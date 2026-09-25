if not GOLD then
    GOLD = { 0.93, 0.78, 0.35 }
end
if not MUTED then
    MUTED = { 0.55, 0.55, 0.55 }
end
sliderSeq = sliderSeq or 0
-- Unselected chrome. Derived from GOLD so it stays near the dark gold border.
GOLD_DIM = {
    (GOLD[1] or 0.93) * 0.8,
    (GOLD[2] or 0.78) * 0.67,
    0.04,
}

local function db()
    if not IchaUIDB then IchaUIDB = {} end
    return IchaUIDB
end

local panel

local function goldBorder(f, edge)
    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = edge or 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.04, 0.04, 0.05, 0.97)
    IchaUI_PaintGoldBorder(f, 1)
end

-- Widget color only. Never SetTextColor on GameFontNormal / GameFontHighlight
-- themselves; that would recolor the whole game UI.
local function configFontPath()
    local path, size, flags
    if GameFontHighlight and GameFontHighlight.GetFont then
        path, size, flags = GameFontHighlight:GetFont()
    end
    if (not path or path == "") and GameFontNormal and GameFontNormal.GetFont then
        path, size, flags = GameFontNormal:GetFont()
    end
    return path, size, flags
end

function IchaUI_DyeFs(fs, r, g, b)
    if not fs or not fs.SetTextColor then return end
    if fs._ichaSmallInput then
        if IchaUI_StyleInputBox then IchaUI_StyleInputBox(fs) end
        return
    end
    local path, size, flags = configFontPath()
    local sz = size or 12
    local fl = ""
    if fs.GetFont then
        local _, curSz, curFl = fs:GetFont()
        if curSz and curSz >= 8 then sz = curSz end
        if curFl and curFl ~= "" then fl = curFl end
    end
    if (not fl or fl == "") and flags and flags ~= "" then fl = flags end
    if path and path ~= "" and fs.SetFont then
        fs:SetFont(path, sz, fl or "")
    end
    fs:SetTextColor(r, g, b)
end

local function dyeNearBlack(fs, fallbackR, fallbackG, fallbackB)
    if not fs or not fs.GetTextColor then return end
    local r, g, b = fs:GetTextColor()
    if not r then r = 0 end
    if not g then g = 0 end
    if not b then b = 0 end
    if (r + g + b) < 0.25 then
        r = fallbackR or 1
        g = fallbackG or 1
        b = fallbackB or 1
    end
    IchaUI_DyeFs(fs, r, g, b)
end

local function dyeButtonFonts(b)
    if not b then return end
    if b._label then dyeNearBlack(b._label, 1, 1, 1) end
    if b.GetFontString then
        local fs = b:GetFontString()
        if fs then dyeNearBlack(fs, 1, 1, 1) end
    end
    if b.GetName then
        local n = b:GetName()
        if n and getglobal then
            local named = getglobal(n .. "Text")
            if named then dyeNearBlack(named, 1, 1, 1) end
        end
    end
    if b.GetRegions then
        local regs = { b:GetRegions() }
        local i
        for i = 1, table.getn(regs) do
            local reg = regs[i]
            if reg and reg.GetObjectType and reg:GetObjectType() == "FontString" then
                dyeNearBlack(reg, 1, 1, 1)
            end
        end
    end
end

function IchaUI_DyeConfigTree(frame, depth)
    if not frame or not frame.GetObjectType then return end
    depth = depth or 0
    if depth > 14 then return end
    local kind = frame:GetObjectType()
    if kind == "EditBox" then
        dyeNearBlack(frame, 1, 1, 1)
        if not frame._ichaDyeHook then
            frame._ichaDyeHook = true
            local oldGain = frame:GetScript("OnEditFocusGained")
            local oldLost = frame:GetScript("OnEditFocusLost")
            frame:SetScript("OnEditFocusGained", function()
                if oldGain then oldGain() end
                dyeNearBlack(this, 1, 1, 1)
            end)
            frame:SetScript("OnEditFocusLost", function()
                if oldLost then oldLost() end
                dyeNearBlack(this, 1, 1, 1)
            end)
        end
    end
    if kind == "Button" then
        dyeButtonFonts(frame)
        if not frame._ichaDyeHook and frame.SetText then
            frame._ichaDyeHook = true
            local baseSet = frame.SetText
            local oldEnter = frame:GetScript("OnEnter")
            local oldLeave = frame:GetScript("OnLeave")
            local oldShow = frame:GetScript("OnShow")
            frame.SetText = function(self, text)
                baseSet(self, text)
                dyeButtonFonts(self)
            end
            frame:SetScript("OnEnter", function()
                if oldEnter then oldEnter() end
                dyeButtonFonts(this)
            end)
            frame:SetScript("OnLeave", function()
                if oldLeave then oldLeave() end
                dyeButtonFonts(this)
            end)
            frame:SetScript("OnShow", function()
                if oldShow then oldShow() end
                dyeButtonFonts(this)
            end)
        end
    end
    if frame.GetRegions then
        local regs = { frame:GetRegions() }
        local i
        for i = 1, table.getn(regs) do
            local reg = regs[i]
            if reg and reg.GetObjectType and reg:GetObjectType() == "FontString" then
                dyeNearBlack(reg, 1, 1, 1)
            end
        end
    end
    if frame.GetChildren then
        local kids = { frame:GetChildren() }
        local i
        for i = 1, table.getn(kids) do
            IchaUI_DyeConfigTree(kids[i], depth + 1)
        end
    end
end

