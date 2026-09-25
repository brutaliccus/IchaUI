-- Visual unit-frame layout editor, Move/Lock, and the config search box.

local KINDS = { "player", "target", "tot", "party", "raid", "combat", "focus" }
local LABELS = {
    player = "Player", target = "Target", tot = "ToT", party = "Party",
    raid = "Raid", combat = "Combat", focus = "Focus",
}
local GOLD_R, GOLD_G, GOLD_B = 0.93, 0.78, 0.35

IchaUI_OptCatalog = IchaUI_OptCatalog or {}

function IchaUI_StyleInputBox(box)
    if not box or not box.SetFont then return end
    box._ichaSmallInput = true
    local path = "Fonts\\FRIZQT__.TTF"
    if GameFontHighlightSmall and GameFontHighlightSmall.GetFont then
        local p = GameFontHighlightSmall:GetFont()
        if p and p ~= "" then path = p end
    end
    box:SetFont(path, 9, "")
    box:SetTextColor(1, 1, 1)
    if box.GetHeight and box.SetHeight then
        local h = box:GetHeight()
        if h and h > 0 and h < 20 then box:SetHeight(20) end
    end
    if box.SetTextInsets then box:SetTextInsets(5, 5, 4, 4) end
    -- InputBoxTemplate's middle piece anchors to $parentLeft/$parentRight, so
    -- on an unnamed box it has no rect and only the end caps draw. Hide the
    -- template art and draw the same three pieces anchored to the box.
    if box.GetRegions and box.CreateTexture then
        local regs = { box:GetRegions() }
        local i
        for i = 1, table.getn(regs) do
            local r = regs[i]
            if r and r ~= box._ichaInL and r ~= box._ichaInM and r ~= box._ichaInR
                and r.GetObjectType and r:GetObjectType() == "Texture" and r.GetTexture then
                local t = r:GetTexture()
                if type(t) == "string" and string.find(string.lower(t), "common%-input%-border") then
                    r:Hide()
                end
            end
        end
        local tex = "Interface\\Common\\Common-Input-Border"
        if not box._ichaInL then
            box._ichaInL = box:CreateTexture(nil, "BACKGROUND")
            box._ichaInR = box:CreateTexture(nil, "BACKGROUND")
            box._ichaInM = box:CreateTexture(nil, "BACKGROUND")
        end
        local h = (box.GetHeight and box:GetHeight()) or 20
        if h < 1 then h = 20 end
        local L, M, R = box._ichaInL, box._ichaInM, box._ichaInR
        L:SetTexture(tex)
        L:SetTexCoord(0, 0.0625, 0, 0.625)
        L:ClearAllPoints()
        L:SetWidth(8)
        L:SetHeight(h)
        L:SetPoint("LEFT", box, "LEFT", -5, 0)
        R:SetTexture(tex)
        R:SetTexCoord(0.9375, 1, 0, 0.625)
        R:ClearAllPoints()
        R:SetWidth(8)
        R:SetHeight(h)
        R:SetPoint("RIGHT", box, "RIGHT", 0, 0)
        M:SetTexture(tex)
        M:SetTexCoord(0.0625, 0.9375, 0, 0.625)
        M:ClearAllPoints()
        M:SetHeight(h)
        M:SetPoint("LEFT", L, "RIGHT", 0, 0)
        M:SetPoint("RIGHT", R, "LEFT", 0, 0)
        L:Show()
        M:Show()
        R:Show()
    end
end

function IchaUI_OptNote(tab, label, sub)
    if not tab or tab == "" or not label or label == "" then return end
    local i
    for i = 1, table.getn(IchaUI_OptCatalog) do
        local e = IchaUI_OptCatalog[i]
        if e.tab == tab and e.label == label and e.sub == sub then return end
    end
    table.insert(IchaUI_OptCatalog, { tab = tab, label = label, sub = sub })
end

local editor
local lockBtn
local placeKind

local function hasPortrait(kind)
    if kind == "raid" then return false end
    return true
end

local function metric(kind)
    if kind == "party" and IchaUIUF_PartyGet then return IchaUIUF_PartyGet() end
    if kind == "raid" and IchaUIUF_RaidGet then return IchaUIUF_RaidGet() end
    if IchaUIUF_Get then return IchaUIUF_Get(kind) end
    return nil
end

local function setField(kind, field, value)
    if kind == "party" and IchaUIUF_PartySet then
        IchaUIUF_PartySet(field, value)
        return
    end
    if kind == "raid" and IchaUIUF_RaidSet then
        IchaUIUF_RaidSet(field, value)
        return
    end
    if IchaUIUF_Set then IchaUIUF_Set(kind, field, value) end
end

local function getPos(kind)
    if kind == "party" and IchaUIUF_PartyGetPos then return IchaUIUF_PartyGetPos() end
    if kind == "raid" and IchaUIUF_RaidGetPos then return IchaUIUF_RaidGetPos() end
    if kind == "combat" and IchaUI_CombatGetPos then return IchaUI_CombatGetPos() end
    if IchaUIUF_GetPos then return IchaUIUF_GetPos(kind) end
    return 0, 0
end

local function setPos(kind, x, y)
    if kind == "party" and IchaUIUF_PartySetPos then
        IchaUIUF_PartySetPos(x, y)
        return
    end
    if kind == "raid" and IchaUIUF_RaidSetPos then
        IchaUIUF_RaidSetPos(x, y)
        return
    end
    if kind == "combat" and IchaUI_CombatSetPos then
        IchaUI_CombatSetPos(x, y)
        return
    end
    if IchaUIUF_SetPos then IchaUIUF_SetPos(kind, x, y) end
end

local function nudge(kind, dx, dy)
    if kind == "party" and IchaUIUF_PartyNudge then
        IchaUIUF_PartyNudge(dx, dy)
        return
    end
    if kind == "raid" and IchaUIUF_RaidGetPos and IchaUIUF_RaidSetPos then
        local x, y = IchaUIUF_RaidGetPos()
        IchaUIUF_RaidSetPos((tonumber(x) or 0) + (tonumber(dx) or 0), (tonumber(y) or 0) + (tonumber(dy) or 0))
        return
    end
    if IchaUIUF_Nudge then IchaUIUF_Nudge(kind, dx, dy) end
end

local function stopMove(kind)
    if not kind then return end
    if kind == "party" and IchaUIUF_PartySet then
        IchaUIUF_PartySet("move", false)
    elseif kind == "raid" and IchaUIUF_RaidSet then
        IchaUIUF_RaidSet("move", false)
    elseif kind == "combat" and IchaUI_CombatSet then
        IchaUI_CombatSet("move", false)
    elseif IchaUIUF_Set then
        local fr = IchaUIUF_Get and IchaUIUF_Get(kind)
        if fr and fr.moving then IchaUIUF_Set(kind, "move", false) end
    end
end

local function placeParent(kind)
    if kind == "party" then return getglobal("IchaUIUF_PartyRoot") end
    if kind == "raid" then return getglobal("IchaUIUF_RaidRoot") end
    if kind == "combat" then return getglobal("IchaUICombatList") end
    local fr = IchaUIUF_Get and IchaUIUF_Get(kind)
    if fr and fr.root then return fr.root end
    return UIParent
end

local function ensureLock()
    if lockBtn then return lockBtn end
    lockBtn = CreateFrame("Button", "IchaUIPlaceLock", UIParent)
    lockBtn:SetWidth(72)
    lockBtn:SetHeight(24)
    lockBtn:SetFrameStrata("DIALOG")
    lockBtn:SetFrameLevel(200)
    lockBtn:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    lockBtn:SetBackdropColor(0.12, 0.1, 0.05, 0.95)
    IchaUI_PaintGoldLightBorder(lockBtn, 1)
    local fs = lockBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("CENTER", lockBtn, "CENTER", 0, 0)
    fs:SetText("Lock")
    IchaUI_PaintGoldFont(fs, 0.93, 0.78, 0.35)
    lockBtn:SetScript("OnClick", function()
        if IchaUIUF_EndPlace then IchaUIUF_EndPlace() end
    end)
    lockBtn:Hide()
    return lockBtn
end

function IchaUIUF_BeginPlace(kind)
    if not kind or kind == "" then return end
    if placeKind and placeKind ~= kind then stopMove(placeKind) end
    placeKind = kind
    IchaUI_PlaceKind = kind
    if IchaUIOptions then IchaUIOptions:Hide() end
    if kind == "party" and IchaUIUF_PartySet then
        IchaUIUF_PartySet("move", true)
    elseif kind == "raid" and IchaUIUF_RaidSet then
        IchaUIUF_RaidSet("move", true)
    elseif kind == "combat" and IchaUI_CombatSet then
        IchaUI_CombatSet("move", true)
    elseif IchaUIUF_Set then
        IchaUIUF_Set(kind, "move", true)
    end
    local parent = placeParent(kind) or UIParent
    local btn = ensureLock()
    btn:SetParent(parent)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", parent, "CENTER", 0, 0)
    btn:SetFrameStrata("DIALOG")
    btn:SetFrameLevel(200)
    btn:Show()
end

function IchaUIUF_EndPlace()
    local kind = placeKind or IchaUI_PlaceKind
    if kind then stopMove(kind) end
    placeKind = nil
    IchaUI_PlaceKind = nil
    if lockBtn then lockBtn:Hide() end
    if not IchaUIDB then IchaUIDB = {} end
    if kind and kind ~= "" then IchaUIDB.framesSubTab = kind end
    IchaUIDB.optionsTab = "Frames"
    if IchaUIOptions_Open then IchaUIOptions_Open() end
    if IchaUIOptions and IchaUIOptions.showTab then IchaUIOptions.showTab("Frames") end
    if kind and IchaUI_FrameEditorShow then IchaUI_FrameEditorShow(kind) end
    if IchaUIOptions and IchaUIOptions.refresh then IchaUIOptions.refresh() end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    placeKind = nil
    IchaUI_PlaceKind = nil
    if lockBtn then lockBtn:Hide() end
end)

local function goldButton(parent, text, w, h)
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
    b:SetBackdropBorderColor(0.55, 0.42, 0.08, 0.8)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    fs:SetText(text or "")
    fs:SetTextColor(0.9, 0.88, 0.8)
    b.label = fs
    return b
end

local function paintSub(btns, kind)
    local k, b
    for k, b in pairs(btns) do
        if k == kind then
            b:SetBackdropColor(0.18, 0.14, 0.06, 0.95)
            IchaUI_PaintGoldBorder(b, 1)
            IchaUI_PaintGoldFont(b.label, 0.93, 0.78, 0.35)
        else
            b:SetBackdropColor(0.06, 0.06, 0.07, 0.85)
            b:SetBackdropBorderColor(0.45, 0.36, 0.08, 0.7)
            b.label:SetTextColor(0.75, 0.72, 0.62)
        end
    end
end

function IchaUI_FrameEditorShow(kind)
    if editor and editor.showKind then editor.showKind(kind) end
end

