---@diagnostic disable: undefined-global
local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/run%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_full(root)

local R = SlotFiller.Restorer
local C = SlotFiller.Constants

-- Macro cache/find/create tests live in tests/macro_resolver_spec.lua
-- (Core/MacroResolver.lua); the remaining tests here exercise ApplyProfile's
-- end-to-end behavior, which still depends on macro recreation indirectly.

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

-- ---------------------------------------------------------------------------
-- Contamination regression — pre-clear behaviour
-- ---------------------------------------------------------------------------

runner:test("empty slot in profile causes ClearSlot even when bar slot has content", function()
    local clearedSlots = {}
    local originalClearSlot = SlotFiller.ActionAPI.ClearSlot
    -- ClearSlot uses dot-notation (no self); first arg is actionID.
    SlotFiller.ActionAPI.ClearSlot = function(actionID)
        clearedSlots[actionID] = true
    end

    _G.GetMacroInfo = nil
    _G.MAX_ACCOUNT_MACROS = 0
    _G.MAX_CHARACTER_MACROS = 0

    -- Profile with nothing in slot 7 and nothing in slot 8.
    local profile = { slots = {} }
    R:ApplyProfile(profile)

    -- Restore before asserting so the stub never leaks into subsequent tests.
    SlotFiller.ActionAPI.ClearSlot = originalClearSlot

    support.assert.isTrue(clearedSlots[7] == true, "slot 7 cleared when profile has no entry")
    support.assert.isTrue(clearedSlots[8] == true, "slot 8 cleared when profile has no entry")
end)

runner:test("RestoreSlot pre-clears the slot before attempting pickup", function()
    local clearCount = 0
    local originalClearSlot = SlotFiller.ActionAPI.ClearSlot
    SlotFiller.ActionAPI.ClearSlot = function(actionID)
        if actionID == 5 then clearCount = clearCount + 1 end
    end
    local originalPickup = SlotFiller.ActionAPI.PickupItemID
    SlotFiller.ActionAPI.PickupItemID = function() return false end

    local caches = { spell = {}, flyout = {}, macroBody = {}, macroName = {}, macroID = {} }
    SlotFiller.State:ResetForTests()
    R:RestoreSlot(5, { type = C.ACTION_TYPE.ITEM, id = 999, name = "Missing Item" }, caches)

    -- Restore before asserting.
    SlotFiller.ActionAPI.ClearSlot    = originalClearSlot
    SlotFiller.ActionAPI.PickupItemID = originalPickup

    support.assert.equal(clearCount, 1, "ClearSlot called once before failed pickup")
end)

-- ---------------------------------------------------------------------------
-- Off-spec spell — silent skip
-- ---------------------------------------------------------------------------

runner:test("off-spec spell is silently skipped with no error", function()
    -- IsSpellRestorable returns false → skip with no error.
    local originalRestorable = SlotFiller.SpellBookAPI.IsSpellRestorable
    SlotFiller.SpellBookAPI.IsSpellRestorable = function() return false end

    _G.MAX_ACCOUNT_MACROS = 0
    _G.MAX_CHARACTER_MACROS = 0

    local profile = {
        slots = {
            [1] = { type = C.ACTION_TYPE.SPELL, id = 12345, name = "Paladin Spell" },
        },
    }
    local ok, errCount = R:ApplyProfile(profile)
    SlotFiller.SpellBookAPI.IsSpellRestorable = originalRestorable

    support.assert.equal(ok, true, "apply succeeds")
    support.assert.equal(errCount, 0, "no error for off-spec spell")
end)

-- ---------------------------------------------------------------------------
-- Zone ability — error when not restorable
-- ---------------------------------------------------------------------------

runner:test("zone ability failure records an error", function()
    -- Stub zone ability API to return nothing (not in a Draenor zone).
    _G.C_ZoneAbility = { GetActiveAbilities = function() return {} end }

    _G.MAX_ACCOUNT_MACROS = 0
    _G.MAX_CHARACTER_MACROS = 0

    local profile = {
        slots = {
            [32] = { type = C.ACTION_TYPE.SPELL, id = 161676, name = "Call to Arms", isZoneAbility = true },
        },
    }
    local ok, errCount = R:ApplyProfile(profile)
    _G.C_ZoneAbility = nil

    support.assert.equal(ok, true, "apply succeeds even with zone ability failure")
    support.assert.equal(errCount, 1, "one error for unrestorable zone ability")
    support.assert.isTrue(
        R:GetLastErrorsText():find("slot 32") ~= nil,
        "error message mentions the slot number")
end)

