-- IchaUI minimap skin (1.12 / RavenCraft)
-- Square gold frame, portrait-ring circle, circular frame art, SexyMap masks.
-- Zone title + clock detach/move/scale/hide. Mouse-wheel zoom. Lua 5.0-safe.
-- SexyMap shapes in that repo are static masks, not flipbooks. No fake spin.

local GOLD = { 0.78, 0.58, 0.16, 1 }
local BG = { 0.05, 0.05, 0.06, 0.72 }
local SQUARE_MASK = "Interface\\ChatFrame\\ChatFrameBackground"
-- Same circle as circledisc.tga, with clear corners forced black so a mask
-- that keys off color or alpha both crop. circledisc itself stays white.
local CIRCLE_MASK = "Interface\\AddOns\\IchaUI\\media\\mmcircle.tga"
local CIRCLE_COVER = "Interface\\AddOns\\IchaUI\\media\\roundmask-circle.tga"
local PORTRAIT_RING = "Interface\\AddOns\\IchaUI\\media\\minimapshapes\\x4\\PortraitFrame.tga"
local PORTRAIT_RING_BACKUP = "Interface\\AddOns\\IchaUI\\media\\PortraitFrame.tga"
local SHAPE_DIR = "Interface\\AddOns\\IchaUI\\media\\minimapshapes\\"
-- Nil or a removed shape (hexagon, diamond, rounded, ring) stays Square.
local SHAPE_ORDER = { "square", "circle" }
local SHAPE = {
    square = { label = "Square", square = true, mask = SQUARE_MASK },
    circle = {
        label = "Circle",
        mask = CIRCLE_MASK,
        cover = CIRCLE_COVER,
        ring = PORTRAIT_RING,
        ringBackup = PORTRAIT_RING_BACKUP,
        ringScale = 1.07,
        portrait = true,
        roundFallback = true,
    },
}

local function addFrame(id, label, file, scale)
    local info = {
        label = label,
        mask = CIRCLE_MASK,
        cover = CIRCLE_COVER,
        ring = SHAPE_DIR .. "x4\\" .. file,
        ringScale = scale,
        roundFallback = true,
    }
    SHAPE[id] = info
    table.insert(SHAPE_ORDER, id)
end

local function addMask(id, label, file, outline)
    local info = {
        label = label,
        mask = SHAPE_DIR .. file,
        maskOnly = true,
    }
    -- Outline is a baked tooltip edge: straight strip plus the matching arc.
    -- 560 canvas. The white bevel's inner edge is 16px in from the image
    -- edge. 560/528 draws that white edge on the map. The inner shadow may
    -- overlap the map; the stroke pixels stay solid.
    if outline then
        info.ring = SHAPE_DIR .. outline
        info.ringScale = 560 / 528
        info.goldBorder = true
    end
    SHAPE[id] = info
    table.insert(SHAPE_ORDER, id)
end

-- pfUI img borders are 64x8 edge strips (eight 8px tiles). Drawn with SetBackdrop,
-- the same way pfUI uses them. edgeOutset puts the inner side of the opaque
-- stroke on the map edge. Not the default Square tooltip frame.
local function addEdge(id, label, file, edgeSize, outset)
    SHAPE[id] = {
        label = label,
        square = true,
        mask = SHAPE_DIR .. "pfui\\minimap.tga",
        edgeFile = SHAPE_DIR .. "pfui\\" .. file,
        edgeSize = edgeSize,
        edgeOutset = outset,
    }
    table.insert(SHAPE_ORDER, id)
end

-- Scales put the solid inner edge of each x4 frame on the circle mask.
-- The 512 image is drawn smaller than its pixel size so it stays sharp.
-- Flash scales put the brightest ring on that same map edge.
addFrame("wowui", "WowUI", "WowUI_Circular_Frame.tga", 2.05)
addFrame("woodboards", "Wood Boards", "WoodBoards_Circular_Frame.tga", 1.95)
addFrame("pandarentraining", "Pandaren Training", "PandarenTraining_Circular_Frame.tga", 1.71)
addFrame("metalplain", "Metal Plain", "MetalPlain_Circular_Frame.tga", 1.94)
addFrame("metaleternium", "Metal Eternium", "MetalEternium_Circular_Frame.tga", 1.91)
addFrame("metalbronze", "Metal Bronze", "MetalBronze_Circular_Frame.tga", 1.94)
addFrame("horde", "Horde", "Horde_Circular_Frame.tga", 1.95)
addFrame("generic1target", "Generic Target", "Generic1Target_Circular_Frame.tga", 1.37)
addFrame("fire", "Fire", "Fire_Circular_Frame.tga", 2.03)
addFrame("arcaneflash", "Arcane Flash", "Arcane_Circular_Flash.tga", 1.89)
addFrame("arcane", "Arcane", "Arcane_Circular_Frame.tga", 1.92)

addMask("sm_circle", "SM Circle", "sm_circle.tga")
addMask("sm_largecircle", "SM Large Circle", "sm_largecircle.tga")
addMask("sm_tvfx", "SM Faded Square", "sm_t_vfx_border.tga")
addMask("sm_top", "SM Top", "sm_top.tga", "sm_top_border.tga")
addMask("sm_topleft", "SM Top Left", "sm_topleft.tga", "sm_topleft_border.tga")
addMask("sm_topright", "SM Top Right", "sm_topright.tga", "sm_topright_border.tga")
addMask("sm_bottom", "SM Bottom", "sm_bottom.tga", "sm_bottom_border.tga")
addMask("sm_bottomleft", "SM Bottom Left", "sm_bottomleft.tga", "sm_bottomleft_border.tga")
addMask("sm_bottomright", "SM Bottom Right", "sm_bottomright.tga", "sm_bottomright_border.tga")

addEdge("pfuisquare", "pfUI Square", "border.tga", 8, 1)
addEdge("pfuiblizz", "pfUI Blizz", "border_blizz.tga", 8, 6)
addEdge("pfuinotop", "pfUI No Top", "border_no_top.tga", 8, 1)

-- Baked circle of the tooltip border's straight edge. Not a 9-slice.
SHAPE["tooltipring"] = {
    label = "Tooltip Ring",
    mask = CIRCLE_MASK,
    cover = CIRCLE_COVER,
    ring = SHAPE_DIR .. "tooltip-ring.tga",
    ringScale = 1.06,
    roundFallback = true,
}
table.insert(SHAPE_ORDER, "tooltipring")
local DEFAULT_SIZE = 155
local DEFAULT_SCALE = 1.0
local DEFAULT_ZONE_SCALE = 1.0
local DEFAULT_CLOCK_SCALE = 1.0

