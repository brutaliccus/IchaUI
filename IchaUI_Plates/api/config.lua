-- IchaPlates: api/config.lua (ported from ShaguPlatesX api/config.lua).
-- ShaguPlatesX: Copyright (c) 2016-2021 Eric Mauser (Shagu), adapted by Ehawne.
-- MIT License, see LICENSE-ShaguPlates.txt. Derived from pfUI by Shagu.
-- Only the groups the nameplate modules read are kept (pfUI bars, chat, panels etc. are gone).
-- The config table is IchaUIDB.plates; existing values are never overwritten.

-- load IchaPlates environment
setfenv(1, IchaPlates:GetEnvironment())

function IchaPlates:UpdateConfig(group, subgroup, entry, value)
  -- create empty config if not existing
  if not IchaPlates_config then
    IchaPlates:BindConfig()
  end

  -- check for missing config groups
  if not IchaPlates_config[group] then
    IchaPlates_config[group] = {}
  end

  -- update config
  if not subgroup and entry and value and not IchaPlates_config[group][entry] then
    IchaPlates_config[group][entry] = value
  end

  -- check for missing config subgroups
  if subgroup and not IchaPlates_config[group][subgroup] then
    IchaPlates_config[group][subgroup] = {}
  end

  -- update config in subgroup
  if subgroup and entry and value and not IchaPlates_config[group][subgroup][entry] then
    IchaPlates_config[group][subgroup][entry] = value
  end
end

