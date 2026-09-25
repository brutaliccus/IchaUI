-- IchaUI Chat message pipeline.
-- Each non-combat ChatFrameN.AddMessage is wrapped once, at file load, so
-- the wrapper sits below hooks other chat addons add later and sees their
-- output. Every step accepts text another addon already rewrote and never
-- doubles it. Only real chat-event lines (info.id as the 5th argument) are
-- rewritten: CLINK -> channel tag -> names -> URLs -> timestamp.
-- Addon prints and replayed history pass through untouched.

local M = IchaUIChat
local P = M.Register("Pipeline", {})

local RING_MAX = 500

-- Hot-path flags, refreshed by P.refresh()
local chOn, namesOn, urlsOn, tsOn, histOn, clinkOn = false, false, false, false, false, false
-- namesOn: any name option on. styleOn: class colors/brackets; lvlOn / grpOn work without it.
local styleOn, lvlOn, grpOn = false, false, false
local chCfg, namesCfg, urlsCfg, tsCfg, histCfg

------------------------------------------------------------------------
-- Ring buffer (Copy chat reads this; 1.12 has no GetMessageInfo)
------------------------------------------------------------------------
local function ringPush(frame, text)
    local r = frame._icRing
    if not r then
        r = { n = 0, pos = 0 }
        frame._icRing = r
    end
    local p = r.pos + 1
    if p > RING_MAX then p = 1 end
    r[p] = text
    r.pos = p
    if r.n < RING_MAX then r.n = r.n + 1 end
end
P.ringPush = ringPush

-- Last `count` lines of a frame, oldest first.
function P.recentLines(frame, count)
    local out = {}
    local r = frame and frame._icRing
    if not r or r.n == 0 then return out end
    count = tonumber(count) or r.n
    if count > r.n then count = r.n end
    local start = r.pos - count + 1
    local i
    for i = 0, count - 1 do
        local p = start + i
        if p < 1 then p = p + RING_MAX end
        table.insert(out, r[p])
    end
    return out
end

------------------------------------------------------------------------
-- Channel tags: CHAT_*_GET globals for typed chat, text rewrite for
-- numbered channels ("[1. General]" is built from the channel string).
------------------------------------------------------------------------
P.TAG_TYPES = {
    "SAY", "YELL", "PARTY", "GUILD", "OFFICER", "RAID", "RAID_LEADER",
    "RAID_WARNING", "BATTLEGROUND", "BATTLEGROUND_LEADER", "WHISPER", "WHISPER_INFORM",
}
P.TAG_DEFAULTS = {
    SAY = "[S]", YELL = "[Y]", PARTY = "[P]", GUILD = "[G]", OFFICER = "[O]",
    RAID = "[R]", RAID_LEADER = "[RL]", RAID_WARNING = "[RW]", BATTLEGROUND = "[B]",
    BATTLEGROUND_LEADER = "[BL]", WHISPER = "[W From]", WHISPER_INFORM = "[W To]",
}

local origGet = {}
do
    local i
    for i = 1, table.getn(P.TAG_TYPES) do
        local t = P.TAG_TYPES[i]
        origGet[t] = getglobal("CHAT_" .. t .. "_GET")
    end
    origGet.CHANNEL = CHAT_CHANNEL_GET
end
P.origGet = origGet

local tagsSet = false

local function applyTags()
    local i
    if chOn then
        local tags = chCfg.tags or {}
        local mid = (chCfg.space and " " or "") .. "%s" .. (chCfg.colon and ":" or "") .. " "
        for i = 1, table.getn(P.TAG_TYPES) do
            local t = P.TAG_TYPES[i]
            if origGet[t] then
                local tag = tags[t]
                if tag == nil then tag = P.TAG_DEFAULTS[t] end
                if tag and tag ~= "" then
                    setglobal("CHAT_" .. t .. "_GET", tag .. mid)
                else
                    setglobal("CHAT_" .. t .. "_GET", origGet[t])
                end
            end
        end
        if origGet.CHANNEL then
            CHAT_CHANNEL_GET = "%s" .. (chCfg.colon and ":" or "") .. " "
        end
        tagsSet = true
    elseif tagsSet then
        for i = 1, table.getn(P.TAG_TYPES) do
            local t = P.TAG_TYPES[i]
            if origGet[t] then setglobal("CHAT_" .. t .. "_GET", origGet[t]) end
        end
        if origGet.CHANNEL then CHAT_CHANNEL_GET = origGet.CHANNEL end
        tagsSet = false
    end
