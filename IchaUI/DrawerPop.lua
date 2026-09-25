-- Edit-mode drawer settings popup. In /icha move, right-click a drawer's mover,
-- its handle, or its Lock chip. Every control calls the same setter and writes
-- the same saved field as the Drawers / Map tab row for that drawer.
-- One popup at a time; its spot is saved in IchaUIDB.drawerPopPos.

local pop
local popId
local panes = {}
local seq = 0
local COL_W = 186
local ROW_H = 24
local TOP = -28

local TEXT_STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }

local function whiteFs(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local fp, fsz, fl = GameFontHighlightSmall:GetFont()
    if fp then fs:SetFont(fp, fsz or 10, fl or "") end
    fs:SetTextColor(1, 1, 1)
    if text then fs:SetText(text) end
    return fs
end

local function paintBox(f, alpha)
    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.09, alpha or 0.94)
    f:SetBackdropBorderColor(0.93, 0.78, 0.35, 1)
end

local function prettyDir(d)
    if d == "radial" then return "Radial" end
    if d == "right" then return "Right" end
    if d == "down" then return "Down" end
    if d == "left" then return "Left" end
    return "Up"
end

local function cycleDir(d)
    if d == "up" then return "right" end
    if d == "right" then return "down" end
    if d == "down" then return "left" end
    if d == "left" then return "radial" end
    return "up"
end

local function onOff(on)
    if on then return "On" end
    return "Off"
end

local function slider(label, lo, hi, step, get, set, show)
    return { kind = "slider", label = label, lo = lo, hi = hi, step = step, get = get, set = set, show = show }
end

-- choice (optional): function() -> opts, selected index, pick(i); makes the
-- row a dropdown instead of stepping through values.
local function cycle(text, click, show, choice)
    return { kind = "cycle", text = text, click = click, show = show, choice = choice }
end

local DIRS = { { "up", "Up" }, { "right", "Right" }, { "down", "Down" }, { "left", "Left" }, { "radial", "Radial" } }

local function idxOf(opts, v)
    local i
    for i = 1, table.getn(opts) do
        if opts[i][1] == v then return i end
    end
    return 0
end

local function shapeChoice(get, set)
    return function()
        local opts = IchaUI_FormShapeOpts and IchaUI_FormShapeOpts() or {}
        return opts, idxOf(opts, get() or "circle"), function(i) set(opts[i][1]) end
    end
end

-- Checkbox: a third of a row wide, so three sit side by side.
local function check(label, get, set)
    return { kind = "check", label = label, get = get, set = set }
end

-- Open direction plus the radial sliders, shown only while Open is Radial.
local function addDir(list, getDir, setDir, getS, setS, getA, setA, getR, setR)
    table.insert(list, cycle(function()
        return "Open: " .. prettyDir(getDir())
    end, function()
        setDir(cycleDir(getDir()))
    end, nil, function()
        return DIRS, idxOf(DIRS, getDir()), function(i) setDir(DIRS[i][1]) end
    end))
    local function radial() return getDir() == "radial" end
    table.insert(list, slider("Spread", 10, 360, 1, getS, setS, radial))
    table.insert(list, slider("Arc", 10, 360, 1, getA, setA, radial))
    table.insert(list, slider("Sh Rot", -360, 360, 1, getR, setR, radial))
end

