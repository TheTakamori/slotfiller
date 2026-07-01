local _, SlotFiller = ...

local Constants = SlotFiller.Constants
local PetAPI = SlotFiller.PetActionAPI

-- Scan and restore logic for the pet action bar. Pet command tokens (Attack,
-- Follow, Stay, Aggressive, Defensive, Passive, Assist) are captured for
-- awareness but never relocated on restore: moving one means picking it up
-- from its current slot, and if that slot has already changed since the
-- profile was saved (or since an earlier slot in the same restore pass moved
-- something), the token can be lost with no way to recover it. Restore only
-- ever clears or places pet *spells*; any live token slot is left untouched
-- regardless of what the profile says, which is the same trade-off this addon
-- already makes for the Rotation Assistant (SBA) button.
SlotFiller.PetBar = {}

function SlotFiller.PetBar:Scan()
    local petSlots = {}
    for petSlotID = Constants.PET_SLOT_MIN, Constants.PET_SLOT_MAX do
        local name, _, isToken, _, _, _, spellID = PetAPI.GetSlotInfo(petSlotID)
        if name then
            local raw = isToken and { token = name } or { spellID = spellID }
            petSlots[petSlotID] = SlotFiller.Normalizer.FromRawPetSlot(raw)
        end
    end
    return SlotFiller.Normalizer.BuildPetProfile(petSlots)
end

function SlotFiller.PetBar:Apply(petSlots)
    if not PetAPI.IsActive() then
        return
    end

    for petSlotID = Constants.PET_SLOT_MIN, Constants.PET_SLOT_MAX do
        if not PetAPI.SlotIsToken(petSlotID) then
            local desired = petSlots[petSlotID]
            if not desired then
                PetAPI.ClearSlot(petSlotID)
            elseif desired.type == Constants.PET_SLOT_TYPE.SPELL then
                PetAPI.ClearSlot(petSlotID)
                if PetAPI.PickupSpellID(desired.spellID) then
                    PetAPI.PlaceSlot(petSlotID)
                elseif ClearCursor then
                    ClearCursor()
                end
            end
            -- desired.type == TOKEN: intentionally left untouched, see module note.
        end
    end
end
