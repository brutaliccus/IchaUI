-- One theme gold for IchaUI chrome. Default is the current dark gold
-- (0.75, 0.52, 0.04). Nothing is written until the Skin picker saves a color.
-- Brighter text is derived from that dark gold so both shift together.

local DARK_R, DARK_G, DARK_B = 0.75, 0.52, 0.04
local LIGHT_R, LIGHT_G, LIGHT_B = 0.93, 0.78, 0.35

local borders = {}
local lightBorders = {}
local fonts = {}
local verts = {}
local fills = {}
local portFills = {}
local FILL_R, FILL_G, FILL_B = 0.07, 0.07, 0.08
local goldBusy = false

local function clamp01(v)
    v = tonumber(v) or 0
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function near(a, b)
    local d = (tonumber(a) or 0) - (tonumber(b) or 0)
    if d < 0 then d = -d end
    if d < 0.021 then return true end
    return false
end

local function isDark(r, g, b)
    if near(r, DARK_R) and near(g, DARK_G) and near(b, DARK_B) then return true end
    return false
end

local function isLight(r, g, b)
    if near(r, LIGHT_R) and near(g, LIGHT_G) and near(b, LIGHT_B) then return true end
    return false
end

local function lift(c, dark0, light0)
    c = clamp01(c)
    if dark0 >= 0.999 then return c end
    local k = (light0 - dark0) / (1 - dark0)
    if k < 0 then k = 0 end
    if k > 1 then k = 1 end
    return clamp01(c + (1 - c) * k)
end

function IchaUI_ThemeGoldOn()
    local d = IchaUIDB and IchaUIDB.gold
    if type(d) ~= "table" then return false end
    if not tonumber(d.r) or not tonumber(d.g) or not tonumber(d.b) then return false end
    return true
end

function IchaUI_Gold()
    if IchaUI_ThemeGoldOn() then
        local d = IchaUIDB.gold
        return clamp01(d.r), clamp01(d.g), clamp01(d.b)
    end
    return DARK_R, DARK_G, DARK_B
end

function IchaUI_GoldLight()
    local r, g, b = IchaUI_Gold()
    return lift(r, DARK_R, LIGHT_R), lift(g, DARK_G, LIGHT_G), lift(b, DARK_B, LIGHT_B)
end

local function remember(list, obj)
    if not obj or obj._ichaGoldTracked then return end
    obj._ichaGoldTracked = true
    table.insert(list, obj)
end

function IchaUI_Fill()
    local d = IchaUIDB and IchaUIDB.fill
    if type(d) == "table" and tonumber(d.r) and tonumber(d.g) and tonumber(d.b) then
        return clamp01(d.r), clamp01(d.g), clamp01(d.b)
    end
    return FILL_R, FILL_G, FILL_B
end

function IchaUI_SetFill(r, g, b)
    if not IchaUIDB then IchaUIDB = {} end
    IchaUIDB.fill = { r = clamp01(r), g = clamp01(g), b = clamp01(b) }
    if IchaUI_RefreshGoldTheme then IchaUI_RefreshGoldTheme() end
end

-- Dark gold hole behind empty portraits. Same theme gold as bars/rings,
-- darkened so it reads as a fill, not the bright accent.
function IchaUI_PortraitFillColor()
    local r, g, b
    if IchaUI_ThemeLiveGold then
        r, g, b = IchaUI_ThemeLiveGold()
    else
        r, g, b = IchaUI_Gold()
    end
    return clamp01(r * 0.20), clamp01(g * 0.20), clamp01(b * 0.20)
end

function IchaUI_PaintPortraitFill(tex)
    if not tex or not tex.SetVertexColor then return end
    if not tex._ichaPortFill then
        tex._ichaPortFill = true
        table.insert(portFills, tex)
    end
    local r, g, b = IchaUI_PortraitFillColor()
    tex:SetVertexColor(r, g, b, 1)
end

