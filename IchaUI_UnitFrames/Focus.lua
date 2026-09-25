-- Focus frame: one living unit (friendly or hostile), remembered by SuperWoW GUID until it dies.
-- Looks like the target unit frame (built by IchaUI_CreateUnitFrame). Does not follow "target".
--
-- This client (1.12 + SuperWoW + Nampower + ClassicAPI):
--   FocusUnit(guid) / ClearFocus() make a real "focus" unit token when the DLL provides them.
--   SuperCleveRoidMacros then accepts /cast [@focus] Spell and /target [@focus].
--   Nampower/SuperWoW CastSpellByName(spell, unitToken) soft-casts on that token
--   (GUID or "focus") without swapping your target. Vanilla's 2nd arg is self-cast,
--   so /focuscast only passes a unit when one of those is present.
--   /target focus is hooked onto the macro /target slash. /targetfocus always works.

local focusFr = nil
local engineOwned = false
local engineTried = false
local clearing = false

local function tokenShape(unit)
    if not unit or type(unit) ~= "string" then return false end
    if unit == "" or unit == "none" then return false end
    if string.sub(unit, 1, 6) == "IchaUI" then return false end
    if string.find(unit, "^0[xX]%x+$") then return true end
    if unit == "player" or unit == "pet" or unit == "target" or unit == "pettarget"
        or unit == "mouseover" or unit == "focus" then
        return true
    end
    if string.find(unit, "^party[1-4]$") then return true end
    if string.find(unit, "^party[1-4]target$") then return true end
    if string.find(unit, "^partypet[1-4]$") then return true end
    if string.find(unit, "^raid%d+$") then return true end
    if string.find(unit, "^raid%d+target$") then return true end
    if string.find(unit, "^raidpet%d+$") then return true end
    if string.find(unit, "^nameplate%d+$") then return true end
    return false
end

local function unitLive(unit)
    if IchaUI_LEAVING then return false end
    if not tokenShape(unit) then return false end
    if type(UnitExists) ~= "function" then return false end
    local exists = false
    local ok = pcall(function()
        if UnitExists(unit) then exists = true end
    end)
    return ok and exists and true or false
end

local function guidString(g)
    if type(g) ~= "string" or g == "" then return nil end
    if not string.find(g, "^0[xX]%x+$") then return nil end
    return g
end

local function readGuid(unit)
    if not tokenShape(unit) then return nil end
    if type(IchaUI_Swing_Guid) ~= "function" then return nil end
    local g = nil
    local ok = pcall(function()
        g = IchaUI_Swing_Guid(unit)
    end)
    if not ok then return nil end
    return guidString(g)
end

local function unitOffline(unit)
    if not unitLive(unit) then return false end
    local off = false
    local ok = pcall(function()
        if not UnitIsConnected then return end
        if UnitIsConnected(unit) then return end
        if UnitIsDead and UnitIsDead(unit) then return end
        if UnitIsGhost and UnitIsGhost(unit) then return end
        local grouped = false
        if UnitInParty and UnitInParty(unit) then grouped = true end
        if UnitInRaid and UnitInRaid(unit) then grouped = true end
        if grouped then off = true end
    end)
    return ok and off
end

local function focusable(unit)
    if not unitLive(unit) then return false end
    if unitOffline(unit) then return true end
    local good = false
    local ok = pcall(function()
        if UnitIsDead and UnitIsDead(unit) then return end
        if UnitIsGhost and UnitIsGhost(unit) then return end
        good = true
    end)
    return ok and good
end

local function unitDead(unit)
    if not unitLive(unit) then return false end
    if unitOffline(unit) then return false end
    local dead = false
    local ok = pcall(function()
        if UnitIsDead and UnitIsDead(unit) then
            dead = true
            return
        end
        if UnitIsGhost and UnitIsGhost(unit) then
            dead = true
            return
        end
        if UnitHealth then
            local hp = UnitHealth(unit)
            local mx = 0
            if UnitHealthMax then mx = UnitHealthMax(unit) or 0 end
            if hp and hp <= 0 and mx > 0 then dead = true end
        end
    end)
    return ok and dead
end

local function focusDb()
    if not IchaUIDB then IchaUIDB = {} end
    if type(IchaUIDB.focus) ~= "table" then
        IchaUIDB.focus = {}
    end
    return IchaUIDB.focus
end

local function sameGuid(unit, guid)
    if not guidString(guid) then return false end
    if not unitLive(unit) then return false end
    local g = readGuid(unit)
    if g and g == guid then return true end
    return false
end

