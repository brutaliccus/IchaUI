-- IchaUI gold skin for TWThreat + Caw DPS Meter (Character/Spellbook stay stock)

-- Circle-button gold on the near-white tooltip edge (not TrackingBorder).
local GOLD = { 0.75, 0.52, 0.04, 1 }
local BG = { 0.05, 0.05, 0.06, 0.72 }
local enabled = true
local edgeSize = 12

local function db()
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.frameSkin then IchaUIDB.frameSkin = {} end
    return IchaUIDB.frameSkin
end

local function loadCfg()
    local d = db()
    if d.enabled ~= nil then
        enabled = d.enabled and true or false
    else
        enabled = true
        d.enabled = true
    end
end

local function saveCfg()
    local d = db()
    d.enabled = enabled
end

local function applyBackdrop(f, alpha, edge)
    if not f or not f.SetBackdrop then return end
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = edge or edgeSize,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(BG[1], BG[2], BG[3], alpha or BG[4])
    IchaUI_PaintGoldBorder(f, 1)
end

local function nukeTexture(t)
    if not t then return end
    if t.SetTexture then
        pcall(function() t:SetTexture("") end)
        pcall(function() t:SetTexture("Interface\\Buttons\\WHITE8X8") end)
    end
    if t.SetVertexColor then pcall(function() t:SetVertexColor(0, 0, 0, 0) end) end
    if t.SetAlpha then pcall(function() t:SetAlpha(0) end) end
    if t.Hide then pcall(function() t:Hide() end) end
end

local function hideBorderRegions(frame)
    if not frame or not frame.GetRegions then return end
    local regions = { frame:GetRegions() }
    local i
    for i = 1, table.getn(regions) do
        local r = regions[i]
        if r and r.GetObjectType and r:GetObjectType() == "Texture" then
            local name = r.GetName and r:GetName()
            local ok = true
            if name then
                local low = string.lower(name)
                if string.find(low, "icon", 1, true)
                    or string.find(low, "portrait", 1, true)
                    or string.find(low, "tab", 1, true)
                    or string.find(low, "brand", 1, true)
                    or string.find(low, "claw", 1, true) then
                    ok = false
                end
            end
            if ok then
                local w = (r.GetWidth and r:GetWidth()) or 0
                local h = (r.GetHeight and r:GetHeight()) or 0
                if (w > 20 and h < 40) or (h > 20 and w < 40) or (w > 100 and h > 100) then
                    nukeTexture(r)
                end
            end
        end
    end
end

local function hideNamedSuffixes(frame, suffixes)
    if not frame or not frame.GetName then return end
    local name = frame:GetName()
    if not name then return end
    local i
    for i = 1, table.getn(suffixes) do
        nukeTexture(getglobal(name .. suffixes[i]))
    end
end

local BLIZZ_BORDER_SUFFIXES = {
    "TopLeft", "TopRight", "Top", "BottomLeft", "BottomRight", "Bottom",
    "Left", "Right", "Background", "PortraitFrame",
}

local function skinFrame(frame, alpha)
    if not frame then return end
    local a = alpha or BG[4]
    pcall(function()
        hideNamedSuffixes(frame, BLIZZ_BORDER_SUFFIXES)
        hideBorderRegions(frame)
        applyBackdrop(frame, a, edgeSize)
        if not frame._ichaSkinHooked then
            frame._ichaSkinHooked = true
            local prevShow = frame:GetScript("OnShow")
            frame:SetScript("OnShow", function()
                if prevShow then pcall(prevShow) end
                if enabled then
                    applyBackdrop(this, a, edgeSize)
                end
            end)
            local prevSize = frame:GetScript("OnSizeChanged")
            frame:SetScript("OnSizeChanged", function()
                if prevSize then pcall(prevSize) end
                if enabled then
                    applyBackdrop(this, a, edgeSize)
                end
            end)
        end
    end)
end

