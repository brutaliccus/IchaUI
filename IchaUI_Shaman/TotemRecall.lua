-- IchaUI TotemRecall: after OOR wait, show Totemic Recall only when ready (or Move).
-- Click the icon to cast (Button OnClick is hardware). No chat spam. Lua 5.0 / 1.12

local DELAY_DEFAULT = 5
local DELAY_MIN = 1
local DELAY_MAX = 30
local TICK = 0.2
local RETRY = 1.5
local RECALL_NAME = "Totemic Recall"
local TURTLE_ID = 45513
local GOLD = { 0.78, 0.58, 0.16, 1 }
local ROUNDMASK = "Interface/AddOns/IchaUI/media/roundmask-circle"
local GOLD_RING = "Interface/Minimap/MiniMap-TrackingBorder"
local ICON_INSET_FRAC = 0.22
local ICON_SIZE = 36
local FALLBACK_TEX = "Interface\\Icons\\Spell_Nature_Earthquake"

local needSince = nil
local firedAt = nil
local lastPulse = 0
local lastRegen = nil
local wantFire = false
local failPrinted = false

local dbg = {
    toggle = false,
    combat = false,
    regen = "-",
    live = 0,
    inRange = 0,
    elapsed = 0,
    spell = "-",
    gcd = false,
    why = "init",
}

local function db()
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.combat then IchaUIDB.combat = {} end
    local c = IchaUIDB.combat
    if c.totemRecall == nil then c.totemRecall = false end
    if c.totemRecallDelay == nil then c.totemRecallDelay = DELAY_DEFAULT end
    if type(c.recallIcon) ~= "table" then
        c.recallIcon = {}
    end
    local ic = c.recallIcon
    if ic.scale == nil then ic.scale = 1 end
    if ic.point == nil then ic.point = "BOTTOM" end
    if ic.relPoint == nil then ic.relPoint = "BOTTOM" end
    if ic.x == nil then ic.x = 0 end
    if ic.y == nil then ic.y = 220 end
    return c
end

local function clampDelay(v)
    v = tonumber(v)
    if not v then v = DELAY_DEFAULT end
    v = math.floor(v + 0.5)
    if v < DELAY_MIN then v = DELAY_MIN end
    if v > DELAY_MAX then v = DELAY_MAX end
    return v
end

local iconRoot
local iconSlot
local iconTex
local iconMover
local iconMoving = false
local showRecallIcon

local function stopTargeting()
    if SpellIsTargeting and SpellIsTargeting() and SpellStopTargeting then
        SpellStopTargeting()
    end
end

local function resetWait()
    needSince = nil
    firedAt = nil
    wantFire = false
end

function IchaUI_TotemRecallGet()
    return db().totemRecall and true or false
end

function IchaUI_TotemRecallSet(on)
    db().totemRecall = on and true or false
    if not on then
        resetWait()
        stopTargeting()
    end
    if showRecallIcon then showRecallIcon() end
end

function IchaUI_TotemRecallDelay()
    return clampDelay(db().totemRecallDelay)
end

function IchaUI_TotemRecallDelaySet(v)
    db().totemRecallDelay = clampDelay(v)
end

-- Regen "in" zeros the clock even if UnitAffectingCombat lags. regen=nil is OOC.
local function inCombat()
    if lastRegen == "in" then
        return true
    end
    if type(UnitAffectingCombat) == "function" then
        local affecting = false
        pcall(function()
            if UnitAffectingCombat("player") then
                affecting = true
            end
        end)
        if affecting then
            return true
        end
    end
    return false
end

local function playerDead()
    local dead = false
    pcall(function()
        if UnitIsDead and UnitIsDead("player") then
            dead = true
        elseif UnitIsGhost and UnitIsGhost("player") then
            dead = true
        end
    end)
    return dead
end

local function onTaxi()
    local taxi = false
    pcall(function()
        if UnitOnTaxi and UnitOnTaxi("player") then
            taxi = true
        end
    end)
    return taxi
end

local function isRecallSpellName(name)
    if not name or name == "" then return false end
    local l = string.lower(tostring(name))
    if string.find(l, "totemic recall", 1, true) then return true end
    if string.find(l, "totem recall", 1, true) then return true end
    if string.find(l, "recall totems", 1, true) then return true end
    if string.find(l, "recall of the totem", 1, true) then return true end
    if string.find(l, "recall", 1, true) and string.find(l, "totem", 1, true) then
        return true
    end
    return false
end

local function exactRecallName(name)
    if not name or name == "" then return false end
    local l = string.lower(tostring(name))
    if l == "totemic recall" then return true end
    if l == "totem recall" then return true end
    if l == "recall totems" then return true end
    return false
