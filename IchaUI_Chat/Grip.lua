-- IchaUI Chat resize grip: a small corner handle while a window is unlocked.
-- ChatSkin mutes ChatFrameNResize*Texture (the second window / double-alpha
-- border). The ChatFrameNResize* buttons stay in place and still size, but
-- they sit under the chrome with no art. This handle sits above the skin and
-- sizes the same way FCF_Resize / FCF_StopResize do.
--
-- 1.12 / Turtle has no UI-ChatIM-SizeGrabber-*.blp (TBC art; not in
-- interface.MPQ or patch-4 / patch-9). The stock handle is ChatFrameBorder
-- with the BottomRight texcoords from FloatingChatFrame.xml.

local M = IchaUIChat
local G = M.Register("Grip", {})

local SIZE = 16
local TEX = "Interface\\ChatFrame\\ChatFrameBorder"
-- Same coords as ChatFrameNResizeBottomRightTexture.
local U1, U2, V1, V2 = 0.75, 1, 0.7265625, 0.8515625

local function dockAnchor(cf)
    if not cf or not cf.isDocked then return true end
    local a = DEFAULT_CHAT_FRAME or M.frame(1)
    return cf == a
end

local function globalLock()
    if type(FCF_Get_ChatLocked) == "function" then
        local v
        pcall(function() v = FCF_Get_ChatLocked() end)
        if v then return true end
    end
    if CHAT_LOCKED == "1" or CHAT_LOCKED == 1 then return true end
    if SIMPLE_CHAT == "1" then return true end
    return false
end

local function windowLock(cf)
    if not cf then return true end
    if cf.isLocked then return true end
    if type(GetChatWindowInfo) == "function" and cf.GetID then
        local locked
        pcall(function()
            local n, fs, r, g, b, a, shown, lock = GetChatWindowInfo(cf:GetID())
            locked = lock
        end)
        if locked then return true end
    end
    return false
end

local function canShow(cf)
    if not cf or not cf.IsShown or not cf:IsShown() then return false end
    if globalLock() then return false end
    if windowLock(cf) then return false end
    if not dockAnchor(cf) then return false end
    return true
end

-- Docked non-anchor windows share ChatFrame1's size, like FCF_Resize.
local function sizeFrame(cf)
    if cf and cf.isDocked then
        return DEFAULT_CHAT_FRAME or M.frame(1) or cf
    end
    return cf
end

local function saveSize(cf)
    if not cf then return end
    if type(FCF_SavePositionAndDimensions) == "function" then
        pcall(function() FCF_SavePositionAndDimensions(cf) end)
        return
    end
    if type(SetChatWindowSavedDimensions) == "function" and cf.GetID and cf.GetWidth then
        pcall(function() SetChatWindowSavedDimensions(cf:GetID(), cf:GetWidth(), cf:GetHeight()) end)
    end
end

local function paint(tex, bright)
    if not tex then return end
    tex:SetTexture(TEX)
    tex:SetTexCoord(U1, U2, V1, V2)
    if IchaUI_PaintGoldVertex then
        IchaUI_PaintGoldVertex(tex, 0.93, 0.78, 0.35, 1, bright and true or nil)
    elseif tex.SetVertexColor then
        if bright then
            tex:SetVertexColor(1, 0.92, 0.55, 1)
        else
            tex:SetVertexColor(0.93, 0.78, 0.35, 1)
        end
    end
end

local function stop(g)
    if not g or not g._sizing then return end
    g._sizing = nil
    g:SetScript("OnUpdate", nil)
    local target = g._target
    g._target = nil
    if not target then return end
    if target.StopMovingOrSizing then target:StopMovingOrSizing() end
    target.resizing = nil
    if target == DEFAULT_CHAT_FRAME or target == M.frame(1) then
        if type(FCF_DockUpdate) == "function" then pcall(FCF_DockUpdate) end
    end
    saveSize(target)
    paint(g.art, nil)
end

local function watch()
    if not this._sizing then return end
    if IsMouseButtonDown then
        local down
        pcall(function() down = IsMouseButtonDown("LeftButton") and true or false end)
        if down == false then
            stop(this)
            return
        end
    end
