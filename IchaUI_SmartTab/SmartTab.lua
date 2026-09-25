-- Smart Tab: Tab cycles the in-combat tracker by current HP.
-- Tank mode (only while Smart Tab is on): on a party/raid member first, then loose, then on-you.
-- Empty / untargetable tracker falls through to the previous Tab binding.
-- Tracker row colors (on you / loose) live here too so Options stays small.

local CMD = "ICHA_SMARTTAB"
local lastGuid = nil
local savedAction = nil
local wasAlive = {}
local tintCache = {}

local ON_R, ON_G, ON_B = 0.9, 0.15, 0.15
local LOOSE_R, LOOSE_G, LOOSE_B = 0.9, 0.9, 0.0

local function dbFlag(key)
    return IchaUIDB and IchaUIDB[key] and true or false
end

function IchaUI_SmartTabReset()
    lastGuid = nil
end

function IchaUI_SmartTabNoteUnit(guid, dead)
    if not guid or guid == "" or guid == "none" then return end
    if dead then
        if wasAlive[guid] then
            wasAlive[guid] = nil
            lastGuid = nil
        end
        return
    end
    wasAlive[guid] = true
end

local function clamp01(v, fallback)
    v = tonumber(v)
    if not v then return fallback end
    if v < 0 then v = 0 end
    if v > 1 then v = 1 end
    return v
end

local function readRGB(tbl, dr, dg, db)
    if type(tbl) ~= "table" then return dr, dg, db end
    return clamp01(tbl.r or tbl[1], dr), clamp01(tbl.g or tbl[2], dg), clamp01(tbl.b or tbl[3], db)
end

function IchaUI_TrackerColorRGB()
    local onR, onG, onB = ON_R, ON_G, ON_B
    local loR, loG, loB = LOOSE_R, LOOSE_G, LOOSE_B
    if IchaUIDB then
        onR, onG, onB = readRGB(IchaUIDB.trackerOnYou, ON_R, ON_G, ON_B)
        loR, loG, loB = readRGB(IchaUIDB.trackerLoose, LOOSE_R, LOOSE_G, LOOSE_B)
    end
    return onR, onG, onB, loR, loG, loB
end

local function wipeTint()
    local k
    for k in pairs(tintCache) do
        tintCache[k] = nil
    end
end

local function tintKey(unit)
    if UnitGUID then
        local g = nil
        local ok = pcall(function()
            g = UnitGUID(unit)
        end)
        if ok and type(g) == "string" and g ~= "" and g ~= "0x0000000000000000" then
            return g
        end
    end
    return unit
end

local function shapedColorToken(unit)
    if not unit or unit == "" or unit == "none" then return false end
    if type(unit) ~= "string" then return false end
    if string.sub(unit, 1, 6) == "IchaUI" then return false end
    if string.find(unit, "^0[xX]%x+$") then return true end
    if string.find(unit, "^nameplate%d+$") then return true end
    if unit == "target" or unit == "pettarget" then return true end
    if string.find(unit, "^party[1-4]target$") then return true end
    if string.find(unit, "^raid%d+target$") then return true end
    return false
end

function IchaUI_CombatRowColors(unit)
    if not shapedColorToken(unit) then return nil end
    if type(IchaUI_CombatTargetOfPlayer) ~= "function" then return nil end
    local state = nil
    local ok = pcall(function()
        state = IchaUI_CombatTargetOfPlayer(unit)
    end)
    if not ok then return nil end
    local key = tintKey(unit)
    if state == nil then
        if key and tintCache[key] then
            local c = tintCache[key]
            return c.r, c.g, c.b
        end
        return nil
    end
    local onR, onG, onB, loR, loG, loB = IchaUI_TrackerColorRGB()
    local r, g, b = loR, loG, loB
    if state then r, g, b = onR, onG, onB end
    if key then tintCache[key] = { r = r, g = g, b = b } end
    return r, g, b
end

local function repaintTracker()
    wipeTint()
    local slots = IchaUI_CombatSlots
    if type(slots) ~= "table" then
        if IchaUI_CombatLayout then IchaUI_CombatLayout() end
        return
    end
    local i
    local any = false
    for i = 1, 40 do
        local fr = slots[i]
        if fr and fr.update and fr.root and fr.root.IsShown and fr.root:IsShown() then
            any = true
            if not fr._holdMissing then
                fr:update()
            end
        end
    end
    if not any and IchaUI_CombatLayout then IchaUI_CombatLayout() end
