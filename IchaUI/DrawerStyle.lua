-- Per-drawer strata, text size, rows/columns, closed-button scale, and popout scale.
-- Defaults stay unset so current drawers do not jump until a control is moved.
-- buttonScale sizes the closed drawer icon. popScale sizes the open tray icons.
-- Each id stores its own pair (default 1). A leftover global number is ignored.

local STRATA = {
    "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG",
    "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP",
}

local INFO = {
    totems = { label = "Totems", strata = "MEDIUM", text = 11, cols = 2, grid = true, textVia = "totems" },
    recall = { label = "Recall", strata = "MEDIUM", text = 11 },
    utility = { label = "Utility", strata = "MEDIUM", text = 11, cols = 1, grid = true, textVia = "extras" },
    imbue = { label = "Imbue", strata = "MEDIUM", text = 11, cols = 1, grid = true, textVia = "extras" },
    shield = { label = "Shield", strata = "MEDIUM", text = 11, cols = 1, grid = true, textVia = "extras" },
    minimap = { label = "Minimap", strata = "MEDIUM", text = 11 },
    resists = { label = "Resists", strata = "MEDIUM", text = 8 },
}

local ORDER = { "totems", "recall", "utility", "imbue", "shield", "minimap", "resists" }

local function info(id)
    return INFO[id]
end

local function bag()
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.drawerStyle then IchaUIDB.drawerStyle = {} end
    -- Old global multiplier. Drop it so one saved number cannot resize every drawer.
    if type(IchaUIDB.drawerStyle.buttonScale) ~= "table" then
        IchaUIDB.drawerStyle.buttonScale = nil
    end
    return IchaUIDB.drawerStyle
end

function IchaUI_DrawerStyleRow(id)
    if not id or not IchaUIDB or not IchaUIDB.drawerStyle then return nil end
    local row = IchaUIDB.drawerStyle[id]
    if type(row) ~= "table" then return nil end
    return row
end

function IchaUI_DrawerStyleGet(id)
    local row = IchaUI_DrawerStyleRow(id)
    if not row then return nil, nil end
    local strata, size
    if type(row.strata) == "string" and row.strata ~= "" then strata = row.strata end
    if tonumber(row.textSize) then size = tonumber(row.textSize) end
    return strata, size
end

function IchaUI_DrawerButtonScale(id)
    if IchaUIDB and IchaUIDB.drawerStyle and type(IchaUIDB.drawerStyle.buttonScale) ~= "table" then
        IchaUIDB.drawerStyle.buttonScale = nil
    end
    local n = 1
    local row = IchaUI_DrawerStyleRow(id)
    if row and tonumber(row.buttonScale) then n = tonumber(row.buttonScale) end
    if n < 0.5 then n = 0.5 end
    if n > 2 then n = 2 end
    return n
end

function IchaUI_DrawerButtonScaleSet(id, v)
    if not id or id == "" then return end
    local n = tonumber(v) or 1
    if n < 0.5 then n = 0.5 end
    if n > 2 then n = 2 end
    n = math.floor(n * 100 + 0.5) / 100
    local row = bag()[id]
    if type(row) ~= "table" then
        bag()[id] = {}
        row = bag()[id]
    end
    if row.buttonScale == n then return end
    row.buttonScale = n
    IchaUI_DrawerScaleApply(id)
end

function IchaUI_DrawerPopScale(id)
    if IchaUIDB and IchaUIDB.drawerStyle and type(IchaUIDB.drawerStyle.buttonScale) ~= "table" then
        IchaUIDB.drawerStyle.buttonScale = nil
    end
    local n = 1
    local row = IchaUI_DrawerStyleRow(id)
    if row and tonumber(row.popScale) then n = tonumber(row.popScale) end
    if n < 0.5 then n = 0.5 end
    if n > 2 then n = 2 end
    return n
end

function IchaUI_DrawerPopScaleSet(id, v)
    if not id or id == "" then return end
    local n = tonumber(v) or 1
    if n < 0.5 then n = 0.5 end
    if n > 2 then n = 2 end
    n = math.floor(n * 100 + 0.5) / 100
    local row = bag()[id]
    if type(row) ~= "table" then
        bag()[id] = {}
        row = bag()[id]
    end
    if row.popScale == n then return end
    row.popScale = n
    IchaUI_DrawerScaleApply(id)
end

function IchaUI_DrawerScaleApply(id)
    if id == "totems" and IchaUITotems_Get and IchaUITotems_Set then
        local t = IchaUITotems_Get()
        local sz = 22
        if t and tonumber(t.drawerSize) then sz = tonumber(t.drawerSize) end
        IchaUITotems_Set("drawerSize", sz)
    elseif (id == "utility" or id == "imbue" or id == "shield") and IchaUIShamanExtras_Apply then
        IchaUIShamanExtras_Apply()
    elseif id == "recall" and IchaUI_TotemRecallIcon_Scale and IchaUI_TotemRecallIcon_ScaleSet then
        IchaUI_TotemRecallIcon_ScaleSet(IchaUI_TotemRecallIcon_Scale())
    elseif id == "minimap" and IchaUIMinimap_SetDrawer then
        IchaUIMinimap_SetDrawer("buttonScale", true)
    elseif id == "resists" and IchaUIUF_layoutTargetCluster then
        IchaUIUF_layoutTargetCluster()
    end
    if IchaUI_CustomDrawers_ApplyStyle then IchaUI_CustomDrawers_ApplyStyle(id) end
end

function IchaUI_DrawerGridCols(id, count)
    local row = IchaUI_DrawerStyleRow(id)
    if not row then return nil end
    count = tonumber(count) or 0
    if row.useCols and tonumber(row.cols) and tonumber(row.cols) >= 1 then
        local cols = math.floor(tonumber(row.cols))
        if cols > 12 then cols = 12 end
        if cols < 1 then cols = 1 end
        return cols
    end
    if tonumber(row.rows) and tonumber(row.rows) >= 1 and count > 0 then
        local rows = math.floor(tonumber(row.rows))
        if rows < 1 then rows = 1 end
        local cols = math.floor((count + rows - 1) / rows)
        if cols < 1 then cols = 1 end
        if cols > 12 then cols = 12 end
        return cols
    end
    return nil
end

local function knownStrata(name)
    if type(name) ~= "string" then return nil end
    local i
    for i = 1, table.getn(STRATA) do
        if STRATA[i] == name then return name end
    end
    return nil
end

local function strataIndex(name, fallback)
    local i
    for i = 1, table.getn(STRATA) do
        if STRATA[i] == name then return i end
    end
    return fallback or 3
end

function IchaUI_DrawerApply(id)
    if id == "totems" then
        if IchaUI_ApplyTotemStrata then IchaUI_ApplyTotemStrata() end
        if IchaUITotems_Apply then IchaUITotems_Apply() end
    elseif id == "recall" then
        if IchaUI_ApplyRecallIconStrata then IchaUI_ApplyRecallIconStrata() end
    elseif id == "utility" or id == "imbue" or id == "shield" then
        if IchaUIShamanExtras_Apply then IchaUIShamanExtras_Apply() end
    elseif id == "minimap" then
        local strata = IchaUI_DrawerStyleGet("minimap")
        local panel = getglobal("IchaUIMinimapDrawerPanel")
        local handle = getglobal("IchaUIMinimapDrawerHandle")
        if strata and strata ~= "" then
            if panel and panel.SetFrameStrata then
                pcall(function() panel:SetFrameStrata(strata) end)
            end
            if handle and handle.SetFrameStrata then
                pcall(function() handle:SetFrameStrata(strata) end)
            end
        end
    elseif id == "resists" then
        if IchaUIUF_ApplyResistTextSize then IchaUIUF_ApplyResistTextSize() end
    end
    if IchaUI_CustomDrawers_ApplyStyle then IchaUI_CustomDrawers_ApplyStyle(id) end
end

local function currentText(id)
    local meta = info(id)
    local _, saved = IchaUI_DrawerStyleGet(id)
    if saved then return saved end
    if meta and meta.textVia == "totems" and IchaUITotems_Get then
        local t = IchaUITotems_Get()
        if t and tonumber(t.textSize) then return tonumber(t.textSize) end
    end
    if meta and meta.textVia == "extras" and IchaUIShamanExtras_Get then
        local g = IchaUIShamanExtras_Get()
        if g and tonumber(g.textSize) then return tonumber(g.textSize) end
    end
    return (meta and meta.text) or 11
