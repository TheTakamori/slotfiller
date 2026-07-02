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

-- Since Patch 10.2, GetActionInfo/C_ActionBar.GetActionInfo stopped reliably
-- returning the macro slot index in `id` for a macro action: whenever the
-- macro's first valid line targets a spell, `id` is actually that spell's ID
-- (subType "spell"); when it targets an item, `id` is an unrelated, often
-- bogus number (subType "item"). Only a nil/empty subType still guarantees
-- `id` is the real macro slot. Blindly passing the unreliable id to
-- GetMacroInfo made it return nil (or, worse, some other macro's data if the
-- spell/item id happened to collide with a valid macro slot number), which
-- collapsed every affected macro's captured name/body down to nothing and
-- made unrelated macros indistinguishable from one another on restore.
-- GetActionText(actionID), unlike `id`, is unaffected by this quirk, so it's
-- used here to resolve the real macro slot via GetMacroIndexByName whenever
-- subType signals `id` can't be trusted.
local function resolveMacroID(macroID, subType, actionText)
    if not subType or subType == "" then
        -- Only case where the native id is documented to be the real macro slot.
        return macroID
    end
    if not (GetMacroIndexByName and actionText and actionText ~= "") then
        -- No name to resolve by: the native id is a known-unreliable alias
        -- (spell/item id), so drop it rather than risk GetMacroInfo silently
        -- returning some unrelated macro's data.
        return nil
    end
    local resolvedID = GetMacroIndexByName(actionText)
    return (resolvedID and resolvedID > 0) and resolvedID or nil
end

local function readMacro(actionID, macroID, subType)
    local actionText = GetActionText and GetActionText(actionID) or nil
    macroID = resolveMacroID(macroID, subType, actionText)

    local name, icon, body
    if GetMacroInfo and macroID then
        name, icon, body = GetMacroInfo(macroID)
    end
    if (not name or name == "") and actionText and actionText ~= "" then
        name = actionText
    end
    -- Character-specific macros occupy slots above MAX_ACCOUNT_MACROS (120).
    local perCharacter = macroID ~= nil and macroID > (MAX_ACCOUNT_MACROS or Constants.MAX_ACCOUNT_MACROS_FALLBACK)
    return name, icon, body, perCharacter, macroID
end

-- zoneAbilitySpellIDs is an optional pre-built { [spellID] = true } lookup set
-- derived from C_ZoneAbility.GetActiveAbilities() by Scan(), so a full 180-slot
-- scan does one O(1) lookup per spell slot instead of a linear scan of the
-- (usually tiny, but not guaranteed) active-abilities list per slot.
-- spellOverrideMap is an optional pre-built override-ID -> base-ID table (see
-- SpellBookAPI.BuildSpellOverrideMap) used to normalise spell slots; also
-- built once per Scan() and shared across all 180 slots.
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
        -- The Assisted Combat (Rotation Assistant / SBA) button isn't a real
        -- spellbook entry and can't be found by spellbook index like a normal
        -- spell, but C_AssistedCombat.GetActionSpell() reports the spell it is
        -- currently suggesting, which is itself an ordinary, pickup-able
        -- spell. Capturing that spell ID here — and treating the slot as a
        -- plain spell from that point on (clearing subType) — lets it restore
        -- through the same spell-pickup path as everything else, including
        -- the talent-override normalisation below, with no need to keep a
        -- spare SBA button elsewhere on the bars to restore from.
        if subType == Constants.ACTION_SUBTYPE.ASSISTEDCOMBAT
            and C_AssistedCombat and C_AssistedCombat.GetActionSpell then
            local suggested = C_AssistedCombat.GetActionSpell()
            -- Guard against 0: undocumented, but harmless to reject since a
            -- real spellID is never 0; falls back to the native (unresolved)
            -- id below, same as when the API is unavailable.
            if suggested and suggested ~= 0 then
                id = suggested
                raw.id = suggested
                subType = nil
                raw.subType = nil
            end
        end
        raw.name = getSpellName(id)
        -- Resolve any active override back to its base spell id up front.
        -- spellOverrideMap (built by walking the current spec's spellbook)
        -- covers ordinary talent swaps, but some overrides are never listed
        -- in any spellbook skill line — most notably vehicle/zone-ability
        -- ones like Undermine's G-99 Breakneck, whose override id (e.g.
        -- 460013) is what the action bar shows while its base id (1215279)
        -- is both what C_ZoneAbility.GetActiveAbilities() reports and the
        -- only id that can actually be picked back up (see
        -- ActionAPI.PickupZoneAbility). A spellbook walk alone can never
        -- learn that mapping, so C_Spell.GetBaseSpell — the general-purpose
        -- reverse-override lookup, which works for any spell id regardless
        -- of spellbook membership — is used as well/instead.
        if subType ~= Constants.ACTION_SUBTYPE.ASSISTEDCOMBAT then
            local baseID = (spellOverrideMap and spellOverrideMap[id])
                or (C_Spell and C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(id))
                or nil

            -- Detect Draenor/zone abilities (hidden from spellbook; managed by
            -- C_ZoneAbility). Checked against both the raw id and its
            -- base-resolved id, since the action bar can be showing an
            -- overridden/vehicle version of a zone ability rather than the id
            -- C_ZoneAbility.GetActiveAbilities() itself reports. Tagging them
            -- here lets the Restorer use the correct pickup path and surface a
            -- meaningful error if restoration fails rather than silently
            -- skipping the slot.
            if zoneAbilitySpellIDs and (zoneAbilitySpellIDs[id] or (baseID and zoneAbilitySpellIDs[baseID])) then
                raw.isZoneAbility = true
            end

            -- Normalise to the base ID so the saved slot survives talent/spec
            -- changes, and so a zone ability's override id — which pickup
            -- can't use directly — is stored as its actually-workable base id
            -- instead.
            if baseID and baseID ~= id then
                raw.id = baseID
            end
        end
    elseif actionType == Constants.ACTION_TYPE.ITEM then
        raw.name = getItemName(id)
    elseif actionType == Constants.ACTION_TYPE.MACRO then
        local name, icon, body, perCharacter, resolvedMacroID = readMacro(actionID, id, subType)
        raw.id = resolvedMacroID
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
