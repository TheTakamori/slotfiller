local _, SlotFiller = ...

SlotFiller.ActionAPI = {}

local PLAYER_SPELL_BANK = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0

local function isOnCurrentSpecSkillLine(skillLineInfo)
    if not skillLineInfo then
        return false
    end
    if skillLineInfo.isOffSpec then
        return false
    end
    if skillLineInfo.offSpecID and skillLineInfo.offSpecID ~= 0 then
        return false
    end
    return true
end

local function isSpellBookItemType(itemInfo)
    if not itemInfo or not itemInfo.itemType then
        return true
    end
    -- Exclude flyout menus — everything else (spell, assistedcombat, etc.) is welcome
    if Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Flyout then
        if itemInfo.itemType == Enum.SpellBookItemType.Flyout then
            return false
        end
    end
    local t = type(itemInfo.itemType) == "string" and string.lower(itemInfo.itemType) or ""
    return t ~= "flyout"
end

function SlotFiller.ActionAPI.GetSlotActionInfo(actionID)
    if C_ActionBar and C_ActionBar.GetActionInfo then
        local actionType, id, subType, extraID = C_ActionBar.GetActionInfo(actionID)
        if actionType then
            return actionType, id, subType, extraID
        end
    end
    if GetActionInfo then
        return GetActionInfo(actionID)
    end
    return nil
end

function SlotFiller.ActionAPI.HasSlotAction(actionID)
    local actionType, id = SlotFiller.ActionAPI.GetSlotActionInfo(actionID)
    if not actionType or actionType == "" then
        return false
    end
    if actionType == "equipmentset" then
        return id ~= nil and id ~= ""
    end
    -- Allow id == 0: some special Midnight actions (e.g. Summon Random Favorite Mount)
    -- may surface with a zero or non-standard id yet still occupy the slot.
    return id ~= nil
end

function SlotFiller.ActionAPI.ClearSlot(actionID)
    if not PickupAction or not ClearCursor then
        return
    end
    if SlotFiller.ActionAPI.HasSlotAction(actionID) then
        PickupAction(actionID)
        ClearCursor()
    end
end

function SlotFiller.ActionAPI.PlaceSlot(actionID)
    if PlaceAction then
        PlaceAction(actionID)
    end
end

function SlotFiller.ActionAPI.PickupSpellID(spellID)
    if not spellID then
        return false
    end

    local function cursorIsValid()
        local t = GetCursorInfo and GetCursorInfo()
        return t == "spell" or t == "companion" or t == "mount"
    end

    if C_Spell and C_Spell.PickupSpell then
        C_Spell.PickupSpell(spellID)
        if cursorIsValid() then
            return true
        end
        if ClearCursor then ClearCursor() end
    elseif PickupSpell then
        PickupSpell(spellID)
        if cursorIsValid() then
            return true
        end
        if ClearCursor then ClearCursor() end
    end

    if C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell and C_SpellBook.PickupSpellBookItem then
        local slotIndex, bank = C_SpellBook.FindSpellBookSlotForSpell(spellID)
        if slotIndex then
            C_SpellBook.PickupSpellBookItem(slotIndex, bank or PLAYER_SPELL_BANK)
            if cursorIsValid() then
                return true
            end
            if ClearCursor then ClearCursor() end
        end
    end

    return false
end

function SlotFiller.ActionAPI.PickupSpellBookIndex(bookIndex, bank)
    if not bookIndex then
        return false
    end
    bank = bank or PLAYER_SPELL_BANK
    if C_SpellBook and C_SpellBook.PickupSpellBookItem then
        C_SpellBook.PickupSpellBookItem(bookIndex, bank)
    elseif PickupSpellBookItem then
        PickupSpellBookItem(bookIndex, "spell")
    else
        return false
    end
    -- Accept any non-empty cursor type: SBA rotation buttons and some special abilities
    -- may surface as "companion", "flyout", or another type rather than plain "spell".
    local cursorType = GetCursorInfo and GetCursorInfo()
    return cursorType ~= nil and cursorType ~= ""
end

function SlotFiller.ActionAPI.PickupMacroID(macroID)
    if not macroID or not PickupMacro then
        return false
    end
    PickupMacro(macroID)
    return GetCursorInfo and GetCursorInfo() == "macro"
end

function SlotFiller.ActionAPI.PickupItemID(itemID)
    if not itemID then
        return false
    end
    if C_Item and C_Item.PickupItem then
        C_Item.PickupItem(itemID)
    elseif PickupItem then
        PickupItem(itemID)
    else
        return false
    end
    return GetCursorInfo and GetCursorInfo() == "item"
end

function SlotFiller.ActionAPI.PickupFlyoutID(flyoutID)
    if not flyoutID then
        return false
    end
    if C_Spell and C_Spell.PickupSpell then
        C_Spell.PickupSpell(flyoutID)
    elseif PickupSpell then
        PickupSpell(flyoutID)
    else
        return false
    end
    local cursorType = GetCursorInfo and GetCursorInfo()
    return cursorType == "flyout" or cursorType == "spell"
end

-- Attempts to pick up a mount from the Mount Journal by matching its summon spell ID.
-- Used as a last resort for "spell" type slots that turned out to be mounts.
function SlotFiller.ActionAPI.PickupMountBySpellID(spellID)
    if not spellID then return false end
    -- PickupSpellID already accepts "mount" cursor type; re-use it here.
    return SlotFiller.ActionAPI.PickupSpellID(spellID)
end

