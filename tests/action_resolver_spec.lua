---@diagnostic disable: undefined-global
local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/[^/]+%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_full(root)

local R       = SlotFiller.ActionResolver
local C       = SlotFiller.Constants
local API     = SlotFiller.ActionAPI
local BookAPI = SlotFiller.SpellBookAPI
local T       = SlotFiller.Text

local emptyCaches = support.empty_restore_caches

-- ---------------------------------------------------------------------------
-- ActionAPI.PickupZoneAbility — override-id matching
-- ---------------------------------------------------------------------------

-- Regression: some zone abilities are overridden while active (e.g.
-- Undermine's G-99 Breakneck: override 460013 is what's saved/shown, but
-- C_ZoneAbility.GetActiveAbilities() only ever reports the base id,
-- 1215279). An exact ability.spellID == targetSpellID check alone would
-- never match a still-un-normalised (older) saved override id, so a
-- GetBaseSpell-based fallback match is required too.
-- A second, unrelated active ability is listed first here specifically so
-- Pass 2's "grab whichever ability is active" fallback can't accidentally
-- mask a Pass-1 matching bug the way it would with only one ability active:
-- if Pass 1's override matching didn't work, Pass 2 would silently pick up
-- the wrong (unrelated) ability instead of failing loudly.
runner:test("PickupZoneAbility matches an un-normalised override id via C_Spell.GetBaseSpell", function()
    _G.C_ZoneAbility = {
        GetActiveAbilities = function()
            return { { spellID = 999999 }, { spellID = 1215279 } }
        end,
    }
    _G.C_Spell = {
        GetBaseSpell = function(id) return id == 460013 and 1215279 or id end,
    }
    local originalPickupSpellID = API.PickupSpellID
    local pickedID = nil
    API.PickupSpellID = function(id) pickedID = id; return true end

    local picked = API.PickupZoneAbility(460013)

    _G.C_ZoneAbility = nil
    _G.C_Spell = nil
    API.PickupSpellID = originalPickupSpellID

    support.assert.isTrue(picked, "override id resolves to the active zone ability")
    support.assert.equal(pickedID, 1215279,
        "picked up the correct ability via its base id, not the unrelated one listed first")
end)

runner:test("PickupZoneAbility matches directly when the saved id is already the base id", function()
    _G.C_ZoneAbility = {
        GetActiveAbilities = function()
            return { { spellID = 1215279 } }
        end,
    }
    _G.C_Spell = { GetBaseSpell = function() error("must not be called when the exact id already matches") end }
    local pickedID = nil
    local originalPickupSpellID = API.PickupSpellID
    API.PickupSpellID = function(id) pickedID = id; return true end

    local picked = API.PickupZoneAbility(1215279)

    _G.C_ZoneAbility = nil
    _G.C_Spell = nil
    API.PickupSpellID = originalPickupSpellID

    support.assert.isTrue(picked, "already-normalised id matches directly")
    support.assert.equal(pickedID, 1215279, "picked up via the exact matched id")
end)

-- ---------------------------------------------------------------------------
-- Spell dispatch
-- ---------------------------------------------------------------------------

runner:test("spell slot: succeeds via spellbook index when ID is in cache", function()
    local originalRestorable = BookAPI.IsSpellRestorable
    local originalPickupIdx  = API.PickupSpellBookIndex
    BookAPI.IsSpellRestorable = function() return true end
    API.PickupSpellBookIndex = function() return true end

    local caches = emptyCaches()
    caches.spell[133] = 5
    local picked, err = R.PickupToCursor({ type = C.ACTION_TYPE.SPELL, id = 133 }, 1, caches)

    BookAPI.IsSpellRestorable = originalRestorable
    API.PickupSpellBookIndex  = originalPickupIdx

    support.assert.equal(picked, true, "spell picked up via ID cache")
    support.assert.isNil(err, "no error on success")
end)

runner:test("spell slot: silently skipped when not restorable (off-spec)", function()
    local originalRestorable = BookAPI.IsSpellRestorable
    BookAPI.IsSpellRestorable = function() return false end

    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.SPELL, id = 99999 }, 1, emptyCaches())

    BookAPI.IsSpellRestorable = originalRestorable

    support.assert.equal(picked, false, "not picked")
    support.assert.isNil(err, "no error — silent skip")
end)

