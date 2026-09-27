--[[
  IchaUI Stance — form detector, Hero 1 virtual pages, and action-bar kits.

  Hero 1 keeps one SavedVariables page per stance (heroPages). The live
  page is IchaUIDB.heroSetup. Drawers never follow stance.

  Action bars do not page with slot offsets. Each bar+stance stores a kit
  (a snapshot of the spells, items, and macros on that bar). On stance
  change the outgoing kit is saved and the incoming kit is placed onto the
  bar's own action slots with PickupSpell / PickupMacro / PickupContainerItem
  / PlaceAction. After that, buttons use those slots directly, so cooldown
  and range stay on the 1.12 action APIs. IchaUI_GetPagedID is identity.

  Old actionMaps offsets are ignored. The current form and page 0 are seeded
  from the live buttons; every other page starts empty.

  Testing: /icha stance | /icha stance sim <id> | /icha stance sim clear
]]

local MAX_BUTTONS = 120
local listeners = {}
local detectedState = 0
local classToken = nil
local started = false
local booted = true
local seenActions = false
local pendingState = nil
local swapping = false
local bootTries = 0
local evt

-- Buff names (Bongos localization defaults)
local BUFF_PROWL = "Prowl"
local BUFF_SHADOWFORM = "Shadowform"

------------------------------------------------------------------------
-- Stance name tables (copy BONGOS_STANCE_LIST)
------------------------------------------------------------------------
local STANCE_NAMES = {
    DRUID = { [0] = "Caster", [1] = "Bear", [2] = "Aquatic", [3] = "Cat",
              [4] = "Travel", [5] = "Moonkin", [6] = "Prowl" },
    ROGUE = { [0] = "Unstealth", [1] = "Stealth" },
    WARRIOR = { [1] = "Battle Stance", [2] = "Defensive Stance", [3] = "Berserker Stance" },
    PRIEST = { [0] = "Healer", [1] = "Shadowform" },
}

-- Stance ids that get a hero virtual page (incl 0)
local function classStanceIds(class)
    if class == "DRUID" then
        return { 0, 1, 2, 3, 4, 5, 6 }
    elseif class == "ROGUE" then
        return { 0, 1 }
    elseif class == "WARRIOR" then
        return { 0, 1, 2, 3 }
    elseif class == "PRIEST" then
        return { 0, 1 }
    end
    -- Non-form classes (SHAMAN etc.): virtual test pages so /icha stance sim N
    -- can swap Hero 1 kits and exercise action-bar paging.
    return { 0, 1, 2, 3, 4, 5, 6 }
end

------------------------------------------------------------------------
-- Deep copy (Lua 5.0)
------------------------------------------------------------------------
local function deepCopy(src)
    if type(src) ~= "table" then return src end
    local dst = {}
    local k, v
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = deepCopy(v)
        else
            dst[k] = v
        end
    end
    return dst
end

------------------------------------------------------------------------
-- DB
------------------------------------------------------------------------
local function db()
    if type(IchaUIDB) ~= "table" then IchaUIDB = {} end
    local s = IchaUIDB.stance
    if type(s) ~= "table" then
        s = {}
        IchaUIDB.stance = s
    end
    if s.enabled == nil then s.enabled = true end
    if s.state == nil then s.state = 0 end
    -- sim: nil or number
    if s.heroPrimaryFollows == nil then s.heroPrimaryFollows = true end
    -- Drawers must NEVER follow stances (Joseph). Force off always.
    s.drawerFollowHero = false
    -- actionMaps (integer offsets) are retired. Kept so old saves still load.
    if type(s.actionMaps) ~= "table" then s.actionMaps = {} end
    if type(s.actionKits) ~= "table" then s.actionKits = {} end
    if type(s.heroPages) ~= "table" then s.heroPages = {} end
    return s
end

-- Live hero dimensions (never hardcode 4x2 — preserves user button count)
local function heroTemplate()
    local s = db()
    local live = nil
    local page0 = nil
    if type(IchaUIDB) == "table" and type(IchaUIDB.heroSetup) == "table" then
        live = IchaUIDB.heroSetup
    end
    if type(s.heroPages) == "table" and type(s.heroPages[0]) == "table" then
        page0 = s.heroPages[0]
    end
    local function area(p)
        if type(p) ~= "table" then return 0 end
        return (tonumber(p.cols) or 0) * (tonumber(p.rows) or 0)
    end
    -- Prefer the larger grid so a leftover empty 4x2 page cannot shrink others
    local la, pa = area(live), area(page0)
    if la >= pa and la > 0 then return live end
    if pa > 0 then return page0 end
    return live or page0
end

local function emptyHeroPage()
    local t = heroTemplate()
    local page = { slots = {} }
    if type(t) == "table" then
        page.cols = tonumber(t.cols) or 4
        page.rows = tonumber(t.rows) or 2
        page.shape = t.shape
        page.layout = t.layout
        page.spread = t.spread
        page.arc = t.arc
        page.rot = t.rot
        if t.slotCount ~= nil then page.slotCount = t.slotCount end
    else
        page.cols = 4
        page.rows = 2
    end
    return page
end

