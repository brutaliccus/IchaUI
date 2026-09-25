-- IchaPlates: api/api.lua (ported from ShaguPlatesX api/api.lua).
-- ShaguPlatesX: Copyright (c) 2016-2021 Eric Mauser (Shagu), adapted by Ehawne.
-- MIT License, see LICENSE-ShaguPlates.txt. Derived from pfUI by Shagu.

IchaPlates.api = { }

-- load IchaPlates environment
setfenv(1, IchaPlates:GetEnvironment())

-- Client API shortcuts
gfind = string.gmatch or string.gfind
mod = math.mod or mod

-- [ strsplit ]
-- Splits a string using a delimiter.
-- 'delimiter'  [string]        characters that will be interpreted as delimiter
--                              characters (bytes) in the string.
-- 'subject'    [string]        String to split.
-- return:      [list]          a list of strings.
function IchaPlates.api.strsplit(delimiter, subject)
  if not subject then return nil end
  local delimiter, fields = delimiter or ":", {}
  local pattern = string.format("([^%s]+)", delimiter)
  string.gsub(subject, pattern, function(c) fields[table.getn(fields)+1] = c end)
  return unpack(fields)
end

-- [ isempty ]
-- Returns true if a table is empty or not existing, otherwise false.
-- 'tbl'         [table]        the table that shall be checked
-- return:      [boolean]       result of the check.
function IchaPlates.api.isempty(tbl)
  if not tbl then return true end
  for k, v in pairs(tbl) do
    return false
  end
  return true
end

-- [ checkversion ]
-- Compares a given version (major,minor,fix) and compares it to the current
-- 'chkmajor'   [number]        the major number to check
-- 'chkminor'   [number]        the minor number to check
-- 'chkfix'     [number]        the fix number to check
--
-- return:      [boolean]       true when the current version is smaller or equal
--                              to the given value, otherwise returns nil.
local major, minor, fix = nil, nil, nil
function IchaPlates.api.checkversion(chkmajor, chkminor, chkfix)
  if not major and not minor and not fix then
    -- load and convert current version
    major, minor, fix = IchaPlates.api.strsplit(".", tostring(IchaPlates_config.version))
    major, minor, fix = tonumber(major) or 0, tonumber(minor) or 0, tonumber(fix) or 0
  end

  local chkversion = chkmajor + chkminor/100 + chkfix/10000
  local curversion = major + minor/100 + fix/10000
  return curversion <= chkversion and true or nil
end

-- [ RunOOC ]
-- Runs a function once, as soon as the combat lockdown fades.
-- func         [function]      The function that shall run ooc.
-- return:      [bool]          true if the function was added,
--                              nil if the function already exists in queue
local queue, frame = {}
function IchaPlates.api.RunOOC(func)
  if not frame then
    frame = CreateFrame("Frame")
    frame:SetScript("OnUpdate", function()
      if InCombatLockdown and InCombatLockdown() then return end
      for key, func in pairs(queue) do func(); queue[key] = nil end
    end)
  end

  if not queue[tostring(func)] then
    queue[tostring(func)] = func
    return true
  end
end

-- [ round ]
-- Rounds a float number into specified places after comma.
-- 'input'      [float]         the number that should be rounded.
-- 'places'     [int]           amount of places after the comma.
-- returns:     [float]         rounded number.
function IchaPlates.api.round(input, places)
  if not places then places = 0 end
  if type(input) == "number" and type(places) == "number" then
    local pow = 1
    for i = 1, places do pow = pow * 10 end
    return floor(input * pow + 0.5) / pow
  end
end

-- [ clamp ]
-- Clamps a number between given range.
-- 'x'          [number]        the number that should be clamped.
-- 'min'        [number]        minimum value.
-- 'max'        [number]        maximum value.
-- returns:     [number]        clamped value: 'x', 'min' or 'max' value itself.
function IchaPlates.api.clamp(x, min, max)
  if type(x) == "number" and type(min) == "number" and type(max) == "number" then
    return x < min and min or x > max and max or x
  else
    return x
  end
end

-- [ modf ]
-- Returns integral and fractional part of a number.
-- 'f'          [float]        the number to breakdown.
-- returns:     [int],[float]  whole and fractional part.
function IchaPlates.api.modf(f)
  if modf then return modf(f) end
  if f > 0 then
    return math.floor(f), mod(f,1)
  end
  return math.ceil(f), mod(f,1)
