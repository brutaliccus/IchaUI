-- Drawer popup dock rows, and custom-drawer Alt / edit-mode config clicks.
--   lua5.1 tools/test_drawer_dock_opts.lua
local fails = 0
local function check(cond, msg)
    if not cond then
        fails = fails + 1
        io.stderr:write("FAIL: " .. msg .. "\n")
    end
end

local all = {}
local function noop() end
local proto = {}
function proto:SetWidth(w) self.w = w end
function proto:SetHeight(h) self.h = h end
function proto:GetWidth() return self.w end
function proto:GetHeight() return self.h end
function proto:SetPoint() end
function proto:ClearAllPoints() end
function proto:SetFrameStrata() end
function proto:SetFrameLevel(n) self.level = n end
function proto:GetFrameLevel() return self.level or 1 end
function proto:EnableMouse() end
function proto:SetMovable() end
function proto:SetClampedToScreen() end
function proto:RegisterForDrag() end
function proto:RegisterForClicks() end
function proto:EnableMouseWheel() end
function proto:SetBackdrop() end
function proto:SetBackdropColor() end
function proto:SetBackdropBorderColor() end
function proto:SetTextColor() end
function proto:SetFont() end
function proto:GetFont() return "Fonts\\FRIZQT__.TTF", 10, "" end
function proto:SetJustifyH() end
function proto:SetAllPoints() end
function proto:SetMinMaxValues(lo, hi) self.lo, self.hi = lo, hi end
function proto:SetValueStep() end
function proto:SetValue(v)
    self.value = v
    local fn = self.scripts and self.scripts.OnValueChanged
    if not fn then return end
    local old = this
    this = self
    fn()
    this = old
end
function proto:GetValue() return self.value end
function proto:SetScale() end
function proto:GetEffectiveScale() return 1 end
function proto:GetLeft() return nil end
function proto:GetTop() return nil end
function proto:GetCenter() return 0, 0 end
function proto:IsShown() return self.shown ~= false end
function proto:Show() self.shown = true end
function proto:Hide() self.shown = false end
function proto:SetScript(ev, fn)
    self.scripts = self.scripts or {}
    self.scripts[ev] = fn
end
function proto:GetScript(ev)
    return self.scripts and self.scripts[ev]
end
function proto:SetText(t)
    self.text = t
    if self.owner then
        self.owner.texts = self.owner.texts or {}
        table.insert(self.owner.texts, tostring(t))
        self.owner.lastText = t
    end
end
function proto:CreateFontString()
    local fs = newFrame()
    fs.owner = self
    return fs
end
function proto:CreateTexture()
    return newFrame()
end
function proto:GetRegions() return nil end
function proto:GetObjectType() return "Frame" end
function proto:GetName() return self.name end

local mt = { __index = proto }
setmetatable(proto, { __index = function(_, k)
    if type(k) ~= "string" then return nil end
    local p3 = string.sub(k, 1, 3)
    if p3 == "Set" or p3 == "Get" or p3 == "IsV" or p3 == "IsS" then return noop end
    if string.sub(k, 1, 6) == "Enable" or string.sub(k, 1, 8) == "Register" then return noop end
    if k == "Hide" or k == "Show" or k == "ClearAllPoints" or k == "StartMoving"
        or k == "StopMovingOrSizing" or k == "CreateFontString" or k == "CreateTexture" then
        return noop
    end
    return nil
end })

function newFrame()
    local f = {}
    setmetatable(f, mt)
    table.insert(all, f)
    return f
end

function CreateFrame(kind, name, parent)
    local f = newFrame()
    f.kind = kind
    f.name = name
    f.parent = parent
    if name and name ~= "" then _G[name] = f end
    return f
end

function getglobal(name)
    return _G[name] or newFrame()
end

local font = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 10, "" end }
GameFontHighlightSmall = font
GameFontHighlight = font
GameFontNormal = font
GameFontNormalSmall = font
UIParent = newFrame()
UIParent.GetEffectiveScale = function() return 1 end
UIParent.GetWidth = function() return 800 end
UIParent.GetHeight = function() return 600 end
UIParent.GetLeft = function() return 0 end
UIParent.GetTop = function() return 600 end
function GetTime() return 0 end
IchaUI_PaintGoldBorder = noop
IchaUI_PaintGoldFont = noop
IchaUI_PaintGoldRing = noop
IchaUI_PaintGoldLightBorder = noop

local popOk, popErr = pcall(dofile, "IchaUI/DrawerPop.lua")
check(popOk, "load DrawerPop.lua: " .. tostring(popErr))