-- CosminPOP/TWThreat: TWTMain is the meter; settings + tankmode windows too
local TWTHREAT_NAMES = {
    "TWTMain",
    "TWTMainSettings",
    "TWTMainTankModeWindow",
    "TWTWithAddonList",
    "TWThreatDisplayTarget",
    "TWThreatDisplayTargetPFUI",
}

local function skinTWThreat()
    local i
    for i = 1, table.getn(TWTHREAT_NAMES) do
        local f = getglobal(TWTHREAT_NAMES[i])
        if f then
            skinFrame(f, 0.65)
        end
    end
    local n
    for n = 1, 12 do
        local bar = getglobal("TWThreat" .. n)
        if bar then
            skinFrame(bar, 0.40)
        end
    end
    for n = 1, 5 do
        local tm = getglobal("TMEF" .. n)
        if tm then
            skinFrame(tm, 0.45)
        end
    end
end

-- NovaElysium/CawDPSMeter named frames (main window + panels)
local CAW_NAMES = {
    "CawDPSMeterWindow",
    "CawOptionsPanel",
    "CawBreakdownPanel",
    "CawComparePanel",
    "CawResetDialog",
    "CawWhisperDialog",
    "CawDPSMeterActorHover",
}

-- Compact gold chrome for Caw popup menus (anonymous frames marked cawDropdown)
local function skinCawDropdown(f)
    if not f then return end
    pcall(function()
        applyBackdrop(f, 0.92, 10)
        f._ichaCawDropSkinned = true
        if not f._ichaSkinHooked then
            f._ichaSkinHooked = true
            local prevShow = f:GetScript("OnShow")
            f:SetScript("OnShow", function()
                if prevShow then pcall(prevShow) end
                if enabled then
                    applyBackdrop(this, 0.92, 10)
                end
            end)
            local prevSize = f:GetScript("OnSizeChanged")
            f:SetScript("OnSizeChanged", function()
                if prevSize then pcall(prevSize) end
                if enabled then
                    applyBackdrop(this, 0.92, 10)
                end
            end)
        end
    end)
end

local function walkCawDropdowns(root, depth)
    if not root or not root.GetChildren then return end
    if depth and depth > 8 then return end
    depth = (depth or 0) + 1
    if root.cawDropdown then
        skinCawDropdown(root)
    end
    local kids = { root:GetChildren() }
    local i
    for i = 1, table.getn(kids) do
        local c = kids[i]
        if c then
            if c.cawDropdown then
                skinCawDropdown(c)
            end
            walkCawDropdowns(c, depth)
        end
    end
end

local function skinCawViewMenus(v)
    if not v then return end
    local keys = {
        "modeMenu", "segmentMenu", "reportMenu", "overflowMenu",
        "modeButton", "segmentButton", "reportButton", "overflowButton",
    }
    local i
    for i = 1, table.getn(keys) do
        local f = v[keys[i]]
        if f then
            if f.cawDropdown or string.find(keys[i], "Menu", 1, true) then
                skinCawDropdown(f)
            else
                -- selector buttons that open the menus
                pcall(function() applyBackdrop(f, 0.95, 8) end)
            end
        end
    end
    if v.frame then walkCawDropdowns(v.frame, 0) end
end

-- Throttled full Caw re-skin (Caw re-applies gray backdrop on resize)
local skinCawDPS -- forward decl for throttle
local cawReskinThrottle = CreateFrame("Frame")
cawReskinThrottle:Hide()
local cawReskinPending = false
cawReskinThrottle:SetScript("OnUpdate", function()
    this._t = (this._t or 0) + arg1
    if this._t < 0.12 then return end
    this._t = 0
    this:Hide()
    cawReskinPending = false
    if enabled and skinCawDPS then
        skinCawDPS()
    end
end)

local function scheduleCawReskin()
    if cawReskinPending then return end
    cawReskinPending = true
    cawReskinThrottle._t = 0
    cawReskinThrottle:Show()
end

