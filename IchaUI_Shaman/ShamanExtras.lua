-- IchaUI shaman extras: weapon imbue + elemental shield + utility drawer
-- Detached movable circle+drawer widgets (same chrome as totems, NOT on totem bar)
-- Lua 5.0 / 1.12 safe

local GOLD = { 0.78, 0.58, 0.16, 1 }
local ROUNDMASK = "Interface/AddOns/IchaUI/media/roundmask-circle"
local EMPTY_SKULL = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
local GOLD_RING = "Interface/Minimap/MiniMap-TrackingBorder"
local DEFAULT_SIZE = 36
local DEFAULT_SCALE = 1.25
local DEFAULT_TEXT = 11
local DEFAULT_DRAWER_SIZE = 34
local DEFAULT_DRAWER_GAP = 2
local DRAWER_CLOSE_DELAY = 0.35
local ICON_INSET_FRAC = 0.22

-- Warning thresholds
local IMBUE_WARN_SEC = 60
local SHIELD_WARN_CHARGES = 2

local IMBUE_LIST = {
    "Rockbiter Weapon",
    "Flametongue Weapon",
    "Frostbrand Weapon",
    "Windfury Weapon",
}

local SHIELD_LIST = {
    "Lightning Shield",
    "Water Shield",
    "Earth Shield",
}

local IMBUE_ICONS = {
    ["Rockbiter Weapon"] = "Interface\\Icons\\Spell_Nature_RockBiter",
    ["Flametongue Weapon"] = "Interface\\Icons\\Spell_Fire_FlameTounge",
    ["Frostbrand Weapon"] = "Interface\\Icons\\Spell_Frost_FrostBrand",
    ["Windfury Weapon"] = "Interface\\Icons\\Spell_Nature_Cyclone",
}

local SHIELD_ICONS = {
    ["Lightning Shield"] = "Interface\\Icons\\Spell_Nature_LightningShield",
    ["Water Shield"] = "Interface\\Icons\\Ability_Shaman_WaterShield", -- Turtle; fallback below
    ["Earth Shield"] = "Interface\\Icons\\Spell_Nature_SkinofEarth",
}

-- Match short / locale-ish names
local IMBUE_MATCH = {
    { key = "Rockbiter Weapon", needles = { "rockbiter" } },
    { key = "Flametongue Weapon", needles = { "flametongue", "flametounge" } },
    { key = "Frostbrand Weapon", needles = { "frostbrand" } },
    { key = "Windfury Weapon", needles = { "windfury weapon", "windfury" } },
}

local SHIELD_MATCH = {
    { key = "Lightning Shield", needles = { "lightning shield" } },
    { key = "Water Shield", needles = { "water shield" } },
    { key = "Earth Shield", needles = { "earth shield" } },
}

local UTILITY_LIST = {
    "Water Walking",
    "Water Breathing",
    "Far Sight",
    "Astral Recall",
    "Reincarnation",
    "Ancestral Spirit",
}

local UTILITY_ICONS = {
    ["Water Walking"] = "Interface\\Icons\\Spell_Frost_WindWalkOn",
    ["Water Breathing"] = "Interface\\Icons\\Spell_Shadow_DemonBreath",
    ["Far Sight"] = "Interface\\Icons\\Spell_Nature_FarSight",
    ["Astral Recall"] = "Interface\\Icons\\Spell_Nature_AstralRecal",
    ["Reincarnation"] = "Interface\\Icons\\Spell_Nature_Reincarnation",
    ["Ancestral Spirit"] = "Interface\\Icons\\Spell_Nature_Regenerate",
}

local UTILITY_MATCH = {
    { key = "Water Walking", needles = { "water walking", "waterwalking", "water walk" } },
    { key = "Water Breathing", needles = { "water breathing", "waterbreathing" } },
    { key = "Far Sight", needles = { "far sight", "farsight" } },
    { key = "Astral Recall", needles = { "astral recall", "astralrecall" } },
    { key = "Reincarnation", needles = { "reincarnation" } },
    { key = "Ancestral Spirit", needles = { "ancestral spirit" } },
}

-- This server (not vanilla): Water Walking = Fish Oil, Water Breathing = Shiny Fish Scales.
-- Tooltip fallback may rename; never let one item count for both spells.
local UTILITY_REAGENT_NEEDLES = {
    ["Water Walking"] = { "fish oil" },
    ["Water Breathing"] = { "shiny fish scales", "fish scale" },
}

if not math.mod then
    math.mod = function(a, b)
        return a - math.floor(a / b) * b
    end
end

local function db()
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.shamanExtras then IchaUIDB.shamanExtras = {} end
    local d = IchaUIDB.shamanExtras
    if not d.imbue then d.imbue = {} end
    if not d.shield then d.shield = {} end
    if not d.utility then d.utility = {} end
    return d
end

-- IchaUIDB.utilityShow[key] == false hides that row. Missing = shown.
local function utilityShown(key)
    local t = IchaUIDB and IchaUIDB.utilityShow
    if type(t) ~= "table" then return true end
    return t[key] ~= false
end

local DEFAULT_IMBUE = "Rockbiter Weapon"
local DEFAULT_SHIELD = "Lightning Shield"
local DEFAULT_UTILITY = "Water Walking"

local function rememberLast(which, key)
    if not key or key == "" or key == "__enchant__" or key == "__none__" then return end
    local d = db()
    if not d[which] then d[which] = {} end
    d[which].last = key
    IchaUIDB.shamanExtras = d
end

local function lastOrDefault(which)
    local d = db()[which] or {}
    local key = d.last
    if which == "imbue" then
        if not key or not IMBUE_ICONS[key] then key = DEFAULT_IMBUE end
    elseif which == "shield" then
        if not key or not SHIELD_ICONS[key] then key = DEFAULT_SHIELD end
    else
        if not key or not UTILITY_ICONS[key] then key = DEFAULT_UTILITY end
    end
    return key
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

local function totemScale()
    -- Prefer shared visual scale with totem bar when available
    if IchaUITotems_Get then
        local t = IchaUITotems_Get()
        if t and t.scale then return t.scale end
    end
    return DEFAULT_SCALE
end

local function totemSize()
    if IchaUITotems_Get then
        local t = IchaUITotems_Get()
        if t and t.size then return t.size end
    end
    return DEFAULT_SIZE
end

local function totemText()
    if IchaUITotems_Get then
        local t = IchaUITotems_Get()
        if t and t.textSize then return t.textSize end
    end
    return DEFAULT_TEXT
end

-- Independent of totem bar text size (saved on shamanExtras)
local function extrasTextSize()
    local d = db()
    local n = tonumber(d.textSize)
    if n and n > 0 then return n end
    return totemText() -- fall back to totem text until user sets one
end

local function totemDrawerSize()
    if IchaUITotems_Get then
        local t = IchaUITotems_Get()
        if t and t.drawerSize then return t.drawerSize end
    end
    return DEFAULT_DRAWER_SIZE
end

local function totemDrawerGap()
    if IchaUITotems_Get then
        local t = IchaUITotems_Get()
        if t and t.drawerGap then return t.drawerGap end
    end
    return DEFAULT_DRAWER_GAP
end

local function drawerButtonScale(id)
    if IchaUI_DrawerButtonScale then return IchaUI_DrawerButtonScale(id) end
    return 1
end

local function drawerPopScale(id)
    if IchaUI_DrawerPopScale then return IchaUI_DrawerPopScale(id) end
    return 1
end

local function extrasDrawerDir(which)
    local d = db()[which]
    local s = d and d.drawerDir
    if s == "down" or s == "left" or s == "right" or s == "radial" then return s end
    return "up"
end

local function applyGoldRing(ringTex, parent, size)
    if not ringTex or not parent then return end
    local s = size or parent:GetWidth() or DEFAULT_SIZE
    if s < 16 then s = 16 end
    local bw = math.floor(s * 1.65 + 0.5)
    ringTex:SetTexture(GOLD_RING)
    ringTex:SetBlendMode("BLEND")
    IchaUI_PaintGoldRing(ringTex)
    ringTex:ClearAllPoints()
    ringTex:SetWidth(bw)
    ringTex:SetHeight(bw)
    ringTex:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    ringTex:Show()
end

local function insetIcon(tex, parent, size)
    if not tex or not parent then return end
    local s = size or parent:GetWidth() or DEFAULT_SIZE
    local iconSz = math.floor(s * (1 - 2 * ICON_INSET_FRAC) + 0.5)
    if iconSz < 10 then iconSz = 10 end
    tex:ClearAllPoints()
    tex:SetWidth(iconSz)
    tex:SetHeight(iconSz)
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

local function pushCircleSlot(slot, icon, roundMask, circleBg, pushTex)
    if not slot or slot._pushed then return end
    slot._pushed = true
    if icon and IchaUI_FormPress and IchaUI_FormPress(slot, true) then
        icon:SetVertexColor(0.82, 0.82, 0.82)
        if pushTex and IchaUI_FormOverlay and IchaUI_FormOverlay(slot, pushTex, "shade") then
            pushTex:SetDrawLayer("OVERLAY", 7)
            pushTex:SetAlpha(0.18)
            pushTex:Show()
        end
        pushTex = nil
    elseif icon then
        insetIcon(icon, slot, slot:GetWidth())
        icon:SetVertexColor(0.82, 0.82, 0.82)
        if roundMask then
            roundMask:ClearAllPoints()
            roundMask:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
            roundMask:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
            roundMask:Show()
        end
    end
    if pushTex then
        pushTex:ClearAllPoints()
        pushTex:SetAllPoints(icon or slot)
        pushTex:SetDrawLayer("OVERLAY", 7)
        pushTex:SetAlpha(0.18)
        pushTex:Show()
    end
