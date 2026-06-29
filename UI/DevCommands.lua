local _, SlotFiller = ...

local Constants = SlotFiller.Constants

-- Wrap the production slash handler to intercept dev-only commands.
-- This file is excluded from release builds; in production the commands
-- fall through to the normal handler, which shows help.
local _Handle = SlotFiller.UI.SlashCommands.Handle

function SlotFiller.UI.SlashCommands:Handle(message)
    local parsed = SlotFiller.SlashParser.Parse(message)
    local verb   = parsed.verb

    if verb == Constants.COMMAND.SCAN then
        local lines = {}
        local count = 0
        for actionID = Constants.SLOT_MIN, Constants.SLOT_MAX do
            local actionType, id, subType, extraID = SlotFiller.ActionAPI.GetSlotActionInfo(actionID)
            if actionType and actionType ~= "" then
                count = count + 1
                lines[#lines + 1] = string.format("[%d] type=%s id=%s sub=%s extra=%s",
                    actionID, tostring(actionType), tostring(id),
                    tostring(subType), tostring(extraID))
            end
        end
        lines[#lines + 1] = string.format("Scan complete: %d occupied slots.", count)
        SlotFiller.UI.CopyFrame:Show(table.concat(lines, "\n"))
        SlotFiller.Print("Scan complete: " .. count .. " occupied slots. Ctrl+C in the popup to copy.")
        return
    end

    if verb == Constants.COMMAND.ERRORS then
        SlotFiller.UI.CopyFrame:Show(SlotFiller.Restorer:GetLastErrorsText())
        SlotFiller.Print("Restore issues shown in popup. Ctrl+C to copy.")
        return
    end

    if verb == Constants.COMMAND.SBA then
        local lines = {}
        lines[#lines+1] = "=== SBA API Diagnostics ==="
        lines[#lines+1] = "C_ActionBar exists: " .. tostring(C_ActionBar ~= nil)
        lines[#lines+1] = "IsAssistedCombatAction: "
            .. tostring(C_ActionBar and C_ActionBar.IsAssistedCombatAction ~= nil)
        lines[#lines+1] = "FindAssistedCombatActionButtons: "
            .. tostring(C_ActionBar and C_ActionBar.FindAssistedCombatActionButtons ~= nil)
        if C_ActionBar and C_ActionBar.FindAssistedCombatActionButtons then
            local slots = C_ActionBar.FindAssistedCombatActionButtons()
            if slots then
                lines[#lines+1] = "FindAssistedCombatActionButtons slots: " .. table.concat(slots, ", ")
            else
                lines[#lines+1] = "FindAssistedCombatActionButtons returned nil"
            end
        end
        lines[#lines+1] = "--- GetActionInfo scan for assistedcombat ---"
        for actionID = 1, 12 do
            local t, id, sub = SlotFiller.ActionAPI.GetSlotActionInfo(actionID)
            if t and t ~= "" then
                lines[#lines+1] = string.format("[%d] type=%s id=%s sub=%s IsAC=%s",
                    actionID, tostring(t), tostring(id), tostring(sub),
                    tostring(C_ActionBar and C_ActionBar.IsAssistedCombatAction
                        and C_ActionBar.IsAssistedCombatAction(actionID)))
            end
        end
        lines[#lines+1] = "--- Spellbook assistedcombat scan ---"
        if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
            for tabIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() do
                local info = C_SpellBook.GetSpellBookSkillLineInfo(tabIndex)
                if info then
                    local offset = info.itemIndexOffset or 0
                    for i = 1, (info.numSpellBookItems or 0) do
                        local bookIndex = offset + i
                        local itemInfo  = C_SpellBook.GetSpellBookItemInfo(bookIndex, 0)
                        if itemInfo then
                            local t = type(itemInfo.itemType) == "string"
                                and string.lower(itemInfo.itemType) or tostring(itemInfo.itemType)
                            if t == "assistedcombat"
                                or (Enum and Enum.SpellBookItemType
                                    and itemInfo.itemType == Enum.SpellBookItemType.AssistedCombat) then
                                lines[#lines+1] = string.format(
                                    "Found SBA in spellbook: tab=%d bookIdx=%d name=%s itemType=%s",
                                    tabIndex, bookIndex,
                                    tostring(itemInfo.name), tostring(itemInfo.itemType))
                                C_SpellBook.PickupSpellBookItem(bookIndex, 0)
                                local ct = GetCursorInfo and GetCursorInfo()
                                lines[#lines+1] = "  After PickupSpellBookItem cursor: " .. tostring(ct)
                                if ClearCursor then ClearCursor() end
                            end
                        end
                    end
                end
            end
        else
            lines[#lines+1] = "C_SpellBook.GetNumSpellBookSkillLines not available"
        end
        SlotFiller.UI.CopyFrame:Show(table.concat(lines, "\n"))
        SlotFiller.Print("SBA diagnostics shown in popup.")
        return
    end

    return _Handle(self, message)
end