-- ---------------------------------------------------------------------------
-- Battle pet — success and failure
-- ---------------------------------------------------------------------------

runner:test("summonpet slot succeeds when pet is in the collection", function()
    _G.C_PetJournal = {
        PickupPet = function(guid)
            if guid == "BattlePet-0-00000B4B64D9" then
                _G._fakeCursor = "battlepet"
            end
        end,
    }
    _G.GetCursorInfo = function() return _G._fakeCursor end

    _G.MAX_ACCOUNT_MACROS = 0
    _G.MAX_CHARACTER_MACROS = 0

    local profile = {
        slots = {
            [48] = { type = C.ACTION_TYPE.SUMMONPET, id = "BattlePet-0-00000B4B64D9", name = "Wee Stinker" },
        },
    }
    local ok, errCount = R:ApplyProfile(profile)

    _G.C_PetJournal = nil
    _G.GetCursorInfo = nil
    _G._fakeCursor   = nil

    support.assert.equal(ok, true, "apply succeeds")
    support.assert.equal(errCount, 0, "no error when pet found")
end)

-- ---------------------------------------------------------------------------
-- SBA restores like an ordinary spell — no special relocation pass or
-- preservation guard.
-- ---------------------------------------------------------------------------

runner:test("RestoreSlot clears and restores an assistedcombat-tagged slot like any other spell", function()
    local cleared, placed = {}, {}
    local originalClearSlot = SlotFiller.ActionAPI.ClearSlot
    local originalPlaceSlot = SlotFiller.ActionAPI.PlaceSlot
    SlotFiller.ActionAPI.ClearSlot = function(actionID) cleared[actionID] = true end
    SlotFiller.ActionAPI.PlaceSlot = function(actionID) placed[actionID] = true end

    local originalPickupID = SlotFiller.ActionAPI.PickupSpellID
    SlotFiller.ActionAPI.PickupSpellID = function() return true end

    local caches = { spell = {}, flyout = {}, macroBody = {}, macroName = {}, macroID = {} }
    SlotFiller.State:ResetForTests()
    R:RestoreSlot(10, { type = C.ACTION_TYPE.SPELL, id = 12345, subType = C.ACTION_SUBTYPE.ASSISTEDCOMBAT }, caches)

    SlotFiller.ActionAPI.ClearSlot = originalClearSlot
    SlotFiller.ActionAPI.PlaceSlot = originalPlaceSlot
    SlotFiller.ActionAPI.PickupSpellID = originalPickupID

    support.assert.isTrue(cleared[10], "slot is cleared like any normal spell slot")
    support.assert.isTrue(placed[10], "captured spell is placed like any normal spell")
end)

runner:test("ApplyProfile no longer special-cases SBA slots into a separate pass", function()
    _G.MAX_ACCOUNT_MACROS = 0
    _G.MAX_CHARACTER_MACROS = 0

    local originalPickupID = SlotFiller.ActionAPI.PickupSpellID
    SlotFiller.ActionAPI.PickupSpellID = function() return true end

    local profile = { slots = {
        [10] = { type = C.ACTION_TYPE.SPELL, id = 12345, subType = C.ACTION_SUBTYPE.ASSISTEDCOMBAT },
    }}
    local ok, errCount = R:ApplyProfile(profile)

    SlotFiller.ActionAPI.PickupSpellID = originalPickupID
    _G.MAX_ACCOUNT_MACROS = nil
    _G.MAX_CHARACTER_MACROS = nil

    support.assert.equal(ok, true, "apply succeeds")
    support.assert.equal(errCount, 0, "captured SBA-suggested spell restores cleanly via the normal spell path")
end)

-- ---------------------------------------------------------------------------
-- Sequential load contamination regression (rule f)
-- ---------------------------------------------------------------------------