end

local function releaseCircleSlot(slot, icon, roundMask, circleBg, pushTex)
    if not slot or not slot._pushed then return end
    slot._pushed = false
    if icon and IchaUI_FormPress and IchaUI_FormPress(slot, false) then
        icon:SetVertexColor(1, 1, 1)
    elseif icon then
        insetIcon(icon, slot, slot:GetWidth())
        icon:SetVertexColor(1, 1, 1)
        if roundMask then
            roundMask:ClearAllPoints()
            roundMask:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
            roundMask:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
            roundMask:Show()
        end
    end
    if pushTex then
        pushTex:Hide()
        pushTex:SetAlpha(0.18)
    end
end

local PUSH_MS = 0.12

local function applyIconTint(w)
    if not w or not w.icon then return end
    if w.slot and w.slot._pushed then
        w.icon:SetVertexColor(0.82, 0.82, 0.82)
    else
        w.icon:SetVertexColor(1, 1, 1, 1)
    end
end

-- Imbue duration: whole minutes until under 1 min, then seconds
local function formatTime(sec)
    if not sec or sec < 0 then return "" end
    if sec >= 60 then
        return tostring(math.floor(sec / 60)) .. "m"
    end
    return string.format("%.0f", sec)
end

local tip = CreateFrame("GameTooltip", "IchaUIShamanExtraTip", nil, "GameTooltipTemplate")
tip:SetOwner(UIParent, "ANCHOR_NONE")

local function tipLine1()
    local fs = getglobal("IchaUIShamanExtraTipTextLeft1")
    return fs and fs:GetText() or nil
end

local knownCache = {}
local knownScanAt = 0
local reagentDirty = true
local reagentCounts = {}
local itemCountById = {}
local itemCountByName = {}
local itemScanOk = false
local spellReagentName = {}
-- Sticky MH/OH remaining seconds. One empty tooltip / aura tick must not blank the timer.
local imbueHold = { key = nil, sec = nil, at = 0 }
local IMBUE_HOLD_GRACE = 0.7

local function matchKey(name, matchList)
    if not name then return nil end
    local l = string.lower(name)
    local i
    for i = 1, table.getn(matchList) do
        local m = matchList[i]
        local j
        for j = 1, table.getn(m.needles) do
            if string.find(l, m.needles[j], 1, true) then
                return m.key
            end
        end
    end
    return nil
end

local function scanSpellbook()
    knownCache = {}
    spellReagentName = {}
    reagentDirty = true
    local book = BOOKTYPE_SPELL or "spell"
    local i = 1
    while i <= 500 do
        local name, rank = GetSpellName(i, book)
        if not name then break end
        local key = matchKey(name, IMBUE_MATCH) or matchKey(name, SHIELD_MATCH) or matchKey(name, UTILITY_MATCH)
        if key then
            local tex = nil
            if GetSpellTexture then tex = GetSpellTexture(i, book) end
            -- Keep highest rank (later entries overwrite)
            knownCache[key] = {
                name = name,
                rank = rank,
                index = i,
                texture = tex,
                base = key,
            }
        end
        i = i + 1
    end
    -- Learned Restoration talent may exist even if the spellbook name is odd; still hide if rank is 0.
    if type(GetNumTalentTabs) == "function" and type(GetNumTalents) == "function" and type(GetTalentInfo) == "function" then
        local tab
        local nTabs = tonumber(GetNumTalentTabs()) or 0
        for tab = 1, nTabs do
            local nTal = tonumber(GetNumTalents(tab)) or 0
            local ti
            for ti = 1, nTal do
                local tname, ttex, _, _, rank = GetTalentInfo(tab, ti)
                if tname and tonumber(rank) and tonumber(rank) > 0 then
                    local key = matchKey(tname, UTILITY_MATCH)
                    if key == "Reincarnation" then
                        if not knownCache[key] then
                            knownCache[key] = {
                                name = tname,
                                rank = "",
                                index = nil,
                                texture = ttex,
                                base = key,
                            }
                        elseif (not knownCache[key].texture) and ttex then
                            knownCache[key].texture = ttex
                        end
                    end
                end
            end
        end
    end
    knownScanAt = GetTime and GetTime() or 0
end

local function ensureKnown()
    local now = GetTime and GetTime() or 0
    if knownScanAt == 0 or (now - knownScanAt) > 5 then
        scanSpellbook()
    end
end

local function iconFor(key, fallbackTable)
    local k = knownCache[key]
    if k and k.texture then return k.texture end
    return (fallbackTable and fallbackTable[key]) or EMPTY_SKULL
end

local function castSpell(key)
    ensureKnown()
    local entry = knownCache[key]
    local book = BOOKTYPE_SPELL or "spell"
    if entry and entry.index and CastSpell then
        CastSpell(entry.index, book)
        return true
    end
    local castName = (entry and entry.name) or key
    if entry and entry.rank and entry.rank ~= "" then
        castName = entry.name .. "(" .. entry.rank .. ")"
    end
    if CastSpellByName then
        CastSpellByName(castName)
        return true
    end
    return false
end

-- Buff scan helper: returns name, texture, count, timeLeft (if available)
local function readPlayerBuff(index)
    if not UnitBuff then return nil end
    local a1, a2, a3, a4, a5 = UnitBuff("player", index)
    if not a1 then return nil end
    local tex, count, timeLeft
    if type(a1) == "string" and (string.find(a1, "Interface") or string.find(a1, "Icons") or string.find(a1, "\\")) then
        tex = a1
        count = (type(a2) == "number" and a2) or 1
    else
        tip:ClearLines()
        pcall(function() tip:SetUnitBuff("player", index) end)
        local n = tipLine1()
        tex = a3 or a1
        count = (type(a4) == "number" and a4) or (type(a2) == "number" and a2) or 1
        if type(GetPlayerBuffTimeLeft) == "function" and type(GetPlayerBuff) == "function" then
            local bid = GetPlayerBuff(index - 1, "HELPFUL")
            if bid and bid >= 0 then
                timeLeft = GetPlayerBuffTimeLeft(bid)
            end
        end
        return n, tex, count, timeLeft
    end
    tip:ClearLines()
    pcall(function() tip:SetUnitBuff("player", index) end)
    local name = tipLine1()
    if type(GetPlayerBuffTimeLeft) == "function" and type(GetPlayerBuff) == "function" then
        local bid = GetPlayerBuff(index - 1, "HELPFUL")
        if bid and bid >= 0 then
            timeLeft = GetPlayerBuffTimeLeft(bid)
        end
    end
    return name, tex, count, timeLeft
end

local function findActiveImbue()
    local now = GetTime and GetTime() or 0
    local function expSec(has, exp)
        if not has then return nil end
        local n = tonumber(exp)
        if n and n > 0 then return n / 1000 end
        return nil
    end
    local sec, slot = nil, 16
    if type(GetWeaponEnchantInfo) == "function" then
        local hasMH, mhExp, mhCharges, hasOH, ohExp, ohCharges = GetWeaponEnchantInfo()
        local mh = expSec(hasMH, mhExp)
        local oh = expSec(hasOH, ohExp)
        if mh then
            sec = mh
            slot = 16
        elseif oh then
            sec = oh
            slot = 17
        end
    end
    local function scanWeaponTip(invSlot)
        if not invSlot then return nil end
        tip:SetOwner(UIParent, "ANCHOR_NONE")
        tip:ClearLines()
        local ok = pcall(function()
            if tip.SetInventoryItem then
                tip:SetInventoryItem("player", invSlot)
            end
        end)
        if not ok then return nil end
        local li
        for li = 1, 15 do
            local fs = getglobal("IchaUIShamanExtraTipTextLeft" .. li)
            local t = fs and fs:GetText()
            local key = matchKey(t, IMBUE_MATCH)
            if key then return key end
        end
        return nil
    end
    local nameKey = nil
    do
        local k = scanWeaponTip(slot)
        if k then nameKey = k end
        if not nameKey and slot == 16 then
            k = scanWeaponTip(17)
            if k then nameKey = k end
        end
    end
    -- Buff names only as fallback. Totem buffs share needles (Windfury / Rockbiter / Flametongue).
    if not nameKey then
        local i
        for i = 1, 32 do
            local name, tex = readPlayerBuff(i)
            if not name and not tex then break end
            if name then
                local l = string.lower(name)
                if not string.find(l, "totem", 1, true) then
                    local key = matchKey(name, IMBUE_MATCH)
                    if key then
                        nameKey = key
                        break
                    end
                end
            end
        end
    end

    if sec and sec > 0 then
        imbueHold.sec = sec
        imbueHold.at = now
        if nameKey then imbueHold.key = nameKey end
        local key = nameKey or imbueHold.key or "__enchant__"
        return key, iconFor(key, IMBUE_ICONS), sec
    end

    local held = nil
    if imbueHold.sec and imbueHold.at then
        held = imbueHold.sec - (now - imbueHold.at)
    end
    local withinGrace = (now - (imbueHold.at or 0)) < IMBUE_HOLD_GRACE
    if held and held > 0 and withinGrace then
        local key = nameKey or imbueHold.key or "__enchant__"
        if nameKey then imbueHold.key = nameKey end
        return key, iconFor(key, IMBUE_ICONS), held
    end

    imbueHold.key = nil
    imbueHold.sec = nil
    imbueHold.at = 0
    return nil, nil, nil
end