local function sectionHeader(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    IchaUI_PaintGoldFont(fs, 0.93, 0.78, 0.35)
    if IchaUI_OptNote then IchaUI_OptNote(IchaUI_OptTab or "", text, nil) end
    return fs
end

local function tip(parent, text, x, y, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if width then fs:SetWidth(width) end
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    IchaUI_DyeFs(fs, 0.82, 0.80, 0.72)
    return fs
end


-- Totem sets editor (Drawers tab). Edits the set on the bar page; the < >
-- here page the bar too. Helpers are passed in (they are file locals below).
function IchaUI_BuildTotemSetsBlock(page, x, y, sectionHeader, makeButton, makeEdit, makeKeyBindRow, bindRows)
    local S = IchaUITotemSets
    if not S then return y end
    sectionHeader(page, "Totem sets", x, y); y = y - 18
    local ui = {}
    local prev = makeButton(page, "<", 20, 20, function() S.Step(-1) end)
    prev:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
    local nameFS = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFS:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    nameFS:SetWidth(130)
    nameFS:SetJustifyH("CENTER")
    IchaUI_DyeFs(nameFS, 1, 1, 1)
    local nxt = makeButton(page, ">", 20, 20, function() S.Step(1) end)
    nxt:SetPoint("LEFT", nameFS, "RIGHT", 4, 0)
    local add = makeButton(page, "Add", 44, 20, function()
        S.SetPage(S.Add())
    end)
    add:SetPoint("LEFT", nxt, "RIGHT", 8, 0)
    local del = makeButton(page, "Remove", 58, 20, function()
        if S.Count() > 1 then S.Remove(S.Page()) end
    end)
    del:SetPoint("LEFT", add, "RIGHT", 4, 0)
    y = y - 24

    local nameEdit = makeEdit(page, 140, 20)
    nameEdit:SetPoint("TOPLEFT", page, "TOPLEFT", x + 6, y)
    nameEdit:SetMaxLetters(24)
    nameEdit:SetScript("OnEditFocusGained", function() this._focus = true end)
    nameEdit:SetScript("OnEditFocusLost", function()
        this._focus = nil
        S.Rename(S.Page(), this:GetText() or "")
    end)
    nameEdit:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    nameEdit:SetScript("OnEscapePressed", function()
        this._focus = nil
        this:SetText(S.Name(nil) or "")
        this:ClearFocus()
    end)
    local renTip = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    renTip:SetPoint("LEFT", nameEdit, "RIGHT", 6, 0)
    renTip:SetText("Name (Enter)")
    IchaUI_DyeFs(renTip, 1, 1, 1)
    y = y - 24

    local els = { "earth", "fire", "water", "air" }
    local labels = { "Earth", "Fire", "Water", "Air" }
    ui.pick = {}
    local i
    for i = 1, 4 do
        local el = els[i]
        local lbl = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", page, "TOPLEFT", x + (i - 1) * 72, y - 6)
        lbl:SetText(labels[i])
        IchaUI_DyeFs(lbl, 1, 1, 1)
        local b = CreateFrame("Button", nil, page)
        b:SetWidth(24)
        b:SetHeight(24)
        b:SetPoint("TOPLEFT", page, "TOPLEFT", x + (i - 1) * 72 + 36, y)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        b:SetBackdropColor(0.06, 0.06, 0.07, 0.9)
        IchaUI_PaintGoldBorder(b, 0.85)
        local ic = b:CreateTexture(nil, "ARTWORK")
        ic:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
        ic:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.icon = ic
        b.el = el
        b:SetScript("OnClick", function()
            S.CyclePick(S.Page(), this.el, (arg1 == "RightButton") and -1 or 1)
            local onEnter = this:GetScript("OnEnter")
            if onEnter then onEnter() end
        end)
        b:SetScript("OnEnter", function()
            this:SetBackdropBorderColor(1, 0.9, 0.5, 1)
            if not GameTooltip then return end
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            local t = S.Table(nil)
            GameTooltip:SetText(S.Pick(t, this.el) or "(none)", 1, 1, 1)
            GameTooltip:AddLine("Left: next  Right: previous", 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            IchaUI_PaintGoldBorder(this, 0.85)
            if GameTooltip then GameTooltip:Hide() end
        end)
        ui.pick[i] = b
    end
    y = y - 30

    -- One bind row per existing set (pool of MAX_BINDS), two columns.
    ui.binds = {}
    local BCOLS, BCW, BROW = 2, 240, 22
    local bi
    for bi = 1, S.MAX_BINDS do
        local setIdx = bi
        local col = math.mod(bi - 1, BCOLS)
        local r = math.floor((bi - 1) / BCOLS)
        local row = makeKeyBindRow(page, "Throw " .. bi, x + col * BCW, y - r * BROW,
            function() return IchaUITotems_GetSetBindKey(setIdx) end,
            function(key) IchaUITotems_ApplySetBindKey(setIdx, key) end)
        table.insert(bindRows, row)
        ui.binds[bi] = row
    end
    y = y - math.floor((S.MAX_BINDS + BCOLS - 1) / BCOLS) * BROW - 2
    local tipFS = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tipFS:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
    tipFS:SetWidth(480)
    tipFS:SetJustifyH("LEFT")
    tipFS:SetText("Arrows on the bar with 2+ sets. Keys for sets 1-" .. S.MAX_BINDS
        .. ". Each throw skips live in-range totems, recasts the rest.")
    IchaUI_DyeFs(tipFS, 1, 1, 1)
    y = y - 18

    IchaUI_TotemSetsRefresh = function()
        local p, n = S.Page(), S.Count()
        nameFS:SetText((S.Name(p) or "") .. "  (" .. p .. "/" .. n .. ")")
        IchaUI_DyeFs(nameFS, 1, 1, 1)
        if not nameEdit._focus then nameEdit:SetText(S.Name(p) or "") end
        local t = S.Table(p)
        local k
        for k = 1, 4 do
            local b = ui.pick[k]
            b.icon:SetTexture(S.Icon(S.Pick(t, b.el), b.el))
        end
        if n > 1 then del:SetAlpha(1) else del:SetAlpha(0.4) end
        for k = 1, S.MAX_BINDS do
            local row = ui.binds[k]
            if k <= n then
                local nm = S.Name(k) or ("Set " .. k)
                if string.len(nm) > 13 then nm = string.sub(nm, 1, 12) .. "." end
                row.label:SetText("Throw " .. nm)
                IchaUI_DyeFs(row.label, 1, 1, 1)
                row.label:Show()
                row.button:Show()
                row.refresh()
            else
                row.label:Hide()
                row.button:Hide()
            end
        end
    end
    IchaUI_TotemSetsRefresh()
    return y
end

-- Click-to-bind capture (keyboard + mouse buttons + mouse wheel, with mods)
local keyCapture = { on = false, slot = nil, label = nil, apply = nil }

local KEYCAP_MOUSE = {
    LeftButton = "BUTTON1",
    RightButton = "BUTTON2",
    MiddleButton = "BUTTON3",
    Button4 = "BUTTON4",
    Button5 = "BUTTON5",
}

local function abbreviateBindKey(key)
    if not key or key == "" then return "—" end
    local s = tostring(key)
    s = string.gsub(s, "BUTTON4", "M4")
    s = string.gsub(s, "BUTTON5", "M5")
    s = string.gsub(s, "BUTTON3", "M3")
    s = string.gsub(s, "MOUSEWHEELUP", "MWU")
    s = string.gsub(s, "MOUSEWHEELDOWN", "MWD")
    s = string.gsub(s, "SHIFT%-", "S-")
    s = string.gsub(s, "CTRL%-", "C-")
    s = string.gsub(s, "ALT%-", "A-")
    return s
end

local keyCapFrame
local function ensureKeyCapFrame()
    if keyCapFrame then return keyCapFrame end
    -- Frame (not Button): wheel events are reliable once EnableMouseWheel is on
    local f = CreateFrame("Frame", "IchaUIKeyCapture", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(1000)
    f:SetAllPoints(UIParent)
    f:EnableMouse(true)
    f:EnableKeyboard(true)
    f:EnableMouseWheel(true)
    f:Hide()
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetTexture(0, 0, 0, 0.55)
    local tip = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    tip:SetPoint("CENTER", f, "CENTER", 0, 40)
    IchaUI_PaintGoldFont(tip, 0.93, 0.78, 0.35)
    tip:SetText("Press a key or scroll (Esc cancel)")
    f.tip = tip
    local function finish(key)
        local apply = keyCapture.apply
        local label = keyCapture.label
        keyCapture.on = false
        keyCapture.apply = nil
        keyCapture.label = nil
        f:Hide()
        if IchaUI_RemoveCapWheelHook then IchaUI_RemoveCapWheelHook() end
        if key and apply then
            apply(key)
            if label then
                label:SetText(abbreviateBindKey(key))
            end
        end
    end
    local function isModifierOnlyKey(key)
        if not key then return true end
        local u = string.upper(tostring(key))
        -- Turtle / 1.12 may report ALT/SHIFT/CTRL (not only LALT/RALT)
        if u == "UNKNOWN" or u == "ESCAPE" then return false end
        if u == "ALT" or u == "LALT" or u == "RALT" then return true end
        if u == "SHIFT" or u == "LSHIFT" or u == "RSHIFT" then return true end
        if u == "CTRL" or u == "CONTROL" or u == "LCTRL" or u == "RCTRL"
            or u == "LCONTROL" or u == "RCONTROL" then
            return true end
        return false
    end
    local function refreshCapTip()
        local parts = {}
        if IsShiftKeyDown and IsShiftKeyDown() then table.insert(parts, "Shift") end
        if IsControlKeyDown and IsControlKeyDown() then table.insert(parts, "Ctrl") end
        if IsAltKeyDown and IsAltKeyDown() then table.insert(parts, "Alt") end
        if table.getn(parts) > 0 then
            f.tip:SetText(table.concat(parts, "+") .. " + …  (Esc cancel)")
        else
            f.tip:SetText(keyCapture.prompt or "Press a key (Esc cancel)")
        end
    end
    f:SetScript("OnUpdate", function()
        if keyCapture.on then refreshCapTip() end
    end)
    f:SetScript("OnKeyDown", function()
        local key = arg1
        if not key then return end
        if key == "ESCAPE" then
            finish(nil)
            return
        end
        -- Wait for a non-modifier key; Alt/Shift/Ctrl alone are never a bind
        if isModifierOnlyKey(key) then
            refreshCapTip()
            return
        end
        local full = key
        if IsShiftKeyDown and IsShiftKeyDown() then full = "SHIFT-" .. full end
        if IsControlKeyDown and IsControlKeyDown() then full = "CTRL-" .. full end
        if IsAltKeyDown and IsAltKeyDown() then full = "ALT-" .. full end
        full = string.upper(full)
        -- Safety: never save a bare modifier chord
        if full == "ALT" or full == "SHIFT" or full == "CTRL" or full == "CONTROL" then
            return
        end
        finish(full)
    end)
    f:SetScript("OnMouseUp", function()
        local base = KEYCAP_MOUSE[arg1]
        if not base then return end
        if base == "BUTTON1" or base == "BUTTON2" then
            -- ignore plain click (clicking the overlay)
            if not (IsAltKeyDown() or IsControlKeyDown() or IsShiftKeyDown()) then
                return
            end
        end
        local full = base
        if IsShiftKeyDown() then full = "SHIFT-" .. full end
        if IsControlKeyDown() then full = "CTRL-" .. full end
        if IsAltKeyDown() then full = "ALT-" .. full end
        finish(string.upper(full))
    end)
    f:SetScript("OnMouseWheel", function()
        -- arg1: 1 = up, -1 = down (1.12)
        local dir = tonumber(arg1) or 0
        local base = nil
        if dir > 0 then
            base = "MOUSEWHEELUP"
        elseif dir < 0 then
            base = "MOUSEWHEELDOWN"
        else
            return
        end
        local full = base
        if IsShiftKeyDown and IsShiftKeyDown() then full = "SHIFT-" .. full end
        if IsControlKeyDown and IsControlKeyDown() then full = "CTRL-" .. full end
        if IsAltKeyDown and IsAltKeyDown() then full = "ALT-" .. full end
        finish(string.upper(full))
    end)
    f:SetScript("OnHide", function()
        keyCapture.on = false
        if IchaUI_RemoveCapWheelHook then IchaUI_RemoveCapWheelHook() end
    end)
    keyCapFrame = f
    return f
end


-- While capturing, also listen on WorldFrame (some 1.12 builds skip Frame wheel)
local function chordFromWheel(dir)
    dir = tonumber(dir) or 0
    local base = nil
    if dir > 0 then base = "MOUSEWHEELUP"
    elseif dir < 0 then base = "MOUSEWHEELDOWN"
    else return nil end
    local full = base
    if IsShiftKeyDown and IsShiftKeyDown() then full = "SHIFT-" .. full end
    if IsControlKeyDown and IsControlKeyDown() then full = "CTRL-" .. full end
    if IsAltKeyDown and IsAltKeyDown() then full = "ALT-" .. full end
    return string.upper(full)
end

-- WorldFrame OnMouseWheel ONLY while key-capturing.
-- Leaving a permanent hook swallows MOUSEWHEEL SetBindings (cast never sticks).
local _capWheelInstalled = false
local _capWheelSaved = nil

local function removeCapWheelHook()
    if not _capWheelInstalled then return end
    _capWheelInstalled = false
    local saved = _capWheelSaved
    _capWheelSaved = nil
    if WorldFrame then
        if saved then
            WorldFrame:SetScript("OnMouseWheel", saved)
        else
            WorldFrame:SetScript("OnMouseWheel", nil)
        end
    end
end
IchaUI_RemoveCapWheelHook = removeCapWheelHook

local function ensureCapWheelHook()
    if _capWheelInstalled or not WorldFrame then return end
    _capWheelInstalled = true
    _capWheelSaved = WorldFrame.GetScript and WorldFrame:GetScript("OnMouseWheel")
    WorldFrame:EnableMouseWheel(true)
    WorldFrame:SetScript("OnMouseWheel", function()
        if not keyCapture.on then
            removeCapWheelHook()
            return
        end
        local full = chordFromWheel(arg1)
        if not full then return end
        -- Mirror keyCapFrame finish (removes this hook)
        local apply = keyCapture.apply
        local label = keyCapture.label
        keyCapture.on = false
        keyCapture.apply = nil
        keyCapture.label = nil
        if keyCapFrame then keyCapFrame:Hide() end
        removeCapWheelHook()
        if apply then apply(full) end
        if label then label:SetText(abbreviateBindKey(full)) end
    end)
end

function IchaUI_IsKeyCapturing()
    return keyCapture.on and true or false
end

IchaUI_AbbreviateBindKey = abbreviateBindKey

local function startKeyCapture(labelFS, applyFn, prompt)
    local f = ensureKeyCapFrame()
    ensureCapWheelHook()
    keyCapture.on = true
    keyCapture.label = labelFS
    keyCapture.apply = applyFn
    keyCapture.prompt = prompt or "Press a key or scroll (Esc cancel)"
    f.tip:SetText(keyCapture.prompt)
    f:Show()
    f:EnableKeyboard(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    -- Steal focus so wheel isn't eaten by the options scroller underneath
    if f.SetPropagateKeyboardInput then
        pcall(function() f:SetPropagateKeyboardInput(false) end)
    end
end
IchaUI_StartKeyCapture = startKeyCapture

local function makeKeyBindRow(parent, title, x, y, getKey, setKey)
    local nameFS = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFS:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    nameFS:SetText(title)
    IchaUI_DyeFs(nameFS, 0.9, 0.88, 0.8)
    nameFS:SetWidth(110)
    nameFS:SetJustifyH("LEFT")

    local keyBtn = CreateFrame("Button", nil, parent)
    keyBtn:SetWidth(100)
    keyBtn:SetHeight(20)
    keyBtn:SetPoint("LEFT", nameFS, "RIGHT", 6, 0)
    keyBtn:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    keyBtn:SetBackdropColor(0.06, 0.06, 0.07, 0.9)
    IchaUI_PaintGoldBorder(keyBtn, 0.85)
    local keyFS = keyBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    keyFS:SetPoint("CENTER", keyBtn, "CENTER", 0, 0)
    keyFS:SetText(abbreviateBindKey(getKey()))
    IchaUI_PaintGoldFont(keyFS, 0.93, 0.78, 0.35)
    keyBtn._label = keyFS
    keyBtn:SetScript("OnClick", function()
        startKeyCapture(keyFS, function(key)
            setKey(key)
        end, "Bind: " .. title .. " — key / mouse / scroll (Esc cancel)")
    end)
    keyBtn:SetScript("OnEnter", function()
        this:SetBackdropBorderColor(1, 0.9, 0.5, 1)
    end)
    keyBtn:SetScript("OnLeave", function()
        IchaUI_PaintGoldBorder(this, 0.85)
    end)

    return {
        refresh = function()
            keyFS:SetText(abbreviateBindKey(getKey()))
        end,
        height = 22,
        label = nameFS,
        button = keyBtn,
    }
end

local function makeButton(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(w or 90)
    b:SetHeight(h or 22)
    b:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    b:SetBackdropColor(0.08, 0.08, 0.09, 0.92)
    IchaUI_PaintGoldBorder(b, 0.85)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    fs:SetText(text or "")
    IchaUI_DyeFs(fs, 1, 1, 1)
    b._label = fs
    b.SetText = function(self, t)
        self._label:SetText(t or "")
        IchaUI_DyeFs(self._label, 1, 1, 1)
    end
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function()
        this:SetBackdropBorderColor(1, 0.9, 0.5, 1)
    end)
    b:SetScript("OnLeave", function()
        IchaUI_PaintGoldBorder(this, 0.85)
    end)
    return b
end

local function makeEdit(parent, w, h)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetWidth(w)
    e:SetHeight(h or 20)
    e:SetAutoFocus(false)
    if IchaUI_StyleInputBox then IchaUI_StyleInputBox(e) end
    e:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    e:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    return e
end

-- Slider row: returns { refresh=, height= }  height used for layout cursor
local function makeSliderRow(parent, title, x, y, width, lo, hi, step, get, onChange, labelR, labelG, labelB)
    sliderSeq = sliderSeq + 1
    local name = "IchaUIOptSlider" .. sliderSeq
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(title)
    local lr, lg, lb = 0.9, 0.88, 0.8
    if labelR then lr, lg, lb = labelR, labelG or 1, labelB or 1 end
    IchaUI_DyeFs(fs, lr, lg, lb)
    fs:SetWidth(48)
    fs:SetJustifyH("LEFT")

    local sl = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    sl:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 50, y - 2)
    sl:SetWidth(width or 110)
    sl:SetHeight(16)
    sl:SetMinMaxValues(lo, hi)
    sl:SetValueStep(step)
    getglobal(name .. "Low"):SetText("")
    getglobal(name .. "High"):SetText("")
    getglobal(name .. "Text"):SetText("")
    IchaUI_DyeFs(getglobal(name .. "Low"), 1, 1, 1)
    IchaUI_DyeFs(getglobal(name .. "High"), 1, 1, 1)
    IchaUI_DyeFs(getglobal(name .. "Text"), 1, 1, 1)

    local ed = makeEdit(parent, 42, 18)
    ed:SetPoint("LEFT", sl, "RIGHT", 6, 0)

    local function setBoth(v, fromSlider)
        if v < lo then v = lo end
        if v > hi then v = hi end
        if not fromSlider then sl:SetValue(v) end
        ed:SetText(string.format(step < 1 and "%.2f" or "%.0f", v))
        if onChange then onChange(v) end
    end

    sl:SetScript("OnValueChanged", function()
        setBoth(this:GetValue(), true)
    end)
    ed:SetScript("OnEnterPressed", function()
        local v = tonumber(this:GetText())
        if v then setBoth(v, false) end
        this:ClearFocus()
    end)
    ed:SetScript("OnEditFocusLost", function()
        local v = tonumber(this:GetText())
        if v then setBoth(v, false) end
    end)

    local function refresh()
        local v = get and get() or lo
        sl:SetValue(v)
        ed:SetText(string.format(step < 1 and "%.2f" or "%.0f", v))
    end

    return { refresh = refresh, height = 26 }
end

local STRATA_LABELS = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }

local function makeStrataRow(parent, title, x, y, getIdx, onIdx)
    sliderSeq = sliderSeq + 1
    local name = "IchaUIOptSlider" .. sliderSeq
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(title)
    IchaUI_DyeFs(fs, 0.9, 0.88, 0.8)
    fs:SetWidth(70)
    fs:SetJustifyH("LEFT")

    local sl = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    sl:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 72, y - 2)
    sl:SetWidth(140)
    sl:SetHeight(16)
    sl:SetMinMaxValues(1, 5)
    sl:SetValueStep(1)
    getglobal(name .. "Low"):SetText("")
    getglobal(name .. "High"):SetText("")
    getglobal(name .. "Text"):SetText("")
    IchaUI_DyeFs(getglobal(name .. "Low"), 1, 1, 1)
    IchaUI_DyeFs(getglobal(name .. "High"), 1, 1, 1)
    IchaUI_DyeFs(getglobal(name .. "Text"), 1, 1, 1)

    local val = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    val:SetPoint("LEFT", sl, "RIGHT", 6, 0)
    val:SetWidth(92)
    val:SetJustifyH("LEFT")
    val:SetText("MEDIUM")
    IchaUI_DyeFs(val, 1, 0.95, 0.75)

    sl:SetScript("OnValueChanged", function()
        local v = math.floor((this:GetValue() or 3) + 0.5)
        if v < 1 then v = 1 end
        if v > 5 then v = 5 end
        val:SetText(STRATA_LABELS[v] or "MEDIUM")
        if onIdx then onIdx(v) end
    end)

    local function refresh()
        local v = getIdx and getIdx() or 3
        v = tonumber(v) or 3
        v = math.floor(v + 0.5)
        if v < 1 then v = 1 end
        if v > 5 then v = 5 end
        sl:SetValue(v)
        val:SetText(STRATA_LABELS[v] or "MEDIUM")
    end

    return { refresh = refresh, height = 26 }
end

local PANEL_W = 1260
local PANEL_H = 740
local CONTENT_PAD = 12
local PAD = 10
local ROW = 26
local SLW = 140
-- Right column origin inside a page (page width is PANEL_W minus pads and scrollbar)
local COL2 = 560
local COL_TIP = 470

-- Smart Mark tab. Lives outside build() to keep its locals/upvalues under Lua 5.0 limits.
local function smWhite(parent, text, x, y, w)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if w then fs:SetWidth(w) end
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    IchaUI_DyeFs(fs, 1, 1, 1)
    return fs
end

local function smIconCoords(tex, idx)
    local i = (tonumber(idx) or 1) - 1
    local left = math.mod(i, 4) * 0.25
    local top = math.floor(i / 4) * 0.25
    tex:SetTexCoord(left, left + 0.25, top, top + 0.25)
end

local function buildSmartMarkPage(pg, makeGoldToggle, paintGoldToggle)
    local refreshList = {}
    local function refreshAll()
        local i
        for i = 1, table.getn(refreshList) do refreshList[i]() end
    end
    local function flagOn()
        if not IchaUIDB or IchaUIDB.smartMark == nil then return true end
        return IchaUIDB.smartMark and true or false
    end

    local y = -4
    sectionHeader(pg, "Smart Mark", PAD, y)
    y = y - 20
    local onBtn = makeGoldToggle(pg, "Smart Mark: On", 160, 20)
    onBtn:SetPoint("TOPLEFT", pg, "TOPLEFT", PAD, y)
    onBtn:SetScript("OnClick", function()
        if not IchaUIDB then IchaUIDB = {} end
        IchaUIDB.smartMark = not flagOn()
        refreshAll()
    end)
    table.insert(refreshList, function()
        local on = flagOn()
        if onBtn._label then onBtn._label:SetText(on and "Smart Mark: On" or "Smart Mark: Off") end
        paintGoldToggle(onBtn, on)
        if onBtn._label then IchaUI_DyeFs(onBtn._label, 1, 1, 1) end
    end)
    local bindE = makeKeyBindRow(pg, "Enemy key", PAD + 176, y - 4,
        function() return IchaUI_SmartMark_GetKey and IchaUI_SmartMark_GetKey("enemy") end,
        function(key)
            if IchaUI_SmartMark_SetKey then IchaUI_SmartMark_SetKey("enemy", key) end
            refreshAll()
        end)
    local bindF = makeKeyBindRow(pg, "Friendly key", PAD + 408, y - 4,
        function() return IchaUI_SmartMark_GetKey and IchaUI_SmartMark_GetKey("friend") end,
        function(key)
            if IchaUI_SmartMark_SetKey then IchaUI_SmartMark_SetKey("friend", key) end
            refreshAll()
        end)
    table.insert(refreshList, bindE.refresh)
    table.insert(refreshList, bindF.refresh)
    y = y - 28
    smWhite(pg, "Hold the bind's modifier and sweep the mouse over units. Smart Mark marks enemies only; Smart Mark Friendly marks friendly units only. Units that already have a mark are skipped. Release the modifier to stop. Binds need Shift, Ctrl, or Alt (also under Esc > Key Bindings > IchaUI Smart Mark).", PAD, y, 640)
    y = y - 40

    local ROWH = 22
    local function buildList(kind, title, x)
        sectionHeader(pg, title, x, y)
        local r
        for r = 1, 8 do
            local pos = r
            local ry = y - 18 - (r - 1) * ROWH
            local num = smWhite(pg, pos .. ".", x, ry - 4, 16)
            local cb = CreateFrame("CheckButton", nil, pg)
            cb:SetWidth(20)
            cb:SetHeight(20)
            cb:SetPoint("TOPLEFT", pg, "TOPLEFT", x + 16, ry + 1)
            cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
            cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
            cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
            cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
            local icon = pg:CreateTexture(nil, "ARTWORK")
            icon:SetWidth(18)
            icon:SetHeight(18)
            icon:SetPoint("TOPLEFT", pg, "TOPLEFT", x + 40, ry)
            icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
            local name = smWhite(pg, "", x + 62, ry - 4, 70)
            local up = makeButton(pg, "Up", 34, 18, function()
                if IchaUI_SmartMark_Move then IchaUI_SmartMark_Move(kind, pos, -1) end
                refreshAll()
            end)
            up:SetPoint("TOPLEFT", pg, "TOPLEFT", x + 134, ry)
            local dn = makeButton(pg, "Dn", 34, 18, function()
                if IchaUI_SmartMark_Move then IchaUI_SmartMark_Move(kind, pos, 1) end
                refreshAll()
            end)
            dn:SetPoint("LEFT", up, "RIGHT", 4, 0)
            cb:SetScript("OnClick", function()
                local ord = IchaUI_SmartMark_GetOrder and IchaUI_SmartMark_GetOrder(kind)
                if ord and ord[pos] and IchaUI_SmartMark_SetIconOn then
                    IchaUI_SmartMark_SetIconOn(kind, ord[pos], this:GetChecked() and true or false)
                end
                refreshAll()
            end)
            if pos == 1 then up:SetAlpha(0.35) end
            if pos == 8 then dn:SetAlpha(0.35) end
            table.insert(refreshList, function()
                local ord = IchaUI_SmartMark_GetOrder and IchaUI_SmartMark_GetOrder(kind)
                local idx = ord and ord[pos] or pos
                local on = true
                if IchaUI_SmartMark_IsIconOn then on = IchaUI_SmartMark_IsIconOn(kind, idx) end
                smIconCoords(icon, idx)
                name:SetText(IchaUI_SmartMark_IconName and IchaUI_SmartMark_IconName(idx) or "")
                cb:SetChecked(on and 1 or nil)
                if on then
                    icon:SetAlpha(1)
                    IchaUI_DyeFs(name, 1, 1, 1)
                    IchaUI_DyeFs(num, 1, 1, 1)
                else
                    icon:SetAlpha(0.3)
                    IchaUI_DyeFs(name, 0.55, 0.55, 0.55)
                    IchaUI_DyeFs(num, 0.55, 0.55, 0.55)
                end
            end)
        end
        local by = y - 18 - 8 * ROWH - 4
        local reset = makeButton(pg, "Reset", 70, 20, function()
            if IchaUI_SmartMark_Reset then IchaUI_SmartMark_Reset(kind) end
            refreshAll()
        end)
        reset:SetPoint("TOPLEFT", pg, "TOPLEFT", x, by)
        return reset
    end
    buildList("enemy", "Enemy order", PAD)
    local fReset = buildList("friend", "Friendly order", PAD + 300)
    local copy = makeButton(pg, "Copy enemy order", 120, 20, function()
        if IchaUI_SmartMark_CopyOrder then IchaUI_SmartMark_CopyOrder("enemy", "friend") end
        refreshAll()
    end)
    copy:SetPoint("LEFT", fReset, "RIGHT", 6, 0)
    smWhite(pg, "Icons go top to bottom and wrap after the last checked one. Unchecked icons are never used.", PAD, y - 18 - 8 * ROWH - 32, 640)

    refreshAll()
    return refreshAll
end

local function build()
    if panel then return panel end

    panel = CreateFrame("Frame", "IchaUIOptions", UIParent)
    panel.refresh = function() end
    panel:SetWidth(PANEL_W)
    panel:SetHeight(PANEL_H)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 10)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetFrameLevel(200)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function() this:StartMoving() end)
    panel:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    goldBorder(panel, 16)
    panel:Hide()

    -- Collect every makeSliderRow refresh into one list (Lua 60-upvalue limit on panel.refresh)
    local sliderRefreshList = {}
    local _makeSliderRow = makeSliderRow
    makeSliderRow = function(parent, title, x, y, width, lo, hi, step, get, onChange, labelR, labelG, labelB)
        local sl = _makeSliderRow(parent, title, x, y, width, lo, hi, step, get, onChange, labelR, labelG, labelB)
        if sl and sl.refresh then
            table.insert(sliderRefreshList, sl.refresh)
        end
        return sl
    end
    local _makeStrataRow = makeStrataRow
    makeStrataRow = function(parent, title, x, y, getIdx, onIdx)
        local sl = _makeStrataRow(parent, title, x, y, getIdx, onIdx)
        if sl and sl.refresh then
            table.insert(sliderRefreshList, sl.refresh)
        end
        return sl
    end
    tinsert(UISpecialFrames, "IchaUIOptions")

    local _tipWide = tip
    tip = function(parent, text, x, y, width)
        if not width or width > COL_TIP then width = COL_TIP end
        return _tipWide(parent, text, x, y, width)
    end

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", panel, "TOP", 0, -14)
    title:SetText("IchaUI")
    IchaUI_PaintGoldFont(title, 0.93, 0.78, 0.35)

    local close = makeButton(panel, "Close", 70, 22, function() panel:Hide() end)
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -12)

    local function paintTestSubBtns()
        if panel._testPartyBtn and IchaUIUF_GetTestParty then
            local on = IchaUIUF_GetTestParty()
            panel._testPartyBtn:SetText(on and "[Party]" or "Party")
        end
        if panel._testRaidBtn and IchaUIUF_GetTestRaid then
            local on = IchaUIUF_GetTestRaid()
            panel._testRaidBtn:SetText(on and "[Raid]" or "Raid")
        end
        local tm = IchaUIUF_GetTestMode and IchaUIUF_GetTestMode()
        if panel._testPartyBtn then
            if tm then panel._testPartyBtn:Show() else panel._testPartyBtn:Hide() end
        end
        if panel._testRaidBtn then
            if tm then panel._testRaidBtn:Show() else panel._testRaidBtn:Hide() end
        end
    end

    local testBtn = makeButton(panel, "Test UI: Off", 100, 22, function()
        if IchaUI_ToggleTestMode then
            IchaUI_ToggleTestMode()
        elseif IchaUI_TestMode then
            local on = not (IchaUIUF_GetTestMode and IchaUIUF_GetTestMode())
            IchaUI_TestMode(on)
        end
        local on = IchaUIUF_GetTestMode and IchaUIUF_GetTestMode()
        this:SetText(on and "Test UI: On" or "Test UI: Off")
        paintTestSubBtns()
    end)
    testBtn:SetPoint("RIGHT", close, "LEFT", -8, 0)
    panel._testBtn = testBtn

    local testPartyBtn = makeButton(panel, "[Party]", 58, 22, function()
        if not IchaUIUF_GetTestParty or not IchaUIUF_SetTestParty then return end
        IchaUIUF_SetTestParty(not IchaUIUF_GetTestParty())
        paintTestSubBtns()
    end)
    testPartyBtn:SetPoint("RIGHT", testBtn, "LEFT", -4, 0)
    panel._testPartyBtn = testPartyBtn

    local testRaidBtn = makeButton(panel, "[Raid]", 52, 22, function()
        if not IchaUIUF_GetTestRaid or not IchaUIUF_SetTestRaid then return end
        IchaUIUF_SetTestRaid(not IchaUIUF_GetTestRaid())
        paintTestSubBtns()
    end)
    testRaidBtn:SetPoint("RIGHT", testPartyBtn, "LEFT", -2, 0)
    panel._testRaidBtn = testRaidBtn
    testPartyBtn:Hide()
    testRaidBtn:Hide()
    panel._paintTestSubBtns = paintTestSubBtns


    ------------------------------------------------------------------
    -- Left tab column (pages sit to the right; profile bar sits below)
    ------------------------------------------------------------------
    local TAB_NAMES = { "Bars", "Hero", "Buffs", "Frames", "Drawers", "Map", "Combat", "Mark", "Skin" }
    local tabBtns = {}
    local pages = {}
    local activeTab = nil
    local contentY = -70
    local contentH = PANEL_H + contentY - 64
    local tabCol = 112

    title:ClearAllPoints()
    title:SetPoint("TOP", panel, "TOP", math.floor(tabCol * 0.5), -14)

    local tabBar = CreateFrame("Frame", nil, panel)
    tabBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, contentY)
    tabBar:SetWidth(tabCol - 4)
    tabBar:SetHeight(PANEL_H + contentY - 16)

    local function paintTab(btn, selected)
        if selected then
            btn:SetBackdropColor(0.18, 0.14, 0.06, 0.95)
            IchaUI_PaintGoldBorder(btn, 1)
            IchaUI_PaintGoldFont(btn._label, 0.93, 0.78, 0.35)
        else
            btn:SetBackdropColor(0.06, 0.06, 0.07, 0.85)
            btn:SetBackdropBorderColor(GOLD_DIM[1], GOLD_DIM[2], GOLD_DIM[3], 0.7)
            IchaUI_DyeFs(btn._label, 0.82, 0.80, 0.72)
            if btn._label then btn._label._gSkip = true end
        end
    end

    local function showTab(name)
        local i, n, btn, pg, known
        if name == "Text" then name = "Frames" end
        known = false
        for i = 1, table.getn(TAB_NAMES) do
            if TAB_NAMES[i] == name then known = true end
        end
        if not known then
            if activeTab then name = activeTab else name = "Bars" end
        end
        activeTab = name
        db().optionsTab = name
        local pop = getglobal("IchaUIProfileList")
        if pop then pop:Hide() end
        for i = 1, table.getn(TAB_NAMES) do
            n = TAB_NAMES[i]
            btn = tabBtns[n]
            pg = pages[n]
            if btn then paintTab(btn, n == name) end
            if pg then
                if n == name then pg:Show() else pg:Hide() end
            end
        end
        if name == "Drawers" and pages._drawersRefresh then
            pages._drawersRefresh()
        end
        if name == "Combat" and pages._combatRefresh then
            pages._combatRefresh()
        end
        if name == "Map" and pages._mapRefresh then
            pages._mapRefresh()
        end
        if panel then IchaUI_DyeConfigTree(panel, 0) end
        if name == "Mark" and pages._markRefresh then
            pages._markRefresh()
        end
    end
    panel._repaintTabs = function()
        local name = activeTab
        if not name or name == "" then name = "Bars" end
        showTab(name)
    end

    local tabGap = 3
    local tabCount = table.getn(TAB_NAMES)
    local tabW = tabCol - 8
    local ti
    for ti = 1, table.getn(TAB_NAMES) do
        local name = TAB_NAMES[ti]
        local b = CreateFrame("Button", nil, tabBar)
        b:SetWidth(tabW)
        b:SetHeight(22)
        b:SetPoint("TOPLEFT", tabBar, "TOPLEFT", 0, -((ti - 1) * (22 + tabGap)))
        b:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        local lbl = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("CENTER", b, "CENTER", 0, 0)
        lbl:SetText(name)
        b._label = lbl
        b:SetScript("OnClick", function() showTab(name) end)
        paintTab(b, false)
        tabBtns[name] = b
    end

    local function makePage(name, scrollH)
        local scrollName = "IchaUIOptScroll" .. name
        local scroll = CreateFrame("ScrollFrame", scrollName, panel)
        scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_PAD + tabCol, contentY)
        scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -CONTENT_PAD - 4, 58)
        scroll:EnableMouseWheel(true)
        scroll:Hide()
        local pg = CreateFrame("Frame", nil, scroll)
        local innerW = PANEL_W - CONTENT_PAD * 2 - 20 - tabCol
        if innerW < 200 then innerW = 200 end
        local innerH = tonumber(scrollH) or (contentH + 80)
        if innerH < contentH then innerH = contentH + 40 end
        pg:SetWidth(innerW)
        pg:SetHeight(innerH)
        scroll:SetScrollChild(pg)
        scroll:SetScript("OnMouseWheel", function()
            local cur = this:GetVerticalScroll() or 0
            local max = this:GetVerticalScrollRange() or 0
            if max < 0 then max = 0 end
            local step = 36
            local nextY = cur - (arg1 or 0) * step
            if nextY < 0 then nextY = 0 end
            if nextY > max then nextY = max end
            this:SetVerticalScroll(nextY)
        end)
        local tipFS = scroll:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tipFS:SetPoint("BOTTOMRIGHT", scroll, "TOPRIGHT", -2, 2)
        IchaUI_DyeFs(tipFS, 0.82, 0.80, 0.72)
        tipFS:SetText("scroll")
        scroll._tip = tipFS
        pages[name] = scroll
        pg._scroll = scroll
        IchaUI_OptTab = name
        return pg
    end

    local function paintGoldToggle(b, on)
        if not b or not b.SetBackdropColor then return end
        if on then
            b:SetBackdropColor(0.18, 0.14, 0.06, 0.95)
            IchaUI_PaintGoldBorder(b, 1)
            if b._label then IchaUI_PaintGoldFont(b._label, 0.93, 0.78, 0.35) end
        else
            b:SetBackdropColor(0.06, 0.06, 0.07, 0.85)
            b:SetBackdropBorderColor(GOLD_DIM[1], GOLD_DIM[2], GOLD_DIM[3], 0.7)
            if b._label then
                b._label._gSkip = true
                IchaUI_DyeFs(b._label, 0.82, 0.80, 0.72)
            end
        end
    end

    local function makeGoldToggle(parent, text, w, h)
        local b = CreateFrame("Button", nil, parent)
        b:SetWidth(w or 70)
        b:SetHeight(h or 18)
        b:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        local lbl = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("CENTER", b, "CENTER", 0, 0)
        lbl:SetText(text or "")
        b._label = lbl
        paintGoldToggle(b, false)
        return b
    end

    ------------------------------------------------------------------
    -- Shared: unit-frame block builder
    ------------------------------------------------------------------
    local function ufBlock(parent, tag, y)
        local pretty = string.upper(string.sub(tag, 1, 1)) .. string.sub(tag, 2)
        if tag == "tot" then pretty = "ToT" end
        if tag == "combat" then pretty = "In combat" end
        sectionHeader(parent, pretty, PAD, y)
        y = y - 18
        local w = makeSliderRow(parent, "Width", PAD, y, 100, 1, 600, 5,
            function()
                local fr = IchaUIUF_Get and IchaUIUF_Get(tag)
                return fr and fr.width or 220
            end,
            function(v) if IchaUIUF_Set then IchaUIUF_Set(tag, "width", v) end end)
        y = y - ROW
        local h = makeSliderRow(parent, "Height", PAD, y, 100, 1, 120, 1,
            function()
                local fr = IchaUIUF_Get and IchaUIUF_Get(tag)
                return fr and fr.height or 48
            end,
            function(v) if IchaUIUF_Set then IchaUIUF_Set(tag, "height", v) end end)
        y = y - ROW
        local s = makeSliderRow(parent, "Scale", PAD, y, 100, 0.4, 3.0, 0.05,
            function()
                local fr = IchaUIUF_Get and IchaUIUF_Get(tag)
                return fr and fr.scale or 1
            end,
            function(v) if IchaUIUF_Set then IchaUIUF_Set(tag, "scale", v) end end)
        y = y - ROW

        local xl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        xl:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
        xl:SetText("X")
        xl:SetTextColor(0.9, 0.88, 0.8)
        local xEdit = makeEdit(parent, 44, 18)
        xEdit:SetPoint("LEFT", xl, "RIGHT", 4, 0)
        local yl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        yl:SetPoint("LEFT", xEdit, "RIGHT", 8, 0)
        yl:SetText("Y")
        yl:SetTextColor(0.9, 0.88, 0.8)
        local yEdit = makeEdit(parent, 44, 18)
        yEdit:SetPoint("LEFT", yl, "RIGHT", 4, 0)

        local function refreshXY()
            if not IchaUIUF_GetPos then return end
            local x, yv = IchaUIUF_GetPos(tag)
            xEdit:SetText(string.format("%.0f", x))
            yEdit:SetText(string.format("%.0f", yv))
        end
        local function applyXY()
            if not IchaUIUF_SetPos then return end
            local x = tonumber(xEdit:GetText()) or 0
            local yv = tonumber(yEdit:GetText()) or 0
            IchaUIUF_SetPos(tag, x, yv)
            refreshXY()
        end
        xEdit:SetScript("OnEnterPressed", function() applyXY(); this:ClearFocus() end)
        yEdit:SetScript("OnEnterPressed", function() applyXY(); this:ClearFocus() end)
        xEdit:SetScript("OnEditFocusLost", function() applyXY() end)
        yEdit:SetScript("OnEditFocusLost", function() applyXY() end)

        local function nudge(dx, dy)
            if IchaUIUF_Nudge then IchaUIUF_Nudge(tag, dx, dy) end
            refreshXY()
        end
        local nL = makeButton(parent, "<", 20, 16, function() nudge(-1, 0) end)
        nL:SetPoint("LEFT", yEdit, "RIGHT", 6, 0)
        local nR = makeButton(parent, ">", 20, 16, function() nudge(1, 0) end)
        nR:SetPoint("LEFT", nL, "RIGHT", 1, 0)
        local nU = makeButton(parent, "^", 20, 16, function() nudge(0, 1) end)
        nU:SetPoint("LEFT", nR, "RIGHT", 1, 0)
        local nD = makeButton(parent, "v", 20, 16, function() nudge(0, -1) end)
        nD:SetPoint("LEFT", nU, "RIGHT", 1, 0)
        y = y - 22

        local mv = makeButton(parent, "Move", 48, 18, function()
            local fr = IchaUIUF_Get and IchaUIUF_Get(tag)
            if fr and IchaUIUF_Set then IchaUIUF_Set(tag, "move", not fr.moving) end
        end)
        mv:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
        local sh = makeButton(parent, "Show", 44, 18, function()
            if IchaUIUF_Set then IchaUIUF_Set(tag, "hidden", false) end
        end)
        sh:SetPoint("LEFT", mv, "RIGHT", 4, 0)
        local hi = makeButton(parent, "Hide", 44, 18, function()
            if IchaUIUF_Set then IchaUIUF_Set(tag, "hidden", true) end
        end)
        hi:SetPoint("LEFT", sh, "RIGHT", 4, 0)
        y = y - 26
        return { w = w, h = h, s = s, refreshXY = refreshXY, y = y }
    end

    ------------------------------------------------------------------
    -- TAB 1: Bars (action bars, shield binds, XP)
    ------------------------------------------------------------------
    local pageBars = makePage("Bars", 400)
    local y1 = -4

    sectionHeader(pageBars, "Action bars", PAD, y1); y1 = y1 - 18
    local barScale = makeSliderRow(pageBars, "Scale", PAD, y1, SLW, 0.4, 2.0, 0.05,
        function() return (db().scale or 1) end,
        function(v) if SlashCmdList and SlashCmdList["ICHA"] then SlashCmdList["ICHA"]("scale " .. v) end end)
    y1 = y1 - ROW
    local barGap = makeSliderRow(pageBars, "Gap", PAD, y1, SLW, 0, 20, 0.5,
        function() return (db().gap or 2) end,
        function(v) if SlashCmdList and SlashCmdList["ICHA"] then SlashCmdList["ICHA"]("gap " .. v) end end)
    y1 = y1 - ROW
    makeStrataRow(pageBars, "Strata", PAD, y1,
        function()
            if IchaUI_GetIconStrata then
                local n, idx = IchaUI_GetIconStrata()
                return idx or 3
            end
            return 3
        end,
        function(v)
            if IchaUI_SetIconStrata then IchaUI_SetIconStrata(v) end
        end)
    y1 = y1 - ROW
    local moveBars = makeButton(pageBars, "Edit positions", 110, 20, function()
        if IchaUI_EditPositions then
            IchaUI_EditPositions()
        elseif SlashCmdList then
            SlashCmdList["ICHA"]("move")
        end
    end)
    moveBars:SetPoint("TOPLEFT", pageBars, "TOPLEFT", PAD, y1)
    local hotkeys = makeButton(pageBars, "Hotkeys", 60, 20, function()
        if SlashCmdList then SlashCmdList["ICHA"]("hotkeys") end
    end)
    hotkeys:SetPoint("LEFT", moveBars, "RIGHT", 4, 0)
    local bindBtn = makeButton(pageBars, "Bind", 50, 20, function()
        if SlashCmdList then SlashCmdList["ICHA"]("bind") end
    end)
    bindBtn:SetPoint("LEFT", hotkeys, "RIGHT", 4, 0)
    y1 = y1 - 22
    local function placeActionAdds(page, y)
        local addBtn = makeButton(page, "Add bar", 64, 18, function()
            if IchaUI_ActionBarAdd then IchaUI_ActionBarAdd() end
            if IchaUIOptions and IchaUIOptions.refresh then IchaUIOptions.refresh() end
        end)
        addBtn:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, y)
        local remBtn = makeButton(page, "Remove", 58, 18, function()
            local n = 6
            if IchaUI_ActionBarCount then n = IchaUI_ActionBarCount() or 6 end
            if n > 6 and IchaUI_ActionBarRemove then IchaUI_ActionBarRemove(n) end
            if IchaUIOptions and IchaUIOptions.refresh then IchaUIOptions.refresh() end
        end)
        remBtn:SetPoint("LEFT", addBtn, "RIGHT", 4, 0)
        local function paintActionAdds()
            local n = 6
            if IchaUI_ActionBarCount then n = IchaUI_ActionBarCount() or 6 end
            if n > 6 then remBtn:Show() else remBtn:Hide() end
        end
        IchaUI_ActionAddRefresh = paintActionAdds
        paintActionAdds()
        return y - 22
    end
    y1 = placeActionAdds(pageBars, y1)
    tip(pageBars, "Side bars sit against the hero bar. Add makes another bar while free slots remain. Right-click a bar in Edit positions for scale, opacity, and its grid.", PAD, y1, 520)
    y1 = y1 - 16
    tip(pageBars, "Strata: action bars, hero, totem bar, and all drawers. DIALOG is still below tooltips.", PAD, y1, 520)
    y1 = y1 - 28
    if not IchaUI_BarFormPick then IchaUI_BarFormPick = 1 end
    local barFormBtn = makeButton(pageBars, "Bar 1", 70, 20, function()
        local n = IchaUI_ActionBarCount and IchaUI_ActionBarCount() or 6
        local p = (IchaUI_BarFormPick or 1) + 1
        if p > n then p = 1 end
        IchaUI_BarFormPick = p
        this:SetText("Bar " .. p)
        if pageBars._formRefresh then pageBars._formRefresh() end
    end)
    barFormBtn:SetPoint("TOPLEFT", pageBars, "TOPLEFT", PAD, y1)
    local shapeBtn = makeButton(pageBars, "Shape: Rectangle", 140, 20, function()
        local id = IchaUI_BarFormPick or 1
        local shape, layout, spread, arc, rot = "rect", "grid", 90, 360, 90
        if IchaUI_ActionBarForm then shape, layout, spread, arc, rot = IchaUI_ActionBarForm(id) end
        if IchaUI_FormShapeNext then shape = IchaUI_FormShapeNext(shape) end
        if IchaUI_ActionBarSetForm then IchaUI_ActionBarSetForm(id, shape, layout, spread, arc, rot) end
        if pageBars._formRefresh then pageBars._formRefresh() end
    end)
    shapeBtn:SetPoint("LEFT", barFormBtn, "RIGHT", 4, 0)
    y1 = y1 - 24
    local layBtn = makeButton(pageBars, "Layout: Grid", 120, 20, function()
        local id = IchaUI_BarFormPick or 1
        local shape, layout, spread, arc, rot = "rect", "grid", 90, 360, 90
        if IchaUI_ActionBarForm then shape, layout, spread, arc, rot = IchaUI_ActionBarForm(id) end
        if layout == "radial" then layout = "grid" else layout = "radial" end
        if IchaUI_ActionBarSetForm then IchaUI_ActionBarSetForm(id, shape, layout, spread, arc, rot) end
        if pageBars._formRefresh then pageBars._formRefresh() end
    end)
    layBtn:SetPoint("TOPLEFT", pageBars, "TOPLEFT", PAD, y1)
    y1 = y1 - ROW
    makeSliderRow(pageBars, "Spread", PAD, y1, SLW, 10, 360, 1,
        function()
            local id = IchaUI_BarFormPick or 1
            local _, _, spread = "rect", "grid", 90
            if IchaUI_ActionBarForm then _, _, spread = IchaUI_ActionBarForm(id) end
            return spread or 90
        end,
        function(v)
            local id = IchaUI_BarFormPick or 1
            local shape, layout, spread, arc, rot = "rect", "grid", 90, 360, 90
            if IchaUI_ActionBarForm then shape, layout, spread, arc, rot = IchaUI_ActionBarForm(id) end
            if IchaUI_ActionBarSetForm then IchaUI_ActionBarSetForm(id, shape, layout, v, arc, rot) end
        end)
    y1 = y1 - ROW
    makeSliderRow(pageBars, "Arc", PAD, y1, SLW, 10, 360, 1,
        function()
            local id = IchaUI_BarFormPick or 1
            local arc = 360
            if IchaUI_ActionBarForm then local _, _, _, a = IchaUI_ActionBarForm(id); arc = a end
            return arc or 360
        end,
        function(v)
            local id = IchaUI_BarFormPick or 1
            local shape, layout, spread, arc, rot = "rect", "grid", 90, 360, 90
            if IchaUI_ActionBarForm then shape, layout, spread, arc, rot = IchaUI_ActionBarForm(id) end
            if IchaUI_ActionBarSetForm then IchaUI_ActionBarSetForm(id, shape, layout, spread, v, rot) end
        end)
    y1 = y1 - ROW
    makeSliderRow(pageBars, "Sh Rot", PAD, y1, SLW, -360, 360, 1,
        function()
            local id = IchaUI_BarFormPick or 1
            local rot = 90
            if IchaUI_ActionBarForm then local _, _, _, _, r = IchaUI_ActionBarForm(id); rot = r end
            return rot or 90
        end,
        function(v)
            local id = IchaUI_BarFormPick or 1
            local shape, layout, spread, arc, rot = "rect", "grid", 90, 360, 90
            if IchaUI_ActionBarForm then shape, layout, spread, arc, rot = IchaUI_ActionBarForm(id) end
            if IchaUI_ActionBarSetForm then IchaUI_ActionBarSetForm(id, shape, layout, spread, arc, v) end
        end)
    pageBars._formRefresh = function()
        local id = IchaUI_BarFormPick or 1
        barFormBtn:SetText("Bar " .. id)
        local shape, layout = "rect", "grid"
        if IchaUI_ActionBarForm then shape, layout = IchaUI_ActionBarForm(id) end
        local lab = shape
        if IchaUI_FormShapeLabel then lab = IchaUI_FormShapeLabel(shape) end
        shapeBtn:SetText("Shape: " .. lab)
        if layout == "radial" then layBtn:SetText("Layout: Radial") else layBtn:SetText("Layout: Grid") end
    end
    pageBars._formRefresh()

    y1 = -4
    sectionHeader(pageBars, "Shield binds", COL2, y1); y1 = y1 - 18
    local shieldRows = {}
    local shi
    for shi = 1, 3 do
        local idx = shi
        local spellFallback = { "Lightning Shield", "Water Shield", "Earth Shield" }
        local spellName = spellFallback[idx]
        if IchaUIShieldBinds_GetSpell then
            spellName = IchaUIShieldBinds_GetSpell(idx) or spellName
        end
        local row = makeKeyBindRow(pageBars, spellName, COL2, y1,
            function()
                if IchaUIShieldBinds_GetKey then return IchaUIShieldBinds_GetKey(idx) end
                return ""
            end,
            function(key)
                if IchaUIShieldBinds_ApplyKey then IchaUIShieldBinds_ApplyKey(idx, key) end
            end)
        table.insert(shieldRows, row)
        y1 = y1 - 24
    end
    tip(pageBars, "Click a key, then press keyboard or mouse (Alt-M4 ok). /icha shieldbind", COL2, y1, 520)
    y1 = y1 - 22

    sectionHeader(pageBars, "XP bar", COL2, y1); y1 = y1 - 18
    local xpW = makeSliderRow(pageBars, "Width", COL2, y1, SLW, 80, 1200, 10,
        function() local x = db().xp or {}; return x.width or 400 end,
        function(v) if IchaUIXP_Slash then IchaUIXP_Slash("width " .. v) end end)
    y1 = y1 - ROW
    local xpH = makeSliderRow(pageBars, "Height", COL2, y1, SLW, 6, 80, 1,
        function() local x = db().xp or {}; return x.height or 14 end,
        function(v) if IchaUIXP_Slash then IchaUIXP_Slash("height " .. v) end end)
    y1 = y1 - ROW
    local xpS = makeSliderRow(pageBars, "Scale", COL2, y1, SLW, 0.4, 3.0, 0.05,
        function() local x = db().xp or {}; return x.scale or 1 end,
        function(v) if IchaUIXP_Slash then IchaUIXP_Slash("scale " .. v) end end)
    y1 = y1 - ROW
    local xpMove = makeButton(pageBars, "Move XP", 70, 20, function()
        if IchaUIXP_Slash then IchaUIXP_Slash("move") end
    end)
    xpMove:SetPoint("TOPLEFT", pageBars, "TOPLEFT", COL2, y1)
    local xpShow = makeButton(pageBars, "Show", 48, 20, function()
        if IchaUIXP_Slash then IchaUIXP_Slash("show") end
    end)
    xpShow:SetPoint("LEFT", xpMove, "RIGHT", 4, 0)
    local xpHide = makeButton(pageBars, "Hide", 48, 20, function()
        if IchaUIXP_Slash then IchaUIXP_Slash("hide") end
    end)
    xpHide:SetPoint("LEFT", xpShow, "RIGHT", 4, 0)
    y1 = y1 - 30


    ------------------------------------------------------------------
    -- TAB: Hero bar (grid, per-button binds, shock)
    ------------------------------------------------------------------
    local pageHero = makePage("Hero", 420)
    y1 = -4
    sectionHeader(pageHero, "Hero bar", PAD, y1); y1 = y1 - 18
    local function placeHeroPicks(page, y)
        IchaUI_HeroPick = IchaUI_HeroPick or 1
        local heroPickBtns = {}
        local heroRemoveBtn
        local function paintHeroPicks()
            local n = 1
            if IchaUI_HeroBarCount then n = IchaUI_HeroBarCount() or 1 end
            if n < 1 then n = 1 end
            if (IchaUI_HeroPick or 1) > n then IchaUI_HeroPick = 1 end
            local i
            for i = 1, 5 do
                local b = heroPickBtns[i]
                if b then
                    if i <= n then
                        b:Show()
                        if i == (IchaUI_HeroPick or 1) then
                            b:SetText("[" .. (i == 1 and "Hero" or ("Hero " .. i)) .. "]")
                        else
                            b:SetText(i == 1 and "Hero" or ("Hero " .. i))
                        end
                    else
                        b:Hide()
                    end
                end
            end
            if heroRemoveBtn then
                if (IchaUI_HeroPick or 1) > 1 then heroRemoveBtn:Show() else heroRemoveBtn:Hide() end
            end
        end
        IchaUI_HeroPickRefresh = paintHeroPicks
        local pi
        for pi = 1, 5 do
            local idx = pi
            local b = makeButton(page, idx == 1 and "Hero" or ("Hero " .. idx), 58, 18, function()
                IchaUI_HeroPick = idx
                if IchaUI_HeroFocus then IchaUI_HeroFocus(idx) end
                paintHeroPicks()
                if IchaUIOptions and IchaUIOptions.refresh then IchaUIOptions.refresh() end
            end)
            if idx == 1 then
                b:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, y)
            else
                b:SetPoint("LEFT", heroPickBtns[idx - 1], "RIGHT", 3, 0)
            end
            if idx > 1 then b:Hide() end
            heroPickBtns[idx] = b
        end
        local heroAddBtn = makeButton(page, "Add", 42, 18, function()
            local id = IchaUI_HeroBarAdd and IchaUI_HeroBarAdd()
            if id then
                IchaUI_HeroPick = id
                if IchaUI_HeroFocus then IchaUI_HeroFocus(id) end
            end
            paintHeroPicks()
            if IchaUIOptions and IchaUIOptions.refresh then IchaUIOptions.refresh() end
        end)
        heroAddBtn:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, y - 20)
        heroRemoveBtn = makeButton(page, "Remove", 58, 18, function()
            local pick = IchaUI_HeroPick or 1
            if pick > 1 and IchaUI_HeroBarRemove then IchaUI_HeroBarRemove(pick) end
            IchaUI_HeroPick = 1
            if IchaUI_HeroFocus then IchaUI_HeroFocus(1) end
            paintHeroPicks()
            if IchaUIOptions and IchaUIOptions.refresh then IchaUIOptions.refresh() end
        end)
        heroRemoveBtn:SetPoint("LEFT", heroAddBtn, "RIGHT", 4, 0)
        heroRemoveBtn:Hide()
        paintHeroPicks()
        return y - 42
    end
    y1 = placeHeroPicks(pageHero, y1)
    makeSliderRow(pageHero, "Scale", PAD, y1, SLW, 0.5, 3.0, 0.05,
        function()
            local pick = IchaUI_HeroPick or 1
            if pick <= 1 then return (db().heroScale or 1.55) end
            if IchaUI_HeroBarScale then return IchaUI_HeroBarScale(pick) or 1.55 end
            return 1.55
        end,
        function(v)
            local pick = IchaUI_HeroPick or 1
            if pick <= 1 then
                if SlashCmdList and SlashCmdList["ICHA"] then SlashCmdList["ICHA"]("heroscale " .. v) end
            elseif IchaUI_HeroBarSetScale then
                IchaUI_HeroBarSetScale(pick, v)
            end
        end)
    y1 = y1 - ROW
    makeSliderRow(pageHero, "Cols", PAD, y1, SLW, 1, 12, 1,
        function()
            local pick = IchaUI_HeroPick or 1
            if IchaUI_HeroBarGrid then
                local c = IchaUI_HeroBarGrid(pick)
                return c or 4
            end
            if IchaUI_HeroGrid then
                local c = IchaUI_HeroGrid()
                return c
            end
            return 4
        end,
        function(v)
            if IchaUI_HeroSetCols then IchaUI_HeroSetCols(v) end
        end)
    y1 = y1 - ROW
    makeSliderRow(pageHero, "Rows", PAD, y1, SLW, 1, 5, 1,
        function()
            local pick = IchaUI_HeroPick or 1
            if IchaUI_HeroBarGrid then
                local c, r = IchaUI_HeroBarGrid(pick)
                return r or 2
            end
            if IchaUI_HeroGrid then
                local c, r = IchaUI_HeroGrid()
                return r
            end
            return 2
        end,
        function(v)
            if IchaUI_HeroSetRows then IchaUI_HeroSetRows(v) end
        end)
    y1 = y1 - ROW
    makeButton(pageHero, "Hero setup", 92, 20, function()
        local pick = IchaUI_HeroPick or 1
        if IchaUI_HeroFocus then IchaUI_HeroFocus(pick) end
        if IchaUI_HeroSetup_Toggle then IchaUI_HeroSetup_Toggle() end
    end):SetPoint("TOPLEFT", pageHero, "TOPLEFT", PAD, y1)
    y1 = y1 - 24
    local heroShape = makeButton(pageHero, "Shape: Square", 140, 20, function()
        local id = IchaUI_HeroPick or 1
        local shape, layout, spread, arc, rot = "square", "grid", 90, 360, 90
        if IchaUI_HeroBarForm then shape, layout, spread, arc, rot = IchaUI_HeroBarForm(id) end
        if IchaUI_FormShapeNext then shape = IchaUI_FormShapeNext(shape) end
        if IchaUI_HeroBarSetForm then IchaUI_HeroBarSetForm(id, shape, layout, spread, arc, rot) end
        local lab = shape
        if IchaUI_FormShapeLabel then lab = IchaUI_FormShapeLabel(shape) end
        this:SetText("Shape: " .. lab)
    end)
    heroShape:SetPoint("TOPLEFT", pageHero, "TOPLEFT", PAD, y1)
    local heroLay = makeButton(pageHero, "Layout: Grid", 120, 20, function()
        local id = IchaUI_HeroPick or 1
        local shape, layout, spread, arc, rot = "square", "grid", 90, 360, 90
        if IchaUI_HeroBarForm then shape, layout, spread, arc, rot = IchaUI_HeroBarForm(id) end
        if layout == "radial" then layout = "grid" else layout = "radial" end
        if IchaUI_HeroBarSetForm then IchaUI_HeroBarSetForm(id, shape, layout, spread, arc, rot) end
        if layout == "radial" then this:SetText("Layout: Radial") else this:SetText("Layout: Grid") end
    end)
    heroLay:SetPoint("LEFT", heroShape, "RIGHT", 4, 0)
    y1 = y1 - ROW
    makeSliderRow(pageHero, "Spread", PAD, y1, SLW, 10, 360, 1,
        function()
            local id = IchaUI_HeroPick or 1
            local spread = 90
            if IchaUI_HeroBarForm then local _, _, s = IchaUI_HeroBarForm(id); spread = s end
            return spread or 90
        end,
        function(v)
            local id = IchaUI_HeroPick or 1
            local shape, layout, spread, arc, rot = "square", "grid", 90, 360, 90
            if IchaUI_HeroBarForm then shape, layout, spread, arc, rot = IchaUI_HeroBarForm(id) end
            if IchaUI_HeroBarSetForm then IchaUI_HeroBarSetForm(id, shape, layout, v, arc, rot) end
        end)
    y1 = y1 - ROW
    makeSliderRow(pageHero, "Arc", PAD, y1, SLW, 10, 360, 1,
        function()
            local id = IchaUI_HeroPick or 1
            local arc = 360
            if IchaUI_HeroBarForm then local _, _, _, a = IchaUI_HeroBarForm(id); arc = a end
            return arc or 360
        end,
        function(v)
            local id = IchaUI_HeroPick or 1
            local shape, layout, spread, arc, rot = "square", "grid", 90, 360, 90
            if IchaUI_HeroBarForm then shape, layout, spread, arc, rot = IchaUI_HeroBarForm(id) end
            if IchaUI_HeroBarSetForm then IchaUI_HeroBarSetForm(id, shape, layout, spread, v, rot) end
        end)
    y1 = y1 - ROW
    makeSliderRow(pageHero, "Sh Rot", PAD, y1, SLW, -360, 360, 1,
        function()
            local id = IchaUI_HeroPick or 1
            local rot = 90
            if IchaUI_HeroBarForm then local _, _, _, _, r = IchaUI_HeroBarForm(id); rot = r end
            return rot or 90
        end,
        function(v)
            local id = IchaUI_HeroPick or 1
            local shape, layout, spread, arc, rot = "square", "grid", 90, 360, 90
            if IchaUI_HeroBarForm then shape, layout, spread, arc, rot = IchaUI_HeroBarForm(id) end
            if IchaUI_HeroBarSetForm then IchaUI_HeroBarSetForm(id, shape, layout, spread, arc, v) end
        end)
    y1 = y1 - ROW
    tip(pageHero, "Same scale, columns, rows, and setup on each hero bar. Shape and radial layout follow the hero you have selected. Edit positions on Bars moves them.", PAD, y1, 500)
    y1 = y1 - 36
    tip(pageHero, "Hero setup shows the bar. Drag a slot to move its abilities. Edit abilities, pick several, then Save. Macros and bag consumables are in that picker. Spell keys still use Target, Mouseover, or Focus.", PAD, y1, 500)


    ------------------------------------------------------------------
    -- TAB 2: Buffs
    ------------------------------------------------------------------
    local pageBuffs = makePage("Buffs", 220)
    local yBf = -4

    sectionHeader(pageBuffs, "Buff / debuff bars", PAD, yBf); yBf = yBf - 18
    local bfScale = makeSliderRow(pageBuffs, "Scale", PAD, yBf, SLW, 0.4, 2.5, 0.05,
        function()
            local t = IchaUIBuffBars_Get and IchaUIBuffBars_Get()
            return (t and t.scale) or 1
        end,
        function(v) if IchaUIBuffBars_Set then IchaUIBuffBars_Set("scale", v) end end)
    yBf = yBf - ROW
    local bfGap = makeSliderRow(pageBuffs, "Gap", PAD, yBf, SLW, 0, 16, 0.5,
        function()
            local t = IchaUIBuffBars_Get and IchaUIBuffBars_Get()
            return (t and t.gap) or 3
        end,
        function(v) if IchaUIBuffBars_Set then IchaUIBuffBars_Set("gap", v) end end)
    yBf = yBf - ROW
    local bfRowGap = makeSliderRow(pageBuffs, "Row", PAD, yBf, SLW, 0, 40, 1,
        function()
            local t = IchaUIBuffBars_Get and IchaUIBuffBars_Get()
            return (t and t.rowGap) or 4
        end,
        function(v) if IchaUIBuffBars_Set then IchaUIBuffBars_Set("rowGap", v) end end)
    yBf = yBf - ROW
    yBf = -4
    local bfCols = makeSliderRow(pageBuffs, "Cols", COL2, yBf, SLW, 4, 16, 1,
        function()
            local t = IchaUIBuffBars_Get and IchaUIBuffBars_Get()
            return (t and t.cols) or 16
        end,
        function(v) if IchaUIBuffBars_Set then IchaUIBuffBars_Set("cols", v) end end)
    yBf = yBf - ROW
    local bfText = makeSliderRow(pageBuffs, "Text", COL2, yBf, SLW, 8, 18, 1,
        function()
            local t = IchaUIBuffBars_Get and IchaUIBuffBars_Get()
            return (t and t.text) or 10
        end,
        function(v) if IchaUIBuffBars_Set then IchaUIBuffBars_Set("text", v) end end)
    yBf = yBf - ROW
    local bfMove = makeButton(pageBuffs, "Move", 55, 20, function()
        if IchaUIBuffBars_Slash then IchaUIBuffBars_Slash("move") end
    end)
    bfMove:SetPoint("TOPLEFT", pageBuffs, "TOPLEFT", COL2, yBf)
    tip(pageBuffs, "Right-click a buff to cancel it", COL2 + 64, yBf - 2, 280)
    yBf = yBf - 30



    ------------------------------------------------------------------
    -- TAB 3: Frames (sub-tabs per unit; text settings live on this page)
    -- Map Reset + Skin Tooltips live in their own tabs — do not touch.
    ------------------------------------------------------------------
    local pageFrames = makePage("Frames", 1600)

    -- Refresh registries (avoid dozens of named locals → upvalue blowups)
    local framesXyRefresh = {}
    local framesBtnRefresh = {}
    local framesSubPages = {}
    local framesSubBtns = {}
    local framesActiveSub = db().framesSubTab or "player"
    if framesActiveSub ~= "player" and framesActiveSub ~= "target" and framesActiveSub ~= "tot"
        and framesActiveSub ~= "party" and framesActiveSub ~= "raid" and framesActiveSub ~= "combat"
        and framesActiveSub ~= "focus" then
        framesActiveSub = "player"
    end

    if IchaUI_BuildFrameEditor and IchaUIUF_Get then
        IchaUI_BuildFrameEditor(pageFrames, framesActiveSub, framesXyRefresh, framesBtnRefresh)
    end

    -- Expose refresh hooks for panel.refresh (Map/Skin untouched)
    pageFrames._framesXyRefresh = framesXyRefresh
    pageFrames._framesBtnRefresh = framesBtnRefresh



    ------------------------------------------------------------------
    -- TAB 5: Drawers (was Totems — nested to stay under build()'s 200 locals)
    ------------------------------------------------------------------
    local function fillDrawersPage()
        local page = makePage("Drawers", 1680)
        local yL = -4
        local slotRows = {}
        local dirRefresh = {}

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
        local function makeDirBtn(parent, x, y, getDir, setDir)
            local btn = makeButton(parent, "Open: " .. prettyDir(getDir()), 120, 20, function()
                local n = cycleDir(getDir())
                setDir(n)
                this:SetText("Open: " .. prettyDir(n))
            end)
            btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
            table.insert(dirRefresh, function()
                btn:SetText("Open: " .. prettyDir(getDir()))
            end)
            return btn
        end
        local spreadRefresh = {}
        local textRefresh = {}
        local function makeDeg(parent, title, x, y, lo, hi, getS, setS)
            local row = makeSliderRow(parent, title, x, y, SLW, lo, hi, 1, getS, setS, 1, 1, 1)
            if row and row.refresh then table.insert(spreadRefresh, row.refresh) end
        end
        local function makeSpread(parent, x, y, getS, setS)
            makeDeg(parent, "Spread", x, y, 10, 360, getS, setS)
        end
        local function makeArc(parent, x, y, getS, setS)
            makeDeg(parent, "Arc", x, y, 10, 360, getS, setS)
        end
        local function makeRot(parent, x, y, getS, setS)
            makeDeg(parent, "Sh Rot", x, y, -360, 360, getS, setS)
        end

        sectionHeader(page, "Totems", PAD, yL); yL = yL - 18
        makeSliderRow(page, "Scale", PAD, yL, SLW, 0.4, 3.0, 0.05,
            function()
                local t = IchaUITotems_Get and IchaUITotems_Get()
                return (t and t.scale) or 1
            end,
            function(v) if IchaUITotems_Set then IchaUITotems_Set("scale", v) end end)
        yL = yL - ROW
        makeSliderRow(page, "Size", PAD, yL, SLW, 20, 80, 1,
            function()
                local t = IchaUITotems_Get and IchaUITotems_Get()
                return (t and t.size) or 36
            end,
            function(v) if IchaUITotems_Set then IchaUITotems_Set("size", v) end end)
        yL = yL - ROW
        makeSliderRow(page, "Gap", PAD, yL, SLW, 0, 40, 0.5,
            function()
                local t = IchaUITotems_Get and IchaUITotems_Get()
                return (t and t.gap) or 6
            end,
            function(v) if IchaUITotems_Set then IchaUITotems_Set("gap", v) end end)
        yL = yL - ROW
        makeSliderRow(page, "Text", PAD, yL, SLW, 8, 24, 1,
            function()
                local t = IchaUITotems_Get and IchaUITotems_Get()
                return (t and t.textSize) or 11
            end,
            function(v) if IchaUITotems_Set then IchaUITotems_Set("textSize", v) end end)
        yL = yL - ROW
        makeStrataRow(page, "T.strata", PAD, yL,
            function()
                if IchaUI_GetTotemTextStrata then
                    local n, idx = IchaUI_GetTotemTextStrata()
                    return idx or 4
                end
                return 4
            end,
            function(v)
                if IchaUI_SetTotemTextStrata then IchaUI_SetTotemTextStrata(v) end
            end)
        yL = yL - ROW
        makeSliderRow(page, "Drawer", PAD, yL, SLW, 14, 48, 1,
            function()
                local t = IchaUITotems_Get and IchaUITotems_Get()
                return t and t.drawerSize or 22
            end,
            function(v) if IchaUITotems_Set then IchaUITotems_Set("drawerSize", v) end end)
        yL = yL - ROW
        makeSliderRow(page, "D.Gap", PAD, yL, SLW, 0, 12, 1,
            function()
                local t = IchaUITotems_Get and IchaUITotems_Get()
                return t and t.drawerGap or 2
            end,
            function(v) if IchaUITotems_Set then IchaUITotems_Set("drawerGap", v) end end)
        yL = yL - ROW
        makeSliderRow(page, "CD badge", PAD, yL, SLW, 0.4, 1.5, 0.05,
            function()
                local t = IchaUITotems_Get and IchaUITotems_Get()
                return (t and t.cdBadgeScale) or 0.85
            end,
            function(v) if IchaUITotems_Set then IchaUITotems_Set("cdBadgeScale", v) end end)
        yL = yL - ROW

        local totMove = makeButton(page, "Move", 55, 20, function()
            if IchaUITotems_Slash then IchaUITotems_Slash("move") end
        end)
        totMove:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, yL)
        local totShow = makeButton(page, "Show", 48, 20, function()
            if IchaUITotems_Set then IchaUITotems_Set("hidden", false) end
        end)
        totShow:SetPoint("LEFT", totMove, "RIGHT", 4, 0)
        local totHide = makeButton(page, "Hide", 48, 20, function()
            if IchaUITotems_Set then IchaUITotems_Set("hidden", true) end
        end)
        totHide:SetPoint("LEFT", totShow, "RIGHT", 4, 0)
        yL = yL - 22
        tip(page, "T.strata: totem duration / tick numbers (default HIGH, below tooltips). Icon layer is Bars → Strata.", PAD, yL, 520)
        yL = yL - 26

        local throwBind = makeKeyBindRow(page, "Throw current", PAD, yL,
            function()
                if IchaUITotems_GetThrowKey then return IchaUITotems_GetThrowKey() end
                return "T"
            end,
            function(key)
                if IchaUITotems_SetThrowKey then IchaUITotems_SetThrowKey(key) end
            end)
        local totThrow = makeButton(page, "Throw now", 80, 20, function()
            if IchaUITotems_ThrowSet then IchaUITotems_ThrowSet() end
        end)
        totThrow:SetPoint("TOPLEFT", page, "TOPLEFT", PAD + 230, yL + 3)
        yL = yL - 26
        if IchaUI_BuildTotemSetsBlock then
            yL = IchaUI_BuildTotemSetsBlock(page, PAD, yL, sectionHeader, makeButton, makeEdit, makeKeyBindRow, slotRows)
        end
        makeDirBtn(page, PAD, yL,
            function()
                local t = IchaUITotems_Get and IchaUITotems_Get()
                return (t and t.drawerDir) or "up"
            end,
            function(d)
                if IchaUITotems_Set then IchaUITotems_Set("drawerDir", d) end
            end)
        yL = yL - 24
        makeSpread(page, PAD, yL,
            function()
                local t = IchaUITotems_Get and IchaUITotems_Get()
                return (t and t.drawerSpread) or 90
            end,
            function(v)
                if IchaUITotems_Set then IchaUITotems_Set("drawerSpread", v) end
            end)
        yL = yL - 26
        makeArc(page, PAD, yL,
            function()
                local t = IchaUITotems_Get and IchaUITotems_Get()
                return (t and t.drawerArc) or 360
            end,
            function(v)
                if IchaUITotems_Set then IchaUITotems_Set("drawerArc", v) end
            end)
        yL = yL - 26
        makeRot(page, PAD, yL,
            function()
                local t = IchaUITotems_Get and IchaUITotems_Get()
                if t and t.drawerRot ~= nil then return t.drawerRot end
                return 90
            end,
            function(v)
                if IchaUITotems_Set then IchaUITotems_Set("drawerRot", v) end
            end)
        yL = yL - 26
        local shiftDr = makeButton(page, "Shift drawers: Off", 140, 20, function()
            local t = IchaUITotems_Get and IchaUITotems_Get()
            local on = not (t and t.shiftDrawer)
            if IchaUITotems_Set then IchaUITotems_Set("shiftDrawer", on) end
            this:SetText(on and "Shift drawers: On" or "Shift drawers: Off")
        end)
        shiftDr:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, yL)
        yL = yL - 22
        tip(page, "Open: element drawers grow from the slot. Default Up. Shift: also imbue / shield / utility.", PAD, yL, 520)
        yL = yL - 16
        tip(page, "Off = hover opens. On = hold Shift. Click = cast. Right-click drawer row = set throw.", PAD, yL, 500)
        yL = yL - 28
        if IchaUI_DrawerStyleControls then
            yL = IchaUI_DrawerStyleControls(page, "totems", PAD, yL, true)
        end
        yL = yL - 8

        local yC = -4
        sectionHeader(page, "Recall", COL2, yC); yC = yC - 20
        local recallOn = makeGoldToggle(page, "Recall: On", 120, 20)
        local function refreshRecallOn()
            local on = IchaUI_TotemRecallGet and IchaUI_TotemRecallGet()
            if recallOn._label then
                recallOn._label:SetText(on and "Recall: On" or "Recall: Off")
            end
            paintGoldToggle(recallOn, on and true or false)
        end
        recallOn:SetScript("OnClick", function()
            local on = not (IchaUI_TotemRecallGet and IchaUI_TotemRecallGet())
            if IchaUI_TotemRecallSet then IchaUI_TotemRecallSet(on) end
            refreshRecallOn()
        end)
        recallOn:SetPoint("TOPLEFT", page, "TOPLEFT", COL2, yC)
        yC = yC - ROW
        makeSliderRow(page, "Wait", COL2, yC, SLW, 1, 30, 1,
            function()
                if IchaUI_TotemRecallDelay then return IchaUI_TotemRecallDelay() end
                return 5
            end,
            function(v)
                if IchaUI_TotemRecallDelaySet then IchaUI_TotemRecallDelaySet(v) end
            end)
        yC = yC - ROW
        tip(page, "Wait: seconds out of range of every live totem (out of combat) before the icon appears.", COL2, yC, 500)
        yC = yC - 28
        local recallMove = makeButton(page, "Move icon", 90, 20, function()
            if IchaUI_TotemRecallIcon_ToggleMove then
                local moving = IchaUI_TotemRecallIcon_ToggleMove()
                this:SetText(moving and "Lock icon" or "Move icon")
            end
        end)
        recallMove:SetPoint("TOPLEFT", page, "TOPLEFT", COL2, yC)
        yC = yC - ROW
        makeSliderRow(page, "Icon", COL2, yC, SLW, 0.5, 2.5, 0.05,
            function()
                if IchaUI_TotemRecallIcon_Scale then return IchaUI_TotemRecallIcon_Scale() end
                return 1
            end,
            function(v)
                if IchaUI_TotemRecallIcon_ScaleSet then IchaUI_TotemRecallIcon_ScaleSet(v) end
            end)
        yC = yC - ROW
        if IchaUI_DrawerStyleControls then
            yC = IchaUI_DrawerStyleControls(page, "recall", COL2, yC)
        end
        yC = yC - 8

        local function extrasRow(which, label)
            sectionHeader(page, label, COL2, yC); yC = yC - 20
            local mv = makeButton(page, "Move", 55, 20, function()
                if IchaUIShamanExtras_ToggleMove then IchaUIShamanExtras_ToggleMove(which) end
            end)
            mv:SetPoint("TOPLEFT", page, "TOPLEFT", COL2, yC)
            local sh = makeButton(page, "Show", 48, 20, function()
                if IchaUIShamanExtras_SetHidden then IchaUIShamanExtras_SetHidden(which, false) end
            end)
            sh:SetPoint("LEFT", mv, "RIGHT", 4, 0)
            local hi = makeButton(page, "Hide", 48, 20, function()
                if IchaUIShamanExtras_SetHidden then IchaUIShamanExtras_SetHidden(which, true) end
            end)
            hi:SetPoint("LEFT", sh, "RIGHT", 4, 0)
            yC = yC - 24
            if which == "utility" and IchaUIShamanExtras_UtilityEntries and IchaUIShamanExtras_SetUtilityShown then
                local cap = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                cap:SetPoint("TOPLEFT", page, "TOPLEFT", COL2, yC)
                cap:SetText("Show in drawer")
                IchaUI_PaintGoldFont(cap, 0.93, 0.78, 0.35)
                yC = yC - 14
                local keys = IchaUIShamanExtras_UtilityEntries()
                local UCOLS, UCW, UROW = 3, 160, 20
                local ui
                for ui = 1, table.getn(keys) do
                    local key = keys[ui]
                    local col = math.mod(ui - 1, UCOLS)
                    local row = math.floor((ui - 1) / UCOLS)
                    local cb = CreateFrame("CheckButton", nil, page)
                    cb:SetWidth(20)
                    cb:SetHeight(20)
                    cb:SetPoint("TOPLEFT", page, "TOPLEFT", COL2 + col * UCW, yC - row * UROW)
                    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
                    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
                    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
                    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
                    local lbl = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
                    lbl:SetText(key)
                    IchaUI_DyeFs(lbl, 1, 1, 1)
                    cb:SetChecked(IchaUIShamanExtras_GetUtilityShown(key) and 1 or nil)
                    cb:SetScript("OnClick", function()
                        IchaUIShamanExtras_SetUtilityShown(key, this:GetChecked() and true or false)
                    end)
                    table.insert(textRefresh, function()
                        cb:SetChecked(IchaUIShamanExtras_GetUtilityShown(key) and 1 or nil)
                    end)
                end
                yC = yC - math.floor((table.getn(keys) + UCOLS - 1) / UCOLS) * UROW - 4
            end
            makeDirBtn(page, COL2, yC,
                function()
                    if IchaUIShamanExtras_GetDrawerDir then return IchaUIShamanExtras_GetDrawerDir(which) end
                    return "up"
                end,
                function(d)
                    if IchaUIShamanExtras_SetDrawerDir then IchaUIShamanExtras_SetDrawerDir(which, d) end
                end)
            yC = yC - 26
            makeSpread(page, COL2, yC,
                function()
                    if IchaUIShamanExtras_GetDrawerSpread then return IchaUIShamanExtras_GetDrawerSpread(which) end
                    return 90
                end,
                function(v)
                    if IchaUIShamanExtras_SetDrawerSpread then IchaUIShamanExtras_SetDrawerSpread(which, v) end
                end)
            yC = yC - 26
            makeArc(page, COL2, yC,
                function()
                    if IchaUIShamanExtras_GetDrawerArc then return IchaUIShamanExtras_GetDrawerArc(which) end
                    return 360
                end,
                function(v)
                    if IchaUIShamanExtras_SetDrawerArc then IchaUIShamanExtras_SetDrawerArc(which, v) end
                end)
            yC = yC - 26
            makeRot(page, COL2, yC,
                function()
                    if IchaUIShamanExtras_GetDrawerRot then return IchaUIShamanExtras_GetDrawerRot(which) end
                    return 90
                end,
                function(v)
                    if IchaUIShamanExtras_SetDrawerRot then IchaUIShamanExtras_SetDrawerRot(which, v) end
                end)
            yC = yC - 26
            if which == "imbue" or which == "shield" then
                local textBtn = makeButton(page, "Text: On", 80, 20, function()
                    local on = false
                    if IchaUIShamanExtras_GetShowText then
                        on = not IchaUIShamanExtras_GetShowText(which)
                    end
                    if IchaUIShamanExtras_SetShowText then
                        IchaUIShamanExtras_SetShowText(which, on)
                    end
                    this:SetText(on and "Text: On" or "Text: Off")
                end)
                textBtn:SetPoint("TOPLEFT", page, "TOPLEFT", COL2, yC)
                yC = yC - 24
                table.insert(textRefresh, function()
                    local on = IchaUIShamanExtras_GetShowText and IchaUIShamanExtras_GetShowText(which)
                    textBtn:SetText(on and "Text: On" or "Text: Off")
                end)
            end
            if IchaUI_DrawerStyleControls then
                yC = IchaUI_DrawerStyleControls(page, which, COL2, yC)
            end
            yC = yC - 6
        end
        extrasRow("utility", "Utility")
        extrasRow("imbue", "Imbue")
        extrasRow("shield", "Shield")
        tip(page, "Detached circles. Open default Up. Red when imbue <60s / shield ≤2 / water buff <60s or 0 reagents.", COL2, yC, 500)
        yC = yC - 28

        sectionHeader(page, "Resists", COL2, yC); yC = yC - 20
        local mobStatsBtn = makeButton(page, "Mob stats: On", 120, 20, function()
            if not IchaUIUF_GetTankDrawerEnabled or not IchaUIUF_SetTankDrawerEnabled then return end
            local on = not IchaUIUF_GetTankDrawerEnabled()
            IchaUIUF_SetTankDrawerEnabled(on)
            this:SetText(on and "Mob stats: On" or "Mob stats: Off")
        end)
        mobStatsBtn:SetPoint("TOPLEFT", page, "TOPLEFT", COL2, yC)
        yC = yC - 24
        local minResBtn = makeButton(page, "Minimal resists: Off", 150, 20, function()
            if not IchaUIUF_GetTankDrawerMinimal or not IchaUIUF_SetTankDrawerMinimal then return end
            local on = not IchaUIUF_GetTankDrawerMinimal()
            IchaUIUF_SetTankDrawerMinimal(on)
            this:SetText(on and "Minimal resists: On" or "Minimal resists: Off")
        end)
        minResBtn:SetPoint("TOPLEFT", page, "TOPLEFT", COL2, yC)
        yC = yC - 24
        makeDirBtn(page, COL2, yC,
            function()
                if IchaUIUF_GetTankDrawerSide then return IchaUIUF_GetTankDrawerSide() end
                return "left"
            end,
            function(d)
                if IchaUIUF_SetTankDrawerSide then IchaUIUF_SetTankDrawerSide(d) end
            end)
        yC = yC - 22
        makeSpread(page, COL2, yC,
            function()
                if IchaUIUF_GetTankDrawerSpread then return IchaUIUF_GetTankDrawerSpread() end
                return 90
            end,
            function(v)
                if IchaUIUF_SetTankDrawerSpread then IchaUIUF_SetTankDrawerSpread(v) end
            end)
        yC = yC - 26
        makeArc(page, COL2, yC,
            function()
                if IchaUIUF_GetTankDrawerArc then return IchaUIUF_GetTankDrawerArc() end
                return 360
            end,
            function(v)
                if IchaUIUF_SetTankDrawerArc then IchaUIUF_SetTankDrawerArc(v) end
            end)
        yC = yC - 26
        makeRot(page, COL2, yC,
            function()
                if IchaUIUF_GetTankDrawerRot then return IchaUIUF_GetTankDrawerRot() end
                return 90
            end,
            function(v)
                if IchaUIUF_SetTankDrawerRot then IchaUIUF_SetTankDrawerRot(v) end
            end)
        yC = yC - 26
        tip(page, "Default Open: Left (inside). Minimal On = resists nestled by caret when closed.", COL2, yC, 500)
        yC = yC - 20
        if IchaUI_DrawerStyleControls then
            yC = IchaUI_DrawerStyleControls(page, "resists", COL2, yC)
        end
        yC = yC - 8

        sectionHeader(page, "Slot binds", PAD, yL); yL = yL - 18
        local slotBindLabels = { "Earth", "Fire", "Water", "Air" }
        local slotBindEls = { "earth", "fire", "water", "air" }
        local sbi
        for sbi = 1, 4 do
            local el = slotBindEls[sbi]
            local label = slotBindLabels[sbi]
            local row = makeKeyBindRow(page, label, PAD, yL,
                function()
                    if IchaUITotems_GetSlotKey then return IchaUITotems_GetSlotKey(el) end
                    return ""
                end,
                function(key)
                    if IchaUITotems_ApplySlotKey then IchaUITotems_ApplySlotKey(el, key) end
                end)
            table.insert(slotRows, row)
            yL = yL - 24
        end
        tip(page, "Casts the totem selected on that slot (right-click drawer to set).", PAD, yL, 500)
        yL = yL - 22

        sectionHeader(page, "Spell binds", PAD, yL); yL = yL - 18
        tip(page, "Binds cast that totem directly so you can drop action-bar buttons.", PAD, yL, 500)
        yL = yL - 20
        local spellBindList = (IchaUITotems_ListSpellBinds and IchaUITotems_ListSpellBinds()) or {}
        local spellElHeaders = { earth = "Earth", fire = "Fire", water = "Water", air = "Air" }
        local lastSpellEl = nil
        local spi
        for spi = 1, table.getn(spellBindList) do
            local item = spellBindList[spi]
            if item.element ~= lastSpellEl then
                lastSpellEl = item.element
                local hdr = spellElHeaders[item.element] or item.element
                sectionHeader(page, hdr, PAD, yL); yL = yL - 18
            end
            local idx = item.index
            local rowLabel = item.label
            if (not rowLabel) and item.base then
                rowLabel = string.gsub(item.base, "%s+Totem%s*$", "")
            end
            if not rowLabel then rowLabel = tostring(idx) end
            local row = makeKeyBindRow(page, rowLabel, PAD, yL,
                function()
                    if IchaUITotems_GetSpellKey then return IchaUITotems_GetSpellKey(idx) end
                    return ""
                end,
                function(key)
                    if IchaUITotems_ApplySpellKey then IchaUITotems_ApplySpellKey(idx, key) end
                end)
            table.insert(slotRows, row)
            yL = yL - 24
        end
        yL = yL - 10

        if IchaUI_BuildDrawerExtras then
            yC = IchaUI_BuildDrawerExtras(page, yC, COL2)
        end
        local needH = -yL
        if -yC > needH then needH = -yC end
        needH = needH + 80
        if page.GetHeight and (page:GetHeight() or 0) < needH then
            page:SetHeight(needH)
        end



        pages._drawersRefresh = function()
            local i
            for i = 1, table.getn(dirRefresh) do
                dirRefresh[i]()
            end
            for i = 1, table.getn(spreadRefresh) do
                spreadRefresh[i]()
            end
            for i = 1, table.getn(textRefresh) do
                textRefresh[i]()
            end
            if shiftDr and IchaUITotems_Get then
                local tg = IchaUITotems_Get()
                shiftDr:SetText((tg and tg.shiftDrawer) and "Shift drawers: On" or "Shift drawers: Off")
            end
            if throwBind and throwBind.refresh then throwBind.refresh() end
            if IchaUI_TotemSetsRefresh then IchaUI_TotemSetsRefresh() end
            for i = 1, table.getn(slotRows) do
                if slotRows[i] and slotRows[i].refresh then slotRows[i].refresh() end
            end
            refreshRecallOn()
            if recallMove then
                if IchaUI_TotemRecallIcon_Moving and IchaUI_TotemRecallIcon_Moving() then
                    recallMove:SetText("Lock icon")
                else
                    recallMove:SetText("Move icon")
                end
            end
            if IchaUIUF_GetTankDrawerEnabled then
                mobStatsBtn:SetText(IchaUIUF_GetTankDrawerEnabled() and "Mob stats: On" or "Mob stats: Off")
            end
            if IchaUIUF_GetTankDrawerMinimal then
                minResBtn:SetText(IchaUIUF_GetTankDrawerMinimal() and "Minimal resists: On" or "Minimal resists: Off")
            end
            if IchaUI_DrawerExtrasRefresh then IchaUI_DrawerExtrasRefresh() end
        end
        pages._drawersRefresh()
    end
    fillDrawersPage()

    ------------------------------------------------------------------
    -- TAB 6: Map
    ------------------------------------------------------------------
    local function fillMapDrawer(pageMap)
        local y = -4
        local function pretty(d)
            if d == "radial" then return "Radial" end
            if d == "right" then return "Right" end
            if d == "down" then return "Down" end
            if d == "left" then return "Left" end
            return "Up"
        end
        local function nextDir(d)
            if d == "up" then return "right" end
            if d == "right" then return "down" end
            if d == "down" then return "left" end
            if d == "left" then return "radial" end
            return "up"
        end
        sectionHeader(pageMap, "Minimap drawer", COL2, y); y = y - 20
        local drawerOn = makeGoldToggle(pageMap, "Drawer: On", 100, 20)
        drawerOn:SetScript("OnClick", function()
            if not IchaUIMinimap_GetDrawer or not IchaUIMinimap_SetDrawer then return end
            local g = IchaUIMinimap_GetDrawer()
            local on = not (g and g.enabled)
            IchaUIMinimap_SetDrawer("enabled", on)
            if this._label then
                this._label:SetText(on and "Drawer: On" or "Drawer: Off")
            end
            paintGoldToggle(this, on)
            if pages._mapRefresh then pages._mapRefresh() end
        end)
        drawerOn:SetPoint("TOPLEFT", pageMap, "TOPLEFT", COL2, y)
        local drawerOpen = makeButton(pageMap, "Open/Close", 90, 20, function()
            if not IchaUIMinimap_SetDrawer then return end
            IchaUIMinimap_SetDrawer("toggle", true)
        end)
        drawerOpen:SetPoint("LEFT", drawerOn, "RIGHT", 4, 0)
        local drawerRescan = makeButton(pageMap, "Rescan", 70, 20, function()
            if IchaUIMinimap_SetDrawer then
                IchaUIMinimap_SetDrawer("rescan", true)
            elseif IchaUIMinimapButtons_Refresh then
                IchaUIMinimapButtons_Refresh()
            end
            if pages._mapRefresh then pages._mapRefresh() end
        end)
        drawerRescan:SetPoint("LEFT", drawerOpen, "RIGHT", 4, 0)
        y = y - 24
        local dirBtn = makeButton(pageMap, "Open: Down", 120, 20, function()
            local g = IchaUIMinimap_GetDrawer and IchaUIMinimap_GetDrawer()
            local d = nextDir((g and g.drawerDir) or "down")
            if IchaUIMinimap_SetDrawer then IchaUIMinimap_SetDrawer("drawerDir", d) end
            this:SetText("Open: " .. pretty(d))
        end)
        dirBtn:SetPoint("TOPLEFT", pageMap, "TOPLEFT", COL2, y)
        y = y - 24
        local mmSpread = makeSliderRow(pageMap, "Spread", COL2, y, SLW, 10, 360, 1,
            function()
                local g = IchaUIMinimap_GetDrawer and IchaUIMinimap_GetDrawer()
                return (g and g.drawerSpread) or 90
            end,
            function(v)
                if IchaUIMinimap_SetDrawer then IchaUIMinimap_SetDrawer("drawerSpread", v) end
            end, 1, 1, 1)
        y = y - 26
        local mmArc = makeSliderRow(pageMap, "Arc", COL2, y, SLW, 10, 360, 1,
            function()
                local g = IchaUIMinimap_GetDrawer and IchaUIMinimap_GetDrawer()
                return (g and g.drawerArc) or 360
            end,
            function(v)
                if IchaUIMinimap_SetDrawer then IchaUIMinimap_SetDrawer("drawerArc", v) end
            end, 1, 1, 1)
        y = y - 26
        local mmRot = makeSliderRow(pageMap, "Sh Rot", COL2, y, SLW, -360, 360, 1,
            function()
                local g = IchaUIMinimap_GetDrawer and IchaUIMinimap_GetDrawer()
                if g and g.drawerRot ~= nil then return g.drawerRot end
                return 90
            end,
            function(v)
                if IchaUIMinimap_SetDrawer then IchaUIMinimap_SetDrawer("drawerRot", v) end
            end, 1, 1, 1)
        y = y - 26
        tip(pageMap, "Buttons in Drawer sit in the arrow tray. Default Open: Down (under the map).", COL2, y, 500)
        y = y - 24
        if IchaUI_DrawerStyleControls then
            y = IchaUI_DrawerStyleControls(pageMap, "minimap", COL2, y)
        end
        y = y - 8
        sectionHeader(pageMap, "Minimap buttons", COL2, y); y = y - 20
        tip(pageMap, "Move unlocks every icon to drag. Lock restores clicks. Reset puts a button back on the minimap.", COL2, y, 500)
        y = y - 16
        local resetAllMm = makeButton(pageMap, "Reset all positions", 140, 20, function()
            if IchaUIMinimap_ResetButtonPos then IchaUIMinimap_ResetButtonPos(nil) end
            if pages._mapRefresh then pages._mapRefresh() end
        end)
        resetAllMm:SetPoint("TOPLEFT", pageMap, "TOPLEFT", COL2, y)
        local iconsMove = makeButton(pageMap, "Move", 55, 20, function()
            if IchaUIMinimap_SetDrawer then
                IchaUIMinimap_SetDrawer("iconMove", true)
            end
            if pages._mapRefresh then pages._mapRefresh() end
        end)
        iconsMove:SetPoint("LEFT", resetAllMm, "RIGHT", 4, 0)
        y = y - ROW
        local function truncLabel(s, maxLen)
            s = tostring(s or "")
            maxLen = maxLen or 22
            if string.len(s) > maxLen then
                return string.sub(s, 1, maxLen - 2) .. ".."
            end
            return s
        end
        local mmBtnContainer = CreateFrame("Frame", nil, pageMap)
        mmBtnContainer:SetPoint("TOPLEFT", pageMap, "TOPLEFT", COL2, y)
        mmBtnContainer:SetWidth(480)
        mmBtnContainer:SetHeight(40)
        local listTop = y
        local mmBtnKids = {}
        local function wipeMmBtnKids()
            local i
            for i = 1, table.getn(mmBtnKids) do
                local c = mmBtnKids[i]
                if c then
                    c:Hide()
                    c:ClearAllPoints()
                end
            end
            mmBtnKids = {}
        end
        local function refresh()
            if drawerOn and IchaUIMinimap_GetDrawer then
                local g = IchaUIMinimap_GetDrawer()
                local on = g and g.enabled
                if drawerOn._label then
                    drawerOn._label:SetText(on and "Drawer: On" or "Drawer: Off")
                end
                paintGoldToggle(drawerOn, on and true or false)
                if dirBtn then
                    dirBtn:SetText("Open: " .. pretty((g and g.drawerDir) or "down"))
                end
                if mmSpread and mmSpread.refresh then mmSpread.refresh() end
                if mmArc and mmArc.refresh then mmArc.refresh() end
                if mmRot and mmRot.refresh then mmRot.refresh() end
                if iconsMove then
                    iconsMove:SetText((g and g.iconMoving) and "Lock" or "Move")
                end
            elseif iconsMove then
                iconsMove:SetText("Move")
            end
            wipeMmBtnKids()
            local n = 0
            if IchaUIMinimap_ListButtons then
                local list = IchaUIMinimap_ListButtons()
                if list then n = table.getn(list) end
                local yi = 0
                local ri
                for ri = 1, n do
                    local info = list[ri]
                    if info then
                        local row = CreateFrame("Frame", nil, mmBtnContainer)
                        row:SetWidth(500)
                        row:SetHeight(20)
                        row:SetPoint("TOPLEFT", mmBtnContainer, "TOPLEFT", 0, yi)
                        row._id = info.id
                        row._inDrawer = info.inDrawer and true or false
                        row._freeMove = info.freeMove and true or false
                        row._moving = info.moving and true or false
                        local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        nameFS:SetPoint("LEFT", row, "LEFT", 0, 0)
                        nameFS:SetWidth(180)
                        nameFS:SetJustifyH("LEFT")
                        nameFS:SetText(truncLabel(info.label or info.id or "?", 22))
                        IchaUI_DyeFs(nameFS, 0.9, 0.88, 0.8)
                        local drawerBtn = makeGoldToggle(row, "Drawer", 64, 18)
                        drawerBtn:SetPoint("LEFT", nameFS, "RIGHT", 6, 0)
                        paintGoldToggle(drawerBtn, row._inDrawer)
                        drawerBtn:SetScript("OnClick", function()
                            local r = this:GetParent()
                            if not r or not r._id or not IchaUIMinimap_SetButton then return end
                            IchaUIMinimap_SetButton(r._id, "inDrawer", not r._inDrawer)
                            if pages._mapRefresh then pages._mapRefresh() end
                        end)
                        local freeBtn = makeGoldToggle(row, "Free", 54, 18)
                        freeBtn:SetPoint("LEFT", drawerBtn, "RIGHT", 4, 0)
                        paintGoldToggle(freeBtn, row._freeMove)
                        freeBtn:SetScript("OnClick", function()
                            local r = this:GetParent()
                            if not r or not r._id or not IchaUIMinimap_SetButton then return end
                            IchaUIMinimap_SetButton(r._id, "freeMove", not r._freeMove)
                            if pages._mapRefresh then pages._mapRefresh() end
                        end)
                        local moveBtn = makeButton(row, row._moving and "Lock" or "Move", 50, 18, function()
                            local r = this:GetParent()
                            if not r or not r._id or not IchaUIMinimap_SetButton then return end
                            IchaUIMinimap_SetButton(r._id, "move", true)
                            if pages._mapRefresh then pages._mapRefresh() end
                        end)
                        moveBtn:SetPoint("LEFT", freeBtn, "RIGHT", 4, 0)
                        local resetBtn = makeButton(row, "Reset", 50, 18, function()
                            local r = this:GetParent()
                            if not r or not r._id or not IchaUIMinimap_SetButton then return end
                            IchaUIMinimap_SetButton(r._id, "reset", true)
                            if pages._mapRefresh then pages._mapRefresh() end
                        end)
                        resetBtn:SetPoint("LEFT", moveBtn, "RIGHT", 4, 0)
                        table.insert(mmBtnKids, row)
                        yi = yi - 22
                    end
                end
                local needH = 24 + (n * 22)
                if needH < 40 then needH = 40 end
                mmBtnContainer:SetHeight(needH)
            end
            local need = -(listTop) + 24 + (n * 22) + 40
            if need < 400 then need = 400 end
            if pageMap.GetHeight and (pageMap:GetHeight() or 0) < need then
                pageMap:SetHeight(need)
            end
        end
        pages._mapRefresh = refresh
        refresh()
    end

    local pageMap = makePage("Map", 1600)
    local yMp = -4

    sectionHeader(pageMap, "Minimap", PAD, yMp); yMp = yMp - 20
    local mmOn = makeButton(pageMap, "Minimap: On", 100, 20, function()
        if IchaUIMinimap_Set then
            local g = IchaUIMinimap_Get and IchaUIMinimap_Get()
            local on = not (g and g.enabled)
            IchaUIMinimap_Set("enabled", on)
            this:SetText(on and "Minimap: On" or "Minimap: Off")
        end
    end)
    mmOn:SetPoint("TOPLEFT", pageMap, "TOPLEFT", PAD, yMp)
    local mmMove = makeButton(pageMap, "Move", 55, 20, function()
        if IchaUIMinimap_Set then
            IchaUIMinimap_Set("move", true)
            local g = IchaUIMinimap_Get and IchaUIMinimap_Get()
            this:SetText((g and g.mapMoving) and "Lock" or "Move")
        end
    end)
    mmMove:SetPoint("LEFT", mmOn, "RIGHT", 4, 0)
    local mmReset = makeButton(pageMap, "Reset", 55, 20, function()
        if IchaUIMinimap_Reset then
            IchaUIMinimap_Reset("map")
        elseif IchaUIMinimap_Set then
            IchaUIMinimap_Set("resetMap", true)
        end
        if mmMove then mmMove:SetText("Move") end
    end)
    mmReset:SetPoint("LEFT", mmMove, "RIGHT", 4, 0)
    local mmShapeBtn = makeButton(pageMap, "Shape: Square", 196, 20, function()
        if IchaUIMinimap_OpenShapePicker then
            IchaUIMinimap_OpenShapePicker()
        end
    end)
    mmShapeBtn:SetPoint("LEFT", mmReset, "RIGHT", 4, 0)
    if IchaUIMinimap_ShapeName then
        mmShapeBtn:SetText("Shape: " .. IchaUIMinimap_ShapeName())
    end
    IchaUI_MinimapShapeButton = mmShapeBtn
    local mmTintBtn = makeButton(pageMap, "Tint", 78, 20, function()
        if not IchaUI_OpenColorPicker or not IchaUIMinimap_Get or not IchaUIMinimap_SetArtTint then return end
        if IchaUIMinimapShapePicker and IchaUIMinimapShapePicker.Hide then
            IchaUIMinimapShapePicker:Hide()
        end
        local g = IchaUIMinimap_Get()
        local r, gv, b = 1, 1, 1
        if g then
            if g.artR then r = g.artR end
            if g.artG then gv = g.artG end
            if g.artB then b = g.artB end
        end
        IchaUI_OpenColorPicker(r, gv, b, function(nr, ng, nb)
            IchaUIMinimap_SetArtTint(nr, ng, nb)
        end)
    end)
    mmTintBtn:SetPoint("LEFT", mmShapeBtn, "RIGHT", 4, 0)
    mmTintBtn._label:ClearAllPoints()
    mmTintBtn._label:SetPoint("LEFT", mmTintBtn, "LEFT", 6, 0)
    local mmTintSw = mmTintBtn:CreateTexture(nil, "OVERLAY")
    mmTintSw:SetTexture("Interface\\Buttons\\WHITE8X8")
    mmTintSw:SetWidth(14)
    mmTintSw:SetHeight(14)
    mmTintSw:SetPoint("RIGHT", mmTintBtn, "RIGHT", -5, 0)
    mmTintSw:SetVertexColor(1, 1, 1, 1)
    IchaUI_MinimapTintSwatch = mmTintSw
    if IchaUIMinimap_Get then
        local g = IchaUIMinimap_Get()
        if g then
            mmTintSw:SetVertexColor(g.artR or 1, g.artG or 1, g.artB or 1, 1)
        end
    end
    yMp = yMp - ROW
    local mmScale = makeSliderRow(pageMap, "MM Scale", PAD, yMp, SLW, 0.4, 2.5, 0.05,
        function()
            local g = IchaUIMinimap_Get and IchaUIMinimap_Get()
            return (g and g.scale) or 1
        end,
        function(v) if IchaUIMinimap_Set then IchaUIMinimap_Set("scale", v) end end)
    yMp = yMp - ROW
    local mmSize = makeSliderRow(pageMap, "MM Size", PAD, yMp, SLW, 80, 280, 5,
        function()
            local g = IchaUIMinimap_Get and IchaUIMinimap_Get()
            return (g and g.size) or 140
        end,
        function(v) if IchaUIMinimap_Set then IchaUIMinimap_Set("size", v) end end)
    yMp = yMp - 8
    tip(pageMap, "Shape opens a preview of every minimap frame. Click one to use it. Tint colors that frame art. Move to drag, Lock to freeze. Reset = default position.", PAD, yMp, 520)
    yMp = yMp - 24

    sectionHeader(pageMap, "Zone title", PAD, yMp); yMp = yMp - 20
    local zoneOn = makeButton(pageMap, "Zone: On", 90, 20, function()
        if IchaUIMinimap_Set then
            local g = IchaUIMinimap_Get and IchaUIMinimap_Get()
            local on = not (g and g.zoneShow)
            IchaUIMinimap_Set("zoneShow", on)
            this:SetText(on and "Zone: On" or "Zone: Off")
        end
    end)
    zoneOn:SetPoint("TOPLEFT", pageMap, "TOPLEFT", PAD, yMp)
    local zoneMove = makeButton(pageMap, "Move", 55, 20, function()
        if IchaUIMinimap_Set then
            IchaUIMinimap_Set("zoneMove", true)
            local g = IchaUIMinimap_Get and IchaUIMinimap_Get()
            this:SetText((g and g.zoneMoving) and "Lock" or "Move")
        end
    end)
    zoneMove:SetPoint("LEFT", zoneOn, "RIGHT", 4, 0)
    local zoneReset = makeButton(pageMap, "Reset", 55, 20, function()
        if IchaUIMinimap_Reset then
            IchaUIMinimap_Reset("zone")
        elseif IchaUIMinimap_Set then
            IchaUIMinimap_Set("resetZone", true)
        end
        if zoneMove then zoneMove:SetText("Move") end
    end)
    zoneReset:SetPoint("LEFT", zoneMove, "RIGHT", 4, 0)
    yMp = yMp - ROW
    local zoneScale = makeSliderRow(pageMap, "Zone Scale", PAD, yMp, SLW, 0.4, 2.5, 0.05,
        function()
            local g = IchaUIMinimap_Get and IchaUIMinimap_Get()
            return (g and g.zoneScale) or 1
        end,
        function(v) if IchaUIMinimap_Set then IchaUIMinimap_Set("zoneScale", v) end end)
    yMp = yMp - ROW
    tip(pageMap, "Zone defaults above the map. Locked = click-through. Move to drag, Lock when done.", PAD, yMp, 520)
    yMp = yMp - 24

    sectionHeader(pageMap, "Clock", PAD, yMp); yMp = yMp - 20
    local clockOn = makeButton(pageMap, "Clock: On", 90, 20, function()
        if IchaUIMinimap_Set then
            local g = IchaUIMinimap_Get and IchaUIMinimap_Get()
            local on = not (g and g.clockShow)
            IchaUIMinimap_Set("clockShow", on)
            this:SetText(on and "Clock: On" or "Clock: Off")
        end
    end)
    clockOn:SetPoint("TOPLEFT", pageMap, "TOPLEFT", PAD, yMp)
    local clockMove = makeButton(pageMap, "Move", 55, 20, function()
        if IchaUIMinimap_Set then
            IchaUIMinimap_Set("clockMove", true)
            local g = IchaUIMinimap_Get and IchaUIMinimap_Get()
            this:SetText((g and g.clockMoving) and "Lock" or "Move")
        end
    end)
    clockMove:SetPoint("LEFT", clockOn, "RIGHT", 4, 0)
    local clockReset = makeButton(pageMap, "Reset", 55, 20, function()
        if IchaUIMinimap_Reset then
            IchaUIMinimap_Reset("clock")
        elseif IchaUIMinimap_Set then
            IchaUIMinimap_Set("resetClock", true)
        end
        if clockMove then clockMove:SetText("Move") end
    end)
    clockReset:SetPoint("LEFT", clockMove, "RIGHT", 4, 0)
    yMp = yMp - ROW
    local clockScale = makeSliderRow(pageMap, "Clock Scale", PAD, yMp, SLW, 0.4, 2.5, 0.05,
        function()
            local g = IchaUIMinimap_Get and IchaUIMinimap_Get()
            return (g and g.clockScale) or 1
        end,
        function(v) if IchaUIMinimap_Set then IchaUIMinimap_Set("clockScale", v) end end)
    yMp = yMp - ROW
    tip(pageMap, "Clock defaults under the map. Locked = click-through. Move to drag, Lock when done.", PAD, yMp, 520)
    yMp = yMp - 28

    fillMapDrawer(pageMap)

    ------------------------------------------------------------------
    -- TAB 7: Combat (helpers only - auto-dismount / melee / OOR)
    ------------------------------------------------------------------
    local pageCombat = makePage("Combat", 320)
    local yCb = -4

    tip(pageCombat, "Combat helpers. Gold = enabled.", PAD, yCb, 520)
    yCb = yCb - 20

    sectionHeader(pageCombat, "Assist", PAD, yCb); yCb = yCb - 20

    local function combatFlag(key)
        if key == "smartTab" then
            return (IchaUIDB and IchaUIDB.smartTab) and true or false
        end
        if key == "smartTabTank" then
            return (IchaUIDB and IchaUIDB.smartTabTank) and true or false
        end
        if key == "smartTabLow" then
            return (IchaUIDB and IchaUIDB.smartTabLow) and true or false
        end
        if key == "hideBarTips" then
            if IchaUI_CombatTooltipsGet then
                return IchaUI_CombatTooltipsGet() and true or false
            end
            return false
        end
        local c = IchaUI_CombatDB and IchaUI_CombatDB()
        if not c then return true end
        if c[key] == nil then return true end
        return c[key] and true or false
    end

    local function combatSet(key, on)
        if key == "smartTab" or key == "smartTabTank" or key == "smartTabLow" then
            if not IchaUIDB then IchaUIDB = {} end
            if key == "smartTab" then
                IchaUIDB.smartTab = on and true or false
                if IchaUI_SmartTabApply then IchaUI_SmartTabApply() end
            elseif key == "smartTabTank" then
                IchaUIDB.smartTabTank = on and true or false
            else
                IchaUIDB.smartTabLow = on and true or false
            end
            return
        end
        if key == "hideBarTips" then
            if IchaUI_CombatTooltipsSet then IchaUI_CombatTooltipsSet(on) end
            return
        end
        local c = IchaUI_CombatDB and IchaUI_CombatDB()
        if not c then return end
        c[key] = on and true or false
    end

    local combatRefreshList = {}
    local combatSlot = 0

    local function makeCombatToggle(label, key)
        local btn = makeGoldToggle(pageCombat, label .. ": On", 180, 20)
        local function refresh()
            local on = combatFlag(key)
            if btn._label then
                btn._label:SetText(on and (label .. ": On") or (label .. ": Off"))
            end
            paintGoldToggle(btn, on)
            if key == "smartTabTank" or key == "smartTabLow" then
                if combatFlag("smartTab") then
                    if btn.Enable then btn:Enable() end
                else
                    if btn.Disable then btn:Disable() end
                    if btn._label then IchaUI_DyeFs(btn._label, 0.55, 0.55, 0.55) end
                    if btn.SetBackdropColor then btn:SetBackdropColor(0.05, 0.05, 0.05, 0.7) end
                    if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.6) end
                end
            end
        end
        btn:SetScript("OnClick", function()
            if (key == "smartTabTank" or key == "smartTabLow") and not combatFlag("smartTab") then
                return
            end
            local on = not combatFlag(key)
            combatSet(key, on)
            refresh()
            if key == "smartTab" and pageCombat._combatRefresh then
                pageCombat._combatRefresh()
            end
        end)
        local x = PAD
        local y = -48
        if key == "smartTabTank" or key == "smartTabLow" then
            x = PAD + 22
            if key == "smartTabTank" then y = -128 else y = -152 end
        else
            local col = math.mod(combatSlot, 2)
            local row = math.floor(combatSlot / 2)
            combatSlot = combatSlot + 1
            if col == 1 then x = COL2 end
            y = -48 - row * 28
        end
        btn:SetPoint("TOPLEFT", pageCombat, "TOPLEFT", x, y)
        table.insert(combatRefreshList, refresh)
        refresh()
        if (key == "smartTab" or key == "smartTabTank" or key == "smartTabLow") and not IchaUI_SmartTabApply then
            btn:Hide()
        end
        return btn
    end

    makeCombatToggle("Auto-dismount", "autoDismount")
    makeCombatToggle("Melee start attack", "meleeStartAttack")
    makeCombatToggle("OOR grey icons", "oorGrey")
    makeCombatToggle("Bar tips", "hideBarTips")
    makeCombatToggle("Smart Tab", "smartTab")
    makeCombatToggle("Tank mode", "smartTabTank")
    makeCombatToggle("Lowest first", "smartTabLow")
    if IchaUI_CombatColorOptions then
        IchaUI_CombatColorOptions(pageCombat, PAD, COL2, -184)
    end

    tip(pageCombat, "Smart Tab cycles the tracker by current HP. A death starts the next Tab at the front of that order. An empty tracker uses normal Tab.", PAD, -216, 520)
    tip(pageCombat, "Lowest first starts at the lowest HP and walks up. Off keeps highest HP first. It does nothing while Smart Tab is off.", PAD, -258, 520)
    tip(pageCombat, "Tank mode puts enemies not on you first, then ones on you. Lowest first flips HP inside each group.", PAD, -300, 520)
    tip(pageCombat, "On you and Loose recolor every tracker mob. Defaults match the old red and yellow.", PAD, -342, 520)
    tip(pageCombat, "OOR grey: action-bar icons tint when target is out of range (Layout).", PAD, -384, COL_TIP)
    tip(pageCombat, "In combat, action bar tooltips stay hidden unless you hold Shift.", PAD, -412, 520)
    tip(pageCombat, "Totemic Recall icon: Drawers tab.", PAD, -440, 520)

    tip(pageCombat, "Smart Mark (enemy and friendly binds, icon order): Mark tab.", PAD, -468, 520)

    pageCombat._combatRefresh = function()
        local i
        for i = 1, table.getn(combatRefreshList) do
            combatRefreshList[i]()
        end
        if pageCombat._trackerColorRefresh then pageCombat._trackerColorRefresh() end
    end
    pages._combatRefresh = pageCombat._combatRefresh

    -- TAB: Mark (Smart Mark icon order + binds)
    pages._markRefresh = buildSmartMarkPage(makePage("Mark", 320), makeGoldToggle, paintGoldToggle)

    ------------------------------------------------------------------
    -- TAB 8: Skin
    ------------------------------------------------------------------
    local pageSkin = makePage("Skin", 480)
    local ySk = -4

    sectionHeader(pageSkin, "Chat skin", PAD, ySk); ySk = ySk - 20
    local chatOn = makeButton(pageSkin, "Border: On", 90, 20, function()
        if IchaUIChatSkin_Set then
            local g = IchaUIChatSkin_Get and IchaUIChatSkin_Get()
            local on = not (g and g.enabled)
            IchaUIChatSkin_Set("enabled", on)
            this:SetText(on and "Border: On" or "Border: Off")
        end
    end)
    chatOn:SetPoint("TOPLEFT", pageSkin, "TOPLEFT", PAD, ySk)
    ySk = ySk - ROW
    local chatAlpha = makeSliderRow(pageSkin, "Alpha", PAD, ySk, SLW, 0.2, 1.0, 0.05,
        function()
            local g = IchaUIChatSkin_Get and IchaUIChatSkin_Get()
            return (g and g.alpha) or 0.72
        end,
        function(v) if IchaUIChatSkin_Set then IchaUIChatSkin_Set("alpha", v) end end)
    ySk = ySk - ROW

    ySk = ySk - 12
    sectionHeader(pageSkin, "TWThreat / Caw DPS skin", PAD, ySk); ySk = ySk - 20
    local frameSkinBtn = makeButton(pageSkin, "Skin TWThreat+Caw: On", 200, 20, function()
        if not IchaUIFrameSkin_Get or not IchaUIFrameSkin_Set then return end
        local g = IchaUIFrameSkin_Get()
        local on = not (g and g.enabled)
        IchaUIFrameSkin_Set("enabled", on)
        this:SetText(on and "Skin TWThreat+Caw: On" or "Skin TWThreat+Caw: Off")
    end)
    frameSkinBtn:SetPoint("TOPLEFT", pageSkin, "TOPLEFT", PAD, ySk)
    ySk = ySk - 24
    tip(pageSkin, "Gold Tooltip-Border on TWThreat + Caw DPS (window + dropdown menus). Character/Spellbook stay stock.", PAD, ySk, PANEL_W - 40)
    ySk = ySk - 28

    sectionHeader(pageSkin, "Tooltips", PAD, ySk); ySk = ySk - 20
    local tipSkinBtn = makeButton(pageSkin, "Tooltips: On", 120, 20, function()
        if not IchaUI_TooltipSkin_Get and not IchaUITooltipSkin_Get then return end
        local g = (IchaUI_TooltipSkin_Get and IchaUI_TooltipSkin_Get()) or (IchaUITooltipSkin_Get and IchaUITooltipSkin_Get())
        local on = not (g and g.enabled)
        if IchaUI_TooltipSkin_SetEnabled then
            IchaUI_TooltipSkin_SetEnabled(on)
        elseif IchaUITooltipSkin_Set then
            IchaUITooltipSkin_Set("enabled", on)
        end
        this:SetText(on and "Tooltips: On" or "Tooltips: Off")
    end)
    tipSkinBtn:SetPoint("TOPLEFT", pageSkin, "TOPLEFT", PAD, ySk)
    ySk = ySk - 24
    tip(pageSkin, "Gold border / dark fill on GameTooltip and common tips. Default On.", PAD, ySk, PANEL_W - 40)
    ySk = ySk - 28

    sectionHeader(pageSkin, "Gold", PAD, ySk); ySk = ySk - 20
    local goldLabel = pageSkin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    goldLabel:SetPoint("TOPLEFT", pageSkin, "TOPLEFT", PAD, ySk)
    goldLabel:SetText("Theme gold")
    IchaUI_PaintGoldFont(goldLabel, 0.93, 0.78, 0.35)
    local goldBtn = CreateFrame("Button", "IchaUIGoldSwatch", pageSkin)
    goldBtn:SetWidth(72)
    goldBtn:SetHeight(18)
    goldBtn:SetPoint("LEFT", goldLabel, "RIGHT", 8, 0)
    goldBtn:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    goldBtn:SetBackdropColor(0.05, 0.05, 0.06, 1)
    IchaUI_PaintGoldBorder(goldBtn, 1)
    local goldTex = goldBtn:CreateTexture(nil, "ARTWORK")
    goldTex:SetPoint("TOPLEFT", goldBtn, "TOPLEFT", 4, -4)
    goldTex:SetPoint("BOTTOMRIGHT", goldBtn, "BOTTOMRIGHT", -4, 4)
    goldTex:SetTexture(1, 1, 1, 1)
    local function paintGoldSwatch()
        local r, g, b = 0.75, 0.52, 0.04
        if IchaUI_Gold then r, g, b = IchaUI_Gold() end
        goldTex:SetVertexColor(r, g, b, 1)
    end
    paintGoldSwatch()
    IchaUI_GoldSwatchPaint = paintGoldSwatch
    goldBtn:SetScript("OnClick", function()
        if not IchaUI_OpenColorPicker then return end
        local was = false
        if IchaUI_ThemeGoldOn and IchaUI_ThemeGoldOn() then was = true end
        local r, g, b = 0.75, 0.52, 0.04
        if was and IchaUI_Gold then r, g, b = IchaUI_Gold() end
        IchaUI_OpenColorPicker(r, g, b, function(nr, ng, nb)
            if IchaUI_SetGold then IchaUI_SetGold(nr, ng, nb) end
        end, function()
            if was then
                if IchaUI_SetGold then IchaUI_SetGold(r, g, b) end
            elseif IchaUI_ClearGold then
                IchaUI_ClearGold()
            end
        end)
    end)
    ySk = ySk - 28
    local fillLabel = pageSkin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fillLabel:SetPoint("TOPLEFT", pageSkin, "TOPLEFT", PAD, ySk)
    fillLabel:SetText("Fill")
    fillLabel:SetTextColor(1, 1, 1)
    local fillBtn = CreateFrame("Button", "IchaUIFillSwatch", pageSkin)
    fillBtn:SetWidth(72)
    fillBtn:SetHeight(18)
    fillBtn:SetPoint("LEFT", fillLabel, "RIGHT", 8, 0)
    fillBtn:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    fillBtn:SetBackdropColor(0.07, 0.07, 0.08, 1)
    IchaUI_PaintGoldBorder(fillBtn, 1)
    local fillTex = fillBtn:CreateTexture(nil, "ARTWORK")
    fillTex:SetPoint("TOPLEFT", fillBtn, "TOPLEFT", 4, -4)
    fillTex:SetPoint("BOTTOMRIGHT", fillBtn, "BOTTOMRIGHT", -4, 4)
    fillTex:SetTexture(1, 1, 1, 1)
    local function paintFillSwatch()
        local r, g, b = 0.07, 0.07, 0.08
        if IchaUI_Fill then r, g, b = IchaUI_Fill() end
        fillTex:SetVertexColor(r, g, b, 1)
    end
    paintFillSwatch()
    IchaUI_FillSwatchPaint = paintFillSwatch
    fillBtn:SetScript("OnClick", function()
        if not IchaUI_OpenColorPicker then return end
        local r, g, b = 0.07, 0.07, 0.08
        if IchaUI_Fill then r, g, b = IchaUI_Fill() end
        IchaUI_OpenColorPicker(r, g, b, function(nr, ng, nb)
            if IchaUI_SetFill then IchaUI_SetFill(nr, ng, nb) end
        end, function()
            if IchaUI_SetFill then IchaUI_SetFill(r, g, b) end
        end)
    end)
    ySk = ySk - 28
    tip(pageSkin, "Borders, rings, and chrome use this gold. Fill is the dark panel behind the gold edge. Brighter gold text follows the border. Both stay as they are until you pick a color.", PAD, ySk, PANEL_W - 40)
    ySk = ySk - 36

    ySk = -4
    tip(pageSkin, "Imbue / shield / utility drawers: Drawers tab.", COL2, ySk, PANEL_W - 40)
    ySk = ySk - 24

    sectionHeader(pageSkin, "Raid / watch debuffs", COL2, ySk); ySk = ySk - 16
    tip(pageSkin, "One debuff name per line.", COL2, ySk, PANEL_W - 40)
    ySk = ySk - 18

    local raidBoxW = 480
    local raidBox = CreateFrame("Frame", nil, pageSkin)
    raidBox:SetPoint("TOPLEFT", pageSkin, "TOPLEFT", COL2, ySk)
    raidBox:SetWidth(raidBoxW)
    raidBox:SetHeight(200)
    goldBorder(raidBox, 10)

    local raidEdit = CreateFrame("EditBox", "IchaUIRaidDebuffEdit", raidBox)
    raidEdit:SetMultiLine(true)
    raidEdit:SetAutoFocus(false)
    local raidFp, raidFsz, raidFl = GameFontHighlightSmall:GetFont()
    if raidFp then raidEdit:SetFont(raidFp, raidFsz or 10, raidFl or "") end
    IchaUI_DyeFs(raidEdit, 1, 1, 1)
    raidEdit:SetWidth(raidBoxW - 16)
    raidEdit:SetHeight(188)
    raidEdit:SetPoint("TOPLEFT", raidBox, "TOPLEFT", 6, -6)
    raidEdit:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    ySk = ySk - 210

    local saveRaid = makeButton(pageSkin, "Save list", 80, 20, function()
        local text = raidEdit:GetText() or ""
        local list = {}
        text = string.gsub(text, "\r\n", "\n")
        text = string.gsub(text, "\r", "\n")
        local start = 1
        while true do
            local ns, ne = string.find(text, "\n", start, true)
            local line
            if not ns then
                line = string.sub(text, start)
            else
                line = string.sub(text, start, ns - 1)
            end
            line = string.gsub(line, "^%s+", "")
            line = string.gsub(line, "%s+$", "")
            if line ~= "" then table.insert(list, line) end
            if not ns then break end
            start = ne + 1
        end
        if IchaUIUF_SetRaidDebuffs then IchaUIUF_SetRaidDebuffs(list) end
        DEFAULT_CHAT_FRAME:AddMessage("Debuff watch list saved (" .. table.getn(list) .. ").")
    end)
    saveRaid:SetPoint("TOPLEFT", pageSkin, "TOPLEFT", COL2, ySk)

    IchaUI_SyncTextKind = function(kind)
        if kind and kind ~= "" then framesActiveSub = kind end
    end

    panel.refresh = function()
        local i
        for i = 1, table.getn(sliderRefreshList) do
            sliderRefreshList[i]()
        end
        -- Frames sub-tab XY + button registries
        if pageFrames and pageFrames._framesXyRefresh then
            local fi
            for fi = 1, table.getn(pageFrames._framesXyRefresh) do
                pageFrames._framesXyRefresh[fi]()
            end
        end
        if pageFrames and pageFrames._framesBtnRefresh then
            local fi
            for fi = 1, table.getn(pageFrames._framesBtnRefresh) do
                pageFrames._framesBtnRefresh[fi]()
            end
        end
        if IchaUIMinimap_Get and mmOn then
            local g = IchaUIMinimap_Get()
            mmOn:SetText((g and g.enabled) and "Minimap: On" or "Minimap: Off")
            if mmMove then mmMove:SetText((g and g.mapMoving) and "Lock" or "Move") end
            if IchaUI_MinimapShapeButton and IchaUIMinimap_ShapeName then
                IchaUI_MinimapShapeButton:SetText("Shape: " .. IchaUIMinimap_ShapeName())
            end
            if IchaUI_MinimapTintSwatch and IchaUIMinimap_Get then
                local tg = IchaUIMinimap_Get()
                if tg then
                    IchaUI_MinimapTintSwatch:SetVertexColor(tg.artR or 1, tg.artG or 1, tg.artB or 1, 1)
                end
            end
        end
        if IchaUIMinimap_Get and zoneOn then
            local g = IchaUIMinimap_Get()
            zoneOn:SetText((g and g.zoneShow) and "Zone: On" or "Zone: Off")
            if zoneMove then zoneMove:SetText((g and g.zoneMoving) and "Lock" or "Move") end
        end
        if IchaUIMinimap_Get and clockOn then
            local g = IchaUIMinimap_Get()
            clockOn:SetText((g and g.clockShow) and "Clock: On" or "Clock: Off")
            if clockMove then clockMove:SetText((g and g.clockMoving) and "Lock" or "Move") end
        end
        if IchaUIFrameSkin_Get and frameSkinBtn then
            local g = IchaUIFrameSkin_Get()
            frameSkinBtn:SetText((g and g.enabled) and "Skin TWThreat+Caw: On" or "Skin TWThreat+Caw: Off")
        end
        if tipSkinBtn and (IchaUI_TooltipSkin_Get or IchaUITooltipSkin_Get) then
            local g = (IchaUI_TooltipSkin_Get and IchaUI_TooltipSkin_Get()) or IchaUITooltipSkin_Get()
            tipSkinBtn:SetText((g and g.enabled) and "Tooltips: On" or "Tooltips: Off")
        end
        if IchaUIChatSkin_Get and chatOn then
            local g = IchaUIChatSkin_Get()
            chatOn:SetText((g and g.enabled) and "Border: On" or "Border: Off")
        end
        if IchaUI_HeroPickRefresh then IchaUI_HeroPickRefresh() end
        if IchaUI_ActionAddRefresh then IchaUI_ActionAddRefresh() end
        if pages._drawersRefresh then pages._drawersRefresh() end
        if pages._mapRefresh then pages._mapRefresh() end
        if IchaUIUF_GetRaidDebuffsText and raidEdit then
            raidEdit:SetText(IchaUIUF_GetRaidDebuffsText())
        end
        -- Row tables kept as lists to avoid upvalue blowups
        local shri
        if shieldRows then
            for shri = 1, table.getn(shieldRows) do
                if shieldRows[shri] and shieldRows[shri].refresh then shieldRows[shri].refresh() end
            end
        end
        if pageCombat and pageCombat._combatRefresh then pageCombat._combatRefresh() end
        if pages._markRefresh then pages._markRefresh() end
    end



    local function buildProfileBar()
        local bar = CreateFrame("Frame", nil, panel)
        bar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", CONTENT_PAD + tabCol, 8)
        bar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -CONTENT_PAD, 8)
        bar:SetHeight(44)
        local lbl = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", bar, "LEFT", 2, 0)
        lbl:SetText("Profile")
        IchaUI_PaintGoldFont(lbl, 0.93, 0.78, 0.35)
        local nameEdit = makeEdit(bar, 150, 20)
        nameEdit:SetPoint("LEFT", lbl, "RIGHT", 6, 0)
        if nameEdit.SetMaxLetters then nameEdit:SetMaxLetters(48) end
        local saveBtn, loadBtn, delBtn, listBtn
        local list, listScroll, listChild
        local rows = {}
        local activeFS = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        IchaUI_DyeFs(activeFS, 0.82, 0.80, 0.72)
        local function say(msg)
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("IchaUI: " .. msg)
            end
        end
        local function nameCount(names)
            local c = 0
            if type(names) ~= "table" then return 0 end
            while names[c + 1] ~= nil do
                c = c + 1
                if c > 500 then break end
            end
            return c
        end
        local function paintActive()
            local n = nil
            if type(IchaUI_ProfileActive) == "function" then n = IchaUI_ProfileActive() end
            if n and n ~= "" then
                activeFS:SetText("Active: " .. n)
            else
                activeFS:SetText("")
            end
            if listBtn and type(IchaUI_ProfileNames) == "function" then
                local c = nameCount(IchaUI_ProfileNames())
                if c > 0 then
                    listBtn:SetText("List (" .. c .. ")")
                else
                    listBtn:SetText("List")
                end
            end
        end
        local function bindName(btn, nm)
            btn:SetScript("OnClick", function()
                nameEdit:SetText(nm)
                list:Hide()
            end)
        end
        local function goldRow(parent)
            local b = CreateFrame("Button", nil, parent)
            b:SetWidth(168)
            b:SetHeight(18)
            b:SetBackdrop({
                bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                tile = true, tileSize = 8, edgeSize = 10,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("CENTER", b, "CENTER", 0, 0)
            b._label = fs
            paintTab(b, false)
            return b
        end
        local function paintList()
            local names = {}
            if type(IchaUI_ProfileNames) == "function" then
                names = IchaUI_ProfileNames() or {}
            end
            local n = 0
            while names[n + 1] ~= nil do
                n = n + 1
                if n > 500 then break end
            end
            local i, b, nm, picked
            picked = nameEdit:GetText() or ""
            for i = 1, n do
                b = rows[i]
                if not b then
                    b = goldRow(listChild)
                    rows[i] = b
                end
                nm = names[i]
                b._label:SetText(nm)
                paintTab(b, nm == picked)
                bindName(b, nm)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", listChild, "TOPLEFT", 4, -((i - 1) * 20) - 4)
                b:Show()
            end
            i = n + 1
            while rows[i] do
                rows[i]:Hide()
                i = i + 1
                if i > 500 then break end
            end
            if not list._empty then
                list._empty = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                list._empty:SetPoint("CENTER", list, "CENTER", 0, 0)
                list._empty:SetText("No profiles")
                list._empty:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
            end
            if n < 1 then list._empty:Show() else list._empty:Hide() end
            local h = n * 20 + 8
            if h < 28 then h = 28 end
            listChild:SetWidth(176)
            listChild:SetHeight(h)
            local vis = h
            if vis > 200 then vis = 200 end
            list:SetHeight(vis + 8)
        end
        list = CreateFrame("Frame", "IchaUIProfileList", panel)
        list:SetWidth(188)
        list:SetHeight(40)
        list:SetFrameStrata("FULLSCREEN_DIALOG")
        list:SetFrameLevel((panel:GetFrameLevel() or 200) + 30)
        goldBorder(list, 12)
        list:Hide()
        list:EnableMouse(true)
        listScroll = CreateFrame("ScrollFrame", "IchaUIProfileListScroll", list)
        listScroll:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -4)
        listScroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -4, 4)
        listScroll:EnableMouseWheel(true)
        listChild = CreateFrame("Frame", nil, listScroll)
        listChild:SetWidth(176)
        listChild:SetHeight(28)
        listScroll:SetScrollChild(listChild)
        listScroll:SetScript("OnMouseWheel", function()
            local cur = this:GetVerticalScroll() or 0
            local maxS = this:GetVerticalScrollRange() or 0
            if maxS < 0 then maxS = 0 end
            local nextY = cur - (arg1 or 0) * 20
            if nextY < 0 then nextY = 0 end
            if nextY > maxS then nextY = maxS end
            this:SetVerticalScroll(nextY)
        end)
        local function doSave()
            local name = nameEdit:GetText() or ""
            if type(IchaUI_ProfileSave) ~= "function" then
                say("Profiles are not loaded.")
                return
            end
            local force = bar._confirmName and bar._confirmName == name
            local ok, why = IchaUI_ProfileSave(name, force)
            if ok then
                bar._confirmName = nil
                saveBtn:SetText("Save")
                if force then
                    say('Replaced profile "' .. name .. '".')
                else
                    say('Saved profile "' .. name .. '".')
                end
                paintActive()
                if list:IsShown() then paintList() end
            elseif why == "exists" then
                bar._confirmName = name
                saveBtn:SetText("Overwrite")
                say('"' .. name .. '" exists. Click Overwrite to replace it.')
            elseif why == "empty" then
                say("Type a profile name first.")
            elseif why == "notready" then
                say("Profiles are still loading. Close this and open /iui again.")
            end
        end
        saveBtn = makeButton(bar, "Save", 88, 20, doSave)
        saveBtn:SetPoint("LEFT", nameEdit, "RIGHT", 6, 0)
        loadBtn = makeButton(bar, "Load", 52, 20, function()
            local name = nameEdit:GetText() or ""
            if type(IchaUI_ProfileLoad) ~= "function" then
                say("Profiles are not loaded.")
                return
            end
            local ok, why = IchaUI_ProfileLoad(name)
            if ok then
                bar._confirmName = nil
                saveBtn:SetText("Save")
                say('Loaded profile "' .. name .. '".')
                paintActive()
                if list:IsShown() then list:Hide() end
            elseif why == "missing" then
                say('No saved profile named "' .. name .. '". Settings were left as they are.')
            elseif why == "empty" then
                say("Type a profile name, or pick one from the list.")
            elseif why == "notready" then
                say("Profiles are still loading. Close this and open /iui again.")
            end
        end)
        loadBtn:SetPoint("LEFT", saveBtn, "RIGHT", 4, 0)
        delBtn = makeButton(bar, "Delete", 64, 20, function()
            local name = nameEdit:GetText() or ""
            if type(IchaUI_ProfileDelete) ~= "function" then
                say("Profiles are not loaded.")
                return
            end
            local ok, why = IchaUI_ProfileDelete(name)
            if ok then
                bar._confirmName = nil
                saveBtn:SetText("Save")
                say('Deleted profile "' .. name .. '".')
                paintActive()
                if list:IsShown() then paintList() end
            elseif why == "missing" then
                say('No saved profile named "' .. name .. '".')
            elseif why == "empty" then
                say("Type a profile name, or pick one from the list.")
            elseif why == "notready" then
                say("Profiles are still loading. Close this and open /iui again.")
            end
        end)
        delBtn:SetPoint("LEFT", loadBtn, "RIGHT", 4, 0)
        listBtn = makeButton(bar, "List", 78, 20, function()
            if list:IsShown() then
                list:Hide()
                return
            end
            paintList()
            list:ClearAllPoints()
            list:SetPoint("BOTTOMLEFT", listBtn, "TOPLEFT", 0, 4)
            list:Show()
        end)
        listBtn:SetPoint("LEFT", delBtn, "RIGHT", 4, 0)
        activeFS:SetPoint("LEFT", listBtn, "RIGHT", 8, 0)
        nameEdit:SetScript("OnTextChanged", function()
            bar._confirmName = nil
            if saveBtn then saveBtn:SetText("Save") end
        end)
        nameEdit:SetScript("OnEnterPressed", function()
            this:ClearFocus()
            doSave()
        end)
        panel:SetScript("OnHide", function()
            if list then list:Hide() end
            if IchaUI_GetTestMode and IchaUI_GetTestMode() and IchaUI_TestMode then
                IchaUI_TestMode(false)
                if panel._testBtn then panel._testBtn:SetText("Test UI: Off") end
                if panel._paintTestSubBtns then panel._paintTestSubBtns() end
            end
        end)
        panel:SetScript("OnShow", function()
            paintActive()
            if list and list:IsShown() then paintList() end
            IchaUI_DyeConfigTree(panel, 0)
        end)
        IchaUI_ProfileBarRefresh = function()
            paintActive()
            if list and list:IsShown() then paintList() end
        end
        paintActive()
    end
    buildProfileBar()

    panel.showTab = showTab
    if IchaUI_BuildConfigSearch then IchaUI_BuildConfigSearch(panel) end

    -- Default / last-used tab (Extras → Skin, Totems → Drawers)
    local function dropUnloadedTabs()
        local function tabLoaded(name)
            if name == "Hero" then return IchaUI_HeroGrid and true or false end
            if name == "Buffs" then return IchaUIBuffBars_Set and true or false end
            if name == "Frames" then return IchaUIUF_Get and true or false end
            if name == "Map" then return IchaUIMinimap_Set and true or false end
            if name == "Mark" then return IchaUI_SmartMark_GetOrder and true or false end
            if name == "Bars" then
                if IchaUI_ActionBarCount or IchaUIShieldBinds_GetSpell or IchaUIXP_Slash then return true end
                return false
            end
            if name == "Drawers" then
                if IchaUITotems_Set or IchaUI_TotemRecallSet or IchaUIShamanExtras_ToggleMove or IchaUI_BuildDrawerExtras or IchaUIUF_GetTankDrawerEnabled then return true end
                return false
            end
            return true
        end
        local kept = {}
        local keepN = 0
        local hideI
        for hideI = 1, table.getn(TAB_NAMES) do
            local tname = TAB_NAMES[hideI]
            if tabLoaded(tname) then
                keepN = keepN + 1
                kept[keepN] = tname
            else
                if tabBtns[tname] then tabBtns[tname]:Hide() end
                if pages[tname] then pages[tname]:Hide() end
            end
        end
        TAB_NAMES = kept
        local visI = 0
        for hideI = 1, table.getn(TAB_NAMES) do
            local tb = tabBtns[TAB_NAMES[hideI]]
            if tb then
                visI = visI + 1
                tb:ClearAllPoints()
                tb:SetPoint("TOPLEFT", tabBar, "TOPLEFT", 0, -((visI - 1) * (22 + tabGap)))
            end
        end
    end
    dropUnloadedTabs()

    local startTab = db().optionsTab
    if startTab == "Extras" then startTab = "Skin" end
    if startTab == "Totems" then startTab = "Drawers" end
    if startTab == "Text" then startTab = "Frames" end
    local known = false
    local ki
    for ki = 1, table.getn(TAB_NAMES) do
        if TAB_NAMES[ki] == startTab then known = true end
    end
    if not known then startTab = TAB_NAMES[1] or "Skin" end
    showTab(startTab)

    return panel
