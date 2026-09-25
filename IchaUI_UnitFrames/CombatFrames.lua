-- Grid of unit frames for enemies the player or the party/raid is fighting, plus raid-marked hostiles.
-- Loaded after UnitFrames.lua. Shared look lives in IchaUIDB.uf.combatGroup
-- under the options key "combat". Default grid is 1 column by 10 rows.

local MAX_CAP = 40
local TOUCH_SEC = 5

local root = CreateFrame("Frame", "IchaUICombatList", UIParent)
root:SetWidth(200)
root:SetHeight(40)
root:SetPoint("LEFT", UIParent, "LEFT", 16, 40)
root:SetMovable(true)
root:EnableMouse(false)
root:RegisterForDrag("LeftButton")
root:SetScript("OnDragStart", function()
    if this.moving then
        this.dragging = true
        this:StartMoving()
    end
end)
root:SetScript("OnDragStop", function()
    this.dragging = false
    this:StopMovingOrSizing()
    local pt, _, rp, x, y = this:GetPoint(1)
    local g = IchaUI_CombatProfile()
    g.point = pt or g.point or "LEFT"
    g.relPoint = rp or pt or g.relPoint or "LEFT"
    g.x = tonumber(x) or 16
    g.y = tonumber(y) or 40
    IchaUI_CombatPlaceRoot()
end)

local dragCover = CreateFrame("Frame", nil, root)
dragCover:SetAllPoints(root)
dragCover:EnableMouse(true)
dragCover:RegisterForDrag("LeftButton")
dragCover:SetFrameLevel(80)
dragCover:Hide()
local dragBg = dragCover:CreateTexture(nil, "BACKGROUND")
dragBg:SetAllPoints(dragCover)
dragBg:SetTexture(1, 1, 1, 1)
dragBg:SetVertexColor(0.15, 0.45, 0.95, 0.35)
local dragLabel = dragCover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
dragLabel:SetPoint("CENTER", dragCover, "CENTER")
dragLabel:SetText("Drag in combat")
dragCover:SetScript("OnDragStart", function()
    if root.moving then
        root.dragging = true
        root:StartMoving()
    end
end)
dragCover:SetScript("OnDragStop", function()
    root.dragging = false
    root:StopMovingOrSizing()
    local pt, _, rp, x, y = root:GetPoint(1)
    local g = IchaUI_CombatProfile()
    g.point = pt or g.point or "LEFT"
    g.relPoint = rp or pt or g.relPoint or "LEFT"
    g.x = tonumber(x) or 16
    g.y = tonumber(y) or 40
    IchaUI_CombatPlaceRoot()
end)

local title = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("BOTTOMLEFT", root, "TOPLEFT", 0, 2)
title:SetText("In combat")
title:Hide()

local slots = {}
local touchAt = {}
local firstSeen = {}
local order = {}
local markOf = {}
local markedKeep = {}
-- GUID -> last known name (or true). Kept while that mob is in combat with the player
-- so a vanished nameplate (LoS / cap) does not delete the row.
local combatHold = {}
-- GUID was seen targeting the player. Those rows stay for the rest of this combat.
local combatOnMe = {}
-- raidNtarget sweep is throttled; GUIDs it found are rewatched between sweeps.
local raidSweep = { at = 0, guids = {} }

function IchaUI_CombatProfile()
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.uf then IchaUIDB.uf = {} end
    local g = IchaUIDB.uf.combatGroup
    if type(g) ~= "table" then
        g = {}
        IchaUIDB.uf.combatGroup = g
    end
    if g.scale == nil then g.scale = 1 end
    if g.width == nil then g.width = 200 end
    if g.height == nil then g.height = 40 end
    if g.pad == nil then g.pad = 4 end
    if g.portrait == nil then g.portrait = true end
    if g.portraitScale == nil then g.portraitScale = 1.22 end
    if g.portraitRing == nil then g.portraitRing = 1.28 end
    if g.portraitOffsetX == nil then g.portraitOffsetX = 0 end
    if g.portraitOffsetY == nil then g.portraitOffsetY = 0 end
    if g.portraitSide == nil then g.portraitSide = "left" end
    if g.badgeAngle == nil then g.badgeAngle = 0 end
    if g.badgeScale == nil then g.badgeScale = 1 end
    if g.badgeOffsetX == nil then g.badgeOffsetX = 0 end
    if g.badgeOffsetY == nil then g.badgeOffsetY = 0 end
    if g.shieldChargeEnabled == nil then g.shieldChargeEnabled = true end
    if g.shieldChargeSpread == nil then g.shieldChargeSpread = 90 end
    if g.shieldChargeSize == nil then g.shieldChargeSize = 10 end
    if g.shieldChargeAngle == nil then g.shieldChargeAngle = 0 end
    if g.shieldChargeReverse == nil then g.shieldChargeReverse = false end
    if g.shieldChargeOffsetX == nil then g.shieldChargeOffsetX = 0 end
    if g.shieldChargeOffsetY == nil then g.shieldChargeOffsetY = 0 end
    if g.x == nil then g.x = 16 end
    if g.y == nil then g.y = 40 end
    if g.point == nil then g.point = "LEFT" end
    if g.relPoint == nil then g.relPoint = "LEFT" end
    if g.cols == nil then g.cols = 1 end
    if g.rows == nil then g.rows = 10 end
    return g
end

function IchaUI_CombatPlaceRoot()
    if root.dragging then return end
    local g = IchaUI_CombatProfile()
    root:ClearAllPoints()
    root:SetPoint(g.point or "LEFT", UIParent, g.relPoint or "LEFT", tonumber(g.x) or 16, tonumber(g.y) or 40)
end

function IchaUI_CombatGetPos()
    local g = IchaUI_CombatProfile()
    return tonumber(g.x) or 16, tonumber(g.y) or 40, g.point or "LEFT", g.relPoint or "LEFT"
end

function IchaUI_CombatSetPos(x, y)
    local g = IchaUI_CombatProfile()
    g.x = tonumber(x) or 0
    g.y = tonumber(y) or 0
    IchaUI_CombatPlaceRoot()
end

