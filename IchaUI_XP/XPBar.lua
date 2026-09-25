-- IchaUI XP bar — separate movable window (XP + rested, 20 segments, gold border)

local SEGMENTS = 20
local BASE_W, BASE_H = 400, 14
local xpScale, xpW, xpH = 1.75, 170, 7
local moving = false
local trackW, trackH = BASE_W, BASE_H
local hover = false

local function db()
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.xp then IchaUIDB.xp = {} end
    return IchaUIDB.xp
end

local root

local function save()
    local d = db()
    d.scale = xpScale
    d.width = xpW
    d.height = xpH
    if root and root.GetPoint then
        local p, _, rp, x, y = root:GetPoint(1)
        d.point, d.relPoint, d.x, d.y = p, rp, x, y
    end
end

local function load()
    local d = db()
    if d.scale then xpScale = tonumber(d.scale) or 1.75 end
    if d.width then xpW = tonumber(d.width) or 170 end
    if d.height then xpH = tonumber(d.height) or 7 end
    if xpScale < 0.4 then xpScale = 0.4 end
    if xpScale > 3 then xpScale = 3 end
    if xpW < 80 then xpW = 80 end
    if xpH < 6 then xpH = 6 end
end

-- A backdrop needs 2 * edge of height for its top and bottom corners. On a
-- thinner bar the corners overlap and the side edges run the full frame
-- height, past the top/bottom gold lines, so cap the edge at half the height.
local function borderEdge(h)
    local e = math.floor(12 * xpScale + 0.5)
    if e < 8 then e = 8 end
    if e > 22 then e = 22 end
    if h then
        local fit = math.floor(h / 2)
        if fit < 2 then fit = 2 end
        if e > fit then e = fit end
    end
    return e
end

-- UI-Tooltip-Border straight edge is a 16px tile. From the outer edge:
-- px 0 clear, 1-2 shade, px 3 the opaque gold line, then shade, px 6 clear.
-- The inside edge of that gold line is 4px into the tile.
local EDGE_TILE = 16
local GOLD_INNER = 4

local function contentInset(edge)
    local n = math.floor((edge or borderEdge()) * GOLD_INNER / EDGE_TILE + 0.5)
    if n < 1 then n = 1 end
    return n
end

local inset = contentInset(12)

root = CreateFrame("Frame", "IchaUIXPRoot", UIParent)
root:SetFrameStrata("MEDIUM")
root:SetMovable(true)
root:EnableMouse(false)
root:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 55)

local border = CreateFrame("Frame", nil, root)
border:SetAllPoints(root)
border:SetBackdrop({
    bgFile = nil,
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 12,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
})
border:SetBackdropColor(0, 0, 0, 0)
IchaUI_PaintGoldBorder(border, 1)

-- Track is the hole inside the gold. Border stays full size and draws above it.
local track = CreateFrame("Frame", nil, root)
track:SetPoint("TOPLEFT", border, "TOPLEFT", inset, -inset)
track:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -inset, inset)
track:SetFrameLevel((root:GetFrameLevel() or 1) + 1)
border:SetFrameLevel((root:GetFrameLevel() or 1) + 2)

-- Background (status bar texture). Points come after SetTexture in seatBar.
local bg = track:CreateTexture(nil, "BACKGROUND")
bg:SetTexture("Interface/TargetingFrame/UI-StatusBar")
bg:SetVertexColor(0.15, 0.15, 0.15)

-- Rested: only the bubble PAST current XP (blue / green at 150%)
local rested = track:CreateTexture(nil, "ARTWORK")
rested:SetTexture("Interface/TargetingFrame/UI-StatusBar")
rested:SetVertexColor(0.25, 0.45, 1.0)
if rested.SetDrawLayer then rested:SetDrawLayer("ARTWORK", 1) end

-- Current XP (purple) on top of rested
local fill = track:CreateTexture(nil, "ARTWORK")
fill:SetTexture("Interface/TargetingFrame/UI-StatusBar")
fill:SetVertexColor(0.58, 0.0, 0.55)
if fill.SetDrawLayer then fill:SetDrawLayer("ARTWORK", 2) end

-- 20 segment dividers
local ticks = {}
for i = 1, SEGMENTS - 1 do
    local tick = track:CreateTexture(nil, "OVERLAY")
    tick:SetTexture("Interface/ChatFrame/ChatFrameBackground")
    tick:SetVertexColor(0, 0, 0)
    tick:SetAlpha(0.65)
    tick:SetWidth(1)
    ticks[i] = tick