end

function IchaUIOptions_Toggle()
    local p = build()
    if p:IsShown() then
        p:Hide()
    else
        if p.refresh then p.refresh() end
        p:Show()
    end
end

function IchaUIOptions_Open()
    local p = build()
    if p.refresh then p.refresh() end
    p:Show()
end

-- Test mode orchestrator: force-show UI pieces for layout testing
local testModeOn = false

function IchaUI_TestMode(on)
    if on == nil then
        on = not testModeOn
    end
    testModeOn = on and true or false
    if IchaUIUF_SetTestMode then IchaUIUF_SetTestMode(testModeOn) end
    if IchaUITotems_SetTestMode then IchaUITotems_SetTestMode(testModeOn) end
    if IchaUIBuffBars_SetTestMode then IchaUIBuffBars_SetTestMode(testModeOn) end
    if IchaUIXP_SetTestMode then IchaUIXP_SetTestMode(testModeOn) end
    if IchaUIShamanExtras_SetTestMode then IchaUIShamanExtras_SetTestMode(testModeOn) end
    DEFAULT_CHAT_FRAME:AddMessage(testModeOn and "IchaUI test mode ON" or "IchaUI test mode OFF")
    return testModeOn
end

function IchaUI_ToggleTestMode()
    return IchaUI_TestMode(not testModeOn)
end

function IchaUI_GetTestMode()
    return testModeOn and true or false
end


