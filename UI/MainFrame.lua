local _, SlotFiller = ...

local Constants = SlotFiller.Constants
local Text = SlotFiller.Text
local Colors = Constants.COLORS
local Frame = Constants.FRAME
local Strings = SlotFiller.Strings
local Widgets = SlotFiller.UI and SlotFiller.UI.Widgets
local AutoLoadIndex = SlotFiller.AutoLoadIndex

SlotFiller.UI = SlotFiller.UI or {}
SlotFiller.UI.MainFrame = {}

local MainFrame = SlotFiller.UI.MainFrame

-- Refresh the panel whenever Core applies a change that could affect what it
-- shows (auto-load fired, spec changed) — Core notifies via SlotFiller.Hooks
-- instead of reaching into UI.MainFrame directly, so this file is the only
-- place that knows the panel exists.
SlotFiller.Hooks.RegisterStateChanged(function()
    if MainFrame.frame and MainFrame.frame:IsShown() then
        MainFrame:Refresh()
    end
end)

-- ── Module-level dropdown-selection state ──────────────────────────────────
-- These are the currently displayed auto-load filters for `selectedProfile`.
local selectedProfile    = nil
local selectedAutoLoad   = false  -- mirrors the "Allow Profile Auto Load" checkbox
local selectedChars      = {}   -- set: "Name-Realm" → true
local selectedClasses    = {}   -- set: "PALADIN"    → true
local selectedSpecs      = {}   -- set: "Retribution" → true

-- ── Helpers ────────────────────────────────────────────────────────────────