end

-- Hover hit (no tooltip — only toggles on-bar text)
local hit = CreateFrame("Frame", nil, root)
hit:SetAllPoints(root)
hit:EnableMouse(true)
hit:SetFrameLevel((root:GetFrameLevel() or 1) + 5)

local label = CreateFrame("Frame", nil, root)
label:SetAllPoints(root)
label:EnableMouse(false)
label:SetFrameLevel((root:GetFrameLevel() or 1) + 15)
local text = label:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
text:SetPoint("CENTER", label, "CENTER", 0, 0)
text:SetJustifyH("CENTER")
text:SetTextColor(1, 0.95, 0.8)
text:Hide()

local function xpValues()
    local cur = UnitXP("player") or 0
    local max = UnitXPMax("player") or 1
    if max < 1 then max = 1 end
    local exh = 0
    if GetXPExhaustion then
        exh = GetXPExhaustion() or 0
    end
    return cur, max, exh
end

-- name, standing, cur, max past the standing floor; nil if no faction watched.
local function repValues()
    if not GetWatchedFactionInfo then return nil end
    local name, standing, lo, hi, value = GetWatchedFactionInfo()
    if not name or name == "" then return nil end
    standing = tonumber(standing) or 4
    lo = tonumber(lo) or 0
    hi = tonumber(hi) or 0
    value = tonumber(value) or lo
    local max = hi - lo
    if max < 1 then max = 1 end
    local cur = value - lo
    if cur < 0 then cur = 0 end
    if cur > max then cur = max end
    return name, standing, cur, max
end

local function atMaxLevel()
    local lvl = UnitLevel and UnitLevel("player") or 0
    return (tonumber(lvl) or 0) >= (tonumber(MAX_PLAYER_LEVEL) or 60)
end

-- Saved choice is IchaUIDB.xpBarMode ("xp" / "rep"). Rep needs a watched
-- faction; at max level a watched faction always wins.
local function barMode()
    if not repValues() then return "xp" end
    if atMaxLevel() then return "rep" end
    if IchaUIDB and IchaUIDB.xpBarMode == "rep" then return "rep" end
    return "xp"
end

local update

hit:SetScript("OnEnter", function()
    hover = true
    text:Show()
end)
hit:SetScript("OnLeave", function()
    hover = false
    text:Hide()
end)
hit:SetScript("OnMouseUp", function()
    if arg1 ~= "RightButton" then return end
    if not IchaUIDB then IchaUIDB = {} end
    if IchaUIDB.xpBarMode == "rep" then
        IchaUIDB.xpBarMode = "xp"
    else
        IchaUIDB.xpBarMode = "rep"
        if not repValues() then
            DEFAULT_CHAT_FRAME:AddMessage("XP bar: watch a faction (reputation pane) to show rep.")
        end
    end
    if update then update() end
end)

-- Move overlay
local mover = CreateFrame("Frame", nil, root)
mover:SetAllPoints(root)
mover:EnableMouse(true)
mover:RegisterForDrag("LeftButton")
mover:Hide()
mover:SetFrameLevel((root:GetFrameLevel() or 1) + 25)
local mbg = mover:CreateTexture(nil, "BACKGROUND")
mbg:SetAllPoints(mover)
mbg:SetTexture(1, 1, 1, 1)
mbg:SetVertexColor(0.15, 0.45, 0.95, 0.3)
local mlabel = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
mlabel:SetPoint("CENTER", mover, "CENTER")
mlabel:SetText("Drag XP bar  |  /icha xp move")
mover:SetScript("OnDragStart", function() root:StartMoving() end)
mover:SetScript("OnDragStop", function()
    root:StopMovingOrSizing()
    save()
end)

-- 1.12 SetPoint restores UI-StatusBar to its 64x8 file and centers it.
-- One TOPLEFT plus an explicit size, pinned again if the size snaps back.
local function seatBar(tex, x, w)
    local h = trackH
    if h < 1 then h = 1 end
    if not x or x < 0 then x = 0 end
    if not w or w < 0.001 then w = 0.001 end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", track, "TOPLEFT", x, 0)
    tex:SetWidth(w)
    tex:SetHeight(h)
    local gw = tex.GetWidth and tex:GetWidth() or w
    local gh = tex.GetHeight and tex:GetHeight() or h
    if math.abs(gw - w) > 0.5 or math.abs(gh - h) > 0.5 then
        tex:SetPoint("TOPLEFT", track, "TOPLEFT", x, 0)
        tex:SetWidth(w)
        tex:SetHeight(h)
    end
