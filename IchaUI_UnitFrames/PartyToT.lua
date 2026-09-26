-- Party target frames: one mini ToT-style frame per party member (party1target..party4target).
-- SuperWoW / ClassicAPI expose partyNtarget on this 1.12 client (Focus.lua already uses it).
-- Also speeds player ToT show/hide: identity-only polls miss the first UnitExists tick.

if type(IchaUI_CreateUnitFrame) ~= "function" then return end

local slots = {}
local lastStamp = { false, false, false, false }
local lastTotStamp = nil
local burstLeft = 0
local GAP = 6

local function clamp(v, lo, hi)
    v = tonumber(v)
    if not v then return lo end
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function uf()
    if not IchaUIDB then IchaUIDB = {} end
    if type(IchaUIDB.uf) ~= "table" then IchaUIDB.uf = {} end
    return IchaUIDB.uf
end

local function validAnchor(a)
    if a == "LEFT" or a == "TOP" or a == "BOTTOM" then return a end
    return "RIGHT"
end

local function partyToTDb()
    local d = uf()
    if type(d.partytot) ~= "table" then d.partytot = {} end
    local p = d.partytot
    if p.scale == nil then p.scale = 1 end
    if p.width == nil then p.width = 106 end
    if p.height == nil then p.height = 48 end
    if p.hidden == nil then p.hidden = false end
    if p.x == nil then p.x = 0 end
    if p.y == nil then p.y = 0 end
    p.anchor = validAnchor(p.anchor)
    p.scale = clamp(p.scale, 0.4, 3)
    p.width = clamp(p.width, 1, 600)
    p.height = clamp(p.height, 1, 420)
    p.x = clamp(p.x, -200, 200)
    p.y = clamp(p.y, -200, 200)
    return p
end

local function saveDb()
    local d = uf()
    d.partytot = partyToTDb()
    IchaUIDB.uf = d
end

local function unitLive(unit)
    if IchaUI_LEAVING then return false end
    if not unit or type(UnitExists) ~= "function" then return false end
    local exists = false
    pcall(function()
        if UnitExists(unit) then exists = true end
    end)
    return exists
end

local function unitStamp(unit)
    if not unitLive(unit) then return false end
    local name, guid, hp, mp = "", "", 0, 0
    pcall(function()
        if UnitName then name = UnitName(unit) or "" end
        if IchaUI_Swing_Guid then guid = IchaUI_Swing_Guid(unit) or "" end
        if UnitHealth then hp = tonumber(UnitHealth(unit)) or 0 end
        if UnitMana then mp = tonumber(UnitMana(unit)) or 0 end
    end)
    return name .. ":" .. guid .. ":" .. tostring(hp) .. ":" .. tostring(mp)
end

local function frameShown(fr)
    return fr and fr.root and fr.root.IsShown and fr.root:IsShown()
end

local function hostFrame(i)
    if type(IchaUIUF_Get) ~= "function" then return nil end
    return IchaUIUF_Get("party" .. i)
end

local function testingParty()
    if type(IchaUIUF_GetTestMode) ~= "function" or not IchaUIUF_GetTestMode() then
        return false
    end
    if type(IchaUIUF_GetTestParty) == "function" and not IchaUIUF_GetTestParty() then
        return false
    end
    return true
end

local function shouldShow(i)
    local p = partyToTDb()
    if p.hidden then return false end
    local host = hostFrame(i)
    if not host or not host.root or not host.root:IsShown() then return false end
    if testingParty() then return true end
    if not unitLive("party" .. i) then return false end
    return unitLive("party" .. i .. "target")
end

