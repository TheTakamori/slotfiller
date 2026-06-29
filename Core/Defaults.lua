local _, SlotFiller = ...

local Constants = SlotFiller.Constants

SlotFiller.Defaults = {}

function SlotFiller.Defaults.Get()
    return {
        version = Constants.DB_VERSION,
        minimap = {
            angle = 220,
            hidden = false,
        },
        profiles = {},
        activeProfile = nil,
        knownCharacters = {},
    }
end
