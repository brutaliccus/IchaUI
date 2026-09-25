-- Combat tab: click-to-dispel rows, Smart Dispel order and binds.
-- h = { sectionHeader, tip, makeButton, makeGoldToggle, paintGoldToggle, makeKeyBindRow }
-- Fits in 540 x 290 from (x, y). Returns a refresh function.

local ROW_LABEL = {
    Magic = "Magic", Curse = "Curse", Poison = "Poison", Disease = "Disease",
    Offensive = "Enemy (offensive)", Smart = "Smart dispel",
}

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local SMART_ICON = "Interface\\Icons\\Spell_Holy_DispelMagic"

function IchaUI_BuildDispelOptions(page, x, y, h)
    if not page or not h or not IchaUI_DispelDB then return function() end end
    local refreshers = {}
    local function add(fn) table.insert(refreshers, fn) end
    local function refreshAll()
        local i
        for i = 1, table.getn(refreshers) do refreshers[i]() end
    end

    h.sectionHeader(page, "Click to dispel", x, y)
    local onBtn = h.makeGoldToggle(page, "Dispel clicks: On", 130, 18)
    onBtn:SetPoint("TOPLEFT", page, "TOPLEFT", x + 150, y + 2)
    onBtn:SetScript("OnClick", function()
        IchaUI_Dispel_SetEnabled(not IchaUI_DispelDB().enabled)
        refreshAll()
    end)
    add(function()
        local on = IchaUI_DispelDB().enabled
        onBtn._label:SetText(on and "Dispel clicks: On" or "Dispel clicks: Off")
        h.paintGoldToggle(onBtn, on)
    end)
    y = y - 24

    local function modOpts(button)
        local out = {}
        local i
        for i = 1, table.getn(IchaUI_DISPEL_MODS) do
            local m = IchaUI_DISPEL_MODS[i]
            if not (m[1] == "NONE" and (button == "LeftButton" or button == "RightButton")) then
                table.insert(out, { m[1], m[2] })
            end
        end
        return out
    end

    local function pickIndex(opts, value)
        local i
        for i = 1, table.getn(opts) do
            if opts[i][1] == value then return i end
        end
        return 0
    end

    local function makeRow(action, ry)
        local icon = page:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(16)
        icon:SetHeight(16)
        icon:SetPoint("TOPLEFT", page, "TOPLEFT", x, ry - 2)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local name = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetPoint("TOPLEFT", page, "TOPLEFT", x + 20, ry - 4)
        name:SetWidth(150)
        name:SetJustifyH("LEFT")

        local btn = h.makeButton(page, "Left", 84, 20, function()
            local opts = IchaUI_DISPEL_BUTTONS
            local c = IchaUI_DispelDB().clicks[action]
            IchaUI_ChoiceMenu(this, opts, pickIndex(opts, c.button), function(i)
                if opts[i] then IchaUI_Dispel_SetClick(action, "button", opts[i][1]) end
                refreshAll()
            end)
        end)
        btn:SetPoint("TOPLEFT", page, "TOPLEFT", x + 174, ry)
        if IchaUI_ChoiceArrow then IchaUI_ChoiceArrow(btn) end

        local mod = h.makeButton(page, "Shift", 104, 20, function()
            local c = IchaUI_DispelDB().clicks[action]
            local opts = modOpts(c.button)
            IchaUI_ChoiceMenu(this, opts, pickIndex(opts, c.mod), function(i)
                if opts[i] then IchaUI_Dispel_SetClick(action, "mod", opts[i][1]) end
                refreshAll()
            end)
        end)
        mod:SetPoint("LEFT", btn, "RIGHT", 4, 0)
        if IchaUI_ChoiceArrow then IchaUI_ChoiceArrow(mod) end

        local warn = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        warn:SetPoint("LEFT", mod, "RIGHT", 6, 0)
        warn:SetWidth(170)
        warn:SetJustifyH("LEFT")

        add(function()
            local c = IchaUI_DispelDB().clicks[action]
            local spell = nil
            if action ~= "Smart" then spell = IchaUI_Dispel_SpellFor(action) end
            local knownRow = IchaUI_Dispel_ActionKnown(action)
            if action == "Smart" then
                icon:SetTexture(SMART_ICON)
            else
                icon:SetTexture((spell and IchaUI_Dispel_SpellIcon(spell)) or FALLBACK_ICON)
            end
            local label = ROW_LABEL[action] or action
            if spell then
                local pet = IchaUI_Dispel_IsPetSpell(spell) and " (pet)" or ""
                label = label .. ": " .. spell .. pet
            elseif action ~= "Smart" then
                label = label .. ": not known"
            end
            name:SetText(label)
            if knownRow then
                IchaUI_DyeFs(name, 1, 1, 1)
                icon:SetVertexColor(1, 1, 1)
            else
                IchaUI_DyeFs(name, 0.55, 0.55, 0.55)
                icon:SetVertexColor(0.4, 0.4, 0.4)
            end
            btn:SetText(IchaUI_Dispel_ButtonLabel(c.button))
            mod:SetText(IchaUI_Dispel_ModLabel(c.mod))
            if c.button == "OFF" then mod:Hide() else mod:Show() end
            local w = nil
            if knownRow then w = IchaUI_Dispel_Conflict(action) end
            warn:SetText(w or "")
            IchaUI_DyeFs(warn, 1, 0.72, 0.3)
        end)
    end

    local i
    for i = 1, table.getn(IchaUI_DISPEL_ACTIONS) do
        makeRow(IchaUI_DISPEL_ACTIONS[i], y)
        y = y - 22
    end
    y = y - 6

    -- Smart order (left) and binds (right)
    local oy = y
    local head = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("TOPLEFT", page, "TOPLEFT", x, oy)
    head:SetText("Smart order")
    IchaUI_PaintGoldFont(head, 0.93, 0.78, 0.35)
    oy = oy - 18
    local slot
    for slot = 1, 4 do
        local idx = slot
        local fs = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", page, "TOPLEFT", x + 4, oy - 3)
        fs:SetWidth(90)
        fs:SetJustifyH("LEFT")
        local up = h.makeButton(page, "^", 20, 16, function()
            IchaUI_Dispel_MoveOrder(idx, -1)
            refreshAll()
        end)
        up:SetPoint("TOPLEFT", page, "TOPLEFT", x + 100, oy)
        local down = h.makeButton(page, "v", 20, 16, function()
            IchaUI_Dispel_MoveOrder(idx, 1)
            refreshAll()
        end)
        down:SetPoint("LEFT", up, "RIGHT", 2, 0)
        if idx == 1 then up:Hide() end
        if idx == 4 then down:Hide() end
        add(function()
            local t = IchaUI_DispelDB().order[idx] or "?"
            fs:SetText(idx .. ". " .. t)
            if IchaUI_Dispel_SpellFor(t) then
                IchaUI_DyeFs(fs, 1, 1, 1)
            else
                IchaUI_DyeFs(fs, 0.55, 0.55, 0.55)
            end
        end)
        oy = oy - 19
    end

    local by = y
    local bx = x + 170
    local bhead = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bhead:SetPoint("TOPLEFT", page, "TOPLEFT", bx, by)
    bhead:SetText("Smart Dispel binds")
    IchaUI_PaintGoldFont(bhead, 0.93, 0.78, 0.35)
    by = by - 18
    local b
    for b = 1, table.getn(IchaUI_DISPEL_BINDS) do
        local cmd = IchaUI_DISPEL_BINDS[b][1]
        local row = h.makeKeyBindRow(page, IchaUI_DISPEL_BINDS[b][2], bx, by - 3,
            function() return IchaUI_Dispel_GetBindKey(cmd) end,
            function(key) IchaUI_Dispel_SetBindKey(cmd, key) end)
        if row.label then IchaUI_DyeFs(row.label, 1, 1, 1) end
        if row.button then
            local kb = row.button
            local capture = kb:GetScript("OnClick")
            kb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            kb:SetScript("OnClick", function()
                if arg1 == "RightButton" then
                    IchaUI_Dispel_SetBindKey(cmd, nil)
                    row.refresh()
                    return
                end
                if capture then capture() end
            end)
        end
        add(row.refresh)
        by = by - 20
    end

    local ty = oy - 4
    if by - 4 < ty then ty = by - 4 end
    h.tip(page, "Works on every IchaUI unit frame. Friendly rows fire only when that debuff is on the unit; the enemy row and Smart on an enemy use the offensive dispel. Smart picks the first school in Smart order. Right-click a bind to clear it.", x, ty, 530)

    IchaUI_DispelOptionsRefresh = function()
        if page.IsVisible and page:IsVisible() then refreshAll() end
    end
    refreshAll()
    return refreshAll
end
