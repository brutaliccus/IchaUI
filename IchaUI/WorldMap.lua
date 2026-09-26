-- IchaUI WorldMap: the world map as a movable, scalable window (Lua 5.0 / 1.12).
-- <Ctrl> + mouse wheel scales it, <Shift> + mouse wheel changes its opacity,
-- drag the frame edge to move it. Esc closes it. Settings live in IchaUIDB.worldmap.
--
-- Based on ShaguTweaks by Eric Mauser (Shagu), MIT License
-- (mods/worldmap-window.lua and the WorldMap part of mods/turtle-wow.lua).
--
-- Copyright (c) 2021 Eric Mauser (Shagu)
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

local function installIchaUIWorldMap()
    local DEFAULTS = {
        enabled = true, border = true, scale = 0.85, alpha = 1,
        point = "CENTER", relPoint = "CENTER", x = 0, y = 30,
        levels = true, levelInst = true, levelRaids = true, levelPvP = true, levelFish = false,
    }
    local LEVEL_KEYS = { levels = true, levelInst = true, levelRaids = true, levelPvP = true, levelFish = true }
    local SCALE_LO, SCALE_HI = 0.4, 1.5
    local ALPHA_LO, ALPHA_HI = 0.2, 1
    -- Pixels of the title bar that must stay on screen after release / scale.
    local TITLE_KEEP = 40

    local st = {
        installed = false, active = false, blocked = nil,
        origToggle = nil, origPanel = nil, addedSpecial = false,
        border = nil, noticed = false,
    }
    -- Assigned later: dragStop/gripStop run before those local function lines.
    local raiseStrata, hookWheels, updateZoomLabel, snapshotArt, keepMapArt, reloadMapTiles
    local FULL_MARGIN = 2

    local function clamp(v, lo, hi)
        v = tonumber(v) or lo
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    local function db()
        if type(IchaUIDB) ~= "table" then IchaUIDB = {} end
        local d = IchaUIDB.worldmap
        if type(d) ~= "table" then
            d = {}
            IchaUIDB.worldmap = d
        end
        local k, v
        for k, v in pairs(DEFAULTS) do
            if d[k] == nil then d[k] = v end
        end
        return d
    end

    local function chat(msg)
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffedc75aIchaUI|r: " .. msg)
        end
    end

    local function hookScript(f, script, func)
        local prev = f:GetScript(script)
        f:SetScript(script, function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            if prev then prev(a1, a2, a3, a4, a5, a6, a7, a8, a9) end
            func(a1, a2, a3, a4, a5, a6, a7, a8, a9)
        end)
    end

    local function ownScript(f, script, func)
        local prev = f:GetScript(script)
        f:SetScript(script, function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            if st.active then
                func(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            elseif prev then
                prev(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            end
        end)
    end

    -- ShaguTweaks keys its module switches by the (localized) module title.
    local function shaguWindowOn()
        if not ShaguTweaks then return false end
        if ShaguTweaks.WorldMapWindowActive then return true end
        local cfg = ShaguTweaks_config
        if type(cfg) ~= "table" then return false end
        local key = "WorldMap Window"
        if type(ShaguTweaks.T) == "table" then
            key = ShaguTweaks.T["WorldMap Window"] or key
        end
        if cfg[key] == 1 or cfg["WorldMap Window"] == 1 then return true end
        return false
    end

    local function mapAddonOwnsMap()
        if Cartographer or METAMAP_TITLE then return true end
        return false
    end

    local function maximized()
        return WORLDMAP_WINDOWED ~= 1
    end

    local function scaleFor(v)
        return clamp(v, SCALE_LO, SCALE_HI)
    end

    local function round2(v)
        return math.floor(v * 100 + 0.5) / 100
    end

    local function getAnchor(f)
        local p, rel, rp, x, y
        local ok = pcall(function()
            p, rel, rp, x, y = f:GetPoint(1)
        end)
        if not p then
            p, rel, rp, x, y = f:GetPoint()
        end
        if not p then return nil end
        return p, rel, rp, x or 0, y or 0
    end

    -- Re-apply exactly what we saved. No derived size, no fit-cap shove.
    local function applyAnchor()
        local d = db()
        local f = WorldMapFrame
        if f._ichaMoving then return end
        f:ClearAllPoints()
        f:SetPoint(d.point or "CENTER", UIParent, d.relPoint or "CENTER", tonumber(d.x) or 0, tonumber(d.y) or 0)
    end

    local function saveAnchor()
        if maximized() then return end
        local p, rel, rp, x, y = getAnchor(WorldMapFrame)
        if not p then return end
        local d = db()
        d.point, d.relPoint = p, rp or p
        d.x, d.y = round2(x), round2(y)
    end

    -- Measured pixel edges. No GetWidth, no saved scale.
    local function nudgeTitle()
        local f = WorldMapFrame
        if f._ichaMoving or maximized() then return false end
        local es = f:GetEffectiveScale() or 1
        if es <= 0 then es = 1 end
        local us = UIParent:GetEffectiveScale() or 1
        if us <= 0 then us = 1 end
        local sl = (UIParent:GetLeft() or 0) * us
        local sr = UIParent:GetRight() and UIParent:GetRight() * us
        local stop = UIParent:GetTop() and UIParent:GetTop() * us
        local sb = (UIParent:GetBottom() or 0) * us
        if not sr then sr = (UIParent:GetWidth() or 0) * us end
        if not stop then stop = (UIParent:GetHeight() or 0) * us end
        local fl = f:GetLeft()
        local fr = f:GetRight()
        local ft = f:GetTop()
        if not fl or not ft then return false end
        fl, ft = fl * es, ft * es
        if fr then fr = fr * es else fr = fl end
        local tt = ft
        local title = WorldMapFrameTitle
        if title and title.GetTop and title:GetTop() then
            local tes = es
            if title.GetEffectiveScale then tes = title:GetEffectiveScale() or es end
            tt = title:GetTop() * tes
        end
        local dx, dy = 0, 0
        local visL, visR = fl, fr
        if visL < sl then visL = sl end
        if visR > sr then visR = sr end
        if visR - visL < TITLE_KEEP then
            if fr < sl + TITLE_KEEP then
                dx = (sl + TITLE_KEEP) - fr
            else
                dx = (sr - TITLE_KEEP) - fl
            end
        end
        if tt > stop then dy = stop - tt end
        if tt < sb then dy = sb - tt end
        if dx == 0 and dy == 0 then return false end
        local p, rel, rp, x, y = getAnchor(f)
        if not p then return false end
        f:ClearAllPoints()
        f:SetPoint(p, UIParent, rp, x + dx / es, y + dy / es)
        return true
    end

    -- Follow the cursor with no walls. 0-delta keeps the live GetPoint, so
    -- press cannot jump. Release ends via IsMouseButtonDown even over children.
    local drag = {}

    local function leftHeld()
        if not IsMouseButtonDown then return true end
        local down = true
        pcall(function()
            down = IsMouseButtonDown("LeftButton") and true or false
        end)
        return down
    end

    local function dragStop(keep)
        local f = WorldMapFrame
        if not f._ichaMoving then return end
        if drag.ticker then drag.ticker:SetScript("OnUpdate", nil) end
        f._ichaMoving = nil
        if keep then
            nudgeTitle()
            saveAnchor()
            if raiseStrata then raiseStrata() end
        end
    end

    local function dragUpdate()
        if not leftHeld() then
            dragStop(true)
            return
        end
        local f = WorldMapFrame
        local es = drag.es or 1
        local cx, cy = GetCursorPosition()
        f:ClearAllPoints()
        f:SetPoint(drag.point, UIParent, drag.rp,
            drag.x + (cx - drag.cx) / es, drag.y + (cy - drag.cy) / es)
    end

    local function dragStart()
        if not st.active or maximized() then return end
        local f = WorldMapFrame
        local p, rel, rp, x, y = getAnchor(f)
        if not p then return end
        drag.point, drag.rp, drag.x, drag.y = p, rp, x, y
        drag.cx, drag.cy = GetCursorPosition()
        local es = f:GetEffectiveScale() or 1
        if es <= 0 then es = 1 end
        drag.es = es
        f._ichaMoving = true
        if f.SetClampedToScreen then f:SetClampedToScreen(false) end
        if not drag.ticker then drag.ticker = CreateFrame("Frame") end
        drag.ticker:SetScript("OnUpdate", dragUpdate)
        drag.ticker:Show()
    end

    local function paintBorder()
        local b = st.border
        if not b then return end
        if st.active and db().border then
            if IchaUI_PaintGoldBorder then IchaUI_PaintGoldBorder(b, 1) end
            b:Show()
        else
            b:Hide()
        end
    end

    local function ensureBorder()
        if st.border then return st.border end
        local b = CreateFrame("Frame", "IchaUIWorldMapBorder", WorldMapFrame)
        b:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", -4, 4)
        b:SetPoint("BOTTOMRIGHT", WorldMapFrame, "BOTTOMRIGHT", 4, -4)
        b:SetBackdrop({
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        b:SetBackdropColor(0, 0, 0, 0)
        b:SetFrameLevel((WorldMapFrame:GetFrameLevel() or 1) + 8)
        b:EnableMouse(false)
        st.border = b
        return b
    end

    -- The map art has a fixed size, so resizing changes the scale. The top-left
    -- corner stays put while dragging; the spot is saved as CENTER on release.
    local function gripUpdate()
        local g = st.grip
        local f = WorldMapFrame
        local cx, cy = GetCursorPosition()
        local es = f:GetEffectiveScale() or 1
        local ps = es / (f:GetScale() or 1)
        local w = (f:GetWidth() or 0) * ps
        local h = (f:GetHeight() or 0) * ps
        if w <= 0 or h <= 0 then return end
        local s = (cx - g._left) / w
        local sy = (g._top - cy) / h
        if sy > s then s = sy end
        if maximized() then return end
        s = scaleFor(s)
        db().scale = s
        if snapshotArt then snapshotArt() end
        f:SetScale(s)
        st.needArtRestore = true
        local nes = f:GetEffectiveScale() or 1
        if nes <= 0 then nes = 1 end
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", g._left / nes, g._top / nes)
        if keepMapArt then keepMapArt() end
        if updateZoomLabel then updateZoomLabel() end
    end

    local function gripStop()
        local g = st.grip
        if not g or not g._sizing then return end
        g._sizing = nil
        g:SetScript("OnUpdate", nil)
        nudgeTitle()
        saveAnchor()
        if keepMapArt then keepMapArt() end
        if raiseStrata then raiseStrata() end
        if reloadMapTiles then reloadMapTiles() end
        if updateZoomLabel then updateZoomLabel() end
        if IchaUI_WorldMap_OptRefresh then IchaUI_WorldMap_OptRefresh() end
    end

    local function ensureGrip()
        if st.grip then return st.grip end
        local g = CreateFrame("Button", "IchaUIWorldMapGrip", WorldMapFrame)
        g:SetWidth(16)
        g:SetHeight(16)
        g:SetPoint("BOTTOMRIGHT", WorldMapFrame, "BOTTOMRIGHT", -2, 2)
        g:SetFrameLevel((WorldMapFrame:GetFrameLevel() or 1) + 12)
        g:EnableMouse(true)
        g:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        g:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        g:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight", "ADD")
        local texs = { g:GetNormalTexture(), g:GetPushedTexture() }
        local ti
        for ti = 1, 2 do
            local t = texs[ti]
            if t and IchaUI_PaintGoldVertex then
                IchaUI_PaintGoldVertex(t, 0.93, 0.78, 0.35, 1, true)
            elseif t and t.SetVertexColor then
                t:SetVertexColor(0.93, 0.78, 0.35, 1)
            end
        end
        g:SetScript("OnMouseDown", function()
            if not st.active or maximized() then return end
            local f = WorldMapFrame
            local es = f:GetEffectiveScale() or 1
            local left, top = f:GetLeft(), f:GetTop()
            if not left or not top then return end
            this._left = left * es
            this._top = top * es
            this._sizing = true
            if snapshotArt then snapshotArt() end
            this:SetScript("OnUpdate", gripUpdate)
        end)
        g:SetScript("OnMouseUp", gripStop)
        g:SetScript("OnHide", gripStop)
        g:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT")
            GameTooltip:SetText("Drag to resize the map")
            GameTooltip:Show()
        end)
        g:SetScript("OnLeave", function() GameTooltip:Hide() end)
        st.grip = g
        return g
    end

    -- Invisible title and edge hit-rects above Magnify's scroll frame so
    -- dragging still works when the map art covers WorldMapFrame.
    local function bindDrag(fr)
        fr:EnableMouse(true)
        fr:SetScript("OnMouseDown", function()
            if arg1 and arg1 ~= "LeftButton" then return end
            dragStart()
        end)
        fr:SetScript("OnMouseUp", function()
            dragStop(true)
        end)
    end

    local function ensureEdges()
        if st.edges then
            local i
            for i = 1, table.getn(st.edges) do st.edges[i]:Show() end
            return
        end
        local parent = WorldMapFrame
        local lv = (parent:GetFrameLevel() or 1) + 10
        local edges = {}
        local function strip(name, w, h)
            local s = CreateFrame("Frame", name, parent)
            s:SetFrameLevel(lv)
            if w then s:SetWidth(w) end
            if h then s:SetHeight(h) end
            bindDrag(s)
            table.insert(edges, s)
            return s
        end
        local top = strip("IchaUIWorldMapDragTop", nil, 32)
        top:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 4)
        top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 4)
        local left = strip("IchaUIWorldMapDragLeft", 10, nil)
        left:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 10)
        local right = strip("IchaUIWorldMapDragRight", 10, nil)
        right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, 0)
        right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 18)
        local bot = strip("IchaUIWorldMapDragBot", nil, 10)
        bot:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 10, 0)
        bot:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -18, 0)
        st.edges = edges
        local names = {
            "WorldMapFrameCloseButton", "WorldMapFrameMaximizeButton",
            "WorldMapFrameMinimizeButton",
        }
        local i
        for i = 1, table.getn(names) do
            local b = getglobal(names[i])
            if b and b.SetFrameLevel then
                b:SetFrameLevel(lv + 4)
            end
        end
    end

    local function hookRelease(fr)
        if not fr or not fr.GetScript or fr._ichaRel then return end
        fr._ichaRel = true
        hookScript(fr, "OnMouseUp", function()
            dragStop(true)
        end)
    end

    -- Ctrl + wheel scales, Shift + wheel fades. Returns true when it used the event.
    local function wheelStep()
        if not st.active then return false end
        local d = db()
        local step = (arg1 or 0) / 10
        if IsShiftKeyDown() then
            IchaUI_WorldMap_Set("alpha", (tonumber(d.alpha) or 1) + step)
            return true
        elseif IsControlKeyDown() then
            if maximized() then return true end
            IchaUI_WorldMap_Set("scale", (tonumber(d.scale) or 1) + step)
            return true
        end
        return false
    end

    ------------------------------------------------------------------
    -- Built-in zoom, only when Magnify is not installed. The detail frame
    -- (map art, WorldMapButton and every pin on it) becomes the scroll child
    -- of a clip frame and is scaled toward the cursor. Maximized map only:
    -- it is detached again before Turtle's Minimize lays the map out.
    ------------------------------------------------------------------
    local ZOOM_MAX, ZOOM_STEP = 2.5, 0.25
    -- Vanilla WorldMapDetailFrame size. Magnify's windowed 702x468 is Turtle's
    -- small map; IchaUI's window is this full map, scaled.
    local MAP_ART_W, MAP_ART_H = 1002, 668
    local zoom = { frame = nil, attached = false, pan = nil, moved = false, marker = nil, model = nil, map = nil }

    local function zoomScale()
        return WorldMapDetailFrame:GetScale() or 1
    end

    local function zoomed()
        return zoom.attached and zoomScale() > 1.001
    end

    local function zoomScroll(x, y, s)
        local zf = zoom.frame
        local maxX = ((WorldMapDetailFrame:GetWidth() or 0) * s - (zf:GetWidth() or 0)) / s
        local maxY = ((WorldMapDetailFrame:GetHeight() or 0) * s - (zf:GetHeight() or 0)) / s
        if maxX < 0 then maxX = 0 end
        if maxY < 0 then maxY = 0 end
        -- 1.12 scroll frames: horizontal scroll is negative, vertical positive.
        zf:SetHorizontalScroll(-clamp(x, 0, maxX))
        zf:SetVerticalScroll(clamp(y, 0, maxY))
    end

    -- The player arrow model is placed by the client in unscaled map units,
    -- so it drifts when zoomed. Swap it for a dot on WorldMapButton meanwhile.
    local function zoomMarker(on)
        if zoom.model and zoom.model.SetModelScale then
            if on then zoom.model:SetModelScale(0) else zoom.model:SetModelScale(1) end
        end
        if zoom.marker then
            if on then zoom.marker:Show() else zoom.marker:Hide() end
        end
    end

    local function zoomReset()
        if not zoom.frame then return end
        zoom.pan = nil
        zoom.moved = false
        if zoom.attached then
            WorldMapDetailFrame:SetScale(1)
            zoom.frame:SetHorizontalScroll(0)
            zoom.frame:SetVerticalScroll(0)
        end
        zoomMarker(false)
    end

    local function zoomAttach()
        -- Magnify already owns WorldMapDetailFrame as its scroll child.
        if WorldMapFrameScrollFrame then return end
        local df = WorldMapDetailFrame
        if not zoom.frame or zoom.attached or not df or not df.GetPoint then return end
        local p, rel, rp, x, y = df:GetPoint(1)
        local zf = zoom.frame
        local dw, dh = df:GetWidth() or 0, df:GetHeight() or 0
        if dw < 1 then dw = MAP_ART_W end
        if dh < 1 then dh = MAP_ART_H end
        zf:ClearAllPoints()
        zf:SetPoint(p or "TOP", rel or WorldMapFrame, rp or p or "TOP", x or 0, y or 0)
        zf:SetWidth(dw)
        zf:SetHeight(dh)
        zoom.parent = df:GetParent()
        zoom.points = { p, rel, rp, x, y }
        df:SetWidth(dw)
        df:SetHeight(dh)
        if df.Show then df:Show() end
        zf:SetScrollChild(df)
        zf:Show()
        zoom.attached = true
        zoomReset()
    end

    local function zoomDetach()
        if not zoom.attached then return end
        zoomReset()
        local df = WorldMapDetailFrame
        local pt = zoom.points
        df:SetParent(zoom.parent or WorldMapFrame)
        df:ClearAllPoints()
        if pt and pt[1] then
            df:SetPoint(pt[1], pt[2] or WorldMapFrame, pt[3] or pt[1], pt[4] or 0, pt[5] or 0)
        end
        zoom.frame:Hide()
        zoom.attached = false
    end

    local function magnifyFrame()
        local sf = WorldMapFrameScrollFrame
        if sf and sf.GetScrollChild then
            local ch = sf:GetScrollChild()
            if ch then return ch end
        end
        return WorldMapDetailFrame
    end

    -- Magnify scales WorldMapDetailFrame (the scroll child). Read that
    -- frame's GetScale(), not a cached value or the window scale.
    local function liveZoom()
        local df = magnifyFrame()
        if df and df.GetScale then
            local z = tonumber(df:GetScale()) or 0
            if z > 0 then return z end
        end
        df = WorldMapDetailFrame
        if df and df.GetScale then
            local z = tonumber(df:GetScale()) or 0
            if z > 0 then return z end
        end
        if MAGNIFY_MIN_ZOOM then return MAGNIFY_MIN_ZOOM end
        return 1
    end

    local function mapScroll()
        if WorldMapFrameScrollFrame then return WorldMapFrameScrollFrame end
        if zoom.attached and zoom.frame then return zoom.frame end
        return nil
    end

    local function showMapTiles()
        local n = NUM_WORLDMAP_DETAIL_TILES or 12
        local i
        for i = 1, n do
            local t = getglobal("WorldMapDetailTile" .. i)
            if t then
                if t.SetAlpha then t:SetAlpha(1) end
                if t.Show then t:Show() end
            end
        end
    end

    reloadMapTiles = function()
        showMapTiles()
        local tile = getglobal("WorldMapDetailTile1")
        local tex
        if tile and tile.GetTexture then tex = tile:GetTexture() end
        if (not tex or tex == "") and SetMapToCurrentZone then
            SetMapToCurrentZone()
        end
        if WorldMapFrame_Update then
            local o = this
            this = WorldMapFrame
            pcall(WorldMapFrame_Update)
            this = o
        end
        showMapTiles()
        local df = WorldMapDetailFrame
        if df and df.Show then df:Show() end
        if WorldMapButton and WorldMapButton.Show then WorldMapButton:Show() end
    end

    -- Parent SetScale on a 1.12 ScrollFrame can drop the child (zero size,
    -- scale 1, scroll 0). Snapshot before the scale change; restore after.
    snapshotArt = function()
        local df = WorldMapDetailFrame
        local sf = mapScroll()
        local snap = { z = liveZoom(), h = 0, v = 0, dw = MAP_ART_W, dh = MAP_ART_H, sw = MAP_ART_W, sh = MAP_ART_H }
        if df then
            local dw, dh = df:GetWidth() or 0, df:GetHeight() or 0
            if dw >= 1 then snap.dw = dw end
            if dh >= 1 then snap.dh = dh end
        end
        if sf then
            snap.h = sf:GetHorizontalScroll() or 0
            snap.v = sf:GetVerticalScroll() or 0
            local sw, sh = sf:GetWidth() or 0, sf:GetHeight() or 0
            if sw >= 1 then snap.sw = sw end
            if sh >= 1 then snap.sh = sh end
        end
        st.artSnap = snap
    end

    -- Magnify owns WorldMapFrameScrollFrame size/anchor (702x468 windowed,
    -- 1002x668 fullscreen). IchaUI must not retarget it.
    local function fitMapScroll()
        if WorldMapFrameScrollFrame then return end
        local sf = mapScroll()
        if not sf then return end
        sf:SetWidth(MAP_ART_W)
        sf:SetHeight(MAP_ART_H)
        if sf.ClearAllPoints then sf:ClearAllPoints() end
        sf:SetPoint("TOP", WorldMapFrame, "TOP", 0, -36)
        if sf.Show then sf:Show() end
    end

    -- Recover from 1.12 parent-SetScale dropping the scroll child. Magnify
    -- owns WorldMapDetailFrame:SetScale and pan; do not overwrite them.
    keepMapArt = function(restoreZoom)
        if restoreZoom == nil then restoreZoom = true end
        local df = WorldMapDetailFrame
        if not df then return end
        local sf = mapScroll()
        local snap = st.artSnap
        local mag = WorldMapFrameScrollFrame and true or false
        local dw = df:GetWidth() or 0
        local dh = df:GetHeight() or 0
        if dw < 1 then
            dw = MAP_ART_W
            if snap and snap.dw and snap.dw > 0 then dw = snap.dw end
            df:SetWidth(dw)
        end
        if dh < 1 then
            dh = MAP_ART_H
            if snap and snap.dh and snap.dh > 0 then dh = snap.dh end
            df:SetHeight(dh)
        end
        if df.Show then df:Show() end
        if WorldMapButton and WorldMapButton.Show then WorldMapButton:Show() end
        if mag then
            if sf then
                local par = df.GetParent and df:GetParent()
                if par ~= sf then
                    if df.SetParent then df:SetParent(sf) end
                    if sf.SetScrollChild then sf:SetScrollChild(df) end
                end
                -- Turtle leftover TOPLEFT 12,-70 double-offsets Magnify's child.
                -- Do not SetPoint; a 1.12 scroll child must have no extra point.
                if not maximized() and df.ClearAllPoints then df:ClearAllPoints() end
                if (sf:GetWidth() or 0) < 1 then
                    local sw = MAP_ART_W
                    if snap and snap.sw and snap.sw > 0 then sw = snap.sw end
                    sf:SetWidth(sw)
                end
                if (sf:GetHeight() or 0) < 1 then
                    local sh = MAP_ART_H
                    if snap and snap.sh and snap.sh > 0 then sh = snap.sh end
                    sf:SetHeight(sh)
                end
                if sf.Show then sf:Show() end
            end
            -- Only put Magnify's zoom back after IchaUI SetScale'd the window
            -- (1.12 resets the child). Never clamp Magnify to 1.0x otherwise.
            if st.needArtRestore and restoreZoom and snap and snap.z and snap.z > 0 then
                df:SetScale(snap.z)
                if sf then
                    sf:SetHorizontalScroll(snap.h or 0)
                    sf:SetVerticalScroll(snap.v or 0)
                end
            end
            st.needArtRestore = nil
            showMapTiles()
            return
        end
        local z = liveZoom()
        if restoreZoom and snap and snap.z and snap.z > 0 then z = snap.z end
        if z < 1 then z = 1 end
        if WorldMapButton then
            if (WorldMapButton:GetWidth() or 0) < 1 then WorldMapButton:SetWidth(MAP_ART_W) end
            if (WorldMapButton:GetHeight() or 0) < 1 then WorldMapButton:SetHeight(MAP_ART_H) end
            if sf and WorldMapButton.SetParent then
                local bp = WorldMapButton.GetParent and WorldMapButton:GetParent()
                if bp ~= df then WorldMapButton:SetParent(df) end
            end
        end
        df:SetScale(z)
        if sf then
            if df.SetParent then df:SetParent(sf) end
            if sf.SetScrollChild then sf:SetScrollChild(df) end
            if df.ClearAllPoints then df:ClearAllPoints() end
            local sw = sf:GetWidth() or 0
            local sh = sf:GetHeight() or 0
            if sw < 1 then
                sw = MAP_ART_W
                if snap and snap.sw and snap.sw > 0 then sw = snap.sw end
                sf:SetWidth(sw)
            end
            if sh < 1 then
                sh = MAP_ART_H
                if snap and snap.sh and snap.sh > 0 then sh = snap.sh end
                sf:SetHeight(sh)
            end
            if sf.Show then sf:Show() end
            dw = df:GetWidth() or 0
            dh = df:GetHeight() or 0
            sw = sf:GetWidth() or 0
            sh = sf:GetHeight() or 0
            local maxX, maxY = 0, 0
            if z > 0 then
                maxX = (dw * z - sw) / z
                maxY = (dh * z - sh) / z
            end
            if maxX < 0 then maxX = 0 end
            if maxY < 0 then maxY = 0 end
            local h, v = 0, 0
            if snap then h, v = snap.h or 0, snap.v or 0 end
            local absH = -h
            if absH < 0 then absH = 0 end
            if absH > maxX then absH = maxX end
            if v < 0 then v = 0 end
            if v > maxY then v = maxY end
            sf:SetHorizontalScroll(-absH)
            sf:SetVerticalScroll(v)
            sf.maxX, sf.maxY = maxX, maxY
            sf.zoomedIn = z > 1.001
        end
        showMapTiles()
    end

    local function packFrame(f)
        if not f then return nil end
        local p, rel, rp, x, y = getAnchor(f)
        local pn, rn
        if f.GetParent then
            local par = f:GetParent()
            if par and par.GetName then pn = par:GetName() end
        end
        if rel and rel.GetName then rn = rel:GetName() end
        return {
            p = p, rp = rp, x = x or 0, y = y or 0, rn = rn, pn = pn,
            w = f:GetWidth() or 0, h = f:GetHeight() or 0,
        }
    end

    local function unpackFrame(f, s)
        if not f or not s then return end
        if s.pn then
            local par = getglobal(s.pn)
            if par and f.SetParent then f:SetParent(par) end
        end
        if s.w and s.w >= 1 then f:SetWidth(s.w) end
        if s.h and s.h >= 1 then f:SetHeight(s.h) end
        if f.ClearAllPoints then f:ClearAllPoints() end
        if s.p then
            local rel = WorldMapFrame
            if s.rn then rel = getglobal(s.rn) or rel end
            f:SetPoint(s.p, rel, s.rp or s.p, s.x or 0, s.y or 0)
        end
    end

    local function captureWinLayout()
        local sf = WorldMapFrameScrollFrame
        st.winLayout = {
            frameW = WorldMapFrame:GetWidth(),
            frameH = WorldMapFrame:GetHeight(),
            scroll = packFrame(sf),
            detail = packFrame(WorldMapDetailFrame),
            button = packFrame(WorldMapButton),
            drop = packFrame(getglobal("pfQuestMapDropdown")),
            dropLevel = packFrame(getglobal("pfQuestMapLevelDropdown")),
            dropFilter = packFrame(getglobal("ModernMapMarkersFilter_Blizz")),
            dropFind = packFrame(getglobal("ModernMapMarkersFind_Blizz")),
            guide = packFrame(WorldMapPositioningGuide),
            h = 0, v = 0,
        }
        if sf then
            st.winLayout.h = sf:GetHorizontalScroll() or 0
            st.winLayout.v = sf:GetVerticalScroll() or 0
        end
    end

    local function applyWinLayout()
        local L = st.winLayout
        if not L then return end
        if L.frameW then WorldMapFrame:SetWidth(L.frameW) end
        if L.frameH then WorldMapFrame:SetHeight(L.frameH) end
        unpackFrame(WorldMapPositioningGuide, L.guide)
        unpackFrame(WorldMapFrameScrollFrame, L.scroll)
        local sf = WorldMapFrameScrollFrame
        local df = WorldMapDetailFrame
        if sf then
            -- Magnify owns the scroll child; never SetPoint it (double-offset).
            if df then
                if df.SetParent then df:SetParent(sf) end
                if sf.SetScrollChild then sf:SetScrollChild(df) end
                if df.ClearAllPoints then df:ClearAllPoints() end
            end
            unpackFrame(WorldMapButton, L.button)
            unpackFrame(getglobal("pfQuestMapDropdown"), L.drop)
            unpackFrame(getglobal("pfQuestMapLevelDropdown"), L.dropLevel)
            unpackFrame(getglobal("ModernMapMarkersFilter_Blizz"), L.dropFilter)
            unpackFrame(getglobal("ModernMapMarkersFind_Blizz"), L.dropFind)
            sf:SetHorizontalScroll(L.h or 0)
            sf:SetVerticalScroll(L.v or 0)
        else
            unpackFrame(WorldMapDetailFrame, L.detail)
            unpackFrame(WorldMapButton, L.button)
            unpackFrame(getglobal("pfQuestMapDropdown"), L.drop)
            unpackFrame(getglobal("pfQuestMapLevelDropdown"), L.dropLevel)
            unpackFrame(getglobal("ModernMapMarkersFilter_Blizz"), L.dropFilter)
            unpackFrame(getglobal("ModernMapMarkersFind_Blizz"), L.dropFind)
        end
    end

    local function finishMapLayout()
        local df = WorldMapDetailFrame
        if st.holdArt then
            st.artSnap = st.holdArt
            st.holdArt = nil
        end
        if maximized() then
            -- Do not rewrite Turtle/Magnify fullscreen geometry.
            keepMapArt(true)
        else
            if st.winLayout then
                applyWinLayout()
                st.needArtRestore = true
                keepMapArt(true)
            else
                keepMapArt(true)
                captureWinLayout()
            end
        end
        reloadMapTiles()
        if df and (df:GetWidth() or 0) < 1 then
            df:SetWidth(MAP_ART_W)
            df:SetHeight(MAP_ART_H)
            keepMapArt(true)
        end
        if updateZoomLabel then updateZoomLabel() end
    end

    local function runMagnifyWheel()
        local sf = WorldMapFrameScrollFrame
        if not sf or not WorldMapFrameScrollFrame_OnMouseWheel then return false end
        local o = this
        this = sf
        WorldMapFrameScrollFrame_OnMouseWheel()
        this = o
        return true
    end

    local function zoomAt(delta)
        if not zoom.attached then return end
        local zf = zoom.frame
        local old = zoomScale()
        local new = clamp(old + (delta or 0) * ZOOM_STEP, 1, ZOOM_MAX)
        if math.abs(new - old) < 0.001 then return end
        local left, top = zf:GetLeft(), zf:GetTop()
        if not left or not top then return end
        local es = zf:GetEffectiveScale() or 1
        local cx, cy = GetCursorPosition()
        local fx = clamp(cx / es - left, 0, zf:GetWidth() or 0)
        local fy = clamp(top - cy / es, 0, zf:GetHeight() or 0)
        local ox = -zf:GetHorizontalScroll() + fx / old
        local oy = zf:GetVerticalScroll() + fy / old
        WorldMapDetailFrame:SetScale(new)
        zoomScroll(ox - fx / new, oy - fy / new, new)
        zoomMarker(new > 1.001)
    end

    local function zoomUpdate()
        if not zoom.attached then return end
        local p = zoom.pan
        if p then
            local x, y = GetCursorPosition()
            local es = WorldMapDetailFrame:GetEffectiveScale() or 1
            local dx = (p.x - x) / es
            local dy = (y - p.y) / es
            if math.abs(dx) >= 1 or math.abs(dy) >= 1 then zoom.moved = true end
            if zoom.moved then zoomScroll(p.h + dx, p.v + dy, zoomScale()) end
        end
        local m = zoom.marker
        if m and m:IsShown() then
            local px, py = GetPlayerMapPosition("player")
            local s = zoomScale()
            if not px or (px == 0 and py == 0) then
                m.tex:Hide()
            else
                m.tex:Show()
                m.tex:SetWidth(16 / s)
                m.tex:SetHeight(16 / s)
                m:ClearAllPoints()
                m:SetPoint("CENTER", WorldMapButton, "TOPLEFT",
                    px * (WorldMapButton:GetWidth() or 0), -py * (WorldMapButton:GetHeight() or 0))
            end
        end
    end

    local function setupZoom()
        if zoom.frame or WorldMapFrameScrollFrame or not WorldMapDetailFrame then return end
        local zf = CreateFrame("ScrollFrame", "IchaUIWorldMapZoom", WorldMapFrame)
        zf:Hide()
        zoom.frame = zf

        local m = CreateFrame("Frame", "IchaUIWorldMapZoomPlayer", WorldMapButton)
        m:SetWidth(1)
        m:SetHeight(1)
        m:SetFrameLevel((WorldMapButton:GetFrameLevel() or 1) + 6)
        m.tex = m:CreateTexture(nil, "OVERLAY")
        m.tex:SetTexture("Interface\\WorldMap\\WorldMapPartyIcon")
        m.tex:SetVertexColor(1, 0.82, 0, 1)
        m.tex:SetPoint("CENTER", m, "CENTER", 0, 0)
        m:Hide()
        zoom.marker = m

        if WorldMapFrame.GetChildren then
            local kids = { WorldMapFrame:GetChildren() }
            local i
            for i = 1, table.getn(kids) do
                local k = kids[i]
                if k and k.GetFrameType and k:GetFrameType() == "Model" and not k:GetName() then
                    zoom.model = k
                    break
                end
            end
        end

        hookScript(WorldMapButton, "OnMouseDown", function()
            zoom.moved = false
            zoom.pan = nil
            if not st.active or arg1 ~= "LeftButton" or not zoomed() then return end
            local x, y = GetCursorPosition()
            zoom.pan = { x = x, y = y, h = -zoom.frame:GetHorizontalScroll(), v = zoom.frame:GetVerticalScroll() }
        end)
        hookScript(WorldMapButton, "OnMouseUp", function()
            zoom.pan = nil
        end)
        local oldClick = WorldMapButton:GetScript("OnClick")
        WorldMapButton:SetScript("OnClick", function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            -- A pan ends on mouse up; don't let it also click into a zone.
            if zoom.moved then
                zoom.moved = false
                return
            end
            if oldClick then oldClick(a1, a2, a3, a4, a5, a6, a7, a8, a9) end
        end)
        hookScript(WorldMapButton, "OnUpdate", zoomUpdate)
        hookScript(WorldMapFrame, "OnHide", zoomReset)

        local ev = CreateFrame("Frame")
        ev:RegisterEvent("WORLD_MAP_UPDATE")
        ev:SetScript("OnEvent", function()
            local id = tostring(GetCurrentMapContinent and GetCurrentMapContinent() or 0) .. ":"
                .. tostring(GetCurrentMapZone and GetCurrentMapZone() or 0)
            if id ~= zoom.map then
                zoom.map = id
                zoomReset()
            end
        end)
    end

    -- Plain wheel: Magnify's zoom when it is installed, else the built-in one.
    local function zoomWheel()
        if runMagnifyWheel() then return end
        zoomAt(arg1)
    end

    -- 1.12 sends the wheel to the topmost mouse-enabled frame under the cursor.
    -- A hit-rect with EnableMouse but no wheel handler swallows Ctrl/Shift.
    -- Chain every mouse frame in the window: Ctrl/Shift are ours, plain zooms.
    local wheelWrap = {}
    local function wrapWheel(f, isMagnify)
        if not f or not f.GetScript then return end
        local name = "?"
        if f.GetName then name = f:GetName() or "?" end
        if name ~= "?" and name ~= "" then
            st.wheelHooked = st.wheelHooked or {}
            local i, seen
            seen = false
            for i = 1, table.getn(st.wheelHooked) do
                if st.wheelHooked[i] == name then seen = true end
            end
            if not seen then table.insert(st.wheelHooked, name) end
        end
        local cur = f:GetScript("OnMouseWheel")
        if cur and cur == wheelWrap[f] then
            if f.EnableMouseWheel then f:EnableMouseWheel(1) end
            return
        end
        local prev = cur
        if isMagnify then st.magnifyWheel = prev end
        local w = function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            if arg1 == nil and a1 ~= nil then arg1 = a1 end
            local mod = "none"
            if IsShiftKeyDown and IsShiftKeyDown() then
                mod = "shift"
            elseif IsControlKeyDown and IsControlKeyDown() then
                mod = "ctrl"
            end
            st.lastWheel = { frame = name, mod = mod, delta = tonumber(arg1) or 0 }
            if wheelStep() then
                if updateZoomLabel then updateZoomLabel() end
                return
            end
            if st.active and not isMagnify then
                zoomWheel()
            elseif isMagnify then
                if prev then
                    prev(a1, a2, a3, a4, a5, a6, a7, a8, a9)
                else
                    runMagnifyWheel()
                end
            elseif prev then
                prev(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            end
            if updateZoomLabel then updateZoomLabel() end
        end
        wheelWrap[f] = w
        f:SetScript("OnMouseWheel", w)
        if f.EnableMouseWheel then f:EnableMouseWheel(1) end
    end

    hookWheels = function()
        st.wheelHooked = {}
        local function walk(fr, depth)
            if not fr or not fr.GetScript or depth > 6 then return end
            wrapWheel(fr, WorldMapFrameScrollFrame and fr == WorldMapFrameScrollFrame)
            if not fr.GetChildren then return end
            local kids = { fr:GetChildren() }
            local i
            for i = 1, table.getn(kids) do walk(kids[i], depth + 1) end
        end
        walk(WorldMapFrame, 0)
        if zoom.frame then wrapWheel(zoom.frame, false) end
    end

    -- FULLSCREEN keeps the map above the HUD but under dropdowns, the config
    -- panel and tooltips. 1.12 does not reliably carry a strata change down to
    -- existing children, so each child below it is set too; children already
    -- higher (Magnify's zone label, the level tooltip) keep theirs.
    local MAP_STRATA = "FULLSCREEN"
    local STRATA_RANK = {
        BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
        FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
    }

    local function liftStrata(fr)
        if not fr or not fr.GetFrameStrata then return end
        local cur = fr:GetFrameStrata()
        if (STRATA_RANK[cur] or 0) < STRATA_RANK[MAP_STRATA] then
            if st.strataSaved[fr] == nil then st.strataSaved[fr] = cur or false end
            fr:SetFrameStrata(MAP_STRATA)
        end
        -- Scroll children follow the clip frame; SetFrameStrata on them can
        -- yank the map art out of Magnify's scroll frame (invisible, scale 1).
        if fr == WorldMapFrameScrollFrame then return end
        if zoom.frame and fr == zoom.frame then return end
        if WorldMapFrameScrollFrame and fr == WorldMapDetailFrame then return end
        if zoom.frame and fr == WorldMapDetailFrame then return end
        if not fr.GetChildren then return end
        local kids = { fr:GetChildren() }
        local i
        for i = 1, table.getn(kids) do liftStrata(kids[i]) end
    end

    -- Children above the map strata, so a strata change that does cascade
    -- can be undone for them.
    local function highKids(fr, out)
        if not fr.GetChildren then return out end
        local kids = { fr:GetChildren() }
        local i
        for i = 1, table.getn(kids) do
            local k = kids[i]
            if k.GetFrameStrata and (STRATA_RANK[k:GetFrameStrata()] or 0) > STRATA_RANK[MAP_STRATA] then
                table.insert(out, { k, k:GetFrameStrata() })
            end
            highKids(k, out)
        end
        return out
    end

    local function keepHigh(list)
        local i
        for i = 1, table.getn(list) do list[i][1]:SetFrameStrata(list[i][2]) end
    end

    raiseStrata = function()
        local f = WorldMapFrame
        if not f or not f.SetFrameStrata then return end
        if st.origStrata == nil then st.origStrata = f:GetFrameStrata() or false end
        st.strataSaved = st.strataSaved or {}
        -- Always walk children. Turtle maximize/minimize can drop kids back
        -- to MEDIUM while the parent stays FULLSCREEN; an early return left
        -- new hit-rects and the map art under the HUD.
        local high = highKids(f, {})
        liftStrata(f)
        keepHigh(high)
        st.strataDone = true
    end

    local function restoreStrata()
        local f = WorldMapFrame
        local high = highKids(f, {})
        if st.origStrata and f.SetFrameStrata then f:SetFrameStrata(st.origStrata) end
        keepHigh(high)
        if st.strataSaved then
            local fr, old
            for fr, old in pairs(st.strataSaved) do
                if old and fr ~= f then fr:SetFrameStrata(old) end
            end
        end
        st.strataSaved, st.strataDone, st.origStrata = nil, nil, nil
    end

    local function screenEdges()
        local us = UIParent:GetEffectiveScale() or 1
        if us <= 0 then us = 1 end
        local sl = (UIParent:GetLeft() or 0) * us
        local sr = UIParent:GetRight() and UIParent:GetRight() * us
        local stop = UIParent:GetTop() and UIParent:GetTop() * us
        local sb = (UIParent:GetBottom() or 0) * us
        if not sr then sr = (UIParent:GetWidth() or 0) * us end
        if not stop then stop = (UIParent:GetHeight() or 0) * us end
        return sl, sb, sr, stop, us
    end

    -- Title top and border/frame bottom in true screen pixels.
    local function chromeEdges()
        local f = WorldMapFrame
        local es = f:GetEffectiveScale() or 1
        if es <= 0 then es = 1 end
        local fl, fr, ft, fb = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
        if not fl or not ft then return nil end
        fl, ft = fl * es, ft * es
        if fr then fr = fr * es else fr = fl end
        if fb then fb = fb * es else fb = ft end
        local top, bot = ft, fb
        local title = WorldMapFrameTitle
        if title and title.GetTop and title:GetTop() then
            local tes = es
            if title.GetEffectiveScale then tes = title:GetEffectiveScale() or es end
            local tt = title:GetTop() * tes
            if tt > top then top = tt end
        end
        local b = st.border
        if b and b.IsShown and b:IsShown() then
            if b.GetTop and b:GetTop() then
                local bes = es
                if b.GetEffectiveScale then bes = b:GetEffectiveScale() or es end
                local bt = b:GetTop() * bes
                if bt > top then top = bt end
            end
            if b.GetBottom and b:GetBottom() then
                local bes = es
                if b.GetEffectiveScale then bes = b:GetEffectiveScale() or es end
                local bb = b:GetBottom() * bes
                if bb < bot then bot = bb end
            end
        end
        return fl, bot, fr, top, es
    end

    local function computeFullScale()
        local sl, sb, sr, stop = screenEdges()
        local fl, bot, fr, top, es = chromeEdges()
        if not fl then return st.fullScale end
        local screenH = stop - sb
        local chromeH = top - bot
        if chromeH < 1 then return st.fullScale end
        local s0 = WorldMapFrame:GetScale() or 1
        if s0 <= 0 then s0 = 1 end
        return s0 * (screenH - FULL_MARGIN * 2) / chromeH
    end

    local function mapFrameSize()
        local bw, bh = MAP_ART_W, MAP_ART_H
        if WorldMapButton then
            local w, h = WorldMapButton:GetWidth() or 0, WorldMapButton:GetHeight() or 0
            if w >= 1 then bw = w end
            if h >= 1 then bh = h end
        end
        return bw + 15, bh + 55
    end

    -- Fit title+border to the measured screen height. Never writes IchaUIDB.
    local function layoutMaximized()
        local f = WorldMapFrame
        local fw, fh = mapFrameSize()
        f:SetWidth(fw)
        f:SetHeight(fh)
        if TargetHPText and WorldMapFrameTitle then
            WorldMapFrameTitle:SetPoint("TOP", f, 0, 17)
        end
        if not st.holdArt then
            snapshotArt()
        end
        f:SetScale(1)
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        local s = computeFullScale()
        if not s or s < 0.1 then s = 1 end
        st.fullScale = s
        f:SetScale(s)
        st.needArtRestore = true
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        local fl, bot, fr, top, es = chromeEdges()
        local sl, sb, sr, stop = screenEdges()
        if fl and es and es > 0 then
            local dx = ((sl + sr) / 2) - ((fl + fr) / 2)
            local dy = (stop - FULL_MARGIN) - top
            if dx ~= 0 or dy ~= 0 then
                f:ClearAllPoints()
                f:SetPoint("CENTER", UIParent, "CENTER", dx / es, dy / es)
            end
        end
        -- Attach built-in zoom after SetScale so the parent scale does not drop
        -- the scroll child. Magnify already owns WorldMapFrameScrollFrame —
        -- leave its fullscreen size/points alone.
        if not WorldMapFrameScrollFrame then
            zoomAttach()
        end
        keepMapArt(true)
    end

    local function ensureZoomInfo()
        if st.zoomInfo then return st.zoomInfo end
        local z = CreateFrame("Frame", "IchaUIWorldMapZoomInfo", WorldMapFrame)
        z:SetWidth(118)
        z:SetHeight(18)
        z:SetFrameLevel((WorldMapFrame:GetFrameLevel() or 1) + 16)
        z:EnableMouse(false)
        if z.EnableMouseWheel then z:EnableMouseWheel(false) end
        z:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        z:SetBackdropColor(0.05, 0.05, 0.06, 0.88)
        if IchaUI_PaintGoldLightBorder then
            IchaUI_PaintGoldLightBorder(z, 0.9)
        elseif z.SetBackdropBorderColor then
            z:SetBackdropBorderColor(0.93, 0.78, 0.35, 0.9)
        end
        local fs = z:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER", z, "CENTER", 0, 0)
        if fs.SetTextColor then fs:SetTextColor(0.95, 0.93, 0.85) end
        if IchaUI_PaintGoldFont then IchaUI_PaintGoldFont(fs, 0.93, 0.78, 0.35) end
        z.text = fs
        local btn = WorldMapFrameMinimizeButton or WorldMapFrameMaximizeButton or WorldMapFrameCloseButton
        if btn then
            z:SetPoint("RIGHT", btn, "LEFT", -8, 0)
        else
            z:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -36, -6)
        end
        z._acc = 0
        z:SetScript("OnUpdate", function()
            local elapsed = arg1
            if elapsed == nil then elapsed = 0 end
            z._acc = (z._acc or 0) + elapsed
            if z._acc < 0.15 then return end
            z._acc = 0
            if updateZoomLabel then updateZoomLabel() end
        end)
        st.zoomInfo = z
        return z
    end

    updateZoomLabel = function()
        local z = ensureZoomInfo()
        if not st.active or maximized() then
            z:Hide()
            return
        end
        if WorldMapFrame.IsShown and not WorldMapFrame:IsShown() then
            z:Hide()
            return
        end
        local zoom = liveZoom()
        local pct = math.floor((tonumber(db().scale) or 1) * 100 + 0.5)
        z.text:SetText(string.format("Zoom %.1fx   %d%%", zoom, pct))
        z:Show()
    end

    -- Scale, opacity and position only: safe on every show.
    local function applyLight()
        if not st.active then return end
        local d = db()
        local f = WorldMapFrame
        f:SetMovable(true)
        f:EnableMouse(true)
        f:EnableKeyboard(false)
        f:EnableMouseWheel(1)
        if f.SetClampedToScreen then f:SetClampedToScreen(false) end
        raiseStrata()
        d.scale = scaleFor(d.scale)
        f:SetAlpha(clamp(d.alpha, ALPHA_LO, ALPHA_HI))
        if BlackoutWorld then BlackoutWorld:Hide() end
        paintBorder()
        hookRelease(WorldMapButton)
        if WorldMapFrameScrollFrame then hookRelease(WorldMapFrameScrollFrame) end
        ensureGrip()
        ensureEdges()
        ensureZoomInfo()
        if maximized() then
            layoutMaximized()
            if st.grip then st.grip:Hide() end
            if st.edges then
                local i
                for i = 1, table.getn(st.edges) do st.edges[i]:Hide() end
            end
        else
            if not WorldMapFrameScrollFrame then
                zoomDetach()
                local fw, fh = mapFrameSize()
                f:SetWidth(fw)
                f:SetHeight(fh)
            elseif st.winLayout and st.winLayout.frameW then
                f:SetWidth(st.winLayout.frameW)
                f:SetHeight(st.winLayout.frameH)
            end
            if not st.holdArt then
                snapshotArt()
            end
            f:SetScale(d.scale)
            st.needArtRestore = true
            applyAnchor()
            if nudgeTitle() then saveAnchor() end
            if st.grip then st.grip:Show() end
            if st.edges then
                local i
                for i = 1, table.getn(st.edges) do st.edges[i]:Show() end
            end
        end
        if not st.hookedMagReset and Magnify_ResetZoom then
            st.hookedMagReset = true
            local oldReset = Magnify_ResetZoom
            Magnify_ResetZoom = function(a1, a2, a3)
                oldReset(a1, a2, a3)
                keepMapArt(false)
                reloadMapTiles()
                if updateZoomLabel then updateZoomLabel() end
            end
        end
        if not st.zoomEv then
            local ev = CreateFrame("Frame")
            ev:RegisterEvent("WORLD_MAP_UPDATE")
            ev:SetScript("OnEvent", function()
                if updateZoomLabel then updateZoomLabel() end
            end)
            st.zoomEv = ev
        end
        hookWheels()
        raiseStrata()
        finishMapLayout()
    end

    -- Turtle's WorldMapFrame_Maximize rebuilds the fullscreen layout; applyLight
    -- then fits chrome to the measured screen and does not save that layout.
    local function applyFull()
        if not st.active then return end
        applyLight()
    end

    local function setSpecial(on)
        local list = UISpecialFrames
        if type(list) ~= "table" then return end
        local i
        for i = table.getn(list), 1, -1 do
            if list[i] == "WorldMapFrame" then
                if on then return end
                if st.addedSpecial then table.remove(list, i) end
            end
        end
        if on then
            table.insert(list, "WorldMapFrame")
            st.addedSpecial = true
        else
            st.addedSpecial = false
        end
    end

    local function install()
        if st.installed then return end
        st.installed = true
        local f = WorldMapFrame

        st.origToggle = ToggleWorldMap
        ToggleWorldMap = function(a1, a2, a3)
            if not st.active then
                if st.origToggle then return st.origToggle(a1, a2, a3) end
                return
            end
            if WorldMapFrame:IsShown() then
                WorldMapFrame:Hide()
            else
                WorldMapFrame:Show()
            end
        end

        setupZoom()
        if type(WorldMapFrame_Maximize) == "function" then
            local oldMax = WorldMapFrame_Maximize
            WorldMapFrame_Maximize = function(a1, a2, a3)
                snapshotArt()
                st.holdArt = st.artSnap
                if not WorldMapFrameScrollFrame then
                    zoomDetach()
                end
                oldMax(a1, a2, a3)
                applyFull()
                finishMapLayout()
            end
        end
        if type(WorldMapFrame_Minimize) == "function" then
            local oldMin = WorldMapFrame_Minimize
            WorldMapFrame_Minimize = function(a1, a2, a3)
                snapshotArt()
                st.holdArt = st.artSnap
                if not WorldMapFrameScrollFrame then
                    zoomDetach()
                end
                oldMin(a1, a2, a3)
                applyLight()
                finishMapLayout()
            end
        end

        hookScript(f, "OnShow", function()
            applyLight()
            finishMapLayout()
        end)
        hookWheels()
        -- While windowed only this drag runs on the frame, so no other move or
        -- position save can fight it; the previous handlers run otherwise.
        ownScript(f, "OnMouseDown", function()
            if arg1 and arg1 ~= "LeftButton" then return end
            dragStart()
        end)
        ownScript(f, "OnMouseUp", function()
            dragStop(true)
        end)
        ownScript(f, "OnDragStart", function() end)
        ownScript(f, "OnDragStop", function() end)
        hookScript(f, "OnHide", function()
            dragStop(true)
        end)
    end

    local function activate()
        if st.active then return end
        install()
        st.active = true
        ensureBorder()
        setSpecial(true)
        if type(UIPanelWindows) == "table" then
            if st.origPanel == nil then st.origPanel = UIPanelWindows["WorldMapFrame"] or false end
            UIPanelWindows["WorldMapFrame"] = { area = "center" }
        end
        if WorldMapFrame.SetUserPlaced then
            pcall(WorldMapFrame.SetUserPlaced, WorldMapFrame, false)
        end
        if st.origClamp == nil then
            st.origClamp = false
            if WorldMapFrame.IsClampedToScreen and WorldMapFrame:IsClampedToScreen() then st.origClamp = true end
        end
        if maximized() and type(WorldMapFrame_Maximize) == "function" then
            WorldMapFrame_Maximize()
        else
            applyFull()
        end
    end

    local function deactivate()
        if not st.active then return end
        st.active = false
        local f = WorldMapFrame
        dragStop(false)
        setSpecial(false)
        if type(UIPanelWindows) == "table" and st.origPanel ~= nil then
            if st.origPanel then
                UIPanelWindows["WorldMapFrame"] = st.origPanel
            else
                UIPanelWindows["WorldMapFrame"] = nil
            end
        end
        zoomDetach()
        if f.SetClampedToScreen then f:SetClampedToScreen(st.origClamp and true or false) end
        f:SetScale(1)
        f:SetAlpha(1)
        f:EnableKeyboard(true)
        f:ClearAllPoints()
        f:SetAllPoints(UIParent)
        if BlackoutWorld then BlackoutWorld:Show() end
        paintBorder()
        if st.grip then st.grip:Hide() end
        if st.zoomInfo then st.zoomInfo:Hide() end
        if st.edges then
            local i
            for i = 1, table.getn(st.edges) do st.edges[i]:Hide() end
        end
        restoreStrata()
        if maximized() and type(WorldMapFrame_Maximize) == "function" then
            WorldMapFrame_Maximize()
        end
    end

    -- Returns false when another map owner blocks IchaUI's window.
    local function canRun()
        if st.blocked == nil then
            if mapAddonOwnsMap() then
                st.blocked = "addon"
            elseif shaguWindowOn() then
                st.blocked = "shagu"
            else
                st.blocked = false
            end
        end
        if st.blocked == "shagu" and not st.noticed and db().enabled then
            st.noticed = true
            chat("ShaguTweaks' |cffffffffWorldMap Window|r module is on, so IchaUI's windowed map stays off. "
                .. "Turn it off in |cffffffff/st|r and |cffffffff/reload|r to use IchaUI's map.")
        end
        return st.blocked == false
    end

    local function sync()
        if not WorldMapFrame or not WorldMapButton then return end
        if db().enabled and canRun() then
            activate()
            applyFull()
        else
            deactivate()
        end
    end

    function IchaUI_WorldMap_Get()
        return db()
    end

    -- "shagu" / "addon" when blocked, else nil. Only known after login.
    function IchaUI_WorldMap_Blocked()
        if st.blocked then return st.blocked end
        return nil
    end

    function IchaUI_WorldMap_Active()
        return st.active
    end

    function IchaUI_WorldMap_Set(key, value)
        local d = db()
        if key == "enabled" then
            d.enabled = value and true or false
            if st.ready then
                local was = st.active
                sync()
                if was and not st.active then
                    chat("Windowed world map off. |cffffffff/reload|r to fully restore the stock map.")
                end
            end
        elseif key == "border" then
            d.border = value and true or false
            paintBorder()
        elseif key == "scale" then
            d.scale = scaleFor(value)
            if st.active and WorldMapFrame and not maximized() then
                snapshotArt()
                WorldMapFrame:SetScale(d.scale)
                st.needArtRestore = true
                if nudgeTitle() then saveAnchor() end
                keepMapArt(true)
                reloadMapTiles()
                raiseStrata()
            end
            if updateZoomLabel then updateZoomLabel() end
        elseif key == "alpha" then
            d.alpha = clamp(value, ALPHA_LO, ALPHA_HI)
            applyLight()
        elseif LEVEL_KEYS[key] then
            d[key] = value and true or false
            if IchaUI_MapLevels_Refresh then IchaUI_MapLevels_Refresh() end
        end
        if key ~= "enabled" and IchaUI_WorldMap_OptRefresh then IchaUI_WorldMap_OptRefresh() end
    end

    function IchaUI_WorldMap_Reset()
        local d = db()
        d.point, d.relPoint = DEFAULTS.point, DEFAULTS.relPoint
        d.x, d.y = DEFAULTS.x, DEFAULTS.y
        d.scale, d.alpha = DEFAULTS.scale, DEFAULTS.alpha
        applyLight()
        if IchaUI_WorldMap_OptRefresh then IchaUI_WorldMap_OptRefresh() end
    end

    function IchaUI_WorldMap_Reload()
        if st.ready then sync() end
        if IchaUI_MapLevels_Refresh then IchaUI_MapLevels_Refresh() end
    end

    function IchaUI_WorldMap_Debug()
        local function n(v)
            if v == nil then return "nil" end
            local num = tonumber(v)
            if not num then return tostring(v) end
            return string.format("%.2f", num)
        end
        local f = WorldMapFrame
        local d = db()
        local sw, sh
        if GetScreenWidth then sw = GetScreenWidth() end
        if GetScreenHeight then sh = GetScreenHeight() end
        chat("mapdebug screen " .. n(sw) .. "x" .. n(sh))
        if UIParent then
            local us
            if UIParent.GetEffectiveScale then us = UIParent:GetEffectiveScale() end
            chat("mapdebug UIParent scale=" .. n(us)
                .. " w=" .. n(UIParent:GetWidth()) .. " h=" .. n(UIParent:GetHeight())
                .. " L=" .. n(UIParent:GetLeft()) .. " R=" .. n(UIParent:GetRight())
                .. " T=" .. n(UIParent:GetTop()) .. " B=" .. n(UIParent:GetBottom()))
        end
        if f then
            local p, rel, rp, x, y = getAnchor(f)
            local relName = "?"
            if rel then
                if rel.GetName then relName = rel:GetName() or "?" end
            else
                relName = "nil"
            end
            chat("mapdebug map scale=" .. n(f:GetScale()) .. " es=" .. n(f:GetEffectiveScale())
                .. " w=" .. n(f:GetWidth()) .. " h=" .. n(f:GetHeight()))
            chat("mapdebug map L=" .. n(f:GetLeft()) .. " R=" .. n(f:GetRight())
                .. " T=" .. n(f:GetTop()) .. " B=" .. n(f:GetBottom()))
            chat("mapdebug GetPoint " .. tostring(p) .. " " .. tostring(relName) .. " " .. tostring(rp)
                .. " x=" .. n(x) .. " y=" .. n(y))
        else
            chat("mapdebug WorldMapFrame missing")
        end
        chat("mapdebug saved point=" .. tostring(d.point) .. " rel=" .. tostring(d.relPoint)
            .. " x=" .. n(d.x) .. " y=" .. n(d.y) .. " scale=" .. n(d.scale))
        local mag = "no"
        if Magnify_ResetZoom or WorldMapFrameScrollFrame then mag = "yes" end
        local win = "nil"
        if WORLDMAP_WINDOWED ~= nil then win = tostring(WORLDMAP_WINDOWED) end
        chat("mapdebug Magnify=" .. mag .. " WORLDMAP_WINDOWED=" .. win
            .. " maximized=" .. tostring(maximized())
            .. " fullScale=" .. n(st.fullScale or computeFullScale()))
        local function strataOf(fr)
            if not fr then return "nil" end
            local nm = "?"
            if fr.GetName then nm = fr:GetName() or "?" end
            local s, lv = "?", "?"
            if fr.GetFrameStrata then s = tostring(fr:GetFrameStrata()) end
            if fr.GetFrameLevel then lv = tostring(fr:GetFrameLevel()) end
            return nm .. " " .. s .. "/" .. lv
        end
        chat("mapdebug strata " .. strataOf(WorldMapFrame)
            .. " | " .. strataOf(WorldMapButton)
            .. " | " .. strataOf(WorldMapDetailFrame)
            .. " | " .. strataOf(WorldMapFrameScrollFrame)
            .. " | " .. strataOf(st.grip)
            .. " | " .. strataOf(st.edges and st.edges[1]))
        local hooks, hn = "-", 0
        if st.wheelHooked then
            hn = table.getn(st.wheelHooked)
            hooks = ""
            local i, lim
            lim = hn
            if lim > 12 then lim = 12 end
            for i = 1, lim do
                if i > 1 then hooks = hooks .. "," end
                hooks = hooks .. st.wheelHooked[i]
            end
            if hn > lim then hooks = hooks .. ",+" .. (hn - lim) end
        end
        chat("mapdebug wheelhooks n=" .. tostring(hn) .. " " .. hooks)
        local lw = st.lastWheel
        if lw then
            chat("mapdebug lastwheel frame=" .. tostring(lw.frame)
                .. " mod=" .. tostring(lw.mod) .. " delta=" .. n(lw.delta))
        else
            chat("mapdebug lastwheel none")
        end
        local function dumpFr(tag, fr)
            if not fr then
                chat("mapdebug " .. tag .. " nil")
                return
            end
            local shown = "?"
            if fr.IsShown then shown = tostring(fr:IsShown()) end
            local pn = "nil"
            if fr.GetParent then
                local par = fr:GetParent()
                if par and par.GetName then pn = par:GetName() or "?" end
            end
            local p, rel, rp, x, y = getAnchor(fr)
            local rn = "nil"
            if rel then
                if rel.GetName then rn = rel:GetName() or "?" end
            end
            chat("mapdebug " .. tag
                .. " shown=" .. shown
                .. " w=" .. n(fr.GetWidth and fr:GetWidth())
                .. " h=" .. n(fr.GetHeight and fr:GetHeight())
                .. " scale=" .. n(fr.GetScale and fr:GetScale())
                .. " es=" .. n(fr.GetEffectiveScale and fr:GetEffectiveScale())
                .. " strata=" .. (fr.GetFrameStrata and tostring(fr:GetFrameStrata()) or "?")
                .. " parent=" .. pn
                .. " pt=" .. tostring(p) .. "/" .. rn .. "/" .. tostring(rp)
                .. " x=" .. n(x) .. " y=" .. n(y))
        end
        dumpFr("detail", WorldMapDetailFrame)
        dumpFr("button", WorldMapButton)
        dumpFr("scroll", WorldMapFrameScrollFrame)
        local child
        if WorldMapFrameScrollFrame and WorldMapFrameScrollFrame.GetScrollChild then
            child = WorldMapFrameScrollFrame:GetScrollChild()
        end
        dumpFr("scrollchild", child)
        dumpFr("guide", WorldMapPositioningGuide)
        dumpFr("dropLevel", getglobal("pfQuestMapLevelDropdown"))
        dumpFr("dropFilter", getglobal("ModernMapMarkersFilter_Blizz"))
        dumpFr("dropFind", getglobal("ModernMapMarkersFind_Blizz"))
        local zi = "?"
        if WorldMapFrameScrollFrame then zi = tostring(WorldMapFrameScrollFrame.zoomedIn) end
        local mf = magnifyFrame()
        local mfn = "nil"
        if mf then
            if mf.GetName then mfn = mf:GetName() or "?" else mfn = "?" end
        end
        chat("mapdebug magnifyFrame=" .. mfn
            .. " scale=" .. n(mf and mf.GetScale and mf:GetScale())
            .. " magzoom=" .. n(liveZoom())
            .. " magMin=" .. n(MAGNIFY_MIN_ZOOM)
            .. " magMax=" .. n(MAGNIFY_MAX_ZOOM)
            .. " magStep=" .. n(MAGNIFY_ZOOM_STEP)
            .. " zoomedIn=" .. zi)
        if WorldMapFrameScrollFrame then
            chat("mapdebug scrollHV h=" .. n(WorldMapFrameScrollFrame:GetHorizontalScroll())
                .. " v=" .. n(WorldMapFrameScrollFrame:GetVerticalScroll()))
        else
            chat("mapdebug scrollHV nil")
        end
        dumpFr("dropdown", getglobal("pfQuestMapDropdown") or pfQuestMapDropdown)
        local tile = getglobal("WorldMapDetailTile1")
        if not tile then
            chat("mapdebug tile1 nil")
        else
            local shown, alpha, tex, tw, th = "?", "?", "?", "?", "?"
            if tile.IsShown then shown = tostring(tile:IsShown()) end
            if tile.GetAlpha then alpha = n(tile:GetAlpha()) end
            if tile.GetTexture then tex = tostring(tile:GetTexture() or "") end
            if tex == "" then tex = "empty" end
            if tile.GetWidth then tw = n(tile:GetWidth()) end
            if tile.GetHeight then th = n(tile:GetHeight()) end
            chat("mapdebug tile1 shown=" .. shown
                .. " alpha=" .. alpha
                .. " tex=" .. tex
                .. " w=" .. tw .. " h=" .. th)
        end
    end

    -- Options > Map section. Helpers come from Options.lua; returns the next y.
    function IchaUI_WorldMapOptionsBlock(page, x, y, sectionHeader, makeButton, makeSliderRow, tip, slw, row, refreshList)
        sectionHeader(page, "World map", x, y); y = y - 20
        local onBtn = makeButton(page, "World map: On", 120, 20, function()
            IchaUI_WorldMap_Set("enabled", not db().enabled)
            if IchaUI_WorldMap_OptRefresh then IchaUI_WorldMap_OptRefresh() end
        end)
        onBtn:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
        local borderBtn = makeButton(page, "Gold border: On", 120, 20, function()
            IchaUI_WorldMap_Set("border", not db().border)
        end)
        borderBtn:SetPoint("LEFT", onBtn, "RIGHT", 4, 0)
        local resetBtn = makeButton(page, "Reset", 55, 20, function()
            IchaUI_WorldMap_Reset()
        end)
        resetBtn:SetPoint("LEFT", borderBtn, "RIGHT", 4, 0)
        y = y - row
        local scaleRow = makeSliderRow(page, "Map Scale", x, y, slw, SCALE_LO, SCALE_HI, 0.05,
            function() return clamp(db().scale, SCALE_LO, SCALE_HI) end,
            function(v) IchaUI_WorldMap_Set("scale", v) end)
        y = y - row
        local alphaRow = makeSliderRow(page, "Map Alpha", x, y, slw, ALPHA_LO, ALPHA_HI, 0.05,
            function() return clamp(db().alpha, ALPHA_LO, ALPHA_HI) end,
            function(v) IchaUI_WorldMap_Set("alpha", v) end)
        y = y - row
        local LV = {
            { "levels", "Level ranges", 108 }, { "levelInst", "Instances", 92 },
            { "levelRaids", "Raids", 72 }, { "levelPvP", "Faction", 76 }, { "levelFish", "Fishing", 76 },
        }
        local lvBtns = {}
        local i
        for i = 1, table.getn(LV) do
            local spec = LV[i]
            local b = makeButton(page, spec[2], spec[3], 20, function()
                IchaUI_WorldMap_Set(spec[1], not db()[spec[1]])
                if IchaUI_WorldMap_OptRefresh then IchaUI_WorldMap_OptRefresh() end
            end)
            if i == 1 then
                b:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
            else
                b:SetPoint("LEFT", lvBtns[i - 1], "RIGHT", 4, 0)
            end
            lvBtns[i] = b
        end
        y = y - row
        local note = tip(page, "", x, y, 520)
        y = y - 16
        local lvNote = tip(page, "", x, y, 520)
        y = y - 28

        local busy = false
        IchaUI_WorldMap_OptRefresh = function()
            if busy then return end
            busy = true
            local d = db()
            onBtn:SetText(d.enabled and "World map: On" or "World map: Off")
            borderBtn:SetText(d.border and "Gold border: On" or "Gold border: Off")
            if scaleRow and scaleRow.refresh then scaleRow.refresh() end
            if alphaRow and alphaRow.refresh then alphaRow.refresh() end
            local b = IchaUI_WorldMap_Blocked()
            if b == "shagu" then
                note:SetText("ShaguTweaks' WorldMap Window is on, so this one is idle. Turn it off in /st, then /reload.")
            elseif b == "addon" then
                note:SetText("Another map addon (Cartographer / MetaMap) owns the world map, so this one is idle.")
            else
                note:SetText("Drag the edge to move, the corner grip to resize. Ctrl + wheel scales, Shift + wheel fades, Esc closes.")
            end
            local j
            for j = 1, table.getn(LV) do
                lvBtns[j]:SetText(LV[j][2] .. (d[LV[j][1]] and ": On" or ": Off"))
            end
            if IchaUI_MapLevels_Blocked and IchaUI_MapLevels_Blocked() then
                lvNote:SetText("The LevelRange addon is loaded, so these are idle. Disable it in the AddOns list.")
            else
                lvNote:SetText("Level ranges: hover a zone on a continent map. Instances, raids, faction and fishing add lines.")
            end
            busy = false
        end
        if type(refreshList) == "table" then
            table.insert(refreshList, IchaUI_WorldMap_OptRefresh)
        end
        IchaUI_WorldMap_OptRefresh()
        return y
    end

    local boot = CreateFrame("Frame", "IchaUIWorldMapBoot")
    boot:RegisterEvent("PLAYER_ENTERING_WORLD")
    boot:SetScript("OnEvent", function()
        this:UnregisterAllEvents()
        -- One frame later, so every addon's PLAYER_ENTERING_WORLD layout has run.
        this:SetScript("OnUpdate", function()
            this:SetScript("OnUpdate", nil)
            this:Hide()
            st.ready = true
            sync()
            if IchaUI_WorldMap_OptRefresh then IchaUI_WorldMap_OptRefresh() end
        end)
        this:Show()
    end)
end

installIchaUIWorldMap()