-- Sync cols/rows/shape fields from template; never wipe slots
local function syncPageDims(page)
    if type(page) ~= "table" then return end
    if type(page.slots) ~= "table" then page.slots = {} end
    local t = heroTemplate()
    if type(t) ~= "table" then
        if not page.cols then page.cols = 4 end
        if not page.rows then page.rows = 2 end
        return
    end
    local tc = tonumber(t.cols) or 4
    local tr = tonumber(t.rows) or 2
    if (not page.cols) or (not page.rows) or (tonumber(page.cols) ~= tc) or (tonumber(page.rows) ~= tr) then
        page.cols = tc
        page.rows = tr
    end
    if page.shape == nil then page.shape = t.shape end
    if page.layout == nil then page.layout = t.layout end
    if page.spread == nil then page.spread = t.spread end
    if page.arc == nil then page.arc = t.arc end
    if page.rot == nil then page.rot = t.rot end
    if page.slotCount == nil and t.slotCount ~= nil then page.slotCount = t.slotCount end
end

------------------------------------------------------------------------
-- Buff scan (Bongos_IsBuffActive if present; else tooltip scan)
------------------------------------------------------------------------
local tipFrame = nil
local function ensureTip()
    if tipFrame then return tipFrame end
    tipFrame = CreateFrame("GameTooltip", "IchaUIStanceTip", UIParent, "GameTooltipTemplate")
    tipFrame:SetOwner(UIParent, "ANCHOR_NONE")
    return tipFrame
end

local function isBuffActive(buffname)
    if not buffname or buffname == "" then return false end
    if Bongos_IsBuffActive then
        return Bongos_IsBuffActive(buffname) and true or false
    end
    local tip = ensureTip()
    local i = 1
    while true do
        if not UnitBuff or not UnitBuff("player", i) then break end
        tip:ClearLines()
        tip:SetUnitBuff("player", i)
        local fs = getglobal("IchaUIStanceTipTextLeft1")
        local text = fs and fs:GetText()
        if text and string.find(text, buffname) then return true end
        i = i + 1
        if i > 32 then break end
    end
    return false
end

local function playerClass()
    if classToken then return classToken end
    if UnitClass then
        local _, token = UnitClass("player")
        if type(token) == "string" and token ~= "" then
            classToken = string.upper(token)
            return classToken
        end
    end
    return nil
end

------------------------------------------------------------------------
-- Hero virtual pages
------------------------------------------------------------------------
local function ensureHeroPage(id)
    local s = db()
    id = tonumber(id) or 0
    if not s.heroPages[id] then
        s.heroPages[id] = emptyHeroPage()
    else
        syncPageDims(s.heroPages[id])
    end
    return s.heroPages[id]
end

local function ensureHeroPages()
    local s = db()
    local class = playerClass()
    -- Still seed even if class unknown yet (use virtual 0-6)
    local ids = classStanceIds(class or "")
    local i
    local firstSeed = false
    -- Seed page 0 from current heroSetup once
    if not s.heroPages[0] then
        firstSeed = true
        if type(IchaUIDB) == "table" and type(IchaUIDB.heroSetup) == "table" then
            s.heroPages[0] = deepCopy(IchaUIDB.heroSetup)
            if type(s.heroPages[0].slots) ~= "table" then s.heroPages[0].slots = {} end
            syncPageDims(s.heroPages[0])
        else
            s.heroPages[0] = emptyHeroPage()
        end
    else
        syncPageDims(s.heroPages[0])
    end
    for i = 1, table.getn(ids) do
        local id = ids[i]
        if id ~= 0 then
            ensureHeroPage(id)
        end
    end
    -- Also ensure current sim / state page (any id) so sim 1..N always has a page
    local cur = tonumber(s.sim)
    if cur == nil then cur = tonumber(s.state) or detectedState or 0 end
    ensureHeroPage(cur)
    -- First install: class often already in a non-0 stance. Copy legacy heroSetup
    -- into the current page once so Hero 1 does not go blank on first bind.
    if firstSeed and not s._heroMigrated then
        s._heroMigrated = true
        if cur ~= 0 and s.heroPages[cur] and type(IchaUIDB.heroSetup) == "table" then
            s.heroPages[cur] = deepCopy(IchaUIDB.heroSetup)
            if type(s.heroPages[cur].slots) ~= "table" then s.heroPages[cur].slots = {} end
            syncPageDims(s.heroPages[cur])
        end
    end
end

local function bindHeroLivePage()
    local s = db()
    if not s.heroPrimaryFollows then return end
    ensureHeroPages()
    local id = IchaUI_StanceState()
    local page = ensureHeroPage(id)
    -- Same table reference so Hero setup edits the active stance page
    IchaUIDB.heroSetup = page
    if IchaUI_HeroReloadFromDB then
        IchaUI_HeroReloadFromDB()
    end
    -- Place the page's spells/items/macros onto the hero slots (icons, cooldown, range).
    if IchaUI_HeroSyncIcons then
        IchaUI_HeroSyncIcons()
    end
    -- Force immediate hero chrome rebuild (pending flag alone can lag a tick)
    if IchaUI_RefreshHeroBar then
        IchaUI_RefreshHeroBar(1)
    elseif IchaUI_RequestLayout then
        IchaUI_RequestLayout()
    end
end

function IchaUI_HeroLivePage()
    local s = db()
    ensureHeroPages()
    local id = 0
    if s.heroPrimaryFollows then
        id = IchaUI_StanceState()
    end
    return ensureHeroPage(id)
end

function IchaUI_HeroEnsureStancePages()
    ensureHeroPages()
    return db().heroPages
end

------------------------------------------------------------------------
-- Public state APIs
------------------------------------------------------------------------
function IchaUI_StanceState()
    local s = db()
    if not s.enabled then return 0 end
    if s.sim ~= nil then return tonumber(s.sim) or 0 end
    return tonumber(s.state) or 0
end

function IchaUI_StanceName(id)
    id = tonumber(id)
    if id == nil then return "Unknown" end
    local class = playerClass()
    if class and STANCE_NAMES[class] and STANCE_NAMES[class][id] then
        return STANCE_NAMES[class][id]
    end
    if id == 0 then return "Default" end
    return "Stance " .. tostring(id)
