local _, SlotFiller = ...

local Constants = SlotFiller.Constants
local API = SlotFiller.ClickBindingAPI
local Text = SlotFiller.Text
local MacroResolver = SlotFiller.MacroResolver

-- Scan and restore logic for Click Bindings. Capture/restore for macro-type
-- bindings reuses SlotFiller.MacroResolver:ResolveOrCreateMacro — the same
-- find-or-create-on-this-character logic action-bar macro slots already use.
SlotFiller.ClickBindings = {}

-- Returns the captured binding list, or nil when Click Bindings aren't
-- supported on this client (so the profile never claims "zero bindings" on a
-- client where the feature doesn't exist).
function SlotFiller.ClickBindings:Scan()
    if not API.IsSupported() then
        return nil
    end

    local entries = {}
    local macroType = API.GetMacroTypeValue()
    for _, info in ipairs(API.GetProfileInfo()) do
        local raw = {
            bindingType = info.type,
            button      = info.button,
            modifiers   = info.modifiers,
        }
        if info.type == macroType then
            -- Always flag as a macro binding once the type matches, even if the
            -- lookup below fails — otherwise FromRawClickBinding would fall
            -- through to the non-macro path with a nil actionID instead of
            -- dropping the entry.
            raw.isMacro = true
            if GetMacroInfo then
                local name, icon, body = GetMacroInfo(info.actionID)
                if name then
                    raw.macroName = name
                    raw.macroIcon = icon
                    raw.macroBody = SlotFiller.Normalizer.CompressMacroText(body)
                end
            end
        else
            raw.actionID = info.actionID
        end

        local entry = SlotFiller.Normalizer.FromRawClickBinding(raw)
        if entry then
            entries[#entries + 1] = entry
        end
    end
    return entries
end

-- Key used to match a click binding to the physical button+modifier it
-- occupies, for merging saved entries over the character's live profile.
local function bindingKey(info)
    return tostring(info.button) .. "|" .. tostring(info.modifiers)
end

-- Restores entries via C_ClickBindings.SetProfileByInfo. caches is the shared
-- macro-lookup table built once per ApplyProfile (see Restorer.ApplyProfile).
-- Returns a list of human-readable error strings for any macro binding that
-- couldn't be resolved or recreated; non-macro bindings (spell/item/menu) never
-- fail since they reference stable, account-independent IDs.
--
-- An empty captured list is treated as "this profile never customised click
-- bindings" rather than "clear them all" — restoring is additive, not
-- destructive, for a feature this new. SetProfileByInfo replaces the entire
-- profile in one call, so a non-empty captured list is merged over the
-- character's current live bindings (keyed by button+modifier) rather than
-- passed alone, so any live binding the saved profile never touched survives.
function SlotFiller.ClickBindings:Apply(entries, caches)
    local errors = {}
    if not entries or #entries == 0 then
        return errors
    end
    if not API.IsSupported() then
        return errors
    end

    local resolved = {}
    local processed = 0
    for _, entry in ipairs(entries) do
        if entry.isMacro then
            -- perCharacter is forced true: ClickBindings doesn't track whether
            -- the original macro was account-wide or character-specific, so it
            -- falls back to the same character-macro creation path action-bar
            -- macro slots use when no existing macro matches.
            local macroID, errReason = MacroResolver:ResolveOrCreateMacro(
                entry.macroName, entry.macroBody, entry.macroIcon, true, caches)
            if macroID then
                resolved[#resolved + 1] = {
                    type      = entry.bindingType,
                    button    = entry.button,
                    modifiers = entry.modifiers,
                    actionID  = macroID,
                }
            elseif errReason == "limit" then
                errors[#errors + 1] = string.format(Text.RESTORE_CLICKBINDING_MACRO_LIMIT, entry.macroName)
            else
                errors[#errors + 1] = string.format(Text.RESTORE_CLICKBINDING_MACRO_FAILED, entry.macroName)
            end
        else
            resolved[#resolved + 1] = {
                type      = entry.bindingType,
                button    = entry.button,
                modifiers = entry.modifiers,
                actionID  = entry.actionID,
            }
        end

        processed = processed + 1
        if processed % Constants.ASYNC_YIELD_BATCH == 0 then
            SlotFiller.Async.MaybeYield()
        end
    end

    -- Merge resolved (saved-profile) entries over the live profile so any
    -- binding the saved profile didn't capture is left exactly as-is.
    local merged = {}
    local mergedIndex = {}
    for _, info in ipairs(API.GetProfileInfo()) do
        local key = bindingKey(info)
        mergedIndex[key] = #merged + 1
        merged[#merged + 1] = info
    end
    for _, info in ipairs(resolved) do
        local key = bindingKey(info)
        local existingIndex = mergedIndex[key]
        if existingIndex then
            merged[existingIndex] = info
        else
            mergedIndex[key] = #merged + 1
            merged[#merged + 1] = info
        end
    end

    API.SetProfileInfo(merged)
    return errors
end