-- SetPortraitTexture when the unit has a face; hide the tex when empty so
-- the circular fill stays visible. Returns true if a real portrait is up.
function IchaUI_ApplyPortraitFace(tex, unit)
    if not tex then return false end
    local loaded = false
    if unit and unit ~= "" and unit ~= "none" and UnitExists then
        local ok, exists = pcall(UnitExists, unit)
        if ok and exists then
            if SetPortraitTexture then
                pcall(SetPortraitTexture, tex, unit)
            end
            if tex.GetTexture then
                local got = tex:GetTexture()
                if got and got ~= "" then loaded = true end
            else
                loaded = true
            end
            if (not loaded) and SetPortraitTextureFromGUID and UnitGUID then
                local okg, guid = pcall(UnitGUID, unit)
                if okg and guid and guid ~= "" then
                    pcall(SetPortraitTextureFromGUID, tex, guid)
                    if tex.GetTexture then
                        local got = tex:GetTexture()
                        if got and got ~= "" then loaded = true end
                    end
                end
            end
        end
    end
    if loaded then
        tex:Show()
    else
        if tex.SetTexture then
            pcall(function() tex:SetTexture("") end)
        end
        tex:Hide()
    end
    return loaded
end

-- Fill opacity: scales every fill's own alpha (1 = each panel's designed alpha).
function IchaUI_ThemeFillAlpha()
    local v = IchaUIDB and tonumber(IchaUIDB.fillAlpha)
    if not v then return 1 end
    return clamp01(v)
end

-- f._ichaFillA is the panel's base alpha; the backdrop shows base * scale.
function IchaUI_PaintFill(f, a)
    if not f or not f.SetBackdropColor then return end
    a = tonumber(a) or 0.94
    if not f._ichaFillTracked then
        f._ichaFillTracked = true
        table.insert(fills, f)
    end
    f._ichaFillA = a
    f._ichaFillShown = a * IchaUI_ThemeFillAlpha()
    local r, g, b = IchaUI_Fill()
    f:SetBackdropColor(r, g, b, f._ichaFillShown)
end

local function repaintFills()
    local i
    for i = 1, table.getn(fills) do
        local f = fills[i]
        if f and f.SetBackdropColor then
            IchaUI_PaintFill(f, f._ichaFillA or 0.94)
        end
    end
end

function IchaUI_SetFillAlpha(v)
    if not IchaUIDB then IchaUIDB = {} end
    IchaUIDB.fillAlpha = clamp01(v)
    repaintFills()
    if type(IchaUIChatSkin_RefreshFill) == "function" then pcall(IchaUIChatSkin_RefreshFill) end
end

local function backdropIsDark(f)
    if not f or not f.GetBackdropColor then return false end
    local r, g, b = f:GetBackdropColor()
    if not r then return false end
    if r > 0.16 or (g or 0) > 0.16 or (b or 0) > 0.16 then return false end
    return true
end

function IchaUI_PaintGoldBorder(f, a)
    if not f or not f.SetBackdropBorderColor then return end
    a = tonumber(a) or 1
    remember(borders, f)
    f._ichaGoldA = a
    local r, g, b = IchaUI_Gold()
    f:SetBackdropBorderColor(r, g, b, a)
    if backdropIsDark(f) then
        local _, _, _, ba = f:GetBackdropColor()
        ba = ba or 0.94
        -- Still showing our scaled alpha: keep the base or it compounds.
        if f._ichaFillA and f._ichaFillShown then
            local d = ba - f._ichaFillShown
            if d < 0 then d = -d end
            if d < 0.0025 then ba = f._ichaFillA end
        end
        IchaUI_PaintFill(f, ba)
    end
end

function IchaUI_PaintGoldLightBorder(f, a)
    if not f or not f.SetBackdropBorderColor then return end
    a = tonumber(a) or 1
    remember(lightBorders, f)
    f._ichaGoldLA = a
    local r, g, b = IchaUI_GoldLight()
    f:SetBackdropBorderColor(r, g, b, a)
end