end

function IchaUI_StanceSetSim(id)
    local s = db()
    if id == nil then
        s.sim = nil
    else
        s.sim = tonumber(id) or 0
        ensureHeroPage(s.sim)
    end
    IchaUI_StanceFire(IchaUI_StanceState())
end

-- Retired in 3.5.0. Action bars swap kits; they do not add a slot offset.
function IchaUI_StanceOffset(barIndex)
    return 0
end

function IchaUI_StanceOnChange(callback)
    if type(callback) == "function" then
        table.insert(listeners, callback)
    end
end

function IchaUI_StanceSetEnabled(on)
    db().enabled = on and true or false
    IchaUI_StanceFire(IchaUI_StanceState())
end

-- Retired in 3.5.0. Offsets are not stored or applied. Use action kits.
function IchaUI_StanceSetMap(barIndex, stanceId, offset)
end

function IchaUI_StanceClassIds()
    return classStanceIds(playerClass() or "")
end

------------------------------------------------------------------------
-- Bar slot ranges (same split Layout uses). Kits place onto these ids.
------------------------------------------------------------------------
local function barStartFallback(barId)
    if BActionBar and BActionBar.GetStart then
        return BActionBar.GetStart(barId)
    end
    local n = (BActionSets and BActionSets.g and BActionSets.g.numActionBars) or 10
    return math.floor(MAX_BUTTONS / n) * (barId - 1) + 1
end

local function barSizeFallback(barId)
    if BActionBar and BActionBar.GetSize then
        return BActionBar.GetSize(barId)
    end
    if BActionSets and BActionSets[barId] and BActionSets[barId].size then
        return BActionSets[barId].size
    end
    local n = (BActionSets and BActionSets.g and BActionSets.g.numActionBars) or 10
    return math.floor(MAX_BUTTONS / n)
end

-- Identity. Stance kits place actions onto the button's own slot.
-- barId is accepted so older callers keep working.
function IchaUI_GetPagedID(buttonId, barId)
    return tonumber(buttonId) or 1
end

------------------------------------------------------------------------
-- Action-bar kits (snapshot ↔ PlaceAction). Swap cost is stance change only.
------------------------------------------------------------------------
local function barCount()
    if IchaUI_ActionBarCount then
        local n = IchaUI_ActionBarCount()
        if n and n > 0 then return n end
    end
    return 6
end

local function barSlotIds(barId)
    barId = tonumber(barId) or 1
    local owned, base
    if barId <= 6 then
        owned = barSizeFallback(barId)
        base = barStartFallback(barId)
    else
        local list = IchaUIDB and IchaUIDB.actionExtras
        local rec = list and list[barId - 6]
        if type(rec) ~= "table" then return {} end
        owned = tonumber(rec.slotCount) or 0
        base = tonumber(rec.slotBase) or 0
    end
    owned = tonumber(owned) or 0
    base = tonumber(base) or 0
    local ids = {}
    local i
    for i = 0, owned - 1 do
        local id = base + i
        if id >= 1 and id <= MAX_BUTTONS then
            table.insert(ids, id)
        end
    end
    return ids
end

local function anyBarAction()
    local b, i
    for b = 1, barCount() do
        local ids = barSlotIds(b)
        for i = 1, table.getn(ids) do
            if HasAction and HasAction(ids[i]) then return true end
        end
    end
    return false
end

local function cursorBusy()
    if CursorHasSpell and CursorHasSpell() then return true end
    if CursorHasItem and CursorHasItem() then return true end
    if CursorHasMacro and CursorHasMacro() then return true end
    if type(GetCursorInfo) == "function" then
        local ok, kind = pcall(GetCursorInfo)
        if ok and kind then return true end
    end
    return false
end

local function normText(text)
    if not text then return "" end
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function normRank(rank)
    rank = normText(rank)
    if rank == "" then return nil end
    local _, _, n = string.find(rank, "^[Rr]ank%s+(%d+)$")
    if n then return "Rank " .. tostring(tonumber(n) or n) end
    return rank
end

local function findSpell(spellName, rankWant, texture)
    if not spellName or spellName == "" or not GetSpellName then return nil end
    local book = BOOKTYPE_SPELL or "spell"
    local want = string.lower(spellName)
    rankWant = normRank(rankWant)
    local best, ranked, texHit
    local i = 1
    while i <= 500 do
        local name, rank = GetSpellName(i, book)
        if not name then break end
        if string.lower(name) == want then
            local tex = nil
            if GetSpellTexture then tex = GetSpellTexture(i, book) end
            local rec = { name = name, rank = normRank(rank), index = i, texture = tex }
            best = rec
            if rankWant and rec.rank == rankWant then ranked = rec end
            if texture and tex and tex == texture then
                if (not texHit) or (rankWant and rec.rank == rankWant) then
                    texHit = rec
                end
            end
        end
        i = i + 1
    end
    if rankWant and ranked then return ranked end
    if rankWant then return nil end
    if texHit then return texHit end
    return best
end

local function findMacro(name)
    if not name or name == "" or not GetMacroInfo then return nil end
    local want = string.lower(name)
    local nAcc, nChar = 18, 18
    if GetNumMacros then
        local a, c = GetNumMacros()
        a = tonumber(a) or 0
        c = tonumber(c) or 0
        if a < 0 then a = 0 end
        if a > 18 then a = 18 end
        if c < 0 then c = 0 end
        if c > 18 then c = 18 end
        nAcc, nChar = a, c
    end
    local i
    for i = 1, nAcc do
        local mname = GetMacroInfo(i)
        if mname and string.lower(mname) == want then return i end
    end
    for i = 1, nChar do
        local mname = GetMacroInfo(18 + i)
        if mname and string.lower(mname) == want then return 18 + i end
    end
    for i = 1, 36 do
        local mname = GetMacroInfo(i)
        if mname and string.lower(mname) == want then return i end
    end
    return nil
