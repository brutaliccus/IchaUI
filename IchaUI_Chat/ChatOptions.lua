-- IchaUI Chat config: the "Chat" tab in /iui. Options.lua makes the page and
-- passes its widget helpers; this file lays out sub-tabs (no scrolling).

local M = IchaUIChat
local O = {}
M.Options = O

local X1, X2 = 10, 560
local SUB_Y = -58
local seq = 0

------------------------------------------------------------------------
-- Widgets
------------------------------------------------------------------------
local function white(fs)
    if IchaUI_DyeFs then IchaUI_DyeFs(fs, 1, 1, 1) else fs:SetTextColor(1, 1, 1) end
end

local function label(parent, text, x, y, w)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if w then fs:SetWidth(w) end
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    white(fs)
    return fs
end

local function header(ctx, parent, text, x, y)
    return ctx.U.sectionHeader(parent, text, x, y)
end

function O.refresh(ctx)
    ctx.loading = true
    local i
    for i = 1, table.getn(ctx.refresh) do
        pcall(ctx.refresh[i])
    end
    ctx.loading = false
end

function O.changed(ctx, soft)
    M.ApplyAll()
    if not soft then O.refresh(ctx) end
end

local function toggle(ctx, parent, text, x, y, w, get, set)
    local b = ctx.U.makeGoldToggle(parent, text, w or 150, 18)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local function paint() ctx.U.paintGoldToggle(b, get() and true or false) end
    b:SetScript("OnClick", function()
        set(not get())
        O.changed(ctx)
    end)
    table.insert(ctx.refresh, paint)
    return b
end

local function cycle(ctx, parent, prefix, x, y, w, opts, get, set)
    local b = ctx.U.makeButton(parent, "", w or 160, 20, nil)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local function find()
        local v = get()
        local i
        for i = 1, table.getn(opts) do
            if opts[i][1] == v then return i end
        end
        return 1
    end
    local function paint() b:SetText(prefix .. ": " .. (opts[find()][2] or "?")) end
    if IchaUI_ChoiceArrow then IchaUI_ChoiceArrow(b) end
    b:SetScript("OnClick", function()
        local pick = function(i)
            set(opts[i][1])
            O.changed(ctx)
        end
        if IchaUI_ChoiceMenu then
            IchaUI_ChoiceMenu(this, opts, find(), pick, opts.fonts)
            return
        end
        local i = find()
        if arg1 == "RightButton" then i = i - 1 else i = i + 1 end
        if i > table.getn(opts) then i = 1 end
        if i < 1 then i = table.getn(opts) end
        pick(i)
    end)
    table.insert(ctx.refresh, paint)
    return b
end

local function slider(ctx, parent, title, x, y, lw, sw, lo, hi, step, get, set)
    seq = seq + 1
    local name = "IchaUIChatOptSlider" .. seq
    label(parent, title, x, y - 1, lw)
    local sl = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    sl:SetPoint("TOPLEFT", parent, "TOPLEFT", x + lw + 4, y - 1)
    sl:SetWidth(sw)
    sl:SetHeight(16)
    sl:SetMinMaxValues(lo, hi)
    sl:SetValueStep(step)
    getglobal(name .. "Low"):SetText("")
    getglobal(name .. "High"):SetText("")
    getglobal(name .. "Text"):SetText("")
    local val = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    val:SetPoint("LEFT", sl, "RIGHT", 6, 0)
    white(val)
    local function fmt(v)
        if step < 1 then return string.format("%.2f", v) end
        return tostring(math.floor(v + 0.5))
    end
    sl:SetScript("OnValueChanged", function()
        local v = this:GetValue()
        if step >= 1 then v = math.floor(v / step + 0.5) * step end
        val:SetText(fmt(v))
        if not ctx.loading then
            set(v)
            O.changed(ctx, true)
        end
    end)
    table.insert(ctx.refresh, function()
        local v = tonumber(get()) or lo
        sl:SetValue(v)
        val:SetText(fmt(v))
    end)
    return sl
end

local function edit(ctx, parent, x, y, w, get, set)
    local e = ctx.U.makeEdit(parent, w, 18)
    e:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local function commit()
        if ctx.loading then return end
        local t = e:GetText() or ""
        if t ~= (get() or "") then
            set(t)
            O.changed(ctx)
        end
    end
    e:SetScript("OnEnterPressed", function()
        commit()
        this:ClearFocus()
    end)
    e:SetScript("OnEditFocusLost", function() commit() end)
    table.insert(ctx.refresh, function() e:SetText(get() or "") end)
    return e
end

local function button(ctx, parent, text, x, y, w, fn)
    local b = ctx.U.makeButton(parent, text, w or 140, 20, fn)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return b
end

local function openPicker(r, g, b, apply)
    if IchaUI_OpenColorPicker then
        IchaUI_OpenColorPicker(r, g, b, apply)
        return
    end
    if not ColorPickerFrame then return end
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.opacityFunc = nil
    ColorPickerFrame.previousValues = { r = r, g = g, b = b }
    ColorPickerFrame.func = function()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        apply(nr, ng, nb)
    end
    ColorPickerFrame.cancelFunc = function() apply(r, g, b) end
    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame:Hide()
    ColorPickerFrame:Show()
    ColorPickerFrame:SetFrameStrata("TOOLTIP")
