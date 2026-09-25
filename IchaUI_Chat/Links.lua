-- IchaUI Chat links: tooltips when hovering item / spell / quest links,
-- Alt-click a name to invite, Ctrl-click to target, Shift-click to put the
-- name in the open edit box, url: clicks, and class colors in the Who,
-- Guild and Friends lists. The chat frame scripts are wrapped after login
-- (and again after entering the world if another addon replaced them), so
-- IchaUI's handler runs first; anything it doesn't handle goes to the
-- previous handler.

local M = IchaUIChat
local K = M.Register("Links", {})

local function cfg() return M.C("links") end

local function stripCodes(s)
    return (string.gsub(string.gsub(s or "", "|c%x%x%x%x%x%x%x%x", ""), "|r", ""))
end

------------------------------------------------------------------------
-- Hover tooltips
------------------------------------------------------------------------
local TIP_TYPES = { item = true, enchant = true, spell = true }
local pending

local function questTip(owner, link, label)
    local _, _, id, lvl = string.find(link, "^quest:(%d+):?(%-?%d*)")
    id = tonumber(id)
    if not id then return false end
    local title = string.gsub(stripCodes(label), "^%[(.*)%]$", "%1")
    if title == "" then title = nil end
    local QL = C_QuestLog
    local details
    if type(QL) == "table" and type(QL.GetQuestDetails) == "function" then
        pcall(function() details = QL.GetQuestDetails(id) end)
    end
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    GameTooltip:ClearLines()
    if type(details) == "table" then
        if details.title and details.title ~= "" then title = details.title end
        GameTooltip:AddLine(title or ("Quest " .. id), 1, 0.82, 0)
        local onQuest
        if type(QL.IsOnQuest) == "function" then pcall(function() onQuest = QL.IsOnQuest(id) end) end
        if onQuest then GameTooltip:AddLine("You are on this quest.", 0.2, 1, 0.2) end
        local info
        if tonumber(details.level) and tonumber(details.level) > 0 then info = (LEVEL or "Level") .. " " .. details.level end
        if details.questType and details.questType ~= "" then
            info = info and (info .. " - " .. details.questType) or details.questType
        end
        if info then GameTooltip:AddLine(info, 0.8, 0.8, 0.8) end
        if details.objectives and details.objectives ~= "" then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(details.objectives, 1, 1, 1, 1)
        end
        pending = nil
    else
        GameTooltip:AddLine(title or ("Quest " .. id), 1, 0.82, 0)
        lvl = tonumber(lvl)
        if lvl and lvl > 0 then GameTooltip:AddLine((LEVEL or "Level") .. " " .. lvl, 0.8, 0.8, 0.8) end
        if type(QL) == "table" and type(QL.RequestLoadQuestByID) == "function" and K.questEv then
            pending = { owner = owner, id = id, link = link, label = label }
            pcall(function() QL.RequestLoadQuestByID(id) end)
        end
    end
    GameTooltip:Show()
    return true
end
K.questTip = questTip

local function wrapEnter(old)
    return function()
        local link = arg1
        if cfg().tips and type(link) == "string" then
            local _, _, kind = string.find(link, "^(%a+):")
            if kind and TIP_TYPES[kind] then
                GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
                local ok = pcall(function() GameTooltip:SetHyperlink(link) end)
                if ok and (GameTooltip:NumLines() or 0) > 0 then
                    GameTooltip:Show()
                    this._icTip = true
                    return
                end
                GameTooltip:Hide()
            elseif kind == "quest" and questTip(this, link, arg2) then
                this._icTip = true
                return
            end
        end
        if old then old() end
    end
end

local function wrapLeave(old)
    return function()
        if this._icTip then
            this._icTip = nil
            pending = nil
            GameTooltip:Hide()
        elseif old then
            old()
        end
    end
end

------------------------------------------------------------------------
-- Clicks
------------------------------------------------------------------------
function K.playerClick(link)
    local _, _, name = string.find(link, "^player:([^:]+)")
    if not name or name == "" then return false end
    local c = cfg()
    if c.altInvite and IsAltKeyDown and IsAltKeyDown() then
        if InviteByName then InviteByName(name) end
        return true
    end
    if c.ctrlTarget and IsControlKeyDown and IsControlKeyDown() then
        if TargetByName then TargetByName(name, true) end
        return true
    end
    if c.shiftName and IsShiftKeyDown and IsShiftKeyDown() then
        local b = ChatFrameEditBox
        if b and b:IsVisible() then
            b:Insert(name)
            return true
        end
    end
    return false
end

local function wrapClick(old)
    return function()
        local link = arg1
        if type(link) == "string" then
            if string.sub(link, 1, 4) == "url:" then
                if M.CopyBox then M.CopyBox.ShowURL(string.sub(link, 5)) end
                return
            end
            if string.sub(link, 1, 7) == "player:" and K.playerClick(link) then return end
        end
        if old then
            old()
        elseif ChatFrame_OnHyperlinkShow then
            ChatFrame_OnHyperlinkShow(arg1, arg2, arg3)
        end
    end
end

local SCRIPTS = {
    { "OnHyperlinkClick", wrapClick },
    { "OnHyperlinkEnter", wrapEnter },
    { "OnHyperlinkLeave", wrapLeave },
}