end

local function findItem(itemId, itemName, texture)
    local wantId = nil
    if itemId and tostring(itemId) ~= "" then wantId = tostring(itemId) end
    local wantName = nil
    if itemName and itemName ~= "" then wantName = string.lower(itemName) end
    local function consider(link, tex, bag, slot, inv)
        if not link then return nil end
        local _, _, id = string.find(link, "item:(%d+)")
        if not id then return nil end
        local iname = nil
        if GetItemInfo then iname = GetItemInfo(tonumber(id) or id) end
        local idOk = wantId and id == wantId
        local nameOk = wantName and iname and string.lower(iname) == wantName
        local texOk = texture and tex and tex == texture
        if idOk or nameOk or (texOk and not wantId and not wantName) then
            return bag, slot, tex or texture, tonumber(id), iname or itemName, inv
        end
        return nil
    end
    if GetContainerNumSlots and GetContainerItemLink then
        local bag
        for bag = 0, 4 do
            local n = GetContainerNumSlots(bag) or 0
            local slot
            for slot = 1, n do
                local link = GetContainerItemLink(bag, slot)
                local tex = nil
                if link and GetContainerItemInfo then
                    tex = GetContainerItemInfo(bag, slot)
                end
                local b, s, t, id, nm, inv = consider(link, tex, bag, slot, nil)
                if b or id then return b, s, t, id, nm, inv end
            end
        end
    end
    if GetInventoryItemLink then
        local inv
        for inv = 0, 19 do
            local link = GetInventoryItemLink("player", inv)
            local tex = nil
            if link and GetInventoryItemTexture then
                tex = GetInventoryItemTexture("player", inv)
            end
            local b, s, t, id, nm = consider(link, tex, nil, nil, inv)
            if id then return b, s, t, id, nm, inv end
        end
    end
    return nil, nil, nil, nil, nil, nil
end

local function tooltipNameRank(actionId)
    local tip = ensureTip()
    if not tip or not tip.SetAction then return nil, nil end
    tip:ClearLines()
    local ok = pcall(function() tip:SetAction(actionId) end)
    if not ok then return nil, nil end
    local left = getglobal("IchaUIStanceTipTextLeft1")
    local right = getglobal("IchaUIStanceTipTextRight1")
    local name = left and left.GetText and left:GetText() or nil
    local rank = right and right.GetText and right:GetText() or nil
    name = normText(name)
    rank = normRank(rank)
    if name == "" then name = nil end
    return name, rank
end

local function actionInfo(actionId)
    if type(GetActionInfo) ~= "function" then return nil end
    local ok, t, id, sub = pcall(GetActionInfo, actionId)
    if not ok then return nil end
    return t, id, sub
end

local function isEmptySnap(snap)
    if type(snap) ~= "table" then return true end
    if snap.empty == 1 then return true end
    if not snap.kind or snap.kind == "" then return true end
    return false
end

local function slotKey(snap)
    if isEmptySnap(snap) then return "0" end
    local name = string.lower(snap.spell or "")
    if snap.kind == "item" then
        return "i:" .. tostring(snap.itemId or "") .. ":" .. name
    end
    if snap.kind == "macro" then
        return "m:" .. name
    end
    return "s:" .. name .. ":" .. string.lower(normRank(snap.rank) or "")
end

local function captureSlot(actionId)
    if not HasAction or not HasAction(actionId) then
        return { empty = 1 }
    end
    local tex = nil
    if GetActionTexture then tex = GetActionTexture(actionId) end
    local macro = nil
    if GetActionText then macro = GetActionText(actionId) end
    macro = normText(macro)
    if macro ~= "" and findMacro(macro) then
        return { kind = "macro", spell = macro, texture = tex }
    end
    local infoType, infoId = actionInfo(actionId)
    local name, rank = tooltipNameRank(actionId)
    if infoType == "macro" then
        local mname = macro
        if type(infoId) == "number" and GetMacroInfo then
            mname = GetMacroInfo(infoId) or mname
        elseif type(infoId) == "string" and infoId ~= "" then
            mname = infoId
        end
        mname = normText(mname)
        if mname ~= "" then
            return { kind = "macro", spell = mname, texture = tex }
        end
    end
    if infoType == "item" then
        local itemId = nil
        if type(infoId) == "number" then
            itemId = infoId
        elseif type(infoId) == "string" then
            local _, _, n = string.find(infoId, "item:(%d+)")
            itemId = tonumber(n or infoId)
        end
        local _, _, itex, iid, iname = findItem(itemId, name, tex)
        return {
            kind = "item",
            itemId = iid or itemId,
            spell = iname or name,
            texture = itex or tex,
        }
    end
    -- GetActionInfo (SuperWoW/ClassicAPI) returns a spell ID, not a book slot.
    -- GetSpellName only accepts book slots — calling it with a spell ID errors.
    if infoType == "spell" and type(infoId) == "number" then
        local sname, srank = nil, nil
        if type(SpellInfo) == "function" then
            local ok, a, b = pcall(SpellInfo, infoId)
            if ok and type(a) == "string" and a ~= "" then
                sname, srank = a, b
            end
        end
        if sname then
            name = sname
            rank = normRank(srank) or rank
        end
        -- else keep tooltip name/rank from tooltipNameRank above
    elseif infoType == "spell" and type(infoId) == "string" and infoId ~= "" then
        name = infoId
    end
    local spellHit = findSpell(name, rank, tex)
    if spellHit and spellHit.index then
        local texOk = (not tex) or (not spellHit.texture) or (spellHit.texture == tex)
        if texOk or (rank and spellHit.rank == normRank(rank)) then
            return {
                kind = "spell",
                spell = spellHit.name,
                rank = spellHit.rank,
                texture = spellHit.texture or tex,
            }
        end
    end
    local _, _, itex, iid, iname = findItem(nil, name, tex)
    if iid or (iname and iname ~= "") then
        if not spellHit then
            return { kind = "item", itemId = iid, spell = iname or name, texture = itex or tex }
        end
    end
    if name and name ~= "" then
        return { kind = "spell", spell = name, rank = rank, texture = tex }
    end
    return { empty = 1 }