end

-- [ Abbreviate ]
-- Abbreviates a number from 1234 to 1.23k
-- 'number'     [number]           the number that should be abbreviated
-- 'returns:    [string]           the abbreviated value
function IchaPlates.api.Abbreviate(number)
  if IchaPlates_config.unitframes.abbrevnum == "1" then
    local sign = number < 0 and -1 or 1
    number = math.abs(number)

    if number > 1000000 then
      return IchaPlates.api.round(number/1000000*sign,2) .. "m"
    elseif number > 1000 then
      return IchaPlates.api.round(number/1000*sign,2) .. "k"
    end
  end

  return number
end

-- [ HookScript ]
-- Securely post-hooks a script handler.
-- 'f'          [frame]             the frame which needs a hook
-- 'script'     [string]            the handler to hook
-- 'func'       [function]          the function that should be added
function HookScript(f, script, func)
  local prev = f:GetScript(script)
  f:SetScript(script, function(a1,a2,a3,a4,a5,a6,a7,a8,a9)
    if prev then prev(a1,a2,a3,a4,a5,a6,a7,a8,a9) end
    func(a1,a2,a3,a4,a5,a6,a7,a8,a9)
  end)
end

-- [ HookAddonOrVariable ]
-- Sets a function to be called automatically once an addon gets loaded
-- 'addon'      [string]            addon or variable name
-- 'func'       [function]          function that should run
function IchaPlates.api.HookAddonOrVariable(addon, func)
  local lurker = CreateFrame("Frame", nil)
  lurker.func = func
  lurker:RegisterEvent("ADDON_LOADED")
  lurker:RegisterEvent("VARIABLES_LOADED")
  lurker:RegisterEvent("PLAYER_ENTERING_WORLD")
  lurker:SetScript("OnEvent",function()
    -- only run when config is available
    if event == "ADDON_LOADED" and not this.foundConfig then
      return
    elseif event == "VARIABLES_LOADED" then
      this.foundConfig = true
    end

    if IsAddOnLoaded(addon) or _G[addon] then
      this:func()
      this:UnregisterAllEvents()
    end
  end)
end

-- [ QueueFunction ]
-- Add functions to a FIFO queue for execution after a short delay.
-- '...'        [vararg]        function, [arguments]
local timer
function IchaPlates.api.QueueFunction(a1,a2,a3,a4,a5,a6,a7,a8,a9)
  if not timer then
    timer = CreateFrame("Frame")
    timer.queue = {}
    timer.interval = TOOLTIP_UPDATE_TIME
    timer.DeQueue = function()
      local item = table.remove(timer.queue,1)
      if item then
        item[1](item[2],item[3],item[4],item[5],item[6],item[7],item[8],item[9])
      end
      if table.getn(timer.queue) == 0 then
        timer:Hide() -- no need to run the OnUpdate when the queue is empty
      end
    end
    timer:SetScript("OnUpdate",function()
      this.sinceLast = (this.sinceLast or 0) + arg1
      while (this.sinceLast > this.interval) do
        this.DeQueue()
        this.sinceLast = this.sinceLast - this.interval
      end
    end)
  end
  table.insert(timer.queue,{a1,a2,a3,a4,a5,a6,a7,a8,a9})
  timer:Show() -- start the OnUpdate
end

-- [ Copy Table ]
-- By default a table assignment only will be a reference instead of a copy.
-- This is used to create a replicate of the actual table.
-- 'src'        [table]        the table that should be copied.
-- return:      [table]        the replicated table.
function IchaPlates.api.CopyTable(src)
  local lookup_table = {}
  local function _copy(src)
    if type(src) ~= "table" then
      return src
    elseif lookup_table[src] then
      return lookup_table[src]
    end
    local new_table = {}
    lookup_table[src] = new_table
    for index, value in pairs(src) do
      new_table[_copy(index)] = _copy(value)
    end
    return setmetatable(new_table, getmetatable(src))
  end
  return _copy(src)
end

-- [ Wipe Table ]
-- Empties a table and returns it
-- 'src'      [table]         the table that should be emptied.
-- return:    [table]         the emptied table.
function IchaPlates.api.wipe(src)
  -- notes: table.insert, table.remove will have undefined behavior
  -- when used on tables emptied this way because Lua removes nil
  -- entries from tables after an indeterminate time.
  -- Instead of table.insert(t,v) use t[table.getn(t)+1]=v as table.getn collapses nil entries.
  -- There are no issues with hash tables, t[k]=v where k is not a number behaves as expected.
  local mt = getmetatable(src) or {}
  if mt.__mode == nil or mt.__mode ~= "kv" then
    mt.__mode = "kv"
    src=setmetatable(src,mt)
  end
  for k in pairs(src) do
    src[k] = nil
  end
  return src
