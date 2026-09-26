-- Account-wide named snapshots of every IchaUI saved-variable table.
-- IchaUIDB stays the live settings table (not wiped on login).
-- IchaUIProfiles is the shared library every character on the account can load.
-- Lua 5.0: helpers live inside one function so this file adds a single main-chunk local.

local function installIchaUIProfiles()
    -- Persisted settings globals. The library itself is not part of a snapshot.
    local SETTINGS = { "IchaUIDB" }
    -- SavedVariables are not assigned until ADDON_LOADED. Do not create the
    -- library table before that, or a later logout can flush an empty copy.
    local ready = false

    local function trim(s)
        s = tostring(s or "")
        s = string.gsub(s, "^%s+", "")
        s = string.gsub(s, "%s+$", "")
        return s
    end

    local function deepCopy(src, seen)
        local tv = type(src)
        if tv ~= "table" then
            if tv == "function" or tv == "userdata" or tv == "thread" then
                return nil
            end
            return src
        end
        if type(src.GetObjectType) == "function" then
            return nil
        end
        if not seen then seen = {} end
        if seen[src] then return seen[src] end
        local dst = {}
        seen[src] = dst
        local k, v
        for k, v in pairs(src) do
            local skip = false
            local ck = k
            local kt = type(k)
            if kt == "function" or kt == "userdata" or kt == "thread" then
                skip = true
            elseif kt == "table" then
                if type(k.GetObjectType) == "function" then
                    skip = true
                else
                    ck = deepCopy(k, seen)
                end
            end
            if not skip then
                local vt = type(v)
                if vt == "table" then
                    if type(v.GetObjectType) ~= "function" then
                        dst[ck] = deepCopy(v, seen)
                    end
                elseif vt ~= "function" and vt ~= "userdata" and vt ~= "thread" then
                    dst[ck] = v
                end
            end
        end
        -- Array part again: some 1.12 clients skip numeric keys in mixed tables.
        local i = 1
        while i < 100000 do
            if src[i] == nil then break end
            v = src[i]
            tv = type(v)
            if tv == "table" then
                if type(v.GetObjectType) ~= "function" then
                    dst[i] = deepCopy(v, seen)
                end
            elseif tv ~= "function" and tv ~= "userdata" and tv ~= "thread" then
                dst[i] = v
            end
            i = i + 1
        end
        return dst
    end

    -- Lua 5.0: WoW writes [1] = "name" into the hash part and drops the n field,
    -- so table.getn on a loaded list is often 0 even when [1] is set.
    local function countIdx(t)
        local n = 0
        if type(t) ~= "table" then return 0 end
        while t[n + 1] ~= nil do
            n = n + 1
            if n > 5000 then break end
        end
        return n
    end

    local function markCount(t, n)
        t.n = n
    end

    local function store()
        if type(IchaUIProfiles) ~= "table" then
            if not ready then return nil end
            IchaUIProfiles = {}
        end
        if type(IchaUIProfiles.byName) ~= "table" then IchaUIProfiles.byName = {} end
        if type(IchaUIProfiles.order) ~= "table" then IchaUIProfiles.order = {} end
        return IchaUIProfiles
    end

    local function capture()
        local snap = {}
        local i, gname, src
        for i = 1, table.getn(SETTINGS) do
            gname = SETTINGS[i]
            src = getglobal(gname)
            if type(src) == "table" then
                snap[gname] = deepCopy(src)
            else
                snap[gname] = {}
            end
        end
        return snap
    end

    local function restore(snap)
        if type(snap) ~= "table" then return false end
        local i, gname
        for i = 1, table.getn(SETTINGS) do
            gname = SETTINGS[i]
            if type(snap[gname]) ~= "table" then
                return false
            end
        end
        for i = 1, table.getn(SETTINGS) do
            gname = SETTINGS[i]
            setglobal(gname, deepCopy(snap[gname]))
        end
        return true
    end

    local function safe(fn)
        if type(fn) ~= "function" then return end
        pcall(fn)
    end

    function IchaUI_ProfileNames()
        local st = store()
        local out = {}
        if not st then
            markCount(out, 0)
            return out
        end
        local seen = {}
        local function add(n)
            if type(n) ~= "string" or n == "" or seen[n] then return end
            if type(st.byName[n]) ~= "table" then return end
            seen[n] = true
            local i = countIdx(out) + 1
            out[i] = n
            markCount(out, i)
        end
        local order = st.order
        local i = 1
        while true do
            local n = order[i]
            if n == nil then break end
            add(n)
            i = i + 1
            if i > 5000 then break end
        end
        local n, snap
        for n, snap in pairs(st.byName) do
            if type(n) == "string" and type(snap) == "table" then
                add(n)
            end
        end
        -- Keep order in sync so a later save does not drop names found only via pairs.
        local rebuilt = {}
        i = 1
        while out[i] ~= nil do
            rebuilt[i] = out[i]
            i = i + 1
        end
        markCount(rebuilt, i - 1)
        st.order = rebuilt
        return out
    end

    function IchaUI_ProfileActive()
        local st = store()
        if not st then return nil end
        local n = st.active
        if type(n) == "string" and type(st.byName[n]) == "table" then
            return n
        end
        return nil
    end

    -- Returns true, or false, "empty" / "exists" / "missing"
    function IchaUI_ProfileSave(name, overwrite)
        name = trim(name)
        if name == "" then return false, "empty" end
        if string.len(name) > 48 then name = string.sub(name, 1, 48) end
        local st = store()
        if not st then return false, "notready" end
        local existed = type(st.byName[name]) == "table"
        if existed and not overwrite then
            return false, "exists"
        end
        st.byName[name] = capture()
        if not existed then
            local i = countIdx(st.order) + 1
            st.order[i] = name
            markCount(st.order, i)
        else
            markCount(st.order, countIdx(st.order))
        end
        st.active = name
        return true
    end

    function IchaUI_ProfileDelete(name)
        name = trim(name)
        if name == "" then return false, "empty" end
        local st = store()
        if not st then return false, "notready" end
        if type(st.byName[name]) ~= "table" then
            return false, "missing"
        end
        st.byName[name] = nil
        local order = {}
        local old = st.order or {}
        local i, n, c
        i = 1
        c = 0
        while true do
            n = old[i]
            if n == nil then break end
            if n ~= name and type(st.byName[n]) == "table" then
                c = c + 1
                order[c] = n
            end
            i = i + 1
            if i > 5000 then break end
        end
        markCount(order, c)
        st.order = order
        if st.active == name then st.active = nil end
        return true
    end

    function IchaUI_ApplySavedSettings()
        safe(IchaUI_ReloadLayoutFromDB)
        safe(function()
            local keys = { "player", "target", "tot", "focus" }
            local kinds = { "player", "target", "tot", "party", "raid", "combat", "focus" }
            local i, fr
            for i = 1, table.getn(keys) do
                if type(IchaUIUF_Get) == "function" then
                    fr = IchaUIUF_Get(keys[i])
                    if fr and type(fr.applySaved) == "function" then
                        fr.applySaved(fr)
                    end
                end
            end
            safe(IchaUIUF_ApplyPartySaved)
            safe(IchaUIUF_restorePartyRootPos)
            safe(IchaUIUF_restoreRaidRootPos)
            if type(IchaUIUF_hideBlizzard) == "function" then
                local hide = true
                if IchaUIDB and IchaUIDB.uf and IchaUIDB.uf.hideBlizzard == false then
                    hide = false
                end
                IchaUIUF_hideBlizzard(hide)
            end
            safe(IchaUIUF_hideBlizzardCastBar)
            safe(IchaUI_RefreshGoldTheme)
            safe(IchaUIUF_ApplyAll)
            if type(IchaUIUF_refreshTextKind) == "function" then
                for i = 1, table.getn(kinds) do
                    IchaUIUF_refreshTextKind(kinds[i])
                end
            end
            safe(IchaUI_CombatLayout)
        end)
        safe(IchaUITotems_ReloadFromDB)
        if type(IchaUITotems_ReloadFromDB) ~= "function" then
            safe(IchaUITotems_Apply)
        end
        safe(IchaUIShamanExtras_ReloadFromDB)
        if type(IchaUIShamanExtras_ReloadFromDB) ~= "function" then
            safe(IchaUIShamanExtras_Apply)
        end
        safe(IchaUIBuffBars_Reload)
        safe(IchaUIXP_Reload)
        safe(IchaUIMinimap_Reload)
        safe(IchaUIChatSkin_Reload)
        safe(IchaUIChat_Reload)
        safe(IchaPlates_Reload)
        safe(IchaUIFrameSkin_Reload)
        safe(IchaUI_TooltipSkin_Refresh)
        safe(IchaUI_TooltipAnchor_Apply)
        safe(IchaUIMinimapButtons_Refresh)
        safe(IchaUI_HeroReloadFromDB)
        safe(IchaUIShieldBinds_Reload)
        safe(IchaUI_TotemRecallReload)
        safe(IchaUI_ApplyIconStrata)
        safe(IchaUI_WorldMap_Reload)
        safe(function()
            local p = getglobal("IchaUIOptions")
            if p and type(p.refresh) == "function" then p.refresh() end
            if p and type(p.showTab) == "function" and IchaUIDB then
                local tab = IchaUIDB.optionsTab
                if tab == "Totems" then tab = "Drawers" end
                if tab == "Extras" then tab = "Skin" end
                if tab == "Text" then tab = "Frames" end
                if type(tab) == "string" and tab ~= "" then
                    p.showTab(tab)
                end
            end
            if type(IchaUI_ProfileBarRefresh) == "function" then
                IchaUI_ProfileBarRefresh()
            end
        end)
    end

    function IchaUI_ProfileLoad(name)
        name = trim(name)
        if name == "" then return false, "empty" end
        local st = store()
        if not st then return false, "notready" end
        local snap = st.byName[name]
        if type(snap) ~= "table" then
            return false, "missing"
        end
        if not restore(snap) then
            return false, "missing"
        end
        if type(IchaUI_ApplyBakedDefaults) == "function" then
            IchaUI_ApplyBakedDefaults()
        end
        st.active = name
        IchaUI_ApplySavedSettings()
        return true
    end

    local boot = CreateFrame("Frame", "IchaUIProfilesBoot")
    boot:RegisterEvent("ADDON_LOADED")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", function()
        if event == "ADDON_LOADED" and arg1 ~= "IchaUI" then return end
        ready = true
        if type(IchaUI_ProfileBarRefresh) == "function" then
            IchaUI_ProfileBarRefresh()
        end
    end)
end

installIchaUIProfiles()