end

local function layoutTicks()
    local tw = trackW
    if tw < 1 then tw = 1 end
    local tickW = math.max(1, math.floor(xpScale + 0.5))
    for i = 1, SEGMENTS - 1 do
        local tick = ticks[i]
        local x = tw * (i / SEGMENTS)
        tick:ClearAllPoints()
        tick:SetPoint("TOPLEFT", track, "TOPLEFT", x - (tickW * 0.5), 0)
        tick:SetWidth(tickW)
        tick:SetHeight(trackH)
        tick:Show()
    end
end

local function applySize()
    local w = math.floor(xpW * xpScale + 0.5)
    local h = math.floor(xpH * xpScale + 0.5)
    root:SetWidth(w)
    root:SetHeight(h)

    local e = borderEdge(h)
    inset = contentInset(e)
    trackW = w - inset * 2
    trackH = h - inset * 2
    if trackW < 1 then trackW = 1 end
    if trackH < 1 then trackH = 1 end
    track:ClearAllPoints()
    track:SetPoint("TOPLEFT", border, "TOPLEFT", inset, -inset)
    track:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -inset, inset)
    track:SetFrameLevel((root:GetFrameLevel() or 1) + 1)
    seatBar(bg, 0, trackW)

    border:SetBackdrop({
        bgFile = nil,
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = e,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    border:SetBackdropColor(0, 0, 0, 0)
    IchaUI_PaintGoldBorder(border, 1)
    border:SetFrameLevel((root:GetFrameLevel() or 1) + 2)

    layoutTicks()

    local fontSize = math.max(9, math.floor(11 * xpScale + 0.5))
    local fontPath, _, fontFlags = GameFontHighlightSmall:GetFont()
    if fontPath then
        text:SetFont(fontPath, fontSize, fontFlags or "OUTLINE")
    end
    if not hover then
        text:Hide()
    end
end

local function updateRep(tw)
    local name, standing, cur, max = repValues()
    local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[standing]
    if c then
        fill:SetVertexColor(c.r or 0, c.g or 0, c.b or 0)
    else
        fill:SetVertexColor(0, 0.6, 0.1)
    end

    local curW = tw * (cur / max)
    if curW < 0 then curW = 0 end
    if curW > tw then curW = tw end
    seatBar(fill, 0, curW)
    fill:Show()
    rested:Hide()

    local label = getglobal("FACTION_STANDING_LABEL" .. standing) or ""
    text:SetText(string.format("%s | %s | %d / %d | %.0f%%",
        name, label, cur, max, (cur / max) * 100))
end

update = function()
    if not UnitXP then return end

    local tw = trackW
    if tw < 1 then
        applySize()
        tw = trackW
    end

    if barMode() == "rep" then
        updateRep(tw)
        if hover then text:Show() else text:Hide() end
        return
    end

    local cur, max, exh = xpValues()
    fill:SetVertexColor(0.58, 0.0, 0.55)

    local curW = tw * (cur / max)
    if curW < 0 then curW = 0 end
    if curW > tw then curW = tw end

    -- Purple current XP from the left, inside the gold stroke
    seatBar(fill, 0, curW)
    fill:Show()

    local restPct = 0
    if max > 0 then
        restPct = (exh / max) * 100
    end

    -- Blue/green rested only PAST current, clipped to end of bar
    local restSpan = 0
    if exh > 0 then
        restSpan = tw * (exh / max)
        if restSpan > (tw - curW) then
            restSpan = tw - curW
        end
    end
    if restPct >= 150 then
        rested:SetVertexColor(0.15, 0.85, 0.25)
    else
        rested:SetVertexColor(0.25, 0.45, 1.0)
    end
    if restSpan > 0.5 then
        seatBar(rested, curW, restSpan)
        rested:Show()
    else
        rested:Hide()
    end

    text:SetText(string.format("%d | %d | %.0f%%", cur, max, restPct))
    if hover then
        text:Show()
    else
        text:Hide()
    end
end

local function setMove(on)
    moving = on and true or false
    if moving then
        mover:Show()
        DEFAULT_CHAT_FRAME:AddMessage("XP bar move on — drag it, /icha xp move to lock.")
    else
        mover:Hide()
        save()
        DEFAULT_CHAT_FRAME:AddMessage("XP bar locked.")
    end
end

function IchaUIXP_SetMove(on)
    local want = on and true or false
    if want == (moving and true or false) then return end
    setMove(want)
end

local function restorePos()
    local d = db()
    root:ClearAllPoints()
    if d.point and d.x then
        root:SetPoint(d.point, UIParent, d.relPoint or d.point, d.x, d.y)
    else
        root:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 55)
    end
end

function IchaUIXP_Slash(rest)
    rest = string.lower(rest or "")
    rest = string.gsub(rest, "^%s+", "")
    if rest == "move" then
        setMove(not moving)
    elseif rest == "show" then
        root:Show()
        db().hidden = nil
        save()
        DEFAULT_CHAT_FRAME:AddMessage("XP bar shown.")
    elseif rest == "hide" then
        root:Hide()
        db().hidden = true
        save()
        DEFAULT_CHAT_FRAME:AddMessage("XP bar hidden.")
    elseif string.find(rest, "^scale") then
        local n = nil
        for token in (string.gmatch or string.gfind)(rest, "%S+") do
            n = tonumber(token) or n
        end
        if not n then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("XP scale: %.2f", xpScale))
        else
            if n < 0.4 then n = 0.4 end
            if n > 3 then n = 3 end
            xpScale = n
            save()
            applySize()
            update()
            DEFAULT_CHAT_FRAME:AddMessage(string.format("XP scale %.2f", xpScale))
        end
    elseif string.find(rest, "^width") or string.find(rest, "^w ") or rest == "w" then
        local n = nil
        for token in (string.gmatch or string.gfind)(rest, "%S+") do
            n = tonumber(token) or n
        end
        if not n then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("XP width: %.0f (pre-scale)", xpW))
        else
            if n < 80 then n = 80 end
            if n > 1200 then n = 1200 end
            xpW = n
            save()
            applySize()
            update()
            DEFAULT_CHAT_FRAME:AddMessage(string.format("XP width %.0f", xpW))
        end
    elseif string.find(rest, "^height") or string.find(rest, "^h ") or rest == "h" then
        local n = nil
        for token in (string.gmatch or string.gfind)(rest, "%S+") do
            n = tonumber(token) or n
        end
        if not n then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("XP height: %.0f (pre-scale)", xpH))
        else
            if n < 6 then n = 6 end
            if n > 80 then n = 80 end
            xpH = n
            save()
            applySize()
            update()
            DEFAULT_CHAT_FRAME:AddMessage(string.format("XP height %.0f", xpH))
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("XP bar: /icha xp move | scale 1 | width 400 | height 14 | show | hide")
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_XP_UPDATE")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("UPDATE_EXHAUSTION")
f:RegisterEvent("UPDATE_FACTION")
f:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        load()
        restorePos()
        applySize()
        if db().hidden then root:Hide() else root:Show() end
    end
    update()
