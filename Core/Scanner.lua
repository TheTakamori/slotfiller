local _, SlotFiller = ...

local Constants = SlotFiller.Constants
local ActionAPI = SlotFiller.ActionAPI

SlotFiller.Scanner = {}

local function getSpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end
    if GetSpellInfo then
        return GetSpellInfo(spellID)
    end
    return nil
end

local function getFlyoutName(flyoutID)
    if GetFlyoutInfo then
        return GetFlyoutInfo(flyoutID)
    end
    return nil
end

local function getItemName(itemID)
    if C_Item and C_Item.GetItemNameByID then
        return C_Item.GetItemNameByID(itemID)
    end
    if GetItemInfo then
        return GetItemInfo(itemID)
    end
    return nil
end

local function readMacro(actionID, macroID)
    local name, icon, body
    if GetMacroInfo and macroID then
        name, icon, body = GetMacroInfo(macroID)
    end
    if (not name or name == "") and GetActionText then
        name = GetActionText(actionID)
    end
    -- Character-specific macros occupy slots above MAX_ACCOUNT_MACROS (120).
    local perCharacter = macroID ~= nil and macroID > (MAX_ACCOUNT_MACROS or 120)
    return name, icon, body, perCharacter
end

-- zoneAbilities is an optional pre-fetched list from C_ZoneAbility.GetActiveAbilities(),
-- passed in by Scan() to avoid redundant API calls across the full slot range.
function SlotFiller.Scanner:ReadSlot(actionID, zoneAbilities)
    local actionType, id, subType, extraID = ActionAPI.GetSlotActionInfo(actionID)
    -- Replicate HasSlotAction logic with already-fetched values to avoid a
    -- second GetSlotActionInfo call per slot (saves 180 redundant API calls
    -- during a full-bar scan).
    if not actionType or actionType == "" then
        return nil
    end
    if actionType == Constants.ACTION_TYPE.EQUIPMENTSET then
        if id == nil or id == "" then return nil end
    elseif id == nil then
        return nil
    end

    local raw = {
        type = actionType,
        id = id,
        actionID = actionID,
        subType = subType,
        extraID = extraID,
    }

    if actionType == Constants.ACTION_TYPE.SPELL then
        raw.name = getSpellName(id)
        -- Detect Draenor/zone abilities (hidden from spellbook; managed by C_ZoneAbility).
        -- Tagging them here lets the Restorer use the correct pickup path and surface a
        -- meaningful error if restoration fails rather than silently skipping the slot.
        if zoneAbilities then
            for _, za in ipairs(zoneAbilities) do
                if za.spellID == id then
                    raw.isZoneAbility = true
                    break
                end
            end
        end
    elseif actionType == Constants.ACTION_TYPE.ITEM then
        raw.name = getItemName(id)
    elseif actionType == Constants.ACTION_TYPE.MACRO then
        local name, icon, body, perCharacter = readMacro(actionID, id)
        raw.name = name
        raw.icon = icon
        raw.body = body
        raw.perCharacter = perCharacter
    elseif actionType == Constants.ACTION_TYPE.FLYOUT then
        raw.name = getFlyoutName(id)
    elseif actionType == Constants.ACTION_TYPE.SUMMONPET then
        -- id is a GUID string (e.g. "BattlePet-0-00000B4B64D9").
        -- Attempt to resolve a display name for use in error messages.
        if C_PetJournal and C_PetJournal.GetPetInfoByPetID and id then
            local _, customName, _, _, _, _, _, speciesName = C_PetJournal.GetPetInfoByPetID(id)
            raw.name = customName or speciesName
        end
    elseif actionType == Constants.ACTION_TYPE.EQUIPMENTSET then
        raw.name = id
    end

    return SlotFiller.Normalizer.FromRaw(raw)
end

function SlotFiller.Scanner:Scan()
    local slots = {}
    local zoneAbilities = (C_ZoneAbility and C_ZoneAbility.GetActiveAbilities)
        and C_ZoneAbility.GetActiveAbilities() or nil
    for actionID = Constants.SLOT_MIN, Constants.SLOT_MAX do
        local slot = self:ReadSlot(actionID, zoneAbilities)
        if slot then
            slots[actionID] = slot
        end
    end
    return slots
end

function SlotFiller.Scanner:CaptureCurrentProfile()
    return SlotFiller.Normalizer.BuildProfile(self:Scan())
end
