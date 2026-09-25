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
    if BG[4] > 1 then BG[4] = 1 end
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
    -- Theme fill x this alpha x fill opacity, tracked so Gold.lua repaints it live.
    if IchaUI_PaintFill then IchaUI_PaintFill(f, alpha or BG[4]) end
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

-- FCF fades CHAT_FRAME_TEXTURES / tab art back in with Show + SetAlpha, so a
-- plain hide does not stick. Only for chat + tab art, never the edit box.
local function lockHidden(t)
    if not t then return end
    nukeTexture(t)
    if t._waDead then return end
    t._waDead = true
    t.Show = function() end
    t.SetAlpha = function() end
    t.SetVertexColor = function() end
end

local function lockNamed(frame, suffixes)
    if not frame then return end
    local name = frame:GetName()
    if not name then return end
    local i
    for i = 1, table.getn(suffixes) do
        lockHidden(getglobal(name .. suffixes[i]))
    end
end

-- UI-Tooltip-Border: the stroke's inner edge is 5/16 of the tile (Blizzard's
-- tooltip pairs edgeSize 16 with insets 5), so fills start there.
local function innerInset(edge)
    return math.floor((edge or edgeSize) * 5 / 16 + 0.5)
end

local function glowRGB()
    if IchaUI_GoldLight then
        local r, g, b = IchaUI_GoldLight()
        if r then return r, g, b end
    end
    return 1, 0.86, 0.5
end

local function insetTo(t, rel, ins)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", rel, "TOPLEFT", ins, -ins)
    t:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", -ins, ins)
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
}
local EDIT_ART = {
    "Left", "Mid", "Middle", "Right",
    "FocusLeft", "FocusMid", "FocusMiddle", "FocusRight",
}
local TAB_ART = {
    "Left", "Middle", "Right",
    "SelectedLeft", "SelectedMiddle", "SelectedRight",
    "HighlightLeft", "HighlightMiddle", "HighlightRight",
    "Highlight", "HighlightTexture",
}
local TAB_EDGE = 10
local TAB_HL_A = 0.16
local TAB_FLASH_A = 0.32

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
    -- _waNoFill: a window whose content brings its own fill (Meters dock)
    applyBackdrop(border, cf._waNoFill and 0 or BG[4], edgeSize)
    if cf:IsShown() then border:Show() else border:Hide() end
    cf._waChrome = border
    return border
end

-- The chrome backdrop is the only chat fill. Blizzard's ChatFrameNBackground
-- (window alpha / hover fades) stays hidden while skinned: drawn over the
-- chrome it stacked a second dark layer that no IchaUI slider controlled.
-- Its requested alpha is kept so turning the skin off gives it back.
local function muteBlizzBackground(cf)
    local bg = cf and getglobal(cf:GetName() .. "Background")
    if not bg then return end
    if not bg._waMute then
        bg._waMute = true
        if bg._waReqA == nil and bg.GetAlpha then bg._waReqA = bg:GetAlpha() end
        local rawShow, rawAlpha = bg.Show, bg.SetAlpha
        bg._waRawShow, bg._waRawAlpha = rawShow, rawAlpha
        bg.Show = function(self)
            if not enabled then rawShow(self) end
        end
        bg.SetAlpha = function(self, a)
            self._waReqA = tonumber(a) or 0
            if not enabled then rawAlpha(self, self._waReqA) end
        end
    end
    bg:Hide()
end

local function restoreBlizzBackground(cf)
    local bg = cf and getglobal(cf:GetName() .. "Background")
    if not bg or not bg._waMute then return end
    bg:ClearAllPoints()
    bg:SetAllPoints(cf)
    bg._waRawAlpha(bg, bg._waReqA or 0)
    bg._waRawShow(bg)
end

local function skinChatFrame(cf)
    if not cf then return end
    -- also while hidden: docked / new windows get shown by FCF later
    muteBlizzBackground(cf)
    if not cf:IsShown() then
        if cf._waChrome then cf._waChrome:Hide() end
        if cf.SetBackdrop then cf:SetBackdrop(nil) end
        return
    end
    lockNamed(cf, CHAT_ART)
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

