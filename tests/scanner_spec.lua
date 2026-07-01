---@diagnostic disable: undefined-global
local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/[^/]+%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_full(root)

local S = SlotFiller.Scanner
local C = SlotFiller.Constants
local API = SlotFiller.ActionAPI
local BookAPI = SlotFiller.SpellBookAPI

-- ---------------------------------------------------------------------------
-- ReadSlot — empty and occupied slots
-- ---------------------------------------------------------------------------

runner:test("ReadSlot returns nil for an empty action slot", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function() return nil end

    local slot = S:ReadSlot(1)

    API.GetSlotActionInfo = originalGetInfo

    support.assert.isNil(slot, "empty slot returns nil")
end)

runner:test("ReadSlot returns nil when actionType is empty string", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function() return "", nil, nil, nil end

    local slot = S:ReadSlot(1)

    API.GetSlotActionInfo = originalGetInfo

    support.assert.isNil(slot, "empty string type treated as empty slot")
end)

runner:test("ReadSlot normalises a spell slot", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 5 then return "spell", 133, "spell", 0 end
        return nil
    end
    _G.C_Spell = { GetSpellName = function(id) return id == 133 and "Fireball" or nil end }

    local slot = S:ReadSlot(5)

    API.GetSlotActionInfo = originalGetInfo
    _G.C_Spell = nil

    support.assert.equal(slot.type, "spell",    "spell type normalised")
    support.assert.equal(slot.id,   133,         "spell id stored")
    support.assert.equal(slot.name, "Fireball",  "spell name resolved")
end)

runner:test("ReadSlot normalises a macro slot", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 3 then return "macro", 7, nil, nil end
        return nil
    end
    _G.GetMacroInfo = function(id)
        if id == 7 then return "MyMacro", nil, "/cast Fireball" end
        return nil
    end
    _G.MAX_ACCOUNT_MACROS = 120

    local slot = S:ReadSlot(3)

    API.GetSlotActionInfo = originalGetInfo
    _G.GetMacroInfo = nil
    _G.MAX_ACCOUNT_MACROS = nil

    support.assert.equal(slot.type,    "macro",   "macro type normalised")
    support.assert.equal(slot.macroID, 7,          "macroID stored")
    support.assert.equal(slot.name,    "MyMacro",  "macro name stored")
end)

runner:test("ReadSlot skips equipmentset with nil or empty id", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function()
        return "equipmentset", nil, nil, nil
    end

    local slot = S:ReadSlot(1)

    API.GetSlotActionInfo = originalGetInfo

    support.assert.isNil(slot, "equipmentset with nil id returns nil")
end)

runner:test("ReadSlot tags zone abilities when zoneAbilitySpellIDs set is provided", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 10 then return "spell", 161676, "spell", 0 end
        return nil
    end
    _G.C_Spell = { GetSpellName = function() return "Call to Arms" end }

    local zoneAbilitySpellIDs = { [161676] = true }
    local slot = S:ReadSlot(10, zoneAbilitySpellIDs)

    API.GetSlotActionInfo = originalGetInfo
    _G.C_Spell = nil

    support.assert.equal(slot.isZoneAbility, true, "zone ability flag set when ID matches")
end)

runner:test("ReadSlot does not tag spell as zone ability when IDs differ", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 10 then return "spell", 9999, "spell", 0 end
        return nil
    end
    _G.C_Spell = { GetSpellName = function() return "Some Spell" end }

    local zoneAbilitySpellIDs = { [161676] = true }
    local slot = S:ReadSlot(10, zoneAbilitySpellIDs)

    API.GetSlotActionInfo = originalGetInfo
    _G.C_Spell = nil

    support.assert.isNil(slot.isZoneAbility, "non-matching spell not tagged as zone ability")
end)

runner:test("ReadSlot normalises an outfit slot", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 6 then return "outfit", 42, nil, nil end
        return nil
    end
    _G.C_TransmogOutfitInfo = {
        GetOutfitInfo = function(id) return id == 42 and { name = "Tank Set" } or nil end,
    }

    local slot = S:ReadSlot(6)

    API.GetSlotActionInfo = originalGetInfo
    _G.C_TransmogOutfitInfo = nil

    support.assert.equal(slot.type, "outfit",  "outfit type normalised")
    support.assert.equal(slot.id,   42,        "outfit id stored")
    support.assert.equal(slot.name, "Tank Set", "outfit name resolved")
end)

