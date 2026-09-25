-- Per-button hero binds. Each visible hero button can hold many
-- ability + key pairs. Pressing a key casts that ability and swaps the button.
-- Grid size: 1-12 columns, 1-5 rows. Default 4 x 2.
-- Slots are stored by cell (column, row), stride MAX_COLS, row 0 = bottom.
-- Growing the grid reveals empty cells. Shrinking drops only cells that
-- fall outside the new size. Remaining keys are not renumbered.

local BIND_POOL = 96
local MAX_COLS = 12
local MAX_ROWS = 5
local HERO_BAR = 7
local PUSH_MS = 0.12
-- Four extra hero bars besides the original (five total). Each extra bar
-- reserves its own action-slot block so it can use the same grid, scale,
-- and hero-setup saves as the original. The block is clamped to slots
-- still free after the original bar (1-120). Default remains one hero bar.
local MAX_EXTRA_HEROES = 4
local focusBar = 1

local pushUntil = 0
local pushBtnId = nil
local chords = {}
local lastFireAt = 0
local lastFireN = 0
local normed = false
local bulkApply = false

local ui = {
    selected = 1,
    scroll = 0,
    pickFor = nil,
    tab = 1,
    page = 0,
    tabs = {},
    slotBtns = {},
    rows = {},
    tabBtns = {},
    pickIcons = {},
}

local function clampInt(v, lo, hi, fallback)
    v = tonumber(v)
    if not v then v = fallback end
    v = math.floor(v + 0.5)
    if v < lo then v = lo end
    if v > hi then v = hi end
    return v
end

local function decodeKey(key)
    key = tonumber(key) or 1
    if key < 1 then key = 1 end
    local idx = key - 1
    local row = math.floor(idx / MAX_COLS)
    local col = math.mod(idx, MAX_COLS)
    return col, row
end

local function encodeKey(col, row)
    return row * MAX_COLS + col + 1
end

local function barStart(barId)
    if BActionBar and BActionBar.GetStart then
        return BActionBar.GetStart(barId)
    end
    local n = (BActionSets and BActionSets.g and BActionSets.g.numActionBars) or 10
    return math.floor(120 / n) * (barId - 1) + 1
end

local function pagedId(buttonId)
    if BActionButton and BActionButton.GetPagedID then
        return BActionButton.GetPagedID(buttonId)
    end
    return buttonId
end

local function fitGrid(cols, rows, cap)
    cols = clampInt(cols, 1, MAX_COLS, 4)
    rows = clampInt(rows, 1, MAX_ROWS, 2)
    if not cap or cap < 1 then cap = 1 end
    while rows > 1 and cols * rows > cap do rows = rows - 1 end
    while cols > 1 and cols * rows > cap do cols = cols - 1 end
    if cols * rows > cap then
        cols = 1
        rows = 1
    end
    return cols, rows
end

local function ensure()
    if not IchaUIDB then IchaUIDB = {} end
    if focusBar > 1 then
        local list = IchaUIDB.heroExtras
        local rec = list and list[focusBar - 1]
        if type(rec) == "table" then
            local cap = tonumber(rec.slotCount) or 8
            if cap < 1 then cap = 1 end
            rec.slotCount = cap
            rec.cols, rec.rows = fitGrid(rec.cols, rec.rows, cap)
            if type(rec.slots) ~= "table" then rec.slots = {} end
            local sc = tonumber(rec.scale) or 1.55
            if sc < 0.5 then sc = 0.5 end
            if sc > 3 then sc = 3 end
            rec.scale = sc
            return rec
        end
        focusBar = 1
    end
    local hs = IchaUIDB.heroSetup
    if type(hs) ~= "table" then
        hs = {}
        IchaUIDB.heroSetup = hs
    end
    hs.cols = clampInt(hs.cols, 1, MAX_COLS, 4)
    hs.rows = clampInt(hs.rows, 1, MAX_ROWS, 2)
    if type(hs.slots) ~= "table" then hs.slots = {} end
    if not normed then
        normed = true
        local copy = {}
        local k, v
        for k, v in pairs(hs.slots) do
            local nk = tonumber(k)
            if nk and type(v) == "table" then
                if type(v.abs) ~= "table" then v.abs = {} end
                copy[nk] = v
            end
        end
        if not hs.posSlots then
            local migrated = {}
            local cols = hs.cols
            if cols < 1 then cols = 1 end
            for k, v in pairs(copy) do
                local nk = tonumber(k)
                if nk and nk >= 1 then
                    local idx = nk - 1
                    local col = math.mod(idx, cols)
                    local row = math.floor(idx / cols)
                    if col < MAX_COLS and row < MAX_ROWS then
                        migrated[encodeKey(col, row)] = v
                    end
                end
            end
            copy = migrated
            hs.posSlots = 1
        end
        hs.slots = copy
    end
    return hs
end

function IchaUI_HeroGrid()
    local hs = ensure()
    return hs.cols, hs.rows
end

function IchaUI_HeroPrimaryGrid()
    local saved = focusBar
    focusBar = 1
    local hs = ensure()
    local c, r = hs.cols, hs.rows
    focusBar = saved
    return c, r
end

function IchaUI_HeroMaxSlots()
    local start = barStart(HERO_BAR)
    local n = 120 - start + 1
    if n < 1 then n = 1 end
    if n > 120 then n = 120 end
    local list = IchaUIDB and IchaUIDB.heroExtras
    if type(list) == "table" then
        local i
        for i = 1, table.getn(list) do
            local e = list[i]
            local base = e and tonumber(e.slotBase)
            if base and base > start then
                local room = base - start
                if room < n then n = room end
            end
        end
    end
    list = IchaUIDB and IchaUIDB.actionExtras
    if type(list) == "table" then
        local i
        for i = 1, table.getn(list) do
            local e = list[i]
            local base = e and tonumber(e.slotBase)
            if base and base > start then
                local room = base - start
                if room < n then n = room end
            end
        end
    end
    if n < 1 then n = 1 end
    return n
end

function IchaUI_HeroVisibleCount()
    local cols, rows = IchaUI_HeroGrid()
    local n = cols * rows
    local hs = ensure()
    if hs and hs.buttonCount then
        n = tonumber(hs.buttonCount) or n
    end
    local maxS
    if focusBar > 1 and IchaUIDB and IchaUIDB.heroExtras and IchaUIDB.heroExtras[focusBar - 1] then
        maxS = tonumber(IchaUIDB.heroExtras[focusBar - 1].slotCount) or n
    else
        maxS = IchaUI_HeroMaxSlots()
    end
    if n > maxS then n = maxS end
    if n < 1 then n = 1 end
    return n, cols
end

function IchaUI_HeroButtonId(slot)
    local saved = focusBar
    focusBar = 1
    slot = tonumber(slot) or 1
    if slot < 1 then focusBar = saved return nil end
    local maxS = IchaUI_HeroMaxSlots()
    if slot > maxS then focusBar = saved return nil end
    local id = barStart(HERO_BAR) + slot - 1
    focusBar = saved
    if id < 1 or id > 120 then return nil end
    return id
end

function IchaUI_HeroButtonIds()
    local saved = focusBar
    focusBar = 1
    local n, cols = IchaUI_HeroVisibleCount()
    local start = barStart(HERO_BAR)
    focusBar = saved
    local ids = {}
    local i
    for i = 0, n - 1 do
        local id = start + i
        if id <= 120 then
            table.insert(ids, id)
        end
    end
    return ids, cols
end

function IchaUI_HeroTopLeftSlot()
    local saved = focusBar
    focusBar = 1
    local n, cols = IchaUI_HeroVisibleCount()
    focusBar = saved
    if cols < 1 then cols = 1 end
    if n < 1 then return 1 end
    local rows = math.floor((n + cols - 1) / cols)
    if rows < 1 then rows = 1 end
    return (rows - 1) * cols + 1
end

local function slotOf(index, create)
    index = tonumber(index) or 0
    if index < 1 then return nil end
    local hs = ensure()
    local slot = hs.slots[index]
    if not slot and create then
        slot = { last = "", abs = {} }
        hs.slots[index] = slot
    end
    if slot and type(slot.abs) ~= "table" then slot.abs = {} end
    return slot
end

local function keyInGrid(key, cols, rows)
    if not cols or not rows then
        cols, rows = IchaUI_HeroGrid()
    end
    local col, row = decodeKey(key)
    if col < 0 or row < 0 then return false end
    if col >= cols or row >= rows then return false end
    local dense = row * cols + col + 1
    local n = IchaUI_HeroVisibleCount()
    if dense > n then return false end
    return true
end

local function buttonIdForKey(key)
    local cols, rows = IchaUI_HeroGrid()
    local col, row = decodeKey(key)
    if col < 0 or col >= cols or row < 0 or row >= rows then return nil end
    local dense = row * cols + col + 1
    local n = IchaUI_HeroVisibleCount()
    if dense > n then return nil end
    if focusBar > 1 and IchaUIDB and IchaUIDB.heroExtras and IchaUIDB.heroExtras[focusBar - 1] then
        local rec = IchaUIDB.heroExtras[focusBar - 1]
        local id = (tonumber(rec.slotBase) or 0) + dense - 1
        if id < 1 or id > 120 then return nil end
        return id
    end
    return IchaUI_HeroButtonId(dense)
end

local function visitSetups(fn)
    local saved = focusBar
    focusBar = 1
    fn(ensure(), 1)
    local list = IchaUIDB and IchaUIDB.heroExtras
    if type(list) == "table" then
        local i
        for i = 1, table.getn(list) do
            focusBar = i + 1
            fn(ensure(), i + 1)
        end
    end
    focusBar = saved
end

local function isButtonMouseKey(key)
    if not key then return false end
    return string.find(string.upper(key), "BUTTON%d") and true or false
end

