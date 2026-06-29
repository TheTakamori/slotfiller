---@diagnostic disable: undefined-global
local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/run%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

-- ClearCursor is called on several unguarded code paths in RestoreSlot.
-- Provide a no-op stub so those paths don't crash in the test host.
_G.ClearCursor = function() end

support.load_full(root)

local R = SlotFiller.Restorer
local C = SlotFiller.Constants

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
    return R:BuildMacroCache()
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
    support.assert.equal(R:FindMacroID(slot, body, name, id), 1, "matched by macroID")
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
    support.assert.equal(R:FindMacroID(slot, body, name, id), 1, "matched by body")
end)

runner:test("FindMacroID falls back to name match when body absent", function()
    local body, name, id = setup_macros({
        { "Fireball", nil, "/cast Fireball" },
    })
    teardown_macros()

    local slot = { name = "Fireball" }
    support.assert.equal(R:FindMacroID(slot, body, name, id), 1, "matched by name")
end)

runner:test("FindMacroID returns nil when nothing matches", function()
    local body, name, id = setup_macros({
        { "Fireball", nil, "/cast Fireball" },
    })
    teardown_macros()

    local slot = { macroID = 99, name = "Ghost", body = "/no_match" }
    support.assert.isNil(R:FindMacroID(slot, body, name, id), "no match returns nil")
end)

-- ---------------------------------------------------------------------------
-- GetLastErrors / GetLastErrorsText
-- ---------------------------------------------------------------------------

runner:test("GetLastErrorsText returns NO_ERRORS text when no errors", function()
    SlotFiller.State:ResetForTests()
    -- Apply an empty profile to clear any leftover errors.
    R:ApplyProfile({ slots = {} })
    support.assert.equal(R:GetLastErrorsText(), SlotFiller.Text.NO_ERRORS, "no-error text")
end)

runner:test("GetLastErrors returns the raw error list", function()
    SlotFiller.State:ResetForTests()
    R:ApplyProfile({ slots = {} })
    local errors = R:GetLastErrors()
    support.assert.equal(type(errors), "table", "errors is a table")
    support.assert.equal(#errors, 0, "empty after clean apply")
end)

runner:test("GetLastErrorsText returns joined error lines after failures", function()
    _G.GetMacroInfo = function() return nil end
    _G.MAX_ACCOUNT_MACROS = 0
    _G.MAX_CHARACTER_MACROS = 0

    local profile = {
        slots = {
            [1] = { type = C.ACTION_TYPE.MACRO, macroID = 99, name = "Ghost", body = "" },
            [2] = { type = C.ACTION_TYPE.MACRO, macroID = 88, name = "Also Gone", body = "" },
        },
    }
    R:ApplyProfile(profile)

    _G.GetMacroInfo = nil

    local text = R:GetLastErrorsText()
    support.assert.isFalse(text == SlotFiller.Text.NO_ERRORS, "error text is not the no-error string")
    support.assert.isTrue(text:find("slot 1") ~= nil, "slot 1 mentioned")
    support.assert.isTrue(text:find("slot 2") ~= nil, "slot 2 mentioned")
end)

-- ---------------------------------------------------------------------------
-- ApplyProfile guards
-- ---------------------------------------------------------------------------

runner:test("ApplyProfile returns false for nil profile", function()
    local ok, reason = R:ApplyProfile(nil)
    support.assert.equal(ok, false, "false for nil")
    support.assert.equal(reason, "missing", "reason: missing")
end)

runner:test("ApplyProfile returns false for profile without slots table", function()
    local ok, reason = R:ApplyProfile({ savedAt = 1 })
    support.assert.equal(ok, false, "false for missing slots")
    support.assert.equal(reason, "missing", "reason: missing")
end)

runner:test("ApplyProfile returns false during combat", function()
    _G.InCombatLockdown = function() return true end
    local ok, reason = R:ApplyProfile({ slots = {} })
    _G.InCombatLockdown = nil
    support.assert.equal(ok, false, "false in combat")
    support.assert.equal(reason, "combat", "reason: combat")
end)

runner:test("ApplyProfile returns true with zero errors for empty profile", function()
    _G.GetMacroInfo = nil
    _G.MAX_ACCOUNT_MACROS = 0
    _G.MAX_CHARACTER_MACROS = 0
    local ok, errCount = R:ApplyProfile({ slots = {} })
    support.assert.equal(ok, true, "true for empty profile")
    support.assert.equal(errCount, 0, "zero errors")
end)

runner:test("ApplyProfile accumulates one error per unresolvable macro slot", function()
    _G.GetMacroInfo = function() return nil end
    _G.MAX_ACCOUNT_MACROS = 0
    _G.MAX_CHARACTER_MACROS = 0

    local profile = {
        slots = {
            [3] = { type = C.ACTION_TYPE.MACRO, macroID = 99, name = "Deleted", body = "" },
        },
    }
    local ok, errCount = R:ApplyProfile(profile)
    _G.GetMacroInfo = nil

    support.assert.equal(ok, true, "apply still returns true with errors")
    support.assert.equal(errCount, 1, "one error recorded")
end)

os.exit(runner:run())