local function applySlotSize(fr)
    if not fr then return end
    local p = partyToTDb()
    fr.scale = p.scale
    fr.width = p.width
    fr.height = p.height
    fr.hidden = p.hidden and true or false
    if fr.hasPortrait then
        if p.portrait ~= nil then fr.portraitEnabled = p.portrait and true or false end
        if p.portraitScale ~= nil then fr.portraitScale = p.portraitScale end
        if p.portraitRing ~= nil then fr.portraitRing = p.portraitRing end
        if p.portraitOffsetX ~= nil then fr.portraitOffsetX = p.portraitOffsetX end
        if p.portraitOffsetY ~= nil then fr.portraitOffsetY = p.portraitOffsetY end
        if p.badgeScale ~= nil then fr.badgeScale = p.badgeScale end
        if p.badgeOffsetX ~= nil then fr.badgeOffsetX = p.badgeOffsetX end
        if p.badgeOffsetY ~= nil then fr.badgeOffsetY = p.badgeOffsetY end
        if p.badgeAngle ~= nil then fr.badgeAngle = p.badgeAngle end
        if p.badgeHost == "frame" or p.badgeHost == "portrait" then
            fr.badgeHost = p.badgeHost
        end
        if p.shieldChargeEnabled ~= nil then
            fr.shieldChargeEnabled = p.shieldChargeEnabled and true or false
        end
        if p.shieldChargeSpread ~= nil then fr.shieldChargeSpread = p.shieldChargeSpread end
        if p.shieldChargeSize ~= nil then fr.shieldChargeSize = p.shieldChargeSize end
        if p.shieldChargeAngle ~= nil then fr.shieldChargeAngle = p.shieldChargeAngle end
        if p.shieldChargeReverse ~= nil then
            fr.shieldChargeReverse = p.shieldChargeReverse and true or false
        end
        if p.shieldChargeOffsetX ~= nil then fr.shieldChargeOffsetX = p.shieldChargeOffsetX end
        if p.shieldChargeOffsetY ~= nil then fr.shieldChargeOffsetY = p.shieldChargeOffsetY end
    end
    if fr.applySize then fr:applySize() end
end

local function anchorOne(i)
    local fr = slots[i]
    local host = hostFrame(i)
    if not fr or not fr.root or not host or not host.root then return end
    local p = partyToTDb()
    local ox = tonumber(p.x) or 0
    local oy = tonumber(p.y) or 0
    local myPt, hostPt, dx, dy = "LEFT", "RIGHT", GAP + ox, oy
    if p.anchor == "LEFT" then
        myPt, hostPt, dx, dy = "RIGHT", "LEFT", -GAP + ox, oy
    elseif p.anchor == "TOP" then
        myPt, hostPt, dx, dy = "BOTTOM", "TOP", ox, GAP + oy
    elseif p.anchor == "BOTTOM" then
        myPt, hostPt, dx, dy = "TOP", "BOTTOM", ox, -GAP + oy
    end
    fr.root:ClearAllPoints()
    fr.root:SetPoint(myPt, host.root, hostPt, dx, dy)
end

local function hideChrome(fr)
    if not fr then return end
    if fr.root then fr.root:Hide() end
    if type(IchaUIUF_HidePreviewChrome) == "function" then
        IchaUIUF_HidePreviewChrome(fr)
    else
        if fr.portraitRingFrame then fr.portraitRingFrame:Hide() end
        if fr.portraitRingTex then fr.portraitRingTex:Hide() end
        if fr.combatBadge then fr.combatBadge:Hide() end
        if fr.castFrame then fr.castFrame:Hide() end
        if IchaUI_HideUnitRaidMark then IchaUI_HideUnitRaidMark(fr) end
        if IchaUI_HideUnitRoleIcons then IchaUI_HideUnitRoleIcons(fr) end
    end
end

local function paintOne(i, force)
    local fr = slots[i]
    if not fr then return end
    if not shouldShow(i) then
        lastStamp[i] = false
        hideChrome(fr)
        return
    end
    local stamp = unitStamp("party" .. i .. "target")
    if (not force) and stamp == lastStamp[i] and frameShown(fr) then
        if fr.updateCast then fr:updateCast() end
        if IchaUI_Swing_Update then IchaUI_Swing_Update(fr) end
        return
    end
    lastStamp[i] = stamp
    anchorOne(i)
    if fr.update then fr:update() end
