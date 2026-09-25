-- Smart mark: hold the modifier in the keybind, mouseover units get raid icons.
-- ICHA_SMARTMARK marks enemies only. ICHA_SMARTMARK_FRIENDLY marks friendly units only.
-- Each has its own icon order (IchaUIDB.smartMarkOrder / smartMarkFriendOrder) and
-- disabled set (smartMarkOff / smartMarkFriendOff). Edit them in /iui > Mark.
-- Units that already have a marker are skipped. Releasing the modifier turns it off.

BINDING_HEADER_ICHASMART = "IchaUI Smart Mark"
BINDING_NAME_ICHA_SMARTMARK = "Smart Mark"
BINDING_NAME_ICHA_SMARTMARK_FRIENDLY = "Smart Mark Friendly"

-- Default: skull, X, moon, circle, square, diamond, star, triangle.
local DEFAULT_ORDER = { 8, 7, 5, 2, 6, 3, 1, 4 }
local ICON_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }

local KINDS = {
    enemy = { order = "smartMarkOrder", off = "smartMarkOff", cmd = "ICHA_SMARTMARK", label = "Smart Mark" },
    friend = { order = "smartMarkFriendOrder", off = "smartMarkFriendOff", cmd = "ICHA_SMARTMARK_FRIENDLY", label = "Smart Mark Friendly" },
}

local active = false
local mode = "enemy"
local marks = {}
local needShift, needCtrl, needAlt = false, false, false
local step = 1
local seen = {}
local lastName, lastTime = nil, 0

