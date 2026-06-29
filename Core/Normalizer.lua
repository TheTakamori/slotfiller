local _, SlotFiller = ...

local Constants = SlotFiller.Constants

SlotFiller.Normalizer = {}

local function trim(text)
    if type(text) ~= "string" then
        return ""
    end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function SlotFiller.Normalizer.CompressMacroText(text)
    text = text or ""
    text = text:gsub("\n", "/n")
    text = text:gsub("/n$", "")
    text = text:gsub("||", "/124")
    return trim(text)
end

function SlotFiller.Normalizer.UncompressMacroText(text)
    text = text or ""
    text = text:gsub("/n", "\n")
    text = text:gsub("/124", "|")
    return trim(text)
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
        if not actionType or actionType == "" then
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
    elseif actionType == Constants.ACTION_TYPE.ITEM then
        slot.id = raw.id
        slot.name = raw.name
    elseif actionType == Constants.ACTION_TYPE.MACRO then
        slot.macroID = raw.id
        slot.actionID = raw.actionID
        slot.name = raw.name
        slot.body = SlotFiller.Normalizer.CompressMacroText(raw.body)
    elseif actionType == Constants.ACTION_TYPE.FLYOUT then
        slot.id = raw.id
        slot.name = raw.name
    elseif actionType == Constants.ACTION_TYPE.SUMMONMOUNT then
        if raw.id == nil then
            return nil
        end
        slot.id = raw.id
    elseif actionType == Constants.ACTION_TYPE.COMPANION then
        slot.id = raw.id
        slot.subType = raw.subType
    elseif actionType == Constants.ACTION_TYPE.EQUIPMENTSET then
        slot.id = raw.id
        slot.name = raw.name
    end

    return slot
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

