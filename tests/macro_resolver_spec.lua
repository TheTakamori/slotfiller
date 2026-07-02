---@diagnostic disable: undefined-global
local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/run%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_full(root)

local M = SlotFiller.MacroResolver

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Install mock macro data and return (bodyCache, nameCache, idCache).
local function setup_macros(macros)
    _G.MAX_ACCOUNT_MACROS = #macros
    _G.MAX_CHARACTER_MACROS = 0
    _G.GetMacroInfo = function(id)
        local m = macros[id]
        if not m then return nil end
        return m[1], m[2], m[3]  -- name, icon, body
    end
    return M:BuildMacroCache()
end

local function teardown_macros()
    _G.GetMacroInfo = nil
    _G.MAX_ACCOUNT_MACROS = nil
    _G.MAX_CHARACTER_MACROS = nil
end

-- ---------------------------------------------------------------------------
-- BuildMacroCache
-- ---------------------------------------------------------------------------

runner:test("BuildMacroCache indexes body, name, and id", function()
    local body, name, id = setup_macros({
        { "Fireball", nil, "/cast Fireball" },
        { "Frost",    nil, "/cast Frostbolt" },
    })
    teardown_macros()

    local compressed1 = SlotFiller.Normalizer.CompressMacroText("/cast Fireball")
    local compressed2 = SlotFiller.Normalizer.CompressMacroText("/cast Frostbolt")

    support.assert.equal(body[compressed1], 1, "body cache points to macro 1")
    support.assert.equal(body[compressed2], 2, "body cache points to macro 2")
    support.assert.equal(name["Fireball"],  1, "name cache points to macro 1")
    support.assert.equal(name["Frost"],     2, "name cache points to macro 2")
    support.assert.equal(id[1],             1, "id cache has macro 1")
    support.assert.equal(id[2],             2, "id cache has macro 2")
end)

runner:test("BuildMacroCache blacklists duplicate macro names", function()
    local _, nameCache, _ = setup_macros({
        { "Shared", nil, "/cast Fireball" },
        { "Shared", nil, "/cast Frostbolt" },
        { "Unique", nil, "/cast Ice Lance" },
    })
    teardown_macros()

    support.assert.isNil(nameCache["Shared"], "duplicate name blacklisted from name cache")
    support.assert.equal(nameCache["Unique"], 3, "unique name kept in name cache")
end)

-- ---------------------------------------------------------------------------
-- BuildMacroCache — macro-count fallback
-- ---------------------------------------------------------------------------

runner:test("BuildMacroCache falls back to Constants when MAX_CHARACTER_MACROS is unavailable", function()
    -- Regression test: Blizzard has deprecated similar macro-count globals
    -- before, and a naive `MAX_CHARACTER_MACROS or 0` fallback would silently
    -- stop character-specific macros (which occupy slots above the account
    -- macro count) from ever being scanned/cached.
    local C = SlotFiller.Constants
    _G.MAX_ACCOUNT_MACROS = nil
    _G.MAX_CHARACTER_MACROS = nil
    local characterSlot = C.MAX_ACCOUNT_MACROS_FALLBACK + 1
    _G.GetMacroInfo = function(id)
        if id == characterSlot then
            return "CharMacro", nil, "/cast Fireball"
        end
        return nil
    end

    local _, nameCache = M:BuildMacroCache()

    _G.GetMacroInfo = nil
    _G.MAX_ACCOUNT_MACROS = nil
    _G.MAX_CHARACTER_MACROS = nil

    support.assert.equal(nameCache["CharMacro"], characterSlot,
        "character macro slot beyond the account-macro fallback is still scanned")
end)

-- ---------------------------------------------------------------------------
-- BuildMacroCache — empty body/name never indexed
-- ---------------------------------------------------------------------------

-- Regression: empty string is truthy in Lua. Indexing "" would let any two
-- bodiless (or unresolvable) macro slots collide onto whichever real macro
-- happened to have an empty body/name — the same class of bug that let
-- unrelated character macros collapse into one during profile restore.
runner:test("BuildMacroCache never indexes an empty compressed body", function()
    local body = setup_macros({
        { "NoBody",  nil, "" },
        { "HasBody", nil, "/cast Fireball" },
    })
    teardown_macros()

    support.assert.isNil(body[""], "empty body is never a cache key")
end)

runner:test("BuildMacroCache never indexes an empty macro name", function()
    local _, name = setup_macros({
        { "", nil, "/cast Fireball" },
    })
    teardown_macros()

    support.assert.isNil(name[""], "empty name is never a cache key")
end)

-- ---------------------------------------------------------------------------
-- FindMacroID
-- ---------------------------------------------------------------------------

runner:test("FindMacroID matches by saved macroID first", function()
    local body, name, id = setup_macros({
        { "Fireball", nil, "/cast Fireball" },
    })
    teardown_macros()

    local slot = {
        macroID = 1,
        name = "Fireball",
        body = SlotFiller.Normalizer.CompressMacroText("/cast Fireball"),
    }
    support.assert.equal(M:FindMacroID(slot, body, name, id), 1, "matched by macroID")
end)

runner:test("FindMacroID falls back to body match when macroID absent from cache", function()
    local body, name, id = setup_macros({
        { "Fireball", nil, "/cast Fireball" },
    })
    teardown_macros()

    local slot = {
        macroID = 99,  -- stale id not in cache
        body = SlotFiller.Normalizer.CompressMacroText("/cast Fireball"),
    }
    support.assert.equal(M:FindMacroID(slot, body, name, id), 1, "matched by body")
end)

runner:test("FindMacroID falls back to name match when body absent", function()
    local body, name, id = setup_macros({
        { "Fireball", nil, "/cast Fireball" },
    })
    teardown_macros()

    local slot = { name = "Fireball" }
    support.assert.equal(M:FindMacroID(slot, body, name, id), 1, "matched by name")
end)

