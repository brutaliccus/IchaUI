-- IchaUI CombatAssist: auto-dismount, melee StartAttack, (range tint lives in Layout)
-- Lua 5.0 / WoW 1.12 (RavenCraft)

local function db()
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.combat then IchaUIDB.combat = {} end
    local c = IchaUIDB.combat
    if c.autoDismount == nil then c.autoDismount = true end
    if c.meleeStartAttack == nil then c.meleeStartAttack = true end
    if c.oorGrey == nil then c.oorGrey = true end
    if c.totemRecall == nil then c.totemRecall = false end
    if c.totemRecallDelay == nil then c.totemRecallDelay = 5 end
    if type(c.recallIcon) ~= "table" then c.recallIcon = {} end
    if c.recallIcon.scale == nil then c.recallIcon.scale = 1 end
    if c.hideBarTips == nil then c.hideBarTips = false end
    return c
end

-- ---------- Auto-dismount ----------
local mountTip = CreateFrame("GameTooltip", "IchaUIMountTip", nil, "GameTooltipTemplate")
mountTip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function tooltipSaysMounted()
    local n = mountTip:NumLines()
    if not n or n < 1 then return false end
    local i
    for i = 1, n do
        local fs = getglobal("IchaUIMountTipTextLeft" .. i)
        local t = fs and fs:GetText()
        if t then
            local low = string.lower(t)
            if string.find(low, "increases speed", 1, true)
                or string.find(low, "mount", 1, true) and string.find(low, "speed", 1, true)
                or string.find(low, "slow and steady", 1, true) then
                return true
            end
        end
    end
    return false
end

local function cancelMountBuffs()
    -- 1.12: GetPlayerBuff(i, filter) → buffIndex or -1
    if not GetPlayerBuff or not CancelPlayerBuff then return false end
    local i
    for i = 0, 31 do
        local id = GetPlayerBuff(i, "HELPFUL")
        if not id or id < 0 then
            break
        end
        mountTip:ClearLines()
        if mountTip.SetPlayerBuff then
            mountTip:SetPlayerBuff(id)
        end
        if tooltipSaysMounted() then
            CancelPlayerBuff(id)
            return true
        end
    end
    return false
end

local function tryDismount()
    if not db().autoDismount then return end
    if UnitOnTaxi and UnitOnTaxi("player") then return end
    if IsMounted and IsMounted() then
        if Dismount then
            Dismount()
            return
        end
    end
    if Dismount then
        -- Some clients no-op when not mounted
        pcall(function() Dismount() end)
    end
    cancelMountBuffs()
end

-- Retry cast after dismount-on-error
local pendingRetry = nil -- { kind="action"|"spell"|"spellname", a=, b=, c= }

local mountErr = {
    SPELL_FAILED_NOT_MOUNTED = true,
    ERR_ATTACK_MOUNTED = true,
    ERR_NOT_WHILE_MOUNTED = true,
    ERR_TAXIPLAYERALREADYMOUNTED = true,
}

local function isMountError(msg)
    if not msg or msg == "" then return false end
    if mountErr[msg] then return true end
    local low = string.lower(tostring(msg))
    if string.find(low, "mounted", 1, true) then return true end
    if string.find(low, "while mounted", 1, true) then return true end
    if SPELL_FAILED_NOT_MOUNTED and msg == SPELL_FAILED_NOT_MOUNTED then return true end
    if ERR_ATTACK_MOUNTED and msg == ERR_ATTACK_MOUNTED then return true end
    if ERR_NOT_WHILE_MOUNTED and msg == ERR_NOT_WHILE_MOUNTED then return true end
    return false
end

-- ---------- Melee StartAttack ----------
local meleeTip = CreateFrame("GameTooltip", "IchaUIMeleeTip", nil, "GameTooltipTemplate")
meleeTip:SetOwner(WorldFrame, "ANCHOR_NONE")

local MELEE_NAMES = {
    ["attack"] = true,
    ["stormstrike"] = true,
    ["heroic strike"] = true,
    ["sinister strike"] = true,
    ["eviscerate"] = true,
    ["backstab"] = true,
    ["riposte"] = true,
    ["hemorrhage"] = true,
    ["ghostly strike"] = true,
    ["ambush"] = true,
    ["garrote"] = true,
    ["rupture"] = true,
    ["maim"] = true,
    ["shiv"] = true,
    ["mortal strike"] = true,
    ["bloodthirst"] = true,
    ["whirlwind"] = true,
    ["overpower"] = true,
    ["revenge"] = true,
    ["sunder armor"] = true,
    ["execute"] = true,
    ["hamstring"] = true,
    ["slam"] = true,
    ["raging blow"] = true,
    ["rake"] = true,
    ["shred"] = true,
    ["ferocious bite"] = true,
    ["claw"] = true,
    ["maul"] = true,
    ["mangle"] = true,
    ["rip"] = true,
    ["pounce"] = true,
    ["ravage"] = true,
    ["crusader strike"] = true,
}

