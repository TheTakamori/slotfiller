local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/run%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_addon(root)

runner:test("saves and loads profiles", function()
    SlotFiller.State:ResetForTests()
    local profile = {
        savedAt = 100,
        slots = {
            [1] = { type = "spell", id = 116, name = "Frostbolt" },
        },
    }
    SlotFiller.State:SetProfile("Raid", profile)
    support.assert.same(SlotFiller.State:GetProfile("Raid"), profile, "profile stored")
    support.assert.equal(SlotFiller.State:ListProfileNames()[1], "Raid", "profile listed")
end)

runner:test("renames and duplicates profiles", function()
    SlotFiller.State:ResetForTests()
    SlotFiller.State:SetProfile("A", { savedAt = 1, slots = { [2] = { type = "spell", id = 1, name = "A" } } })

    local renamed, reason = SlotFiller.State:RenameProfile("A", "B")
    support.assert.equal(renamed, true, "rename ok")
    support.assert.isNil(reason, "no rename reason")
    support.assert.isNil(SlotFiller.State:GetProfile("A"), "old name removed")
    support.assert.equal(SlotFiller.State:GetProfile("B").slots[2].name, "A", "renamed profile kept data")

    local duplicated, dupReason = SlotFiller.State:DuplicateProfile("B", "C")
    support.assert.equal(duplicated, true, "duplicate ok")
    support.assert.isNil(dupReason, "no duplicate reason")
    support.assert.equal(SlotFiller.State:GetProfile("C").slots[2].name, "A", "duplicate copied data")
end)

runner:test("profiles are shared account-wide", function()
    SlotFiller.State:ResetForTests()
    SlotFiller.State:SetProfile("Shared", { savedAt = 1, slots = {} })
    support.assert.isTrue(SlotFiller.State:GetProfile("Shared") ~= nil, "profile visible globally")
end)

runner:test("deletes profile and clears active when deleted", function()
    SlotFiller.State:ResetForTests()
    SlotFiller.State:SetProfile("Target", { savedAt = 1, slots = {} })
    SlotFiller.State:SetActiveProfile("Target")
    support.assert.equal(SlotFiller.State:GetActiveProfileName(), "Target", "active set before delete")

    local deleted = SlotFiller.State:DeleteProfile("Target")
    support.assert.equal(deleted, true, "delete returns true")
    support.assert.isNil(SlotFiller.State:GetProfile("Target"), "profile removed")
    support.assert.isNil(SlotFiller.State:GetActiveProfileName(), "active cleared after delete")

    local again = SlotFiller.State:DeleteProfile("Target")
    support.assert.equal(again, false, "delete missing returns false")
end)

runner:test("SetActiveProfile and GetActiveProfileName", function()
    SlotFiller.State:ResetForTests()
    SlotFiller.State:SetProfile("A", { savedAt = 1, slots = {} })
    SlotFiller.State:SetProfile("B", { savedAt = 2, slots = {} })

    support.assert.isNil(SlotFiller.State:GetActiveProfileName(), "no active initially")
    SlotFiller.State:SetActiveProfile("A")
    support.assert.equal(SlotFiller.State:GetActiveProfileName(), "A", "active is A")
    SlotFiller.State:SetActiveProfile("B")
    support.assert.equal(SlotFiller.State:GetActiveProfileName(), "B", "active switched to B")
end)

