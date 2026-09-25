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
        local p, rel, rp, x, y = getAnchor(WorldMapFrame)
        if not p then return end
        local d = db()
        d.point, d.relPoint = p, rp or p
        d.x, d.y = round2(x), round2(y)
    end

    -- Measured pixel edges. No GetWidth, no saved scale.
    local function nudgeTitle()
        local f = WorldMapFrame
        if f._ichaMoving then return false end
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
        if not st.active then return end
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
        s = scaleFor(s)
        db().scale = s
        f:SetScale(s)
        local nes = f:GetEffectiveScale() or 1
        if nes <= 0 then nes = 1 end
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", g._left / nes, g._top / nes)
    end

    local function gripStop()
        local g = st.grip
        if not g or not g._sizing then return end
        g._sizing = nil
        g:SetScript("OnUpdate", nil)
        nudgeTitle()
        saveAnchor()
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
            if not st.active then return end
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
        local df = WorldMapDetailFrame
        if not zoom.frame or zoom.attached or not df or not df.GetPoint then return end
        local p, rel, rp, x, y = df:GetPoint(1)
        local zf = zoom.frame
        zf:ClearAllPoints()
        zf:SetPoint(p or "TOP", rel or WorldMapFrame, rp or p or "TOP", x or 0, y or 0)
        zf:SetWidth(df:GetWidth() or 1002)
        zf:SetHeight(df:GetHeight() or 668)
        zoom.parent = df:GetParent()
        zoom.points = { p, rel, rp, x, y }
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
        local sf = WorldMapFrameScrollFrame
        if sf and st.magnifyWheel then
            local o = this
            this = sf
            st.magnifyWheel()
            this = o
            return
        end
        zoomAt(arg1)
    end

    -- The wheel goes to the top frame under the cursor that takes it: Magnify's
    -- scroll frame, WorldMapButton (if it ends up on top) or the window edge.
    -- Chain each one: Ctrl/Shift are ours, plain wheel zooms.
    local wheelWrap = {}
    local function wrapWheel(f, isMagnify)
        if not f or not f.GetScript then return end
        local cur = f:GetScript("OnMouseWheel")
        if cur and cur == wheelWrap[f] then return end
        local prev = cur
        if isMagnify then st.magnifyWheel = prev end
        local w = function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            if wheelStep() then return end
            if st.active and not isMagnify then
                zoomWheel()
            elseif prev then
                prev(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            end
        end
        wheelWrap[f] = w
        f:SetScript("OnMouseWheel", w)
        if not isMagnify and f.EnableMouseWheel then f:EnableMouseWheel(1) end
    end

    local function hookWheels()
        wrapWheel(WorldMapFrame, false)
        wrapWheel(WorldMapButton, false)
        if WorldMapFrameScrollFrame then wrapWheel(WorldMapFrameScrollFrame, true) end
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

    local function raiseStrata()
        local f = WorldMapFrame
        if not f.SetFrameStrata then return end
        if st.origStrata == nil then st.origStrata = f:GetFrameStrata() or false end
        st.strataSaved = st.strataSaved or {}
        if st.strataDone and f:GetFrameStrata() == MAP_STRATA then return end
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
        f:SetScale(d.scale)
        f:SetAlpha(clamp(d.alpha, ALPHA_LO, ALPHA_HI))
        applyAnchor()
        if nudgeTitle() then saveAnchor() end
        if BlackoutWorld then BlackoutWorld:Hide() end
        paintBorder()
        hookWheels()
        hookRelease(WorldMapButton)
        if WorldMapFrameScrollFrame then hookRelease(WorldMapFrameScrollFrame) end
        if Magnify_ResetZoom and WorldMapFrameScrollFrame then
            WorldMapFrameScrollFrame:SetPoint("TOP", f, 0, -36)
        end
        ensureGrip():Show()
        ensureEdges()
    end

    -- Turtle's WorldMapFrame_Maximize rebuilds the fullscreen layout; size the
    -- window first, then applyAnchor + a measured title nudge.
    local function applyFull()
        if not st.active then return end
        local f = WorldMapFrame
        if maximized() then
            f:ClearAllPoints()
            f:SetWidth(WorldMapButton:GetWidth() + 15)
            f:SetHeight(WorldMapButton:GetHeight() + 55)
            if TargetHPText and WorldMapFrameTitle then
                WorldMapFrameTitle:SetPoint("TOP", f, 0, 17)
            end
            zoomAttach()
        end
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
                zoomDetach()
                oldMax(a1, a2, a3)
                applyFull()
            end
        end
        if type(WorldMapFrame_Minimize) == "function" then
            local oldMin = WorldMapFrame_Minimize
            WorldMapFrame_Minimize = function(a1, a2, a3)
                zoomDetach()
                oldMin(a1, a2, a3)
                applyLight()
            end
        end

        hookScript(f, "OnShow", function()
            applyLight()
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
            if st.active and WorldMapFrame then
                WorldMapFrame:SetScale(d.scale)
                if nudgeTitle() then saveAnchor() end
            end
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
            chat("mapdebug UIParent scale=" .. n(UIParent:GetEffectiveScale and UIParent:GetEffectiveScale())
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
            .. " maximized=" .. tostring(maximized()))
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
