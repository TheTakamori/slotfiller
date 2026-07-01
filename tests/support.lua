---@diagnostic disable: undefined-global

local support = {}

local function is_array(tbl)
    if type(tbl) ~= "table" then
        return false
    end
    local count = 0
    for key in pairs(tbl) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false
        end
        count = count + 1
    end
    for index = 1, count do
        if tbl[index] == nil then
            return false
        end
    end
    return true
end

local function sorted_keys(tbl)
    local keys = {}
    for key in pairs(tbl or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)
    return keys
end

local function pretty(value, seen)
    if type(value) == "string" then
        return string.format("%q", value)
    end
    if type(value) ~= "table" then
        return tostring(value)
    end

    seen = seen or {}
    if seen[value] then
        return "<cycle>"
    end
    seen[value] = true

    local parts = {}
    if is_array(value) then
        for index = 1, #value do
            parts[#parts + 1] = pretty(value[index], seen)
        end
    else
        for _, key in ipairs(sorted_keys(value)) do
            parts[#parts + 1] = string.format("[%s]=%s", pretty(key, seen), pretty(value[key], seen))
        end
    end

    seen[value] = nil
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function deep_equal(left, right, seen)
    if left == right then
        return true
    end
    if type(left) ~= type(right) then
        return false
    end
    if type(left) ~= "table" then
        return false
    end

    seen = seen or {}
    if seen[left] ~= nil then
        return seen[left] == right
    end
    seen[left] = right

    local checked = {}
    for key, value in pairs(left) do
        if not deep_equal(value, right[key], seen) then
            return false
        end
        checked[key] = true
    end
    for key in pairs(right) do
        if not checked[key] then
            return false
        end
    end
    return true
end

support.assert = {}

function support.assert.equal(actual, expected, message)
    if actual == expected then
        return
    end
    error(string.format("%sExpected %s, got %s",
        message and (message .. "\n") or "", pretty(expected), pretty(actual)), 2)
end

function support.assert.same(actual, expected, message)
    if deep_equal(actual, expected) then
        return
    end
    error(string.format("%sExpected %s, got %s",
        message and (message .. "\n") or "", pretty(expected), pretty(actual)), 2)
end

function support.assert.isTrue(actual, message)
    if actual == true or (actual and actual ~= false) then
        return
    end
    error(string.format("%sExpected truthy, got %s",
        message and (message .. "\n") or "", pretty(actual)), 2)
end

function support.assert.isFalse(actual, message)
    if not actual then
        return
    end
    error(string.format("%sExpected falsy, got %s",
        message and (message .. "\n") or "", pretty(actual)), 2)
end

function support.assert.isNil(actual, message)
    if actual == nil then
        return
    end
    error(string.format("%sExpected nil, got %s",
        message and (message .. "\n") or "", pretty(actual)), 2)
end

function support.new_runner()
    local runner = {
        tests = {},
    }

    function runner:test(name, fn)
        self.tests[#self.tests + 1] = {
            name = name,
            fn = fn,
        }
    end

    function runner:run()
        local failed = 0
        for index = 1, #self.tests do
            local test = self.tests[index]
            local ok, err = pcall(test.fn)
            if not ok then
                failed = failed + 1
                io.stderr:write(string.format("FAIL %s\n%s\n", test.name, tostring(err)))
            end
        end
        if failed == 0 then
            io.stdout:write(string.format("PASS %d tests\n", #self.tests))
        end
        return failed == 0 and 0 or 1
    end

    return runner
end

local function install_wow_stubs()
    -- WoW globals used by addon logic that are absent from standard Lua
    _G.wipe = _G.wipe or function(t)
        for k in pairs(t) do t[k] = nil end
        return t
    end
end

-- Shared restore-cache shape builders, used by any spec that calls
-- ActionResolver.PickupToCursor / Restorer:ApplyProfile / ClickBindings:Apply
-- / MacroResolver:ResolveOrCreateMacro directly with a hand-built caches
-- table instead of one produced by Restorer:ApplyProfile itself.

-- Full shape expected by ActionResolver.PickupToCursor.
function support.empty_restore_caches()
    return { spell = {}, flyout = {}, macroBody = {}, macroName = {}, macroID = {} }
end

-- Macro-only shape expected by MacroResolver:ResolveOrCreateMacro and
-- ClickBindings:Apply, which never touch the spell/flyout caches.
function support.empty_macro_caches()
    return { macroBody = {}, macroName = {}, macroID = {} }
end

function support.load_addon(root)
    install_wow_stubs()
    SlotFiller = {}
    local function load(path)
        local chunk, err = loadfile(root .. "/" .. path)
        if not chunk then
            error(err)
        end
        chunk("SlotFiller", SlotFiller)
    end

    load("Core/Constants.lua")
    load("Core/WoWConstants.lua")
    load("Core/Strings.lua")
    load("Core/Text.lua")
    load("Core/Defaults.lua")
    load("Core/Async.lua")
    load("Core/Hooks.lua")
    load("Core/Normalizer.lua")
    load("Core/Context.lua")
    load("Core/State.lua")
    load("Core/AutoLoad.lua")
    load("Core/ProfileIndex.lua")
    load("Core/ProfileActions.lua")
    load("UI/SlashCommands.lua")
end

-- Loads the full addon including WoW-API-dependent modules. ActionAPI,
-- PetActionAPI, ClickBindingAPI, Scanner, and Restorer all guard their WoW
-- API calls so they run safely in a plain Lua host.
function support.load_full(root)
    support.load_addon(root)
    -- ClearCursor is called on several unguarded code paths across
    -- ActionAPI/Restorer/PetBar/ClickBindings; stub it once here instead of
    -- in every spec file that loads the full addon.
    _G.ClearCursor = _G.ClearCursor or function() end
    local function load(path)
        local chunk = assert(loadfile(root .. "/" .. path))
        chunk("SlotFiller", SlotFiller)
    end
    load("Core/ActionAPI.lua")
    load("Core/SpellBookAPI.lua")
    load("Core/PetActionAPI.lua")
    load("Core/ClickBindingAPI.lua")
    load("Core/MacroResolver.lua")
    load("Core/ActionResolver.lua")
    load("Core/PetBar.lua")
    load("Core/ClickBindings.lua")
    load("Core/Scanner.lua")
    load("Core/Restorer.lua")
end

return support
