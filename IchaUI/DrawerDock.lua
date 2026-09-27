-- IchaUI DrawerDock: dock any drawer main button to a UI parent or portrait rim.
-- Saved in IchaUIDB.drawerDock[id]:
--   { mode = "free"|"frame"|"portrait",
--     parent, point, relPoint, x, y,   -- frame mode
--     unit, angle, ox, oy }             -- portrait mode
--
-- Public API (Options + consumers):
--   IchaUI_DrawerDockGet(id) -> copy of dock row or nil
--   IchaUI_DrawerDockSet(id, fields)  merge; mode "free" or non-table clears; nil mode merges; Apply
--   IchaUI_DrawerDockClear(id) -> free
--   IchaUI_DrawerDockApply(id, frame) -> true if docked SetPoint applied
--   IchaUI_DrawerDockApplyAll()
--   IchaUI_DrawerDockRegister(id, frame) / IchaUI_DrawerDockUnregister(id)
--   IchaUI_DrawerDockOnPortraitChanged(unitKey)
--   IchaUI_DrawerDockModeOpts() / ParentOpts() / PortraitOpts()
--   IchaUI_DrawerDockResolveParent(parentSpec) -> Frame or nil
--   IchaUI_DrawerDockResolveFrame(id) -> Frame or nil
--   IchaUI_DrawerDockNormalizeMode(m) -> "free"|"frame"|"portrait"|nil
--   IchaUI_DrawerDockIsDocked(id) -> boolean
--
-- Frames: call IchaUI_DrawerDockOnPortraitChanged(key) after portrait applySize / shape set.
-- Lua 5.0 only (no #, prefer globals, clamp angle 0..360).

IchaUI_DrawerDockFrames = IchaUI_DrawerDockFrames or {}
-- Strong refs: drop any prior weak metatable so registered frames survive GC.
do
    local mt = getmetatable(IchaUI_DrawerDockFrames)
    if mt then setmetatable(IchaUI_DrawerDockFrames, nil) end
    IchaUI_DrawerDockFrames._weak = nil
end

IchaUI_DrawerDockUFKeys = { "player", "target", "tot", "focus" }
IchaUI_DrawerDockUFLabels = {
    player = "Player",
    target = "Target",
    tot = "ToT",
    focus = "Focus",
}

-- Normalize mode string: lowercase; empty/nil -> nil; only free|frame|portrait valid.
-- Unknown modes return nil (caller keeps prior mode; never wipe on unknown).
function IchaUI_DrawerDockNormalizeMode(m)
    if m == nil then return nil end
    if type(m) ~= "string" then return nil end
    m = string.lower(m)
    if m == "" then return nil end
    if m == "free" or m == "frame" or m == "portrait" then return m end
    return nil
end

-- Resolve a dock id to its live frame: registered table first, then known globals.
function IchaUI_DrawerDockResolveFrame(id)
    if not id then return nil end
    local fr = IchaUI_DrawerDockFrames[id]
    if fr then return fr end
    if not getglobal then return nil end
    local map = {
        totems = "IchaUITotemsRoot",
        imbue = "IchaUIImbueRoot",
        shield = "IchaUIShieldRoot",
        utility = "IchaUIUtilityRoot",
        recall = "IchaUITotemRecallIcon",
        resists = "IchaUIUF_TankCaret",
    }
    local name = map[id]
    if name then
        fr = getglobal(name)
        if fr then return fr end
        if id == "resists" then
            fr = getglobal("IchaUIUF_TankDrawer")
            if fr then return fr end
        end
        return nil
    end
    -- Custom drawers: cd:<id> -> IchaUICustomDrawer<id>
    if type(id) == "string" and string.sub(id, 1, 3) == "cd:" then
        local cid = string.sub(id, 4)
        if cid and cid ~= "" then
            fr = getglobal("IchaUICustomDrawer" .. cid)
            if fr then return fr end
        end
    end
    return nil
end

-- Ensure Frames[id] is populated when Resolve finds a live global.
function IchaUI_DrawerDockEnsureFrame(id)
    if not id then return nil end
    local fr = IchaUI_DrawerDockFrames[id]
    if fr then return fr end
    fr = IchaUI_DrawerDockResolveFrame(id)
    if fr then
        IchaUI_DrawerDockFrames[id] = fr
    end
    return fr
end

function IchaUI_DrawerDockBag()
    if not IchaUIDB then IchaUIDB = {} end
    if not IchaUIDB.drawerDock then IchaUIDB.drawerDock = {} end
    local bag = IchaUIDB.drawerDock
    -- 1) Split accidental shared row tables (same ref under two ids).
    local seen = {}
    local id, row
    for id, row in pairs(bag) do
        if type(row) == "table" then
            if seen[row] then
                bag[id] = IchaUI_DrawerDockCopyRow(row)
            else
                seen[row] = id
            end
            -- Normalize known modes in place. Unknown/empty: leave row intact (never wipe).
            local nm = IchaUI_DrawerDockNormalizeMode(row.mode)
            if nm then
                row.mode = nm
            end
        end
    end
    -- 2) If older UI copied one portrait blob onto many ids (same unit/angle/ox/oy),
    --    keep the first, give the rest unique default angles so they stop stacking.
    if not IchaUI_DrawerDockMigratedDupes then
        IchaUI_DrawerDockMigratedDupes = true
        local groups = {}
        for id, row in pairs(bag) do
            if type(row) == "table" and IchaUI_DrawerDockNormalizeMode(row.mode) == "portrait" then
                local sig = tostring(row.unit or "player") .. "|"
                    .. tostring(tonumber(row.angle) or 0) .. "|"
                    .. tostring(tonumber(row.ox) or 0) .. "|"
                    .. tostring(tonumber(row.oy) or 0)
                if not groups[sig] then groups[sig] = {} end
                groups[sig][table.getn(groups[sig]) + 1] = id
            end
        end
        local sig, list
        for sig, list in pairs(groups) do
            if table.getn(list) > 1 then
                local i
                for i = 2, table.getn(list) do
                    local did = list[i]
                    local r = bag[did]
                    if type(r) == "table" then
                        r = IchaUI_DrawerDockCopyRow(r) or {}
                        r.angle = IchaUI_DrawerDockDefaultAngle(did)
                        bag[did] = r
                    end
                end
            end
        end
    end
    return bag
