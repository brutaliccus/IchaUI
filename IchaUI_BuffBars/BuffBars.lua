-- IchaUI player buff / debuff bars (minimap-style, action-bar chrome)
-- Rectangular icons + gold border + roundmask; duration under; stacks bottom-right.

-- Default buff border: circle-button gold on the white tooltip edge.
local GOLD = { 0.75, 0.52, 0.04, 1 }
local ROUNDMASK = "Interface\\AddOns\\IchaUI\\media\\roundmask.tga"
local BASE_W, BASE_H = 40, 30 -- same 4:3 as action bars (Layout.lua)
local DEFAULT_SCALE = 0.9000000357627869
local DEFAULT_GAP = 2.5
local DEFAULT_ROW_GAP = 0
local DEFAULT_COLS = 16
local MAX_ICONS = 48 -- 3 rows × 16 cols

local cfgScale, cfgGap, cfgRowGap, cfgCols = DEFAULT_SCALE, DEFAULT_GAP, DEFAULT_ROW_GAP, DEFAULT_COLS
local cfgText = 8
local moving = false

local buffRoot, debuffRoot
local buffIcons, debuffIcons = {}, {}
local moverBuff, moverDebuff

local function db()
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.buffBars then IchaUIDB.buffBars = {} end
    return IchaUIDB.buffBars
end

-- Retail-style consolidated buffs: helpful auras >= 10 min (or until cancelled)
-- hide in one drawer slot. New keys on IchaUIDB.buffBars only.
local LONG_SECS = 600
local ARROW_TEX = "Interface\\AddOns\\IchaUI\\media\\Arrow-Left-Up.tga"
local CONS_ICON_CLOSED = "Interface\\AddOns\\IchaUI_BuffBars\\media\\ConsolidatedBuffs-Closed.tga"
local CONS_ICON_OPEN = "Interface\\AddOns\\IchaUI_BuffBars\\media\\ConsolidatedBuffs-Open.tga"
local consUI = { icons = {}, grace = 0 }

local function consIcon(open)
    if open then return CONS_ICON_OPEN end
    return CONS_ICON_CLOSED
end

local function consolidateOn()
    if db().consolidate == false then return false end
    return true
end

local function consolidateOpen()
    return db().consolidatedExpanded and true or false
end

-- Session snapshots of starting duration, keyed by folded buff name (or texture).
-- Persisted in IchaUIDB.buffBars.baseDur so a /reload mid-buff keeps the start time.
local baseSeen = {}
local nameByTex = {}

local function foldName(s)
    if not s or s == "" then return "" end
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    s = string.gsub(s, "%s+", " ")
    return string.lower(s)
end

local function nameList(which)
    local d = db()
    local key = "neverConsolidate"
    if which == "always" then key = "alwaysConsolidate" end
    if type(d[key]) ~= "table" then d[key] = {} end
    return d[key]
end

local function listHas(which, name)
    local fold = foldName(name)
    if fold == "" then return false end
    local list = nameList(which)
    local i
    for i = 1, table.getn(list) do
        if foldName(list[i]) == fold then return true end
    end
    return false
end

local function auraKey(e)
    if e and e.name and e.name ~= "" then return foldName(e.name) end
    if e and e.texture then return string.lower(e.texture) end
    return "i:" .. tostring(e and e.index or "")
end

local function persistBase()
    local d = db()
    if type(d.baseDur) ~= "table" then d.baseDur = {} end
    return d.baseDur
end

local function snapBase(e)
    local key = auraKey(e)
    local left = e.timeLeft
    if not left then left = 0 end
    local rec = baseSeen[key]
    local store = persistBase()
    if not rec or not rec.live then
        if rec and not rec.live then
            rec.base = left
        elseif store[key] and left > 0 and store[key] > 0 and left <= (store[key] + 1) then
            rec = { base = store[key], last = left, live = true }
        else
            rec = { base = left, last = left, live = true }
        end
        rec.last = left
        rec.live = true
        baseSeen[key] = rec
    else
        if left > rec.last + 0.5 then
            rec.base = left
        elseif left > rec.base then
            rec.base = left
        end
        rec.last = left
        rec.live = true
    end
    store[key] = rec.base
    e.baseDur = rec.base
end

local function shouldConsolidate(e)
    if not e then return false end
    if listHas("never", e.name) then return false end
    if listHas("always", e.name) then return true end
    local left = e.timeLeft
    if not left or left <= 0 then return true end
    local base = e.baseDur
    if not base then base = left end
    if base <= 0 then return true end
    return base >= LONG_SECS
end

local function iconW()
    return math.floor(BASE_W * cfgScale + 0.5)
end
local function iconH()
    return math.floor(BASE_H * cfgScale + 0.5)
end

local function formatDur(sec)
    if not sec or sec <= 0 then return "" end
    if sec >= 3600 then
        return string.format("%dh", math.floor(sec / 3600 + 0.5))
    end
    if sec >= 60 then
        return string.format("%dm", math.floor(sec / 60 + 0.5))
    end
    if sec >= 10 then
        return string.format("%d", math.floor(sec + 0.5))
    end
    return string.format("%.1f", sec)
