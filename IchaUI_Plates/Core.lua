-- IchaPlates core (ported from ShaguPlatesX ShaguPlates.lua). Lua 5.0 / WoW 1.12.
-- ShaguPlatesX: Copyright (c) 2016-2021 Eric Mauser (Shagu), adapted by Ehawne.
-- MIT License, see LICENSE-ShaguPlates.txt. Derived from pfUI by Shagu.
--
-- Settings live in IchaUIDB.plates (this addon has no SavedVariables). The first load
-- imports ShaguPlatesX_config when ShaguPlatesX is enabled. While ShaguPlatesX is loaded
-- IchaPlates stands by: both addons skin the same WorldFrame plates, so running both
-- would draw every plate twice.

IchaPlates = CreateFrame("Frame", "IchaPlatesBoot", UIParent)
IchaPlates:RegisterEvent("ADDON_LOADED")
IchaPlates:RegisterEvent("PLAYER_LOGIN")
IchaPlates:RegisterEvent("PLAYER_LEAVING_WORLD")
IchaPlates:RegisterEvent("PLAYER_LOGOUT")
IchaPlates:RegisterEvent("PLAYER_ENTERING_WORLD")

IchaPlates.bootup = true
IchaPlates.state = "loading"
IchaPlates.leaving = false

IchaPlates_config = {}
IchaPlates_locale = {}

IchaPlates.cache = {}
IchaPlates.module = {}
IchaPlates.modules = {}
IchaPlates.version = {}
IchaPlates.hooks = {}
IchaPlates.env = {}

IchaPlates.name = "IchaUI_Plates"
IchaPlates.path = "Interface\\AddOns\\IchaUI_Plates"

-- ShaguPlates / ShaguPlatesX config paths -> the copies in IchaUI_Plates\media.
function IchaPlates.MediaPath(value)
  if type(value) ~= "string" then return value end
  local _, _, rest = string.find(value, "^[Ii][Nn][Tt][Ee][Rr][Ff][Aa][Cc][Ee]\\[Aa][Dd][Dd][Oo][Nn][Ss]\\[Ss]hagu[Pp]lates[Xx]?\\(.+)$")
  if not rest then
    _, _, rest = string.find(value, "^Interface\\AddOns\\IchaUI_Plates\\(.+)$")
    if not rest or string.find(rest, "^media\\") then return value end
  end
  local _, _, kind, file = string.find(rest, "^(%a+)\\(.+)$")
  if kind == "img" or kind == "fonts" then
    return IchaPlates.path .. "\\media\\" .. kind .. "\\" .. file
  end
  return IchaPlates.path .. "\\" .. rest
end

-- handle/convert media dir paths
IchaPlates.media = setmetatable({}, { __index = function(tab, key)
  local value = tostring(key)
  if strfind(value, "img:") then
    value = string.gsub(value, "img:", IchaPlates.path .. "\\media\\img\\")
  elseif strfind(value, "font:") then
    value = string.gsub(value, "font:", IchaPlates.path .. "\\media\\fonts\\")
  else
    value = IchaPlates.MediaPath(value)
  end
  rawset(tab, key, value)
  return value
end})

-- cache client version
do
  local _, _, _, client = GetBuildInfo()
  client = client or 11200
  IchaPlates.expansion = "vanilla"
  IchaPlates.client = client
end

-- setup IchaPlates namespace
setmetatable(IchaPlates.env, {__index = getfenv(0)})

-- ShaguPlatesX enabled in the AddOns list: it loads after us (S > I), so decide early.
function IchaPlates.ShaguPlatesXEnabled()
  if not GetAddOnInfo then return false end
  local name, _, _, enabled, loadable = GetAddOnInfo("ShaguPlatesX")
  return (name and enabled and loadable) and true or false
end

function IchaPlates.ShaguPlatesXLoaded()
  if type(ShaguPlatesX) ~= "table" then return false end
  if IsAddOnLoaded and not IsAddOnLoaded("ShaguPlatesX") then return false end
  return true