end

local function nameIsRecall(name)
    return isRecallSpellName(name) or exactRecallName(name)
end

local function findRecall()
    if IchaUITotems_RecallSpell and IchaUITotems_RecallSpell.index then
        local cached = IchaUITotems_RecallSpell
        if type(GetSpellName) == "function" then
            local n = GetSpellName(cached.index, BOOKTYPE_SPELL or "spell")
            if n and nameIsRecall(n) then
                cached.name = n
                return cached
            end
        else
            return cached
        end
    end
    if type(GetSpellName) ~= "function" then return nil end
    local book = BOOKTYPE_SPELL or "spell"
    local turtle = nil
    pcall(function()
        if SpellInfo then
            turtle = SpellInfo(TURTLE_ID)
        end
    end)
    if turtle then
        turtle = string.lower(tostring(turtle))
    end
    local best = nil
    local exact = nil
    local i = 1
    while i <= 500 do
        local name, rank = GetSpellName(i, book)
        if not name then break end
        local rec = { name = name, rank = rank, index = i }
        if turtle and string.lower(name) == turtle then
            exact = rec
        end
        if exactRecallName(name) then
            exact = rec
        end
        if isRecallSpellName(name) then
            best = rec
        end
        i = i + 1
    end
    local rec = exact or best
    if rec and rec.index and type(GetSpellTexture) == "function" then
        local t = GetSpellTexture(rec.index, BOOKTYPE_SPELL or "spell")
        if t then rec.texture = t end
    end
    return rec
end

local function onGcd(entry)
    if type(GetSpellCooldown) ~= "function" then return false end
    if not entry or not entry.index then return false end
    local book = BOOKTYPE_SPELL or "spell"
    local start, duration = GetSpellCooldown(entry.index, book)
    start = tonumber(start) or 0
    duration = tonumber(duration) or 0
    if start > 0 and duration > 0 then
        local now = GetTime and GetTime() or 0
        if (start + duration - now) > 0.05 then
            return true
        end
    end
    return false
end

local function liveRange()
    if type(IchaUITotems_LiveRangeQuery) ~= "function" then
        return 0, false, 0
    end
    local n, allOor, nIn = IchaUITotems_LiveRangeQuery()
    n = tonumber(n) or 0
    nIn = tonumber(nIn) or 0
    if n < 1 then
        return 0, false, 0
    end
    return n, allOor and true or false, nIn
end

local function recallTexture(entry)
    if entry and entry.texture and entry.texture ~= "" then
        return entry.texture
    end
    if entry and entry.index and type(GetSpellTexture) == "function" then
        local t = GetSpellTexture(entry.index, BOOKTYPE_SPELL or "spell")
        if t and t ~= "" then return t end
    end
    return FALLBACK_TEX
end

local function iconScale()
    local s = tonumber(db().recallIcon.scale) or 1
    if s < 0.5 then s = 0.5 end
    if s > 2.5 then s = 2.5 end
    return s
end

local function saveIconPos()
    if not iconRoot then return end
    local ic = db().recallIcon
    local p, _, rp, x, y = iconRoot:GetPoint(1)
    ic.point = p or "BOTTOM"
    ic.relPoint = rp or p or "BOTTOM"
    ic.x = tonumber(x) or 0
    ic.y = tonumber(y) or 220
end

local function restoreIconPos()
    if not iconRoot then return end
    local ic = db().recallIcon
    iconRoot:ClearAllPoints()
    iconRoot:SetPoint(ic.point or "BOTTOM", UIParent, ic.relPoint or ic.point or "BOTTOM", tonumber(ic.x) or 0, tonumber(ic.y) or 220)
end

