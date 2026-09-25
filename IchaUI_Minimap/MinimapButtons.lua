-- IchaUI minimap button drawer (1.12 / RavenCraft, Lua 5.0)
-- Replaces TurtleSnacks + MinimapButtonBag collection with a gold-chrome
-- drawer under the minimap. Options: /iui → Drawers.

local GOLD = { 0.78, 0.58, 0.16, 1 }
local ARROW_DOWN_UP = "Interface\\AddOns\\IchaUI\\media\\Arrow-PointDown-Up.tga"
local ARROW_DOWN_DOWN = "Interface\\AddOns\\IchaUI\\media\\Arrow-PointDown-Down.tga"
local ARROW_UP_UP = "Interface\\AddOns\\IchaUI\\media\\Arrow-PointUp-Up.tga"
local ARROW_UP_DOWN = "Interface\\AddOns\\IchaUI\\media\\Arrow-PointUp-Down.tga"
local drawerDir = "down"
local drawerSpread = 90
local drawerArc = 360
local drawerRot = 90
-- Pre-rotated TGAs (1.12 SetTexCoord is 4-arg only — cannot rotate in-client)
local function setHandleArrow(tex, open, pressed)
    if not tex then return end
    local dir = drawerDir
    if dir ~= "up" and dir ~= "left" and dir ~= "right" and dir ~= "radial" then dir = "down" end
    -- PointDown/PointUp art files are labeled opposite of their glyph.
    -- closed → point in the open direction; open → point opposite (close).
    if dir == "down" then
        if open then
            tex:SetTexture(pressed and ARROW_DOWN_DOWN or ARROW_DOWN_UP)
        else
            tex:SetTexture(pressed and ARROW_UP_DOWN or ARROW_UP_UP)
        end
        tex:SetTexCoord(0, 1, 0, 1)
    elseif dir == "up" then
        if open then
            tex:SetTexture(pressed and ARROW_UP_DOWN or ARROW_UP_UP)
        else
            tex:SetTexture(pressed and ARROW_DOWN_DOWN or ARROW_DOWN_UP)
        end
        tex:SetTexCoord(0, 1, 0, 1)
    elseif dir == "radial" then
        tex:SetTexture(pressed and ARROW_UP_DOWN or ARROW_UP_UP)
        tex:SetTexCoord(0, 1, 0, 1)
    else
        local leftUp = "Interface\\AddOns\\IchaUI\\media\\Arrow-Left-Up.tga"
        local leftDn = "Interface\\AddOns\\IchaUI\\media\\Arrow-Left-Down.tga"
        tex:SetTexture(pressed and leftDn or leftUp)
        -- closed left / open right: native left arrow; closed right / open left: flip
        local faceLeft = (dir == "left" and not open) or (dir == "right" and open)
        if faceLeft then
            tex:SetTexCoord(0, 1, 0, 1)
        else
            tex:SetTexCoord(1, 0, 0, 1)
        end
    end
    local parent = tex:GetParent()
    if parent then
        tex:ClearAllPoints()
        local ox, oy = 0, 0
        if dir == "down" then
            oy = open and 0 or -1
        end
        tex:SetPoint("CENTER", parent, "CENTER", ox, oy)
    end
    local aw = 20
    if IchaUI_DrawerButtonScale then
        aw = math.floor(20 * IchaUI_DrawerButtonScale("minimap") + 0.5)
    end
    if aw < 8 then aw = 8 end
    tex:SetWidth(aw)
    tex:SetHeight(aw)
    tex:SetVertexColor(1, 1, 1, 1)
    tex:Show()
end

local GOLD_RING = "Interface/Minimap/MiniMap-TrackingBorder"
local CIRCLE_BG = "Interface/Minimap/UI-Minimap-Background"
local BTN_SIZE = 28
local COLS = 5
local PAD = 4
local HANDLE_H = 18

local function btnPx()
    local s = 1
    if IchaUI_DrawerPopScale then s = IchaUI_DrawerPopScale("minimap") end
    local n = math.floor(BTN_SIZE * s + 0.5)
    if n < 8 then n = 8 end
    return n
end

-- Never collect these (pins / chrome / our own frames)
local IGNORE = {
    MiniMapPing = true,
    MinimapBackdrop = true,
    MinimapBorder = true,
    MinimapBorderTop = true,
    MinimapZoneTextButton = true,
    MinimapZoneText = true,
    MinimapToggleButton = true,
    BookOfTracksFrame = true,
    GatherNote = true,
    FishingExtravaganzaMini = true,
    MiniNotePOI = true,
    RecipeRadarMinimapIcon = true,
    FWGMinimapPOI = true,
    QuestieNote = true,
    MetaMap = true,
    pfMiniMapPin = true,
    TimeManagerClockButton = true,
    GameTimeFrame = true,
    MBB_MinimapButtonFrame = true,
    IchaUIMinimapChrome = true,
    IchaUIMinimapZone = true,
    IchaUIMinimapClock = true,
    IchaUIMinimapMover = true,
    IchaUIMinimapZoneMover = true,
    IchaUIMinimapClockMover = true,
    IchaUIMinimapDrawer = true,
    IchaUIMinimapDrawerHandle = true,
    IchaUIMinimapDrawerPanel = true,
}

-- Stock Blizzard / Turtle frames: optional (default not in drawer)
-- Never resize these; never blank their icon art when cleaning borders.
local STOCK = {
    MinimapZoomIn = true,
    MinimapZoomOut = true,
    MiniMapMailFrame = true,
    MiniMapTrackingFrame = true,
    MiniMapBattlefieldFrame = true,
    MiniMapMeetingStoneFrame = true,
}

-- Always try to collect these Turtle / common addon frames
local FORCE = {
    "MinimapShopFrame",
    "TWMinimapShopFrame",
    "TWMiniMapBattlefieldFrame",
    "LFT_Minimap",
    "DPSMate_MiniMap",
}

local IGNORE_SIZE = {
    AM_MinimapButton = true,
    STC_HealthstoneButton = true,
    STC_ShardButton = true,
    STC_SoulstoneButton = true,
    STC_SpellstoneButton = true,
    STC_FirestoneButton = true,
    TurtleCount = true,
}