local function isMouseKey(key)
    if not key then return false end
    local u = string.upper(key)
    if string.find(u, "BUTTON%d") then return true end
    if string.find(u, "MOUSEWHEEL", 1, true) then return true end
    return false
end

local function clearCmdKeys(cmd)
    if not GetBindingKey then return end
    local k1, k2 = GetBindingKey(cmd)
    if k1 and k1 ~= "" and SetBinding then SetBinding(k1) end
    if k2 and k2 ~= "" and SetBinding then SetBinding(k2) end
end

local function saveBindSet()
    if SaveBindings and GetCurrentBindingSet then
        SaveBindings(GetCurrentBindingSet())
    elseif SaveBindings then
        SaveBindings(1)
    end
end

-- Unknown unit tokens THROW on this client. pcall first result only.
local function unitExists(unit)
    if not unit or unit == "" or unit == "none" then return false end
    if string.sub(unit, 1, 6) == "IchaUI" then return false end
    if string.find(unit, "^nameplate%d+target$") then return false end
    if type(UnitExists) ~= "function" then return false end
    local exists = false
    local ok = pcall(function()
        if UnitExists(unit) then exists = true end
    end)
    return ok and exists
end

local function sameUnit(a, b)
    if not a or not b then return false end
    if a == b then return true end
    if type(UnitIsUnit) ~= "function" then return false end
    local same = false
    local ok = pcall(function()
        if UnitIsUnit(a, b) then same = true end
    end)
    return ok and same
end

local function targetUnitSafe(unit)
    if not unitExists(unit) then return false end
    if type(TargetUnit) ~= "function" then return false end
    local ok = pcall(function()
        TargetUnit(unit)
    end)
    return ok and true or false
end

local function spellTargetSafe(unit)
    if not unitExists(unit) then return false end
    if type(SpellTargetUnit) ~= "function" then return false end
    local ok = pcall(function()
        SpellTargetUnit(unit)
    end)
    return ok and true or false
end

-- Mouseover: SuperWoW "mouseover" token, then the unit on the hovered frame.
-- Do not build nameplateN.."target".
local function resolveMouseover()
    if unitExists("mouseover") then return "mouseover" end
    if type(GetMouseFocus) ~= "function" then return nil end
    local f = GetMouseFocus()
    local hops = 0
    while f and hops < 8 do
        hops = hops + 1
        local u = nil
        if type(f.unit) == "string" then
            u = f.unit
        elseif type(f.unitstr) == "string" then
            u = f.unitstr
        end
        if u and unitExists(u) then return u end
        if type(f.label) == "string" and f.id then
            local tok = f.label .. tostring(f.id)
            if unitExists(tok) then return tok end
        end
        local fname = nil
        if f.GetName then fname = f:GetName() end
        if fname and string.sub(fname, 1, 8) == "IchaUIUF_" then
            local key = string.sub(fname, 9)
            local us = string.find(key, "_")
            if us then key = string.sub(key, 1, us - 1) end
            local map = IchaUI_Swing_Frames
            local fr = map and map[key]
            if fr and type(fr.unit) == "string" and unitExists(fr.unit) then
                return fr.unit
            end
            if key == "tot" then key = "targettarget" end
            if unitExists(key) then return key end
        end
        if f.GetParent then
            f = f:GetParent()
        else
            f = nil
        end
    end
    return nil
end

local function wantRank(rank)
    if rank == nil or rank == "" then return nil end
    if type(rank) == "number" then return rank end
    local s = tostring(rank)
    local low = string.lower(s)
    if low == "max" or low == "highest" then return nil end
    return s
end

local function rankEquals(bookRank, want)
    if not want then return false end
    bookRank = bookRank or ""
    if type(want) == "number" then
        local n = tonumber(string.gsub(tostring(bookRank), "[^0-9]", ""))
        return n == want
    end
    local w = tostring(want)
    if bookRank == w then return true end
    if string.lower(bookRank) == string.lower(w) then return true end
    local bn = tonumber(string.gsub(bookRank, "[^0-9]", ""))
    local wn = tonumber(string.gsub(w, "[^0-9]", ""))
    if bn and wn and bn == wn then return true end
    return false
end

local function ranksFor(spellName)
    local ranks = {}
    if not spellName or spellName == "" or not GetSpellName then return ranks end
    local book = BOOKTYPE_SPELL or "spell"
    local want = string.lower(spellName)
    local i = 1
    while i <= 500 do
        local name, rank = GetSpellName(i, book)
        if not name then break end
        if string.lower(name) == want and rank and rank ~= "" then
            local seen = false
            local r
            for r = 1, table.getn(ranks) do
                if ranks[r] == rank then
                    seen = true
                    break
                end
            end
            if not seen then
                table.insert(ranks, rank)
            end
        end
        i = i + 1
    end
    return ranks
end

local function rankButtonText(rank)
    local want = wantRank(rank)
    if not want then return "Max" end
    if type(want) == "number" then return "R" .. tostring(want) end
    local n = tonumber(string.gsub(tostring(want), "[^0-9]", ""))
    if n then return "R" .. tostring(n) end
    return "Max"
end

local function atOf(entry)
    if entry and entry.at == "mouseover" then return "mouseover" end
    if entry and entry.at == "focus" then return "focus" end
    return "target"
end

local function findSpell(spellName, rankWant)
    if not spellName or spellName == "" or not GetSpellName then return nil end
    local book = BOOKTYPE_SPELL or "spell"
    local want = string.lower(spellName)
    rankWant = wantRank(rankWant)
    local best = nil
    local ranked = nil
    local i = 1
    while i <= 500 do
        local name, rank = GetSpellName(i, book)
        if not name then break end
        if string.lower(name) == want then
            local tex = nil
            if GetSpellTexture then tex = GetSpellTexture(i, book) end
            best = { name = name, rank = rank, index = i, texture = tex }
            if rankWant and rankEquals(rank, rankWant) then
                ranked = { name = name, rank = rank, index = i, texture = tex }
            end
        end
        i = i + 1
    end
    if not rankWant then return best end
    if ranked then return ranked end
    if best then
        local r = rankWant
        if type(r) == "number" then r = "Rank " .. tostring(r) end
        return { name = best.name, rank = r, index = nil, texture = best.texture }
    end
    return nil
end

local function fireSpell(entry, spellName, rankWant)
    local book = BOOKTYPE_SPELL or "spell"
    if entry and entry.index and CastSpell then
        CastSpell(entry.index, book)
        return true
    end
    if not CastSpellByName then return false end
    local castName = spellName
    if entry and entry.name then
        castName = entry.name
        if entry.rank and entry.rank ~= "" then
            castName = entry.name .. "(" .. entry.rank .. ")"
        end
    else
        local r = wantRank(rankWant)
        if r then
            if type(r) == "number" then r = "Rank " .. tostring(r) end
            castName = spellName .. "(" .. r .. ")"
        end
    end
    CastSpellByName(castName)
    return true
end

-- at == "mouseover" / "focus": TargetUnit that unit, CastSpell, SpellTargetUnit if needed,
-- TargetLastTarget. Missing mouseover falls back to current target. Empty focus does not cast.
-- Never pass a unit as CastSpellByName's 2nd arg (vanilla treats a truthy 2nd arg as self-cast).
local function castSpell(spellName, rankWant, at)
    local entry = findSpell(spellName, rankWant)
    local mo = nil
    local switched = false
    if at == "focus" then
        if type(IchaUI_FocusUnit) == "function" then
            mo = IchaUI_FocusUnit()
        end
        if not mo then return nil end
        if not (unitExists("target") and sameUnit("target", mo)) then
            switched = targetUnitSafe(mo)
        end
    elseif at == "mouseover" then
        mo = resolveMouseover()
        if mo then
            if not (unitExists("target") and sameUnit("target", mo)) then
                switched = targetUnitSafe(mo)
            end
        end
    end
    fireSpell(entry, spellName, rankWant)
    if mo and SpellIsTargeting and SpellIsTargeting() then
        spellTargetSafe(mo)
    end
    if switched and type(TargetLastTarget) == "function" then
        TargetLastTarget()
    end
    if entry then return entry end
    if spellName and spellName ~= "" then return { name = spellName } end
    return nil
end

local function entryKind(entry)
    if entry and (entry.kind == "macro" or entry.kind == "item") then
        return entry.kind
    end
    return "spell"
end

local function sameAbility(a, b)
    if entryKind(a) ~= entryKind(b) then return false end
    local kind = entryKind(a)
    if kind == "item" then
        local ai = tostring(a and a.itemId or "")
        local bi = tostring(b and b.itemId or "")
        if ai ~= "" and bi ~= "" then return ai == bi end
    end
    local an = string.lower((a and a.spell) or "")
    local bn = string.lower((b and b.spell) or "")
    return an ~= "" and an == bn
end

local function findMacro(name)
    if not name or name == "" or not GetMacroInfo then return nil, nil end
    local want = string.lower(name)
    local i
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
    for i = 1, nAcc do
        local mname, tex = GetMacroInfo(i)
        if mname and string.lower(mname) == want then
            return i, tex
        end
    end
    for i = 1, nChar do
        local mname, tex = GetMacroInfo(18 + i)
        if mname and string.lower(mname) == want then
            return 18 + i, tex
        end
    end
    for i = 1, 36 do
        local mname, tex = GetMacroInfo(i)
        if mname and string.lower(mname) == want then
            return i, tex
        end
    end
    return nil, nil
end

