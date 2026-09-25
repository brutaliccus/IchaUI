-- Shared position model for hero bars, action bars, and edit mode.
-- Action bars start attached to the cluster (no barPlace row). Detach
-- parents a bar to UIParent. Snap distance is 14px. The gap is the
-- attached-layout padding (icon gap, or 2x that beside a hero) measured
-- from each bar's real edges, so square hero buttons and wide action
-- buttons do not share one cell size. Nudge is 1px on the snapped offset
-- and is saved with the snap. Escape saves the positions and leaves edit mode.

local SNAP = 14
local editOn = false
local finishing = false
local reopenConfig = false
local snapshot = nil
local drag = {}
local reg = { action = {}, hero = {} }
local movers = {}
local pinHostCenter
local chips = {}
local chipAt = {}
local entries = {}

local function absn(n)
    n = tonumber(n) or 0
    if n < 0 then n = -n end
    return n
end

local function gaps()
    local g = tonumber(IchaUI_LayoutGap) or 2
    if g < 0 then g = 0 end
    local m = tonumber(IchaUI_LayoutMidGap) or (g * 2)
    return g, m
end

local function frameCenter(f)
    if not f or not f.GetCenter then return nil, nil end
    local cx, cy = f:GetCenter()
    if not cx or not cy then return nil, nil end
    local fs = f:GetEffectiveScale() or 1
    local us = UIParent:GetEffectiveScale() or 1
    if us == 0 then us = 1 end
    return cx * fs / us, cy * fs / us
end

local function frameSize(f)
    local w = (f and f.GetWidth and f:GetWidth()) or 1
    local h = (f and f.GetHeight and f:GetHeight()) or 1
    if w < 1 then w = 1 end
    if h < 1 then h = 1 end
    local fs = (f and f.GetEffectiveScale and f:GetEffectiveScale()) or 1
    local us = UIParent:GetEffectiveScale() or 1
    if us == 0 then us = 1 end
    local k = fs / us
    return w * k, h * k
end

local function pinCenter(f, sx, sy)
    if not f or not sx or not sy then return end
    f:SetParent(UIParent)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx, sy)
end

local function parentHas(frame, needle)
    local guard = 0
    while frame and guard < 10 do
        if frame == needle then return true end
        if not frame.GetParent then return false end
        frame = frame:GetParent()
        guard = guard + 1
    end
    return false
end

local function copyTable(src, seen)
    if type(src) ~= "table" then return src end
    if not seen then seen = {} end
    if seen[src] then return seen[src] end
    local out = {}
    seen[src] = out
    local k, v
    for k, v in pairs(src) do
        if type(v) ~= "function" then
            if type(k) == "table" then
                out[copyTable(k, seen)] = copyTable(v, seen)
            else
                out[k] = copyTable(v, seen)
            end
        end
    end
    return out
end

local function copySnap(s)
    if type(s) ~= "table" then return nil end
    return {
        kind = s.kind,
        index = s.index,
        edge = s.edge,
        row = s.row or 0,
        useMid = s.useMid and true or false,
    }
end

local function sameSnap(a, b)
    if not a or not b then return false end
    if a.kind ~= b.kind then return false end
    if a.index ~= b.index then return false end
    if a.edge ~= b.edge then return false end
    if (a.row or 0) ~= (b.row or 0) then return false end
    return true
end

local function actionPlace(index, create)
    if not IchaUIDB then IchaUIDB = {} end
    if not create and type(IchaUIDB.barPlace) ~= "table" then return nil end
    if type(IchaUIDB.barPlace) ~= "table" then IchaUIDB.barPlace = {} end
    local row = IchaUIDB.barPlace[index]
    if create and type(row) ~= "table" then
        row = { nudgeX = 0, nudgeY = 0, detached = true }
        IchaUIDB.barPlace[index] = row
    end
    return row
end

local function extraRec(index)
    local list = IchaUIDB and IchaUIDB.heroExtras
    if type(list) ~= "table" then return nil end
    return list[index - 1]
end

local function extraPlace(index, create)
    local rec = extraRec(index)
    if type(rec) ~= "table" then return nil end
    if type(rec.place) ~= "table" then
        if not create then return nil end
        rec.place = { nudgeX = 0, nudgeY = 0 }
    end
    return rec.place
end

local function actionExtraRec(index)
    local list = IchaUIDB and IchaUIDB.actionExtras
    if type(list) ~= "table" then return nil end
    return list[index - 6]
end

local function actionExtraPlace(index, create)
    local rec = actionExtraRec(index)
    if type(rec) ~= "table" then return nil end
    if type(rec.place) ~= "table" then
        if not create then return nil end
        rec.place = { detached = true, nudgeX = 0, nudgeY = 0 }
    end
    return rec.place
end

local function placeOf(kind, index, create)
    if kind == "hero" then
        if index <= 1 then return nil end
        return extraPlace(index, create)
    end
    if kind == "action" and index > 6 then
        return actionExtraPlace(index, create)
    end
    return actionPlace(index, create)
end

local function isDetached(kind, index)
    if kind == "hero" then return index > 1 end
    if kind == "action" and index > 6 then return true end
    local row = actionPlace(index, false)
    return row and row.detached and true or false
end

function IchaUI_EditModeActive()
    return editOn and true or false
end

local function cursorPos()
    if not GetCursorPosition then return nil, nil end
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale() or 1
    if s == 0 then s = 1 end
    return (x or 0) / s, (y or 0) / s
end

local function bestSnap(kind, index, host)
    local gap, mid = gaps()
    local info = reg[kind] and reg[kind][index]
    local btnH = (info and info.btnH) or 30
    local cell = btnH + gap
    local best, bestD
    local function consider(targetKind, targetIndex, edge, row, useMid)
        if targetKind == kind and targetIndex == index then return end
        local tinfo = reg[targetKind] and reg[targetKind][targetIndex]
        if not tinfo or not tinfo.host then return end
        local target = tinfo.host
        if not target.IsShown or not target:IsShown() then return end
        if parentHas(target, host) or parentHas(host, target) then return end
        local tcx, tcy = frameCenter(target)
        local tw, th = frameSize(target)
        local aw, ah = frameSize(host)
        if not tcx or not aw then return end
        local pad = gap
        if useMid then pad = mid end
        local rowN = row or 0
        local ax, ay
        if edge == "left" then
            ax = tcx - tw / 2 - pad - aw / 2
            ay = tcy - th / 2 + ah / 2 + rowN * cell
        elseif edge == "right" then
            ax = tcx + tw / 2 + pad + aw / 2
            ay = tcy - th / 2 + ah / 2 + rowN * cell
        elseif edge == "above" then
            ax = tcx - tw / 2 + aw / 2
            ay = tcy + th / 2 + gap + ah / 2
        else
            ax = tcx - tw / 2 + aw / 2
            ay = tcy - th / 2 - gap - ah / 2
        end
        local hx, hy = frameCenter(host)
        if not hx then return end
        local d = absn(hx - ax)
        local dy = absn(hy - ay)
        if dy > d then d = dy end
        if kind == "action" and targetKind == "hero" and targetIndex == 1 then
            local homeEdge = "left"
            local homeRow = index - 1
            if index >= 4 then
                homeEdge = "right"
                homeRow = index - 4
            end
            if edge == homeEdge and rowN == homeRow then
                d = d - 0.25
            end
        end
        if d <= SNAP and (not bestD or d < bestD) then
            bestD = d
            best = {
                kind = targetKind,
                index = targetIndex,
                edge = edge,
                row = rowN,
                useMid = useMid and true or false,
            }
        end
    end
    local heroN = 0
    if IchaUI_HeroBarCount then heroN = IchaUI_HeroBarCount() or 1 end
    local hi
    for hi = 1, heroN do
        if kind == "action" then
            consider("hero", hi, "left", 0, true)
            consider("hero", hi, "left", 1, true)
            consider("hero", hi, "left", 2, true)
            consider("hero", hi, "right", 0, true)
            consider("hero", hi, "right", 1, true)
            consider("hero", hi, "right", 2, true)
        else
            consider("hero", hi, "left", 0, true)
            consider("hero", hi, "right", 0, true)
        end
        consider("hero", hi, "above", 0, false)
        consider("hero", hi, "below", 0, false)
    end
    local ai
    local actionN = 0
    if IchaUI_ActionBarCount then actionN = IchaUI_ActionBarCount() or 6 end
    for ai = 1, actionN do
        consider("action", ai, "left", 0, false)
        consider("action", ai, "right", 0, false)
        consider("action", ai, "above", 0, false)
        consider("action", ai, "below", 0, false)
    end
    return best