local managed = {}   -- [name] = { frame=, chrome=, origParent=, origPoint=, prepared= }
local drawerOpen = false
local drawerEnabled = true
local iconMoveOn = false
local conflictWarned = false
local bootDone = false

local handle, panel, grid
local updateDrawerVisibility  -- forward decl
local layoutDrawerGrid        -- forward decl

----------------------------------------------------------------------
-- SavedVariables
----------------------------------------------------------------------
local function db()
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.minimapButtons then
        IchaUIDB.minimapButtons = {
            drawerOpen = false,
            enabled = true,
            buttons = {},
        }
    end
    if not IchaUIDB.minimapButtons.buttons then
        IchaUIDB.minimapButtons.buttons = {}
    end
    return IchaUIDB.minimapButtons
end

local function btnCfg(name)
    local d = db()
    if not d.buttons[name] then
        local stock = STOCK[name] and true or false
        d.buttons[name] = {
            inDrawer = not stock,
            freeMove = false,
        }
    end
    return d.buttons[name]
end

local function loadCfg()
    local d = db()
    if d.enabled ~= nil then drawerEnabled = d.enabled and true or false end
    if d.drawerOpen ~= nil then drawerOpen = d.drawerOpen and true or false end
    if d.drawerDir == "up" or d.drawerDir == "left" or d.drawerDir == "right" or d.drawerDir == "radial" then
        drawerDir = d.drawerDir
    else
        drawerDir = "down"
    end
    if IchaUI_DrawerNormSpread then
        drawerSpread = IchaUI_DrawerNormSpread(d.drawerSpread)
    else
        drawerSpread = tonumber(d.drawerSpread) or 90
        if drawerSpread < 10 then drawerSpread = 10 end
        if drawerSpread > 360 then drawerSpread = 360 end
        drawerSpread = math.floor(drawerSpread + 0.5)
    end
    if IchaUI_DrawerNormArc then
        drawerArc = IchaUI_DrawerNormArc(d.drawerArc)
    else
        drawerArc = tonumber(d.drawerArc) or 360
        if drawerArc < 10 then drawerArc = 10 end
        if drawerArc > 360 then drawerArc = 360 end
        drawerArc = math.floor(drawerArc + 0.5)
    end
    if IchaUI_DrawerNormRot then
        drawerRot = IchaUI_DrawerNormRot(d.drawerRot)
    else
        if d.drawerRot == nil then
            drawerRot = 90
        else
            drawerRot = tonumber(d.drawerRot) or 90
            if drawerRot < -360 then drawerRot = -360 end
            if drawerRot > 360 then drawerRot = 360 end
            drawerRot = math.floor(drawerRot + 0.5)
        end
    end
end

local function saveCfg()
    local d = db()
    d.enabled = drawerEnabled
    d.drawerOpen = drawerOpen
    if drawerDir ~= "up" and drawerDir ~= "left" and drawerDir ~= "right" and drawerDir ~= "radial" then
        drawerDir = "down"
    end
    d.drawerDir = drawerDir
    d.drawerSpread = drawerSpread
    d.drawerArc = drawerArc
    d.drawerRot = drawerRot
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function isIgnored(name)
    if not name then return true end
    if IGNORE[name] then return true end
    -- Prefix / substring ignores for POI-style children
    local needles = {
        "GatherNote", "MiniNotePOI", "QuestieNote", "MetaMap",
        "FWGMinimapPOI", "RecipeRadarMinimapIcon", "pfMiniMapPin",
        "IchaUIMinimap", "MBB_MinimapButton", "BookOfTracks",
        "FishingExtravaganza",
    }
    local i
    for i = 1, table.getn(needles) do
        if string.find(name, needles[i], 1, true) then
            return true
        end
    end
    return false
end

local function prettyLabel(name)
    if not name then return "?" end
    local map = {
        MinimapZoomIn = "Zoom In",
        MinimapZoomOut = "Zoom Out",
        MiniMapMailFrame = "Mail",
        MiniMapTrackingFrame = "Tracking",
        MiniMapBattlefieldFrame = "Battlefield",
        MiniMapMeetingStoneFrame = "Meeting Stone",
        MinimapShopFrame = "TW Shop",
        TWMinimapShopFrame = "TW Shop",
        TWMiniMapBattlefieldFrame = "TW BG Finder",
        LFT_Minimap = "Looking For Turtles",
        DPSMate_MiniMap = "DPSMate",
    }
    if map[name] then return map[name] end
    local s = string.gsub(name, "Frame$", "")
    s = string.gsub(s, "Button$", "")
    s = string.gsub(s, "Minimap", "")
    s = string.gsub(s, "MiniMap", "")
    s = string.gsub(s, "^_+", "")
    if s == "" then return name end
    return s
end

local function hasClickish(frame)
    if not frame then return false end
    local ok, result
    if frame.HasScript then
        ok, result = pcall(function()
            if frame:HasScript("OnClick") and frame:GetScript("OnClick") then return true end
            if frame:HasScript("OnMouseUp") and frame:GetScript("OnMouseUp") then return true end
            if frame:HasScript("OnMouseDown") and frame:GetScript("OnMouseDown") then return true end
            return false
        end)
        if ok and result then return true end
    end
    -- Buttons without HasScript still often respond to clicks
    if frame.GetObjectType then
        local t = frame:GetObjectType()
        if t == "Button" then return true end
    end
    return false
end

local function findClickChild(frame)
    if hasClickish(frame) then return frame end
    if not frame.GetChildren then return frame end
    local kids = { frame:GetChildren() }
    local i
    for i = 1, table.getn(kids) do
        local c = kids[i]
        if c and c.GetName and c:GetName() and hasClickish(c) then
            return c
        end
    end
    return frame
end

-- True if a texture is (or looks like) a minimap button ring — by name OR path.
-- Prefer skipping our chrome when unsure; stacking rings looks worse than no tint.
local function texPathIsBorder(path)
    if not path or path == "" then return false end
    local p = string.lower(tostring(path))
    if string.find(p, "trackingborder", 1, true) then return true end
    if string.find(p, "minimap-tracking", 1, true) then return true end
    if string.find(p, "ui-minimap-border", 1, true) then return true end
    if string.find(p, "minimapborder", 1, true) then return true end
    if string.find(p, "buttonborder", 1, true) then return true end
    if string.find(p, "iconborder", 1, true) then return true end
    -- Generic *border* art that is not an icon glyph
    if string.find(p, "border", 1, true) and not string.find(p, "icon", 1, true) then
        return true
    end
    return false
