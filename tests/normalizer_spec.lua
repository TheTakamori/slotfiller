local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/run%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_addon(root)

local N = SlotFiller.Normalizer
local C = SlotFiller.Constants

runner:test("compresses and uncompresses macro text", function()
    local compressed = N.CompressMacroText("line1\nline2||pipe")
    support.assert.equal(compressed, "line1/nline2/124pipe", "macro compression")
    support.assert.equal(N.UncompressMacroText(compressed), "line1\nline2|pipe", "macro uncompression")
end)

runner:test("builds profile from supported slots only", function()
    local profile = N.BuildProfile({
        [1] = { type = "spell", id = 133, name = "Fireball" },
        [4] = { type = "macro", name = "Burst", body = "/cast Fireball" },
        [999] = { type = "spell", id = 1, name = "Ignored" },
    })
    support.assert.equal(profile.slots[1].name, "Fireball", "slot 1 saved")
    support.assert.equal(profile.slots[4].name, "Burst", "slot 4 saved")
    support.assert.equal(profile.slots[999], nil, "out of range slot ignored")
end)

runner:test("IsSupportedActionType recognises known types and rejects UNKNOWN", function()
    support.assert.equal(N.IsSupportedActionType(C.ACTION_TYPE.SPELL),        true,  "spell")
    support.assert.equal(N.IsSupportedActionType(C.ACTION_TYPE.MACRO),        true,  "macro")
    support.assert.equal(N.IsSupportedActionType(C.ACTION_TYPE.ITEM),         true,  "item")
    support.assert.equal(N.IsSupportedActionType(C.ACTION_TYPE.FLYOUT),       true,  "flyout")
    support.assert.equal(N.IsSupportedActionType(C.ACTION_TYPE.COMPANION),    true,  "companion")
    support.assert.equal(N.IsSupportedActionType(C.ACTION_TYPE.EQUIPMENTSET), true,  "equipmentset")
    support.assert.equal(N.IsSupportedActionType(C.ACTION_TYPE.SUMMONMOUNT),  true,  "summonmount")
    support.assert.equal(N.IsSupportedActionType(C.ACTION_TYPE.UNKNOWN),      false, "UNKNOWN rejected")
    support.assert.equal(N.IsSupportedActionType(nil),                        false, "nil rejected")
    support.assert.equal(N.IsSupportedActionType("weirdtype"),                false, "arbitrary string rejected")
end)

runner:test("FromRaw normalises all action types", function()
    -- spell
    local spell = N.FromRaw({ type = "spell", id = 133, name = "Fireball", subType = "spell", extraID = 0 })
    support.assert.equal(spell.type, "spell",    "spell type")
    support.assert.equal(spell.id,   133,        "spell id")
    support.assert.equal(spell.name, "Fireball", "spell name")
    support.assert.equal(spell.subType, "spell", "spell subType")

    -- macro
    local macro = N.FromRaw({ type = "macro", id = 5, actionID = 3, name = "Go", body = "/cast Fire\n/cast Ice" })
    support.assert.equal(macro.type,     "macro",           "macro type")
    support.assert.equal(macro.macroID,  5,                 "macro id stored as macroID")
    support.assert.equal(macro.actionID, 3,                 "macro actionID")
    support.assert.equal(macro.name,     "Go",              "macro name")
    support.assert.equal(macro.body,     "/cast Fire/n/cast Ice", "macro body compressed")

    -- item
    local item = N.FromRaw({ type = "item", id = 208704, name = "Hearthstone" })
    support.assert.equal(item.type, "item",        "item type")
    support.assert.equal(item.id,   208704,        "item id")
    support.assert.equal(item.name, "Hearthstone", "item name")

    -- flyout
    local flyout = N.FromRaw({ type = "flyout", id = 1, name = "Portals" })
    support.assert.equal(flyout.type, "flyout",  "flyout type")
    support.assert.equal(flyout.id,   1,         "flyout id")

    -- summonmount
    local mount = N.FromRaw({ type = "summonmount", id = 268435455 })
    support.assert.equal(mount.type, "summonmount", "summonmount type")
    support.assert.equal(mount.id,   268435455,     "summonmount id")

    -- companion
    local comp = N.FromRaw({ type = "companion", id = 122708, subType = "MOUNT" })
    support.assert.equal(comp.type,    "companion", "companion type")
    support.assert.equal(comp.id,      122708,      "companion id")
    support.assert.equal(comp.subType, "MOUNT",     "companion subType")

    -- equipmentset
    local eset = N.FromRaw({ type = "equipmentset", id = "Tank Gear", name = "Tank Gear" })
    support.assert.equal(eset.type, "equipmentset", "equipmentset type")
    support.assert.equal(eset.id,   "Tank Gear",    "equipmentset id")

    -- summonpet
    local pet = N.FromRaw({ type = "summonpet", id = "BattlePet-0-00000B4B64D9", name = "Wee Stinker" })
    support.assert.equal(pet.type, "summonpet",                "summonpet type")
    support.assert.equal(pet.id,   "BattlePet-0-00000B4B64D9", "summonpet id (GUID)")
    support.assert.equal(pet.name, "Wee Stinker",              "summonpet name")
end)

