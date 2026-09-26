-- IchaUI v2.1: plain frames (no per-slot WeakestAuras).
-- Left 1-3 | hero bar center | right 4-6. Left grows right->left; right left->right.

local BASE_W, BASE_H = 40, 30
local iconGap = 2.0
local BAR7_SCALE = 1.55 -- default hero scale; overridden by DB.heroScale
local heroScale = BAR7_SCALE
local iconScale = 1.0
local showHotkeys = true
local ICON_INSET = 1

local bindMode = false
local hoveredBtn = nil
local buttonOnKeyDown
local setBindMode
local clearBind

local buttons = {}
local pool = {}



local function iconW()
    return math.floor(BASE_W * iconScale + 0.5)
end
local function iconH()
    return math.floor(BASE_H * iconScale + 0.5)
end

-- Fit sweep to the icon texture rect
local function borderEdgeSize()
    -- Thicker edge that scales with icons
    local e = math.floor(16 * iconScale + 0.5)
    if e < 10 then e = 10 end
    if e > 28 then e = 28 end
    return e
end

local function borderOutset()
    -- Push border frame outside the icon so gold wraps the edge
    local o = math.floor(3 * iconScale + 0.5)
    if o < 2 then o = 2 end
    return o
end

local function applyBorder(b)
    if not b or not b.border then return end
    local e = borderEdgeSize()
    local o = borderOutset()
    b.border:ClearAllPoints()
    b.border:SetPoint("TOPLEFT", b, "TOPLEFT", -o, o)
    b.border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", o, -o)
    b.border:SetBackdrop({
        bgFile = nil,
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = e,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    IchaUI_PaintGoldBorder(b.border, 1)
end

local CD_BASE = 36 -- Blizzard cooldown Model is authored for ~36px buttons

local function sizeCooldown(b)
    if not b or not b.cooldown then return end
    local w = b._cw or b:GetWidth() or iconW()
    local h = b._ch or b:GetHeight() or iconH()
    if w < 1 then w = iconW() end
    if h < 1 then h = iconH() end

    b.cooldown:SetParent(b)
    b.cooldown:ClearAllPoints()
    -- Reset scale before applying size (recycled buttons)
    b.cooldown:SetScale(1)

    local round = b._formShape == "circle" or b._formShape == "tooltip" or b._formShape == "portrait"
    local edged = b._formShape == "square" or b._formShape == "rect"
    if IchaUI_FormIsRound then round = IchaUI_FormIsRound(b._formShape) end
    if IchaUI_FormIsEdged then edged = IchaUI_FormIsEdged(b._formShape) end
    local hole = w
    if round and not b._hole then hole = math.floor(w * 0.75 + 0.5) end
    if b._formShape == "circle" then
        hole = math.floor(w * 0.62 + 0.5)
    elseif b._formShape == "tooltip" or b._formShape == "portrait" then
        hole = math.floor(w * 0.96 + 0.5)
        if b._formShape == "portrait" then hole = math.floor(w * 0.94 + 0.5) end
    end
    if b._hole and b._hole > 4 and round then hole = b._hole end
    if round and b.icon and b.icon.GetWidth and b.icon:GetWidth() > 4 then
        hole = b.icon:GetWidth()
    end
    local square = math.abs(w - h) < 2
    if round then
        -- The model's dark sweep is about 1/1.4 of its frame. With the black
        -- mask it could fill the icon (1.4x). A portrait icon has no mask, so
        -- the frame is the hole and the sweep's corners land on the icon's rim.
        local grow = 1.4
        if b._iconPortrait then grow = 1.0 end
        local scale = hole * grow / CD_BASE
        if scale < 0.4 then scale = 0.4 end
        b.cooldown:SetWidth(CD_BASE)
        b.cooldown:SetHeight(CD_BASE)
        b.cooldown:SetScale(scale)
    elseif edged then
        local iw = b._innerW or w
        local ih = b._innerH or h
        local cw = math.floor(iw * 1.4 + 0.5)
        local ch = math.floor(ih * 1.4 + 0.5)
        if cw > w then cw = w end
        if ch > h then ch = h end
        if cw < 8 then cw = 8 end
        if ch < 8 then ch = 8 end
        if math.abs(cw - ch) < 2 then
            local scale = cw / CD_BASE
            if scale < 0.4 then scale = 0.4 end
            b.cooldown:SetWidth(CD_BASE)
            b.cooldown:SetHeight(CD_BASE)
            b.cooldown:SetScale(scale)
        else
            b.cooldown:SetWidth(cw)
            b.cooldown:SetHeight(ch)
        end
    elseif square then
        local scale = w / CD_BASE
        if scale < 0.5 then scale = 0.5 end
        b.cooldown:SetWidth(CD_BASE)
        b.cooldown:SetHeight(CD_BASE)
        b.cooldown:SetScale(scale)
    else
        b.cooldown:SetWidth(w)
        b.cooldown:SetHeight(h)
    end
    -- The sweep centers on the icon. Offsets are in the model's scaled units.
    local cs = b.cooldown:GetScale() or 1
    if cs <= 0 then cs = 1 end
    b.cooldown:SetPoint("CENTER", b, "CENTER", (b._iconDX or 0) / cs, (b._iconDY or 0) / cs)
    local base = b:GetFrameLevel() or 1
    b.cooldown:SetFrameLevel(base + 4)
    if b._sweepOn then
        b.cooldown:Hide()
    else
        b.cooldown:Show()
    end
    if b.ringHost then b.ringHost:SetFrameLevel(base + 8) end
    if b.textLayer then b.textLayer:SetFrameLevel(base + 10) end
    -- b.iconMask (level +6) covers both the icon and the sweep corners.
    if IchaUI_PlaceFormMask then IchaUI_PlaceFormMask(b) end
end







function layoutIcon(b, pushed)
    if not b or not b.icon then return end
    -- Shaped buttons own their icon size. Re-anchoring on press stretched the
    -- art to the full button, then the next refresh snapped it back.
    if b._formShape then return end
    local inset = ICON_INSET
    local ox, oy = 0, 0
    if pushed then ox, oy = 1, -1 end
    b.icon:ClearAllPoints()
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", inset + ox, -(inset - oy))
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -(inset - ox), inset + oy)
    if b.roundMask then
        b.roundMask:ClearAllPoints()
        b.roundMask:SetPoint("TOPLEFT", b.icon, "TOPLEFT", 0, 0)
        b.roundMask:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 0, 0)
    end
end

local applyIconUsable -- filled after pagedId()

function pushButton(buttonId)
    local b = buttons[buttonId]
    if not b then return end
    b._pushed = true
    layoutIcon(b, true)
    if b.icon then
        if applyIconUsable then
            applyIconUsable(b, true)
        else
            b.icon:SetVertexColor(0.82, 0.82, 0.82)
        end
    end
    -- A round icon has transparent corners; the square shade would show there.
    -- The pressed vertex tint above is enough on its own.
    if b.pushTex and IchaUI_FormOverlay and IchaUI_FormOverlay(b, b.pushTex, "shade") then
        b.pushTex:SetDrawLayer("OVERLAY", 7)
        b.pushTex:SetAlpha(0.18)
        b.pushTex:Show()
    elseif b.pushTex then
        b.pushTex:ClearAllPoints()
        b.pushTex:SetAllPoints(b.icon or b)
        b.pushTex:SetDrawLayer("OVERLAY", 7)
        b.pushTex:SetAlpha(0.18)
        b.pushTex:Show()
    end
    -- keep gold border unchanged while pressed
end

function releaseButton(buttonId)
    local b = buttons[buttonId]
    if not b then return end
    if not b._pushed then return end
    b._pushed = false
    layoutIcon(b, false)
    if b.pushTex then
        b.pushTex:Hide()
        b.pushTex:SetAlpha(0.18)
    end
    if b.icon then
        if applyIconUsable then
            applyIconUsable(b, false)
        end
        -- never force white here — that flashes through out-of-mana tint
    end
end

local function setHoverGlow(b, on)
    if not b then return end
    if not b.hoverGlow then return end
    if on then
        local g = b.hoverGlow
        g:ClearAllPoints()
        if IchaUI_FormOverlay and IchaUI_FormOverlay(b, g, "glow") then
            -- shaped: round glow on the opening, or the icon rect
        elseif b._iconPortrait and b.icon then
            g:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
            g:SetAllPoints(b.icon)
        else
            g:SetTexture("Interface/Buttons/ButtonHilight-Square")
            g:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
            g:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
        end
        g:Show()
    else
        b.hoverGlow:Hide()
    end
end


-- ACTIONBUTTON keybinds: fire UseAction ourselves.
-- Blizzard ActionButton frames are hidden (no Bongos), so stock ActionButtonDown
-- often no-ops — that is why binds felt dead after removing Bongos.
local _ActionButtonDown = ActionButtonDown
local _ActionButtonUp = ActionButtonUp

local function actionIdForBind(buttonId)
    if BActionButton and BActionButton.GetPagedID then
        return BActionButton.GetPagedID(buttonId)
    end
    return buttonId
end

local function ourActionButtonDown(id)
    pushButton(id)
    local actionId = actionIdForBind(id)
    if IchaUIShamanExtras_NotifyBoundTexture and GetActionTexture then
        IchaUIShamanExtras_NotifyBoundTexture(GetActionTexture(actionId))
    end
    if HasAction and HasAction(actionId) and UseAction then
        UseAction(actionId, 1, 0)
    elseif _ActionButtonDown then
        -- Fallback if slot empty / API missing
        _ActionButtonDown(id)
    end
end
local function ourActionButtonUp(id)
    releaseButton(id)
    -- Do not call stock ActionButtonUp UseAction path — already fired on Down
end

local function hookActionButtons()
    -- Bongos may replace these after load — re-wrap if needed
    if ActionButtonDown ~= ourActionButtonDown then
        _ActionButtonDown = ActionButtonDown
        ActionButtonDown = ourActionButtonDown
    end
    if ActionButtonUp ~= ourActionButtonUp then
        _ActionButtonUp = ActionButtonUp
        ActionButtonUp = ourActionButtonUp
    end
end
hookActionButtons()

local function releaseAllPushed()
    for id, b in pairs(buttons) do
        if b._pushed then releaseButton(id) end
    end
end

local function abbreviateKey(key)
    if not key or key == "" then return "" end
    key = string.upper(key)
    key = string.gsub(key, " ", "")
    key = string.gsub(key, "ALT%-", "A")
    key = string.gsub(key, "CTRL%-", "C")
    key = string.gsub(key, "SHIFT%-", "S")
    key = string.gsub(key, "NUMPAD", "N")
    key = string.gsub(key, "BACKSPACE", "BSpc")
    key = string.gsub(key, "HOME", "Hm")
    key = string.gsub(key, "END", "End")
    key = string.gsub(key, "INSERT", "Ins")
    key = string.gsub(key, "DELETE", "Del")
    key = string.gsub(key, "MIDDLEMOUSE", "M3")
    key = string.gsub(key, "MOUSEBUTTON4", "M4")
    key = string.gsub(key, "MOUSEBUTTON5", "M5")
    key = string.gsub(key, "MOUSEWHEELDOWN", "MwDn")
    key = string.gsub(key, "MOUSEWHEELUP", "MwUp")
    key = string.gsub(key, "PAGEDOWN", "PgDn")
    key = string.gsub(key, "PAGEUP", "PgUp")
    key = string.gsub(key, "SPACEBAR", "Spc")
    key = string.gsub(key, "SPACE", "Spc")
    return key
end