end

P.applyTags = applyTags

local function stripCodes(s)
    return (string.gsub(string.gsub(s, "|c%x%x%x%x%x%x%x%x", ""), "|r", ""))
end

-- Only a timestamp (or nothing) may sit before the channel tag.
local function onlyStamp(before)
    if before == "" then return true end
    local p = stripCodes(before)
    return string.find(p, "^%s*$") or string.find(p, "^%s*[%[%(<]?%d%d?:%d%d[%d:%sAPMapm]*[%]%)>]?%s*$")
end

-- "[1. General]" from the game, or "[1]" when another addon already shortened it.
local function shortChannel(text)
    local s, e, num = string.find(text, "%[(%d+)%. [^%]]-%]")
    if not s or not onlyStamp(string.sub(text, 1, s - 1)) then
        s, e, num = string.find(text, "%[(%d+)%]")
        if not s or not onlyStamp(string.sub(text, 1, s - 1)) then return text end
    end
    local over = chCfg.chan and chCfg.chan[tonumber(num)]
    local rep
    if over and over ~= "" then rep = over else rep = "[" .. num .. "]" end
    return string.sub(text, 1, s - 1) .. rep .. string.sub(text, e + 1)
end
P.shortChannel = shortChannel

------------------------------------------------------------------------
-- Name -> class/level cache. Two generations of at most cap/2 entries each:
-- a lookup promotes into the current one, a full current one becomes the
-- old one and the previous old one is dropped. Entries are "CLASS:level".
------------------------------------------------------------------------
local NC
local raidGroup = {}
local locToToken = {}

local function cacheTable()
    if NC then return NC end
    local nc = M.C("names")
    if type(nc.cache) ~= "table" then nc.cache = {} end
    NC = nc.cache
    if type(NC.cur) ~= "table" then NC.cur = {} end
    if type(NC.old) ~= "table" then NC.old = {} end
    NC.n = tonumber(NC.n) or 0
    return NC
end

local function cacheHalf()
    local cap = tonumber(M.C("names").cacheMax) or 2000
    if cap < 20 then cap = 20 end
    return math.floor(cap / 2)
end

local function decode(e)
    if not e then return nil, nil end
    local _, _, c, l = string.find(e, "^(%u*):(%d*)$")
    if c == "" then c = nil end
    return c, tonumber(l)
end

function P.nameSet(name, class, level)
    if type(name) ~= "string" or name == "" then return end
    local nc = cacheTable()
    local e = nc.cur[name]
    if not e then
        e = nc.old[name]
        if e then nc.old[name] = nil end
        nc.n = nc.n + 1
        if nc.n > cacheHalf() then
            nc.old = nc.cur
            nc.cur = {}
            nc.n = 1
        end
    end
    local oc, ol = decode(e)
    class = class or oc
    level = tonumber(level)
    if not level or level <= 0 then level = ol end
    nc.cur[name] = (class or "") .. ":" .. (level or "")
end

function P.nameGet(name)
    local nc = cacheTable()
    local e = nc.cur[name]
    if e then return decode(e) end
    e = nc.old[name]
    if e then
        local c, l = decode(e)
        P.nameSet(name, c, l)
        return c, l
    end
    return nil, nil
end

function P.cacheCount()
    local nc = cacheTable()
    local n, k = 0
    for k in pairs(nc.cur) do n = n + 1 end
    for k in pairs(nc.old) do n = n + 1 end
    return n
end

