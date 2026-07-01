local _, SlotFiller = ...

local Constants = SlotFiller.Constants
local ActionAPI = SlotFiller.ActionAPI
local SpellBookAPI = SlotFiller.SpellBookAPI

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

local function getOutfitName(outfitID)
    if C_TransmogOutfitInfo and C_TransmogOutfitInfo.GetOutfitInfo then
        local outfitInfo = C_TransmogOutfitInfo.GetOutfitInfo(outfitID)
        return outfitInfo and outfitInfo.name
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
    local perCharacter = macroID ~= nil and macroID > (MAX_ACCOUNT_MACROS or Constants.MAX_ACCOUNT_MACROS_FALLBACK)
    return name, icon, body, perCharacter
end

-- zoneAbilitySpellIDs is an optional pre-built { [spellID] = true } lookup set
-- derived from C_ZoneAbility.GetActiveAbilities() by Scan(), so a full 180-slot
-- scan does one O(1) lookup per spell slot instead of a linear scan of the
-- (usually tiny, but not guaranteed) active-abilities list per slot.
-- spellOverrideMap is an optional pre-built override-ID -> base-ID table (see
-- ActionAPI.BuildSpellOverrideMap) used to normalise spell slots; also built
-- once per Scan() and shared across all 180 slots.
function SlotFiller.Scanner:ReadSlot(actionID, zoneAbilitySpellIDs, spellOverrideMap)
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
        if zoneAbilitySpellIDs and zoneAbilitySpellIDs[id] then
            raw.isZoneAbility = true
        end
        -- Normalise a talent-overridden spell back to its base ID (skip zone
        -- abilities and SBA, which aren't real spellbook entries) so the saved
        -- slot survives talent or spec changes made after the save.
        if not raw.isZoneAbility and subType ~= Constants.ACTION_SUBTYPE.ASSISTEDCOMBAT
            and spellOverrideMap and spellOverrideMap[id] then
            raw.id = spellOverrideMap[id]
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
    elseif actionType == Constants.ACTION_TYPE.OUTFIT then
        raw.name = getOutfitName(id)
    end

    return SlotFiller.Normalizer.FromRaw(raw)
end

function SlotFiller.Scanner:Scan()
    local slots = {}
    local zoneAbilities = (C_ZoneAbility and C_ZoneAbility.GetActiveAbilities)
        and C_ZoneAbility.GetActiveAbilities() or nil
    local zoneAbilitySpellIDs = nil
    if zoneAbilities then
        zoneAbilitySpellIDs = {}
        for _, za in ipairs(zoneAbilities) do
            if za.spellID then
                zoneAbilitySpellIDs[za.spellID] = true
            end
        end
    end
    local spellOverrideMap = SpellBookAPI.BuildSpellOverrideMap()
    for actionID = Constants.SLOT_MIN, Constants.SLOT_MAX do
        local slot = self:ReadSlot(actionID, zoneAbilitySpellIDs, spellOverrideMap)
        if slot then
            slots[actionID] = slot
        end
        if actionID % Constants.ASYNC_YIELD_BATCH == 0 then
            SlotFiller.Async.MaybeYield()
        end
    end
    return slots
end

-- Returns (lines, count): one formatted "[slot] type=... id=... sub=... extra=..."
-- string per occupied action slot, and the occupied-slot count. Shared by the
-- production `/sfill scan` command (prints each line) and the dev-only
-- diagnostic command (shows them in the copy-popup), so the two never drift.
function SlotFiller.Scanner:FormatSlotDump()
    local lines = {}
    local count = 0
    for actionID = Constants.SLOT_MIN, Constants.SLOT_MAX do
        local actionType, id, subType, extraID = ActionAPI.GetSlotActionInfo(actionID)
        if actionType and actionType ~= "" then
            count = count + 1
            lines[#lines + 1] = string.format("[%d] type=%s id=%s sub=%s extra=%s",
                actionID, tostring(actionType), tostring(id),
                tostring(subType), tostring(extraID))
        end
    end
    return lines, count
end

function SlotFiller.Scanner:CaptureCurrentProfile()
    local profile = SlotFiller.Normalizer.BuildProfile(self:Scan())

    -- petSlots/clickBindings are only attached when there is something to
    -- capture (a pet is out / click bindings are supported) so an older
    -- profile, or one saved without a pet out, never causes the restorer to
    -- wipe live data it has no information about.
    if SlotFiller.PetActionAPI.IsActive() then
        profile.petSlots = SlotFiller.PetBar:Scan()
    end

    local clickBindings = SlotFiller.ClickBindings:Scan()
    if clickBindings then
        profile.clickBindings = clickBindings
    end

    return profile
end
