local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/[^/]+%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_addon(root)

-- Helper: build a fake global record with the given profiles table.
local function withProfiles(profiles)
    SlotFiller.State.GetGlobalRecord = function(_)
        return { profiles = profiles }
    end
end

-- Helper: build a profile with the given autoLoad config.
-- `enabled` defaults to true so existing matching tests are unaffected;
-- pass `autoLoad = { enabled = false, ... }` to test the gate explicitly.
local function profileWith(autoLoad)
    local al = autoLoad or {}
    if al.enabled == nil then al.enabled = true end
    return { savedAt = 0, slots = {}, autoLoad = al }
end

-- ── No candidates ───────────────────────────────────────────────────────────

runner:test("returns nil when no profiles exist", function()
    withProfiles({})
    support.assert.isNil(
        SlotFiller.AutoLoad.FindBestProfile("Bob-Realm", "PALADIN", "Retribution"))
end)

runner:test("returns nil when all profiles conflict", function()
    withProfiles({
        Prot = profileWith({ characters = {}, classes = {"PALADIN"}, specs = {"Protection"} }),
    })
    support.assert.isNil(
        SlotFiller.AutoLoad.FindBestProfile("Bob-Realm", "PALADIN", "Retribution"),
        "spec conflict — Prot should not match a Ret player")
end)

-- ── Empty autoLoad (catch-all) ───────────────────────────────────────────────

runner:test("empty autoLoad matches any context with score 0", function()
    withProfiles({
        Any = profileWith({}),
    })
    support.assert.equal(
        SlotFiller.AutoLoad.FindBestProfile("Bob-Realm", "PALADIN", "Retribution"),
        "Any")
end)

runner:test("higher-scoring profile beats catch-all", function()
    withProfiles({
        Any      = profileWith({}),
        RetSpec  = profileWith({ classes = {}, specs = {"Retribution"} }),
    })
    support.assert.equal(
        SlotFiller.AutoLoad.FindBestProfile("Bob-Realm", "PALADIN", "Retribution"),
        "RetSpec",
        "spec-matched profile (+1) beats catch-all (0)")
end)

-- ── Conflict elimination ─────────────────────────────────────────────────────

runner:test("class conflict eliminates profile", function()
    withProfiles({
        WarlockOnly = profileWith({ classes = {"WARLOCK"} }),
        Any         = profileWith({}),
    })
    support.assert.equal(
        SlotFiller.AutoLoad.FindBestProfile("Bob-Realm", "PALADIN", "Retribution"),
        "Any",
        "WARLOCK profile should not match a PALADIN")
end)

runner:test("character conflict eliminates profile", function()
    withProfiles({
        AliceOnly = profileWith({ characters = {"Alice-Realm"} }),
        Any       = profileWith({}),
    })
    support.assert.equal(
        SlotFiller.AutoLoad.FindBestProfile("Bob-Realm", "PALADIN", "Retribution"),
        "Any",
        "Alice-only profile should not match Bob")
end)

-- ── Scoring ──────────────────────────────────────────────────────────────────

runner:test("class match scores +2", function()
    withProfiles({
        ClassMatch = profileWith({ classes = {"PALADIN"} }),
        SpecMatch  = profileWith({ specs = {"Retribution"} }),
    })
    support.assert.equal(
        SlotFiller.AutoLoad.FindBestProfile("Bob-Realm", "PALADIN", "Retribution"),
        "ClassMatch",
        "class match (+2) beats spec match (+1)")
end)

runner:test("class+spec match scores +3 and beats class-only", function()
    withProfiles({
        ClassOnly     = profileWith({ classes = {"PALADIN"} }),
        ClassAndSpec  = profileWith({ classes = {"PALADIN"}, specs = {"Retribution"} }),
    })
    support.assert.equal(
        SlotFiller.AutoLoad.FindBestProfile("Bob-Realm", "PALADIN", "Retribution"),
        "ClassAndSpec",
        "class+spec (+3) beats class-only (+2)")
end)

