-- IchaUI leaving-world guard. Lua 5.0 / WoW 1.12 (RavenCraft)
-- SuperWoW GUID lookups crash after the object manager is torn down (#132 at
-- 0x004648AC). Party/raid UnitExists/UnitName on partyN / partyNtarget hit a
-- freed SGroupPtr (0x8510007c). pcall cannot catch either. Logout()/Quit()
-- set IchaUI_LEAVING and freeze tickers BEFORE the native teardown. Every
-- poller checks IchaUI_LEAVING first. New tickers call IchaUI_LeavingHold.

IchaUI_LEAVING = false

local handlers = {}
local held = {}
local pendingAt = nil
local confirmed = false

-- fn(true) when leaving starts, fn(false) when the world is back.
function IchaUI_OnLeaving(fn)
    if type(fn) ~= "function" then return end
    table.insert(handlers, fn)
end

-- Register a ticker so Logout()/Quit() can nil OnUpdate before C++ teardown.
-- onUpdate is restored on CancelLogout / PLAYER_ENTERING_WORLD.
function IchaUI_LeavingHold(frame, onUpdate)
    if not frame then return end
    local i
    for i = 1, table.getn(held) do
        if held[i].frame == frame then
            if type(onUpdate) == "function" then
                held[i].fn = onUpdate
            end
            return
        end
    end
    table.insert(held, { frame = frame, fn = onUpdate })
end

local function hideNamed(name)
    local f = getglobal(name)
    if f and f.Hide then f:Hide() end
end

-- No Unit*. Hide party/ToT/P.ToT/raid roots and their UIParent chrome.
local function hideGroupFrames()
    hideNamed("IchaUIUF_PartyRoot")
    hideNamed("IchaUIUF_RaidRoot")
    hideNamed("IchaUIUF_tot")
    hideNamed("IchaUIUF_tot_AzeriteRing")
    hideNamed("IchaUIUF_tot_Badge")
    local i
    for i = 1, 4 do
        hideNamed("IchaUIUF_party" .. i)
        hideNamed("IchaUIUF_party" .. i .. "_AzeriteRing")
        hideNamed("IchaUIUF_party" .. i .. "_Badge")
        hideNamed("IchaUIUF_ptot" .. i)
        hideNamed("IchaUIUF_ptot" .. i .. "_AzeriteRing")
        hideNamed("IchaUIUF_ptot" .. i .. "_Badge")
    end
    for i = 1, 40 do
        hideNamed("IchaUIUF_raid" .. i)
    end
end

local function freezeWorld()
    local i
    for i = 1, table.getn(held) do
        local h = held[i]
        if h.frame then
            h.frame:SetScript("OnUpdate", nil)
        end
    end
    hideGroupFrames()
end

local function thawWorld()
    local i
    for i = 1, table.getn(held) do
        local h = held[i]
        if h.frame and type(h.fn) == "function" then
            h.frame:SetScript("OnUpdate", h.fn)
        end
    end
end

local function notify(on)
    local i
    for i = 1, table.getn(handlers) do
        pcall(handlers[i], on)
    end
end

local function setLeaving(on)
    on = on and true or false
    if not on then
        pendingAt = nil
        confirmed = false
    end
    if IchaUI_LEAVING == on then return end
    -- Flag first so any in-flight OnUpdate bails before Unit*.
    IchaUI_LEAVING = on
    if on then
        freezeWorld()
    else
        thawWorld()
    end
    notify(on)
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