end

local function pinSnap(host, snap, nudgeX, nudgeY, btnH)
    if not host or not snap then return false end
    local tinfo = reg[snap.kind] and reg[snap.kind][snap.index]
    if not tinfo or not tinfo.host then return false end
    local target = tinfo.host
    local gap, mid = gaps()
    local pad = gap
    if snap.useMid then pad = mid end
    local cell = (btnH or 30) + gap
    local nx = tonumber(nudgeX) or 0
    local ny = tonumber(nudgeY) or 0
    local row = snap.row or 0
    host:SetParent(target)
    host:ClearAllPoints()
    if snap.edge == "left" then
        host:SetPoint("BOTTOMRIGHT", target, "BOTTOMLEFT", -pad + nx, row * cell + ny)
    elseif snap.edge == "right" then
        host:SetPoint("BOTTOMLEFT", target, "BOTTOMRIGHT", pad + nx, row * cell + ny)
    elseif snap.edge == "above" then
        host:SetPoint("BOTTOMLEFT", target, "TOPLEFT", nx, gap + ny)
    else
        host:SetPoint("TOPLEFT", target, "BOTTOMLEFT", nx, -gap + ny)
    end
    return true
end

local function saveFree(kind, index, host)
    local sx, sy = frameCenter(host)
    if not sx then return end
    local place = placeOf(kind, index, true)
    if not place then
        if kind == "hero" and index <= 1 and IchaUI_SaveLayoutPos then
            IchaUI_SaveLayoutPos()
        end
        return
    end
    place.snap = nil
    place.nudgeX = 0
    place.nudgeY = 0
    place.x = sx
    place.y = sy
    if kind == "action" then place.detached = true end
    pinCenter(host, sx, sy)
end

local function applySaved(kind, index, host, relX, relY)
    local info = reg[kind] and reg[kind][index]
    local btnH = info and info.btnH or 30
    local w = host:GetWidth() or 1
    local h = host:GetHeight() or 1
    if kind == "hero" and index <= 1 then
        local root = IchaUI_LayoutRoot and IchaUI_LayoutRoot()
        if not root then root = UIParent end
        host:SetParent(root)
        host:ClearAllPoints()
        host:SetPoint("BOTTOMLEFT", root, "BOTTOM", relX or 0, relY or 0)
        return
    end
    local place = placeOf(kind, index, kind == "hero")
    if kind == "action" and index <= 6 and (not place or not place.detached) then
        local root = IchaUI_LayoutRoot and IchaUI_LayoutRoot()
        if not root then root = UIParent end
        host:SetParent(root)
        host:ClearAllPoints()
        host:SetPoint("BOTTOMLEFT", root, "BOTTOM", relX or 0, relY or 0)
        return
    end
    if place and place.snap then
        if pinSnap(host, place.snap, place.nudgeX, place.nudgeY, btnH) then
            return
        end
    end
    if place and place.x ~= nil and place.y ~= nil then
        pinCenter(host, place.x, place.y)
        return
    end
    local root = IchaUI_LayoutRoot and IchaUI_LayoutRoot()
    if not root then root = UIParent end
    host:SetParent(root)
    host:ClearAllPoints()
    host:SetPoint("BOTTOMLEFT", root, "BOTTOM", relX or 0, relY or 0)
end

function IchaUI_ReapplyBarPlaces()
    local function again(kind, n)
        local i
        for i = 1, n do
            local info = reg[kind] and reg[kind][i]
            if info and info.host then
                if info.dx ~= nil and not isDetached(kind, i) then
                    pinHostCenter(info.host, info.dx, info.dy)
                else
                    applySaved(kind, i, info.host, info.relX, info.relY)
                end
            end
        end
    end
    local an = 6
    if IchaUI_ActionBarCount then an = IchaUI_ActionBarCount() or 6 end
    local hn = 1
    if IchaUI_HeroBarCount then hn = IchaUI_HeroBarCount() or 1 end
    again("hero", hn)
    again("action", an)
end

local function paintChip(b, text)
    b:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    b:SetBackdropColor(0.08, 0.08, 0.09, 0.94)
    b:SetBackdropBorderColor(0.93, 0.78, 0.35, 1)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    fs:SetText(text or "")
    fs:SetTextColor(1, 1, 1)
    b.label = fs
end

local function countOpen()
    local n = 0
    local i
    for i = 1, table.getn(entries) do
        if not entries[i].locked then n = n + 1 end
    end
    return n
end

local endEdit

local function markLocked(id)
    local i
    for i = 1, table.getn(entries) do
        if entries[i].id == id then entries[i].locked = true end
    end
    if countOpen() < 1 then endEdit(true) end
end

local function refreshMover(kind, index)
    local key = kind .. index
    local mv = movers[key]
    if not mv then return end
    local place = placeOf(kind, index, false)
    local snapped = place and place.snap
    local detached = isDetached(kind, index)
    if mv.detach then
        if kind == "action" and not detached and editOn and not mv.locked then
            mv.detach:Show()
        else
            mv.detach:Hide()
        end
    end
    if mv.nudge then
        if snapped and editOn and not mv.locked then mv.nudge:Show() else mv.nudge:Hide() end
    end
end

