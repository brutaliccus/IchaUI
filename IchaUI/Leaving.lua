-- IchaUI leaving-world guard. Lua 5.0 / WoW 1.12 (RavenCraft)
-- SuperWoW resolves GUID unit tokens straight through the object manager. Once logout or
-- exit starts, that manager is torn down and a GUID lookup is a native crash (#132 at
-- 0x004648AC); pcall cannot catch it. Every GUID poller checks IchaUI_LEAVING first.

IchaUI_LEAVING = false

local handlers = {}
local pendingAt = nil
local confirmed = false

-- fn(true) when leaving starts, fn(false) when the world is back.
function IchaUI_OnLeaving(fn)
    if type(fn) ~= "function" then return end
    table.insert(handlers, fn)
end

local function setLeaving(on)
    on = on and true or false
    if not on then
        pendingAt = nil
        confirmed = false
    end
    if IchaUI_LEAVING == on then return end
    IchaUI_LEAVING = on
    local i
    for i = 1, table.getn(handlers) do
        pcall(handlers[i], on)
    end
end
IchaUI_SetLeaving = setLeaving

local ev = CreateFrame("Frame", "IchaUILeavingGuard")
ev:RegisterEvent("PLAYER_LEAVING_WORLD")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(function() ev:RegisterEvent("PLAYER_CAMPING") end)
pcall(function() ev:RegisterEvent("PLAYER_QUITING") end)
pcall(function() ev:RegisterEvent("LOGOUT_CANCEL") end)
ev:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" or event == "LOGOUT_CANCEL" then
        setLeaving(false)
        return
    end
    confirmed = true
    setLeaving(true)
end)

-- Logout()/Quit() can be refused (combat, etc.) without any event. If neither
-- PLAYER_CAMPING/QUITING nor PLAYER_LEAVING_WORLD follows, resume.
ev:SetScript("OnUpdate", function()
    if not pendingAt or confirmed then return end
    if (GetTime() - pendingAt) > 1.5 then
        setLeaving(false)
    end
end)

local function armFromCall()
    if UnitAffectingCombat and UnitAffectingCombat("player") then return end
    pendingAt = GetTime()
    confirmed = false
    setLeaving(true)
end

local _Logout = Logout
if _Logout then
    Logout = function()
        armFromCall()
        return _Logout()
    end
end

local _Quit = Quit
if _Quit then
    Quit = function()
        armFromCall()
        return _Quit()
    end
end

-- /camp or /quit cancelled via the popup: 1.12 sends no LOGOUT_CANCEL, so
-- without this the flag stays true and every guarded handler stays muted.
local _CancelLogout = CancelLogout
if _CancelLogout then
    CancelLogout = function()
        setLeaving(false)
        return _CancelLogout()
    end
end

local _ForceQuit = ForceQuit
if _ForceQuit then
    ForceQuit = function()
        pendingAt = GetTime()
        confirmed = true
        setLeaving(true)
        return _ForceQuit()
    end
end