runner:test("spell slot: error (not silent) when restorable but every pickup path fails", function()
    local originalRestorable = BookAPI.IsSpellRestorable
    local originalPickupID   = API.PickupSpellID
    BookAPI.IsSpellRestorable = function() return true end
    API.PickupSpellID = function() return false end

    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.SPELL, id = 42, name = "Stubborn Spell" }, 3, emptyCaches())

    BookAPI.IsSpellRestorable = originalRestorable
    API.PickupSpellID = originalPickupID

    support.assert.equal(picked, false, "not picked")
    support.assert.isTrue(err ~= nil, "unexpected pickup failure is reported, not silently swallowed")
    support.assert.isTrue(err:find("slot 3") ~= nil, "error names the slot")
    support.assert.isTrue(err:find("Stubborn Spell") ~= nil, "error names the spell")
end)

-- ---------------------------------------------------------------------------
-- Zone ability spell path
-- ---------------------------------------------------------------------------

runner:test("zone-ability spell: succeeds via PickupZoneAbility, bypassing IsSpellRestorable", function()
    local originalRestorable = BookAPI.IsSpellRestorable
    local originalZoneAbility = API.PickupZoneAbility
    BookAPI.IsSpellRestorable = function() error("must not be called for zone abilities") end
    API.PickupZoneAbility = function() return true end

    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.SPELL, id = 161676, isZoneAbility = true }, 6, emptyCaches())

    BookAPI.IsSpellRestorable = originalRestorable
    API.PickupZoneAbility = originalZoneAbility

    support.assert.equal(picked, true, "zone ability picked up")
    support.assert.isNil(err, "no error on success")
end)

runner:test("zone-ability spell: error when PickupZoneAbility fails", function()
    local originalZoneAbility = API.PickupZoneAbility
    API.PickupZoneAbility = function() return false end

    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.SPELL, id = 161676, isZoneAbility = true }, 6, emptyCaches())

    API.PickupZoneAbility = originalZoneAbility

    support.assert.equal(picked, false, "not picked")
    support.assert.isTrue(err ~= nil, "error returned (unexpected failure, not silent)")
    support.assert.isTrue(err:find("slot 6") ~= nil, "error names the slot")
end)

-- ---------------------------------------------------------------------------
-- Macro dispatch
-- ---------------------------------------------------------------------------

runner:test("macro slot: succeeds by matching an existing macro by name", function()
    local originalPickupMacro = API.PickupMacroID
    API.PickupMacroID = function() return true end

    local caches = emptyCaches()
    caches.macroName["Heal"] = 7

    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.MACRO, name = "Heal", body = "/cast Heal" }, 2, caches)

    API.PickupMacroID = originalPickupMacro

    support.assert.equal(picked, true, "macro picked up via existing macro match")
    support.assert.isNil(err, "no error on success")
end)

runner:test("macro slot: creates a character macro on no match when perCharacter", function()
    local originalCreate = API.CreateCharacterMacro
    local originalPickupMacro = API.PickupMacroID
    API.CreateCharacterMacro = function() return 555 end
    API.PickupMacroID = function() return true end

    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.MACRO, name = "NewMacro", body = "/cast X", perCharacter = true },
        2, emptyCaches())

    API.CreateCharacterMacro = originalCreate
    API.PickupMacroID = originalPickupMacro

    support.assert.equal(picked, true, "newly created macro picked up")
    support.assert.isNil(err, "no error on success")
end)

runner:test("macro slot: error when the character macro limit is full", function()
    local originalCreate = API.CreateCharacterMacro
    API.CreateCharacterMacro = function() return nil, "limit" end

    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.MACRO, name = "Overflow", body = "/cast X", perCharacter = true },
        4, emptyCaches())

    API.CreateCharacterMacro = originalCreate

    support.assert.equal(picked, false, "not picked")
    support.assert.isTrue(err ~= nil, "error returned")
    support.assert.isTrue(err:find("Overflow") ~= nil, "macro name in error")
    support.assert.isTrue(err:find("slot 4") ~= nil, "slot in error")
end)

runner:test("macro slot: not_found error for a missing global macro (not perCharacter)", function()
    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.MACRO, name = "Ghost", body = "/cast Gone", perCharacter = false },
        8, emptyCaches())

    support.assert.equal(picked, false, "not picked")
    support.assert.isTrue(err ~= nil, "error returned")
    support.assert.isTrue(err:find("Ghost") ~= nil, "macro name in error")