end

local function regionLooksLikeBorder(tex)
    if not tex or not tex.GetObjectType then return false end
    if tex:GetObjectType() ~= "Texture" then return false end
    local n = tex.GetName and tex:GetName()
    if n then
        -- Icon art (MiniMapTrackingIcon / MiniMapMailIcon): not a border.
        if string.find(n, "Icon", 1, true) and not string.find(n, "Border", 1, true) then
            -- still allow path check below
        else
            if string.find(n, "TrackingBorder", 1, true) then return true end
            if string.find(n, "Border", 1, true) then return true end
            if string.find(n, "Backdrop", 1, true) then return true end
            if string.find(n, "Overlay", 1, true) and string.find(n, "Border", 1, true) then return true end
        end
    end
    if tex.GetTexture then
        local ok, path = pcall(function() return tex:GetTexture() end)
        if ok and texPathIsBorder(path) then return true end
    end
    return false
end

local function frameHasBackdropEdge(frame)
    if not frame or not frame.GetBackdrop then return false end
    local ok, bd = pcall(function() return frame:GetBackdrop() end)
    if not ok or not bd then return false end
    if type(bd) == "table" and bd.edgeFile and tostring(bd.edgeFile) ~= "" then
        return true
    end
    return false
end

local function scanFrameForBorder(frame)
    if not frame then return false end
    if frameHasBackdropEdge(frame) then return true end
    local base = frame.GetName and frame:GetName()
    if base then
        local suffixes = {
            "TrackingBorder", "Border", "IconBorder", "BorderTexture",
            "BorderTop", "BorderLeft", "BorderRight", "BorderBottom",
            "Backdrop", "Overlay", "Ring",
        }
        local i
        for i = 1, table.getn(suffixes) do
            local t = getglobal(base .. suffixes[i])
            if t and regionLooksLikeBorder(t) then return true end
            if t and t.GetObjectType and t:GetObjectType() == "Texture" then
                if regionLooksLikeBorder(t) then return true end
            end
            if t and frameHasBackdropEdge(t) then return true end
        end
        local extras = {
            getglobal("MiniMapMailBorder"),
            getglobal("MiniMapTrackingBorder"),
            getglobal("MiniMapTrackingFrame"),
        }
        for i = 1, table.getn(extras) do
            local t = extras[i]
            if t and t.GetParent and t:GetParent() == frame then return true end
        end
    end
    if frame.GetRegions then
        local regs = { frame:GetRegions() }
        local i
        for i = 1, table.getn(regs) do
            if regionLooksLikeBorder(regs[i]) then return true end
        end
    end
    if frame.GetChildren then
        local kids = { frame:GetChildren() }
        local i
        for i = 1, table.getn(kids) do
            local c = kids[i]
            if c and frameHasBackdropEdge(c) then return true end
            if c and c.GetRegions then
                local regs = { c:GetRegions() }
                local j
                for j = 1, table.getn(regs) do
                    if regionLooksLikeBorder(regs[j]) then return true end
                end
            end
            if c and regionLooksLikeBorder(c) then return true end
        end
    end
    return false
end

local function hasNativeBorder(frame)
    if not frame then return false end
    if scanFrameForBorder(frame) then return true end
    -- Border often lives on parent / click-child while we track the other
    if frame.GetParent then
        local p = frame:GetParent()
        if p and p ~= Minimap and p ~= MinimapBackdrop and p ~= UIParent then
            if scanFrameForBorder(p) then return true end
        end
    end
    return false
end

-- Gold-tint an existing border instead of stacking a second ring
local function tintNativeBorders(frame)
    if not frame then return end
    local function tint(tex)
        if not regionLooksLikeBorder(tex) then return end
        if tex.SetVertexColor then
            pcall(function() IchaUI_PaintGoldRing(tex) end)
        end
    end
    if frame.GetRegions then
        local regs = { frame:GetRegions() }
        local i
        for i = 1, table.getn(regs) do tint(regs[i]) end
    end
    local base = frame.GetName and frame:GetName()
    if base then
        local suffixes = { "TrackingBorder", "Border", "IconBorder" }
        local i
        for i = 1, table.getn(suffixes) do
            local t = getglobal(base .. suffixes[i])
            if t then tint(t) end
        end
    end
    if frame.GetChildren then
        local kids = { frame:GetChildren() }
        local i
        for i = 1, table.getn(kids) do
            local c = kids[i]
            if c and c.GetRegions then
                local regs = { c:GetRegions() }
                local j
                for j = 1, table.getn(regs) do tint(regs[j]) end
            end
        end
    end
end

----------------------------------------------------------------------
-- Gold chrome (dark plate + TrackingBorder tint)
----------------------------------------------------------------------
-- Only hide true border textures. Never touch Icon / letter / tracking art.
local function hideUglyBorders(frame)
    if not frame then return end
    -- Stock frames keep their own chrome; do not blank mail letter / tracking icon
    local fname = frame.GetName and frame:GetName()
    if fname and STOCK[fname] then return end
    if hasNativeBorder(frame) then return end

    if fname then
        local suffixes = {
            "Border", "TrackingBorder", "Background", "IconOverlay",
            "BorderTop", "BorderLeft", "BorderRight", "BorderBottom",
            "IconBackdrop",
        }
        local i
        for i = 1, table.getn(suffixes) do
            local t = getglobal(fname .. suffixes[i])
            if t and t.GetObjectType and t:GetObjectType() == "Texture" then
                local n = t.GetName and t:GetName()
                if n and not string.find(n, "Icon", 1, true) then
                    if t.Hide then pcall(function() t:Hide() end) end
                    if t.SetAlpha then pcall(function() t:SetAlpha(0) end) end
                end
            end
        end
    end
    if frame.GetRegions then
        local regs = { frame:GetRegions() }
        local i
        for i = 1, table.getn(regs) do
            local r = regs[i]
            if regionLooksLikeBorder(r) then
                pcall(function()
                    r:SetAlpha(0)
                    r:Hide()
                end)
            end
        end
    end
