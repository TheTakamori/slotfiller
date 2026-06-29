local _, SlotFiller = ...

local Constants = SlotFiller.Constants
local ActionAPI = SlotFiller.ActionAPI

SlotFiller.ActionResolver = {}

-- ---------------------------------------------------------------------------
-- Per-type pickup helpers
-- Each returns (picked: bool, errMsg: string|nil).
--   picked = true                 → cursor holds the action; caller places it.
--   picked = false, errMsg = nil  → expected failure (e.g. off-spec spell); leave slot empty silently.
--   picked = false, errMsg = str  → unexpected failure; caller records errMsg as a restore error.
-- ---------------------------------------------------------------------------

local function pickupSpell(slot, actionID, spellCache)
    -- Zone abilities: hidden from the spellbook; skip IsSpellRestorable check and go
    -- straight to the zone-ability pickup path.  Any active zone ability can be placed
    -- here; WoW will dynamically display the correct ability for the current zone.
    if slot.isZoneAbility then
        if ActionAPI.PickupZoneAbility(slot.id) then
            return true, nil
        end
        local T = SlotFiller.Text
        return false, string.format(T.RESTORE_ZONE_ABILITY_FAILED, actionID)
    end

    -- Pre-validate: if the spell is not known for the current class/spec, skip silently
    -- rather than emitting an error.  This is the expected outcome when loading a
    -- profile that was saved on a different class or specialization.
    if not ActionAPI.IsSpellRestorable(slot.id) then
        return false, nil
    end

    -- Prefer spellbook-slot pickup (most reliable for proc abilities, talent overrides).
    local picked = false
    if slot.id and spellCache[slot.id] then
        picked = ActionAPI.PickupSpellBookIndex(spellCache[slot.id])
    end
    if not picked and slot.name and spellCache[slot.name] then
        picked = ActionAPI.PickupSpellBookIndex(spellCache[slot.name])
    end
    if not picked and slot.name and spellCache[string.lower(slot.name)] then
        picked = ActionAPI.PickupSpellBookIndex(spellCache[string.lower(slot.name)])
    end
    -- Direct pickup by spell ID as final fallback.
    if not picked and slot.id then
        picked = ActionAPI.PickupSpellID(slot.id)
    end
    -- Silently drop if all paths failed; IsSpellRestorable returning true but pickup
    -- failing is an edge case (proc / passive spells) that does not warrant an error.
    return picked, nil
end

local function pickupItem(slot, actionID)
    if not ActionAPI.PickupItemID(slot.id) then
        return false, string.format(
            "Unable to restore item %s to slot %d.",
            slot.name or tostring(slot.id), actionID)
    end
    return true, nil
end

local function pickupMacro(slot, actionID, caches)
    -- FindMacroID is defined on Restorer (loaded after ActionResolver).  The forward
    -- reference is safe because this function is called at runtime, not load time.
    local macroID = SlotFiller.Restorer:FindMacroID(
        slot, caches.macroBody, caches.macroName, caches.macroID)
    if not macroID or not ActionAPI.PickupMacroID(macroID) then
        return false, string.format(
            "Unable to restore macro %s to slot %d.",
            slot.name or slot.body or "?", actionID)
    end
    return true, nil
end

local function pickupFlyout(slot, actionID, flyoutCache)
    if not ActionAPI.PickupFlyoutID(slot.id, flyoutCache) then
        return false, string.format(
            "Unable to restore flyout %s to slot %d.",
            slot.name or tostring(slot.id), actionID)
    end
    return true, nil
end

local function pickupMount(slot, actionID)
    if not ActionAPI.PickupMountByID(slot.id) then
        return false, string.format(
            "Unable to restore mount (id=%s) to slot %d.",
            tostring(slot.id), actionID)
    end
    return true, nil
end