function IchaUI_BuildFrameEditor(page, startKind, xyList, btnList)
    if not page then return end
    local ed = { kind = startKind or "player", busy = false, rows = {} }
    editor = ed
    if not IchaUIDB then IchaUIDB = {} end
    local known = false
    local i
    for i = 1, table.getn(KINDS) do
        if KINDS[i] == ed.kind then known = true end
    end
    if not known then ed.kind = "player" end

    local subBtns = {}
    local sx = 8
    for i = 1, table.getn(KINDS) do
        local kind = KINDS[i]
        local b = goldButton(page, LABELS[kind], 72, 20)
        b:SetPoint("TOPLEFT", page, "TOPLEFT", sx, -4)
        b:SetScript("OnClick", function()
            ed.showKind(kind)
        end)
        subBtns[kind] = b
        sx = sx + 76
    end

    local preview = CreateFrame("Frame", nil, page)
    preview:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -26)
    preview:SetWidth(520)
    preview:SetHeight(148)
    preview:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    preview:SetBackdropColor(0.04, 0.04, 0.05, 0.92)
    IchaUI_PaintGoldBorder(preview, 0.9)
    local cap = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cap:SetPoint("TOPLEFT", preview, "TOPLEFT", 10, -6)
    cap:SetText("Preview")
    IchaUI_PaintGoldFont(cap, 0.93, 0.78, 0.35)

    local bars = CreateFrame("Frame", nil, preview)
    bars:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    bars:SetBackdropColor(0.05, 0.05, 0.06, 0.95)
    IchaUI_PaintGoldBorder(bars, 1)
    local hpBg = bars:CreateTexture(nil, "BACKGROUND")
    hpBg:SetTexture("Interface/TargetingFrame/UI-StatusBar")
    hpBg:SetVertexColor(0.12, 0.12, 0.12, 1)
    local hp = bars:CreateTexture(nil, "ARTWORK")
    hp:SetTexture("Interface/TargetingFrame/UI-StatusBar")
    local swing = bars:CreateTexture(nil, "ARTWORK")
    swing:SetTexture("Interface/TargetingFrame/UI-StatusBar")
    swing:SetVertexColor(0.92, 0.90, 0.82, 1)
    local mpBg = bars:CreateTexture(nil, "BACKGROUND")
    mpBg:SetTexture("Interface/TargetingFrame/UI-StatusBar")
    mpBg:SetVertexColor(0.08, 0.08, 0.1, 1)
    local mp = bars:CreateTexture(nil, "ARTWORK")
    mp:SetTexture("Interface/TargetingFrame/UI-StatusBar")
    mp:SetVertexColor(0.2, 0.4, 0.9, 1)
    local nameFS = bars:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFS:SetTextColor(1, 0.95, 0.8)
    local hpFS = bars:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hpFS:SetTextColor(1, 1, 1)
    local powerFS = bars:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    powerFS:SetTextColor(0.7, 0.85, 1)

    local port = CreateFrame("Frame", nil, preview)
    local portBg = port:CreateTexture(nil, "BACKGROUND")
    portBg:SetAllPoints(port)
    portBg:SetTexture("Interface/Minimap/UI-Minimap-Background")
    portBg:SetVertexColor(0, 0, 0, 1)
    local face = port:CreateTexture(nil, "ARTWORK")
    face:SetTexCoord(0, 1, 0, 1)
    local ringFrame = CreateFrame("Frame", nil, preview)
    ringFrame:EnableMouse(false)
    local ring = ringFrame:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\AddOns\\IchaUI\\media\\PortraitFrame.tga")
    ring:SetTexCoord(0, 1, 0, 1)
    IchaUI_PaintGoldVertex(ring, 0.80, 0.66, 0.15, 1)
    ring:SetAllPoints(ringFrame)

    local badge = CreateFrame("Frame", nil, preview)
    local badgeBg = badge:CreateTexture(nil, "BACKGROUND")
    badgeBg:SetAllPoints(badge)
    badgeBg:SetTexture("Interface\\AddOns\\IchaUI\\media\\circledisc.tga")
    badgeBg:SetVertexColor(0.05, 0.05, 0.06, 1)
    local badgeRing = badge:CreateTexture(nil, "BORDER")
    badgeRing:SetAllPoints(badge)
    badgeRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    IchaUI_PaintGoldRing(badgeRing)
    local badgeFS = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    badgeFS:SetPoint("CENTER", badge, "CENTER", 0, 0)
    badgeFS:SetJustifyH("CENTER")
    badgeFS:SetText("60")
    badgeFS:SetTextColor(1, 0.92, 0.65)

    local function makeIcon(path, u0, v0, u1, v1)
        local f = CreateFrame("Frame", nil, preview)
        f:EnableMouse(false)
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetAllPoints(f)
        t:SetTexture(path)
        if u0 then t:SetTexCoord(u0, u1, v0, v1) end
        f.tex = t
        return f
    end
    local lead = makeIcon("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    local loot = makeIcon("Interface\\GroupFrame\\UI-Group-MasterLooter")
    local mark = makeIcon("Interface\\TargetingFrame\\UI-RaidTargetingIcons", 0, 0, 0.25, 0.25)

    local castFrame = CreateFrame("Frame", nil, preview)
    local castBg = castFrame:CreateTexture(nil, "BACKGROUND")
    castBg:SetTexture("Interface/TargetingFrame/UI-StatusBar")
    castBg:SetVertexColor(0.08, 0.07, 0.06, 1)
    local castFill = castFrame:CreateTexture(nil, "ARTWORK")
    castFill:SetTexture("Interface/TargetingFrame/UI-StatusBar")
    IchaUI_PaintGoldVertex(castFill, 0.95, 0.78, 0.22, 1, true)
    local castArtL = castFrame:CreateTexture(nil, "OVERLAY")
    local castBorder = castFrame:CreateTexture(nil, "OVERLAY")
    local castArtR = castFrame:CreateTexture(nil, "OVERLAY")
    local castIconHolder = CreateFrame("Frame", nil, castFrame)
    castIconHolder:SetWidth(32)
    castIconHolder:SetHeight(32)
    local castIconBg = castIconHolder:CreateTexture(nil, "BACKGROUND")
    castIconBg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    castIconBg:SetVertexColor(0, 0, 0, 1)
    local castIcon = castIconHolder:CreateTexture(nil, "ARTWORK")
    castIcon:SetTexture("Interface\\Icons\\Spell_Nature_Lightning")
    local castIconRing = castIconHolder:CreateTexture(nil, "OVERLAY")
    castIconRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    IchaUI_PaintGoldRing(castIconRing)
    local castTextPlate = CreateFrame("Frame", nil, castFrame)
    castTextPlate:SetAllPoints(castFrame)
    local castName = castTextPlate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    castName:SetJustifyH("LEFT")
    castName:SetText("Cast")
    castName:SetTextColor(1, 0.95, 0.85)
    local castTime = castTextPlate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    castTime:SetJustifyH("RIGHT")
    castTime:SetText("1.2")
    castTime:SetTextColor(1, 0.95, 0.85)
    local castFake = {
        castFrame = castFrame,
        castBorder = castBorder,
        castArtL = castArtL,
        castArtR = castArtR,
        castIconHolder = castIconHolder,
        castIcon = castIcon,
        castIconBg = castIconBg,
        castIconRing = castIconRing,
    }
    -- Sample auras are children of the mock unit frame so their anchors
    -- are that gold frame, and they paint above its bar and border.
    local function sampleIcon(path)
        local f = CreateFrame("Frame", nil, bars)
        f:EnableMouse(false)
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetTexture(path)
        f.tex = t
        local border = CreateFrame("Frame", nil, f)
        border:SetFrameLevel((f:GetFrameLevel() or 1) + 3)
        f.border = border
        f:Hide()
        return f
    end
    local sampleBuffs = {
        sampleIcon("Interface\\Icons\\Spell_Nature_Regeneration"),
        sampleIcon("Interface\\Icons\\Spell_Holy_SealOfProtection"),
        sampleIcon("Interface\\Icons\\Spell_Nature_LightningShield"),
    }
    local sampleDebuffs = {
        sampleIcon("Interface\\Icons\\Spell_Shadow_ShadowWordPain"),
        sampleIcon("Interface\\Icons\\Spell_Nature_NullifyPoison"),
    }

    local function outlineFont(fs, size)
        local fp = GameFontHighlightSmall:GetFont()
        local sz = math.floor((tonumber(size) or 10) + 0.5)
        if sz < 8 then sz = 8 end
        if sz > 18 then sz = 18 end
        if fp then fs:SetFont(fp, sz, "OUTLINE") end
    end
    local function placeText(fs, bar, align, x, y)
        fs:ClearAllPoints()
        local a = align or "CENTER"
        if a ~= "LEFT" and a ~= "RIGHT" then a = "CENTER" end
        fs:SetJustifyH(a)
        if a == "LEFT" then
            fs:SetPoint("LEFT", bar, "LEFT", 4 + (x or 0), y or 0)
        elseif a == "RIGHT" then
            fs:SetPoint("RIGHT", bar, "RIGHT", -4 + (x or 0), y or 0)
        else
            fs:SetPoint("CENTER", bar, "CENTER", x or 0, y or 0)
        end
    end
    local function placeIcon(tex, rel, anchor, x, y, sz)
        tex:ClearAllPoints()
        tex:SetWidth(sz)
        tex:SetHeight(sz)
        local a = anchor or "CENTER"
        tex:SetPoint("CENTER", rel, a, x or 0, y or 0)
        tex:Show()
    end

    local function paintPreview()
        local baseLv = (preview:GetFrameLevel() or 1)
        bars:SetFrameLevel(baseLv + 2)
        castFrame:SetFrameLevel(baseLv + 4)
        port:SetFrameLevel(baseLv + 40)
        ringFrame:SetFrameLevel(baseLv + 50)
        badge:SetFrameLevel(baseLv + 55)
        local kind = ed.kind
        cap:SetText("Preview: " .. (LABELS[kind] or kind))
        local m = metric(kind)
        local hpH, mpH = 33, 7
        if IchaUIUF_GetBarSplit then
            hpH, mpH = IchaUIUF_GetBarSplit(kind)
        end
        if not hpH or hpH < 1 then hpH = 33 end
        if not mpH or mpH < 1 then mpH = 7 end
        local gap = 2
        if kind == "party" or kind == "raid" then gap = 0 end
        local stack = hpH + mpH + gap + 6
        local fit = 1
        if stack > 70 then fit = 70 / stack end
        local drawHp = math.max(8, math.floor(hpH * fit + 0.5))
        local drawMp = math.max(4, math.floor(mpH * fit + 0.5))
        local drawGap = 0
        if gap > 0 then drawGap = math.max(2, math.floor(gap * fit + 0.5)) end
        local barW = 210
        if m and m.width then
            barW = math.floor((tonumber(m.width) or 210) + 0.5)
        end
        if barW < 90 then barW = 90 end
        if barW > 280 then barW = 280 end
        local frameH = 6 + drawHp + drawGap + drawMp
        bars:SetWidth(barW)
        bars:SetHeight(frameH)
        local showPort = hasPortrait(kind)
        if m and m.portraitEnabled == false then showPort = false end
        local ph = 0
        if showPort then
            local psc = (m and tonumber(m.portraitScale)) or 1.22
            ph = math.floor(frameH * psc + 0.5)
            if ph < 36 then ph = 36 end
            if ph > 96 then ph = 96 end
        end
        local leftPad = 16
        if showPort then
            local cutIn = math.floor(ph * 0.32 + 0.5)
            leftPad = (ph - cutIn) + 18
        end
        bars:ClearAllPoints()
        bars:SetPoint("LEFT", preview, "LEFT", leftPad, 8)

        hpBg:ClearAllPoints()
        hpBg:SetPoint("TOPLEFT", bars, "TOPLEFT", 4, -4)
        hpBg:SetWidth(barW - 8)
        hpBg:SetHeight(drawHp)
        hp:ClearAllPoints()
        hp:SetPoint("TOPLEFT", hpBg, "TOPLEFT", 0, 0)
        hp:SetWidth(math.floor((barW - 8) * 0.78 + 0.5))
        hp:SetHeight(drawHp)
        if drawGap > 0 then
            swing:Show()
            swing:ClearAllPoints()
            swing:SetPoint("TOPLEFT", hpBg, "BOTTOMLEFT", 0, 0)
            swing:SetWidth(barW - 8)
            swing:SetHeight(drawGap)
            swing:SetVertexColor(0.92, 0.90, 0.82, 1)
            mpBg:ClearAllPoints()
            mpBg:SetPoint("TOPLEFT", swing, "BOTTOMLEFT", 0, 0)
        else
            swing:Hide()
            mpBg:ClearAllPoints()
            mpBg:SetPoint("TOPLEFT", hpBg, "BOTTOMLEFT", 0, 0)
        end
        mpBg:SetWidth(barW - 8)
        mpBg:SetHeight(drawMp)
        mp:ClearAllPoints()
        mp:SetPoint("TOPLEFT", mpBg, "TOPLEFT", 0, 0)
        mp:SetWidth(barW - 8)
        mp:SetHeight(drawMp)

        local hpPath = "Interface/TargetingFrame/UI-StatusBar"
        local mpPath = hpPath
        local castPath = hpPath
        if IchaUIUF_BarFillPath then
            hpPath = IchaUIUF_BarFillPath(kind, "health") or hpPath
            mpPath = IchaUIUF_BarFillPath(kind, "power") or mpPath
            castPath = IchaUIUF_BarFillPath(kind, "cast") or castPath
        end
        hpBg:SetTexture(hpPath)
        hp:SetTexture(hpPath)
        mpBg:SetTexture(mpPath)
        mp:SetTexture(mpPath)
        swing:SetTexture("Interface/TargetingFrame/UI-StatusBar")
        if kind == "target" or kind == "tot" or kind == "focus" then
            hp:SetVertexColor(0.8, 0.15, 0.15, 1)
        else
            hp:SetVertexColor(0.15, 0.7, 0.2, 1)
        end
        mp:SetVertexColor(0.2, 0.4, 0.9, 1)

        local ts = IchaUIUF_GetTextSettings and IchaUIUF_GetTextSettings(kind)
        if not ts then ts = {} end
        outlineFont(nameFS, 11 * ((ts.nameScale) or 1))
        outlineFont(hpFS, 10 * ((ts.hpScale) or 1))
        outlineFont(powerFS, 9 * ((ts.powerScale) or 1))
        nameFS:SetText(LABELS[kind] or "Name")
        nameFS:Show()
        placeText(nameFS, hpBg, ts.nameAlign or "CENTER", ts.nameX or 0, ts.nameY or 4)
        if ts.showHpPct == false then
            hpFS:SetText("100 / 100")
        else
            hpFS:SetText("100%")
        end
        hpFS:Show()
        placeText(hpFS, hpBg, ts.hpAlign or "CENTER", ts.hpX or 0, ts.hpY or -7)
        if ts.showPowerText == false then
            powerFS:Hide()
        else
            powerFS:SetText("100")
            powerFS:Show()
            placeText(powerFS, mpBg, ts.powerAlign or "CENTER", 0, 0)
        end

        if showPort then
            port:Show()
            port:SetWidth(ph)
            port:SetHeight(ph)
            port:ClearAllPoints()
            local cutIn = math.floor(ph * 0.32 + 0.5)
            local ox = (m and tonumber(m.portraitOffsetX)) or 0
            local oy = (m and tonumber(m.portraitOffsetY)) or 0
            if m and m.portraitSide == "right" then
                port:SetPoint("RIGHT", bars, "RIGHT", (ph - cutIn) + ox, oy)
            else
                port:SetPoint("LEFT", bars, "LEFT", -(ph - cutIn) + ox, oy)
            end
            face:ClearAllPoints()
            local faceSz = math.floor(ph * (1 - 2 * 0.04) + 0.5)
            face:SetWidth(faceSz)
            face:SetHeight(faceSz)
            face:SetPoint("CENTER", port, "CENTER", 0, 0)
            face:SetTexCoord(0, 1, 0, 1)
            if SetPortraitTexture then
                local unit = "player"
                if unit ~= "" and unit ~= "none" then
                    local okp, exists = pcall(UnitExists, unit)
                    if okp and exists then
                        pcall(SetPortraitTexture, face, unit)
                    end
                end
            end
            face:SetTexCoord(0, 1, 0, 1)
            local ringMul = (m and tonumber(m.portraitRing)) or 1.28
            local ringSz = math.floor(ph * ringMul + 0.5)
            ringFrame:Show()
            ringFrame:ClearAllPoints()
            ringFrame:SetWidth(ringSz)
            ringFrame:SetHeight(ringSz)
            ringFrame:SetPoint("CENTER", port, "CENTER", 0, 0)
            local portBadge = IchaUI_LevelPortraitOn and IchaUI_LevelPortraitOn(kind)
            local bsc = (m and tonumber(m.badgeScale)) or 1
            local csz = math.floor(ph * 0.38 * bsc + 0.5)
            if csz < 14 then csz = 14 end
            if csz > 28 then csz = 28 end
            if portBadge then badge:Show() else badge:Hide() end
            badge:SetWidth(csz)
            badge:SetHeight(csz)
            badge:ClearAllPoints()
            local ang = (m and tonumber(m.badgeAngle)) or 0
            while ang < 0 do ang = ang + 360 end
            while ang >= 360 do ang = ang - 360 end
            local rad = ang * math.pi / 180
            local radius = (ph * 0.5) - (csz * 0.15)
            if radius < ph * 0.25 then radius = ph * 0.25 end
            local bx = math.sin(rad) * radius + ((m and tonumber(m.badgeOffsetX)) or 0)
            local by = -math.cos(rad) * radius + ((m and tonumber(m.badgeOffsetY)) or 0)
            local badgeRel = port
            if m and m.badgeHost == "frame" then
                badgeRel = bars
                bx = (m and tonumber(m.badgeOffsetX)) or 0
                by = (m and tonumber(m.badgeOffsetY)) or 0
            end
            badge:SetPoint("CENTER", badgeRel, "CENTER", bx, by)
            local bw = math.floor(csz * 1.65 + 0.5)
            badgeRing:ClearAllPoints()
            badgeRing:SetWidth(bw)
            badgeRing:SetHeight(bw)
            badgeRing:SetPoint("TOPLEFT", badge, "TOPLEFT", 0, 0)
            local inset = math.floor(csz * 0.88 + 0.5)
            badgeBg:ClearAllPoints()
            badgeBg:SetWidth(inset)
            badgeBg:SetHeight(inset)
            badgeBg:SetPoint("CENTER", badge, "CENTER", 0, 0)
            outlineFont(badgeFS, csz * 0.5)
            badgeFS:SetText("60")
        else
            port:Hide()
            ringFrame:Hide()
            badge:Hide()
        end

        local iconRel = bars
        local iconParent = bars
        if showPort then
            iconRel = port
            iconParent = ringFrame
        end
        local function iconHost(host)
            if host == "frame" or not showPort then return bars end
            return port
        end
        lead:SetParent(iconParent)
        loot:SetParent(iconParent)
        mark:SetParent(iconParent)
        local iconLv = (iconParent:GetFrameLevel() or 1) + 9
        lead:SetFrameLevel(iconLv)
        loot:SetFrameLevel(iconLv)
        mark:SetFrameLevel(iconLv)
        local leadS = IchaUIUF_GetRoleIconSettings and IchaUIUF_GetRoleIconSettings(kind, "leader")
        if leadS and leadS.show ~= false then
            placeIcon(lead, iconHost(leadS.host), leadS.anchor or "TOPLEFT", leadS.x or 0, leadS.y or 0, 14)
        else
            lead:Hide()
        end
        local lootS = IchaUIUF_GetRoleIconSettings and IchaUIUF_GetRoleIconSettings(kind, "loot")
        if lootS and lootS.show ~= false then
            placeIcon(loot, iconHost(lootS.host), lootS.anchor or "TOPRIGHT", lootS.x or 0, lootS.y or 0, 14)
        else
            loot:Hide()
        end
        local markS = IchaUIUF_GetMarkSettings and IchaUIUF_GetMarkSettings(kind)
        if (not markS) or markS.markShow ~= false then
            placeIcon(mark, iconHost(markS and markS.host), (markS and markS.markAnchor) or "CENTER", (markS and markS.markX) or 0, (markS and markS.markY) or 0, 16)
        else
            mark:Hide()
        end

        local castOn = kind ~= "raid"
        if castOn and IchaUIUF_CastBarOn and not IchaUIUF_CastBarOn(kind) then castOn = false end
        if not castOn then
            castFrame:Hide()
        else
            castFrame:Show()
            local cs = IchaUIUF_GetCastSettings and IchaUIUF_GetCastSettings(kind)
            local castW = (cs and tonumber(cs.castLen)) or (IchaUI_CAST_NAT or 214)
            if castW < (IchaUI_CAST_LEN_MIN or 80) then castW = IchaUI_CAST_LEN_MIN or 80 end
            if castW > (IchaUI_CAST_LEN_MAX or 420) then castW = IchaUI_CAST_LEN_MAX or 420 end
            local csc = (cs and tonumber(cs.castScale)) or 1
            if csc < (IchaUI_CAST_SC_MIN or 0.4) then csc = IchaUI_CAST_SC_MIN or 0.4 end
            if csc > (IchaUI_CAST_SC_MAX or 3) then csc = IchaUI_CAST_SC_MAX or 3 end
            local castH = IchaUI_CAST_ART_H or 22
            castFrame:SetScale(csc)
            castFrame:SetWidth(castW)
            castFrame:SetHeight(castH)
            if IchaUI_Cast_LayoutArt then
                IchaUI_Cast_LayoutArt(castFake, castW, false)
            end
            castFrame:ClearAllPoints()
            local cox = (cs and tonumber(cs.castOffsetX)) or 0
            local coy = (cs and tonumber(cs.castOffsetY)) or 0
            local castPos = (cs and cs.castPos) or "bottom"
            if castPos == "top" then
                castFrame:SetPoint("BOTTOMLEFT", bars, "TOPLEFT", cox, coy)
            else
                castFrame:SetPoint("TOPLEFT", mpBg, "BOTTOMLEFT", cox, -gap + coy)
            end
            castBg:ClearAllPoints()
            castBg:SetPoint("TOPLEFT", castFrame, "TOPLEFT", 3, -4)
            castBg:SetPoint("BOTTOMRIGHT", castFrame, "BOTTOMRIGHT", -4, 4)
            castBg:SetTexture(castPath)
            castBg:SetVertexColor(0.08, 0.07, 0.06, 1)
            castBg:Show()
            local insetL = castFake._castFillInsetL or 6
            local insetY = castFake._castFillInsetY or 7
            local fillMax = castFake._castFillMax or (castW - 12)
            castFill:ClearAllPoints()
            castFill:SetPoint("TOPLEFT", castFrame, "TOPLEFT", insetL, -insetY)
            castFill:SetPoint("BOTTOMLEFT", castFrame, "BOTTOMLEFT", insetL, insetY)
            castFill:SetWidth(math.max(1, math.floor(fillMax * 0.62 + 0.5)))
            castFill:SetTexture(castPath)
            IchaUI_PaintGoldVertex(castFill, 0.95, 0.78, 0.22, 1, true)
            castFill:Show()
            local iconSz = 32
            local iconX = math.floor(iconSz * 0.32 + 0.5)
            castIconHolder:SetFrameLevel((castFrame:GetFrameLevel() or 1) + 8)
            castIconHolder:ClearAllPoints()
            castIconHolder:SetPoint("CENTER", castFrame, "LEFT", iconX, 0)
            if IchaUI_Cast_LayoutIcon then
                IchaUI_Cast_LayoutIcon(castFake, iconSz, false)
            end
            castIconHolder:Show()
            castTextPlate:SetFrameLevel((castFrame:GetFrameLevel() or 1) + 12)
            local iconRight = iconX + math.floor(iconSz / 2)
            local cFont = math.floor(castH * 0.5 + 0.5)
            outlineFont(castName, cFont)
            outlineFont(castTime, cFont)
            castName:ClearAllPoints()
            castName:SetPoint("LEFT", castFrame, "LEFT", iconRight + 4, 0)
            castName:SetText("Cast")
            castTime:ClearAllPoints()
            castTime:SetPoint("RIGHT", castFrame, "RIGHT", -10, 0)
            castTime:SetText("1.2")
        end
        local buffN = 3
        local debuffN = 2
        local bRow = 8
        local dRow = 8
        local bAnc = "TOPLEFT"
        local dAnc = "BOTTOMLEFT"
        local bOx, bOy, dOx, dOy = 0, 0, 0, 0
        if IchaUIUF_AuraLayoutGet then
            buffN = IchaUIUF_AuraLayoutGet(kind, "buffsShown") or 3
            debuffN = IchaUIUF_AuraLayoutGet(kind, "debuffsShown") or 2
            bRow = IchaUIUF_AuraLayoutGet(kind, "buffPerRow") or 8
            dRow = IchaUIUF_AuraLayoutGet(kind, "debuffPerRow") or 8
            bAnc = IchaUIUF_AuraLayoutGet(kind, "buffAnchor") or bAnc
            dAnc = IchaUIUF_AuraLayoutGet(kind, "debuffAnchor") or dAnc
            bOx = IchaUIUF_AuraLayoutGet(kind, "buffX") or 0
            bOy = IchaUIUF_AuraLayoutGet(kind, "buffY") or 0
            dOx = IchaUIUF_AuraLayoutGet(kind, "debuffX") or 0
            dOy = IchaUIUF_AuraLayoutGet(kind, "debuffY") or 0
        end
        if buffN > 3 then buffN = 3 end
        if debuffN > 2 then debuffN = 2 end
        if bRow < 1 then bRow = 1 end
        if dRow < 1 then dRow = 1 end
        local bPad = tonumber(ts.buffPad) or 2
        local dPad = tonumber(ts.debuffPad) or 2
        if bPad < 0 then bPad = 0 end
        if bPad > 12 then bPad = 12 end
        if dPad < 0 then dPad = 0 end
        if dPad > 12 then dPad = 12 end
        local function validSide(anchorName, above)
            local side = anchorName
            if not side or side == "" then
                if above then side = "TOP" else side = "BOTTOM" end
            end
            if side ~= "TOP" and side ~= "TOPLEFT" and side ~= "TOPRIGHT"
                and side ~= "BOTTOM" and side ~= "BOTTOMLEFT" and side ~= "BOTTOMRIGHT"
                and side ~= "LEFT" and side ~= "RIGHT" then
                side = "TOPLEFT"
            end
            return side
        end
        local function prepSample(icon, aw, ah)
            icon:SetParent(bars)
            icon:ClearAllPoints()
            icon:SetWidth(aw)
            icon:SetHeight(ah)
            icon:SetFrameLevel((bars:GetFrameLevel() or 1) + 25)
            if icon.tex then
                icon.tex:ClearAllPoints()
                icon.tex:SetAllPoints(icon)
                if IchaUI_ApplyAuraAspect then
                    IchaUI_ApplyAuraAspect(icon.tex, aw, ah)
                end
            end
            local border = icon.border
            if border then
                local edge = math.floor(aw * 0.42 + 0.5)
                if edge < 8 then edge = 8 end
                if edge > 16 then edge = 16 end
                local outset = math.floor(aw * 0.08 + 0.5)
                if outset < 2 then outset = 2 end
                border:ClearAllPoints()
                border:SetPoint("TOPLEFT", icon, "TOPLEFT", -outset, outset)
                border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", outset, -outset)
                border:SetBackdrop({
                    bgFile = nil,
                    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                    tile = true,
                    tileSize = 8,
                    edgeSize = edge,
                    insets = { left = 2, right = 2, top = 2, bottom = 2 },
                })
                border:SetBackdropColor(0, 0, 0, 0)
                border:SetFrameLevel((icon:GetFrameLevel() or 1) + 3)
                if IchaUI_PaintGoldBorder then
                    IchaUI_PaintGoldBorder(border, 1)
                else
                    border:SetBackdropBorderColor(0.75, 0.52, 0.04, 1)
                end
                border:Show()
            end
        end
        -- Same points as UnitFrames.lua layoutAuraGrid (anchor is the unit root).
        local function seatLive(list, count, per, anchorName, ox, oy, aw, ah, pad, above)
            local side = validSide(anchorName, above)
            local framePad = 3
            local outset = math.floor(aw * 0.08 + 0.5)
            if outset < 2 then outset = 2 end
            local i
            for i = 1, table.getn(list) do
                local tex = list[i]
                if i <= count then
                    local idx = i - 1
                    local col = idx - math.floor(idx / per) * per
                    local row = math.floor(idx / per)
                    local step = framePad + outset + col * (aw + pad)
                    prepSample(tex, aw, ah)
                    if side == "TOP" or side == "TOPLEFT" then
                        local y = outset + row * (ah + pad) + oy
                        tex:SetPoint("BOTTOMLEFT", bars, "TOPLEFT", step + ox, y)
                    elseif side == "TOPRIGHT" then
                        local y = outset + row * (ah + pad) + oy
                        tex:SetPoint("BOTTOMRIGHT", bars, "TOPRIGHT", -step + ox, y)
                    elseif side == "BOTTOM" or side == "BOTTOMLEFT" then
                        local y = -outset - row * (ah + pad) + oy
                        tex:SetPoint("TOPLEFT", bars, "BOTTOMLEFT", step + ox, y)
                    elseif side == "BOTTOMRIGHT" then
                        local y = -outset - row * (ah + pad) + oy
                        tex:SetPoint("TOPRIGHT", bars, "BOTTOMRIGHT", -step + ox, y)
                    elseif side == "LEFT" then
                        local y = -framePad - outset - col * (ah + pad) + oy
                        local x = -outset - row * (aw + pad) + ox
                        tex:SetPoint("TOPRIGHT", bars, "TOPLEFT", x, y)
                    else
                        local y = -framePad - outset - col * (ah + pad) + oy
                        local x = outset + row * (aw + pad) + ox
                        tex:SetPoint("TOPLEFT", bars, "TOPRIGHT", x, y)
                    end
                    tex:Show()
                else
                    tex:Hide()
                end
            end
        end
        -- Raid compact frames use layoutAuraGridInset (inside the unit frame).
        local function seatInset(list, count, per, anchorName, ox, oy, aw, ah, pad)
            local side = validSide(anchorName, false)
            local gap = pad
            local edge = 2
            local i
            for i = 1, table.getn(list) do
                local tex = list[i]
                if i <= count then
                    local idx = i - 1
                    local col = idx - math.floor(idx / per) * per
                    local row = math.floor(idx / per)
                    local rowStart = row * per
                    local rowCount = count - rowStart
                    if rowCount > per then rowCount = per end
                    prepSample(tex, aw, ah)
                    if side == "TOP" or side == "TOPLEFT" then
                        local rowW = rowCount * aw + (rowCount - 1) * gap
                        local x0 = edge
                        if side == "TOP" then
                            x0 = ((bars:GetWidth() or 0) - rowW) / 2
                        end
                        local x = x0 + col * (aw + gap) + ox
                        local y = -edge - row * (ah + gap) + oy
                        tex:SetPoint("TOPLEFT", bars, "TOPLEFT", x, y)
                    elseif side == "TOPRIGHT" then
                        local x = -edge - col * (aw + gap) + ox
                        local y = -edge - row * (ah + gap) + oy
                        tex:SetPoint("TOPRIGHT", bars, "TOPRIGHT", x, y)
                    elseif side == "BOTTOM" or side == "BOTTOMLEFT" then
                        local rowW = rowCount * aw + (rowCount - 1) * gap
                        local x0 = edge
                        if side == "BOTTOM" then
                            x0 = ((bars:GetWidth() or 0) - rowW) / 2
                        end
                        local x = x0 + col * (aw + gap) + ox
                        local y = edge + row * (ah + gap) + oy
                        tex:SetPoint("BOTTOMLEFT", bars, "BOTTOMLEFT", x, y)
                    elseif side == "BOTTOMRIGHT" then
                        local x = -edge - col * (aw + gap) + ox
                        local y = edge + row * (ah + gap) + oy
                        tex:SetPoint("BOTTOMRIGHT", bars, "BOTTOMRIGHT", x, y)
                    elseif side == "LEFT" then
                        local x = edge + row * (aw + gap) + ox
                        local y = -edge - col * (ah + gap) + oy
                        tex:SetPoint("TOPLEFT", bars, "TOPLEFT", x, y)
                    else
                        local x = -edge - row * (aw + gap) + ox
                        local y = -edge - col * (ah + gap) + oy
                        tex:SetPoint("TOPRIGHT", bars, "TOPRIGHT", x, y)
                    end
                    tex:Show()
                else
                    tex:Hide()
                end
            end
        end
        local bSc = tonumber(ts.buffScale) or 1
        local dSc = tonumber(ts.debuffScale) or 1
        if bSc < 0.4 then bSc = 0.4 end
        if bSc > 3 then bSc = 3 end
        if dSc < 0.4 then dSc = 0.4 end
        if dSc > 3 then dSc = 3 end
        local fScale = (m and tonumber(m.scale)) or 1
        if fScale < 0.4 then fScale = 0.4 end
        if fScale > 3 then fScale = 3 end
        local gScale = 1
        if IchaUIUF_GetAuraIconScale then gScale = tonumber(IchaUIUF_GetAuraIconScale()) or 1 end
        if gScale < 0.5 then gScale = 0.5 end
        if gScale > 2 then gScale = 2 end
        local bw = math.floor(24 * fScale * gScale * bSc + 0.5)
        local bh = math.floor(18 * fScale * gScale * bSc + 0.5)
        local dw = math.floor(24 * fScale * gScale * dSc + 0.5)
        local dh = math.floor(18 * fScale * gScale * dSc + 0.5)
        if bw < 2 then bw = 2 end
        if bh < 2 then bh = 2 end
        if dw < 2 then dw = 2 end
        if dh < 2 then dh = 2 end
        if kind == "party" then
            -- layoutAuraSplitTop: buffs left and debuffs right, above the frame, rows grow up.
            local outset = math.floor(bw * 0.08 + 0.5)
            if outset < 2 then outset = 2 end
            local framePad = 3
            local rowPad = bPad
            if dPad > rowPad then rowPad = dPad end
            local bi, di, row = 1, 1, 0
            while row < 4 and (bi <= buffN or di <= debuffN) do
                local remB = buffN - bi + 1
                if remB < 0 then remB = 0 end
                local remD = debuffN - di + 1
                if remD < 0 then remD = 0 end
                local bTake = remB
                if bTake > bRow then bTake = bRow end
                local dTake = remD
                if dTake > dRow then dTake = dRow end
                if bTake <= 0 and dTake <= 0 then break end
                local y = outset + row * (bh + rowPad)
                local c
                for c = 0, bTake - 1 do
                    local tex = sampleBuffs[bi]
                    if tex then
                        local x = framePad + outset + c * (bw + bPad)
                        prepSample(tex, bw, bh)
                        tex:SetPoint("BOTTOMLEFT", bars, "TOPLEFT", x + bOx, y + bOy)
                        tex:Show()
                    end
                    bi = bi + 1
                end
                for c = 0, dTake - 1 do
                    local tex = sampleDebuffs[di]
                    if tex then
                        local x = framePad + outset + c * (bw + dPad)
                        prepSample(tex, dw, dh)
                        tex:SetPoint("BOTTOMRIGHT", bars, "TOPRIGHT", -x + dOx, y + dOy)
                        tex:Show()
                    end
                    di = di + 1
                end
                row = row + 1
            end
            local hi
            for hi = bi, table.getn(sampleBuffs) do
                if sampleBuffs[hi] then sampleBuffs[hi]:Hide() end
            end
            for hi = di, table.getn(sampleDebuffs) do
                if sampleDebuffs[hi] then sampleDebuffs[hi]:Hide() end
            end
        elseif kind == "raid" then
            seatInset(sampleBuffs, buffN, bRow, bAnc, bOx, bOy, bw, bh, bPad)
            seatInset(sampleDebuffs, debuffN, dRow, dAnc, dOx, dOy, dw, dh, dPad)
        else
            seatLive(sampleBuffs, buffN, bRow, bAnc, bOx, bOy, bw, bh, bPad, true)
            seatLive(sampleDebuffs, debuffN, dRow, dAnc, dOx, dOy, dw, dh, dPad, false)
        end
    end

    local edCol = 1
    local function addHeader(text, showFn, column)
        if column then edCol = column end
        local f = CreateFrame("Frame", nil, page)
        f:SetWidth(320)
        f:SetHeight(16)
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", f, "LEFT", 0, 0)
        fs:SetText(text)
        IchaUI_PaintGoldFont(fs, 0.93, 0.78, 0.35)
        IchaUI_OptNote("Frames", text, nil)
        table.insert(ed.rows, { frame = f, h = 16, show = showFn or function() return true end, col = edCol })
    end

    local function addSlider(label, lo, hi, step, digits, get, set, showFn, white)
        local f = CreateFrame("Frame", nil, page)
        f:SetWidth(340)
        f:SetHeight(20)
        local capFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        capFS:SetPoint("LEFT", f, "LEFT", 0, 0)
        capFS:SetWidth(96)
        capFS:SetJustifyH("LEFT")
        capFS:SetText(label)
        if white then
            local fp, fsz, fl = GameFontHighlightSmall:GetFont()
            if fp and capFS.SetFont then capFS:SetFont(fp, fsz or 10, fl or "") end
            capFS:SetTextColor(1, 1, 1)
        else
            capFS:SetTextColor(0.9, 0.88, 0.8)
        end
        local sl = CreateFrame("Slider", nil, f, "OptionsSliderTemplate")
        sl:SetPoint("LEFT", capFS, "RIGHT", 6, 0)
        sl:SetWidth(130)
        sl:SetHeight(16)
        sl:SetMinMaxValues(lo, hi)
        sl:SetValueStep(step)
        do
            local regions = { sl:GetRegions() }
            local ri
            for ri = 1, table.getn(regions) do
                local r = regions[ri]
                if r and r.SetText and r.GetObjectType and r:GetObjectType() == "FontString" then
                    r:SetText("")
                    if IchaUI_DyeFs then
                        IchaUI_DyeFs(r, 1, 1, 1)
                    else
                        r:SetTextColor(1, 1, 1)
                    end
                end
            end
        end
        local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        box:SetWidth(46)
        box:SetHeight(16)
        box:SetPoint("LEFT", sl, "RIGHT", 8, 0)
        box:SetAutoFocus(false)
        box:SetJustifyH("CENTER")
        IchaUI_StyleInputBox(box)
        local function fmt(v)
            if digits and digits > 0 then return string.format("%." .. digits .. "f", v) end
            return string.format("%.0f", v)
        end
        local function clampV(raw)
            local v = tonumber(raw)
            if not v then v = lo end
            if v < lo then v = lo end
            if v > hi then v = hi end
            if step and step > 0 then
                local n = math.floor((v - lo) / step + 0.5)
                v = lo + n * step
            end
            if v < lo then v = lo end
            if v > hi then v = hi end
            return v
        end
        local function paint()
            local was = ed.busy
            ed.busy = true
            local v = get(ed.kind)
            if not v then v = lo end
            sl:SetValue(v)
            box:SetText(fmt(v))
            ed.busy = was
        end
        local function commit(raw)
            if ed.busy then return end
            local v = clampV(raw)
            ed.busy = true
            sl:SetValue(v)
            box:SetText(fmt(v))
            set(ed.kind, v)
            local n
            for n = 1, table.getn(ed.rows) do
                if ed.rows[n].refresh and ed.rows[n].refresh ~= paint then
                    ed.rows[n].refresh()
                end
            end
            ed.busy = false
            paintPreview()
        end
        sl:SetScript("OnValueChanged", function()
            if ed.busy then return end
            local v = this:GetValue()
            box:SetText(fmt(v))
            ed.busy = true
            set(ed.kind, v)
            local n
            for n = 1, table.getn(ed.rows) do
                if ed.rows[n].refresh and ed.rows[n].refresh ~= paint then
                    ed.rows[n].refresh()
                end
            end
            ed.busy = false
            paintPreview()
        end)
        box:SetScript("OnEnterPressed", function()
            commit(this:GetText())
            this:ClearFocus()
        end)
        box:SetScript("OnEditFocusLost", function()
            commit(this:GetText())
        end)
        if xyList then table.insert(xyList, paint) end
        IchaUI_OptNote("Frames", label, nil)
        table.insert(ed.rows, { frame = f, h = 20, show = showFn or function() return true end, refresh = paint, col = edCol })
    end

    local function addButton(text, w, onClick, showFn, refreshFn)
        local f = CreateFrame("Frame", nil, page)
        f:SetWidth(520)
        f:SetHeight(24)
        local b = goldButton(f, text, w or 140, 20)
        b:SetPoint("LEFT", f, "LEFT", 0, 0)
        b:SetScript("OnClick", function()
            onClick(ed.kind, b)
            if refreshFn then refreshFn(ed.kind, b) end
            paintPreview()
        end)
        if refreshFn and btnList then
            table.insert(btnList, function() refreshFn(ed.kind, b) end)
        end
        table.insert(ed.rows, { frame = f, h = 20, show = showFn or function() return true end, col = edCol })
        return b
    end

    local function always() return true end
    local function portOnly(kind) return hasPortrait(kind) end
    local function notRaid(kind) return kind ~= "raid" end
    local function partyOnly(kind) return kind == "party" end
    local function raidOnly(kind) return kind == "raid" end
    local function groupOnly(kind) return kind == "party" or kind == "raid" or kind == "combat" end

    addHeader("Frame", always, 1)
    addSlider("Width", 1, 600, 1, 0, function(kind)
        local m = metric(kind)
        return (m and m.width) or 220
    end, function(kind, v) setField(kind, "width", v) end, always)
    addSlider("Height", 1, 420, 1, 0, function(kind)
        local m = metric(kind)
        return (m and m.height) or 48
    end, function(kind, v) setField(kind, "height", v) end, always)
    addSlider("Scale", 0.4, 3, 0.05, 2, function(kind)
        local m = metric(kind)
        return (m and m.scale) or 1
    end, function(kind, v) setField(kind, "scale", v) end, always)

    local xy = CreateFrame("Frame", nil, page)
    xy:SetWidth(520)
    xy:SetHeight(24)
    local xl = xy:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    xl:SetPoint("LEFT", xy, "LEFT", 0, 0)
    xl:SetText("X")
    xl:SetTextColor(0.9, 0.88, 0.8)
    local xBox = CreateFrame("EditBox", nil, xy, "InputBoxTemplate")
    xBox:SetWidth(52)
    xBox:SetHeight(18)
    xBox:SetPoint("LEFT", xl, "RIGHT", 6, 0)
    xBox:SetAutoFocus(false)
    IchaUI_StyleInputBox(xBox)
    local yl = xy:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    yl:SetPoint("LEFT", xBox, "RIGHT", 10, 0)
    yl:SetText("Y")
    yl:SetTextColor(0.9, 0.88, 0.8)
    local yBox = CreateFrame("EditBox", nil, xy, "InputBoxTemplate")
    yBox:SetWidth(52)
    yBox:SetHeight(18)
    yBox:SetPoint("LEFT", yl, "RIGHT", 6, 0)
    yBox:SetAutoFocus(false)
    IchaUI_StyleInputBox(yBox)
    local function paintXY()
        local x, yv = getPos(ed.kind)
        xBox:SetText(string.format("%.0f", tonumber(x) or 0))
        yBox:SetText(string.format("%.0f", tonumber(yv) or 0))
    end
    local function applyXY()
        setPos(ed.kind, tonumber(xBox:GetText()) or 0, tonumber(yBox:GetText()) or 0)
        paintXY()
    end
    xBox:SetScript("OnEnterPressed", function() applyXY(); this:ClearFocus() end)
    yBox:SetScript("OnEnterPressed", function() applyXY(); this:ClearFocus() end)
    xBox:SetScript("OnEditFocusLost", function() applyXY() end)
    yBox:SetScript("OnEditFocusLost", function() applyXY() end)
    local nL = goldButton(xy, "<", 22, 18)
    nL:SetPoint("LEFT", yBox, "RIGHT", 8, 0)
    nL:SetScript("OnClick", function() nudge(ed.kind, -1, 0); paintXY() end)
    local nR = goldButton(xy, ">", 22, 18)
    nR:SetPoint("LEFT", nL, "RIGHT", 2, 0)
    nR:SetScript("OnClick", function() nudge(ed.kind, 1, 0); paintXY() end)
    local nU = goldButton(xy, "^", 22, 18)
    nU:SetPoint("LEFT", nR, "RIGHT", 2, 0)
    nU:SetScript("OnClick", function() nudge(ed.kind, 0, 1); paintXY() end)
    local nD = goldButton(xy, "v", 22, 18)
    nD:SetPoint("LEFT", nU, "RIGHT", 2, 0)
    nD:SetScript("OnClick", function() nudge(ed.kind, 0, -1); paintXY() end)
    if xyList then table.insert(xyList, paintXY) end
    table.insert(ed.rows, { frame = xy, h = 22, show = always, col = 1 })

    local moveRow = CreateFrame("Frame", nil, page)
    moveRow:SetWidth(520)
    moveRow:SetHeight(24)
    local moveB = goldButton(moveRow, "Move", 64, 20)
    moveB:SetPoint("LEFT", moveRow, "LEFT", 0, 0)
    moveB:SetScript("OnClick", function() IchaUIUF_BeginPlace(ed.kind) end)
    local showB = goldButton(moveRow, "Show", 56, 20)
    showB:SetPoint("LEFT", moveB, "RIGHT", 6, 0)
    showB:SetScript("OnClick", function() setField(ed.kind, "hidden", false) end)
    local hideB = goldButton(moveRow, "Hide", 56, 20)
    hideB:SetPoint("LEFT", showB, "RIGHT", 4, 0)
    hideB:SetScript("OnClick", function() setField(ed.kind, "hidden", true) end)
    local enB = goldButton(moveRow, "Enabled: On", 110, 20)
    enB:SetPoint("LEFT", hideB, "RIGHT", 8, 0)
    enB:SetScript("OnClick", function()
        local fr = IchaUIUF_Get and IchaUIUF_Get(ed.kind)
        local hidden = fr and fr.hidden
        setField(ed.kind, "hidden", not hidden)
        if enB.label then
            if hidden then enB.label:SetText("Enabled: On") else enB.label:SetText("Enabled: Off") end
        end
    end)
    table.insert(ed.rows, { frame = moveRow, h = 22, show = always, col = 1 })
    IchaUI_OptNote("Frames", "Move", nil)

    addSlider("Pad", 0, 40, 1, 0, function(kind)
        local m = metric(kind)
        return (m and m.pad) or 0
    end, function(kind, v) setField(kind, "pad", v) end, groupOnly)
    addSlider("Columns", 1, 40, 1, 0, function(kind)
        local m = metric(kind)
        return (m and m.cols) or 1
    end, function(kind, v) setField(kind, "cols", v) end, function(kind)
        return kind == "raid" or kind == "combat"
    end)
    addSlider("Rows", 1, 40, 1, 0, function(kind)
        local m = metric(kind)
        return (m and m.rows) or 1
    end, function(kind, v) setField(kind, "rows", v) end, function(kind)
        return kind == "raid" or kind == "combat"
    end)
    addButton("Growth", 200, function(kind, b)
        local order = { "center", "left", "right", "up", "down", "grid" }
        local m = metric(kind)
        local cur = (m and m.growth) or "center"
        local idx = 1
        local i
        for i = 1, table.getn(order) do
            if order[i] == cur then idx = i end
        end
        idx = idx + 1
        if idx > table.getn(order) then idx = 1 end
        setField(kind, "growth", order[idx])
        b.label:SetText("Growth: " .. order[idx])
    end, partyOnly, function(kind, b)
        local m = metric(kind)
        b.label:SetText("Growth: " .. ((m and m.growth) or "center"))
    end)

    addHeader("Bars", always)
    addSlider("Health ratio", 1, 99, 1, 0, function(kind)
        if IchaUIUF_GetBarRatioPct then return IchaUIUF_GetBarRatioPct(kind) end
        return 80
    end, function(kind, v)
        if IchaUIUF_SetBarRatio then IchaUIUF_SetBarRatio(kind, v) end
    end, always)
    addSlider("Health height", 1, 200, 1, 0, function(kind)
        if IchaUIUF_GetBarSplit then
            local hpH = IchaUIUF_GetBarSplit(kind)
            return hpH
        end
        return 33
    end, function(kind, v)
        if IchaUIUF_SetBarHealth then IchaUIUF_SetBarHealth(kind, v) end
    end, always)
    addSlider("Power height", 1, 200, 1, 0, function(kind)
        if IchaUIUF_GetBarSplit then
            local _, mpH = IchaUIUF_GetBarSplit(kind)
            return mpH
        end
        return 7
    end, function(kind, v)
        if IchaUIUF_SetBarPower then IchaUIUF_SetBarPower(kind, v) end
    end, always)
    addButton("Health texture", 200, function(kind, b)
        local name = "Blizzard"
        if IchaUIUF_CycleBarFill then name = IchaUIUF_CycleBarFill(kind, "health") or name end
        b.label:SetText("Health: " .. name)
    end, always, function(kind, b)
        local name = "Blizzard"
        if IchaUIUF_BarFillName then name = IchaUIUF_BarFillName(kind, "health") or name end
        b.label:SetText("Health: " .. name)
    end)
    addButton("Power texture", 200, function(kind, b)
        local name = "Blizzard"
        if IchaUIUF_CycleBarFill then name = IchaUIUF_CycleBarFill(kind, "power") or name end
        b.label:SetText("Power: " .. name)
    end, always, function(kind, b)
        local name = "Blizzard"
        if IchaUIUF_BarFillName then name = IchaUIUF_BarFillName(kind, "power") or name end
        b.label:SetText("Power: " .. name)
    end)

    addHeader("Portrait", portOnly, 2)
    addButton("Portrait", 120, function(kind, b)
        local m = metric(kind)
        local on = not (m and m.portraitEnabled ~= false)
        setField(kind, "portrait", on)
        b.label:SetText(on and "Portrait: On" or "Portrait: Off")
    end, portOnly, function(kind, b)
        local m = metric(kind)
        local on = (not m) or (m.portraitEnabled ~= false)
        b.label:SetText(on and "Portrait: On" or "Portrait: Off")
    end)
    addSlider("Portrait scale", 0.8, 2.5, 0.05, 2, function(kind)
        local m = metric(kind)
        return (m and m.portraitScale) or 1.22
    end, function(kind, v) setField(kind, "portraitScale", v) end, portOnly)
    addSlider("Ring scale", 0.9, 1.4, 0.01, 2, function(kind)
        local m = metric(kind)
        return (m and m.portraitRing) or 1.28
    end, function(kind, v) setField(kind, "portraitRing", v) end, portOnly)
    addSlider("Portrait X", -40, 40, 1, 0, function(kind)
        local m = metric(kind)
        return (m and m.portraitOffsetX) or 0
    end, function(kind, v) setField(kind, "portraitOffsetX", v) end, portOnly)
    addSlider("Portrait Y", -40, 40, 1, 0, function(kind)
        local m = metric(kind)
        return (m and m.portraitOffsetY) or 0
    end, function(kind, v) setField(kind, "portraitOffsetY", v) end, portOnly)
    addSlider("Badge scale", 0.5, 2, 0.05, 2, function(kind)
        local m = metric(kind)
        return (m and m.badgeScale) or 1
    end, function(kind, v) setField(kind, "badgeScale", v) end, portOnly)
    addSlider("Badge X", -40, 40, 1, 0, function(kind)
        local m = metric(kind)
        return (m and m.badgeOffsetX) or 0
    end, function(kind, v) setField(kind, "badgeOffsetX", v) end, portOnly)
    addSlider("Badge Y", -40, 40, 1, 0, function(kind)
        local m = metric(kind)
        return (m and m.badgeOffsetY) or 0
    end, function(kind, v) setField(kind, "badgeOffsetY", v) end, portOnly)
    addSlider("Badge angle", 0, 360, 1, 0, function(kind)
        local m = metric(kind)
        return (m and m.badgeAngle) or 0
    end, function(kind, v) setField(kind, "badgeAngle", v) end, portOnly, true)
    local function playerOnly(kind) return kind == "player" end
    addHeader("Shield orbs", playerOnly, 2)
    addSlider("Size", 6, 28, 1, 0, function(kind)
        local m = metric(kind)
        return (m and m.shieldChargeSize) or 10
    end, function(kind, v) setField(kind, "shieldChargeSize", v) end, playerOnly, true)
    addSlider("Spread", 10, 360, 1, 0, function(kind)
        local m = metric(kind)
        return (m and m.shieldChargeSpread) or 90
    end, function(kind, v) setField(kind, "shieldChargeSpread", v) end, playerOnly, true)
    addSlider("Sh Rot", -360, 360, 1, 0, function(kind)
        local m = metric(kind)
        return (m and m.shieldChargeAngle) or 0
    end, function(kind, v) setField(kind, "shieldChargeAngle", v) end, playerOnly, true)
    addSlider("Sh X", -40, 40, 1, 0, function(kind)
        local m = metric(kind)
        return (m and m.shieldChargeOffsetX) or 0
    end, function(kind, v) setField(kind, "shieldChargeOffsetX", v) end, playerOnly, true)
    addSlider("Sh Y", -40, 40, 1, 0, function(kind)
        local m = metric(kind)
        return (m and m.shieldChargeOffsetY) or 0
    end, function(kind, v) setField(kind, "shieldChargeOffsetY", v) end, playerOnly, true)
    addButton("Badge on", 160, function(kind, b)
        local m = metric(kind)
        local cur = (m and m.badgeHost) or "portrait"
        local nxt = "frame"
        if cur == "frame" then nxt = "portrait" end
        setField(kind, "badgeHost", nxt)
        b.label:SetText(nxt == "frame" and "Badge on: Frame" or "Badge on: Portrait")
    end, portOnly, function(kind, b)
        local m = metric(kind)
        local host = (m and m.badgeHost) or "portrait"
        b.label:SetText(host == "frame" and "Badge on: Frame" or "Badge on: Portrait")
    end)
    addButton("Portrait badge", 150, function(kind, b)
        if IchaUIUF_ToggleLevelPortrait then IchaUIUF_ToggleLevelPortrait(kind) end
        local on = IchaUI_LevelPortraitOn and IchaUI_LevelPortraitOn(kind)
        b.label:SetText(on and "Port badge: On" or "Port badge: Off")
    end, function(kind) return kind ~= "raid" end, function(kind, b)
        local on = IchaUI_LevelPortraitOn and IchaUI_LevelPortraitOn(kind)
        b.label:SetText(on and "Port badge: On" or "Port badge: Off")
    end)
    addButton("Level on bar", 140, function(kind, b)
        if IchaUIUF_CycleLevelBar then IchaUIUF_CycleLevelBar(kind) end
        if IchaUI_LevelBarLabel then b.label:SetText(IchaUI_LevelBarLabel(kind)) end
    end, always, function(kind, b)
        if IchaUI_LevelBarLabel then b.label:SetText(IchaUI_LevelBarLabel(kind)) end
    end)

    addHeader("Text", always, 3)
    addSlider("Name scale", 0.4, 3, 0.05, 2, function(kind)
        local t = IchaUIUF_GetTextSettings and IchaUIUF_GetTextSettings(kind)
        return (t and t.nameScale) or 1
    end, function(kind, v)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "nameScale", v) end
    end, always)
    addSlider("Health text scale", 0.4, 3, 0.05, 2, function(kind)
        local t = IchaUIUF_GetTextSettings and IchaUIUF_GetTextSettings(kind)
        return (t and t.hpScale) or 1
    end, function(kind, v)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "hpScale", v) end
    end, always)
    addSlider("Power text scale", 0.4, 3, 0.05, 2, function(kind)
        local t = IchaUIUF_GetTextSettings and IchaUIUF_GetTextSettings(kind)
        return (t and t.powerScale) or 1
    end, function(kind, v)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "powerScale", v) end
    end, always)
    addSlider("Name X", -200, 200, 1, 0, function(kind)
        local t = IchaUIUF_GetTextSettings and IchaUIUF_GetTextSettings(kind)
        return (t and t.nameX) or 0
    end, function(kind, v)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "nameX", v) end
    end, always)
    addSlider("Name Y", -200, 200, 1, 0, function(kind)
        local t = IchaUIUF_GetTextSettings and IchaUIUF_GetTextSettings(kind)
        return (t and t.nameY) or 0
    end, function(kind, v)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "nameY", v) end
    end, always)
    addSlider("Health text X", -200, 200, 1, 0, function(kind)
        local t = IchaUIUF_GetTextSettings and IchaUIUF_GetTextSettings(kind)
        return (t and t.hpX) or 0
    end, function(kind, v)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "hpX", v) end
    end, always)
    addSlider("Health text Y", -200, 200, 1, 0, function(kind)
        local t = IchaUIUF_GetTextSettings and IchaUIUF_GetTextSettings(kind)
        return (t and t.hpY) or 0
    end, function(kind, v)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "hpY", v) end
    end, always)
    addButton("Health percent", 150, function(kind, b)
        local t = IchaUIUF_GetTextSettings and IchaUIUF_GetTextSettings(kind)
        local on = not (t and t.showHpPct ~= false)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "showHpPct", on) end
        b.label:SetText(on and "Health percent: On" or "Health percent: Off")
    end, always, function(kind, b)
        local t = IchaUIUF_GetTextSettings and IchaUIUF_GetTextSettings(kind)
        local on = (not t) or (t.showHpPct ~= false)
        b.label:SetText(on and "Health percent: On" or "Health percent: Off")
    end)
    addButton("Power text", 140, function(kind, b)
        local t = IchaUIUF_GetTextSettings and IchaUIUF_GetTextSettings(kind)
        local on = not (t and t.showPowerText ~= false)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "showPowerText", on) end
        b.label:SetText(on and "Power text: On" or "Power text: Off")
    end, always, function(kind, b)
        local t = IchaUIUF_GetTextSettings and IchaUIUF_GetTextSettings(kind)
        local on = (not t) or (t.showPowerText ~= false)
        b.label:SetText(on and "Power text: On" or "Power text: Off")
    end)
    addSlider("Buff pad", 0, 12, 1, 0, function(kind)
        local t = IchaUIUF_GetTextSettings and IchaUIUF_GetTextSettings(kind)
        return (t and t.buffPad) or 2
    end, function(kind, v)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "buffPad", v) end
    end, always)
    addSlider("Debuff pad", 0, 12, 1, 0, function(kind)
        local t = IchaUIUF_GetTextSettings and IchaUIUF_GetTextSettings(kind)
        return (t and t.debuffPad) or 2
    end, function(kind, v)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "debuffPad", v) end
    end, always)

    local function auraGet(kind, field, fallback)
        if IchaUIUF_AuraLayoutGet then return IchaUIUF_AuraLayoutGet(kind, field) end
        return fallback
    end
    local AURA_ANCHORS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
    local function cycleAuraAnchor(kind, field)
        local cur = auraGet(kind, field, "TOPLEFT")
        local idx = 1
        local i
        for i = 1, table.getn(AURA_ANCHORS) do
            if AURA_ANCHORS[i] == cur then idx = i end
        end
        idx = idx + 1
        if idx > table.getn(AURA_ANCHORS) then idx = 1 end
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, field, AURA_ANCHORS[idx]) end
        return AURA_ANCHORS[idx]
    end
    addButton("Buff anchor", 180, function(kind, b)
        local a = cycleAuraAnchor(kind, "buffAnchor")
        b.label:SetText("Buff anchor: " .. a)
    end, always, function(kind, b)
        b.label:SetText("Buff anchor: " .. auraGet(kind, "buffAnchor", "TOPLEFT"))
    end)
    addSlider("Buff scale", 0.4, 3, 0.05, 2, function(kind)
        local t = IchaUIUF_GetTextSettings and IchaUIUF_GetTextSettings(kind)
        return (t and t.buffScale) or 1
    end, function(kind, v)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "buffScale", v) end
    end, always)
    addSlider("Buff X", -80, 80, 1, 0, function(kind)
        return auraGet(kind, "buffX", 0)
    end, function(kind, v)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "buffOffsetX", v) end
    end, always)
    addSlider("Buff Y", -80, 80, 1, 0, function(kind)
        return auraGet(kind, "buffY", 0)
    end, function(kind, v)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "buffOffsetY", v) end
    end, always)
    addSlider("Buffs shown", 0, 20, 1, 0, function(kind)
        return auraGet(kind, "buffsShown", 16)
    end, function(kind, v)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "buffsShown", v) end
    end, always)
    addSlider("Buffs per row", 1, 20, 1, 0, function(kind)
        return auraGet(kind, "buffPerRow", 8)
    end, function(kind, v)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "buffPerRow", v) end
    end, always)
    addButton("Debuff anchor", 180, function(kind, b)
        local a = cycleAuraAnchor(kind, "debuffAnchor")
        b.label:SetText("Debuff anchor: " .. a)
    end, always, function(kind, b)
        b.label:SetText("Debuff anchor: " .. auraGet(kind, "debuffAnchor", "BOTTOMLEFT"))
    end)
    addSlider("Debuff scale", 0.4, 3, 0.05, 2, function(kind)
        local t = IchaUIUF_GetTextSettings and IchaUIUF_GetTextSettings(kind)
        return (t and t.debuffScale) or 1
    end, function(kind, v)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "debuffScale", v) end
    end, always)
    addSlider("Debuff X", -80, 80, 1, 0, function(kind)
        return auraGet(kind, "debuffX", 0)
    end, function(kind, v)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "debuffOffsetX", v) end
    end, always)
    addSlider("Debuff Y", -80, 80, 1, 0, function(kind)
        return auraGet(kind, "debuffY", 0)
    end, function(kind, v)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "debuffOffsetY", v) end
    end, always)
    addSlider("Debuffs shown", 0, 20, 1, 0, function(kind)
        return auraGet(kind, "debuffsShown", 16)
    end, function(kind, v)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "debuffsShown", v) end
    end, always)
    addSlider("Debuffs per row", 1, 20, 1, 0, function(kind)
        return auraGet(kind, "debuffPerRow", 8)
    end, function(kind, v)
        if IchaUIUF_SetTextSetting then IchaUIUF_SetTextSetting(kind, "debuffPerRow", v) end
    end, always)

    local function auraFilterMode(kind, which)
        local f = IchaUIUF_GetAuraFilters and IchaUIUF_GetAuraFilters(kind)
        if not f then return "all" end
        if which == "debuff" then
            if f.whitelistDebuffsOnly then return "whitelist" end
            if f.showAllDebuffs then return "all" end
            if f.showMyDebuffs then return "mine" end
            return "none"
        end
        if f.whitelistBuffsOnly then return "whitelist" end
        if f.showAllBuffs then return "all" end
        if f.showMyBuffs then return "mine" end
        return "none"
    end
    local function auraFilterLabel(kind, which)
        local mode = auraFilterMode(kind, which)
        local name = "All"
        if mode == "mine" then
            name = "My"
        elseif mode == "whitelist" then
            name = "Whitelist"
        elseif mode == "none" then
            if which == "debuff" and kind == "raid" then
                name = "Dispel"
            else
                name = "None"
            end
        end
        if which == "debuff" then return "Debuffs: " .. name end
        return "Buffs: " .. name
    end
    local AURA_FILTER_MODES = { "all", "mine", "whitelist", "none" }
    local function cycleAuraFilter(kind, which)
        local cur = auraFilterMode(kind, which)
        local idx = 1
        local i
        for i = 1, table.getn(AURA_FILTER_MODES) do
            if AURA_FILTER_MODES[i] == cur then idx = i end
        end
        idx = idx + 1
        if idx > table.getn(AURA_FILTER_MODES) then idx = 1 end
        local mode = AURA_FILTER_MODES[idx]
        if IchaUIUF_GetAuraFilters then
            local f = IchaUIUF_GetAuraFilters(kind)
            if which == "debuff" then
                f.showAllDebuffs = (mode == "all")
                f.showMyDebuffs = (mode == "mine")
                f.whitelistDebuffsOnly = (mode == "whitelist")
            else
                f.showAllBuffs = (mode == "all")
                f.showMyBuffs = (mode == "mine")
                f.whitelistBuffsOnly = (mode == "whitelist")
            end
        end
        if IchaUIUF_refreshTextKind then IchaUIUF_refreshTextKind(kind) end
        return mode
    end
    addButton("Buffs", 180, function(kind, b)
        cycleAuraFilter(kind, "buff")
        b.label:SetText(auraFilterLabel(kind, "buff"))
    end, always, function(kind, b)
        b.label:SetText(auraFilterLabel(kind, "buff"))
    end)
    addButton("Debuffs", 180, function(kind, b)
        cycleAuraFilter(kind, "debuff")
        b.label:SetText(auraFilterLabel(kind, "debuff"))
    end, always, function(kind, b)
        b.label:SetText(auraFilterLabel(kind, "debuff"))
    end)
    local function addAuraList(label, which)
        local f = CreateFrame("Frame", nil, page)
        f:SetWidth(340)
        f:SetHeight(20)
        local capFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        capFS:SetPoint("LEFT", f, "LEFT", 0, 0)
        capFS:SetWidth(96)
        capFS:SetJustifyH("LEFT")
        capFS:SetText(label)
        capFS:SetTextColor(0.9, 0.88, 0.8)
        local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        box:SetWidth(180)
        box:SetHeight(16)
        box:SetPoint("LEFT", capFS, "RIGHT", 6, 0)
        box:SetAutoFocus(false)
        box:SetJustifyH("LEFT")
        IchaUI_StyleInputBox(box)
        local function paint()
            local text = ""
            if IchaUIUF_GetAuraWhitelistText then
                text = IchaUIUF_GetAuraWhitelistText(ed.kind, which) or ""
            end
            text = string.gsub(text, "\n", ", ")
            box:SetText(text)
        end
        local function commit()
            if IchaUIUF_SetAuraWhitelist then
                IchaUIUF_SetAuraWhitelist(ed.kind, which, box:GetText() or "")
            end
            paintPreview()
        end
        box:SetScript("OnEnterPressed", function()
            commit()
            this:ClearFocus()
        end)
        box:SetScript("OnEditFocusLost", function()
            commit()
        end)
        if xyList then table.insert(xyList, paint) end
        IchaUI_OptNote("Frames", label, nil)
        table.insert(ed.rows, { frame = f, h = 20, show = always, col = edCol, refresh = paint })
    end
    addAuraList("Buff list", "buff")
    addAuraList("Debuff list", "debuff")

    addHeader("Cast bar", notRaid, 2)
    addButton("Cast bar", 140, function(kind, b)
        local s = IchaUIUF_GetCastSettings and IchaUIUF_GetCastSettings(kind)
        local on = not (s and s.castEnabled == false)
        on = not on
        if IchaUIUF_SetCastSetting then IchaUIUF_SetCastSetting(kind, "castEnabled", on) end
        b.label:SetText(on and "Cast bar: On" or "Cast bar: Off")
    end, notRaid, function(kind, b)
        local s = IchaUIUF_GetCastSettings and IchaUIUF_GetCastSettings(kind)
        local on = (not s) or (s.castEnabled ~= false)
        b.label:SetText(on and "Cast bar: On" or "Cast bar: Off")
    end)
    addSlider("Length", 80, 420, 1, 0, function(kind)
        local s = IchaUIUF_GetCastSettings and IchaUIUF_GetCastSettings(kind)
        return (s and s.castLen) or 214
    end, function(kind, v)
        if IchaUIUF_SetCastSetting then IchaUIUF_SetCastSetting(kind, "castLen", v) end
    end, notRaid)
    addSlider("Cast scale", 0.4, 3, 0.05, 2, function(kind)
        local s = IchaUIUF_GetCastSettings and IchaUIUF_GetCastSettings(kind)
        return (s and s.castScale) or 1
    end, function(kind, v)
        if IchaUIUF_SetCastSetting then IchaUIUF_SetCastSetting(kind, "castScale", v) end
    end, notRaid)
    addSlider("Cast X", -80, 80, 1, 0, function(kind)
        local s = IchaUIUF_GetCastSettings and IchaUIUF_GetCastSettings(kind)
        return (s and s.castOffsetX) or 0
    end, function(kind, v)
        if IchaUIUF_SetCastSetting then IchaUIUF_SetCastSetting(kind, "castOffsetX", v) end
    end, notRaid)
    addSlider("Cast Y", -80, 80, 1, 0, function(kind)
        local s = IchaUIUF_GetCastSettings and IchaUIUF_GetCastSettings(kind)
        return (s and s.castOffsetY) or 0
    end, function(kind, v)
        if IchaUIUF_SetCastSetting then IchaUIUF_SetCastSetting(kind, "castOffsetY", v) end
    end, notRaid)
    addButton("Cast texture", 200, function(kind, b)
        local name = "Blizzard"
        if IchaUIUF_CycleBarFill then name = IchaUIUF_CycleBarFill(kind, "cast") or name end
        b.label:SetText("Cast: " .. name)
    end, notRaid, function(kind, b)
        local name = "Blizzard"
        if IchaUIUF_BarFillName then name = IchaUIUF_BarFillName(kind, "cast") or name end
        b.label:SetText("Cast: " .. name)
    end)

    addHeader("Icons", always, 2)
    addButton("Leader", 120, function(kind, b)
        local s = IchaUIUF_GetRoleIconSettings and IchaUIUF_GetRoleIconSettings(kind, "leader")
        local on = not (s and s.show ~= false)
        if IchaUIUF_SetRoleIconSetting then IchaUIUF_SetRoleIconSetting(kind, "leader", "show", on) end
        b.label:SetText(on and "Leader: On" or "Leader: Off")
    end, always, function(kind, b)
        local s = IchaUIUF_GetRoleIconSettings and IchaUIUF_GetRoleIconSettings(kind, "leader")
        local on = (not s) or (s.show ~= false)
        b.label:SetText(on and "Leader: On" or "Leader: Off")
    end)
    addButton("Leader anchor", 160, function(kind, b)
        local a = "CENTER"
        if IchaUIUF_CycleRoleAnchor then a = IchaUIUF_CycleRoleAnchor(kind, "leader") or a end
        b.label:SetText("Leader anchor: " .. a)
    end, always, function(kind, b)
        local s = IchaUIUF_GetRoleIconSettings and IchaUIUF_GetRoleIconSettings(kind, "leader")
        b.label:SetText("Leader anchor: " .. ((s and s.anchor) or "CENTER"))
    end)
    addButton("Leader on", 160, function(kind, b)
        local s = IchaUIUF_GetRoleIconSettings and IchaUIUF_GetRoleIconSettings(kind, "leader")
        local cur = (s and s.host) or "portrait"
        local nxt = "frame"
        if cur == "frame" then nxt = "portrait" end
        if IchaUIUF_SetRoleIconSetting then IchaUIUF_SetRoleIconSetting(kind, "leader", "host", nxt) end
        b.label:SetText(nxt == "frame" and "Leader on: Frame" or "Leader on: Portrait")
    end, always, function(kind, b)
        local s = IchaUIUF_GetRoleIconSettings and IchaUIUF_GetRoleIconSettings(kind, "leader")
        local host = (s and s.host) or "portrait"
        b.label:SetText(host == "frame" and "Leader on: Frame" or "Leader on: Portrait")
    end)
    addSlider("Leader X", -80, 80, 1, 0, function(kind)
        local s = IchaUIUF_GetRoleIconSettings and IchaUIUF_GetRoleIconSettings(kind, "leader")
        return (s and s.x) or 0
    end, function(kind, v)
        if IchaUIUF_SetRoleIconSetting then IchaUIUF_SetRoleIconSetting(kind, "leader", "x", v) end
    end, always)
    addSlider("Leader Y", -80, 80, 1, 0, function(kind)
        local s = IchaUIUF_GetRoleIconSettings and IchaUIUF_GetRoleIconSettings(kind, "leader")
        return (s and s.y) or 0
    end, function(kind, v)
        if IchaUIUF_SetRoleIconSetting then IchaUIUF_SetRoleIconSetting(kind, "leader", "y", v) end
    end, always)
    addButton("Loot", 120, function(kind, b)
        local s = IchaUIUF_GetRoleIconSettings and IchaUIUF_GetRoleIconSettings(kind, "loot")
        local on = not (s and s.show ~= false)
        if IchaUIUF_SetRoleIconSetting then IchaUIUF_SetRoleIconSetting(kind, "loot", "show", on) end
        b.label:SetText(on and "Loot: On" or "Loot: Off")
    end, always, function(kind, b)
        local s = IchaUIUF_GetRoleIconSettings and IchaUIUF_GetRoleIconSettings(kind, "loot")
        local on = (not s) or (s.show ~= false)
        b.label:SetText(on and "Loot: On" or "Loot: Off")
    end)
    addButton("Loot anchor", 160, function(kind, b)
        local a = "CENTER"
        if IchaUIUF_CycleRoleAnchor then a = IchaUIUF_CycleRoleAnchor(kind, "loot") or a end
        b.label:SetText("Loot anchor: " .. a)
    end, always, function(kind, b)
        local s = IchaUIUF_GetRoleIconSettings and IchaUIUF_GetRoleIconSettings(kind, "loot")
        b.label:SetText("Loot anchor: " .. ((s and s.anchor) or "CENTER"))
    end)
    addButton("Loot on", 160, function(kind, b)
        local s = IchaUIUF_GetRoleIconSettings and IchaUIUF_GetRoleIconSettings(kind, "loot")
        local cur = (s and s.host) or "portrait"
        local nxt = "frame"
        if cur == "frame" then nxt = "portrait" end
        if IchaUIUF_SetRoleIconSetting then IchaUIUF_SetRoleIconSetting(kind, "loot", "host", nxt) end
        b.label:SetText(nxt == "frame" and "Loot on: Frame" or "Loot on: Portrait")
    end, always, function(kind, b)
        local s = IchaUIUF_GetRoleIconSettings and IchaUIUF_GetRoleIconSettings(kind, "loot")
        local host = (s and s.host) or "portrait"
        b.label:SetText(host == "frame" and "Loot on: Frame" or "Loot on: Portrait")
    end)
    addSlider("Loot X", -80, 80, 1, 0, function(kind)
        local s = IchaUIUF_GetRoleIconSettings and IchaUIUF_GetRoleIconSettings(kind, "loot")
        return (s and s.x) or 0
    end, function(kind, v)
        if IchaUIUF_SetRoleIconSetting then IchaUIUF_SetRoleIconSetting(kind, "loot", "x", v) end
    end, always)
    addSlider("Loot Y", -80, 80, 1, 0, function(kind)
        local s = IchaUIUF_GetRoleIconSettings and IchaUIUF_GetRoleIconSettings(kind, "loot")
        return (s and s.y) or 0
    end, function(kind, v)
        if IchaUIUF_SetRoleIconSetting then IchaUIUF_SetRoleIconSetting(kind, "loot", "y", v) end
    end, always)
    addButton("Combat hide", 140, function(kind, b)
        local s = IchaUIUF_GetRoleGate and IchaUIUF_GetRoleGate(kind)
        local on = not (s and s.hideCombat)
        if IchaUIUF_SetRoleGate then IchaUIUF_SetRoleGate(kind, "hideCombat", on) end
        b.label:SetText(on and "Combat hide: On" or "Combat hide: Off")
    end, always, function(kind, b)
        local s = IchaUIUF_GetRoleGate and IchaUIUF_GetRoleGate(kind)
        local on = s and s.hideCombat
        b.label:SetText(on and "Combat hide: On" or "Combat hide: Off")
    end)
    addButton("Hover only", 140, function(kind, b)
        local s = IchaUIUF_GetRoleGate and IchaUIUF_GetRoleGate(kind)
        local on = not (s and s.hoverOnly)
        if IchaUIUF_SetRoleGate then IchaUIUF_SetRoleGate(kind, "hoverOnly", on) end
        b.label:SetText(on and "Hover only: On" or "Hover only: Off")
    end, always, function(kind, b)
        local s = IchaUIUF_GetRoleGate and IchaUIUF_GetRoleGate(kind)
        local on = s and s.hoverOnly
        b.label:SetText(on and "Hover only: On" or "Hover only: Off")
    end)
    addButton("Mark", 110, function(kind, b)
        local s = IchaUIUF_GetMarkSettings and IchaUIUF_GetMarkSettings(kind)
        local on = not (s and s.markShow ~= false)
        if IchaUIUF_SetMarkSetting then IchaUIUF_SetMarkSetting(kind, "markShow", on) end
        b.label:SetText(on and "Mark: On" or "Mark: Off")
    end, always, function(kind, b)
        local s = IchaUIUF_GetMarkSettings and IchaUIUF_GetMarkSettings(kind)
        local on = (not s) or (s.markShow ~= false)
        b.label:SetText(on and "Mark: On" or "Mark: Off")
    end)
    addButton("Mark anchor", 160, function(kind, b)
        local a = "CENTER"
        if IchaUIUF_CycleMarkAnchor then a = IchaUIUF_CycleMarkAnchor(kind) or a end
        b.label:SetText("Mark anchor: " .. a)
    end, always, function(kind, b)
        local s = IchaUIUF_GetMarkSettings and IchaUIUF_GetMarkSettings(kind)
        b.label:SetText("Mark anchor: " .. ((s and s.markAnchor) or "CENTER"))
    end)
    addButton("Mark on", 160, function(kind, b)
        local s = IchaUIUF_GetMarkSettings and IchaUIUF_GetMarkSettings(kind)
        local cur = (s and s.host) or "portrait"
        local nxt = "frame"
        if cur == "frame" then nxt = "portrait" end
        if IchaUIUF_SetMarkSetting then IchaUIUF_SetMarkSetting(kind, "host", nxt) end
        b.label:SetText(nxt == "frame" and "Mark on: Frame" or "Mark on: Portrait")
    end, always, function(kind, b)
        local s = IchaUIUF_GetMarkSettings and IchaUIUF_GetMarkSettings(kind)
        local host = (s and s.host) or "portrait"
        b.label:SetText(host == "frame" and "Mark on: Frame" or "Mark on: Portrait")
    end)
    addSlider("Mark X", -80, 80, 1, 0, function(kind)
        local s = IchaUIUF_GetMarkSettings and IchaUIUF_GetMarkSettings(kind)
        return (s and s.markX) or 0
    end, function(kind, v)
        if IchaUIUF_SetMarkSetting then IchaUIUF_SetMarkSetting(kind, "markX", v) end
    end, always)
    addSlider("Mark Y", -80, 80, 1, 0, function(kind)
        local s = IchaUIUF_GetMarkSettings and IchaUIUF_GetMarkSettings(kind)
        return (s and s.markY) or 0
    end, function(kind, v)
        if IchaUIUF_SetMarkSetting then IchaUIUF_SetMarkSetting(kind, "markY", v) end
    end, always)

    local function layout()
        local pageW = page:GetWidth() or 1080
        if pageW < 400 then pageW = 1080 end
        local gap = 8
        local colW = math.floor((pageW - 16 - gap * 2) / 3)
        if colW < 240 then colW = 240 end
        local topY = -26
        local previewH = 148
        preview:ClearAllPoints()
        preview:SetPoint("TOPLEFT", page, "TOPLEFT", 8, topY)
        preview:SetWidth(colW)
        preview:SetHeight(previewH)
        local ys = { topY - previewH - 8, topY, topY }
        local n
        for n = 1, table.getn(ed.rows) do
            local row = ed.rows[n]
            if row.show(ed.kind) then
                local c = row.col or 1
                if c < 1 then c = 1 end
                if c > 3 then c = 3 end
                local x = 8 + (c - 1) * (colW + gap)
                row.frame:SetWidth(colW)
                row.frame:ClearAllPoints()
                row.frame:SetPoint("TOPLEFT", page, "TOPLEFT", x, ys[c])
                row.frame:Show()
                ys[c] = ys[c] - row.h
            else
                row.frame:Hide()
            end
        end
        local bottom = ys[1]
        if ys[2] < bottom then bottom = ys[2] end
        if ys[3] < bottom then bottom = ys[3] end
        local need = -bottom + 12
        if need < 200 then need = 200 end
        page:SetHeight(need)
        if page._scroll then
            page._scroll:SetVerticalScroll(0)
            if page._scroll._tip then page._scroll._tip:Hide() end
        end
    end

    function ed.showKind(kind)
        local ok = false
        local n
        for n = 1, table.getn(KINDS) do
            if KINDS[n] == kind then ok = true end
        end
        if not ok then kind = "player" end
        ed.kind = kind
        if not IchaUIDB then IchaUIDB = {} end
        IchaUIDB.framesSubTab = kind
        paintSub(subBtns, kind)
        layout()
        paintPreview()
        paintXY()
        if IchaUI_SyncTextKind then IchaUI_SyncTextKind(kind) end
        if xyList then
            for n = 1, table.getn(xyList) do xyList[n]() end
        end
        if btnList then
            for n = 1, table.getn(btnList) do btnList[n]() end
        end
    end

    ed.showKind(ed.kind)
    if IchaUI_DyeConfigTree then IchaUI_DyeConfigTree(page, 0) end