end

-- [ GetStringColor ]
-- Queries the IchaPlates setting strings and extract its color codes
-- returns r,g,b,a
local color_cache = {}
function IchaPlates.api.GetStringColor(colorstr)
  if not color_cache[colorstr] then
    local r, g, b, a = IchaPlates.api.strsplit(",", colorstr)
    color_cache[colorstr] = { r, g, b, a }
  end
  return unpack(color_cache[colorstr])
end

-- [ rgbhex ]
-- Returns color format from color info
-- 'r'          [table | number]  color table or r color component
-- 'g'          [number]          optional g color component
-- 'b'          [number]          optional b color component
-- 'a'          [number]          optional alpha component
-- returns color string in the form of '|caarrggbb'
local _r, _g, _b, _a
function IchaPlates.api.rgbhex(r, g, b, a)
  if type(r) == "table" then
    if r.r then
      _r, _g, _b, _a = r.r, r.g, r.b, (r.a or 1)
    elseif table.getn(r) >= 3 then
      _r, _g, _b, _a = r[1], r[2], r[3], (r[4] or 1)
    end
  elseif tonumber(r) then
    _r, _g, _b, _a = r, g, b, (a or 1)
  end

  if _r and _g and _b and _a then
    -- limit values to 0-1
    _r = _r + 0 > 1 and 1 or _r + 0
    _g = _g + 0 > 1 and 1 or _g + 0
    _b = _b + 0 > 1 and 1 or _b + 0
    _a = _a + 0 > 1 and 1 or _a + 0
    return string.format("|c%02x%02x%02x%02x", _a*255, _r*255, _g*255, _b*255)
  end

  return ""
end

-- [ GetBorderSize ]
-- Returns the configure value of a border and its pixel scaled version.
-- 'pref' allows to specifiy a custom border (i.e unitframes, panel)
function IchaPlates.api.GetBorderSize(pref)
  if not IchaPlates.borders then IchaPlates.borders = {} end

  -- set to default border if accessing a wrong border type
  if not pref or not IchaPlates_config.appearance.border[pref] or IchaPlates_config.appearance.border[pref] == "-1" then
    pref = "default"
  end

  if IchaPlates.borders[pref] then
    -- return already cached values
    return IchaPlates.borders[pref][1], IchaPlates.borders[pref][2]
  else
    -- add new borders to the IchaPlates tree
    local raw = tonumber(IchaPlates_config.appearance.border[pref])
    if raw == -1 then raw = 3 end

    local scaled = raw * GetPerfectPixel()
    IchaPlates.borders[pref] = { raw, scaled }

    return raw, scaled
  end
end

-- [ GetPerfectPixel ]
-- Returns a number that equals a real pixel on regular scaled frames.
-- Respects the current UI-scale and calculates a real pixel based on
-- the screen resolution and the 768px sized drawlayer.
function IchaPlates.api.GetPerfectPixel()
  if IchaPlates.pixel then return IchaPlates.pixel end

  if IchaPlates_config.appearance.border.pixelperfect == "1" then
    local scale = GetCVar("uiScale")
    local resolution = GetCVar("gxResolution")
    local _, _, screenwidth, screenheight = strfind(resolution, "(.+)x(.+)")

    IchaPlates.pixel = 768 / screenheight / scale
    IchaPlates.pixel = IchaPlates.pixel > 1 and 1 or IchaPlates.pixel

    -- autodetect and zoom for HiDPI displays
    if IchaPlates_config.appearance.border.hidpi == "1" then
      IchaPlates.pixel = IchaPlates.pixel < .5 and IchaPlates.pixel * 2 or IchaPlates.pixel
    end
  else
    IchaPlates.pixel = .7
  end

  IchaPlates.backdrop = {
    bgFile = "Interface\\BUTTONS\\WHITE8X8", tile = false, tileSize = 0,
    edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = IchaPlates.pixel,
    insets = {left = -IchaPlates.pixel, right = -IchaPlates.pixel, top = -IchaPlates.pixel, bottom = -IchaPlates.pixel},
  }

  IchaPlates.backdrop_thin = {
    bgFile = "Interface\\BUTTONS\\WHITE8X8", tile = false, tileSize = 0,
    edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = IchaPlates.pixel,
    insets = {left = 0, right = 0, top = 0, bottom = 0},
  }

  return IchaPlates.pixel