function IchaUI_PaintGoldFont(fs, r0, g0, b0)
    if not fs or not fs.SetTextColor then return end
    remember(fonts, fs)
    fs._gSkip = nil
    fs._gfr, fs._gfg, fs._gfb = r0, g0, b0
    local r, g, b = r0, g0, b0
    if isLight(r0, g0, b0) or isDark(r0, g0, b0) or IchaUI_ThemeGoldOn() then
        r, g, b = IchaUI_GoldLight()
    end
    if IchaUI_DyeFs then
        IchaUI_DyeFs(fs, r, g, b)
    else
        fs:SetTextColor(r, g, b)
    end
end

-- r0,g0,b0 is the color used until the picker saves a theme.
-- bright: cast fill and other light gold, follows IchaUI_GoldLight.
-- Otherwise a saved theme uses the dark gold.
function IchaUI_PaintGoldVertex(tex, r0, g0, b0, a, bright)
    if not tex or not tex.SetVertexColor then return end
    a = tonumber(a) or 1
    remember(verts, tex)
    tex._gvr, tex._gvg, tex._gvb = r0, g0, b0
    tex._gva = a
    if bright then tex._gvBright = true else tex._gvBright = false end
    -- TrackingBorder art is baked gold. Desaturate first or the theme tint
    -- stays golden brown no matter which color the picker saved.
    if tex._ichaGoldDesat and tex.SetDesaturated then
        local function desatRing()
            tex:SetDesaturated(1)
        end
        pcall(desatRing)
    end
    local r, g, b = r0, g0, b0
    if tex._gvBright then
        if isLight(r0, g0, b0) or IchaUI_ThemeGoldOn() then
            r, g, b = IchaUI_GoldLight()
        end
    else
        if isDark(r0, g0, b0) or IchaUI_ThemeGoldOn() then
            r, g, b = IchaUI_Gold()
        end
    end
    tex:SetVertexColor(r, g, b, a)
end

-- Thick circle-button ring (MiniMap-TrackingBorder). Grayscale, then theme gold,
-- so IchaUI_RefreshGoldTheme's vertex repaint changes it live.
function IchaUI_PaintGoldRing(tex)
    if not tex or not tex.SetVertexColor then return end
    tex._ichaGoldDesat = true
    IchaUI_PaintGoldVertex(tex, 0.75, 0.52, 0.04, 1)
end

-- 1.12 keeps the old edge art until SetBackdrop runs again. A color
-- write alone stays invisible until /reload recreates the backdrop.
local function flashBorder(f, r, g, b, a)
    if not f or not f.SetBackdropBorderColor then return end
    local bd = nil
    if f.GetBackdrop then bd = f:GetBackdrop() end
    local br, bg, bb, ba = nil, nil, nil, nil
    if f.GetBackdropColor then
        br, bg, bb, ba = f:GetBackdropColor()
    end
    if bd and f.SetBackdrop then
        f:SetBackdrop(bd)
    end
    if br and f.SetBackdropColor then
        f:SetBackdropColor(br, bg or 0, bb or 0, ba or 1)
    end
    f:SetBackdropBorderColor(r, g, b, a or 1)
end

local function repaintBorders()
    local i
    for i = 1, table.getn(borders) do
        local f = borders[i]
        if f then
            local r, g, b = IchaUI_Gold()
            pcall(flashBorder, f, r, g, b, f._ichaGoldA or 1)
        end
    end
    for i = 1, table.getn(lightBorders) do
        local f = lightBorders[i]
        if f then
            local r, g, b = IchaUI_GoldLight()
            pcall(flashBorder, f, r, g, b, f._ichaGoldLA or 1)
        end
    end
end