end

function IchaPlates:BindConfig()
  if type(IchaUIDB) ~= "table" then IchaUIDB = {} end
  if type(IchaUIDB.plates) ~= "table" then IchaUIDB.plates = {} end
  IchaPlates_config = IchaUIDB.plates
  IchaPlates.env.C = IchaPlates_config
  return IchaPlates_config
end

local function fixMedia(t, depth)
  if type(t) ~= "table" or depth > 4 then return end
  local k, v
  for k, v in pairs(t) do
    if type(v) == "string" then
      t[k] = IchaPlates.MediaPath(v)
    elseif type(v) == "table" then
      fixMedia(v, depth + 1)
    end
  end
end

function IchaPlates:FixMedia()
  fixMedia(IchaPlates_config, 0)
end

local function copyTable(src, depth)
  if type(src) ~= "table" then return src end
  local dst = {}
  local k, v
  for k, v in pairs(src) do
    if type(v) == "table" then
      if depth < 6 then dst[k] = copyTable(v, depth + 1) end
    else
      dst[k] = v
    end
  end
  return dst
end

-- Copy the nameplate-relevant groups of ShaguPlatesX_config into IchaUIDB.plates.
-- ShaguPlatesX saved variables only exist while ShaguPlatesX is enabled.
function IchaPlates:ImportShaguPlatesX()
  local src = ShaguPlatesX_config
  if type(src) ~= "table" or type(src.nameplates) ~= "table" then return false end
  local C = self:BindConfig()
  if type(src.global) == "table" then C.global = copyTable(src.global, 0) end
  if type(src.unitframes) == "table" then C.unitframes = copyTable(src.unitframes, 0) end
  C.nameplates = copyTable(src.nameplates, 0)
  if type(C.appearance) ~= "table" then C.appearance = {} end
  if type(src.appearance) == "table" then
    if type(src.appearance.border) == "table" then C.appearance.border = copyTable(src.appearance.border, 0) end
    if type(src.appearance.cd) == "table" then C.appearance.cd = copyTable(src.appearance.cd, 0) end
  end
  if type(C.icha) ~= "table" then C.icha = {} end
  C.icha.imported = "ShaguPlatesX " .. tostring(src.version or "?")
  fixMedia(C, 0)
  IchaPlates.borders = nil
  IchaPlates.pixel = nil
  return true
end

function IchaPlates:Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccIchaPlates|r: " .. tostring(msg))
  end
end

function IchaPlates:IsLeaving()
  if IchaUI_LEAVING then return true end
  return IchaPlates.leaving and true or false
end

local function setLeaving(on)
  on = on and true or false
  IchaPlates.leaving = on
  local np = IchaPlates.nameplates
  if np and np.SetLeaving then np.SetLeaving(on) end
end

-- IchaUI\Leaving.lua also arms on Logout()/Quit() before any event fires.
if IchaUI_OnLeaving then
  IchaUI_OnLeaving(setLeaving)
end

