local _, SlotFiller = ...

local Constants = SlotFiller.Constants
local Text = SlotFiller.Text
local Strings = SlotFiller.Strings

SlotFiller.SlashParser = {}

local function splitOnce(text)
    local first, rest = text:match("^(%S+)%s*(.*)$")
    return first, Strings.Trim(rest)
end

function SlotFiller.SlashParser.Parse(message)
    local trimmed = Strings.Trim(message)
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
            newName = Strings.Trim(newName),
        }
    end
    if verb == Constants.COMMAND.DUPLICATE then
        local sourceName, newName = rest:match("^(%S+)%s+(.+)$")
        return {
            verb = Constants.COMMAND.DUPLICATE,
            sourceName = sourceName,
            newName = Strings.Trim(newName),
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
    -- Explicit "open" typed as a word (empty input uses the early-return path above).
    if verb == Constants.COMMAND.OPEN then
        return { verb = Constants.COMMAND.OPEN }
    end
    -- Guard: prevent reserved command words from being treated as profile shorthand-loads.
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
    SlotFiller.Print(Text.SLASH_HELP_SCAN)
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

    if verb == Constants.COMMAND.ERRORS then
        local errors = SlotFiller.Restorer:GetLastErrors()
        if #errors == 0 then
            SlotFiller.Print(Text.NO_ERRORS)
        else
            for _, line in ipairs(errors) do
                SlotFiller.Print(line)
            end
        end
        return
    end

    if not SlotFiller.Context.RequireReady() then
        return
    end

    if verb == Constants.COMMAND.SCAN then
        local count = 0
        for actionID = Constants.SLOT_MIN, Constants.SLOT_MAX do
            local actionType, id, subType, extraID = SlotFiller.ActionAPI.GetSlotActionInfo(actionID)
            if actionType and actionType ~= "" then
                count = count + 1
                SlotFiller.Print(string.format("[%d] type=%s id=%s sub=%s extra=%s",
                    actionID, tostring(actionType), tostring(id),
                    tostring(subType), tostring(extraID)))
            end
        end
        SlotFiller.Print(string.format("Scan complete: %d occupied slots.", count))
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