-- Mirrors IchaUI_DrawerStyleControls (Strata, Text size, Icon, Popout, Shape, Columns/Rows).
local function addStyle(list, id, skipText, skipShape)
    if not IchaUI_DrawerStyleWrite or not IchaUI_DrawerStyleValue then return end
    table.insert(list, cycle(function()
        return "Strata: " .. tostring(IchaUI_DrawerStyleValue(id, "strata"))
    end, function()
        IchaUI_DrawerStyleWrite(id, "strataNext")
    end, nil, function()
        local opts = IchaUI_DrawerStrataOpts and IchaUI_DrawerStrataOpts() or {}
        return opts, idxOf(opts, IchaUI_DrawerStyleValue(id, "strata")), function(i)
            IchaUI_DrawerStyleWrite(id, "strata", opts[i][1])
        end
    end))
    if not skipText then
        table.insert(list, slider("Text size", 6, 28, 1, function()
            return IchaUI_DrawerStyleValue(id, "text")
        end, function(v)
            IchaUI_DrawerStyleWrite(id, "text", v)
        end))
    end
    table.insert(list, slider("Icon", 0.5, 2, 0.05, function()
        if IchaUI_DrawerButtonScale then return IchaUI_DrawerButtonScale(id) end
        return 1
    end, function(v)
        if IchaUI_DrawerButtonScaleSet then IchaUI_DrawerButtonScaleSet(id, v) end
    end))
    table.insert(list, slider("Popout", 0.5, 2, 0.05, function()
        if IchaUI_DrawerPopScale then return IchaUI_DrawerPopScale(id) end
        return 1
    end, function(v)
        if IchaUI_DrawerPopScaleSet then IchaUI_DrawerPopScaleSet(id, v) end
    end))
    if not skipShape then
        table.insert(list, cycle(function()
            local cur = IchaUI_DrawerStyleValue(id, "shape")
            if IchaUI_FormShapeLabel then cur = IchaUI_FormShapeLabel(cur) end
            return "Shape: " .. tostring(cur)
        end, function()
            local cur = IchaUI_DrawerStyleValue(id, "shape") or "circle"
            if IchaUI_FormShapeNext then cur = IchaUI_FormShapeNext(cur) else cur = "circle" end
            IchaUI_DrawerStyleWrite(id, "shape", cur)
        end, nil, shapeChoice(function()
            return IchaUI_DrawerStyleValue(id, "shape")
        end, function(v)
            IchaUI_DrawerStyleWrite(id, "shape", v)
        end)))
    end
    local meta = IchaUI_DrawerStyleMeta and IchaUI_DrawerStyleMeta(id)
    if meta and meta.grid then
        table.insert(list, slider("Columns", 1, 12, 1, function()
            return IchaUI_DrawerStyleValue(id, "cols")
        end, function(v)
            IchaUI_DrawerStyleWrite(id, "cols", v)
        end))
        table.insert(list, slider("Rows", 0, 20, 1, function()
            return IchaUI_DrawerStyleValue(id, "rows")
        end, function(v)
            IchaUI_DrawerStyleWrite(id, "rows", v)
        end))
    end
end

local function totemsList()
    if not IchaUITotems_Get or not IchaUITotems_Set then return nil end
    local function tget(k, d)
        return function()
            local t = IchaUITotems_Get()
            if t and t[k] ~= nil then return t[k] end
            return d
        end
    end
    local function tset(k)
        return function(v) IchaUITotems_Set(k, v) end
    end
    local list = {}
    table.insert(list, slider("Scale", 0.4, 3.0, 0.05, tget("scale", 1), tset("scale")))
    table.insert(list, slider("Size", 20, 80, 1, tget("size", 36), tset("size")))
    table.insert(list, slider("Gap", 0, 40, 0.5, tget("gap", 6), tset("gap")))
    table.insert(list, slider("Text", 8, 24, 1, tget("textSize", 11), tset("textSize")))
    table.insert(list, slider("Drawer", 14, 48, 1, tget("drawerSize", 22), tset("drawerSize")))
    table.insert(list, slider("D.Gap", 0, 12, 1, tget("drawerGap", 2), tset("drawerGap")))
    table.insert(list, slider("CD badge", 0.4, 1.5, 0.05, tget("cdBadgeScale", 0.85), tset("cdBadgeScale")))
    if IchaUI_GetTotemTextStrata and IchaUI_SetTotemTextStrata then
        table.insert(list, cycle(function()
            local _, idx = IchaUI_GetTotemTextStrata()
            return "T.strata: " .. (TEXT_STRATA[idx or 4] or "HIGH")
        end, function()
            local _, idx = IchaUI_GetTotemTextStrata()
            idx = (tonumber(idx) or 4) + 1
            if idx > 5 then idx = 1 end
            IchaUI_SetTotemTextStrata(idx)
        end, nil, function()
            local opts = {}
            local i
            for i = 1, table.getn(TEXT_STRATA) do table.insert(opts, { i, TEXT_STRATA[i] }) end
            local _, idx = IchaUI_GetTotemTextStrata()
            return opts, tonumber(idx) or 4, function(k) IchaUI_SetTotemTextStrata(k) end
        end))
    end
    table.insert(list, cycle(function()
        local t = IchaUITotems_Get()
        return "Shift drawers: " .. onOff(t and t.shiftDrawer)
    end, function()
        local t = IchaUITotems_Get()
        IchaUITotems_Set("shiftDrawer", not (t and t.shiftDrawer))
    end))
    addDir(list, tget("drawerDir", "up"), tset("drawerDir"),
        tget("drawerSpread", 90), tset("drawerSpread"),
        tget("drawerArc", 360), tset("drawerArc"),
        tget("drawerRot", 90), tset("drawerRot"))
    addStyle(list, "totems", true)
    return list
