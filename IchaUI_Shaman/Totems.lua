-- IchaUI Shaman totem bar (Turtle / RavenCraft 1.12, Lua 5.0-safe)

local GOLD = { 0.78, 0.58, 0.16, 1 }
-- Circle clip: custom square mask (totemmask) + built-in Minimap ring (always circular).
-- Empty slot: quest skull TGA (same extensionless style as working PVP icons).
local ROUNDMASK = "Interface/AddOns/IchaUI/media/roundmask-circle"
local EMPTY_TOTEM = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
-- Built-in circular frame (Vanilla minimap tracking border)
local GOLD_RING = "Interface/Minimap/MiniMap-TrackingBorder"
local DEFAULT_SIZE = 36
local DEFAULT_GAP = 6
local DEFAULT_SCALE = 1.25
local DEFAULT_TEXT = 11
local DEFAULT_DRAWER_SIZE = 34
local DEFAULT_DRAWER_GAP = 2
local DRAWER_CLOSE_DELAY = 0.35
local THROW_STAGGER = 0.10 -- Turtle: totem schools share no GCD; tiny gap for the client
local BORDER_OUTSET = 0
local ICON_INSET_FRAC = 0.22 -- icon ~56% of button, inside TrackingBorder hole
local SEARING_CAST_FALLBACK = 2.2 -- Searing Bolt cast time (Turtle)
local SEARING_CYCLE = 2.2 -- continuous re-cast; no idle gap

-- Improved Fire Totems (2 ranks): Fire Nova -1s delay/rank; Searing +10% attack speed/rank.
-- Magma threat is not a timer (ignored).
local impFireTotemsRank = 0
local impFireScanAt = 0

local function scanImprovedFireTotems()
    impFireTotemsRank = 0
    if type(GetNumTalentTabs) ~= "function" or type(GetTalentInfo) ~= "function" then
        return 0
    end
    local tabs = GetNumTalentTabs() or 0
    local t
    for t = 1, tabs do
        local n = GetNumTalents and (GetNumTalents(t) or 0) or 0
        local i
        for i = 1, n do
            local name, _, _, _, rank = GetTalentInfo(t, i)
            if name then
                local l = string.lower(name)
                -- "Improved Fire Totems" (enUS); loose match for locales
                if string.find(l, "fire totem", 1, true)
                    and (string.find(l, "improv", 1, true) or string.find(l, "verbess", 1, true)
                        or string.find(l, "améli", 1, true) or string.find(l, "mejor", 1, true)) then
                    impFireTotemsRank = tonumber(rank) or 0
                    impFireScanAt = GetTime and GetTime() or 0
                    return impFireTotemsRank
                end
            end
        end
    end
    impFireScanAt = GetTime and GetTime() or 0
    return 0
end

local function ensureImpFireTotems()
    local now = GetTime and GetTime() or 0
    if impFireScanAt == 0 or (now - impFireScanAt) > 5 then
        scanImprovedFireTotems()
    end
end

-- Base 2.2s; Imp Fire Totems +10%/+20% attack speed → interval / 1.10 / 1.20
local function searingCastLength()
    ensureImpFireTotems()
    local base = SEARING_CAST_FALLBACK
    local r = impFireTotemsRank or 0
    if r < 0 then r = 0 end
    if r > 2 then r = 2 end
    if r <= 0 then
        return base
    end
    return base / (1 + 0.10 * r)
end

local function searingCycleLength()
    -- Continuous re-cast: cycle == cast length after talent
    return searingCastLength()
end


-- UI order left→right
local ELEMENTS = { "earth", "fire", "water", "air" }
local ELEMENT_LABEL = {
    earth = "Earth",
    fire = "Fire",
    water = "Water",
    air = "Air",
}

-- Classic GetTotemInfo slot: 1=Fire, 2=Earth, 3=Water, 4=Air
local CLASSIC_SLOT = {
    fire = 1,
    earth = 2,
    water = 3,
    air = 4,
}

-- Catalog: base names (rank-agnostic match via string.find)
local CATALOG = {
    earth = {
        "Stoneskin Totem",
        "Earthbind Totem",
        "Stoneclaw Totem",
        "Strength of Earth Totem",
        "Tremor Totem",
    },
    fire = {
        "Searing Totem",
        "Fire Nova Totem",
        "Magma Totem",
        "Frost Resistance Totem",
        "Flametongue Totem",
    },
    water = {
        "Healing Stream Totem",
        "Mana Spring Totem",
        "Poison Cleansing Totem",
        "Disease Cleansing Totem",
        "Fire Resistance Totem",
        "Mana Tide Totem",
    },
    air = {
        "Windfury Totem",
        "Grounding Totem",
        "Grace of Air Totem",
        "Windwall Totem",
        "Nature Resistance Totem",
        "Tranquil Air Totem",
        "Sentry Totem",
    },
}

-- Approximate vanilla durations (seconds)
local DURATION = {
    ["Stoneskin Totem"] = 120,
    ["Earthbind Totem"] = 45,
    ["Stoneclaw Totem"] = 15,
    ["Strength of Earth Totem"] = 120,
    ["Tremor Totem"] = 120,
    ["Searing Totem"] = 55,
    ["Fire Nova Totem"] = 5,
    ["Magma Totem"] = 20,
    ["Frost Resistance Totem"] = 120,
    ["Flametongue Totem"] = 120,
    ["Healing Stream Totem"] = 60,
    ["Mana Spring Totem"] = 60,
    ["Poison Cleansing Totem"] = 120,
    ["Disease Cleansing Totem"] = 120,
    ["Fire Resistance Totem"] = 120,
    ["Mana Tide Totem"] = 12,
    ["Windfury Totem"] = 120,
    ["Grounding Totem"] = 45,
    ["Grace of Air Totem"] = 120,
    ["Windwall Totem"] = 120,
    ["Nature Resistance Totem"] = 120,
    ["Tranquil Air Totem"] = 120,
    ["Sentry Totem"] = 300,
}

-- Pulse periods (Magma / Mana Spring ticks + cleansing / tremor)
local PERIOD = {
    ["Tremor Totem"] = 4, -- Turtle: 4s pulse (was 5; felt +1s long)
    ["Poison Cleansing Totem"] = 5,
    ["Disease Cleansing Totem"] = 5,
    ["Magma Totem"] = 2,
    ["Mana Spring Totem"] = 2, -- Turtle mana spring tick
    ["Healing Stream Totem"] = 2, -- heal tick pulse
}

-- Fire totems that show a cast bar only while actually casting
local FIRE_CAST_TOTEMS = {
    ["Searing Totem"] = true,
    -- Magma is a 2s pulse tick (PERIOD), not a bolt cast bar
}

-- Fire Nova detonates at ~4s untalented; buff lifetime is often 5s.
-- Imp Fire Totems: -1s delay per rank (rank 2 → 2s fuse).
local FIRE_NOVA_FUSE = 4

-- Full-lifetime fuse ring (fills until totem expires / Fire Nova detonates)
local FIRE_LIFETIME_RING = {
    ["Fire Nova Totem"] = true,
}

-- Totems that do NOT put a lasting buff on the player (position/GUID only)
local GROUND_ONLY = {
    ["Searing Totem"] = true,
    ["Magma Totem"] = true,
    ["Fire Nova Totem"] = true,
    ["Stoneclaw Totem"] = true,
    ["Earthbind Totem"] = true,
    ["Grounding Totem"] = true,
    ["Sentry Totem"] = true,
    ["Poison Cleansing Totem"] = true,
    ["Disease Cleansing Totem"] = true,
    ["Tremor Totem"] = true,
}

-- Fallback icons when spellbook texture unavailable
local ICONS = {
    ["Stoneskin Totem"] = "Interface\\Icons\\Spell_Nature_StoneSkinTotem",
    ["Earthbind Totem"] = "Interface\\Icons\\Spell_Nature_StrengthOfEarthTotem02",
    ["Stoneclaw Totem"] = "Interface\\Icons\\Spell_Nature_StoneClawTotem",
    ["Strength of Earth Totem"] = "Interface\\Icons\\Spell_Nature_EarthBindTotem",
    ["Tremor Totem"] = "Interface\\Icons\\Spell_Nature_TremorTotem",
    ["Searing Totem"] = "Interface\\Icons\\Spell_Fire_SearingTotem",
    ["Fire Nova Totem"] = "Interface\\Icons\\Spell_Fire_SealOfFire",
    ["Magma Totem"] = "Interface\\Icons\\Spell_Fire_SelfDestruct",
    ["Frost Resistance Totem"] = "Interface\\Icons\\Spell_FrostResistanceTotem_01",
    ["Flametongue Totem"] = "Interface\\Icons\\Spell_Nature_GuardianWard",
    ["Healing Stream Totem"] = "Interface\\Icons\\INV_Spear_04",
    ["Mana Spring Totem"] = "Interface\\Icons\\Spell_Nature_ManaRegenTotem",
    ["Poison Cleansing Totem"] = "Interface\\Icons\\Spell_Nature_PoisonCleansingTotem",
    ["Disease Cleansing Totem"] = "Interface\\Icons\\Spell_Nature_DiseaseCleansingTotem",
    ["Fire Resistance Totem"] = "Interface\\Icons\\Spell_FireResistanceTotem_01",
    ["Mana Tide Totem"] = "Interface\\Icons\\Spell_Frost_SummonWaterElemental",
    ["Windfury Totem"] = "Interface\\Icons\\Spell_Nature_Windfury",
    ["Grounding Totem"] = "Interface\\Icons\\Spell_Nature_GroundingTotem",
    ["Grace of Air Totem"] = "Interface\\Icons\\Spell_Nature_InvisibilityTotem",
    ["Windwall Totem"] = "Interface\\Icons\\Spell_Nature_EarthBind",
    ["Nature Resistance Totem"] = "Interface\\Icons\\Spell_Nature_NatureResistanceTotem",
    ["Tranquil Air Totem"] = "Interface\\Icons\\Spell_Nature_Brilliance",
    ["Sentry Totem"] = "Interface\\Icons\\Spell_Nature_RemoveCurse",
}

-- Empty / "no totem" placeholder — skull TGA for all elements
local EMPTY_ICONS = {
    earth = EMPTY_TOTEM,
    fire  = EMPTY_TOTEM,
    water = EMPTY_TOTEM,
    air   = EMPTY_TOTEM,
}

-- Keybind header / name (1.12 Bindings.xml)
BINDING_HEADER_ICHA = "IchaUI"
BINDING_NAME_ICHA_THROWTOTEMS = "Throw Current Totem Set"
BINDING_NAME_ICHA_TOTEMSETNEXT = "Next Totem Set"
BINDING_NAME_ICHA_TOTEMBIND_EARTH = "Totem Slot: Earth"
BINDING_NAME_ICHA_TOTEMBIND_FIRE = "Totem Slot: Fire"
BINDING_NAME_ICHA_TOTEMBIND_WATER = "Totem Slot: Water"
BINDING_NAME_ICHA_TOTEMBIND_AIR = "Totem Slot: Air"

-- Flat ordered catalog for ICHA_TOTEMCAST1..23 (drawer spells; keep order)
local TOTEM_BIND_LIST = {
    -- earth 1-5
    { base = "Stoneskin Totem", element = "earth", label = "Stoneskin" },
    { base = "Earthbind Totem", element = "earth", label = "Earthbind" },
    { base = "Stoneclaw Totem", element = "earth", label = "Stoneclaw" },
    { base = "Strength of Earth Totem", element = "earth", label = "Strength of Earth" },
    { base = "Tremor Totem", element = "earth", label = "Tremor" },
    -- fire 6-10
    { base = "Searing Totem", element = "fire", label = "Searing" },
    { base = "Fire Nova Totem", element = "fire", label = "Fire Nova" },
    { base = "Magma Totem", element = "fire", label = "Magma" },
    { base = "Frost Resistance Totem", element = "fire", label = "Frost Resistance" },
    { base = "Flametongue Totem", element = "fire", label = "Flametongue" },
    -- water 11-16
    { base = "Healing Stream Totem", element = "water", label = "Healing Stream" },
    { base = "Mana Spring Totem", element = "water", label = "Mana Spring" },
    { base = "Poison Cleansing Totem", element = "water", label = "Poison Cleansing" },
    { base = "Disease Cleansing Totem", element = "water", label = "Disease Cleansing" },
    { base = "Fire Resistance Totem", element = "water", label = "Fire Resistance" },
    { base = "Mana Tide Totem", element = "water", label = "Mana Tide" },
    -- air 17-23
    { base = "Windfury Totem", element = "air", label = "Windfury" },
    { base = "Grounding Totem", element = "air", label = "Grounding" },
    { base = "Grace of Air Totem", element = "air", label = "Grace of Air" },
    { base = "Windwall Totem", element = "air", label = "Windwall" },
    { base = "Nature Resistance Totem", element = "air", label = "Nature Resistance" },
    { base = "Tranquil Air Totem", element = "air", label = "Tranquil Air" },
    { base = "Sentry Totem", element = "air", label = "Sentry" },
}
do
    local i
    for i = 1, table.getn(TOTEM_BIND_LIST) do
        local e = TOTEM_BIND_LIST[i]
        setglobal("BINDING_NAME_ICHA_TOTEMCAST" .. i, "Totem: " .. (e.label or e.base))
    end
    for i = 1, 10 do
        setglobal("BINDING_NAME_ICHA_THROWTOTEMSET" .. i, "Throw Totem Set " .. i)
    end
end

local cfgScale, cfgSize, cfgGap, cfgText = DEFAULT_SCALE, DEFAULT_SIZE, DEFAULT_GAP, DEFAULT_TEXT
local cfgDrawerSize, cfgDrawerGap = DEFAULT_DRAWER_SIZE, DEFAULT_DRAWER_GAP
local DEFAULT_CD_BADGE_SCALE = 0.85
local cfgCdBadgeScale = DEFAULT_CD_BADGE_SCALE
-- Extra Y lift (px) so CD badges sit above cast/tick text when that text is visible
local CD_BADGE_CAST_LIFT = 14
local CD_BADGE_POOL_MAX = 4
local CD_BADGE_GAP = 2
local cfgShiftDrawer = false
local moving = false
local root, mover
local slots = {} -- element → slot frame
local drawers = {} -- element → drawer frame
local pinned = {} -- element → bool
local closeAt = {} -- element → GetTime when hover-close fires
local knownCache = {} -- baseName → { name=full, rank=, index=, texture= }
local knownScanAt = 0
local live = {} -- element → { name=, start=, duration=, icon= }
local liveCast = {} -- element → { start=, finish=, name= } (actual cast only)
local TOTEM_KEEP_RANGE = 30 -- Turtle patched totem aura range
local TOTEM_CHAT = false -- set true to re-enable throw / select spam
local function totemChat(msg)
    if TOTEM_CHAT and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
end
local liveGuid = {} -- element → SuperWoW GUID string when known
local lastCastBase = {} -- element → last cast catalog base
local spellCdFallback = {} -- element → { start=, duration=, base= }


local throwQueue = {}
local pendingRecall = false -- { index=, name=, base= }
local suppressLiveUntil = 0 -- after recall: block GetTotemInfo from re-showing timers
local throwNext = 0
local throwTotal = 0
local throwDone = 0
local throwBusy = false
local isShaman = false

-- Forward decls so call sites never hit a nil global
local emptyIcon, iconFor, applyGoldRing, insetIcon, applySlotVisuals, buildDrawerRows, noteSpellCd

local function db()
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.totems then IchaUIDB.totems = {} end
    local d = IchaUIDB.totems
    if not d.active then d.active = {} end
    if d.textStrata == nil or d.textStrata == "" then
        d.textStrata = "MEDIUM"
    elseif type(IchaUI_StrataFromValue) == "function" then
        local n = IchaUI_StrataFromValue(d.textStrata, 4)
        if n and n ~= "" then d.textStrata = n end
    end
    -- Default Up matches the original slot-top stack; missing/invalid must not flip layouts
    if d.drawerDir ~= "down" and d.drawerDir ~= "left" and d.drawerDir ~= "right" and d.drawerDir ~= "radial" then
        d.drawerDir = "up"
    end
    return d
end

-- Nested locals: column-0 helpers here overflow Lua 5.0's 200-local main chunk.
function IchaUI_ApplyTotemStrata()
    local function norm(v, defName, defIdx)
        if type(IchaUI_StrataFromValue) == "function" then
            local n = IchaUI_StrataFromValue(v, defIdx)
            if n and n ~= "" then return n end
        end
        if type(v) == "number" then
            if v == 1 then return "BACKGROUND" end
            if v == 2 then return "LOW" end
            if v == 3 then return "MEDIUM" end
            if v == 4 then return "HIGH" end
            if v == 5 then return "DIALOG" end
            return defName
        end
        if type(v) == "string" and v ~= "" then
            local u = string.upper(v)
            if u == "BACKGROUND" or u == "LOW" or u == "MEDIUM" or u == "HIGH" or u == "DIALOG" then
                return u
            end
            if u == "TOOLTIP" then return "DIALOG" end
        end
        return defName
    end
    local function iconName()
        if type(IchaUI_GetIconStrata) == "function" then
            return norm(IchaUI_GetIconStrata(), "MEDIUM", 3)
        end
        return "MEDIUM"
    end
    local iname = iconName()
    if IchaUI_DrawerStyleGet then
        local savedStrata = IchaUI_DrawerStyleGet("totems")
        if savedStrata and savedStrata ~= "" then iname = savedStrata end
    end
    if not iname or iname == "" then iname = "MEDIUM" end
    if root then
        pcall(function()
            root:SetFrameStrata(iname)
        end)
    end
    local i
    for i = 1, table.getn(ELEMENTS) do
        local el = ELEMENTS[i]
        local slot = slots[el]
        if slot and slot.timerFrame then
            pcall(function()
                slot.timerFrame:SetFrameStrata(iname)
                slot.timerFrame:SetFrameLevel((slot:GetFrameLevel() or 1) + 20)
            end)
        end
        if slot and slot.cdBadges then
            local bi
            for bi = 1, table.getn(slot.cdBadges) do
                local b = slot.cdBadges[bi]
                if b then
                    pcall(function()
                        b:SetFrameStrata(iname)
                        b:SetFrameLevel((slot:GetFrameLevel() or 1) + 24)
                    end)
                end
            end
        end
        if slot and slot.cdBadge and slot.cdBadge.SetFrameStrata then
            pcall(function()
                slot.cdBadge:SetFrameStrata(iname)
                slot.cdBadge:SetFrameLevel((slot:GetFrameLevel() or 1) + 24)
            end)
        end
        local dr = drawers[el]
        if dr then
            local open = false
            if dr.IsShown then
                open = dr:IsShown() and true or false
            end
            local dname = iname
            local fl = 10
            if open then
                if type(IchaUI_DrawerOpenStrata) == "function" then
                    dname = norm(IchaUI_DrawerOpenStrata(), "HIGH", 4)
                elseif iname == "BACKGROUND" then
                    dname = "LOW"
                elseif iname == "LOW" then
                    dname = "MEDIUM"
                elseif iname == "MEDIUM" then
                    dname = "HIGH"
                else
                    dname = "DIALOG"
                end
                fl = 40
            end
            if not dname or dname == "" then dname = "MEDIUM" end
            pcall(function()
                dr:SetFrameStrata(dname)
                dr:SetFrameLevel(fl)
            end)
            if dr.rows then
                local ri
                for ri = 1, table.getn(dr.rows) do
                    local row = dr.rows[ri]
                    if row then
                        pcall(function()
                            row:SetFrameLevel(fl + 4)
                        end)
                    end
                end
            end
        end
    end
    if mover and mover.SetFrameStrata then
        pcall(function()
            mover:SetFrameStrata(iname)
            local base = 1
            if root and root.GetFrameLevel then base = root:GetFrameLevel() or 1 end
            mover:SetFrameLevel(base + 40)
        end)
    end
end

local DEFAULT_THROW_KEY = "T"
local throwMouseKey = nil

local function isButtonMouseKey(key)
    if not key then return false end
    return string.find(string.upper(key), "BUTTON%d") and true or false
end
local function isWheelKey(key)
    if not key then return false end
    return string.find(string.upper(key), "MOUSEWHEEL", 1, true) and true or false
end
-- Chord registry (BUTTON + wheel). SetBinding skipped only for BUTTON*.
local function isThrowMouseKey(key)
    return isButtonMouseKey(key) or isWheelKey(key)
end

local function clearThrowCmdKeys(cmd)
    if not GetBindingKey then return end
    local k1, k2 = GetBindingKey(cmd)
    if k1 and k1 ~= "" then SetBinding(k1) end
    if k2 and k2 ~= "" then SetBinding(k2) end
end

local function saveThrowBindSet()
    if SaveBindings and GetCurrentBindingSet then
        SaveBindings(GetCurrentBindingSet())
    elseif SaveBindings then
        SaveBindings(1)
    end
end

local function setThrowMouseChord(key)
    IchaUI_MouseChordActions = IchaUI_MouseChordActions or {}
    if throwMouseKey and IchaUI_MouseChordActions[throwMouseKey] then
        IchaUI_MouseChordActions[throwMouseKey] = nil
    end
    throwMouseKey = nil
    if key and isThrowMouseKey(key) then
        local chord = string.upper(key)
        throwMouseKey = chord
        IchaUI_MouseChordActions[chord] = function()
            if IchaUITotems_ThrowSet then IchaUITotems_ThrowSet() end
        end
    end
end

function IchaUITotems_GetThrowKey()
    local d = db()
    if GetBindingKey then
        local live = GetBindingKey("ICHA_THROWTOTEMS")
        if live and live ~= "" then
            d.throwKey = live
            return live
        end
    end
    return d.throwKey or DEFAULT_THROW_KEY
end

function IchaUITotems_SetThrowKey(key)
    local d = db()
    if not key or key == "" then key = DEFAULT_THROW_KEY end
    key = string.upper(key)
    d.throwKey = key
    clearThrowCmdKeys("ICHA_THROWTOTEMS")
    if (not isButtonMouseKey(key)) and SetBinding then
        SetBinding(key, "ICHA_THROWTOTEMS")
    end
    saveThrowBindSet()
    setThrowMouseChord(key)
    return key
end

local function applyThrowBinding()
    local d = db()
    if GetBindingKey then
        local live = GetBindingKey("ICHA_THROWTOTEMS")
        if live and live ~= "" then
            d.throwKey = live
            setThrowMouseChord(live)
            return
        end
    end
    IchaUITotems_SetThrowKey(d.throwKey or DEFAULT_THROW_KEY)
end

-- Per-element slot keybinds (cast getActive for that slot)
local SLOT_BIND_CMD = {
    earth = "ICHA_TOTEMBIND_EARTH",
    fire = "ICHA_TOTEMBIND_FIRE",
    water = "ICHA_TOTEMBIND_WATER",
    air = "ICHA_TOTEMBIND_AIR",
}
local slotMouseKeys = {} -- element → chord string currently registered

local function ensureSlotBindsDB()
    local d = db()
    if not d.slotBinds then d.slotBinds = {} end
    local i
    for i = 1, table.getn(ELEMENTS) do
        local el = ELEMENTS[i]
        if d.slotBinds[el] == nil then
            d.slotBinds[el] = ""
        end
    end
    return d.slotBinds
end

local function resolveSlotElement(elOrIdx)
    if type(elOrIdx) == "number" then
        local el = ELEMENTS[elOrIdx]
        return el
    end
    if not elOrIdx then return nil end
    local s = string.lower(tostring(elOrIdx))
    local i
    for i = 1, table.getn(ELEMENTS) do
        if ELEMENTS[i] == s then return ELEMENTS[i] end
    end
    -- Allow "1".."4" as strings
    local n = tonumber(s)
    if n then return ELEMENTS[n] end
    return nil
end

local function clearSlotMouseChord(el)
    local old = slotMouseKeys[el]
    if old and IchaUI_MouseChordActions then
        IchaUI_MouseChordActions[old] = nil
    end
    slotMouseKeys[el] = nil
end

