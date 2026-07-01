local _, SlotFiller = ...

local Constants = SlotFiller.Constants
local Defaults = SlotFiller.Defaults

SlotFiller.State = {}

-- Catch-all auto-load config returned when a profile has no autoLoad table
-- yet (new profile) or doesn't exist at all. A fresh table is built on every
-- call so callers can freely mutate the returned arrays.
local function defaultAutoLoad()
    return { enabled = false, characters = {}, classes = {}, specs = {} }
end

local function copyDefaults(defaults, target)
    target = target or {}
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = copyDefaults(value, target[key] or {})
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

-- Cached after the first call so every other accessor below (most of which
-- run on hot paths like dropdown rebuilds) doesn't re-walk the full defaults
-- tree via copyDefaults on every call. Safe for the addon's lifetime: WoW
-- populates _G[SAVED_VARIABLES] once, before ADDON_LOADED fires, and nothing
-- in this addon ever replaces that table's identity afterward.
local cachedDB = nil
local cachedKnownCharacters = nil

function SlotFiller.State:GetDB()
    if cachedDB == nil then
        cachedDB = copyDefaults(Defaults.Get(), _G[Constants.SAVED_VARIABLES] or {})
        _G[Constants.SAVED_VARIABLES] = cachedDB
    end
    return cachedDB
end

function SlotFiller.State:ResetForTests()
    cachedDB = copyDefaults(Defaults.Get(), {})
    cachedKnownCharacters = nil
    _G[Constants.SAVED_VARIABLES] = cachedDB
    return cachedDB
end

function SlotFiller.State:GetMinimapSettings()
    return self:GetDB().minimap
end

function SlotFiller.State:GetKnownCharactersTable()
    local db = self:GetDB()
    if not db.knownCharacters then
        db.knownCharacters = {}
    end
    return db.knownCharacters
end

function SlotFiller.State:TrackCharacter(nameRealm, classFile, classID)
    self:GetKnownCharactersTable()[nameRealm] = { file = classFile, classID = classID }
    cachedKnownCharacters = nil
end

-- Rebuilds and sorts the character list lazily; cached until the next
-- TrackCharacter call invalidates it. Avoids re-allocating and re-sorting on
-- every dropdown-menu open, which previously happened on every call.
function SlotFiller.State:GetKnownCharacters()
    if cachedKnownCharacters == nil then
        local t = self:GetKnownCharactersTable()
        local list = {}
        for key, info in pairs(t) do
            list[#list + 1] = { key = key, file = info.file, classID = info.classID }
        end
        table.sort(list, function(a, b) return a.key < b.key end)
        cachedKnownCharacters = list
    end
    return cachedKnownCharacters
end

-- Returns a copy of the array `t` (or a new empty array when `t` is nil).
local function copyArray(t)
    local copy = {}
    for i, v in ipairs(t or {}) do copy[i] = v end
    return copy
end

function SlotFiller.State:GetProfileAutoLoad(profileName)
    local profile = self:GetProfile(profileName)
    if not profile then return defaultAutoLoad() end
    local al = profile.autoLoad
    if not al then return defaultAutoLoad() end
    -- Always return independent copies of the saved arrays: callers (e.g. the
    -- profile manager's filter dropdowns) treat the result as a free-standing
    -- snapshot to mutate locally, and mutating a live reference here would
    -- silently corrupt SavedVariables outside of SetProfileAutoLoad.
    return {
        enabled    = al.enabled == true,
        characters = copyArray(al.characters),
        classes    = copyArray(al.classes),
        specs      = copyArray(al.specs),
    }
end

function SlotFiller.State:SetProfileAutoLoad(profileName, autoLoad)
    local profile = self:GetProfile(profileName)
    if not profile then return end
    profile.autoLoad = autoLoad
end

function SlotFiller.State:GetGlobalRecord()
    local db = self:GetDB()
    if db.profiles == nil then
        db.profiles = {}
    end
    return db
end

function SlotFiller.State:GetProfile(profileName)
    return self:GetGlobalRecord().profiles[profileName]
end

function SlotFiller.State:SetProfile(profileName, profile)
    self:GetGlobalRecord().profiles[profileName] = profile
end

function SlotFiller.State:DeleteProfile(profileName)
    local rec = self:GetGlobalRecord()
    if not rec.profiles[profileName] then
        return false
    end
    rec.profiles[profileName] = nil
    if rec.activeProfile == profileName then
        rec.activeProfile = nil
    end
    return true
end

function SlotFiller.State:RenameProfile(oldName, newName)
    local rec = self:GetGlobalRecord()
    local profile = rec.profiles[oldName]
    if not profile then
        return false, "missing"
    end
    if rec.profiles[newName] then
        return false, "exists"
    end
    rec.profiles[newName] = profile
    rec.profiles[oldName] = nil
    if rec.activeProfile == oldName then
        rec.activeProfile = newName
    end
    return true
end

function SlotFiller.State:DuplicateProfile(sourceName, newName)
    local rec = self:GetGlobalRecord()
    local source = rec.profiles[sourceName]
    if not source then
        return false, "missing"
    end
    if rec.profiles[newName] then
        return false, "exists"
    end
    rec.profiles[newName] = SlotFiller.Normalizer.CloneProfile(source)
    return true
end

function SlotFiller.State:SetActiveProfile(profileName)
    self:GetGlobalRecord().activeProfile = profileName
end

function SlotFiller.State:GetActiveProfileName()
    return self:GetGlobalRecord().activeProfile
end

function SlotFiller.State:ListProfileNames()
    local rec = self:GetGlobalRecord()
    local names = {}
    for profileName in pairs(rec.profiles) do
        names[#names + 1] = profileName
    end
    table.sort(names, function(left, right)
        return left:lower() < right:lower()
    end)
    return names
end

function SlotFiller.State:SetMinimapHidden(hidden)
    self:GetMinimapSettings().hidden = hidden and true or false
end

function SlotFiller.State:IsMinimapHidden()
    return self:GetMinimapSettings().hidden == true
end

function SlotFiller.State:GetMinimapAngle()
    return self:GetMinimapSettings().angle or Defaults.Get().minimap.angle
end

function SlotFiller.State:SetMinimapAngle(angle)
    self:GetMinimapSettings().angle = angle
end