-- ── Character preference ─────────────────────────────────────────────────────

runner:test("character match restricts pool to character profiles", function()
    withProfiles({
        -- High-scoring non-character profile
        GenericClassSpec = profileWith({ classes = {"PALADIN"}, specs = {"Retribution"} }),
        -- Character-specific profile with lower score
        BobProfile       = profileWith({ characters = {"Bob-Realm"} }),
    })
    support.assert.equal(
        SlotFiller.AutoLoad.FindBestProfile("Bob-Realm", "PALADIN", "Retribution"),
        "BobProfile",
        "character-matched profile wins even with lower score than non-character profile")
end)

runner:test("character match with better score wins tie", function()
    withProfiles({
        BobBase   = profileWith({ characters = {"Bob-Realm"} }),
        BobWithClass = profileWith({ characters = {"Bob-Realm"}, classes = {"PALADIN"} }),
    })
    support.assert.equal(
        SlotFiller.AutoLoad.FindBestProfile("Bob-Realm", "PALADIN", "Retribution"),
        "BobWithClass",
        "within character pool, higher class score wins")
end)

-- ── Exact match ─────────────────────────────────────────────────────────────

runner:test("exact char+class+spec match wins over all alternatives", function()
    withProfiles({
        Any         = profileWith({}),
        ClassSpec   = profileWith({ classes = {"PALADIN"}, specs = {"Retribution"} }),
        BobExact    = profileWith({
            characters = {"Bob-Realm"},
            classes    = {"PALADIN"},
            specs      = {"Retribution"},
        }),
    })
    support.assert.equal(
        SlotFiller.AutoLoad.FindBestProfile("Bob-Realm", "PALADIN", "Retribution"),
        "BobExact",
        "full char+class+spec profile is the most specific match")
end)

-- ── enabled gate ─────────────────────────────────────────────────────────────

runner:test("profile with enabled=false is never selected", function()
    withProfiles({
        Disabled = profileWith({ enabled = false, classes = {"PALADIN"} }),
    })
    support.assert.isNil(
        SlotFiller.AutoLoad.FindBestProfile("Bob-Realm", "PALADIN", "Retribution"),
        "disabled profile must be ignored even when it would otherwise match")
end)

runner:test("profile with no enabled field is treated as disabled", function()
    withProfiles({
        Legacy = { savedAt = 0, slots = {}, autoLoad = { characters = {}, classes = {}, specs = {} } },
    })
    support.assert.isNil(
        SlotFiller.AutoLoad.FindBestProfile("Bob-Realm", "PALADIN", "Retribution"),
        "profile without enabled=true must not be auto-loaded")
end)

runner:test("enabled profile is selected while disabled sibling is ignored", function()
    withProfiles({
        Disabled = profileWith({ enabled = false }),
        Active   = profileWith({ enabled = true  }),
    })
    support.assert.equal(
        SlotFiller.AutoLoad.FindBestProfile("Bob-Realm", "PALADIN", "Retribution"),
        "Active",
        "only the enabled profile should be returned")
end)

runner:test("no profiles enabled returns nil even if all would match", function()
    withProfiles({
        P1 = profileWith({ enabled = false }),
        P2 = profileWith({ enabled = false }),
    })
    support.assert.isNil(
        SlotFiller.AutoLoad.FindBestProfile("Bob-Realm", "PALADIN", "Retribution"),
        "nil when no profile has enabled=true")
end)

-- ── Nil context inputs ───────────────────────────────────────────────────────

runner:test("nil characterKey does not break conflict detection", function()
    withProfiles({
        Any = profileWith({}),
    })
    -- Should not error, catch-all still qualifies.
    support.assert.equal(
        SlotFiller.AutoLoad.FindBestProfile(nil, "PALADIN", "Retribution"),
        "Any")
end)

os.exit(runner:run())