runner:test("loading profile B after profile A never leaves A stale content in empty B slot", function()
    _G.MAX_ACCOUNT_MACROS = 0
    _G.MAX_CHARACTER_MACROS = 0

    local clearCounts = {}
    local originalClearSlot = SlotFiller.ActionAPI.ClearSlot
    SlotFiller.ActionAPI.ClearSlot = function(actionID)
        clearCounts[actionID] = (clearCounts[actionID] or 0) + 1
    end

    local originalPickup = SlotFiller.ActionAPI.PickupItemID
    SlotFiller.ActionAPI.PickupItemID = function() return false end

    -- Profile A: slot 5 has an item that will fail to restore.
    local profileA = { slots = {
        [5] = { type = C.ACTION_TYPE.ITEM, id = 99999, name = "Profile A Item" },
    }}
    R:ApplyProfile(profileA)

    -- Profile B: slot 5 intentionally absent (empty bar slot).
    local profileB = { slots = {} }
    R:ApplyProfile(profileB)

    SlotFiller.ActionAPI.ClearSlot    = originalClearSlot
    SlotFiller.ActionAPI.PickupItemID = originalPickup

    -- Slot 5 must be cleared in profile A's load (pre-clear before failed pickup)
    -- AND in profile B's load (empty sweep of all slots).
    support.assert.isTrue(
        (clearCounts[5] or 0) >= 2,
        "slot 5 swept in both profile A and profile B loads; stale A content cannot survive")
end)

-- ---------------------------------------------------------------------------
-- Unknown action type (rule h)
-- ---------------------------------------------------------------------------

runner:test("ApplyProfile logs a detailed error for UNKNOWN action type", function()
    _G.MAX_ACCOUNT_MACROS = 0
    _G.MAX_CHARACTER_MACROS = 0

    local profile = {
        slots = {
            [20] = {
                type    = C.ACTION_TYPE.UNKNOWN,
                rawType = "futurenewtype",
                id      = 42,
            },
        },
    }
    local ok, errCount = R:ApplyProfile(profile)

    support.assert.equal(ok, true, "apply returns true")
    support.assert.equal(errCount, 1, "one error for unknown type")
    local errText = R:GetLastErrorsText()
    support.assert.isTrue(errText:find("futurenewtype") ~= nil, "error names the raw type")
    support.assert.isTrue(errText:find("slot 20") ~= nil, "error names the slot")
end)

runner:test("summonpet slot records an error when pet is not in the collection", function()
    _G.C_PetJournal = { PickupPet = function() end }  -- pickup does nothing; cursor stays nil
    _G.GetCursorInfo = function() return nil end

    _G.MAX_ACCOUNT_MACROS = 0
    _G.MAX_CHARACTER_MACROS = 0

    local profile = {
        slots = {
            [48] = { type = C.ACTION_TYPE.SUMMONPET, id = "BattlePet-0-DEADBEEF0000", name = "Gone Pet" },
        },
    }
    local ok, errCount = R:ApplyProfile(profile)

    _G.C_PetJournal  = nil
    _G.GetCursorInfo = nil

    support.assert.equal(ok, true, "apply still returns true")
    support.assert.equal(errCount, 1, "one error for missing pet")
    support.assert.isTrue(
        R:GetLastErrorsText():find("slot 48") ~= nil,
        "error mentions slot 48")
end)

-- ---------------------------------------------------------------------------
-- Character-specific macro recreation
-- ---------------------------------------------------------------------------

-- Helper: install a macro environment where no macros pre-exist and
-- CreateMacro will succeed, returning newID and capturing call arguments.
local function setup_char_macro_env(newID, numUsed)
    numUsed = numUsed or 0
    _G.MAX_ACCOUNT_MACROS  = 120
    _G.MAX_CHARACTER_MACROS = 18
    _G.GetMacroInfo = function() return nil end
    _G.GetNumMacros = function() return 0, numUsed end

    local captured = {}
    _G.CreateMacro = function(name, icon, body, perChar)
        captured.name    = name
        captured.icon    = icon
        captured.body    = body
        captured.perChar = perChar
        return newID
    end

    local pickedUp = nil
    _G.PickupMacro   = function(id) pickedUp = id end
    _G.GetCursorInfo = function() return pickedUp and "macro" or nil end

    return captured, function() return pickedUp end
end

local function teardown_char_macro_env()
    _G.MAX_ACCOUNT_MACROS   = nil
    _G.MAX_CHARACTER_MACROS = nil
    _G.GetMacroInfo         = nil
    _G.GetNumMacros         = nil
    _G.CreateMacro          = nil
    _G.PickupMacro          = nil
    _G.GetCursorInfo        = nil
