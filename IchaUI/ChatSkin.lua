-- IchaUI chat skin
-- Outer gold chrome (child of chat → no ghosts, text clears border)
-- Tabs skinned in place; edit box parked above chrome; scroll/menu hidden

local GOLD = { 0.78, 0.58, 0.16, 1 }
local BG = { 0.05, 0.05, 0.06, 0.75 }
local enabled = true
local edgeSize = 12
local PAD = 10
local PAD_TOP = 2 -- keep gold edge just under the edit box

local function db()
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.chatSkin then IchaUIDB.chatSkin = {} end
    return IchaUIDB.chatSkin
end

local function loadCfg()
    local d = db()
    if d.enabled ~= nil then enabled = d.enabled and true or false end
    if d.alpha ~= nil then BG[4] = tonumber(d.alpha) or BG[4] end
    if d.edge ~= nil then edgeSize = tonumber(d.edge) or edgeSize end
    if d.pad ~= nil then PAD = tonumber(d.pad) or PAD end
    if BG[4] < 0.15 then BG[4] = 0.15 end
    if BG[4] > 0.75 then BG[4] = 0.75 end
    if edgeSize < 8 then edgeSize = 8 end
    if edgeSize > 16 then edgeSize = 16 end
    if PAD < 8 then PAD = 8 end
    if PAD > 14 then PAD = 14 end
end

local function saveCfg()
    local d = db()
    d.enabled = enabled
    d.alpha = BG[4]
    d.edge = edgeSize
    d.pad = PAD
end

local function applyBackdrop(f, alpha, edge)
    if not f or not f.SetBackdrop then return end
    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = edge or edgeSize,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(BG[1], BG[2], BG[3], alpha or BG[4])
    IchaUI_PaintGoldBorder(f, 1)
end

local function nukeTexture(t)
    if not t then return end
    if t.SetTexture then
        t:SetTexture("")
        pcall(function() t:SetTexture("Interface/Buttons/WHITE8X8") end)
        -- Stop Blizzard from putting the art back
        if not t._waLocked then
            t._waLocked = true
            t.SetTexture = function(self, path)
                if path and path ~= "" and path ~= "Interface/Buttons/WHITE8X8" then
                    return
                end
            end
        end
    end
    if t.SetVertexColor then t:SetVertexColor(0, 0, 0, 0) end
    if t.SetAlpha then t:SetAlpha(0) end
    if t.Hide then t:Hide() end
    if t.SetWidth then t:SetWidth(1) end
    if t.SetHeight then t:SetHeight(1) end
end

local function hideNamed(frame, suffixes)
    if not frame then return end
    local name = frame:GetName()
    if not name then return end
    local i
    for i = 1, table.getn(suffixes) do
        nukeTexture(getglobal(name .. suffixes[i]))
    end
end

local function hideAllTextures(frame)
    if not frame or not frame.GetRegions then return end
    local regions = { frame:GetRegions() }
    local i
    for i = 1, table.getn(regions) do
        local r = regions[i]
        if r and r.GetObjectType and r:GetObjectType() == "Texture" then
            -- Keep our solid fill
            if frame._waFill and r == frame._waFill then
                -- skip
            else
                nukeTexture(r)
            end
        end
    end
end

local CHAT_ART = {
    "TopTexture", "BottomTexture", "LeftTexture", "RightTexture",
    "TopLeftTexture", "TopRightTexture", "BottomLeftTexture", "BottomRightTexture",
    "Background",
}
local EDIT_ART = {
    "Left", "Mid", "Middle", "Right",
    "FocusLeft", "FocusMid", "FocusMiddle", "FocusRight",
}
local TAB_ART = {
    "Left", "Middle", "Right",
    "SelectedLeft", "SelectedMiddle", "SelectedRight",
    "HighlightLeft", "HighlightMiddle", "HighlightRight",
}

local function destroyLegacyBorders()
    local i
    for i = 1, 10 do
        local b = getglobal("ChatFrame" .. i .. "WABorder")
        if b then
            b:Hide()
            if b.SetBackdrop then b:SetBackdrop(nil) end
            b.Show = function() end
        end
    end
    local ebb = getglobal("ChatFrameEditBoxWABorder")
    if ebb then
        ebb:Hide()
        if ebb.SetBackdrop then ebb:SetBackdrop(nil) end
        ebb.Show = function() end
    end
end

------------------------------------------------------------------------
-- Scroll / menu / social chrome — hide permanently
------------------------------------------------------------------------
local function buryButton(b)
    if not b then return end
    b:Hide()
    if b.SetAlpha then b:SetAlpha(0) end
    if b.EnableMouse then b:EnableMouse(false) end
    if b.Enable then b:EnableMouse(false) end
    if b.SetWidth then b:SetWidth(1) end
    if b.SetHeight then b:SetHeight(1) end
    if b.ClearAllPoints and b.SetPoint then
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -5000, 5000)
    end
    if not b._waNoShow then
        b._waNoShow = true
        b.Show = function() end
        b:SetScript("OnShow", function(self)
            self:Hide()
            if self.SetAlpha then self:SetAlpha(0) end
        end)
        b:SetScript("OnEnter", function() GameTooltip:Hide() end)
    end
