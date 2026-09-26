-- IchaUI Chat meter dock: TWThreat / Caw DPS windows / any named frame
-- inside "Meters" chat tabs. Each tab's host is a spare ChatFrame (first free
-- of 4-7) with every message group and channel removed, so Blizzard's dock
-- handles tabs and show/hide. A fake tab is only used if all 7 are taken.
-- Docking reparents the frame into the host, inset to the gold border, and
-- keeps a snapshot (IchaUIDB.chat.dock.snapshots) so undock restores it.
-- A meter lives on one tab only (dock.tabs[i].frames).

local M = IchaUIChat
local D = M.Register("Dock", {})

D.tabs = {}   -- runtime, parallel to dock.tabs: { host =, hostId =, fake =, order = {} }
D.docked = {} -- key -> rec (rec.tab = tab index)

local BORDER_INSET = 4 -- ChatSkin chrome: round(edge 12 * 5 / 16)

local function cfg()
    local c = M.C("dock")
    if type(c.frames) ~= "table" then c.frames = {} end
    if type(c.snapshots) ~= "table" then c.snapshots = {} end
    if type(c.tabs) ~= "table" then
        -- one-dock settings (frames / hostName / hostId / layout) become tab 1
        c.tabs = {}
        if M.count(c.frames) > 0 or (tonumber(c.hostId) or 0) > 0 then
            c.tabs[1] = { name = c.hostName or "Meters", hostId = tonumber(c.hostId) or 0, layout = c.layout or "auto", frames = c.frames }
        end
    end
    return c
end

local function tabCfg(ti)
    local t = cfg().tabs[ti]
    if type(t) ~= "table" then return nil end
    if type(t.frames) ~= "table" then t.frames = {} end
    if type(t.name) ~= "string" or t.name == "" then t.name = "Meters" end
    return t
end

function D.numTabs()
    return M.count(cfg().tabs)
end

function D.tabName(ti)
    local t = tabCfg(ti)
    return t and t.name or "?"
end

local function rt(ti)
    if not D.tabs[ti] then D.tabs[ti] = { order = {} } end
    return D.tabs[ti]
end

function D.isHost(cf)
    if not cf then return false end
    local _, r
    for _, r in pairs(D.tabs) do
        if r.host == cf then return true end
    end
    return false
end

local function isFrame(f)
    return type(f) == "table" and type(f.GetObjectType) == "function" and type(f.SetPoint) == "function"
end

------------------------------------------------------------------------
-- Presets: resolvers return a list of { frame =, key =, twt = }
------------------------------------------------------------------------
D.PRESETS = {
    { key = "twthreat", label = "TWThreat" },
    { key = "caw", label = "Caw DPS" },
}

-- Presets that were dropped: saved entries are removed and the frame undocked.
local REMOVED = { mobresist = "MobResistDisplay" }

local REFUSE = {
    UIParent = true, WorldFrame = true, Minimap = true, MinimapCluster = true,
    ChatFrameEditBox = true, IchaUIOptions = true, GameTooltip = true,
}

function D.resolve(entry)
    local out = {}
    if type(entry) ~= "table" then return out end
    local k = entry.key
    if k == "twthreat" then
        local f = getglobal("TWTMain")
        if isFrame(f) then table.insert(out, { frame = f, key = "twthreat", twt = true }) end
    elseif k == "caw" then
        local C = CAW_DPS_METER
        local view = tonumber(entry.view) or 1
        if view >= 2 then
            local v = D.cawView(view)
            if v then table.insert(out, { frame = v.frame, key = "caw#" .. view }) end
            return out
        end
        local w = (type(C) == "table" and C.window) or getglobal("CawDPSMeterWindow")
        if isFrame(w) then table.insert(out, { frame = w, key = "caw", many = entry.multi }) end
        if entry.multi then
            local i
            for i = 2, D.cawMax() do
                local v = D.cawView(i)
                if v then table.insert(out, { frame = v.frame, key = "caw#" .. i, many = true }) end
            end
        end
    elseif k == "custom" and type(entry.name) == "string" and entry.name ~= "" then
        local n = entry.name
        local f = getglobal(n)
        if isFrame(f) and not REFUSE[n] and not string.find(n, "^ChatFrame%d") then
            table.insert(out, { frame = f, key = "custom:" .. n })
        end
    end
    return out
end

------------------------------------------------------------------------
-- Caw windows: the primary CawDPSMeterWindow is view 1; extra views are
-- CAW_DPS_METER.multiWindows[2..multiWindowMax] (anonymous frames, own mode).
-- Closed views stay pooled with v.closed = true.
------------------------------------------------------------------------
function D.cawMax()
    local C = CAW_DPS_METER
    return (type(C) == "table" and tonumber(C.multiWindowMax)) or 4
end

function D.cawView(i)
    local C = CAW_DPS_METER
    if type(C) ~= "table" or type(C.multiWindows) ~= "table" then return nil end
    local v = C.multiWindows[i]
    if type(v) == "table" and isFrame(v.frame) and not v.closed then return v end
    return nil
end

local CAW_MODES = {
    damage = "Damage", healing = "Healing", overhealing = "Overheal", threat = "Threat",
    damageTaken = "Taken", deaths = "Deaths", interrupts = "Interrupts", cc = "CC",
    ccBreaks = "CC Breaks", dispels = "Dispels", buffs = "Buffs",
    debuffsCast = "Debuffs Cast", debuffsReceived = "Debuffs Recv",
}

function D.cawModeLabel(view)
    local C = CAW_DPS_METER
    if type(C) ~= "table" then return nil end
    local mode
    if (tonumber(view) or 1) >= 2 then
        local v = D.cawView(view)
        mode = v and v.mode
    else
        mode = C.mode
    end
    if not mode then return nil end
    return CAW_MODES[mode] or tostring(mode)
end

-- a closed extra view's frame (pooled): undock must not re-show it
local function cawClosedFrame(f)
    local C = CAW_DPS_METER
    if type(C) ~= "table" or type(C.multiWindowPool) ~= "table" then return false end
    local _, v
    for _, v in pairs(C.multiWindowPool) do
        if type(v) == "table" and v.frame == f and v.closed then return true end
    end
    return false
end

function D.entryLabel(entry)
    if entry.key == "custom" then return entry.name or "?" end
    if entry.key == "caw" then
        local view = tonumber(entry.view) or 1
        local l = "Caw " .. view
        local m = D.cawModeLabel(view)
        if m then l = l .. " (" .. m .. ")" end
        if view < 2 and entry.multi then l = "Caw (all windows)" end
        return l
    end
    local i
    for i = 1, table.getn(D.PRESETS) do
        if D.PRESETS[i].key == entry.key then return D.PRESETS[i].label end
    end
    return entry.key or "?"
end

