local _, SlotFiller = ...

local Constants = SlotFiller.Constants
local ActionAPI = SlotFiller.ActionAPI
local SpellBookAPI = SlotFiller.SpellBookAPI
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
        addError(self, string.format(Text.RESTORE_SBA_NO_SOURCE, actionID))
        return
    end

    if not PickupAction then
        addError(self, string.format(Text.RESTORE_SBA_API_MISSING, actionID))
        return
    end

    PickupAction(sourceSlot)
    local cursorType = GetCursorInfo and GetCursorInfo()
    if cursorType and cursorType ~= "" then
        ActionAPI.PlaceSlot(actionID)
        if ClearCursor then ClearCursor() end  -- discard any old content swapped off the target slot
    else
        if ClearCursor then ClearCursor() end
        addError(self, string.format(Text.RESTORE_SBA_PICKUP_FAILED, actionID, sourceSlot))
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

    local macroBodyCache, macroNameCache, macroIDCache = SlotFiller.MacroResolver:BuildMacroCache()
    local caches = {
        spell     = SpellBookAPI.BuildSpellBookCache(),
        flyout    = SpellBookAPI.BuildFlyoutBookCache(),
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
            if actionID % Constants.ASYNC_YIELD_BATCH == 0 then
                SlotFiller.Async.MaybeYield()
            end
        end
    end

    -- Pass 2: Restore all remaining (non-SBA) slots.
    for actionID = Constants.SLOT_MIN, Constants.SLOT_MAX do
        if not sbaTargetSet[actionID] then
            self:RestoreSlot(actionID, profile.slots[actionID], caches)
        end
        if actionID % Constants.ASYNC_YIELD_BATCH == 0 then
            SlotFiller.Async.MaybeYield()
        end
    end

    if profile.petSlots then
        SlotFiller.PetBar:Apply(profile.petSlots)
    end

    if profile.clickBindings then
        for _, message in ipairs(SlotFiller.ClickBindings:Apply(profile.clickBindings, caches)) do
            addError(self, message)
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
