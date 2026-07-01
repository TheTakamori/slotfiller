---@diagnostic disable: undefined-global
local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/[^/]+%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_addon(root)

-- Bootstrap.lua isn't loaded by support.load_addon/load_full (it's the
-- top-level event-wiring entry point, never called as a library by other
-- modules). Stub the WoW frame/event API it needs, then load it directly.
local registeredEvents = {}
local eventHandler = nil

_G.CreateFrame = function()
    local frame = {}
    function frame:RegisterEvent(event) registeredEvents[event] = true end
    function frame:SetScript(scriptType, fn)
        if scriptType == "OnEvent" then eventHandler = fn end
    end
    return frame
end

-- Bootstrap reaches into these UI modules directly; neither is loaded by
-- support.load_addon, so stub minimal versions before loading Bootstrap.
SlotFiller.UI = SlotFiller.UI or {}
SlotFiller.UI.MinimapButton = { Ensure = function() end }
SlotFiller.UI.SlashCommands.Register = function() end

-- ProfileActions:Load needs Restorer; not loaded by support.load_addon either.
SlotFiller.Restorer = { ApplyProfile = function() return true, 0 end }

do
    local chunk = assert(loadfile(root .. "/Core/Bootstrap.lua"))
    chunk("SlotFiller", SlotFiller)
end

local function fireEvent(event, arg1)
    eventHandler(nil, event, arg1)
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function stubContext(opts)
    opts = opts or {}
    SlotFiller.Context.IsCombatLocked = function() return opts.inCombat == true end
    SlotFiller.Context.GetSpecName    = function() return opts.specName end
    SlotFiller.Context.GetPlayerName  = function() return opts.name end
    SlotFiller.Context.GetRealmName   = function() return opts.realm end
    SlotFiller.Context.GetClassFile   = function() return opts.classFile end
    SlotFiller.Context.GetClassID     = function() return opts.classID end
end

local function stubAutoLoad(profileName)
    SlotFiller.AutoLoad.FindBestProfile = function() return profileName end
end

local function silencePrint()
    SlotFiller.Print = function() end
end

silencePrint()

-- ---------------------------------------------------------------------------
-- Event registration
-- ---------------------------------------------------------------------------

runner:test("Bootstrap registers all events it handles", function()
    support.assert.isTrue(registeredEvents["ADDON_LOADED"], "ADDON_LOADED registered")
    support.assert.isTrue(registeredEvents["PLAYER_LOGIN"], "PLAYER_LOGIN registered")
    support.assert.isTrue(registeredEvents["PLAYER_SPECIALIZATION_CHANGED"], "spec-change registered")
    support.assert.isTrue(registeredEvents["PLAYER_REGEN_ENABLED"], "combat-end registered")
end)

-- ---------------------------------------------------------------------------
-- ADDON_LOADED
-- ---------------------------------------------------------------------------

runner:test("ADDON_LOADED for a different addon is ignored", function()
    local called = false
    local originalRegister = SlotFiller.UI.SlashCommands.Register
    SlotFiller.UI.SlashCommands.Register = function() called = true end

    fireEvent("ADDON_LOADED", "SomeOtherAddon")

    SlotFiller.UI.SlashCommands.Register = originalRegister
    support.assert.isFalse(called, "slash commands not registered for a different addon")
end)

runner:test("ADDON_LOADED for SlotFiller registers slash commands and initializes the DB", function()
    local registered = false
    local originalRegister = SlotFiller.UI.SlashCommands.Register
    SlotFiller.UI.SlashCommands.Register = function() registered = true end

    SlotFiller.State:ResetForTests()
    fireEvent("ADDON_LOADED", "SlotFiller")

    SlotFiller.UI.SlashCommands.Register = originalRegister
    support.assert.isTrue(registered, "slash commands registered")
    support.assert.equal(type(_G.SlotFillerDB), "table", "DB initialized")
end)

-- ---------------------------------------------------------------------------
-- PLAYER_LOGIN — character tracking + minimap + auto-load
-- ---------------------------------------------------------------------------