-- ---------------------------------------------------------------------------
-- ReadSlot — spell override normalisation
-- ---------------------------------------------------------------------------

runner:test("ReadSlot rewrites an overridden spell back to its base ID", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 8 then return "spell", 200, "spell", 0 end
        return nil
    end
    _G.C_Spell = { GetSpellName = function() return "Override Spell" end }

    local overrideMap = { [200] = 100 }  -- 200 (override) -> 100 (base)
    local slot = S:ReadSlot(8, nil, overrideMap)

    API.GetSlotActionInfo = originalGetInfo
    _G.C_Spell = nil

    support.assert.equal(slot.id, 100, "saved id is the base spell, not the override")
end)

runner:test("ReadSlot leaves an SBA (assistedcombat) slot's id untouched", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 9 then return "spell", 200, "assistedcombat", nil end
        return nil
    end
    _G.C_Spell = { GetSpellName = function() return "Rotation Spell" end }

    local overrideMap = { [200] = 100 }
    local slot = S:ReadSlot(9, nil, overrideMap)

    API.GetSlotActionInfo = originalGetInfo
    _G.C_Spell = nil

    support.assert.equal(slot.id, 200, "assistedcombat id is never remapped")
end)

runner:test("ReadSlot leaves a spell id untouched when no override map is given", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 11 then return "spell", 200, "spell", 0 end
        return nil
    end
    _G.C_Spell = { GetSpellName = function() return "Plain Spell" end }

    local slot = S:ReadSlot(11)

    API.GetSlotActionInfo = originalGetInfo
    _G.C_Spell = nil

    support.assert.equal(slot.id, 200, "id unchanged without an override map")
end)

-- ---------------------------------------------------------------------------
-- Scan — zone ability lookup-set construction
-- ---------------------------------------------------------------------------

runner:test("Scan builds a zoneAbility lookup set from C_ZoneAbility and tags matching spells", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 7 then return "spell", 161676, "spell", 0 end
        return nil
    end
    _G.C_Spell = { GetSpellName = function() return "Garrison Banner" end }
    _G.C_ZoneAbility = {
        GetActiveAbilities = function()
            return { { spellID = 161676 }, { spellID = 999999 } }
        end,
    }

    local slots = S:Scan()

    API.GetSlotActionInfo = originalGetInfo
    _G.C_Spell = nil
    _G.C_ZoneAbility = nil

    support.assert.isTrue(slots[7].isZoneAbility, "slot 7 spell ID matches an active zone ability")
end)

runner:test("Scan does not flag a spell absent from the active zone abilities", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 7 then return "spell", 42, "spell", 0 end
        return nil
    end
    _G.C_Spell = { GetSpellName = function() return "Ordinary Spell" end }
    _G.C_ZoneAbility = {
        GetActiveAbilities = function()
            return { { spellID = 161676 } }
        end,
    }

    local slots = S:Scan()

    API.GetSlotActionInfo = originalGetInfo
    _G.C_Spell = nil
    _G.C_ZoneAbility = nil

    support.assert.isNil(slots[7].isZoneAbility, "spell not in the active-abilities list is not flagged")
end)

-- ---------------------------------------------------------------------------
-- Scan — full bar
-- ---------------------------------------------------------------------------

runner:test("Scan returns only occupied slots indexed by actionID", function()
    local fakeSlots = {
        [1] = { "spell", 133, "spell", 0 },
        [5] = { "item",  208704, nil, nil },
    }
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        local s = fakeSlots[actionID]
        return s and s[1], s and s[2], s and s[3], s and s[4]
    end
    _G.C_Spell = { GetSpellName = function(id) return id == 133 and "Fireball" or nil end }
    _G.C_Item  = { GetItemNameByID = function(id) return id == 208704 and "Hearthstone" or nil end }

    local slots = S:Scan()

    API.GetSlotActionInfo = originalGetInfo
    _G.C_Spell = nil
    _G.C_Item  = nil

    support.assert.equal(slots[1].type, "spell", "slot 1 is spell")
    support.assert.equal(slots[5].type, "item",  "slot 5 is item")
    support.assert.isNil(slots[2],               "slot 2 empty")
end)