end

local function currentStrata(id)
    local saved = IchaUI_DrawerStyleGet(id)
    if saved and saved ~= "" then return saved end
    local meta = info(id)
    return (meta and meta.strata) or "MEDIUM"
end

local function writeText(id, value)
    local n = math.floor((tonumber(value) or 11) + 0.5)
    if n < 6 then n = 6 end
    if n > 28 then n = 28 end
    local meta = info(id)
    local row = bag()[id]
    if type(row) ~= "table" then
        bag()[id] = {}
        row = bag()[id]
    end
    row.textSize = n
    if meta and meta.textVia == "totems" and IchaUITotems_Set then
        IchaUITotems_Set("textSize", n)
    elseif meta and meta.textVia == "extras" and IchaUIShamanExtras_Set then
        IchaUIShamanExtras_Set("textSize", n)
    end
    IchaUI_DrawerApply(id)
end

local function writeStrata(id, name)
    name = knownStrata(name)
    if not name then return end
    local row = bag()[id]
    if type(row) ~= "table" then
        bag()[id] = {}
        row = bag()[id]
    end
    row.strata = name
    IchaUI_DrawerApply(id)
end

local function writeCols(id, value)
    local n = math.floor((tonumber(value) or 1) + 0.5)
    if n < 1 then n = 1 end
    if n > 12 then n = 12 end
    local row = bag()[id]
    if type(row) ~= "table" then
        bag()[id] = {}
        row = bag()[id]
    end
    row.cols = n
    row.useCols = true
    IchaUI_DrawerApply(id)
end

local function writeRows(id, value)
    local n = math.floor((tonumber(value) or 0) + 0.5)
    if n < 0 then n = 0 end
    if n > 20 then n = 20 end
    local row = bag()[id]
    if type(row) ~= "table" then
        bag()[id] = {}
        row = bag()[id]
    end
    row.rows = n
    if n >= 1 then row.useCols = nil end
    IchaUI_DrawerApply(id)
end

local refreshers = {}

function IchaUI_DrawerExtrasRefresh()
    local i
    for i = 1, table.getn(refreshers) do
        refreshers[i]()
    end
    if IchaUI_CustomDrawers_RefreshOptions then IchaUI_CustomDrawers_RefreshOptions() end
end

