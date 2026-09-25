-- Custom drawers. Contents come from the hero ability picker.
-- The closed button is only a toggle handle. Entries cast from their own click, then the tray closes.

local drawers = {}
local optionRefresh
local setOpen
local GOLD_R, GOLD_G, GOLD_B = 0.93, 0.78, 0.35
local RING_R, RING_G, RING_B = 0.75, 0.52, 0.04
local DISC = "Interface\\AddOns\\IchaUI\\media\\circledisc.tga"
local GOLD_RING = "Interface/Minimap/MiniMap-TrackingBorder"
local ROUNDMASK = "Interface/AddOns/IchaUI/media/roundmask-circle"
local CIRCLE = 36
local RECT_W, RECT_H = 40, 30
local CLOSE_DELAY = 0.35
local ICON_INSET_FRAC = 0.22

local function db()
    if not IchaUIDB then IchaUIDB = {} end
    if type(IchaUIDB.customDrawers) ~= "table" then IchaUIDB.customDrawers = {} end
    return IchaUIDB.customDrawers
end

local function findRec(id)
    local list = db()
    local i
    for i = 1, table.getn(list) do
        if list[i] and list[i].id == id then return list[i], i end
    end
    return nil, nil
end

local function normDir(d)
    if d == "down" or d == "left" or d == "right" or d == "up" or d == "radial" then return d end
    return "up"
end

local function shapeOf(rec)
    if rec and (rec.shape == "rect" or rec.shape == "square" or rec.shape == "circle" or rec.shape == "tooltip" or rec.shape == "portrait") then
        return rec.shape
    end
    if rec and IchaUI_FormShapeDef and IchaUI_FormShapeDef(rec.shape) then return rec.shape end
    return "circle"
end

local function measure(rec, s)
    if shapeOf(rec) == "rect" then
        return math.floor(RECT_W * s + 0.5), math.floor(RECT_H * s + 0.5)
    end
    local n = math.floor(CIRCLE * s + 0.5)
    if n < 8 then n = 8 end
    return n, n
end

local function buttonSize(rec)
    local s = 1
    if rec and rec.id and IchaUI_DrawerButtonScale then
        s = IchaUI_DrawerButtonScale("cd:" .. rec.id)
    end
    return measure(rec, s)
end

local function popSize(rec)
    local s = 1
    if rec and rec.id and IchaUI_DrawerPopScale then
        s = IchaUI_DrawerPopScale("cd:" .. rec.id)
    end
    return measure(rec, s)
end

local function useEntry(e)
    if not e or not e.spell or e.spell == "" then return end
    if e.kind == "macro" then
        if not GetMacroInfo or not RunMacro then return end
        local i
        for i = 1, 36 do
            local name = GetMacroInfo(i)
            if name and name == e.spell then
                RunMacro(i)
                return
            end
        end
        return
    end
    if e.kind == "item" then
        if not GetContainerNumSlots or not UseContainerItem then return end
        local b
        for b = 0, 4 do
            local slots = GetContainerNumSlots(b) or 0
            local s
            for s = 1, slots do
                local link = GetContainerItemLink(b, s)
                if link and string.find(link, e.spell, 1, true) then
                    UseContainerItem(b, s)
                    return
                end
            end
        end
        return
    end
    if not GetSpellName or not CastSpell then return end
    local i = 1
    while i <= 400 do
        local name = GetSpellName(i, BOOKTYPE_SPELL)
        if not name then return end
        if name == e.spell then
            CastSpell(i, BOOKTYPE_SPELL)
            return
        end
        i = i + 1
    end
end

local function nextId()
    local n = 1
    if IchaUIDB and tonumber(IchaUIDB.customDrawerSeq) then
        n = math.floor(tonumber(IchaUIDB.customDrawerSeq)) + 1
    end
    if not IchaUIDB then IchaUIDB = {} end
    IchaUIDB.customDrawerSeq = n
    return "cd" .. n
end

-- Screen offset from UIParent center, in the parent's scale.
-- Sample this while StartMoving is still active; StopMovingOrSizing can snap back to the old point.
local function centerOffset(btn)
    if not btn or not btn.GetCenter then return 0, 0 end
    local cx, cy = btn:GetCenter()
    if cx == nil or cy == nil then return 0, 0 end
    local rs = 1
    local us = 1
    if btn.GetEffectiveScale then rs = btn:GetEffectiveScale() or 1 end
    if UIParent and UIParent.GetEffectiveScale then us = UIParent:GetEffectiveScale() or 1 end
    if not us or us == 0 then us = 1 end
    local ux, uy = 0, 0
    if UIParent and UIParent.GetCenter then
        ux, uy = UIParent:GetCenter()
    end
    ux = ux or 0
    uy = uy or 0
    return (cx * rs - ux * us) / us, (cy * rs - uy * us) / us
end

local function pinCenter(btn, x, y)
    if not btn then return end
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", UIParent, "CENTER", x or 0, y or 0)
end

local function savePos(ui, ox, oy)
    local rec = findRec(ui.id)
    if not rec or not ui.btn then return end
    if ox == nil or oy == nil then
        ox, oy = centerOffset(ui.btn)
    end
    rec.x = math.floor((ox or 0) + 0.5)
    rec.y = math.floor((oy or 0) + 0.5)
    rec.point = "CENTER"
    rec.relPoint = "CENTER"
    pinCenter(ui.btn, rec.x, rec.y)
end

local function restorePos(btn, rec)
    if not btn or not rec then return end
    if btn.dragged then return end
    pinCenter(btn, tonumber(rec.x) or 0, tonumber(rec.y) or 0)
end

