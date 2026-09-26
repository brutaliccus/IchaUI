-- IchaUI unit frames — player (+round portrait) + target + ToT + party/raid, thick HP, thin power, class colors

local AURA_W, AURA_H = 24, 18 -- 4:3 like action bars (40x30); roundmask authored 128x96
local AURA_PAD = 2
local MAX_AURA_SLOTS = 20 -- up to 2 rows
local BASE_W, BASE_H = 220, 48
local GOLD = { 0.78, 0.58, 0.16, 1 }
-- TrackingBorder circles stay on GOLD (texture is already the dark gold).
-- White tooltip edges use the circle's seen gold: 0.75, 0.52, 0.04 (190, 133, 10).
-- Cast fill gold (StatusBar texture takes this cleanly)
local CAST_GOLD = { 0.95, 0.78, 0.22, 1 }
-- Portrait: circular fill + face + gold ring (no alpha mask — Vanilla-safe)
local PORTRAIT_BG = "Interface\\AddOns\\IchaUI\\media\\portrait-circular-bg.tga"
local PORTRAIT_MASK = "Interface\\AddOns\\IchaUI\\media\\portrait-mask.tga"
local PORTRAIT_RING = "Interface\\AddOns\\IchaUI\\media\\PortraitFrame.tga"
local PORTRAIT_RING_BACKUP = "Interface\\AddOns\\IchaUI\\media\\AzeriteGoldRing.tga" -- keep as fallback
local PORTRAIT_DEFAULT_SCALE = 1.22 -- portrait diameter vs frame height (overhang)
local PORTRAIT_DEFAULT_RING = 1.28 -- ring size / portrait size (thin rim needs overhang)
local PORTRAIT_FACE_INSET = 0.04

-- Portrait gold ring: Art PortraitFrame.tga (OneDrive portrait.png). Never MiniMap-TrackingBorder.
-- Backup: AzeriteGoldRing.tga (PORTRAIT_RING_BACKUP). Ring on UIParent (HIGH) so port cannot clip it.
local _portraitRingLogged = nil
-- PortraitFrame only on the portrait ring — never MiniMap-TrackingBorder.
local function applyPortraitRing(ringTex, parent, size)
    if not ringTex or not parent then return end
    local s = tonumber(size) or parent:GetWidth() or 48
    if s < 16 then s = 16 end
    -- RavenCraft/1.12: include .tga; no hyphens in filename. Never TrackingBorder.
    ringTex:SetTexture(PORTRAIT_RING)
    -- If custom ring failed to load, fall back to Azerite
    if ringTex.GetTexture and (not ringTex:GetTexture() or ringTex:GetTexture() == "") then
        ringTex:SetTexture(PORTRAIT_RING_BACKUP)
    end
    -- PortraitFrame is bright yellow. Multiply onto circle gold (~190, 133, 11).
    IchaUI_PaintGoldVertex(ringTex, 0.80, 0.66, 0.15, 1)
    if ringTex.SetBlendMode then
        ringTex:SetBlendMode("BLEND")
    end
    if ringTex.SetTexCoord then
        ringTex:SetTexCoord(0, 1, 0, 1)
    end
    ringTex:ClearAllPoints()
    ringTex:SetWidth(s)
    ringTex:SetHeight(s)
    ringTex:SetPoint("CENTER", parent, "CENTER", 0, 0)
    ringTex:SetAlpha(1)
    ringTex:Show()
    if not _portraitRingLogged and DEFAULT_CHAT_FRAME then
        _portraitRingLogged = true
        local got = "?"
        if ringTex.GetTexture then
            got = tostring(ringTex:GetTexture() or "nil")
        end
        local shown = "hidden"
        if parent.IsShown and parent:IsShown() then shown = "shown" end
        local pw = 0
        if parent.GetWidth then pw = parent:GetWidth() or 0 end
        DEFAULT_CHAT_FRAME:AddMessage(
            "IchaUI portrait ring tex: " .. got
            .. " sz=" .. tostring(s)
            .. " parentW=" .. tostring(pw)
            .. " " .. shown
        )
    end
end

local function db()
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.uf then IchaUIDB.uf = {} end
    local d = IchaUIDB.uf
    if not d.raidDebuffs then d.raidDebuffs = {} end
    if d.predictHeals == nil then d.predictHeals = true end
    if d.auraIconScale == nil then d.auraIconScale = 1.0 end
    if d.tankDrawerEnabled == nil then d.tankDrawerEnabled = true end
    if d.tankDrawerMinimal == nil then d.tankDrawerMinimal = true end
    if d.tankDrawerSide == nil then d.tankDrawerSide = "left" end
    if d.manaTicker == nil then d.manaTicker = true end
    if d.levelFont == nil then d.levelFont = 10 end
    return d
end

local function clamp(n, lo, hi)
    n = tonumber(n) or lo
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function badUnitToken(unit)
    if not unit or unit == "" or unit == "none" then return true end
    if string.sub(unit, 1, 6) == "IchaUI" then return true end
    return false
end

local function classColor(unit)
    if badUnitToken(unit) then return 0.5, 0.5, 0.5 end
    local ok, exists = pcall(UnitExists, unit)
    if not ok or not exists then return 0.5, 0.5, 0.5 end
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then return c.r, c.g, c.b end
    end
    local r = UnitReaction and UnitReaction(unit, "player")
    if r then
        if r >= 5 then return 0.0, 0.8, 0.0 end
        if r == 4 then return 0.9, 0.9, 0.0 end
        return 0.9, 0.15, 0.15
    end
    return 0.0, 0.8, 0.0
end

local function powerColor(unit)
    if badUnitToken(unit) then return 0.2, 0.4, 0.95 end
    local ok, pt = pcall(UnitPowerType, unit)
    if not ok then pt = 0 end
    pt = pt or 0
    if pt == 1 then return 0.9, 0.15, 0.15 end
    if pt == 3 then return 0.95, 0.9, 0.15 end
    if pt == 2 then return 0.9, 0.45, 0.1 end
    return 0.2, 0.4, 0.95
end

-- Mana tick spark (pfUI energytick model):
--   mana spend (cost > 0) → 5s FSR sweep
--   when that finishes → rolling 2s sweeps (+ world latency)
--   mana gains never re-anchor (totems / spirit ticks / pots stay ignored)
local function manaTickLagSec()
    if not GetNetStats then return 0 end
    local _, _, lagHome, lagWorld = GetNetStats()
    local lagMs = tonumber(lagWorld) or tonumber(lagHome) or 0
    if lagMs < 0 then lagMs = 0 end
    if lagMs > 750 then lagMs = 750 end
    return lagMs / 1000
end

local function tripManaFsr(fr)
    if not fr or fr.unit ~= "player" then return end
    local now = GetTime()
    if fr._manaFsrTripAt and (now - fr._manaFsrTripAt) < 0.20 then
        return
    end
    fr._manaFsrTripAt = now
    -- pfUI: this.target = 5 → next OnUpdate sets start/max
    fr._manaTickTarget = 5
end

local function updateManaTicker(fr)
    if not fr or not fr.mpTick or not fr.mpBg then return end
    local spark = fr.mpTick
    -- 1.12 drops a texture that was set at create time with no tex coords
    -- (solid vertex-color quad). Apply the spark file once, then only move it.
    if not fr._manaTickReady then
        spark:SetTexture("Interface\\AddOns\\IchaUI\\media\\ManaTickSpark.tga")
        spark:SetTexCoord(0.015625, 0.984375, 0.015625, 0.984375)
        fr._manaTickReady = true
    end
    if db().manaTicker == false then spark:Hide() return end
    if fr.unit ~= "player" then spark:Hide() return end
    if UnitPowerType and UnitPowerType("player") ~= 0 then spark:Hide() return end
    -- No tick spark at full mana (nothing to regenerate)
    do
        local cur = UnitMana("player") or 0
        local mx = UnitManaMax("player") or 0
        if mx > 0 and cur >= mx then
            spark:Hide()
            return
        end
    end
    if UnitIsDead and UnitIsDead("player") then spark:Hide() return end
    if UnitIsGhost and UnitIsGhost("player") then spark:Hide() return end
    local mpBg = fr.mpBg
    local w = mpBg:GetWidth() or 0
    local h = mpBg:GetHeight() or 8
    if w < 2 then spark:Hide() return end

    local now = GetTime()
    -- Arm a new sweep (FSR)
    if fr._manaTickTarget then
        fr._manaTickStart = now
        fr._manaTickMax = fr._manaTickTarget
        fr._manaTickTarget = nil
    end
    if not fr._manaTickStart then
        fr._manaTickStart = now
        fr._manaTickMax = 2 + manaTickLagSec()
    end

    local elapsed = now - fr._manaTickStart
    local maxT = fr._manaTickMax or (2 + manaTickLagSec())
    if elapsed > maxT then
        -- pfUI: roll into a fresh 2s tick when the current sweep ends
        fr._manaTickStart = now
        fr._manaTickMax = 2 + manaTickLagSec()
        elapsed = 0
        maxT = fr._manaTickMax
    end

    local p = 0
    if maxT > 0 then p = elapsed / maxT end
    if p < 0 then p = 0 end
    if p > 1 then p = 1 end

    if maxT >= 4.5 then
        spark:SetVertexColor(1.0, 0.85, 0.35) -- FSR
    else
        spark:SetVertexColor(0.45, 0.85, 1.0) -- tick
    end
    spark:SetWidth(math.max(16, h * 1.6))
    spark:SetHeight(math.max(14, h * 2.4))
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", mpBg, "LEFT", w * p, 0)
    spark:Show()
end

local function unitName(unit)
    if badUnitToken(unit) then return "" end
    local ok, exists = pcall(UnitExists, unit)
    if not ok or not exists then return "" end
    local nok, name = pcall(UnitName, unit)
    if not nok then return "" end
    return name or ""
end

-- Single-line name: Shagu-style abbreviate (H. Wave), then ".." if still too wide.
-- ShaguTweaks-extras only hooks Blizzard's TargetFrame and does not export
-- its shortener, so IchaUI names (target, tracker, cast bar) run this copy.
-- The live fontstring is width-capped; GetStringWidth then reports that cap
-- and every name looked like it already fit. Measure on an uncapped string.
local function setTruncatedText(fs, text, maxW)
    if not fs then return end
    text = tostring(text or "")
    if text == "" then
        fs:SetText("")
        return
    end
    if type(fs.SetNonSpaceWrap) == "function" then
        pcall(function() fs:SetNonSpaceWrap(0) end)
    end
    maxW = tonumber(maxW)
    local function glyphWidth()
        local size = 12
        if type(fs.GetFont) == "function" then
            local _, sz = fs:GetFont()
            sz = tonumber(sz)
            if sz and sz > 0 then size = sz end
        end
        return size * 0.55
    end
    local function textWidth(s)
        local est = string.len(s) * glyphWidth()
        local parent = UIParent
        if not parent or type(parent.CreateFontString) ~= "function" then
            return est
        end
        if not IchaUI_NameMeasure then
            local mf = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            mf:SetAlpha(0)
            mf:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
            mf:Show()
            IchaUI_NameMeasure = mf
        end
        local mf = IchaUI_NameMeasure
        if type(fs.GetFont) == "function" and type(mf.SetFont) == "function" then
            local font, sz, flags = fs:GetFont()
            sz = tonumber(sz)
            if font and sz and sz > 0 then
                if type(flags) == "string" and flags ~= "" then
                    mf:SetFont(font, sz, flags)
                else
                    mf:SetFont(font, sz)
                end
            end
        end
        mf:SetText(s)
        local w = 0
        if type(mf.GetStringWidth) == "function" then
            w = tonumber(mf:GetStringWidth()) or 0
        end
        if w < 1 then return est end
        return w
    end
    local function put(s)
        if not s or s == "" then
            s = string.sub(text, 1, 1)
            if not s or s == "" then s = "." end
        end
        if fs:GetText() ~= s then
            fs:SetText(s)
        end
    end
    local function fits(s)
        if not maxW or maxW < 4 then return true end
        return textWidth(s) <= maxW + 0.5
    end
    local function abbrevWord(word)
        return string.sub(word, 1, 1) .. ". "
    end
    if fits(text) then
        put(text)
        return
    end
    -- ShaguTweaks: first word only, then every word except the last
    local short = string.gsub(text, "^(%S+) ", abbrevWord)
    if fits(short) then
        put(short)
        return
    end
    short = string.gsub(short, "(%S+) ", abbrevWord)
    if fits(short) then
        put(short)
        return
    end
    local ell = ".."
    local n = string.len(short)
    while n > 1 do
        n = n - 1
        local cut = string.sub(short, 1, n) .. ell
        if cut ~= "" and fits(cut) then
            put(cut)
            return
        end
    end
    put(ell)
end

local tip = CreateFrame("GameTooltip", "IchaUIUFTip", nil, "GameTooltipTemplate")
tip:SetOwner(UIParent, "ANCHOR_NONE")

local function tipName(setFn)
    if type(setFn) ~= "function" then return nil end
    tip:ClearLines()
    local ok = pcall(setFn)
    if not ok then return nil end
    local fs = getglobal("IchaUIUFTipTextLeft1")
    return fs and fs:GetText() or nil
end

local function isTexturePath(s)
    if type(s) ~= "string" then return false end
    if string.find(s, "Interface") then return true end
    if string.find(s, "\\") or string.find(s, "/") then return true end
    if string.find(s, "Icons") or string.find(s, "icons") then return true end
    -- bare icon file names
    local l = string.lower(s)
    if string.find(l, "inv_") or string.find(l, "spell_") or string.find(l, "ability_") then
        return true
    end
    return false
end

local function normalizeAuraTexture(tex)
    if type(tex) == "number" then
        if GetSpellTexture then
            local t = GetSpellTexture(tex)
            if type(t) == "string" and t ~= "" then return t end
        end
        return nil
    end
    if type(tex) ~= "string" or tex == "" then return nil end
    local l = string.lower(tex)
    if not string.find(tex, "Interface") and not string.find(tex, "\\") and not string.find(tex, "/") then
        if string.find(l, "inv_") or string.find(l, "spell_") or string.find(l, "ability_")
            or string.find(l, "icon_") or string.find(l, "trade_") then
            tex = "Interface\\Icons\\" .. tex
        end
    end
    return tex
end

local function isDispelWord(s)
    if type(s) ~= "string" then return false end
    local d = string.lower(s)
    return d == "magic" or d == "curse" or d == "disease" or d == "poison" or d == "none"
end

local function dispelFromSpellId(spellId)
    if not spellId or spellId == 0 then return nil end
    if type(GetSpellRecField) == "function" then
        -- Nampower raises on unknown spell ids; that must not abort the aura pass.
        local d
        pcall(function() d = GetSpellRecField(spellId, "dispel") end)
        if type(d) == "string" and isDispelWord(d) then return d end
        -- Some builds return numeric dispel school ids
        if d == 1 then return "Magic" end
        if d == 2 then return "Curse" end
        if d == 3 then return "Disease" end
        if d == 4 then return "Poison" end
    end
    return nil
end

-- Turtle / SuperWoW / Nampower / optional pfUI libdebuff
-- Returns: name, icon, count, dtype, caster, spellId
local function readDebuff(unit, index, onlyMineOrDispellable)
    if badUnitToken(unit) then return nil end
    -- pfUI own-debuff pass
    if onlyMineOrDispellable == "mine" and pfUI and pfUI.api and pfUI.api.libdebuff
        and pfUI.api.libdebuff.UnitOwnDebuff then
        local tex, stacks, dtype, dur, left, spellId = pfUI.api.libdebuff:UnitOwnDebuff(unit, index)
        tex = normalizeAuraTexture(tex)
        if not tex then return nil end
        local name = tipName(function() tip:SetUnitDebuff(unit, index) end)
        return name, tex, stacks or 1, dtype, "player", spellId
    end

    local showDisp = nil
    if onlyMineOrDispellable == "dispellable" then
        showDisp = 1
    end

    -- Try PLAYER filter (Turtle/ClassicAPI) for mine-only scans
    local a1, a2, a3, a4, a5, a6, a7, a8
    if onlyMineOrDispellable == "mine" then
        a1, a2, a3, a4, a5, a6, a7, a8 = UnitDebuff(unit, index, 1)
        -- some builds use string filter
        if not a1 and type(UnitDebuff) == "function" then
            a1, a2, a3, a4, a5, a6, a7, a8 = UnitDebuff(unit, index, "PLAYER")
        end
    else
        a1, a2, a3, a4, a5, a6, a7, a8 = UnitDebuff(unit, index, showDisp)
    end
    if not a1 then return nil end

    local name, icon, count, dtype, caster, spellId
    if isTexturePath(a1) or (type(a1) == "string" and normalizeAuraTexture(a1)) then
        icon = normalizeAuraTexture(a1)
        count = (type(a2) == "number" and a2) or 1
        if isDispelWord(a3) then
            dtype = a3
            spellId = (type(a4) == "number" and a4) or nil
        elseif type(a3) == "number" then
            -- Could be spellId (SuperWoW sometimes omits dtype) or stacks confusion
            if a3 > 20 then
                spellId = a3
                dtype = dispelFromSpellId(spellId)
            else
                count = a3
                spellId = (type(a4) == "number" and a4) or nil
                if isDispelWord(a4) then dtype = a4 end
            end
        else
            dtype = a3
            spellId = (type(a4) == "number" and a4) or nil
        end
        -- SuperWoW classic: texture, stacks, dtype, spellID
        if type(a4) == "number" and a4 > 20 then
            spellId = a4
        end
        -- caster / "mine" flags often trail the returns
        if a5 == 1 or a5 == true or a5 == "player" then caster = "player" end
        if a6 == 1 or a6 == true or a6 == "player" then caster = "player" end
        if a7 == 1 or a7 == true then caster = "player" end
        if type(a8) == "string" then caster = a8 end
        if type(a7) == "string" and (a7 == "player" or string.find(a7, "player")) then caster = "player" end
        name = tipName(function() tip:SetUnitDebuff(unit, index) end)
    elseif type(a1) == "string" and isTexturePath(a3) then
        name, icon = a1, normalizeAuraTexture(a3)
        count = (type(a4) == "number" and a4) or 1
        if isDispelWord(a5) then dtype = a5 end
        if type(a8) == "string" or type(a8) == "number" then caster = a8 end
        if type(a4) == "number" and a4 > 20 then spellId = a4 end
        if type(a8) == "number" then spellId = a8 end
    else
        icon = normalizeAuraTexture(a1)
        count = (type(a2) == "number" and a2) or 1
        dtype, spellId = a3, a4
        name = tipName(function() tip:SetUnitDebuff(unit, index) end)
    end

    if not dtype and type(spellId) == "number" then
        dtype = dispelFromSpellId(spellId)
    end
    if (not name or name == "") and type(spellId) == "number" and type(SpellInfo) == "function" then
        local ok, n = pcall(SpellInfo, spellId)
        if ok and type(n) == "string" then name = n end
    end
    icon = normalizeAuraTexture(icon)
    if not icon then return nil end
    if unit == "player" and type(GetPlayerBuff) == "function" and type(GetPlayerBuffApplications) == "function" then
        local bid = GetPlayerBuff(index - 1, "HARMFUL")
        if type(bid) == "number" and bid >= 0 then
            count = tonumber(GetPlayerBuffApplications(bid)) or 0
        elseif type(count) == "number" and count == index then
            count = 0
        end
    end
    return name, icon, count or 0, dtype, caster, spellId
end

local function readBuff(unit, index)
    if badUnitToken(unit) then return nil end
    local a1, a2, a3, a4, a5 = UnitBuff(unit, index)
    if not a1 then return nil end
    local name, icon, count, dtype, spellId
    if isTexturePath(a1) or normalizeAuraTexture(a1) then
        icon = normalizeAuraTexture(a1)
        count = (type(a2) == "number" and a2) or 1
        if isDispelWord(a3) then
            dtype = a3
            spellId = type(a4) == "number" and a4 or nil
        elseif type(a3) == "number" then
            spellId = a3
            dtype = dispelFromSpellId(spellId)
        end
        name = tipName(function() tip:SetUnitBuff(unit, index) end)
    elseif type(a1) == "string" and isTexturePath(a3) then
        name, icon = a1, normalizeAuraTexture(a3)
        count = (type(a4) == "number" and a4) or 1
        if isDispelWord(a5) then dtype = a5 end
    else
        icon = normalizeAuraTexture(a1)
        count = (type(a2) == "number" and a2) or 1
        name = tipName(function() tip:SetUnitBuff(unit, index) end)
    end
    if not dtype and type(spellId) == "number" then
        dtype = dispelFromSpellId(spellId)
    end
    icon = normalizeAuraTexture(icon)
    if not icon then return nil end
    -- Player: UnitBuff's extra return is often the slot, not applications.
    -- GetPlayerBuffApplications is the real stack/charge count (0 if it does not stack).
    if unit == "player" and type(GetPlayerBuff) == "function" and type(GetPlayerBuffApplications) == "function" then
        local bid = GetPlayerBuff(index - 1, "HELPFUL")
        if type(bid) == "number" and bid >= 0 then
            count = tonumber(GetPlayerBuffApplications(bid)) or 0
        elseif type(count) == "number" and count == index then
            count = 0
        end
    end
    return name, icon, count or 0, dtype, spellId
end


-- Debuff/buff remaining time: same approach as ShaguPlatesX —
-- SuperWoW UnitDebuff returns spellID; duration comes from IchaUI_DebuffDurations
-- (IchaUI_Plates, localized) or a SpellInfo name lookup. We cache start time when an
-- aura first appears.
local auraTimeCache = {} -- [unitToken .. "::" .. key] = { start=, duration=, spellId= }

local function shaguDebuffDurationDB()
    if type(IchaUI_DebuffDurations) == "table" then
        return IchaUI_DebuffDurations
    end
    -- IchaUI_Plates off: use ShaguPlatesX's table if that addon happens to be loaded.
    local loc = GetLocale and GetLocale() or "enUS"
    if ShaguPlatesX_locale and ShaguPlatesX_locale[loc] and ShaguPlatesX_locale[loc]["debuffs"] then
        return ShaguPlatesX_locale[loc]["debuffs"]
    end
    return nil
end

local function spellNameFromId(spellId)
    if not spellId then return nil end
    if type(SpellInfo) == "function" then
        local ok, name = pcall(SpellInfo, spellId)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellId)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return nil
end

-- Turtle RavenCraft: Flame Shock is 15s, ticks every 3s (5 ticks)
local FLAMESHOCK_DURATION = 15
local FLAMESHOCK_TICK = 3

local function isFlameShockName(name)
    if not name or name == "" then return false end
    local l = string.lower(name)
    return string.find(l, "flame shock", 1, true) and true or false
end

local function lookupDebuffDuration(spellName, spellId)
    if not spellName and spellId then
        spellName = spellNameFromId(spellId)
    end
    if not spellName then return nil end
    -- Turtle override before Shagu (vanilla tables often say 12s)
    if isFlameShockName(spellName) then
        return FLAMESHOCK_DURATION
    end
    local db = shaguDebuffDurationDB()
    if db and db[spellName] then
        local d = db[spellName][0] or db[spellName][1]
        d = tonumber(d)
        if d and d > 0 then return d end
    end
    return nil
end

-- Stable identity so retargeting the same mob keeps timers (not "target" token)
local function unitIdentity(unit)
    -- "none", blank, IchaUI frame names, and character names are not unit ids.
    if badUnitToken(unit) then return nil end
    if string.find(unit, "^0[xX]%x+$") then
        -- SuperWoW GUID token
    elseif unit == "player" or unit == "target" or unit == "pet" or unit == "mouseover"
        or unit == "targettarget" or unit == "targettargettarget"
        or unit == "pettarget" or unit == "playertarget" or unit == "focus" then
        -- standard token
    elseif string.find(unit, "^party[1-4]$") or string.find(unit, "^party[1-4]target$")
        or string.find(unit, "^partypet[1-4]$")
        or string.find(unit, "^raid%d+$") or string.find(unit, "^raid%d+target$")
        or string.find(unit, "^raidpet%d+$")
        or string.find(unit, "^nameplate%d+$") then
        -- group / nameplate token
    else
        return nil
    end
    if UnitGUID and UnitExists and UnitExists(unit) then
        local g = UnitGUID(unit)
        if g and g ~= "" then return "guid:" .. tostring(g) end
    end
    if UnitExists and UnitExists(unit) and UnitName then
        local nm = UnitName(unit)
        if nm and nm ~= "" then
            local lvl = UnitLevel and UnitLevel(unit) or 0
            return "name:" .. string.lower(nm) .. ":" .. tostring(lvl)
        end
    end
    return nil
end

local function auraCacheKey(unit, spellId, texture, name)
    local id = unitIdentity(unit)
    if not id then return nil end
    -- Texture first: SuperWoW spellId / tooltip name flicker every GCD and
    -- used to fork the key so trackAuraTime treated the DoT as brand new.
    if texture then
        local t = string.lower(tostring(texture))
        t = string.gsub(t, "/", "\\")
        return id .. "::t:" .. t
    end
    if name and name ~= "" then return id .. "::n:" .. string.lower(name) end
    if spellId then return id .. "::id:" .. tostring(spellId) end
    return nil
end

local function trackAuraTime(unit, spellId, texture, name, seenSet, stacks)
    local key = auraCacheKey(unit, spellId, texture, name)
    if not key then return nil end
    if seenSet then seenSet[key] = true end
    local now = GetTime and GetTime() or 0
    stacks = tonumber(stacks) or 1
    local e = auraTimeCache[key]
    if not e then
        local dur = lookupDebuffDuration(name, spellId)
        if (not dur or dur <= 0) and name then
            dur = lookupDebuffDuration(name, nil)
        end
        e = { start = now, duration = dur, spellId = spellId, stacks = stacks, name = name }
        auraTimeCache[key] = e
    else
        -- Recast / refresh: stacks went up, or explicit refresh flagged
        if stacks > (e.stacks or 1) then
            e.start = now
            e.applied = now
            local base = lookupDebuffDuration(name or e.name, spellId or e.spellId)
            if base and base > 0 then e.duration = base end
        end
        e.stacks = stacks
        if spellId and not e.spellId then e.spellId = spellId end
        if name and not e.name then e.name = name end
        if not e.duration then
            e.duration = lookupDebuffDuration(name or e.name, spellId or e.spellId)
        end
    end
    if e.duration and e.duration > 0 and e.start then
        local left = e.duration - (now - e.start)
        if left > 0 then return left end
        return 0
    end
    return nil
end

-- Reset start time only on a real apply/refresh of that spell (never a tick/hit).
local function refreshAuraTimersForSpell(spellId, spellName)
    if not spellId and (not spellName or spellName == "") then return end
    local now = GetTime and GetTime() or 0
    local lname = spellName and string.lower(spellName) or nil
    -- Callers decide apply vs tick (UNIT_CASTEVENT CAST gate / SPELLCAST_STOP after
    -- a START); a DoT tick landing just before a real recast must not veto it.
    local prefixes = {}
    -- Scoped to the mob the cast hit when known, so recasting on another mob
    -- does not reset the current target's copy of that DoT.
    if IchaUI_RefreshAuraGuid and IchaUI_RefreshAuraGuid ~= "" then
        table.insert(prefixes, IchaUI_RefreshAuraGuid)
    else
        local tid = unitIdentity("target")
        if tid then table.insert(prefixes, tid .. "::") end
        local oid = unitIdentity("targettarget")
        if oid then table.insert(prefixes, oid .. "::") end
    end
    local function keyInScope(k)
        if table.getn(prefixes) < 1 then return true end
        local pi
        for pi = 1, table.getn(prefixes) do
            local p = prefixes[pi]
            if p and string.sub(k, 1, string.len(p)) == p then return true end
        end
        return false
    end
    local k, e
    for k, e in pairs(auraTimeCache) do
        if keyInScope(k) then
            local match = false
            if spellId and e.spellId and tonumber(e.spellId) == tonumber(spellId) then
                match = true
            elseif lname and e.name and string.lower(e.name) == lname then
                match = true
            end
            if match then
                e.start = now
                e.applied = now
                -- Back to the base duration: Molten Blast may have extended it.
                local base = lookupDebuffDuration(spellName or e.name, spellId or e.spellId)
                if base and base > 0 then e.duration = base end
            end
        end
    end
end

-- Turtle: Molten Blast restores spent Flame Shock ticks without resetting
-- the next-tick clock (keep start; extend duration by completed periods).
local function isMoltenBlastName(name)
    if not name or name == "" then return false end
    local l = string.lower(name)
    return string.find(l, "molten blast", 1, true) and true or false
end

-- scope: "id::" cache prefix of the Molten Blast target (nil = current target).
local function restoreFlameShockTicksFromMoltenBlast(scope)
    local now = GetTime and GetTime() or 0
    local period = FLAMESHOCK_TICK
    if not scope or scope == "" then
        local tid = unitIdentity("target")
        if not tid then return false end
        scope = tid .. "::"
    end
    local k, e
    local any = false
    for k, e in pairs(auraTimeCache) do
        if e and string.sub(k, 1, string.len(scope)) == scope
            and (isFlameShockName(e.name) or string.find(k, "spell_fire_flameshock", 1, true))
            and e.start then
            local elapsed = now - e.start
            if elapsed < 0 then elapsed = 0 end
            -- Always from the full Turtle duration (idempotent: a second MB or a
            -- duplicate CAST/SPELLCAST_STOP cannot stack extensions).
            -- Keep start so the tick phase is preserved.
            local spentTicks = math.floor(elapsed / period)
            local d = FLAMESHOCK_DURATION + (spentTicks * period)
            local expired = e.duration and e.duration > 0 and elapsed >= e.duration
            if (not expired) and e.duration ~= d then
                e.duration = d
                e.applied = now
                any = true
            end
        end
    end
    return any
end

local pendingCastName = nil
local pendingCastId = nil

local function pruneAuraCache(unit, seenSet)
    local id = unitIdentity(unit)
    if not id then return end -- no unit / switched away: keep cache for other GUIDs
    local prefix = id .. "::"
    local k
    for k in pairs(auraTimeCache) do
        if string.sub(k, 1, string.len(prefix)) == prefix then
            if not seenSet or not seenSet[k] then
                auraTimeCache[k] = nil
            end
        end
    end
end

-- Drop expired entries so the cache cannot grow forever across many mobs
local function sweepExpiredAuraCache()
    local now = GetTime and GetTime() or 0
    local k, e
    for k, e in pairs(auraTimeCache) do
        if e and e.start and e.duration and e.duration > 0 then
            if (now - e.start) > (e.duration + 2) then
                auraTimeCache[k] = nil
            end
        elseif e and e.start and (now - e.start) > 600 then
            auraTimeCache[k] = nil
        end
    end
end

-- Prefer cache. Live remaining APIs often return full duration on GCD/tick.
local function peekDebuffTimeLeft(unit, index, spellId, texture, name)
    local live = nil
    if type(UnitDebuffRemainingTime) == "function" then
        local ok, left = pcall(UnitDebuffRemainingTime, unit, index)
        if ok then live = tonumber(left) end
        if live and live <= 0 then live = nil end
    end
    if not live and pfUI and pfUI.api and pfUI.api.libdebuff and pfUI.api.libdebuff.UnitDebuff then
        local tex, stacks, dtype, dur, left = pfUI.api.libdebuff:UnitDebuff(unit, index)
        live = tonumber(left)
        if live and live <= 0 then live = nil end
    end
    -- SuperWoW: refresh spellId from UnitDebuff if missing
    if not spellId then
        local a1, a2, a3, a4 = UnitDebuff(unit, index)
        if type(a4) == "number" and a4 > 20 then spellId = a4 end
        if type(a3) == "number" and a3 > 20 and not isDispelWord(a3) then spellId = a3 end
        if not texture and isTexturePath(a1) then texture = a1 end
    end
    if not name and spellId then name = spellNameFromId(spellId) end
    local stacks = 1
    -- stacks often 2nd UnitDebuff return; re-read cheaply
    local a1, a2 = UnitDebuff(unit, index)
    if type(a2) == "number" and a2 > 0 and a2 < 100 then stacks = a2 end
    local cached = trackAuraTime(unit, spellId, texture, name, nil, stacks)
    if live and cached then
        -- Jump up to "full" is a tick/GCD flicker unless we just applied.
        if live > cached + 0.75 then
            local key = auraCacheKey(unit, spellId, texture, name)
            local e = key and auraTimeCache[key]
            local now = GetTime and GetTime() or 0
            if e and e.start and (now - e.start) < 0.6 then
                return live
            end
            return cached
        end
        return live
    end
    if live then return live end
    return cached
end

local function peekBuffTimeLeft(unit, index, spellId, texture, name)
    if type(UnitBuffRemainingTime) == "function" then
        local ok, left = pcall(UnitBuffRemainingTime, unit, index)
        if ok and tonumber(left) and tonumber(left) > 0 then return tonumber(left) end
    end
    -- Buffs: no Shagu duration DB wired; skip estimate unless live API
    return nil
end

local function raidWatch()
    local t = {}
    local list = db().raidDebuffs or {}
    local i
    for i = 1, table.getn(list) do
        local n = list[i]
        if n and n ~= "" then
            t[string.lower(n)] = true
        end
    end
    return t
end

local function isMineCaster(caster)
    if not caster then return false end
    if caster == "player" then return true end
    if caster == true or caster == 1 then return true end
    if type(caster) == "string" and UnitIsUnit and UnitIsUnit(caster, "player") then
        return true
    end
    return false
end

local function dtypeKey(dtype)
    if not dtype or type(dtype) ~= "string" then return nil end
    return string.lower(dtype)
end

local function formatAuraTime(remain)
    if not remain or remain <= 0 then return "" end
    if remain >= 3600 then
        return string.format("%dh", math.floor(remain / 3600 + 0.5))
    end
    if remain >= 60 then
        return string.format("%dm", math.floor(remain / 60 + 0.5))
    end
    if remain >= 10 then
        return string.format("%d", math.floor(remain + 0.5))
    end
    return string.format("%.1f", remain)
end

local function makeBar(parent, layer)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK")
    tex:SetTexture("Interface/TargetingFrame/UI-StatusBar")
    return tex
end

local function applyGold(border, edge)
    border:SetBackdrop({
        bgFile = nil,
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = edge or 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    border:SetBackdropColor(0, 0, 0, 0)
    IchaUI_PaintGoldBorder(border, GOLD[4])
end

local function applyAuraGold(border, edge, outset)
    if not border then return end
    local e = edge or 10
    local o = outset or 2
    border:ClearAllPoints()
    -- parent is the icon frame; border is child — point to parent
    local parent = border:GetParent()
    border:SetPoint("TOPLEFT", parent, "TOPLEFT", -o, o)
    border:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", o, -o)
    border:SetBackdrop({
        bgFile = nil,
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = e,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    border:SetBackdropColor(0, 0, 0, 0)
    IchaUI_PaintGoldBorder(border, GOLD[4])
end

-- Icon art fills the aura button edge to edge. SetAllPoints after SetTexture
-- so 1.12 does not leave the file centered. No inset: icon size stays 24x18.
-- GLOBAL on purpose: main chunk is at Lua's 200-local limit.
function IchaUI_PinAuraTex(icon)
    if not icon or not icon.tex then return end
    local tex = icon.tex
    local w = icon:GetWidth() or 0
    local h = icon:GetHeight() or 0
    if w < 2 then w = AURA_W end
    if h < 2 then h = AURA_H end
    tex:ClearAllPoints()
    tex:SetAllPoints(icon)
    if icon.roundMask then
        icon.roundMask:ClearAllPoints()
        icon.roundMask:SetAllPoints(tex)
    end
    IchaUI_ApplyAuraAspect(tex, w, h)
end

-- Same icon zoom/crop as action bars (Layout.applyAspect).
-- GLOBAL on purpose: main chunk is at Lua's 200-local limit.
function IchaUI_ApplyAuraAspect(tex, w, h)
    if not tex then return end
    w = tonumber(w) or 0
    h = tonumber(h) or 0
    if w <= 0 then w = AURA_W end
    if h <= 0 then h = AURA_H end
    local pad, span = 0.07, 0.86
    if w == h then
        tex:SetTexCoord(pad, 1 - pad, pad, 1 - pad)
        return
    end
    if w > h then
        local crop = (1 - (h / w)) / 2
        tex:SetTexCoord(pad, 1 - pad, pad + crop * span, 1 - pad - crop * span)
    else
        local crop = (1 - (w / h)) / 2
        tex:SetTexCoord(pad + crop * span, 1 - pad - crop * span, pad, 1 - pad)
    end
end

-- Melee swing timer (player + target only). Globals: main chunk at ~200-local limit.
IchaUI_SWING_SPARK = "Interface\\AddOns\\IchaUI\\media\\TotemCastSpark.tga"

-- Cast bar chrome (globals: chunk local budget)
IchaUI_CAST_BORDER = "Interface\\AddOns\\IchaUI\\media\\UI-CastingBar-Border-Small.tga"
IchaUI_CAST_SPARK = "Interface\\AddOns\\IchaUI\\media\\UI-CastingBar-Spark.tga"
IchaUI_CAST_SHIELD = "Interface\\AddOns\\IchaUI\\media\\UI-CastingBar-Small-FocusShield.tga"
-- StatusBar (not BarFill): BarFill is dark+alpha and muddies gold vertex color
IchaUI_CAST_FILL = "Interface/TargetingFrame/UI-StatusBar"
-- Pixel length. Caps stay 1 texel = 1 pixel; only the straight middle changes.
-- 214 matches a default unit bar (220-wide frame, 3px pad each side).
IchaUI_CAST_NAT = 214
IchaUI_CAST_LEN_MIN = 80
IchaUI_CAST_LEN_MAX = 420
-- Uniform scale of the whole cast bar (same factor on X and Y). 1 = natural size.
IchaUI_CAST_SC_MIN = 0.4
IchaUI_CAST_SC_MAX = 3
IchaUI_CAST_TEX_W = 256
IchaUI_CAST_SLICE_L = 48
IchaUI_CAST_SLICE_R = 48
IchaUI_CAST_ART_X = 28
IchaUI_CAST_ART_W = 200
IchaUI_CAST_ART_H = 22
IchaUI_CAST_IN_L = 6
IchaUI_CAST_IN_R = 6
IchaUI_CAST_IN_Y = 7
IchaUI_CAST_SH_L = 36
IchaUI_CAST_SH_R = 8
-- Shield emblem lives in the left cap so Length does not stretch it.
IchaUI_CAST_SH_SLICE = 72

function IchaUI_ValidCastPos(p)
    if p == "top" then return "top" end
    return "bottom"
end

function IchaUIUF_GetCastSettings(kind)
    if not kind or kind == "" then kind = "player" end
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.uf then IchaUIDB.uf = {} end
    local d = IchaUIDB.uf
    if not d.castByType then d.castByType = {} end
    local s = d.castByType[kind]
    if type(s) ~= "table" then
        s = {}
        d.castByType[kind] = s
        if kind == "focus" and type(d.castByType.target) == "table" then
            local src = d.castByType.target
            s.castPos = src.castPos
            s.castOffsetX = src.castOffsetX
            s.castOffsetY = src.castOffsetY
            s.castLen = src.castLen
            s.castScale = src.castScale
            s.castWidth = src.castWidth
            if src.castEnabled ~= nil then s.castEnabled = src.castEnabled and true or false end
        end
    end
    s.castPos = IchaUI_ValidCastPos(s.castPos)
    s.castOffsetX = clamp(tonumber(s.castOffsetX) or 0, -80, 80)
    s.castOffsetY = clamp(tonumber(s.castOffsetY) or 0, -80, 80)
    if kind == "player" or kind == "target" or kind == "focus" then
        s.castDetached = s.castDetached and true or false
    else
        s.castDetached = false
    end
    -- Old castWidth was a percent of the unit bar (40-180). Map it once to pixels.
    if s.castLen == nil then
        local pct = tonumber(s.castWidth)
        if not pct or pct < 40 or pct > 180 then pct = 100 end
        s.castLen = math.floor((IchaUI_CAST_NAT or 214) * pct / 100 + 0.5)
    end
    s.castLen = clamp(tonumber(s.castLen) or IchaUI_CAST_NAT or 214, IchaUI_CAST_LEN_MIN or 80, IchaUI_CAST_LEN_MAX or 420)
    s.castScale = clamp(tonumber(s.castScale) or 1, IchaUI_CAST_SC_MIN or 0.4, IchaUI_CAST_SC_MAX or 3)
    return s
end

-- nil castEnabled means On, so existing bars stay until the user turns them off.
function IchaUIUF_CastBarOn(kind)
    if not kind or kind == "" or kind == "raid" then return false end
    if string.find(kind, "^raid") then return false end
    local s = IchaUIUF_GetCastSettings(kind)
    if s and s.castEnabled == false then return false end
    return true
end

-- Raid target (star..skull) on portrait, else the unit frame. Per-kind in IchaUIDB.uf.markByType.
IchaUI_MARK_ANCHORS = { "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
IchaUI__markGrabUnit = nil
IchaUI__markGrabIdx = nil

-- host nil or "portrait": stick to the portrait when it is showing (portrait X/Y moves it).
-- host "frame": stick to the unit frame; portrait nudge does not move it.
function IchaUI_IconHost(fr, host)
    local root = fr and fr.root
    local wantPort = true
    if host == "frame" then wantPort = false end
    local port = fr and fr.portraitFrame
    local portOn = wantPort and fr and fr.hasPortrait and (fr.portraitEnabled ~= false) and port
    if portOn and port.IsShown and not port:IsShown() then
        portOn = false
    end
    if portOn then
        local parentF = port
        if fr.portraitRingFrame and fr.portraitRingFrame.IsShown and fr.portraitRingFrame:IsShown() then
            parentF = fr.portraitRingFrame
        end
        return port, parentF, true
    end
    return root, root, false
end

function IchaUI_ValidMarkAnchor(a)
    if a == "CENTER" or a == "TOP" or a == "BOTTOM" or a == "LEFT" or a == "RIGHT"
        or a == "TOPLEFT" or a == "TOPRIGHT" or a == "BOTTOMLEFT" or a == "BOTTOMRIGHT" then
        return a
    end
    return "CENTER"
end

function IchaUIUF_GetMarkSettings(kind)
    if not kind or kind == "" then kind = "player" end
    if IchaUI_LevelStoreKey then kind = IchaUI_LevelStoreKey(kind) end
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.uf then IchaUIDB.uf = {} end
    local d = IchaUIDB.uf
    if not d.markByType then d.markByType = {} end
    local s = d.markByType[kind]
    if type(s) ~= "table" then
        s = {}
        d.markByType[kind] = s
        if kind == "focus" and type(d.markByType.target) == "table" then
            local src = d.markByType.target
            s.markShow = src.markShow
            s.markAnchor = src.markAnchor
            s.markX = src.markX
            s.markY = src.markY
            s.markScale = src.markScale
        end
    end
    if s.markShow == nil then s.markShow = true end
    if s.markShow then s.markShow = true else s.markShow = false end
    s.markAnchor = IchaUI_ValidMarkAnchor(s.markAnchor)
    s.markX = clamp(tonumber(s.markX) or 0, -80, 80)
    s.markY = clamp(tonumber(s.markY) or 0, -80, 80)
    s.markScale = clamp(tonumber(s.markScale) or 1, 0.4, 2.5)
    return s
end

function IchaUIUF_SetMarkSetting(kind, field, value)
    local s = IchaUIUF_GetMarkSettings(kind)
    if field == "markShow" then
        if value then s.markShow = true else s.markShow = false end
    elseif field == "markAnchor" then
        s.markAnchor = IchaUI_ValidMarkAnchor(value)
    elseif field == "markX" or field == "markY" then
        s[field] = clamp(tonumber(value) or 0, -80, 80)
    elseif field == "markScale" then
        s.markScale = clamp(tonumber(value) or 1, 0.4, 2.5)
    elseif field == "host" then
        if value == "frame" then s.host = "frame" else s.host = "portrait" end
    else
        return
    end
    local store = kind
    if IchaUI_LevelStoreKey then store = IchaUI_LevelStoreKey(kind) end
    if IchaUIUF_refreshTextKind then
        IchaUIUF_refreshTextKind(store)
    end
end

function IchaUIUF_CycleMarkAnchor(kind, pick)
    local s = IchaUIUF_GetMarkSettings(kind)
    local cur = s.markAnchor or "CENTER"
    local list = IchaUI_MARK_ANCHORS
    local idx = 1
    local i
    for i = 1, table.getn(list) do
        if list[i] == cur then
            idx = i
            break
        end
    end
    idx = idx + 1
    if idx > table.getn(list) then idx = 1 end
    if pick and list[pick] then idx = pick end
    IchaUIUF_SetMarkSetting(kind, "markAnchor", list[idx])
    return list[idx]
end

function IchaUI__markGrab()
    IchaUI__markGrabIdx = GetRaidTargetIndex(IchaUI__markGrabUnit)
end

function IchaUI_SafeRaidTargetIndex(unit)
    if not unit or unit == "" or unit == "none" then return nil end
    if string.sub(tostring(unit), 1, 6) == "IchaUI" then return nil end
    if type(GetRaidTargetIndex) ~= "function" then return nil end
    IchaUI__markGrabUnit = unit
    IchaUI__markGrabIdx = nil
    local ok = pcall(IchaUI__markGrab)
    if not ok then return nil end
    local idx = tonumber(IchaUI__markGrabIdx)
    IchaUI__markGrabUnit = nil
    IchaUI__markGrabIdx = nil
    if not idx or idx < 1 then return nil end
    if idx > 8 then idx = 8 end
    return idx
end

function IchaUI_ApplyRaidMarkTexCoord(tex, index)
    if not tex or not tex.SetTexCoord then return end
    index = tonumber(index) or 1
    if index < 1 then index = 1 end
    if index > 8 then index = 8 end
    local i = index - 1
    local col = math.mod(i, 4)
    local row = math.floor(i / 4)
    local left = col * 0.25
    local top = row * 0.25
    tex:SetTexCoord(left, left + 0.25, top, top + 0.25)
end

function IchaUI_HideUnitRaidMark(fr)
    if not fr then return end
    if fr.raidMark then fr.raidMark:Hide() end
    if fr.raidMarkTex then fr.raidMarkTex:Hide() end
end

function IchaUI_UpdateUnitRaidMark(fr)
    if not fr or not fr.raidMark then return end
    local mark = fr.raidMark
    local tex = fr.raidMarkTex
    local testing = IchaUIUF_GetTestMode and IchaUIUF_GetTestMode()
    if fr.hidden and not testing then
        IchaUI_HideUnitRaidMark(fr)
        return
    end
    local kind = fr.key or "player"
    if IchaUI_LevelStoreKey then kind = IchaUI_LevelStoreKey(fr.key) end
    local s = IchaUIUF_GetMarkSettings(kind)
    if not s or s.markShow == false then
        IchaUI_HideUnitRaidMark(fr)
        return
    end
    local unit = fr.unit
    local idx = nil
    if unit and unit ~= "" and unit ~= "none" then
        if string.sub(tostring(unit), 1, 6) ~= "IchaUI" then
            idx = IchaUI_SafeRaidTargetIndex(unit)
        end
    end
    if not idx then
        if testing or fr._forcePreview then
            idx = 8
        else
            IchaUI_HideUnitRaidMark(fr)
            return
        end
    end
    local root = fr.root
    if not root then
        IchaUI_HideUnitRaidMark(fr)
        return
    end
    if root.IsShown and not root:IsShown() then
        IchaUI_HideUnitRaidMark(fr)
        return
    end
    local rel, parentF, portOn = root, root, false
    if IchaUI_IconHost then
        rel, parentF, portOn = IchaUI_IconHost(fr, s.host)
    end
    if not rel then
        IchaUI_HideUnitRaidMark(fr)
        return
    end
    mark:SetParent(parentF or rel)
    local hw = rel:GetWidth() or 40
    local hh = rel:GetHeight() or 24
    if hw < 8 then hw = 40 end
    if hh < 8 then hh = 24 end
    local base = hh * 0.55
    if portOn then base = hw * 0.42 end
    local sz = math.floor(base * (tonumber(s.markScale) or 1) + 0.5)
    if sz < 8 then sz = 8 end
    if sz > 72 then sz = 72 end
    mark:SetWidth(sz)
    mark:SetHeight(sz)
    mark:ClearAllPoints()
    mark:SetPoint("CENTER", rel, IchaUI_ValidMarkAnchor(s.markAnchor), tonumber(s.markX) or 0, tonumber(s.markY) or 0)
    if portOn then
        mark:SetFrameStrata((parentF.GetFrameStrata and parentF:GetFrameStrata()) or "MEDIUM")
        mark:SetFrameLevel((parentF:GetFrameLevel() or 1) + 8)
    else
        mark:SetFrameStrata(root:GetFrameStrata() or "MEDIUM")
        mark:SetFrameLevel((root:GetFrameLevel() or 1) + 25)
    end
    if tex then
        tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        IchaUI_ApplyRaidMarkTexCoord(tex, idx)
        tex:ClearAllPoints()
        tex:SetAllPoints(mark)
        tex:Show()
    end
    mark:EnableMouse(false)
    mark:Show()
end

function IchaUIUF_RefreshRaidMarks()
    local map = IchaUI_Swing_Frames
    if not map then return end
    local _, fr
    for _, fr in pairs(map) do
        if fr then IchaUI_UpdateUnitRaidMark(fr) end
    end
end

-- Leader crown + master looter. Same per-kind anchor/nudge save as raid marks.
-- 1.12: UnitIsPartyLeader is the party leader; the raid leader uses that same flag.
-- Rank 2 from GetRaidRosterInfo is the raid leader if a raid token misses the unit API.
-- Never pass "none", IchaUI* frame names, or character names into unit APIs.

function IchaUI_RoleUnitOk(unit)
    if not unit or unit == "" or unit == "none" then return false end
    unit = tostring(unit)
    if string.sub(unit, 1, 6) == "IchaUI" then return false end
    if unit == "player" or unit == "target" or unit == "pet" or unit == "mouseover" then return true end
    if unit == "targettarget" or unit == "targettargettarget" then return true end
    if string.find(unit, "^party[1-4]$") then return true end
    if string.find(unit, "^partypet[1-4]$") then return true end
    if string.find(unit, "^raid%d+$") then return true end
    if string.find(unit, "^raidpet%d+$") then return true end
    if string.find(unit, "^nameplate%d+$") then return true end
    if string.find(unit, "^0[xX]%x+$") then return true end
    return false
end

function IchaUI_InPartyOrRaid()
    if type(GetNumRaidMembers) == "function" then
        local ok, v = pcall(GetNumRaidMembers)
        if ok and tonumber(v) and tonumber(v) > 0 then return true, true end
    end
    if type(GetNumPartyMembers) == "function" then
        local ok, v = pcall(GetNumPartyMembers)
        if ok and tonumber(v) and tonumber(v) > 0 then return true, false end
    end
    return false, false
end

function IchaUI_UnitIsLeader(unit)
    if not IchaUI_RoleUnitOk(unit) then return false end
    local grouped, inRaid = IchaUI_InPartyOrRaid()
    if not grouped then return false end
    if type(UnitIsPartyLeader) == "function" then
        local ok, lead = pcall(UnitIsPartyLeader, unit)
        if ok and lead then return true end
    end
    if not inRaid then return false end
    local _, _, n = string.find(tostring(unit), "^raid(%d+)$")
    n = tonumber(n)
    if not n or n < 1 or n > 40 then return false end
    if type(GetRaidRosterInfo) ~= "function" then return false end
    local rank
    local function grabRank()
        local _, r = GetRaidRosterInfo(n)
        rank = r
    end
    local okR = pcall(grabRank)
    if not okR then return false end
    if tonumber(rank) == 2 then return true end
    return false
end

function IchaUI_UnitIsMasterLooter(unit)
    if not IchaUI_RoleUnitOk(unit) then return false end
    if type(GetLootMethod) ~= "function" or type(UnitIsUnit) ~= "function" then return false end
    local method, pidx, ridx
    local function grabLoot()
        method, pidx, ridx = GetLootMethod()
    end
    local ok = pcall(grabLoot)
    if not ok then return false end
    if method ~= "master" then return false end
    local _, inRaid = IchaUI_InPartyOrRaid()
    ridx = tonumber(ridx)
    pidx = tonumber(pidx)
    local token = nil
    if inRaid and ridx and ridx >= 1 and ridx <= 40 then
        token = "raid" .. ridx
    elseif pidx == 0 then
        token = "player"
    elseif pidx and pidx >= 1 and pidx <= 4 then
        token = "party" .. pidx
    elseif ridx and ridx >= 1 and ridx <= 40 then
        token = "raid" .. ridx
    end
    if not token or not IchaUI_RoleUnitOk(token) then return false end
    local okU, same = pcall(UnitIsUnit, unit, token)
    if okU and same then return true end
    return false
end

function IchaUIUF_GetRoleIconSettings(kind, which)
    if which ~= "loot" then which = "leader" end
    if not kind or kind == "" then kind = "player" end
    if IchaUI_LevelStoreKey then kind = IchaUI_LevelStoreKey(kind) end
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.uf then IchaUIDB.uf = {} end
    local d = IchaUIDB.uf
    local bag = "leaderByType"
    local defAnc = "TOPLEFT"
    if which == "loot" then
        bag = "lootByType"
        defAnc = "TOPRIGHT"
    end
    if not d[bag] then d[bag] = {} end
    local s = d[bag][kind]
    if type(s) ~= "table" then
        s = {}
        d[bag][kind] = s
        if kind == "focus" and type(d[bag].target) == "table" then
            local src = d[bag].target
            s.anchor = src.anchor
            s.x = src.x
            s.y = src.y
            s.scale = src.scale
            s.show = src.show
        end
    end
    if s.anchor == nil or s.anchor == "" then s.anchor = defAnc end
    s.anchor = IchaUI_ValidMarkAnchor(s.anchor)
    s.x = clamp(tonumber(s.x) or 0, -80, 80)
    s.y = clamp(tonumber(s.y) or 0, -80, 80)
    s.scale = clamp(tonumber(s.scale) or 1, 0.4, 2.5)
    if s.show == nil then s.show = true end
    if s.show then s.show = true else s.show = false end
    return s
end

function IchaUIUF_SetRoleIconSetting(kind, which, field, value)
    if which ~= "loot" then which = "leader" end
    local s = IchaUIUF_GetRoleIconSettings(kind, which)
    if field == "anchor" then
        s.anchor = IchaUI_ValidMarkAnchor(value)
    elseif field == "x" or field == "y" then
        s[field] = clamp(tonumber(value) or 0, -80, 80)
    elseif field == "scale" then
        s.scale = clamp(tonumber(value) or 1, 0.4, 2.5)
    elseif field == "show" then
        if value then s.show = true else s.show = false end
    elseif field == "host" then
        if value == "frame" then s.host = "frame" else s.host = "portrait" end
    else
        return
    end
    local store = kind
    if IchaUI_LevelStoreKey then store = IchaUI_LevelStoreKey(kind) end
    if IchaUIUF_refreshTextKind then
        IchaUIUF_refreshTextKind(store)
    end
end

function IchaUIUF_CycleRoleAnchor(kind, which, pick)
    local s = IchaUIUF_GetRoleIconSettings(kind, which)
    local cur = s.anchor or "TOPLEFT"
    local list = IchaUI_MARK_ANCHORS
    local idx = 1
    local i
    for i = 1, table.getn(list) do
        if list[i] == cur then
            idx = i
            break
        end
    end
    idx = idx + 1
    if idx > table.getn(list) then idx = 1 end
    if pick and list[pick] then idx = pick end
    IchaUIUF_SetRoleIconSetting(kind, which, "anchor", list[idx])
    return list[idx]
end

function IchaUI_HideUnitRoleIcons(fr)
    if not fr then return end
    if fr.leaderIcon then fr.leaderIcon:Hide() end
    if fr.leaderIconTex then fr.leaderIconTex:Hide() end
    if fr.lootIcon then fr.lootIcon:Hide() end
    if fr.lootIconTex then fr.lootIconTex:Hide() end
end

function IchaUI_AttachRoleIcons(fr, key, root)
    if not fr or not root or not key then return end
    local lead = CreateFrame("Frame", "IchaUIUF_" .. key .. "_Leader", root)
    lead:EnableMouse(false)
    lead:Hide()
    local ltex = lead:CreateTexture(nil, "OVERLAY")
    ltex:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    ltex:SetAllPoints(lead)
    IchaUI_PaintGoldVertex(ltex, 0.80, 0.66, 1, 1)
    ltex:Hide()
    fr.leaderIcon = lead
    fr.leaderIconTex = ltex
    local loot = CreateFrame("Frame", "IchaUIUF_" .. key .. "_Loot", root)
    loot:EnableMouse(false)
    loot:Hide()
    local otex = loot:CreateTexture(nil, "OVERLAY")
    otex:SetTexture("Interface\\GroupFrame\\UI-Group-MasterLooter")
    otex:SetAllPoints(loot)
    IchaUI_PaintGoldVertex(otex, 0.80, 0.66, 1, 1)
    otex:Hide()
    fr.lootIcon = loot
    fr.lootIconTex = otex
end

-- Leader/loot "Combat hide" + "Hover only" state. combat = PLAYER_REGEN_* verdict
-- (nil = ask the API); settle = poll ticks left of full re-applies after login/roster.
IchaUIUF_RoleFade = { acc = 0, combat = nil, combatAt = 0, lastCombat = nil, settle = 0 }

function IchaUIUF_ApiInCombat()
    if type(UnitAffectingCombat) ~= "function" then return false end
    local ok, combat = pcall(UnitAffectingCombat, "player")
    if ok and combat then return true end
    return false
end

function IchaUI_PlayerInCombat()
    -- UnitAffectingCombat can lag PLAYER_REGEN_*; the event wins until the API agrees.
    local rf = IchaUIUF_RoleFade
    if rf and rf.combat ~= nil then return rf.combat end
    return IchaUIUF_ApiInCombat()
end

function IchaUIUF_SetRoleCombat(inCombat)
    local rf = IchaUIUF_RoleFade
    rf.combat = inCombat and true or false
    rf.combatAt = GetTime and GetTime() or 0
end

function IchaUI_RoleHoverLive(fr)
    if not fr or type(MouseIsOver) ~= "function" then return false end
    local port = fr.portraitFrame
    if port and port.IsVisible and port:IsVisible() then
        local ok, hit = pcall(MouseIsOver, port)
        if ok and hit then return true end
    end
    local root = fr.root
    if root and root.IsVisible and root:IsVisible() then
        local ok, hit = pcall(MouseIsOver, root)
        if ok and hit then return true end
    end
    return false
end

-- OnEnter/OnLeave alone miss exits (child frames, frames hidden under the cursor,
-- edge rounding), so hover and combat are re-derived here ~10x/s.
function IchaUIUF_PollRoleFades(elapsed)
    local rf = IchaUIUF_RoleFade
    rf.acc = rf.acc + (tonumber(elapsed) or 0)
    if rf.acc < 0.1 then return end
    rf.acc = 0
    if rf.combat ~= nil then
        local now = GetTime and GetTime() or 0
        if IchaUIUF_ApiInCombat() == rf.combat or now - (rf.combatAt or 0) > 3 then
            rf.combat = nil
        end
    end
    local combat = IchaUI_PlayerInCombat()
    local combatChanged = (combat ~= rf.lastCombat)
    rf.lastCombat = combat
    if rf.settle > 0 then
        rf.settle = rf.settle - 1
        if math.mod(rf.settle, 5) == 0 then
            IchaUIUF_RefreshRoleIcons()
            return
        end
    end
    local map = IchaUI_Swing_Frames
    if not map then return end
    local _, fr
    for _, fr in pairs(map) do
        if fr and (fr.leaderIcon or fr.lootIcon) then
            local gate = IchaUIUF_GetRoleGate(fr.key or "player")
            local dirty = combatChanged and gate.hideCombat
            if gate.hoverOnly then
                local over = IchaUI_RoleHoverLive(fr)
                if over ~= (fr._roleHover and true or false) then
                    fr._roleHover = over
                    dirty = true
                end
            end
            if dirty then IchaUI_UpdateUnitRoleIcons(fr) end
        end
    end
end

function IchaUIUF_GetRoleGate(kind)
    if not kind or kind == "" then kind = "player" end
    if IchaUI_LevelStoreKey then kind = IchaUI_LevelStoreKey(kind) end
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.uf then IchaUIDB.uf = {} end
    local d = IchaUIDB.uf
    if not d.roleGateByType then d.roleGateByType = {} end
    local s = d.roleGateByType[kind]
    if type(s) ~= "table" then
        s = {}
        d.roleGateByType[kind] = s
        if kind == "focus" and type(d.roleGateByType.target) == "table" then
            s.hideCombat = d.roleGateByType.target.hideCombat
            s.hoverOnly = d.roleGateByType.target.hoverOnly
        end
    end
    if s.hideCombat then s.hideCombat = true else s.hideCombat = false end
    if s.hoverOnly then s.hoverOnly = true else s.hoverOnly = false end
    return s
end

function IchaUIUF_SetRoleGate(kind, field, value)
    local s = IchaUIUF_GetRoleGate(kind)
    if field ~= "hideCombat" and field ~= "hoverOnly" then return end
    if value then s[field] = true else s[field] = false end
    local store = kind
    if IchaUI_LevelStoreKey then store = IchaUI_LevelStoreKey(kind) end
    if IchaUIUF_refreshTextKind then
        IchaUIUF_refreshTextKind(store)
    end
end

function IchaUI_RoleHoverEnd(fr)
    if not fr then return end
    if IchaUI_RoleHoverLive(fr) then fr._roleHover = true else fr._roleHover = false end
    if IchaUI_UpdateUnitRoleIcons then IchaUI_UpdateUnitRoleIcons(fr) end
end

function IchaUI_UpdateUnitRoleIcons(fr)
    if not fr or (not fr.leaderIcon and not fr.lootIcon) then return end
    local testing = IchaUIUF_GetTestMode and IchaUIUF_GetTestMode()
    if fr.hidden and not testing then
        IchaUI_HideUnitRoleIcons(fr)
        return
    end
    local root = fr.root
    if not root or (root.IsShown and not root:IsShown()) then
        IchaUI_HideUnitRoleIcons(fr)
        return
    end
    local unit = fr.unit
    local showLead = false
    local showLoot = false
    if unit and IchaUI_RoleUnitOk(unit) and type(UnitExists) == "function" then
        local okE, ex = pcall(UnitExists, unit)
        if okE and ex then
            showLead = IchaUI_UnitIsLeader(unit)
            showLoot = IchaUI_UnitIsMasterLooter(unit)
        end
    end
    local kind = fr.key or "player"
    if IchaUI_LevelStoreKey then kind = IchaUI_LevelStoreKey(fr.key) end
    local leadS = IchaUIUF_GetRoleIconSettings(kind, "leader")
    local lootS = IchaUIUF_GetRoleIconSettings(kind, "loot")
    if leadS.show == false then showLead = false end
    if lootS.show == false then showLoot = false end
    local gate = IchaUIUF_GetRoleGate(kind)
    if gate.hideCombat and IchaUI_PlayerInCombat() then
        showLead = false
        showLoot = false
    end
    if gate.hoverOnly and not fr._roleHover then
        showLead = false
        showLoot = false
    end
    local function seat(icon, tex, on, anc, ox, oy, path, scale, host)
        if not icon then return end
        if not on then
            icon:Hide()
            if tex then tex:Hide() end
            return
        end
        local rel, parentF, portOn = root, root, false
        if IchaUI_IconHost then
            rel, parentF, portOn = IchaUI_IconHost(fr, host)
        end
        if not rel then
            icon:Hide()
            return
        end
        local hw = rel:GetWidth() or 40
        local hh = rel:GetHeight() or 24
        if hw < 8 then hw = 40 end
        if hh < 8 then hh = 24 end
        local sz = math.floor(hh * 0.42 + 0.5)
        if portOn then sz = math.floor(hw * 0.30 + 0.5) end
        if sz < 10 then sz = 10 end
        if sz > 22 then sz = 22 end
        local iconSz = math.floor(sz * (tonumber(scale) or 1) + 0.5)
        if iconSz < 6 then iconSz = 6 end
        if iconSz > 64 then iconSz = 64 end
        icon:SetParent(parentF or rel)
        icon:SetWidth(iconSz)
        icon:SetHeight(iconSz)
        icon:ClearAllPoints()
        -- Own X/Y sits on top of the portrait offset when rel is the portrait frame.
        icon:SetPoint("CENTER", rel, IchaUI_ValidMarkAnchor(anc), tonumber(ox) or 0, tonumber(oy) or 0)
        if portOn then
            icon:SetFrameStrata((parentF.GetFrameStrata and parentF:GetFrameStrata()) or "MEDIUM")
            icon:SetFrameLevel((parentF:GetFrameLevel() or 1) + 9)
        else
            icon:SetFrameStrata(root:GetFrameStrata() or "MEDIUM")
            icon:SetFrameLevel((root:GetFrameLevel() or 1) + 26)
        end
        if tex then
            tex:SetTexture(path)
            tex:ClearAllPoints()
            tex:SetAllPoints(icon)
            -- Crown and coin are already gold. Multiply onto circle gold (~190, 133, 11).
            IchaUI_PaintGoldVertex(tex, 0.80, 0.66, 1, 1)
            tex:Show()
        end
        icon:EnableMouse(false)
        icon:Show()
    end
    seat(fr.leaderIcon, fr.leaderIconTex, showLead, leadS.anchor, leadS.x, leadS.y, "Interface\\GroupFrame\\UI-Group-LeaderIcon", leadS.scale, leadS.host)
    seat(fr.lootIcon, fr.lootIconTex, showLoot, lootS.anchor, lootS.x, lootS.y, "Interface\\GroupFrame\\UI-Group-MasterLooter", lootS.scale, lootS.host)
end

function IchaUIUF_RefreshRoleIcons()
    local map = IchaUI_Swing_Frames
    if not map then return end
    local _, fr
    for _, fr in pairs(map) do
        if fr then IchaUI_UpdateUnitRoleIcons(fr) end
    end
end

function IchaUI_FitSpellName(fs, name, maxW)
    if not fs then return end
    name = tostring(name or "")
    name = string.gsub(name, "%s*%([Rr]ank%s+%d+%)", "")
    name = string.gsub(name, "%s+[Rr]ank%s+%d+$", "")
    setTruncatedText(fs, name, maxW)
end

function IchaUI_Cast_LayoutIcon(fr, iconSz, locked)
    if not fr or not fr.castIconHolder then return end
    local sz = tonumber(iconSz) or 16
    if sz < 10 then sz = 10 end
    local hold = fr.castIconHolder
    hold:SetWidth(sz)
    hold:SetHeight(sz)
    if locked then
        -- Spell icon sits in the shield hole. No round ring.
        if fr.castIconRing then fr.castIconRing:Hide() end
        if fr.castIconBg then fr.castIconBg:Hide() end
        if fr.castIcon then
            fr.castIcon:ClearAllPoints()
            fr.castIcon:SetWidth(sz)
            fr.castIcon:SetHeight(sz)
            fr.castIcon:SetPoint("CENTER", hold, "CENTER", 0, 0)
            fr.castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        return
    end
    if fr.castIconBg then
        fr.castIconBg:ClearAllPoints()
        fr.castIconBg:SetAllPoints(hold)
        fr.castIconBg:Show()
    end
    if fr.castIcon then
        local inset = math.floor(sz * (1 - 2 * 0.22) + 0.5)
        if inset < 8 then inset = 8 end
        fr.castIcon:ClearAllPoints()
        fr.castIcon:SetWidth(inset)
        fr.castIcon:SetHeight(inset)
        fr.castIcon:SetPoint("CENTER", hold, "CENTER", 0, 2)
        fr.castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    if fr.castIconRing then
        local bw = math.floor(sz * 1.65 + 0.5)
        fr.castIconRing:ClearAllPoints()
        fr.castIconRing:SetWidth(bw)
        fr.castIconRing:SetHeight(bw)
        fr.castIconRing:SetPoint("TOPLEFT", hold, "TOPLEFT", 0, 0)
        IchaUI_PaintGoldRing(fr.castIconRing)
        fr.castIconRing:Show()
    end
end

function IchaUI_Cast_PlaceSpark(fr, fillW)
    if not fr or not fr.castSpark or not fr.castFill then return end
    local sp = fr.castSpark
    if fr._castLocked then
        sp:Hide()
        return
    end
    local w = tonumber(fillW) or 0
    if w < 1 then
        sp:Hide()
        return
    end
    sp:ClearAllPoints()
    sp:SetPoint("CENTER", fr.castFill, "RIGHT", 0, 0)
    sp:Show()
end

function IchaUI_Cast_ClearPin(fr)
    if not fr then return end
    fr._castPinKey = nil
    fr._castPinStart = nil
    fr._castPinDur = nil
    fr._castHoldPct = nil
    fr._castHoldKey = nil
end

-- After UNIT_CASTEVENT CAST / SPELLCAST_STOP: ignore leftover ClassicAPI times
-- (same start) so the bar cannot bounce backward. Globals: chunk local budget.
function IchaUI_Cast_MarkDone(key, spellID, startMs)
    if not key then return end
    if not IchaUI_Cast_Done then IchaUI_Cast_Done = {} end
    local now = 0
    if GetTime then now = GetTime() end
    IchaUI_Cast_Done[tostring(key)] = {
        spellId = spellID,
        start = tonumber(startMs) or 0,
        untilSec = now + 1.25,
        marked = now,
    }
end

function IchaUI_Cast_IsStale(key, spellID, startMs)
    if not IchaUI_Cast_Done or not key then return false end
    local d = IchaUI_Cast_Done[tostring(key)]
    if not d then return false end
    local now = 0
    if GetTime then now = GetTime() end
    if now > (d.untilSec or 0) then
        IchaUI_Cast_Done[tostring(key)] = nil
        return false
    end
    -- Leftover CastingInfo after SUCCESS has an old start. A real recast
    -- started in the last 0.25s. Do not compare start stamps (they drift).
    startMs = tonumber(startMs) or 0
    if startMs > 0 then
        local age = (now * 1000) - startMs
        if age >= 0 and age < 250 then return false end
    end
    if spellID and d.spellId and tonumber(spellID) ~= tonumber(d.spellId) then
        if startMs > 0 then
            local age2 = (now * 1000) - startMs
            if age2 >= 0 and age2 < 250 then return false end
        end
    end
    return true
end

function IchaUI_Cast_LateStart(key, spellID)
    if not IchaUI_Cast_Done or not key then return false end
    local d = IchaUI_Cast_Done[tostring(key)]
    if not d then return false end
    local now = 0
    if GetTime then now = GetTime() end
    if now > (d.untilSec or 0) then
        IchaUI_Cast_Done[tostring(key)] = nil
        return false
    end
    if spellID and d.spellId and tonumber(spellID) ~= tonumber(d.spellId) then
        return false
    end
    return (now - (d.marked or 0)) < 0.35
end

function IchaUI_Cast_FilterInfo(unit, info)
    if not info then return nil end
    local st = tonumber(info.start) or 0
    local sid = info.spellId
    if IchaUI_Swing_Guid then
        local g = IchaUI_Swing_Guid(unit)
        if g and IchaUI_Cast_IsStale(g, sid, st) then return nil end
    end
    if unit == "player" and IchaUI_Cast_IsStale("player", sid, st) then return nil end
    return info
end

-- Vanilla pushback: jump the fill back by a fixed delay, keep original fill rate.
-- ClassicAPI keeps startMs and extends endMs (delayMs); do not use stretched duration.
function IchaUI_Cast_Progress(fr, info, nowMs)
    if not info then return 0, 0 end
    local start = tonumber(info.start) or 0
    local finish = tonumber(info.finish) or 0
    nowMs = tonumber(nowMs) or 0
    if finish <= start then return 0, 0 end
    local raw = finish - start
    local delay = tonumber(info.delay) or 0
    if delay < 0 then delay = 0 end
    if delay > 0 and delay < 50 then delay = delay * 1000 end

    local pinKey = tostring(info.spellId or "") .. "\t" .. tostring(info.name or "")
    if info.channel then pinKey = "c:" .. pinKey end

    local orig = raw
    if delay > 0 and raw > delay + 50 then
        orig = raw - delay
        if fr then
            fr._castPinKey = pinKey
            fr._castPinStart = start
            fr._castPinDur = orig
        end
    elseif fr then
        local same = fr._castPinKey == pinKey
        if same then
            local ds = start - (tonumber(fr._castPinStart) or start)
            if ds < 0 then ds = -ds end
            if ds > 2500 then same = false end
        end
        if not same then
            fr._castPinKey = pinKey
            fr._castPinStart = start
            fr._castPinDur = raw
            orig = raw
        else
            orig = tonumber(fr._castPinDur) or raw
            if orig < 50 then orig = raw end
            -- Infer pushback only before the safe (latency) zone. A later
            -- end time after SUCCESS / near full is leftover, not delay.
            if delay <= 0 and raw > orig + 20 then
                local elapsed0 = nowMs - start
                local lag = 0
                if fr then lag = tonumber(fr._castDispLag) or 0 end
                if elapsed0 < orig - lag - 50 then
                    delay = raw - orig
                end
            end
        end
    end
    if orig < 50 then orig = raw end

    local pct = 0
    if orig > 0 then
        if info.channel then
            pct = (finish - nowMs) / orig
        else
            local elapsed = nowMs - start - delay
            if elapsed < 0 then elapsed = 0 end
            if elapsed > orig then elapsed = orig end
            pct = elapsed / orig
        end
    end
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end
    return pct, orig
end

-- Left/right end caps. The original border texture is the stretchable middle.
function IchaUI_Cast_EnsureCaps(fr)
    if not fr or fr.castArtL or not fr.castFrame then return end
    local p = fr.castFrame
    local left = p:CreateTexture(nil, "OVERLAY")
    local right = p:CreateTexture(nil, "OVERLAY")
    IchaUI_PaintGoldVertex(left, 0.96, 0.70, 0.06, 1)
    IchaUI_PaintGoldVertex(right, 0.96, 0.70, 0.06, 1)
    left:Hide()
    right:Hide()
    fr.castArtL = left
    fr.castArtR = right
end

function IchaUI_Cast_TintArt(fr)
    if not fr then return end
    if fr.castArtL then IchaUI_PaintGoldVertex(fr.castArtL, 0.96, 0.70, 0.06, 1) end
    if fr.castBorder then IchaUI_PaintGoldVertex(fr.castBorder, 0.96, 0.70, 0.06, 1) end
    if fr.castArtR then IchaUI_PaintGoldVertex(fr.castArtR, 0.96, 0.70, 0.06, 1) end
end

function IchaUI_Cast_ShowArt(fr)
    if not fr then return end
    IchaUI_Cast_EnsureCaps(fr)
    IchaUI_Cast_TintArt(fr)
    if fr.castArtL then fr.castArtL:Show() end
    if fr.castBorder then fr.castBorder:Show() end
    if fr.castArtR then fr.castArtR:Show() end
end

-- 256x64 chrome at natural height. Length only clips or stretches the middle.
-- Y tex coords stay 0..1 so the caps are never squashed.
function IchaUI_Cast_LayoutArt(fr, length, locked)
    if not fr or not fr.castFrame or not fr.castBorder then return end
    IchaUI_Cast_EnsureCaps(fr)
    local nat = IchaUI_CAST_NAT or 214
    length = tonumber(length) or nat
    local lo = IchaUI_CAST_LEN_MIN or 80
    local hi = IchaUI_CAST_LEN_MAX or 420
    if length < lo then length = lo end
    if length > hi then length = hi end
    local sliceL = IchaUI_CAST_SLICE_L or 48
    local sliceR = IchaUI_CAST_SLICE_R or 48
    if locked then
        sliceL = IchaUI_CAST_SH_SLICE or 72
    end
    local artX = IchaUI_CAST_ART_X or 28
    local texW = IchaUI_CAST_TEX_W or 256
    local hang = texW - (artX + (IchaUI_CAST_ART_W or 200))
    local midTex = texW - sliceL - sliceR
    local leftIn = sliceL - artX
    if leftIn < 1 then leftIn = 1 end
    local rightIn = sliceR - hang
    if rightIn < 1 then rightIn = 1 end
    local midPx = length - leftIn - rightIn
    if midPx < 4 then midPx = 4 end
    local uL = sliceL / texW
    local uR0 = (texW - sliceR) / texW
    local u1 = uR0
    if midPx < midTex then
        u1 = (sliceL + midPx) / texW
    end
    local path = IchaUI_CAST_BORDER
    if locked then path = IchaUI_CAST_SHIELD end
    local L = fr.castArtL
    local M = fr.castBorder
    local R = fr.castArtR
    local th = 64
    L:SetTexture(path)
    M:SetTexture(path)
    R:SetTexture(path)
    L:SetTexCoord(0, uL, 0, 1)
    M:SetTexCoord(uL, u1, 0, 1)
    R:SetTexCoord(uR0, 1, 0, 1)
    L:SetWidth(sliceL)
    M:SetWidth(midPx)
    R:SetWidth(sliceR)
    L:SetHeight(th)
    M:SetHeight(th)
    R:SetHeight(th)
    L:ClearAllPoints()
    M:ClearAllPoints()
    R:ClearAllPoints()
    L:SetPoint("LEFT", fr.castFrame, "LEFT", -artX, 0)
    M:SetPoint("LEFT", fr.castFrame, "LEFT", leftIn, 0)
    R:SetPoint("RIGHT", fr.castFrame, "RIGHT", hang, 0)
    IchaUI_Cast_TintArt(fr)
    local inL = IchaUI_CAST_IN_L or 6
    local inR = IchaUI_CAST_IN_R or 6
    if locked then
        inL = IchaUI_CAST_SH_L or 36
        inR = IchaUI_CAST_SH_R or 8
    end
    local fillMax = length - inL - inR
    if fillMax < 1 then fillMax = 1 end
    fr._castFillMax = fillMax
    fr._castFillInsetL = inL
    fr._castFillInsetR = inR
    fr._castFillInsetY = IchaUI_CAST_IN_Y or 7
    fr._castLenPx = length
end

-- Hide every cast-bar layer. Parent Hide() is not enough: a later Show() would
-- reveal leftover interruptible fill/spark/border under the shield.
function IchaUI_Cast_HidePieces(fr)
    if not fr then return end
    IchaUI_Cast_ClearPin(fr)
    if fr.castSpark then fr.castSpark:Hide() end
    if fr.castLag then fr.castLag:Hide() end
    if fr.castSpellIcon then fr.castSpellIcon:Hide() end
    if fr.castIconHolder then fr.castIconHolder:Hide() end
    if fr.castBg then fr.castBg:Hide() end
    if fr.castFill then fr.castFill:Hide() end
    if fr.castArtL then fr.castArtL:Hide() end
    if fr.castArtR then fr.castArtR:Hide() end
    if fr.castBorder then fr.castBorder:Hide() end
    if fr.castTime then fr.castTime:Hide() end
    if fr.castInterrupt then fr.castInterrupt:Hide() end
    if fr.castFrame then fr.castFrame:Hide() end
end

-- Same uninterruptible cast coming back as interruptible (ClassicAPI / SuperWoW linger).
function IchaUI_Cast_IsLockLeftover(fr, info, nowSec)
    if not fr or not info then return false end
    if info.locked then return false end
    if not fr._castLocked and (fr._castLockExpire or 0) <= (nowSec or 0) then
        return false
    end
    local start = tonumber(info.start) or 0
    local prev = tonumber(fr._castLockStart) or 0
    local d = start - prev
    if d < 0 then d = -d end
    if prev > 0 and d < 800 then return true end
    local n = info.name or ""
    if n ~= "" and n == (fr._castLockName or "") then return true end
    return false
end

-- Cancel/stop must drop both bars. A stale interruptible copy of fishing
-- must not keep counting, and must not seed the Test UI sample.
function IchaUI_Cast_QuenchFrame(fr)
    if not fr then return end
    local nowSec = GetTime and GetTime() or 0
    local hold = fr._interruptedUntil or 0
    local wasLocked = (fr._castLocked and true or false) or ((fr._castLockExpire or 0) > nowSec)
    fr._castLocked = false
    fr._castLockName = ""
    fr._castLockStart = 0
    fr._castLockExpire = 0
    fr._castLagW = 0
    fr._testCastStart = nil
    fr._castQuenchMark = nowSec * 1000
    fr._castQuenchUntil = nowSec + 1.5
    if IchaUI_Cast_MarkDone and fr.unit then
        local g = IchaUI_Swing_Guid and IchaUI_Swing_Guid(fr.unit)
        if g then IchaUI_Cast_MarkDone(g, nil, fr._castPinStart) end
        if fr.unit == "player" then IchaUI_Cast_MarkDone("player", nil, fr._castPinStart) end
    end
    if IchaUI_Cast_ClearPin then IchaUI_Cast_ClearPin(fr) end
    if wasLocked or hold <= nowSec then
        fr._casting = false
        fr._interruptedUntil = 0
        if IchaUI_Cast_HidePieces then IchaUI_Cast_HidePieces(fr) end
    end
end

function IchaUI_Cast_QuenchUnit(who)
    if not who or who == "" or who == "none" then return end
    if string.sub(who, 1, 6) == "IchaUI" then return end
    local function dropKey(key)
        if not key or key == "" then return end
        if swCastClear then swCastClear(key) end
    end
    if IchaUI_Swing_Guid then
        local g = IchaUI_Swing_Guid(who)
        if g then dropKey(g) end
    end
    if type(UnitName) == "function" then
        local ok, n = pcall(UnitName, who)
        if ok and type(n) == "string" and n ~= "" then dropKey(n) end
    end
    local function consider(fr)
        if not fr or not fr.unit then return end
        local u = fr.unit
        if not u or u == "" or u == "none" then return end
        if string.sub(u, 1, 6) == "IchaUI" then return end
        local hit = (u == who)
        if not hit and type(UnitIsUnit) == "function" then
            local ok, same = pcall(UnitIsUnit, u, who)
            hit = ok and same and true or false
        end
        if hit then IchaUI_Cast_QuenchFrame(fr) end
    end
    if IchaUIUF_Get then
        consider(IchaUIUF_Get("player"))
        consider(IchaUIUF_Get("target"))
        consider(IchaUIUF_Get("tot"))
        consider(IchaUIUF_Get("focus"))
    end
    if IchaUI_Swing_Frames then
        local _, fr
        for _, fr in pairs(IchaUI_Swing_Frames) do
            consider(fr)
        end
    end
end

function IchaUI_Cast_QuenchEvent(event, arg1)
    local who = "player"
    if event and string.sub(event, 1, 5) == "UNIT_" then
        if arg1 and arg1 ~= "" and arg1 ~= "none" and string.sub(tostring(arg1), 1, 6) ~= "IchaUI" then
            who = arg1
        end
    end
    IchaUI_Cast_QuenchUnit(who)
end

-- Latency strip MUST stay inside the fill area (never past the bar/chrome).
-- Left-anchored: 1.12 right-anchor + SetWidth can grow past the frame edge.
function IchaUI_Cast_PlaceLag(fr, lagW, channel)
    local castLag = fr and fr.castLag
    local castFrame = fr and fr.castFrame
    if not castLag or not castFrame then return end
    if fr._castLocked then
        castLag:Hide()
        return
    end
    local maxW = tonumber(fr._castFillMax) or 1
    if maxW < 1 then maxW = 1 end
    local w = tonumber(lagW) or 0
    -- Incoming / no lag computed: do not paint a fake mark on target bars.
    if w <= 0 then
        fr._castLagW = 0
        castLag:Hide()
        return
    end
    if w < 4 then w = 4 end
    if w > maxW * 0.35 then w = maxW * 0.35 end
    if w > maxW then w = maxW end
    fr._castLagW = w
    local il = tonumber(fr._castFillInsetL) or 0
    local iy = tonumber(fr._castFillInsetY) or 0
    castLag:ClearAllPoints()
    if channel then
        -- Channel: lag warning at the LEFT of the fill region
        castLag:SetPoint("TOPLEFT", castFrame, "TOPLEFT", il, -iy)
        castLag:SetPoint("BOTTOMLEFT", castFrame, "BOTTOMLEFT", il, iy)
    else
        -- Normal cast: lag is the rightmost slice of the fill region
        local x = il + maxW - w
        castLag:SetPoint("TOPLEFT", castFrame, "TOPLEFT", x, -iy)
        castLag:SetPoint("BOTTOMLEFT", castFrame, "BOTTOMLEFT", x, iy)
    end
    castLag:SetWidth(math.max(0.001, w))
    if castLag.SetDrawLayer then castLag:SetDrawLayer("OVERLAY") end
    castLag:SetVertexColor(0.85, 0.12, 0.12, 1)
    castLag:Show()
end


function IchaUI_Swing_OrientSpark(tex, angle)
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
    pcall(function()
        tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
    end)
end


function IchaUI_Swing_GetSpeed(unit)
    if not unit or type(UnitAttackSpeed) ~= "function" then return nil end
    local ok, s = pcall(UnitAttackSpeed, unit)
    if not ok then return nil end
    s = tonumber(s)
    if not s or s <= 0 then return nil end
    return s
end

function IchaUI_Swing_Hide(fr)
    if not fr then return end
    if fr.swingFill then fr.swingFill:Hide() end
    if fr.swingSpark then fr.swingSpark:Hide() end
end

function IchaUI_Swing_Reset(fr)
    if not fr or not fr.swingBg then return end
    local now = GetTime and GetTime() or 0
    -- Collapse MAINHAND + combat-log double fire; still accept real next swings
    if fr._swingStart and (now - fr._swingStart) < 0.05 then
        return
    end
    fr._swingStart = now
    local spd = IchaUI_Swing_GetSpeed(fr.unit)
    if spd then fr._swingPeriod = spd end
    if not fr._swingPeriod or fr._swingPeriod <= 0 then
        fr._swingPeriod = 2.0
    end
end

function IchaUI_Swing_Clear(fr)
    if not fr then return end
    fr._swingStart = nil
    -- keep period if known; clear progress until next hit
    IchaUI_Swing_Hide(fr)
end

function IchaUI_Swing_RefreshSpeed(fr)
    if not fr or not fr.swingBg then return end
    local unit = fr.unit
    local newPeriod = IchaUI_Swing_GetSpeed(unit)
    if not newPeriod then return end
    local oldPeriod = tonumber(fr._swingPeriod)
    local startT = fr._swingStart
    if startT and oldPeriod and oldPeriod > 0 and newPeriod > 0 and newPeriod ~= oldPeriod then
        local now = GetTime and GetTime() or 0
        local elapsed = now - startT
        local progress = elapsed / oldPeriod
        if progress < 0 then progress = 0 end
        if progress > 1 then progress = 1 end
        -- Keep visual progress across speed changes
        fr._swingStart = now - (progress * newPeriod)
    end
    fr._swingPeriod = newPeriod
end

function IchaUI_Swing_Update(fr)
    if not fr or not fr.swingBg or not fr.swingFill or not fr.swingSpark then return end
    local unit = fr.unit
    local bg = fr.swingBg
    local fill = fr.swingFill
    local spark = fr.swingSpark
    if badUnitToken(unit) then
        IchaUI_Swing_Hide(fr)
        return
    end
    local okExists, exists = pcall(UnitExists, unit)
    if not okExists or not exists then
        IchaUI_Swing_Hide(fr)
        return
    end
    -- Hide filled swing bar while out of combat (player gate for both bars)
    if not (UnitAffectingCombat and UnitAffectingCombat("player")) then
        IchaUI_Swing_Hide(fr)
        return
    end
    if (UnitIsDead and UnitIsDead(unit)) or (UnitIsGhost and UnitIsGhost(unit)) then
        fr._swingStart = nil
        IchaUI_Swing_Hide(fr)
        return
    end
    local barW = bg:GetWidth() or 0
    if barW < 1 then barW = 1 end
    local gapH = bg:GetHeight() or 2
    local startT = fr._swingStart
    local period = tonumber(fr._swingPeriod)
    if not period or period <= 0 then
        period = IchaUI_Swing_GetSpeed(unit)
        if period then fr._swingPeriod = period end
    end
    if not startT or not period or period <= 0 then
        IchaUI_Swing_Hide(fr)
        return
    end
    local now = GetTime and GetTime() or 0
    local pct = (now - startT) / period
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end
    if pct <= 0 then
        IchaUI_Swing_Hide(fr)
        return
    end
    local fw = barW * pct
    if fw < 0.001 then fw = 0.001 end
    fill:ClearAllPoints()
    fill:SetHeight(gapH)
    fill:SetWidth(fw)
    spark:ClearAllPoints()
    local sh = gapH * 4
    if sh < 8 then sh = 8 end
    spark:SetWidth(12)
    spark:SetHeight(sh)
    if fr.key == "target" or fr.key == "tot" or fr.key == "focus" then
        -- Fill right → left (toward screen center when target is on the right)
        fill:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 0, 0)
        fill:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
        spark:SetPoint("CENTER", fill, "LEFT", 0, 0)
        -- Stock spark points up; tip faces travel (left)
        IchaUI_Swing_OrientSpark(spark, math.pi / 2)
    else
        -- Player: fill left → right
        fill:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
        fill:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
        spark:SetPoint("CENTER", fill, "RIGHT", 0, 0)
        -- Tip faces travel (right)
        IchaUI_Swing_OrientSpark(spark, -math.pi / 2)
    end
    fill:Show()
    spark:Show()
end

function IchaUI_Swing_Guid(unit)
    if IchaUI_LEAVING then return nil end
    if not unit or type(UnitExists) ~= "function" then return nil end
    if unit == "" or unit == "none" then return nil end
    if string.sub(unit, 1, 6) == "IchaUI" then return nil end
    -- SuperWoW: UnitExists returns (exists, guid). Plain 1.12 returns only exists.
    -- Do not pcall: Lua 5.0 keeps only the first return (would drop guid).
    local exists, g = UnitExists(unit)
    if not exists then return nil end
    if type(g) == "string" and g ~= "" then
        return g
    end
    if type(UnitGUID) == "function" then
        local ok, g2 = pcall(UnitGUID, unit)
        if ok and g2 and g2 ~= "" then return tostring(g2) end
    end
    return nil
end

function IchaUI_Swing_CasterIsUnit(caster, unit)
    if not caster or not unit then return false end
    if unit == "" or unit == "none" then return false end
    local c = tostring(caster)
    if c == "" or c == "none" then return false end
    if c == unit then return true end
    local ug = IchaUI_Swing_Guid(unit)
    if ug and c == ug then return true end
    -- SuperWoW: GUID strings are valid unit tokens for UnitIsUnit
    if type(UnitIsUnit) == "function" then
        local ok, r = pcall(UnitIsUnit, c, unit)
        if ok and r then return true end
        if ug then
            ok, r = pcall(UnitIsUnit, ug, c)
            if ok and r then return true end
        end
    end
    return false
end

-- SuperWoW UNIT_CASTEVENT MAINHAND/OFFHAND carries caster GUID — unique per mob.
function IchaUI_Swing_ResetToken(unit)
    local map = IchaUI_Swing_Frames
    if not map or not unit then return end
    if unit == "" or unit == "none" then return end
    local _, fr
    for _, fr in pairs(map) do
        if fr and fr.swingBg and fr.unit and fr.unit ~= "" and fr.unit ~= "none" then
            local match = (fr.unit == unit)
            if not match and UnitIsUnit then
                local ok, r = pcall(UnitIsUnit, fr.unit, unit)
                if ok and r then match = true end
            end
            if not match then
                local ug = IchaUI_Swing_Guid(fr.unit)
                if ug and ug == tostring(unit) then match = true end
            end
            if match then IchaUI_Swing_Reset(fr) end
        end
    end
end

function IchaUI_Swing_RefreshToken(unit)
    local map = IchaUI_Swing_Frames
    if not map or not unit then return end
    if unit == "" or unit == "none" then return end
    local _, fr
    for _, fr in pairs(map) do
        if fr and fr.swingBg and fr.unit and fr.unit ~= "" and fr.unit ~= "none" then
            local match = (fr.unit == unit)
            if not match and UnitIsUnit then
                local ok, r = pcall(UnitIsUnit, fr.unit, unit)
                if ok and r then match = true end
            end
            if not match then
                local ug = IchaUI_Swing_Guid(fr.unit)
                if ug and ug == tostring(unit) then match = true end
            end
            if match then IchaUI_Swing_RefreshSpeed(fr) end
        end
    end
end

function IchaUI_Swing_OnCastEvent(caster, eventType)
    local et = eventType and string.upper(tostring(eventType)) or ""
    -- Mainhand white swings only (OH would desync the MH bar)
    if et ~= "MAINHAND" then return end
    -- GUID / nameplate token: resets combat plates SetUnit'd to that mob
    if caster and caster ~= "" and caster ~= "none" then
        IchaUI_Swing_ResetToken(caster)
    end
    if IchaUI_Swing_CasterIsUnit(caster, "player") then
        IchaUI_Swing_ResetToken("player")
        return
    end
    if IchaUI_Swing_CasterIsUnit(caster, "target") then
        IchaUI_Swing_ResetToken("target")
    end
    if IchaUI_Swing_CasterIsUnit(caster, "targettarget") then
        IchaUI_Swing_ResetToken("targettarget")
    end
end

function IchaUI_Swing_MsgIsUnit(msg, unit)
    if not msg or not UnitName or not unit then return false end
    local tname = UnitName(unit)
    if not tname or tname == "" then return false end
    local n = string.len(tname)
    if string.sub(msg, 1, n) ~= tname then return false end
    local nextc = string.sub(msg, n + 1, n + 1)
    if nextc ~= "" and nextc ~= " " and nextc ~= "'" then
        return false
    end
    return true
end

function IchaUI_Swing_OnCombatEvent()
    local e = event
    if e == "CHAT_MSG_COMBAT_SELF_HITS" or e == "CHAT_MSG_COMBAT_SELF_MISSES" then
        -- Chat fallback / debounce vs MAINHAND double-fire
        local fr = IchaUI_Swing_Frames and IchaUI_Swing_Frames["player"]
        if fr then
            local now = GetTime and GetTime() or 0
            if not fr._swingStart or (now - fr._swingStart) > 0.12 then
                IchaUI_Swing_ResetToken("player")
            end
        end
        return
    end
    if e == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS"
        or e == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES"
        or e == "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS"
        or e == "CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES"
        or e == "CHAT_MSG_COMBAT_HOSTILEPLAYER_VS_SELF_HITS"
        or e == "CHAT_MSG_COMBAT_HOSTILEPLAYER_VS_SELF_MISSES" then
        -- Name-only combat log cannot tell identical mobs apart.
        -- Prefer GUID MAINHAND; use chat only when target has no GUID.
        if not IchaUI_Swing_Guid("target") and IchaUI_Swing_MsgIsUnit(arg1, "target") then
            IchaUI_Swing_ResetToken("target")
        end
        if not IchaUI_Swing_Guid("targettarget") and IchaUI_Swing_MsgIsUnit(arg1, "targettarget") then
            IchaUI_Swing_ResetToken("targettarget")
        end
        return
    end
    if e == "UNIT_COMBAT" then
        return
    end
    if e == "UNIT_ATTACK_SPEED" then
        local u = arg1
        if u and u ~= "" and u ~= "none" then
            IchaUI_Swing_RefreshToken(u)
        end
        return
    end
end


local function makeAuraSlot(parent)
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetWidth(AURA_W)
    icon:SetHeight(AURA_H)
    icon:SetFrameLevel((parent:GetFrameLevel() or 1) + 25)
    icon:EnableMouse(true)

    local tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex = tex
    IchaUI_PinAuraTex(icon)

    -- Rounded corners (same mask as action bars), rectangular frame
    local round = icon:CreateTexture(nil, "ARTWORK")
    round:SetTexture("Interface\\AddOns\\IchaUI\\media\\roundmask.tga")
    round:SetAllPoints(tex)
    round:SetVertexColor(0, 0, 0, 1)
    icon.roundMask = round

    -- Gold border (action-bar style), sits above icon/mask
    local border = CreateFrame("Frame", nil, icon)
    border:SetFrameLevel((icon:GetFrameLevel() or 1) + 3)
    icon.border = border
    applyAuraGold(border, 8, 1)

    -- No ActionButton-Border glow. That art stays a small centered square on
    -- these 4:3 slots. Debuff type is the gold border color only.

    local textLayer = CreateFrame("Frame", nil, icon)
    textLayer:SetAllPoints(icon)
    textLayer:SetFrameLevel((icon:GetFrameLevel() or 1) + 8)
    icon.textLayer = textLayer

    local cd = textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cd:SetPoint("BOTTOMRIGHT", textLayer, "BOTTOMRIGHT", 1, -1)
    cd:SetTextColor(1, 1, 1)
    icon.count = cd

    local timer = textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timer:SetPoint("CENTER", textLayer, "CENTER", 0, 0)
    -- Match totem / imbue / shield timer gold
    timer:SetTextColor(1, 0.92, 0.65)
    icon.timer = timer

    icon.auraUnit = nil
    icon.auraIndex = nil
    icon.auraKind = nil
    icon.expires = nil
    icon:SetScript("OnEnter", function()
        if not icon.auraUnit or not icon.auraIndex then return end
        GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
        if icon.auraKind == "buff" then
            GameTooltip:SetUnitBuff(icon.auraUnit, icon.auraIndex)
        else
            GameTooltip:SetUnitDebuff(icon.auraUnit, icon.auraIndex)
        end
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    icon:Hide()
    return icon
end

local frames = {}
IchaUI_Swing_Frames = frames -- swing helpers (defined above) need a global alias

function IchaUIUF_GetLevelFont()
    local d = db()
    local n = tonumber(d.levelFont) or 10
    if n < 6 then n = 6 end
    if n > 24 then n = 24 end
    return n
end

function IchaUIUF_SetLevelFont(v)
    local d = db()
    v = tonumber(v) or 10
    if v < 6 then v = 6 end
    if v > 24 then v = 24 end
    d.levelFont = v
    local map = IchaUI_Swing_Frames
    if not map then return end
    local _, fr
    for _, fr in pairs(map) do
        if fr and fr.applySize then fr:applySize() end
    end
end

-- Classic level-diff color for the level NUMBER only. The badge ring stays theme gold.
function IchaUI_LevelDiffColor(lvl, classification)
    lvl = tonumber(lvl) or 0
    if classification == "worldboss" or lvl < 0 then
        return 1, 0.1, 0.1, false
    end
    if lvl <= 0 then
        return 1, 0.82, 0, true
    end
    if type(GetDifficultyColor) == "function" then
        local col = nil
        local function grabDiff()
            col = GetDifficultyColor(lvl)
        end
        local okD = pcall(grabDiff)
        if okD and type(col) == "table" and col.r and col.g and col.b then
            local keep = false
            if col.r >= 0.95 and col.g >= 0.7 and col.b <= 0.15 then keep = true end
            return col.r, col.g, col.b, keep
        end
    end
    local mine = 1
    if type(UnitLevel) == "function" then
        local pl = nil
        local function grabMine()
            pl = UnitLevel("player")
        end
        local okP = pcall(grabMine)
        if okP and tonumber(pl) and tonumber(pl) > 0 then mine = tonumber(pl) end
    end
    local diff = lvl - mine
    if diff >= 5 then
        return 1, 0.1, 0.1, false
    end
    if diff >= 3 then
        return 1, 0.5, 0.25, false
    end
    if diff >= -2 then
        return 1, 0.82, 0, true
    end
    local green = 5
    if type(GetQuestGreenRange) == "function" then
        local gr = nil
        local function grabGreen()
            gr = GetQuestGreenRange()
        end
        local okG = pcall(grabGreen)
        if okG and tonumber(gr) then green = tonumber(gr) end
    end
    if -diff <= green then
        return 0.25, 0.75, 0.25, false
    end
    return 0.5, 0.5, 0.5, false
end

function IchaUI_PaintHpLevel(fs, unit)
    if not fs or badUnitToken(unit) then
        if fs then
            fs:SetText("")
            fs:Hide()
        end
        return
    end
    local okExists, exists = pcall(UnitExists, unit)
    if not okExists or not exists then
        fs:SetText("")
        fs:Hide()
        return
    end
    local lvl = (UnitLevel and UnitLevel(unit)) or 0
    local text
    if lvl < 0 then
        text = "??"
    elseif lvl > 0 then
        text = tostring(lvl)
    else
        text = "?"
    end
    local classif = nil
    if UnitClassification then
        local function grabClass()
            classif = UnitClassification(unit)
        end
        pcall(grabClass)
        if classif == "worldboss" then
            text = "??"
        elseif classif == "elite" or classif == "rareelite" then
            text = text .. "+"
        elseif classif == "rare" then
            text = text .. "r"
        end
    end
    local r, g, b = IchaUI_LevelDiffColor(lvl, classif)
    fs:SetText(text)
    fs:SetTextColor(r, g, b)
    fs:Show()
end

function IchaUI_PaintPortraitLevel(fs, unit, ring)
    if not fs then return 1, 0.82, 0, true end
    if badUnitToken(unit) then
        fs:SetText("?")
        fs:SetTextColor(1, 0.82, 0)
        if ring then IchaUI_PaintGoldRing(ring) end
        return 1, 0.82, 0, true
    end
    local exists = false
    local function grabExists()
        exists = UnitExists(unit)
    end
    local okE = pcall(grabExists)
    if not okE or not exists then
        fs:SetText("?")
        fs:SetTextColor(1, 0.82, 0)
        if ring then IchaUI_PaintGoldRing(ring) end
        return 1, 0.82, 0, true
    end
    local lvl = 0
    if type(UnitLevel) == "function" then
        local function grabLvl()
            lvl = UnitLevel(unit)
        end
        pcall(grabLvl)
        lvl = tonumber(lvl) or 0
    end
    local c = nil
    if type(UnitClassification) == "function" then
        local function grabC()
            c = UnitClassification(unit)
        end
        pcall(grabC)
    end
    local base
    if c == "worldboss" or lvl < 0 then
        base = "??"
    elseif lvl > 0 then
        base = tostring(lvl)
    else
        base = "?"
    end
    if c == "rareelite" then
        fs:SetText(base .. "R+")
    elseif c == "elite" then
        fs:SetText(base .. "+")
    elseif c == "rare" then
        fs:SetText(base .. "R")
    else
        fs:SetText(base)
    end
    local r, g, b = IchaUI_LevelDiffColor(lvl, c)
    fs:SetTextColor(r, g, b)
    if ring then IchaUI_PaintGoldRing(ring) end
    return r, g, b
end

function IchaUI_TintLevelPreview(fs, ring, lvl)
    local r, g, b = IchaUI_LevelDiffColor(lvl, nil)
    if fs then fs:SetTextColor(r, g, b) end
    if ring then IchaUI_PaintGoldRing(ring) end
end

function IchaUI_LevelStoreKey(key)
    if not key then return "player" end
    if string.find(key, "^combat") then return "combat" end
    if string.find(key, "^party") then return "party" end
    if string.find(key, "^raid") then return "raid" end
    if key == "focus" then return "focus" end
    return key
end

function IchaUI_LevelRow(key)
    local d = db()
    if type(d.levelShow) ~= "table" then d.levelShow = {} end
    local store = IchaUI_LevelStoreKey(key)
    local row = d.levelShow[store]
    if type(row) ~= "table" then
        row = {}
        d.levelShow[store] = row
        if store == "focus" and type(d.levelShow.target) == "table" then
            row.portrait = d.levelShow.target.portrait
            row.bar = d.levelShow.target.bar
        end
    end
    return row
end

function IchaUI_LevelCanPortrait(key)
    local store = IchaUI_LevelStoreKey(key)
    if store == "player" or store == "target" or store == "tot" or store == "combat" or store == "focus" or store == "party" then return true end
    return false
end

function IchaUI_LevelPortraitOn(key)
    if not IchaUI_LevelCanPortrait(key) then return false end
    local row = IchaUI_LevelRow(key)
    if row.portrait == false then return false end
    return true
end

-- bar nil = health-bar level only when the portrait level is not showing.
function IchaUI_LevelBarOn(key, portraitShowing)
    local row = IchaUI_LevelRow(key)
    if row.bar == true then return true end
    if row.bar == false then return false end
    return not portraitShowing
end

function IchaUI_LevelBarLabel(key)
    local row = IchaUI_LevelRow(key)
    if row.bar == true then return "Bar lvl: On" end
    if row.bar == false then return "Bar lvl: Off" end
    return "Bar lvl: Auto"
end

function IchaUI_RefreshLevelShow()
    local map = IchaUI_Swing_Frames
    if map then
        local _, fr
        for _, fr in pairs(map) do
            if fr then
                if fr.update then fr:update() end
                if fr.updatePvP then fr:updatePvP() end
            end
        end
    end
    if IchaUI_CombatLayout then IchaUI_CombatLayout() end
end

function IchaUIUF_ToggleLevelPortrait(key)
    local row = IchaUI_LevelRow(key)
    if IchaUI_LevelPortraitOn(key) then
        row.portrait = false
    else
        row.portrait = true
    end
    IchaUI_RefreshLevelShow()
end

-- pick: "auto" / "on" / "off" (dropdown); nil steps Auto -> On -> Off.
function IchaUIUF_CycleLevelBar(key, pick)
    local row = IchaUI_LevelRow(key)
    if pick == "auto" then
        row.bar = nil
    elseif pick == "on" then
        row.bar = true
    elseif pick == "off" then
        row.bar = false
    elseif row.bar == nil then
        row.bar = true
    elseif row.bar == true then
        row.bar = false
    else
        row.bar = nil
    end
    IchaUI_RefreshLevelShow()
end
local testMode = false
local testShowParty = true
local testShowRaid = true
local TEST_BUFF_TEX = "Interface\\Icons\\Spell_Nature_Regeneration"
local TEST_DEBUFF_TEX = "Interface\\Icons\\Spell_Shadow_ShadowWordPain"
local TEST_CAST_DUR = 2.0
local partyRoot = nil
local partyFrames = {}
local partyMoving = false
local raidRoot = nil
local raidFrames = {}
local raidMoving = false
local layoutRaid -- forward
local shouldShowRaidFrames -- forward

local partyMover = nil

local function isPartyUnit(u)
    if type(u) ~= "string" then return false end
    return string.find(u, "^party%d") ~= nil
end

local function isRaidUnit(u)
    if not u then return false end
    return string.find(u, "^raid%d+") ~= nil
end


local function isTargetFrameUnit(u)
    return u == "target" or u == "targettarget"
end


local function partyDb()
    local d = db()
    if not d.party then d.party = {} end
    local p = d.party
    if p.scale == nil then p.scale = 1 end
    if p.width == nil then p.width = BASE_W end
    if p.height == nil then p.height = BASE_H end
    if p.pad == nil then p.pad = 8 end
    if p.hidden == nil then p.hidden = false end
    return p
end

local function savePartyDb()
    local d = db()
    d.party = partyDb()
    IchaUIDB.uf = d
end

local RAID_W = math.floor(BASE_W / 2) -- half party width
local RAID_COLS, RAID_ROWS = 20, 2

local function raidDb()
    local d = db()
    if not d.raid then d.raid = {} end
    local r = d.raid
    if r.scale == nil then r.scale = 1 end
    if r.width == nil then r.width = RAID_W end
    if r.height == nil then r.height = BASE_H end
    if r.pad == nil then r.pad = 0 end
    if r.cols == nil then r.cols = RAID_COLS end
    if r.rows == nil then r.rows = RAID_ROWS end
    if r.hidden == nil then r.hidden = false end
    -- Keep within 40 pre-built slots
    r.cols = clamp(tonumber(r.cols) or RAID_COLS, 1, 40)
    r.rows = clamp(tonumber(r.rows) or RAID_ROWS, 1, 40)
    if r.cols * r.rows > 40 then
        -- Prefer shrinking rows when over capacity
        r.rows = math.max(1, math.floor(40 / r.cols))
    end
    return r
end

local function saveRaidDb()
    local d = db()
    d.raid = raidDb()
    IchaUIDB.uf = d
end


local function saveFrame(key, fr)
    local d = db()
    if not d[key] then d[key] = {} end
    local s = d[key]
    s.scale = fr.scale
    s.width = fr.width
    s.height = fr.height
    s.hidden = fr.hidden and true or nil
    if fr.hasPortrait then
        s.portrait = fr.portraitEnabled and true or false
        s.portraitScale = fr.portraitScale or PORTRAIT_DEFAULT_SCALE
        s.portraitRing = fr.portraitRing or PORTRAIT_DEFAULT_RING
        s.portraitOffsetX = fr.portraitOffsetX or 0
        s.portraitOffsetY = fr.portraitOffsetY or 0
        s.badgeAngle = fr.badgeAngle or 0
        s.badgeScale = fr.badgeScale or 1
        s.badgeOffsetX = fr.badgeOffsetX or 0
        s.badgeOffsetY = fr.badgeOffsetY or 0
        if fr.badgeHost == "frame" or fr.badgeHost == "portrait" then
            s.badgeHost = fr.badgeHost
        else
            s.badgeHost = nil
        end
        s.shieldChargeEnabled = fr.shieldChargeEnabled ~= false
        s.shieldChargeSpread = fr.shieldChargeSpread or 90
        s.shieldChargeSize = fr.shieldChargeSize or 10
        s.shieldChargeAngle = fr.shieldChargeAngle or 0
        s.shieldChargeReverse = fr.shieldChargeReverse and true or false
        s.shieldChargeOffsetX = fr.shieldChargeOffsetX or 0
        s.shieldChargeOffsetY = fr.shieldChargeOffsetY or 0
    end
    if fr.root and fr.root.GetPoint and not fr.managedPos then
        local p, rel, rp, x, y = fr.root:GetPoint(1)
        s.point = p
        s.relPoint = rp or p
        s.x = tonumber(x) or 0
        s.y = tonumber(y) or 0
    end
    -- Keep a top-level stamp so the SV file always dirties
    IchaUIDB.uf = d
end

local function loadFrame(key, defaults)
    local s = (IchaUIDB and IchaUIDB.uf and IchaUIDB.uf[key]) or {}
    local src = nil
    local partyKey = (type(key) == "string" and string.find(key, "^party")) and true or false
    if key == "focus" and IchaUIDB and IchaUIDB.uf and type(IchaUIDB.uf.target) == "table" then
        src = IchaUIDB.uf.target
    elseif partyKey and IchaUIDB and IchaUIDB.uf and type(IchaUIDB.uf.party) == "table" then
        -- Shared party record. Never copy player or target onto party.
        src = IchaUIDB.uf.party
    end
    local function pick(field, fallback)
        if partyKey and src and src[field] ~= nil then return src[field] end
        if s[field] ~= nil then return s[field] end
        if (not partyKey) and src and src[field] ~= nil then return src[field] end
        return fallback
    end
    local portraitOn = defaults.portrait
    if partyKey and src and src.portrait ~= nil then
        portraitOn = src.portrait and true or false
    elseif s.portrait ~= nil then
        portraitOn = s.portrait and true or false
    elseif (not partyKey) and src and src.portrait ~= nil then
        portraitOn = src.portrait and true or false
    elseif portraitOn == nil then
        portraitOn = false
    end
    local shieldOn = true
    if s.shieldChargeEnabled ~= nil then
        shieldOn = s.shieldChargeEnabled ~= false
    elseif (not partyKey) and src and src.shieldChargeEnabled ~= nil then
        shieldOn = src.shieldChargeEnabled ~= false
    end
    local badgeHost = nil
    if partyKey and src and (src.badgeHost == "frame" or src.badgeHost == "portrait") then
        badgeHost = src.badgeHost
    elseif s.badgeHost == "frame" or s.badgeHost == "portrait" then
        badgeHost = s.badgeHost
    end
    return {
        scale = clamp(tonumber(pick("scale", defaults.scale)) or defaults.scale, 0.4, 3),
        width = clamp(tonumber(pick("width", defaults.width)) or defaults.width, 1, 600),
        height = clamp(tonumber(pick("height", defaults.height)) or defaults.height, 1, 420),
        hidden = s.hidden and true or false,
        portrait = portraitOn and true or false,
        portraitScale = clamp(tonumber(pick("portraitScale", defaults.portraitScale or PORTRAIT_DEFAULT_SCALE)) or PORTRAIT_DEFAULT_SCALE, 0.8, 2.5),
        portraitRing = clamp(tonumber(pick("portraitRing", defaults.portraitRing or PORTRAIT_DEFAULT_RING)) or PORTRAIT_DEFAULT_RING, 0.90, 1.40),
        portraitOffsetX = clamp(tonumber(pick("portraitOffsetX", defaults.portraitOffsetX or 0)) or 0, -40, 40),
        portraitOffsetY = clamp(tonumber(pick("portraitOffsetY", defaults.portraitOffsetY or 0)) or 0, -40, 40),
        badgeAngle = clamp(tonumber(pick("badgeAngle", defaults.badgeAngle or 0)) or 0, 0, 360),
        badgeScale = clamp(tonumber(pick("badgeScale", defaults.badgeScale or 1)) or 1, 0.5, 2.0),
        badgeOffsetX = clamp(tonumber(pick("badgeOffsetX", defaults.badgeOffsetX or 0)) or 0, -40, 40),
        badgeOffsetY = clamp(tonumber(pick("badgeOffsetY", defaults.badgeOffsetY or 0)) or 0, -40, 40),
        badgeHost = badgeHost,
        shieldChargeEnabled = shieldOn,
        shieldChargeSpread = clamp(tonumber(pick("shieldChargeSpread", defaults.shieldChargeSpread or 90)) or 90, 10, 360),
        shieldChargeSize = clamp(tonumber(pick("shieldChargeSize", defaults.shieldChargeSize or 10)) or 10, 6, 28),
        shieldChargeAngle = clamp(tonumber(pick("shieldChargeAngle", defaults.shieldChargeAngle or 0)) or 0, -360, 360),
        shieldChargeReverse = (pick("shieldChargeReverse", false) and true or false),
        shieldChargeOffsetX = clamp(tonumber(pick("shieldChargeOffsetX", defaults.shieldChargeOffsetX or 0)) or 0, -40, 40),
        shieldChargeOffsetY = clamp(tonumber(pick("shieldChargeOffsetY", defaults.shieldChargeOffsetY or 0)) or 0, -40, 40),
        point = s.point,
        relPoint = s.relPoint,
        x = tonumber(s.x),
        y = tonumber(s.y),
    }
end

local TEXT_DEFAULTS = {
    nameX = 0, nameY = 4,
    hpX = 0, hpY = -7,
    nameScale = 1, hpScale = 1, powerScale = 1,
    nameAlign = "CENTER", hpAlign = "CENTER", powerAlign = "CENTER",
    showHpPct = false,
    showPowerText = false,
    buffPad = 2,
    debuffPad = 2,
    -- Aura layout (per frame kind); TOP/BOTTOM match legacy above/below grids
    buffScale = 1, debuffScale = 1,
    buffOffsetX = 0, buffOffsetY = 0,
    debuffOffsetX = 0, debuffOffsetY = 0,
    buffAnchor = "TOPLEFT",
    debuffAnchor = "BOTTOMLEFT",
}

local TEXT_KINDS = { "player", "target", "tot", "party", "raid", "combat", "focus" }

local function validAlign(a)
    if a == "LEFT" or a == "RIGHT" or a == "CENTER" then return a end
    return "CENTER"
end


-- Global (not local): Lua 5.0 chunk local budget. Valid: TOP/BOTTOM/LEFT/RIGHT + corners.
function IchaUI_ValidAuraAnchor(a)
    if a == "TOPLEFT" or a == "TOP" or a == "TOPRIGHT"
        or a == "BOTTOMLEFT" or a == "BOTTOM" or a == "BOTTOMRIGHT"
        or a == "LEFT" or a == "RIGHT" then
        return a
    end
    return "TOPLEFT"
end

-- Aura show mode + whitelist (globals: Lua 5.0 chunk local budget)
function IchaUI_ValidAuraShowMode(m)
    if m == "all" or m == "mine" or m == "whitelist" or m == "none" then
        return m
    end
    return "all"
end

function IchaUI_ParseAuraList(list)
    local out = {}
    if type(list) == "string" then
        local s = list
        s = string.gsub(s, "\r\n", "\n")
        s = string.gsub(s, "\r", "\n")
        local pos = 1
        local n = string.len(s)
        while pos <= n do
            local i = string.find(s, "\n", pos, true)
            local line
            if i then
                line = string.sub(s, pos, i - 1)
                pos = i + 1
            else
                line = string.sub(s, pos)
                pos = n + 1
            end
            line = string.gsub(line, "^%s+", "")
            line = string.gsub(line, "%s+$", "")
            if line ~= "" then
                table.insert(out, line)
            end
        end
        return out
    end
    if type(list) ~= "table" then return out end
    local i
    for i = 1, table.getn(list) do
        local e = list[i]
        if type(e) == "number" then
            table.insert(out, tostring(e))
        elseif type(e) == "string" then
            e = string.gsub(e, "^%s+", "")
            e = string.gsub(e, "%s+$", "")
            if e ~= "" then table.insert(out, e) end
        end
    end
    return out
end

function IchaUI_CopyAuraList(list)
    return IchaUI_ParseAuraList(list)
end

function IchaUI_BuildAuraWhitelistLookup(list)
    local names = {}
    local ids = {}
    list = IchaUI_ParseAuraList(list)
    local i
    for i = 1, table.getn(list) do
        local e = list[i]
        local n = tonumber(e)
        if n then ids[n] = true end
        if type(e) == "string" and e ~= "" then
            names[string.lower(e)] = true
        end
    end
    return { names = names, ids = ids }
end

function IchaUI_AuraWhitelistMatch(lookup, name, spellId)
    if not lookup then return false end
    local sid = tonumber(spellId)
    if sid and lookup.ids and lookup.ids[sid] then return true end
    local nameLow = nil
    if name and type(name) == "string" and name ~= "" then
        nameLow = string.lower(name)
        if lookup.names and lookup.names[nameLow] then return true end
    end
    -- Numeric whitelist entry: also match SpellInfo(id) name when aura has no id
    if nameLow and lookup.ids and type(SpellInfo) == "function" then
        local id, _
        for id, _ in pairs(lookup.ids) do
            local ok, sn = pcall(SpellInfo, id)
            if ok and type(sn) == "string" and string.lower(sn) == nameLow then
                return true
            end
        end
    end
    return false
end

-- mode: all|mine|whitelist|none; isMine boolean (caller computes)
function IchaUI_AuraPassesFilter(mode, lookup, name, spellId, isMine)
    mode = IchaUI_ValidAuraShowMode(mode)
    if mode == "none" then return false end
    if mode == "all" then return true end
    if mode == "mine" then
        if isMine then return true end
        return false
    end
    -- whitelist
    return IchaUI_AuraWhitelistMatch(lookup, name, spellId)
end


local function textKindForKey(key)
    if key == "focus" then return "focus" end
    if key == "player" or key == "target" or key == "tot" then
        return key
    end
    if key and string.find(key, "^party") then
        return "party"
    end
    if key and string.find(key, "^combat") then
        return "combat"
    end
    if key and string.find(key, "^raid") then
        return "raid"
    end
    return "player"
end

local function normalizeTextSettings(s)
    s = s or {}
    return {
        nameX = clamp(tonumber(s.nameX) or TEXT_DEFAULTS.nameX, -200, 200),
        nameY = clamp(tonumber(s.nameY) or TEXT_DEFAULTS.nameY, -200, 200),
        hpX = clamp(tonumber(s.hpX) or TEXT_DEFAULTS.hpX, -200, 200),
        hpY = clamp(tonumber(s.hpY) or TEXT_DEFAULTS.hpY, -200, 200),
        nameScale = clamp(tonumber(s.nameScale) or TEXT_DEFAULTS.nameScale, 0.4, 3.0),
        hpScale = clamp(tonumber(s.hpScale) or TEXT_DEFAULTS.hpScale, 0.4, 3.0),
        powerScale = clamp(tonumber(s.powerScale) or TEXT_DEFAULTS.powerScale, 0.4, 3.0),
        nameAlign = validAlign(s.nameAlign or TEXT_DEFAULTS.nameAlign),
        hpAlign = validAlign(s.hpAlign or TEXT_DEFAULTS.hpAlign),
        powerAlign = validAlign(s.powerAlign or TEXT_DEFAULTS.powerAlign),
        showHpPct = s.showHpPct and true or false,
        showPowerText = s.showPowerText and true or false,
        buffPad = clamp(tonumber(s.buffPad) or TEXT_DEFAULTS.buffPad, 0, 12),
        debuffPad = clamp(tonumber(s.debuffPad) or TEXT_DEFAULTS.debuffPad, 0, 12),
        buffScale = clamp(tonumber(s.buffScale) or TEXT_DEFAULTS.buffScale, 0.4, 3),
        debuffScale = clamp(tonumber(s.debuffScale) or TEXT_DEFAULTS.debuffScale, 0.4, 3),
        buffOffsetX = clamp(tonumber(s.buffOffsetX) or TEXT_DEFAULTS.buffOffsetX, -80, 80),
        buffOffsetY = clamp(tonumber(s.buffOffsetY) or TEXT_DEFAULTS.buffOffsetY, -80, 80),
        debuffOffsetX = clamp(tonumber(s.debuffOffsetX) or TEXT_DEFAULTS.debuffOffsetX, -80, 80),
        debuffOffsetY = clamp(tonumber(s.debuffOffsetY) or TEXT_DEFAULTS.debuffOffsetY, -80, 80),
        buffAnchor = IchaUI_ValidAuraAnchor(s.buffAnchor or TEXT_DEFAULTS.buffAnchor),
        debuffAnchor = IchaUI_ValidAuraAnchor(s.debuffAnchor or TEXT_DEFAULTS.debuffAnchor),
        buffsShown = s.buffsShown,
        debuffsShown = s.debuffsShown,
        buffPerRow = s.buffPerRow,
        debuffPerRow = s.debuffPerRow,
    }
end

local function legacyTextSource(d)
    if d.text and type(d.text) == "table" then
        return d.text
    end
    if d.nameX ~= nil or d.nameY ~= nil or d.hpX ~= nil or d.hpY ~= nil
        or d.nameAlign ~= nil or d.hpAlign ~= nil or d.powerAlign ~= nil
        or d.showHpPct ~= nil or d.showPowerText ~= nil then
        return d
    end
    return nil
end

local function ensureTextByType()
    local d = db()
    local by = d.textByType
    if type(by) ~= "table" then
        by = {}
        d.textByType = by
        local legacy = legacyTextSource(d)
        local i
        for i = 1, table.getn(TEXT_KINDS) do
            local k = TEXT_KINDS[i]
            if k ~= "focus" then
                by[k] = normalizeTextSettings(legacy)
            end
        end
        IchaUIDB.uf = d
        return by
    end
    local i
    for i = 1, table.getn(TEXT_KINDS) do
        local k = TEXT_KINDS[i]
        if type(by[k]) ~= "table" and k ~= "focus" then
            local legacy = legacyTextSource(d)
            by[k] = normalizeTextSettings(legacy)
        end
    end
    return by
end

local function loadTextSettings(kind)
    if not kind or kind == "" then kind = "player" end
    if kind ~= "player" and kind ~= "target" and kind ~= "tot" and kind ~= "party" and kind ~= "raid" and kind ~= "combat" and kind ~= "focus" then
        kind = "player"
    end
    local by = ensureTextByType()
    if kind == "focus" then
        local raw = by[kind]
        local src = by.target
        if type(raw) ~= "table" then raw = {} end
        if type(src) == "table" then
            local merged = {}
            local names = {
                "nameX", "nameY", "hpX", "hpY",
                "nameScale", "hpScale", "powerScale",
                "nameAlign", "hpAlign", "powerAlign",
                "showHpPct", "showPowerText",
                "buffPad", "debuffPad", "buffScale", "debuffScale",
                "buffOffsetX", "buffOffsetY", "debuffOffsetX", "debuffOffsetY",
                "buffAnchor", "debuffAnchor",
                "buffsShown", "debuffsShown", "buffPerRow", "debuffPerRow",
            }
            local fi
            for fi = 1, table.getn(names) do
                local fk = names[fi]
                if raw[fk] ~= nil then
                    merged[fk] = raw[fk]
                else
                    merged[fk] = src[fk]
                end
            end
            return normalizeTextSettings(merged)
        end
        return normalizeTextSettings(raw)
    end
    return normalizeTextSettings(by[kind])
end

local function saveTextSettings(kind, t)
    if not t then return end
    if not kind or kind == "" then kind = "player" end
    if kind ~= "player" and kind ~= "target" and kind ~= "tot" and kind ~= "party" and kind ~= "raid" and kind ~= "combat" and kind ~= "focus" then
        kind = "player"
    end
    local d = db()
    local by = ensureTextByType()
    by[kind] = normalizeTextSettings(t)
    d.textByType = by
    IchaUIDB.uf = d
end

-- Incoming heal prediction
-- Amount: tooltip of the EXACT rank being cast (name+texture match in spellbook).
-- Visual: green ONLY for the incoming chunk to the right of current HP.
-- Lifetime: only while healCastActive; wiped instantly on stop/cancel/fail.
local healFallback = {} -- [unitNameLower] = amount
local applyPlayerHealPred -- forward: used by cast events before definition

local healCastActive = false
local healDebug = false

local function wipeHealFallback()
    local k
    for k in pairs(healFallback) do
        healFallback[k] = nil
    end
    healCastActive = false
end

local healTip = CreateFrame("GameTooltip", "IchaUIHealTip", UIParent, "GameTooltipTemplate")
healTip:SetOwner(UIParent, "ANCHOR_NONE")

local function parseHealAmountFromTooltip()
    local best = nil
    local li
    for li = 1, 30 do
        local fs = getglobal("IchaUIHealTipTextLeft" .. li)
        local line = fs and fs:GetText()
        if not line then
            -- skip
        else
            local low = string.lower(line)
            -- Skip pure mana / cast-time lines
            local skip = false
            if string.find(low, "mana", 1, true) and not string.find(low, "heal", 1, true) then
                skip = true
            end
            if string.find(low, "sec cast", 1, true) then skip = true end
            if not skip then
                local a, b, one = nil, nil, nil
                local _
                -- Prefer "1234 to 1456" / "1234 - 1456" (ASCII hyphen only — unicode breaks Lua patterns)
                _, _, a, b = string.find(line, "(%d+)%s+[tT]o%s+(%d+)")
                if not a then _, _, a, b = string.find(line, "(%d+)%s*%-%s*(%d+)") end
                if not a then _, _, a, b = string.find(line, "(%d+)%s*/%s*(%d+)") end
                if a and b then
                    local lo, hi = tonumber(a), tonumber(b)
                    if lo and hi and hi >= lo and hi >= 20 then
                        local pick = math.floor((lo + hi) / 2 + 0.5) -- mid of tip range
                        if not best or pick > best then best = pick end
                    end
                else
                    -- Any sizable number on a heal/restore line
                    if string.find(low, "heal", 1, true) or string.find(low, "restor", 1, true)
                        or string.find(low, "for ", 1, true) then
                        _, _, one = string.find(line, "[Ff]or%s+(%d+)")
                        if not one then
                            -- last number on the line >= 20
                            local p = 1
                            while true do
                                local s, e, n = string.find(line, "(%d+)", p)
                                if not s then break end
                                local v = tonumber(n)
                                if v and v >= 20 then one = n end
                                p = e + 1
                            end
                        end
                        if one then
                            local n = tonumber(one)
                            if n and n >= 20 then
                                if not best or n > best then best = n end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function normTexPath(s)
    if type(s) ~= "string" then return s end
    s = string.gsub(s, "/", "\\")
    return string.lower(s)
end

-- "Healing Wave(Rank 8)" / "Healing Wave Rank 8" / bare "Healing Wave"
local function parseSpellNameRank(spellName)
    if not spellName or spellName == "" then return nil, nil end
    local _, _, b, r = string.find(spellName, "^(.+)%s*%(%s*[Rr]ank%s*(%d+)%s*%)%s*$")
    if b and r then
        b = string.gsub(b, "%s+$", "")
        b = string.gsub(b, "^%s+", "")
        return b, tonumber(r)
    end
    _, _, b, r = string.find(spellName, "^(.+)%s+[Rr]ank%s*(%d+)%s*$")
    if b and r then
        b = string.gsub(b, "%s+$", "")
        b = string.gsub(b, "^%s+", "")
        return b, tonumber(r)
    end
    return spellName, nil
end

local function tipAmountForSpellIndex(i, book)
    healTip:ClearLines()
    if not pcall(function() healTip:SetSpell(i, book) end) then return nil end
    return parseHealAmountFromTooltip()
end

-- SuperWoW: SpellInfo(id) → name, rank (CleveRoid / BlizzNameplatesPlus)
local function rankFromSpellId(spellId)
    if not spellId then return nil, nil end
    local try = {
        function()
            if type(SpellInfo) ~= "function" then return nil end
            return SpellInfo(spellId)
        end,
        function()
            if type(GetSpellInfo) ~= "function" then return nil end
            return GetSpellInfo(spellId)
        end,
    }
    local ti
    for ti = 1, table.getn(try) do
        local ok, nm, rk = pcall(try[ti])
        if ok and type(nm) == "string" and nm ~= "" then
            local rnum = nil
            if rk ~= nil then
                local _, _, rn = string.find(tostring(rk), "(%d+)")
                rnum = tonumber(rn)
            end
            if not rnum then
                local _, r2 = parseSpellNameRank(nm)
                rnum = r2
            end
            local base = parseSpellNameRank(nm)
            return base or nm, rnum
        end
    end
    return nil, nil
end

-- Tip amount for a SuperWoW spell id (hyperlink), never SetSpell(id) as book index.
local function tipAmountForSpellId(spellId)
    if not spellId then return nil end
    healTip:ClearLines()
    local link = "spell:" .. tostring(spellId)
    if pcall(function() healTip:SetHyperlink(link) end) then
        local amt = parseHealAmountFromTooltip()
        if amt then return amt end
    end
    return nil
end

-- Scan spellbook for base name; return tip for wantRank, or max rank tip if wantRank nil.
local function tipAmountFromSpellbook(base, wantRank)
    if not GetSpellName or not base then return nil, nil end
    local book = BOOKTYPE_SPELL or "spell"
    local exactAmt, exactRank = nil, nil
    local maxAmt, maxRank = nil, -1
    local i = 1
    while i <= 400 do
        local n, rank = GetSpellName(i, book)
        if not n then break end
        if n and base and string.lower(n) == string.lower(base) then
            local rnum = 0
            if rank then
                local _, _, rn = string.find(rank, "(%d+)")
                rnum = tonumber(rn) or 0
            end
            local amt = tipAmountForSpellIndex(i, book)
            if amt then
                if wantRank and rnum == wantRank then
                    exactAmt, exactRank = amt, rnum
                end
                if rnum >= maxRank then
                    maxRank, maxAmt = rnum, amt
                end
            end
        end
        i = i + 1
    end
    if exactAmt then return exactAmt, exactRank end
    -- Only fall back to max when caller asked for any rank (wantRank nil)
    if not wantRank and maxAmt then return maxAmt, maxRank end
    return nil, nil
end

-- Action bar that started this cast → tip (includes +healing).
local function tipFromCurrentAction(baseHint)
    if type(IsCurrentAction) ~= "function" then return nil, nil, nil end
    local slot
    for slot = 1, 120 do
        if IsCurrentAction(slot) then
            healTip:ClearLines()
            if pcall(function() healTip:SetAction(slot) end) then
                local fs = getglobal("IchaUIHealTipTextLeft1")
                local title = fs and fs:GetText()
                if title and title ~= "" then
                    local b, r = parseSpellNameRank(title)
                    local okBase = false
                    if not baseHint then
                        okBase = true
                    elseif b and string.lower(b) == string.lower(baseHint) then
                        okBase = true
                    elseif string.find(string.lower(title), string.lower(baseHint), 1, true) then
                        okBase = true
                    end
                    if okBase then
                        local amt = parseHealAmountFromTooltip()
                        return b or baseHint, r, amt
                    end
                end
            end
        end
    end
    return nil, nil, nil
end


-- RavenCraft DB spell ids → base name, rank, mid heal (no +healing).
-- Used when UNIT_CASTEVENT gives an id so we never collapse every rank to one tip.
-- Source: https://database.ravencraft.io/?spell=331 and ?spell=8004
local HEAL_SPELL_INFO = {
    -- Healing Wave
    [331]   = { base = "Healing Wave", rank = 1,  mid = 39 },
    [332]   = { base = "Healing Wave", rank = 2,  mid = 71 },
    [547]   = { base = "Healing Wave", rank = 3,  mid = 142 },
    [913]   = { base = "Healing Wave", rank = 4,  mid = 292 },
    [939]   = { base = "Healing Wave", rank = 5,  mid = 408 },
    [959]   = { base = "Healing Wave", rank = 6,  mid = 579 },
    [8005]  = { base = "Healing Wave", rank = 7,  mid = 797 },
    [10395] = { base = "Healing Wave", rank = 8,  mid = 1092 },
    [10396] = { base = "Healing Wave", rank = 9,  mid = 1464 },
    [25357] = { base = "Healing Wave", rank = 10, mid = 1735 },
    -- Lesser Healing Wave
    [8004]  = { base = "Lesser Healing Wave", rank = 1, mid = 174 },
    [8008]  = { base = "Lesser Healing Wave", rank = 2, mid = 264 },
    [8010]  = { base = "Lesser Healing Wave", rank = 3, mid = 359 },
    [10466] = { base = "Lesser Healing Wave", rank = 4, mid = 486 },
    [10467] = { base = "Lesser Healing Wave", rank = 5, mid = 668 },
    [10468] = { base = "Lesser Healing Wave", rank = 6, mid = 880 },
    [27624] = { base = "Lesser Healing Wave", rank = 6, mid = 880 },
}

-- Rank-aware heal size.
-- IMPORTANT: never return tipFromCurrentAction blindly — IsCurrentAction often
-- stays on one bar button, so every rank would show the same tip.
local function estimateHealAmount(spellName, castTexture, spellId, wantRank)
    if not spellName and not spellId then return nil end
    local base, rankFromName = parseSpellNameRank(spellName or "")
    if wantRank == nil then wantRank = rankFromName end
    if not base or base == "" then base = spellName end

    local dbInfo = nil
    if spellId then
        dbInfo = HEAL_SPELL_INFO[tonumber(spellId) or spellId]
        if dbInfo then
            base = dbInfo.base
            wantRank = dbInfo.rank
            if not spellName or spellName == "" then
                spellName = dbInfo.base .. " (Rank " .. dbInfo.rank .. ")"
            end
        else
            local nm, rk = rankFromSpellId(spellId)
            if nm then
                local b2 = parseSpellNameRank(nm)
                base = b2 or nm
                if rk then wantRank = rk end
                if not spellName or spellName == "" then spellName = nm end
            end
        end
        -- Tooltip from id (may include +healing on some clients)
        local byId = tipAmountForSpellId(spellId)
        if byId then return byId end
    end

    -- Current action: only if its rank matches the rank we want (or rank still unknown)
    do
        local ab, ar, aamt = tipFromCurrentAction(base)
        if aamt then
            if wantRank == nil then
                return aamt
            end
            if ar and ar == wantRank then
                return aamt
            end
        end
        if wantRank == nil and ar then wantRank = ar end
        if ab and (not base or base == "") then base = ab end
    end

    -- Spellbook tip for the EXACT rank (includes +healing)
    if wantRank then
        local amt = tipAmountFromSpellbook(base, wantRank)
        if amt then return amt end
    end
    -- DB midpoint for this exact spell id (rank-correct even if tip parse fails)
    if dbInfo and dbInfo.mid then
        return dbInfo.mid
    end
    -- Rank unknown only: highest rank tip
    if not wantRank then
        local amt = tipAmountFromSpellbook(base, nil)
        if amt then return amt end
    end
    return nil
end

-- Last-resort heal size when tooltip parse fails (still show green while casting)
local function fallbackHealAmount(unit)
    local hpMax = UnitHealthMax(unit) or 0
    local hpCur = UnitHealth(unit) or 0
    if hpMax < 1 then return 100 end
    local missing = hpMax - hpCur
    local guess = math.floor(hpMax * 0.25 + 0.5)
    if guess < 50 then guess = 50 end
    if missing > 0 and guess > missing then guess = missing end
    if guess < 1 then guess = 1 end
    return guess
end

local function getIncomingHeals(unit)
    if not unit or not UnitExists(unit) then return 0 end
    local ours = 0
    if healCastActive then
        local nm = UnitName(unit)
        if nm then
            ours = tonumber(healFallback[string.lower(nm)]) or 0
        end
    end
    local api = 0
    if type(UnitGetIncomingHeals) == "function" then
        local ok, a, b = pcall(UnitGetIncomingHeals, unit)
        if ok then
            local n = tonumber(a) or 0
            if type(b) == "number" and b > n then n = b end
            if n > 0 then api = n end
            if api == 0 then
                local ok2, own = pcall(UnitGetIncomingHeals, unit, "player")
                if ok2 and tonumber(own) and tonumber(own) > 0 then api = tonumber(own) end
            end
        end
    end
    -- Prefer our rank tip when present; otherwise API. If both, take the larger
    -- so a stale low API value can't hide a good tip (and we never go blank).
    if ours > 0 and api > 0 then
        if ours >= api then return ours end
        -- API much larger than ours → trust ours still if ours looks real (>= 50)
        if ours >= 50 then return ours end
        return api
    end
    if ours > 0 then return ours end
    if api > 0 then return api end
    local hc = LibStub and LibStub("LibHealComm-4.0", true)
    if not hc and HealComm then hc = HealComm end
    if hc then
        local guid = UnitGUID and UnitGUID(unit)
        if guid and hc.GetHealAmount then
            local amt = hc:GetHealAmount(guid, hc.ALL_HEALS or 0xF, GetTime and (GetTime() + 3) or nil)
            if tonumber(amt) and tonumber(amt) > 0 then return tonumber(amt) end
        end
    end
    return 0
end

local function noteIncomingHeal(destName, amount)
    if not destName then return end
    amount = tonumber(amount) or 0
    if amount <= 0 then return end
    wipeHealFallback()
    healFallback[string.lower(destName)] = amount
    healCastActive = true
end


local function placeHealPred(healPred, hpBg, barW, pct, incoming, hpMax)
    if not healPred or not hpBg then return end
    incoming = tonumber(incoming) or 0
    hpMax = tonumber(hpMax) or 1
    if hpMax < 1 then hpMax = 1 end
    pct = tonumber(pct) or 0
    if incoming <= 0 or pct >= 0.999 then
        healPred:Hide()
        return
    end
    -- Soft green CHUNK only to the right of current HP (not under the filled part)
    local incW = barW * (incoming / hpMax)
    if incW < 1 then
        healPred:Hide()
        return
    end
    local x = barW * pct
    local barH = hpBg:GetHeight()
    if not barH or barH < 1 then barH = 12 end
    healPred:ClearAllPoints()
    healPred:SetPoint("TOPLEFT", hpBg, "TOPLEFT", x, 0)
    healPred:SetPoint("BOTTOMLEFT", hpBg, "BOTTOMLEFT", x, 0)
    healPred:SetWidth(math.max(0.001, incW))
    healPred:SetHeight(barH)
    healPred:SetTexture("Interface/TargetingFrame/UI-StatusBar")
    healPred:SetVertexColor(0.35, 0.9, 0.45)
    healPred:SetAlpha(0.55)
    healPred:Show()
end

local function clearIncomingHeal(destName)
    if destName then
        healFallback[string.lower(destName)] = nil
    end
end



-- Inset aura grid for raid frames (inside the unit frame).
-- Honors /iui buff/debuff Anchor (TOP/BOTTOM/LEFT/RIGHT + corners), pad, and XY.
local function layoutAuraGridInset(icons, shown, perRow, aw, ah, anchor, pad, offsetX, offsetY, anchorPoint)
    shown = tonumber(shown) or 0
    perRow = tonumber(perRow) or 8
    aw = tonumber(aw) or AURA_W
    ah = tonumber(ah) or AURA_H
    if aw < 2 then aw = 2 end
    if ah < 2 then ah = 2 end
    if perRow < 1 then perRow = 1 end
    pad = tonumber(pad)
    if pad == nil then pad = 0 end
    if pad < 0 then pad = 0 end
    if pad > 8 then pad = 8 end
    offsetX = tonumber(offsetX) or 0
    offsetY = tonumber(offsetY) or 0
    local side = IchaUI_ValidAuraAnchor(anchorPoint or "BOTTOM")
    local gap = pad
    local edge = 2
    local i
    for i = 1, MAX_AURA_SLOTS do
        local icon = icons[i]
        if not icon then break end
        if i <= shown then
            local layKey = tostring(aw) .. ":" .. tostring(ah) .. ":" .. tostring(shown) .. ":" .. tostring(perRow) .. ":" .. side .. ":" .. tostring(offsetX) .. ":" .. tostring(offsetY) .. ":" .. tostring(pad) .. ":" .. tostring(i)
            if icon._layKey ~= layKey or not icon:IsShown() then
                local idx0 = i - 1
                local col = idx0 - math.floor(idx0 / perRow) * perRow
                local row = math.floor(idx0 / perRow)
                local rowStart = row * perRow
                local rowCount = shown - rowStart
                if rowCount > perRow then rowCount = perRow end
                icon:SetWidth(aw)
                icon:SetHeight(ah)
                if icon.tex then
                    IchaUI_PinAuraTex(icon)
                end
                if icon.border then
                    icon.border:Hide()
                end
                if icon.ring then
                    icon.ring:SetAlpha(0)
                    icon.ring:Hide()
                end
                icon:ClearAllPoints()
                -- Inside the frame along the chosen edge; rows grow inward
                if side == "TOP" or side == "TOPLEFT" then
                    local rowW = rowCount * aw + (rowCount - 1) * gap
                    local x0 = edge
                    if side == "TOP" then
                        x0 = ((anchor:GetWidth() or 0) - rowW) / 2
                    end
                    local x = x0 + col * (aw + gap) + offsetX
                    local y = -edge - row * (ah + gap) + offsetY
                    icon:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y)
                elseif side == "TOPRIGHT" then
                    local x = -edge - col * (aw + gap) + offsetX
                    local y = -edge - row * (ah + gap) + offsetY
                    icon:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", x, y)
                elseif side == "BOTTOM" or side == "BOTTOMLEFT" then
                    local rowW = rowCount * aw + (rowCount - 1) * gap
                    local x0 = edge
                    if side == "BOTTOM" then
                        x0 = ((anchor:GetWidth() or 0) - rowW) / 2
                    end
                    local x = x0 + col * (aw + gap) + offsetX
                    local y = edge + row * (ah + gap) + offsetY
                    icon:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", x, y)
                elseif side == "BOTTOMRIGHT" then
                    local x = -edge - col * (aw + gap) + offsetX
                    local y = edge + row * (ah + gap) + offsetY
                    icon:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", x, y)
                elseif side == "LEFT" then
                    local x = edge + row * (aw + gap) + offsetX
                    local y = -edge - col * (ah + gap) + offsetY
                    icon:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y)
                else
                    -- RIGHT
                    local x = -edge - row * (aw + gap) + offsetX
                    local y = -edge - col * (ah + gap) + offsetY
                    icon:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", x, y)
                end
                icon:Show()
                icon:SetFrameLevel((anchor:GetFrameLevel() or 1) + 8)
                icon._layKey = layKey
            end
        else
            if icon:IsShown() then icon:Hide() end
            icon._layKey = nil
            icon._auraTex = nil
            icon._auraKind = nil
            icon._auraCount = nil
            if icon.count then
                icon.count:SetText("")
                icon.count:Hide()
            end
            icon._auraCol = nil
            icon.expires = nil
        end
    end
end

local function layoutAuraGrid(icons, shown, perRow, aw, ah, anchor, above, yExtra, pad, offsetX, offsetY, anchorPoint)
    -- Optional offsetX/Y + anchorPoint (TOP/BOTTOM/LEFT/RIGHT + corners). Omitted => legacy above/below.
    shown = tonumber(shown) or 0
    perRow = tonumber(perRow) or 8
    aw = tonumber(aw) or AURA_W
    ah = tonumber(ah) or AURA_H
    if perRow < 1 then perRow = 1 end
    yExtra = tonumber(yExtra) or 0
    pad = tonumber(pad)
    if pad == nil then pad = AURA_PAD end
    if pad < 0 then pad = 0 end
    if pad > 12 then pad = 12 end
    offsetX = tonumber(offsetX) or 0
    offsetY = tonumber(offsetY) or 0
    local side = anchorPoint
    if not side or side == "" then
        if above then side = "TOP" else side = "BOTTOM" end
    end
    side = IchaUI_ValidAuraAnchor(side)
    local edge = math.floor(aw * 0.42 + 0.5)
    if edge < 8 then edge = 8 end
    if edge > 16 then edge = 16 end
    local outset = math.floor(aw * 0.08 + 0.5)
    if outset < 2 then outset = 2 end
    local i
    for i = 1, MAX_AURA_SLOTS do
        local icon = icons[i]
        if i <= shown then
            local layKey = tostring(aw) .. ":" .. tostring(ah) .. ":" .. tostring(shown) .. ":" .. tostring(perRow) .. ":" .. side .. ":" .. tostring(offsetX) .. ":" .. tostring(offsetY) .. ":" .. tostring(yExtra) .. ":" .. tostring(pad) .. ":" .. tostring(i)
            if icon._layKey ~= layKey or not icon:IsShown() then
                local idx = i - 1
                local col = idx - math.floor(idx / perRow) * perRow
                local row = math.floor(idx / perRow)
                icon:SetWidth(aw)
                icon:SetHeight(ah)
                if icon.tex then
                    IchaUI_PinAuraTex(icon)
                end
                if icon.ring then
                    icon.ring:SetAlpha(0)
                    icon.ring:Hide()
                end
                if icon.border then
                    applyAuraGold(icon.border, edge, outset)
                end
                icon:ClearAllPoints()
                -- Match UF content pad (bars sit at +3) + gold outset so outer edge lines up
                local framePad = 3
                local step = framePad + outset + col * (aw + pad)
                if side == "TOP" or side == "TOPLEFT" then
                    local y = outset + row * (ah + pad) + offsetY
                    icon:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", step + offsetX, y)
                elseif side == "TOPRIGHT" then
                    local y = outset + row * (ah + pad) + offsetY
                    icon:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", -step + offsetX, y)
                elseif side == "BOTTOM" or side == "BOTTOMLEFT" then
                    local y = -outset - yExtra - row * (ah + pad) + offsetY
                    icon:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", step + offsetX, y)
                elseif side == "BOTTOMRIGHT" then
                    local y = -outset - yExtra - row * (ah + pad) + offsetY
                    icon:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", -step + offsetX, y)
                elseif side == "LEFT" then
                    local y = -framePad - outset - col * (ah + pad) + offsetY
                    local x = -outset - row * (aw + pad) + offsetX
                    icon:SetPoint("TOPRIGHT", anchor, "TOPLEFT", x, y)
                else
                    -- RIGHT
                    local y = -framePad - outset - col * (ah + pad) + offsetY
                    local x = outset + row * (aw + pad) + offsetX
                    icon:SetPoint("TOPLEFT", anchor, "TOPRIGHT", x, y)
                end
                icon:Show()
                icon._layKey = layKey
            end
        else
            if icon:IsShown() then icon:Hide() end
            icon._layKey = nil
            icon._auraTex = nil
            icon._auraKind = nil
            icon._auraCount = nil
            if icon.count then
                icon.count:SetText("")
                icon.count:Hide()
            end
            icon._auraCol = nil
            icon.expires = nil
        end
    end
end


-- Party: buffs LEFT + debuffs RIGHT on TOP, rows grow UPWARD; shared row capacity = perRow
local function layoutAuraSplitTop(buffs, bShown, debuffs, dShown, perRow, aw, ah, anchor, maxSlots, buffPad, debuffPad, buffOx, buffOy, debuffOx, debuffOy, daw, dah, buffPer, debuffPer)
    bShown = tonumber(bShown) or 0
    dShown = tonumber(dShown) or 0
    perRow = tonumber(perRow) or 8
    aw = tonumber(aw) or AURA_W
    ah = tonumber(ah) or AURA_H
    if perRow < 1 then perRow = 1 end
    maxSlots = tonumber(maxSlots) or (perRow * 2)
    buffPad = tonumber(buffPad)
    if buffPad == nil then buffPad = AURA_PAD end
    if buffPad < 0 then buffPad = 0 end
    if buffPad > 12 then buffPad = 12 end
    debuffPad = tonumber(debuffPad)
    if debuffPad == nil then debuffPad = AURA_PAD end
    if debuffPad < 0 then debuffPad = 0 end
    if debuffPad > 12 then debuffPad = 12 end
    buffOx = tonumber(buffOx) or 0
    buffOy = tonumber(buffOy) or 0
    debuffOx = tonumber(debuffOx) or 0
    debuffOy = tonumber(debuffOy) or 0
    daw = tonumber(daw) or aw
    dah = tonumber(dah) or ah
    local rowPad = buffPad
    if debuffPad > rowPad then rowPad = debuffPad end
    if maxSlots < 1 then maxSlots = perRow end
    local maxRows = math.floor(maxSlots / perRow)
    if maxRows < 1 then maxRows = 1 end
    if buffPer or debuffPer then
        local br = tonumber(buffPer) or math.floor(perRow / 2)
        local dr = tonumber(debuffPer) or (perRow - (tonumber(buffPer) or math.floor(perRow / 2)))
        if br < 1 then br = 1 end
        if dr < 1 then dr = 1 end
        local needB = 0
        local needD = 0
        if bShown > 0 then needB = math.floor((bShown + br - 1) / br) end
        if dShown > 0 then needD = math.floor((dShown + dr - 1) / dr) end
        local need = needB
        if needD > need then need = needD end
        if need > maxRows then maxRows = need end
        if maxRows > 8 then maxRows = 8 end
    end
    local edge = math.floor(aw * 0.42 + 0.5)
    if edge < 8 then edge = 8 end
    if edge > 16 then edge = 16 end
    local outset = math.floor(aw * 0.08 + 0.5)
    if outset < 2 then outset = 2 end
    local framePad = 3

    local function styleIcon(icon, iw, ih)
        if not icon then return end
        iw = tonumber(iw) or aw
        ih = tonumber(ih) or ah
        icon:SetWidth(iw)
        icon:SetHeight(ih)
        if icon.tex then
            IchaUI_PinAuraTex(icon)
        end
        if icon.ring then
            icon.ring:SetAlpha(0)
            icon.ring:Hide()
        end
        if icon.border then
            applyAuraGold(icon.border, edge, outset)
        end
    end

    local function takeForRow(remB, remD)
        if remB <= 0 and remD <= 0 then return 0, 0 end
        if buffPer or debuffPer then
            local bCap = tonumber(buffPer) or math.floor(perRow / 2)
            local dCap = tonumber(debuffPer) or (perRow - bCap)
            if bCap < 1 then bCap = 1 end
            if dCap < 1 then dCap = 1 end
            local bTake = remB
            if bTake > bCap then bTake = bCap end
            local dTake = remD
            if dTake > dCap then dTake = dCap end
            return bTake, dTake
        end
        if remB + remD <= perRow then
            return remB, remD
        end
        local bTake = math.floor(perRow / 2)
        local dTake = perRow - bTake
        if remB < bTake then
            bTake = remB
            dTake = remD
            if dTake > (perRow - bTake) then dTake = perRow - bTake end
        elseif remD < dTake then
            dTake = remD
            bTake = remB
            if bTake > (perRow - dTake) then bTake = perRow - dTake end
        else
            if bTake > remB then bTake = remB end
            if dTake > remD then dTake = remD end
        end
        return bTake, dTake
    end

    local bi, di = 1, 1
    local row = 0
    local placed = 0
    while row < maxRows and (bi <= bShown or di <= dShown) and placed < maxSlots do
        local remB = bShown - bi + 1
        if remB < 0 then remB = 0 end
        local remD = dShown - di + 1
        if remD < 0 then remD = 0 end
        local bTake, dTake = takeForRow(remB, remD)
        if bTake <= 0 and dTake <= 0 then break end
        -- Cap to remaining slots budget
        if placed + bTake + dTake > maxSlots then
            local room = maxSlots - placed
            if room <= 0 then break end
            if bTake + dTake > room then
                local nb, nd = takeForRow(math.min(remB, room), math.min(remD, room))
                -- if takeForRow still too big, shrink
                if nb + nd > room then
                    nb = math.floor(room / 2)
                    nd = room - nb
                    if nb > remB then nb = remB; nd = room - nb end
                    if nd > remD then nd = remD; nb = room - nd end
                    if nb < 0 then nb = 0 end
                    if nd < 0 then nd = 0 end
                end
                bTake, dTake = nb, nd
            end
        end
        local y = outset + row * (ah + rowPad)
        local c
        for c = 0, bTake - 1 do
            local icon = buffs and buffs[bi]
            if icon then
                local x = framePad + outset + c * (aw + buffPad)
                local layKey = "b:" .. tostring(aw) .. ":" .. tostring(ah) .. ":" .. tostring(x + buffOx) .. ":" .. tostring(y + buffOy) .. ":" .. tostring(bShown) .. ":" .. tostring(dShown)
                if icon._layKey ~= layKey or not icon:IsShown() then
                    styleIcon(icon, aw, ah)
                    icon:ClearAllPoints()
                    icon:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", x + buffOx, y + buffOy)
                    icon:Show()
                    icon._layKey = layKey
                end
            end
            bi = bi + 1
            placed = placed + 1
        end
        for c = 0, dTake - 1 do
            local icon = debuffs and debuffs[di]
            if icon then
                local x = framePad + outset + c * (aw + debuffPad)
                local layKey = "d:" .. tostring(daw) .. ":" .. tostring(dah) .. ":" .. tostring(-x + debuffOx) .. ":" .. tostring(y + debuffOy) .. ":" .. tostring(bShown) .. ":" .. tostring(dShown)
                if icon._layKey ~= layKey or not icon:IsShown() then
                    styleIcon(icon, daw, dah)
                    icon:ClearAllPoints()
                    icon:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", -x + debuffOx, y + debuffOy)
                    icon:Show()
                    icon._layKey = layKey
                end
            end
            di = di + 1
            placed = placed + 1
        end
        row = row + 1
    end
    local hi
    for hi = bi, MAX_AURA_SLOTS do
        local icon = buffs and buffs[hi]
        if icon then
            if icon:IsShown() then icon:Hide() end
            icon._layKey = nil
            icon._auraTex = nil
            icon._auraKind = nil
            icon._auraCount = nil
            if icon.count then
                icon.count:SetText("")
                icon.count:Hide()
            end
            icon._auraCol = nil
            icon.expires = nil
        end
    end
    for hi = di, MAX_AURA_SLOTS do
        local icon = debuffs and debuffs[hi]
        if icon then
            if icon:IsShown() then icon:Hide() end
            icon._layKey = nil
            icon._auraTex = nil
            icon._auraKind = nil
            icon._auraCount = nil
            if icon.count then
                icon.count:SetText("")
                icon.count:Hide()
            end
            icon._auraCol = nil
            icon.expires = nil
        end
    end
end

-- SuperWoW UNIT_CASTEVENT + combat-log fallback → cast bars for target/ToT/party
-- Keys: caster GUID (preferred) and unit name (combat log / GUID-less clients)
local swCastByGuid = {}
local swCastByName = {}

function swCastNormalizeName(name)
    if not name or name == "" then return nil end
    return string.lower(tostring(name))
end

function swCastClear(key)
    if not key then return end
    local k = tostring(key)
    swCastByGuid[k] = nil
    local info = swCastByName[swCastNormalizeName(k)]
    if info then swCastByName[swCastNormalizeName(k)] = nil end
end

function swCastClearInfo(info)
    if not info then return end
    if info.guid then swCastByGuid[tostring(info.guid)] = nil end
    if info.nameKey then swCastByName[info.nameKey] = nil end
end

function swCastSpellMeta(spellID, spellNameHint)
    local name = spellNameHint or spellNameFromId(spellID)
    local texture = nil
    local castMs = nil
    if spellID and type(SpellInfo) == "function" then
        -- SuperWoW SpellInfo: name, rank, icon, castTime
        local ok, n, _, icon, ct = pcall(SpellInfo, spellID)
        if ok then
            if type(n) == "string" and n ~= "" then name = n end
            if type(icon) == "string" and icon ~= "" then
                if string.find(icon, "Interface") then
                    texture = icon
                else
                    texture = "Interface\\Icons\\" .. icon
                end
            end
            ct = tonumber(ct)
            if ct and ct > 0 then
                castMs = ct
                if castMs < 50 then castMs = castMs * 1000 end
            end
        end
    end
    if (not texture or texture == "") and spellID and GetSpellTexture then
        local ok, t = pcall(GetSpellTexture, spellID)
        if ok then texture = t end
    end
    if (not texture or texture == "") and spellID and GetSpellInfo then
        local ok, _, _, tex = pcall(GetSpellInfo, spellID)
        if ok and type(tex) == "string" then texture = tex end
    end
    if not name or name == "" then name = "Casting" end
    return name, texture, castMs
end

function swCastStore(guid, unitName, spellID, spellNameHint, durMs, channel)
    local nowMs = (GetTime and GetTime() or 0) * 1000
    local name, texture, spellCastMs = swCastSpellMeta(spellID, spellNameHint)
    local dur = tonumber(durMs) or spellCastMs
    if not dur or dur <= 0 then dur = 3000 end
    if dur < 50 then dur = dur * 1000 end
    if dur > 600000 then dur = 600000 end
    local info = {
        name = name,
        texture = texture,
        start = nowMs,
        finish = nowMs + dur,
        channel = channel and true or false,
        spellId = spellID,
        locked = false,
        delay = 0,
        guid = guid and tostring(guid) or nil,
        nameKey = swCastNormalizeName(unitName),
    }
    if info.guid then swCastByGuid[info.guid] = info end
    if info.nameKey then swCastByName[info.nameKey] = info end
    return info
end

function swCastRemember(caster, castEvent, spellID, durMs)
    if not caster then return end
    local et = castEvent and string.upper(tostring(castEvent)) or ""
    if et == "MAINHAND" or et == "OFFHAND" or et == "EXTRA" then return end
    local guid = tostring(caster)
    if et == "FAIL" or et == "FAILED" or et == "INTERRUPTED" then
        local info = swCastByGuid[guid]
        swCastClearInfo(info)
        swCastByGuid[guid] = nil
        return
    end
    if et == "CAST" then
        -- Successful finish: snap end to now. Channel CAST is a tick — do not end.
        local info = swCastByGuid[guid]
        if info and info.channel then
            return
        end
        local nowMs = (GetTime and GetTime() or 0) * 1000
        if info then
            info.finish = nowMs
            info.succeeded = true
            if IchaUI_Cast_MarkDone then
                IchaUI_Cast_MarkDone(guid, info.spellId or spellID, info.start)
            end
        elseif IchaUI_Cast_MarkDone then
            IchaUI_Cast_MarkDone(guid, spellID, nil)
        end
        -- Hide now. A later OnUpdate with leftover CastingInfo must not rewind.
        if IchaUI_Cast_QuenchUnit then IchaUI_Cast_QuenchUnit(guid) end
        return
    end
    if et == "DELAY" or et == "DELAYED" then
        local info = swCastByGuid[guid]
        if info and not info.channel then
            local extra = tonumber(durMs) or 0
            if extra > 0 and extra < 50 then extra = extra * 1000 end
            if extra > 0 then
                info.delay = (tonumber(info.delay) or 0) + extra
                info.finish = (tonumber(info.finish) or 0) + extra
            end
        end
        return
    end
    if et ~= "START" and et ~= "CHANNEL" then return end
    if IchaUI_Cast_LateStart and IchaUI_Cast_LateStart(guid, spellID) then
        return
    end
    local nowMs = (GetTime and GetTime() or 0) * 1000
    local existing = swCastByGuid[guid]
    -- Channel ticks must not reset the bar to full unless the duration grew (refresh).
    if et == "CHANNEL" and existing and existing.channel and not existing.succeeded then
        local same = true
        if spellID and existing.spellId and tonumber(spellID) ~= tonumber(existing.spellId) then
            same = false
        end
        if same and (tonumber(existing.finish) or 0) > nowMs + 50 then
            local extra = tonumber(durMs) or 0
            if extra > 0 and extra < 50 then extra = extra * 1000 end
            if extra > 0 then
                local newFin = nowMs + extra
                if newFin > (tonumber(existing.finish) or 0) + 250 then
                    existing.start = nowMs
                    existing.finish = newFin
                end
            end
            return
        end
    end
    -- Prefer a readable name if SuperWoW can resolve the GUID as a unit
    local uname = nil
    if type(UnitName) == "function" then
        local ok, n = pcall(UnitName, guid)
        if ok and type(n) == "string" and n ~= "" then uname = n end
    end
    swCastStore(guid, uname, spellID, nil, durMs, et == "CHANNEL")
    if IchaUI_Cast_Done then IchaUI_Cast_Done[guid] = nil end
end

function swCastFresh(info, keyGuid, keyName)
    if not info then return nil end
    local nowMs = (GetTime and GetTime() or 0) * 1000
    if (tonumber(info.finish) or 0) <= nowMs then
        swCastClearInfo(info)
        if keyGuid then swCastByGuid[tostring(keyGuid)] = nil end
        if keyName then swCastByName[swCastNormalizeName(keyName)] = nil end
        return nil
    end
    return info
end

function getSwCastInfo(unit)
    if not unit then return nil end
    -- 1) Direct GUID from SuperWoW UnitExists / UnitGUID
    local g = IchaUI_Swing_Guid(unit)
    if g then
        local info = swCastFresh(swCastByGuid[g], g, nil)
        if info then return info end
    end
    -- 2) SuperWoW: GUIDs are valid unit tokens — scan cache with UnitIsUnit
    if type(UnitIsUnit) == "function" then
        local guid, info
        for guid, info in pairs(swCastByGuid) do
            local ok, same = pcall(UnitIsUnit, unit, guid)
            if ok and same then
                info = swCastFresh(info, guid, nil)
                if info then return info end
            end
        end
    end
    -- 3) Name fallback (combat log / identical-name edge cases)
    if type(UnitName) == "function" then
        local ok, n = pcall(UnitName, unit)
        if ok and n and n ~= "" then
            local nk = swCastNormalizeName(n)
            local info = swCastFresh(swCastByName[nk], nil, n)
            if info then return info end
        end
    end
    return nil
end

-- Combat-log cast starts when SuperWoW events are missing (vanilla / no GUID)
function swCastFromCombatLog(msg)
    if not msg or msg == "" then return end
    local mob, spell
    local function tryGlob(glob)
        if not glob then return nil, nil end
        local pat = tostring(glob)
        -- "%s begins to cast %s." → captures (escape magic chars except %s/%d)
        pat = string.gsub(pat, "([%(%)%.%+%*%?%[%]%^%$])", "%%%1")
        pat = string.gsub(pat, "%%s", "(.+)")
        pat = string.gsub(pat, "%%d", "(%%d+)")
        local _, _, a, b = string.find(msg, "^" .. pat .. "$")
        return a, b
    end
    mob, spell = tryGlob(SPELLCASTOTHERSTART)
    if not mob then mob, spell = tryGlob(SPELLPERFORMOTHERSTART) end
    if not mob then
        local _, _, m, s = string.find(msg, "^(.+) begins to cast (.+)%.$")
        if m and s then mob, spell = m, s end
    end
    if not mob then
        local _, _, m, s = string.find(msg, "^(.+) begins to perform (.+)%.$")
        if m and s then mob, spell = m, s end
    end
    if not mob or not spell then return end
    swCastStore(nil, mob, nil, spell, 3000, false)
end

function swCastInterruptFromCombatLog(msg)
    if not msg or msg == "" then return end
    local mob
    local _, _, m = string.find(msg, "^You interrupt (.+)'s ")
    if m then
        mob = m
    else
        _, _, m = string.find(msg, " interrupts (.+)'s ")
        if m then mob = m end
    end
    if not mob then return end
    local nk = swCastNormalizeName(mob)
    local info = swCastByName[nk]
    if info then swCastClearInfo(info) end
end

-- Cast / channel info — ClassicAPI first (RavenCraft remote casts), then SuperWoW cache.
function normalizeCastTimes(startTime, endTime)
    startTime = tonumber(startTime) or 0
    endTime = tonumber(endTime) or 0
    if endTime <= startTime then return 0, 0 end
    -- GetTime()-seconds mistaken for ms: duration under ~50s as a raw delta
    local dur = endTime - startTime
    if dur > 0 and dur < 50 then
        startTime = startTime * 1000
        endTime = endTime * 1000
    end
    return startTime, endTime
end

function castInfoFromParts(name, texture, startTime, endTime, channel, spellId, locked, delayMs)
    if not name or name == "" then return nil end
    startTime, endTime = normalizeCastTimes(startTime, endTime)
    if endTime <= startTime then return nil end
    if type(texture) == "number" and GetSpellTexture and spellId then
        local ok, t = pcall(GetSpellTexture, spellId)
        if ok then texture = t end
    end
    if type(texture) ~= "string" or texture == "" then
        texture = nil
        if spellId and GetSpellTexture then
            local ok, t = pcall(GetSpellTexture, spellId)
            if ok then texture = t end
        end
    end
    delayMs = tonumber(delayMs) or 0
    if delayMs < 0 then delayMs = 0 end
    if delayMs > 0 and delayMs < 50 then delayMs = delayMs * 1000 end
    return {
        name = name,
        texture = texture,
        start = startTime,
        finish = endTime,
        channel = channel and true or false,
        spellId = spellId,
        locked = locked and true or false,
        delay = delayMs,
    }
end

-- ClassicAPI 11-tuple: name, displayName, texture, startMs, endMs, isTradeSkill,
-- castID, notInterruptible, spellId, castBarID, delayMs.
-- Call via pcall so a bad unit token cannot throw; pcall only needs the info table.
function IchaUI_Cast_FromClassic(unit, channel)
    if not unit or not C_Spell then return nil end
    local r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11
    if channel then
        if type(C_Spell.UnitChannelInfo) ~= "function" then return nil end
        r1, r2, r3, r4, r5, r6, r7, r8 = C_Spell.UnitChannelInfo(unit)
        return castInfoFromParts(r1, r3, r4, r5, true, r8, r7, nil)
    end
    if type(C_Spell.UnitCastingInfo) ~= "function" then return nil end
    r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11 = C_Spell.UnitCastingInfo(unit)
    return castInfoFromParts(r1, r3, r4, r5, false, r9, r8, r11)
end

local function getCastInfo(unit)
    if not unit then return nil end

    -- 1) ClassicAPI C_Spell — authoritative for target/ToT/party on RavenCraft
    -- Shape: name, displayName, texture, startMs, endMs, isTradeSkill,
    --        castID, notInterruptible, spellId [, castBarID, delayMs]
    if C_Spell and type(C_Spell) == "table" then
        local ok, info = pcall(IchaUI_Cast_FromClassic, unit, false)
        if ok and info then return IchaUI_Cast_FilterInfo(unit, info) end
        ok, info = pcall(IchaUI_Cast_FromClassic, unit, true)
        if ok and info then return IchaUI_Cast_FilterInfo(unit, info) end
    end

    -- 2) Client-provided global UnitCastingInfo / UnitChannelInfo, if any
    if type(UnitCastingInfo) == "function" then
        local ok, r1, r2, r3, r4, r5, r6 = pcall(UnitCastingInfo, unit)
        if ok and r1 then
            local texture, startMs, endMs = r4, r5, r6
            -- name, rank, texture, start, end  (texture in slot 3)
            if type(r3) == "string" and (string.find(r3, "Interface") or string.find(r3, "Icons")) then
                texture, startMs, endMs = r3, r4, r5
            end
            local info = castInfoFromParts(r1, texture, startMs, endMs, false, nil, false)
            if info then return IchaUI_Cast_FilterInfo(unit, info) end
        end
    end
    if type(UnitChannelInfo) == "function" then
        local ok, r1, r2, r3, r4, r5, r6 = pcall(UnitChannelInfo, unit)
        if ok and r1 then
            local texture, startMs, endMs = r4, r5, r6
            if type(r3) == "string" and (string.find(r3, "Interface") or string.find(r3, "Icons")) then
                texture, startMs, endMs = r3, r4, r5
            end
            local info = castInfoFromParts(r1, texture, startMs, endMs, true, nil, false)
            if info then return IchaUI_Cast_FilterInfo(unit, info) end
        end
    end

    -- 3) SuperWoW / combat-log cache
    return IchaUI_Cast_FilterInfo(unit, getSwCastInfo(unit))
end

local function getCastLatencyMs()
    -- 1.12: down, up, lag. SuperWoW / later may add lagWorld as a 4th return.
    -- Lua 0 is truthy, so "world or home" must not prefer a 0 world ping.
    local home, world = 0, 0
    if type(GetNetStats) == "function" then
        local _, _, lagHome, lagWorld = GetNetStats()
        home = tonumber(lagHome) or 0
        world = tonumber(lagWorld) or 0
    end
    if home < 0 then home = 0 end
    if world < 0 then world = 0 end
    local lag = home
    if world > lag then lag = world end
    if lag < 1 then lag = 100 end
    if lag > 1000 then lag = 1000 end
    return lag
end

-- One cast UI per person, except self-target / self-ToT also mirror the player cast.
local function castOwnedByThisFrame(key, unit)
    if not unit or unit == "" or unit == "none" then return false end
    if string.sub(unit, 1, 6) == "IchaUI" then return false end
    if not UnitExists then return false end
    local ok, exists = pcall(UnitExists, unit)
    if not ok or not exists then return false end
    if key and string.find(tostring(key), "^combat") then
        return true
    end
    local isPlayer = UnitIsUnit and UnitIsUnit(unit, "player")
    if isPlayer then
        if key == "player" then return true end
        -- Targeting yourself: show the same cast on the target frame
        if key == "target" then return true end
        -- You are the ToT: mirror on ToT as well
        if key == "tot" then return true end
        return false
    end
    if UnitExists("target") and UnitIsUnit and UnitIsUnit(unit, "target") then
        return key == "target" or key == "focus"
    end
    return true
end


-- Dispellable debuff tint: same StatusBar look as heal pred, 50% alpha,
-- full HP bar, above fill / below name+HP text. Color by type.
local function setDispelGlow(fr, r, g, b, a)
    if not fr then return end
    local t = fr.dispelTint
    -- Offline party/raid stays grey; aura tint must not restore class color.
    if fr.unit and UnitIsConnected and (isPartyUnit(fr.unit) or isRaidUnit(fr.unit))
        and fr.unit ~= "" and fr.unit ~= "none" and not UnitIsConnected(fr.unit) then
        fr._dispelHP = nil
        if fr.hp then fr.hp:SetVertexColor(0.45, 0.45, 0.45) end
        if fr.mp then fr.mp:SetVertexColor(0.45, 0.45, 0.45) end
        if t then
            t:SetAlpha(0)
            t:Hide()
        end
        return
    end
    if not a or a <= 0 then
        fr._dispelHP = nil
        if t then
            t:SetAlpha(0)
            t:Hide()
        end
        -- Restore class color on next update; apply immediately if we can
        if fr.hp and fr.unit and classColor then
            local cr, cg, cb = classColor(fr.unit)
            fr.hp:SetVertexColor(cr, cg, cb)
        end
        return
    end
    -- Recolor the HP fill itself (overlay alone looks grey/weak on blue bars)
    fr._dispelHP = { r, g, b }
    if fr.hp then
        fr.hp:SetVertexColor(r, g, b)
    end
    -- Light StatusBar wash on top (heal-pred style), normal blend ~40%
    if t then
        t:SetTexture("Interface/TargetingFrame/UI-StatusBar")
        t:SetBlendMode("BLEND")
        t:SetVertexColor(r, g, b)
        t:SetAlpha(0.4)
        t:Show()
    end
end

local function clearDispelGlow(fr)
    setDispelGlow(fr, 0, 0, 0, 0)
end

-- Unit right-click menu (Vanilla UnitPopup) + IchaUI chrome while ours is open
local unitMenu
local unitMenuUnit = "player"
local unitMenuCreateHooked = false

local function unitMenuWhich(unit)
    if badUnitToken(unit) or not UnitExists or not UnitExists(unit) then
        return nil, nil
    end
    if UnitIsUnit(unit, "player") then
        return "SELF", nil
    end
    if UnitIsUnit(unit, "pet") then
        return "PET", nil
    end
    if UnitIsPlayer(unit) then
        if UnitInParty(unit) then
            return "PARTY", nil
        end
        if UnitInRaid and UnitInRaid(unit) then
            return "RAID_PLAYER", nil
        end
        return "PLAYER", nil
    end
    return "RAID_TARGET_ICON", RAID_TARGET_ICON
end

local function skinOurDropLists()
    local openName = UIDROPDOWNMENU_OPEN_MENU
    local menuFrame = nil
    if type(openName) == "string" then
        menuFrame = getglobal(openName)
    elseif type(openName) == "table" then
        menuFrame = openName
        if menuFrame.GetName then
            openName = menuFrame:GetName()
        else
            openName = nil
        end
    end
    local isOurs = (openName == "IchaUIUF_DropDown")

    local menuUnit = unitMenuUnit
    local menuName = nil
    if menuFrame then
        if menuFrame.unit and not badUnitToken(menuFrame.unit) then
            menuUnit = menuFrame.unit
        end
        menuName = menuFrame.name
    end
    local unitNm = nil
    if menuUnit then
        unitNm = unitName(menuUnit)
        if unitNm == "" then unitNm = nil end
    end

    local function rgbForPlayerName(want)
        if not want or want == "" then return nil end
        local foundR, foundG, foundB
        local function tryUnit(u)
            if foundR or not u or badUnitToken(u) then return end
            local hit = false
            pcall(function()
                if UnitExists(u) and UnitIsPlayer(u) then
                    local n = UnitName(u)
                    if n == want then hit = true end
                end
            end)
            if hit then
                foundR, foundG, foundB = classColor(u)
            end
        end
        tryUnit(menuUnit)
        tryUnit("player")
        tryUnit("target")
        tryUnit("mouseover")
        tryUnit("targettarget")
        tryUnit("pettarget")
        local ui
        for ui = 1, 4 do
            tryUnit("party" .. ui)
        end
        for ui = 1, 40 do
            tryUnit("raid" .. ui)
        end
        if foundR then return foundR, foundG, foundB end
        if GetNumRaidMembers and GetRaidRosterInfo then
            local n = GetNumRaidMembers() or 0
            for ui = 1, n do
                local rn, rank, subgroup, level, class, fileName = GetRaidRosterInfo(ui)
                if rn == want and fileName and RAID_CLASS_COLORS and RAID_CLASS_COLORS[fileName] then
                    local c = RAID_CLASS_COLORS[fileName]
                    return c.r, c.g, c.b
                end
            end
        end
        local CLASS_FILE = {
            Warrior = "WARRIOR", Paladin = "PALADIN", Hunter = "HUNTER",
            Rogue = "ROGUE", Priest = "PRIEST", Shaman = "SHAMAN",
            Mage = "MAGE", Warlock = "WARLOCK", Druid = "DRUID",
        }
        if GetNumFriends and GetFriendInfo then
            local n = GetNumFriends() or 0
            for ui = 1, n do
                local fn, _, fclass = GetFriendInfo(ui)
                if fn == want and fclass then
                    local file = CLASS_FILE[fclass] or string.upper(fclass)
                    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
                    if c then return c.r, c.g, c.b end
                end
            end
        end
        return nil
    end

    local function paintName(btn, nt, txt, isTitle)
        if not nt or not txt or txt == "" then return false end
        txt = string.gsub(txt, "|c%x%x%x%x%x%x%x%x", "")
        txt = string.gsub(txt, "|r", "")
        local isNameBtn = false
        if unitNm and txt == unitNm then isNameBtn = true end
        if menuName and txt == menuName then isNameBtn = true end
        if isTitle then isNameBtn = true end
        if not isNameBtn and UnitPopupButtons then
            local stock = false
            local k, v
            for k, v in pairs(UnitPopupButtons) do
                if type(v) == "table" and v.text == txt then
                    stock = true
                    break
                end
            end
            if not stock then
                isNameBtn = true
            end
        end
        if not isNameBtn then return false end
        local r, g, b = rgbForPlayerName(txt)
        if not r and menuUnit and ((unitNm and txt == unitNm) or (menuName and txt == menuName) or isTitle) then
            local isPl = false
            pcall(function()
                if UnitExists(menuUnit) and UnitIsPlayer(menuUnit) then
                    isPl = true
                end
            end)
            if isPl then
                r, g, b = classColor(menuUnit)
            end
        end
        if not r then return false end
        nt:SetTextColor(r, g, b)
        if btn.SetDisabledTextColor then
            btn:SetDisabledTextColor(r, g, b)
        end
        return true
    end

    local li
    for li = 1, 3 do
        local list = getglobal("DropDownList" .. li)
        if list and list:IsShown() then
            if isOurs then
                list:SetBackdrop({
                    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 14,
                    insets = { left = 3, right = 3, top = 3, bottom = 3 },
                })
                list:SetBackdropColor(0.04, 0.04, 0.05, 0.97)
                IchaUI_PaintGoldBorder(list, GOLD[4] or 1)
            end
            local maxB = UIDROPDOWNMENU_MAXBUTTONS or 32
            local bi
            for bi = 1, maxB do
                local btn = getglobal(list:GetName() .. "Button" .. bi)
                if not btn then break end
                if btn:IsShown() then
                    local nt = getglobal(btn:GetName() .. "NormalText")
                    local txt = nil
                    if btn.GetText then txt = btn:GetText() end
                    if (not txt or txt == "") and nt and nt.GetText then
                        txt = nt:GetText()
                    end
                    local enabled = 1
                    if btn.IsEnabled then
                        enabled = btn:IsEnabled()
                    end
                    local isTitle = (enabled == 0 or enabled == false)
                    if isOurs then
                        if nt then
                            nt:SetTextColor(0.92, 0.88, 0.75)
                        end
                        local hl = getglobal(btn:GetName() .. "Highlight")
                        if hl then
                            IchaUI_PaintGoldVertex(hl, 0.78, 0.58, 0.16, 1)
                        end
                        local check = getglobal(btn:GetName() .. "Check")
                        if check and check.SetVertexColor then
                            IchaUI_PaintGoldVertex(check, 0.78, 0.58, 0.16, 1)
                        end
                    end
                    paintName(btn, nt, txt, isTitle and bi == 1)
                end
            end
        end
    end
end

local function hookDropListSkin(list)
    if not list or list._ichaUFSkinHook then return end
    list._ichaUFSkinHook = true
    local prev = list:GetScript("OnShow")
    list:SetScript("OnShow", function()
        if prev then prev() end
        skinOurDropLists()
    end)
end

local function ensureUnitMenu()
    if unitMenu then return unitMenu end
    unitMenu = CreateFrame("Frame", "IchaUIUF_DropDown", UIParent, "UIDropDownMenuTemplate")

    local CELL = 28
    local GAP = 4
    local INSET = 8

    local function hideMarkGrid()
        local g = getglobal("IchaUIUF_MarkGrid")
        if g then g:Hide() end
        local c = getglobal("IchaUIUF_MarkGridCatch")
        if c then c:Hide() end
    end
    local function currentMark(u)
        local idx = 0
        pcall(function()
            if GetRaidTargetIndex then
                local v = GetRaidTargetIndex(u)
                if type(v) == "number" then idx = v end
            end
        end)
        return idx
    end
    local function setMark(u, idx)
        if not SetRaidTarget then return end
        pcall(function() SetRaidTarget(u, idx) end)
    end
    local function refreshMarkGrid()
        local g = getglobal("IchaUIUF_MarkGrid")
        if not g or not g.btns then return end
        local cur = currentMark(unitMenuUnit)
        local mi
        for mi = 1, 8 do
            local b = g.btns[mi]
            if b and b.sel then
                if cur == mi then b.sel:Show() else b.sel:Hide() end
            end
        end
        local clear = g.btns[9]
        if clear and clear.sel then
            if cur == 0 then clear.sel:Show() else clear.sel:Hide() end
        end
    end
    local function makeMarkClick(idx)
        return function()
            setMark(unitMenuUnit, idx)
            hideMarkGrid()
        end
    end
    local function showMarkGrid()
        local g = getglobal("IchaUIUF_MarkGrid")
        local c = getglobal("IchaUIUF_MarkGridCatch")
        if not g or not c then return end
        refreshMarkGrid()
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        if not scale or scale == 0 then scale = 1 end
        x = x / scale
        y = y / scale
        g:ClearAllPoints()
        g:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        c:Show()
        g:Show()
        if g.focusBtn then
            if unitMenu._fromFocus then
                g.focusBtn:SetText("Clear Focus")
            else
                g.focusBtn:SetText("Set Focus")
            end
        end
        if g.Raise then g:Raise() end
    end

    local catch = CreateFrame("Button", "IchaUIUF_MarkGridCatch", UIParent)
    catch:Hide()
    catch:SetAllPoints(UIParent)
    catch:SetFrameStrata("FULLSCREEN_DIALOG")
    catch:SetFrameLevel(1)
    catch:EnableMouse(true)
    catch:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    catch:SetScript("OnClick", hideMarkGrid)

    local grid = CreateFrame("Frame", "IchaUIUF_MarkGrid", UIParent)
    grid:Hide()
    grid:SetFrameStrata("FULLSCREEN_DIALOG")
    grid:SetFrameLevel(20)
    grid:EnableMouse(true)
    local gridW = INSET + INSET + CELL * 3 + GAP * 2
    grid:SetWidth(gridW)
    grid:SetHeight(gridW + 28)
    grid:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    grid:SetBackdropColor(0.04, 0.04, 0.05, 0.97)
    IchaUI_PaintGoldBorder(grid, GOLD[4] or 1)
    grid.btns = {}
    local mi
    for mi = 1, 9 do
        local btn = CreateFrame("Button", "IchaUIUF_MarkGridBtn" .. mi, grid)
        btn:SetWidth(CELL)
        btn:SetHeight(CELL)
        local col = math.mod(mi - 1, 3)
        local row = math.floor((mi - 1) / 3)
        btn:SetPoint("TOPLEFT", grid, "TOPLEFT", INSET + col * (CELL + GAP), -(INSET + row * (CELL + GAP)))
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
        if mi <= 8 then
            icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
            IchaUI_ApplyRaidMarkTexCoord(icon, mi)
            btn:SetScript("OnClick", makeMarkClick(mi))
        else
            icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            btn:SetScript("OnClick", makeMarkClick(0))
        end
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        local hi = btn:GetHighlightTexture()
        if hi and hi.SetBlendMode then hi:SetBlendMode("ADD") end
        local sel = CreateFrame("Frame", nil, btn)
        sel:SetAllPoints(btn)
        applyGold(sel, 8)
        sel:Hide()
        btn.sel = sel
        grid.btns[mi] = btn
    end

    if not grid.focusBtn then
        grid.focusBtn = CreateFrame("Button", "IchaUIUF_MarkGridFocus", grid, "UIPanelButtonTemplate")
        grid.focusBtn:SetWidth(gridW - INSET * 2)
        grid.focusBtn:SetHeight(20)
        grid.focusBtn:SetPoint("BOTTOM", grid, "BOTTOM", 0, 5)
        grid.focusBtn:SetText("Set Focus")
        grid.focusBtn:SetScript("OnClick", function()
            if unitMenu._fromFocus then
                if type(IchaUI_ClearFocus) == "function" then
                    IchaUI_ClearFocus()
                end
            elseif type(IchaUI_SetFocusUnit) == "function" then
                IchaUI_SetFocusUnit(unitMenuUnit)
            end
            hideMarkGrid()
        end)
    end

    unitMenu.ShowMarkGrid = showMarkGrid
    unitMenu.HideMarkGrid = hideMarkGrid

    local function focusBtnLabel(btn)
        if not btn then return nil end
        if btn.value == "ICHA_SET_FOCUS" then return "Set Focus" end
        local txt = nil
        if btn.GetText then txt = btn:GetText() end
        if (not txt or txt == "") and btn.GetName then
            local nt = getglobal(btn:GetName() .. "NormalText")
            if nt and nt.GetText then txt = nt:GetText() end
        end
        if txt == "Clear Focus" then return "Set Focus" end
        return txt
    end
    local function paintDropFocus(btn)
        if not btn then return end
        local label = "Set Focus"
        if unitMenu._fromFocus then label = "Clear Focus" end
        btn.value = "ICHA_SET_FOCUS"
        if btn.SetText then btn:SetText(label) end
        local nt = nil
        if btn.GetName then nt = getglobal(btn:GetName() .. "NormalText") end
        if nt and nt.SetText then nt:SetText(label) end
        btn.func = function()
            if unitMenu._fromFocus then
                if type(IchaUI_ClearFocus) == "function" then
                    IchaUI_ClearFocus()
                end
            elseif type(IchaUI_SetFocusUnit) == "function" then
                IchaUI_SetFocusUnit(unitMenuUnit)
            end
        end
    end
    -- Mouseover re-enters this init without clearing the list, so AddButton
    -- stacked a new Set Focus each time. Keep the first shown one and hide the rest.
    local function pruneSetFocus(list)
        if not list or not list.GetName then return 0 end
        local name = list:GetName()
        local maxB = UIDROPDOWNMENU_MAXBUTTONS or 8
        if maxB < 32 then maxB = 32 end
        local keep = nil
        local i
        for i = 1, maxB do
            local btn = getglobal(name .. "Button" .. i)
            if not btn then break end
            if focusBtnLabel(btn) == "Set Focus" then
                if not keep and btn.IsShown and btn:IsShown() then
                    keep = i
                    paintDropFocus(btn)
                else
                    btn:Hide()
                    btn.value = nil
                    if btn.SetText then btn:SetText("") end
                    local nt = getglobal(name .. "Button" .. i .. "NormalText")
                    if nt and nt.SetText then nt:SetText("") end
                end
            end
        end
        local n = list.numButtons or 0
        while n > 0 do
            local btn = getglobal(name .. "Button" .. n)
            if btn and btn.IsShown and not btn:IsShown() then
                n = n - 1
            else
                break
            end
        end
        list.numButtons = n
        if n > 0 and list.SetHeight then
            local bh = UIDROPDOWNMENU_BUTTON_HEIGHT or 16
            local bd = UIDROPDOWNMENU_BORDER_HEIGHT or 15
            list:SetHeight((bh * n) + (bd * 2))
        end
        if keep then return 1 end
        return 0
    end
    UIDropDownMenu_Initialize(unitMenu, function(level)
        local menuLevel = level
        if not menuLevel then menuLevel = UIDROPDOWNMENU_MENU_LEVEL or 1 end
        local which = unitMenuWhich(unitMenuUnit)
        local nm = unitName(unitMenuUnit)
        if nm == "" then nm = nil end
        if menuLevel > 1 then
            if which and UnitPopup_ShowMenu then
                UnitPopup_ShowMenu(unitMenu, which, unitMenuUnit, nm, nil)
            end
            return
        end
        local list = getglobal("DropDownList" .. menuLevel)
        if not list then list = getglobal("DropDownList1") end
        if list and list.IsShown and list:IsShown() and (list.numButtons or 0) > 0 then
            if pruneSetFocus(list) > 0 then return end
        end
        if which and UnitPopup_ShowMenu then
            UnitPopup_ShowMenu(unitMenu, which, unitMenuUnit, nm, nil)
        end
        if which and which ~= "RAID_TARGET_ICON" and UIDropDownMenu_AddButton then
            local kept = 0
            if list then kept = pruneSetFocus(list) end
            if kept == 0 then
                local label = "Set Focus"
                if unitMenu._fromFocus then label = "Clear Focus" end
                UIDropDownMenu_AddButton({
                    text = label,
                    value = "ICHA_SET_FOCUS",
                    func = function()
                        if unitMenu._fromFocus then
                            if type(IchaUI_ClearFocus) == "function" then
                                IchaUI_ClearFocus()
                            end
                        elseif type(IchaUI_SetFocusUnit) == "function" then
                            IchaUI_SetFocusUnit(unitMenuUnit)
                        end
                    end,
                    notCheckable = 1,
                }, 1)
            end
        end
    end, "MENU")
    local li
    for li = 1, 3 do
        hookDropListSkin(getglobal("DropDownList" .. li))
    end
    -- lists may be created later on first open
    if UIDropDownMenu_CreateFrames and not unitMenuCreateHooked then
        unitMenuCreateHooked = true
        local oldCreate = UIDropDownMenu_CreateFrames
        UIDropDownMenu_CreateFrames = function(level, index)
            oldCreate(level, index)
            local i
            for i = 1, 3 do
                hookDropListSkin(getglobal("DropDownList" .. i))
            end
            skinOurDropLists()
        end
    end
    return unitMenu
end

hookDropListSkin(getglobal("DropDownList1"))
hookDropListSkin(getglobal("DropDownList2"))
hookDropListSkin(getglobal("DropDownList3"))

local function showUnitMenu(unit, fromFocus)
    if badUnitToken(unit) or not UnitExists or not UnitExists(unit) then return end
    unitMenuUnit = unit
    ensureUnitMenu()
    unitMenu._fromFocus = fromFocus and true or false
    local which = unitMenuWhich(unit)
    local useGrid = (which == "RAID_TARGET_ICON")
    if which == "PLAYER" and UnitCanCooperate then
        if not UnitCanCooperate("player", unit) then useGrid = true end
    end
    if useGrid then
        if CloseDropDownMenus then CloseDropDownMenus() end
        if unitMenu.ShowMarkGrid then unitMenu.ShowMarkGrid() end
        return
    end
    if unitMenu.HideMarkGrid then unitMenu.HideMarkGrid() end
    if not ToggleDropDownMenu then return end
    if CloseDropDownMenus then CloseDropDownMenus() end
    ToggleDropDownMenu(1, nil, unitMenu, "cursor", 0, 0)
    skinOurDropLists()
end

-- Click-to-dispel lives in IchaUI\Dispel.lua; it reads debuff schools through this.
IchaUI_Dispel_ReadDebuff = readDebuff

local function handleUnitFrameClick(fr, unit, button)
    if not fr or fr.moving then return end
    if fr.unit and fr.unit ~= "" then
        unit = fr.unit
    end
    if badUnitToken(unit) then return end
    if not UnitExists or not UnitExists(unit) then return end
    if SpellIsTargeting and SpellIsTargeting() then
        if button == "RightButton" then
            if SpellStopTargeting then SpellStopTargeting() end
        else
            if SpellTargetUnit then SpellTargetUnit(unit) else TargetUnit(unit) end
            return
        end
    end
    if CursorHasItem and CursorHasItem() then
        if DropItemOnUnit then DropItemOnUnit(unit) end
        return
    end
    if IchaUI_Dispel_HandleClick and IchaUI_Dispel_HandleClick(unit, button) then
        return
    end
    if button == "LeftButton" then
        TargetUnit(unit)
    elseif button == "RightButton" then
        showUnitMenu(unit, fr.key == "focus")
    end
end

local function createUnitFrame(key, unit, defaults, opts)
    opts = opts or {}
    local parent = opts.parent or UIParent
    local managedPos = opts.managedPos and true or false
    local raidCompact = opts.raidCompact and true or false
    local cfg = loadFrame(key, defaults)
    local wantPortrait = (opts.portrait and true) or false
    local portSide = opts.portraitSide or "left"
    if portSide ~= "right" then portSide = "left" end
    local fr = {
        key = key, unit = unit,
        scale = cfg.scale, width = cfg.width, height = cfg.height,
        hidden = cfg.hidden, moving = false,
        managedPos = managedPos,
        raidCompact = raidCompact,
        hasPortrait = wantPortrait,
        portraitEnabled = wantPortrait and (cfg.portrait and true or false),
        portraitScale = cfg.portraitScale or PORTRAIT_DEFAULT_SCALE,
        portraitRing = cfg.portraitRing or PORTRAIT_DEFAULT_RING,
        portraitOffsetX = cfg.portraitOffsetX or 0,
        portraitOffsetY = cfg.portraitOffsetY or 0,
        badgeAngle = cfg.badgeAngle or 0,
        badgeScale = cfg.badgeScale or 1,
        badgeOffsetX = cfg.badgeOffsetX or 0,
        badgeOffsetY = cfg.badgeOffsetY or 0,
        badgeHost = cfg.badgeHost,
        shieldChargeEnabled = cfg.shieldChargeEnabled ~= false,
        shieldChargeSpread = cfg.shieldChargeSpread or 90,
        shieldChargeSize = cfg.shieldChargeSize or 10,
        shieldChargeAngle = cfg.shieldChargeAngle or 0,
        shieldChargeReverse = cfg.shieldChargeReverse and true or false,
        shieldChargeOffsetX = cfg.shieldChargeOffsetX or 0,
        shieldChargeOffsetY = cfg.shieldChargeOffsetY or 0,
        portraitSide = portSide,
    }

    local root = CreateFrame("Button", "IchaUIUF_" .. key, parent)
    root:SetFrameStrata("MEDIUM")
    root:SetMovable(true)
    root:EnableMouse(true)
    root:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if IchaUI_Dispel_RegisterFrame then IchaUI_Dispel_RegisterFrame(root, fr) end
    root:RegisterForDrag("LeftButton")
    fr.root = root

    local border = CreateFrame("Frame", nil, root)
    border:SetAllPoints(root)
    applyGold(border, 12)
    fr.border = border

    -- Round portrait: same circle stack as totem slots (bg + face + gold ring)
    if wantPortrait then
        local port = CreateFrame("Button", "IchaUIUF_" .. key .. "_Portrait", root)
        port:SetFrameLevel((root:GetFrameLevel() or 1) + 40)
        port:EnableMouse(true)
        port:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        if IchaUI_Dispel_RegisterFrame then IchaUI_Dispel_RegisterFrame(port, fr) end
        port:SetScript("OnClick", function()
            handleUnitFrameClick(fr, unit, arg1)
        end)
        port:SetScript("OnEnter", function()
            fr._roleHover = true
            if IchaUI_UpdateUnitRoleIcons then IchaUI_UpdateUnitRoleIcons(fr) end
            if fr.moving then return end
            if not unit or unit == "" or unit == "none" or not UnitExists then return end
            local ok, exists = pcall(UnitExists, unit)
            if ok and exists then
                GameTooltip:SetOwner(port, "ANCHOR_BOTTOMRIGHT")
                GameTooltip:SetUnit(unit)
                GameTooltip:Show()
            end
        end)
        port:SetScript("OnLeave", function()
            GameTooltip:Hide()
            if IchaUI_RoleHoverEnd then IchaUI_RoleHoverEnd(fr) end
        end)
        fr.portraitFrame = port

        -- Totem-style circular backdrop (proven on this client)
        local circleBg = port:CreateTexture(nil, "BACKGROUND")
        circleBg:SetTexture("Interface/Minimap/UI-Minimap-Background")
        if IchaUI_PaintPortraitFill then
            IchaUI_PaintPortraitFill(circleBg)
        else
            circleBg:SetVertexColor(0.12, 0.08, 0.02, 1)
        end
        fr.portraitBg = circleBg

        local ptex = port:CreateTexture(nil, "ARTWORK")
        fr.portraitTex = ptex

        fr.portraitMask = nil

        -- Fresh frame/tex names (nil tex) — old global PortraitRingTex can stick to a dead parent
        local ringFrame = CreateFrame("Frame", "IchaUIUF_" .. key .. "_AzeriteRing", UIParent)
        -- MEDIUM with UF (not TOOLTIP) so World Map / bags cover the ring
        ringFrame:SetFrameStrata("MEDIUM")
        ringFrame:SetFrameLevel(50)
        ringFrame:EnableMouse(false)
        fr.portraitRingFrame = ringFrame
        local ring = ringFrame:CreateTexture(nil, "OVERLAY")
        fr.portraitRingTex = ring

        -- Combat / level badge. Same MEDIUM strata as the unit frame, a step
        -- above the portrait ring only. HIGH/DIALOG would cover bags and menus.
        -- Player: combat swords > rest zzz (OOC) > Port level. Target/ToT/combat: Port level.
        -- TrackingBorder is OK on this badge — never on the portrait ring itself.
        if key == "player" or key == "target" or key == "tot" or key == "focus" or (key and string.find(key, "^combat")) or (key and string.find(key, "^party")) then
            local badge = CreateFrame("Frame", "IchaUIUF_" .. key .. "_Badge", UIParent)
            badge:SetFrameStrata("MEDIUM")
            badge:SetFrameLevel(55)
            badge:EnableMouse(false)
            badge:Hide()
            fr.combatBadge = badge

            -- Alpha disc under the badge icon. Corners of the TGA are transparent.
            local circleBg = badge:CreateTexture(nil, "BACKGROUND")
            circleBg:SetTexture("Interface\\AddOns\\IchaUI\\media\\circledisc.tga")
            circleBg:SetVertexColor(0.05, 0.05, 0.06, 1)
            fr.combatBadgeBg = circleBg

            local combat = badge:CreateTexture(nil, "OVERLAY")
            combat:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
            combat:SetTexCoord(0.5, 1.0, 0.0, 0.5)
            combat:Hide()
            fr.combatIcon = combat

            local goldRing = badge:CreateTexture(nil, "BORDER")
            goldRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
            IchaUI_PaintGoldRing(goldRing)
            if goldRing.SetBlendMode then goldRing:SetBlendMode("BLEND") end
            fr.combatBadgeRing = goldRing

            -- Text above ring (child frame) so level isn't buried under TrackingBorder
            local textLayer = CreateFrame("Frame", nil, badge)
            textLayer:SetAllPoints(badge)
            textLayer:SetFrameLevel((badge:GetFrameLevel() or 1) + 10)
            fr.combatBadgeTextLayer = textLayer
            local lvlFS = textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lvlFS:SetJustifyH("CENTER")
            lvlFS:SetJustifyV("MIDDLE")
            lvlFS:SetTextColor(1, 0.92, 0.65)
            lvlFS:Hide()
            fr.levelText = lvlFS
        end
    end

    local hpBg = makeBar(root, "BACKGROUND")
    hpBg:SetVertexColor(0.12, 0.12, 0.12)
    fr.hpBg = hpBg

    -- Soft green incoming chunk (BORDER = above empty bg, beside current HP fill)
    local healPred = makeBar(root, "BORDER")
    healPred:SetVertexColor(0.35, 0.9, 0.45)
    healPred:SetAlpha(0.55)
    healPred:Hide()
    fr.healPred = healPred

    local hp = makeBar(root, "ARTWORK")
    fr.hp = hp

    -- Dispellable debuff tint (heal-pred style StatusBar), above HP, under text
    local dispelTint = makeBar(root, "OVERLAY")
    dispelTint:SetAlpha(0)
    dispelTint:Hide()
    fr.dispelTint = dispelTint
    fr.glow = dispelTint -- alias for any leftover refs

    local nameFS = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFS:SetJustifyH("CENTER")
    nameFS:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    fr.nameFS = nameFS

    local hpText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hpText:SetJustifyH("CENTER")
    hpText:SetTextColor(1, 1, 1)
    fr.hpText = hpText

    -- Red DC mark sits on the HP text anchor (party/raid, and focus when that token is one).
    if isPartyUnit(unit) or isRaidUnit(unit) or key == "focus" then
        fr.dcIcon = root:CreateTexture(nil, "OVERLAY")
        fr.dcIcon:SetTexture("Interface\\CharacterFrame\\Disconnect-Icon")
        fr.dcIcon:SetVertexColor(1, 0.15, 0.15, 1)
        fr.dcIcon:Hide()
    end

    local hpLevel = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hpLevel:SetJustifyH("RIGHT")
    hpLevel:SetTextColor(1, 0.82, 0)
    hpLevel:Hide()
    fr.hpLevel = hpLevel

    local mpBg = makeBar(root, "BACKGROUND")
    mpBg:SetVertexColor(0.1, 0.1, 0.1)
    fr.mpBg = mpBg

    local mp = makeBar(root, "ARTWORK")
    fr.mp = mp

    local mpTick = root:CreateTexture(nil, "OVERLAY")
    mpTick:SetTexture("Interface\\AddOns\\IchaUI\\media\\ManaTickSpark.tga")
    mpTick:SetTexCoord(0.015625, 0.984375, 0.015625, 0.984375)
    if mpTick.SetBlendMode then mpTick:SetBlendMode("ADD") end
    mpTick:SetWidth(20)
    mpTick:SetHeight(32)
    mpTick:Hide()
    fr.mpTick = mpTick
    fr._lastMana = nil
    fr._manaFsrTripAt = 0
    fr._manaTickTarget = nil
    fr._manaTickStart = nil
    fr._manaTickMax = nil

    -- Melee swing timer bar in the HP–MP gap (player, target, tot, combat plates)
    if key == "player" or key == "target" or key == "tot" or key == "focus" or (key and string.find(key, "^combat")) then
        local swingBg = makeBar(root, "BACKGROUND")
        swingBg:SetVertexColor(0.08, 0.08, 0.08)
        fr.swingBg = swingBg
        local swingFill = makeBar(root, "ARTWORK")
        swingFill:SetVertexColor(0.92, 0.90, 0.82)
        swingFill:Hide()
        fr.swingFill = swingFill
        local swingSpark = root:CreateTexture(nil, "OVERLAY")
        swingSpark:SetTexture(IchaUI_SWING_SPARK)
        if swingSpark.SetBlendMode then
            pcall(function() swingSpark:SetBlendMode("ADD") end)
        end
        swingSpark:SetVertexColor(0.95, 0.93, 0.85)
        swingSpark:SetWidth(12)
        swingSpark:SetHeight(8)
        swingSpark:Hide()
        fr.swingSpark = swingSpark
        fr._swingStart = nil
        fr._swingPeriod = nil
    end

    local powerText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    powerText:SetJustifyH("CENTER")
    powerText:SetTextColor(1, 1, 1)
    powerText:Hide()
    fr.powerText = powerText

    -- Cast bar: chrome border + spark + totem-style circular spell icon
    local castFrame = CreateFrame("Frame", nil, root)
    castFrame:Hide()
    castFrame:SetMovable(true)
    castFrame:EnableMouse(false)
    fr.castFrame = castFrame
    -- Raid frames: never show cast bars
    if raidCompact then
        castFrame:Hide()
        castFrame:SetHeight(1)
        castFrame:SetAlpha(0)
    end
    local castBg = makeBar(castFrame, "BACKGROUND")
    castBg:SetTexture(IchaUI_CAST_FILL)
    castBg:SetVertexColor(0.08, 0.07, 0.06, 1)
    fr.castBg = castBg
    local castFill = makeBar(castFrame, "ARTWORK")
    castFill:SetTexture(IchaUI_CAST_FILL)
    IchaUI_PaintGoldVertex(castFill, CAST_GOLD[1], CAST_GOLD[2], CAST_GOLD[3], 1, true)
    fr.castFill = castFill
    -- Predictive latency segment (player casts / test mode); red end-zone
    local castLag = makeBar(castFrame, "BORDER")
    castLag:SetTexture(IchaUI_CAST_FILL)
    castLag:SetVertexColor(0.85, 0.12, 0.12, 1)
    castLag:SetAlpha(1)
    castLag:Hide()
    fr.castLag = castLag
    -- Totem-style circular spell icon — oversized, sits over left end of bar art
    local castIconHolder = CreateFrame("Frame", nil, castFrame)
    castIconHolder:SetWidth(32)
    castIconHolder:SetHeight(32)
    castIconHolder:SetFrameLevel((castFrame:GetFrameLevel() or 1) + 8)
    fr.castIconHolder = castIconHolder
    local castIconBg = castIconHolder:CreateTexture(nil, "BACKGROUND")
    castIconBg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    castIconBg:SetVertexColor(0, 0, 0, 1)
    fr.castIconBg = castIconBg
    local castIcon = castIconHolder:CreateTexture(nil, "ARTWORK")
    fr.castIcon = castIcon
    local castIconRing = castIconHolder:CreateTexture(nil, "OVERLAY")
    castIconRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    if castIconRing.SetBlendMode then castIconRing:SetBlendMode("BLEND") end
    IchaUI_PaintGoldRing(castIconRing)
    fr.castIconRing = castIconRing
    -- Spell icon drawn under the FocusShield chrome (transparent hole)
    local castSpellIcon = castFrame:CreateTexture(nil, "ARTWORK")
    castSpellIcon:Hide()
    fr.castSpellIcon = castSpellIcon
    -- Classic casting-bar border chrome (texture, not tooltip backdrop)
    local castBorder = castFrame:CreateTexture(nil, "OVERLAY")
    castBorder:SetTexture(IchaUI_CAST_BORDER)
    IchaUI_PaintGoldVertex(castBorder, 0.96, 0.70, 0.06, 1)
    fr.castBorder = castBorder
    -- Name and timer sit above the bar art so the shield channel does not cover them
    local castTextPlate = CreateFrame("Frame", nil, castFrame)
    castTextPlate:SetAllPoints(castFrame)
    castTextPlate:SetFrameLevel((castFrame:GetFrameLevel() or 1) + 5)
    local castName = castTextPlate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    castName:SetJustifyH("LEFT")
    castName:SetTextColor(1, 0.95, 0.85)
    fr.castName = castName
    local castTime = castTextPlate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    castTime:SetJustifyH("RIGHT")
    castTime:SetTextColor(1, 0.95, 0.85)
    castTime:Hide()
    fr.castTime = castTime
    -- Progress spark at fill edge
    local castSpark = castFrame:CreateTexture(nil, "OVERLAY")
    castSpark:SetTexture(IchaUI_CAST_SPARK)
    if castSpark.SetBlendMode then
        pcall(function() castSpark:SetBlendMode("ADD") end)
    end
    castSpark:SetWidth(20)
    castSpark:SetHeight(20)
    castSpark:Hide()
    fr.castSpark = castSpark
    local castInterrupt = castTextPlate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    castInterrupt:SetPoint("CENTER", castFrame, "CENTER", 0, 0)
    castInterrupt:SetTextColor(1, 0.15, 0.15)
    castInterrupt:SetText("Interrupted")
    castInterrupt:Hide()
    fr.castInterrupt = castInterrupt
    -- Detached mover (player + target only)
    if key == "player" or key == "target" or key == "focus" then
        local castMover = CreateFrame("Frame", nil, castFrame)
        castMover:SetAllPoints(castFrame)
        castMover:EnableMouse(true)
        castMover:RegisterForDrag("LeftButton")
        castMover:Hide()
        castMover:SetFrameLevel((castFrame:GetFrameLevel() or 1) + 30)
        local cmbg = castMover:CreateTexture(nil, "BACKGROUND")
        cmbg:SetAllPoints(castMover)
        cmbg:SetTexture(1, 1, 1, 1)
        cmbg:SetVertexColor(0.95, 0.55, 0.15, 0.35)
        local cml = castMover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        cml:SetPoint("CENTER", castMover, "CENTER")
        cml:SetText("Drag cast")
        castMover:SetScript("OnDragStart", function()
            castFrame:StartMoving()
        end)
        castMover:SetScript("OnDragStop", function()
            castFrame:StopMovingOrSizing()
            local kind = textKindForKey(key)
            local p, _, rp, x, y = castFrame:GetPoint(1)
            local s = IchaUIUF_GetCastSettings and IchaUIUF_GetCastSettings(kind)
            if s then
                s.castPoint = p
                s.castRelPoint = rp or p
                s.castX = tonumber(x) or 0
                s.castY = tonumber(y) or 0
                if IchaUIDB and IchaUIDB.uf then
                    if not IchaUIDB.uf.castByType then IchaUIDB.uf.castByType = {} end
                    IchaUIDB.uf.castByType[kind] = s
                    IchaUIDB.uf = IchaUIDB.uf
                end
            end
        end)
        fr.castMover = castMover
        fr._castMoving = false
    end
    fr._casting = false
    fr._castLocked = false
    fr._interruptedUntil = 0

    fr._interruptedUntil = 0

    -- PvP flag icon (screen-center side of bar)
    local pvpIcon = root:CreateTexture(nil, "OVERLAY")
    pvpIcon:SetWidth(18)
    pvpIcon:SetHeight(18)
    -- Screen-center side of the frame (player/party: right; target: left), inset into the bar
    if key == "player" or isPartyUnit(unit) then
        pvpIcon:SetPoint("TOPRIGHT", root, "TOPRIGHT", -4, -4)
    else
        pvpIcon:SetPoint("TOPLEFT", root, "TOPLEFT", 4, -4)
    end
    pvpIcon:Hide()
    fr.pvpIcon = pvpIcon

    do
        local mark = CreateFrame("Frame", "IchaUIUF_" .. key .. "_RaidMark", root)
        mark:EnableMouse(false)
        mark:Hide()
        local mtex = mark:CreateTexture(nil, "OVERLAY")
        mtex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        mtex:SetAllPoints(mark)
        mtex:Hide()
        fr.raidMark = mark
        fr.raidMarkTex = mtex
    end
    if IchaUI_AttachRoleIcons then IchaUI_AttachRoleIcons(fr, key, root) end

    fr.buffs = {}
    fr.debuffs = {}
    local i
    for i = 1, MAX_AURA_SLOTS do
        fr.buffs[i] = makeAuraSlot(root)
        fr.debuffs[i] = makeAuraSlot(root)
    end

    local mover = CreateFrame("Frame", nil, root)
    mover:SetAllPoints(root)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    if managedPos then
        mover:Hide()
        mover:EnableMouse(false)
    else
        mover:Hide()
    end
    mover:SetFrameLevel((root:GetFrameLevel() or 1) + 20)
    local mbg = mover:CreateTexture(nil, "BACKGROUND")
    mbg:SetAllPoints(mover)
    mbg:SetTexture(1, 1, 1, 1)
    mbg:SetVertexColor(0.15, 0.45, 0.95, 0.35)
    local ml = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ml:SetPoint("CENTER", mover, "CENTER")
    ml:SetText("Drag " .. key)
    mover:SetScript("OnDragStart", function() root:StartMoving() end)
    mover:SetScript("OnDragStop", function()
        root:StopMovingOrSizing()
        saveFrame(key, fr)
    end)
    fr.mover = mover

    root:SetScript("OnClick", function()
        handleUnitFrameClick(fr, unit, arg1)
    end)
    root:SetScript("OnEnter", function()
        fr._roleHover = true
        if IchaUI_UpdateUnitRoleIcons then IchaUI_UpdateUnitRoleIcons(fr) end
        if fr.moving then return end
        if not unit or unit == "" or unit == "none" or not UnitExists then return end
        local ok, exists = pcall(UnitExists, unit)
        if ok and exists then
            GameTooltip:SetOwner(root, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:SetUnit(unit)
            GameTooltip:Show()
        end
    end)
    root:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if IchaUI_RoleHoverEnd then IchaUI_RoleHoverEnd(fr) end
    end)

    function fr:applySize()
        local w = math.floor(self.width * self.scale + 0.5)
        local h = math.floor(self.height * self.scale + 0.5)
        root:SetWidth(w)
        root:SetHeight(h)
        local unitLive = false
        if unit and unit ~= "" and unit ~= "none" and UnitExists then
            local ok, exists = pcall(UnitExists, unit)
            unitLive = ok and exists and true or false
        end
        local e = math.floor(12 * self.scale + 0.5)
        if e < 8 then e = 8 end
        if e > 20 then e = 20 end
        applyGold(border, e)
        if border then border:Show() end
        -- gold border frame level set after glow layout (above HP glow)

        -- Portrait: one port frame; bg + face + Azerite ring all scale together
        if self.hasPortrait and self.portraitFrame then
            if self.portraitEnabled ~= false then
                local psc = tonumber(self.portraitScale) or PORTRAIT_DEFAULT_SCALE
                local pring = tonumber(self.portraitRing) or PORTRAIT_DEFAULT_RING
                local ph = math.floor(h * psc + 0.5)
                if ph < 28 then ph = 28 end
                local ringSz = math.floor(ph * pring + 0.5)
                if ringSz < 16 then ringSz = 16 end

                local port = self.portraitFrame
                port:Show()
                port:SetWidth(ph)
                port:SetHeight(ph)
                port:ClearAllPoints()
                local cutIn = math.floor(ph * 0.32 + 0.5)
                local ox = tonumber(self.portraitOffsetX) or 0
                local oy = tonumber(self.portraitOffsetY) or 0
                if self.portraitSide == "right" then
                    local rightOff = (ph - cutIn) + ox
                    port:SetPoint("RIGHT", root, "RIGHT", rightOff, oy)
                else
                    local leftOff = -(ph - cutIn) + ox
                    port:SetPoint("LEFT", root, "LEFT", leftOff, oy)
                end
                port:SetFrameLevel((root:GetFrameLevel() or 1) + 40)

                local faceSz = math.floor(ph * (1 - 2 * PORTRAIT_FACE_INSET) + 0.5)
                if faceSz < 12 then faceSz = 12 end

                if self.portraitBg then
                    self.portraitBg:Show()
                    self.portraitBg:ClearAllPoints()
                    self.portraitBg:SetAllPoints(port)
                    self.portraitBg:SetTexture("Interface/Minimap/UI-Minimap-Background")
                    if IchaUI_PaintPortraitFill then
                        IchaUI_PaintPortraitFill(self.portraitBg)
                    else
                        self.portraitBg:SetVertexColor(0.12, 0.08, 0.02, 1)
                    end
                end

                if self.portraitTex then
                    self.portraitTex:ClearAllPoints()
                    self.portraitTex:SetWidth(faceSz)
                    self.portraitTex:SetHeight(faceSz)
                    self.portraitTex:SetPoint("CENTER", port, "CENTER", 0, 0)
                    if IchaUI_ApplyPortraitFace then
                        IchaUI_ApplyPortraitFace(self.portraitTex, unit)
                    else
                        if SetPortraitTexture and unitLive then
                            SetPortraitTexture(self.portraitTex, unit)
                        end
                        self.portraitTex:Show()
                    end
                    if (isPartyUnit(unit) or isRaidUnit(unit)) and unit ~= "" and unit ~= "none" then
                        if UnitIsConnected and not UnitIsConnected(unit) then
                            self.portraitTex:SetVertexColor(0.45, 0.45, 0.45)
                            if self.portraitTex.SetDesaturated then
                                pcall(function() self.portraitTex:SetDesaturated(1) end)
                            end
                        else
                            self.portraitTex:SetVertexColor(1, 1, 1)
                            if self.portraitTex.SetDesaturated then
                                pcall(function() self.portraitTex:SetDesaturated(0) end)
                            end
                        end
                    end
                end

                if self.portraitRingFrame and self.portraitRingTex then
                    local rf = self.portraitRingFrame
                    rf:Show()
                    rf:SetWidth(ringSz)
                    rf:SetHeight(ringSz)
                    rf:ClearAllPoints()
                    rf:SetPoint("CENTER", port, "CENTER", 0, 0)
                    rf:SetFrameStrata("MEDIUM")
                    rf:SetFrameLevel((root:GetFrameLevel() or 1) + 50)
                    applyPortraitRing(self.portraitRingTex, rf, ringSz)
                end
                if self.combatBadge then
                    local bsc = tonumber(self.badgeScale) or 1
                    if bsc < 0.5 then bsc = 0.5 end
                    if bsc > 2 then bsc = 2 end
                    local csz = math.floor(ph * 0.38 * bsc + 0.5)
                    if csz < 12 then csz = 12 end
                    if csz > 40 then csz = 40 end
                    local badge = self.combatBadge
                    badge:SetWidth(csz)
                    badge:SetHeight(csz)
                    badge:ClearAllPoints()
                    -- Angle 0 = bottom of portrait; increases clockwise around the rim
                    local ang = tonumber(self.badgeAngle) or 0
                    while ang < 0 do ang = ang + 360 end
                    while ang >= 360 do ang = ang - 360 end
                    local rad = ang * math.pi / 180
                    local radius = (ph * 0.5) - (csz * 0.15)
                    if radius < ph * 0.25 then radius = ph * 0.25 end
                    local bx = math.sin(rad) * radius + (tonumber(self.badgeOffsetX) or 0)
                    local by = -math.cos(rad) * radius + (tonumber(self.badgeOffsetY) or 0)
                    local badgeRel = port
                    if self.badgeHost == "frame" then
                        badgeRel = root
                        bx = tonumber(self.badgeOffsetX) or 0
                        by = tonumber(self.badgeOffsetY) or 0
                    end
                    badge:SetPoint("CENTER", badgeRel, "CENTER", bx, by)
                    badge:SetFrameStrata("MEDIUM")
                    badge:SetFrameLevel((root:GetFrameLevel() or 1) + 55)
                    -- Big centered content (~88% of badge); dark fill matches content
                    local inset = math.floor(csz * 0.88 + 0.5)
                    if inset < 12 then inset = 12 end
                    if self.combatIcon then
                        self.combatIcon:ClearAllPoints()
                        self.combatIcon:SetWidth(inset)
                        self.combatIcon:SetHeight(inset)
                        self.combatIcon:SetPoint("CENTER", badge, "CENTER", 0, 0)
                    end
                    if self.combatBadgeBg then
                        -- Same hole as the badge icon, inside the gold ring
                        self.combatBadgeBg:SetTexture("Interface\\AddOns\\IchaUI\\media\\circledisc.tga")
                        self.combatBadgeBg:ClearAllPoints()
                        self.combatBadgeBg:SetWidth(inset)
                        self.combatBadgeBg:SetHeight(inset)
                        self.combatBadgeBg:SetPoint("CENTER", badge, "CENTER", 0, 0)
                        self.combatBadgeBg:SetVertexColor(0.05, 0.05, 0.06, 1)
                        self.combatBadgeBg:SetAlpha(1)
                        self.combatBadgeBg:Show()
                    end
                    if self.combatBadgeMask then self.combatBadgeMask:Hide() end
                    if self.levelText then
                        local fontPath = GameFontHighlightSmall:GetFont()
                        -- Scale with badge; no fixed min that overflows small badges into "..."
                        local fs = math.floor(csz * 0.50 + 0.5)
                        if fs < 6 then fs = 6 end
                        if fs > 18 then fs = 18 end
                        if fontPath then
                            self.levelText:SetFont(fontPath, fs, "OUTLINE")
                        end
                        self.levelText:ClearAllPoints()
                        self.levelText:SetPoint("CENTER", badge, "CENTER", 0, 0)
                        -- Wide enough that 2-digit levels never ellipsize; font already scaled
                        self.levelText:SetWidth(csz + 10)
                        self.levelText:SetHeight(csz)
                        self.levelText:SetJustifyH("CENTER")
                    end
                    if self.combatBadgeTextLayer then
                        self.combatBadgeTextLayer:SetFrameLevel((badge:GetFrameLevel() or 1) + 10)
                        self.combatBadgeTextLayer:Show()
                    end
                    if self.combatBadgeRing then
                        local bw = math.floor(csz * 1.65 + 0.5)
                        self.combatBadgeRing:ClearAllPoints()
                        self.combatBadgeRing:SetWidth(bw)
                        self.combatBadgeRing:SetHeight(bw)
                        self.combatBadgeRing:SetPoint("TOPLEFT", badge, "TOPLEFT", 0, 0)
                        self.combatBadgeRing:Show()
                    end
                end
            else
                self.portraitFrame:Hide()
                if self.portraitRingFrame then self.portraitRingFrame:Hide() end
                if self.portraitRingTex then self.portraitRingTex:Hide() end
                if self.combatBadge then self.combatBadge:Hide() end
                if self.combatIcon then self.combatIcon:Hide() end
                if self.levelText then self.levelText:Hide() end
            end
            if self.updateShieldCharges then
                self:updateShieldCharges()
            end
            if IchaUI_UpdateUnitRaidMark then IchaUI_UpdateUnitRaidMark(self) end
            if IchaUI_UpdateUnitRoleIcons then IchaUI_UpdateUnitRoleIcons(self) end
        end

        border:ClearAllPoints()
        border:SetAllPoints(root)

        local pad = 3
        local gap = 2
        -- Party and raid have no swing timer, so do not reserve the HP–MP slot.
        local barGap = gap
        if isPartyUnit(key) or isRaidUnit(key) then barGap = 0 end
        local barW = w - pad * 2
        if barW < 1 then barW = 1 end
        local usable = h - pad * 2
        local mpH, hpH, customScreen = nil, nil, nil
        if IchaUIUF_ResolveBarPixels then
            hpH, mpH, customScreen = IchaUIUF_ResolveBarPixels(key)
        end
        if not hpH then
            mpH = math.max(1, math.floor(usable * 0.16 + 0.5))
            hpH = usable - barGap - mpH
            if hpH < 1 then hpH = 1 end
        elseif customScreen and customScreen > 0 then
            h = customScreen
            root:SetHeight(h)
        end
        -- Natural art height. Do not multiply by frame scale (that squashes the caps).
        local castH = IchaUI_CAST_ART_H or 22
        local castAllowed = true
        if IchaUIUF_CastBarOn and not IchaUIUF_CastBarOn(textKindForKey(key)) then
            castAllowed = false
        end
        local showCast = castAllowed and (not self.raidCompact) and (self._casting or ((self._interruptedUntil or 0) > (GetTime and GetTime() or 0)))

        local ts = loadTextSettings(textKindForKey(key))
        local nameSc = tonumber(ts.nameScale) or 1
        local hpSc = tonumber(ts.hpScale) or 1
        local powerSc = tonumber(ts.powerScale) or 1
        local nameH = math.max(6, math.floor(12 * self.scale * nameSc + 0.5))
        local hpNumH = math.max(6, math.floor(9 * self.scale * hpSc + 0.5))
        local fontPath = GameFontHighlightSmall:GetFont()
        if fontPath then
            nameFS:SetFont(fontPath, nameH, "OUTLINE")
            hpText:SetFont(fontPath, hpNumH, "OUTLINE")
            local cFont = math.floor(castH * 0.5 + 0.5)
            if cFont < 6 then cFont = 6 end
            if cFont > 16 then cFont = 16 end
            castName:SetFont(fontPath, cFont, "OUTLINE")
            castTime:SetFont(fontPath, cFont, "OUTLINE")
            castInterrupt:SetFont(fontPath, cFont + 1, "OUTLINE")
        end
        if self.hpLevel and fontPath then
            local lsz = math.max(6, math.floor(IchaUIUF_GetLevelFont() * self.scale + 0.5))
            self.hpLevel:SetFont(fontPath, lsz, "OUTLINE")
            self.hpLevel:ClearAllPoints()
            self.hpLevel:SetPoint("BOTTOMRIGHT", hpBg, "BOTTOMRIGHT", -3, 2)
            self.hpLevel:SetJustifyH("RIGHT")
            self.hpLevel:SetWidth(math.max(28, math.floor(barW * 0.4)))
            self.hpLevel:SetHeight(lsz + 2)
        end

        local pvpSz = math.max(14, math.floor(16 * self.scale + 0.5))
        pvpIcon:SetWidth(pvpSz)
        pvpIcon:SetHeight(pvpSz)
        pvpIcon:ClearAllPoints()
        if key == "player" or isPartyUnit(unit) then
            pvpIcon:SetPoint("TOPRIGHT", root, "TOPRIGHT", -4, -4)
        else
            pvpIcon:SetPoint("TOPLEFT", root, "TOPLEFT", 4, -4)
        end

        hpBg:ClearAllPoints()
        hpBg:SetPoint("TOPLEFT", root, "TOPLEFT", pad, -pad)
        hpBg:SetWidth(barW)
        hpBg:SetHeight(hpH)

        -- Dispel tint covers full HP bar (same rect as hpBg), under name/HP text
        if self.dispelTint then
            self.dispelTint:ClearAllPoints()
            self.dispelTint:SetAllPoints(hpBg)
        end
        if border then
            border:SetFrameLevel((root:GetFrameLevel() or 1) + 8)
        end
        if border then
            border:SetFrameLevel((root:GetFrameLevel() or 1) + 8)
        end

        -- healPred placed in update/refreshHealOverlay (soft StatusBar chunk)
        healPred:SetTexture("Interface/TargetingFrame/UI-StatusBar")
        healPred:SetVertexColor(0.35, 0.9, 0.45)
        healPred:SetAlpha(0.55)

        if self._holdMissing and not unitLive and key and string.find(key, "^combat") then
            self._holdHpW = hp:GetWidth()
        end
        hp:ClearAllPoints()
        hp:SetPoint("TOPLEFT", hpBg, "TOPLEFT", 0, 0)
        hp:SetPoint("BOTTOMLEFT", hpBg, "BOTTOMLEFT", 0, 0)
        -- Never leave HP at full barW (cast show/hide calls applySize) — use live %
        local hpPct0 = 0
        if unitLive then
            local hpCur0 = UnitHealth(unit) or 0
            local hpMax0 = UnitHealthMax(unit) or 1
            if hpMax0 < 1 then hpMax0 = 1 end
            hpPct0 = hpCur0 / hpMax0
            if hpPct0 < 0 then hpPct0 = 0 end
            if hpPct0 > 1 then hpPct0 = 1 end
        elseif testMode then
            hpPct0 = 0.75
        end
        if self._holdMissing and not unitLive and key and string.find(key, "^combat") then
            if not self._holdHpW or self._holdHpW < 0.001 then self._holdHpW = 0.001 end
            IchaUI_SeatPowerFill(hp, hpBg, self._holdHpW)
        else
            IchaUI_SeatPowerFill(hp, hpBg, math.max(0.001, barW * hpPct0))
        end

        local function alignPoint(align)
            if align == "LEFT" then return "LEFT" end
            if align == "RIGHT" then return "RIGHT" end
            return "CENTER"
        end

        nameFS:ClearAllPoints()
        local nap = alignPoint(ts.nameAlign)
        nameFS:SetJustifyH(ts.nameAlign)
        if nap == "LEFT" then
            nameFS:SetPoint("LEFT", hpBg, "LEFT", 4 + ts.nameX, ts.nameY)
        elseif nap == "RIGHT" then
            nameFS:SetPoint("RIGHT", hpBg, "RIGHT", -4 + ts.nameX, ts.nameY)
        else
            nameFS:SetPoint("CENTER", hpBg, "CENTER", ts.nameX, ts.nameY)
        end
        local nameMax = barW - 8
        if nameMax < 20 then nameMax = 20 end
        nameFS:SetWidth(nameMax)
        nameFS:SetHeight(nameH + 2)
        if type(nameFS.SetNonSpaceWrap) == "function" then
            pcall(function() nameFS:SetNonSpaceWrap(0) end)
        end
        self._nameMaxW = nameMax

        hpText:ClearAllPoints()
        local hap = alignPoint(ts.hpAlign)
        hpText:SetJustifyH(ts.hpAlign)
        if hap == "LEFT" then
            hpText:SetPoint("LEFT", hpBg, "LEFT", 4 + ts.hpX, ts.hpY)
        elseif hap == "RIGHT" then
            hpText:SetPoint("RIGHT", hpBg, "RIGHT", -4 + ts.hpX, ts.hpY)
        else
            hpText:SetPoint("CENTER", hpBg, "CENTER", ts.hpX, ts.hpY)
        end
        hpText:SetWidth(barW - 8)

        if self.dcIcon then
            local dcSz = math.floor(hpNumH + 6)
            if dcSz < 12 then dcSz = 12 end
            if dcSz > 16 then dcSz = 16 end
            if hpH > 6 and dcSz > hpH - 4 then dcSz = hpH - 4 end
            if dcSz < 8 then dcSz = 8 end
            self.dcIcon:ClearAllPoints()
            self.dcIcon:SetWidth(dcSz)
            self.dcIcon:SetHeight(dcSz)
            if hap == "LEFT" then
                self.dcIcon:SetPoint("LEFT", hpBg, "LEFT", 4 + ts.hpX, ts.hpY)
            elseif hap == "RIGHT" then
                self.dcIcon:SetPoint("RIGHT", hpBg, "RIGHT", -4 + ts.hpX, ts.hpY)
            else
                self.dcIcon:SetPoint("CENTER", hpBg, "CENTER", ts.hpX, ts.hpY)
            end
        end

        local powerFontH = math.max(6, math.floor(8 * self.scale * powerSc + 0.5))
        if fontPath then
            powerText:SetFont(fontPath, powerFontH, "OUTLINE")
        end
        powerText:ClearAllPoints()
        local pap = alignPoint(ts.powerAlign)
        powerText:SetJustifyH(ts.powerAlign)
        if pap == "LEFT" then
            powerText:SetPoint("LEFT", mpBg, "LEFT", 4, 0)
        elseif pap == "RIGHT" then
            powerText:SetPoint("RIGHT", mpBg, "RIGHT", -4, 0)
        else
            powerText:SetPoint("CENTER", mpBg, "CENTER", 0, 0)
        end
        powerText:SetWidth(barW - 8)
        if ts.showPowerText then
            powerText:Show()
        else
            powerText:Hide()
        end

        -- Power always in its slot under HP; cast bar sits beneath power when active
        -- Swing timer occupies the existing HP–MP gap (height=gap); layout totals unchanged
        if self.swingBg then
            self.swingBg:ClearAllPoints()
            self.swingBg:SetPoint("TOPLEFT", hpBg, "BOTTOMLEFT", 0, 0)
            self.swingBg:SetWidth(barW)
            self.swingBg:SetHeight(gap)
            self.swingBg:Show()
            if self.swingFill then
                self.swingFill:SetHeight(gap)
                self.swingFill:SetVertexColor(0.92, 0.90, 0.82)
            end
            if self.swingSpark then
                local sh = gap * 4
                if sh < 8 then sh = 8 end
                self.swingSpark:SetWidth(12)
                self.swingSpark:SetHeight(sh)
                self.swingSpark:SetVertexColor(0.95, 0.93, 0.85)
            end
            mpBg:ClearAllPoints()
            mpBg:SetPoint("TOPLEFT", self.swingBg, "BOTTOMLEFT", 0, 0)
        else
            mpBg:ClearAllPoints()
            mpBg:SetPoint("TOPLEFT", hpBg, "BOTTOMLEFT", 0, -barGap)
        end
        mpBg:SetWidth(barW)
        mpBg:SetHeight(mpH)
        mpBg:Show()

        if self._holdMissing and not unitLive and key and string.find(key, "^combat") then
            self._holdMpW = mp:GetWidth()
        end
        local mpPct0 = 0
        if unitLive then
            local mpCur0 = UnitMana(unit) or 0
            local mpMax0 = UnitManaMax(unit) or 1
            if mpMax0 < 1 then mpMax0 = 1 end
            mpPct0 = mpCur0 / mpMax0
            if mpPct0 < 0 then mpPct0 = 0 end
            if mpPct0 > 1 then mpPct0 = 1 end
        end
        local mpW0 = math.max(0.001, barW * mpPct0)
        if self._holdMissing and not unitLive and key and string.find(key, "^combat") then
            if not self._holdMpW or self._holdMpW < 0.001 then self._holdMpW = 0.001 end
            mpW0 = self._holdMpW
        end
        do
            local fillKind = textKindForKey(key)
            local hpPath = "Interface/TargetingFrame/UI-StatusBar"
            local mpPath = hpPath
            if IchaUIUF_BarFillPath then
                hpPath = IchaUIUF_BarFillPath(fillKind, "health") or hpPath
                mpPath = IchaUIUF_BarFillPath(fillKind, "power") or mpPath
            end
            local hpDrawW = hp:GetWidth()
            local mpDrawW = mp:GetWidth()
            if not hpDrawW or hpDrawW < 0.001 then hpDrawW = 0.001 end
            if not mpDrawW or mpDrawW < 0.001 then mpDrawW = 0.001 end
            IchaUIUF_ApplyBarFill(hp, hpPath)
            IchaUIUF_ApplyBarFill(mp, mpPath)
            -- SetTexture resets the quad to the file size. Explicit width and
            -- height (not TOP+BOTTOM) keep Bevel/Gloss from centering.
            IchaUI_SeatPowerFill(hp, hpBg, hpDrawW)
            if self.swingFill then
                self.swingFill:SetTexture("Interface/TargetingFrame/UI-StatusBar")
            end
        end
        -- After SetTexture: file height is ~32px and would sit short of a thin power slot.
        IchaUI_SeatPowerFill(mp, mpBg, mpW0)
        mp:Show()

        if ts.showPowerText then
            powerText:Show()
        else
            powerText:Hide()
        end

        do
            local ckind = textKindForKey(key)
            local cs = IchaUIUF_GetCastSettings(ckind)
            local castPos = cs.castPos or "bottom"
            local cox = tonumber(cs.castOffsetX) or 0
            local coy = tonumber(cs.castOffsetY) or 0
            local castW = tonumber(cs.castLen) or IchaUI_CAST_NAT or 214
            if castW < (IchaUI_CAST_LEN_MIN or 80) then castW = IchaUI_CAST_LEN_MIN or 80 end
            if castW > (IchaUI_CAST_LEN_MAX or 420) then castW = IchaUI_CAST_LEN_MAX or 420 end
            -- Length is unscaled pixels. Scale then shrinks X and Y by the same factor.
            self._castScale = tonumber(cs.castScale) or 1
            if self._castScale < (IchaUI_CAST_SC_MIN or 0.4) then self._castScale = IchaUI_CAST_SC_MIN or 0.4 end
            if self._castScale > (IchaUI_CAST_SC_MAX or 3) then self._castScale = IchaUI_CAST_SC_MAX or 3 end
            local detached = (key == "player" or key == "target" or key == "focus") and cs.castDetached and true or false
            self._castDetached = detached
            self._castPos = castPos

            castFrame:ClearAllPoints()
            if detached then
                if castFrame:GetParent() ~= UIParent then
                    castFrame:SetParent(UIParent)
                end
                castFrame:SetScale(self._castScale or 1)
                castFrame:SetFrameStrata("MEDIUM")
                castFrame:SetFrameLevel(60)
                if cs.castPoint and cs.castX ~= nil then
                    castFrame:SetPoint(cs.castPoint, UIParent, cs.castRelPoint or cs.castPoint, cs.castX or 0, cs.castY or 0)
                else
                    castFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -40)
                end
                self._debuffYExtra = 0
            else
                if castFrame:GetParent() ~= root then
                    castFrame:SetParent(root)
                end
                castFrame:SetScale(self._castScale or 1)
                if castPos == "top" then
                    castFrame:SetPoint("BOTTOMLEFT", root, "TOPLEFT", cox, coy)
                else
                    castFrame:SetPoint("TOPLEFT", mpBg, "BOTTOMLEFT", cox, -gap + coy)
                end
                -- Debuff row stays at the user's anchor/offset; it must not follow cast state
                -- (end/interrupt paths do not all re-run applySize, which left it shifted).
                self._debuffYExtra = 0
            end

            castFrame:SetWidth(castW)
            castFrame:SetHeight(castH)

            local lockedBar = self._castLocked and true or false
            -- Caps stay 1:1. Length only clips or stretches the straight middle.
            IchaUI_Cast_LayoutArt(self, castW, lockedBar)
            local insetL = self._castFillInsetL or 6
            local insetR = self._castFillInsetR or 6
            local insetY = self._castFillInsetY or 7
            local fillMax = self._castFillMax or 1
            if fillMax < 1 then fillMax = 1 end

            -- Interruptible: round icon on the left curve.
            -- Uninterruptible: icon sits in the shield hole at native texel size.
            local iconSz = 32
            self._castIconSz = iconSz
            -- Right edge of the spell icon in frame pixels. Text starts past this,
            -- not at the fill inset (that inset sits under the icon).
            local iconRight = insetL
            if lockedBar and fr.castSpellIcon and castBorder then
                if fr.castIconHolder then fr.castIconHolder:Hide() end
                if fr.castSpark then fr.castSpark:Hide() end
                if castLag then castLag:Hide() end
                fr.castSpellIcon:ClearAllPoints()
                fr.castSpellIcon:SetWidth(16)
                fr.castSpellIcon:SetHeight(16)
                fr.castSpellIcon:SetPoint("CENTER", castFrame, "LEFT", 17, 1)
                fr.castSpellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                iconRight = 17 + 8
                if showCast then fr.castSpellIcon:Show() else fr.castSpellIcon:Hide() end
            else
                if fr.castSpellIcon then fr.castSpellIcon:Hide() end
                if fr.castIconHolder then
                    fr.castIconHolder:SetFrameLevel((castFrame:GetFrameLevel() or 1) + 8)
                    fr.castIconHolder:ClearAllPoints()
                    local iconX = math.floor(iconSz * 0.32 + 0.5)
                    fr.castIconHolder:SetPoint("CENTER", castFrame, "LEFT", iconX, 0)
                    iconRight = iconX + math.floor(iconSz / 2)
                    IchaUI_Cast_LayoutIcon(fr, iconSz, false)
                    if showCast then fr.castIconHolder:Show() else fr.castIconHolder:Hide() end
                end
            end
            if castTextPlate then
                castTextPlate:SetFrameLevel((castFrame:GetFrameLevel() or 1) + 12)
            end

            -- Channel bg + fill + lag (StatusBar), gold / dark / red.
            -- Regular bar: empty track meets the inner border. Gold fill keeps insets.
            -- Shield: same track height as interruptible (4px Y); keep left/right insets.
            if castBg then
                castBg:SetTexture(IchaUI_CAST_FILL)
                castBg:ClearAllPoints()
                local bgTop = 4
                local bgH = (castH or 22) - (bgTop * 2)
                if bgH < 1 then bgH = 1 end
                if lockedBar then
                    IchaUI_SeatCastFill(castBg, castFrame, insetL, -bgTop, math.max(0.001, fillMax), bgH)
                else
                    castBg:SetPoint("TOPLEFT", castFrame, "TOPLEFT", 3, -bgTop)
                    castBg:SetPoint("BOTTOMRIGHT", castFrame, "BOTTOMRIGHT", -4, bgTop)
                    if castBg.SetHeight then castBg:SetHeight(bgH) end
                end
                -- 1.12 keeps UI-StatusBar at file height unless texcoords are non-identity.
                if castBg.SetTexCoord then
                    castBg:SetTexCoord(0.5 / 256, 1 - (0.5 / 256), 0.5 / 32, 1 - (0.5 / 32))
                end
                castBg:SetVertexColor(0.08, 0.07, 0.06, 1)
                castBg:Show()
            end
            IchaUIUF_ApplyBarFill(castFill, (IchaUIUF_BarFillPath and IchaUIUF_BarFillPath(textKindForKey(key), "cast")) or IchaUI_CAST_FILL)
            local fillH = castH - (insetY * 2)
            if fillH < 1 then fillH = 1 end
            self._castFillX = insetL
            self._castFillY = -insetY
            self._castFillH = fillH
            IchaUI_SeatCastFill(castFill, castFrame, insetL, -insetY, math.max(0.001, fillMax), fillH)
            if IchaUI_PaintGoldVertex then
                IchaUI_PaintGoldVertex(castFill, CAST_GOLD[1], CAST_GOLD[2], CAST_GOLD[3], 1, true)
            else
                IchaUI_PaintGoldVertex(castFill, CAST_GOLD[1], CAST_GOLD[2], CAST_GOLD[3], 1, true)
            end
            if lockedBar then
                if castLag then castLag:Hide() end
            elseif castLag then
                castLag:SetTexture(IchaUI_CAST_FILL)
                IchaUI_Cast_PlaceLag(self, self._castLagW or 0, false)
            end

            if fr.castSpark then
                fr.castSpark:SetWidth(32)
                fr.castSpark:SetHeight(32)
                if lockedBar then fr.castSpark:Hide() end
            end

            castTime:ClearAllPoints()
            local lagOff = insetR + 4
            if (self._castLagW or 0) >= 2 then
                lagOff = insetR + (self._castLagW or 0) + 2
            end
            castTime:SetPoint("RIGHT", castFrame, "RIGHT", -lagOff, 0)
            castTime:SetWidth(40)
            -- Small gap after the icon. Also stay inside the fill channel so
            -- the shield rim is not covered. Length only shortens the right.
            local nameGap = 4
            local nameLeft = iconRight + nameGap
            if insetL + nameGap > nameLeft then nameLeft = insetL + nameGap end
            castName:ClearAllPoints()
            castName:SetPoint("LEFT", castFrame, "LEFT", nameLeft, 0)
            castName:SetPoint("RIGHT", castTime, "LEFT", -4, 0)
            local namePx = castW - nameLeft - lagOff - 40 - 4
            if namePx < 8 then namePx = 8 end
            self._castNameMaxW = namePx
            self._castNameChars = math.floor(namePx / 6)
            if self._castNameChars < 2 then self._castNameChars = 2 end
            -- Keep fillMax from insets above — do NOT widen to barW-iconSz (overhangs border)
            self._castIconSz = iconSz

            if showCast then
                if castBg then castBg:Show() end
                if castFill then castFill:Show() end
                IchaUI_Cast_ShowArt(self)
                castFrame:Show()
            else
                IchaUI_Cast_HidePieces(self)
            end
        end
        self._barW = barW
        local aScale = 1.0
        do
            local d = db()
            aScale = tonumber(d.auraIconScale) or 1.0
            if aScale < 0.5 then aScale = 0.5 end
            if aScale > 2.0 then aScale = 2.0 end
        end
        -- Keep 4:3 action-bar aspect (do not force square)
        local auraTs = loadTextSettings(textKindForKey(key))
        local padForRow = tonumber(auraTs.buffPad) or AURA_PAD
        if padForRow < 0 then padForRow = 0 end
        self._buffPad = tonumber(auraTs.buffPad) or AURA_PAD
        self._debuffPad = tonumber(auraTs.debuffPad) or AURA_PAD
        self._buffScale = clamp(tonumber(auraTs.buffScale) or 1, 0.4, 3)
        self._debuffScale = clamp(tonumber(auraTs.debuffScale) or 1, 0.4, 3)
        self._buffOffsetX = clamp(tonumber(auraTs.buffOffsetX) or 0, -80, 80)
        self._buffOffsetY = clamp(tonumber(auraTs.buffOffsetY) or 0, -80, 80)
        self._debuffOffsetX = clamp(tonumber(auraTs.debuffOffsetX) or 0, -80, 80)
        self._debuffOffsetY = clamp(tonumber(auraTs.debuffOffsetY) or 0, -80, 80)
        self._buffAnchor = IchaUI_ValidAuraAnchor(auraTs.buffAnchor or "TOPLEFT")
        self._debuffAnchor = IchaUI_ValidAuraAnchor(auraTs.debuffAnchor or "BOTTOMLEFT")
        self._awBuff = math.floor(AURA_W * self.scale * aScale * self._buffScale + 0.5)
        self._ahBuff = math.floor(AURA_H * self.scale * aScale * self._buffScale + 0.5)
        self._awDebuff = math.floor(AURA_W * self.scale * aScale * self._debuffScale + 0.5)
        self._ahDebuff = math.floor(AURA_H * self.scale * aScale * self._debuffScale + 0.5)
        if self._awBuff < 2 then self._awBuff = 2 end
        if self._ahBuff < 2 then self._ahBuff = 2 end
        if self._awDebuff < 2 then self._awDebuff = 2 end
        if self._ahDebuff < 2 then self._ahDebuff = 2 end
        -- _aw/_ah = buff sizes for backward compat; perRow uses max icon width
        self._aw = self._awBuff
        self._ah = self._ahBuff
        local rowW = self._awBuff
        if self._awDebuff > rowW then rowW = self._awDebuff end
        local perRow = math.floor(barW / (rowW + padForRow))
        if perRow < 1 then perRow = 1 end
        self._perRow = perRow
        self._maxAuras = math.min(MAX_AURA_SLOTS, perRow * 2)
        -- Cast bar show/hide changes _debuffYExtra. Re-seat shown DoTs; never rebuild.
        do
            local y = self._debuffYExtra or 0
            if self._debuffYLaid ~= y and self.debuffs and not self.raidCompact then
                self._debuffYLaid = y
                local shown = 0
                local i
                for i = 1, MAX_AURA_SLOTS do
                    if self.debuffs[i] and self.debuffs[i]:IsShown() then
                        shown = i
                    end
                end
                if shown > 0 then
                    layoutAuraGrid(
                        self.debuffs, shown, self._debuffPerRow or self._perRow or 8,
                        self._awDebuff or self._aw or AURA_W,
                        self._ahDebuff or self._ah or AURA_H,
                        root, false, y,
                        self._debuffPad or AURA_PAD,
                        self._debuffOffsetX or self._debuffOx or 0,
                        self._debuffOffsetY or self._debuffOy or 0,
                        self._debuffAnchor
                    )
                end
            end
        end
        if IchaUI_UpdateUnitRaidMark then IchaUI_UpdateUnitRaidMark(self) end; if IchaUI_UpdateUnitRoleIcons then IchaUI_UpdateUnitRoleIcons(self) end
    end

    local function paintAura(icon, texture, count, ringR, ringG, ringB, ringA, auraUnit, auraIndex, auraKind, timeLeft)
        if not icon then return end
        local tex = normalizeAuraTexture(texture)
        if not tex then
            tex = "Interface\\Icons\\INV_Misc_QuestionMark"
        end
        count = tonumber(count) or 0
        if count < 0 then count = 0 end
        ringR = ringR or 0.85
        ringG = ringG or 0.85
        ringB = ringB or 0.85
        ringA = ringA or 0
        -- Same spell still in this slot: do not SetTexture / Hide+Show / restart the timer.
        local same = (icon._auraTex == tex and icon._auraKind == auraKind and icon:IsShown())
        if not same then
            icon.tex:SetTexture(tex)
            if not icon.tex:GetTexture() then
                icon.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end
            -- SetTexture restores the file size; pin again so the art fills the button.
            IchaUI_PinAuraTex(icon)
            icon._auraTex = tex
            icon._auraKind = auraKind
        end
        -- Applications only. Never the slot index, and never a previous aura's number.
        if icon.count then
            if count > 1 then
                if icon._auraCount ~= count then
                    icon.count:SetText(tostring(math.floor(count)))
                    icon._auraCount = count
                end
                icon.count:Show()
            else
                icon.count:SetText("")
                icon.count:Hide()
                icon._auraCount = nil
            end
        end
        local colKey = tostring(ringR) .. ":" .. tostring(ringG) .. ":" .. tostring(ringB) .. ":" .. tostring(ringA) .. ":" .. tostring(auraKind)
        if icon._auraCol ~= colKey then
            icon._auraCol = colKey
            -- Debuffs: border matches effect type (poison/disease/magic/curse/bleed).
            -- Buffs keep gold chrome. No inner glow.
            if icon.border then
                if auraKind == "debuff" and ringA and ringA > 0.5 then
                    icon.border:SetBackdropBorderColor(ringR, ringG, ringB, 1)
                else
                    IchaUI_PaintGoldBorder(icon.border, GOLD[4])
                end
            end
            if icon.ring then
                icon.ring:SetAlpha(0)
                icon.ring:Hide()
            end
        end
        icon.auraUnit = auraUnit
        icon.auraIndex = auraIndex
        icon.auraKind = auraKind
        local now = GetTime and GetTime() or 0
        -- Debuffs: restart the clock only when apply start is new (true reapply).
        local applyStart = nil
        if auraKind == "debuff" and auraUnit then
            local ck = auraCacheKey(auraUnit, nil, tex, nil)
            local e = ck and auraTimeCache[ck]
            -- applied also moves on Molten Blast (duration change, same start)
            if e then applyStart = e.applied or e.start end
        end
        if auraKind == "debuff" then
            local sameApply = same and icon._auraApplied and applyStart and icon._auraApplied == applyStart
            if not sameApply then
                icon._auraApplied = applyStart
                if timeLeft and timeLeft > 0 then
                    icon.expires = now + timeLeft
                    if icon.timer then
                        icon.timer:SetText(formatAuraTime(timeLeft))
                        icon.timer:SetTextColor(1, 0.92, 0.65)
                        icon.timer:Show()
                    end
                elseif not same then
                    icon.expires = nil
                    if icon.timer then
                        icon.timer:SetText("")
                        icon.timer:Hide()
                    end
                end
            end
        elseif timeLeft and timeLeft > 0 then
            local newExp = now + timeLeft
            if same and icon.expires and icon.expires > now then
                local oldLeft = icon.expires - now
                if timeLeft > oldLeft + 0.75 then
                    icon.expires = newExp
                    if icon.timer then
                        icon.timer:SetText(formatAuraTime(timeLeft))
                        icon.timer:SetTextColor(1, 0.92, 0.65)
                        icon.timer:Show()
                    end
                end
            else
                icon.expires = newExp
                if icon.timer then
                    icon.timer:SetText(formatAuraTime(timeLeft))
                    icon.timer:SetTextColor(1, 0.92, 0.65)
                    icon.timer:Show()
                end
            end
        elseif not same then
            icon.expires = nil
            if icon.timer then
                icon.timer:SetText("")
                icon.timer:Hide()
            end
        end
    end

    function fr:updateCast()
        if self.raidCompact then
            IchaUI_Cast_HidePieces(self)
            self._casting = nil
            return
        end
        if IchaUIUF_CastBarOn and not IchaUIUF_CastBarOn(textKindForKey(key)) then
            self._testCastStart = nil
            self._casting = false
            self._castLocked = false
            IchaUI_Cast_HidePieces(self)
            return
        end
        -- Player + target cast bars (own bar under power; never replace mana)
        local nowSec = GetTime and GetTime() or 0
        local wasShown = castFrame:IsShown() and true or false

        -- Canceled cast (fishing shield): ignore stale info and do not start a sample.
        if (self._castQuenchUntil or 0) > nowSec then
            local fresh = false
            if unit and unit ~= "" and unit ~= "none" and string.sub(unit, 1, 6) ~= "IchaUI" then
                local infoQ = getCastInfo(unit)
                local startQ = infoQ and tonumber(infoQ.start) or 0
                local finQ = infoQ and tonumber(infoQ.finish) or 0
                if infoQ and finQ > (nowSec * 1000) and startQ > (self._castQuenchMark or 0) + 50 then
                    fresh = true
                    self._castQuenchUntil = 0
                end
            end
            if not fresh then
                self._testCastStart = nil
                self._castLocked = false
                if (self._interruptedUntil or 0) > nowSec then
                    return
                end
                IchaUI_Cast_HidePieces(self)
                self._casting = false
                return
            end
        end

        -- Test / preview: loop a sample cast on this frame's real bar.
        -- Preview rows often have no unit, so this runs before the ownership gate.
        -- Odd cycles use the uninterruptible shield chrome; even cycles the normal bar.
        local previewCast = (testMode or self._forcePreview) and true or false
        if previewCast then
            local realLive = false
            if not badUnitToken(unit) then
                local real = getCastInfo(unit)
                if real and real.finish then
                    local fin = tonumber(real.finish) or 0
                    if fin > (nowSec * 1000) then realLive = true end
                end
            end
            if realLive then
                self._testCastStart = nil
            else
                if not self._testCastStart then
                    self._testCastStart = nowSec
                    if not self._testCastN then self._testCastN = 0 end
                end
                local elapsed = nowSec - self._testCastStart
                if elapsed >= TEST_CAST_DUR then
                    self._testCastStart = nowSec
                    elapsed = 0
                    self._testCastN = (self._testCastN or 0) + 1
                end
                local locked = false
                if math.mod(self._testCastN or 0, 2) == 1 then locked = true end
                local was = self._casting
                local wasLocked = self._castLocked and true or false
                self._casting = true
                self._interruptedUntil = 0
                self._castLocked = locked
                if (not was) or (wasLocked ~= locked) then
                    self:applySize()
                end
                local maxW = self._castFillMax or 1
                if maxW < 1 then maxW = 1 end
                local pct = 0
                if TEST_CAST_DUR > 0 then
                    pct = elapsed / TEST_CAST_DUR
                end
                if pct < 0 then pct = 0 end
                if pct > 1 then pct = 1 end
                local lagW = 0
                if not locked then
                    local durMs = TEST_CAST_DUR * 1000
                    if durMs > 0 then
                        lagW = maxW * (150 / durMs)
                        if lagW > maxW * 0.35 then lagW = maxW * 0.35 end
                    end
                end
                self._castLagW = lagW
                castInterrupt:Hide()
                castName:Show()
                IchaUI_FitSpellName(castName, "Test Cast", self._castNameMaxW or 80)
                IchaUI_SeatCastFill(castFill, castFrame, self._castFillX or 6, self._castFillY or -7, math.max(0.001, maxW * pct), self._castFillH or 8)
                IchaUI_PaintGoldVertex(castFill, CAST_GOLD[1], CAST_GOLD[2], CAST_GOLD[3], 1, true)
                if castFill then castFill:Show() end
                if castBg then castBg:Show() end
                IchaUI_Cast_ShowArt(self)
                if locked then
                    if fr.castSpellIcon then
                        fr.castSpellIcon:SetTexture(TEST_BUFF_TEX)
                        fr.castSpellIcon:Show()
                    end
                    if castIconHolder then castIconHolder:Hide() end
                    if castLag then castLag:Hide() end
                    if self.castSpark then self.castSpark:Hide() end
                else
                    castIcon:SetTexture(TEST_BUFF_TEX)
                    if fr.castSpellIcon then fr.castSpellIcon:Hide() end
                    castIcon:Show()
                    if castIconHolder then castIconHolder:Show() end
                    IchaUI_Cast_LayoutIcon(self, self._castIconSz, false)
                    IchaUI_Cast_PlaceSpark(self, maxW * pct)
                    if castLag then
                        castLag:SetTexture(IchaUI_CAST_FILL)
                        IchaUI_Cast_PlaceLag(self, lagW, false)
                    end
                end
                if castTime then
                    local remain = TEST_CAST_DUR - elapsed
                    if remain < 0 then remain = 0 end
                    if remain >= 10 then
                        castTime:SetText(string.format("%.0f", remain))
                    else
                        castTime:SetText(string.format("%.1f", remain))
                    end
                    castTime:SetTextColor(1, 0.95, 0.85)
                    castTime:ClearAllPoints()
                    local ir = self._castFillInsetR or 0
                    local lagOff = ir + 4
                    if (not locked) and lagW >= 2 then
                        lagOff = ir + lagW + 2
                    end
                    castTime:SetPoint("RIGHT", castFrame, "RIGHT", -lagOff, 0)
                    castTime:Show()
                end
                castFrame:Show()
                -- Cast bar show/hide must not rebuild debuff icons.
                return
            end
        else
            self._testCastStart = nil
            self._testCastN = nil
        end

        -- One cast bar per person (player owns self; target owns current target)
        if not castOwnedByThisFrame(key, unit) then
            IchaUI_Cast_HidePieces(self)
            self._casting = nil
            return
        end

        -- If a new cast already started, drop Interrupted immediately
        local earlyInfo = getCastInfo(unit)
        if earlyInfo and IchaUI_Cast_IsLockLeftover(self, earlyInfo, nowSec) then
            earlyInfo = nil
        end
        if earlyInfo and earlyInfo.finish and earlyInfo.finish > 0 then
            if (self._interruptedUntil or 0) > 0 then
                self._interruptedUntil = 0
                castInterrupt:Hide()
                castName:Show()
            end
        elseif (self._castLockExpire or 0) > nowSec then
            self._interruptedUntil = 0
        elseif (self._interruptedUntil or 0) > nowSec then
            -- Hold red Interrupted overlay briefly (only if nothing else is casting)
            self._casting = false
            castInterrupt:Show()
            castName:Hide()
            if castTime then castTime:Hide() end
            if castLag then castLag:Hide() end
            if self.castSpark then self.castSpark:Hide() end
            castFill:SetVertexColor(0.7, 0.1, 0.1)
            IchaUI_PaintGoldVertex(castBorder, 0.96, 0.70, 0.06, 1)
            if not wasShown then self:applySize() end
            if castFill then castFill:Show() end
            if castBg then castBg:Show() end
            IchaUI_Cast_ShowArt(self)
            castFrame:Show()
            return
        elseif (self._interruptedUntil or 0) > 0 then
            self._interruptedUntil = 0
            castInterrupt:Hide()
            castName:Show()
            self:applySize()
        end

        local info = getCastInfo(unit)
        local was = self._casting
        local now = nowSec * 1000
        -- Drop stale entries (ClassicAPI can linger briefly after interrupt)
        if info and info.finish and now >= (tonumber(info.finish) or 0) then
            info = nil
        end
        if info and IchaUI_Cast_IsLockLeftover(self, info, nowSec) then
            info = nil
        end
            if info and info.finish and info.finish > 0 then
            self._casting = true
            self._interruptedUntil = 0
            castInterrupt:Hide()
            castName:Show()
            local locked = info.locked and true or false
            local chromeChanged = (self._castLocked and true or false) ~= locked
            self._castLocked = locked
            if locked then
                self._castLockName = info.name or ""
                self._castLockStart = tonumber(info.start) or 0
                self._castLockExpire = 0
            end
            if not was or chromeChanged then self:applySize() end
            -- applySize may be first chance to compute fill width
            if not self._castFillMax or self._castFillMax < 1 then
                self:applySize()
            end
            IchaUI_FitSpellName(castName, info.name or "", self._castNameMaxW or (castName:GetWidth() or 80))
            local tex = info.texture or "Interface/Icons/INV_Misc_QuestionMark"
            castIcon:SetTexture(tex)
            if fr.castSpellIcon then
                fr.castSpellIcon:SetTexture(tex)
            end
            castIcon:Show()
            if locked then
                if castIconHolder then castIconHolder:Hide() end
                if fr.castSpellIcon then fr.castSpellIcon:Show() end
                if castLag then castLag:Hide() end
            else
                if castIconHolder then castIconHolder:Show() end
                if fr.castSpellIcon then fr.castSpellIcon:Hide() end
            end
            local start = tonumber(info.start) or 0
            local finish = tonumber(info.finish) or 0
            if finish <= start then
                if castFill then castFill:Show() end
                if castBg then castBg:Show() end
                IchaUI_Cast_ShowArt(self)
                castFrame:Show()
                -- Cast bar show/hide must not rebuild debuff icons.
                return
            end
            local lagMs = 0
            local outgoing = (unit == "player")
            if (not outgoing) and unit and UnitIsUnit then
                local okU, sameU = pcall(UnitIsUnit, unit, "player")
                outgoing = okU and sameU and true or false
            end
            if outgoing and not info.channel then
                lagMs = getCastLatencyMs()
            end
            self._castDispLag = lagMs
            local pct, dur = IchaUI_Cast_Progress(self, info, now)
            if dur <= 0 then dur = finish - start end
            local lagFrac = 0
            if dur > 0 and lagMs > 0 then
                lagFrac = lagMs / dur
                if lagFrac > 0.35 then lagFrac = 0.35 end
            end
            -- Same cast: never draw backward (SUCCESS leftover / late START / pin).
            local holdKey = tostring(info.spellId or "") .. "\t" .. tostring(info.name or "")
            if info.channel then holdKey = "c:" .. holdKey end
            if self._castHoldKey == holdKey then
                if pct < (self._castHoldPct or 0) then pct = self._castHoldPct end
            else
                self._castHoldKey = holdKey
                self._castHoldPct = 0
            end
            if pct > (self._castHoldPct or 0) then self._castHoldPct = pct end
            local maxW = self._castFillMax or 1
            local lagW = maxW * lagFrac
            self._castLagW = lagW
            if pct < 0 then pct = 0 end
            if pct > 1 then pct = 1 end
            IchaUI_SeatCastFill(castFill, castFrame, self._castFillX or 6, self._castFillY or -7, math.max(0.001, maxW * pct), self._castFillH or 8)
            if castFill then castFill:Show() end
            if castBg then castBg:Show() end
            local sparkW = maxW * pct
            if outgoing and (not info.channel) and lagW >= 4 then
                local safeW = maxW - lagW
                if safeW > 0 and sparkW > safeW then sparkW = safeW end
            end
            IchaUI_Cast_PlaceSpark(self, sparkW)
            local remain = (finish - now) / 1000
            if remain < 0 then remain = 0 end
            if castTime then
                if remain >= 10 then
                    castTime:SetText(string.format("%.0f", remain))
                else
                    castTime:SetText(string.format("%.1f", remain))
                end
                castTime:SetTextColor(1, 0.95, 0.85)
                castTime:Show()
            end
            if locked then
                if castLag then castLag:Hide() end
            elseif castLag then
                castLag:SetTexture(IchaUI_CAST_FILL)
                IchaUI_Cast_PlaceLag(self, lagW, info.channel)
            end
            -- Keep countdown left of the red lag strip (normal casts); channels leave right edge
            if castTime then
                castTime:ClearAllPoints()
                local ir = self._castFillInsetR or 0
                local lagOff = ir + 4
                if lagW >= 2 and not info.channel then
                    lagOff = ir + lagW + 2
                end
                castTime:SetPoint("RIGHT", castFrame, "RIGHT", -lagOff, 0)
            end
            self._castLocked = locked
            if locked then
                IchaUI_PaintGoldVertex(castFill, CAST_GOLD[1], CAST_GOLD[2], CAST_GOLD[3], 1, true)
                IchaUI_PaintGoldVertex(castBorder, 0.96, 0.70, 0.06, 1)
            elseif info.channel then
                castFill:SetVertexColor(0.4, 0.7, 1.0)
                IchaUI_PaintGoldVertex(castBorder, 0.96, 0.70, 0.06, 1)
            else
                IchaUI_PaintGoldVertex(castFill, CAST_GOLD[1], CAST_GOLD[2], CAST_GOLD[3], 1, true)
                IchaUI_PaintGoldVertex(castBorder, 0.96, 0.70, 0.06, 1)
            end
            IchaUI_Cast_ShowArt(self)
            castFrame:Show()
        else
            local wasLocked = self._castLocked and true or false
            self._casting = false
            IchaUI_Cast_ClearPin(self)
            if wasLocked then
                self._castLockExpire = nowSec + 1.25
                self._interruptedUntil = 0
            end
            self._castLocked = false
            self._castLagW = 0
            if (self._interruptedUntil or 0) <= nowSec then
                IchaUI_Cast_HidePieces(self)
                castName:Show()
                -- Cast end: keep shown debuffs; applySize shifts Y only.
            end
            if was or wasLocked then self:applySize() end
        end
    end

    function fr:markInterrupted()
        local wasShown = castFrame:IsShown() and true or false
        if not self._casting and not wasShown then return end
        local wasLocked = self._castLocked and true or false
        local nowHold = GetTime and GetTime() or 0
        self._casting = false
        self._castLagW = 0
        IchaUI_Cast_ClearPin(self)
        -- Uninterruptible chrome is the whole bar. Cancelling it hides;
        -- swapping in the normal border looks like a second cast bar.
        if wasLocked or (self._castLockExpire or 0) > nowHold then
            self._castLocked = false
            self._interruptedUntil = 0
            self._castLockExpire = nowHold + 1.25
            IchaUI_Cast_HidePieces(self)
            self:applySize()
            return
        end
        self._castLocked = false
        self._interruptedUntil = nowHold + 1.2
        castInterrupt:Show()
        castName:Hide()
        if castTime then castTime:Hide() end
        if castLag then castLag:Hide() end
        if self.castSpark then self.castSpark:Hide() end
        if fr.castSpellIcon then fr.castSpellIcon:Hide() end
        castFill:SetVertexColor(0.75, 0.1, 0.1)
        IchaUI_SeatCastFill(castFill, castFrame, self._castFillX or 6, self._castFillY or -7, math.max(0.001, self._castFillMax or 1), self._castFillH or 8)
        IchaUI_PaintGoldVertex(castBorder, 0.96, 0.70, 0.06, 1)
        self:applySize()
        if castFill then castFill:Show() end
        if castBg then castBg:Show() end
        IchaUI_Cast_ShowArt(self)
        castFrame:Show()
    end

    function fr:updatePvP()
        local unitMissing = (not unit or unit == "" or unit == "none" or string.sub(unit, 1, 6) == "IchaUI")
        if not unitMissing then
            local ok, exists = pcall(UnitExists, unit)
            unitMissing = not (ok and exists)
        end
        if unitMissing then
            pvpIcon:Hide()
            return
        end
        local flagged = false
        if UnitIsPVP and UnitIsPVP(unit) then flagged = true end
        if UnitIsPVPFreeForAll and UnitIsPVPFreeForAll(unit) then flagged = true end
        if flagged then
            local faction = UnitFactionGroup and UnitFactionGroup(unit)
            -- Packaged from wow-ui-textures PVPFrame currency icons
            if faction == "Horde" then
                pvpIcon:SetTexture("Interface\\AddOns\\IchaUI\\media\\PVPCurrencyHorde.tga")
            else
                -- Alliance (and unknown) use Alliance currency icon
                pvpIcon:SetTexture("Interface\\AddOns\\IchaUI\\media\\PVPCurrencyAlliance.tga")
            end
            pvpIcon:Show()
        else
            pvpIcon:Hide()
        end

        -- Legacy rest icon retired — resting uses the combat/level badge (zzz).
        if self.restIcon then
            self.restIcon:Hide()
        end

        -- Player: combat swords > rest zzz (OOC) > Port level. Target/ToT/combat: Port level.
        if self.combatBadge then
            local showBadge = false
            local showCombat = false
            local showRest = false
            local showLevel = false
            local portOk = self.portraitEnabled ~= false and self.portraitFrame and self.portraitFrame:IsShown()
            if key == "player" then
                if portOk and unit == "player" then
                    if UnitAffectingCombat and UnitAffectingCombat("player") then
                        showBadge = true
                        showCombat = true
                    elseif IsResting and IsResting() then
                        showBadge = true
                        showRest = true
                    elseif IchaUI_LevelPortraitOn and IchaUI_LevelPortraitOn(key) then
                        showBadge = true
                        showLevel = true
                    end
                end
            elseif IchaUI_LevelCanPortrait and IchaUI_LevelCanPortrait(key) then
                if portOk and IchaUI_LevelPortraitOn(key) and not badUnitToken(unit) and UnitExists and UnitExists(unit) then
                    showBadge = true
                    showLevel = true
                end
            end
            if showBadge then
                self.combatBadge:Show()
                self.combatBadge:SetFrameStrata("MEDIUM")
                self.combatBadge:SetFrameLevel((root:GetFrameLevel() or 1) + 55)
                if self.combatBadgeBg then self.combatBadgeBg:Show() end
                if self.combatBadgeMask then self.combatBadgeMask:Hide() end
                if self.combatBadgeRing then self.combatBadgeRing:Show() end
                if self.combatBadgeTextLayer then
                    self.combatBadgeTextLayer:SetFrameLevel((self.combatBadge:GetFrameLevel() or 1) + 10)
                end
            else
                self.combatBadge:Hide()
            end
            if self.combatIcon then
                if showCombat then
                    -- Crossed swords (UI-StateIcon)
                    self.combatIcon:SetTexCoord(0.5, 1.0, 0.0, 0.5)
                    self.combatIcon:Show()
                elseif showRest then
                    -- Resting ZZZ (same sheet, left half)
                    self.combatIcon:SetTexCoord(0.0, 0.5, 0.0, 0.421875)
                    self.combatIcon:Show()
                else
                    self.combatIcon:Hide()
                end
            end
            if showLevel and self.levelText then
                IchaUI_PaintPortraitLevel(self.levelText, unit, self.combatBadgeRing)
            elseif self.combatBadgeRing then
                IchaUI_PaintGoldRing(self.combatBadgeRing)
            end
            if self.levelText then
                if showLevel then self.levelText:Show() else self.levelText:Hide() end
            end
        end
    end

    function fr:updateAuras()
        local function finishAuras()
            if self.updateShieldCharges then self:updateShieldCharges() end
        end
        local buffPad = tonumber(self._buffPad) or AURA_PAD
        local debuffPad = tonumber(self._debuffPad) or AURA_PAD
        local buffScale, debuffScale = 1, 1
        local buffOx, buffOy, debuffOx, debuffOy = 0, 0, 0, 0
        local buffAnchor, debuffAnchor = "TOPLEFT", "BOTTOMLEFT"
        do
            local ts = loadTextSettings(textKindForKey(key))
            buffPad = tonumber(ts.buffPad) or buffPad
            debuffPad = tonumber(ts.debuffPad) or debuffPad
            buffScale = tonumber(ts.buffScale) or 1
            debuffScale = tonumber(ts.debuffScale) or 1
            buffOx = tonumber(ts.buffOffsetX) or 0
            buffOy = tonumber(ts.buffOffsetY) or 0
            debuffOx = tonumber(ts.debuffOffsetX) or 0
            debuffOy = tonumber(ts.debuffOffsetY) or 0
            buffAnchor = IchaUI_ValidAuraAnchor(ts.buffAnchor or "TOPLEFT")
            debuffAnchor = IchaUI_ValidAuraAnchor(ts.debuffAnchor or "BOTTOMLEFT")
            self._buffPad = buffPad
            self._debuffPad = debuffPad
            self._buffScale = buffScale
            self._debuffScale = debuffScale
            self._buffOx = buffOx
            self._buffOy = buffOy
            self._debuffOx = debuffOx
            self._debuffOy = debuffOy
            self._buffOffsetX = buffOx
            self._buffOffsetY = buffOy
            self._debuffOffsetX = debuffOx
            self._debuffOffsetY = debuffOy
            self._buffAnchor = buffAnchor
            self._debuffAnchor = debuffAnchor
            local function optInt(v, lo, hi)
                if v == nil then return nil end
                local n = math.floor(tonumber(v) or lo)
                if n < lo then n = lo end
                if n > hi then n = hi end
                return n
            end
            self._buffShownMax = optInt(ts.buffsShown, 0, 20)
            self._debuffShownMax = optInt(ts.debuffsShown, 0, 20)
            self._buffPerRow = optInt(ts.buffPerRow, 1, 20)
            self._debuffPerRow = optInt(ts.debuffPerRow, 1, 20)
        end

        -- Sizes: AURA_* * frameScale * globalAuraIconScale * per-kind scale
        local gScale = 1.0
        do
            local d = db()
            gScale = tonumber(d.auraIconScale) or 1.0
            if gScale < 0.5 then gScale = 0.5 end
            if gScale > 2.0 then gScale = 2.0 end
        end
        local fScale = self.scale or 1
        local baw = math.floor(AURA_W * fScale * gScale * buffScale + 0.5)
        local bah = math.floor(AURA_H * fScale * gScale * buffScale + 0.5)
        local daw = math.floor(AURA_W * fScale * gScale * debuffScale + 0.5)
        local dah = math.floor(AURA_H * fScale * gScale * debuffScale + 0.5)
        if baw < 2 then baw = 2 end
        if bah < 2 then bah = 2 end
        if daw < 2 then daw = 2 end
        if dah < 2 then dah = 2 end
        self._awBuff, self._ahBuff, self._awDebuff, self._ahDebuff = baw, bah, daw, dah
        self._aw, self._ah = baw, bah

        -- Debuff identity fingerprint: skip paint/layout when the set is unchanged.
        -- Buffs still update. Empty one-scan flicker (GCD UNIT_AURA) keeps last set
        -- for the SAME unit only — never keep another mob's icons.
        local doDebuffPaint = true
        local doDebuffLayout = true
        if not testMode and not self._forcePreview then
            local function currentDebuffFp()
                local u = self.unit or unit
                if badUnitToken(u) then return "" end
                local exists = false
                pcall(function()
                    if UnitExists and UnitExists(u) then exists = true end
                end)
                if not exists then return "" end
                local fk = "raid"
                if not self.raidCompact then
                    fk = textKindForKey(key)
                end
                local mineDeb = IchaUIUF_BuildMineDebuffMap(u)
                local parts = {}
                local di
                for di = 1, 16 do
                    local dname, dicon, dcount, dtype, caster, spellId = readDebuff(u, di, nil)
                    if not dicon then break end
                    local mine = IchaUIUF_DebuffIsMine(caster, dname, dicon, mineDeb)
                    if IchaUIUF_ShouldShowDebuff(fk, dname, spellId, mine, dtype) then
                        local t = normalizeAuraTexture(dicon) or "?"
                        t = string.lower(tostring(t))
                        t = string.gsub(t, "/", "\\")
                        table.insert(parts, t .. "#" .. tostring(tonumber(dcount) or 1))
                    end
                end
                local fp = ""
                local pi
                for pi = 1, table.getn(parts) do
                    if pi == 1 then
                        fp = parts[pi]
                    else
                        fp = fp .. "|" .. parts[pi]
                    end
                end
                return fp
            end
            local fp = currentDebuffFp()
            local uid = ""
            if not badUnitToken(self.unit or unit) then
                uid = unitIdentity(self.unit or unit) or ""
            end
            local yk = tostring(self._debuffYExtra or 0) .. ":" .. tostring(daw) .. ":" .. tostring(dah)
                .. ":" .. tostring(debuffPad) .. ":" .. tostring(debuffOx) .. ":" .. tostring(debuffOy)
                .. ":" .. tostring(debuffAnchor or "")
                .. ":" .. tostring(self._debuffPerRow or "")
                .. ":" .. tostring(self._debuffShownMax or "")
            if uid ~= (self._debuffUid or "") then
                self._debuffUid = uid
                self._debuffFp = nil
                self._debuffEmptyN = 2
            end
            if fp == "" and self._debuffFp and self._debuffFp ~= "" then
                self._debuffEmptyN = (self._debuffEmptyN or 0) + 1
                if self._debuffEmptyN < 2 then
                    fp = self._debuffFp
                end
            else
                self._debuffEmptyN = 0
            end
            -- Count caps change how many icons get painted; a layout-only pass would reuse the stale count.
            local capKey = tostring(self._maxAuras or "") .. ":" .. tostring(self._debuffShownMax or "")
            if capKey ~= self._debuffCapKey then
                self._debuffCapKey = capKey
                self._debuffFp = nil
            end
            if fp == self._debuffFp then
                if yk == self._debuffLay then
                    doDebuffPaint = false
                    doDebuffLayout = false
                else
                    doDebuffPaint = false
                    doDebuffLayout = true
                    self._debuffLay = yk
                end
            else
                self._debuffFp = fp
                self._debuffLay = yk
            end
        end

        local paintAuraAll = paintAura
        local function paintAura(icon, texture, count, ringR, ringG, ringB, ringA, auraUnit, auraIndex, auraKind, timeLeft)
            if (not doDebuffPaint) and auraKind == "debuff" then return end
            paintAuraAll(icon, texture, count, ringR, ringG, ringB, ringA, auraUnit, auraIndex, auraKind, timeLeft)
        end

        if not doDebuffPaint then
            local nowSkip = GetTime and GetTime() or 0
            local si
            local uNow = self.unit or unit
            for si = 1, MAX_AURA_SLOTS do
                local icon = self.debuffs and self.debuffs[si]
                if icon and icon:IsShown() then
                    if icon.auraUnit and uNow and icon.auraUnit ~= uNow then
                        local sameU = false
                        if (not badUnitToken(icon.auraUnit)) and (not badUnitToken(uNow)) and UnitIsUnit then
                            pcall(function()
                                if UnitIsUnit(icon.auraUnit, uNow) then sameU = true end
                            end)
                        end
                        if not sameU then
                            doDebuffPaint = true
                            doDebuffLayout = true
                        end
                    end
                    if (not doDebuffPaint) and icon.auraUnit and icon._auraTex then
                        local left = peekDebuffTimeLeft(icon.auraUnit, icon.auraIndex, nil, icon._auraTex, nil)
                        local ck = auraCacheKey(icon.auraUnit, nil, icon._auraTex, nil)
                        local e = ck and auraTimeCache[ck]
                        local stamp = e and (e.applied or e.start)
                        if stamp and icon._auraApplied ~= stamp then
                            icon._auraApplied = stamp
                            left = tonumber(left)
                            if left and left > 0 then
                                icon.expires = nowSkip + left
                                if icon.timer then
                                    icon.timer:SetText(formatAuraTime(left))
                                    icon.timer:SetTextColor(1, 0.92, 0.65)
                                    icon.timer:Show()
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Raid compact: filters on top of former mine-buffs + typed-debuffs scan
        if self.raidCompact then
            local root = self.root
            local unit = self.unit
            local filterKind = "raid"
            local perRow = 8
            local maxN = 16
            if self._buffPerRow then perRow = self._buffPerRow end
            local debuffPerRow = self._debuffPerRow or perRow
            if self._buffShownMax then maxN = self._buffShownMax end
            local maxDebuff = self._debuffShownMax or maxN
            local buffList = {}
            local debuffList = {}
            local function push(list, icon, count, rr, rg, rb, ra, aidx, kind, left)
                if not icon then return end
                local cap = maxN
                if list == debuffList then cap = maxDebuff end
                if table.getn(list) >= cap then return end
                table.insert(list, {
                    icon = icon, count = count or 1,
                    r = rr, g = rg, b = rb, a = ra,
                    aidx = aidx, kind = kind, left = left,
                })
            end
            local function raidDtypeColor(dt)
                if dt == "magic" then return 0.35, 0.55, 1.0, 1 end
                if dt == "poison" then return 0.2, 0.95, 0.15, 1 end
                if dt == "disease" then return 1.0, 0.92, 0.05, 1 end
                if dt == "curse" then return 0.7, 0.25, 0.95, 1 end
                return 0.85, 0.85, 0.85, 0.9
            end
            local raidMissing = badUnitToken(unit)
            if not raidMissing then
                local okExists, exists = pcall(UnitExists, unit)
                raidMissing = not (okExists and exists)
            end
            if testMode and raidMissing then
                if IchaUIUF_FiltersAllowAnyBuffs(filterKind) then
                    local ti
                    for ti = 1, 4 do
                        push(buffList, "Interface\\Icons\\Spell_Nature_Regeneration", 1, 0.3, 0.85, 0.35, 1, ti, "buff", nil)
                    end
                end
                if IchaUIUF_FiltersAllowAnyDebuffs(filterKind) then
                    push(debuffList, "Interface\\Icons\\Spell_Nature_NullifyPoison", 1, 0.2, 0.95, 0.15, 1, 1, "debuff", nil)
                    push(debuffList, "Interface\\Icons\\Spell_Holy_HarmUndeadAura", 1, 1.0, 0.92, 0.05, 1, 2, "debuff", nil)
                end
            elseif not raidMissing then
                local mineDeb = IchaUIUF_BuildMineDebuffMap(unit)
                local mineBuf = IchaUIUF_BuildMineBuffMap(unit)
                local di
                for di = 1, 16 do
                    local dname, dicon, dcount, dtype, caster, spellId = readDebuff(unit, di, nil)
                    if not dicon then break end
                    local mine = IchaUIUF_DebuffIsMine(caster, dname, dicon, mineDeb)
                    if IchaUIUF_ShouldShowDebuff(filterKind, dname, spellId, mine, dtype) then
                        local dt = dtypeKey(dtype)
                        local rr, rg, rb, ra = raidDtypeColor(dt)
                        local left = nil
                        if peekDebuffTimeLeft then
                            left = peekDebuffTimeLeft(unit, di, spellId, dicon, dname)
                        end
                        push(debuffList, dicon, dcount, rr, rg, rb, ra, di, "debuff", left)
                    end
                end
                local bi
                for bi = 1, 32 do
                    local bname, bicon, bcount, btype, bspell = readBuff(unit, bi)
                    if not bicon then break end
                    local mine = IchaUIUF_BuffIsMine(bname, bicon, mineBuf)
                    if IchaUIUF_ShouldShowBuff(filterKind, bname, bspell, mine) then
                        push(buffList, bicon, bcount, 0.35, 0.85, 0.45, 1, bi, "buff", nil)
                    end
                end
            end
            local nb = table.getn(buffList)
            local nd = table.getn(debuffList)
            local i
            for i = 1, maxN do
                if i <= nb then
                    local e = buffList[i]
                    paintAura(self.buffs[i], e.icon, e.count, e.r, e.g, e.b, e.a, unit, e.aidx, "buff", e.left)
                else
                    if self.buffs[i] then self.buffs[i]:Hide() end
                end
            end
            if doDebuffPaint then
                self._debuffShown = nd
                local debuffLoop = maxDebuff
                if maxN > debuffLoop then debuffLoop = maxN end
                for i = 1, debuffLoop do
                    if i <= nd then
                        local e = debuffList[i]
                        paintAura(self.debuffs[i], e.icon, e.count, e.r, e.g, e.b, e.a, unit, e.aidx, "debuff", e.left)
                    else
                        if self.debuffs[i] then self.debuffs[i]:Hide() end
                    end
                end
            else
                nd = self._debuffShown or nd
            end
            -- Separate anchors: only auto-stack if both share the same edge
            local bSide = buffAnchor or "BOTTOM"
            local dSide = debuffAnchor or "BOTTOM"
            local debuffLift = 0
            local sameEdge = false
            if bSide == dSide then
                sameEdge = true
            elseif (bSide == "BOTTOM" or bSide == "BOTTOMLEFT" or bSide == "BOTTOMRIGHT")
                and (dSide == "BOTTOM" or dSide == "BOTTOMLEFT" or dSide == "BOTTOMRIGHT") then
                sameEdge = true
            elseif (bSide == "TOP" or bSide == "TOPLEFT" or bSide == "TOPRIGHT")
                and (dSide == "TOP" or dSide == "TOPLEFT" or dSide == "TOPRIGHT") then
                sameEdge = true
            elseif (bSide == "LEFT") and (dSide == "LEFT") then
                sameEdge = true
            elseif (bSide == "RIGHT") and (dSide == "RIGHT") then
                sameEdge = true
            end
            if sameEdge and nb > 0 then
                local brows = math.floor((nb + perRow - 1) / perRow)
                if brows < 1 then brows = 1 end
                debuffLift = brows * (bah + buffPad) + 2
            end
            layoutAuraGridInset(self.buffs, nb, perRow, baw, bah, root, buffPad, buffOx, buffOy, bSide)
            if doDebuffLayout then
                layoutAuraGridInset(self.debuffs, nd, debuffPerRow, daw, dah, root, debuffPad, debuffOx, debuffOy + debuffLift, dSide)
            end
            if clearDispelGlow then clearDispelGlow(self) end
            finishAuras()
            return
        end

        -- show-all first; soft filters only
        local filterKind = textKindForKey(key)
        local mineBufMap = nil
        local mineDebMap = nil
        local function ensureMineMaps()
            if not mineBufMap then mineBufMap = IchaUIUF_BuildMineBuffMap(unit) end
            if not mineDebMap then mineDebMap = IchaUIUF_BuildMineDebuffMap(unit) end
        end

        local function paintTestAuras()
            local perRow = self._perRow or 8
            local maxN = self._maxAuras or (perRow * 2)
            local aw = self._aw or AURA_W
            local ah = self._ah or AURA_H
            local debuffY = self._debuffYExtra or 0
            local nb = 0
            if IchaUIUF_FiltersAllowAnyBuffs(filterKind) then
                nb = 4
                if nb > maxN then nb = maxN end
                local i
                for i = 1, nb do
                    paintAura(self.buffs[i], TEST_BUFF_TEX, (i == 2) and 3 or 1, 0.85, 0.85, 0.85, 0.55, nil, nil, nil, 12 - i)
                end
            end
            layoutAuraGrid(self.buffs, nb, perRow, baw, bah, root, true, 0, buffPad, buffOx, buffOy, buffAnchor)
            local nd = 0
            if IchaUIUF_FiltersAllowAnyDebuffs(filterKind) then
                nd = 4
                if nd > maxN then nd = maxN end
                local i
                for i = 1, nd do
                    local rr, rg, rb, ra = 0.75, 0.75, 0.75, 0.5
                    if i == 1 then rr, rg, rb, ra = 0.2, 0.95, 0.3, 0.95 end
                    if i == 2 then rr, rg, rb, ra = 0.35, 0.55, 1.0, 0.95 end
                    paintAura(self.debuffs[i], TEST_DEBUFF_TEX, 1, rr, rg, rb, ra, nil, nil, nil, 18 - i * 2)
                end
            end
            layoutAuraGrid(self.debuffs, nd, perRow, daw, dah, root, false, debuffY, debuffPad, debuffOx, debuffOy, debuffAnchor)
            clearDispelGlow(self)
        end

        local unitMissing = (not unit or unit == "" or unit == "none" or string.sub(unit, 1, 6) == "IchaUI")
        if not unitMissing then
            local ok, exists = pcall(UnitExists, unit)
            unitMissing = not (ok and exists)
        end
        if unitMissing then
            if testMode or self._forcePreview then
                if isPartyUnit(unit) then
                    local pr = self._perRow or 8
                    local mn = self._maxAuras or (pr * 2)
                    local aw0 = self._aw or AURA_W
                    local ah0 = self._ah or AURA_H
                    local nb = 0
                    if IchaUIUF_FiltersAllowAnyBuffs(filterKind) then
                        nb = 4
                        if nb > mn then nb = mn end
                        local i
                        for i = 1, nb do
                            paintAura(self.buffs[i], TEST_BUFF_TEX, (i == 2) and 3 or 1, 0.85, 0.85, 0.85, 0.55, nil, nil, nil, 12 - i)
                        end
                    end
                    local nd = 0
                    if IchaUIUF_FiltersAllowAnyDebuffs(filterKind) then
                        nd = 4
                        if nd > mn then nd = mn end
                        local i
                        for i = 1, nd do
                            local rr, rg, rb, ra = 0.75, 0.75, 0.75, 0.5
                            if i == 1 then rr, rg, rb, ra = 0.2, 0.95, 0.3, 0.95 end
                            if i == 2 then rr, rg, rb, ra = 0.35, 0.55, 1.0, 0.95 end
                            paintAura(self.debuffs[i], TEST_DEBUFF_TEX, 1, rr, rg, rb, ra, nil, nil, nil, 18 - i * 2)
                        end
                    end
                    layoutAuraSplitTop(self.buffs, nb, self.debuffs, nd, pr, baw, bah, root, mn, buffPad, debuffPad, buffOx, buffOy, debuffOx, debuffOy, daw, dah)
                    clearDispelGlow(self)
                else
                    paintTestAuras()
                end
            else
                layoutAuraGrid(self.buffs, 0, 1, baw, bah, root, true, 0, buffPad, buffOx, buffOy, buffAnchor)
                if doDebuffLayout then
                    layoutAuraGrid(self.debuffs, 0, 1, daw, dah, root, false, 0, debuffPad, debuffOx, debuffOy, debuffAnchor)
                    self._debuffShown = 0
                    self._debuffFp = ""
                end
                clearDispelGlow(self)
            end
            finishAuras()
            return
        end

        local perRow = self._buffPerRow or self._perRow or 8
        local debuffPerRow = self._debuffPerRow or perRow
        local maxBuff = self._maxAuras or (perRow * 2)
        if self._buffShownMax ~= nil then maxBuff = self._buffShownMax end
        local maxDebuff = self._maxAuras or (debuffPerRow * 2)
        if self._debuffShownMax ~= nil then maxDebuff = self._debuffShownMax end
        local maxN = maxBuff
        local aw = self._aw or AURA_W
        local ah = self._ah or AURA_H
        local debuffY = self._debuffYExtra or 0
        local watch = raidWatch()

        local function colorForDtype(dt)
            if dt == "poison" then return 0.15, 0.90, 0.20, 0.95 end
            if dt == "disease" then return 0.95, 0.88, 0.10, 0.95 end
            if dt == "magic" then return 0.25, 0.50, 1.00, 0.95 end
            if dt == "curse" then return 0.72, 0.28, 0.95, 0.95 end
            if dt == "bleed" then return 0.95, 0.12, 0.12, 0.95 end
            return 0.85, 0.85, 0.85, 0.75
        end

        local function classifyDebuff(dtype, dname)
            local dt = dtypeKey(dtype)
            if dt then return dt end
            if dname then
                local low = string.lower(dname)
                if string.find(low, "bleed", 1, true) then return "bleed" end
                if low == "rend" or low == "deep wounds" or low == "rupture"
                    or low == "garrote" or low == "rip" or low == "rake"
                    or low == "pounce" or low == "hemorrhage" then
                    return "bleed"
                end
                if string.find(low, "wound", 1, true) and not string.find(low, "poison", 1, true) then
                    return "bleed"
                end
            end
            return nil
        end

        -- ===== PARTY: buffs LEFT + debuffs RIGHT on TOP (split), grow UP =====
        if isPartyUnit(unit) then
            ensureMineMaps()
            local bShown = 0
            local bi
            for bi = 1, 32 do
                local bname, bicon, bcount, btype, bspell = readBuff(unit, bi)
                if not bicon then break end
                local mine = IchaUIUF_BuffIsMine(bname, bicon, mineBufMap)
                if IchaUIUF_ShouldShowBuff(filterKind, bname, bspell, mine) then
                    local dt = dtypeKey(btype)
                    local rr, rg, rb, ra = 0.85, 0.85, 0.85, 0.55
                    if dt == "magic" then rr, rg, rb, ra = 0.35, 0.55, 1.0, 0.95 end
                    bShown = bShown + 1
                    if bShown <= maxN then
                        local left = peekBuffTimeLeft(unit, bi)
                        paintAura(self.buffs[bShown], bicon, bcount, rr, rg, rb, ra, unit, bi, "buff", left)
                    end
                end
            end
            if bShown > maxN then bShown = maxN end

            local dShown = self._debuffShown or 0
            local hasPoison, hasDisease = false, false
            if doDebuffPaint then
                dShown = 0
                local di
                for di = 1, 16 do
                    local dname, dicon, dcount, dtype, caster, spellId = readDebuff(unit, di, nil)
                    if not dicon then break end
                    local mine = IchaUIUF_DebuffIsMine(caster, dname, dicon, mineDebMap)
                    if IchaUIUF_ShouldShowDebuff(filterKind, dname, spellId, mine, dtype) then
                        local dt = classifyDebuff(dtype, dname)
                        if dt == "poison" then hasPoison = true end
                        if dt == "disease" then hasDisease = true end
                        local rr, rg, rb, ra = colorForDtype(dt)
                        dShown = dShown + 1
                        if dShown <= maxDebuff then
                            local left = peekDebuffTimeLeft(unit, di, spellId, dicon, dname)
                            paintAura(self.debuffs[dShown], dicon, dcount, rr, rg, rb, ra, unit, di, "debuff", left)
                        end
                    end
                end
                if dShown > maxDebuff then dShown = maxDebuff end
                self._debuffShown = dShown
            end

            if testMode and bShown == 0 and dShown == 0 then
                if IchaUIUF_FiltersAllowAnyBuffs(filterKind) then
                    local nb = 4
                    if nb > maxN then nb = maxN end
                    local i
                    for i = 1, nb do
                        paintAura(self.buffs[i], TEST_BUFF_TEX, (i == 2) and 3 or 1, 0.85, 0.85, 0.85, 0.55, nil, nil, nil, 12 - i)
                    end
                    bShown = nb
                end
                if IchaUIUF_FiltersAllowAnyDebuffs(filterKind) then
                    local nd = 4
                    if nd > maxN then nd = maxN end
                    local i
                    for i = 1, nd do
                        local rr, rg, rb, ra = 0.75, 0.75, 0.75, 0.5
                        if i == 1 then rr, rg, rb, ra = 0.2, 0.95, 0.3, 0.95 end
                        if i == 2 then rr, rg, rb, ra = 0.35, 0.55, 1.0, 0.95 end
                        paintAura(self.debuffs[i], TEST_DEBUFF_TEX, 1, rr, rg, rb, ra, nil, nil, nil, 18 - i * 2)
                    end
                    dShown = nd
                end
            end

            -- Shared row = frame width, not "Buffs per row"; slot budget = frame, not "Buffs shown".
            layoutAuraSplitTop(self.buffs, bShown, self.debuffs, dShown, self._perRow or 8, baw, bah, root, self._maxAuras or ((self._perRow or 8) * 2), buffPad, debuffPad, buffOx, buffOy, debuffOx, debuffOy, daw, dah, self._buffPerRow, self._debuffPerRow)
            if hasPoison or hasDisease then
                if hasPoison then
                    setDispelGlow(self, 0.2, 0.95, 0.15, 1)
                else
                    setDispelGlow(self, 1.0, 0.92, 0.05, 1)
                end
            else
                clearDispelGlow(self)
            end
            finishAuras()
            return
        end

        -- ===== PLAYER: debuffs below + optional UF buffs via filters =====
        if unit == "player" then
            if testMode or self._forcePreview then
                local nb = 3
                if nb > maxN then nb = maxN end
                local i
                for i = 1, nb do
                    paintAura(self.buffs[i], TEST_BUFF_TEX, (i == 2) and 3 or 1, 0.85, 0.85, 0.85, 0.55, nil, nil, nil, 12 - i)
                end
                layoutAuraGrid(self.buffs, nb, perRow, baw, bah, root, true, 0, buffPad, buffOx, buffOy, buffAnchor)
                local nd = 3
                if nd > maxDebuff then nd = maxDebuff end
                for i = 1, nd do
                    local rr, rg, rb, ra = 0.75, 0.75, 0.75, 0.5
                    if i == 1 then rr, rg, rb, ra = 0.2, 0.95, 0.3, 0.95 end
                    if i == 2 then rr, rg, rb, ra = 0.35, 0.55, 1.0, 0.95 end
                    paintAura(self.debuffs[i], TEST_DEBUFF_TEX, 1, rr, rg, rb, ra, nil, nil, nil, 18 - i * 2)
                end
                layoutAuraGrid(self.debuffs, nd, debuffPerRow, daw, dah, root, false, debuffY, debuffPad, debuffOx, debuffOy, debuffAnchor)
                self._debuffShown = nd
                self._debuffFp = nil
                clearDispelGlow(self)
                finishAuras()
                return
            end
            ensureMineMaps()
            local bShown = 0
            if IchaUIUF_FiltersAllowAnyBuffs(filterKind) then
                local bi
                for bi = 1, 32 do
                    local bname, bicon, bcount, btype, bspell = readBuff(unit, bi)
                    if not bicon then break end
                    local mine = IchaUIUF_BuffIsMine(bname, bicon, mineBufMap)
                    if IchaUIUF_ShouldShowBuff(filterKind, bname, bspell, mine) then
                        local dt = dtypeKey(btype)
                        local rr, rg, rb, ra = 0.85, 0.85, 0.85, 0.55
                        if dt == "magic" then rr, rg, rb, ra = 0.35, 0.55, 1.0, 0.95 end
                        bShown = bShown + 1
                        if bShown <= maxN then
                            local left = peekBuffTimeLeft(unit, bi)
                            paintAura(self.buffs[bShown], bicon, bcount, rr, rg, rb, ra, unit, bi, "buff", left)
                        end
                    end
                end
                if bShown > maxN then bShown = maxN end
            end
            layoutAuraGrid(self.buffs, bShown, perRow, baw, bah, root, true, 0, buffPad, buffOx, buffOy, buffAnchor)

            local dShown = self._debuffShown or 0
            local hasPoison, hasDisease = false, false
            if doDebuffPaint then
                dShown = 0
                local di
                for di = 1, 16 do
                    local dname, dicon, dcount, dtype, caster, spellId = readDebuff(unit, di, nil)
                    if not dicon then break end
                    local mine = IchaUIUF_DebuffIsMine(caster, dname, dicon, mineDebMap)
                    if IchaUIUF_ShouldShowDebuff(filterKind, dname, spellId, mine, dtype) then
                        local dt = classifyDebuff(dtype, dname)
                        if dt == "poison" then hasPoison = true end
                        if dt == "disease" then hasDisease = true end
                        local rr, rg, rb, ra = colorForDtype(dt)
                        dShown = dShown + 1
                        if dShown <= maxDebuff then
                            local left = peekDebuffTimeLeft(unit, di, spellId, dicon, dname)
                            paintAura(self.debuffs[dShown], dicon, dcount, rr, rg, rb, ra, unit, di, "debuff", left)
                        end
                    end
                end
                if dShown > maxDebuff then dShown = maxDebuff end
                self._debuffShown = dShown
            end
            if doDebuffLayout then
                layoutAuraGrid(self.debuffs, dShown, debuffPerRow, daw, dah, root, false, debuffY, debuffPad, debuffOx, debuffOy, debuffAnchor)
            end
            if hasPoison or hasDisease then
                if hasPoison then
                    setDispelGlow(self, 0.2, 0.95, 0.15, 1)
                else
                    setDispelGlow(self, 1.0, 0.92, 0.05, 1)
                end
            else
                clearDispelGlow(self)
            end
            finishAuras()
            return
        end
        local combatPlate = key and string.find(key, "^combat")
        if not isTargetFrameUnit(unit) and not combatPlate then
            layoutAuraGrid(self.buffs, 0, 1, baw, bah, root, true, 0, buffPad, buffOx, buffOy, buffAnchor)
            if doDebuffLayout then
                layoutAuraGrid(self.debuffs, 0, 1, daw, dah, root, false, 0, debuffPad, debuffOx, debuffOy, debuffAnchor)
                self._debuffShown = 0
                self._debuffFp = ""
            end
            clearDispelGlow(self)
            finishAuras()
            return
        end

        local friendly = false
        local attackable = false
        if UnitIsFriend then
            local okF, rF = pcall(UnitIsFriend, "player", unit)
            if okF and rF then friendly = true end
        end
        if UnitCanAttack then
            local okA, rA = pcall(UnitCanAttack, "player", unit)
            if okA and rA then attackable = true end
        end

        -- ===== TARGET BUFFS (above): hostile all (filtered); skip friendly =====
        ensureMineMaps()
        local bShown = 0
        if attackable then
            local bi
            for bi = 1, 32 do
                local bname, bicon, bcount, btype, bspell = readBuff(unit, bi)
                if not bicon then break end
                local mine = IchaUIUF_BuffIsMine(bname, bicon, mineBufMap)
                if IchaUIUF_ShouldShowBuff(filterKind, bname, bspell, mine) then
                    local dt = dtypeKey(btype)
                    local rr, rg, rb, ra = 0.85, 0.85, 0.85, 0.55
                    if dt == "magic" then rr, rg, rb, ra = 0.35, 0.55, 1.0, 0.95 end
                    bShown = bShown + 1
                    if bShown <= maxN then
                        local left = peekBuffTimeLeft(unit, bi)
                        paintAura(self.buffs[bShown], bicon, bcount, rr, rg, rb, ra, unit, bi, "buff", left)
                    end
                end
            end
        end
        if bShown > maxN then bShown = maxN end
        layoutAuraGrid(self.buffs, bShown, perRow, baw, bah, root, true, 0, buffPad, buffOx, buffOy, buffAnchor)

        -- ===== TARGET DEBUFFS (below) =====
        local dShown = self._debuffShown or 0
        local hasPoison, hasDisease = false, false
        local painted = {}

        local function addDebuff(dicon, dcount, rr, rg, rb, ra, key, auraIndex, timeLeft)
            if not dicon then return end
            local dedupe = tostring(auraIndex or dShown + 1)
            if painted[dedupe] then return end
            painted[dedupe] = true
            dShown = dShown + 1
            if dShown <= maxDebuff then
                paintAura(self.debuffs[dShown], dicon, dcount, rr, rg, rb, ra, unit, auraIndex, "debuff", timeLeft)
            end
        end

        if not doDebuffPaint then
            -- Keep last grid; apply-start sync already ran.
        elseif friendly then
            dShown = 0
            local di
            local seenTimes = {}
            for di = 1, 16 do
                local dname, dicon, dcount, dtype, caster, spellId = readDebuff(unit, di, nil)
                if not dicon then break end
                local mine = IchaUIUF_DebuffIsMine(caster, dname, dicon, mineDebMap)
                if IchaUIUF_ShouldShowDebuff(filterKind, dname, spellId, mine, dtype) then
                    local dt = classifyDebuff(dtype, dname)
                    if dt == "poison" then hasPoison = true end
                    if dt == "disease" then hasDisease = true end
                    local rr, rg, rb, ra = colorForDtype(dt)
                    local left = peekDebuffTimeLeft(unit, di, spellId, dicon, dname)
                    local ck = auraCacheKey(unit, spellId, dicon, dname)
                    if ck then seenTimes[ck] = true end
                    addDebuff(dicon, dcount, rr, rg, rb, ra, dicon, di, left)
                end
            end
            pruneAuraCache(unit, seenTimes)
        else
            -- Hostile: YOUR dots / watch list — never "dispellable" colors.
            dShown = 0
            local mineTex = {}
            local mi
            for mi = 1, 16 do
                local mname, micon = readDebuff(unit, mi, "mine")
                if not micon then break end
                mineTex[micon] = true
                if mname then mineTex[string.lower(mname)] = true end
            end
            local di
            local seenTimes = {}
            for di = 1, 16 do
                local dname, dicon, dcount, dtype, caster, spellId = readDebuff(unit, di, nil)
                if not dicon then break end
                local mine = isMineCaster(caster) or mineTex[dicon]
                    or (dname and mineTex[string.lower(dname)])
                if IchaUIUF_ShouldShowDebuff(filterKind, dname, spellId, mine, dtype) then
                    local watch = raidWatch()
                    local onWatch = dname and watch[string.lower(dname)]
                    local rr, rg, rb, ra = 0.75, 0.75, 0.75, 0.5
                    if mine then
                        rr, rg, rb, ra = 0.2, 0.95, 0.3, 0.95
                    elseif onWatch then
                        rr, rg, rb, ra = 0.95, 0.75, 0.1, 0.9
                    end
                    local left = peekDebuffTimeLeft(unit, di, spellId, dicon, dname)
                    local ck = auraCacheKey(unit, spellId, dicon, dname)
                    if ck then seenTimes[ck] = true end
                    addDebuff(dicon, dcount, rr, rg, rb, ra, dicon, di, left)
                end
            end
            pruneAuraCache(unit, seenTimes)
        end

        if doDebuffPaint then
            if dShown > maxDebuff then dShown = maxDebuff end
            self._debuffShown = dShown
        end
        if testMode and bShown == 0 and dShown == 0 then
            paintTestAuras()
            finishAuras()
            return
        end
        if doDebuffLayout then
            layoutAuraGrid(self.debuffs, dShown, debuffPerRow, daw, dah, root, false, debuffY, debuffPad, debuffOx, debuffOy, debuffAnchor)
        end

        if friendly and (hasPoison or hasDisease) then
            if hasPoison then
                setDispelGlow(self, 0.2, 0.95, 0.15, 1)
            else
                setDispelGlow(self, 1.0, 0.92, 0.05, 1)
            end
        else
            clearDispelGlow(self)
        end
        finishAuras()
    end

    function fr:hideShieldCharges()
        if self.shieldChargeFrame then
            self.shieldChargeFrame:Hide()
        end
        local balls = self.shieldBalls
        if not balls then return end
        local i
        for i = 1, 16 do
            local b = balls[i]
            if b then b:Hide() end
        end
    end

    function fr:updateShieldCharges()
        -- Shield charge circles belong on the player frame only.
        local u = self.unit or unit
        if u ~= "player" then
            self:hideShieldCharges()
            return
        end
        if not self.hasPortrait or self.portraitEnabled == false or not self.portraitFrame then
            self:hideShieldCharges()
            return
        end
        if self.shieldChargeEnabled == false then
            self:hideShieldCharges()
            return
        end
        if self.hidden and not testMode then
            self:hideShieldCharges()
            return
        end
        local port = self.portraitFrame
        if not port or (port.IsShown and not port:IsShown()) then
            self:hideShieldCharges()
            return
        end

        local kind, charges = nil, 0
        local preview = (testMode or self._forcePreview) and true or false

        local function auraKind(name, tex)
            local n = string.lower(tostring(name or ""))
            local t = string.lower(tostring(tex or ""))
            if (string.find(n, "lightning", 1, true) and string.find(n, "shield", 1, true))
                or string.find(t, "lightningshield", 1, true) then
                return "lightning"
            end
            if (string.find(n, "water", 1, true) and string.find(n, "shield", 1, true))
                or string.find(t, "watershield", 1, true)
                or string.find(t, "ability_shaman_water", 1, true) then
                return "water"
            end
            if (string.find(n, "earth", 1, true) and string.find(n, "shield", 1, true))
                or string.find(t, "skinofearth", 1, true)
                or string.find(t, "earthshield", 1, true) then
                return "earth"
            end
            return nil
        end

        local function takeCharges(n)
            n = tonumber(n) or 1
            if n < 1 then n = 1 end
            if n > 16 then n = 16 end
            return n
        end

        local tokenOk = true
        if not u or u == "" or u == "none" then
            tokenOk = false
        elseif string.sub(u, 1, 6) == "IchaUI" then
            tokenOk = false
        elseif string.sub(u, 1, 9) == "nameplate" then
            tokenOk = false
        elseif string.find(u, "^0[xX]") then
            tokenOk = false
        end

        if tokenOk and u == "player" and type(GetPlayerBuff) == "function" and type(GetPlayerBuffTexture) == "function" then
            local i
            for i = 0, 31 do
                local id = GetPlayerBuff(i, "HELPFUL")
                if id == nil or id < 0 then break end
                local tex = GetPlayerBuffTexture(id)
                local k = auraKind(nil, tex)
                if not k and tip then
                    tip:SetOwner(UIParent, "ANCHOR_NONE")
                    tip:ClearLines()
                    pcall(function() tip:SetPlayerBuff(id) end)
                    local fs = getglobal("IchaUIUFTipTextLeft1")
                    local nm = fs and fs:GetText()
                    k = auraKind(nm, tex)
                end
                if k then
                    local n = nil
                    if type(GetPlayerBuffApplications) == "function" then
                        n = GetPlayerBuffApplications(id)
                    end
                    kind = k
                    charges = takeCharges(n)
                    break
                end
            end
        end

        if not kind and tokenOk then
            pcall(function()
                local bi
                for bi = 1, 32 do
                    local bname, bicon, bcount = readBuff(u, bi)
                    if not bicon then break end
                    local k = auraKind(bname, bicon)
                    if k then
                        kind = k
                        charges = takeCharges(bcount)
                        break
                    end
                end
            end)
        end

        if not kind and preview then
            kind = "water"
            charges = 3
        end

        if not kind or charges < 1 then
            self:hideShieldCharges()
            return
        end

        if not self.shieldChargeFrame then
            local holder = CreateFrame("Frame", "IchaUIUF_" .. key .. "_ShieldBalls", UIParent)
            holder:SetFrameStrata("HIGH")
            holder:SetFrameLevel(70)
            holder:EnableMouse(false)
            self.shieldChargeFrame = holder
            self.shieldBalls = {}
        end
        local holder = self.shieldChargeFrame
        local balls = self.shieldBalls
        local i
        for i = 1, 16 do
            if not balls[i] then
                local b = CreateFrame("Frame", nil, holder)
                b:EnableMouse(false)
                local fill = b:CreateTexture(nil, "ARTWORK")
                fill:SetTexture("Interface\\AddOns\\IchaUI\\media\\ShieldChargeFill.tga")
                fill:SetAllPoints(b)
                if fill.SetTexCoord then fill:SetTexCoord(0, 1, 0, 1) end
                b.fill = fill
                local rimtex = b:CreateTexture(nil, "OVERLAY")
                rimtex:SetTexture("Interface\\AddOns\\IchaUI\\media\\ShieldChargeRim.tga")
                rimtex:SetAllPoints(b)
                if rimtex.SetTexCoord then rimtex:SetTexCoord(0, 1, 0, 1) end
                -- Bright yellow rim art. Multiply onto circle gold (~190, 133, 11).
                IchaUI_PaintGoldVertex(rimtex, 0.75, 0.70, 0.21, 1)
                b.rim = rimtex
                balls[i] = b
            end
        end

        local cr, cg, cb = 0.45, 0.75, 1.0
        if kind == "earth" then
            cr, cg, cb = 0.52, 0.46, 0.18
        elseif kind == "lightning" then
            cr, cg, cb = 0.22, 0.32, 0.78
        end

        -- Same portrait/badge rim as applySize combatBadge (CENTER of port, same radius).
        -- Do not add badgeAngle / badgeOffset — Sh Rot/X/Y are an independent start.
        local h = math.floor((tonumber(self.height) or 40) * (tonumber(self.scale) or 1) + 0.5)
        local psc = tonumber(self.portraitScale) or PORTRAIT_DEFAULT_SCALE
        local ph = math.floor(h * psc + 0.5)
        if ph < 28 then ph = 28 end
        local bsc = tonumber(self.badgeScale) or 1
        if bsc < 0.5 then bsc = 0.5 end
        if bsc > 2 then bsc = 2 end
        local csz = math.floor(ph * 0.38 * bsc + 0.5)
        if csz < 12 then csz = 12 end
        if csz > 40 then csz = 40 end
        local radius = (ph * 0.5) - (csz * 0.15)
        if radius < ph * 0.25 then radius = ph * 0.25 end

        local ballSz = math.floor((tonumber(self.shieldChargeSize) or 10) + 0.5)
        if ballSz < 6 then ballSz = 6 end
        if ballSz > 28 then ballSz = 28 end

        local function rimXY(a, ox, oy)
            local twoPi = math.pi * 2
            local rad = a * math.pi / 180
            rad = math.mod(rad, twoPi)
            if rad < 0 then rad = rad + twoPi end
            local bx = math.floor(math.sin(rad) * radius + ox + 0.5)
            local by = math.floor(-math.cos(rad) * radius + oy + 0.5)
            return bx, by
        end

        -- 0=bottom; persist signed Sh Rot; wrap only for trig (0..2π).
        -- Default grow is clockwise (minus step). Reverse flips step sign.
        local startAng = tonumber(self.shieldChargeAngle) or 0
        local ox = tonumber(self.shieldChargeOffsetX) or 0
        local oy = tonumber(self.shieldChargeOffsetY) or 0
        local spread = tonumber(self.shieldChargeSpread) or 90
        if spread < 10 then spread = 10 end
        if spread > 360 then spread = 360 end
        local maxSlots = 9
        if charges > maxSlots then maxSlots = charges end
        if maxSlots > 16 then maxSlots = 16 end
        local step = 0
        if charges > 1 then
            if spread >= 360 then
                step = 360 / maxSlots
            elseif maxSlots > 1 then
                step = spread / (maxSlots - 1)
            end
        end
        local stepSign = -1
        if self.shieldChargeReverse then stepSign = 1 end

        holder:Show()
        holder:SetFrameStrata("HIGH")
        holder:SetFrameLevel((root:GetFrameLevel() or 1) + 70)

        for i = 1, 16 do
            local b = balls[i]
            if i <= charges then
                local a = startAng + stepSign * (i - 1) * step
                local bx, by = rimXY(a, ox, oy)
                b:ClearAllPoints()
                b:SetWidth(ballSz)
                b:SetHeight(ballSz)
                b:SetPoint("CENTER", port, "CENTER", bx, by)
                if b.fill then
                    b.fill:SetVertexColor(cr, cg, cb, 1)
                    b.fill:Show()
                end
                if b.rim then
                    IchaUI_PaintGoldVertex(b.rim, 0.75, 0.70, 0.21, 1)
                    b.rim:Show()
                end
                b:Show()
            else
                b:Hide()
            end
        end
    end

    function fr:update(skipAuras)
        if self.hidden and not testMode then
            root:Hide()
            if self.portraitRingFrame then self.portraitRingFrame:Hide() end
            if self.combatBadge then self.combatBadge:Hide() end
            if self.hideShieldCharges then self:hideShieldCharges() end
            if IchaUI_HideUnitRaidMark then IchaUI_HideUnitRaidMark(self) end; if IchaUI_HideUnitRoleIcons then IchaUI_HideUnitRoleIcons(self) end
            if self.dcIcon then self.dcIcon:Hide() end
            return
        end
        if key == "focus" and not self._focusActive then
            root:Hide()
            self._portraitChromeOn = false
            if self.portraitRingFrame then self.portraitRingFrame:Hide() end
            if self.portraitRingTex then self.portraitRingTex:Hide() end
            if self.portraitFrame then self.portraitFrame:Hide() end
            if self.combatBadge then self.combatBadge:Hide() end
            if self.combatIcon then self.combatIcon:Hide() end
            if self.levelText then self.levelText:Hide() end
            if self.hideShieldCharges then self:hideShieldCharges() end
            if self.castFrame then self.castFrame:Hide() end
            if IchaUI_HideUnitRaidMark then IchaUI_HideUnitRaidMark(self) end
            if IchaUI_HideUnitRoleIcons then IchaUI_HideUnitRoleIcons(self) end
            return
        end
        if key == "focus" and self._holdMissing then
            root:Show()
            return
        end
        local unitLive = false
        if unit and unit ~= "" and unit ~= "none" and UnitExists then
            local ok, exists = pcall(UnitExists, unit)
            unitLive = ok and exists and true or false
        end
        if not unitLive then
            if testMode or self._forcePreview then
                root:Show()
                if self.border then self.border:Show() end
                local pretty = key
                if key == "target" then pretty = "Target"
                elseif key == "tot" or unit == "targettarget" then pretty = "ToT"
                elseif isPartyUnit(unit) then
                    local _, _, n = string.find(unit, "(%d+)")
                    pretty = "Party" .. (n or "")
                elseif key and string.find(key, "^combat") then
                    pretty = "In combat"
                end
                setTruncatedText(nameFS, pretty, self._nameMaxW or (hpBg:GetWidth() - 8))
                local cr, cg, cb = 0.78, 0.58, 0.16 -- gold / generic class-ish
                if key == "target" or key == "tot" or unit == "targettarget" then cr, cg, cb = 0.9, 0.15, 0.15 end
                local barW = hpBg:GetWidth()
                if barW < 1 then barW = self.width * self.scale - 8 end
                local pct = 0.75
                IchaUI_SeatPowerFill(hp, hpBg, math.max(0.001, barW * pct))
                hp:SetVertexColor(cr, cg, cb)
                if hp.SetDesaturated then
                    pcall(function() hp:SetDesaturated(0) end)
                end
                if mp.SetDesaturated then
                    pcall(function() mp:SetDesaturated(0) end)
                end
                if self.portraitBg then
                    if IchaUI_PaintPortraitFill then
                        IchaUI_PaintPortraitFill(self.portraitBg)
                    end
                    self.portraitBg:Show()
                end
                if self.portraitTex then
                    if IchaUI_ApplyPortraitFace then
                        IchaUI_ApplyPortraitFace(self.portraitTex, unit)
                    end
                    self.portraitTex:SetVertexColor(1, 1, 1)
                    if self.portraitTex.SetDesaturated then
                        pcall(function() self.portraitTex:SetDesaturated(0) end)
                    end
                end
                hpText:Show()
                if self.dcIcon then self.dcIcon:Hide() end
                healPred:Hide()
                local ts = loadTextSettings(textKindForKey(key))
                if ts.showHpPct then
                    hpText:SetText("750 / 1000 (75%)")
                else
                    hpText:SetText("750 / 1000")
                end
                local mw = mpBg:GetWidth()
                if mw < 1 then mw = barW end
                IchaUI_SeatPowerFill(mp, mpBg, math.max(0.001, mw * 0.6))
                mp:SetVertexColor(0.2, 0.4, 0.95)
                if ts.showPowerText then
                    powerText:SetText("600 / 1000")
                    powerText:Show()
                else
                    powerText:SetText("")
                    powerText:Hide()
                end
                self:updateAuras()
                self:updateCast()
                if self.pvpIcon then self.pvpIcon:Hide() end
                if self.hpLevel then
                    local portShown = self.hasPortrait and self.portraitEnabled ~= false
                    local showPort = portShown and IchaUI_LevelPortraitOn and IchaUI_LevelPortraitOn(key)
                    if IchaUI_LevelBarOn and IchaUI_LevelBarOn(key, showPort) then
                        self.hpLevel:SetText("60")
                        IchaUI_TintLevelPreview(self.hpLevel, nil, 60)
                        self.hpLevel:Show()
                    else
                        self.hpLevel:Hide()
                    end
                    if self.levelText then
                        if showPort then
                            self.levelText:SetText("60")
                            IchaUI_TintLevelPreview(self.levelText, self.combatBadgeRing, 60)
                            self.levelText:Show()
                            if self.combatBadge then self.combatBadge:Show() end
                        else
                            self.levelText:Hide()
                            if IchaUI_LevelCanPortrait and IchaUI_LevelCanPortrait(key) and self.combatBadge then
                                self.combatBadge:Hide()
                            end
                        end
                    end
                end
                if IchaUI_UpdateUnitRaidMark then IchaUI_UpdateUnitRaidMark(self) end; if IchaUI_UpdateUnitRoleIcons then IchaUI_UpdateUnitRoleIcons(self) end
                return
            end
            -- Combat list: nameplate gone, but this mob is still in combat with the player.
            -- Leave the last health/cast paint in place until the row is dropped.
            if self._holdMissing and key and (string.find(key, "^combat") or key == "focus") then
                root:Show()
                return
            end
            if isTargetFrameUnit(unit) or isPartyUnit(unit) or key == "focus" or (key and string.find(key, "^combat")) then
                root:Hide()
                nameFS:SetText("")
                hpText:SetText("")
                if powerText then powerText:SetText(""); powerText:Hide() end
            else
                root:Show()
            end
            -- UIParent portrait ring / badge outlive root:Hide — must hide explicitly
            self._portraitChromeOn = false
            if self.portraitRingFrame then self.portraitRingFrame:Hide() end
            if self.portraitRingTex then self.portraitRingTex:Hide() end
            if self.portraitFrame then self.portraitFrame:Hide() end
            if self.border then self.border:Hide() end
            if self.combatBadge then self.combatBadge:Hide() end
            if self.combatIcon then self.combatIcon:Hide() end
            if self.levelText then self.levelText:Hide() end
            if self.hideShieldCharges then self:hideShieldCharges() end
            if self.hpLevel then self.hpLevel:Hide() end
            if IchaUI_HideUnitRaidMark then IchaUI_HideUnitRaidMark(self) end; if IchaUI_HideUnitRoleIcons then IchaUI_HideUnitRoleIcons(self) end
            hpText:Show()
            if self.dcIcon then self.dcIcon:Hide() end
            if hp.SetDesaturated then
                pcall(function() hp:SetDesaturated(0) end)
            end
            if mp.SetDesaturated then
                pcall(function() mp:SetDesaturated(0) end)
            end
            if self.portraitTex then
                self.portraitTex:SetVertexColor(1, 1, 1)
                if self.portraitTex.SetDesaturated then
                    pcall(function() self.portraitTex:SetDesaturated(0) end)
                end
            end
            healPred:Hide()
            self:updateAuras()
            self:updateCast()
            self:updatePvP()
            return
        end
        root:Show()
        if self.border then self.border:Show() end

        setTruncatedText(nameFS, unitName(unit), self._nameMaxW or (hpBg:GetWidth() - 8))
        local cr, cg, cb = classColor(unit)
        -- Tracker rows: on-you vs loose. Unknown target keeps the last color for this mob.
        if self._colorUnit ~= unit then
            self._colorUnit = unit
            self._cR, self._cG, self._cB = nil, nil, nil
        end
        if key and string.find(key, "^combat") and IchaUI_CombatRowColors and not badUnitToken(unit) then
            self._tr, self._tg, self._tb = IchaUI_CombatRowColors(unit)
            if self._tr then
                cr, cg, cb = self._tr, self._tg, self._tb
                self._cR, self._cG, self._cB = cr, cg, cb
            end
        end

        local hpCur = UnitHealth(unit) or 0
        local hpMax = UnitHealthMax(unit) or 1
        if hpMax < 1 then hpMax = 1 end
        local pct = hpCur / hpMax
        if pct < 0 then pct = 0 end
        if pct > 1 then pct = 1 end
        local barW = hpBg:GetWidth()
        if barW < 1 then barW = self.width * self.scale - 8 end
        IchaUI_SeatPowerFill(hp, hpBg, math.max(0.001, barW * pct))
        if key and string.find(key, "^combat") then
            if self._cR then
                hp:SetVertexColor(self._cR, self._cG, self._cB)
                nameFS:SetTextColor(self._cR, self._cG, self._cB)
            end
        elseif self._dispelHP then
            hp:SetVertexColor(self._dispelHP[1], self._dispelHP[2], self._dispelHP[3])
        else
            hp:SetVertexColor(cr, cg, cb)
        end

        -- Offline party/raid: UnitIsConnected is nil/false. Do not show 0 HP.
        local offline = false
        if (isPartyUnit(unit) or isRaidUnit(unit)) and UnitIsConnected
            and unit ~= "" and unit ~= "none" then
            if not UnitIsConnected(unit) then
                offline = true
            end
        end
        if offline then
            if pct <= 0 then
                IchaUI_SeatPowerFill(hp, hpBg, math.max(0.001, barW))
            end
            hp:SetVertexColor(0.45, 0.45, 0.45)
            if hp.SetDesaturated then
                pcall(function() hp:SetDesaturated(1) end)
            end
        elseif hp.SetDesaturated then
            pcall(function() hp:SetDesaturated(0) end)
            if key and string.find(key, "^combat") then
                if self._cR then
                    hp:SetVertexColor(self._cR, self._cG, self._cB)
                    nameFS:SetTextColor(self._cR, self._cG, self._cB)
                end
            elseif self._dispelHP then
                hp:SetVertexColor(self._dispelHP[1], self._dispelHP[2], self._dispelHP[3])
            else
                hp:SetVertexColor(cr, cg, cb)
            end
        end

        -- Predictive heal: green CHUNK to the right of current HP only
        local dbuf = db()
        if not offline and dbuf.predictHeals ~= false and healCastActive
            and not (UnitIsDead(unit) or UnitIsGhost(unit)) then
            local incoming = getIncomingHeals(unit) or 0
            local missing = hpMax - hpCur
            if incoming > missing then incoming = missing end
            placeHealPred(healPred, hpBg, barW, pct, incoming, hpMax)
        else
            healPred:Hide()
        end

        local ts = loadTextSettings(textKindForKey(key))
        if offline then
            hpText:SetText("")
            hpText:Hide()
            if self.dcIcon then self.dcIcon:Show() end
        else
            hpText:Show()
            if self.dcIcon then self.dcIcon:Hide() end
            if UnitIsDead(unit) or UnitIsGhost(unit) then
                hpText:SetText("Dead")
            else
                if ts.showHpPct then
                    local pctN = math.floor(pct * 100 + 0.5)
                    hpText:SetText(string.format("%d / %d (%d%%)", hpCur, hpMax, pctN))
                else
                    hpText:SetText(string.format("%d / %d", hpCur, hpMax))
                end
            end
        end
        IchaUI_PaintHpLevel(self.hpLevel, unit)
        local portShown = self.hasPortrait and self.portraitEnabled ~= false
        local showPortLevel = portShown and IchaUI_LevelPortraitOn and IchaUI_LevelPortraitOn(key)
        -- Combat swords / rest zzz occupy the badge; Auto bar still shows the number then.
        if showPortLevel and key == "player" then
            if UnitAffectingCombat and UnitAffectingCombat("player") then
                showPortLevel = false
            elseif IsResting and IsResting() then
                showPortLevel = false
            end
        end
        if self.hpLevel and IchaUI_LevelBarOn and not IchaUI_LevelBarOn(key, showPortLevel) then
            self.hpLevel:Hide()
        end

        local mpCur = UnitMana(unit) or 0
        local mpMax = UnitManaMax(unit) or 1
        if mpMax < 1 then mpMax = 1 end
        local mpct = mpCur / mpMax
        if mpct < 0 then mpct = 0 end
        if mpct > 1 then mpct = 1 end
        local mw = mpBg:GetWidth()
        if mw < 1 then mw = barW end
        IchaUI_SeatPowerFill(mp, mpBg, math.max(0.001, mw * mpct))
        local pr, pg, pb = powerColor(unit)
        mp:SetVertexColor(pr, pg, pb)
        if offline then
            if mpct <= 0 then
                IchaUI_SeatPowerFill(mp, mpBg, math.max(0.001, mw))
            end
            mp:SetVertexColor(0.45, 0.45, 0.45)
            if mp.SetDesaturated then
                pcall(function() mp:SetDesaturated(1) end)
            end
            powerText:SetText("")
            powerText:Hide()
        else
            if mp.SetDesaturated then
                pcall(function() mp:SetDesaturated(0) end)
                mp:SetVertexColor(pr, pg, pb)
            end
            if ts.showPowerText then
                powerText:SetText(string.format("%d / %d", mpCur, mpMax))
                powerText:Show()
            else
                powerText:SetText("")
                powerText:Hide()
            end
        end

        if self.hasPortrait and self.portraitEnabled ~= false then
            -- After no-target Hide, UIParent ring needs a full re-layout once (not every tick)
            if not self._portraitChromeOn and self.applySize then
                self:applySize()
            end
            self._portraitChromeOn = true
            if self.portraitBg then
                if IchaUI_PaintPortraitFill then
                    IchaUI_PaintPortraitFill(self.portraitBg)
                end
                self.portraitBg:Show()
            end
            if self.portraitTex then
                if IchaUI_ApplyPortraitFace then
                    IchaUI_ApplyPortraitFace(self.portraitTex, unit)
                elseif SetPortraitTexture and unit and unit ~= "none" and unit ~= "" then
                    pcall(SetPortraitTexture, self.portraitTex, unit)
                end
            end
            if self.portraitTex and (isPartyUnit(unit) or isRaidUnit(unit)) then
                if offline then
                    self.portraitTex:SetVertexColor(0.45, 0.45, 0.45)
                    if self.portraitTex.SetDesaturated then
                        pcall(function() self.portraitTex:SetDesaturated(1) end)
                    end
                else
                    self.portraitTex:SetVertexColor(1, 1, 1)
                    if self.portraitTex.SetDesaturated then
                        pcall(function() self.portraitTex:SetDesaturated(0) end)
                    end
                end
            end
            if self.portraitFrame then self.portraitFrame:Show() end
            if self.portraitRingFrame then self.portraitRingFrame:Show() end
            -- Always re-show ring tex (Hide on no-unit); re-apply texture if helper present
            if self.portraitRingTex then
                if applyPortraitRing and self.portraitRingFrame then
                    local rf = self.portraitRingFrame
                    local ringSz = rf:GetWidth() or rf:GetHeight() or 48
                    if ringSz < 16 then ringSz = 16 end
                    applyPortraitRing(self.portraitRingTex, rf, ringSz)
                else
                    self.portraitRingTex:Show()
                end
            end
        elseif self.hasPortrait then
            self._portraitChromeOn = false
            if self.portraitFrame then self.portraitFrame:Hide() end
            if self.portraitRingFrame then self.portraitRingFrame:Hide() end
            if self.portraitRingTex then self.portraitRingTex:Hide() end
        end

        if not skipAuras then
            self:updateAuras()
        end
        if offline then
            if pct <= 0 then
                IchaUI_SeatPowerFill(hp, hpBg, math.max(0.001, barW))
            end
            if mpct <= 0 then
                IchaUI_SeatPowerFill(mp, mpBg, math.max(0.001, mw))
            end
            hp:SetVertexColor(0.45, 0.45, 0.45)
            mp:SetVertexColor(0.45, 0.45, 0.45)
            self._dispelHP = nil
            if self.dispelTint then
                self.dispelTint:SetAlpha(0)
                self.dispelTint:Hide()
            end
            if self.portraitTex and (isPartyUnit(unit) or isRaidUnit(unit)) then
                self.portraitTex:SetVertexColor(0.45, 0.45, 0.45)
            end
            hpText:SetText("")
            hpText:Hide()
            if self.dcIcon then self.dcIcon:Show() end
        end
        self:updateCast()
        self:updatePvP()
        if IchaUI_UpdateUnitRaidMark then IchaUI_UpdateUnitRaidMark(self) end; if IchaUI_UpdateUnitRoleIcons then IchaUI_UpdateUnitRoleIcons(self) end
    end

    function fr:setMove(on)
        self.moving = on and true or false
        if self.moving then self.mover:Show() else
            self.mover:Hide()
            saveFrame(key, self)
        end
    end

    function fr:setCastMove(on)
        if key ~= "player" and key ~= "target" and key ~= "focus" then return end
        self._castMoving = on and true or false
        if not self.castMover or not self.castFrame then return end
        if self._castMoving then
            -- ensure detached so free move is meaningful
            local kind = textKindForKey(key)
            local s = IchaUIUF_GetCastSettings(kind)
            if not s.castDetached then
                IchaUIUF_SetCastSetting(kind, "castDetached", true)
            end
            self.castFrame:EnableMouse(true)
            self.castMover:Show()
            self.castFrame:Show()
        else
            self.castFrame:EnableMouse(false)
            self.castMover:Hide()
            if self.applySize then self:applySize() end
        end
    end

    function fr:restorePos()
        if managedPos then
            return
        end
        local s = loadFrame(key, defaults)
        root:ClearAllPoints()
        if s.point and s.x ~= nil then
            root:SetPoint(s.point, UIParent, s.relPoint or s.point, s.x, s.y or 0)
        elseif key == "player" then
            root:SetPoint("BOTTOM", UIParent, "BOTTOM", -220, 180)
        elseif key == "focus" then
            root:SetPoint("BOTTOM", UIParent, "BOTTOM", 220, 280)
        elseif key == "tot" or unit == "targettarget" then
            -- Near target (target default is BOTTOM +220, 180)
            root:SetPoint("BOTTOM", UIParent, "BOTTOM", 420, 180)
        else
            root:SetPoint("BOTTOM", UIParent, "BOTTOM", 220, 180)
        end
    end

    function fr:applySaved()
        local s = loadFrame(key, defaults)
        self.scale = s.scale
        self.width = s.width
        self.height = s.height
        self.hidden = s.hidden
        if self.hasPortrait then
            -- Saved false stays off. Missing stays off. Do not turn a portrait on just because the key was absent.
            self.portraitEnabled = s.portrait and true or false
            self.portraitScale = s.portraitScale or PORTRAIT_DEFAULT_SCALE
            self.portraitRing = s.portraitRing or PORTRAIT_DEFAULT_RING
            self.portraitOffsetX = s.portraitOffsetX or 0
            self.portraitOffsetY = s.portraitOffsetY or 0
            self.badgeAngle = s.badgeAngle or 0
            self.badgeScale = s.badgeScale or 1
            self.badgeOffsetX = s.badgeOffsetX or 0
            self.badgeOffsetY = s.badgeOffsetY or 0
            if s.badgeHost == "frame" or s.badgeHost == "portrait" then
                self.badgeHost = s.badgeHost
            else
                self.badgeHost = nil
            end
            self.shieldChargeEnabled = s.shieldChargeEnabled ~= false
            self.shieldChargeSpread = s.shieldChargeSpread or 90
            self.shieldChargeSize = s.shieldChargeSize or 10
            self.shieldChargeAngle = s.shieldChargeAngle or 0
            self.shieldChargeReverse = s.shieldChargeReverse and true or false
            self.shieldChargeOffsetX = s.shieldChargeOffsetX or 0
            self.shieldChargeOffsetY = s.shieldChargeOffsetY or 0
        end
        self:restorePos()
        self:applySize()
        if self.hidden then
            root:Hide()
            if self.hideShieldCharges then self:hideShieldCharges() end
            if IchaUI_HideUnitRaidMark then IchaUI_HideUnitRaidMark(self) end; if IchaUI_HideUnitRoleIcons then IchaUI_HideUnitRoleIcons(self) end
        else
            root:Show()
        end
    end

    function fr:SetUnit(newUnit)
        if not newUnit or newUnit == "" then newUnit = "none" end
        if unit ~= newUnit then
            IchaUI_Swing_Clear(self)
            self._debuffFp = nil
            self._debuffUid = nil
            self._debuffShown = 0
            self._debuffEmptyN = 0
            do
                local i
                for i = 1, MAX_AURA_SLOTS do
                    local icon = self.debuffs and self.debuffs[i]
                    if icon then
                        if icon:IsShown() then icon:Hide() end
                        icon._auraTex = nil
                        icon._auraKind = nil
                        icon._auraApplied = nil
                        icon.auraUnit = nil
                        icon.expires = nil
                    end
                end
            end
        end
        unit = newUnit
        self.unit = newUnit
    end

    fr:restorePos()
    fr:applySize()
    if fr.hidden then root:Hide() end
    frames[key] = fr
    return fr
end

-- Bar split + fill textures. Globals: UnitFrames.lua is at the local limit.
function IchaUIUF_BarKind(key)
    if not key then return "player" end
    if key == "player" or key == "target" or key == "tot" or key == "focus"
        or key == "party" or key == "raid" or key == "combat" then
        return key
    end
    if string.find(key, "^party") then return "party" end
    if string.find(key, "^raid") then return "raid" end
    if string.find(key, "^combat") then return "combat" end
    return "player"
end

-- Power fill must match the slot after SetTexture. 1.12 SetTexture restores the
-- file size (status bars are 256x32). Health is about that tall; a thin power
-- slot then draws the texture short and centered instead of at mpH.
function IchaUI_SeatPowerFill(mp, mpBg, width)
    if not mp or not mpBg then return end
    local h = mpBg:GetHeight() or 0
    if h < 1 then h = 1 end
    local w = tonumber(width) or 0
    if w < 0.001 then w = 0.001 end
    mp:ClearAllPoints()
    -- Explicit size. TOP+BOTTOM anchors plus a shorter height get centered in 1.12.
    mp:SetPoint("TOPLEFT", mpBg, "TOPLEFT", 0, 0)
    mp:SetWidth(w)
    mp:SetHeight(h)
    if IchaUIUF_StretchBarFill then IchaUIUF_StretchBarFill(mp) end
end

function IchaUIUF_BarGap(kind)
    kind = IchaUIUF_BarKind(kind)
    if kind == "party" or kind == "raid" then return 0 end
    return 2
end

function IchaUIUF_NaturalBarPixels(height, scale, kind)
    local sc = tonumber(scale) or 1
    if sc < 0.05 then sc = 1 end
    local fh = math.floor((tonumber(height) or 48) * sc + 0.5)
    if fh < 8 then fh = 8 end
    local usable = fh - 6
    if usable < 2 then usable = 2 end
    local gap = IchaUIUF_BarGap(kind)
    local mpH = math.max(1, math.floor(usable * 0.16 + 0.5))
    local hpH = usable - gap - mpH
    if hpH < 1 then hpH = 1 end
    return hpH, mpH
end

function IchaUIUF_KindMetrics(kind)
    kind = IchaUIUF_BarKind(kind)
    if kind == "party" and IchaUIUF_PartyGet then
        local t = IchaUIUF_PartyGet()
        return tonumber(t.height) or 48, tonumber(t.scale) or 1, tonumber(t.width) or 220
    end
    if kind == "raid" and IchaUIUF_RaidGet then
        local t = IchaUIUF_RaidGet()
        return tonumber(t.height) or 48, tonumber(t.scale) or 1, tonumber(t.width) or 110
    end
    if kind == "combat" and IchaUI_CombatProfile then
        local g = IchaUI_CombatProfile()
        return tonumber(g.height) or 40, tonumber(g.scale) or 1, tonumber(g.width) or 200
    end
    if IchaUIUF_Get then
        local fr = IchaUIUF_Get(kind)
        if fr then
            return tonumber(fr.height) or 48, tonumber(fr.scale) or 1, tonumber(fr.width) or 220
        end
    end
    return 48, 1, 220
end

function IchaUIUF_GetBarSplit(kind)
    kind = IchaUIUF_BarKind(kind)
    local row = IchaUIDB and IchaUIDB.uf and IchaUIDB.uf.barSplit and IchaUIDB.uf.barSplit[kind]
    if type(row) == "table" and tonumber(row.health) and tonumber(row.power) then
        local hp = math.floor(tonumber(row.health) + 0.5)
        local mp = math.floor(tonumber(row.power) + 0.5)
        if hp < 1 then hp = 1 end
        if mp < 1 then mp = 1 end
        if hp > 200 then hp = 200 end
        if mp > 200 then mp = 200 end
        return hp, mp, true
    end
    local height, scale = IchaUIUF_KindMetrics(kind)
    local hp, mp = IchaUIUF_NaturalBarPixels(height, scale, kind)
    return hp, mp, false
end

function IchaUIUF_GetBarRatioPct(kind)
    local hp, mp = IchaUIUF_GetBarSplit(kind)
    local total = hp + mp
    if total < 1 then return 50 end
    return math.floor((hp / total) * 100 + 0.5)
end

function IchaUIUF_ResolveBarPixels(key)
    local kind = IchaUIUF_BarKind(key)
    local row = IchaUIDB and IchaUIDB.uf and IchaUIDB.uf.barSplit and IchaUIDB.uf.barSplit[kind]
    if type(row) ~= "table" or not tonumber(row.health) or not tonumber(row.power) then
        return nil
    end
    local hp = math.max(1, math.min(200, math.floor(tonumber(row.health) + 0.5)))
    local mp = math.max(1, math.min(200, math.floor(tonumber(row.power) + 0.5)))
    local screen = 6 + IchaUIUF_BarGap(kind) + hp + mp
    return hp, mp, screen
end

function IchaUIUF_WriteBarSplit(kind, health, power)
    kind = IchaUIUF_BarKind(kind)
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.uf then IchaUIDB.uf = {} end
    if not IchaUIDB.uf.barSplit then IchaUIDB.uf.barSplit = {} end
    local hp = math.max(1, math.min(200, math.floor((tonumber(health) or 1) + 0.5)))
    local mp = math.max(1, math.min(200, math.floor((tonumber(power) or 1) + 0.5)))
    local total = hp + mp
    local ratio = 0
    if total > 0 then ratio = hp / total end
    IchaUIDB.uf.barSplit[kind] = { health = hp, power = mp, ratio = ratio }
    return hp, mp
end

function IchaUIUF_ReflowBars(kind)
    kind = IchaUIUF_BarKind(kind)
    if kind == "party" and IchaUIUF_layoutParty then
        IchaUIUF_layoutParty()
        return
    end
    if kind == "raid" and IchaUIUF_refreshAll then
        IchaUIUF_refreshAll()
        return
    end
    if kind == "combat" and IchaUI_CombatLayout then
        IchaUI_CombatLayout()
        return
    end
    if IchaUIUF_Get then
        local fr = IchaUIUF_Get(kind)
        if fr and fr.applySize then fr:applySize() end
        if fr and fr.update then fr:update() end
    end
    if (kind == "target" or kind == "tot") and IchaUIUF_layoutTargetCluster then
        IchaUIUF_layoutTargetCluster()
    end
end

function IchaUIUF_SyncFrameHeightFromBars(kind)
    kind = IchaUIUF_BarKind(kind)
    local hp, mp = IchaUIUF_GetBarSplit(kind)
    local _, scale = IchaUIUF_KindMetrics(kind)
    if not scale or scale < 0.05 then scale = 1 end
    local screen = 6 + IchaUIUF_BarGap(kind) + hp + mp
    local logical = screen / scale
    if logical < 1 then logical = 1 end
    if logical > 420 then logical = 420 end
    IchaUI_BarSkipRefit = true
    if kind == "party" and IchaUIUF_PartySet then
        IchaUIUF_PartySet("height", logical)
    elseif kind == "raid" and IchaUIUF_RaidSet then
        IchaUIUF_RaidSet("height", logical)
    elseif kind == "combat" and IchaUIUF_Set then
        IchaUIUF_Set("combat", "height", logical)
    elseif IchaUIUF_Set then
        IchaUIUF_Set(kind, "height", logical)
    end
    IchaUI_BarSkipRefit = nil
end

function IchaUIUF_RefitBarsToHeight(kind, logical, scale)
    kind = IchaUIUF_BarKind(kind)
    local row = IchaUIDB and IchaUIDB.uf and IchaUIDB.uf.barSplit and IchaUIDB.uf.barSplit[kind]
    if type(row) ~= "table" then return end
    local hp, mp = IchaUIUF_GetBarSplit(kind)
    local total = hp + mp
    if total < 2 then return end
    local ratio = hp / total
    local sc = tonumber(scale) or 1
    if sc < 0.05 then sc = 1 end
    local screen = math.floor((tonumber(logical) or 48) * sc + 0.5)
    local usable = screen - 6 - IchaUIUF_BarGap(kind)
    if usable < 2 then usable = 2 end
    local nh = math.floor(usable * ratio + 0.5)
    if nh < 1 then nh = 1 end
    if nh > usable - 1 then nh = usable - 1 end
    local np = usable - nh
    if nh > 200 then nh = 200 end
    if np > 200 then np = 200 end
    if np < 1 then np = 1 end
    if nh == hp and np == mp then return end
    IchaUIUF_WriteBarSplit(kind, nh, np)
end

function IchaUIUF_ScaleSavedBars(kind, oldSc, newSc)
    kind = IchaUIUF_BarKind(kind)
    local row = IchaUIDB and IchaUIDB.uf and IchaUIDB.uf.barSplit and IchaUIDB.uf.barSplit[kind]
    if type(row) ~= "table" then return end
    oldSc = tonumber(oldSc) or 1
    newSc = tonumber(newSc) or 1
    if oldSc < 0.05 then oldSc = 1 end
    if math.abs(newSc - oldSc) < 0.001 then return end
    local hp, mp = IchaUIUF_GetBarSplit(kind)
    local factor = newSc / oldSc
    IchaUIUF_WriteBarSplit(kind, math.max(1, math.floor(hp * factor + 0.5)), math.max(1, math.floor(mp * factor + 0.5)))
    IchaUIUF_SyncFrameHeightFromBars(kind)
end

function IchaUIUF_SetBarHealth(kind, value)
    local hp, mp, saved = IchaUIUF_GetBarSplit(kind)
    local nh = math.max(1, math.min(200, math.floor((tonumber(value) or hp) + 0.5)))
    if saved and nh == hp then return end
    if (not saved) and nh == hp then return end
    IchaUIUF_WriteBarSplit(kind, nh, mp)
    IchaUIUF_SyncFrameHeightFromBars(kind)
    IchaUIUF_ReflowBars(kind)
end

function IchaUIUF_SetBarPower(kind, value)
    local hp, mp, saved = IchaUIUF_GetBarSplit(kind)
    local np = math.max(1, math.min(200, math.floor((tonumber(value) or mp) + 0.5)))
    if saved and np == mp then return end
    if (not saved) and np == mp then return end
    IchaUIUF_WriteBarSplit(kind, hp, np)
    IchaUIUF_SyncFrameHeightFromBars(kind)
    IchaUIUF_ReflowBars(kind)
end

function IchaUIUF_SetBarRatio(kind, pct)
    pct = tonumber(pct) or 50
    if pct > 1 then pct = pct / 100 end
    if pct < 0.02 then pct = 0.02 end
    if pct > 0.98 then pct = 0.98 end
    local hp, mp, saved = IchaUIUF_GetBarSplit(kind)
    local total = hp + mp
    if total < 2 then total = 2 end
    local nh = math.floor(total * pct + 0.5)
    if nh < 1 then nh = 1 end
    if nh > total - 1 then nh = total - 1 end
    local np = total - nh
    if saved and nh == hp and np == mp then return end
    if (not saved) and nh == hp and np == mp then return end
    IchaUIUF_WriteBarSplit(kind, nh, np)
    IchaUIUF_SyncFrameHeightFromBars(kind)
    IchaUIUF_ReflowBars(kind)
end

IchaUI_BAR_FILLS = {
    { key = "blizzard", name = "Blizzard", path = "Interface/TargetingFrame/UI-StatusBar" },
    { key = "flat", name = "Flat", path = "Interface\\AddOns\\IchaUI\\media\\BarFlat.tga" },
    { key = "smooth", name = "Smooth", path = "Interface\\AddOns\\IchaUI\\media\\BarSmooth.tga" },
    { key = "gradient", name = "Gradient", path = "Interface\\AddOns\\IchaUI\\media\\BarGradient.tga" },
    { key = "gloss", name = "Gloss", path = "Interface\\AddOns\\IchaUI\\media\\BarGloss.tga" },
    { key = "bevel", name = "Bevel", path = "Interface\\AddOns\\IchaUI\\media\\BarBevel.tga" },
}

function IchaUIUF_BarFillKey(kind, which)
    kind = IchaUIUF_BarKind(kind)
    local row = IchaUIDB and IchaUIDB.uf and IchaUIDB.uf.barFill and IchaUIDB.uf.barFill[kind]
    if type(row) == "table" and type(row[which]) == "string" and row[which] ~= "" then
        return row[which]
    end
    return "blizzard"
end

function IchaUIUF_BarFillPath(kind, which)
    local want = IchaUIUF_BarFillKey(kind, which)
    local i
    for i = 1, table.getn(IchaUI_BAR_FILLS) do
        if IchaUI_BAR_FILLS[i].key == want then
            return IchaUI_BAR_FILLS[i].path
        end
    end
    return "Interface/TargetingFrame/UI-StatusBar"
end

-- SetTexture alone keeps a 256x32 file (Bevel, Gloss) at its own aspect,
-- centered in the bar. Tex coords plus a re-pin after this call stretch
-- the painted pixels to the bar's inner width and height.
function IchaUIUF_ApplyBarFill(tex, path)
    if not tex or not tex.SetTexture then return end
    if not path or path == "" then
        path = "Interface/TargetingFrame/UI-StatusBar"
    end
    tex:SetTexture(path)
    tex._ichaFill = path
    if IchaUIUF_StretchBarFill then IchaUIUF_StretchBarFill(tex) end
end

-- 256x32 Bevel/Gloss. The pixels already reach the file edge (no empty
-- padding). 1.12 ignores SetTexCoord(0, 1, 0, 1), so the file stays at its
-- own size, centered in the bar. A half-texel crop is not the identity coord,
-- which forces the paint to stretch to the bar width and height.
function IchaUIUF_StretchBarFill(tex)
    if not tex or not tex.SetTexCoord then return end
    local path = tex._ichaFill
    if type(path) ~= "string" and tex.GetTexture then
        path = tex:GetTexture()
    end
    if type(path) ~= "string" then return end
    local low = string.lower(path)
    if string.find(low, "barbevel", 1, true) or string.find(low, "bargloss", 1, true) then
        tex:SetTexCoord(0.5 / 256, 1 - (0.5 / 256), 0.5 / 32, 1 - (0.5 / 32))
    end
end

function IchaUI_SeatCastFill(tex, parent, x, y, w, h)
    if not tex or not parent then return end
    w = tonumber(w) or 0
    h = tonumber(h) or 0
    if w < 0.001 then w = 0.001 end
    if h < 1 then h = 1 end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
    tex:SetWidth(w)
    tex:SetHeight(h)
    IchaUIUF_StretchBarFill(tex)
end

function IchaUIUF_BarFillName(kind, which)
    local want = IchaUIUF_BarFillKey(kind, which)
    local i
    for i = 1, table.getn(IchaUI_BAR_FILLS) do
        if IchaUI_BAR_FILLS[i].key == want then
            return IchaUI_BAR_FILLS[i].name
        end
    end
    return "Blizzard"
end

-- pick: index into IchaUI_BAR_FILLS (dropdown); nil steps to the next fill.
function IchaUIUF_CycleBarFill(kind, which, pick)
    kind = IchaUIUF_BarKind(kind)
    local cur = IchaUIUF_BarFillKey(kind, which)
    local idx = 1
    local i
    for i = 1, table.getn(IchaUI_BAR_FILLS) do
        if IchaUI_BAR_FILLS[i].key == cur then idx = i end
    end
    idx = idx + 1
    if idx > table.getn(IchaUI_BAR_FILLS) then idx = 1 end
    if pick and IchaUI_BAR_FILLS[pick] then idx = pick end
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.uf then IchaUIDB.uf = {} end
    if not IchaUIDB.uf.barFill then IchaUIDB.uf.barFill = {} end
    if type(IchaUIDB.uf.barFill[kind]) ~= "table" then
        IchaUIDB.uf.barFill[kind] = {}
    end
    IchaUIDB.uf.barFill[kind][which] = IchaUI_BAR_FILLS[idx].key
    IchaUIUF_ReflowBars(kind)
    return IchaUI_BAR_FILLS[idx].name
end

IchaUI_CreateUnitFrame = createUnitFrame

local player = createUnitFrame("player", "player", { scale = 1, width = BASE_W, height = BASE_H, portrait = true, portraitScale = PORTRAIT_DEFAULT_SCALE, portraitRing = PORTRAIT_DEFAULT_RING }, { portrait = true, portraitSide = "left" })
local target = createUnitFrame("target", "target", { scale = 1, width = BASE_W, height = BASE_H, portrait = true, portraitScale = PORTRAIT_DEFAULT_SCALE, portraitRing = PORTRAIT_DEFAULT_RING }, { portrait = true, portraitSide = "right" })
local tot = createUnitFrame("tot", "targettarget", { scale = 1, width = BASE_W, height = BASE_H, portrait = true, portraitScale = PORTRAIT_DEFAULT_SCALE, portraitRing = PORTRAIT_DEFAULT_RING }, { managedPos = true, portrait = true, portraitSide = "right" })

------------------------------------------------------------------
-- Tank drawer (target) + docked ToT
------------------------------------------------------------------
local TANK_CARET_W = 26 -- ~25% smaller than prior 33
local TANK_CHAT_BG = { 0.08, 0.08, 0.09, 0.55 }
local TANK_DRAWER_W = 118
local TANK_DRAWER_H = BASE_H
local TANK_GAP = 0
local TANK_ARROW_NUDGE_X = -4 -- screen-left a few px
-- Nestled (closed): overlap into caret. Open: flush against caret (border clears itself).
local TANK_MINIMAL_SEP = 6
local TANK_OPEN_SEP = 2

function IchaUIUF_tankDrawerOpen()
    local d = db()
    return d.tankDrawerOpen and true or false
end

function IchaUIUF_setTankDrawerOpen(on)
    local d = db()
    d.tankDrawerOpen = on and true or false
end

function IchaUIUF_tankDrawerEnabled()
    local d = db()
    if d.tankDrawerEnabled == nil then return true end
    return d.tankDrawerEnabled and true or false
end

function IchaUIUF_tankDrawerMinimal()
    local d = db()
    return d.tankDrawerMinimal and true or false
end

function IchaUIUF_tankDrawerSide()
    local d = db()
    local s = d.tankDrawerSide
    if s == "right" or s == "up" or s == "down" or s == "radial" then return s end
    return "left"
end

-- How far the target portrait overhangs past the RIGHT edge (for ToT padding)
function IchaUIUF_targetPortraitOverhang()
    if not target or not target.hasPortrait then return 0 end
    if target.portraitEnabled == false then return 0 end
    local h = tonumber(target.height) or BASE_H
    local psc = tonumber(target.portraitScale) or PORTRAIT_DEFAULT_SCALE
    local ph = math.floor(h * psc + 0.5)
    if ph < 28 then ph = 28 end
    local cutIn = math.floor(ph * 0.32 + 0.5)
    local ox = tonumber(target.portraitOffsetX) or 0
    local overhang = (ph - cutIn) + ox
    if overhang < 0 then overhang = 0 end
    local pring = tonumber(target.portraitRing) or PORTRAIT_DEFAULT_RING
    local ringSz = math.floor(ph * pring + 0.5)
    local ringOver = math.floor((ringSz - ph) / 2 + 0.5)
    if ringOver > 0 then overhang = overhang + ringOver end
    return overhang
end

-- Slim resist strip width (pad + col); hugs caret
local TANK_MINIMAL_W = 2 + 30

local tankCaret = CreateFrame("Button", "IchaUIUF_TankCaret", target.root)
tankCaret:SetWidth(TANK_CARET_W)
tankCaret:SetHeight(BASE_H)
tankCaret:SetFrameLevel((target.root:GetFrameLevel() or 1) + 12)
tankCaret:EnableMouse(true)
tankCaret:RegisterForClicks("LeftButtonUp")
do
    -- Arrow only — no border / background (MoneyFrame Left arrow)
    if tankCaret.SetBackdrop then tankCaret:SetBackdrop(nil) end
    local arrowTex = tankCaret:CreateTexture(nil, "ARTWORK")
    arrowTex:SetWidth(24)
    arrowTex:SetHeight(24)
    arrowTex:SetPoint("CENTER", tankCaret, "CENTER", TANK_ARROW_NUDGE_X, 0)
    tankCaret.arrowTex = arrowTex
    tankCaret._arrowLeft = true
    tankCaret._arrowPressed = false
        tankCaret.UpdateArrow = function(self, pointLeft, pressed)
        if pointLeft ~= nil then
            if pointLeft == true or pointLeft == "left" then
                self._arrowDir = "left"
            elseif pointLeft == false or pointLeft == "right" then
                self._arrowDir = "right"
            elseif pointLeft == "up" or pointLeft == "down" then
                self._arrowDir = pointLeft
            end
            self._arrowLeft = (self._arrowDir == "left") and true or false
        end
        if pressed ~= nil then self._arrowPressed = pressed and true or false end
        local tex = self.arrowTex
        if not tex then return end
        local dir = self._arrowDir or "left"
        local ox, oy = TANK_ARROW_NUDGE_X, 0
        if dir == "up" or dir == "down" then
            ox, oy = 0, 0
            -- PointUp/PointDown files are labeled opposite of the glyph (same as minimap handle)
            if self._arrowPressed then
                if dir == "up" then
                    tex:SetTexture("Interface\\AddOns\\IchaUI\\media\\Arrow-PointDown-Down.tga")
                else
                    tex:SetTexture("Interface\\AddOns\\IchaUI\\media\\Arrow-PointUp-Down.tga")
                end
            else
                if dir == "up" then
                    tex:SetTexture("Interface\\AddOns\\IchaUI\\media\\Arrow-PointDown-Up.tga")
                else
                    tex:SetTexture("Interface\\AddOns\\IchaUI\\media\\Arrow-PointUp-Up.tga")
                end
            end
            tex:SetTexCoord(0, 1, 0, 1)
        else
            if self._arrowPressed then
                tex:SetTexture("Interface\\AddOns\\IchaUI\\media\\Arrow-Left-Down.tga")
            else
                tex:SetTexture("Interface\\AddOns\\IchaUI\\media\\Arrow-Left-Up.tga")
            end
            if dir == "left" then
                tex:SetTexCoord(0, 1, 0, 1)
            else
                tex:SetTexCoord(1, 0, 0, 1)
            end
        end
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", self, "CENTER", ox, oy)
        local aw = 24
        if IchaUI_DrawerButtonScale then
            aw = math.floor(24 * IchaUI_DrawerButtonScale("resists") + 0.5)
        end
        if aw < 8 then aw = 8 end
        tex:SetWidth(aw)
        tex:SetHeight(aw)
        tex:SetVertexColor(1, 1, 1, 1)
        tex:Show()
    end
    -- Compat shim: old fs:SetText("<"|">") callers
    tankCaret.fs = {
        SetText = function(_, s)
            if s == "<" then
                tankCaret:UpdateArrow("left", false)
            elseif s == "^" then
                tankCaret:UpdateArrow("up", false)
            elseif s == "v" then
                tankCaret:UpdateArrow("down", false)
            else
                tankCaret:UpdateArrow("right", false)
            end
        end,
    }
    tankCaret:UpdateArrow(false, false)
    tankCaret:SetScript("OnMouseDown", function()
        this:UpdateArrow(nil, true)
    end)
    tankCaret:SetScript("OnMouseUp", function()
        this:UpdateArrow(nil, false)
        if arg1 == "RightButton" and IchaUI_DrawerEditClick then IchaUI_DrawerEditClick("resists") end
    end)
    tankCaret:SetScript("OnLeave", function()
        this:UpdateArrow(nil, false)
    end)
end

local tankDrawer = CreateFrame("Frame", "IchaUIUF_TankDrawer", target.root)
tankDrawer:SetWidth(TANK_DRAWER_W)
tankDrawer:SetHeight(TANK_DRAWER_H)
tankDrawer:SetFrameLevel((target.root:GetFrameLevel() or 1) + 10)
tankDrawer:EnableMouse(true)
tankDrawer:Hide()
do
    -- No border / background around the drawer
    if tankDrawer.SetBackdrop then tankDrawer:SetBackdrop(nil) end
end

-- Minimal resists: numbers only (no tooltip chrome)
function IchaUIUF_applyTankDrawerChrome(minimal)
    if not tankDrawer or not tankDrawer.SetBackdrop then return end
    if minimal then
        tankDrawer:SetBackdrop(nil)
        return
    end
    -- Full drawer open: gold border + dark glass (caret stays arrow-only)
    tankDrawer:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    tankDrawer:SetBackdropColor(TANK_CHAT_BG[1], TANK_CHAT_BG[2], TANK_CHAT_BG[3], TANK_CHAT_BG[4])
    IchaUI_PaintGoldBorder(tankDrawer, 1)
end

function IchaUIUF_tankFS(parent, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    local fp, fsz = GameFontHighlightSmall:GetFont()
    local resistSize = 8
    if IchaUI_DrawerStyleGet then
        local savedStrata, savedSize = IchaUI_DrawerStyleGet("resists")
        if savedSize and savedSize >= 6 then resistSize = savedSize end
        if savedStrata and savedStrata ~= "" and parent and parent.SetFrameStrata then
            pcall(function() parent:SetFrameStrata(savedStrata) end)
        end
    end
    if fp then fs:SetFont(fp, resistSize, "OUTLINE") end
    return fs
end

-- Layout: resists LEFT (colored), type/armor/dmg/speed RIGHT.
-- Drawer matches full target height; width sized so nothing truncates.
local RES_COLS = {
    { idx = 6, r = 1.00, g = 1.00, b = 1.00 }, -- Arcane (white)
    { idx = 2, r = 1.00, g = 0.35, b = 0.15 }, -- Fire
    { idx = 3, r = 0.30, g = 0.90, b = 0.30 }, -- Nature
    { idx = 4, r = 0.40, g = 0.75, b = 1.00 }, -- Frost
    { idx = 5, r = 0.70, g = 0.40, b = 0.95 }, -- Shadow
    { idx = 1, r = 1.00, g = 0.90, b = 0.40 }, -- Holy
}
local TANK_PAD = 3
local TANK_RES_STEP = 8 -- overridden in layout to fit full height
local TANK_RES_COL_W = 30 -- room for "999" with outline, no clip
local TANK_RIGHT_X = 4 + TANK_RES_COL_W + 4
local TANK_RIGHT_W = TANK_DRAWER_W - TANK_RIGHT_X - 4 -- ~74: fits "Humanoid", "1234–5678"
local TANK_OVERLAP = 14 -- snug caret to frame + drawer

local tankRes = {}
do
    local i
    for i = 1, 6 do
        local fs = IchaUIUF_tankFS(tankDrawer, "LEFT")
        fs:SetJustifyH("LEFT")
        fs:SetWidth(TANK_RES_COL_W)
        if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
        fs:SetPoint("TOPLEFT", tankDrawer, "TOPLEFT", 4, -(TANK_PAD + (i - 1) * TANK_RES_STEP))
        local c = RES_COLS[i]
        fs:SetTextColor(c.r, c.g, c.b)
        tankRes[i] = fs
    end
end

function IchaUIUF_tankRightFS()
    local fs = IchaUIUF_tankFS(tankDrawer, "LEFT")
    fs:SetJustifyH("LEFT")
    fs:SetWidth(TANK_RIGHT_W)
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
    return fs
end

local tankType = IchaUIUF_tankRightFS()
tankType:SetPoint("TOPLEFT", tankDrawer, "TOPLEFT", TANK_RIGHT_X, -TANK_PAD)
tankType:SetTextColor(0.7, 0.7, 0.65)

local tankArmor = IchaUIUF_tankRightFS()
tankArmor:SetPoint("TOPLEFT", tankType, "BOTTOMLEFT", 0, 0)
tankArmor:SetTextColor(0.92, 0.88, 0.75)

local tankDmg = IchaUIUF_tankRightFS()
tankDmg:SetPoint("TOPLEFT", tankArmor, "BOTTOMLEFT", 0, 0)
tankDmg:SetTextColor(0.92, 0.88, 0.75)

local tankSpeed = IchaUIUF_tankRightFS()
tankSpeed:SetPoint("TOPLEFT", tankDmg, "BOTTOMLEFT", 0, 0)
tankSpeed:SetTextColor(0.92, 0.88, 0.75)

function IchaUIUF_ApplyResistTextSize()
    local sz = 8
    local strata
    if IchaUI_DrawerStyleGet then
        local savedStrata, savedSize = IchaUI_DrawerStyleGet("resists")
        if savedSize and savedSize >= 6 then sz = savedSize end
        if savedStrata and savedStrata ~= "" then strata = savedStrata end
    end
    local fp = GameFontHighlightSmall:GetFont()
    if fp then
        local i
        for i = 1, 6 do
            if tankRes[i] then tankRes[i]:SetFont(fp, sz, "OUTLINE") end
        end
        if tankType then tankType:SetFont(fp, sz, "OUTLINE") end
        if tankArmor then tankArmor:SetFont(fp, sz, "OUTLINE") end
        if tankDmg then tankDmg:SetFont(fp, sz, "OUTLINE") end
        if tankSpeed then tankSpeed:SetFont(fp, sz, "OUTLINE") end
    end
    if strata and tankDrawer and tankDrawer.SetFrameStrata then
        pcall(function()
            tankDrawer:SetFrameStrata(strata)
            local parent = tankDrawer:GetParent()
            local base = 1
            if parent and parent.GetFrameLevel then base = parent:GetFrameLevel() or 1 end
            tankDrawer:SetFrameLevel(base + 20)
        end)
    end
end

function IchaUIUF_fmtNum(n)
    n = tonumber(n)
    if not n then return "—" end
    if n < 0 then return "—" end
    if n >= 1000 then
        return string.format("%d", math.floor(n + 0.5))
    end
    if math.abs(n - math.floor(n + 0.5)) < 0.05 then
        return string.format("%d", math.floor(n + 0.5))
    end
    return string.format("%.1f", n)
end

function IchaUIUF_resistEffective(unit, idx)
    if type(UnitResistance) ~= "function" then return 0 end
    local ok, a, b = pcall(UnitResistance, unit, idx)
    if not ok then return 0 end
    return tonumber(b) or tonumber(a) or 0
end

function IchaUIUF_refreshTankDrawer()
    local unit = "target"
    local has = UnitExists and UnitExists(unit)
    if not has and not (IchaUIUF_GetTestMode and IchaUIUF_GetTestMode()) then
        tankType:SetText("")
        tankArmor:SetText("—")
        tankDmg:SetText("—")
        tankSpeed:SetText("—")
        local i
        for i = 1, 6 do
            tankRes[i]:SetText("—")
        end
        return
    end

    local ctype = (has and UnitCreatureType and UnitCreatureType(unit)) or ""
    if ctype == "" and IchaUIUF_GetTestMode and IchaUIUF_GetTestMode() then
        ctype = "Humanoid"
    end
    tankType:SetText(ctype or "")

    local armor = 0
    if has and type(UnitArmor) == "function" then
        local ok, a, b = pcall(UnitArmor, unit)
        if ok then armor = tonumber(b) or tonumber(a) or 0 end
    end
    if armor == 0 and has then
        local r0 = IchaUIUF_resistEffective(unit, 0)
        if r0 > 0 then armor = r0 end
    end
    if (not has) and IchaUIUF_GetTestMode and IchaUIUF_GetTestMode() then
        armor = 3842
    end
    tankArmor:SetText(IchaUIUF_fmtNum(armor))

    local dmgLo, dmgHi = nil, nil
    if has and type(UnitDamage) == "function" then
        local ok, lo, hi = pcall(UnitDamage, unit)
        if ok then dmgLo, dmgHi = tonumber(lo), tonumber(hi) end
    end
    if dmgLo and dmgHi then
        tankDmg:SetText(IchaUIUF_fmtNum(dmgLo) .. "–" .. IchaUIUF_fmtNum(dmgHi))
    elseif IchaUIUF_GetTestMode and IchaUIUF_GetTestMode() and not has then
        tankDmg:SetText("45–67")
    else
        tankDmg:SetText("—")
    end

    local spd, oh = nil, nil
    if has and type(UnitAttackSpeed) == "function" then
        local ok, s, o = pcall(UnitAttackSpeed, unit)
        if ok then spd, oh = tonumber(s), tonumber(o) end
    end
    if spd and spd > 0 then
        local t = IchaUIUF_fmtNum(spd) .. "s"
        if oh and oh > 0 then t = t .. "/" .. IchaUIUF_fmtNum(oh) .. "s" end
        tankSpeed:SetText(t)
    elseif IchaUIUF_GetTestMode and IchaUIUF_GetTestMode() and not has then
        tankSpeed:SetText("2.0s")
    else
        tankSpeed:SetText("—")
    end

    local i
    for i = 1, 6 do
        local c = RES_COLS[i]
        local v = 0
        if has then
            v = IchaUIUF_resistEffective(unit, c.idx)
        elseif IchaUIUF_GetTestMode and IchaUIUF_GetTestMode() then
            v = ({12, 8, 15, 5, 20, 3})[i]
        end
        tankRes[i]:SetText(IchaUIUF_fmtNum(v))
        tankRes[i]:SetTextColor(c.r, c.g, c.b)
    end
end

function IchaUIUF_layoutTargetCluster()
    if not target or not target.root or not tot or not tot.root then return end
    local th = target.root:GetHeight() or BASE_H
    local tw = target.root:GetWidth() or BASE_W

    local enabled = IchaUIUF_tankDrawerEnabled()
    local minimal = IchaUIUF_tankDrawerMinimal()
    local open = IchaUIUF_tankDrawerOpen()
    if not enabled then
        open = false
        IchaUIUF_setTankDrawerOpen(false)
    end

    -- Full-height resist column; resistances stay nearest the caret.
    -- Closed/minimal: slim strip nestled into the caret.
    -- Open: full tooltip flush to caret; resists stay on caret side, stats outer.
    -- side "right": resists LEFT (by handle), type/armor RIGHT.
    -- side "left":  resists RIGHT (by handle), type/armor LEFT.
    do
        local sideNow = IchaUIUF_tankDrawerSide()
        local usable = th - TANK_PAD * 2
        if usable < 36 then usable = 36 end
        local step = usable / 6
        local i
        local resistSz = 8
        if IchaUI_DrawerStyleGet then
            local _, savedSize = IchaUI_DrawerStyleGet("resists")
            if savedSize and savedSize >= 6 then resistSz = savedSize end
            if resistSz > 28 then resistSz = 28 end
        end
        local pop = 1
        if IchaUI_DrawerPopScale then pop = IchaUI_DrawerPopScale("resists") end
        local openW = math.floor(TANK_DRAWER_W * pop + 0.5)
        local resCol = math.floor(TANK_RES_COL_W * pop + 0.5)
        if resCol < 16 then resCol = 16 end
        local statsW = openW - (4 + resCol + 4) - 4
        local statsMin = math.floor(56 * pop + 0.5)
        if statsW < statsMin then statsW = statsMin end
        for i = 1, 6 do
            if tankRes[i] then
                tankRes[i]:ClearAllPoints()
                tankRes[i]:SetWidth(resCol)
                if tankRes[i].SetNonSpaceWrap then tankRes[i]:SetNonSpaceWrap(false) end
                local fp = GameFontHighlightSmall:GetFont()
                if fp then tankRes[i]:SetFont(fp, resistSz, "OUTLINE") end
                if sideNow == "left" then
                    -- Nestled against caret (drawer RIGHT); open keeps them here
                    tankRes[i]:SetJustifyH("RIGHT")
                    local pad = open and -4 or -1
                    tankRes[i]:SetPoint("TOPRIGHT", tankDrawer, "TOPRIGHT", pad, -(TANK_PAD + (i - 1) * step))
                else
                    tankRes[i]:SetJustifyH("LEFT")
                    local pad = open and 4 or 1
                    tankRes[i]:SetPoint("TOPLEFT", tankDrawer, "TOPLEFT", pad, -(TANK_PAD + (i - 1) * step))
                end
            end
        end
        local function fitStats(fs)
            if not fs then return end
            fs:SetJustifyH("LEFT")
            fs:SetWidth(statsW)
            if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
            local fp = GameFontHighlightSmall:GetFont()
            if fp then fs:SetFont(fp, resistSz, "OUTLINE") end
        end
        fitStats(tankType); fitStats(tankArmor); fitStats(tankDmg); fitStats(tankSpeed)
        local lineH = resistSz
        local gapY = 1
        local blockH = 4 * lineH + 3 * gapY
        local topOff = (th - blockH) / 2
        if topOff < TANK_PAD then topOff = TANK_PAD end
        tankType:ClearAllPoints()
        tankArmor:ClearAllPoints()
        tankDmg:ClearAllPoints()
        tankSpeed:ClearAllPoints()
        if sideNow == "left" then
            -- Stats on the outer (left) side — shift over with the open tooltip
            tankType:SetPoint("TOPLEFT", tankDrawer, "TOPLEFT", 4, -topOff)
        else
            tankType:SetPoint("TOPLEFT", tankDrawer, "TOPLEFT", 4 + resCol + 4, -topOff)
        end
        tankArmor:SetPoint("TOPLEFT", tankType, "BOTTOMLEFT", 0, -gapY)
        tankDmg:SetPoint("TOPLEFT", tankArmor, "BOTTOMLEFT", 0, -gapY)
        tankSpeed:SetPoint("TOPLEFT", tankDmg, "BOTTOMLEFT", 0, -gapY)
    end

    -- Show/hide right-column texts (type/armor/dmg/speed)
    local function setRightVisible(vis)
        if tankType then if vis then tankType:Show() else tankType:Hide() end end
        if tankArmor then if vis then tankArmor:Show() else tankArmor:Hide() end end
        if tankDmg then if vis then tankDmg:Show() else tankDmg:Hide() end end
        if tankSpeed then if vis then tankSpeed:Show() else tankSpeed:Hide() end end
    end

    local side = IchaUIUF_tankDrawerSide() -- "left" (inside/default) or "right"
    local portPad = IchaUIUF_targetPortraitOverhang()
    local totBase = TANK_GAP - TANK_OVERLAP + portPad
    local caretW = TANK_CARET_W
    if IchaUI_DrawerButtonScale then
        caretW = math.floor(TANK_CARET_W * IchaUI_DrawerButtonScale("resists") + 0.5)
    end
    if caretW < 10 then caretW = 10 end
    local pop = 1
    if IchaUI_DrawerPopScale then pop = IchaUI_DrawerPopScale("resists") end
    local openW = math.floor(TANK_DRAWER_W * pop + 0.5)
    local minW = math.floor((2 + TANK_RES_COL_W) * pop + 0.5)

    if not enabled then
        -- Mob stats OFF: hide caret + drawer; ToT docks to target right (+ portrait pad)
        tankCaret:Hide()
        tankDrawer:Hide()
        setRightVisible(false)
        tot.root:ClearAllPoints()
        tot.root:SetPoint("LEFT", target.root, "RIGHT", totBase, 0)
        return
    end

    tankCaret:SetParent(target.root)
    tankCaret:ClearAllPoints()
    tankCaret:Show()

    if side == "left" then
        -- Inside edge (toward screen center): caret on LEFT, drawer pops further LEFT
        tankCaret:SetHeight(th)
        tankCaret:SetWidth(caretW)
        tankCaret:SetPoint("TOPRIGHT", target.root, "TOPLEFT", TANK_OVERLAP, 0)
        tankCaret:SetPoint("BOTTOMRIGHT", target.root, "BOTTOMLEFT", TANK_OVERLAP, 0)

        if open then
            tankCaret.fs:SetText(">")
            tankDrawer:SetParent(tankCaret)
            tankDrawer:Show()
            IchaUIUF_applyTankDrawerChrome(false)
            tankDrawer:SetWidth(openW)
            tankDrawer:ClearAllPoints()
            tankDrawer:SetPoint("TOPRIGHT", tankCaret, "TOPLEFT", TANK_OPEN_SEP, 0)
            tankDrawer:SetPoint("BOTTOMRIGHT", tankCaret, "BOTTOMLEFT", TANK_OPEN_SEP, 0)
            setRightVisible(true)
            IchaUIUF_refreshTankDrawer()
        elseif minimal then
            tankCaret.fs:SetText("<")
            tankDrawer:SetParent(tankCaret)
            tankDrawer:Show()
            IchaUIUF_applyTankDrawerChrome(true)
            local mw = minW
            tankDrawer:SetWidth(mw)
            tankDrawer:ClearAllPoints()
            tankDrawer:SetPoint("TOPRIGHT", tankCaret, "TOPLEFT", TANK_MINIMAL_SEP, 0)
            tankDrawer:SetPoint("BOTTOMRIGHT", tankCaret, "BOTTOMLEFT", TANK_MINIMAL_SEP, 0)
            setRightVisible(false)
            IchaUIUF_refreshTankDrawer()
        else
            tankCaret.fs:SetText("<")
            tankDrawer:Hide()
            setRightVisible(false)
        end

        -- ToT always on RIGHT of target; clear portrait overhang
        tot.root:ClearAllPoints()
        tot.root:SetPoint("LEFT", target.root, "RIGHT", totBase, 0)
    elseif side == "up" then
        tankCaret:SetWidth(tw)
        tankCaret:SetHeight(caretW)
        tankCaret:SetPoint("BOTTOMLEFT", target.root, "TOPLEFT", 0, -TANK_OVERLAP)
        tankCaret:SetPoint("BOTTOMRIGHT", target.root, "TOPRIGHT", 0, -TANK_OVERLAP)
        tankDrawer:SetParent(tankCaret)
        tankDrawer:ClearAllPoints()
        if open then
            tankCaret.fs:SetText("v")
            tankDrawer:Show()
            IchaUIUF_applyTankDrawerChrome(false)
            tankDrawer:SetWidth(openW)
            tankDrawer:SetHeight(th)
            tankDrawer:SetPoint("BOTTOM", tankCaret, "TOP", 0, TANK_OPEN_SEP)
            setRightVisible(true)
            IchaUIUF_refreshTankDrawer()
        elseif minimal then
            tankCaret.fs:SetText("^")
            tankDrawer:Show()
            IchaUIUF_applyTankDrawerChrome(true)
            local mw = minW
            tankDrawer:SetWidth(mw)
            tankDrawer:SetHeight(th)
            tankDrawer:SetPoint("BOTTOM", tankCaret, "TOP", 0, TANK_MINIMAL_SEP)
            setRightVisible(false)
            IchaUIUF_refreshTankDrawer()
        else
            tankCaret.fs:SetText("^")
            tankDrawer:Hide()
            setRightVisible(false)
        end
        tot.root:ClearAllPoints()
        tot.root:SetPoint("LEFT", target.root, "RIGHT", totBase, 0)
    elseif side == "down" then
        tankCaret:SetWidth(tw)
        tankCaret:SetHeight(caretW)
        tankCaret:SetPoint("TOPLEFT", target.root, "BOTTOMLEFT", 0, TANK_OVERLAP)
        tankCaret:SetPoint("TOPRIGHT", target.root, "BOTTOMRIGHT", 0, TANK_OVERLAP)
        tankDrawer:SetParent(tankCaret)
        tankDrawer:ClearAllPoints()
        if open then
            tankCaret.fs:SetText("^")
            tankDrawer:Show()
            IchaUIUF_applyTankDrawerChrome(false)
            tankDrawer:SetWidth(openW)
            tankDrawer:SetHeight(th)
            tankDrawer:SetPoint("TOP", tankCaret, "BOTTOM", 0, -TANK_OPEN_SEP)
            setRightVisible(true)
            IchaUIUF_refreshTankDrawer()
        elseif minimal then
            tankCaret.fs:SetText("v")
            tankDrawer:Show()
            IchaUIUF_applyTankDrawerChrome(true)
            local mw = minW
            tankDrawer:SetWidth(mw)
            tankDrawer:SetHeight(th)
            tankDrawer:SetPoint("TOP", tankCaret, "BOTTOM", 0, -TANK_MINIMAL_SEP)
            setRightVisible(false)
            IchaUIUF_refreshTankDrawer()
        else
            tankCaret.fs:SetText("v")
            tankDrawer:Hide()
            setRightVisible(false)
        end
        tot.root:ClearAllPoints()
        tot.root:SetPoint("LEFT", target.root, "RIGHT", totBase, 0)
    elseif side == "radial" then
        tankCaret:SetHeight(th)
        tankCaret:SetWidth(caretW)
        tankCaret:SetPoint("TOPRIGHT", target.root, "TOPLEFT", TANK_OVERLAP, 0)
        tankCaret:SetPoint("BOTTOMRIGHT", target.root, "BOTTOMLEFT", TANK_OVERLAP, 0)
        tankDrawer:SetParent(tankCaret)
        tankDrawer:ClearAllPoints()
        if open then
            tankCaret.fs:SetText("*")
            tankDrawer:Show()
            IchaUIUF_applyTankDrawerChrome(true)
            tankDrawer:SetWidth(2)
            tankDrawer:SetHeight(2)
            tankDrawer:SetPoint("CENTER", tankCaret, "CENTER", 0, 0)
            setRightVisible(true)
            IchaUIUF_refreshTankDrawer()
            local bits = {}
            local bi
            for bi = 1, 6 do
                if tankRes[bi] then table.insert(bits, tankRes[bi]) end
            end
            if tankType then table.insert(bits, tankType) end
            if tankArmor then table.insert(bits, tankArmor) end
            if tankDmg then table.insert(bits, tankDmg) end
            if tankSpeed then table.insert(bits, tankSpeed) end
            local bc = table.getn(bits)
            local spread = 90
            if IchaUIUF_GetTankDrawerSpread then spread = IchaUIUF_GetTankDrawerSpread() end
            local radius = caretW + 4
            if IchaUI_DrawerRadialRadius then
                radius = IchaUI_DrawerRadialRadius(bc, caretW, math.floor(18 * pop + 0.5), 4, spread)
            end
            for bi = 1, bc do
                local fs = bits[bi]
                local rx, ry = 0, caretW
                if IchaUI_DrawerRadialXY then rx, ry = IchaUI_DrawerRadialXY(bi, bc, radius, db().tankDrawerArc, db().tankDrawerRot) end
                fs:ClearAllPoints()
                fs:SetPoint("CENTER", tankCaret, "CENTER", rx, ry)
            end
        elseif minimal then
            tankCaret.fs:SetText("<")
            tankDrawer:Show()
            IchaUIUF_applyTankDrawerChrome(true)
            local mw = minW
            tankDrawer:SetWidth(mw)
            tankDrawer:SetHeight(th)
            tankDrawer:SetPoint("TOPRIGHT", tankCaret, "TOPLEFT", TANK_MINIMAL_SEP, 0)
            tankDrawer:SetPoint("BOTTOMRIGHT", tankCaret, "BOTTOMLEFT", TANK_MINIMAL_SEP, 0)
            setRightVisible(false)
            IchaUIUF_refreshTankDrawer()
        else
            tankCaret.fs:SetText("<")
            tankDrawer:Hide()
            setRightVisible(false)
        end
        tot.root:ClearAllPoints()
        tot.root:SetPoint("LEFT", target.root, "RIGHT", totBase, 0)
    else
        -- Classic RIGHT side: caret on target right, drawer pops further right
        tankCaret:SetHeight(th)
        tankCaret:SetWidth(caretW)
        tankCaret:SetPoint("TOPLEFT", target.root, "TOPRIGHT", -TANK_OVERLAP, 0)
        tankCaret:SetPoint("BOTTOMLEFT", target.root, "BOTTOMRIGHT", -TANK_OVERLAP, 0)

        if open then
            tankCaret.fs:SetText("<")
            tankDrawer:SetParent(tankCaret)
            tankDrawer:Show()
            IchaUIUF_applyTankDrawerChrome(false)
            tankDrawer:SetWidth(openW)
            tankDrawer:ClearAllPoints()
            tankDrawer:SetPoint("TOPLEFT", tankCaret, "TOPRIGHT", -TANK_OPEN_SEP, 0)
            tankDrawer:SetPoint("BOTTOMLEFT", tankCaret, "BOTTOMRIGHT", -TANK_OPEN_SEP, 0)
            setRightVisible(true)
            IchaUIUF_refreshTankDrawer()

            tot.root:ClearAllPoints()
            local slide = caretW + openW + TANK_GAP - TANK_OVERLAP * 2
            if totBase > slide then slide = totBase end
            tot.root:SetPoint("LEFT", target.root, "RIGHT", slide, 0)
        elseif minimal then
            tankCaret.fs:SetText(">")
            tankDrawer:SetParent(tankCaret)
            tankDrawer:Show()
            IchaUIUF_applyTankDrawerChrome(true)
            local mw = minW
            tankDrawer:SetWidth(mw)
            tankDrawer:ClearAllPoints()
            tankDrawer:SetPoint("TOPLEFT", tankCaret, "TOPRIGHT", -TANK_MINIMAL_SEP, 0)
            tankDrawer:SetPoint("BOTTOMLEFT", tankCaret, "BOTTOMRIGHT", -TANK_MINIMAL_SEP, 0)
            setRightVisible(false)
            IchaUIUF_refreshTankDrawer()

            tot.root:ClearAllPoints()
            local slide = caretW + mw + TANK_GAP - TANK_OVERLAP * 2
            if totBase > slide then slide = totBase end
            tot.root:SetPoint("LEFT", target.root, "RIGHT", slide, 0)
        else
            tankCaret.fs:SetText(">")
            tankDrawer:Hide()
            setRightVisible(false)
            tot.root:ClearAllPoints()
            local slide = caretW + TANK_GAP - TANK_OVERLAP
            if totBase > slide then slide = totBase end
            tot.root:SetPoint("LEFT", target.root, "RIGHT", slide, 0)
        end
    end
end

tankCaret:SetScript("OnClick", function()
    IchaUIUF_setTankDrawerOpen(not IchaUIUF_tankDrawerOpen())
    IchaUIUF_layoutTargetCluster()
end)

-- No GameTooltip — the drawer itself is the tip that grows out of the caret
tankCaret:SetScript("OnEnter", nil)
tankCaret:SetScript("OnLeave", nil)

-- Refresh stats while open; re-dock when target size / open state changes
local tankTicker = CreateFrame("Frame")
local tankElapsed = 0
local lastTankTw, lastTankTh, lastTankOpen = nil, nil, nil
tankTicker:SetScript("OnUpdate", function()
    if IchaUI_LEAVING then return end
    tankElapsed = tankElapsed + arg1
    -- Poll ~10Hz while open (or minimal strip) so resists track live
    local enabled = IchaUIUF_tankDrawerEnabled()
    local minimal = IchaUIUF_tankDrawerMinimal()
    local open = IchaUIUF_tankDrawerOpen()
    local live = enabled and (open or minimal)
    local need = live and 0.1 or 0.25
    if tankElapsed < need then return end
    tankElapsed = 0
    if not target or not target.root or not target.root:IsVisible() then
        return
    end
    local tw = target.root:GetWidth() or 0
    local th = target.root:GetHeight() or 0
    local sideNow = IchaUIUF_tankDrawerSide()
    local sideBit = 0
    if sideNow == "right" then sideBit = 1
    elseif sideNow == "up" then sideBit = 2
    elseif sideNow == "down" then sideBit = 3
    end
    local stateKey = (enabled and 1 or 0) * 8 + (minimal and 1 or 0) * 4 + (open and 1 or 0) * 2 + sideBit
    if tw ~= lastTankTw or th ~= lastTankTh or stateKey ~= lastTankOpen then
        lastTankTw, lastTankTh, lastTankOpen = tw, th, stateKey
        IchaUIUF_layoutTargetCluster()
    elseif live then
        IchaUIUF_refreshTankDrawer()
    end
end)

function IchaUIUF_LayoutTargetCluster()
    IchaUIUF_layoutTargetCluster()
end

function IchaUIUF_SetTankDrawer(on)
    IchaUIUF_setTankDrawerOpen(on)
    IchaUIUF_layoutTargetCluster()
end

function IchaUIUF_GetTankDrawer()
    return IchaUIUF_tankDrawerOpen()
end

function IchaUIUF_GetTankDrawerEnabled()
    return IchaUIUF_tankDrawerEnabled()
end

function IchaUIUF_SetTankDrawerEnabled(on)
    local d = db()
    d.tankDrawerEnabled = on and true or false
    if not d.tankDrawerEnabled then
        d.tankDrawerOpen = false
    end
    IchaUIDB.uf = d
    IchaUIUF_layoutTargetCluster()
end

function IchaUIUF_GetTankDrawerMinimal()
    return IchaUIUF_tankDrawerMinimal()
end

function IchaUIUF_SetTankDrawerMinimal(on)
    local d = db()
    d.tankDrawerMinimal = on and true or false
    IchaUIDB.uf = d
    IchaUIUF_layoutTargetCluster()
end

function IchaUIUF_GetTankDrawerSide()
    return IchaUIUF_tankDrawerSide()
end

function IchaUIUF_GetTankDrawerSpread()
    local d = db()
    if IchaUI_DrawerNormSpread then return IchaUI_DrawerNormSpread(d.tankDrawerSpread) end
    local n = tonumber(d.tankDrawerSpread) or 90
    if n < 10 then n = 10 end
    if n > 360 then n = 360 end
    return math.floor(n + 0.5)
end

function IchaUIUF_SetTankDrawerSpread(value)
    local d = db()
    local n = tonumber(value) or 90
    if IchaUI_DrawerNormSpread then n = IchaUI_DrawerNormSpread(n) end
    if n < 10 then n = 10 end
    if n > 360 then n = 360 end
    d.tankDrawerSpread = math.floor(n + 0.5)
    IchaUIDB.uf = d
    IchaUIUF_layoutTargetCluster()
end

function IchaUIUF_GetTankDrawerArc()
    local d = db()
    if IchaUI_DrawerNormArc then return IchaUI_DrawerNormArc(d.tankDrawerArc) end
    local n = tonumber(d.tankDrawerArc) or 360
    if n < 10 then n = 10 end
    if n > 360 then n = 360 end
    return math.floor(n + 0.5)
end

function IchaUIUF_SetTankDrawerArc(value)
    local d = db()
    local n = tonumber(value)
    if n == nil then n = 360 end
    if IchaUI_DrawerNormArc then n = IchaUI_DrawerNormArc(n) end
    if n < 10 then n = 10 end
    if n > 360 then n = 360 end
    d.tankDrawerArc = math.floor(n + 0.5)
    IchaUIDB.uf = d
    IchaUIUF_layoutTargetCluster()
end

function IchaUIUF_GetTankDrawerRot()
    local d = db()
    if IchaUI_DrawerNormRot then return IchaUI_DrawerNormRot(d.tankDrawerRot) end
    if d.tankDrawerRot == nil then return 90 end
    local n = tonumber(d.tankDrawerRot) or 90
    if n < -360 then n = -360 end
    if n > 360 then n = 360 end
    return math.floor(n + 0.5)
end

function IchaUIUF_SetTankDrawerRot(value)
    local d = db()
    local n = tonumber(value)
    if n == nil then n = 90 end
    if IchaUI_DrawerNormRot then n = IchaUI_DrawerNormRot(n) end
    if n < -360 then n = -360 end
    if n > 360 then n = 360 end
    d.tankDrawerRot = math.floor(n + 0.5)
    IchaUIDB.uf = d
    IchaUIUF_layoutTargetCluster()
end

function IchaUIUF_SetTankDrawerSide(side)
    local d = db()
    if side ~= "right" and side ~= "up" and side ~= "down" and side ~= "radial" then side = "left" end
    d.tankDrawerSide = side
    IchaUIDB.uf = d
    IchaUIUF_layoutTargetCluster()
end

IchaUIUF_layoutTargetCluster()

-- Pin party/raid roots by visual CENTER so adding members grows outward.
-- Globals: UnitFrames.lua main chunk is at Lua's 200-local limit.
function IchaUIUF_RootScreenCenter(fr)
    if not fr then return nil end
    local cx, cy = fr:GetCenter()
    if not cx or not cy then return nil end
    local rs = fr:GetEffectiveScale() or 1
    local us = UIParent:GetEffectiveScale() or 1
    return cx * rs / us, cy * rs / us
end

function IchaUIUF_PinRootCenter(fr, sx, sy)
    if not fr or sx == nil or sy == nil then return end
    fr:ClearAllPoints()
    fr:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx, sy)
end

function IchaUIUF_SaveRootCenter(fr, dbrow)
    local sx, sy = IchaUIUF_RootScreenCenter(fr)
    if not sx then return end
    IchaUIUF_PinRootCenter(fr, sx, sy)
    if dbrow then
        dbrow.x = sx
        dbrow.y = sy
        dbrow.point = "CENTER"
        dbrow.relPoint = "BOTTOMLEFT"
    end
end

function IchaUIUF_SizeRootCentered(fr, dbrow, w, h, liveCenter)
    if not fr then return end
    local sx, sy
    if liveCenter then
        sx, sy = IchaUIUF_RootScreenCenter(fr)
    end
    if not sx and dbrow and dbrow.point == "CENTER" and dbrow.x ~= nil then
        sx = tonumber(dbrow.x)
        sy = tonumber(dbrow.y)
    end
    fr:SetWidth(math.max(1, tonumber(w) or 1))
    fr:SetHeight(math.max(1, tonumber(h) or 1))
    if sx and sy then
        IchaUIUF_PinRootCenter(fr, sx, sy)
        return
    end
    -- Old TOPLEFT/BOTTOMLEFT save: keep this layout's look, then pin the new center.
    sx, sy = IchaUIUF_RootScreenCenter(fr)
    if sx then
        IchaUIUF_PinRootCenter(fr, sx, sy)
        if dbrow then
            dbrow.x = sx
            dbrow.y = sy
            dbrow.point = "CENTER"
            dbrow.relPoint = "BOTTOMLEFT"
        end
    end
end


-- Party root: center-pinned horizontal row (shared scale/pad/size)
partyRoot = CreateFrame("Frame", "IchaUIUF_PartyRoot", UIParent)
partyRoot:SetFrameStrata("MEDIUM")
partyRoot:SetWidth(1)
partyRoot:SetHeight(1)
partyRoot:SetMovable(true)
partyRoot:EnableMouse(false)
partyRoot:SetClampedToScreen(true)

partyMover = CreateFrame("Frame", nil, partyRoot)
partyMover:SetAllPoints(partyRoot)
partyMover:EnableMouse(true)
partyMover:RegisterForDrag("LeftButton")
partyMover:Hide()
partyMover:SetFrameLevel((partyRoot:GetFrameLevel() or 1) + 30)
do
    local mbg = partyMover:CreateTexture(nil, "BACKGROUND")
    mbg:SetAllPoints(partyMover)
    mbg:SetTexture(1, 1, 1, 1)
    mbg:SetVertexColor(0.15, 0.45, 0.95, 0.35)
    local ml = partyMover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ml:SetPoint("CENTER", partyMover, "CENTER")
    ml:SetText("Drag party")
end
partyMover:SetScript("OnDragStart", function() partyRoot:StartMoving() end)
partyMover:SetScript("OnDragStop", function()
    partyRoot:StopMovingOrSizing()
    IchaUIUF_SaveRootCenter(partyRoot, partyDb())
    savePartyDb()
end)

local pi
for pi = 1, 4 do
    local ukey = "party" .. pi
    partyFrames[pi] = createUnitFrame(ukey, ukey, { scale = 1, width = BASE_W, height = BASE_H, portrait = false, portraitScale = 1.0 }, {
        parent = partyRoot,
        managedPos = true,
        portrait = true,
        portraitSide = "left",
    })
end

function IchaUIUF_restorePartyRootPos()
    local p = partyDb()
    partyRoot:ClearAllPoints()
    if p.point == "CENTER" and p.x ~= nil then
        IchaUIUF_PinRootCenter(partyRoot, tonumber(p.x) or 0, tonumber(p.y) or 0)
    elseif p.point and p.x ~= nil then
        partyRoot:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x, p.y or 0)
    else
        -- Default: bottom center-ish, above action bars
        partyRoot:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 250)
    end
end

function IchaUIUF_HidePreviewChrome(fr)
    if not fr then return end
    fr._portraitChromeOn = false
    if fr.root then fr.root:Hide() end
    if fr.portraitFrame then fr.portraitFrame:Hide() end
    if fr.portraitRingFrame then fr.portraitRingFrame:Hide() end
    if fr.portraitRingTex then fr.portraitRingTex:Hide() end
    if fr.border then fr.border:Hide() end
    if fr.combatBadge then fr.combatBadge:Hide() end
    if fr.combatIcon then fr.combatIcon:Hide() end
    if fr.levelText then fr.levelText:Hide() end
    if fr.hpLevel then fr.hpLevel:Hide() end
    if fr.hideShieldCharges then fr:hideShieldCharges() end
    if fr.castFrame then fr.castFrame:Hide() end
    if IchaUI_HideUnitRaidMark then IchaUI_HideUnitRaidMark(fr) end
    if IchaUI_HideUnitRoleIcons then IchaUI_HideUnitRoleIcons(fr) end
end

function IchaUIUF_layoutParty()
    local p = partyDb()
    local scale = clamp(tonumber(p.scale) or 1, 0.4, 3)
    local width = clamp(tonumber(p.width) or BASE_W, 1, 600)
    local height = clamp(tonumber(p.height) or BASE_H, 1, 420)
    local gap = clamp(tonumber(p.pad) or 8, 0, 40)
    p.scale, p.width, p.height, p.pad = scale, width, height, gap

    -- Real raid layout → hide party (raid frames take over)
    if shouldShowRaidFrames and shouldShowRaidFrames() and not partyMoving then
        local i
        for i = 1, 4 do
            local fr = partyFrames[i]
            if fr then
                local keep = UnitExists and UnitExists(fr.unit)
                if keep then
                    if fr.root then fr.root:Hide() end
                    if fr.portraitRingFrame then fr.portraitRingFrame:Hide() end
                    if fr.portraitRingTex then fr.portraitRingTex:Hide() end
                    if fr.combatBadge then fr.combatBadge:Hide() end
                    if IchaUI_HideUnitRaidMark then IchaUI_HideUnitRaidMark(fr) end; if IchaUI_HideUnitRoleIcons then IchaUI_HideUnitRoleIcons(fr) end
                else
                    IchaUIUF_HidePreviewChrome(fr)
                end
            end
        end
        if partyRoot then partyRoot:Hide() end
        return
    end

    local shown = {}
    local i
    for i = 1, 4 do
        local fr = partyFrames[i]
        if fr then
            fr.scale = scale
            fr.width = width
            fr.height = height
            local exists = UnitExists and UnitExists(fr.unit)
            -- Test UI: Party toggle forces party frames (independent of raid toggle)
            local want = (not p.hidden) and (exists or (testMode and testShowParty))
            if want then
                fr.hidden = false
                table.insert(shown, fr)
            else
                fr.hidden = p.hidden and true or false
                if exists then
                    if fr.root then fr.root:Hide() end
                    if fr.portraitRingFrame then fr.portraitRingFrame:Hide() end
                    if fr.portraitRingTex then fr.portraitRingTex:Hide() end
                    if fr.combatBadge then fr.combatBadge:Hide() end
                    if IchaUI_HideUnitRaidMark then IchaUI_HideUnitRaidMark(fr) end; if IchaUI_HideUnitRoleIcons then IchaUI_HideUnitRoleIcons(fr) end
                else
                    IchaUIUF_HidePreviewChrome(fr)
                end
            end
        end
    end

    local n = table.getn(shown)
    local fw = math.floor(width * scale + 0.5)
    local fh = math.floor(height * scale + 0.5)
    if n == 0 then
        if partyMoving then
            partyRoot:Show()
            IchaUIUF_SizeRootCentered(partyRoot, p, math.max(1, fw), math.max(1, fh), true)
        else
            partyRoot:Hide()
        end
        return
    end

    partyRoot:Show()
    local grow = p.growth
    if grow ~= "left" and grow ~= "right" and grow ~= "up" and grow ~= "down" and grow ~= "grid" then
        grow = "center"
    end
    if grow == "center" then
        local total = n * fw + (n - 1) * gap
        IchaUIUF_SizeRootCentered(partyRoot, p, total, fh, partyMoving)
        local startX = -total / 2
        for i = 1, n do
            local fr = shown[i]
            fr:applySize()
            fr.root:ClearAllPoints()
            fr.root:SetPoint("LEFT", partyRoot, "CENTER", startX + (i - 1) * (fw + gap), 0)
            fr:update()
        end
        return
    end
    local reachX = fw
    local reachY = fh
    if grow == "left" or grow == "right" then
        reachX = fw + (n - 1) * (fw + gap)
    elseif grow == "up" or grow == "down" then
        reachY = fh + (n - 1) * (fh + gap)
    else
        local cols = 1
        local rows = 1
        if n > 1 then cols = 2 end
        if n > 2 then rows = 2 end
        reachX = cols * fw + (cols - 1) * gap
        reachY = rows * fh + (rows - 1) * gap
    end
    IchaUIUF_SizeRootCentered(partyRoot, p, reachX, reachY, partyMoving)
    for i = 1, n do
        local fr = shown[i]
        fr:applySize()
        fr.root:ClearAllPoints()
        local ox, oy = 0, 0
        local step = i - 1
        if grow == "right" then
            ox = step * (fw + gap)
        elseif grow == "left" then
            ox = -step * (fw + gap)
        elseif grow == "up" then
            oy = step * (fh + gap)
        elseif grow == "down" then
            oy = -step * (fh + gap)
        else
            local col = math.mod(step, 2)
            local row = math.floor(step / 2)
            ox = col * (fw + gap)
            oy = -row * (fh + gap)
        end
        fr.root:SetPoint("CENTER", partyRoot, "CENTER", ox, oy)
        fr:update()
    end
end

function IchaUIUF_hideBlizzardParty(on)
    local i
    for i = 1, 4 do
        local f = getglobal("PartyMemberFrame" .. i)
        if f then
            if on then
                f:Hide()
                f:SetScript("OnShow", function() this:Hide() end)
            else
                f:SetScript("OnShow", nil)
            end
        end
    end
    if PartyMemberBackground then
        if on then
            PartyMemberBackground:Hide()
            PartyMemberBackground:SetScript("OnShow", function() this:Hide() end)
        else
            PartyMemberBackground:SetScript("OnShow", nil)
        end
    end
end

function IchaUIUF_hideBlizzardCastBar()
    local bar = CastingBarFrame
    if not bar then return end
    bar:UnregisterAllEvents()
    bar:Hide()
    bar:SetAlpha(0)
    bar:EnableMouse(false)
    bar:SetScript("OnEvent", nil)
    bar:SetScript("OnUpdate", nil)
    bar:SetScript("OnShow", function()
        this:Hide()
    end)
end

IchaUIUF_hideBlizzardCastBar()

function IchaUIUF_hideBlizzard(on)
    db().hideBlizzard = on and true or false
    if on then
        if PlayerFrame then
            PlayerFrame:Hide()
            PlayerFrame:SetScript("OnShow", function() this:Hide() end)
        end
        if TargetFrame then
            TargetFrame:Hide()
            TargetFrame:SetScript("OnShow", function() this:Hide() end)
        end
        IchaUIUF_hideBlizzardParty(true)
    else
        if PlayerFrame then
            PlayerFrame:SetScript("OnShow", nil)
            PlayerFrame:Show()
        end
        if TargetFrame then
            TargetFrame:SetScript("OnShow", nil)
        end
        IchaUIUF_hideBlizzardParty(false)
    end
end


-- ========== RAID FRAMES (2×20, half-width, pad 0, swap with party) ==========

shouldShowRaidFrames = function()
    -- Test UI: only force raid when the Raid toggle is on
    if testMode then return testShowRaid and true or false end
    local n = 0
    if GetNumRaidMembers then
        n = GetNumRaidMembers() or 0
    end
    if n < 1 then return false end
    if n > 5 then return true end
    -- ≤5 but more than one raid subgroup occupied
    if not GetRaidRosterInfo then return false end
    local seen = {}
    local groups = 0
    local i
    for i = 1, n do
        local name, rank, subgroup = GetRaidRosterInfo(i)
        if subgroup and not seen[subgroup] then
            seen[subgroup] = true
            groups = groups + 1
            if groups > 1 then return true end
        end
    end
    return false
end

raidRoot = CreateFrame("Frame", "IchaUIUF_RaidRoot", UIParent)
raidRoot:SetFrameStrata("MEDIUM")
raidRoot:SetWidth(1)
raidRoot:SetHeight(1)
raidRoot:SetMovable(true)
raidRoot:EnableMouse(false)
raidRoot:SetClampedToScreen(true)

local raidMover = CreateFrame("Frame", nil, raidRoot)
raidMover:SetAllPoints(raidRoot)
raidMover:EnableMouse(true)
raidMover:RegisterForDrag("LeftButton")
raidMover:Hide()
raidMover:SetFrameLevel((raidRoot:GetFrameLevel() or 1) + 30)
do
    local mbg = raidMover:CreateTexture(nil, "BACKGROUND")
    mbg:SetAllPoints(raidMover)
    mbg:SetTexture(1, 1, 1, 1)
    mbg:SetVertexColor(0.85, 0.55, 0.15, 0.35)
    local ml = raidMover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ml:SetPoint("CENTER", raidMover, "CENTER")
    ml:SetText("Drag raid")
end
raidMover:SetScript("OnDragStart", function() raidRoot:StartMoving() end)
raidMover:SetScript("OnDragStop", function()
    raidRoot:StopMovingOrSizing()
    IchaUIUF_SaveRootCenter(raidRoot, raidDb())
    saveRaidDb()
end)

do
    local ri
    for ri = 1, 40 do
        local ukey = "raid" .. ri
        raidFrames[ri] = createUnitFrame(ukey, ukey, { scale = 1, width = RAID_W, height = BASE_H }, {
            parent = raidRoot,
            managedPos = true,
            raidCompact = true,
        })
    end
end

function IchaUIUF_restoreRaidRootPos()
    local r = raidDb()
    raidRoot:ClearAllPoints()
    if r.point == "CENTER" and r.x ~= nil then
        IchaUIUF_PinRootCenter(raidRoot, tonumber(r.x) or 0, tonumber(r.y) or 0)
    elseif r.point and r.x ~= nil then
        raidRoot:SetPoint(r.point, UIParent, r.relPoint or r.point, r.x, r.y or 0)
    else
        -- Default: left-center, above party default
        raidRoot:SetPoint("LEFT", UIParent, "LEFT", 20, 40)
    end
end

layoutRaid = function()
    local r = raidDb()
    local scale = clamp(tonumber(r.scale) or 1, 0.4, 3)
    local width = clamp(tonumber(r.width) or RAID_W, 1, 400)
    local height = clamp(tonumber(r.height) or BASE_H, 1, 420)
    local gap = clamp(tonumber(r.pad) or 0, 0, 40)
    local cols = clamp(tonumber(r.cols) or RAID_COLS, 1, 40)
    local rows = clamp(tonumber(r.rows) or RAID_ROWS, 1, 40)
    if cols * rows > 40 then rows = math.max(1, math.floor(40 / cols)) end
    r.scale, r.width, r.height, r.pad, r.cols, r.rows = scale, width, height, gap, cols, rows

    local fw = math.floor(width * scale + 0.5)
    local fh = math.floor(height * scale + 0.5)
    local slots = cols * rows
    if slots > 40 then slots = 40 end

    if not shouldShowRaidFrames() then
        local i
        for i = 1, 40 do
            local fr = raidFrames[i]
            if fr then
                local keep = UnitExists and UnitExists(fr.unit)
                if keep then
                    if fr.root then fr.root:Hide() end
                    if fr.portraitRingFrame then fr.portraitRingFrame:Hide() end
                    if fr.portraitRingTex then fr.portraitRingTex:Hide() end
                    if fr.border then fr.border:Hide() end
                    if IchaUI_HideUnitRaidMark then IchaUI_HideUnitRaidMark(fr) end; if IchaUI_HideUnitRoleIcons then IchaUI_HideUnitRoleIcons(fr) end
                else
                    IchaUIUF_HidePreviewChrome(fr)
                end
            end
        end
        if raidMoving then
            raidRoot:Show()
            local totalW = cols * fw + (cols - 1) * gap
            local totalH = rows * fh + (rows - 1) * gap
            IchaUIUF_SizeRootCentered(raidRoot, r, totalW, totalH, true)
        else
            raidRoot:Hide()
        end
        return
    end

    if r.hidden and not raidMoving and not testMode then
        local i
        for i = 1, 40 do
            local fr = raidFrames[i]
            if fr then
                local keep = UnitExists and UnitExists(fr.unit)
                if keep then
                    if fr.root then fr.root:Hide() end
                    if fr.portraitRingFrame then fr.portraitRingFrame:Hide() end
                    if fr.portraitRingTex then fr.portraitRingTex:Hide() end
                    if fr.border then fr.border:Hide() end
                    if IchaUI_HideUnitRaidMark then IchaUI_HideUnitRaidMark(fr) end; if IchaUI_HideUnitRoleIcons then IchaUI_HideUnitRoleIcons(fr) end
                else
                    IchaUIUF_HidePreviewChrome(fr)
                end
            end
        end
        raidRoot:Hide()
        return
    end

    -- Test/Move: center the full reserved grid. Live: center only occupied cells.
    local preview = (testMode or raidMoving) and true or false
    local usedCols, usedRows
    if preview then
        usedCols = cols
        usedRows = rows
    else
        local lastI = 0
        local i
        for i = 1, slots do
            local fr = raidFrames[i]
            if fr and UnitExists and UnitExists(fr.unit) then
                lastI = i
            end
        end
        if lastI < 1 then
            local hi
            for hi = 1, 40 do
                local fr = raidFrames[hi]
                if fr then
                    local keep = UnitExists and UnitExists(fr.unit)
                    if keep then
                        if fr.root then fr.root:Hide() end
                        if fr.portraitRingFrame then fr.portraitRingFrame:Hide() end
                        if fr.portraitRingTex then fr.portraitRingTex:Hide() end
                        if fr.border then fr.border:Hide() end
                        if IchaUI_HideUnitRaidMark then IchaUI_HideUnitRaidMark(fr) end; if IchaUI_HideUnitRoleIcons then IchaUI_HideUnitRoleIcons(fr) end
                    else
                        IchaUIUF_HidePreviewChrome(fr)
                    end
                end
            end
            raidRoot:Hide()
            return
        end
        usedRows = math.floor((lastI - 1) / cols) + 1
        if lastI < cols then
            usedCols = lastI
        else
            usedCols = cols
        end
    end

    local totalW = usedCols * fw + (usedCols - 1) * gap
    local totalH = usedRows * fh + (usedRows - 1) * gap
    raidRoot:Show()
    IchaUIUF_SizeRootCentered(raidRoot, r, totalW, totalH, raidMoving)

    local i
    for i = 1, 40 do
        local fr = raidFrames[i]
        if fr then
            fr.scale = scale
            fr.width = width
            fr.height = height
            local exists = UnitExists and UnitExists(fr.unit)
            local inGrid = (i <= slots)
            local want = inGrid and (preview or exists)
            if want then
                fr.hidden = false
                if fr.applySize then fr:applySize() end
                local col = (i - 1) - math.floor((i - 1) / cols) * cols
                local row = math.floor((i - 1) / cols)
                local x = -totalW / 2 + col * (fw + gap)
                local y = totalH / 2 - row * (fh + gap)
                fr.root:ClearAllPoints()
                fr.root:SetPoint("TOPLEFT", raidRoot, "CENTER", x, y)
                fr.root:Show()
                if fr.update then fr:update() end
            else
                fr.hidden = true
                if exists then
                    if fr.root then fr.root:Hide() end
                    if fr.portraitRingFrame then fr.portraitRingFrame:Hide() end
                    if fr.portraitRingTex then fr.portraitRingTex:Hide() end
                    if fr.border then fr.border:Hide() end
                    if IchaUI_HideUnitRaidMark then IchaUI_HideUnitRaidMark(fr) end; if IchaUI_HideUnitRoleIcons then IchaUI_HideUnitRoleIcons(fr) end
                else
                    IchaUIUF_HidePreviewChrome(fr)
                end
            end
        end
    end
end

function IchaUIUF_RaidGet()
    local r = raidDb()
    return {
        scale = r.scale,
        width = r.width,
        height = r.height,
        pad = r.pad,
        gap = r.pad,
        cols = r.cols,
        rows = r.rows,
        hidden = r.hidden and true or false,
        moving = raidMoving and true or false,
        x = r.x,
        y = r.y,
        point = r.point,
    }
end

function IchaUIUF_RaidSet(field, value)
    local r = raidDb()
    if field == "scale" then
        local oldSc = tonumber(r.scale) or 1
        r.scale = clamp(tonumber(value) or r.scale, 0.4, 3)
        if not IchaUI_BarSkipRefit and IchaUIUF_ScaleSavedBars then
            IchaUIUF_ScaleSavedBars("raid", oldSc, r.scale)
        end
    elseif field == "width" then
        r.width = clamp(tonumber(value) or r.width, 1, 400)
    elseif field == "height" then
        r.height = clamp(tonumber(value) or r.height, 1, 420)
        if not IchaUI_BarSkipRefit and IchaUIUF_RefitBarsToHeight then
            IchaUIUF_RefitBarsToHeight("raid", r.height, r.scale)
        end
    elseif field == "pad" or field == "gap" then
        r.pad = clamp(tonumber(value) or r.pad, 0, 40)
    elseif field == "cols" or field == "columns" or field == "col" then
        r.cols = clamp(tonumber(value) or r.cols or RAID_COLS, 1, 40)
        if r.cols * (r.rows or RAID_ROWS) > 40 then
            r.rows = math.max(1, math.floor(40 / r.cols))
        end
    elseif field == "rows" or field == "row" then
        r.rows = clamp(tonumber(value) or r.rows or RAID_ROWS, 1, 40)
        if (r.cols or RAID_COLS) * r.rows > 40 then
            r.cols = math.max(1, math.floor(40 / r.rows))
        end
    elseif field == "hidden" then
        r.hidden = value and true or false
    elseif field == "move" or field == "moving" then
        raidMoving = value and true or false
        if raidMover then
            if raidMoving then
                raidMover:Show()
                raidRoot:EnableMouse(true)
                raidRoot:RegisterForDrag("LeftButton")
                raidRoot:Show()
            else
                raidMover:Hide()
                raidRoot:EnableMouse(false)
                IchaUIUF_SaveRootCenter(raidRoot, r)
            end
        end
        saveRaidDb()
        if layoutRaid then layoutRaid() end
        IchaUIUF_layoutParty()
        return
    else
        return
    end
    saveRaidDb()
    if layoutRaid then layoutRaid() end
end

function IchaUIUF_RaidGetPos()
    if not raidRoot then return 0, 0, "CENTER", "BOTTOMLEFT" end
    local sx, sy = IchaUIUF_RootScreenCenter(raidRoot)
    if sx then return sx, sy, "CENTER", "BOTTOMLEFT" end
    local r = raidDb()
    return tonumber(r.x) or 0, tonumber(r.y) or 0, "CENTER", "BOTTOMLEFT"
end

function IchaUIUF_RaidSetPos(x, y)
    if not raidRoot then return end
    local r = raidDb()
    r.x = tonumber(x) or 0
    r.y = tonumber(y) or 0
    r.point = "CENTER"
    r.relPoint = "BOTTOMLEFT"
    IchaUIUF_PinRootCenter(raidRoot, r.x, r.y)
    saveRaidDb()
end


-- Recolor frames that sampled gold when they were built. Called from the
-- Skin picker so the saved color shows without /reload.
function IchaUIUF_RefreshGoldChrome()
    local map = IchaUI_Swing_Frames
    if map then
        local _, fr
        for _, fr in pairs(map) do
            if fr then
                if fr.border then
                    local e = 12
                    if fr.scale then
                        e = math.floor(12 * fr.scale + 0.5)
                    end
                    if e < 8 then e = 8 end
                    if e > 20 then e = 20 end
                    applyGold(fr.border, e)
                end
                if fr.portraitRingTex and fr.portraitRingFrame then
                    local rf = fr.portraitRingFrame
                    local ringSz = 48
                    if rf.GetWidth then ringSz = rf:GetWidth() or 48 end
                    if ringSz < 16 then ringSz = 16 end
                    applyPortraitRing(fr.portraitRingTex, rf, ringSz)
                end
                if fr.portraitBg and IchaUI_PaintPortraitFill then
                    IchaUI_PaintPortraitFill(fr.portraitBg)
                end
                if IchaUI_Cast_TintArt then IchaUI_Cast_TintArt(fr) end
                if fr.castIconRing then
                    IchaUI_PaintGoldRing(fr.castIconRing)
                end
                if fr.combatBadgeRing then
                    IchaUI_PaintGoldRing(fr.combatBadgeRing)
                end
            end
        end
    end
    if tankDrawer then
        IchaUI_PaintGoldBorder(tankDrawer, 1)
    end
end

function IchaUIUF_refreshAll()
    player:update()
    target:update()
    tot:update()
    IchaUIUF_layoutParty()
    if layoutRaid then layoutRaid() end
    if IchaUI_CombatLayout then IchaUI_CombatLayout() end
end

-- Immediate shield paint (UNIT_AURA / PLAYER_AURAS_CHANGED). Player frame only.
function IchaUIUF_PaintShieldCharges(who)
    if not player or not player.updateShieldCharges then return end
    if not who or who == "" then
        who = "player"
    end
    local hit = (who == "player")
    if not hit and type(who) == "string" and who ~= "none"
        and string.sub(who, 1, 6) ~= "IchaUI"
        and string.sub(who, 1, 9) ~= "nameplate"
        and (string.find(who, "^0[xX]%x+$") or string.find(who, "^[a-z]+%d*$"))
        and UnitIsUnit then
        local ok, same = pcall(UnitIsUnit, "player", who)
        if ok and same then hit = true end
    end
    if hit then
        player:updateShieldCharges()
    end
end

-- Push DoT refresh / Molten Blast duration into shown icons without rebuilding the grid.
function IchaUIUF_SyncShownAuraTimers()
    local now = GetTime and GetTime() or 0
    local function syncFr(fr)
        if not fr then return end
        local function syncList(list, kind)
            if not list then return end
            local i
            for i = 1, MAX_AURA_SLOTS do
                local icon = list[i]
                if icon and icon:IsShown() and icon.auraUnit and icon.auraIndex then
                    local left = nil
                    if kind == "debuff" then
                        left = peekDebuffTimeLeft(icon.auraUnit, icon.auraIndex, nil, icon._auraTex, nil)
                    else
                        left = peekBuffTimeLeft(icon.auraUnit, icon.auraIndex, nil, icon._auraTex, nil)
                    end
                    left = tonumber(left)
                    if kind == "debuff" then
                        -- Restart only when cache apply-start is new (recast of this DoT).
                        local ck = auraCacheKey(icon.auraUnit, nil, icon._auraTex, nil)
                        local e = ck and auraTimeCache[ck]
                        local applyStart = e and (e.applied or e.start)
                        if applyStart and icon._auraApplied ~= applyStart then
                            icon._auraApplied = applyStart
                            if left and left > 0 then
                                icon.expires = now + left
                                if icon.timer then
                                    icon.timer:SetText(formatAuraTime(left))
                                    icon.timer:SetTextColor(1, 0.92, 0.65)
                                    icon.timer:Show()
                                end
                            end
                        end
                    elseif left and left > 0 then
                        local oldLeft = 0
                        if icon.expires then
                            oldLeft = icon.expires - now
                        end
                        if (not icon.expires) or (icon.expires <= now) or (left > oldLeft + 0.75) then
                            icon.expires = now + left
                            if icon.timer then
                                icon.timer:SetText(formatAuraTime(left))
                                icon.timer:SetTextColor(1, 0.92, 0.65)
                                icon.timer:Show()
                            end
                        end
                    end
                end
            end
        end
        syncList(fr.debuffs, "debuff")
        syncList(fr.buffs, "buff")
    end
    syncFr(player)
    syncFr(target)
    syncFr(tot)
    local pi
    for pi = 1, 4 do
        syncFr(partyFrames[pi])
    end
    for pi = 1, 40 do
        syncFr(raidFrames[pi])
    end
    if IchaUI_CombatSlots then
        for pi = 1, 40 do
            syncFr(IchaUI_CombatSlots[pi])
        end
    end
end

function IchaUIUF_ApplyAll()
    player:applySize()
    target:applySize()
    tot:applySize()
    IchaUIUF_layoutParty()
    if layoutRaid then layoutRaid() end
    if IchaUIUF_LayoutTargetCluster then IchaUIUF_LayoutTargetCluster() end
    if IchaUI_CombatLayout then IchaUI_CombatLayout() end
    IchaUIUF_refreshAll()
end

function IchaUIUF_Get(key)
    if key == "combat" and IchaUI_CombatFrame then return IchaUI_CombatFrame end
    return frames[key]
end

function IchaUIUF_GetTestMode()
    return testMode and true or false
end

function IchaUIUF_GetTestParty()
    return testShowParty and true or false
end

function IchaUIUF_GetTestRaid()
    return testShowRaid and true or false
end

function IchaUIUF_SetTestParty(on)
    testShowParty = on and true or false
    if testMode then
        IchaUIUF_layoutParty()
        if layoutRaid then layoutRaid() end
    end
end

function IchaUIUF_SetTestRaid(on)
    testShowRaid = on and true or false
    if testMode then
        IchaUIUF_layoutParty()
        if layoutRaid then layoutRaid() end
    end
end

function IchaUIUF_ClearTestAuras(fr)
    if not fr then return end
    fr._testCastStart = nil
    fr._debuffFp = nil
    fr._debuffLay = nil
    fr._debuffShown = 0
    fr._debuffEmptyN = 2
    local function wipe(list)
        if not list then return end
        local i
        for i = 1, MAX_AURA_SLOTS do
            local icon = list[i]
            if icon then
                icon:Hide()
                icon._layKey = nil
                icon._auraTex = nil
                icon._auraKind = nil
                icon._auraCount = nil
                icon._auraCol = nil
                icon._auraApplied = nil
                icon.auraUnit = nil
                icon.auraIndex = nil
                icon.auraKind = nil
                icon.expires = nil
                if icon.timer then
                    icon.timer:SetText("")
                    icon.timer:Hide()
                end
                if icon.count then
                    icon.count:SetText("")
                    icon.count:Hide()
                end
                if icon.ring then
                    icon.ring:SetAlpha(0)
                    icon.ring:Hide()
                end
            end
        end
    end
    wipe(fr.buffs)
    wipe(fr.debuffs)
end

function IchaUIUF_SetTestMode(on)
    testMode = on and true or false
    if not testMode then
        local _, fr
        for _, fr in pairs(frames) do
            IchaUIUF_ClearTestAuras(fr)
        end
    end
    IchaUIUF_refreshAll()
end

function IchaUIUF_ApplyPartySaved()
    local i
    for i = 1, 4 do
        local fr = partyFrames[i]
        if fr and fr.applySaved then
            fr:applySaved()
        end
    end
end

function IchaUIUF_PartyGet()
    local p = partyDb()
    local fr = partyFrames[1]
    local slot = nil
    if IchaUIDB and IchaUIDB.uf and type(IchaUIDB.uf.party1) == "table" then
        slot = IchaUIDB.uf.party1
    end
    local portOn = false
    local psc, pring, pox, poy, bsc = 1, PORTRAIT_DEFAULT_RING, 0, 0, 1
    local box, boy, bang, bhost = 0, 0, 0, nil
    if fr then
        portOn = fr.portraitEnabled and true or false
        psc = fr.portraitScale or 1
        pring = fr.portraitRing or PORTRAIT_DEFAULT_RING
        pox = fr.portraitOffsetX or 0
        poy = fr.portraitOffsetY or 0
        bsc = fr.badgeScale or 1
        box = fr.badgeOffsetX or 0
        boy = fr.badgeOffsetY or 0
        bang = fr.badgeAngle or 0
        bhost = fr.badgeHost
    end
    -- Saved record wins over a frame that was built before SavedVariables loaded.
    if slot then
        if slot.portrait ~= nil then portOn = slot.portrait and true or false end
        if slot.portraitScale ~= nil then psc = slot.portraitScale end
        if slot.portraitRing ~= nil then pring = slot.portraitRing end
        if slot.portraitOffsetX ~= nil then pox = slot.portraitOffsetX end
        if slot.portraitOffsetY ~= nil then poy = slot.portraitOffsetY end
        if slot.badgeScale ~= nil then bsc = slot.badgeScale end
        if slot.badgeOffsetX ~= nil then box = slot.badgeOffsetX end
        if slot.badgeOffsetY ~= nil then boy = slot.badgeOffsetY end
        if slot.badgeAngle ~= nil then bang = slot.badgeAngle end
        if slot.badgeHost == "frame" or slot.badgeHost == "portrait" then bhost = slot.badgeHost end
    end
    if p.portrait ~= nil then portOn = p.portrait and true or false end
    if p.portraitScale ~= nil then psc = p.portraitScale end
    if p.portraitRing ~= nil then pring = p.portraitRing end
    if p.portraitOffsetX ~= nil then pox = p.portraitOffsetX end
    if p.portraitOffsetY ~= nil then poy = p.portraitOffsetY end
    if p.badgeScale ~= nil then bsc = p.badgeScale end
    if p.badgeOffsetX ~= nil then box = p.badgeOffsetX end
    if p.badgeOffsetY ~= nil then boy = p.badgeOffsetY end
    if p.badgeAngle ~= nil then bang = p.badgeAngle end
    if p.badgeHost == "frame" or p.badgeHost == "portrait" then bhost = p.badgeHost end
    local grow = p.growth or "center"
    return {
        scale = p.scale,
        width = p.width,
        height = p.height,
        pad = p.pad,
        gap = p.pad,
        hidden = p.hidden and true or false,
        moving = partyMoving and true or false,
        x = p.x,
        y = p.y,
        point = p.point,
        portraitEnabled = portOn,
        portraitScale = psc,
        portraitRing = pring,
        portraitOffsetX = pox,
        portraitOffsetY = poy,
        badgeScale = bsc,
        badgeOffsetX = box,
        badgeOffsetY = boy,
        badgeAngle = bang,
        badgeHost = bhost,
        growth = grow,
    }
end

function IchaUIUF_PartySet(field, value)
    local p = partyDb()
    if field == "scale" then
        local oldSc = tonumber(p.scale) or 1
        p.scale = clamp(tonumber(value) or p.scale, 0.4, 3)
        if not IchaUI_BarSkipRefit and IchaUIUF_ScaleSavedBars then
            IchaUIUF_ScaleSavedBars("party", oldSc, p.scale)
        end
    elseif field == "width" then
        p.width = clamp(tonumber(value) or p.width, 1, 600)
    elseif field == "height" then
        p.height = clamp(tonumber(value) or p.height, 1, 420)
        if not IchaUI_BarSkipRefit and IchaUIUF_RefitBarsToHeight then
            IchaUIUF_RefitBarsToHeight("party", p.height, p.scale)
        end
    elseif field == "pad" or field == "gap" then
        p.pad = clamp(tonumber(value) or p.pad, 0, 40)
    elseif field == "hidden" then
        p.hidden = value and true or false
    elseif field == "portrait" or field == "portraitScale" or field == "portraitRing"
        or field == "portraitOffsetX" or field == "portraitOffsetY" or field == "badgeScale"
        or field == "badgeOffsetX" or field == "badgeOffsetY" or field == "badgeAngle"
        or field == "badgeHost" then
        local i
        for i = 1, 4 do
            local fr = partyFrames[i]
            if fr and fr.hasPortrait then
                if field == "portrait" then
                    fr.portraitEnabled = value and true or false
                    p.portrait = fr.portraitEnabled and true or false
                elseif field == "portraitScale" then
                    fr.portraitScale = clamp(tonumber(value) or fr.portraitScale, 0.8, 2.5)
                    p.portraitScale = fr.portraitScale
                elseif field == "portraitRing" then
                    fr.portraitRing = clamp(tonumber(value) or fr.portraitRing, 0.90, 1.40)
                    p.portraitRing = fr.portraitRing
                elseif field == "portraitOffsetX" then
                    fr.portraitOffsetX = clamp(tonumber(value) or 0, -40, 40)
                    p.portraitOffsetX = fr.portraitOffsetX
                elseif field == "portraitOffsetY" then
                    fr.portraitOffsetY = clamp(tonumber(value) or 0, -40, 40)
                    p.portraitOffsetY = fr.portraitOffsetY
                elseif field == "badgeScale" then
                    fr.badgeScale = clamp(tonumber(value) or 1, 0.5, 2.0)
                    p.badgeScale = fr.badgeScale
                elseif field == "badgeOffsetX" then
                    fr.badgeOffsetX = clamp(tonumber(value) or 0, -40, 40)
                    p.badgeOffsetX = fr.badgeOffsetX
                elseif field == "badgeOffsetY" then
                    fr.badgeOffsetY = clamp(tonumber(value) or 0, -40, 40)
                    p.badgeOffsetY = fr.badgeOffsetY
                elseif field == "badgeAngle" then
                    fr.badgeAngle = clamp(tonumber(value) or 0, 0, 360)
                    p.badgeAngle = fr.badgeAngle
                elseif field == "badgeHost" then
                    if value == "frame" then fr.badgeHost = "frame" else fr.badgeHost = "portrait" end
                    p.badgeHost = fr.badgeHost
                end
                saveFrame("party" .. i, fr)
            end
        end
    elseif field == "growth" then
        local g = value
        if g ~= "left" and g ~= "right" and g ~= "up" and g ~= "down" and g ~= "grid" then
            g = "center"
        end
        p.growth = g
    elseif field == "move" or field == "moving" then
        partyMoving = value and true or false
        if partyMover then
            if partyMoving then
                partyMover:Show()
                partyRoot:EnableMouse(true)
                partyRoot:RegisterForDrag("LeftButton")
                partyRoot:Show()
                if partyRoot:GetWidth() < 40 then
                    local fw = math.max(1, math.floor((p.width or BASE_W) * (p.scale or 1) + 0.5))
                    local fh = math.max(1, math.floor((p.height or BASE_H) * (p.scale or 1) + 0.5))
                    IchaUIUF_SizeRootCentered(partyRoot, p, fw, fh, true)
                end
            else
                partyMover:Hide()
                partyRoot:EnableMouse(false)
                IchaUIUF_SaveRootCenter(partyRoot, p)
            end
        end
        savePartyDb()
        IchaUIUF_layoutParty()
        return
    else
        return
    end
    savePartyDb()
    IchaUIUF_layoutParty()
end

function IchaUIUF_PartyGetPos()
    if not partyRoot then return 0, 0, "CENTER", "BOTTOMLEFT" end
    local sx, sy = IchaUIUF_RootScreenCenter(partyRoot)
    if sx then return sx, sy, "CENTER", "BOTTOMLEFT" end
    local p = partyDb()
    return tonumber(p.x) or 0, tonumber(p.y) or 0, "CENTER", "BOTTOMLEFT"
end

function IchaUIUF_PartySetPos(x, y)
    if not partyRoot then return end
    local p = partyDb()
    p.x = tonumber(x) or 0
    p.y = tonumber(y) or 0
    p.point = "CENTER"
    p.relPoint = "BOTTOMLEFT"
    IchaUIUF_PinRootCenter(partyRoot, p.x, p.y)
    savePartyDb()
end

function IchaUIUF_PartyNudge(dx, dy)
    local x, y = IchaUIUF_PartyGetPos()
    IchaUIUF_PartySetPos(x + (tonumber(dx) or 0), y + (tonumber(dy) or 0))
end

function IchaUIUF_GetPos(key)
    if key == "combat" and IchaUI_CombatGetPos then
        return IchaUI_CombatGetPos()
    end
    local fr = frames[key]
    if not fr or not fr.root then return 0, 0 end
    local p, _, rp, x, y = fr.root:GetPoint(1)
    return tonumber(x) or 0, tonumber(y) or 0, p, rp
end

function IchaUIUF_SetPos(key, x, y)
    if key == "combat" and IchaUI_CombatSetPos then
        IchaUI_CombatSetPos(x, y)
        return
    end
    local fr = frames[key]
    if not fr or not fr.root then return end
    local p, rel, rp = fr.root:GetPoint(1)
    p = p or "CENTER"
    rp = rp or p
    rel = rel or UIParent
    fr.root:ClearAllPoints()
    fr.root:SetPoint(p, rel, rp, tonumber(x) or 0, tonumber(y) or 0)
    saveFrame(key, fr)
end

function IchaUIUF_Nudge(key, dx, dy)
    local x, y = IchaUIUF_GetPos(key)
    IchaUIUF_SetPos(key, x + (tonumber(dx) or 0), y + (tonumber(dy) or 0))
end

function IchaUIUF_refreshTextKind(kind)
    if kind == "player" then
        if player then player:applySize(); player:update() end
    elseif kind == "target" then
        if target then target:applySize(); target:update() end
    elseif kind == "tot" then
        if tot then tot:applySize(); tot:update() end
    elseif kind == "focus" then
        local fr = frames and frames.focus
        if fr then
            if fr.applySize then fr:applySize() end
            if fr.updateAuras then fr:updateAuras() end
            if fr.updateCast then fr:updateCast() end
            if fr.update then fr:update() end
        end
    elseif kind == "party" then
        IchaUIUF_layoutParty()
    elseif kind == "combat" then
        if IchaUI_CombatLayout then IchaUI_CombatLayout() end
    elseif kind == "raid" then
        if layoutRaid then layoutRaid() end
        local ri
        for ri = 1, 40 do
            local fr = raidFrames[ri]
            if fr and fr.root and fr.root:IsShown() then
                if fr.applySize then fr:applySize() end
                if fr.updateAuras then fr:updateAuras() end
                if fr.update then fr:update() end
            end
        end
    else
        IchaUIUF_ApplyAll()
    end
end

function IchaUIUF_GetTextSettings(kind)
    if not kind or kind == "" then kind = "player" end
    return loadTextSettings(kind)
end

function IchaUIUF_SetTextSetting(kind, key, value)
    if not kind or kind == "" then kind = "player" end
    local t
    local focusSparse = false
    if kind == "focus" then
        local by = ensureTextByType()
        if type(by.focus) ~= "table" then by.focus = {} end
        t = by.focus
        focusSparse = true
    else
        t = loadTextSettings(kind)
    end
    if key == "nameX" or key == "nameY" or key == "hpX" or key == "hpY" then
        t[key] = clamp(tonumber(value) or 0, -200, 200)
    elseif key == "nameScale" or key == "hpScale" or key == "powerScale" then
        t[key] = clamp(tonumber(value) or 1, 0.4, 3.0)
    elseif key == "nameAlign" or key == "hpAlign" or key == "powerAlign" then
        t[key] = validAlign(value)
    elseif key == "showHpPct" or key == "showPowerText" then
        t[key] = value and true or false
    elseif key == "buffPad" or key == "debuffPad" then
        t[key] = clamp(tonumber(value) or 2, 0, 12)
    elseif key == "buffScale" or key == "debuffScale" then
        t[key] = clamp(tonumber(value) or 1, 0.4, 3)
    elseif key == "buffOffsetX" or key == "buffOffsetY"
        or key == "debuffOffsetX" or key == "debuffOffsetY" then
        t[key] = clamp(tonumber(value) or 0, -80, 80)
    elseif key == "buffAnchor" or key == "debuffAnchor" then
        t[key] = IchaUI_ValidAuraAnchor(value)
    elseif key == "buffsShown" or key == "debuffsShown" then
        local n = math.floor(tonumber(value) or 0)
        if n < 0 then n = 0 end
        if n > 20 then n = 20 end
        t[key] = n
    elseif key == "buffPerRow" or key == "debuffPerRow" then
        local n = math.floor(tonumber(value) or 1)
        if n < 1 then n = 1 end
        if n > 20 then n = 20 end
        t[key] = n
    else
        return
    end
    if focusSparse then
        local by = ensureTextByType()
        by.focus = t
        local d = db()
        d.textByType = by
        IchaUIDB.uf = d
    else
        saveTextSettings(kind, t)
    end
    IchaUIUF_refreshTextKind(kind)
end

function IchaUIUF_AuraLayoutGet(kind, field)
    local t = IchaUIUF_GetTextSettings(kind)
    if not t then t = {} end
    local per = 8
    local shown = 16
    if kind ~= "raid" and IchaUIUF_Get then
        local fr = IchaUIUF_Get(kind)
        if not fr and kind == "party" then fr = IchaUIUF_Get("party1") end
        if not fr and kind == "combat" then fr = IchaUIUF_Get("combat1") end
        if fr and fr._perRow then per = fr._perRow end
        if fr and fr._maxAuras then shown = fr._maxAuras end
    end
    if field == "buffAnchor" then return t.buffAnchor or "TOPLEFT" end
    if field == "debuffAnchor" then return t.debuffAnchor or "BOTTOMLEFT" end
    if field == "buffX" then return tonumber(t.buffOffsetX) or 0 end
    if field == "buffY" then return tonumber(t.buffOffsetY) or 0 end
    if field == "debuffX" then return tonumber(t.debuffOffsetX) or 0 end
    if field == "debuffY" then return tonumber(t.debuffOffsetY) or 0 end
    if field == "buffsShown" then
        if t.buffsShown ~= nil then return tonumber(t.buffsShown) or 0 end
        return shown
    end
    if field == "debuffsShown" then
        if t.debuffsShown ~= nil then return tonumber(t.debuffsShown) or 0 end
        return shown
    end
    if field == "buffPerRow" then
        if t.buffPerRow ~= nil then return tonumber(t.buffPerRow) or 1 end
        return per
    end
    if field == "debuffPerRow" then
        if t.debuffPerRow ~= nil then return tonumber(t.debuffPerRow) or 1 end
        return per
    end
    return 0
end

function IchaUIUF_NudgeText(kind, which, dx, dy)
    if not kind or kind == "" then kind = "player" end
    local t = loadTextSettings(kind)
    dx = tonumber(dx) or 0
    dy = tonumber(dy) or 0
    if which == "name" then
        t.nameX = clamp(t.nameX + dx, -200, 200)
        t.nameY = clamp(t.nameY + dy, -200, 200)
    elseif which == "hp" then
        t.hpX = clamp(t.hpX + dx, -200, 200)
        t.hpY = clamp(t.hpY + dy, -200, 200)
    else
        return
    end
    saveTextSettings(kind, t)
    IchaUIUF_refreshTextKind(kind)
end

function IchaUIUF_NudgeTextScale(kind, which, delta)
    if not kind or kind == "" then kind = "player" end
    local t = loadTextSettings(kind)
    delta = tonumber(delta) or 0
    local key
    if which == "name" then
        key = "nameScale"
    elseif which == "hp" then
        key = "hpScale"
    elseif which == "power" then
        key = "powerScale"
    else
        return
    end
    t[key] = clamp((tonumber(t[key]) or 1) + delta, 0.4, 3.0)
    saveTextSettings(kind, t)
    IchaUIUF_refreshTextKind(kind)
end

function IchaUIUF_GetPredictHeals()
    local d = db()
    return d.predictHeals ~= false
end

function IchaUIUF_SetPredictHeals(on)
    local d = db()
    d.predictHeals = on and true or false
    IchaUIDB.uf = d
    player:update()
    target:update()
    tot:update()
end

function IchaUIUF_GetAuraIconScale()
    local d = db()
    local v = tonumber(d.auraIconScale) or 1.0
    if v < 0.5 then v = 0.5 end
    if v > 2.0 then v = 2.0 end
    return v
end

function IchaUIUF_SetAuraIconScale(v)
    local d = db()
    v = tonumber(v) or 1.0
    if v < 0.5 then v = 0.5 end
    if v > 2.0 then v = 2.0 end
    d.auraIconScale = v
    IchaUIDB.uf = d
    if IchaUIUF_ApplyAll then
        IchaUIUF_ApplyAll()
    else
        if player then player:applySize(); player:update() end
        if target then target:applySize(); target:update() end
        if tot then tot:applySize(); tot:update() end
        IchaUIUF_layoutParty()
        if layoutRaid then layoutRaid() end
    end
end

function IchaUIUF_GetManaTicker()
    return db().manaTicker ~= false
end

function IchaUIUF_SetManaTicker(on)
    db().manaTicker = on and true or false
    if player and player.mpTick and not on then
        player.mpTick:Hide()
    end
end

function IchaUIUF_SetCastSetting(kind, field, value)
    if not kind or kind == "" then return end
    local s = IchaUIUF_GetCastSettings(kind)
    if field == "castPos" then
        s.castPos = IchaUI_ValidCastPos(value)
    elseif field == "castOffsetX" then
        s.castOffsetX = clamp(tonumber(value) or 0, -80, 80)
    elseif field == "castOffsetY" then
        s.castOffsetY = clamp(tonumber(value) or 0, -80, 80)
    elseif field == "castLen" then
        s.castLen = clamp(tonumber(value) or IchaUI_CAST_NAT or 214, IchaUI_CAST_LEN_MIN or 80, IchaUI_CAST_LEN_MAX or 420)
    elseif field == "castScale" then
        s.castScale = clamp(tonumber(value) or 1, IchaUI_CAST_SC_MIN or 0.4, IchaUI_CAST_SC_MAX or 3)
    elseif field == "castEnabled" then
        if value == false then s.castEnabled = false else s.castEnabled = true end
    elseif field == "castWidth" then
        -- Legacy percent (40-180). Store the pixel length and stop scaling both axes.
        local v = tonumber(value) or 100
        if v >= 40 and v <= 180 then
            v = math.floor((IchaUI_CAST_NAT or 214) * v / 100 + 0.5)
        end
        s.castLen = clamp(v, IchaUI_CAST_LEN_MIN or 80, IchaUI_CAST_LEN_MAX or 420)
    elseif field == "castHeight" then
        -- Height stays the texture's natural size.
        return
    elseif field == "castDetached" then
        if kind == "player" or kind == "target" or kind == "focus" then
            s.castDetached = value and true or false
            if not s.castDetached then
                local fr = frames and frames[kind]
                if fr and fr._castMoving and fr.setCastMove then
                    fr:setCastMove(false)
                end
            end
        end
    elseif field == "castPoint" then
        s.castPoint = value
    elseif field == "castRelPoint" then
        s.castRelPoint = value
    elseif field == "castX" then
        s.castX = tonumber(value)
    elseif field == "castY" then
        s.castY = tonumber(value)
    elseif field == "castMove" then
        -- toggle free-move overlay on detached cast bar
        local fr = frames and frames[kind]
        if fr and fr.setCastMove then fr:setCastMove(value and true or false) end
        return
    else
        return
    end
    IchaUIDB.uf.castByType[kind] = s
    IchaUIDB.uf = IchaUIDB.uf
    if kind == "player" or kind == "target" or kind == "tot" or kind == "focus" then
        local fr = frames and frames[kind]
        if fr then
            if fr.applySize then fr:applySize() end
            if fr.updateCast then fr:updateCast() end
        end
    elseif kind == "party" then
        local i
        for i = 1, 4 do
            local fr = partyFrames and partyFrames[i]
            if fr then
                if fr.applySize then fr:applySize() end
                if fr.updateCast then fr:updateCast() end
            end
        end
    elseif kind == "raid" then
        local i
        if raidFrames then
            for i = 1, table.getn(raidFrames) do
                local fr = raidFrames[i]
                if fr then
                    if fr.applySize then fr:applySize() end
                    if fr.updateCast then fr:updateCast() end
                end
            end
        end
    elseif kind == "combat" then
        if IchaUI_CombatLayout then IchaUI_CombatLayout() end
    end
end


function IchaUIUF_Set(key, field, value)
    if key == "combat" and IchaUI_CombatSet then
        IchaUI_CombatSet(field, value)
        return
    end
    local fr = frames[key]
    if not fr then return end
    if field == "scale" then
        local oldSc = tonumber(fr.scale) or 1
        fr.scale = clamp(value, 0.4, 3)
        if not IchaUI_BarSkipRefit and IchaUIUF_ScaleSavedBars then
            IchaUIUF_ScaleSavedBars(key, oldSc, fr.scale)
        end
    elseif field == "width" then
        fr.width = clamp(value, 1, 600)
    elseif field == "height" then
        fr.height = clamp(value, 1, 420)
        if not IchaUI_BarSkipRefit and IchaUIUF_RefitBarsToHeight then
            IchaUIUF_RefitBarsToHeight(key, fr.height, fr.scale)
        end
    elseif field == "hidden" then
        fr.hidden = value and true or false
        if fr.hidden then fr.root:Hide() else fr.root:Show() end
    elseif field == "portrait" then
        if not fr.hasPortrait then return end
        fr.portraitEnabled = value and true or false
    elseif field == "portraitScale" then
        if not fr.hasPortrait then return end
        fr.portraitScale = clamp(value, 0.8, 2.5)
    elseif field == "portraitRing" then
        if not fr.hasPortrait then return end
        fr.portraitRing = clamp(value, 0.90, 1.40)
    elseif field == "portraitOffsetX" then
        if not fr.hasPortrait then return end
        fr.portraitOffsetX = clamp(value, -40, 40)
    elseif field == "portraitOffsetY" then
        if not fr.hasPortrait then return end
        fr.portraitOffsetY = clamp(value, -40, 40)
    elseif field == "badgeAngle" then
        if not fr.hasPortrait then return end
        fr.badgeAngle = clamp(value, 0, 360)
    elseif field == "badgeScale" then
        if not fr.hasPortrait then return end
        fr.badgeScale = clamp(value, 0.5, 2.0)
    elseif field == "badgeOffsetX" then
        if not fr.hasPortrait then return end
        fr.badgeOffsetX = clamp(value, -40, 40)
    elseif field == "badgeOffsetY" then
        if not fr.hasPortrait then return end
        fr.badgeOffsetY = clamp(value, -40, 40)
    elseif field == "badgeHost" then
        if not fr.hasPortrait then return end
        if value == "frame" then fr.badgeHost = "frame" else fr.badgeHost = "portrait" end
    elseif field == "shieldChargeEnabled" then
        if not fr.hasPortrait then return end
        fr.shieldChargeEnabled = value and true or false
    elseif field == "shieldChargeSpread" then
        if not fr.hasPortrait then return end
        fr.shieldChargeSpread = clamp(value, 10, 360)
    elseif field == "shieldChargeSize" then
        if not fr.hasPortrait then return end
        fr.shieldChargeSize = clamp(value, 6, 28)
    elseif field == "shieldChargeAngle" then
        if not fr.hasPortrait then return end
        fr.shieldChargeAngle = clamp(value, -360, 360)
    elseif field == "shieldChargeReverse" then
        if not fr.hasPortrait then return end
        fr.shieldChargeReverse = value and true or false
    elseif field == "shieldChargeOffsetX" then
        if not fr.hasPortrait then return end
        fr.shieldChargeOffsetX = clamp(value, -40, 40)
    elseif field == "shieldChargeOffsetY" then
        if not fr.hasPortrait then return end
        fr.shieldChargeOffsetY = clamp(value, -40, 40)
    elseif field == "move" then
        fr:setMove(value)
        return
    end
    saveFrame(key, fr)
    fr:applySize()
    fr:update()
    if (key == "target" or key == "tot") and (field == "portrait" or field == "portraitScale"
        or field == "portraitRing" or field == "portraitOffsetX"
        or field == "portraitOffsetY" or field == "badgeAngle"
        or field == "badgeScale" or field == "badgeOffsetX"
        or field == "badgeOffsetY" or field == "width" or field == "height"
        or field == "scale") then
        if IchaUIUF_layoutTargetCluster then IchaUIUF_layoutTargetCluster() end
    end
end


-- ===== Per-kind aura filters (globals; IchaUIDB.uf.auraFiltersByType[kind]) =====
-- Booleans: showAllBuffs/Debuffs, showMyBuffs/Debuffs, whitelistBuffsOnly/DebuffsOnly
-- Whitelist exclusive when *Only; else (all) or (my and isMine). Raid legacy typed
-- when debuff filters would otherwise hide everything.

function IchaUIUF_DefaultAuraFilters(kind)
    local t = {
        showAllBuffs = true,
        showAllDebuffs = true,
        showMyBuffs = false,
        showMyDebuffs = false,
        whitelistBuffsOnly = false,
        whitelistDebuffsOnly = false,
        whitelistBuffs = {},
        whitelistDebuffs = {},
    }
    if kind == "player" then
        t.showAllBuffs = false
    elseif kind == "raid" then
        t.showAllBuffs = false
        t.showMyBuffs = true
        t.showAllDebuffs = false
    end
    return t
end

function IchaUIUF_GetAuraFilters(kind)
    if not kind or kind == "" then kind = "player" end
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.uf then IchaUIDB.uf = {} end
    local d = IchaUIDB.uf
    if not d.auraFiltersByType then d.auraFiltersByType = {} end
    local by = d.auraFiltersByType
    if type(by[kind]) ~= "table" then
        if kind == "focus" and type(by.target) == "table" then
            local src = by.target
            local copied = IchaUIUF_DefaultAuraFilters("target")
            if src.showAllBuffs ~= nil then copied.showAllBuffs = src.showAllBuffs and true or false end
            if src.showAllDebuffs ~= nil then copied.showAllDebuffs = src.showAllDebuffs and true or false end
            if src.showMyBuffs ~= nil then copied.showMyBuffs = src.showMyBuffs and true or false end
            if src.showMyDebuffs ~= nil then copied.showMyDebuffs = src.showMyDebuffs and true or false end
            if src.whitelistBuffsOnly ~= nil then copied.whitelistBuffsOnly = src.whitelistBuffsOnly and true or false end
            if src.whitelistDebuffsOnly ~= nil then copied.whitelistDebuffsOnly = src.whitelistDebuffsOnly and true or false end
            if type(src.whitelistBuffs) == "table" and IchaUI_CopyAuraList then
                copied.whitelistBuffs = IchaUI_CopyAuraList(src.whitelistBuffs)
            end
            if type(src.whitelistDebuffs) == "table" and IchaUI_CopyAuraList then
                copied.whitelistDebuffs = IchaUI_CopyAuraList(src.whitelistDebuffs)
            end
            by[kind] = copied
            return by[kind]
        end
        -- Migrate from legacy textByType buffShow/debuffShow if present
        local legacy = nil
        if d.textByType and type(d.textByType[kind]) == "table" then
            legacy = d.textByType[kind]
        end
        local t = IchaUIUF_DefaultAuraFilters(kind)
        if legacy then
            local bs = legacy.buffShow
            if bs == "none" then
                t.showAllBuffs = false; t.showMyBuffs = false; t.whitelistBuffsOnly = false
            elseif bs == "mine" then
                t.showAllBuffs = false; t.showMyBuffs = true; t.whitelistBuffsOnly = false
            elseif bs == "whitelist" then
                t.showAllBuffs = false; t.showMyBuffs = false; t.whitelistBuffsOnly = true
            elseif bs == "all" then
                t.showAllBuffs = true; t.showMyBuffs = false; t.whitelistBuffsOnly = false
            end
            local ds = legacy.debuffShow
            if ds == "none" then
                t.showAllDebuffs = false; t.showMyDebuffs = false; t.whitelistDebuffsOnly = false
            elseif ds == "mine" then
                t.showAllDebuffs = false; t.showMyDebuffs = true; t.whitelistDebuffsOnly = false
            elseif ds == "whitelist" then
                t.showAllDebuffs = false; t.showMyDebuffs = false; t.whitelistDebuffsOnly = true
            elseif ds == "all" then
                t.showAllDebuffs = true; t.showMyDebuffs = false; t.whitelistDebuffsOnly = false
            end
            if type(legacy.buffWhitelist) == "table" then
                t.whitelistBuffs = IchaUI_CopyAuraList(legacy.buffWhitelist)
            end
            if type(legacy.debuffWhitelist) == "table" then
                t.whitelistDebuffs = IchaUI_CopyAuraList(legacy.debuffWhitelist)
            end
        end
        by[kind] = t
    else
        local f = by[kind]
        local def = IchaUIUF_DefaultAuraFilters(kind)
        if f.showAllBuffs == nil then f.showAllBuffs = def.showAllBuffs end
        if f.showAllDebuffs == nil then f.showAllDebuffs = def.showAllDebuffs end
        if f.showMyBuffs == nil then f.showMyBuffs = def.showMyBuffs end
        if f.showMyDebuffs == nil then f.showMyDebuffs = def.showMyDebuffs end
        if f.whitelistBuffsOnly == nil then f.whitelistBuffsOnly = false end
        if f.whitelistDebuffsOnly == nil then f.whitelistDebuffsOnly = false end
        if type(f.whitelistBuffs) ~= "table" then f.whitelistBuffs = {} end
        if type(f.whitelistDebuffs) ~= "table" then f.whitelistDebuffs = {} end
    end
    return by[kind]
end

function IchaUIUF_IsTypedDispelDebuff(dtype)
    if not dtype then return false end
    local dt = dtype
    if type(dt) ~= "string" then dt = tostring(dt) end
    dt = string.lower(dt)
    return dt == "magic" or dt == "poison" or dt == "disease" or dt == "curse"
end

function IchaUIUF_ShouldShowBuff(kind, name, spellId, isMine)
    local f = IchaUIUF_GetAuraFilters(kind)
    if f.whitelistBuffsOnly then
        local lookup = IchaUI_BuildAuraWhitelistLookup(f.whitelistBuffs)
        return IchaUI_AuraWhitelistMatch(lookup, name, spellId)
    end
    if f.showAllBuffs then return true end
    if f.showMyBuffs and isMine then return true end
    return false
end

function IchaUIUF_ShouldShowDebuff(kind, name, spellId, isMine, dtype)
    local f = IchaUIUF_GetAuraFilters(kind)
    if f.whitelistDebuffsOnly then
        local lookup = IchaUI_BuildAuraWhitelistLookup(f.whitelistDebuffs)
        return IchaUI_AuraWhitelistMatch(lookup, name, spellId)
    end
    if f.showAllDebuffs then return true end
    if f.showMyDebuffs and isMine then return true end
    -- Raid legacy: typed/dispellable when all/my/whitelist off
    if kind == "raid" and IchaUIUF_IsTypedDispelDebuff(dtype) then
        return true
    end
    return false
end

function IchaUIUF_FiltersAllowAnyBuffs(kind)
    local f = IchaUIUF_GetAuraFilters(kind)
    if f.whitelistBuffsOnly then
        return table.getn(f.whitelistBuffs or {}) > 0
    end
    return f.showAllBuffs or f.showMyBuffs
end

function IchaUIUF_FiltersAllowAnyDebuffs(kind)
    local f = IchaUIUF_GetAuraFilters(kind)
    if f.whitelistDebuffsOnly then
        return table.getn(f.whitelistDebuffs or {}) > 0
    end
    if f.showAllDebuffs or f.showMyDebuffs then return true end
    if kind == "raid" then return true end
    return false
end

-- "My buffs": 1.12 UnitBuff has no caster, so mine = buff named like a spell in
-- the player's own spellbook. Map keys: "n:<lower name>" and spell textures.
IchaUIUF_MySpellbook = { dirty = true, map = {} }

function IchaUIUF_RebuildSpellbook()
    local sb = IchaUIUF_MySpellbook
    local map = {}
    local n = 0
    local book = BOOKTYPE_SPELL or "spell"
    local function add(i)
        local name, tex
        pcall(function() name = GetSpellName(i, book) end)
        if type(name) ~= "string" or name == "" then return false end
        map["n:" .. string.lower(name)] = true
        if type(GetSpellTexture) == "function" then
            pcall(function() tex = GetSpellTexture(i, book) end)
            tex = normalizeAuraTexture(tex)
            if tex then map[tex] = true end
        end
        n = n + 1
        return true
    end
    if type(GetSpellName) == "function" then
        local tabs = 0
        if type(GetNumSpellTabs) == "function" then
            pcall(function() tabs = tonumber(GetNumSpellTabs()) or 0 end)
        end
        if tabs > 0 and type(GetSpellTabInfo) == "function" then
            local t
            for t = 1, tabs do
                local offset, count
                pcall(function()
                    local _, _, o, c = GetSpellTabInfo(t)
                    offset, count = tonumber(o), tonumber(c)
                end)
                if offset and count then
                    local i
                    for i = offset + 1, offset + count do add(i) end
                end
            end
        else
            local i = 1
            while i <= 1024 and add(i) do i = i + 1 end
        end
    end
    sb.map = map
    -- Spellbook can be empty before login; retry on the next aura pass.
    sb.dirty = (n == 0)
    return map
end

function IchaUIUF_BuildMineBuffMap(unit)
    local sb = IchaUIUF_MySpellbook
    if sb.dirty then return IchaUIUF_RebuildSpellbook() end
    return sb.map
end

function IchaUIUF_BuildMineDebuffMap(unit)
    local keys = {}
    if not unit then return keys end
    local mi
    for mi = 1, 16 do
        local mname, micon = readDebuff(unit, mi, "mine")
        if not micon then break end
        keys[micon] = true
        if mname and mname ~= "" then
            keys["n:" .. string.lower(mname)] = true
        end
    end
    return keys
end

function IchaUIUF_BuffIsMine(name, icon, mineMap)
    if not mineMap then return false end
    if name and name ~= "" then
        return mineMap["n:" .. string.lower(name)] and true or false
    end
    -- No tooltip name: texture only (spells can share icons).
    if icon and mineMap[icon] then return true end
    return false
end

function IchaUIUF_DebuffIsMine(caster, name, icon, mineMap)
    if isMineCaster(caster) then return true end
    if mineMap then
        if icon and mineMap[icon] then return true end
        if name and name ~= "" and mineMap["n:" .. string.lower(name)] then return true end
    end
    return false
end

function IchaUIUF_SetAuraFilter(kind, key, value)
    if not kind or kind == "" then kind = "player" end
    local f = IchaUIUF_GetAuraFilters(kind)
    if key == "showAllBuffs" or key == "showAllDebuffs"
        or key == "showMyBuffs" or key == "showMyDebuffs"
        or key == "whitelistBuffsOnly" or key == "whitelistDebuffsOnly" then
        f[key] = value and true or false
    else
        return
    end
    IchaUIUF_refreshTextKind(kind)
end

function IchaUIUF_SetAuraWhitelist(kind, which, text)
    if not kind or kind == "" then kind = "player" end
    local f = IchaUIUF_GetAuraFilters(kind)
    local list = IchaUI_ParseAuraList(text)
    -- Also accept comma-separated on one line
    if type(text) == "string" and string.find(text, ",", 1, true) then
        local merged = {}
        local i
        for i = 1, table.getn(list) do
            local line = list[i]
            local start = 1
            while true do
                local ns, ne = string.find(line, ",", start, true)
                local part
                if not ns then
                    part = string.sub(line, start)
                else
                    part = string.sub(line, start, ns - 1)
                end
                part = string.gsub(part, "^%s+", "")
                part = string.gsub(part, "%s+$", "")
                if part ~= "" then table.insert(merged, part) end
                if not ns then break end
                start = ne + 1
            end
        end
        list = merged
    end
    if which == "debuff" then
        f.whitelistDebuffs = list
    else
        f.whitelistBuffs = list
    end
    IchaUIUF_refreshTextKind(kind)
end

function IchaUIUF_GetAuraWhitelistText(kind, which)
    if not kind or kind == "" then kind = "player" end
    local f = IchaUIUF_GetAuraFilters(kind)
    local list = f.whitelistBuffs
    if which == "debuff" then list = f.whitelistDebuffs end
    list = list or {}
    local n = table.getn(list)
    if n == 0 then return "" end
    local s = list[1] or ""
    local i
    for i = 2, n do
        s = s .. "\n" .. (list[i] or "")
    end
    return s
end

function IchaUIUF_SetRaidDebuffs(list)
    db().raidDebuffs = list or {}
    IchaUIUF_refreshAll()
end

function IchaUIUF_GetRaidDebuffsText()
    local list = db().raidDebuffs or {}
    local n = table.getn(list)
    if n == 0 then return "" end
    local s = list[1] or ""
    local i
    for i = 2, n do
        s = s .. "\n" .. (list[i] or "")
    end
    return s
end

function IchaUIUF_Slash(rest)
    rest = string.lower(rest or "")
    rest = string.gsub(rest, "^%s+", "")
    if string.find(rest, "^party") then
        rest = string.gsub(rest, "^party%s*", "")
        if rest == "move" then
            IchaUIUF_PartySet("move", not partyMoving)
        elseif rest == "show" then
            IchaUIUF_PartySet("hidden", false)
        elseif rest == "hide" then
            IchaUIUF_PartySet("hidden", true)
        elseif string.find(rest, "^scale") or string.find(rest, "^width") or string.find(rest, "^height")
            or string.find(rest, "^pad") or string.find(rest, "^gap") then
            local field = "scale"
            if string.find(rest, "^width") then field = "width" end
            if string.find(rest, "^height") then field = "height" end
            if string.find(rest, "^pad") or string.find(rest, "^gap") then field = "pad" end
            local n = nil
            for token in (string.gmatch or string.gfind)(rest, "%S+") do
                n = tonumber(token) or n
            end
            if n then IchaUIUF_PartySet(field, n) end
        else
            DEFAULT_CHAT_FRAME:AddMessage("UF party: move|show|hide|scale|width|height|pad")
        end
        return
    end
    if string.find(rest, "^raid") then
        rest = string.gsub(rest, "^raid%s*", "")
        if rest == "move" then
            IchaUIUF_RaidSet("move", not raidMoving)
        elseif rest == "show" then
            IchaUIUF_RaidSet("hidden", false)
        elseif rest == "hide" then
            IchaUIUF_RaidSet("hidden", true)
        elseif string.find(rest, "^scale") or string.find(rest, "^width") or string.find(rest, "^height")
            or string.find(rest, "^pad") or string.find(rest, "^gap")
            or string.find(rest, "^cols") or string.find(rest, "^col")
            or string.find(rest, "^rows") or string.find(rest, "^row") then
            local field = "scale"
            if string.find(rest, "^width") then field = "width" end
            if string.find(rest, "^height") then field = "height" end
            if string.find(rest, "^pad") or string.find(rest, "^gap") then field = "pad" end
            if string.find(rest, "^cols") or string.find(rest, "^col") then field = "cols" end
            if string.find(rest, "^rows") or string.find(rest, "^row") then field = "rows" end
            local n = nil
            for token in (string.gmatch or string.gfind)(rest, "%S+") do
                n = tonumber(token) or n
            end
            if n then IchaUIUF_RaidSet(field, n) end
        else
            DEFAULT_CHAT_FRAME:AddMessage("UF raid: move|show|hide|scale|width|height|pad|cols|rows")
        end
        return
    end
    local who = "player"
    if string.find(rest, "^focus") then
        who = "focus"
        rest = string.gsub(rest, "^focus%s*", "")
    elseif string.find(rest, "^tot") or string.find(rest, "^targettarget") then
        who = "tot"
        rest = string.gsub(rest, "^tot%s*", "")
        rest = string.gsub(rest, "^targettarget%s*", "")
    elseif string.find(rest, "^target") then
        who = "target"
        rest = string.gsub(rest, "^target%s*", "")
    elseif string.find(rest, "^player") then
        who = "player"
        rest = string.gsub(rest, "^player%s*", "")
    end
    if rest == "move" then
        local fr = frames[who]
        fr:setMove(not fr.moving)
    elseif rest == "show" then
        IchaUIUF_Set(who, "hidden", false)
    elseif rest == "hide" then
        IchaUIUF_Set(who, "hidden", true)
    elseif string.find(rest, "^scale") or string.find(rest, "^width") or string.find(rest, "^height") then
        local field = "scale"
        if string.find(rest, "^width") then field = "width" end
        if string.find(rest, "^height") then field = "height" end
        local n = nil
        for token in (string.gmatch or string.gfind)(rest, "%S+") do
            n = tonumber(token) or n
        end
        if n then IchaUIUF_Set(who, field, n) end
    elseif rest == "blizzard" then
        IchaUIUF_hideBlizzard(not db().hideBlizzard)
    elseif rest == "healdebug" or rest == "healdbg" then
        healDebug = not healDebug
        DEFAULT_CHAT_FRAME:AddMessage("IchaUI heal debug: " .. (healDebug and "ON — cast heals, watch chat for id/rank/tip" or "OFF"))
    else
        DEFAULT_CHAT_FRAME:AddMessage("UF: /icha uf [player|target|focus|tot|party] move|show|hide|scale|width|height|pad|healdebug")
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_UPDATE_RESTING")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("UNIT_TARGET")
ev:RegisterEvent("PARTY_MEMBERS_CHANGED")
ev:RegisterEvent("PARTY_MEMBER_ENABLE")
ev:RegisterEvent("PARTY_MEMBER_DISABLE")
ev:RegisterEvent("RAID_ROSTER_UPDATE")
ev:RegisterEvent("PARTY_LEADER_CHANGED")
ev:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
ev:RegisterEvent("UNIT_HEALTH")
ev:RegisterEvent("UNIT_MAXHEALTH")
ev:RegisterEvent("UNIT_MANA")
ev:RegisterEvent("UNIT_MAXMANA")
ev:RegisterEvent("UNIT_ENERGY")
ev:RegisterEvent("UNIT_RAGE")
ev:RegisterEvent("UNIT_DISPLAYPOWER")
ev:RegisterEvent("UNIT_AURA")
ev:RegisterEvent("PLAYER_AURAS_CHANGED")
pcall(function() ev:RegisterEvent("PLAYER_AURA") end)
ev:RegisterEvent("SPELLS_CHANGED")
pcall(function() ev:RegisterEvent("LEARNED_SPELL_IN_TAB") end)
ev:RegisterEvent("UNIT_LEVEL")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("UNIT_NAME_UPDATE")
ev:RegisterEvent("UNIT_PORTRAIT_UPDATE")
ev:RegisterEvent("RAID_TARGET_UPDATE")
ev:RegisterEvent("UNIT_RESISTANCE")
ev:RegisterEvent("UNIT_ATTACK_SPEED")
ev:RegisterEvent("UNIT_ATTACK_POWER")
ev:RegisterEvent("UNIT_SPELLCAST_START")
ev:RegisterEvent("UNIT_SPELLCAST_STOP")
ev:RegisterEvent("UNIT_SPELLCAST_FAILED")
ev:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
ev:RegisterEvent("UNIT_SPELLCAST_DELAYED")
ev:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
ev:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
ev:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
ev:RegisterEvent("SPELLCAST_START")
ev:RegisterEvent("SPELLCAST_STOP")
ev:RegisterEvent("SPELLCAST_FAILED")
ev:RegisterEvent("SPELLCAST_INTERRUPTED")
ev:RegisterEvent("SPELLCAST_DELAYED")
ev:RegisterEvent("SPELLCAST_CHANNEL_START")
ev:RegisterEvent("SPELLCAST_CHANNEL_STOP")
-- SuperWoW
ev:RegisterEvent("UNIT_CASTEVENT")
ev:RegisterEvent("UNIT_HEAL_PREDICTION")
-- Combat-log cast starts (fallback when SuperWoW GUID events are missing)
ev:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE")
ev:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_BUFF")
ev:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
ev:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF")
ev:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE")
ev:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF")
ev:RegisterEvent("CHAT_MSG_SPELL_PARTY_DAMAGE")
ev:RegisterEvent("CHAT_MSG_SPELL_PARTY_BUFF")
ev:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
ev:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS")
ev:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
ev:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS")
ev:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE")
ev:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS")
ev:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE")
ev:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS")
ev:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
-- Melee swing timer combat log / UNIT_COMBAT
ev:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
ev:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
ev:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
ev:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
ev:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS")
ev:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES")
pcall(function() ev:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_VS_SELF_HITS") end)
pcall(function() ev:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_VS_SELF_MISSES") end)
ev:RegisterEvent("UNIT_COMBAT")
ev:SetScript("OnEvent", function()
    if IchaUI_LEAVING and event ~= "PLAYER_LOGOUT" and event ~= "PLAYER_ENTERING_WORLD" then return end
    if event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" or event == "PLAYER_ENTERING_WORLD" then
        if IchaUIUF_MySpellbook then IchaUIUF_MySpellbook.dirty = true end
        if event ~= "PLAYER_ENTERING_WORLD" then return end
    end
    -- Combat-log cast bars (name-keyed; works without SuperWoW)
    if string.find(event, "CHAT_MSG_SPELL_", 1, true) then
        -- Periodic tick/hit: mark so UNIT_CASTEVENT CAST cannot treat this as a reapply.
        if string.find(event, "PERIODIC", 1, true) and arg1 then
            local msg = arg1
            if not string.find(msg, "afflicted by", 1, true) then
                local _, _, tickSpell = string.find(msg, "from your (.+)%.")
                if not tickSpell then
                    _, _, tickSpell = string.find(msg, "from your (.+)$")
                end
                if tickSpell and tickSpell ~= "" then
                    IchaUI_PeriodicTickName = string.lower(tickSpell)
                    IchaUI_PeriodicTickAt = GetTime and GetTime() or 0
                end
            end
        end
        if swCastFromCombatLog then swCastFromCombatLog(arg1) end
        if swCastInterruptFromCombatLog then swCastInterruptFromCombatLog(arg1) end
        if target and target.updateCast then target:updateCast() end
        if tot and tot.updateCast then tot:updateCast() end
        do
            local pi
            for pi = 1, 4 do
                local fr = partyFrames and partyFrames[pi]
                if fr and fr.updateCast then fr:updateCast() end
            end
        end
        -- Fall through only for combat-hit swing messages; spell chat ends here
        if not (event == "CHAT_MSG_SPELL_SELF_DAMAGE") then
            return
        end
        -- SELF_DAMAGE may also matter for interrupts; still return after cast update
        return
    end

    -- Swing timer: combat hits / attack speed (before early returns)
    if event == "CHAT_MSG_COMBAT_SELF_HITS" or event == "CHAT_MSG_COMBAT_SELF_MISSES"
        or event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS"
        or event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES"
        or event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS"
        or event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES"
        or event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_VS_SELF_HITS"
        or event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_VS_SELF_MISSES"
        or event == "UNIT_COMBAT" then
        IchaUI_Swing_OnCombatEvent()
        if event ~= "UNIT_COMBAT" then return end
        -- UNIT_COMBAT may also matter for other handlers; fall through only if needed
        return
    end

    if event == "PLAYER_UPDATE_RESTING"
        or event == "PLAYER_REGEN_DISABLED"
        or event == "PLAYER_REGEN_ENABLED" then
        if event == "PLAYER_REGEN_ENABLED" then
            if player then IchaUI_Swing_Clear(player) end
            if target then IchaUI_Swing_Clear(target) end
            if tot then IchaUI_Swing_Clear(tot) end
            if IchaUI_CombatSlots then
                local si
                for si = 1, 40 do
                    local sfr = IchaUI_CombatSlots[si]
                    if sfr then IchaUI_Swing_Clear(sfr) end
                end
            end
        end
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            IchaUIUF_SetRoleCombat(event == "PLAYER_REGEN_DISABLED")
        end
        if player then player:update() end
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            if IchaUIUF_RefreshRoleIcons then IchaUIUF_RefreshRoleIcons() end
        end
        return
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        if db().hideBlizzard ~= false then
            IchaUIUF_hideBlizzard(true)
        end
        IchaUIUF_hideBlizzardCastBar()
        -- Re-apply SavedVariables (file-load can race; login is authoritative)
        player:applySaved()
        target:applySaved()
        tot:applySaved()
        if frames.focus and frames.focus.applySaved then
            frames.focus:applySaved()
        end
        if IchaUIUF_ApplyPartySaved then
            IchaUIUF_ApplyPartySaved()
        end
        IchaUIUF_restorePartyRootPos()
        IchaUIUF_restoreRaidRootPos()
        IchaUIUF_layoutParty()
        if layoutRaid then layoutRaid() end
        player:update()
        target:update()
        tot:update()
        -- Group/leader/loot data can arrive after login; re-apply role fades for ~2s.
        IchaUIUF_RoleFade.combat = nil
        IchaUIUF_RoleFade.settle = 20
        IchaUIUF_RefreshRoleIcons()
    end
    if event == "PLAYER_LOGOUT" then
        saveFrame("player", player)
        saveFrame("target", target)
        saveFrame("tot", tot)
        if frames.focus then saveFrame("focus", frames.focus) end
        savePartyDb()
        if saveRaidDb then saveRaidDb() end
        return
    end
    if event == "PARTY_MEMBERS_CHANGED" or event == "PARTY_MEMBER_ENABLE"
        or event == "PARTY_MEMBER_DISABLE" then
        IchaUIUF_layoutParty()
        if layoutRaid then layoutRaid() end
        if IchaUIUF_RefreshRoleIcons then IchaUIUF_RefreshRoleIcons() end
        if IchaUIUF_RoleFade.settle < 10 then IchaUIUF_RoleFade.settle = 10 end
        return
    end
    if event == "RAID_ROSTER_UPDATE" then
        IchaUIUF_layoutParty()
        if layoutRaid then layoutRaid() end
        if IchaUIUF_RefreshRoleIcons then IchaUIUF_RefreshRoleIcons() end
        if IchaUIUF_RoleFade.settle < 10 then IchaUIUF_RoleFade.settle = 10 end
        return
    end
    if event == "PARTY_LEADER_CHANGED" or event == "PARTY_LOOT_METHOD_CHANGED" then
        if IchaUIUF_RefreshRoleIcons then IchaUIUF_RefreshRoleIcons() end
        if IchaUIUF_RoleFade.settle < 10 then IchaUIUF_RoleFade.settle = 10 end
        return
    end
    if event == "RAID_TARGET_UPDATE" then
        if IchaUIUF_RefreshRaidMarks then IchaUIUF_RefreshRaidMarks() end
        return
    end
    if event == "PLAYER_AURAS_CHANGED" or event == "PLAYER_AURA" then
        -- Vanilla player buffs (shield recast) often skip UNIT_AURA.
        -- Shield charge circles are player-frame only. Player icons may refresh
        -- here (slot reuse); never rebuild target/tot/party/raid/combat grids.
        if IchaUIUF_PaintShieldCharges then IchaUIUF_PaintShieldCharges("player") end
        if player and player.updateAuras then player:updateAuras() end
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then
        -- Always rebuild target + ToT from live tokens (self-target included)
        if target then
            IchaUI_Swing_Clear(target)
            target._debuffFp = nil
            target._debuffUid = nil
            target._debuffShown = 0
            target._debuffEmptyN = 0
            target:update()
        end
        if tot then
            tot._debuffFp = nil
            tot._debuffUid = nil
            tot._debuffShown = 0
            tot._debuffEmptyN = 0
            tot:update()
        end
        if refreshTankDrawer then IchaUIUF_refreshTankDrawer() end
        if IchaUIUF_layoutTargetCluster then IchaUIUF_layoutTargetCluster() end
        return
    end
    if event == "PLAYER_LEVEL_UP" then
        if IchaUI_RefreshLevelShow then IchaUI_RefreshLevelShow() end
        return
    end
    if event == "UNIT_TARGET" then
        -- Turtle/SuperWoW may pass GUID or odd tokens — always refresh ToT
        if target then target:update() end
        if tot then tot:update() end
        return
    end
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_MANA"
        or event == "UNIT_MAXMANA" or event == "UNIT_ENERGY" or event == "UNIT_RAGE"
        or event == "UNIT_DISPLAYPOWER" or event == "UNIT_AURA" or event == "UNIT_NAME_UPDATE"
        or event == "UNIT_LEVEL" or event == "UNIT_PORTRAIT_UPDATE"
        or event == "UNIT_RESISTANCE" or event == "UNIT_ATTACK_SPEED" or event == "UNIT_ATTACK_POWER" then
        local u = arg1
        local skipAuras = (event ~= "UNIT_AURA")
        if event == "UNIT_ATTACK_SPEED" then
            if u and u ~= "" and u ~= "none" then
                IchaUI_Swing_RefreshToken(u)
            end
        end
        if u == "player" and player then
            if event == "UNIT_MANA" or event == "UNIT_MAXMANA" then
                local cur = UnitMana("player") or 0
                local last = player._lastMana
                if last ~= nil then
                    local delta = cur - last
                    -- Only mana *spend* (spell cost) starts FSR. Gains from spirit,
                    -- Mana Spring, pots, etc. must not touch the spark clock.
                    if delta <= -1 then
                        tripManaFsr(player)
                    end
                end
                player._lastMana = cur
            end
            player:update(skipAuras)
            if event == "UNIT_LEVEL" and IchaUI_RefreshLevelShow then
                IchaUI_RefreshLevelShow()
            end
        end
        if u == "target" then
            target:update(skipAuras)
            if tankDrawerOpen and IchaUIUF_tankDrawerOpen() and refreshTankDrawer then
                IchaUIUF_refreshTankDrawer()
            end
        end
        if u == "targettarget" then tot:update(skipAuras) end
        if isPartyUnit(u) or isRaidUnit(u) then
            local fr = frames[u]
            if fr then fr:update(skipAuras) end
        end
        -- ToT is often the same unit as player/target under a different token
        if tot and not badUnitToken(u) and u ~= "targettarget"
            and (string.find(u, "^0[xX]%x+$") or string.find(u, "^[a-z][a-z0-9]*$"))
            and UnitExists and UnitExists("targettarget")
            and UnitIsUnit and UnitIsUnit(u, "targettarget") then
            tot:update(skipAuras)
        end
        if event == "UNIT_AURA" then
            -- GUID / odd tokens skip the exact "player"/"target" branches above.
            -- Empty combat slots store unit "none"; never hand that to UnitIsUnit.
            if not badUnitToken(u) and (string.find(u, "^0[xX]%x+$") or string.find(u, "^[a-z][a-z0-9]*$")) and UnitIsUnit then
                if u ~= "player" and player then
                    local okp, samep = pcall(UnitIsUnit, "player", u)
                    if okp and samep and player.updateAuras then player:updateAuras() end
                end
                if u ~= "target" and target then
                    local okt, samet = pcall(UnitIsUnit, "target", u)
                    if okt and samet and target.updateAuras then target:updateAuras() end
                end
                if tot and u ~= "targettarget" then
                    local oko, sameo = pcall(UnitIsUnit, "targettarget", u)
                    if oko and sameo and tot.updateAuras then tot:updateAuras() end
                end
                local gi
                for gi = 1, 4 do
                    local pfr = partyFrames[gi]
                    if pfr and pfr.updateAuras and not badUnitToken(pfr.unit) and pfr.unit ~= u then
                        local okp, samep = pcall(UnitIsUnit, pfr.unit, u)
                        if okp and samep then pfr:updateAuras() end
                    end
                end
                for gi = 1, 40 do
                    local rfr = raidFrames[gi]
                    if rfr and rfr.updateAuras and not badUnitToken(rfr.unit) and rfr.unit ~= u then
                        local okr, samer = pcall(UnitIsUnit, rfr.unit, u)
                        if okr and samer then rfr:updateAuras() end
                    end
                end
                if IchaUI_CombatSlots then
                    for gi = 1, 40 do
                        local cfr = IchaUI_CombatSlots[gi]
                        if cfr and cfr.updateAuras and not badUnitToken(cfr.unit) and cfr.unit ~= u then
                            local okc, samec = pcall(UnitIsUnit, cfr.unit, u)
                            if okc and samec then cfr:updateAuras() end
                        end
                    end
                end
            end
            if IchaUIUF_PaintShieldCharges then IchaUIUF_PaintShieldCharges(u) end
        end
        return
    end
    if event == "UNIT_HEAL_PREDICTION" then
        local u = arg1
        if u == "player" then player:update(true) end
        if u == "target" then target:update(true) end
        if u == "targettarget" then tot:update(true) end
        return
    end
    if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "SPELLCAST_INTERRUPTED" then
        -- SPELLCAST_INTERRUPTED is the local player and has no unit token.
        -- A missing arg must not be treated as target and target-of-target.
        local who = "player"
        if event == "UNIT_SPELLCAST_INTERRUPTED" and arg1 and arg1 ~= "" then
            who = arg1
        end
        local function frameIsCaster(fr)
            if not fr or not fr.unit then return false end
            if fr.unit == who then return true end
            if UnitIsUnit then
                local ok, same = pcall(UnitIsUnit, fr.unit, who)
                if ok and same then return true end
            end
            return false
        end
        if frameIsCaster(player) then player:markInterrupted() end
        if frameIsCaster(target) then target:markInterrupted() end
        if frameIsCaster(tot) then tot:markInterrupted() end
        -- fall through to cast bar + optional heal fallback clear
    end
    if event == "UNIT_CASTEVENT" then
        -- SuperWoW melee swing: caster GUID + MAINHAND (shape-safe)
        if IchaUI_Swing_OnCastEvent then
            local swingEv = arg3
            if type(arg2) == "string" and string.upper(tostring(arg2)) == "MAINHAND" then
                swingEv = arg2
            elseif type(arg3) == "string" then
                swingEv = arg3
            elseif type(arg4) == "string" then
                swingEv = arg4
            end
            IchaUI_Swing_OnCastEvent(arg1, swingEv)
        end
        -- SuperWoW shapes vary: (guid, guid, event, spellId, durMs) or shifted
        local a1, a2, a3, a4, a5 = arg1, arg2, arg3, arg4, arg5
        local castEvent, spellID = nil, nil
        if type(a3) == "string" and type(a4) == "number" then
            castEvent, spellID = a3, a4
        elseif type(a2) == "string" and type(a3) == "number" then
            castEvent, spellID = a2, a3
        elseif type(a4) == "number" then
            spellID = a4
            castEvent = type(a3) == "string" and a3 or "START"
        end
        castEvent = castEvent and string.upper(tostring(castEvent)) or ""
        -- Feed target/ToT/party cast bars (Vanilla has no UnitCastingInfo for NPCs)
        do
            local durMs = nil
            if type(a3) == "string" and type(a4) == "number" then
                durMs = tonumber(a5)
            elseif type(a2) == "string" and type(a3) == "number" then
                durMs = tonumber(a4)
            else
                durMs = tonumber(a5) or tonumber(a4)
            end
            if a1 then
                swCastRemember(a1, castEvent, spellID, durMs)
            end
        end
        local isPlayerCaster = a1 and IchaUI_Swing_CasterIsUnit and IchaUI_Swing_CasterIsUnit(a1, "player")
        if isPlayerCaster and (castEvent == "START" or castEvent == "CHANNEL") then
            pendingCastId = spellID
            pendingCastName = spellNameFromId(spellID)
            if spellID then
                applyPlayerHealPred(pendingCastName, nil, spellID)
            end
        elseif isPlayerCaster and castEvent == "CAST" then
            do
                local pg = IchaUI_Swing_Guid and IchaUI_Swing_Guid("player")
                local pinfo = pg and swCastByGuid[pg]
                local skipCh = pinfo and pinfo.channel
                if (not skipCh) and IchaUI_Cast_MarkDone then
                    IchaUI_Cast_MarkDone("player", spellID, pinfo and pinfo.start)
                    if IchaUI_Cast_QuenchUnit then IchaUI_Cast_QuenchUnit("player") end
                end
            end
            local sname = spellNameFromId(spellID) or pendingCastName
            -- Cache prefix of the unit this cast landed on (SuperWoW arg2 = target GUID).
            -- Instant DoTs (Flame Shock, SW:P, Serpent Sting...) have no START, so a
            -- CAST on a known unit is the apply; refreshAuraTimersForSpell still only
            -- touches that unit's aura of the same spell.
            local castScope = nil
            if type(a2) == "string" and string.find(a2, "^0[xX]%x+$")
                and not string.find(a2, "^0[xX]0+$") then
                local cid = unitIdentity(a2)
                if cid then castScope = cid .. "::" end
            end
            if isMoltenBlastName(sname) then
                restoreFlameShockTicksFromMoltenBlast(castScope)
            else
                -- Apply: CAST on a known unit, pending START match, or this spell's own
                -- CD just started (shocks ~6s). Periodic CAST must not reset DoTs.
                local isTick = false
                do
                    local tickAt = IchaUI_PeriodicTickAt
                    local tickName = IchaUI_PeriodicTickName
                    local nowt = GetTime and GetTime() or 0
                    if tickAt and tickName and (nowt - tickAt) < 0.4 then
                        if sname and string.lower(sname) == tickName then isTick = true end
                    end
                end
                local pendingMatch = false
                if pendingCastId and spellID and tonumber(pendingCastId) == tonumber(spellID) then
                    pendingMatch = true
                elseif pendingCastName and sname and string.lower(pendingCastName) == string.lower(sname) then
                    pendingMatch = true
                end
                local cdDur = 0
                if (not isTick) and (not castScope) and (not pendingMatch) and sname
                    and type(GetSpellCooldown) == "function" then
                    local nowt = GetTime and GetTime() or 0
                    if spellID then
                        local okCd, st, du = pcall(GetSpellCooldown, spellID)
                        if okCd then
                            st = tonumber(st) or 0
                            du = tonumber(du) or 0
                            if du > 0 and st > 0 and (nowt - st) < 0.55 then
                                cdDur = du
                            end
                        end
                    end
                    if cdDur == 0 and type(GetSpellName) == "function" then
                        local book = BOOKTYPE_SPELL or "spell"
                        local want = string.lower(sname)
                        local si = 1
                        while si <= 250 do
                            local n = GetSpellName(si, book)
                            if not n then break end
                            if string.lower(n) == want then
                                local st, du = GetSpellCooldown(si, book)
                                st = tonumber(st) or 0
                                du = tonumber(du) or 0
                                if du > 0 and st > 0 and (nowt - st) < 0.55 then
                                    cdDur = du
                                end
                                break
                            end
                            si = si + 1
                        end
                    end
                end
                -- Ticks are SMSG_PERIODICAURALOG, never a SuperWoW CAST with a target
                -- GUID, so a tick landing just before a recast must not veto it.
                local apply = castScope or ((not isTick) and (pendingMatch or cdDur > 2.0))
                if apply then
                    IchaUI_RefreshAuraGuid = castScope
                    refreshAuraTimersForSpell(spellID, sname)
                    IchaUI_RefreshAuraGuid = nil
                end
            end
            pendingCastId = nil
            pendingCastName = nil
            if IchaUIUF_SyncShownAuraTimers then IchaUIUF_SyncShownAuraTimers() end
            if IchaUIUF_PaintShieldCharges then IchaUIUF_PaintShieldCharges("player") end
        elseif isPlayerCaster and (castEvent == "FAIL" or castEvent == "FAILED" or castEvent == "INTERRUPTED") then
            pendingCastId = nil
            pendingCastName = nil
        end
    end
    if event == "SPELLCAST_STOP" or event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED"
        or event == "SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if IchaUI_Cast_QuenchEvent then IchaUI_Cast_QuenchEvent(event, arg1) end
    end
    if string.find(event, "SPELLCAST") or event == "UNIT_CASTEVENT" then
        -- Mana ticker FSR is driven only by UnitMana spend (see UNIT_MANA), so
        -- 0-cost casts (Water Shield, etc.) never reset the spark.
        if event == "SPELLCAST_DELAYED" then
            local extra = tonumber(arg1) or 0
            if extra > 0 then
                if extra < 50 then extra = extra * 1000 end
                local g = IchaUI_Swing_Guid and IchaUI_Swing_Guid("player")
                local info = g and swCastByGuid[g]
                if not info and UnitName then
                    local okn, n = pcall(UnitName, "player")
                    if okn and n then info = swCastByName[swCastNormalizeName(n)] end
                end
                if info and not info.channel then
                    info.delay = (tonumber(info.delay) or 0) + extra
                    info.finish = (tonumber(info.finish) or 0) + extra
                end
            end
        end

        player:updateCast()
        target:updateCast()
        tot:updateCast()
        do
            local pi
            for pi = 1, 4 do
                local fr = partyFrames and partyFrames[pi]
                if fr and fr.updateCast then fr:updateCast() end
            end
        end
        -- Heal-cast fallback when UnitGetIncomingHeals / HealComm unavailable
        if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED"
            or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "SPELLCAST_STOP"
            or event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED" then
            local okLand = (event == "UNIT_SPELLCAST_STOP" or event == "SPELLCAST_STOP")
            if okLand and (pendingCastName or pendingCastId) then
                if isMoltenBlastName(pendingCastName) then
                    restoreFlameShockTicksFromMoltenBlast()
                else
                    local tid = unitIdentity("target")
                    if tid then IchaUI_RefreshAuraGuid = tid .. "::" end
                    refreshAuraTimersForSpell(pendingCastId, pendingCastName)
                    IchaUI_RefreshAuraGuid = nil
                end
            end
            if event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED"
                or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
                pendingCastId = nil
                pendingCastName = nil
            elseif okLand then
                pendingCastId = nil
                pendingCastName = nil
            end
            wipeHealFallback()
            if player and player.healPred then player.healPred:Hide() end
            if target and target.healPred then target.healPred:Hide() end
            if tot and tot.healPred then tot.healPred:Hide() end
            if player then player:update(true) end
            if target then target:update(true) end
            if tot then tot:update(true) end
            -- 1.12 SPELLCAST_START: arg1=spellName, arg2=castTime. UNIT_*: arg1=unit.
            local caster = "player"
            local spellHint = nil
            if event == "UNIT_SPELLCAST_START" then
                if arg1 and arg1 ~= "" and UnitExists(arg1) then
                    caster = arg1
                end
            else
                -- SPELLCAST_START is always the local player
                caster = "player"
                spellHint = arg1
            end
            if UnitExists(caster) then
                local info = getCastInfo(caster)
                local spellName = (info and info.name) or spellHint
                if caster == "player" and spellName then
                    pendingCastName = spellName
                    pendingCastId = info and info.spellId or pendingCastId
                end
                if spellName then
                    local lname = string.lower(spellName)
                    local isHeal = string.find(lname, "heal")
                        or string.find(lname, "rejuvenat")
                        or string.find(lname, "regrowth")
                        or string.find(lname, "flash")
                        or string.find(lname, "renew")
                        or string.find(lname, "holy light")
                        or string.find(lname, "healing touch")
                        or string.find(lname, "healing wave")
                        or string.find(lname, "chain heal")
                    if isHeal then
                        -- Auto-self-cast: friendly target => them; hostile/none => self
                        local dest, destUnit = nil, nil
                        if caster == "player" then
                            local hasT = UnitExists("target")
                            local friendT = hasT and UnitIsFriend and UnitIsFriend("player", "target")
                            local attackT = hasT and UnitCanAttack and UnitCanAttack("player", "target")
                            if hasT and friendT and not attackT then
                                dest = UnitName("target")
                                destUnit = "target"
                            else
                                dest = UnitName("player")
                                destUnit = "player"
                            end
                        elseif UnitExists("target") and UnitIsFriend and UnitIsFriend(caster, "target") then
                            dest = UnitName("target")
                            destUnit = "target"
                        end
                        if dest and destUnit then
                            local tex = info and info.texture or nil
                            local sid = pendingCastId or (info and info.spellId)
                            applyPlayerHealPred(spellName, tex, sid)
                        end
                    end
                end
            end
        end
        return
    end
    if event == "PLAYER_FLAGS_CHANGED" or event == "UNIT_FACTION" then
        if arg1 == "player" or not arg1 then player:updatePvP() end
        if arg1 == "target" or not arg1 then target:updatePvP() end
        if arg1 == "targettarget" or not arg1 then tot:updatePvP() end
        return
    end
    IchaUIUF_refreshAll()
end)

-- Smooth cast bar fill + lightweight heal-pred refresh
local function refreshHealOverlay(fr)
    if not fr or not fr.healPred or not fr.hpBg then return end
    local unit = fr.unit
    local healPred = fr.healPred
    local hpBg = fr.hpBg
    if not unit or not UnitExists(unit) or not healCastActive then
        healPred:Hide()
        return
    end
    local d = db()
    if d.predictHeals == false then
        healPred:Hide()
        return
    end
    if UnitIsDead(unit) or UnitIsGhost(unit) then
        healPred:Hide()
        return
    end
    local hpCur = UnitHealth(unit) or 0
    local hpMax = UnitHealthMax(unit) or 1
    if hpMax < 1 then hpMax = 1 end
    local pct = hpCur / hpMax
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end
    local barW = hpBg:GetWidth()
    if barW < 1 then barW = fr.width * fr.scale - 8 end
    local incoming = getIncomingHeals(unit) or 0
    local missing = hpMax - hpCur
    if incoming > missing then incoming = missing end
    placeHealPred(healPred, hpBg, barW, pct, incoming, hpMax)
end

local function resolveHealDest()
    if UnitExists("target") and UnitIsUnit and UnitIsUnit("target", "player") then
        return UnitName("player"), "player"
    end
    if UnitExists("target") and UnitIsFriend and UnitIsFriend("player", "target")
        and not (UnitCanAttack and UnitCanAttack("player", "target")) then
        return UnitName("target"), "target"
    end
    return UnitName("player"), "player"
end

local function isHealSpellName(spellName)
    if not spellName then return false end
    local lname = string.lower(spellName)
    return string.find(lname, "heal")
        or string.find(lname, "rejuvenat")
        or string.find(lname, "regrowth")
        or string.find(lname, "flash")
        or string.find(lname, "renew")
        or string.find(lname, "holy light")
        or string.find(lname, "healing touch")
        or string.find(lname, "healing wave")
        or string.find(lname, "chain heal")
        or string.find(lname, "lesser heal")
        or string.find(lname, "prayer of healing")
end

-- Apply green pred from the cast we actually started (rank from spellId when possible).
applyPlayerHealPred = function(spellName, texture, spellId)
    if not isHealSpellName(spellName) and not (spellId and isHealSpellName(spellNameFromId(spellId) or "")) then
        if spellId then
            local nm = spellNameFromId(spellId)
            if not isHealSpellName(nm) then return false end
            spellName = spellName or nm
        else
            return false
        end
    end
    if spellId and (not spellName or spellName == "") then
        spellName = spellNameFromId(spellId) or spellName
    end
    local destName, destUnit = resolveHealDest()
    if not destName then return false end
    local _, wantRank = parseSpellNameRank(spellName or "")
    local sid = spellId or pendingCastId
    -- Ignore bogus getCastInfo "spellId" heuristics (often cast time / junk < 100)
    if sid and tonumber(sid) and tonumber(sid) < 100 then
        sid = pendingCastId
    end
    local nm2, rk2 = nil, nil
    if sid then nm2, rk2 = rankFromSpellId(sid) end
    if rk2 then wantRank = rk2 end
    if nm2 and (not spellName or spellName == "") then spellName = nm2 end
    local amt = estimateHealAmount(spellName, texture, sid, wantRank)
    if not amt then
        amt = fallbackHealAmount(destUnit or "player")
    end
    if healDebug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cffc9a227IchaUI heal|r id=%s name=%s rank=%s tip=%s dest=%s",
            tostring(sid or "?"),
            tostring(spellName or "?"),
            tostring(wantRank or rk2 or "?"),
            tostring(amt or "?"),
            tostring(destName or "?")))
    end
    if not amt then return false end
    noteIncomingHeal(destName, amt)
    if player then player:update(true) end
    if target then target:update(true) end
    if tot then tot:update(true) end
    return true
end

local function syncPlayerHealCastFallback()
    if not UnitExists("player") then
        if healCastActive then
            wipeHealFallback()
            if player and player.healPred then player.healPred:Hide() end
            if target and target.healPred then target.healPred:Hide() end
        end
        return
    end
    local info = getCastInfo("player")
    if not info or not info.name then
        if healCastActive then
            wipeHealFallback()
            if player and player.healPred then player.healPred:Hide() end
            if target and target.healPred then target.healPred:Hide() end
        end
        return
    end
    if not isHealSpellName(info.name) then
        if healCastActive then
            wipeHealFallback()
            if player and player.healPred then player.healPred:Hide() end
            if target and target.healPred then target.healPred:Hide() end
        end
        return
    end
    -- Prefer SuperWoW cast id over getCastInfo's heuristic spellId
    local sid = pendingCastId or (info and info.spellId)
    applyPlayerHealPred(info.name, info.texture, sid)
end

local function refreshAuraTimers(fr)
    if not fr or not fr.debuffs then return end
    local now = GetTime and GetTime() or 0
    local i
    for i = 1, MAX_AURA_SLOTS do
        local icon = fr.debuffs[i]
        if icon and icon:IsShown() and icon.timer then
            if icon.expires and icon.expires > now then
                icon.timer:SetText(formatAuraTime(icon.expires - now))
                icon.timer:SetTextColor(1, 0.92, 0.65)
                icon.timer:Show()
            else
                if icon.expires then
                    icon.timer:SetText("")
                    icon.timer:Hide()
                end
            end
        end
        icon = fr.buffs and fr.buffs[i]
        if icon and icon:IsShown() and icon.timer then
            if icon.expires and icon.expires > now then
                icon.timer:SetText(formatAuraTime(icon.expires - now))
                icon.timer:SetTextColor(1, 0.92, 0.65)
                icon.timer:Show()
            else
                if icon.expires then
                    icon.timer:SetText("")
                    icon.timer:Hide()
                end
            end
        end
    end
end

local castTicker = CreateFrame("Frame")
local healTickAccum = 0
local function needsCastTick(fr)
    if not fr then return false end
    if fr.raidCompact then return false end
    -- Always poll player/target/tot: target casts often lack UNIT_SPELLCAST_*
    -- (ClassicAPI CastingInfo and/or SuperWoW GUID cache).
    return true
end

local totWatchId = nil
local totWatchAccum = 0
castTicker:SetScript("OnUpdate", function()
    if IchaUI_LEAVING then return end
    IchaUIUF_PollRoleFades(arg1)
    if player then updateManaTicker(player) end
    if player then IchaUI_Swing_Update(player) end
    if target then IchaUI_Swing_Update(target) end
    if tot then IchaUI_Swing_Update(tot) end
    -- Poll ToT identity — PLAYER_TARGET_CHANGED can lag behind targettarget on Turtle
    totWatchAccum = totWatchAccum + (arg1 or 0)
    if totWatchAccum >= 0.05 then
        totWatchAccum = 0
        local id = nil
        if UnitExists and UnitExists("targettarget") then
            id = unitIdentity("targettarget") or (UnitName and UnitName("targettarget")) or "?"
        else
            id = false
        end
        if id ~= totWatchId then
            totWatchId = id
            if tot then
                tot._swingStart = nil
                tot._swingPeriod = nil
                IchaUI_Swing_Hide(tot)
                tot:update()
            end
            if target then target:update() end
        end
    end
    if needsCastTick(player) then player:updateCast() end
    if needsCastTick(target) then target:updateCast() end
    if needsCastTick(tot) then tot:updateCast() end
    local pi
    for pi = 1, 4 do
        local fr = partyFrames[pi]
        if needsCastTick(fr) then fr:updateCast() end
    end
    if IchaUI_CombatSlots then
        local ci
        for ci = 1, 40 do
            local cfr = IchaUI_CombatSlots[ci]
            if cfr and cfr.root and cfr.root:IsShown() then
                IchaUI_Swing_Update(cfr)
                if cfr.updateCast then cfr:updateCast() end
            end
        end
    end
    healTickAccum = healTickAccum + (arg1 or 0)
    if healTickAccum >= 0.2 then
        healTickAccum = 0
        local d = db()
        if d.predictHeals ~= false then
            syncPlayerHealCastFallback()
            refreshHealOverlay(player)
            refreshHealOverlay(target)
            refreshHealOverlay(tot)
        end
        refreshAuraTimers(player)
        refreshAuraTimers(target)
        refreshAuraTimers(tot)
        for pi = 1, 4 do
            refreshAuraTimers(partyFrames[pi])
        end
        for pi = 1, 40 do
            refreshAuraTimers(raidFrames[pi])
        end
        if IchaUI_CombatSlots then
            local ai
            for ai = 1, 40 do
                refreshAuraTimers(IchaUI_CombatSlots[ai])
            end
        end
        sweepExpiredAuraCache()
    end
end)

-- Initial party layout (SV may load later on PLAYER_LOGIN)
IchaUIUF_restorePartyRootPos()
IchaUIUF_restoreRaidRootPos()
layoutRaid()
IchaUIUF_layoutParty()
