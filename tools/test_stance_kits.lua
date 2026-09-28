-- Lua 5.1 stand-in for the 1.12 kit swap. Run:
--   lua5.1 tools/test_stance_kits.lua shaman
--   lua5.1 tools/test_stance_kits.lua warrior
--   lua5.1 tools/test_stance_kits.lua partial
local mode = (arg and arg[1]) or "shaman"
local fails = 0
local function check(cond, msg)
    if not cond then
        fails = fails + 1
        io.stderr:write("FAIL: " .. msg .. "\n")
    end
end

local slots = {}
local cursor = nil
local tipName, tipRank = nil, nil
local frames = {}
local sounds = 0
local heroSync = 0
local heroReload = 0
local drawers = 0
local refreshN = 0

local spells = {
    { name = "Healing Wave", rank = "Rank 1", texture = "Interface\\Icons\\HW" },
    { name = "Healing Wave", rank = "Rank 3", texture = "Interface\\Icons\\HW" },
    { name = "Lightning Bolt", rank = "Rank 1", texture = "Interface\\Icons\\LB" },
    { name = "Attack", rank = nil, texture = "Interface\\Icons\\ATK" },
}
local macros = { [1] = "pot" }
local bags = {
    [0] = { [1] = { id = 5512, name = "Healthstone", texture = "Interface\\Icons\\HS" } },
}

local function copyCursor(src)
    if not src then return nil end
    local dst = {}
    local k, v
    for k, v in pairs(src) do dst[k] = v end
    return dst
end

function CreateFrame(kind, name)
    local f = { name = name, scripts = {} }
    function f:RegisterEvent() end
    function f:UnregisterEvent() end
    function f:SetScript(which, fn) self.scripts[which] = fn end
    function f:Hide() end
    function f:Show() end
    function f:ClearLines() end
    function f:SetOwner() end
    function f:SetAction(slot)
        local s = slots[slot]
        if not s then
            tipName, tipRank = nil, nil
        else
            tipName = s.spell
            tipRank = s.rank
        end
    end
    frames[name] = f
    return f
end

function getglobal(name)
    if name == "IchaUIStanceTipTextLeft1" then
        return { GetText = function() return tipName end }
    end
    if name == "IchaUIStanceTipTextRight1" then
        return { GetText = function() return tipRank end }
    end
    return nil
end

function HasAction(id) return slots[id] ~= nil end
function GetActionTexture(id)
    local s = slots[id]
    return s and s.texture or nil
end
function GetActionText(id)
    local s = slots[id]
    if s and s.kind == "macro" then return s.spell end
    return nil
end
function ClearCursor() cursor = nil end
function CursorHasSpell() return cursor and cursor.kind == "spell" end
function CursorHasItem() return cursor and cursor.kind == "item" end
function CursorHasMacro() return cursor and cursor.kind == "macro" end
function PickupAction(id)
    cursor = copyCursor(slots[id])
    slots[id] = nil
end
function PlaceAction(id)
    slots[id] = copyCursor(cursor)
    cursor = nil
    if PlaySound then PlaySound("CLICK") end
end
function PickupSpell(index, book)
    local s = spells[index]
    if not s then return end
    cursor = { kind = "spell", spell = s.name, rank = s.rank, texture = s.texture }
end
function PickupMacro(index)
    local name = macros[index]
    cursor = { kind = "macro", spell = name, texture = "Interface\\Icons\\INV_Misc_QuestionMark" }
end
function PickupContainerItem(bag, slot)
    local it = bags[bag] and bags[bag][slot]
    if not it then return end
    cursor = { kind = "item", itemId = it.id, spell = it.name, texture = it.texture }
end
function PickupInventoryItem(inv) end
BOOKTYPE_SPELL = "spell"
function GetSpellName(index, book)
    local s = spells[index]
    if not s then return nil end
    return s.name, s.rank
end
function GetSpellTexture(index, book)
    local s = spells[index]
    return s and s.texture or nil
end
function GetNumMacros() return 1, 0 end
function GetMacroInfo(index)
    local name = macros[index]
    if not name then return nil end
    return name, "Interface\\Icons\\INV_Misc_QuestionMark", "/use Healthstone"
end
function GetContainerNumSlots(bag)
    if bag == 0 then return 1 end
    return 0
end
function GetContainerItemLink(bag, slot)
    local it = bags[bag] and bags[bag][slot]
    if not it then return nil end
    return "|cff1eff00|Hitem:" .. it.id .. ":0:0:0|h[" .. it.name .. "]|h|r"
end
function GetContainerItemInfo(bag, slot)
    local it = bags[bag] and bags[bag][slot]
    if not it then return nil end
    return it.texture, 1