local function ensureMover(kind, index, host)
    local key = kind .. index
    local mv = movers[key]
    if mv then
        mv:SetParent(host)
        mv:ClearAllPoints()
        mv:SetAllPoints(host)
        return mv
    end
    mv = CreateFrame("Frame", "IchaUIMove" .. key, host)
    mv:SetMovable(true)
    mv:SetAllPoints(host)
    mv:SetFrameStrata("DIALOG")
    mv:EnableMouse(true)
    mv:RegisterForDrag("LeftButton")
    local bg = mv:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(mv)
    bg:SetTexture(1, 1, 1, 1)
    bg:SetVertexColor(0.15, 0.45, 0.95, 0.28)
    local label = mv:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER", mv, "CENTER", 0, 0)
    label:SetTextColor(1, 1, 1)
    if kind == "hero" then
        if index <= 1 then label:SetText("Hero") else label:SetText("Hero " .. index) end
    else
        label:SetText("Bar " .. index)
    end
    mv.label = label

    local lock = CreateFrame("Button", nil, mv)
    lock:SetWidth(36)
    lock:SetHeight(16)
    lock:SetPoint("TOPRIGHT", mv, "TOPRIGHT", 0, 0)
    lock:SetFrameLevel((mv:GetFrameLevel() or 1) + 5)
    paintChip(lock, "Lock")
    lock:SetScript("OnClick", function()
        mv.locked = true
        mv:EnableMouse(false)
        mv:Hide()
        if kind == "hero" and index <= 1 and IchaUI_SaveLayoutPos then
            IchaUI_SaveLayoutPos()
        end
        markLocked(key)
    end)
    mv.lock = lock

    local detach = CreateFrame("Button", nil, mv)
    detach:SetWidth(48)
    detach:SetHeight(16)
    detach:SetPoint("TOPLEFT", mv, "TOPLEFT", 0, 0)
    detach:SetFrameLevel((mv:GetFrameLevel() or 1) + 5)
    paintChip(detach, "Detach")
    detach:SetScript("OnClick", function()
        local sx, sy = frameCenter(host)
        local place = actionPlace(index, true)
        place.detached = true
        place.snap = nil
        place.nudgeX = 0
        place.nudgeY = 0
        place.x = sx
        place.y = sy
        pinCenter(host, sx, sy)
        mv:SetParent(host)
        mv:ClearAllPoints()
        mv:SetAllPoints(host)
        refreshMover(kind, index)
        if IchaUI_RequestLayout then IchaUI_RequestLayout() end
    end)
    mv.detach = detach

    local nudge = CreateFrame("Frame", nil, mv)
    nudge:SetWidth(70)
    nudge:SetHeight(16)
    nudge:SetPoint("BOTTOM", mv, "BOTTOM", 0, 0)
    nudge:SetFrameLevel((mv:GetFrameLevel() or 1) + 5)
    local function arrow(text, dx, dy, x)
        local b = CreateFrame("Button", nil, nudge)
        b:SetWidth(16)
        b:SetHeight(16)
        b:SetPoint("LEFT", nudge, "LEFT", x, 0)
        paintChip(b, text)
        b:SetScript("OnClick", function()
            local place = placeOf(kind, index, false)
            if not place or not place.snap then return end
            place.nudgeX = (tonumber(place.nudgeX) or 0) + dx
            place.nudgeY = (tonumber(place.nudgeY) or 0) + dy
            local info = reg[kind] and reg[kind][index]
            local btnH = info and info.btnH or 30
            pinSnap(host, place.snap, place.nudgeX, place.nudgeY, btnH)
        end)
    end
    arrow("<", -1, 0, 0)
    arrow(">", 1, 0, 18)
    arrow("^", 0, 1, 36)
    arrow("v", 0, -1, 54)
    mv.nudge = nudge

    mv:SetScript("OnDragStart", function()
        if not editOn or mv.locked then return end
        if kind == "hero" and index <= 1 then
            drag.mode = "cluster"
            drag.host = nil
            local root = IchaUI_LayoutRoot and IchaUI_LayoutRoot()
            if root then root:StartMoving() end
            return
        end
        if kind == "action" and not isDetached(kind, index) then
            drag.mode = "cluster"
            drag.host = nil
            local root = IchaUI_LayoutRoot and IchaUI_LayoutRoot()
            if root then root:StartMoving() end
            return
        end
        local place = placeOf(kind, index, true)
        drag.mode = "bar"
        drag.kind = kind
        drag.index = index
        drag.host = host
        drag.origin = place and copySnap(place.snap) or nil
        drag.nudgeX = place and tonumber(place.nudgeX) or 0
        drag.nudgeY = place and tonumber(place.nudgeY) or 0
        drag.sticky = nil
        drag.moved = nil
        drag.startX, drag.startY = frameCenter(host)
        local sx, sy = frameCenter(host)
        pinCenter(host, sx, sy)
        host:StartMoving()
    end)
    mv:SetScript("OnDragStop", function()
        if drag.internal then return end
        if drag.mode == "cluster" then
            local root = IchaUI_LayoutRoot and IchaUI_LayoutRoot()
            if root then
                root:StopMovingOrSizing()
                if IchaUI_SaveLayoutPos then IchaUI_SaveLayoutPos() end
            end
            drag.mode = nil
            return
        end
        if drag.host ~= host then return end
        drag.internal = true
        host:StopMovingOrSizing()
        drag.internal = false
        local snap = drag.sticky
        if not drag.moved then snap = nil end
        if not snap and drag.moved then snap = bestSnap(kind, index, host) end
        local place = placeOf(kind, index, true)
        if snap and place then
            local nx, ny = 0, 0
            if sameSnap(snap, drag.origin) then
                nx = drag.nudgeX or 0
                ny = drag.nudgeY or 0
            end
            place.snap = snap
            place.nudgeX = nx
            place.nudgeY = ny
            if kind == "action" then place.detached = true end
            local info = reg[kind] and reg[kind][index]
            pinSnap(host, snap, nx, ny, info and info.btnH or 30)
            local fx, fy = frameCenter(host)
            if fx then
                place.x = fx
                place.y = fy
            end
        else
            saveFree(kind, index, host)
        end
        drag.host = nil
        drag.mode = nil
        drag.sticky = nil
        refreshMover(kind, index)
    end)
    mv:SetScript("OnMouseUp", function()
        if arg1 ~= "RightButton" then return end
        if not editOn or mv.locked then return end
        if kind ~= "action" and kind ~= "hero" then return end
        if IchaUI_ShowActionGridPop then IchaUI_ShowActionGridPop(kind, index, mv) end
    end)
    movers[key] = mv
    mv:Hide()
    return mv
end

local function showBarMovers()
    local ai
    local actionN = 0
    if IchaUI_ActionBarCount then actionN = IchaUI_ActionBarCount() or 6 end
    for ai = 1, actionN do
        local info = reg.action[ai]
        if info and info.host then
            info.host:Show()
            local mv = ensureMover("action", ai, info.host)
            mv.locked = false
            mv:EnableMouse(true)
            mv:Show()
            refreshMover("action", ai)
        end
    end
    local heroN = 0
    if IchaUI_HeroBarCount then heroN = IchaUI_HeroBarCount() or 1 end
    local hi
    for hi = 1, heroN do
        local info = reg.hero[hi]
        if info and info.host then
            info.host:Show()
            local mv = ensureMover("hero", hi, info.host)
            mv.locked = false
            mv:EnableMouse(true)
            mv:Show()
            refreshMover("hero", hi)
        end
    end
end

local function hideBarMovers()
    if IchaUI_HideActionGridPop then IchaUI_HideActionGridPop() end
    if IchaUI_HideDrawerPop then IchaUI_HideDrawerPop() end
    local k, mv
    for k, mv in pairs(movers) do
        mv.locked = false
        mv:Hide()
        mv:EnableMouse(false)
    end
end

local gridPop
local gridFor

local function ceilDiv(n, d)
    n = math.floor(tonumber(n) or 1)
    d = math.floor(tonumber(d) or 1)
    if n < 1 then n = 1 end
    if d < 1 then d = 1 end
    return math.floor((n + d - 1) / d)
end

local function lookCurrent()
    if gridPop and gridPop.kind == "hero" and IchaUI_HeroBarLook then
        return IchaUI_HeroBarLook(gridFor)
    end
    if IchaUI_ActionBarLook then return IchaUI_ActionBarLook(gridFor) end
end

local function applyGridFrom(which, raw)
    if not gridFor or not lookCurrent() then return end
    local scale, opacity, fade, slots, cols, rows, owned = lookCurrent()
    slots = math.floor(tonumber(slots) or 1)
    cols = math.floor(tonumber(cols) or 1)
    rows = math.floor(tonumber(rows) or 1)
    owned = math.floor(tonumber(owned) or slots)
    if owned < 1 then owned = 1 end
    raw = math.floor((tonumber(raw) or 1) + 0.5)
    if which == "slots" then
        slots = raw
        if slots < 1 then slots = 1 end
        if slots > owned then slots = owned end
        if cols > slots then cols = slots end
        if cols < 1 then cols = 1 end
        rows = ceilDiv(slots, cols)
    elseif which == "cols" then
        cols = raw
        if cols < 1 then cols = 1 end
        if cols > slots then cols = slots end
        rows = ceilDiv(slots, cols)
    elseif which == "rows" then
        rows = raw
        if rows < 1 then rows = 1 end
        if rows > slots then rows = slots end
        cols = ceilDiv(slots, rows)
        if cols > slots then cols = slots end
        if cols < 1 then cols = 1 end
    end
    if gridPop and gridPop.kind == "hero" and IchaUI_HeroBarSetMenu then
        IchaUI_HeroBarSetMenu(gridFor, cols, rows, slots)
    elseif IchaUI_ActionBarSetGrid then
        IchaUI_ActionBarSetGrid(gridFor, cols, rows, slots)
    end