end

-- [ Create Backdrop ]
-- Creates a IchaPlates compatible frame as backdrop element
-- 'f'          [frame]         the frame which should get a backdrop.
-- 'inset'      [int]           backdrop inset, defaults to border size.
-- 'legacy'     [bool]          use legacy backdrop instead of creating frames.
-- 'transp'     [number]        set default transparency
local backdrop, b, level, rawborder, border, br, bg, bb, ba, er, eg, eb, ea
function IchaPlates.api.CreateBackdrop(f, inset, legacy, transp, backdropSetting)
  -- exit if now frame was given
  if not f then return end

  -- load raw and pixel perfect scaled border
  rawborder, border = GetBorderSize()

  -- load custom border if existing
  if inset then
    rawborder = inset / GetPerfectPixel()
    border = inset
  end

  -- detect if blizzard backdrops shall be used
  local blizz = C.appearance.border.force_blizz == "1" and true or nil
  backdrop = blizz and IchaPlates.backdrop_blizz_full or rawborder == 1 and IchaPlates.backdrop_thin or IchaPlates.backdrop
  border = blizz and math.max(border, 3) or border

  -- get the color settings
  br, bg, bb, ba = IchaPlates.api.GetStringColor(IchaPlates_config.appearance.border.background)
  er, eg, eb, ea = IchaPlates.api.GetStringColor(IchaPlates_config.appearance.border.color)

  if transp and transp < tonumber(ba) then ba = transp end

  -- use legacy backdrop handling
  if legacy then
    if backdropSetting then f:SetBackdrop(backdropSetting) end
    f:SetBackdrop(backdrop)
    f:SetBackdropColor(br, bg, bb, ba)
    f:SetBackdropBorderColor(er, eg, eb , ea)
  else
    -- increase clickable area if available
    if f.SetHitRectInsets and ( not InCombatLockdown or not InCombatLockdown()) then
      f:SetHitRectInsets(-border,-border,-border,-border)
    end

    -- use new backdrop behaviour
    if not f.backdrop then
      if f:GetBackdrop() then f:SetBackdrop(nil) end

      local b = CreateFrame("Frame", nil, f)
      level = f:GetFrameLevel()
      if level < 1 then
        b:SetFrameLevel(level)
      else
        b:SetFrameLevel(level - 1)
      end

      f.backdrop = b
    end

    f.backdrop:SetPoint("TOPLEFT", f, "TOPLEFT", -border, border)
    f.backdrop:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", border, -border)
    f.backdrop:SetBackdrop(backdrop)
    f.backdrop:SetBackdropColor(br, bg, bb, ba)
    f.backdrop:SetBackdropBorderColor(er, eg, eb , ea)

    if blizz then
      if not f.backdrop_border then
        local border = CreateFrame("Frame", nil, f)
        border:SetFrameLevel(level + 1)
        f.backdrop_border = border

        local hookSetBackdropBorderColor = f.backdrop.SetBackdropBorderColor
        f.backdrop.SetBackdropBorderColor = function(self, r, g, b, a)
          f.backdrop_border:SetBackdropBorderColor(r, g, b, a)
          hookSetBackdropBorderColor(f.backdrop, r, g, b, a)
        end
      end

      f.backdrop_border:SetAllPoints(f.backdrop)
      f.backdrop_border:SetBackdrop(IchaPlates.backdrop_blizz_border)
      f.backdrop_border:SetBackdropBorderColor(er, eg, eb , ea)
    end
  end
end

-- [ Create Shadow ]
-- Creates a IchaPlates compatible frame as shadow element
-- 'f'          [frame]         the frame which should get a backdrop.
function IchaPlates.api.CreateBackdropShadow(f)
  -- exit if now frame was given
  if not f then return end

  if f.backdrop_shadow or IchaPlates_config.appearance.border.shadow ~= "1" then
    return
  end

  local anchor = f.backdrop or f
  f.backdrop_shadow = CreateFrame("Frame", nil, anchor)
  f.backdrop_shadow:SetFrameStrata("BACKGROUND")
  f.backdrop_shadow:SetFrameLevel(1)
  f.backdrop_shadow:SetPoint("TOPLEFT", anchor, "TOPLEFT", -7, 7)
  f.backdrop_shadow:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 7, -7)
  f.backdrop_shadow:SetBackdrop(IchaPlates.backdrop_shadow)
  f.backdrop_shadow:SetBackdropBorderColor(0,0,0,tonumber(IchaPlates_config.appearance.border.shadow_intensity))