end

local function swatch(ctx, parent, x, y, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(40)
    b:SetHeight(16)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    b:SetBackdropColor(0.05, 0.05, 0.06, 1)
    if IchaUI_PaintGoldBorder then IchaUI_PaintGoldBorder(b, 1) end
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
    t:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
    t:SetTexture("Interface/Buttons/WHITE8X8")
    local function paint()
        local c = get() or { r = 1, g = 1, b = 1 }
        t:SetVertexColor(c.r or 1, c.g or 1, c.b or 1, 1)
    end
    b:SetScript("OnClick", function()
        local c = get() or { r = 1, g = 1, b = 1 }
        openPicker(c.r or 1, c.g or 1, c.b or 1, function(nr, ng, nb)
            set({ r = nr, g = ng, b = nb })
            paint()
            M.ApplyAll()
        end)
    end)
    table.insert(ctx.refresh, paint)
    return b
end

local function winName(i)
    if GetChatWindowInfo then
        local n = GetChatWindowInfo(i)
        if n and n ~= "" then return n end
    end
    return "Window " .. i
end

local function winTip(b, id)
    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText(id .. ": " .. winName(id))
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Per-window on/off row
local function windowRow(ctx, parent, x, y, getTbl)
    label(parent, "Windows", x, y - 3, 58)
    local i
    for i = 1, M.numWindows() do
        local id = i
        local b = ctx.U.makeGoldToggle(parent, tostring(id), 24, 18)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 60 + (id - 1) * 27, y)
        b:SetScript("OnClick", function()
            local t = getTbl()
            t[id] = not M.winOn(t, id)
            O.changed(ctx)
        end)
        winTip(b, id)
        table.insert(ctx.refresh, function() ctx.U.paintGoldToggle(b, M.winOn(getTbl(), id)) end)
    end
end

-- Pick-one window row (Font / Fade pages)
local function windowPick(ctx, parent, x, y)
    label(parent, "Window", x, y - 3, 58)
    local i
    for i = 1, M.numWindows() do
        local id = i
        local b = ctx.U.makeGoldToggle(parent, tostring(id), 24, 18)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 60 + (id - 1) * 27, y)
        b:SetScript("OnClick", function()
            ctx.win = id
            O.refresh(ctx)
        end)
        winTip(b, id)
        table.insert(ctx.refresh, function() ctx.U.paintGoldToggle(b, ctx.win == id) end)
    end
end

local function tbl(section, key)
    local c = M.C(section)
    if type(c[key]) ~= "table" then c[key] = {} end
    return c[key]
end

local function getter(section, key) return function() return M.C(section)[key] end end
local function setter(section, key) return function(v) M.C(section)[key] = v end end

------------------------------------------------------------------------
-- Edit box
------------------------------------------------------------------------
local function buildEditBox(ctx, p)
    local y = -4
    header(ctx, p, "Edit box position", X1, y); y = y - 22
    cycle(ctx, p, "Position", X1, y, 170, { { "TOP", "Top" }, { "BOTTOM", "Bottom" }, { "FREE", "Free" } },
        getter("editbox", "position"), setter("editbox", "position"))
    cycle(ctx, p, "Width", X1 + 180, y, 170, { { "match", "Match chat" }, { "fixed", "Fixed px" } },
        getter("editbox", "widthMode"), setter("editbox", "widthMode")); y = y - 28
    slider(ctx, p, "Width px", X1, y, 70, 200, 120, 900, 5, getter("editbox", "width"), setter("editbox", "width")); y = y - 26
    slider(ctx, p, "X offset", X1, y, 70, 200, -200, 200, 1, getter("editbox", "offX"), setter("editbox", "offX")); y = y - 26
    slider(ctx, p, "Y gap", X1, y, 70, 200, -20, 60, 1, getter("editbox", "gap"), setter("editbox", "gap")); y = y - 26
    slider(ctx, p, "Height", X1, y, 70, 200, 0, 48, 1, getter("editbox", "height"), setter("editbox", "height")); y = y - 28
    toggle(ctx, p, "Locked (Free mode)", X1, y, 170, getter("editbox", "locked"), setter("editbox", "locked"))
    button(ctx, p, "Reset free position", X1 + 180, y + 1, 150, function()
        local c = M.C("editbox")
        c.freePoint, c.freeRelPoint, c.freeX, c.freeY = "BOTTOMLEFT", "BOTTOMLEFT", 30, 220
        O.changed(ctx)
    end); y = y - 30
    label(p, "Top / Bottom anchor to the selected chat window's gold border. Y gap is the space between border and box. " ..
        "Height 0 keeps the game's height (at least 30). Free: unlock, drag the open edit box, then lock. " ..
        "Free is anchored to the screen (UIParent).", X1, y, 480)

    local y2 = -4
    header(ctx, p, "Keys", X2, y2); y2 = y2 - 22
    toggle(ctx, p, "Arrow keys without Alt", X2, y2, 190, getter("editbox", "arrowKeys"), setter("editbox", "arrowKeys"))
    toggle(ctx, p, "Keep unsent text after Esc", X2 + 200, y2, 200, getter("editbox", "sticky"), setter("editbox", "sticky")); y2 = y2 - 34

    header(ctx, p, "MoveAnything", X2, y2); y2 = y2 - 22
    local st = label(p, "", X2, y2, 500)
    table.insert(ctx.refresh, function()
        if M.EditBox.maHooked() then
            st:SetText("MoveAnything is holding the edit box (\"Chat EditBox (Move to Top)\"). While it does, its own top/bottom anchor wins.")
            st:SetTextColor(1, 0.62, 0.3)
        else
            st:SetText("MoveAnything is not holding the edit box. IchaUI places it.")
            white(st)
        end
    end); y2 = y2 - 30
    button(ctx, p, "Release from MoveAnything", X2, y2, 200, function()
        M.EditBox.releaseMA()
        O.refresh(ctx)
    end)
    button(ctx, p, "Re-apply position", X2 + 210, y2, 140, function() M.EditBox.place() end); y2 = y2 - 28
    label(p, "Release uses MoveAnything's own reset for that one entry. Your other MoveAnything frames are untouched.", X2, y2, 500)