end

function IchaUIUF_LayoutPartyToT()
    local i
    for i = 1, 4 do
        applySlotSize(slots[i])
        paintOne(i, true)
    end
end

function IchaUIUF_ApplyPartyToTSaved()
    IchaUIUF_LayoutPartyToT()
end

function IchaUIUF_PartyToTGet()
    local p = partyToTDb()
    local fr = slots[1]
    local portOn, psc, pring, pox, poy = false, 1.05, 1, 0, 0
    local bsc, box, boy, bang, bhost = 1, 0, 0, 0, nil
    if fr then
        portOn = fr.portraitEnabled and true or false
        psc = fr.portraitScale or psc
        pring = fr.portraitRing or pring
        pox = fr.portraitOffsetX or 0
        poy = fr.portraitOffsetY or 0
        bsc = fr.badgeScale or 1
        box = fr.badgeOffsetX or 0
        boy = fr.badgeOffsetY or 0
        bang = fr.badgeAngle or 0
        bhost = fr.badgeHost
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
    return {
        scale = p.scale,
        width = p.width,
        height = p.height,
        hidden = p.hidden and true or false,
        moving = false,
        x = p.x,
        y = p.y,
        anchor = p.anchor,
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
    }
end

function IchaUIUF_PartyToTSet(field, value)
    local p = partyToTDb()
    if field == "scale" then
        local oldSc = tonumber(p.scale) or 1
        p.scale = clamp(tonumber(value) or p.scale, 0.4, 3)
        if not IchaUI_BarSkipRefit and IchaUIUF_ScaleSavedBars then
            IchaUIUF_ScaleSavedBars("partytot", oldSc, p.scale)
        end
    elseif field == "width" then
        p.width = clamp(tonumber(value) or p.width, 1, 600)
    elseif field == "height" then
        p.height = clamp(tonumber(value) or p.height, 1, 420)
        if not IchaUI_BarSkipRefit and IchaUIUF_RefitBarsToHeight then
            IchaUIUF_RefitBarsToHeight("partytot", p.height, p.scale)
        end
    elseif field == "hidden" then
        p.hidden = value and true or false
    elseif field == "anchor" then
        p.anchor = validAnchor(value)
    elseif field == "x" then
        p.x = clamp(tonumber(value) or 0, -200, 200)
    elseif field == "y" then
        p.y = clamp(tonumber(value) or 0, -200, 200)
    elseif field == "move" then
        return
    elseif field == "portrait" or field == "portraitScale" or field == "portraitRing"
        or field == "portraitOffsetX" or field == "portraitOffsetY" or field == "badgeScale"
        or field == "badgeOffsetX" or field == "badgeOffsetY" or field == "badgeAngle"
        or field == "badgeHost" or field == "shieldChargeEnabled" or field == "shieldChargeSpread"
        or field == "shieldChargeSize" or field == "shieldChargeAngle"
        or field == "shieldChargeReverse" or field == "shieldChargeOffsetX"
        or field == "shieldChargeOffsetY" then
        p[field] = value
        if field == "portrait" then p.portrait = value and true or false end
        if field == "portraitScale" then p.portraitScale = clamp(tonumber(value) or 1.05, 0.8, 2.5) end
        if field == "portraitRing" then p.portraitRing = clamp(tonumber(value) or 1, 0.90, 1.40) end
        if field == "portraitOffsetX" then p.portraitOffsetX = clamp(tonumber(value) or 0, -40, 40) end
        if field == "portraitOffsetY" then p.portraitOffsetY = clamp(tonumber(value) or 0, -40, 40) end
        if field == "badgeScale" then p.badgeScale = clamp(tonumber(value) or 1, 0.5, 2.0) end
        if field == "badgeOffsetX" then p.badgeOffsetX = clamp(tonumber(value) or 0, -40, 40) end
        if field == "badgeOffsetY" then p.badgeOffsetY = clamp(tonumber(value) or 0, -40, 40) end
        if field == "badgeAngle" then p.badgeAngle = clamp(tonumber(value) or 0, 0, 360) end
        if field == "badgeHost" then
            if value == "frame" then p.badgeHost = "frame" else p.badgeHost = "portrait" end
        end
        if field == "shieldChargeEnabled" then p.shieldChargeEnabled = value and true or false end
        if field == "shieldChargeSpread" then p.shieldChargeSpread = clamp(tonumber(value) or 90, 10, 360) end
        if field == "shieldChargeSize" then p.shieldChargeSize = clamp(tonumber(value) or 10, 6, 28) end
        if field == "shieldChargeAngle" then p.shieldChargeAngle = clamp(tonumber(value) or 0, -360, 360) end
        if field == "shieldChargeReverse" then p.shieldChargeReverse = value and true or false end
        if field == "shieldChargeOffsetX" then p.shieldChargeOffsetX = clamp(tonumber(value) or 0, -40, 40) end
        if field == "shieldChargeOffsetY" then p.shieldChargeOffsetY = clamp(tonumber(value) or 0, -40, 40) end
    else
        return
    end
    saveDb()
    IchaUIUF_LayoutPartyToT()