end

runner:test("perCharacter macro not found on this character is created and placed", function()
    local captured, pickedUpFn = setup_char_macro_env(121, 0)

    local profile = {
        slots = {
            [4] = {
                type         = C.ACTION_TYPE.MACRO,
                macroID      = 121,
                name         = "MyMacro",
                body         = SlotFiller.Normalizer.CompressMacroText("/cast Fireball"),
                icon         = 134414,
                perCharacter = true,
            },
        },
    }
    local ok, errCount = R:ApplyProfile(profile)
    teardown_char_macro_env()

    support.assert.equal(ok, true, "apply succeeds")
    support.assert.equal(errCount, 0, "no error when macro is recreated")
    support.assert.equal(captured.name,    "MyMacro", "correct name passed to CreateMacro")
    support.assert.equal(captured.icon,    134414,    "correct icon passed to CreateMacro")
    support.assert.equal(captured.perChar, true,      "created as character-specific")
    support.assert.equal(pickedUpFn(),     121,       "newly created macro was picked up")
end)

runner:test("perCharacter macro body is uncompressed before passing to CreateMacro", function()
    local captured, _ = setup_char_macro_env(121, 0)

    local compressed = SlotFiller.Normalizer.CompressMacroText("/cast Fire\n/say Hello")
    local profile = {
        slots = {
            [1] = {
                type         = C.ACTION_TYPE.MACRO,
                macroID      = 125,
                name         = "TwoLine",
                body         = compressed,
                perCharacter = true,
            },
        },
    }
    R:ApplyProfile(profile)
    teardown_char_macro_env()

    support.assert.equal(captured.body, "/cast Fire\n/say Hello",
        "body is uncompressed before passing to CreateMacro")
end)

runner:test("perCharacter macro uses fallback icon when profile has no icon", function()
    local captured, _ = setup_char_macro_env(121, 0)

    local profile = {
        slots = {
            [2] = {
                type         = C.ACTION_TYPE.MACRO,
                macroID      = 122,
                name         = "NoIcon",
                body         = SlotFiller.Normalizer.CompressMacroText("/cast Ice"),
                -- icon intentionally absent
                perCharacter = true,
            },
        },
    }
    R:ApplyProfile(profile)
    teardown_char_macro_env()

    support.assert.equal(captured.icon, "INV_MISC_QUESTIONMARK",
        "fallback icon used when slot has no icon")
end)

runner:test("perCharacter macro creation is skipped when character is at the limit", function()
    local createCalled = false
    _G.MAX_ACCOUNT_MACROS   = 120
    _G.MAX_CHARACTER_MACROS = 18
    _G.GetMacroInfo         = function() return nil end
    _G.GetNumMacros         = function() return 0, 18 end  -- all 18 slots used
    _G.CreateMacro          = function() createCalled = true return 130 end

    local profile = {
        slots = {
            [4] = {
                type         = C.ACTION_TYPE.MACRO,
                macroID      = 125,
                name         = "OverLimit",
                body         = SlotFiller.Normalizer.CompressMacroText("/cast Frostbolt"),
                perCharacter = true,
            },
        },
    }
    local ok, errCount = R:ApplyProfile(profile)

    _G.MAX_ACCOUNT_MACROS   = nil
    _G.MAX_CHARACTER_MACROS = nil
    _G.GetMacroInfo         = nil
    _G.GetNumMacros         = nil
    _G.CreateMacro          = nil

    support.assert.equal(ok, true, "apply returns true even when limit is full")
    support.assert.equal(errCount, 1, "one error recorded for limit-blocked creation")
    support.assert.isFalse(createCalled, "CreateMacro must not be called when limit is full")
    support.assert.isTrue(
        R:GetLastErrorsText():find("limit") ~= nil,
        "error message mentions the limit")
    support.assert.isTrue(
        R:GetLastErrorsText():find("slot 4") ~= nil,
        "error message mentions the slot")
end)

