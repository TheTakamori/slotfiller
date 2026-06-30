local _, SlotFiller = ...

-- Shared string helpers used across parsing, normalization, and UI input
-- handling. Centralised here per the addon's reuse rule: any helper needed
-- in 3+ places belongs in a focused shared module, not copy-pasted locals.
SlotFiller.Strings = {}

-- Strips leading/trailing whitespace. Non-string input (including nil)
-- safely returns "" rather than raising, since callers often trim raw
-- widget text or optional message fragments.
function SlotFiller.Strings.Trim(text)
    if type(text) ~= "string" then
        return ""
    end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end