local function goldButton(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(w)
    b:SetHeight(h)
    b:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    b:SetBackdropColor(0.08, 0.08, 0.09, 0.9)
    IchaUI_PaintGoldBorder(b, 0.8)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    fs:SetText(text or "")
    IchaUI_PaintGoldFont(fs, 0.93, 0.78, 0.35)
    b.label = fs
    b:SetScript("OnClick", onClick)
    return b
end

local function slider(parent, label, x, y, lo, hi, step, get, set)
    local cap = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cap:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    cap:SetWidth(108)
    cap:SetJustifyH("LEFT")
    cap:SetText(label)
    local lr, lg, lb = 0.9, 0.88, 0.8
    if label == "Icon" or label == "Popout" or label == "Scale" then lr, lg, lb = 1, 1, 1 end
    if IchaUI_DyeFs then
        IchaUI_DyeFs(cap, lr, lg, lb)
    end
    cap:SetTextColor(lr, lg, lb)
    local sl = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    sl:SetPoint("LEFT", cap, "RIGHT", 8, 0)
    sl:SetWidth(160)
    sl:SetHeight(16)
    sl:SetMinMaxValues(lo, hi)
    sl:SetValueStep(step)
    if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
    do
        local regions = { sl:GetRegions() }
        local ri
        for ri = 1, table.getn(regions) do
            local r = regions[ri]
            if r and r.SetText and r.GetObjectType and r:GetObjectType() == "FontString" then
                r:SetText("")
                if IchaUI_DyeFs then
                    IchaUI_DyeFs(r, 1, 1, 1)
                else
                    r:SetTextColor(1, 1, 1)
                end
            end
        end
    end
    local val = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    val:SetPoint("LEFT", sl, "RIGHT", 8, 0)
    if IchaUI_DyeFs then
        IchaUI_DyeFs(val, 0.93, 0.88, 0.7)
    else
        val:SetTextColor(0.93, 0.88, 0.7)
    end
    local fmt = "%.0f"
    if step and step < 1 then fmt = "%.2f" end
    local busy = false
    local function paint()
        busy = true
        local v = get()
        if not v then v = lo end
        sl:SetValue(v)
        val:SetText(string.format(fmt, v))
        busy = false
    end
    sl:SetScript("OnValueChanged", function()
        if busy then return end
        local v = this:GetValue()
        val:SetText(string.format(fmt, v))
        set(v)
    end)
    paint()
    return paint
end

function IchaUI_DrawerStyleControls(parent, id, x, y, skipText)
    if not parent or not id then return y or 0 end
    x = x or 10
    y = y or 0
    local sid = id
    local strataBtn = goldButton(parent, "Strata: " .. currentStrata(sid), 200, 20, function()
        local cur = currentStrata(sid)
        local idx = strataIndex(cur, 3) + 1
        if idx > table.getn(STRATA) then idx = 1 end
        writeStrata(sid, STRATA[idx])
        if this.label then this.label:SetText("Strata: " .. STRATA[idx]) end
    end)
    strataBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local sbtn = strataBtn
    table.insert(refreshers, function()
        if sbtn and sbtn.label then
            sbtn.label:SetText("Strata: " .. currentStrata(sid))
        end
    end)
    y = y - 26
    if not skipText then
        local paintText = slider(parent, "Text size", x, y, 6, 28, 1, function()
            return currentText(sid)
        end, function(v)
            writeText(sid, v)
        end)
        table.insert(refreshers, paintText)
        y = y - 28
    end
    local paintScale = slider(parent, "Icon", x, y, 0.5, 2, 0.05, function()
        if IchaUI_DrawerButtonScale then return IchaUI_DrawerButtonScale(sid) end
        return 1
    end, function(v)
        if IchaUI_DrawerButtonScaleSet then IchaUI_DrawerButtonScaleSet(sid, v) end
    end)
    table.insert(refreshers, paintScale)
    y = y - 28
    local paintPop = slider(parent, "Popout", x, y, 0.5, 2, 0.05, function()
        if IchaUI_DrawerPopScale then return IchaUI_DrawerPopScale(sid) end
        return 1
    end, function(v)
        if IchaUI_DrawerPopScaleSet then IchaUI_DrawerPopScaleSet(sid, v) end
    end)
    table.insert(refreshers, paintPop)
    y = y - 28
    local shapeBtn = goldButton(parent, "Shape: Rectangle", 150, 20, function()
        local row = bag()[sid]
        if type(row) ~= "table" then
            bag()[sid] = {}
            row = bag()[sid]
        end
        local cur = row.shape or "circle"
        if IchaUI_FormShapeNext then cur = IchaUI_FormShapeNext(cur) else cur = "circle" end
        row.shape = cur
        local lab = cur
        if IchaUI_FormShapeLabel then lab = IchaUI_FormShapeLabel(cur) end
        if this.label then this.label:SetText("Shape: " .. lab) end
        IchaUI_DrawerScaleApply(sid)
    end)
    shapeBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if shapeBtn.label then
        if IchaUI_DyeFs then
            IchaUI_DyeFs(shapeBtn.label, 1, 1, 1)
        else
            shapeBtn.label:SetTextColor(1, 1, 1)
        end
    end
    table.insert(refreshers, function()
        local row = IchaUI_DrawerStyleRow(sid)
        local cur = (row and row.shape) or "circle"
        local lab = cur
        if IchaUI_FormShapeLabel then lab = IchaUI_FormShapeLabel(cur) end
        if shapeBtn.label then shapeBtn.label:SetText("Shape: " .. lab) end
    end)
    y = y - 26
    local meta = info(sid)
    if meta and meta.grid then
        local paintCols = slider(parent, "Columns", x, y, 1, 12, 1, function()
            local row = IchaUI_DrawerStyleRow(sid)
            if row and row.useCols and tonumber(row.cols) then return tonumber(row.cols) end
            return meta.cols or 1
        end, function(v)
            writeCols(sid, v)
        end)
        table.insert(refreshers, paintCols)
        y = y - 28
        local paintRows = slider(parent, "Rows", x, y, 0, 20, 1, function()
            local row = IchaUI_DrawerStyleRow(sid)
            if row and tonumber(row.rows) then return tonumber(row.rows) end
            return 0
        end, function(v)
            writeRows(sid, v)
        end)
        table.insert(refreshers, paintRows)
        y = y - 28
    end
    return y
end

function IchaUI_BuildDrawerExtras(parent, y, x)
    if not parent then return y or 0 end
    y = y or -4
    if IchaUI_BuildCustomDrawerOptions then
        y = IchaUI_BuildCustomDrawerOptions(parent, y, x)
    end
    local need = -y + 40
    if parent.GetHeight and (parent:GetHeight() or 0) < need then
        parent:SetHeight(need)
    end
    return y
end

-- Radial tray: even circle around the closed button. Spread 90 is the clearance radius.
-- First icon is straight up (-90 deg). Lua 5.0: degrees via pi/180.
function IchaUI_DrawerNormSpread(v)
    local n = tonumber(v) or 90
    if n < 10 then n = 10 end
    if n > 360 then n = 360 end
    return math.floor(n + 0.5)
end

-- Arc is how many degrees the icons occupy (orb Spread). Nil keeps a full circle.
function IchaUI_DrawerNormArc(v)
    if v == nil or v == "" then return 360 end
    local n = tonumber(v)
    if not n then return 360 end
    if n < 10 then n = 10 end
    if n > 360 then n = 360 end
    return math.floor(n + 0.5)
end

-- Arc center in degrees. 0 = right, 90 = up, 270 = down. Nil keeps the first icon on top.
function IchaUI_DrawerNormRot(v)
    if v == nil or v == "" then return 90 end
    local n = tonumber(v)
    if not n then return 90 end
    if n < -360 then n = -360 end
    if n > 360 then n = 360 end
    return math.floor(n + 0.5)
end

function IchaUI_DrawerRadialRadius(count, buttonSize, iconSize, gap, spread)
    local b = tonumber(buttonSize) or 0
    local ic = tonumber(iconSize) or b
    local g = tonumber(gap) or 0
    if b < 1 then b = 1 end
    if ic < 1 then ic = 1 end
    if g < 0 then g = 0 end
    local n = tonumber(count) or 1
    if n < 1 then n = 1 end
    local clear = b + g
    local edge = (b + ic) * 0.5 + g
    if edge > clear then clear = edge end
    if n > 1 then
        local chord = ic + g
        local s = math.sin(math.pi / n)
        if s > 0.001 then
            local need = chord / (2 * s)
            if need > clear then clear = need end
        end
    end
    return clear * (IchaUI_DrawerNormSpread(spread) / 90)
end

function IchaUI_DrawerRadialXY(index, count, radius, arc, center)
    local n = tonumber(count) or 1
    if n < 1 then n = 1 end
    local i = (tonumber(index) or 1) - 1
    local span = IchaUI_DrawerNormArc(arc)
    local mid = IchaUI_DrawerNormRot(center)
    local deg = mid
    if n > 1 and span >= 360 then
        deg = mid - i * (360 / n)
    elseif n > 1 then
        deg = (mid - span / 2) + i * (span / (n - 1))
    end
    local rad = deg * math.pi / 180
    local r = tonumber(radius) or 0
    return math.cos(rad) * r, math.sin(rad) * r
end

-- Button border shapes shared by bars, hero bars, and drawers.
-- rect = current tooltip edge on the button's own size.
local FORM_SHAPES = { "rect", "square", "circle", "tooltip", "portrait",
    "pfsquare", "pfblizz", "metalplain", "eternium", "bronze", "wowui", "wood", "target" }
local FORM_LABEL = {
    rect = "Rectangle",
    square = "Square",
    circle = "Circle",
    tooltip = "Tooltip Ring",
    portrait = "Portrait",
}
-- Minimap skin art reused as button shapes (same files as MinimapSkin.lua).
-- Frames: the art's opaque outer edge is `outer` of the file width and its
-- hole is `hole` of the slot (alpha > 128, measured). The ring quad is
-- side / outer so the outer edge meets the slot; the round icon is grown 13%
-- past the hole so its baked 4/64 border tucks under the frame (~2-2.5px of
-- tuck at the 49px hero slot; 8% left that border showing at 12/3/6/9).
-- Edges: pfUI 64x8 edge strips on an 8px backdrop. `outset` puts the art's
-- outer visible pixel on the slot edge; `inset` is the stroke's inner edge.
-- Natural colors, like the minimap (no theme gold).
local FORM_DIR = "Interface\\AddOns\\IchaUI\\media\\minimapshapes\\"
local FORM_DEF = {
    pfsquare = { label = "pfUI Square", edge = FORM_DIR .. "pfui\\border.tga", outset = 0, inset = 1 },
    pfblizz = { label = "pfUI Blizz", edge = FORM_DIR .. "pfui\\border_blizz.tga", outset = 2, inset = 2 },
    metalplain = { label = "Metal Plain", ring = FORM_DIR .. "x4\\MetalPlain_Circular_Frame.tga", outer = 0.619, hole = 0.748 },
    eternium = { label = "Metal Eternium", ring = FORM_DIR .. "x4\\MetalEternium_Circular_Frame.tga", outer = 0.619, hole = 0.748 },
    bronze = { label = "Metal Bronze", ring = FORM_DIR .. "x4\\MetalBronze_Circular_Frame.tga", outer = 0.618, hole = 0.752 },
    wowui = { label = "WoWUI", ring = FORM_DIR .. "x4\\WowUI_Circular_Frame.tga", outer = 0.636, hole = 0.689 },
    wood = { label = "Wood Boards", ring = FORM_DIR .. "x4\\WoodBoards_Circular_Frame.tga", outer = 0.618, hole = 0.751 },
    target = { label = "Generic Target", ring = FORM_DIR .. "x4\\Generic1Target_Circular_Frame.tga", outer = 0.888, hole = 0.702 },
}
local FORM_ICON_GROW = 1.13
do
    local k, v
    for k, v in pairs(FORM_DEF) do FORM_LABEL[k] = v.label end
end

function IchaUI_FormShapeDef(v)
    return FORM_DEF[v]
end
local FORM_RING = "Interface\\Minimap\\UI-Minimap-Border"
local FORM_TRACK = "Interface\\Minimap\\MiniMap-TrackingBorder"
local FORM_TIP = "Interface\\AddOns\\IchaUI\\media\\minimapshapes\\tooltip-ring.tga"
local FORM_PORT = "Interface\\AddOns\\IchaUI\\media\\minimapshapes\\x4\\PortraitFrame.tga"
local FORM_PORT2 = "Interface\\AddOns\\IchaUI\\media\\PortraitFrame.tga"
-- Rings thickened ~50% inward (outer edge unchanged). New files are only seen
-- after a full client restart, so each tries its files in order and falls
-- back to the original ring. PortraitFrame-thick2 fills the source art's
-- transparent seam between its two gold rings (left side).
local FORM_THICK = {
    tooltip = {
        { "Interface\\AddOns\\IchaUI\\media\\minimapshapes\\tooltip-ring-thick.tga", "tooltip%-ring%-thick" },
        fallback = FORM_TIP,
    },
    portrait = {
        { "Interface\\AddOns\\IchaUI\\media\\minimapshapes\\x4\\PortraitFrame-thick2.tga", "portraitframe%-thick2" },
        { "Interface\\AddOns\\IchaUI\\media\\minimapshapes\\x4\\PortraitFrame-thick.tga", "portraitframe%-thick" },
        fallback = FORM_PORT,
    },
}
local thickOk = {}

-- Returns the loaded file's index in the list (1 = newest), or false.
local function loadThickRing(ring, shape)
    local row = FORM_THICK[shape]
    if not row then return false end
    local ok = thickOk[shape]
    if ok == nil then ok = {} thickOk[shape] = ok end
    local i
    for i = 1, table.getn(row) do
        if ok[i] ~= false then
            ring:SetTexture(row[i][1])
            local g = ring:GetTexture()
            if type(g) == "string" and string.find(string.lower(g), row[i][2]) then
                ok[i] = true
                return i
            end
            ok[i] = false
        end
    end
    ring:SetTexture(row.fallback)
    return false
end
local FORM_MASK = "Interface\\AddOns\\IchaUI\\media\\roundmask-circle.tga"
-- A failed SetTexture on this client leaves the old texture (or nil) in place,
-- so each spelling is tried until GetTexture reports the circle file.
local FORM_MASK_TRY = {
    "Interface\\AddOns\\IchaUI\\media\\roundmask-circle.tga",
    "Interface\\AddOns\\IchaUI\\media\\roundmask-circle",
    "Interface/AddOns/IchaUI/media/roundmask-circle.tga",
    "Interface/AddOns/IchaUI/media/roundmask-circle",
}
local formMaskPath = nil

local function formMaskLoaded(t)
    local g = t:GetTexture()
    if type(g) ~= "string" then return false end
    return string.find(string.lower(g), "roundmask%-circle") ~= nil
end

local function loadFormMask(t)
    if formMaskPath then
        t:SetTexture(formMaskPath)
        if formMaskLoaded(t) then return true end
    end
    local i
    for i = 1, table.getn(FORM_MASK_TRY) do
        t:SetTexture(FORM_MASK_TRY[i])
        if formMaskLoaded(t) then
            formMaskPath = FORM_MASK_TRY[i]
            return true
        end
    end
    t:SetTexture(FORM_MASK)
    return false
end

function IchaUI_FormMaskPath()
    return formMaskPath
end

function IchaUI_DrawerShape(id)
    local row = IchaUI_DrawerStyleRow(id)
    local s = row and row.shape
    if IchaUI_FormShapeNorm then return IchaUI_FormShapeNorm(s or "circle") end
    if s == "square" or s == "rect" or s == "tooltip" or s == "portrait" or s == "circle" then return s end
    return "circle"
end

function IchaUI_FormShapeNorm(v)
    if v == "square" or v == "circle" or v == "tooltip" or v == "portrait" or v == "rect" then
        return v
    end
    if v and FORM_DEF[v] then return v end
    return "rect"
end

function IchaUI_FormShapeLabel(v)
    local s = IchaUI_FormShapeNorm(v)
    return FORM_LABEL[s] or "Rectangle"
end

function IchaUI_FormShapeNext(v)
    local s = IchaUI_FormShapeNorm(v)
    local i
    for i = 1, table.getn(FORM_SHAPES) do
        if FORM_SHAPES[i] == s then
            local n = i + 1
            if n > table.getn(FORM_SHAPES) then n = 1 end
            return FORM_SHAPES[n]
        end
    end
    return "square"
end

function IchaUI_FormIsSquare(v)
    local s = IchaUI_FormShapeNorm(v)
    return s == "square" or s == "circle" or s == "tooltip" or s == "portrait" or FORM_DEF[s] ~= nil
end

function IchaUI_ApplyButtonForm(b, shape)
    if not b then return end
    shape = IchaUI_FormShapeNorm(shape)
    b._formStep = "start"
    b._formMask = nil
    b._goldRingForm = nil
    if b.SetBackdrop then b:SetBackdrop(nil) end
    if b.formRing then b.formRing:Hide() end
    if b.ringHost then b.ringHost:Hide() end
    if b.goldRing then b.goldRing:Hide() end
    if b.circleBg then b.circleBg:Hide() end
    if b.rectBorder then b.rectBorder:Hide() end
    if b.GetNormalTexture then
        local nt = b:GetNormalTexture()
        if nt then nt:Hide() end
    end
    local def = FORM_DEF[shape]
    if shape == "rect" or shape == "square" or (def and def.edge) then
        if not b.border then
            local border = CreateFrame("Frame", nil, b)
            if border.EnableMouse then border:EnableMouse(false) end
            border:SetFrameLevel((b:GetFrameLevel() or 1) + 6)
            b.border = border
        end
        b.border:SetFrameLevel((b:GetFrameLevel() or 1) + 6)
        local e = 10
        local inset
        b.border:ClearAllPoints()
        if def then
            local o = def.outset or 0
            e = 8
            inset = def.inset or 1
            b.border:SetPoint("TOPLEFT", b, "TOPLEFT", -o, o)
            b.border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", o, -o)
            b.border:SetBackdrop({
                bgFile = nil,
                edgeFile = def.edge,
                tile = true, tileSize = 8, edgeSize = e,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            b.border:SetBackdropBorderColor(1, 1, 1, 1)
            b._ringTex = def.edge
        else
            if b.GetWidth then
                local w = b:GetWidth() or 36
                e = math.floor(w * 0.22 + 0.5)
                if e < 8 then e = 8 end
                if e > 14 then e = 14 end
            end
            b.border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
            b.border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
            b.border:SetBackdrop({
                bgFile = nil,
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                tile = true, tileSize = 8, edgeSize = e,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            if IchaUI_PaintGoldBorder then IchaUI_PaintGoldBorder(b.border, 1) end
            b._ringTex = "Interface/Tooltips/UI-Tooltip-Border"
            inset = math.floor(e * 4 / 16 + 0.5)
        end
        b.border:Show()
        if b.roundMask then b.roundMask:Hide() end
        if b.iconMask then b.iconMask:Hide() end
        if b.cdMask then b.cdMask:Hide() end
        if inset < 1 then inset = 1 end
        b._formShape = shape
        if b._iconPortrait then IchaUI_SetButtonIcon(b) end
        if b.icon then
            b.icon:ClearAllPoints()
            b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", inset, -inset)
            b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -inset, inset)
            local u0, u1 = 0.08, 0.92
            local span = u1 - u0
            local bw = b:GetWidth() or 1
            local bh = b:GetHeight() or 1
            if bw < 1 then bw = 1 end
            if bh < 1 then bh = 1 end
            if shape == "rect" and bw > bh then
                local crop = (1 - (bh / bw)) / 2
                if crop < 0 then crop = 0 end
                if crop > 0.45 then crop = 0.45 end
                b.icon:SetTexCoord(u0, u1, u0 + crop * span, u1 - crop * span)
            else
                b.icon:SetTexCoord(u0, u1, u0, u1)
            end
        end
        b._formShape = shape
        local iw = (b:GetWidth() or 36) - inset * 2
        local ih = (b:GetHeight() or 36) - inset * 2
        if iw < 8 then iw = 8 end
        if ih < 8 then ih = 8 end
        b._innerW = iw
        b._innerH = ih
        b._inset = inset
        b._iconDX = 0
        b._iconDY = 0
        b._hole = iw
        if ih < iw then b._hole = ih end
        b._formStep = "edge"
        return
    end
    if b.border and b.border.SetBackdrop then
        b.border:SetBackdrop(nil)
        b.border:Hide()
    end
    b._formShape = shape
    if shape == "circle" and b.goldRing then
        -- Drawer/totem circle keeps its own look: square icon under the black
        -- round mask and the tracker ring. Undo a portrait-drawn icon.
        b._goldRingForm = true
        b._iconDX = 0
        b._iconDY = 0
        b._ringTex = b.goldRing.GetTexture and b.goldRing:GetTexture()
        if b._iconPortrait then
            IchaUI_SetButtonIcon(b)
            if b.icon then
                local raw = b.icon._ichaRawCoord or b.icon.SetTexCoord
                raw(b.icon, 0.08, 0.92, 0.08, 0.92)
            end
        end
        b.goldRing:Show()
        if b.circleBg then b.circleBg:Show() end
        if b.roundMask then b.roundMask:Show() end
        if b.iconMask then b.iconMask:Hide() end
        if b.cdMask then b.cdMask:Hide() end
        b._formStep = "goldRing"
        return
    end
    if not b.ringHost then
        local host = CreateFrame("Frame", nil, b)
        host:EnableMouse(false)
        host:SetFrameLevel((b:GetFrameLevel() or 1) + 8)
        local created = host:CreateTexture(nil, "OVERLAY")
        created:Hide()
        host.ring = created
        b.ringHost = host
    end
    b.ringHost:SetFrameLevel((b:GetFrameLevel() or 1) + 8)
    b.ringHost:Show()
    local ring = b.ringHost.ring
    if b.formRing then b.formRing:Hide() end
    local side = 36
    if b.GetWidth then side = b:GetWidth() or side end
    local tex = FORM_RING
    -- Circle uses the drawer tracker ring (MiniMap-TrackingBorder), not the
    -- raw minimap border. 1.65 and TOPLEFT match the drawer gold ring.
    local scale = 1.65
    if shape == "circle" then
        tex = FORM_TRACK
        scale = 1.65
    elseif shape == "tooltip" then
        tex = FORM_TIP
        scale = 1.0
    elseif shape == "portrait" then
        tex = FORM_PORT
        scale = 1.0
    end
    if def and def.ring then tex = def.ring end
    if shape == "tooltip" or shape == "portrait" then
        b._ringThick = loadThickRing(ring, shape)
    else
        b._ringThick = nil
        ring:SetTexture(tex)
    end
    b._ringTex = ring:GetTexture()
    if ring.SetBlendMode then ring:SetBlendMode("BLEND") end
    if ring.SetTexCoord then ring:SetTexCoord(0, 1, 0, 1) end
    if def then ring:SetVertexColor(1, 1, 1, 1) end
    if shape == "circle" and IchaUI_PaintGoldRing then IchaUI_PaintGoldRing(ring) end
    if (shape == "tooltip" or shape == "portrait") and IchaUI_PaintGoldVertex then
        IchaUI_PaintGoldVertex(ring, 0.75, 0.52, 0.04, 1)
    end
    -- Tracker art sits in the top-left of the texture. A TOPLEFT anchor
    -- pins that gold up-left of the slot. Center the visible ring instead.
    -- 1.65 makes the gold outer edge match the slot; the shift pulls the
    -- art's center onto the button center. No texcoord zoom.
    ring:ClearAllPoints()
    if shape == "circle" then
        local bw = math.floor(side * 64 / 36 + 0.5)
        local shift = math.floor(side * 0.347 + 0.5)
        ring:SetWidth(bw)
        ring:SetHeight(bw)
        ring:SetPoint("CENTER", b, "CENTER", shift, -shift)
    elseif def then
        local rw = side / def.outer
        ring:SetWidth(rw)
        ring:SetHeight(rw)
        ring:SetPoint("CENTER", b, "CENTER", 0, 0)
    else
        ring:SetWidth(side)
        ring:SetHeight(side)
        ring:SetPoint("CENTER", b, "CENTER", 0, 0)
    end
    ring:Show()
    b._formStep = "ring"
    -- Tracker hole is 56% of the slot. Tooltip and portrait rings sit slightly
    -- inside the slot, so the icon stops at that inner edge, not the slot edge.
    -- SetPortraitToTexture keeps the icon's baked 4/64 border at 12/3/6/9
    -- o'clock, so each icon is grown past the hole until that border tucks
    -- against the ring (hole: circle 0.56, tooltip 0.90, portrait 0.88).
    local frac = 0.62
    if shape == "tooltip" then frac = 0.96
    elseif shape == "portrait" then frac = 0.94
    elseif def then frac = def.hole * FORM_ICON_GROW end
    local iconSz = math.floor(side * frac + 0.5)
    if iconSz < 10 then iconSz = 10 end
    b._hole = iconSz
    local vis = 0.56
    if shape == "tooltip" then vis = 0.90
    elseif shape == "portrait" then vis = 0.88
    elseif def and def.hole then vis = def.hole end
    b._holeVis = side * vis
    -- The tracker ring's hole sits up-left of its outer edge (measured at the
    -- 49 px hero slot: 1.5 px high, 0.5 px left). Move the icon, not the ring,
    -- so the ring's outer edge still meets the slot edge.
    b._iconDX = 0
    b._iconDY = 0
    if shape == "circle" then
        b._iconDX = -side * 0.010
        b._iconDY = side * 0.031
    end
    if b.icon then
        b.icon:ClearAllPoints()
        b.icon:SetWidth(iconSz)
        b.icon:SetHeight(iconSz)
        b.icon:SetPoint("CENTER", b, "CENTER", b._iconDX, b._iconDY)
        if b.icon.SetTexCoord and not b._iconPortrait then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        if b.icon.SetDrawLayer then b.icon:SetDrawLayer("ARTWORK") end
    end
    IchaUI_SetButtonIcon(b)
    b._formStep = "icon"
    b._formMask = true
    IchaUI_PlaceFormMask(b)
    b._formStep = "mask"
end
IchaUI_ApplyButtonForm_src = "DrawerStyle"

-- Custom art for round shapes: [3]/[4] is a pre-rounded copy drawn with a plain
-- SetTexture; [1]/[2] is a 64px copy for SetPortraitToTexture. Both are newer
-- files (full restart); without them the square original draws under the mask.
local PORTRAIT_ALT = {
    ["firetwist-searing"] = { "Interface\\AddOns\\IchaUI\\media\\firetwist-searing-64.tga", "firetwist-searing-64",
        "Interface\\AddOns\\IchaUI\\media\\firetwist-searing-round.tga", "firetwist-searing-round" },
    ["firetwist-magma"] = { "Interface\\AddOns\\IchaUI\\media\\firetwist-magma-64.tga", "firetwist-magma-64",
        "Interface\\AddOns\\IchaUI\\media\\firetwist-magma-round.tga", "firetwist-magma-round" },
}

local function formIsRound(s)
    if s == "circle" or s == "tooltip" or s == "portrait" then return true end
    local d = s and FORM_DEF[s]
    return d ~= nil and d.ring ~= nil
end

function IchaUI_FormIsRound(s)
    return formIsRound(s)
end

-- Square-hole shapes drawn with an edge backdrop (square, rect, pfUI edges).
function IchaUI_FormIsEdged(s)
    if s == "square" or s == "rect" then return true end
    local d = s and FORM_DEF[s]
    return d ~= nil and d.edge ~= nil
end

-- One entry point for icon art on IchaUIBtn buttons. Round shapes draw the
-- icon with SetPortraitToTexture, so the outside of the circle is transparent.
-- The plain SetTexture runs first so a no-op portrait call still leaves art.
function IchaUI_SetButtonIcon(b, path)
    if not b or not b.icon then return end
    local ic = b.icon
    if path then b._iconPath = path end
    path = b._iconPath
    if not path then return end
    local setTex = ic._ichaRawSet or ic.SetTexture
    local setCoord = ic._ichaRawCoord or ic.SetTexCoord
    if formIsRound(b._formShape) and not b._goldRingForm then
        if b._iconPortrait and b._iconDrawn == path then return end
        local was = b._iconPortrait
        local src = path
        local lp = string.lower(path)
        local alt = nil
        local k, v
        for k, v in pairs(PORTRAIT_ALT) do
            if string.find(lp, k, 1, true) then alt = v end
        end
        local ok = false
        if alt then
            src = nil
            -- A failed SetTexture keeps the old texture, so check the name.
            setTex(ic, alt[3])
            local g = ic:GetTexture()
            if type(g) == "string" and string.find(string.lower(g), alt[4], 1, true) then
                ok = true
            else
                setTex(ic, alt[1])
                g = ic:GetTexture()
                if type(g) == "string" and string.find(string.lower(g), alt[2], 1, true) then
                    src = alt[1]
                end
            end
        end
        if src and SetPortraitToTexture then
            setTex(ic, src)
            ok = pcall(function() SetPortraitToTexture(ic, src) end)
            if not ok and ic.GetName and ic:GetName() then
                ok = pcall(function() SetPortraitToTexture(ic:GetName(), src) end)
            end
        end
        if ok then
            setCoord(ic, 0, 1, 0, 1)
            b._iconPortrait = true
            b._iconDrawn = path
            if not was and b._formMask then IchaUI_PlaceFormMask(b) end
            return
        end
        -- Square art on a round shape: crop like ApplyButtonForm and let the
        -- round masks cover the corners.
        b._iconPortrait = nil
        b._iconDrawn = path
        setTex(ic, path)
        setCoord(ic, 0.08, 0.92, 0.08, 0.92)
        if was and b._formMask then IchaUI_PlaceFormMask(b) end
        return
    end
    b._iconPortrait = nil
    b._iconDrawn = path
    setTex(ic, path)
end

-- For buttons whose own code sets icon art directly (totem slots): route
-- the icon's SetTexture through IchaUI_SetButtonIcon so round shapes get
-- the transparent round icon, and ignore crop texcoords while it is drawn.
function IchaUI_WrapButtonIcon(b)
    if not b or not b.icon or b.icon._ichaRawSet then return end
    local ic = b.icon
    ic._ichaRawSet = ic.SetTexture
    ic._ichaRawCoord = ic.SetTexCoord
    ic.SetTexture = function(self, p, a2, a3, a4)
        if type(p) == "number" then
            b._iconPath = nil
            b._iconPortrait = nil
            b._iconDrawn = nil
            self._ichaRawSet(self, p, a2, a3, a4)
            return
        end
        if type(p) == "string" then
            b._iconPath = p
            if formIsRound(b._formShape) and not b._goldRingForm then
                b._iconDrawn = nil
                IchaUI_SetButtonIcon(b, p)
                return
            end
        else
            b._iconPath = nil
        end
        b._iconPortrait = nil
        b._iconDrawn = p
        self._ichaRawSet(self, p)
    end
    ic.SetTexCoord = function(self, a1, a2, a3, a4)
        if b._iconPortrait then
            self._ichaRawCoord(self, 0, 1, 0, 1)
            return
        end
        self._ichaRawCoord(self, a1, a2, a3, a4)
    end
    local cur = ic.GetTexture and ic:GetTexture()
    if type(cur) == "string" and not b._iconPath then b._iconPath = cur end
end

-- Pressed look for a styled button whose own press code assumes the drawer
-- circle (totem slots): re-apply the form, then nudge the icon 1px down-right.
-- Returns false for the drawer gold-ring circle so the caller keeps its path.
function IchaUI_FormPress(b, down)
    if not b or not b.icon or not b._formShape or b._goldRingForm then return false end
    if b._formShape == "circle" and b.goldRing then return false end
    IchaUI_ApplyButtonForm(b, b._formShape)
    if down then
        local ic = b.icon
        if b._inset then
            local p1, rel, p2, x, y = ic:GetPoint(1)
            if p1 == "TOPLEFT" then
                local i = b._inset
                ic:ClearAllPoints()
                ic:SetPoint("TOPLEFT", b, "TOPLEFT", i + 1, -i - 1)
                ic:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -i + 1, i - 1)
                return true
            end
        end
        ic:ClearAllPoints()
        ic:SetPoint("CENTER", b, "CENTER", (b._iconDX or 0) + 1, (b._iconDY or 0) - 1)
    end
    return true
end

-- Press shade / hover glow for a styled button. Round shapes get a disc (or
-- round glow) the size of the frame's opening, so no square corners show past
-- the ring. Everything else covers the icon. Returns false for the drawer
-- gold-ring circle and unstyled buttons so callers keep their own look.
local OVERLAY_DISC = "Interface\\AddOns\\IchaUI\\media\\circledisc.tga"
local OVERLAY_GLOW = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
local OVERLAY_SHADE = "Interface/ChatFrame/ChatFrameBackground"
local OVERLAY_SQGLOW = "Interface/Buttons/ButtonHilight-Square"
function IchaUI_FormOverlay(b, tex, kind)
    if not b or not tex or not b._formShape or b._goldRingForm then return false end
    tex:ClearAllPoints()
    if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
    if formIsRound(b._formShape) then
        local d = b._holeVis or b._hole or (b:GetWidth() or 36) * 0.56
        if kind == "glow" then
            tex:SetTexture(OVERLAY_GLOW)
            d = d * 1.15
        else
            tex:SetTexture(OVERLAY_DISC)
        end
        tex:SetWidth(d)
        tex:SetHeight(d)
        tex:SetPoint("CENTER", b, "CENTER", b._iconDX or 0, b._iconDY or 0)
        return true
    end
    if kind == "glow" then
        tex:SetTexture(OVERLAY_SQGLOW)
    else
        tex:SetTexture(OVERLAY_SHADE)
    end
    if b.icon then tex:SetAllPoints(b.icon) else tex:SetAllPoints(b) end
    return true
end

-- Cooldown sweep sheets: 64-frame pie atlases (8x8 cells). Cell 0 is full
-- dark; the clear wedge grows clockwise from 12 o'clock, like the Blizzard
-- model. Round shapes use the circle sheet on the icon; square and rect use
-- the square sheet stretched over the icon's inner rect.
local SWEEP_GRID = 8
local SWEEP_N = 64
local SWEEP_HALF = 0.5 / 1024
local SWEEP_SHEETS = {
    round = { path = "Interface\\AddOns\\IchaUI\\media\\cdsweep-round.tga", pat = "cdsweep%-round" },
    square = { path = "Interface\\AddOns\\IchaUI\\media\\cdsweep-square.tga", pat = "cdsweep%-square" },
}
local sweepSheetOk = {}

local function sweepSheetFor(shape)
    if formIsRound(shape) then return "round" end
    if shape == "square" or shape == "rect" then return "square" end
    if shape and FORM_DEF[shape] and FORM_DEF[shape].edge then return "square" end
    return nil
end

local function sweepLoad(sw, key)
    if sw._sheet == key then return true end
    if sweepSheetOk[key] == false then return false end
    local row = SWEEP_SHEETS[key]
    sw.tex:SetTexture(row.path)
    local g = sw.tex:GetTexture()
    if type(g) == "string" and string.find(string.lower(g), row.pat) then
        sweepSheetOk[key] = true
        sw.tex2:SetTexture(row.path)
        sw._sheet = key
        sw._cell = nil
        return true
    end
    sweepSheetOk[key] = false
    return false
end

local function sweepCoords(tex, i)
    local col = math.mod(i, SWEEP_GRID)
    local row = math.floor(i / SWEEP_GRID)
    tex:SetTexCoord(col / SWEEP_GRID + SWEEP_HALF, (col + 1) / SWEEP_GRID - SWEEP_HALF,
        row / SWEEP_GRID + SWEEP_HALF, (row + 1) / SWEEP_GRID - SWEEP_HALF)
end

-- Sub-cell interpolation: cell i (sw.tex) at alpha t over cell i+1 (sw.tex2)
-- at alpha a. The sheets are flat black at alpha 158, so the two layers
-- multiply: the shared dark keeps exactly 158 and the 5.6 degree sliver
-- between the cells fades out with t. Integer progress is one cell at full.
local SWEEP_A = 158 / 255

local function sweepProgress(sw, p)
    if p < 0 then p = 0 end
    if p > SWEEP_N - 0.0001 then p = SWEEP_N - 0.0001 end
    local i = math.floor(p)
    local t = 1 - (p - i)
    if sw._cell ~= i then
        sw._cell = i
        sweepCoords(sw.tex, i)
        if i + 1 < SWEEP_N then
            sweepCoords(sw.tex2, i + 1)
            sw.tex2:Show()
        else
            sw.tex2:Hide()
        end
    end
    sw.tex:SetAlpha(t)
    if i + 1 < SWEEP_N then
        sw.tex2:SetAlpha((1 - (1 - SWEEP_A) / (1 - SWEEP_A * t)) / SWEEP_A)
    end
end

-- Cooldown numbers: the square buttons' text is ShaguTweaks "Cooldown
-- Numbers", which lives on the Blizzard model. With the model hidden, the
-- same text is drawn here: same font, size rule, formatting, colors, update
-- rate, and the same rule of no text under 2 seconds (no GCD text).
local TIMER_WRAP = (2 ^ 32) / 1000

local function timerWanted(b)
    if b.cooldown and (b.cooldown.noCooldownCount or b.cooldown.pfCooldownType) then return false end
    if not ShaguTweaks or not ShaguTweaks_config then return false end
    local key = "Cooldown Numbers"
    if ShaguTweaks.T and ShaguTweaks.T[key] then key = ShaguTweaks.T[key] end
    return ShaguTweaks_config[key] == 1
end

local function timerText(remaining)
    if ShaguTweaks and ShaguTweaks.TimeConvert then return ShaguTweaks.TimeConvert(remaining) end
    local color = "|cffffffff"
    if remaining < 5 then
        color = "|cffff5555"
    elseif remaining < 10 then
        color = "|cffffff55"
    end
    if remaining < 60 then return color .. math.ceil(remaining) end
    if remaining < 3600 then return color .. math.ceil(remaining / 60) .. "m" end
    if remaining < 86400 then return color .. math.ceil(remaining / 3600) .. "h" end
    return color .. math.ceil(remaining / 86400) .. "d"
end

local function timerFont(b)
    local fs = b.cdText
    if not fs then
        local host = b.textLayer or b
        fs = host:CreateFontString(nil, "OVERLAY")
        b.cdText = fs
    end
    local size = b:GetHeight() or 0
    if size > 0 then size = size * 0.64 else size = 12 end
    if size > 14 then size = 14 end
    if fs._size ~= size then
        fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
        fs._size = size
    end
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", b, "CENTER", b._iconDX or 0, b._iconDY or 0)
    return fs
end

local function timerHide(b)
    if b and b.cdText then
        b.cdText:SetText("")
        b.cdText:Hide()
        b.cdText._last = nil
    end
end

-- One shared driver runs every frame while any sweep is active; its script is
-- cleared when the last one stops.
local sweepActive = {}
local sweepActiveN = 0
local sweepDriver = CreateFrame("Frame")

local function sweepStop(sw)
    if sw._ticking then
        sw._ticking = nil
        sweepActive[sw] = nil
        sweepActiveN = sweepActiveN - 1
        if sweepActiveN <= 0 then
            sweepActiveN = 0
            sweepDriver:SetScript("OnUpdate", nil)
        end
    end
    sw:Hide()
    sw._cell = nil
    timerHide(sw._owner)
end

local function sweepTick(sw, dt, now)
    local dur = sw._dur or 0
    local elapsed = now - (sw._start or 0)
    if elapsed < 0 then elapsed = elapsed + TIMER_WRAP end
    local remaining = dur - elapsed
    if dur <= 0 or remaining <= 0 then
        sweepStop(sw)
        return
    end
    local left = remaining / dur
    if left > 1 then left = 1 end
    sweepProgress(sw, (1 - left) * SWEEP_N)
    local b = sw._owner
    if b and b.cdText and sw._timer then
        sw._textElapsed = (sw._textElapsed or 0) + (dt or 0)
        if sw._textElapsed >= 0.1 or not b.cdText._last then
            sw._textElapsed = 0
            local t = timerText(remaining)
            if b.cdText._last ~= t then
                b.cdText._last = t
                b.cdText:SetText(t)
            end
        end
    end
end

local function sweepDrive()
    local dt = arg1 or 0
    local now = GetTime()
    for sw in pairs(sweepActive) do
        sweepTick(sw, dt, now)
    end
end

-- Returns true when the custom sweep owns this button's cooldown; the caller
-- then keeps the Blizzard model hidden. False means use the model as before
-- (unknown shape, or the sheet is not loadable until a full restart).
function IchaUI_SetButtonSweep(b, start, duration, enable)
    if not b then return false end
    local key = sweepSheetFor(b._formShape)
    if not b.sweep and key then
        local f = CreateFrame("Frame", nil, b)
        f:EnableMouse(false)
        f.tex = f:CreateTexture(nil, "ARTWORK")
        f.tex:SetAllPoints(f)
        f.tex2 = f:CreateTexture(nil, "ARTWORK")
        f.tex2:SetAllPoints(f)
        f._owner = b
        f:Hide()
        b.sweep = f
    end
    local sw = b.sweep
    if not key or not sweepLoad(sw, key) then
        b._sweepOn = nil
        if sw then sweepStop(sw) end
        return false
    end
    b._sweepOn = true
    if b.cooldown then b.cooldown._ichaSweepOwner = b end
    sw:ClearAllPoints()
    if key == "round" then
        local sz = b._hole or 36
        sw:SetWidth(sz)
        sw:SetHeight(sz)
        sw:SetPoint("CENTER", b, "CENTER", b._iconDX or 0, b._iconDY or 0)
    else
        local inset = b._inset or 1
        sw:SetPoint("TOPLEFT", b, "TOPLEFT", inset, -inset)
        sw:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -inset, inset)
    end
    -- Above the icon and model (+4), below the gold edge (+6) and ring (+8).
    sw:SetFrameLevel((b:GetFrameLevel() or 1) + 5)
    local st = start or 0
    local dur = duration or 0
    local now = GetTime()
    if enable == 0 or dur <= 0 or st <= 0 or st + dur <= now then
        sweepStop(sw)
        return true
    end
    local changed = sw._start ~= st or sw._dur ~= dur
    sw._start = st
    sw._dur = dur
    sw._timer = dur >= 2 and timerWanted(b)
    if sw._timer then
        local fs = timerFont(b)
        if changed then fs._last = nil end
        fs:Show()
    else
        timerHide(b)
    end
    if not sw._ticking then
        sw._ticking = true
        sweepActive[sw] = true
        sweepActiveN = sweepActiveN + 1
        if sweepActiveN == 1 then sweepDriver:SetScript("OnUpdate", sweepDrive) end
    end
    sweepTick(sw, 0, now)
    if sw._ticking then sw:Show() end
    return true
end

function IchaUI_SweepDebug(b)
    local sw = b and b.sweep
    if not sw then return "sweep=none shape=" .. tostring(b and b._formShape) end
    local key = sweepSheetFor(b._formShape)
    local row = key and SWEEP_SHEETS[key]
    local fs = b.cdText
    return "sweep=" .. tostring(row and row.path) .. " loaded=" .. tostring(key and sweepSheetOk[key])
        .. " on=" .. tostring(b._sweepOn) .. " shown=" .. tostring(sw:IsShown() and true or false)
        .. " cell=" .. tostring(sw._cell) .. " | timer want=" .. tostring(sw._timer and true or false)
        .. " shown=" .. tostring(fs and fs:IsShown() and true or false)
        .. " text=" .. tostring(fs and fs._last) .. " size=" .. tostring(fs and fs._size)
        .. " ringThick=" .. tostring(b._ringThick)
end

-- Corner crop for circle, tooltip, and portrait. Two black roundmask layers:
-- b.roundMask on the button in OVERLAY (above the ARTWORK icon) and b.iconMask,
-- a child frame above the cooldown model so the sweep corners are covered too.
-- Both are anchored to the button with an explicit size, never to b.icon: the
-- icon is a texture, and a frame anchored to a texture may never get a rect.
function IchaUI_PlaceFormMask(b)
    if not b then return end
    if not b._formMask then
        if b.iconMask then b.iconMask:Hide() end
        if b.cdMask then b.cdMask:Hide() end
        return
    end
    if b._iconPortrait then
        if b.roundMask then b.roundMask:Hide() end
        if b.iconMask then b.iconMask:Hide() end
        if b.cdMask then b.cdMask:Hide() end
        local lvl = b:GetFrameLevel() or 1
        if b.cooldown then b.cooldown:SetFrameLevel(lvl + 4) end
        if b.ringHost then b.ringHost:SetFrameLevel(lvl + 8) end
        if b.textLayer then b.textLayer:SetFrameLevel(lvl + 10) end
        return
    end
    local sz = b._hole
    if not sz or sz < 4 then sz = math.floor((b:GetWidth() or 36) * 0.56 + 0.5) end
    if b.roundMask then
        local rm = b.roundMask
        b._rmOk = loadFormMask(rm)
        rm:SetVertexColor(0, 0, 0, 1)
        if rm.SetBlendMode then rm:SetBlendMode("BLEND") end
        if rm.SetTexCoord then rm:SetTexCoord(0, 1, 0, 1) end
        if rm.SetDrawLayer then rm:SetDrawLayer("OVERLAY") end
        rm:ClearAllPoints()
        rm:SetWidth(sz)
        rm:SetHeight(sz)
        rm:SetPoint("CENTER", b, "CENTER", b._iconDX or 0, b._iconDY or 0)
        rm:Show()
    end
    if not b.iconMask then
        local f = CreateFrame("Frame", nil, b)
        f:EnableMouse(false)
        f.tex = f:CreateTexture(nil, "OVERLAY")
        b.iconMask = f
    end
    local f = b.iconMask
    local t = f.tex
    f:ClearAllPoints()
    f:SetWidth(sz)
    f:SetHeight(sz)
    f:SetPoint("CENTER", b, "CENTER", b._iconDX or 0, b._iconDY or 0)
    b._imOk = loadFormMask(t)
    t:SetVertexColor(0, 0, 0, 1)
    if t.SetBlendMode then t:SetBlendMode("BLEND") end
    if t.SetTexCoord then t:SetTexCoord(0, 1, 0, 1) end
    if t.SetDrawLayer then t:SetDrawLayer("OVERLAY") end
    t:ClearAllPoints()
    t:SetWidth(sz)
    t:SetHeight(sz)
    t:SetPoint("CENTER", f, "CENTER", 0, 0)
    t:Show()
    f:Show()
    local base = b:GetFrameLevel() or 1
    if b.cooldown then b.cooldown:SetFrameLevel(base + 4) end
    f:SetFrameLevel(base + 6)
    if b.ringHost then b.ringHost:SetFrameLevel(base + 8) end
    if b.textLayer then b.textLayer:SetFrameLevel(base + 10) end
    if b.cdMask then b.cdMask:Hide() end
end

local function dbgVal(o, m)
    if not o or not o[m] then return "-" end
    local r
    pcall(function() r = o[m](o) end)
    if r == nil then return "nil" end
    if type(r) == "number" then return tostring(math.floor(r + 0.5)) end
    if type(r) == "string" then return (string.gsub(r, "^.*[\\/]", "")) end
    if type(r) == "table" and r.GetName then return tostring(r:GetName() or "anon") end
    return tostring(r)
end

local function dbgFull(t)
    if not t or not t.GetTexture then return "-" end
    local r
    pcall(function() r = t:GetTexture() end)
    return tostring(r)
end

local function dbgTint(t)
    if not t or not t.GetVertexColor then return "-" end
    local r, g, bl, a
    pcall(function() r, g, bl, a = t:GetVertexColor() end)
    local s = tostring(r) .. "," .. tostring(g) .. "," .. tostring(bl) .. "," .. tostring(a)
    if t.GetBlendMode then s = s .. " " .. dbgVal(t, "GetBlendMode") end
    return s
end

local function dbgButton(b)
    local out = DEFAULT_CHAT_FRAME
    local m = b.iconMask
    local mt = m and m.tex
    local rm = b.roundMask
    local ic = b.icon
    out:AddMessage("|cffffd100" .. dbgVal(b, "GetName") .. "|r shape=" .. tostring(b._formShape)
        .. " step=" .. tostring(b._formStep) .. " own=" .. tostring(b._formMask)
        .. " hole=" .. tostring(b._hole) .. " lvl=" .. dbgVal(b, "GetFrameLevel")
        .. " " .. dbgVal(b, "GetFrameStrata")
        .. " cd=" .. dbgVal(b.cooldown, "GetFrameLevel") .. " ring=" .. dbgVal(b.ringHost, "GetFrameLevel"))
    out:AddMessage("  form=" .. tostring(b._formShape) .. " (" .. tostring(IchaUI_FormShapeLabel(b._formShape)) .. ")"
        .. " ringTex=" .. tostring(b._ringTex) .. " goldRingForm=" .. tostring(b._goldRingForm)
        .. " iconOff=" .. string.format("%.2f,%.2f", b._iconDX or 0, b._iconDY or 0)
        .. " wrapped=" .. tostring(ic and ic._ichaRawSet ~= nil))
    out:AddMessage("  iconMask=" .. tostring(m ~= nil) .. " sh=" .. dbgVal(m, "IsShown") .. " vis=" .. dbgVal(m, "IsVisible")
        .. " " .. dbgVal(m, "GetWidth") .. "x" .. dbgVal(m, "GetHeight") .. " L=" .. dbgVal(m, "GetLeft")
        .. " lvl=" .. dbgVal(m, "GetFrameLevel") .. " " .. dbgVal(m, "GetFrameStrata")
        .. " tex=" .. dbgVal(mt, "GetTexture") .. " tsh=" .. dbgVal(mt, "IsShown") .. " " .. dbgVal(mt, "GetDrawLayer")
        .. " | roundMask sh=" .. dbgVal(rm, "IsShown") .. " tex=" .. dbgVal(rm, "GetTexture")
        .. " " .. dbgVal(rm, "GetDrawLayer") .. " " .. dbgVal(rm, "GetWidth") .. " L=" .. dbgVal(rm, "GetLeft"))
    out:AddMessage("  icon tex=" .. dbgVal(ic, "GetTexture") .. " " .. dbgVal(ic, "GetWidth") .. "x" .. dbgVal(ic, "GetHeight")
        .. " L=" .. dbgVal(ic, "GetLeft") .. " " .. dbgVal(ic, "GetDrawLayer") .. " parent=" .. dbgVal(ic, "GetParent")
        .. " sh=" .. dbgVal(ic, "IsShown") .. " src=" .. tostring(IchaUI_ApplyButtonForm_src))
    out:AddMessage("  portrait=" .. tostring(b._iconPortrait) .. " api=" .. tostring(SetPortraitToTexture ~= nil)
        .. " path=" .. tostring(b._iconPath) .. " drawn=" .. tostring(b._iconDrawn)
        .. " cdScale=" .. dbgVal(b.cooldown, "GetScale") .. " iconTint=" .. dbgTint(ic))
    out:AddMessage("  " .. IchaUI_SweepDebug(b) .. " model=" .. dbgVal(b.cooldown, "IsShown"))
    out:AddMessage("  maskPath=" .. tostring(formMaskPath) .. " rmOk=" .. tostring(b._rmOk) .. " imOk=" .. tostring(b._imOk))
    out:AddMessage("  iconMask.tex=" .. dbgFull(mt) .. " tint=" .. dbgTint(mt))
    out:AddMessage("  roundMask=" .. dbgFull(rm) .. " tint=" .. dbgTint(rm))
end

-- /iui maskdebug: button under the mouse, else the first four hero buttons.
function IchaUI_MaskDebug()
    local list = {}
    pcall(function()
        local f = GetMouseFocus and GetMouseFocus()
        local n = 0
        while f and n < 6 do
            if f.icon and f.GetName and f:GetName() and string.find(f:GetName(), "^IchaUIBtn") then
                table.insert(list, f)
                return
            end
            f = f.GetParent and f:GetParent()
            n = n + 1
        end
    end)
    if table.getn(list) < 1 then
        pcall(function()
            local ids = IchaUI_HeroButtonIds and IchaUI_HeroButtonIds()
            local i
            if ids then
                for i = 1, table.getn(ids) do
                    local b = getglobal("IchaUIBtn" .. tostring(ids[i]))
                    if b and table.getn(list) < 4 then table.insert(list, b) end
                end
            end
        end)
    end
    if table.getn(list) < 1 then
        DEFAULT_CHAT_FRAME:AddMessage("IchaUI maskdebug: no IchaUIBtn buttons found. src=" .. tostring(IchaUI_ApplyButtonForm_src))
        return
    end
    local i
    for i = 1, table.getn(list) do
        local b = list[i]
        if not pcall(function() dbgButton(b) end) then
            DEFAULT_CHAT_FRAME:AddMessage("IchaUI maskdebug: error reading " .. dbgVal(b, "GetName"))
        end
    end
end

-- Read/write for the edit-mode drawer popup (DrawerPop.lua). Same getters and
-- writers as IchaUI_DrawerStyleControls, so both write the same saved fields.
function IchaUI_DrawerStyleMeta(id)
    return info(id)
end

function IchaUI_DrawerStyleValue(id, field)
    if field == "strata" then return currentStrata(id) end
    if field == "text" then return currentText(id) end
    local row = IchaUI_DrawerStyleRow(id)
    if field == "cols" then
        if row and row.useCols and tonumber(row.cols) then return tonumber(row.cols) end
        local meta = info(id)
        return (meta and meta.cols) or 1
    end
    if field == "rows" then
        if row and tonumber(row.rows) then return tonumber(row.rows) end
        return 0
    end
    if field == "shape" then return (row and row.shape) or "circle" end
    return nil
end

function IchaUI_DrawerStyleWrite(id, field, value)
    if not id or id == "" then return end
    if field == "strataNext" then
        local idx = strataIndex(currentStrata(id), 3) + 1
        if idx > table.getn(STRATA) then idx = 1 end
        writeStrata(id, STRATA[idx])
    elseif field == "strata" then
        writeStrata(id, value)
    elseif field == "text" then
        writeText(id, value)
    elseif field == "cols" then
        writeCols(id, value)
    elseif field == "rows" then
        writeRows(id, value)
    elseif field == "shape" then
        local row = bag()[id]
        if type(row) ~= "table" then
            bag()[id] = {}
            row = bag()[id]
        end
        row.shape = value
        IchaUI_DrawerScaleApply(id)
    end
end
