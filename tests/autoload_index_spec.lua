---@diagnostic disable: undefined-global
local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/[^/]+%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_addon(root)
-- AutoLoadIndex isn't loaded by load_addon/load_full (UI-adjacent Core module
-- pulled in directly by UI/MainFrame.lua in-game); load it explicitly here.
do
    local chunk = assert(loadfile(root .. "/Core/AutoLoadIndex.lua"))
    chunk("SlotFiller", SlotFiller)
end

local Index = SlotFiller.AutoLoadIndex

-- Stub class/spec/character data so tests don't depend on real WoW globals.
local function stubContext()
    SlotFiller.Context.GetAllClasses = function()
        return {
            { name = "Paladin", file = "PALADIN", id = 2 },
            { name = "Warlock", file = "WARLOCK", id = 9 },
        }
    end
    SlotFiller.Context.GetSpecsForClass = function(classID)
        if classID == 2 then
            return {
                { name = "Holy",        index = 1 },
                { name = "Protection",  index = 2 },
                { name = "Retribution", index = 3 },
            }
        end
        if classID == 9 then
            return {
                { name = "Affliction", index = 1 },
                { name = "Demonology", index = 2 },
                { name = "Destruction", index = 3 },
            }
        end
        return {}
    end
end

local function stubKnownCharacters(list)
    SlotFiller.State.GetKnownCharacters = function() return list end
end

stubContext()

-- ---------------------------------------------------------------------------
-- GetEligibleClasses
-- ---------------------------------------------------------------------------

runner:test("GetEligibleClasses returns every class when no character is selected", function()
    local classes = Index.GetEligibleClasses({})
    support.assert.equal(#classes, 2, "all classes eligible with no character filter")
end)

runner:test("GetEligibleClasses restricts to classes played by selected characters", function()
    stubKnownCharacters({
        { key = "Bob-Realm",   file = "PALADIN" },
        { key = "Eve-Realm",   file = "WARLOCK" },
    })
    local classes = Index.GetEligibleClasses({ ["Bob-Realm"] = true })
    support.assert.equal(#classes, 1, "only the selected character's class is eligible")
    support.assert.equal(classes[1].file, "PALADIN", "Paladin is the eligible class")
end)

runner:test("GetEligibleClasses dedupes characters sharing a class", function()
    stubKnownCharacters({
        { key = "Bob-Realm",  file = "PALADIN" },
        { key = "Carl-Realm", file = "PALADIN" },
    })
    local classes = Index.GetEligibleClasses({ ["Bob-Realm"] = true, ["Carl-Realm"] = true })
    support.assert.equal(#classes, 1, "PALADIN listed once even though two selected characters share it")
end)

-- ---------------------------------------------------------------------------
-- GetEligibleSpecs
-- ---------------------------------------------------------------------------

runner:test("GetEligibleSpecs returns no specs when no class is selected", function()
    local specs = Index.GetEligibleSpecs({})
    support.assert.equal(#specs, 0, "no specs eligible without a selected class")
end)

runner:test("GetEligibleSpecs returns specs for every selected class", function()
    local specs = Index.GetEligibleSpecs({ PALADIN = true })
    support.assert.equal(#specs, 3, "all three Paladin specs eligible")
    support.assert.equal(specs[1].key, "Holy", "key is the bare spec name")
    support.assert.equal(specs[1].label, "Paladin — Holy", "label includes class name")
end)

runner:test("GetEligibleSpecs combines specs across multiple selected classes", function()
    local specs = Index.GetEligibleSpecs({ PALADIN = true, WARLOCK = true })
    support.assert.equal(#specs, 6, "specs from both classes included")
end)

-- ---------------------------------------------------------------------------
-- PruneInvalidClasses
-- ---------------------------------------------------------------------------

runner:test("PruneInvalidClasses is a no-op with no character selected", function()
    local selectedClasses = { WARLOCK = true }
    Index.PruneInvalidClasses({}, selectedClasses)
    support.assert.isTrue(selectedClasses.WARLOCK, "class selection untouched when no character filter is active")
end)

runner:test("PruneInvalidClasses removes a class no longer eligible for the selected character", function()
    stubKnownCharacters({
        { key = "Bob-Realm", file = "PALADIN" },
    })
    local selectedChars   = { ["Bob-Realm"] = true }
    local selectedClasses = { PALADIN = true, WARLOCK = true }
    Index.PruneInvalidClasses(selectedChars, selectedClasses)
    support.assert.isTrue(selectedClasses.PALADIN, "Paladin stays selected (Bob plays it)")
    support.assert.isNil(selectedClasses.WARLOCK, "Warlock pruned (Bob doesn't play it)")
end)

-- ---------------------------------------------------------------------------
-- PruneInvalidSpecs
-- ---------------------------------------------------------------------------

runner:test("PruneInvalidSpecs clears all specs when no class is selected", function()
    local selectedSpecs = { Holy = true }
    Index.PruneInvalidSpecs({}, selectedSpecs)
    support.assert.isNil(selectedSpecs.Holy, "spec cleared once its class is deselected")
end)

runner:test("PruneInvalidSpecs removes a spec that no longer belongs to a selected class", function()
    local selectedClasses = { PALADIN = true }
    local selectedSpecs   = { Holy = true, Affliction = true }
    Index.PruneInvalidSpecs(selectedClasses, selectedSpecs)
    support.assert.isTrue(selectedSpecs.Holy, "Holy stays selected (belongs to Paladin)")
    support.assert.isNil(selectedSpecs.Affliction, "Affliction pruned (belongs to deselected Warlock)")
end)

os.exit(runner:run())