local function ensureParts(btn)
    if btn.cdParts then return end
    btn.cdParts = true
    local disc = btn:CreateTexture(nil, "BACKGROUND")
    disc:SetTexture(DISC)
    disc:SetVertexColor(0.05, 0.05, 0.06, 1)
    if disc.SetTexCoord then disc:SetTexCoord(0, 1, 0, 1) end
    btn.circleBg = disc
    local mask = btn:CreateTexture(nil, "ARTWORK")
    mask:SetTexture(ROUNDMASK)
    mask:SetVertexColor(0, 0, 0, 1)
    if mask.SetTexCoord then mask:SetTexCoord(0, 1, 0, 1) end
    btn.roundMask = mask
    local ring = btn:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(GOLD_RING)
    if ring.SetBlendMode then ring:SetBlendMode("BLEND") end
    if ring.SetTexCoord then ring:SetTexCoord(0, 1, 0, 1) end
    IchaUI_PaintGoldRing(ring)
    btn.goldRing = ring
    local border = CreateFrame("Frame", nil, btn)
    if border.EnableMouse then border:EnableMouse(false) end
    btn.rectBorder = border
end

local function hideCircle(btn)
    if btn.circleBg then btn.circleBg:Hide() end
    if btn.roundMask then btn.roundMask:Hide() end
    if btn.goldRing then btn.goldRing:Hide() end
end

local function hideRect(btn)
    local border = btn.rectBorder
    if not border then return end
    if border.SetBackdrop then border:SetBackdrop(nil) end
    border:Hide()
end

local function applyGoldRing(ring, parent, size)
    if not ring or not parent then return end
    local s = size or CIRCLE
    if s < 16 then s = 16 end
    local bw = math.floor(s * 1.65 + 0.5)
    ring:SetTexture(GOLD_RING)
    if ring.SetBlendMode then ring:SetBlendMode("BLEND") end
    if ring.SetTexCoord then ring:SetTexCoord(0, 1, 0, 1) end
    IchaUI_PaintGoldRing(ring)
    ring:ClearAllPoints()
    ring:SetWidth(bw)
    ring:SetHeight(bw)
    ring:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    ring:Show()
end

local function applyRectBorder(border, btn)
    if not border or not btn then return end
    local e = 12
    local o = 2
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", -o, o)
    border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", o, -o)
    border:SetBackdrop({
        bgFile = nil,
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = e,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    IchaUI_PaintGoldBorder(border, 1)
    if border.EnableMouse then border:EnableMouse(false) end
    border:Show()
end

local function pathish(tex)
    if type(tex) ~= "string" or tex == "" then return false end
    if string.find(tex, "/") then return true end
    if string.find(tex, "\\") then return true end
    return false
end

-- Same path the tray row uses. A spell name or a texture object that only
-- exists on the row is turned into a saved icon path before SetTexture.
local function resolveTexture(e, rowIcon)
    local tex = nil
    if e and type(e.texture) == "string" and e.texture ~= "" then
        tex = e.texture
    end
    if (not tex or tex == "") and rowIcon and rowIcon.GetTexture then
        local cur = rowIcon:GetTexture()
        if type(cur) == "string" and pathish(cur) then
            tex = cur
        end
    end
    if tex and not pathish(tex) then
        if not string.find(tex, " ") then
            tex = "Interface\\Icons\\" .. tex
        else
            tex = nil
        end
    end
    if not tex or tex == "" then
        tex = "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    return tex
end

local function applyShape(btn, rec, tray)
    if not btn then return end
    ensureParts(btn)
    if btn.SetBackdrop then btn:SetBackdrop(nil) end
    local w, h
    if tray then
        w, h = popSize(rec)
    else
        w, h = buttonSize(rec)
    end
    btn:SetWidth(w)
    btn:SetHeight(h)
    local icon = btn.icon
    if icon then
        if icon.SetDrawLayer then icon:SetDrawLayer("ARTWORK", 1) end
        if icon.SetVertexColor then icon:SetVertexColor(1, 1, 1) end
        if icon.SetAlpha then icon:SetAlpha(1) end
        icon:Show()
    end
    if btn.circleBg and btn.circleBg.SetDrawLayer then
        btn.circleBg:SetDrawLayer("BACKGROUND")
    end
    if shapeOf(rec) == "rect" then
        hideCircle(btn)
        if icon then
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
            icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
            local pad = 0.08
            local u0, u1 = pad, 1 - pad
            local v0, v1 = pad, 1 - pad
            if w > h and w > 0 then
                local span = u1 - u0
                local crop = (1 - (h / w)) / 2
                v0 = pad + crop * span
                v1 = 1 - pad - crop * span
            end
            icon:SetTexCoord(u0, u1, v0, v1)
        end
        applyRectBorder(btn.rectBorder, btn)
    elseif shapeOf(rec) == "square" then
        hideCircle(btn)
        hideRect(btn)
        if icon then
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 4, -4)
            icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -4, 4)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        if btn.SetBackdrop then btn:SetBackdrop(nil) end
    else
        hideRect(btn)
        local iconSz = math.floor(w * (1 - 2 * ICON_INSET_FRAC) + 0.5)
        if iconSz < 10 then iconSz = 10 end
        if icon then
            icon:ClearAllPoints()
            icon:SetWidth(iconSz)
            icon:SetHeight(iconSz)
            icon:SetPoint("CENTER", btn, "CENTER", 0, 2)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        if btn.circleBg and icon then
            btn.circleBg:SetTexture(DISC)
            btn.circleBg:SetVertexColor(0.05, 0.05, 0.06, 1)
            if btn.circleBg.SetTexCoord then btn.circleBg:SetTexCoord(0, 1, 0, 1) end
            btn.circleBg:ClearAllPoints()
            btn.circleBg:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
            btn.circleBg:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
            btn.circleBg:Show()
        end
        if btn.roundMask and icon then
            if btn.roundMask.SetDrawLayer then btn.roundMask:SetDrawLayer("ARTWORK", 2) end
            btn.roundMask:SetTexture(ROUNDMASK)
            btn.roundMask:SetVertexColor(0, 0, 0, 1)
            if btn.roundMask.SetTexCoord then btn.roundMask:SetTexCoord(0, 1, 0, 1) end
            btn.roundMask:ClearAllPoints()
            btn.roundMask:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
            btn.roundMask:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
            btn.roundMask:Show()
        end
        applyGoldRing(btn.goldRing, btn, w)
    end
    if IchaUI_WrapButtonIcon then IchaUI_WrapButtonIcon(btn) end
    if IchaUI_ApplyButtonForm then
        IchaUI_ApplyButtonForm(btn, shapeOf(rec))
    end
