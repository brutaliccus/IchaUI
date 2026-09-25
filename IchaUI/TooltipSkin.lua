-- IchaUI gold chrome for GameTooltip + common tip frames (Lua 5.0 / 1.12)

-- Circle-button gold on the near-white tooltip edge (not TrackingBorder).
local GOLD = { 0.75, 0.52, 0.04, 1 }
local BG = { 0.05, 0.05, 0.06, 0.92 }
local enabled = true
local edgeSize = 12
local hooked = {}

local function db()
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.tooltipSkin then IchaUIDB.tooltipSkin = {} end
    return IchaUIDB.tooltipSkin
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

-- Vendor coins: GameTooltipMoneyFrame is a child of the tip. SetBackdrop paints
-- the fill above that child, so the sell price sits behind the window. A real
-- AddLine is measured with the other rows and draws above the backdrop.
local prevSetTooltipMoney = nil
local moneyHooked = false

local function formatOneCoin(pattern, amount, suffix)
    local chunk = nil
    if type(pattern) == "string" then
        local n = 0
        local function countSpecs()
            local _, c = string.gsub(pattern, "%%[%d%.]*[dsf]", "")
            n = c or 0
        end
        pcall(countSpecs)
        if n >= 3 then
            local ok = pcall(function()
                chunk = string.format(pattern, amount, 0, 0)
            end)
            if not ok then chunk = nil end
        end
        if not chunk and n >= 1 then
            local ok = pcall(function()
                chunk = string.format(pattern, amount)
            end)
            if not ok then chunk = nil end
        end
    end
    if type(chunk) ~= "string" or chunk == "" then
        chunk = tostring(amount) .. suffix
    end
    return chunk
end

