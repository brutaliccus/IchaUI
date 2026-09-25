-- IchaUI Chat tabs, fonts, fading and channel color memory.
-- Tabs: ChatSkin.lua owns the tab art; this only dims inactive tab labels
-- (FontString alpha, which neither FCF nor ChatSkin touches), flashes the
-- selected tab on whisper, and picks the tab to select at login.

local M = IchaUIChat
local T = M.Register("Tabs", {})

T.FONTS = {
    { "Keep current", nil },
    { "Friz Quadrata", "Fonts\\FRIZQT__.TTF" },
    { "Arial Narrow", "Fonts\\ARIALN.TTF" },
    { "Skurri", "Fonts\\skurri.ttf" },
    { "Morpheus", "Fonts\\MORPHEUS.ttf" },
}
-- IchaUI media fonts go here as { label, path } (IchaUI\media ships none yet).
if type(IchaUIChat_ExtraFonts) == "table" then
    local i
    for i = 1, table.getn(IchaUIChat_ExtraFonts) do table.insert(T.FONTS, IchaUIChat_ExtraFonts[i]) end
end

local function isHost(cf)
    return M.Dock and M.Dock.isHost and M.Dock.isHost(cf)
end

------------------------------------------------------------------------
-- Tabs
------------------------------------------------------------------------
local function tabText(i)
    local tab = getglobal("ChatFrame" .. i .. "Tab")
    return tab and getglobal(tab:GetName() .. "Text")
end

function T.paintTabs()
    local c = M.C("tabs")
    local sel = M.selectedFrame()
    local a = tonumber(c.inactiveAlpha) or 0.5
    local i
    for i = 1, M.numWindows() do
        local fs = tabText(i)
        local cf = M.frame(i)
        if fs and cf then
            if c.on and cf.isDocked and cf ~= sel then
                fs:SetAlpha(a)
                fs._icDim = true
            elseif fs._icDim or c.on then
                fs:SetAlpha(1)
                fs._icDim = nil
            end
        end
    end
end

local tabQ = CreateFrame("Frame")
tabQ:Hide()
tabQ:SetScript("OnUpdate", function()
    this:Hide()
    T.paintTabs()
end)

local function queueTabs()
    tabQ:Show()
end

local function hookTabs()
    if T._hooked then return end
    T._hooked = true
    local names = { "FCF_Tab_OnClick", "FCF_SelectDockFrame", "FCF_DockUpdate", "FCF_DockFrame", "FCF_UnDockFrame" }
    local i
    for i = 1, table.getn(names) do
        local fname = names[i]
        local old = getglobal(fname)
        if type(old) == "function" then
            setglobal(fname, function(a1, a2, a3, a4)
                local r = old(a1, a2, a3, a4)
                queueTabs()
                return r
            end)
        end
    end
end

function T.flashSelected()
    local cf = M.selectedFrame()
    if not cf or not cf:IsVisible() then return end
    local flash = getglobal(cf:GetName() .. "TabFlash")
    if not flash then return end
    if UIFrameFlash then
        UIFrameFlash(flash, 0.25, 0.25, 1.6, nil, 0.1, 0.1)
    else
        flash:Show()
        M.After(1.2, function() flash:Hide() end)
    end
end

function T.selectLoginTab()
    local id = tonumber(M.C("tabs").loginTab) or 0
    if id < 1 then return end
    local cf = M.frame(id)
    if cf and cf.isDocked and FCF_SelectDockFrame then
        FCF_SelectDockFrame(cf)
    end
end

------------------------------------------------------------------------
-- Font / size / justify per window
------------------------------------------------------------------------
function T.fontFor(i)
    local w = M.C("font").windows
    if type(w) ~= "table" then return nil end
    return w[i]
end

function T.applyFonts()
    local c = M.C("font")
    local i
    for i = 1, M.numWindows() do
        local cf = M.frame(i)
        if cf and cf.GetFont and not isHost(cf) then
            local w = c.on and T.fontFor(i)
            if type(w) == "table" and (w.face or w.size or w.justify) then
                if not cf._icFontOrig then
                    local p, s, f = cf:GetFont()
                    cf._icFontOrig = { p, s, f }
                end
                local o = cf._icFontOrig
                local face = w.face or o[1]
                local size = tonumber(w.size) or o[2]
                if face and size then cf:SetFont(face, size, o[3] or "") end
                if cf.SetJustifyH then cf:SetJustifyH(w.justify or "LEFT") end
                cf._icFontSet = true
            elseif cf._icFontSet then
                local o = cf._icFontOrig
                if o and o[1] and o[2] then cf:SetFont(o[1], o[2], o[3] or "") end
                if cf.SetJustifyH then cf:SetJustifyH("LEFT") end
                cf._icFontSet = nil
            end
        end
    end