function K.hookFrames()
    local i, j
    for i = 1, M.numWindows() do
        local cf = M.frame(i)
        if cf and not M.isCombatFrame(cf) then
            if not cf._icLinkFns then cf._icLinkFns = {} end
            for j = 1, table.getn(SCRIPTS) do
                local sname, wrap = SCRIPTS[j][1], SCRIPTS[j][2]
                local cur
                local ok = pcall(function() cur = cf:GetScript(sname) end)
                if ok and (cur == nil or cur ~= cf._icLinkFns[sname]) then
                    local fn = wrap(cur)
                    if pcall(function() cf:SetScript(sname, fn) end) then cf._icLinkFns[sname] = fn end
                end
            end
        end
    end
    if type(SetItemRef) == "function" and not K._itemRef then
        K._itemRef = true
        local oldRef = SetItemRef
        SetItemRef = function(link, text, button)
            if type(link) == "string" and string.sub(link, 1, 4) == "url:" then
                if M.CopyBox then M.CopyBox.ShowURL(string.sub(link, 5)) end
                return
            end
            return oldRef(link, text, button)
        end
    end
end

------------------------------------------------------------------------
-- Class colors in the Who / Guild / Friends lists
------------------------------------------------------------------------
local function tokenOf(loc)
    local P = M.Pipeline
    return P and P.tokenFor and P.tokenFor(loc) or nil
end

local function paint(fsName, c, a)
    local fs = getglobal(fsName)
    if fs and c then fs:SetTextColor(c.r, c.g, c.b, a or 1) end
end

local function diff(level)
    level = tonumber(level)
    if not level or level <= 0 or type(GetDifficultyColor) ~= "function" then return nil end
    local c
    pcall(function() c = GetDifficultyColor(level) end)
    return c
end

function K.guildColors()
    if not GuildListScrollFrame or not GetGuildRosterInfo then return end
    local off = FauxScrollFrame_GetOffset(GuildListScrollFrame) or 0
    local i
    for i = 1, (GUILDMEMBERS_TO_DISPLAY or 13) do
        local name, _, _, level, loc, _, _, _, online = GetGuildRosterInfo(off + i)
        if name then
            local a = online and 1 or 0.5
            local tk = tokenOf(loc)
            local c = tk and RAID_CLASS_COLORS and RAID_CLASS_COLORS[tk]
            paint("GuildFrameButton" .. i .. "Name", c, a)
            paint("GuildFrameButton" .. i .. "Class", c, a)
            paint("GuildFrameGuildStatusButton" .. i .. "Name", c, a)
            paint("GuildFrameButton" .. i .. "Level", diff(level), a)
        end
    end
end

function K.whoColors()
    if not WhoListScrollFrame or not GetWhoInfo then return end
    local off = FauxScrollFrame_GetOffset(WhoListScrollFrame) or 0
    local i
    for i = 1, (WHOS_TO_DISPLAY or 17) do
        local name, _, level, _, loc = GetWhoInfo(off + i)
        if name then
            local tk = tokenOf(loc)
            local c = tk and RAID_CLASS_COLORS and RAID_CLASS_COLORS[tk]
            paint("WhoFrameButton" .. i .. "Name", c, 1)
            paint("WhoFrameButton" .. i .. "Class", c, 1)
            paint("WhoFrameButton" .. i .. "Level", diff(level), 1)
        end
    end
end

-- Recolors the name inside the friend row's text, replacing a color another
-- addon already put on it instead of stacking a second one.
function K.colorNameIn(t, name, hex)
    local s, e = string.find(t, name, 1, true)
    if not s then return t end
    local before = string.gsub(string.sub(t, 1, s - 1), "|c%x%x%x%x%x%x%x%x$", "")
    local after = string.gsub(string.sub(t, e + 1), "^|r", "")
    return before .. hex .. name .. "|r" .. after
end

function K.friendColors()
    if not FriendsFrameFriendsScrollFrame or not GetFriendInfo then return end
    local off = FauxScrollFrame_GetOffset(FriendsFrameFriendsScrollFrame) or 0
    local i
    for i = 1, (FRIENDS_TO_DISPLAY or 10) do
        local name, _, loc, _, connected = GetFriendInfo(off + i)
        if not name then break end
        if connected then
            local tk = tokenOf(loc)
            local c = tk and RAID_CLASS_COLORS and RAID_CLASS_COLORS[tk]
            local base = "FriendsFrameFriendButton" .. i
            local fs = getglobal(base .. "ButtonTextName") or getglobal(base .. "ButtonTextNameLocation")
            if c and fs and fs.GetText then
                local t = fs:GetText()
                if t then fs:SetText(K.colorNameIn(t, name, M.hex(c))) end
            end
        end
    end
end

local function after(fname, fn)
    local old = getglobal(fname)
    if type(old) ~= "function" then return end
    setglobal(fname, function(a1, a2, a3, a4)
        old(a1, a2, a3, a4)
        if cfg().social then pcall(fn) end
    end)
end

function K.hookLists()
    if K._lists then return end
    K._lists = true
    after("GuildStatus_Update", K.guildColors)
    after("WhoList_Update", K.whoColors)
    after("FriendsList_Update", K.friendColors)
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------
function K:login()
    K.hookFrames()
    K.hookLists()
    if not K.questEv then
        local f = CreateFrame("Frame")
        if pcall(function() f:RegisterEvent("QUEST_DATA_LOAD_RESULT") end) then
            f:SetScript("OnEvent", function()
                local p = pending
                if not p or tonumber(arg1) ~= p.id then return end
                pending = nil
                if arg2 and p.owner._icTip then questTip(p.owner, p.link, p.label) end
            end)
            K.questEv = f
        end
    end
end

function K:world()
    K.hookFrames()
    M.After(2, K.hookFrames)
end
