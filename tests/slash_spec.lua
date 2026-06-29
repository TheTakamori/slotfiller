local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/run%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_addon(root)

local parser  = SlotFiller.SlashParser
local command = SlotFiller.Constants.COMMAND

-- ---------------------------------------------------------------------------
-- Open / positional load (original coverage)
-- ---------------------------------------------------------------------------

runner:test("parses open, save, and load commands", function()
    support.assert.same(parser.Parse(""),          { verb = command.OPEN },                         "empty opens ui")
    support.assert.same(parser.Parse("save raid"), { verb = command.SAVE, profileName = "raid" },   "save")
    support.assert.same(parser.Parse("load raid"), { verb = command.LOAD, profileName = "raid" },   "load")
    support.assert.same(parser.Parse("raid"),      { verb = command.LOAD, profileName = "raid" },   "shorthand load")
end)

runner:test("parses rename and duplicate commands", function()
    support.assert.same(parser.Parse("rename old new name"), {
        verb = command.RENAME,
        oldName = "old",
        newName = "new name",
    }, "rename")
    support.assert.same(parser.Parse("duplicate source copy"), {
        verb = command.DUPLICATE,
        sourceName = "source",
        newName = "copy",
    }, "duplicate")
end)

runner:test("parses minimap command", function()
    support.assert.same(parser.Parse("minimap"), { verb = command.MINIMAP }, "minimap toggle")
end)

-- ---------------------------------------------------------------------------
-- New commands added since initial spec
-- ---------------------------------------------------------------------------

runner:test("parses scan command", function()
    support.assert.same(parser.Parse("scan"), { verb = command.SCAN }, "scan")
    support.assert.same(parser.Parse("SCAN"), { verb = command.SCAN }, "scan case-insensitive")
end)

runner:test("parses sba command", function()
    support.assert.same(parser.Parse("sba"), { verb = command.SBA }, "sba diagnostics")
end)

runner:test("parses errors command", function()
    support.assert.same(parser.Parse("errors"), { verb = command.ERRORS }, "errors")
end)

runner:test("parses list command", function()
    support.assert.same(parser.Parse("list"), { verb = command.LIST }, "list")
end)

runner:test("parses delete command with profile name", function()
    support.assert.same(parser.Parse("delete My Profile"), {
        verb = command.DELETE,
        profileName = "My Profile",
    }, "delete with name")
end)

runner:test("parses help command", function()
    support.assert.same(parser.Parse("help"), { verb = command.HELP }, "help")
end)

-- ---------------------------------------------------------------------------
-- Edge cases
-- ---------------------------------------------------------------------------

runner:test("load aliases apply and use produce LOAD verb", function()
    support.assert.same(parser.Parse("apply Raid"),  { verb = command.LOAD, profileName = "Raid" },  "apply alias")
    support.assert.same(parser.Parse("use Mythic"),  { verb = command.LOAD, profileName = "Mythic" }, "use alias")
end)

runner:test("unrecognised verb is treated as shorthand load", function()
    support.assert.same(parser.Parse("Ret Base"), { verb = command.LOAD, profileName = "Ret Base" }, "profile name with space")
    support.assert.same(parser.Parse("MySingle"), { verb = command.LOAD, profileName = "MySingle" }, "single token profile name")
end)

runner:test("leading and trailing whitespace is stripped", function()
    support.assert.same(parser.Parse("  save   my raid  "), {
        verb = command.SAVE,
        profileName = "my raid",
    }, "save with surrounding spaces")
    support.assert.same(parser.Parse("  "), { verb = command.OPEN }, "whitespace-only opens ui")
end)

os.exit(runner:run())