end

local function captureBar(barId)
    local ids = barSlotIds(barId)
    local kit = { slots = {} }
    local i
    for i = 1, table.getn(ids) do
        kit.slots[i] = captureSlot(ids[i])
    end
    return kit
end

local function emptyBarKit(barId)
    local ids = barSlotIds(barId)
    local kit = { slots = {} }
    local i
    for i = 1, table.getn(ids) do
        kit.slots[i] = { empty = 1 }
    end
    return kit
end

local function clearSlot(actionId)
    if not HasAction or not HasAction(actionId) then return end
    if not PickupAction then return end
    if ClearCursor then ClearCursor() end
    PickupAction(actionId)
    if ClearCursor then ClearCursor() end
end

local function placeSnap(actionId, snap)
    if isEmptySnap(snap) then
        clearSlot(actionId)
        return
    end
    if slotKey(captureSlot(actionId)) == slotKey(snap) then return end
    local placed = false
    if snap.kind == "macro" then
        local idx = findMacro(snap.spell)
        if idx and PickupMacro and PlaceAction then
            if ClearCursor then ClearCursor() end
            PickupMacro(idx)
            PlaceAction(actionId)
            if ClearCursor then ClearCursor() end
            placed = true
        end
    elseif snap.kind == "item" then
        local bag, slot, _, _, _, inv = findItem(snap.itemId, snap.spell, snap.texture)
        if bag ~= nil and slot and PickupContainerItem and PlaceAction then
            if ClearCursor then ClearCursor() end
            PickupContainerItem(bag, slot)
            PlaceAction(actionId)
            if ClearCursor then ClearCursor() end
            placed = true
        elseif inv ~= nil and PickupInventoryItem and PlaceAction then
            if ClearCursor then ClearCursor() end
            PickupInventoryItem(inv)
            PlaceAction(actionId)
            if CursorHasItem and CursorHasItem() then
                PickupInventoryItem(inv)
            end
            if ClearCursor then ClearCursor() end
            placed = true
        end
    else
        local found = findSpell(snap.spell, snap.rank, snap.texture)
        if found and found.index and PickupSpell and PlaceAction then
            if ClearCursor then ClearCursor() end
            PickupSpell(found.index, BOOKTYPE_SPELL or "spell")
            PlaceAction(actionId)
            if ClearCursor then ClearCursor() end
            placed = true
        end
    end
    if not placed then
        clearSlot(actionId)
    end
end

local function withQuiet(fn)
    local old = PlaySound
    if old then PlaySound = function() end end
    local ok, err = pcall(fn)
    if old then PlaySound = old end
    if not ok then error(err, 0) end
end

local function snapshotBarKits(stanceId)
    if not anyBarAction() and not seenActions then return end
    if anyBarAction() then seenActions = true end
    stanceId = tonumber(stanceId) or 0
    local s = db()
    local b
    for b = 1, barCount() do
        if type(s.actionKits[b]) ~= "table" then s.actionKits[b] = {} end
        s.actionKits[b][stanceId] = captureBar(b)
    end
end

local function applyBar(barId, stanceId)
    local s = db()
    if type(s.actionKits[barId]) ~= "table" then
        s.actionKits[barId] = {}
        s.actionKits[barId][stanceId] = captureBar(barId)
        return
    end
    local kit = s.actionKits[barId][stanceId]
    local ids = barSlotIds(barId)
    if type(kit) ~= "table" or type(kit.slots) ~= "table" then
        local i
        for i = 1, table.getn(ids) do
            clearSlot(ids[i])
        end
        s.actionKits[barId][stanceId] = emptyBarKit(barId)
        return
    end
    local i
    for i = 1, table.getn(ids) do
        local snap = kit.slots[i]
        if snap == nil then snap = { empty = 1 } end
        placeSnap(ids[i], snap)
    end
end

local function applyAllKits(stanceId)
    stanceId = tonumber(stanceId) or 0
    withQuiet(function()
        local b
        for b = 1, barCount() do
            applyBar(b, stanceId)
        end
    end)
end

local function seedActionKits()
    local s = db()
    if s._kitsSeeded then return end
    s._kitsSeeded = true
    local st = tonumber(detectedState) or 0
    local b
    for b = 1, barCount() do
        if type(s.actionKits[b]) ~= "table" then s.actionKits[b] = {} end
        s.actionKits[b][0] = captureBar(b)
        if st ~= 0 then
            s.actionKits[b][st] = deepCopy(s.actionKits[b][0])
        end
    end
    s.applied = st
    if anyBarAction() then seenActions = true end
end