end

local function saveRGB(which, r, g, b)
    if not IchaUIDB then IchaUIDB = {} end
    local pack = { r = r, g = g, b = b }
    if which == "on" then
        IchaUIDB.trackerOnYou = pack
    else
        IchaUIDB.trackerLoose = pack
    end
    repaintTracker()
end

local pickerSaved = false
local pickerStrata = "DIALOG"
local pickerLevel = 1
local pickerBtnLevel = {}

local function rememberPicker()
    if pickerSaved or not ColorPickerFrame then return end
    pickerSaved = true
    if ColorPickerFrame.GetFrameStrata then
        pickerStrata = ColorPickerFrame:GetFrameStrata() or "DIALOG"
    end
    if ColorPickerFrame.GetFrameLevel then
        pickerLevel = ColorPickerFrame:GetFrameLevel() or 1
    end
    local names = { "ColorPickerOkayButton", "ColorPickerCancelButton" }
    local i
    for i = 1, 2 do
        local f = getglobal(names[i])
        if f and f.GetFrameLevel then
            pickerBtnLevel[names[i]] = f:GetFrameLevel() or 1
        end
    end
end

local function restorePicker()
    if not pickerSaved or not ColorPickerFrame then return end
    if ColorPickerFrame.SetFrameStrata then
        ColorPickerFrame:SetFrameStrata(pickerStrata or "DIALOG")
    end
    if ColorPickerFrame.SetFrameLevel then
        ColorPickerFrame:SetFrameLevel(pickerLevel or 1)
    end
    local name, level
    for name, level in pairs(pickerBtnLevel) do
        local f = getglobal(name)
        if f and f.SetFrameLevel then
            f:SetFrameLevel(level or 1)
        end
    end
end

-- 1.12 frame levels are absolute. Raising ColorPickerFrame above its own
-- Okay/Cancel buttons paints the window over the buttons. Lift the buttons higher.
local function liftPicker()
    if not ColorPickerFrame then return end
    rememberPicker()
    local base = 40
    local panel = getglobal("IchaUIOptions")
    if panel and panel.GetFrameLevel then
        local lv = panel:GetFrameLevel()
        if lv and lv + 20 > base then base = lv + 20 end
    end
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    if ColorPickerFrame.SetFrameLevel then
        ColorPickerFrame:SetFrameLevel(base)
    end
    if ColorPickerFrame.GetChildren then
        local c1, c2, c3, c4, c5, c6, c7, c8 = ColorPickerFrame:GetChildren()
        local kids = { c1, c2, c3, c4, c5, c6, c7, c8 }
        local i
        for i = 1, 8 do
            local c = kids[i]
            if c and c.SetFrameLevel then
                c:SetFrameLevel(base + 2)
            end
        end
    end
    local names = { "ColorPickerOkayButton", "ColorPickerCancelButton" }
    local i
    for i = 1, 2 do
        local f = getglobal(names[i])
        if f then
            if f.SetFrameStrata then f:SetFrameStrata("FULLSCREEN_DIALOG") end
            if f.SetFrameLevel then f:SetFrameLevel(base + 20) end
            if f.EnableMouse then f:EnableMouse(true) end
            if f.Raise then f:Raise() end
        end
    end
end

local pickerHooked = false
local function ensurePickerHook()
    if pickerHooked or not ColorPickerFrame or not ColorPickerFrame.SetScript then return end
    pickerHooked = true
    local oldHide = ColorPickerFrame:GetScript("OnHide")
    local oldShow = ColorPickerFrame:GetScript("OnShow")
    ColorPickerFrame:SetScript("OnHide", function()
        if oldHide then oldHide() end
        restorePicker()
    end)
    ColorPickerFrame:SetScript("OnShow", function()
        if oldShow then oldShow() end
        liftPicker()
    end)
end

local function openPicker(r, g, b, apply)
    IchaUI_OpenColorPicker(r, g, b, apply, nil)
end

