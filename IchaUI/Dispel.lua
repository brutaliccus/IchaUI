-- Click-to-dispel and Smart Dispel for every IchaUI unit frame.
-- Spells come from the spellbook (and the pet book for Felhunter), so any class
-- only gets rows it can cast. Settings: IchaUIDB.dispel (defaults in Defaults.lua).
--
-- Casts only run from a Button OnClick (unit frames) or a key binding handler.

IchaUI_DISPEL_TYPES = { "Magic", "Curse", "Poison", "Disease" }
IchaUI_DISPEL_ACTIONS = { "Magic", "Curse", "Poison", "Disease", "Offensive", "Smart" }

-- Strongest first. Cleanse / Purify cover several schools.
local CANDIDATES = {
    Magic = { "Dispel Magic", "Cleanse", "Devour Magic" },
    Curse = { "Remove Curse", "Remove Lesser Curse" },
    Poison = { "Abolish Poison", "Cure Poison", "Cleanse", "Purify" },
    Disease = { "Abolish Disease", "Cure Disease", "Cleanse", "Purify" },
    Offensive = { "Purge", "Dispel Magic", "Devour Magic" },
}

IchaUI_DISPEL_BUTTONS = {
    { "LeftButton", "Left" },
    { "RightButton", "Right" },
    { "MiddleButton", "Middle" },
    { "Button4", "Button 4" },
    { "Button5", "Button 5" },
    { "OFF", "Off" },
}

IchaUI_DISPEL_MODS = {
    { "NONE", "None" },
    { "SHIFT", "Shift" },
    { "CTRL", "Ctrl" },
    { "ALT", "Alt" },
    { "CTRL-SHIFT", "Ctrl+Shift" },
    { "ALT-SHIFT", "Alt+Shift" },
    { "ALT-CTRL", "Ctrl+Alt" },
    { "ALT-CTRL-SHIFT", "Ctrl+Alt+Shift" },
}

local DEFAULT_CLICKS = {
    Poison = { button = "LeftButton", mod = "SHIFT" },
    Disease = { button = "RightButton", mod = "SHIFT" },
    Magic = { button = "LeftButton", mod = "CTRL" },
    Curse = { button = "RightButton", mod = "CTRL" },
    Offensive = { button = "LeftButton", mod = "ALT" },
    Smart = { button = "MiddleButton", mod = "NONE" },
}

local BUTTON_KEY = {
    LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3",
    Button4 = "BUTTON4", Button5 = "BUTTON5",
}

BINDING_HEADER_ICHADISPEL = "IchaUI Dispel"
BINDING_NAME_ICHA_DISPEL_TARGET = "Smart Dispel Target"
BINDING_NAME_ICHA_DISPEL_MOUSEOVER = "Smart Dispel Mouseover"
BINDING_NAME_ICHA_DISPEL_SELF = "Smart Dispel Self"
BINDING_NAME_ICHA_DISPEL_FOCUS = "Smart Dispel Focus"

IchaUI_DISPEL_BINDS = {
    { "ICHA_DISPEL_TARGET", "Target" },
    { "ICHA_DISPEL_MOUSEOVER", "Mouseover" },
    { "ICHA_DISPEL_SELF", "Self" },
    { "ICHA_DISPEL_FOCUS", "Focus" },
}

local known = {}
local knownPet = {}
local scanned = false
local frames = {}

local function validButton(b)
    if b == "OFF" then return true end
    return BUTTON_KEY[b] and true or false
end

local function validMod(m)
    local i
    for i = 1, table.getn(IchaUI_DISPEL_MODS) do
        if IchaUI_DISPEL_MODS[i][1] == m then return true end
    end
    return false
end

local function validType(t)
    return t == "Magic" or t == "Curse" or t == "Poison" or t == "Disease"
end