end

-- Debuff-type border colors (poison / disease / magic / curse / bleed)
local DTYPE_RGB = {
    poison  = { 0.15, 0.90, 0.20, 1 },
    disease = { 0.95, 0.88, 0.10, 1 },
    magic   = { 0.25, 0.50, 1.00, 1 },
    curse   = { 0.72, 0.28, 0.95, 1 },
    bleed   = { 0.95, 0.12, 0.12, 1 },
}

-- Physical bleeds have no dispel type — match common 1.12 names
local BLEED_NAMES = {
    ["rend"] = true, ["deep wounds"] = true, ["rupture"] = true,
    ["garrote"] = true, ["rip"] = true, ["rake"] = true,
    ["pounce"] = true, ["hemorrhage"] = true, ["gouge"] = false,
    ["blood frenzy"] = true, ["crippling poison"] = false,
}
local function isBleedName(name)
    if not name or name == "" then return false end
    local low = string.lower(name)
    if BLEED_NAMES[low] then return true end
    if string.find(low, "bleed", 1, true) then return true end
    if string.find(low, "wound", 1, true) and not string.find(low, "poison", 1, true) then
        return true
    end
    return false
end

local dtypeTip = CreateFrame("GameTooltip", "IchaUIBuffDtypeTip", UIParent, "GameTooltipTemplate")
dtypeTip:SetOwner(UIParent, "ANCHOR_NONE")

local function nameFromPlayerBuff(buffId)
    if not buffId or buffId < 0 then return nil end
    dtypeTip:ClearLines()
    if not pcall(function() dtypeTip:SetPlayerBuff(buffId) end) then return nil end
    local fs = getglobal("IchaUIBuffDtypeTipTextLeft1")
    local t = fs and fs:GetText()
    if t and t ~= "" then return t end
    return nil
end

local function auraName(id)
    if type(GetPlayerBuffName) == "function" then
        local ok, n = pcall(GetPlayerBuffName, id)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    return nameFromPlayerBuff(id)
end

local function resolveDebuffDtype(buffId)
    -- Official dispel school (Magic / Curse / Disease / Poison)
    if type(GetPlayerBuffDispelType) == "function" then
        local ok, t = pcall(GetPlayerBuffDispelType, buffId)
        if ok and type(t) == "string" and t ~= "" then
            return string.lower(t)
        end
    end
    -- Bleed / physical: no dispel type — sniff the buff name
    local nm = nameFromPlayerBuff(buffId)
    if isBleedName(nm) then return "bleed" end
    return nil
end

local function rgbaForDtype(dtype)
    if dtype and DTYPE_RGB[dtype] then return DTYPE_RGB[dtype] end
    return GOLD
end

-- texture -> stack count from UnitBuff/UnitDebuff this refresh.
-- Counts equal to the 1-based index are the slot, not charges, and are skipped.
local function stackMap(filter)
    local map = {}
    local fn = UnitBuff
    if filter == "HARMFUL" then fn = UnitDebuff end
    if type(fn) ~= "function" then return map end
    local i
    for i = 1, 40 do
        local a1, a2, a3, a4 = fn("player", i)
        if not a1 then break end
        local tex, stacks
        if type(a1) == "string" and string.find(string.lower(a1), "interface", 1, true) then
            tex = a1
            stacks = tonumber(a2)
        elseif type(a3) == "string" and string.find(string.lower(a3), "interface", 1, true) then
            tex = a3
            stacks = tonumber(a4)
            if not stacks then stacks = tonumber(a2) end
        end
        if tex and stacks and stacks > 1 and stacks ~= i then
            map[tex] = stacks
        end
    end
    return map
end

local function writeStack(btn, count, auraKey)
    if not btn or not btn.stack then return end
    count = tonumber(count) or 0
    if count < 0 then count = 0 end
    -- Aura in this slot changed: drop the previous number before writing the new one.
    if auraKey ~= btn._auraKey then
        btn.stack:SetText("")
        btn.stack:Hide()
        btn._auraKey = auraKey
    end
    if count > 1 or (btn.consolidated and count > 0 and not btn._consOpen) then
        btn.stack:ClearAllPoints()
        btn.stack:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
        btn.stack:SetText(tostring(math.floor(count)))
        btn.stack:Show()
    else
        btn.stack:SetText("")
        btn.stack:Hide()
    end
end