end

local function applyLabel(ui, rec)
    if not ui or not ui.nameFS or not ui.btn then return end
    local fs = ui.nameFS
    if rec and rec.showTitle == false then
        fs:Hide()
        return
    end
    fs:ClearAllPoints()
    if rec and rec.labelPos == "top" then
        fs:SetPoint("BOTTOM", ui.btn, "TOP", 0, 1)
    else
        fs:SetPoint("TOP", ui.btn, "BOTTOM", 0, -1)
    end
    fs:Show()
end

local function ensureItemCount(btn)
    if not btn or btn.countLayer then return end
    local layer = CreateFrame("Frame", nil, btn)
    layer:SetAllPoints(btn)
    if layer.EnableMouse then layer:EnableMouse(false) end
    btn.countLayer = layer
    local fs = layer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("RIGHT")
    fs:SetJustifyV("BOTTOM")
    btn.countFs = fs
end

local function paintItemCount(btn, entry, rec)
    if not btn then return end
    ensureItemCount(btn)
    local layer = btn.countLayer
    local fs = btn.countFs
    if not layer or not fs then return end
    local strata = "MEDIUM"
    if btn.GetFrameStrata then
        local s = btn:GetFrameStrata()
        if s and s ~= "" then strata = s end
    end
    pcall(function()
        layer:SetFrameStrata(strata)
        layer:SetFrameLevel((btn:GetFrameLevel() or 1) + 10)
    end)
    local isItem = entry and entry.kind == "item"
    local n = nil
    if isItem and IchaUI_BagItemCount then
        n = IchaUI_BagItemCount(entry.itemId, entry.spell)
    end
    if n == nil then
        fs:SetText("")
        fs:Hide()
        return
    end
    n = tonumber(n) or 0
    local anchor = btn.icon or btn
    fs:ClearAllPoints()
    fs:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -2, 2)
    local w = CIRCLE
    if btn and btn.GetWidth then
        w = btn:GetWidth() or CIRCLE
    elseif rec then
        w = buttonSize(rec)
    end
    local dfs = math.max(8, math.floor((tonumber(w) or CIRCLE) * 0.34 + 0.5))
    local fontPath = GameFontHighlightSmall:GetFont()
    if fontPath then
        fs:SetFont(fontPath, dfs, "THICKOUTLINE")
        if fs.SetShadowColor then
            fs:SetShadowColor(0, 0, 0, 1)
            fs:SetShadowOffset(1, -1)
        end
    end
    fs:SetText(tostring(n))
    if n <= 0 then
        fs:SetTextColor(1, 0.15, 0.15)
    else
        fs:SetTextColor(1, 0.92, 0.65)
    end
    fs:Show()
end

local function layoutTray(ui)
    local rec = findRec(ui.id)
    if not rec or not ui.tray or not ui.btn then return end
    local entries = rec.entries or {}
    local n = table.getn(entries)
    local cols = tonumber(rec.cols) or 1
    if cols < 1 then cols = 1 end
    if cols > 12 then cols = 12 end
    if tonumber(rec.rows) and tonumber(rec.rows) >= 1 and n > 0 then
        local rows = math.floor(tonumber(rec.rows))
        cols = math.floor((n + rows - 1) / rows)
        if cols < 1 then cols = 1 end
    end
    if rec.useCols and tonumber(rec.cols) and tonumber(rec.cols) >= 1 then
        cols = math.floor(tonumber(rec.cols))
    end
    if cols < 1 then cols = 1 end
    if cols > 12 then cols = 12 end
    local bw, bh = buttonSize(rec)
    local w, h = popSize(rec)
    local gap = 4
    local stepX = w + gap
    local stepY = h + gap
    local dir = normDir(rec.dir)
    local labelPad = 0
    if rec.showTitle ~= false then
        local th = tonumber(rec.textSize) or 11
        if th < 6 then th = 6 end
        if th > 28 then th = 28 end
        if (dir == "up" and rec.labelPos == "top") or (dir == "down" and rec.labelPos ~= "top") then
            labelPad = th + 4
        end
    end
    local i
    for i = 1, table.getn(ui.icons) do
        local btn = ui.icons[i]
        local e = entries[i]
        if e then
            btn.entry = e
            applyShape(btn, rec, true)
            if btn.icon then
                local tex = resolveTexture(e, btn.icon)
                e.texture = tex
                btn.icon:SetTexture(tex)
                btn.icon:Show()
                applyShape(btn, rec, true)
            end
            local idx = i - 1
            local col = math.mod(idx, cols)
            local row = math.floor(idx / cols)
            local x, y = 0, 0
            if dir == "radial" and IchaUI_DrawerRadialRadius and IchaUI_DrawerRadialXY then
                local radius = IchaUI_DrawerRadialRadius(n, bw, h, gap, rec.spread)
                x, y = IchaUI_DrawerRadialXY(i, n, radius, rec.arc, rec.rot)
            elseif dir == "right" then
                x = stepX * (row + 1)
                y = stepY * col
            elseif dir == "left" then
                x = -stepX * (row + 1)
                y = stepY * col
            elseif dir == "down" then
                y = -(stepY * (row + 1) + labelPad)
                x = stepX * col
            else
                y = stepY * (row + 1) + labelPad
                x = stepX * col
            end
            btn:ClearAllPoints()
            btn:SetPoint("CENTER", ui.btn, "CENTER", x, y)
            local lvl = ui.btn:GetFrameLevel() or 1
            btn:SetFrameLevel(lvl + 5)
            paintItemCount(btn, e, rec)
            btn:Show()
        else
            btn.entry = nil
            paintItemCount(btn, nil, rec)
            btn:Hide()
        end
    end
end