local function clampNum(v, lo, hi, fallback)
    v = tonumber(v)
    if not v then v = fallback end
    if v < lo then v = lo end
    if v > hi then v = hi end
    return v
end

local function gridLimits()
    local g = IchaUI_CombatProfile()
    local cols = clampNum(g.cols, 1, MAX_CAP, 1)
    local rows = clampNum(g.rows, 1, MAX_CAP, 10)
    if cols * rows > MAX_CAP then
        rows = math.max(1, math.floor(MAX_CAP / cols))
    end
    g.cols = cols
    g.rows = rows
    return cols, rows, cols * rows
end

local function pushLook(fr)
    local g = IchaUI_CombatProfile()
    fr.scale = clampNum(g.scale, 0.4, 3, 1)
    fr.width = clampNum(g.width, 1, 600, 200)
    fr.height = clampNum(g.height, 1, 420, 40)
    fr.portraitEnabled = g.portrait ~= false
    fr.portraitScale = clampNum(g.portraitScale, 0.8, 2.5, 1.22)
    fr.portraitRing = clampNum(g.portraitRing, 0.90, 1.40, 1.28)
    fr.portraitOffsetX = clampNum(g.portraitOffsetX, -40, 40, 0)
    fr.portraitOffsetY = clampNum(g.portraitOffsetY, -40, 40, 0)
    fr.portraitSide = (g.portraitSide == "right") and "right" or "left"
    fr.badgeAngle = clampNum(g.badgeAngle, 0, 360, 0)
    fr.badgeScale = clampNum(g.badgeScale, 0.5, 2.0, 1)
    fr.badgeOffsetX = clampNum(g.badgeOffsetX, -40, 40, 0)
    fr.badgeOffsetY = clampNum(g.badgeOffsetY, -40, 40, 0)
    if g.badgeHost == "frame" or g.badgeHost == "portrait" then
        fr.badgeHost = g.badgeHost
    else
        fr.badgeHost = nil
    end
    fr.shieldChargeEnabled = g.shieldChargeEnabled ~= false
    fr.shieldChargeSpread = clampNum(g.shieldChargeSpread, 10, 360, 90)
    fr.shieldChargeSize = clampNum(g.shieldChargeSize, 6, 28, 10)
    fr.shieldChargeAngle = clampNum(g.shieldChargeAngle, -360, 360, 0)
    fr.shieldChargeReverse = g.shieldChargeReverse and true or false
    fr.shieldChargeOffsetX = clampNum(g.shieldChargeOffsetX, -40, 40, 0)
    fr.shieldChargeOffsetY = clampNum(g.shieldChargeOffsetY, -40, 40, 0)
    fr.hidden = false
end

function IchaUI_CombatSet(field, value)
    local g = IchaUI_CombatProfile()
    if field == "scale" then
        local oldSc = tonumber(g.scale) or 1
        g.scale = clampNum(value, 0.4, 3, 1)
        if not IchaUI_BarSkipRefit and IchaUIUF_ScaleSavedBars then
            IchaUIUF_ScaleSavedBars("combat", oldSc, g.scale)
        end
    elseif field == "width" then
        g.width = clampNum(value, 1, 600, 200)
    elseif field == "height" then
        g.height = clampNum(value, 1, 420, 40)
        if not IchaUI_BarSkipRefit and IchaUIUF_RefitBarsToHeight then
            IchaUIUF_RefitBarsToHeight("combat", g.height, g.scale)
        end
    elseif field == "pad" then
        g.pad = clampNum(value, 0, 24, 4)
    elseif field == "cols" or field == "columns" then
        g.cols = clampNum(value, 1, MAX_CAP, 1)
        local rows = clampNum(g.rows, 1, MAX_CAP, 10)
        if g.cols * rows > MAX_CAP then
            rows = math.max(1, math.floor(MAX_CAP / g.cols))
        end
        g.rows = rows
    elseif field == "rows" or field == "row" then
        g.rows = clampNum(value, 1, MAX_CAP, 10)
        local cols = clampNum(g.cols, 1, MAX_CAP, 1)
        if cols * g.rows > MAX_CAP then
            cols = math.max(1, math.floor(MAX_CAP / g.rows))
        end
        g.cols = cols
    elseif field == "portrait" then
        g.portrait = value and true or false
    elseif field == "portraitScale" then
        g.portraitScale = clampNum(value, 0.8, 2.5, 1.22)
    elseif field == "portraitRing" then
        g.portraitRing = clampNum(value, 0.90, 1.40, 1.28)
    elseif field == "portraitOffsetX" then
        g.portraitOffsetX = clampNum(value, -40, 40, 0)
    elseif field == "portraitOffsetY" then
        g.portraitOffsetY = clampNum(value, -40, 40, 0)
    elseif field == "portraitSide" then
        if value == "right" then g.portraitSide = "right" else g.portraitSide = "left" end
    elseif field == "badgeAngle" then
        g.badgeAngle = clampNum(value, 0, 360, 0)
    elseif field == "badgeScale" then
        g.badgeScale = clampNum(value, 0.5, 2.0, 1)
    elseif field == "badgeOffsetX" then
        g.badgeOffsetX = clampNum(value, -40, 40, 0)
    elseif field == "badgeOffsetY" then
        g.badgeOffsetY = clampNum(value, -40, 40, 0)
    elseif field == "badgeHost" then
        if value == "frame" then g.badgeHost = "frame" else g.badgeHost = "portrait" end
    elseif field == "shieldChargeEnabled" then
        g.shieldChargeEnabled = value and true or false
    elseif field == "shieldChargeSpread" then
        g.shieldChargeSpread = clampNum(value, 10, 360, 90)
    elseif field == "shieldChargeSize" then
        g.shieldChargeSize = clampNum(value, 6, 28, 10)
    elseif field == "shieldChargeAngle" then
        g.shieldChargeAngle = clampNum(value, -360, 360, 0)
    elseif field == "shieldChargeReverse" then
        g.shieldChargeReverse = value and true or false
    elseif field == "shieldChargeOffsetX" then
        g.shieldChargeOffsetX = clampNum(value, -40, 40, 0)
    elseif field == "shieldChargeOffsetY" then
        g.shieldChargeOffsetY = clampNum(value, -40, 40, 0)
    elseif field == "hidden" then
        g.hidden = value and true or false
    elseif field == "move" then
        root.moving = value and true or false
        if root.moving then root:EnableMouse(true) else root:EnableMouse(false) end
        if not root.moving then root:StopMovingOrSizing() end
    end
    if IchaUI_CombatFrame then
        IchaUI_CombatFrame.moving = root.moving and true or false
        IchaUI_CombatFrame.hidden = g.hidden and true or false
        IchaUI_CombatFrame.portraitEnabled = g.portrait ~= false
        IchaUI_CombatFrame.portraitSide = (g.portraitSide == "right") and "right" or "left"
        IchaUI_CombatFrame.shieldChargeEnabled = g.shieldChargeEnabled ~= false
        IchaUI_CombatFrame.shieldChargeSpread = clampNum(g.shieldChargeSpread, 10, 360, 90)
        IchaUI_CombatFrame.shieldChargeSize = clampNum(g.shieldChargeSize, 6, 28, 10)
        IchaUI_CombatFrame.shieldChargeAngle = clampNum(g.shieldChargeAngle, -360, 360, 0)
        IchaUI_CombatFrame.shieldChargeReverse = g.shieldChargeReverse and true or false
        IchaUI_CombatFrame.shieldChargeOffsetX = clampNum(g.shieldChargeOffsetX, -40, 40, 0)
        IchaUI_CombatFrame.shieldChargeOffsetY = clampNum(g.shieldChargeOffsetY, -40, 40, 0)
        if g.badgeHost == "frame" or g.badgeHost == "portrait" then
            IchaUI_CombatFrame.badgeHost = g.badgeHost
        else
            IchaUI_CombatFrame.badgeHost = nil
        end
    end
    IchaUI_CombatLayout()