local function setSlotMouseChord(el, key)
    clearSlotMouseChord(el)
    if key and key ~= "" and isThrowMouseKey(key) then
        local chord = string.upper(key)
        slotMouseKeys[el] = chord
        IchaUI_MouseChordActions = IchaUI_MouseChordActions or {}
        local element = el
        IchaUI_MouseChordActions[chord] = function()
            if IchaUITotems_SlotBindFire then IchaUITotems_SlotBindFire(element) end
        end
    end
end

function IchaUITotems_GetSlotKey(elOrIdx)
    local el = resolveSlotElement(elOrIdx)
    if not el then return "" end
    local sb = ensureSlotBindsDB()
    local cmd = SLOT_BIND_CMD[el]
    if cmd and GetBindingKey then
        local live = GetBindingKey(cmd)
        if live and live ~= "" then
            sb[el] = live
            return live
        end
    end
    local k = sb[el]
    if k and k ~= "" then return k end
    return ""
end

function IchaUITotems_ApplySlotKey(elOrIdx, key)
    local el = resolveSlotElement(elOrIdx)
    if not el then return "" end
    local sb = ensureSlotBindsDB()
    if not key then key = "" end
    key = string.gsub(key, "^%s+", "")
    key = string.gsub(key, "%s+$", "")
    if key ~= "" then
        key = string.upper(key)
    end
    sb[el] = key
    local cmd = SLOT_BIND_CMD[el]
    if cmd then
        clearThrowCmdKeys(cmd)
        if key ~= "" and (not isButtonMouseKey(key)) and SetBinding then
            SetBinding(key, cmd)
        end
    end
    saveThrowBindSet()
    setSlotMouseChord(el, key)
    return key
end

local function applySlotBindings()
    ensureSlotBindsDB()
    local i
    for i = 1, table.getn(ELEMENTS) do
        local el = ELEMENTS[i]
        local key = IchaUITotems_GetSlotKey(el)
        -- Re-apply so mouse chords / SetBinding stick across login
        IchaUITotems_ApplySlotKey(el, key or "")
    end
end

-- Per-catalog-totem spell keybinds (ICHA_TOTEMCAST1..23)
local spellMouseKeys = {} -- base → chord string currently registered

local function ensureSpellBindsDB()
    local d = db()
    if not d.spellBinds then d.spellBinds = {} end
    local i
    for i = 1, table.getn(TOTEM_BIND_LIST) do
        local base = TOTEM_BIND_LIST[i].base
        if d.spellBinds[base] == nil then
            d.spellBinds[base] = ""
        end
    end
    return d.spellBinds
end

local function spellBindCmd(idx)
    if not idx then return nil end
    return "ICHA_TOTEMCAST" .. tostring(idx)
end

local function resolveSpellBind(baseOrIdx)
    if type(baseOrIdx) == "number" then
        return TOTEM_BIND_LIST[baseOrIdx], baseOrIdx
    end
    if not baseOrIdx then return nil, nil end
    local s = tostring(baseOrIdx)
    local n = tonumber(s)
    if n and TOTEM_BIND_LIST[n] then
        return TOTEM_BIND_LIST[n], n
    end
    local i
    for i = 1, table.getn(TOTEM_BIND_LIST) do
        local e = TOTEM_BIND_LIST[i]
        if e.base == s or e.label == s then
            return e, i
        end
    end
    return nil, nil
end

local function clearSpellMouseChord(base)
    local old = spellMouseKeys[base]
    if old and IchaUI_MouseChordActions then
        IchaUI_MouseChordActions[old] = nil
    end
    spellMouseKeys[base] = nil
end

local function setSpellMouseChord(idx, base, key)
    clearSpellMouseChord(base)
    if key and key ~= "" and isThrowMouseKey(key) then
        local chord = string.upper(key)
        spellMouseKeys[base] = chord
        IchaUI_MouseChordActions = IchaUI_MouseChordActions or {}
        local n = idx
        IchaUI_MouseChordActions[chord] = function()
            if IchaUITotems_SpellBindFire then IchaUITotems_SpellBindFire(n) end
        end
    end
end

function IchaUITotems_ListSpellBinds()
    ensureSpellBindsDB()
    local out = {}
    local i
    for i = 1, table.getn(TOTEM_BIND_LIST) do
        local e = TOTEM_BIND_LIST[i]
        local key = IchaUITotems_GetSpellKey(i)
        table.insert(out, {
            index = i,
            base = e.base,
            element = e.element,
            key = key or "",
            label = e.label,
        })
    end
    return out
end

function IchaUITotems_GetSpellKey(baseOrIdx)
    local e, idx = resolveSpellBind(baseOrIdx)
    if not e then return "" end
    local sb = ensureSpellBindsDB()
    local cmd = spellBindCmd(idx)
    if cmd and GetBindingKey then
        local live = GetBindingKey(cmd)
        if live and live ~= "" then
            sb[e.base] = live
            return live
        end
    end
    local k = sb[e.base]
    if k and k ~= "" then return k end
    return ""
end

function IchaUITotems_ApplySpellKey(baseOrIdx, key)
    local e, idx = resolveSpellBind(baseOrIdx)
    if not e then return "" end
    local sb = ensureSpellBindsDB()
    if not key then key = "" end
    key = string.gsub(key, "^%s+", "")
    key = string.gsub(key, "%s+$", "")
    if key ~= "" then
        key = string.upper(key)
    end
    sb[e.base] = key
    local cmd = spellBindCmd(idx)
    if cmd then
        clearThrowCmdKeys(cmd)
        if key ~= "" and (not isButtonMouseKey(key)) and SetBinding then
            SetBinding(key, cmd)
        end
    end
    saveThrowBindSet()
    setSpellMouseChord(idx, e.base, key)
    return key
end

local function applySpellBindings()
    ensureSpellBindsDB()
    local i
    for i = 1, table.getn(TOTEM_BIND_LIST) do
        local key = IchaUITotems_GetSpellKey(i)
        IchaUITotems_ApplySpellKey(i, key or "")
    end
end


local function isPlayerShaman()
    local c = UnitClass and UnitClass("player")
    if not c then return false end
    if c == "Shaman" or c == "Schamane" or c == "Chaman" or c == "Chamán" or c == "Sciamano" then
        return true
    end
    local _, token = UnitClass("player")
    if token == "SHAMAN" then return true end
    return false
end

local function baseName(full)
    if not full then return nil end
    local b = string.gsub(full, "%s*%(.*%)%s*$", "")
    b = string.gsub(b, "%s+[Rr]ank%s+%d+%s*$", "")
    return b
end

local function matchCatalog(full, element)
    local list = CATALOG[element]
    if not list or not full then return nil end
    local n = table.getn(list)
    local i
    for i = 1, n do
        local cat = list[i]
        if full == cat or string.find(full, cat, 1, true) then
            return cat
        end
    end
    return nil
end

local function scanSpellbook()
    knownCache = {}
    IchaUITotems_RecallSpell = nil
    local book = BOOKTYPE_SPELL or "spell"
    local i = 1
    while true do
        local name, rank = GetSpellName(i, book)
        if not name then break end
        local ei
        for ei = 1, table.getn(ELEMENTS) do
            local e = ELEMENTS[ei]
            local cat = matchCatalog(name, e)
            if cat then
                local tex = nil
                if GetSpellTexture then
                    tex = GetSpellTexture(i, book)
                end
                knownCache[cat] = {
                    name = name,
                    rank = rank,
                    index = i,
                    texture = tex,
                    element = e,
                    base = cat,
                }
            end
        end
        do
            local l = string.lower(tostring(name))
            if string.find(l, "recall", 1, true) and string.find(l, "totem", 1, true) then
                local tex = nil
                if GetSpellTexture then
                    tex = GetSpellTexture(i, book)
                end
                IchaUITotems_RecallSpell = { name = name, rank = rank, index = i, texture = tex }
            end
        end
        i = i + 1
        if i > 500 then break end
    end
    knownScanAt = GetTime and GetTime() or 0
end

local function ensureKnown()
    local now = GetTime and GetTime() or 0
    if knownScanAt == 0 or (now - knownScanAt) > 5 then
        scanSpellbook()
    end
end

function iconFor(base)
    local k = knownCache[base]
    if k and k.texture then return k.texture end
    return ICONS[base] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function emptyIcon(element)
    -- Built-in skull (custom TGA refused to load on this client)
    return EMPTY_TOTEM
end

local function durationFor(base)
    return DURATION[base] or 120
end

local function periodFor(base)
    return PERIOD[base]
end

-- Effective fuse / display life for ring + center countdown
local function fuseFor(base, dur)
    if base == "Fire Nova Totem" then
        ensureImpFireTotems()
        local r = impFireTotemsRank or 0
        if r < 0 then r = 0 end
        if r > 2 then r = 2 end
        local fuse = FIRE_NOVA_FUSE - r
        if fuse < 1 then fuse = 1 end
        return fuse
    end
    return dur or durationFor(base) or 120
end

local function formatTime(sec)
    if not sec or sec <= 0 then return "" end
    if sec >= 60 then
        return string.format("%d:%02d", math.floor(sec / 60), math.floor(math.mod(sec, 60)))
    end
    -- Whole seconds left via floor (not round): a 5s Fire Nova was showing
    -- 5 4 3 2 1 0 because %.0f rounded up half-seconds, and "0" hung after the nova.
    local n = math.floor(sec)
    if n < 1 then return "" end
    return tostring(n)
end

-- math.mod for Lua 5.0 / 5.1 compat
if not math.mod then
    math.mod = function(a, b)
        return a - math.floor(a / b) * b
    end
end

-- Classic minimap-button ring: opaque corners crop the square icon underneath.
-- Button is `size`x`size`; TrackingBorder is ~1.65x and anchored TOPLEFT (no rest nudge).
function applyGoldRing(ringTex, parent, size)
    if not ringTex or not parent then return end
    local s = size or parent:GetWidth() or cfgSize or 36
    if s < 16 then s = 16 end
    local bw = math.floor(s * 1.65 + 0.5)
    ringTex:SetTexture(GOLD_RING)
    ringTex:SetBlendMode("BLEND")
    IchaUI_PaintGoldRing(ringTex)
    ringTex:ClearAllPoints()
    ringTex:SetWidth(bw)
    ringTex:SetHeight(bw)
    -- Vanilla minimap buttons: border TOPLEFT of button, icon centered smaller inside
    ringTex:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    ringTex:Show()
end

-- Kept name for call sites that still pass a Frame; no-op square tooltip border
local function applyGoldBorder(borderFrame, parent)
    if borderFrame then
        borderFrame:SetBackdrop(nil)
        borderFrame:Hide()
    end
end

function insetIcon(tex, parent, size)
    if not tex or not parent then return end
    local s = size or parent:GetWidth() or cfgSize or 36
    -- Keep icon inside the circular hole (~56% of button)
    local iconSz = math.floor(s * (1 - 2 * ICON_INSET_FRAC) + 0.5)
    if iconSz < 10 then iconSz = 10 end
    tex:ClearAllPoints()
    tex:SetWidth(iconSz)
    tex:SetHeight(iconSz)
    -- Rest: 0, +2 (between prior -2 and +2 X; hole sits slightly up). Pressed: +1,-1 vs rest.
    local ox, oy = 0, 2
    if parent._pushed then ox, oy = 1, 1 end
    tex:SetPoint("CENTER", parent, "CENTER", ox, oy)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if parent.roundMask then
        parent.roundMask:SetTexture(ROUNDMASK)
        parent.roundMask:SetVertexColor(0, 0, 0, 1)
        parent.roundMask:ClearAllPoints()
        parent.roundMask:SetPoint("TOPLEFT", tex, "TOPLEFT", 0, 0)
        parent.roundMask:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 0, 0)
        parent.roundMask:Show()
    end
    -- Alpha disc (transparent corners) under the icon, same size as the icon hole.
    if parent.circleBg then
        parent.circleBg:SetTexture("Interface\\AddOns\\IchaUI\\media\\circledisc.tga")
        parent.circleBg:SetVertexColor(0.05, 0.05, 0.06, 1)
        parent.circleBg:ClearAllPoints()
        parent.circleBg:SetPoint("TOPLEFT", tex, "TOPLEFT", 0, 0)
        parent.circleBg:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 0, 0)
        parent.circleBg:Show()
        if parent.circleMask then parent.circleMask:Hide() end
    end
end

-- Match Layout.lua action-bar pressed look (nudge + dim + dark overlay)
local function pushCircleSlot(slot)
    if not slot or slot._pushed then return end
    slot._pushed = true
    if slot.icon and IchaUI_FormPress and IchaUI_FormPress(slot, true) then
        slot.icon:SetVertexColor(0.82, 0.82, 0.82)
    elseif slot.icon then
        insetIcon(slot.icon, slot, slot:GetWidth())
        slot.icon:SetVertexColor(0.82, 0.82, 0.82)
        if slot.roundMask then
            slot.roundMask:ClearAllPoints()
            slot.roundMask:SetPoint("TOPLEFT", slot.icon, "TOPLEFT", 0, 0)
            slot.roundMask:SetPoint("BOTTOMRIGHT", slot.icon, "BOTTOMRIGHT", 0, 0)
            slot.roundMask:Show()
        end
    end
    if slot.pushTex then
        if not (IchaUI_FormOverlay and IchaUI_FormOverlay(slot, slot.pushTex, "shade")) then
            slot.pushTex:ClearAllPoints()
            slot.pushTex:SetAllPoints(slot.icon or slot)
        end
        slot.pushTex:SetDrawLayer("OVERLAY", 7)
        slot.pushTex:SetAlpha(0.18)
        slot.pushTex:Show()
    end
end

local function releaseCircleSlot(slot)
    if not slot or not slot._pushed then return end
    slot._pushed = false
    if slot.icon and IchaUI_FormPress and IchaUI_FormPress(slot, false) then
        slot.icon:SetVertexColor(1, 1, 1)
    elseif slot.icon then
        insetIcon(slot.icon, slot, slot:GetWidth())
        slot.icon:SetVertexColor(1, 1, 1)
        if slot.roundMask then
            slot.roundMask:ClearAllPoints()
            slot.roundMask:SetPoint("TOPLEFT", slot.icon, "TOPLEFT", 0, 0)
            slot.roundMask:SetPoint("BOTTOMRIGHT", slot.icon, "BOTTOMRIGHT", 0, 0)
            slot.roundMask:Show()
        end
    end
    if slot.pushTex then
        slot.pushTex:Hide()
        slot.pushTex:SetAlpha(0.18)
    end
end

-- Keybind press: same look as click, auto-release like hero PUSH_MS
local PUSH_MS = 0.12

local function bindPush(slot)
    if not slot then return end
    pushCircleSlot(slot)
    slot._bindPushUntil = (GetTime and GetTime() or 0) + PUSH_MS
end

local function tickBindPushes(now)
    local i
    for i = 1, table.getn(ELEMENTS) do
        local el = ELEMENTS[i]
        local slot = slots[el]
        if slot and slot._bindPushUntil and now >= slot._bindPushUntil then
            slot._bindPushUntil = nil
            releaseCircleSlot(slot)
        end
        local dr = drawers[el]
        if dr and dr.rows then
            local r
            for r = 1, table.getn(dr.rows) do
                local row = dr.rows[r]
                if row and row._bindPushUntil and now >= row._bindPushUntil then
                    row._bindPushUntil = nil
                    releaseCircleSlot(row)
                end
            end
        end
    end
end

