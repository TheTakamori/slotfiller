local _, SlotFiller = ...

local Constants = SlotFiller.Constants
local Text = SlotFiller.Text

SlotFiller.SlashParser = {}

local function trim(text)
    return (text or ""):match("^%s*(.-)%s*$") or ""
end

local function splitOnce(text)
    local first, rest = text:match("^(%S+)%s*(.*)$")
    return first, trim(rest)
end

function SlotFiller.SlashParser.Parse(message)
    local trimmed = trim(message)
    if trimmed == "" then
        return { verb = Constants.COMMAND.OPEN }
    end

    local verb, rest = splitOnce(trimmed)
    verb = string.lower(verb)

    if verb == Constants.COMMAND.SAVE then
        return { verb = Constants.COMMAND.SAVE, profileName = rest }
    end
    if verb == Constants.COMMAND.LOAD or verb == Constants.COMMAND.APPLY or verb == Constants.COMMAND.USE then
        return { verb = Constants.COMMAND.LOAD, profileName = rest }
    end
    if verb == Constants.COMMAND.LIST then
        return { verb = Constants.COMMAND.LIST }
    end
    if verb == Constants.COMMAND.DELETE then
        return { verb = Constants.COMMAND.DELETE, profileName = rest }
    end
    if verb == Constants.COMMAND.RENAME then
        local oldName, newName = rest:match("^(%S+)%s+(.+)$")
        return {
            verb = Constants.COMMAND.RENAME,
            oldName = oldName,
            newName = trim(newName),
        }
    end
    if verb == Constants.COMMAND.DUPLICATE then
        local sourceName, newName = rest:match("^(%S+)%s+(.+)$")
        return {
            verb = Constants.COMMAND.DUPLICATE,
            sourceName = sourceName,
            newName = trim(newName),
        }
    end
    if verb == Constants.COMMAND.HELP then
        return { verb = Constants.COMMAND.HELP }
    end
    if verb == Constants.COMMAND.MINIMAP then
        return { verb = Constants.COMMAND.MINIMAP }
    end
    if verb == Constants.COMMAND.SCAN then
        return { verb = Constants.COMMAND.SCAN }
    end
    if verb == Constants.COMMAND.SBA then
        return { verb = Constants.COMMAND.SBA }
    end
    if verb == Constants.COMMAND.ERRORS then
        return { verb = Constants.COMMAND.ERRORS }
    end
    if Constants.RESERVED_COMMANDS[verb] then
        return { verb = verb }
    end

    return { verb = Constants.COMMAND.LOAD, profileName = trimmed }
end

SlotFiller.UI = SlotFiller.UI or {}
SlotFiller.UI.SlashCommands = {}

local function showHelp()
    SlotFiller.Print(Text.SLASH_HELP_TITLE)
    SlotFiller.Print(Text.SLASH_HELP_OPEN)
    SlotFiller.Print(Text.SLASH_HELP_SAVE)
    SlotFiller.Print(Text.SLASH_HELP_LOAD)
    SlotFiller.Print(Text.SLASH_HELP_SHORT)
    SlotFiller.Print(Text.SLASH_HELP_LIST)
    SlotFiller.Print(Text.SLASH_HELP_DELETE)
    SlotFiller.Print(Text.SLASH_HELP_RENAME)
    SlotFiller.Print(Text.SLASH_HELP_DUPLICATE)
    SlotFiller.Print(Text.SLASH_HELP_MINIMAP)
    SlotFiller.Print(Text.SLASH_HELP_HELP)
end

function SlotFiller.UI.SlashCommands:Handle(message)
    local parsed = SlotFiller.SlashParser.Parse(message)
    local verb = parsed.verb

    if verb == Constants.COMMAND.OPEN then
        SlotFiller.UI.MainFrame:Toggle()
        return
    end
    if verb == Constants.COMMAND.HELP then
        showHelp()
        return
    end
    if verb == Constants.COMMAND.MINIMAP then
        SlotFiller.UI.MinimapButton:Ensure()
        SlotFiller.UI.MinimapButton:ToggleHidden()
        return
    end

    if not SlotFiller.Context.RequireReady() then
        return
    end

    local actions = SlotFiller.ProfileActions

    if verb == Constants.COMMAND.SAVE then
        actions:Save(parsed.profileName)
    elseif verb == Constants.COMMAND.LOAD then
        actions:Load(parsed.profileName)
    elseif verb == Constants.COMMAND.LIST then
        actions:List()
    elseif verb == Constants.COMMAND.DELETE then
        actions:Delete(parsed.profileName)
    elseif verb == Constants.COMMAND.RENAME then
        actions:Rename(parsed.oldName, parsed.newName)
    elseif verb == Constants.COMMAND.DUPLICATE then
        actions:Duplicate(parsed.sourceName, parsed.newName)
    else
        showHelp()
    end
end

function SlotFiller.UI.SlashCommands:Register()
    SLASH_SLOTFILLER1 = Constants.SLASH_COMMAND
    SlashCmdList.SLOTFILLER = function(message)
        SlotFiller.UI.SlashCommands:Handle(message)
    end
end