local function paintGlow(t, rel, ins, a)
    t:SetTexture("Interface/Buttons/WHITE8X8")
    if t.SetBlendMode then t:SetBlendMode("ADD") end
    local r, g, b = glowRGB()
    t:SetVertexColor(r, g, b, a)
    insetTo(t, rel, ins)
end

-- Blizzard's highlight / flash use their own offsets; replace them with a
-- gold wash clipped to the inside of the tab stroke.
local function skinTabGlow(tab)
    local ins = innerInset(TAB_EDGE)
    local blizz
    if tab.GetHighlightTexture then
        pcall(function() blizz = tab:GetHighlightTexture() end)
    end
    if blizz and blizz ~= tab._waHL then lockHidden(blizz) end
    local regions = { tab:GetRegions() }
    local i
    for i = 1, table.getn(regions) do
        local r = regions[i]
        if r and r ~= tab._waHL and r.GetObjectType and r:GetObjectType() == "Texture" then
            local layer
            if r.GetDrawLayer then
                pcall(function() layer = r:GetDrawLayer() end)
            end
            if layer == "HIGHLIGHT" then lockHidden(r) end
        end
    end
    if not tab._waHL then tab._waHL = tab:CreateTexture(nil, "HIGHLIGHT") end
    paintGlow(tab._waHL, tab, ins, TAB_HL_A)

    local flash = getglobal(tab:GetName() .. "Flash")
    if not flash then return end
    if flash:GetObjectType() == "Texture" then
        paintGlow(flash, tab, ins, TAB_FLASH_A)
        return
    end
    insetTo(flash, tab, ins)
    local fr = { flash:GetRegions() }
    for i = 1, table.getn(fr) do
        local r = fr[i]
        if r and r.GetObjectType and r:GetObjectType() == "Texture" then
            paintGlow(r, flash, 0, TAB_FLASH_A)
        end
    end
end

local function skinTab(tab)
    if not tab then return end
    -- Strip default tab art only — never SetWidth/Height/Points (FCF owns layout)
    lockNamed(tab, TAB_ART)
    local tabA = BG[4] + 0.12
    if tabA > 0.75 then tabA = math.max(0.75, BG[4]) end
    applyBackdrop(tab, tabA, TAB_EDGE)
    skinTabGlow(tab)

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

-- Edit box position is owned by IchaUI_Chat (IchaUIChat_PlaceEditBox,
-- IchaUIDB.chat.editbox); this only makes sure the border it anchors to exists.
local function placeEditBoxAboveChrome(eb)
    local cf = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME or getglobal("ChatFrame1")
    if not cf or not eb then return end
    if enabled and not cf._waChrome then ensureOuterBorder(cf) end
    if IchaUIChat_PlaceEditBox then IchaUIChat_PlaceEditBox(eb) end
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
            restoreBlizzBackground(cf)
        end
        local tab = getglobal("ChatFrame" .. i .. "Tab")
        if tab and tab.SetBackdrop then tab:SetBackdrop(nil) end
        if tab and tab._waHL then tab._waHL:SetVertexColor(0, 0, 0, 0) end
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
        if BG[4] > 1 then BG[4] = 1 end
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

-- A tab click is what fixed misaligned tabs: FCF_SelectDockFrame ->
-- FCF_DockUpdate re-anchors every docked tab (and hides the unselected
-- frames), then the click hook re-skins everything. fullRelayout does exactly
-- that, one frame after any FCF layout call so bursts coalesce. Paths that
-- move tabs without an FCF call (tab flash, new tab text width, a window
-- added by another addon) are caught by the tab geometry check in the tick.
local relaying = false
local tabBase = nil

local function round0(v)
    if not v then return "-" end
    return math.floor(v + 0.5)
end