local function bindingTextFor(buttonId)
    if not GetBindingKey or not GetBindingText then return "" end
    local key = GetBindingKey("CLICK IchaUIBtn" .. buttonId .. ":LeftButton")
    if (not key or key == "") then
        key = GetBindingKey("ACTIONBUTTON" .. buttonId)
    end
    if (not key or key == "") then
        key = GetBindingKey("CLICK BActionButton" .. buttonId .. ":LeftButton")
    end
    if not key or key == "" then return "" end
    return abbreviateKey(GetBindingText(key, "KEY_"))
end

local HOTKEY_BASE = 9
local COUNT_BASE = 11

local function scaleFonts(b)
    if not b then return end
    local path = "Fonts/FRIZQT__.TTF"
    local hk = math.max(6, math.floor(HOTKEY_BASE * iconScale + 0.5))
    local ck = math.max(7, math.floor(COUNT_BASE * iconScale + 0.5))
    if b.hotkey then
        b.hotkey:SetFont(path, hk, "OUTLINE")
        local maxW = (b:GetWidth() or iconW()) - 10
        if maxW < 8 then maxW = 8 end
        b.hotkey:SetWidth(maxW)
        b.hotkey:SetHeight(hk + 2)
        b.hotkey:SetJustifyH("CENTER")
        b.hotkey:SetJustifyV("BOTTOM")
        b.hotkey:SetNonSpaceWrap(false)
    end
    if b.count then
        b.count:SetFont(path, ck, "OUTLINE")
    end
end

local function updateHotkey(b)
    if not b or not b.hotkey then return end
    if not showHotkeys then
        b.hotkey:SetText("")
        b.hotkey:Hide()
        return
    end
    scaleFonts(b)
    local text = bindingTextFor(b.buttonId)
    if not text or text == "" then
        b.hotkey:SetText("")
        b.hotkey:Hide()
        return
    end
    -- Shrink/truncate until it fits inside the button width
    local maxW = (b:GetWidth() or iconW()) - 10
    b.hotkey:SetText(text)
    if b.hotkey.GetStringWidth then
        local guard = 0
        while b.hotkey:GetStringWidth() > maxW and string.len(text) > 1 and guard < 20 do
            text = string.sub(text, 1, string.len(text) - 1)
            b.hotkey:SetText(text)
            guard = guard + 1
        end
    elseif string.len(text) > 4 then
        -- Fallback when GetStringWidth is missing: hard cap
        local cap = 4
        if iconScale < 0.85 then cap = 3 end
        if iconScale < 0.7 then cap = 2 end
        text = string.sub(text, 1, cap)
        b.hotkey:SetText(text)
    end
    b.hotkey:Show()
end






local root = CreateFrame("Frame", "IchaUILayoutRoot", UIParent)
root:SetFrameStrata("MEDIUM")
root:SetWidth(1)
root:SetHeight(1)
root:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 90)
root:SetMovable(true)
root:EnableMouse(false)
root:RegisterForDrag("LeftButton")

local moving = false

-- Keep the bar's visual center fixed when width changes. After StartMoving,
-- WoW often reanchors to BOTTOMLEFT; SetWidth then slides the whole stack right.
local function rootScreenCenter()
    local cx, cy = root:GetCenter()
    if not cx or not cy then return nil end
    local rs = root:GetEffectiveScale() or 1
    local us = UIParent:GetEffectiveScale() or 1
    return cx * rs / us, cy * rs / us
end

local function pinRootCenter(sx, sy)
    if not sx or not sy then return end
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx, sy)
end

local function setRootSize(w, h)
    -- While dragging use live center; otherwise stick to saved layoutX/Y
    local sx, sy
    if moving then
        sx, sy = rootScreenCenter()
    elseif IchaUIDB and IchaUIDB.layoutX ~= nil and IchaUIDB.layoutY ~= nil then
        sx, sy = tonumber(IchaUIDB.layoutX), tonumber(IchaUIDB.layoutY)
    else
        sx, sy = rootScreenCenter()
    end
    -- Pin CENTER before the size change. A TOPLEFT anchor left by StartMoving
    -- grows the cluster down and right, then the old pin snapped it back.
    if sx and sy then
        pinRootCenter(sx, sy)
    end
    root:SetWidth(w)
    root:SetHeight(h)
end

local function saveRootPos()
    local sx, sy = rootScreenCenter()
    if not sx then return end
    if not IchaUIDB then IchaUIDB = {} end
    IchaUIDB.layoutX = sx
    IchaUIDB.layoutY = sy
    pinRootCenter(sx, sy)
end

local function restoreRootPos()
    if not IchaUIDB then return end
    local sx, sy = IchaUIDB.layoutX, IchaUIDB.layoutY
    if sx and sy then
        pinRootCenter(sx, sy)
    end
end

root:SetScript("OnDragStart", function() this:StartMoving() end)
root:SetScript("OnDragStop", function() this:StopMovingOrSizing(); saveRootPos() end)

-- Action-bar / drawer icon strata (1–5). Totem duration text is totems.textStrata.
IchaUI_STRATA_NAMES = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }

local function strataFromValue(v, defaultIdx)
    if not defaultIdx then defaultIdx = 3 end
    if type(v) == "string" then
        local u = string.upper(v)
        local i
        for i = 1, 5 do
            if IchaUI_STRATA_NAMES[i] == u then
                return IchaUI_STRATA_NAMES[i], i
            end
        end
        if u == "TOOLTIP" then
            return "DIALOG", 5
        end
        return IchaUI_STRATA_NAMES[defaultIdx], defaultIdx
    end
    v = tonumber(v)
    if not v then v = defaultIdx end
    v = math.floor(v + 0.5)
    -- Out of 1–5 is corrupt (not a user BACKGROUND pick) — default MEDIUM/HIGH
    if v < 1 or v > 5 then
        v = defaultIdx
    end
    return IchaUI_STRATA_NAMES[v], v
end

function IchaUI_StrataFromValue(v, defaultIdx)
    return strataFromValue(v, defaultIdx)
end

function IchaUI_GetIconStrata()
    if not IchaUIDB then IchaUIDB = {} end
    return strataFromValue(IchaUIDB.iconStrata, 3)
end

function IchaUI_GetTotemTextStrata()
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.totems then IchaUIDB.totems = {} end
    return strataFromValue(IchaUIDB.totems.textStrata, 4)
end

function IchaUI_DrawerOpenStrata()
    local name, idx = IchaUI_GetIconStrata()
    local up = idx + 1
    if up > 5 then up = 5 end
    return IchaUI_STRATA_NAMES[up], up
end

function IchaUI_ApplyLayoutIconStrata()
    local name = IchaUI_GetIconStrata()
    if root then
        pcall(function()
            root:SetFrameStrata(name)
        end)
    end
end

function IchaUI_ApplyIconStrata()
    IchaUI_ApplyLayoutIconStrata()
    if IchaUI_ApplyTotemStrata then IchaUI_ApplyTotemStrata() end
    if IchaUI_ApplyShamanExtrasStrata then IchaUI_ApplyShamanExtrasStrata() end
    if IchaUI_ApplyRecallIconStrata then IchaUI_ApplyRecallIconStrata() end
end

function IchaUI_SetIconStrata(v)
    local name, idx = strataFromValue(v, 3)
    if not IchaUIDB then IchaUIDB = {} end
    IchaUIDB.iconStrata = name
    IchaUI_ApplyIconStrata()
    return name, idx
end

function IchaUI_SetTotemTextStrata(v)
    local name, idx = strataFromValue(v, 4)
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.totems then IchaUIDB.totems = {} end
    IchaUIDB.totems.textStrata = name
    if IchaUI_ApplyTotemStrata then IchaUI_ApplyTotemStrata() end
    if IchaUI_ApplyShamanExtrasStrata then IchaUI_ApplyShamanExtrasStrata() end
    return name, idx
end

-- Visible grab area shown only in move mode
local mover = CreateFrame("Frame", "IchaUILayoutMover", root)
mover:SetAllPoints(root)
mover:SetFrameLevel((root:GetFrameLevel() or 1) + 20)
mover:EnableMouse(true)
mover:RegisterForDrag("LeftButton")
mover:Hide()
local bg = mover:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(mover)
bg:SetTexture(1, 1, 1, 1)
bg:SetVertexColor(0.15, 0.45, 0.95, 0.35)
local top = mover:CreateTexture(nil, "OVERLAY")
top:SetTexture(1, 1, 1, 1)
top:SetVertexColor(0.4, 0.85, 1, 1)
top:SetHeight(2)
top:SetPoint("TOPLEFT", mover, "TOPLEFT")
top:SetPoint("TOPRIGHT", mover, "TOPRIGHT")
local bot = mover:CreateTexture(nil, "OVERLAY")
bot:SetTexture(1, 1, 1, 1)
bot:SetVertexColor(0.4, 0.85, 1, 1)
bot:SetHeight(2)
bot:SetPoint("BOTTOMLEFT", mover, "BOTTOMLEFT")
bot:SetPoint("BOTTOMRIGHT", mover, "BOTTOMRIGHT")
local left = mover:CreateTexture(nil, "OVERLAY")
left:SetTexture(1, 1, 1, 1)
left:SetVertexColor(0.4, 0.85, 1, 1)
left:SetWidth(2)
left:SetPoint("TOPLEFT", mover, "TOPLEFT")
left:SetPoint("BOTTOMLEFT", mover, "BOTTOMLEFT")
local right = mover:CreateTexture(nil, "OVERLAY")
right:SetTexture(1, 1, 1, 1)
right:SetVertexColor(0.4, 0.85, 1, 1)
right:SetWidth(2)
right:SetPoint("TOPRIGHT", mover, "TOPRIGHT")
right:SetPoint("BOTTOMRIGHT", mover, "BOTTOMRIGHT")
local label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
label:SetPoint("CENTER", mover, "CENTER")
label:SetText("Drag to move  |  /icha move to lock")
label:SetTextColor(1, 1, 1)
mover:SetScript("OnDragStart", function()
    root:StartMoving()
end)
mover:SetScript("OnDragStop", function()
    root:StopMovingOrSizing()
    saveRootPos()
end)

local gridShown = false

local function cursorHasAction()
    if gridShown then return true end
    if CursorHasSpell and CursorHasSpell() then return true end
    if CursorHasItem and CursorHasItem() then return true end
    if CursorHasMacro and CursorHasMacro() then return true end
    if GetCursorInfo then
        local kind = GetCursorInfo()
        if kind then return true end
    end
    return false
end


local function setMoveMode(on)
    moving = on and true or false
    root:EnableMouse(moving)
    if moving then
        mover:ClearAllPoints()
        mover:SetAllPoints(root)
        mover:Show()
    else
        mover:Hide()
        if not moving then saveRootPos() end
    end
end

function IchaUI_SetClusterMove(on)
    setMoveMode(on and true or false)
end

function IchaUI_SaveLayoutPos()
    saveRootPos()
end

function IchaUI_LayoutRoot()
    return root
end

local function barStart(barId)
    if BActionBar and BActionBar.GetStart then return BActionBar.GetStart(barId) end
    local n = (BActionSets and BActionSets.g and BActionSets.g.numActionBars) or 10
    return math.floor(120 / n) * (barId - 1) + 1
end

local function barSize(barId)
    if BActionBar and BActionBar.GetSize then return BActionBar.GetSize(barId) end
    if BActionSets and BActionSets[barId] and BActionSets[barId].size then
        return BActionSets[barId].size
    end
    local n = (BActionSets and BActionSets.g and BActionSets.g.numActionBars) or 10
    return math.floor(120 / n)
end

