local _, SlotFiller = ...

local Constants = SlotFiller.Constants
local ActionAPI = SlotFiller.ActionAPI
local Text = SlotFiller.Text

SlotFiller.Restorer = {
    lastErrors = {},
}

local function clearErrors(self)
    wipe(self.lastErrors)
end

local function addError(self, message)
    self.lastErrors[#self.lastErrors + 1] = message
end

-- Returns true if the given action slot currently holds an SBA (assistedcombat) button.
-- Uses C_ActionBar.IsAssistedCombatAction when available; falls back to GetActionInfo
-- subType comparison, which is known to work reliably on Midnight 12.0.7.
local function slotIsAssistedCombat(actionID)
    if C_ActionBar and C_ActionBar.IsAssistedCombatAction then
        return C_ActionBar.IsAssistedCombatAction(actionID)
    end
    local actionType, _, subType = ActionAPI.GetSlotActionInfo(actionID)
    return actionType == Constants.ACTION_TYPE.SPELL
        and subType == Constants.ACTION_SUBTYPE.ASSISTEDCOMBAT
end

-- Returns a list of all action slot IDs that currently hold an SBA button.
-- Uses C_ActionBar.FindAssistedCombatActionButtons when available; otherwise
-- walks all slots via GetActionInfo.
local function findAllAssistedCombatSlots()
    if C_ActionBar and C_ActionBar.FindAssistedCombatActionButtons then
        local result = C_ActionBar.FindAssistedCombatActionButtons()
        if result and #result > 0 then
            return result
        end
    end
    local slots = {}
    for actionID = Constants.SLOT_MIN, Constants.SLOT_MAX do
        if slotIsAssistedCombat(actionID) then
            slots[#slots + 1] = actionID
        end
    end
    return slots
end

function SlotFiller.Restorer:BuildMacroCache()
    local bodyCache = {}
    local nameCache = {}
    local idCache = {}
    local blacklist = {}
    local maxMacros = (MAX_ACCOUNT_MACROS or 120) + (MAX_CHARACTER_MACROS or 0)

    if not GetMacroInfo then
        return bodyCache, nameCache, idCache
    end

    for macroID = 1, maxMacros do
        local name, _, body = GetMacroInfo(macroID)
        if name and body then
            idCache[macroID] = macroID
            local compressedBody = SlotFiller.Normalizer.CompressMacroText(body)
            bodyCache[compressedBody] = macroID
            if nameCache[name] then
                blacklist[name] = true
                nameCache[name] = nil  -- ambiguous: drop the earlier entry too
            elseif not blacklist[name] then
                nameCache[name] = macroID
            end
        end
    end

    return bodyCache, nameCache, idCache
end

function SlotFiller.Restorer:FindMacroID(slot, bodyCache, nameCache, idCache)
    if slot.macroID and idCache[slot.macroID] and GetMacroInfo then
        local name, _, body = GetMacroInfo(slot.macroID)
        if body then
            local compressedBody = SlotFiller.Normalizer.CompressMacroText(body)
            if (not slot.body or slot.body == compressedBody) and (not slot.name or slot.name == name) then
                return slot.macroID
            end
        end
    end
    if slot.body and bodyCache[slot.body] then
        return bodyCache[slot.body]
    end
    if slot.name and nameCache[slot.name] then
        return nameCache[slot.name]
    end
    return nil
end

-- Restores an Assisted Combat (SBA) button to actionID.
-- spareSBASlots is a pre-captured list of currently-SBA slots that are not themselves
-- profile SBA targets (safe to steal from). Mutated in-place as sources are consumed.
function SlotFiller.Restorer:RestoreSBASlot(actionID, spareSBASlots)
    -- Already correct — leave the existing SBA button untouched.
    if slotIsAssistedCombat(actionID) then
        return
    end

    -- Find a spare source slot to copy from.
    local sourceSlot = nil
    if spareSBASlots and #spareSBASlots > 0 then
        sourceSlot = table.remove(spareSBASlots, 1)
    end

    if not sourceSlot then
        addError(self, string.format(
            "Cannot restore Assisted Combat button to slot %d. No Rotation Assistant button was found on your action bars — drag one from the spellbook to any bar, then reload the profile.",
            actionID))
        return
    end

    if not PickupAction then
        addError(self, string.format("Cannot restore Assisted Combat button to slot %d. PickupAction unavailable.", actionID))
        return
    end

    PickupAction(sourceSlot)
    local cursorType = GetCursorInfo and GetCursorInfo()
    if cursorType and cursorType ~= "" then
        ActionAPI.PlaceSlot(actionID)
        if ClearCursor then ClearCursor() end  -- discard any old content swapped off the target slot
    else
        if ClearCursor then ClearCursor() end
        addError(self, string.format(
            "Cannot restore Assisted Combat button to slot %d. Pickup from source slot %d failed.",
            actionID, sourceSlot))
    end
end

function SlotFiller.Restorer:RestoreSlot(actionID, slot, caches)
    if ClearCursor then ClearCursor() end

    -- SBA buttons cannot be recreated once removed; always preserve them regardless
    -- of what the profile says.  SBA target slots are placed by the dedicated pre-pass
    -- and are excluded from Pass 2, so this guard handles only the case where a
    -- non-SBA profile entry would otherwise displace an existing SBA button.
    if slotIsAssistedCombat(actionID) then
        return
    end

    if not slot then
        ActionAPI.ClearSlot(actionID)
        return
    end

    -- Pre-clear ensures stale content from a previous profile cannot persist when the
    -- new profile's action for this slot fails to restore (off-spec spell, deleted
    -- macro, pet no longer in collection, etc.).
    ActionAPI.ClearSlot(actionID)

    local picked, errMsg = SlotFiller.ActionResolver.PickupToCursor(slot, actionID, caches)
    if picked then
        ActionAPI.PlaceSlot(actionID)
    else
        if errMsg then
            addError(self, errMsg)
        end
        if ClearCursor then ClearCursor() end
    end
end

function SlotFiller.Restorer:ApplyProfile(profile)
    clearErrors(self)

    if not profile or type(profile.slots) ~= "table" then
        return false, "missing"
    end

    if SlotFiller.Context.IsCombatLocked() then
        return false, "combat"
    end

    if ClearCursor then
        ClearCursor()
    end

    local previousSound
    if GetCVar and SetCVar then
        previousSound = GetCVar("Sound_EnableAllSound")
        SetCVar("Sound_EnableAllSound", "0")
    end

    local macroBodyCache, macroNameCache, macroIDCache = self:BuildMacroCache()
    local caches = {
        spell     = ActionAPI.BuildSpellBookCache(),
        flyout    = ActionAPI.BuildFlyoutBookCache(),
        macroBody = macroBodyCache,
        macroName = macroNameCache,
        macroID   = macroIDCache,
    }

    -- Identify which profile slots need an Assisted Combat (SBA) button.
    local sbaTargetSet = {}
    local hasSBATargets = false
    for actionID = Constants.SLOT_MIN, Constants.SLOT_MAX do
        local slot = profile.slots[actionID]
        if slot and slot.type == Constants.ACTION_TYPE.SPELL and slot.subType == Constants.ACTION_SUBTYPE.ASSISTEDCOMBAT then
            sbaTargetSet[actionID] = true
            hasSBATargets = true
        end
    end

    -- Build a list of currently-SBA slots that are NOT already at a profile SBA target
    -- position; these are safe to use as pickup sources without disturbing correct slots.
    local spareSBASlots = {}
    if hasSBATargets then
        local currentSBA = findAllAssistedCombatSlots()
        for _, slotID in ipairs(currentSBA) do
            if not sbaTargetSet[slotID] then
                spareSBASlots[#spareSBASlots + 1] = slotID
            end
        end
    end

    -- Pass 1: Restore SBA slots before any bars are modified (avoids source destruction).
    if hasSBATargets then
        for actionID = Constants.SLOT_MIN, Constants.SLOT_MAX do
            if sbaTargetSet[actionID] then
                self:RestoreSBASlot(actionID, spareSBASlots)
            end
        end
    end

    -- Pass 2: Restore all remaining (non-SBA) slots.
    for actionID = Constants.SLOT_MIN, Constants.SLOT_MAX do
        if not sbaTargetSet[actionID] then
            self:RestoreSlot(actionID, profile.slots[actionID], caches)
        end
    end

    if previousSound ~= nil and SetCVar then
        SetCVar("Sound_EnableAllSound", previousSound)
    end

    return true, #self.lastErrors
end

function SlotFiller.Restorer:GetLastErrors()
    return self.lastErrors
end

function SlotFiller.Restorer:GetLastErrorsText()
    if #self.lastErrors == 0 then
        return Text.NO_ERRORS
    end
    return table.concat(self.lastErrors, "\n")
end
