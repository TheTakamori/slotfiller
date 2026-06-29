local _, SlotFiller = ...

SlotFiller.AutoLoad = {}

-- Returns true if the value exists in the array table.
local function contains(t, value)
    for _, v in ipairs(t) do
        if v == value then return true end
    end
    return false
end

-- A profile conflicts with the current context when it has a non-empty filter
-- that does NOT include the current value for that dimension.  Empty filters
-- mean "match any" and never produce a conflict.
local function isConflict(autoLoad, characterKey, classFile, specName)
    local chars   = autoLoad.characters or {}
    local classes = autoLoad.classes    or {}
    local specs   = autoLoad.specs      or {}

    if #chars   > 0 and characterKey and not contains(chars,   characterKey) then return true end
    if #classes > 0 and classFile    and not contains(classes, classFile)    then return true end
    if #specs   > 0 and specName     and not contains(specs,   specName)     then return true end
    return false
end

-- Score measures how specifically a candidate matches the current context.
-- Only non-empty filters that do match contribute — an empty filter scores 0
-- for that dimension (it means "any", not a targeted match).
local function scoreCandidate(autoLoad, classFile, specName)
    local s = 0
    local classes = autoLoad.classes or {}
    local specs   = autoLoad.specs   or {}
    if #classes > 0 and classFile and contains(classes, classFile) then s = s + 2 end
    if #specs   > 0 and specName  and contains(specs,   specName)  then s = s + 1 end
    return s
end

-- Finds the best auto-load profile for the given context.
-- Returns the profile name, or nil if nothing qualifies.
--
-- Algorithm:
--   1. Eliminate conflicting profiles.
--   2. If any remaining candidate specifically lists the current character,
--      restrict the pool to those character-matched candidates.
--   3. Pick the highest-scoring candidate (class match +2, spec match +1).
function SlotFiller.AutoLoad.FindBestProfile(characterKey, classFile, specName)
    local rec = SlotFiller.State:GetGlobalRecord()
    local candidates = {}

    for profileName, profile in pairs(rec.profiles) do
        local autoLoad = profile.autoLoad or {}
        if autoLoad.enabled and not isConflict(autoLoad, characterKey, classFile, specName) then
            candidates[#candidates + 1] = { name = profileName, autoLoad = autoLoad }
        end
    end

    if #candidates == 0 then return nil end

    -- Prefer profiles that explicitly target the current character.
    local charMatched = {}
    for _, c in ipairs(candidates) do
        local chars = c.autoLoad.characters or {}
        if characterKey and #chars > 0 and contains(chars, characterKey) then
            charMatched[#charMatched + 1] = c
        end
    end

    local pool = #charMatched > 0 and charMatched or candidates

    local bestName  = nil
    local bestScore = -1
    for _, c in ipairs(pool) do
        local s = scoreCandidate(c.autoLoad, classFile, specName)
        if s > bestScore then
            bestScore = s
            bestName  = c.name
        end
    end

    return bestName
end
