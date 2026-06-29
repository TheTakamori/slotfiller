local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/[^/]+%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_addon(root)

-- Minimal WoW stubs needed by ProfileActions.
local function stubContext(notInCombat)
    SlotFiller.Context.RequireNotInCombat = function() return notInCombat ~= false end
    SlotFiller.Context.RequireReady       = function() return true end
end

local function stubScanner(slots)
    SlotFiller.Scanner = SlotFiller.Scanner or {}
    SlotFiller.Scanner.CaptureCurrentProfile = function()
        return { savedAt = 1, slots = slots or { [1] = { type = "spell", id = 1 } } }
    end
end

local function silencePrint()
    SlotFiller.Print = function() end
end

local function capturePrint()
    local lines = {}
    SlotFiller.Print = function(msg) lines[#lines + 1] = msg end
    return lines
end

-- Stubs Restorer:ApplyProfile to return the given ok/result pair.
local function stubRestorer(ok, result)
    SlotFiller.Restorer = SlotFiller.Restorer or {}
    SlotFiller.Restorer.ApplyProfile = function(_, _) return ok, result end
end

-- Stubs Scanner so that CaptureCurrentProfile returns a profile with a given slot count.
local function stubScannerWithSlots(count)
    local slots = {}
    for i = 1, count do
        slots[i] = { type = "spell", id = i }
    end
    SlotFiller.Scanner = SlotFiller.Scanner or {}
    SlotFiller.Scanner.CaptureCurrentProfile = function()
        return { savedAt = 1, slots = slots }
    end
    SlotFiller.Normalizer = SlotFiller.Normalizer or {}
    SlotFiller.Normalizer.CountFilledSlots = function(_) return count end
end

-- ── Save (Save As) ────────────────────────────────────────────────────────────

runner:test("Save creates a new profile with no autoLoad config", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    stubScanner()
    silencePrint()

    support.assert.isTrue(SlotFiller.ProfileActions:Save("NewProfile"))
    local al = SlotFiller.State:GetProfileAutoLoad("NewProfile")
    support.assert.equal(al.enabled, false, "new profile starts with enabled=false")
    support.assert.same(al.characters, {}, "new profile starts with no characters")
end)

runner:test("Save preserves existing autoLoad when overwriting (Update)", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    stubScanner()
    silencePrint()

    support.assert.isTrue(SlotFiller.ProfileActions:Save("RetBase"))
    SlotFiller.State:SetProfileAutoLoad("RetBase", {
        enabled    = true,
        characters = { "Bob-Realm" },
        classes    = { "PALADIN" },
        specs      = { "Retribution" },
    })

    support.assert.isTrue(SlotFiller.ProfileActions:Save("RetBase"))

    local al = SlotFiller.State:GetProfileAutoLoad("RetBase")
    support.assert.equal(al.enabled, true, "enabled flag survived overwrite")
    support.assert.same(al.characters, { "Bob-Realm" }, "characters survived overwrite")
    support.assert.same(al.classes,    { "PALADIN"   }, "classes survived overwrite")
    support.assert.same(al.specs,      { "Retribution" }, "specs survived overwrite")
end)

runner:test("Save does not copy autoLoad from a different profile", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    stubScanner()
    silencePrint()

    support.assert.isTrue(SlotFiller.ProfileActions:Save("ProfileA"))
    SlotFiller.State:SetProfileAutoLoad("ProfileA", {
        enabled = true, characters = { "Alice-Realm" }, classes = {}, specs = {},
    })

    support.assert.isTrue(SlotFiller.ProfileActions:Save("ProfileB"))
    local al = SlotFiller.State:GetProfileAutoLoad("ProfileB")
    support.assert.equal(al.enabled, false, "new profile must not inherit another profile's autoLoad")
    support.assert.same(al.characters, {}, "new profile must start with empty characters")
end)

runner:test("Save prints SAVE_EMPTY when no slots captured", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    stubScannerWithSlots(0)
    local lines = capturePrint()

    SlotFiller.ProfileActions:Save("EmptyBar")
    local combined = table.concat(lines, " ")
    support.assert.isTrue(combined:find("EmptyBar") ~= nil, "profile name in output")
    support.assert.isTrue(combined:find("no slots") ~= nil or combined:find("no slot") ~= nil
        or combined:find("Make sure") ~= nil, "SAVE_EMPTY wording present")
end)

-- ── Load ──────────────────────────────────────────────────────────────────────

runner:test("Load returns false for missing profile", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    silencePrint()
    support.assert.isFalse(SlotFiller.ProfileActions:Load("Ghost"), "false for missing")
end)

runner:test("Load returns false for empty name", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    silencePrint()
    support.assert.isFalse(SlotFiller.ProfileActions:Load(""),  "false for empty name")
    support.assert.isFalse(SlotFiller.ProfileActions:Load(nil), "false for nil name")
end)

runner:test("Load succeeds and sets active profile (clean restore)", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    stubRestorer(true, 0)
    local lines = capturePrint()

    SlotFiller.State:SetProfile("MyProfile", { savedAt = 1, slots = {} })
    support.assert.isTrue(SlotFiller.ProfileActions:Load("MyProfile"), "Load returns true")
    support.assert.equal(SlotFiller.State:GetActiveProfileName(), "MyProfile", "active profile updated")
    local combined = table.concat(lines, " ")
    support.assert.isTrue(combined:find("MyProfile") ~= nil, "profile name in output")
end)

runner:test("Load reports restore errors when issues exist", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    stubRestorer(true, 2)
    local lines = capturePrint()

    SlotFiller.State:SetProfile("IssueProfile", { savedAt = 1, slots = {} })
    support.assert.isTrue(SlotFiller.ProfileActions:Load("IssueProfile"), "Load returns true")
    local combined = table.concat(lines, " ")
    support.assert.isTrue(combined:find("issue") ~= nil or combined:find("Issue") ~= nil,
        "RESTORE_ERRORS wording present")
end)

runner:test("Load returns false when Restorer fails", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    stubRestorer(false, nil)
    silencePrint()

    SlotFiller.State:SetProfile("FailProfile", { savedAt = 1, slots = {} })
    support.assert.isFalse(SlotFiller.ProfileActions:Load("FailProfile"), "false when restore fails")
end)

-- ── Delete ────────────────────────────────────────────────────────────────────

runner:test("Delete removes an existing profile", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    silencePrint()
    SlotFiller.State:SetProfile("ToDelete", { savedAt = 1, slots = {} })
    support.assert.isTrue(SlotFiller.ProfileActions:Delete("ToDelete"))
    support.assert.isNil(SlotFiller.State:GetProfile("ToDelete"), "profile removed")
end)

runner:test("Delete returns false for missing profile", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    silencePrint()
    support.assert.isFalse(SlotFiller.ProfileActions:Delete("Ghost"), "false for missing")
end)

runner:test("Delete returns false for empty name", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    silencePrint()
    support.assert.isFalse(SlotFiller.ProfileActions:Delete(""), "false for empty name")
end)

-- ── Rename ────────────────────────────────────────────────────────────────────

runner:test("Rename moves an existing profile to a new name", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    silencePrint()
    SlotFiller.State:SetProfile("Old", { savedAt = 9, slots = {} })
    support.assert.isTrue(SlotFiller.ProfileActions:Rename("Old", "New"))
    support.assert.isNil(SlotFiller.State:GetProfile("Old"), "old key gone")
    support.assert.equal(SlotFiller.State:GetProfile("New").savedAt, 9, "data at new key")
end)

runner:test("Rename returns false when old and new names are identical", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    silencePrint()
    SlotFiller.State:SetProfile("Same", { savedAt = 1, slots = {} })
    support.assert.isFalse(SlotFiller.ProfileActions:Rename("Same", "Same"), "identical names rejected")
end)

runner:test("Rename returns false when target name already exists", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    silencePrint()
    SlotFiller.State:SetProfile("A", { savedAt = 1, slots = {} })
    SlotFiller.State:SetProfile("B", { savedAt = 2, slots = {} })
    support.assert.isFalse(SlotFiller.ProfileActions:Rename("A", "B"), "clash rejected")
end)

runner:test("Rename returns false for empty names", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    silencePrint()
    support.assert.isFalse(SlotFiller.ProfileActions:Rename("", "New"), "empty old rejected")
    support.assert.isFalse(SlotFiller.ProfileActions:Rename("Old", ""), "empty new rejected")
end)

-- ── Duplicate ─────────────────────────────────────────────────────────────────

runner:test("Duplicate creates an independent copy", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    silencePrint()
    SlotFiller.State:SetProfile("Source", { savedAt = 7, slots = {} })
    support.assert.isTrue(SlotFiller.ProfileActions:Duplicate("Source", "CopiedProfile"))
    support.assert.equal(SlotFiller.State:GetProfile("CopiedProfile").savedAt, 7, "copy has source data")
    support.assert.equal(SlotFiller.State:GetProfile("Source").savedAt, 7, "source unchanged")
end)

runner:test("Duplicate returns false for missing source", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    silencePrint()
    support.assert.isFalse(SlotFiller.ProfileActions:Duplicate("Ghost", "Copy"), "false for missing")
end)

runner:test("Duplicate returns false when target already exists", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    silencePrint()
    SlotFiller.State:SetProfile("Source",   { savedAt = 1, slots = {} })
    SlotFiller.State:SetProfile("Existing", { savedAt = 2, slots = {} })
    support.assert.isFalse(SlotFiller.ProfileActions:Duplicate("Source", "Existing"), "clash rejected")
end)

runner:test("Duplicate success message uses 'as' preposition consistent with prompt", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    local lines = capturePrint()

    SlotFiller.State:SetProfile("Src", { savedAt = 1, slots = {} })
    SlotFiller.ProfileActions:Duplicate("Src", "Copy")
    local combined = table.concat(lines, " ")
    support.assert.isTrue(combined:find(" as ") ~= nil,
        "success message should say 'Src as Copy', matching the Duplicate prompt wording")
end)

-- ── Overwrite ─────────────────────────────────────────────────────────────────

runner:test("Overwrite returns false for non-existent profile", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    silencePrint()
    support.assert.isFalse(SlotFiller.ProfileActions:Overwrite("Ghost"), "false for missing")
end)

runner:test("Overwrite updates an existing profile and preserves autoLoad", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    stubScanner()
    silencePrint()

    support.assert.isTrue(SlotFiller.ProfileActions:Save("ExistingProfile"))
    SlotFiller.State:SetProfileAutoLoad("ExistingProfile", {
        enabled = true, characters = { "Alice-Realm" }, classes = {}, specs = {},
    })

    support.assert.isTrue(SlotFiller.ProfileActions:Overwrite("ExistingProfile"), "Overwrite returns true")

    local al = SlotFiller.State:GetProfileAutoLoad("ExistingProfile")
    support.assert.equal(al.enabled, true, "autoLoad enabled preserved after Overwrite")
    support.assert.same(al.characters, { "Alice-Realm" }, "characters preserved after Overwrite")
end)

-- ── List ──────────────────────────────────────────────────────────────────────

runner:test("List prints all saved profile names", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    SlotFiller.State:SetProfile("Alpha", { savedAt = 1, slots = {} })
    SlotFiller.State:SetProfile("Beta",  { savedAt = 2, slots = {} })

    local printed = {}
    SlotFiller.Print = function(msg) printed[#printed+1] = msg end

    SlotFiller.ProfileActions:List()
    local combined = table.concat(printed, " ")
    support.assert.isTrue(combined:find("Alpha") ~= nil, "Alpha in output")
    support.assert.isTrue(combined:find("Beta")  ~= nil, "Beta in output")
end)

runner:test("List prints empty message when no profiles exist", function()
    SlotFiller.State:ResetForTests()
    stubContext()
    local printed = {}
    SlotFiller.Print = function(msg) printed[#printed+1] = msg end
    SlotFiller.ProfileActions:List()
    local combined = table.concat(printed, " ")
    support.assert.isTrue(combined:find(SlotFiller.Text.LIST_EMPTY) ~= nil, "empty message printed")
end)

os.exit(runner:run())