local function applyBorder(border, edge, dtype)
    local c = rgbaForDtype(dtype)
    border:SetBackdrop({
        bgFile = nil,
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = edge or 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    border:SetBackdropColor(0, 0, 0, 0)
    if c == GOLD then
        local r, g, b = 0.75, 0.52, 0.04
        if IchaUI_Gold then r, g, b = IchaUI_Gold() end
        border:SetBackdropBorderColor(r, g, b, c[4] or 1)
    else
        border:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
    end
end

local function applyGold(border, edge)
    applyBorder(border, edge, nil)
end

local function loadCfg()
    local d = db()
    if d.scale then cfgScale = tonumber(d.scale) or DEFAULT_SCALE end
    if d.gap then cfgGap = tonumber(d.gap) or DEFAULT_GAP end
    if d.rowGap then cfgRowGap = tonumber(d.rowGap) or DEFAULT_ROW_GAP end
    if d.cols then cfgCols = tonumber(d.cols) or DEFAULT_COLS end
    if d.text then cfgText = tonumber(d.text) or 8 end
    if cfgScale < 0.4 then cfgScale = 0.4 end
    if cfgScale > 2.5 then cfgScale = 2.5 end
    if cfgGap < 0 then cfgGap = 0 end
    if cfgRowGap < 0 then cfgRowGap = 0 end
    if cfgRowGap > 40 then cfgRowGap = 40 end
    if cfgCols < 4 then cfgCols = 4 end
    if cfgCols > 16 then cfgCols = 16 end
end

local function saveCfg()
    local d = db()
    d.scale = cfgScale
    d.gap = cfgGap
    d.rowGap = cfgRowGap
    d.cols = cfgCols
    d.text = cfgText
    if d.consolidate == nil then d.consolidate = true end
    if d.consolidatedExpanded == nil then d.consolidatedExpanded = false end
    if buffRoot then
        local p, _, rp, x, y = buffRoot:GetPoint(1)
        d.buffPoint, d.buffRel, d.buffX, d.buffY = p, rp, x, y
    end
    if debuffRoot then
        local p, _, rp, x, y = debuffRoot:GetPoint(1)
        d.debuffPoint, d.debuffRel, d.debuffX, d.debuffY = p, rp, x, y
    end
end

local function hideBlizzardBuffs()
    if BuffFrame then
        BuffFrame:UnregisterAllEvents()
        BuffFrame:Hide()
        BuffFrame.Show = function() end
    end
    if TemporaryEnchantFrame then
        TemporaryEnchantFrame:Hide()
        TemporaryEnchantFrame.Show = function() end
    end
    -- Individual BuffButton frames
    local i
    for i = 0, 47 do
        local b = getglobal("BuffButton" .. i)
        if b then
            b:Hide()
            b.Show = function() end
        end
    end
end


local function applyAspect(tex, w, h, sideZoom)
    if not tex then return end
    local pad, span = 0.07, 0.86
    local z = tonumber(sideZoom) or 0
    if z < 0 then z = 0 end
    local u0, u1 = pad + z, 1 - pad - z
    local v0, v1 = pad, 1 - pad
    if w and h and w ~= h then
        if w > h then
            -- Wider frame: crop top/bottom of square spell icon so it isn't squashed
            local crop = (1 - (h / w)) / 2
            v0 = pad + crop * span
            v1 = 1 - pad - crop * span
        else
            local crop = (1 - (w / h)) / 2
            u0 = pad + crop * span + z
            u1 = 1 - pad - crop * span - z
        end
    end
    tex:SetTexCoord(u0, u1, v0, v1)
end

local function goldRGB()
    local r, g, b = 0.75, 0.52, 0.04
    if IchaUI_Gold then r, g, b = IchaUI_Gold() end
    return r, g, b
end

local function paintConsArrow(btn)
    local a = btn and btn.arrowBtn
    if not a then return end
    local tex = a.tex
    if not tex then return end
    tex:SetTexture(ARROW_TEX)
    if btn._consOpen then
        tex:SetTexCoord(1, 0, 0, 1)
    else
        tex:SetTexCoord(0, 1, 0, 1)
    end
    local r, g, b = goldRGB()
    tex:SetVertexColor(r, g, b, 1)
end

local function ensureConsChrome(btn)
    if not btn or btn.arrowBtn then return end
    local a = CreateFrame("Button", nil, btn)
    a:EnableMouse(true)
    a:RegisterForClicks("LeftButtonUp")
    a:SetFrameLevel((btn:GetFrameLevel() or 1) + 10)
    local tex = a:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(a)
    a.tex = tex
    a:SetScript("OnClick", function()
        if IchaUIBuffBars_Set then
            IchaUIBuffBars_Set("consolidatedExpanded", not consolidateOpen())
        end
    end)
    a:SetScript("OnEnter", function()
        local p = this:GetParent()
        if p and p.GetScript then
            local fn = p:GetScript("OnEnter")
            if fn then fn() end
        end
    end)
    a:SetScript("OnLeave", function()
        local p = this:GetParent()
        if p and p.GetScript then
            local fn = p:GetScript("OnLeave")
            if fn then fn() end
        end
    end)
    btn.arrowBtn = a
    a:Hide()
end

local function cancelPlayerHelpful(btn)
    if not btn or btn.consolidated then return end
    if btn.filter == "HELPFUL" and btn.index ~= nil then
        CancelPlayerBuff(btn.index)
    end
end

local function tipConsolidated(btn)
    if GameTooltip then GameTooltip:Hide() end
    if not btn or not btn.consolidated or btn._consOpen then
        if consUI.fly then consUI.fly:Hide() end
        return
    end
    consUI.host = btn
    consUI.grace = 0.25
    if consUI.open then consUI.open() end
end

local function makeIcon(parent, name)
    local btn = CreateFrame("Button", name, parent)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn.icon = icon

    local round = btn:CreateTexture(nil, "ARTWORK")
    round:SetTexture(ROUNDMASK)
    round:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    round:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    round:SetVertexColor(0, 0, 0, 1)
    btn.roundMask = round

    local border = CreateFrame("Frame", nil, btn)
    border:SetFrameLevel((btn:GetFrameLevel() or 1) + 3)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
    applyGold(border, 11)
    btn.border = border

    local textLayer = CreateFrame("Frame", nil, btn)
    textLayer:SetAllPoints(btn)
    textLayer:SetFrameLevel((btn:GetFrameLevel() or 1) + 8)

    local stack = textLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    stack:SetPoint("BOTTOMRIGHT", textLayer, "BOTTOMRIGHT", -2, 2)
    stack:SetJustifyH("RIGHT")
    stack:SetTextColor(1, 1, 1)
    btn.stack = stack

    local dur = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dur:SetJustifyH("CENTER")
    dur:SetTextColor(1, 0.92, 0.7)
    btn.dur = dur

    btn:SetScript("OnEnter", function()
        if this.consolidated then
            tipConsolidated(this)
            return
        end
        if this.index == nil then return end
        GameTooltip:SetOwner(this, "ANCHOR_BOTTOMLEFT")
        if this.filter == "HELPFUL" then
            GameTooltip:SetPlayerBuff(this.index)
        else
            -- Harmful: SetPlayerBuff still works with the buff index from GetPlayerBuff
            GameTooltip:SetPlayerBuff(this.index)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        if this.consolidated then
            consUI.grace = 0.2
            return
        end
        GameTooltip:Hide()
    end)
    btn:SetScript("OnMouseUp", function()
        if arg1 == "RightButton" then
            cancelPlayerHelpful(this)
        end
    end)
    btn:SetScript("OnClick", function()
        if this.consolidated then
            if IchaUIBuffBars_Set then
                IchaUIBuffBars_Set("consolidatedExpanded", not consolidateOpen())
            end
        end
    end)

    btn:Hide()
    return btn
end

local function sizeIcon(btn)
    local w, h = iconW(), iconH()
    btn:SetWidth(w)
    btn:SetHeight(h)
    if btn.consolidated then
        applyAspect(btn.icon, w, h, 0.10)
    else
        applyAspect(btn.icon, w, h)
    end
    if btn.roundMask then btn.roundMask:Show() end
    local e = math.floor(11 * cfgScale + 0.5)
    if e < 8 then e = 8 end
    if e > 18 then e = 18 end
    applyBorder(btn.border, e, btn.dtype)
    btn.border:ClearAllPoints()
    btn.border:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 2)
    btn.border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
    local fontPath = GameFontHighlightSmall:GetFont()
    local fs = math.max(8, math.floor(cfgText * cfgScale + 0.5))
    if fontPath then
        btn.dur:SetFont(fontPath, fs, "OUTLINE")
        btn.stack:SetFont(fontPath, math.max(9, fs), "OUTLINE")
    end
    btn.dur:ClearAllPoints()
    btn.dur:SetPoint("TOP", btn, "BOTTOM", 0, -1)
    btn.dur:SetWidth(w + 8)
    if btn.arrowBtn then
        local aw = math.floor(h * 0.38 + 0.5)
        if aw < 10 then aw = 10 end
        if aw > 14 then aw = 14 end
        btn.arrowBtn:SetWidth(aw)
        btn.arrowBtn:SetHeight(aw)
        btn.arrowBtn:ClearAllPoints()
        btn.arrowBtn:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 2, 2)
        btn.arrowBtn:SetFrameLevel((btn:GetFrameLevel() or 1) + 10)
        paintConsArrow(btn)
    end