local function coinText(copper)
    if type(copper) ~= "number" or copper <= 0 then return nil end
    copper = math.floor(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor(math.mod(copper, 10000) / 100)
    local cop = math.mod(copper, 100)
    local text = ""
    local function add(amount, pattern, suffix)
        if not amount or amount <= 0 then return end
        if text ~= "" then text = text .. " " end
        text = text .. formatOneCoin(pattern, amount, suffix)
    end
    -- Client money strings embed the coin icons. If a string is missing, use the
    -- same MoneyFrame art (UI-GoldIcon, UI-SilverIcon, UI-CopperIcon).
    local function iconPattern(pat, file)
        if type(pat) == "string" and string.find(pat, "|T", 1, true) then
            return pat
        end
        return "%d|TInterface\\MoneyFrame\\" .. file .. ":0:0:2:0|t"
    end
    add(gold, iconPattern(GOLD_AMOUNT_TEXTURE, "UI-GoldIcon"), "g")
    add(silver, iconPattern(SILVER_AMOUNT_TEXTURE, "UI-SilverIcon"), "s")
    add(cop, iconPattern(COPPER_AMOUNT_TEXTURE, "UI-CopperIcon"), "c")
    if text == "" then return nil end
    return text
end

local function isSellText(prefixText)
    if type(prefixText) ~= "string" or prefixText == "" then return false end
    if SELL_PRICE and string.find(prefixText, SELL_PRICE, 1, true) then return true end
    local low = string.lower(prefixText)
    if string.find(low, "sell", 1, true) then return true end
    return false
end

local function sellLabel()
    if type(SELL_PRICE) == "string" and SELL_PRICE ~= "" then
        if string.sub(SELL_PRICE, -1) == ":" then return SELL_PRICE end
        return SELL_PRICE .. ":"
    end
    return "Sell Price:"
end

local function addMoneyLine(frame, copper, prefixText, moneyType)
    if not frame or not frame.AddLine then return false end
    local coins = coinText(copper)
    if not coins then return false end
    local r, g, b = 1, 1, 1
    if not isSellText(prefixText) and moneyType ~= "STATIC" and type(GetMoney) == "function" then
        local have = nil
        local function readMoney()
            have = GetMoney()
        end
        local ok = pcall(readMoney)
        if ok and type(have) == "number" and have < copper then
            r, g, b = 1, 0.1, 0.1
        end
    end
    local line = coins
    if type(prefixText) == "string" and prefixText ~= "" then
        line = prefixText
        if string.sub(prefixText, -1) ~= " " then
            line = line .. " "
        end
        line = line .. coins
    end
    frame:AddLine(line, r, g, b)
    frame.hasMoney = 1
    frame._ichaMoneyText = true
    local function widen()
        if not frame.GetName or not frame.NumLines or not frame.SetMinimumWidth then return end
        local name = frame:GetName()
        local n = frame:NumLines()
        if not name or not n then return end
        local fs = getglobal(name .. "TextLeft" .. n)
        if not fs or not fs.GetStringWidth then return end
        local w = fs:GetStringWidth() or 0
        local need = w + 28
        local cur = 0
        if frame.GetMinimumWidth then cur = frame:GetMinimumWidth() or 0 end
        if need > cur then frame:SetMinimumWidth(need) end
    end
    pcall(widen)
    return true
end

local function tipName(tip)
    if not tip or not tip.GetName then return nil end
    local n = tip:GetName()
    if type(n) ~= "string" or n == "" then return nil end
    return n
end

local function raiseMoneyFrame(mf, tip)
    if not mf then return end
    local level = 20
    if tip and tip.GetFrameLevel then
        level = (tip:GetFrameLevel() or 1) + 20
    end
    if mf.SetFrameStrata then mf:SetFrameStrata("TOOLTIP") end
    if mf.SetFrameLevel then mf:SetFrameLevel(level) end
    if not mf.GetChildren then return end
    local kids = { mf:GetChildren() }
    local i
    for i = 1, table.getn(kids) do
        local k = kids[i]
        if k then
            if k.SetFrameStrata then k:SetFrameStrata("TOOLTIP") end
            if k.SetFrameLevel then k:SetFrameLevel(level + 1) end
        end
    end
end

local function buttonAmount(button)
    if not button then return 0 end
    if button.IsShown and not button:IsShown() then return 0 end
    local fs = nil
    if button.GetName then
        fs = getglobal(button:GetName() .. "Text")
    end
    if not fs and button.GetFontString then
        local function grab()
            fs = button:GetFontString()
        end
        pcall(grab)
    end
    if not fs or not fs.GetText then return 0 end
    local n = tonumber(fs:GetText() or "")
    if not n or n <= 0 then return 0 end
    return n
end

local function readMoneyFrame(mf)
    local mfName = mf and mf.GetName and mf:GetName()
    if type(mfName) ~= "string" then return nil, false end
    local gb = getglobal(mfName .. "GoldButton")
    local sb = getglobal(mfName .. "SilverButton")
    local cb = getglobal(mfName .. "CopperButton")
    if not gb and not sb and not cb then
        return nil, false
    end
    local total = buttonAmount(gb) * 10000 + buttonAmount(sb) * 100 + buttonAmount(cb)
    return total, true
end

local function prefixFromMoneyFrame(mf)
    local mfName = mf and mf.GetName and mf:GetName()
    if type(mfName) ~= "string" then return nil end
    local pre = getglobal(mfName .. "PrefixText")
    if pre and pre.GetText then
        local t = pre:GetText()
        if type(t) == "string" and t ~= "" then return t end
    end
    return nil
end

local function eachMoneyFrame(tip, fn)
    local name = tipName(tip)
    if not name then return end
    local plain = getglobal(name .. "MoneyFrame")
    if plain then fn(plain) end
    local i
    for i = 1, 30 do
        local mf = getglobal(name .. "MoneyFrame" .. i)
        if mf then fn(mf) end
    end
end

local function hideMoneyFrames(tip)
    eachMoneyFrame(tip, function(mf)
        if mf.Hide then mf:Hide() end
    end)
    if not tip or not tip.GetChildren then return end
    local kids = { tip:GetChildren() }
    local i
    for i = 1, table.getn(kids) do
        local k = kids[i]
        if k and k.GetName and k.Hide then
            local n = k:GetName()
            if type(n) == "string" then
                if string.find(n, "MoneyFrame", 1, true)
                    or string.find(n, "GoldButton", 1, true)
                    or string.find(n, "SilverButton", 1, true)
                    or string.find(n, "CopperButton", 1, true) then
                    k:Hide()
                end
            end
        end
    end
end

local function tuckMoneyFrames(tip)
    if not tip then return end
    eachMoneyFrame(tip, function(mf)
        if tip._ichaMoneyText then
            if mf.Hide then mf:Hide() end
        else
            raiseMoneyFrame(mf, tip)
        end
    end)
end

-- Stock 1.12 GetItemInfo has no sell price. SuperWoW / later clients append it
-- after the icon path. A missing or zero price is not shown.
local function lookupSellPrice(item)
    if item == nil or item == "" or type(GetItemInfo) ~= "function" then return nil end
    local price = nil
    local function grab()
        local ret = { GetItemInfo(item) }
        local a9, a10, a11 = ret[9], ret[10], ret[11]
        local function afterIcon(icon, amount)
            if type(amount) ~= "number" or type(icon) ~= "string" then return false end
            if string.find(icon, "Interface", 1, true) or string.find(icon, "\\", 1, true) then
                price = amount
                return true
            end
            return false
        end
        if not afterIcon(a10, a11) then
            afterIcon(a9, a10)
        end
    end
    local ok = pcall(grab)
    if not ok then return nil end
    if type(price) ~= "number" or price <= 0 then return nil end
    return math.floor(price)
end

local function priceFromTooltipName(tip)
    local name = tipName(tip)
    if not name then return nil end
    local line2 = getglobal(name .. "TextLeft2")
    if line2 and line2.GetText then
        local t2 = line2:GetText()
        if type(t2) == "string" and string.find(t2, "^Level %d") then
            return nil
        end
    end
    local fs = getglobal(name .. "TextLeft1")
    if not fs or not fs.GetText then return nil end
    local text = fs:GetText()
    if type(text) ~= "string" or text == "" then return nil end
    return lookupSellPrice(text)
end

local function tooltipHasSellText(tip)
    local name = tipName(tip)
    if not name or not tip.NumLines then return false end
    local n = tip:NumLines() or 0
    if n > 30 then n = 30 end
    local needle = "sell price"
    if type(SELL_PRICE) == "string" and SELL_PRICE ~= "" then
        needle = string.lower(SELL_PRICE)
    end
    local i
    for i = 1, n do
        local fs = getglobal(name .. "TextLeft" .. i)
        local t = fs and fs.GetText and fs:GetText()
        if type(t) == "string" then
            local low = string.lower(t)
            if string.find(low, needle, 1, true) then
                if string.find(t, "|T", 1, true) or string.find(low, "%d") then
                    return true
                end
            end
        end
    end
    return false
end

local function relayoutTip(tip)
    if not tip or not tip.Show or tip._ichaGrew then return end
    local n = tipName(tip)
    -- Shopping tips are sized by SetInventoryItem. A second Show puts the
    -- money frame and stock border back on top of the lines.
    if n == "ShoppingTooltip1" or n == "ShoppingTooltip2" then
        tip._ichaGrew = true
        return
    end
    if tip.IsShown and not tip:IsShown() then return end
    tip._ichaSellBusy = true
    tip._ichaGrew = true
    tip:Show()
    tip._ichaSellBusy = nil
end

local function absorbMoneyFrames(tip)
    local added = false
    eachMoneyFrame(tip, function(mf)
        if mf.IsShown and not mf:IsShown() then return end
        local total, parsed = readMoneyFrame(mf)
        if parsed and total and total > 0 then
            if addMoneyLine(tip, total, prefixFromMoneyFrame(mf), "STATIC") then
                added = true
                if mf.Hide then mf:Hide() end
            else
                raiseMoneyFrame(mf, tip)
            end
        elseif parsed or tip._ichaMoneyText then
            if mf.Hide then mf:Hide() end
        else
            raiseMoneyFrame(mf, tip)
        end
    end)
    return added
end

local function ensureVendorLine(tip)
    if not tip or tip._ichaSellBusy then return end
    if tip._ichaMoneyText or tooltipHasSellText(tip) then
        tip._ichaMoneyText = true
        hideMoneyFrames(tip)
        relayoutTip(tip)
        return
    end
    local added = absorbMoneyFrames(tip)
    if not added then
        local price = nil
        if tip._ichaItem then
            price = lookupSellPrice(tip._ichaItem)
        end
        if not price then
            price = priceFromTooltipName(tip)
        end
        if price and price > 0 then
            added = addMoneyLine(tip, price, sellLabel(), "STATIC")
        end
    end
    if added then
        hideMoneyFrames(tip)
        relayoutTip(tip)
    end
end

local function hookSetTooltipMoney()
    if moneyHooked or type(SetTooltipMoney) ~= "function" then return end
    moneyHooked = true
    prevSetTooltipMoney = SetTooltipMoney
    SetTooltipMoney = function(frame, money, moneyType, prefixText)
        if frame and frame._ichaAddingMoney then
            if prevSetTooltipMoney then
                return prevSetTooltipMoney(frame, money, moneyType, prefixText)
            end
            return
        end
        local amount = money
        if type(amount) == "string" then amount = tonumber(amount) end
        if type(amount) ~= "number" or amount <= 0 then
            if frame then hideMoneyFrames(frame) end
            return
        end
        if frame and (frame._ichaMoneyText or tooltipHasSellText(frame)) then
            frame._ichaMoneyText = true
            hideMoneyFrames(frame)
            return
        end
        if frame and frame.AddLine then
            frame._ichaPlaceOk = nil
            frame._ichaAddingMoney = true
            local ok = pcall(function()
                frame._ichaPlaceOk = addMoneyLine(frame, amount, prefixText, moneyType)
            end)
            frame._ichaAddingMoney = nil
            if ok and frame._ichaPlaceOk then
                frame._ichaPlaceOk = nil
                hideMoneyFrames(frame)
                relayoutTip(frame)
                return
            end
            frame._ichaPlaceOk = nil
        end
        if prevSetTooltipMoney then
            return prevSetTooltipMoney(frame, money, moneyType, prefixText)
        end
    end
end

local updateCompare
local compareOwner = nil

local function wantsCompare(tip)
    local n = tipName(tip)
    if n == "GameTooltip" or n == "ItemRefTooltip" then return true end
    if n == "AtlasLootTooltip" or n == "LootLinkTooltip" then return true end
    return false
end

local function hideCompare(tip)
    if tip and compareOwner and compareOwner ~= tip then return end
    compareOwner = nil
    local s1 = getglobal("ShoppingTooltip1")
    local s2 = getglobal("ShoppingTooltip2")
    if s1 and s1.Hide then s1:Hide() end
    if s2 and s2.Hide then s2:Hide() end
end

local function clearTipMoneyState(tip)
    if not tip then return end
    tip._ichaMoneyText = nil
    tip._ichaSellBusy = nil
    tip._ichaGrew = nil
    tip._ichaItem = nil
    tip._ichaPlaceOk = nil
    tip._ichaInvSlot = nil
end

local function rememberItemLink(tip, which, a, b)
    if not tip then return end
    local link = nil
    local function grab()
        if which == "bag" and type(GetContainerItemLink) == "function" then
            link = GetContainerItemLink(a, b)
        elseif which == "inv" and type(GetInventoryItemLink) == "function" then
            link = GetInventoryItemLink(a, b)
        elseif which == "link" then
            link = a
        elseif which == "loot" and type(GetLootSlotLink) == "function" then
            link = GetLootSlotLink(a)
        elseif which == "roll" and type(GetLootRollItemLink) == "function" then
            link = GetLootRollItemLink(a)
        elseif which == "quest" and type(GetQuestItemLink) == "function" then
            link = GetQuestItemLink(a, b)
        elseif which == "questlog" and type(GetQuestLogItemLink) == "function" then
            link = GetQuestLogItemLink(a, b)
        elseif which == "merchant" and type(GetMerchantItemLink) == "function" then
            link = GetMerchantItemLink(a)
        end
    end
    local ok = pcall(grab)
    if ok and link and link ~= "" then
        tip._ichaItem = link
    end
end

local function hookSetter(tip, method, which)
    if not tip or not tip[method] or tip["_ichaHs" .. method] then return end
    tip["_ichaHs" .. method] = true
    local orig = tip[method]
    -- Paperdoll keeps the gear tip only when SetInventoryItem returns hasItem.
    -- Dropping that return makes the slot call SetText and the tip goes blank.
    tip[method] = function(self, a, b, c)
        clearTipMoneyState(self)
        local r1, r2, r3
        if c ~= nil then
            r1, r2, r3 = orig(self, a, b, c)
        elseif b ~= nil then
            r1, r2, r3 = orig(self, a, b)
        else
            r1, r2, r3 = orig(self, a)
        end
        rememberItemLink(self, which, a, b)
        if which == "inv" and a == "player" then
            self._ichaInvSlot = b
        end
        if which == "inv" and not r1 and a == "player" and type(b) == "number" then
            local linked = nil
            local function probeLink()
                if type(GetInventoryItemLink) == "function" then
                    linked = GetInventoryItemLink("player", b)
                end
            end
            local pok = pcall(probeLink)
            if pok and linked and linked ~= "" then
                local named = tipName(self)
                local fs = named and getglobal(named .. "TextLeft1")
                local txt = fs and fs.GetText and fs:GetText()
                if type(txt) == "string" and txt ~= "" then
                    r1 = 1
                end
            end
        end
        pcall(ensureVendorLine, self)
        if updateCompare and wantsCompare(self) then
            pcall(updateCompare, self)
        end
        return r1, r2, r3
    end
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

local function skinStatusBar(bar)
    if not bar then return end
    pcall(function()
        if bar.SetStatusBarColor then
            -- keep Blizzard fill; only chrome the border if present
        end
        if bar.SetBackdrop then
            applyBackdrop(bar, 0.85, 8)
        end
        -- Named border textures often used on GameTooltipStatusBar
        local n = bar.GetName and bar:GetName()
        if n then
            local border = getglobal(n .. "Border")
            if border and border.SetVertexColor then
                if IchaUI_PaintGoldVertex then
                    IchaUI_PaintGoldVertex(border, 0.75, 0.52, 0.04, 1)
                else
                    border:SetVertexColor(0.75, 0.52, 0.04, 1)
                end
            end
        end
        if bar.GetRegions then
            local regions = { bar:GetRegions() }
            local i
            for i = 1, table.getn(regions) do
                local r = regions[i]
                if r and r.GetObjectType and r:GetObjectType() == "Texture" then
                    local rn = r.GetName and r:GetName()
                    if rn and string.find(string.lower(rn), "border", 1, true) then
                        if r.SetVertexColor then
                            if IchaUI_PaintGoldVertex then
                                IchaUI_PaintGoldVertex(r, 0.75, 0.52, 0.04, 1)
                            else
                                r:SetVertexColor(0.75, 0.52, 0.04, 1)
                            end
                        end
                    end
                end
            end
        end
    end)
end

local function skinOne(tip)
    if not tip then return end
    pcall(function()
        applyBackdrop(tip, BG[4], edgeSize)
        tuckMoneyFrames(tip)
        local n = tip.GetName and tip:GetName()
        if n == "GameTooltip" or (n and string.find(n, "GameTooltip", 1, true)) then
            skinStatusBar(getglobal("GameTooltipStatusBar") or tip.StatusBar)
        end
    end)
end

-- Equip location -> paperdoll slot names. Second entry is the other ring,
-- trinket, or weapon. 2H shows both hands because it replaces both.
local EQUIP_ROWS = {
    { "INVTYPE_HEAD", { "HeadSlot" } },
    { "INVTYPE_NECK", { "NeckSlot" } },
    { "INVTYPE_SHOULDER", { "ShoulderSlot" } },
    { "INVTYPE_BODY", { "ShirtSlot" } },
    { "INVTYPE_CHEST", { "ChestSlot" } },
    { "INVTYPE_ROBE", { "ChestSlot" } },
    { "INVTYPE_WAIST", { "WaistSlot" } },
    { "INVTYPE_LEGS", { "LegsSlot" } },
    { "INVTYPE_FEET", { "FeetSlot" } },
    { "INVTYPE_WRIST", { "WristSlot" } },
    { "INVTYPE_HAND", { "HandsSlot" } },
    { "INVTYPE_FINGER", { "Finger0Slot", "Finger1Slot" } },
    { "INVTYPE_TRINKET", { "Trinket0Slot", "Trinket1Slot" } },
    { "INVTYPE_CLOAK", { "BackSlot" } },
    { "INVTYPE_WEAPON", { "MainHandSlot", "SecondaryHandSlot" } },
    { "INVTYPE_SHIELD", { "SecondaryHandSlot" } },
    { "INVTYPE_2HWEAPON", { "MainHandSlot", "SecondaryHandSlot" } },
    { "INVTYPE_WEAPONMAINHAND", { "MainHandSlot" } },
    { "INVTYPE_WEAPONOFFHAND", { "SecondaryHandSlot" } },
    { "INVTYPE_HOLDABLE", { "SecondaryHandSlot" } },
    { "INVTYPE_RANGED", { "RangedSlot" } },
    { "INVTYPE_THROWN", { "RangedSlot" } },
    { "INVTYPE_RANGEDRIGHT", { "RangedSlot" } },
    { "INVTYPE_RELIC", { "RangedSlot" } },
    { "INVTYPE_TABARD", { "TabardSlot" } },
    { "INVTYPE_AMMO", { "AmmoSlot" } },
    { "INVTYPE_QUIVER", { "AmmoSlot" } },
}

local PAPER_ROWS = {
    { "HeadSlot", { "HeadSlot" } },
    { "NeckSlot", { "NeckSlot" } },
    { "ShoulderSlot", { "ShoulderSlot" } },
    { "ShirtSlot", { "ShirtSlot" } },
    { "ChestSlot", { "ChestSlot" } },
    { "WaistSlot", { "WaistSlot" } },
    { "LegsSlot", { "LegsSlot" } },
    { "FeetSlot", { "FeetSlot" } },
    { "WristSlot", { "WristSlot" } },
    { "HandsSlot", { "HandsSlot" } },
    { "Finger0Slot", { "Finger0Slot", "Finger1Slot" } },
    { "Finger1Slot", { "Finger0Slot", "Finger1Slot" } },
    { "Trinket0Slot", { "Trinket0Slot", "Trinket1Slot" } },
    { "Trinket1Slot", { "Trinket0Slot", "Trinket1Slot" } },
    { "BackSlot", { "BackSlot" } },
    { "MainHandSlot", { "MainHandSlot", "SecondaryHandSlot" } },
    { "SecondaryHandSlot", { "MainHandSlot", "SecondaryHandSlot" } },
    { "RangedSlot", { "RangedSlot" } },
    { "TabardSlot", { "TabardSlot" } },
    { "AmmoSlot", { "AmmoSlot" } },
}

local SLOT_NUM = {
    HeadSlot = 1,
    NeckSlot = 2,
    ShoulderSlot = 3,
    ShirtSlot = 4,
    ChestSlot = 5,
    WaistSlot = 6,
    LegsSlot = 7,
    FeetSlot = 8,
    WristSlot = 9,
    HandsSlot = 10,
    Finger0Slot = 11,
    Finger1Slot = 12,
    Trinket0Slot = 13,
    Trinket1Slot = 14,
    BackSlot = 15,
    MainHandSlot = 16,
    SecondaryHandSlot = 17,
    RangedSlot = 18,
    TabardSlot = 19,
    AmmoSlot = 0,
}

local slotIdCache = {}
local equipLabels = nil

local function equipLabel(i)
    if not equipLabels then
        equipLabels = {}
        local n
        for n = 1, table.getn(EQUIP_ROWS) do
            local g = getglobal(EQUIP_ROWS[n][1])
            if type(g) == "string" then
                equipLabels[n] = g
            else
                equipLabels[n] = ""
            end
        end
    end
    return equipLabels[i] or ""
end

local function slotsForToken(token)
    if type(token) ~= "string" then return nil end
    local i
    for i = 1, table.getn(EQUIP_ROWS) do
        if EQUIP_ROWS[i][1] == token then
            return EQUIP_ROWS[i][2]
        end
    end
    return nil
end

local function equipLocFromItem(item)
    if item == nil or item == "" or type(GetItemInfo) ~= "function" then return nil end
    local loc = nil
    local function grab()
        local ret = { GetItemInfo(item) }
        local i
        for i = 1, table.getn(ret) do
            local v = ret[i]
            if type(v) == "string" and string.sub(v, 1, 8) == "INVTYPE_" then
                loc = v
                return
            end
        end
    end
    local ok = pcall(grab)
    if not ok then return nil end
    return loc
end

local function trimTipText(s)
    if type(s) ~= "string" then return "" end
    local _, _, inner = string.find(s, "^%s*(.-)%s*$")
    if type(inner) == "string" then return inner end
    return s
end

local function matchEquipLine(text, exactOnly)
    if type(text) ~= "string" or text == "" then return nil end
    local best, bestLen = nil, 0
    local i
    for i = 1, table.getn(EQUIP_ROWS) do
        local label = equipLabel(i)
        if label ~= "" then
            local hit = false
            if exactOnly then
                if text == label then hit = true end
            elseif string.find(text, label, 1, true) then
                hit = true
            end
            if hit and string.len(label) > bestLen then
                bestLen = string.len(label)
                best = EQUIP_ROWS[i][2]
            end
        end
    end
    return best
end

local function slotsFromTipText(tip)
    local name = tipName(tip)
    if not name or not tip or not tip.NumLines then return nil end
    local n = tip:NumLines() or 0
    if n > 40 then n = 40 end
    local exact, sub = nil, nil
    local i
    for i = 2, n do
        local li
        for li = 1, 2 do
            local side = "Left"
            if li == 2 then side = "Right" end
            local fs = getglobal(name .. "Text" .. side .. i)
            local raw = fs and fs.GetText and fs:GetText()
            local text = trimTipText(raw)
            if text ~= "" then
                if not exact then
                    local hit = matchEquipLine(text, true)
                    if hit then exact = hit end
                end
                if not sub then
                    local hit2 = matchEquipLine(text, false)
                    if hit2 then sub = hit2 end
                end
            end
        end
    end
    if exact then return exact end
    return sub
end

local function invSlotId(slotName)
    if type(slotName) ~= "string" then return nil end
    if slotIdCache[slotName] ~= nil then
        return slotIdCache[slotName]
    end
    local id = nil
    if type(GetInventorySlotInfo) == "function" then
        local ok = pcall(function()
            id = GetInventorySlotInfo(slotName)
        end)
        if not ok then id = nil end
    end
    if type(id) ~= "number" and SLOT_NUM[slotName] ~= nil then
        id = SLOT_NUM[slotName]
    end
    if type(id) ~= "number" then return nil end
    slotIdCache[slotName] = id
    return id
end

local function slotsForPaperSlot(slotId)
    if type(slotId) ~= "number" then return nil end
    local i
    for i = 1, table.getn(PAPER_ROWS) do
        local id = invSlotId(PAPER_ROWS[i][1])
        if id == slotId then
            return PAPER_ROWS[i][2]
        end
    end
    return nil
end

local function ownerInvSlot(tip)
    if not tip or not tip.GetOwner then return nil end
    local id = nil
    local ok = pcall(function()
        local owner = tip:GetOwner()
        if not owner or not owner.GetName or not owner.GetID then return end
        local n = owner:GetName()
        if type(n) ~= "string" then return end
        if string.find(n, "Inspect", 1, true) then return end
        if not string.find(n, "Character", 1, true) and not string.find(n, "PaperDoll", 1, true) then
            return
        end
        local got = owner:GetID()
        if type(got) == "number" and got >= 0 then
            id = got
        end
    end)
    if not ok then return nil end
    return id
end

local function hoveredInvSlot(tip)
    if tip and type(tip._ichaInvSlot) == "number" then
        return tip._ichaInvSlot
    end
    return ownerInvSlot(tip)
end

local function slotsForTip(tip)
    if not tip then return nil end
    local slots = slotsForToken(equipLocFromItem(tip._ichaItem))
    if slots then return slots end
    slots = slotsFromTipText(tip)
    if slots then return slots end
    return slotsForPaperSlot(hoveredInvSlot(tip))
end

local function shiftIsDown()
    if type(IsShiftKeyDown) ~= "function" then return false end
    if IsShiftKeyDown() then return true end
    return false
end

local function compareGoesLeft(parent)
    local cx, sw = nil, nil
    local ok = pcall(function()
        if parent.GetCenter then cx = parent:GetCenter() end
        sw = GetScreenWidth()
    end)
    if not ok or type(cx) ~= "number" or type(sw) ~= "number" then return false end
    if cx > (sw * 0.5) then return true end
    return false
end

local function tipHasLines(st)
    if not st then return false end
    local name = tipName(st)
    if not name then return false end
    local fs = getglobal(name .. "TextLeft1")
    local txt = fs and fs.GetText and fs:GetText()
    if type(txt) == "string" and txt ~= "" then return true end
    return false
end

local function anchorCompare(st, anchorTo, side)
    if not st or not anchorTo or not st.ClearAllPoints or not st.SetPoint then return end
    st:ClearAllPoints()
    if side == "LEFT" then
        st:SetPoint("TOPRIGHT", anchorTo, "TOPLEFT", -2, 0)
    else
        st:SetPoint("TOPLEFT", anchorTo, "TOPRIGHT", 2, 0)
    end
end

local function slotHasItem(slotId)
    if type(slotId) ~= "number" then return false end
    if type(GetInventoryItemLink) ~= "function" then return true end
    local link = nil
    local ok = pcall(function()
        link = GetInventoryItemLink("player", slotId)
    end)
    if not ok then return true end
    if link and link ~= "" then return true end
    return false
end

local function fixCompareTex(st)
    if not st or not st.GetRegions then return end
    local regions = { st:GetRegions() }
    local i
    for i = 1, table.getn(regions) do
        local r = regions[i]
        if r and r.GetObjectType and r:GetObjectType() == "Texture" and r.SetTexCoord then
            local path = nil
            if r.GetTexture then path = r:GetTexture() end
            local low = ""
            if type(path) == "string" then low = string.lower(path) end
            if string.find(low, "background", 1, true) or string.find(low, "chatframe", 1, true) or string.find(low, "statusbar", 1, true) then
                r:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
                r:SetTexCoord(0, 1, 0, 1)
                if r.SetVertexColor then
                    r:SetVertexColor(BG[1], BG[2], BG[3], BG[4])
                end
            elseif string.find(low, "border", 1, true) then
                if r.SetVertexColor then
                    r:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
                end
            end
        end
    end
end

local function hideMoneyDeep(tip)
    hideMoneyFrames(tip)
    if not tip or not tip.GetChildren then return end
    local kids = { tip:GetChildren() }
    local i
    for i = 1, table.getn(kids) do
        local k = kids[i]
        if k and k.GetName and k.Hide then
            local n = k:GetName()
            if type(n) == "string" then
                if string.find(n, "MoneyFrame", 1, true)
                    or string.find(n, "GoldButton", 1, true)
                    or string.find(n, "SilverButton", 1, true)
                    or string.find(n, "CopperButton", 1, true) then
                    k:Hide()
                end
            end
        end
    end
end

-- Template border/background textures sit in front of the lines. Their
-- transparent centers let stat text show through the gold art. Backdrop
-- draws the one border behind the text, so those regions have to go first.
local function hideStockTipTextures(st)
    if not st or not st.GetRegions then return end
    local regions = { st:GetRegions() }
    local i
    for i = 1, table.getn(regions) do
        local r = regions[i]
        if r and r.GetObjectType and r:GetObjectType() == "Texture" and r.Hide then
            r:Hide()
        end
    end
end

local function finishCompareTip(st)
    if not st then return end
    hideStockTipTextures(st)
    applyBackdrop(st, BG[4], edgeSize)
    pcall(ensureVendorLine, st)
    hideMoneyDeep(st)
    st._ichaCmpHold = true
end

local function paintCompareTip(st)
    if not st then return end
    local n = tipName(st)
    if n then
        local bar = getglobal(n .. "StatusBar")
        if bar and bar.Hide then bar:Hide() end
    end
    finishCompareTip(st)
end

local function fillCompareTip(st, anchorTo, slotId, side)
    if not st or type(slotId) ~= "number" then return false end
    st._ichaCmpQuiet = true
    if st.SetAlpha then st:SetAlpha(0) end
    pcall(function()
        if st.SetOwner then
            st:SetOwner(anchorTo, "ANCHOR_NONE")
        end
    end)
    local hasItem = nil
    local ok = pcall(function()
        hasItem = st:SetInventoryItem("player", slotId)
    end)
    st._ichaCmpQuiet = nil
    if not ok or not hasItem or not tipHasLines(st) then
        if st.Hide then st:Hide() end
        if st.SetAlpha then st:SetAlpha(1) end
        return false
    end
    paintCompareTip(st)
    pcall(function()
        anchorCompare(st, anchorTo, side)
        if st.SetFrameStrata then st:SetFrameStrata("TOOLTIP") end
        if st.SetClampedToScreen then st:SetClampedToScreen(true) end
        if anchorTo and anchorTo.GetFrameLevel and st.SetFrameLevel then
            st:SetFrameLevel((anchorTo:GetFrameLevel() or 1) + 5)
        end
    end)
    st._ichaCmpPainted = true
    if st.SetAlpha then st:SetAlpha(1) end
    if st.Show then st:Show() end
    return true
end

local function showCompare(tip)
    local names = slotsForTip(tip)
    local st1 = getglobal("ShoppingTooltip1")
    local st2 = getglobal("ShoppingTooltip2")
    if not names or not st1 then
        hideCompare(tip)
        return false
    end
    local side = "RIGHT"
    if compareGoesLeft(tip) then side = "LEFT" end
    local hovered = hoveredInvSlot(tip)
    local anchorTo = tip
    local used = 0
    local i
    for i = 1, table.getn(names) do
        if used < 2 then
            local id = invSlotId(names[i])
            local skip = false
            if type(id) ~= "number" then
                skip = true
            elseif type(hovered) == "number" and id == hovered then
                skip = true
            elseif not slotHasItem(id) then
                skip = true
            end
            if not skip then
                local st = st1
                if used == 1 then st = st2 end
                if st and fillCompareTip(st, anchorTo, id, side) then
                    anchorTo = st
                    used = used + 1
                end
            end
        end
    end
    if used < 1 then
        hideCompare(tip)
        return false
    end
    if used < 2 and st2 and st2.Hide then st2:Hide() end
    compareOwner = tip
    return true
end

local compareBusy = false

local function compareKey(tip)
    local head = ""
    local tname = tipName(tip)
    if tname then
        local fs = getglobal(tname .. "TextLeft1")
        if fs and fs.GetText then
            local ht = fs:GetText()
            if type(ht) == "string" then head = ht end
        end
    end
    if head == "" and (not tip._ichaItem or tip._ichaItem == "") then
        return nil
    end
    return tostring(tip._ichaItem or "") .. "|" .. tostring(tip._ichaInvSlot or "") .. "|" .. head
end

updateCompare = function(tip)
    if compareBusy or not tip or not wantsCompare(tip) then return end
    if tip.IsShown and not tip:IsShown() then
        if compareOwner == tip then
            hideCompare(tip)
        end
        tip._ichaCmpDown = nil
        tip._ichaCmpKey = nil
        return
    end
    if not shiftIsDown() then
        if tip._ichaCmpDown or compareOwner == tip then
            hideCompare(tip)
        end
        tip._ichaCmpDown = nil
        tip._ichaCmpKey = nil
        return
    end
    local key = compareKey(tip)
    if not key then return end
    if tip._ichaCmpDown and tip._ichaCmpKey == key then return end
    compareBusy = true
    local showed = false
    local ok = pcall(function()
        showed = showCompare(tip)
    end)
    compareBusy = false
    if not ok then
        hideCompare(tip)
        tip._ichaCmpDown = nil
        tip._ichaCmpKey = nil
        return
    end
    if not showed then return end
    tip._ichaCmpDown = true
    tip._ichaCmpKey = key
end

local function hookTip(tip)
    if not tip or hooked[tip] then return end
    hooked[tip] = true
    if not tip._ichaTipOwnerHook and tip.SetOwner then
        tip._ichaTipOwnerHook = true
        local prevOwner = tip.SetOwner
        tip.SetOwner = function(self, owner, anchor, xOff, yOff)
            clearTipMoneyState(self)
            return prevOwner(self, owner, anchor, xOff, yOff)
        end
    end
    hookSetter(tip, "SetBagItem", "bag")
    hookSetter(tip, "SetInventoryItem", "inv")
    hookSetter(tip, "SetHyperlink", "link")
    hookSetter(tip, "SetLootItem", "loot")
    hookSetter(tip, "SetLootRollItem", "roll")
    hookSetter(tip, "SetMerchantItem", "merchant")
    hookSetter(tip, "SetQuestItem", "quest")
    hookSetter(tip, "SetQuestLogItem", "questlog")
    local prevShow = tip.GetScript and tip:GetScript("OnShow")
    tip:SetScript("OnShow", function()
        if this._ichaCmpQuiet then
            if this.SetAlpha then this:SetAlpha(0) end
            return
        end
        if this._ichaCmpPainted then
            this._ichaCmpPainted = nil
            finishCompareTip(this)
            return
        end
        if prevShow then pcall(prevShow) end
        if enabled then skinOne(this) end
        pcall(ensureVendorLine, this)
    end)
    if not tip._ichaTipHideHook then
        tip._ichaTipHideHook = true
        local prevHide = tip.GetScript and tip:GetScript("OnHide")
        tip:SetScript("OnHide", function()
            if wantsCompare(this) then
                hideCompare(this)
                this._ichaCmpDown = nil
                this._ichaCmpKey = nil
            end
            clearTipMoneyState(this)
            if prevHide then pcall(prevHide) end
        end)
    end
    -- Blizzard often recolors after Show; light OnUpdate while visible
    if not tip._ichaTipSkinUpdate then
        tip._ichaTipSkinUpdate = true
        local prevUp = tip.GetScript and tip:GetScript("OnUpdate")
        tip:SetScript("OnUpdate", function()
            if prevUp then pcall(prevUp) end
            if wantsCompare(this) and updateCompare then
                pcall(updateCompare, this)
            end
            if not enabled then return end
            local sn = tipName(this)
            if sn == "ShoppingTooltip1" or sn == "ShoppingTooltip2" then
                if this._ichaCmpHold then
                    this._ichaCmpHold = nil
                    hideMoneyDeep(this)
                    applyBackdrop(this, BG[4], edgeSize)
                    pcall(ensureVendorLine, this)
                    hideMoneyDeep(this)
                end
                return
            end
            this._ichaTipSkinT = (this._ichaTipSkinT or 0) + (arg1 or 0)
            if this._ichaTipSkinT < 0.15 then return end
            this._ichaTipSkinT = 0
            skinOne(this)
        end)
    end
end

local OPTIONAL_NAMES = {
    "GameTooltip",
    "ItemRefTooltip",
    "ShoppingTooltip1",
    "ShoppingTooltip2",
    "WorldMapTooltip",
    "AtlasLootTooltip",
    "ComparisonTooltip1",
    "ComparisonTooltip2",
    "LootLinkTooltip",
    "ItemTooltip",
}

local function applyAll()
    loadCfg()
    hookSetTooltipMoney()
    local i
    for i = 1, table.getn(OPTIONAL_NAMES) do
        local tip = getglobal(OPTIONAL_NAMES[i])
        if tip then
            hookTip(tip)
            if enabled then skinOne(tip) end
        end
    end
    if enabled then
        skinStatusBar(getglobal("GameTooltipStatusBar"))
    end
end

function IchaUI_TooltipSkin_Refresh()
    applyAll()
end

function IchaUI_TooltipSkin_Get()
    loadCfg()
    return { enabled = enabled }
end

function IchaUI_TooltipSkin_SetEnabled(on)
    loadCfg()
    enabled = on and true or false
    saveCfg()
    if enabled then
        applyAll()
    end
end

-- Options / FrameSkin-style field API
function IchaUITooltipSkin_Get()
    return IchaUI_TooltipSkin_Get()
end

function IchaUITooltipSkin_Set(field, value)
    if field == "enabled" then
        IchaUI_TooltipSkin_SetEnabled(value)
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function()
    hookSetTooltipMoney()
    if event == "ADDON_LOADED" then
        -- Late addon tips (AtlasLoot etc.)
        applyAll()
        return
    end
    applyAll()
    local t = CreateFrame("Frame")
    local e = 0
    t:SetScript("OnUpdate", function()
        e = e + arg1
        if e < 1.0 then return end
        this:SetScript("OnUpdate", nil)
        applyAll()
    end)
end)