local function resolveGuid(guid)
    if IchaUI_LEAVING or not guidString(guid) then return nil end
    -- Group tokens first so a party/raid focus keeps the party-frame offline path
    -- and does not follow "target".
    if sameGuid("player", guid) then return "player" end
    if sameGuid("pet", guid) then return "pet" end
    local i
    for i = 1, 4 do
        local u = "party" .. i
        if sameGuid(u, guid) then return u end
    end
    for i = 1, 40 do
        local u = "raid" .. i
        if sameGuid(u, guid) then return u end
    end
    if unitLive(guid) then return guid end
    if sameGuid("focus", guid) then return "focus" end
    if sameGuid("target", guid) then return "target" end
    if sameGuid("pettarget", guid) then return "pettarget" end
    if sameGuid("mouseover", guid) then return "mouseover" end
    for i = 1, 4 do
        local u = "party" .. i .. "target"
        if sameGuid(u, guid) then return u end
    end
    for i = 1, 40 do
        local u = "raid" .. i .. "target"
        if sameGuid(u, guid) then return u end
    end
    for i = 1, 40 do
        local u = "nameplate" .. i
        if sameGuid(u, guid) then return u end
    end
    return nil
end

local function unitNameOf(unit)
    if not unitLive(unit) then return nil end
    if type(UnitName) ~= "function" then return nil end
    local name = nil
    local ok = pcall(function()
        name = UnitName(unit)
    end)
    if ok and type(name) == "string" and name ~= "" then return name end
    return nil
end

local function msgHasName(msg, name)
    if not msg or not name or name == "" then return false end
    local n = string.len(name)
    local m = string.len(msg)
    if n > m then return false end
    local i
    for i = 1, (m - n + 1) do
        if string.sub(msg, i, i + n - 1) == name then
            local prev = " "
            if i > 1 then prev = string.sub(msg, i - 1, i - 1) end
            local nxt = string.sub(msg, i + n, i + n)
            local prevOk = (prev == " " or prev == "")
            local nextOk = (nxt == "" or nxt == " " or nxt == "'" or nxt == "." or nxt == "!" or nxt == ",")
            if prevOk and nextOk then return true end
        end
    end
    return false
end

local function say(msg)
    if DEFAULT_CHAT_FRAME and msg then
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
end

local function trim(s)
    if not s then return "" end
    local _, _, t = string.find(s, "^%s*(.-)%s*$")
    if not t then return "" end
    return t
end

-- Nampower v2.37+ and SuperWoW accept a unit token / GUID as CastSpellByName's 2nd arg.
-- Vanilla treats any truthy 2nd arg as self-cast, so do not pass a unit without these.
local function softCastOk()
    if type(SetAutoloot) == "function" then return true end
    if type(SpellInfo) == "function" then return true end
    if type(GetNampowerVersion) == "function" then return true end
    return false
end

if type(IchaUI_CreateUnitFrame) ~= "function" then return end

focusFr = IchaUI_CreateUnitFrame("focus", "target", {
    scale = 1, width = 220, height = 48,
    portrait = true, portraitScale = 1.22, portraitRing = 1.28,
}, { portrait = true, portraitSide = "right" })

if not focusFr then return end
focusFr._focusActive = false
focusFr._holdMissing = false
focusFr._seenLive = false
if focusFr.update then focusFr:update() end

local function savePos(fr)
    if not fr or not fr.root or not fr.root.GetPoint then return end
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.uf then IchaUIDB.uf = {} end
    if type(IchaUIDB.uf.focus) ~= "table" then IchaUIDB.uf.focus = {} end
    local p, _, rp, x, y = fr.root:GetPoint(1)
    local s = IchaUIDB.uf.focus
    s.point = p
    s.relPoint = rp or p
    s.x = tonumber(x) or 0
    s.y = tonumber(y) or 0
    IchaUIDB.uf = IchaUIDB.uf
end

if focusFr.root then
    focusFr.root:RegisterForDrag("LeftButton")
    focusFr.root:SetScript("OnDragStart", function()
        if not (IsShiftKeyDown and IsShiftKeyDown()) then return end
        this:StartMoving()
    end)
    focusFr.root:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        savePos(focusFr)
    end)
end

local baseSetMove = focusFr.setMove
focusFr.setMove = function(self, on)
    if baseSetMove then baseSetMove(self, on) end
    if self.moving then
        if self.root then self.root:Show() end
    elseif self.update then
        self:update()
    end
end