-- Thin circular cast/tick progress (NOT Cooldown wipe). Lua 5.0 / 1.12-safe.
-- Round: overlapping opaque discs along the arc. Square: solid edge strips.
-- Spark rotates with tangent so tip sits perpendicular to travel direction.
-- Angle: a = pi/2 - pct*2*pi; ox=cos(a)*r, oy=sin(a)*r (pct=0 at 12 o'clock, clockwise).
local CAST_RING_SEG = 72
local CAST_SPARK_TEX = "Interface\\AddOns\\IchaUI\\media\\TotemCastSpark.tga"
local CAST_SPARK_FALLBACK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local CAST_RING_BG_TEX = "Interface\\AddOns\\IchaUI\\media\\TotemProgressRing.tga"
local CAST_CHIP_TEX = "Interface\\AddOns\\IchaUI\\media\\circledisc.tga"

-- Frame art's visible outer edge, measured from the textures (alpha > 128).
-- Round: { radius, center x, center y } as fractions of the ring texture,
-- center measured from its top-left. circle = the MiniMap-TrackingBorder the
-- client loads (256 px, patch-I.mpq): centered on its gold band, out to the
-- outer bevel band's edge (64/256 px). That band is lit top-left and in
-- shadow bottom-right, so a fit to its lit part sits too high and small.
-- tipLine: UI-Tooltip-Border's gold line starts 3/16 of the edge size in.
-- edgeLine: px from the pfUI border frame's edge to its visible line.
IchaUITotems_CastRim = {
    circle = { 0.2520, 0.2954, 0.2807 },
    tooltip = { 0.4766, 0.5, 0.5 },
    portrait = { 0.4795, 0.4995, 0.4917 },
    metalplain = { 0.3100, 0.5029, 0.5 },
    eternium = { 0.3100, 0.5029, 0.5 },
    bronze = { 0.3086, 0.5, 0.5 },
    wowui = { 0.3178, 0.5, 0.5029 },
    wood = { 0.3086, 0.5, 0.5 },
    target = { 0.4453, 0.5020, 0.5059 },
    tipLine = 3 / 16,
    edgeLine = { pfsquare = 0, pfblizz = 3 },
}

local function castRingColor(base)
    if base == "Searing Totem" or base == "Magma Totem" or base == "Fire Nova Totem" then
        return 1.0, 0.55, 0.12 -- fire
    elseif base == "Poison Cleansing Totem" then
        return 0.25, 0.95, 0.30 -- poison green
    elseif base == "Disease Cleansing Totem" then
        return 1.0, 0.90, 0.20 -- disease yellow
    elseif base == "Mana Spring Totem" or base == "Healing Stream Totem" then
        return 0.30, 0.65, 1.0 -- water
    elseif base == "Tremor Totem" then
        return 0.90, 0.70, 0.28 -- earth
    end
    return 0.55, 0.95, 1.0 -- air
end

-- Rotate a square texture's UVs by angle (radians). Works on 1.12 without SetRotation.
local function setTexRotated(tex, angle)
    if not tex then return end
    if tex.SetRotation then
        pcall(function() tex:SetRotation(angle) end)
        return
    end
    local c = math.cos(angle)
    local s = math.sin(angle)
    local function rot(u, v)
        u = u - 0.5
        v = v - 0.5
        return 0.5 + u * c - v * s, 0.5 + u * s + v * c
    end
    local ulx, uly = rot(0, 0)
    local llx, lly = rot(0, 1)
    local urx, ury = rot(1, 0)
    local lrx, lry = rot(1, 1)
    -- SetTexCoord(ULx, ULy, LLx, LLy, URx, URy, LRx, LRy)
    pcall(function()
        tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
    end)
end

local function killCastCooldown(slot)
    if not slot then return end
    slot.cdStart = nil
    if slot.cd then
        pcall(function()
            if CooldownFrame_SetTimer then
                CooldownFrame_SetTimer(slot.cd, 0, 0, 0)
            end
            slot.cd:Hide()
            if slot.cd.SetAlpha then slot.cd:SetAlpha(0) end
        end)
    end
    if slot.cdMaskFrame then
        pcall(function() slot.cdMaskFrame:Hide() end)
    end
end

local function sizeTotemCd(slot)
    killCastCooldown(slot)
end

local function ensureCastRing(slot)
    if not slot or not slot.icon then return end
    if not slot.castRingFrame then
        local f = CreateFrame("Frame", nil, slot)
        f:SetAllPoints(slot)
        f:SetFrameLevel((slot:GetFrameLevel() or 1) + 20)
        slot.castRingFrame = f
    end
    local parent = slot.castRingFrame

    if not slot.castRingBg then
        local bg = parent:CreateTexture(nil, "ARTWORK")
        bg:SetTexture(CAST_RING_BG_TEX)
        pcall(function() bg:SetBlendMode("ADD") end)
        bg:Hide()
        slot.castRingBg = bg
    end

    if not slot.castSegs then
        slot.castSegs = {}
    end

    if not slot.castSpark then
        local sp = parent:CreateTexture(nil, "OVERLAY")
        sp:SetTexture(CAST_SPARK_TEX)
        pcall(function() sp:SetBlendMode("ADD") end)
        sp:Hide()
        slot.castSpark = sp
    end
end

-- Round stroke dot i: an opaque disc, plain 0..1 texcoords. Rotated UVs
-- tile the texture in game (no clamp), which drew diagonal dashes.
function IchaUITotems_CastDot(slot, i)
    local seg = slot.castSegs[i]
    if not seg then
        seg = slot.castRingFrame:CreateTexture(nil, "OVERLAY")
        seg:Hide()
        slot.castSegs[i] = seg
    end
    seg:SetTexture(CAST_CHIP_TEX)
    seg:SetTexCoord(0, 1, 0, 1)
    pcall(function() seg:SetBlendMode("BLEND") end)
    return seg
end

-- Square stroke strip k (1..5): solid, axis-aligned, no texcoord tricks.
function IchaUITotems_CastStrip(slot, k)
    if not slot.castEdges then slot.castEdges = {} end
    local t = slot.castEdges[k]
    if not t then
        t = slot.castRingFrame:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        t:Hide()
        slot.castEdges[k] = t
    end
    pcall(function() t:SetBlendMode("BLEND") end)
    return t
end

function IchaUITotems_HideCastParts(slot, fromSeg)
    if slot.castRingBg then slot.castRingBg:Hide() end
    if slot.castEdges then
        local ei
        for ei = 1, table.getn(slot.castEdges) do slot.castEdges[ei]:Hide() end
    end
    if slot.castSegs then
        local i
        for i = fromSeg or 1, table.getn(slot.castSegs) do slot.castSegs[i]:Hide() end
    end
end

local function layoutCastRing(slot)
    if not slot or not slot.icon then return end
    ensureCastRing(slot)
    if slot.castRingFrame then
        slot.castRingFrame:SetFrameLevel((slot:GetFrameLevel() or 1) + 20)
        if slot.timerFrame and IchaUI_ApplyTotemStrata then IchaUI_ApplyTotemStrata() end
        slot.castRingFrame:Show()
    end
    local iw = slot.icon:GetWidth() or 0
    if iw < 8 then
        iw = (cfgSize or 36) * (cfgScale or 1) * (1 - 2 * ICON_INSET_FRAC)
        if iw < 8 then iw = 16 end
    end
    -- A solid stroke whose inner edge touches the art's visible outer edge,
    -- so its centerline is thk / 2 past that edge. Styled shapes are 2x.
    local side = slot:GetWidth() or iw
    local sh = slot:GetHeight() or side
    local minSide = side
    if sh < minSide then minSide = sh end
    local styled = slot._formShape and not slot._goldRingForm
    local shape = slot._formShape
    local RIM = IchaUITotems_CastRim
    local thk = minSide * 0.03
    if thk < 1 then thk = 1 end
    if styled then thk = thk * 2 end
    local half = thk / 2
    local sparkBase = iw
    local radius
    slot._castRect = nil
    if styled and IchaUI_FormIsEdged and IchaUI_FormIsEdged(shape) then
        -- Square-hole shapes: a rectangle around the border's visible outer
        -- edge. _castRect = half extents of the stroke's centerline.
        local inW = slot._innerW or iw
        local inH = slot._innerH or iw
        local m = inW
        if inH < m then m = inH end
        local def = IchaUI_FormShapeDef and IchaUI_FormShapeDef(shape)
        local vis
        if def and def.edge then
            local ln = RIM.edgeLine[shape] or 0
            vis = (def.outset or 0) - ln
        else
            local e = math.floor(side * 0.22 + 0.5)
            if e < 8 then e = 8 end
            if e > 14 then e = 14 end
            vis = -e * RIM.tipLine
        end
        slot._castRect = { side / 2 + vis + half, sh / 2 + vis + half, thk }
        slot._castOX = 0
        slot._castOY = 0
        radius = minSide / 2
        sparkBase = m
    else
        local T, rf, cx, cy
        if styled then
            local def = IchaUI_FormShapeDef and IchaUI_FormShapeDef(shape)
            local hole
            if def and def.ring then
                hole = minSide * def.hole
            elseif shape == "tooltip" then
                hole = minSide * 0.90
            elseif shape == "portrait" then
                hole = minSide * 0.88
            else
                hole = minSide * 0.56
            end
            if hole < 8 then hole = 8 end
            sparkBase = hole
            local rim = RIM[shape] or RIM.tooltip
            rf = rim[1]
            if shape == "circle" then
                -- DrawerStyle tracker ring: 64/36 of the side, CENTER + shift.
                T = math.floor(side * 64 / 36 + 0.5)
                local shift = math.floor(side * 0.347 + 0.5)
                cx = shift + (rim[2] - 0.5) * T
                cy = -shift - (rim[3] - 0.5) * T
            else
                T = side
                if def and def.outer then T = side / def.outer end
                cx = (rim[2] - 0.5) * T
                cy = -(rim[3] - 0.5) * T
            end
        else
            -- Drawer gold ring: applyGoldRing pins it at the slot's TOPLEFT.
            T = slot.goldRing and slot.goldRing:GetWidth()
            if not T or T < 16 then
                local s = sh
                if s < 16 then s = 16 end
                T = math.floor(s * 1.65 + 0.5)
            end
            local rim = RIM.circle
            rf = rim[1]
            cx = rim[2] * T - side / 2
            cy = -(rim[3] * T - sh / 2)
        end
        radius = rf * T + half
        slot._castOX = cx
        slot._castOY = cy
    end
    -- Dots every half stroke width merge into one solid line.
    local n = math.ceil(2 * math.pi * radius / (thk * 0.5))
    if n < 48 then n = 48 end
    if n > 240 then n = 240 end
    slot._castSegN = n
    local sparkSz = math.max(10, math.floor(sparkBase * 0.28 + 0.5))
    if styled then sparkSz = math.floor(sparkSz * 1.15 + 0.5) end
    slot._castRingRadius = radius
    slot._castChipLen = thk
    slot._castChipThk = thk
    slot._castRingSparkLen = math.floor(sparkSz * 1.15 + 0.5)
    slot._castRingSparkThk = sparkSz

    local sp = slot.castSpark
    sp:SetWidth(slot._castRingSparkLen)
    sp:SetHeight(sparkSz)
    sp:SetTexture(CAST_SPARK_TEX)
end

local function hideCastRing(slot)
    if not slot then return end
    slot._castRingPct = nil
    IchaUITotems_HideCastParts(slot)
    if slot.castSpark then slot.castSpark:Hide() end
    killCastCooldown(slot)
end

local function hideCastSwipe(slot)
    hideCastRing(slot)
end

local function setCastRing(slot, pct, base)
    if not slot or not slot.icon then return end
    if not pct or pct ~= pct then
        hideCastRing(slot)
        return
    end
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end
    ensureCastRing(slot)
    layoutCastRing(slot)
    killCastCooldown(slot)

    if slot._castRect then
        IchaUITotems_SetCastRect(slot, pct, base)
        return
    end

    local r, g, b = castRingColor(base)
    local radius = slot._castRingRadius or 12
    local thk = slot._castChipThk or 2
    local n = slot._castSegN or CAST_RING_SEG
    local ox0 = slot._castOX or 0
    local oy0 = slot._castOY or 0

    -- Colored arc from 12 o'clock clockwise to the spark. No dim track.
    local lit = math.floor(pct * n + 0.5)
    if lit > n then lit = n end
    if lit < 0 then lit = 0 end
    if slot.castRingBg then slot.castRingBg:Hide() end
    if slot.castEdges then
        local ei
        for ei = 1, table.getn(slot.castEdges) do slot.castEdges[ei]:Hide() end
    end

    local i
    for i = 1, lit do
        local seg = IchaUITotems_CastDot(slot, i)
        local a = math.pi / 2 - ((i - 0.5) / n) * 2 * math.pi
        seg:ClearAllPoints()
        seg:SetWidth(thk)
        seg:SetHeight(thk)
        seg:SetPoint("CENTER", slot, "CENTER", math.cos(a) * radius + ox0, math.sin(a) * radius + oy0)
        seg:SetVertexColor(r, g, b)
        if seg.SetAlpha then seg:SetAlpha(1) end
        seg:Show()
    end
    for i = lit + 1, table.getn(slot.castSegs) do
        slot.castSegs[i]:Hide()
    end

    local a = math.pi / 2 - pct * 2 * math.pi
    local sp = slot.castSpark
    sp:ClearAllPoints()
    sp:SetWidth(slot._castRingSparkLen or 10)
    sp:SetHeight(slot._castRingSparkThk or 10)
    sp:SetPoint("CENTER", slot, "CENTER", math.cos(a) * radius + ox0, math.sin(a) * radius + oy0)
    -- Spark tip faces clockwise travel (stock spark points "up")
    setTexRotated(sp, a - math.pi / 2)
    sp:SetVertexColor(1, 1, 0.92)
    if sp.SetAlpha then sp:SetAlpha(1) end
    pcall(function()
        sp:SetTexture(CAST_SPARK_TEX)
    end)
    sp:Show()
    slot._castRingPct = pct
end

-- Square/rect progress: travels clockwise from top center along the stroke's
-- centerline. Distance s runs 0..P; edges are top (s in -hw..hw), right,
-- bottom, left.
function IchaUITotems_CastRectAt(hw, hh, s)
    local P = 4 * hw + 4 * hh
    if s > 3 * hw + 4 * hh then s = s - P end
    if s < hw then return s, hh, 1 end
    if s < hw + 2 * hh then return hw, hh - (s - hw), 2 end
    if s < 3 * hw + 2 * hh then return hw - (s - hw - 2 * hh), -hh, 3 end
    return -hw, -hh + (s - 3 * hw - 2 * hh), 4
end

-- Five solid strips (top-right half, right, bottom, left, top-left half),
-- each grown along its edge as progress passes it. A strip that starts or
-- ends at a corner runs half a stroke past it so the corners close.
function IchaUITotems_SetCastRect(slot, pct, base)
    local rc = slot._castRect
    local hw, hh, thk = rc[1], rc[2], rc[3]
    if hw < 1 then hw = 1 end
    if hh < 1 then hh = 1 end
    local ox = slot._castOX or 0
    local oy = slot._castOY or 0
    local r, g, b = castRingColor(base)
    local P = 4 * hw + 4 * hh
    local d = pct * P
    local half = thk / 2
    IchaUITotems_HideCastParts(slot)

    -- { start s, length, start x, start y, dir x, dir y, starts at corner }
    local E = {
        { 0, hw, 0, hh, 1, 0, false },
        { hw, 2 * hh, hw, hh, 0, -1, true },
        { hw + 2 * hh, 2 * hw, hw, -hh, -1, 0, true },
        { 3 * hw + 2 * hh, 2 * hh, -hw, -hh, 0, 1, true },
        { 3 * hw + 4 * hh, hw, -hw, hh, 1, 0, true },
    }
    local k
    for k = 1, 5 do
        local e = E[k]
        local f = d - e[1]
        if f > e[2] then f = e[2] end
        if f > 0 then
            local a0 = 0
            local a1 = f
            if e[7] then a0 = -half end
            if f >= e[2] and k < 5 then a1 = f + half end
            local mid = (a0 + a1) / 2
            local len = a1 - a0
            local t = IchaUITotems_CastStrip(slot, k)
            t:ClearAllPoints()
            if e[5] ~= 0 then
                t:SetWidth(len)
                t:SetHeight(thk)
            else
                t:SetWidth(thk)
                t:SetHeight(len)
            end
            t:SetPoint("CENTER", slot, "CENTER", ox + e[3] + e[5] * mid, oy + e[4] + e[6] * mid)
            t:SetVertexColor(r, g, b)
            if t.SetAlpha then t:SetAlpha(1) end
            t:Show()
        end
    end

    local sx, sy, sedge = IchaUITotems_CastRectAt(hw, hh, d)
    local rot = 0
    if sedge == 2 then rot = -math.pi / 2
    elseif sedge == 3 then rot = -math.pi
    elseif sedge == 4 then rot = math.pi / 2 end
    local sp = slot.castSpark
    sp:ClearAllPoints()
    sp:SetWidth(slot._castRingSparkLen or 10)
    sp:SetHeight(slot._castRingSparkThk or 10)
    sp:SetPoint("CENTER", slot, "CENTER", ox + sx, oy + sy)
    setTexRotated(sp, rot)
    sp:SetVertexColor(1, 1, 0.92)
    if sp.SetAlpha then sp:SetAlpha(1) end
    pcall(function() sp:SetTexture(CAST_SPARK_TEX) end)
    sp:Show()
    slot._castRingPct = pct
end





local function savePos()
    local d = db()
    if root and root.GetPoint then
        local p, _, rp, x, y = root:GetPoint(1)
        d.point, d.relPoint, d.x, d.y = p, rp, x, y
    end
    if d.hidden then d.hidden = true else d.hidden = false end
    d.scale = cfgScale
    d.size = cfgSize
    d.gap = cfgGap
    d.textSize = cfgText
    d.drawerSize = cfgDrawerSize
    d.drawerGap = cfgDrawerGap
    d.cdBadgeScale = cfgCdBadgeScale
    d.shiftDrawer = cfgShiftDrawer and true or false
    if d.drawerDir ~= "down" and d.drawerDir ~= "left" and d.drawerDir ~= "right" and d.drawerDir ~= "radial" then
        d.drawerDir = "up"
    end
    d.moving = moving
    if type(IchaUI_GetTotemTextStrata) == "function" then
        local n = IchaUI_GetTotemTextStrata()
        if n and n ~= "" then d.textStrata = n end
    elseif not d.textStrata or d.textStrata == "" then
        d.textStrata = "MEDIUM"
    end
end

local function loadCfg()
    local d = db()
    if d.scale then cfgScale = tonumber(d.scale) or DEFAULT_SCALE end
    if d.size then cfgSize = tonumber(d.size) or DEFAULT_SIZE end
    if d.gap then cfgGap = tonumber(d.gap) or DEFAULT_GAP end
    if d.textSize then cfgText = tonumber(d.textSize) or DEFAULT_TEXT end
    if d.drawerSize then cfgDrawerSize = tonumber(d.drawerSize) or DEFAULT_DRAWER_SIZE end
    if d.drawerGap then cfgDrawerGap = tonumber(d.drawerGap) or DEFAULT_DRAWER_GAP end
    if d.cdBadgeScale then cfgCdBadgeScale = tonumber(d.cdBadgeScale) or DEFAULT_CD_BADGE_SCALE end
    if d.shiftDrawer ~= nil then cfgShiftDrawer = d.shiftDrawer and true or false end
    if cfgScale < 0.4 then cfgScale = 0.4 end
    if cfgScale > 3 then cfgScale = 3 end
    if cfgSize < 20 then cfgSize = 20 end
    if cfgSize > 80 then cfgSize = 80 end
    if cfgGap < 0 then cfgGap = 0 end
    if cfgGap > 40 then cfgGap = 40 end
    if cfgText < 6 then cfgText = 6 end
    if cfgText > 28 then cfgText = 28 end
    if cfgDrawerSize < 14 then cfgDrawerSize = 14 end
    if cfgDrawerSize > 48 then cfgDrawerSize = 48 end
    if cfgDrawerGap < 0 then cfgDrawerGap = 0 end
    if cfgDrawerGap > 12 then cfgDrawerGap = 12 end
    if cfgCdBadgeScale < 0.4 then cfgCdBadgeScale = 0.4 end
    if cfgCdBadgeScale > 1.5 then cfgCdBadgeScale = 1.5 end
end

-- Totem sets. Set 1 = d.active (legacy key); sets 2..N = d.extraSets[i-1].active.
-- d.setPage = page shown on the bar. Global table: Totems.lua is near the
-- 200-local main-chunk limit.
IchaUITotemSets = IchaUITotemSets or {}
IchaUITotemSets.override = nil -- element→base picks while throwing a non-page set
-- Drop stale page-caret frames from a soft /reload so MakeArrow can rebind art.
IchaUITotemSets.prev = nil
IchaUITotemSets.next = nil

function IchaUITotemSets.Norm()
    local d = db()
    if type(d.active) ~= "table" then d.active = {} end
    if type(d.extraSets) ~= "table" then d.extraSets = {} end
    local i = 1
    while i <= table.getn(d.extraSets) do
        local s = d.extraSets[i]
        if type(s) ~= "table" then
            table.remove(d.extraSets, i)
        else
            if type(s.active) ~= "table" then s.active = {} end
            if type(s.name) ~= "string" or s.name == "" then s.name = "Set " .. (i + 1) end
            i = i + 1
        end
    end
    local n = 1 + table.getn(d.extraSets)
    local p = tonumber(d.setPage) or 1
    p = math.floor(p)
    if p < 1 or p > n then p = 1 end
    d.setPage = p
    return d, n
end

function IchaUITotemSets.Count()
    local _, n = IchaUITotemSets.Norm()
    return n
end

function IchaUITotemSets.Page()
    local d = IchaUITotemSets.Norm()
    return d.setPage
end

function IchaUITotemSets.Table(idx)
    local d, n = IchaUITotemSets.Norm()
    idx = tonumber(idx) or d.setPage
    if idx < 1 or idx > n then return nil end
    if idx == 1 then return d.active end
    return d.extraSets[idx - 1].active
end

function IchaUITotemSets.Name(idx)
    local d, n = IchaUITotemSets.Norm()
    idx = tonumber(idx) or d.setPage
    if idx < 1 or idx > n then return nil end
    if idx == 1 then
        if type(d.set1Name) == "string" and d.set1Name ~= "" then return d.set1Name end
        return "Set 1"
    end
    return d.extraSets[idx - 1].name
end

function IchaUITotemSets.Pick(t, element)
    local a = t and t[element]
    if not a or a == "" or a == "__none__" then return nil end
    return a
end

function IchaUITotemSets.ActiveTable()
    if IchaUITotemSets.override then return IchaUITotemSets.override end
    return IchaUITotemSets.Table(nil)
end

local function getActive(element)
    return IchaUITotemSets.Pick(IchaUITotemSets.ActiveTable(), element)
end

local function setActive(element, base)
    -- Throw-set selection (green glow); icon shows when nothing is live
    local d = db()
    local t = IchaUITotemSets.Table(nil)
    if not base or base == "" or base == "__none__" then
        t[element] = nil
    else
        t[element] = base
    end
    if element == "fire" then
        if base ~= "Searing Totem" and base ~= "Magma Totem" and base ~= "Fire Nova Totem" then
            d.fireTwist = nil
            local fs = slots["fire"]
            if fs then
                fs._twistDue = nil
                fs._twistBase = nil
                fs._twistArmed = nil
                fs._twistGen = (fs._twistGen or 0) + 1
                fs._twistExpect = nil
            end
        end
    end
    applySlotVisuals()
    local dr = drawers[element]
    if dr and dr:IsShown() then
        buildDrawerRows(element)
    end
end

local markDropped -- forward decl

local function queueEntryFor(base)
    if not base or base == "__none__" then return nil end
    ensureKnown()
    local k = knownCache[base]
    local entry = { base = base, name = base, index = nil, rank = nil }
    if k then
        entry.name = k.name or base
        entry.index = k.index
        entry.rank = k.rank
    end
    return entry
end

local function castEntry(entry)
    if not entry or not entry.base then return false end
    local book = BOOKTYPE_SPELL or "spell"
    local castOk = false
    -- Prefer spellbook index (most reliable on 1.12 / Turtle)
    if entry.index and CastSpell then
        CastSpell(entry.index, book)
        castOk = true
    end
    if not castOk and entry.name and CastSpellByName then
        local castName = entry.name
        if entry.rank and entry.rank ~= "" then
            castName = entry.name .. "(" .. entry.rank .. ")"
        end
        CastSpellByName(castName)
        castOk = true
    end
    if not castOk and CastSpellByName then
        CastSpellByName(entry.base)
        castOk = true
    end
    if castOk then
        markDropped(entry.base)
        noteSpellCd(entry)
    end
    return castOk
end

local function castTotem(base)
    local entry = queueEntryFor(base)
    if not entry then return false end
    return castEntry(entry)
end

local lastSlotFireAt = 0
local lastSlotFireEl = nil

function IchaUITotems_SlotBindFire(elOrIdx)
    local el = resolveSlotElement(elOrIdx)
    if not el then return end
    local now = GetTime and GetTime() or 0
    if el == lastSlotFireEl and (now - lastSlotFireAt) < 0.12 then
        return
    end
    lastSlotFireAt = now
    lastSlotFireEl = el
    if not isPlayerShaman() then return end
    bindPush(slots[el])
    local act = getActive(el)
    if not act then
        local label = ELEMENT_LABEL[el] or el
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(
                "IchaUI: no active " .. label .. " totem — right-click a totem in the drawer to set.")
        end
        return
    end
    -- Fire slot key throws the active set. Twist (when on) is inside ThrowSet.
    if el == "fire" and IchaUITotems_ThrowSet then
        IchaUITotems_ThrowSet()
        return
    end
    castTotem(act)
end

local lastSpellFireAt = 0
local lastSpellFireN = nil

function IchaUITotems_SpellBindFire(n)
    n = tonumber(n)
    if not n then return end
    local e = TOTEM_BIND_LIST[n]
    if not e then return end
    local now = GetTime and GetTime() or 0
    if n == lastSpellFireN and (now - lastSpellFireAt) < 0.12 then
        return
    end
    lastSpellFireAt = now
    lastSpellFireN = n
    if not isPlayerShaman() then return end
    local base = e.base
    -- Spell bind: press the drawer spell button if visible, else that element's slot
    local pushed = false
    local dr = drawers[e.element]
    if dr and dr.rows and dr:IsShown() then
        local ri
        for ri = 1, table.getn(dr.rows) do
            local row = dr.rows[ri]
            if row and row.base == base and not row.isNone then
                bindPush(row)
                pushed = true
                break
            end
        end
    end
    if not pushed then
        bindPush(slots[e.element])
    end
    -- Spell bind = cast only (do not change throw-set / active selection).
    -- Fire twist: Searing / Magma / Fire Nova keys use the twist cast so a
    -- live Searing or Magma is not dropped again.
    if e.element == "fire" and IchaUITotems_FireTwistMode and IchaUITotems_FireTwistMode() then
        if base == "Fire Nova Totem" and IchaUITotems_ThrowSet then
            IchaUITotems_ThrowSet()
            return
        end
        if base == "Searing Totem" or base == "Magma Totem" then
            if IchaUITotems_CastFireTwist then
                IchaUITotems_CastFireTwist()
                return
            end
        end
    end
    castTotem(base)
end


local function hideDrawer(element)
    local dr = drawers[element]
    if dr then
        dr:Hide()
        if IchaUI_ApplyTotemStrata then IchaUI_ApplyTotemStrata() end
    end
    pinned[element] = nil
    closeAt[element] = nil
    -- Restore CD badges after drawer closes (applySlotVisuals is a global def)
    local slot = slots[element]
    local fn = rawget(_G, "applySlotVisuals")
    if slot and type(fn) == "function" then
        pcall(fn)
    end
end

local function hideAllDrawers(except)
    local i
    for i = 1, table.getn(ELEMENTS) do
        local e = ELEMENTS[i]
        if e ~= except then
            hideDrawer(e)
        end
    end
end


local function showSpellTip(owner, spellName)
    if not spellName or spellName == "" or spellName == "__none__" then return end
    if not GameTooltip then return end
    if not (IsShiftKeyDown and IsShiftKeyDown()) then return end
    ensureKnown()
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local book = BOOKTYPE_SPELL or "spell"
    local idx = nil
    local k = knownCache[spellName]
    if k and k.index then
        idx = k.index
    else
        local i = 1
        while i <= 500 do
            local name = GetSpellName(i, book)
            if not name then break end
            if name == spellName or string.find(name, spellName, 1, true) then
                idx = i
            end
            i = i + 1
        end
    end
    if idx and GameTooltip.SetSpell then
        GameTooltip:SetSpell(idx, book)
    else
        GameTooltip:SetText(spellName)
    end
    -- Shift-hover tips stay on TOOLTIP (above duration text)
    if GameTooltip.SetFrameStrata then
        GameTooltip:SetFrameStrata("TOOLTIP")
    end
    if GameTooltip.SetFrameLevel then
        local fl = 300
        if owner and owner.GetFrameLevel then
            local ofl = owner:GetFrameLevel() or 0
            if ofl + 50 > fl then fl = ofl + 50 end
        end
        GameTooltip:SetFrameLevel(fl)
    end
    if GameTooltip.Raise then GameTooltip:Raise() end
    GameTooltip:Show()
end

local function hideSpellTip()
    if GameTooltip then GameTooltip:Hide() end
end

local function tipUpdateCheck()
    local name = this._ichaTipSpell
    if not name then return end
    if IsShiftKeyDown and IsShiftKeyDown() then
        if not this._ichaTipShown then
            showSpellTip(this, name)
            this._ichaTipShown = true
        end
    else
        if this._ichaTipShown then
            hideSpellTip()
            this._ichaTipShown = nil
        end
    end
end

function buildDrawerRows(element)
    local dr = drawers[element]
    if not dr then return end
    ensureKnown()
    if dr.rows then
        local i
        for i = 1, table.getn(dr.rows) do
            releaseCircleSlot(dr.rows[i])
            dr.rows[i]:Hide()
            dr.rows[i]:SetParent(nil)
        end
    end
    dr.rows = {}
    local list = CATALOG[element]
    local n = table.getn(list)
    -- Drawer size is independent of main totem slot size.
    -- popScale multiplies after the 14-48 clamp so 1.00 stays today's tray size.
    local iconSz = math.floor(cfgDrawerSize * cfgScale + 0.5)
    if iconSz < 14 then iconSz = 14 end
    if iconSz > 48 then iconSz = 48 end
    local bsc = 1
    if IchaUI_DrawerPopScale then bsc = IchaUI_DrawerPopScale("totems") end
    iconSz = math.floor(iconSz * bsc + 0.5)
    local gap = math.floor(cfgDrawerGap * cfgScale + 0.5)
    if gap < 0 then gap = 0 end
    local cols = 2
    if IchaUI_DrawerGridCols then
        local gridCols = IchaUI_DrawerGridCols("totems", n)
        if gridCols and gridCols >= 1 then cols = gridCols end
    end
    local shown = 0
    local dir = db().drawerDir
    if dir ~= "down" and dir ~= "left" and dir ~= "right" and dir ~= "radial" then dir = "up" end

    local function addIconRow(base, tex, isNone)
        shown = shown + 1
        local row = CreateFrame("Button", nil, dr)
        row:SetWidth(iconSz)
        row:SetHeight(iconSz)
        -- 2-across; first icons nearest the slot, then grow along dir
        local idx = shown - 1
        local a = math.mod(idx, cols)
        local b = math.floor(idx / cols)
        local step = iconSz + gap
        if dir == "radial" then
            row:SetPoint("CENTER", dr, "CENTER", 0, 0)
        elseif dir == "up" then
            row:SetPoint("BOTTOMLEFT", dr, "BOTTOMLEFT", a * step, b * step)
        elseif dir == "down" then
            row:SetPoint("TOPLEFT", dr, "TOPLEFT", a * step, -b * step)
        elseif dir == "right" then
            row:SetPoint("BOTTOMLEFT", dr, "BOTTOMLEFT", b * step, a * step)
        else
            row:SetPoint("BOTTOMRIGHT", dr, "BOTTOMRIGHT", -b * step, a * step)
        end
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetFrameLevel((dr:GetFrameLevel() or 1) + 10)
        row.base = base
        row.element = element
        row.isNone = isNone and true or false

        local circleBg = row:CreateTexture(nil, "BACKGROUND")
        circleBg:SetTexture("Interface\\AddOns\\IchaUI\\media\\circledisc.tga")
        circleBg:SetVertexColor(0.05, 0.05, 0.06, 1)
        row.circleBg = circleBg

        local ic = row:CreateTexture(nil, "ARTWORK")
        row.icon = ic
        local round = row:CreateTexture(nil, "ARTWORK")
        row.roundMask = round
        insetIcon(ic, row, iconSz)
        ic:SetTexture(tex)
        round:SetTexture(ROUNDMASK)
        round:SetVertexColor(0, 0, 0, 1)
        round:Show()

        local goldRing = row:CreateTexture(nil, "OVERLAY")
        goldRing:SetTexture(GOLD_RING)
        applyGoldRing(goldRing, row, iconSz)
        row.goldRing = goldRing

        local hilite = row:CreateTexture(nil, "OVERLAY")
        hilite:SetAllPoints(ic)
        hilite:SetTexture("Interface/Buttons/ButtonHilight-Square")
        hilite:SetBlendMode("ADD")
        hilite:SetAlpha(0)
        row.hilite = hilite

        local pushTex = row:CreateTexture(nil, "OVERLAY")
        pushTex:SetTexture("Interface/ChatFrame/ChatFrameBackground")
        pushTex:SetVertexColor(0, 0, 0)
        pushTex:SetAlpha(0.18)
        pushTex:Hide()
        row.pushTex = pushTex

        -- Selected throw-set: circular gold glow scaled to drawer icon
        local sel = row:CreateTexture(nil, "OVERLAY")
        -- Minimap zoom highlight is round (ActionButton-Border reads square/tiny when stretched)
        sel:SetTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")
        sel:SetBlendMode("ADD")
        sel:SetVertexColor(1.0, 0.82, 0.28, 1)
        local glowSz = math.floor(iconSz * 1.35 + 0.5)
        sel:ClearAllPoints()
        sel:SetWidth(glowSz)
        sel:SetHeight(glowSz)
        sel:SetPoint("CENTER", ic, "CENTER", 0, 0)
        local cur = getActive(element)
        if (isNone and not cur) or (not isNone and cur == base) then
            sel:SetAlpha(0.95)
            sel:Show()
        else
            sel:SetAlpha(0)
            sel:Hide()
        end
        row.selGlow = sel

        row:SetScript("OnMouseDown", function()
            pushCircleSlot(this)
        end)
        row:SetScript("OnMouseUp", function()
            if not this._bindPushUntil then
                releaseCircleSlot(this)
            end
        end)
        row:SetScript("OnEnter", function()
            this.hilite:SetAlpha(0.45)
            closeAt[this.element] = nil
            if this.isNone or this.base == "__none__" then
                this._ichaTipSpell = nil
            else
                this._ichaTipSpell = this.base
                this._ichaTipShown = nil
                if IsShiftKeyDown and IsShiftKeyDown() then
                    showSpellTip(this, this.base)
                    this._ichaTipShown = true
                end
            end
            this:SetScript("OnUpdate", tipUpdateCheck)
        end)
        row:SetScript("OnLeave", function()
            this.hilite:SetAlpha(0)
            this._ichaTipSpell = nil
            this._ichaTipShown = nil
            this:SetScript("OnUpdate", nil)
            hideSpellTip()
            if not this._bindPushUntil then
                releaseCircleSlot(this)
            end
            if not pinned[this.element] then
                closeAt[this.element] = (GetTime and GetTime() or 0) + DRAWER_CLOSE_DELAY
            end
        end)
        row:SetScript("OnClick", function()
            local el = this.element
            local base = this.base
            if this.isNone then
                if arg1 == "RightButton" or arg1 == "LeftButton" then
                    setActive(el, nil)
                    savePos()
                    hideDrawer(el)
                    totemChat("Totem active [" .. ELEMENT_LABEL[el] .. "]: (none)")
                end
                return
            end
            if arg1 == "LeftButton" then
                castTotem(base)
            elseif arg1 == "RightButton" then
                setActive(el, base)
                savePos()
                hideDrawer(el)
                totemChat("Totem active [" .. ELEMENT_LABEL[el] .. "]: " .. base)
            end
        end)
        table.insert(dr.rows, row)
    end

    -- First: empty skull (clear throw-set)
    addIconRow("__none__", emptyIcon(element), true)

    local i
    for i = 1, n do
        local cat = list[i]
        local k = knownCache[cat]
        if k then
            addIconRow(cat, iconFor(cat), false)
        end
    end

    local rows = math.floor((shown + cols - 1) / cols)
    if rows < 1 then rows = 1 end
    local w, h
    if dir == "radial" and IchaUI_DrawerRadialRadius and IchaUI_DrawerRadialXY then
        local slotSz = math.floor((cfgSize or 36) * (cfgScale or 1) + 0.5)
        if slots and slots[element] and slots[element].GetWidth then
            local sw = slots[element]:GetWidth()
            if sw and sw > 1 then slotSz = sw end
        end
        local radius = IchaUI_DrawerRadialRadius(shown, slotSz, iconSz, gap, db().drawerSpread)
        local ri
        for ri = 1, shown do
            local row = dr.rows[ri]
            if row then
                local rx, ry = IchaUI_DrawerRadialXY(ri, shown, radius, db().drawerArc, db().drawerRot)
                row:ClearAllPoints()
                row:SetPoint("CENTER", dr, "CENTER", rx, ry)
            end
        end
        w = 2
        h = 2
    elseif dir == "left" or dir == "right" then
        w = rows * iconSz + math.max(0, rows - 1) * gap
        h = cols * iconSz + (cols - 1) * gap
    else
        w = cols * iconSz + (cols - 1) * gap
        h = rows * iconSz + math.max(0, rows - 1) * gap
    end
    dr:SetWidth(w)
    dr:SetHeight(h)
    if dr.empty then dr.empty:Hide() end
end


local function canHoverOpenDrawer()
    if not cfgShiftDrawer then return true end
    return IsShiftKeyDown and IsShiftKeyDown()
end

local function showDrawer(element, pin)
    local dr = drawers[element]
    local slot = slots[element]
    if not dr or not slot then return end
    if not (dr.IsShown and dr:IsShown()) then
        hideAllDrawers(element)
    end
    buildDrawerRows(element)
    dr:ClearAllPoints()
    local dir = db().drawerDir
    if dir ~= "down" and dir ~= "left" and dir ~= "right" and dir ~= "radial" then dir = "up" end
    if dir == "radial" then
        dr:SetPoint("CENTER", slot, "CENTER", 0, 0)
        dr:EnableMouse(false)
    else
        dr:EnableMouse(true)
        if dir == "up" then
            dr:SetPoint("BOTTOM", slot, "TOP", 0, 1)
        elseif dir == "down" then
            dr:SetPoint("TOP", slot, "BOTTOM", 0, -1)
        elseif dir == "left" then
            dr:SetPoint("RIGHT", slot, "LEFT", -1, 0)
        else
            dr:SetPoint("LEFT", slot, "RIGHT", 1, 0)
        end
    end
    dr:Show()
    if IchaUI_ApplyTotemStrata then IchaUI_ApplyTotemStrata() end
    -- CD badges sit above the slot and ate first-open clicks — hide only when opening up
    if dir == "up" then
        if slot.cdBadges then
            local bi
            for bi = 1, table.getn(slot.cdBadges) do
                local b = slot.cdBadges[bi]
                if b then
                    b._hiddenForDrawer = b:IsShown() and true or false
                    b:EnableMouse(false)
                    b:Hide()
                end
            end
        elseif slot.cdBadge then
            slot.cdBadge._hiddenForDrawer = slot.cdBadge:IsShown() and true or false
            slot.cdBadge:EnableMouse(false)
            slot.cdBadge:Hide()
        end
    else
        local fn = rawget(_G, "applySlotVisuals")
        if type(fn) == "function" then pcall(fn) end
    end
    if dr.rows then
        local i
        for i = 1, table.getn(dr.rows) do
            local row = dr.rows[i]
            if row then
                row:EnableMouse(true)
                row:SetFrameLevel((dr:GetFrameLevel() or 40) + 4)
                if row.Raise then row:Raise() end
            end
        end
    end
    if dr.Raise then dr:Raise() end
    if pin then
        pinned[element] = true
        closeAt[element] = nil
    else
        pinned[element] = nil
    end
end

local function updateLiveFromAPI()
    if type(GetTotemInfo) ~= "function" then return false end
    local now = GetTime and GetTime() or 0
    -- After Totemic Recall, API still reports totems for a frame or two —
    -- re-filling live here was flashing duration text before icons cleared.
    if now < suppressLiveUntil then
        local i
        for i = 1, table.getn(ELEMENTS) do
            local el = ELEMENTS[i]
            live[el] = nil
            liveCast[el] = nil
            liveGuid[el] = nil
        end
        return true
    end
    local i
    for i = 1, table.getn(ELEMENTS) do
        local el = ELEMENTS[i]
        local slotIdx = CLASSIC_SLOT[el]
        local have, name, startTime, duration, icon = GetTotemInfo(slotIdx)
        if have and name and duration and tonumber(duration) and tonumber(duration) > 0 then
            local prev = live[el]
            local start = tonumber(startTime) or now
            -- Keep a fresh markDropped/rethrow start for 2s so API can't undo the reset
            if prev and prev.dropStamp and (now - prev.dropStamp) < 2.0 then
                start = prev.start or start
            end
            local baseNameResolved = matchCatalog(name, el) or baseName(name)
            local durApi = tonumber(duration)
            if baseNameResolved == "Fire Nova Totem" then
                durApi = fuseFor(baseNameResolved, durApi)
            end
            live[el] = {
                name = name,
                start = start,
                duration = durApi,
                icon = icon,
                base = baseNameResolved,
                fromAPI = true,
                dropStamp = prev and prev.dropStamp or nil,
                dropX = prev and prev.dropX or nil,
                dropY = prev and prev.dropY or nil,
                dropZ = prev and prev.dropZ or nil,
                sawBuff = prev and prev.sawBuff or nil,
            }
        else
            live[el] = nil
            liveCast[el] = nil
            liveGuid[el] = nil
        end
    end
    return true
end

local function isTotemRecallName(name)
    if not name or name == "" then return false end
    local l = string.lower(tostring(name))
    if string.find(l, "totemic recall", 1, true) then return true end
    if string.find(l, "totem recall", 1, true) then return true end
    if string.find(l, "recall of the totem", 1, true) then return true end
    if string.find(l, "call of the elements", 1, true) then return true end
    -- Turtle / custom names
    if string.find(l, "recall", 1, true) and string.find(l, "totem", 1, true) then return true end
    return false
end

local function wipeSlotTimers(slot)
    if not slot then return end
    if slot.timer then
        slot.timer:SetText("")
        if slot.timer.SetAlpha then slot.timer:SetAlpha(1) end
        slot.timer:Hide()
    end
    if slot.pulse then
        slot.pulse:SetAlpha(0)
        slot.pulse:Hide()
    end
    if slot.castText then
        slot.castText:SetText("")
        slot.castText:Hide()
    end
    if slot.periodBar then
        slot.periodBar:Hide()
        slot.periodBar:SetWidth(1)
    end
    -- Thin cast ring + spark (replaces Cooldown swipe)
    if slot.castRingBg then slot.castRingBg:Hide() end
    if slot.castEdges then
        local ei
        for ei = 1, table.getn(slot.castEdges) do slot.castEdges[ei]:Hide() end
    end
    if slot.castSpark then slot.castSpark:Hide() end
    if slot.castSegs then
        local ri
        for ri = 1, table.getn(slot.castSegs) do
            slot.castSegs[ri]:Hide()
        end
    end
    slot._castRingPct = nil
    slot.cdStart = nil
    if slot.cd then
        -- Keep Cooldown unused for casts (never resurrect square wipe)
        if CooldownFrame_SetTimer then
            pcall(function() CooldownFrame_SetTimer(slot.cd, 0, 0, 0) end)
        end
        pcall(function() slot.cd:Hide() end)
        pcall(function()
            slot.cd:SetSequence(0)
            slot.cd:SetAlpha(0)
        end)
    end
    if slot.cdMaskFrame then
        pcall(function() slot.cdMaskFrame:Hide() end)
    end
    if slot.cdBadges then
        local wi
        for wi = 1, table.getn(slot.cdBadges) do
            local b = slot.cdBadges[wi]
            if b then
                b:Hide()
                if b.cdText then b.cdText:SetText("") end
            end
        end
    elseif slot.cdBadge then
        slot.cdBadge:Hide()
        if slot.cdBadge.cdText then
            slot.cdBadge.cdText:SetText("")
        end
    end
end

local lastClearAt = 0
local clearingLive = false
local function clearAllLive(reason)
    local now = GetTime and GetTime() or 0
    -- Extend suppress even on duplicate recall events
    if now + 0.8 > suppressLiveUntil then
        suppressLiveUntil = now + 0.8
    end
    -- Recall fires START + STOP + chat + totem-update; one visual wipe is enough
    if clearingLive then return end
    if (now - lastClearAt) < 0.5 then
        return
    end
    clearingLive = true
    lastClearAt = now
    pendingRecall = true -- keep true so applySlotVisuals won't paint live
    liveGuid = {}
    local i
    -- Null live FIRST so nothing can read stale duration mid-wipe
    for i = 1, table.getn(ELEMENTS) do
        live[ELEMENTS[i]] = nil
        liveCast[ELEMENTS[i]] = nil
    end
    for i = 1, table.getn(ELEMENTS) do
        local el = ELEMENTS[i]
        wipeSlotTimers(slots[el])
        local slot = slots[el]
        if slot and slot.timer then
            slot.timer:SetText("")
            slot.timer:Hide()
        end
        if slot and slot.castText then
            slot.castText:SetText("")
            slot.castText:Hide()
        end
        if slot and slot.icon then
            local act = getActive(el)
            if act then
                slot.icon:SetTexture(iconFor(act))
            else
                slot.icon:SetTexture(emptyIcon(el))
            end
            slot.icon:SetVertexColor(1, 1, 1, 1)
            if el == "fire" and IchaUITotems_PaintFireTwist then
                IchaUITotems_PaintFireTwist(slot)
            end
        end
        if slot and slot.cdBadges then
            local ci
            for ci = 1, table.getn(slot.cdBadges) do
                local b = slot.cdBadges[ci]
                if b then b:Hide() end
            end
        elseif slot and slot.cdBadge then
            slot.cdBadge:Hide()
        end
    end
    -- Drop any in-flight throw queue (totems recalled)
    throwQueue = {}
    throwNext = 0
    throwTotal = 0
    throwDone = 0
    throwBusy = false
    local fs = slots["fire"]
    if fs then
        fs._twistDue = nil
        fs._twistBase = nil
        fs._twistArmed = nil
        fs._twistGen = (fs._twistGen or 0) + 1
        fs._twistExpect = nil
        fs._twistTries = nil
    end
    clearingLive = false
    pendingRecall = false
    -- Do NOT call applySlotVisuals here — OnUpdate will paint empty slots
    -- without a second full pass fighting GetTotemInfo.
end

-- CallOfElements-style: SuperWoW UnitPosition is world XYZ in yards (3D).
local function hasSuperWow()
    return (SUPERWOW_VERSION ~= nil) or (type(SetAutoloot) == "function")
end

local function unitXYZ(unit)
    if type(UnitPosition) ~= "function" or not unit then return nil end
    if type(UnitExists) == "function" then
        local okEx, exists = pcall(UnitExists, unit)
        if okEx and not exists then return nil end
    end
    local ok, x, y, z = pcall(UnitPosition, unit)
    if ok and x and y then return x, y, (z or 0) end
    return nil
end

local function playerXYZ()
    return unitXYZ("player")
end

-- Horizontal yards only (totem aura is a cylinder; Z noise made range feel wrong).
local function distYards2(ax, ay, bx, by)
    if not ax or not bx then return nil end
    local dx = ax - bx
    local dy = ay - by
    return math.sqrt(dx * dx + dy * dy)
end

local function outOfRangeOf(unit, yards)
    local x1, y1 = playerXYZ()
    local x2, y2 = unitXYZ(unit)
    if not x1 or not x2 then return nil end
    local d = distYards2(x1, y1, x2, y2)
    if not d then return nil end
    return d >= yards
end

local lastGuidScan = 0
local function refreshTotemGuids(force)
    if IchaUI_LEAVING or not hasSuperWow() then return end
    if type(WorldFrame) ~= "table" or type(WorldFrame.GetChildren) ~= "function" then return end
    local now = GetTime and GetTime() or 0
    -- Full WorldFrame scan is expensive; once per quarter-second is enough for range
    if not force and (now - lastGuidScan) < 0.25 then return end
    lastGuidScan = now
    local kids = { WorldFrame:GetChildren() }
    local playerName = UnitName and UnitName("player")
    if not playerName then return end
    local i
    for i = 1, table.getn(kids) do
        local f = kids[i]
        if f and f.IsVisible and f:IsVisible() and f.GetName then
            local okG, guid = pcall(function() return f:GetName(1) end)
            if okG and guid and type(guid) == "string" and string.len(guid) > 4 then
                local okN, name = pcall(UnitName, guid)
                if okN and name and name ~= "" then
                    local owner = nil
                    local okO, on = pcall(UnitName, guid .. "owner")
                    if okO and on then owner = on end
                    -- Require owner match when SuperWoW provides it (avoid foreign totems)
                    if owner == playerName or owner == nil then
                        local ei
                        for ei = 1, table.getn(ELEMENTS) do
                            local e = ELEMENTS[ei]
                            local L = live[e]
                            if L and L.base and string.find(name, L.base, 1, true) then
                                if owner == playerName or liveGuid[e] == nil then
                                    liveGuid[e] = guid
                                end
                            elseif L and L.name and string.find(name, L.name, 1, true) then
                                if owner == playerName or liveGuid[e] == nil then
                                    liveGuid[e] = guid
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Scan player buff textures (same API CallOfElements uses).
local function playerBuffTextures()
    local out = {}
    if type(GetPlayerBuff) ~= "function" or type(GetPlayerBuffTexture) ~= "function" then
        return out
    end
    local i
    for i = 0, 31 do
        local buffId = GetPlayerBuff(i, "HELPFUL|HARMFUL|PASSIVE")
        if not buffId or buffId < 0 then
            break
        end
        local tex = GetPlayerBuffTexture(buffId)
        if tex then
            out[tex] = true
        end
    end
    return out
end

-- Per-totem range. Prefer CoE buff-presence (true aura range), then GUID, then frozen drop.
local function totemInRange(el, yards)
    yards = yards or TOTEM_KEEP_RANGE
    local L = live[el]
    if not L or not L.start then return nil end
    local base = L.base

    -- 1) Buff aura totems: red exactly when the game drops your buff (~30y)
    if base and not GROUND_ONLY[base] then
        local tex = L.icon or iconFor(base)
        if tex then
            local buffs = playerBuffTextures()
            if buffs[tex] then
                L.sawBuff = true
                return true
            end
            if L.sawBuff then
                return false
            end
            -- Buff not seen yet (just dropped) — fall through to position
        end
    end

    -- 2) SuperWoW totem GUID (CoE path) — scan is throttled / done in applySlotVisuals
    local guid = liveGuid[el]
    if guid then
        local oor = outOfRangeOf(guid, yards)
        if oor ~= nil then return (not oor) end
    end

    -- 3) Frozen drop anchor (set once on cast — never chased by buff ticks)
    if L.dropX and L.dropY then
        local x, y = playerXYZ()
        if not x then return nil end
        local d = distYards2(x, y, L.dropX, L.dropY)
        if not d then return nil end
        return d <= yards
    end
    return nil