-- Saved lists can come back with table.getn == 0, so the order is read by index.
local function fixOrder(o)
    local out, seen = {}, {}
    local i
    if type(o) == "table" then
        for i = 1, 4 do
            local t = o[i]
            if validType(t) and not seen[t] then
                table.insert(out, t)
                seen[t] = true
            end
        end
    end
    for i = 1, 4 do
        local t = IchaUI_DISPEL_TYPES[i]
        if not seen[t] then
            table.insert(out, t)
            seen[t] = true
        end
    end
    return out
end

function IchaUI_DispelDB()
    if type(IchaUIDB) ~= "table" then IchaUIDB = {} end
    local d = IchaUIDB.dispel
    if type(d) ~= "table" then
        d = {}
        IchaUIDB.dispel = d
    end
    if d.enabled == nil then d.enabled = true end
    if type(d.clicks) ~= "table" then d.clicks = {} end
    local i
    for i = 1, table.getn(IchaUI_DISPEL_ACTIONS) do
        local a = IchaUI_DISPEL_ACTIONS[i]
        local c = d.clicks[a]
        if type(c) ~= "table" then
            c = {}
            d.clicks[a] = c
        end
        if not validButton(c.button) then c.button = DEFAULT_CLICKS[a].button end
        if not validMod(c.mod) then c.mod = DEFAULT_CLICKS[a].mod end
        if c.mod == "NONE" and (c.button == "LeftButton" or c.button == "RightButton") then
            c.mod = "SHIFT"
        end
    end
    local o = fixOrder(d.order)
    d.order = o
    return d
end

------------------------------------------------------------------------
-- Spellbook
------------------------------------------------------------------------
local function scanBook(book, into)
    if type(GetSpellName) ~= "function" then return end
    local i = 1
    while i < 1024 do
        local name = nil
        local ok = pcall(function() name = GetSpellName(i, book) end)
        if not ok or not name then break end
        into[name] = true
        i = i + 1
    end
end

function IchaUI_Dispel_Rescan()
    known = {}
    knownPet = {}
    scanBook(BOOKTYPE_SPELL or "spell", known)
    local hasPet = true
    if type(HasPetSpells) == "function" then
        hasPet = false
        pcall(function() if HasPetSpells() then hasPet = true end end)
    end
    if hasPet then scanBook(BOOKTYPE_PET or "pet", knownPet) end
    scanned = true
end

local function spellKnown(name)
    if not scanned then IchaUI_Dispel_Rescan() end
    return (known[name] or knownPet[name]) and true or false
end

-- Best known spell for a debuff school, or "Offensive". nil when none.
function IchaUI_Dispel_SpellFor(action)
    local list = CANDIDATES[action]
    if not list then return nil end
    local i
    for i = 1, table.getn(list) do
        if spellKnown(list[i]) then return list[i] end
    end
    return nil
end

function IchaUI_Dispel_IsPetSpell(name)
    if not name then return false end
    return (knownPet[name] and not known[name]) and true or false
end

function IchaUI_Dispel_SpellIcon(name)
    if not name or type(GetSpellTexture) ~= "function" then return nil end
    local book = BOOKTYPE_SPELL or "spell"
    if IchaUI_Dispel_IsPetSpell(name) then book = BOOKTYPE_PET or "pet" end
    local i = 1
    while i < 1024 do
        local n = nil
        pcall(function() n = GetSpellName(i, book) end)
        if not n then break end
        if n == name then
            local tex = nil
            pcall(function() tex = GetSpellTexture(i, book) end)
            return tex
        end
        i = i + 1
    end
    return nil
end

-- Smart can do something when any school or the offensive row has a spell.
function IchaUI_Dispel_ActionKnown(action)
    if action == "Smart" then
        local i
        for i = 1, table.getn(IchaUI_DISPEL_ACTIONS) do
            local a = IchaUI_DISPEL_ACTIONS[i]
            if a ~= "Smart" and IchaUI_Dispel_SpellFor(a) then return true end
        end
        return false
    end
    return IchaUI_Dispel_SpellFor(action) and true or false