end

local function ensureIcons(list, root, prefix, n)
    while table.getn(list) < n do
        local i = table.getn(list) + 1
        table.insert(list, makeIcon(root, "IchaUI" .. prefix .. i))
    end
end

local function layoutRow(root, icons, count)
    local w, h = iconW(), iconH()
    local gap = cfgGap
    local cols = cfgCols
    if cols > 16 then cols = 16 end
    local maxShow = cols * 3 -- 3 rows max
    if maxShow > MAX_ICONS then maxShow = MAX_ICONS end
    if count > maxShow then count = maxShow end
    local rows = math.floor((count + cols - 1) / cols)
    if rows < 1 then rows = 1 end
    if rows > 3 then rows = 3 end
    local durH = math.max(12, math.floor(cfgText * cfgScale + 0.5) + 2)
    local rowH = h + durH + (cfgRowGap or 0)
    local totalW = cols * (w + gap) - gap
    local totalH = rows * rowH
    root:SetWidth(math.max(totalW, w))
    root:SetHeight(math.max(totalH, rowH))

    local i
    for i = 1, table.getn(icons) do
        local btn = icons[i]
        sizeIcon(btn)
        if i <= count then
            local idx = i - 1
            local col = math.mod(idx, cols)
            local row = math.floor(idx / cols)
            -- Grow left from right origin (minimap style): col 0 at right
            local x = -((col + 1) * (w + gap) - gap)
            local y = -row * rowH
            btn:ClearAllPoints()
            btn:SetPoint("TOPRIGHT", root, "TOPRIGHT", x + w, y)
            btn:Show()
            btn.dur:Show()
            -- After SetFont in sizeIcon, so the label is this aura's count, not the slot's last text.
            writeStack(btn, btn._auraCount, btn._auraKeyPending)
            if btn.consolidated and btn.arrowBtn then
                btn.arrowBtn:Show()
            elseif btn.arrowBtn then
                btn.arrowBtn:Hide()
            end
        else
            btn._auraCount = nil
            btn._auraKeyPending = nil
            btn.consolidated = nil
            btn._longNames = nil
            btn._longList = nil
            btn._longCount = nil
            btn._consOpen = nil
            writeStack(btn, 0, nil)
            if btn.arrowBtn then btn.arrowBtn:Hide() end
            btn:Hide()
            btn.dur:SetText("")
            btn.dur:Hide()
        end
    end