local function repaintTracked()
    local i
    repaintBorders()
    for i = 1, table.getn(fonts) do
        local fs = fonts[i]
        if fs and fs.SetTextColor and not fs._gSkip then
            IchaUI_PaintGoldFont(fs, fs._gfr, fs._gfg, fs._gfb)
        end
    end
    for i = 1, table.getn(fills) do
        local f = fills[i]
        if f and f.SetBackdropColor then
            IchaUI_PaintFill(f, f._ichaFillA or 0.94)
        end
    end
    for i = 1, table.getn(verts) do
        local tex = verts[i]
        if tex and tex.SetVertexColor then
            IchaUI_PaintGoldVertex(tex, tex._gvr, tex._gvg, tex._gvb, tex._gva, tex._gvBright)
        end
    end
    for i = 1, table.getn(portFills) do
        local tex = portFills[i]
        if tex and tex.SetVertexColor then
            IchaUI_PaintPortraitFill(tex)
        end
    end
end

function IchaUI_PushConfigGold()
    local r, g, b = IchaUI_GoldLight()
    if GOLD then
        GOLD[1], GOLD[2], GOLD[3] = r, g, b
    end
    if GOLD_DIM then
        if IchaUI_ThemeGoldOn() then
            local dr, dg, db = IchaUI_Gold()
            GOLD_DIM[1], GOLD_DIM[2], GOLD_DIM[3] = dr, dg, db
        else
            GOLD_DIM[1] = LIGHT_R * 0.8
            GOLD_DIM[2] = LIGHT_G * 0.67
            GOLD_DIM[3] = DARK_B
        end
    end
end

function IchaUI_SetGold(r, g, b)
    if not IchaUIDB then IchaUIDB = {} end
    IchaUIDB.gold = { r = clamp01(r), g = clamp01(g), b = clamp01(b) }
    if IchaUI_RefreshGoldTheme then IchaUI_RefreshGoldTheme() end
end

function IchaUI_ClearGold()
    if IchaUIDB then IchaUIDB.gold = nil end
    if IchaUI_RefreshGoldTheme then IchaUI_RefreshGoldTheme() end
end

local function callRefresh(fn)
    if type(fn) ~= "function" then return end
    pcall(fn)
end

function IchaUI_RefreshGoldTheme()
    if goldBusy then return end
    goldBusy = true
    callRefresh(IchaUI_PushConfigGold)
    callRefresh(repaintTracked)
    callRefresh(IchaUIUF_RefreshGoldChrome)
    callRefresh(IchaUIUF_RefreshRoleIcons)
    callRefresh(IchaUI_TooltipSkin_Refresh)
    callRefresh(IchaUIChatSkin_Reload)
    callRefresh(IchaUIMinimap_Reload)
    callRefresh(IchaUIMinimapButtons_Refresh)
    callRefresh(IchaUIFrameSkin_Reload)
    callRefresh(IchaUIBuffBars_Reload)
    callRefresh(IchaUIXP_Reload)
    callRefresh(IchaUI_DrawerExtrasRefresh)
    callRefresh(IchaPlates_ThemeRefresh)
    if type(IchaUI_DrawerApply) == "function" then
        pcall(IchaUI_DrawerApply, "totems")
        pcall(IchaUI_DrawerApply, "recall")
        pcall(IchaUI_DrawerApply, "utility")
        pcall(IchaUI_DrawerApply, "imbue")
        pcall(IchaUI_DrawerApply, "shield")
        pcall(IchaUI_DrawerApply, "minimap")
    end
    local panel = getglobal("IchaUIOptions")
    if panel and type(IchaUI_DyeConfigTree) == "function" then
        pcall(IchaUI_DyeConfigTree, panel, 0)
    end
    if panel and type(panel._repaintTabs) == "function" then
        pcall(panel._repaintTabs)
    end
    callRefresh(IchaUI_GoldSwatchPaint)
    callRefresh(IchaUI_FillSwatchPaint)
    callRefresh(IchaUI_ThemePreviewPaint)
    -- Borders again after tab/config paint, which can SetBackdrop.
    callRefresh(repaintBorders)
    goldBusy = false
end