local function swapActionKits(target)
    target = tonumber(target) or 0
    seedActionKits()
    local s = db()
    local applied = tonumber(s.applied)
    if applied == nil then
        s.applied = target
        applied = target
    end
    if applied == target then return end
    snapshotBarKits(applied)
    applyAllKits(target)
    s.applied = target
end

local function refreshActionBars()
    if IchaUI_RequestLayout then IchaUI_RequestLayout() end
    local n = barCount()
    local bi
    for bi = 1, n do
        if IchaUI_RefreshActionBar then IchaUI_RefreshActionBar(bi) end
    end
end

function IchaUI_StanceCopyKits(fromId, toId, barIndex)
    fromId = tonumber(fromId) or 0
    toId = tonumber(toId) or 0
    if fromId == toId then return end
    seedActionKits()
    local s = db()
    if tonumber(s.applied) == fromId then
        snapshotBarKits(fromId)
    end
    local function copyOne(b)
        if type(s.actionKits[b]) ~= "table" then s.actionKits[b] = {} end
        local src = s.actionKits[b][fromId]
        if type(src) == "table" then
            s.actionKits[b][toId] = deepCopy(src)
        else
            s.actionKits[b][toId] = emptyBarKit(b)
        end
        if tonumber(s.applied) == toId then
            withQuiet(function() applyBar(b, toId) end)
        end
    end
    if barIndex then
        copyOne(tonumber(barIndex) or 1)
    else
        local b
        for b = 1, barCount() do copyOne(b) end
    end
    if tonumber(s.applied) == toId then
        refreshActionBars()
    end
end

function IchaUI_StanceClearKits(stanceId, barIndex)
    stanceId = tonumber(stanceId) or 0
    seedActionKits()
    local s = db()
    local function clearOne(b)
        if type(s.actionKits[b]) ~= "table" then s.actionKits[b] = {} end
        s.actionKits[b][stanceId] = emptyBarKit(b)
        if tonumber(s.applied) == stanceId then
            withQuiet(function() applyBar(b, stanceId) end)
        end
    end
    if barIndex then
        clearOne(tonumber(barIndex) or 1)
    else
        local b
        for b = 1, barCount() do clearOne(b) end
    end
    if tonumber(s.applied) == stanceId then
        if anyBarAction() then seenActions = true end
        seenActions = true
        refreshActionBars()
    end
end

------------------------------------------------------------------------
-- Fire / refresh
------------------------------------------------------------------------
local function pumpPending()
    if cursorBusy() then return end
    if evt then evt:SetScript("OnUpdate", nil) end
    local st = pendingState
    pendingState = nil
    if st ~= nil then
        IchaUI_StanceFire(st)
    end
end

function IchaUI_StanceFire(state)
    state = tonumber(state) or IchaUI_StanceState()
    if swapping then
        pendingState = state
        return
    end
    if not booted then
        pendingState = state
        return
    end
    if cursorBusy() then
        pendingState = state
        if evt then evt:SetScript("OnUpdate", pumpPending) end
        return
    end
    swapping = true
    local s = db()
    -- Keep stored detected state unless simming (state arg is effective)
    if s.sim == nil then
        s.state = detectedState
    end

    ensureHeroPage(state)
    swapActionKits(state)

    if s.heroPrimaryFollows then
        bindHeroLivePage()
    end

    refreshActionBars()
    if IchaUI_RefreshHeroBar then IchaUI_RefreshHeroBar(1) end

    -- Drawers must NEVER follow/change with stances — do not call CustomDrawers_Apply

    local i
    for i = 1, table.getn(listeners) do
        local fn = listeners[i]
        if type(fn) == "function" then
            pcall(fn, state)
        end
    end
    swapping = false
    if pendingState ~= nil and pendingState ~= state and not cursorBusy() then
        local nxt = pendingState
        pendingState = nil
        IchaUI_StanceFire(nxt)
    end
end

------------------------------------------------------------------------
-- Detectors (copy Bongos stance.lua event logic)
------------------------------------------------------------------------
local quietDetect = false

local function setDetected(n)
    n = tonumber(n) or 0
    if detectedState == n then
        db().state = n
        return
    end
    detectedState = n
    db().state = n
    if quietDetect then return end
    -- Under sim, remember live form but do not thrash hero/bars
    if db().sim ~= nil then return end
    IchaUI_StanceFire(IchaUI_StanceState())
end

local function watchWarrior()
    -- UPDATE_BONUS_ACTIONBAR → GetBonusBarOffset() → 1/2/3
end

local function detectWarrior()
    if GetBonusBarOffset then
        setDetected(GetBonusBarOffset() or 0)
    end
end

local function detectRogue()
    if GetBonusBarOffset then
        setDetected(GetBonusBarOffset() or 0)
    end
end

local function detectDruidBonus()
    local state = 0
    local i
    for i = 1, 5 do
        if GetShapeshiftFormInfo then
            local _, _, active = GetShapeshiftFormInfo(i)
            if active then
                state = i
                break
            end
        end
    end
    setDetected(state)
end

local function detectDruidProwl()
    -- Only meaningful while cat (form 3) is active
    if not GetShapeshiftFormInfo then return end
    local _, _, active = GetShapeshiftFormInfo(3)
    if active then
        if isBuffActive(BUFF_PROWL) then
            setDetected(6)
        else
            setDetected(3)
        end
    end
end

local function detectPriest()
    if isBuffActive(BUFF_SHADOWFORM) then
        setDetected(1)
    else
        setDetected(0)
    end
end

local function pollNow()
    local class = playerClass()
    if not class then return end
    if class == "WARRIOR" then
        detectWarrior()
    elseif class == "ROGUE" then
        detectRogue()
    elseif class == "DRUID" then
        detectDruidBonus()
        detectDruidProwl()
    elseif class == "PRIEST" then
        detectPriest()
    else
        setDetected(0)
    end