end

local function recallList()
    if not IchaUI_TotemRecallSet then return nil end
    local list = {}
    table.insert(list, cycle(function()
        return "Recall: " .. onOff(IchaUI_TotemRecallGet and IchaUI_TotemRecallGet())
    end, function()
        IchaUI_TotemRecallSet(not (IchaUI_TotemRecallGet and IchaUI_TotemRecallGet()))
    end))
    if IchaUI_TotemRecallDelaySet then
        table.insert(list, slider("Wait", 1, 30, 1, function()
            if IchaUI_TotemRecallDelay then return IchaUI_TotemRecallDelay() end
            return 5
        end, function(v) IchaUI_TotemRecallDelaySet(v) end))
    end
    if IchaUI_TotemRecallIcon_ScaleSet then
        table.insert(list, slider("Scale", 0.5, 2.5, 0.05, function()
            if IchaUI_TotemRecallIcon_Scale then return IchaUI_TotemRecallIcon_Scale() end
            return 1
        end, function(v) IchaUI_TotemRecallIcon_ScaleSet(v) end))
    end
    addStyle(list, "recall")
    return list
end

local function extrasList(which)
    if not IchaUIShamanExtras_SetDrawerDir then return nil end
    local list = {}
    if which == "utility" and IchaUIShamanExtras_UtilityEntries and IchaUIShamanExtras_SetUtilityShown then
        local keys = IchaUIShamanExtras_UtilityEntries()
        local i
        for i = 1, table.getn(keys) do
            local key = keys[i]
            table.insert(list, check(key, function()
                return IchaUIShamanExtras_GetUtilityShown(key)
            end, function(on)
                IchaUIShamanExtras_SetUtilityShown(key, on)
            end))
        end
    end
    addDir(list,
        function()
            if IchaUIShamanExtras_GetDrawerDir then return IchaUIShamanExtras_GetDrawerDir(which) end
            return "up"
        end,
        function(d) IchaUIShamanExtras_SetDrawerDir(which, d) end,
        function()
            if IchaUIShamanExtras_GetDrawerSpread then return IchaUIShamanExtras_GetDrawerSpread(which) end
            return 90
        end,
        function(v) if IchaUIShamanExtras_SetDrawerSpread then IchaUIShamanExtras_SetDrawerSpread(which, v) end end,
        function()
            if IchaUIShamanExtras_GetDrawerArc then return IchaUIShamanExtras_GetDrawerArc(which) end
            return 360
        end,
        function(v) if IchaUIShamanExtras_SetDrawerArc then IchaUIShamanExtras_SetDrawerArc(which, v) end end,
        function()
            if IchaUIShamanExtras_GetDrawerRot then return IchaUIShamanExtras_GetDrawerRot(which) end
            return 90
        end,
        function(v) if IchaUIShamanExtras_SetDrawerRot then IchaUIShamanExtras_SetDrawerRot(which, v) end end)
    if (which == "imbue" or which == "shield") and IchaUIShamanExtras_SetShowText then
        table.insert(list, cycle(function()
            return "Text: " .. onOff(IchaUIShamanExtras_GetShowText and IchaUIShamanExtras_GetShowText(which))
        end, function()
            local on = not (IchaUIShamanExtras_GetShowText and IchaUIShamanExtras_GetShowText(which))
            IchaUIShamanExtras_SetShowText(which, on)
        end))
    end
    addStyle(list, which)
    return list
end