-- Picks up a mount by its mountActionID (the id returned by GetActionInfo for a
-- "summonmount" slot). Uses C_MountJournal.Pickup(0) for the random-favourite-mount
-- sentinel (268435455), otherwise resolves to the mount's summon spell via
-- GetMountInfoByID and picks it up with PickupSpell.
function SlotFiller.ActionAPI.PickupMountByID(mountActionID)
    if mountActionID == nil then return false end
    if not C_MountJournal then return false end

    local ok, picked = pcall(function()
        -- 268435455 (0x0FFFFFFF) = "Summon Random Favourite Mount"
        if mountActionID == 268435455 then
            if not C_MountJournal.Pickup then return false end
            C_MountJournal.Pickup(0)
            local t = GetCursorInfo and GetCursorInfo()
            return t ~= nil and t ~= ""
        end

        -- Primary: treat mountActionID as a mountID (they coincide in Midnight's
        -- summonmount type). GetMountInfoByID gives us the summon spell; PickupSpell
        -- puts the mount on the cursor (GetCursorInfo returns "mount", not "spell").
        if C_MountJournal.GetMountInfoByID then
            local _, spellID = C_MountJournal.GetMountInfoByID(mountActionID)
            if spellID and spellID > 0 then
                if SlotFiller.ActionAPI.PickupSpellID(spellID) then
                    return true
                end
                if ClearCursor then ClearCursor() end
            end
        end

        -- Fallback: iterate all mounts, pick each up, compare the cursor mountActionID.
        -- This is O(N) but only runs when the primary strategy fails.
        if C_MountJournal.GetNumMounts and C_MountJournal.Pickup then
            local numMounts = C_MountJournal.GetNumMounts()
            for displayIndex = 1, numMounts do
                C_MountJournal.Pickup(displayIndex)
                local cursorType, cursorActionID = GetCursorInfo()
                if cursorType == "mount" and cursorActionID == mountActionID then
                    return true
                end
                if ClearCursor then ClearCursor() end
            end
        end

        return false
    end)
    return ok and picked or false
end

function SlotFiller.ActionAPI.PickupEquipmentSetName(setName)
    if not setName then
        return false
    end
    if C_EquipmentSet and C_EquipmentSet.PickupEquipmentSet and C_EquipmentSet.GetNumEquipmentSets then
        for index = 1, C_EquipmentSet.GetNumEquipmentSets() do
            local name = C_EquipmentSet.GetEquipmentSetInfo(index)
            if name == setName then
                C_EquipmentSet.PickupEquipmentSet(index)
                return GetCursorInfo and GetCursorInfo() == "equipmentset"
            end
        end
        return false
    end
    if GetNumEquipmentSets and GetEquipmentSetInfo and PickupEquipmentSet then
        for index = 1, GetNumEquipmentSets() do
            if GetEquipmentSetInfo(index) == setName then
                PickupEquipmentSet(index)
                return GetCursorInfo and GetCursorInfo() == "equipmentset"
            end
        end
    end
    return false
end

function SlotFiller.ActionAPI.GetSpellBookItemInfo(bookIndex)
    if not bookIndex or not C_SpellBook or not C_SpellBook.GetSpellBookItemInfo then
        return nil
    end
    return C_SpellBook.GetSpellBookItemInfo(bookIndex, PLAYER_SPELL_BANK)
end

function SlotFiller.ActionAPI.IterateSpellBookEntries(callback)
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo then
        for tabIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(tabIndex)
            if skillLineInfo and not skillLineInfo.isGuild and isOnCurrentSpecSkillLine(skillLineInfo) then
                local offset = skillLineInfo.itemIndexOffset or 0
                local numSpells = skillLineInfo.numSpellBookItems or 0
                for spellIndex = 1, numSpells do
                    local bookIndex = offset + spellIndex
                    local itemInfo = SlotFiller.ActionAPI.GetSpellBookItemInfo(bookIndex)
                    if itemInfo and itemInfo.name and not itemInfo.isOffSpec and isSpellBookItemType(itemInfo) then
                        callback(bookIndex, itemInfo.name, itemInfo.subName, itemInfo.spellID or itemInfo.actionID)
                    end
                end
            end
        end
        return
    end

    if not GetSpellTabInfo or not GetSpellBookItemName then
        return
    end

    for tabIndex = 1, (MAX_SKILLLINE_TABS or 8) do
        local _, _, offset, numSpells, _, offSpecID = GetSpellTabInfo(tabIndex)
        if (offSpecID == nil or offSpecID == 0) and numSpells and numSpells > 0 then
            for spellIndex = 1, numSpells do
                local bookIndex = offset + spellIndex
                local spellName, spellSubName = GetSpellBookItemName(bookIndex, "spell")
                if spellName then
                    callback(bookIndex, spellName, spellSubName, nil, nil)
                end
            end
        end
    end
end

function SlotFiller.ActionAPI.BuildSpellBookCache()
    local cache = {}
    SlotFiller.ActionAPI.IterateSpellBookEntries(function(bookIndex, spellName, spellSubName, spellID)
        cache[spellName] = bookIndex
        cache[string.lower(spellName)] = bookIndex
        if spellSubName and spellSubName ~= "" then
            cache[spellName .. spellSubName] = bookIndex
        end
        if spellID then
            cache[spellID] = bookIndex
        end
    end)
    return cache
end
-- Spellbook scan confirmed that the SBA (assistedcombat) button does not appear in
-- any spellbook skill line and cannot be picked up programmatically. Restoration
-- relies solely on PickupAction from an existing SBA slot on the action bars.
