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

function IchaUI_PaintFill(f, a)
    if not f or not f.SetBackdropColor then return end
    a = tonumber(a) or 0.94
    if not f._ichaFillTracked then
        f._ichaFillTracked = true
        table.insert(fills, f)
    end
    f._ichaFillA = a
    local r, g, b = IchaUI_Fill()
    f:SetBackdropColor(r, g, b, a)
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
        IchaUI_PaintFill(f, ba or 0.94)
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

local function repaintTracked()
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
    -- Borders again after tab/config paint, which can SetBackdrop.
    callRefresh(repaintTracked)
    goldBusy = false
end
