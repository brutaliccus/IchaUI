-- Hero ability picker. One button holds an ordered list.
-- Clicks only change the draft. Save writes it. Cancel discards it.
-- Spells, macros (GetNumMacros / GetMacroInfo), and usable bag items.

local DRAFT_MAX = 24

local ui = {
    draft = {},
    slotKey = nil,
    tabs = {},
    tab = 1,
    page = 0,
    chosenScroll = 0,
    tabBtns = {},
    icons = {},
    chosen = {},
    pickCols = 10,
    pickRows = 5,
    pickN = 50,
    tabSlots = 18,
    chosenN = 12,
}

local itemScan

local function abilityKey(entry)
    if not entry then return "" end
    local kind = entry.kind or "spell"
    if kind ~= "macro" and kind ~= "item" then kind = "spell" end
    if kind == "item" then
        local id = entry.itemId
        if id and tostring(id) ~= "" then return "i:" .. tostring(id) end
    end
    local name = entry.spell or entry.name or ""
    return kind .. ":" .. string.lower(name)
end

local function ensureScan()
    if itemScan then return itemScan end
    itemScan = CreateFrame("GameTooltip", "IchaUIHeroItemScan", nil, "GameTooltipTemplate")
    itemScan:SetOwner(WorldFrame, "ANCHOR_NONE")
    return itemScan
end