end

local function applyStyleFrom(which, raw)
    if not gridFor or not lookCurrent() then return end
    local scale, opacity, fade, slots, cols, rows, owned, gap = lookCurrent()
    scale = tonumber(scale) or 1
    opacity = tonumber(opacity) or 1
    fade = tonumber(fade) or opacity
    local writeGap = nil
    if which == "scale" then
        scale = tonumber(raw) or 1
    elseif which == "opacity" then
        opacity = (tonumber(raw) or 100) / 100
    elseif which == "fade" then
        fade = (tonumber(raw) or 100) / 100
    elseif which == "gap" then
        writeGap = math.floor((tonumber(raw) or 0) + 0.5)
    end
    if gridPop and gridPop.kind == "hero" and IchaUI_HeroBarSetStyle then
        IchaUI_HeroBarSetStyle(gridFor, scale, opacity, fade, writeGap)
    elseif IchaUI_ActionBarSetStyle then
        IchaUI_ActionBarSetStyle(gridFor, scale, opacity, fade, writeGap)
    end
end

local function applyFormSlider(which, raw)
    if not gridFor then return end
    local shape, layout, spread, arc, rot = "rect", "grid", 90, 360, 90
    if gridPop and gridPop.kind == "hero" and IchaUI_HeroBarForm then
        shape, layout, spread, arc, rot = IchaUI_HeroBarForm(gridFor)
    elseif IchaUI_ActionBarForm then
        shape, layout, spread, arc, rot = IchaUI_ActionBarForm(gridFor)
    end
    raw = math.floor((tonumber(raw) or 0) + 0.5)
    if which == "spread" then spread = raw
    elseif which == "arc" then arc = raw
    elseif which == "rot" then rot = raw end
    if gridPop and gridPop.kind == "hero" and IchaUI_HeroBarSetForm then
        IchaUI_HeroBarSetForm(gridFor, shape, layout, spread, arc, rot)
    elseif IchaUI_ActionBarSetForm then
        IchaUI_ActionBarSetForm(gridFor, shape, layout, spread, arc, rot)
    end
end

local function paintGridPop()
    if not gridPop or not gridFor or not lookCurrent() then return end
    local scale, opacity, fade, slots, cols, rows, owned, gap = lookCurrent()
    owned = math.floor(tonumber(owned) or 1)
    if owned < 1 then owned = 1 end
    gridPop.skip = true
    local function setSl(sl, lo, hi, v)
        if not sl then return end
        sl:SetMinMaxValues(lo, hi)
        if v < lo then v = lo end
        if v > hi then v = hi end
        sl:SetValue(v)
        if sl.valueText then
            if sl.whole then
                sl.valueText:SetText(tostring(math.floor(v + 0.5)))
            else
                sl.valueText:SetText(string.format("%.2f", v))
            end
        end
    end
    local scaleHi = 2
    local colHi = owned
    local rowHi = owned
    if gridPop.kind == "hero" then
        scaleHi = 3
        if colHi > 12 then colHi = 12 end
        if rowHi > 5 then rowHi = 5 end
    end
    setSl(gridPop.scaleSl, 0.5, scaleHi, tonumber(scale) or 1)
    setSl(gridPop.opSl, 0, 100, (tonumber(opacity) or 1) * 100)
    setSl(gridPop.fadeSl, 0, 100, (tonumber(fade) or 1) * 100)
    setSl(gridPop.slotSl, 1, owned, tonumber(slots) or owned)
    setSl(gridPop.colSl, 1, colHi, tonumber(cols) or 1)
    setSl(gridPop.rowSl, 1, rowHi, tonumber(rows) or 1)
    setSl(gridPop.padSl, 0, 20, tonumber(gap) or 2)
    local shape, layout, spread, arc, rot = "rect", "grid", 90, 360, 90
    if gridPop.kind == "hero" and IchaUI_HeroBarForm then
        shape, layout, spread, arc, rot = IchaUI_HeroBarForm(gridFor)
    elseif IchaUI_ActionBarForm then
        shape, layout, spread, arc, rot = IchaUI_ActionBarForm(gridFor)
    end
    if gridPop.shapeBtn and gridPop.shapeBtn.label then
        local lab = shape
        if IchaUI_FormShapeLabel then lab = IchaUI_FormShapeLabel(shape) end
        gridPop.shapeBtn.label:SetText("Shape: " .. lab)
    end
    if gridPop.layBtn and gridPop.layBtn.label then
        if layout == "radial" then
            gridPop.layBtn.label:SetText("Layout: Radial")
        else
            gridPop.layBtn.label:SetText("Layout: Grid")
        end
    end
    setSl(gridPop.spreadSl, 10, 360, tonumber(spread) or 90)
    setSl(gridPop.arcSl, 10, 360, tonumber(arc) or 360)
    setSl(gridPop.rotSl, -360, 360, tonumber(rot) or 90)
    gridPop.skip = nil
end

function IchaUI_HideActionGridPop()
    if gridPop then gridPop:Hide() end
    gridFor = nil
end

local function savePopPos()
    if not gridPop or not gridPop.GetLeft then return end
    if not IchaUIDB then IchaUIDB = {} end
    local x = gridPop:GetLeft()
    local y = gridPop:GetTop()
    local ux = UIParent:GetLeft() or 0
    local uy = UIParent:GetTop() or 0
    if not x or not y then return end
    IchaUIDB.barPopPos = { x = x - ux, y = y - uy }
end

local function placePop()
    if not gridPop or gridPop.placed then return end
    gridPop:ClearAllPoints()
    local pos = IchaUIDB and IchaUIDB.barPopPos
    if pos and pos.x and pos.y then
        gridPop:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos.x, pos.y)
        gridPop.placed = true
        return
    end
    local cx, cy = 0, 0
    if GetCursorPosition then cx, cy = GetCursorPosition() end
    local scale = 1
    if UIParent.GetEffectiveScale then scale = UIParent:GetEffectiveScale() or 1 end
    if scale < 0.01 then scale = 1 end
    cx = cx / scale
    cy = cy / scale
    local pw = gridPop:GetWidth() or 230
    local ph = gridPop:GetHeight() or 210
    local sw = UIParent:GetWidth() or 0
    local sh = UIParent:GetHeight() or 0
    local x = cx + 12
    if x + pw > sw then x = sw - pw - 8 end
    if x < 0 then x = 0 end
    local top = cy + 8
    if top > sh then top = sh - 8 end
    if top < ph then top = ph end
    gridPop:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, top - sh)
    gridPop.placed = true
    savePopPos()
end

