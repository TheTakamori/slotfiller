---@diagnostic disable: undefined-global
local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/[^/]+%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_full(root)

-- SlashCommands:Handle reaches into UI.MainFrame / UI.MinimapButton, neither
-- of which is loaded by support.load_full (they require live WoW frame
-- APIs). Stub minimal versions so Handle's dispatch logic can run.
SlotFiller.UI = SlotFiller.UI or {}
SlotFiller.UI.MainFrame = { Toggle = function() end }
SlotFiller.UI.MinimapButton = { Ensure = function() end, ToggleHidden = function() end }

local Handler = SlotFiller.UI.SlashCommands
local Text = SlotFiller.Text

local function capturePrint()
    local lines = {}
    SlotFiller.Print = function(msg) lines[#lines + 1] = msg end
    return lines
end

-- ---------------------------------------------------------------------------
-- OPEN / HELP / MINIMAP — no readiness gate
-- ---------------------------------------------------------------------------

runner:test("empty input opens the main frame", function()
    local opened = false
    SlotFiller.UI.MainFrame.Toggle = function() opened = true end

    Handler:Handle("")

    support.assert.isTrue(opened, "MainFrame:Toggle called for empty input")
end)

runner:test("help prints the help text", function()
    local lines = capturePrint()
    Handler:Handle("help")
    support.assert.isTrue(#lines > 0, "help prints at least one line")
    support.assert.equal(lines[1], Text.SLASH_HELP_TITLE, "first line is the help title")
end)

runner:test("minimap ensures and toggles the minimap button", function()
    local ensured, toggled = false, false
    SlotFiller.UI.MinimapButton.Ensure       = function() ensured = true end
    SlotFiller.UI.MinimapButton.ToggleHidden = function() toggled = true end

    Handler:Handle("minimap")

    support.assert.isTrue(ensured, "minimap button ensured")
    support.assert.isTrue(toggled, "minimap visibility toggled")
end)

-- ---------------------------------------------------------------------------
-- ERRORS — no readiness gate
-- ---------------------------------------------------------------------------

runner:test("errors prints 'no errors' when nothing was recorded", function()
    SlotFiller.Restorer.lastErrors = {}
    local lines = capturePrint()

    Handler:Handle("errors")

    support.assert.equal(#lines, 1, "one line printed")
    support.assert.equal(lines[1], Text.NO_ERRORS, "prints the no-errors message")
end)

runner:test("errors prints each recorded restore issue", function()
    SlotFiller.Restorer.lastErrors = { "issue one", "issue two" }
    local lines = capturePrint()

    Handler:Handle("errors")

    support.assert.equal(#lines, 2,           "both issues printed")
    support.assert.equal(lines[1], "issue one", "first issue printed verbatim")
    support.assert.equal(lines[2], "issue two", "second issue printed verbatim")

    SlotFiller.Restorer.lastErrors = {}
end)

-- ---------------------------------------------------------------------------
-- Readiness-gated commands
-- ---------------------------------------------------------------------------

runner:test("save is blocked when the character isn't ready", function()
    SlotFiller.Context.RequireReady = function() return false end
    local saveCalled = false
    SlotFiller.ProfileActions.Save = function() saveCalled = true end

    Handler:Handle("save myprofile")

    support.assert.isFalse(saveCalled, "ProfileActions:Save never reached without readiness")
end)

runner:test("scan prints the occupied-slot dump from Scanner:FormatSlotDump", function()
    SlotFiller.Context.RequireReady = function() return true end
    local originalGetInfo = SlotFiller.ActionAPI.GetSlotActionInfo
    SlotFiller.ActionAPI.GetSlotActionInfo = function(actionID)
        if actionID == 1 then return "spell", 133, "spell", 0 end
        return nil
    end

    local lines = capturePrint()
    Handler:Handle("scan")

    SlotFiller.ActionAPI.GetSlotActionInfo = originalGetInfo

    support.assert.equal(#lines, 2, "one slot line plus the summary line")
    support.assert.isTrue(lines[1]:find("%[1%]") ~= nil, "slot 1 line printed")
    support.assert.isTrue(lines[2]:find("1 occupied") ~= nil, "summary reports one occupied slot")
end)

runner:test("save/load/list/delete/rename/duplicate dispatch to ProfileActions", function()
    SlotFiller.Context.RequireReady = function() return true end

    local calls = {}
    SlotFiller.ProfileActions.Save      = function(_, name) calls.save = name end
    SlotFiller.ProfileActions.Load      = function(_, name) calls.load = name end
    SlotFiller.ProfileActions.List      = function(_) calls.list = true end
    SlotFiller.ProfileActions.Delete    = function(_, name) calls.delete = name end
    SlotFiller.ProfileActions.Rename    = function(_, old, new) calls.rename = { old, new } end
    SlotFiller.ProfileActions.Duplicate = function(_, src, new) calls.duplicate = { src, new } end

    Handler:Handle("save Raid")
    Handler:Handle("load Raid")
    Handler:Handle("list")
    Handler:Handle("delete Raid")
    Handler:Handle("rename Old New")
    Handler:Handle("duplicate Old Copy")

    support.assert.equal(calls.save,   "Raid", "save dispatched with name")
    support.assert.equal(calls.load,   "Raid", "load dispatched with name")
    support.assert.isTrue(calls.list,           "list dispatched")
    support.assert.equal(calls.delete, "Raid", "delete dispatched with name")
    support.assert.same(calls.rename,    { "Old", "New" },  "rename dispatched with old/new")
    support.assert.same(calls.duplicate, { "Old", "Copy" }, "duplicate dispatched with source/new")
end)

os.exit(runner:run())
