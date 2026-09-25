-- IchaUI ShockBinds: shared WorldFrame mouse chord hook (hero, shield, totems).
-- The old top-left Earth/Frost/Flame button is not applied anymore.
-- Set those spells on any hero button in /iui → Hero → Hero setup.
-- Lua 5.0 / Turtle WoW 1.12 safe.

BINDING_HEADER_ICHA = BINDING_HEADER_ICHA or "IchaUI"
BINDING_NAME_ICHA_SHOCKBIND1 = "Shock Bind 1 (Earth)"
BINDING_NAME_ICHA_SHOCKBIND2 = "Shock Bind 2 (Frost)"
BINDING_NAME_ICHA_SHOCKBIND3 = "Shock Bind 3 (Flame)"

local HERO_BAR = 7
local PUSH_MS = 0.12
local pushUntil = 0
local pushBtnId = nil

-- Mouse chord → slot (only BUTTON* keys; keyboard uses SetBinding)
local mouseChordSlot = {}

local function ensureDB()
    if not IchaUIDB then IchaUIDB = {} end
    local sb = IchaUIDB.shockBinds
    if not sb then
        sb = {
            binds = {
                { key = "", spell = "" },
                { key = "", spell = "" },
                { key = "", spell = "" },
            },
            last = "",
            releasedToHero = false,
        }
        IchaUIDB.shockBinds = sb
    end
    if not sb.binds then sb.binds = {} end
    local i
    for i = 1, 3 do
        if not sb.binds[i] then
            sb.binds[i] = { key = "", spell = "" }
        end
    end
    return sb
end

local function barStart(barId)
    if BActionBar and BActionBar.GetStart then
        return BActionBar.GetStart(barId)
    end
    local n = (BActionSets and BActionSets.g and BActionSets.g.numActionBars) or 10
    return math.floor(120 / n) * (barId - 1) + 1
end

-- placeGrid fills bottom-up: ids[1]=bottom-left, ids[5]=top-left in a 4x2 hero grid
local HERO_TOPLEFT_OFFSET = 4

local function heroButtonId()
    if IchaUI_HeroButtonId and IchaUI_HeroTopLeftSlot then
        local id = IchaUI_HeroButtonId(IchaUI_HeroTopLeftSlot())
        if id then return id end
    end
    return barStart(HERO_BAR) + HERO_TOPLEFT_OFFSET
end

local function pagedId(buttonId)
    if BActionButton and BActionButton.GetPagedID then
        return BActionButton.GetPagedID(buttonId)
    end
    return buttonId
end

local function findSpell(spellName)
    if not spellName or spellName == "" or not GetSpellName then
        return nil
    end
    local book = BOOKTYPE_SPELL or "spell"
    local want = string.lower(spellName)
    local best = nil
    local i = 1
    while i <= 500 do
        local name, rank = GetSpellName(i, book)
        if not name then break end
        if string.lower(name) == want then
            local tex = nil
            if GetSpellTexture then
                tex = GetSpellTexture(i, book)
            end
            best = { name = name, rank = rank, index = i, texture = tex }
        end
        i = i + 1
    end
    return best
end

local function castSpell(spellName)
    local entry = findSpell(spellName)
    local book = BOOKTYPE_SPELL or "spell"
    if entry and entry.index and CastSpell then
        CastSpell(entry.index, book)
        return entry
    end
    if CastSpellByName then
        local castName = spellName
        if entry and entry.name then
            castName = entry.name
            if entry.rank and entry.rank ~= "" then
                castName = entry.name .. "(" .. entry.rank .. ")"
            end
        end
        CastSpellByName(castName)
        return entry or { name = spellName }
    end
    return nil
end

local function overlayIcon(buttonId, texture)
    if not texture then return end
    local b = getglobal("IchaUIBtn" .. tostring(buttonId))
    if b and b.icon then
        if IchaUI_SetButtonIcon then
            IchaUI_SetButtonIcon(b, texture)
        else
            b.icon:SetTexture(texture)
        end
        b.icon:Show()
        b.icon:SetAlpha(1)
    end
end

local function placeSpellOnHero(entry)
    local btnId = heroButtonId()
    local actionId = pagedId(btnId)
    local placed = false
    if entry and entry.index and PickupSpell and PlaceAction then
        local book = BOOKTYPE_SPELL or "spell"
        ClearCursor()
        PickupSpell(entry.index, book)
        PlaceAction(actionId)
        ClearCursor()
        placed = true
    end
    if entry and entry.texture then
        overlayIcon(btnId, entry.texture)
    end
    return btnId