end

local function hideChatButtons(cf)
    if not cf then return end
    local name = cf:GetName()
    if not name then return end
    local list = {
        name .. "UpButton",
        name .. "DownButton",
        name .. "BottomButton",
        name .. "ButtonFrame",
        name .. "MinimizeButton",
    }
    local i
    for i = 1, table.getn(list) do
        buryButton(getglobal(list[i]))
    end
end

local function hideGlobalChatButtons()
    -- Chat options / menu / social / channel buttons near the chat dock
    local list = {
        "ChatFrameMenuButton",
        "ChatMenuButton",
        "ChatMenu",
        "ChatFrameChannelButton",
        "ChatFrameToggleVoiceDeafenButton",
        "ChatFrameToggleVoiceMuteButton",
        "FriendsMicroButton",
        "SocialsMicroButton",
        "QuickJoinToastButton",
    }
    local i
    for i = 1, table.getn(list) do
        buryButton(getglobal(list[i]))
    end
    -- Per-window leftovers
    local n = NUM_CHAT_WINDOWS or 7
    for i = 1, n do
        buryButton(getglobal("ChatFrame" .. i .. "ButtonFrame"))
    end
end

------------------------------------------------------------------------
-- Chat frame chrome
------------------------------------------------------------------------
local function ensureOuterBorder(cf)
    if not cf then return end
    local bname = cf:GetName() .. "WAChrome"
    local border = getglobal(bname)
    if not border then
        border = CreateFrame("Frame", bname, cf)
    end
    border:SetParent(cf)
    local fl = (cf:GetFrameLevel() or 2) - 1
    if fl < 0 then fl = 0 end
    border:SetFrameLevel(fl)
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", cf, "TOPLEFT", -PAD, PAD_TOP)
    border:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", PAD, -PAD)
    applyBackdrop(border, BG[4], edgeSize)
    if cf:IsShown() then border:Show() else border:Hide() end
    cf._waChrome = border
    return border
end

local function skinChatFrame(cf)
    if not cf then return end
    if not cf:IsShown() then
        if cf._waChrome then cf._waChrome:Hide() end
        if cf.SetBackdrop then cf:SetBackdrop(nil) end
        return
    end
    hideNamed(cf, CHAT_ART)
    if cf.SetBackdrop then cf:SetBackdrop(nil) end
    ensureOuterBorder(cf)
    hideChatButtons(cf)
end

------------------------------------------------------------------------
-- Tabs: size to text, anchor under gold chrome (not the message frame)
------------------------------------------------------------------------
local function tabLabelWidth(fs, label)
    local w = 0
    if fs and fs.GetStringWidth then
        w = fs:GetStringWidth() or 0
    end
    -- Before first paint GetStringWidth is often 0 — estimate from text
    if (not w or w < 8) and label and string.len(label) > 0 then
        w = string.len(label) * 7.5
    end
    if w < 24 then w = 40 end
    return w
end

local function skinTab(tab)
    if not tab then return end
    -- Strip default tab art only — never SetWidth/Height/Points (FCF owns layout)
    hideNamed(tab, TAB_ART)
    applyBackdrop(tab, math.min(0.75, BG[4] + 0.12), 10)

    local fs = tab:GetName() and getglobal(tab:GetName() .. "Text")
    if fs then
        if fs.SetTextColor then fs:SetTextColor(1, 0.92, 0.7) end
        if fs.SetJustifyH then fs:SetJustifyH("CENTER") end
        if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end
        -- Center text without resizing the tab
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", tab, "CENTER", 0, 1)
    end
end

local function layoutTabs()
    local n = NUM_CHAT_WINDOWS or 7
    local i
    for i = 1, n do
        local tab = getglobal("ChatFrame" .. i .. "Tab")
        if tab then
            skinTab(tab)
        end
    end
end

