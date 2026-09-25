-- IchaPlates: modules/nameplates.lua (ported from ShaguPlatesX modules/nameplates.lua).
-- ShaguPlatesX: Copyright (c) 2016-2021 Eric Mauser (Shagu), adapted by Ehawne.
-- MIT License, see LICENSE-ShaguPlates.txt. Derived from pfUI by Shagu.

IchaPlates:RegisterModule("nameplates", "vanilla", function ()
  -- disable original castbars
  pcall(SetCVar, "ShowVKeyCastbar", 0)

  local unitcolors = {
    ["ENEMY_NPC"] = { .9, .2, .3, .8 },
    ["NEUTRAL_NPC"] = { 1, 1, .3, .8 },
    ["FRIENDLY_NPC"] = { .6, 1, 0, .8 },
    ["ENEMY_PLAYER"] = { .9, .2, .3, .8 },
    ["FRIENDLY_PLAYER"] = { .2, .6, 1, .8 }
  }

  local combatstate = {
    -- gets overwritten by user config
    ["NOTHREAT"] = { r = 1, g = 0, b = 0, a = 1 },     -- Red: not targeting you
    ["THREAT"]   = { r = 0, g = 1, b = 0, a = 1 },     -- Green: targeting you (has aggro)
    ["CASTING"]  = { r = .7, g = .2, b = .7, a = 1 },  -- Purple: casting
    ["STUN"]     = { r = 1, g = 1, b = 0, a = .6 },    -- Yellow: stunned/no target
    ["NONE"]     = { r = .2, g = .2, b = .2, a = 1 },
  }

  local elitestrings = {
    ["elite"] = "+",
    ["rareelite"] = "R+",
    ["rare"] = "R",
    ["boss"] = "B"
  }

  -- catch all nameplates
  local childs, regions, plate
  local initialized = 0
  local parentcount = 0
  local platecount = 0
  local registry = {}
  local debuffdurations = C.appearance.cd.debuffs == "1" and true or nil

  -- SuperWoW performance optimization: GUID-based registry for O(1) lookups
  local guidRegistry = {}   -- guid -> plate
  local castEvents = {}     -- guid -> cast info
  local debuffCache = {}    -- guid -> { [spellID] = { start, duration } }
  local threatMemory = {}   -- guid -> true if mob had player targeted (persists through casts)

  -- wipe polyfill
  local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end end

  -- Throttle constants
  local THROTTLE_INTERVAL = 0.1   -- 100ms for all plates

  -- Cache frequently accessed config values (updated on config change)
  local cfg_showcastbar, cfg_targetcastbar, cfg_notargalpha, cfg_namefightcolor
  local cfg_spellname, cfg_showhp, cfg_showdebuffs
  local cfg_targetzoom, cfg_zoomval, cfg_zoominstant, cfg_width, cfg_heighthealth

  -- store SuperAPI_Castlib original scripts for restore
  local superapi_castlib_stored = false
  local superapi_castlib_onupdate, superapi_castlib_onevent

  local function CacheConfig()
    cfg_showcastbar = C.nameplates["showcastbar"] == "1"
    cfg_targetcastbar = C.nameplates["targetcastbar"] == "1"

    -- manage SuperAPI_Castlib based on our castbar setting
    if C.global.override_superapi_castlib == "1" and SuperAPI_Castlib then
      if cfg_showcastbar then
        -- store and disable SuperAPI_Castlib
        if not superapi_castlib_stored then
          superapi_castlib_onupdate = SuperAPI_Castlib:GetScript("OnUpdate")
          superapi_castlib_onevent = SuperAPI_Castlib:GetScript("OnEvent")
          superapi_castlib_stored = true
          SuperAPI_Castlib:UnregisterAllEvents()
          SuperAPI_Castlib:SetScript("OnUpdate", nil)
          SuperAPI_Castlib:SetScript("OnEvent", nil)
          SuperAPI_nameplatebars = false
        end
      elseif superapi_castlib_stored then
        -- restore SuperAPI_Castlib
        SuperAPI_Castlib:RegisterEvent("UNIT_CASTEVENT")
        SuperAPI_Castlib:SetScript("OnUpdate", superapi_castlib_onupdate)
        SuperAPI_Castlib:SetScript("OnEvent", superapi_castlib_onevent)
        SuperAPI_nameplatebars = true
        superapi_castlib_stored = false
      end
    end
    cfg_notargalpha = tonumber(C.nameplates.notargalpha) or 0.5
    cfg_namefightcolor = C.nameplates.namefightcolor == "1"
    cfg_spellname = C.nameplates.spellname == "1"
    cfg_showhp = C.nameplates.showhp == "1"
    cfg_showdebuffs = C.nameplates["showdebuffs"] == "1"
    cfg_targetzoom = C.nameplates.targetzoom == "1"
    cfg_zoomval = (tonumber(C.nameplates.targetzoomval) or 0.4) + 1
    cfg_zoominstant = C.nameplates.targetzoominstant == "1"
    cfg_width = tonumber(C.nameplates.width) or 120
    cfg_heighthealth = tonumber(C.nameplates.heighthealth) or 8
  end

  -- cache default border color
  local er, eg, eb, ea = GetStringColor(IchaPlates_config.appearance.border.color)

  -- IchaUI theme: plate borders take the IchaUI gold instead of the configured color.
  local function ThemeOn()
    return C.icha and C.icha.theme == "1" and IchaUI_Gold and true or false
  end

  local function CacheBorderColor()
    er, eg, eb, ea = GetStringColor(C.appearance.border.color)
    if ThemeOn() then
      er, eg, eb = IchaUI_Gold()
      ea = 1
    end
  end
  CacheBorderColor()

  local function ThemeBorder(frame)
    if not frame or not ThemeOn() then return end
    if frame.backdrop then frame.backdrop:SetBackdropBorderColor(er, eg, eb, ea) end
  end

  local function GetCombatStateColor(guid)
    -- plates without a SuperWoW guid have no unit to ask
    if not guid or guid == "" then return false end
    local target = guid.."target"
    local color = false

    if UnitAffectingCombat("player") and UnitAffectingCombat(guid) and not UnitCanAssist("player", guid) then
      local isCasting = castEvents[guid] and castEvents[guid].endTime and GetTime() < castEvents[guid].endTime
      local targetingPlayer = UnitIsUnit(target, "player")

      -- Remember if mob targets player, clear only when targeting someone else while NOT casting
      if targetingPlayer then
        threatMemory[guid] = true
      elseif UnitExists(target) and not isCasting then
        threatMemory[guid] = nil
      end

      if C.nameplates.ccombatcasting == "1" and isCasting then
        color = combatstate.CASTING
      elseif C.nameplates.ccombatthreat == "1" and (targetingPlayer or threatMemory[guid]) then
        color = combatstate.THREAT
      elseif C.nameplates.ccombatnothreat == "1" and UnitExists(target) then
        color = combatstate.NOTHREAT
      elseif C.nameplates.ccombatstun == "1" and not UnitExists(target) and not UnitIsPlayer(guid) then
        color = combatstate.STUN
      end
    end

    return color
  end

  local function DoNothing()
    return
  end

  local function IsNamePlate(frame)
    if frame:GetObjectType() ~= NAMEPLATE_FRAMETYPE then return nil end
    regions = plate:GetRegions()

    if not regions then return nil end
    if not regions.GetObjectType then return nil end
    if not regions.GetTexture then return nil end

    if regions:GetObjectType() ~= "Texture" then return nil end
    return regions:GetTexture() == "Interface\\Tooltips\\Nameplate-Border" or nil
  end

  local function DisableObject(object)
    if not object then return end
    if not object.GetObjectType then return end

    local otype = object:GetObjectType()

    if otype == "Texture" then
      object:SetTexture("")
      object:SetTexCoord(0, 0, 0, 0)
    elseif otype == "FontString" then
      object:SetWidth(0.001)
    elseif otype == "StatusBar" then
      object:SetStatusBarTexture("")
    end
  end

  local function TotemPlate(name)
    if C.nameplates.totemicons == "1" then
      for totem, icon in pairs(L["totems"]) do
        if string.find(name, totem) then return icon end
      end
    end
  end

  local function HidePlate(unittype, name, fullhp, target)
    -- keep some plates always visible according to config
    if C.nameplates.fullhealth == "1" and not fullhp then return nil end
    if C.nameplates.target == "1" and target then return nil end

    -- return true when something needs to be hidden
    if C.nameplates.enemynpc == "1" and unittype == "ENEMY_NPC" then
      return true
    elseif C.nameplates.enemyplayer == "1" and unittype == "ENEMY_PLAYER" then
      return true
    elseif C.nameplates.neutralnpc == "1" and unittype == "NEUTRAL_NPC" then
      return true
    elseif C.nameplates.friendlynpc == "1" and unittype == "FRIENDLY_NPC" then
      return true
    elseif C.nameplates.friendlyplayer == "1" and unittype == "FRIENDLY_PLAYER" then
      return true
    elseif C.nameplates.critters == "1" and unittype == "NEUTRAL_NPC" then
      for i, critter in pairs(L["critters"]) do
        if string.lower(name) == string.lower(critter) then return true end
      end
    elseif C.nameplates.totems == "1" then
      for totem in pairs(L["totems"]) do
        if string.find(name, totem) then return true end
      end
    end

    -- nothing to hide
    return nil
  end

  local function abbrevname(t)
    return string.sub(t,1,1)..". "
  end

  local function GetNameString(name)
    local abbrev = IchaPlates_config.unitframes.abbrevname == "1" or nil
    local size = 20

    -- first try to only abbreviate the first word
    if abbrev and name and strlen(name) > size then
      name = string.gsub(name, "^(%S+) ", abbrevname)
    end

    -- abbreviate all if it still doesn't fit
    if abbrev and name and strlen(name) > size then
      name = string.gsub(name, "(%S+) ", abbrevname)
    end

    return name
  end


  local function GetUnitType(red, green, blue)
    if red > .9 and green < .2 and blue < .2 then
      return "ENEMY_NPC"
    elseif red > .9 and green > .9 and blue < .2 then
      return "NEUTRAL_NPC"
    elseif red < .2 and green < .2 and blue > 0.9 then
      return "FRIENDLY_PLAYER"
    elseif red < .2 and green > .9 and blue < .2 then
      return "FRIENDLY_NPC"
    end
  end

  local filter, list, cache
  local function DebuffFilterPopulate()
    -- initialize variables
    filter = C.nameplates["debuffs"]["filter"]
    if filter == "none" then return end
    list = C.nameplates["debuffs"][filter]
    cache = {}

    -- populate list
    for _, val in pairs({strsplit("#", list)}) do
      cache[strlower(val)] = true
    end
  end

  local function DebuffFilter(effect)
    if not filter then DebuffFilterPopulate() end
    if filter == "none" then return true end
    if not cache then DebuffFilterPopulate() end

    if filter == "blacklist" and cache[strlower(effect)] then
      return nil
    elseif filter == "blacklist" then
      return true
    elseif filter == "whitelist" and cache[strlower(effect)] then
      return true
    elseif filter == "whitelist" then
      return nil
    end
  end

  -- Debuff icons use the IchaUI aura look: 4:3 rect (height = debuffsize),
  -- same icon crop, round mask and gold edge as unit frame auras.
  local ROUNDMASK = "Interface\\AddOns\\IchaUI\\media\\roundmask.tga"

  local function DebuffDims()
    local h = tonumber(C.nameplates.debuffsize) or 14
    if h < 2 then h = 2 end
    local w = floor(h * 4 / 3 + 0.5)
    local edge = floor(w * 0.42 + 0.5)
    if edge < 8 then edge = 8 end
    if edge > 16 then edge = 16 end
    local outset = floor(w * 0.08 + 0.5)
    if outset < 2 then outset = 2 end
    return w, h, edge, outset
  end

  local function DebuffAspect(tex, w, h)
    if IchaUI_ApplyAuraAspect then
      IchaUI_ApplyAuraAspect(tex, w, h)
      return
    end
    local pad, span = 0.07, 0.86
    if w > h then
      local crop = (1 - (h / w)) / 2
      tex:SetTexCoord(pad, 1 - pad, pad + crop * span, 1 - pad - crop * span)
    elseif w < h then
      local crop = (1 - (w / h)) / 2
      tex:SetTexCoord(pad + crop * span, 1 - pad - crop * span, pad, 1 - pad)
    else
      tex:SetTexCoord(pad, 1 - pad, pad, 1 - pad)
    end
  end

  local function DebuffBorder(debuff, edge, outset)
    local border = debuff.border
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", debuff, "TOPLEFT", -outset, outset)
    border:SetPoint("BOTTOMRIGHT", debuff, "BOTTOMRIGHT", outset, -outset)
    border:SetBackdrop({
      bgFile = nil,
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true, tileSize = 8, edgeSize = edge,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    border:SetBackdropColor(0, 0, 0, 0)
    if IchaUI_PaintGoldBorder then
      IchaUI_PaintGoldBorder(border, 1)
    else
      border:SetBackdropBorderColor(0.75, 0.52, 0.04, 1)
    end
  end

  local function CreateDebuffIcon(plate, index)
    plate.debuffs[index] = CreateFrame("Frame", plate.platename.."Debuff"..index, plate)
    plate.debuffs[index]:Hide()
    plate.debuffs[index]:SetFrameLevel(1)

    plate.debuffs[index].icon = plate.debuffs[index]:CreateTexture(nil, "BACKGROUND")
    plate.debuffs[index].icon:SetTexture(.3,1,.8,1)
    plate.debuffs[index].icon:SetAllPoints(plate.debuffs[index])

    plate.debuffs[index].mask = plate.debuffs[index]:CreateTexture(nil, "ARTWORK")
    plate.debuffs[index].mask:SetTexture(ROUNDMASK)
    plate.debuffs[index].mask:SetVertexColor(0, 0, 0, 1)
    plate.debuffs[index].mask:SetAllPoints(plate.debuffs[index])

    -- levels: icon 1, gold edge 2, stacks + timer text 3
    plate.debuffs[index].border = CreateFrame("Frame", nil, plate.debuffs[index])
    plate.debuffs[index].border:SetFrameLevel(2)

    plate.debuffs[index].textLayer = CreateFrame("Frame", nil, plate.debuffs[index])
    plate.debuffs[index].textLayer:SetFrameLevel(3)
    plate.debuffs[index].textLayer:SetAllPoints(plate.debuffs[index])

    plate.debuffs[index].stacks = plate.debuffs[index].textLayer:CreateFontString(nil, "OVERLAY")
    plate.debuffs[index].stacks:SetAllPoints(plate.debuffs[index])
    plate.debuffs[index].stacks:SetJustifyH("RIGHT")
    plate.debuffs[index].stacks:SetJustifyV("BOTTOM")
    plate.debuffs[index].stacks:SetTextColor(1,1,0)

    if IchaPlates.client <= 11200 then
      -- create a fake animation frame on vanilla to improve performance
      plate.debuffs[index].cd = CreateFrame("Frame", plate.platename.."Debuff"..index.."Cooldown", plate.debuffs[index])
      plate.debuffs[index].cd:SetScript("OnUpdate", CooldownFrame_OnUpdateModel)
      plate.debuffs[index].cd.AdvanceTime = DoNothing
      plate.debuffs[index].cd.SetSequence = DoNothing
      plate.debuffs[index].cd.SetSequenceTime = DoNothing
    else
      -- use regular cooldown animation frames on burning crusade and later
      plate.debuffs[index].cd = CreateFrame(COOLDOWN_FRAME_TYPE, plate.platename.."Debuff"..index.."Cooldown", plate.debuffs[index], "CooldownFrameTemplate")
    end

    plate.debuffs[index].cd:SetAllPoints(plate.debuffs[index])
    plate.debuffs[index].cd.pfCooldownStyleAnimation = 0
    plate.debuffs[index].cd.pfCooldownType = "ALL"
    plate.debuffs[index].cd.pfCooldownTextLevel = 2
  end

  local function UpdateDebuffConfig(nameplate, i)
    if not nameplate.debuffs[i] then return end

    -- update debuff positions
    local width = tonumber(C.nameplates.width) or 120
    local debuffoffset = tonumber(C.nameplates.debuffoffset) or 4
    local w, h, edge, outset = DebuffDims()
    -- gold edges sit outside the icon: gap keeps neighbours from overlapping
    local gap = outset * 2
    local limit = floor((width + gap) / (w + gap))
    if limit < 1 then limit = 1 end
    local font = C.nameplates.use_unitfonts == "1" and IchaPlates.font_unit or IchaPlates.font_default
    local font_size = C.nameplates.use_unitfonts == "1" and C.global.font_unit_size or C.global.font_size
    local font_style = C.nameplates.name.fontstyle

    local aligna, alignb, offs, space
    if C.nameplates.debuffs["position"] == "BOTTOM" then
      aligna, alignb, offs, space = "TOPLEFT", "BOTTOMLEFT", -(debuffoffset + outset), -gap
    else
      aligna, alignb, offs, space = "BOTTOMLEFT", "TOPLEFT", debuffoffset + outset, gap
    end
    nameplate.debuffOutset = outset

    local debuff = nameplate.debuffs[i]
    debuff.stacks:SetFont(font, font_size, font_style)
    debuff:ClearAllPoints()
    if i == 1 then
      debuff:SetPoint(aligna, nameplate.health, alignb, outset, offs)
    elseif i <= limit then
      debuff:SetPoint("LEFT", nameplate.debuffs[i-1], "RIGHT", gap, 0)
    else
      debuff:SetPoint(aligna, nameplate.debuffs[i-limit], alignb, 0, space)
    end

    debuff:SetWidth(w)
    debuff:SetHeight(h)
    DebuffAspect(debuff.icon, w, h)
    DebuffBorder(debuff, edge, outset)
  end

  -- player GUID for cast event filtering
  local playerGUID = nil

  -- track which GUID has combo points (only one at a time)
  local comboPointGuid = nil

  -- create nameplate core
  local nameplates = CreateFrame("Frame", "IchaPlatesCore", UIParent)
  nameplates:RegisterEvent("PLAYER_ENTERING_WORLD")
  nameplates:RegisterEvent("PLAYER_TARGET_CHANGED")
  nameplates:RegisterEvent("UNIT_COMBO_POINTS")
  nameplates:RegisterEvent("PLAYER_COMBO_POINTS")
  nameplates:RegisterEvent("UNIT_AURA")
  nameplates:RegisterEvent("UNIT_CASTEVENT")

  -- Logout / zoning: the client tears down units while SuperWoW still resolves GUID
  -- tokens (ERROR #132). No scanning, GUID lookups or OnUpdates until the world is back.
  local IsLeaving = function() return IchaPlates:IsLeaving() end

  nameplates:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
      _, playerGUID = UnitExists("player")
      CacheConfig()
      CacheBorderColor()
      this:SetGameVariables()

    elseif IsLeaving() then
      return

    elseif event == "UNIT_AURA" then
      -- SuperWoW: arg1 is the unit GUID - direct O(1) lookup
      local guid = arg1
      local plate = guidRegistry[guid]
      if plate and plate.nameplate then
        plate.nameplate.auraUpdate = true

        -- Track debuff start times for duration display
        if debuffdurations then
          if not debuffCache[guid] then debuffCache[guid] = {} end
          local seen = {}

          -- Scan current debuffs and track new ones
          for i = 1, 16 do
            local texture, stacks, dtype, spellID = UnitDebuff(guid, i)
            if not texture then break end

            seen[spellID] = true
            if not debuffCache[guid][spellID] then
              -- New debuff - record start time and lookup duration
              local spellName = SpellInfo(spellID)
              local duration = L["debuffs"][spellName] and L["debuffs"][spellName][0] or nil
              debuffCache[guid][spellID] = { start = GetTime(), duration = duration }
            end
          end

          -- Clear expired debuffs from cache
          for spellID in pairs(debuffCache[guid]) do
            if not seen[spellID] then
              debuffCache[guid][spellID] = nil
            end
          end
        end
      end

    elseif event == "UNIT_CASTEVENT" then
      local casterGUID = arg1
      local eventType = arg3  -- "START", "CAST", "FAIL", "CHANNEL", "MAINHAND", "OFFHAND"
      local spellID = arg4
      local castDuration = arg5

      -- Own cast landing on a unit (arg2 = target GUID): recasting a DoT restarts its
      -- timer; Molten Blast (Turtle) gives Flame Shock back its spent 3s ticks while
      -- keeping start, so the tick phase is unchanged.
      if casterGUID == playerGUID and eventType == "CAST" and debuffdurations
        and spellID and arg2 and debuffCache[arg2] then
        local castName = SpellInfo(spellID)
        local lcast = castName and string.lower(castName)
        local molten = lcast and string.find(lcast, "molten blast", 1, true)
        local now = GetTime()
        local changed = nil
        for id, entry in pairs(debuffCache[arg2]) do
          local auraName = SpellInfo(id)
          local laura = auraName and string.lower(auraName)
          local base = auraName and L["debuffs"][auraName] and L["debuffs"][auraName][0]
          if molten then
            if laura and string.find(laura, "flame shock", 1, true) and entry.start then
              local elapsed = now - entry.start
              if elapsed >= 0 and (not entry.duration or elapsed < entry.duration) then
                entry.duration = (base or 15) + math.floor(elapsed / 3) * 3
                entry.stamp = now
                changed = true
              end
            end
          elseif id == spellID or (laura and laura == lcast) then
            entry.start = now
            if base then entry.duration = base end
            entry.stamp = now
            changed = true
          end
        end
        if changed then
          local plate = guidRegistry[arg2]
          if plate and plate.nameplate then plate.nameplate.auraUpdate = true end
        end
      end

      -- Skip player casts and melee
      if casterGUID == playerGUID then return end
      if eventType == "MAINHAND" or eventType == "OFFHAND" then return end

      -- Store cast data
      if eventType == "START" or eventType == "CHANNEL" then
        if not castEvents[casterGUID] then castEvents[casterGUID] = {} end
        wipe(castEvents[casterGUID])

        local spellName, _, icon = SpellInfo(spellID)
        castEvents[casterGUID].event = eventType
        castEvents[casterGUID].spellID = spellID
        castEvents[casterGUID].spellName = spellName
        castEvents[casterGUID].icon = icon
        castEvents[casterGUID].startTime = GetTime()
        castEvents[casterGUID].endTime = castDuration and GetTime() + castDuration / 1000
        castEvents[casterGUID].duration = castDuration and castDuration / 1000

      elseif eventType == "CAST" or eventType == "FAIL" then
        if castEvents[casterGUID] and castEvents[casterGUID].spellID == spellID then
          wipe(castEvents[casterGUID])
        end
      end

      -- Flag plate for castbar update
      local plate = guidRegistry[casterGUID]
      if plate and plate.nameplate then
        plate.nameplate.castUpdate = true
      end

    elseif event == "PLAYER_TARGET_CHANGED" then
      -- Flag target plate for update
      local _, targetGuid = UnitExists("target")
      if targetGuid then
        local plate = guidRegistry[targetGuid]
        if plate and plate.nameplate then
          plate.nameplate.targetUpdate = true
        end
      end

    elseif event == "PLAYER_COMBO_POINTS" or event == "UNIT_COMBO_POINTS" then
      -- Only update the plate that has/had combo points
      local _, newGuid = UnitExists("target")
      local cp = GetComboPoints("player", "target")

      -- Clear old combo point holder if different
      if comboPointGuid and comboPointGuid ~= newGuid then
        local oldPlate = guidRegistry[comboPointGuid]
        if oldPlate and oldPlate.nameplate then
          oldPlate.nameplate.comboUpdate = true
        end
      end

      -- Update new combo point holder
      if cp and cp > 0 and newGuid then
        comboPointGuid = newGuid
        local plate = guidRegistry[newGuid]
        if plate and plate.nameplate then
          plate.nameplate.comboUpdate = true
        end
      else
        comboPointGuid = nil
      end
    end
  end)

  -- Cache frame-level state (updated once per frame, used by all plates)
  local frameState = {
    now = 0,
    hasTarget = false,
    targetGuid = nil,
    hasMouseover = false,
  }

  nameplates:SetScript("OnUpdate", function()
    if IsLeaving() then
      this:Hide()
      return
    end

    -- Update frame-level cache once per frame
    frameState.now = GetTime()
    frameState.hasTarget,frameState.targetGuid = UnitExists("target")
    frameState.hasMouseover = UnitExists("mouseover")

    -- detect new nameplates
    parentcount = WorldFrame:GetNumChildren()
    if initialized < parentcount then
      childs = { WorldFrame:GetChildren() }
      for i = initialized + 1, parentcount do
        plate = childs[i]
        if IsNamePlate(plate) and not registry[plate] then
          nameplates.OnCreate(plate)
          registry[plate] = plate
        end
      end

      initialized = parentcount
    end

    -- central OnUpdate for all plates
    for plate in pairs(registry) do
      if plate:IsVisible() then
        nameplates.OnUpdate(plate, frameState)
      end
    end
  end)

  -- combat tracker
  nameplates.combat = CreateFrame("Frame")
  nameplates.combat:RegisterEvent("PLAYER_ENTER_COMBAT")
  nameplates.combat:RegisterEvent("PLAYER_LEAVE_COMBAT")
  nameplates.combat:SetScript("OnEvent", function()
    if event == "PLAYER_ENTER_COMBAT" then
      this.inCombat = 1
      if PlayerFrame then PlayerFrame.inCombat = 1 end
    elseif event == "PLAYER_LEAVE_COMBAT" then
      this.inCombat = nil
      if PlayerFrame then PlayerFrame.inCombat = nil end
    end
  end)

  -- Hiding the core frame stops the WorldFrame scan; hiding each overlay stops the
  -- debuff/cooldown OnUpdates parented to it. Resume shows them again.
  nameplates.SetLeaving = function(on)
    local p
    if on then
      nameplates:Hide()
      if nameplates.mouselook then nameplates.mouselook:Hide() end
      for p in pairs(registry) do
        if p.nameplate then p.nameplate:Hide() end
      end
    else
      for p in pairs(registry) do
        if p.nameplate then
          p.nameplate:Show()
          p.nameplate.tick = nil
          if p:IsVisible() then nameplates.OnShow(p) end
        end
      end
      nameplates:Show()
    end
  end

  nameplates.OnCreate = function(frame)
    local parent = frame or this
    platecount = platecount + 1
    local platename = "IchaPlate" .. platecount

    -- create IchaPlates nameplate overlay
    local nameplate = CreateFrame("Button", platename, parent)
    nameplate.platename = platename
    nameplate:EnableMouse(0)
    nameplate.parent = parent
    nameplate.cache = {}
    nameplate.original = {}

    -- Stagger tick to spread updates across frames (0.05s apart per plate)
    nameplate.tick = GetTime() + math.mod(platecount,10) * 0.05

    -- create shortcuts for all known elements and disable them
    nameplate.original.healthbar, nameplate.original.castbar = parent:GetChildren()
    DisableObject(nameplate.original.healthbar)
    DisableObject(nameplate.original.castbar)

    for i, object in pairs({parent:GetRegions()}) do
      if NAMEPLATE_OBJECTORDER[i] and NAMEPLATE_OBJECTORDER[i] == "raidicon" then
        nameplate[NAMEPLATE_OBJECTORDER[i]] = object
      elseif NAMEPLATE_OBJECTORDER[i] then
        nameplate.original[NAMEPLATE_OBJECTORDER[i]] = object
        DisableObject(object)
      else
        DisableObject(object)
      end
    end

    HookScript(nameplate.original.healthbar, "OnValueChanged", nameplates.OnValueChanged)

    -- adjust sizes and scaling of the nameplate
    local scale = tonumber(C.nameplates.scale) or 1
    nameplate:SetScale(UIParent:GetScale() * scale)

    nameplate.health = CreateFrame("StatusBar", nil, nameplate)
    nameplate.health:SetFrameLevel(4) -- keep above glow
    nameplate.health.text = nameplate.health:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameplate.health.text:SetAllPoints()
    nameplate.health.text:SetTextColor(1,1,1,1)

    nameplate.name = nameplate:CreateFontString(nil, "OVERLAY")
    local nameoffset = tonumber(C.nameplates.nameoffset) or 0
    nameplate.name:SetPoint("TOP", nameplate, "TOP", 0, nameoffset)

    nameplate.glow = nameplate:CreateTexture(nil, "BACKGROUND")
    nameplate.glow:SetPoint("CENTER", nameplate.health, "CENTER", 0, 0)
    nameplate.glow:SetTexture(IchaPlates.media["img:dot"])
    nameplate.glow:Hide()

    nameplate.guild = nameplate:CreateFontString(nil, "OVERLAY")
    nameplate.guild:SetPoint("BOTTOM", nameplate.health, "BOTTOM", 0, 0)

    nameplate.level = nameplate:CreateFontString(nil, "OVERLAY")
    nameplate.level:SetPoint("RIGHT", nameplate.health, "LEFT", -3, 0)

    nameplate.raidicon:SetParent(nameplate.health)
    nameplate.raidicon:SetDrawLayer("OVERLAY")
    nameplate.raidicon:SetTexture(IchaPlates.media["img:raidicons"])

    nameplate.totem = CreateFrame("Frame", nil, nameplate)
    nameplate.totem:SetPoint("CENTER", nameplate, "CENTER", 0, 0)
    nameplate.totem:SetHeight(32)
    nameplate.totem:SetWidth(32)
    nameplate.totem.icon = nameplate.totem:CreateTexture(nil, "OVERLAY")
    nameplate.totem.icon:SetTexCoord(.078, .92, .079, .937)
    nameplate.totem.icon:SetAllPoints()
    CreateBackdrop(nameplate.totem)

    do -- debuffs
      nameplate.debuffs = {}
      CreateDebuffIcon(nameplate, 1)
    end

    do -- combopoints
      local combopoints = { }
      for i = 1, 5 do
        combopoints[i] = CreateFrame("Frame", nil, nameplate)
        combopoints[i]:Hide()
        combopoints[i]:SetFrameLevel(8)
        combopoints[i].tex = combopoints[i]:CreateTexture("OVERLAY")
        combopoints[i].tex:SetAllPoints()

        if i < 3 then
          combopoints[i].tex:SetTexture(1, .3, .3, .75)
        elseif i < 4 then
          combopoints[i].tex:SetTexture(1, 1, .3, .75)
        else
          combopoints[i].tex:SetTexture(.3, 1, .3, .75)
        end
      end
      nameplate.combopoints = combopoints
    end

    do -- castbar
      local castbar = CreateFrame("StatusBar", nil, nameplate.health)
      castbar:Hide()

      castbar:SetScript("OnShow", function()
        if C.nameplates.debuffs["position"] == "BOTTOM" then
          local o = nameplate.debuffOutset or 0
          nameplate.debuffs[1]:SetPoint("TOPLEFT", this, "BOTTOMLEFT", o, -4 - o)
        end
      end)

      castbar:SetScript("OnHide", function()
        if C.nameplates.debuffs["position"] == "BOTTOM" then
          local o = nameplate.debuffOutset or 0
          nameplate.debuffs[1]:SetPoint("TOPLEFT", this:GetParent(), "BOTTOMLEFT", o, -4 - o)
        end
      end)

      castbar.text = castbar:CreateFontString(nil, "DIALOG", "GameFontNormal")
      castbar.text:SetPoint("RIGHT", castbar, "LEFT", -4, 0)
      castbar.text:SetNonSpaceWrap(false)
      castbar.text:SetTextColor(1,1,1,.5)

      castbar.spell = castbar:CreateFontString(nil, "DIALOG", "GameFontNormal")
      castbar.spell:SetPoint("CENTER", castbar, "CENTER")
      castbar.spell:SetNonSpaceWrap(false)
      castbar.spell:SetTextColor(1,1,1,1)

      castbar.icon = CreateFrame("Frame", nil, castbar)
      castbar.icon.tex = castbar.icon:CreateTexture(nil, "BORDER")
      castbar.icon.tex:SetAllPoints()

      nameplate.castbar = castbar
    end

    parent.nameplate = nameplate
    HookScript(parent, "OnShow", nameplates.OnShow)
    parent:SetScript("OnUpdate", nil)  -- Disable Blizzard's OnUpdate, we handle centrally

    nameplates.OnConfigChange(parent)
    nameplates.OnShow(parent)
  end

  nameplates.OnConfigChange = function(frame)
    local parent = frame
    local nameplate = frame.nameplate

    local font = C.nameplates.use_unitfonts == "1" and IchaPlates.font_unit or IchaPlates.font_default
    local font_size = C.nameplates.use_unitfonts == "1" and C.global.font_unit_size or C.global.font_size
    local font_style = C.nameplates.name.fontstyle
    local glowr, glowg, glowb, glowa = GetStringColor(C.nameplates.glowcolor)
    local hlr, hlg, hlb, hla = GetStringColor(C.nameplates.highlightcolor)
    local hptexture = IchaPlates.media[C.nameplates.healthtexture]
    local rawborder, default_border = GetBorderSize("nameplates")

    local plate_width = C.nameplates.width + 50
    local plate_height = C.nameplates.heighthealth + font_size + 5
    local plate_height_cast = C.nameplates.heighthealth + font_size + 5 + C.nameplates.heightcast + 5
    local combo_size = 5

    local width = tonumber(C.nameplates.width)
    local debuffsize = tonumber(C.nameplates.debuffsize)
    local healthoffset = tonumber(C.nameplates.health.offset)
    local nameoffset = tonumber(C.nameplates.nameoffset) or 0
    local scale = tonumber(C.nameplates.scale) or 1
    local orientation = C.nameplates.verticalhealth == "1" and "VERTICAL" or "HORIZONTAL"

    local c = combatstate -- load combat state colors
    c.CASTING.r, c.CASTING.g, c.CASTING.b, c.CASTING.a = GetStringColor(C.nameplates.combatcasting)
    c.THREAT.r, c.THREAT.g, c.THREAT.b, c.THREAT.a = GetStringColor(C.nameplates.combatthreat)
    c.NOTHREAT.r, c.NOTHREAT.g, c.NOTHREAT.b, c.NOTHREAT.a = GetStringColor(C.nameplates.combatnothreat)
    c.STUN.r, c.STUN.g, c.STUN.b, c.STUN.a = GetStringColor(C.nameplates.combatstun)

    nameplate:SetScale(UIParent:GetScale() * scale)
    nameplate:SetWidth(plate_width)
    nameplate:SetHeight(plate_height)
    nameplate:SetPoint("TOP", parent, "TOP", 0, 0)

    nameplate.name:ClearAllPoints()
    nameplate.name:SetPoint("TOP", nameplate, "TOP", 0, nameoffset)
    nameplate.name:SetFont(font, font_size, font_style)

    nameplate.health:SetOrientation(orientation)
    nameplate.health:ClearAllPoints()
    nameplate.health:SetPoint("TOP", nameplate, "CENTER", 0, healthoffset)
    nameplate.health:SetStatusBarTexture(hptexture)
    nameplate.health:SetWidth(C.nameplates.width)
    nameplate.health:SetHeight(C.nameplates.heighthealth)
    nameplate.health.hlr, nameplate.health.hlg, nameplate.health.hlb, nameplate.health.hla = hlr, hlg, hlb, hla

    CreateBackdrop(nameplate.health, default_border)

    nameplate.health.text:SetFont(font, font_size - 2, "OUTLINE")
    nameplate.health.text:SetJustifyH(C.nameplates.hptextpos)

    nameplate.guild:SetFont(font, font_size, font_style)

    nameplate.glow:SetWidth(C.nameplates.width + 60)
    nameplate.glow:SetHeight(C.nameplates.heighthealth + 30)
    nameplate.glow:SetVertexColor(glowr, glowg, glowb, glowa)

    nameplate.raidicon:ClearAllPoints()
    nameplate.raidicon:SetPoint(C.nameplates.raidiconpos, nameplate.health, C.nameplates.raidiconpos, C.nameplates.raidiconoffx, C.nameplates.raidiconoffy)
    nameplate.level:SetFont(font, font_size, font_style)
    nameplate.raidicon:SetWidth(C.nameplates.raidiconsize)
    nameplate.raidicon:SetHeight(C.nameplates.raidiconsize)

    for i=1,16 do
      UpdateDebuffConfig(nameplate, i)
    end

    for i=1,5 do
      nameplate.combopoints[i]:SetWidth(combo_size)
      nameplate.combopoints[i]:SetHeight(combo_size)
      nameplate.combopoints[i]:SetPoint("TOPRIGHT", nameplate.health, "BOTTOMRIGHT", -(i-1)*(combo_size+default_border*3), -default_border*3)
      CreateBackdrop(nameplate.combopoints[i], default_border)
    end

    nameplate.castbar:SetPoint("TOPLEFT", nameplate.health, "BOTTOMLEFT", 0, -default_border*3)
    nameplate.castbar:SetPoint("TOPRIGHT", nameplate.health, "BOTTOMRIGHT", 0, -default_border*3)
    nameplate.castbar:SetHeight(C.nameplates.heightcast)
    nameplate.castbar:SetStatusBarTexture(hptexture)
    nameplate.castbar:SetStatusBarColor(.9,.8,0,1)
    CreateBackdrop(nameplate.castbar, default_border)

    nameplate.castbar.text:SetFont(font, font_size, "OUTLINE")
    nameplate.castbar.spell:SetFont(font, font_size, "OUTLINE")
    nameplate.castbar.icon:SetPoint("BOTTOMLEFT", nameplate.castbar, "BOTTOMRIGHT", default_border*3, 0)
    nameplate.castbar.icon:SetPoint("TOPLEFT", nameplate.health, "TOPRIGHT", default_border*3, 0)
    nameplate.castbar.icon:SetWidth(C.nameplates.heightcast + default_border*3 + C.nameplates.heighthealth)
    CreateBackdrop(nameplate.castbar.icon, default_border)

    ThemeBorder(nameplate.castbar)
    ThemeBorder(nameplate.castbar.icon)
    ThemeBorder(nameplate.totem)
    for i=1,5 do
      ThemeBorder(nameplate.combopoints[i])
    end

    nameplates:OnDataChanged(nameplate)
  end

  nameplates.OnValueChanged = function()
    -- Just sync health bar, don't run full OnDataChanged
    local plate = this:GetParent().nameplate
    if plate and plate.health then
      plate.health:SetMinMaxValues(plate.original.healthbar:GetMinMaxValues())
      plate.health:SetValue(plate.original.healthbar:GetValue())
    end
  end

  nameplates.OnDataChanged = function(self, plate)
    local visible = plate:IsVisible()
    local hp = plate.original.healthbar:GetValue()
    local hpmin, hpmax = plate.original.healthbar:GetMinMaxValues()
    local name = plate.original.name:GetText()
    local level = plate.original.level:IsShown() and plate.original.level:GetObjectType() == "FontString" and tonumber(plate.original.level:GetText()) or "??"
    local target = plate.istarget
    local mouseover = UnitExists("mouseover") and plate.original.glow:IsShown() or nil
    local unitstr = target and "target" or mouseover and "mouseover" or nil
    local red, green, blue = plate.original.healthbar:GetStatusBarColor()
    local unittype = GetUnitType(red, green, blue) or "ENEMY_NPC"
    local font_size = C.nameplates.use_unitfonts == "1" and C.global.font_unit_size or C.global.font_size

    -- use superwow unit guid as unitstr if possible
    local guid = plate.parent:GetName(1)
    if guid == "" then guid = nil end
    if guid and not unitstr then
      unitstr = guid
    end

    -- get unit data directly from GUID
    local class, player, elite, guild
    if guid then
      local _, classToken = UnitClass(guid)
      class = classToken
      player = UnitIsPlayer(guid)
      elite = UnitClassification(guid)
      guild = GetGuildInfo(guid)
    end

    if player and unittype == "ENEMY_NPC" then unittype = "ENEMY_PLAYER" end
    elite = plate.original.levelicon:IsShown() and not player and "boss" or elite

    -- skip data updates on invisible frames
    if not visible then return end

    -- target event sometimes fires too quickly, where nameplate identifiers are not
    -- yet updated. So while being inside this event, we cannot trust the unitstr.
    if event == "PLAYER_TARGET_CHANGED" then unitstr = nil end

    -- remove unitstr on unit name mismatch
    if unitstr and UnitName(unitstr) ~= name then unitstr = nil end

    -- use mobhealth values if addon is running
    if (MobHealth3 or MobHealthFrame) and target and name == UnitName('target') and MobHealth_GetTargetCurHP() then
      hp = MobHealth_GetTargetCurHP() > 0 and MobHealth_GetTargetCurHP() or hp
      hpmax = MobHealth_GetTargetMaxHP() > 0 and MobHealth_GetTargetMaxHP() or hpmax
    end

    -- always make sure to keep plate visible
    plate:Show()

    if target and C.nameplates.targetglow == "1" then
      plate.glow:Show() else plate.glow:Hide()
    end

    -- target indicator
    if superwow_active and C.nameplates.outcombatstate == "1" then
      -- determine color based on combat state
      local color = GetCombatStateColor(guid)

      -- set border color
      if color then
        plate.health.backdrop:SetBackdropBorderColor(color.r, color.g, color.b, color.a)
      elseif ThemeOn() then
        plate.health.backdrop:SetBackdropBorderColor(er, eg, eb, ea)
      else
        color = combatstate.NONE
        plate.health.backdrop:SetBackdropBorderColor(color.r, color.g, color.b, color.a)
      end
    elseif target and C.nameplates.targethighlight == "1" then
      plate.health.backdrop:SetBackdropBorderColor(plate.health.hlr, plate.health.hlg, plate.health.hlb, plate.health.hla)
    elseif C.nameplates.outfriendlynpc == "1" and unittype == "FRIENDLY_NPC" then
      plate.health.backdrop:SetBackdropBorderColor(unpack(unitcolors[unittype]))
    elseif C.nameplates.outfriendly == "1" and unittype == "FRIENDLY_PLAYER" then
      plate.health.backdrop:SetBackdropBorderColor(unpack(unitcolors[unittype]))
    elseif C.nameplates.outneutral == "1" and strfind(unittype, "NEUTRAL") then
      plate.health.backdrop:SetBackdropBorderColor(unpack(unitcolors[unittype]))
    elseif C.nameplates.outenemy == "1" and strfind(unittype, "ENEMY") then
      plate.health.backdrop:SetBackdropBorderColor(unpack(unitcolors[unittype]))
    else
      plate.health.backdrop:SetBackdropBorderColor(er,eg,eb,ea)
    end

    -- hide frames according to the configuration
    local TotemIcon = TotemPlate(name)

    if TotemIcon then
      -- create totem icon
      plate.totem.icon:SetTexture("Interface\\Icons\\" .. TotemIcon)

      plate.glow:Hide()
      plate.level:Hide()
      plate.name:Hide()
      plate.health:Hide()
      plate.guild:Hide()
      plate.totem:Show()
    elseif HidePlate(unittype, name, (hpmax-hp == hpmin), target) then
      plate.level:SetPoint("RIGHT", plate.name, "LEFT", -3, 0)
      plate.name:SetParent(plate)
      plate.guild:SetPoint("BOTTOM", plate.name, "BOTTOM", -2, -(font_size + 2))

      plate.level:Show()
      plate.name:Show()
      plate.health:Hide()
      if guild and C.nameplates.showguildname == "1" then
        plate.glow:SetPoint("CENTER", plate.name, "CENTER", 0, -(font_size / 2) - 2)
      else
        plate.glow:SetPoint("CENTER", plate.name, "CENTER", 0, 0)
      end
      plate.totem:Hide()
    else
      plate.level:SetPoint("RIGHT", plate.health, "LEFT", -5, 0)
      plate.name:SetParent(plate.health)
      plate.guild:SetPoint("BOTTOM", plate.health, "BOTTOM", 0, -(font_size + 4))

      plate.level:Show()
      plate.name:Show()
      plate.health:Show()
      plate.glow:SetPoint("CENTER", plate.health, "CENTER", 0, 0)
      plate.totem:Hide()
    end

    plate.name:SetText(GetNameString(name))
    plate.level:SetText(string.format("%s%s", level, (elitestrings[elite] or "")))

    if guild and C.nameplates.showguildname == "1" then
      plate.guild:SetText(guild)
      if guild == GetGuildInfo("player") then
        plate.guild:SetTextColor(0, 0.9, 0, 1)
      else
        plate.guild:SetTextColor(0.8, 0.8, 0.8, 1)
      end
      plate.guild:Show()
    else
      plate.guild:Hide()
    end

    -- Health bar - only update when values change
    if plate.cache.hp ~= hp or plate.cache.hpmax ~= hpmax then
      plate.cache.hp = hp
      plate.cache.hpmax = hpmax
      plate.health:SetMinMaxValues(hpmin, hpmax)
      plate.health:SetValue(hp)

      if cfg_showhp then
        local rhp, rhpmax
        if guid and UnitHealthMax then
          rhp = UnitHealth(guid)
          rhpmax = UnitHealthMax(guid)
        elseif hpmax > 100 or (round(hpmax/100*hp) ~= hp) then
          rhp, rhpmax = hp, hpmax
        end

        if rhp and rhpmax then
          local setting = C.nameplates.hptextformat
          local pct = ceil(hp/hpmax*100)
          if setting == "curperc" then
            plate.health.text:SetText(Abbreviate(rhp).." | "..pct.."%")
          elseif setting == "cur" then
            plate.health.text:SetText(Abbreviate(rhp))
          elseif setting == "curmax" then
            plate.health.text:SetText(Abbreviate(rhp).." - "..Abbreviate(rhpmax))
          elseif setting == "curmaxs" then
            plate.health.text:SetText(Abbreviate(rhp).." / "..Abbreviate(rhpmax))
          elseif setting == "curmaxperc" then
            plate.health.text:SetText(Abbreviate(rhp).." - "..Abbreviate(rhpmax).." | "..pct.."%")
          elseif setting == "curmaxpercs" then
            plate.health.text:SetText(Abbreviate(rhp).." / "..Abbreviate(rhpmax).." | "..pct.."%")
          elseif setting == "deficit" then
            plate.health.text:SetText("-"..Abbreviate(rhpmax - rhp))
          else
            plate.health.text:SetText(pct.."%")
          end
        else
          plate.health.text:SetText(ceil(hp/hpmax*100).."%")
        end
      end
    end

    local r, g, b, a = unpack(unitcolors[unittype])

    if unittype == "ENEMY_PLAYER" and C.nameplates["enemyclassc"] == "1" and class and RAID_CLASS_COLORS[class] then
      r, g, b, a = RAID_CLASS_COLORS[class].r, RAID_CLASS_COLORS[class].g, RAID_CLASS_COLORS[class].b, 1
    elseif unittype == "FRIENDLY_PLAYER" and C.nameplates["friendclassc"] == "1" and class and RAID_CLASS_COLORS[class] then
      r, g, b, a = RAID_CLASS_COLORS[class].r, RAID_CLASS_COLORS[class].g, RAID_CLASS_COLORS[class].b, 1
    end

    if superwow_active and unitstr and UnitIsTapped(unitstr) and not UnitIsTappedByPlayer(unitstr) then
      r, g, b, a = .5, .5, .5, .8
    end

    if superwow_active and C.nameplates.barcombatstate == "1" then
      local color = GetCombatStateColor(guid)

      if color then
        r, g, b, a = color.r, color.g, color.b, color.a
      end
    end

    if r ~= plate.cache.r or g ~= plate.cache.g or b ~= plate.cache.b then
      plate.health:SetStatusBarColor(r, g, b, a)
      plate.cache.r, plate.cache.g, plate.cache.b = r, g, b
    end

    if r + g + b ~= plate.cache.namecolor and unittype == "FRIENDLY_PLAYER" and C.nameplates["friendclassnamec"] == "1" and class and RAID_CLASS_COLORS[class] then
      plate.name:SetTextColor(r, g, b, a)
      plate.cache.namecolor = r + g + b
    end

    -- update combopoints
    for i=1, 5 do plate.combopoints[i]:Hide() end
    if target and C.nameplates.cpdisplay == "1" then
      for i=1, GetComboPoints("target") do plate.combopoints[i]:Show() end
    end

    -- update debuffs - minimize Set calls
    local index = 1

    if cfg_showdebuffs and guid then
      for i = 1, 16 do
        local texture, stacks, dtype, spellID = UnitDebuff(guid, i)
        if not texture then break end

        local effect = SpellInfo(spellID)
        if effect and DebuffFilter(effect) then
          local debuff = plate.debuffs[index]
          if not debuff then
            CreateDebuffIcon(plate, index)
            UpdateDebuffConfig(plate, index)
            debuff = plate.debuffs[index]
          end

          -- Only update texture if changed
          if debuff.lastTexture ~= texture then
            debuff.lastTexture = texture
            debuff.icon:SetTexture(texture)
            DebuffAspect(debuff.icon, debuff:GetWidth(), debuff:GetHeight())
          end

          -- Only show if not already shown
          if not debuff.isShown then
            debuff.isShown = true
            debuff:Show()
          end

          -- Stacks - only update when changed
          local showStacks = stacks and stacks > 1
          if debuff.lastStacks ~= stacks then
            debuff.lastStacks = stacks
            if showStacks then
              debuff.stacks:SetText(stacks)
              debuff.stacks:Show()
            else
              debuff.stacks:Hide()
            end
          end

          -- Duration - only set timer when spell changes
          if debuffdurations then
            -- Ensure cache exists (handles race condition where UNIT_AURA fired before plate was registered)
            if not debuffCache[guid] then debuffCache[guid] = {} end
            if not debuffCache[guid][spellID] then
              local spellName = SpellInfo(spellID)
              local duration = L["debuffs"][spellName] and L["debuffs"][spellName][0] or nil
              debuffCache[guid][spellID] = { start = GetTime(), duration = duration }
            end

            local cache = debuffCache[guid][spellID]
            -- stamp moves on a recast / Molten Blast (UNIT_CASTEVENT above)
            if cache.duration and cache.start
              and (debuff.lastCdSpell ~= spellID or debuff.lastCdStamp ~= cache.stamp) then
              debuff.lastCdSpell = spellID
              debuff.lastCdStamp = cache.stamp
              debuff.cd:SetAlpha(0)
              debuff.cd:Show()
              CooldownFrame_SetTimer(debuff.cd, cache.start, cache.duration, 1)
            end
          end

          index = index + 1
        end
      end
    end

    -- hide remaining debuffs - only if currently shown
    for i = index, 16 do
      local debuff = plate.debuffs[i]
      if debuff and debuff.isShown then
        debuff.isShown = nil
        debuff.lastTexture = nil
        debuff.lastStacks = nil
        debuff.lastCdSpell = nil
        debuff:Hide()
      end
    end
  end

  nameplates.OnShow = function(frame)
    local frame = frame or this
    local nameplate = frame.nameplate
    if IsLeaving() then return end

    -- SuperWoW: Register plate in GUID registry for O(1) lookups
    local guid = frame:GetName(1)
    if guid and guid ~= "" then
      -- Clear old GUID mapping if plate was reused (but keep debuff cache - it's keyed by GUID globally)
      if nameplate.lastGuid and nameplate.lastGuid ~= guid then
        guidRegistry[nameplate.lastGuid] = nil
      end
      guidRegistry[guid] = frame
      nameplate.lastGuid = guid
    end

    nameplates:OnDataChanged(nameplate)
  end

  nameplates.OnUpdate = function(frame, state)
    local nameplate = frame.nameplate
    local original = nameplate.original
    local now = state.now
    local guid = nameplate.lastGuid

    -- Target detection via GUID comparison (stable, no flicker)
    local target = state.hasTarget and guid and guid == state.targetGuid
    local mouseover = state.hasMouseover and original.glow:IsShown() or nil

    -- Alpha - only set when changed (uses stable GUID-based target detection)
    nameplate.istarget = target
    local wantAlpha = (target or not state.hasTarget) and 1 or cfg_notargalpha
    if nameplate.lastAlpha ~= wantAlpha then
      nameplate.lastAlpha = wantAlpha
      nameplate:SetAlpha(wantAlpha)
    end

    -- Castbar - only update when actively casting for smooth animation
    local castbar = nameplate.castbar
    local showCast = cfg_showcastbar and (not cfg_targetcastbar or target)
    local castInfo = showCast and guid and castEvents[guid]

    if castInfo and castInfo.spellID and castInfo.endTime and now < castInfo.endTime and castInfo.event ~= "CAST" and castInfo.event ~= "FAIL" then
      -- Only set min/max when cast changes (use 0-based range for smooth StatusBar rendering)
      if castbar.lastCastStart ~= castInfo.startTime then
        castbar.lastCastStart = castInfo.startTime
        castbar:SetMinMaxValues(0, castInfo.endTime - castInfo.startTime)
      end

      -- Value must update for smooth animation (0-based for precision)
      if castInfo.event == "CHANNEL" then
        castbar:SetValue(castInfo.endTime - now)
      else
        castbar:SetValue(now - castInfo.startTime)
      end

      -- Text/icon only when changed
      local timeLeft = floor((castInfo.endTime - now) * 10)
      if castbar.lastTime ~= timeLeft then
        castbar.lastTime = timeLeft
        castbar.text:SetText(string.format("%.1f", timeLeft / 10))
      end

      if castbar.lastSpell ~= castInfo.spellID then
        castbar.lastSpell = castInfo.spellID
        castbar.spell:SetText(cfg_spellname and castInfo.spellName or "")
        if castInfo.icon then
          castbar.icon.tex:SetTexture(castInfo.icon)
          castbar.icon.tex:SetTexCoord(.1,.9,.1,.9)
        end
      end

      -- Show only when needed
      if not castbar.isShown then
        castbar.isShown = true
        castbar:Show()
      end
    else
      -- Hide cast info and bar
      if castInfo and castInfo.spellID then wipe(castInfo) end
      if castbar.isShown then
        castbar.isShown = nil
        castbar.lastCastStart = nil
        castbar.lastSpell = nil
        castbar:Hide()
      end
    end

    -- Throttle non-critical updates (100ms interval)
    if nameplate.lastUpdate and (now - nameplate.lastUpdate) < THROTTLE_INTERVAL then
      return
    end
    nameplate.lastUpdate = now

    -- Check for event-driven update flags
    local update
    if nameplate.auraUpdate or nameplate.targetUpdate or nameplate.castUpdate or nameplate.comboUpdate then
      update = true
      nameplate.auraUpdate = nil
      nameplate.targetUpdate = nil
      nameplate.castUpdate = nil
      nameplate.comboUpdate = nil
    end

    -- reset strata cache on target change
    if nameplate.istarget ~= target then
      nameplate.target_strata = nil
    end

    -- keep target nameplate above others
    if target and nameplate.target_strata ~= 1 then
      nameplate:SetFrameStrata("LOW")
      nameplate.target_strata = 1
    elseif not target and nameplate.target_strata ~= 0 then
      nameplate:SetFrameStrata("BACKGROUND")
      nameplate.target_strata = 0
    end

    -- queue update on visual target update
    if nameplate.cache.target ~= target then
      nameplate.cache.target = target
      update = true
    end

    -- queue update on visual mouseover update
    if nameplate.cache.mouseover ~= mouseover then
      nameplate.cache.mouseover = mouseover
      update = true
    end

    -- trigger update when name color changed
    local r, g, b = original.name:GetTextColor()
    if r + g + b ~= nameplate.cache.namecolor then
      nameplate.cache.namecolor = r + g + b

      if cfg_namefightcolor then
        if r > .9 and g < .2 and b < .2 then
          nameplate.name:SetTextColor(1,0.4,0.2,1) -- infight
        else
          nameplate.name:SetTextColor(r,g,b,1)
        end
      else
        nameplate.name:SetTextColor(1,1,1,1)
      end
      update = true
    end

    -- trigger update when level color changed
    local r, g, b = original.level:GetTextColor()
    r, g, b = r + .3, g + .3, b + .3
    if r + g + b ~= nameplate.cache.levelcolor then
      nameplate.cache.levelcolor = r + g + b
      nameplate.level:SetTextColor(r,g,b,1)
      update = true
    end

    -- Note: Debuff timeout scanning removed - now event-driven via UNIT_AURA

    -- use timer based updates
    if not nameplate.tick or nameplate.tick < now then
      update = true
    end

    -- run full updates if required
    if update then
      nameplates:OnDataChanged(nameplate)
      nameplate.tick = now + .5
    end

    -- target zoom (uses cached config values)
    if target and cfg_targetzoom then
      local wc = cfg_width * cfg_zoomval
      local hc = cfg_heighthealth * (cfg_zoomval * .9)

      if cfg_zoominstant then
        -- instant zoom
        if not nameplate.health.zoomed then
          nameplate.health:SetWidth(wc)
          nameplate.health:SetHeight(hc)
          nameplate.health.zoomed = true
        end
      else
        -- animated zoom
        local w, h = nameplate.health:GetWidth(), nameplate.health:GetHeight()
        local animation = false

        if wc >= w then
          nameplate.health:SetWidth(w * 1.05)
          nameplate.health.zoomTransition = true
          animation = true
        end

        if hc >= h then
          nameplate.health:SetHeight(h * 1.05)
          nameplate.health.zoomTransition = true
          animation = true
        end

        if not animation and not nameplate.health.zoomed then
          nameplate.health:SetWidth(wc)
          nameplate.health:SetHeight(hc)
          nameplate.health.zoomTransition = nil
          nameplate.health.zoomed = true
        end
      end
    elseif nameplate.health.zoomed or nameplate.health.zoomTransition then
      if cfg_zoominstant then
        -- instant unzoom
        nameplate.health:SetWidth(cfg_width)
        nameplate.health:SetHeight(cfg_heighthealth)
        nameplate.health.zoomTransition = nil
        nameplate.health.zoomed = nil
      else
        -- animated unzoom
        local w, h = nameplate.health:GetWidth(), nameplate.health:GetHeight()
        local animation = false

        if cfg_width <= w then
          nameplate.health:SetWidth(w * .95)
          animation = true
        end

        if cfg_heighthealth <= h then
          nameplate.health:SetHeight(h * .95)
          animation = true
        end

        if not animation then
          nameplate.health:SetWidth(cfg_width)
          nameplate.health:SetHeight(cfg_heighthealth)
          nameplate.health.zoomTransition = nil
          nameplate.health.zoomed = nil
        end
      end
    end

  end

  -- set nameplate game settings
  nameplates.SetGameVariables = function()
    -- update visibility (hostile)
    if C.nameplates["showhostile"] == "1" then
      _G.NAMEPLATES_ON = true
      ShowNameplates()
    else
      _G.NAMEPLATES_ON = nil
      HideNameplates()
    end

    -- update visibility (hostile)
    if C.nameplates["showfriendly"] == "1" then
      _G.FRIENDNAMEPLATES_ON = true
      ShowFriendNameplates()
    else
      _G.FRIENDNAMEPLATES_ON = nil
      HideFriendNameplates()
    end
  end

  nameplates:SetGameVariables()

  nameplates.UpdateConfig = function()
    -- update cached config values
    CacheConfig()
    CacheBorderColor()

    -- update debuff filters
    DebuffFilterPopulate()

    -- update nameplate visibility
    nameplates:SetGameVariables()

    -- apply all config changes
    for plate in pairs(registry) do
      plate.nameplate.lastAlpha = nil  -- force alpha recalculation
      nameplates.OnConfigChange(plate)
    end
  end

  if IchaPlates.client <= 11200 then
    -- handle vanilla only settings
    -- due to the secured lua api, those settings can't be applied to TBC and later.
    local hookOnConfigChange = nameplates.OnConfigChange
    nameplates.OnConfigChange = function(self)
      hookOnConfigChange(self)

      local parent = self
      local nameplate = self.nameplate
      local plate = (C.nameplates["overlap"] == "1" or C.nameplates["vertical_offset"] ~= "0") and nameplate or parent

      -- disable all clicks for now
      parent:EnableMouse(false)
      nameplate:EnableMouse(false)

      -- adjust vertical offset
      if C.nameplates["vertical_offset"] ~= "0" then
        nameplate:SetPoint("TOP", parent, "TOP", 0, tonumber(C.nameplates["vertical_offset"]))
      end

      -- replace clickhandler
      if C.nameplates["overlap"] == "1" or C.nameplates["vertical_offset"] ~= "0" then
        plate:SetScript("OnClick", function() parent:Click() end)
      end

      -- enable mouselook on rightbutton down
      if C.nameplates["rightclick"] == "1" then
        plate:SetScript("OnMouseDown", nameplates.mouselook.OnMouseDown)
      else
        plate:SetScript("OnMouseDown", nil)
      end
    end

    local hookOnDataChanged = nameplates.OnDataChanged
    nameplates.OnDataChanged = function(self, nameplate)
      hookOnDataChanged(self, nameplate)

      -- make sure to keep mouse events disabled on parent nameplate
      if (C.nameplates["overlap"] == "1" or C.nameplates["vertical_offset"] ~= "0") then
        nameplate.parent:EnableMouse(false)
      end
    end

    local hookOnUpdate = nameplates.OnUpdate
    nameplates.OnUpdate = function(frame, state)
      -- initialize shortcut variables
      local plate = (C.nameplates["overlap"] == "1" or C.nameplates["vertical_offset"] ~= "0") and frame.nameplate or frame
      local clickable = C.nameplates["clickthrough"] ~= "1" and true or false

      -- disable all click events
      if not clickable then
        frame:EnableMouse(false)
        frame.nameplate:EnableMouse(false)
      else
        plate:EnableMouse(clickable)
      end

      if C.nameplates["overlap"] == "1" then
        if frame:GetWidth() > 1 then
          -- set parent to 1 pixel to have them overlap each other
          frame:SetWidth(1)
          frame:SetHeight(1)
        end
      else
        local scale = tonumber(C.nameplates.scale) or 1
        local effectiveScale = UIParent:GetScale() * scale
        local targetWidth = floor(frame.nameplate:GetWidth() * effectiveScale)

        if not frame.nameplate.dwidth then
          -- cache initial sizing value for comparison
          frame.nameplate.dwidth = targetWidth
        end

        if floor(frame:GetWidth()) ~= targetWidth then
          -- align parent plate to the actual size (respecting custom scale)
          frame:SetWidth(frame.nameplate:GetWidth() * effectiveScale)
          frame:SetHeight(frame.nameplate:GetHeight() * effectiveScale)
          frame.nameplate.dwidth = targetWidth
        end
      end

      -- disable click events while spell is targeting
      local mouseEnabled = frame.nameplate:IsMouseEnabled()
      if C.nameplates["clickthrough"] == "0" and C.nameplates["overlap"] == "1" and SpellIsTargeting() == mouseEnabled then
        frame.nameplate:EnableMouse(not mouseEnabled)
      end

      hookOnUpdate(frame, state)
    end

    -- enable mouselook on rightbutton down
    nameplates.mouselook = CreateFrame("Frame", nil, UIParent)
    nameplates.mouselook.time = nil
    nameplates.mouselook.frame = nil
    nameplates.mouselook.OnMouseDown = function()
      if arg1 and arg1 == "RightButton" then
        MouselookStart()

        -- start detection of the rightclick emulation
        nameplates.mouselook.time = GetTime()
        nameplates.mouselook.frame = this
        nameplates.mouselook:Show()
      end
    end

    nameplates.mouselook:SetScript("OnUpdate", function()
      -- break here if nothing to do
      if not this.time or not this.frame then
        this:Hide()
        return
      end

      -- if threshold is reached (0.5 second) no click action will follow
      if not IsMouselooking() and this.time + tonumber(C.nameplates["clickthreshold"]) < GetTime() then
        this:Hide()
        return
      end

      -- run a usual nameplate rightclick action
      if not IsMouselooking() then
        this.frame:Click("LeftButton")
        if UnitCanAttack("player", "target") and not nameplates.combat.inCombat then AttackTarget() end
        this:Hide()
        return
      end
    end)
  end

  IchaPlates.nameplates = nameplates
end)
