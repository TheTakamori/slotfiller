local _, SlotFiller = ...

local Constants = SlotFiller.Constants
local Text = SlotFiller.Text
local Strings = SlotFiller.Strings

-- Confirmation/rename/duplicate/delete dialogs for the profile manager panel.
-- Dialogs are registered once here at load time (StaticPopupDialogs entries
-- are stable definitions; only the per-show `data` table changes), instead of
-- being rebuilt inside a button's OnClick handler on every click.
--
-- Each Show* function takes the target profile name and an `onSuccess(name)`
-- callback that the caller (UI/MainFrame.lua) uses to update its own
-- selectedProfile state and refresh — this module has no knowledge of
-- MainFrame's internals.
SlotFiller.UI = SlotFiller.UI or {}
SlotFiller.UI.ProfilePopups = {}

local Popups = SlotFiller.UI.ProfilePopups

local function getStaticPopupEditBox(dialog)
    if not dialog then return nil end
    return dialog.EditBox or dialog.editBox
end

local function getStaticPopupEditText(dialog)
    local editBox = getStaticPopupEditBox(dialog)
    if not editBox then return "" end
    return Strings.Trim(editBox:GetText())
end

-- Rename and Duplicate are identical shapes: an edit-box dialog seeded with
-- an existing profile name, calling the same-named SlotFiller.ProfileActions
-- method with (existingName, newName) whether the user clicks Accept or
-- presses Enter in the edit box. methodName is looked up dynamically (not
-- captured as a function reference) so tests can still stub
-- SlotFiller.ProfileActions[methodName] freely.
local function acceptEditBoxDialog(methodName)
    return function(dialog)
        local existingName = dialog.data.name
        local newName = getStaticPopupEditText(dialog)
        if SlotFiller.Context.RequireReady()
            and SlotFiller.ProfileActions[methodName](SlotFiller.ProfileActions, existingName, newName) then
            dialog.data.onSuccess(newName)
        end
    end
end

local function acceptEditBoxOnEnter(methodName)
    return function(editBox)
        local dialog = editBox:GetParent()
        local existingName = dialog.data.name
        local newName = Strings.Trim(editBox:GetText())
        if SlotFiller.Context.RequireReady()
            and SlotFiller.ProfileActions[methodName](SlotFiller.ProfileActions, existingName, newName) then
            dialog.data.onSuccess(newName)
        end
        if dialog then dialog:Hide() end
    end
end

StaticPopupDialogs.SLOTFILLER_OVERWRITE = {
    text = Text.UI_CONFIRM_OVERWRITE, button1 = YES, button2 = NO,
    OnAccept = function(dialog)
        local name = dialog.data.name
        if SlotFiller.Context.RequireReady()
            and SlotFiller.ProfileActions:Overwrite(name) then
            dialog.data.onSuccess(name)
        end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs.SLOTFILLER_RENAME = {
    text = Text.UI_RENAME_PROMPT, button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = true, maxLetters = Constants.MAX_PROFILE_NAME_LEN,
    OnAccept = acceptEditBoxDialog("Rename"),
    EditBoxOnEnterPressed = acceptEditBoxOnEnter("Rename"),
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs.SLOTFILLER_DUPLICATE = {
    text = Text.UI_DUPLICATE_PROMPT, button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = true, maxLetters = Constants.MAX_PROFILE_NAME_LEN,
    OnAccept = acceptEditBoxDialog("Duplicate"),
    EditBoxOnEnterPressed = acceptEditBoxOnEnter("Duplicate"),
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs.SLOTFILLER_DELETE = {
    text = Text.UI_CONFIRM_DELETE, button1 = YES, button2 = NO,
    OnAccept = function(dialog)
        local name = dialog.data.name
        if SlotFiller.Context.RequireReady()
            and SlotFiller.ProfileActions:Delete(name) then
            dialog.data.onSuccess(nil)
        end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function Popups.ShowOverwrite(profileName, onSuccess)
    if not profileName then return end
    if not SlotFiller.Context.RequireNotInCombat() then return end
    StaticPopup_Show("SLOTFILLER_OVERWRITE", profileName, nil, { name = profileName, onSuccess = onSuccess })
end

function Popups.ShowRename(profileName, onSuccess)
    if not profileName then return end
    StaticPopup_Show("SLOTFILLER_RENAME", profileName, nil, { name = profileName, onSuccess = onSuccess })
end

function Popups.ShowDuplicate(profileName, onSuccess)
    if not profileName then return end
    StaticPopup_Show("SLOTFILLER_DUPLICATE", profileName, nil, { name = profileName, onSuccess = onSuccess })
end

function Popups.ShowDelete(profileName, onSuccess)
    if not profileName then return end
    StaticPopup_Show("SLOTFILLER_DELETE", profileName, nil, { name = profileName, onSuccess = onSuccess })
end