end

-- Smart-throw: still near if ANY active set totem is in range of its own anchor.
local function nearLastDrop(yards)
    yards = yards or TOTEM_KEEP_RANGE
    local saw = false
    local i
    for i = 1, table.getn(ELEMENTS) do
        local el = ELEMENTS[i]
        if getActive(el) and live[el] then
            local r = totemInRange(el, yards)
            if r == true then return true end
            if r == false then saw = true end
        end
    end
    if saw then return false end
    return nil
end

local function anySetTotemLive()
    local now = GetTime and GetTime() or 0
    local i
    for i = 1, table.getn(ELEMENTS) do
        local el = ELEMENTS[i]
        if getActive(el) then
            local L = live[el]
            if L and L.start and L.duration then
                if ((L.start + L.duration) - now) > 0.2 then
                    return true
                end
            end
        end
    end
    return false
end

-- nLive, allOutOfRange.
-- Uses the same slot flags applySlotVisuals paints (gold = proven in-range).
-- Unknown range is OOR. Does not call GetTotemInfo (that can wipe live and
-- reset the 5s recall wait while the bar still shows red timers).
function IchaUITotems_LiveRangeQuery()
    local now = GetTime and GetTime() or 0
    if now < suppressLiveUntil then
        return 0, false, 0
    end
    local n = 0
    local inCnt = 0
    local anyIn = false
    local i
    for i = 1, table.getn(ELEMENTS) do
        local el = ELEMENTS[i]
        local slot = slots[el]
        local liveHere = false
        local provenIn = false
        -- Prefer the same flags applySlotVisuals paints (red timer = not in-range).
        if slot and slot._recallLive then
            liveHere = true
            -- Red timer is OOR. Gold (_recallInRange) is in-range. Do not invert.
            if slot._recallRed then
                provenIn = false
            else
                provenIn = (slot._recallInRange == true)
            end
        else
            local L = live[el]
            if L and L.start then
                local remain = 1
                if L.duration then
                    remain = (L.start + L.duration) - now
                end
                if remain > 0.2 then
                    liveHere = true
                    local r = totemInRange(el, TOTEM_KEEP_RANGE)
                    provenIn = (r == true)
                end
            end
        end
        if liveHere then
            n = n + 1
            if provenIn then
                anyIn = true
                inCnt = inCnt + 1
            end
        end
    end
    if n == 0 then
        return 0, false, 0
    end
    return n, (not anyIn), inCnt
end

-- anchorPos: true on real casts only. Buff chat must NOT re-anchor (that chased
-- the player and made timers go red around ~42y instead of 30).
markDropped = function(spellName, anchorPos)
    if not spellName then return end
    if isTotemRecallName(spellName) then
        clearAllLive("recall")
        return
    end
    if anchorPos == nil then anchorPos = true end
    local i
    for i = 1, table.getn(ELEMENTS) do
        local el = ELEMENTS[i]
        local cat = matchCatalog(spellName, el)
        if cat then
            local now = GetTime and GetTime() or 0
            local prev = live[el]
            local dropX, dropY, dropZ = nil, nil, nil
            local sawBuff = nil
            -- Only re-anchor on a real new drop/rethrow. Duplicate events (buff
            -- applications, double UNIT_CASTEVENT) must keep the original feet.
            local isFresh = true
            if prev and prev.base == cat and prev.dropX and prev.dropStamp and (now - prev.dropStamp) < 2.0 then
                isFresh = false
            end
            if anchorPos and isFresh then
                local px, py, pz = playerXYZ()
                if px then
                    dropX, dropY, dropZ = px, py, pz or 0
                end
                liveGuid[el] = nil -- new totem object
            elseif prev then
                dropX, dropY, dropZ = prev.dropX, prev.dropY, prev.dropZ
                sawBuff = prev.sawBuff
                -- keep guid if same totem
            end
            -- Rethrow always resets pulse / searing phase clocks
            live[el] = {
                name = spellName,
                start = now,
                duration = fuseFor(cat, durationFor(cat)),
                base = cat,
                fromFallback = true,
                fromAPI = nil,
                dropStamp = (isFresh and now) or (prev and prev.dropStamp) or now,
                castSynced = nil,
                dropX = dropX,
                dropY = dropY,
                dropZ = dropZ,
                sawBuff = sawBuff,
            }
            liveCast[el] = nil
            -- Arm the same recall flags applySlotVisuals paints (slot click AND throw-set).
            local slot = slots[el]
            if slot then
                slot._recallLive = true
                local r = totemInRange(el, TOTEM_KEEP_RANGE)
                slot._recallInRange = (r == true)
                slot._recallRed = (r == false)
            end
            -- Track CD for above-slot timer (GCD / spell CD)
            if isFresh and noteSpellCd then
                noteSpellCd(queueEntryFor(cat) or { base = cat })
            end
            -- Wait for real UNIT_CASTEVENT / "begins to cast" for accurate bolt timer
            return
        end
    end