end

------------------------------------------------------------------------
-- Units and auras
------------------------------------------------------------------------
local function tokenOk(unit)
    if type(unit) ~= "string" or unit == "" or unit == "none" then return false end
    if string.sub(unit, 1, 6) == "IchaUI" then return false end
    if string.find(unit, "^0[xX]%x+$") then return true end
    if unit == "player" or unit == "pet" or unit == "target" or unit == "targettarget"
        or unit == "pettarget" or unit == "mouseover" or unit == "focus" then
        return true
    end
    if string.find(unit, "^party[1-4]$") or string.find(unit, "^partypet[1-4]$") then return true end
    if string.find(unit, "^party[1-4]target$") then return true end
    if string.find(unit, "^raid%d+$") or string.find(unit, "^raidpet%d+$") then return true end
    if string.find(unit, "^raid%d+target$") then return true end
    if string.find(unit, "^nameplate%d+$") then return true end
    return false
end

local function unitLive(unit)
    if IchaUI_LEAVING then return false end
    if not tokenOk(unit) or type(UnitExists) ~= "function" then return false end
    local ex = false
    pcall(function() if UnitExists(unit) then ex = true end end)
    return ex
end

local function unitHostile(unit)
    local h = false
    pcall(function()
        if UnitCanAttack and UnitCanAttack("player", unit) then h = true end
    end)
    return h
end

local function schoolWord(s)
    if type(s) ~= "string" then return nil end
    local l = string.lower(s)
    if l == "magic" then return "Magic" end
    if l == "curse" then return "Curse" end
    if l == "poison" then return "Poison" end
    if l == "disease" then return "Disease" end
    return nil
end

-- 1.12: texture, count, debuffType. SuperWoW adds a spell id.
local function rawDebuffType(unit, i)
    local a1, a2, a3, a4, a5 = nil, nil, nil, nil, nil
    pcall(function() a1, a2, a3, a4, a5 = UnitDebuff(unit, i) end)
    if not a1 then return nil, false end
    local t = schoolWord(a3) or schoolWord(a4) or schoolWord(a5)
    return t, true
end

-- { Magic = true, ... } for the unit's current debuffs.
function IchaUI_Dispel_DebuffTypes(unit)
    local have = {}
    if not unitLive(unit) then return have end
    local reader = IchaUI_Dispel_ReadDebuff
    local i
    for i = 1, 40 do
        local t, more = nil, false
        if type(reader) == "function" then
            local name, icon, dt = nil, nil, nil
            pcall(function()
                local n, ic, _, d = reader(unit, i, nil)
                name, icon, dt = n, ic, d
            end)
            more = (name or icon) and true or false
            t = schoolWord(dt)
        else
            t, more = rawDebuffType(unit, i)
        end
        if not more then break end
        if t then have[t] = true end
    end
    return have
end

------------------------------------------------------------------------
-- Casting
------------------------------------------------------------------------
-- Nampower / SuperWoW take a unit token or GUID as CastSpellByName's 2nd arg.
-- Plain 1.12 treats any 2nd arg as self-cast.
local function softCastOk()
    if type(SetAutoloot) == "function" then return true end
    if type(SpellInfo) == "function" then return true end
    if type(GetNampowerVersion) == "function" then return true end
    return false
end

local function isUnit(a, b)
    local same = false
    pcall(function() if UnitIsUnit and UnitIsUnit(a, b) then same = true end end)
    return same
end