end

local function destroyChrome(entry)
    if not entry or not entry.chrome then return end
    pcall(function() entry.chrome:Hide() end)
    pcall(function() entry.chrome:SetParent(nil) end)
    entry.chrome = nil
end

local function ensureChrome(entry)
    local frame = entry.frame
    if not frame then return nil end

    -- Already has a ring / backdrop: tint it gold, never stack plate+ring
    if hasNativeBorder(frame) then
        destroyChrome(entry)
        tintNativeBorders(frame)
        entry._nativeChrome = true
        return nil
    end

    if entry.chrome then return entry.chrome end

    local c = CreateFrame("Frame", nil, frame)
    c:SetAllPoints(frame)
    c:EnableMouse(false)
    c:SetFrameLevel((frame:GetFrameLevel() or 1) + 5)

    local plate = c:CreateTexture(nil, "BACKGROUND")
    plate:SetTexture(CIRCLE_BG)
    plate:SetVertexColor(0, 0, 0, 0.92)
    plate:SetWidth(BTN_SIZE)
    plate:SetHeight(BTN_SIZE)
    plate:SetPoint("CENTER", c, "CENTER", 0, 0)
    c.plate = plate

    local ring = c:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(GOLD_RING)
    ring:SetTexCoord(0, 0.6, 0, 0.6)
    IchaUI_PaintGoldRing(ring)
    local bw = math.floor(BTN_SIZE * 1.65 + 0.5)
    ring:SetWidth(bw)
    ring:SetHeight(bw)
    ring:SetPoint("CENTER", c, "CENTER", 0, 0)
    c.ring = ring

    entry.chrome = c
    hideUglyBorders(frame)
    return c
end

local function showChrome(entry, show)
    if not entry then return end
    if entry.frame and hasNativeBorder(entry.frame) then
        destroyChrome(entry)
        if show then tintNativeBorders(entry.frame) end
        return
    end
    local c = ensureChrome(entry)
    if not c then return end
    if show then c:Show() else c:Hide() end
end

----------------------------------------------------------------------
-- Drag lock / unlock
----------------------------------------------------------------------
local function clearDrag(f)
    if not f then return end
    if f.SetMovable then pcall(function() f:SetMovable(false) end) end
    if f.RegisterForDrag then pcall(function() f:RegisterForDrag() end) end
    if f.SetScript then
        pcall(function() f:SetScript("OnDragStart", nil) end)
        pcall(function() f:SetScript("OnDragStop", nil) end)
    end
    -- Keep EnableMouse so the button's own OnClick still works when locked
end

local function enableFreeDrag(f)
    if not f then return end
    if f.SetMovable then f:SetMovable(true) end
    if f.EnableMouse then f:EnableMouse(true) end
    if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
    f:SetScript("OnDragStart", function()
        if not iconMoveOn then return end
        if this.SetParent then
            pcall(function() this:SetParent(UIParent) end)
        end
        if this.SetFrameStrata then
            pcall(function() this:SetFrameStrata("MEDIUM") end)
        end
        this:StartMoving()
    end)
    f:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local n = this:GetName()
        if not n then return end
        local c = btnCfg(n)
        local p, _, rp, x, y = this:GetPoint()
        c.point = p or "CENTER"
        c.rel = rp or "CENTER"
        c.relTo = "UIParent"
        c.x = tonumber(x) or 0
        c.y = tonumber(y) or 0
        c.freeMove = true
        c.inDrawer = false
    end)
end

----------------------------------------------------------------------
-- Capture / restore original layout
----------------------------------------------------------------------
local function captureOrig(entry)
    local f = entry.frame
    -- Only once, before first steal into drawer / free (never after already reparented)
    if not f or entry.origCaptured then return end
    entry.origParent = f:GetParent()
    entry.origWidth = f:GetWidth()
    entry.origHeight = f:GetHeight()
    entry.origScale = f:GetScale()
    local p, rel, rp, x, y = f:GetPoint()
    if p then
        entry.origPoint = { p, rel, rp, x, y }
    else
        entry.origPoint = { "CENTER", Minimap, "CENTER", 0, 0 }
    end
    entry.wasShown = f:IsShown() and true or false
    entry.origCaptured = true
end

local function rawShow(f)
    if f._ichaShow then
        f._ichaShow(f)
    elseif f.Show then
        f:Show()
    end
end

local function rawHide(f)
    if f._ichaHide then
        f._ichaHide(f)
    elseif f.Hide then
        f:Hide()
    end
end

local function prepareFrame(frame)
    if not frame or frame._ichaPrepared then return end
    frame._ichaShow = frame.Show
    frame._ichaHide = frame.Hide
    -- Soft-hook Show/Hide so addons that re-show icons don't yank them out of the drawer
    frame.Show = function(self)
        self._ichaWantVisible = true
        local name = self:GetName()
        local cfg = name and btnCfg(name)
        if cfg and cfg.inDrawer and drawerEnabled then
            if drawerOpen then
                self._ichaShow(self)
            end
            -- closed drawer: stay hidden
            return
        end
        self._ichaShow(self)
    end
    frame.Hide = function(self)
        self._ichaWantVisible = false
        self._ichaHide(self)
    end
    frame._ichaPrepared = true
    frame._ichaWantVisible = frame:IsShown() and true or false
end