end

local function noteFireCast(spellHint, dur, fromEvent)
    local now = GetTime and GetTime() or 0
    local name = tostring(spellHint or "Searing Bolt")
    -- Never start a cast timer from the totem DROP (summon) — only real bolts
    local nl = string.lower(name)
    if string.find(nl, "totem", 1, true) and not string.find(nl, "bolt", 1, true) then
        return
    end
    local L = live["fire"]
    -- Only track while a fire cast-totem is actually down
    if not L or not L.base or not FIRE_CAST_TOTEMS[L.base] then
        return
    end
    local base = L.base
    if string.find(name, "Magma", 1, true) then
        base = "Magma Totem"
    elseif string.find(name, "Searing", 1, true) then
        base = "Searing Totem"
    end
    local fallback = searingCastLength()
    local d = tonumber(dur)
    if d and d > 10 then d = d / 1000 end -- ms → sec
    if not d or d <= 0 then d = fallback end
    if d > 4 then d = fallback end
    if d < 0.3 then d = fallback end
    liveCast["fire"] = {
        start = now,
        finish = now + d,
        name = base,
        fromEvent = fromEvent and true or nil,
    }
    if fromEvent and L then
        L.castSynced = true
    end
end


local function elementForBase(base)
    if not base then return nil end
    ensureKnown()
    local k = knownCache[base]
    if k and k.element then return k.element end
    local ei
    for ei = 1, table.getn(ELEMENTS) do
        local el = ELEMENTS[ei]
        if matchCatalog(base, el) then return el end
    end
    return nil
end

local function spellOnCooldown(entry)
    if not entry or not entry.index or type(GetSpellCooldown) ~= "function" then
        return false, 0, 0
    end
    local book = BOOKTYPE_SPELL or "spell"
    local start, duration, enable = GetSpellCooldown(entry.index, book)
    start = tonumber(start) or 0
    duration = tonumber(duration) or 0
    if enable == 0 then return true, 0.5, 0.5 end
    -- Ignore GCD (~1.5s); only real totem spell CDs (Stoneclaw, Fire Nova, etc.)
    if start > 0 and duration > 1.7 then
        local now = GetTime and GetTime() or 0
        local remain = (start + duration) - now
        if remain > 0.05 then
            return true, remain, duration
        end
    end
    return false, 0, 0
end

noteSpellCd = function(entry)
    if not entry or not entry.base then return end
    local el = elementForBase(entry.base)
    if not el then return end
    lastCastBase[el] = entry.base
    local now = GetTime and GetTime() or 0
    local start, duration = 0, 0
    local book = BOOKTYPE_SPELL or "spell"
    if entry.index and type(GetSpellCooldown) == "function" then
        local s, d = GetSpellCooldown(entry.index, book)
        start = tonumber(s) or 0
        duration = tonumber(d) or 0
    end
    -- Only record real spell CDs (skip GCD)
    if start > 0 and duration > 1.7 then
        spellCdFallback[el] = { start = start, duration = duration, base = entry.base }
    else
        spellCdFallback[el] = nil
    end
end

-- Fire twist: right-click the fire slot cycles off → Nova then Searing →
-- Nova then Magma. The follow totem is queued for the detonate time.
-- Every successful Fire Nova arms that follow, even if Searing or Magma
-- was already down (Nova removes them). If Nova is on cooldown, do nothing.
function IchaUITotems_FireCanTwist()
    local act = getActive("fire")
    if act == "Searing Totem" or act == "Magma Totem" or act == "Fire Nova Totem" then
        return true
    end
    return false
end

function IchaUITotems_FireTwistMode()
    if not IchaUITotems_FireCanTwist() then return nil end
    local d = db()
    if not d then return nil end
    if d.fireTwist == "searing" or d.fireTwist == "magma" then
        return d.fireTwist
    end
    return nil
end

function IchaUITotems_TwistFollowBase()
    local m = IchaUITotems_FireTwistMode()
    if m == "magma" then return "Magma Totem" end
    if m == "searing" then return "Searing Totem" end
    return nil
end

function IchaUITotems_FireTotemLive(base)
    if not base then return false end
    local L = live["fire"]
    if not L or L.base ~= base or not L.start or not L.duration then
        return false
    end
    local now = GetTime and GetTime() or 0
    local life = L.duration
    if L.base == "Fire Nova Totem" then
        life = fuseFor(L.base, L.duration)
    end
    if (L.start + life) - now > 0.2 then
        return true
    end
    return false
end

function IchaUITotems_FireNovaReady()
    local entry = queueEntryFor("Fire Nova Totem")
    if not entry then return false end
    local onCd = spellOnCooldown(entry)
    if onCd then return false end
    return true
end

function IchaUITotems_TwistSpellName(base)
    local entry = queueEntryFor(base)
    if not entry then return base end
    local castName = entry.name or base
    if entry.rank and entry.rank ~= "" then
        castName = castName .. "(" .. entry.rank .. ")"
    end
    return castName
end

function IchaUITotems_RunTwistFollow()
    local slot = slots["fire"]
    if not slot or not slot._twistArmed then return end
    local base = slot._twistBase
    local name = slot._twistSpell
    if not base or not name or not IchaUITotems_FireTwistMode() then
        slot._twistArmed = nil
        return
    end
    local function followLanded()
        if IchaUITotems_FireTotemLive(base) then return true end
        local L = live["fire"]
        if L and L.base == base then return true end
        if type(GetTotemInfo) == "function" then
            local have, tname = GetTotemInfo(CLASSIC_SLOT["fire"])
            if have and tname and matchCatalog(tostring(tname), "fire") == base then
                markDropped(base)
                return true
            end
        end
        return false
    end
    if followLanded() then
        slot._twistArmed = nil
        slot._twistExpect = nil
        slot._twistDue = nil
        return
    end
    local now = GetTime and GetTime() or 0
    local deadline = slot._twistDeadline or (now + 1.5)
    local function giveUp()
        slot._twistArmed = nil
        slot._twistExpect = nil
        slot._twistDue = nil
        if followLanded() then return end
        if slot._twistFailChat then return end
        slot._twistFailChat = true
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("IchaUI: fire twist follow failed")
        end
    end
    local function arm(delay)
        slot._twistArmed = true
        slot._twistGen = (slot._twistGen or 0) + 1
        local gen = slot._twistGen
        local function step()
            local s = slots["fire"]
            if not s or s._twistGen ~= gen then return end
            IchaUITotems_RunTwistFollow()
        end
        local scheduled = false
        if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            local ok = pcall(C_Timer.After, delay, step)
            if ok then scheduled = true end
        end
        if not scheduled and Chronos and type(Chronos.schedule) == "function" then
            local ok2 = pcall(Chronos.schedule, delay, step)
            if ok2 then scheduled = true end
        end
        if not scheduled then
            slot._twistArmed = nil
        end
        return scheduled
    end
    if now >= deadline then
        giveUp()
        return
    end
    -- Nova still the fire totem, or the follow spell has a real cooldown (not GCD).
    -- FireTotemLive ignores the last 0.2s, so also block while any fuse time remains.
    local novaStill = IchaUITotems_FireTotemLive("Fire Nova Totem")
    local Lf = live["fire"]
    if Lf and Lf.base == "Fire Nova Totem" and Lf.start and Lf.duration then
        local life = fuseFor(Lf.base, Lf.duration)
        if (Lf.start + life) - now > 0 then
            novaStill = true
        end
    end
    local followCd = false
    local entry = queueEntryFor(base)
    if entry then
        local onCd = spellOnCooldown(entry)
        if onCd then followCd = true end
    end
    if novaStill or followCd then
        local step = 0.20
        if now + step > deadline then
            giveUp()
        elseif not arm(step) then
            giveUp()
        end
        return
    end
    -- Last QueueSpellByName may still be landing. A fail event is not proof.
    if slot._twistExpect and (now - slot._twistExpect) < 0.20 then
        local wait = 0.20 - (now - slot._twistExpect)
        if wait < 0.15 then wait = 0.15 end
        if now + wait > deadline then
            giveUp()
        elseif not arm(wait) then
            giveUp()
        end
        return
    end
    if type(QueueSpellByName) ~= "function" then
        slot._twistArmed = nil
        if not slot._twistFailChat then
            slot._twistFailChat = true
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("IchaUI: fire twist follow failed (no QueueSpellByName)")
            end
        end
        return
    end
    if not slot._twistAnnounced then
        slot._twistAnnounced = true
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("IchaUI: fire twist " .. name)
        end
    end
    QueueSpellByName(name)
    slot._twistExpect = now
    slot._twistExpectBase = base
    local step = 0.20
    if now + step > deadline then
        slot._twistDeadline = now + 0.25
        if not arm(0.25) then giveUp() end
    elseif not arm(step) then
        giveUp()
    end
end

function IchaUITotems_QueueTwistFollow(base)
    local slot = slots["fire"]
    if not slot or not base then return end
    local fuse = fuseFor("Fire Nova Totem", 5)
    if not fuse or fuse < 1 then fuse = 1 end
    -- Drop just after the nova finishes on the server: fuse + ping + 10ms.
    local pingMs = 0
    if type(GetNetStats) == "function" then
        local _, _, home, world = GetNetStats()
        world = tonumber(world)
        home = tonumber(home)
        if world and world > 0 then
            pingMs = world
        elseif home and home > 0 then
            pingMs = home
        end
    end
    if pingMs < 0 then pingMs = 0 end
    if pingMs > 2000 then pingMs = 2000 end
    fuse = fuse + (pingMs / 1000) + 0.010
    local nowArm = GetTime and GetTime() or 0
    slot._twistGen = (slot._twistGen or 0) + 1
    local gen = slot._twistGen
    slot._twistBase = base
    slot._twistSpell = IchaUITotems_TwistSpellName(base)
    slot._twistArmed = true
    slot._twistDue = nil
    slot._twistTries = 0
    slot._twistFailChat = nil
    slot._twistAnnounced = nil
    slot._twistExpect = nil
    slot._twistExpectBase = base
    -- Retries may run until 1.5s after this due time. The first wait stays fuse+ping+10ms.
    slot._twistDeadline = nowArm + fuse + 1.5
    local function fire()
        local s = slots["fire"]
        if not s or s._twistGen ~= gen then return end
        IchaUITotems_RunTwistFollow()
    end
    local armed = false
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        local ok = pcall(C_Timer.After, fuse, fire)
        if ok then armed = true end
    end
    if not armed and Chronos and type(Chronos.schedule) == "function" then
        local ok2 = pcall(Chronos.schedule, fuse, fire)
        if ok2 then armed = true end
    end
    if not armed then
        slot._twistArmed = nil
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("IchaUI: fire twist follow failed (no delay timer)")
        end
    end
end

function IchaUITotems_CastFireTwist()
    local follow = IchaUITotems_TwistFollowBase()
    if not follow then
        local act = getActive("fire")
        if act then castTotem(act) end
        return
    end
    local now = GetTime and GetTime() or 0
    local slot = slots["fire"]
    if slot and slot._twistNovaAt and (now - slot._twistNovaAt) < 0.35 then
        return
    end
    local function castNova(queueFollow)
        if not IchaUITotems_FireNovaReady() then return end
        if slot then slot._twistNovaAt = now end
        if castTotem("Fire Nova Totem") then
            if queueFollow then
                IchaUITotems_QueueTwistFollow(follow)
            end
        end
    end
    if IchaUITotems_FireTotemLive("Searing Totem") or IchaUITotems_FireTotemLive("Magma Totem") then
        -- Block an immediate Searing/Magma drop while they are already down.
        -- castNova still arms the follow when Fire Nova actually casts.
        castNova(true)
        return
    end
    if IchaUITotems_FireTotemLive("Fire Nova Totem") then
        return
    end
    if slot and (slot._twistDue or slot._twistArmed) then
        return
    end
    castNova(true)
end

function IchaUITotems_CycleFireTwist()
    if not IchaUITotems_FireCanTwist() then return end
    local d = db()
    local m = d.fireTwist
    local nxt = nil
    if m ~= "searing" and m ~= "magma" then
        nxt = "searing"
    elseif m == "searing" then
        nxt = "magma"
    end
    d.fireTwist = nxt
    local slot = slots["fire"]
    if slot then
        slot._twistDue = nil
        slot._twistBase = nil
        slot._twistArmed = nil
        slot._twistGen = (slot._twistGen or 0) + 1
        slot._twistExpect = nil
        slot._twistTries = nil
    end
    if applySlotVisuals then applySlotVisuals() end
    if nxt == "searing" then
        totemChat("Fire twist: Fire Nova, then Searing")
    elseif nxt == "magma" then
        totemChat("Fire twist: Fire Nova, then Magma")
    else
        totemChat("Fire twist off")
    end
end

function IchaUITotems_TickFireTwist(now)
    -- Follow-up is armed with C_Timer.After on the keypress. OnUpdate cannot cast.
end

function IchaUITotems_NoteTwistFail()
    -- SPELLCAST_FAILED / INTERRUPTED also fires for Fire Nova, GCD, and a queue
    -- that still lands. Never chat here, and never wipe a totem that just dropped.
    local slot = slots["fire"]
    if not slot or not slot._twistExpect then return end
    local now = GetTime and GetTime() or 0
    if (now - slot._twistExpect) > 1.5 then return end
    local base = slot._twistExpectBase or slot._twistBase
    if base and IchaUITotems_FireTotemLive(base) then
        slot._twistExpect = nil
        slot._twistArmed = nil
        slot._twistGen = (slot._twistGen or 0) + 1
        return
    end
    local L = live["fire"]
    if L and base and L.base == base then
        slot._twistExpect = nil
        slot._twistArmed = nil
        slot._twistGen = (slot._twistGen or 0) + 1
        return
    end
end

function IchaUITotems_PaintFireTwist(slot)
    if not slot or not slot.icon then return end
    if slot.twistOverlay then slot.twistOverlay:Hide() end
    if slot.twistStrips then
        local hi
        for hi = 1, table.getn(slot.twistStrips) do
            if slot.twistStrips[hi] then slot.twistStrips[hi]:Hide() end
        end
    end
    local follow = IchaUITotems_TwistFollowBase()
    if not follow then return end
    local path = "Interface\\AddOns\\IchaUI\\media\\firetwist-searing.tga"
    if follow == "Magma Totem" then
        path = "Interface\\AddOns\\IchaUI\\media\\firetwist-magma.tga"
    end
    local dim = 1
    if slot._pushed then dim = 0.82 end
    -- Texcoords stay as the button form set them (rect crop, round art, circle crop).
    slot.icon:SetTexture(path)
    slot.icon:SetVertexColor(dim, dim, dim, 1)
    if slot.icon.SetDrawLayer then
        slot.icon:SetDrawLayer("ARTWORK")
    end
end

-- Resolve catalog base → spellbook cache entry (index for GetSpellCooldown).
-- Missing this aborted PLAYER_LOGIN at refreshActiveIcons → root stayed Hide()'d.
local function knownEntryFor(base)
    if not base or base == "" or base == "__none__" then return nil end
    ensureKnown()
    return knownCache[base]
end

local function listElementCds(el, act, L)
    ensureKnown()
    local candidates = {}
    local seen = {}
    local function add(b)
        if not b or b == "" or b == "__none__" then return end
        if seen[b] then return end
        seen[b] = true
        table.insert(candidates, b)
    end
    add(act)
    if L and L.base then add(L.base) end
    add(lastCastBase[el])
    local list = CATALOG[el]
    if list then
        local i
        for i = 1, table.getn(list) do
            add(list[i])
        end
    end
    local out = {}
    local byBase = {}
    local i
    for i = 1, table.getn(candidates) do
        local base = candidates[i]
        local entry = knownEntryFor(base)
        local onCd, rem, dur = spellOnCooldown(entry)
        if onCd and rem and rem > 0.35 then
            local row = { base = base, rem = rem, dur = dur or 0 }
            table.insert(out, row)
            byBase[base] = row
        end
    end
    local fb = spellCdFallback[el]
    if fb and fb.start and fb.duration and fb.duration > 1.7 then
        local now = GetTime and GetTime() or 0
        local rem = (fb.start + fb.duration) - now
        if rem > 0.35 and fb.base then
            local b = fb.base
            if byBase[b] then
                if rem > byBase[b].rem then
                    byBase[b].rem = rem
                    byBase[b].dur = fb.duration
                end
            else
                local row = { base = b, rem = rem, dur = fb.duration }
                table.insert(out, row)
                byBase[b] = row
            end
        end
    end
    -- Longest remaining first (simple swap sort; Lua 5.0 safe)
    local n = table.getn(out)
    local a, b
    for a = 1, n - 1 do
        for b = a + 1, n do
            if out[b].rem > out[a].rem then
                local tmp = out[a]
                out[a] = out[b]
                out[b] = tmp
            end
        end
    end
    return out
end

local function hideCdBadges(slot)
    if not slot then return end
    local badges = slot.cdBadges
    if badges then
        local i
        for i = 1, table.getn(badges) do
            local b = badges[i]
            if b then
                b:Hide()
                if b.cdText then b.cdText:SetText("") end
            end
        end
    elseif slot.cdBadge then
        slot.cdBadge:Hide()
        if slot.cdBadge.cdText then slot.cdBadge.cdText:SetText("") end
    end
end

local function paintOneCdBadge(b, base, rem, frameLevel)
    if not b then return end
    local txt
    if rem >= 10 then
        txt = string.format("%.0f", rem)
    else
        txt = string.format("%.1f", rem)
    end
    local tex = (base and iconFor(base)) or nil
    if b.icon then
        if tex then
            b.icon:SetTexture(tex)
        end
    end
    if b.cdText then
        b.cdText:SetText(txt)
        b.cdText:SetTextColor(1.0, 0.82, 0.28)
        if b.cdText.SetShadowColor then
            b.cdText:SetShadowColor(0, 0, 0, 1)
            b.cdText:SetShadowOffset(1, -1)
        end
        b.cdText:Show()
    end
    b:SetFrameLevel(frameLevel)
    b:Show()
end

-- CD above slot: mini badge(s). Skip overwriting castText if pulse/bolt owns it.
-- Multiple catalog CDs in the same element → side-by-side badges centered on the slot.
-- When castTextBusy, lift badges so they sit above the cast/tick timer text.
local function updateCdBadge(slot, el, act, L, castTextBusy)
    if not slot then return end
    local cds = listElementCds(el, act, L)
    local n = table.getn(cds)
    if n <= 0 then
        hideCdBadges(slot)
        if slot.castText and not castTextBusy then
            slot.castText:SetText("")
            slot.castText:Hide()
        end
        return
    end

    -- CD text lives ONLY on the badge (not also above the slot — that was a duplicate)
    if slot.castText and not castTextBusy then
        slot.castText:SetText("")
        slot.castText:Hide()
    end

    local badges = slot.cdBadges
    if not badges then
        -- Legacy single-badge fallback
        if slot.cdBadge and n >= 1 then
            local row = cds[1]
            local tex = (row.base and iconFor(row.base)) or emptyIcon(el)
            if slot.cdBadge.icon then slot.cdBadge.icon:SetTexture(tex) end
            paintOneCdBadge(slot.cdBadge, row.base, row.rem, (slot:GetFrameLevel() or 1) + 25)
            local slotSize = slot._cdBadgeSlotSize or math.floor((cfgSize or 36) * (cfgScale or 1) + 0.5)
            local sz = math.floor(slotSize * (cfgCdBadgeScale or DEFAULT_CD_BADGE_SCALE) + 0.5)
            if sz < 16 then sz = 16 end
            if sz > 48 then sz = 48 end
            local lift = math.max(2, math.floor(sz * 0.12 + 0.5))
            if castTextBusy then lift = lift + CD_BADGE_CAST_LIFT end
            slot.cdBadge:ClearAllPoints()
            slot.cdBadge:SetPoint("BOTTOM", slot, "TOP", 0, lift)
        end
        return
    end

    if n > CD_BADGE_POOL_MAX then n = CD_BADGE_POOL_MAX end

    local slotSize = slot._cdBadgeSlotSize or math.floor((cfgSize or 36) * (cfgScale or 1) + 0.5)
    local sz = math.floor(slotSize * (cfgCdBadgeScale or DEFAULT_CD_BADGE_SCALE) + 0.5)
    if sz < 16 then sz = 16 end
    if sz > 48 then sz = 48 end
    local lift = math.max(2, math.floor(sz * 0.12 + 0.5))
    if castTextBusy then
        lift = lift + CD_BADGE_CAST_LIFT
    end
    local gap = CD_BADGE_GAP
    local fl = (slot:GetFrameLevel() or 1) + 25

    local i
    for i = 1, table.getn(badges) do
        local b = badges[i]
        if i <= n then
            local row = cds[i]
            local tex = (row.base and iconFor(row.base)) or emptyIcon(el)
            if b.icon then b.icon:SetTexture(tex) end
            -- Centered row: grow from center
            local x = (i - (n + 1) / 2) * (sz + gap)
            b:ClearAllPoints()
            b:SetPoint("BOTTOM", slot, "TOP", x, lift)
            paintOneCdBadge(b, row.base, row.rem, fl)
        else
            b:Hide()
            if b.cdText then b.cdText:SetText("") end
        end
    end
end