local function catalog()
    local book = BOOKTYPE_SPELL or "spell"
    local tabs = {}

    local function pushSpell(spells, seen, index, name)
        if not name or name == "" then return end
        local key = string.lower(name)
        local tex = nil
        if GetSpellTexture then tex = GetSpellTexture(index, book) end
        local entry = { name = name, texture = tex, index = index, kind = "spell" }
        if seen[key] then
            spells[seen[key]] = entry
        else
            table.insert(spells, entry)
            seen[key] = table.getn(spells)
        end
    end

    local nTabs = 0
    if GetNumSpellTabs then nTabs = GetNumSpellTabs() or 0 end
    local t
    for t = 1, nTabs do
        local name, texture, offset, num = "Spells", nil, 0, 0
        if GetSpellTabInfo then
            name, texture, offset, num = GetSpellTabInfo(t)
        end
        offset = tonumber(offset) or 0
        num = tonumber(num) or 0
        local spells = {}
        local seen = {}
        if GetSpellName then
            local i
            for i = offset + 1, offset + num do
                local sname = GetSpellName(i, book)
                pushSpell(spells, seen, i, sname)
            end
        end
        if table.getn(spells) > 0 then
            table.insert(tabs, { name = name or "Spells", texture = texture, kind = "spell", spells = spells })
        end
    end
    if table.getn(tabs) < 1 and GetSpellName then
        local spells = {}
        local seen = {}
        local i = 1
        while i <= 500 do
            local sname = GetSpellName(i, book)
            if not sname then break end
            pushSpell(spells, seen, i, sname)
            i = i + 1
        end
        if table.getn(spells) > 0 then
            table.insert(tabs, { name = "General", texture = nil, kind = "spell", spells = spells })
        end
    end

    local macros = {}
    local macroSeen = {}
    local function addMacro(index, charMacro)
        if not GetMacroInfo then return end
        local name, tex = GetMacroInfo(index)
        if not name or name == "" then return end
        if macroSeen[name] then return end
        macroSeen[name] = true
        if not tex or tex == "" then tex = "Interface\\Icons\\INV_Misc_QuestionMark" end
        table.insert(macros, {
            name = name,
            texture = tex,
            index = index,
            kind = "macro",
            charMacro = charMacro,
        })
    end
    local nAcc, nChar = nil, nil
    if GetNumMacros then
        nAcc, nChar = GetNumMacros()
    end
    nAcc = tonumber(nAcc)
    nChar = tonumber(nChar)
    if nAcc and nChar and (nAcc + nChar) > 0 then
        if nAcc < 0 then nAcc = 0 end
        if nAcc > 18 then nAcc = 18 end
        if nChar < 0 then nChar = 0 end
        if nChar > 18 then nChar = 18 end
        local i
        for i = 1, nAcc do addMacro(i, false) end
        for i = 1, nChar do addMacro(18 + i, true) end
    elseif GetMacroInfo then
        local i
        for i = 1, 36 do
            addMacro(i, i > 18)
        end
    end
    table.sort(macros, function(a, b)
        return string.lower(a.name) < string.lower(b.name)
    end)
    table.insert(tabs, { name = "Macros", texture = nil, kind = "macro", spells = macros })

    local function hasText(s, part)
        if not s or s == "" or not part then return false end
        return string.find(string.lower(s), part, 1, true) and true or false
    end

    local function categoryFor(itemType, itemSub, name)
        local sub = itemSub or ""
        local typ = itemType or ""
        if hasText(sub, "bandage") or hasText(typ, "bandage") or hasText(name, "bandage") then
            return "Bandages"
        end
        if hasText(sub, "scroll") or hasText(typ, "scroll") then return "Scrolls" end
        if hasText(sub, "potion") or hasText(typ, "potion") then return "Potions" end
        if hasText(sub, "elixir") or hasText(typ, "elixir") then return "Elixirs" end
        if hasText(sub, "flask") or hasText(typ, "flask") then return "Flasks" end
        local function hasWord(s, word)
            if not s or s == "" then return false end
            s = string.lower(s)
            if s == word then return true end
            if string.sub(s, 1, string.len(word) + 1) == word .. " " then return true end
            if string.len(s) >= string.len(word) + 1 and string.sub(s, -string.len(word) - 1) == " " .. word then
                return true
            end
            if string.find(s, " " .. word .. " ", 1, true) then return true end
            return false
        end
        local foodish = hasText(sub, "food") or hasText(sub, "drink") or hasText(typ, "food")
        local drinkName = hasWord(name, "water") or hasWord(name, "milk") or hasWord(name, "juice")
            or hasWord(name, "nectar") or hasWord(name, "tea") or hasWord(name, "coffee")
            or hasWord(name, "drink") or hasWord(name, "rum") or hasWord(name, "wine")
            or hasWord(name, "mead") or hasWord(name, "grog") or hasWord(name, "ale")
        if foodish and drinkName then return "Water" end
        if foodish then return "Food" end
        if drinkName and (hasText(typ, "consumable") or sub == "") then return "Water" end
        if sub ~= "" then return sub end
        if hasText(typ, "consumable") then return "Consumables" end
        if typ ~= "" then return typ end
        return "Other"
    end

    local function usableItem(itemId, itemType)
        local scan = ensureScan()
        if not scan then return itemType == "Consumable" end
        local usable = false
        local ok = pcall(function()
            scan:SetOwner(WorldFrame, "ANCHOR_NONE")
            scan:ClearLines()
            scan:SetHyperlink("item:" .. tostring(itemId))
            local nlines = 0
            if scan.NumLines then nlines = scan:NumLines() or 0 end
            local line
            for line = 1, nlines do
                local left = getglobal("IchaUIHeroItemScanTextLeft" .. tostring(line))
                local text = nil
                if left and left.GetText then text = left:GetText() end
                if text and string.sub(text, 1, 5) == "Use: " then
                    usable = true
                end
            end
        end)
        return ok and usable
    end

    local groups = {}
    local added = {}
    if GetContainerNumSlots and GetContainerItemLink then
        local bag
        for bag = 0, 4 do
            local slots = GetContainerNumSlots(bag) or 0
            local slot
            for slot = 1, slots do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local _, _, id = string.find(link, "item:(%d+)")
                    if id and not added[id] then
                        local name, itemType, itemSub, itex
                        if GetItemInfo then
                            local infoName, infoLink, infoQual, infoLevel, infoMin, infoType, infoSub, infoStack, infoEquip, infoTex = GetItemInfo(id)
                            name = infoName
                            itemType = infoType
                            itemSub = infoSub
                            itex = infoTex
                        end
                        if not name then
                            local _, _, linkName = string.find(link, "%[(.+)%]")
                            name = linkName
                        end
                        local isQuest = itemType == "Quest" and (not name or string.sub(name, 1, 5) ~= "Juju ")
                        if name and name ~= "" and not isQuest and itemType ~= "Trade Goods" and usableItem(id, itemType) then
                            local tex = nil
                            if GetContainerItemInfo then tex = GetContainerItemInfo(bag, slot) end
                            if not tex or tex == "" then tex = itex end
                            if not tex or tex == "" then tex = "Interface\\Icons\\INV_Misc_QuestionMark" end
                            local cat = categoryFor(itemType, itemSub, name)
                            if cat == "Macros" then cat = "Macro Items" end
                            if not groups[cat] then groups[cat] = {} end
                            table.insert(groups[cat], {
                                name = name,
                                texture = tex,
                                itemId = id,
                                kind = "item",
                            })
                            added[id] = true
                        end
                    end
                end
            end
        end
    end

    local function catRank(name)
        if name == "Food" then return 1 end
        if name == "Water" then return 2 end
        if name == "Potions" then return 3 end
        if name == "Elixirs" then return 4 end
        if name == "Flasks" then return 5 end
        if name == "Bandages" then return 6 end
        if name == "Scrolls" then return 7 end
        if name == "Consumables" then return 8 end
        return 50
    end

    local catNames = {}
    local cat, list
    for cat, list in pairs(groups) do
        if list and table.getn(list) > 0 then
            table.sort(list, function(a, b)
                return string.lower(a.name) < string.lower(b.name)
            end)
            table.insert(catNames, cat)
        end
    end
    table.sort(catNames, function(a, b)
        local ra, rb = catRank(a), catRank(b)
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    local ci
    for ci = 1, table.getn(catNames) do
        local cname = catNames[ci]
        table.insert(tabs, { name = cname, texture = nil, kind = "item", spells = groups[cname] })
    end
    return tabs
end

local function toggleDraft(entry)
    if not entry or not entry.name or entry.name == "" then return end
    local key = abilityKey(entry)
    local i
    for i = 1, table.getn(ui.draft) do
        if abilityKey(ui.draft[i]) == key then
            table.remove(ui.draft, i)
            return
        end
    end
    if table.getn(ui.draft) >= DRAFT_MAX then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("IchaUI: a hero button holds " .. DRAFT_MAX .. " abilities.")
        end
        return
    end
    local kind = entry.kind or "spell"
    if kind ~= "macro" and kind ~= "item" then kind = "spell" end
    table.insert(ui.draft, {
        spell = entry.name,
        kind = kind,
        itemId = entry.itemId,
        texture = entry.texture,
    })
end

local picker

local function build()
    local GOLD_R, GOLD_G, GOLD_B = 0.78, 0.58, 0.16
    picker = CreateFrame("Frame", "IchaUIHeroPicker", UIParent)
    picker:SetWidth(880)
    picker:SetHeight(520)
    picker:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    picker:SetFrameLevel(480)
    picker:SetMovable(true)
    picker:EnableMouse(true)
    picker:EnableMouseWheel(true)
    picker:RegisterForDrag("LeftButton")
    picker:SetScript("OnDragStart", function() this:StartMoving() end)
    picker:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    picker:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    picker:SetBackdropColor(0.07, 0.07, 0.08, 1)
    IchaUI_PaintGoldBorder(picker, 1)
    local solid = picker:CreateTexture(nil, "BACKGROUND")
    solid:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    solid:SetPoint("TOPLEFT", picker, "TOPLEFT", 4, -4)
    solid:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -4, 4)
    solid:SetVertexColor(0.07, 0.07, 0.08, 1)
    picker:Hide()
    picker:SetScript("OnShow", function()
        if IchaUI_DyeConfigTree then IchaUI_DyeConfigTree(picker, 0) end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "IchaUIHeroPicker") end

    local title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", picker, "TOPLEFT", 14, -12)
    title:SetText("Edit abilities")
    IchaUI_PaintGoldFont(title, 0.78, 0.58, 0.16)
    ui.title = title

    local hint = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", picker, "TOPLEFT", 200, -14)
    hint:SetWidth(520)
    hint:SetJustifyH("LEFT")
    hint:SetText("Click to add or remove. The list on the left is the order saved on this button.")
    hint:SetTextColor(0.7, 0.7, 0.65)

    local listHeader = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listHeader:SetPoint("TOPLEFT", picker, "TOPLEFT", 14, -40)
    listHeader:SetText("Selected")
    IchaUI_PaintGoldFont(listHeader, 0.78, 0.58, 0.16)
    ui.listHeader = listHeader

    local listHint = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    listHint:SetPoint("TOPLEFT", picker, "TOPLEFT", 14, -58)
    listHint:SetWidth(170)
    listHint:SetJustifyH("LEFT")
    listHint:SetText("Click a row to remove it.")
    listHint:SetTextColor(0.55, 0.55, 0.5)

    local saveBtn = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    saveBtn:SetWidth(78)
    saveBtn:SetHeight(22)
    saveBtn:SetText("Save")
    saveBtn:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 14, 12)
    saveBtn:SetScript("OnClick", function()
        local key = ui.slotKey
        local src = ui.draft or {}
        local copy = {}
        local i
        for i = 1, table.getn(src) do
            local d = src[i]
            if d and d.spell and d.spell ~= "" then
                table.insert(copy, {
                    spell = d.spell,
                    kind = d.kind or "spell",
                    itemId = d.itemId,
                    texture = d.texture,
                })
            end
        end
        if type(ui.onSave) == "function" then
            local fn = ui.onSave
            ui.onSave = nil
            fn(copy)
        elseif IchaUI_HeroCommitAbilities and key then
            IchaUI_HeroCommitAbilities(key, copy)
        end
        if IchaUI_HeroPicker_Close then IchaUI_HeroPicker_Close() end
    end)

    local cancelBtn = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    cancelBtn:SetWidth(78)
    cancelBtn:SetHeight(22)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
    cancelBtn:SetScript("OnClick", function()
        if IchaUI_HeroPicker_Close then IchaUI_HeroPicker_Close() end
    end)

    local function turnPage(dir)
        ui.page = (ui.page or 0) + dir
        if ui.page < 0 then ui.page = 0 end
        if ui.refresh then ui.refresh() end
    end

    picker:SetScript("OnMouseWheel", function()
        local dir = tonumber(arg1) or 0
        if dir > 0 then turnPage(-1) else turnPage(1) end
    end)

    local ti
    for ti = 1, ui.tabSlots do
        local tb = CreateFrame("Button", nil, picker)
        tb:SetWidth(90)
        tb:SetHeight(22)
        tb:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        tb:SetBackdropColor(0.12, 0.12, 0.13, 1)
        IchaUI_PaintGoldBorder(tb, 0.7)
        local tic = tb:CreateTexture(nil, "ARTWORK")
        tic:SetWidth(16)
        tic:SetHeight(16)
        tic:SetPoint("LEFT", tb, "LEFT", 2, 0)
        tic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tic:Hide()
        tb.icon = tic
        local tlab = tb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tlab:SetPoint("LEFT", tb, "LEFT", 20, 0)
        tlab:SetPoint("RIGHT", tb, "RIGHT", -4, 0)
        tlab:SetJustifyH("LEFT")
        tlab:SetTextColor(0.95, 0.9, 0.75)
        tb.label = tlab
        tb:SetScript("OnClick", function()
            if not this.tabIndex then return end
            ui.tab = this.tabIndex
            ui.page = 0
            if ui.refresh then ui.refresh() end
        end)
        tb:SetScript("OnEnter", function()
            if not this.tabName then return end
            GameTooltip:SetOwner(this, "ANCHOR_TOP")
            GameTooltip:SetText(this.tabName)
            GameTooltip:Show()
        end)
        tb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        tb:Hide()
        ui.tabBtns[ti] = tb
    end

    local ci
    for ci = 1, ui.chosenN do
        local rowBtn = CreateFrame("Button", nil, picker)
        rowBtn:SetWidth(168)
        rowBtn:SetHeight(20)
        rowBtn:SetPoint("TOPLEFT", picker, "TOPLEFT", 12, -(78 + (ci - 1) * 22))
        rowBtn:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        rowBtn:SetBackdropColor(0.06, 0.06, 0.07, 0.9)
        IchaUI_PaintGoldBorder(rowBtn, 0.7)
        local ric = rowBtn:CreateTexture(nil, "ARTWORK")
        ric:SetWidth(16)
        ric:SetHeight(16)
        ric:SetPoint("LEFT", rowBtn, "LEFT", 2, 0)
        ric:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ric:Hide()
        rowBtn.icon = ric
        local rl = rowBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rl:SetPoint("LEFT", rowBtn, "LEFT", 20, 0)
        rl:SetPoint("RIGHT", rowBtn, "RIGHT", -4, 0)
        rl:SetJustifyH("LEFT")
        rl:SetTextColor(0.95, 0.95, 0.9)
        rowBtn.label = rl
        rowBtn:EnableMouseWheel(true)
        rowBtn:SetScript("OnMouseWheel", function()
            local dir = tonumber(arg1) or 0
            if dir > 0 then ui.chosenScroll = (ui.chosenScroll or 0) - 1 end
            if dir < 0 then ui.chosenScroll = (ui.chosenScroll or 0) + 1 end
            if ui.chosenScroll < 0 then ui.chosenScroll = 0 end
            if ui.refresh then ui.refresh() end
        end)
        rowBtn:SetScript("OnClick", function()
            local idx = this.draftIndex
            if not idx or not ui.draft or not ui.draft[idx] then return end
            table.remove(ui.draft, idx)
            if ui.refresh then ui.refresh() end
        end)
        rowBtn:Hide()
        ui.chosen[ci] = rowBtn
    end

    local pi
    for pi = 1, ui.pickN do
        local b = CreateFrame("Button", nil, picker)
        b:SetWidth(40)
        b:SetHeight(40)
        b:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        b:SetBackdropColor(0, 0, 0, 1)
        b:SetBackdropBorderColor(0.4, 0.35, 0.15, 1)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
        icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.icon = icon
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel", function()
            local dir = tonumber(arg1) or 0
            if dir > 0 then turnPage(-1) else turnPage(1) end
        end)
        b:SetScript("OnClick", function()
            if not this.entryName then return end
            toggleDraft({
                name = this.entryName,
                kind = this.entryKind,
                itemId = this.entryItem,
                texture = this.entryTex,
            })
            if ui.refresh then ui.refresh() end
        end)
        b:SetScript("OnEnter", function()
            if not this.entryName then return end
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            local named = false
            if this.entryKind == "spell" and this.entryIndex and GameTooltip.SetSpell then
                local ok = pcall(function()
                    GameTooltip:SetSpell(this.entryIndex, BOOKTYPE_SPELL or "spell")
                    named = true
                end)
                if not ok then named = false end
            elseif this.entryKind == "item" and this.entryItem and GameTooltip.SetHyperlink then
                local ok = pcall(function()
                    GameTooltip:SetHyperlink("item:" .. tostring(this.entryItem))
                    named = true
                end)
                if not ok then named = false end
            end
            if not named then
                GameTooltip:SetText(this.entryName)
                if this.entryKind == "macro" then
                    local who = "Account macro"
                    if this.entryChar then who = "Character macro" end
                    GameTooltip:AddLine(who, 0.8, 0.8, 0.7)
                    if this.entryIndex and GetMacroInfo then
                        local _, _, body = GetMacroInfo(this.entryIndex)
                        if body and body ~= "" then
                            if string.len(body) > 80 then body = string.sub(body, 1, 78) .. ".." end
                            GameTooltip:AddLine(body, 1, 1, 1)
                        end
                    end
                elseif this.entryKind == "item" then
                    GameTooltip:AddLine("Consumable", 0.8, 0.8, 0.7)
                end
            end
            GameTooltip:Show()
            if this.inDraft then
                this:SetBackdropBorderColor(0.45, 1, 0.55, 1)
            else
                this:SetBackdropBorderColor(1, 0.9, 0.4, 1)
            end
        end)
        b:SetScript("OnLeave", function()
            GameTooltip:Hide()
            if this.inDraft then
                this:SetBackdropBorderColor(0.35, 0.85, 0.4, 1)
            else
                this:SetBackdropBorderColor(0.4, 0.35, 0.15, 1)
            end
        end)
        b:Hide()
        ui.icons[pi] = b
    end

    local prevBtn = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    prevBtn:SetWidth(70)
    prevBtn:SetHeight(20)
    prevBtn:SetText("Prev")
    prevBtn:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 200, 12)
    prevBtn:SetScript("OnClick", function() turnPage(-1) end)
    local nextBtn = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    nextBtn:SetWidth(70)
    nextBtn:SetHeight(20)
    nextBtn:SetText("Next")
    nextBtn:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -14, 12)
    nextBtn:SetScript("OnClick", function() turnPage(1) end)
    local pageLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pageLabel:SetPoint("BOTTOM", picker, "BOTTOM", 80, 16)
    pageLabel:SetTextColor(0.9, 0.85, 0.7)
    ui.pageLabel = pageLabel
    local emptyMsg = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyMsg:SetPoint("TOPLEFT", picker, "TOPLEFT", 220, -120)
    emptyMsg:SetWidth(400)
    emptyMsg:SetJustifyH("LEFT")
    emptyMsg:SetTextColor(0.7, 0.7, 0.65)
    emptyMsg:Hide()
    ui.emptyMsg = emptyMsg

    local function clip(name, n)
        if not name or name == "" then return "" end
        if string.len(name) <= n then return name end
        return string.sub(name, 1, n - 2) .. ".."
    end

    local function inDraft(entry)
        local key = abilityKey(entry)
        local i
        for i = 1, table.getn(ui.draft) do
            if abilityKey(ui.draft[i]) == key then return true end
        end
        return false
    end

    local function refresh()
        local tabs = ui.tabs or {}
        local tabCount = table.getn(tabs)
        if ui.tab < 1 then ui.tab = 1 end
        if tabCount > 0 and ui.tab > tabCount then ui.tab = tabCount end
        local showTabs = tabCount
        if showTabs > ui.tabSlots then showTabs = ui.tabSlots end
        local tabRows = 1
        if showTabs > 8 then tabRows = 2 end
        local perRow = showTabs
        if tabRows > 1 then perRow = math.floor((showTabs + 1) / 2) end
        if perRow < 1 then perRow = 1 end
        local tabW = math.floor(640 / perRow) - 4
        if tabW > 150 then tabW = 150 end
        if tabW < 64 then tabW = 64 end
        local tb
        for tb = 1, ui.tabSlots do
            local btn = ui.tabBtns[tb]
            local info = tabs[tb]
            if btn and info and tb <= showTabs then
                local row = 0
                local col = tb - 1
                if tabRows > 1 and tb > perRow then
                    row = 1
                    col = tb - perRow - 1
                end
                btn.tabIndex = tb
                btn.tabName = info.name
                btn:SetWidth(tabW)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", picker, "TOPLEFT", 200 + col * (tabW + 4), -(36 + row * 26))
                if info.texture and btn.icon then
                    btn.icon:SetTexture(info.texture)
                    btn.icon:Show()
                    if btn.label then
                        btn.label:ClearAllPoints()
                        btn.label:SetPoint("LEFT", btn, "LEFT", 20, 0)
                        btn.label:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
                    end
                elseif btn.icon then
                    btn.icon:Hide()
                    if btn.label then
                        btn.label:ClearAllPoints()
                        btn.label:SetPoint("LEFT", btn, "LEFT", 6, 0)
                        btn.label:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
                    end
                end
                if btn.label then btn.label:SetText(clip(info.name or "", 18)) end
                if tb == ui.tab then
                    btn:SetBackdropBorderColor(1, 0.9, 0.45, 1)
                    btn:SetBackdropColor(0.28, 0.2, 0.06, 1)
                else
                    IchaUI_PaintGoldBorder(btn, 0.7)
                    btn:SetBackdropColor(0.12, 0.12, 0.13, 1)
                end
                btn:Show()
            elseif btn then
                btn:Hide()
            end
        end

        local gridTop = 36 + tabRows * 26 + 8
        local tab = tabs[ui.tab]
        local spells = (tab and tab.spells) or {}
        local spellCount = table.getn(spells)
        local per = ui.pickN
        local pages = math.floor((spellCount + per - 1) / per)
        if pages < 1 then pages = 1 end
        if ui.page > pages - 1 then ui.page = pages - 1 end
        if ui.page < 0 then ui.page = 0 end
        local base = ui.page * per
        local p
        for p = 1, per do
            local b = ui.icons[p]
            local spell = spells[base + p]
            if b and spell then
                local col = math.mod(p - 1, ui.pickCols)
                local row = math.floor((p - 1) / ui.pickCols)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", picker, "TOPLEFT", 200 + col * 46, -(gridTop + row * 46))
                b.entryName = spell.name
                b.entryKind = spell.kind or "spell"
                b.entryItem = spell.itemId
                b.entryTex = spell.texture
                b.entryIndex = spell.index
                b.entryChar = spell.charMacro
                b.inDraft = inDraft(spell)
                if spell.texture then
                    b.icon:SetTexture(spell.texture)
                else
                    b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                end
                if b.inDraft then
                    b:SetBackdropBorderColor(0.35, 0.85, 0.4, 1)
                else
                    b:SetBackdropBorderColor(0.4, 0.35, 0.15, 1)
                end
                b:Show()
            elseif b then
                b.entryName = nil
                b.entryKind = nil
                b.entryItem = nil
                b.entryIndex = nil
                b.inDraft = nil
                b:Hide()
            end
        end
        if ui.emptyMsg then
            if spellCount < 1 then
                local empty = "Nothing on this tab."
                if tab and tab.kind == "macro" then
                    empty = "No macros. Account and character macros show up here."
                elseif tab and tab.kind == "item" then
                    empty = "No usable items in your bags for this category."
                end
                ui.emptyMsg:SetText(empty)
                ui.emptyMsg:Show()
            else
                ui.emptyMsg:Hide()
            end
        end
        if ui.pageLabel then
            local tabName = (tab and tab.name) or ""
            ui.pageLabel:SetText(tabName .. "   " .. tostring(ui.page + 1) .. " / " .. tostring(pages))
        end
        if ui.title then
            ui.title:SetText("Edit abilities")
        end

        local draftN = table.getn(ui.draft)
        local maxScroll = draftN - ui.chosenN
        if maxScroll < 0 then maxScroll = 0 end
        if ui.chosenScroll > maxScroll then ui.chosenScroll = maxScroll end
        if ui.chosenScroll < 0 then ui.chosenScroll = 0 end
        if ui.listHeader then
            ui.listHeader:SetText("Selected (" .. tostring(draftN) .. ")")
        end
        local r
        for r = 1, ui.chosenN do
            local rowBtn = ui.chosen[r]
            local idx = ui.chosenScroll + r
            local entry = ui.draft[idx]
            if rowBtn and entry then
                rowBtn.draftIndex = idx
                local prefix = tostring(idx) .. ". "
                rowBtn.label:SetText(prefix .. clip(entry.spell or "", 16))
                if entry.texture and rowBtn.icon then
                    rowBtn.icon:SetTexture(entry.texture)
                    rowBtn.icon:Show()
                elseif rowBtn.icon then
                    rowBtn.icon:Hide()
                end
                rowBtn:Show()
            elseif rowBtn then
                rowBtn.draftIndex = nil
                rowBtn:Hide()
            end
        end
    end

    ui.refresh = refresh
