-- IchaUI Chat scrolling: mouse wheel, sticky channels, scrollback length,
-- and a gold scroll-to-bottom reminder shown only while scrolled up.
-- Wheel and sticky are set again after entering the world so they win over
-- other chat addons that set them while loading.

local M = IchaUIChat
local S = M.Register("Scroll", {})

S.STICKY_TYPES = { "SAY", "YELL", "PARTY", "GUILD", "OFFICER", "RAID", "RAID_WARNING", "BATTLEGROUND", "WHISPER", "CHANNEL", "EMOTE" }

local ARROW = "Interface\\AddOns\\IchaUI\\media\\Arrow-PointDown-Up"

local function isHost(cf)
    return M.Dock and M.Dock.isHost and M.Dock.isHost(cf)
end

------------------------------------------------------------------------
-- Reminder arrow
------------------------------------------------------------------------
local function ensureArrow(cf)
    if cf._icArrow then return cf._icArrow end
    local b = CreateFrame("Button", nil, cf)
    b:SetWidth(22)
    b:SetHeight(22)
    b:SetFrameLevel((cf:GetFrameLevel() or 1) + 6)
    b:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    b:SetBackdropColor(0.05, 0.05, 0.06, 0.85)
    if IchaUI_PaintGoldBorder then
        IchaUI_PaintGoldBorder(b, 1)
    else
        b:SetBackdropBorderColor(0.78, 0.58, 0.16, 1)
    end
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
    t:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
    t:SetTexture(ARROW)
    t:SetVertexColor(1, 0.86, 0.5, 1)
    b.tex = t
    b:SetScript("OnClick", function()
        local f = this:GetParent()
        f:ScrollToBottom()
        this:Hide()
    end)
    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:SetText("Scroll to bottom")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:ClearAllPoints()
    b:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 4, -2)
    b:Hide()
    cf._icArrow = b
    return b
end

function S.updateReminder(cf)
    if not cf then return end
    local on = M.C("scroll").reminder
    if not on or isHost(cf) then
        if cf._icArrow then cf._icArrow:Hide() end
        return
    end
    local atBottom = true
    if cf.AtBottom then atBottom = cf:AtBottom() and true or false end
    if atBottom then
        if cf._icArrow then cf._icArrow:Hide() end
    else
        ensureArrow(cf):Show()
    end
end

local driver = CreateFrame("Frame")
driver.acc = 0
driver:Hide()
driver:SetScript("OnUpdate", function()
    this.acc = this.acc + (arg1 or 0)
    if this.acc < 0.2 then return end
    this.acc = 0
    local i
    for i = 1, M.numWindows() do
        local cf = M.frame(i)
        if cf and cf:IsVisible() then S.updateReminder(cf) end
    end
end)

------------------------------------------------------------------------
-- Wheel
------------------------------------------------------------------------
local function onWheel()
    local c = M.C("scroll")
    local d = arg1 or 0
    if c.shiftJump ~= false and IsShiftKeyDown and IsShiftKeyDown() then
        if d > 0 then this:ScrollToTop() else this:ScrollToBottom() end
    else
        local n = tonumber(c.lines) or 3
        if n < 1 then n = 1 end
        if IsControlKeyDown and IsControlKeyDown() then
            local mult = tonumber(c.ctrlMult) or 3
            if mult < 1 then mult = 1 end
            n = n * mult
        end
        local i
        for i = 1, n do
            if d > 0 then this:ScrollUp() else this:ScrollDown() end
        end
    end
    S.updateReminder(this)
end
S.onWheel = onWheel

function S.applyWheel()
    local c = M.C("scroll")
    local i
    for i = 1, M.numWindows() do
        local cf = M.frame(i)
        if cf and not isHost(cf) then
            if c.wheel then
                cf:EnableMouseWheel(true)
                cf:SetScript("OnMouseWheel", onWheel)
                cf._icWheel = true
            elseif cf._icWheel then
                cf:SetScript("OnMouseWheel", nil)
                cf:EnableMouseWheel(false)
                cf._icWheel = nil
            end
        end
    end
end

function S.applySticky()
    local c = M.C("scroll")
    if not c.stickyOn or type(ChatTypeInfo) ~= "table" then return end
    local t = c.sticky or {}
    local i
    for i = 1, table.getn(S.STICKY_TYPES) do
        local k = S.STICKY_TYPES[i]
        if ChatTypeInfo[k] and t[k] ~= nil then
            ChatTypeInfo[k].sticky = t[k] and 1 or 0
        end
    end
end

------------------------------------------------------------------------
-- Scrollback. SetMaxLines clears the frame, so it only runs when the
-- value actually changes (and early, before history is replayed).
------------------------------------------------------------------------
function S.maxLines()
    local n = tonumber(M.C("scroll").maxLines) or 128
    if n < 128 then n = 128 end
    if n > 1000 then n = 1000 end
    return n
end

function S.applyMaxLines()
    local n = S.maxLines()
    local i
    for i = 1, M.numWindows() do
        local cf = M.frame(i)
        if cf and cf.SetMaxLines and not isHost(cf) then
            local cur = cf._icMax
            if not cur and cf.GetMaxLines then
                pcall(function() cur = cf:GetMaxLines() end)
            end
            if not cur then cur = 128 end
            if cur ~= n then
                cf:SetMaxLines(n)
            end
            cf._icMax = n
        end
    end
end

function S:init()
    S.applyMaxLines()
end

function S:login()
    S.applyWheel()
    S.applySticky()
    if M.C("scroll").reminder then driver:Show() end
end

function S:world()
    S.applyWheel()
    S.applySticky()
    M.After(2, function()
        S.applyWheel()
        S.applySticky()
    end)
end

function S:apply()
    S.applyMaxLines()
    S.applyWheel()
    S.applySticky()
    if M.C("scroll").reminder then
        driver:Show()
    else
        driver:Hide()
        local i
        for i = 1, M.numWindows() do
            local cf = M.frame(i)
            if cf and cf._icArrow then cf._icArrow:Hide() end
        end
    end
end