local function tokenFor(loc, token)
    if token and token ~= "" then
        if loc then locToToken[loc] = token end
        return token
    end
    if not loc or loc == "" then return nil end
    if locToToken[loc] then return locToToken[loc] end
    local t = string.upper(string.gsub(loc, "%s", ""))
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[t] then return t end
    return nil
end

P.tokenFor = tokenFor

local function learnUnit(unit)
    if not UnitExists or not UnitExists(unit) then return end
    if UnitIsPlayer and not UnitIsPlayer(unit) then return end
    local name = UnitName(unit)
    local loc, token = UnitClass(unit)
    P.nameSet(name, tokenFor(loc, token), UnitLevel(unit))
end

function P.scanGroup()
    local i
    raidGroup = {}
    learnUnit("player")
    local nr = GetNumRaidMembers and GetNumRaidMembers() or 0
    for i = 1, nr do
        local name, _, subgroup, level, loc, token = GetRaidRosterInfo(i)
        if name then
            P.nameSet(name, tokenFor(loc, token), level)
            raidGroup[name] = subgroup
        end
    end
    for i = 1, nr do learnUnit("raid" .. i) end
    local np = GetNumPartyMembers and GetNumPartyMembers() or 0
    for i = 1, np do learnUnit("party" .. i) end
end

-- GUILD_ROSTER_UPDATE only follows a GuildRoster() request.
local lastRoster = -1000
local function requestGuild(force)
    if not GuildRoster or not IsInGuild or not IsInGuild() then return end
    local now = GetTime()
    if not force and now - lastRoster < 30 then return end
    lastRoster = now
    pcall(GuildRoster)
end
P.requestGuild = requestGuild

function P.scanGuild()
    if not GetNumGuildMembers then return end
    local n = GetNumGuildMembers(true) or 0
    local i
    for i = 1, n do
        local name, _, _, level, loc = GetGuildRosterInfo(i)
        if name then P.nameSet(name, tokenFor(loc), level) end
    end
end

function P.scanFriends()
    if not GetNumFriends then return end
    local i
    for i = 1, (GetNumFriends() or 0) do
        local name, level, loc = GetFriendInfo(i)
        if name then P.nameSet(name, tokenFor(loc), level) end
    end
end

function P.scanWho()
    if not GetNumWhoResults then return end
    local i
    for i = 1, (GetNumWhoResults() or 0) do
        local name, _, level, _, loc = GetWhoInfo(i)
        if name then P.nameSet(name, tokenFor(loc), level) end
    end
end

local classHexCache = {}
local function classHex(token)
    if not token then return nil end
    local h = classHexCache[token]
    if h then return h end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if not c then return nil end
    h = M.hex(c.r, c.g, c.b)
    classHexCache[token] = h
    return h
end

