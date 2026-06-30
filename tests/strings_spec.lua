---@diagnostic disable: undefined-global
local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/[^/]+%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_addon(root)

local Strings = SlotFiller.Strings

runner:test("Trim strips leading and trailing whitespace", function()
    support.assert.equal(Strings.Trim("  hello  "), "hello", "spaces trimmed")
    support.assert.equal(Strings.Trim("\thello\n"), "hello", "tabs/newlines trimmed")
end)

runner:test("Trim preserves internal whitespace", function()
    support.assert.equal(Strings.Trim("  hello world  "), "hello world", "internal space kept")
end)

runner:test("Trim returns empty string for nil", function()
    support.assert.equal(Strings.Trim(nil), "", "nil becomes empty string")
end)

runner:test("Trim returns empty string for non-string input", function()
    support.assert.equal(Strings.Trim(42),    "", "number becomes empty string")
    support.assert.equal(Strings.Trim(true),  "", "boolean becomes empty string")
    support.assert.equal(Strings.Trim({}),    "", "table becomes empty string")
end)

runner:test("Trim returns empty string for whitespace-only input", function()
    support.assert.equal(Strings.Trim("   "), "", "whitespace-only collapses to empty")
end)

runner:test("Trim leaves an already-trimmed string unchanged", function()
    support.assert.equal(Strings.Trim("clean"), "clean", "no-op on clean input")
end)

os.exit(runner:run())