local function findItem(itemId, itemName)
    if not GetContainerNumSlots or not GetContainerItemLink then return nil, nil, nil end
    local wantId = nil
    if itemId and tostring(itemId) ~= "" then wantId = tostring(itemId) end
    local wantName = nil
    if itemName and itemName ~= "" then wantName = string.lower(itemName) end
    local bag
    for bag = 0, 4 do
        local n = GetContainerNumSlots(bag) or 0
        local slot
        for slot = 1, n do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, _, id = string.find(link, "item:(%d+)")
                local match = false
                if wantId and id and id == wantId then
                    match = true
                elseif wantName and id and GetItemInfo then
                    local iname = GetItemInfo(id)
                    if iname and string.lower(iname) == wantName then match = true end
                end
                if match then
                    local tex = nil
                    if GetContainerItemInfo then tex = GetContainerItemInfo(bag, slot) end
                    return bag, slot, tex
                end
            end
        end
    end
    return nil, nil, nil
end

local function placeEntry(entry)
    if not entry then return nil end
    local kind = entryKind(entry)
    if kind == "macro" then
        local idx, tex = findMacro(entry.spell)
        if not tex or tex == "" then tex = entry.texture end
        return { kind = "macro", macroIndex = idx, texture = tex, name = entry.spell }
    end
    if kind == "item" then
        local bag, slot, tex = findItem(entry.itemId, entry.spell)
        if not tex or tex == "" then tex = entry.texture end
        return { kind = "item", bag = bag, slot = slot, texture = tex, itemId = entry.itemId, name = entry.spell }
    end
    local found = findSpell(entry.spell, entry.rank)
    if found then return found end
    if entry.texture and entry.texture ~= "" then
        return { texture = entry.texture, name = entry.spell }
    end
    return nil
end

local function entryIcon(entry)
    if not entry then return nil end
    if entry.texture and entry.texture ~= "" then return entry.texture end
    local pe = placeEntry(entry)
    if pe then return pe.texture end
    return nil
end

local function slotShownEntry(slot)
    if not slot or type(slot.abs) ~= "table" then return nil end
    local i
    if slot.last and slot.last ~= "" then
        for i = 1, table.getn(slot.abs) do
            local e = slot.abs[i]
            if e and e.spell == slot.last then return e end
        end
    end
    for i = 1, table.getn(slot.abs) do
        local e = slot.abs[i]
        if e and e.spell and e.spell ~= "" then return e end
    end
    return nil
end

function IchaUI_HeroButtonItem(buttonId)
    buttonId = tonumber(buttonId)
    if not buttonId then return nil, nil end
    local itemId, itemName, itemTex
    visitSetups(function(hs, index)
        if itemId ~= nil or (type(itemName) == "string" and itemName ~= "") then return end
        local cols = tonumber(hs.cols) or 1
        local rows = tonumber(hs.rows) or 1
        if cols < 1 then cols = 1 end
        if rows < 1 then rows = 1 end
        local base = barStart(HERO_BAR)
        local cap = IchaUI_HeroMaxSlots()
        if index > 1 then
            base = tonumber(hs.slotBase) or 0
            cap = tonumber(hs.slotCount) or (cols * rows)
        end
        local n = cols * rows
        if n > cap then n = cap end
        local dense = buttonId - base + 1
        if dense < 1 or dense > n then return end
        local idx = dense - 1
        local col = math.mod(idx, cols)
        local row = math.floor(idx / cols)
        if col < 0 or row < 0 or col >= cols or row >= rows then return end
        local slot = hs.slots and hs.slots[encodeKey(col, row)]
        local shown = slotShownEntry(slot)
        if shown and entryKind(shown) == "item" then
            itemId = shown.itemId
            itemName = shown.spell
            itemTex = shown.texture
        end
    end)
    if itemId == nil and (type(itemName) ~= "string" or itemName == "") then
        return nil, nil
    end
    return itemId, itemName, itemTex
end

local function cursorBusy()
    if type(CursorHasSpell) == "function" and CursorHasSpell() then return true end
    if type(CursorHasItem) == "function" and CursorHasItem() then return true end
    if type(CursorHasMacro) == "function" and CursorHasMacro() then return true end
    return false
end

local function overlayIcon(buttonId, texture)
    if not texture or not buttonId then return end
    local b = getglobal("IchaUIBtn" .. tostring(buttonId))
    if b and b.icon then
        if IchaUI_SetButtonIcon then
            IchaUI_SetButtonIcon(b, texture)
        else
            b.icon:SetTexture(texture)
        end
        b.icon:Show()
        b.icon:SetAlpha(1)
    end
end

local function placeOn(entry, buttonId)
    if not entry or not buttonId then return end
    local oldPlay = PlaySound
    if oldPlay then PlaySound = function() end end
    if cursorBusy() then
        if entry.texture then overlayIcon(buttonId, entry.texture) end
        if oldPlay then PlaySound = oldPlay end
        return
    end
    if ClearCursor then ClearCursor() end
    if entry.kind == "macro" and entry.macroIndex and PickupMacro and PlaceAction then
        PickupMacro(entry.macroIndex)
        PlaceAction(pagedId(buttonId))
        if ClearCursor then ClearCursor() end
    elseif entry.kind == "item" and entry.bag and entry.slot and PickupContainerItem and PlaceAction then
        PickupContainerItem(entry.bag, entry.slot)
        PlaceAction(pagedId(buttonId))
        if ClearCursor then ClearCursor() end
    elseif entry.index and PickupSpell and PlaceAction then
        local book = BOOKTYPE_SPELL or "spell"
        PickupSpell(entry.index, book)
        PlaceAction(pagedId(buttonId))
        if ClearCursor then ClearCursor() end
    end
    if entry.texture then overlayIcon(buttonId, entry.texture) end
    if oldPlay then PlaySound = oldPlay end
end

local function clearAction(buttonId)
    if not buttonId or not PickupAction then return end
    local oldPlay = PlaySound
    if oldPlay then PlaySound = function() end end
    if cursorBusy() then
        if oldPlay then PlaySound = oldPlay end
        return
    end
    local aid = pagedId(buttonId)
    if HasAction and not HasAction(aid) then
        if oldPlay then PlaySound = oldPlay end
        return
    end
    if ClearCursor then ClearCursor() end
    PickupAction(aid)
    if ClearCursor then ClearCursor() end
    if oldPlay then PlaySound = oldPlay end
end

local function buttonHasSpell(entry, buttonId)
    if not entry or not entry.texture or not buttonId then return false end
    if type(GetActionTexture) ~= "function" then return false end
    local tex = GetActionTexture(pagedId(buttonId))
    return tex and tex == entry.texture
end

local function doPush(buttonId)
    if not buttonId then return end
    if pushButton then pushButton(buttonId) end
    pushBtnId = buttonId
    pushUntil = (GetTime and GetTime() or 0) + PUSH_MS
end

local function rebuildChords()
    chords = {}
    visitSetups(function(hs)
        local s
        for s = 1, MAX_COLS * MAX_ROWS do
            local slot = hs.slots[s]
            if slot and slot.abs then
                local i
                for i = 1, table.getn(slot.abs) do
                    local entry = slot.abs[i]
                    local k = entry and entry.key
                    if k and k ~= "" and entry.bindId and isMouseKey(k) then
                        chords[string.upper(k)] = entry.bindId
                    end
                end
            end
        end
    end)
end

local function applyEntryKey(entry, key)
    if not entry or not entry.bindId then return end
    local cmd = "ICHA_HEROBIND" .. tostring(entry.bindId)
    clearCmdKeys(cmd)
    if not key or key == "" then
        entry.key = ""
    else
        key = string.upper(key)
        visitSetups(function(hs)
            local s
            for s = 1, MAX_COLS * MAX_ROWS do
                local slot = hs.slots[s]
                if slot and slot.abs then
                    local i
                    for i = 1, table.getn(slot.abs) do
                        local other = slot.abs[i]
                        if other ~= entry and other.key and other.key ~= "" and string.upper(other.key) == key then
                            clearCmdKeys("ICHA_HEROBIND" .. tostring(other.bindId))
                            other.key = ""
                        end
                    end
                end
            end
        end)
        entry.key = key
        if (not isButtonMouseKey(key)) and SetBinding then
            SetBinding(key, cmd)
        end
    end
    if not bulkApply then
        saveBindSet()
        rebuildChords()
    end
end

local function allocBindId()
    local used = {}
    visitSetups(function(hs)
        local s
        for s = 1, MAX_COLS * MAX_ROWS do
            local slot = hs.slots[s]
            if slot and slot.abs then
                local i
                for i = 1, table.getn(slot.abs) do
                    local id = slot.abs[i] and tonumber(slot.abs[i].bindId)
                    if id then used[id] = true end
                end
            end
        end
    end)
    local n
    for n = 1, BIND_POOL do
        if not used[n] then return n end
    end
    return nil
end

local function findByBind(n)
    n = tonumber(n)
    if not n then return nil, nil, nil, nil end
    local foundS, foundE, foundSlot, foundBar
    visitSetups(function(hs, index)
        if foundS then return end
        local s
        for s = 1, MAX_COLS * MAX_ROWS do
            local slot = hs.slots[s]
            if slot and slot.abs then
                local i
                for i = 1, table.getn(slot.abs) do
                    if tonumber(slot.abs[i].bindId) == n then
                        foundS = s
                        foundE = slot.abs[i]
                        foundSlot = slot
                        foundBar = index
                        return
                    end
                end
            end
        end
    end)
    return foundS, foundE, foundSlot, foundBar
end

local function applyAll()
    bulkApply = true
    visitSetups(function(hs)
        local s
        for s = 1, MAX_COLS * MAX_ROWS do
            local slot = hs.slots[s]
            if slot and slot.abs then
                local i
                for i = 1, table.getn(slot.abs) do
                    local entry = slot.abs[i]
                    if entry and entry.key and entry.key ~= "" then
                        applyEntryKey(entry, entry.key)
                    end
                end
            end
        end
    end)
    bulkApply = false
    saveBindSet()
    rebuildChords()
end