end

------------------------------------------------------------------------
-- Slash helper
------------------------------------------------------------------------
function IchaUI_StanceSlash(rest)
    rest = string.lower(string.gsub(rest or "", "^%s+", ""))
    rest = string.gsub(rest, "%s+$", "")
    local s = db()
    local class = playerClass() or "?"

    if rest == "" or rest == "status" or rest == "print" then
        local st = IchaUI_StanceState()
        local simFlag = (s.sim ~= nil) and " (SIM)" or ""
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "IchaUI stance: class=%s state=%s (%s)%s enabled=%s heroFollow=%s kits=%s",
            class, tostring(st), IchaUI_StanceName(st), simFlag,
            s.enabled and "yes" or "no",
            s.heroPrimaryFollows and "yes" or "no",
            tostring(s.applied or st)
        ))
        return
    end

    local _, _, simArg = string.find(rest, "^sim%s+(.+)$")
    if rest == "sim" then
        DEFAULT_CHAT_FRAME:AddMessage("IchaUI: /icha stance sim <id> | /icha stance sim clear")
        return
    end
    if simArg then
        simArg = string.gsub(simArg, "^%s+", "")
        simArg = string.gsub(simArg, "%s+$", "")
        if simArg == "clear" or simArg == "off" or simArg == "nil" or simArg == "none" then
            IchaUI_StanceSetSim(nil)
            DEFAULT_CHAT_FRAME:AddMessage("IchaUI stance sim cleared. Live state=" ..
                tostring(IchaUI_StanceState()) .. " (" .. IchaUI_StanceName(IchaUI_StanceState()) .. ")")
            return
        end
        local n = tonumber(simArg)
        if not n then
            DEFAULT_CHAT_FRAME:AddMessage("IchaUI: stance sim needs a number (or clear).")
            return
        end
        IchaUI_StanceSetSim(n)
        DEFAULT_CHAT_FRAME:AddMessage("IchaUI stance sim=" .. tostring(n) ..
            " (" .. IchaUI_StanceName(n) .. ")")
        return
    end

    DEFAULT_CHAT_FRAME:AddMessage("IchaUI stance: /icha stance | stance sim <id> | stance sim clear")
end

------------------------------------------------------------------------
-- Options section builder (appends into Bars page; keeps Options.lua locals down)
-- h = { sectionHeader, tip, makeButton, makeGoldToggle, paintGoldToggle }
-- Returns refreshFn, newY
------------------------------------------------------------------------
function IchaUI_BuildStanceOptions(page, x, y, h)
    if not page or not h then return function() end, y or -4 end
    local refreshers = {}
    local function add(fn) table.insert(refreshers, fn) end
    local function refreshAll()
        local i
        for i = 1, table.getn(refreshers) do refreshers[i]() end
    end

    local PAD = x or 10
    local yy = y or -4
    local COLW = 340
    local stateFS, mapFS

    h.sectionHeader(page, "Stance", PAD, yy)
    yy = yy - 20

    local enBtn = h.makeGoldToggle(page, "Stance: On", 120, 20)
    enBtn:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, yy)
    enBtn:SetScript("OnClick", function()
        local s = db()
        IchaUI_StanceSetEnabled(not s.enabled)
        refreshAll()
    end)
    add(function()
        local on = db().enabled
        enBtn._label:SetText(on and "Stance: On" or "Stance: Off")
        h.paintGoldToggle(enBtn, on)
    end)
    yy = yy - 24

    -- Stack under Stance toggle so COL3 (~340 wide) does not clip.
    local heroBtn = h.makeGoldToggle(page, "Hero 1 follows: On", 160, 20)
    heroBtn:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, yy)
    heroBtn:SetScript("OnClick", function()
        local s = db()
        s.heroPrimaryFollows = not s.heroPrimaryFollows
        IchaUI_StanceFire(IchaUI_StanceState())
        refreshAll()
    end)
    add(function()
        local on = db().heroPrimaryFollows
        heroBtn._label:SetText(on and "Hero 1 follows: On" or "Hero 1 follows: Off")
        h.paintGoldToggle(heroBtn, on)
    end)
    yy = yy - 26

    stateFS = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stateFS:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, yy)
    stateFS:SetJustifyH("LEFT")
    stateFS:SetWidth(COLW)
    add(function()
        local s = db()
        local st = IchaUI_StanceState()
        stateFS:SetText(string.format("Current: %s (%s)  detected=%s",
            tostring(st), IchaUI_StanceName(st), tostring(s.state or 0)))
        if IchaUI_DyeFs then IchaUI_DyeFs(stateFS, 1, 1, 1) end
    end)
    yy = yy - 22

    h.tip(page, "Drawers never follow stances. Action bars and Hero 1 load the page for your current form.", PAD, yy, COLW)
    yy = yy - 28

    h.sectionHeader(page, "Action bar kits", PAD, yy)
    yy = yy - 18
    h.tip(page, "Each stance keeps its own copy of your action bars. Drag spells, items, or macros on while that page is selected. Page 0 starts from your current bars. Other pages start empty.", PAD, yy, COLW)
    yy = yy - 32

    mapFS = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mapFS:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, yy)
    mapFS:SetJustifyH("LEFT")
    mapFS:SetWidth(COLW)
    add(function()
        local s = db()
        local loaded = s.applied
        if loaded == nil then loaded = IchaUI_StanceState() end
        mapFS:SetText(string.format("Kits loaded: %s (%s)", tostring(loaded), IchaUI_StanceName(loaded)))
        if IchaUI_DyeFs then IchaUI_DyeFs(mapFS, 0.9, 0.88, 0.8) end
    end)
    yy = yy - 22

    local copyBtn = h.makeButton(page, "Copy page", 90, 20, function()
        local cur = IchaUI_StanceState()
        local opts = {}
        local ids2 = IchaUI_StanceClassIds()
        local j
        for j = 1, table.getn(ids2) do
            local sid = ids2[j]
            if sid ~= cur then
                table.insert(opts, { sid, "Copy to " .. IchaUI_StanceName(sid) })
            end
        end
        if IchaUI_ChoiceMenu then
            IchaUI_ChoiceMenu(copyBtn, opts, 1, function(idx)
                local o = opts[idx]
                if o and IchaUI_StanceCopyKits then
                    IchaUI_StanceCopyKits(cur, o[1])
                end
                refreshAll()
            end)
        end
    end)
    copyBtn:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, yy)
    local clearBtn = h.makeButton(page, "Clear page", 90, 20, function()
        if IchaUI_StanceClearKits then IchaUI_StanceClearKits(IchaUI_StanceState()) end
        refreshAll()
    end)
    clearBtn:SetPoint("LEFT", copyBtn, "RIGHT", 6, 0)
    yy = yy - 26

    h.tip(page, "Select a page below. Copy page duplicates the loaded action-bar kits. Clear page empties every action bar on this stance.", PAD, yy, COLW)
    yy = yy - 32

    h.sectionHeader(page, "Hero 1 / kit pages", PAD, yy)
    yy = yy - 18
    h.tip(page, "Each stance keeps its own Hero 1 kit. Click a page to load it (editing applies to that page). Live form returns to your real form.", PAD, yy, COLW)
    yy = yy - 28

    local liveBtn = h.makeButton(page, "Live form", 90, 20, function()
        if IchaUI_StanceSetSim then IchaUI_StanceSetSim(nil) end
        refreshAll()
    end)
    liveBtn:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, yy)
    yy = yy - 24

    local ids4 = IchaUI_StanceClassIds()
    local i
    local bx = PAD
    local btnW = 155
    local step = 165
    for i = 1, table.getn(ids4) do
        local sid = ids4[i]
        local b = h.makeButton(page, IchaUI_StanceName(sid), btnW, 20, function()
            -- Quiet page select via existing sim API (no sim labels in Options).
            if IchaUI_StanceSetSim then IchaUI_StanceSetSim(sid) end
            refreshAll()
        end)
        b:SetPoint("TOPLEFT", page, "TOPLEFT", bx, yy)
        bx = bx + step
        if bx + btnW > PAD + COLW then
            bx = PAD
            yy = yy - 24
        end
    end
    yy = yy - 28

    h.tip(page, "Click a page name to select that stance page. Hero 1 and your action bars load it. Live form returns to your current form.", PAD, yy, COLW)
    yy = yy - 20

    refreshAll()
    return refreshAll, yy