local function ensureIcons(ui, count)
    while table.getn(ui.icons) < count do
        local btn = CreateFrame("Button", nil, ui.tray)
        btn:SetWidth(CIRCLE)
        btn:SetHeight(CIRCLE)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn.drawerUi = ui
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon = icon
        btn:SetScript("OnClick", function()
            local owner = this.drawerUi
            if owner and owner.btn and (owner.btn.dragged or owner.btn.blockToggle) then return end
            if arg1 == "RightButton" then
                local rec = owner and findRec(owner.id)
                if rec and this.entry then
                    local tex = resolveTexture(this.entry, this.icon)
                    rec.activeSpell = this.entry.spell or ""
                    rec.activeKind = this.entry.kind or ""
                    rec.icon = tex
                    this.entry.texture = tex
                    if owner.btn then owner.btn.icon = owner.icon end
                    if owner.icon and owner.btn then
                        owner.icon:SetTexture(tex)
                        owner.icon:Show()
                        applyShape(owner.btn, rec)
                    end
                    paintItemCount(owner.btn, this.entry, rec)
                end
                if owner and setOpen then setOpen(owner, false) end
                return
            end
            if this.entry then useEntry(this.entry) end
            if owner and setOpen then setOpen(owner, false) end
        end)
        btn:SetScript("OnEnter", function()
            local owner = this.drawerUi
            if owner then owner.closeAt = nil end
            if this.entry and this.entry.spell and GameTooltip then
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetText(this.entry.spell, 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
            local owner = this.drawerUi
            if owner then
                owner.closeAt = (GetTime and GetTime() or 0) + CLOSE_DELAY
            end
        end)
        table.insert(ui.icons, btn)
    end
end

setOpen = function(ui, open)
    if not ui or not ui.tray then return end
    if open then
        ui.closeAt = nil
        local cur = findRec(ui.id)
        local n = 0
        if cur and cur.entries then n = table.getn(cur.entries) end
        ensureIcons(ui, n)
        layoutTray(ui)
        ui.tray:Show()
        ui.open = true
    else
        ui.open = false
        ui.closeAt = nil
        ui.tray:Hide()
        local i
        local icons = ui.icons or {}
        for i = 1, table.getn(icons) do
            icons[i]:Hide()
        end
    end
end

local function activeEntry(rec)
    if not rec then return nil end
    local entries = rec.entries or {}
    local n = table.getn(entries)
    if n < 1 then return nil end
    local want = rec.activeSpell
    local kind = rec.activeKind or ""
    if type(want) == "string" and want ~= "" then
        local i
        for i = 1, n do
            local e = entries[i]
            if e and e.spell == want and (e.kind or "") == kind then
                return e
            end
        end
    end
    return entries[1]
end

local function applyChrome(ui)
    local rec = findRec(ui.id)
    if not rec or not ui.btn then return end
    local strata = rec.strata
    if IchaUI_DrawerStyleGet then
        local saved = IchaUI_DrawerStyleGet("cd:" .. rec.id)
        if saved and saved ~= "" then strata = saved end
    end
    if not strata or strata == "" then strata = "MEDIUM" end
    pcall(function()
        ui.btn:SetFrameStrata(strata)
        ui.tray:SetFrameStrata(strata)
    end)
    local i
    for i = 1, table.getn(ui.icons) do
        pcall(function() ui.icons[i]:SetFrameStrata(strata) end)
    end
    local size = tonumber(rec.textSize) or 11
    if IchaUI_DrawerStyleGet then
        local _, savedSize = IchaUI_DrawerStyleGet("cd:" .. ui.id)
        if savedSize and savedSize >= 6 then size = savedSize end
    end
    if size < 6 then size = 6 end
    if size > 28 then size = 28 end
    rec.textSize = size
    if ui.nameFS then
        local fp = GameFontHighlightSmall:GetFont()
        if fp then ui.nameFS:SetFont(fp, size, "OUTLINE") end
        ui.nameFS:SetText(rec.name or "Drawer")
        IchaUI_PaintGoldFont(ui.nameFS, 0.93, 0.78, 0.35)
    end
    applyLabel(ui, rec)
    local shown = activeEntry(rec)
    local tex = nil
    if rec.activeSpell and rec.activeSpell ~= "" and shown and shown.spell == rec.activeSpell
        and shown.texture and shown.texture ~= "" then
        tex = resolveTexture(shown, nil)
    end
    if (not pathish(tex)) and rec.icon and rec.icon ~= "" then
        tex = resolveTexture({ texture = rec.icon }, nil)
    end
    if not pathish(tex) then
        tex = resolveTexture(shown, nil)
    end
    rec.icon = tex
    if ui.btn then ui.btn.icon = ui.icon end
    if ui.icon then
        ui.icon:SetTexture(tex)
        ui.icon:Show()
    end
    applyShape(ui.btn, rec)
    if ui.icon then
        ui.icon:SetTexture(tex)
        ui.icon:Show()
        applyShape(ui.btn, rec)
    end
    paintItemCount(ui.btn, activeEntry(rec), rec)
    if ui.open then layoutTray(ui) end
    if ui.labelFrame then
        pcall(function()
            ui.labelFrame:SetFrameStrata(strata)
            ui.labelFrame:SetFrameLevel((ui.btn:GetFrameLevel() or 1) + 30)
        end)
    end
    if rec.hidden then
        if ui.open and setOpen then setOpen(ui, false) end
        ui.btn:Hide()
    else
        ui.btn:Show()
    end
end

local function makeDrawer(rec)
    if drawers[rec.id] then return drawers[rec.id] end
    local btn = CreateFrame("Button", "IchaUICustomDrawer" .. rec.id, UIParent)
    btn:SetWidth(CIRCLE)
    btn:SetHeight(CIRCLE)
    btn:SetFrameStrata("MEDIUM")
    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp")
    if btn.SetBackdrop then btn:SetBackdrop(nil) end
    local icon = btn:CreateTexture(nil, "ARTWORK")
    if icon.SetDrawLayer then icon:SetDrawLayer("ARTWORK", 1) end
    icon:SetWidth(CIRCLE)
    icon:SetHeight(CIRCLE)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 2)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:Show()
    btn.icon = icon
    local labelFrame = CreateFrame("Frame", nil, btn)
    labelFrame:SetWidth(CIRCLE)
    labelFrame:SetHeight(CIRCLE)
    labelFrame:SetPoint("CENTER", btn, "CENTER", 0, 0)
    if labelFrame.EnableMouse then labelFrame:EnableMouse(false) end
    local nameFS = labelFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFS:SetJustifyH("CENTER")
    IchaUI_PaintGoldFont(nameFS, 0.93, 0.78, 0.35)
    local tray = CreateFrame("Frame", nil, btn)
    tray:SetWidth(8)
    tray:SetHeight(8)
    tray:SetPoint("CENTER", btn, "CENTER", 0, 0)
    if tray.EnableMouse then tray:EnableMouse(false) end
    tray:Hide()
    local ui = {
        id = rec.id, btn = btn, tray = tray, icons = {},
        icon = icon, nameFS = nameFS, labelFrame = labelFrame, open = false,
    }
    btn.drawerUi = ui
    btn:SetScript("OnMouseDown", function()
        if arg1 and arg1 ~= "LeftButton" then return end
        this.dragged = nil
        this.blockToggle = nil
        if GetCursorPosition then
            this.downX, this.downY = GetCursorPosition()
        end
    end)
    btn:SetScript("OnDragStart", function()
        if not ui.moving then return end
        this.dragged = true
        this:StartMoving()
    end)
    btn:SetScript("OnDragStop", function()
        local hadX = this:GetCenter()
        local ox, oy = centerOffset(this)
        this:StopMovingOrSizing()
        if hadX == nil then
            ox, oy = centerOffset(this)
        end
        local moved = true
        if this.downX ~= nil and GetCursorPosition then
            local cx, cy = GetCursorPosition()
            local dx = (cx or 0) - this.downX
            local dy = (cy or 0) - (this.downY or 0)
            if dx < 0 then dx = -dx end
            if dy < 0 then dy = -dy end
            if dx < 12 and dy < 12 then moved = false end
        end
        this.dragged = nil
        if moved then
            this.blockToggle = true
            savePos(ui, ox, oy)
        else
            this.blockToggle = nil
            local rec = findRec(ui.id)
            if rec then restorePos(ui.btn, rec) end
        end
    end)
    btn:SetScript("OnEnter", function()
        if this.dragged then return end
        local live = findRec(ui.id)
        if live and live.hidden then return end
        ui.closeAt = nil
        if setOpen then setOpen(ui, true) end
    end)
    btn:SetScript("OnLeave", function()
        if this.dragged then return end
        ui.closeAt = (GetTime and GetTime() or 0) + CLOSE_DELAY
    end)
    btn:SetScript("OnMouseUp", function()
        if arg1 == "RightButton" then
            if IchaUI_DrawerEditClick then IchaUI_DrawerEditClick("cd:" .. ui.id) end
            return
        end
        if arg1 and arg1 ~= "LeftButton" then return end
        if this.dragged or this.blockToggle then
            this.dragged = nil
            this.blockToggle = nil
        end
    end)
    pinCenter(btn, tonumber(rec.x) or 0, tonumber(rec.y) or 0)
    drawers[rec.id] = ui
    applyChrome(ui)
    return ui