end

function IchaUI_DrawerDockClampAngle(ang)
    ang = tonumber(ang) or 0
    while ang < 0 do ang = ang + 360 end
    while ang > 360 do ang = ang - 360 end
    if ang > 360 then ang = 360 end
    if ang < 0 then ang = 0 end
    return ang
end

-- Stable default portrait angle so newly-docked drawers do not stack.
function IchaUI_DrawerDockDefaultAngle(id)
    local map = {
        totems = 270, recall = 225, imbue = 0, shield = 90,
        utility = 180, resists = 315,
    }
    if map[id] then return map[id] end
    if type(id) == "string" and string.sub(id, 1, 3) == "cd:" then
        local s = string.sub(id, 4)
        local i, h = 1, 0
        for i = 1, string.len(s) do
            h = h + string.byte(s, i)
        end
        return IchaUI_DrawerDockClampAngle(h * 37)
    end
    return 0
end

function IchaUI_DrawerDockCopyRow(row)
    if type(row) ~= "table" then return nil end
    local out = {}
    local k, v
    for k, v in pairs(row) do
        out[k] = v
    end
    return out
end

function IchaUI_DrawerDockGet(id)
    if not id then return nil end
    local bag = IchaUI_DrawerDockBag()
    local row = bag[id]
    if type(row) ~= "table" then return nil end
    local mode = IchaUI_DrawerDockNormalizeMode(row.mode)
    if not mode or mode == "free" then return nil end
    local out = IchaUI_DrawerDockCopyRow(row)
    if out then out.mode = mode end
    return out
end

function IchaUI_DrawerDockIsDocked(id)
    if not id or not IchaUIDB or not IchaUIDB.drawerDock then return false end
    local row = IchaUIDB.drawerDock[id]
    if type(row) ~= "table" then return false end
    local mode = IchaUI_DrawerDockNormalizeMode(row.mode)
    if mode == "frame" or mode == "portrait" then return true end
    return false