-- No fixed count cap. Each extra bar takes a free block of 12, else 8,
-- else 4, else 3, else 2, else 1 slot, and stops only when nothing is free.
-- Blocks must not overlap bars 1-6, existing extras, or hero bars.

local function actionOwned(barId)
    barId = tonumber(barId) or 1
    if barId <= 6 then return barSize(barId), barStart(barId) end
    local list = IchaUIDB and IchaUIDB.actionExtras
    local rec = list and list[barId - 6]
    if type(rec) ~= "table" then return 0, 0 end
    return tonumber(rec.slotCount) or 0, tonumber(rec.slotBase) or 0
end

local function fitBarGrid(cols, rows, cap)
    cols = math.floor(tonumber(cols) or cap)
    rows = math.floor(tonumber(rows) or 1)
    if cols < 1 then cols = 1 end
    if rows < 1 then rows = 1 end
    if not cap or cap < 1 then cap = 1 end
    if cols > cap then cols = cap end
    if rows > cap then rows = cap end
    while rows > 1 and cols * rows > cap do rows = rows - 1 end
    while cols > 1 and cols * rows > cap do cols = cols - 1 end
    if cols * rows > cap then
        cols = 1
        rows = 1
    end
    return cols, rows
end

local function barRec(barId)
    if barId > 6 then
        local list = IchaUIDB and IchaUIDB.actionExtras
        return list and list[barId - 6]
    end
    local g = IchaUIDB and IchaUIDB.barGrid
    return g and g[barId]
end

local function barGridSpec(barId)
    local owned, base = actionOwned(barId)
    if owned < 1 then return 1, 1, 0, base, 0, 1, 1, 1 end
    local cols, rows, slots = owned, 1, owned
    local scale, opacity, fade = 1, 1, 1
    local gap = iconGap
    local rec = barRec(barId)
    if type(rec) == "table" then
        if rec.cols then cols = rec.cols end
        if rec.rows then rows = rec.rows end
        if rec.slots then
            slots = rec.slots
        elseif rec.cols or rec.rows then
            slots = cols * rows
        end
        if rec.scale then scale = tonumber(rec.scale) or 1 end
        if rec.opacity then opacity = tonumber(rec.opacity) or 1 end
        if rec.fade ~= nil then fade = tonumber(rec.fade) or opacity else fade = opacity end
        if rec.gap ~= nil then gap = tonumber(rec.gap) or iconGap end
    end
    if slots < 1 then slots = 1 end
    if slots > owned then slots = owned end
    if cols < 1 then cols = 1 end
    if cols > slots then cols = slots end
    if rows < 1 then rows = 1 end
    local needRows = math.floor((slots + cols - 1) / cols)
    if rows < needRows then rows = needRows end
    if scale < 0.5 then scale = 0.5 end
    if scale > 2 then scale = 2 end
    if opacity < 0 then opacity = 0 end
    if opacity > 1 then opacity = 1 end
    if fade < 0 then fade = 0 end
    if fade > 1 then fade = 1 end
    if gap < 0 then gap = 0 end
    if gap > 20 then gap = 20 end
    return cols, rows, owned, base, slots, scale, opacity, fade, gap
end

local function barGridIds(barId, showEmpty)
    local cols, rows, owned, base, slots = barGridSpec(barId)
    local n = slots or (cols * rows)
    if n > owned then n = owned end
    if n < 0 then n = 0 end
    local rec = barRec(barId)
    local ids = {}
    local i
    for i = 0, n - 1 do
        local id = base + i
        if id >= 1 and id <= 120 then
            local actionId = id
            if BActionButton and BActionButton.GetPagedID then
                actionId = BActionButton.GetPagedID(id)
            end
            local show = showEmpty
            if rec and rec.layout == "radial" then show = true end
            if not show and HasAction and HasAction(actionId) then show = true end
            if show then table.insert(ids, id) end
        end
    end
    return ids, cols
end

local function blockHits(lo, hi, b, c)
    b = tonumber(b)
    c = tonumber(c)
    if not b or not c or c < 1 then return false end
    local top = b + c - 1
    if hi < b or lo > top then return false end
    return true
end

local function actionBlockFree(lo, hi)
    if lo < 1 or hi > 120 or lo > hi then return false end
    local i
    for i = 1, 6 do
        if blockHits(lo, hi, barStart(i), barSize(i)) then return false end
    end
    if IchaUI_HeroButtonIds then
        local ids = IchaUI_HeroButtonIds()
        if ids and ids[1] then
            if blockHits(lo, hi, ids[1], table.getn(ids)) then return false end
        end
    end
    local list = IchaUIDB and IchaUIDB.heroExtras
    if type(list) == "table" then
        for i = 1, table.getn(list) do
            local e = list[i]
            if blockHits(lo, hi, e and e.slotBase, e and e.slotCount) then return false end
        end
    end
    list = IchaUIDB and IchaUIDB.actionExtras
    if type(list) == "table" then
        for i = 1, table.getn(list) do
            local e = list[i]
            if blockHits(lo, hi, e and e.slotBase, e and e.slotCount) then return false end
        end
    end
    return true
end

function IchaUI_ActionBarCount()
    local n = 6
    if IchaUIDB and type(IchaUIDB.actionExtras) == "table" then
        n = 6 + table.getn(IchaUIDB.actionExtras)
    end
    return n
end

function IchaUI_ActionBarGrid(index)
    local cols, rows, owned, base, slots = barGridSpec(index)
    return cols, rows, slots, owned
end

function IchaUI_ActionBarLook(index)
    local cols, rows, owned, base, slots, scale, opacity, fade, gap = barGridSpec(index)
    return scale, opacity, fade, slots, cols, rows, owned, gap
end

function IchaUI_ActionBarForm(index)
    local rec = barRec(index)
    local shape, layout, spread, arc, rot = "rect", "grid", 90, 360, 90
    if type(rec) == "table" then
        if rec.shape then shape = rec.shape end
        if rec.layout == "radial" then layout = "radial" end
        if rec.spread then spread = rec.spread end
        if rec.arc then arc = rec.arc end
        if rec.rot ~= nil then rot = rec.rot end
    end
    if IchaUI_FormShapeNorm then shape = IchaUI_FormShapeNorm(shape) end
    if IchaUI_DrawerNormSpread then spread = IchaUI_DrawerNormSpread(spread) end
    if IchaUI_DrawerNormArc then arc = IchaUI_DrawerNormArc(arc) end
    if IchaUI_DrawerNormRot then rot = IchaUI_DrawerNormRot(rot) end
    return shape, layout, spread, arc, rot
end

local function writeBarFields(index, fields)
    index = tonumber(index) or 1
    if not IchaUIDB then IchaUIDB = {} end
    local rec
    if index > 6 then
        local list = IchaUIDB.actionExtras
        rec = list and list[index - 6]
        if type(rec) ~= "table" then return nil end
    else
        if type(IchaUIDB.barGrid) ~= "table" then IchaUIDB.barGrid = {} end
        if type(IchaUIDB.barGrid[index]) ~= "table" then IchaUIDB.barGrid[index] = {} end
        rec = IchaUIDB.barGrid[index]
    end
    local k, v
    for k, v in pairs(fields) do
        rec[k] = v
    end
    return rec
end

function IchaUI_ActionBarSetForm(index, shape, layout, spread, arc, rot)
    local fields = {}
    if shape then fields.shape = shape end
    if layout then fields.layout = layout end
    if spread then fields.spread = spread end
    if arc then fields.arc = arc end
    if rot ~= nil then fields.rot = rot end
    if not writeBarFields(index, fields) then return end
    if IchaUI_RefreshActionBar then IchaUI_RefreshActionBar(index) end
end

function IchaUI_ActionBarSetGrid(index, cols, rows, slots)
    index = tonumber(index) or 1
    local owned = actionOwned(index)
    if owned < 1 then return end
    slots = math.floor(tonumber(slots) or 0)
    if slots < 1 then
        cols = math.floor(tonumber(cols) or 1)
        rows = math.floor(tonumber(rows) or 1)
        if cols < 1 then cols = 1 end
        if rows < 1 then rows = 1 end
        slots = cols * rows
    end
    if slots > owned then slots = owned end
    cols = math.floor(tonumber(cols) or 1)
    rows = math.floor(tonumber(rows) or 1)
    if cols < 1 then cols = 1 end
    if rows < 1 then rows = 1 end
    if cols > slots then cols = slots end
    if rows > slots then rows = slots end
    writeBarFields(index, { cols = cols, rows = rows, slots = slots })
    if IchaUI_RefreshActionBar then IchaUI_RefreshActionBar(index) end
    return cols, rows, slots
end

function IchaUI_ActionBarSetStyle(index, scale, opacity, fade, gap)
    index = tonumber(index) or 1
    scale = tonumber(scale) or 1
    opacity = tonumber(opacity) or 1
    if fade == nil then fade = opacity end
    fade = tonumber(fade) or opacity
    if scale < 0.5 then scale = 0.5 end
    if scale > 2 then scale = 2 end
    if opacity < 0 then opacity = 0 end
    if opacity > 1 then opacity = 1 end
    if fade < 0 then fade = 0 end
    if fade > 1 then fade = 1 end
    local fields = { scale = scale, opacity = opacity, fade = fade }
    if gap ~= nil then
        gap = tonumber(gap) or 0
        if gap < 0 then gap = 0 end
        if gap > 20 then gap = 20 end
        fields.gap = gap
    end
    if not writeBarFields(index, fields) then return end
    if IchaUI_RefreshActionBar then IchaUI_RefreshActionBar(index) end
    return scale, opacity, fade, gap
end

function IchaUI_ActionBarAdd()
    if not IchaUIDB then IchaUIDB = {} end
    if type(IchaUIDB.actionExtras) ~= "table" then IchaUIDB.actionExtras = {} end
    local list = IchaUIDB.actionExtras
    local sizes = { 12, 8, 4, 3, 2, 1 }
    local base, count
    local si
    for si = 1, table.getn(sizes) do
        local need = sizes[si]
        local hi = 120
        while hi >= need do
            local lo = hi - need + 1
            if actionBlockFree(lo, hi) then
                base = lo
                count = need
                break
            end
            hi = hi - 1
        end
        if base then break end
    end
    if not base then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("IchaUI: not enough action slots left for another bar.")
        end
        return nil
    end
    local cols, rows = fitBarGrid(count, 1, count)
    local rec = {
        slotBase = base,
        slotCount = count,
        cols = cols,
        rows = rows,
        place = { detached = true, nudgeX = 0, nudgeY = 0 },
    }
    table.insert(list, rec)
    if IchaUI_RequestLayout then IchaUI_RequestLayout() end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("IchaUI: added action bar " .. tostring(6 + table.getn(list)) .. " (" .. count .. " slots).")
    end
    return 6 + table.getn(list)
end

function IchaUI_ActionBarRemove(index)
    index = tonumber(index) or 0
    if index <= 6 then return end
    if not IchaUIDB or type(IchaUIDB.actionExtras) ~= "table" then return end
    local list = IchaUIDB.actionExtras
    local rec = list[index - 6]
    if type(rec) ~= "table" then return end
    local cap = tonumber(rec.slotCount) or 0
    local b0 = tonumber(rec.slotBase) or 0
    local i
    for i = 0, cap - 1 do
        local id = b0 + i
        if PickupAction then PickupAction(id) end
        if ClearCursor then ClearCursor() end
    end
    table.remove(list, index - 6)
    if IchaUI_RequestLayout then IchaUI_RequestLayout() end
end

local function pagedId(buttonId)
    if BActionButton and BActionButton.GetPagedID then
        return BActionButton.GetPagedID(buttonId)
    end
    return buttonId