end

local function overFrame(f)
    if not f or not f.IsVisible or not f:IsVisible() then return false end
    if type(MouseIsOver) == "function" then
        local ok, v = pcall(MouseIsOver, f)
        if ok and v then return true end
    end
    return false
end

local function hideConsFly()
    if consUI.fly then consUI.fly:Hide() end
end

local function paintConsFly()
    local host = consUI.host
    if not host or not host.consolidated or host._consOpen then
        hideConsFly()
        return
    end
    local list = host._longList
    if not list or table.getn(list) == 0 then
        hideConsFly()
        return
    end
    if not consUI.fly then
        local f = CreateFrame("Frame", "IchaUIConsFly", UIParent)
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(80)
        f:EnableMouse(true)
        f:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.04, 0.04, 0.05, 0.94)
        f:SetScript("OnEnter", function() consUI.grace = 0.25 end)
        f:SetScript("OnLeave", function() consUI.grace = 0.2 end)
        consUI.fly = f
    end
    local f = consUI.fly
    local r, g, b = goldRGB()
    f:SetBackdropBorderColor(r, g, b, 1)
    if IchaUI_Fill then
        local fr, fg, fb = IchaUI_Fill()
        f:SetBackdropColor(fr or 0.04, fg or 0.04, fb or 0.05, 0.94)
    end
    local n = table.getn(list)
    if n > 24 then n = 24 end
    ensureIcons(consUI.icons, f, "ConsFly", n)
    local w, h = iconW(), iconH()
    local gap = cfgGap
    local durH = math.max(12, math.floor(cfgText * cfgScale + 0.5) + 2)
    local rowH = h + durH + (cfgRowGap or 0)
    local cols = n
    if cols > 8 then cols = 8 end
    if cols < 1 then cols = 1 end
    local rows = math.floor((n + cols - 1) / cols)
    if rows < 1 then rows = 1 end
    -- Icon gold borders sit 2px outside the button; keep them inside the panel.
    local inset = 8
    f:SetWidth(cols * (w + gap) - gap + inset * 2)
    f:SetHeight(rows * rowH + inset * 2)
    local flyLvl = (f:GetFrameLevel() or 1) + 5
    local i
    for i = 1, table.getn(consUI.icons) do
        local btn = consUI.icons[i]
        if i <= n then
            local e = list[i]
            btn.consolidated = nil
            btn._consOpen = nil
            btn._longList = nil
            btn.index = e.index
            btn.filter = "HELPFUL"
            btn.dtype = nil
            btn.icon:SetTexture(e.texture)
            btn._auraCount = e.count or 0
            btn._auraKeyPending = e.texture or ""
            if e.timeLeft and e.timeLeft > 0 then
                btn.dur:SetText(formatDur(e.timeLeft))
            else
                btn.dur:SetText("")
            end
            sizeIcon(btn)
            btn:EnableMouse(true)
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:SetFrameLevel(flyLvl)
            local idx = i - 1
            local col = math.mod(idx, cols)
            local row = math.floor(idx / cols)
            local x = -(inset + col * (w + gap))
            local y = -(inset + row * rowH)
            btn:ClearAllPoints()
            btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", x, y)
            btn:Show()
            btn.dur:Show()
            writeStack(btn, btn._auraCount, btn._auraKeyPending)
        else
            btn.index = nil
            btn.consolidated = nil
            writeStack(btn, 0, nil)
            btn:Hide()
            btn.dur:SetText("")
            btn.dur:Hide()
        end
    end
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", 4, -6)
    f:Show()
end

consUI.open = paintConsFly

local function tickConsFly(dt)
    local host = consUI.host
    local fly = consUI.fly
    if overFrame(host) or (host and overFrame(host.arrowBtn)) or overFrame(fly) then
        consUI.grace = 0.25
        return
    end
    if fly and fly:IsShown() then
        consUI.grace = (consUI.grace or 0) - (dt or 0)
        if consUI.grace <= 0 then hideConsFly() end
    end
end