----------------------------------------------------------------------
-- Layout: drawer grid / free / stock home
----------------------------------------------------------------------
layoutDrawerGrid = function()
    if not grid then return end
    local px = btnPx()
    local list = {}
    local name, entry
    for name, entry in pairs(managed) do
        local cfg = btnCfg(name)
        if cfg.inDrawer and entry.frame then
            table.insert(list, name)
        end
    end
    table.sort(list)

    local n = table.getn(list)
    local dir = drawerDir
    if dir ~= "up" and dir ~= "left" and dir ~= "right" and dir ~= "radial" then dir = "down" end
    local cols, rows
    if dir == "radial" then
        cols = 1
        rows = 1
        if n > 0 then rows = n end
    elseif dir == "left" or dir == "right" then
        rows = 2
        if n < 1 then
            cols = 1
        else
            cols = math.floor((n - 1) / rows) + 1
        end
    else
        cols = COLS
        rows = 1
        if n > 0 then
            rows = math.floor((n - 1) / cols) + 1
        end
    end
    local pw = cols * (px + PAD) + PAD
    local ph = rows * (px + PAD) + PAD
    if dir == "radial" then
        pw = 2
        ph = 2
    else
        if ph < px + PAD * 2 then ph = px + PAD * 2 end
        if pw < px + PAD * 2 then pw = px + PAD * 2 end
    end
    panel:SetWidth(pw)
    panel:SetHeight(ph)
    grid:SetWidth(pw)
    grid:SetHeight(ph)

    local i
    for i = 1, n do
        name = list[i]
        entry = managed[name]
        local f = entry.frame
        if f then
            -- Capture home only once, before first steal
            captureOrig(entry)
            prepareFrame(f)
            showChrome(entry, true)
            -- Do not resize stock frames (mail / tracking / zoom / …)
            if not IGNORE_SIZE[name] and not STOCK[name] then
                f:SetWidth(px)
                f:SetHeight(px)
                if entry.chrome then
                    if entry.chrome.plate then
                        entry.chrome.plate:SetWidth(px)
                        entry.chrome.plate:SetHeight(px)
                    end
                    if entry.chrome.ring then
                        local bw = math.floor(px * 1.65 + 0.5)
                        entry.chrome.ring:SetWidth(bw)
                        entry.chrome.ring:SetHeight(bw)
                    end
                end
            end
            f:SetParent(grid)
            f:ClearAllPoints()
            if dir == "radial" and IchaUI_DrawerRadialRadius and IchaUI_DrawerRadialXY and handle then
                local hb = handle:GetWidth() or 24
                local hh = handle:GetHeight() or hb
                if hh > hb then hb = hh end
                local radius = IchaUI_DrawerRadialRadius(n, hb, px, PAD, drawerSpread)
                local rx, ry = IchaUI_DrawerRadialXY(i, n, radius, drawerArc, drawerRot)
                f:SetPoint("CENTER", handle, "CENTER", rx, ry)
            else
            local col, row
            if dir == "left" or dir == "right" then
                row = math.mod(i - 1, rows)
                col = math.floor((i - 1) / rows)
            else
                col = math.mod(i - 1, cols)
                row = math.floor((i - 1) / cols)
            end
            local x = PAD + col * (px + PAD)
            local y = PAD + row * (px + PAD)
            if dir == "up" then
                f:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", x, y)
            elseif dir == "left" then
                f:SetPoint("TOPRIGHT", grid, "TOPRIGHT", -x, -y)
            else
                -- down (default) and right: grow away from the handle
                f:SetPoint("TOPLEFT", grid, "TOPLEFT", x, -y)
            end
            end
            f:SetFrameLevel((grid:GetFrameLevel() or 1) + 2 + i)
            -- Drawer: drag only while shared icon Move/Lock is unlocked
            if iconMoveOn then
                enableFreeDrag(f)
            else
                clearDrag(f)
            end
            if drawerOpen then
                rawShow(f)
            else
                rawHide(f)
            end
        end
    end
end

-- Place at saved / default free coords. allowDrag only while shared icon Move is unlocked.
-- Never call StartMoving from Options — user drags via OnDragStart only.
local function savedPosLooksSane(cfg)
    if not cfg or cfg.x == nil then return false end
    local x = tonumber(cfg.x) or 0
    local y = tonumber(cfg.y) or 0
    -- Off-screen / stuck-to-cursor disasters
    if x > 2500 or x < -2500 or y > 2500 or y < -2500 then return false end
    return true
end

local function clearSavedPos(cfg)
    if not cfg then return end
    cfg.point = nil
    cfg.rel = nil
    cfg.relTo = nil
    cfg.x = nil
    cfg.y = nil
end

local function placeFree(name, entry, allowDrag)
    local f = entry.frame
    if not f then return end
    local cfg = btnCfg(name)
    captureOrig(entry)
    prepareFrame(f)
    showChrome(entry, true)
    f:SetParent(UIParent)
    f:ClearAllPoints()
    if cfg.point and cfg.x ~= nil and savedPosLooksSane(cfg) then
        local rel = UIParent
        if cfg.relTo == "Minimap" and Minimap then rel = Minimap end
        f:SetPoint(cfg.point, rel, cfg.rel or cfg.point, cfg.x or 0, cfg.y or 0)
    else
        if not savedPosLooksSane(cfg) then clearSavedPos(cfg) end
        -- Defaults: mail/tracking hug the minimap; others sit under it
        if name == "MiniMapMailFrame" and Minimap then
            f:SetParent(Minimap)
            f:ClearAllPoints()
            f:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 21, -1)
        elseif name == "MiniMapTrackingFrame" and Minimap then
            f:SetParent(Minimap)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -6, -1)
        else
            f:SetPoint("TOP", Minimap or UIParent, "BOTTOM", 0, -28)
        end
    end
    f:SetFrameStrata("MEDIUM")
    rawShow(f)

    if allowDrag then
        enableFreeDrag(f)
    else
        -- Locked: keep visible at saved coords, clicks go to the button
        clearDrag(f)
    end
end

local function restoreHome(name, entry)
    local f = entry.frame
    if not f then return end
    captureOrig(entry)
    showChrome(entry, true)
    clearDrag(f)
    local parent = entry.origParent or Minimap or UIParent
    f:SetParent(parent)
    f:ClearAllPoints()
    local op = entry.origPoint
    if op then
        local rel = op[2] or parent
        f:SetPoint(op[1] or "CENTER", rel, op[3] or op[1] or "CENTER", op[4] or 0, op[5] or 0)
    else
        f:SetPoint("CENTER", Minimap or UIParent, "CENTER", 0, 0)
    end
    if entry.origWidth then f:SetWidth(entry.origWidth) end
    if entry.origHeight then f:SetHeight(entry.origHeight) end
    if entry.wasShown then rawShow(f) else rawHide(f) end