local syncing = false
local function syncBarIcons()
    if syncing or cursorBusy() then return end
    syncing = true
    visitSetups(function()
        local cols, rows = IchaUI_HeroGrid()
        local n = IchaUI_HeroVisibleCount()
        local row
        for row = 0, rows - 1 do
            local col
            for col = 0, cols - 1 do
                local dense = row * cols + col + 1
                if dense <= n then
                    local key = encodeKey(col, row)
                    local btn = buttonIdForKey(key)
                    local slot = slotOf(key, false)
                    local shown = slotShownEntry(slot)
                    if shown and shown.spell and shown.spell ~= "" and btn then
                        local resolved = placeEntry(shown)
                        if resolved then
                            placeOn(resolved, btn)
                        elseif shown.texture then
                            overlayIcon(btn, shown.texture)
                        end
                    elseif btn then
                        clearAction(btn)
                    end
                end
            end
        end
    end)
    syncing = false
end

local function placeLastIcons()
    syncBarIcons()
end

function IchaUI_HeroBindFire(n)
    n = tonumber(n) or 0
    if n < 1 or n > BIND_POOL then return end
    local now = GetTime and GetTime() or 0
    if n == lastFireN and (now - lastFireAt) < 0.12 then return end
    local slotIndex, entry, slot, owner = findByBind(n)
    if not entry or not entry.spell or entry.spell == "" then return end
    local savedFocus = focusBar
    focusBar = owner or 1
    if not slotIndex or not keyInGrid(slotIndex) then
        focusBar = savedFocus
        return
    end
    lastFireAt = now
    lastFireN = n
    local spell = entry.spell
    local kind = entryKind(entry)
    if slot then slot.last = spell end
    local btnId = buttonIdForKey(slotIndex)
    focusBar = savedFocus
    local castEntry = nil
    local doUse = false
    if kind == "macro" or kind == "item" then
        castEntry = placeEntry(entry)
        doUse = true
    else
        if IchaUIShamanExtras_NotifyBoundCast then
            IchaUIShamanExtras_NotifyBoundCast(spell)
        end
        castEntry = castSpell(spell, entry.rank, atOf(entry))
        if not castEntry or not castEntry.index then
            castEntry = findSpell(spell, entry.rank) or castEntry
        end
    end
    local same = false
    if castEntry and btnId then same = buttonHasSpell(castEntry, btnId) end
    if not IchaUIHero_DeferPlace then
        IchaUIHero_DeferPlace = CreateFrame("Frame", "IchaUIHero_DeferPlace")
    end
    local defer = IchaUIHero_DeferPlace
    defer._ent = castEntry
    defer._btnId = btnId
    defer._needPlace = not same
    defer._use = doUse
    defer._frames = 0
    defer:SetScript("OnUpdate", function()
        this._frames = (this._frames or 0) + 1
        if this._frames < 1 then return end
        this:SetScript("OnUpdate", nil)
        local e = this._ent
        local id = this._btnId
        if this._needPlace and e and id then
            placeOn(e, id)
        elseif e and e.texture and id then
            overlayIcon(id, e.texture)
        end
        if this._use and id then
            local used = false
            local aid = pagedId(id)
            if UseAction and HasAction and HasAction(aid) then
                UseAction(aid, 1, 0)
                used = true
            end
            if not used and e and e.kind == "item" and e.bag and UseContainerItem then
                UseContainerItem(e.bag, e.slot)
                used = true
            end
            if not used and e and e.kind == "macro" and e.macroIndex and RunMacro then
                RunMacro(e.macroIndex)
            end
        end
        doPush(id)
    end)
end

function IchaUI_HeroChordFire(chord)
    if not chord or chord == "" then return false end
    local id = chords[string.upper(chord)]
    if not id then return false end
    IchaUI_HeroBindFire(id)
    return true
end

local function addAbility(slotIndex)
    local id = allocBindId()
    if not id then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("IchaUI: hero setup holds " .. BIND_POOL .. " keybinds total.")
        end
        return false
    end
    local slot = slotOf(slotIndex, true)
    if not slot then return false end
    table.insert(slot.abs, { spell = "", key = "", bindId = id, rank = "", at = "target" })
    return true
end

local function removeAbility(slotIndex, absIndex)
    local slot = slotOf(slotIndex, false)
    if not slot or not slot.abs then return end
    local entry = slot.abs[absIndex]
    if not entry then return end
    applyEntryKey(entry, "")
    table.remove(slot.abs, absIndex)
    if slot.last == entry.spell then
        slot.last = ""
        local i
        for i = 1, table.getn(slot.abs) do
            local e = slot.abs[i]
            if e and e.spell and e.spell ~= "" then
                slot.last = e.spell
                break
            end
        end
    end
    syncBarIcons()
end

local function setAbilitySpell(slotIndex, absIndex, spell)
    local slot = slotOf(slotIndex, false)
    if not slot or not slot.abs or not slot.abs[absIndex] then return end
    slot.abs[absIndex].spell = spell or ""
    slot.abs[absIndex].kind = "spell"
    slot.abs[absIndex].rank = ""
    slot.abs[absIndex].itemId = nil
    slot.last = slot.abs[absIndex].spell
    syncBarIcons()
end

local function setAbilityKey(slotIndex, absIndex, key)
    local slot = slotOf(slotIndex, false)
    if not slot or not slot.abs or not slot.abs[absIndex] then return end
    applyEntryKey(slot.abs[absIndex], key or "")
end

local function cycleAbilityRank(slotIndex, absIndex)
    local slot = slotOf(slotIndex, false)
    local entry = slot and slot.abs and slot.abs[absIndex]
    if not entry or entryKind(entry) ~= "spell" then return end
    if not entry.spell or entry.spell == "" then return end
    local ranks = ranksFor(entry.spell)
    local n = table.getn(ranks)
    if n < 1 then
        entry.rank = ""
        return
    end
    local cur = wantRank(entry.rank)
    local idx = 0
    if cur then
        local i
        for i = 1, n do
            if rankEquals(ranks[i], cur) then
                idx = i
                break
            end
        end
    end
    idx = idx + 1
    if idx > n then
        entry.rank = ""
    else
        entry.rank = ranks[idx]
    end
end

local function cycleAbilityAt(slotIndex, absIndex)
    local slot = slotOf(slotIndex, false)
    local entry = slot and slot.abs and slot.abs[absIndex]
    if not entry or entryKind(entry) ~= "spell" then return end
    if entry.at == "mouseover" then
        entry.at = "focus"
    elseif entry.at == "focus" then
        entry.at = "target"
    else
        entry.at = "mouseover"
    end
end

local function dropOutside(cols, rows)
    local hs = ensure()
    local doomed = {}
    local k, slot
    for k, slot in pairs(hs.slots) do
        local key = tonumber(k)
        if key and type(slot) == "table" then
            local col, row = decodeKey(key)
            local dense = row * cols + col + 1
            local n = cols * rows
            if hs.buttonCount then n = tonumber(hs.buttonCount) or n end
            if col >= cols or row >= rows or dense > n then
                table.insert(doomed, key)
            end
        end
    end
    local i
    for i = 1, table.getn(doomed) do
        local key = doomed[i]
        local held = hs.slots[key]
        if held and held.abs then
            local j
            for j = 1, table.getn(held.abs) do
                if held.abs[j] then applyEntryKey(held.abs[j], "") end
            end
        end
        hs.slots[key] = nil
    end
end

function IchaUI_HeroMoveSlot(fromKey, toKey)
    fromKey = tonumber(fromKey)
    toKey = tonumber(toKey)
    if not fromKey or not toKey or fromKey == toKey then return end
    if not keyInGrid(fromKey) or not keyInGrid(toKey) then return end
    local hs = ensure()
    local a = hs.slots[fromKey]
    local b = hs.slots[toKey]
    local function occupied(slot)
        return slotShownEntry(slot) and true or false
    end
    if not occupied(a) then return end
    if occupied(b) then
        hs.slots[fromKey] = b
        hs.slots[toKey] = a
    else
        hs.slots[toKey] = a
        hs.slots[fromKey] = nil
    end
    if ui.selected == fromKey then ui.selected = toKey end
    syncBarIcons()
    if IchaUI_HeroSetup_Refresh then IchaUI_HeroSetup_Refresh() end
end

function IchaUI_HeroCommitAbilities(slotKey, draft)
    slotKey = tonumber(slotKey)
    if not slotKey or type(draft) ~= "table" then return end
    local slot = slotOf(slotKey, true)
    if not slot then return end
    local old = slot.abs or {}
    local used = {}
    local newAbs = {}
    local i
    for i = 1, table.getn(draft) do
        local d = draft[i]
        if d and d.spell and d.spell ~= "" then
            local reused = nil
            local j
            for j = 1, table.getn(old) do
                if not used[j] and sameAbility(old[j], d) then
                    reused = old[j]
                    used[j] = true
                    break
                end
            end
            if reused then
                reused.kind = entryKind(d)
                reused.spell = d.spell
                if d.itemId then reused.itemId = d.itemId end
                if d.texture and d.texture ~= "" then reused.texture = d.texture end
                table.insert(newAbs, reused)
            else
                table.insert(newAbs, {
                    spell = d.spell,
                    key = "",
                    bindId = nil,
                    rank = "",
                    at = "target",
                    kind = entryKind(d),
                    itemId = d.itemId,
                    texture = d.texture,
                    _new = true,
                })
            end
        end
    end
    for i = 1, table.getn(old) do
        if not used[i] and old[i] then
            applyEntryKey(old[i], "")
        end
    end
    slot.abs = {}
    for i = 1, table.getn(newAbs) do
        if not newAbs[i]._new then
            table.insert(slot.abs, newAbs[i])
        end
    end
    local final = {}
    local denyNew = false
    local told = false
    for i = 1, table.getn(newAbs) do
        local e = newAbs[i]
        if e._new then
            if not denyNew then
                local id = allocBindId()
                if not id then
                    denyNew = true
                    if not told and DEFAULT_CHAT_FRAME then
                        told = true
                        DEFAULT_CHAT_FRAME:AddMessage("IchaUI: hero setup holds " .. BIND_POOL .. " keybinds total.")
                    end
                else
                    e._new = nil
                    e.bindId = id
                    table.insert(slot.abs, e)
                    table.insert(final, e)
                end
            end
        else
            table.insert(final, e)
        end
    end
    slot.abs = final
    local keepLast = false
    for i = 1, table.getn(final) do
        if final[i] and final[i].spell == slot.last then keepLast = true end
    end
    if not keepLast then
        slot.last = ""
        if final[1] and final[1].spell then slot.last = final[1].spell end
    end
    syncBarIcons()
    if IchaUI_HeroSetup_Refresh then IchaUI_HeroSetup_Refresh() end