end

local function makeSlots(count)
    if not IchaUI_CreateUnitFrame then return end
    if not count or count < 1 then count = 1 end
    if count > MAX_CAP then count = MAX_CAP end
    local i
    for i = 1, count do
        if not slots[i] then
            local fr = IchaUI_CreateUnitFrame("combat" .. i, "none", {
                scale = 1,
                width = 200,
                height = 40,
                portrait = true,
                portraitScale = 1.22,
                portraitRing = 1.28,
            }, {
                parent = root,
                managedPos = true,
                portrait = true,
                portraitSide = "left",
            })
            slots[i] = fr
            if fr and fr.root then fr.root:Hide() end
        end
    end
end

local function unitGuid(unit)
    if IchaUI_Swing_Guid then
        local g = IchaUI_Swing_Guid(unit)
        if g and g ~= "" then return g end
    end
    if UnitExists then
        local ok, exists, guid = pcall(UnitExists, unit)
        if ok and exists and guid and guid ~= "" and guid ~= "0x0000000000000000" then
            return guid
        end
    end
    return nil
end

local function unitOk(unit)
    if not unit or unit == "" or unit == "none" or not UnitExists then return false end
    local ok, exists = pcall(UnitExists, unit)
    return (ok and exists) and true or false
end

local function safeName(unit)
    if not unit or unit == "" or unit == "none" or not UnitName then return nil end
    local ok, name = pcall(UnitName, unit)
    if not ok then return nil end
    return name
end

local function realGuid(unit)
    if not unitOk(unit) then return nil end
    local exists, guid = UnitExists(unit)
    if not exists or type(guid) ~= "string" or guid == "" then return nil end
    if not string.find(guid, "^0[xX]%x+$") then return nil end
    local gname = safeName(guid)
    local uname = safeName(unit)
    if not gname or gname == "" or gname ~= uname then return nil end
    if UnitIsUnit then
        local ok, same = pcall(UnitIsUnit, guid, unit)
        if ok and not same then return nil end
    end
    return guid
end

local function touchKey(unit)
    if not unit or unit == "" or unit == "none" then return nil end
    local name = safeName(unit)
    if not name or name == "" then return nil end
    local pname = safeName("player")
    if pname and name == pname then return nil end
    return realGuid(unit)
end

local function noteUnit(unit)
    if not unitOk(unit) then return end
    if UnitIsUnit then
        local ok, same = pcall(UnitIsUnit, unit, "player")
        if not ok or same then return end
    end
    local g = touchKey(unit)
    if not g then return end
    local now = GetTime()
    touchAt[g] = now
    if not firstSeen[g] then firstSeen[g] = now end
    local nm = safeName(unit)
    if nm and nm ~= "" then
        combatHold[g] = nm
    elseif not combatHold[g] then
        combatHold[g] = true
    end
end

local function hostileAlive(unit)
    if not unitOk(unit) then return false end
    if UnitIsUnit then
        local ok, same = pcall(UnitIsUnit, unit, "player")
        if not ok or same then return false end
    end
    if UnitIsDead then
        local ok, dead = pcall(UnitIsDead, unit)
        if not ok or dead then return false end
    end
    if UnitIsGhost then
        local ok, ghost = pcall(UnitIsGhost, unit)
        if ok and ghost then return false end
    end
    if UnitIsFriend then
        local ok, friend = pcall(UnitIsFriend, "player", unit)
        if not ok or friend then return false end
    end
    if UnitCanAttack then
        local ok, can = pcall(UnitCanAttack, "player", unit)
        if not ok or not can then return false end
    end
    return true
end

-- 1-8 if this hostile has a raid mark; nil otherwise. Unknown tokens throw.
local function raidMark(unit)
    if not GetRaidTargetIndex then return nil end
    if not unit or unit == "" or unit == "none" then return nil end
    local ok, idx = pcall(GetRaidTargetIndex, unit)
    if not ok then return nil end
    idx = tonumber(idx)
    if not idx or idx < 1 or idx > 8 then return nil end
    return idx
end