end

------------------------------------------------------------------------
-- Messages: timestamps, names, channel tags, URLs
------------------------------------------------------------------------
local TS_FORMATS = {
    { "%H:%M", "14:05" }, { "%H:%M:%S", "14:05:09" }, { "%I:%M %p", "02:05 PM" },
    { "%I:%M:%S %p", "02:05:09 PM" }, { "%X", "Locale (%X)" },
}

local TAG_LABELS = {
    SAY = "Say", YELL = "Yell", PARTY = "Party", GUILD = "Guild", OFFICER = "Officer", RAID = "Raid",
    RAID_LEADER = "Raid lead", RAID_WARNING = "Raid warn", BATTLEGROUND = "BG", BATTLEGROUND_LEADER = "BG lead",
    WHISPER = "Whisper in", WHISPER_INFORM = "Whisper out",
}

local function buildMessagesLeft(ctx, p)
    local y = -4
    header(ctx, p, "Timestamps (applied last)", X1, y); y = y - 22
    toggle(ctx, p, "Timestamps", X1, y, 110, getter("timestamps", "on"), setter("timestamps", "on"))
    toggle(ctx, p, "Server time", X1 + 118, y, 100, getter("timestamps", "server"), setter("timestamps", "server"))
    label(p, "Color", X1 + 230, y - 3, 34)
    swatch(ctx, p, X1 + 266, y - 1, getter("timestamps", "color"), setter("timestamps", "color")); y = y - 26
    cycle(ctx, p, "Format", X1, y, 200, TS_FORMATS, getter("timestamps", "format"), setter("timestamps", "format"))
    label(p, "Custom", X1 + 210, y - 4, 44)
    edit(ctx, p, X1 + 256, y - 1, 90, getter("timestamps", "format"), setter("timestamps", "format")); y = y - 26
    windowRow(ctx, p, X1, y, function() return tbl("timestamps", "windows") end); y = y - 36

    header(ctx, p, "Player names", X1, y); y = y - 22
    toggle(ctx, p, "Name styling", X1, y, 110, getter("names", "on"), setter("names", "on"))
    cycle(ctx, p, "Brackets", X1 + 118, y + 1, 150, { { "square", "[Name]" }, { "angle", "<Name>" }, { "none", "Name" } },
        getter("names", "brackets"), setter("names", "brackets")); y = y - 24
    toggle(ctx, p, "Show level", X1, y, 110, getter("names", "level"), setter("names", "level"))
    toggle(ctx, p, "Raid group", X1 + 118, y, 110, getter("names", "group"), setter("names", "group")); y = y - 22
    local cnt = label(p, "", X1, y, 480)
    table.insert(ctx.refresh, function()
        cnt:SetText("Styling = class colors + brackets. Level and group work on their own. Known from group, guild, " ..
            "friends, /who and targets. Cache: " .. M.Pipeline.cacheCount() .. " names (cap " .. (M.C("names").cacheMax or 2000) .. ").")
    end)
end

