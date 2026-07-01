local _, SlotFiller = ...

-- Raw WoW API wrappers for the pet action bar (GetPetActionInfo / PickupPetAction
-- / PickupPetSpell). Kept separate from ActionAPI.lua because the pet bar is a
-- distinct WoW API surface with its own slot range and semantics — see
-- Core/PetBar.lua for the scan/restore logic built on top of these wrappers.
SlotFiller.PetActionAPI = {}

function SlotFiller.PetActionAPI.IsActive()
    return IsPetActive ~= nil and IsPetActive() == true
end

function SlotFiller.PetActionAPI.GetSlotInfo(petSlotID)
    if not GetPetActionInfo then
        return nil
    end
    return GetPetActionInfo(petSlotID)
end

function SlotFiller.PetActionAPI.SlotIsToken(petSlotID)
    local _, _, isToken = SlotFiller.PetActionAPI.GetSlotInfo(petSlotID)
    return isToken == true
end

function SlotFiller.PetActionAPI.ClearSlot(petSlotID)
    if not (PickupPetAction and ClearCursor) then
        return
    end
    local name = SlotFiller.PetActionAPI.GetSlotInfo(petSlotID)
    if name then
        PickupPetAction(petSlotID)
        ClearCursor()
    end
end

-- Places whatever is currently on the cursor into petSlotID, discarding
-- whatever the slot held before (PickupPetAction both picks up and places,
-- depending on cursor state, so this is the same call as ClearSlot above —
-- only the caller's intent differs).
function SlotFiller.PetActionAPI.PlaceSlot(petSlotID)
    if PickupPetAction then
        PickupPetAction(petSlotID)
    end
    if ClearCursor then
        ClearCursor()
    end
end

function SlotFiller.PetActionAPI.PickupSpellID(spellID)
    if not (spellID and PickupPetSpell) then
        return false
    end
    PickupPetSpell(spellID)
    local cursorType = GetCursorInfo and GetCursorInfo()
    return cursorType ~= nil and cursorType ~= ""
end