local function escPat(s)
    return (string.gsub(s, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

-- Other addons' player-link rewrites, folded back before IchaUI restyles:
--   |r[|cffxxxxxx|Hplayer:X|h|cffxxxxxxName|h|r]|r  (brackets outside, class color)
--   |Hplayer:X|h[Name]|h|r |cffxxxxxx60|r          (level after the link)
local function unwrapNames(text)
    if styleOn then
        text = string.gsub(text, "|r%[|c%x%x%x%x%x%x%x%x(|Hplayer:[^|]+|h)|c%x%x%x%x%x%x%x%x([^|]*)|h|r%]|r", "%1[%2]|h")
    end
    if lvlOn then
        text = string.gsub(text, "(|Hplayer:[^|]+|h[^|]*|h|r) |c%x%x%x%x%x%x%x%x%d+|r", "%1")
    end
    return text
end

-- Drops a level prefix / group suffix already inside a label (a line run twice).
local function dropExtras(disp, name)
    local n = escPat(name)
    disp = string.gsub(disp, "^([%[<]?)%d+:(" .. n .. ")", "%1%2")
    disp = string.gsub(disp, "(|c%x%x%x%x%x%x%x%x[%[<]?)%d+:(" .. n .. ")", "%1%2")
    disp = string.gsub(disp, "([%[<])%d+:(" .. n .. ")", "%1%2")
    disp = string.gsub(disp, "(" .. n .. "):%d+", "%1")
    return disp
end

-- Puts pre/suf around the name inside a link label, keeping whatever
-- brackets and color codes another addon put there:
-- "[Name]", "|cffxxxxxxName", "[|cffxxxxxxName|r]", "|cffxxxxxx[Name]|r".
local function insertAround(disp, name, pre, suf)
    local init = 1
    while true do
        local s, e = string.find(disp, name, init, true)
        if not s then break end
        local before = string.sub(disp, 1, s - 1)
        local _, _, partial = string.find(before, "|c(%x*)$")
        if not (partial and string.len(partial) < 8) and not string.find(stripCodes(before), "%w") then
            return before .. pre .. name .. suf .. string.sub(disp, e + 1)
        end
        init = s + 1
    end
    return pre .. disp .. suf
end

local function nameRepl(link, disp)
    local _, _, name = string.find(link, "^([^:]+)")
    name = name or link
    local cls, lvl = P.nameGet(name)
    local pre, suf = "", ""
    if lvlOn then
        if lvl and lvl > 0 then pre = lvl .. ":" else requestGuild() end
    end
    if grpOn and raidGroup[name] then suf = ":" .. raidGroup[name] end
    if not styleOn then
        if pre == "" and suf == "" then return nil end
        disp = dropExtras(disp, name)
        return "|Hplayer:" .. link .. "|h" .. insertAround(disp, name, pre, suf) .. "|h"
    end
    local plain = stripCodes(disp)
    local _, _, inner = string.find(plain, "^[%[<](.*)[%]>]$")
    local hadBr = inner ~= nil and string.sub(plain, 1, 1) == "["
    local raw = inner or plain
    inner = dropExtras(raw, name)
    if plain ~= disp or inner ~= raw then hadBr = false end
    local L, R, body
    local st = namesCfg.brackets
    if st == "angle" then L, R = "<", ">"
    elseif st == "none" then L, R = "", ""
    else L, R = "[", "]" end
    local col = classHex(cls)
    if not col and pre == "" and suf == "" and L == "[" and hadBr then return nil end
    if col then body = col .. pre .. inner .. suf .. "|r" else body = pre .. inner .. suf end
    return "|Hplayer:" .. link .. "|h" .. L .. body .. R .. "|h"
end

local function colorNames(text)
    text = unwrapNames(text)
    return (string.gsub(text, "|Hplayer:([^|]+)|h(.-)|h", nameRepl))
end
P.colorNames = colorNames

------------------------------------------------------------------------
-- URLs. Whitespace tokens are tested one by one (so a URL at the very
-- start of a line matches too); tokens holding "|" (links, colors) are left alone.
------------------------------------------------------------------------
local TLD = {}
do
    local list = "com net org edu gov mil int info biz name pro aero coop museum mobi asia tel travel jobs " ..
        "io gg tv co uk de ru eu ca au nl fr pl se cz br jp cn kr es pt ch dk fi hu ro sk ua nz za ar mx " ..
        "app dev xyz online site club wiki link live shop store tech top blog cloud games media news social space website"
    local t
    for t in string.gfind(list, "%S+") do TLD[t] = true end
end

local function knownTLD(host)
    local _, _, tld = string.find(host, "%.(%a%a+)$")
    return tld and TLD[string.lower(tld)]
end

local function mayContainURL(text)
    if string.find(text, "://", 1, true) or string.find(text, "@", 1, true) then return true end
    if not string.find(text, ".", 1, true) then return false end
    if string.find(text, "%d+%.%d+%.%d+%.%d+") then return true end
    if string.find(text, "www.", 1, true) then return true end
    local t
    for t in string.gfind(text, "%.(%a%a+)") do
        if TLD[string.lower(t)] then return true end
    end
    return false
end
P.mayContainURL = mayContainURL

local function isURL(s)
    if string.find(s, "^%a[%w%+%.%-]*://[^%s]+") then return true end
    if string.find(s, "^[wW][wW][wW]%.[%w%-]+%.[%w%-%.]+") then return true end
    if string.find(s, "^[%w%._%-]+@[%w%-]+%.[%w%.%-]+$") then return knownTLD(s) and true or false end
    if string.find(s, "^%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?$")
        or string.find(s, "^%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?[:/]%S*$") then return true end
    local host = s
    local slash = string.find(s, "/", 1, true)
    if slash then host = string.sub(s, 1, slash - 1) end
    local _, _, h2 = string.find(host, "^(.-):%d+$")
    if h2 then host = h2 end
    if string.find(host, "^[%w%-]+%.[%w%-%.]*%a$") and string.find(host, "%a") and knownTLD(host) then
        return true
    end
    return false
end
P.isURL = isURL

local urlHex = "|cff66ccff"

local function urlToken(tok)
    if string.find(tok, "|", 1, true) then return nil end
    local _, _, lead, core, trail = string.find(tok, "^([%(<\"']*)(.-)([%.,;:!%?%)>\"']*)$")
    if not core or core == "" then return nil end
    if not isURL(core) then return nil end
    local shown = core
    if urlsCfg.brackets then shown = "[" .. core .. "]" end
    return lead .. urlHex .. "|Hurl:" .. core .. "|h" .. shown .. "|h|r" .. trail
end

-- Text inside any |H...|h...|h link (items, players, other addons' url: links)
-- is left alone; only the parts between links are scanned.
local function linkify(text)
    if not string.find(text, "|H", 1, true) then
        return (string.gsub(text, "(%S+)", urlToken))
    end
    local out, pos = {}, 1
    while true do
        local s, e = string.find(text, "|H[^|]*|h.-|h", pos)
        if not s then break end
        table.insert(out, (string.gsub(string.sub(text, pos, s - 1), "(%S+)", urlToken)))
        table.insert(out, string.sub(text, s, e))
        pos = e + 1
    end
    table.insert(out, (string.gsub(string.sub(text, pos), "(%S+)", urlToken)))
    return table.concat(out)
end
P.linkify = linkify

------------------------------------------------------------------------
-- Prat / Chatter CLINK markers -> real links
------------------------------------------------------------------------
local function clink(text)
    text = string.gsub(text, "{CLINK:(%x+):([%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-):([^}]-)}", "|c%1|Hitem:%2|h[%3]|h|r")
    text = string.gsub(text, "{CLINK:(%x+):([%d-]-:[%d-]-:[%d-]-:[%d-]-):([^}]-)}", "|c%1|Hitem:%2|h[%3]|h|r")
    text = string.gsub(text, "{CLINK:item:(%x+):([%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-):([^}]-)}", "|c%1|Hitem:%2|h[%3]|h|r")
    text = string.gsub(text, "{CLINK:enchant:(%x+):([%d-]-):([^}]-)}", "|c%1|Henchant:%2|h[%3]|h|r")
    text = string.gsub(text, "{CLINK:spell:(%x+):([%d-]-):([^}]-)}", "|c%1|Hspell:%2|h[%3]|h|r")
    text = string.gsub(text, "{CLINK:quest:(%x+):([%d-]-):([%d-]-):([^}]-)}", "|c%1|Hquest:%2:%3|h[%4]|h|r")
    return text
end
P.clink = clink

-- A line that already starts with a clock ("[14:05]", "(2:05:09 PM)", colored or not).
local function hasStamp(text)
    local p = string.gsub(string.sub(text, 1, 40), "^|c%x%x%x%x%x%x%x%x", "")
    return string.find(p, "^[%[%(<]?%d%d?:%d%d") ~= nil
end
P.hasStamp = hasStamp

------------------------------------------------------------------------
-- Timestamps (always last)
------------------------------------------------------------------------
local stampT, stampS

local function serverOffset()
    if not GetGameTime or not date then return 0 end
    local h, m = GetGameTime()
    local d = date("*t")
    if not h or type(d) ~= "table" then return 0 end
    local diff = (h * 60 + m) - (d.hour * 60 + d.min)
    while diff > 720 do diff = diff - 1440 end
    while diff <= -720 do diff = diff + 1440 end
    return diff * 60
end
P.serverOffset = serverOffset

function P.stamp(now)
    local t = now or time()
    if t == stampT and stampS then return stampS end
    local shown = t
    if tsCfg.server then shown = t + serverOffset() end
    local fmt = tsCfg.format
    if type(fmt) ~= "string" or fmt == "" then fmt = "%H:%M" end
    local s
    pcall(function() s = date(fmt, shown) end)
    if type(s) ~= "string" then s = date("%H:%M", shown) end
    stampT = t
    stampS = M.hex(tsCfg.color or { r = 0.6, g = 0.6, b = 0.6 }) .. "[" .. s .. "]|r "
    return stampS
end

------------------------------------------------------------------------
-- History (saved per window under IchaUIDB.chat.history.data)
------------------------------------------------------------------------
local function histData()
    if type(histCfg.data) ~= "table" then histCfg.data = {} end
    return histCfg.data
end

local function histCap()
    local n = tonumber(histCfg.lines) or 50
    if n < 5 then n = 5 end
    if n > 200 then n = 200 end
    return n
end

local function histPush(frame, text, r, g, b)
    if not histOn or not P._replayed then return end
    local id = frame:GetID()
    if not id or not M.winOn(histCfg.windows, id) then return end
    local data = histData()
    local list = data[id]
    if type(list) ~= "table" then list = {}; data[id] = list end
    local col = M.hex(r or 1, g or 1, b or 1)
    local s = col .. string.gsub(text, "|r", "|r" .. col)
    local n = (list._n or M.count(list)) + 1
    list[n] = s
    list._n = n
    local cap = histCap()
    if n > cap + 20 then
        list = M.keepLast(list, cap)
        list._n = cap
        data[id] = list
    end
end
P.histPush = histPush

function P.replayHistory()
    if P._replayed then return end
    P._replayed = true
    if not histOn then return end
    local data = histData()
    local cap = histCap()
    local id
    for id = 1, M.numWindows() do
        local cf = M.frame(id)
        local list = data[id]
        if type(list) == "table" then
            list = M.keepLast(list, cap)
            list._n = M.count(list)
            data[id] = list
        end
        if cf and not cf._icSkip and type(list) == "table" and M.winOn(histCfg.windows, id) then
            local n = list._n
            if n > 0 then
                local add = cf._icOrigAdd or cf.AddMessage
                local i
                for i = 1, n do
                    add(cf, list[i], 1, 1, 1)
                    ringPush(cf, list[i])
                end
                add(cf, "|cff707070-- " .. n .. " restored lines --|r", 1, 1, 1)
            end
        end
    end
end

function P.clearHistory()
    histCfg.data = {}
end

------------------------------------------------------------------------
-- The wrapper
------------------------------------------------------------------------
function P.process(frame, text)
    if clinkOn and string.find(text, "{CLINK:", 1, true) then
        text = clink(text)
    end
    if chOn and string.find(text, "[", 1, true) then
        text = shortChannel(text)
    end
    if namesOn and string.find(text, "|Hplayer:", 1, true) then
        text = colorNames(text)
    end
    if urlsOn and mayContainURL(text) then
        text = linkify(text)
    end
    if tsOn and M.winOn(tsCfg.windows, frame:GetID()) and not hasStamp(text) then
        text = P.stamp() .. text
    end
    return text
end

local function isRealLine(frame, id)
    if id ~= nil then return true end
    local e = event
    return (this == frame and type(e) == "string" and string.sub(e, 1, 9) == "CHAT_MSG_") and true or false
end
P.isRealLine = isRealLine

function P.AddMessage(frame, text, r, g, b, id, a6)
    local orig = frame._icOrigAdd
    if frame._icSkip or type(text) ~= "string" or text == "" then
        return orig(frame, text, r, g, b, id, a6)
    end
    if M.ready and isRealLine(frame, id) then
        text = P.process(frame, text)
        histPush(frame, text, r, g, b)
    end
    ringPush(frame, text)
    return orig(frame, text, r, g, b, id, a6)
end

function P.install(cf)
    if not cf or cf._icOrigAdd or not cf.AddMessage then return end
    cf._icOrigAdd = cf.AddMessage
    cf.AddMessage = P.AddMessage
end

function P.refreshSkip()
    local D = M.Dock
    local i
    for i = 1, M.numWindows() do
        local cf = M.frame(i)
        if cf then cf._icSkip = M.isCombatFrame(cf) or (D and D.isHost and D.isHost(cf)) or false end
    end
end

do
    local i
    for i = 1, M.numWindows() do
        local cf = M.frame(i)
        if cf then
            P.install(cf)
            if i == 2 then cf._icSkip = true end
        end
    end
end

------------------------------------------------------------------------
-- Name cache events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function()
    if not namesOn then return end
    if event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        P.scanGroup()
    elseif event == "GUILD_ROSTER_UPDATE" then
        P.scanGuild()
    elseif event == "FRIENDLIST_UPDATE" then
        P.scanFriends()
    elseif event == "WHO_LIST_UPDATE" then
        P.scanWho()
    elseif event == "PLAYER_TARGET_CHANGED" then
        learnUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        learnUnit("mouseover")
    elseif event == "PLAYER_LEVEL_UP" then
        P.nameSet(UnitName("player"), nil, arg1)
    end
end)
local rosterTick = 0
ev:SetScript("OnUpdate", function()
    rosterTick = rosterTick + (arg1 or 0)
    if rosterTick < 120 then return end
    rosterTick = 0
    if namesOn then requestGuild() end
end)
local NAME_EVENTS = {
    "RAID_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "GUILD_ROSTER_UPDATE", "FRIENDLIST_UPDATE",
    "WHO_LIST_UPDATE", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_LEVEL_UP",
}

local function scanAll()
    P.scanGroup()
    P.scanFriends()
    P.scanGuild()
    if ShowFriends then pcall(ShowFriends) end
    requestGuild(true)
end

local skipEv = CreateFrame("Frame")
skipEv:RegisterEvent("UPDATE_CHAT_WINDOWS")
skipEv:SetScript("OnEvent", function() P.refreshSkip() end)

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------
function P.refresh()
    chCfg = M.C("channels")
    namesCfg = M.C("names")
    urlsCfg = M.C("urls")
    tsCfg = M.C("timestamps")
    histCfg = M.C("history")
    chOn = chCfg.on and true or false
    clinkOn = M.C("links").clink and true or false
    styleOn = namesCfg.on and true or false
    lvlOn = namesCfg.level and true or false
    grpOn = namesCfg.group and true or false
    namesOn = styleOn or lvlOn or grpOn
    urlsOn = urlsCfg.on and true or false
    tsOn = tsCfg.on and true or false
    histOn = histCfg.on and true or false
    urlHex = M.hex(urlsCfg.color or { r = 0.4, g = 0.8, b = 1 })
    stampT, stampS = nil, nil
    NC = nil
end

function P:init()
    P.refresh()
end

function P:login()
    P.refresh()
    P.refreshSkip()
    applyTags()
    local i
    for i = 1, table.getn(NAME_EVENTS) do
        pcall(function() ev:RegisterEvent(NAME_EVENTS[i]) end)
    end
    P._namesWas = namesOn
    if namesOn then scanAll() end
end

-- Other chat addons set CHAT_*_GET while loading; set ours again after them.
function P:world()
    P.refreshSkip()
    applyTags()
    M.After(2, applyTags)
    if not P._replayed then P.replayHistory() end
end

function P:apply()
    P.refresh()
    P.refreshSkip()
    applyTags()
    local was = P._namesWas
    P._namesWas = namesOn
    if namesOn then
        if was then P.scanGroup() else scanAll() end
    end
end
