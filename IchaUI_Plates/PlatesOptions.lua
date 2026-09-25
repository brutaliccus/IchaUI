-- IchaUI Plates config: the "Plates" tab in /iui. Options.lua makes the page and passes
-- its widget helpers; this file lays out sub-tabs (no scrolling). Every ShaguPlatesX
-- nameplate option is here. "*" marks options ShaguPlatesX also needed a reload for.

local X1, X2 = 10, 560
local SUB_Y = -40
local ROW = 22
local seq = 0

local function C() return IchaPlates_config or IchaPlates:BindConfig() end
local function grp(path)
    local t = C()
    local i
    for i = 1, table.getn(path) do
        if type(t[path[i]]) ~= "table" then t[path[i]] = {} end
        t = t[path[i]]
    end
    return t
end

local G_NP = { "nameplates" }
local G_NAME = { "nameplates", "name" }
local G_HEALTH = { "nameplates", "health" }
local G_DEBUFF = { "nameplates", "debuffs" }
local G_GLOBAL = { "global" }
local G_UF = { "unitframes" }
local G_BORDER = { "appearance", "border" }
local G_CD = { "appearance", "cd" }
local G_ICHA = { "icha" }

------------------------------------------------------------------------
-- Widgets
------------------------------------------------------------------------
local function white(fs)
    if IchaUI_DyeFs then IchaUI_DyeFs(fs, 1, 1, 1) else fs:SetTextColor(1, 1, 1) end
end

local function label(parent, text, x, y, w)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if w then fs:SetWidth(w) end
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    white(fs)
    return fs
end

local function refreshAll(ctx)
    ctx.loading = true
    local i
    for i = 1, table.getn(ctx.refresh) do
        pcall(ctx.refresh[i])
    end
    ctx.loading = false
end

-- live: ShaguPlatesX applied it at once; otherwise it wanted a reload.
local function changed(ctx, live)
    if live then
        if IchaPlates_Apply then IchaPlates_Apply() end
    else
        ctx.needReload = true
    end
    refreshAll(ctx)
end

local function caption(text, live)
    if live then return text end
    return text .. " *"
end

local function toggle(ctx, parent, text, x, y, w, path, key, live)
    local b = ctx.U.makeGoldToggle(parent, caption(text, live), w or 260, 18)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetScript("OnClick", function()
        local t = grp(path)
        if t[key] == "1" then t[key] = "0" else t[key] = "1" end
        changed(ctx, live)
    end)
    table.insert(ctx.refresh, function() ctx.U.paintGoldToggle(b, grp(path)[key] == "1") end)
    return b
end

local function cycle(ctx, parent, prefix, x, y, w, opts, path, key, live)
    local b = ctx.U.makeButton(parent, "", w or 260, 20, nil)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local function find()
        local v = grp(path)[key]
        local i
        for i = 1, table.getn(opts) do
            if opts[i][1] == v then return i end
        end
        return 0
    end
    if IchaUI_ChoiceArrow then IchaUI_ChoiceArrow(b) end
    b:SetScript("OnClick", function()
        local pick = function(i)
            grp(path)[key] = opts[i][1]
            changed(ctx, live)
        end
        if IchaUI_ChoiceMenu then
            IchaUI_ChoiceMenu(this, opts, find(), pick, opts.fonts)
            return
        end
        local i = find()
        if arg1 == "RightButton" then i = i - 1 else i = i + 1 end
        if i > table.getn(opts) then i = 1 end
        if i < 1 then i = table.getn(opts) end
        pick(i)
    end)
    table.insert(ctx.refresh, function()
        local i = find()
        local shown = (i > 0 and opts[i][2]) or tostring(grp(path)[key] or "?")
        b:SetText(caption(prefix, live) .. ": " .. shown)
    end)
    return b
end

local function fmtNum(v, step)
    if step < 1 then
        local s = string.format("%.2f", v)
        s = string.gsub(s, "0+$", "")
        s = string.gsub(s, "%.$", "")
        return s
    end
    return tostring(math.floor(v + 0.5))
end

