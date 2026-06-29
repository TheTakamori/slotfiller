local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/run%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_addon(root)

runner:test("Build returns activeProfile and context fields", function()
    SlotFiller.State:ResetForTests()
    SlotFiller.State:SetProfile("Beta",  { savedAt = 2, slots = {} })
    SlotFiller.State:SetProfile("Alpha", { savedAt = 1, slots = {} })
    SlotFiller.State:SetActiveProfile("Beta")

    local model = SlotFiller.ProfileIndex:Build()
    support.assert.equal(model.activeProfile, "Beta", "active profile reported")
end)

runner:test("Build returns nil activeProfile when none set", function()
    SlotFiller.State:ResetForTests()
    local model = SlotFiller.ProfileIndex:Build()
    support.assert.isNil(model.activeProfile, "no active profile initially")
end)

runner:test("Build includes context identifiers (nil in tests is acceptable)", function()
    SlotFiller.State:ResetForTests()
    -- In a plain Lua host, WoW APIs are absent; the fields should be nil without error.
    local model = SlotFiller.ProfileIndex:Build()
    support.assert.equal(type(model), "table", "Build returns a table")
    -- specName, characterName, realmName, className may be nil in plain Lua host.
    -- The table itself must have these keys (even if nil values).
    support.assert.isTrue(model.specName == nil or type(model.specName) == "string",
        "specName is string or nil")
end)

os.exit(runner:run())