function IchaUI_OpenColorPicker(r, g, b, apply, onCancel)
    if not ColorPickerFrame or not ColorPickerFrame.SetColorRGB then return end
    ColorPickerFrame.func = function()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        if apply then apply(nr, ng, nb) end
    end
    ColorPickerFrame.cancelFunc = function(prev)
        if onCancel then
            onCancel(prev)
            return
        end
        if not apply then return end
        if type(prev) == "table" then
            apply(prev.r or r, prev.g or g, prev.b or b)
        else
            apply(r, g, b)
        end
    end
    ColorPickerFrame.opacityFunc = nil
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.previousValues = { r = r, g = g, b = b }
    ColorPickerFrame:SetColorRGB(r, g, b)
    ensurePickerHook()
    ColorPickerFrame:Hide()
    ColorPickerFrame:Show()
    liftPicker()
end

function IchaUI_CombatColorOptions(parent, x, x2, y)
    if not parent then return end
    local function rgbFor(which)
        local onR, onG, onB, loR, loG, loB = IchaUI_TrackerColorRGB()
        if which == "on" then return onR, onG, onB end
        return loR, loG, loB
    end
    local function makeSwatch(label, which, sx)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", sx, y)
        fs:SetText(label)
        fs:SetTextColor(0.9, 0.9, 0.9)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetWidth(28)
        btn:SetHeight(16)
        btn:SetPoint("LEFT", fs, "RIGHT", 8, 0)
        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(btn)
        tex:SetTexture(1, 1, 1, 1)
        local function paint()
            local rr, gg, bb = rgbFor(which)
            tex:SetVertexColor(rr, gg, bb)
        end
        paint()
        btn:SetScript("OnClick", function()
            local rr, gg, bb = rgbFor(which)
            openPicker(rr, gg, bb, function(nr, ng, nb)
                saveRGB(which, nr, ng, nb)
                paint()
            end)
        end)
        return paint
    end
    local paintOn = makeSwatch("On you", "on", x)
    local paintLoose = makeSwatch("Loose", "loose", x2)
    parent._trackerColorRefresh = function()
        paintOn()
        paintLoose()
    end
end

local function editFocused()
    local eb = ChatFrameEditBox
    if not eb and getglobal then eb = getglobal("ChatFrameEditBox") end
    if not eb then return false end
    if eb.HasFocus and eb:HasFocus() then return true end
    if eb.IsVisible and eb:IsVisible() then return true end
    return false
end

local function tokenOk(token)
    if not token or token == "" or token == "none" then return false end
    if type(token) ~= "string" then return false end
    if string.sub(token, 1, 6) == "IchaUI" then return false end
    if string.find(token, "^0[xX]%x+$") then return true end
    if token == "target" or token == "pettarget" then return true end
    if string.find(token, "^nameplate%d+$") then return true end
    if string.find(token, "^party[1-4]target$") then return true end
    if string.find(token, "^raid%d+target$") then return true end
    return false
end

local function normalTab()
    local action = savedAction
    if (not action or action == "" or action == CMD) and IchaUIDB then
        action = IchaUIDB.smartTabPrev
    end
    if not action or action == "" or action == CMD then
        action = "TARGETNEARESTENEMY"
    end
    if action == "TARGETPREVIOUSENEMY" then
        if TargetNearestEnemy then TargetNearestEnemy(1) end
        return
    end
    if action == "TARGETNEARESTFRIEND" then
        if TargetNearestFriend then TargetNearestFriend() end
        return
    end
    if action == "TARGETPREVIOUSFRIEND" then
        if TargetNearestFriend then TargetNearestFriend(1) end
        return
    end
    if action == "TARGETLASTTARGET" then
        if TargetLastTarget then TargetLastTarget() end
        return
    end
    if action == "TARGETLASTHOSTILE" then
        if TargetLastEnemy then TargetLastEnemy() end
        return
    end
    if TargetNearestEnemy then TargetNearestEnemy() end
end