end

function IchaUI_HeroSetGrid(cols, rows)
    local hs = ensure()
    local oldCols, oldRows = hs.cols, hs.rows
    cols = clampInt(cols, 1, MAX_COLS, hs.cols)
    rows = clampInt(rows, 1, MAX_ROWS, hs.rows)
    if focusBar > 1 then
        local cap = tonumber(hs.slotCount) or 8
        local fc, fr = fitGrid(cols, rows, cap)
        if fc ~= cols or fr ~= rows then
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("IchaUI: hero " .. focusBar .. " has " .. cap .. " action slots.")
            end
        end
        cols, rows = fc, fr
    end
    local changed = (oldCols ~= cols) or (oldRows ~= rows)
    if changed and (cols < oldCols or rows < oldRows) then
        dropOutside(cols, rows)
    end
    hs.cols = cols
    hs.rows = rows
    if changed then
        syncBarIcons()
        if IchaUI_RequestLayout then IchaUI_RequestLayout() end
    end
    if IchaUI_HeroSetup_Refresh then IchaUI_HeroSetup_Refresh() end
end

function IchaUI_HeroSetCols(v)
    local _, rows = IchaUI_HeroGrid()
    IchaUI_HeroSetGrid(v, rows)
end

function IchaUI_HeroSetRows(v)
    local cols = IchaUI_HeroGrid()
    IchaUI_HeroSetGrid(cols, v)
end

local function shortName(name)
    if not name or name == "" then return "(choose ability)" end
    if string.len(name) > 16 then return string.sub(name, 1, 14) .. ".." end
    return name
end

local function keyText(key)
    if IchaUI_AbbreviateBindKey then return IchaUI_AbbreviateBindKey(key) end
    if not key or key == "" then return "—" end
    return key
end