local function resistsList()
    if not IchaUIUF_SetTankDrawerSide then return nil end
    local list = {}
    if IchaUIUF_SetTankDrawerEnabled and IchaUIUF_GetTankDrawerEnabled then
        table.insert(list, cycle(function()
            return "Mob stats: " .. onOff(IchaUIUF_GetTankDrawerEnabled())
        end, function()
            IchaUIUF_SetTankDrawerEnabled(not IchaUIUF_GetTankDrawerEnabled())
        end))
    end
    if IchaUIUF_SetTankDrawerMinimal and IchaUIUF_GetTankDrawerMinimal then
        table.insert(list, cycle(function()
            return "Minimal resists: " .. onOff(IchaUIUF_GetTankDrawerMinimal())
        end, function()
            IchaUIUF_SetTankDrawerMinimal(not IchaUIUF_GetTankDrawerMinimal())
        end))
    end
    addDir(list,
        function()
            if IchaUIUF_GetTankDrawerSide then return IchaUIUF_GetTankDrawerSide() end
            return "left"
        end,
        function(d) IchaUIUF_SetTankDrawerSide(d) end,
        function()
            if IchaUIUF_GetTankDrawerSpread then return IchaUIUF_GetTankDrawerSpread() end
            return 90
        end,
        function(v) if IchaUIUF_SetTankDrawerSpread then IchaUIUF_SetTankDrawerSpread(v) end end,
        function()
            if IchaUIUF_GetTankDrawerArc then return IchaUIUF_GetTankDrawerArc() end
            return 360
        end,
        function(v) if IchaUIUF_SetTankDrawerArc then IchaUIUF_SetTankDrawerArc(v) end end,
        function()
            if IchaUIUF_GetTankDrawerRot then return IchaUIUF_GetTankDrawerRot() end
            return 90
        end,
        function(v) if IchaUIUF_SetTankDrawerRot then IchaUIUF_SetTankDrawerRot(v) end end)
    addStyle(list, "resists")
    return list
end

local function minimapList()
    if not IchaUIMinimap_SetDrawer or not IchaUIMinimap_GetDrawer then return nil end
    local function mget(k, d)
        return function()
            local g = IchaUIMinimap_GetDrawer()
            if g and g[k] ~= nil then return g[k] end
            return d
        end
    end
    local function mset(k)
        return function(v) IchaUIMinimap_SetDrawer(k, v) end
    end
    local list = {}
    table.insert(list, cycle(function()
        local g = IchaUIMinimap_GetDrawer()
        return "Drawer: " .. onOff(g and g.enabled)
    end, function()
        local g = IchaUIMinimap_GetDrawer()
        IchaUIMinimap_SetDrawer("enabled", not (g and g.enabled))
    end))
    addDir(list, mget("drawerDir", "down"), mset("drawerDir"),
        mget("drawerSpread", 90), mset("drawerSpread"),
        mget("drawerArc", 360), mset("drawerArc"),
        mget("drawerRot", 90), mset("drawerRot"))
    addStyle(list, "minimap")
    return list
end

local function customRec(rid)
    local list = IchaUIDB and IchaUIDB.customDrawers
    if type(list) ~= "table" then return nil end
    local i
    for i = 1, table.getn(list) do
        if list[i] and list[i].id == rid then return list[i] end
    end
    return nil
end