end

------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------
local function bootStep()
    bootTries = bootTries + 1
    local ready = false
    if anyBarAction() then ready = true end
    if bootTries > 90 then ready = true end
    if not ready then return end
    booted = true
    if evt then evt:SetScript("OnUpdate", nil) end
    local s = db()
    if not s._kitsSeeded then
        seedActionKits()
    elseif anyBarAction() and s.applied ~= nil then
        snapshotBarKits(s.applied)
    end
    local st = pendingState
    pendingState = nil
    if st == nil then st = IchaUI_StanceState() end
    IchaUI_StanceFire(st)
end

local function startup()
    if started then return end
    started = true
    db()
    local class = playerClass()
    if class then
        -- Detect live form quietly so hero page migration knows the current stance
        quietDetect = true
        pollNow()
        quietDetect = false
        ensureHeroPages()
    end
    -- Wait until the client has restored action slots (or a short cap) so a
    -- blank capture cannot wipe saved kits. Not a steady-state poll.
    booted = false
    bootTries = 0
    if evt then
        evt:SetScript("OnUpdate", bootStep)
    else
        booted = true
        IchaUI_StanceFire(IchaUI_StanceState())
    end
end

local function snapshotApplied()
    if swapping or not booted then return end
    local s = db()
    if s._kitsSeeded and s.applied ~= nil then
        snapshotBarKits(s.applied)
    end
end

evt = CreateFrame("Frame", "IchaUIStanceEvent")
evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("PLAYER_ENTERING_WORLD")
evt:RegisterEvent("PLAYER_LOGOUT")
evt:RegisterEvent("PLAYER_LEAVING_WORLD")
evt:RegisterEvent("ADDON_LOADED")
evt:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
evt:RegisterEvent("PLAYER_AURAS_CHANGED")
evt:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" then
        if arg1 == "IchaUI" then
            db()
        end
        return
    end
    if event == "PLAYER_LOGOUT" or event == "PLAYER_LEAVING_WORLD" then
        snapshotApplied()
        return
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        startup()
        return
    end
    local class = playerClass()
    if not class then return end
    if not db().enabled then return end

    if event == "UPDATE_BONUS_ACTIONBAR" then
        if class == "WARRIOR" then
            detectWarrior()
        elseif class == "ROGUE" then
            detectRogue()
        elseif class == "DRUID" then
            detectDruidBonus()
        end
        return
    end
    if event == "PLAYER_AURAS_CHANGED" then
        if class == "DRUID" then
            detectDruidProwl()
        elseif class == "PRIEST" then
            detectPriest()
        end
        return
    end
end)

-- Eager defaults so Options/Slash work before login in some load orders
db()
