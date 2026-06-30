---@diagnostic disable: undefined-global
local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/[^/]+%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_full(root)

local S = SlotFiller.Scanner
local C = SlotFiller.Constants
local API = SlotFiller.ActionAPI

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

runner:test("ReadSlot tags zone abilities when zoneAbilities list is provided", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 10 then return "spell", 161676, "spell", 0 end
        return nil
    end
    _G.C_Spell = { GetSpellName = function() return "Call to Arms" end }

    local zoneAbilities = { { spellID = 161676 } }
    local slot = S:ReadSlot(10, zoneAbilities)

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

    local zoneAbilities = { { spellID = 161676 } }
    local slot = S:ReadSlot(10, zoneAbilities)

    API.GetSlotActionInfo = originalGetInfo
    _G.C_Spell = nil

    support.assert.isNil(slot.isZoneAbility, "non-matching spell not tagged as zone ability")
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

os.exit(runner:run())