end

local function applyOne(name)
    local entry = managed[name]
    if not entry or not entry.frame then return end
    if not drawerEnabled then
        restoreHome(name, entry)
        showChrome(entry, false)
        return
    end
    local cfg = btnCfg(name)
    if cfg.inDrawer then
        -- grid layout done in batch via layoutDrawerGrid
        return
    elseif cfg.freeMove then
        placeFree(name, entry, iconMoveOn)
    elseif cfg.point and cfg.x ~= nil then
        -- Stays at last free coords; drag only while unlocked
        placeFree(name, entry, iconMoveOn)
    else
        restoreHome(name, entry)
        if iconMoveOn then
            enableFreeDrag(entry.frame)
        else
            clearDrag(entry.frame)
        end
    end
end

local function applyAll()
    if not iconMoveOn then
        local name, entry
        for name, entry in pairs(managed) do
            if entry and entry.frame and entry.frame.StopMovingOrSizing then
                pcall(function() entry.frame:StopMovingOrSizing() end)
            end
        end
    end
    if not drawerEnabled then
        local name, entry
        for name, entry in pairs(managed) do
            restoreHome(name, entry)
            showChrome(entry, false)
        end
        if panel then panel:Hide() end
        if handle then handle:Hide() end
        return
    end
    layoutDrawerGrid()
    local name, entry
    for name, entry in pairs(managed) do
        local cfg = btnCfg(name)
        if not cfg.inDrawer then
            applyOne(name)
        end
    end
    updateDrawerVisibility()
end

----------------------------------------------------------------------
-- Drawer chrome UI
----------------------------------------------------------------------
updateDrawerVisibility = function()
    if not handle or not panel then return end
    if not drawerEnabled then
        handle:Hide()
        panel:Hide()
        return
    end
    handle:Show()
    local dir = drawerDir
    if dir ~= "up" and dir ~= "left" and dir ~= "right" and dir ~= "radial" then dir = "down" end
    local hs = 1
    if IchaUI_DrawerButtonScale then hs = IchaUI_DrawerButtonScale("minimap") end
    local thin = math.floor(HANDLE_H * hs + 0.5)
    local wide = math.floor(24 * hs + 0.5)
    if thin < 8 then thin = 8 end
    if wide < 10 then wide = 10 end
    if dir == "left" or dir == "right" then
        handle:SetWidth(thin)
        handle:SetHeight(wide)
    else
        handle:SetWidth(wide)
        handle:SetHeight(thin)
    end
    handle:ClearAllPoints()
    if dir == "down" then
        -- Sit under the clock when present; otherwise under the minimap
        local clock = getglobal("IchaUIMinimapClock")
        if clock and clock.IsShown and clock:IsShown() then
            handle:SetPoint("TOP", clock, "BOTTOM", 0, -2)
        elseif Minimap then
            handle:SetPoint("TOP", Minimap, "BOTTOM", 0, -4)
        else
            handle:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    elseif dir == "up" then
        local zone = getglobal("IchaUIMinimapZone")
        if zone and zone.IsShown and zone:IsShown() then
            handle:SetPoint("BOTTOM", zone, "TOP", 0, 2)
        elseif Minimap then
            handle:SetPoint("BOTTOM", Minimap, "TOP", 0, 4)
        else
            handle:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    elseif dir == "left" then
        if Minimap then
            handle:SetPoint("RIGHT", Minimap, "LEFT", -4, 0)
        else
            handle:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    elseif dir == "radial" or dir == "down" then
        local clock = getglobal("IchaUIMinimapClock")
        if dir == "radial" then clock = nil end
        if dir ~= "radial" and clock and clock.IsShown and clock:IsShown() then
            handle:SetPoint("TOP", clock, "BOTTOM", 0, -2)
        elseif Minimap then
            handle:SetPoint("TOP", Minimap, "BOTTOM", 0, -4)
        else
            handle:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    else
        if Minimap then
            handle:SetPoint("LEFT", Minimap, "RIGHT", 4, 0)
        else
            handle:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end
    if drawerOpen then
        panel:Show()
        panel:ClearAllPoints()
        if dir == "radial" then
            panel:SetPoint("CENTER", handle, "CENTER", 0, 0)
        elseif dir == "down" then
            panel:SetPoint("TOP", handle, "BOTTOM", 0, 0)
        elseif dir == "up" then
            panel:SetPoint("BOTTOM", handle, "TOP", 0, 0)
        elseif dir == "left" then
            panel:SetPoint("RIGHT", handle, "LEFT", 0, 0)
        else
            panel:SetPoint("LEFT", handle, "RIGHT", 0, 0)
        end
    else
        panel:Hide()
    end
    if handle.arrowTex then
        setHandleArrow(handle.arrowTex, drawerOpen, false)
    end
    -- Re-show/hide drawer-resident buttons
    local name, entry
    for name, entry in pairs(managed) do
        local cfg = btnCfg(name)
        if cfg.inDrawer and entry.frame then
            if drawerOpen then
                rawShow(entry.frame)
            else
                rawHide(entry.frame)
            end
        end
    end
end

local function toggleDrawer()
    drawerOpen = not drawerOpen
    saveCfg()
    layoutDrawerGrid()
    updateDrawerVisibility()
end

