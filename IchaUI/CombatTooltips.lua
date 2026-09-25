-- IchaUI CombatTooltips: hide action-bar GameTooltip in combat unless Shift
-- Lua 5.0 / WoW 1.12 (RavenCraft)

local hookedShow = false
local hookedUpdate = false
local hiding = false
local lastBarOwner = nil

local function db()
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.combat then IchaUIDB.combat = {} end
    local c = IchaUIDB.combat
    if c.hideBarTips == nil then c.hideBarTips = false end
    return c
end

function IchaUI_CombatTooltipsGet()
    return db().hideBarTips and true or false
end

local function inCombat()
    if type(UnitAffectingCombat) ~= "function" then return false end
    local combat = false
    local function probe()
        combat = UnitAffectingCombat("player") and true or false
    end
    local ok = pcall(probe)
    if not ok then return false end
    return combat
end

local function shiftDown()
    if type(IsShiftKeyDown) ~= "function" then return false end
    if IsShiftKeyDown() then return true end
    return false
end

local function frameName(f)
    if not f then return nil end
    local n = nil
    local function grab()
        if f.GetName then n = f:GetName() end
    end
    pcall(grab)
    if type(n) == "string" and n ~= "" then return n end
    return nil
end

local function nameLooksBar(n)
    if type(n) ~= "string" or n == "" then return false end
    if string.find(n, "IchaUIBtn", 1, true) then return true end
    if string.find(n, "BActionButton", 1, true) then return true end
    if string.find(n, "BonusActionButton", 1, true) then return true end
    if string.find(n, "ActionButton", 1, true) then return true end
    if string.find(n, "Shapeshift", 1, true) then return true end
    if string.find(n, "PetAction", 1, true) then return true end
    return false
end

local function nameLooksBarParent(n)
    if type(n) ~= "string" or n == "" then return false end
    if n == "IchaUILayoutRoot" then return true end
    if string.find(n, "BActionBar", 1, true) then return true end
    if n == "BonusActionBarFrame" then return true end
    if n == "ShapeshiftBarFrame" then return true end
    if n == "PetActionBarFrame" then return true end
    if string.find(n, "^MultiBar") then return true end
    return false
end

local function isActionBarOwner(frame)
    local f = frame
    local depth = 0
    while f and depth < 12 do
        local n = frameName(f)
        if n then
            if nameLooksBar(n) then return true end
            if depth > 0 and nameLooksBarParent(n) then return true end
        end
        if f.buttonId and n and string.find(n, "IchaUIBtn", 1, true) then
            return true
        end
        local parent = nil
        local function grabP()
            if f.GetParent then parent = f:GetParent() end
        end
        pcall(grabP)
        f = parent
        depth = depth + 1
    end
    return false
end

local function tooltipOwner()
    if not GameTooltip then return nil end
    local owner = nil
    local function grab()
        if GameTooltip.GetOwner then
            owner = GameTooltip:GetOwner()
        elseif GameTooltip.owner then
            owner = GameTooltip.owner
        end
    end
    pcall(grab)
    return owner
end

local function mouseOver(f)
    if not f then return false end
    if type(MouseIsOver) ~= "function" then return false end
    local over = false
    local function grab()
        if MouseIsOver(f) then over = true end
    end
    pcall(grab)
    return over
end

local function tipShown()
    if not GameTooltip then return false end
    local shown = false
    local function grab()
        if GameTooltip.IsShown and GameTooltip:IsShown() then
            shown = true
        end
    end
    pcall(grab)
    return shown
end

local function hideTip()
    if hiding or not GameTooltip then return end
    hiding = true
    pcall(function()
        GameTooltip:Hide()
    end)
    hiding = false
end

local function showTip()
    if hiding or not GameTooltip then return end
    pcall(function()
        GameTooltip:Show()
    end)
end