local function pushEngine(guid, unit)
    engineTried = true
    engineOwned = false
    if type(FocusUnit) ~= "function" then return end
    if guidString(guid) then
        pcall(function() FocusUnit(guid) end)
    end
    if sameGuid("focus", guid) then
        engineOwned = true
        return
    end
    if tokenShape(unit) then
        pcall(function() FocusUnit(unit) end)
    end
    if sameGuid("focus", guid) then
        engineOwned = true
    end
end

local function paintFocus()
    if not focusFr or focusFr.moving then return end
    local db = focusDb()
    local guid = guidString(db.guid)
    if not guid then
        focusFr._focusActive = false
        focusFr._holdMissing = false
        focusFr._seenLive = false
        if focusFr.update then focusFr:update() end
        return
    end
    local tok = resolveGuid(guid)
    if tok and unitDead(tok) then
        IchaUI_ClearFocus(true)
        say("IchaUI focus removed (dead).")
        return
    end
    if tok then
        local n = unitNameOf(tok)
        if n then db.name = n end
        if not engineOwned and not engineTried then
            pushEngine(guid, tok)
        end
        focusFr._focusActive = true
        focusFr._holdMissing = false
        focusFr._seenLive = true
        if focusFr.unit ~= tok and focusFr.SetUnit then
            focusFr:SetUnit(tok)
        end
        if focusFr.update then focusFr:update() end
    elseif focusFr._seenLive then
        -- Nameplate dropped. update() sees _holdMissing and keeps the last paint.
        focusFr._focusActive = true
        focusFr._holdMissing = true
        if focusFr.update then focusFr:update() end
    else
        focusFr._focusActive = false
        focusFr._holdMissing = false
        if focusFr.update then focusFr:update() end
    end
end

function IchaUI_ClearFocus(quiet)
    if clearing then return end
    clearing = true
    local db = focusDb()
    local had = guidString(db.guid) and true or false
    db.guid = nil
    db.name = nil
    engineOwned = false
    engineTried = false
    if focusFr then
        focusFr._seenLive = false
        focusFr._holdMissing = false
        focusFr._focusActive = false
        if focusFr.update then focusFr:update() end
    end
    if type(ClearFocus) == "function" then
        pcall(function() ClearFocus() end)
    end
    clearing = false
    if had and not quiet then
        say("IchaUI focus cleared.")
    end
end

function IchaUI_SetFocusUnit(unit)
    if not unit or unit == "" then unit = "target" end
    if not tokenShape(unit) then return end
    if not focusable(unit) then return end
    local guid = readGuid(unit)
    if not guid then return end
    local db = focusDb()
    local name = unitNameOf(unit)
    db.guid = guid
    if name then db.name = name end
    if focusFr then
        focusFr._holdMissing = false
    end
    engineTried = false
    pushEngine(guid, unit)
    paintFocus()
    if db.name then
        say("IchaUI focus: " .. db.name)
    else
        say("IchaUI focus set.")
    end
end

function IchaUI_FocusUnit()
    local db = focusDb()
    local guid = guidString(db.guid)
    if not guid then return nil end
    if sameGuid("focus", guid) then return "focus" end
    return resolveGuid(guid)
end

function IchaUI_FocusRefresh()
    paintFocus()
end

function IchaUI_TargetFocus()
    local tok = IchaUI_FocusUnit()
    if not tok then return end
    if type(TargetUnit) ~= "function" then return end
    pcall(function() TargetUnit(tok) end)
end

local function castAtFocus(spell)
    spell = trim(spell)
    if spell == "" then return end
    local tok = IchaUI_FocusUnit()
    if not tok then return end
    if not softCastOk() or type(CastSpellByName) ~= "function" then
        say("IchaUI: /focuscast needs SuperWoW or Nampower (unit-token cast).")
        return
    end
    CastSpellByName(spell, tok)
    if SpellIsTargeting and SpellIsTargeting() and type(SpellTargetUnit) == "function" then
        SpellTargetUnit(tok)
    end
end

local castBtn = CreateFrame("Button", "IchaUIFocusCastBtn", UIParent)
castBtn:SetWidth(1)
castBtn:SetHeight(1)
castBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -2, 2)
castBtn:EnableMouse(true)
castBtn:RegisterForClicks("LeftButtonUp")
castBtn:SetAlpha(0)
castBtn:SetScript("OnClick", function()
    castAtFocus(this.spell)
end)
castBtn:Hide()

