---@diagnostic disable: undefined-global
local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/[^/]+%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_addon(root)

-- ProfilePopups.lua registers StaticPopupDialogs entries and calls
-- StaticPopup_Show at load/runtime — neither exists in the plain-Lua host,
-- so stub minimal versions before loading it directly.
_G.StaticPopupDialogs = {}
_G.ACCEPT, _G.CANCEL, _G.YES, _G.NO = "ACCEPT", "CANCEL", "YES", "NO"

local shown = nil
_G.StaticPopup_Show = function(which, textArg1, textArg2, data)
    shown = { which = which, textArg1 = textArg1, textArg2 = textArg2, data = data }
end

do
    local chunk = assert(loadfile(root .. "/UI/ProfilePopups.lua"))
    chunk("SlotFiller", SlotFiller)
end

local Popups = SlotFiller.UI.ProfilePopups
local Dialogs = _G.StaticPopupDialogs

local function stubReady(ready)
    SlotFiller.Context.RequireReady = function() return ready end
end

local function stubNotInCombat(notInCombat)
    SlotFiller.Context.RequireNotInCombat = function() return notInCombat end
end

stubReady(true)
stubNotInCombat(true)

-- ---------------------------------------------------------------------------
-- Show* guard clauses
-- ---------------------------------------------------------------------------

runner:test("ShowRename does nothing without a profile name", function()
    shown = nil
    Popups.ShowRename(nil, function() end)
    support.assert.isNil(shown, "no popup shown for a nil profile name")
end)

runner:test("ShowOverwrite shows the popup with the profile name and onSuccess callback", function()
    shown = nil
    local onSuccess = function() end
    Popups.ShowOverwrite("Raid", onSuccess)

    support.assert.equal(shown.which, "SLOTFILLER_OVERWRITE", "overwrite popup shown")
    support.assert.equal(shown.textArg1, "Raid", "profile name passed as the text substitution arg")
    support.assert.equal(shown.data.name, "Raid", "data carries the profile name")
    support.assert.isTrue(shown.data.onSuccess == onSuccess, "data carries the onSuccess callback")
end)

runner:test("ShowOverwrite is blocked while in combat", function()
    stubNotInCombat(false)
    shown = nil

    Popups.ShowOverwrite("Raid", function() end)

    stubNotInCombat(true)
    support.assert.isNil(shown, "overwrite popup never shown while in combat")
end)

runner:test("ShowRename/ShowDuplicate/ShowDelete show their respective popups", function()
    shown = nil
    Popups.ShowRename("Raid", function() end)
    support.assert.equal(shown.which, "SLOTFILLER_RENAME")

    shown = nil
    Popups.ShowDuplicate("Raid", function() end)
    support.assert.equal(shown.which, "SLOTFILLER_DUPLICATE")

    shown = nil
    Popups.ShowDelete("Raid", function() end)
    support.assert.equal(shown.which, "SLOTFILLER_DELETE")
end)

-- ---------------------------------------------------------------------------
-- OnAccept dispatch
-- ---------------------------------------------------------------------------

runner:test("Overwrite OnAccept calls ProfileActions:Overwrite and onSuccess with the same name", function()
    local overwritten, succeededWith = nil, nil
    SlotFiller.ProfileActions.Overwrite = function(_, name) overwritten = name; return true end

    Dialogs.SLOTFILLER_OVERWRITE.OnAccept({ data = { name = "Raid", onSuccess = function(n) succeededWith = n end } })

    support.assert.equal(overwritten, "Raid", "Overwrite called with the profile name")
    support.assert.equal(succeededWith, "Raid", "onSuccess called with the same name")
end)

runner:test("Overwrite OnAccept does not call onSuccess when ProfileActions:Overwrite fails", function()
    SlotFiller.ProfileActions.Overwrite = function() return false end
    local called = false

    Dialogs.SLOTFILLER_OVERWRITE.OnAccept({ data = { name = "Raid", onSuccess = function() called = true end } })

    support.assert.isFalse(called, "onSuccess not called on failure")
end)

runner:test("Overwrite OnAccept does not call onSuccess when not ready", function()
    stubReady(false)
    SlotFiller.ProfileActions.Overwrite = function() return true end
    local called = false

    Dialogs.SLOTFILLER_OVERWRITE.OnAccept({ data = { name = "Raid", onSuccess = function() called = true end } })

    stubReady(true)
    support.assert.isFalse(called, "onSuccess not called when RequireReady() is false")
end)

runner:test("Delete OnAccept calls ProfileActions:Delete and onSuccess(nil)", function()
    local deleted, succeededWith, successCalled = nil, "unset", false
    SlotFiller.ProfileActions.Delete = function(_, name) deleted = name; return true end

    Dialogs.SLOTFILLER_DELETE.OnAccept({
        data = { name = "Raid", onSuccess = function(n) succeededWith = n; successCalled = true end },
    })

    support.assert.equal(deleted, "Raid", "Delete called with the profile name")
    support.assert.isTrue(successCalled, "onSuccess called")
    support.assert.isNil(succeededWith, "onSuccess called with nil (no more selected profile)")
end)

runner:test("Rename OnAccept reads the edit box and calls ProfileActions:Rename(old, new)", function()
    local renamedArgs, succeededWith = nil, nil
    SlotFiller.ProfileActions.Rename = function(_, old, new) renamedArgs = { old, new }; return true end

    local dialog = {
        data = { name = "OldName", onSuccess = function(n) succeededWith = n end },
        EditBox = { GetText = function() return "NewName" end },
    }
    Dialogs.SLOTFILLER_RENAME.OnAccept(dialog)

    support.assert.same(renamedArgs, { "OldName", "NewName" }, "Rename called with old/new names")
    support.assert.equal(succeededWith, "NewName", "onSuccess called with the new name")
end)

runner:test("Rename EditBoxOnEnterPressed dispatches the same way and hides the dialog", function()
    local renamedArgs = nil
    SlotFiller.ProfileActions.Rename = function(_, old, new) renamedArgs = { old, new }; return true end

    local hidden = false
    local dialog = { data = { name = "OldName", onSuccess = function() end }, Hide = function() hidden = true end }
    local editBox = {
        GetText = function() return "NewName" end,
        GetParent = function() return dialog end,
    }
    Dialogs.SLOTFILLER_RENAME.EditBoxOnEnterPressed(editBox)

    support.assert.same(renamedArgs, { "OldName", "NewName" }, "Rename called via Enter key path")
    support.assert.isTrue(hidden, "dialog hidden after Enter")
end)

runner:test("Duplicate OnAccept calls ProfileActions:Duplicate(source, new)", function()
    local duplicatedArgs = nil
    SlotFiller.ProfileActions.Duplicate = function(_, src, new) duplicatedArgs = { src, new }; return true end

    local dialog = {
        data = { name = "Source", onSuccess = function() end },
        EditBox = { GetText = function() return "Copy" end },
    }
    Dialogs.SLOTFILLER_DUPLICATE.OnAccept(dialog)

    support.assert.same(duplicatedArgs, { "Source", "Copy" }, "Duplicate called with source/new names")
end)

os.exit(runner:run())
