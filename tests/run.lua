local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/run%.lua$") or "."

-- Override with `LUARUN=luajit lua tests/run.lua` (or similar) on a host
-- where the plain `lua` interpreter isn't on PATH but another Lua 5.1+
-- compatible one is.
local interpreter = os.getenv("LUARUN") or "lua"

local specs = {
    "strings_spec.lua",
    "normalizer_spec.lua",
    "state_spec.lua",
    "profile_index_spec.lua",
    "context_spec.lua",
    "slash_spec.lua",
    "slash_handle_spec.lua",
    "async_spec.lua",
    "restorer_spec.lua",
    "macro_resolver_spec.lua",
    "autoload_spec.lua",
    "autoload_index_spec.lua",
    "profile_actions_spec.lua",
    "bootstrap_spec.lua",
    "action_resolver_spec.lua",
    "scanner_spec.lua",
    "spellbook_api_spec.lua",
    "petbar_spec.lua",
    "clickbindings_spec.lua",
}

local failedSpecs = {}
for index = 1, #specs do
    local spec = specs[index]
    local result = { os.execute(string.format("%s %q", interpreter, root .. "/tests/" .. spec)) }
    local code = result[3] or result[1]
    if not (code == 0 or code == true) then
        failedSpecs[#failedSpecs + 1] = spec
    end
end

if #failedSpecs > 0 then
    io.stderr:write(string.format("FAILED %d of %d spec file(s):\n", #failedSpecs, #specs))
    for _, spec in ipairs(failedSpecs) do
        io.stderr:write(string.format("  - %s\n", spec))
    end
    os.exit(1)
end

io.stdout:write(string.format("PASS all %d spec files\n", #specs))
os.exit(0)