end

function IchaUIUF_PartyToTGetPos()
    local p = partyToTDb()
    return tonumber(p.x) or 0, tonumber(p.y) or 0
end

function IchaUIUF_PartyToTSetPos(x, y)
    local p = partyToTDb()
    p.x = clamp(tonumber(x) or 0, -200, 200)
    p.y = clamp(tonumber(y) or 0, -200, 200)
    saveDb()
    IchaUIUF_LayoutPartyToT()
end

function IchaUIUF_PartyToTNudge(dx, dy)
    local x, y = IchaUIUF_PartyToTGetPos()
    IchaUIUF_PartyToTSetPos(x + (tonumber(dx) or 0), y + (tonumber(dy) or 0))
end

local function refreshPlayerTot(force)
    if type(IchaUIUF_Get) ~= "function" then return end
    local tot = IchaUIUF_Get("tot")
    if not tot or not tot.update then return end
    local stamp = unitStamp("targettarget")
    local shown = frameShown(tot)
    if force or (stamp and not shown) or ((not stamp) and shown) or stamp ~= lastTotStamp then
        lastTotStamp = stamp
        if tot._swingStart and not stamp then
            tot._swingStart = nil
            tot._swingPeriod = nil
            if IchaUI_Swing_Hide then IchaUI_Swing_Hide(tot) end
        end
        tot:update()
    elseif shown and tot.updateCast then
        tot:updateCast()
    end
end

function IchaUIUF_RefreshToTFast()
    burstLeft = 0.40
    refreshPlayerTot(true)
    local i
    for i = 1, 4 do
        paintOne(i, true)
    end
end

-- Build after party frames exist (this file loads after UnitFrames.lua).
do
    local i
    for i = 1, 4 do
        local host = hostFrame(i)
        local parent = (host and host.root) or UIParent
        slots[i] = IchaUI_CreateUnitFrame("ptot" .. i, "party" .. i .. "target", {
            scale = 1, width = 106, height = 48,
            portrait = false, portraitScale = 1.05, portraitRing = 1,
        }, {
            parent = parent,
            managedPos = true,
            portrait = true,
            portraitSide = "right",
        })
        if slots[i] and slots[i].root then
            slots[i].root:Hide()
        end
    end
    IchaUIUF_LayoutPartyToT()
end