local function buildMessagesRight(ctx, p)
    local y = -4
    header(ctx, p, "Short channel tags", X2, y); y = y - 22
    toggle(ctx, p, "Channel tags", X2, y, 110, getter("channels", "on"), setter("channels", "on"))
    toggle(ctx, p, "Space after tag", X2 + 118, y, 120, getter("channels", "space"), setter("channels", "space"))
    toggle(ctx, p, "Colon after name", X2 + 246, y, 130, getter("channels", "colon"), setter("channels", "colon")); y = y - 24
    local types = M.Pipeline.TAG_TYPES
    local i
    for i = 1, table.getn(types) do
        local t = types[i]
        local col = math.mod(i - 1, 3)
        local row = math.floor((i - 1) / 3)
        local x = X2 + col * 180
        local yy = y - row * 22
        label(p, TAG_LABELS[t] or t, x, yy - 3, 70)
        edit(ctx, p, x + 72, yy, 90, function()
            local v = tbl("channels", "tags")[t]
            if v == nil then v = M.Pipeline.TAG_DEFAULTS[t] end
            return v
        end, function(v) tbl("channels", "tags")[t] = v end)
    end
    y = y - 4 * 22 - 4
    label(p, "Numbered channels (blank = [number]):", X2, y - 2, 300); y = y - 18
    for i = 1, 10 do
        local n = i
        local col = math.mod(n - 1, 5)
        local row = math.floor((n - 1) / 5)
        local x = X2 + col * 106
        local yy = y - row * 22
        label(p, n .. ".", x, yy - 3, 18)
        edit(ctx, p, x + 18, yy, 80, function() return tbl("channels", "chan")[n] or "" end,
            function(v) tbl("channels", "chan")[n] = v end)
    end
    y = y - 2 * 22 - 2 - 30

    header(ctx, p, "Clickable URLs", X2, y); y = y - 22
    toggle(ctx, p, "URL links", X2, y, 110, getter("urls", "on"), setter("urls", "on"))
    toggle(ctx, p, "[Brackets]", X2 + 118, y, 100, getter("urls", "brackets"), setter("urls", "brackets"))
    label(p, "Color", X2 + 230, y - 3, 34)
    swatch(ctx, p, X2 + 266, y - 1, getter("urls", "color"), setter("urls", "color")); y = y - 22
    label(p, "Click a link to open a copy box (Ctrl+C). Matches at the start of a line too.", X2, y, 520)
end

------------------------------------------------------------------------
-- Scrolling
------------------------------------------------------------------------
local STICKY_LABELS = {
    SAY = "Say", YELL = "Yell", PARTY = "Party", GUILD = "Guild", OFFICER = "Officer", RAID = "Raid",
    RAID_WARNING = "Raid warning", BATTLEGROUND = "Battleground", WHISPER = "Whisper", CHANNEL = "Channels", EMOTE = "Emote",
}

local function buildScrolling(ctx, p)
    local y = -4
    header(ctx, p, "Mouse wheel", X1, y); y = y - 22
    toggle(ctx, p, "Mouse wheel", X1, y, 110, getter("scroll", "wheel"), setter("scroll", "wheel"))
    toggle(ctx, p, "Shift = top / bottom", X1 + 118, y, 150, getter("scroll", "shiftJump"), setter("scroll", "shiftJump")); y = y - 26
    slider(ctx, p, "Lines / notch", X1, y, 80, 180, 1, 10, 1, getter("scroll", "lines"), setter("scroll", "lines")); y = y - 26
    slider(ctx, p, "Ctrl x", X1, y, 80, 180, 1, 10, 1, getter("scroll", "ctrlMult"), setter("scroll", "ctrlMult")); y = y - 34

    header(ctx, p, "Scrollback", X1, y); y = y - 22
    ctx.pendingMax = nil
    slider(ctx, p, "Lines", X1, y, 80, 180, 128, 1000, 8, function() return ctx.pendingMax or M.C("scroll").maxLines end,
        function(v) ctx.pendingMax = v end)
    button(ctx, p, "Apply", X1 + 330, y + 1, 70, function()
        if ctx.pendingMax then M.C("scroll").maxLines = ctx.pendingMax end
        ctx.pendingMax = nil
        M.Scroll.applyMaxLines()
        O.refresh(ctx)
    end); y = y - 24
    label(p, "Applying a new length clears the chat windows (the game does that).", X1, y, 480); y = y - 30

    header(ctx, p, "Scroll-to-bottom reminder", X1, y); y = y - 22
    toggle(ctx, p, "Reminder arrow", X1, y, 130, getter("scroll", "reminder"), setter("scroll", "reminder")); y = y - 22
    label(p, "A small gold arrow in the corner while you're scrolled up. Click it to jump down.", X1, y, 480)

    local y2 = -4
    header(ctx, p, "Sticky channels", X2, y2); y2 = y2 - 22
    toggle(ctx, p, "Manage sticky", X2, y2, 120, getter("scroll", "stickyOn"), setter("scroll", "stickyOn")); y2 = y2 - 24
    local types = M.Scroll.STICKY_TYPES
    local i
    for i = 1, table.getn(types) do
        local t = types[i]
        local col = math.mod(i - 1, 3)
        local row = math.floor((i - 1) / 3)
        toggle(ctx, p, STICKY_LABELS[t] or t, X2 + col * 150, y2 - row * 22, 140,
            function() return tbl("scroll", "sticky")[t] end,
            function(v) tbl("scroll", "sticky")[t] = v end)
    end
    y2 = y2 - 4 * 22 - 4
    label(p, "A sticky type stays selected in the edit box after you send.", X2, y2, 480)
end