runner:test("FromRaw returns nil for invalid inputs", function()
    support.assert.isNil(N.FromRaw(nil),                                "nil raw")
    support.assert.isNil(N.FromRaw({}),                                 "no type field")
    support.assert.isNil(N.FromRaw({ type = "spell",      id = nil }), "spell with nil id")
    support.assert.isNil(N.FromRaw({ type = "summonmount", id = nil }), "summonmount with nil id")
    support.assert.isNil(N.FromRaw({ type = "summonpet",   id = nil }), "summonpet with nil id")
end)

runner:test("IsSupportedActionType recognises summonpet", function()
    support.assert.equal(N.IsSupportedActionType(C.ACTION_TYPE.SUMMONPET), true, "summonpet supported")
end)

runner:test("FromRaw wraps unrecognised action types as UNKNOWN", function()
    local slot = N.FromRaw({ type = "weirdnewtype", id = 42, subType = "foo" })
    support.assert.equal(slot.type,    C.ACTION_TYPE.UNKNOWN, "wrapped as UNKNOWN")
    support.assert.equal(slot.rawType, "weirdnewtype",        "rawType preserved")
    support.assert.equal(slot.id,      42,                    "id preserved")
    support.assert.equal(slot.subType, "foo",                 "subType preserved")
end)

runner:test("CountFilledSlots counts occupied slots within range", function()
    support.assert.equal(N.CountFilledSlots(nil),          0, "nil profile")
    support.assert.equal(N.CountFilledSlots({ slots = {} }), 0, "empty slots")

    local profile = N.BuildProfile({
        [1]  = { type = "spell", id = 1, name = "A" },
        [5]  = { type = "spell", id = 2, name = "B" },
        [12] = { type = "item",  id = 3, name = "C" },
    })
    support.assert.equal(N.CountFilledSlots(profile), 3, "three slots")
end)

runner:test("CloneProfile produces an independent deep copy", function()
    local original = {
        savedAt = 100,
        slots = { [1] = { type = "spell", id = 133, name = "Fireball" } },
    }
    local copy = N.CloneProfile(original)
    support.assert.equal(copy.savedAt,         100,        "savedAt copied")
    support.assert.equal(copy.slots[1].name,   "Fireball", "slot data copied")
    -- Mutating the copy must not affect the original
    copy.slots[1].name = "Changed"
    support.assert.equal(original.slots[1].name, "Fireball", "original unaffected by copy mutation")
end)

runner:test("CloneProfile copies autoLoad config as an independent deep copy", function()
    local original = {
        savedAt  = 1,
        slots    = {},
        autoLoad = {
            enabled    = true,
            characters = { "Bob-Realm" },
            classes    = { "PALADIN" },
            specs      = { "Retribution" },
        },
    }
    local copy = N.CloneProfile(original)
    support.assert.equal(copy.autoLoad.enabled,      true,          "enabled copied")
    support.assert.same(copy.autoLoad.characters,    { "Bob-Realm" }, "characters copied")
    support.assert.same(copy.autoLoad.classes,       { "PALADIN"   }, "classes copied")
    support.assert.same(copy.autoLoad.specs,         { "Retribution" }, "specs copied")
    -- Mutations to the copy's arrays must not affect the original.
    copy.autoLoad.characters[1] = "Alice-Realm"
    support.assert.equal(original.autoLoad.characters[1], "Bob-Realm", "original characters unaffected")
end)

runner:test("CloneProfile without autoLoad produces copy with no autoLoad field", function()
    local original = { savedAt = 2, slots = {} }
    local copy = N.CloneProfile(original)
    support.assert.isNil(copy.autoLoad, "no autoLoad when source has none")
end)

os.exit(runner:run())