end

function IchaUI_CustomDrawers_Apply()
    local list = db()
    local i
    for i = 1, table.getn(list) do
        local rec = list[i]
        if rec and rec.id then
            local ui = makeDrawer(rec)
            if ui and ui.btn then
                restorePos(ui.btn, rec)
                applyChrome(ui)
            end
        end
    end
end

function IchaUI_CustomDrawers_ApplyStyle(id)
    if not id then return end
    local prefix = string.sub(id, 1, 3)
    if prefix ~= "cd:" then return end
    local real = string.sub(id, 4)
    local ui = drawers[real]
    if ui then applyChrome(ui) end
end

function IchaUI_CustomDrawers_Delete(id)
    local rec, idx = findRec(id)
    if not rec then return end
    local ui = drawers[id]
    if ui then
        setOpen(ui, false)
        if ui.btn then ui.btn:Hide() end
        drawers[id] = nil
    end
    table.remove(db(), idx)
    if optionRefresh then optionRefresh() end
end

function IchaUI_CustomDrawers_Edit(id)
    local rec = findRec(id)
    if not rec or not IchaUI_HeroPicker_OpenDraft then return end
    IchaUI_HeroPicker_OpenDraft(rec.entries, function(copy)
        local live = findRec(id)
        if not live then return end
        live.entries = copy or {}
        if live.entries[1] and live.entries[1].texture then
            live.icon = live.entries[1].texture
        end
        local ui = drawers[id]
        if ui then
            applyChrome(ui)
            ensureIcons(ui, table.getn(live.entries))
            if ui.open then layoutTray(ui) end
        end
        if optionRefresh then optionRefresh() end
    end)
end

function IchaUI_CustomDrawers_Create(name, entries)
    local rec = {
        id = nextId(),
        name = name or "Drawer",
        x = 80,
        y = 80,
        point = "CENTER",
        relPoint = "CENTER",
        entries = entries or {},
        cols = 1,
        rows = 0,
        useCols = true,
        textSize = 11,
        strata = "MEDIUM",
        shape = "circle",
        dir = "up",
        showTitle = true,
        labelPos = "bottom",
    }
    if rec.name == "" then rec.name = "Drawer" end
    if rec.entries[1] and rec.entries[1].texture then
        rec.icon = rec.entries[1].texture
    end
    table.insert(db(), rec)
    makeDrawer(rec)
    if optionRefresh then optionRefresh() end
    return rec.id
end

local function refreshItemCounts()
    local id, ui
    for id, ui in pairs(drawers) do
        if ui and ui.btn then
            local rec = findRec(ui.id)
            paintItemCount(ui.btn, activeEntry(rec), rec)
            local icons = ui.icons or {}
            local i
            for i = 1, table.getn(icons) do
                local b = icons[i]
                if b then paintItemCount(b, b.entry, rec) end
            end
        end
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("BAG_UPDATE")
boot:SetScript("OnEvent", function()
    if event == "BAG_UPDATE" then
        refreshItemCounts()
        return
    end
    IchaUI_CustomDrawers_Apply()
end)
boot:SetScript("OnUpdate", function()
    local now = GetTime and GetTime() or 0
    local id, ui
    for id, ui in pairs(drawers) do
        if ui and ui.closeAt and now >= ui.closeAt then
            ui.closeAt = nil
            if ui.open and setOpen then setOpen(ui, false) end
        end
    end
end)