-- Same record fields the Custom drawers rows write (shape, dir, spread, arc,
-- rot, showTitle, labelPos, cols/rows/useCols) plus the cd:<id> style row.
local function customList(sid)
    if not IchaUI_CustomDrawers_ApplyStyle then return nil end
    local rid = string.sub(sid, 4)
    if not customRec(rid) then return nil end
    local function live() return customRec(rid) end
    local function refresh() IchaUI_CustomDrawers_ApplyStyle(sid) end
    local function dir()
        local rec = live()
        local d = rec and rec.dir
        if d == "down" or d == "left" or d == "right" or d == "radial" then return d end
        return "up"
    end
    local function put(k, v)
        local rec = live()
        if not rec then return end
        rec[k] = v
        refresh()
    end
    local list = {}
    table.insert(list, cycle(function()
        local rec = live()
        local cur = (rec and rec.shape) or "circle"
        if IchaUI_FormShapeLabel then cur = IchaUI_FormShapeLabel(cur) end
        return "Shape: " .. tostring(cur)
    end, function()
        local rec = live()
        if not rec then return end
        if IchaUI_FormShapeNext then
            put("shape", IchaUI_FormShapeNext(rec.shape or "circle"))
        end
    end, nil, shapeChoice(function()
        local rec = live()
        return rec and rec.shape
    end, function(v) put("shape", v) end)))
    addDir(list, dir, function(d) put("dir", d) end,
        function()
            local rec = live()
            if IchaUI_DrawerNormSpread then return IchaUI_DrawerNormSpread(rec and rec.spread) end
            return 90
        end,
        function(v)
            if IchaUI_DrawerNormSpread then v = IchaUI_DrawerNormSpread(v) end
            put("spread", v)
        end,
        function()
            local rec = live()
            if IchaUI_DrawerNormArc then return IchaUI_DrawerNormArc(rec and rec.arc) end
            return 360
        end,
        function(v) put("arc", math.floor((tonumber(v) or 360) + 0.5)) end,
        function()
            local rec = live()
            if IchaUI_DrawerNormRot then return IchaUI_DrawerNormRot(rec and rec.rot) end
            return 90
        end,
        function(v) put("rot", math.floor((tonumber(v) or 90) + 0.5)) end)
    table.insert(list, cycle(function()
        local rec = live()
        if rec and rec.showTitle == false then return "Title: Hide" end
        return "Title: Show"
    end, function()
        local rec = live()
        if not rec then return end
        put("showTitle", rec.showTitle == false)
    end))
    table.insert(list, cycle(function()
        local rec = live()
        if rec and rec.labelPos == "top" then return "Label: Top" end
        return "Label: Bottom"
    end, function()
        local rec = live()
        if not rec then return end
        if rec.labelPos == "top" then put("labelPos", "bottom") else put("labelPos", "top") end
    end))
    table.insert(list, slider("Cols", 1, 12, 1, function()
        local rec = live()
        return math.floor(tonumber(rec and rec.cols) or 1)
    end, function(v)
        local rec = live()
        if not rec then return end
        rec.cols = math.floor(v + 0.5)
        rec.useCols = true
        refresh()
    end))
    table.insert(list, slider("Rows", 0, 20, 1, function()
        local rec = live()
        return math.floor(tonumber(rec and rec.rows) or 0)
    end, function(v)
        local rec = live()
        if not rec then return end
        local n = math.floor(v + 0.5)
        rec.rows = n
        if n >= 1 then rec.useCols = nil else rec.useCols = true end
        refresh()
    end))
    addStyle(list, sid, false, true)
    return list
end

local function controlList(id)
    if (id == "totems" or id == "recall" or id == "utility" or id == "imbue" or id == "shield")
        and not IchaUI_IsShaman() then
        return nil
    end
    if id == "totems" then return totemsList() end
    if id == "recall" then return recallList() end
    if id == "utility" or id == "imbue" or id == "shield" then return extrasList(id) end
    if id == "resists" then return resistsList() end
    if id == "minimap" then return minimapList() end
    if string.sub(id, 1, 3) == "cd:" then return customList(id) end
    return nil
end

local function titleFor(id)
    if string.sub(id, 1, 3) == "cd:" then
        local rec = customRec(string.sub(id, 4))
        return (rec and rec.name) or "Drawer"
    end
    local meta = IchaUI_DrawerStyleMeta and IchaUI_DrawerStyleMeta(id)
    return (meta and meta.label) or id
end

local function fmtVal(step, v)
    if step < 1 then return string.format("%.2f", v) end
    return tostring(math.floor(v + 0.5))
end

-- Each row is 6 slots: sliders / cycles take 3 (two per row), checks take 2.
local SLOT_W = (COL_W * 2 + 8) / 6

local function layout(pane)
    local slot = 0
    local row = 0
    local i
    for i = 1, table.getn(pane.ctl) do
        local c = pane.ctl[i]
        local show = c.spec.show
        if (not show) or show() then
            local span = 3
            if c.spec.kind == "check" then span = 2 end
            if span == 3 and slot > 0 and slot < 3 then slot = 3 end
            if slot + span > 6 then
                row = row + 1
                slot = 0
            end
            local dy = 0
            if c.spec.kind == "cycle" then dy = -3 end
            local x = math.floor(slot * SLOT_W + 0.5)
            if span == 3 then x = (slot / 3) * (COL_W + 8) end
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", pop, "TOPLEFT", 10 + x, TOP - row * ROW_H + dy)
            c:Show()
            slot = slot + span
        else
            c:Hide()
        end
    end
    local rows = row
    if slot > 0 then rows = row + 1 end
    pop:SetHeight(-TOP + rows * ROW_H + 8)
end

local function repaint(except)
    local pane = popId and panes[popId]
    if not pane or not pop then return end
    pop.skip = true
    local i
    for i = 1, table.getn(pane.ctl) do
        local c = pane.ctl[i]
        if c ~= except and c.paint then c.paint() end
    end
    pop.skip = nil
    layout(pane)