end

local function place(g, cf)
    local chrome = cf._waChrome or getglobal(cf:GetName() and (cf:GetName() .. "WAChrome") or "")
    local rel = (chrome and chrome.IsShown and chrome:IsShown()) and chrome or cf
    g:ClearAllPoints()
    g:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", -1, 1)
    local fl = (cf:GetFrameLevel() or 1) + 10
    if chrome and chrome.GetFrameLevel then
        local cl = chrome:GetFrameLevel() or 0
        if fl <= cl then fl = cl + 2 end
    end
    g:SetFrameLevel(fl)
end

local function ensure(cf)
    if cf._icGrip then return cf._icGrip end
    local name = cf:GetName()
    local g = CreateFrame("Button", name and (name .. "IchaGrip") or nil, cf)
    g:SetWidth(SIZE)
    g:SetHeight(SIZE)
    g:EnableMouse(true)
    g._icFrame = cf

    local bg = g:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(g)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.05, 0.05, 0.06, 0.72)
    g.bg = bg

    local art = g:CreateTexture(nil, "ARTWORK")
    art:SetAllPoints(g)
    paint(art, nil)
    g.art = art

    local hl = g:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(g)
    hl:SetTexture(TEX)
    hl:SetTexCoord(U1, U2, V1, V2)
    hl:SetVertexColor(1, 0.95, 0.7, 1)
    if hl.SetBlendMode then hl:SetBlendMode("ADD") end

    g:SetScript("OnMouseDown", function()
        if arg1 and arg1 ~= "LeftButton" then return end
        local cf = this._icFrame
        if not canShow(cf) then return end
        local target = sizeFrame(cf)
        if not target or not target.StartSizing then return end
        if globalLock() or windowLock(target) then return end
        this._target = target
        this._sizing = true
        target.resizing = 1
        paint(this.art, true)
        target:StartSizing("BOTTOMRIGHT")
        this:SetScript("OnUpdate", watch)
    end)
    g:SetScript("OnMouseUp", function()
        stop(this)
    end)
    g:SetScript("OnHide", function()
        stop(this)
    end)
    g:SetScript("OnEnter", function()
        if not GameTooltip then return end
        GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT")
        GameTooltip:SetText("Drag to resize")
        GameTooltip:Show()
    end)
    g:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    cf._icGrip = g
    return g
end

function G.refresh()
    local i
    for i = 1, M.numWindows() do
        local cf = M.frame(i)
        if cf then
            if canShow(cf) then
                local g = ensure(cf)
                place(g, cf)
                g:Show()
            elseif cf._icGrip then
                stop(cf._icGrip)
                cf._icGrip:Hide()
            end
        end
    end
end

local q = CreateFrame("Frame")
q:Hide()
q:SetScript("OnUpdate", function()
    this:Hide()
    G.refresh()
end)

local function queue()
    q:Show()
end

local function hookAfter(fname)
    local old = getglobal(fname)
    if type(old) ~= "function" then return end
    setglobal(fname, function(a1, a2, a3, a4)
        local r = old(a1, a2, a3, a4)
        queue()
        return r
    end)
end

function G:login()
    if G._hooked then return end
    G._hooked = true
    hookAfter("FCF_SetLocked")
    hookAfter("FCF_Set_ChatLocked")
    hookAfter("FCF_ToggleLock")
    hookAfter("FCF_DockFrame")
    hookAfter("FCF_UnDockFrame")
    hookAfter("FCF_OpenNewWindow")
    local ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", queue)
    pcall(function() ev:RegisterEvent("UPDATE_CHAT_WINDOWS") end)
    pcall(function() ev:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS") end)
    local i
    for i = 1, M.numWindows() do
        local cf = M.frame(i)
        if cf and not cf._icGripShowHook then
            cf._icGripShowHook = true
            local old = cf:GetScript("OnShow")
            cf:SetScript("OnShow", function()
                if old then old() end
                queue()
            end)
        end
    end
    queue()
end

function G:world()
    queue()
    M.After(1.2, G.refresh)
end

function G:apply()
    queue()
end