end

local function doPush(buttonId)
    if pushButton then
        pushButton(buttonId)
        pushBtnId = buttonId
        pushUntil = (GetTime and GetTime() or 0) + PUSH_MS
    end
end

-- BUTTON* → WorldFrame chord only (SetBinding flaky for ALT-BUTTONn).
-- MOUSEWHEEL* → SetBinding (global) + WorldFrame chord backup.
local function isButtonMouseKey(key)
    if not key then return false end
    return string.find(string.upper(key), "BUTTON%d") and true or false
end
local function isWheelKey(key)
    if not key then return false end
    return string.find(string.upper(key), "MOUSEWHEEL", 1, true) and true or false
end
local function isMouseKey(key)
    return isButtonMouseKey(key) or isWheelKey(key)
end

local function rebuildMouseChords(sb)
    mouseChordSlot = {}
    local i
    for i = 1, 3 do
        local k = sb.binds[i] and sb.binds[i].key
        if k and isMouseKey(k) then
            mouseChordSlot[string.upper(k)] = i
        end
    end
end

local function clearCmdKeys(cmd)
    if not GetBindingKey then return end
    local k1, k2 = GetBindingKey(cmd)
    if k1 and k1 ~= "" then SetBinding(k1) end
    if k2 and k2 ~= "" then SetBinding(k2) end
end

local function saveBindSet()
    if SaveBindings and GetCurrentBindingSet then
        SaveBindings(GetCurrentBindingSet())
    elseif SaveBindings then
        SaveBindings(1)
    end
end

-- Apply one slot's key to the game binding table (+ mouse chord table)
function IchaUIShockBinds_ApplyKey(n, key)
    n = tonumber(n) or 1
    if n < 1 then n = 1 end
    if n > 3 then n = 3 end
    local sb = ensureDB()
    if not key or key == "" then
        key = ""
    else
        key = string.upper(key)
    end
    sb.binds[n].key = key
    local cmd = "ICHA_SHOCKBIND" .. n
    clearCmdKeys(cmd)
    -- BUTTON*: WorldFrame chord only. Wheel/keyboard: SetBinding (+ chord backup for wheel).
    if key ~= "" and (not isButtonMouseKey(key)) and SetBinding then
        SetBinding(key, cmd)
    end
    saveBindSet()
    rebuildMouseChords(sb)
    return key
end

function IchaUIShockBinds_GetKey(n)
    n = tonumber(n) or 1
    local sb = ensureDB()
    local cmd = "ICHA_SHOCKBIND" .. n
    if GetBindingKey then
        local live = GetBindingKey(cmd)
        if live and live ~= "" then
            sb.binds[n].key = live
            return live
        end
    end
    return (sb.binds[n] and sb.binds[n].key) or ""
end

function IchaUIShockBinds_GetSpell(n)
    n = tonumber(n) or 1
    local sb = ensureDB()
    return (sb.binds[n] and sb.binds[n].spell) or ""
end

local lastShockFireAt = 0
local lastShockFireN = 0

local function heroHasSpell(entry)
    if not entry or not entry.texture then return false end
    if type(GetActionTexture) ~= "function" then return false end
    local tex = GetActionTexture(pagedId(heroButtonId()))
    return tex and tex == entry.texture
end

function IchaUI_ShockBindFire(n)
    -- Retired. Hero setup owns every hero button, including the old shock corner.
    return
end

local function syncKeysFromBindings(sb)
    local i
    for i = 1, 3 do
        local cmd = "ICHA_SHOCKBIND" .. i
        if GetBindingKey then
            local k1 = GetBindingKey(cmd)
            if k1 and k1 ~= "" then
                sb.binds[i].key = k1
            end
        end
    end
    rebuildMouseChords(sb)
end

local function releaseShockKeys()
    local sb = ensureDB()
    mouseChordSlot = {}
    if sb.releasedToHero then return end
    local i
    for i = 1, 3 do
        clearCmdKeys("ICHA_SHOCKBIND" .. i)
        if sb.binds[i] then
            sb.binds[i].key = ""
            sb.binds[i].spell = ""
        end
    end
    sb.last = ""
    saveBindSet()
    sb.releasedToHero = true
end