end

local function makeSlider(pane, spec)
    seq = seq + 1
    local name = "IchaUIDrawerPopSlider" .. seq
    local cell = CreateFrame("Frame", nil, pane)
    cell:SetWidth(COL_W)
    cell:SetHeight(ROW_H)
    local cap = whiteFs(cell, spec.label)
    cap:SetPoint("LEFT", cell, "LEFT", 0, 0)
    cap:SetWidth(52)
    cap:SetJustifyH("LEFT")
    local sl = CreateFrame("Slider", name, cell, "OptionsSliderTemplate")
    sl:SetPoint("LEFT", cell, "LEFT", 54, 0)
    sl:SetWidth(96)
    sl:SetHeight(16)
    sl:SetMinMaxValues(spec.lo, spec.hi)
    sl:SetValueStep(spec.step)
    local low = getglobal(name .. "Low")
    local high = getglobal(name .. "High")
    local mid = getglobal(name .. "Text")
    if low then low:SetText("") end
    if high then high:SetText("") end
    if mid then mid:SetText("") end
    local vt = whiteFs(cell)
    vt:SetPoint("LEFT", sl, "RIGHT", 4, 0)
    sl:SetScript("OnValueChanged", function()
        if pop.skip then return end
        local v = this:GetValue() or spec.lo
        if spec.step >= 1 then v = math.floor(v + 0.5) end
        vt:SetText(fmtVal(spec.step, v))
        spec.set(v)
        repaint(cell)
    end)
    cell.paint = function()
        local v = tonumber(spec.get()) or spec.lo
        if v < spec.lo then v = spec.lo end
        if v > spec.hi then v = spec.hi end
        sl:SetValue(v)
        vt:SetText(fmtVal(spec.step, v))
    end
    return cell
end

local function makeCycle(pane, spec)
    local b = CreateFrame("Button", nil, pane)
    b:SetWidth(COL_W - 8)
    b:SetHeight(18)
    paintBox(b, 0.9)
    local fs = whiteFs(b)
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    if spec.choice and IchaUI_ChoiceMenu then
        b._label = fs
        if IchaUI_ChoiceArrow then IchaUI_ChoiceArrow(b) end
        b:SetScript("OnClick", function()
            local opts, cur, pick = spec.choice()
            IchaUI_ChoiceMenu(this, opts, cur, function(i)
                pick(i)
                repaint(nil)
            end)
        end)
    else
        b:SetScript("OnClick", function()
            spec.click()
            repaint(nil)
        end)
    end
    b.paint = function()
        fs:SetText(spec.text())
    end
    return b
end

local function makeCheck(pane, spec)
    local cell = CreateFrame("Frame", nil, pane)
    cell:SetWidth(math.floor(SLOT_W * 2) - 4)
    cell:SetHeight(ROW_H)
    local cb = CreateFrame("CheckButton", nil, cell)
    cb:SetWidth(20)
    cb:SetHeight(20)
    cb:SetPoint("LEFT", cell, "LEFT", 0, 0)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    local fs = whiteFs(cell, spec.label)
    fs:SetPoint("LEFT", cb, "RIGHT", 1, 0)
    fs:SetWidth(math.floor(SLOT_W * 2) - 26)
    fs:SetJustifyH("LEFT")
    cb:SetScript("OnClick", function()
        spec.set(this:GetChecked() and true or false)
        repaint(nil)
    end)
    cell.paint = function()
        cb:SetChecked(spec.get() and 1 or nil)
    end
    return cell
end

local function buildPane(list)
    local pane = CreateFrame("Frame", nil, pop)
    pane:SetAllPoints(pop)
    pane.ctl = {}
    local i
    for i = 1, table.getn(list) do
        local spec = list[i]
        local c
        if spec.kind == "slider" then
            c = makeSlider(pane, spec)
        elseif spec.kind == "check" then
            c = makeCheck(pane, spec)
        else
            c = makeCycle(pane, spec)
        end
        c.spec = spec
        table.insert(pane.ctl, c)
    end
    return pane
end

