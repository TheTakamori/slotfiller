local _, SlotFiller = ...

-- Minimal pub-sub so Core modules (e.g. Bootstrap) can notify interested UI
-- listeners without referencing UI/*.lua directly. Keeps the dependency
-- direction one-way (Core never reaches into UI internals) per the
-- architecture rule, while still letting the profile panel refresh itself
-- after a Core-driven change such as auto-load or a spec change.
SlotFiller.Hooks = {}

local stateChangedListeners = {}

-- fn is called with no arguments whenever Core applies a change a visible UI
-- might need to reflect (a profile was auto-loaded, the active spec changed).
function SlotFiller.Hooks.RegisterStateChanged(fn)
    stateChangedListeners[#stateChangedListeners + 1] = fn
end

function SlotFiller.Hooks.NotifyStateChanged()
    for _, fn in ipairs(stateChangedListeners) do
        fn()
    end
end