local function say(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("IchaUI: " .. msg) end
end

local function cleanOrder(src)
    local out, used = {}, {}
    local i, v
    if type(src) == "table" then
        for i = 1, table.getn(src) do
            v = tonumber(src[i])
            if v and v >= 1 and v <= 8 and math.floor(v) == v and not used[v] then
                used[v] = true
                table.insert(out, v)
            end
        end
    end
    for i = 1, table.getn(DEFAULT_ORDER) do
        v = DEFAULT_ORDER[i]
        if not used[v] then
            used[v] = true
            table.insert(out, v)
        end
    end
    return out
end

local function kindOf(kind)
    if kind == "friend" or kind == "friendly" then return "friend" end
    return "enemy"
end

-- Read fresh every call: profile loads replace IchaUIDB.
local function kindDB(kind)
    local k = KINDS[kindOf(kind)]
    if not IchaUIDB then IchaUIDB = {} end
    local ord = IchaUIDB[k.order]
    local clean = cleanOrder(ord)
    local ok = type(ord) == "table" and table.getn(ord) == table.getn(clean)
    if ok then
        local i
        for i = 1, table.getn(clean) do
            if ord[i] ~= clean[i] then ok = false end
        end
    end
    if not ok then IchaUIDB[k.order] = clean end
    if type(IchaUIDB[k.off]) ~= "table" then IchaUIDB[k.off] = {} end
    return IchaUIDB[k.order], IchaUIDB[k.off]
end

local function enabledMarks(kind)
    local ord, off = kindDB(kind)
    local out = {}
    local i
    for i = 1, table.getn(ord) do
        if not off[ord[i]] then table.insert(out, ord[i]) end
    end
    return out
end

-- Config API (used by IchaUI Options, Mark tab)
function IchaUI_SmartMark_IconName(idx)
    return ICON_NAMES[idx] or "?"
end

function IchaUI_SmartMark_GetOrder(kind)
    local ord = kindDB(kind)
    return ord
end

function IchaUI_SmartMark_IsIconOn(kind, idx)
    local _, off = kindDB(kind)
    return not off[idx]
end

function IchaUI_SmartMark_SetIconOn(kind, idx, on)
    local _, off = kindDB(kind)
    idx = tonumber(idx)
    if not idx then return end
    if on then off[idx] = nil else off[idx] = true end
end

function IchaUI_SmartMark_Move(kind, pos, dir)
    local ord = kindDB(kind)
    local other = pos + dir
    if pos < 1 or pos > table.getn(ord) or other < 1 or other > table.getn(ord) then return end
    local t = ord[pos]
    ord[pos] = ord[other]
    ord[other] = t
end

function IchaUI_SmartMark_Reset(kind)
    local k = KINDS[kindOf(kind)]
    if not IchaUIDB then IchaUIDB = {} end
    IchaUIDB[k.order] = cleanOrder(nil)
    IchaUIDB[k.off] = {}
end

function IchaUI_SmartMark_CopyOrder(fromKind, toKind)
    local ord, off = kindDB(fromKind)
    local k = KINDS[kindOf(toKind)]
    local o2, f2 = {}, {}
    local i
    for i = 1, table.getn(ord) do
        o2[i] = ord[i]
        if off[ord[i]] then f2[ord[i]] = true end
    end
    IchaUIDB[k.order] = o2
    IchaUIDB[k.off] = f2
end

function IchaUI_SmartMark_GetKey(kind)
    if not GetBindingKey then return nil end
    local k1 = GetBindingKey(KINDS[kindOf(kind)].cmd)
    return k1
end

local function hasMod(key)
    if type(key) ~= "string" then return false end
    if string.find(key, "SHIFT") or string.find(key, "CTRL") or string.find(key, "ALT") then return true end
    return false
end

function IchaUI_SmartMark_SetKey(kind, key)
    if not SetBinding or not GetBindingKey then return end
    local cmd = KINDS[kindOf(kind)].cmd
    if key and key ~= "" and not hasMod(key) then
        say("Smart Mark binds need Shift, Ctrl, or Alt (for example SHIFT-Q).")
        return
    end
    local k1, k2 = GetBindingKey(cmd)
    if k1 and k1 ~= "" then SetBinding(k1) end
    if k2 and k2 ~= "" then SetBinding(k2) end
    if key and key ~= "" then SetBinding(key, cmd) end
    if SaveBindings then
        local set = GetCurrentBindingSet and GetCurrentBindingSet()
        SaveBindings(set or 1)
    end
end

local function modDown()
    if needShift and not (IsShiftKeyDown and IsShiftKeyDown()) then return false end
    if needCtrl and not (IsControlKeyDown and IsControlKeyDown()) then return false end
    if needAlt and not (IsAltKeyDown and IsAltKeyDown()) then return false end
    if not needShift and not needCtrl and not needAlt then return false end
    return true
end

-- Returns key, true for a GUID (SuperWoW); name, false otherwise.
local function unitKey(unit)
    if UnitGUID then
        local g = UnitGUID(unit)
        if g and g ~= "" then return g, true end
    end
    local name = UnitName(unit)
    if not name or name == "" then return nil, false end
    return name, false
end

local function nextMark()
    local n = table.getn(marks)
    if n < 1 then return nil end
    if step < 1 or step > n then step = 1 end
    local m = marks[step]
    step = step + 1
    if step > n then step = 1 end
    return m
end

local function unitWanted(unit)
    if mode == "friend" then
        if not UnitIsFriend or not UnitIsFriend("player", unit) then return false end
        if UnitCanAttack and UnitCanAttack("player", unit) then return false end
        return true
    end
    if not UnitCanAttack or not UnitCanAttack("player", unit) then return false end
    return true
end

local function markUnit(unit)
    if not unit or not UnitExists or not UnitExists(unit) then return end
    if not unitWanted(unit) then return end
    if UnitIsDead and UnitIsDead(unit) then return end
    local key, byGuid = unitKey(unit)
    if not key then return end
    local now = GetTime and GetTime() or 0
    if byGuid then
        if seen[key] then return end
    elseif key == lastName and (now - lastTime) < 1 then
        -- Without GUIDs, names repeat across a pack; only guard the unit just marked.
        return
    end
    local cur = 0
    if GetRaidTargetIndex then cur = GetRaidTargetIndex(unit) or 0 end
    if cur ~= 0 then
        if byGuid then seen[key] = true end
        return
    end
    if not SetRaidTarget then return end
    local mark = nextMark()
    if not mark then return end
    SetRaidTarget(unit, mark)
    if byGuid then
        seen[key] = true
    else
        lastName = key
        lastTime = now
    end
end

local function smartMarkOn()
    if not IchaUIDB or IchaUIDB.smartMark == nil then return true end
    return IchaUIDB.smartMark and true or false
end

local function canMark()
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        if IsRaidLeader and IsRaidLeader() then return true end
        if IsRaidOfficer and IsRaidOfficer() then return true end
        return false
    end
    return true
end

local function parseMods(key)
    local s, c, a = false, false, false
    if type(key) == "string" then
        if string.find(key, "SHIFT") then s = true end
        if string.find(key, "CTRL") then c = true end
        if string.find(key, "ALT") then a = true end
    end
    return s, c, a
end

local function modsHeld(s, c, a)
    if not s and not c and not a then return false end
    if s and not (IsShiftKeyDown and IsShiftKeyDown()) then return false end
    if c and not (IsControlKeyDown and IsControlKeyDown()) then return false end
    if a and not (IsAltKeyDown and IsAltKeyDown()) then return false end
    return true
end

local function startMark(kind, keystate)
    if not smartMarkOn() then
        active = false
        return
    end
    local down = (keystate == nil or keystate == "down")
    if not down then
        active = false
        return
    end
    kind = kindOf(kind)
    local k1, k2
    if GetBindingKey then k1, k2 = GetBindingKey(KINDS[kind].cmd) end
    local s, c, a = parseMods(k1)
    if k2 and not modsHeld(s, c, a) then
        local s2, c2, a2 = parseMods(k2)
        if modsHeld(s2, c2, a2) or (not s and not c and not a) then
            s, c, a = s2, c2, a2
        end
    end
    needShift, needCtrl, needAlt = s, c, a
    if not needShift and not needCtrl and not needAlt then
        say(KINDS[kind].label .. " needs Shift, Ctrl, or Alt in the keybind.")
        active = false
        return
    end
    if not canMark() then
        say("Smart Mark: you need raid lead or assist to mark.")
        active = false
        return
    end
    marks = enabledMarks(kind)
    if table.getn(marks) < 1 then
        say(KINDS[kind].label .. ": every icon is disabled (/iui > Mark).")
        active = false
        return
    end
    mode = kind
    active = true
    step = 1
    seen = {}
    lastName = nil
    lastTime = 0
    markUnit("mouseover")
end

function IchaUI_SmartMark_Bind(keystate)
    startMark("enemy", keystate)
end

function IchaUI_SmartMark_BindFriendly(keystate)
    startMark("friend", keystate)
end

local f = CreateFrame("Frame", "IchaUISmartMark")
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
f:SetScript("OnEvent", function()
    if not smartMarkOn() then
        active = false
        return
    end
    if active then markUnit("mouseover") end
end)
f:SetScript("OnUpdate", function()
    if not active then return end
    if not smartMarkOn() or not modDown() then
        active = false
        return
    end
    markUnit("mouseover")
end)