-- Player only (not pet). Used by combat-plate HP color (red on you / yellow off you).
local function targetsPlayer(unit)
    if not unit or unit == "" or unit == "none" or not UnitExists or not UnitIsUnit or not UnitName then return false end
    local tot
    if string.find(unit, "^nameplate") or string.find(unit, "^0[xX]") then
        local g = realGuid(unit)
        if not g then return false end
        tot = g .. "target"
    else
        tot = unit .. "target"
    end
    local ok, exists = pcall(UnitExists, tot)
    if not ok or not exists then return false end
    local okSame, same = pcall(UnitIsUnit, tot, "player")
    if not okSame or not same then return false end
    local okSelf, isSelf = pcall(UnitIsUnit, tot, unit)
    if okSelf and isSelf then return false end
    local pname = safeName("player")
    local tname = safeName(tot)
    if not pname or pname == "" or tname ~= pname then return false end
    return true
end
IchaUI_CombatTargetsPlayer = targetsPlayer

-- Who this unit is targeting: "me", "group" (party/raid member or pet, not me),
-- "other" (someone outside the group), "none" (no target), nil = cannot tell.
-- Does not check hostility or combat.
local function groupAggro(unit)
    if not unit or unit == "" or unit == "none" or type(unit) ~= "string" then return nil end
    if string.sub(unit, 1, 6) == "IchaUI" then return nil end
    if not UnitExists or not UnitIsUnit then return nil end
    if not unitOk(unit) then return nil end
    local tot
    if string.find(unit, "^nameplate") or string.find(unit, "^0[xX]") then
        local g = realGuid(unit)
        if not g then return nil end
        tot = g .. "target"
    else
        tot = unit .. "target"
    end
    local state = nil
    local ok = pcall(function()
        if not UnitExists(tot) then
            state = "none"
            return
        end
        if UnitIsUnit(tot, unit) then return end
        if UnitIsUnit(tot, "player") then
            state = "me"
            return
        end
        if UnitIsUnit(tot, "pet") then
            state = "group"
            return
        end
        if (UnitPlayerOrPetInParty and UnitPlayerOrPetInParty(tot))
            or (UnitPlayerOrPetInRaid and UnitPlayerOrPetInRaid(tot))
            or (UnitInParty and UnitInParty(tot))
            or (UnitInRaid and UnitInRaid(tot)) then
            state = "group"
            return
        end
        local i
        for i = 1, 4 do
            if UnitIsUnit(tot, "party" .. i) or UnitIsUnit(tot, "partypet" .. i) then
                state = "group"
                return
            end
        end
        state = "other"
    end)
    if not ok then return nil end
    return state
end
IchaUI_CombatGroupAggro = groupAggro

local function onGroupFighting(unit)
    if groupAggro(unit) ~= "group" then return false end
    if UnitAffectingCombat then
        local combat = false
        local ok = pcall(function()
            if UnitAffectingCombat(unit) then combat = true end
        end)
        if not ok or not combat then return false end
    end
    return true
end

-- true = target is the player, false = readable and not the player, nil = cannot tell.
-- Invalid tokens return nil and do not call Unit*.
local function shapedToken(unit)
    if not unit or unit == "" or unit == "none" then return false end
    if type(unit) ~= "string" then return false end
    if string.sub(unit, 1, 6) == "IchaUI" then return false end
    if string.find(unit, "^0[xX]%x+$") then return true end
    if string.find(unit, "^nameplate%d+$") then return true end
    if unit == "target" or unit == "pettarget" then return true end
    if string.find(unit, "^party[1-4]target$") then return true end
    if string.find(unit, "^raid%d+target$") then return true end
    return false
end

local function targetOfPlayer(unit)
    if not shapedToken(unit) then return nil end
    if not UnitExists or not UnitIsUnit then return nil end
    local unitLive = false
    local okU = pcall(function()
        if UnitExists(unit) then unitLive = true end
    end)
    if not okU or not unitLive then return nil end
    local tot
    if string.find(unit, "^nameplate") or string.find(unit, "^0[xX]") then
        local g = realGuid(unit)
        if not g then return nil end
        tot = g .. "target"
    else
        tot = unit .. "target"
    end
    local totLive = false
    local okT = pcall(function()
        if UnitExists(tot) then totLive = true end
    end)
    if not okT then return nil end
    if not totLive then return false end
    local same = false
    local okS = pcall(function()
        if UnitIsUnit(tot, "player") then same = true end
    end)
    if not okS then return nil end
    if not same then return false end
    local isSelf = false
    local okSelf = pcall(function()
        if UnitIsUnit(tot, unit) then isSelf = true end
    end)
    if okSelf and isSelf then return nil end
    local pname = safeName("player")
    local tname = safeName(tot)
    if not pname or pname == "" or tname ~= pname then return nil end
    return true
end
IchaUI_CombatTargetOfPlayer = targetOfPlayer

local function wantsUnit(unit, inCombat)
    if not hostileAlive(unit) then return false end
    if raidMark(unit) then return true end
    if targetsPlayer(unit) then
        local fighting = true
        if UnitAffectingCombat then
            local ok, combat = pcall(UnitAffectingCombat, unit)
            if ok then fighting = combat and true or false end
        end
        if fighting then return true end
    end
    if onGroupFighting(unit) then return true end
    if inCombat then
        local g = touchKey(unit)
        local t = g and touchAt[g]
        if t and (GetTime() - t) <= TOUCH_SEC then return true end
    end
    return false
end

local function consider(unit, inCombat, seen)
    if not wantsUnit(unit, inCombat) then return end
    local g = touchKey(unit)
    if not g then return end
    if seen[g] then return end
    seen[g] = realGuid(unit) or unit
    if not firstSeen[g] then firstSeen[g] = GetTime() end
    markOf[g] = raidMark(unit)
    local n = table.getn(order) + 1
    order[n] = g
end