end

------------------------------------------------------------------------
-- Text fading per window
------------------------------------------------------------------------
function T.applyFade()
    local c = M.C("fade")
    local w = type(c.windows) == "table" and c.windows or {}
    local i
    for i = 1, M.numWindows() do
        local cf = M.frame(i)
        if cf and cf.SetFading and not isHost(cf) then
            local s = c.on and w[i]
            if type(s) == "table" then
                cf:SetFading(s.fade and true or false)
                if cf.SetTimeVisible then cf:SetTimeVisible(tonumber(s.time) or 120) end
                cf._icFade = true
            elseif cf._icFade then
                cf:SetFading(true)
                if cf.SetTimeVisible then cf:SetTimeVisible(120) end
                cf._icFade = nil
            end
        end
    end
end

------------------------------------------------------------------------
-- Channel color memory: colors keyed by channel name, reapplied when a
-- channel's number changes or it is rejoined.
------------------------------------------------------------------------
function T.channelName(n)
    if not GetChannelName then return nil end
    local _, name = GetChannelName(n)
    if type(name) ~= "string" or name == "" then return nil end
    name = string.gsub(name, "%s+%-%s+.*$", "")
    return string.lower(name)
end

local rawChange

function T.rememberColor(ctype, r, g, b)
    local c = M.C("colors")
    if not c.on or T._applying then return end
    local _, _, n = string.find(ctype or "", "^CHANNEL(%d+)$")
    if not n then return end
    local name = T.channelName(tonumber(n))
    if not name then return end
    if type(c.map) ~= "table" then c.map = {} end
    c.map[name] = { r = r, g = g, b = b }
end

function T.reapplyColors()
    local c = M.C("colors")
    if not c.on or type(ChatTypeInfo) ~= "table" then return end
    if type(c.map) ~= "table" then c.map = {} end
    local n
    for n = 1, 10 do
        local name = T.channelName(n)
        local info = ChatTypeInfo["CHANNEL" .. n]
        if name and info then
            local m = c.map[name]
            if m and m.r then
                if math.abs((info.r or 0) - m.r) > 0.01 or math.abs((info.g or 0) - m.g) > 0.01
                    or math.abs((info.b or 0) - m.b) > 0.01 then
                    T._applying = true
                    local fn = rawChange or ChangeChatColor
                    if fn then pcall(function() fn("CHANNEL" .. n, m.r, m.g, m.b) end) end
                    T._applying = nil
                end
            elseif info.r then
                c.map[name] = { r = info.r, g = info.g, b = info.b }
            end
        end
    end
end

local colorQueued = false
local function queueColors()
    if colorQueued then return end
    colorQueued = true
    M.After(0.5, function()
        colorQueued = false
        T.reapplyColors()
    end)
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function()
    if event == "CHAT_MSG_WHISPER" then
        if M.C("tabs").on and M.C("tabs").flashWhisper then T.flashSelected() end
    elseif event == "CHANNEL_UI_UPDATE" or event == "CHAT_MSG_CHANNEL_NOTICE" or event == "UPDATE_CHAT_COLOR" then
        queueColors()
    end
end)

local function hookColors()
    if T._colorHook or type(ChangeChatColor) ~= "function" then return end
    T._colorHook = true
    rawChange = ChangeChatColor
    ChangeChatColor = function(ctype, r, g, b)
        rawChange(ctype, r, g, b)
        T.rememberColor(ctype, r, g, b)
    end
end

------------------------------------------------------------------------
function T:login()
    hookTabs()
    hookColors()
    ev:RegisterEvent("CHAT_MSG_WHISPER")
    pcall(function() ev:RegisterEvent("CHANNEL_UI_UPDATE") end)
    ev:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
    pcall(function() ev:RegisterEvent("UPDATE_CHAT_COLOR") end)
    T.applyFonts()
    T.applyFade()
end

function T:world()
    if not T._loginTabDone then
        T._loginTabDone = true
        M.After(1.5, function()
            T.selectLoginTab()
            T.paintTabs()
        end)
    end
    M.After(2, T.reapplyColors)
    queueTabs()
end

function T:apply()
    T.applyFonts()
    T.applyFade()
    T.paintTabs()
    queueColors()
end