function IchaUIShockBinds_Slash(msg)
    DEFAULT_CHAT_FRAME:AddMessage("IchaUI: shock binds are off. Set every hero button in /iui → Hero → Hero setup.")
end

-- Map WorldFrame OnMouseDown arg1 → BUTTON n
local MOUSE_BTN = {
    LeftButton = "BUTTON1",
    RightButton = "BUTTON2",
    MiddleButton = "BUTTON3",
    Button4 = "BUTTON4",
    Button5 = "BUTTON5",
    BUTTON4 = "BUTTON4",
    BUTTON5 = "BUTTON5",
}

local function chordFromMouseArg(btn)
    local base = MOUSE_BTN[btn]
    if not base then return nil end
    -- Don't steal plain left/right click
    if base == "BUTTON1" or base == "BUTTON2" then
        if not (IsAltKeyDown() or IsControlKeyDown() or IsShiftKeyDown()) then
            return nil
        end
    end
    local full = base
    if IsShiftKeyDown() then full = "SHIFT-" .. full end
    if IsControlKeyDown() then full = "CTRL-" .. full end
    if IsAltKeyDown() then full = "ALT-" .. full end
    return string.upper(full)
end


local function fireIchaBindingAction(action)
    if not action or action == "" then return false end
    if string.find(action, "ICHA_HEROBIND", 1, true) == 1 then
        local n = tonumber(string.sub(action, 14))
        if n and IchaUI_HeroBindFire then IchaUI_HeroBindFire(n); return true end
    end
    if string.find(action, "ICHA_SHIELDBIND", 1, true) == 1 then
        local n = tonumber(string.sub(action, 16))
        if n and IchaUI_ShieldBindFire then IchaUI_ShieldBindFire(n); return true end
    end
    if string.find(action, "ICHA_TOTEMCAST", 1, true) == 1 then
        local n = tonumber(string.sub(action, 14))
        if n and IchaUITotems_SpellBindFire then IchaUITotems_SpellBindFire(n); return true end
    end
    if action == "ICHA_TOTEMBIND_EARTH" and IchaUITotems_SlotBindFire then
        IchaUITotems_SlotBindFire("earth"); return true
    end
    if action == "ICHA_TOTEMBIND_FIRE" and IchaUITotems_SlotBindFire then
        IchaUITotems_SlotBindFire("fire"); return true
    end
    if action == "ICHA_TOTEMBIND_WATER" and IchaUITotems_SlotBindFire then
        IchaUITotems_SlotBindFire("water"); return true
    end
    if action == "ICHA_TOTEMBIND_AIR" and IchaUITotems_SlotBindFire then
        IchaUITotems_SlotBindFire("air"); return true
    end
    if action == "ICHA_THROWTOTEMS" and IchaUITotems_ThrowSet then
        IchaUITotems_ThrowSet(); return true
    end
    if string.find(action, "ICHA_THROWTOTEMSET", 1, true) == 1 then
        local n = tonumber(string.sub(action, 19))
        if n and IchaUITotems_ThrowSetN then IchaUITotems_ThrowSetN(n); return true end
    end
    return false
end

local function buildWheelChordKeys(dir)
    local base = (dir > 0) and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
    local sh = IsShiftKeyDown and IsShiftKeyDown()
    local ct = IsControlKeyDown and IsControlKeyDown()
    local al = IsAltKeyDown and IsAltKeyDown()
    local keys = {}
    local function add(k)
        k = string.upper(k)
        local i
        for i = 1, table.getn(keys) do
            if keys[i] == k then return end
        end
        table.insert(keys, k)
    end
    -- SHIFT → CTRL → ALT (same as capture)
    do
        local full = base
        if sh then full = "SHIFT-" .. full end
        if ct then full = "CTRL-" .. full end
        if al then full = "ALT-" .. full end
        add(full)
    end
    -- ALT → CTRL → SHIFT (Blizzard-ish)
    do
        local full = base
        if al then full = "ALT-" .. full end
        if ct then full = "CTRL-" .. full end
        if sh then full = "SHIFT-" .. full end
        add(full)
    end
    add(base)
    return keys
end

local function fireFromWheelKey(full)
    if not full then return false end
    full = string.upper(full)
    local handled = false
    if IchaUI_MouseChordActions and IchaUI_MouseChordActions[full] then
        IchaUI_MouseChordActions[full]()
        handled = true
    end
    if type(GetBindingAction) == "function" then
        local ok, action = pcall(GetBindingAction, full)
        if ok and fireIchaBindingAction(action) then
            handled = true
        end
    end
    return handled
