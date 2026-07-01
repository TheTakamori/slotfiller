---@diagnostic disable: undefined-global
local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/[^/]+%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_full(root)

local API = SlotFiller.ClickBindingAPI
local CB  = SlotFiller.ClickBindings

local emptyCaches = support.empty_macro_caches

-- ---------------------------------------------------------------------------
-- ClickBindingAPI
-- ---------------------------------------------------------------------------

runner:test("IsSupported is false without C_ClickBindings", function()
    support.assert.isFalse(API.IsSupported(), "unsupported when C_ClickBindings absent")
end)

runner:test("IsSupported is true when the full API is present", function()
    _G.C_ClickBindings = { GetProfileInfo = function() end, SetProfileByInfo = function() end }
    support.assert.isTrue(API.IsSupported(), "supported when both functions exist")
    _G.C_ClickBindings = nil
end)

runner:test("GetMacroTypeValue falls back to 2 without an Enum table", function()
    support.assert.equal(API.GetMacroTypeValue(), 2, "fallback value")
end)

-- ---------------------------------------------------------------------------
-- ClickBindings:Scan
-- ---------------------------------------------------------------------------

runner:test("Scan returns nil when click bindings are unsupported", function()
    support.assert.isNil(CB:Scan(), "nil when C_ClickBindings absent")
end)