end

function IchaUI_DrawerDockClear(id)
    if not id then return end
    local bag = IchaUI_DrawerDockBag()
    bag[id] = nil
    -- Apply free (no-op dock); never depends on Frames being present.
    IchaUI_DrawerDockApply(id, IchaUI_DrawerDockEnsureFrame(id))
end

function IchaUI_DrawerDockSet(id, fields)
    if not id then return end
    local bag = IchaUI_DrawerDockBag()
    -- Non-table fields = clear. Explicit mode "free" = clear.
    -- mode == nil means partial update (angle/ox/oy/x/y) — merge, do not wipe.
    -- Unknown mode strings are ignored (keep prior mode); never wipe the row.
    if type(fields) ~= "table" then
        bag[id] = nil
        IchaUI_DrawerDockApply(id, IchaUI_DrawerDockEnsureFrame(id))
        return
    end
    local wantMode = nil
    local modeGiven = false
    if fields.mode ~= nil then
        modeGiven = true
        wantMode = IchaUI_DrawerDockNormalizeMode(fields.mode)
        if fields.mode == "free" or (type(fields.mode) == "string" and string.lower(fields.mode) == "free") then
            bag[id] = nil
            IchaUI_DrawerDockApply(id, IchaUI_DrawerDockEnsureFrame(id))
            return
        end
    end
    -- Fresh row every Set so two drawer ids never share one table reference.
    local prev = bag[id]
    local row = {}
    local hadAngle = false
    if type(prev) == "table" then
        local k, v
        for k, v in pairs(prev) do
            row[k] = v
        end
        if prev.angle ~= nil then hadAngle = true end
    end
    local k, v
    for k, v in pairs(fields) do
        if k == "mode" then
            -- handled below via wantMode / prior
        else
            row[k] = v
            if k == "angle" then hadAngle = true end
        end
    end
    if modeGiven then
        if wantMode then
            row.mode = wantMode
        end
        -- else unknown mode: keep prior row.mode (already copied); do not wipe
    end
    -- Normalize whatever mode we ended with
    local mode = IchaUI_DrawerDockNormalizeMode(row.mode)
    if mode then row.mode = mode end
    bag[id] = row
    if mode == "portrait" then
        if not hadAngle then
            row.angle = IchaUI_DrawerDockDefaultAngle(id)
        else
            row.angle = IchaUI_DrawerDockClampAngle(row.angle)
        end
        row.ox = tonumber(row.ox) or 0
        row.oy = tonumber(row.oy) or 0
        if not row.unit or row.unit == "" then row.unit = "player" end
    elseif mode == "frame" then
        row.point = row.point or "CENTER"
        row.relPoint = row.relPoint or row.point or "CENTER"
        row.x = tonumber(row.x) or 0
        row.y = tonumber(row.y) or 0
        if not row.parent or row.parent == "" then row.parent = "UIParent" end
    end
    -- Partial / nil mode: keep merged row; Apply is a no-op until mode set.
    -- Never bag[id]=nil for unknown mode.
    IchaUI_DrawerDockApply(id, IchaUI_DrawerDockEnsureFrame(id))
end

function IchaUI_DrawerDockResolveParent(parentSpec)
    if not parentSpec or parentSpec == "" then return nil end
    if type(parentSpec) ~= "string" then
        if type(parentSpec) == "table" and parentSpec.GetName then return parentSpec end
        return nil
    end
    -- UF key: prefer .root for frame-mode docking.
    if IchaUIUF_Get then
        local fr = IchaUIUF_Get(parentSpec)
        if fr then
            if fr.root then return fr.root end
            if fr.GetName then return fr end
        end
    end
    -- Named global frame (and common aliases).
    local name = parentSpec
    if name == "IchaUITotemRoot" then name = "IchaUITotemsRoot" end
    if name == "totems" then name = "IchaUITotemsRoot" end
    if getglobal then
        local f = getglobal(name)
        if f and f.GetName then return f end
    end
    return nil
end