local function goldButton(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(w)
    b:SetHeight(h)
    b:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    b:SetBackdropColor(0.08, 0.08, 0.09, 0.9)
    IchaUI_PaintGoldLightBorder(b, 0.85)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    fs:SetText(text or "")
    IchaUI_PaintGoldFont(fs, 0.93, 0.78, 0.35)
    b.label = fs
    b:SetScript("OnClick", onClick)
    return b
end

local function shapeLabel(rec)
    if rec and rec.shape == "rect" then return "Shape: Rectangle" end
    if rec and rec.shape == "square" then return "Shape: Square" end
    if rec and rec.shape == "tooltip" then return "Shape: Tooltip Ring" end
    if rec and rec.shape == "portrait" then return "Shape: Portrait" end
    if rec and IchaUI_FormShapeDef and IchaUI_FormShapeDef(rec.shape) and IchaUI_FormShapeLabel then
        return "Shape: " .. IchaUI_FormShapeLabel(rec.shape)
    end
    return "Shape: Circle"
end

local function prettyDir(d)
    if d == "radial" then return "Radial" end
    if d == "right" then return "Right" end
    if d == "down" then return "Down" end
    if d == "left" then return "Left" end
    return "Up"
end

local function cycleDir(d)
    if d == "up" then return "right" end
    if d == "right" then return "down" end
    if d == "down" then return "left" end
    if d == "left" then return "radial" end
    return "up"
end

local function dirLabel(rec)
    return "Open: " .. prettyDir(normDir(rec and rec.dir))
end

local function titleLabel(rec)
    if rec and rec.showTitle == false then return "Title: Hide" end
    return "Title: Show"
end

local function labelPosLabel(rec)
    if rec and rec.labelPos == "top" then return "Label: Top" end
    return "Label: Bottom"
end

local function moveLabel(ui)
    if ui and ui.moving then return "Lock" end
    return "Move"
end

local function colsLabel(rec)
    local n = tonumber(rec and rec.cols) or 1
    n = math.floor(n)
    if n < 1 then n = 1 end
    return "Cols: " .. tostring(n)
end

local function rowsLabel(rec)
    local n = tonumber(rec and rec.rows) or 0
    n = math.floor(n)
    if n < 0 then n = 0 end
    return "Rows: " .. tostring(n)
end

local function dyeCfg(fs, r, g, b)
    if r == GOLD_R and g == GOLD_G and b == GOLD_B and IchaUI_PaintGoldFont then
        IchaUI_PaintGoldFont(fs, 0.93, 0.78, 0.35)
        return
    end
    if IchaUI_DyeFs then
        IchaUI_DyeFs(fs, r, g, b)
    elseif fs and fs.SetTextColor then
        fs:SetTextColor(r, g, b)
    end
end

local function refreshLive(id)
    local ui = drawers[id]
    if not ui then return end
    applyChrome(ui)
end

function IchaUI_CustomDrawers_RefreshOptions()
    if optionRefresh then optionRefresh() end
end

function IchaUI_BuildCustomDrawerOptions(parent, y, x)
    y = y or -4
    x = x or 10
    local head = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    head:SetText("Custom drawers")
    dyeCfg(head, GOLD_R, GOLD_G, GOLD_B)
    if IchaUI_OptNote then IchaUI_OptNote("Drawers", "Custom drawers", nil) end
    y = y - 18
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    hint:SetWidth(500)
    hint:SetJustifyH("LEFT")
    hint:SetText("Each drawer is one group. Move unlocks the closed button, Lock pins it. Show and Hide persist. Hover opens the tray. Left-click uses an entry. Right-click sets it on the button.")
    dyeCfg(hint, 0.82, 0.80, 0.72)
    y = y - 36

    local nameLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameLbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    nameLbl:SetText("Name")
    dyeCfg(nameLbl, 0.9, 0.88, 0.8)
    local nameBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    nameBox:SetWidth(140)
    nameBox:SetHeight(20)
    nameBox:SetPoint("LEFT", nameLbl, "RIGHT", 8, 0)
    nameBox:SetAutoFocus(false)
    if IchaUI_StyleInputBox then IchaUI_StyleInputBox(nameBox) end
    dyeCfg(nameBox, 1, 1, 1)
    nameBox:SetText("My drawer")
    local newBtn = goldButton(parent, "Pick abilities", 120, 20, function()
        local name = nameBox:GetText() or "Drawer"
        if not IchaUI_HeroPicker_OpenDraft then return end
        IchaUI_HeroPicker_OpenDraft({}, function(copy)
            IchaUI_CustomDrawers_Create(name, copy)
        end)
    end)
    newBtn:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    y = y - 28

    local host = CreateFrame("Frame", nil, parent)
    host:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    host:SetWidth(520)
    host:SetHeight(40)
    local function degSlider(row, key, label, x, y, lo, hi, fallback)
        local cap = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cap:SetPoint("TOPLEFT", row, "TOPLEFT", x, y)
        cap:SetText(label)
        if cap.SetFont and GameFontHighlightSmall.GetFont then
            local fp, fsz, fl = GameFontHighlightSmall:GetFont()
            if fp then cap:SetFont(fp, fsz or 10, fl or "") end
        end
        cap:SetTextColor(1, 1, 1)
        local sl = CreateFrame("Slider", nil, row, "OptionsSliderTemplate")
        sl:SetPoint("LEFT", cap, "RIGHT", 6, 0)
        sl:SetWidth(90)
        sl:SetHeight(16)
        sl:SetMinMaxValues(lo, hi)
        sl:SetValueStep(1)
        sl._key = key
        sl._fallback = fallback
        sl._busy = true
        sl:SetScript("OnValueChanged", function()
            if this._busy then return end
            local owner = this:GetParent()
            local live = owner and findRec(owner._id)
            if not live then return end
            local n = math.floor((this:GetValue() or this._fallback) + 0.5)
            if live[this._key] == n then return end
            live[this._key] = n
            refreshLive(owner._id)
        end)
        sl._busy = nil
        local regions = { sl:GetRegions() }
        local ri
        for ri = 1, table.getn(regions) do
            local r = regions[ri]
            if r and r.SetText and r.GetObjectType and r:GetObjectType() == "FontString" then
                r:SetText("")
                r:SetTextColor(1, 1, 1)
            end
        end
        return sl, cap
    end
    local baseY = y
    local rowById = {}

    local function clearRows()
        local id, row
        for id, row in pairs(rowById) do
            if row then row:Hide() end
        end
    end

    local function paint()
        clearRows()
        local list = db()
        local i
        local yy = 0
        for i = 1, table.getn(list) do
            local rec = list[i]
            if rec and rec.id then
                local rid = rec.id
                local row = rowById[rid]
                if not row then
                    row = CreateFrame("Frame", nil, host)
                    row:SetWidth(510)
                    row._id = rid
                    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
                    row.name:SetWidth(240)
                    row.name:SetJustifyH("LEFT")
                    dyeCfg(row.name, GOLD_R, GOLD_G, GOLD_B)
                    row.shape = goldButton(row, "Shape: Circle", 132, 18, function() end)
                    row.shape:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -20)
                    row.open = goldButton(row, "Open: Up", 100, 18, function() end)
                    row.open:SetPoint("LEFT", row.shape, "RIGHT", 4, 0)
                    row.spreadCap = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.spreadCap:SetPoint("LEFT", row.open, "RIGHT", 8, 0)
                    row.spreadCap:SetText("Spread")
                    if row.spreadCap.SetFont and GameFontHighlightSmall.GetFont then
                        local fp, fsz, fl = GameFontHighlightSmall:GetFont()
                        if fp then row.spreadCap:SetFont(fp, fsz or 10, fl or "") end
                    end
                    row.spreadCap:SetTextColor(1, 1, 1)
                    row.spread = CreateFrame("Slider", nil, row, "OptionsSliderTemplate")
                    row.spread:SetPoint("LEFT", row.spreadCap, "RIGHT", 4, 0)
                    row.spread:SetWidth(70)
                    row.spread:SetHeight(16)
                    row.spread:SetMinMaxValues(10, 360)
                    row.spread:SetValueStep(1)
                    row.spread._busy = true
                    row.spread:SetScript("OnValueChanged", function()
                        if this._busy then return end
                        local owner = this:GetParent()
                        local live = owner and findRec(owner._id)
                        if not live then return end
                        local n = this:GetValue() or 90
                        if IchaUI_DrawerNormSpread then n = IchaUI_DrawerNormSpread(n) end
                        if live.spread == n then return end
                        live.spread = n
                        refreshLive(owner._id)
                    end)
                    row.spread._busy = nil
                    do
                        local regions = { row.spread:GetRegions() }
                        local ri
                        for ri = 1, table.getn(regions) do
                            local r = regions[ri]
                            if r and r.SetText and r.GetObjectType and r:GetObjectType() == "FontString" then
                                r:SetText("")
                                r:SetTextColor(1, 1, 1)
                            end
                        end
                    end
                    row.title = goldButton(row, "Title: Show", 92, 18, function() end)
                    row.title:SetPoint("LEFT", row.spread, "RIGHT", 6, 0)
                    row.labelPos = goldButton(row, "Label: Bottom", 112, 18, function() end)
                    row.labelPos:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -42)
                    row.move = goldButton(row, "Move", 58, 18, function() end)
                    row.move:SetPoint("LEFT", row.labelPos, "RIGHT", 4, 0)
                    row.show = goldButton(row, "Show", 52, 18, function() end)
                    row.show:SetPoint("LEFT", row.move, "RIGHT", 4, 0)
                    row.hide = goldButton(row, "Hide", 52, 18, function() end)
                    row.hide:SetPoint("LEFT", row.show, "RIGHT", 4, 0)
                    row.edit = goldButton(row, "Edit", 52, 18, function() end)
                    row.edit:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -64)
                    row.del = goldButton(row, "Delete", 64, 18, function() end)
                    row.del:SetPoint("LEFT", row.edit, "RIGHT", 4, 0)
                    row.cols = goldButton(row, "Cols: 1", 72, 18, function() end)
                    row.cols:SetPoint("LEFT", row.del, "RIGHT", 4, 0)
                    row.rows = goldButton(row, "Rows: 0", 72, 18, function() end)
                    row.rows:SetPoint("LEFT", row.cols, "RIGHT", 4, 0)
                    row.arc, row.arcCap = degSlider(row, "arc", "Arc", 0, -86, 10, 360, 360)
                    row.rot, row.rotCap = degSlider(row, "rot", "Sh Rot", 220, -86, -360, 360, 90)
                    local bottom = -110
                    if IchaUI_DrawerStyleControls then
                        bottom = IchaUI_DrawerStyleControls(row, "cd:" .. rid, 0, -110)
                    end
                    local rh = -bottom + 6
                    if rh < 110 then rh = 110 end
                    row:SetHeight(rh)
                    row._h = rh
                    rowById[rid] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", host, "TOPLEFT", 0, yy)
                row.name:SetText(rec.name or rid)
                dyeCfg(row.name, GOLD_R, GOLD_G, GOLD_B)
                if row.shape.label then row.shape.label:SetText(shapeLabel(rec)) end
                if row.open.label then row.open.label:SetText(dirLabel(rec)) end
                if row.spread then
                    local sp = 90
                    if IchaUI_DrawerNormSpread then sp = IchaUI_DrawerNormSpread(rec.spread) end
                    local showSp = normDir(rec.dir) == "radial"
                    if showSp then row.spread:Show() else row.spread:Hide() end
                    if row.spreadCap then
                        if showSp then row.spreadCap:Show() else row.spreadCap:Hide() end
                    end
                    row.spread._busy = true
                    row.spread:SetValue(sp)
                    row.spread._busy = nil
                end
                local function paintDeg(sl, cap, value)
                    if not sl then return end
                    local showSp = normDir(rec.dir) == "radial"
                    if showSp then sl:Show() else sl:Hide() end
                    if cap then
                        if showSp then cap:Show() else cap:Hide() end
                    end
                    sl._busy = true
                    sl:SetValue(value)
                    sl._busy = nil
                end
                local arcV = 360
                if IchaUI_DrawerNormArc then arcV = IchaUI_DrawerNormArc(rec.arc) end
                paintDeg(row.arc, row.arcCap, arcV)
                local rotV = 90
                if IchaUI_DrawerNormRot then rotV = IchaUI_DrawerNormRot(rec.rot) end
                paintDeg(row.rot, row.rotCap, rotV)
                if row.title.label then row.title.label:SetText(titleLabel(rec)) end
                if row.labelPos.label then row.labelPos.label:SetText(labelPosLabel(rec)) end
                local liveUi = drawers[rid]
                if row.move.label then row.move.label:SetText(moveLabel(liveUi)) end
                if row.cols.label then row.cols.label:SetText(colsLabel(rec)) end
                if row.rows.label then row.rows.label:SetText(rowsLabel(rec)) end
                row.shape:SetScript("OnClick", function()
                    local live = findRec(rid)
                    if not live then return end
                    if IchaUI_FormShapeNext then
                        live.shape = IchaUI_FormShapeNext(live.shape or "circle")
                    elseif live.shape == "rect" then
                        live.shape = "square"
                    elseif live.shape == "square" then
                        live.shape = "circle"
                    else
                        live.shape = "rect"
                    end
                    if this.label then this.label:SetText(shapeLabel(live)) end
                    refreshLive(rid)
                end)
                row.open:SetScript("OnClick", function()
                    local live = findRec(rid)
                    if not live then return end
                    live.dir = cycleDir(normDir(live.dir))
                    if this.label then this.label:SetText(dirLabel(live)) end
                    local row = this:GetParent()
                    if row and row.spread then
                        local on = normDir(live.dir) == "radial"
                        local function vis(w, show)
                            if not w then return end
                            if show then w:Show() else w:Hide() end
                        end
                        vis(row.spread, on)
                        vis(row.spreadCap, on)
                        vis(row.arc, on)
                        vis(row.arcCap, on)
                        vis(row.rot, on)
                        vis(row.rotCap, on)
                    end
                    refreshLive(rid)
                end)
                if IchaUI_ShapeDropdown then
                    IchaUI_ShapeDropdown(row.shape, function()
                        return shapeOf(findRec(rid))
                    end)
                end
                if IchaUI_StepDropdown then
                    IchaUI_StepDropdown(row.open, IchaUI_DIR_OPTS, function()
                        local live = findRec(rid)
                        return live and normDir(live.dir)
                    end, function(v)
                        local live = findRec(rid)
                        if live then live.dir = v end
                    end)
                end
                row.title:SetScript("OnClick", function()
                    local live = findRec(rid)
                    if not live then return end
                    if live.showTitle == false then
                        live.showTitle = true
                    else
                        live.showTitle = false
                    end
                    if this.label then this.label:SetText(titleLabel(live)) end
                    refreshLive(rid)
                end)
                row.labelPos:SetScript("OnClick", function()
                    local live = findRec(rid)
                    if not live then return end
                    if live.labelPos == "top" then
                        live.labelPos = "bottom"
                    else
                        live.labelPos = "top"
                    end
                    if this.label then this.label:SetText(labelPosLabel(live)) end
                    refreshLive(rid)
                end)
                row.move:SetScript("OnClick", function()
                    local ui = drawers[rid]
                    if not ui then
                        local live = findRec(rid)
                        if live then ui = makeDrawer(live) end
                    end
                    if not ui then return end
                    if ui.moving then ui.moving = nil else ui.moving = true end
                    if this.label then this.label:SetText(moveLabel(ui)) end
                end)
                row.show:SetScript("OnClick", function()
                    local live = findRec(rid)
                    if not live then return end
                    live.hidden = false
                    refreshLive(rid)
                end)
                row.hide:SetScript("OnClick", function()
                    local live = findRec(rid)
                    if not live then return end
                    live.hidden = true
                    refreshLive(rid)
                end)
                row.edit:SetScript("OnClick", function()
                    IchaUI_CustomDrawers_Edit(rid)
                end)
                row.del:SetScript("OnClick", function()
                    IchaUI_CustomDrawers_Delete(rid)
                end)
                row.cols:SetScript("OnClick", function()
                    local live = findRec(rid)
                    if not live then return end
                    local n = math.floor((tonumber(live.cols) or 1) + 1)
                    if n > 12 then n = 1 end
                    if n < 1 then n = 1 end
                    live.cols = n
                    live.useCols = true
                    if this.label then this.label:SetText(colsLabel(live)) end
                    refreshLive(rid)
                end)
                row.rows:SetScript("OnClick", function()
                    local live = findRec(rid)
                    if not live then return end
                    local n = math.floor((tonumber(live.rows) or 0) + 1)
                    if n > 20 then n = 0 end
                    if n < 0 then n = 0 end
                    live.rows = n
                    if n >= 1 then live.useCols = nil else live.useCols = true end
                    if this.label then this.label:SetText(rowsLabel(live)) end
                    refreshLive(rid)
                end)
                row:Show()
                local step = row._h or 120
                yy = yy - step - 8
            end
        end
        local h = -yy
        if h < 24 then h = 24 end
        host:SetHeight(h)
        local need = -(baseY - h) + 48
        if parent.GetHeight and (parent:GetHeight() or 0) < need then
            parent:SetHeight(need)
        end
    end
    optionRefresh = paint
    paint()
    y = y - host:GetHeight() - 12
    local need = -y + 40
    if parent.GetHeight and (parent:GetHeight() or 0) < need then
        parent:SetHeight(need)
    end
    return y
end