local function layoutRecallIcon()
    if not iconRoot or not iconSlot then return end
    local size = math.floor(ICON_SIZE * iconScale() + 0.5)
    if size < 16 then size = 16 end
    local bsc = 1
    if IchaUI_DrawerButtonScale then bsc = IchaUI_DrawerButtonScale("recall") end
    size = math.floor(size * bsc + 0.5)
    iconRoot:SetWidth(size)
    iconRoot:SetHeight(size)
    iconSlot:SetWidth(size)
    iconSlot:SetHeight(size)
    if type(insetIcon) == "function" and iconTex then
        insetIcon(iconTex, iconSlot, size)
    elseif iconTex then
        local iconSz = math.floor(size * (1 - 2 * ICON_INSET_FRAC) + 0.5)
        if iconSz < 10 then iconSz = 10 end
        iconTex:ClearAllPoints()
        iconTex:SetWidth(iconSz)
        iconTex:SetHeight(iconSz)
        iconTex:SetPoint("CENTER", iconSlot, "CENTER", 0, 2)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    if iconSlot.circleBg and iconTex then
        iconSlot.circleBg:SetTexture("Interface\\AddOns\\IchaUI\\media\\circledisc.tga")
        iconSlot.circleBg:SetVertexColor(0.05, 0.05, 0.06, 1)
        iconSlot.circleBg:ClearAllPoints()
        iconSlot.circleBg:SetPoint("TOPLEFT", iconTex, "TOPLEFT", 0, 0)
        iconSlot.circleBg:SetPoint("BOTTOMRIGHT", iconTex, "BOTTOMRIGHT", 0, 0)
        iconSlot.circleBg:Show()
    end
    if iconSlot.circleMask then iconSlot.circleMask:Hide() end
    if iconSlot.roundMask and iconTex then
        iconSlot.roundMask:SetTexture(ROUNDMASK)
        iconSlot.roundMask:SetVertexColor(0, 0, 0, 1)
        iconSlot.roundMask:ClearAllPoints()
        iconSlot.roundMask:SetPoint("TOPLEFT", iconTex, "TOPLEFT", 0, 0)
        iconSlot.roundMask:SetPoint("BOTTOMRIGHT", iconTex, "BOTTOMRIGHT", 0, 0)
        iconSlot.roundMask:Show()
    end
    local formShape = "circle"
    if IchaUI_DrawerShape then formShape = IchaUI_DrawerShape("recall") end
    if formShape == "rect" then
        iconSlot:SetWidth(math.floor(size * 4 / 3 + 0.5))
        iconRoot:SetWidth(math.floor(size * 4 / 3 + 0.5))
    end
    if type(applyGoldRing) == "function" and iconSlot.goldRing then
        applyGoldRing(iconSlot.goldRing, iconSlot, size)
    elseif iconSlot.goldRing then
        local bw = math.floor(size * 1.65 + 0.5)
        iconSlot.goldRing:SetWidth(bw)
        iconSlot.goldRing:SetHeight(bw)
        iconSlot.goldRing:ClearAllPoints()
        iconSlot.goldRing:SetPoint("TOPLEFT", iconSlot, "TOPLEFT", 0, 0)
    end
    if IchaUI_ApplyButtonForm then IchaUI_ApplyButtonForm(iconSlot, formShape) end
    if iconMover then
        iconMover:SetAllPoints(iconRoot)
    end
end

local function paintRecallIcon()
    if not iconTex then return end
    iconTex:SetTexture(recallTexture(findRecall()))
end

local function ensureRecallIcon()
    if iconRoot then return iconRoot end
    iconRoot = CreateFrame("Frame", "IchaUITotemRecallIcon", UIParent)
    iconRoot:SetFrameStrata("MEDIUM")
    iconRoot:SetMovable(true)
    iconRoot:EnableMouse(false)
    if iconRoot.SetClampedToScreen then
        iconRoot:SetClampedToScreen(true)
    end
    iconRoot:Hide()

    iconSlot = CreateFrame("Button", "IchaUITotemRecallIconSlot", iconRoot)
    iconSlot:EnableMouse(true)
    iconSlot:RegisterForClicks("LeftButtonUp")
    iconSlot:SetPoint("CENTER", iconRoot, "CENTER", 0, 0)

    local circleBg = iconSlot:CreateTexture(nil, "BACKGROUND")
    circleBg:SetTexture("Interface\\AddOns\\IchaUI\\media\\circledisc.tga")
    circleBg:SetVertexColor(0.05, 0.05, 0.06, 1)
    iconSlot.circleBg = circleBg

    iconTex = iconSlot:CreateTexture(nil, "ARTWORK")
    iconSlot.icon = iconTex
    if IchaUI_WrapButtonIcon then IchaUI_WrapButtonIcon(iconSlot) end

    local round = iconSlot:CreateTexture(nil, "ARTWORK")
    round:SetTexture(ROUNDMASK)
    round:SetVertexColor(0, 0, 0, 1)
    round:Show()
    iconSlot.roundMask = round

    local goldRing = iconSlot:CreateTexture(nil, "OVERLAY")
    goldRing:SetTexture(GOLD_RING)
    IchaUI_PaintGoldRing(goldRing)
    iconSlot.goldRing = goldRing

    iconMover = CreateFrame("Frame", nil, iconRoot)
    iconMover:SetAllPoints(iconRoot)
    iconMover:EnableMouse(true)
    iconMover:RegisterForDrag("LeftButton")
    iconMover:Hide()
    iconMover:SetFrameLevel((iconRoot:GetFrameLevel() or 1) + 30)
    local mbg = iconMover:CreateTexture(nil, "BACKGROUND")
    mbg:SetAllPoints(iconMover)
    mbg:SetTexture(1, 1, 1, 1)
    mbg:SetVertexColor(0.15, 0.45, 0.95, 0.35)
    local ml = iconMover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ml:SetPoint("CENTER", iconMover, "CENTER")
    ml:SetText("Drag")
    iconMover:SetScript("OnDragStart", function() iconRoot:StartMoving() end)
    iconMover:SetScript("OnDragStop", function()
        iconRoot:StopMovingOrSizing()
        saveIconPos()
    end)
    iconMover:SetScript("OnMouseUp", function()
        if arg1 == "RightButton" and IchaUI_DrawerEditClick then IchaUI_DrawerEditClick("recall") end
    end)

    iconSlot:SetScript("OnClick", function()
        if iconMoving then return end
        if IchaUI_TotemRecall_Fire then
            IchaUI_TotemRecall_Fire()
        end
    end)
    iconSlot:SetScript("OnEnter", function()
        if iconMoving then return end
        if GameTooltip then
            GameTooltip:SetOwner(iconSlot, "ANCHOR_RIGHT")
            GameTooltip:SetText("Totemic Recall")
            GameTooltip:AddLine("Click to recall totems", 0.92, 0.88, 0.75)
            GameTooltip:Show()
        end
    end)
    iconSlot:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    restoreIconPos()
    layoutRecallIcon()
    paintRecallIcon()
    IchaUI_ApplyRecallIconStrata()
    local leftover = getglobal("IchaUITotemRecallClick")
    if leftover then leftover:Hide() end
    return iconRoot
