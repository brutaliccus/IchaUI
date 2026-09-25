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

    local function place()
        local d = db()
        local f = WorldMapFrame
        f:ClearAllPoints()
        f:SetPoint(d.point or "CENTER", UIParent, d.relPoint or "CENTER", tonumber(d.x) or 0, tonumber(d.y) or 0)
    end

    -- Save as a CENTER offset in the map's own scale so rescaling keeps it centered.
    local function savePos()
        local f = WorldMapFrame
        local cx, cy = f:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if not cx or not ux then return end
        local fs = f:GetEffectiveScale() or 1
        local us = UIParent:GetEffectiveScale() or 1
        if fs <= 0 then fs = 1 end
        local k = us / fs
        local d = db()
        d.point = "CENTER"
        d.relPoint = "CENTER"
        d.x = cx - ux * k
        d.y = cy - uy * k
        place()
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
        local ps = UIParent:GetEffectiveScale() or 1
        local w = (f:GetWidth() or 0) * ps
        local h = (f:GetHeight() or 0) * ps
        if w <= 0 or h <= 0 then return end
        local s = (cx - g._left) / w
        local sh = (g._top - cy) / h
        if sh > s then s = sh end
        s = clamp(s, SCALE_LO, SCALE_HI)
        db().scale = s
        f:SetScale(s)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", g._left / (s * ps), g._top / (s * ps))
    end

    local function gripStop()
        local g = st.grip
        if not g or not g._sizing then return end
        g._sizing = nil
        g:SetScript("OnUpdate", nil)
        savePos()
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

    -- The wheel goes to the top frame under the cursor that takes it, which over the
    -- map is Magnify's scroll frame (or WorldMapButton), not WorldMapFrame. Chain each
    -- one: modified wheel is ours, plain wheel runs the previous script (Magnify zoom).
    local wheelWrap = {}
    local function wrapWheel(f, enable)
        if not f or not f.GetScript then return end
        local cur = f:GetScript("OnMouseWheel")
        if cur and cur == wheelWrap[f] then return end
        local prev = cur
        local w = function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
            if wheelStep() then return end
            if prev then prev(a1, a2, a3, a4, a5, a6, a7, a8, a9) end
        end
        wheelWrap[f] = w
        f:SetScript("OnMouseWheel", w)
        if enable and f.EnableMouseWheel then f:EnableMouseWheel(1) end
    end

    local function hookWheels()
        wrapWheel(WorldMapFrame, true)
        if WorldMapFrameScrollFrame then
            wrapWheel(WorldMapFrameScrollFrame, false)
        else
            wrapWheel(WorldMapButton, true)
        end
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
        f:SetScale(clamp(d.scale, SCALE_LO, SCALE_HI))
        f:SetAlpha(clamp(d.alpha, ALPHA_LO, ALPHA_HI))
        place()
        if BlackoutWorld then BlackoutWorld:Hide() end
        paintBorder()
        hookWheels()
        ensureGrip():Show()
    end

    -- Turtle's WorldMapFrame_Maximize rebuilds the fullscreen layout; resize after it.
    local function applyFull()
        if not st.active then return end
        applyLight()
        if not maximized() then return end
        local f = WorldMapFrame
        f:SetWidth(WorldMapButton:GetWidth() + 15)
        f:SetHeight(WorldMapButton:GetHeight() + 55)
        if TargetHPText and WorldMapFrameTitle then
            WorldMapFrameTitle:SetPoint("TOP", f, 0, 17)
        end
        -- Magnify keeps its scroll frame at -70 unless ShaguTweaks' window is on.
        if Magnify_ResetZoom and WorldMapFrameScrollFrame then
            WorldMapFrameScrollFrame:SetPoint("TOP", f, 0, -48)
        end
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

        if type(WorldMapFrame_Maximize) == "function" then
            local oldMax = WorldMapFrame_Maximize
            WorldMapFrame_Maximize = function(a1, a2, a3)
                oldMax(a1, a2, a3)
                applyFull()
            end
        end
        if type(WorldMapFrame_Minimize) == "function" then
            local oldMin = WorldMapFrame_Minimize
            WorldMapFrame_Minimize = function(a1, a2, a3)
                oldMin(a1, a2, a3)
                applyLight()
            end
        end

        hookScript(f, "OnShow", function()
            applyLight()
        end)
        hookWheels()
        hookScript(f, "OnMouseDown", function()
            if not st.active then return end
            WorldMapFrame:StartMoving()
            WorldMapFrame._ichaMoving = true
        end)
        hookScript(f, "OnMouseUp", function()
            if not WorldMapFrame._ichaMoving then return end
            WorldMapFrame._ichaMoving = nil
            WorldMapFrame:StopMovingOrSizing()
            savePos()
        end)
        hookScript(f, "OnHide", function()
            if not WorldMapFrame._ichaMoving then return end
            WorldMapFrame._ichaMoving = nil
            WorldMapFrame:StopMovingOrSizing()
            savePos()
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
        if f._ichaMoving then
            f._ichaMoving = nil
            f:StopMovingOrSizing()
        end
        setSpecial(false)
        if type(UIPanelWindows) == "table" and st.origPanel ~= nil then
            if st.origPanel then
                UIPanelWindows["WorldMapFrame"] = st.origPanel
            else
                UIPanelWindows["WorldMapFrame"] = nil
            end
        end
        f:SetScale(1)
        f:SetAlpha(1)
        f:EnableKeyboard(true)
        f:ClearAllPoints()
        f:SetAllPoints(UIParent)
        if BlackoutWorld then BlackoutWorld:Show() end
        paintBorder()
        if st.grip then st.grip:Hide() end
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
            local old = clamp(d.scale, SCALE_LO, SCALE_HI)
            local new = clamp(value, SCALE_LO, SCALE_HI)
            if d.point == "CENTER" and d.relPoint == "CENTER" and new > 0 then
                d.x = (tonumber(d.x) or 0) * old / new
                d.y = (tonumber(d.y) or 0) * old / new
            end
            d.scale = new
            applyLight()
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