-- GUID string ascending. Missing GUIDs stay after those rows, in their previous relative order.
local function sortOrder(seen, prevList)
    local function keyIsGuid(g)
        if not g or g == "" then return false end
        local s = tostring(g)
        if not string.find(s, "^0[xX]%x+$") then return false end
        return true
    end
    local guids = {}
    local ng = 0
    local others = {}
    local no = 0
    local inOther = {}
    local n = table.getn(order)
    local i
    for i = 1, n do
        local g = order[i]
        if g then
            if keyIsGuid(g) then
                ng = ng + 1
                guids[ng] = g
            elseif not inOther[g] then
                no = no + 1
                others[no] = g
                inOther[g] = true
            end
        end
    end
    local a, b
    for a = 1, ng do
        for b = a + 1, ng do
            local sa = tostring(guids[a])
            local sb = tostring(guids[b])
            if sb < sa then
                local tmp = guids[a]
                guids[a] = guids[b]
                guids[b] = tmp
            end
        end
    end
    local stable = {}
    local ns = 0
    local used = {}
    local pn = 0
    if type(prevList) == "table" then pn = table.getn(prevList) end
    local p
    for p = 1, pn do
        local g = prevList[p]
        if g and inOther[g] and not used[g] then
            ns = ns + 1
            stable[ns] = g
            used[g] = true
        end
    end
    for i = 1, no do
        local g = others[i]
        if not used[g] then
            ns = ns + 1
            stable[ns] = g
            used[g] = true
        end
    end
    local out = {}
    local outN = 0
    for i = 1, ng do
        outN = outN + 1
        out[outN] = guids[i]
    end
    for i = 1, ns do
        outN = outN + 1
        out[outN] = stable[i]
    end
    order = out
end

-- SuperWoW GUID token still resolves, or throws when the plate is gone.
local function guidLive(guid)
    if not guid or type(guid) ~= "string" then return false end
    if not string.find(guid, "^0[xX]%x+$") then return false end
    if type(UnitExists) ~= "function" then return false end
    local exists = false
    local ok = pcall(function()
        if UnitExists(guid) then exists = true end
    end)
    return ok and exists and true or false
end

-- Row stays painted: GUID is a combat-with-me hold and no longer a live unit.
local function holdFrozen(token)
    if not token or token == "" or token == "none" then return false end
    if type(token) ~= "string" then return false end
    if not string.find(token, "^0[xX]%x+$") then return false end
    if not combatHold[token] then return false end
    if guidLive(token) then return false end
    return true
end

local function tabTokenForGuid(g)
    if not shapedToken(g) then return nil end
    if not string.find(g, "^0[xX]%x+$") then return nil end
    if guidLive(g) then return g end
    local function consider(u)
        if not shapedToken(u) then return nil end
        if not unitOk(u) then return nil end
        if u == g then return u end
        local ug = unitGuid(u)
        if ug == g then return u end
        return nil
    end
    local i
    for i = 1, MAX_CAP do
        local fr = slots[i]
        local hit = fr and consider(fr.unit)
        if hit then return hit end
    end
    local hit = consider("target")
    if hit then return hit end
    hit = consider("pettarget")
    if hit then return hit end
    for i = 1, 4 do
        hit = consider("party" .. i .. "target")
        if hit then return hit end
    end
    for i = 1, 40 do
        hit = consider("nameplate" .. i)
        if hit then return hit end
    end
    return nil
end

local function tabLife(token)
    if not shapedToken(token) then return nil end
    local state = nil
    local ok = pcall(function()
        if not UnitExists(token) then return end
        if UnitIsDead and UnitIsDead(token) then
            state = "dead"
            return
        end
        if UnitIsGhost and UnitIsGhost(token) then
            state = "dead"
            return
        end
        if UnitHealth then
            local hp = UnitHealth(token)
            if hp and hp <= 0 then
                state = "dead"
                return
            end
            if hp and hp > 0 then
                state = "alive"
                return
            end
        end
        state = "alive"
    end)
    if not ok then return nil end
    return state
end

local function noteSmartTabDeaths(prevOrder, pn)
    if not IchaUI_SmartTabNoteUnit then return end
    local function mark(g, removed)
        if not g or g == "" then return end
        local token = tabTokenForGuid(g)
        local life = tabLife(token)
        if life == "dead" then
            IchaUI_SmartTabNoteUnit(g, true)
        elseif life == "alive" and not removed then
            IchaUI_SmartTabNoteUnit(g, false)
        end
    end
    local i
    for i = 1, table.getn(order) do
        mark(order[i], false)
    end
    if not prevOrder or not pn then return end
    for i = 1, pn do
        local g = prevOrder[i]
        local still = false
        if g then
            local j
            for j = 1, table.getn(order) do
                if order[j] == g then still = true end
            end
            if not still then mark(g, true) end
        end
    end
end

function IchaUI_CombatTabRows()
    local rows = {}
    local n = 0
    local i
    for i = 1, table.getn(order) do
        local g = order[i]
        local token = tabTokenForGuid(g)
        if token then
            n = n + 1
            rows[n] = { guid = g, token = token }
        end
    end
    return rows
end

