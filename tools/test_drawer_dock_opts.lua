-- Drawer dock picker ids and the edit-mode popup dock rows.
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
function proto:GetFont() return nil end
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

IchaUI_PaintGoldBorder = noop
IchaUI_PaintGoldFont = noop
IchaUI_DyeFs = function(fs, r, g, b)
    if fs and fs.SetTextColor then fs:SetTextColor(r, g, b) end
end

local optionsOk, optionsErr = pcall(dofile, "IchaUI/Options.lua")
check(optionsOk, "load Options.lua: " .. tostring(optionsErr))
local popOk, popErr = pcall(dofile, "IchaUI/DrawerPop.lua")
check(popOk, "load DrawerPop.lua: " .. tostring(popErr))

IchaUI_IsShaman = function() return false end
IchaUIDB = {
    customDrawers = {
        { id = "pots", name = "Pots", shape = "circle", dir = "up" },
        { id = "noname", name = "" },
        { name = "NoId" },
    },
}
IchaUIDB.customDrawers.note = { id = "ghost", name = "Ghost" }

local function findOpt(opts, id)
    local i
    for i = 1, table.getn(opts) do
        if opts[i] and opts[i][1] == id then return opts[i] end
    end
    return nil
end

local opts = IchaUI_DrawerDockDrawerOpts()
check(findOpt(opts, "totems") == nil, "non-shaman omits totems")
check(findOpt(opts, "recall") == nil, "non-shaman omits recall")
check(findOpt(opts, "utility") == nil, "non-shaman omits utility")
check(findOpt(opts, "minimap") ~= nil, "lists minimap")
check(findOpt(opts, "resists") ~= nil, "lists resists")
local pots = findOpt(opts, "cd:pots")
check(pots ~= nil and pots[2] == "Pots", "custom drawer is cd:pots labeled Pots")
check(findOpt(opts, "pots") == nil, "does not list the bare custom id")
check(findOpt(opts, "ghost") == nil and findOpt(opts, "cd:ghost") == nil, "ignores a hash entry pairs() would see")
local noname = findOpt(opts, "cd:noname")
check(noname ~= nil and noname[2] == "noname", "empty name falls back to id")
check(findOpt(opts, "cd:NoId") == nil, "skips a record with no id")

local potsAt, nonameAt
local i
for i = 1, table.getn(opts) do
    if opts[i][1] == "cd:pots" then potsAt = i end
    if opts[i][1] == "cd:noname" then nonameAt = i end
end
check(potsAt and nonameAt and potsAt < nonameAt, "custom drawers stay in array order")

IchaUI_IsShaman = function() return true end
opts = IchaUI_DrawerDockDrawerOpts()
check(opts[1] and opts[1][1] == "totems" and opts[1][2] == "Totems", "shaman lists totems first")
check(findOpt(opts, "cd:pots") ~= nil, "shaman list still has cd:pots")

local dock = {}
local sets = {}
local clears = {}
function IchaUI_DrawerDockGet(id)
    return dock[id]
end
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

IchaUI_IsShaman = function() return false end
local page = CreateFrame("Frame", "DockPage")
page.GetHeight = function() return 0 end
page.SetHeight = function() end
local bottom = IchaUI_BuildDrawerDockBlock(page, -4, 10)
check(type(bottom) == "number" and bottom < -4, "dock block returns a cursor below its header")

local function buttonText(prefix)
    local n, f
    for n, f in ipairs(all) do
        if f._label and type(f._label.text) == "string" and string.sub(f._label.text, 1, string.len(prefix)) == prefix then
            return f
        end
    end
    return nil
end

local drawerBtn = buttonText("Drawer: ")
check(drawerBtn ~= nil and drawerBtn._label.text == "Drawer: Minimap", "picker starts on Minimap")

local captured
IchaUI_ChoiceMenu = function(anchor, menuOpts, cur, onPick)
    captured = { opts = menuOpts, cur = cur, onPick = onPick, anchor = anchor }
end
this = drawerBtn
drawerBtn.scripts.OnClick()
check(captured and findOpt(captured.opts, "cd:pots") and findOpt(captured.opts, "cd:pots")[2] == "Pots",
    "picker menu includes cd:pots / Pots")
check(captured and findOpt(captured.opts, "cd:ghost") == nil, "picker menu skips the hash entry")
local pickIdx
for i = 1, table.getn(captured.opts) do
    if captured.opts[i][1] == "cd:pots" then pickIdx = i end
end
captured.onPick(pickIdx)
drawerBtn = buttonText("Drawer: ")
check(drawerBtn and drawerBtn._label.text == "Drawer: Pots", "picking the custom row selects Pots")

dock["cd:pots"] = { mode = "portrait", unit = "player", angle = 45, ox = 3, oy = -1,
    parent = "PlayerFrame", point = "TOP", relPoint = "BOTTOM", x = 12, y = -8 }
IchaUI_DrawerDockBlockRefresh()

local function rowShown(prefix)
    local btn = buttonText(prefix)
    if not btn or not btn.parent then return nil end
    return btn.parent.shown
