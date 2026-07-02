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

-- Regression: since Patch 10.2, GetActionInfo returns the macro's referenced
-- spellID (not the macro slot index) whenever subType == "spell". Passing
-- that spellID straight to GetMacroInfo used to return nil, wiping out the
-- macro's captured name/body.
runner:test("ReadSlot resolves the real macroID by name when subType is \"spell\"", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        -- 96231 here is a spellID (Rebuke), not macro slot 42 — exactly the
        -- Blizzard quirk this test guards against.
        if actionID == 9 then return "macro", 96231, "spell", nil end
        return nil
    end
    _G.GetActionText = function(actionID)
        return actionID == 9 and "MyRebukeMacro" or nil
    end
    _G.GetMacroIndexByName = function(name)
        return name == "MyRebukeMacro" and 42 or nil
    end
    _G.GetMacroInfo = function(id)
        if id == 42 then return "MyRebukeMacro", nil, "/cast Rebuke" end
        return nil
    end
    _G.MAX_ACCOUNT_MACROS = 120

    local slot = S:ReadSlot(9)

    API.GetSlotActionInfo = originalGetInfo
    _G.GetActionText = nil
    _G.GetMacroIndexByName = nil
    _G.GetMacroInfo = nil
    _G.MAX_ACCOUNT_MACROS = nil

    support.assert.equal(slot.type,    "macro",         "macro type normalised")
    support.assert.equal(slot.macroID, 42,               "resolved real macro slot, not the aliased spellID")
    support.assert.equal(slot.name,    "MyRebukeMacro",  "macro name resolved via the real macroID")
    support.assert.equal(slot.body,    "/cast Rebuke",   "macro body resolved via the real macroID")
end)

-- Regression: the aliased spellID can coincidentally land inside the valid
-- 1-150 macro slot range (many core spells have low, Classic-era spellIDs),
-- so GetMacroInfo(<aliased id>) doesn't always fail loudly with nil — it can
-- silently return a completely unrelated macro's real name/body. This is the
-- most dangerous form of the bug: silent data corruption at scan time, with
-- no error to surface it. Resolving by name must never let that substitution
-- happen.
runner:test("ReadSlot never substitutes an unrelated macro that coincidentally shares the aliased spellID", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        -- Spell 5 aliases the macro slot; macro slot 5 is a real, unrelated
        -- macro that must never be substituted in for this button.
        if actionID == 20 then return "macro", 5, "spell", nil end
        return nil
    end
    _G.GetActionText = function(actionID)
        return actionID == 20 and "JudgmentMacro" or nil
    end
    _G.GetMacroIndexByName = function(name)
        return name == "JudgmentMacro" and 47 or nil
    end
    _G.GetMacroInfo = function(id)
        if id == 5 then return "WrongUnrelatedMacro", nil, "/wrong" end
        if id == 47 then return "JudgmentMacro", nil, "/cast Judgment" end
        return nil
    end
    _G.MAX_ACCOUNT_MACROS = 120

    local slot = S:ReadSlot(20)

    API.GetSlotActionInfo = originalGetInfo
    _G.GetActionText = nil
    _G.GetMacroIndexByName = nil
    _G.GetMacroInfo = nil
    _G.MAX_ACCOUNT_MACROS = nil

    support.assert.equal(slot.macroID, 47,             "resolves to the real macro, not the aliased slot-5 collision")
    support.assert.equal(slot.name,    "JudgmentMacro", "captures the real macro's name")
    support.assert.equal(slot.body,    "/cast Judgment", "captures the real macro's body, not the unrelated macro at slot 5")
end)

-- Regression: two distinct macros that both hit the subType == "spell" alias
-- quirk must stay distinguishable from one another (the actual bug reported:
-- multiple different macros collapsed into a single restored macro because
-- GetMacroInfo(<aliased spellID>) returned nil for both).
runner:test("ReadSlot keeps two distinct subType=spell macros distinguishable", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 10 then return "macro", 642,   "spell", nil end
        if actionID == 11 then return "macro", 19750, "spell", nil end
        return nil
    end
    _G.GetActionText = function(actionID)
        if actionID == 10 then return "MacroA" end
        if actionID == 11 then return "MacroB" end
        return nil
    end
    _G.GetMacroIndexByName = function(name)
        if name == "MacroA" then return 121 end
        if name == "MacroB" then return 122 end
        return nil
    end
    _G.GetMacroInfo = function(id)
        if id == 121 then return "MacroA", nil, "/cast Judgment" end
        if id == 122 then return "MacroB", nil, "/cast Avenger's Shield" end
        return nil
    end
    _G.MAX_ACCOUNT_MACROS = 120

    local slotA = S:ReadSlot(10)
    local slotB = S:ReadSlot(11)

    API.GetSlotActionInfo = originalGetInfo
    _G.GetActionText = nil
    _G.GetMacroIndexByName = nil
    _G.GetMacroInfo = nil
    _G.MAX_ACCOUNT_MACROS = nil

    support.assert.equal(slotA.macroID, 121, "first macro resolves to its own slot")
    support.assert.equal(slotB.macroID, 122, "second macro resolves to its own distinct slot")
    support.assert.equal(slotA.name, "MacroA", "first macro keeps its own name")
    support.assert.equal(slotB.name, "MacroB", "second macro keeps its own distinct name")
    support.assert.equal(slotA.body, "/cast Judgment", "first macro keeps its own body")
    support.assert.equal(slotB.body, "/cast Avenger's Shield", "second macro keeps its own distinct body")
end)