-- Fast ToT / party-target detection. Vanilla 1.12 has no UNIT_TARGET for
-- targettarget; SuperWoW may fire UNIT_TARGET / UNIT_TARGETTABLE_CHANGED.
local pulse = CreateFrame("Frame", "IchaUIUF_PartyToTPulse")
pulse.t = 0
pulse:RegisterEvent("PLAYER_LOGIN")
pulse:RegisterEvent("PLAYER_ENTERING_WORLD")
pulse:RegisterEvent("PLAYER_TARGET_CHANGED")
pulse:RegisterEvent("UNIT_TARGET")
pulse:RegisterEvent("PARTY_MEMBERS_CHANGED")
pulse:RegisterEvent("PARTY_MEMBER_ENABLE")
pulse:RegisterEvent("PARTY_MEMBER_DISABLE")
pulse:RegisterEvent("RAID_ROSTER_UPDATE")
pulse:RegisterEvent("UNIT_HEALTH")
pulse:RegisterEvent("UNIT_MAXHEALTH")
pulse:RegisterEvent("UNIT_MANA")
pulse:RegisterEvent("UNIT_NAME_UPDATE")
pulse:RegisterEvent("UNIT_PORTRAIT_UPDATE")
pcall(function() pulse:RegisterEvent("UNIT_TARGETTABLE_CHANGED") end)
pcall(function() pulse:RegisterEvent("PLAYER_FOCUS_CHANGED") end)
pulse:SetScript("OnEvent", function()
    if IchaUI_LEAVING and event ~= "PLAYER_ENTERING_WORLD" then return end
    if event == "PLAYER_TARGET_CHANGED" or event == "UNIT_TARGET"
        or event == "UNIT_TARGETTABLE_CHANGED" then
        IchaUIUF_RefreshToTFast()
        return
    end
    if event == "PARTY_MEMBERS_CHANGED" or event == "PARTY_MEMBER_ENABLE"
        or event == "PARTY_MEMBER_DISABLE" or event == "RAID_ROSTER_UPDATE"
        or event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        IchaUIUF_LayoutPartyToT()
        refreshPlayerTot(true)
        return
    end
    local who = arg1
    if type(who) == "string" then
        if who == "targettarget" or who == "target" then
            refreshPlayerTot(true)
        end
        local i
        for i = 1, 4 do
            if who == ("party" .. i) or who == ("party" .. i .. "target") then
                paintOne(i, true)
            end
        end
    end
end)
pulse:SetScript("OnUpdate", function()
    if IchaUI_LEAVING then return end
    local dt = arg1 or 0
    if burstLeft > 0 then
        burstLeft = burstLeft - dt
        refreshPlayerTot(true)
        local i
        for i = 1, 4 do
            paintOne(i, true)
        end
        return
    end
    this.t = (this.t or 0) + dt
    if this.t < 0.05 then
        local i
        for i = 1, 4 do
            local fr = slots[i]
            if fr and frameShown(fr) then
                if fr.updateCast then fr:updateCast() end
                if IchaUI_Swing_Update then IchaUI_Swing_Update(fr) end
            end
        end
        return
    end
    this.t = 0
    refreshPlayerTot(false)
    local i
    for i = 1, 4 do
        paintOne(i, false)
    end
end)

-- Kind helpers (globals). Avoid new UnitFrames.lua column-0 locals.
do
    local prevBar = IchaUIUF_BarKind
    function IchaUIUF_BarKind(key)
        if key == "partytot" or (type(key) == "string" and string.find(key, "^ptot")) then
            return "partytot"
        end
        if prevBar then return prevBar(key) end
        return "player"
    end
end

do
    local prevStore = IchaUI_LevelStoreKey
    function IchaUI_LevelStoreKey(key)
        if key == "partytot" or (type(key) == "string" and string.find(key, "^ptot")) then
            return "partytot"
        end
        if prevStore then return prevStore(key) end
        return key or "player"
    end
end

do
    local prevCan = IchaUI_LevelCanPortrait
    function IchaUI_LevelCanPortrait(key)
        local store = key
        if IchaUI_LevelStoreKey then store = IchaUI_LevelStoreKey(key) end
        if store == "partytot" then return true end
        if prevCan then return prevCan(key) end
        return false
    end
end

do
    local prevGet = IchaUIUF_Get
    function IchaUIUF_Get(key)
        if key == "partytot" then return slots[1] end
        if prevGet then return prevGet(key) end
        return nil
    end
