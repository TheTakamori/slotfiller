local _, SlotFiller = ...

SlotFiller.Constants = {
    VERSION = "1.1.1",
    ADDON_NAME = "SlotFiller",
    ADDON_TITLE = "Slot Filler",
    SAVED_VARIABLES = "SlotFillerDB",
    SLASH_COMMAND = "/sfill",

    DB_VERSION = 3,

    MAX_PROFILE_NAME_LEN = 32,
    AUTOLOAD_DELAY_SEC   = 0.5,

    SLOT_MIN = 1,
    -- Full action-slot range:
    --   1-72   : main action bars 1-6 (pages 1-2 + bars 2-5)
    --   73-120 : class bonus bars (Rogue stealth, Druid forms, Warrior stances, etc.)
    --   121-132: Skyriding bar / possession bar
    --   133-144: reserved/unknown — included so future usage is captured automatically
    --   145-180: action bars 6-8 (MultiBar5-7, added in Dragonflight/10.0)
    SLOT_MAX = 180,

    ACTION_TYPE = {
        SPELL = "spell",
        ITEM = "item",
        MACRO = "macro",
        FLYOUT = "flyout",
        COMPANION = "companion",
        EQUIPMENTSET = "equipmentset",
        SUMMONMOUNT = "summonmount",
        -- Storage-only passthrough for native WoW types not explicitly handled above
        UNKNOWN = "unknown",
    },

    ACTION_SUBTYPE = {
        ASSISTEDCOMBAT = "assistedcombat",
    },

    COMMAND = {
        SAVE = "save",
        LOAD = "load",
        APPLY = "apply",
        USE = "use",
        LIST = "list",
        DELETE = "delete",
        RENAME = "rename",
        DUPLICATE = "duplicate",
        HELP = "help",
        OPEN = "open",
        MINIMAP = "minimap",
        SCAN = "scan",
        SBA = "sba",
        ERRORS = "errors",
    },

    MINIMAP = {
        BUTTON_SIZE = 31,
        BACKGROUND_SIZE = 24,
        ICON_SIZE = 18,
        OVERLAY_SIZE = 50,
        ICON_OFFSET_X = 7,
        ICON_OFFSET_Y = -6,
        RADIUS_OFFSET = 5,
        FRAME_LEVEL_OFFSET = 8,
        TEX_COORD_LEFT = 0.08,
        TEX_COORD_RIGHT = 0.92,
        TEX_COORD_TOP = 0.08,
        TEX_COORD_BOTTOM = 0.92,
    },

    TEXTURE = {
        MINIMAP_BACKGROUND = "Interface\\Minimap\\UI-Minimap-Background",
        MINIMAP_BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder",
        MINIMAP_HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
        MINIMAP_ICON = "Interface\\AddOns\\SlotFiller\\Media\\Icons\\slotfiller-64.png",
    },

    CHAT_PREFIX = "|cff33ff99Slot Filler|r: ",

    FRAME = {
        WIDTH = 420,
        HEIGHT = 420,
        -- Bottom-row and button positions (y from frame bottom)
        FOOTER_BOTTOM      = 16,
        SAVE_BOTTOM        = 16,
        SAVE_BOX_WIDTH     = 190,
        SAVE_BUTTON_WIDTH  = 72,
        CLOSE_BUTTON_WIDTH = 72,
        ACTION_ROW2_BOTTOM = 48,
        ACTION_ROW1_BOTTOM = 78,
        -- Dropdown section bottoms (y from frame bottom to widget's bottom edge).
        -- Each section is 48 px tall: 22 px widget + 12 px label + 14 px gap.
        -- PROFILE_BOTTOM has an extra gap to visually separate it from the
        -- auto-load config section below it.
        SPECS_BOTTOM         = 110,
        CLASSES_BOTTOM       = 158,
        CHARS_BOTTOM         = 206,
        AUTOLOAD_CHECK_BOTTOM = 254,  -- "Allow Profile Auto Load" checkbox
        PROFILE_BOTTOM       = 292,
        DD_HEIGHT            = 22,
    },

    COLORS = {
        BODY        = { 0.04, 0.04, 0.04, 0.92 },
        BORDER      = { 0.22, 0.22, 0.22, 1 },
        TEXT        = { 0.92, 0.92, 0.92, 1 },
        MUTED       = { 0.68, 0.68, 0.68, 1 },
        PLACEHOLDER = { 0.45, 0.45, 0.45, 1 },
        WARNING     = { 1,    0.6,  0,    1 },
    },
}

SlotFiller.Constants.RESERVED_COMMANDS = {
    [SlotFiller.Constants.COMMAND.SAVE] = true,
    [SlotFiller.Constants.COMMAND.LOAD] = true,
    [SlotFiller.Constants.COMMAND.APPLY] = true,
    [SlotFiller.Constants.COMMAND.USE] = true,
    [SlotFiller.Constants.COMMAND.LIST] = true,
    [SlotFiller.Constants.COMMAND.DELETE] = true,
    [SlotFiller.Constants.COMMAND.RENAME] = true,
    [SlotFiller.Constants.COMMAND.DUPLICATE] = true,
    [SlotFiller.Constants.COMMAND.HELP] = true,
    [SlotFiller.Constants.COMMAND.OPEN] = true,
    [SlotFiller.Constants.COMMAND.MINIMAP] = true,
    [SlotFiller.Constants.COMMAND.SCAN] = true,
}