local function shieldKeyFromName(name)
    if not name then return nil end
    local key = matchKey(name, SHIELD_MATCH)
    if key then return key end
    local l = string.lower(name)
    -- tighter singles if tooltip is short / colored leftovers stripped
    if string.find(l, "lightning", 1, true) and string.find(l, "shield", 1, true) then
        return "Lightning Shield"
    end
    if string.find(l, "water", 1, true) and string.find(l, "shield", 1, true) then
        return "Water Shield"
    end
    if string.find(l, "earth", 1, true) and string.find(l, "shield", 1, true) then
        return "Earth Shield"
    end
    return nil
end

local function shieldKeyFromTexture(tex)
    if not tex or tex == "" then return nil end
    local low = string.lower(tex)
    -- strip path noise
    if string.find(low, "lightningshield", 1, true) then return "Lightning Shield" end
    if string.find(low, "watershield", 1, true) then return "Water Shield" end
    if string.find(low, "ability_shaman_water", 1, true) then return "Water Shield" end
    if string.find(low, "skinofearth", 1, true) then return "Earth Shield" end
    if string.find(low, "earthshield", 1, true) then return "Earth Shield" end
    -- exact match vs catalog / spellbook cache
    local k, v
    for k, v in pairs(SHIELD_ICONS) do
        if v and string.lower(v) == low then return k end
    end
    ensureKnown()
    for k, v in pairs(knownCache) do
        if SHIELD_ICONS[k] and v.tex and string.lower(v.tex) == low then return k end
    end
    return nil
end

local function readShieldCharges(buffId, unitBuffCount)
    local charges = tonumber(unitBuffCount)
    if (not charges or charges < 1) and buffId and buffId >= 0 and type(GetPlayerBuffApplications) == "function" then
        charges = tonumber(GetPlayerBuffApplications(buffId))
    end
    if not charges or charges < 1 then charges = 1 end
    return charges
end

local function findActiveShield()
    -- 1) GetPlayerBuff scan (BuffBars-proven on this client)
    if type(GetPlayerBuff) == "function" and type(GetPlayerBuffTexture) == "function" then
        local i
        for i = 0, 31 do
            local id = GetPlayerBuff(i, "HELPFUL")
            if id == nil or id < 0 then break end
            local tex = GetPlayerBuffTexture(id)
            if tex then
                local key = shieldKeyFromTexture(tex)
                if not key then
                    tip:SetOwner(UIParent, "ANCHOR_NONE")
                    tip:ClearLines()
                    pcall(function() tip:SetPlayerBuff(id) end)
                    key = shieldKeyFromName(tipLine1())
                end
                if key then
                    return key, iconFor(key, SHIELD_ICONS) or tex, readShieldCharges(id, nil)
                end
            end
        end
    end

    -- 2) UnitBuff scan (ClassicAPI may return name-first or texture-first)
    if type(UnitBuff) == "function" then
        local i
        for i = 1, 40 do
            local a1, a2, a3, a4, a5, a6 = UnitBuff("player", i)
            if not a1 then break end
            local name, tex, count
            if type(a1) == "string" and (string.find(a1, "Interface") or string.find(a1, "Icons") or string.find(a1, "\\") or string.find(a1, "/")) then
                tex = a1
                count = (type(a2) == "number" and a2) or nil
            elseif type(a1) == "string" then
                name = a1
                if type(a3) == "string" then tex = a3 end
                if type(a2) == "string" and (string.find(a2, "Interface") or string.find(a2, "Icons")) then tex = a2 end
                count = (type(a4) == "number" and a4) or (type(a3) == "number" and a3) or (type(a2) == "number" and a2) or nil
            end
            local key = shieldKeyFromName(name) or shieldKeyFromTexture(tex)
            if not key and tex then
                tip:SetOwner(UIParent, "ANCHOR_NONE")
                tip:ClearLines()
                pcall(function() tip:SetUnitBuff("player", i) end)
                key = shieldKeyFromName(tipLine1())
            end
            if key then
                local bid = nil
                if type(GetPlayerBuff) == "function" then
                    bid = GetPlayerBuff(i - 1, "HELPFUL")
                    if bid and bid < 0 then bid = nil end
                end
                return key, iconFor(key, SHIELD_ICONS) or tex, readShieldCharges(bid, count)
            end
        end
    end

    return nil, nil, nil
end

local function findActiveUtility()
    if type(GetPlayerBuff) == "function" and type(GetPlayerBuffTexture) == "function" then
        local i
        for i = 0, 31 do
            local id = GetPlayerBuff(i, "HELPFUL")
            if id == nil or id < 0 then break end
            local tex = GetPlayerBuffTexture(id)
            local key = nil
            if tex then
                local low = string.lower(tex)
                if string.find(low, "windwalk", 1, true) then
                    key = "Water Walking"
                elseif string.find(low, "demonbreath", 1, true) then
                    key = "Water Breathing"
                end
            end
            if not key then
                tip:SetOwner(UIParent, "ANCHOR_NONE")
                tip:ClearLines()
                pcall(function() tip:SetPlayerBuff(id) end)
                key = matchKey(tipLine1(), UTILITY_MATCH)
            end
            if key == "Water Walking" or key == "Water Breathing" then
                local tl = nil
                if type(GetPlayerBuffTimeLeft) == "function" then
                    tl = GetPlayerBuffTimeLeft(id)
                end
                return key, iconFor(key, UTILITY_ICONS) or tex, tl
            end
        end
    end
    local i
    for i = 1, 32 do
        local name, tex, count, timeLeft = readPlayerBuff(i)
        if not name and not tex then break end
        local key = matchKey(name, UTILITY_MATCH)
        if key == "Water Walking" or key == "Water Breathing" then
            return key, tex or iconFor(key, UTILITY_ICONS), timeLeft
        end
    end
    return nil, nil, nil
end

local function spellCooldownLeft(key)
    if not key then return 0 end
    ensureKnown()
    local entry = knownCache[key]
    -- Talent-only cache can omit index; resolve once from the spellbook so
    -- drawer rows can show CD without the spell being the selected/set ability.
    if entry and not entry.index and not entry._triedCdIndex and type(GetSpellName) == "function" then
        entry._triedCdIndex = true
        local book = BOOKTYPE_SPELL or "spell"
        local i = 1
        while i <= 500 do
            local name = GetSpellName(i, book)
            if not name then break end
            if matchKey(name, UTILITY_MATCH) == key then
                entry.index = i
                if not entry.name then entry.name = name end
            end
            i = i + 1
        end
    end
    if not entry or not entry.index or type(GetSpellCooldown) ~= "function" then
        return 0
    end
    local start, duration = GetSpellCooldown(entry.index, BOOKTYPE_SPELL or "spell")
    start = tonumber(start) or 0
    duration = tonumber(duration) or 0
    if start <= 0 or duration <= 2 then return 0 end
    local now = GetTime and GetTime() or 0
    local left = start + duration - now
    if left < 0 then left = 0 end
    return left
end

local function stripUiCodes(s)
    if not s then return nil end
    s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
    s = string.gsub(s, "|r", "")
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

local function itemNameFromLink(link)
    if not link then return nil end
    local _, _, name = string.find(link, "%[([^%]]+)%]")
    return stripUiCodes(name)
end

local function extractSpellReagent(key)
    if not key then return nil end
    if spellReagentName[key] ~= nil then
        if spellReagentName[key] == false then return nil end
        return spellReagentName[key]
    end
    ensureKnown()
    local entry = knownCache[key]
    if not entry or not entry.index or not tip.SetSpell then
        spellReagentName[key] = false
        return nil
    end
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:ClearLines()
    pcall(function()
        tip:SetSpell(entry.index, BOOKTYPE_SPELL or "spell")
    end)
    local found = nil
    local li
    for li = 1, 20 do
        local fs = getglobal("IchaUIShamanExtraTipTextLeft" .. li)
        local t = fs and fs:GetText()
        if t and t ~= "" then
            local _, _, name = string.find(t, "[Rr]eagents?:%s*(.+)")
            if not name then
                _, _, name = string.find(t, "[Rr]equires%s+[Rr]eagent:?%s*(.+)")
            end
            if name then
                name = stripUiCodes(name)
                name = string.gsub(name, "%s*%(%d+%)%s*$", "")
                local comma = string.find(name, ",", 1, true)
                if comma then
                    name = string.sub(name, 1, comma - 1)
                    name = stripUiCodes(name)
                end
                if name ~= "" and not string.find(string.lower(name), "level", 1, true) then
                    found = name
                    break
                end
            end
        end
    end
    if found then
        spellReagentName[key] = found
        return found
    end
    spellReagentName[key] = false
    return nil
end

local function itemMatchesUtilityReagent(itemName, spellKey)
    if not itemName or itemName == "" or not spellKey then return false end
    local l = string.lower(itemName)
    local function hitsNeedles(needles)
        if not needles then return false end
        local i
        for i = 1, table.getn(needles) do
            if string.find(l, needles[i], 1, true) then
                return true
            end
        end
        return false
    end
    if hitsNeedles(UTILITY_REAGENT_NEEDLES[spellKey]) then
        return true
    end
    -- Exclusive: Scales belong to Breathing, Oil to Walking — do not also claim via tooltip.
    local other = "Water Breathing"
    if spellKey == "Water Breathing" then other = "Water Walking" end
    if hitsNeedles(UTILITY_REAGENT_NEEDLES[other]) then
        return false
    end
    local req = extractSpellReagent(spellKey)
    if type(req) == "string" and req ~= "" then
        local rl = string.lower(req)
        if l == rl then return true end
        if string.len(rl) >= 6 and string.find(l, rl, 1, true) then return true end
    end
    return false
end

