-- IchaUI_DebuffDurations: localized debuff name -> { [0] = default seconds, [rank] = seconds }.
-- Shared with IchaUI\UnitFrames.lua so aura timers no longer need ShaguPlatesX loaded.
-- Data ported from ShaguPlatesX (MIT, Eric Mauser (Shagu), adapted by Ehawne).

do
  local loc = IchaPlates_locale[GetLocale()]
  if loc and loc.debuffs then
    IchaUI_DebuffDurations = loc.debuffs
  elseif IchaPlates_locale.enUS then
    IchaUI_DebuffDurations = IchaPlates_locale.enUS.debuffs
  end
end
