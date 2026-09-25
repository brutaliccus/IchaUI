-- IchaUI Chat edit box: the single owner of ChatFrameEditBox placement.
-- ChatSkin.lua's placeEditBoxAboveChrome delegates here. Anchors to the
-- selected chat frame's gold border (cf._waChrome). MoveAnything, while it
-- holds ChatFrameEditBox, replaces SetPoint/ClearAllPoints with no-ops, so
-- its Hidden* originals are used when present.

local M = IchaUIChat
local E = M.Register("EditBox", {})

local function box()
    return ChatFrameEditBox or getglobal("ChatFrameEditBox")
end
E.box = box

local function clear(f)
    local fn = f.HiddenClearAllPoints or f.ClearAllPoints
    fn(f)
end

local function point(f, a, rel, b, x, y)
    local fn = f.HiddenSetPoint or f.SetPoint
    fn(f, a, rel, b, x, y)
end

local function skinOn()
    if not IchaUIChatSkin_Get then return false end
    local g = IchaUIChatSkin_Get()
    return g and g.enabled and true or false
end

------------------------------------------------------------------------
-- The edit box follows the selected tab, but never a meter tab: there it
-- stays on the last chat tab (position, chatFrame, SELECTED_CHAT_FRAME).
------------------------------------------------------------------------
local function isMeter(cf)
    return cf and M.Dock and M.Dock.isHost and M.Dock.isHost(cf) or false
end
E.isMeter = isMeter

function E.chatFrame()
    local cf = E.lastChat
    if cf and not isMeter(cf) and (cf.isDocked or (cf.IsShown and cf:IsShown())) then return cf end
    return getglobal("ChatFrame1")
end

function E.rebind()
    local sel = SELECTED_CHAT_FRAME
    if sel and not isMeter(sel) then
        E.lastChat = sel
    end
    local cf = E.chatFrame()
    if isMeter(SELECTED_CHAT_FRAME) then SELECTED_CHAT_FRAME = cf end
    if isMeter(DEFAULT_CHAT_FRAME) then DEFAULT_CHAT_FRAME = cf end
    local b = box()
    if b and isMeter(b.chatFrame) then b.chatFrame = cf end
    return cf
end

function E.anchorFrame()
    local cf = M.selectedFrame()
    if isMeter(cf) then cf = E.chatFrame() end
    if not cf then return getglobal("ChatFrame1") end
    if skinOn() and cf._waChrome then return cf._waChrome end
    return cf
end

local function enableDrag(b, on)
    if on then
        b:SetMovable(true)
        if b.SetClampedToScreen then b:SetClampedToScreen(true) end
        b:RegisterForDrag("LeftButton")
    else
        pcall(function() b:RegisterForDrag() end)
    end
end

function IchaUIChat_PlaceEditBox(b)
    b = b or box()
    if not b then return end
    local c = M.C("editbox")
    local pos = c.position or "TOP"
    local h = tonumber(c.height) or 0
    if h >= 16 then
        b:SetHeight(h)
    elseif (b:GetHeight() or 0) < 28 then
        b:SetHeight(30)
    end
    local match = c.widthMode ~= "fixed"
    local w = tonumber(c.width) or 400
    if w < 120 then w = 120 end
    clear(b)
    if pos == "FREE" then
        point(b, c.freePoint or "BOTTOMLEFT", "UIParent", c.freeRelPoint or "BOTTOMLEFT",
            tonumber(c.freeX) or 30, tonumber(c.freeY) or 220)
        if match then
            local rel = E.anchorFrame()
            -- the chrome is sized by anchors: GetWidth is its stale stored size
            local rw = rel and rel.GetWidth and rel:GetWidth()
            local l, r = rel and rel.GetLeft and rel:GetLeft(), rel and rel.GetRight and rel:GetRight()
            if l and r and r > l then
                rw = (r - l) * rel:GetEffectiveScale() / b:GetEffectiveScale()
            end
            if rw and rw > 50 then w = rw end
        end
        b:SetWidth(w)
        enableDrag(b, not c.locked)
    else
        local rel = E.anchorFrame()
        local ox = tonumber(c.offX) or 0
        local gap = tonumber(c.gap) or 2
        local pA, rA, pB, rB, y
        if pos == "BOTTOM" then
            pA, rA, pB, rB, y = "TOPLEFT", "BOTTOMLEFT", "TOPRIGHT", "BOTTOMRIGHT", -gap
        else
            pA, rA, pB, rB, y = "BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT", "TOPRIGHT", gap
        end
        point(b, pA, rel, rA, ox, y)
        if match then
            point(b, pB, rel, rB, ox, y)
        else
            b:SetWidth(w)
        end
        enableDrag(b, false)
    end
    b._waPlaced = true
