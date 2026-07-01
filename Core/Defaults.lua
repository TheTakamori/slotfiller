local _, SlotFiller = ...

local Constants = SlotFiller.Constants

SlotFiller.Defaults = {}

function SlotFiller.Defaults.Get()
    return {
        version = Constants.DB_VERSION,
        minimap = {
            angle = Constants.MINIMAP.DEFAULT_ANGLE,
            hidden = false,
        },
        profiles = {},
        knownCharacters = {},
    }
end