local panel
local function buildPanel()
    local GOLD_R, GOLD_G, GOLD_B = 0.78, 0.58, 0.16
    panel = CreateFrame("Frame", "IchaUIHeroSetup", UIParent)
    panel:SetWidth(910)
    panel:SetHeight(520)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetFrameLevel(400)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function() this:StartMoving() end)
    panel:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    panel:SetScript("OnMouseWheel", function() end)
    panel:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:SetBackdropColor(0.07, 0.07, 0.08, 1)
    IchaUI_PaintGoldBorder(panel, 1)
    local solid = panel:CreateTexture(nil, "BACKGROUND")
    solid:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    solid:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4)
    solid:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 4)
    solid:SetVertexColor(0.07, 0.07, 0.08, 1)
    panel:Hide()
    panel:SetScript("OnHide", function()
        if ui.ghost then ui.ghost:Hide() end
        ui.dragFrom = nil
        if IchaUI_HeroPicker_Close then IchaUI_HeroPicker_Close() end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "IchaUIHeroSetup") end

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -12)
    title:SetText("Hero setup")
    IchaUI_PaintGoldFont(title, 0.78, 0.58, 0.16)
    ui.title = title

    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    closeBtn:SetWidth(60)
    closeBtn:SetHeight(20)
    closeBtn:SetText("Close")
    closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -10)
    closeBtn:SetFrameLevel(430)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -34)
    hint:SetWidth(400)
    hint:SetJustifyH("LEFT")
    hint:SetText("Drag a slot onto another to move that ability group. Added rows and columns stay empty. Edit abilities, then Save.")
    hint:SetTextColor(0.7, 0.7, 0.65)

    local function smallBtn(parent, text, w, h)
        local b = CreateFrame("Button", nil, parent)
        b:SetWidth(w)
        b:SetHeight(h)
        b:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        b:SetBackdropColor(0.06, 0.06, 0.07, 0.9)
        IchaUI_PaintGoldBorder(b, 0.8)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("CENTER", b, "CENTER", 0, 0)
        fs:SetText(text or "")
        fs:SetTextColor(0.9, 0.9, 0.85)
        b.label = fs
        return b
    end

    local colLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    colLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -88)
    colLabel:SetText("Columns")
    colLabel:SetTextColor(0.8, 0.8, 0.75)
    local colMinus = smallBtn(panel, "-", 22, 18)
    colMinus:SetPoint("LEFT", colLabel, "RIGHT", 8, 0)
    local colVal = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    colVal:SetWidth(18)
    colVal:SetJustifyH("CENTER")
    colVal:SetPoint("LEFT", colMinus, "RIGHT", 4, 0)
    IchaUI_PaintGoldFont(colVal, 0.78, 0.58, 0.16)
    local colPlus = smallBtn(panel, "+", 22, 18)
    colPlus:SetPoint("LEFT", colVal, "RIGHT", 6, 0)
    colMinus:SetScript("OnClick", function()
        local c = IchaUI_HeroGrid()
        IchaUI_HeroSetCols(c - 1)
    end)
    colPlus:SetScript("OnClick", function()
        local c = IchaUI_HeroGrid()
        IchaUI_HeroSetCols(c + 1)
    end)

    local rowLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rowLabel:SetPoint("LEFT", colPlus, "RIGHT", 18, 0)
    rowLabel:SetText("Rows")
    rowLabel:SetTextColor(0.8, 0.8, 0.75)
    local rowMinus = smallBtn(panel, "-", 22, 18)
    rowMinus:SetPoint("LEFT", rowLabel, "RIGHT", 8, 0)
    local rowVal = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rowVal:SetWidth(14)
    rowVal:SetJustifyH("CENTER")
    rowVal:SetPoint("LEFT", rowMinus, "RIGHT", 4, 0)
    IchaUI_PaintGoldFont(rowVal, 0.78, 0.58, 0.16)
    local rowPlus = smallBtn(panel, "+", 22, 18)
    rowPlus:SetPoint("LEFT", rowVal, "RIGHT", 6, 0)
    rowMinus:SetScript("OnClick", function()
        local _, r = IchaUI_HeroGrid()
        IchaUI_HeroSetRows(r - 1)
    end)
    rowPlus:SetScript("OnClick", function()
        local _, r = IchaUI_HeroGrid()
        IchaUI_HeroSetRows(r + 1)
    end)

    local gridHost = CreateFrame("Frame", nil, panel)
    gridHost:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -114)
    gridHost:SetWidth(410)
    gridHost:SetHeight(230)

    local ghost = CreateFrame("Frame", "IchaUIHeroDragGhost", UIParent)
    ghost:SetWidth(36)
    ghost:SetHeight(36)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:EnableMouse(false)
    local gicon = ghost:CreateTexture(nil, "ARTWORK")
    gicon:SetAllPoints(ghost)
    gicon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ghost.icon = gicon
    ghost:Hide()
    ui.ghost = ghost
    local function trackGhost()
        if not ui.dragFrom then
            this:Hide()
            this:SetScript("OnUpdate", nil)
            return
        end
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        if not scale or scale <= 0 then scale = 1 end
        this:ClearAllPoints()
        this:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end

    local function cursorOver(frame)
        if not frame or not frame.IsShown or not frame:IsShown() then return false end
        if not frame.GetLeft or not GetCursorPosition then return false end
        local l = frame:GetLeft()
        local rgt = frame:GetRight()
        local top = frame:GetTop()
        local bot = frame:GetBottom()
        if not l or not rgt or not top or not bot then return false end
        local x, y = GetCursorPosition()
        local scale = frame:GetEffectiveScale()
        if not scale or scale <= 0 then scale = 1 end
        x = x / scale
        y = y / scale
        if x < l or x > rgt or y > top or y < bot then return false end
        return true
    end

    local i
    for i = 1, MAX_COLS * MAX_ROWS do
        local idx = i
        local b = smallBtn(gridHost, "", 36, 36)
        b.slotKey = idx
        ui.slotBtns[idx] = b
        b:RegisterForDrag("LeftButton")
        local ic = b:CreateTexture(nil, "ARTWORK")
        ic:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -4)
        ic:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 4)
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ic:Hide()
        b.icon = ic
        b.label:ClearAllPoints()
        b.label:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
        b.label:SetJustifyH("RIGHT")
        b:SetScript("OnMouseDown", function()
            if arg1 and arg1 ~= "LeftButton" then return end
            ui.selected = this.slotKey
            ui.scroll = 0
        end)
        b:SetScript("OnMouseUp", function()
            if ui.dragFrom then return end
            if IchaUI_HeroSetup_Refresh then IchaUI_HeroSetup_Refresh() end
        end)
        b:SetScript("OnDragStart", function()
            local slot = slotOf(this.slotKey, false)
            if not slotShownEntry(slot) then return end
            ui.dragFrom = this.slotKey
            ui.selected = this.slotKey
            local shown = slotShownEntry(slot)
            local tex = entryIcon(shown)
            if tex and ui.ghost and ui.ghost.icon then
                ui.ghost.icon:SetTexture(tex)
                ui.ghost:Show()
                ui.ghost:SetScript("OnUpdate", trackGhost)
            end
        end)
        b:SetScript("OnDragStop", function()
            if ui.ghost then ui.ghost:Hide() end
            local from = ui.dragFrom
            ui.dragFrom = nil
            if not from then return end
            local to = nil
            local k
            for k = 1, MAX_COLS * MAX_ROWS do
                local ob = ui.slotBtns[k]
                if ob and cursorOver(ob) then
                    to = ob.slotKey
                    break
                end
            end
            if from and to and from ~= to and IchaUI_HeroMoveSlot then
                IchaUI_HeroMoveSlot(from, to)
            elseif IchaUI_HeroSetup_Refresh then
                IchaUI_HeroSetup_Refresh()
            end
        end)
        b:SetScript("OnEnter", function()
            local slot = slotOf(this.slotKey, false)
            local col, row = decodeKey(this.slotKey)
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText("Column " .. tostring(col + 1) .. ", row " .. tostring(row + 1) .. " from bottom")
            if slot and slot.abs then
                local ai
                for ai = 1, table.getn(slot.abs) do
                    local e = slot.abs[ai]
                    if e and e.spell and e.spell ~= "" then
                        local tag = "Spell"
                        if entryKind(e) == "macro" then tag = "Macro" end
                        if entryKind(e) == "item" then tag = "Item" end
                        GameTooltip:AddLine(tag .. ": " .. e.spell, 1, 1, 1)
                    end
                end
            end
            GameTooltip:AddLine("Drag onto another slot to move this group.", 0.75, 0.75, 0.65)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local slotTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    slotTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 440, -56)
    slotTitle:SetText("Button")
    IchaUI_PaintGoldFont(slotTitle, 0.78, 0.58, 0.16)

    local absHost = CreateFrame("Frame", nil, panel)
    absHost:SetPoint("TOPLEFT", panel, "TOPLEFT", 440, -78)
    absHost:SetWidth(450)
    absHost:SetHeight(210)
    absHost:EnableMouse(true)
    absHost:EnableMouseWheel(true)
    absHost:SetScript("OnMouseWheel", function()
        local dir = tonumber(arg1) or 0
        if dir > 0 then ui.scroll = ui.scroll - 1 end
        if dir < 0 then ui.scroll = ui.scroll + 1 end
        if ui.scroll < 0 then ui.scroll = 0 end
        if IchaUI_HeroSetup_Refresh then IchaUI_HeroSetup_Refresh() end
    end)

    local ROW_N = 8
    for i = 1, ROW_N do
        local rowIdx = i
        local y = -((i - 1) * 24)
        local spellBtn = smallBtn(absHost, "(choose ability)", 140, 20)
        spellBtn:SetPoint("TOPLEFT", absHost, "TOPLEFT", 0, y)
        local sIcon = spellBtn:CreateTexture(nil, "ARTWORK")
        sIcon:SetWidth(16)
        sIcon:SetHeight(16)
        sIcon:SetPoint("LEFT", spellBtn, "LEFT", 2, 0)
        sIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        sIcon:Hide()
        spellBtn.icon = sIcon
        spellBtn.label:ClearAllPoints()
        spellBtn.label:SetPoint("LEFT", spellBtn, "LEFT", 20, 0)
        spellBtn.label:SetJustifyH("LEFT")
        spellBtn:EnableMouseWheel(true)
        local rankBtn = smallBtn(absHost, "Max", 44, 20)
        rankBtn:SetPoint("LEFT", spellBtn, "RIGHT", 4, 0)
        rankBtn:EnableMouseWheel(true)
        local atBtn = smallBtn(absHost, "Target", 82, 20)
        atBtn:SetPoint("LEFT", rankBtn, "RIGHT", 4, 0)
        atBtn:EnableMouseWheel(true)
        local keyBtn = smallBtn(absHost, "—", 70, 20)
        keyBtn:SetPoint("LEFT", atBtn, "RIGHT", 4, 0)
        keyBtn:EnableMouseWheel(true)
        local xBtn = smallBtn(absHost, "x", 20, 20)
        xBtn:SetPoint("LEFT", keyBtn, "RIGHT", 4, 0)
        xBtn:EnableMouseWheel(true)
        local function wheelAbs()
            local dir = tonumber(arg1) or 0
            if dir > 0 then ui.scroll = ui.scroll - 1 end
            if dir < 0 then ui.scroll = ui.scroll + 1 end
            if ui.scroll < 0 then ui.scroll = 0 end
            if IchaUI_HeroSetup_Refresh then IchaUI_HeroSetup_Refresh() end
        end
        spellBtn:SetScript("OnMouseWheel", wheelAbs)
        rankBtn:SetScript("OnMouseWheel", wheelAbs)
        atBtn:SetScript("OnMouseWheel", wheelAbs)
        keyBtn:SetScript("OnMouseWheel", wheelAbs)
        xBtn:SetScript("OnMouseWheel", wheelAbs)
        spellBtn:SetScript("OnClick", function()
            local slot = slotOf(ui.selected, false)
            local absIndex = ui.scroll + rowIdx
            if not slot or not slot.abs or not slot.abs[absIndex] then return end
            if IchaUI_HeroPicker_Open then IchaUI_HeroPicker_Open(ui.selected) end
        end)
        rankBtn:SetScript("OnClick", function()
            cycleAbilityRank(ui.selected, ui.scroll + rowIdx)
            if IchaUI_HeroSetup_Refresh then IchaUI_HeroSetup_Refresh() end
        end)
        rankBtn:SetScript("OnEnter", function()
            local slot = slotOf(ui.selected, false)
            local absIndex = ui.scroll + rowIdx
            local entry = slot and slot.abs and slot.abs[absIndex]
            local tip = "Highest rank"
            if entry and entryKind(entry) ~= "spell" then
                tip = "Rank applies to spells"
            elseif entry and wantRank(entry.rank) then
                local r = entry.rank
                if type(r) == "number" then r = "Rank " .. tostring(r) end
                tip = tostring(r)
            end
            GameTooltip:SetOwner(this, "ANCHOR_TOP")
            GameTooltip:SetText(tip)
            GameTooltip:Show()
        end)
        rankBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        atBtn:SetScript("OnClick", function()
            cycleAbilityAt(ui.selected, ui.scroll + rowIdx)
            if IchaUI_HeroSetup_Refresh then IchaUI_HeroSetup_Refresh() end
        end)
        atBtn:SetScript("OnEnter", function()
            local slot = slotOf(ui.selected, false)
            local absIndex = ui.scroll + rowIdx
            local entry = slot and slot.abs and slot.abs[absIndex]
            local tip = "Cast at current target"
            if entry and entryKind(entry) == "macro" then
                tip = "Runs this macro from the hero button"
            elseif entry and entryKind(entry) == "item" then
                tip = "Uses this item from the hero button"
            elseif atOf(entry) == "mouseover" then
                tip = "Cast at mouseover, then restore target"
            elseif atOf(entry) == "focus" then
                tip = "Cast at focus, then restore target"
            end
            GameTooltip:SetOwner(this, "ANCHOR_TOP")
            GameTooltip:SetText(tip)
            GameTooltip:Show()
        end)
        atBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        keyBtn:SetScript("OnClick", function()
            local slot = slotOf(ui.selected, false)
            local absIndex = ui.scroll + rowIdx
            if not slot or not slot.abs or not slot.abs[absIndex] then return end
            if not IchaUI_StartKeyCapture then return end
            local capCol, capRow = decodeKey(ui.selected)
            IchaUI_StartKeyCapture(keyBtn.label, function(key)
                setAbilityKey(ui.selected, absIndex, key)
                if IchaUI_HeroSetup_Refresh then IchaUI_HeroSetup_Refresh() end
            end, "Column " .. tostring(capCol + 1) .. ", row " .. tostring(capRow + 1) .. " — key / mouse / scroll")
        end)
        xBtn:SetScript("OnClick", function()
            removeAbility(ui.selected, ui.scroll + rowIdx)
            if IchaUI_HeroSetup_Refresh then IchaUI_HeroSetup_Refresh() end
        end)
        ui.rows[i] = { spell = spellBtn, rank = rankBtn, at = atBtn, key = keyBtn, x = xBtn }
    end

    local addBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addBtn:SetWidth(130)
    addBtn:SetHeight(20)
    addBtn:SetText("Edit abilities")
    addBtn:SetPoint("TOPLEFT", absHost, "BOTTOMLEFT", 0, -6)
    addBtn:SetScript("OnClick", function()
        if IchaUI_HeroPicker_Open then IchaUI_HeroPicker_Open(ui.selected) end
    end)

    local shockNote = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    shockNote:SetPoint("TOPLEFT", addBtn, "BOTTOMLEFT", 0, -8)
    shockNote:SetWidth(450)
    shockNote:SetJustifyH("LEFT")
    shockNote:SetTextColor(0.65, 0.65, 0.6)

    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 14)
    status:SetWidth(860)
    status:SetJustifyH("LEFT")
    status:SetTextColor(0.55, 0.55, 0.5)


    local function refresh()
        local cols, rows = IchaUI_HeroGrid()
        local n = IchaUI_HeroVisibleCount()
        if ui.title then
            if focusBar > 1 then
                ui.title:SetText("Hero " .. tostring(focusBar) .. " setup")
            else
                ui.title:SetText("Hero setup")
            end
        end
        colVal:SetText(tostring(cols))
        rowVal:SetText(tostring(rows))
        local selCol, selRow = decodeKey(ui.selected)
        local selDense = selRow * cols + selCol + 1
        if selCol >= cols or selRow >= rows or selCol < 0 or selRow < 0 or selDense > n then
            ui.selected = 1
            selCol, selRow = 0, 0
        end
        local gap = 3
        local bw = 36
        if cols > 0 then bw = math.floor((400 - gap) / cols) - gap end
        if bw > 42 then bw = 42 end
        if bw < 22 then bw = 22 end
        local step = bw + gap
        local s
        for s = 1, MAX_COLS * MAX_ROWS do
            local b = ui.slotBtns[s]
            local col, row = decodeKey(s)
            local dense = row * cols + col + 1
            if b and col < cols and row < rows and dense <= n then
                local fromTop = (rows - 1) - row
                b:SetWidth(bw)
                b:SetHeight(bw)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", gridHost, "TOPLEFT", col * step, -(fromTop * step))
                local held = slotOf(s, false)
                local shown = slotShownEntry(held)
                local tex = entryIcon(shown)
                local nabs = 0
                if held and held.abs then
                    local ai
                    for ai = 1, table.getn(held.abs) do
                        local e = held.abs[ai]
                        if e and e.spell and e.spell ~= "" then nabs = nabs + 1 end
                    end
                end
                if tex and b.icon then
                    b.icon:SetTexture(tex)
                    b.icon:Show()
                elseif b.icon then
                    b.icon:Hide()
                end
                if nabs > 1 then
                    b.label:SetText(tostring(nabs))
                else
                    b.label:SetText("")
                end
                if s == ui.selected then
                    b:SetBackdropBorderColor(1, 0.9, 0.45, 1)
                    b:SetBackdropColor(0.22, 0.16, 0.05, 0.95)
                else
                    IchaUI_PaintGoldBorder(b, 0.75)
                    b:SetBackdropColor(0.06, 0.06, 0.07, 0.9)
                end
                b:Show()
            elseif b then
                b:Hide()
            end
        end
        local slot = slotOf(ui.selected, false)
        local count = (slot and slot.abs) and table.getn(slot.abs) or 0
        local maxScroll = count - ROW_N
        if maxScroll < 0 then maxScroll = 0 end
        if ui.scroll > maxScroll then ui.scroll = maxScroll end
        if ui.scroll < 0 then ui.scroll = 0 end
        slotTitle:SetText("Column " .. tostring(selCol + 1) .. ", row " .. tostring(selRow + 1) .. "  (" .. tostring(count) .. ")")
        local r
        for r = 1, ROW_N do
            local row = ui.rows[r]
            local absIndex = ui.scroll + r
            local entry = slot and slot.abs and slot.abs[absIndex]
            if entry then
                row.spell.label:SetText(shortName(entry.spell))
                local iconTex = nil
                if entry.spell and entry.spell ~= "" then iconTex = entryIcon(entry) end
                if iconTex and row.spell.icon then
                    row.spell.icon:SetTexture(iconTex)
                    row.spell.icon:Show()
                elseif row.spell.icon then
                    row.spell.icon:Hide()
                end
                if row.rank and row.rank.label then
                    if entryKind(entry) ~= "spell" then
                        row.rank.label:SetText("—")
                        IchaUI_PaintGoldBorder(row.rank, 0.8)
                    else
                        row.rank.label:SetText(rankButtonText(entry.rank))
                        if wantRank(entry.rank) then
                            row.rank:SetBackdropBorderColor(1, 0.9, 0.45, 1)
                        else
                            IchaUI_PaintGoldBorder(row.rank, 0.8)
                        end
                    end
                end
                if row.at and row.at.label then
                    if entryKind(entry) == "macro" then
                        row.at.label:SetText("Macro")
                        IchaUI_PaintGoldBorder(row.at, 0.8)
                    elseif entryKind(entry) == "item" then
                        row.at.label:SetText("Item")
                        IchaUI_PaintGoldBorder(row.at, 0.8)
                    elseif atOf(entry) == "mouseover" then
                        row.at.label:SetText("Mouseover")
                        row.at:SetBackdropBorderColor(1, 0.9, 0.45, 1)
                    elseif atOf(entry) == "focus" then
                        row.at.label:SetText("Focus")
                        row.at:SetBackdropBorderColor(1, 0.9, 0.45, 1)
                    else
                        row.at.label:SetText("Target")
                        IchaUI_PaintGoldBorder(row.at, 0.8)
                    end
                end
                row.key.label:SetText(keyText(entry.key))
                row.spell:Show()
                if row.rank then row.rank:Show() end
                if row.at then row.at:Show() end
                row.key:Show()
                row.x:Show()
            else
                row.spell:Hide()
                if row.rank then row.rank:Hide() end
                if row.at then row.at:Hide() end
                row.key:Hide()
                row.x:Hide()
            end
        end
        local note = "Spells keep Target, Mouseover, and Focus. Empty focus does not cast. Macros and items use the hero button. A number on a slot is how many abilities it holds."
        shockNote:SetText(note)
        local want = cols * rows
        local maxS = IchaUI_HeroMaxSlots()
        if focusBar > 1 and IchaUIDB and IchaUIDB.heroExtras and IchaUIDB.heroExtras[focusBar - 1] then
            maxS = tonumber(IchaUIDB.heroExtras[focusBar - 1].slotCount) or maxS
        end
        local msg = string.format("Showing %d  (%d wide, %d tall). Width 1-%d, height 1-%d. Keybinds shared: %d.", n, cols, rows, MAX_COLS, MAX_ROWS, BIND_POOL)
        if want > n then
            msg = msg .. string.format(" %d more would not fit (action slots left: %d).", want - n, maxS)
        end
        status:SetText(msg)
    end

    panel:SetScript("OnShow", function()
        if IchaUI_DyeConfigTree then IchaUI_DyeConfigTree(panel, 0) end
    end)
    IchaUI_HeroSetup_Refresh = refresh
    ui.refresh = refresh
    if IchaUI_DyeConfigTree then IchaUI_DyeConfigTree(panel, 0) end