local function sameEntry(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or a.key ~= b.key then return false end
    if a.key == "custom" then return a.name == b.name end
    if a.key == "caw" then
        -- "all windows" is its own entry: Caw 1 can sit on one tab, the rest on another
        return (tonumber(a.view) or 1) == (tonumber(b.view) or 1) and (a.multi and true or false) == (b.multi and true or false)
    end
    return true
end
D.sameEntry = sameEntry

-- Meters that can be added: { entry =, label = }
function D.meterChoices()
    local out = {}
    table.insert(out, { entry = { key = "twthreat" }, label = "TWThreat" })
    table.insert(out, { entry = { key = "caw" }, label = D.entryLabel({ key = "caw" }) })
    local i
    for i = 2, D.cawMax() do
        if D.cawView(i) then
            table.insert(out, { entry = { key = "caw", view = i }, label = D.entryLabel({ key = "caw", view = i }) })
        end
    end
    table.insert(out, { entry = { key = "caw", multi = true }, label = "Caw (all windows)" })
    return out
end

-- Which tab holds an entry (nil = none)
function D.entryTab(entry)
    local ti
    for ti = 1, D.numTabs() do
        local t = tabCfg(ti)
        local j
        for j = 1, M.count(t.frames) do
            if sameEntry(t.frames[j], entry) then return ti, j end
        end
    end
    return nil
end

------------------------------------------------------------------------
-- Host
------------------------------------------------------------------------
local function windowInfo(i)
    if not GetChatWindowInfo then return nil end
    local name, _, _, _, _, _, shown, _, docked = GetChatWindowInfo(i)
    return name, shown, docked
end

local function stripHost(cf)
    if not cf then return end
    local list = cf.messageTypeList
    if type(list) == "table" and table.getn(list) > 0 then
        if ChatFrame_RemoveAllMessageGroups then
            pcall(function() ChatFrame_RemoveAllMessageGroups(cf) end)
        elseif ChatFrame_RemoveMessageGroup then
            local i
            for i = table.getn(list), 1, -1 do
                local g = list[i]
                pcall(function() ChatFrame_RemoveMessageGroup(cf, g) end)
            end
        end
    end
    local ch = cf.channelList
    if type(ch) == "table" and table.getn(ch) > 0 then
        if ChatFrame_RemoveAllChannels then
            pcall(function() ChatFrame_RemoveAllChannels(cf) end)
        elseif ChatFrame_RemoveChannel then
            local i
            for i = table.getn(ch), 1, -1 do
                local g = ch[i]
                pcall(function() ChatFrame_RemoveChannel(cf, g) end)
            end
        end
    end
end

local function setupHost(cf, i, t)
    if not cf then return end
    if FCF_SetWindowName then pcall(function() FCF_SetWindowName(cf, t.name) end) end
    stripHost(cf)
    if cf.Clear then cf:Clear() end
    cf:Show()
    local tab = getglobal("ChatFrame" .. i .. "Tab")
    if tab then tab:Show() end
    if SetChatWindowShown then pcall(function() SetChatWindowShown(i, 1) end) end
    if not cf.isDocked and FCF_DockFrame then pcall(function() FCF_DockFrame(cf) end) end
    t.hostId = i
end

-- chat window ids held by other tabs' hosts
local function claimedBy(i, ti)
    local j, r
    for j, r in pairs(D.tabs) do
        if j ~= ti and r.hostId == i and r.host and not r.host._icFake then return true end
    end
    return false
end

function D.findHost(ti)
    local t = tabCfg(ti)
    if not t then return nil end
    local want = t.name
    local n = M.numWindows()
    local id = tonumber(t.hostId) or 0
    if id >= 4 and id <= n and not claimedBy(id, ti) then
        local name, shown, docked = windowInfo(id)
        local f = M.frame(id)
        if f and name == want and (shown or docked or f.isDocked) then return f, id end
    end
    local i
    for i = 4, n do
        local name, shown, docked = windowInfo(i)
        local f = M.frame(i)
        if f and name == want and (shown or docked) and not claimedBy(i, ti) then
            t.hostId = i
            return f, i
        end
    end
    return nil
end

local function buildFake(ti)
    local r = rt(ti)
    if r.fake then return r.fake end
    local cf1 = getglobal("ChatFrame1")
    local h = CreateFrame("Frame", ti == 1 and "IchaUIMetersHost" or ("IchaUIMetersHost" .. ti), UIParent)
    h:SetAllPoints(cf1)
    h:SetFrameStrata(cf1:GetFrameStrata() or "LOW")
    h:SetFrameLevel((cf1:GetFrameLevel() or 1) + 10)
    h:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    local skin = IchaUIChatSkin_Get and IchaUIChatSkin_Get()
    local a = (skin and skin.alpha) or 0.75
    h:SetBackdropColor(0.05, 0.05, 0.06, a)
    if IchaUI_PaintGoldBorder then IchaUI_PaintGoldBorder(h, 1) end
    if IchaUI_PaintFill then IchaUI_PaintFill(h, a) end
    h:EnableMouse(true)
    h:Hide()
    local tab = CreateFrame("Button", ti == 1 and "IchaUIMetersTab" or ("IchaUIMetersTab" .. ti), UIParent)
    tab:SetWidth(64)
    tab:SetHeight(22)
    tab:SetPoint("BOTTOMRIGHT", cf1._waChrome or cf1, "TOPRIGHT", -(ti - 1) * 66, 2)
    tab:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    tab:SetBackdropColor(0.05, 0.05, 0.06, 0.85)
    if IchaUI_PaintGoldBorder then IchaUI_PaintGoldBorder(tab, 1) end
    local fs = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER", tab, "CENTER", 0, 1)
    fs:SetText(D.tabName(ti))
    fs:SetTextColor(1, 0.92, 0.7)
    tab:SetScript("OnClick", function()
        local show = not h:IsShown()
        D.hideFakes()
        if show then h:Show() end
    end)
    h.tab = tab
    h.tabText = fs
    h._icFake = true
    r.fake = h
    return h
end

function D.hideFakes()
    local _, r
    for _, r in pairs(D.tabs) do
        if r.fake then r.fake:Hide() end
    end
end

-- Finds or makes a tab's host.
function D.ensureHost(ti, create)
    local t = tabCfg(ti)
    if not t then return nil end
    local r = rt(ti)
    local h = r.host
    if h and (h._icFake or h.isDocked or h:IsShown()) then return h end
    local cf, id = D.findHost(ti)
    if not cf and create then
        local n = M.numWindows()
        local i
        for i = 4, n do
            local f = M.frame(i)
            local name, shown, docked = windowInfo(i)
            if f and not shown and not docked and not f.isDocked and not claimedBy(i, ti) then
                setupHost(f, i, t)
                cf, id = f, i
                break
            end
        end
        if not cf then cf = buildFake(ti) end
    elseif cf then
        stripHost(cf)
    end
    r.host = cf
    r.hostId = id
    if cf and not cf._icFake then cf._icSkip = true end
    if cf and cf._icFake and cf.tabText then cf.tabText:SetText(t.name); cf.tab:Show() end
    if M.Pipeline and M.Pipeline.refreshSkip then M.Pipeline.refreshSkip() end
    return cf
end

------------------------------------------------------------------------
-- Snapshot / restore
------------------------------------------------------------------------
function D.snapshot(f)
    local p = f:GetParent()
    local s = {
        parent = (p and p.GetName and p:GetName()) or "UIParent",
        points = {},
        w = f:GetWidth(), h = f:GetHeight(),
        scale = f:GetScale(),
        shown = f:IsShown() and true or false,
    }
    local absolute = false
    local i
    for i = 1, 5 do
        local a, rel, b, x, y
        pcall(function() a, rel, b, x, y = f:GetPoint(i) end)
        if not a then break end
        local rn = rel and rel.GetName and rel:GetName()
        if rel and not rn then absolute = true end
        table.insert(s.points, { a, rn or "UIParent", b or a, x or 0, y or 0 })
    end
    if absolute and f:GetLeft() then
        s.points = { { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", f:GetLeft(), f:GetBottom() } }
    end
    if table.getn(s.points) == 0 then
        s.points = { { "CENTER", "UIParent", "CENTER", 0, 0 } }
    end
    return s
end

function D.restore(f, s)
    if not s then return end
    f:SetParent(getglobal(s.parent or "UIParent") or UIParent)
    if s.scale and s.scale > 0 then f:SetScale(s.scale) end
    f:ClearAllPoints()
    local i
    for i = 1, table.getn(s.points or {}) do
        local p = s.points[i]
        f:SetPoint(p[1], getglobal(p[2] or "UIParent") or UIParent, p[3], p[4], p[5])
    end
    if s.w and s.h and s.w > 0 and s.h > 0 then
        f:SetWidth(s.w)
        f:SetHeight(s.h)
    end
    if s.shown then f:Show() else f:Hide() end
end

------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------
local function noop() end

-- The client's laid-out size. GetWidth/GetHeight return a frame's own stored
-- size, which is stale for frames sized by two anchors (chat chrome, docked
-- chat frames), so measure the edges and fall back to it only if unplaced.
local function drawnSize(f)
    if not f then return nil end
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if l and r and t and b and r > l and t > b then return r - l, t - b end
    return f:GetWidth(), f:GetHeight()
end
D.drawnSize = drawnSize

function D.innerRect(ti)
    local h = D.tabs[ti or 1] and D.tabs[ti or 1].host
    if not h then return nil, 0 end
    local c = cfg()
    local extra = tonumber(c.inset) or 0
    local skin = IchaUIChatSkin_Get and IchaUIChatSkin_Get()
    if h._waChrome and skin and skin.enabled then return h._waChrome, BORDER_INSET + extra end
    if h._icFake then return h, BORDER_INSET + extra end
    return h, extra
end

------------------------------------------------------------------------
-- TWThreat lays its bars out from TWT.windowWidth (set from its column
-- options) and TWT_CONFIG.barHeight * visibleBars. Docked, TWTMain is
-- anchored at two corners and those values follow the drawn dock rect; the
-- snapshot keeps the user's visibleBars and undock rebuilds TWThreat's own
-- size from its config.
------------------------------------------------------------------------
local function twtApi()
    if type(TWT) ~= "table" or type(TWT_CONFIG) ~= "table" then return nil end
    return TWT, TWT_CONFIG
end

-- visibleBars comes from the snapshot height (TWThreat's own
-- barHeight * bars + label rows), which predates any docked resize.
function D.twtSnapshot(s)
    local T, C = twtApi()
    if not T or s.twt then return end
    local vb = tonumber(C.visibleBars)
    local bh = tonumber(C.barHeight) or 0
    if tonumber(s.h) and bh > 0 then
        vb = math.floor((s.h - (C.labelRow and 40 or 20)) / bh + 0.5)
        if vb < 1 then vb = 1 end
    end
    s.twt = { visibleBars = vb }
end

local function unpin(f)
    if f.SetMinResize then f:SetMinResize(1, 1) end
    if f.SetMaxResize then f:SetMaxResize(4096, 4096) end
end

local function effScale(f)
    local s = f and f.GetEffectiveScale and f:GetEffectiveScale()
    if not s or s <= 0 then s = 1 end
    return s
end

-- "size": TWThreat's width / bar count follow the dock at its own scale.
-- "scale": keep TWThreat's own column width and scale it up to the dock
-- width (bigger text); bar count still fills the height.
function D.twtMode()
    if cfg().twtFit == "scale" then return "scale" end
    return "size"
end

local function twtBars(C, h)
    local labels = C.labelRow and 40 or 20
    local bh = tonumber(C.barHeight) or 20
    if bh < 1 then bh = 20 end
    local vb = math.floor((h - labels) / bh)
    if vb < 1 then vb = 1 end
    return vb
end

-- Centre line of rel: two columns hang off the same edge, so they stretch
-- with the border without any width math.
local function splitGuide(rel)
    local g = rel._icSplit
    if not g then
        g = CreateFrame("Frame", nil, rel)
        g:SetWidth(1)
        rel._icSplit = g
    end
    if g:GetParent() ~= rel then g:SetParent(rel) end
    g:ClearAllPoints()
    g:SetPoint("TOP", rel, "TOP", 0, 0)
    g:SetPoint("BOTTOM", rel, "BOTTOM", 0, 0)
    return g
end

-- Column i of cols inside rel, by two corners (rel units: ins inset, gap
-- between columns; x0 / colW only for 3+ columns). Returns rel -> frame units.
local function anchorIn(f, rel, ins, gap, i, cols, x0, colW)
    local k = effScale(rel) / effScale(f)
    f:ClearAllPoints()
    if cols == 2 then
        local g = splitGuide(rel)
        if i == 1 then
            f:SetPoint("TOPLEFT", rel, "TOPLEFT", ins * k, -ins * k)
            f:SetPoint("BOTTOMRIGHT", g, "BOTTOM", -gap / 2 * k, ins * k)
        else
            f:SetPoint("TOPLEFT", g, "TOP", gap / 2 * k, -ins * k)
            f:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", -ins * k, ins * k)
        end
    elseif cols > 2 then
        f:SetPoint("TOPLEFT", rel, "TOPLEFT", x0 * k, -ins * k)
        f:SetPoint("BOTTOMRIGHT", rel, "BOTTOMLEFT", (x0 + colW) * k, ins * k)
    else
        f:SetPoint("TOPLEFT", rel, "TOPLEFT", ins * k, -ins * k)
        f:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", -ins * k, ins * k)
    end
    return k
end

-- Caw treats any OnHide it didn't cause as the user closing the window, and
-- a child's OnHide also fires when its parent hides. Docked, the host hides
-- on every tab switch / dock re-layout, so keep Caw's flag unless the frame
-- itself was hidden (its close button).
local function guardParentHide(rec)
    local f = rec.frame
    if f:GetScript("OnHide") == rec.hideGuard and rec.hideGuard then return end
    local inner = f:GetScript("OnHide")
    rec.onHide = inner
    rec.hideGuard = function()
        local was = this.cawManuallyHidden
        if inner then inner() end
        if this:IsShown() then this.cawManuallyHidden = was end
    end
    f:SetScript("OnHide", rec.hideGuard)
end

local function hostFill(ti, on)
    local h = D.tabs[ti] and D.tabs[ti].host
    if not h then return end
    if h._icFake then
        local skin = IchaUIChatSkin_Get and IchaUIChatSkin_Get()
        if IchaUI_PaintFill then IchaUI_PaintFill(h, on and ((skin and skin.alpha) or 0.75) or 0) end
    elseif IchaUIChatSkin_SetNoFill then
        IchaUIChatSkin_SetNoFill(h, not on)
    end
end

-- TWTMain stretches with its anchors; TWThreat's bar width (windowWidth)
-- and bar count are set from the drawn column size.
function D.twtPlace(rec, rel, ins, gap, i, cols, x0, colW, H)
    local f = rec.frame
    local T, C = twtApi()
    local s = cfg().snapshots[rec.key]
    local baseScale = (s and tonumber(s.scale) and s.scale > 0) and s.scale or 1
    local mode = D.twtMode()
    D._twtBusy = true
    local w, h, k
    if mode == "scale" and T then
        unpin(f)
        if type(T.setColumnLabels) == "function" then pcall(T.setColumnLabels) end
        local w0 = tonumber(T.windowWidth) or 300
        if w0 < 1 then w0 = 300 end
        f:SetScale(effScale(rel) * colW / w0 / effScale(f:GetParent()))
        k = anchorIn(f, rel, ins, gap, i, cols, x0, colW)
        w, h = colW * k, H * k
        T.windowWidth = w
    else
        if f:GetScale() ~= baseScale then f:SetScale(baseScale) end
        k = anchorIn(f, rel, ins, gap, i, cols, x0, colW)
        w, h = colW * k, H * k
        if T then T.windowWidth = w end
    end
    if T then
        C.visibleBars = twtBars(C, h)
        if type(FrameHeightSlider_OnValueChanged) == "function" then pcall(FrameHeightSlider_OnValueChanged) end
        -- TWThreat pins min = max resize to its own size; the anchors size it now
        unpin(f)
        if type(T.updateUI) == "function" then pcall(T.updateUI, "IchaUI_Chat") end
    end
    D._twtBusy = false
    rec.twtW, rec.twtH, rec.twtMode = w, h, mode
    D.twtCheckSoon()
end

-- Something re-anchored TWTMain (its login / scale slider code): the drawn
-- size no longer matches, lay out again.
function D.twtVerify()
    local rec = D.docked.twthreat
    if not rec or not rec.twtW then return true end
    local f = rec.frame
    if not f:IsVisible() then return true end
    local rw, rh = drawnSize(f)
    if not rw then return true end
    if math.abs(rw - rec.twtW) <= 1.5 and math.abs(rh - rec.twtH) <= 1.5 then
        rec.twtMiss = 0
        return true
    end
    rec.twtMiss = (rec.twtMiss or 0) + 1
    return false
end

-- Re-assert at most a few times in a row; hooks and host resizes lay out again.
function D.twtRetry()
    local rec = D.docked.twthreat
    return rec and (rec.twtMiss or 0) <= 3
end

local chk = CreateFrame("Frame")
chk:Hide()
chk:SetScript("OnUpdate", function()
    this:Hide()
    if not D.twtVerify() and D.twtRetry() then D.layout() end
end)
function D.twtCheckSoon()
    chk:Show()
end

local lq = CreateFrame("Frame")
lq:Hide()
lq:SetScript("OnUpdate", function()
    this:Hide()
    D.layout()
end)

-- The dock rect is sized by anchors; re-fit when the client resizes it.
local function watchRect(rel)
    if not rel or rel._icDockWatch then return end
    rel._icDockWatch = true
    local prev = rel:GetScript("OnSizeChanged")
    rel:SetScript("OnSizeChanged", function()
        if prev then prev() end
        if next(D.docked) then lq:Show() end
    end)
end

function D.twtRestore(f, s)
    local T, C = twtApi()
    if not T then return end
    D._twtBusy = true
    unpin(f)
    if s and s.twt and tonumber(s.twt.visibleBars) then C.visibleBars = tonumber(s.twt.visibleBars) end
    if type(T.setColumnLabels) == "function" then pcall(T.setColumnLabels) end
    if type(FrameHeightSlider_OnValueChanged) == "function" then pcall(FrameHeightSlider_OnValueChanged) end
    D._twtBusy = false
end

-- TWThreat re-sizes itself from its settings (bar height slider, column and
-- label toggles, scale slider); lay the dock out again right after.
local function hookTWT()
    if D._twtHook then return end
    D._twtHook = true
    local names = { "FrameHeightSlider_OnValueChanged", "TWTMainMainWindow_Resized", "WindowScaleSlider_OnValueChanged" }
    local i
    for i = 1, table.getn(names) do
        local old = getglobal(names[i])
        if type(old) == "function" then
            setglobal(names[i], function(a1, a2)
                local r = old(a1, a2)
                if not D._twtBusy and D.docked.twthreat then D.layout() end
                return r
            end)
        end
    end
    local T = twtApi()
    if T and type(T.setColumnLabels) == "function" then
        local oldCols = T.setColumnLabels
        T.setColumnLabels = function(a1, a2)
            local r = oldCols(a1, a2)
            if not D._twtBusy and D.docked.twthreat then D.layout() end
            return r
        end
    end
end

-- Caw re-lays out on its own update once the stored size changes; do it now
-- so the dock never shows a frame laid out for the old size.
function D.relayoutMeter(f)
    local C = CAW_DPS_METER
    if type(C) ~= "table" then return end
    if f == C.window then
        if type(C.applyCompactWindowLayout) == "function" then pcall(C.applyCompactWindowLayout) end
        return
    end
    if type(C.multiWindows) ~= "table" or type(C.layoutMultiWindow) ~= "function" then return end
    local i
    for i = 1, (tonumber(C.multiWindowMax) or 0) do
        local v = C.multiWindows[i]
        if type(v) == "table" and v.frame == f then
            pcall(C.layoutMultiWindow, v)
            return
        end
    end
end

function D.layout()
    local ti
    for ti = 1, D.numTabs() do D.layoutTab(ti) end
end

function D.layoutTab(ti)
    local rel, ins = D.innerRect(ti)
    if not rel then return end
    local r = rt(ti)
    local list = {}
    local i
    for i = 1, table.getn(r.order) do
        local rec = D.docked[r.order[i]]
        if rec then table.insert(list, rec) end
    end
    local n = table.getn(list)
    if n == 0 then return end
    watchRect(rel)
    local t = tabCfg(ti)
    local mode = (t and t.layout) or "auto"
    if mode == "auto" then
        if n >= 2 then mode = "split" else mode = "fill" end
    end
    local RW, RH = drawnSize(rel)
    local W = (RW or 0) - 2 * ins
    local H = (RH or 0) - 2 * ins
    if W < 20 or H < 20 then return end
    r.lastW, r.lastH = RW, RH
    local cols = 1
    if mode == "split" and n > 1 then cols = n end
    local gap = 2
    local colW = (W - (cols - 1) * gap) / cols
    hostFill(ti, false)
    for i = 1, n do
        local rec = list[i]
        local f = rec.frame
        local col = cols > 1 and i or 1
        local x0 = ins + (col - 1) * (colW + gap)
        if rec.twt then
            D.twtPlace(rec, rel, ins, gap, col, cols, x0, colW, H)
        else
            local k = anchorIn(f, rel, ins, gap, col, cols, x0, colW)
            -- The anchors size the frame, but meters (Caw) lay out their rows,
            -- header and footer from GetWidth/GetHeight, the stored size.
            f:SetWidth(colW * k)
            f:SetHeight(H * k)
            guardParentHide(rec)
            D.relayoutMeter(f)
        end
        rec.rel = rel
    end
end

------------------------------------------------------------------------
-- Dock / undock one frame
------------------------------------------------------------------------
function D.dockFrame(item, ti)
    local f, key = item.frame, item.key
    if D.docked[key] then return true end
    local r = rt(ti)
    local host = r.host
    if not host or f == host then return false end
    local p = host
    while p do
        if p == f then return false end
        p = p.GetParent and p:GetParent()
    end
    if D.isHost(f) then return false end
    if f.HiddenSetPoint then
        if not D._refused then D._refused = {} end
        if not D._refused[key] then
            D._refused[key] = true
            M.Print((f:GetName() or key) .. " is held by MoveAnything; reset it there to dock it.")
        end
        return false
    end
    local c = cfg()
    if not c.snapshots[key] then c.snapshots[key] = D.snapshot(f) end
    if item.twt then D.twtSnapshot(c.snapshots[key]) end
    local rec = {
        frame = f, key = key, twt = item.twt, tab = ti,
        dragStart = f:GetScript("OnDragStart"),
        dragStop = f:GetScript("OnDragStop"),
        sm = rawget(f, "StartMoving"),
        ss = rawget(f, "StartSizing"),
    }
    f:SetScript("OnDragStart", nil)
    f:SetScript("OnDragStop", nil)
    f.StartMoving = noop
    f.StartSizing = noop
    f:SetParent(host)
    if c.snapshots[key].shown then
        -- a host hide before the guard existed left Caw "closed" (and saved)
        f.cawManuallyHidden = nil
        f:Show()
    end
    D.docked[key] = rec
    table.insert(r.order, key)
    return true
end

function D.undockKey(key)
    local rec = D.docked[key]
    local c = cfg()
    local ti = rec and rec.tab
    if rec then
        local f = rec.frame
        f.StartMoving = rec.sm
        f.StartSizing = rec.ss
        f:SetScript("OnDragStart", rec.dragStart)
        f:SetScript("OnDragStop", rec.dragStop)
        if rec.hideGuard and f:GetScript("OnHide") == rec.hideGuard then f:SetScript("OnHide", rec.onHide) end
        D.docked[key] = nil
        if rec.twt then D.twtRestore(f, c.snapshots[key]) end
        D.restore(f, c.snapshots[key])
        if cawClosedFrame(f) then f:Hide() end
    end
    c.snapshots[key] = nil
    local j, r
    for j, r in pairs(D.tabs) do
        local i
        for i = table.getn(r.order), 1, -1 do
            if r.order[i] == key then table.remove(r.order, i) end
        end
        if j == ti and table.getn(r.order) == 0 then hostFill(j, true) end
    end
end

function D.undockTab(ti)
    local r = D.tabs[ti]
    if not r then return end
    local keys = {}
    local i
    for i = 1, table.getn(r.order) do table.insert(keys, r.order[i]) end
    for i = 1, table.getn(keys) do D.undockKey(keys[i]) end
end

function D.undockAll()
    local keys = {}
    local key
    for key in pairs(D.docked) do table.insert(keys, key) end
    local i
    for i = 1, table.getn(keys) do D.undockKey(keys[i]) end
end

-- key -> { item, tab }. A meter is on one tab: explicit entries claim first
-- (tab order), then "all Caw windows" fills in the views nobody claimed.
local function wantedKeys()
    local want = {}
    local c = cfg()
    if not c.on then return want end
    local pass, ti
    for pass = 1, 2 do
        for ti = 1, D.numTabs() do
            local t = tabCfg(ti)
            local i
            for i = 1, M.count(t.frames) do
                local items = D.resolve(t.frames[i])
                local j
                for j = 1, table.getn(items) do
                    local it = items[j]
                    local early = not it.many
                    if ((pass == 1) == early) and not want[it.key] then want[it.key] = { item = it, tab = ti } end
                end
            end
        end
    end
    return want
end
D.wantedKeys = wantedKeys

function D.purgeRemoved()
    local c = cfg()
    local ti
    for ti = 1, D.numTabs() do
        local t = tabCfg(ti)
        local i = M.count(t.frames)
        while i >= 1 do
            local e = t.frames[i]
            if type(e) == "table" and REMOVED[e.key] then t.frames = M.without(t.frames, i) end
            i = i - 1
        end
    end
    local key, fname
    for key, fname in pairs(REMOVED) do
        if D.docked[key] then
            D.undockKey(key)
        elseif c.snapshots[key] then
            local f = getglobal(fname)
            if isFrame(f) and not f.HiddenSetPoint then D.restore(f, c.snapshots[key]) end
            c.snapshots[key] = nil
        end
    end
end

-- Dock what is configured and resolvable, undock what is no longer wanted
-- (or moved to another tab), and re-anchor anything an addon moved back out.
function D.sync(create)
    D.purgeRemoved()
    local want = wantedKeys()
    local key, rec, w
    local drop = {}
    for key, rec in pairs(D.docked) do
        w = want[key]
        if not w or w.item.frame ~= rec.frame or w.tab ~= rec.tab then table.insert(drop, key) end
    end
    local i
    for i = 1, table.getn(drop) do D.undockKey(drop[i]) end
    local changed = {}
    local ti
    for ti = 1, D.numTabs() do
        local has = false
        for key, w in pairs(want) do
            if w.tab == ti then has = true end
        end
        if has or create then D.ensureHost(ti, create) end
    end
    for key, w in pairs(want) do
        local r = rt(w.tab)
        if not D.docked[key] and r.host then
            if D.dockFrame(w.item, w.tab) then changed[w.tab] = true end
        end
    end
    for key, rec in pairs(D.docked) do
        local f = rec.frame
        local h = rt(rec.tab).host
        local _, rel = f:GetPoint(1)
        if f:GetParent() ~= h then
            f:SetParent(h)
            changed[rec.tab] = true
        elseif rel ~= rec.rel then
            changed[rec.tab] = true
        end
        if rec.hideGuard and f:GetScript("OnHide") ~= rec.hideGuard then guardParentHide(rec) end
    end
    for ti = 1, D.numTabs() do
        local r = rt(ti)
        local rel = D.innerRect(ti)
        if rel and table.getn(r.order) > 0 then
            local rw, rh = drawnSize(rel)
            if rw ~= r.lastW or rh ~= r.lastH then changed[ti] = true end
        end
    end
    local tw = D.docked.twthreat
    if tw and not D.twtVerify() and D.twtRetry() then changed[tw.tab] = true end
    if table.getn(drop) > 0 then
        D.layout()
    else
        for ti = 1, D.numTabs() do
            if changed[ti] then D.layoutTab(ti) end
        end
    end
end

-- Host closed from Blizzard's tab menu: give the meters back.
local function hostLost(ti)
    local r = D.tabs[ti]
    local h = r and r.host
    if not h or h._icFake then return false end
    if h.isDocked or h:IsShown() then return false end
    local name, shown, docked = windowInfo(r.hostId or 0)
    if shown or docked then return false end
    return true
end

local function dropHost(ti)
    local r = rt(ti)
    D.undockTab(ti)
    local h = r.host
    if h and not h._icFake and FCF_Close then
        pcall(function() FCF_Close(h) end)
    elseif h and h._icFake then
        h:Hide()
        if h.tab then h.tab:Hide() end
    end
    r.host = nil
    r.hostId = nil
    local t = tabCfg(ti)
    if t then t.hostId = 0 end
end

------------------------------------------------------------------------
-- Config API (tabs)
------------------------------------------------------------------------
local function nameTaken(name, skip)
    local ti
    for ti = 1, D.numTabs() do
        if ti ~= skip and D.tabName(ti) == name then return true end
    end
    return false
end

local function uniqueName(name, skip)
    if not nameTaken(name, skip) then return name end
    local n = 2
    while nameTaken(name .. " " .. n, skip) do n = n + 1 end
    return name .. " " .. n
end

-- Returns the new tab's index.
function D.addTab(name)
    local c = cfg()
    if type(name) ~= "string" or name == "" then name = "Meters" end
    M.append(c.tabs, { name = uniqueName(name), hostId = 0, layout = "auto", frames = {} })
    local ti = D.numTabs()
    D.tabs[ti] = { order = {} }
    c.on = true
    D.ensureHost(ti, true)
    D.sync(false)
    return ti
end

function D.removeTab(ti)
    local c = cfg()
    if not tabCfg(ti) then return end
    dropHost(ti)
    c.tabs = M.without(c.tabs, ti)
    local n = D.numTabs()
    local j
    for j = ti, n do D.tabs[j] = D.tabs[j + 1] end
    D.tabs[n + 1] = nil
    local _, rec
    for _, rec in pairs(D.docked) do
        if rec.tab > ti then rec.tab = rec.tab - 1 end
    end
    for j = 1, n do
        local r = D.tabs[j]
        if r and r.fake and r.fake.tab then
            local cf1 = getglobal("ChatFrame1")
            r.fake.tab:ClearAllPoints()
            r.fake.tab:SetPoint("BOTTOMRIGHT", cf1._waChrome or cf1, "TOPRIGHT", -(j - 1) * 66, 2)
        end
    end
    if M.Pipeline and M.Pipeline.refreshSkip then M.Pipeline.refreshSkip() end
    D.sync(false)
end

function D.renameTab(ti, name)
    local t = tabCfg(ti)
    if not t or type(name) ~= "string" then return end
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    if name == "" then return end
    t.name = uniqueName(name, ti)
    local h = rt(ti).host
    if h and h._icFake then
        if h.tabText then h.tabText:SetText(t.name) end
    elseif h and FCF_SetWindowName then
        pcall(function() FCF_SetWindowName(h, t.name) end)
    end
end

function D.setTabLayout(ti, mode)
    local t = tabCfg(ti)
    if not t then return end
    t.layout = mode
    D.layoutTab(ti)
end

function D.tabLayout(ti)
    local t = tabCfg(ti)
    return (t and t.layout) or "auto"
end

function D.tabFrames(ti)
    local t = tabCfg(ti)
    return t and t.frames or {}
end

function D.tabHost(ti)
    local r = D.tabs[ti]
    return r and r.host, r and r.hostId
end

-- Puts a meter on tab ti, taking it off any other tab.
function D.addEntry(ti, entry)
    local t = tabCfg(ti)
    if not t then return end
    local j
    for j = D.numTabs(), 1, -1 do
        local o = tabCfg(j)
        local i = M.count(o.frames)
        while i >= 1 do
            local e = o.frames[i]
            if sameEntry(e, entry) and j ~= ti then o.frames = M.without(o.frames, i) end
            i = i - 1
        end
    end
    local found = false
    for j = 1, M.count(t.frames) do
        if sameEntry(t.frames[j], entry) then found = true end
    end
    if not found then
        M.append(t.frames, { key = entry.key, name = entry.name, view = entry.view, multi = entry.multi })
    end
    cfg().on = true
    D.sync(true)
end

function D.removeEntry(ti, idx)
    local t = tabCfg(ti)
    if not t or not t.frames[idx] then return end
    t.frames = M.without(t.frames, idx)
    D.sync(false)
end

function D.entryStatus(entry, ti)
    local items = D.resolve(entry)
    if table.getn(items) == 0 then return "not found" end
    local want = wantedKeys()
    local n, total, refused, i = 0, 0, false
    for i = 1, table.getn(items) do
        local key = items[i].key
        local w = want[key]
        if not w or w.tab == ti then
            total = total + 1
            local rec = D.docked[key]
            if rec and rec.tab == ti then n = n + 1 end
            if items[i].frame.HiddenSetPoint then refused = true end
        end
    end
    if total == 0 then return "on another tab" end
    if n == total then return "docked" end
    if refused then return "MoveAnything holds it" end
    if n > 0 then return "partly docked" end
    return "waiting"
end

------------------------------------------------------------------------
-- Leave a meter tab for chat (dock.backToGeneral). Only from a meter tab,
-- one docked chat tab per event, only through FCF_SelectDockFrame.
------------------------------------------------------------------------
local function showsGroup(cf, group)
    local list = cf and cf.messageTypeList
    if not group or type(list) ~= "table" then return false end
    local i
    for i = 1, table.getn(list) do
        if list[i] == group then return true end
    end
    return false
end
D.showsGroup = showsGroup

local function groupCount(cf)
    if not cf then return 0 end
    local n = 0
    if type(cf.messageTypeList) == "table" then n = n + table.getn(cf.messageTypeList) end
    if type(cf.channelList) == "table" then n = n + table.getn(cf.channelList) end
    return n
end

local function dockedChat(cf)
    return cf and cf.isDocked and not cf._icFake and not D.isHost(cf)
end

-- The docked chat tab for a message group: `prefer` if it shows the group,
-- else the most dedicated one (fewest groups + channels, lowest id on a tie).
-- Nil when the tab on screen already shows it, or no docked tab does.
function D.chatTabFor(group, prefer)
    local shown = M.shownFrame()
    if dockedChat(shown) and showsGroup(shown, group) then return nil end
    if dockedChat(prefer) and showsGroup(prefer, group) then return prefer end
    local dock = DOCKED_CHAT_FRAMES
    if type(dock) ~= "table" then return nil end
    local best, bestN, i
    for i = 1, table.getn(dock) do
        local cf = dock[i]
        if dockedChat(cf) and showsGroup(cf, group) then
            local n = groupCount(cf)
            if not best or n < bestN or (n == bestN and cf:GetID() < best:GetID()) then best, bestN = cf, n end
        end
    end
    return best
end

function D.leaveMeterTab(group, prefer)
    if not cfg().backToGeneral then return end
    D.hideFakes()
    if not D.isHost(M.shownFrame()) or not FCF_SelectDockFrame then return end
    local cf = D.chatTabFor(group, prefer)
    if not cf then cf = prefer end
    if not dockedChat(cf) then cf = getglobal("ChatFrame1") end
    if dockedChat(cf) and cf ~= SELECTED_DOCK_FRAME then FCF_SelectDockFrame(cf) end
end

function D.backToGeneral()
    D.leaveMeterTab(nil, M.EditBox and M.EditBox.chatFrame and M.EditBox.chatFrame())
end

-- Typing from a meter tab: back to the last chat tab, or the tab that shows
-- the edit box's chat type (a reply goes to the whisper tab).
function D.beforeOpenChat()
    local b = ChatFrameEditBox
    local ct = b and b.chatType
    if ct == "CHANNEL" then ct = nil end
    D.leaveMeterTab(ct, M.EditBox and M.EditBox.chatFrame and M.EditBox.chatFrame())
end

-- Whispers that land in the same frame make one decision on the next one.
local ev = CreateFrame("Frame")
ev:Hide()
ev:RegisterEvent("CHAT_MSG_WHISPER")
ev:SetScript("OnEvent", function()
    this.group = this.group or "WHISPER"
    this:Show()
end)
ev:SetScript("OnUpdate", function()
    this:Hide()
    local g = this.group
    this.group = nil
    D.leaveMeterTab(g, nil)
end)

------------------------------------------------------------------------
-- Dock repair: at most one shown docked frame (the selected tab). The
-- rest stay hidden and on ChatFrame1. Nil holes in DOCKED_CHAT_FRAMES
-- are dropped so stock FCF_SelectDockFrame / FCF_Tab_OnClick can Hide()
-- without erroring (which left every tab visible and clickable).
------------------------------------------------------------------------
local function dockCount(dock)
    if type(dock) ~= "table" then return 0 end
    local n = table.getn(dock)
    if type(dock.n) == "number" and dock.n > n then n = dock.n end
    return n
end

local function compactDock(dock)
    local n = dockCount(dock)
    local i, removed = 1, 0
    while i <= n do
        if dock[i] then
            i = i + 1
        else
            table.remove(dock, i)
            removed = removed + 1
            n = dockCount(dock)
        end
    end
    return removed
end

local function inDock(dock, f)
    if not f or type(dock) ~= "table" then return false end
    local i
    for i = 1, dockCount(dock) do
        if dock[i] == f then return true end
    end
    return false
end

-- Visible tab: the selected dock (meter host included), never a hidden
-- SELECTED_CHAT_FRAME sitting behind a meter tab.
local function pickSelected(dock, cf1)
    local sel = SELECTED_DOCK_FRAME
    if inDock(dock, sel) then return sel end
    sel = SELECTED_CHAT_FRAME
    if inDock(dock, sel) then return sel end
    if dock[1] then return dock[1] end
    return DEFAULT_CHAT_FRAME or cf1
end

-- Hide extras only. Never Show() here; FCF_SelectDockFrame does that.
local function hideUnselected(sel)
    local n, i = 0
    local dock = DOCKED_CHAT_FRAMES
    if type(dock) == "table" then
        for i = 1, dockCount(dock) do
            local cf = dock[i]
            if cf and cf ~= sel and cf.IsShown and cf:IsShown() then
                cf:Hide()
                n = n + 1
            end
        end
    end
    for i = 1, M.numWindows() do
        local cf = M.frame(i)
        if cf and cf ~= sel and cf.isDocked and cf.IsShown and cf:IsShown() then
            cf:Hide()
            n = n + 1
        end
    end
    return n
end

local function offDock(cf, base)
    if not cf or not base or not cf.GetLeft or not base.GetLeft then return false end
    local l, t, bl, bt = cf:GetLeft(), cf:GetTop(), base:GetLeft(), base:GetTop()
    if not l or not t or not bl or not bt then return false end
    return math.abs(l - bl) > 2 or math.abs(t - bt) > 2
end

local function snapToBase(cf, base)
    if not cf or not base or cf == base then return end
    if cf.resizing or base.resizing then return end
    if not cf.ClearAllPoints or not cf.SetPoint then return end
    cf:ClearAllPoints()
    cf:SetPoint("TOPLEFT", base, "TOPLEFT", 0, 0)
    cf:SetPoint("BOTTOMRIGHT", base, "BOTTOMRIGHT", 0, 0)
end

-- full: also re-dock saved-docked windows and put ChatFrame1 first (login).
function D.repairDock(full)
    local dock = DOCKED_CHAT_FRAMES
    if type(dock) ~= "table" then return 0 end
    local cf1 = getglobal("ChatFrame1")
    local fixed = compactDock(dock)
    if fixed > 0 and FCF_SaveDock then pcall(FCF_SaveDock) end
    dock = DOCKED_CHAT_FRAMES
    if type(dock) ~= "table" then return fixed end
    local i
    if full and FCF_DockFrame then
        for i = 1, M.numWindows() do
            local cf = M.frame(i)
            local _, _, docked = windowInfo(i)
            if cf and docked and cf ~= cf1 then
                if not inDock(dock, cf) then
                    cf.isDocked = nil
                    pcall(function() FCF_DockFrame(cf) end)
                    dock = DOCKED_CHAT_FRAMES
                    if type(dock) ~= "table" then return fixed + 1 end
                    compactDock(dock)
                    if cf ~= SELECTED_DOCK_FRAME and cf.Hide then cf:Hide() end
                    fixed = fixed + 1
                end
            end
        end
        if cf1 and dock[1] ~= cf1 then
            for i = dockCount(dock), 2, -1 do
                if dock[i] == cf1 then
                    table.remove(dock, i)
                    table.insert(dock, 1, cf1)
                    if FCF_SaveDock then pcall(FCF_SaveDock) end
                    dock = DOCKED_CHAT_FRAMES
                    fixed = fixed + 1
                end
            end
        end
    end
    local sel = pickSelected(dock, cf1)
    local hidden = hideUnselected(sel)
    if hidden > 0 then fixed = fixed + hidden end
    local base = DEFAULT_CHAT_FRAME or cf1
    if base then
        for i = 1, dockCount(dock) do
            local cf = dock[i]
            if cf and cf ~= base and not (base.resizing or cf.resizing) and offDock(cf, base) then
                snapToBase(cf, base)
                fixed = fixed + 1
            end
        end
    end
    if sel and sel.IsShown and not sel:IsShown() and FCF_SelectDockFrame then
        pcall(function() FCF_SelectDockFrame(sel) end)
        hideUnselected(sel)
        fixed = fixed + 1
    end
    return fixed
end

local function anyFrames()
    local ti
    for ti = 1, D.numTabs() do
        if M.count(tabCfg(ti).frames) > 0 then return true end
    end
    return false
end

local ticker = CreateFrame("Frame")
ticker.acc = 0
ticker:SetScript("OnUpdate", function()
    this.acc = this.acc + (arg1 or 0)
    if this.acc < 1 then return end
    this.acc = 0
    if not M.ready or not D._started then return end
    if not MOVING_CHATFRAME then D.repairDock(false) end
    local c = cfg()
    if not c.on or not anyFrames() then
        if next(D.docked) then D.undockAll() end
        return
    end
    local ti
    for ti = 1, D.numTabs() do
        if hostLost(ti) then
            D.undockTab(ti)
            local r = rt(ti)
            r.host = nil
            r.hostId = nil
            tabCfg(ti).hostId = 0
        end
    end
    D.sync(false)
end)

------------------------------------------------------------------------
function D:login()
    hookTWT()
    local c = cfg()
    if c.on then
        local ti
        for ti = 1, D.numTabs() do D.ensureHost(ti, false) end
    end
    if type(FCF_Tab_OnClick) == "function" and not D._tabHook then
        D._tabHook = true
        local old = FCF_Tab_OnClick
        FCF_Tab_OnClick = function(a1)
            local r = old(a1)
            D.hideFakes()
            if D.docked.twthreat then D.twtCheckSoon() end
            return r
        end
    end
end

function D:world()
    M.After(1, function()
        D._started = true
        D.purgeRemoved()
        local c = cfg()
        if c.on and anyFrames() then D.sync(true) end
    end)
    M.After(2.5, function()
        if D.repairDock(true) > 0 then M.Print("put overlapping or loose chat tabs back in the dock.") end
    end)
end

function D:apply()
    if D._started then D.sync(false) end
    D.layout()
end

------------------------------------------------------------------------
-- /ichachat dockdebug | dockfit size|scale
------------------------------------------------------------------------
local function fmt(v)
    if type(v) == "number" then return string.format("%.1f", v) end
    return tostring(v)
end

-- Screen pixels: edges x effective scale, plus the frame's stored size.
local function screenRect(label, f)
    if not f then return label .. " -" end
    local e = effScale(f)
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    local s = label .. " "
    if l and r and t and b then
        s = s .. "L" .. fmt(l * e) .. " R" .. fmt(r * e) .. " T" .. fmt(t * e) .. " B" .. fmt(b * e)
            .. " = " .. fmt((r - l) * e) .. "x" .. fmt((t - b) * e) .. "px"
    else
        s = s .. "not placed"
    end
    s = s .. " (stored " .. fmt(f:GetWidth()) .. "x" .. fmt(f:GetHeight()) .. ", eff " .. fmt(e) .. ")"
    if f.IsVisible and not f:IsVisible() then s = s .. " hidden" end
    return s
end

local function childList(f)
    local out = {}
    local list = { f:GetChildren() }
    local i
    for i = 1, table.getn(list) do
        local c = list[i]
        local w, h = drawnSize(c)
        table.insert(out, tostring(c:GetName() or "?") .. " " .. fmt(w) .. "x" .. fmt(h) .. (c:IsShown() and "" or " off"))
    end
    return table.concat(out, "; ")
end

function D.debug()
    local P = M.Print
    local c = cfg()
    P("dock on=" .. tostring(c.on) .. " tabs=" .. D.numTabs() .. " fit=" .. D.twtMode())
    local cf1 = getglobal("ChatFrame1")
    P(screenRect("ChatFrame1", cf1))
    P(screenRect("ChatFrame1 chrome", cf1 and cf1._waChrome))
    local ti
    for ti = 1, D.numTabs() do
        local h, id = D.tabHost(ti)
        local keys = table.concat(rt(ti).order, ", ")
        P("tab " .. ti .. " '" .. D.tabName(ti) .. "' layout=" .. D.tabLayout(ti) .. " host="
            .. tostring(h and (h._icFake and "fake" or ("ChatFrame" .. tostring(id)))) .. " meters: " .. (keys ~= "" and keys or "-"))
        local rel, ins = D.innerRect(ti)
        if rel then
            local W, H = drawnSize(rel)
            P(screenRect("  rect", rel))
            P("  inset " .. fmt(ins) .. " inner " .. fmt((W or 0) - 2 * ins) .. "x" .. fmt((H or 0) - 2 * ins) .. " (rect units)")
        end
    end
    local f = getglobal("TWTMain")
    if f then
        P(screenRect("TWTMain", f) .. " scale " .. fmt(f:GetScale()) .. " parent " .. tostring(f:GetParent() and f:GetParent():GetName()))
        local i
        for i = 1, 2 do
            local a, r, b, x, y
            pcall(function() a, r, b, x, y = f:GetPoint(i) end)
            if a then P("  point " .. a .. " " .. tostring(r and r:GetName()) .. " " .. tostring(b) .. " " .. fmt(x) .. "," .. fmt(y)) end
        end
        local T, C = twtApi()
        if T then
            P("  TWT windowWidth " .. fmt(T.windowWidth) .. " bars " .. fmt(C.visibleBars) .. " x " .. fmt(C.barHeight)
                .. " labelRow " .. tostring(C.labelRow) .. " windowScale " .. fmt(C.windowScale))
        end
        local rec = D.docked.twthreat
        if rec then
            P("  target " .. fmt(rec.twtW) .. "x" .. fmt(rec.twtH) .. " misses " .. fmt(rec.twtMiss or 0))
        else
            P("  TWThreat not docked")
        end
        P("  skin backdrop on TWTMain: " .. tostring(f._ichaSkinA ~= nil) .. "; children: " .. childList(f))
    else
        P("TWTMain not found")
    end
    local cw = (type(CAW_DPS_METER) == "table" and CAW_DPS_METER.window) or getglobal("CawDPSMeterWindow")
    if cw then P(screenRect("Caw", cw)) end
end

SLASH_ICHAUICHAT1 = "/ichachat"
SlashCmdList["ICHAUICHAT"] = function(msg)
    local _, _, cmd, rest = string.find(msg or "", "^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")
    rest = string.lower(rest or "")
    if rest == "auto" then rest = "size" end
    if cmd == "dockdebug" then
        D.debug()
    elseif cmd == "fixtabs" then
        local n = D.repairDock(true)
        M.Print(n > 0 and "chat tabs put back in the dock." or "chat dock looks fine.")
    elseif cmd == "dockfit" and (rest == "size" or rest == "scale") then
        local c = cfg()
        c.twtFit = rest
        c.twtAuto = nil
        if D.docked.twthreat then D.docked.twthreat.twtMiss = 0 end
        D.layout()
        M.Print("TWThreat dock fit: " .. rest)
    else
        M.Print("/ichachat dockdebug - Meters dock sizes; /ichachat dockfit size|scale (now " .. D.twtMode()
            .. "; scale = TWThreat's own layout scaled up, bigger text); /ichachat fixtabs - re-dock stuck chat tabs")
    end
end