function IchaUI_CombatRefresh()
    makeSlots()
    local inCombat = UnitAffectingCombat and UnitAffectingCombat("player")
    if not inCombat then
        touchAt = {}
        combatHold = {}
        combatOnMe = {}
    end
    local seen = {}
    local hadRow = {}
    local prevOrder = {}
    local pn = 0
    local k
    for k = 1, table.getn(order) do
        if order[k] then
            hadRow[order[k]] = true
            pn = pn + 1
            prevOrder[pn] = order[k]
        end
        order[k] = nil
    end
    markOf = {}
    local prevKeep = markedKeep
    local function stillFighting(unit)
        if not hostileAlive(unit) then return false end
        if targetsPlayer(unit) then
            local fighting = true
            if UnitAffectingCombat then
                local combat = false
                local ok = pcall(function()
                    if UnitAffectingCombat(unit) then combat = true end
                end)
                if ok then fighting = combat and true or false end
            end
            if fighting then return true end
        end
        if onGroupFighting(unit) then return true end
        if inCombat then
            local gk = touchKey(unit)
            local t = gk and touchAt[gk]
            if t and (GetTime() - t) <= TOUCH_SEC then return true end
        end
        return false
    end
    local function watch(unit)
        if not unitOk(unit) then return end
        if inCombat and targetsPlayer(unit) then noteUnit(unit) end
        local g = touchKey(unit)
        if g then
            if inCombat and targetsPlayer(unit) then combatOnMe[g] = true end
            if stillFighting(unit) then
                local nm = safeName(unit)
                if nm and nm ~= "" then
                    combatHold[g] = nm
                elseif not combatHold[g] then
                    combatHold[g] = true
                end
            else
                combatHold[g] = nil
                combatOnMe[g] = nil
            end
        end
        consider(unit, inCombat, seen)
    end
    watch("target")
    watch("pettarget")
    local i
    for i = 1, 4 do
        watch("party" .. i .. "target")
    end
    local raidN = 0
    if GetNumRaidMembers then raidN = GetNumRaidMembers() or 0 end
    if raidN > 0 then
        local now = GetTime()
        if now - (raidSweep.at or 0) >= 0.5 then
            raidSweep.at = now
            raidSweep.guids = {}
            for i = 1, raidN do
                local u = "raid" .. i .. "target"
                if unitOk(u) then
                    local rg = touchKey(u)
                    if rg and not seen[rg] then
                        watch(u)
                        if seen[rg] then raidSweep.guids[rg] = true end
                    end
                end
            end
        else
            local rg
            for rg in pairs(raidSweep.guids) do
                if not seen[rg] then watch(rg) end
            end
        end
    else
        raidSweep.guids = {}
    end
    local foundPlate = false
    for i = 1, 40 do
        local plate = "nameplate" .. i
        if unitOk(plate) then
            foundPlate = true
            watch(plate)
        end
    end
    if not foundPlate and C_NamePlate and C_NamePlate.GetNamePlateGUIDs then
        local ok, guids = pcall(C_NamePlate.GetNamePlateGUIDs)
        if ok and type(guids) == "table" then
            local gi
            for gi = 1, table.getn(guids) do
                local guid = guids[gi]
                if guid and guid ~= "" then watch(guid) end
            end
        end
    end
    local pg
    for pg in pairs(prevKeep) do
        if pg and not seen[pg] then
            watch(pg)
        end
    end
    if inCombat then
        local pending = {}
        local npend = 0
        local hg
        for hg in pairs(combatHold) do
            if hg and not seen[hg] and string.find(hg, "^0[xX]%x+$") then
                npend = npend + 1
                pending[npend] = hg
            end
        end
        local pi
        for pi = 1, npend do
            local g = pending[pi]
            if guidLive(g) then
                watch(g)
                if not seen[g] then
                    combatHold[g] = nil
                    combatOnMe[g] = nil
                end
            elseif hadRow[g] then
                local keep = combatOnMe[g]
                if not keep then
                    local t = touchAt[g]
                    keep = t and (GetTime() - t) <= TOUCH_SEC
                end
                if keep then
                    seen[g] = g
                    if not firstSeen[g] then firstSeen[g] = GetTime() end
                    order[table.getn(order) + 1] = g
                else
                    combatHold[g] = nil
                    combatOnMe[g] = nil
                end
            end
        end
    end
    local kept = {}
    local oi
    for oi = 1, table.getn(order) do
        local g = order[oi]
        if seen[g] then
            kept[table.getn(kept) + 1] = g
        end
    end
    order = kept
    sortOrder(seen, prevOrder)
    local mk = {}
    for oi = 1, table.getn(order) do
        local g = order[oi]
        if markOf[g] then mk[g] = true end
    end
    markedKeep = mk
    if not inCombat then
        local keepFS = {}
        for oi = 1, table.getn(order) do
            local g = order[oi]
            keepFS[g] = firstSeen[g]
        end
        firstSeen = keepFS
    end
    noteSmartTabDeaths(prevOrder, pn)
    return seen
end

function IchaUI_CombatLayout()
    local cols, rows, cap = gridLimits()
    makeSlots(cap)
    local g = IchaUI_CombatProfile()
    IchaUI_CombatPlaceRoot()
    local testing = IchaUIUF_GetTestMode and IchaUIUF_GetTestMode()
    local seen = {}
    if not testing then
        seen = IchaUI_CombatRefresh() or {}
    end
    local visW = clampNum(g.width, 1, 600, 200) * clampNum(g.scale, 0.4, 3, 1)
    local visH = clampNum(g.height, 1, 420, 40) * clampNum(g.scale, 0.4, 3, 1)
    local gap = clampNum(g.pad, 0, 24, 4)
    local overhang = 0
    local puff = 0
    if g.portrait ~= false then
        local psc = clampNum(g.portraitScale, 0.8, 2.5, 1.22)
        overhang = visH * psc * 0.7
        puff = visH * ((psc - 1) * 0.5)
        if puff < 0 then puff = 0 end
    end
    local stepX = visW + gap + overhang
    local stepY = visH + gap + puff
    local shown = 0
    local i
    for i = 1, MAX_CAP do
        local fr = slots[i]
        if fr and fr.root then
            local token = nil
            if i <= cap and not testing and not g.hidden then
                local gkey = order[i]
                if gkey then token = seen[gkey] end
            end
            if not token and i <= cap and (testing or root.moving) and not (g.hidden and not testing) then
                token = "none"
            end
            if token and fr.SetUnit then
                fr._forcePreview = (token == "none") and true or false
                local frozen = (not testing) and holdFrozen(token)
                fr._holdMissing = frozen and true or false
                if fr.unit ~= token then
                    fr:SetUnit(token)
                    fr._casting = false
                    fr._castLocked = false
                    fr._castLockExpire = 0
                    fr._interruptedUntil = 0
                    if IchaUI_Cast_HidePieces then IchaUI_Cast_HidePieces(fr) end
                end
                pushLook(fr)
                local col = math.mod(i - 1, cols)
                local row = math.floor((i - 1) / cols)
                fr.root:ClearAllPoints()
                fr.root:SetPoint("TOPLEFT", root, "TOPLEFT", col * stepX, -(row * stepY))
                if fr.applySize then fr:applySize() end
                if not frozen and fr.update then fr:update() end
                fr.root:Show()
                shown = shown + 1
            else
                fr._holdMissing = false
                if fr.SetUnit then fr:SetUnit("none") end
                if IchaUI_Swing_Hide then IchaUI_Swing_Hide(fr) end
                if fr.root then fr.root:Hide() end
                if fr.portraitFrame then fr.portraitFrame:Hide() end
                if fr.portraitRingFrame then fr.portraitRingFrame:Hide() end
                if fr.portraitRingTex then fr.portraitRingTex:Hide() end
                if fr.combatBadge then fr.combatBadge:Hide() end
                if fr.combatIcon then fr.combatIcon:Hide() end
                if fr.levelText then fr.levelText:Hide() end
                if fr.hideShieldCharges then fr:hideShieldCharges() end
                if fr.hpLevel then fr.hpLevel:Hide() end
                if IchaUI_HideUnitRaidMark then IchaUI_HideUnitRaidMark(fr) end
                if IchaUI_HideUnitRoleIcons then IchaUI_HideUnitRoleIcons(fr) end
                fr._portraitChromeOn = false
                fr._forcePreview = false
            end
        end
    end
    local usedRows = 1
    if shown > 0 then
        usedRows = math.floor((shown + cols - 1) / cols)
    end
    local gridW = cols * visW + math.max(0, cols - 1) * (gap + overhang)
    local gridH = usedRows * visH + math.max(0, usedRows - 1) * (gap + puff)
    if shown < 1 and root.moving then
        gridW = cols * visW
        gridH = rows * visH
    end
    root:SetWidth(math.max(gridW, 8))
    root:SetHeight(math.max(gridH, 1))
    if shown > 0 or root.moving then
        root:Show()
    else
        root:Hide()
    end
    if root.moving then
        dragCover:ClearAllPoints()
        dragCover:SetAllPoints(root)
        dragCover:Show()
        title:Show()
    else
        dragCover:Hide()
        title:Hide()
    end