local function hookCawSizeReskin(f, walkRoot)
    if not f or f._ichaCawSizeHooked then return end
    f._ichaCawSizeHooked = true
    local prevSize = f:GetScript("OnSizeChanged")
    f:SetScript("OnSizeChanged", function()
        if prevSize then pcall(prevSize) end
        if not enabled then return end
        applyBackdrop(this, 0.72, edgeSize)
        if walkRoot then
            walkCawDropdowns(this, 0)
        end
        scheduleCawReskin()
    end)
end

local function hookCawViewFrame(v)
    if not v or not v.frame then return end
    local f = v.frame
    if f._ichaCawViewHooked then
        walkCawDropdowns(f, 0)
        return
    end
    f._ichaCawViewHooked = true
    local prevSize = f:GetScript("OnSizeChanged")
    local prevShow = f:GetScript("OnShow")
    f:SetScript("OnShow", function()
        if prevShow then pcall(prevShow) end
        if enabled then
            applyBackdrop(this, 0.72, edgeSize)
            walkCawDropdowns(this, 0)
            skinCawViewMenus(v)
        end
    end)
    f:SetScript("OnSizeChanged", function()
        if prevSize then pcall(prevSize) end
        if not enabled then return end
        applyBackdrop(this, 0.72, edgeSize)
        walkCawDropdowns(this, 0)
        skinCawViewMenus(v)
        scheduleCawReskin()
    end)
end

skinCawDPS = function()
    local i
    for i = 1, table.getn(CAW_NAMES) do
        local f = getglobal(CAW_NAMES[i])
        if f then
            skinFrame(f, 0.72)
            walkCawDropdowns(f, 0)
            -- Named Caw frames: re-apply + re-walk dropdowns on resize
            hookCawSizeReskin(f, true)
        end
    end
    -- Multi-window views + menus live on CAW_DPS_METER (anonymous parents)
    local D = CAW_DPS_METER
    if type(D) == "table" then
        if D.mainView then
            skinCawViewMenus(D.mainView)
            hookCawViewFrame(D.mainView)
        end
        if D.multiWindows then
            local wi
            for wi = 1, 8 do
                local v = D.multiWindows[wi]
                if v then
                    skinCawViewMenus(v)
                    hookCawViewFrame(v)
                end
            end
        end
        -- Breakdown / compare menus
        if D.breakdownPanel then walkCawDropdowns(D.breakdownPanel, 0) end
        if D.comparePanel then walkCawDropdowns(D.comparePanel, 0) end
    end
end

local function applyAll()
    loadCfg()
    if not enabled then return end
    skinTWThreat()
    skinCawDPS()
end

function IchaUIFrameSkin_Get()
    loadCfg()
    return { enabled = enabled }
end

function IchaUIFrameSkin_Set(field, value)
    loadCfg()
    if field == "enabled" then
        enabled = value and true or false
        saveCfg()
        if enabled then
            applyAll()
        end
        return
    end
    saveCfg()
    if enabled then applyAll() end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" then
        local name = arg1
        if name == "TWThreat" or name == "TWT" then
            if enabled then skinTWThreat() end
        elseif name == "CawDPSMeter" then
            if enabled then skinCawDPS() end
            -- Menus are often created after first open — rescan a few times
            local r = CreateFrame("Frame")
            local n = 0
            r:SetScript("OnUpdate", function()
                n = n + arg1
                if n < 0.75 then return end
                n = 0
                this._passes = (this._passes or 0) + 1
                if enabled then skinCawDPS() end
                if this._passes >= 8 then
                    this:SetScript("OnUpdate", nil)
                end
            end)
        end
        return
    end
    applyAll()
    -- Late pass: TWThreat / Caw may load after us
    local t = CreateFrame("Frame")
    local e = 0
    t:SetScript("OnUpdate", function()
        e = e + arg1
        if e < 1.5 then return end
        this:SetScript("OnUpdate", nil)
        if enabled then
            skinTWThreat()
            skinCawDPS()
        end
    end)
end)

function IchaUIFrameSkin_Reload()
    applyAll()
end