-- Returns list of { index=, texture=, timeLeft=, count=, filter=, name=, baseDur= }
local function collectBuffs(filter)
    local out = {}
    local byTex = stackMap(filter)
    local i = 0
    local cons = (filter == "HELPFUL" and consolidateOn())
    -- Scan past MAX in case API skips holes; stop once we have MAX_ICONS
    while i < 64 and table.getn(out) < MAX_ICONS do
        local id = GetPlayerBuff(i, filter)
        if not id or id < 0 then break end
        local tex = GetPlayerBuffTexture(id)
        if tex then
            local left = 0
            if GetPlayerBuffTimeLeft then
                left = GetPlayerBuffTimeLeft(id) or 0
            end
            local apps = 0
            if GetPlayerBuffApplications then
                apps = GetPlayerBuffApplications(id) or 0
            end
            -- Stack belongs to this icon's texture, not the slot it used to occupy.
            if byTex[tex] then apps = byTex[tex] end
            local dtype = nil
            if filter == "HARMFUL" then
                dtype = resolveDebuffDtype(id)
            end
            local nm = nil
            if cons then
                nm = nameByTex[tex]
                if not nm then
                    nm = auraName(id)
                    if nm then nameByTex[tex] = nm end
                end
            end
            table.insert(out, {
                index = id,
                texture = tex,
                timeLeft = left,
                count = apps,
                filter = filter,
                slot = i,
                dtype = dtype,
                name = nm,
            })
        end
        i = i + 1
    end
    if cons then
        local present = {}
        local j
        for j = 1, table.getn(out) do
            snapBase(out[j])
            present[auraKey(out[j])] = true
        end
        local k, rec
        for k, rec in pairs(baseSeen) do
            if rec and not present[k] then rec.live = nil end
        end
    end
    return out
end

local function paintList(icons, root, filter)
    local list = collectBuffs(filter)
    local opened = false
    if filter == "HELPFUL" and consolidateOn() then
        local short, long, shown = {}, {}, {}
        local i
        for i = 1, table.getn(list) do
            local e = list[i]
            if shouldConsolidate(e) then
                table.insert(long, e)
            else
                table.insert(short, e)
            end
        end
        if table.getn(long) > 0 then
            opened = consolidateOpen()
            local names = {}
            for i = 1, table.getn(long) do
                local nm = long[i].name
                if not nm or nm == "" then nm = "Buff" end
                table.insert(names, nm)
            end
            table.insert(shown, {
                consolidated = true,
                texture = consIcon(opened),
                count = table.getn(long),
                names = names,
                longs = long,
                filter = filter,
            })
            if opened then
                for i = 1, table.getn(list) do
                    table.insert(shown, list[i])
                end
            else
                for i = 1, table.getn(short) do
                    table.insert(shown, short[i])
                end
            end
            list = shown
        end
    end
    local n = table.getn(list)
    if n > MAX_ICONS then n = MAX_ICONS end
    ensureIcons(icons, root, filter == "HELPFUL" and "Buff" or "Debuff", MAX_ICONS)
    local i
    for i = 1, n do
        local e = list[i]
        local btn = icons[i]
        if e.consolidated then
            ensureConsChrome(btn)
            btn.consolidated = true
            btn.index = nil
            btn.filter = filter
            btn.dtype = nil
            btn._consOpen = opened
            btn._longCount = e.count or 0
            btn._longNames = e.names
            btn._longList = e.longs
            btn.icon:SetTexture(consIcon(opened))
            applyAspect(btn.icon, iconW(), iconH(), 0.10)
            btn._auraCount = 0
            if not opened then btn._auraCount = e.count or 0 end
            btn._auraKeyPending = "consolidated"
            btn.dur:SetText("")
            paintConsArrow(btn)
            consUI.host = btn
            if opened then
                hideConsFly()
            elseif consUI.fly and consUI.fly:IsShown() then
                paintConsFly()
            end
        else
            btn.consolidated = nil
            btn._consOpen = nil
            btn._longCount = nil
            btn._longNames = nil
            btn._longList = nil
            btn.index = e.index
            btn.filter = filter
            btn.dtype = (filter == "HARMFUL") and e.dtype or nil
            btn.icon:SetTexture(e.texture)
            applyAspect(btn.icon, iconW(), iconH())
            btn._auraCount = e.count or 0
            btn._auraKeyPending = e.texture or ""
            if e.timeLeft and e.timeLeft > 0 then
                btn.dur:SetText(formatDur(e.timeLeft))
            else
                btn.dur:SetText("")
            end
        end
        -- Color debuff chrome by type; buffs stay gold
        local eSz = math.floor(11 * cfgScale + 0.5)
        if eSz < 8 then eSz = 8 end
        if eSz > 18 then eSz = 18 end
        applyBorder(btn.border, eSz, btn.dtype)
    end
    layoutRow(root, icons, n)
    if filter == "HELPFUL" then
        local host = consUI.host
        if not host or not host.consolidated or host._consOpen then
            hideConsFly()
        end
    end
end

local buffTestMode = false

