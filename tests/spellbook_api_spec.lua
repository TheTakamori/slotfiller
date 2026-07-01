---@diagnostic disable: undefined-global
local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/[^/]+%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_full(root)

local BookAPI = SlotFiller.SpellBookAPI

-- Installs a minimal C_SpellBook stub with one current-spec skill line
-- containing the given list of { name, itemType, spellID, actionID, subName }.
local function stubSpellBook(items)
    _G.C_SpellBook = {
        GetNumSpellBookSkillLines = function() return 1 end,
        GetSpellBookSkillLineInfo = function()
            return { isGuild = false, isOffSpec = false, itemIndexOffset = 0, numSpellBookItems = #items }
        end,
        GetSpellBookItemInfo = function(bookIndex)
            return items[bookIndex]
        end,
    }
end

local function teardownSpellBook()
    _G.C_SpellBook = nil
end

-- ---------------------------------------------------------------------------
-- IsSpellRestorable
-- ---------------------------------------------------------------------------

runner:test("IsSpellRestorable returns false for a nil spellID", function()
    support.assert.isFalse(BookAPI.IsSpellRestorable(nil), "nil spellID is never restorable")
end)

runner:test("IsSpellRestorable defaults to true without C_SpellBook (test host)", function()
    support.assert.isTrue(BookAPI.IsSpellRestorable(123), "assume valid when API unavailable")
end)

runner:test("IsSpellRestorable delegates to C_SpellBook.IsSpellKnownOrInSpellBook", function()
    _G.C_SpellBook = {
        IsSpellKnownOrInSpellBook = function(spellID) return spellID == 42 end,
    }
    support.assert.isTrue(BookAPI.IsSpellRestorable(42),  "known spell is restorable")
    support.assert.isFalse(BookAPI.IsSpellRestorable(43), "unknown spell is not restorable")
    _G.C_SpellBook = nil
end)

-- ---------------------------------------------------------------------------
-- BuildSpellBookCache / IterateSpellBookEntries
-- ---------------------------------------------------------------------------

runner:test("BuildSpellBookCache indexes by name, lowercase name, subName, and spellID", function()
    stubSpellBook({
        { name = "Fireball", subName = "Rank 1", spellID = 100, actionID = 100, itemType = "spell" },
    })

    local cache = BookAPI.BuildSpellBookCache()

    teardownSpellBook()

    support.assert.equal(cache["Fireball"], 1, "indexed by exact name")
    support.assert.equal(cache["fireball"], 1, "indexed by lowercase name")
    support.assert.equal(cache["FireballRank 1"], 1, "indexed by name+subName")
    support.assert.equal(cache[100], 1, "indexed by spellID")
end)

runner:test("BuildSpellBookCache excludes flyout entries", function()
    stubSpellBook({
        { name = "Portal Menu", spellID = 200, actionID = 200, itemType = "flyout" },
    })

    local cache = BookAPI.BuildSpellBookCache()

    teardownSpellBook()

    support.assert.isNil(cache["Portal Menu"], "flyouts excluded from the spell cache")
end)

runner:test("BuildSpellBookCache excludes off-spec entries", function()
    stubSpellBook({
        { name = "Off Spec Spell", spellID = 300, actionID = 300, itemType = "spell", isOffSpec = true },
    })

    local cache = BookAPI.BuildSpellBookCache()

    teardownSpellBook()

    support.assert.isNil(cache["Off Spec Spell"], "off-spec entries excluded")
end)

-- ---------------------------------------------------------------------------
-- BuildFlyoutBookCache
-- ---------------------------------------------------------------------------

runner:test("BuildFlyoutBookCache indexes flyout entries by actionID", function()
    stubSpellBook({
        { name = "Spell",       spellID = 1, actionID = 1, itemType = "spell" },
        { name = "Portal Menu", spellID = 2, actionID = 555, itemType = "flyout" },
    })

    local cache = BookAPI.BuildFlyoutBookCache()

    teardownSpellBook()

    support.assert.equal(cache[555], 2, "flyout indexed by its actionID")
    support.assert.isNil(cache[1],   "non-flyout entries excluded")
end)

runner:test("BuildFlyoutBookCache returns an empty table without C_SpellBook", function()
    local cache = BookAPI.BuildFlyoutBookCache()
    support.assert.equal(next(cache), nil, "empty cache when spellbook API unavailable")
end)

-- ---------------------------------------------------------------------------
-- BuildSpellOverrideMap
-- ---------------------------------------------------------------------------

runner:test("BuildSpellOverrideMap maps override ID to base ID", function()
    stubSpellBook({
        { name = "Base Spell", spellID = 100, actionID = 100, itemType = "spell" },
    })
    _G.C_Spell = {
        GetOverrideSpell = function(spellID)
            if spellID == 100 then return 200 end
            return spellID
        end,
    }

    local overrideMap = BookAPI.BuildSpellOverrideMap()

    teardownSpellBook()
    _G.C_Spell = nil

    support.assert.equal(overrideMap[200], 100, "override ID 200 maps back to base ID 100")
end)

runner:test("BuildSpellOverrideMap is empty without C_Spell.GetOverrideSpell", function()
    local overrideMap = BookAPI.BuildSpellOverrideMap()
    support.assert.equal(next(overrideMap), nil, "empty map without the override API")
end)

os.exit(runner:run())