local function bagSlotNameAndCount(bag, slot)
    local tex, count
    if type(GetContainerItemInfo) == "function" then
        tex, count = GetContainerItemInfo(bag, slot)
    end
    local link = nil
    if type(GetContainerItemLink) == "function" then
        link = GetContainerItemLink(bag, slot)
    end
    local name = itemNameFromLink(link)
    local id = nil
    if type(link) == "string" then
        local _, _, found = string.find(link, "item:(%d+)")
        id = found
    end
    if (not tex or tex == "") and not name and not id then
        return nil, 0, nil
    end
    if not name then
        tip:SetOwner(UIParent, "ANCHOR_NONE")
        tip:ClearLines()
        pcall(function()
            if tip.SetBagItem then
                tip:SetBagItem(bag, slot)
            end
        end)
        name = stripUiCodes(tipLine1())
    end
    if (not name or name == "") and not id then return nil, 0, nil end
    return name, tonumber(count) or 1, id
end

local function ensureReagentCounts()
    if not reagentDirty then return end
    reagentDirty = false
    itemCountById = {}
    itemCountByName = {}
    itemScanOk = false
    reagentCounts["Water Walking"] = 0
    reagentCounts["Water Breathing"] = 0
    extractSpellReagent("Water Walking")
    extractSpellReagent("Water Breathing")
    if type(GetContainerNumSlots) ~= "function" then return end
    itemScanOk = true
    local bag
    for bag = 0, 4 do
        local slots = tonumber(GetContainerNumSlots(bag)) or 0
        local slot
        for slot = 1, slots do
            local name, n, id = bagSlotNameAndCount(bag, slot)
            n = tonumber(n) or 0
            if id and id ~= "" and n > 0 then
                itemCountById[id] = (tonumber(itemCountById[id]) or 0) + n
            end
            if name and name ~= "" and n > 0 then
                local lk = string.lower(name)
                itemCountByName[lk] = (tonumber(itemCountByName[lk]) or 0) + n
                if itemMatchesUtilityReagent(name, "Water Walking") then
                    reagentCounts["Water Walking"] = reagentCounts["Water Walking"] + n
                elseif itemMatchesUtilityReagent(name, "Water Breathing") then
                    reagentCounts["Water Breathing"] = reagentCounts["Water Breathing"] + n
                end
            end
        end
    end
end

local function utilityReagentCount(key)
    ensureReagentCounts()
    return tonumber(reagentCounts[key]) or 0
end

-- Bag total for a real item. nil when the container API is missing.
-- 0 when the scan ran and the bags do not hold that item (same as utility reagents).
function IchaUI_InvalidateBagItemCount()
    reagentDirty = true
end

function IchaUI_BagItemCount(itemId, itemName)
    ensureReagentCounts()
    if not itemScanOk then return nil end
    if itemId ~= nil and tostring(itemId) ~= "" then
        return tonumber(itemCountById[tostring(itemId)]) or 0
    end
    if type(itemName) == "string" and itemName ~= "" then
        return tonumber(itemCountByName[string.lower(itemName)]) or 0
    end
    return nil
end

-- Closed-circle cast + tooltip use the drawer SET, not the live buff.
-- Live aura used to overwrite last in paint, so drawer clicks appeared to no-op.
local function currentKey(id)
    local key = lastOrDefault(id)
    if id == "utility" and not utilityShown(key) then
        local i
        for i = 1, table.getn(UTILITY_LIST) do
            local k = UTILITY_LIST[i]
            if utilityShown(k) and knownCache[k] then return k end
        end
    end
    return key
end

----------------------------------------------------------------
-- Generic circle widget factory
----------------------------------------------------------------
local extrasTestMode = false
local widgets = {} -- id -> widget


local function shiftDrawerRequired()
    if IchaUITotems_Get then
        local g = IchaUITotems_Get()
        if g and g.shiftDrawer then return true end
    end
    return false
end


local function showSpellTip(owner, spellName)
    if not spellName or spellName == "" or spellName == "__none__" or spellName == "__enchant__" then return end
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
    -- Shift-hover tips stay on TOOLTIP (above icon / duration text)
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

local function extrasIconStrata()
    if type(IchaUI_GetIconStrata) == "function" then
        local n = IchaUI_GetIconStrata()
        if n and n ~= "" then return n end
    end
    return "MEDIUM"
end

local function extrasDrawerOpenStrata()
    if type(IchaUI_DrawerOpenStrata) == "function" then
        local n = IchaUI_DrawerOpenStrata()
        if n and n ~= "" then return n end
    end
    local base = extrasIconStrata()
    if base == "BACKGROUND" then return "LOW" end
    if base == "LOW" then return "MEDIUM" end
    if base == "MEDIUM" then return "HIGH" end
    return "DIALOG"
end

local function applyWidgetStrata(w, drawerOpen)
    if not w then return end
    local iconName = extrasIconStrata()
    if IchaUI_DrawerStyleGet and w.id then
        local savedStrata = IchaUI_DrawerStyleGet(w.id)
        if savedStrata and savedStrata ~= "" then iconName = savedStrata end
    end
    local textName = iconName
    if w.root then
        pcall(function()
            w.root:SetFrameStrata(iconName)
        end)
    end
    if w.textLayer then
        pcall(function()
            w.textLayer:SetFrameStrata(textName)
            local add = 8
            if textName == iconName then
                add = 12
            end
            w.textLayer:SetFrameLevel((w.slot and w.slot.GetFrameLevel and (w.slot:GetFrameLevel() or 1) or 1) + add)
        end)
    end
    if w.mover and w.mover.SetFrameStrata then
        pcall(function()
            w.mover:SetFrameStrata(iconName)
            local base = 1
            if w.slot and w.slot.GetFrameLevel then base = w.slot:GetFrameLevel() or 1 end
            w.mover:SetFrameLevel(base + 20)
        end)
    end
    if w.drawer then
        local open = drawerOpen
        if open == nil then
            open = w.drawer:IsShown() and true or false
        end
        local dname = iconName
        local fl = 10
        if open then
            dname = extrasDrawerOpenStrata()
            fl = 40
        end
        pcall(function()
            w.drawer:SetFrameStrata(dname)
            w.drawer:SetFrameLevel(fl)
        end)
        if w.drawer.rows then
            local i
            for i = 1, table.getn(w.drawer.rows) do
                local row = w.drawer.rows[i]
                if row then
                    pcall(function()
                        row:SetFrameStrata(dname)
                        row:SetFrameLevel(fl + 4)
                    end)
                    if row.countLayer then
                        pcall(function()
                            row.countLayer:SetFrameStrata(dname)
                            row.countLayer:SetFrameLevel((row:GetFrameLevel() or fl) + 6)
                        end)
                    end
                end
            end
        end
    end
end

function IchaUI_ApplyShamanExtrasStrata()
    local id, w
    for id, w in pairs(widgets) do
        if w then
            local open = false
            if w.drawer and w.drawer.IsShown then
                open = w.drawer:IsShown() and true or false
            end
            applyWidgetStrata(w, open)
        end
    end
end

local function canHoverOpenDrawer()
    if not shiftDrawerRequired() then return true end
    return IsShiftKeyDown and IsShiftKeyDown()
end

local function hideOtherDrawers(exceptId)
    local id, w
    for id, w in pairs(widgets) do
        if id ~= exceptId and w.drawer then
            w.drawer:Hide()
            w.pinned = nil
            w.closeAt = nil
        end
    end
end

local refreshWidget

-- Drawer-row reagent / cooldown text (Reincarnation + Astral Recall CD even when not set).
local function paintDrawerRowText(row)
    if not row or row.isNone or not row.base then return end
    local fs = row.cdFs
    if not fs then return end
    local base = row.base
    if base == "Water Walking" or base == "Water Breathing" then
        local n = utilityReagentCount(base)
        fs:SetText(tostring(n))
        if n <= 0 then
            fs:SetTextColor(1, 0.15, 0.15)
        else
            fs:SetTextColor(1, 0.92, 0.65)
        end
        fs:Show()
        return
    end
    if base == "Astral Recall" or base == "Reincarnation" then
        local sec = spellCooldownLeft(base)
        if sec and sec > 0 then
            fs:SetText(formatTime(sec))
            fs:SetTextColor(1, 0.92, 0.65)
            fs:Show()
        else
            fs:SetText("")
            fs:Hide()
        end
        return
    end
    fs:SetText("")
    fs:Hide()
end

