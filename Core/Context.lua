local _, SlotFiller = ...

local Constants = SlotFiller.Constants
local Text = SlotFiller.Text

SlotFiller.Context = {}

function SlotFiller.Context.GetPlayerGUID()
    if not UnitGUID then
        return nil
    end
    return UnitGUID("player")
end

-- Returns localizedClass, classFile, classID for the current player.
local function getPlayerClassData()
    if UnitClass then
        return UnitClass("player")
    end
    return nil, nil, nil
end

function SlotFiller.Context.GetPlayerName()
    if UnitName then
        return UnitName("player")
    end
    return nil
end

function SlotFiller.Context.GetRealmName()
    if GetRealmName then
        return GetRealmName()
    end
    return nil
end

function SlotFiller.Context.GetClassName()
    local name = getPlayerClassData()
    return name
end

function SlotFiller.Context.GetClassFile()
    local _, file = getPlayerClassData()
    return file
end

function SlotFiller.Context.GetClassID()
    local _, _, id = getPlayerClassData()
    return id
end

-- Returns a sorted array of { name, file, id } for all playable classes.
function SlotFiller.Context.GetAllClasses()
    local classes = {}
    if not GetNumClasses or not GetClassInfo then return classes end
    for i = 1, GetNumClasses() do
        local name, file = GetClassInfo(i)
        if name and file then
            classes[#classes + 1] = { name = name, file = file, id = i }
        end
    end
    table.sort(classes, function(a, b) return a.name < b.name end)
    return classes
end

-- Returns a sorted array of { name, index } for the specs of the given classID.
function SlotFiller.Context.GetSpecsForClass(classID)
    local specs = {}
    if not classID then return specs end
    local numFn  = GetNumSpecializationsForClassID
    local infoFn = GetSpecializationInfoForClassID
    if not numFn or not infoFn then return specs end
    local count = numFn(classID)
    if not count or count == 0 then return specs end
    for i = 1, count do
        local _, name = infoFn(classID, i)
        if name then
            specs[#specs + 1] = { name = name, index = i }
        end
    end
    return specs
end

function SlotFiller.Context.GetSpecIndex()
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        return C_SpecializationInfo.GetSpecialization()
    end
    if GetSpecialization then
        return GetSpecialization()
    end
    return nil
end

function SlotFiller.Context.GetSpecName(specIndex)
    specIndex = specIndex or SlotFiller.Context.GetSpecIndex()
    if not specIndex then
        return nil
    end

    if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
        local _, name = C_SpecializationInfo.GetSpecializationInfo(specIndex)
        return name
    end
    if GetSpecializationInfo then
        local _, name = GetSpecializationInfo(specIndex)
        return name
    end
    return "Spec " .. tostring(specIndex)
end

function SlotFiller.Context.IsCombatLocked()
    return InCombatLockdown and InCombatLockdown()
end

function SlotFiller.Context.RequireReady()
    if not SlotFiller.Context.GetPlayerGUID() then
        SlotFiller.Print(Text.NO_CHARACTER)
        return false
    end
    if not SlotFiller.Context.GetSpecIndex() then
        SlotFiller.Print(Text.NO_SPEC)
        return false
    end
    return true
end

function SlotFiller.Context.RequireNotInCombat()
    if SlotFiller.Context.IsCombatLocked() then
        SlotFiller.Print(Text.COMBAT_BLOCKED)
        return false
    end
    return true
end

function SlotFiller.Context.GetScope()
    local specIndex = SlotFiller.Context.GetSpecIndex()
    if not specIndex then
        return nil
    end
    return {
        specName = SlotFiller.Context.GetSpecName(specIndex),
    }
end