end
function GetItemInfo(id)
    id = tonumber(id)
    local bag, slot
    for bag = 0, 4 do
        local n = GetContainerNumSlots(bag)
        for slot = 1, n do
            local it = bags[bag][slot]
            if it and it.id == id then
                return it.name, "item:" .. id .. ":0:0:0", 1, 1, nil, nil, nil, nil, it.texture
            end
        end
    end
    return nil
end
function PlaySound() sounds = sounds + 1 end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function UnitClass()
    if mode == "warrior" then return "Warrior", "WARRIOR" end
    return "Shaman", "SHAMAN"
end
function GetBonusBarOffset()
    if mode == "warrior" then return 2 end
    return 0
end
function IchaUI_ActionBarCount() return 2 end
function IchaUI_RequestLayout() refreshN = refreshN + 1 end
function IchaUI_RefreshActionBar() refreshN = refreshN + 1 end
function IchaUI_RefreshHeroBar() end
function IchaUI_HeroReloadFromDB() heroReload = heroReload + 1 end
function IchaUI_HeroSyncIcons() heroSync = heroSync + 1 end
function IchaUI_CustomDrawers_Apply() drawers = drawers + 1 end

local function putSpell(id, index)
    local s = spells[index]
    slots[id] = { kind = "spell", spell = s.name, rank = s.rank, texture = s.texture }
end
local function putItem(id)
    local it = bags[0][1]
    slots[id] = { kind = "item", itemId = it.id, spell = it.name, texture = it.texture }
end
local function putMacro(id)
    slots[id] = { kind = "macro", spell = "pot", texture = "Interface\\Icons\\INV_Misc_QuestionMark" }
end

IchaUIDB = {
    heroSetup = { cols = 6, rows = 2, slots = { [1] = { abs = { { spell = "Attack" } } } } },
    stance = { actionMaps = { [1] = { [1] = 6 } } },
}

putSpell(1, 2) -- Healing Wave Rank 3
putMacro(2)
putItem(3)
putSpell(13, 3) -- bar 2 Lightning Bolt
slots[73] = { kind = "spell", spell = "SENTINEL", rank = "Rank 1", texture = "Interface\\Icons\\NO" }

dofile("IchaUI/Stance.lua")

local function slotSpell(id)
    local s = slots[id]
    if not s then return nil, nil, nil end
    return s.kind, s.spell, s.rank
end

if mode == "warrior" then
    local fr = frames.IchaUIStanceEvent
    event = "PLAYER_ENTERING_WORLD"
    fr.scripts.OnEvent()
    check(fr.scripts.OnUpdate ~= nil, "boot waits on OnUpdate")
    fr.scripts.OnUpdate()
    check(fr.scripts.OnUpdate == nil, "boot OnUpdate cleared")
    check(IchaUIDB.stance._kitsSeeded == true, "warrior kits seeded")
    check(IchaUIDB.stance.applied == 2, "applied is defensive stance, got " .. tostring(IchaUIDB.stance.applied))
    check(IchaUIDB.stance.drawerFollowHero == false, "drawers forced off")
    local k0 = IchaUIDB.stance.actionKits[1][0].slots[1]
    local k2 = IchaUIDB.stance.actionKits[1][2].slots[1]
    check(k0 and k0.spell == "Healing Wave" and k0.rank == "Rank 3", "page 0 seeded from live bar")
    check(k2 and k2.spell == "Healing Wave" and k2.rank == "Rank 3", "current form seeded from live bar")
    check(IchaUIDB.stance.actionKits[1][1] == nil, "other warrior pages start empty")
    local kind, name, rank = slotSpell(1)
    check(kind == "spell" and name == "Healing Wave" and rank == "Rank 3", "login did not wipe the live bar")
    check(slots[73] and slots[73].spell == "SENTINEL", "seed did not touch offset slot 73")
    check(IchaUI_GetPagedID(1, 1) == 1, "GetPagedID stays 1")
    check(IchaUI_StanceOffset(1) == 0, "offset API is 0")
    local soundsBefore = sounds
    IchaUI_StanceSetSim(1)
    check(sounds == soundsBefore, "place/clear did not play the UI click")
    PlaySound()
    check(sounds == soundsBefore + 1, "PlaySound restored after the swap")
    check(slots[1] == nil, "sim 1 clears the bar (empty kit)")
    check(slots[73] and slots[73].spell == "SENTINEL", "sim did not pull the old offset slot")
    check(drawers == 0, "drawers were not applied")
    check(heroSync >= 1 and heroReload >= 1, "hero page was rebound and placed")
    check(IchaUIDB.heroSetup == IchaUIDB.stance.heroPages[1], "heroSetup is the sim page")
    check(IchaUIDB.heroSetup.cols == 6 and IchaUIDB.heroSetup.rows == 2, "hero page kept 6x2")
    IchaUI_StanceSetSim(nil)
    kind, name, rank = slotSpell(1)
    check(kind == "spell" and name == "Healing Wave" and rank == "Rank 3", "clear sim restores defensive kit")
    check(IchaUI_StanceState() == 2, "live state is 2")