function IchaUI_DrawerDockApplyPortrait(id, frame, row)
    if not frame or type(row) ~= "table" then return false end
    local unit = row.unit or "player"
    local port = nil
    if IchaUIUF_PortraitDockParent then
        port = IchaUIUF_PortraitDockParent(unit)
    end
    if not port then
        local fr = IchaUIUF_Get and IchaUIUF_Get(unit)
        if fr and fr.portraitFrame then port = fr.portraitFrame end
    end
    if not port then return false end
    local sz = 36
    if frame.GetWidth then
        local w = frame:GetWidth()
        if w and w > 0 then sz = w end
    end
    -- Always pass a real angle for THIS id — never nil (PortraitDockXY would
    -- fall back to shared badgeAngle and stack every drawer on one spot).
    local ang
    if row.angle == nil then
        ang = IchaUI_DrawerDockDefaultAngle(id)
    else
        ang = IchaUI_DrawerDockClampAngle(row.angle)
    end
    local ox = tonumber(row.ox) or 0
    local oy = tonumber(row.oy) or 0
    local bx, by = 0, 0
    if IchaUIUF_PortraitDockXY then
        bx, by = IchaUIUF_PortraitDockXY(unit, ang, sz, ox, oy)
    end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", port, "CENTER", bx, by)
    if frame.SetFrameLevel and port.GetFrameLevel then
        local pl = port:GetFrameLevel() or 1
        frame:SetFrameLevel(pl + 5)
    end
    return true
end

function IchaUI_DrawerDockApplyFrame(id, frame, row)
    if not frame or type(row) ~= "table" then return false end
    local parent = IchaUI_DrawerDockResolveParent(row.parent)
    if not parent then return false end
    local point = row.point or "CENTER"
    local rel = row.relPoint or point
    local x = tonumber(row.x) or 0
    local y = tonumber(row.y) or 0
    frame:ClearAllPoints()
    frame:SetPoint(point, parent, rel, x, y)
    return true
end

function IchaUI_DrawerDockApply(id, frame)
    if not id then return false end
    if not frame then
        frame = IchaUI_DrawerDockEnsureFrame(id)
    elseif not IchaUI_DrawerDockFrames[id] then
        IchaUI_DrawerDockFrames[id] = frame
    end
    if not frame then return false end
    if not IchaUIDB or not IchaUIDB.drawerDock then return false end
    local raw = IchaUIDB.drawerDock[id]
    if type(raw) ~= "table" then return false end
    local row = IchaUI_DrawerDockCopyRow(raw)
    if not row then return false end
    local mode = IchaUI_DrawerDockNormalizeMode(row.mode)
    -- Failed Apply returns false only — never Clear / wipe mode.
    if mode == "portrait" then
        row.mode = mode
        return IchaUI_DrawerDockApplyPortrait(id, frame, row) and true or false
    end
    if mode == "frame" then
        row.mode = mode
        return IchaUI_DrawerDockApplyFrame(id, frame, row) and true or false
    end
    return false
end

function IchaUI_DrawerDockApplyAll()
    local bag = IchaUI_DrawerDockBag()
    local id, row
    for id, row in pairs(bag) do
        if type(row) == "table" then
            local mode = IchaUI_DrawerDockNormalizeMode(row.mode)
            if mode == "frame" or mode == "portrait" then
                local fr = IchaUI_DrawerDockEnsureFrame(id)
                if fr then IchaUI_DrawerDockApply(id, fr) end
            end
        end
    end
end

function IchaUI_DrawerDockRegister(id, frame)
    if not id or not frame then return end
    IchaUI_DrawerDockFrames[id] = frame
    IchaUI_DrawerDockApply(id, frame)
end

function IchaUI_DrawerDockUnregister(id)
    if not id then return end
    IchaUI_DrawerDockFrames[id] = nil
end

function IchaUI_DrawerDockOnPortraitChanged(unitKey)
    if not unitKey then return end
    if not IchaUIDB or not IchaUIDB.drawerDock then return end
    local bag = IchaUIDB.drawerDock
    local id, row
    for id, row in pairs(bag) do
        if type(row) == "table" and IchaUI_DrawerDockNormalizeMode(row.mode) == "portrait" and row.unit == unitKey then
            local fr = IchaUI_DrawerDockEnsureFrame(id)
            if fr then IchaUI_DrawerDockApplyPortrait(id, fr, row) end
        end
    end