IchaUIDB = {
    customDrawers = {
        { id = "pots", name = "Pots", shape = "circle", dir = "up", x = 0, y = 0, entries = {} },
    },
}
function IchaUI_IsShaman() return true end
function IchaUI_CustomDrawers_ApplyStyle() end

local dock = {}
local sets = {}
local clears = {}
function IchaUI_DrawerDockGet(id) return dock[id] end
function IchaUI_DrawerDockSet(id, fields)
    if type(fields) ~= "table" then
        table.insert(sets, { id, fields, nil, "wipe" })
        dock[id] = nil
        return
    end
    if type(dock[id]) ~= "table" then dock[id] = {} end
    local k, v
    for k, v in pairs(fields) do
        table.insert(sets, { id, k, v })
        dock[id][k] = v
    end
end
function IchaUI_DrawerDockClear(id)
    table.insert(clears, id)
    dock[id] = { mode = "free" }
end
function IchaUI_DrawerDockModeOpts()
    return { { "free", "Free" }, { "frame", "Frame" }, { "portrait", "Portrait" } }
end
function IchaUI_DrawerDockParentOpts()
    return { { "PlayerFrame", "Player" }, { "UIParent", "UIParent" } }
end
function IchaUI_DrawerDockPortraitOpts()
    return { { "player", "Player" }, { "target", "Target" } }
end

local captured
IchaUI_ChoiceMenu = function(anchor, menuOpts, cur, onPick)
    captured = { opts = menuOpts, cur = cur, onPick = onPick, anchor = anchor }
end

local function popCell(fragment)
    local found
    local n, f
    for n, f in ipairs(all) do
        if f.lastText and string.find(f.lastText, fragment, 1, true) and f.scripts and f.scripts.OnClick then
            found = f
        end
    end
    return found
end

local function cellShown(fragment)
    local found
    local n, f
    for n, f in ipairs(all) do
        if (f.shown == true or f.shown == false) and f.texts then
            local j, t
            for j, t in ipairs(f.texts) do
                if string.find(t, fragment, 1, true) then found = f.shown end
            end
        end
    end
    return found
end

local function dockButtons()
    local c = 0
    local n, f
    for n, f in ipairs(all) do
        if f.lastText and string.sub(f.lastText, 1, 6) == "Dock: " and f.scripts and f.scripts.OnClick then
            c = c + 1
        end
    end
    return c
end

dock["cd:pots"] = { mode = "portrait", unit = "player", angle = 90, ox = 4, oy = -2,
    parent = "PlayerFrame", point = "TOPLEFT", relPoint = "CENTER", x = 20, y = -6 }
check(IchaUI_ShowDrawerPop("cd:pots") == true, "custom drawer popup opens")
check(IchaUIDrawerPop and IchaUIDrawerPop.title and IchaUIDrawerPop.title.text == "Pots", "popup title is the drawer name")
check(popCell("Dock: ") and popCell("Dock: ").lastText == "Dock: Portrait", "popup dock mode is Portrait")
check(popCell("Parent: ") and popCell("Parent: ").shown == false, "popup hides parent while portrait-docked")
check(popCell("Unit: ") and popCell("Unit: ").shown == true and popCell("Unit: ").lastText == "Unit: Player",
    "popup shows the portrait unit")
check(cellShown("Angle") == true, "popup shows angle while portrait-docked")
check(cellShown("Dock X") == false, "popup hides frame offsets while portrait-docked")

local dockBtn = popCell("Dock: ")
this = dockBtn
dockBtn.scripts.OnClick()
check(captured and captured.opts and captured.opts[3] and captured.opts[3][1] == "portrait", "popup mode menu offers portrait")
local frameIdx, i
for i = 1, table.getn(captured.opts) do
    if captured.opts[i][1] == "frame" then frameIdx = i end
end
captured.onPick(frameIdx)
check(dock["cd:pots"].mode == "frame", "picking Frame writes mode through DrawerDockSet")
check(popCell("Parent: ") and popCell("Parent: ").shown == true, "popup shows parent after switching to frame")
check(popCell("Unit: ") and popCell("Unit: ").shown == false, "popup hides unit after switching to frame")
check(popCell("Point: ") and popCell("Point: ").lastText == "Point: Top Left", "popup point label")

local clearPop = popCell("Clear dock")
check(clearPop ~= nil, "popup has Clear dock")
this = clearPop
clearPop.scripts.OnClick()
check(clears[table.getn(clears)] == "cd:pots", "popup Clear dock uses the cd: id")
check(popCell("Dock: ") and popCell("Dock: ").lastText == "Dock: Free", "popup returns to Free after clear")
check(popCell("Parent: ").shown == false and popCell("Unit: ").shown == false, "popup hides dock fields after clear")