local function buildDrawer(w)
    local dr = w.drawer
    if not dr then return end
    ensureKnown()
    if dr.rows then
        local i
        for i = 1, table.getn(dr.rows) do
            dr.rows[i]:Hide()
            dr.rows[i]:SetParent(nil)
        end
    end
    dr.rows = {}
    local scale = totemScale()
    local iconSz = math.floor(totemDrawerSize() * scale + 0.5)
    if iconSz < 14 then iconSz = 14 end
    if iconSz > 48 then iconSz = 48 end
    iconSz = math.floor(iconSz * drawerPopScale(w.id) + 0.5)
    local gap = math.floor(totemDrawerGap() * scale + 0.5)
    if gap < 0 then gap = 0 end
    local cols = 1
    if IchaUI_DrawerGridCols and w.id then
        local gridCols = IchaUI_DrawerGridCols(w.id, table.getn(list or {}))
        if gridCols and gridCols >= 1 then cols = gridCols end
    end
    local shown = 0
    local list = w.spellList
    local icons = w.iconTable
    local dir = extrasDrawerDir(w.id)

    local function addRow(base, tex, isNone)
        shown = shown + 1
        local row = CreateFrame("Button", nil, dr)
        row:SetWidth(iconSz)
        row:SetHeight(iconSz)
        local idx = shown - 1
        local step = iconSz + gap
        if dir == "radial" then
            row:SetPoint("CENTER", dr, "CENTER", 0, 0)
        elseif dir == "up" then
            row:SetPoint("BOTTOMLEFT", dr, "BOTTOMLEFT", 0, idx * step)
        elseif dir == "down" then
            row:SetPoint("TOPLEFT", dr, "TOPLEFT", 0, -idx * step)
        elseif dir == "right" then
            row:SetPoint("BOTTOMLEFT", dr, "BOTTOMLEFT", idx * step, 0)
        else
            row:SetPoint("BOTTOMRIGHT", dr, "BOTTOMRIGHT", -idx * step, 0)
        end
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.base = base
        row.widgetId = w.id
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
        applyGoldRing(goldRing, row, iconSz)

        if not isNone and (base == "Water Walking" or base == "Water Breathing"
            or base == "Astral Recall" or base == "Reincarnation") then
            local tlayer = CreateFrame("Frame", nil, row)
            tlayer:SetAllPoints(row)
            row.countLayer = tlayer
            local cfs = tlayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cfs:SetPoint("CENTER", ic, "CENTER", 0, 0)
            local dfs = math.max(6, math.floor(extrasTextSize() * scale + 0.5))
            local fontPath = GameFontHighlightSmall:GetFont()
            if fontPath then
                cfs:SetFont(fontPath, dfs, "THICKOUTLINE")
                if cfs.SetShadowColor then
                    cfs:SetShadowColor(0, 0, 0, 1)
                    cfs:SetShadowOffset(1, -1)
                end
            end
            row.cdFs = cfs
            paintDrawerRowText(row)
        end

        local hilite = row:CreateTexture(nil, "OVERLAY")
        hilite:SetAllPoints(ic)
        hilite:SetTexture("Interface/Buttons/ButtonHilight-Square")
        hilite:SetBlendMode("ADD")
        hilite:SetAlpha(0)

        row:SetScript("OnEnter", function()
            hilite:SetAlpha(0.45)
            local ww = widgets[this.widgetId]
            if ww then ww.closeAt = nil end
            if this.isNone or not this.base or this.base == "__none__" then
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
            hilite:SetAlpha(0)
            this._ichaTipSpell = nil
            this._ichaTipShown = nil
            this:SetScript("OnUpdate", nil)
            hideSpellTip()
            local ww = widgets[this.widgetId]
            if ww and not ww.pinned then
                ww.closeAt = (GetTime and GetTime() or 0) + DRAWER_CLOSE_DELAY
            end
        end)
        -- Open-drawer click assigns the closed-circle set spell only. Never
        -- CastSpell here — hardware cast is the closed slot's OnClick.
        row:SetScript("OnClick", function()
            if this.isNone then return end
            local ww = widgets[this.widgetId]
            if ww then
                rememberLast(ww.id, this.base)
                if ww.icon then
                    ww.icon:SetTexture(iconFor(this.base, ww.iconTable))
                    ww.icon:SetVertexColor(1, 1, 1, 1)
                end
                ww.drawer:Hide()
                ww.pinned = nil
                refreshWidget(ww)
            end
        end)
        table.insert(dr.rows, row)
    end

    local i
    for i = 1, table.getn(list) do
        local base = list[i]
        if (knownCache[base] or extrasTestMode) and (w.id ~= "utility" or utilityShown(base)) then
            addRow(base, iconFor(base, icons), false)
        end
    end

    if shown < 1 then shown = 1 end
    if dir == "radial" and IchaUI_DrawerRadialRadius and IchaUI_DrawerRadialXY then
        local slotSz = iconSz
        if w.slot and w.slot.GetWidth then slotSz = w.slot:GetWidth() or iconSz end
        local spread = 90
        local bag = db()[w.id]
        if bag and bag.drawerSpread then spread = bag.drawerSpread end
        local arc, rot = nil, nil
        if bag then arc, rot = bag.drawerArc, bag.drawerRot end
        local radius = IchaUI_DrawerRadialRadius(shown, slotSz, iconSz, gap, spread)
        local ri
        for ri = 1, shown do
            local row = dr.rows[ri]
            if row then
                local rx, ry = IchaUI_DrawerRadialXY(ri, shown, radius, arc, rot)
                row:ClearAllPoints()
                row:SetPoint("CENTER", dr, "CENTER", rx, ry)
            end
        end
        dr:SetWidth(2)
        dr:SetHeight(2)
    elseif dir == "left" or dir == "right" then
        dr:SetWidth(shown * iconSz + math.max(0, shown - 1) * gap)
        dr:SetHeight(iconSz)
    else
        dr:SetWidth(iconSz)
        dr:SetHeight(shown * iconSz + math.max(0, shown - 1) * gap)
    end
end

local function showDrawer(w, pin)
    hideOtherDrawers(w.id)
    buildDrawer(w)
    w.drawer:ClearAllPoints()
    local dir = extrasDrawerDir(w.id)
    if dir == "radial" then
        w.drawer:SetPoint("CENTER", w.slot, "CENTER", 0, 0)
        w.drawer:EnableMouse(false)
    else
        w.drawer:EnableMouse(true)
        if dir == "up" then
            w.drawer:SetPoint("BOTTOM", w.slot, "TOP", 0, 1)
        elseif dir == "down" then
            w.drawer:SetPoint("TOP", w.slot, "BOTTOM", 0, -1)
        elseif dir == "left" then
            w.drawer:SetPoint("RIGHT", w.slot, "LEFT", -1, 0)
        else
            w.drawer:SetPoint("LEFT", w.slot, "RIGHT", 1, 0)
        end
    end
    applyWidgetStrata(w, true)
    w.drawer:Show()
    if w.drawer.Raise then w.drawer:Raise() end
    if w.drawer.rows then
        local i
        for i = 1, table.getn(w.drawer.rows) do
            local row = w.drawer.rows[i]
            if row then
                row:EnableMouse(true)
                row:SetFrameLevel((w.drawer:GetFrameLevel() or 40) + 4)
                if row.Raise then row:Raise() end
                if row.countLayer then
                    local cname = extrasDrawerOpenStrata()
                    if not cname or cname == "" then cname = "MEDIUM" end
                    row.countLayer:SetFrameStrata(cname)
                    row.countLayer:SetFrameLevel((row:GetFrameLevel() or 1) + 6)
                end
            end
        end
    end
    if pin then
        w.pinned = true
        w.closeAt = nil
    else
        w.pinned = nil
    end
end

local function layoutWidget(w)
    local scale = totemScale()
    local size = math.floor(totemSize() * scale + 0.5)
    local fs = math.max(6, math.floor(extrasTextSize() * scale + 0.5))
    size = math.floor(size * drawerButtonScale(w.id) + 0.5)
    w.root:SetWidth(size)
    w.root:SetHeight(size + 8)
    w.slot:SetWidth(size)
    w.slot:SetHeight(size)
    w.slot:ClearAllPoints()
    w.slot:SetPoint("BOTTOM", w.root, "BOTTOM", 0, 0)
    insetIcon(w.icon, w.slot, size)
    if w.roundMask then
        w.roundMask:ClearAllPoints()
        w.roundMask:SetPoint("TOPLEFT", w.icon, "TOPLEFT", 0, 0)
        w.roundMask:SetPoint("BOTTOMRIGHT", w.icon, "BOTTOMRIGHT", 0, 0)
        w.roundMask:SetTexture(ROUNDMASK)
        w.roundMask:SetVertexColor(0, 0, 0, 1)
        w.roundMask:Show()
    end
    applyGoldRing(w.goldRing, w.slot, size)
    local formShape = "circle"
    if IchaUI_DrawerShape then formShape = IchaUI_DrawerShape(w.id) end
    if formShape == "rect" then
        w.slot:SetWidth(math.floor(size * 4 / 3 + 0.5))
        w.root:SetWidth(math.floor(size * 4 / 3 + 0.5))
    end
    if IchaUI_ApplyButtonForm then IchaUI_ApplyButtonForm(w.slot, formShape) end
    w.text:ClearAllPoints()
    w.text:SetPoint("CENTER", w.icon, "CENTER", 0, 0)
    local fontPath = GameFontHighlightSmall:GetFont()
    if fontPath then
        w.text:SetFont(fontPath, fs, "THICKOUTLINE")
        if w.text.SetShadowColor then
            w.text:SetShadowColor(0, 0, 0, 1)
            w.text:SetShadowOffset(1, -1)
        end
        if w.drawer and w.drawer.rows then
            local ri
            for ri = 1, table.getn(w.drawer.rows) do
                local row = w.drawer.rows[ri]
                if row and row.cdFs then
                    row.cdFs:SetFont(fontPath, fs, "THICKOUTLINE")
                end
            end
        end
    end
    if w.mover then w.mover:SetAllPoints(w.root) end
end

local function restorePos(w)
    local d = db()[w.id]
    w.root:ClearAllPoints()
    if d and d.point and d.x ~= nil then
        w.root:SetPoint(d.point, UIParent, d.relPoint or d.point, d.x, d.y or 0)
    else
        if w.id == "imbue" then
            w.root:SetPoint("BOTTOM", UIParent, "BOTTOM", 120, 160)
        elseif w.id == "shield" then
            w.root:SetPoint("BOTTOM", UIParent, "BOTTOM", 170, 160)
        else
            w.root:SetPoint("BOTTOM", UIParent, "BOTTOM", 220, 160)
        end
    end
end

local function savePos(w)
    local d = db()
    if not d[w.id] then d[w.id] = {} end
    local s = d[w.id]
    local p, _, rp, x, y = w.root:GetPoint(1)
    s.point = p
    s.relPoint = rp or p
    s.x = tonumber(x) or 0
    s.y = tonumber(y) or 0
    IchaUIDB.shamanExtras = d
end

