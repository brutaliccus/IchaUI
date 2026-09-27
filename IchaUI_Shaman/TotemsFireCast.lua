-- Totems fire-cast helpers (own chunk: keeps Totems.lua under Lua 5.0 200-local limit).
-- Loaded before Totems.lua via IchaUI_Shaman.toc.

-- Chunk-local budget (Lua 5.0 limit 200): keep these helpers on one table
-- instead of three `local function` names (was tipping Totems.lua over the limit
-- at IchaUITotems_FireCast.parseUnitCastEvent — FrameXML: "too many local variables (limit=200)").
IchaUITotems_FireCast = {}
function IchaUITotems_FireCast.chatLooksLikeFireCastStart(msg)
    if not msg then return false end
    local l = string.lower(tostring(msg))
    -- Only CAST START lines — hits would re-sync mid-cast and skew the timer
    if not (string.find(l, "begin", 1, true) or string.find(l, "starts to cast", 1, true)
        or string.find(l, "begins to cast", 1, true) or string.find(l, "casting", 1, true)) then
        return false
    end
    -- Bolt only — NOT "Searing Totem" (that is the drop / summon)
    if string.find(l, "searing bolt", 1, true) then return true end
    if string.find(l, "searing totem", 1, true) then return false end
    return false
end

function IchaUITotems_FireCast.unitCastLooksLikeFire(hint)
    if not hint then return false end
    if type(hint) == "number" and type(SpellInfo) == "function" then
        local ok, nm = pcall(SpellInfo, hint)
        if ok and nm then hint = nm end
    end
    local s = tostring(hint)
    local l = string.lower(s)
    -- Ignore the totem summon itself (shows a fake cast on drop)
    if string.find(l, "totem", 1, true) and not string.find(l, "bolt", 1, true) then
        return false
    end
    if string.find(l, "searing bolt", 1, true) then return true end
    if string.find(l, "searingtotem", 1, true) then return false end
    -- Real bolt cast names only
    if string.find(l, "searing", 1, true) and string.find(l, "bolt", 1, true) then return true end
    return false
end

-- SuperWoW UNIT_CASTEVENT: typically caster, target, eventType, spellID, durationMs
function IchaUITotems_FireCast.parseUnitCastEvent()
    local a1, a2, a3, a4, a5 = arg1, arg2, arg3, arg4, arg5
    local eventType, spellId, durMs = nil, nil, nil
    -- Common SuperWoW shape
    if type(a3) == "string" and type(a4) == "number" then
        eventType, spellId, durMs = a3, a4, a5
    elseif type(a2) == "string" and type(a3) == "number" then
        eventType, spellId, durMs = a2, a3, a4
    elseif type(a4) == "number" and type(a5) == "number" then
        spellId, durMs = a4, a5
    end
    local spellName = nil
    if type(spellId) == "number" and type(SpellInfo) == "function" then
        local ok, nm = pcall(SpellInfo, spellId)
        if ok then spellName = nm end
    end
    if not spellName then
        -- fall back to scanning args for name tokens
        local hints = { a1, a2, a3, a4, a5 }
        local hi
        for hi = 1, table.getn(hints) do
            if IchaUITotems_FireCast.unitCastLooksLikeFire(hints[hi]) then
                if type(hints[hi]) == "number" and SpellInfo then
                    local ok, nm = pcall(SpellInfo, hints[hi])
                    if ok then spellName = nm end
                else
                    spellName = tostring(hints[hi])
                end
                break
            end
        end
    end
    return eventType, spellId, spellName, durMs
end

