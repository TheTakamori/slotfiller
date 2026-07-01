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

    -- global macro (no icon, no perCharacter)
    local macro = N.FromRaw({ type = "macro", id = 5, actionID = 3, name = "Go", body = "/cast Fire\n/cast Ice" })
    support.assert.equal(macro.type,     "macro",           "macro type")
    support.assert.equal(macro.macroID,  5,                 "macro id stored as macroID")
    support.assert.equal(macro.actionID, 3,                 "macro actionID")
    support.assert.equal(macro.name,     "Go",              "macro name")
    support.assert.equal(macro.body,     "/cast Fire/n/cast Ice", "macro body compressed")
    support.assert.isNil(macro.perCharacter,               "perCharacter absent for global macro")

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

    -- outfit
    local outfit = N.FromRaw({ type = "outfit", id = 42, name = "Tank Set" })
    support.assert.equal(outfit.type, "outfit",    "outfit type")
    support.assert.equal(outfit.id,   42,           "outfit id")
    support.assert.equal(outfit.name, "Tank Set",   "outfit name")
end)

runner:test("IsSupportedActionType recognises outfit", function()
    support.assert.equal(N.IsSupportedActionType(C.ACTION_TYPE.OUTFIT), true, "outfit supported")
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

-- ---------------------------------------------------------------------------
-- Macro slot icon and perCharacter persistence
-- ---------------------------------------------------------------------------

runner:test("FromRaw stores icon and perCharacter for a character-specific macro", function()
    local slot = N.FromRaw({
        type = "macro", id = 125, actionID = 10,
        name = "MyMacro", body = "/cast Fireball",
        icon = 134414, perCharacter = true,
    })
    support.assert.equal(slot.icon,         134414, "icon stored")
    support.assert.equal(slot.perCharacter, true,   "perCharacter stored")
end)

runner:test("FromRaw omits perCharacter for a global macro", function()
    local slot = N.FromRaw({
        type = "macro", id = 5, actionID = 1,
        name = "Global", body = "/cast Ice",
        icon = 134414, perCharacter = false,
    })
    support.assert.equal(slot.icon, 134414, "icon still stored for global macro")
    support.assert.isNil(slot.perCharacter, "perCharacter not set for global macro")
end)

runner:test("FromRaw stores nil icon when scanner provides none", function()
    local slot = N.FromRaw({
        type = "macro", id = 3, actionID = 1,
        name = "NoIcon", body = "/cast Fire",
    })
    support.assert.isNil(slot.icon, "icon is nil when raw.icon absent")
end)

-- ---------------------------------------------------------------------------
-- Pet action bar
-- ---------------------------------------------------------------------------

runner:test("FromRawPetSlot normalises a token", function()
    local slot = N.FromRawPetSlot({ token = "PET_ACTION_ATTACK" })
    support.assert.equal(slot.type,  C.PET_SLOT_TYPE.TOKEN, "token type")
    support.assert.equal(slot.token, "PET_ACTION_ATTACK",   "token name stored")
end)

runner:test("FromRawPetSlot normalises a spell", function()
    local slot = N.FromRawPetSlot({ spellID = 17253 })
    support.assert.equal(slot.type,    C.PET_SLOT_TYPE.SPELL, "spell type")
    support.assert.equal(slot.spellID, 17253,                 "spellID stored")
end)

runner:test("FromRawPetSlot returns nil for empty input", function()
    support.assert.isNil(N.FromRawPetSlot(nil),  "nil raw")
    support.assert.isNil(N.FromRawPetSlot({}),   "no token or spellID")
end)

runner:test("BuildPetProfile keeps only slots within the pet bar range", function()
    local petSlots = N.BuildPetProfile({
        [1]  = { type = "token", token = "PET_ACTION_ATTACK" },
        [10] = { type = "spell", spellID = 1 },
        [99] = { type = "spell", spellID = 2 },
    })
    support.assert.equal(petSlots[1].token,   "PET_ACTION_ATTACK", "slot 1 kept")
    support.assert.equal(petSlots[10].spellID, 1,                  "slot 10 kept")
    support.assert.isNil(petSlots[99],                              "out-of-range slot dropped")
end)

-- ---------------------------------------------------------------------------
-- Click bindings
-- ---------------------------------------------------------------------------

runner:test("FromRawClickBinding normalises a non-macro binding", function()
    local entry = N.FromRawClickBinding({
        bindingType = 1, button = "RightButton", modifiers = 0, actionID = 133,
    })
    support.assert.equal(entry.bindingType, 1,             "bindingType stored")
    support.assert.equal(entry.button,      "RightButton", "button stored")
    support.assert.equal(entry.actionID,    133,            "actionID stored")
    support.assert.isNil(entry.isMacro,                     "isMacro absent for non-macro binding")
end)

runner:test("FromRawClickBinding normalises a macro binding", function()
    local entry = N.FromRawClickBinding({
        bindingType = 2, button = "Button4", modifiers = 1,
        isMacro = true, macroName = "Heal", macroBody = "/cast Heal", macroIcon = 1,
    })
    support.assert.equal(entry.isMacro,   true,         "isMacro stored")
    support.assert.equal(entry.macroName, "Heal",       "macroName stored")
    support.assert.equal(entry.macroBody, "/cast Heal", "macroBody stored")
end)

runner:test("FromRawClickBinding returns nil for a macro binding with no resolved macro", function()
    local entry = N.FromRawClickBinding({
        bindingType = 2, button = "Button4", modifiers = 0, isMacro = true,
    })
    support.assert.isNil(entry, "no stable data to restore without a macro name")
end)

runner:test("FromRawClickBinding returns nil for invalid input", function()
    support.assert.isNil(N.FromRawClickBinding(nil),                          "nil raw")
    support.assert.isNil(N.FromRawClickBinding({ bindingType = 1 }),          "missing button")
end)

-- ---------------------------------------------------------------------------
-- CloneProfile: petSlots / clickBindings
-- ---------------------------------------------------------------------------

runner:test("CloneProfile deep-copies petSlots independently", function()
    local original = {
        savedAt = 1,
        slots = {},
        petSlots = { [1] = { type = "spell", spellID = 5 } },
    }
    local copy = N.CloneProfile(original)
    copy.petSlots[1].spellID = 999
    support.assert.equal(original.petSlots[1].spellID, 5, "original petSlots unaffected by copy mutation")
end)

runner:test("CloneProfile deep-copies clickBindings independently", function()
    local original = {
        savedAt = 1,
        slots = {},
        clickBindings = { { bindingType = 1, button = "Button4", actionID = 7 } },
    }
    local copy = N.CloneProfile(original)
    copy.clickBindings[1].actionID = 999
    support.assert.equal(original.clickBindings[1].actionID, 7, "original clickBindings unaffected by copy mutation")
end)

runner:test("CloneProfile omits petSlots/clickBindings when source has none", function()
    local copy = N.CloneProfile({ savedAt = 1, slots = {} })
    support.assert.isNil(copy.petSlots,      "no petSlots when source has none")
    support.assert.isNil(copy.clickBindings, "no clickBindings when source has none")
end)

os.exit(runner:run())