-- Regression: the same GetActionInfo quirk also fires for subType == "item"
-- (an item-cast macro), where `id` is documented to return an unrelated,
-- often bogus number (frequently actionID-1) rather than the macro slot.
-- The fix treats any non-nil/non-empty subType as untrustworthy, so this
-- must resolve exactly like the "spell" case.
runner:test("ReadSlot resolves the real macroID by name when subType is \"item\"", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        -- 8 here mimics Blizzard's documented "actionID - 1" bogus id quirk
        -- for item-casting macros, not a real macro slot.
        if actionID == 9 then return "macro", 8, "item", nil end
        return nil
    end
    _G.GetActionText = function(actionID)
        return actionID == 9 and "TrinketMacro" or nil
    end
    _G.GetMacroIndexByName = function(name)
        return name == "TrinketMacro" and 63 or nil
    end
    _G.GetMacroInfo = function(id)
        if id == 8  then return "WrongMacro", nil, "/wrong" end
        if id == 63 then return "TrinketMacro", nil, "/use 13" end
        return nil
    end
    _G.MAX_ACCOUNT_MACROS = 120

    local slot = S:ReadSlot(9)

    API.GetSlotActionInfo = originalGetInfo
    _G.GetActionText = nil
    _G.GetMacroIndexByName = nil
    _G.GetMacroInfo = nil
    _G.MAX_ACCOUNT_MACROS = nil

    support.assert.equal(slot.macroID, 63,            "resolved the real macro slot, not the bogus item-quirk id")
    support.assert.equal(slot.name,    "TrinketMacro", "macro name resolved via the real macroID")
    support.assert.equal(slot.body,    "/use 13",      "macro body resolved via the real macroID, not the id-8 collision")
end)

runner:test("ReadSlot falls back to the native macroID when subType is nil", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 12 then return "macro", 55, nil, nil end
        return nil
    end
    _G.GetActionText = function() return "PlainMacro" end
    _G.GetMacroIndexByName = function() error("must not be called when subType is nil") end
    _G.GetMacroInfo = function(id)
        if id == 55 then return "PlainMacro", nil, "/cast Consecration" end
        return nil
    end
    _G.MAX_ACCOUNT_MACROS = 120

    local slot = S:ReadSlot(12)

    API.GetSlotActionInfo = originalGetInfo
    _G.GetActionText = nil
    _G.GetMacroIndexByName = nil
    _G.GetMacroInfo = nil
    _G.MAX_ACCOUNT_MACROS = nil

    support.assert.equal(slot.macroID, 55, "native macroID trusted when subType never aliases it")
end)