-- Same path the unit frames used before: cast, then aim the targeting cursor at
-- the unit. Without soft-cast, a friendly spell would land on a different
-- friendly target, so swap target for the cast and swap back.
function IchaUI_Dispel_CastOn(spell, unit)
    if not spell or not unitLive(unit) then return false end
    if type(CastSpellByName) ~= "function" then return false end
    if softCastOk() then
        CastSpellByName(spell, unit)
        if SpellIsTargeting and SpellIsTargeting() and SpellTargetUnit then
            SpellTargetUnit(unit)
        end
        return true
    end
    if unit == "player" and not isUnit("target", "player") then
        CastSpellByName(spell, 1)
        return true
    end
    local swap = false
    if UnitExists and UnitExists("target") and not isUnit("target", unit) then
        swap = true
    end
    if swap and TargetUnit and TargetLastTarget then
        TargetUnit(unit)
        CastSpellByName(spell)
        if SpellIsTargeting and SpellIsTargeting() and SpellTargetUnit then
            SpellTargetUnit(unit)
        end
        TargetLastTarget()
        return true
    end
    CastSpellByName(spell)
    if SpellIsTargeting and SpellIsTargeting() then
        if SpellTargetUnit then SpellTargetUnit(unit) else TargetUnit(unit) end
    end
    return true
end

-- Spell Smart Dispel would use on the unit right now, or nil.
function IchaUI_Dispel_SmartSpell(unit)
    if not unitLive(unit) then return nil end
    if unitHostile(unit) then
        return IchaUI_Dispel_SpellFor("Offensive"), "Offensive"
    end
    local d = IchaUI_DispelDB()
    local have = IchaUI_Dispel_DebuffTypes(unit)
    local i
    for i = 1, 4 do
        local t = d.order[i]
        if t and have[t] then
            local sp = IchaUI_Dispel_SpellFor(t)
            if sp then return sp, t end
        end
    end
    return nil
end

local function errMsg(msg)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(msg, 1, 0.3, 0.3, 1, 2)
    end
end

function IchaUI_Dispel_Smart(unit, loud)
    if IchaUI_LEAVING then return false end
    if not unitLive(unit) then return false end
    local sp = IchaUI_Dispel_SmartSpell(unit)
    if not sp then
        if loud then errMsg("Nothing to dispel") end
        return false
    end
    return IchaUI_Dispel_CastOn(sp, unit)
end

------------------------------------------------------------------------
-- Clicks
------------------------------------------------------------------------
function IchaUI_Dispel_ModsNow()
    local parts = {}
    if IsAltKeyDown and IsAltKeyDown() then table.insert(parts, "ALT") end
    if IsControlKeyDown and IsControlKeyDown() then table.insert(parts, "CTRL") end
    if IsShiftKeyDown and IsShiftKeyDown() then table.insert(parts, "SHIFT") end
    if table.getn(parts) == 0 then return "NONE" end
    return table.concat(parts, "-")
end

local function clickOf(action)
    local d = IchaUI_DispelDB()
    return d.clicks[action]
end

local function matches(action, button, mods)
    local c = clickOf(action)
    if not c or c.button == "OFF" then return false end
    return c.button == button and c.mod == mods
end

-- true when the click was a dispel click (the frame must not target / open its menu).
function IchaUI_Dispel_HandleClick(unit, button)
    if IchaUI_LEAVING then return false end
    local d = IchaUI_DispelDB()
    if not d.enabled then return false end
    if not unitLive(unit) then return false end
    local mods = IchaUI_Dispel_ModsNow()
    if unitHostile(unit) then
        if matches("Offensive", button, mods) or matches("Smart", button, mods) then
            local sp = IchaUI_Dispel_SpellFor("Offensive")
            if sp then
                IchaUI_Dispel_CastOn(sp, unit)
                return true
            end
        end
        return false
    end
    local claimed = false
    local have = IchaUI_Dispel_DebuffTypes(unit)
    local i
    -- Rows sharing one click resolve in Smart order.
    for i = 1, 4 do
        local t = d.order[i]
        if matches(t, button, mods) then
            local sp = IchaUI_Dispel_SpellFor(t)
            if sp then
                claimed = true
                if have[t] then
                    IchaUI_Dispel_CastOn(sp, unit)
                    return true
                end
            end
        end
    end
    if matches("Smart", button, mods) and IchaUI_Dispel_ActionKnown("Smart") then
        IchaUI_Dispel_Smart(unit, false)
        return true
    end
    return claimed