-- Values stay strings in IchaUIDB.plates, like ShaguPlatesX stored them.
local function slider(ctx, parent, title, x, y, lo, hi, step, path, key, live, pct)
    seq = seq + 1
    local name = "IchaPlatesOptSlider" .. seq
    label(parent, caption(title, live), x, y - 1, 150)
    local sl = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    sl:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 154, y - 1)
    sl:SetWidth(200)
    sl:SetHeight(16)
    sl:SetMinMaxValues(lo, hi)
    sl:SetValueStep(step)
    getglobal(name .. "Low"):SetText("")
    getglobal(name .. "High"):SetText("")
    getglobal(name .. "Text"):SetText("")
    local val = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    val:SetPoint("LEFT", sl, "RIGHT", 6, 0)
    white(val)
    local function show(v)
        if pct then val:SetText(math.floor(v * 100 + 0.5) .. "%") else val:SetText(fmtNum(v, step)) end
    end
    sl:SetScript("OnValueChanged", function()
        local v = this:GetValue()
        v = math.floor(v / step + 0.5) * step
        show(v)
        if not ctx.loading then
            local s = fmtNum(v, step)
            if grp(path)[key] ~= s then
                grp(path)[key] = s
                if live then
                    if IchaPlates_Apply then IchaPlates_Apply() end
                else
                    ctx.needReload = true
                    if ctx.paintStatus then ctx.paintStatus() end
                end
            end
        end
    end)
    table.insert(ctx.refresh, function()
        local v = tonumber(grp(path)[key]) or lo
        sl:SetValue(v)
        show(v)
    end)
    return sl
end

local function button(ctx, parent, text, x, y, w, fn)
    local b = ctx.U.makeButton(parent, text, w or 140, 20, fn)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return b
end

-- ShaguPlatesX lists are "#"-separated; shown and typed comma-separated here.
local function listEdit(ctx, parent, title, x, y, w, path, key)
    label(parent, title, x, y - 3, 70)
    local e = ctx.U.makeEdit(parent, w, 18)
    e:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 74, y)
    local function commit()
        if ctx.loading then return end
        local out = {}
        local part
        for part in string.gfind((e:GetText() or "") .. ",", "([^,]*),") do
            part = string.gsub(part, "^%s+", "")
            part = string.gsub(part, "%s+$", "")
            if part ~= "" then table.insert(out, part) end
        end
        local s = table.concat(out, "#")
        if s ~= (grp(path)[key] or "") then
            grp(path)[key] = s
            changed(ctx, true)
        end
    end
    e:SetScript("OnEnterPressed", function()
        commit()
        this:ClearFocus()
    end)
    e:SetScript("OnEditFocusLost", function() commit() end)
    table.insert(ctx.refresh, function()
        local s = string.gsub(grp(path)[key] or "", "#", ", ")
        e:SetText(s)
    end)
    return e
end

local function openPicker(r, g, b, apply)
    if IchaUI_OpenColorPicker then
        IchaUI_OpenColorPicker(r, g, b, apply)
        return
    end
    if not ColorPickerFrame then return end
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.opacityFunc = nil
    ColorPickerFrame.previousValues = { r = r, g = g, b = b }
    ColorPickerFrame.func = function()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        apply(nr, ng, nb)
    end
    ColorPickerFrame.cancelFunc = function() apply(r, g, b) end
    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame:Hide()
    ColorPickerFrame:Show()
    ColorPickerFrame:SetFrameStrata("TOOLTIP")
end

local function parseColor(s)
    local r, g, b, a = IchaPlates.api.GetStringColor(s or "1,1,1,1")
    return tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1, tonumber(a) or 1
end

local function num3(v)
    local s = string.format("%.3f", v)
    s = string.gsub(s, "0+$", "")
    s = string.gsub(s, "%.$", "")
    return s
end