end

function IchaUI_DrawerDockModeOpts()
    return {
        { id = "free", label = "Free" },
        { id = "frame", label = "Frame" },
        { id = "portrait", label = "Portrait edge" },
    }
end

function IchaUI_DrawerDockPortraitOpts()
    local out = {}
    local i
    for i = 1, table.getn(IchaUI_DrawerDockUFKeys) do
        local k = IchaUI_DrawerDockUFKeys[i]
        out[table.getn(out) + 1] = {
            id = k,
            label = IchaUI_DrawerDockUFLabels[k] or k,
        }
    end
    return out
end

function IchaUI_DrawerDockParentOpts()
    local out = {}
    local i
    for i = 1, table.getn(IchaUI_DrawerDockUFKeys) do
        local k = IchaUI_DrawerDockUFKeys[i]
        local ok = false
        if IchaUIUF_Get then
            local fr = IchaUIUF_Get(k)
            if fr and (fr.root or fr.GetName) then ok = true end
        end
        if ok then
            out[table.getn(out) + 1] = {
                id = k,
                label = IchaUI_DrawerDockUFLabels[k] or k,
            }
        end
    end
    local named = {
        { id = "UIParent", label = "UIParent" },
        { id = "Minimap", label = "Minimap" },
        { id = "IchaUITotemsRoot", label = "Totems root" },
        { id = "IchaUIImbueRoot", label = "Imbue root" },
        { id = "IchaUIShieldRoot", label = "Shield root" },
        { id = "IchaUIUtilityRoot", label = "Utility root" },
    }
    for i = 1, table.getn(named) do
        local e = named[i]
        local f = getglobal and getglobal(e.id)
        if f and f.GetName then
            out[table.getn(out) + 1] = e
        end
    end
    return out
end


-- Call after size/layout changes (Arc/scale/etc.) so portrait rim uses live sz.
function IchaUI_DrawerDockReapply(id)
    if not id then return false end
    return IchaUI_DrawerDockApply(id, IchaUI_DrawerDockEnsureFrame(id)) and true or false
end


-- Boot: Register often applies before UF portraits exist. Retry ApplyAll on
-- ADDON_LOADED / login / entering world, plus deferred passes so docks stick
-- after /reload once portrait parents exist. Never clears mode on failure.
do
    if not IchaUI_DrawerDockBoot then
        local boot = CreateFrame("Frame")
        IchaUI_DrawerDockBoot = boot
        boot._delay = nil
        boot._retryIdx = nil
        boot._retries = nil
        boot:RegisterEvent("ADDON_LOADED")
        boot:RegisterEvent("PLAYER_LOGIN")
        boot:RegisterEvent("PLAYER_ENTERING_WORLD")
        local function scheduleRetries()
            -- Immediate + 0.5 / 1.5 / 3.0s (and keep the prior ~0.75s feel via 0.5/1.5).
            this._retries = { 0, 0.5, 1.5, 3.0 }
            this._retryIdx = 1
            this._delay = 0
            this:SetScript("OnUpdate", function()
                local list = this._retries
                local idx = this._retryIdx
                if not list or not idx or idx > table.getn(list) then
                    this:SetScript("OnUpdate", nil)
                    this._delay = nil
                    this._retries = nil
                    this._retryIdx = nil
                    return
                end
                local target = list[idx]
                this._delay = (this._delay or 0) + (arg1 or 0)
                if this._delay < target then return end
                this._retryIdx = idx + 1
                if IchaUI_DrawerDockApplyAll then IchaUI_DrawerDockApplyAll() end
            end)
        end
        boot:SetScript("OnEvent", function()
            if event == "ADDON_LOADED" then
                if arg1 ~= "IchaUI" then return end
            end
            if IchaUI_DrawerDockApplyAll then IchaUI_DrawerDockApplyAll() end
            scheduleRetries()
        end)
    end
end