------------------------------------------------------------------------
-- Picker preview. While ColorPickerFrame is open the picked color lives in
-- themeSess only: swatches, the Skin preview box and the options window
-- chrome follow it. The saved theme and the full repaint wait for Okay.
------------------------------------------------------------------------
local THROTTLE = 0.25
local themeSess = nil
local pendingHide = nil
local okDepth = 0
local jobs = {}
local timer = CreateFrame("Frame")
timer:Hide()

local function runJob(j)
    j.due = nil
    j.last = GetTime()
    pcall(j.fn)
end

-- Leading run, then at most one trailing run per THROTTLE window.
local function throttle(key, fn)
    local j = jobs[key]
    if not j then
        j = { last = -100 }
        jobs[key] = j
    end
    j.fn = fn
    if not j.due and GetTime() - j.last >= THROTTLE then
        runJob(j)
        return
    end
    if not j.due then j.due = j.last + THROTTLE end
    timer:Show()
end

local function flushJob(key)
    local j = jobs[key]
    if j and j.due then runJob(j) end
end

local function dropJob(key)
    local j = jobs[key]
    if j then j.due = nil end
end

function IchaUI_ThemeLiveApplyOn()
    if IchaUIDB and IchaUIDB.themeLiveApply then return true end
    return false
end

function IchaUI_SetThemeLiveApply(on)
    if not IchaUIDB then IchaUIDB = {} end
    if on then IchaUIDB.themeLiveApply = true else IchaUIDB.themeLiveApply = nil end
end

function IchaUI_ThemeLiveGold()
    local s = themeSess
    if s and s.kind == "gold" then return s.cr, s.cg, s.cb end
    return IchaUI_Gold()
end

function IchaUI_ThemeLiveGoldLight()
    local r, g, b = IchaUI_ThemeLiveGold()
    return lift(r, DARK_R, LIGHT_R), lift(g, DARK_G, LIGHT_G), lift(b, DARK_B, LIGHT_B)
end

function IchaUI_ThemeLiveFill()
    local s = themeSess
    if s and s.kind == "fill" then return s.cr, s.cg, s.cb end
    return IchaUI_Fill()
end

local function paintConfigChrome()
    local panel = getglobal("IchaUIOptions")
    if not panel or not panel.SetBackdropBorderColor then return end
    local r, g, b = IchaUI_ThemeLiveGold()
    flashBorder(panel, r, g, b, panel._ichaGoldA or 1)
    if panel._ichaFillA then
        local fr, fg, fb = IchaUI_ThemeLiveFill()
        panel._ichaFillShown = panel._ichaFillA * IchaUI_ThemeFillAlpha()
        panel:SetBackdropColor(fr, fg, fb, panel._ichaFillShown)
    end
end

-- Cheap: two swatches, the preview box and one window border.
function IchaUI_ThemePreview()
    callRefresh(IchaUI_GoldSwatchPaint)
    callRefresh(IchaUI_FillSwatchPaint)
    callRefresh(IchaUI_ThemePreviewPaint)
    callRefresh(paintConfigChrome)
end

local function rgbCopy(t)
    if type(t) ~= "table" or not tonumber(t.r) or not tonumber(t.g) or not tonumber(t.b) then return nil end
    return { r = clamp01(t.r), g = clamp01(t.g), b = clamp01(t.b) }
end

local function writeSess(s, t)
    if not IchaUIDB then IchaUIDB = {} end
    IchaUIDB[s.kind] = t
end

local function endSess(s)
    if themeSess == s then themeSess = nil end
    dropJob("theme")
end

local function commitSess(s)
    if themeSess ~= s then return end
    endSess(s)
    writeSess(s, { r = s.cr, g = s.cg, b = s.cb })
    IchaUI_RefreshGoldTheme()
end

local function cancelSess(s, prev)
    if themeSess ~= s then return end
    endSess(s)
    if not s.applied then
        IchaUI_ThemePreview()
        return
    end
    -- Live apply already saved a color: put the old one back and repaint once.
    local t = nil
    if s.orig then t = rgbCopy(prev) or s.orig end
    writeSess(s, t)
    IchaUI_RefreshGoldTheme()
end