end)

runner:test("macro slot: error when macro is resolved but ActionAPI.PickupMacroID itself fails", function()
    local originalPickupMacro = API.PickupMacroID
    API.PickupMacroID = function() return false end

    local caches = emptyCaches()
    caches.macroName["Heal"] = 7

    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.MACRO, name = "Heal", body = "/cast Heal" }, 9, caches)

    API.PickupMacroID = originalPickupMacro

    support.assert.equal(picked, false, "not picked")
    support.assert.isTrue(err ~= nil, "error returned even though macro was resolved")
    support.assert.isTrue(err:find("slot 9") ~= nil, "slot in error")
end)

-- ---------------------------------------------------------------------------
-- Item dispatch
-- ---------------------------------------------------------------------------

runner:test("item slot: succeeds when PickupItemID returns true", function()
    local originalPickup = API.PickupItemID
    API.PickupItemID = function() return true end

    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.ITEM, id = 208704, name = "Hearthstone" }, 3, emptyCaches())

    API.PickupItemID = originalPickup

    support.assert.equal(picked, true, "item picked")
    support.assert.isNil(err, "no error")
end)

runner:test("item slot: error when PickupItemID fails", function()
    local originalPickup = API.PickupItemID
    API.PickupItemID = function() return false end

    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.ITEM, id = 99, name = "Ghost Item" }, 5, emptyCaches())

    API.PickupItemID = originalPickup

    support.assert.equal(picked, false, "not picked")
    support.assert.isTrue(err ~= nil, "error message returned")
    support.assert.isTrue(err:find("slot 5") ~= nil, "error names the slot")
    support.assert.isTrue(err:find("Ghost Item") ~= nil, "error names the item")
end)

-- ---------------------------------------------------------------------------
-- Flyout dispatch
-- ---------------------------------------------------------------------------

runner:test("flyout slot: error when PickupFlyoutID fails", function()
    local originalPickup = API.PickupFlyoutID
    API.PickupFlyoutID = function() return false end

    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.FLYOUT, id = 1, name = "Portals" }, 7, emptyCaches())

    API.PickupFlyoutID = originalPickup

    support.assert.equal(picked, false, "not picked")
    support.assert.isTrue(err ~= nil, "error returned")
    support.assert.isTrue(err:find("slot 7") ~= nil, "slot in error")
end)

-- ---------------------------------------------------------------------------
-- Summon mount dispatch
-- ---------------------------------------------------------------------------

runner:test("summonmount slot: error when PickupMountByID fails", function()
    local originalPickup = API.PickupMountByID
    API.PickupMountByID = function() return false end

    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.SUMMONMOUNT, id = 12345 }, 9, emptyCaches())

    API.PickupMountByID = originalPickup

    support.assert.equal(picked, false, "not picked")
    support.assert.isTrue(err ~= nil, "error returned")
    support.assert.isTrue(err:find("slot 9") ~= nil, "slot in error")
end)

-- ---------------------------------------------------------------------------
-- Battle pet dispatch
-- ---------------------------------------------------------------------------

runner:test("summonpet slot: succeeds when PickupBattlePet returns true", function()
    local originalPickup = API.PickupBattlePet
    API.PickupBattlePet = function() return true end

    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.SUMMONPET, id = "BattlePet-0-AAA", name = "Wee Stinker" },
        11, emptyCaches())

    API.PickupBattlePet = originalPickup

    support.assert.equal(picked, true, "pet picked")
    support.assert.isNil(err, "no error")
end)

runner:test("summonpet slot: error when PickupBattlePet fails", function()
    local originalPickup = API.PickupBattlePet
    API.PickupBattlePet = function() return false end

    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.SUMMONPET, id = "BattlePet-0-DEAD", name = "Gone" },
        12, emptyCaches())

    API.PickupBattlePet = originalPickup

    support.assert.equal(picked, false, "not picked")
    support.assert.isTrue(err ~= nil, "error returned")
    support.assert.isTrue(err:find("slot 12") ~= nil, "slot in error")
    support.assert.isTrue(err:find("collection") ~= nil, "collection hint in error")
end)

-- ---------------------------------------------------------------------------
-- Equipment set dispatch
-- ---------------------------------------------------------------------------