end
check(rowShown("Unit: ") == true, "portrait mode shows the unit row")
check(rowShown("Parent: ") == false, "portrait mode hides the frame parent row")
check(buttonText("Unit: ") and buttonText("Unit: ")._label.text == "Unit: Player", "unit label comes from PortraitOpts")

dock["cd:pots"].mode = "frame"
IchaUI_DrawerDockBlockRefresh()
check(rowShown("Parent: ") == true, "frame mode shows the parent row")
check(rowShown("Unit: ") == false, "frame mode hides the unit row")
check(buttonText("Point: ") and buttonText("Point: ")._label.text == "Point: Top", "point label")
check(buttonText("Rel: ") and buttonText("Rel: ")._label.text == "Rel: Bottom", "relPoint label")

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
check(cellShown("Angle") == false, "frame mode hides the angle slider")
local xsl
local n, f
for n, f in ipairs(all) do
    if f.lo == -1200 and f.scripts and f.scripts.OnValueChanged then xsl = f end
end
check(xsl ~= nil, "frame offsets have a slider")
local nsets = table.getn(sets)
xsl.value = 40
this = xsl
xsl.scripts.OnValueChanged()
check(table.getn(sets) == nsets + 1, "dragging an offset writes once")
check(dock["cd:pots"].x == 40 or dock["cd:pots"].y == 40, "offset slider writes through DrawerDockSet")

local clearBtn = buttonText("Clear dock")
check(clearBtn ~= nil, "options block has Clear dock")
this = clearBtn
clearBtn.scripts.OnClick()
check(clears[table.getn(clears)] == "cd:pots", "Clear dock clears the selected cd: id")
check(rowShown("Parent: ") == false, "clear returns to free and hides frame rows")

-- Edit-mode popup for the same custom drawer.
dock["cd:pots"] = { mode = "portrait", unit = "player", angle = 90, ox = 4, oy = -2,
    parent = "PlayerFrame", point = "TOPLEFT", relPoint = "CENTER", x = 20, y = -6 }
function IchaUI_CustomDrawers_ApplyStyle() end
local shown = IchaUI_ShowDrawerPop("cd:pots")
check(shown == true, "right-click path opens the custom drawer popup")
check(IchaUIDrawerPop and IchaUIDrawerPop.title and IchaUIDrawerPop.title.text == "Pots", "popup title is the drawer name")

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
local dockBtn = popCell("Dock: ")
check(dockBtn ~= nil and dockBtn.lastText == "Dock: Portrait", "popup dock mode is Portrait")
check(dockBtn.shown == true, "dock mode row is shown")
local parentBtn = popCell("Parent: ")
check(parentBtn ~= nil and parentBtn.shown == false, "popup hides parent while portrait-docked")
local unitBtn = popCell("Unit: ")
check(unitBtn ~= nil and unitBtn.shown == true and unitBtn.lastText == "Unit: Player", "popup shows the portrait unit")
check(cellShown("Angle") == true, "popup shows angle while portrait-docked")
check(cellShown("Dock X") == false, "popup hides frame offsets while portrait-docked")

captured = nil
this = dockBtn
dockBtn.scripts.OnClick()
check(captured and captured.opts and captured.opts[3] and captured.opts[3][1] == "portrait", "popup mode menu offers portrait")
local frameIdx
for i = 1, table.getn(captured.opts) do
    if captured.opts[i][1] == "frame" then frameIdx = i end
end
captured.onPick(frameIdx)
check(dock["cd:pots"].mode == "frame", "picking Frame writes mode through DrawerDockSet")
parentBtn = popCell("Parent: ")
unitBtn = popCell("Unit: ")
check(parentBtn and parentBtn.shown == true, "popup shows parent after switching to frame")
check(unitBtn and unitBtn.shown == false, "popup hides unit after switching to frame")
check(popCell("Point: ") and popCell("Point: ").lastText == "Point: Top Left", "popup point label")

local clearPop = popCell("Clear dock")
check(clearPop ~= nil, "popup has Clear dock")
local nclears = table.getn(clears)
this = clearPop
clearPop.scripts.OnClick()
check(table.getn(clears) == nclears + 1 and clears[table.getn(clears)] == "cd:pots", "popup Clear dock uses the cd: id")
check(popCell("Dock: ") and popCell("Dock: ").lastText == "Dock: Free", "popup returns to Free after clear")
check(popCell("Parent: ").shown == false and popCell("Unit: ").shown == false, "popup hides dock fields after clear")

-- No DrawerDock API: a second drawer omits dock rows.
IchaUI_DrawerDockGet = nil
IchaUI_DrawerDockSet = nil
IchaUIDB.customDrawers[3] = { id = "bare", name = "Bare", shape = "circle", dir = "up" }
local bare = IchaUI_ShowDrawerPop("cd:bare")
check(bare == true, "popup still opens when DrawerDock is absent")
local function countText(exact)
    local c = 0
    local n, f
    for n, f in ipairs(all) do
        if f.lastText == exact and f.scripts and f.scripts.OnClick then c = c + 1 end
    end
    return c
end
check(countText("Clear dock") == 2, "missing DrawerDock does not add another Clear dock row")

if fails > 0 then
    io.stderr:write(fails .. " failed\n")
    os.exit(1)
end
print("ok")