local function readLive(token)
    if not tokenOk(token) then return nil, false end
    local hp = nil
    local ok = pcall(function()
        if not UnitExists(token) then return end
        if UnitIsDead and UnitIsDead(token) then return end
        if UnitIsGhost and UnitIsGhost(token) then return end
        local cur = UnitHealth(token)
        if not cur or cur <= 0 then return end
        hp = cur
    end)
    if not ok or not hp then return nil, false, 2 end
    local onYou = false
    if IchaUI_CombatTargetsPlayer then
        local flagged = false
        local ok2 = pcall(function()
            if IchaUI_CombatTargetsPlayer(token) then flagged = true end
        end)
        if ok2 and flagged then onYou = true end
    end
    -- Tank tier: 1 = on a party/raid member, 2 = loose / unknown, 3 = on you.
    local tier = 2
    if onYou then
        tier = 3
    elseif IchaUI_CombatGroupAggro then
        local who = nil
        pcall(function()
            who = IchaUI_CombatGroupAggro(token)
        end)
        if who == "group" then tier = 1 end
    end
    return hp, onYou, tier
end

local function doTarget(token)
    if not tokenOk(token) then return false end
    if type(TargetUnit) ~= "function" then return false end
    local ok = pcall(function()
        TargetUnit(token)
    end)
    return ok and true or false
end

local function sortByHp(list, n, lowFirst)
    local a = 1
    while a <= n do
        local b = a + 1
        while b <= n do
            local swap = false
            if lowFirst then
                if list[b].hp < list[a].hp then
                    swap = true
                elseif list[b].hp == list[a].hp and tostring(list[b].guid) < tostring(list[a].guid) then
                    swap = true
                end
            else
                if list[b].hp > list[a].hp then
                    swap = true
                elseif list[b].hp == list[a].hp and tostring(list[b].guid) < tostring(list[a].guid) then
                    swap = true
                end
            end
            if swap then
                local tmp = list[a]
                list[a] = list[b]
                list[b] = tmp
            end
            b = b + 1
        end
        a = a + 1
    end
end

local function orderForTab(list, n, tank, lowFirst)
    if not tank then
        sortByHp(list, n, lowFirst)
        return list, n
    end
    local merged = {}
    local nm = 0
    local tier, i
    for tier = 1, 3 do
        local bucket = {}
        local nb = 0
        for i = 1, n do
            if list[i].tier == tier then
                nb = nb + 1
                bucket[nb] = list[i]
            end
        end
        sortByHp(bucket, nb, lowFirst)
        for i = 1, nb do
            nm = nm + 1
            merged[nm] = bucket[i]
        end
    end
    return merged, nm
end

local function guidOf(token)
    if not tokenOk(token) then return nil end
    local g = nil
    pcall(function()
        local exists, guid = UnitExists(token)
        if exists and type(guid) == "string" and guid ~= "0x0000000000000000"
            and string.find(guid, "^0[xX]%x+$") then
            g = guid
        end
    end)
    if g then return g end
    if UnitGUID then
        pcall(function()
            local guid = UnitGUID(token)
            if type(guid) == "string" and guid ~= "0x0000000000000000"
                and string.find(guid, "^0[xX]%x+$") then
                g = guid
            end
        end)
    end
    return g
end

local function liveHostile(token)
    if not tokenOk(token) then return false end
    local good = false
    pcall(function()
        if not UnitExists(token) then return end
        if UnitIsUnit and UnitIsUnit(token, "player") then return end
        if UnitIsDead and UnitIsDead(token) then return end
        if UnitIsGhost and UnitIsGhost(token) then return end
        if UnitIsFriend and UnitIsFriend("player", token) then return end
        if UnitCanAttack and not UnitCanAttack("player", token) then return end
        local hp = UnitHealth(token)
        if not hp or hp <= 0 then return end
        good = true
    end)
    return good
end

-- Last resort: walk TargetNearestEnemy looking for a mob that is not on the player.
-- Restores the original target when nothing qualifies.
local function cycleForLoose()
    if type(TargetNearestEnemy) ~= "function" then return false, nil end
    local hadTarget = false
    pcall(function()
        if UnitExists("target") then hadTarget = true end
    end)
    local origGuid = guidOf("target")
    local firstGuid = nil
    local idleGuid = nil
    local i
    for i = 1, 12 do
        pcall(TargetNearestEnemy)
        if not liveHostile("target") then break end
        local g = guidOf("target")
        if i == 1 then
            firstGuid = g
        elseif g and firstGuid and g == firstGuid then
            break
        end
        local fighting = true
        if UnitAffectingCombat then
            fighting = false
            pcall(function()
                if UnitAffectingCombat("target") then fighting = true end
            end)
        end
        local who = nil
        if fighting and IchaUI_CombatGroupAggro then
            pcall(function()
                who = IchaUI_CombatGroupAggro("target")
            end)
        end
        if who == "group" then return true, g end
        if (who == "other" or who == "none") and g and not idleGuid then
            idleGuid = g
        end
    end
    if idleGuid and doTarget(idleGuid) then return true, idleGuid end
    if origGuid then
        doTarget(origGuid)
    elseif not hadTarget and ClearTarget then
        ClearTarget()
    end
    return false, nil