local cmpWatch = CreateFrame("Frame")
cmpWatch:SetScript("OnUpdate", function()
    if not updateCompare then return end
    local gt = GameTooltip
    if gt and gt.IsShown and gt:IsShown() then
        updateCompare(gt)
    elseif compareOwner == gt then
        hideCompare(gt)
    end
    local ir = getglobal("ItemRefTooltip")
    if ir and ir.IsShown and ir:IsShown() then
        updateCompare(ir)
    elseif compareOwner == ir then
        hideCompare(ir)
    end
end)

hookSetTooltipMoney()

------------------------------------------------------------------------
-- Movable default tooltip anchor (IchaUIDB.tooltip).
-- Only GameTooltip_SetDefaultAnchor callers move; tooltips an addon anchors
-- itself (ANCHOR_RIGHT on its own owner etc.) never pass through here.
-- Until the box is dragged in /icha move and the corner is Bottom right,
-- the hook changes nothing and Blizzard's spot is used as is.
------------------------------------------------------------------------
local function installIchaUITooltipAnchor()
    local CORNERS = { "BOTTOMRIGHT", "BOTTOMLEFT", "TOPRIGHT", "TOPLEFT" }
    local CORNER_LABELS = {
        BOTTOMRIGHT = "Bottom right", BOTTOMLEFT = "Bottom left",
        TOPRIGHT = "Top right", TOPLEFT = "Top left",
    }
    local BOX_W, BOX_H = 160, 64
    local anchor = nil
    local moving = false
    local base = nil
    local prev = nil
    local busy = false
    local defaultAnchor

    local function db()
        if type(IchaUIDB) ~= "table" then IchaUIDB = {} end
        local t = IchaUIDB.tooltip
        if type(t) ~= "table" then
            t = (IchaUI_BakedGet and IchaUI_BakedGet("tooltip")) or {}
            if type(t) ~= "table" then t = {} end
            IchaUIDB.tooltip = t
        end
        if t.enabled == nil then t.enabled = true end
        return t
    end

    local function cornerOf(t)
        local c = t and t.corner
        if CORNER_LABELS[c] then return c end
        return "BOTTOMRIGHT"
    end

    -- Blizzard's live spot: BOTTOMRIGHT, -CONTAINER_OFFSET_X - 13, CONTAINER_OFFSET_Y.
    local function blizzXY()
        local ox = tonumber(CONTAINER_OFFSET_X)
        local oy = tonumber(CONTAINER_OFFSET_Y)
        if not ox or not oy then
            local t = IchaUI_BakedDefaults and IchaUI_BakedDefaults.tooltip
            return (t and t.x) or -13, (t and t.y) or 70
        end
        return -ox - 13, oy
    end

    local function round(v)
        return math.floor((v or 0) + 0.5)
    end

    local function place()
        if not anchor then return end
        local t = db()
        anchor:ClearAllPoints()
        if t.moved and t.point then
            anchor:SetPoint(t.point, UIParent, t.relPoint or t.point, t.x or 0, t.y or 0)
        else
            local x, y = blizzXY()
            anchor:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", x, y)
        end
    end

    local function paintBox()
        if not anchor or not anchor.sub then return end
        anchor.sub:SetText(CORNER_LABELS[cornerOf(db())] .. " corner")
    end

    -- Store the box by the chosen corner so the tooltip grows away from it.
    local function saveFromRect()
        if not anchor then return end
        local l, r = anchor:GetLeft(), anchor:GetRight()
        local tp, b = anchor:GetTop(), anchor:GetBottom()
        if not l or not r or not tp or not b then return end
        local pr = UIParent:GetRight() or UIParent:GetWidth() or 0
        local pt = UIParent:GetTop() or UIParent:GetHeight() or 0
        local t = db()
        local c = cornerOf(t)
        local x, y
        if string.find(c, "LEFT") then x = l else x = r - pr end
        if string.find(c, "BOTTOM") then y = b else y = tp - pt end
        t.point = c
        t.relPoint = c
        t.x = round(x)
        t.y = round(y)
        t.moved = true
        place()
    end

    local function ensureAnchor()
        if anchor then return anchor end
        anchor = CreateFrame("Frame", "IchaUITooltipAnchor", UIParent)
        anchor:SetWidth(BOX_W)
        anchor:SetHeight(BOX_H)
        anchor:SetFrameStrata("DIALOG")
        anchor:SetClampedToScreen(true)
        anchor:SetMovable(true)
        anchor:EnableMouse(false)
        anchor:RegisterForDrag("LeftButton")
        local box = CreateFrame("Frame", nil, anchor)
        box:SetAllPoints(anchor)
        box:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        box:SetBackdropColor(0.06, 0.06, 0.07, 0.85)
        box:SetBackdropBorderColor(0.93, 0.78, 0.35, 1)
        local lbl = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("CENTER", box, "CENTER", 0, 7)
        lbl:SetText("Tooltip")
        lbl:SetTextColor(0.93, 0.78, 0.35)
        local sub = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sub:SetPoint("CENTER", box, "CENTER", 0, -9)
        sub:SetTextColor(1, 1, 1)
        box:Hide()
        anchor.box = box
        anchor.sub = sub
        anchor:SetScript("OnDragStart", function()
            if moving then
                this.dragging = true
                this:StartMoving()
            end
        end)
        anchor:SetScript("OnDragStop", function()
            this.dragging = nil
            this:StopMovingOrSizing()
            if moving then saveFromRect() end
        end)
        place()
        paintBox()
        anchor:Show()
        return anchor
    end

    local function applyTo(tooltip, parent)
        if tooltip ~= GameTooltip then return end
        local t = db()
        if not t.enabled then return end
        local owner = parent
        if not owner and tooltip.GetOwner then owner = tooltip:GetOwner() end
        if not owner then owner = UIParent end
        if t.cursor then
            tooltip:SetOwner(owner, "ANCHOR_CURSOR")
            tooltip.default = 1
            return
        end
        local c = cornerOf(t)
        if not t.moved and c == "BOTTOMRIGHT" then return end
        local a = ensureAnchor()
        if not t.moved then place() end
        tooltip:SetOwner(owner, "ANCHOR_NONE")
        tooltip:ClearAllPoints()
        tooltip:SetPoint(c, a, c, 0, 0)
        tooltip.default = 1
    end

    -- A later addon that wraps us and calls us back as its "original" lands
    -- in the busy branch, which runs the function we first replaced.
    defaultAnchor = function(tooltip, parent)
        if busy then
            if base then return base(tooltip, parent) end
            return
        end
        busy = true
        local ok = true
        if prev then ok = pcall(prev, tooltip, parent) end
        busy = false
        if not ok and base and base ~= prev then base(tooltip, parent) end
        applyTo(tooltip, parent)
    end

    local function ensureHook()
        local cur = GameTooltip_SetDefaultAnchor
        if cur == defaultAnchor or type(cur) ~= "function" then return end
        if not base then base = cur end
        prev = cur
        GameTooltip_SetDefaultAnchor = defaultAnchor
    end

    function IchaUI_TooltipAnchor_Get()
        return db()
    end

    function IchaUI_TooltipAnchor_Enabled()
        return db().enabled and true or false
    end

    function IchaUI_TooltipAnchor_Corners()
        local out = {}
        local i
        for i = 1, table.getn(CORNERS) do
            out[i] = { CORNERS[i], CORNER_LABELS[CORNERS[i]] }
        end
        return out
    end

    function IchaUI_TooltipAnchor_CornerLabel(c)
        return CORNER_LABELS[c] or CORNER_LABELS.BOTTOMRIGHT
    end

    function IchaUI_TooltipAnchor_Frame()
        return ensureAnchor()
    end

    function IchaUI_TooltipAnchor_Apply()
        ensureHook()
        ensureAnchor()
        place()
        paintBox()
        if not moving then anchor.box:Hide() end
    end

    -- Solo move (Skin tab Move button): only this box unlocks, above the config
    -- window, with its own Lock chip. Escape closes it via UISpecialFrames.
    local solo = false
    local soloStarting = false
    local soloKey = nil
    local soloChip = nil
    local endSolo

    local function ensureSolo()
        if soloChip then return end
        local a = ensureAnchor()
        soloChip = CreateFrame("Button", nil, a.box)
        soloChip:SetWidth(36)
        soloChip:SetHeight(16)
        soloChip:SetPoint("TOPRIGHT", a.box, "TOPRIGHT", 0, 16)
        soloChip:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        soloChip:SetBackdropColor(0.08, 0.08, 0.09, 0.94)
        soloChip:SetBackdropBorderColor(0.93, 0.78, 0.35, 1)
        local fs = soloChip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("CENTER", soloChip, "CENTER", 0, 0)
        fs:SetText("Lock")
        fs:SetTextColor(1, 1, 1)
        soloChip:SetScript("OnClick", function() endSolo() end)
        soloChip:Hide()
        soloKey = CreateFrame("Frame", "IchaUITooltipAnchorSolo", UIParent)
        soloKey:SetScript("OnHide", function()
            if solo then endSolo() end
        end)
        soloKey:Hide()
        if UISpecialFrames then table.insert(UISpecialFrames, "IchaUITooltipAnchorSolo") end
    end

    local function soloRefresh()
        if IchaUI_TooltipAnchorRowRefresh then pcall(IchaUI_TooltipAnchorRowRefresh) end
    end

    endSolo = function()
        if not solo then return end
        solo = false
        IchaUI_TooltipAnchor_SetMove(false)
        soloRefresh()
    end

    function IchaUI_TooltipAnchor_SetMove(on)
        local a = ensureAnchor()
        if solo and on and not soloStarting then
            -- full edit mode took over: drop the solo chip, keep the box unlocked
            solo = false
            soloRefresh()
        end
        if on then
            moving = true
            place()
            paintBox()
            a:EnableMouse(true)
            a.box:Show()
        else
            if a.dragging then
                a.dragging = nil
                a:StopMovingOrSizing()
                saveFromRect()
            end
            moving = false
            solo = false
            a:EnableMouse(false)
            a.box:Hide()
        end
        if soloChip then
            if solo then soloChip:Show() else soloChip:Hide() end
            if not solo and soloKey:IsShown() then soloKey:Hide() end
        end
        if solo then
            a:SetFrameStrata("TOOLTIP")
            a:SetFrameLevel(250)
            a.box:SetFrameLevel(251)
            soloChip:SetFrameLevel(252)
        else
            a:SetFrameStrata("DIALOG")
        end
    end

    function IchaUI_TooltipAnchor_Moving()
        return moving
    end

    function IchaUI_TooltipAnchor_SoloActive()
        return solo
    end

    -- Unlock only the tooltip box; a second call locks and saves.
    function IchaUI_TooltipAnchor_ToggleSolo()
        if solo then
            endSolo()
            return false
        end
        if IchaUI_EditModeActive and IchaUI_EditModeActive() then return false end
        local t = db()
        t.enabled = true
        t.cursor = false
        ensureSolo()
        solo = true
        soloStarting = true
        IchaUI_TooltipAnchor_SetMove(true)
        soloStarting = false
        soloKey:Show()
        soloRefresh()
        return true
    end

    -- field: "enabled" | "cursor" | "corner" | "reset"
    function IchaUI_TooltipAnchor_Set(field, value)
        local t = db()
        if field == "enabled" then
            t.enabled = value and true or false
        elseif field == "cursor" then
            t.cursor = value and true or false
        elseif field == "corner" then
            if not CORNER_LABELS[value] then return end
            t.corner = value
            if t.moved then saveFromRect() end
        elseif field == "reset" then
            t.moved = false
            t.corner = "BOTTOMRIGHT"
            local x, y = blizzXY()
            t.point = "BOTTOMRIGHT"
            t.relPoint = "BOTTOMRIGHT"
            t.x = x
            t.y = y
        end
        ensureAnchor()
        place()
        paintBox()
    end

    -- Hook at load, then again after login in case another addon replaced
    -- the global without chaining (it then becomes our prev).
    ensureHook()
    local tipBoot = CreateFrame("Frame")
    tipBoot:RegisterEvent("PLAYER_ENTERING_WORLD")
    tipBoot:SetScript("OnEvent", function()
        this:UnregisterEvent("PLAYER_ENTERING_WORLD")
        IchaUI_TooltipAnchor_Apply()
        local e = 0
        this:SetScript("OnUpdate", function()
            e = e + (arg1 or 0)
            if e < 3 then return end
            this:SetScript("OnUpdate", nil)
            ensureHook()
        end)
    end)
end

installIchaUITooltipAnchor()
