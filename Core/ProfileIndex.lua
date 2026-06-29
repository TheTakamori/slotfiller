local _, SlotFiller = ...

SlotFiller.ProfileIndex = {}

function SlotFiller.ProfileIndex:Build()
    return {
        specName      = SlotFiller.Context.GetSpecName(),
        characterName = SlotFiller.Context.GetPlayerName(),
        realmName     = SlotFiller.Context.GetRealmName(),
        className     = SlotFiller.Context.GetClassName(),
        activeProfile = SlotFiller.State:GetActiveProfileName(),
    }
end