local function updateVisibility(w)
    local d = db()[w.id] or {}
    if extrasTestMode then
        w.root:Show()
        return
    end
    if not isPlayerShaman() then
        w.root:Hide()
        if w.drawer then w.drawer:Hide() end
        return
    end
    if d.hidden then
        w.root:Hide()
        if w.drawer then w.drawer:Hide() end
    else
        w.root:Show()
    end
end

local function extrasShowText(which)
    if which ~= "imbue" and which ~= "shield" then return true end
    local d = db()[which]
    if d and d.showText == false then return false end
    return true
end

local function finishActiveText(w)
    if not w or not w.text then return end
    if extrasShowText(w.id) then
        w.text:Show()
    else
        w.text:Hide()
    end
end

local function paintImbue(w)
    if extrasTestMode and not findActiveImbue() then
        w.icon:SetTexture(IMBUE_ICONS["Windfury Weapon"])
        applyIconTint(w)
        w.text:SetText("45")
        w.text:SetTextColor(1, 0.15, 0.15) -- < 60s demo → red
        finishActiveText(w)
        return
    end
    local last = lastOrDefault("imbue")
    w.icon:SetTexture(iconFor(last, IMBUE_ICONS))
    applyIconTint(w)
    local key, tex, sec = findActiveImbue()
    local known = key
    if key == "__enchant__" then known = nil end
    -- Hide only when a different known imbue is on the weapon. Unknown name +
    -- live/held duration still counts on the set circle (failed tooltip must not blank).
    local showTimer = false
    if sec and sec > 0 then
        if known and IMBUE_ICONS[known] then
            showTimer = (known == last)
        else
            showTimer = true
        end
    end
    if showTimer then
        if tex and known == last then w.icon:SetTexture(tex) end
        w.text:SetText(formatTime(sec))
        if sec < IMBUE_WARN_SEC then
            w.text:SetTextColor(1, 0.15, 0.15)
        else
            w.text:SetTextColor(1, 0.92, 0.65)
        end
        finishActiveText(w)
        return
    end
    w.text:SetText("")
    w.text:Hide()
end

local function paintShield(w)
    if extrasTestMode and not findActiveShield() then
        w.icon:SetTexture(SHIELD_ICONS["Lightning Shield"])
        applyIconTint(w)
        w.text:SetText("2")
        w.text:SetTextColor(1, 0.15, 0.15) -- ≤2 demo → red
        finishActiveText(w)
        return
    end
    local last = lastOrDefault("shield")
    w.icon:SetTexture(iconFor(last, SHIELD_ICONS))
    applyIconTint(w)
    local key, tex, charges = findActiveShield()
    if key == last then
        w.icon:SetTexture(iconFor(last, SHIELD_ICONS) or tex)
        local n = tonumber(charges) or 1
        if n < 1 then n = 1 end
        w.text:SetText(tostring(n))
        if n <= SHIELD_WARN_CHARGES then
            w.text:SetTextColor(1, 0.15, 0.15)
        else
            w.text:SetTextColor(1, 0.92, 0.65)
        end
        finishActiveText(w)
        return
    end
    w.text:SetText("")
    w.text:Hide()
end

local function paintUtility(w)
    if extrasTestMode then
        w.icon:SetTexture(UTILITY_ICONS["Water Walking"])
        applyIconTint(w)
        w.text:SetText("45")
        w.text:SetTextColor(1, 0.15, 0.15)
        w.text:Show()
        return
    end
    local last = currentKey("utility")
    w.icon:SetTexture(iconFor(last, UTILITY_ICONS))
    applyIconTint(w)
    if last == "Water Walking" or last == "Water Breathing" then
        local key, tex, timeLeft = findActiveUtility()
        local sec = nil
        if key == last then
            if tex then w.icon:SetTexture(tex) end
            sec = tonumber(timeLeft)
        end
        if sec and sec > 0 then
            w.text:SetText(formatTime(sec))
            if sec < IMBUE_WARN_SEC then
                w.text:SetTextColor(1, 0.15, 0.15)
            else
                w.text:SetTextColor(1, 0.92, 0.65)
            end
            w.text:Show()
            return
        end
        local n = utilityReagentCount(last)
        w.text:SetText(tostring(n))
        if n <= 0 then
            w.text:SetTextColor(1, 0.15, 0.15)
        else
            w.text:SetTextColor(1, 0.92, 0.65)
        end
        w.text:Show()
        return
    end
    if last == "Astral Recall" or last == "Reincarnation" then
        local sec = spellCooldownLeft(last)
        if sec and sec > 0 then
            w.text:SetText(formatTime(sec))
            w.text:SetTextColor(1, 0.92, 0.65)
            w.text:Show()
        else
            w.text:SetText("")
            w.text:Hide()
        end
        return
    end
    w.text:SetText("")
    w.text:Hide()
end

refreshWidget = function(w)
    if not w or not w.root then return end
    if w.id == "imbue" then
        paintImbue(w)
    elseif w.id == "shield" then
        paintShield(w)
    else
        paintUtility(w)
    end
    if w.drawer and w.drawer.IsShown and w.drawer:IsShown() and w.drawer.rows then
        local ri
        for ri = 1, table.getn(w.drawer.rows) do
            paintDrawerRowText(w.drawer.rows[ri])
        end
    end
end

local function makeWidget(id, spellList, iconTable, paintFn)
    local w = { id = id, spellList = spellList, iconTable = iconTable, moving = false }
    local tag = "Shield"
    if id == "imbue" then tag = "Imbue" end
    if id == "utility" then tag = "Utility" end

    local root = CreateFrame("Frame", "IchaUI" .. tag .. "Root", UIParent)
    root:SetMovable(true)
    root:EnableMouse(false)
    root:SetWidth(40)
    root:SetHeight(48)
    root:Hide()
    w.root = root

    local slot = CreateFrame("Button", "IchaUI" .. tag .. "Slot", root)
    slot:EnableMouse(true)
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    w.slot = slot

    local circleBg = slot:CreateTexture(nil, "BACKGROUND")
    circleBg:SetTexture("Interface\\AddOns\\IchaUI\\media\\circledisc.tga")
    circleBg:SetVertexColor(0.05, 0.05, 0.06, 1)
    w.circleBg = circleBg
    slot.circleBg = circleBg

    local icon = slot:CreateTexture(nil, "ARTWORK")
    w.icon = icon
    slot.icon = icon
    if IchaUI_WrapButtonIcon then IchaUI_WrapButtonIcon(slot) end

    local round = slot:CreateTexture(nil, "ARTWORK")
    round:SetTexture(ROUNDMASK)
    round:SetVertexColor(0, 0, 0, 1)
    round:Show()
    w.roundMask = round
    slot.roundMask = round

    local goldRing = slot:CreateTexture(nil, "OVERLAY")
    goldRing:SetTexture(GOLD_RING)
    IchaUI_PaintGoldRing(goldRing)
    w.goldRing = goldRing
    slot.goldRing = goldRing

    local pushTex = slot:CreateTexture(nil, "OVERLAY")
    pushTex:SetTexture("Interface/ChatFrame/ChatFrameBackground")
    pushTex:SetVertexColor(0, 0, 0)
    pushTex:SetAlpha(0.18)
    pushTex:Hide()
    w.pushTex = pushTex

    -- Charge / remaining text. Strata matches this drawer (applyWidgetStrata).
    local textLayer = CreateFrame("Frame", nil, slot)
    textLayer:SetAllPoints(slot)
    w.textLayer = textLayer
    local text = textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetTextColor(1, 0.92, 0.65)
    text:Hide()
    w.text = text

    local mover = CreateFrame("Frame", nil, root)
    mover:SetAllPoints(root)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:Hide()
    mover:SetFrameLevel((root:GetFrameLevel() or 1) + 30)
    local mbg = mover:CreateTexture(nil, "BACKGROUND")
    mbg:SetAllPoints(mover)
    mbg:SetTexture(1, 1, 1, 1)
    mbg:SetVertexColor(0.15, 0.45, 0.95, 0.35)
    local ml = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ml:SetPoint("CENTER", mover, "CENTER")
    ml:SetText("Drag " .. id)
    mover:SetScript("OnDragStart", function() root:StartMoving() end)
    mover:SetScript("OnDragStop", function()
        root:StopMovingOrSizing()
        savePos(w)
    end)
    mover:SetScript("OnMouseUp", function()
        if arg1 == "RightButton" and IchaUI_DrawerEditClick then IchaUI_DrawerEditClick(id) end
    end)
    w.mover = mover

    local dr = CreateFrame("Frame", "IchaUI" .. tag .. "Drawer", UIParent)
    dr:SetWidth(40)
    dr:SetHeight(40)
    dr:EnableMouse(true)
    dr:Hide()
    dr:SetScript("OnEnter", function() w.closeAt = nil end)
    dr:SetScript("OnLeave", function()
        if not w.pinned then
            w.closeAt = (GetTime and GetTime() or 0) + DRAWER_CLOSE_DELAY
        end
    end)
    w.drawer = dr

    slot:SetScript("OnMouseDown", function()
        pushCircleSlot(slot, w.icon, w.roundMask, w.circleBg, w.pushTex)
    end)
    slot:SetScript("OnMouseUp", function()
        if not w._bindPushUntil then
            releaseCircleSlot(slot, w.icon, w.roundMask, w.circleBg, w.pushTex)
        end
    end)
    slot:SetScript("OnEnter", function()
        w.closeAt = nil
        w._drawerHover = true
        if canHoverOpenDrawer() then
            showDrawer(w, false)
        end
        local key = currentKey(id)
        this._ichaTipSpell = key
        this._ichaTipShown = nil
        if key and IsShiftKeyDown and IsShiftKeyDown() then
            showSpellTip(this, key)
            this._ichaTipShown = true
        end
        this:SetScript("OnUpdate", tipUpdateCheck)
    end)
    slot:SetScript("OnLeave", function()
        w._drawerHover = nil
        this._ichaTipSpell = nil
        this._ichaTipShown = nil
        this:SetScript("OnUpdate", nil)
        hideSpellTip()
        if not w._bindPushUntil then
            releaseCircleSlot(slot, w.icon, w.roundMask, w.circleBg, w.pushTex)
        end
        if not w.pinned then
            w.closeAt = (GetTime and GetTime() or 0) + DRAWER_CLOSE_DELAY
        end
    end)
    slot:SetScript("OnClick", function()
        if arg1 == "LeftButton" then
            local key = currentKey(id)
            if key then
                castSpell(key)
                rememberLast(id, key)
                return
            end
            if shiftDrawerRequired() and not (IsShiftKeyDown and IsShiftKeyDown()) then
                return
            end
            if w.drawer and w.drawer:IsShown() then
                w.drawer:Hide()
                w.pinned = nil
                w.closeAt = nil
            else
                showDrawer(w, false)
            end
        elseif arg1 == "RightButton" then
            if shiftDrawerRequired() and not (IsShiftKeyDown and IsShiftKeyDown()) then
                return
            end
            if w.drawer and w.drawer:IsShown() then
                w.drawer:Hide()
                w.pinned = nil
                w.closeAt = nil
            else
                showDrawer(w, false)
            end
        end
    end)

    local defKey = DEFAULT_SHIELD
    local defIcons = SHIELD_ICONS
    if id == "imbue" then
        defKey = DEFAULT_IMBUE
        defIcons = IMBUE_ICONS
    elseif id == "utility" then
        defKey = DEFAULT_UTILITY
        defIcons = UTILITY_ICONS
    end
    icon:SetTexture(iconFor(defKey, defIcons))
    widgets[id] = w
    applyWidgetStrata(w, false)
    restorePos(w)
    layoutWidget(w)
    updateVisibility(w)
    refreshWidget(w)
    return w