end

-- "LeftButtonUp", ... for every button a frame needs.
function IchaUI_Dispel_ClickList()
    local want = { LeftButton = true, RightButton = true }
    local d = IchaUI_DispelDB()
    if d.enabled then
        local i
        for i = 1, table.getn(IchaUI_DISPEL_ACTIONS) do
            local c = d.clicks[IchaUI_DISPEL_ACTIONS[i]]
            if c and BUTTON_KEY[c.button] then want[c.button] = true end
        end
    end
    local out = {}
    local order = { "LeftButton", "RightButton", "MiddleButton", "Button4", "Button5" }
    local i
    for i = 1, 5 do
        if want[order[i]] then table.insert(out, order[i] .. "Up") end
    end
    return out
end

local function applyTo(btn)
    if not btn or not btn.RegisterForClicks then return end
    local l = IchaUI_Dispel_ClickList()
    btn:RegisterForClicks(l[1], l[2], l[3], l[4], l[5])
end

-- fr: the IchaUI unit-frame table (fr.unit) behind this button, for mouseover binds.
function IchaUI_Dispel_RegisterFrame(btn, fr)
    if not btn then return end
    frames[btn] = fr or true
    applyTo(btn)
end

function IchaUI_Dispel_ApplyClicks()
    local b
    for b in pairs(frames) do applyTo(b) end
end

function IchaUI_Dispel_ModLabel(m)
    local i
    for i = 1, table.getn(IchaUI_DISPEL_MODS) do
        if IchaUI_DISPEL_MODS[i][1] == m then return IchaUI_DISPEL_MODS[i][2] end
    end
    return m or "?"
end

function IchaUI_Dispel_ButtonLabel(b)
    local i
    for i = 1, table.getn(IchaUI_DISPEL_BUTTONS) do
        if IchaUI_DISPEL_BUTTONS[i][1] == b then return IchaUI_DISPEL_BUTTONS[i][2] end
    end
    return b or "?"
end

function IchaUI_Dispel_ClickLabel(action)
    local c = clickOf(action)
    if not c or c.button == "OFF" then return "Off" end
    if c.mod == "NONE" then return IchaUI_Dispel_ButtonLabel(c.button) end
    return IchaUI_Dispel_ModLabel(c.mod) .. "+" .. IchaUI_Dispel_ButtonLabel(c.button)
end

local function side(action)
    if action == "Offensive" then return "enemy" end
    if action == "Smart" then return "both" end
    return "friend"
end

-- Short warning for the options row, or nil.
function IchaUI_Dispel_Conflict(action)
    local c = clickOf(action)
    if not c or c.button == "OFF" then return nil end
    if c.mod == "NONE" and c.button == "LeftButton" then return "Replaces target click" end
    if c.mod == "NONE" and c.button == "RightButton" then return "Replaces unit menu" end
    local mine = side(action)
    local i
    for i = 1, table.getn(IchaUI_DISPEL_ACTIONS) do
        local o = IchaUI_DISPEL_ACTIONS[i]
        if o ~= action and matches(o, c.button, c.mod) then
            local os = side(o)
            local overlap = (mine == "both" or os == "both" or mine == os)
            if overlap then
                if mine == "friend" and os == "friend" then
                    return "Shares with " .. o .. " (Smart order)"
                end
                return "Same click as " .. o
            end
        end
    end
    if type(GetBindingAction) == "function" then
        local key = BUTTON_KEY[c.button]
        if c.mod ~= "NONE" then key = c.mod .. "-" .. key end
        local act = nil
        pcall(function() act = GetBindingAction(key) end)
        if act and act ~= "" then
            local nm = getglobal("BINDING_NAME_" .. act) or act
            return "Keybind " .. nm .. " (frame wins)"
        end
    end
    return nil
end