local function paintTestPlaceholders(icons, root, filter)
    -- Full 48-icon grid for Test UI (3 rows × 16 cols)
    ensureIcons(icons, root, filter == "HELPFUL" and "Buff" or "Debuff", MAX_ICONS)
    local texB = {
        "Interface\\Icons\\Spell_Nature_Regeneration",
        "Interface\\Icons\\Spell_Holy_WordFortitude",
        "Interface\\Icons\\Spell_Nature_Thorns",
        "Interface\\Icons\\Spell_Holy_DivineSpirit",
    }
    local texD = {
        "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
        "Interface\\Icons\\Spell_Fire_Immolation",
        "Interface\\Icons\\Spell_Nature_NullifyPoison",
        "Interface\\Icons\\Ability_Warrior_Sunder",
    }
    local pool = (filter == "HELPFUL") and texB or texD
    local nPool = table.getn(pool)
    local i
    local cycle = { "poison", "disease", "magic", "curse", "bleed", nil }
    for i = 1, MAX_ICONS do
        local btn = icons[i]
        btn.index = nil
        btn.filter = filter
        btn.consolidated = nil
        if btn.arrowBtn then btn.arrowBtn:Hide() end
        if filter == "HARMFUL" then
            btn.dtype = cycle[math.mod(i - 1, table.getn(cycle)) + 1]
        else
            btn.dtype = nil
        end
        local tex = pool[math.mod(i - 1, nPool) + 1]
        btn.icon:SetTexture(tex)
        applyAspect(btn.icon, iconW(), iconH())
        if math.mod(i, 5) == 0 then
            btn._auraCount = 2 + math.mod(i, 3)
        else
            btn._auraCount = 0
        end
        btn._auraKeyPending = tex .. ":" .. i
        local left = 120 - math.mod(i * 7, 110)
        if left < 3 then left = 3 end
        btn.dur:SetText(formatDur(left))
    end
    layoutRow(root, icons, MAX_ICONS)
end

local function refresh()
    if not buffRoot then return end
    if buffTestMode then
        paintTestPlaceholders(buffIcons, buffRoot, "HELPFUL")
        paintTestPlaceholders(debuffIcons, debuffRoot, "HARMFUL")
        if buffRoot then buffRoot:Show() end
        if debuffRoot then debuffRoot:Show() end
        return
    end
    paintList(buffIcons, buffRoot, "HELPFUL")
    paintList(debuffIcons, debuffRoot, "HARMFUL")
end

local function restorePos()
    local d = db()
    buffRoot:ClearAllPoints()
    if d.buffPoint and d.buffX then
        buffRoot:SetPoint(d.buffPoint, UIParent, d.buffRel or d.buffPoint, d.buffX, d.buffY)
    else
        buffRoot:SetPoint("TOPRIGHT", MinimapCluster or Minimap or UIParent, "TOPLEFT", -8, -16)
    end
    debuffRoot:ClearAllPoints()
    if d.debuffPoint and d.debuffX then
        debuffRoot:SetPoint(d.debuffPoint, UIParent, d.debuffRel or d.debuffPoint, d.debuffX, d.debuffY)
    else
        debuffRoot:SetPoint("TOPRIGHT", buffRoot, "BOTTOMRIGHT", 0, -12)
    end
end

local function setMoving(on)
    moving = on and true or false
    if moverBuff then
        if moving then moverBuff:Show() else moverBuff:Hide() end
    end
    if moverDebuff then
        if moving then moverDebuff:Show() else moverDebuff:Hide() end
    end
    if moving then
        DEFAULT_CHAT_FRAME:AddMessage("Buff bars: drag to move, /icha buffs move to lock.")
    else
        saveCfg()
        DEFAULT_CHAT_FRAME:AddMessage("Buff bars locked.")
    end
end

local function makeMover(root, label)
    local m = CreateFrame("Frame", nil, root)
    m:SetAllPoints(root)
    m:EnableMouse(true)
    m:RegisterForDrag("LeftButton")
    m:SetFrameLevel((root:GetFrameLevel() or 1) + 20)
    m:Hide()
    local bg = m:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(m)
    bg:SetTexture(1, 1, 1, 1)
    bg:SetVertexColor(0.15, 0.45, 0.95, 0.35)
    local fs = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER", m, "CENTER")
    fs:SetText(label)
    m:SetScript("OnDragStart", function() root:StartMoving() end)
    m:SetScript("OnDragStop", function()
        root:StopMovingOrSizing()
        saveCfg()
    end)
    return m
end

local function build()
    loadCfg()
    hideBlizzardBuffs()

    buffRoot = CreateFrame("Frame", "IchaUIBuffBar", UIParent)
    buffRoot:SetFrameStrata("MEDIUM")
    buffRoot:SetMovable(true)
    buffRoot:SetWidth(200)
    buffRoot:SetHeight(40)
    buffRoot:Show()

    debuffRoot = CreateFrame("Frame", "IchaUIDebuffBar", UIParent)
    debuffRoot:SetFrameStrata("MEDIUM")
    debuffRoot:SetMovable(true)
    debuffRoot:SetWidth(200)
    debuffRoot:SetHeight(40)
    debuffRoot:Show()

    moverBuff = makeMover(buffRoot, "Buffs")
    moverDebuff = makeMover(debuffRoot, "Debuffs")

    restorePos()
    refresh()
end

