local _, SlotFiller = ...

SlotFiller.Async = {}

-- Cooperative yield point for heavy scan/restore loops (full 180-slot bar scan,
-- macro cache build, pet bar, click bindings). Calling this from inside a
-- coroutine lets a long pass yield back to WoW between batches so it can never
-- trip the client's "script ran too long" watchdog. It is a true no-op when
-- called from the main thread, so every current caller (Save/Load both run
-- synchronously today) is unaffected — this only matters the moment a future
-- caller wraps the work in a coroutine (e.g. a bulk-import feature).
--
-- coroutine.running() returns (thread, true) on the main thread in Lua 5.2+
-- and LuaJIT, but nil on the main thread in plain Lua 5.1. The second return
-- value is what distinguishes "really inside a coroutine" from "main thread"
-- across both runtimes.
function SlotFiller.Async.MaybeYield()
    local co, isMain = coroutine.running()
    if co and not isMain then
        coroutine.yield()
    end
end
