local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/run%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_addon(root)

-- In the plain Lua test host, WoW globals (UnitClass, UnitName, GetRealmName, etc.)
-- are absent.  All Context functions that wrap WoW APIs must return nil / empty
-- without raising errors.

runner:test("GetPlayerName returns nil without WoW APIs", function()
    support.assert.isNil(SlotFiller.Context.GetPlayerName())
end)

runner:test("GetRealmName returns nil without WoW APIs", function()
    support.assert.isNil(SlotFiller.Context.GetRealmName())
end)

runner:test("GetClassName returns nil without WoW APIs", function()
    support.assert.isNil(SlotFiller.Context.GetClassName())
end)

runner:test("GetClassFile returns nil without WoW APIs", function()
    support.assert.isNil(SlotFiller.Context.GetClassFile())
end)

runner:test("GetClassID returns nil without WoW APIs", function()
    support.assert.isNil(SlotFiller.Context.GetClassID())
end)

runner:test("GetPlayerGUID returns nil without WoW APIs", function()
    support.assert.isNil(SlotFiller.Context.GetPlayerGUID())
end)

runner:test("GetAllClasses returns empty array without WoW APIs", function()
    local classes = SlotFiller.Context.GetAllClasses()
    support.assert.equal(type(classes), "table")
    support.assert.equal(#classes, 0)
end)

runner:test("GetSpecsForClass(nil) returns empty array", function()
    local specs = SlotFiller.Context.GetSpecsForClass(nil)
    support.assert.equal(type(specs), "table")
    support.assert.equal(#specs, 0)
end)

runner:test("GetSpecsForClass with classID returns empty array without WoW APIs", function()
    local specs = SlotFiller.Context.GetSpecsForClass(2)
    support.assert.equal(type(specs), "table")
    support.assert.equal(#specs, 0)
end)

runner:test("GetAllClasses returns sorted results when WoW APIs present", function()
    -- Stub minimal WoW class enumeration
    _G.GetNumClasses = function() return 3 end
    _G.GetClassInfo  = function(i)
        local t = {
            [1] = { "Warrior",  "WARRIOR"  },
            [2] = { "Mage",     "MAGE"     },
            [3] = { "Death Knight", "DEATHKNIGHT" },
        }
        local entry = t[i]
        return entry and entry[1], entry and entry[2]
    end

    local classes = SlotFiller.Context.GetAllClasses()
    support.assert.equal(#classes, 3, "three classes returned")
    support.assert.equal(classes[1].name, "Death Knight", "sorted first (alphabetical)")
    support.assert.equal(classes[2].name, "Mage",         "sorted second")
    support.assert.equal(classes[3].name, "Warrior",      "sorted third")
    support.assert.equal(classes[1].file, "DEATHKNIGHT",  "file stored")
    support.assert.equal(classes[1].id, 3, "id matches loop index")

    -- Clean up stubs
    _G.GetNumClasses = nil
    _G.GetClassInfo  = nil
end)

runner:test("GetSpecsForClass returns sorted specs when WoW APIs present", function()
    _G.GetNumSpecializationsForClassID  = function(_) return 2 end
    _G.GetSpecializationInfoForClassID  = function(_, i)
        local t = { [1] = "Retribution", [2] = "Holy" }
        return nil, t[i]
    end

    local specs = SlotFiller.Context.GetSpecsForClass(2)
    support.assert.equal(#specs, 2, "two specs returned")
    support.assert.equal(specs[1].name, "Retribution", "first spec")
    support.assert.equal(specs[2].name, "Holy",         "second spec")

    _G.GetNumSpecializationsForClassID  = nil
    _G.GetSpecializationInfoForClassID  = nil
end)

runner:test("GetScope returns nil when spec APIs absent", function()
    support.assert.isNil(SlotFiller.Context.GetScope())
end)

runner:test("IsCombatLocked returns falsy without WoW APIs", function()
    support.assert.isFalse(SlotFiller.Context.IsCombatLocked())
end)

os.exit(runner:run())