function IchaUIBuffBars_Get()
    return {
        scale = cfgScale,
        gap = cfgGap,
        rowGap = cfgRowGap,
        cols = cfgCols,
        text = cfgText,
        moving = moving,
        consolidate = consolidateOn(),
        consolidatedExpanded = consolidateOpen(),
        neverConsolidate = nameList("never"),
        alwaysConsolidate = nameList("always"),
    }
end

function IchaUIBuffBars_List(which, action, name)
    if which ~= "always" then which = "never" end
    local list = nameList(which)
    if action == "get" or not action then return list end
    name = tostring(name or "")
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    name = string.gsub(name, "%s+", " ")
    if name == "" then return list end
    local fold = foldName(name)
    if action == "add" then
        local i
        for i = 1, table.getn(list) do
            if foldName(list[i]) == fold then return list end
        end
        table.insert(list, name)
    elseif action == "remove" then
        local i
        for i = table.getn(list), 1, -1 do
            if foldName(list[i]) == fold then
                table.remove(list, i)
            end
        end
    end
    saveCfg()
    refresh()
    return list
end

function IchaUIBuffBars_Set(field, value)
    if field == "scale" then
        cfgScale = tonumber(value) or cfgScale
        if cfgScale < 0.4 then cfgScale = 0.4 end
        if cfgScale > 2.5 then cfgScale = 2.5 end
    elseif field == "gap" then
        cfgGap = tonumber(value) or cfgGap
        if cfgGap < 0 then cfgGap = 0 end
    elseif field == "rowGap" or field == "rowgap" then
        cfgRowGap = tonumber(value) or cfgRowGap
        if cfgRowGap < 0 then cfgRowGap = 0 end
        if cfgRowGap > 40 then cfgRowGap = 40 end
    elseif field == "cols" then
        cfgCols = math.floor(tonumber(value) or cfgCols)
        if cfgCols < 4 then cfgCols = 4 end
        if cfgCols > 16 then cfgCols = 16 end
    elseif field == "text" then
        cfgText = tonumber(value) or cfgText
        if cfgText < 8 then cfgText = 8 end
        if cfgText > 20 then cfgText = 20 end
    elseif field == "consolidate" then
        db().consolidate = value and true or false
    elseif field == "consolidatedExpanded" then
        db().consolidatedExpanded = value and true or false
    elseif field == "moving" then
        setMoving(value and true or false)
        return
    end
    saveCfg()
    refresh()
end

function IchaUIBuffBars_Slash(msg)
    msg = string.lower(string.gsub(msg or "", "^%s+", ""))
    if msg == "move" then
        setMoving(not moving)
    elseif string.find(msg, "^scale") then
        local n = nil
        for tok in (string.gmatch or string.gfind)(msg, "%S+") do n = tonumber(tok) or n end
        if n then IchaUIBuffBars_Set("scale", n) end
        DEFAULT_CHAT_FRAME:AddMessage(string.format("Buff bar scale: %.2f", cfgScale))
    elseif string.find(msg, "^gap") then
        local n = nil
        for tok in (string.gmatch or string.gfind)(msg, "%S+") do n = tonumber(tok) or n end
        if n then IchaUIBuffBars_Set("gap", n) end
    elseif string.find(msg, "^cols") or string.find(msg, "^col") then
        local n = nil
        for tok in (string.gmatch or string.gfind)(msg, "%S+") do n = tonumber(tok) or n end
        if n then IchaUIBuffBars_Set("cols", n) end
        DEFAULT_CHAT_FRAME:AddMessage(string.format("Buff bar columns: %d", cfgCols))
    else
        DEFAULT_CHAT_FRAME:AddMessage("Buff bars: /icha buffs move|scale|gap|cols")
    end
end

local evt = CreateFrame("Frame")
evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("PLAYER_ENTERING_WORLD")
evt:RegisterEvent("PLAYER_AURAS_CHANGED")
evt:RegisterEvent("PLAYER_DEAD")
pcall(function() evt:RegisterEvent("UNIT_AURA") end)

evt:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        if not buffRoot then build() else
            loadCfg()
            hideBlizzardBuffs()
            restorePos()
            refresh()
        end
    elseif event == "PLAYER_AURAS_CHANGED" or event == "UNIT_AURA" or event == "PLAYER_DEAD" then
        if event == "UNIT_AURA" and arg1 and arg1 ~= "player" then return end
        refresh()
    end
end)

evt:SetScript("OnUpdate", function()
    tickConsFly(arg1 or 0)
    if not this._acc then this._acc = 0 end
    this._acc = this._acc + (arg1 or 0)
    if this._acc < 0.2 then return end
    this._acc = 0
    -- Tick durations without full rebuild when possible
    if buffRoot then refresh() end
end)

function IchaUIBuffBars_SetTestMode(on)
    buffTestMode = on and true or false
    if buffTestMode then hideConsFly() end
    if buffRoot then
        if buffTestMode then
            buffRoot:Show()
            if debuffRoot then debuffRoot:Show() end
        end
        refresh()
    end
end

function IchaUIBuffBars_Reload()
    loadCfg()
    if not buffRoot then return end
    restorePos()
    refresh()
end