end

function IchaUI_HeroPicker_Open(slotKey)
    if not picker then build() end
    if IchaUI_HeroGrid then IchaUI_HeroGrid() end
    slotKey = tonumber(slotKey)
    if not slotKey then return end
    ui.onSave = nil
    ui.slotKey = slotKey
    ui.draft = {}
    ui.tab = 1
    ui.page = 0
    ui.chosenScroll = 0
    local hs = IchaUIDB and IchaUIDB.heroSetup
    local slot = hs and hs.slots and hs.slots[slotKey]
    if slot and type(slot.abs) == "table" then
        local i
        for i = 1, table.getn(slot.abs) do
            local e = slot.abs[i]
            if e and e.spell and e.spell ~= "" then
                local kind = e.kind
                if kind ~= "macro" and kind ~= "item" then kind = "spell" end
                table.insert(ui.draft, {
                    spell = e.spell,
                    kind = kind,
                    itemId = e.itemId,
                    texture = e.texture,
                })
            end
        end
    end
    ui.tabs = catalog()
    ui.tab = 1
    picker:Show()
    if ui.refresh then ui.refresh() end
end

function IchaUI_HeroPicker_Close()
    ui.onSave = nil
    ui.slotKey = nil
    ui.draft = {}
    if picker then picker:Hide() end
end

function IchaUI_HeroPicker_OpenDraft(initial, onSave)
    if not picker then build() end
    if IchaUI_HeroGrid then IchaUI_HeroGrid() end
    ui.slotKey = nil
    ui.onSave = onSave
    ui.draft = {}
    ui.tab = 1
    ui.page = 0
    ui.chosenScroll = 0
    if type(initial) == "table" then
        local i
        for i = 1, table.getn(initial) do
            local e = initial[i]
            if e and e.spell and e.spell ~= "" then
                local kind = e.kind
                if kind ~= "macro" and kind ~= "item" then kind = "spell" end
                table.insert(ui.draft, {
                    spell = e.spell,
                    kind = kind,
                    itemId = e.itemId,
                    texture = e.texture,
                })
            end
        end
    end
    ui.tabs = catalog()
    ui.tab = 1
    picker:Show()
    if ui.refresh then ui.refresh() end
end

function IchaUI_HeroPicker_IsOpen()
    if picker and picker:IsShown() then return true end
    return false
end