end

local imbueW = makeWidget("imbue", IMBUE_LIST, IMBUE_ICONS)
local shieldW = makeWidget("shield", SHIELD_LIST, SHIELD_ICONS)
local utilityW = makeWidget("utility", UTILITY_LIST, UTILITY_ICONS)

local function applyAll()
    layoutWidget(imbueW)
    layoutWidget(shieldW)
    layoutWidget(utilityW)
    updateVisibility(imbueW)
    updateVisibility(shieldW)
    updateVisibility(utilityW)
    refreshWidget(imbueW)
    refreshWidget(shieldW)
    refreshWidget(utilityW)
    IchaUI_ApplyShamanExtrasStrata()
    do
        local id, w
        for id, w in pairs(widgets) do
            if w and w.drawer and w.drawer.IsShown and w.drawer:IsShown() then
                showDrawer(w, w.pinned and true or false)
            end
        end
    end
end

function IchaUIShamanExtras_OnShieldBoundCast(spellName)
    if not spellName or spellName == "" then return end
    local key = shieldKeyFromName(spellName)
    if not key then
        local want = string.lower(spellName)
        local i
        for i = 1, table.getn(SHIELD_LIST) do
            if string.lower(SHIELD_LIST[i]) == want then
                key = SHIELD_LIST[i]
                break
            end
        end
    end
    if not key then key = spellName end
    if not SHIELD_ICONS[key] then return end
    rememberLast("shield", key)
    local w = widgets and widgets["shield"]
    if w and w.icon then
        w.icon:SetTexture(iconFor(key, SHIELD_ICONS))
        applyIconTint(w)
    end
end

local function pulseCircle(w)
    if not w or not w.slot then return end
    pushCircleSlot(w.slot, w.icon, w.roundMask, w.circleBg, w.pushTex)
    w._bindPushUntil = (GetTime and GetTime() or 0) + PUSH_MS
end

local function tickCirclePush(now)
    local id, w
    for id, w in pairs(widgets) do
        if w and w._bindPushUntil and now >= w._bindPushUntil then
            w._bindPushUntil = nil
            releaseCircleSlot(w.slot, w.icon, w.roundMask, w.circleBg, w.pushTex)
        end
    end
end

function IchaUIShamanExtras_PulsePush(which)
    if not which then return end
    pulseCircle(widgets[which])
end

function IchaUIShamanExtras_NotifyBoundCast(spellName)
    if not spellName or spellName == "" or not IchaUI_IsShaman() then return end
    local want = string.lower(spellName)
    want = string.gsub(want, "%s*%(.*%)$", "")
    local i
    for i = 1, table.getn(IMBUE_LIST) do
        if string.lower(IMBUE_LIST[i]) == want then
            pulseCircle(widgets["imbue"])
            return
        end
    end
    for i = 1, table.getn(SHIELD_LIST) do
        if string.lower(SHIELD_LIST[i]) == want then
            pulseCircle(widgets["shield"])
            return
        end
    end
    for i = 1, table.getn(UTILITY_LIST) do
        if string.lower(UTILITY_LIST[i]) == want then
            pulseCircle(widgets["utility"])
            return
        end
    end
end

function IchaUIShamanExtras_NotifyBoundTexture(tex)
    if not tex or tex == "" or not IchaUI_IsShaman() then return end
    local low = string.lower(string.gsub(tex, "/", "\\"))
    local k, v
    for k, v in pairs(IMBUE_ICONS) do
        if v and string.lower(string.gsub(v, "/", "\\")) == low then
            pulseCircle(widgets["imbue"])
            return
        end
    end
    for k, v in pairs(SHIELD_ICONS) do
        if v and string.lower(string.gsub(v, "/", "\\")) == low then
            pulseCircle(widgets["shield"])
            return
        end
    end
    for k, v in pairs(UTILITY_ICONS) do
        if v and string.lower(string.gsub(v, "/", "\\")) == low then
            pulseCircle(widgets["utility"])
            return
        end
    end
    ensureKnown()
    for k, v in pairs(knownCache) do
        if v and v.texture and string.lower(string.gsub(v.texture, "/", "\\")) == low then
            if IMBUE_ICONS[k] then
                pulseCircle(widgets["imbue"])
                return
            end
            if SHIELD_ICONS[k] then
                pulseCircle(widgets["shield"])
                return
            end
            if UTILITY_ICONS[k] then
                pulseCircle(widgets["utility"])
                return
            end
        end
    end
end

function IchaUIShamanExtras_Apply()
    applyAll()
end

function IchaUIShamanExtras_SetTestMode(on)
    if on and not IchaUI_IsShaman() then return end
    extrasTestMode = on and true or false
    applyAll()
end

function IchaUIShamanExtras_SetMove(which, on)
    local w = widgets[which]
    if not w or not IchaUI_IsShaman() then return end
    w.moving = on and true or false
    if w.moving then
        w.mover:Show()
        w.root:Show()
        DEFAULT_CHAT_FRAME:AddMessage("IchaUI: drag " .. which .. " — click Move again to lock.")
    else
        w.mover:Hide()
        savePos(w)
        updateVisibility(w)
        DEFAULT_CHAT_FRAME:AddMessage("IchaUI: " .. which .. " locked.")
    end
end

function IchaUIShamanExtras_ToggleMove(which)
    local w = widgets[which]
    if not w then return end
    IchaUIShamanExtras_SetMove(which, not w.moving)
end

function IchaUIShamanExtras_SetHidden(which, hidden)
    local d = db()
    if not d[which] then d[which] = {} end
    d[which].hidden = hidden and true or nil
    IchaUIDB.shamanExtras = d
    local w = widgets[which]
    if w then updateVisibility(w) end
end

function IchaUIShamanExtras_Get(which)
    local root = db()
    if which == nil or which == "" or which == "all" then
        return {
            textSize = extrasTextSize(),
        }
    end
    local w = widgets[which]
    local d = root[which] or {}
    return {
        moving = w and w.moving,
        hidden = d.hidden and true or false,
        x = d.x,
        y = d.y,
        textSize = extrasTextSize(),
        drawerDir = extrasDrawerDir(which),
        drawerSpread = (IchaUI_DrawerNormSpread and IchaUI_DrawerNormSpread(d.drawerSpread)) or 90,
        drawerArc = (IchaUI_DrawerNormArc and IchaUI_DrawerNormArc(d.drawerArc)) or 360,
        drawerRot = (IchaUI_DrawerNormRot and IchaUI_DrawerNormRot(d.drawerRot)) or 90,
        showText = not (d.showText == false),
    }
end

function IchaUIShamanExtras_GetDrawerDir(which)
    return extrasDrawerDir(which)
end

function IchaUIShamanExtras_GetDrawerSpread(which)
    local d = db()[which]
    local n = d and d.drawerSpread
    if IchaUI_DrawerNormSpread then return IchaUI_DrawerNormSpread(n) end
    n = tonumber(n) or 90
    if n < 10 then n = 10 end
    if n > 360 then n = 360 end
    return math.floor(n + 0.5)
end

function IchaUIShamanExtras_GetShowText(which)
    return extrasShowText(which)
end

function IchaUIShamanExtras_SetShowText(which, on)
    if which ~= "imbue" and which ~= "shield" then return end
    local d = db()
    if not d[which] then d[which] = {} end
    d[which].showText = on and true or false
    IchaUIDB.shamanExtras = d
    if applyAll then applyAll() end
end

-- Every row the utility drawer can show, in drawer order (copy).
function IchaUIShamanExtras_UtilityEntries()
    local out = {}
    local i
    for i = 1, table.getn(UTILITY_LIST) do
        table.insert(out, UTILITY_LIST[i])
    end
    return out
