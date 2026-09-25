-- Core /icha and /iui. Bar commands go to IchaUI_Bars (IchaUIBars_Slash).
-- TotemRecall may wrap SlashCmdList["ICHA"] after this file loads.

SLASH_ICHA1 = "/icha"
SLASH_ICHA2 = "/ichaui"
SLASH_IUI1 = "/iui"

local function openOptions()
    if IchaUIOptions_Toggle then
        IchaUIOptions_Toggle()
    else
        DEFAULT_CHAT_FRAME:AddMessage("Options panel not loaded.")
    end
end

local function maskDebug()
    if IchaUI_MaskDebug then
        IchaUI_MaskDebug()
    else
        DEFAULT_CHAT_FRAME:AddMessage("IchaUI maskdebug: IchaUI_MaskDebug missing. DrawerStyle.lua did not load.")
    end
end

SlashCmdList["IUI"] = function(msg)
    msg = string.lower(string.gsub(msg or "", "^%s+", ""))
    if msg == "maskdebug" then
        maskDebug()
        return
    end
    openOptions()
end

SlashCmdList["ICHA"] = function(msg)
    msg = string.lower(string.gsub(msg or "", "^%s+", ""))
    if msg == "maskdebug" then
        maskDebug()
        return
    end
    if msg == "options" or msg == "option" or msg == "config" or msg == "opt" then
        openOptions()
        return
    end
    if msg == "" then
        DEFAULT_CHAT_FRAME:AddMessage("IchaUI: /iui for options. /icha <cmd> — hotkeys|bind|gap|scale|heroscale|move|xp|uf|totems|imbue|shield|utility|buffs|chat|shock|shieldbind")
        return
    end
    if string.find(msg, "^xp") then
        local rest = string.gsub(msg, "^xp%s*", "")
        if IchaUIXP_Slash then
            IchaUIXP_Slash(rest)
        else
            DEFAULT_CHAT_FRAME:AddMessage("XP bar not loaded.")
        end
        return
    end
    if string.find(msg, "^uf") or string.find(msg, "^unit") then
        local rest = string.gsub(msg, "^uf%s*", "")
        rest = string.gsub(rest, "^unit%s*", "")
        if IchaUIUF_Slash then
            IchaUIUF_Slash(rest)
        else
            DEFAULT_CHAT_FRAME:AddMessage("Unit frames not loaded.")
        end
        return
    end
    if string.find(msg, "^totems") or string.find(msg, "^totem") then
        local rest = string.gsub(msg, "^totems%s*", "")
        rest = string.gsub(rest, "^totem%s*", "")
        if IchaUITotems_Slash then
            IchaUITotems_Slash(rest)
        else
            DEFAULT_CHAT_FRAME:AddMessage("Totem bar not loaded.")
        end
        return
    end
    if string.find(msg, "^shieldbind") then
        local rest = string.gsub(msg, "^shieldbind%s*", "")
        if IchaUIShieldBinds_Slash then
            IchaUIShieldBinds_Slash(rest)
        else
            DEFAULT_CHAT_FRAME:AddMessage("Shield binds not loaded.")
        end
        return
    end
    if string.find(msg, "^imbue") or string.find(msg, "^shield") or string.find(msg, "^utility") or string.find(msg, "^util") then
        if IchaUIShamanExtras_Slash then
            IchaUIShamanExtras_Slash(msg)
        else
            DEFAULT_CHAT_FRAME:AddMessage("Shaman extras not loaded.")
        end
        return
    end
    if string.find(msg, "^buffs") or string.find(msg, "^buff") or string.find(msg, "^debuffs") then
        local rest = string.gsub(msg, "^buffs%s*", "")
        rest = string.gsub(rest, "^buff%s*", "")
        rest = string.gsub(rest, "^debuffs%s*", "")
        if IchaUIBuffBars_Slash then
            IchaUIBuffBars_Slash(rest)
        else
            DEFAULT_CHAT_FRAME:AddMessage("Buff bars not loaded.")
        end
        return
    end
    if string.find(msg, "^chat") then
        local rest = string.gsub(msg, "^chat%s*", "")
        if IchaUIChatSkin_Slash then
            IchaUIChatSkin_Slash(rest)
        else
            DEFAULT_CHAT_FRAME:AddMessage("Chat skin not loaded.")
        end
        return
    end
    if string.find(msg, "^shock") then
        local rest = string.gsub(msg, "^shock%s*", "")
        if IchaUIShockBinds_Slash then
            IchaUIShockBinds_Slash(rest)
        else
            DEFAULT_CHAT_FRAME:AddMessage("Shock binds not loaded.")
        end
        return
    end
    if msg == "move" or msg == "edit" then
        if IchaUI_EditModeActive and IchaUI_EditModeActive() then
            if IchaUI_EditPositionsCancel then IchaUI_EditPositionsCancel() end
            return
        end
        if IchaUI_EditPositions then
            IchaUI_EditPositions()
            return
        end
    end
    if IchaUIBars_Slash then
        IchaUIBars_Slash(msg)
        return
    end
    if msg == "move" or msg == "edit" then
        DEFAULT_CHAT_FRAME:AddMessage("Edit positions not loaded.")
        return
    end
    DEFAULT_CHAT_FRAME:AddMessage("IchaUI: /iui opens options. Also: hotkeys | bind | gap | scale | heroscale | move | show | hide | wipe | xp | uf | totems | buffs | chat")
end