end

-- Keep OOM / unusable / OOR tint through press+release (no white flash)
-- OOR grey only when a target exists; no target → full color (if usable)
applyIconUsable = function(b, pressed)
    if not b or not b.icon or not b.buttonId then return end
    local actionId = pagedId(b.buttonId)
    if not (HasAction and HasAction(actionId)) then return end
    local usable, nomana = IsUsableAction(actionId)
    local oor = false
    local wantOor = true
    if IchaUI_CombatDB then
        local cd = IchaUI_CombatDB()
        if cd and cd.oorGrey == false then wantOor = false end
    end
    if wantOor and usable and UnitExists and UnitExists("target") and IsActionInRange then
        local r = IsActionInRange(actionId)
        -- 0 = out of range; 1 = in range; nil = no range requirement
        if r == 0 then
            oor = true
        end
    end
    if usable and not oor then
        if pressed then
            b.icon:SetVertexColor(0.82, 0.82, 0.82)
        else
            b.icon:SetVertexColor(1, 1, 1)
        end
    elseif usable and oor then
        if pressed then
            b.icon:SetVertexColor(0.45, 0.45, 0.45)
        else
            b.icon:SetVertexColor(0.55, 0.55, 0.55)
        end
    elseif nomana then
        if pressed then
            b.icon:SetVertexColor(0.40, 0.40, 0.85)
        else
            b.icon:SetVertexColor(0.5, 0.5, 1)
        end
    else
        if pressed then
            b.icon:SetVertexColor(0.32, 0.32, 0.32)
        else
            b.icon:SetVertexColor(0.4, 0.4, 0.4)
        end
    end
end

local function applyAspect(tex, w, h)
    if not tex then return end
    local pad, span = 0.07, 0.86
    if w == h then
        tex:SetTexCoord(pad, 1 - pad, pad, 1 - pad)
        return
    end
    if w > h then
        local crop = (1 - (h / w)) / 2
        tex:SetTexCoord(pad, 1 - pad, pad + crop * span, 1 - pad - crop * span)
    else
        local crop = (1 - (w / h)) / 2
        tex:SetTexCoord(pad + crop * span, 1 - pad - crop * span, pad, 1 - pad)
    end
end


-- Quality-tinted inner glow when an action-bar item is currently equipped
local EQUIP_QCOLOR = {
    [0] = { 0.62, 0.62, 0.62 }, -- poor
    [1] = { 1.00, 1.00, 1.00 }, -- common
    [2] = { 0.12, 1.00, 0.00 }, -- uncommon
    [3] = { 0.00, 0.44, 0.87 }, -- rare
    [4] = { 0.64, 0.21, 0.93 }, -- epic
    [5] = { 1.00, 0.50, 0.00 }, -- legendary
    [6] = { 0.90, 0.80, 0.50 }, -- artifact
}

local function qualityRGB(q)
    if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
        local c = ITEM_QUALITY_COLORS[q]
        return c.r or 1, c.g or 1, c.b or 1
    end
    local c = EQUIP_QCOLOR[q] or EQUIP_QCOLOR[1]
    return c[1], c[2], c[3]
end

local function equippedActionQuality(actionId)
    if not (IsEquippedAction and IsEquippedAction(actionId)) then
        return nil
    end
    local atex = GetActionTexture and GetActionTexture(actionId)
    local slot
    for slot = 0, 19 do
        local itex = GetInventoryItemTexture and GetInventoryItemTexture("player", slot)
        if atex and itex and itex == atex then
            if GetInventoryItemQuality then
                local q = GetInventoryItemQuality("player", slot)
                if q ~= nil then return q end
            end
            local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
            if link and GetItemInfo then
                local _, _, quality = GetItemInfo(link)
                if quality ~= nil then return quality end
            end
        end
    end
    return 1 -- equipped but quality unknown → common white
end

local EQUIP_GLOW_TEX = "Interface\\AddOns\\IchaUI\\media\\EquippedGlow.tga"

local function sizeEquipGlow(b)
    if not b or not b.equipGlow or not b.icon then return end
    -- Art's EquippedGlow.tga: white rim at outer edge — hug the icon exactly
    if IchaUI_FormIsRound and IchaUI_FormIsRound(b._formShape) and IchaUI_FormOverlay
        and IchaUI_FormOverlay(b, b.equipGlow, "glow") then
        return
    end
    b.equipGlow:ClearAllPoints()
    b.equipGlow:SetAllPoints(b.icon)
    b.equipGlow:SetTexture(EQUIP_GLOW_TEX)
end

local function updateEquipGlow(b, actionId)
    if not b or not b.equipGlow then return end
    local q = equippedActionQuality(actionId)
    if q == nil then
        b.equipGlow:Hide()
        return
    end
    local r, g, bl = qualityRGB(q)
    sizeEquipGlow(b)
    b.equipGlow:SetVertexColor(r, g, bl)
    b.equipGlow:SetAlpha(1)
    b.equipGlow:Show()
end

local function acquire(buttonId)
    local b = buttons[buttonId]
    if b then
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        return b
    end
    b = table.remove(pool)
    if b then
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    if not b then
        local name = "IchaUIBtn" .. buttonId
        b = CreateFrame("Button", name, root)
        b:EnableMouse(true)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:RegisterForDrag("LeftButton")
        -- Icon fills the button; rounded mat masks square corners (real curve, not square chops)
        local ICON_INSET = 1
        local icon = b:CreateTexture(name .. "Icon", "ARTWORK")
        icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        b.icon = icon
        local pushTex = b:CreateTexture(nil, "OVERLAY")
        pushTex:SetAllPoints(icon)
        pushTex:SetTexture("Interface/ChatFrame/ChatFrameBackground")
        pushTex:SetVertexColor(0, 0, 0)
        pushTex:SetAlpha(0.18)
        pushTex:Hide()
        b.pushTex = pushTex
        local hoverGlow = b:CreateTexture(nil, "OVERLAY")
        hoverGlow:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
        hoverGlow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
        hoverGlow:SetTexture("Interface/Buttons/ButtonHilight-Square")
        hoverGlow:SetBlendMode("ADD")
        hoverGlow:SetAlpha(0.35)
        hoverGlow:Hide()
        b.hoverGlow = hoverGlow
        -- Equipped-item quality glow (inside gold border)
        local equipGlow = b:CreateTexture(nil, "OVERLAY")
        equipGlow:SetTexture("Interface\\AddOns\\IchaUI\\media\\EquippedGlow.tga")
        equipGlow:SetBlendMode("ADD")
        equipGlow:SetAlpha(0.95)
        equipGlow:Hide()
        b.equipGlow = equipGlow
        local round = b:CreateTexture(nil, "ARTWORK")
        round:SetTexture("Interface\\AddOns\\IchaUI\\media\\roundmask.tga")
        round:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        round:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
        round:SetVertexColor(0, 0, 0, 1)
        b.roundMask = round
        -- Gold border above the icon/mask, under labels (edge scales with icons)
        local border = CreateFrame("Frame", nil, b)
        border:SetFrameLevel((b:GetFrameLevel() or 1) + 3)
        b.border = border
        applyBorder(b)
        local cd = CreateFrame("Model", name .. "Cooldown", b, "CooldownFrameTemplate")
        b.cooldown = cd
        sizeCooldown(b)
        -- Text above border, inset from edges so it stays readable
        local textLayer = CreateFrame("Frame", nil, b)
        textLayer:SetAllPoints(b)
        textLayer:SetFrameLevel((b:GetFrameLevel() or 1) + 8)
        b.textLayer = textLayer
        local hotkey = textLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
        hotkey:SetPoint("BOTTOM", textLayer, "BOTTOM", 0, 5)
        hotkey:SetJustifyH("CENTER")
        hotkey:SetTextColor(1, 0.95, 0.75)
        hotkey:SetWidth(20)
        hotkey:SetNonSpaceWrap(false)
        b.hotkey = hotkey
        local count = textLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        count:SetPoint("TOPRIGHT", textLayer, "TOPRIGHT", -5, -4)
        b.count = count
        -- Pickup/place must never fall through to UseAction (potions drink, spells fire).
        local function isQuickMove()
            if BActionSets_IsQuickMoveKeyDown and BActionSets_IsQuickMoveKeyDown() then
                return true
            end
            if IsShiftKeyDown and IsShiftKeyDown() then
                return true
            end
            return false
        end
        b:SetScript("OnClick", function()
            if bindMode then
                if arg1 == "RightButton" then
                    clearBind(this.buttonId)
                end
                return
            end
            if this._ichaSkipUse then
                this._ichaSkipUse = nil
                this._ichaMouseClick = nil
                return
            end
            -- Keyboard CLICK binds (Shift+1) fire OnClick without OnMouseDown.
            -- Only a real mouse press may pick up / rearrange.
            local fromMouse = this._ichaMouseClick
            this._ichaMouseClick = nil
            local actionId = pagedId(this.buttonId)
            -- Drop onto this slot: place, do not use/drink/cast.
            if cursorHasAction() then
                PlaceAction(actionId)
                return
            end
            -- Mouse Shift-click / quick-move: pick up, do not use.
            -- Keybinds must fall through to UseAction even if Shift is held.
            if fromMouse and isQuickMove() then
                if HasAction and HasAction(actionId) then
                    PickupAction(actionId)
                end
                return
            end
            if not (HasAction and HasAction(actionId)) then return end
            local onSelf = 0
            if arg1 == "RightButton" and BActionSets_RightClickSelfCasts and BActionSets_RightClickSelfCasts() then
                onSelf = 1
            end
            -- One UseAction per click (Down+Up registration used to double-fire and
            -- toggle weapons right back off).
            UseAction(actionId, 1, onSelf)
        end)
        b:SetScript("OnDragStart", function()
            if moving then return end
            if IchaUI_EditModeActive and IchaUI_EditModeActive() then return end
            -- Only pick up with Shift or Bongos quick-move key (never plain drag)
            if not isQuickMove() then return end
            PickupAction(pagedId(this.buttonId))
            this._ichaSkipUse = true
        end)
        b:SetScript("OnReceiveDrag", function()
            PlaceAction(pagedId(this.buttonId))
            this._ichaSkipUse = true
        end)
        b:SetScript("OnMouseDown", function()
            if cursorHasAction() then
                PlaceAction(pagedId(this.buttonId))
                this._ichaSkipUse = true
                this._ichaMouseClick = nil
                return
            end
            -- Fresh press with an empty cursor is a real click, not a leftover drop.
            this._ichaSkipUse = nil
            this._ichaMouseClick = true
            if bindMode then return end
            pushButton(this.buttonId)
        end)
        b:SetScript("OnMouseUp", function()
            releaseButton(this.buttonId)
        end)
        b:SetScript("OnEnter", function()
            -- Disarm any previously hovered bind target
            if hoveredBtn and hoveredBtn ~= this then
                hoveredBtn:EnableKeyboard(false)
                hoveredBtn:SetScript("OnKeyDown", nil)
                setHoverGlow(hoveredBtn, false)
                if bindMode and hoveredBtn.border then
                    IchaUI_PaintGoldBorder(hoveredBtn.border, 1)
                end
            end
            hoveredBtn = this
            setHoverGlow(this, true)
            if bindMode then
                this:EnableKeyboard(true)
                this:SetScript("OnKeyDown", buttonOnKeyDown)
                if this.border then
                    this.border:SetBackdropBorderColor(0.3, 1, 0.4, 1)
                end
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetText("Bind slot " .. tostring(this.buttonId))
                GameTooltip:AddLine("Press a key  |  Right-click clears  |  ESC exits", 0.8, 0.8, 0.8)
                GameTooltip:Show()
                return
            end
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetAction(pagedId(this.buttonId))
        end)
        b:SetScript("OnLeave", function()
            this._ichaMouseClick = nil
            if hoveredBtn == this then
                hoveredBtn = nil
            end
            setHoverGlow(this, false)
            releaseButton(this.buttonId)
            this:EnableKeyboard(false)
            this:SetScript("OnKeyDown", nil)
            if this.border then
                IchaUI_PaintGoldBorder(this.border, 1)
            end
            GameTooltip:Hide()
        end)
    end
    b.buttonId = buttonId
    buttons[buttonId] = b
    return b
