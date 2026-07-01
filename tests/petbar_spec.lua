---@diagnostic disable: undefined-global
local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/[^/]+%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_full(root)

local API = SlotFiller.PetActionAPI
local PB  = SlotFiller.PetBar
local C   = SlotFiller.Constants

-- ---------------------------------------------------------------------------
-- PetActionAPI
-- ---------------------------------------------------------------------------

runner:test("IsActive reflects IsPetActive", function()
    _G.IsPetActive = function() return true end
    support.assert.isTrue(API.IsActive(), "active when IsPetActive true")
    _G.IsPetActive = function() return false end
    support.assert.isFalse(API.IsActive(), "inactive when IsPetActive false")
    _G.IsPetActive = nil
    support.assert.isFalse(API.IsActive(), "inactive when API missing")
end)

runner:test("SlotIsToken reads the isToken flag from GetPetActionInfo", function()
    _G.GetPetActionInfo = function(id)
        if id == 1 then return "PET_ACTION_ATTACK", nil, true end
        return "Claw", nil, false, true, false, false, 12345
    end
    support.assert.isTrue(API.SlotIsToken(1), "slot 1 is a token")
    support.assert.isFalse(API.SlotIsToken(2), "slot 2 is not a token")
    _G.GetPetActionInfo = nil
end)

runner:test("PickupSpellID returns false when the spell can't be picked up", function()
    _G.PickupPetSpell = function() end
    _G.GetCursorInfo = function() return nil end
    support.assert.isFalse(API.PickupSpellID(99999), "failed pickup returns false")
    _G.PickupPetSpell = nil
    _G.GetCursorInfo = nil
end)

runner:test("PickupSpellID returns true when the cursor picks up the spell", function()
    _G.PickupPetSpell = function() end
    _G.GetCursorInfo = function() return "petaction" end
    support.assert.isTrue(API.PickupSpellID(17253), "successful pickup returns true")
    _G.PickupPetSpell = nil
    _G.GetCursorInfo = nil
end)

-- ---------------------------------------------------------------------------
-- PetBar:Scan
-- ---------------------------------------------------------------------------

runner:test("Scan captures tokens and spells, skipping empty slots", function()
    _G.GetPetActionInfo = function(id)
        if id == 1 then return "PET_ACTION_ATTACK", nil, true end
        if id == 2 then return "Claw", nil, false, true, false, false, 17253 end
        return nil
    end

    local petSlots = PB:Scan()

    _G.GetPetActionInfo = nil

    support.assert.equal(petSlots[1].type,    C.PET_SLOT_TYPE.TOKEN, "slot 1 captured as token")
    support.assert.equal(petSlots[1].token,   "PET_ACTION_ATTACK",   "token name stored")
    support.assert.equal(petSlots[2].type,    C.PET_SLOT_TYPE.SPELL, "slot 2 captured as spell")
    support.assert.equal(petSlots[2].spellID, 17253,                 "spellID stored")
    support.assert.isNil(petSlots[3],                                 "empty slot omitted")
end)

-- ---------------------------------------------------------------------------
-- PetBar:Apply
-- ---------------------------------------------------------------------------

runner:test("Apply does nothing when no pet is active", function()
    _G.IsPetActive = function() return false end
    local cleared = false
    _G.PickupPetAction = function() cleared = true end

    PB:Apply({})

    _G.IsPetActive = nil
    _G.PickupPetAction = nil

    support.assert.isFalse(cleared, "no pet-bar calls made without an active pet")
end)

runner:test("Apply leaves a live token slot untouched even when the profile wants a spell there", function()
    _G.IsPetActive = function() return true end
    _G.GetPetActionInfo = function(id)
        if id == 1 then return "PET_ACTION_ATTACK", nil, true end
        return nil
    end
    local touched = false
    _G.PickupPetAction = function() touched = true end

    PB:Apply({ [1] = { type = C.PET_SLOT_TYPE.SPELL, spellID = 1 } })

    _G.IsPetActive = nil
    _G.GetPetActionInfo = nil
    _G.PickupPetAction = nil

    support.assert.isFalse(touched, "live token slot is never cleared or placed into")
end)

runner:test("Apply clears a non-token slot the profile says should be empty", function()
    _G.IsPetActive = function() return true end
    _G.GetPetActionInfo = function(id)
        if id == 3 then return "Claw", nil, false, true, false, false, 17253 end
        return nil
    end
    local clearedSlots = {}
    _G.PickupPetAction = function(id) clearedSlots[id] = true end

    PB:Apply({})

    _G.IsPetActive = nil
    _G.GetPetActionInfo = nil
    _G.PickupPetAction = nil

    support.assert.isTrue(clearedSlots[3], "non-token slot cleared when profile has no entry")
end)

runner:test("Apply restores a pet spell to its slot", function()
    _G.IsPetActive = function() return true end
    _G.GetPetActionInfo = function() return nil end  -- no token anywhere
    local placedAt = nil
    _G.PickupPetAction = function(id) placedAt = id end
    _G.PickupPetSpell = function() end
    _G.GetCursorInfo = function() return "petaction" end

    PB:Apply({ [4] = { type = C.PET_SLOT_TYPE.SPELL, spellID = 17253 } })

    _G.IsPetActive = nil
    _G.GetPetActionInfo = nil
    _G.PickupPetAction = nil
    _G.PickupPetSpell = nil
    _G.GetCursorInfo = nil

    support.assert.equal(placedAt, 4, "spell placed into slot 4 (last PickupPetAction call)")
end)

os.exit(runner:run())