local enabled = true
local mmScale = DEFAULT_SCALE
local mmSize = DEFAULT_SIZE
local zoneShow = true
local zoneScale = DEFAULT_ZONE_SCALE
local clockShow = true
local clockScale = DEFAULT_CLOCK_SCALE
local wheelZoom = true
local wheelFn
local chrome = nil
local mover = nil
local zoneMover = nil
local clockMover = nil
local mapMoveOn = false
local zoneMoveOn = false
local clockMoveOn = false
local zoneFrame = nil
local clockFrame = nil
local mmShape = "square"
local artR, artG, artB = 1, 1, 1
local shapeRing = nil
local shapeCover = nil
local tintedGold

local function db()
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.minimap then IchaUIDB.minimap = {} end
    return IchaUIDB.minimap
end

local function clamp(n, lo, hi)
    n = tonumber(n) or lo
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function knownShape(name)
    if name and SHAPE[name] then return name end
    return "square"
end

local function loadCfg()
    local d = db()
    if d.enabled ~= nil then enabled = d.enabled and true or false end
    mmShape = knownShape(d.shape)
    d.shape = mmShape
    d.frameDetail = nil
    artR = clamp(d.artR or 1, 0, 1)
    artG = clamp(d.artG or 1, 0, 1)
    artB = clamp(d.artB or 1, 0, 1)
    mmScale = clamp(d.scale or DEFAULT_SCALE, 0.4, 2.5)
    mmSize = clamp(d.size or DEFAULT_SIZE, 80, 280)
    if d.zoneShow ~= nil then zoneShow = d.zoneShow and true or false end
    zoneScale = clamp(d.zoneScale or DEFAULT_ZONE_SCALE, 0.5, 2.5)
    if d.clockShow ~= nil then clockShow = d.clockShow and true or false end
    clockScale = clamp(d.clockScale or DEFAULT_CLOCK_SCALE, 0.5, 2.5)
    if d.wheelZoom ~= nil then wheelZoom = d.wheelZoom and true or false end
    -- Drop corrupt/legacy non-CENTER point schemas
    if d.zonePoint and not (d.zonePoint == "CENTER" and d.zoneRelPoint == "CENTER") then
        d.zonePoint, d.zoneRelPoint, d.zoneX, d.zoneY, d.zoneAnchor = nil, nil, nil, nil, nil
    end
    if d.clockPoint and not (d.clockPoint == "CENTER" and d.clockRelPoint == "CENTER") then
        d.clockPoint, d.clockRelPoint, d.clockX, d.clockY, d.clockAnchor = nil, nil, nil, nil, nil
    end
end

local function savePointOf(frame, prefix)
    if not frame or not frame.GetLeft then return end
    local left = frame:GetLeft()
    local bottom = frame:GetBottom()
    if left == nil or bottom == nil then return end
    local fw = frame:GetWidth() or 0
    local fh = frame:GetHeight() or 0
    local d = db()
    -- Prefer Minimap-relative so zone/clock stay glued to the map when it moves
    if Minimap and Minimap.GetLeft then
        local ml = Minimap:GetLeft()
        local mb = Minimap:GetBottom()
        if ml ~= nil and mb ~= nil then
            local mw = Minimap:GetWidth() or 0
            local mh = Minimap:GetHeight() or 0
            local cx = (left + fw * 0.5) - (ml + mw * 0.5)
            local cy = (bottom + fh * 0.5) - (mb + mh * 0.5)
            d[prefix .. "Point"] = "CENTER"
            d[prefix .. "RelPoint"] = "CENTER"
            d[prefix .. "X"] = cx
            d[prefix .. "Y"] = cy
            d[prefix .. "Anchor"] = "minimap"
            return
        end
    end
    local uw = (UIParent and UIParent:GetWidth()) or 0
    local uh = (UIParent and UIParent:GetHeight()) or 0
    local cx = (left + fw * 0.5) - (uw * 0.5)
    local cy = (bottom + fh * 0.5) - (uh * 0.5)
    d[prefix .. "Point"] = "CENTER"
    d[prefix .. "RelPoint"] = "CENTER"
    d[prefix .. "X"] = cx
    d[prefix .. "Y"] = cy
    d[prefix .. "Anchor"] = "screen"
end

local function saveCfg()
    local d = db()
    d.enabled = enabled
    d.shape = mmShape
    d.frameDetail = nil
    d.artR = artR
    d.artG = artG
    d.artB = artB
    d.scale = mmScale
    d.size = mmSize
    d.zoneShow = zoneShow
    d.zoneScale = zoneScale
    d.clockShow = clockShow
    d.clockScale = clockScale
    d.wheelZoom = wheelZoom
    if Minimap and Minimap.GetPoint then
        local p, _, rp, x, y = Minimap:GetPoint(1)
        if p then
            d.point = p
            d.relPoint = rp or p
            d.x = tonumber(x) or 0
            d.y = tonumber(y) or 0
        end
    end
    -- Zone/clock anchors only saved on user drag (absolute UIParent coords).
end

local function nuke(t)
    if not t then return end
    if t.SetTexture then
        pcall(function() t:SetTexture("") end)
        pcall(function() t:SetTexture("Interface\\Buttons\\WHITE8X8") end)
    end
    if t.SetVertexColor then pcall(function() t:SetVertexColor(0, 0, 0, 0) end) end
    if t.SetAlpha then pcall(function() t:SetAlpha(0) end) end
    if t.Hide then pcall(function() t:Hide() end) end
end

local function hideNamed(name)
    local f = getglobal(name)
    if f then
        if f.Hide then pcall(function() f:Hide() end) end
        nuke(f)
    end
end

