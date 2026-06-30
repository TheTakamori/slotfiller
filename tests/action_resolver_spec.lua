---@diagnostic disable: undefined-global
local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/[^/]+%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

_G.ClearCursor = function() end

support.load_full(root)

local R   = SlotFiller.ActionResolver
local C   = SlotFiller.Constants
local API = SlotFiller.ActionAPI
local T   = SlotFiller.Text

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function emptyCaches()
    return { spell = {}, flyout = {}, macroBody = {}, macroName = {}, macroID = {} }
end

-- ---------------------------------------------------------------------------
-- Spell dispatch
-- ---------------------------------------------------------------------------

runner:test("spell slot: succeeds via spellbook index when ID is in cache", function()
    local originalRestorable = API.IsSpellRestorable
    local originalPickupIdx  = API.PickupSpellBookIndex
    API.IsSpellRestorable    = function() return true end
    API.PickupSpellBookIndex = function() return true end

    local caches = emptyCaches()
    caches.spell[133] = 5
    local picked, err = R.PickupToCursor({ type = C.ACTION_TYPE.SPELL, id = 133 }, 1, caches)

    API.IsSpellRestorable    = originalRestorable
    API.PickupSpellBookIndex = originalPickupIdx

    support.assert.equal(picked, true, "spell picked up via ID cache")
    support.assert.isNil(err, "no error on success")
end)

runner:test("spell slot: silently skipped when not restorable (off-spec)", function()
    local originalRestorable = API.IsSpellRestorable
    API.IsSpellRestorable    = function() return false end

    local picked, err = R.PickupToCursor(
        { type = C.ACTION_TYPE.SPELL, id = 99999 }, 1, emptyCaches())

    API.IsSpellRestorable = originalRestorable

    support.assert.equal(picked, false, "not picked")
    support.assert.isNil(err, "no error — silent skip")
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