------------------------------------------------------------------------
-- Edit box: nuke art, solid fill, park ABOVE chrome once
------------------------------------------------------------------------
local function killEditArt(eb)
    if not eb then return end
    hideNamed(eb, EDIT_ART)
    hideAllTextures(eb)
    nukeTexture(getglobal("ChatFrameEditBoxLeft"))
    nukeTexture(getglobal("ChatFrameEditBoxMid"))
    nukeTexture(getglobal("ChatFrameEditBoxRight"))
    nukeTexture(getglobal("ChatFrameEditBoxFocusLeft"))
    nukeTexture(getglobal("ChatFrameEditBoxFocusMid"))
    nukeTexture(getglobal("ChatFrameEditBoxFocusRight"))

    if not eb._waFill then
        local fill = eb:CreateTexture(nil, "ARTWORK")
        fill:SetDrawLayer("ARTWORK", -8)
        eb._waFill = fill
    end
    eb._waFill:ClearAllPoints()
    -- Inset so gold backdrop edge stays visible
    eb._waFill:SetPoint("TOPLEFT", eb, "TOPLEFT", 5, -5)
    eb._waFill:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", -5, 5)
    eb._waFill:SetTexture("Interface/Tooltips/UI-Tooltip-Background")
    -- Lighter than chat so it doesn't look like a black slab
    eb._waFill:SetVertexColor(0.12, 0.11, 0.10, 0.55)
    eb._waFill:Show()
end

local function styleEditBox(eb)
    if not eb then return end
    killEditArt(eb)
    -- Lighter alpha + clear gold edge
    applyBackdrop(eb, 0.40, 12)
end

local function placeEditBoxAboveChrome(eb)
    local cf = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME or getglobal("ChatFrame1")
    if not cf or not eb then return end
    local chrome = cf._waChrome or ensureOuterBorder(cf)
    if not chrome then return end
    eb:ClearAllPoints()
    eb:SetPoint("BOTTOMLEFT", chrome, "TOPLEFT", 0, 2)
    eb:SetPoint("BOTTOMRIGHT", chrome, "TOPRIGHT", 0, 2)
    if (eb:GetHeight() or 0) < 28 then
        eb:SetHeight(30)
    end
    eb._waPlaced = true
end

local function skinEditBox(forcePlace)
    local eb = ChatFrameEditBox or getglobal("ChatFrameEditBox")
    if not eb then return end
    styleEditBox(eb)
    if forcePlace or not eb._waPlaced then
        placeEditBoxAboveChrome(eb)
    end
    local hdr = getglobal("ChatFrameEditBoxHeader")
    if hdr and hdr.SetTextColor then
        IchaUI_PaintGoldFont(hdr, 0.78, 0.58, 0.16)
    end

    if not eb._waSkinHooked then
        eb._waSkinHooked = true
        local oldGain = eb:GetScript("OnEditFocusGained")
        local oldShow = eb:GetScript("OnShow")
        local oldUpdate = eb:GetScript("OnUpdate")

        eb:SetScript("OnEditFocusGained", function()
            if oldGain then oldGain() end
            styleEditBox(this)
            if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(this) end
            this:SetAlpha(1)
        end)
        eb:SetScript("OnShow", function()
            if oldShow then oldShow() end
            styleEditBox(this)
            placeEditBoxAboveChrome(this)
            this:SetAlpha(1)
        end)
        eb:SetScript("OnUpdate", function()
            -- Re-apply gold border every tick; Blizzard clears it
            styleEditBox(this)
            local focused = this.HasFocus and this:HasFocus()
            if focused then
                if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(this) end
                this:SetAlpha(1)
            end
            if oldUpdate then oldUpdate() end
            if focused then this:SetAlpha(1) end
        end)
    end
end

local function hookShowHide()
    local i
    for i = 1, (NUM_CHAT_WINDOWS or 7) do
        local cf = getglobal("ChatFrame" .. i)
        if cf and not cf._waShowHook then
            cf._waShowHook = true
            local oldShow = cf:GetScript("OnShow")
            local oldHide = cf:GetScript("OnHide")
            cf:SetScript("OnShow", function()
                if oldShow then oldShow() end
                if enabled then skinChatFrame(this) end
            end)
            cf:SetScript("OnHide", function()
                if oldHide then oldHide() end
                if this._waChrome then this._waChrome:Hide() end
            end)
        end
    end
end

local function skinAll()
    loadCfg()
    destroyLegacyBorders()
    if not enabled then return end
    hideGlobalChatButtons()
    local n = NUM_CHAT_WINDOWS or 7
    local i
    for i = 1, n do
        local cf = getglobal("ChatFrame" .. i)
        if cf then
            skinChatFrame(cf)
        end
    end
    layoutTabs()
    skinEditBox(true)
end

local function unskinAll()
    destroyLegacyBorders()
    local n = NUM_CHAT_WINDOWS or 7
    local i
    for i = 1, n do
        local cf = getglobal("ChatFrame" .. i)
        if cf then
            if cf.SetBackdrop then cf:SetBackdrop(nil) end
            local chrome = getglobal(cf:GetName() .. "WAChrome")
            if chrome then chrome:Hide() end
        end
        local tab = getglobal("ChatFrame" .. i .. "Tab")
        if tab and tab.SetBackdrop then tab:SetBackdrop(nil) end
    end
    local eb = ChatFrameEditBox or getglobal("ChatFrameEditBox")
    if eb and eb.SetBackdrop then eb:SetBackdrop(nil) end