local function pickupBattlePet(slot, actionID)
    if not ActionAPI.PickupBattlePet(slot.id) then
        return false, string.format(
            "Unable to restore battle pet %s to slot %d. The pet may not be in your collection.",
            slot.name or tostring(slot.id), actionID)
    end
    return true, nil
end

-- Shared helper used by both pickupCompanion and pickupUnknown.
local function tryPickupCompanion(subType, id)
    if PickupCompanion and subType then
        pcall(PickupCompanion, subType, id)
        local ct = GetCursorInfo and GetCursorInfo()
        if ct == "companion" or ct == "mount" then
            return true
        end
    end
    -- Fallback: most Midnight companion mounts surface through the mount journal.
    return id ~= nil and ActionAPI.PickupMountBySpellID(id)
end

local function pickupCompanion(slot, actionID)
    if not tryPickupCompanion(slot.subType, slot.id) then
        return false, string.format(
            "Unable to restore companion (id=%s, sub=%s) to slot %d.",
            tostring(slot.id), tostring(slot.subType), actionID)
    end
    return true, nil
end

local function pickupEquipmentSet(slot, actionID)
    if not ActionAPI.PickupEquipmentSetName(slot.id) then
        return false, string.format(
            "Unable to restore equipment set %s to slot %d.",
            tostring(slot.id), actionID)
    end
    return true, nil
end

local function pickupUnknown(slot, actionID)
    local rawType = slot.rawType
    local picked = false
    -- Attempt common raw types that may arrive here from future WoW patches.
    if rawType == "companion" then
        picked = tryPickupCompanion(slot.subType, slot.id)
    elseif rawType == "summonmount" then
        picked = ActionAPI.PickupMountByID(slot.id)
    end
    if not picked then
        return false, string.format(
            "Cannot restore action type '%s' in slot %d. Use /sfill scan for details.",
            tostring(rawType), actionID)
    end
    return true, nil
end

-- ---------------------------------------------------------------------------
-- Public dispatcher
-- ---------------------------------------------------------------------------

-- Attempts to place the action described by slot onto the cursor.
--
-- slot      - normalised slot table from the saved profile.
-- actionID  - destination action bar slot number (used only for error messages).
-- caches    - table built by Restorer.ApplyProfile:
--               .spell    = spellbook ID/name → bookIndex
--               .flyout   = flyoutID → bookIndex
--               .macroBody, .macroName, .macroID = macro lookup tables
--
-- Returns (picked, errMsg):
--   picked = true                 → cursor holds the action.
--   picked = false, errMsg = nil  → expected/silent failure; leave slot empty.
--   picked = false, errMsg = str  → unexpected failure; caller logs the error.
function SlotFiller.ActionResolver.PickupToCursor(slot, actionID, caches)
    local t = slot.type

    if t == Constants.ACTION_TYPE.SPELL then
        return pickupSpell(slot, actionID, caches.spell)
    elseif t == Constants.ACTION_TYPE.ITEM then
        return pickupItem(slot, actionID)
    elseif t == Constants.ACTION_TYPE.MACRO then
        return pickupMacro(slot, actionID, caches)
    elseif t == Constants.ACTION_TYPE.FLYOUT then
        return pickupFlyout(slot, actionID, caches.flyout)
    elseif t == Constants.ACTION_TYPE.SUMMONMOUNT then
        return pickupMount(slot, actionID)
    elseif t == Constants.ACTION_TYPE.SUMMONPET then
        return pickupBattlePet(slot, actionID)
    elseif t == Constants.ACTION_TYPE.COMPANION then
        return pickupCompanion(slot, actionID)
    elseif t == Constants.ACTION_TYPE.EQUIPMENTSET then
        return pickupEquipmentSet(slot, actionID)
    elseif t == Constants.ACTION_TYPE.UNKNOWN then
        return pickupUnknown(slot, actionID)
    end

    return false, string.format(
        "Cannot restore unrecognised action type '%s' in slot %d. Use /sfill scan for details.",
        tostring(t), actionID)
end
