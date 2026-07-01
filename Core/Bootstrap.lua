local addonName, SlotFiller = ...

local Constants = SlotFiller.Constants
local Text = SlotFiller.Text
local WoW = SlotFiller.WoWConstants

local events = CreateFrame(WoW.UI.FRAME)
events:RegisterEvent(WoW.EVENT.ADDON_LOADED)
events:RegisterEvent(WoW.EVENT.PLAYER_LOGIN)
events:RegisterEvent(WoW.EVENT.PLAYER_SPECIALIZATION_CHANGED)
events:RegisterEvent(WoW.EVENT.PLAYER_REGEN_ENABLED)

-- Set when a delayed auto-load attempt found combat active and bailed out,
-- so the PLAYER_REGEN_ENABLED handler below knows to retry once combat ends.
-- Without this, a profile could simply never auto-load for the session if
-- combat happened to overlap the post-login delay.
local pendingAutoLoadRetry = false

-- Resolves the best auto-load profile for the current context and loads it.
-- If no profile has "Allow Profile Auto Load" enabled, nothing is loaded.
local function triggerAutoLoad()
    local function apply()
        if SlotFiller.Context.IsCombatLocked() then
            pendingAutoLoadRetry = true
            return
        end
        local specName = SlotFiller.Context.GetSpecName()
        if not specName then return end

        local name  = SlotFiller.Context.GetPlayerName()
        local realm = SlotFiller.Context.GetRealmName()
        local characterKey = (name and realm) and (name .. "-" .. realm) or nil
        local classFile    = SlotFiller.Context.GetClassFile()

        local profileName = SlotFiller.AutoLoad.FindBestProfile(characterKey, classFile, specName)
        if not profileName then return end

        if profileName ~= SlotFiller.State:GetActiveProfileName() then
            SlotFiller.ProfileActions:Load(profileName)
            SlotFiller.Hooks.NotifyStateChanged()
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(Constants.AUTOLOAD_DELAY_SEC, apply)
    else
        apply()
    end
end

events:SetScript(WoW.UI.ON_EVENT, function(_, event, arg1)
    if event == WoW.EVENT.ADDON_LOADED then
        if arg1 ~= addonName then
            return
        end
        SlotFiller.State:GetDB()
        SlotFiller.UI.SlashCommands:Register()
        SlotFiller.Print(Text.LOADED)
        return
    end

    if event == WoW.EVENT.PLAYER_LOGIN then
        SlotFiller.UI.MinimapButton:Ensure()

        -- Track the logged-in character for the character-selection dropdown.
        local name  = SlotFiller.Context.GetPlayerName()
        local realm = SlotFiller.Context.GetRealmName()
        local file  = SlotFiller.Context.GetClassFile()
        local id    = SlotFiller.Context.GetClassID()
        if name and realm and file then
            SlotFiller.State:TrackCharacter(name .. "-" .. realm, file, id)
        end

        triggerAutoLoad()
        return
    end

    if event == WoW.EVENT.PLAYER_SPECIALIZATION_CHANGED then
        SlotFiller.Hooks.NotifyStateChanged()
        triggerAutoLoad()
        return
    end

    if event == WoW.EVENT.PLAYER_REGEN_ENABLED then
        if pendingAutoLoadRetry then
            pendingAutoLoadRetry = false
            triggerAutoLoad()
        end
    end
end)