end

function E.place()
    IchaUIChat_PlaceEditBox(box())
end

local function saveFree(b)
    local c = M.C("editbox")
    local x, y = b:GetLeft(), b:GetBottom()
    if not x or not y then return end
    local s = b:GetEffectiveScale() / (UIParent:GetEffectiveScale() or 1)
    c.freePoint, c.freeRelPoint = "BOTTOMLEFT", "BOTTOMLEFT"
    c.freeX = math.floor(x * s + 0.5)
    c.freeY = math.floor(y * s + 0.5)
end

------------------------------------------------------------------------
-- MoveAnything
------------------------------------------------------------------------
function E.maHooked()
    if type(MoveAnything_FindFrameOptions) ~= "function" then return false end
    local opt
    pcall(function() opt = MoveAnything_FindFrameOptions("ChatFrameEditBox") end)
    return opt ~= nil
end

-- Uses MoveAnything's own reset; falls back to its Allow/Clear pair.
function E.releaseMA()
    local b = box()
    if type(MoveAnything_ResetFrameOptions) == "function" then
        pcall(function() MoveAnything_ResetFrameOptions("ChatFrameEditBox") end)
    end
    if E.maHooked() then
        if type(MoveAnything_AllowExternalMovement) == "function" and b then
            pcall(function() MoveAnything_AllowExternalMovement(b) end)
        end
        if type(MoveAnything_ClearFrameOptions) == "function" then
            pcall(function() MoveAnything_ClearFrameOptions("ChatFrameEditBox") end)
        end
    end
    if b and b.HiddenSetPoint and type(MoveAnything_AllowExternalMovement) == "function" then
        pcall(function() MoveAnything_AllowExternalMovement(b) end)
    end
    E.place()
    if E.notice then E.notice:Hide() end
    if E.maHooked() then
        M.Print("MoveAnything still holds the edit box. Open MoveAnything and reset \"Chat EditBox (Move to Top)\", then /reload.")
        return false
    end
    M.Print("edit box released from MoveAnything. IchaUI now places it.")
    return true
end

local function buildNotice()
    if E.notice then return E.notice end
    local f = CreateFrame("Frame", "IchaUIChatMANotice", UIParent)
    f:SetWidth(380)
    f:SetHeight(104)
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.04, 0.04, 0.05, 0.96)
    if IchaUI_PaintGoldBorder then IchaUI_PaintGoldBorder(f, 1) end
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    t:SetText("IchaUI Chat")
    if IchaUI_PaintGoldFont then IchaUI_PaintGoldFont(t, 0.93, 0.78, 0.35) end
    local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -28)
    body:SetWidth(356)
    body:SetJustifyH("LEFT")
    body:SetTextColor(1, 1, 1)
    body:SetText("MoveAnything is holding the chat edit box, so IchaUI's edit box position can't fully apply. Release it so IchaUI owns the position?")
    local rel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    rel:SetWidth(170)
    rel:SetHeight(20)
    rel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    rel:SetText("Release from MoveAnything")
    rel:SetScript("OnClick", function() E.releaseMA() end)
    local later = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    later:SetWidth(70)
    later:SetHeight(20)
    later:SetPoint("LEFT", rel, "RIGHT", 6, 0)
    later:SetText("Not now")
    later:SetScript("OnClick", function() f:Hide() end)
    local never = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    never:SetWidth(80)
    never:SetHeight(20)
    never:SetPoint("LEFT", later, "RIGHT", 6, 0)
    never:SetText("Don't ask")
    never:SetScript("OnClick", function()
        M.C("editbox").maNotice = false
        f:Hide()
    end)
    f:Hide()
    E.notice = f
    return f
end

function E.checkMA()
    if E._noticeShown then return end
    if not E.maHooked() then return end
    if M.C("editbox").maNotice == false then return end
    E._noticeShown = true
    buildNotice():Show()