local function savePos()
    if not pop or not pop.GetLeft then return end
    if not IchaUIDB then IchaUIDB = {} end
    local x = pop:GetLeft()
    local y = pop:GetTop()
    if not x or not y then return end
    local ux = UIParent:GetLeft() or 0
    local uy = UIParent:GetTop() or 0
    IchaUIDB.drawerPopPos = { x = x - ux, y = y - uy }
end

local function placePop()
    if not pop or pop.placed then return end
    pop:ClearAllPoints()
    local pos = IchaUIDB and IchaUIDB.drawerPopPos
    if pos and pos.x and pos.y then
        pop:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos.x, pos.y)
        pop.placed = true
        return
    end
    local cx, cy = 0, 0
    if GetCursorPosition then cx, cy = GetCursorPosition() end
    local scale = UIParent:GetEffectiveScale() or 1
    if scale < 0.01 then scale = 1 end
    cx = cx / scale
    cy = cy / scale
    local pw = pop:GetWidth() or 400
    local ph = pop:GetHeight() or 200
    local sw = UIParent:GetWidth() or 0
    local sh = UIParent:GetHeight() or 0
    local x = cx + 12
    if x + pw > sw then x = sw - pw - 8 end
    if x < 0 then x = 0 end
    local top = cy + 8
    if top > sh then top = sh - 8 end
    if top < ph then top = ph end
    pop:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, top - sh)
    pop.placed = true
    savePos()
end

local function ensurePop()
    if pop then return pop end
    pop = CreateFrame("Frame", "IchaUIDrawerPop", UIParent)
    pop:SetWidth(10 + COL_W * 2 + 8 + 10)
    pop:SetHeight(120)
    pop:SetFrameStrata("TOOLTIP")
    pop:SetFrameLevel(220)
    paintBox(pop, 0.94)
    pop:EnableMouse(true)
    pop:SetMovable(true)
    if pop.SetClampedToScreen then pop:SetClampedToScreen(true) end
    pop:RegisterForDrag("LeftButton")
    pop:SetScript("OnDragStart", function() this:StartMoving() end)
    pop:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        savePos()
    end)
    local title = pop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", pop, "TOPLEFT", 10, -9)
    if IchaUI_PaintGoldFont then
        IchaUI_PaintGoldFont(title, 0.93, 0.78, 0.35)
    else
        title:SetTextColor(0.93, 0.78, 0.35)
    end
    pop.title = title
    local close = CreateFrame("Button", nil, pop, "UIPanelCloseButton")
    close:SetWidth(24)
    close:SetHeight(24)
    close:SetPoint("TOPRIGHT", pop, "TOPRIGHT", 2, 2)
    close:SetFrameLevel(pop:GetFrameLevel() + 5)
    close:SetScript("OnClick", function() IchaUI_HideDrawerPop() end)
    pop:Hide()
    return pop
end

function IchaUI_HideDrawerPop()
    if pop then pop:Hide() end
    popId = nil
end

function IchaUI_DrawerPopShown()
    return pop and pop:IsShown() and true or false
end

function IchaUI_ShowDrawerPop(id)
    if type(id) ~= "string" or id == "" then return false end
    local pane = panes[id]
    if not pane then
        local list = controlList(id)
        if not list or table.getn(list) < 1 then return false end
        ensurePop()
        pane = buildPane(list)
        panes[id] = pane
    end
    if IchaUI_HideActionGridPop then IchaUI_HideActionGridPop() end
    local k, p
    for k, p in pairs(panes) do
        if p ~= pane then p:Hide() end
    end
    popId = id
    pop.title:SetText(titleFor(id))
    pane:Show()
    repaint(nil)
    placePop()
    pop:Show()
    return true
end

-- Right-click hook for drawer handles. True only in position edit mode; the
-- caller keeps its normal right-click behavior when this returns false.
function IchaUI_DrawerEditClick(id)
    if not IchaUI_EditModeActive or not IchaUI_EditModeActive() then return false end
    return IchaUI_ShowDrawerPop(id) and true or false
end

-- Edit-mode entry ids (Positions.lua) to drawer ids.
function IchaUI_DrawerIdForEntry(eid)
    if type(eid) ~= "string" then return nil end
    if eid == "totems" or eid == "recall" or eid == "utility" or eid == "imbue" or eid == "shield" then
        return eid
    end
    if eid == "minimap" or eid == "mmicons" then return "minimap" end
    if string.sub(eid, 1, 2) == "cd" then return "cd:" .. string.sub(eid, 3) end
    return nil
end