elseif mode ~= "partial" then
    check(IchaUI_GetPagedID(1) == 1, "identity before sim")
    check(IchaUI_GetPagedID(12, 1) == 12, "identity with bar id")
    IchaUI_StanceSetMap(1, 1, 9)
    check(IchaUI_GetPagedID(1, 1) == 1, "SetMap does not page")
    check(IchaUI_StanceOffset(1) == 0, "StanceOffset is 0 despite saved map 6")

    IchaUI_StanceSetSim(0)
    check(IchaUIDB.stance.applied == 0, "shaman applied page 0")
    check(IchaUIDB.stance.actionKits[1][0].slots[1].spell == "Healing Wave", "kit captured rank 3 spell")
    check(IchaUIDB.stance.actionKits[1][0].slots[1].rank == "Rank 3", "rank stored")
    check(IchaUIDB.stance.actionKits[1][0].slots[2].kind == "macro", "macro captured")
    check(IchaUIDB.stance.actionKits[1][0].slots[3].kind == "item", "item captured")
    check(IchaUIDB.stance.actionKits[1][0].slots[3].itemId == 5512, "item id from bag 0")
    check(IchaUIDB.stance.actionKits[2][0].slots[1].spell == "Lightning Bolt", "bar 2 captured")
    check(IchaUIDB.heroSetup == IchaUIDB.stance.heroPages[0], "hero page 0 is live")
    check(IchaUIDB.heroSetup.cols == 6, "hero dims from live setup")
    check(drawers == 0, "no drawer follow")

    local soundsBefore = sounds
    IchaUI_StanceSetSim(1)
    check(sounds == soundsBefore, "swap muted PlaySound")
    PlaySound()
    check(sounds == soundsBefore + 1, "PlaySound restored")
    check(slots[1] == nil and slots[2] == nil and slots[3] == nil, "sim 1 emptied bar 1")
    check(slots[13] == nil, "sim 1 emptied bar 2")
    check(slots[73] and slots[73].spell == "SENTINEL", "offset slot left alone")
    check(IchaUI_GetPagedID(1, 1) == 1, "still identity while simming")
    check(heroSync >= 1, "hero icons synced")
    check(IchaUIDB.heroSetup == IchaUIDB.stance.heroPages[1], "hero page 1 showing")
    check(IchaUIDB.heroSetup.cols == 6 and IchaUIDB.heroSetup.rows == 2, "sim page did not shrink")
    check(IchaUIDB.stance.drawerFollowHero == false, "drawer flag forced")
    check(refreshN > 0, "bars refreshed on sim")

    putSpell(1, 4) -- user drops Attack while simming 1
    local fr = frames.IchaUIStanceEvent
    event = "PLAYER_LEAVING_WORLD"
    fr.scripts.OnEvent()
    local saved = IchaUIDB.stance.actionKits[1][1].slots[1]
    check(saved and saved.spell == "Attack", "logout snapshot kept the sim edit")

    IchaUI_StanceSetSim(0)
    local kind, name, rank = slotSpell(1)
    check(kind == "spell" and name == "Healing Wave" and rank == "Rank 3", "back to rank 3, not rank 1")
    kind, name = slotSpell(2)
    check(kind == "macro" and name == "pot", "macro restored")
    kind, name = slotSpell(3)
    check(kind == "item" and name == "Healthstone", "item restored from bag 0")
    kind, name = slotSpell(13)
    check(kind == "spell" and name == "Lightning Bolt", "bar 2 restored")
    check(slots[73].spell == "SENTINEL", "sentinel still untouched")

    IchaUI_StanceSetSim(1)
    kind, name = slotSpell(1)
    check(kind == "spell" and name == "Attack", "sim 1 kit came back")

    IchaUI_StanceCopyKits(1, 2)
    IchaUI_StanceSetSim(2)
    kind, name = slotSpell(1)
    check(kind == "spell" and name == "Attack", "copy page placed the kit")
    IchaUI_StanceClearKits(2, 1)
    check(slots[1] == nil, "clear this bar kit emptied bar 1")
    check(slots[13] == nil, "bar 2 stays on the copied empty kit")

    IchaUI_StanceSetSim(0)
    -- cursor blocks the next swap
    local blocked = true
    CursorHasSpell = function() return blocked end
    local before = slots[1] and slots[1].spell
    IchaUI_StanceSetSim(1)
    check(slots[1] and slots[1].spell == before, "busy cursor defers the kit swap")
    check(frames.IchaUIStanceEvent.scripts.OnUpdate ~= nil, "defer uses OnUpdate only while pending")
    blocked = false
    frames.IchaUIStanceEvent.scripts.OnUpdate()
    check(frames.IchaUIStanceEvent.scripts.OnUpdate == nil, "OnUpdate cleared after the swap")
    check(slots[1] and slots[1].spell == "Attack", "deferred sim landed")
    check(drawers == 0, "drawers still ignored")
