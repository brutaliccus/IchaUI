-- IchaPlates: modules/superwow.lua (ported from ShaguPlatesX modules/superwow.lua).
-- ShaguPlatesX: Copyright (c) 2016-2021 Eric Mauser (Shagu), adapted by Ehawne.
-- MIT License, see LICENSE-ShaguPlates.txt. Derived from pfUI by Shagu.
-- The pfUI unitframe parts (mouseover cast, druid mana, focus) had no frames to act on
-- in ShaguPlatesX and are not ported.

IchaPlates:RegisterModule("superwow", "vanilla", function ()
  if SetAutoloot and SpellInfo and not SUPERWOW_VERSION then
    -- Turn every enchanting link that we create in the enchanting frame,
    -- from "spell:" back into "enchant:". The enchant-version is what is
    -- used by all unmodified game clients. This is required to generate
    -- usable links for everyone from the enchant frame while having SuperWoW.
    local HookGetCraftItemLink = GetCraftItemLink
    _G.GetCraftItemLink = function(index)
      local link = HookGetCraftItemLink(index)
      return string.gsub(link, "spell:", "enchant:")
    end

    -- Convert every enchanting link that we receive into a
    -- spell link, as for some reason SuperWoW can't handle
    -- enchanting links at all and requires it to be a spell.
    local HookSetItemRef = SetItemRef
    _G.SetItemRef = function(link, text, button)
      link = string.gsub(link, "enchant:", "spell:")
      HookSetItemRef(link, text, button)
    end

    local HookGameTooltipSetHyperlink = GameTooltip.SetHyperlink
    _G.GameTooltip.SetHyperlink = function(self, link)
      link = string.gsub(link, "enchant:", "spell:")
      HookGameTooltipSetHyperlink(self, link)
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cffffffaaAn old version of SuperWoW was detected. Please consider updating:")
    DEFAULT_CHAT_FRAME:AddMessage("-> https://github.com/balakethelock/SuperWoW/releases/")
  end

  if SUPERWOW_VERSION == "1.5" then
    QueueFunction(function()
      local HookCombatText_AddMessage = _G.CombatText_AddMessage
      if not HookCombatText_AddMessage then return end
      _G.CombatText_AddMessage = function(message, a, b, c, d, e, f)
        local _, _, hex = string.find(message or "", ".+ %[(0x.+)%]")
        if hex and not IchaPlates:IsLeaving() and UnitName(hex) then
          message = string.gsub(message, hex, UnitName(hex))
        end

        HookCombatText_AddMessage(message, a, b, c, d, e, f)
      end
    end)
  end

  -- Mark SuperWoW as active
  superwow_active = true
end)