runner:test("FindMacroID returns nil when nothing matches", function()
    local body, name, id = setup_macros({
        { "Fireball", nil, "/cast Fireball" },
    })
    teardown_macros()

    local slot = { macroID = 99, name = "Ghost", body = "/no_match" }
    support.assert.isNil(M:FindMacroID(slot, body, name, id), "no match returns nil")
end)

-- Regression: two slots that both lack real capture data (empty body AND
-- empty name — e.g. two macros whose id/name couldn't be resolved) must
-- never be treated as matching each other or an unrelated bodiless macro.
runner:test("FindMacroID never matches two slots together via an empty body", function()
    local body, name, id = setup_macros({
        { "Real", nil, "/cast Fireball" },
    })
    teardown_macros()

    local slotA = { name = "", body = "" }
    local slotB = { name = "", body = "" }
    support.assert.isNil(M:FindMacroID(slotA, body, name, id), "empty-bodied slot A has no match")
    support.assert.isNil(M:FindMacroID(slotB, body, name, id), "empty-bodied slot B has no match")
end)

-- ---------------------------------------------------------------------------
-- ResolveOrCreateMacro
-- ---------------------------------------------------------------------------

local emptyMacroCaches = support.empty_macro_caches

runner:test("ResolveOrCreateMacro returns the existing macroID when one matches", function()
    local body, name, id = setup_macros({ { "Fireball", nil, "/cast Fireball" } })
    teardown_macros()

    local macroID, errReason = M:ResolveOrCreateMacro(
        "Fireball", SlotFiller.Normalizer.CompressMacroText("/cast Fireball"), nil, false,
        { macroBody = body, macroName = name, macroID = id })

    support.assert.equal(macroID, 1,    "matched existing macro")
    support.assert.isNil(errReason,     "no error reason on match")
end)

runner:test("ResolveOrCreateMacro creates a character macro when perCharacter and no match", function()
    _G.MAX_CHARACTER_MACROS = 18
    _G.GetNumMacros = function() return 0, 0 end
    _G.CreateMacro  = function() return 555 end

    local macroID, errReason = M:ResolveOrCreateMacro(
        "New", "/cast Ice", nil, true, emptyMacroCaches())

    _G.MAX_CHARACTER_MACROS = nil
    _G.GetNumMacros = nil
    _G.CreateMacro  = nil

    support.assert.equal(macroID, 555, "newly created macroID returned")
    support.assert.isNil(errReason,    "no error reason on success")
end)

-- Regression: an empty-string name is truthy in Lua. Without an explicit
-- guard, ResolveOrCreateMacro would treat it like a real name and call
-- CreateMacro with a blank name — producing the empty "ghost" character
-- macro seen in the field regression this whole suite is guarding against.
runner:test("ResolveOrCreateMacro treats an empty-string name like no name at all", function()
    local createCalled = false
    _G.MAX_CHARACTER_MACROS = 18
    _G.GetNumMacros = function() return 0, 0 end
    _G.CreateMacro  = function() createCalled = true return 555 end

    local macroID, errReason = M:ResolveOrCreateMacro(
        "", "", nil, true, emptyMacroCaches())

    _G.MAX_CHARACTER_MACROS = nil
    _G.GetNumMacros = nil
    _G.CreateMacro  = nil

    support.assert.isNil(macroID,               "no macroID for an unnamed slot")
    support.assert.equal(errReason, "not_found", "reason is not_found, not a creation")
    support.assert.isFalse(createCalled,         "CreateMacro is never called with a blank name")
end)

runner:test("ResolveOrCreateMacro returns not_found when not perCharacter and no match", function()
    local macroID, errReason = M:ResolveOrCreateMacro(
        "Ghost", "/cast Gone", nil, false, emptyMacroCaches())

    support.assert.isNil(macroID,            "no macroID")
    support.assert.equal(errReason, "not_found", "reason is not_found for global macros")
end)

runner:test("ResolveOrCreateMacro returns limit when character macro cap is full", function()
    _G.MAX_CHARACTER_MACROS = 18
    _G.GetNumMacros = function() return 0, 18 end
    _G.CreateMacro  = function() return 1 end

    local macroID, errReason = M:ResolveOrCreateMacro(
        "Overflow", "/cast X", nil, true, emptyMacroCaches())

    _G.MAX_CHARACTER_MACROS = nil
    _G.GetNumMacros = nil
    _G.CreateMacro  = nil

    support.assert.isNil(macroID,       "no macroID at limit")
    support.assert.equal(errReason, "limit", "reason is limit")
end)

-- ---------------------------------------------------------------------------
-- ResolveOrCreateMacro keeps shared caches in sync after creation
-- ---------------------------------------------------------------------------

runner:test("ResolveOrCreateMacro updates caches so a second lookup finds the new macro", function()
    _G.MAX_CHARACTER_MACROS = 18
    _G.GetNumMacros = function() return 0, 0 end
    local nextID = 700
    _G.CreateMacro  = function() nextID = nextID + 1; return nextID end

    local caches = emptyMacroCaches()
    local firstID, firstErr = M:ResolveOrCreateMacro("Dup", "/cast Dup", nil, true, caches)
    local secondID, secondErr = M:ResolveOrCreateMacro("Dup", "/cast Dup", nil, true, caches)

    _G.MAX_CHARACTER_MACROS = nil
    _G.GetNumMacros = nil
    _G.CreateMacro  = nil

    support.assert.isNil(firstErr,  "no error on first creation")
    support.assert.isNil(secondErr, "no error on second lookup")
    support.assert.equal(secondID, firstID, "second lookup reuses the macro created by the first call")
end)

os.exit(runner:run())