end

function IchaUI_ApplyRecallIconStrata()
    if not iconRoot then return end
    local name = "MEDIUM"
    if IchaUI_GetIconStrata then
        local n = IchaUI_GetIconStrata()
        if n and n ~= "" then name = n end
    end
    if IchaUI_DrawerStyleGet then
        local savedStrata = IchaUI_DrawerStyleGet("recall")
        if savedStrata and savedStrata ~= "" then name = savedStrata end
    end
    pcall(function()
        iconRoot:SetFrameStrata(name)
    end)
    if iconMover and iconMover.SetFrameStrata then
        pcall(function()
            iconMover:SetFrameStrata(name)
            local base = 1
            if iconSlot and iconSlot.GetFrameLevel then
                base = iconSlot:GetFrameLevel() or 1
            end
            iconMover:SetFrameLevel(base + 12)
        end)
    end
end

showRecallIcon = function()
    ensureRecallIcon()
    local vis = iconMoving or wantFire
    if vis then
        paintRecallIcon()
        layoutRecallIcon()
        iconRoot:Show()
    else
        iconRoot:Hide()
    end
end

function IchaUI_TotemRecallIcon_Moving()
    return iconMoving and true or false
end

function IchaUI_TotemRecallIcon_ApplyPos()
    ensureRecallIcon()
    restoreIconPos()
end

function IchaUI_TotemRecallIcon_ToggleMove()
    ensureRecallIcon()
    iconMoving = not iconMoving
    if iconMoving then
        restoreIconPos()
        layoutRecallIcon()
        iconRoot:Show()
        iconMover:Show()
    else
        iconMover:Hide()
        saveIconPos()
        showRecallIcon()
    end
    return iconMoving
end

function IchaUI_TotemRecallIcon_Scale()
    return iconScale()
end

function IchaUI_TotemRecallIcon_ScaleSet(v)
    v = tonumber(v) or 1
    if v < 0.5 then v = 0.5 end
    if v > 2.5 then v = 2.5 end
    db().recallIcon.scale = v
    ensureRecallIcon()
    layoutRecallIcon()
    showRecallIcon()
end