end

local function releaseAllExcept(valid)
    for id, b in pairs(buttons) do
        if not valid[id] then
            b:Hide()
            b:SetParent(root)
            buttons[id] = nil
            table.insert(pool, b)
        end
    end
end

local function filledIds(barId)
    local start = barStart(barId)
    local size = barSize(barId)
    local ids = {}
    for n = 0, size - 1 do
        local buttonId = start + n
        local actionId = pagedId(buttonId)
        if HasAction and HasAction(actionId) then
            table.insert(ids, buttonId)
        end
    end
    return ids
end

local actionHosts = {}
local heroHosts = {}

local function ensureHost(kind, index)
    local t = heroHosts
    local name = "IchaUIHeroHost" .. index
    if kind ~= "hero" then
        t = actionHosts
        name = "IchaUIActionHost" .. index
    end
    local f = t[index]
    if f then return f end
    f = CreateFrame("Frame", name, root)
    f:SetMovable(true)
    f:EnableMouse(false)
    f:SetWidth(4)
    f:SetHeight(4)
    t[index] = f
    return f
end

local function paintButton(b, w, h)
    b:SetWidth(w)
    b:SetHeight(h)
    b._cw = w
    b._ch = h
    sizeCooldown(b)
    if not b._formShape then
        applyAspect(b.icon, w, h)
        applyBorder(b)
    elseif IchaUI_FormIsRound and IchaUI_FormIsRound(b._formShape) then
        if b.border then b.border:Hide() end
    end
    updateHotkey(b)
    if b.roundMask and not b._formShape then
        b.roundMask:ClearAllPoints()
        b.roundMask:SetPoint("TOPLEFT", b.icon, "TOPLEFT", 0, 0)
        b.roundMask:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 0, 0)
        b.roundMask:Show()
    end
    sizeEquipGlow(b)
    b:Show()
end

-- Buttons sit inside the bar frame from its bottom-left. The frame's
-- position (attached, free, or snapped) is applied by IchaUI_SeatBarHost.
local function placeRow(ids, parent, w, h, gap)
    local count = table.getn(ids)
    if count < 1 then
        parent:SetWidth(w)
        parent:SetHeight(h)
        return w, h, false
    end
    local step = w + gap
    local rowW = count * step - gap
    parent:SetWidth(rowW)
    parent:SetHeight(h)
    local i
    for i = 1, count do
        local b = acquire(ids[i])
        b:SetParent(parent)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", (i - 1) * step, 0)
        paintButton(b, w, h)
    end
    parent:Show()
    return rowW, h, true
end

local function placeGrid(ids, parent, cols, w, h, gap)
    local count = table.getn(ids)
    if cols < 1 then cols = 1 end
    if count < 1 then
        parent:SetWidth(w)
        parent:SetHeight(h)
        return w, h, false
    end
    local stepX = w + gap
    local stepY = h + gap
    local rows = math.floor((count + cols - 1) / cols)
    local gridW = cols * stepX - gap
    local gridH = rows * stepY - gap
    if gridW < w then gridW = w end
    if gridH < h then gridH = h end
    parent:SetWidth(gridW)
    parent:SetHeight(gridH)
    local i
    for i = 1, count do
        local idx = i - 1
        local col = math.mod(idx, cols)
        local row = math.floor(idx / cols)
        local b = acquire(ids[i])
        b:SetParent(parent)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", col * stepX, row * stepY)
        paintButton(b, w, h)
    end
    parent:Show()
    return gridW, gridH, true
end

local function paintForm(ids, shape)
    if not IchaUI_ApplyButtonForm then return end
    local i
    for i = 1, table.getn(ids) do
        local b = buttons[ids[i]]
        if b then IchaUI_ApplyButtonForm(b, shape) end
    end
end

local function placeRadial(ids, parent, w, h, gap, spread, arc, rot)
    local count = table.getn(ids)
    if count < 1 then
        parent:SetWidth(w)
        parent:SetHeight(h)
        return w, h, false
    end
    local side = w
    if h > side then side = h end
    local radius = side
    if IchaUI_DrawerRadialRadius then
        radius = IchaUI_DrawerRadialRadius(count, side, side, gap, spread)
    end
    local span = radius * 2 + side
    parent:SetWidth(span)
    parent:SetHeight(span)
    local i
    for i = 1, count do
        local b = acquire(ids[i])
        b:SetParent(parent)
        b:ClearAllPoints()
        local x, y = 0, 0
        if IchaUI_DrawerRadialXY then
            x, y = IchaUI_DrawerRadialXY(i, count, radius, arc, rot)
        end
        b:SetPoint("CENTER", parent, "CENTER", x, y)
        paintButton(b, w, h)
    end
    parent:Show()
    return span, span, true
end

local function placeBar(kind, index, ids, parent, cols, w, h, gap)
    local shape, layout, spread, arc, rot = "rect", "grid", 90, 360, 90
    if kind == "hero" and IchaUI_HeroBarForm then
        shape, layout, spread, arc, rot = IchaUI_HeroBarForm(index)
    elseif IchaUI_ActionBarForm then
        shape, layout, spread, arc, rot = IchaUI_ActionBarForm(index)
    end
    if IchaUI_FormIsSquare and IchaUI_FormIsSquare(shape) then
        local side = w
        if h > side then side = h end
        w, h = side, side
    elseif shape == "rect" then
        local side = h
        if w < h then side = w end
        w = math.floor(side * 4 / 3 + 0.5)
        h = side
    end
    local gw, gh, filled
    if layout == "radial" then
        gw, gh, filled = placeRadial(ids, parent, w, h, gap, spread, arc, rot)
    else
        gw, gh, filled = placeGrid(ids, parent, cols, w, h, gap)
    end
    paintForm(ids, shape)
    return gw, gh, filled
end

local function seatHost(kind, index, host, relX, relY, w, h, btnW, btnH, filled)
    if not filled then
        if IchaUI_EditModeActive and IchaUI_EditModeActive() then
            host:Show()
        else
            host:Hide()
        end
    end
    if IchaUI_SeatBarHost then
        IchaUI_SeatBarHost(kind, index, host, relX, relY, w, h, btnW, btnH)
    else
        host:SetParent(root)
        host:ClearAllPoints()
        host:SetWidth(w)
        host:SetHeight(h)
        host:SetPoint("BOTTOMLEFT", root, "BOTTOM", relX, relY)
    end
end

local function allIds(barId)
    local start = barStart(barId)
    local size = barSize(barId)
    local ids = {}
    for n = 0, size - 1 do
        table.insert(ids, start + n)
    end
    return ids
end


local function layout(showEmpty)
    local cellW = iconW() + iconGap
    local cellH = iconH() + iconGap
    local leftCounts, rightCounts = {}, {}
    local leftMax, rightMax = 0, 0

    for barId = 1, 3 do
        if showEmpty then
            leftCounts[barId] = allIds(barId)
        else
            leftCounts[barId] = filledIds(barId)
        end
        local c = table.getn(leftCounts[barId])
        if c > leftMax then leftMax = c end
    end
    for barId = 4, 6 do
        if showEmpty then
            rightCounts[barId] = allIds(barId)
        else
            rightCounts[barId] = filledIds(barId)
        end
        local c = table.getn(rightCounts[barId])
        if c > rightMax then rightMax = c end
    end
    if leftMax < 1 then leftMax = 1 end
    if rightMax < 1 then rightMax = 1 end

    -- Hero bar: columns 1-12, rows 1-5. Slots are action ids from bar 7 upward.
    local side7 = math.floor(math.max(iconW(), iconH()) * heroScale + 0.5)
    local w7, h7 = side7, side7
    local heroCols = 4
    local b7 = {}
    if IchaUI_HeroButtonIds then
        local ids, cols = IchaUI_HeroButtonIds()
        if ids then b7 = ids end
        if cols and cols >= 1 then heroCols = cols end
    else
        local heroSrc = allIds(7)
        local hi
        local cap = 8
        for hi = 1, cap do
            if heroSrc[hi] then
                table.insert(b7, heroSrc[hi])
            end
        end
    end
    local shownN = table.getn(b7)
    if shownN < 1 then shownN = 1 end
    local heroRows = math.floor((shownN + heroCols - 1) / heroCols)
    if heroRows < 1 then heroRows = 1 end
    local heroGap = iconGap
    if IchaUI_HeroBarLook then
        local _, _, _, _, _, _, _, hg = IchaUI_HeroBarLook(1)
        if hg then heroGap = hg end
    end
    local heroW = heroCols * (w7 + heroGap) - heroGap
    local heroH = heroRows * (h7 + heroGap) - heroGap
    if heroW < w7 then heroW = w7 end
    if heroH < h7 then heroH = h7 end

    local leftW = leftMax * cellW - iconGap
    local rightW = rightMax * cellW - iconGap
    local midGap = iconGap * 2
    -- Hero grid is centered on the cluster. Wider columns move its edges
    -- out, and the side bars are glued to those edges so they shift with it.
    local heroCenterX = 0
    local leftRightEdge = -heroW / 2 - midGap
    local rightOriginX = heroW / 2 + midGap
    local totalW = leftW + midGap + heroW + midGap + rightW

    local valid = {}
    local function mark(ids)
        for i = 1, table.getn(ids) do valid[ids[i]] = true end
    end

    IchaUI_LayoutGap = iconGap
    IchaUI_LayoutMidGap = midGap

    -- Side stacks (3 high), bottom-aligned with hero grid.
    -- Each bar is its own frame. Attached bars stay on the cluster;
    -- detached bars are seated by the shared position model.
    local bw, bh = iconW(), iconH()
    local function stackSide(order, edgeX, growLeft)
        local y = 0
        local maxW = 0
        local ri
        for ri = 1, 3 do
            local barId = order[ri]
            local ids, cols = barGridIds(barId, showEmpty)
            mark(ids)
            local nIds = table.getn(ids)
            if not showEmpty and nIds > 0 and nIds < cols then cols = nIds end
            if cols < 1 then cols = 1 end
            local bsc = 1
            local _, _, _, _, _, specScale, _, _, barGap = barGridSpec(barId)
            if specScale and specScale > 0 then bsc = specScale end
            if not barGap then barGap = iconGap end
            local bw2 = math.floor(bw * bsc + 0.5)
            local bh2 = math.floor(bh * bsc + 0.5)
            if bw2 < 8 then bw2 = 8 end
            if bh2 < 8 then bh2 = 8 end
            local host = ensureHost("action", barId)
            local gw, gh, filled = placeBar("action", barId, ids, host, cols, bw2, bh2, barGap)
            if gw > maxW then maxW = gw end
            local relX = edgeX
            if growLeft then relX = edgeX - gw end
            seatHost("action", barId, host, relX, y, gw, gh, bw2, bh2, filled)
            if gh < bh2 then gh = bh2 end
            y = y + gh + iconGap
        end
        if y > iconGap then y = y - iconGap end
        return maxW, y
    end
    local leftW2, leftH = stackSide({1, 2, 3}, leftRightEdge, true)
    local rightW2, rightH = stackSide({4, 5, 6}, rightOriginX, false)
    if leftW2 > 0 then leftW = leftW2 end
    if rightW2 > 0 then rightW = rightW2 end
    totalW = leftW + midGap + heroW + midGap + rightW
    local sideH = leftH
    if rightH > sideH then sideH = rightH end

    mark(b7)
    local heroHost = ensureHost("hero", 1)
    local hw, hh, heroFilled = placeBar("hero", 1, b7, heroHost, heroCols, w7, h7, heroGap)
    if hw < heroW then hw = heroW end
    if hh < heroH then hh = heroH end
    seatHost("hero", 1, heroHost, -hw / 2, 0, hw, hh, w7, h7, heroFilled)

    local heroCount = 1
    if IchaUI_HeroBarCount then heroCount = IchaUI_HeroBarCount() end
    local ei
    for ei = 2, heroCount do
        local ids, cols = {}, 4
        if IchaUI_HeroBarButtonIds then
            ids, cols = IchaUI_HeroBarButtonIds(ei)
        end
        if not ids then ids = {} end
        if not cols or cols < 1 then cols = 4 end
        local sc = 1.55
        local hgap = iconGap
        if IchaUI_HeroBarScale then sc = IchaUI_HeroBarScale(ei) or sc end
        if IchaUI_HeroBarLook then
            local _, _, _, _, _, _, _, hg = IchaUI_HeroBarLook(ei)
            if hg then hgap = hg end
        end
        local side = math.floor(math.max(bw, bh) * sc + 0.5)
        mark(ids)
        local host = ensureHost("hero", ei)
        local ew, eh, efilled = placeBar("hero", ei, ids, host, cols, side, side, hgap)
        seatHost("hero", ei, host, 0, 0, ew, eh, side, side, efilled)
    end
    for ei = heroCount + 1, 5 do
        if heroHosts[ei] then heroHosts[ei]:Hide() end
    end

    local axCount = IchaUI_ActionBarCount()
    local ax
    for ax = 7, axCount do
        local ids, cols = barGridIds(ax, showEmpty)
        mark(ids)
        local nIds = table.getn(ids)
        if not showEmpty and nIds > 0 and nIds < cols then cols = nIds end
        if cols < 1 then cols = 1 end
        local bsc = 1
        local _, _, _, _, _, specScale, _, _, barGap = barGridSpec(ax)
        if specScale and specScale > 0 then bsc = specScale end
        if not barGap then barGap = iconGap end
        local bw2 = math.floor(bw * bsc + 0.5)
        local bh2 = math.floor(bh * bsc + 0.5)
        if bw2 < 8 then bw2 = 8 end
        if bh2 < 8 then bh2 = 8 end
        local host = ensureHost("action", ax)
        local gw, gh, filled = placeBar("action", ax, ids, host, cols, bw2, bh2, barGap)
        seatHost("action", ax, host, 0, 0, gw, gh, bw2, bh2, filled)
    end
    local hk, hf
    for hk, hf in pairs(actionHosts) do
        if hk > axCount and hf then hf:Hide() end
    end

    releaseAllExcept(valid)
    local o = borderOutset()
    local pad = o + 4
    local stackH = 2 * cellH + iconH()
    if sideH and sideH > stackH then stackH = sideH end
    local totalH = stackH
    if heroH > totalH then totalH = heroH end
    setRootSize(math.max(totalW, 1) + pad * 2, totalH + pad * 2)
    if moving and mover then
        mover:ClearAllPoints()
        mover:SetAllPoints(root)
    end
    IchaUI_ApplyLayoutIconStrata()
    if IchaUI_ReapplyBarPlaces then IchaUI_ReapplyBarPlaces() end
