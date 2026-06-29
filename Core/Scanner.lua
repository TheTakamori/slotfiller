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
    local name, _, body
    if GetMacroInfo and macroID then
        name, _, body = GetMacroInfo(macroID)
    end
    if (not name or name == "") and GetActionText then
        name = GetActionText(actionID)
    end
    return name, body
end

function SlotFiller.Scanner:ReadSlot(actionID)
    local actionType, id, subType, extraID = ActionAPI.GetSlotActionInfo(actionID)
    -- Replicate HasSlotAction logic with already-fetched values to avoid a
    -- second GetSlotActionInfo call per slot (saves 180 redundant API calls
    -- during a full-bar scan).
    if not actionType or actionType == "" then
        return nil
    end
    if actionType == "equipmentset" then
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
    elseif actionType == Constants.ACTION_TYPE.ITEM then
        raw.name = getItemName(id)
    elseif actionType == Constants.ACTION_TYPE.MACRO then
        local name, body = readMacro(actionID, id)
        raw.name = name
        raw.body = body
    elseif actionType == Constants.ACTION_TYPE.FLYOUT then
        raw.name = getFlyoutName(id)
    elseif actionType == Constants.ACTION_TYPE.EQUIPMENTSET then
        raw.name = id
    end

    return SlotFiller.Normalizer.FromRaw(raw)
end

function SlotFiller.Scanner:Scan()
    local slots = {}
    for actionID = Constants.SLOT_MIN, Constants.SLOT_MAX do
        local slot = self:ReadSlot(actionID)
        if slot then
            slots[actionID] = slot
        end
    end
    return slots
end

function SlotFiller.Scanner:CaptureCurrentProfile()
    return SlotFiller.Normalizer.BuildProfile(self:Scan())
end