runner:test("ListProfileNames returns case-insensitive sorted order", function()
    SlotFiller.State:ResetForTests()
    SlotFiller.State:SetProfile("Zebra",  { savedAt = 1, slots = {} })
    SlotFiller.State:SetProfile("alpha",  { savedAt = 2, slots = {} })
    SlotFiller.State:SetProfile("Middle", { savedAt = 3, slots = {} })

    local names = SlotFiller.State:ListProfileNames()
    support.assert.equal(#names, 3, "three names returned")
    support.assert.equal(names[1], "alpha",  "alpha first (case-insensitive)")
    support.assert.equal(names[2], "Middle", "Middle second")
    support.assert.equal(names[3], "Zebra",  "Zebra last")
end)

-- (Active-profile-tracking and missing/exists reason-code cases for rename
-- are covered by the dedicated "── RenameProfile ──" block below, rather
-- than duplicated here.)

runner:test("minimap hidden state persists and defaults to false", function()
    SlotFiller.State:ResetForTests()
    support.assert.equal(SlotFiller.State:IsMinimapHidden(), false, "not hidden by default")
    SlotFiller.State:SetMinimapHidden(true)
    support.assert.equal(SlotFiller.State:IsMinimapHidden(), true, "hidden after set")
    SlotFiller.State:SetMinimapHidden(false)
    support.assert.equal(SlotFiller.State:IsMinimapHidden(), false, "visible after clear")
end)

runner:test("minimap angle persists and defaults to Constants default", function()
    SlotFiller.State:ResetForTests()
    local defaultAngle = SlotFiller.Defaults.Get().minimap.angle
    support.assert.equal(SlotFiller.State:GetMinimapAngle(), defaultAngle, "default angle matches Defaults")
    SlotFiller.State:SetMinimapAngle(135)
    support.assert.equal(SlotFiller.State:GetMinimapAngle(), 135, "angle stored correctly")
end)

-- ── GetDB caching ──────────────────────────────────────────────────────────

runner:test("GetDB merges defaults once and returns the same table on later calls", function()
    SlotFiller.State:ResetForTests()
    local first = SlotFiller.State:GetDB()
    first.profiles.Sentinel = { savedAt = 1, slots = {} }

    local second = SlotFiller.State:GetDB()
    support.assert.isTrue(second == first, "GetDB returns the same cached table identity")
    support.assert.equal(second.profiles.Sentinel.savedAt, 1,
        "mutations through one GetDB() call are visible through a later call")
end)

-- ── GetKnownCharacters caching ─────────────────────────────────────────────

runner:test("GetKnownCharacters caches the sorted list across calls", function()
    SlotFiller.State:ResetForTests()
    SlotFiller.State:TrackCharacter("Bob-Realm", "PALADIN", 2)

    local first  = SlotFiller.State:GetKnownCharacters()
    local second = SlotFiller.State:GetKnownCharacters()
    support.assert.isTrue(first == second, "same cached list returned until invalidated")
end)

runner:test("TrackCharacter invalidates the GetKnownCharacters cache", function()
    SlotFiller.State:ResetForTests()
    SlotFiller.State:TrackCharacter("Bob-Realm", "PALADIN", 2)
    local before = SlotFiller.State:GetKnownCharacters()
    support.assert.equal(#before, 1, "one character before tracking a second")

    SlotFiller.State:TrackCharacter("Eve-Realm", "WARLOCK", 9)
    local after = SlotFiller.State:GetKnownCharacters()
    support.assert.equal(#after, 2, "newly tracked character appears after invalidation")
end)

runner:test("TrackCharacter stores and GetKnownCharacters returns sorted list", function()
    SlotFiller.State:ResetForTests()
    SlotFiller.State:TrackCharacter("Zebra-Realm", "WARRIOR",  2)
    SlotFiller.State:TrackCharacter("Alpha-Realm", "PALADIN",  4)
    SlotFiller.State:TrackCharacter("Middle-Realm", "MAGE",    8)

    local chars = SlotFiller.State:GetKnownCharacters()
    support.assert.equal(#chars, 3, "three characters tracked")
    support.assert.equal(chars[1].key, "Alpha-Realm",  "sorted first")
    support.assert.equal(chars[2].key, "Middle-Realm", "sorted second")
    support.assert.equal(chars[3].key, "Zebra-Realm",  "sorted third")
    support.assert.equal(chars[1].file, "PALADIN", "class file stored")
    support.assert.equal(chars[1].classID, 4, "classID stored")
end)

runner:test("TrackCharacter upserts — re-tracking same key updates fields", function()
    SlotFiller.State:ResetForTests()
    SlotFiller.State:TrackCharacter("Bob-Realm", "PALADIN", 4)
    SlotFiller.State:TrackCharacter("Bob-Realm", "WARRIOR", 2)

    local chars = SlotFiller.State:GetKnownCharacters()
    support.assert.equal(#chars, 1, "still one character")
    support.assert.equal(chars[1].file, "WARRIOR", "class updated to latest value")
end)

runner:test("GetProfileAutoLoad returns empty tables for unknown profile", function()
    SlotFiller.State:ResetForTests()
    local al = SlotFiller.State:GetProfileAutoLoad("Ghost")
    support.assert.equal(al.enabled, false, "enabled defaults to false")
    support.assert.same(al.characters, {})
    support.assert.same(al.classes,    {})
    support.assert.same(al.specs,      {})
end)

runner:test("GetProfileAutoLoad default tables are independent across calls", function()
    SlotFiller.State:ResetForTests()
    local first  = SlotFiller.State:GetProfileAutoLoad("Ghost")
    local second = SlotFiller.State:GetProfileAutoLoad("AlsoGhost")
    first.characters[#first.characters + 1] = "Mutated"
    support.assert.same(second.characters, {}, "mutating one default does not affect another call's result")
end)

runner:test("GetProfileAutoLoad default tables are independent for a profile with no autoLoad table", function()
    SlotFiller.State:ResetForTests()
    SlotFiller.State:SetProfile("NoAutoLoad", { savedAt = 1, slots = {} })
    local first  = SlotFiller.State:GetProfileAutoLoad("NoAutoLoad")
    local second = SlotFiller.State:GetProfileAutoLoad("NoAutoLoad")
    first.classes[#first.classes + 1] = "PALADIN"
    support.assert.same(second.classes, {}, "separate calls never share the same default table")
end)

runner:test("GetProfileAutoLoad returns independent copies, not live references, for a saved config", function()
    SlotFiller.State:ResetForTests()
    SlotFiller.State:SetProfile("MyProfile", { savedAt = 1, slots = {} })
    SlotFiller.State:SetProfileAutoLoad("MyProfile", {
        enabled = true, characters = { "Bob-Realm" }, classes = {}, specs = {},
    })

    local result = SlotFiller.State:GetProfileAutoLoad("MyProfile")
    result.characters[#result.characters + 1] = "Mutated-Realm"

    local fresh = SlotFiller.State:GetProfileAutoLoad("MyProfile")
    support.assert.same(fresh.characters, { "Bob-Realm" },
        "mutating a previous result must not corrupt the saved autoLoad config")
end)

runner:test("SetProfileAutoLoad and GetProfileAutoLoad roundtrip", function()
    SlotFiller.State:ResetForTests()
    SlotFiller.State:SetProfile("MyProfile", { savedAt = 1, slots = {} })

    local config = {
        enabled    = true,
        characters = { "Bob-Realm" },
        classes    = { "PALADIN"   },
        specs      = { "Retribution", "Holy" },
    }
    SlotFiller.State:SetProfileAutoLoad("MyProfile", config)

    local stored = SlotFiller.State:GetProfileAutoLoad("MyProfile")
    support.assert.equal(stored.enabled, true, "enabled flag persisted")
    support.assert.same(stored.characters, { "Bob-Realm" })
    support.assert.same(stored.classes,    { "PALADIN"   })
    support.assert.equal(#stored.specs, 2, "two specs stored")
end)

runner:test("GetProfileAutoLoad enabled defaults to false when not set", function()
    SlotFiller.State:ResetForTests()
    SlotFiller.State:SetProfile("OldProfile", { savedAt = 1, slots = {} })
    SlotFiller.State:SetProfileAutoLoad("OldProfile", { characters = {}, classes = {}, specs = {} })
    local al = SlotFiller.State:GetProfileAutoLoad("OldProfile")
    support.assert.equal(al.enabled, false, "enabled is false when absent")
end)

runner:test("SetProfileAutoLoad for missing profile is a no-op", function()
    SlotFiller.State:ResetForTests()
    SlotFiller.State:SetProfileAutoLoad("NoSuchProfile", { characters = {"x"} })
    local al = SlotFiller.State:GetProfileAutoLoad("NoSuchProfile")
    support.assert.same(al.characters, {}, "missing profile returns default empty")
end)

-- ── RenameProfile ─────────────────────────────────────────────────────────────

runner:test("RenameProfile moves data to new key and removes old key", function()
    SlotFiller.State:ResetForTests()
    SlotFiller.State:SetProfile("OldName", { savedAt = 1, slots = {} })
    SlotFiller.State:SetActiveProfile("OldName")

    local ok, err = SlotFiller.State:RenameProfile("OldName", "NewName")
    support.assert.equal(ok,  true, "rename succeeded")
    support.assert.isNil(err, "no error reason")
    support.assert.isNil(SlotFiller.State:GetProfile("OldName"), "old key gone")
    support.assert.equal(SlotFiller.State:GetProfile("NewName").savedAt, 1, "data moved")
    support.assert.equal(SlotFiller.State:GetActiveProfileName(), "NewName", "active updated")
end)

runner:test("RenameProfile returns false with 'missing' when source does not exist", function()
    SlotFiller.State:ResetForTests()
    local ok, reason = SlotFiller.State:RenameProfile("Ghost", "NewName")
    support.assert.equal(ok,     false,     "fails for missing source")
    support.assert.equal(reason, "missing", "reason: missing")
end)

runner:test("RenameProfile returns false with 'exists' when target already exists", function()
    SlotFiller.State:ResetForTests()
    SlotFiller.State:SetProfile("A", { savedAt = 1, slots = {} })
    SlotFiller.State:SetProfile("B", { savedAt = 2, slots = {} })
    local ok, reason = SlotFiller.State:RenameProfile("A", "B")
    support.assert.equal(ok,     false,   "fails when target exists")
    support.assert.equal(reason, "exists", "reason: exists")
end)

-- ── DuplicateProfile ──────────────────────────────────────────────────────────

runner:test("DuplicateProfile creates an independent copy under the new key", function()
    SlotFiller.State:ResetForTests()
    SlotFiller.State:SetProfile("Source", { savedAt = 5, slots = { [1] = { type = "spell", id = 1 } } })
    local ok = SlotFiller.State:DuplicateProfile("Source", "Copy")
    support.assert.equal(ok, true, "duplicate succeeded")
    support.assert.equal(SlotFiller.State:GetProfile("Copy").savedAt, 5, "copy has source data")
    support.assert.equal(SlotFiller.State:GetProfile("Source").savedAt, 5, "source still present")
end)

runner:test("DuplicateProfile returns false with 'missing' when source absent", function()
    SlotFiller.State:ResetForTests()
    local ok, reason = SlotFiller.State:DuplicateProfile("Ghost", "Copy")
    support.assert.equal(ok,     false,     "fails for missing source")
    support.assert.equal(reason, "missing", "reason: missing")
end)

runner:test("DuplicateProfile returns false with 'exists' when target already exists", function()
    SlotFiller.State:ResetForTests()
    SlotFiller.State:SetProfile("Source", { savedAt = 1, slots = {} })
    SlotFiller.State:SetProfile("Copy",   { savedAt = 2, slots = {} })
    local ok, reason = SlotFiller.State:DuplicateProfile("Source", "Copy")
    support.assert.equal(ok,     false,   "fails when target exists")
    support.assert.equal(reason, "exists", "reason: exists")
end)

os.exit(runner:run())