end

local function setIcon(b, path)
    if IchaUI_SetButtonIcon then
        IchaUI_SetButtonIcon(b, path)
    else
        b.icon:SetTexture(path)
    end
end

local function updateVisuals()
    for buttonId, b in pairs(buttons) do
        local actionId = pagedId(buttonId)
        if HasAction and HasAction(actionId) then
            local tex = GetActionTexture and GetActionTexture(actionId)
            if tex then setIcon(b, tex) end
            b.icon:Show()
            b.icon:SetAlpha(1)
            if b._formShape then
                if IchaUI_ApplyButtonForm then IchaUI_ApplyButtonForm(b, b._formShape) end
            else
                applyAspect(b.icon, b:GetWidth(), b:GetHeight())
            end
            sizeCooldown(b)
            updateHotkey(b)
            local start, duration, enable = GetActionCooldown(actionId)
            if b.cooldown then
                sizeCooldown(b)
                local st = start or 0
                local dur = duration or 0
                local en = enable
                if en == nil then en = 1 end
                -- Call original blender directly so our Bongos suppress hook still applies to Bongos only
                if IchaUI_SetButtonSweep and IchaUI_SetButtonSweep(b, st, dur, en) then
                    b.cooldown:Hide()
                elseif _CooldownFrame_SetTimer then
                    _CooldownFrame_SetTimer(b.cooldown, st, dur, en)
                elseif CooldownFrame_SetTimer then
                    CooldownFrame_SetTimer(b.cooldown, st, dur, en)
                end
                if dur and dur > 0 and en ~= 0 and not b._sweepOn then
                    b.cooldown:Show()
                end
            end
            -- Stock ActionButton_UpdateCount: consumable or stackable only (show even at 1).
            local showCount = nil
            if (type(IsConsumableAction) == "function" and IsConsumableAction(actionId))
                or (type(IsStackableAction) == "function" and IsStackableAction(actionId)) then
                showCount = 0
                if type(GetActionCount) == "function" then
                    showCount = tonumber(GetActionCount(actionId)) or 0
                end
            end
            if showCount == nil then
                b.count:SetText("")
                b.count:Hide()
            else
                local n = tonumber(showCount) or 0
                b.count:SetText(tostring(n))
                if n <= 0 then
                    b.count:SetTextColor(1, 0.15, 0.15)
                else
                    b.count:SetTextColor(1, 1, 1)
                end
                b.count:Show()
            end
            if applyIconUsable then
                applyIconUsable(b, b._pushed and true or false)
            end
            updateEquipGlow(b, actionId)
            b:SetAlpha(1)
        else
            -- Empty drop target: faint slot while placing, invisible otherwise
            if b._formShape then
                if IchaUI_ApplyButtonForm then IchaUI_ApplyButtonForm(b, b._formShape) end
            else
                applyAspect(b.icon, b:GetWidth(), b:GetHeight())
            end
            if IchaUI_EditModeActive and IchaUI_EditModeActive() then
                setIcon(b, "Interface/Buttons/UI-Quickslot2")
                b.icon:Show()
                b.icon:SetVertexColor(1, 1, 1)
                b.icon:SetAlpha(1)
                b:SetAlpha(1)
                if b.border and not (IchaUI_FormIsRound and IchaUI_FormIsRound(b._formShape))
                    and not (IchaUI_FormShapeDef and IchaUI_FormShapeDef(b._formShape)) then
                    applyBorder(b)
                    b.border:Show()
                end
            elseif bindMode or cursorHasAction() then
                setIcon(b, "Interface/Buttons/UI-Quickslot2")
                b.icon:Show()
                if bindMode then
                    b.icon:SetVertexColor(0.35, 0.9, 0.45)
                else
                    b.icon:SetVertexColor(0.5, 0.7, 1)
                end
                b.icon:SetAlpha(0.55)
                b:SetAlpha(1)
            else
                b.icon:Hide()
                b:SetAlpha(0.01)
            end
            b.count:SetText("")
            b.count:Hide()
            updateHotkey(b)
            if b.equipGlow then b.equipGlow:Hide() end
            if CooldownFrame_SetTimer and b.cooldown then
                CooldownFrame_SetTimer(b.cooldown, 0, 0, 0)
            end
            if IchaUI_SetButtonSweep then IchaUI_SetButtonSweep(b, 0, 0, 0) end
        end
        if IchaUI_PlaceFormMask then IchaUI_PlaceFormMask(b) end
    end
end

local bongosHidden = true



-- Always suppress Bongos action-button cooldown Models (they draw even when bars are menu-hidden)
local _CooldownFrame_SetTimer = CooldownFrame_SetTimer
function CooldownFrame_SetTimer(frame, start, duration, enable)
    if frame then
        local n = frame.GetName and frame:GetName()
        if n and string.find(n, "^BActionButton%d+Cooldown") then
            frame:Hide()
            return
        end
        if frame._ichaSweepOwner and frame._ichaSweepOwner._sweepOn then
            frame:Hide()
            return
        end
    end
    if _CooldownFrame_SetTimer then
        _CooldownFrame_SetTimer(frame, start, duration, enable)
    end
end

local function nukeBongosCooldowns()
    -- Bongos Models keep drawing even when buttons are "hidden" via the Bongos menu
    for i = 1, 120 do
        local cd = getglobal("BActionButton" .. i .. "Cooldown")
        if cd then
            cd:Hide()
            cd:ClearAllPoints()
            cd:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -5000, 5000)
            cd:SetAlpha(0)
        end
        local btn = getglobal("BActionButton" .. i)
        if btn and bongosHidden then
            btn:Hide()
            btn:EnableMouse(false)
        end
    end
    for i = 1, 7 do
        local bar = getglobal("BActionBar" .. i)
        if bar and bongosHidden then
            bar:Hide()
        end
    end
end

local function hideBongos()
    bongosHidden = true
    for i = 1, 7 do
        local bar = getglobal("BActionBar" .. i)
        if bar then
            bar:Hide()
            bar:SetAlpha(0)
            if bar.EnableMouse then bar:EnableMouse(false) end
            -- Stop Bongos from popping the bar back up
            if not bar._ichaHooked then
                bar._ichaHooked = true
                bar:SetScript("OnShow", function()
                    if bongosHidden then this:Hide() end
                end)
            end
        end
        local start = barStart(i)
        local size = barSize(i)
        for n = 0, size - 1 do
            local btn = getglobal("BActionButton" .. (start + n))
            if btn then
                -- Alpha 0 still draws cooldown Models — must Hide()
                btn:Hide()
                btn:SetAlpha(0)
                btn:EnableMouse(false)
                local cd = getglobal(btn:GetName() and (btn:GetName() .. "Cooldown") or "")
                if cd then cd:Hide() end
                if not btn._ichaHooked then
                    btn._ichaHooked = true
                    btn:SetScript("OnShow", function()
                        if bongosHidden then
                            this:Hide()
                            local c = getglobal(this:GetName() .. "Cooldown")
                            if c then c:Hide() end
                        end
                    end)
                end
            end
        end
    end
    nukeBongosCooldowns()
end


-- Hide stock Blizzard action bars / bags / micro menu (IchaUI replaces them; Bongos optional)
local blizzardHidden = true
local BLIZZARD_HIDE = {
    "MainMenuBar",
    "MainMenuBarArtFrame",
    "MainMenuExpBar",
    "MainMenuBarMaxLevelBar",
    "ExhaustionTick",
    "ReputationWatchBar",
    "MainMenuBarPerformanceBarFrame",
    "MultiBarBottomLeft",
    "MultiBarBottomRight",
    "MultiBarRight",
    "MultiBarLeft",
    "MultiCastActionBarFrame",
    "PossessBarFrame",
    "BonusActionBarFrame",
    "ShapeshiftBarFrame",
    "PetActionBarFrame",
    "MainMenuBarVehicleLeaveButton",
    "CharacterMicroButton",
    "SpellbookMicroButton",
    "TalentMicroButton",
    "QuestLogMicroButton",
    "SocialsMicroButton",
    "WorldMapMicroButton",
    "MainMenuMicroButton",
    "HelpMicroButton",
    "MainMenuBarBackpackButton",
    "CharacterBag0Slot",
    "CharacterBag1Slot",
    "CharacterBag2Slot",
    "CharacterBag3Slot",
    "KeyRingButton",
    "MainMenuBarPageNumber",
    "ActionBarUpButton",
    "ActionBarDownButton",
    "VerticalMultiBarsContainer",
}

