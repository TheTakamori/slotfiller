---@diagnostic disable: undefined-global
local scriptPath = (arg and arg[0]) or ""
local root = scriptPath:match("(.+)/tests/[^/]+%.lua$") or "."
local support = assert(loadfile(root .. "/tests/support.lua"))()

local runner = support.new_runner()

support.load_addon(root)

local Async = SlotFiller.Async

runner:test("MaybeYield is a no-op on the main thread", function()
    -- The runner wraps every test body in pcall, so reaching the assertion
    -- below already proves MaybeYield did not raise "attempt to yield from
    -- outside a coroutine". Also assert its documented no-op return contract
    -- (returns nothing) rather than a tautological "true == true" check.
    local result = Async.MaybeYield()
    support.assert.isNil(result, "no-op call returns nothing")
end)

runner:test("MaybeYield actually yields when called inside a coroutine", function()
    local resumeCount = 0
    local co = coroutine.create(function()
        Async.MaybeYield()
        resumeCount = resumeCount + 1
        Async.MaybeYield()
        resumeCount = resumeCount + 1
    end)

    support.assert.equal(coroutine.status(co), "suspended", "not started yet")
    coroutine.resume(co)
    support.assert.equal(resumeCount, 0, "paused before first increment")
    support.assert.equal(coroutine.status(co), "suspended", "yielded, not dead")

    coroutine.resume(co)
    support.assert.equal(resumeCount, 1, "paused before second increment")

    coroutine.resume(co)
    support.assert.equal(resumeCount, 2, "ran to completion")
    support.assert.equal(coroutine.status(co), "dead", "coroutine finished")
end)

os.exit(runner:run())