runner:test("equipmentset slot: error when PickupEquipmentSetName fails", function()
    local originalPickup = API.PickupEquipmentSetName
    API.PickupEquipmentSetName = function() return false end

    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.EQUIPMENTSET, id = "Tank Gear" }, 14, emptyCaches())

    API.PickupEquipmentSetName = originalPickup

    support.assert.equal(picked, false, "not picked")
    support.assert.isTrue(err ~= nil, "error returned")
    support.assert.isTrue(err:find("slot 14") ~= nil, "slot in error")
end)

-- ---------------------------------------------------------------------------
-- Outfit dispatch
-- ---------------------------------------------------------------------------

runner:test("outfit slot: succeeds when PickupOutfitID returns true", function()
    local originalPickup = API.PickupOutfitID
    API.PickupOutfitID = function() return true end

    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.OUTFIT, id = 42, name = "Tank Set" }, 13, emptyCaches())

    API.PickupOutfitID = originalPickup

    support.assert.equal(picked, true, "outfit picked")
    support.assert.isNil(err, "no error")
end)

runner:test("outfit slot: error when PickupOutfitID fails", function()
    local originalPickup = API.PickupOutfitID
    API.PickupOutfitID = function() return false end

    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.OUTFIT, id = 42, name = "Tank Set" }, 13, emptyCaches())

    API.PickupOutfitID = originalPickup

    support.assert.equal(picked, false, "not picked")
    support.assert.isTrue(err ~= nil, "error returned")
    support.assert.isTrue(err:find("slot 13") ~= nil, "slot in error")
    support.assert.isTrue(err:find("Tank Set") ~= nil, "outfit name in error")
end)

-- ---------------------------------------------------------------------------
-- Companion dispatch
-- ---------------------------------------------------------------------------

runner:test("companion slot: error when all pickup paths fail", function()
    _G.PickupCompanion = nil
    local originalMount = API.PickupMountBySpellID
    API.PickupMountBySpellID = function() return false end

    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.COMPANION, id = 99, subType = "MOUNT" }, 16, emptyCaches())

    API.PickupMountBySpellID = originalMount

    support.assert.equal(picked, false, "not picked")
    support.assert.isTrue(err ~= nil, "error returned")
end)

-- ---------------------------------------------------------------------------
-- UNKNOWN type dispatch
-- ---------------------------------------------------------------------------

runner:test("UNKNOWN type: error when raw type is unhandled", function()
    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.UNKNOWN, rawType = "futureaction", id = 42 },
        20, emptyCaches())

    support.assert.equal(picked, false, "not picked")
    support.assert.isTrue(err ~= nil, "error returned")
    support.assert.isTrue(err:find("futureaction") ~= nil, "raw type in error")
    support.assert.isTrue(err:find("slot 20") ~= nil, "slot in error")
end)

runner:test("UNKNOWN type with rawType=summonmount: delegates to PickupMountByID", function()
    local originalMount = API.PickupMountByID
    API.PickupMountByID = function() return true end

    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.UNKNOWN, rawType = "summonmount", id = 12345 },
        22, emptyCaches())

    API.PickupMountByID = originalMount

    support.assert.equal(picked, true, "mount picked via UNKNOWN rawType fallback")
    support.assert.isNil(err, "no error on success")
end)

-- ---------------------------------------------------------------------------
-- Unrecognised type (not in ACTION_TYPE at all)
-- ---------------------------------------------------------------------------

runner:test("completely unrecognised type returns error", function()
    local picked, err = R.PickupToCursor(
        { type = "completelynewtype" }, 30, emptyCaches())

    support.assert.equal(picked, false, "not picked")
    support.assert.isTrue(err ~= nil, "error returned")
    support.assert.isTrue(err:find("completelynewtype") ~= nil, "type name in error")
end)

-- ---------------------------------------------------------------------------
-- Error message text keys are from Text module (no bare strings)
-- ---------------------------------------------------------------------------

runner:test("item failure error uses Text.RESTORE_ITEM_FAILED format", function()
    local originalPickup = API.PickupItemID
    API.PickupItemID = function() return false end

    local _, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.ITEM, id = 1, name = "X" }, 99, emptyCaches())

    API.PickupItemID = originalPickup

    local expected = string.format(T.RESTORE_ITEM_FAILED, "X", 99)
    support.assert.equal(err, expected, "error matches Text.RESTORE_ITEM_FAILED template")
end)

os.exit(runner:run())