end

local facade = {
    key = "combat",
    hasPortrait = true,
}
facade.root = root
function facade:applySize()
    IchaUI_CombatLayout()
end
function facade:update()
    IchaUI_CombatLayout()
end
function facade:setMove(on)
    root.moving = on and true or false
    root:EnableMouse(root.moving and true or false)
    if not root.moving then root:StopMovingOrSizing() end
    IchaUI_CombatLayout()
end

setmetatable(facade, { __index = function(_, field)
    local g = IchaUI_CombatProfile()
    if field == "scale" then return g.scale end
    if field == "width" then return g.width end
    if field == "height" then return g.height end
    if field == "pad" then return g.pad end
    if field == "portraitEnabled" then return g.portrait ~= false end
    if field == "portraitScale" then return g.portraitScale end
    if field == "portraitRing" then return g.portraitRing end
    if field == "portraitOffsetX" then return g.portraitOffsetX end
    if field == "portraitOffsetY" then return g.portraitOffsetY end
    if field == "portraitSide" then return (g.portraitSide == "right") and "right" or "left" end
    if field == "badgeAngle" then return g.badgeAngle end
    if field == "badgeScale" then return g.badgeScale end
    if field == "badgeOffsetX" then return g.badgeOffsetX end
    if field == "badgeOffsetY" then return g.badgeOffsetY end
    if field == "badgeHost" then
        if g.badgeHost == "frame" or g.badgeHost == "portrait" then return g.badgeHost end
        return nil
    end
    if field == "shieldChargeEnabled" then return g.shieldChargeEnabled ~= false end
    if field == "shieldChargeSpread" then return g.shieldChargeSpread end
    if field == "shieldChargeSize" then return g.shieldChargeSize end
    if field == "shieldChargeAngle" then return g.shieldChargeAngle end
    if field == "shieldChargeReverse" then return g.shieldChargeReverse and true or false end
    if field == "shieldChargeOffsetX" then return g.shieldChargeOffsetX end
    if field == "shieldChargeOffsetY" then return g.shieldChargeOffsetY end
    if field == "cols" then return g.cols end
    if field == "rows" then return g.rows end
    if field == "hidden" then return g.hidden and true or false end
    if field == "moving" then return root.moving and true or false end
    return nil
end })

facade.moving = false
facade.hidden = false
facade.portraitEnabled = true
facade.portraitSide = "left"
IchaUI_CombatFrame = facade
do
    local g = IchaUI_CombatProfile()
    facade.hidden = g.hidden and true or false
    facade.portraitEnabled = g.portrait ~= false
    facade.portraitSide = (g.portraitSide == "right") and "right" or "left"
end
IchaUI_CombatSlots = slots

local function nameInMsg(msg, unit)
    if not msg or not unit or not unitOk(unit) then return false end
    if not UnitName then return false end
    local name = safeName(unit)
    if not name or name == "" then return false end
    local n = string.len(name)
    local m = string.len(msg)
    if n > m then return false end
    local i
    for i = 1, (m - n + 1) do
        if string.sub(msg, i, i + n - 1) == name then
            local prev = " "
            if i > 1 then prev = string.sub(msg, i - 1, i - 1) end
            local nxt = string.sub(msg, i + n, i + n)
            local prevOk = (prev == " " or prev == "")
            local nextOk = (nxt == "" or nxt == " " or nxt == "'" or nxt == "." or nxt == "!" or nxt == ",")
            if prevOk and nextOk then return true end
        end
    end
    return false
end

local function msgHasName(msg, name)
    if not msg or not name or name == "" then return false end
    local n = string.len(name)
    local m = string.len(msg)
    if n > m then return false end
    local i
    for i = 1, (m - n + 1) do
        if string.sub(msg, i, i + n - 1) == name then
            local prev = " "
            if i > 1 then prev = string.sub(msg, i - 1, i - 1) end
            local nxt = string.sub(msg, i + n, i + n)
            local prevOk = (prev == " " or prev == "")
            local nextOk = (nxt == "" or nxt == " " or nxt == "'" or nxt == "." or nxt == "!" or nxt == ",")
            if prevOk and nextOk then return true end
        end
    end
    return false
end

local function mentionsUs(msg)
    if not msg or msg == "" then return false end
    if string.find(msg, " you") or string.find(msg, " You") then return true end
    if string.find(msg, "Your ") or string.find(msg, " your ") then return true end
    if string.find(msg, "Totem") or string.find(msg, "Earthbind") then return true end
    return false
end

local function personalLog()
    if not event then return false end
    if string.find(event, "SELF") then return true end
    if string.find(event, "PET") then return true end
    return false
end