local function restoreTip(owner)
    if not owner or not GameTooltip then return end
    if tipShown() then return end
    local lines = 0
    pcall(function()
        if GameTooltip.NumLines then
            lines = GameTooltip:NumLines() or 0
        end
    end)
    if lines > 0 then
        showTip()
        return
    end
    local script = nil
    pcall(function()
        if owner.GetScript then
            script = owner:GetScript("OnEnter")
        end
    end)
    if script then
        local saved = this
        this = owner
        pcall(script)
        this = saved
        return
    end
    showTip()
end

local function shouldIntercept()
    if not IchaUI_CombatTooltipsGet() then return false end
    if not inCombat() then return false end
    if shiftDown() then return false end
    return true
end

local function barOwnerNow()
    local owner = tooltipOwner()
    if owner and isActionBarOwner(owner) then
        lastBarOwner = owner
        return owner
    end
    if lastBarOwner and isActionBarOwner(lastBarOwner) then
        if mouseOver(lastBarOwner) then
            return lastBarOwner
        end
    end
    return nil
end

local function syncTip()
    if not GameTooltip then
        lastBarOwner = nil
        return
    end
    if not IchaUI_CombatTooltipsGet() then
        lastBarOwner = nil
        return
    end
    local owner = barOwnerNow()
    if not owner then
        lastBarOwner = nil
        return
    end
    if not mouseOver(owner) then
        lastBarOwner = nil
        return
    end
    lastBarOwner = owner
    if shouldIntercept() then
        if tipShown() then hideTip() end
        return
    end
    restoreTip(owner)
end

function IchaUI_CombatTooltipsSet(on)
    db().hideBarTips = on and true or false
    if not on then
        if lastBarOwner and mouseOver(lastBarOwner) then
            restoreTip(lastBarOwner)
        end
        lastBarOwner = nil
        return
    end
    syncTip()
end

local function onTipShow()
    if hiding then return end
    if not IchaUI_CombatTooltipsGet() then return end
    local owner = tooltipOwner()
    if not owner or not isActionBarOwner(owner) then
        return
    end
    lastBarOwner = owner
    if shouldIntercept() then
        hideTip()
    end
end

local function onTipUpdate()
    if hiding then return end
    if not IchaUI_CombatTooltipsGet() then return end
    if not tipShown() then return end
    local owner = tooltipOwner()
    if not owner or not isActionBarOwner(owner) then return end
    lastBarOwner = owner
    if shouldIntercept() then
        hideTip()
    end
end

local function hookTooltip()
    if not GameTooltip or not GameTooltip.SetScript then return end
    if not hookedShow then
        hookedShow = true
        local prevShow = nil
        if GameTooltip.GetScript then
            prevShow = GameTooltip:GetScript("OnShow")
        end
        GameTooltip:SetScript("OnShow", function()
            if prevShow then pcall(prevShow) end
            onTipShow()
        end)
    end
    if not hookedUpdate then
        hookedUpdate = true
        local prevUp = nil
        if GameTooltip.GetScript then
            prevUp = GameTooltip:GetScript("OnUpdate")
        end
        GameTooltip:SetScript("OnUpdate", function()
            if prevUp then pcall(prevUp) end
            onTipUpdate()
        end)
    end
end

local watch = CreateFrame("Frame", "IchaUICombatTooltips", UIParent)
watch:RegisterEvent("PLAYER_LOGIN")
watch:RegisterEvent("PLAYER_ENTERING_WORLD")
watch:RegisterEvent("PLAYER_REGEN_DISABLED")
watch:RegisterEvent("PLAYER_REGEN_ENABLED")
watch:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        hookTooltip()
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        syncTip()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if lastBarOwner and mouseOver(lastBarOwner) then
            restoreTip(lastBarOwner)
        end
    end
end)

watch:SetScript("OnUpdate", function()
    if not IchaUI_CombatTooltipsGet() then return end
    if lastBarOwner then
        syncTip()
    end
end)