function IchaUITotems_Get() return {} end
function IchaUITotems_Set() end
function IchaUI_TotemRecallSet() end
function IchaUIShamanExtras_SetDrawerDir() end
function IchaUIUF_SetTankDrawerSide() end
function IchaUIMinimap_GetDrawer() return {} end
function IchaUIMinimap_SetDrawer() end

local ids = { "totems", "recall", "utility", "imbue", "shield", "resists", "minimap" }
local before = dockButtons()
for i = 1, table.getn(ids) do
    local id = ids[i]
    check(IchaUI_ShowDrawerPop(id) == true, "popup opens for " .. id)
    check(dockButtons() == before + i, id .. " popup has dock controls")
end

IchaUIDB.customDrawers[2] = { id = "bare", name = "Bare", shape = "circle", dir = "up" }
dock["cd:pots"] = { mode = "portrait", unit = "player", angle = 1, ox = 0, oy = 0,
    parent = "PlayerFrame", point = "TOP", relPoint = "TOP", x = 3, y = 4 }
dock["cd:bare"] = { mode = "frame", parent = "UIParent", point = "LEFT", relPoint = "RIGHT", x = 8, y = 9 }
check(IchaUI_ShowDrawerPop("cd:bare") == true, "second custom drawer popup opens on its own id")
check(popCell("Dock: ") and popCell("Dock: ").lastText == "Dock: Frame", "bare popup shows its own Frame dock")
local barePop = popCell("Dock: ")
captured = nil
this = barePop
barePop.scripts.OnClick()
local portraitIdx, pi
for pi = 1, table.getn(captured.opts) do
    if captured.opts[pi][1] == "portrait" then portraitIdx = pi end
end
captured.onPick(portraitIdx)
check(dock["cd:bare"].mode == "portrait", "bare popup writes drawerDock[cd:bare]")
check(dock["cd:pots"].mode == "portrait" and dock["cd:pots"].x == 3, "pots dock row is not overwritten")
check(sets[table.getn(sets)][1] == "cd:bare", "bare popup Set uses cd:bare")
check(dock["custom"] == nil and dock["cd"] == nil and dock.pots == nil and dock.bare == nil,
    "popup does not write a shared or bare dock key")

local savedDockGet, savedDockSet = IchaUI_DrawerDockGet, IchaUI_DrawerDockSet
IchaUI_DrawerDockGet = nil
IchaUI_DrawerDockSet = nil
IchaUIDB.customDrawers[3] = { id = "nodock", name = "No dock", shape = "circle", dir = "up" }
local docksBeforeBare = dockButtons()
check(IchaUI_ShowDrawerPop("cd:nodock") == true, "popup still opens when DrawerDock is absent")
check(dockButtons() == docksBeforeBare, "missing DrawerDock omits dock rows")
table.remove(IchaUIDB.customDrawers, 3)