local function applyBackdrop(f, edge, fill)
    if not f or not f.SetBackdrop then return end
    -- Minimap chrome: gold edge only (no grey tooltip fill over the map)
    local bg = nil
    if fill then
        bg = "Interface\\Tooltips\\UI-Tooltip-Background"
    end
    f:SetBackdrop({
        bgFile = bg,
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = edge or 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    if fill then
        f:SetBackdropColor(BG[1], BG[2], BG[3], BG[4])
    else
        f:SetBackdropColor(0, 0, 0, 0)
    end
    IchaUI_PaintGoldBorder(f, 1)
end

-- Sit just ahead of the minimap (same strata, small level bump). Stay on UIParent
-- so StartMoving works and scale stays independent. Never HIGH/DIALOG/FULLSCREEN/TOOLTIP.
local function applyMinimapLayer(frame, bump)
    if not frame then return end
    local strata = "MEDIUM"
    if Minimap and Minimap.GetFrameStrata then
        strata = Minimap:GetFrameStrata() or strata
    else
        local cluster = getglobal("MinimapCluster")
        if cluster and cluster.GetFrameStrata then
            strata = cluster:GetFrameStrata() or strata
        end
    end
    if strata == "HIGH" or strata == "DIALOG" or strata == "FULLSCREEN"
        or strata == "FULLSCREEN_DIALOG" or strata == "TOOLTIP" then
        strata = "MEDIUM"
    end
    local ml = 2
    local cluster = getglobal("MinimapCluster")
    if cluster and cluster.GetFrameLevel then
        ml = cluster:GetFrameLevel() or 2
    elseif Minimap and Minimap.GetFrameLevel then
        ml = Minimap:GetFrameLevel() or 2
    end
    if ml < 2 then ml = 2 end
    bump = tonumber(bump) or 3
    if frame.SetParent and UIParent then
        local cur = nil
        if frame.GetParent then cur = frame:GetParent() end
        if cur ~= UIParent then
            pcall(function() frame:SetParent(UIParent) end)
        end
    end
    frame:SetFrameStrata(strata)
    local lvl = ml + bump
    if lvl < 1 then lvl = 1 end
    if lvl > 20 then lvl = 20 end
    frame:SetFrameLevel(lvl)
end

local function ensureChrome()
    if chrome then return chrome end
    chrome = CreateFrame("Frame", "IchaUIMinimapChrome", UIParent)
    chrome:EnableMouse(false)
    applyBackdrop(chrome, 12, false)
    return chrome
end

local function makeDragHandle(name, label, w)
    local m = CreateFrame("Button", name, UIParent)
    m:SetWidth(w or 70)
    m:SetHeight(16)
    applyMinimapLayer(m, 5)
    applyBackdrop(m, 8, true)
    local fs = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER", m, "CENTER", 0, 0)
    IchaUI_PaintGoldFont(fs, 0.78, 0.58, 0.16)
    fs:SetText(label)
    m:RegisterForDrag("LeftButton")
    m:EnableMouse(true)
    m:Hide()
    return m
end

-- Own zone + clock frames (Turtle/1.12 stock frames are flaky / GameTimeFrame is not a clock)
local function ensureZoneFrame()
    if zoneFrame then return zoneFrame end
    local f = CreateFrame("Frame", "IchaUIMinimapZone", UIParent)
    f:SetWidth(220)
    f:SetHeight(22)
    applyMinimapLayer(f, 3)
    f:EnableMouse(false)
    f:SetMovable(true)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER", f, "CENTER", 0, 0)
    IchaUI_PaintGoldFont(fs, 0.78, 0.58, 0.16)
    fs:SetJustifyH("CENTER")
    fs:SetWidth(220)
    f.text = fs
    zoneFrame = f
    return f
end

local function ensureClockFrame()
    if clockFrame then return clockFrame end
    local f = CreateFrame("Frame", "IchaUIMinimapClock", UIParent)
    f:SetWidth(64)
    f:SetHeight(20)
    applyMinimapLayer(f, 3)
    f:EnableMouse(false)
    f:SetMovable(true)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER", f, "CENTER", 0, 0)
    IchaUI_PaintGoldFont(fs, 0.78, 0.58, 0.16)
    fs:SetJustifyH("CENTER")
    fs:SetWidth(64)
    f.text = fs
    clockFrame = f
    return f
end

local function refreshZoneText()
    local f = zoneFrame
    if not f or not f.text then return end
    local name = nil
    if GetMinimapZoneText then
        name = GetMinimapZoneText()
    end
    if (not name or name == "") and GetZoneText then
        name = GetZoneText()
    end
    if (not name or name == "") and GetRealZoneText then
        name = GetRealZoneText()
    end
    f.text:SetText(name or "")
    -- PvP difficulty tint when available
    if GetZonePVPInfo then
        local pvp = GetZonePVPInfo()
        if pvp == "sanctuary" then
            f.text:SetTextColor(0.41, 0.8, 0.94)
        elseif pvp == "arena" then
            f.text:SetTextColor(1.0, 0.1, 0.1)
        elseif pvp == "friendly" then
            f.text:SetTextColor(0.1, 1.0, 0.1)
        elseif pvp == "hostile" then
            f.text:SetTextColor(1.0, 0.1, 0.1)
        elseif pvp == "contested" then
            f.text:SetTextColor(1.0, 0.7, 0.0)
        else
            IchaUI_PaintGoldFont(f.text, 0.78, 0.58, 0.16)
        end
    else
        IchaUI_PaintGoldFont(f.text, 0.78, 0.58, 0.16)
    end
end

local function refreshClockText()
    local f = clockFrame
    if not f or not f.text then return end
    local h, m = 0, 0
    if GetGameTime then
        h, m = GetGameTime()
    end
    h = tonumber(h) or 0
    m = tonumber(m) or 0
    f.text:SetText(string.format("%d:%02d", h, m))
end

-- Hide stock zone title so we do not double-draw
local function hideStockZone()
    local names = {
        "MinimapZoneTextButton",
        "MinimapZoneText",
        "MinimapToggleButton",
    }
    local i
    for i = 1, table.getn(names) do
        local o = getglobal(names[i])
        if o then
            if o.Hide then pcall(function() o:Hide() end) end
            if o.SetAlpha then pcall(function() o:SetAlpha(0) end) end
        end
    end
end

local function applySavedPoint(frame, prefix, myPoint, relPoint, fx, fy, relFrame)
    if not frame then return end
    local d = db()
    local pt = d[prefix .. "Point"]
    local rp = d[prefix .. "RelPoint"]
    local anchor = d[prefix .. "Anchor"]
    frame:ClearAllPoints()
    if pt == "CENTER" and rp == "CENTER" and anchor == "minimap" and Minimap then
        frame:SetPoint("CENTER", Minimap, "CENTER", d[prefix .. "X"] or 0, d[prefix .. "Y"] or 0)
    elseif pt == "CENTER" and rp == "CENTER" and (anchor == "screen" or anchor == nil) then
        -- Legacy absolute screen save (pre-minimap-anchor)
        frame:SetPoint("CENTER", UIParent, "CENTER", d[prefix .. "X"] or 0, d[prefix .. "Y"] or 0)
    else
        -- Default: glued to the minimap
        local rel = relFrame or Minimap or UIParent
        frame:SetPoint(myPoint or "TOP", rel, relPoint or myPoint or "TOP", fx or 0, fy or 12)
    end
end

-- Locked: click-through (EnableMouse false). Unlocked: drag, no Shift required.
local function wireMoveLock(frame, unlocked, onStop)
    if not frame then return end
    frame:SetMovable(true)
    applyMinimapLayer(frame, 3)
    if unlocked then
        if frame.EnableMouse then frame:EnableMouse(true) end
        if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
        frame:SetScript("OnDragStart", function()
            this:StartMoving()
        end)
        frame:SetScript("OnDragStop", function()
            this:StopMovingOrSizing()
            if onStop then onStop() end
        end)
    else
        if frame.StopMovingOrSizing then pcall(function() frame:StopMovingOrSizing() end) end
        if frame.EnableMouse then frame:EnableMouse(false) end
        if frame.RegisterForDrag then pcall(function() frame:RegisterForDrag() end) end
        frame:SetScript("OnDragStart", nil)
        frame:SetScript("OnDragStop", nil)
    end
end

local function applyZone()
    local f = ensureZoneFrame()
    hideStockZone()
    applyMinimapLayer(f, 3)
    applySavedPoint(f, "zone", "BOTTOM", "TOP", 0, 10, Minimap)

    pcall(function() f:SetScale(zoneScale) end)
    local fontPath = GameFontNormal:GetFont()
    if fontPath and f.text then
        local fs = math.max(9, math.floor(12 * zoneScale + 0.5))
        pcall(function() f.text:SetFont(fontPath, fs, "OUTLINE") end)
    end
    refreshZoneText()

    if zoneShow and enabled then
        f:Show()
    else
        f:Hide()
    end

    wireMoveLock(f, zoneMoveOn and zoneShow and enabled, function()
        savePointOf(f, "zone")
        saveCfg()
    end)

    if not zoneMover then
        zoneMover = makeDragHandle("IchaUIMinimapZoneMover", "Zone", 50)
        zoneMover:SetScript("OnDragStart", function()
            local z = ensureZoneFrame()
            if z then z:StartMoving() end
        end)
        zoneMover:SetScript("OnDragStop", function()
            local z = ensureZoneFrame()
            if z then
                z:StopMovingOrSizing()
                savePointOf(z, "zone")
                saveCfg()
            end
        end)
    end
    applyMinimapLayer(zoneMover, 5)
    zoneMover:ClearAllPoints()
    zoneMover:SetPoint("BOTTOM", f, "TOP", 0, 2)
    if zoneMoveOn and zoneShow and enabled then zoneMover:Show() else zoneMover:Hide() end
end

local function applyClock()
    local f = ensureClockFrame()
    -- Hide stock day/night button only if we are showing our digital clock on top of it
    local gt = getglobal("GameTimeFrame")
    local tm = getglobal("TimeManagerClockButton")
    if clockShow then
        if gt then pcall(function() gt:Hide() end) end
        if tm then pcall(function() tm:Hide() end) end
    end

    applyMinimapLayer(f, 3)
    applySavedPoint(f, "clock", "TOPRIGHT", "BOTTOMRIGHT", 0, -4, Minimap)

    pcall(function() f:SetScale(clockScale) end)
    local fontPath = GameFontNormal:GetFont()
    if fontPath and f.text then
        local fs = math.max(9, math.floor(12 * clockScale + 0.5))
        pcall(function() f.text:SetFont(fontPath, fs, "OUTLINE") end)
    end
    refreshClockText()

    if clockShow and enabled then
        f:Show()
    else
        f:Hide()
    end

    wireMoveLock(f, clockMoveOn and clockShow and enabled, function()
        savePointOf(f, "clock")
        saveCfg()
    end)

    if not clockMover then
        clockMover = makeDragHandle("IchaUIMinimapClockMover", "Clock", 50)
        clockMover:SetScript("OnDragStart", function()
            local c = ensureClockFrame()
            if c then c:StartMoving() end
        end)
        clockMover:SetScript("OnDragStop", function()
            local c = ensureClockFrame()
            if c then
                c:StopMovingOrSizing()
                savePointOf(c, "clock")
                saveCfg()
            end
        end)
    end
    applyMinimapLayer(clockMover, 5)
    clockMover:ClearAllPoints()
    clockMover:SetPoint("BOTTOM", f, "TOP", 0, 2)
    if clockMoveOn and clockShow and enabled then clockMover:Show() else clockMover:Hide() end
end

local function shapeDef(name)
    local info = SHAPE[name or "square"]
    if not info then info = SHAPE.square end
    return info
end

local function nextShapeName(cur)
    local i
    local n = table.getn(SHAPE_ORDER)
    for i = 1, n do
        if SHAPE_ORDER[i] == cur then
            local j = i + 1
            if j > n then j = 1 end
            return SHAPE_ORDER[j]
        end
    end
    return "square"
end

local function hideShapeArt()
    if shapeRing then shapeRing:Hide() end
    if shapeCover then shapeCover:Hide() end
end

local function ensureShapeRing()
    if shapeRing then return shapeRing end
    if not Minimap then return nil end
    -- Child of Minimap so the ring scales with the map. 1.12 does not clip children.
    local f = CreateFrame("Frame", "IchaUIMinimapRing", Minimap)
    f:EnableMouse(false)
    local gold = f:CreateTexture(nil, "OVERLAY")
    gold:SetAllPoints(f)
    if gold.SetTexCoord then gold:SetTexCoord(0, 1, 0, 1) end
    gold:Hide()
    f.goldTex = gold
    local art = f:CreateTexture(nil, "OVERLAY")
    art:SetAllPoints(f)
    if art.SetTexCoord then art:SetTexCoord(0, 1, 0, 1) end
    art:Hide()
    f.artTex = art
    f:Hide()
    shapeRing = f
    return f
end

local function ensureShapeCover()
    if shapeCover then return shapeCover end
    if not Minimap then return nil end
    local f = CreateFrame("Frame", "IchaUIMinimapShapeCover", Minimap)
    f:SetAllPoints(Minimap)
    f:EnableMouse(false)
    local tex = f:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(f)
    tex:SetVertexColor(0, 0, 0, 1)
    if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
    f.tex = tex
    f:Hide()
    shapeCover = f
    return f
end

-- Square uses the full mask already in this skin. Other shapes swap that
-- for a disc/shape TGA (opaque inside, clear outside). If the client has no
-- SetMaskTexture, the cover TGA blacks out the corners the way round buttons do.
local function tryEngineMask(path)
    if not Minimap or not Minimap.SetMaskTexture or not path or path == "" then
        return false
    end
    local ok = pcall(function() Minimap:SetMaskTexture(path) end)
    if ok then return true end
    return false
end

local function applyShapeMask(info)
    local cover = ensureShapeCover()
    if info.square then
        tryEngineMask(info.mask or SQUARE_MASK)
        if cover then cover:Hide() end
        return
    end
    local clipped = tryEngineMask(info.mask or CIRCLE_MASK)
    if (not clipped) and info.roundFallback then
        clipped = tryEngineMask("Textures\\MinimapMask")
    end
    if clipped or not info.cover or not cover or not cover.tex then
        if cover then cover:Hide() end
        return
    end
    cover.tex:SetTexture(info.cover)
    cover.tex:SetVertexColor(0, 0, 0, 1)
    if cover.tex.SetTexCoord then cover.tex:SetTexCoord(0, 1, 0, 1) end
    local ml = 2
    if Minimap.GetFrameLevel then ml = Minimap:GetFrameLevel() or 2 end
    local lvl = ml + 2
    if lvl < 1 then lvl = 1 end
    if lvl > 20 then lvl = 20 end
    cover:SetFrameLevel(lvl)
    cover:ClearAllPoints()
    cover:SetAllPoints(Minimap)
    cover:Show()
end

local function applyShapeRing(info)
    local f = ensureShapeRing()
    if not f then return end
    if not info or not info.ring then
        f:Hide()
        return
    end
    local tex
    if info.portrait then
        if f.artTex then f.artTex:Hide() end
        tex = f.goldTex
    else
        if f.goldTex then f.goldTex:Hide() end
        tex = f.artTex
    end
    if not tex then
        f:Hide()
        return
    end
    tex:Show()
    tex:SetTexture(info.ring)
    f.artPath = info.ring
    if info.portrait and info.ringBackup and tex.GetTexture and (not tex:GetTexture() or tex:GetTexture() == "") then
        tex:SetTexture(info.ringBackup)
    end
    if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
    if tex.SetBlendMode then tex:SetBlendMode("BLEND") end
    if info.goldBorder then
        local br, bgc, bb = tintedGold()
        tex:SetVertexColor(br, bgc, bb, 1)
    else
        tex:SetVertexColor(artR, artG, artB, 1)
    end
    local strata = "MEDIUM"
    if Minimap.GetFrameStrata then strata = Minimap:GetFrameStrata() or strata end
    if strata == "HIGH" or strata == "DIALOG" or strata == "FULLSCREEN"
        or strata == "FULLSCREEN_DIALOG" or strata == "TOOLTIP" then
        strata = "MEDIUM"
    end
    local ml = Minimap:GetFrameLevel() or 2
    f:SetFrameStrata(strata)
    local lvl = ml + 3
    if lvl < 1 then lvl = 1 end
    if lvl > 20 then lvl = 20 end
    f:SetFrameLevel(lvl)
    pcall(function() f:SetScale(1) end)
    local side = mmSize * (info.ringScale or 1)
    if side < 16 then side = 16 end
    f:SetWidth(side)
    f:SetHeight(side)
    f:ClearAllPoints()
    f:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
    f:Show()
end

tintedGold = function()
    local gr, gg, gb = 0.75, 0.52, 0.04
    if IchaUI_Gold then
        gr, gg, gb = IchaUI_Gold()
    end
    return gr * artR, gg * artG, gb * artB
end

local function applyMaskTint()
    -- Tint colors the border art only. This overlay used to multiply
    -- the mask color onto the map.
    local f = getglobal("IchaUIMinimapMaskTint")
    if f then f:Hide() end
end

local function applyShape()
    local info = shapeDef(mmShape)
    applyShapeMask(info)
    applyMaskTint(info)
    if info.square then
        if shapeRing then shapeRing:Hide() end
    else
        applyShapeRing(info)
    end
    return info
end

-- ShaguTweaks MiniMap Tweaks: wheel over the map calls Minimap_ZoomIn/Out.
-- Magnify zooms the world map, not the minimap; if a Magnify build already
-- hooked Minimap, leave that handler so wheel does not double-step.
local function magnifyOwnsMinimapWheel()
    if not (IsAddOnLoaded and IsAddOnLoaded("Magnify")) then return false end
    if not Minimap or not Minimap.GetScript then return false end
    local s = Minimap:GetScript("OnMouseWheel")
    if not s or s == wheelFn then return false end
    return true
end

local function stepMinimapZoom(delta)
    if not Minimap or not delta or delta == 0 then return end
    if delta > 0 then
        if Minimap_ZoomIn then
            local ok = pcall(Minimap_ZoomIn)
            if ok then return end
        end
        if not Minimap.GetZoom or not Minimap.SetZoom then return end
        local z = Minimap:GetZoom() or 0
        local hi = 5
        if Minimap.GetZoomLevels then
            local n = Minimap:GetZoomLevels()
            if n and n > 0 then hi = n - 1 end
        end
        if z < hi then Minimap:SetZoom(z + 1) end
    else
        if Minimap_ZoomOut then
            local ok = pcall(Minimap_ZoomOut)
            if ok then return end
        end
        if not Minimap.GetZoom or not Minimap.SetZoom then return end
        local z = Minimap:GetZoom() or 0
        if z > 0 then Minimap:SetZoom(z - 1) end
    end
end

wheelFn = function()
    if not wheelZoom then return end
    if IsControlKeyDown and IsControlKeyDown() then return end
    if IsShiftKeyDown and IsShiftKeyDown() then return end
    local d = tonumber(arg1)
    if d == nil then return end
    stepMinimapZoom(d)
end

local function hookWheel(frame, on)
    if not frame or not frame.SetScript then return end
    if on then
        frame:SetScript("OnMouseWheel", wheelFn)
        if frame.EnableMouseWheel then frame:EnableMouseWheel(true) end
    else
        local cur = frame.GetScript and frame:GetScript("OnMouseWheel")
        if cur == wheelFn then
            frame:SetScript("OnMouseWheel", nil)
            if frame.EnableMouseWheel then frame:EnableMouseWheel(false) end
        end
    end
end

local function applyWheelZoom()
    local on = wheelZoom and true or false
    if Minimap then
        if on and magnifyOwnsMinimapWheel() then
            -- Magnify already zooms the minimap
        else
            hookWheel(Minimap, on)
        end
    end
    hookWheel(chrome, on)
    hookWheel(shapeRing, on)
    hookWheel(shapeCover, on)
    hookWheel(zoneFrame, on)
    hookWheel(clockFrame, on)
    hookWheel(mover, on)
    hookWheel(zoneMover, on)
    hookWheel(clockMover, on)
    hookWheel(getglobal("MinimapZoomIn"), on)
    hookWheel(getglobal("MinimapZoomOut"), on)
end

local function applySkin()
    if not Minimap then return end
    loadCfg()
    if not enabled then
        if chrome then chrome:Hide() end
        if mover then mover:Hide() end
        if zoneMover then zoneMover:Hide() end
        if clockMover then clockMover:Hide() end
        hideShapeArt()
        applyWheelZoom()
        return
    end

    -- Hide default circular border art
    hideNamed("MinimapBorder")
    hideNamed("MinimapBorderTop")
    hideNamed("MinimapBackdrop")
    hideNamed("MiniMapBattlefieldBorder")
    -- Keep zoom buttons usable; restyle lightly if present
    local zi = getglobal("MinimapZoomIn")
    local zo = getglobal("MinimapZoomOut")
    if zi and zi.SetAlpha then pcall(function() zi:SetAlpha(0.85) end) end
    if zo and zo.SetAlpha then pcall(function() zo:SetAlpha(0.85) end) end

    local sz = mmSize
    Minimap:SetWidth(sz)
    Minimap:SetHeight(sz)
    Minimap:SetScale(mmScale)
    local info = applyShape()

    local d = db()
    if d.point then
        Minimap:ClearAllPoints()
        Minimap:SetPoint(d.point, UIParent, d.relPoint or d.point, d.x or 0, d.y or 0)
    end

    Minimap:SetMovable(true)
    Minimap:EnableMouse(true)
    if mapMoveOn then
        Minimap:RegisterForDrag("LeftButton")
        Minimap:SetScript("OnDragStart", function()
            this:StartMoving()
        end)
        Minimap:SetScript("OnDragStop", function()
            this:StopMovingOrSizing()
            saveCfg()
        end)
    else
        if Minimap.RegisterForDrag then pcall(function() Minimap:RegisterForDrag() end) end
        Minimap:SetScript("OnDragStart", nil)
        Minimap:SetScript("OnDragStop", nil)
    end

    local c = ensureChrome()
    local strata = "MEDIUM"
    if Minimap.GetFrameStrata then strata = Minimap:GetFrameStrata() or strata end
    local ml = Minimap:GetFrameLevel() or 2
    if ml < 2 then ml = 2 end
    c:SetFrameStrata(strata)
    c:SetFrameLevel(ml - 1)
    c:ClearAllPoints()
    -- Default Square stays 3px outside the map. pfUI edges use their own outset
    -- so the opaque stroke meets the map. 4px on Square left the gold inner
    -- edge about 1px short, most visibly along the bottom.
    local ox = 3
    if info.edgeOutset then ox = info.edgeOutset end
    c:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -ox, ox)
    c:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", ox, -ox)
    if info.square then
        if info.edgeFile then
            c:SetBackdrop({
                bgFile = nil,
                edgeFile = info.edgeFile,
                tile = true, tileSize = 8, edgeSize = info.edgeSize or 8,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            c:SetBackdropColor(0, 0, 0, 0)
            c:SetBackdropBorderColor(artR, artG, artB, 1)
            c:Show()
        else
            applyBackdrop(c, 12, false)
            local br, bgc, bb = tintedGold()
            c:SetBackdropBorderColor(br, bgc, bb, 1)
            c:Show()
        end
    else
        c:Hide()
    end

    if not mover then
        mover = makeDragHandle("IchaUIMinimapMover", "Minimap", 60)
        mover:SetScript("OnDragStart", function()
            Minimap:StartMoving()
        end)
        mover:SetScript("OnDragStop", function()
            Minimap:StopMovingOrSizing()
            saveCfg()
        end)
    end
    applyMinimapLayer(mover, 5)
    mover:ClearAllPoints()
    mover:SetPoint("BOTTOM", Minimap, "TOP", 0, 6)
    if mapMoveOn then mover:Show() else mover:Hide() end

    applyZone()
    applyClock()
    applyWheelZoom()

    saveCfg()
end

local function unskin()
    if chrome then chrome:Hide() end
    hideShapeArt()
    if mover then mover:Hide() end
    if zoneMover then zoneMover:Hide() end
    if clockMover then clockMover:Hide() end
    if zoneFrame then
        if zoneFrame.EnableMouse then zoneFrame:EnableMouse(false) end
        zoneFrame:Hide()
    end
    if clockFrame then
        if clockFrame.EnableMouse then clockFrame:EnableMouse(false) end
        clockFrame:Hide()
    end
    applyWheelZoom()
end

local function bakedMinimap()
    local base = IchaUI_BakedGet and IchaUI_BakedGet("minimap")
    if type(base) ~= "table" then base = {} end
    return base
end

local function clearSavedPoint(prefix)
    local d = db()
    local base = bakedMinimap()
    d[prefix .. "Point"] = base[prefix .. "Point"]
    d[prefix .. "RelPoint"] = base[prefix .. "RelPoint"]
    d[prefix .. "X"] = base[prefix .. "X"]
    d[prefix .. "Y"] = base[prefix .. "Y"]
    d[prefix .. "Anchor"] = base[prefix .. "Anchor"]
end

-- Reset map / zone / clock to the baked default anchors (IchaUI\Defaults.lua).
function IchaUIMinimap_Reset(which)
    loadCfg()
    which = which or "all"
    local d = db()
    if which == "map" or which == "all" then
        local base = bakedMinimap()
        d.point, d.relPoint, d.x, d.y = base.point, base.relPoint, base.x, base.y
        mapMoveOn = false
        if Minimap then
            Minimap:ClearAllPoints()
            if d.point then
                Minimap:SetPoint(d.point, UIParent, d.relPoint or d.point, d.x or 0, d.y or 0)
            else
                Minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -20)
            end
        end
    end
    if which == "zone" or which == "all" then
        clearSavedPoint("zone")
        zoneMoveOn = false
    end
    if which == "clock" or which == "all" then
        clearSavedPoint("clock")
        clockMoveOn = false
    end
    saveCfg()
    if enabled then
        applySkin()
    end
end

function IchaUIMinimap_Get()
    loadCfg()
    local d = db()
    return {
        enabled = enabled,
        shape = mmShape,
        artR = artR,
        artG = artG,
        artB = artB,
        scale = mmScale,
        size = mmSize,
        point = d.point,
        x = d.x,
        y = d.y,
        zoneShow = zoneShow,
        zoneScale = zoneScale,
        zonePoint = d.zonePoint,
        zoneX = d.zoneX,
        zoneY = d.zoneY,
        clockShow = clockShow,
        clockScale = clockScale,
        clockPoint = d.clockPoint,
        clockX = d.clockX,
        clockY = d.clockY,
        mapMoving = mapMoveOn and true or false,
        zoneMoving = zoneMoveOn and true or false,
        clockMoving = clockMoveOn and true or false,
        wheelZoom = wheelZoom and true or false,
    }
end

function IchaUIMinimap_Set(field, value)
    loadCfg()
    if field == "enabled" then
        enabled = value and true or false
        saveCfg()
        if enabled then applySkin() else unskin() end
        return
    elseif field == "scale" then
        mmScale = clamp(value, 0.4, 2.5)
    elseif field == "size" then
        mmSize = clamp(value, 80, 280)
    elseif field == "shape" then
        mmShape = knownShape(value)
    elseif field == "move" then
        mapMoveOn = not mapMoveOn
        if enabled then applySkin() end
        return
    elseif field == "zoneShow" then
        zoneShow = value and true or false
        saveCfg()
        if enabled then applyZone() end
        return
    elseif field == "zoneScale" then
        zoneScale = clamp(value, 0.5, 2.5)
        saveCfg()
        if enabled then applyZone() end
        return
    elseif field == "zoneMove" then
        zoneMoveOn = not zoneMoveOn
        if enabled then applyZone() end
        return
    elseif field == "clockShow" then
        clockShow = value and true or false
        saveCfg()
        if enabled then applyClock() end
        return
    elseif field == "clockScale" then
        clockScale = clamp(value, 0.5, 2.5)
        saveCfg()
        if enabled then applyClock() end
        return
    elseif field == "clockMove" then
        clockMoveOn = not clockMoveOn
        if enabled then applyClock() end
        return
    elseif field == "wheelZoom" then
        wheelZoom = value and true or false
        saveCfg()
        applyWheelZoom()
        return
    elseif field == "reset" then
        IchaUIMinimap_Reset(value or "all")
        return
    elseif field == "resetMap" then
        IchaUIMinimap_Reset("map")
        return
    elseif field == "resetZone" then
        IchaUIMinimap_Reset("zone")
        return
    elseif field == "resetClock" then
        IchaUIMinimap_Reset("clock")
        return
    end
    saveCfg()
    if enabled then applySkin() end
end

function IchaUIMinimap_ShapeName()
    loadCfg()
    local info = shapeDef(mmShape)
    if info and info.label then return info.label end
    return "Square"
end

function IchaUIMinimap_CycleShape()
    loadCfg()
    IchaUIMinimap_Set("shape", nextShapeName(mmShape))
    return IchaUIMinimap_ShapeName()
end

function IchaUIMinimap_ShapeList()
    local out = {}
    local i
    local n = table.getn(SHAPE_ORDER)
    for i = 1, n do
        local id = SHAPE_ORDER[i]
        local info = SHAPE[id]
        local row = { id = id, label = "Square" }
        if info and info.label then row.label = info.label end
        if info and info.edgeFile then
            row.kind = "edge"
            row.tex = info.edgeFile
            row.edgeSize = info.edgeSize
        elseif info and info.square then
            row.kind = "square"
        elseif info and info.maskOnly then
            row.kind = "mask"
            if info.goldBorder and info.ring then
                row.tex = info.ring
                row.goldBorder = true
            else
                row.tex = info.mask
            end
        elseif info and info.portrait then
            row.kind = "portrait"
            row.tex = info.ring
        else
            row.kind = "frame"
            if info then row.tex = info.ring end
        end
        table.insert(out, row)
    end
    return out
end

local shapePicker = nil
local shapePickerWatch = nil

local function dyePickerText(fs, r, g, b)
    if not fs or not fs.SetTextColor then return end
    local path, size, flags
    if GameFontHighlight and GameFontHighlight.GetFont then
        path, size, flags = GameFontHighlight:GetFont()
    end
    if (not path or path == "") and GameFontNormal and GameFontNormal.GetFont then
        path, size, flags = GameFontNormal:GetFont()
    end
    if path and path ~= "" and fs.SetFont then
        fs:SetFont(path, size or 10, flags or "")
    end
    fs:SetTextColor(r, g, b)
end

local function specialIndex(name)
    if not UISpecialFrames then return nil end
    local i
    local n = table.getn(UISpecialFrames)
    for i = 1, n do
        if UISpecialFrames[i] == name then return i end
    end
    return nil
end

local function removeSpecial(name)
    local i = specialIndex(name)
    if not i then return end
    table.remove(UISpecialFrames, i)
end

local function paintShapeCell(cell, selected)
    if not cell then return end
    cell._selected = selected
    if selected then
        cell:SetBackdropColor(0.18, 0.14, 0.05, 0.98)
        cell:SetBackdropBorderColor(1, 0.86, 0.35, 1)
    else
        cell:SetBackdropColor(0.06, 0.06, 0.07, 0.94)
        if IchaUI_PaintGoldBorder then
            IchaUI_PaintGoldBorder(cell, 0.75)
        else
            cell:SetBackdropBorderColor(0.75, 0.6, 0.2, 1)
        end
    end
end

local function applyPickerTint()
    if not shapePicker or not shapePicker.cells then return end
    local br, bgc, bb = tintedGold()
    local i
    local n = table.getn(shapePicker.cells)
    for i = 1, n do
        local cell = shapePicker.cells[i]
        if cell.kind == "square" then
            if cell.squarePrev and cell.squarePrev.SetBackdropBorderColor then
                cell.squarePrev:SetBackdropBorderColor(br, bgc, bb, 1)
            end
        elseif cell.kind == "edge" then
            if cell.squarePrev and cell.squarePrev.SetBackdropBorderColor then
                cell.squarePrev:SetBackdropBorderColor(artR, artG, artB, 1)
            end
        elseif cell.goldBorder and cell.preview and cell.preview.SetVertexColor then
            cell.preview:SetVertexColor(br, bgc, bb, 1)
            if cell.preview.SetBlendMode then cell.preview:SetBlendMode("BLEND") end
        elseif cell.preview and cell.preview.SetVertexColor then
            cell.preview:SetVertexColor(artR, artG, artB, 1)
            if cell.preview.SetBlendMode then cell.preview:SetBlendMode("BLEND") end
        end
    end
end

local function ensureShapePicker()
    if shapePicker then return shapePicker end
    local f = CreateFrame("Frame", "IchaUIMinimapShapePicker", UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(50)
    f:EnableMouse(true)
    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.04, 0.04, 0.05, 0.97)
    if IchaUI_PaintGoldBorder then
        IchaUI_PaintGoldBorder(f, 1)
    else
        f:SetBackdropBorderColor(0.93, 0.78, 0.35, 1)
    end
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", f, "TOP", 0, -14)
    title:SetText("Minimap shape")
    dyePickerText(title, 1, 0.9, 0.55)
    f.title = title

    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetWidth(64)
    closeBtn:SetHeight(20)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -12)
    closeBtn:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    closeBtn:SetBackdropColor(0.08, 0.08, 0.09, 0.92)
    if IchaUI_PaintGoldBorder then IchaUI_PaintGoldBorder(closeBtn, 0.85) end
    local closeFs = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    closeFs:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    closeFs:SetText("Close")
    dyePickerText(closeFs, 1, 1, 1)
    closeBtn:SetScript("OnClick", function()
        f:Hide()
    end)
    closeBtn:SetScript("OnEnter", function()
        this:SetBackdropBorderColor(1, 0.9, 0.5, 1)
    end)
    closeBtn:SetScript("OnLeave", function()
        if IchaUI_PaintGoldBorder then IchaUI_PaintGoldBorder(this, 0.85) end
    end)

    local list = IchaUIMinimap_ShapeList()
    local cols = 6
    local cellW = 108
    local cellH = 96
    local gap = 6
    local n = table.getn(list)
    local rows = math.floor((n + cols - 1) / cols)
    if rows < 1 then rows = 1 end
    local gridW = cols * cellW + (cols - 1) * gap
    local gridH = rows * cellH + (rows - 1) * gap
    f:SetWidth(gridW + 36)
    f:SetHeight(gridH + 58)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)

    f.cells = {}
    local i
    for i = 1, n do
        local info = list[i]
        local col = math.mod(i - 1, cols)
        local row = math.floor((i - 1) / cols)
        local cell = CreateFrame("Button", nil, f)
        cell:SetWidth(cellW)
        cell:SetHeight(cellH)
        cell:SetPoint("TOPLEFT", f, "TOPLEFT", 18 + col * (cellW + gap), -40 - row * (cellH + gap))
        cell:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        cell.shapeId = info.id
        cell.kind = info.kind
        cell.goldBorder = info.goldBorder
        cell:SetScript("OnClick", function()
            if not this.shapeId or not IchaUIMinimap_Set then return end
            IchaUIMinimap_Set("shape", this.shapeId)
            if IchaUI_MinimapShapeButton and IchaUIMinimap_ShapeName then
                IchaUI_MinimapShapeButton:SetText("Shape: " .. IchaUIMinimap_ShapeName())
            end
            local ci
            local cn = table.getn(f.cells)
            for ci = 1, cn do
                paintShapeCell(f.cells[ci], f.cells[ci].shapeId == this.shapeId)
            end
            f:Hide()
        end)
        cell:SetScript("OnEnter", function()
            if this._selected then return end
            this:SetBackdropBorderColor(1, 0.9, 0.5, 1)
        end)
        cell:SetScript("OnLeave", function()
            paintShapeCell(this, this._selected)
        end)

        local tex = cell:CreateTexture(nil, "ARTWORK")
        tex:SetWidth(68)
        tex:SetHeight(68)
        tex:SetPoint("TOP", cell, "TOP", 0, -6)
        if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
        cell.preview = tex

        local sq = CreateFrame("Frame", nil, cell)
        sq:SetWidth(68)
        sq:SetHeight(68)
        sq:SetPoint("TOP", cell, "TOP", 0, -6)
        sq:EnableMouse(false)
        sq:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        sq:SetBackdropColor(0.05, 0.05, 0.06, 1)
        cell.squarePrev = sq

        if info.kind == "square" then
            tex:Hide()
            sq:Show()
        elseif info.kind == "edge" then
            tex:Hide()
            sq:SetBackdrop({
                bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                edgeFile = info.tex,
                tile = true, tileSize = 8, edgeSize = info.edgeSize or 8,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            sq:SetBackdropColor(0.05, 0.05, 0.06, 1)
            sq:SetBackdropBorderColor(artR, artG, artB, 1)
            sq:Show()
        else
            sq:Hide()
            tex:Show()
            if info.tex then tex:SetTexture(info.tex) end
            if info.goldBorder then
                local br, bgc, bb = tintedGold()
                tex:SetVertexColor(br, bgc, bb, 1)
            else
                tex:SetVertexColor(artR, artG, artB, 1)
            end
            if tex.SetBlendMode then tex:SetBlendMode("BLEND") end
        end

        local lab = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lab:SetPoint("BOTTOM", cell, "BOTTOM", 0, 5)
        lab:SetWidth(cellW - 8)
        lab:SetJustifyH("CENTER")
        lab:SetText(info.label or "")
        dyePickerText(lab, 1, 1, 1)
        paintShapeCell(cell, false)
        table.insert(f.cells, cell)
    end

    f:SetScript("OnShow", function()
        removeSpecial("IchaUIOptions")
        if not specialIndex("IchaUIMinimapShapePicker") then
            table.insert(UISpecialFrames, "IchaUIMinimapShapePicker")
        end
        local cur = "square"
        if IchaUIMinimap_Get then
            local g = IchaUIMinimap_Get()
            if g and g.shape then cur = g.shape end
        end
        local ci
        local cn = table.getn(this.cells)
        for ci = 1, cn do
            paintShapeCell(this.cells[ci], this.cells[ci].shapeId == cur)
        end
        applyPickerTint()
    end)
    f:SetScript("OnHide", function()
        -- Hidden frames do not receive OnUpdate. A one-shot watcher restores
        -- the config window after Escape finishes closing this picker.
        if shapePickerWatch then shapePickerWatch:Show() end
    end)

    if not shapePickerWatch then
        shapePickerWatch = CreateFrame("Frame", nil, UIParent)
        shapePickerWatch:Hide()
        shapePickerWatch:SetScript("OnUpdate", function()
            this:Hide()
            removeSpecial("IchaUIMinimapShapePicker")
            if IchaUIOptions and IchaUIOptions.IsShown and IchaUIOptions:IsShown() then
                if not specialIndex("IchaUIOptions") then
                    table.insert(UISpecialFrames, "IchaUIOptions")
                end
            end
        end)
    end

    shapePicker = f
    return f
end

function IchaUIMinimap_OpenShapePicker()
    local f = ensureShapePicker()
    if not f then return end
    f:Show()
end

function IchaUIMinimap_SetArtTint(r, g, b)
    loadCfg()
    artR = clamp(r, 0, 1)
    artG = clamp(g, 0, 1)
    artB = clamp(b, 0, 1)
    saveCfg()
    if enabled then applySkin() end
    if IchaUI_MinimapTintSwatch and IchaUI_MinimapTintSwatch.SetVertexColor then
        IchaUI_MinimapTintSwatch:SetVertexColor(artR, artG, artB, 1)
    end
    applyPickerTint()
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("ZONE_CHANGED")
boot:RegisterEvent("ZONE_CHANGED_INDOORS")
boot:RegisterEvent("ZONE_CHANGED_NEW_AREA")
boot:RegisterEvent("MINIMAP_UPDATE_ZOOM")
boot:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        loadCfg()
        if enabled then
            applySkin()
        end
    else
        if enabled and zoneShow then
            refreshZoneText()
        end
    end
end)

function IchaUIMinimap_Reload()
    loadCfg()
    if enabled then
        applySkin()
    else
        unskin()
    end
end

-- Lightweight clock tick
local clockTick = CreateFrame("Frame")
local clockAccum = 0
clockTick:SetScript("OnUpdate", function()
    if not enabled or not clockShow then return end
    clockAccum = clockAccum + (arg1 or 0)
    if clockAccum < 1 then return end
    clockAccum = 0
    refreshClockText()
end)