end

-- [ GetColoredTime ] --
-- 'remaining'   the time in seconds that should be converted
-- return        a colored string including a time unit (m/h/d)
local color_day, color_hour, color_minute, color_low, color_normal
function IchaPlates.api.ResetTimeColors()
  color_day, color_hour, color_minute, color_low, color_normal = nil, nil, nil, nil, nil
end

function IchaPlates.api.GetColoredTimeString(remaining)
  if not remaining then return "" end

  -- Show days if remaining is > 99 Hours (99 * 60 * 60)
  if remaining > 356400 then
    if not color_day then
      local r,g,b,a = IchaPlates.api.GetStringColor(C.appearance.cd.daycolor)
      color_day = IchaPlates.api.rgbhex(r,g,b)
    end

    return color_day .. round(remaining / 86400) .. "|rd"

  -- Show hours if remaining is > 99 Minutes (99 * 60)
  elseif remaining > 5940 then
    if not color_hour then
      local r,g,b,a = IchaPlates.api.GetStringColor(C.appearance.cd.hourcolor)
      color_hour = IchaPlates.api.rgbhex(r,g,b)
    end

    return color_hour .. round(remaining / 3600) .. "|rh"

  -- Show minutes if remaining is > 99 Seconds (99)
  elseif remaining > 99 then
    if not color_minute then
      local r,g,b,a = IchaPlates.api.GetStringColor(C.appearance.cd.minutecolor)
      color_minute = IchaPlates.api.rgbhex(r,g,b)
    end

    return color_minute .. round(remaining / 60) .. "|rm"

  -- Show milliseconds on low
  elseif remaining <= 5 and IchaPlates_config.appearance.cd.milliseconds == "1" then
    if not color_low then
      local r,g,b,a = IchaPlates.api.GetStringColor(C.appearance.cd.lowcolor)
      color_low = IchaPlates.api.rgbhex(r,g,b)
    end

    return color_low .. string.format("%.1f", round(remaining,1))

  -- Show seconds on low
  elseif remaining <= 5 then
    if not color_low then
      local r,g,b,a = IchaPlates.api.GetStringColor(C.appearance.cd.lowcolor)
      color_low = IchaPlates.api.rgbhex(r,g,b)
    end

    return color_low .. round(remaining)

  -- Show seconds on normal
  elseif remaining >= 0 then
    if not color_normal then
      local r, g, b, a = IchaPlates.api.GetStringColor(C.appearance.cd.normalcolor)
      color_normal = IchaPlates.api.rgbhex(r,g,b)
    end
    return color_normal .. round(remaining)

  -- Return empty
  else
    return ""
  end
end

-- [ GetColorGradient ] --
-- 'perc'     percentage (0-1)
-- return r,g,b and hexcolor
local gradientcolors = {}
function IchaPlates.api.GetColorGradient(perc)
  perc = perc > 1 and 1 or perc
  perc = perc < 0 and 0 or perc
  perc = floor(perc*100)/100

  local index = perc
  if not gradientcolors[index] then
    local r1, g1, b1, r2, g2, b2

    if perc <= 0.5 then
      perc = perc * 2
      r1, g1, b1 = 1, 0, 0
      r2, g2, b2 = 1, 1, 0
    else
      perc = perc * 2 - 1
      r1, g1, b1 = 1, 1, 0
      r2, g2, b2 = 0, 1, 0
    end

    local r = round(r1 + (r2 - r1) * perc, 4)
    local g = round(g1 + (g2 - g1) * perc, 4)
    local b = round(b1 + (b2 - b1) * perc, 4)
    local h = IchaPlates.api.rgbhex(r,g,b)

    gradientcolors[index] = {}
    gradientcolors[index].r = r
    gradientcolors[index].g = g
    gradientcolors[index].b = b
    gradientcolors[index].h = h
  end

  return gradientcolors[index].r,
    gradientcolors[index].g,
    gradientcolors[index].b,
    gradientcolors[index].h
end