local function dragSess(s, r, g, b)
    s.cr, s.cg, s.cb = clamp01(r), clamp01(g), clamp01(b)
    IchaUI_ThemePreview()
    if not IchaUI_ThemeLiveApplyOn() then return end
    throttle("theme", function()
        if themeSess ~= s then return end
        s.applied = true
        writeSess(s, { r = s.cr, g = s.cg, b = s.cb })
        IchaUI_RefreshGoldTheme()
    end)
end

local pickerHooked = false
local function hookPicker()
    if pickerHooked or not ColorPickerFrame or not ColorPickerFrame.GetScript then return end
    pickerHooked = true
    local okBtn = getglobal("ColorPickerOkayButton")
    if okBtn and okBtn.GetScript then
        local oldOk = okBtn:GetScript("OnClick")
        okBtn:SetScript("OnClick", function()
            local s = themeSess
            okDepth = okDepth + 1
            if oldOk then pcall(oldOk) end
            okDepth = okDepth - 1
            if s and themeSess == s then
                s.cr, s.cg, s.cb = ColorPickerFrame:GetColorRGB()
                commitSess(s)
            end
        end)
    end
    local oldHide = ColorPickerFrame:GetScript("OnHide")
    ColorPickerFrame:SetScript("OnHide", function()
        if oldHide then oldHide() end
        -- Escape / another picker user: decide next frame, after any Okay func.
        if themeSess and okDepth == 0 then
            pendingHide = themeSess
            timer:Show()
        end
    end)
end

timer:SetScript("OnUpdate", function()
    local now = GetTime()
    local busy = false
    local k, j
    for k, j in pairs(jobs) do
        if j.due then
            if now >= j.due then runJob(j) else busy = true end
        end
    end
    local s = pendingHide
    pendingHide = nil
    if s and themeSess == s then
        if not ColorPickerFrame:IsShown() or ColorPickerFrame.func ~= s.func then
            cancelSess(s, nil)
        end
    end
    if not busy then this:Hide() end
end)

-- kind: "gold" or "fill" (the IchaUIDB key).
function IchaUI_ThemePickColor(kind)
    if not IchaUI_OpenColorPicker or not ColorPickerFrame then return end
    if themeSess then cancelSess(themeSess, nil) end
    local s = { kind = kind }
    local r, g, b
    if kind == "gold" then
        if IchaUI_ThemeGoldOn() then s.orig = rgbCopy(IchaUIDB.gold) end
        r, g, b = IchaUI_Gold()
    else
        s.orig = rgbCopy(IchaUIDB and IchaUIDB.fill)
        r, g, b = IchaUI_Fill()
    end
    s.cr, s.cg, s.cb = r, g, b
    IchaUI_OpenColorPicker(r, g, b, function(nr, ng, nb)
        if themeSess ~= s then return end
        -- Okay hides the frame (or runs inside our Okay hook) before func.
        if okDepth > 0 or not ColorPickerFrame:IsShown() then
            s.cr, s.cg, s.cb = clamp01(nr), clamp01(ng), clamp01(nb)
            commitSess(s)
        else
            dragSess(s, nr, ng, nb)
        end
    end, function(prev)
        cancelSess(s, prev)
    end)
    s.func = ColorPickerFrame.func
    hookPicker()
    themeSess = s
    IchaUI_ThemePreview()
end

-- Opacity slider: save at once, preview at once, repaint fills throttled.
function IchaUI_ThemeFillAlphaInput(v)
    v = clamp01(v)
    local d = v - IchaUI_ThemeFillAlpha()
    if d < 0 then d = -d end
    if d < 0.001 then return end
    if not IchaUIDB then IchaUIDB = {} end
    IchaUIDB.fillAlpha = v
    IchaUI_ThemePreview()
    throttle("fillAlpha", function()
        IchaUI_SetFillAlpha(IchaUI_ThemeFillAlpha())
    end)
end

function IchaUI_ThemeFillAlphaFlush()
    flushJob("fillAlpha")
end