else
    -- Login with a full bar, then logout while only one slot still HasAction.
    putSpell(4, 3)
    local fr = frames.IchaUIStanceEvent
    event = "PLAYER_ENTERING_WORLD"
    fr.scripts.OnEvent()
    fr.scripts.OnUpdate()
    check(fr.scripts.OnUpdate == nil, "partial boot OnUpdate cleared")
    local kit = IchaUIDB.stance.actionKits[1][0]
    check(kit and kit.slots[1].spell == "Healing Wave", "partial seed slot 1")
    check(kit.slots[2].kind == "macro", "partial seed slot 2")
    check(kit.slots[3].kind == "item", "partial seed slot 3")
    check(kit.slots[4].spell == "Lightning Bolt", "partial seed slot 4")
    check(IchaUIDB.stance.actionKits[2][0].slots[1].spell == "Lightning Bolt", "partial seed bar 2")

    -- One leftover HasAction, and that leftover even changed. Fresh count is
    -- lower, so the whole denser kit stays (including the previous slot 1).
    putSpell(1, 4)
    slots[2] = nil
    slots[3] = nil
    slots[4] = nil
    slots[13] = nil
    event = "PLAYER_LEAVING_WORLD"
    fr.scripts.OnEvent()
    kit = IchaUIDB.stance.actionKits[1][0].slots
    check(kit[1].spell == "Healing Wave", "sparse logout kept the prior slot 1")
    check(kit[2].kind == "macro", "sparse logout kept slot 2")
    check(kit[3].kind == "item", "sparse logout kept slot 3")
    check(kit[4].spell == "Lightning Bolt", "sparse logout kept slot 4")
    check(IchaUIDB.stance.actionKits[2][0].slots[1].spell == "Lightning Bolt", "fully empty bar 2 kept its kit")

    -- Same filled-count still writes. Bar 2 empty is the fully-empty refuse.
    putSpell(1, 4)
    putMacro(2)
    putItem(3)
    putSpell(4, 3)
    slots[13] = nil
    event = "PLAYER_LOGOUT"
    fr.scripts.OnEvent()
    kit = IchaUIDB.stance.actionKits[1][0].slots
    check(kit[1].spell == "Attack", "equal count logout saved the live edit")
    check(kit[2].kind == "macro" and kit[4].spell == "Lightning Bolt", "equal count kept the other slots")
    check(IchaUIDB.stance.actionKits[2][0].slots[1].spell == "Lightning Bolt", "empty bar still refused")

    -- Every owned slot empty: early return, kits unchanged.
    slots[1] = nil
    slots[2] = nil
    slots[3] = nil
    slots[4] = nil
    event = "PLAYER_LOGOUT"
    fr.scripts.OnEvent()
    kit = IchaUIDB.stance.actionKits[1][0].slots
    check(kit[1].spell == "Attack", "all-empty logout did not wipe bar 1")
    check(kit[4].spell == "Lightning Bolt", "all-empty logout did not wipe slot 4")

    -- Not a logout: a sparser in-world snapshot (stance swap) still saves the clear.
    putSpell(1, 4)
    putMacro(2)
    putItem(3)
    slots[4] = nil
    IchaUI_StanceSetSim(1)
    kit = IchaUIDB.stance.actionKits[1][0].slots
    check(kit[4].empty == 1, "stance swap wrote the real clear")
    check(kit[1].spell == "Attack" and kit[2].kind == "macro", "stance swap kept the filled slots")
    check(IchaUIDB.stance.applied == 1, "swap moved to the other page")
    check(IchaUIDB.stance.actionKits[1][1].slots[1].empty == 1, "other page was not the applied kit")
end

if fails > 0 then
    io.stderr:write(mode .. ": " .. fails .. " failed\n")
    os.exit(1)
end
print(mode .. ": ok")