function IchaUI_Dispel_SetClick(action, field, value)
    local d = IchaUI_DispelDB()
    local c = d.clicks[action]
    if not c then return end
    if field == "button" and validButton(value) then c.button = value end
    if field == "mod" and validMod(value) then c.mod = value end
    if c.mod == "NONE" and (c.button == "LeftButton" or c.button == "RightButton") then
        c.mod = "SHIFT"
    end
    IchaUI_Dispel_ApplyClicks()
end

function IchaUI_Dispel_SetEnabled(on)
    IchaUI_DispelDB().enabled = on and true or false
    IchaUI_Dispel_ApplyClicks()
end

function IchaUI_Dispel_MoveOrder(idx, dir)
    local d = IchaUI_DispelDB()
    local j = idx + dir
    if idx < 1 or idx > 4 or j < 1 or j > 4 then return end
    local o = d.order
    o[idx], o[j] = o[j], o[idx]
end

------------------------------------------------------------------------
-- Key bindings (Bindings.xml)
------------------------------------------------------------------------
local function hoveredFrameUnit()
    if type(GetMouseFocus) ~= "function" then return nil end
    local f = nil
    pcall(function() f = GetMouseFocus() end)
    local depth = 0
    while f and depth < 4 do
        local fr = frames[f]
        if type(fr) == "table" and unitLive(fr.unit) then return fr.unit end
        if not f.GetParent then break end
        f = f:GetParent()
        depth = depth + 1
    end
    return nil
end

function IchaUI_Dispel_Bind(which)
    if IchaUI_LEAVING then return end
    local unit = nil
    if which == "target" then
        unit = "target"
    elseif which == "self" then
        unit = "player"
    elseif which == "mouseover" then
        unit = hoveredFrameUnit()
        if not unit and unitLive("mouseover") then unit = "mouseover" end
    elseif which == "focus" then
        if type(IchaUI_FocusUnit) == "function" then
            local tok = nil
            pcall(function() tok = IchaUI_FocusUnit() end)
            if tokenOk(tok) then unit = tok end
        end
    end
    if not unit or not unitLive(unit) then return end
    IchaUI_Dispel_Smart(unit, true)
end

function IchaUI_Dispel_GetBindKey(cmd)
    if type(GetBindingKey) ~= "function" then return nil end
    local k = GetBindingKey(cmd)
    return k
end

function IchaUI_Dispel_SetBindKey(cmd, key)
    if type(SetBinding) ~= "function" or type(GetBindingKey) ~= "function" then return end
    local k1, k2 = GetBindingKey(cmd)
    if k1 and k1 ~= "" then SetBinding(k1) end
    if k2 and k2 ~= "" then SetBinding(k2) end
    if key and key ~= "" then SetBinding(key, cmd) end
    if SaveBindings then
        local set = GetCurrentBindingSet and GetCurrentBindingSet()
        SaveBindings(set or 1)
    end
end

------------------------------------------------------------------------
-- Rescan on spellbook / pet changes
------------------------------------------------------------------------
IchaUIDispelEvents = CreateFrame("Frame", "IchaUIDispelEvents")
IchaUIDispelEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
IchaUIDispelEvents:RegisterEvent("SPELLS_CHANGED")
IchaUIDispelEvents:RegisterEvent("LEARNED_SPELL_IN_TAB")
IchaUIDispelEvents:RegisterEvent("UNIT_PET")
IchaUIDispelEvents:RegisterEvent("PET_BAR_UPDATE")
IchaUIDispelEvents:SetScript("OnEvent", function()
    if IchaUI_LEAVING then return end
    if event == "UNIT_PET" and arg1 ~= "player" then return end
    IchaUI_Dispel_Rescan()
    if event == "PLAYER_ENTERING_WORLD" then IchaUI_Dispel_ApplyClicks() end
    if IchaUI_DispelOptionsRefresh then IchaUI_DispelOptionsRefresh() end
end)
