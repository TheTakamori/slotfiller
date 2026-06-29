local _, SlotFiller = ...

local Text = SlotFiller.Text

SlotFiller.ProfileActions = {}

function SlotFiller.ProfileActions:Save(profileName)
    if not profileName or profileName == "" then
        SlotFiller.Print(Text.PROFILE_NAME_REQUIRED)
        return false
    end
    if not SlotFiller.Context.RequireNotInCombat() then
        return false
    end

    local profile = SlotFiller.Scanner:CaptureCurrentProfile()
    -- Preserve the existing auto-load config so that Save As (new profile)
    -- starts with no config, while Update (existing profile) keeps its config.
    local existing = SlotFiller.State:GetProfile(profileName)
    if existing and existing.autoLoad then
        profile.autoLoad = existing.autoLoad
    end
    local slotCount = SlotFiller.Normalizer.CountFilledSlots(profile)
    SlotFiller.State:SetProfile(profileName, profile)
    SlotFiller.State:SetActiveProfile(profileName)
    if slotCount == 0 then
        SlotFiller.Print(string.format(Text.SAVE_EMPTY, profileName))
    else
        SlotFiller.Print(string.format(Text.SAVE_SUCCESS, profileName, slotCount))
    end
    return true
end

function SlotFiller.ProfileActions:Load(profileName)
    if not profileName or profileName == "" then
        SlotFiller.Print(Text.PROFILE_NAME_REQUIRED)
        return false
    end

    local profile = SlotFiller.State:GetProfile(profileName)
    if not profile then
        SlotFiller.Print(string.format(Text.PROFILE_NOT_FOUND, profileName))
        return false
    end
    if not SlotFiller.Context.RequireNotInCombat() then
        return false
    end

    local ok, result = SlotFiller.Restorer:ApplyProfile(profile)
    if not ok then
        if result == "combat" then
            SlotFiller.Print(Text.COMBAT_BLOCKED)
        end
        return false
    end

    SlotFiller.State:SetActiveProfile(profileName)
    if result and result > 0 then
        SlotFiller.Print(string.format(Text.RESTORE_ERRORS, profileName, result))
    else
        SlotFiller.Print(string.format(Text.RESTORE_CLEAN, profileName))
    end
    return true
end

function SlotFiller.ProfileActions:Delete(profileName)
    if not profileName or profileName == "" then
        SlotFiller.Print(Text.PROFILE_NAME_REQUIRED)
        return false
    end
    if not SlotFiller.State:DeleteProfile(profileName) then
        SlotFiller.Print(string.format(Text.PROFILE_NOT_FOUND, profileName))
        return false
    end
    SlotFiller.Print(string.format(Text.DELETE_SUCCESS, profileName))
    return true
end

function SlotFiller.ProfileActions:Rename(oldName, newName)
    if not oldName or oldName == "" or not newName or newName == "" then
        SlotFiller.Print(Text.INVALID_RENAME)
        return false
    end
    if oldName == newName then
        SlotFiller.Print(Text.SAME_PROFILE_NAME)
        return false
    end

    local ok, reason = SlotFiller.State:RenameProfile(oldName, newName)
    if not ok then
        if reason == "exists" then
            SlotFiller.Print(string.format(Text.PROFILE_EXISTS, newName))
        else
            SlotFiller.Print(string.format(Text.PROFILE_NOT_FOUND, oldName))
        end
        return false
    end

    SlotFiller.Print(string.format(Text.RENAME_SUCCESS, oldName, newName))
    return true
end

function SlotFiller.ProfileActions:Duplicate(sourceName, newName)
    if not sourceName or sourceName == "" or not newName or newName == "" then
        SlotFiller.Print(Text.PROFILE_NAME_REQUIRED)
        return false
    end

    local ok, reason = SlotFiller.State:DuplicateProfile(sourceName, newName)
    if not ok then
        if reason == "exists" then
            SlotFiller.Print(string.format(Text.PROFILE_EXISTS, newName))
        else
            SlotFiller.Print(string.format(Text.PROFILE_NOT_FOUND, sourceName))
        end
        return false
    end

    SlotFiller.Print(string.format(Text.DUPLICATE_SUCCESS, sourceName, newName))
    return true
end

function SlotFiller.ProfileActions:List()
    local names = SlotFiller.State:ListProfileNames()
    SlotFiller.Print(Text.LIST_HEADER)
    if #names == 0 then
        SlotFiller.Print(Text.LIST_EMPTY)
        return
    end
    SlotFiller.Print(table.concat(names, ", "))
end

function SlotFiller.ProfileActions:Overwrite(profileName)
    if not SlotFiller.State:GetProfile(profileName) then
        SlotFiller.Print(string.format(Text.PROFILE_NOT_FOUND, profileName))
        return false
    end
    return self:Save(profileName)
end