runner:test("same perCharacter macro on two slots: created once, not twice", function()
    local createCount = 0
    _G.MAX_ACCOUNT_MACROS   = 120
    _G.MAX_CHARACTER_MACROS = 18
    _G.GetMacroInfo         = function() return nil end
    _G.GetNumMacros         = function() return 0, 0 end
    _G.CreateMacro          = function()
        createCount = createCount + 1
        return 121
    end
    _G.PickupMacro   = function(id) _G._pickedMacro = id end
    _G.GetCursorInfo = function() return _G._pickedMacro and "macro" or nil end

    local compressed = SlotFiller.Normalizer.CompressMacroText("/cast Fireball")
    local profile = {
        slots = {
            [4] = { type = C.ACTION_TYPE.MACRO, macroID = 125, name = "Multi",
                    body = compressed, perCharacter = true },
            [8] = { type = C.ACTION_TYPE.MACRO, macroID = 125, name = "Multi",
                    body = compressed, perCharacter = true },
        },
    }
    local ok, errCount = R:ApplyProfile(profile)

    _G.MAX_ACCOUNT_MACROS   = nil
    _G.MAX_CHARACTER_MACROS = nil
    _G.GetMacroInfo         = nil
    _G.GetNumMacros         = nil
    _G.CreateMacro          = nil
    _G.PickupMacro          = nil
    _G.GetCursorInfo        = nil
    _G._pickedMacro         = nil

    support.assert.equal(ok, true, "apply succeeds")
    support.assert.equal(errCount, 0, "no errors for either slot")
    support.assert.equal(createCount, 1, "CreateMacro called exactly once even though macro appears on two slots")
end)

runner:test("global macro missing from this character reports an error without attempting creation", function()
    local createCalled = false
    _G.MAX_ACCOUNT_MACROS   = 120
    _G.MAX_CHARACTER_MACROS = 0
    _G.GetMacroInfo         = function() return nil end
    _G.GetNumMacros         = function() return 0, 0 end
    _G.CreateMacro          = function() createCalled = true return 5 end

    local profile = {
        slots = {
            [7] = {
                type    = C.ACTION_TYPE.MACRO,
                macroID = 5,
                name    = "GlobalGone",
                body    = SlotFiller.Normalizer.CompressMacroText("/cast Fire"),
                -- perCharacter is absent → global macro
            },
        },
    }
    local ok, errCount = R:ApplyProfile(profile)

    _G.MAX_ACCOUNT_MACROS   = nil
    _G.MAX_CHARACTER_MACROS = nil
    _G.GetMacroInfo         = nil
    _G.GetNumMacros         = nil
    _G.CreateMacro          = nil

    support.assert.equal(ok, true, "apply returns true")
    support.assert.equal(errCount, 1, "one error for missing global macro")
    support.assert.isFalse(createCalled, "CreateMacro must not be called for global macros")
end)

runner:test("perCharacter macro with no name skips creation and records an error", function()
    local createCalled = false
    _G.MAX_ACCOUNT_MACROS   = 120
    _G.MAX_CHARACTER_MACROS = 18
    _G.GetMacroInfo         = function() return nil end
    _G.GetNumMacros         = function() return 0, 0 end
    _G.CreateMacro          = function() createCalled = true return 121 end

    local profile = {
        slots = {
            [9] = {
                type         = C.ACTION_TYPE.MACRO,
                macroID      = 130,
                -- name intentionally absent
                body         = SlotFiller.Normalizer.CompressMacroText("/cast X"),
                perCharacter = true,
            },
        },
    }
    local ok, errCount = R:ApplyProfile(profile)

    _G.MAX_ACCOUNT_MACROS   = nil
    _G.MAX_CHARACTER_MACROS = nil
    _G.GetMacroInfo         = nil
    _G.GetNumMacros         = nil
    _G.CreateMacro          = nil

    support.assert.equal(ok, true, "apply returns true")
    support.assert.equal(errCount, 1, "one error when name is absent")
    support.assert.isFalse(createCalled,
        "CreateMacro must not be called when slot has no name")
end)

runner:test("ActionAPI.CreateCharacterMacro returns limit reason when at capacity", function()
    _G.MAX_CHARACTER_MACROS = 18
    _G.GetNumMacros = function() return 0, 18 end
    _G.CreateMacro  = function() return 121 end

    local id, reason = SlotFiller.ActionAPI.CreateCharacterMacro("X", nil, "")

    _G.MAX_CHARACTER_MACROS = nil
    _G.GetNumMacros = nil
    _G.CreateMacro  = nil

    support.assert.isNil(id,              "no id returned when at limit")
    support.assert.equal(reason, "limit", "reason is 'limit'")
end)