end

local function slotsFree(lo, hi)
    if lo < 1 or hi > 120 or lo > hi then return false end
    local start = barStart(HERO_BAR)
    local saved = focusBar
    focusBar = 1
    local vis = IchaUI_HeroVisibleCount()
    focusBar = saved
    local primHi = start + vis - 1
    if not (hi < start or lo > primHi) then return false end
    local list = IchaUIDB and IchaUIDB.heroExtras
    if type(list) == "table" then
        local i
        for i = 1, table.getn(list) do
            local e = list[i]
            local b = e and tonumber(e.slotBase)
            local c = e and tonumber(e.slotCount)
            if b and c and c > 0 then
                local ehi = b + c - 1
                if not (hi < b or lo > ehi) then return false end
            end
        end
    end
    list = IchaUIDB and IchaUIDB.actionExtras
    if type(list) == "table" then
        local i
        for i = 1, table.getn(list) do
            local e = list[i]
            local b = e and tonumber(e.slotBase)
            local c = e and tonumber(e.slotCount)
            if b and c and c > 0 then
                local ehi = b + c - 1
                if not (hi < b or lo > ehi) then return false end
            end
        end
    end
    return true
end

local function allocExtraBlock()
    local start = barStart(HERO_BAR)
    local sizes = { 12, 8, 4 }
    local si
    for si = 1, table.getn(sizes) do
        local need = sizes[si]
        local hi = 120
        while hi >= start + need - 1 do
            local lo = hi - need + 1
            if slotsFree(lo, hi) then return lo, need end
            hi = hi - 1
        end
    end
    return nil, nil
end

function IchaUI_HeroFocus(index)
    index = tonumber(index) or 1
    if index < 1 then index = 1 end
    local n = 1
    if IchaUIDB and type(IchaUIDB.heroExtras) == "table" then
        n = 1 + table.getn(IchaUIDB.heroExtras)
    end
    if index > n then index = 1 end
    focusBar = index
    ui.selected = 1
    ui.scroll = 0
end

function IchaUI_HeroBarCount()
    local n = 1
    if IchaUIDB and type(IchaUIDB.heroExtras) == "table" then
        n = 1 + table.getn(IchaUIDB.heroExtras)
    end
    return n
end

function IchaUI_HeroBarButtonIds(index)
    index = tonumber(index) or 1
    if index <= 1 then return IchaUI_HeroButtonIds() end
    local saved = focusBar
    focusBar = index
    local hs = ensure()
    local n, cols = IchaUI_HeroVisibleCount()
    local base = tonumber(hs.slotBase) or 0
    focusBar = saved
    local ids = {}
    local i
    for i = 0, n - 1 do
        local id = base + i
        if id >= 1 and id <= 120 then table.insert(ids, id) end
    end
    return ids, cols
end

function IchaUI_HeroBarGrid(index)
    index = tonumber(index) or 1
    if index <= 1 then
        if IchaUI_HeroPrimaryGrid then return IchaUI_HeroPrimaryGrid() end
        return 4, 2
    end
    local list = IchaUIDB and IchaUIDB.heroExtras
    local rec = list and list[index - 1]
    if type(rec) ~= "table" then return 4, 2 end
    return tonumber(rec.cols) or 4, tonumber(rec.rows) or 2
end

function IchaUI_HeroBarScale(index)
    index = tonumber(index) or 1
    if index <= 1 then
        if IchaUIDB and IchaUIDB.heroScale then
            return tonumber(IchaUIDB.heroScale) or 1.55
        end
        return 1.55
    end
    local list = IchaUIDB and IchaUIDB.heroExtras
    local rec = list and list[index - 1]
    if rec and rec.scale then return tonumber(rec.scale) or 1.55 end
    return 1.55
end

