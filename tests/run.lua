local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/run%.lua$") or "."

local specs = {
    "normalizer_spec.lua",
    "state_spec.lua",
    "profile_index_spec.lua",
    "context_spec.lua",
    "slash_spec.lua",
    "restorer_spec.lua",
    "autoload_spec.lua",
    "profile_actions_spec.lua",
}

local failed = 0
for index = 1, #specs do
    local spec = specs[index]
    local result = { os.execute(string.format("lua %q", root .. "/tests/" .. spec)) }
    local code = result[3] or result[1]
    if not (code == 0 or code == true) then
        failed = failed + 1
    end
end

if failed > 0 then
    io.stderr:write(string.format("FAILED %d spec file(s)\n", failed))
    os.exit(1)
end

io.stdout:write(string.format("PASS all %d spec files\n", #specs))
os.exit(0)
