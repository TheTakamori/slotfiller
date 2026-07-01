local _, SlotFiller = ...

local Constants = SlotFiller.Constants

SlotFiller.Text = {
    LOADED = Constants.ADDON_TITLE .. " loaded. Use " .. Constants.SLASH_COMMAND .. " for profiles.",
    COMBAT_BLOCKED = "Cannot change action bar slots while in combat.",
    NO_SPEC = "No active specialization.",
    NO_CHARACTER = "Character data is not ready yet.",

    SAVE_SUCCESS = "Saved profile %s (%d slots).",
    SAVE_EMPTY = "Saved profile %s, but no slots were captured. Make sure actions are on your action bars.",
    DELETE_SUCCESS = "Deleted profile %s.",
    RENAME_SUCCESS = "Renamed %s to %s.",
    DUPLICATE_SUCCESS = "Duplicated %s as %s.",

    PROFILE_NOT_FOUND = "No profile named %s.",
    PROFILE_EXISTS = "Profile %s already exists.",
    PROFILE_NAME_REQUIRED = "Profile name is required.",
    SAME_PROFILE_NAME = "Old and new profile names are the same.",
    INVALID_RENAME = "Usage: " .. Constants.SLASH_COMMAND .. " rename <old> <new>",

    RESTORE_ERRORS = "Loaded profile %s with %d issue(s). Use " .. Constants.SLASH_COMMAND .. " errors.",
    RESTORE_CLEAN = "Loaded profile %s.",
    RESTORE_CORRUPT = "Profile %s could not be loaded. The saved data appears corrupt or incomplete.",
    RESTORE_ZONE_ABILITY_FAILED = "Zone ability in slot %d could not be restored. Enter a Draenor zone and reload the profile.",
    RESTORE_MACRO_LIMIT = "Cannot recreate character macro '%s' in slot %d: the "
        .. Constants.MAX_CHARACTER_MACROS_FALLBACK .. " character macro limit is full.",
    RESTORE_MACRO_CREATE_FAILED = "Cannot recreate character macro '%s' in slot %d: macro creation failed.",
    RESTORE_SPELL_FAILED = "Unable to restore spell %s to slot %d.",
    RESTORE_ITEM_FAILED = "Unable to restore item %s to slot %d.",
    RESTORE_MACRO_FAILED = "Unable to restore macro %s to slot %d.",
    RESTORE_FLYOUT_FAILED = "Unable to restore flyout %s to slot %d.",
    RESTORE_MOUNT_FAILED = "Unable to restore mount (id=%s) to slot %d.",
    RESTORE_PET_FAILED = "Unable to restore battle pet %s to slot %d. The pet may not be in your collection.",
    RESTORE_COMPANION_FAILED = "Unable to restore companion (id=%s, sub=%s) to slot %d.",
    RESTORE_EQUIPSET_FAILED = "Unable to restore equipment set %s to slot %d.",
    RESTORE_OUTFIT_FAILED = "Unable to restore outfit %s to slot %d.",
    RESTORE_UNKNOWN_TYPE = "Cannot restore action type '%s' in slot %d. Use /sfill scan for details.",
    RESTORE_CLICKBINDING_MACRO_LIMIT = "Cannot recreate click-cast macro '%s': the "
        .. Constants.MAX_CHARACTER_MACROS_FALLBACK .. " character macro limit is full.",
    RESTORE_CLICKBINDING_MACRO_FAILED = "Cannot restore click-cast macro '%s' for a click binding.",
    NO_ERRORS = "No restore issues recorded.",

    LIST_HEADER = "Saved profiles:",
    LIST_EMPTY = "No profiles saved yet.",

    UI_TITLE = Constants.ADDON_TITLE,
    UI_SAVE_PLACEHOLDER = "Profile name...",
    UI_SAVE = "Save As",
    UI_CLOSE = "Close",
    UI_LOAD = "Load",
    UI_OVERWRITE = "Update",
    UI_RENAME = "Rename",
    UI_DUPLICATE = "Duplicate",
    UI_DELETE = "Delete",
    UI_ACTIVE = "Active: %s",
    UI_CONFIRM_DELETE = "Delete profile %s?",
    UI_CONFIRM_OVERWRITE = "Update profile %s with current bar?",
    UI_RENAME_PROMPT = "Rename %s to:",
    UI_DUPLICATE_PROMPT = "Duplicate %s as:",
    -- Dropdown labels
    UI_PROFILE_LABEL     = "Profile:",
    UI_CHARACTERS_LABEL  = "Characters:",
    UI_CLASSES_LABEL     = "Classes:",
    UI_SPECS_LABEL       = "Specs:",
    UI_PROFILE_NONE      = "No profiles saved.",
    UI_AUTOLOAD_ANY      = "Any",
    UI_NO_CHARACTERS     = "Log in on a character first.",
    UI_AUTOLOAD_ENABLED  = "Allow Profile Auto Load",
    UI_AUTOLOAD_TITLE    = "Allow Profile Auto Load",
    UI_AUTOLOAD_HINT     =
        "When enabled, SlotFiller automatically loads a matching profile "
        .. "when you log in or switch specializations.\n\n"
        .. "A profile matches when none of its filters conflict with your "
        .. "current character, class, or specialization. Leave a filter set "
        .. "to Any to match all values for that dimension.\n\n"
        .. "If multiple profiles qualify, ones that explicitly list your "
        .. "character are preferred. Among those, the most specific match "
        .. "by class and specialization wins.",
    -- Copy frame
    UI_COPY_HINT = "Text is selected. Press Ctrl+C to copy, then close.",

    MINIMAP_TOOLTIP_TITLE = Constants.ADDON_TITLE,
    MINIMAP_TOOLTIP_OPEN = "Click to open profiles.",
    MINIMAP_TOOLTIP_TOGGLE = "Use " .. Constants.SLASH_COMMAND .. " minimap to show or hide this button.",
    MINIMAP_TOOLTIP_DRAG = "Drag to move this button.",
    MINIMAP_SHOWN = "Minimap button shown.",
    MINIMAP_HIDDEN = "Minimap button hidden. Use " .. Constants.SLASH_COMMAND .. " minimap to show it again.",

    SLASH_HELP_TITLE = Constants.ADDON_TITLE .. " commands:",
    SLASH_HELP_OPEN = Constants.SLASH_COMMAND .. " - Open profile manager",
    SLASH_HELP_SAVE = Constants.SLASH_COMMAND .. " save <name> - Save all action bar slots (main bars, class bars, skyriding, bars 6-8)",
    SLASH_HELP_LOAD = Constants.SLASH_COMMAND .. " load <name> - Load a profile",
    SLASH_HELP_SHORT = Constants.SLASH_COMMAND .. " <name> - Load a profile",
    SLASH_HELP_LIST = Constants.SLASH_COMMAND .. " list - List saved profiles",
    SLASH_HELP_DELETE = Constants.SLASH_COMMAND .. " delete <name> - Delete a profile",
    SLASH_HELP_RENAME = Constants.SLASH_COMMAND .. " rename <old> <new> - Rename a profile",
    SLASH_HELP_DUPLICATE = Constants.SLASH_COMMAND .. " duplicate <source> <new> - Duplicate a profile",
    SLASH_HELP_MINIMAP = Constants.SLASH_COMMAND .. " minimap - Show or hide the minimap button",
    SLASH_HELP_SCAN = Constants.SLASH_COMMAND .. " scan - Print raw action type/ID for every occupied slot (diagnostic)",
    SLASH_HELP_HELP = Constants.SLASH_COMMAND .. " help - Show this help",
}

function SlotFiller.Print(message)
    local line = Constants.CHAT_PREFIX .. message
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(line)
    else
        print(line)
    end
end