end

function IchaUIChatSkin_Get()
    return { enabled = enabled, alpha = BG[4], edge = edgeSize, pad = PAD }
end

function IchaUIChatSkin_Set(field, value)
    if field == "enabled" then
        enabled = value and true or false
        saveCfg()
        if enabled then skinAll() else unskinAll() end
        return
    elseif field == "alpha" then
        BG[4] = tonumber(value) or BG[4]
        if BG[4] < 0.15 then BG[4] = 0.15 end
        if BG[4] > 0.75 then BG[4] = 0.75 end
    elseif field == "edge" then
        edgeSize = tonumber(value) or edgeSize
    elseif field == "pad" then
        PAD = tonumber(value) or PAD
    end
    saveCfg()
    skinAll()
end

function IchaUIChatSkin_Slash(msg)
    msg = string.lower(string.gsub(msg or "", "^%s+", ""))
    if msg == "off" or msg == "hide" then
        IchaUIChatSkin_Set("enabled", false)
        DEFAULT_CHAT_FRAME:AddMessage("Chat gold border off.")
    elseif msg == "on" or msg == "show" or msg == "" then
        IchaUIChatSkin_Set("enabled", true)
        DEFAULT_CHAT_FRAME:AddMessage("Chat gold border on.")
    elseif string.find(msg, "^alpha") then
        local n = nil
        for tok in (string.gmatch or string.gfind)(msg, "%S+") do n = tonumber(tok) or n end
        if n then
            if n > 1 then n = n / 100 end
            IchaUIChatSkin_Set("alpha", n)
        end
        DEFAULT_CHAT_FRAME:AddMessage(string.format("Chat bg alpha: %.2f", BG[4]))
    else
        DEFAULT_CHAT_FRAME:AddMessage("Chat skin: /icha chat on|off|alpha")
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(function() boot:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS") end)
boot:SetScript("OnEvent", function()
    local d = CreateFrame("Frame")
    d.t = 0
    d:SetScript("OnUpdate", function()
        this.t = this.t + (arg1 or 0)
        if this.t < 0.4 then return end
        this:SetScript("OnUpdate", nil)
        hookShowHide()
        skinAll()
        -- Second pass: GetStringWidth is valid after first paint
        local d2 = CreateFrame("Frame")
        d2.t = 0
        d2:SetScript("OnUpdate", function()
            this.t = this.t + (arg1 or 0)
            if this.t < 1.0 then return end
            this:SetScript("OnUpdate", nil)
            layoutTabs()
            skinEditBox(true)
        end)
    end)
end)

-- Keep tabs skinned + buttons hidden (Blizzard restores them)
local tick = CreateFrame("Frame")
tick.acc = 0
tick:SetScript("OnUpdate", function()
    if not enabled then return end
    this.acc = this.acc + (arg1 or 0)
    if this.acc < 0.4 then return end
    this.acc = 0
    hideGlobalChatButtons()
    local n = NUM_CHAT_WINDOWS or 7
    local i
    for i = 1, n do
        local cf = getglobal("ChatFrame" .. i)
        if cf and cf:IsShown() then
            hideChatButtons(cf)
            if cf._waChrome then
                cf._waChrome:ClearAllPoints()
                cf._waChrome:SetPoint("TOPLEFT", cf, "TOPLEFT", -PAD, PAD_TOP)
                cf._waChrome:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", PAD, -PAD)
            end
        end
    end
    -- Chat options button fights back — bury every tick
    buryButton(getglobal("ChatFrameMenuButton"))
end)

if type(FCF_OpenNewWindow) == "function" then
    local old = FCF_OpenNewWindow
    FCF_OpenNewWindow = function(name)
        local f = old(name)
        if enabled then skinAll() end
        return f
    end
end

if type(FCF_Tab_OnClick) == "function" then
    local oldT = FCF_Tab_OnClick
    FCF_Tab_OnClick = function(button)
        oldT(button)
        if enabled then
            skinAll()
            layoutTabs()
            local eb = ChatFrameEditBox or getglobal("ChatFrameEditBox")
            if eb then placeEditBoxAboveChrome(eb) end
        end
    end
end

if type(ChatEdit_UpdateHeader) == "function" then
    local oldH = ChatEdit_UpdateHeader
    ChatEdit_UpdateHeader = function(editBox)
        oldH(editBox)
        if enabled then
            local eb = editBox or ChatFrameEditBox
            killEditArt(eb)
            -- Re-lock textures after header update tries to restore them
            hideNamed(eb, EDIT_ART)
        end
    end
end

function IchaUIChatSkin_Reload()
    loadCfg()
    if enabled then skinAll() else unskinAll() end
end
