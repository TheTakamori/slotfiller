local _, SlotFiller = ...

-- Index layer for the profile manager's auto-load filter dropdowns
-- (Characters / Classes / Specs). Derives prepared option lists and prunes
-- now-invalid selections from State/Context data so UI/MainFrame.lua only
-- ever renders models handed to it, instead of filtering/sorting raw class
-- and character data itself.
SlotFiller.AutoLoadIndex = {}

-- selectedChars is a set: "Name-Realm" -> true.
-- Returns a sorted array of { name, file, id } for classes eligible given the
-- current character selection. With no character selected, every playable
-- class is eligible.
function SlotFiller.AutoLoadIndex.GetEligibleClasses(selectedChars)
    if next(selectedChars) == nil then
        return SlotFiller.Context.GetAllClasses()
    end

    local allClasses = SlotFiller.Context.GetAllClasses()
    local classByFile = {}
    for _, ci in ipairs(allClasses) do classByFile[ci.file] = ci end

    local known  = SlotFiller.State:GetKnownCharacters()
    local seen   = {}
    local result = {}
    for _, info in ipairs(known) do
        if selectedChars[info.key] and not seen[info.file] then
            seen[info.file] = true
            local ci = classByFile[info.file]
            if ci then result[#result + 1] = ci end
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

-- selectedClasses is a set: "PALADIN" -> true.
-- Returns an array of { key, label } for specs of every selected class,
-- where key is the spec name (used for matching) and label is "Class — Spec"
-- (used for display).
function SlotFiller.AutoLoadIndex.GetEligibleSpecs(selectedClasses)
    local allClasses = SlotFiller.Context.GetAllClasses()
    local classById  = {}
    for _, ci in ipairs(allClasses) do classById[ci.file] = ci end

    local classFiles = {}
    for file in pairs(selectedClasses) do classFiles[#classFiles + 1] = file end
    table.sort(classFiles)

    local result = {}
    for _, file in ipairs(classFiles) do
        local ci = classById[file]
        if ci then
            for _, spec in ipairs(SlotFiller.Context.GetSpecsForClass(ci.id)) do
                result[#result + 1] = {
                    key   = spec.name,
                    label = ci.name .. " — " .. spec.name,
                }
            end
        end
    end
    return result
end

-- Removes any selectedClasses entry that is no longer eligible given
-- selectedChars (mutates selectedClasses in place). No-op while no character
-- is selected, since every class is eligible in that state.
function SlotFiller.AutoLoadIndex.PruneInvalidClasses(selectedChars, selectedClasses)
    if next(selectedChars) == nil then return end
    local eligible = SlotFiller.AutoLoadIndex.GetEligibleClasses(selectedChars)
    local valid    = {}
    for _, ci in ipairs(eligible) do valid[ci.file] = true end
    for file in pairs(selectedClasses) do
        if not valid[file] then selectedClasses[file] = nil end
    end
end

-- Removes any selectedSpecs entry that is no longer eligible given
-- selectedClasses (mutates selectedSpecs in place). Clears all specs when no
-- class is selected, since a spec can only be eligible under a chosen class.
function SlotFiller.AutoLoadIndex.PruneInvalidSpecs(selectedClasses, selectedSpecs)
    if next(selectedClasses) == nil then
        for k in pairs(selectedSpecs) do selectedSpecs[k] = nil end
        return
    end
    local eligible = SlotFiller.AutoLoadIndex.GetEligibleSpecs(selectedClasses)
    local valid    = {}
    for _, s in ipairs(eligible) do valid[s.key] = true end
    for key in pairs(selectedSpecs) do
        if not valid[key] then selectedSpecs[key] = nil end
    end
end