end

-- Scan saved bind strings (chord table / SetBinding can miss on some 1.12 clients)
local function fireFromSavedWheelBinds(full)
    if not full then return false end
    full = string.upper(full)
    if IchaUI_HeroChordFire and IchaUI_HeroChordFire(full) then
        return true
    end
    -- Shield: IchaUIDB.shieldBinds.binds[i].key
    if IchaUIDB and IchaUIDB.shieldBinds and IchaUIDB.shieldBinds.binds and IchaUI_ShieldBindFire then
        local i
        for i = 1, 3 do
            local b = IchaUIDB.shieldBinds.binds[i]
            local k = b and b.key
            if k and k ~= "" and string.upper(k) == full then
                IchaUI_ShieldBindFire(i)
                return true
            end
        end
    end
    -- Per-totem: prefer ListSpellBinds, else raw DB
    if IchaUITotems_ListSpellBinds then
        local list = IchaUITotems_ListSpellBinds()
        local i
        for i = 1, table.getn(list) do
            local e = list[i]
            if e and e.key and e.key ~= "" and string.upper(e.key) == full then
                if IchaUITotems_SpellBindFire then
                    IchaUITotems_SpellBindFire(e.index)
                    return true
                end
            end
        end
    elseif IchaUIDB and IchaUIDB.totems and IchaUIDB.totems.spellBinds and IchaUITotems_SpellBindFire then
        -- fallback raw map base→key (index unknown — skip)
    end
    -- Slot binds: IchaUIDB.totems.slotBinds[el]
    if IchaUIDB and IchaUIDB.totems and IchaUIDB.totems.slotBinds and IchaUITotems_SlotBindFire then
        local els = { "earth", "fire", "water", "air" }
        local i
        for i = 1, 4 do
            local el = els[i]
            local k = IchaUIDB.totems.slotBinds[el]
            if k and k ~= "" and string.upper(k) == full then
                IchaUITotems_SlotBindFire(el)
                return true
            end
        end
    end
    return false
end

function IchaUI_FireWheelBind(dir)
    dir = tonumber(dir) or 0
    if dir == 0 then return false end
    local keys = buildWheelChordKeys(dir)
    local i
    for i = 1, table.getn(keys) do
        local full = keys[i]
        if fireFromWheelKey(full) then return true end
        if fireFromSavedWheelBinds(full) then return true end
    end
    return false
end

local function hookWorldMouse()
    if IchaUIShockBinds_MouseHooked then return end
    if not WorldFrame then return end
    IchaUIShockBinds_MouseHooked = true
    local prev = WorldFrame.GetScript and WorldFrame:GetScript("OnMouseDown")
    WorldFrame:SetScript("OnMouseDown", function()
        -- Look-click only. Totemic Recall uses its own button OnClick (hardware).
        if prev then prev() end
        local chord = chordFromMouseArg(arg1)
        if not chord then return end
        if IchaUI_HeroChordFire then
            IchaUI_HeroChordFire(chord)
        end
        -- Throw-set mouse chord (Totems registers into this global table)
        if IchaUI_MouseChordActions and IchaUI_MouseChordActions[chord] then
            IchaUI_MouseChordActions[chord]()
        end
    end)
    local prevUp = WorldFrame.GetScript and WorldFrame:GetScript("OnMouseUp")
    WorldFrame:SetScript("OnMouseUp", function()
        if prevUp then prevUp() end
    end)
    -- Do NOT hook OnMouseWheel here.
    -- Any WorldFrame OnMouseWheel script swallows the event so SetBinding(MOUSEWHEEL*)
    -- never runs a real keybind cast (CastSpell from the hook also fails to stick).
    -- Wheel binds use SetBinding only; BUTTON* chords stay on OnMouseDown above.
end

-- Shared mouse-chord registry (throw bind + anything else)
IchaUI_MouseChordActions = IchaUI_MouseChordActions or {}

local evt = CreateFrame("Frame", "IchaUIShockBindsEvent")
evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("PLAYER_ENTERING_WORLD")
evt:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        releaseShockKeys()
        hookWorldMouse()
    end
end)

evt:SetScript("OnUpdate", function()
    if not pushBtnId then return end
    local now = GetTime and GetTime() or 0
    if now >= pushUntil then
        if releaseButton then
            releaseButton(pushBtnId)
        end
        pushBtnId = nil
    end
end)