------------------------------------------------------------------------
-- Tabs (+ channel color memory)
------------------------------------------------------------------------
local function buildTabs(ctx, p)
    local y = -4
    header(ctx, p, "Tab names", X1, y); y = y - 22
    toggle(ctx, p, "Dim the names of tabs you're not on", X1, y, 260, getter("tabs", "on"), setter("tabs", "on")); y = y - 24
    slider(ctx, p, "Dimmed brightness", X1, y, 110, 180, 0.1, 1, 0.05, getter("tabs", "inactiveAlpha"), setter("tabs", "inactiveAlpha")); y = y - 22
    label(p, "Only the text of the other docked tabs fades, so the tab you're on stands out. 1 = no dimming.", X1, y, 480); y = y - 32

    header(ctx, p, "Whisper alert", X1, y); y = y - 22
    toggle(ctx, p, "Flash the tab I'm on when a whisper arrives", X1, y, 300, getter("tabs", "flashWhisper"), setter("tabs", "flashWhisper")); y = y - 22
    label(p, "The game only flashes tabs you're not looking at. This also flashes the one you're on, if it shows whispers.", X1, y, 480); y = y - 32

    header(ctx, p, "Starting tab", X1, y); y = y - 22
    local opts = { { 0, "Game's choice" } }
    local i
    for i = 1, M.numWindows() do table.insert(opts, { i, tostring(i) }) end
    cycle(ctx, p, "Open at login", X1, y, 200, opts, function() return tonumber(M.C("tabs").loginTab) or 0 end,
        setter("tabs", "loginTab"))
    local nm = label(p, "", X1 + 210, y - 4, 200)
    table.insert(ctx.refresh, function()
        local id = tonumber(M.C("tabs").loginTab) or 0
        nm:SetText(id > 0 and winName(id) or "")
    end); y = y - 24
    label(p, "Picks which docked chat window's tab is selected after login or /reload.", X1, y, 480); y = y - 32

    header(ctx, p, "Leaving meter tabs", X1, y); y = y - 22
    toggle(ctx, p, "Leave a meter tab when a whisper comes in or I type", X1, y, 340, getter("dock", "backToGeneral"), setter("dock", "backToGeneral")); y = y - 22
    label(p, "Only acts while a meter tab is showing. Picks one tab: a whisper opens the tab most dedicated to whispers " ..
        "(your Whispers tab before General); typing goes back to the chat tab you were last on, or one that shows what you're typing. " ..
        "Never switches away from a chat tab.", X1, y, 480)

    local y2 = -4
    header(ctx, p, "Channel colors", X2, y2); y2 = y2 - 22
    toggle(ctx, p, "Remember channel colors", X2, y2, 190, getter("colors", "on"), setter("colors", "on")); y2 = y2 - 22
    label(p, "Colors are kept by channel name and put back when you rejoin or a channel's number changes.", X2, y2, 480); y2 = y2 - 30
    button(ctx, p, "Forget saved colors", X2, y2, 150, function()
        M.C("colors").map = {}
        M.Print("channel color memory cleared.")
    end)
end

------------------------------------------------------------------------
-- History + copy
------------------------------------------------------------------------
local function buildHistory(ctx, p)
    local y = -4
    header(ctx, p, "Saved chat history", X1, y); y = y - 22
    toggle(ctx, p, "Saved history", X1, y, 120, getter("history", "on"), setter("history", "on")); y = y - 26
    slider(ctx, p, "Lines / window", X1, y, 90, 180, 5, 200, 5, getter("history", "lines"), setter("history", "lines")); y = y - 26
    windowRow(ctx, p, X1, y, function() return tbl("history", "windows") end); y = y - 28
    button(ctx, p, "Clear saved history", X1, y, 150, function()
        M.Pipeline.clearHistory()
        M.Print("saved chat history cleared.")
    end); y = y - 28
    label(p, "Replays the last lines of each chosen window after /reload or login. Replayed lines skip timestamps, names and links, so nothing doubles. " ..
        "If another chat addon also restores history, turn one of them off.", X1, y, 480)

    local y2 = -4
    header(ctx, p, "Copy chat", X2, y2); y2 = y2 - 22
    slider(ctx, p, "Lines", X2, y2, 60, 180, 50, 500, 10, getter("history", "copyLines"), setter("history", "copyLines")); y2 = y2 - 26
    toggle(ctx, p, "Copy button in chat windows", X2, y2, 210, getter("history", "copyButton"), setter("history", "copyButton")); y2 = y2 - 26
    button(ctx, p, "Copy selected window", X2, y2, 170, function() M.CopyBox.CopyChat(nil) end); y2 = y2 - 28
    label(p, "Keybind: Key Bindings > IchaUI Chat. Or type /chatcopy. Opens the window's recent lines in a box; Ctrl+C copies.", X2, y2, 480)
end