local function hideOneBlizzard(name)
    local f = getglobal(name)
    if not f then return end
    if f.Hide then f:Hide() end
    if f.SetAlpha then f:SetAlpha(0) end
    if f.EnableMouse then f:EnableMouse(false) end
    if not f._ichaBlizzHook then
        f._ichaBlizzHook = true
        if f.SetScript and f.HasScript and f:HasScript("OnShow") then
            local prev = f:GetScript("OnShow")
            f:SetScript("OnShow", function()
                if blizzardHidden then
                    this:Hide()
                    if this.SetAlpha then this:SetAlpha(0) end
                elseif prev then
                    prev()
                end
            end)
        elseif f.SetScript then
            f:SetScript("OnShow", function()
                if blizzardHidden then
                    this:Hide()
                    if this.SetAlpha then this:SetAlpha(0) end
                end
            end)
        end
    end
end

local function hideBlizzardUI()
    blizzardHidden = true
    local i
    for i = 1, table.getn(BLIZZARD_HIDE) do
        hideOneBlizzard(BLIZZARD_HIDE[i])
    end
    -- Numbered action buttons on main bar
    for i = 1, 12 do
        hideOneBlizzard("ActionButton" .. i)
        hideOneBlizzard("BonusActionButton" .. i)
        hideOneBlizzard("MultiBarBottomLeftButton" .. i)
        hideOneBlizzard("MultiBarBottomRightButton" .. i)
        hideOneBlizzard("MultiBarRightButton" .. i)
        hideOneBlizzard("MultiBarLeftButton" .. i)
        hideOneBlizzard("ShapeshiftButton" .. i)
        hideOneBlizzard("PetActionButton" .. i)
    end
end

local function showBlizzardUI()
    blizzardHidden = false
    local i
    for i = 1, table.getn(BLIZZARD_HIDE) do
        local f = getglobal(BLIZZARD_HIDE[i])
        if f and f.Show then
            f:Show()
            if f.SetAlpha then f:SetAlpha(1) end
            if f.EnableMouse then f:EnableMouse(true) end
        end
    end
end

local function showBongos()
    bongosHidden = false
    for i = 1, 7 do
        local bar = getglobal("BActionBar" .. i)
        if bar then
            bar:Show()
            bar:SetAlpha(1)
            if bar.EnableMouse then bar:EnableMouse(true) end
        end
        local start = barStart(i)
        local size = barSize(i)
        for n = 0, size - 1 do
            local btn = getglobal("BActionButton" .. (start + n))
            if btn then
                btn:Show()
                btn:SetAlpha(1)
                btn:EnableMouse(true)
            end
        end
    end
end

local function wipeOldWA()
    if not WeakestAurasDB or not WeakestAurasDB.displays then return end
    local removed = 0
    -- Prefer tree delete for the group
    if WeakestAurasDB.displays["Bongos Replace"] then
        if WA and WA.DeleteAuraTree then
            WA.DeleteAuraTree("Bongos Replace")
            removed = removed + 1
        elseif WA and WA.DeleteAura then
            WA.DeleteAura("Bongos Replace")
            removed = removed + 1
        else
            WeakestAurasDB.displays["Bongos Replace"] = nil
            removed = removed + 1
        end
    end
    -- Orphan BR Slot* leftovers
    local toRemove = {}
    for id, _ in pairs(WeakestAurasDB.displays) do
        if type(id) == "string" and string.find(id, "^BR Slot ") then
            table.insert(toRemove, id)
        end
    end
    for i = 1, table.getn(toRemove) do
        local id = toRemove[i]
        if WA and WA.DeleteAura then
            WA.DeleteAura(id)
        else
            WeakestAurasDB.displays[id] = nil
        end
        removed = removed + 1
        local r = getglobal("WeakestAuras:" .. id)
        if r then
            if r.Hide then r:Hide() end
            if r.EnableMouse then r:EnableMouse(false) end
        end
    end
    -- Nuke leftover click overlays from v1 if any
    for i = 1, 200 do
        local c = getglobal("IchaUIClick" .. i)
        if c then
            c:Hide()
            c:EnableMouse(false)
            c:SetParent(nil)
        end
    end
    if removed > 0 and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("IchaUI Layout: removed " .. removed .. " old WeakestAuras icons.")
    end
end

local showEmptySlots = false

local function layoutSignature()
    local parts = { showEmptySlots and "1" or "0", tostring(iconScale), tostring(iconGap), tostring(heroScale), tostring(borderEdgeSize()), tostring(borderOutset()) }
    local hc, hr = 4, 2
    if IchaUI_HeroPrimaryGrid then
        hc, hr = IchaUI_HeroPrimaryGrid()
    elseif IchaUI_HeroGrid then
        hc, hr = IchaUI_HeroGrid()
    end
    table.insert(parts, tostring(hc))
    table.insert(parts, tostring(hr))
    if IchaUI_HeroBarCount then
        table.insert(parts, "hb" .. tostring(IchaUI_HeroBarCount()))
        local hi
        for hi = 2, IchaUI_HeroBarCount() do
            local sc = IchaUI_HeroBarScale and IchaUI_HeroBarScale(hi) or 0
            table.insert(parts, tostring(sc))
            if IchaUI_HeroBarButtonIds then
                local ids, cols = IchaUI_HeroBarButtonIds(hi)
                table.insert(parts, tostring(cols or 0))
                table.insert(parts, tostring(ids and table.getn(ids) or 0))
            end
        end
    end
    for barId = 1, IchaUI_ActionBarCount() do
        table.insert(parts, tostring(barSize(barId)))
        local ids = barGridIds(barId, showEmptySlots)
        for i = 1, table.getn(ids) do
            table.insert(parts, tostring(ids[i]))
        end
        table.insert(parts, ";")
    end
    return table.concat(parts, ",")
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
f:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
f:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
f:RegisterEvent("ACTIONBAR_UPDATE_STATE")
f:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
f:RegisterEvent("ACTIONBAR_SHOWGRID")
f:RegisterEvent("ACTIONBAR_HIDEGRID")
f:RegisterEvent("UPDATE_BINDINGS")
f:RegisterEvent("UNIT_INVENTORY_CHANGED")
f:RegisterEvent("UPDATE_INVENTORY_ALERTS")
f:RegisterEvent("BAG_UPDATE")

local lastSig, pendingLayout, layoutElapsed = nil, true, 0

function IchaUI_RefreshActionBar(index)
    index = tonumber(index) or 1
    local host = actionHosts[index]
    if not host then
        pendingLayout = true
        lastSig = nil
        return
    end
    local ids, cols = barGridIds(index, showEmptySlots)
    local nIds = table.getn(ids)
    if not showEmptySlots and nIds > 0 and nIds < cols then cols = nIds end
    if cols < 1 then cols = 1 end
    local bsc = 1
    local _, _, _, _, _, specScale, _, _, barGap = barGridSpec(index)
    if specScale and specScale > 0 then bsc = specScale end
    if not barGap then barGap = iconGap end
    local bw2 = math.floor(iconW() * bsc + 0.5)
    local bh2 = math.floor(iconH() * bsc + 0.5)
    if bw2 < 8 then bw2 = 8 end
    if bh2 < 8 then bh2 = 8 end
    placeBar("action", index, ids, host, cols, bw2, bh2, barGap)
    if IchaUI_HoldBarCenter then IchaUI_HoldBarCenter("action", index, host) end
end

function IchaUI_RefreshHeroBar(index)
    index = tonumber(index) or 1
    local host = heroHosts[index]
    if not host then
        pendingLayout = true
        lastSig = nil
        return
    end
    local ids, cols = {}, 4
    if index <= 1 and IchaUI_HeroButtonIds then
        local got, c = IchaUI_HeroButtonIds()
        if got then ids = got end
        if c and c >= 1 then cols = c end
    elseif IchaUI_HeroBarButtonIds then
        local got, c = IchaUI_HeroBarButtonIds(index)
        if got then ids = got end
        if c and c >= 1 then cols = c end
    end
    local sc = heroScale
    if index > 1 and IchaUI_HeroBarScale then sc = IchaUI_HeroBarScale(index) or sc end
    local hgap = iconGap
    if IchaUI_HeroBarLook then
        local _, _, _, _, _, _, _, hg = IchaUI_HeroBarLook(index)
        if hg then hgap = hg end
    end
    local side = math.floor(math.max(iconW(), iconH()) * sc + 0.5)
    if side < 8 then side = 8 end
    placeBar("hero", index, ids, host, cols, side, side, hgap)
    if IchaUI_HoldBarCenter then IchaUI_HoldBarCenter("hero", index, host) end
end

function IchaUI_RequestLayout()
    pendingLayout = true
    lastSig = nil
end
local visElapsed = 0

local function loadDB()
    if not IchaUIDB then
        if type(WABongosLayoutDB) == "table" then
            IchaUIDB = WABongosLayoutDB
        else
            IchaUIDB = {}
        end
    end
    if IchaUIDB.scale then
        iconScale = tonumber(IchaUIDB.scale) or 1.0
        if iconScale < 0.4 then iconScale = 0.4 end
        if iconScale > 2.0 then iconScale = 2.0 end
    end
    if IchaUIDB.gap then
        iconGap = tonumber(IchaUIDB.gap) or 2.0
        if iconGap < 0 then iconGap = 0 end
        if iconGap > 20 then iconGap = 20 end
    end
    if IchaUIDB.showHotkeys ~= nil then
        showHotkeys = IchaUIDB.showHotkeys and true or false
    end
    if IchaUIDB.heroScale then
        heroScale = tonumber(IchaUIDB.heroScale) or BAR7_SCALE
        if heroScale < 0.5 then heroScale = 0.5 end
        if heroScale > 3.0 then heroScale = 3.0 end
    else
        heroScale = BAR7_SCALE
    end
    IchaUIDB.iconStrata = strataFromValue(IchaUIDB.iconStrata, 3)
end

local function saveDB()
    if not IchaUIDB then IchaUIDB = {} end
    IchaUIDB.scale = iconScale
    IchaUIDB.gap = iconGap
    IchaUIDB.showHotkeys = showHotkeys
    IchaUIDB.heroScale = heroScale
    local sname = "MEDIUM"
    if IchaUI_GetIconStrata then
        sname = IchaUI_GetIconStrata() or "MEDIUM"
    elseif IchaUIDB.iconStrata then
        sname = IchaUIDB.iconStrata
    end
    IchaUIDB.iconStrata = sname
end

local wiped = false

