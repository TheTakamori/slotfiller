local _, SlotFiller = ...

local Constants = SlotFiller.Constants
local Strings = SlotFiller.Strings

SlotFiller.Normalizer = {}

local MacroEscape = Constants.MACRO_ESCAPE

function SlotFiller.Normalizer.CompressMacroText(text)
    text = text or ""
    text = text:gsub("\n", MacroEscape.NEWLINE)
    text = text:gsub(MacroEscape.NEWLINE .. "$", "")
    text = text:gsub("||", MacroEscape.PIPE)
    return Strings.Trim(text)
end

function SlotFiller.Normalizer.UncompressMacroText(text)
    text = text or ""
    text = text:gsub(MacroEscape.NEWLINE, "\n")
    text = text:gsub(MacroEscape.PIPE, "|")
    return Strings.Trim(text)
end

function SlotFiller.Normalizer.IsSupportedActionType(actionType)
    if not actionType then
        return false
    end
    -- UNKNOWN is a storage-only passthrough type, never a native WoW action type
    if actionType == Constants.ACTION_TYPE.UNKNOWN then
        return false
    end
    for _, supportedType in pairs(Constants.ACTION_TYPE) do
        if actionType == supportedType then
            return true
        end
    end
    return false
end

function SlotFiller.Normalizer.FromRaw(raw)
    if not raw or not raw.type then
        return nil
    end

    local actionType = raw.type
    if not SlotFiller.Normalizer.IsSupportedActionType(actionType) then
        -- Preserve any native WoW type we don't explicitly handle so it can be
        -- attempted on restore (e.g. new Midnight action types such as mounts
        -- or SBA rotation buttons that surface under an unexpected type string).
        -- NOTE: this guard is reachable — the `not raw.type` check above only
        -- rejects nil/false; an empty string "" is truthy in Lua and falls
        -- through to here, where IsSupportedActionType("") is also false.
        if actionType == "" then
            return nil
        end
        return {
            type = Constants.ACTION_TYPE.UNKNOWN,
            rawType = actionType,
            id = raw.id,
            subType = raw.subType,
            extraID = raw.extraID,
        }
    end

    local slot = {
        type = actionType,
    }

    if actionType == Constants.ACTION_TYPE.SPELL then
        if raw.id == nil then
            return nil
        end
        slot.id = raw.id
        slot.name = raw.name
        slot.subType = raw.subType
        slot.extraID = raw.extraID
        if raw.isZoneAbility then
            slot.isZoneAbility = true
        end
    elseif actionType == Constants.ACTION_TYPE.ITEM then
        slot.id = raw.id
        slot.name = raw.name
    elseif actionType == Constants.ACTION_TYPE.MACRO then
        slot.macroID = raw.id
        slot.actionID = raw.actionID
        slot.name = raw.name
        slot.body = SlotFiller.Normalizer.CompressMacroText(raw.body)
        slot.icon = raw.icon
        -- Only persist the flag for character-specific macros so global macro slots
        -- never accidentally trigger the create-on-restore path.
        if raw.perCharacter then
            slot.perCharacter = true
        end
    elseif actionType == Constants.ACTION_TYPE.FLYOUT then
        slot.id = raw.id
        slot.name = raw.name
    elseif actionType == Constants.ACTION_TYPE.SUMMONMOUNT then
        if raw.id == nil then
            return nil
        end
        slot.id = raw.id
    elseif actionType == Constants.ACTION_TYPE.SUMMONPET then
        if not raw.id then
            return nil
        end
        slot.id = raw.id
        slot.name = raw.name
    elseif actionType == Constants.ACTION_TYPE.COMPANION then
        slot.id = raw.id
        slot.subType = raw.subType
    elseif actionType == Constants.ACTION_TYPE.EQUIPMENTSET then
        slot.id = raw.id
        slot.name = raw.name
    elseif actionType == Constants.ACTION_TYPE.OUTFIT then
        slot.id = raw.id
        slot.name = raw.name
    end

    return slot
end

-- ---------------------------------------------------------------------------
-- Pet action bar
-- ---------------------------------------------------------------------------

-- raw is { token = string } for a pet command token, or { spellID = number }
-- for a pet ability. Returns nil for anything else (e.g. an empty slot).
function SlotFiller.Normalizer.FromRawPetSlot(raw)
    if not raw then
        return nil
    end
    if raw.token then
        return { type = Constants.PET_SLOT_TYPE.TOKEN, token = raw.token }
    end
    if raw.spellID then
        return { type = Constants.PET_SLOT_TYPE.SPELL, spellID = raw.spellID }
    end
    return nil