------------------------------------------------------------------------
-- Links: hover tooltips, name clicks, CLINK, social list colors
------------------------------------------------------------------------
local function buildLinks(ctx, p)
    local y = -4
    header(ctx, p, "Chat links", X1, y); y = y - 22
    toggle(ctx, p, "Hover tooltips", X1, y, 130, getter("links", "tips"), setter("links", "tips"))
    toggle(ctx, p, "Convert CLINK links", X1 + 138, y, 160, getter("links", "clink"), setter("links", "clink")); y = y - 22
    label(p, "Hovering an item, spell or quest link in chat shows its tooltip. CLINK turns Prat/Chatter " ..
        "{CLINK:...} text into real links.", X1, y, 480); y = y - 34

    header(ctx, p, "Player name clicks", X1, y); y = y - 22
    toggle(ctx, p, "Alt-click: invite", X1, y, 130, getter("links", "altInvite"), setter("links", "altInvite"))
    toggle(ctx, p, "Ctrl-click: target", X1 + 138, y, 140, getter("links", "ctrlTarget"), setter("links", "ctrlTarget"))
    toggle(ctx, p, "Shift-click: name to edit box", X1 + 286, y, 200, getter("links", "shiftName"), setter("links", "shiftName")); y = y - 22
    label(p, "Shift-click only inserts while the edit box is open; otherwise it does the game's /who.", X1, y, 480)

    local y2 = -4
    header(ctx, p, "Social lists", X2, y2); y2 = y2 - 22
    toggle(ctx, p, "Class colors in Who / Guild / Friends", X2, y2, 260, getter("links", "social"), setter("links", "social")); y2 = y2 - 22
    label(p, "Names and classes in class color, levels in difficulty color. Offline guild members are dimmed.", X2, y2, 480)
end

------------------------------------------------------------------------
-- Dock
------------------------------------------------------------------------
local function dropdown(ctx, parent, x, y, w, text, opts, cur, pick)
    local b = ctx.U.makeButton(parent, "", w, 20, nil)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if IchaUI_ChoiceArrow then IchaUI_ChoiceArrow(b) end
    b:SetScript("OnClick", function()
        local o = opts()
        if table.getn(o) == 0 then return end
        if IchaUI_ChoiceMenu then
            IchaUI_ChoiceMenu(this, o, cur(), pick)
        else
            pick(1)
        end
    end)
    table.insert(ctx.refresh, function() b:SetText(text()) end)
    return b
end