function applySlotVisuals()
    local now = GetTime and GetTime() or 0
    -- One GUID scan per paint (not per element — WorldFrame:GetChildren is heavy)
    if not pendingRecall then
        local anyLive = false
        local gi
        for gi = 1, table.getn(ELEMENTS) do
            if live[ELEMENTS[gi]] then anyLive = true break end
        end
        if anyLive then refreshTotemGuids() end
    end
    local i
    for i = 1, table.getn(ELEMENTS) do
        local el = ELEMENTS[i]
        local slot = slots[el]
        if slot then
            local L = live[el]
            -- While recalling / suppress window, never paint live timers
            if pendingRecall or now < suppressLiveUntil then
                L = nil
            end
            local remain = 0
            if L and L.start and L.duration then
                local lifeDur = L.duration
                if L.base == "Fire Nova Totem" then
                    lifeDur = fuseFor(L.base, L.duration)
                end
                remain = (L.start + lifeDur) - now
                if remain <= 0 then
                    live[el] = nil
                    liveGuid[el] = nil
                    L = nil
                    remain = 0
                end
            end

            -- Expire live cast window
            local LC = liveCast[el]
            if LC and LC.finish and now >= LC.finish then
                liveCast[el] = nil
                LC = nil
            end

            -- Throw-set selection is highlighted in the DRAWER only (not main bar)
            local act = getActive(el)

            local castTextBusy = false
            -- Twist art is painted below; setting the plain icon first would
            -- redraw a round shape's icon twice per paint.
            local twistArt = el == "fire" and IchaUITotems_TwistFollowBase and IchaUITotems_TwistFollowBase()
            if L and remain > 0 then
                -- LIVE dropped totem
                local tex = L.icon or iconFor(L.base) or emptyIcon(el)
                if not twistArt then slot.icon:SetTexture(tex) end
                slot.icon:SetVertexColor(1, 1, 1, 1)

                local base = L.base
                local per = periodFor(base)
                local iconW = slot.icon:GetWidth() or (cfgSize * cfgScale)
                if iconW < 8 then iconW = cfgSize * cfgScale * 0.56 end

                -- Duration in center; red when THIS totem is out of range;
                -- flash when under 10s remaining (in range)
                slot.timer:SetText(formatTime(remain))
                local inRange = totemInRange(el, TOTEM_KEEP_RANGE)
                slot._recallLive = true
                slot._recallInRange = (inRange == true)
                slot._recallRed = (inRange == false)
                if inRange == false then
                    slot.timer:SetTextColor(1, 0, 0)
                    if slot.timer.SetAlpha then slot.timer:SetAlpha(1) end
                elseif remain < 10 then
                    -- ~2.5 Hz blink between bright warning and dim gold
                    local on = (math.mod(math.floor(now * 5), 2) == 0)
                    if on then
                        slot.timer:SetTextColor(1.0, 0.45, 0.12)
                        if slot.timer.SetAlpha then slot.timer:SetAlpha(1) end
                    else
                        slot.timer:SetTextColor(1.0, 0.92, 0.65)
                        if slot.timer.SetAlpha then slot.timer:SetAlpha(0.35) end
                    end
                else
                    slot.timer:SetTextColor(1, 0.92, 0.65)
                    if slot.timer.SetAlpha then slot.timer:SetAlpha(1) end
                end
                slot.timer:Show()

                if FIRE_CAST_TOTEMS[base] then
                    -- Searing: thin cast ring + tip spark during liveCast bolt window
                    slot.pulse:Hide()
                    slot.periodBar:Hide()
                    slot.periodBar:SetWidth(1)
                    if slot.castText then
                        slot.castText:SetText("")
                        slot.castText:Hide()
                    end
                    if LC and LC.fromEvent and LC.start and LC.finish and now < LC.finish then
                        local dur = LC.finish - LC.start
                        if dur < 0.05 then dur = 0.05 end
                        local elapsed = now - LC.start
                        if elapsed < 0 then elapsed = 0 end
                        if elapsed > dur then elapsed = dur end
                        -- Cast bar fills as cast progresses (elapsed/dur)
                        setCastRing(slot, elapsed / dur, base)
                        -- Ring is on the icon; do not lift CD badges (castText hidden)
                    else
                        hideCastRing(slot)
                    end
                elseif FIRE_LIFETIME_RING and FIRE_LIFETIME_RING[base] then
                    -- Fire Nova fuse: fill until detonate (4s, -1s/rank Imp Fire Totems), not buff life 5s
                    slot.periodBar:Hide()
                    slot.periodBar:SetWidth(1)
                    slot.pulse:Hide()
                    if slot.castText then
                        slot.castText:SetText("")
                        slot.castText:Hide()
                    end
                    local dur = fuseFor(base, L.duration)
                    if dur < 0.05 then dur = 0.05 end
                    local elapsed = now - (L.start or now)
                    if elapsed < 0 then elapsed = 0 end
                    if elapsed > dur then elapsed = dur end
                    setCastRing(slot, elapsed / dur, base)
                    -- Fuse ring on icon only — lifting CD badges made Fire Nova CD jump up then drop after detonate
                elseif per and per > 0 then
                    -- Pulse totems: thin ring + spark (Magma, Mana Spring, Tremor, cleanses)
                    slot.periodBar:Hide()
                    slot.periodBar:SetWidth(1)
                    slot.pulse:Hide()
                    if slot.castText then
                        slot.castText:SetText("")
                        slot.castText:Hide()
                    end
                    local elapsed = math.mod(now - L.start, per)
                    if elapsed < 0 then elapsed = 0 end
                    local pct = elapsed / per
                    if pct > 1 then pct = 1 end
                    setCastRing(slot, pct, base)
                    -- Pulse ring on icon; keep CD badges at normal height
                else
                    slot.pulse:Hide()
                    slot.periodBar:Hide()
                    slot.periodBar:SetWidth(1)
                    hideCastRing(slot)
                    if slot.castText then slot.castText:Hide() end
                end
            else
                -- Not live: show throw-set active icon (or skull), clear timers
                slot._recallLive = false
                slot._recallInRange = false
                slot._recallRed = false
                wipeSlotTimers(slot)
                liveCast[el] = nil
                if twistArt then
                    slot.icon:SetVertexColor(1, 1, 1, 1)
                elseif act then
                    slot.icon:SetTexture(iconFor(act))
                    slot.icon:SetVertexColor(1, 1, 1, 1)
                else
                    slot.icon:SetTexture(emptyIcon(el))
                    slot.icon:SetVertexColor(1, 1, 1, 1)
                end
            end
            updateCdBadge(slot, el, act, live[el], castTextBusy)
            if slot._pushed and slot.icon then
                slot.icon:SetVertexColor(0.82, 0.82, 0.82)
            end
            if el == "fire" and IchaUITotems_PaintFireTwist then
                IchaUITotems_PaintFireTwist(slot)
            end
        end
        -- Shift-to-open: open while hovering if Shift held
        local slot = slots[el]
        if slot and slot._drawerHover then
            local act = getActive(el)
            slot._ichaTipSpell = act
        end
        if slot and slot._drawerHover and canHoverOpenDrawer() then
            local dr = drawers[el]
            if dr and not dr:IsShown() then
                showDrawer(el, false)
            end
        elseif cfgShiftDrawer and slot and slot._drawerHover and not canHoverOpenDrawer() then
            local dr = drawers[el]
            if dr and dr:IsShown() and not pinned[el] then
                hideDrawer(el)
            end
        end
        if closeAt[el] and not pinned[el] then
            if now >= closeAt[el] then
                local dr = drawers[el]
                if dr and dr:IsShown() then
                    hideDrawer(el)
                else
                    closeAt[el] = nil
                end
            end
        end
    end
end


local function sizeOneCdBadge(b, sz)
    if not b then return end
    b:SetWidth(sz)
    b:SetHeight(sz)
    if b.icon then
        insetIcon(b.icon, b, sz)
    end
    if b.roundMask then
        b.roundMask:ClearAllPoints()
        b.roundMask:SetPoint("TOPLEFT", b.icon, "TOPLEFT", 0, 0)
        b.roundMask:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 0, 0)
        b.roundMask:SetTexture(ROUNDMASK)
        b.roundMask:SetVertexColor(0, 0, 0, 1)
        b.roundMask:Show()
    end
    if b.ring then
        applyGoldRing(b.ring, b, sz)
    end
    if b.cdText then
        local fp = GameFontHighlightSmall:GetFont()
        local baseText = DEFAULT_TEXT
        if not baseText or baseText < 1 then baseText = 11 end
        local fs = math.floor(sz * 0.38 * ((cfgText or baseText) / baseText) + 0.5)
        if fs < 6 then fs = 6 end
        if fp then b.cdText:SetFont(fp, fs, "THICKOUTLINE") end
        b.cdText:SetTextColor(1.0, 0.82, 0.28)
        if b.cdText.SetShadowColor then
            b.cdText:SetShadowColor(0, 0, 0, 1)
            b.cdText:SetShadowOffset(1, -1)
        end
        b.cdText:ClearAllPoints()
        b.cdText:SetPoint("CENTER", b, "CENTER", 0, 0)
    end
end

local function sizeCdBadge(slot, slotSize)
    if not slot then return end
    slot._cdBadgeSlotSize = slotSize
    local sz = math.floor((slotSize or 36) * (cfgCdBadgeScale or DEFAULT_CD_BADGE_SCALE) + 0.5)
    if sz < 16 then sz = 16 end
    if sz > 48 then sz = 48 end
    local badges = slot.cdBadges
    if badges then
        local i
        for i = 1, table.getn(badges) do
            sizeOneCdBadge(badges[i], sz)
        end
    elseif slot.cdBadge then
        sizeOneCdBadge(slot.cdBadge, sz)
        -- Default single-badge anchor (updateCdBadge overrides when shown)
        local lift = math.max(2, math.floor(sz * 0.12 + 0.5))
        slot.cdBadge:ClearAllPoints()
        slot.cdBadge:SetPoint("BOTTOM", slot, "TOP", 0, lift)
    end
end

local function layoutBar()
    if not root then return end
    local size = math.floor(cfgSize * cfgScale + 0.5)
    local bsc = 1
    if IchaUI_DrawerButtonScale then bsc = IchaUI_DrawerButtonScale("totems") end
    size = math.floor(size * bsc + 0.5)
    local formShape = "circle"
    if IchaUI_DrawerShape then formShape = IchaUI_DrawerShape("totems") end
    local slotW = size
    if formShape == "rect" then slotW = math.floor(size * 4 / 3 + 0.5) end
    local gap = math.floor(cfgGap * cfgScale + 0.5)
    local n = table.getn(ELEMENTS)
    local totalW = n * slotW + (n - 1) * gap
    local totalH = size + 36
    root:SetWidth(totalW)
    root:SetHeight(totalH)

    local i
    for i = 1, n do
        local el = ELEMENTS[i]
        local slot = slots[el]
        if slot then
            slot:SetWidth(slotW)
            slot:SetHeight(size)
            slot:ClearAllPoints()
            slot:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", (i - 1) * (slotW + gap), 0)

            -- Shrink icon into the circle hole, then cover corners with TrackingBorder
            insetIcon(slot.icon, slot, size)

            if slot.roundMask then
                slot.roundMask:ClearAllPoints()
                slot.roundMask:SetPoint("TOPLEFT", slot.icon, "TOPLEFT", 0, 0)
                slot.roundMask:SetPoint("BOTTOMRIGHT", slot.icon, "BOTTOMRIGHT", 0, 0)
                slot.roundMask:SetVertexColor(0, 0, 0, 1)
                slot.roundMask:SetTexture(ROUNDMASK)
                slot.roundMask:Show()
            end

            if slot.border then
                applyGoldBorder(slot.border, slot)
            end
            if slot.goldRing then
                applyGoldRing(slot.goldRing, slot, size)
            end
            if IchaUI_WrapButtonIcon then IchaUI_WrapButtonIcon(slot) end
            if IchaUI_ApplyButtonForm then IchaUI_ApplyButtonForm(slot, formShape) end

            -- Duration on the icon; cast/tick text ABOVE the slot (ring stays on slot)
            slot.timer:ClearAllPoints()
            slot.timer:SetPoint("CENTER", slot.icon, "CENTER", 0, 0)
            local fontPath, _, fontFlags = GameFontHighlightSmall:GetFont()
            local fs = math.max(6, math.floor(cfgText * cfgScale + 0.5))
            if fontPath then
                slot.timer:SetFont(fontPath, fs, "THICKOUTLINE")
                if slot.timer.SetShadowColor then
                    slot.timer:SetShadowColor(0, 0, 0, 1)
                    slot.timer:SetShadowOffset(1, -1)
                end
            end

            -- Pulse + leftover period bar on the slot (do not follow icon nudge)
            slot.periodBar:ClearAllPoints()
            slot.periodBar:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", 1, 1)
            slot.periodBar:SetHeight(3)
            slot.periodBar:SetWidth(1)

            slot.pulse:ClearAllPoints()
            slot.pulse:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
            slot.pulse:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 0, 0)

            -- Main bar: no selection glow (drawer shows throw-set pick)
            if slot.activeGlow then
                slot.activeGlow:Hide()
            end

            if slot.castText then
                slot.castText:ClearAllPoints()
                slot.castText:SetPoint("BOTTOM", slot, "TOP", 0, 2)
                local fontPath2, _, fontFlags2 = GameFontHighlightSmall:GetFont()
                local cfs = math.max(6, math.floor(cfgText * cfgScale * 0.85 + 0.5))
                if fontPath2 then
                    slot.castText:SetFont(fontPath2, cfs, "THICKOUTLINE")
                    if slot.castText.SetShadowColor then
                        slot.castText:SetShadowColor(0, 0, 0, 1)
                        slot.castText:SetShadowOffset(1, -1)
                    end
                end
            end
            -- Cast ring only via setCastRing (don't abort bar layout)
            if killCastCooldown then pcall(killCastCooldown, slot) end
            if slot.cdBadges or slot.cdBadge then
                pcall(function() sizeCdBadge(slot, size) end)
            end
            slot:Show()
        end
    end
    if mover then
        mover:SetAllPoints(root)
    end
    if IchaUITotemSets.LayoutArrows then pcall(IchaUITotemSets.LayoutArrows, size, gap) end
    if IchaUI_ApplyTotemStrata then IchaUI_ApplyTotemStrata() end
end

-- Size/center CD badge like a mini totem circle (icon inside TrackingBorder hole)
local function makeSlot(element)
    local slot = CreateFrame("Button", "IchaUITotem_" .. element, root)
    slot:EnableMouse(true)
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot.element = element

    -- Black circular plate under the icon (hides square corners behind the ring)
    local circleBg = slot:CreateTexture(nil, "BACKGROUND")
    circleBg:SetTexture("Interface\\AddOns\\IchaUI\\media\\circledisc.tga")
    circleBg:SetVertexColor(0.05, 0.05, 0.06, 1)
    slot.circleBg = circleBg

    local icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon = icon

    -- Legacy Tooltip border frame kept hidden
    local border = CreateFrame("Frame", nil, slot)
    border:Hide()
    slot.border = border

    -- Extra black corner mask on top of icon (backup if TrackingBorder gaps)
    local round = slot:CreateTexture(nil, "ARTWORK")
    round:SetTexture(ROUNDMASK)
    round:SetVertexColor(0, 0, 0, 1)
    round:Show()
    slot.roundMask = round

    -- Built-in circular Minimap tracking border (opaque corners crop the icon)
    local goldRing = slot:CreateTexture(nil, "OVERLAY")
    goldRing:SetTexture(GOLD_RING)
    IchaUI_PaintGoldRing(goldRing)
    slot.goldRing = goldRing

    local pushTex = slot:CreateTexture(nil, "OVERLAY")
    pushTex:SetTexture("Interface/ChatFrame/ChatFrameBackground")
    pushTex:SetVertexColor(0, 0, 0)
    pushTex:SetAlpha(0.18)
    pushTex:Hide()
    slot.pushTex = pushTex

    -- Duration / cast text. Strata follows the drawer (IchaUI_ApplyTotemStrata).
    local timerFrame = CreateFrame("Frame", nil, slot)
    timerFrame:SetAllPoints(slot)
    slot.timerFrame = timerFrame
    local timer = timerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timer:SetTextColor(1, 0.92, 0.65)
    do
        local fp, fsz = GameFontHighlightSmall:GetFont()
        if fp then timer:SetFont(fp, fsz or 12, "THICKOUTLINE") end
        if timer.SetShadowColor then
            timer:SetShadowColor(0, 0, 0, 1)
            timer:SetShadowOffset(1, -1)
        end
    end
    timer:Hide()
    slot.timer = timer

    local pulse = slot:CreateTexture(nil, "OVERLAY")
    pulse:SetTexture("Interface/Buttons/ButtonHilight-Square")
    pulse:SetBlendMode("ADD")
    pulse:SetAlpha(0)
    pulse:Hide()
    slot.pulse = pulse

    local periodBar = slot:CreateTexture(nil, "OVERLAY")
    periodBar:SetTexture("Interface/TargetingFrame/UI-StatusBar")
    periodBar:SetVertexColor(1, 0.55, 0.1, 0.95)
    periodBar:Hide()
    slot.periodBar = periodBar

    -- Soft gold glow inside the circle when throw-set totem is selected
    local activeGlow = slot:CreateTexture(nil, "OVERLAY")
    activeGlow:SetTexture("Interface/Buttons/UI-ActionButton-Border")
    activeGlow:SetBlendMode("ADD")
    activeGlow:SetVertexColor(1.0, 0.82, 0.28, 1) -- yellow-gold
    activeGlow:SetAlpha(0)
    activeGlow:Hide()
    slot.activeGlow = activeGlow

    -- NEVER CreateFrame("Cooldown") here — prior builds left slot.cd=nil on purpose
    -- (square wipe + some clients abort slot create). Cast/tick uses ring+spark only.
    slot.cd = nil
    -- castRingBg / castSegs / castSpark created lazily in ensureCastRing

    -- Cast/tick text above icon (same strata as duration; hidden when ring is active)
    local castText = timerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    castText:SetPoint("BOTTOM", slot, "TOP", 0, 2)
    castText:SetTextColor(1, 1, 1) -- white
    do
        local fp, fsz = GameFontHighlightSmall:GetFont()
        if fp then castText:SetFont(fp, fsz or 11, "THICKOUTLINE") end
        if castText.SetShadowColor then
            castText:SetShadowColor(0, 0, 0, 1)
            castText:SetShadowOffset(1, -1)
        end
    end
    castText:Hide()
    slot.castText = castText

    local label = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER", slot, "CENTER", 0, 0)
    label:SetText("")
    slot.elLabel = label


    -- Mini circular CD badge pool (same crop as main totem: inset icon + TrackingBorder).
    -- Multiple element CDs share the slot; badges grow side-by-side from center.
    slot.cdBadges = {}
    do
        local bi
        for bi = 1, CD_BADGE_POOL_MAX do
            local cdBadge = CreateFrame("Frame", nil, slot)
            cdBadge:SetWidth(26)
            cdBadge:SetHeight(26)
            cdBadge:SetPoint("BOTTOM", slot, "TOP", 0, 4)
            cdBadge:SetFrameLevel((slot:GetFrameLevel() or 1) + 25)
            cdBadge:EnableMouse(false)
            cdBadge:Hide()
            local cdBg = cdBadge:CreateTexture(nil, "BACKGROUND")
            cdBg:SetTexture("Interface\\AddOns\\IchaUI\\media\\circledisc.tga")
            cdBg:SetVertexColor(0.05, 0.05, 0.06, 1)
            cdBadge.circleBg = cdBg
            local cdIcon = cdBadge:CreateTexture(nil, "ARTWORK")
            cdBadge.icon = cdIcon
            local cdMask = cdBadge:CreateTexture(nil, "ARTWORK")
            cdMask:SetTexture(ROUNDMASK)
            cdMask:SetVertexColor(0, 0, 0, 1)
            cdMask:Show()
            cdBadge.roundMask = cdMask
            local cdRing = cdBadge:CreateTexture(nil, "OVERLAY")
            cdRing:SetTexture(GOLD_RING)
            IchaUI_PaintGoldRing(cdRing)
            cdBadge.ring = cdRing
            local cdText = cdBadge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cdText:SetPoint("CENTER", cdBadge, "CENTER", 0, 0)
            cdText:SetTextColor(1.0, 0.82, 0.28)
            cdBadge.cdText = cdText
            table.insert(slot.cdBadges, cdBadge)
        end
    end
    slot.cdBadge = slot.cdBadges[1] -- compat alias (first badge)

    slot:SetScript("OnMouseDown", function()
        pushCircleSlot(this)
    end)
    slot:SetScript("OnMouseUp", function()
        if not this._bindPushUntil then
            releaseCircleSlot(this)
        end
    end)
    slot:SetScript("OnEnter", function()
        closeAt[this.element] = nil
        this._drawerHover = true
        if canHoverOpenDrawer() then
            showDrawer(this.element, false)
        end
        local act = getActive(this.element)
        this._ichaTipSpell = act
        this._ichaTipShown = nil
        if act and IsShiftKeyDown and IsShiftKeyDown() then
            showSpellTip(this, act)
            this._ichaTipShown = true
        end
        this:SetScript("OnUpdate", tipUpdateCheck)
    end)
    slot:SetScript("OnLeave", function()
        this._drawerHover = nil
        this._ichaTipSpell = nil
        this._ichaTipShown = nil
        this:SetScript("OnUpdate", nil)
        hideSpellTip()
        if not this._bindPushUntil then
            releaseCircleSlot(this)
        end
        if not pinned[this.element] then
            closeAt[this.element] = (GetTime and GetTime() or 0) + DRAWER_CLOSE_DELAY
        end
    end)
    slot:SetScript("OnClick", function()
        local el = this.element
        local function openDrawerUnpinned()
            -- Never pin from the slot — pinned drawers ignore mouse-leave and stay forever
            local dr = drawers[el]
            if dr and dr:IsShown() then
                hideDrawer(el)
                return
            end
            showDrawer(el, false)
        end
        if arg1 == "LeftButton" then
            local act = getActive(el)
            if act then
                if el == "fire" and IchaUITotems_CastFireTwist then
                    IchaUITotems_CastFireTwist()
                else
                    castTotem(act)
                end
            else
                if cfgShiftDrawer and not (IsShiftKeyDown and IsShiftKeyDown()) then
                    totemChat("Hold Shift and click to open the " .. ELEMENT_LABEL[el] .. " drawer.")
                    return
                end
                openDrawerUnpinned()
                totemChat("No active " .. ELEMENT_LABEL[el] .. " totem — right-click a totem in the drawer to set.")
            end
        elseif arg1 == "RightButton" then
            if el == "fire" and IchaUITotems_FireCanTwist and IchaUITotems_FireCanTwist() then
                if IchaUITotems_CycleFireTwist then
                    IchaUITotems_CycleFireTwist()
                end
                return
            end
            -- Shift-drawer mode: right-click also needs Shift (same as hover)
            if cfgShiftDrawer and not (IsShiftKeyDown and IsShiftKeyDown()) then
                return
            end
            openDrawerUnpinned()
        end
    end)

    icon:SetTexture(emptyIcon(element))
    icon:SetVertexColor(1, 1, 1, 1)

    slots[element] = slot

    -- drawer: no backdrop — icons only, vertical stack
    local dr = CreateFrame("Frame", "IchaUITotemDrawer_" .. element, UIParent)
    dr:SetWidth(40)
    dr:SetHeight(40)
    dr:EnableMouse(true)
    dr:Hide()
    dr.element = element
    dr:SetScript("OnEnter", function()
        closeAt[this.element] = nil
    end)
    dr:SetScript("OnLeave", function()
        if not pinned[this.element] then
            closeAt[this.element] = (GetTime and GetTime() or 0) + DRAWER_CLOSE_DELAY
        end
    end)
    drawers[element] = dr

    return slot
end

local function refreshActiveIcons()
    applySlotVisuals()
end

local function restorePos()
    local d = db()
    root:ClearAllPoints()
    if d.point and d.x then
        root:SetPoint(d.point, UIParent, d.relPoint or d.point, d.x, d.y)
    else
        root:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 160)
    end
end

local function setMove(on)
    moving = on and true or false
    local d = db()
    d.moving = moving
    if moving then
        mover:Show()
        DEFAULT_CHAT_FRAME:AddMessage("Totem bar move on — drag it, /icha totems move to lock.")
    else
        mover:Hide()
        savePos()
        DEFAULT_CHAT_FRAME:AddMessage("Totem bar locked.")
    end
end

local totemTestMode = false

local _totemVisDiagPrinted = nil
local function updateVisibility()
    isShaman = isPlayerShaman()
    local d = db()
    if totemTestMode then
        root:Show()
        return
    end
    if not isShaman then
        root:Hide()
        local i
        for i = 1, table.getn(ELEMENTS) do
            hideDrawer(ELEMENTS[i])
        end
        return
    end
    if d.hidden then
        root:Hide()
    else
        root:Show()
    end
    -- One-shot diagnose if shaman bar still not shown (sticky hidden / parent / error)
    if not _totemVisDiagPrinted and DEFAULT_CHAT_FRAME then
        local shown = root and root.IsShown and root:IsShown()
        if isShaman and not d.hidden and not shown then
            _totemVisDiagPrinted = true
            DEFAULT_CHAT_FRAME:AddMessage(
                "IchaUI Totems: shaman but bar hidden (forced Show). Check /icha totems show"
            )
            root:Show()
        elseif isShaman and d.hidden then
            _totemVisDiagPrinted = true
            DEFAULT_CHAT_FRAME:AddMessage(
                "IchaUI Totems: hidden via setting — /icha totems show to restore"
            )
        end
    end
end

-- Turtle: totem schools share no GCD — cast the whole set in one shot
-- (same as when this worked; queue/GCD logic was the regression).
local function processThrow(now)
    -- kept for OnUpdate callers; queue unused for throw-set
    if table.getn(throwQueue) == 0 then
        throwBusy = false
        return
    end
    local i
    for i = 1, table.getn(throwQueue) do
        castEntry(throwQueue[i])
    end
    throwQueue = {}
    throwBusy = false
end

local function onThrowCastFinished()
    throwBusy = false
end

local lastThrowFireAt = 0