-- Colors are "r,g,b,a" strings; the alpha the user had is kept.
local function swatch(ctx, parent, text, x, y, path, key, live)
    if text then label(parent, caption(text, live), x, y - 2, 150) end
    local bx = text and (x + 154) or x
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(40)
    b:SetHeight(16)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", bx, y)
    b:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    b:SetBackdropColor(0.05, 0.05, 0.06, 1)
    if IchaUI_PaintGoldBorder then IchaUI_PaintGoldBorder(b, 1) end
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
    t:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
    t:SetTexture("Interface/Buttons/WHITE8X8")
    local function paint()
        local r, g, bb = parseColor(grp(path)[key])
        t:SetVertexColor(r, g, bb, 1)
    end
    b:SetScript("OnClick", function()
        local r, g, bb, a = parseColor(grp(path)[key])
        openPicker(r, g, bb, function(nr, ng, nb)
            grp(path)[key] = num3(nr) .. "," .. num3(ng) .. "," .. num3(nb) .. "," .. num3(a)
            paint()
            if live then
                if IchaPlates_Apply then IchaPlates_Apply() end
            else
                ctx.needReload = true
                if ctx.paintStatus then ctx.paintStatus() end
            end
        end)
    end)
    table.insert(ctx.refresh, paint)
    return b
end

local function header(ctx, parent, text, x, y)
    return ctx.U.sectionHeader(parent, text, x, y)
end

------------------------------------------------------------------------
-- Dropdown values (ShaguPlatesX settings.lua)
------------------------------------------------------------------------
local P = "Interface\\AddOns\\IchaUI_Plates\\media\\"

local FONTS = {
    { P .. "fonts\\BigNoodleTitling.ttf", "BigNoodleTitling" },
    { P .. "fonts\\Continuum.ttf", "Continuum" },
    { P .. "fonts\\DieDieDie.ttf", "DieDieDie" },
    { P .. "fonts\\Expressway.ttf", "Expressway" },
    { P .. "fonts\\Homespun.ttf", "Homespun" },
    { P .. "fonts\\Hooge.ttf", "Hooge" },
    { P .. "fonts\\Myriad-Pro.ttf", "Myriad-Pro" },
    { P .. "fonts\\PT-Sans-Narrow-Bold.ttf", "PT-Sans-Narrow-Bold" },
    { P .. "fonts\\PT-Sans-Narrow-Regular.ttf", "PT-Sans-Narrow-Regular" },
}
do
    local loc = GetLocale()
    local extra
    if loc == "enUS" or loc == "frFR" or loc == "deDE" or loc == "ruRU" then
        extra = { "ARIALN.TTF", "FRIZQT__.TTF", "MORPHEUS.TTF", "SKURRI.TTF" }
    elseif loc == "koKR" then
        extra = { "2002.TTF", "2002B.TTF", "ARIALN.TTF", "FRIZQT__.TTF", "K_Damage.TTF", "K_Pagetext.TTF" }
    elseif loc == "zhCN" then
        extra = { "ARIALN.TTF", "FRIZQT__.TTF", "FZBWJW.TTF", "FZJZJW.TTF", "FZLBJW.TTF", "FZXHJW.TTF", "FZXHLJW.TTF" }
    else
        extra = {}
    end
    local i
    for i = 1, table.getn(extra) do
        local f = extra[i]
        table.insert(FONTS, { "Fonts\\" .. f, (string.gsub(f, "_*%.TTF$", "")) })
    end
end
FONTS.fonts = true

local TEXTURES = {
    { P .. "img\\bar", "IchaPlates" },
    { P .. "img\\bar_tukui", "TukUI" },
    { P .. "img\\bar_elvui", "ElvUI" },
    { P .. "img\\bar_gradient", "Gradient" },
    { P .. "img\\bar_striped", "Striped" },
    { "Interface\\TargetingFrame\\UI-StatusBar", "Wow Status" },
    { "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar", "Wow Skill" },
}

