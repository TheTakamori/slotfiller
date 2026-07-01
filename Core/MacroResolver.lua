local _, SlotFiller = ...

local Constants = SlotFiller.Constants
local ActionAPI = SlotFiller.ActionAPI
local Normalizer = SlotFiller.Normalizer

-- Macro find-or-create logic shared by ActionResolver (action-bar macro
-- slots), Restorer (macro cache used across a full profile apply), and
-- ClickBindings (macro-type click bindings) — all three need identical
-- find-or-create-on-this-character semantics. Extracted to its own module so
-- none of those three need a runtime forward reference to one another.
SlotFiller.MacroResolver = {}

function SlotFiller.MacroResolver:BuildMacroCache()
    local bodyCache = {}
    local nameCache = {}
    local idCache = {}
    local blacklist = {}
    local maxMacros = (MAX_ACCOUNT_MACROS or Constants.MAX_ACCOUNT_MACROS_FALLBACK)
        + (MAX_CHARACTER_MACROS or 0)

    if not GetMacroInfo then
        return bodyCache, nameCache, idCache
    end

    for macroID = 1, maxMacros do
        local name, _, body = GetMacroInfo(macroID)
        if name and body then
            idCache[macroID] = macroID
            local compressedBody = Normalizer.CompressMacroText(body)
            bodyCache[compressedBody] = macroID
            if nameCache[name] then
                blacklist[name] = true
                nameCache[name] = nil  -- ambiguous: drop the earlier entry too
            elseif not blacklist[name] then
                nameCache[name] = macroID
            end
        end
        if macroID % Constants.ASYNC_YIELD_BATCH == 0 then
            SlotFiller.Async.MaybeYield()
        end
    end

    return bodyCache, nameCache, idCache
end

function SlotFiller.MacroResolver:FindMacroID(slot, bodyCache, nameCache, idCache)
    if slot.macroID and idCache[slot.macroID] and GetMacroInfo then
        local name, _, body = GetMacroInfo(slot.macroID)
        if body then
            local compressedBody = Normalizer.CompressMacroText(body)
            if (not slot.body or slot.body == compressedBody) and (not slot.name or slot.name == name) then
                return slot.macroID
            end
        end
    end
    if slot.body and bodyCache[slot.body] then
        return bodyCache[slot.body]
    end
    if slot.name and nameCache[slot.name] then
        return nameCache[slot.name]
    end
    return nil
end

-- Resolves a macro reference to a macroID on this character, creating it if
-- it's a character-specific macro that isn't found.
--
-- Returns (macroID, nil) on success, or (nil, reason) where reason is "limit"
-- (18 character-macro cap reached), "create_failed", or "not_found" (global
-- macro missing, or no name available to recreate it from).
function SlotFiller.MacroResolver:ResolveOrCreateMacro(name, body, icon, perCharacter, caches)
    local macroID = self:FindMacroID({ name = name, body = body }, caches.macroBody, caches.macroName, caches.macroID)
    if macroID then
        return macroID, nil
    end

    if not (perCharacter and name) then
        return nil, "not_found"
    end

    local uncompressedBody = body and Normalizer.UncompressMacroText(body) or ""
    local newID, createErr = ActionAPI.CreateCharacterMacro(name, icon, uncompressedBody)
    if not newID then
        return nil, (createErr == "limit") and "limit" or "create_failed"
    end

    -- Keep the shared caches in sync so a later lookup (another action-bar
    -- slot or click binding referencing the same macro) finds it instead of
    -- attempting a duplicate creation.
    caches.macroID[newID] = newID
    if body then caches.macroBody[body] = newID end
    caches.macroName[name] = newID
    return newID, nil
end