function IchaPlates:UpdateFonts()
  -- abort when config is not ready yet
  if not IchaPlates_config or not IchaPlates_config.global then return end
  local G = IchaPlates_config.global

  -- load font configuration
  local default, unit, unit_name, combat
  if G.force_region == "1" and GetLocale() == "zhCN" and IchaPlates.expansion == "vanilla" then
    -- force locale compatible fonts (zhCN 1.12)
    default = "Fonts\\FZXHLJW.TTF"
    combat = "Fonts\\FZXHLJW.TTF"
    unit = "Fonts\\FZXHLJW.TTF"
    unit_name = "Fonts\\FZXHLJW.TTF"
  elseif G.force_region == "1" and GetLocale() == "zhTW" and IchaPlates.expansion == "vanilla" then
    -- force locale compatible fonts (zhTW 1.12)
    default = "Fonts\\FZXHLJW.ttf"
    combat = "Fonts\\FZXHLJW.ttf"
    unit = "Fonts\\FZXHLJW.ttf"
    unit_name = "Fonts\\FZXHLJW.ttf"
  elseif G.force_region == "1" and GetLocale() == "koKR" then
    -- force locale compatible fonts (koKR)
    default = "Fonts\\2002.TTF"
    combat = "Fonts\\2002.TTF"
    unit = "Fonts\\2002.TTF"
    unit_name = "Fonts\\2002.TTF"
  else
    -- use default entries
    default = IchaPlates.media[G.font_default]
    combat = IchaPlates.media[G.font_combat]
    unit = IchaPlates.media[G.font_unit]
    unit_name = IchaPlates.media[G.font_unit_name]
  end

  -- write setting shortcuts
  IchaPlates.font_default = default
  IchaPlates.font_combat = combat
  IchaPlates.font_unit = unit
  IchaPlates.font_unit_name = unit_name
end

function IchaPlates:GetEnvironment()
  -- load api into environment
  local m, func
  for m, func in pairs(IchaPlates.api or {}) do
    IchaPlates.env[m] = func
  end

  if not IchaPlates.env.T then
    IchaPlates.env.T = setmetatable({}, { __index = function(tab, key)
      local value = tostring(key)
      rawset(tab, key, value)
      return value
    end})
  end

  IchaPlates.env._G = getfenv(0)
  IchaPlates.env.C = IchaPlates_config
  IchaPlates.env.L = IchaPlates.GetLocaleTable()

  return IchaPlates.env
end

function IchaPlates.GetLocaleTable()
  local L = IchaPlates_locale[GetLocale()] or IchaPlates_locale["enUS"] or {}
  local en = IchaPlates_locale["enUS"]
  if en and L ~= en and not getmetatable(L) then
    setmetatable(L, { __index = en })
  end
  return L
end

function IchaPlates:RegisterModule(name, a2, a3)
  if IchaPlates.module[name] then return end
  local hasv = type(a2) == "string"
  local func, version = hasv and a3 or a2, hasv and a2 or "vanilla"

  -- check for client compatibility
  if not strfind(version, IchaPlates.expansion) then return end

  IchaPlates.module[name] = func
  table.insert(IchaPlates.modules, name)
  if not IchaPlates.bootup then
    IchaPlates:LoadModule(name)
  end
end

function IchaPlates:LoadModule(m)
  setfenv(IchaPlates.module[m], IchaPlates:GetEnvironment())
  IchaPlates.module[m]()
end