local function actionSpellName(actionId)
    if not actionId then return nil end
    -- GetActionText is macro name; spell actions often nil — use tooltip
    meleeTip:ClearLines()
    meleeTip:SetAction(actionId)
    local fs = getglobal("IchaUIMeleeTipTextLeft1")
    local t = fs and fs:GetText()
    if t and t ~= "" then return t end
    if GetActionText then
        local tx = GetActionText(actionId)
        if tx and tx ~= "" then return tx end
    end
    return nil
end

local function tooltipIsMeleeRange()
    local n = meleeTip:NumLines()
    if not n then return false end
    local i
    for i = 2, n do
        local fs = getglobal("IchaUIMeleeTipTextLeft" .. i)
        local t = fs and fs:GetText()
        if t then
            local low = string.lower(t)
            if string.find(low, "melee range", 1, true) then
                return true
            end
            -- "8 yd range" etc. — not melee
        end
    end
    return false
end

local function isMeleeAction(actionId)
    if not actionId or not HasAction(actionId) then return false end
    if IsAttackAction and IsAttackAction(actionId) then return true end
    local name = actionSpellName(actionId)
    if name then
        local low = string.lower(name)
        if MELEE_NAMES[low] then return true end
    end
    meleeTip:ClearLines()
    meleeTip:SetAction(actionId)
    if tooltipIsMeleeRange() then return true end
    return false
end

local function alreadyAutoAttacking()
    local i
    for i = 1, 120 do
        if HasAction(i) and IsAttackAction and IsAttackAction(i) and IsCurrentAction and IsCurrentAction(i) then
            return true
        end
    end
    return false
end

local function ensureStartAttack()
    if not db().meleeStartAttack then return end
    if not UnitExists("target") then return end
    if UnitIsDead and UnitIsDead("target") then return end
    if UnitCanAttack and not UnitCanAttack("player", "target") then return end
    if alreadyAutoAttacking() then return end
    if AttackTarget then
        AttackTarget()
    end
end

local function beforeUseAction(actionId)
    tryDismount()
    if isMeleeAction(actionId) then
        ensureStartAttack()
    end
end

-- ---------- Hooks ----------
local _UseAction = UseAction
UseAction = function(slot, checkCursor, onSelf)
    beforeUseAction(slot)
    pendingRetry = { kind = "action", a = slot, b = checkCursor, c = onSelf }
    return _UseAction(slot, checkCursor, onSelf)
end

local _CastSpell = CastSpell
if _CastSpell then
    CastSpell = function(spellId, bookType)
        tryDismount()
        -- book casts: start attack if melee name in spellbook is hard; skip name scan
        pendingRetry = { kind = "spell", a = spellId, b = bookType }
        return _CastSpell(spellId, bookType)
    end
end

local _CastSpellByName = CastSpellByName
if _CastSpellByName then
    CastSpellByName = function(name, onSelf)
        tryDismount()
        if name then
            local low = string.lower(name)
            -- strip rank
            local bare = string.gsub(low, "%s*%(.*%)%s*$", "")
            bare = string.gsub(bare, "^%s+", "")
            bare = string.gsub(bare, "%s+$", "")
            if MELEE_NAMES[bare] or string.find(bare, "stormstrike", 1, true) then
                ensureStartAttack()
            end
        end
        pendingRetry = { kind = "spellname", a = name, b = onSelf }
        return _CastSpellByName(name, onSelf)
    end
end

-- Error-frame: dismount + one retry
local errFrame = CreateFrame("Frame", "IchaUICombatAssistErr")
errFrame:RegisterEvent("UI_ERROR_MESSAGE")
errFrame:SetScript("OnEvent", function()
    if event ~= "UI_ERROR_MESSAGE" then return end
    if not db().autoDismount then return end
    local msg = arg1
    if not isMountError(msg) then return end
    tryDismount()
    local p = pendingRetry
    if not p then return end
    pendingRetry = nil
    if p.kind == "action" and _UseAction then
        _UseAction(p.a, p.b, p.c)
    elseif p.kind == "spell" and _CastSpell then
        _CastSpell(p.a, p.b)
    elseif p.kind == "spellname" and _CastSpellByName then
        _CastSpellByName(p.a, p.b)
    end
end)

-- Clear pending shortly after cast so stale retries do not fire
local clearFrame = CreateFrame("Frame", "IchaUICombatAssistClear")
local clearAt = 0
clearFrame:SetScript("OnUpdate", function()
    if not pendingRetry then return end
    clearAt = clearAt + (arg1 or 0)
    if clearAt > 0.35 then
        clearAt = 0
        pendingRetry = nil
    end
end)

-- Expose for Layout range tint
function IchaUI_CombatDB()
    return db()
end