local function ensureDrawer()
    if handle then return end

    handle = CreateFrame("Button", "IchaUIMinimapDrawerHandle", UIParent)
    local px0 = btnPx()
    local hs0 = 1
    if IchaUI_DrawerButtonScale then hs0 = IchaUI_DrawerButtonScale("minimap") end
    handle:SetWidth(math.floor(24 * hs0 + 0.5))
    handle:SetHeight(math.floor(HANDLE_H * hs0 + 0.5))
    handle:SetFrameStrata("MEDIUM")
    handle:SetFrameLevel(40)
    handle:EnableMouse(true)
    handle:RegisterForClicks("LeftButtonUp")
    -- No border / background — arrow only
    if handle.SetBackdrop then handle:SetBackdrop(nil) end

    local arrowTex = handle:CreateTexture(nil, "ARTWORK")
    arrowTex:SetWidth(20)
    arrowTex:SetHeight(20)
    arrowTex:SetPoint("CENTER", handle, "CENTER", 0, 0)
    handle.arrowTex = arrowTex
    setHandleArrow(arrowTex, false, false)

    handle:SetScript("OnMouseDown", function()
        if this.arrowTex then setHandleArrow(this.arrowTex, drawerOpen, true) end
    end)
    handle:SetScript("OnMouseUp", function()
        if this.arrowTex then setHandleArrow(this.arrowTex, drawerOpen, false) end
        if arg1 == "RightButton" and IchaUI_DrawerEditClick then IchaUI_DrawerEditClick("minimap") end
    end)
    handle:SetScript("OnClick", function()
        toggleDrawer()
        if this.arrowTex then setHandleArrow(this.arrowTex, drawerOpen, false) end
    end)
    handle:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Minimap buttons", 1, 1, 1)
        GameTooltip:AddLine("Click to open/close", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    handle:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if this.arrowTex then setHandleArrow(this.arrowTex, drawerOpen, false) end
    end)

    panel = CreateFrame("Frame", "IchaUIMinimapDrawerPanel", UIParent)
    panel:SetWidth(COLS * (px0 + PAD) + PAD)
    panel:SetHeight(px0 + PAD * 2)
    panel:SetFrameStrata("MEDIUM")
    if IchaUI_DrawerStyleGet then
        local savedStrata = IchaUI_DrawerStyleGet("minimap")
        if savedStrata and savedStrata ~= "" then
            pcall(function() panel:SetFrameStrata(savedStrata) end)
            pcall(function() handle:SetFrameStrata(savedStrata) end)
        end
    end
    panel:SetFrameLevel(35)
    panel:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 12, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0.04, 0.04, 0.05, 0.94)
    IchaUI_PaintGoldBorder(panel, 1)
    panel:EnableMouse(true)
    panel:Hide()

    grid = CreateFrame("Frame", "IchaUIMinimapDrawer", panel)
    grid:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    grid:SetWidth(panel:GetWidth())
    grid:SetHeight(panel:GetHeight())
    grid:EnableMouse(false)
end

----------------------------------------------------------------------
-- Collection / scan
----------------------------------------------------------------------
local function registerButton(frame)
    if not frame or not frame.GetName then return end
    local name = frame:GetName()
    if not name or isIgnored(name) then return end
    if managed[name] then
        managed[name].frame = frame
        return
    end
    frame = findClickChild(frame)
    name = frame:GetName()
    if not name or isIgnored(name) then return end
    if managed[name] then
        managed[name].frame = frame
        return
    end
    -- Stock frames are registered even without click scripts
    if not STOCK[name] and not hasClickish(frame) then
        return
    end
    managed[name] = { frame = frame }
    btnCfg(name) -- ensure defaults
    captureOrig(managed[name])
    prepareFrame(frame)
end

local function gather()
    if not Minimap then return end

    -- Minimap children
    local kids = { Minimap:GetChildren() }
    local i
    for i = 1, table.getn(kids) do
        registerButton(kids[i])
    end

    -- MinimapBackdrop children (some addons parent here)
    local bd = getglobal("MinimapBackdrop")
    if bd and bd.GetChildren then
        local extra = { bd:GetChildren() }
        for i = 1, table.getn(extra) do
            registerButton(extra[i])
        end
    end

    -- Force-known Turtle / common
    for i = 1, table.getn(FORCE) do
        local f = getglobal(FORCE[i])
        if f then registerButton(f) end
    end

    -- Stock optionals (always register if present so Options can toggle)
    local stockNames = {
        "MinimapZoomIn", "MinimapZoomOut",
        "MiniMapMailFrame", "MiniMapTrackingFrame",
        "MiniMapBattlefieldFrame", "MiniMapMeetingStoneFrame",
    }
    for i = 1, table.getn(stockNames) do
        local f = getglobal(stockNames[i])
        if f then registerButton(f) end
    end
end

----------------------------------------------------------------------
-- Conflict notice (MBB / TurtleSnacks)
----------------------------------------------------------------------
local function warnConflicts()
    if conflictWarned then return end
    local hit = false
    if IsAddOnLoaded and IsAddOnLoaded("MinimapButtonBag") then hit = true end
    if getglobal("MBB_MinimapButtonFrame") then hit = true end
    if IsAddOnLoaded and IsAddOnLoaded("TurtleSnacks") then hit = true end
    if hit then
        conflictWarned = true
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffc79429IchaUI|r minimap drawer owns buttons — disable MinimapButtonBag / TurtleSnacks to avoid fights.",
            1, 0.85, 0.4
        )
        -- Soft-hide MBB bag button if present
        local mbb = getglobal("MBB_MinimapButtonFrame")
        if mbb and mbb.Hide then pcall(function() mbb:Hide() end) end
    end
end

----------------------------------------------------------------------
-- Public API (exact names for Options Map tab)
----------------------------------------------------------------------
function IchaUIMinimap_ListButtons()
    gather()
    local out = {}
    local names = {}
    local name
    for name, _ in pairs(managed) do
        table.insert(names, name)
    end
    table.sort(names)
    local i
    for i = 1, table.getn(names) do
        name = names[i]
        local cfg = btnCfg(name)
        table.insert(out, {
            id = name,
            label = prettyLabel(name),
            inDrawer = cfg.inDrawer and true or false,
            freeMove = cfg.freeMove and true or false,
            moving = iconMoveOn and true or false,
        })
    end
    return out
end