local FONTSTYLE = { { "NONE", "None" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick Outline" }, { "MONOCHROME", "Monochrome" } }
local BORDER = { { "-1", "Default" }, { "0", "None" }, { "1", "1 Pixel" }, { "2", "2 Pixel" }, { "3", "3 Pixel" }, { "4", "4 Pixel" }, { "5", "5 Pixel" } }
local POSITIONS = {
    { "TOPLEFT", "Top Left" }, { "TOP", "Top" }, { "TOPRIGHT", "Top Right" },
    { "LEFT", "Left" }, { "CENTER", "Center" }, { "RIGHT", "Right" },
    { "BOTTOMLEFT", "Bottom Left" }, { "BOTTOM", "Bottom" }, { "BOTTOMRIGHT", "Bottom Right" },
}
local DEBUFFPOS = { { "TOP", "Top" }, { "BOTTOM", "Bottom" } }
local FILTER = { { "none", "None" }, { "whitelist", "Whitelist" }, { "blacklist", "Blacklist" } }
local TEXTALIGN = { { "LEFT", "Left" }, { "CENTER", "Center" }, { "RIGHT", "Right" } }
local HPFORMAT = {
    { "percent", "Percent" }, { "cur", "Current HP" }, { "curperc", "Current | Percent" },
    { "curmax", "Current - Max" }, { "curmaxs", "Current / Max" }, { "curmaxperc", "Current - Max | Percent" },
    { "curmaxpercs", "Current / Max | Percent" }, { "deficit", "Deficit" },
}

------------------------------------------------------------------------
-- Sub-tabs
------------------------------------------------------------------------
StaticPopupDialogs["ICHAPLATES_RESET"] = {
    text = "Reset all IchaPlates settings to the defaults?",
    button1 = TEXT(YES),
    button2 = TEXT(NO),
    OnAccept = function()
        local old = C().icha or {}
        IchaUIDB.plates = { icha = { enabled = old.enabled, theme = old.theme, notice = old.notice, imported = "reset" } }
        if IchaPlates_Reload then IchaPlates_Reload() end
        if IchaPlates._optRefresh then IchaPlates._optRefresh(true) end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

local function buildGeneral(ctx, p)
    local y = -4
    header(ctx, p, "IchaPlates", X1, y); y = y - ROW
    toggle(ctx, p, "Enabled", X1, y, 170, G_ICHA, "enabled", false)
    toggle(ctx, p, "IchaUI theme color on plate borders", X1 + 180, y, 260, G_ICHA, "theme", true); y = y - 28
    button(ctx, p, "Import from ShaguPlatesX", X1, y, 180, function()
        if IchaPlates:ImportShaguPlatesX() then
            IchaPlates_Reload()
            IchaPlates:Print("ShaguPlatesX settings imported.")
            ctx.needReload = true
            refreshAll(ctx)
        else
            IchaPlates:Print("ShaguPlatesX settings are only readable while ShaguPlatesX is enabled.")
        end
    end)
    button(ctx, p, "Reset to defaults", X1 + 190, y, 130, function() StaticPopup_Show("ICHAPLATES_RESET") end)
    button(ctx, p, "Reload UI", X1 + 330, y, 100, function() ReloadUI() end); y = y - 26
    local src = label(p, "", X1, y - 3, 520)
    table.insert(ctx.refresh, function()
        local im = C().icha and C().icha.imported
        if im and string.find(im, "^ShaguPlatesX") then
            src:SetText("Settings came from " .. im .. ". Later changes live only in IchaUI.")
        else
            src:SetText("Settings: IchaUI defaults (" .. tostring(im or "new") .. ").")
        end
    end); y = y - 20
    label(p, "IchaPlates is built into IchaUI. While ShaguPlatesX is enabled, IchaPlates stands by so you " ..
        "never get two sets of plates: disable ShaguPlatesX in the AddOns list and restart the game. " ..
        "Options marked * need a /reload.", X1, y, 520); y = y - 56

    header(ctx, p, "Addon compatibility", X1, y); y = y - ROW
    toggle(ctx, p, "Disable ShaguTweaks nameplate library", X1, y, 300, G_GLOBAL, "override_shagutweaks_nameplates", false); y = y - ROW
    toggle(ctx, p, "Disable ShaguTweaks target frame libraries", X1, y, 300, G_GLOBAL, "override_shagutweaks_targetlibs", false); y = y - ROW
    toggle(ctx, p, "Disable SuperAPI castlib", X1, y, 300, G_GLOBAL, "override_superapi_castlib", false); y = y - 30

    header(ctx, p, "Text", X1, y); y = y - ROW
    toggle(ctx, p, "Abbreviate numbers (4200 -> 4.2k)", X1, y, 260, G_UF, "abbrevnum", false)
    toggle(ctx, p, "Abbreviate unit names", X1 + 270, y, 240, G_UF, "abbrevname", false); y = y - ROW
    toggle(ctx, p, "Region compatible font", X1, y, 260, G_GLOBAL, "force_region", false)

    local y2 = -4
    header(ctx, p, "Look & feel", X2, y2); y2 = y2 - ROW
    slider(ctx, p, "Nameplate scale", X2, y2, 0.5, 2, 0.05, G_NP, "scale", true); y2 = y2 - 24
    slider(ctx, p, "Vertical offset", X2, y2, -60, 60, 1, G_NP, "vertical_offset", true); y2 = y2 - 24
    slider(ctx, p, "Name text offset", X2, y2, -40, 40, 1, G_NP, "nameoffset", true); y2 = y2 - 24
    slider(ctx, p, "Nameplate width", X2, y2, 40, 300, 1, G_NP, "width", true); y2 = y2 - 24
    slider(ctx, p, "Right click attack threshold", X2, y2, 0, 2, 0.1, G_NP, "clickthreshold", true); y2 = y2 - 28
    toggle(ctx, p, "Show on hostile units", X2, y2, 250, G_NP, "showhostile", true)
    toggle(ctx, p, "Show on friendly units", X2 + 260, y2, 250, G_NP, "showfriendly", true); y2 = y2 - ROW
    toggle(ctx, p, "Class colors on enemies", X2, y2, 250, G_NP, "enemyclassc", true)
    toggle(ctx, p, "Class colors on friends", X2 + 260, y2, 250, G_NP, "friendclassc", true); y2 = y2 - ROW
    toggle(ctx, p, "Red name text on infight units", X2, y2, 250, G_NP, "namefightcolor", true)
    toggle(ctx, p, "Combo point display", X2 + 260, y2, 250, G_NP, "cpdisplay", true); y2 = y2 - ROW
    toggle(ctx, p, "Clickthrough", X2, y2, 250, G_NP, "clickthrough", true)
    toggle(ctx, p, "Overlap", X2 + 260, y2, 250, G_NP, "overlap", true); y2 = y2 - ROW
    toggle(ctx, p, "Mouselook with right click", X2, y2, 250, G_NP, "rightclick", true)
    toggle(ctx, p, "Replace totems with icons", X2 + 260, y2, 250, G_NP, "totemicons", true)
end

local function buildHealth(ctx, p)
    local y = -4
    header(ctx, p, "Target", X1, y); y = y - ROW
    toggle(ctx, p, "Glow around target nameplate", X1, y, 250, G_NP, "targetglow", true)
    swatch(ctx, p, nil, X1 + 260, y - 1, G_NP, "glowcolor", true)
    label(p, "Glow color", X1 + 306, y - 3, 100); y = y - ROW
    toggle(ctx, p, "Zoom target nameplate", X1, y, 250, G_NP, "targetzoom", true)
    toggle(ctx, p, "Instant target zoom", X1 + 260, y, 250, G_NP, "targetzoominstant", true); y = y - 26
    slider(ctx, p, "Target zoom factor", X1, y, 0, 1, 0.05, G_NP, "targetzoomval", true, true); y = y - 24
    slider(ctx, p, "Inactive nameplate alpha", X1, y, 0, 1, 0.05, G_NP, "notargalpha", true, true); y = y - 30

    header(ctx, p, "Raid icon", X1, y); y = y - ROW
    cycle(ctx, p, "Position", X1, y, 250, POSITIONS, G_NP, "raidiconpos", true); y = y - 26
    slider(ctx, p, "X offset", X1, y, -60, 60, 1, G_NP, "raidiconoffx", true); y = y - 24
    slider(ctx, p, "Y offset", X1, y, -60, 60, 1, G_NP, "raidiconoffy", true); y = y - 24
    slider(ctx, p, "Size", X1, y, 4, 64, 1, G_NP, "raidiconsize", true)

    local y2 = -4
    header(ctx, p, "Healthbar", X2, y2); y2 = y2 - ROW
    slider(ctx, p, "Vertical offset", X2, y2, -40, 40, 1, G_HEALTH, "offset", true); y2 = y2 - 24
    slider(ctx, p, "Height", X2, y2, 1, 40, 1, G_NP, "heighthealth", true); y2 = y2 - 26
    cycle(ctx, p, "Texture", X2, y2, 250, TEXTURES, G_NP, "healthtexture", true)
    toggle(ctx, p, "Vertical healthbar", X2 + 260, y2 - 1, 250, G_NP, "verticalhealth", true); y2 = y2 - 26
    toggle(ctx, p, "Show health points", X2, y2, 250, G_NP, "showhp", false); y2 = y2 - 24
    cycle(ctx, p, "Text position", X2, y2, 250, TEXTALIGN, G_NP, "hptextpos", true)
    cycle(ctx, p, "Format", X2 + 260, y2, 250, HPFORMAT, G_NP, "hptextformat", true); y2 = y2 - 30

    header(ctx, p, "Hide healthbar on", X2, y2); y2 = y2 - ROW
    toggle(ctx, p, "Enemy NPCs", X2, y2, 165, G_NP, "enemynpc", true)
    toggle(ctx, p, "Enemy players", X2 + 172, y2, 165, G_NP, "enemyplayer", true)
    toggle(ctx, p, "Neutral NPCs", X2 + 344, y2, 165, G_NP, "neutralnpc", true); y2 = y2 - ROW
    toggle(ctx, p, "Friendly NPCs", X2, y2, 165, G_NP, "friendlynpc", true)
    toggle(ctx, p, "Friendly players", X2 + 172, y2, 165, G_NP, "friendlyplayer", true)
    toggle(ctx, p, "Critters", X2 + 344, y2, 165, G_NP, "critters", true); y2 = y2 - ROW
    toggle(ctx, p, "Totems", X2, y2, 165, G_NP, "totems", true); y2 = y2 - 28
    header(ctx, p, "But always show on", X2, y2); y2 = y2 - ROW
    toggle(ctx, p, "Units with missing HP", X2, y2, 250, G_NP, "fullhealth", true)
    toggle(ctx, p, "Target units", X2 + 260, y2, 250, G_NP, "target", true)
end

local function buildCast(ctx, p)
    local y = -4
    header(ctx, p, "Castbar", X1, y); y = y - ROW
    toggle(ctx, p, "Enable castbars", X1, y, 250, G_NP, "showcastbar", true)
    toggle(ctx, p, "Only show target castbar", X1 + 260, y, 250, G_NP, "targetcastbar", true); y = y - ROW
    toggle(ctx, p, "Enable spell name", X1, y, 250, G_NP, "spellname", true); y = y - 26
    slider(ctx, p, "Castbar height", X1, y, 1, 40, 1, G_NP, "heightcast", true); y = y - 30

    header(ctx, p, "Debuffs", X1, y); y = y - ROW
    toggle(ctx, p, "Enable debuffs", X1, y, 250, G_NP, "showdebuffs", true)
    toggle(ctx, p, "Estimate debuffs", X1 + 260, y, 250, G_NP, "guessdebuffs", true); y = y - ROW
    toggle(ctx, p, "Show debuff stacks", X1, y, 250, G_DEBUFF, "showstacks", true)
    toggle(ctx, p, "Only show own debuffs (experimental)", X1 + 260, y, 250, G_NP, "selfdebuff", true); y = y - 26
    cycle(ctx, p, "Position", X1, y, 250, DEBUFFPOS, G_DEBUFF, "position", true)
    cycle(ctx, p, "Filter mode", X1 + 260, y, 250, FILTER, G_DEBUFF, "filter", true); y = y - 28
    slider(ctx, p, "Icon offset", X1, y, -20, 40, 1, G_NP, "debuffoffset", true); y = y - 24
    slider(ctx, p, "Icon size", X1, y, 6, 40, 1, G_NP, "debuffsize", true); y = y - 28
    listEdit(ctx, p, "Blacklist", X1, y, 430, G_DEBUFF, "blacklist"); y = y - 24
    listEdit(ctx, p, "Whitelist", X1, y, 430, G_DEBUFF, "whitelist"); y = y - 22
    label(p, "Spell names, separated by commas. Press Enter to save.", X1 + 74, y, 430)

    local y2 = -4
    header(ctx, p, "Cooldown / durations", X2, y2); y2 = y2 - ROW
    toggle(ctx, p, "Display debuff durations", X2, y2, 250, G_CD, "debuffs", false)
    toggle(ctx, p, "Milliseconds when timer runs out", X2 + 260, y2, 250, G_CD, "milliseconds", true); y2 = y2 - ROW
    toggle(ctx, p, "Durations on Blizzard frames", X2, y2, 250, G_CD, "blizzard", false)
    toggle(ctx, p, "Durations on foreign frames", X2 + 260, y2, 250, G_CD, "foreign", false); y2 = y2 - ROW
    toggle(ctx, p, "Hide foreign cooldown animations", X2, y2, 250, G_CD, "hideanim", false)
    toggle(ctx, p, "Dynamic font size", X2 + 260, y2, 250, G_CD, "dynamicsize", false); y2 = y2 - 26
    cycle(ctx, p, "Font", X2, y2, 250, FONTS, G_CD, "font", false); y2 = y2 - 28
    slider(ctx, p, "Font size", X2, y2, 6, 40, 1, G_CD, "font_size", false); y2 = y2 - 24
    slider(ctx, p, "Font size (Blizzard)", X2, y2, 6, 40, 1, G_CD, "font_size_blizz", false); y2 = y2 - 24
    slider(ctx, p, "Font size (foreign)", X2, y2, 6, 40, 1, G_CD, "font_size_foreign", false); y2 = y2 - 24
    slider(ctx, p, "Text threshold (s)", X2, y2, 0, 10, 1, G_CD, "threshold", false); y2 = y2 - 28
    swatch(ctx, p, "Color: under 3 sec", X2, y2, G_CD, "lowcolor", false); y2 = y2 - ROW
    swatch(ctx, p, "Color: seconds", X2, y2, G_CD, "normalcolor", false); y2 = y2 - ROW
    swatch(ctx, p, "Color: minutes", X2, y2, G_CD, "minutecolor", false); y2 = y2 - ROW
    swatch(ctx, p, "Color: hours", X2, y2, G_CD, "hourcolor", false); y2 = y2 - ROW
    swatch(ctx, p, "Color: days", X2, y2, G_CD, "daycolor", false)
end

local function buildColors(ctx, p)
    local y = -4
    header(ctx, p, "Outlines", X1, y); y = y - ROW
    toggle(ctx, p, "Blue border on friendly players", X1, y, 250, G_NP, "outfriendly", true)
    toggle(ctx, p, "Green border on friendly NPCs", X1 + 260, y, 250, G_NP, "outfriendlynpc", true); y = y - ROW
    toggle(ctx, p, "Yellow border on neutral units", X1, y, 250, G_NP, "outneutral", true)
    toggle(ctx, p, "Red border on enemy units", X1 + 260, y, 250, G_NP, "outenemy", true); y = y - ROW
    toggle(ctx, p, "Border around target unit", X1, y, 250, G_NP, "targethighlight", true)
    swatch(ctx, p, nil, X1 + 260, y - 1, G_NP, "highlightcolor", true)
    label(p, "Target border color", X1 + 306, y - 3, 150); y = y - 30

    header(ctx, p, "Aggro display", X1, y); y = y - ROW
    toggle(ctx, p, "Border color shows combat state", X1, y, 250, G_NP, "outcombatstate", true)
    toggle(ctx, p, "Health color shows combat state", X1 + 260, y, 250, G_NP, "barcombatstate", true); y = y - 26
    toggle(ctx, p, "When unit is attacking you", X1, y, 250, G_NP, "ccombatthreat", true)
    swatch(ctx, p, nil, X1 + 260, y - 1, G_NP, "combatthreat", true); y = y - ROW
    toggle(ctx, p, "When unit is attacking others", X1, y, 250, G_NP, "ccombatnothreat", true)
    swatch(ctx, p, nil, X1 + 260, y - 1, G_NP, "combatnothreat", true); y = y - ROW
    toggle(ctx, p, "When unit is attacking no one", X1, y, 250, G_NP, "ccombatstun", true)
    swatch(ctx, p, nil, X1 + 260, y - 1, G_NP, "combatstun", true); y = y - ROW
    toggle(ctx, p, "When unit is casting", X1, y, 250, G_NP, "ccombatcasting", true)
    swatch(ctx, p, nil, X1 + 260, y - 1, G_NP, "combatcasting", true)

    local y2 = -4
    header(ctx, p, "Borders", X2, y2); y2 = y2 - ROW
    cycle(ctx, p, "Border size", X2, y2, 250, BORDER, G_BORDER, "nameplates", true)
    toggle(ctx, p, "Use Blizzard borders", X2 + 260, y2 - 1, 250, G_BORDER, "force_blizz", false); y2 = y2 - 26
    toggle(ctx, p, "Pixel perfect borders", X2, y2, 250, G_BORDER, "pixelperfect", false)
    toggle(ctx, p, "Scale borders on HiDPI displays", X2 + 260, y2, 250, G_BORDER, "hidpi", false); y2 = y2 - 26
    swatch(ctx, p, "Background color", X2, y2, G_BORDER, "background", false); y2 = y2 - ROW
    swatch(ctx, p, "Border color", X2, y2, G_BORDER, "color", false); y2 = y2 - ROW
    label(p, "The IchaUI theme toggle (General) overrides the border color with the IchaUI gold.", X2, y2 - 2, 500); y2 = y2 - 28

    header(ctx, p, "Fonts", X2, y2); y2 = y2 - ROW
    cycle(ctx, p, "Text font", X2, y2, 250, FONTS, G_GLOBAL, "font_unit", false)
    cycle(ctx, p, "Font style", X2 + 260, y2, 250, FONTSTYLE, G_NAME, "fontstyle", true); y2 = y2 - 28
    slider(ctx, p, "Text font size", X2, y2, 6, 30, 1, G_GLOBAL, "font_unit_size", false)
end

------------------------------------------------------------------------
-- Entry point (called from Options.lua)
------------------------------------------------------------------------
local SUBS = {
    { "General", buildGeneral },
    { "Health", buildHealth },
    { "Cast & Auras", buildCast },
    { "Colors & Fonts", buildColors },
}

function IchaPlates_BuildOptions(pg, U)
    local ctx = { pg = pg, U = U, refresh = {}, subs = {}, btns = {}, loading = false }

    -- The page fits without scrolling.
    if pg._scroll then
        pg._scroll:EnableMouseWheel(false)
        if pg._scroll._tip then pg._scroll._tip:Hide() end
    end

    local status = label(pg, "", 470, -8, 620)
    ctx.paintStatus = function()
        local txt, r, g, b = "Loading", 0.8, 0.8, 0.8
        if IchaPlates_Status then txt, r, g, b = IchaPlates_Status() end
        if ctx.needReload then
            status:SetText("Status: " .. txt .. "   |cffff9a55Reload to apply * changes|r")
        else
            status:SetText("Status: " .. txt)
        end
        status:SetTextColor(r, g, b)
    end
    table.insert(ctx.refresh, ctx.paintStatus)

    local function show(n)
        ctx.active = n
        local ic = grp(G_ICHA)
        ic.optSub = n
        local i
        for i = 1, table.getn(SUBS) do
            if i == n then ctx.subs[i]:Show() else ctx.subs[i]:Hide() end
            U.paintGoldToggle(ctx.btns[i], i == n)
        end
        refreshAll(ctx)
    end
    local i
    for i = 1, table.getn(SUBS) do
        local n = i
        local b = U.makeGoldToggle(pg, SUBS[i][1], 106, 20)
        b:SetPoint("TOPLEFT", pg, "TOPLEFT", X1 + (i - 1) * 110, -4)
        b:SetScript("OnClick", function() show(n) end)
        ctx.btns[i] = b
        local sub = CreateFrame("Frame", nil, pg)
        sub:SetPoint("TOPLEFT", pg, "TOPLEFT", 0, SUB_Y)
        sub:SetWidth(1100)
        sub:SetHeight(560)
        sub:Hide()
        ctx.subs[i] = sub
        SUBS[i][2](ctx, sub)
    end
    local line = pg:CreateTexture(nil, "ARTWORK")
    line:SetTexture("Interface/Buttons/WHITE8X8")
    line:SetVertexColor(0.78, 0.58, 0.16, 0.5)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", pg, "TOPLEFT", X1, -30)
    line:SetPoint("TOPRIGHT", pg, "TOPLEFT", 1090, -30)

    local start = tonumber(grp(G_ICHA).optSub) or 1
    if start < 1 or start > table.getn(SUBS) then start = 1 end
    show(start)

    IchaPlates._optRefresh = function(reset)
        if reset then ctx.needReload = true end
        if ctx.active then show(ctx.active) end
    end
    return IchaPlates._optRefresh
end
