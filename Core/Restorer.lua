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

function SlotFiller.Restorer:RestoreSlot(actionID, slot, caches)
    if ClearCursor then ClearCursor() end

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

    -- Assisted Combat (SBA) slots need no special handling here: Scanner
    -- captures the button's currently-suggested spell as an ordinary spell
    -- id (see Scanner.lua), so it restores through this same single pass via
    -- ActionResolver's normal spell pickup path.
    for actionID = Constants.SLOT_MIN, Constants.SLOT_MAX do
        self:RestoreSlot(actionID, profile.slots[actionID], caches)
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
