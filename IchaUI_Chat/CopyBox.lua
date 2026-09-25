-- IchaUI Chat copy dialogs: URL copy (single line) and Copy chat (the
-- window's recent lines from the pipeline's ring buffer). Ctrl+C copies.

local M = IchaUIChat
local CB = M.Register("CopyBox", {})

local function goldFrame(f, edge)
    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = edge or 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.04, 0.04, 0.05, 0.96)
    if IchaUI_PaintGoldBorder then
        IchaUI_PaintGoldBorder(f, 1)
    else
        f:SetBackdropBorderColor(0.78, 0.58, 0.16, 1)
    end
end

local function goldText(fs)
    if IchaUI_PaintGoldFont then
        IchaUI_PaintGoldFont(fs, 0.93, 0.78, 0.35)
    else
        fs:SetTextColor(0.93, 0.78, 0.35)
    end
end

function CB.plain(s)
    if type(s) ~= "string" then return "" end
    s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
    s = string.gsub(s, "|r", "")
    s = string.gsub(s, "|H.-|h(.-)|h", "%1")
    s = string.gsub(s, "|T.-|t", "")
    return s
end

------------------------------------------------------------------------
-- URL dialog
------------------------------------------------------------------------
local urlBox

local function buildURL()
    if urlBox then return urlBox end
    local f = CreateFrame("Frame", "IchaUIChatURLCopy", UIParent)
    f:SetWidth(420)
    f:SetHeight(78)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    goldFrame(f, 14)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    title:SetText("Link  (Ctrl+C to copy, Esc to close)")
    goldText(title)

    local eb = CreateFrame("EditBox", "IchaUIChatURLCopyEdit", f)
    eb:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -28)
    eb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -28)
    eb:SetHeight(24)
    eb:SetFontObject(ChatFontNormal or GameFontHighlight)
    eb:SetAutoFocus(false)
    eb:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    eb:SetBackdropColor(0, 0, 0, 0.8)
    eb:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnEnterPressed", function() f:Hide() end)
    eb:SetScript("OnTextChanged", function()
        if f._url and this:GetText() ~= f._url then
            this:SetText(f._url)
            this:HighlightText()
        end
    end)
    f.edit = eb

    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetWidth(64)
    close:SetHeight(18)
    close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 7)
    close:SetText(CLOSE or "Close")
    close:SetScript("OnClick", function() f:Hide() end)

    tinsert(UISpecialFrames, "IchaUIChatURLCopy")
    urlBox = f
    return f
end

function CB.ShowURL(url)
    local f = buildURL()
    f._url = url or ""
    f.edit:SetText(f._url)
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end

------------------------------------------------------------------------
-- Copy chat dialog
------------------------------------------------------------------------
local textBox

local function buildText()
    if textBox then return textBox end
    local f = CreateFrame("Frame", "IchaUIChatCopy", UIParent)
    f:SetWidth(620)
    f:SetHeight(400)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    goldFrame(f, 16)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    goldText(title)
    f.title = title

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -14)
    hint:SetText("Ctrl+A selects all, Ctrl+C copies")
    hint:SetTextColor(1, 1, 1)

    local sf = CreateFrame("ScrollFrame", "IchaUIChatCopyScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -34)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 38)

    local eb = CreateFrame("EditBox", "IchaUIChatCopyEdit", sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal or GameFontHighlight)
    eb:SetWidth(560)
    eb:SetHeight(320)
    pcall(function() eb:SetMaxLetters(0) end)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnCursorChanged", function()
        if ScrollingEdit_OnCursorChanged then ScrollingEdit_OnCursorChanged(arg1, arg2, arg3, arg4) end
    end)
    eb:SetScript("OnUpdate", function()
        if ScrollingEdit_OnUpdate then pcall(ScrollingEdit_OnUpdate) end
    end)
    sf:SetScrollChild(eb)
    f.edit = eb
    f.scroll = sf

    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetWidth(70)
    close:SetHeight(20)
    close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 10)
    close:SetText(CLOSE or "Close")
    close:SetScript("OnClick", function() f:Hide() end)

    local all = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    all:SetWidth(90)
    all:SetHeight(20)
    all:SetPoint("RIGHT", close, "LEFT", -6, 0)
    all:SetText("Select all")
    all:SetScript("OnClick", function()
        f.edit:SetFocus()
        f.edit:HighlightText()
    end)

    tinsert(UISpecialFrames, "IchaUIChatCopy")
    textBox = f
    return f
end

function CB.ShowText(title, text)
    local f = buildText()
    f.title:SetText(title or "Copy")
    f.edit:SetText(text or "")
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end

function CB.CopyChat(cf)
    cf = cf or M.selectedFrame()
    if not cf then return end
    local n = tonumber(M.C("history").copyLines) or 200
    local lines = M.Pipeline.recentLines(cf, n)
    local out = {}
    local i
    for i = 1, table.getn(lines) do
        table.insert(out, CB.plain(lines[i]))
    end
    local name = cf:GetName() or "Chat"
    if GetChatWindowInfo and cf.GetID then
        local wn = GetChatWindowInfo(cf:GetID())
        if wn and wn ~= "" then name = wn end
    end
    CB.ShowText("Copy chat: " .. name .. " (" .. table.getn(out) .. " lines)", table.concat(out, "\n"))
end

function IchaUIChat_CopyChat()
    CB.CopyChat(nil)
end

------------------------------------------------------------------------
-- Optional small copy button in each chat window's top-right corner
------------------------------------------------------------------------
local function ensureButton(cf)
    if cf._icCopyBtn then return cf._icCopyBtn end
    local b = CreateFrame("Button", nil, cf)
    b:SetWidth(18)
    b:SetHeight(18)
    b:SetFrameLevel((cf:GetFrameLevel() or 1) + 5)
    b:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    b:SetBackdropColor(0.05, 0.05, 0.06, 0.8)
    if IchaUI_PaintGoldBorder then IchaUI_PaintGoldBorder(b, 0.9) end
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    fs:SetText("C")
    goldText(fs)
    b:SetAlpha(0.45)
    b:SetScript("OnEnter", function()
        this:SetAlpha(1)
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:SetText("Copy chat")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        this:SetAlpha(0.45)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function() CB.CopyChat(this:GetParent()) end)
    cf._icCopyBtn = b
    return b
end

function CB:apply()
    local on = M.C("history").copyButton and true or false
    local i
    for i = 1, M.numWindows() do
        local cf = M.frame(i)
        if cf and not M.isCombatFrame(cf) and not (M.Dock and M.Dock.isHost and M.Dock.isHost(cf)) then
            if on then
                local b = ensureButton(cf)
                b:ClearAllPoints()
                b:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 2, 2)
                b:Show()
            elseif cf._icCopyBtn then
                cf._icCopyBtn:Hide()
            end
        end
    end
end

function CB:login()
    CB:apply()
end

SLASH_ICHAUICHATCOPY1 = "/chatcopy"
SlashCmdList["ICHAUICHATCOPY"] = function() CB.CopyChat(nil) end