end

function IchaUI_SmartTab()
    if editFocused() then return end
    if not dbFlag("smartTab") then
        normalTab()
        return
    end
    if IchaUI_CombatRefresh then IchaUI_CombatRefresh() end
    local rows = nil
    if IchaUI_CombatTabRows then rows = IchaUI_CombatTabRows() end
    local list = {}
    local n = 0
    if type(rows) == "table" then
        local i
        for i = 1, table.getn(rows) do
            local row = rows[i]
            if row and tokenOk(row.token) and row.guid and row.guid ~= "" and row.guid ~= "none" then
                local hp, onYou, tier = readLive(row.token)
                if hp then
                    n = n + 1
                    list[n] = { guid = row.guid, token = row.token, hp = hp, onYou = onYou, tier = tier }
                end
            end
        end
    end
    local tank = dbFlag("smartTabTank")
    if tank then
        -- The tracker only builds rows with SuperWoW GUIDs. Without them, walk Tab
        -- looking for a mob on a group member.
        local anyOff = false
        local k
        for k = 1, n do
            if list[k].tier ~= 3 then anyOff = true end
        end
        local hasGuids = false
        pcall(function()
            local _, pg = UnitExists("player")
            if type(pg) == "string" and string.find(pg, "^0[xX]%x+$") then hasGuids = true end
        end)
        if not anyOff and not hasGuids then
            local found, fg = cycleForLoose()
            if found then
                lastGuid = fg
                return
            end
        end
    end
    if n < 1 then
        normalTab()
        return
    end
    local lowFirst = dbFlag("smartTabLow")
    list, n = orderForTab(list, n, tank, lowFirst)
    local pick = 1
    if lastGuid then
        local found = nil
        local i
        for i = 1, n do
            if list[i].guid == lastGuid then found = i end
        end
        if found then
            pick = found + 1
            if pick > n then pick = 1 end
        end
    end
    local step = 0
    local chosen = nil
    while step < n do
        local idx = pick + step
        while idx > n do idx = idx - n end
        if doTarget(list[idx].token) then
            chosen = list[idx]
            break
        end
        step = step + 1
    end
    if not chosen then
        normalTab()
        return
    end
    lastGuid = chosen.guid
end

function IchaUI_SmartTabApply()
    if type(SetBinding) ~= "function" or type(GetBindingAction) ~= "function" then return end
    local current = nil
    local ok = pcall(function()
        current = GetBindingAction("TAB")
    end)
    if not ok then return end
    local on = dbFlag("smartTab")
    if on then
        if current ~= CMD then
            if current and current ~= "" and current ~= CMD then
                savedAction = current
            else
                savedAction = "TARGETNEARESTENEMY"
            end
            if not IchaUIDB then IchaUIDB = {} end
            IchaUIDB.smartTabPrev = savedAction
            SetBinding("TAB", CMD)
        else
            if IchaUIDB and IchaUIDB.smartTabPrev and IchaUIDB.smartTabPrev ~= "" and IchaUIDB.smartTabPrev ~= CMD then
                savedAction = IchaUIDB.smartTabPrev
            else
                savedAction = "TARGETNEARESTENEMY"
            end
        end
        return
    end
    if current == CMD then
        local restore = savedAction
        if (not restore or restore == "" or restore == CMD) and IchaUIDB then
            restore = IchaUIDB.smartTabPrev
        end
        if not restore or restore == "" or restore == CMD then
            restore = "TARGETNEARESTENEMY"
        end
        SetBinding("TAB", restore)
    end
    savedAction = nil
    if IchaUIDB then IchaUIDB.smartTabPrev = nil end
end

local bindWatch = CreateFrame("Frame", "IchaUISmartTabFrame")
bindWatch:RegisterEvent("ADDON_LOADED")
bindWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
bindWatch:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 ~= "IchaUI" then return end
    IchaUI_SmartTabApply()
end)