local function decide(skipRetry)
    wantFire = false
    dbg.toggle = IchaUI_TotemRecallGet() and true or false
    dbg.combat = inCombat() and true or false
    dbg.regen = lastRegen or "--"
    dbg.elapsed = 0
    dbg.spell = "-"
    dbg.gcd = false

    local n, allOor, nIn = liveRange()
    dbg.live = n
    dbg.inRange = nIn

    if not dbg.toggle then
        dbg.why = "toggle"
        resetWait()
        return
    end

    -- Clock reset if nothing is live or any totem is in range.
    if n < 1 or not allOor then
        if n < 1 then
            dbg.why = "no-live"
        else
            dbg.why = "in-range"
        end
        resetWait()
        return
    end

    -- Combat: stop the clock, zero elapsed, never fire. Fresh wait starts on leave.
    if inCombat() then
        dbg.why = "combat"
        resetWait()
        return
    end

    local now = GetTime and GetTime() or 0
    if not needSince then
        needSince = now
        dbg.why = "wait"
        dbg.elapsed = 0
        return
    end
    dbg.elapsed = now - needSince
    if dbg.elapsed < 0 then
        dbg.elapsed = 0
    end
    if dbg.elapsed < IchaUI_TotemRecallDelay() then
        dbg.why = "wait"
        return
    end

    -- Dead/taxi: skip this send, keep OOR elapsed so we fire as soon as we can.
    if playerDead() then
        dbg.why = "dead"
        return
    end
    if onTaxi() then
        dbg.why = "taxi"
        return
    end

    local entry = findRecall()
    if entry and entry.index then
        dbg.spell = tostring(entry.index)
    else
        dbg.spell = "click"
    end

    if onGcd(entry) then
        dbg.gcd = true
        dbg.why = "gcd"
        wantFire = true
        return
    end

    wantFire = true
    dbg.why = "queued"
end

local function sendRecall(entry)
    local name = RECALL_NAME
    if entry and entry.name and entry.name ~= "" then
        name = entry.name
    end
    if entry and entry.index and type(CastSpell) == "function" then
        CastSpell(entry.index, BOOKTYPE_SPELL or "spell")
        return true
    end
    if type(CastSpellByName) == "function" then
        CastSpellByName(name)
        return true
    end
    return false
end

function IchaUI_TotemRecall_Fire()
    local entry = findRecall()
    if onGcd(entry) then
        wantFire = true
        return false
    end
    wantFire = false
    firedAt = GetTime and GetTime() or 0
    local ok = sendRecall(entry)
    if SpellIsTargeting and SpellIsTargeting() then
        stopTargeting()
    end
    return ok and true or false
end

function IchaUI_TotemRecall_TryFire()
    pcall(function()
        decide(true)
    end)
    if wantFire then
        return IchaUI_TotemRecall_Fire()
    end
    return false
end

function IchaUI_TotemRecallPulse()
    local now = GetTime and GetTime() or 0
    if (now - lastPulse) < TICK then return end
    lastPulse = now
    pcall(decide)
    showRecallIcon()
end

function IchaUI_TotemRecallDebug()
    pcall(decide)
    wantFire = false
    if dbg.spell == "-" then
        local entry = findRecall()
        if entry and entry.index then
            dbg.spell = tostring(entry.index)
        else
            dbg.spell = "script"
        end
    end
    local msg = string.format(
        "IchaUI recall: toggle=%s combat=%s regen=%s live=%d inRange=%d elapsed=%.1f spell=%s gcd=%s why=%s",
        tostring(dbg.toggle),
        tostring(dbg.combat),
        tostring(dbg.regen),
        tonumber(dbg.live) or 0,
        tonumber(dbg.inRange) or 0,
        tonumber(dbg.elapsed) or 0,
        tostring(dbg.spell),
        tostring(dbg.gcd),
        tostring(dbg.why)
    )
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
end

local f = CreateFrame("Frame", "IchaUITotemRecall", UIParent)
f:SetWidth(1)
f:SetHeight(1)
f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
f:Show()
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("SPELLS_CHANGED")
f:SetScript("OnEvent", function()
    if event == "PLAYER_REGEN_DISABLED" then
        lastRegen = "in"
        resetWait()
        dbg.elapsed = 0
        dbg.why = "combat"
    elseif event == "PLAYER_REGEN_ENABLED" then
        lastRegen = "out"
        -- Fresh wait from this moment if still live and all OOR (not leftover pre-combat time).
        pcall(decide)
    elseif event == "PLAYER_ENTERING_WORLD" then
        resetWait()
        failPrinted = false
        stopTargeting()
        if showRecallIcon then showRecallIcon() end
    elseif event == "SPELLS_CHANGED" then
        if paintRecallIcon then paintRecallIcon() end
    end
end)

f:SetScript("OnUpdate", function()
    IchaUI_TotemRecallPulse()
end)

local prevIcha = SlashCmdList and SlashCmdList["ICHA"]
if SlashCmdList then
    SlashCmdList["ICHA"] = function(msg)
        local m = string.lower(string.gsub(msg or "", "^%s+", ""))
        if m == "recalldebug" or m == "recall debug" then
            IchaUI_TotemRecallDebug()
            return
        end
        if prevIcha then
            prevIcha(msg)
        end
    end
end

function IchaUI_TotemRecallReload()
    if not iconRoot then return end
    restoreIconPos()
    layoutRecallIcon()
    IchaUI_ApplyRecallIconStrata()
end