runner:test("ActionAPI.CreateCharacterMacro returns unavailable when API missing", function()
    -- Ensure CreateMacro is absent
    local saved = _G.CreateMacro
    _G.CreateMacro  = nil
    _G.GetNumMacros = nil

    local id, reason = SlotFiller.ActionAPI.CreateCharacterMacro("X", nil, "")

    _G.CreateMacro  = saved

    support.assert.isNil(id,                   "no id without API")
    support.assert.equal(reason, "unavailable", "reason is 'unavailable'")
end)

runner:test("ActionAPI.CreateCharacterMacro returns new macroID on success", function()
    _G.MAX_CHARACTER_MACROS = 18
    _G.GetNumMacros = function() return 0, 0 end
    _G.CreateMacro  = function(name, icon, body, perChar)
        return 121
    end

    local id, reason = SlotFiller.ActionAPI.CreateCharacterMacro("Test", 134414, "/cast Fire")

    _G.MAX_CHARACTER_MACROS = nil
    _G.GetNumMacros = nil
    _G.CreateMacro  = nil

    support.assert.equal(id,     121, "macroID returned on success")
    support.assert.isNil(reason,      "no error reason on success")
end)

-- ---------------------------------------------------------------------------
-- ApplyProfile — petSlots wiring
-- ---------------------------------------------------------------------------

runner:test("ApplyProfile applies petSlots via PetBar when present", function()
    _G.MAX_ACCOUNT_MACROS = 0
    _G.MAX_CHARACTER_MACROS = 0

    local applied = nil
    local originalApply = SlotFiller.PetBar.Apply
    SlotFiller.PetBar.Apply = function(_, petSlots) applied = petSlots end

    local profile = { slots = {}, petSlots = { [1] = { type = "spell", spellID = 5 } } }
    R:ApplyProfile(profile)

    SlotFiller.PetBar.Apply = originalApply

    support.assert.equal(applied[1].spellID, 5, "petSlots forwarded to PetBar:Apply")
end)

runner:test("ApplyProfile does not call PetBar:Apply when profile has no petSlots", function()
    _G.MAX_ACCOUNT_MACROS = 0
    _G.MAX_CHARACTER_MACROS = 0

    local called = false
    local originalApply = SlotFiller.PetBar.Apply
    SlotFiller.PetBar.Apply = function() called = true end

    R:ApplyProfile({ slots = {} })

    SlotFiller.PetBar.Apply = originalApply

    support.assert.isFalse(called, "PetBar:Apply skipped without petSlots")
end)

-- ---------------------------------------------------------------------------
-- ApplyProfile — clickBindings wiring
-- ---------------------------------------------------------------------------

runner:test("ApplyProfile applies clickBindings via ClickBindings and records returned errors", function()
    _G.MAX_ACCOUNT_MACROS = 0
    _G.MAX_CHARACTER_MACROS = 0

    local receivedEntries = nil
    local originalApply = SlotFiller.ClickBindings.Apply
    SlotFiller.ClickBindings.Apply = function(_, entries)
        receivedEntries = entries
        return { "click binding problem" }
    end

    local profile = { slots = {}, clickBindings = { { bindingType = 1, button = "Button4" } } }
    local ok, errCount = R:ApplyProfile(profile)

    SlotFiller.ClickBindings.Apply = originalApply

    support.assert.equal(ok, true, "apply succeeds")
    support.assert.equal(errCount, 1, "click binding error counted")
    support.assert.equal(receivedEntries[1].button, "Button4", "clickBindings forwarded")
    support.assert.isTrue(R:GetLastErrorsText():find("click binding problem") ~= nil,
        "click binding error message recorded")
end)

runner:test("ApplyProfile does not call ClickBindings:Apply when profile has no clickBindings", function()
    _G.MAX_ACCOUNT_MACROS = 0
    _G.MAX_CHARACTER_MACROS = 0

    local called = false
    local originalApply = SlotFiller.ClickBindings.Apply
    SlotFiller.ClickBindings.Apply = function() called = true return {} end

    R:ApplyProfile({ slots = {} })

    SlotFiller.ClickBindings.Apply = originalApply

    support.assert.isFalse(called, "ClickBindings:Apply skipped without clickBindings")
end)

os.exit(runner:run())