-- One press: every element in `picks` (element→base, nil = bar page) that is
-- dead, out of range or a different totem is recast; matching in-range lives
-- are kept. Throw current / per-set / throw-all all go through here.
function IchaUITotemSets.Throw(picks)
    IchaUITotemSets.override = nil
    if not isPlayerShaman() then
        return
    end
    local now = GetTime and GetTime() or 0
    if (now - lastThrowFireAt) < PUSH_MS then
        return
    end
    lastThrowFireAt = now
    IchaUITotemSets.override = picks
    ensureKnown()
    local castList = {}
    local kept = 0
    local i
    -- Replace dead / OOR / mismatched lives; keep only matching in-range set totems
    for i = 1, table.getn(ELEMENTS) do
        local el = ELEMENTS[i]
        local act = getActive(el)
        if act then
            -- Fire twist uses the same hardware path as a left-click on the fire slot.
            -- Do not also queue the set fire totem, and do not clear live fire first
            -- (CastFireTwist needs that to skip a recast of Searing/Magma).
            if el == "fire" and IchaUITotems_FireTwistMode and IchaUITotems_FireTwistMode()
                and IchaUITotems_CastFireTwist then
                bindPush(slots[el])
                IchaUITotems_CastFireTwist()
            else
                local L = live[el]
                local liveOk = false
                if L and L.start and L.duration then
                    if ((L.start + L.duration) - now) > 0.2 then
                        liveOk = true
                    end
                end
                local inRange = nil
                if liveOk then
                    inRange = totemInRange(el, TOTEM_KEEP_RANGE)
                end
                -- Keep only if live matches the throw-set pick AND still in range
                local sameAsSet = liveOk and L and L.base and act and (L.base == act)
                if sameAsSet and inRange == true then
                    kept = kept + 1
                else
                    -- Dead, OOR, or different totem than active set → re-drop the set pick
                    local entry = queueEntryFor(act)
                    if entry then
                        table.insert(castList, entry)
                        bindPush(slots[el])
                        live[el] = nil
                        liveCast[el] = nil
                        if liveGuid then liveGuid[el] = nil end
                    end
                end
            end
        end
    end
    local nq = table.getn(castList)
    -- Fire every school immediately (no shared GCD on Turtle)
    for i = 1, nq do
        castEntry(castList[i])
    end
    IchaUITotemSets.override = nil
end

function IchaUITotems_ThrowSet()
    IchaUITotemSets.Throw(nil)
end

function IchaUITotems_ThrowSetN(n)
    n = tonumber(n)
    if not n then return end
    local t = IchaUITotemSets.Table(n)
    if not t then return end
    if n == IchaUITotemSets.Page() then
        IchaUITotemSets.Throw(nil)
    else
        IchaUITotemSets.Throw(t)
    end
end

-- Key Bindings menu reads BINDING_NAME_* when drawn: name the live sets,
-- mark unused pool slots.
function IchaUITotemSets.BindingLabels()
    local n = IchaUITotemSets.Count()
    local k
    for k = 1, IchaUITotemSets.MAX_BINDS do
        if k <= n then
            setglobal("BINDING_NAME_ICHA_THROWTOTEMSET" .. k, "Throw Totem Set " .. k .. ": " .. IchaUITotemSets.Name(k))
        else
            setglobal("BINDING_NAME_ICHA_THROWTOTEMSET" .. k, "Throw Totem Set " .. k .. " (not created)")
        end
    end
end

-- Page changed / set edited: repaint bar, open drawers, arrows, config.
function IchaUITotemSets.Changed()
    IchaUITotemSets.override = nil
    pcall(IchaUITotemSets.BindingLabels)
    if applySlotVisuals then pcall(applySlotVisuals) end
    local i
    for i = 1, table.getn(ELEMENTS) do
        local dr = drawers[ELEMENTS[i]]
        if dr and dr.IsShown and dr:IsShown() then
            pcall(buildDrawerRows, ELEMENTS[i])
        end
    end
    if IchaUITotemSets.RefreshArrows then IchaUITotemSets.RefreshArrows() end
    if IchaUI_TotemSetsRefresh then pcall(IchaUI_TotemSetsRefresh) end
end

function IchaUITotemSets.SetPage(idx)
    local d, n = IchaUITotemSets.Norm()
    idx = tonumber(idx) or 1
    idx = math.floor(idx)
    -- wrap
    idx = math.mod(idx - 1, n)
    if idx < 0 then idx = idx + n end
    d.setPage = idx + 1
    IchaUITotemSets.Changed()
    return d.setPage
end

function IchaUITotemSets.Step(delta)
    return IchaUITotemSets.SetPage(IchaUITotemSets.Page() + (tonumber(delta) or 1))
end

-- New sets start as a copy of the bar page so one element can be tweaked.
function IchaUITotemSets.Add(name)
    local d, n = IchaUITotemSets.Norm()
    local src = IchaUITotemSets.Table(nil) or {}
    local copy = {}
    local i
    for i = 1, table.getn(ELEMENTS) do
        local el = ELEMENTS[i]
        if IchaUITotemSets.Pick(src, el) then copy[el] = src[el] end
    end
    if type(name) ~= "string" or name == "" then name = "Set " .. (n + 1) end
    table.insert(d.extraSets, { name = name, active = copy })
    IchaUITotemSets.Changed()
    return n + 1
end

-- Removing set 1 promotes set 2 into the legacy d.active / d.set1Name keys.
function IchaUITotemSets.Remove(idx)
    local d, n = IchaUITotemSets.Norm()
    idx = tonumber(idx)
    if not idx or n < 2 or idx < 1 or idx > n then return false end
    if idx == 1 then
        local s = d.extraSets[1]
        d.active = s.active
        d.set1Name = s.name
        table.remove(d.extraSets, 1)
    else
        table.remove(d.extraSets, idx - 1)
    end
    if d.setPage > idx then
        d.setPage = d.setPage - 1
    elseif d.setPage == idx and d.setPage > n - 1 then
        d.setPage = n - 1
    end
    IchaUITotemSets.Norm()
    IchaUITotemSets.Changed()
    return true
end

function IchaUITotemSets.Rename(idx, name)
    local d, n = IchaUITotemSets.Norm()
    idx = tonumber(idx)
    if not idx or idx < 1 or idx > n then return end
    if type(name) ~= "string" then return end
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    if name == "" then name = "Set " .. idx end
    if idx == 1 then
        d.set1Name = name
    else
        d.extraSets[idx - 1].name = name
    end
    IchaUITotemSets.Changed()
end

function IchaUITotemSets.SetPick(idx, element, base)
    local t = IchaUITotemSets.Table(idx)
    if not t or not CLASSIC_SLOT[element] then return end
    if not base or base == "" or base == "__none__" then
        t[element] = nil
    else
        t[element] = base
    end
    IchaUITotemSets.Changed()
end

-- Picker cycle for config: none → each known (else catalog) totem → none.
function IchaUITotemSets.CyclePick(idx, element, dir)
    local t = IchaUITotemSets.Table(idx)
    local list = CATALOG[element]
    if not t or not list then return end
    ensureKnown()
    local opts = { "__none__" }
    local i
    local anyKnown = false
    for i = 1, table.getn(list) do
        if knownCache[list[i]] then anyKnown = true end
    end
    for i = 1, table.getn(list) do
        if knownCache[list[i]] or not anyKnown then table.insert(opts, list[i]) end
    end
    local cur = IchaUITotemSets.Pick(t, element) or "__none__"
    local at = 1
    for i = 1, table.getn(opts) do
        if opts[i] == cur then at = i end
    end
    local m = table.getn(opts)
    at = math.mod(at - 1 + (dir or 1) + m, m) + 1
    IchaUITotemSets.SetPick(idx, element, opts[at])
end

-- Dropdown rows for the config picker, same list as CyclePick:
-- { base, label, nil, icon }; "__none__" clears the slot.
function IchaUITotemSets.PickOpts(element)
    local out = { { "__none__", "(none)", nil, emptyIcon(element) } }
    local list = CATALOG[element]
    if not list then return out end
    ensureKnown()
    local anyKnown = false
    local i
    for i = 1, table.getn(list) do
        if knownCache[list[i]] then anyKnown = true end
    end
    for i = 1, table.getn(list) do
        if knownCache[list[i]] or not anyKnown then
            table.insert(out, { list[i], list[i], nil, iconFor(list[i]) })
        end
    end
    return out
end

function IchaUITotemSets.Icon(base, element)
    if not base then return emptyIcon(element) end
    return iconFor(base)
end

-- Per-set keybinds. Bindings.xml is static: fixed pool
-- ICHA_THROWTOTEMSET1..MAX_BINDS. Keys saved in d.setBinds[cmd].
IchaUITotemSets.MAX_BINDS = 10
IchaUITotemSets.chords = {}

-- Next-set key: same paging as the right arrow; never casts.
function IchaUITotems_NextSet()
    if IchaUITotemSets.Count() < 2 then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("IchaUI: only one totem set — add more in /iui → Drawers.")
        end
        return
    end
    IchaUITotemSets.Step(1)
end

function IchaUITotemSets.BindCmd(which)
    if which == "current" then return "ICHA_THROWTOTEMS" end
    if which == "next" then return "ICHA_TOTEMSETNEXT" end
    local n = tonumber(which)
    if n and n >= 1 and n <= IchaUITotemSets.MAX_BINDS then
        return "ICHA_THROWTOTEMSET" .. n
    end
    return nil
end

function IchaUITotemSets.FireCmd(cmd)
    if cmd == "ICHA_THROWTOTEMS" then
        IchaUITotems_ThrowSet()
    elseif cmd == "ICHA_TOTEMSETNEXT" then
        IchaUITotems_NextSet()
    elseif cmd and string.find(cmd, "ICHA_THROWTOTEMSET", 1, true) == 1 then
        IchaUITotems_ThrowSetN(tonumber(string.sub(cmd, 19)))
    end
end

function IchaUITotems_GetSetBindKey(which)
    if which == "current" then return IchaUITotems_GetThrowKey() end
    local cmd = IchaUITotemSets.BindCmd(which)
    if not cmd then return "" end
    local d = db()
    if type(d.setBinds) ~= "table" then d.setBinds = {} end
    if GetBindingKey then
        local k = GetBindingKey(cmd)
        if k and k ~= "" then
            d.setBinds[cmd] = k
            return k
        end
    end
    return d.setBinds[cmd] or ""
end

function IchaUITotems_ApplySetBindKey(which, key)
    if which == "current" then return IchaUITotems_SetThrowKey(key) end
    local cmd = IchaUITotemSets.BindCmd(which)
    if not cmd then return "" end
    local d = db()
    if type(d.setBinds) ~= "table" then d.setBinds = {} end
    if not key then key = "" end
    key = string.gsub(key, "^%s+", "")
    key = string.gsub(key, "%s+$", "")
    if key ~= "" then key = string.upper(key) end
    d.setBinds[cmd] = key
    clearThrowCmdKeys(cmd)
    if key ~= "" and (not isButtonMouseKey(key)) and SetBinding then
        SetBinding(key, cmd)
    end
    saveThrowBindSet()
    IchaUI_MouseChordActions = IchaUI_MouseChordActions or {}
    local old = IchaUITotemSets.chords[cmd]
    if old and IchaUI_MouseChordActions[old] then IchaUI_MouseChordActions[old] = nil end
    IchaUITotemSets.chords[cmd] = nil
    if key ~= "" and isThrowMouseKey(key) then
        IchaUITotemSets.chords[cmd] = key
        IchaUI_MouseChordActions[key] = function() IchaUITotemSets.FireCmd(cmd) end
    end
    return key
end

function IchaUITotemSets.ApplyBindings()
    -- Retired throw-all command: drop its saved key and any live binding.
    local d = db()
    if type(d.setBinds) == "table" and d.setBinds.ICHA_THROWTOTEMSALL ~= nil then
        d.setBinds.ICHA_THROWTOTEMSALL = nil
        pcall(clearThrowCmdKeys, "ICHA_THROWTOTEMSALL")
        pcall(saveThrowBindSet)
    end
    local n
    IchaUITotems_ApplySetBindKey("next", IchaUITotems_GetSetBindKey("next"))
    for n = 1, IchaUITotemSets.MAX_BINDS do
        IchaUITotems_ApplySetBindKey(n, IchaUITotems_GetSetBindKey(n))
    end
    pcall(IchaUITotemSets.BindingLabels)
end

-- Bar paging arrows (only with 2+ sets). Same caret art and paint path as
-- the minimap drawer handle / mob stats caret: native left glyph, mirrored
-- for right. Extensionless path first — this client can drop a .tga
-- SetTexture after /reload and leave the green missing-texture tile.
IchaUITotemSets.ARROW_UP = "Interface\\AddOns\\IchaUI\\media\\Arrow-Left-Up"
IchaUITotemSets.ARROW_DOWN = "Interface\\AddOns\\IchaUI\\media\\Arrow-Left-Down"

function IchaUITotemSets.PaintArrow(btn, pressed)
    local tex = btn and btn.arrowTex
    if not tex then return end
    local base = IchaUITotemSets.ARROW_UP
    if pressed then base = IchaUITotemSets.ARROW_DOWN end
    tex:SetTexture(base)
    local g = tex.GetTexture and tex:GetTexture()
    if type(g) ~= "string" or not string.find(string.lower(g), "arrow%-left") then
        tex:SetTexture(base .. ".tga")
    end
    if btn.dir < 0 then
        tex:SetTexCoord(0, 1, 0, 1)
    else
        tex:SetTexCoord(1, 0, 0, 1)
    end
    -- 1.12 SetTexture restores the 32px file size; SetAllPoints on an
    -- unsized button left a 0x0 or native-size blob after /reload.
    local aw = btn:GetWidth()
    if not aw or aw < 8 then aw = 22 end
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", btn, "CENTER", 0, 0)
    tex:SetWidth(aw)
    tex:SetHeight(aw)
    tex:SetVertexColor(1, 1, 1, 1)
    tex:Show()
end

function IchaUITotemSets.MakeArrow(dir)
    local name = dir < 0 and "IchaUITotemPagePrev" or "IchaUITotemPageNext"
    local b = getglobal(name)
    if not b then
        b = CreateFrame("Button", name, root)
    else
        b:SetParent(root)
    end
    b.dir = dir
    b:EnableMouse(true)
    b:RegisterForClicks("LeftButtonUp")
    if not b.arrowTex then
        local regions = { b:GetRegions() }
        local ri
        for ri = 1, table.getn(regions) do
            local r = regions[ri]
            if r and r.GetObjectType and r:GetObjectType() == "Texture" then
                if not b.arrowTex then
                    b.arrowTex = r
                elseif r ~= b.arrowTex then
                    r:Hide()
                end
            end
        end
        if not b.arrowTex then
            b.arrowTex = b:CreateTexture(nil, "ARTWORK")
        end
    end
    IchaUITotemSets.PaintArrow(b, false)
    b:SetScript("OnMouseDown", function() IchaUITotemSets.PaintArrow(this, true) end)
    b:SetScript("OnMouseUp", function() IchaUITotemSets.PaintArrow(this, false) end)
    b:SetScript("OnClick", function() IchaUITotemSets.Step(this.dir) end)
    b:SetScript("OnEnter", function()
        if not GameTooltip then return end
        GameTooltip:SetOwner(this, this.dir < 0 and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
        local p = IchaUITotemSets.Page()
        GameTooltip:SetText(IchaUITotemSets.Name(p) .. "  (" .. p .. "/" .. IchaUITotemSets.Count() .. ")", 1, 1, 1)
        GameTooltip:AddLine("Click: " .. (this.dir < 0 and "previous" or "next") .. " totem set", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        IchaUITotemSets.PaintArrow(this, false)
        if GameTooltip then GameTooltip:Hide() end
    end)
    b:Hide()
    return b
end

-- Read-only copy of layoutCastRing's geometry: x of the cast stroke's outer
-- edge (left, right) relative to the slot center, for the slot's current
-- form/size. layoutCastRing only runs per cast, so it can't be read before.
function IchaUITotemSets.RingExtent(slot)
    local iw = slot.icon and slot.icon:GetWidth() or 0
    if iw < 8 then
        iw = (cfgSize or 36) * (cfgScale or 1) * (1 - 2 * ICON_INSET_FRAC)
        if iw < 8 then iw = 16 end
    end
    local side = slot:GetWidth() or iw
    local sh = slot:GetHeight() or side
    local minSide = side
    if sh < minSide then minSide = sh end
    local styled = slot._formShape and not slot._goldRingForm
    local shape = slot._formShape
    local RIM = IchaUITotems_CastRim
    local thk = minSide * 0.03
    if thk < 1 then thk = 1 end
    if styled then thk = thk * 2 end
    local half = thk / 2
    if styled and IchaUI_FormIsEdged and IchaUI_FormIsEdged(shape) then
        local def = IchaUI_FormShapeDef and IchaUI_FormShapeDef(shape)
        local vis
        if def and def.edge then
            vis = (def.outset or 0) - (RIM.edgeLine[shape] or 0)
        else
            local e = math.floor(side * 0.22 + 0.5)
            if e < 8 then e = 8 end
            if e > 14 then e = 14 end
            vis = -e * RIM.tipLine
        end
        local hw = side / 2 + vis + half
        return -(hw + half), hw + half
    end
    local T, rf, cx
    if styled then
        local def = IchaUI_FormShapeDef and IchaUI_FormShapeDef(shape)
        local rim = RIM[shape] or RIM.tooltip
        rf = rim[1]
        if shape == "circle" then
            T = math.floor(side * 64 / 36 + 0.5)
            cx = math.floor(side * 0.347 + 0.5) + (rim[2] - 0.5) * T
        else
            T = side
            if def and def.outer then T = side / def.outer end
            cx = (rim[2] - 0.5) * T
        end
    else
        T = slot.goldRing and slot.goldRing:GetWidth()
        if not T or T < 16 then
            local s = sh
            if s < 16 then s = 16 end
            T = math.floor(s * 1.65 + 0.5)
        end
        rf = RIM.circle[1]
        cx = RIM.circle[2] * T - side / 2
    end
    local outer = rf * T + half + half
    return cx - outer, cx + outer
end

-- Arrow art is 32 px with the caret at x 15..22, y 9..20 (alpha > 128):
-- inset from the bar-facing edge and its center lift, as texture fractions.
IchaUITotemSets.ARROW_INSET = 10 / 32
IchaUITotemSets.ARROW_FAR = 15 / 32
IchaUITotemSets.ARROW_LIFT = 1.5 / 32
IchaUITotemSets.RING_GAP = 5

-- Called from layoutBar after slots are sized/formed. Anchored to the end
-- slots so arrows follow moves, scale, size, gap and shape.
function IchaUITotemSets.LayoutArrows(size, gap)
    if not root then return end
    local S = IchaUITotemSets
    if not S.prev then
        S.prev = S.MakeArrow(-1)
        S.next = S.MakeArrow(1)
    end
    local first = slots[ELEMENTS[1]]
    local last = slots[ELEMENTS[table.getn(ELEMENTS)]]
    if not first or not last then return end
    S.arrowSize = size or S.arrowSize or 36
    local aw = math.floor(S.arrowSize * 0.625 + 0.5)
    if aw < 15 then aw = 15 end
    local inset = aw * S.ARROW_INSET
    local far = aw * S.ARROW_FAR
    local oy = -aw * S.ARROW_LIFT
    local left = S.RingExtent(first)
    local _, right = S.RingExtent(last)
    -- Above slot form rings (slot+8). +6 sat under the ring quad and the
    -- leftover TrackingBorder texels looked like a missing-texture tile.
    local fl = (root:GetFrameLevel() or 1) + 16
    S.prev:SetWidth(aw)
    S.prev:SetHeight(aw)
    S.prev:ClearAllPoints()
    S.prev:SetPoint("RIGHT", first, "CENTER", left - S.RING_GAP + inset, oy)
    S.prev:SetHitRectInsets(far, inset, 0, 0)
    S.prev:SetFrameLevel(fl)
    S.next:SetWidth(aw)
    S.next:SetHeight(aw)
    S.next:ClearAllPoints()
    S.next:SetPoint("LEFT", last, "CENTER", right + S.RING_GAP - inset, oy)
    S.next:SetHitRectInsets(inset, far, 0, 0)
    S.next:SetFrameLevel(fl)
    S.geom = { aw = aw, ringL = left, ringR = right,
        caretL = left - S.RING_GAP, caretR = right + S.RING_GAP }
    S.RefreshArrows()
end

function IchaUITotemSets.RefreshArrows()
    local S = IchaUITotemSets
    if not S.prev then return end
    if S.Count() < 2 then
        S.prev:Hide()
        S.next:Hide()
        return
    end
    IchaUITotemSets.PaintArrow(S.prev, false)
    IchaUITotemSets.PaintArrow(S.next, false)
    S.prev:Show()
    S.next:Show()
end

function IchaUITotems_Get()
    return {
        scale = cfgScale,
        size = cfgSize,
        gap = cfgGap,
        textSize = cfgText,
        drawerSize = cfgDrawerSize,
        drawerGap = cfgDrawerGap,
        cdBadgeScale = cfgCdBadgeScale,
        shiftDrawer = cfgShiftDrawer and true or false,
        drawerDir = db().drawerDir or "up",
        drawerSpread = (IchaUI_DrawerNormSpread and IchaUI_DrawerNormSpread(db().drawerSpread)) or 90,
        drawerArc = (IchaUI_DrawerNormArc and IchaUI_DrawerNormArc(db().drawerArc)) or 360,
        drawerRot = (IchaUI_DrawerNormRot and IchaUI_DrawerNormRot(db().drawerRot)) or 90,
        hidden = db().hidden and true or false,
        moving = moving,
        active = IchaUITotemSets.Table(nil),
        textStrata = (type(IchaUI_GetTotemTextStrata) == "function" and IchaUI_GetTotemTextStrata()) or "HIGH",
    }
end

function IchaUITotems_Set(field, value)
    if field == "scale" then
        cfgScale = tonumber(value) or cfgScale
        if cfgScale < 0.4 then cfgScale = 0.4 end
        if cfgScale > 3 then cfgScale = 3 end
    elseif field == "size" then
        cfgSize = tonumber(value) or cfgSize
        if cfgSize < 20 then cfgSize = 20 end
        if cfgSize > 80 then cfgSize = 80 end
    elseif field == "gap" or field == "pad" then
        cfgGap = tonumber(value) or cfgGap
        if cfgGap < 0 then cfgGap = 0 end
        if cfgGap > 40 then cfgGap = 40 end
    elseif field == "textSize" or field == "text" then
        cfgText = tonumber(value) or cfgText
        if cfgText < 6 then cfgText = 6 end
        if cfgText > 28 then cfgText = 28 end
    elseif field == "drawerSize" or field == "drawersize" then
        cfgDrawerSize = tonumber(value) or cfgDrawerSize
        if cfgDrawerSize < 14 then cfgDrawerSize = 14 end
        if cfgDrawerSize > 48 then cfgDrawerSize = 48 end
    elseif field == "shiftDrawer" or field == "shiftdrawer" or field == "shift" then
        cfgShiftDrawer = value and true or false
    elseif field == "drawerGap" or field == "drawergap" then
        cfgDrawerGap = tonumber(value) or cfgDrawerGap
        if cfgDrawerGap < 0 then cfgDrawerGap = 0 end
        if cfgDrawerGap > 12 then cfgDrawerGap = 12 end
    elseif field == "drawerDir" or field == "drawerdirection" or field == "openDir" then
        local s = string.lower(tostring(value or "up"))
        if s ~= "down" and s ~= "left" and s ~= "right" and s ~= "radial" then s = "up" end
        db().drawerDir = s
    elseif field == "drawerSpread" or field == "drawerspread" or field == "spread" then
        local n = tonumber(value) or 90
        if IchaUI_DrawerNormSpread then n = IchaUI_DrawerNormSpread(n) end
        if n < 10 then n = 10 end
        if n > 360 then n = 360 end
        db().drawerSpread = math.floor(n + 0.5)
    elseif field == "drawerArc" or field == "drawerarc" or field == "arc" then
        local n = tonumber(value)
        if n == nil then n = 360 end
        if IchaUI_DrawerNormArc then n = IchaUI_DrawerNormArc(n) end
        if n < 10 then n = 10 end
        if n > 360 then n = 360 end
        db().drawerArc = math.floor(n + 0.5)
    elseif field == "drawerRot" or field == "drawerrot" or field == "rot" then
        local n = tonumber(value)
        if n == nil then n = 90 end
        if IchaUI_DrawerNormRot then n = IchaUI_DrawerNormRot(n) end
        if n < -360 then n = -360 end
        if n > 360 then n = 360 end
        db().drawerRot = math.floor(n + 0.5)
    elseif field == "hidden" then
        db().hidden = value and true or nil
        updateVisibility()
    elseif field == "cdBadgeScale" or field == "cdbadge" or field == "cdBadge" then
        cfgCdBadgeScale = tonumber(value) or cfgCdBadgeScale
        if cfgCdBadgeScale < 0.4 then cfgCdBadgeScale = 0.4 end
        if cfgCdBadgeScale > 1.5 then cfgCdBadgeScale = 1.5 end
    elseif field == "moving" or field == "move" then
        setMove(value and true or false)
        return
    elseif field == "textStrata" or field == "textstrata" or field == "textLayer" then
        if IchaUI_SetTotemTextStrata then
            IchaUI_SetTotemTextStrata(value)
        elseif type(IchaUI_StrataFromValue) == "function" then
            local n = IchaUI_StrataFromValue(value, 4)
            db().textStrata = n or "HIGH"
        else
            db().textStrata = "HIGH"
        end
        savePos()
        if IchaUI_ApplyTotemStrata then IchaUI_ApplyTotemStrata() end
        return
    elseif field == "active" then
        return
    end
    savePos()
    layoutBar()
    do
        local i
        for i = 1, table.getn(ELEMENTS) do
            local el = ELEMENTS[i]
            local dr = drawers[el]
            if dr and dr.IsShown and dr:IsShown() then
                showDrawer(el, pinned[el] and true or false)
            end
        end
    end
    if IchaUI_ApplyTotemStrata then IchaUI_ApplyTotemStrata() end
    if IchaUIShamanExtras_Apply then IchaUIShamanExtras_Apply() end
end

function IchaUITotems_Apply()
    loadCfg()
    layoutBar()
    refreshActiveIcons()
    updateVisibility()
    if IchaUI_ApplyTotemStrata then IchaUI_ApplyTotemStrata() end
    if IchaUIShamanExtras_Apply then IchaUIShamanExtras_Apply() end
end

function IchaUITotems_SetTestMode(on)
    if on and not IchaUI_IsShaman() then return end
    totemTestMode = on and true or false
    if totemTestMode then
        local now = GetTime and GetTime() or 0
        local demo = {
            earth = { base = "Stoneclaw Totem", icon = "Interface\\Icons\\Spell_Nature_StoneClawTotem", duration = 55 },
            fire = { base = "Searing Totem", icon = "Interface\\Icons\\Spell_Fire_SearingTotem", duration = 40 },
            water = { base = "Healing Stream Totem", icon = "Interface\\Icons\\INV_Spear_04", duration = 60 },
            air = { base = "Windfury Totem", icon = "Interface\\Icons\\Spell_Nature_Windfury", duration = 50 },
        }
        local i
        for i = 1, table.getn(ELEMENTS) do
            local el = ELEMENTS[i]
            local d = demo[el]
            if d then
                live[el] = {
                    start = now,
                    duration = d.duration,
                    base = d.base,
                    icon = d.icon,
                }
            end
        end
        root:Show()
        if layoutBar then layoutBar() end
        if applySlotVisuals then applySlotVisuals() end
        -- Briefly open drawers so layout is visible
        for i = 1, table.getn(ELEMENTS) do
            if showDrawer then showDrawer(ELEMENTS[i], true) end
        end
    else
        -- Clear demo live timers only if they look like our demo bases
        local i
        for i = 1, table.getn(ELEMENTS) do
            local el = ELEMENTS[i]
            local L = live[el]
            if L and (L.base == "Stoneclaw Totem" or L.base == "Searing Totem"
                or L.base == "Healing Stream Totem" or L.base == "Windfury Totem") then
                live[el] = nil
                wipeSlotTimers(slots[el])
            end
            hideDrawer(el)
        end
        updateVisibility()
        if applySlotVisuals then applySlotVisuals() end
    end
end

function IchaUITotems_Slash(rest)
    if not IchaUI_IsShaman() then
        DEFAULT_CHAT_FRAME:AddMessage("IchaUI: the totem bar is shaman-only.")
        return
    end
    rest = string.lower(rest or "")
    rest = string.gsub(rest, "^%s+", "")
    if rest == "move" then
        setMove(not moving)
    elseif rest == "show" then
        local d = db()
        d.hidden = false
        if root then
            root:SetAlpha(1)
            if IchaUI_ApplyTotemStrata then IchaUI_ApplyTotemStrata() end
            root:Show()
            local left = root.GetLeft and root:GetLeft()
            local bottom = root.GetBottom and root:GetBottom()
            if (not d.point) or (left and (left < -400 or left > 2500))
                or (bottom and (bottom < -400 or bottom > 2500)) then
                root:ClearAllPoints()
                root:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 160)
                d.point, d.relPoint, d.x, d.y = "BOTTOM", "BOTTOM", 0, 160
            end
            pcall(layoutBar)
            if applySlotVisuals then pcall(applySlotVisuals) end
            local i
            for i = 1, table.getn(ELEMENTS) do
                local s = slots[ELEMENTS[i]]
                if s then s:Show() end
            end
        end
        savePos()
        DEFAULT_CHAT_FRAME:AddMessage("Totem bar shown — /icha totems move to drag if needed.")
    elseif rest == "hide" then
        db().hidden = true
        updateVisibility()
        savePos()
        DEFAULT_CHAT_FRAME:AddMessage("Totem bar hidden.")
    elseif rest == "throw" or rest == "set" or rest == "cast" then
        IchaUITotems_ThrowSet()
    elseif string.find(rest, "^throw %d+$") then
        IchaUITotems_ThrowSetN(tonumber(string.sub(rest, 7)))
    elseif rest == "next" or rest == "prev" then
        IchaUITotemSets.Step(rest == "next" and 1 or -1)
        DEFAULT_CHAT_FRAME:AddMessage("Totem set: " .. IchaUITotemSets.Name(nil)
            .. " (" .. IchaUITotemSets.Page() .. "/" .. IchaUITotemSets.Count() .. ")")
    elseif string.find(rest, "^scale") then
        local n = nil
        for token in (string.gmatch or string.gfind)(rest, "%S+") do
            n = tonumber(token) or n
        end
        if not n then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("Totem scale: %.2f", cfgScale))
        else
            IchaUITotems_Set("scale", n)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("Totem scale %.2f", cfgScale))
        end
    elseif string.find(rest, "^size") then
        local n = nil
        for token in (string.gmatch or string.gfind)(rest, "%S+") do
            n = tonumber(token) or n
        end
        if not n then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("Totem size: %.0f", cfgSize))
        else
            IchaUITotems_Set("size", n)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("Totem size %.0f", cfgSize))
        end
    elseif string.find(rest, "^gap") or string.find(rest, "^pad") then
        local n = nil
        for token in (string.gmatch or string.gfind)(rest, "%S+") do
            n = tonumber(token) or n
        end
        if not n then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("Totem gap: %.1f", cfgGap))
        else
            IchaUITotems_Set("gap", n)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("Totem gap %.1f", cfgGap))
        end
    elseif string.find(rest, "^text") then
        local n = nil
        for token in (string.gmatch or string.gfind)(rest, "%S+") do
            n = tonumber(token) or n
        end
        if not n then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("Totem text size: %.0f", cfgText))
        else
            IchaUITotems_Set("textSize", n)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("Totem text size %.0f", cfgText))
        end
    elseif rest == "clear" then
        local t = IchaUITotemSets.Table(nil)
        local k
        for k = 1, table.getn(ELEMENTS) do t[ELEMENTS[k]] = nil end
        IchaUITotemSets.Changed()
        DEFAULT_CHAT_FRAME:AddMessage("Active totems cleared (" .. IchaUITotemSets.Name(nil) .. ").")
    else
        DEFAULT_CHAT_FRAME:AddMessage("Totems: /icha totems move|show|hide|throw|scale|size|gap|text|drawersize|drawergap|clear")
        DEFAULT_CHAT_FRAME:AddMessage("Also: /icha totems throw [N|all] | next | prev — bind: Throw Current Totem Set")
    end