end

do
    local prevSet = IchaUIUF_Set
    function IchaUIUF_Set(key, field, value)
        if key == "partytot" then
            IchaUIUF_PartyToTSet(field, value)
            return
        end
        if prevSet then prevSet(key, field, value) end
    end
end

do
    local prevGetPos = IchaUIUF_GetPos
    function IchaUIUF_GetPos(key)
        if key == "partytot" then return IchaUIUF_PartyToTGetPos() end
        if prevGetPos then return prevGetPos(key) end
        return 0, 0
    end
end

do
    local prevSetPos = IchaUIUF_SetPos
    function IchaUIUF_SetPos(key, x, y)
        if key == "partytot" then
            IchaUIUF_PartyToTSetPos(x, y)
            return
        end
        if prevSetPos then prevSetPos(key, x, y) end
    end
end

do
    local prevNudge = IchaUIUF_Nudge
    function IchaUIUF_Nudge(key, dx, dy)
        if key == "partytot" then
            IchaUIUF_PartyToTNudge(dx, dy)
            return
        end
        if prevNudge then prevNudge(key, dx, dy) end
    end
end

do
    local prevKind = IchaUIUF_KindMetrics
    function IchaUIUF_KindMetrics(kind)
        if IchaUIUF_BarKind then kind = IchaUIUF_BarKind(kind) end
        if kind == "partytot" then
            local t = IchaUIUF_PartyToTGet()
            return tonumber(t.height) or 48, tonumber(t.scale) or 1, tonumber(t.width) or 106
        end
        if prevKind then return prevKind(kind) end
        return 48, 1, 220
    end
end

do
    local prevReflow = IchaUIUF_ReflowBars
    function IchaUIUF_ReflowBars(kind)
        if IchaUIUF_BarKind then kind = IchaUIUF_BarKind(kind) end
        if kind == "partytot" then
            IchaUIUF_LayoutPartyToT()
            return
        end
        if prevReflow then prevReflow(kind) end
    end
end

do
    local prevLayout = IchaUIUF_layoutParty
    function IchaUIUF_layoutParty()
        if prevLayout then prevLayout() end
        IchaUIUF_LayoutPartyToT()
    end
end

do
    local prevApply = IchaUIUF_ApplyAll
    function IchaUIUF_ApplyAll()
        if prevApply then prevApply() end
        IchaUIUF_LayoutPartyToT()
    end
end

do
    local prevRefresh = IchaUIUF_refreshAll
    function IchaUIUF_refreshAll()
        if prevRefresh then prevRefresh() end
        local i
        for i = 1, 4 do
            paintOne(i, true)
        end
    end
end

do
    local prevText = IchaUIUF_refreshTextKind
    function IchaUIUF_refreshTextKind(kind)
        if kind == "partytot" then
            IchaUIUF_LayoutPartyToT()
            return
        end
        if prevText then prevText(kind) end
    end
end

do
    local prevParty = IchaUIUF_ApplyPartySaved
    function IchaUIUF_ApplyPartySaved()
        if prevParty then prevParty() end
        IchaUIUF_ApplyPartyToTSaved()
    end
end

do
    local prevCast = IchaUIUF_SetCastSetting
    function IchaUIUF_SetCastSetting(kind, field, value)
        if prevCast then prevCast(kind, field, value) end
        if kind == "partytot" then
            local i
            for i = 1, 4 do
                local fr = slots[i]
                if fr then
                    if fr.applySize then fr:applySize() end
                    if fr.updateCast then fr:updateCast() end
                end
            end
        end
    end
end

do
    local prevSync = IchaUIUF_SyncShownAuraTimers
    function IchaUIUF_SyncShownAuraTimers()
        if prevSync then prevSync() end
        local i
        for i = 1, 4 do
            local fr = slots[i]
            if fr and frameShown(fr) and fr.updateAuras then
                fr:updateAuras()
            end
        end
    end
end
