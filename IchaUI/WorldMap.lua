-- IchaUI WorldMap: the world map as a movable, scalable window (Lua 5.0 / 1.12).
-- <Ctrl> + mouse wheel scales it, <Shift> + mouse wheel changes its opacity,
-- plain mouse wheel zooms the map art, left-drag pans it while zoomed,
-- drag the frame edge to move it. Esc closes it. Settings live in IchaUIDB.worldmap.
--
-- Based on ShaguTweaks by Eric Mauser (Shagu), MIT License
-- (mods/worldmap-window.lua and the WorldMap part of mods/turtle-wow.lua).
-- Map zoom and pan follow Magnify by lookino, MIT License (main.lua).
--
-- Copyright (c) 2021 Eric Mauser (Shagu)
-- Copyright (c) 2026 lookino
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
    local FULL_MARGIN = 2

    -- Turtle's FrameXML geometry (WorldMapFrame.xml / WorldMapFrame.lua).
    -- Windowed: a 720x521 frame with the 1002x668 art at scale 0.7, TOPLEFT
    -- 15,-33 in art units. IchaUI keeps the art at scale 1 inside the same
    -- parchment border, whose pieces are fixed-size frame textures: fully
    -- opaque up to 12 / 25 / 7 / 33 units in from left / top / right /
    -- bottom. The margins put the art edge 2+ units under that opaque band.
    -- Fullscreen: the art sits at TOP -502,-69 of the 1024x768 positioning guide.
    local ART_W, ART_H = 1002, 668
    local TURTLE_WIN_W, TURTLE_WIN_H = 720, 521
    local STOCK_X, STOCK_Y = 15, -33
    local WIN_L, WIN_T, WIN_R, WIN_B = 10, 23, 5, 30
    local FULL_W, FULL_H = 1024, 768
    local ZOOM_MAX, ZOOM_STEP = 3, 0.25
    local PAN_SLOP = 3

    local st = {
        installed = false, active = false, blocked = nil,
        origToggle = nil, origPanel = nil, addedSpecial = false,
        border = nil, noticed = false,
    }
    -- Assigned later: dragStop/gripStop run before those local function lines.
    local raiseStrata, hookWheels, updateZoomLabel, ensureArt, repairCenter, hookMapRepair

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

    -- Magnify ships WorldMapFrameScrollFrame; when it is loaded it owns zoom
    -- and the art layout, and IchaUI only moves, scales and fades the window.
    local function magnifyLoaded()
        return WorldMapFrameScrollFrame ~= nil
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
        pcall(function()
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
        f:SetScale(s)
        local nes = f:GetEffectiveScale() or 1
        if nes <= 0 then nes = 1 end
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", g._left / nes, g._top / nes)
        if updateZoomLabel then updateZoomLabel() end
    end

    local function gripStop()
        local g = st.grip
        if not g or not g._sizing then return end
        g._sizing = nil
        g:SetScript("OnUpdate", nil)
        nudgeTitle()
        saveAnchor()
        if ensureArt then ensureArt() end
        if raiseStrata then raiseStrata() end
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

    -- Invisible title and edge hit-rects in the frame margin, outside the
    -- map viewport, so dragging works while the art covers WorldMapFrame.
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
        if st.edges then return end
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
        -- Sized to the frame margin so none of them covers the map art.
        local top = strip("IchaUIWorldMapDragTop", nil, 26)
        top:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 4)
        top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 4)
        local left = strip("IchaUIWorldMapDragLeft", 10, nil)
        left:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 10)
        local right = strip("IchaUIWorldMapDragRight", 5, nil)
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

    local function showChrome(on)
        if st.grip then
            if on then st.grip:Show() else st.grip:Hide() end
        end
        if st.edges then
            local i
            for i = 1, table.getn(st.edges) do
                if on then st.edges[i]:Show() else st.edges[i]:Hide() end
            end
        end
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
    -- Native map zoom (used when Magnify is not loaded).
    --
    --   WorldMapFrame
    --     IchaUIWorldMapViewport  ScrollFrame, 1002x668, at the stock art spot
    --       IchaUIWorldMapCanvas  scroll child, anchored to the viewport; its
    --                             scale is the zoom
    --         WorldMapDetailFrame TOPLEFT of the canvas, scale 1
    --         WorldMapButton      TOPLEFT of the detail frame, scale 1
    --     IchaUIWorldMapOverlay   same rect as the viewport, never scaled:
    --                             pfQuest / ModernMapMarkers dropdowns, zone label
    --
    -- Every frame in that chain always has a point on a sized frame, so
    -- WorldMapButton:GetCenter() never returns nil. Scroll offsets are in canvas
    -- units; 1.12 horizontal scroll is negative (as in Magnify).
    ------------------------------------------------------------------
    local zoom = { z = 1, h = 0, v = 0, pan = nil, moved = false, map = nil }
    local native = false

    local function winSize()
        return WIN_L + ART_W + WIN_R, WIN_T + ART_H + WIN_B
    end

    local function anchorViewport()
        local vp = zoom.vp
        vp:ClearAllPoints()
        if maximized() and WorldMapPositioningGuide then
            vp:SetPoint("TOPLEFT", WorldMapPositioningGuide, "TOP", -502, -69)
        else
            vp:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", WIN_L, -WIN_T)
        end
        vp:SetWidth(ART_W)
        vp:SetHeight(ART_H)
    end

    local function panLimits(z)
        local vw = zoom.vp:GetWidth() or ART_W
        local vh = zoom.vp:GetHeight() or ART_H
        if vw < 1 then vw = ART_W end
        if vh < 1 then vh = ART_H end
        local mx = ART_W - vw / z
        local my = ART_H - vh / z
        if mx < 0 then mx = 0 end
        if my < 0 then my = 0 end
        return mx, my
    end

    local function applyZoom()
        local z = clamp(zoom.z, 1, ZOOM_MAX)
        zoom.z = z
        local mx, my = panLimits(z)
        zoom.h = clamp(zoom.h, 0, mx)
        zoom.v = clamp(zoom.v, 0, my)
        local c = zoom.canvas
        if math.abs((c:GetScale() or 1) - z) > 0.0001 then c:SetScale(z) end
        zoom.vp:SetHorizontalScroll(-zoom.h)
        zoom.vp:SetVerticalScroll(zoom.v)
    end

    local function arrowModel()
        if zoom.model ~= nil then return zoom.model or nil end
        zoom.model = false
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
        local m = zoom.model
        if m then
            hookScript(m, "OnShow", function()
                if st.active and native and zoom.z > 1.001 then this:Hide() end
            end)
            return m
        end
        return nil
    end

    -- The client places its player arrow model in unzoomed units (Blizzard
    -- scales by WorldMapDetailFrame:GetScale(), which stays 1), and the model
    -- is not clipped. While zoomed, hide it and draw an arrow on WorldMapButton.
    local function updateArrow()
        local a = zoom.arrow
        if not a then return end
        if not st.active or zoom.z <= 1.001 then
            a:Hide()
            return
        end
        local px, py = GetPlayerMapPosition("player")
        if not px or (px == 0 and py == 0) then
            a:Hide()
            return
        end
        local b = WorldMapButton
        a:ClearAllPoints()
        a:SetPoint("CENTER", b, "TOPLEFT", px * (b:GetWidth() or ART_W), -py * (b:GetHeight() or ART_H))
        local size = 28 / zoom.z
        a.tex:SetWidth(size)
        a.tex:SetHeight(size)
        local m = arrowModel()
        if m and m.GetFacing then
            local r = m:GetFacing() or 0
            local s2 = math.sqrt(2)
            local q = math.pi / 4
            a.tex:SetTexCoord(
                0.5 + math.cos(r + 5 * q) / s2, 0.5 + math.sin(r + 5 * q) / s2,
                0.5 + math.cos(r + 3 * q) / s2, 0.5 + math.sin(r + 3 * q) / s2,
                0.5 + math.cos(r - q) / s2, 0.5 + math.sin(r - q) / s2,
                0.5 + math.cos(r + q) / s2, 0.5 + math.sin(r + q) / s2)
        end
        a:Show()
    end

    local function zoomChanged()
        local m = arrowModel()
        if m and zoom.z > 1.001 then m:Hide() end
        updateArrow()
        -- pfQuest-turtle sizes its continent pins from WorldMapButton's
        -- effective scale inside its WorldMapDetailFrame.SetScale hook.
        if WorldMapDetailFrame then WorldMapDetailFrame:SetScale(1) end
        if updateZoomLabel then updateZoomLabel() end
    end

    local function zoomReset()
        zoom.z, zoom.h, zoom.v = 1, 0, 0
        zoom.pan, zoom.moved = nil, false
        if native and zoom.vp then
            applyZoom()
            zoomChanged()
        end
    end

    local function zoomAt(delta)
        local vp = zoom.vp
        if not vp then return end
        local old = zoom.z
        local new = clamp(old + (tonumber(delta) or 0) * ZOOM_STEP, 1, ZOOM_MAX)
        if math.abs(new - old) < 0.001 then return end
        local left, top = vp:GetLeft(), vp:GetTop()
        if not left or not top then return end
        local es = vp:GetEffectiveScale() or 1
        if es <= 0 then es = 1 end
        local cx, cy = GetCursorPosition()
        local fx = clamp(cx / es - left, 0, vp:GetWidth() or ART_W)
        local fy = clamp(top - cy / es, 0, vp:GetHeight() or ART_H)
        local ox = zoom.h + fx / old
        local oy = zoom.v + fy / old
        zoom.z = new
        zoom.h = ox - fx / new
        zoom.v = oy - fy / new
        applyZoom()
        zoomChanged()
    end

    local function panStop()
        zoom.pan = nil
        if zoom.panTicker then zoom.panTicker:SetScript("OnUpdate", nil) end
    end

    local function panUpdate()
        local p = zoom.pan
        if not p then return panStop() end
        if not leftHeld() then return panStop() end
        local x, y = GetCursorPosition()
        if not zoom.moved and (math.abs(x - p.x) >= PAN_SLOP or math.abs(y - p.y) >= PAN_SLOP) then
            zoom.moved = true
        end
        if not zoom.moved then return end
        local es = zoom.canvas:GetEffectiveScale() or 1
        if es <= 0 then es = 1 end
        zoom.h = p.h + (p.x - x) / es
        zoom.v = p.v + (y - p.y) / es
        applyZoom()
        updateArrow()
    end

    local function panStart()
        zoom.moved = false
        zoom.pan = nil
        if not st.active or not native or zoom.z <= 1.001 then return end
        local x, y = GetCursorPosition()
        zoom.pan = { x = x, y = y, h = zoom.h, v = zoom.v }
        if not zoom.panTicker then zoom.panTicker = CreateFrame("Frame") end
        zoom.panTicker:SetScript("OnUpdate", panUpdate)
        zoom.panTicker:Show()
    end

    local DROP_NAMES = { "ModernMapMarkersFilter_Blizz", "ModernMapMarkersFind_Blizz" }

    local function hostDrop(f)
        if f:GetParent() ~= zoom.overlay then f:SetParent(zoom.overlay) end
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        local btn = f.GetName and f:GetName() and getglobal(f:GetName() .. "Button")
        if btn and btn.SetFrameStrata then btn:SetFrameStrata("FULLSCREEN_DIALOG") end
    end

    -- pfQuest parents its dropdown to WorldMapButton (TOPRIGHT 0,-10) and
    -- ModernMapMarkers copies that parent; the zone label is a WorldMapButton
    -- child too. All of them would zoom and clip, so they live on the overlay.
    local function placeDropdowns()
        local ov = zoom.overlay
        local dd = getglobal("pfQuestMapDropdown")
        if dd then
            hostDrop(dd)
            dd:ClearAllPoints()
            dd:SetPoint("TOPRIGHT", ov, "TOPRIGHT", 0, -10)
        end
        local lv = getglobal("pfQuestMapLevelDropdown")
        if lv then
            lv:SetFrameStrata("FULLSCREEN_DIALOG")
            local lb = getglobal("pfQuestMapLevelDropdownButton")
            if lb then lb:SetFrameStrata("FULLSCREEN_DIALOG") end
        end
        local i
        for i = 1, table.getn(DROP_NAMES) do
            local f = getglobal(DROP_NAMES[i])
            if f then
                local par = f:GetParent()
                if par == WorldMapButton or par == ov then
                    zoom.hosted = zoom.hosted or {}
                    zoom.hosted[DROP_NAMES[i]] = true
                    hostDrop(f)
                end
            end
        end
        local area = WorldMapFrameAreaFrame
        if area then
            if area:GetParent() ~= ov then area:SetParent(ov) end
            area:ClearAllPoints()
            area:SetPoint("TOP", ov, "TOP", 0, -10)
        end
    end

    local function setupNative()
        if zoom.vp then return end
        local vp = CreateFrame("ScrollFrame", "IchaUIWorldMapViewport", WorldMapFrame)
        vp:SetWidth(ART_W)
        vp:SetHeight(ART_H)
        vp:EnableMouse(false)
        zoom.vp = vp
        anchorViewport()
        local c = CreateFrame("Frame", "IchaUIWorldMapCanvas", vp)
        c:SetWidth(ART_W)
        c:SetHeight(ART_H)
        c:SetPoint("TOPLEFT", vp, "TOPLEFT", 0, 0)
        vp:SetScrollChild(c)
        zoom.canvas = c

        local ov = CreateFrame("Frame", "IchaUIWorldMapOverlay", WorldMapFrame)
        ov:SetAllPoints(vp)
        ov:EnableMouse(false)
        ov:SetFrameStrata("FULLSCREEN_DIALOG")
        zoom.overlay = ov

        -- Keep the stock stacking: pins were leveled off WorldMapButton's level.
        zoom.lvDetail = WorldMapDetailFrame:GetFrameLevel()
        zoom.lvButton = WorldMapButton:GetFrameLevel()
        vp:SetFrameLevel(zoom.lvDetail)
        c:SetFrameLevel(zoom.lvDetail)

        local a = CreateFrame("Frame", "IchaUIWorldMapArrow", WorldMapButton)
        a:SetWidth(1)
        a:SetHeight(1)
        a:SetFrameLevel((WorldMapButton:GetFrameLevel() or 1) + 8)
        a.tex = a:CreateTexture(nil, "OVERLAY")
        a.tex:SetTexture("Interface\\Minimap\\MinimapArrow")
        a.tex:SetPoint("CENTER", a, "CENTER", 0, 0)
        a:Hide()
        zoom.arrow = a

        hookScript(WorldMapButton, "OnMouseDown", function()
            if arg1 == "LeftButton" then panStart() end
        end)
        -- WorldMapButton clicks run from OnMouseUp (WorldMapButton_OnClick).
        -- A pan ends there and must not also click into a zone.
        local prevUp = WorldMapButton:GetScript("OnMouseUp")
        WorldMapButton:SetScript("OnMouseUp", function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            dragStop(true)
            local moved = zoom.moved
            panStop()
            zoom.moved = false
            if moved and st.active then return end
            if prevUp then prevUp(a1, a2, a3, a4, a5, a6, a7, a8, a9) end
        end)
        -- OnUpdate is wrapped in hookMapRepair so GetCenter() is repaired
        -- before Turtle's WorldMapButton_OnUpdate (FrameXML ~493) can crash.
        hookScript(WorldMapFrame, "OnHide", zoomReset)

        local ev = CreateFrame("Frame")
        ev:RegisterEvent("WORLD_MAP_UPDATE")
        ev:SetScript("OnEvent", function()
            if st.active and repairCenter then repairCenter() end
            local id = tostring(GetCurrentMapContinent and GetCurrentMapContinent() or 0) .. ":"
                .. tostring(GetCurrentMapZone and GetCurrentMapZone() or 0)
            if id ~= zoom.map then
                zoom.map = id
                if st.active then zoomReset() end
            end
        end)
    end

    local function pointIs(f, p, rel, rp)
        local ok, fp, frel, frp, fx, fy = pcall(f.GetPoint, f, 1)
        if not ok or fp ~= p or frel ~= rel or frp ~= rp then return false end
        if math.abs(fx or 0) > 0.01 or math.abs(fy or 0) > 0.01 then return false end
        if f.GetNumPoints and f:GetNumPoints() ~= 1 then return false end
        return true
    end

    -- True when something (Turtle's Minimize/Maximize, another addon) moved,
    -- rescaled or reparented a frame in the viewport chain.
    local function artDrifted()
        local c, df, b = zoom.canvas, WorldMapDetailFrame, WorldMapButton
        if df:GetParent() ~= c or b:GetParent() ~= c then return true end
        if math.abs((df:GetScale() or 1) - 1) > 0.001 then return true end
        if math.abs((b:GetScale() or 1) - 1) > 0.001 then return true end
        if math.abs((c:GetScale() or 1) - zoom.z) > 0.001 then return true end
        if not pointIs(df, "TOPLEFT", c, "TOPLEFT") then return true end
        if not pointIs(b, "TOPLEFT", df, "TOPLEFT") then return true end
        local dd = getglobal("pfQuestMapDropdown")
        if dd and dd:GetParent() ~= zoom.overlay then return true end
        if not b:GetCenter() then return true end
        return false
    end

    -- Idempotent: puts the whole viewport chain back. Each ClearAllPoints is
    -- followed at once by a point on a sized frame.
    ensureArt = function(onlyIfDrifted)
        if not native or not zoom.vp or not st.active then return end
        if onlyIfDrifted and not artDrifted() then return end
        local vp, c, df, b = zoom.vp, zoom.canvas, WorldMapDetailFrame, WorldMapButton
        anchorViewport()
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", vp, "TOPLEFT", 0, 0)
        c:SetWidth(ART_W)
        c:SetHeight(ART_H)
        vp:SetScrollChild(c)
        if df:GetParent() ~= c then df:SetParent(c) end
        if math.abs((df:GetScale() or 1) - 1) > 0.001 then df:SetScale(1) end
        df:SetWidth(ART_W)
        df:SetHeight(ART_H)
        df:ClearAllPoints()
        df:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
        if b:GetParent() ~= c then b:SetParent(c) end
        if math.abs((b:GetScale() or 1) - 1) > 0.001 then b:SetScale(1) end
        b:SetWidth(ART_W)
        b:SetHeight(ART_H)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", df, "TOPLEFT", 0, 0)
        if zoom.lvDetail and df:GetFrameLevel() ~= zoom.lvDetail then df:SetFrameLevel(zoom.lvDetail) end
        if zoom.lvButton and b:GetFrameLevel() ~= zoom.lvButton then b:SetFrameLevel(zoom.lvButton) end
        vp:Show()
        c:Show()
        zoom.overlay:Show()
        applyZoom()
        placeDropdowns()
    end

    -- pfQuest /db object|unit|track calls pfMap:ShowMapID, which ToggleWorldMap
    -- (or SetMapZoom if the map is already open) and attaches pins on that
    -- same frame. Turtle WorldMapButton_OnUpdate then does arithmetic on
    -- GetCenter(); a missing point or size makes centerY nil. The 0.25s
    -- drift pass is too late, so repair before that math runs.
    repairCenter = function()
        if not st.active or not WorldMapButton then return false end
        if WorldMapButton:GetCenter() then return true end
        if WorldMapFrame and WorldMapFrame.IsVisible and not WorldMapFrame:IsVisible() then
            return false
        end
        if not maximized() then applyAnchor() end
        if native and ensureArt then ensureArt() end
        return WorldMapButton:GetCenter() ~= nil
    end

    local function wrapButtonOnUpdate()
        if not WorldMapButton or not WorldMapButton.GetScript then return end
        local cur = WorldMapButton:GetScript("OnUpdate")
        if cur and cur == zoom.guardUpdate then return end
        zoom.innerUpdate = cur
        if not zoom.guardUpdate then
            local acc = 0
            zoom.guardUpdate = function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
                if st.active then
                    if not WorldMapButton:GetCenter() then
                        if repairCenter then repairCenter() end
                    end
                    if not WorldMapButton:GetCenter() then
                        updateArrow()
                        return
                    end
                end
                local inner = zoom.innerUpdate
                if inner then inner(a1, a2, a3, a4, a5, a6, a7, a8, a9) end
                if not st.active then return end
                updateArrow()
                acc = acc + (arg1 or 0)
                if acc < 0.25 then return end
                acc = 0
                if ensureArt then ensureArt(true) end
            end
        end
        WorldMapButton:SetScript("OnUpdate", zoom.guardUpdate)
    end

    local function wrapButtonOnUpdateFn()
        if st.wrappedOnUpdateFn or type(WorldMapButton_OnUpdate) ~= "function" then return end
        st.wrappedOnUpdateFn = true
        local orig = WorldMapButton_OnUpdate
        WorldMapButton_OnUpdate = function(elapsed)
            if st.active and WorldMapButton and not WorldMapButton:GetCenter() then
                if repairCenter then repairCenter() end
                if not WorldMapButton:GetCenter() then return end
            end
            return orig(elapsed)
        end
    end

    local function hookSetMapZoom()
        if st.hookedZoom or type(SetMapZoom) ~= "function" then return end
        st.hookedZoom = true
        local orig = SetMapZoom
        SetMapZoom = function(a1, a2, a3, a4, a5)
            orig(a1, a2, a3, a4, a5)
            if repairCenter then repairCenter() end
        end
    end

    local function hookPfQuestTrack()
        if type(pfMap) ~= "table" then return end
        if not st.hookedShowMap and type(pfMap.ShowMapID) == "function" then
            st.hookedShowMap = true
            local orig = pfMap.ShowMapID
            pfMap.ShowMapID = function(self, map)
                local r = orig(self, map)
                if repairCenter then repairCenter() end
                return r
            end
        end
        if not st.hookedSetMap and type(pfMap.SetMapByID) == "function" then
            st.hookedSetMap = true
            local orig = pfMap.SetMapByID
            pfMap.SetMapByID = function(self, id)
                orig(self, id)
                if repairCenter then repairCenter() end
            end
        end
    end

    hookMapRepair = function()
        wrapButtonOnUpdate()
        wrapButtonOnUpdateFn()
        hookSetMapZoom()
        hookPfQuestTrack()
    end

    -- Back to Turtle's stock art layout (IchaUI map switched off).
    local function restoreArt()
        if not native or not zoom.vp then return end
        zoom.z, zoom.h, zoom.v = 1, 0, 0
        panStop()
        if zoom.arrow then zoom.arrow:Hide() end
        local df, b = WorldMapDetailFrame, WorldMapButton
        local ws = 1
        if not maximized() then ws = tonumber(WORLDMAP_WINDOWED_SCALE) or 0.7 end
        df:SetParent(WorldMapFrame)
        df:SetScale(ws)
        df:ClearAllPoints()
        if maximized() then
            df:SetPoint("TOPLEFT", WorldMapPositioningGuide, "TOP", -502, -69)
        else
            df:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", STOCK_X, STOCK_Y)
        end
        b:SetParent(WorldMapFrame)
        b:SetScale(ws)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", df, "TOPLEFT", 0, 0)
        if zoom.lvDetail then df:SetFrameLevel(zoom.lvDetail) end
        if zoom.lvButton then b:SetFrameLevel(zoom.lvButton) end
        local dd = getglobal("pfQuestMapDropdown")
        if dd then
            dd:SetParent(b)
            dd:ClearAllPoints()
            dd:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, -10)
        end
        if zoom.hosted then
            local name
            for name in pairs(zoom.hosted) do
                local f = getglobal(name)
                if f then f:SetParent(b) end
            end
        end
        local area = WorldMapFrameAreaFrame
        if area then
            area:SetParent(b)
            area:ClearAllPoints()
            area:SetPoint("TOP", b, "TOP", 0, -10)
        end
        zoom.vp:Hide()
        zoom.overlay:Hide()
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

    -- 1.12 sends the wheel to the topmost wheel-enabled frame under the cursor.
    -- A fixed set of map frames is routed: Ctrl/Shift are the window's,
    -- plain wheel zooms. Each frame is wrapped once.
    local wheelWrap = {}
    local function wrapWheel(f)
        if not f or not f.GetScript then return end
        local name = "?"
        if f.GetName then name = f:GetName() or "?" end
        local cur = f:GetScript("OnMouseWheel")
        if cur and cur == wheelWrap[f] then
            if f.EnableMouseWheel then f:EnableMouseWheel(1) end
            return
        end
        local prev = cur
        local isMagnify = WorldMapFrameScrollFrame and f == WorldMapFrameScrollFrame
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
            if st.active and native then
                zoomAt(arg1)
            elseif isMagnify and prev then
                prev(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            elseif st.active and magnifyLoaded() then
                runMagnifyWheel()
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
        local names = {}
        local function add(f)
            if not f then return end
            wrapWheel(f)
            table.insert(names, (f.GetName and f:GetName()) or "?")
        end
        add(WorldMapFrame)
        add(WorldMapPositioningGuide)
        add(WorldMapDetailFrame)
        add(WorldMapButton)
        add(WorldMapFrameScrollFrame)
        add(zoom.vp)
        add(zoom.canvas)
        add(st.grip)
        if st.edges then
            local i
            for i = 1, table.getn(st.edges) do add(st.edges[i]) end
        end
        st.wheelHooked = names
    end

    -- FULLSCREEN keeps the map above the HUD but under dropdowns, the config
    -- panel and tooltips. 1.12 does not reliably carry a strata change down to
    -- existing children, so each child below it is set too; children already
    -- higher (the overlay dropdowns, the level tooltip) keep theirs.
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
        -- Leave scroll children alone: they follow their clip frame.
        if fr == WorldMapFrameScrollFrame then return end
        if zoom.vp and fr == zoom.vp then return end
        if WorldMapFrameScrollFrame and fr == WorldMapDetailFrame then return end
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

    local function setTree(fr, strata, saved)
        if not fr or not fr.SetFrameStrata then return end
        if saved[fr] == nil then saved[fr] = fr:GetFrameStrata() or false end
        fr:SetFrameStrata(strata)
        if not fr.GetChildren then return end
        local kids = { fr:GetChildren() }
        local i
        for i = 1, table.getn(kids) do setTree(kids[i], strata, saved) end
    end

    -- The art sits in the canvas at higher levels than WorldMapFrame's own
    -- children, so the map's controls go one strata above it.
    local WIDGET_NAMES = {
        "WorldMapContinentDropDown", "WorldMapZoneDropDown",
        "WorldMapZoomOutButton", "WorldMapMagnifyingGlassButton",
        "ModernMapMarkersFind_Panel",
    }

    local function raiseWidgets()
        local i
        for i = 1, table.getn(WIDGET_NAMES) do
            local w = getglobal(WIDGET_NAMES[i])
            if w then setTree(w, "FULLSCREEN_DIALOG", st.strataSaved) end
        end
    end

    -- DropDownList1..n are shared by the whole UI. While the map is shown
    -- an opened list goes to TOOLTIP; it is put back when it hides.
    local function hookMenuLists()
        if st.listsHooked then return end
        local n = tonumber(UIDROPDOWNMENU_MAXLEVELS) or 3
        local i
        for i = 1, n do
            local l = getglobal("DropDownList" .. i)
            if l then
                st.listsHooked = true
                hookScript(l, "OnShow", function()
                    if not (st.active and WorldMapFrame and WorldMapFrame:IsVisible()) then return end
                    this.ichaSaved = this.ichaSaved or {}
                    setTree(this, "TOOLTIP", this.ichaSaved)
                end)
                hookScript(l, "OnHide", function()
                    local saved = this.ichaSaved
                    if not saved then return end
                    this.ichaSaved = nil
                    local fr, old
                    for fr, old in pairs(saved) do
                        if old then fr:SetFrameStrata(old) end
                    end
                end)
            end
        end
    end

    raiseStrata = function()
        local f = WorldMapFrame
        if not f or not f.SetFrameStrata then return end
        if st.origStrata == nil then st.origStrata = f:GetFrameStrata() or false end
        st.strataSaved = st.strataSaved or {}
        -- Always walk children. Turtle maximize/minimize can drop kids back
        -- to MEDIUM while the parent stays FULLSCREEN.
        local high = highKids(f, {})
        liftStrata(f)
        keepHigh(high)
        raiseWidgets()
        hookMenuLists()
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
            local bes = es
            if b.GetEffectiveScale then bes = b:GetEffectiveScale() or es end
            if b.GetTop and b:GetTop() then
                local bt = b:GetTop() * bes
                if bt > top then top = bt end
            end
            if b.GetBottom and b:GetBottom() then
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

    -- Turtle's 1024x768 fullscreen chrome, fit to the measured screen height.
    -- Never writes IchaUIDB.
    local function layoutMaximized()
        local f = WorldMapFrame
        f:SetWidth(FULL_W)
        f:SetHeight(FULL_H)
        if TargetHPText and WorldMapFrameTitle then
            WorldMapFrameTitle:SetPoint("TOP", f, 0, 17)
        end
        f:SetScale(1)
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        local s = computeFullScale()
        if not s or s < 0.1 then s = 1 end
        st.fullScale = s
        f:SetScale(s)
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
    end

    local function layoutWindowed()
        local f = WorldMapFrame
        if native then
            local w, h = winSize()
            f:SetWidth(w)
            f:SetHeight(h)
        end
        f:SetScale(db().scale)
        applyAnchor()
        if nudgeTitle() then saveAnchor() end
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
        st.zoomInfo = z
        return z
    end

    local function mapZoom()
        if native then return zoom.z end
        local z = WorldMapDetailFrame and WorldMapDetailFrame:GetScale() or 1
        local base = 1
        if not maximized() and MAGNIFY_MIN_ZOOM then base = MAGNIFY_MIN_ZOOM end
        if base <= 0 then base = 1 end
        return z / base
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
        local pct = math.floor((tonumber(db().scale) or 1) * 100 + 0.5)
        z.text:SetText(string.format("Zoom %.1fx   %d%%", mapZoom(), pct))
        z:Show()
    end

    -- Full layout for the current mode. Safe on every show and after
    -- Turtle's Minimize / Maximize.
    local function layout()
        if not st.active then return end
        local d = db()
        local f = WorldMapFrame
        f:SetMovable(true)
        f:EnableMouse(true)
        f:EnableKeyboard(false)
        if f.SetClampedToScreen then f:SetClampedToScreen(false) end
        d.scale = scaleFor(d.scale)
        f:SetAlpha(clamp(d.alpha, ALPHA_LO, ALPHA_HI))
        if BlackoutWorld then BlackoutWorld:Hide() end
        paintBorder()
        ensureGrip()
        ensureEdges()
        ensureZoomInfo()
        local mode = maximized() and "full" or "win"
        if st.mode ~= mode then
            st.mode = mode
            zoomReset()
        end
        if maximized() then
            layoutMaximized()
            showChrome(false)
        else
            layoutWindowed()
            showChrome(true)
        end
        ensureArt()
        if hookMapRepair then hookMapRepair() end
        hookWheels()
        raiseStrata()
        updateZoomLabel()
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
        native = not magnifyLoaded()

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
                if repairCenter then repairCenter() end
            end
        end

        if native then setupNative() end
        if hookMapRepair then hookMapRepair() end
        -- Turtle's Minimize/Maximize rescale and re-point the detail frame and
        -- WorldMapButton; layout() takes them back into the viewport.
        if type(WorldMapFrame_Maximize) == "function" then
            local oldMax = WorldMapFrame_Maximize
            WorldMapFrame_Maximize = function(a1, a2, a3)
                oldMax(a1, a2, a3)
                layout()
            end
        end
        if type(WorldMapFrame_Minimize) == "function" then
            local oldMin = WorldMapFrame_Minimize
            WorldMapFrame_Minimize = function(a1, a2, a3)
                oldMin(a1, a2, a3)
                layout()
            end
        end

        hookScript(f, "OnShow", layout)
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
        st.mode = nil
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
            layout()
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
        restoreArt()
        if f.SetClampedToScreen then f:SetClampedToScreen(st.origClamp and true or false) end
        f:SetScale(1)
        f:SetAlpha(1)
        f:EnableKeyboard(true)
        if maximized() then
            f:ClearAllPoints()
            f:SetAllPoints(UIParent)
            if BlackoutWorld then BlackoutWorld:Show() end
        else
            f:SetWidth(TURTLE_WIN_W)
            f:SetHeight(TURTLE_WIN_H)
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
        end
        paintBorder()
        showChrome(false)
        if st.zoomInfo then st.zoomInfo:Hide() end
        restoreStrata()
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
            if st.active then layout() else activate() end
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

    -- The map viewport frame (clip rect of the art), or nil.
    function IchaUI_WorldMap_Viewport()
        if st.active and native and zoom.vp and zoom.vp:IsShown() then return zoom.vp end
        return nil
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
                WorldMapFrame:SetScale(d.scale)
                if nudgeTitle() then saveAnchor() end
                ensureArt()
                raiseStrata()
            end
            if updateZoomLabel then updateZoomLabel() end
        elseif key == "alpha" then
            d.alpha = clamp(value, ALPHA_LO, ALPHA_HI)
            if st.active and WorldMapFrame then WorldMapFrame:SetAlpha(d.alpha) end
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
        layout()
        if IchaUI_WorldMap_OptRefresh then IchaUI_WorldMap_OptRefresh() end
    end

    function IchaUI_WorldMap_Reload()
        if st.ready then sync() end
        if IchaUI_MapLevels_Refresh then IchaUI_MapLevels_Refresh() end
    end

    -- /icha mapdebug: one line per frame, compact enough for a screenshot.
    function IchaUI_WorldMap_Debug()
        local function n(v)
            if v == nil then return "nil" end
            local num = tonumber(v)
            if not num then return tostring(v) end
            return string.format("%.1f", num)
        end
        local function nm(fr)
            if not fr then return "nil" end
            if fr.GetName then return fr:GetName() or "?" end
            return "?"
        end
        local function pt(fr)
            local p, rel, rp, x, y = getAnchor(fr)
            if not p then return "NOPOINT" end
            local np = ""
            if fr.GetNumPoints then np = "#" .. tostring(fr:GetNumPoints()) end
            return p .. ">" .. nm(rel) .. "." .. tostring(rp) .. "(" .. n(x) .. "," .. n(y) .. ")" .. np
        end
        local function fr(tag, f)
            if not f then
                chat("|cffffd200" .. tag .. "|r nil")
                return
            end
            local cx, cy = f:GetCenter()
            local es = f:GetEffectiveScale() or 1
            local c = "nil"
            if cx then c = n(cx * es) .. "," .. n(cy * es) end
            chat("|cffffd200" .. tag .. "|r " .. n(f:GetWidth()) .. "x" .. n(f:GetHeight())
                .. " s" .. string.format("%.2f", f:GetScale() or 0) .. " es" .. string.format("%.2f", es)
                .. " c=" .. c .. " par=" .. nm(f:GetParent()) .. " " .. pt(f)
                .. (f:IsShown() and "" or " HIDDEN"))
        end
        local f = WorldMapFrame
        local d = db()
        chat("|cffffd200map|r " .. (maximized() and "FULL" or "WIN") .. " W=" .. tostring(WORLDMAP_WINDOWED)
            .. " active=" .. tostring(st.active) .. " native=" .. tostring(native)
            .. " Magnify=" .. (magnifyLoaded() and "yes" or "no")
            .. " zoom=" .. string.format("%.2f", mapZoom()) .. " pan=" .. n(zoom.h) .. "," .. n(zoom.v)
            .. " scale=" .. n(d.scale) .. " full=" .. n(st.fullScale))
        fr("frame", f)
        fr("viewport", zoom.vp)
        if zoom.vp then
            chat("|cffffd200scroll|r h=" .. n(zoom.vp:GetHorizontalScroll()) .. " v=" .. n(zoom.vp:GetVerticalScroll())
                .. " canvas s" .. string.format("%.2f", zoom.canvas:GetScale() or 0)
                .. " " .. pt(zoom.canvas))
        end
        fr("detail", WorldMapDetailFrame)
        fr("button", WorldMapButton)
        if WorldMapFrameScrollFrame then fr("magnify", WorldMapFrameScrollFrame) end
        local drops = { "pfQuestMapDropdown", "pfQuestMapLevelDropdown",
            "ModernMapMarkersFilter_Blizz", "ModernMapMarkersFind_Blizz" }
        local i
        for i = 1, table.getn(drops) do
            local dd = getglobal(drops[i])
            if dd then
                local r, t = dd:GetRight(), dd:GetTop()
                local es = dd:GetEffectiveScale() or 1
                local tr = "nil"
                if r and t then tr = n(r * es) .. "," .. n(t * es) end
                chat("|cffffd200" .. drops[i] .. "|r par=" .. nm(dd:GetParent()) .. " " .. pt(dd)
                    .. " TR=" .. tr .. " " .. tostring(dd:GetFrameStrata()))
            end
        end
        local function strata(name)
            local f = getglobal(name)
            return (f and f.GetFrameStrata and f:GetFrameStrata()) or "-"
        end
        chat("|cffffd200menus|r continent=" .. strata("WorldMapContinentDropDown")
            .. " zone=" .. strata("WorldMapZoneDropDown")
            .. " list1=" .. strata("DropDownList1")
            .. " hooked=" .. tostring(st.listsHooked and true or false))
        local lw = st.lastWheel
        chat("|cffffd200wheel|r n=" .. tostring(st.wheelHooked and table.getn(st.wheelHooked) or 0)
            .. (lw and (" last=" .. tostring(lw.frame) .. "/" .. tostring(lw.mod) .. "/" .. n(lw.delta)) or " last=none"))
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
                note:SetText("Drag the edge to move, the corner grip to resize. Wheel zooms, drag pans, Ctrl + wheel scales, Shift + wheel fades.")
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