end

function IchaUI_BuildConfigSearch(panel)
    if not panel then return end
    local box = CreateFrame("EditBox", "IchaUIOptSearch", panel, "InputBoxTemplate")
    box:SetWidth(104)
    box:SetHeight(20)
    box:SetAutoFocus(false)
    IchaUI_StyleInputBox(box)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -44)
    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 2, 1)
    label:SetText("Search")
    IchaUI_PaintGoldFont(label, 0.93, 0.78, 0.35)
    local list = CreateFrame("Frame", nil, panel)
    list:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -8, -2)
    list:SetWidth(280)
    list:SetHeight(20)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetFrameLevel(400)
    list:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    list:SetBackdropColor(0.05, 0.05, 0.06, 0.96)
    IchaUI_PaintGoldLightBorder(list, 0.9)
    list:Hide()
    local hits = {}
    local hi
    for hi = 1, 10 do
        local b = CreateFrame("Button", nil, list)
        b:SetWidth(264)
        b:SetHeight(18)
        b:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -4 - (hi - 1) * 18)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", b, "LEFT", 2, 0)
        fs:SetWidth(250)
        fs:SetJustifyH("LEFT")
        fs:SetTextColor(0.92, 0.9, 0.8)
        b.label = fs
        b:SetScript("OnClick", function()
            local e = this.entry
            if not e then return end
            box:SetText("")
            list:Hide()
            if panel.showTab then panel.showTab(e.tab) end
            if e.tab == "Frames" and e.sub and IchaUI_FrameEditorShow then
                IchaUI_FrameEditorShow(e.sub)
            end
        end)
        b:Hide()
        hits[hi] = b
    end
    local function applyFilter()
        local q = string.lower(box:GetText() or "")
        local n
        for n = 1, 10 do
            hits[n]:Hide()
            hits[n].entry = nil
        end
        if q == "" then
            list:Hide()
            return
        end
        local found = 0
        local i
        for i = 1, table.getn(IchaUI_OptCatalog) do
            local e = IchaUI_OptCatalog[i]
            local hay = string.lower((e.tab or "") .. " " .. (e.label or ""))
            if string.find(hay, q, 1, true) then
                found = found + 1
                if found <= 10 then
                    local b = hits[found]
                    local sub = ""
                    if e.sub and e.sub ~= "" then sub = " / " .. e.sub end
                    b.label:SetText((e.tab or "") .. " — " .. (e.label or "") .. sub)
                    b.entry = e
                    b:Show()
                end
            end
        end
        if found < 1 then
            list:Hide()
            return
        end
        local shown = found
        if shown > 10 then shown = 10 end
        list:SetHeight(8 + shown * 18)
        list:Show()
    end
    box:SetScript("OnTextChanged", function() applyFilter() end)
    box:SetScript("OnEscapePressed", function()
        this:SetText("")
        this:ClearFocus()
        list:Hide()
    end)
    box:SetScript("OnEnterPressed", function()
        this:ClearFocus()
    end)
    if IchaUI_DyeConfigTree then IchaUI_DyeConfigTree(panel, 0) end
end