function IchaUI_ShowActionGridPop(kind, index, anchor)
    if kind ~= "action" and kind ~= "hero" then
        anchor = index
        index = kind
        kind = "action"
    end
    index = tonumber(index) or 1
    if IchaUI_HideDrawerPop then IchaUI_HideDrawerPop() end
    if not gridPop then
        gridPop = CreateFrame("Frame", "IchaUIBarGridPop", UIParent)
        gridPop:SetWidth(250)
        gridPop:SetHeight(360)
        gridPop:SetFrameStrata("TOOLTIP")
        gridPop:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        gridPop:SetBackdropColor(0.08, 0.08, 0.09, 0.94)
        gridPop:SetBackdropBorderColor(0.93, 0.78, 0.35, 1)
        gridPop:EnableMouse(true)
        gridPop:SetMovable(true)
        gridPop:RegisterForDrag("LeftButton")
        gridPop:SetScript("OnDragStart", function() this:StartMoving() end)
        gridPop:SetScript("OnDragStop", function()
            this:StopMovingOrSizing()
            savePopPos()
        end)
        local function addSlider(key, title, y, lo, hi, step, whole, kind)
            local fs = gridPop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", gridPop, "TOPLEFT", 8, y)
            fs:SetText(title)
            fs:SetTextColor(1, 1, 1)
            fs:SetWidth(52)
            fs:SetJustifyH("LEFT")
            local name = "IchaUIBarPop" .. key
            local sl = CreateFrame("Slider", name, gridPop, "OptionsSliderTemplate")
            sl:SetPoint("TOPLEFT", gridPop, "TOPLEFT", 62, y)
            sl:SetWidth(110)
            sl:SetHeight(16)
            sl:SetMinMaxValues(lo, hi)
            sl:SetValueStep(step)
            local low = getglobal(name .. "Low")
            local high = getglobal(name .. "High")
            local mid = getglobal(name .. "Text")
            if low then low:SetText("") low:SetTextColor(1, 1, 1) end
            if high then high:SetText("") high:SetTextColor(1, 1, 1) end
            if mid then mid:SetText("") mid:SetTextColor(1, 1, 1) end
            local vt = gridPop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            vt:SetPoint("LEFT", sl, "RIGHT", 6, 0)
            vt:SetTextColor(1, 1, 1)
            sl.valueText = vt
            sl.whole = whole
            sl.kind = kind
            sl:SetScript("OnValueChanged", function()
                if gridPop.skip then return end
                local v = this:GetValue() or 0
                if this.whole then v = math.floor(v + 0.5) end
                if this.valueText then
                    if this.whole then
                        this.valueText:SetText(tostring(math.floor(v + 0.5)))
                    else
                        this.valueText:SetText(string.format("%.2f", v))
                    end
                end
                if this.kind == "scale" or this.kind == "opacity" or this.kind == "fade" or this.kind == "gap" then
                    applyStyleFrom(this.kind, v)
                elseif this.kind == "spread" or this.kind == "arc" or this.kind == "rot" then
                    applyFormSlider(this.kind, v)
                else
                    applyGridFrom(this.kind, v)
                end
                gridPop.skip = true
                paintGridPop()
                gridPop.skip = nil
            end)
            return sl
        end
        gridPop.scaleSl = addSlider("Scale", "Scale", -8, 0.5, 2, 0.05, false, "scale")
        gridPop.opSl = addSlider("Opacity", "Opacity", -36, 0, 100, 1, true, "opacity")
        gridPop.fadeSl = addSlider("Fade", "Faded", -64, 0, 100, 1, true, "fade")
        gridPop.slotSl = addSlider("Slots", "Slots", -92, 1, 12, 1, true, "slots")
        gridPop.colSl = addSlider("Cols", "Cols", -120, 1, 12, 1, true, "cols")
        gridPop.rowSl = addSlider("Rows", "Rows", -148, 1, 12, 1, true, "rows")
        gridPop.padSl = addSlider("Pad", "Pad", -176, 0, 20, 1, true, "gap")
        gridPop.spreadSl = addSlider("Spread", "Spread", -232, 10, 360, 1, true, "spread")
        gridPop.arcSl = addSlider("Arc", "Arc", -260, 10, 360, 1, true, "arc")
        gridPop.rotSl = addSlider("Rot", "Sh Rot", -288, -360, 360, 1, true, "rot")
        local function formButton(text, y, onClick)
            local b = CreateFrame("Button", nil, gridPop)
            b:SetWidth(160)
            b:SetHeight(18)
            b:SetPoint("TOPLEFT", gridPop, "TOPLEFT", 8, y)
            b:SetBackdrop({
                bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                tile = true, tileSize = 8, edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            b:SetBackdropColor(0.08, 0.08, 0.09, 0.9)
            b:SetBackdropBorderColor(0.93, 0.78, 0.35, 1)
            local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("CENTER", b, "CENTER", 0, 0)
            fs:SetText(text)
            fs:SetTextColor(1, 1, 1)
            b.label = fs
            b:SetScript("OnClick", onClick)
            return b
        end
        gridPop.shapeBtn = formButton("Shape: Rectangle", -204, function()
            local shape, layout, spread, arc, rot = "rect", "grid", 90, 360, 90
            if gridPop.kind == "hero" and IchaUI_HeroBarForm then
                shape, layout, spread, arc, rot = IchaUI_HeroBarForm(gridFor)
            elseif IchaUI_ActionBarForm then
                shape, layout, spread, arc, rot = IchaUI_ActionBarForm(gridFor)
            end
            if IchaUI_FormShapeNext then shape = IchaUI_FormShapeNext(shape) end
            if gridPop.kind == "hero" and IchaUI_HeroBarSetForm then
                IchaUI_HeroBarSetForm(gridFor, shape, layout, spread, arc, rot)
            elseif IchaUI_ActionBarSetForm then
                IchaUI_ActionBarSetForm(gridFor, shape, layout, spread, arc, rot)
            end
            paintGridPop()
        end)
        if IchaUI_ShapeDropdown then
            IchaUI_ShapeDropdown(gridPop.shapeBtn, function()
                if gridPop.kind == "hero" and IchaUI_HeroBarForm then return (IchaUI_HeroBarForm(gridFor)) end
                if IchaUI_ActionBarForm then return (IchaUI_ActionBarForm(gridFor)) end
                return "rect"
            end)
        end
        gridPop.layBtn = formButton("Layout: Grid", -316, function()
            local shape, layout, spread, arc, rot = "rect", "grid", 90, 360, 90
            if gridPop.kind == "hero" and IchaUI_HeroBarForm then
                shape, layout, spread, arc, rot = IchaUI_HeroBarForm(gridFor)
            elseif IchaUI_ActionBarForm then
                shape, layout, spread, arc, rot = IchaUI_ActionBarForm(gridFor)
            end
            if layout == "radial" then layout = "grid" else layout = "radial" end
            if gridPop.kind == "hero" and IchaUI_HeroBarSetForm then
                IchaUI_HeroBarSetForm(gridFor, shape, layout, spread, arc, rot)
            elseif IchaUI_ActionBarSetForm then
                IchaUI_ActionBarSetForm(gridFor, shape, layout, spread, arc, rot)
            end
            paintGridPop()
        end)
    end
    gridPop.kind = kind
    gridFor = index
    paintGridPop()
    placePop()
    gridPop:Show()
end

local function layoutRoot()
    local root = IchaUI_LayoutRoot and IchaUI_LayoutRoot()
    if not root then root = UIParent end
    return root
end

-- Screen delta between two frame centers, in the root's point space.
local function centerDelta(host, root)
    local hx, hy = frameCenter(host)
    local rx, ry = frameCenter(root)
    if not hx or not rx then return nil end
    local us = UIParent:GetEffectiveScale() or 1
    if us == 0 then us = 1 end
    local ps = (root.GetEffectiveScale and root:GetEffectiveScale()) or 1
    if ps == 0 then ps = 1 end
    local k = us / ps
    return (hx - rx) * k, (hy - ry) * k
end

pinHostCenter = function(host, dx, dy)
    local root = layoutRoot()
    host:SetParent(root)
    host:ClearAllPoints()
    host:SetPoint("CENTER", root, "CENTER", dx or 0, dy or 0)
end

function IchaUI_HoldBarCenter(kind, index, host)
    if not host then return end
    if drag.host == host then return end
    local info = reg[kind] and reg[kind][index]
    if isDetached(kind, index) then
        if info then applySaved(kind, index, host, info.relX, info.relY) end
        return
    end
    if info and info.dx ~= nil then
        pinHostCenter(host, info.dx, info.dy)
    end
end

function IchaUI_SeatBarHost(kind, index, host, relX, relY, w, h, btnW, btnH)
    if not reg[kind] then reg[kind] = {} end
    local prev = reg[kind][index]
    local dx, dy = nil, nil
    if prev and prev.dx ~= nil then
        dx, dy = prev.dx, prev.dy
    end
    reg[kind][index] = {
        host = host,
        relX = relX,
        relY = relY,
        btnW = btnW,
        btnH = btnH,
        dx = dx,
        dy = dy,
    }
    if host and w and h then
        host:SetWidth(w)
        host:SetHeight(h)
    end
    if editOn then
        local id = kind .. index
        local found = false
        local ei
        for ei = 1, table.getn(entries) do
            if entries[ei].id == id then found = true end
        end
        if not found then
            table.insert(entries, { id = id, frame = host, locked = false })
        end
    end
    if drag.host == host then
        if editOn then
            local mv = ensureMover(kind, index, host)
            mv:Show()
        end
        return
    end
    -- Attached bars keep the center captured on first seat. A later stack
    -- pass (edit mode, radial) must not write a new BOTTOMLEFT offset.
    local row = placeOf(kind, index, false)
    local parked = isDetached(kind, index) or (row and (row.snap or row.x ~= nil))
    if parked or dx == nil then
        applySaved(kind, index, host, relX, relY)
    end
    if not parked and host then
        if dx == nil then
            dx, dy = centerDelta(host, layoutRoot())
            reg[kind][index].dx = dx
            reg[kind][index].dy = dy
        end
        if dx ~= nil then
            pinHostCenter(host, dx, dy)
        end
    end
    if editOn and host then
        host:Show()
        local mv = ensureMover(kind, index, host)
        if not mv.locked then
            mv:EnableMouse(true)
            mv:Show()
            refreshMover(kind, index)
        end
    end
end

local catcher
local function ensureCatcher()
    if catcher then return catcher end
    catcher = CreateFrame("Frame", "IchaUIEditCatcher", UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("BACKGROUND")
    catcher:EnableMouse(false)
    catcher:EnableKeyboard(true)
    catcher:Hide()
    local hint = catcher:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hint:SetPoint("TOP", UIParent, "TOP", 0, -80)
    hint:SetText("Edit positions — drag, then Lock each frame. Escape cancels.")
    hint:SetTextColor(1, 1, 1)
    catcher.hint = hint
    catcher:SetScript("OnHide", function()
        if finishing or not editOn then return end
        if IchaUI_EditPositionsCancel then IchaUI_EditPositionsCancel() end
    end)
    catcher:SetScript("OnKeyDown", function()
        if arg1 == "ESCAPE" and editOn then
            -- First Escape closes an open settings popup; the next one leaves edit mode.
            if IchaUI_DrawerPopShown and IchaUI_DrawerPopShown() then
                IchaUI_HideDrawerPop()
                return
            end
            if gridPop and gridPop:IsShown() then
                IchaUI_HideActionGridPop()
                return
            end
            if IchaUI_EditPositionsCancel then IchaUI_EditPositionsCancel() end
        end
    end)
    if UISpecialFrames then
        local found = false
        local i
        for i = 1, table.getn(UISpecialFrames) do
            if UISpecialFrames[i] == "IchaUIEditCatcher" then found = true end
        end
        if not found then table.insert(UISpecialFrames, "IchaUIEditCatcher") end
    end
    return catcher
end

local driver = CreateFrame("Frame", "IchaUIEditDriver", UIParent)
driver:SetScript("OnUpdate", function()
    if not editOn or drag.mode ~= "bar" or not drag.host then return end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        -- Leaving a live snap calls StartMoving again. That second move
        -- has no OnDragStop, so mouse-up here must always release.
        local host = drag.host
        local kind, index = drag.kind, drag.index
        local wasSticky = drag.sticky
        local didMove = drag.moved
        drag.internal = true
        if host and host.StopMovingOrSizing then host:StopMovingOrSizing() end
        drag.internal = false
        drag.host = nil
        drag.mode = nil
        drag.sticky = nil
        drag.moved = nil
        if host and kind then
            local snap = wasSticky
            if not snap and didMove then snap = bestSnap(kind, index, host) end
            local place = placeOf(kind, index, true)
            if snap and place then
                local nx, ny = 0, 0
                if sameSnap(snap, drag.origin) then
                    nx = drag.nudgeX or 0
                    ny = drag.nudgeY or 0
                end
                place.snap = snap
                place.nudgeX = nx
                place.nudgeY = ny
                if kind == "action" then place.detached = true end
                local info = reg[kind] and reg[kind][index]
                pinSnap(host, snap, nx, ny, info and info.btnH or 30)
                local fx, fy = frameCenter(host)
                if fx then
                    place.x = fx
                    place.y = fy
                end
            else
                saveFree(kind, index, host)
            end
        end
        refreshMover(kind, index)
        return
    end
    local host = drag.host
    local cx, cy = cursorPos()
    if drag.sticky then
        if cx and drag.cursorX then
            if absn(cx - drag.cursorX) > SNAP or absn(cy - (drag.cursorY or 0)) > SNAP then
                drag.sticky = nil
                local sx, sy = frameCenter(host)
                pinCenter(host, sx, sy)
                host:StartMoving()
                local place = placeOf(drag.kind, drag.index, true)
                if place then
                    place.snap = nil
                    place.nudgeX = 0
                    place.nudgeY = 0
                end
                refreshMover(drag.kind, drag.index)
            end
        end
        return
    end
    if not drag.moved then
        local hx, hy = frameCenter(host)
        if hx and drag.startX then
            if absn(hx - drag.startX) > SNAP or absn(hy - (drag.startY or 0)) > SNAP then
                drag.moved = true
            end
        end
    end
    if not drag.moved then return end
    local snap = bestSnap(drag.kind, drag.index, host)
    if not snap then return end
    local nx, ny = 0, 0
    if sameSnap(snap, drag.origin) then
        nx = drag.nudgeX or 0
        ny = drag.nudgeY or 0
    end
    drag.internal = true
    host:StopMovingOrSizing()
    drag.internal = false
    local info = reg[drag.kind] and reg[drag.kind][drag.index]
    if pinSnap(host, snap, nx, ny, info and info.btnH or 30) then
        drag.sticky = snap
        drag.cursorX, drag.cursorY = cursorPos()
        local place = placeOf(drag.kind, drag.index, true)
        if place then
            place.snap = snap
            place.nudgeX = nx
            place.nudgeY = ny
            if drag.kind == "action" then place.detached = true end
            local fx, fy = frameCenter(host)
            if fx then
                place.x = fx
                place.y = fy
            end
        end
        refreshMover(drag.kind, drag.index)
    end
end)

local function hideChips()
    local i
    for i = 1, table.getn(chips) do
        if chips[i] then chips[i]:Hide() end
    end
    chips = {}
    chipAt = {}
end

local function addChip(frame, id, onLock)
    if not frame then return end
    chipAt[frame] = (chipAt[frame] or 0) + 1
    local b = CreateFrame("Button", nil, frame)
    b:SetWidth(36)
    b:SetHeight(16)
    b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -((chipAt[frame] - 1) * 40), 16)
    b:SetFrameStrata("TOOLTIP")
    b:SetFrameLevel(200)
    paintChip(b, "Lock")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function()
        if arg1 == "RightButton" then
            local did = IchaUI_DrawerIdForEntry and IchaUI_DrawerIdForEntry(id)
            if did and IchaUI_ShowDrawerPop then IchaUI_ShowDrawerPop(did) end
            return
        end
        if onLock then onLock() end
        b:Hide()
        markLocked(id)
    end)
    b:Show()
    table.insert(chips, b)
end

local function shown(frame)
    return frame and frame.IsShown and frame:IsShown()
end

local function collectEntries()
    entries = {}
    local function add(id, frame, unlock, lock)
        if not frame then return end
        table.insert(entries, { id = id, frame = frame, unlock = unlock, lock = lock, locked = false })
    end
    local ai
    local actionN = 0
    if IchaUI_ActionBarCount then actionN = IchaUI_ActionBarCount() or 6 end
    for ai = 1, actionN do
        local info = reg.action[ai]
        if info and info.host then
            add("action" .. ai, info.host, nil, nil)
        end
    end
    local heroN = 0
    if IchaUI_HeroBarCount then heroN = IchaUI_HeroBarCount() or 1 end
    local hi
    for hi = 1, heroN do
        local info = reg.hero[hi]
        if info and info.host then
            add("hero" .. hi, info.host, nil, nil)
        end
    end
    local xp = getglobal("IchaUIXPRoot")
    if IchaUIXP_SetMove and shown(xp) then
        add("xp", xp, function()
            if IchaUIXP_SetMove then IchaUIXP_SetMove(true) end
        end, function()
            if IchaUIXP_SetMove then IchaUIXP_SetMove(false) end
        end)
    end
    local ufKeys = { "player", "target", "tot", "focus" }
    local ui
    for ui = 1, table.getn(ufKeys) do
        local key = ufKeys[ui]
        local fr = IchaUIUF_Get and IchaUIUF_Get(key)
        if IchaUIUF_Get and fr and fr.root and shown(fr.root) then
            local k = key
            add("uf" .. k, fr.root, function()
                if IchaUIUF_Set then IchaUIUF_Set(k, "move", true) end
            end, function()
                if IchaUIUF_Set then IchaUIUF_Set(k, "move", false) end
            end)
        end
    end
    local party = getglobal("IchaUIUF_PartyRoot")
    if IchaUIUF_PartySet and shown(party) then
        add("party", party, function()
            if IchaUIUF_PartySet then IchaUIUF_PartySet("move", true) end
        end, function()
            if IchaUIUF_PartySet then IchaUIUF_PartySet("move", false) end
        end)
    end
    local raid = getglobal("IchaUIUF_RaidRoot")
    if IchaUIUF_RaidSet and shown(raid) then
        add("raid", raid, function()
            if IchaUIUF_RaidSet then IchaUIUF_RaidSet("move", true) end
        end, function()
            if IchaUIUF_RaidSet then IchaUIUF_RaidSet("move", false) end
        end)
    end
    local combat = getglobal("IchaUICombatList")
    if IchaUI_CombatSet and shown(combat) then
        add("combat", combat, function()
            if IchaUI_CombatSet then IchaUI_CombatSet("move", true) end
        end, function()
            if IchaUI_CombatSet then IchaUI_CombatSet("move", false) end
        end)
    end
    local buff = getglobal("IchaUIBuffBar")
    if IchaUIBuffBars_Set and shown(buff) then
        add("buff", buff, function()
            if IchaUIBuffBars_Set then IchaUIBuffBars_Set("moving", true) end
        end, function()
            if IchaUIBuffBars_Set then IchaUIBuffBars_Set("moving", false) end
        end)
    end
    local debuff = getglobal("IchaUIDebuffBar")
    if IchaUIBuffBars_Set and shown(debuff) then
        add("debuff", debuff, function()
            if IchaUIBuffBars_Set then IchaUIBuffBars_Set("moving", true) end
        end, function()
            if IchaUIBuffBars_Set then IchaUIBuffBars_Set("moving", false) end
        end)
    end
    local totems = getglobal("IchaUITotemsRoot")
    if IchaUITotems_Set and IchaUI_IsShaman() and shown(totems) then
        add("totems", totems, function()
            if IchaUITotems_Set then IchaUITotems_Set("move", true) end
        end, function()
            if IchaUITotems_Set then IchaUITotems_Set("move", false) end
        end)
    end
    local extras = { "imbue", "shield", "utility" }
    local ei
    for ei = 1, table.getn(extras) do
        local which = extras[ei]
        local tag = "Shield"
        if which == "imbue" then tag = "Imbue" end
        if which == "utility" then tag = "Utility" end
        local fr = getglobal("IchaUI" .. tag .. "Root")
        if IchaUIShamanExtras_SetMove and IchaUI_IsShaman() and shown(fr) then
            local w = which
            add(w, fr, function()
                if IchaUIShamanExtras_SetMove then IchaUIShamanExtras_SetMove(w, true) end
            end, function()
                if IchaUIShamanExtras_SetMove then IchaUIShamanExtras_SetMove(w, false) end
            end)
        end
    end
    -- The Recall icon is created on demand and hidden until needed. With Recall
    -- on, edit mode still lists it so it can be moved and right-clicked.
    local recallOn = IchaUI_TotemRecallGet and IchaUI_TotemRecallGet()
    local recall = getglobal("IchaUITotemRecallIcon")
    if not recall and recallOn and IchaUI_TotemRecallIcon_ApplyPos then
        IchaUI_TotemRecallIcon_ApplyPos()
        recall = getglobal("IchaUITotemRecallIcon")
    end
    if IchaUI_TotemRecallIcon_ToggleMove and IchaUI_IsShaman() and recall and (shown(recall) or recallOn) then
        add("recall", recall, function()
            if IchaUI_TotemRecallIcon_Moving and not IchaUI_TotemRecallIcon_Moving() then
                if IchaUI_TotemRecallIcon_ToggleMove then IchaUI_TotemRecallIcon_ToggleMove() end
            end
        end, function()
            if IchaUI_TotemRecallIcon_Moving and IchaUI_TotemRecallIcon_Moving() then
                if IchaUI_TotemRecallIcon_ToggleMove then IchaUI_TotemRecallIcon_ToggleMove() end
            end
        end)
    end
    if Minimap and shown(Minimap) and IchaUIMinimap_Set then
        add("minimap", Minimap, function()
            local g = IchaUIMinimap_Get and IchaUIMinimap_Get()
            if g and not g.mapMoving then IchaUIMinimap_Set("move", true) end
        end, function()
            local g = IchaUIMinimap_Get and IchaUIMinimap_Get()
            if g and g.mapMoving then IchaUIMinimap_Set("move", true) end
        end)
    end
    local zone = getglobal("IchaUIMinimapZone")
    if shown(zone) and IchaUIMinimap_Set then
        add("zone", zone, function()
            local g = IchaUIMinimap_Get and IchaUIMinimap_Get()
            if g and not g.zoneMoving then IchaUIMinimap_Set("zoneMove", true) end
        end, function()
            local g = IchaUIMinimap_Get and IchaUIMinimap_Get()
            if g and g.zoneMoving then IchaUIMinimap_Set("zoneMove", true) end
        end)
    end
    local clock = getglobal("IchaUIMinimapClock")
    if shown(clock) and IchaUIMinimap_Set then
        add("clock", clock, function()
            local g = IchaUIMinimap_Get and IchaUIMinimap_Get()
            if g and not g.clockMoving then IchaUIMinimap_Set("clockMove", true) end
        end, function()
            local g = IchaUIMinimap_Get and IchaUIMinimap_Get()
            if g and g.clockMoving then IchaUIMinimap_Set("clockMove", true) end
        end)
    end
    if IchaUIMinimap_ListButtons and IchaUIMinimap_GetDrawer and IchaUIMinimap_SetButton and Minimap and shown(Minimap) then
        local list = IchaUIMinimap_ListButtons()
        local sample = list and list[1] and list[1].id
        if sample then
            add("mmicons", Minimap, function()
                local g = IchaUIMinimap_GetDrawer()
                if g and not g.moving then IchaUIMinimap_SetButton(sample, "move", true) end
            end, function()
                local g = IchaUIMinimap_GetDrawer()
                if g and g.moving then IchaUIMinimap_SetButton(sample, "move", true) end
            end)
        end
    end
    -- Tooltip anchor: an invisible frame, so it is listed whenever the custom
    -- anchor is on (cursor-follow ignores the box, so it is left out then).
    local tipCfg = IchaUI_TooltipAnchor_Get and IchaUI_TooltipAnchor_Get()
    if IchaUI_TooltipAnchor_SetMove and tipCfg and tipCfg.enabled and not tipCfg.cursor then
        add("tooltip", IchaUI_TooltipAnchor_Frame(), function()
            IchaUI_TooltipAnchor_SetMove(true)
        end, function()
            IchaUI_TooltipAnchor_SetMove(false)
        end)
    end
    local drawers = IchaUIDB and IchaUIDB.customDrawers
    if IchaUI_CustomDrawers_Apply and type(drawers) == "table" then
        local di
        for di = 1, table.getn(drawers) do
            local rec = drawers[di]
            if rec and rec.id and not rec.hidden then
                local btn = getglobal("IchaUICustomDrawer" .. tostring(rec.id))
                if shown(btn) then
                    local id = rec.id
                    add("cd" .. tostring(id), btn, function()
                        local b = getglobal("IchaUICustomDrawer" .. tostring(id))
                        if b and b.drawerUi then b.drawerUi.moving = true end
                    end, function()
                        local b = getglobal("IchaUICustomDrawer" .. tostring(id))
                        if b and b.drawerUi then b.drawerUi.moving = nil end
                    end)
                end
            end
        end
    end
end

local function unlockAll()
    local i
    for i = 1, table.getn(entries) do
        local e = entries[i]
        if e.unlock then e.unlock() end
        local bar = (string.sub(e.id, 1, 6) == "action") or (string.sub(e.id, 1, 4) == "hero")
        if not bar then
            addChip(e.frame, e.id, e.lock)
        end
    end
    showBarMovers()
end

local function stopForeign()
    local i
    for i = 1, table.getn(entries) do
        local e = entries[i]
        if e.lock then e.lock() end
    end
end

local SNAP_KEYS = {
    "layoutX", "layoutY", "barPlace", "xp", "buffBars", "uf", "totems",
    "shamanExtras", "minimap", "customDrawers", "combat", "heroExtras",
    "tooltip",
}

local function takeSnapshot()
    if not IchaUIDB then IchaUIDB = {} end
    snapshot = {}
    local i
    for i = 1, table.getn(SNAP_KEYS) do
        local k = SNAP_KEYS[i]
        snapshot[k] = copyTable(IchaUIDB[k])
    end
end

local function restoreSnapshot()
    if not snapshot or not IchaUIDB then return end
    local i
    for i = 1, table.getn(SNAP_KEYS) do
        local k = SNAP_KEYS[i]
        IchaUIDB[k] = copyTable(snapshot[k])
    end
end

local function reapply()
    if IchaUI_ReloadLayoutFromDB then IchaUI_ReloadLayoutFromDB() end
    if IchaUI_HeroReloadFromDB then IchaUI_HeroReloadFromDB() end
    if IchaUIXP_Reload then IchaUIXP_Reload() end
    if IchaUIBuffBars_Reload then IchaUIBuffBars_Reload() end
    if IchaUITotems_ReloadFromDB then IchaUITotems_ReloadFromDB() end
    if IchaUIMinimap_Reload then IchaUIMinimap_Reload() end
    if IchaUIShamanExtras_Apply then IchaUIShamanExtras_Apply() end
    if IchaUI_CustomDrawers_Apply then IchaUI_CustomDrawers_Apply() end
    if IchaUI_TotemRecallIcon_ApplyPos then IchaUI_TotemRecallIcon_ApplyPos() end
    if IchaUI_TooltipAnchor_Apply then IchaUI_TooltipAnchor_Apply() end
    if IchaUIUF_Get then
        local keys = { "player", "target", "tot", "focus" }
        local i
        for i = 1, table.getn(keys) do
            local fr = IchaUIUF_Get(keys[i])
            if fr and fr.applySaved then fr:applySaved() end
        end
    end
    if IchaUIUF_restorePartyRootPos then IchaUIUF_restorePartyRootPos() end
    if IchaUIUF_layoutParty then IchaUIUF_layoutParty() end
    if IchaUIUF_restoreRaidRootPos then IchaUIUF_restoreRaidRootPos() end
    if IchaUI_CombatPlaceRoot then IchaUI_CombatPlaceRoot() end
    if IchaUI_RequestLayout then IchaUI_RequestLayout() end
end

local function saveLiveDrag()
    if drag.mode == "cluster" then
        if IchaUI_SaveLayoutPos then IchaUI_SaveLayoutPos() end
        return
    end
    if drag.host and drag.kind and not drag.sticky then
        saveFree(drag.kind, drag.index, drag.host)
    end
end

local function settleUnits()
    local keys = { "target", "tot", "focus" }
    local i
    for i = 1, table.getn(keys) do
        local key = keys[i]
        if IchaUIUF_Set then IchaUIUF_Set(key, "move", false) end
        local fr = IchaUIUF_Get and IchaUIUF_Get(key)
        if fr then
            if fr.mover then fr.mover:Hide() end
            if fr.castMover then fr.castMover:Hide() end
            if fr.update then fr:update() end
        end
    end
end

local function shutdownUI()
    saveLiveDrag()
    editOn = false
    finishing = true
    drag.host = nil
    drag.mode = nil
    drag.sticky = nil
    drag.moved = nil
    if drag.internal then drag.internal = false end
    local root = IchaUI_LayoutRoot and IchaUI_LayoutRoot()
    if root and root.StopMovingOrSizing then root:StopMovingOrSizing() end
    hideBarMovers()
    hideChips()
    stopForeign()
    settleUnits()
    if IchaUI_SetClusterMove then IchaUI_SetClusterMove(false) end
    local c = ensureCatcher()
    c:Hide()
    finishing = false
end

endEdit = function(commit)
    if not editOn and not commit then return end
    local was = editOn
    if not was and not commit then return end
    shutdownUI()
    if IchaUI_RequestLayout then IchaUI_RequestLayout() end
    if commit or reopenConfig then
        if IchaUIOptions_Open then IchaUIOptions_Open() end
    end
end

function IchaUI_EditPositionsCancel()
    if not editOn then return end
    endEdit(false)
end

function IchaUI_EditPositions()
    if editOn then return end
    if IchaUI_SetClusterMove then IchaUI_SetClusterMove(false) end
    reopenConfig = false
    if IchaUIOptions and IchaUIOptions.IsShown and IchaUIOptions:IsShown() then
        reopenConfig = true
        IchaUIOptions:Hide()
    end
    editOn = true
    collectEntries()
    if IchaUI_RequestLayout then IchaUI_RequestLayout() end
    unlockAll()
    local c = ensureCatcher()
    c:Show()
    if countOpen() < 1 then
        endEdit(true)
    end
end