local function tabSig()
    local parts = {}
    local i
    for i = 1, (NUM_CHAT_WINDOWS or 7) do
        local tab = getglobal("ChatFrame" .. i .. "Tab")
        if tab and tab:IsShown() then
            local l = tab:GetLeft()
            local fs = getglobal(tab:GetName() .. "Text")
            local fl = fs and fs.GetLeft and fs:GetLeft()
            local off = nil
            if fl and l then off = fl - l end
            table.insert(parts, i .. ":" .. round0(l) .. "," .. round0(tab:GetBottom()) .. ","
                .. round0(tab:GetWidth()) .. "," .. round0(off))
        end
    end
    return table.concat(parts, ";")
end

local function fullRelayout()
    if not enabled then return end
    relaying = true
    if type(FCF_DockUpdate) == "function" and type(DOCKED_CHAT_FRAMES) == "table" then
        pcall(FCF_DockUpdate)
    end
    relaying = false
    skinAll()
    tabBase = nil
end

local tabQ = CreateFrame("Frame")
tabQ:Hide()
tabQ:SetScript("OnUpdate", function()
    this:Hide()
    fullRelayout()
end)

local function hookTabLayout(fname)
    local old = getglobal(fname)
    if type(old) ~= "function" then return end
    setglobal(fname, function(a1, a2, a3, a4)
        local r = old(a1, a2, a3, a4)
        if not relaying then tabQ:Show() end
        return r
    end)
end
hookTabLayout("FCF_DockUpdate")
hookTabLayout("FCF_SelectDockFrame")
hookTabLayout("FCF_SetWindowName")
hookTabLayout("FCF_SetTabPosition")
hookTabLayout("FCF_UpdateDockPosition")
hookTabLayout("FCF_DockFrame")
hookTabLayout("FCF_UnDockFrame")
hookTabLayout("FCF_Close")

local function leftButtonDown()
    if not IsMouseButtonDown then return false end
    local down = false
    pcall(function() down = IsMouseButtonDown("LeftButton") and true or false end)
    return down
end

-- Runs from the 0.4s tick: re-lay tabs once when their geometry drifts from
-- the last applied layout (baseline taken one tick after each relayout).
local function checkTabDrift()
    if leftButtonDown() then return end
    local s = tabSig()
    if tabBase == nil then
        tabBase = s
    elseif s ~= tabBase then
        tabBase = nil
        tabQ:Show()
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(function() boot:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS") end)
pcall(function() boot:RegisterEvent("UPDATE_CHAT_WINDOWS") end)
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
            if enabled then fullRelayout() end
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
                muteBlizzBackground(cf)
            end
        end
    end
    -- Chat options button fights back — bury every tick
    buryButton(getglobal("ChatFrameMenuButton"))
    checkTabDrift()
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

local function hookReskin(fname)
    local old = getglobal(fname)
    if type(old) ~= "function" then return end
    setglobal(fname, function(a1, a2, a3, a4)
        local r = old(a1, a2, a3, a4)
        if enabled then skinAll() end
        return r
    end)
end
hookReskin("FCF_DockFrame")
hookReskin("FCF_UnDockFrame")

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

-- Fill opacity changed (Gold.lua): repaint the chrome fills.
function IchaUIChatSkin_RefreshFill()
    if not enabled or not IchaUI_PaintFill then return end
    local i
    for i = 1, (NUM_CHAT_WINDOWS or 7) do
        local cf = getglobal("ChatFrame" .. i)
        if cf and cf._waChrome then IchaUI_PaintFill(cf._waChrome, cf._waNoFill and 0 or BG[4]) end
    end
end

-- Gold border only (no fill) for a window whose content has its own fill.
function IchaUIChatSkin_SetNoFill(cf, on)
    if not cf then return end
    on = on and true or nil
    if cf._waNoFill == on then return end
    cf._waNoFill = on
    if cf._waChrome and enabled and IchaUI_PaintFill then
        IchaUI_PaintFill(cf._waChrome, on and 0 or BG[4])
    end
end