local function touchNamedIn(msg)
    if not msg or msg == "" then return end
    if not personalLog() and not mentionsUs(msg) then return end
    local names = {}
    local buckets = {}
    local seenKey = {}
    local function add(unit)
        if not unitOk(unit) or not hostileAlive(unit) then return end
        if not nameInMsg(msg, unit) then return end
        local name = safeName(unit)
        local key = touchKey(unit)
        if not name or name == "" or not key then return end
        if seenKey[key] then return end
        seenKey[key] = true
        local bucket = buckets[name]
        if not bucket then
            bucket = {}
            buckets[name] = bucket
            table.insert(names, name)
        end
        bucket[table.getn(bucket) + 1] = unit
    end
    local function confirmed(unit)
        if targetsPlayer(unit) then return true end
        if UnitIsUnit and unitOk("target") then
            local ok, same = pcall(UnitIsUnit, unit, "target")
            if ok and same then return true end
        end
        if UnitIsUnit and unitOk("pettarget") then
            local ok, same = pcall(UnitIsUnit, unit, "pettarget")
            if ok and same then return true end
        end
        return false
    end
    add("target")
    local i
    for i = 1, 4 do
        add("party" .. i .. "target")
    end
    add("pettarget")
    if C_NamePlate and C_NamePlate.GetNamePlateGUIDs then
        local ok, guids = pcall(C_NamePlate.GetNamePlateGUIDs)
        if ok and type(guids) == "table" then
            local gi
            for gi = 1, table.getn(guids) do
                local guid = guids[gi]
                if guid and guid ~= "" then add(guid) end
            end
        end
    end
    local n
    for n = 1, 40 do
        add("nameplate" .. n)
    end
    local ni
    for ni = 1, table.getn(names) do
        local bucket = buckets[names[ni]]
        local count = table.getn(bucket)
        if count == 1 then
            noteUnit(bucket[1])
        else
            local bi
            for bi = 1, count do
                if confirmed(bucket[bi]) then noteUnit(bucket[bi]) end
            end
        end
    end
end

local scan = CreateFrame("Frame", "IchaUICombatScan", UIParent)
scan.elapsed = 0
scan:RegisterEvent("PLAYER_REGEN_DISABLED")
scan:RegisterEvent("PLAYER_REGEN_ENABLED")
scan:RegisterEvent("PLAYER_TARGET_CHANGED")
scan:RegisterEvent("UNIT_TARGET")
scan:RegisterEvent("RAID_TARGET_UPDATE")
scan:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
scan:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
scan:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
scan:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
scan:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
scan:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
scan:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS")
scan:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
scan:RegisterEvent("CHAT_MSG_COMBAT_PET_HITS")
scan:RegisterEvent("CHAT_MSG_COMBAT_PET_MISSES")
scan:RegisterEvent("CHAT_MSG_SPELL_PET_DAMAGE")
scan:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
scan:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
scan:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")
scan:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_DEATH")
scan:RegisterEvent("UNIT_AURA")
scan:RegisterEvent("PLAYER_AURAS_CHANGED")
pcall(function() scan:RegisterEvent("PLAYER_AURA") end)
scan:SetScript("OnEvent", function()
    if event == "UNIT_AURA" or event == "PLAYER_AURAS_CHANGED" or event == "PLAYER_AURA" then
        local who = arg1
        if event ~= "UNIT_AURA" or not who or who == "" then
            who = "player"
        end
        -- Shield charge circles are player-frame only. Combat rows never paint them.
        if IchaUIUF_PaintShieldCharges then
            if who == "player" then
                IchaUIUF_PaintShieldCharges("player")
            elseif type(who) == "string" and who ~= "none"
                and string.sub(who, 1, 6) ~= "IchaUI"
                and string.sub(who, 1, 9) ~= "nameplate"
                and (string.find(who, "^0[xX]%x+$") or string.find(who, "^[a-z]+%d*$"))
                and UnitIsUnit then
                local ok, same = pcall(UnitIsUnit, "player", who)
                if ok and same then
                    IchaUIUF_PaintShieldCharges("player")
                end
            end
        end
        return
    end
    if event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" or event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_DEATH" then
        local msg = arg1
        if msg and msg ~= "" then
            local hitG = nil
            local hits = 0
            local hg, hv
            for hg, hv in pairs(combatHold) do
                if type(hv) == "string" and msgHasName(msg, hv) then
                    hits = hits + 1
                    hitG = hg
                end
            end
            if hits >= 1 and IchaUI_SmartTabReset then
                IchaUI_SmartTabReset()
            end
            if hits == 1 and hitG then
                combatHold[hitG] = nil
                combatOnMe[hitG] = nil
                touchAt[hitG] = nil
                IchaUI_CombatLayout()
            end
        end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        touchAt = {}
        combatHold = {}
        combatOnMe = {}
        IchaUI_CombatLayout()
        return
    end
    if event == "PLAYER_TARGET_CHANGED" or event == "UNIT_TARGET" or event == "PLAYER_REGEN_DISABLED" or event == "RAID_TARGET_UPDATE" then
        IchaUI_CombatLayout()
        return
    end
    if arg1 and arg1 ~= "" then
        touchNamedIn(arg1)
    end
end)
scan:SetScript("OnUpdate", function()
    this.elapsed = (this.elapsed or 0) + (arg1 or 0)
    if this.elapsed < 0.2 then return end
    this.elapsed = 0
    if root.dragging then return end
    local testing = IchaUIUF_GetTestMode and IchaUIUF_GetTestMode()
    if testing then return end
    local before = ""
    local i
    for i = 1, MAX_CAP do
        before = before .. tostring(order[i] or "") .. "|"
    end
    IchaUI_CombatRefresh()
    local after = ""
    for i = 1, MAX_CAP do
        after = after .. tostring(order[i] or "") .. "|"
    end
    if after ~= before then
        IchaUI_CombatLayout()
    else
        for i = 1, MAX_CAP do
            local fr = slots[i]
            if fr and fr.root and fr.root:IsShown() and fr.update then
                if holdFrozen(fr.unit) then
                    fr._holdMissing = true
                else
                    fr._holdMissing = false
                    fr:update()
                end
            end
        end
    end
end)

IchaUI_CombatPlaceRoot()
makeSlots()
IchaUI_CombatLayout()
