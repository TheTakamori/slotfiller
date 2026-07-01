local _, SlotFiller = ...

SlotFiller.Constants = {
    VERSION = "1.3.1",
    ADDON_NAME = "SlotFiller",
    ADDON_TITLE = "Slot Filler",
    SAVED_VARIABLES = "SlotFillerDB",
    SLASH_COMMAND = "/sfill",

    DB_VERSION = 3,

    MAX_PROFILE_NAME_LEN = 32,
    AUTOLOAD_DELAY_SEC   = 0.5,

    -- Fallback values for Blizzard globals that may be unavailable on a given
    -- client/build (e.g. the plain-Lua test host). Named here instead of
    -- inlined as magic numbers at each call site.
    MAX_ACCOUNT_MACROS_FALLBACK    = 120,
    MAX_CHARACTER_MACROS_FALLBACK  = 18,
    MAX_SKILLLINE_TABS_FALLBACK    = 8,
    DEFAULT_MACRO_ICON             = "INV_MISC_QUESTIONMARK",
    -- Enum.ClickBindingType.Macro's documented numeric value, used when the
    -- Enum table itself is unavailable.
    CLICK_BINDING_TYPE_MACRO_FALLBACK = 2,

    -- How many iterations a heavy scan/restore loop processes between
    -- cooperative yield points (see Core/Async.lua). One shared interval
    -- keeps every loop's pacing consistent and avoids per-caller tuning.
    ASYNC_YIELD_BATCH = 30,

    -- Macro body escape tokens used to make a macro safely storable as a
    -- single SavedVariables string (see Normalizer.CompressMacroText).
    MACRO_ESCAPE = {
        NEWLINE = "/n",
        PIPE    = "/124",
    },

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
        OUTFIT = "outfit",
        SUMMONMOUNT = "summonmount",
        SUMMONPET = "summonpet",
        -- Storage-only passthrough for native WoW types not explicitly handled above
        UNKNOWN = "unknown",
    },

    -- Sentinel mount-action ID returned by GetActionInfo for "Summon Random Favourite Mount".
    RANDOM_FAVORITE_MOUNT_ID = 268435455,

    ACTION_SUBTYPE = {
        ASSISTEDCOMBAT = "assistedcombat",
    },

    PET_SLOT_MIN = 1,
    -- Mirrors Blizzard's NUM_PET_ACTION_SLOTS (10). Hardcoded rather than read
    -- from the global so Constants.lua stays free of WoW-API load-order
    -- assumptions; PetActionAPI re-checks the live global where it matters.
    PET_SLOT_MAX = 10,

    PET_SLOT_TYPE = {
        -- Pet command tokens (Attack, Follow, Stay, etc.). Recorded so restore
        -- can avoid disturbing them, but never relocated — see PetActionAPI.lua.
        TOKEN = "token",
        SPELL = "spell",
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
        DEFAULT_ANGLE = 220,
        -- Inset subtracted from the diagonal placement radius so the button
        -- doesn't visually clip past a square/cornered minimap shape.
        DIAGONAL_INSET = 10,
        -- Squared-pixel drag distance (in screen space) beyond which a
        -- minimap-button click is treated as a drag rather than a click.
        DRAG_THRESHOLD_SQ = 4,
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
        -- Action-row button widths.
        BUTTON_WIDTH_SM = 72,
        BUTTON_WIDTH_MD = 88,
    },

    COPY_FRAME = {
        WIDTH  = 520,
        HEIGHT = 380,
        HINT_OFFSET_X    = 14,
        HINT_OFFSET_Y    = -30,
        SCROLL_INSET_TOP    = -50,
        SCROLL_INSET_LEFT   = 8,
        SCROLL_INSET_RIGHT  = -28,
        SCROLL_INSET_BOTTOM = 8,
    },

    COLORS = {
        BODY            = { 0.04, 0.04, 0.04, 0.92 },
        BORDER          = { 0.22, 0.22, 0.22, 1 },
        TEXT            = { 0.92, 0.92, 0.92, 1 },
        MUTED           = { 0.68, 0.68, 0.68, 1 },
        PLACEHOLDER     = { 0.45, 0.45, 0.45, 1 },
        TOOLTIP_TITLE   = { 1,    1,    1,    1 },
        TOOLTIP_BODY    = { 0.9,  0.9,  0.9,  1 },
    },
}

SlotFiller.Constants.RESERVED_COMMANDS = {
    [SlotFiller.Constants.COMMAND.SAVE]      = true,
    [SlotFiller.Constants.COMMAND.LOAD]      = true,
    [SlotFiller.Constants.COMMAND.APPLY]     = true,
    [SlotFiller.Constants.COMMAND.USE]       = true,
    [SlotFiller.Constants.COMMAND.LIST]      = true,
    [SlotFiller.Constants.COMMAND.DELETE]    = true,
    [SlotFiller.Constants.COMMAND.RENAME]    = true,
    [SlotFiller.Constants.COMMAND.DUPLICATE] = true,
    [SlotFiller.Constants.COMMAND.HELP]      = true,
    [SlotFiller.Constants.COMMAND.OPEN]      = true,
    [SlotFiller.Constants.COMMAND.MINIMAP]   = true,
    [SlotFiller.Constants.COMMAND.SCAN]      = true,
    -- Dev-only verbs must also be reserved so a profile named "sba" or "errors"
    -- is never accidentally shorthand-loaded instead of running the command.
    [SlotFiller.Constants.COMMAND.SBA]       = true,
    [SlotFiller.Constants.COMMAND.ERRORS]    = true,
}
