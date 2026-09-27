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
function IchaUI_DrawerDockSet(id, key, value)
    table.insert(sets, { id, key, value })
    if type(dock[id]) ~= "table" then dock[id] = {} end
    dock[id][key] = value
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

IchaUI_DrawerDockGet = nil
IchaUI_DrawerDockSet = nil
IchaUIDB.customDrawers[2] = { id = "bare", name = "Bare", shape = "circle", dir = "up" }
local docksBeforeBare = dockButtons()
check(IchaUI_ShowDrawerPop("cd:bare") == true, "popup still opens when DrawerDock is absent")
check(dockButtons() == docksBeforeBare, "missing DrawerDock omits dock rows")

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
end

if fails > 0 then
    io.stderr:write(fails .. " failed\n")
    os.exit(1)
end
print("ok")