-- Returns a comma-separated summary of the keys in a selection set, or
-- `Text.UI_AUTOLOAD_ANY` when nothing is selected.
local function selectionSummary(selectionSet)
    local items = {}
    for k in pairs(selectionSet) do items[#items + 1] = k end
    if #items == 0 then return Text.UI_AUTOLOAD_ANY end
    table.sort(items)
    return table.concat(items, ", ")
end

-- ── Dropdown setup ─────────────────────────────────────────────────────────

local function saveCurrentAutoLoad()
    if not selectedProfile then return end
    local chars, classes, specs = {}, {}, {}
    for k in pairs(selectedChars)   do chars[#chars+1]     = k end
    for k in pairs(selectedClasses) do classes[#classes+1] = k end
    for k in pairs(selectedSpecs)   do specs[#specs+1]     = k end
    SlotFiller.State:SetProfileAutoLoad(selectedProfile, {
        enabled    = selectedAutoLoad,
        characters = chars,
        classes    = classes,
        specs      = specs,
    })
end

local function loadAutoLoadConfig(profileName)
    for k in pairs(selectedChars)   do selectedChars[k]   = nil end
    for k in pairs(selectedClasses) do selectedClasses[k] = nil end
    for k in pairs(selectedSpecs)   do selectedSpecs[k]   = nil end
    selectedAutoLoad = false
    if not profileName then return end
    local config = SlotFiller.State:GetProfileAutoLoad(profileName)
    selectedAutoLoad = config.enabled == true
    for _, v in ipairs(config.characters or {}) do selectedChars[v]   = true end
    for _, v in ipairs(config.classes    or {}) do selectedClasses[v] = true end
    for _, v in ipairs(config.specs      or {}) do selectedSpecs[v]   = true end
end

-- Called when a profile popup (rename/duplicate/overwrite/delete) completes
-- successfully. resultName is the profile's new selected name, or nil when
-- the profile was deleted.
local function onProfilePopupSuccess(resultName)
    selectedProfile = resultName
    MainFrame:Refresh()
end

-- SetupDropdownMenus must be called after all dropdown frames exist.
function MainFrame:SetupDropdownMenus()
    local frame = self.frame

    -- Forward declarations so closures can reference functions defined later.
    local rebuildAutoLoadCheck, rebuildProfileDropdown
    local rebuildCharsText, rebuildClassesText, rebuildSpecsText

    -- ── Menu generators (registered once; close over live state tables) ──────
    -- The generators read `selectedChars`, `selectedClasses`, `selectedSpecs`
    -- at open-time, so the menu is always up-to-date without re-registering.

    frame.specDropdown:SetupMenu(function(_, root)
        local specs = AutoLoadIndex.GetEligibleSpecs(selectedClasses)
        if #specs == 0 then
            root:CreateTitle(Text.UI_AUTOLOAD_ANY)
            return
        end
        for _, s in ipairs(specs) do
            local key = s.key
            root:CreateCheckbox(
                s.label,
                function() return selectedSpecs[key] == true end,
                function()
                    if selectedSpecs[key] then selectedSpecs[key] = nil
                    else selectedSpecs[key] = true end
                    rebuildSpecsText()
                    saveCurrentAutoLoad()
                end
            )
        end
    end)

    frame.classDropdown:SetupMenu(function(_, root)
        local classes = AutoLoadIndex.GetEligibleClasses(selectedChars)
        if #classes == 0 then
            root:CreateTitle(Text.UI_AUTOLOAD_ANY)
            return
        end
        for _, ci in ipairs(classes) do
            local file = ci.file
            root:CreateCheckbox(
                ci.name,
                function() return selectedClasses[file] == true end,
                function()
                    if selectedClasses[file] then selectedClasses[file] = nil
                    else selectedClasses[file] = true end
                    AutoLoadIndex.PruneInvalidSpecs(selectedClasses, selectedSpecs)
                    rebuildClassesText()
                    rebuildSpecsText()
                    saveCurrentAutoLoad()
                end
            )
        end
    end)

    frame.charDropdown:SetupMenu(function(_, root)
        local chars = SlotFiller.State:GetKnownCharacters()
        if #chars == 0 then
            root:CreateTitle(Text.UI_NO_CHARACTERS)
            return
        end
        for _, info in ipairs(chars) do
            local key = info.key
            root:CreateCheckbox(
                key,
                function() return selectedChars[key] == true end,
                function()
                    if selectedChars[key] then selectedChars[key] = nil
                    else selectedChars[key] = true end
                    AutoLoadIndex.PruneInvalidClasses(selectedChars, selectedClasses)
                    AutoLoadIndex.PruneInvalidSpecs(selectedClasses, selectedSpecs)
                    rebuildCharsText()
                    rebuildClassesText()
                    rebuildSpecsText()
                    saveCurrentAutoLoad()
                end
            )
        end
    end)

    -- ── Text / state updaters ────────────────────────────────────────────────

    rebuildSpecsText = function()
        local hasClasses = next(selectedClasses) ~= nil
        frame.specDropdown:SetEnabled(hasClasses)
        frame.specsLabel:SetAlpha(hasClasses and 1 or 0.5)
        frame.specDropdown:SetText(selectionSummary(selectedSpecs))
    end

    rebuildClassesText = function()
        if next(selectedClasses) == nil then
            frame.classDropdown:SetText(Text.UI_AUTOLOAD_ANY)
            return
        end
        local allClasses = SlotFiller.Context.GetAllClasses()
        local names = {}
        for _, ci in ipairs(allClasses) do
            if selectedClasses[ci.file] then
                names[#names + 1] = ci.name
            end
        end
        frame.classDropdown:SetText(#names > 0 and table.concat(names, ", ") or Text.UI_AUTOLOAD_ANY)
    end

    rebuildCharsText = function()
        frame.charDropdown:SetText(selectionSummary(selectedChars))
    end

    rebuildAutoLoadCheck = function()
        frame.autoLoadCheck:SetChecked(selectedAutoLoad)
        local isEnabled = selectedProfile ~= nil
        frame.autoLoadCheck:SetEnabled(isEnabled)
        frame.autoLoadCheckLabel:SetAlpha(isEnabled and 1 or 0.4)
    end

    -- ── Profile dropdown ─────────────────────────────────────────────────────
    -- SetupMenu IS re-called here because the profile list changes when
    -- profiles are saved / deleted / renamed.
    -- WowStyle1DropdownTemplate uses DropdownSelectionTextMixin. We use
    -- SetDefaultText for both the placeholder and the active selection because
    -- our items are plain CreateButton entries (no radio selectionFunc needed).
    -- Calling SetSelectionText(text) would store the string as selectionFunc
    -- and crash UpdateToMenuSelections when it tries to call it.

    local function buildProfileMenu(_, root)
        local names = SlotFiller.State:ListProfileNames()
        if #names == 0 then
            root:CreateTitle(Text.UI_PROFILE_NONE)
            return
        end
        for _, name in ipairs(names) do
            local n = name
            root:CreateButton(n, function()
                selectedProfile = n
                loadAutoLoadConfig(n)
                -- SetDefaultText updates the button label (selectionFunc stays
                -- nil so UpdateToMenuSelections never tries to call it).
                frame.profileDropdown:SetDefaultText(n)
                rebuildAutoLoadCheck()
                rebuildCharsText()
                rebuildClassesText()
                rebuildSpecsText()
            end)
        end
    end

    rebuildProfileDropdown = function()
        frame.profileDropdown:SetupMenu(buildProfileMenu)
        if selectedProfile then
            frame.profileDropdown:SetDefaultText(selectedProfile)
        else
            frame.profileDropdown:SetDefaultText(Text.UI_PROFILE_NONE)
        end
    end

    -- Store public rebuilders so Refresh() can call them.
    self.rebuildProfileDropdown = rebuildProfileDropdown
    self.rebuildAutoLoadCheck   = rebuildAutoLoadCheck
    self.rebuildCharsText       = rebuildCharsText
    self.rebuildClassesText     = rebuildClassesText
    self.rebuildSpecsText       = rebuildSpecsText

    rebuildProfileDropdown()
    rebuildAutoLoadCheck()
    rebuildCharsText()
    rebuildClassesText()
    rebuildSpecsText()
end

-- ── Save-box helpers ────────────────────────────────────────────────────────

function MainFrame:UpdateSavePlaceholder()
    local frame = self.frame
    if not frame or not frame.saveBox or not frame.savePlaceholder then return end
    local hasText  = Strings.Trim(frame.saveBox:GetText()) ~= ""
    local hasFocus = frame.saveBox:HasFocus()
    frame.savePlaceholder:SetShown(not hasText and not hasFocus)
end

function MainFrame:EnsureSaveBoxOverlay()
    local frame = self.frame
    if not frame or not frame.saveBox or frame.savePlaceholder then return end
    local placeholder = frame.saveBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    placeholder:SetPoint("LEFT", frame.saveBox, "LEFT", 10, 0)
    placeholder:SetJustifyH("LEFT")
    placeholder:SetText(Text.UI_SAVE_PLACEHOLDER)
    placeholder:SetTextColor(Colors.PLACEHOLDER[1], Colors.PLACEHOLDER[2], Colors.PLACEHOLDER[3])
    frame.savePlaceholder = placeholder
end

function MainFrame:GetSaveProfileName()
    local saveBox = self.frame and self.frame.saveBox
    if not saveBox then return "" end
    return Strings.Trim(saveBox:GetText())
end

function MainFrame:SetupSaveBox(saveBox)
    saveBox:SetText("")
    saveBox:SetScript("OnEditFocusGained", function() MainFrame:UpdateSavePlaceholder() end)
    saveBox:SetScript("OnEditFocusLost",   function() MainFrame:UpdateSavePlaceholder() end)
    saveBox:SetScript("OnTextChanged",     function() MainFrame:UpdateSavePlaceholder() end)
end

function MainFrame:SaveFromInput()
    local profileName = self:GetSaveProfileName()
    if profileName == "" then
        SlotFiller.Print(Text.PROFILE_NAME_REQUIRED)
        return
    end
    if not SlotFiller.Context.RequireReady() then return end
    if SlotFiller.ProfileActions:Save(profileName) then
        selectedProfile = profileName
        self.frame.saveBox:SetText("")
        self:UpdateSavePlaceholder()
        self:Refresh()
    end
end

-- ── Frame construction ──────────────────────────────────────────────────────

function MainFrame:Ensure()
    if self.frame then
        self:EnsureSaveBoxOverlay()
        self:UpdateSavePlaceholder()
        return self.frame
    end

    local frame = CreateFrame("Frame", "SlotFillerMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(Frame.WIDTH, Frame.HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    frame:Hide()
    Widgets.ApplyBackdrop(frame)

    -- ── Header ──
    frame.title = Widgets.CreateLabel(frame, Text.UI_TITLE, "GameFontNormalLarge")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -16)

    frame.specLabel = Widgets.CreateLabel(frame, "")
    frame.specLabel:SetPoint("TOP", frame.title, "BOTTOM", 0, -8)

    frame.activeLabel = Widgets.CreateLabel(frame, "")
    frame.activeLabel:SetPoint("TOP", frame.specLabel, "BOTTOM", 0, -4)
    frame.activeLabel:SetTextColor(Colors.MUTED[1], Colors.MUTED[2], Colors.MUTED[3])

    -- ── Footer ──
    frame.versionLabel = Widgets.CreateLabel(frame, "v" .. Constants.VERSION, "GameFontNormalSmall")
    frame.versionLabel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
    frame.versionLabel:SetTextColor(Colors.MUTED[1], Colors.MUTED[2], Colors.MUTED[3])

    -- SBA Warning hover — aligned to the same baseline as versionLabel.
    frame.sbaHover = CreateFrame("Frame", nil, frame)
    frame.sbaHover:SetSize(80, 16)
    frame.sbaHover:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 8)
    frame.sbaHover:EnableMouse(true)
    frame.sbaWarningLabel = frame.sbaHover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.sbaWarningLabel:SetPoint("BOTTOMLEFT", frame.sbaHover, "BOTTOMLEFT", 0, 0)
    frame.sbaWarningLabel:SetText(Text.UI_SBA_WARNING)
    frame.sbaWarningLabel:SetTextColor(Colors.WARNING[1], Colors.WARNING[2], Colors.WARNING[3], Colors.WARNING[4])
    Widgets.AttachTooltip(frame.sbaHover, Text.UI_SBA_WARNING, Text.UI_SBA_HINT, Colors.WARNING)

    -- ── Profile dropdown ──
    frame.profileLabel = Widgets.CreateLabel(frame, Text.UI_PROFILE_LABEL, "GameFontNormalSmall")
    frame.profileLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, Frame.PROFILE_BOTTOM + Frame.DD_HEIGHT + 4)

    frame.profileDropdown = CreateFrame("DropdownButton", "SlotFillerProfileDropdown", frame, "WowStyle1DropdownTemplate")
    frame.profileDropdown:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  20,  Frame.PROFILE_BOTTOM)
    frame.profileDropdown:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, Frame.PROFILE_BOTTOM)
    frame.profileDropdown:SetDefaultText(Text.UI_PROFILE_NONE)

    -- ── Allow Profile Auto Load checkbox ──
    frame.autoLoadCheck = CreateFrame("CheckButton", "SlotFillerAutoLoadCheck", frame, "UICheckButtonTemplate")
    frame.autoLoadCheck:SetSize(20, 20)
    frame.autoLoadCheck:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, Frame.AUTOLOAD_CHECK_BOTTOM)
    frame.autoLoadCheck:SetScript("OnClick", function(self)
        selectedAutoLoad = self:GetChecked() and true or false
        saveCurrentAutoLoad()
    end)

    frame.autoLoadCheckLabel = frame.autoLoadCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.autoLoadCheckLabel:SetPoint("LEFT", frame.autoLoadCheck, "RIGHT", 2, 0)
    frame.autoLoadCheckLabel:SetText(Text.UI_AUTOLOAD_ENABLED)

    -- Hover frame covers the checkbox icon + label so the tooltip fires anywhere
    -- along the "Allow Profile Auto Load" row, not just over the 20×20 widget.
    frame.autoLoadHover = CreateFrame("Frame", nil, frame)
    frame.autoLoadHover:SetPoint("LEFT",  frame.autoLoadCheck,      "LEFT",  0, 0)
    frame.autoLoadHover:SetPoint("RIGHT", frame.autoLoadCheckLabel, "RIGHT", 4, 0)
    frame.autoLoadHover:SetHeight(20)
    frame.autoLoadHover:EnableMouse(true)
    Widgets.AttachTooltip(frame.autoLoadHover, Text.UI_AUTOLOAD_TITLE, Text.UI_AUTOLOAD_HINT)

    -- ── Characters dropdown ──
    frame.charsLabel = Widgets.CreateLabel(frame, Text.UI_CHARACTERS_LABEL, "GameFontNormalSmall")
    frame.charsLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, Frame.CHARS_BOTTOM + Frame.DD_HEIGHT + 4)

    frame.charDropdown = CreateFrame("DropdownButton", "SlotFillerCharDropdown", frame, "WowStyle1FilterDropdownTemplate")
    frame.charDropdown:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  20,  Frame.CHARS_BOTTOM)
    frame.charDropdown:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, Frame.CHARS_BOTTOM)
    frame.charDropdown:SetText(Text.UI_AUTOLOAD_ANY)

    -- ── Classes dropdown ──
    frame.classesLabel = Widgets.CreateLabel(frame, Text.UI_CLASSES_LABEL, "GameFontNormalSmall")
    frame.classesLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, Frame.CLASSES_BOTTOM + Frame.DD_HEIGHT + 4)

    frame.classDropdown = CreateFrame("DropdownButton", "SlotFillerClassDropdown", frame, "WowStyle1FilterDropdownTemplate")
    frame.classDropdown:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  20,  Frame.CLASSES_BOTTOM)
    frame.classDropdown:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, Frame.CLASSES_BOTTOM)
    frame.classDropdown:SetText(Text.UI_AUTOLOAD_ANY)

    -- ── Specs dropdown ──
    frame.specsLabel = Widgets.CreateLabel(frame, Text.UI_SPECS_LABEL, "GameFontNormalSmall")
    frame.specsLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, Frame.SPECS_BOTTOM + Frame.DD_HEIGHT + 4)

    frame.specDropdown = CreateFrame("DropdownButton", "SlotFillerSpecDropdown", frame, "WowStyle1FilterDropdownTemplate")
    frame.specDropdown:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  20,  Frame.SPECS_BOTTOM)
    frame.specDropdown:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, Frame.SPECS_BOTTOM)
    frame.specDropdown:SetText(Text.UI_AUTOLOAD_ANY)

    -- ── Action row 1 — Load / Overwrite / Rename ──
    frame.loadButton = Widgets.CreateButton(frame, Text.UI_LOAD, Frame.BUTTON_WIDTH_SM)
    frame.loadButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, Frame.ACTION_ROW1_BOTTOM)
    frame.loadButton:SetScript("OnClick", function()
        if not selectedProfile or not SlotFiller.Context.RequireReady() then return end
        if SlotFiller.ProfileActions:Load(selectedProfile) then
            MainFrame:Refresh()
        end
    end)

    frame.overwriteButton = Widgets.CreateButton(frame, Text.UI_OVERWRITE, Frame.BUTTON_WIDTH_MD)
    frame.overwriteButton:SetPoint("LEFT", frame.loadButton, "RIGHT", 6, 0)
    frame.overwriteButton:SetScript("OnClick", function()
        -- Flush any pending UI selections to State before the overwrite
        -- operation reads existing.autoLoad from State, so deselections made
        -- in the filter dropdowns are not silently discarded.
        saveCurrentAutoLoad()
        SlotFiller.UI.ProfilePopups.ShowOverwrite(selectedProfile, onProfilePopupSuccess)
    end)

    frame.renameButton = Widgets.CreateButton(frame, Text.UI_RENAME, Frame.BUTTON_WIDTH_SM)
    frame.renameButton:SetPoint("LEFT", frame.overwriteButton, "RIGHT", 6, 0)
    frame.renameButton:SetScript("OnClick", function()
        SlotFiller.UI.ProfilePopups.ShowRename(selectedProfile, onProfilePopupSuccess)
    end)

    -- ── Action row 2 — Duplicate / Delete ──
    frame.duplicateButton = Widgets.CreateButton(frame, Text.UI_DUPLICATE, Frame.BUTTON_WIDTH_MD)
    frame.duplicateButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, Frame.ACTION_ROW2_BOTTOM)
    frame.duplicateButton:SetScript("OnClick", function()
        SlotFiller.UI.ProfilePopups.ShowDuplicate(selectedProfile, onProfilePopupSuccess)
    end)

    frame.deleteButton = Widgets.CreateButton(frame, Text.UI_DELETE, Frame.BUTTON_WIDTH_SM)
    frame.deleteButton:SetPoint("LEFT", frame.duplicateButton, "RIGHT", 6, 0)
    frame.deleteButton:SetScript("OnClick", function()
        SlotFiller.UI.ProfilePopups.ShowDelete(selectedProfile, onProfilePopupSuccess)
    end)

    -- ── Save row ──
    frame.saveBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.saveBox:SetAutoFocus(false)
    frame.saveBox:SetSize(Frame.SAVE_BOX_WIDTH, 24)
    frame.saveBox:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, Frame.SAVE_BOTTOM)
    frame.saveBox:SetMaxLetters(Constants.MAX_PROFILE_NAME_LEN)
    self:SetupSaveBox(frame.saveBox)

    frame.saveButton = Widgets.CreateButton(frame, Text.UI_SAVE, Frame.SAVE_BUTTON_WIDTH)
    frame.saveButton:SetPoint("LEFT", frame.saveBox, "RIGHT", 8, 0)
    frame.saveButton:SetScript("OnClick", function() MainFrame:SaveFromInput() end)
    frame.saveBox:SetScript("OnEnterPressed", function()
        MainFrame:SaveFromInput()
        frame.saveBox:ClearFocus()
    end)
    frame.saveBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    frame.closeButton = Widgets.CreateButton(frame, Text.UI_CLOSE, Frame.CLOSE_BUTTON_WIDTH)
    frame.closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, Frame.FOOTER_BOTTOM)
    frame.closeButton:SetScript("OnClick", function() frame:Hide() end)

    self.frame = frame
    -- Register with the engine so Escape closes the panel.
    table.insert(UISpecialFrames, "SlotFillerMainFrame")
    self:EnsureSaveBoxOverlay()
    self:UpdateSavePlaceholder()
    self:SetupDropdownMenus()
    return frame