runner:test("Scan builds and applies the spell override map to spell slots", function()
    local originalBuildMap = BookAPI.BuildSpellOverrideMap
    BookAPI.BuildSpellOverrideMap = function() return { [200] = 100 } end

    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 3 then return "spell", 200, "spell", 0 end
        return nil
    end
    _G.C_Spell = { GetSpellName = function() return "Override Spell" end }

    local slots = S:Scan()

    BookAPI.BuildSpellOverrideMap = originalBuildMap
    API.GetSlotActionInfo = originalGetInfo
    _G.C_Spell = nil

    support.assert.equal(slots[3].id, 100, "Scan() normalises slot 3 to the base spell id")
end)

runner:test("Scan fetches zone abilities once for all slots", function()
    local callCount = 0
    _G.C_ZoneAbility = {
        GetActiveAbilities = function()
            callCount = callCount + 1
            return {}
        end,
    }

    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function() return nil end

    S:Scan()

    API.GetSlotActionInfo = originalGetInfo
    _G.C_ZoneAbility = nil

    support.assert.equal(callCount, 1, "GetActiveAbilities called exactly once per Scan()")
end)

runner:test("CaptureCurrentProfile wraps Scan result in a profile table", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 2 then return "spell", 133, nil, nil end
        return nil
    end
    _G.C_Spell = { GetSpellName = function() return "Fireball" end }

    local profile = S:CaptureCurrentProfile()

    API.GetSlotActionInfo = originalGetInfo
    _G.C_Spell = nil

    support.assert.equal(type(profile),         "table", "returns a table")
    support.assert.equal(profile.slots[2].type, "spell", "slot 2 captured")
    support.assert.isTrue(profile.savedAt ~= nil,        "savedAt field present")
end)

-- ---------------------------------------------------------------------------
-- CaptureCurrentProfile — petSlots / clickBindings attachment
-- ---------------------------------------------------------------------------

runner:test("CaptureCurrentProfile omits petSlots when no pet is active", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function() return nil end
    _G.IsPetActive = function() return false end

    local profile = S:CaptureCurrentProfile()

    API.GetSlotActionInfo = originalGetInfo
    _G.IsPetActive = nil

    support.assert.isNil(profile.petSlots, "no petSlots captured without an active pet")
end)

runner:test("CaptureCurrentProfile attaches petSlots when a pet is active", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function() return nil end
    _G.IsPetActive = function() return true end
    _G.GetPetActionInfo = function(petSlotID)
        if petSlotID == 1 then return "PET_ACTION_ATTACK", nil, true end
        return nil
    end

    local profile = S:CaptureCurrentProfile()

    API.GetSlotActionInfo = originalGetInfo
    _G.IsPetActive = nil
    _G.GetPetActionInfo = nil

    support.assert.equal(profile.petSlots[1].type,  C.PET_SLOT_TYPE.TOKEN, "pet slot 1 captured as token")
    support.assert.equal(profile.petSlots[1].token, "PET_ACTION_ATTACK",   "token name captured")
end)

runner:test("CaptureCurrentProfile omits clickBindings when unsupported", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function() return nil end

    local profile = S:CaptureCurrentProfile()

    API.GetSlotActionInfo = originalGetInfo

    support.assert.isNil(profile.clickBindings, "no clickBindings without C_ClickBindings support")
end)

-- ---------------------------------------------------------------------------
-- FormatSlotDump
-- ---------------------------------------------------------------------------

runner:test("FormatSlotDump returns one formatted line per occupied slot and the count", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 1 then return "spell", 133, "spell", 0 end
        if actionID == 2 then return "item", 456, nil, nil end
        return nil
    end

    local lines, count = S:FormatSlotDump()

    API.GetSlotActionInfo = originalGetInfo

    support.assert.equal(count, 2, "two occupied slots counted")
    support.assert.equal(#lines, 2, "two lines produced")
    support.assert.isTrue(lines[1]:find("%[1%]") ~= nil, "first line names slot 1")
    support.assert.isTrue(lines[1]:find("id=133") ~= nil, "first line includes the action id")
    support.assert.isTrue(lines[2]:find("%[2%]") ~= nil, "second line names slot 2")
end)

runner:test("FormatSlotDump returns no lines when every slot is empty", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function() return nil end

    local lines, count = S:FormatSlotDump()

    API.GetSlotActionInfo = originalGetInfo

    support.assert.equal(count, 0,  "no occupied slots")
    support.assert.equal(#lines, 0, "no lines produced")
end)

os.exit(runner:run())