function IchaPlates:LoadConfig()
  local path = IchaPlates.path
  --                MODULE        SUBGROUP       ENTRY               VALUE
  IchaPlates:UpdateConfig("icha",       nil,           "enabled",          "1")
  IchaPlates:UpdateConfig("icha",       nil,           "theme",            "0")

  IchaPlates:UpdateConfig("global",     nil,           "language",         GetLocale())
  IchaPlates:UpdateConfig("global",     nil,           "pixelperfect",     "0")

  IchaPlates:UpdateConfig("global",     nil,           "font_blizzard",    "0")
  IchaPlates:UpdateConfig("global",     nil,           "font_default", "Fonts\\FRIZQT__.TTF")
  IchaPlates:UpdateConfig("global",     nil,           "font_size",        "12")
  IchaPlates:UpdateConfig("global",     nil,           "font_unit", "Fonts\\FRIZQT__.TTF")
  IchaPlates:UpdateConfig("global",     nil,           "font_unit_size",   "12")
  IchaPlates:UpdateConfig("global",     nil,           "font_unit_style",  "OUTLINE")
  IchaPlates:UpdateConfig("global",     nil,           "font_unit_name",   path.."\\media\\fonts\\Myriad-Pro.ttf")
  IchaPlates:UpdateConfig("global",     nil,           "font_combat",      path.."\\media\\fonts\\Continuum.ttf")

  IchaPlates:UpdateConfig("global",     nil,           "force_region",     "1")
  IchaPlates:UpdateConfig("global",     nil,           "errors",           "1")
  IchaPlates:UpdateConfig("global",     nil,           "override_shagutweaks_nameplates", "1")
  IchaPlates:UpdateConfig("global",     nil,           "override_shagutweaks_targetlibs", "1")
  IchaPlates:UpdateConfig("global",     nil,           "override_superapi_castlib", "1")

  IchaPlates:UpdateConfig("unitframes", nil,           "abbrevnum",        "1")
  IchaPlates:UpdateConfig("unitframes", nil,           "abbrevname",       "1")

  IchaPlates:UpdateConfig("appearance", "border",      "background",       "0,0,0,1")
  IchaPlates:UpdateConfig("appearance", "border",      "color",            "0.2,0.2,0.2,1")
  IchaPlates:UpdateConfig("appearance", "border",      "shadow",           "0")
  IchaPlates:UpdateConfig("appearance", "border",      "shadow_intensity", ".35")
  IchaPlates:UpdateConfig("appearance", "border",      "pixelperfect",     "1")
  IchaPlates:UpdateConfig("appearance", "border",      "force_blizz", "1")
  IchaPlates:UpdateConfig("appearance", "border",      "hidpi",            "1")
  IchaPlates:UpdateConfig("appearance", "border",      "default",          "3")
  IchaPlates:UpdateConfig("appearance", "border",      "nameplates",       "2")
  IchaPlates:UpdateConfig("appearance", "cd",          "lowcolor",         "1,.2,.2,1")
  IchaPlates:UpdateConfig("appearance", "cd",          "normalcolor",      "1,1,1,1")
  IchaPlates:UpdateConfig("appearance", "cd",          "minutecolor",      ".2,1,1,1")
  IchaPlates:UpdateConfig("appearance", "cd",          "hourcolor",        ".2,.5,1,1")
  IchaPlates:UpdateConfig("appearance", "cd",          "daycolor",         ".2,.2,1,1")
  IchaPlates:UpdateConfig("appearance", "cd",          "threshold",        "2")
  IchaPlates:UpdateConfig("appearance", "cd",          "font_size",        "12")
  IchaPlates:UpdateConfig("appearance", "cd",          "font_size_blizz",  "12")
  IchaPlates:UpdateConfig("appearance", "cd",          "font_size_foreign","12")
  IchaPlates:UpdateConfig("appearance", "cd",          "debuffs",          "1")
  IchaPlates:UpdateConfig("appearance", "cd",          "blizzard",         "0")
  IchaPlates:UpdateConfig("appearance", "cd",          "foreign",          "0")
  IchaPlates:UpdateConfig("appearance", "cd",          "milliseconds",     "1")
  IchaPlates:UpdateConfig("appearance", "cd",          "hideanim",         "0")
  IchaPlates:UpdateConfig("appearance", "cd",          "font",             path.."\\media\\fonts\\BigNoodleTitling.ttf")
  IchaPlates:UpdateConfig("appearance", "cd",          "dynamicsize",      "1")

  IchaPlates:UpdateConfig("nameplates", nil,           "showhostile",      "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "showfriendly",     "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "use_unitfonts", "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "legacy",           "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "overlap",          "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "verticalhealth",   "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "vertical_offset",  "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "scale",            "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "nameoffset",       "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "showcastbar",      "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "targetcastbar",    "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "spellname",        "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "showdebuffs",      "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "selfdebuff",       "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "guessdebuffs",     "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "clickthrough",     "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "rightclick",       "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "clickthreshold",   "0.5")
  IchaPlates:UpdateConfig("nameplates", nil,           "enemyclassc",      "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "friendclassc",     "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "friendclassnamec", "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "raidiconsize",     "16")
  IchaPlates:UpdateConfig("nameplates", nil,           "raidiconpos",      "CENTER")
  IchaPlates:UpdateConfig("nameplates", nil,           "raidiconoffx",     "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "raidiconoffy",     "-5")
  IchaPlates:UpdateConfig("nameplates", nil,           "fullhealth",       "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "target",           "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "namefightcolor",   "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "enemynpc",         "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "enemyplayer",      "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "neutralnpc",       "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "friendlynpc",      "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "friendlyplayer",   "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "critters",         "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "totems",           "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "totemicons",       "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "showguildname",    "0")

  IchaPlates:UpdateConfig("nameplates", nil,           "outcombatstate",   "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "barcombatstate",   "1")

  IchaPlates:UpdateConfig("nameplates", nil,           "ccombatthreat",    "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "ccombatnothreat",  "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "ccombatstun",      "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "ccombatcasting",   "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "combatthreat",     ".6,1,0,1")
  IchaPlates:UpdateConfig("nameplates", nil,           "combatnothreat",   ".9,.2,.3,1")
  IchaPlates:UpdateConfig("nameplates", nil,           "combatstun",       ".8,.8,.8,1")
  IchaPlates:UpdateConfig("nameplates", nil,           "combatcasting",    ".7,.2,.7,1")

  IchaPlates:UpdateConfig("nameplates", nil,           "outfriendly",      "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "outfriendlynpc",   "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "outneutral",       "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "outenemy",         "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "targethighlight",  "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "highlightcolor",   "1,1,1,1")

  IchaPlates:UpdateConfig("nameplates", nil,           "showhp",           "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "hptextpos",        "RIGHT")
  IchaPlates:UpdateConfig("nameplates", nil,           "hptextformat",     "curmaxs")
  IchaPlates:UpdateConfig("nameplates", nil,           "width",            "120")
  IchaPlates:UpdateConfig("nameplates", nil,           "debuffsize",       "14")
  IchaPlates:UpdateConfig("nameplates", nil,           "debuffoffset",     "4")
  IchaPlates:UpdateConfig("nameplates", nil,           "heighthealth",     "8")
  IchaPlates:UpdateConfig("nameplates", nil,           "heightcast",       "8")
  IchaPlates:UpdateConfig("nameplates", nil,           "cpdisplay",        "0")
  IchaPlates:UpdateConfig("nameplates", nil,           "targetglow",       "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "glowcolor",        "1,1,1,1")
  IchaPlates:UpdateConfig("nameplates", nil,           "targetzoom",       "1")
  IchaPlates:UpdateConfig("nameplates", nil,           "targetzoomval",    ".30")
  IchaPlates:UpdateConfig("nameplates", nil,           "targetzoominstant","1")
  IchaPlates:UpdateConfig("nameplates", nil,           "notargalpha",      ".70")
  IchaPlates:UpdateConfig("nameplates", nil,           "healthtexture",    path.."\\media\\img\\bar")
  IchaPlates:UpdateConfig("nameplates", "name",        "fontstyle",        "OUTLINE")
  IchaPlates:UpdateConfig("nameplates", "health",      "offset",           "-4")
  IchaPlates:UpdateConfig("nameplates", "debuffs",     "filter",           "none")
  IchaPlates:UpdateConfig("nameplates", "debuffs",     "whitelist",        "")
  IchaPlates:UpdateConfig("nameplates", "debuffs",     "blacklist",        "")
  IchaPlates:UpdateConfig("nameplates", "debuffs",     "showstacks",       "0")
  IchaPlates:UpdateConfig("nameplates", "debuffs",     "position",         "BOTTOM")

  IchaPlates:UpdateConfig("disabled",   nil,           nil,                nil)
end

function IchaPlates:MigrateConfig()
  -- pfUI's 1.x-3.x migrations do not apply: imported configs come from ShaguPlatesX 5.x.
  IchaPlates_config.version = IchaPlates.version.string
end