end

-- ── Public methods ──────────────────────────────────────────────────────────

function MainFrame:Refresh()
    local frame = self:Ensure()

    local indexModel = SlotFiller.ProfileIndex.Build()

    -- Build "Name-Realm · Class · Spec" info line. Always updated, even when
    -- RequireReady() below would fail, so the header never shows stale data
    -- from a previous character while the panel is open.
    local specParts = {}
    local charName  = indexModel.characterName
    if charName then
        local realm = indexModel.realmName
        specParts[#specParts + 1] = realm and (charName .. "-" .. realm) or charName
    end
    if indexModel.className then specParts[#specParts + 1] = indexModel.className end
    if indexModel.specName  then specParts[#specParts + 1] = indexModel.specName  end
    frame.specLabel:SetText(table.concat(specParts, " · "))

    if indexModel.activeProfile then
        frame.activeLabel:SetText(string.format(Text.UI_ACTIVE, indexModel.activeProfile))
        frame.activeLabel:Show()
    else
        frame.activeLabel:Hide()
    end

    if not SlotFiller.Context.RequireReady() then return end

    -- Keep selectedProfile valid after renames / deletes.
    local names = SlotFiller.State:ListProfileNames()
    local stillExists = false
    for _, n in ipairs(names) do
        if n == selectedProfile then stillExists = true; break end
    end
    if not stillExists then
        selectedProfile = indexModel.activeProfile
    end

    -- Rebuild all dropdowns to reflect current state.
    loadAutoLoadConfig(selectedProfile)
    if self.rebuildProfileDropdown then
        self.rebuildProfileDropdown()
        self.rebuildAutoLoadCheck()
        self.rebuildCharsText()
        self.rebuildClassesText()
        self.rebuildSpecsText()
    end

    self:EnsureSaveBoxOverlay()
    self:UpdateSavePlaceholder()
end

function MainFrame:ShowPanel()
    self:Ensure()
    -- Always start with the currently active profile highlighted so the panel
    -- reflects reality each time it is opened, regardless of any stale
    -- in-session dropdown selection from a previous open.
    selectedProfile = SlotFiller.State:GetActiveProfileName()
    self:Refresh()
    self.frame:Show()
    -- Re-apply filter text after Show() as a guard against any OnShow
    -- behaviour in Blizzard templates that might reset widget display state.
    if self.rebuildCharsText then
        self.rebuildCharsText()
        self.rebuildClassesText()
        self.rebuildSpecsText()
    end
end

function MainFrame:Toggle()
    self:Ensure()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:ShowPanel()
    end
end