function IchaUI_HeroBarLook(index)
    index = tonumber(index) or 1
    local saved = focusBar
    focusBar = index
    local hs = ensure()
    local cols = tonumber(hs.cols) or 4
    local rows = tonumber(hs.rows) or 2
    local owned
    if index > 1 then
        owned = tonumber(hs.slotCount) or (cols * rows)
    else
        owned = IchaUI_HeroMaxSlots()
    end
    if not owned or owned < 1 then owned = 1 end
    if owned > 60 then owned = 60 end
    local slots = cols * rows
    if hs.buttonCount then slots = tonumber(hs.buttonCount) or slots end
    if slots < 1 then slots = 1 end
    if slots > owned then slots = owned end
    local scale = 1.55
    if index <= 1 then
        if IchaUIDB and IchaUIDB.heroScale then scale = tonumber(IchaUIDB.heroScale) or 1.55 end
    else
        scale = tonumber(hs.scale) or 1.55
    end
    if scale < 0.5 then scale = 0.5 end
    if scale > 3 then scale = 3 end
    local opacity = tonumber(hs.opacity)
    if not opacity then opacity = 1 end
    local fade = opacity
    if hs.fade ~= nil then fade = tonumber(hs.fade) or opacity end
    if opacity < 0 then opacity = 0 end
    if opacity > 1 then opacity = 1 end
    if fade < 0 then fade = 0 end
    if fade > 1 then fade = 1 end
    local gap = 2
    if IchaUI_LayoutGap then gap = IchaUI_LayoutGap end
    if hs.gap ~= nil then gap = tonumber(hs.gap) or gap end
    if gap < 0 then gap = 0 end
    if gap > 20 then gap = 20 end
    focusBar = saved
    return scale, opacity, fade, slots, cols, rows, owned, gap
end

function IchaUI_HeroBarSetStyle(index, scale, opacity, fade, gap)
    index = tonumber(index) or 1
    if IchaUI_HeroBarSetScale then IchaUI_HeroBarSetScale(index, scale) end
    local saved = focusBar
    focusBar = index
    local hs = ensure()
    opacity = tonumber(opacity) or 1
    if fade == nil then fade = opacity end
    fade = tonumber(fade) or opacity
    if opacity < 0 then opacity = 0 end
    if opacity > 1 then opacity = 1 end
    if fade < 0 then fade = 0 end
    if fade > 1 then fade = 1 end
    hs.opacity = opacity
    hs.fade = fade
    if gap ~= nil then
        gap = tonumber(gap) or 0
        if gap < 0 then gap = 0 end
        if gap > 20 then gap = 20 end
        hs.gap = gap
    end
    focusBar = saved
    if IchaUI_RequestLayout then IchaUI_RequestLayout() end
end

function IchaUI_HeroBarSetMenu(index, cols, rows, slots)
    index = tonumber(index) or 1
    local saved = focusBar
    focusBar = index
    local hs = ensure()
    local owned
    if index > 1 then
        owned = tonumber(hs.slotCount) or 1
    else
        owned = IchaUI_HeroMaxSlots()
    end
    if not owned or owned < 1 then owned = 1 end
    if owned > 60 then owned = 60 end
    slots = math.floor(tonumber(slots) or 1)
    cols = math.floor(tonumber(cols) or 1)
    rows = math.floor(tonumber(rows) or 1)
    if slots < 1 then slots = 1 end
    if slots > owned then slots = owned end
    if cols < 1 then cols = 1 end
    if cols > 12 then cols = 12 end
    if cols > slots then cols = slots end
    if rows < 1 then rows = 1 end
    if rows > 5 then rows = 5 end
    if rows > slots then rows = slots end
    local need = math.floor((slots + cols - 1) / cols)
    if rows < need then rows = need end
    if rows > 5 then
        rows = 5
        cols = math.floor((slots + 4) / 5)
        if cols < 1 then cols = 1 end
        if cols > 12 then cols = 12 end
        if cols > slots then cols = slots end
        need = math.floor((slots + cols - 1) / cols)
        if need > 5 then slots = cols * 5 end
        if slots > owned then slots = owned end
        rows = math.floor((slots + cols - 1) / cols)
        if rows > 5 then rows = 5 end
    end
    local prev = cols * rows
    if hs.buttonCount then prev = tonumber(hs.buttonCount) or prev end
    hs.buttonCount = slots
    focusBar = saved
    focusBar = index
    IchaUI_HeroSetGrid(cols, rows)
    hs = ensure()
    hs.buttonCount = slots
    local c = tonumber(hs.cols) or cols
    local r = tonumber(hs.rows) or rows
    if hs.buttonCount > c * r then hs.buttonCount = c * r end
    if hs.buttonCount < prev then dropOutside(c, r) end
    focusBar = saved
    if IchaUI_RequestLayout then IchaUI_RequestLayout() end
end

function IchaUI_HeroBarForm(index)
    index = tonumber(index) or 1
    local saved = focusBar
    focusBar = index
    local hs = ensure()
    focusBar = saved
    local shape, layout, spread, arc, rot = "square", "grid", 90, 360, 90
    if type(hs) == "table" then
        if hs.shape then shape = hs.shape end
        if hs.layout == "radial" then layout = "radial" end
        if hs.spread then spread = hs.spread end
        if hs.arc then arc = hs.arc end
        if hs.rot ~= nil then rot = hs.rot end
    end
    if IchaUI_FormShapeNorm then shape = IchaUI_FormShapeNorm(shape) end
    if IchaUI_DrawerNormSpread then spread = IchaUI_DrawerNormSpread(spread) end
    if IchaUI_DrawerNormArc then arc = IchaUI_DrawerNormArc(arc) end
    if IchaUI_DrawerNormRot then rot = IchaUI_DrawerNormRot(rot) end
    return shape, layout, spread, arc, rot
end

function IchaUI_HeroBarSetForm(index, shape, layout, spread, arc, rot)
    index = tonumber(index) or 1
    local saved = focusBar
    focusBar = index
    local hs = ensure()
    if shape then hs.shape = shape end
    if layout then hs.layout = layout end
    if spread then hs.spread = spread end
    if arc then hs.arc = arc end
    if rot ~= nil then hs.rot = rot end
    focusBar = saved
    if IchaUI_RefreshHeroBar then IchaUI_RefreshHeroBar(index) end
end

function IchaUI_HeroBarSetScale(index, v)
    index = tonumber(index) or 1
    v = tonumber(v) or 1.55
    if v < 0.5 then v = 0.5 end
    if v > 3 then v = 3 end
    if index <= 1 then
        if not IchaUIDB then IchaUIDB = {} end
        IchaUIDB.heroScale = v
        if SlashCmdList and SlashCmdList["ICHA"] then
            SlashCmdList["ICHA"]("heroscale " .. v)
        end
        return
    end
    local saved = focusBar
    focusBar = index
    local hs = ensure()
    hs.scale = v
    focusBar = saved
    if IchaUI_RefreshHeroBar then IchaUI_RefreshHeroBar(index) end
end

function IchaUI_HeroBarAdd()
    if not IchaUIDB then IchaUIDB = {} end
    if type(IchaUIDB.heroExtras) ~= "table" then IchaUIDB.heroExtras = {} end
    local list = IchaUIDB.heroExtras
    if table.getn(list) >= MAX_EXTRA_HEROES then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("IchaUI: 4 extra hero bars is the maximum.")
        end
        return nil
    end
    local base, count = allocExtraBlock()
    if not base then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("IchaUI: not enough action slots left for another hero bar.")
        end
        return nil
    end
    local scale = 1.55
    if IchaUIDB.heroScale then scale = tonumber(IchaUIDB.heroScale) or scale end
    local cols, rows = fitGrid(4, 2, count)
    local rec = {
        scale = scale,
        cols = cols,
        rows = rows,
        slotBase = base,
        slotCount = count,
        slots = {},
        posSlots = 1,
    }
    table.insert(list, rec)
    if IchaUI_RequestLayout then IchaUI_RequestLayout() end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("IchaUI: added hero " .. tostring(table.getn(list) + 1) .. " (" .. count .. " slots).")
    end
    return table.getn(list) + 1
end

function IchaUI_HeroBarRemove(index)
    index = tonumber(index) or 0
    if index <= 1 then return end
    if not IchaUIDB or type(IchaUIDB.heroExtras) ~= "table" then return end
    local list = IchaUIDB.heroExtras
    local rec = list[index - 1]
    if type(rec) ~= "table" then return end
    local saved = focusBar
    focusBar = index
    local hs = ensure()
    local s
    for s = 1, MAX_COLS * MAX_ROWS do
        local slot = hs.slots[s]
        if slot and slot.abs then
            local i
            for i = 1, table.getn(slot.abs) do
                if slot.abs[i] then applyEntryKey(slot.abs[i], "") end
            end
        end
    end
    local cap = tonumber(hs.slotCount) or 0
    local base = tonumber(hs.slotBase) or 0
    local i
    for i = 0, cap - 1 do
        clearAction(base + i)
    end
    focusBar = 1
    table.remove(list, index - 1)
    if saved >= index then saved = 1 end
    if saved > 1 and saved > table.getn(list) + 1 then saved = 1 end
    focusBar = saved
    if focusBar < 1 then focusBar = 1 end
    if IchaUI_RequestLayout then IchaUI_RequestLayout() end
    syncBarIcons()
end

function IchaUI_HeroSetup_Toggle()
    if not panel then buildPanel() end
    if panel:IsShown() then
        panel:Hide()
    else
        ui.pickFor = nil
        panel:Show()
        if IchaUI_HeroSetup_Refresh then IchaUI_HeroSetup_Refresh() end
    end
end

local evt = CreateFrame("Frame", "IchaUIHeroBindsEvent")
local didPlace = false
evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("PLAYER_ENTERING_WORLD")
evt:SetScript("OnEvent", function()
    ensure()
    applyAll()
    if not didPlace then
        placeLastIcons()
        didPlace = true
    end
end)
evt:SetScript("OnUpdate", function()
    if not pushBtnId then return end
    local now = GetTime and GetTime() or 0
    if now >= pushUntil then
        if releaseButton then releaseButton(pushBtnId) end
        pushBtnId = nil
    end
end)

function IchaUI_HeroReloadFromDB()
    normed = false
    ensure()
    applyAll()
    if IchaUI_RequestLayout then IchaUI_RequestLayout() end
end