runner:test("ReadSlot leaves macroID nil when a subType=spell macro can't be resolved by name", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 13 then return "macro", 999999, "spell", nil end
        return nil
    end
    _G.GetActionText = function() return nil end
    _G.GetMacroIndexByName = function() return nil end
    _G.GetMacroInfo = function() error("must not be called with an unresolved macroID") end
    _G.MAX_ACCOUNT_MACROS = 120

    local slot = S:ReadSlot(13)

    API.GetSlotActionInfo = originalGetInfo
    _G.GetActionText = nil
    _G.GetMacroIndexByName = nil
    _G.GetMacroInfo = nil
    _G.MAX_ACCOUNT_MACROS = nil

    support.assert.isNil(slot.macroID, "unresolved alias is dropped rather than trusted as a macroID")
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

-- Regression: some zone abilities are themselves overridden while active —
-- e.g. Undermine's G-99 Breakneck vehicle shows override spell 460013 on the
-- action bar, while C_ZoneAbility.GetActiveAbilities() only ever lists its
-- base spell, 1215279 (the id pickup actually requires — see
-- ActionAPI.PickupZoneAbility). Checking zoneAbilitySpellIDs against the raw
-- id alone missed this, so the slot was never tagged isZoneAbility and fell
-- through to the ordinary IsSpellRestorable gate, which silently (and
-- incorrectly) treats a zone-only ability as an off-spec spell and skips
-- restoring it entirely.
runner:test("ReadSlot tags a zone ability by its base id when the action bar shows an override", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 8 then return "spell", 460013, "spell", 0 end
        return nil
    end
    _G.C_Spell = {
        GetSpellName = function() return "G-99 Breakneck" end,
        GetBaseSpell = function(id) return id == 460013 and 1215279 or id end,
    }

    local zoneAbilitySpellIDs = { [1215279] = true }
    local slot = S:ReadSlot(8, zoneAbilitySpellIDs)

    API.GetSlotActionInfo = originalGetInfo
    _G.C_Spell = nil

    support.assert.equal(slot.isZoneAbility, true, "override-displayed zone ability is still tagged")
    support.assert.equal(slot.id, 1215279, "saved id is the ability's base id, which pickup can actually use")
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

runner:test("ReadSlot never applies the talent-override map to an unresolved assistedcombat slot", function()
    -- No C_AssistedCombat stub: capture fails, so the id stays the raw
    -- (non-spellbook) placeholder — remapping it via the override map would
    -- be meaningless, so it must stay skipped in this case.
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

    support.assert.equal(slot.id, 200, "assistedcombat id is never remapped through the talent-override map")
end)

runner:test("ReadSlot captures C_AssistedCombat.GetActionSpell() as the id for an assistedcombat slot", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 9 then return "spell", 200, "assistedcombat", nil end
        return nil
    end
    _G.C_Spell = { GetSpellName = function() return "Templar Strike" end }
    _G.C_AssistedCombat = { GetActionSpell = function() return 555 end }

    local slot = S:ReadSlot(9)

    API.GetSlotActionInfo = originalGetInfo
    _G.C_Spell = nil
    _G.C_AssistedCombat = nil

    support.assert.equal(slot.id, 555, "id is overridden with the live suggested spell")
    support.assert.equal(slot.name, "Templar Strike", "name reflects the captured suggestion, not the raw slot id")
    support.assert.isNil(slot.subType, "subType is cleared once treated as a plain spell")
end)

runner:test("ReadSlot keeps the native id for an assistedcombat slot when C_AssistedCombat is unavailable", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 9 then return "spell", 200, "assistedcombat", nil end
        return nil
    end
    _G.C_Spell = { GetSpellName = function() return "Rotation Spell" end }

    local slot = S:ReadSlot(9)

    API.GetSlotActionInfo = originalGetInfo
    _G.C_Spell = nil

    support.assert.equal(slot.id, 200, "falls back to the native id without C_AssistedCombat")
end)

runner:test("ReadSlot ignores a suggested spell id of 0 and falls back to the native id", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 9 then return "spell", 200, "assistedcombat", nil end
        return nil
    end
    _G.C_Spell = { GetSpellName = function() return "Rotation Spell" end }
    _G.C_AssistedCombat = { GetActionSpell = function() return 0 end }

    local slot = S:ReadSlot(9)

    API.GetSlotActionInfo = originalGetInfo
    _G.C_Spell = nil
    _G.C_AssistedCombat = nil

    support.assert.equal(slot.id, 200, "id 0 is treated as no suggestion, falls back to native id")
end)

runner:test("ReadSlot applies the talent-override map to a successfully captured SBA suggestion", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 9 then return "spell", 200, "assistedcombat", nil end
        return nil
    end
    _G.C_Spell = { GetSpellName = function() return "Overridden Suggestion" end }
    _G.C_AssistedCombat = { GetActionSpell = function() return 555 end }

    local overrideMap = { [555] = 111 }  -- 555 (override) -> 111 (base)
    local slot = S:ReadSlot(9, nil, overrideMap)

    API.GetSlotActionInfo = originalGetInfo
    _G.C_Spell = nil
    _G.C_AssistedCombat = nil

    support.assert.equal(slot.id, 111,
        "the captured suggestion is itself a real spell, so it is normalised to its base id like any other spell")
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

-- End-to-end regression for the Undermine G-99 Breakneck report: a full
-- Scan() must tag and normalise an override-displayed zone ability, not just
-- ReadSlot called in isolation.
runner:test("Scan tags and normalises a vehicle zone-ability override (G-99 Breakneck)", function()
    local originalGetInfo = API.GetSlotActionInfo
    API.GetSlotActionInfo = function(actionID)
        if actionID == 8 then return "spell", 460013, "spell", 0 end
        return nil
    end
    _G.C_Spell = {
        GetSpellName = function() return "G-99 Breakneck" end,
        GetBaseSpell = function(id) return id == 460013 and 1215279 or id end,
    }
    _G.C_ZoneAbility = {
        GetActiveAbilities = function()
            return { { spellID = 1215279 } }
        end,
    }

    local slots = S:Scan()

    API.GetSlotActionInfo = originalGetInfo
    _G.C_Spell = nil
    _G.C_ZoneAbility = nil

    support.assert.isTrue(slots[8].isZoneAbility, "override-displayed vehicle ability is flagged as a zone ability")
    support.assert.equal(slots[8].id, 1215279, "saved as the base id C_ZoneAbility/pickup both recognise")
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