-- Disable ShaguTweaks / SuperAPI duplicates exactly like ShaguPlatesX does.
function IchaPlates:ApplyCompatOverrides()
  local C = IchaPlates_config

  -- disable ShaguTweaks nameplate library to avoid duplicate processing
  if C.global.override_shagutweaks_nameplates == "1" and ShaguTweaks and ShaguTweaks.libnameplate then
    ShaguTweaks.libnameplate:SetScript("OnUpdate", nil)
    ShaguTweaks.libnameplate.OnInit = {}
    ShaguTweaks.libnameplate.OnShow = {}
    ShaguTweaks.libnameplate.OnUpdate = {}
  end

  -- manage ShaguTweaks target frame libraries based on TargetFrame visibility
  -- disable libdebuff and libcast if the frame is permanently hidden by another addon
  if C.global.override_shagutweaks_targetlibs == "1" and ShaguTweaks and (ShaguTweaks.libdebuff or ShaguTweaks.libcast) then
    local libdebuff = ShaguTweaks.libdebuff
    local libcast = ShaguTweaks.libcast

    local libdebuff_stored = false
    local libdebuff_onevent, libdebuff_updateunits
    local libdebuff_events = {
      "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE",
      "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
      "CHAT_MSG_SPELL_FAILED_LOCALPLAYER",
      "CHAT_MSG_SPELL_SELF_DAMAGE",
      "PLAYER_TARGET_CHANGED",
      "SPELLCAST_STOP",
      "UNIT_AURA",
      "CHAT_MSG_COMBAT_SELF_HITS",
    }

    local libcast_stored = false
    local libcast_onevent
    local libcast_events = {
      "CHAT_MSG_SPELL_SELF_DAMAGE",
      "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE",
      "CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF",
      "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE",
      "CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF",
      "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS",
      "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS",
      "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE",
      "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE",
      "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE",
      "CHAT_MSG_SPELL_PARTY_DAMAGE",
      "CHAT_MSG_SPELL_PARTY_BUFF",
      "CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE",
      "CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS",
      "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
      "CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS",
      "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
      "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_BUFF",
      "SPELLCAST_START",
      "SPELLCAST_STOP",
      "SPELLCAST_FAILED",
      "SPELLCAST_INTERRUPTED",
      "SPELLCAST_DELAYED",
      "SPELLCAST_CHANNEL_START",
      "SPELLCAST_CHANNEL_STOP",
      "SPELLCAST_CHANNEL_UPDATE",
    }

    local function DisableTargetFrameLibs()
      if libdebuff and not libdebuff_stored then
        libdebuff_onevent = libdebuff:GetScript("OnEvent")
        libdebuff_updateunits = libdebuff.UpdateUnits
        libdebuff:UnregisterAllEvents()
        libdebuff:SetScript("OnEvent", nil)
        libdebuff.UpdateUnits = function() end
        libdebuff_stored = true
      end
      if libcast and not libcast_stored then
        libcast_onevent = libcast:GetScript("OnEvent")
        libcast:UnregisterAllEvents()
        libcast:SetScript("OnEvent", nil)
        libcast_stored = true
      end
    end

    local function EnableTargetFrameLibs()
      local _, ev
      if libdebuff and libdebuff_stored then
        for _, ev in pairs(libdebuff_events) do
          pcall(libdebuff.RegisterEvent, libdebuff, ev)
        end
        libdebuff:SetScript("OnEvent", libdebuff_onevent)
        libdebuff.UpdateUnits = libdebuff_updateunits
        libdebuff_stored = false
      end
      if libcast and libcast_stored then
        for _, ev in pairs(libcast_events) do
          pcall(libcast.RegisterEvent, libcast, ev)
        end
        libcast:SetScript("OnEvent", libcast_onevent)
        libcast_stored = false
      end
    end

    -- check if TargetFrame is permanently hidden (has target but frame not visible)
    local targetlibs_checker = CreateFrame("Frame")
    local checked = false
    targetlibs_checker:RegisterEvent("PLAYER_TARGET_CHANGED")
    targetlibs_checker:SetScript("OnEvent", function()
      if checked then return end
      if UnitExists("target") then
        checked = true
        -- we have a target - if TargetFrame still isn't visible, it's been replaced
        if TargetFrame and not TargetFrame:IsVisible() then
          DisableTargetFrameLibs()
        end
        targetlibs_checker:UnregisterAllEvents()
      end
    end)

    -- also hook TargetFrame hide for dynamic detection
    if TargetFrame then
      local oldHide = TargetFrame:GetScript("OnHide")
      TargetFrame:SetScript("OnHide", function()
        if oldHide then oldHide() end
        -- only disable if hidden while we have a target (permanent hide)
        if UnitExists("target") and checked then
          DisableTargetFrameLibs()
        end
      end)

      local oldShow = TargetFrame:GetScript("OnShow")
      TargetFrame:SetScript("OnShow", function()
        if oldShow then oldShow() end
        EnableTargetFrameLibs()
      end)
    end
  end
end

