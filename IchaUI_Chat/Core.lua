-- IchaUI Chat core: settings (IchaUIDB.chat), a one-shot timer, and the
-- module lifecycle (init / login / world).

IchaUIChat = IchaUIChat or {}
local M = IchaUIChat

M.modules = {}
M.ready = false

BINDING_HEADER_ICHAUICHAT = "IchaUI Chat"
BINDING_NAME_ICHAUICHAT_COPY = "Copy chat (selected window)"

function M.Print(msg)
    local f = DEFAULT_CHAT_FRAME or getglobal("ChatFrame1")
    if f then f:AddMessage("|cffe8c35aIchaUI Chat:|r " .. (msg or "")) end
end

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------
-- Live data, not settings: kept when a profile load swaps IchaUIDB.
local RUNTIME = {
    { "history", "data" }, { "names", "cache" }, { "dock", "snapshots" }, { "dock", "hostId" },
}

function M.db()
    if not IchaUIDB then IchaUIDB = {} end
    if type(IchaUIDB.chat) ~= "table" then IchaUIDB.chat = {} end
    local c = IchaUIDB.chat
    if c ~= M._dbRef then
        local old = M._dbRef
        M._dbRef = c
        local baked = IchaUI_BakedDefaults and IchaUI_BakedDefaults.chat
        if baked and IchaUI_BakedFill then IchaUI_BakedFill(c, baked, nil) end
        if type(old) == "table" then
            local i
            for i = 1, table.getn(RUNTIME) do
                local s, k = RUNTIME[i][1], RUNTIME[i][2]
                if type(old[s]) == "table" and old[s][k] ~= nil then
                    if type(c[s]) ~= "table" then c[s] = {} end
                    c[s][k] = old[s][k]
                end
            end
        end
    end
    return c
end

-- IchaUI_ProfileLoad calls this after replacing IchaUIDB.
function IchaUIChat_Reload()
    M.db()
    M.ApplyAll()
end

function M.C(section)
    local c = M.db()
    if type(c[section]) ~= "table" then c[section] = {} end
    return c[section]
end

-- Per-window flag table lookup; missing entries count as on.
function M.winOn(tbl, id)
    if type(tbl) ~= "table" then return true end
    local v = tbl[id]
    if v == nil then return true end
    return v and true or false
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
-- Saved lists: table.getn can read 0 on a list loaded from SavedVariables,
-- so count, append and trim them by index.
function M.count(t)
    if type(t) ~= "table" then return 0 end
    local n = 0
    while t[n + 1] ~= nil do n = n + 1 end
    return n
end

function M.append(t, v)
    t[M.count(t) + 1] = v
end

-- Keeps the last `cap` entries; returns a new list.
function M.keepLast(t, cap)
    local n = M.count(t)
    local out = {}
    local first = n - cap + 1
    if first < 1 then first = 1 end
    local i
    for i = first, n do out[i - first + 1] = t[i] end
    return out
end

-- Removes entry `idx`; returns a new list.
function M.without(t, idx)
    local out = {}
    local n = M.count(t)
    local i
    for i = 1, n do
        if i ~= idx then out[M.count(out) + 1] = t[i] end
    end
    return out
end

local function clamp01(v)
    v = tonumber(v) or 1
    if v < 0 then v = 0 end
    if v > 1 then v = 1 end
    return v
end

function M.hex(r, g, b)
    if type(r) == "table" then r, g, b = r.r, r.g, r.b end
    return string.format("|cff%02x%02x%02x",
        math.floor(clamp01(r) * 255 + 0.5),
        math.floor(clamp01(g) * 255 + 0.5),
        math.floor(clamp01(b) * 255 + 0.5))
end

function M.numWindows()
    return NUM_CHAT_WINDOWS or 7
end

function M.frame(i)
    return getglobal("ChatFrame" .. i)
end

-- Combat-log style windows (mostly SPELL / COMBAT groups) stay untouched.
function M.isCombatFrame(cf)
    if not cf then return true end
    if cf == getglobal("ChatFrame2") then return true end
    local list = cf.messageTypeList
    if type(list) ~= "table" then return false end
    local n, k, v = 0
    for k, v in pairs(list) do
        if type(v) == "string" and (string.find(v, "SPELL", 1, true) or string.find(v, "COMBAT", 1, true)) then
            n = n + 1
        end
    end
    return n > 5
end

function M.selectedFrame()
    return SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME or getglobal("ChatFrame1")
end

-- The docked tab on screen. Differs from selectedFrame on a meter tab,
-- where the edit box keeps SELECTED_CHAT_FRAME on the last chat tab.
function M.shownFrame()
    local s = SELECTED_DOCK_FRAME
    if s and s.IsVisible and s:IsVisible() then return s end
    local i
    for i = 1, M.numWindows() do
        local cf = M.frame(i)
        if cf and cf.isDocked and cf:IsVisible() then return cf end
    end
    return M.selectedFrame()
end

------------------------------------------------------------------------
-- One-shot timers
------------------------------------------------------------------------
local timers = {}
local timerFrame = CreateFrame("Frame")
timerFrame:Hide()
timerFrame:SetScript("OnUpdate", function()
    local now = GetTime()
    local i = 1
    while i <= table.getn(timers) do
        local t = timers[i]
        if now >= t.at then
            table.remove(timers, i)
            local ok = pcall(t.fn)
            if not ok and M.debug then M.Print("timer error") end
        else
            i = i + 1
        end
    end
    if table.getn(timers) == 0 then this:Hide() end
end)

function M.After(sec, fn)
    table.insert(timers, { at = GetTime() + (tonumber(sec) or 0), fn = fn })
    timerFrame:Show()
end

------------------------------------------------------------------------
-- Modules: M.Register(name, { init=, login=, world=, apply= })
------------------------------------------------------------------------
function M.Register(name, mod)
    mod.name = name
    table.insert(M.modules, mod)
    M[name] = mod
    return mod
end

local function runAll(stage)
    local i
    for i = 1, table.getn(M.modules) do
        local mod = M.modules[i]
        local fn = mod[stage]
        if fn then
            local ok = pcall(fn, mod)
            if not ok then M.Print("error in " .. (mod.name or "?") .. "." .. stage) end
        end
    end
end

-- Re-apply every module after a config change.
function M.ApplyAll()
    runAll("apply")
end

function M.Apply(name)
    local mod = M[name]
    if mod and mod.apply then pcall(mod.apply, mod) end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" then
        if arg1 ~= "IchaUI_Chat" then return end
        M.db()
        runAll("init")
    elseif event == "PLAYER_LOGIN" then
        M.db()
        M.ready = true
        runAll("login")
    elseif event == "PLAYER_ENTERING_WORLD" then
        runAll("world")
    end
end)