end

function IchaUIShamanExtras_GetUtilityShown(key)
    return utilityShown(key)
end

function IchaUIShamanExtras_SetUtilityShown(key, on)
    if not key or not UTILITY_ICONS[key] then return end
    if not IchaUIDB then IchaUIDB = {} end
    if type(IchaUIDB.utilityShow) ~= "table" then IchaUIDB.utilityShow = {} end
    IchaUIDB.utilityShow[key] = on and true or false
    if applyAll then applyAll() end
end

function IchaUIShamanExtras_SetDrawerDir(which, dir)
    if which ~= "imbue" and which ~= "shield" and which ~= "utility" then return end
    local s = string.lower(tostring(dir or "up"))
    if s ~= "down" and s ~= "left" and s ~= "right" and s ~= "radial" then s = "up" end
    local d = db()
    if not d[which] then d[which] = {} end
    d[which].drawerDir = s
    IchaUIDB.shamanExtras = d
    if applyAll then applyAll() end
end

function IchaUIShamanExtras_GetDrawerArc(which)
    local d = db()[which]
    local n = d and d.drawerArc
    if IchaUI_DrawerNormArc then return IchaUI_DrawerNormArc(n) end
    n = tonumber(n) or 360
    if n < 10 then n = 10 end
    if n > 360 then n = 360 end
    return math.floor(n + 0.5)
end

function IchaUIShamanExtras_GetDrawerRot(which)
    local d = db()[which]
    local n = d and d.drawerRot
    if IchaUI_DrawerNormRot then return IchaUI_DrawerNormRot(n) end
    if n == nil then return 90 end
    n = tonumber(n) or 90
    if n < -360 then n = -360 end
    if n > 360 then n = 360 end
    return math.floor(n + 0.5)
end

function IchaUIShamanExtras_SetDrawerSpread(which, value)
    if which ~= "imbue" and which ~= "shield" and which ~= "utility" then return end
    local n = tonumber(value) or 90
    if IchaUI_DrawerNormSpread then n = IchaUI_DrawerNormSpread(n) end
    if n < 10 then n = 10 end
    if n > 360 then n = 360 end
    local d = db()
    if not d[which] then d[which] = {} end
    d[which].drawerSpread = math.floor(n + 0.5)
    IchaUIDB.shamanExtras = d
    if applyAll then applyAll() end
end

function IchaUIShamanExtras_SetDrawerArc(which, value)
    if which ~= "imbue" and which ~= "shield" and which ~= "utility" then return end
    local n = tonumber(value)
    if n == nil then n = 360 end
    if IchaUI_DrawerNormArc then n = IchaUI_DrawerNormArc(n) end
    if n < 10 then n = 10 end
    if n > 360 then n = 360 end
    local d = db()
    if not d[which] then d[which] = {} end
    d[which].drawerArc = math.floor(n + 0.5)
    IchaUIDB.shamanExtras = d
    if applyAll then applyAll() end
end

function IchaUIShamanExtras_SetDrawerRot(which, value)
    if which ~= "imbue" and which ~= "shield" and which ~= "utility" then return end
    local n = tonumber(value)
    if n == nil then n = 90 end
    if IchaUI_DrawerNormRot then n = IchaUI_DrawerNormRot(n) end
    if n < -360 then n = -360 end
    if n > 360 then n = 360 end
    local d = db()
    if not d[which] then d[which] = {} end
    d[which].drawerRot = math.floor(n + 0.5)
    IchaUIDB.shamanExtras = d
    if applyAll then applyAll() end
end

function IchaUIShamanExtras_Set(field, value)
    if field == "textSize" then
        local n = tonumber(value) or DEFAULT_TEXT
        if n < 6 then n = 6 end
        if n > 28 then n = 28 end
        local d = db()
        d.textSize = n
        IchaUIDB.shamanExtras = d
        if applyAll then applyAll() end
    end
end

function IchaUIShamanExtras_Slash(rest)
    if not IchaUI_IsShaman() then
        DEFAULT_CHAT_FRAME:AddMessage("IchaUI: imbue / shield / utility are shaman-only.")
        return
    end
    rest = string.lower(rest or "")
    rest = string.gsub(rest, "^%s+", "")
    if string.find(rest, "^imbue") then
        rest = string.gsub(rest, "^imbue%s*", "")
        if rest == "move" then IchaUIShamanExtras_ToggleMove("imbue")
        elseif rest == "show" then IchaUIShamanExtras_SetHidden("imbue", false)
        elseif rest == "hide" then IchaUIShamanExtras_SetHidden("imbue", true)
        else DEFAULT_CHAT_FRAME:AddMessage("Imbue: /icha imbue move|show|hide") end
    elseif string.find(rest, "^shield") then
        rest = string.gsub(rest, "^shield%s*", "")
        if rest == "move" then IchaUIShamanExtras_ToggleMove("shield")
        elseif rest == "show" then IchaUIShamanExtras_SetHidden("shield", false)
        elseif rest == "hide" then IchaUIShamanExtras_SetHidden("shield", true)
        else DEFAULT_CHAT_FRAME:AddMessage("Shield: /icha shield move|show|hide") end
    elseif string.find(rest, "^utility") or string.find(rest, "^util") then
        rest = string.gsub(rest, "^utility%s*", "")
        rest = string.gsub(rest, "^util%s*", "")
        if rest == "move" then IchaUIShamanExtras_ToggleMove("utility")
        elseif rest == "show" then IchaUIShamanExtras_SetHidden("utility", false)
        elseif rest == "hide" then IchaUIShamanExtras_SetHidden("utility", true)
        else DEFAULT_CHAT_FRAME:AddMessage("Utility: /icha utility move|show|hide") end
    else
        DEFAULT_CHAT_FRAME:AddMessage("Shaman extras: /icha imbue|shield|utility move|show|hide")
    end
end

-- Events + tick
local evt = CreateFrame("Frame", "IchaUIShamanExtrasEvt", UIParent)
evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("PLAYER_ENTERING_WORLD")
evt:RegisterEvent("SPELLS_CHANGED")
evt:RegisterEvent("PLAYER_AURAS_CHANGED")
pcall(function() evt:RegisterEvent("UNIT_INVENTORY_CHANGED") end)
pcall(function() evt:RegisterEvent("UNIT_AURA") end)
pcall(function() evt:RegisterEvent("SPELLCAST_STOP") end)
pcall(function() evt:RegisterEvent("SPELLCAST_FAILED") end)
pcall(function() evt:RegisterEvent("UNIT_SPELLCAST_STOP") end)
pcall(function() evt:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED") end)
pcall(function() evt:RegisterEvent("SPELL_UPDATE_COOLDOWN") end)
pcall(function() evt:RegisterEvent("BAG_UPDATE") end)

local function extrasStandDown()
    if not IchaUI_ShamanStandDown(evt, imbueW.root, shieldW.root, utilityW.root) then return false end
    IchaUI_ShamanStandDown(imbueW.drawer, shieldW.drawer, utilityW.drawer)
    return true
end

evt:SetScript("OnEvent", function()
    if (event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD") and extrasStandDown() then return end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        reagentDirty = true
        ensureKnown()
        restorePos(imbueW)
        restorePos(shieldW)
        restorePos(utilityW)
        applyAll()
    elseif event == "SPELLS_CHANGED" then
        knownScanAt = 0
        spellReagentName = {}
        reagentDirty = true
        ensureKnown()
    elseif event == "BAG_UPDATE" then
        reagentDirty = true
        refreshWidget(utilityW)
    elseif event == "PLAYER_AURAS_CHANGED" or event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED"
        or event == "SPELLCAST_STOP" or event == "SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_SUCCEEDED"
        or event == "SPELL_UPDATE_COOLDOWN" then
        if event == "UNIT_AURA" and arg1 and arg1 ~= "player" then return end
        if event == "UNIT_INVENTORY_CHANGED" and arg1 and arg1 ~= "player" then return end
        if (event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_SUCCEEDED") and arg1 and arg1 ~= "player" then return end
        refreshWidget(imbueW)
        refreshWidget(shieldW)
        refreshWidget(utilityW)
    end
end)

evt:SetScript("OnUpdate", function()
    local now = GetTime and GetTime() or 0
    tickCirclePush(now)
    if not this._acc then this._acc = 0 end
    this._acc = this._acc + (arg1 or 0)
    -- Drawer close
    local id, w
    for id, w in pairs(widgets) do
        if w.closeAt and not w.pinned then
            if now >= w.closeAt then
                if w.drawer and w.drawer:IsShown() then
                    w.drawer:Hide()
                end
                w.closeAt = nil
            end
        end
    end
    -- Shift-to-open while hovering (shared with totem option)
    local id, w
    for id, w in pairs(widgets) do
        if w and w._drawerHover then
            local key = currentKey(w.id)
            if w.slot then
                w.slot._ichaTipSpell = key
            end
            if canHoverOpenDrawer() then
                if w.drawer and not w.drawer:IsShown() then
                    showDrawer(w, false)
                end
            elseif shiftDrawerRequired() and w.drawer and w.drawer:IsShown() and not w.pinned then
                w.drawer:Hide()
            end
        end
    end
    if this._acc < 0.2 then return end
    this._acc = 0
    if imbueW.root:IsShown() then refreshWidget(imbueW) end
    if shieldW.root:IsShown() then refreshWidget(shieldW) end
    if utilityW.root:IsShown() then refreshWidget(utilityW) end
end)

function IchaUIShamanExtras_ReloadFromDB()
    restorePos(imbueW)
    restorePos(shieldW)
    restorePos(utilityW)
    applyAll()
end

extrasStandDown()
