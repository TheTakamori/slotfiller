local _, SlotFiller = ...

-- Spellbook iteration and cache-building helpers, split out of
-- Core/ActionAPI.lua. ActionAPI keeps action-slot query/pickup/clear/place
-- plus the non-spellbook pickup wrappers (item/macro/mount/pet/equipment/
-- outfit/companion); this module owns everything that walks the player's
-- spellbook skill lines.
SlotFiller.SpellBookAPI = {}

local PLAYER_SPELL_BANK = SlotFiller.ActionAPI.PLAYER_SPELL_BANK
local Constants = SlotFiller.Constants

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

-- Shared by isSpellBookItemType (exclude flyouts from the generic spell
-- cache) and BuildFlyoutBookCache (include only flyouts), so the two never
-- drift on what counts as a flyout entry.
local function isFlyoutItemType(itemInfo)
    if not itemInfo or not itemInfo.itemType then
        return false
    end
    if Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Flyout then
        return itemInfo.itemType == Enum.SpellBookItemType.Flyout
    end
    return type(itemInfo.itemType) == "string" and string.lower(itemInfo.itemType) == "flyout"
end

local function isSpellBookItemType(itemInfo)
    if not itemInfo or not itemInfo.itemType then
        return true
    end
    -- Exclude flyout menus — everything else (spell, assistedcombat, etc.) is welcome
    return not isFlyoutItemType(itemInfo)
end

function SlotFiller.SpellBookAPI.GetSpellBookItemInfo(bookIndex)
    if not bookIndex or not C_SpellBook or not C_SpellBook.GetSpellBookItemInfo then
        return nil
    end
    return C_SpellBook.GetSpellBookItemInfo(bookIndex, PLAYER_SPELL_BANK)
end

-- Returns true when spellID is known by or appears in the player's current spellbook,
-- meaning it can be placed on the action bar.  Used by ActionResolver to skip spells
-- that belong to a different class or inactive spec without emitting spurious errors.
function SlotFiller.SpellBookAPI.IsSpellRestorable(spellID)
    if not spellID then return false end
    if C_SpellBook then
        if C_SpellBook.IsSpellKnownOrInSpellBook then
            -- includeOverrides = true catches talent-overridden base spells.
            return C_SpellBook.IsSpellKnownOrInSpellBook(spellID, PLAYER_SPELL_BANK, true) == true
        end
        if C_SpellBook.IsSpellKnown then
            return C_SpellBook.IsSpellKnown(spellID, PLAYER_SPELL_BANK) == true
        end
    end
    -- API unavailable (test host or pre-Midnight build): assume valid and let the
    -- pickup attempt determine restorability.
    return true
end

-- Walks every spellbook entry in the current spec's non-guild skill lines,
-- calling visit(bookIndex, itemInfo) for each entry found. Shared low-level
-- walker behind IterateSpellBookEntries and BuildFlyoutBookCache so both
-- share one tab/slot loop instead of each re-implementing it.
--
-- Returns true if the modern C_SpellBook walk ran (regardless of whether any
-- entries were found), or false if C_SpellBook is unavailable and the caller
-- should fall back to the legacy API itself.
local function walkCurrentSpecSkillLines(visit)
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo) then
        return false
    end
    for tabIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(tabIndex)
        if skillLineInfo and not skillLineInfo.isGuild and isOnCurrentSpecSkillLine(skillLineInfo) then
            local offset = skillLineInfo.itemIndexOffset or 0
            local numSpells = skillLineInfo.numSpellBookItems or 0
            for spellIndex = 1, numSpells do
                local bookIndex = offset + spellIndex
                local itemInfo = SlotFiller.SpellBookAPI.GetSpellBookItemInfo(bookIndex)
                if itemInfo then
                    visit(bookIndex, itemInfo)
                end
            end
        end
    end
    return true
end

function SlotFiller.SpellBookAPI.IterateSpellBookEntries(callback)
    local handledByModernAPI = walkCurrentSpecSkillLines(function(bookIndex, itemInfo)
        if itemInfo.name and not itemInfo.isOffSpec and isSpellBookItemType(itemInfo) then
            callback(bookIndex, itemInfo.name, itemInfo.subName, itemInfo.spellID or itemInfo.actionID)
        end
    end)
    if handledByModernAPI then
        return
    end

    if not GetSpellTabInfo or not GetSpellBookItemName then
        return
    end

    for tabIndex = 1, (MAX_SKILLLINE_TABS or Constants.MAX_SKILLLINE_TABS_FALLBACK) do
        local _, _, offset, numSpells, _, offSpecID = GetSpellTabInfo(tabIndex)
        if (offSpecID == nil or offSpecID == 0) and numSpells and numSpells > 0 then
            for spellIndex = 1, numSpells do
                local bookIndex = offset + spellIndex
                local spellName, spellSubName = GetSpellBookItemName(bookIndex, "spell")
                if spellName then
                    callback(bookIndex, spellName, spellSubName, nil)
                end
            end
        end
    end
end

function SlotFiller.SpellBookAPI.BuildSpellBookCache()
    local cache = {}
    SlotFiller.SpellBookAPI.IterateSpellBookEntries(function(bookIndex, spellName, spellSubName, spellID)
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
-- Note: the Assisted Combat (SBA) button itself never appears in any
-- spellbook skill line, so it's never a key in this cache. Restoring an SBA
-- slot instead uses the spell C_AssistedCombat.GetActionSpell() captured at
-- save time (see Scanner.lua), which is an ordinary spellbook entry.

-- Builds a cache of flyoutID -> spellBookIndex for all flyout entries visible in the
-- current spec's spellbook.  Used as a fallback by ActionAPI.PickupFlyoutID for newer
-- flyouts (e.g. Midnight portal menus) that cannot be picked up directly by flyout ID.
function SlotFiller.SpellBookAPI.BuildFlyoutBookCache()
    local cache = {}
    walkCurrentSpecSkillLines(function(bookIndex, itemInfo)
        if itemInfo.actionID and isFlyoutItemType(itemInfo) then
            cache[itemInfo.actionID] = bookIndex
        end
    end)
    return cache
end

-- Returns a table mapping override spell ID -> base spell ID for every spellbook
-- entry whose currently-displayed spell differs from its base (talent swaps and
-- baseline-replacement abilities). GetActionInfo reports whichever spell is
-- currently showing, which can be an override ID that only exists while a
-- specific talent is selected. Saving the base ID instead keeps a profile valid
-- across talent or spec changes made after the save — Scanner applies this map
-- when capturing spell slots.
function SlotFiller.SpellBookAPI.BuildSpellOverrideMap()
    local overrideMap = {}
    if not (C_Spell and C_Spell.GetOverrideSpell) then
        return overrideMap
    end
    SlotFiller.SpellBookAPI.IterateSpellBookEntries(function(_, _, _, spellID)
        if spellID then
            local overrideID = C_Spell.GetOverrideSpell(spellID)
            if overrideID and overrideID ~= spellID then
                overrideMap[overrideID] = spellID
            end
        end
    end)
    return overrideMap
end