StaticPopupDialogs["ICHAPLATES_SHAGUPLATESX"] = {
  text = "|cff33ffccIchaPlates|r is built into IchaUI now and your ShaguPlatesX settings were copied over.\n\nShaguPlatesX is still enabled, so IchaPlates is standing by to avoid double nameplates.\n\nDisable |cffffffaaShaguPlatesX|r in the AddOns list at character select, then restart the game.",
  button1 = TEXT(OKAY),
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

function IchaPlates:ShowConflictNotice()
  self:Print("ShaguPlatesX is also enabled, so IchaPlates is standing by (no double plates). Disable ShaguPlatesX in the AddOns list and restart to use IchaPlates.")
  local C = IchaPlates_config
  if C.icha and C.icha.notice ~= "1" then
    C.icha.notice = "1"
    if StaticPopup_Show then StaticPopup_Show("ICHAPLATES_SHAGUPLATESX") end
  end
end

-- Human readable state for the /iui Plates tab.
function IchaPlates_Status()
  local s = IchaPlates.state
  if s == "active" then return "Active", 0.4, 1, 0.4 end
  if s == "deferred" then return "Standing by: disable ShaguPlatesX in the AddOns list, then restart", 1, 0.45, 0.35 end
  if s == "disabled" then return "Disabled (reload to apply)", 0.8, 0.8, 0.8 end
  if s == "nosuperwow" then return "Needs SuperWoW 1.4+", 1, 0.45, 0.35 end
  return "Loading", 0.8, 0.8, 0.8
end

function IchaPlates:Start()
  local C = self:BindConfig()
  if type(C.icha) ~= "table" then C.icha = {} end

  -- one-time import from ShaguPlatesX; later loads never overwrite IchaUIDB.plates
  if not C.icha.imported then
    if self:ImportShaguPlatesX() then
      self:Print("imported your ShaguPlatesX settings into IchaUI (/iui > Plates).")
    else
      C.icha.imported = "defaults"
    end
  end

  self:LoadConfig()
  self:MigrateConfig()
  self:FixMedia()
  self:UpdateFonts()

  if IchaPlates_config.icha.enabled ~= "1" then
    self.state = "disabled"
    return
  end

  if not SetAutoloot then
    self.state = "nosuperwow"
    self:Print("requires SuperWoW 1.4 or greater. https://github.com/balakethelock/SuperWoW/releases/")
    return
  end

  if IchaPlates.ShaguPlatesXLoaded() then
    self.state = "deferred"
    self:ShowConflictNotice()
    return
  end

  self:ApplyCompatOverrides()

  -- load modules
  local _, m
  for _, m in pairs(self.modules) do
    if not (IchaPlates_config["disabled"] and IchaPlates_config["disabled"][m] == "1") then
      IchaPlates:LoadModule(m)
    end
  end

  self.bootup = nil
  self.state = "active"
  if self:IsLeaving() then setLeaving(true) end
end

-- Re-read IchaUIDB.plates (profile load, reset) and repaint live plates.
function IchaPlates_Reload()
  local C = IchaPlates:BindConfig()
  if type(C.icha) ~= "table" then C.icha = {} end
  if not C.icha.imported then C.icha.imported = "profile" end
  IchaPlates:LoadConfig()
  IchaPlates:FixMedia()
  IchaPlates.borders = nil
  IchaPlates.pixel = nil
  if IchaPlates.api and IchaPlates.api.ResetTimeColors then IchaPlates.api.ResetTimeColors() end
  IchaPlates:UpdateFonts()
  IchaPlates:GetEnvironment()
  if IchaPlates.state == "active" and IchaPlates.nameplates and IchaPlates.nameplates.UpdateConfig then
    IchaPlates.nameplates.UpdateConfig()
  end
end

-- Live update after a /iui change that ShaguPlatesX applied without reload.
function IchaPlates_Apply()
  if IchaPlates.api and IchaPlates.api.ResetTimeColors then IchaPlates.api.ResetTimeColors() end
  if IchaPlates.state == "active" and IchaPlates.nameplates and IchaPlates.nameplates.UpdateConfig then
    IchaPlates.nameplates.UpdateConfig()
  end
end

-- Gold theme changed (IchaUI_RefreshGoldTheme).
function IchaPlates_ThemeRefresh()
  if IchaPlates_config and IchaPlates_config.icha and IchaPlates_config.icha.theme == "1" then
    IchaPlates_Apply()
  end
end

IchaPlates:SetScript("OnEvent", function()
  if event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_LOGOUT" then
    setLeaving(true)
    return
  end
  if event == "PLAYER_ENTERING_WORLD" then
    setLeaving(false)
    return
  end

  if event == "ADDON_LOADED" then
    if arg1 ~= IchaPlates.name then return end
    -- read IchaPlates version from .toc file
    local major, minor, fix = IchaPlates.api.strsplit(".", tostring(GetAddOnMetadata(IchaPlates.name, "Version")))
    IchaPlates.version.major = tonumber(major) or 1
    IchaPlates.version.minor = tonumber(minor) or 2
    IchaPlates.version.fix   = tonumber(fix)   or 0
    IchaPlates.version.string = IchaPlates.version.major .. "." .. IchaPlates.version.minor .. "." .. IchaPlates.version.fix

    local C = IchaPlates:BindConfig()
    -- ShaguTweaks skips its own nameplate mods when ShaguPlates exists (it checks at
    -- VARIABLES_LOADED). ShaguPlatesX sets this itself when it is the one running.
    local off = type(C.icha) == "table" and C.icha.enabled == "0"
    if not off and SetAutoloot and not ShaguPlates and not IchaPlates.ShaguPlatesXEnabled() then
      ShaguPlates = IchaPlates
    end
    return
  end

  if event == "PLAYER_LOGIN" then
    this:UnregisterEvent("PLAYER_LOGIN")
    IchaPlates:Start()
  end
end)

IchaPlates.backdrop = {
  bgFile = "Interface\\BUTTONS\\WHITE8X8", tile = false, tileSize = 0,
  edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1,
  insets = {left = -1, right = -1, top = -1, bottom = -1},
}
IchaPlates.backdrop_no_top = IchaPlates.backdrop

IchaPlates.backdrop_thin = {
  bgFile = "Interface\\BUTTONS\\WHITE8X8", tile = false, tileSize = 0,
  edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1,
  insets = {left = 0, right = 0, top = 0, bottom = 0},
}

IchaPlates.backdrop_hover = {
  edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 24,
  insets = {left = -1, right = -1, top = -1, bottom = -1},
}

IchaPlates.backdrop_shadow = {
  edgeFile = IchaPlates.media["img:glow2"], edgeSize = 8,
  insets = {left = 0, right = 0, top = 0, bottom = 0},
}

IchaPlates.backdrop_blizz_bg = {
  bgFile =  "Interface\\BUTTONS\\WHITE8X8", tile = true, tileSize = 8,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

IchaPlates.backdrop_blizz_border = {
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

IchaPlates.backdrop_blizz_full = {
  bgFile =  "Interface\\BUTTONS\\WHITE8X8", tile = true, tileSize = 8,
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

-- slash commands (ShaguPlatesX's /sp, /spx stay with ShaguPlatesX)
SLASH_ICHAPLATES1 = "/iplates"
SLASH_ICHAPLATES2 = "/ichaplates"
function SlashCmdList.ICHAPLATES(msg)
  if IchaUIOptions_Open then
    IchaUIOptions_Open()
    local p = getglobal("IchaUIOptions")
    if p and p.showTab then p.showTab("Plates") end
  end
end

-- ShaguPlatesX also provided these two; keep them when nothing else does.
if not SlashCmdList.RELOAD then
  SLASH_RELOAD1 = "/rl"
  function SlashCmdList.RELOAD(msg, editbox)
    ReloadUI()
  end
end

if not SlashCmdList.GM then
  SLASH_GM1, SLASH_GM2 = "/gm", "/support"
  function SlashCmdList.GM(msg, editbox)
    ToggleHelpFrame(1)
  end
end