end

------------------------------------------------------------------------
-- Arrow keys, sticky unsent text
------------------------------------------------------------------------
function E.applyKeys()
    local b = box()
    if not b or not b.SetAltArrowKeyMode then return end
    local c = M.C("editbox")
    b:SetAltArrowKeyMode(not c.arrowKeys)
end

local function hookSticky()
    local b = box()
    if not b or b._icSticky then return end
    b._icSticky = true
    local oldEsc = b:GetScript("OnEscapePressed")
    local oldEnter = b:GetScript("OnEnterPressed")
    b:SetScript("OnEscapePressed", function()
        if M.C("editbox").sticky then
            E.stash = this:GetText()
            E.stashType = this.chatType
            E.stashTell = this.tellTarget
            E.stashChan = this.channelTarget
        end
        if oldEsc then oldEsc() elseif ChatEdit_OnEscapePressed then ChatEdit_OnEscapePressed(this) end
    end)
    b:SetScript("OnEnterPressed", function()
        E.stash = nil
        if oldEnter then oldEnter() elseif ChatEdit_OnEnterPressed then ChatEdit_OnEnterPressed() end
    end)
    b:SetScript("OnDragStart", function()
        local c = M.C("editbox")
        if c.position == "FREE" and not c.locked then this:StartMoving() end
    end)
    b:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local c = M.C("editbox")
        if c.position == "FREE" then
            saveFree(this)
            E.place()
        end
    end)
end

local function hookGlobals()
    if E._globals then return end
    E._globals = true
    if type(ChatFrame_OpenChat) == "function" then
        local oldOpen = ChatFrame_OpenChat
        ChatFrame_OpenChat = function(text, chatFrame)
            local before = SELECTED_CHAT_FRAME
            if M.Dock and M.Dock.beforeOpenChat then M.Dock.beforeOpenChat() end
            local cf = E.rebind()
            -- a meter frame, or the tab Back to General just switched away from
            if chatFrame and (isMeter(chatFrame) or (chatFrame == before and cf ~= before)) then chatFrame = cf end
            oldOpen(text, chatFrame)
            E.rebind()
            local stash = E.stash
            E.stash = nil
            if (text == nil or text == "") and stash and stash ~= "" and M.C("editbox").sticky then
                local b = box()
                if b and (b:GetText() or "") == "" then
                    if E.stashType then b.chatType = E.stashType end
                    if E.stashTell then b.tellTarget = E.stashTell end
                    if E.stashChan then b.channelTarget = E.stashChan end
                    b:SetText(stash)
                    if ChatEdit_UpdateHeader then ChatEdit_UpdateHeader(b) end
                end
            end
        end
    end
    local function clearFirst(fname)
        local old = getglobal(fname)
        if type(old) ~= "function" then return end
        setglobal(fname, function(a1, a2)
            E.stash = nil
            return old(a1, a2)
        end)
    end
    clearFirst("ChatFrame_ReplyTell")
    clearFirst("ChatFrame_ReplyTell2")
    local function placeAfter(fname, selects)
        local old = getglobal(fname)
        if type(old) ~= "function" then return end
        setglobal(fname, function(a1, a2, a3, a4)
            local r = old(a1, a2, a3, a4)
            -- FCF_SelectDockFrame(frame): a chat tab picked in code counts as selected
            if selects and type(a1) == "table" and a1.AddMessage and not isMeter(a1) then
                SELECTED_CHAT_FRAME = a1
            end
            E.rebind()
            E.place()
            return r
        end)
    end
    placeAfter("FCF_Tab_OnClick")
    placeAfter("FCF_SelectDockFrame", true)
end

local function hookShow()
    local b = box()
    if not b or b._icShowHook then return end
    b._icShowHook = true
    local old = b:GetScript("OnShow")
    b:SetScript("OnShow", function()
        E.rebind()
        if old then old() end
        E.rebind()
        IchaUIChat_PlaceEditBox(this)
    end)
end

function E:login()
    hookSticky()
    hookGlobals()
    hookShow()
    E.applyKeys()
    E.place()
end

function E:world()
    E.applyKeys()
    M.After(1.2, function()
        E.applyKeys()
        E.place()
        E.checkMA()
    end)
end

function E:apply()
    E.applyKeys()
    E.place()
end