end

function SlotFiller.Normalizer.BuildPetProfile(petSlotsByIndex)
    local petSlots = {}
    for index = Constants.PET_SLOT_MIN, Constants.PET_SLOT_MAX do
        if petSlotsByIndex[index] then
            petSlots[index] = petSlotsByIndex[index]
        end
    end
    return petSlots
end

-- ---------------------------------------------------------------------------
-- Click bindings
-- ---------------------------------------------------------------------------

-- raw fields: bindingType, button, modifiers, actionID (non-macro types), and
-- macroName/macroBody/macroIcon (macro type only, captured by Scanner since a
-- raw macro index isn't stable across characters). Returns nil when there is
-- nothing stable to restore (e.g. a macro binding whose macro lookup failed).
function SlotFiller.Normalizer.FromRawClickBinding(raw)
    if not raw or raw.bindingType == nil or not raw.button then
        return nil
    end

    if raw.isMacro then
        if not raw.macroName then
            return nil
        end
        return {
            bindingType = raw.bindingType,
            button      = raw.button,
            modifiers   = raw.modifiers or 0,
            isMacro     = true,
            macroName   = raw.macroName,
            macroBody   = raw.macroBody,
            macroIcon   = raw.macroIcon,
        }
    end

    return {
        bindingType = raw.bindingType,
        button      = raw.button,
        modifiers   = raw.modifiers or 0,
        actionID    = raw.actionID,
    }
end

function SlotFiller.Normalizer.BuildProfile(slotsByIndex)
    local profile = {
        savedAt = time and time() or 0,
        slots = {},
    }

    for slotIndex = Constants.SLOT_MIN, Constants.SLOT_MAX do
        local slot = slotsByIndex[slotIndex]
        if slot then
            profile.slots[slotIndex] = slot
        end
    end

    return profile
end

function SlotFiller.Normalizer.CountFilledSlots(profile)
    if not profile or type(profile.slots) ~= "table" then
        return 0
    end

    local count = 0
    for slotIndex = Constants.SLOT_MIN, Constants.SLOT_MAX do
        if profile.slots[slotIndex] then
            count = count + 1
        end
    end
    return count
end

function SlotFiller.Normalizer.CloneProfile(profile)
    if type(CopyTable) == "function" then
        return CopyTable(profile)
    end

    -- Manual fallback (plain-Lua host, e.g. test runner).
    local copy = {
        savedAt = profile and profile.savedAt or 0,
        slots   = {},
    }
    for slotIndex, slot in pairs((profile and profile.slots) or {}) do
        copy.slots[slotIndex] = SlotFiller.Normalizer.CloneSlot(slot)
    end
    -- Deep-copy petSlots/clickBindings (optional sub-tables) so Duplicate gives
    -- the new profile independent copies, same reasoning as autoLoad below.
    if profile and profile.petSlots then
        copy.petSlots = {}
        for index, slot in pairs(profile.petSlots) do
            copy.petSlots[index] = SlotFiller.Normalizer.CloneSlot(slot)
        end
    end
    if profile and profile.clickBindings then
        copy.clickBindings = {}
        for i, entry in ipairs(profile.clickBindings) do
            copy.clickBindings[i] = SlotFiller.Normalizer.CloneSlot(entry)
        end
    end
    -- Deep-copy the autoLoad config so Duplicate gives the new profile its own
    -- independent copy (mutations to one must not affect the other).
    if profile and profile.autoLoad then
        local al = profile.autoLoad
        local chars, classes, specs = {}, {}, {}
        for _, v in ipairs(al.characters or {}) do chars[#chars+1]     = v end
        for _, v in ipairs(al.classes    or {}) do classes[#classes+1] = v end
        for _, v in ipairs(al.specs      or {}) do specs[#specs+1]     = v end
        copy.autoLoad = {
            enabled    = al.enabled,
            characters = chars,
            classes    = classes,
            specs      = specs,
        }
    end
    return copy
end

function SlotFiller.Normalizer.CloneSlot(slot)
    local copy = {}
    for key, value in pairs(slot or {}) do
        copy[key] = value
    end
    return copy
end