runner:test("Scan captures a non-macro binding by actionID", function()
    _G.C_ClickBindings = {
        GetProfileInfo = function()
            return { { type = 1, actionID = 133, button = "RightButton", modifiers = 0 } }
        end,
        SetProfileByInfo = function() end,
    }

    local entries = CB:Scan()

    _G.C_ClickBindings = nil

    support.assert.equal(#entries, 1,                  "one entry captured")
    support.assert.equal(entries[1].actionID, 133,     "actionID stored")
    support.assert.isNil(entries[1].isMacro,            "not flagged as macro")
end)

runner:test("Scan captures a macro binding by name/body/icon, not raw actionID", function()
    _G.C_ClickBindings = {
        GetProfileInfo = function()
            return { { type = 2, actionID = 5, button = "Button4", modifiers = 1 } }
        end,
        SetProfileByInfo = function() end,
    }
    _G.GetMacroInfo = function(id)
        if id == 5 then return "Heal", 1, "/cast Heal" end
        return nil
    end

    local entries = CB:Scan()

    _G.C_ClickBindings = nil
    _G.GetMacroInfo = nil

    support.assert.equal(#entries, 1,                "one entry captured")
    support.assert.isTrue(entries[1].isMacro,        "flagged as macro")
    support.assert.equal(entries[1].macroName, "Heal", "macro name captured")
    support.assert.isNil(entries[1].actionID,          "raw macro index not stored")
end)

runner:test("Scan drops a macro binding whose macro lookup fails", function()
    _G.C_ClickBindings = {
        GetProfileInfo = function()
            return { { type = 2, actionID = 99, button = "Button4", modifiers = 0 } }
        end,
        SetProfileByInfo = function() end,
    }
    _G.GetMacroInfo = function() return nil end

    local entries = CB:Scan()

    _G.C_ClickBindings = nil
    _G.GetMacroInfo = nil

    support.assert.equal(#entries, 0, "unresolvable macro binding dropped")
end)

-- ---------------------------------------------------------------------------
-- ClickBindings:Apply
-- ---------------------------------------------------------------------------

runner:test("Apply does nothing when entries are empty (additive, not destructive)", function()
    local called = false
    _G.C_ClickBindings = {
        GetProfileInfo = function() end,
        SetProfileByInfo = function() called = true end,
    }

    local errors = CB:Apply({}, emptyCaches())

    _G.C_ClickBindings = nil

    support.assert.equal(#errors, 0, "no errors")
    support.assert.isFalse(called, "SetProfileByInfo not called for an empty list")
end)

runner:test("Apply forwards non-macro bindings unchanged and calls SetProfileByInfo", function()
    local applied = nil
    _G.C_ClickBindings = {
        GetProfileInfo = function() end,
        SetProfileByInfo = function(entries) applied = entries end,
    }

    local errors = CB:Apply(
        { { bindingType = 1, button = "RightButton", modifiers = 0, actionID = 133 } },
        emptyCaches())

    _G.C_ClickBindings = nil

    support.assert.equal(#errors, 0,             "no errors")
    support.assert.equal(applied[1].actionID, 133, "actionID forwarded unchanged")
end)

runner:test("Apply resolves a macro binding and records an error when it can't be created", function()
    _G.C_ClickBindings = {
        GetProfileInfo = function() end,
        SetProfileByInfo = function() end,
    }
    _G.MAX_CHARACTER_MACROS = 18
    _G.GetNumMacros = function() return 0, 18 end  -- character macro cap full

    local errors = CB:Apply(
        { { bindingType = 2, button = "Button4", modifiers = 0, isMacro = true, macroName = "Heal", macroBody = "/cast Heal" } },
        emptyCaches())

    _G.C_ClickBindings = nil
    _G.MAX_CHARACTER_MACROS = nil
    _G.GetNumMacros = nil

    support.assert.equal(#errors, 1, "one error recorded")
    support.assert.isTrue(errors[1]:find("Heal") ~= nil, "error names the macro")
end)

runner:test("Apply merges saved entries over live bindings instead of replacing the whole profile", function()
    local applied = nil
    _G.C_ClickBindings = {
        -- A live binding on Button5 that the saved profile never captured.
        GetProfileInfo = function()
            return { { type = 1, actionID = 42, button = "Button5", modifiers = 0 } }
        end,
        SetProfileByInfo = function(entries) applied = entries end,
    }

    local errors = CB:Apply(
        { { bindingType = 1, button = "RightButton", modifiers = 0, actionID = 133 } },
        emptyCaches())

    _G.C_ClickBindings = nil

    support.assert.equal(#errors, 0, "no errors")

    local byButton = {}
    for _, entry in ipairs(applied) do
        byButton[entry.button] = entry
    end
    support.assert.equal(byButton["RightButton"].actionID, 133,
        "saved profile entry is present")
    support.assert.equal(byButton["Button5"].actionID, 42,
        "live binding the saved profile never captured survives the merge")
end)

runner:test("Apply overwrites a live binding on the same button+modifier with the saved entry", function()
    local applied = nil
    _G.C_ClickBindings = {
        GetProfileInfo = function()
            return { { type = 1, actionID = 999, button = "RightButton", modifiers = 0 } }
        end,
        SetProfileByInfo = function(entries) applied = entries end,
    }

    local errors = CB:Apply(
        { { bindingType = 1, button = "RightButton", modifiers = 0, actionID = 133 } },
        emptyCaches())

    _G.C_ClickBindings = nil

    support.assert.equal(#errors, 0, "no errors")
    support.assert.equal(#applied, 1, "same button+modifier key is replaced, not duplicated")
    support.assert.equal(applied[1].actionID, 133, "saved profile entry wins on a matching key")
end)

runner:test("Apply resolves a macro binding to a newly created macro's ID", function()
    local applied = nil
    _G.C_ClickBindings = {
        GetProfileInfo = function() end,
        SetProfileByInfo = function(entries) applied = entries end,
    }
    _G.MAX_CHARACTER_MACROS = 18
    _G.GetNumMacros = function() return 0, 0 end
    _G.CreateMacro = function() return 777 end

    local errors = CB:Apply(
        { { bindingType = 2, button = "Button4", modifiers = 0, isMacro = true, macroName = "Heal", macroBody = "/cast Heal" } },
        emptyCaches())

    _G.C_ClickBindings = nil
    _G.MAX_CHARACTER_MACROS = nil
    _G.GetNumMacros = nil
    _G.CreateMacro = nil

    support.assert.equal(#errors, 0,              "no errors")
    support.assert.equal(applied[1].actionID, 777, "resolved macro ID forwarded")
end)

os.exit(runner:run())
