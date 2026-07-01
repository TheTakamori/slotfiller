local _, SlotFiller = ...

local Constants = SlotFiller.Constants

-- Raw WoW API wrappers for Click Bindings (click-cast: spells/items/macros bound
-- to a mouse button + modifier, mainly used by healers on raid/party frames).
-- Retail-only; C_ClickBindings is genuinely absent on Classic.
SlotFiller.ClickBindingAPI = {}

function SlotFiller.ClickBindingAPI.IsSupported()
    return C_ClickBindings ~= nil
        and C_ClickBindings.GetProfileInfo ~= nil
        and C_ClickBindings.SetProfileByInfo ~= nil
end

function SlotFiller.ClickBindingAPI.GetProfileInfo()
    if not SlotFiller.ClickBindingAPI.IsSupported() then
        return {}
    end
    return C_ClickBindings.GetProfileInfo() or {}
end

function SlotFiller.ClickBindingAPI.SetProfileInfo(entries)
    if not SlotFiller.ClickBindingAPI.IsSupported() then
        return false
    end
    C_ClickBindings.SetProfileByInfo(entries)
    return true
end

-- Bindings of this type reference a macro by index, which isn't stable across
-- characters — ClickBindings captures name/body/icon for these instead and
-- resolves them the same way action-bar macro slots do. Falls back to the
-- documented numeric value when the Enum table is unavailable (older clients
-- or the plain-Lua test host).
function SlotFiller.ClickBindingAPI.GetMacroTypeValue()
    return (Enum and Enum.ClickBindingType and Enum.ClickBindingType.Macro)
        or Constants.CLICK_BINDING_TYPE_MACRO_FALLBACK
end
