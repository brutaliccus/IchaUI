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
    if count > 1 then
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


local function applyAspect(tex, w, h)
    if not tex then return end
    local pad, span = 0.07, 0.86
    if w == h then
        tex:SetTexCoord(pad, 1 - pad, pad, 1 - pad)
        return
    end
    if w > h then
        -- Wider frame: crop top/bottom of square spell icon so it isn't squashed
        local crop = (1 - (h / w)) / 2
        tex:SetTexCoord(pad, 1 - pad, pad + crop * span, 1 - pad - crop * span)
    else
        local crop = (1 - (w / h)) / 2
        tex:SetTexCoord(pad + crop * span, 1 - pad - crop * span, pad, 1 - pad)
    end
end

local function makeIcon(parent, name)
    local btn = CreateFrame("Button", name, parent)
    btn:EnableMouse(true)
    btn:RegisterForClicks("RightButtonUp")

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
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function()
        if arg1 == "RightButton" and this.filter == "HELPFUL" and this.index ~= nil then
            CancelPlayerBuff(this.index)
        end
    end)

    btn:Hide()
    return btn
end

local function sizeIcon(btn)
    local w, h = iconW(), iconH()
    btn:SetWidth(w)
    btn:SetHeight(h)
    applyAspect(btn.icon, w, h)
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
        else
            btn._auraCount = nil
            btn._auraKeyPending = nil
            writeStack(btn, 0, nil)
            btn:Hide()
            btn.dur:SetText("")
            btn.dur:Hide()
        end
    end
end

-- Returns list of { index=, texture=, timeLeft=, count=, filter= }
local function collectBuffs(filter)
    local out = {}
    local byTex = stackMap(filter)
    local i = 0
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
            table.insert(out, {
                index = id,
                texture = tex,
                timeLeft = left,
                count = apps,
                filter = filter,
                slot = i,
                dtype = dtype,
            })
        end
        i = i + 1
    end
    return out
end

local function paintList(icons, root, filter)
    local list = collectBuffs(filter)
    local n = table.getn(list)
    if n > MAX_ICONS then n = MAX_ICONS end
    ensureIcons(icons, root, filter == "HELPFUL" and "Buff" or "Debuff", MAX_ICONS)
    local i
    for i = 1, n do
        local e = list[i]
        local btn = icons[i]
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
        -- Color debuff chrome by type; buffs stay gold
        local eSz = math.floor(11 * cfgScale + 0.5)
        if eSz < 8 then eSz = 8 end
        if eSz > 18 then eSz = 18 end
        applyBorder(btn.border, eSz, btn.dtype)
    end
    layoutRow(root, icons, n)
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
    }
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
    if not this._acc then this._acc = 0 end
    this._acc = this._acc + (arg1 or 0)
    if this._acc < 0.2 then return end
    this._acc = 0
    -- Tick durations without full rebuild when possible
    if buffRoot then refresh() end
end)

function IchaUIBuffBars_SetTestMode(on)
    buffTestMode = on and true or false
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