local function buildDock(ctx, p)
    local D = M.Dock
    local function sel()
        local n = D.numTabs()
        local s = tonumber(ctx.dockTab) or 1
        if s > n then s = n end
        if s < 1 then s = 1 end
        ctx.dockTab = s
        return s
    end
    local function has() return D.numTabs() > 0 end

    local y = -4
    header(ctx, p, "Meter tabs", X1, y); y = y - 22
    toggle(ctx, p, "Docking", X1, y, 90, getter("dock", "on"), setter("dock", "on"))
    cycle(ctx, p, "TWThreat fit", X1 + 98, y + 1, 170, { { "size", "Resize" }, { "scale", "Scale up" } },
        function() return M.Dock.twtMode() end,
        function(v)
            local c = M.C("dock")
            c.twtFit = v
            c.twtAuto = nil
            if D.docked.twthreat then D.docked.twthreat.twtMiss = 0 end
            D.layout()
        end); y = y - 26
    slider(ctx, p, "Extra inset", X1, y, 80, 160, 0, 12, 1, getter("dock", "inset"), setter("dock", "inset")); y = y - 26
    toggle(ctx, p, "Leave a meter tab when a whisper comes in or I type", X1, y, 340, getter("dock", "backToGeneral"), setter("dock", "backToGeneral")); y = y - 30

    header(ctx, p, "Tab", X1, y); y = y - 22
    dropdown(ctx, p, X1, y, 200,
        function() return has() and ("Tab: " .. D.tabName(sel())) or "Tab: none" end,
        function()
            local o = {}
            local i
            for i = 1, D.numTabs() do table.insert(o, { i, D.tabName(i) }) end
            return o
        end,
        sel,
        function(i) ctx.dockTab = i; O.refresh(ctx) end)
    button(ctx, p, "+ New tab", X1 + 206, y, 96, function()
        ctx.dockTab = D.addTab("Meters")
        O.refresh(ctx)
    end)
    local rm = button(ctx, p, "Remove tab", X1 + 308, y, 100, function()
        if not has() then return end
        D.removeTab(sel())
        O.refresh(ctx)
    end); y = y - 26
    local nl = label(p, "Name", X1, y - 3, 40)
    local ne = edit(ctx, p, X1 + 42, y, 158,
        function() return has() and D.tabName(sel()) or "" end,
        function(t) if has() then D.renameTab(sel(), t) end end)
    local lay = cycle(ctx, p, "Layout", X1 + 206, y + 1, 202, { { "auto", "Auto" }, { "fill", "Fill" }, { "split", "Side by side" } },
        function() return has() and D.tabLayout(sel()) or "auto" end,
        function(v) if has() then D.setTabLayout(sel(), v) end end); y = y - 26
    local hs = label(p, "", X1, y - 2, 480)
    table.insert(ctx.refresh, function()
        if not has() then
            hs:SetText("No meter tabs yet. + New tab makes one; add meters to it on the right.")
            rm:Hide(); nl:Hide(); ne:Hide(); lay:Hide()
            return
        end
        rm:Show(); nl:Show(); ne:Show(); lay:Show()
        local h, id = D.tabHost(sel())
        if h and h._icFake then
            hs:SetText("Host: fallback tab (all 7 chat windows are in use).")
        elseif h then
            hs:SetText("Host: chat window " .. (id or "?") .. " (" .. winName(id or 1) .. ").")
        else
            hs:SetText("Host: none. It is made when this tab gets a meter.")
        end
    end); y = y - 24
    label(p, "Each tab is a spare chat window (4-7) with no messages. A meter sits on one tab; " ..
        "adding it to another tab moves it. Docked frames can't be dragged; Remove puts them back.", X1, y, 480)

    local y2 = -4
    header(ctx, p, "Meters on this tab", X2, y2); y2 = y2 - 22
    dropdown(ctx, p, X2, y2, 250,
        function() return "+ Add meter" end,
        function()
            local o = {}
            local list = D.meterChoices()
            ctx.dockChoices = list
            local i
            for i = 1, table.getn(list) do
                local l = list[i].label
                local on = D.entryTab(list[i].entry)
                if on then l = l .. "  (on " .. D.tabName(on) .. ")" end
                table.insert(o, { i, l, entry = list[i].entry })
            end
            return o
        end,
        function() return nil end,
        function(i)
            local list = ctx.dockChoices or D.meterChoices()
            if not list[i] then return end
            if not has() then ctx.dockTab = D.addTab("Meters") end
            D.addEntry(sel(), list[i].entry)
            O.refresh(ctx)
        end)
    local nameEd = ctx.U.makeEdit(p, 130, 18)
    nameEd:SetPoint("TOPLEFT", p, "TOPLEFT", X2 + 258, y2)
    button(ctx, p, "+ Frame", X2 + 394, y2 + 1, 80, function()
        local n = string.gsub(nameEd:GetText() or "", "%s", "")
        if n == "" then return end
        if not getglobal(n) then
            M.Print("no frame named " .. n .. ".")
            return
        end
        if not has() then ctx.dockTab = D.addTab("Meters") end
        D.addEntry(sel(), { key = "custom", name = n })
        nameEd:SetText("")
        O.refresh(ctx)
    end); y2 = y2 - 28
    local rows = {}
    local i
    for i = 1, 8 do
        local idx = i
        local r = {}
        r.fs = label(p, "", X2, y2 - (i - 1) * 24 - 3, 330)
        r.btn = button(ctx, p, "Remove", X2 + 340, y2 - (i - 1) * 24, 80, function()
            if has() then D.removeEntry(sel(), idx) end
            O.refresh(ctx)
        end)
        rows[i] = r
    end
    table.insert(ctx.refresh, function()
        local ti = has() and sel() or nil
        local list = ti and D.tabFrames(ti) or {}
        local j
        for j = 1, 8 do
            local e = list[j]
            if e then
                rows[j].fs:SetText(D.entryLabel(e) .. "  |cffbbbbbb(" .. D.entryStatus(e, ti) .. ")|r")
                rows[j].fs:Show()
                rows[j].btn:Show()
            elseif j == 1 then
                rows[j].fs:SetText("|cffbbbbbbNo meters on this tab.|r")
                rows[j].fs:Show()
                rows[j].btn:Hide()
            else
                rows[j].fs:Hide()
                rows[j].btn:Hide()
            end
        end
    end)
    y2 = y2 - 8 * 24 - 4
    label(p, "Caw's extra windows (its + button) show up here as Caw 2-4 with their mode; " ..
        "Caw (all windows) takes every Caw window no other tab has.", X2, y2, 480)
end

------------------------------------------------------------------------
-- Font + fading
------------------------------------------------------------------------
local function fontWin(ctx)
    local w = tbl("font", "windows")
    if type(w[ctx.win]) ~= "table" then w[ctx.win] = {} end
    return w[ctx.win]
end

local function fadeWin(ctx)
    local w = tbl("fade", "windows")
    if type(w[ctx.win]) ~= "table" then w[ctx.win] = { fade = true, time = 120 } end
    return w[ctx.win]
end