end


-- Per-frame cast/tick ring paint (spark + colored trail). Keeps motion smooth.
local function updateCastRingsFast()
    if not applySlotVisuals then return end
    local now = GetTime and GetTime() or 0
    local i
    for i = 1, table.getn(ELEMENTS) do
        local el = ELEMENTS[i]
        local slot = slots[el]
        if slot then
            local L = live[el]
            local remain = 0
            if L and L.start and L.duration then
                remain = (L.start + L.duration) - now
            end
            if L and remain > 0 and not pendingRecall and now >= (suppressLiveUntil or 0) then
                local base = L.base
                local LC = liveCast[el]
                if FIRE_CAST_TOTEMS[base] then
                    if LC and LC.fromEvent and LC.start and LC.finish and now < LC.finish then
                        local dur = LC.finish - LC.start
                        if dur < 0.05 then dur = 0.05 end
                        local elapsed = now - LC.start
                        if elapsed < 0 then elapsed = 0 end
                        if elapsed > dur then elapsed = dur end
                        setCastRing(slot, elapsed / dur, base)
                    else
                        hideCastRing(slot)
                    end
                elseif FIRE_LIFETIME_RING and FIRE_LIFETIME_RING[base] then
                    local dur = fuseFor(base, L.duration)
                    if dur < 0.05 then dur = 0.05 end
                    local elapsed = now - (L.start or now)
                    if elapsed < 0 then elapsed = 0 end
                    if elapsed > dur then elapsed = dur end
                    setCastRing(slot, elapsed / dur, base)
                else
                    local per = periodFor(base)
                    if per and per > 0 then
                        local elapsed = math.mod(now - L.start, per)
                        if elapsed < 0 then elapsed = 0 end
                        local pct = elapsed / per
                        if pct > 1 then pct = 1 end
                        setCastRing(slot, pct, base)
                    end
                end
            end
        end
    end
end

-- Build UI
root = CreateFrame("Frame", "IchaUITotemsRoot", UIParent)
root:SetFrameStrata("MEDIUM")
root:SetMovable(true)
root:EnableMouse(false)
root:SetWidth(200)
root:SetHeight(50)
root:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 160)
root:Hide()

local i
for i = 1, table.getn(ELEMENTS) do
    makeSlot(ELEMENTS[i])
end
if IchaUI_ApplyTotemStrata then IchaUI_ApplyTotemStrata() end

mover = CreateFrame("Frame", nil, root)
mover:SetAllPoints(root)
mover:EnableMouse(true)
mover:RegisterForDrag("LeftButton")
mover:Hide()
mover:SetFrameLevel((root:GetFrameLevel() or 1) + 30)
local mbg = mover:CreateTexture(nil, "BACKGROUND")
mbg:SetAllPoints(mover)
mbg:SetTexture(1, 1, 1, 1)
mbg:SetVertexColor(0.15, 0.45, 0.95, 0.3)
local mlabel = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
mlabel:SetPoint("CENTER", mover, "CENTER")
mlabel:SetText("Drag totems  |  /icha totems move")
mover:SetScript("OnDragStart", function() root:StartMoving() end)
mover:SetScript("OnDragStop", function()
    root:StopMovingOrSizing()
    savePos()
end)
mover:SetScript("OnMouseUp", function()
    if arg1 == "RightButton" and IchaUI_DrawerEditClick then IchaUI_DrawerEditClick("totems") end
end)

-- Visuals only on root (may be hidden); throw processing lives on always-shown ticker
root:SetScript("OnUpdate", function()
    if IchaUI_LEAVING then return end
    local now = GetTime and GetTime() or 0
    -- Cast spark/trail every frame for smooth motion
    pcall(updateCastRingsFast)
    if not this._totemAcc then this._totemAcc = 0 end
    this._totemAcc = this._totemAcc + (arg1 or 0)
    if this._totemAcc > 0.05 then
        this._totemAcc = 0
        if GetTotemInfo then
            pcall(updateLiveFromAPI)
        end
        pcall(applySlotVisuals)
    end
    -- Pulse recall after red-timer paint so _recallLive/_recallInRange are current.
    if IchaUI_TotemRecallPulse then
        IchaUI_TotemRecallPulse()
    end
end)

local evt = CreateFrame("Frame", "IchaUITotemsEvt", UIParent)
evt:Show() -- always shown so throw chain works if bar hidden
evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("PLAYER_ENTERING_WORLD")
evt:RegisterEvent("SPELLS_CHANGED")
pcall(function() evt:RegisterEvent("CHARACTER_POINTS_CHANGED") end)
evt:RegisterEvent("PLAYER_AURAS_CHANGED")
pcall(function() evt:RegisterEvent("PLAYER_TOTEM_UPDATE") end)
pcall(function() evt:RegisterEvent("UNIT_CASTEVENT") end)
evt:RegisterEvent("SPELLCAST_START")
evt:RegisterEvent("SPELLCAST_STOP")
pcall(function() evt:RegisterEvent("SPELLCAST_FAILED") end)
pcall(function() evt:RegisterEvent("SPELLCAST_INTERRUPTED") end)
evt:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
evt:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
pcall(function() evt:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE") end)
pcall(function() evt:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILE_DAMAGE") end)
pcall(function() evt:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS") end)
pcall(function() evt:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE") end)
pcall(function() evt:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE") end)
pcall(function() evt:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE") end)
evt:RegisterEvent("PLAYER_LEAVING_WORLD")

evt:SetScript("OnUpdate", function()
    if IchaUI_LEAVING then return end
    local now = GetTime and GetTime() or 0
    tickBindPushes(now)
    if IchaUITotems_TickFireTwist then
        IchaUITotems_TickFireTwist(now)
    end
    processThrow(now)
    -- Always-shown ticker: recall still pulses if the 1x1 recall frame is culled.
    if IchaUI_TotemRecallPulse then
        IchaUI_TotemRecallPulse()
    end
    -- If root hidden, still refresh visuals lightly so liveCast expires cleanly when shown again
    if not this._acc then this._acc = 0 end
    this._acc = this._acc + (arg1 or 0)
    if this._acc > 0.15 then
        this._acc = 0
        if root and not root:IsShown() then
            -- keep throw path alive; skip heavy visuals when hidden
        elseif root and root:IsShown() then
            -- root OnUpdate handles visuals when shown
        end
    end
end)

local function chatLooksLikeFireCastStart(msg)
    if not msg then return false end
    local l = string.lower(tostring(msg))
    -- Only CAST START lines — hits would re-sync mid-cast and skew the timer
    if not (string.find(l, "begin", 1, true) or string.find(l, "starts to cast", 1, true)
        or string.find(l, "begins to cast", 1, true) or string.find(l, "casting", 1, true)) then
        return false
    end
    -- Bolt only — NOT "Searing Totem" (that is the drop / summon)
    if string.find(l, "searing bolt", 1, true) then return true end
    if string.find(l, "searing totem", 1, true) then return false end
    return false
end

local function unitCastLooksLikeFire(hint)
    if not hint then return false end
    if type(hint) == "number" and type(SpellInfo) == "function" then
        local ok, nm = pcall(SpellInfo, hint)
        if ok and nm then hint = nm end
    end
    local s = tostring(hint)
    local l = string.lower(s)
    -- Ignore the totem summon itself (shows a fake cast on drop)
    if string.find(l, "totem", 1, true) and not string.find(l, "bolt", 1, true) then
        return false
    end
    if string.find(l, "searing bolt", 1, true) then return true end
    if string.find(l, "searingtotem", 1, true) then return false end
    -- Real bolt cast names only
    if string.find(l, "searing", 1, true) and string.find(l, "bolt", 1, true) then return true end
    return false
end

-- SuperWoW UNIT_CASTEVENT: typically caster, target, eventType, spellID, durationMs
local function parseUnitCastEvent()
    local a1, a2, a3, a4, a5 = arg1, arg2, arg3, arg4, arg5
    local eventType, spellId, durMs = nil, nil, nil
    -- Common SuperWoW shape
    if type(a3) == "string" and type(a4) == "number" then
        eventType, spellId, durMs = a3, a4, a5
    elseif type(a2) == "string" and type(a3) == "number" then
        eventType, spellId, durMs = a2, a3, a4
    elseif type(a4) == "number" and type(a5) == "number" then
        spellId, durMs = a4, a5
    end
    local spellName = nil
    if type(spellId) == "number" and type(SpellInfo) == "function" then
        local ok, nm = pcall(SpellInfo, spellId)
        if ok then spellName = nm end
    end
    if not spellName then
        -- fall back to scanning args for name tokens
        local hints = { a1, a2, a3, a4, a5 }
        local hi
        for hi = 1, table.getn(hints) do
            if unitCastLooksLikeFire(hints[hi]) then
                if type(hints[hi]) == "number" and SpellInfo then
                    local ok, nm = pcall(SpellInfo, hints[hi])
                    if ok then spellName = nm end
                else
                    spellName = tostring(hints[hi])
                end
                break
            end
        end
    end
    return eventType, spellId, spellName, durMs
end

evt:SetScript("OnEvent", function()
    if (event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD")
        and IchaUI_ShamanStandDown(this, root, drawers.earth, drawers.fire, drawers.water, drawers.air) then
        return
    end
    if event == "PLAYER_LEAVING_WORLD" then
        liveGuid = {}
        return
    end
    if IchaUI_LEAVING and event ~= "PLAYER_ENTERING_WORLD" then return end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        loadCfg()
        restorePos()
        isShaman = isPlayerShaman()
        updateVisibility()
        if root and isShaman and not db().hidden then
            root:SetAlpha(1)
            if IchaUI_ApplyTotemStrata then IchaUI_ApplyTotemStrata() end
            root:Show()
        end
        pcall(layoutBar)
        if applySlotVisuals then pcall(applySlotVisuals) end
        pcall(scanSpellbook)
        pcall(scanImprovedFireTotems)
        pcall(refreshActiveIcons)
        updateVisibility()
        if applyThrowBinding then pcall(applyThrowBinding) end
        if applySlotBindings then pcall(applySlotBindings) end
        if applySpellBindings then pcall(applySpellBindings) end
        pcall(IchaUITotemSets.ApplyBindings)
        pcall(IchaUITotemSets.RefreshArrows)
        if GetTotemInfo then pcall(updateLiveFromAPI) end
    elseif event == "SPELLS_CHANGED" or event == "CHARACTER_POINTS_CHANGED" then
        scanSpellbook()
        scanImprovedFireTotems()
        refreshActiveIcons()
    elseif event == "PLAYER_TOTEM_UPDATE" then
        if GetTotemInfo then
            updateLiveFromAPI()
        else
            -- No API: treat empty update after recall as wipe if we pending
            if pendingRecall then
                clearAllLive("totem-update")
            end
        end
        -- Skip repaint right after recall wipe (avoids second flicker/stutter)
        local now = GetTime and GetTime() or 0
        if (now - lastClearAt) > 0.25 then
            if applySlotVisuals then applySlotVisuals() end
        end
    elseif event == "UNIT_CASTEVENT" then
        -- SuperWoW: arg1=casterGUID, arg2=target, arg3=eventType, arg4=spellId
        -- Only treat real START casts of a catalog totem as a drop (never buff ticks).
        do
            local caster = arg1
            local et = arg3 and string.upper(tostring(arg3)) or ""
            local spellId = arg4
            local isPlayer = (caster == "player" or caster == "pet")
            if not isPlayer and type(UnitIsUnit) == "function" then
                local okU, r = pcall(UnitIsUnit, tostring(caster), "player")
                if okU and r then isPlayer = true end
            end
            if not isPlayer and type(UnitGUID) == "function" then
                local okG, pg = pcall(UnitGUID, "player")
                if okG and pg and tostring(caster) == tostring(pg) then isPlayer = true end
            end
            local isStart = (et == "START" or et == "CAST" or et == "")
            if et == "FAIL" or et == "FAILED" or et == "INTERRUPTED" or et == "MAINHAND" or et == "OFFHAND" then
                isStart = false
            end
            if isPlayer and isStart and spellId then
                local spellHint = nil
                if type(spellId) == "number" and SpellInfo then
                    local ok, nm = pcall(SpellInfo, spellId)
                    if ok and nm then spellHint = nm end
                end
                if not spellHint and type(spellId) == "number" and GetSpellName then
                    local nm = GetSpellName(spellId, BOOKTYPE_SPELL or "spell")
                    if nm then spellHint = nm end
                end
                if type(spellId) == "string" and string.find(spellId, "Totem", 1, true) then
                    spellHint = spellId
                end
                if spellHint and string.find(tostring(spellHint), "Totem", 1, true) then
                    markDropped(tostring(spellHint), true)
                end
            end
        end
        -- Totem bolt cast start (caster is often a GUID, not "player")
        local eventType, spellId, spellName, durMs = parseUnitCastEvent()
        local et = eventType and string.upper(tostring(eventType)) or ""
        local isStart = (et == "" or et == "START" or et == "CAST")
        -- Ignore FAIL / channel noise; prefer START when present
        if et == "FAIL" or et == "FAILED" or et == "INTERRUPTED" then
            isStart = false
        end
        -- Bolt casts come from the totem GUID, never from the player (player = drop)
        local boltCaster = arg1
        local boltFromPlayer = (boltCaster == "player" or boltCaster == "pet")
        if not boltFromPlayer and type(UnitIsUnit) == "function" then
            local okU, r = pcall(UnitIsUnit, tostring(boltCaster), "player")
            if okU and r then boltFromPlayer = true end
        end
        if not boltFromPlayer and type(UnitGUID) == "function" then
            local okG, pg = pcall(UnitGUID, "player")
            if okG and pg and tostring(boltCaster) == tostring(pg) then boltFromPlayer = true end
        end
        if isStart and not boltFromPlayer and (unitCastLooksLikeFire(spellName) or unitCastLooksLikeFire(spellId)) then
            local dur = nil
            if type(durMs) == "number" and durMs > 0 then
                dur = durMs > 10 and (durMs / 1000) or durMs
            end
            noteFireCast(spellName or spellId or "Searing Bolt", dur, true)
        end
    elseif event == "SPELLCAST_STOP" or event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED" then
        if pendingRecall and event == "SPELLCAST_STOP" then
            pendingRecall = false
            clearAllLive("recall-stop")
        elseif event ~= "SPELLCAST_STOP" then
            pendingRecall = false
        end
        onThrowCastFinished()
        if event ~= "SPELLCAST_STOP" and IchaUITotems_NoteTwistFail then
            IchaUITotems_NoteTwistFail()
        end
    elseif event == "SPELLCAST_START" then
        -- arg1 = spell name on 1.12
        if isTotemRecallName(arg1) then
            pendingRecall = true
            -- Wipe immediately so OnUpdate never paints red OOR after buffs drop
            clearAllLive("recall-start")
        end
    elseif event == "CHAT_MSG_SPELL_SELF_BUFF" or event == "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS" then
        local msg = arg1 or ""
        if isTotemRecallName(msg) then
            clearAllLive("recall-chat")
            return
        end
        -- Do NOT markDropped here: periodic buff text re-anchored range to your
        -- feet while walking and pushed the red threshold out to ~42y.
    else
        -- Combat chat: only "begins to cast" (not hits)
        local msg = arg1 or ""
        if chatLooksLikeFireCastStart(msg) then
            noteFireCast(msg, searingCastLength(), true)
        end
    end
end)

SLASH_ICHATOTEMS1 = "/ichatotems"
SlashCmdList["ICHATOTEMS"] = function(msg)
    IchaUITotems_Slash(msg or "")
end

function IchaUITotems_ReloadFromDB()
    if not IchaUI_IsShaman() then return end
    loadCfg()
    restorePos()
    if IchaUITotems_Apply then IchaUITotems_Apply() end
    if applyThrowBinding then applyThrowBinding() end
    if applySlotBindings then applySlotBindings() end
    if applySpellBindings then applySpellBindings() end
    pcall(IchaUITotemSets.ApplyBindings)
    IchaUITotemSets.Changed()
    local i
    for i = 1, table.getn(ELEMENTS) do
        local el = ELEMENTS[i]
        local dr = drawers[el]
        if dr and dr.IsShown and dr:IsShown() and showDrawer then
            showDrawer(el, pinned[el] and true or false)
        end
    end
end

layoutBar()
IchaUI_ShamanStandDown(evt, root, drawers.earth, drawers.fire, drawers.water, drawers.air)