runner:test("PLAYER_LOGIN tracks the logged-in character", function()
    stubContext({ name = "Bob", realm = "Realm", classFile = "PALADIN", classID = 2 })
    stubAutoLoad(nil)
    SlotFiller.State:ResetForTests()

    fireEvent("PLAYER_LOGIN")

    local known = SlotFiller.State:GetKnownCharacters()
    support.assert.equal(#known, 1, "one character tracked")
    support.assert.equal(known[1].key, "Bob-Realm", "tracked under Name-Realm key")
end)

runner:test("PLAYER_LOGIN ensures the minimap button", function()
    local called = false
    local originalEnsure = SlotFiller.UI.MinimapButton.Ensure
    SlotFiller.UI.MinimapButton.Ensure = function() called = true end

    stubContext({})
    stubAutoLoad(nil)
    fireEvent("PLAYER_LOGIN")

    SlotFiller.UI.MinimapButton.Ensure = originalEnsure
    support.assert.isTrue(called, "minimap button ensured on login")
end)

-- ---------------------------------------------------------------------------
-- Auto-load
-- ---------------------------------------------------------------------------

runner:test("auto-load does nothing without an active specialization", function()
    stubContext({ specName = nil })
    local findCalled = false
    SlotFiller.AutoLoad.FindBestProfile = function() findCalled = true end

    fireEvent("PLAYER_LOGIN")

    support.assert.isFalse(findCalled, "FindBestProfile not even consulted without a spec")
end)

runner:test("auto-load loads the best-matching profile and notifies listeners", function()
    stubContext({ specName = "Retribution", name = "Bob", realm = "Realm", classFile = "PALADIN" })
    stubAutoLoad("RetProfile")
    SlotFiller.State:ResetForTests()

    local loadedName = nil
    SlotFiller.ProfileActions.Load = function(_, name) loadedName = name; return true end
    local notified = false
    SlotFiller.Hooks.RegisterStateChanged(function() notified = true end)

    fireEvent("PLAYER_LOGIN")

    support.assert.equal(loadedName, "RetProfile", "matched profile loaded")
    support.assert.isTrue(notified, "state-changed listeners notified")
end)

runner:test("auto-load does not reload a profile that is already active", function()
    stubContext({ specName = "Retribution" })
    stubAutoLoad("AlreadyActive")
    SlotFiller.State:ResetForTests()
    SlotFiller.State:SetActiveProfile("AlreadyActive")

    local loadCalled = false
    SlotFiller.ProfileActions.Load = function() loadCalled = true end

    fireEvent("PLAYER_LOGIN")

    support.assert.isFalse(loadCalled, "no redundant reload of the already-active profile")
end)

-- ---------------------------------------------------------------------------
-- Combat retry
-- ---------------------------------------------------------------------------

runner:test("auto-load deferred in combat retries automatically after combat ends", function()
    local inCombat = true
    stubContext({ specName = "Retribution" })
    SlotFiller.Context.IsCombatLocked = function() return inCombat end
    stubAutoLoad("PostCombatProfile")
    SlotFiller.State:ResetForTests()

    local loadedName = nil
    SlotFiller.ProfileActions.Load = function(_, name) loadedName = name; return true end

    fireEvent("PLAYER_LOGIN")
    support.assert.isNil(loadedName, "no load attempted while still in combat")

    inCombat = false
    fireEvent("PLAYER_REGEN_ENABLED")

    support.assert.equal(loadedName, "PostCombatProfile", "retry after combat ends loads the matching profile")
end)

runner:test("PLAYER_REGEN_ENABLED is a no-op when no auto-load retry is pending", function()
    stubContext({ specName = nil })
    local findCalled = false
    SlotFiller.AutoLoad.FindBestProfile = function() findCalled = true end

    fireEvent("PLAYER_REGEN_ENABLED")

    support.assert.isFalse(findCalled, "no auto-load attempt when nothing was deferred")
end)

-- ---------------------------------------------------------------------------
-- PLAYER_SPECIALIZATION_CHANGED
-- ---------------------------------------------------------------------------

runner:test("spec change notifies state-changed listeners and re-attempts auto-load", function()
    stubContext({ specName = "Protection" })
    stubAutoLoad(nil)

    local notified = false
    SlotFiller.Hooks.RegisterStateChanged(function() notified = true end)

    fireEvent("PLAYER_SPECIALIZATION_CHANGED")

    support.assert.isTrue(notified, "state-changed listeners notified on spec change")
end)

os.exit(runner:run())
