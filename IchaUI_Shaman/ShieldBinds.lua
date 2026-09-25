-- IchaUI ShieldBinds: multi-keybind shield casting (Lightning / Water / Earth).
-- Same pattern as ShockBinds: flips shield widget to last cast.
-- Lua 5.0 / Turtle WoW 1.12 safe.

BINDING_HEADER_ICHA = BINDING_HEADER_ICHA or "IchaUI"
BINDING_NAME_ICHA_SHIELDBIND1 = "Shield Bind 1 (Lightning)"
BINDING_NAME_ICHA_SHIELDBIND2 = "Shield Bind 2 (Water)"
BINDING_NAME_ICHA_SHIELDBIND3 = "Shield Bind 3 (Earth)"

local DEFAULT_BINDS = {
    { key = "", spell = "Lightning Shield" },
    { key = "", spell = "Water Shield" },
    { key = "", spell = "Earth Shield" },
}

local function ensureDB()
    if not IchaUIDB then IchaUIDB = {} end
    local sb = IchaUIDB.shieldBinds
    if not sb then
        sb = {
            binds = {
                { key = DEFAULT_BINDS[1].key, spell = DEFAULT_BINDS[1].spell },
                { key = DEFAULT_BINDS[2].key, spell = DEFAULT_BINDS[2].spell },
                { key = DEFAULT_BINDS[3].key, spell = DEFAULT_BINDS[3].spell },
            },
            last = "Lightning Shield",
            defaultsApplied = false,
        }
        IchaUIDB.shieldBinds = sb
    end
    if not sb.binds then sb.binds = {} end
    local i
    for i = 1, 3 do
        if not sb.binds[i] then
            sb.binds[i] = {
                key = DEFAULT_BINDS[i].key,
                spell = DEFAULT_BINDS[i].spell,
            }
        else
            if not sb.binds[i].spell or sb.binds[i].spell == "" then
                sb.binds[i].spell = DEFAULT_BINDS[i].spell
            end
            if sb.binds[i].key == nil then
                sb.binds[i].key = DEFAULT_BINDS[i].key
            end
        end
    end
    if not sb.last or sb.last == "" then
        sb.last = sb.binds[1].spell or "Lightning Shield"
    end
    return sb
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

local function isButtonMouseKey(key)
    if not key or key == "" then return false end
    return string.find(string.upper(key), "BUTTON%d") and true or false
end
local function isWheelKey(key)
    if not key or key == "" then return false end
    return string.find(string.upper(key), "MOUSEWHEEL", 1, true) and true or false
end
local function isMouseKey(key)
    return isButtonMouseKey(key) or isWheelKey(key)
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

local function unregisterMouseChord(key)
    if not key or key == "" then return end
    if IchaUI_MouseChordActions then
        IchaUI_MouseChordActions[string.upper(key)] = nil
    end
end

local function registerMouseChord(key, n)
    if not key or key == "" or not isMouseKey(key) then return end
    IchaUI_MouseChordActions = IchaUI_MouseChordActions or {}
    local slot = n
    IchaUI_MouseChordActions[string.upper(key)] = function()
        IchaUI_ShieldBindFire(slot)
    end
end

local function rebuildMouseChords(sb)
    local i
    for i = 1, 3 do
        local k = sb.binds[i] and sb.binds[i].key
        if k and k ~= "" and isMouseKey(k) then
            registerMouseChord(k, i)
        end
    end
end

function IchaUIShieldBinds_ApplyKey(n, key)
    n = tonumber(n) or 1
    if n < 1 then n = 1 end
    if n > 3 then n = 3 end
    local sb = ensureDB()
    local old = sb.binds[n].key
    if old and old ~= "" then
        unregisterMouseChord(old)
    end
    if not key then key = "" end
    key = string.gsub(key, "^%s+", "")
    key = string.gsub(key, "%s+$", "")
    if key ~= "" then
        key = string.upper(key)
    end
    sb.binds[n].key = key
    local cmd = "ICHA_SHIELDBIND" .. n
    clearCmdKeys(cmd)
    if key ~= "" and (not isButtonMouseKey(key)) and SetBinding then
        SetBinding(key, cmd)
    end
    if key ~= "" and isMouseKey(key) then
        registerMouseChord(key, n)
    end
    saveBindSet()
    return key
end

function IchaUIShieldBinds_GetKey(n)
    n = tonumber(n) or 1
    local sb = ensureDB()
    local cmd = "ICHA_SHIELDBIND" .. n
    if GetBindingKey then
        local live = GetBindingKey(cmd)
        if live and live ~= "" then
            sb.binds[n].key = live
            return live
        end
    end
    local k = sb.binds[n] and sb.binds[n].key
    if k and k ~= "" then return k end
    return ""
end

function IchaUIShieldBinds_GetSpell(n)
    n = tonumber(n) or 1
    local sb = ensureDB()
    return (sb.binds[n] and sb.binds[n].spell) or DEFAULT_BINDS[n].spell
end

local lastFireAt = 0
local lastFireN = 0

function IchaUI_ShieldBindFire(n)
    n = tonumber(n) or 1
    if n < 1 then n = 1 end
    if n > 3 then n = 3 end
    local now = GetTime and GetTime() or 0
    if n == lastFireN and (now - lastFireAt) < 0.12 then
        return
    end
    lastFireAt = now
    lastFireN = n
    local sb = ensureDB()
    local bind = sb.binds[n]
    if not bind or not bind.spell then return end
    local spell = bind.spell
    if IchaUIShamanExtras_PulsePush then
        IchaUIShamanExtras_PulsePush("shield")
    end
    castSpell(spell)
    sb.last = spell
    if IchaUIShamanExtras_OnShieldBoundCast then
        IchaUIShamanExtras_OnShieldBoundCast(spell)
    end
end

local function applyDefaultBindings(sb)
    local i
    for i = 1, 3 do
        local key = sb.binds[i].key or ""
        IchaUIShieldBinds_ApplyKey(i, key)
    end
    sb.defaultsApplied = true
    rebuildMouseChords(sb)
end

function IchaUIShieldBinds_Slash(msg)
    local sb = ensureDB()
    DEFAULT_CHAT_FRAME:AddMessage("IchaUI shield binds:")
    local i
    for i = 1, 3 do
        local b = sb.binds[i]
        local key = IchaUIShieldBinds_GetKey(i)
        if not key or key == "" then key = "(unset)" end
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  %d) %s → %s", i, key, b.spell or "?"))
    end
    DEFAULT_CHAT_FRAME:AddMessage("  last: " .. tostring(sb.last or "?"))
    DEFAULT_CHAT_FRAME:AddMessage("  Rebind in /iui → Bars.")
end

local evt = CreateFrame("Frame", "IchaUIShieldBindsEvent")
evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("PLAYER_ENTERING_WORLD")
evt:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        local sb = ensureDB()
        applyDefaultBindings(sb)
        -- Ensure WorldFrame mouse hook exists (ShockBinds owns it)
        if IchaUIShockBinds_MouseHooked then
            -- ok
        elseif WorldFrame then
            -- Soft-ensure shared table; ShockBinds hook also reads it
            IchaUI_MouseChordActions = IchaUI_MouseChordActions or {}
        end
    end
end)

function IchaUIShieldBinds_Reload()
    applyDefaultBindings(ensureDB())
end