end)

-- Picking a faction in the reputation pane does not fire UPDATE_FACTION on
-- 1.12, so repaint on SetWatchedFactionIndex and poll the watched faction.
local lastWatch = nil
local function watchKey()
    if not GetWatchedFactionInfo then return "" end
    local name, standing, lo, hi, value = GetWatchedFactionInfo()
    return tostring(name) .. ":" .. tostring(standing) .. ":" .. tostring(value) .. ":" .. tostring(hi)
end
if SetWatchedFactionIndex then
    local origSetWatched = SetWatchedFactionIndex
    SetWatchedFactionIndex = function(i)
        origSetWatched(i)
        lastWatch = nil
        if update then update() end
    end
end
local watchPoll = 0
f:SetScript("OnUpdate", function()
    watchPoll = watchPoll + (arg1 or 0)
    if watchPoll < 0.5 then return end
    watchPoll = 0
    local k = watchKey()
    if k ~= lastWatch then
        lastWatch = k
        if update then update() end
    end
end)

applySize()

local xpTestMode = false
function IchaUIXP_SetTestMode(on)
    xpTestMode = on and true or false
    if xpTestMode then
        root:Show()
    else
        if db().hidden then root:Hide() else root:Show() end
    end
end

function IchaUIXP_Reload()
    load()
    restorePos()
    applySize()
    update()
    if db().hidden then root:Hide() else root:Show() end
end