function IchaUIMinimap_SetButton(id, field, value)
    if not id then return end
    gather()
    local entry = managed[id]
    if not entry then
        local f = getglobal(id)
        if f then
            registerButton(f)
            entry = managed[id]
        end
    end
    if not entry then return end
    local cfg = btnCfg(id)

    if field == "inDrawer" then
        cfg.inDrawer = value and true or false
        if cfg.inDrawer then
            cfg.freeMove = false
        end
        -- Always re-grid + visibility after drawer membership changes
        ensureDrawer()
        applyAll()
        layoutDrawerGrid()
        updateDrawerVisibility()
        return
    elseif field == "freeMove" then
        cfg.freeMove = value and true or false
        if cfg.freeMove then
            cfg.inDrawer = false
        end
        -- freeMove off: applyOne keeps saved free coords via placeFree(..., false)
        ensureDrawer()
        applyAll()
        return
    elseif field == "move" then
        -- Shared Move/Lock for all minimap icons (not a per-button free sticky).
        iconMoveOn = not iconMoveOn
        ensureDrawer()
        applyAll()
        return
    elseif field == "reset" or field == "resetPos" then
        clearSavedPos(cfg)
        cfg.freeMove = false
        -- Keep drawer membership as-is; if not in drawer, restore vanilla home
        ensureDrawer()
        if cfg.inDrawer then
            applyAll()
            layoutDrawerGrid()
            updateDrawerVisibility()
        else
            restoreHome(id, entry)
            -- Stock mail/tracking: force classic anchor if orig was already bad
            if id == "MiniMapMailFrame" and Minimap and entry.frame then
                local f = entry.frame
                f:SetParent(Minimap)
                f:ClearAllPoints()
                f:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 21, -1)
                rawShow(f)
            elseif id == "MiniMapTrackingFrame" and Minimap and entry.frame then
                local f = entry.frame
                f:SetParent(Minimap)
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -6, -1)
                rawShow(f)
            end
            showChrome(entry, true)
        end
        return
    else
        return
    end
end

function IchaUIMinimap_ResetButtonPos(id)
    if id then
        IchaUIMinimap_SetButton(id, "reset", true)
        return
    end
    -- nil id → reset every button's saved free coords and lock drag
    iconMoveOn = false
    gather()
    local name, entry
    for name, entry in pairs(managed) do
        IchaUIMinimap_SetButton(name, "reset", true)
    end
end

function IchaUIMinimap_GetDrawer()
    loadCfg()
    return {
        enabled = drawerEnabled,
        open = drawerOpen,
        drawerOpen = drawerOpen,
        iconMoving = iconMoveOn and true or false,
        moving = iconMoveOn and true or false,
        drawerDir = drawerDir or "down",
        drawerSpread = drawerSpread or 90,
        drawerArc = drawerArc or 360,
        drawerRot = drawerRot,
    }
end

function IchaUIMinimap_SetDrawer(field, value)
    loadCfg()
    if field == "enabled" then
        drawerEnabled = value and true or false
        saveCfg()
        ensureDrawer()
        applyAll()
        return
    elseif field == "open" or field == "drawerOpen" then
        drawerOpen = value and true or false
        saveCfg()
        ensureDrawer()
        layoutDrawerGrid()
        updateDrawerVisibility()
        return
    elseif field == "toggle" then
        ensureDrawer()
        toggleDrawer()
        return
    elseif field == "refresh" or field == "rescan" then
        IchaUIMinimapButtons_Refresh()
        return
    elseif field == "buttonScale" or field == "popScale" then
        ensureDrawer()
        layoutDrawerGrid()
        updateDrawerVisibility()
        return
    elseif field == "iconMove" or field == "buttonsMove" then
        iconMoveOn = not iconMoveOn
        ensureDrawer()
        applyAll()
        return
    elseif field == "dir" or field == "drawerDir" or field == "openDir" then
        local s = string.lower(tostring(value or "down"))
        if s ~= "up" and s ~= "left" and s ~= "right" and s ~= "radial" then s = "down" end
        drawerDir = s
        saveCfg()
        ensureDrawer()
        layoutDrawerGrid()
        updateDrawerVisibility()
        return
    elseif field == "drawerSpread" or field == "spread" then
        if IchaUI_DrawerNormSpread then
            drawerSpread = IchaUI_DrawerNormSpread(value)
        else
            drawerSpread = math.floor((tonumber(value) or 90) + 0.5)
            if drawerSpread < 10 then drawerSpread = 10 end
            if drawerSpread > 360 then drawerSpread = 360 end
        end
        saveCfg()
        ensureDrawer()
        layoutDrawerGrid()
        updateDrawerVisibility()
        return
    elseif field == "drawerArc" or field == "arc" then
        if IchaUI_DrawerNormArc then
            drawerArc = IchaUI_DrawerNormArc(value)
        else
            drawerArc = math.floor((tonumber(value) or 360) + 0.5)
            if drawerArc < 10 then drawerArc = 10 end
            if drawerArc > 360 then drawerArc = 360 end
        end
        saveCfg()
        ensureDrawer()
        layoutDrawerGrid()
        updateDrawerVisibility()
        return
    elseif field == "drawerRot" or field == "rot" then
        if IchaUI_DrawerNormRot then
            drawerRot = IchaUI_DrawerNormRot(value)
        else
            local n = tonumber(value)
            if n == nil then n = 90 end
            if n < -360 then n = -360 end
            if n > 360 then n = 360 end
            drawerRot = math.floor(n + 0.5)
        end
        saveCfg()
        ensureDrawer()
        layoutDrawerGrid()
        updateDrawerVisibility()
        return
    end
end

-- Extra helpers (Options may call Refresh by either name)
function IchaUIMinimapButtons_Refresh()
    loadCfg()
    ensureDrawer()
    gather()
    applyAll()
end

function IchaUIMinimapButtons_GetList()
    return IchaUIMinimap_ListButtons()
end

function IchaUIMinimapButtons_Set(name, field, value)
    return IchaUIMinimap_SetButton(name, field, value)
end

----------------------------------------------------------------------
-- Boot
----------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("ADDON_LOADED")

local rescanAt = nil

boot:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "IchaUI" then
        loadCfg()
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        loadCfg()
        ensureDrawer()
        warnConflicts()
        -- Delayed gather: many minimap buttons spawn after login
        rescanAt = GetTime() + 3
        if not bootDone then
            bootDone = true
            gather()
            applyAll()
        end
    end
end)

local rescansLeft = 2
local tick = CreateFrame("Frame")
tick:SetScript("OnUpdate", function()
    if not rescanAt then return end
    if GetTime() < rescanAt then return end
    gather()
    applyAll()
    rescansLeft = rescansLeft - 1
    if rescansLeft > 0 then
        rescanAt = GetTime() + 5
    else
        rescanAt = nil
    end
end)