local function registerSlash()
    SLASH_ICHAUISETFOCUS1 = "/setfocus"
    SlashCmdList["ICHAUISETFOCUS"] = function()
        IchaUI_SetFocusUnit("target")
    end
    SLASH_ICHAUICLEARFOCUS1 = "/clearfocus"
    SlashCmdList["ICHAUICLEARFOCUS"] = function()
        IchaUI_ClearFocus()
    end
    SLASH_ICHAUIFOCUSCAST1 = "/focuscast"
    SlashCmdList["ICHAUIFOCUSCAST"] = function(msg)
        -- CastSpell runs in this button's OnClick (hardware). A macro's /focuscast
        -- is already inside the action-button click; Click() keeps CastSpell there.
        castBtn.spell = trim(msg)
        castBtn:Show()
        castBtn:Click()
        castBtn:Hide()
    end
    SLASH_ICHAUITARGETFOCUS1 = "/targetfocus"
    SlashCmdList["ICHAUITARGETFOCUS"] = function()
        IchaUI_TargetFocus()
    end
end

local targetHooked = false
local function hookTargetSlash()
    if targetHooked then return end
    if not SlashCmdList or type(SlashCmdList.TARGET) ~= "function" then return end
    targetHooked = true
    local prev = SlashCmdList.TARGET
    SlashCmdList.TARGET = function(msg)
        local low = string.lower(trim(msg or ""))
        if low == "focus" then
            IchaUI_TargetFocus()
            return
        end
        if prev then prev(msg) end
    end
end

registerSlash()

local pulse = CreateFrame("Frame", "IchaUIFocusPulse")
pulse:RegisterEvent("PLAYER_LOGIN")
pulse:RegisterEvent("PLAYER_ENTERING_WORLD")
pulse:RegisterEvent("UNIT_HEALTH")
pulse:RegisterEvent("UNIT_MAXHEALTH")
pulse:RegisterEvent("UNIT_MANA")
pulse:RegisterEvent("UNIT_MAXMANA")
pulse:RegisterEvent("UNIT_ENERGY")
pulse:RegisterEvent("UNIT_RAGE")
pulse:RegisterEvent("UNIT_DISPLAYPOWER")
pulse:RegisterEvent("UNIT_AURA")
pulse:RegisterEvent("UNIT_PORTRAIT_UPDATE")
pulse:RegisterEvent("UNIT_NAME_UPDATE")
pulse:RegisterEvent("UNIT_LEVEL")
pulse:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")
pulse:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_DEATH")
pcall(function() pulse:RegisterEvent("CHAT_MSG_COMBAT_FRIENDLY_DEATH") end)
pcall(function() pulse:RegisterEvent("CHAT_MSG_COMBAT_FRIENDLYPLAYER_DEATH") end)
pcall(function() pulse:RegisterEvent("CHAT_MSG_COMBAT_PET_DEATH") end)
pcall(function() pulse:RegisterEvent("PLAYER_FOCUS_CHANGED") end)
pulse.t = 0
pulse:SetScript("OnEvent", function()
    if IchaUI_LEAVING and event ~= "PLAYER_ENTERING_WORLD" then return end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        registerSlash()
        hookTargetSlash()
        paintFocus()
        return
    end
    if event == "PLAYER_FOCUS_CHANGED" then
        if clearing then return end
        paintFocus()
        return
    end
    if event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" or event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_DEATH"
        or event == "CHAT_MSG_COMBAT_FRIENDLY_DEATH" or event == "CHAT_MSG_COMBAT_FRIENDLYPLAYER_DEATH"
        or event == "CHAT_MSG_COMBAT_PET_DEATH" then
        local db = focusDb()
        local guid = guidString(db.guid)
        if not guid or not db.name then return end
        if not msgHasName(arg1, db.name) then return end
        local tok = resolveGuid(guid)
        if tok and not unitDead(tok) then return end
        IchaUI_ClearFocus(true)
        say("IchaUI focus removed (dead).")
        return
    end
    local db = focusDb()
    local guid = guidString(db.guid)
    if not guid or not focusFr or not focusFr._focusActive then return end
    local who = arg1
    if type(who) ~= "string" then
        paintFocus()
        return
    end
    if who == guid or who == focusFr.unit or who == "focus" then
        paintFocus()
    end
end)
pulse:SetScript("OnUpdate", function()
    if IchaUI_LEAVING then return end
    if not focusFr or not focusFr._focusActive or focusFr.moving then return end
    local dt = arg1 or 0
    this.t = (this.t or 0) + dt
    if not focusFr._holdMissing then
        if focusFr.updateCast then focusFr:updateCast() end
        if IchaUI_Swing_Update then IchaUI_Swing_Update(focusFr) end
    end
    if this.t < 0.05 then return end
    this.t = 0
    paintFocus()
end)

paintFocus()