local function buildFont(ctx, p)
    ctx.win = ctx.win or 1
    local y = -4
    header(ctx, p, "Font", X1, y); y = y - 22
    toggle(ctx, p, "Custom fonts", X1, y, 120, getter("font", "on"), setter("font", "on")); y = y - 26
    windowPick(ctx, p, X1, y); y = y - 28
    local faces = {}
    local i
    for i = 1, table.getn(M.Tabs.FONTS) do
        local f = M.Tabs.FONTS[i]
        table.insert(faces, { f[2], f[1] })
    end
    faces.fonts = true
    cycle(ctx, p, "Face", X1, y, 220, faces, function() return fontWin(ctx).face end, function(v) fontWin(ctx).face = v end)
    cycle(ctx, p, "Justify", X1 + 230, y, 150, { { nil, "Left" }, { "CENTER", "Center" }, { "RIGHT", "Right" } },
        function() return fontWin(ctx).justify end, function(v) fontWin(ctx).justify = v end); y = y - 28
    slider(ctx, p, "Size", X1, y, 50, 200, 0, 22, 1, function() return fontWin(ctx).size or 0 end,
        function(v) if v < 8 then fontWin(ctx).size = nil else fontWin(ctx).size = v end end); y = y - 26
    button(ctx, p, "Copy to all windows", X1, y, 160, function()
        local src = fontWin(ctx)
        local w = tbl("font", "windows")
        local j
        for j = 1, M.numWindows() do w[j] = { face = src.face, size = src.size, justify = src.justify } end
        O.changed(ctx)
    end); y = y - 28
    label(p, "Size 0 keeps the window's own size. The nameplate font is never touched.", X1, y, 480)

    local y2 = -4
    header(ctx, p, "Text fading", X2, y2); y2 = y2 - 22
    toggle(ctx, p, "Manage fading", X2, y2, 120, getter("fade", "on"), setter("fade", "on")); y2 = y2 - 26
    label(p, "Uses the window picked on the left.", X2, y2 - 3, 300); y2 = y2 - 22
    toggle(ctx, p, "Fade old lines", X2, y2, 120, function() return fadeWin(ctx).fade end, function(v) fadeWin(ctx).fade = v end); y2 = y2 - 26
    slider(ctx, p, "Fade after (s)", X2, y2, 90, 180, 5, 300, 5, function() return fadeWin(ctx).time or 120 end,
        function(v) fadeWin(ctx).time = v end)
end

------------------------------------------------------------------------
-- Chat skin strip (border + bg alpha, moved here from the Skin tab)
------------------------------------------------------------------------
local function buildSkinStrip(ctx, pg)
    local x = 740
    local b = ctx.U.makeButton(pg, "Border: On", 90, 20, function()
        if not IchaUIChatSkin_Set then return end
        local g = IchaUIChatSkin_Get and IchaUIChatSkin_Get()
        IchaUIChatSkin_Set("enabled", not (g and g.enabled))
        O.changed(ctx)
    end)
    b:SetPoint("TOPLEFT", pg, "TOPLEFT", x, -4)
    table.insert(ctx.refresh, function()
        local g = IchaUIChatSkin_Get and IchaUIChatSkin_Get()
        b:SetText((g and g.enabled) and "Border: On" or "Border: Off")
    end)
    slider(ctx, pg, "Bg alpha", x + 100, -6, 52, 120, 0.2, 1.0, 0.05,
        function()
            local g = IchaUIChatSkin_Get and IchaUIChatSkin_Get()
            return (g and g.alpha) or 0.75
        end,
        function(v) if IchaUIChatSkin_Set then IchaUIChatSkin_Set("alpha", v) end end)
end

------------------------------------------------------------------------
-- Entry point (called from Options.lua)
------------------------------------------------------------------------
local SUBS = {
    { "Edit box", function(ctx, p) buildEditBox(ctx, p) end },
    { "Messages", function(ctx, p) buildMessagesLeft(ctx, p); buildMessagesRight(ctx, p) end },
    { "Scrolling", function(ctx, p) buildScrolling(ctx, p) end },
    { "Tabs", function(ctx, p) buildTabs(ctx, p) end },
    { "History", function(ctx, p) buildHistory(ctx, p) end },
    { "Dock", function(ctx, p) buildDock(ctx, p) end },
    { "Font", function(ctx, p) buildFont(ctx, p) end },
    { "Links", function(ctx, p) buildLinks(ctx, p) end },
}

function IchaUIChat_BuildOptions(pg, U)
    local ctx = { pg = pg, U = U, refresh = {}, subs = {}, btns = {}, loading = false }
    local function show(n)
        ctx.active = n
        M.db().optSub = n
        local i
        for i = 1, table.getn(SUBS) do
            if i == n then ctx.subs[i]:Show() else ctx.subs[i]:Hide() end
            U.paintGoldToggle(ctx.btns[i], i == n)
        end
        O.refresh(ctx)
    end
    local i
    for i = 1, table.getn(SUBS) do
        local n = i
        local b = U.makeGoldToggle(pg, SUBS[i][1], 82, 20)
        b:SetPoint("TOPLEFT", pg, "TOPLEFT", X1 + (i - 1) * 86, -4)
        b:SetScript("OnClick", function() show(n) end)
        ctx.btns[i] = b
        local sub = CreateFrame("Frame", nil, pg)
        sub:SetPoint("TOPLEFT", pg, "TOPLEFT", 0, SUB_Y)
        sub:SetWidth(1100)
        sub:SetHeight(540)
        sub:Hide()
        ctx.subs[i] = sub
        SUBS[i][2](ctx, sub)
    end
    buildSkinStrip(ctx, pg)
    local line = pg:CreateTexture(nil, "ARTWORK")
    line:SetTexture("Interface/Buttons/WHITE8X8")
    line:SetVertexColor(0.78, 0.58, 0.16, 0.5)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", pg, "TOPLEFT", X1, -32)
    line:SetPoint("TOPRIGHT", pg, "TOPLEFT", 1090, -32)
    local start = tonumber(M.db().optSub) or 1
    if start < 1 or start > table.getn(SUBS) then start = 1 end
    show(start)
    return function()
        if ctx.active then show(ctx.active) end
    end
end