local cdOk, cdErr = pcall(dofile, "IchaUI_CustomDrawers/CustomDrawers.lua")
check(cdOk, "load CustomDrawers.lua: " .. tostring(cdErr))
if cdOk then
    local opened = {}
    IchaUI_ShowDrawerPop = function(id)
        table.insert(opened, id)
        return true
    end
    local applyOk, applyErr = pcall(IchaUI_CustomDrawers_Apply)
    check(applyOk, "apply custom drawers: " .. tostring(applyErr))
    local btn = IchaUICustomDrawerpots
    check(btn and btn.scripts and btn.scripts.OnMouseUp, "custom drawer handle has a mouse-up script")
    if btn and btn.scripts and btn.scripts.OnMouseUp then
        local altOn, editOn = false, false
        local configured = {}
        local editClicks = {}
        function IsAltKeyDown() return altOn end
        function IchaUI_EditModeActive() return editOn end
        function IchaUI_DrawerConfigClick(id)
            table.insert(configured, id)
            return true
        end
        function IchaUI_DrawerEditClick(id)
            table.insert(editClicks, id)
            return true
        end
        local function click(button)
            arg1 = button
            this = btn
            btn.scripts.OnMouseUp()
        end
        click("RightButton")
        check(table.getn(configured) == 0 and table.getn(opened) == 0 and table.getn(editClicks) == 0,
            "plain right-click outside edit mode does not open config")
        altOn = true
        click("RightButton")
        check(table.getn(configured) == 1 and configured[1] == "cd:pots" and table.getn(opened) == 0,
            "Alt+right-click uses DrawerConfigClick outside edit mode")
        altOn = false
        editOn = true
        click("RightButton")
        check(table.getn(configured) == 2 and configured[2] == "cd:pots" and table.getn(opened) == 0,
            "plain right-click in edit mode uses DrawerConfigClick")
        click("LeftButton")
        check(table.getn(configured) == 2 and table.getn(opened) == 0, "left-click does not open config")
        check(table.getn(editClicks) == 0, "DrawerEditClick is not used")
        IchaUI_DrawerConfigClick = nil
        altOn = true
        editOn = false
        click("RightButton")
        check(table.getn(opened) == 1 and opened[1] == "cd:pots", "Alt+right-click falls back to ShowDrawerPop")
        altOn = false
        click("RightButton")
        check(table.getn(opened) == 1, "plain right-click still does not open config without DrawerConfigClick")
    end

    IchaUI_DrawerDockGet = savedDockGet
    IchaUI_DrawerDockSet = savedDockSet
    dock["cd:pots"] = { mode = "portrait", unit = "player", angle = 90, ox = 4, oy = -2,
        parent = "PlayerFrame", point = "TOPLEFT", relPoint = "CENTER", x = 20, y = -6 }
    dock["cd:bare"] = { mode = "frame", parent = "UIParent", point = "LEFT", relPoint = "RIGHT", x = 8, y = 9 }
    local page = CreateFrame("Frame", "IchaUIOptPage", UIParent)
    page:SetWidth(560)
    page:SetHeight(40)
    local optOk, optErr = pcall(IchaUI_BuildCustomDrawerOptions, page, -4, 10)
    check(optOk, "build custom drawer options: " .. tostring(optErr))

    local function under(f, root)
        local g, guard = f, 0
        while g and guard < 16 do
            if g == root then return true end
            g = g.parent
            guard = guard + 1
        end
        return false
    end
    local function labeledUnder(root, fragment, wantClick)
        local found
        local n, f
        for n, f in ipairs(all) do
            if under(f, root) and f.lastText and string.find(f.lastText, fragment, 1, true) then
                if not wantClick or (f.scripts and f.scripts.OnClick) then found = f end
            end
        end
        return found
    end
    local function countDock(root)
        local c, n, f = 0
        for n, f in ipairs(all) do
            if under(f, root) and f.lastText and string.sub(f.lastText, 1, 6) == "Dock: "
                and f.scripts and f.scripts.OnClick then
                c = c + 1
            end
        end
        return c
    end

    local function anyShown(fragment)
        local n, f
        for n, f in ipairs(all) do
            if under(f, page) and f.shown ~= false and f.lastText and string.find(f.lastText, fragment, 1, true) then
                return true
            end
        end
        return false
    end
    local function siblingClick(modeText, label)
        local modeBtn = labeledUnder(page, modeText, true)
        if not modeBtn then return nil end
        local n, f
        for n, f in ipairs(all) do
            if f.parent == modeBtn.parent and f.lastText == label and f.scripts and f.scripts.OnClick then
                return f
            end
        end
        return nil
    end

    local function blockOf(btn)
        if btn and btn.parent then return btn.parent.parent end
    end
    local function shownIn(block, text)
        if not block then return nil end
        local n, f
        for n, f in ipairs(all) do
            if under(f, block) and f.shown ~= false and f.lastText and string.find(f.lastText, text, 1, true) then
                return f
            end
        end
    end
    local function clearOf(modeBtn)
        if not modeBtn then return nil end
        local n, f
        for n, f in ipairs(all) do
            if f.parent == modeBtn.parent and f.lastText == "Clear dock" and f.scripts and f.scripts.OnClick then
                return f
            end
        end
    end

    check(countDock(page) == 2, "each existing custom drawer row has dock controls")
    local potsDock = labeledUnder(page, "Dock: Portrait", true)
    local bareDockBtn = labeledUnder(page, "Dock: Frame", true)
    local potsBlock = blockOf(potsDock)
    local bareBlock = blockOf(bareDockBtn)
    check(potsDock ~= nil, "portrait-docked drawer shows Dock: Portrait on its row")
    check(shownIn(potsBlock, "Unit: Player") ~= nil, "portrait row shows the unit control")
    check(shownIn(potsBlock, "Angle") ~= nil, "portrait row shows angle")
    check(shownIn(potsBlock, "Parent: ") == nil, "portrait row hides the frame parent")
    check(shownIn(potsBlock, "Dock X") == nil, "portrait row hides frame offsets")
    check(shownIn(bareBlock, "Parent: UIParent") ~= nil, "frame row shows its own parent")
    check(shownIn(bareBlock, "Unit: ") == nil, "frame row hides portrait unit")

    captured = nil
    this = potsDock
    potsDock.scripts.OnClick()
    check(captured and captured.opts and captured.opts[2] and captured.opts[2][1] == "frame",
        "row dock mode menu offers frame")
    captured.onPick(2)
    check(dock["cd:pots"].mode == "frame", "row dock mode writes through DrawerDockSet")
    check(dock["cd:bare"].mode == "frame" and dock["cd:bare"].x == 8, "switching pots does not write the bare dock row")
    check(shownIn(potsBlock, "Parent: Player") ~= nil, "pots frame row shows parent")
    check(shownIn(potsBlock, "Unit: ") == nil, "pots frame row hides unit")
    local xCell = shownIn(potsBlock, "Dock X")
    local xSlider
    local n, f
    for n, f in ipairs(all) do
        if f.parent == xCell and f.kind == "Slider" then xSlider = f end
    end
    check(xSlider ~= nil, "pots frame row has its own Dock X slider")
    if xSlider then
        xSlider:SetValue(33)
        check(dock["cd:pots"].x == 33, "Dock X writes cd:pots")
        check(dock["cd:bare"].x == 8, "Dock X on pots does not write cd:bare")
    end
    local clearRow = clearOf(potsDock)
    check(clearRow ~= nil, "row has Clear dock")
    this = clearRow
    clearRow.scripts.OnClick()
    check(clears[table.getn(clears)] == "cd:pots", "row Clear dock uses the cd: id")
    check(dock["cd:pots"].mode == "free", "row clear resets the pots dock record")
    check(dock["cd:bare"].mode == "frame" and dock["cd:bare"].x == 8, "bare row keeps its own dock record")
    check(shownIn(potsBlock, "Parent: ") == nil and shownIn(potsBlock, "Unit: ") == nil,
        "free pots row hides frame and portrait fields")
    check(shownIn(bareBlock, "Parent: ") ~= nil, "bare row still shows its frame dock")

    local beforeNew = countDock(page)
    local nid = IchaUI_CustomDrawers_Create("Food", {})
    check(nid ~= nil, "create returns an id")
    check(countDock(page) == beforeNew + 1, "a newly created drawer row gets dock controls")
    local foodDock
    for n, f in ipairs(all) do
        if under(f, page) and f.lastText and string.sub(f.lastText, 1, 6) == "Dock: "
            and f.scripts and f.scripts.OnClick then
            foodDock = f
        end
    end
    captured = nil
    this = foodDock
    foodDock.scripts.OnClick()
    captured.onPick(3)
    check(dock["cd:" .. nid] and dock["cd:" .. nid].mode == "portrait",
        "new drawer dock controls bind cd:" .. tostring(nid))
    check(dock["cd:pots"].mode == "free" and dock["cd:bare"].mode == "frame" and dock["cd:bare"].x == 8,
        "a new drawer does not overwrite the other cd: dock rows")
    check(dock["custom"] == nil and dock["cd"] == nil and dock.pots == nil and dock.bare == nil and dock[nid] == nil,
        "options do not write a shared or bare dock key")
    local si
    for si = 1, table.getn(sets) do
        local wrote = sets[si][1]
        local bareKey = (wrote == "custom" or wrote == "cd" or wrote == "pots" or wrote == "bare" or wrote == nid)
        local missingColon = type(wrote) == "string" and string.sub(wrote, 1, 2) == "cd" and string.sub(wrote, 1, 3) ~= "cd:"
        check(not bareKey and not missingColon, "dock Set id is a full cd: key, got " .. tostring(wrote))
        check(sets[si][4] ~= "wipe", "DrawerDockSet must take a fields table, not a string key")
    end
    for si = 1, table.getn(clears) do
        local wrote = clears[si]
        check(type(wrote) == "string" and string.sub(wrote, 1, 3) == "cd:" and string.len(wrote) > 3,
            "dock Clear id is a full cd: key, got " .. tostring(wrote))
    end

    IchaUI_DrawerDockGet = nil
    IchaUI_DrawerDockSet = nil
    local bareHost = CreateFrame("Frame", nil, UIParent)
    local yBare = IchaUI_BuildDrawerDockBlock(bareHost, "cd:bare", 0, -10)
    check(yBare == -10, "helper omits dock rows when DrawerDock is missing")
    check(bareHost._ichaDockLayout == nil, "helper does not install a layout when DrawerDock is missing")
end

if fails > 0 then
    io.stderr:write(fails .. " failed\n")
    os.exit(1)
end
print("ok")