f:SetScript("OnEvent", function()
    local ev = event
    if ev == "ADDON_LOADED" then
        if arg1 == "IchaUI" then
            loadDB()
            restoreRootPos()
            IchaUI_ApplyIconStrata()
        end
        return
    end
    if (ev == "PLAYER_LOGIN" or ev == "PLAYER_ENTERING_WORLD") and not wiped then
        wiped = true
        loadDB()
        restoreRootPos()
        wipeOldWA()
        hookActionButtons()
        IchaUI_ApplyIconStrata()
        pendingLayout = true
        lastSig = nil
    end
    if ev == "UPDATE_BINDINGS" then
        for _, b in pairs(buttons) do updateHotkey(b) end
        return
    end
    if ev == "ACTIONBAR_SHOWGRID" then
        gridShown = true
        pendingLayout = true
        lastSig = nil
        return
    end
    if ev == "ACTIONBAR_HIDEGRID" then
        gridShown = false
        pendingLayout = true
        lastSig = nil
        return
    end
    if ev == "ACTIONBAR_UPDATE_COOLDOWN" or ev == "SPELL_UPDATE_COOLDOWN" or ev == "ACTIONBAR_UPDATE_STATE" then
        updateVisuals()
        return
    end
    if ev == "UNIT_INVENTORY_CHANGED" then
        if arg1 == "player" then
            updateVisuals()
        end
        return
    end
    if ev == "UPDATE_INVENTORY_ALERTS" then
        updateVisuals()
        return
    end
    if ev == "BAG_UPDATE" then
        if IchaUI_InvalidateBagItemCount then IchaUI_InvalidateBagItemCount() end
        updateVisuals()
        return
    end
    pendingLayout = true
    if ev == "ACTIONBAR_SLOT_CHANGED" then
        updateVisuals()
    end
end)

local function fadeOne(host, opacity, fade)
    if not host or not host.IsShown or not host:IsShown() then return end
    local target = fade or 1
    if MouseIsOver and MouseIsOver(host) then target = opacity or 1 end
    if not host._fadeA then host._fadeA = target end
    local a = host._fadeA
    if a < target then
        a = a + 0.12
        if a > target then a = target end
    elseif a > target then
        a = a - 0.12
        if a < target then a = target end
    end
    host._fadeA = a
    host:SetAlpha(a)
end

local function applyBarFade()
    local n = IchaUI_ActionBarCount()
    local i
    for i = 1, n do
        local _, _, _, _, _, _, opacity, fade = barGridSpec(i)
        fadeOne(actionHosts[i], opacity, fade)
    end
    local hn = 1
    if IchaUI_HeroBarCount then hn = IchaUI_HeroBarCount() or 1 end
    for i = 1, hn do
        local opacity, fade = 1, 1
        if IchaUI_HeroBarLook then
            local _, op, fd = IchaUI_HeroBarLook(i)
            opacity = op or 1
            fade = fd or opacity
        end
        fadeOne(heroHosts[i], opacity, fade)
    end
end

f:SetScript("OnUpdate", function()
    local dt = arg1 or 0
    applyBarFade()
    local editEmpty = IchaUI_EditModeActive and IchaUI_EditModeActive()
    local wantEmpty = bindMode or cursorHasAction() or (editEmpty and true or false)
    if wantEmpty ~= showEmptySlots then
        showEmptySlots = wantEmpty
        pendingLayout = true
        lastSig = nil
    end
    visElapsed = visElapsed + dt
    if visElapsed >= 0.1 then
        visElapsed = 0
        updateVisuals()
        if root:IsShown() then
            if bongosHidden then hideBongos() end
            if blizzardHidden then hideBlizzardUI() end
            nukeBongosCooldowns()
        end
    end
    if not pendingLayout then return end
    layoutElapsed = layoutElapsed + dt
    if layoutElapsed < 0.1 then return end
    layoutElapsed = 0
    pendingLayout = false
    local sig = layoutSignature()
    if sig ~= lastSig then
        lastSig = sig
        layout(showEmptySlots)
        hookActionButtons()
        if bongosHidden then hideBongos() end
        if blizzardHidden then hideBlizzardUI() end
    end
    updateVisuals()
end)


-- Hover-to-bind: /icha bind, then hover a button and press a key.

local function bindingCommand(buttonId)
    -- Named button click — works for every IchaUI slot (ACTIONBUTTON only exists for 1-12).
    return "CLICK IchaUIBtn" .. buttonId .. ":LeftButton"
end

local function clearKeyBinding(key)
    if not key or key == "" then return end
    SetBinding(key)
end

local function applyBind(buttonId, key)
    if not buttonId or not key or key == "" then return false end
    if key == "ESCAPE" then return false end
    local uk = string.upper(tostring(key))
    if uk == "LSHIFT" or uk == "RSHIFT" or uk == "SHIFT"
        or uk == "LCTRL" or uk == "RCTRL" or uk == "CTRL" or uk == "CONTROL"
        or uk == "LCONTROL" or uk == "RCONTROL"
        or uk == "LALT" or uk == "RALT" or uk == "ALT"
        or uk == "UNKNOWN" then
        return false
    end

    local full = key
    if IsShiftKeyDown() then full = "SHIFT-" .. full end
    if IsControlKeyDown() then full = "CTRL-" .. full end
    if IsAltKeyDown() then full = "ALT-" .. full end
    full = string.upper(full)

    local cmd = bindingCommand(buttonId)
    clearKeyBinding(full)
    local ok = SetBinding(full, cmd)
    if ok then
        local set = GetCurrentBindingSet and GetCurrentBindingSet() or 1
        SaveBindings(set)
        if DEFAULT_CHAT_FRAME then
            local shown = abbreviateKey(GetBindingText(full, "KEY_") or full)
            DEFAULT_CHAT_FRAME:AddMessage("Bound " .. shown .. " -> IchaUI slot " .. buttonId)
        end
        for _, b in pairs(buttons) do updateHotkey(b) end
        return true
    end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("Bind failed for " .. full)
    end
    return false
end

clearBind = function(buttonId)
    local cmds = {
        bindingCommand(buttonId),
        "ACTIONBUTTON" .. buttonId,
        "CLICK BActionButton" .. buttonId .. ":LeftButton",
    }
    local ci
    for ci = 1, table.getn(cmds) do
        local cmd = cmds[ci]
        local k1, k2 = GetBindingKey(cmd)
        if k1 then clearKeyBinding(k1) end
        if k2 then clearKeyBinding(k2) end
    end
    local set = GetCurrentBindingSet and GetCurrentBindingSet() or 1
    SaveBindings(set)
    for _, b in pairs(buttons) do updateHotkey(b) end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("Cleared binds on IchaUI slot " .. buttonId)
    end
end

function buttonOnKeyDown()
    if not bindMode then return end
    local key = arg1
    if key == "ESCAPE" then
        setBindMode(false)
        return
    end
    -- Only the hovered button is valid (never trust `this` — other buttons may still see the key)
    if not hoveredBtn or not hoveredBtn.buttonId then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("Hover a button, then press a key.")
        end
        return
    end
    applyBind(hoveredBtn.buttonId, key)
end

function setBindMode(on)
    bindMode = on and true or false
    hoveredBtn = nil
    showEmptySlots = bindMode or cursorHasAction()
    pendingLayout = true
    lastSig = nil
    -- Never arm every button — only the hovered one gets keyboard (avoids random binds)
    for _, b in pairs(buttons) do
        b:EnableKeyboard(false)
        b:SetScript("OnKeyDown", nil)
        if b.border then
            IchaUI_PaintGoldBorder(b.border, 1)
        end
    end
    if bindMode then
        DEFAULT_CHAT_FRAME:AddMessage("Bind mode ON — hover ONE button, then press a key. Right-click clears. ESC or /icha bind to exit.")
    else
        DEFAULT_CHAT_FRAME:AddMessage("Bind mode off.")
    end
end

function IchaUIBars_Slash(msg)
    msg = string.lower(string.gsub(msg or "", "^%s+", ""))
    if msg == "show" then
        showBongos()
        root:Hide()
        DEFAULT_CHAT_FRAME:AddMessage("Bongos shown; replacement hidden. (/icha hide to reverse)")
    elseif msg == "hide" then
        root:Show()
        hideBongos()
        pendingLayout = true
        lastSig = nil
        DEFAULT_CHAT_FRAME:AddMessage("Bongos hidden; replacement shown.")
    elseif msg == "hotkeys" or msg == "hotkey" or msg == "binds" then
        showHotkeys = not showHotkeys
        saveDB()
        for _, b in pairs(buttons) do updateHotkey(b) end
        DEFAULT_CHAT_FRAME:AddMessage(showHotkeys and "Keybind text shown." or "Keybind text hidden.")
    elseif msg == "bind" then
        setBindMode(not bindMode)
    elseif msg == "move" or msg == "edit" then
        if IchaUI_EditModeActive and IchaUI_EditModeActive() then
            if IchaUI_EditPositionsCancel then IchaUI_EditPositionsCancel() end
        elseif IchaUI_EditPositions then
            IchaUI_EditPositions()
        else
            setMoveMode(not moving)
            if moving then
                DEFAULT_CHAT_FRAME:AddMessage("Blue drag box on — drag it, then /icha move to lock.")
            else
                DEFAULT_CHAT_FRAME:AddMessage("Bar locked.")
            end
        end
    elseif msg == "wipe" then
        wiped = false
        wipeOldWA()
        wiped = true
        pendingLayout = true
        lastSig = nil
    elseif string.find(msg, "^scale") then
        local n = nil
        for token in (string.gmatch or string.gfind)(msg, "%S+") do
            n = tonumber(token) or n
        end
        if not n then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("Current scale: %.2f  (try /icha scale 0.85)", iconScale))
        else
            if n < 0.4 then n = 0.4 end
            if n > 2.0 then n = 2.0 end
            iconScale = n
            saveDB()
            pendingLayout = true
            lastSig = nil
            DEFAULT_CHAT_FRAME:AddMessage(string.format("Icon scale set to %.2f (%dx%d)", iconScale, iconW(), iconH()))
        end
    elseif string.find(msg, "^gap") or string.find(msg, "^pad") then
        local n = nil
        for token in (string.gmatch or string.gfind)(msg, "%S+") do
            n = tonumber(token) or n
        end
        if not n then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("Current gap: %.1f  (try /icha gap 2)", iconGap))
        else
            if n < 0 then n = 0 end
            if n > 20 then n = 20 end
            iconGap = n
            saveDB()
            pendingLayout = true
            lastSig = nil
            DEFAULT_CHAT_FRAME:AddMessage(string.format("Button gap set to %.1f", iconGap))
        end
    elseif string.find(msg, "^heroscale") or string.find(msg, "^hero ") or msg == "hero" then
        local n = nil
        for token in (string.gmatch or string.gfind)(msg, "%S+") do
            n = tonumber(token) or n
        end
        if not n then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("Hero scale: %.2f  (try /icha heroscale 1.55)", heroScale))
        else
            if n < 0.5 then n = 0.5 end
            if n > 3.0 then n = 3.0 end
            heroScale = n
            saveDB()
            pendingLayout = true
            lastSig = nil
            local side = math.floor(math.max(iconW(), iconH()) * heroScale + 0.5)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("Hero scale %.2f (%dx%d)", heroScale, side, side))
        end
    else
        pendingLayout = true
        lastSig = nil
        wipeOldWA()
        DEFAULT_CHAT_FRAME:AddMessage("IchaUI: /iui opens options. Also: hotkeys | bind | gap | scale | heroscale | move | show | hide | wipe | xp | uf | totems | buffs | chat")
    end
end


function IchaUI_HideBlizzard(on)
    if on == false then
        showBlizzardUI()
    else
        hideBlizzardUI()
    end
end

-- Always hide stock Blizzard chrome when IchaUI bars are active
hideBlizzardUI()

function IchaUI_ReloadLayoutFromDB()
    loadDB()
    restoreRootPos()
    if IchaUI_ApplyIconStrata then IchaUI_ApplyIconStrata() end
    pendingLayout = true
    lastSig = nil
    layoutElapsed = 0
    updateVisuals()
end
