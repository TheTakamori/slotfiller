local _, SlotFiller = ...

local Constants = SlotFiller.Constants
local Text = SlotFiller.Text
local Colors = Constants.COLORS
local Frame = Constants.FRAME

SlotFiller.UI = SlotFiller.UI or {}
SlotFiller.UI.MainFrame = {}

local MainFrame = SlotFiller.UI.MainFrame

-- ── Module-level dropdown-selection state ──────────────────────────────────
-- These are the currently displayed auto-load filters for `selectedProfile`.
local selectedProfile    = nil
local selectedAutoLoad   = false  -- mirrors the "Allow Profile Auto Load" checkbox
local selectedChars      = {}   -- set: "Name-Realm" → true
local selectedClasses    = {}   -- set: "PALADIN"    → true
local selectedSpecs      = {}   -- set: "Retribution" → true

-- ── Helpers ────────────────────────────────────────────────────────────────

local function applyBackdrop(frame)
    frame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(Colors.BODY[1], Colors.BODY[2], Colors.BODY[3], Colors.BODY[4])
    frame:SetBackdropBorderColor(Colors.BORDER[1], Colors.BORDER[2], Colors.BORDER[3], Colors.BORDER[4])
end

local function createLabel(parent, text, fontObject)
    local label = parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlight")
    label:SetText(text or "")
    label:SetTextColor(Colors.TEXT[1], Colors.TEXT[2], Colors.TEXT[3])
    return label
end

local function createButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 72, 22)
    button:SetText(text)
    return button
end

local function trim(text)
    return (text or ""):match("^%s*(.-)%s*$") or ""
end

local function getStaticPopupEditBox(dialog)
    if not dialog then return nil end
    return dialog.EditBox or dialog.editBox
end

local function getStaticPopupEditText(dialog)
    local editBox = getStaticPopupEditBox(dialog)
    if not editBox then return "" end
    return trim(editBox:GetText())
end

-- Returns a comma-separated summary of the keys in a selection set, or
-- `Text.UI_AUTOLOAD_ANY` when nothing is selected.
local function selectionSummary(selectionSet)
    local items = {}
    for k in pairs(selectionSet) do items[#items + 1] = k end
    if #items == 0 then return Text.UI_AUTOLOAD_ANY end
    table.sort(items)
    return table.concat(items, ", ")
end

-- ── Auto-load selection helpers ────────────────────────────────────────────

-- Classes eligible for the Classes dropdown given the current char selection.
local function getEligibleClasses()
    if next(selectedChars) == nil then
        return SlotFiller.Context.GetAllClasses()
    end
    local known   = SlotFiller.State:GetKnownCharacters()
    local seen    = {}
    local result  = {}
    for _, info in ipairs(known) do
        if selectedChars[info.key] and not seen[info.file] then
            seen[info.file]  = true
            -- Find the localized class name from all-classes lookup
            local allClasses = SlotFiller.Context.GetAllClasses()
            for _, ci in ipairs(allClasses) do
                if ci.file == info.file then
                    result[#result + 1] = ci
                    break
                end
            end
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

-- Specs eligible for the Specs dropdown given the current class selection.
local function getEligibleSpecs()
    local allClasses = SlotFiller.Context.GetAllClasses()
    local classById  = {}
    for _, ci in ipairs(allClasses) do classById[ci.file] = ci end

    local classFiles = {}
    for file in pairs(selectedClasses) do classFiles[#classFiles + 1] = file end
    table.sort(classFiles)

    local result = {}
    for _, file in ipairs(classFiles) do
        local ci = classById[file]
        if ci then
            for _, spec in ipairs(SlotFiller.Context.GetSpecsForClass(ci.id)) do
                result[#result + 1] = {
                    key   = spec.name,
                    label = ci.name .. " — " .. spec.name,
                }
            end
        end
    end
    return result
end

local function pruneInvalidClasses()
    if next(selectedChars) == nil then return end
    local eligible = getEligibleClasses()
    local valid    = {}
    for _, ci in ipairs(eligible) do valid[ci.file] = true end
    for file in pairs(selectedClasses) do
        if not valid[file] then selectedClasses[file] = nil end
    end
end

local function pruneInvalidSpecs()
    if next(selectedClasses) == nil then
        for k in pairs(selectedSpecs) do selectedSpecs[k] = nil end
        return
    end
    local eligible = getEligibleSpecs()
    local valid    = {}
    for _, s in ipairs(eligible) do valid[s.key] = true end
    for key in pairs(selectedSpecs) do
        if not valid[key] then selectedSpecs[key] = nil end
    end
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
        local specs = getEligibleSpecs()
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
        local classes = getEligibleClasses()
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
                    pruneInvalidSpecs()
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
                    pruneInvalidClasses()
                    pruneInvalidSpecs()
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
        frame.classDropdown:SetText(selectionSummary(selectedClasses))
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
    local hasText  = trim(frame.saveBox:GetText()) ~= ""
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
    return trim(saveBox:GetText())
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
    applyBackdrop(frame)

    -- ── Header ──
    frame.title = createLabel(frame, Text.UI_TITLE, "GameFontNormalLarge")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -16)

    frame.specLabel = createLabel(frame, "")
    frame.specLabel:SetPoint("TOP", frame.title, "BOTTOM", 0, -8)

    frame.activeLabel = createLabel(frame, "")
    frame.activeLabel:SetPoint("TOP", frame.specLabel, "BOTTOM", 0, -4)
    frame.activeLabel:SetTextColor(Colors.MUTED[1], Colors.MUTED[2], Colors.MUTED[3])

    -- ── Footer ──
    frame.versionLabel = createLabel(frame, "v" .. Constants.VERSION, "GameFontNormalSmall")
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
    frame.sbaWarningLabel:SetTextColor(1, 0.6, 0, 1)
    frame.sbaHover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(Text.UI_SBA_WARNING, 1, 0.6, 0)
        GameTooltip:AddLine(Text.UI_SBA_HINT, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.sbaHover:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- ── Profile dropdown ──
    frame.profileLabel = createLabel(frame, Text.UI_PROFILE_LABEL, "GameFontNormalSmall")
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

    -- ── Characters dropdown ──
    frame.charsLabel = createLabel(frame, Text.UI_CHARACTERS_LABEL, "GameFontNormalSmall")
    frame.charsLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, Frame.CHARS_BOTTOM + Frame.DD_HEIGHT + 4)

    frame.charDropdown = CreateFrame("DropdownButton", "SlotFillerCharDropdown", frame, "WowStyle1FilterDropdownTemplate")
    frame.charDropdown:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  20,  Frame.CHARS_BOTTOM)
    frame.charDropdown:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, Frame.CHARS_BOTTOM)
    frame.charDropdown:SetText(Text.UI_AUTOLOAD_ANY)

    -- ── Classes dropdown ──
    frame.classesLabel = createLabel(frame, Text.UI_CLASSES_LABEL, "GameFontNormalSmall")
    frame.classesLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, Frame.CLASSES_BOTTOM + Frame.DD_HEIGHT + 4)

    frame.classDropdown = CreateFrame("DropdownButton", "SlotFillerClassDropdown", frame, "WowStyle1FilterDropdownTemplate")
    frame.classDropdown:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  20,  Frame.CLASSES_BOTTOM)
    frame.classDropdown:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, Frame.CLASSES_BOTTOM)
    frame.classDropdown:SetText(Text.UI_AUTOLOAD_ANY)

    -- ── Specs dropdown ──
    frame.specsLabel = createLabel(frame, Text.UI_SPECS_LABEL, "GameFontNormalSmall")
    frame.specsLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, Frame.SPECS_BOTTOM + Frame.DD_HEIGHT + 4)

    frame.specDropdown = CreateFrame("DropdownButton", "SlotFillerSpecDropdown", frame, "WowStyle1FilterDropdownTemplate")
    frame.specDropdown:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  20,  Frame.SPECS_BOTTOM)
    frame.specDropdown:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, Frame.SPECS_BOTTOM)
    frame.specDropdown:SetText(Text.UI_AUTOLOAD_ANY)

    -- ── Action row 1 — Load / Overwrite / Rename ──
    frame.loadButton = createButton(frame, Text.UI_LOAD, 72)
    frame.loadButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, Frame.ACTION_ROW1_BOTTOM)
    frame.loadButton:SetScript("OnClick", function()
        if not selectedProfile or not SlotFiller.Context.RequireReady() then return end
        if SlotFiller.ProfileActions:Load(selectedProfile) then
            MainFrame:Refresh()
        end
    end)

    frame.overwriteButton = createButton(frame, Text.UI_OVERWRITE, 88)
    frame.overwriteButton:SetPoint("LEFT", frame.loadButton, "RIGHT", 6, 0)
    frame.overwriteButton:SetScript("OnClick", function()
        if not selectedProfile then return end
        StaticPopupDialogs.SLOTFILLER_OVERWRITE = {
            text = Text.UI_CONFIRM_OVERWRITE, button1 = YES, button2 = NO,
            OnAccept = function(dialog)
                local name = dialog.data
                -- Flush any pending UI selections to State before the overwrite
                -- operation reads existing.autoLoad from State, so deselections
                -- made in the filter dropdowns are not silently discarded.
                saveCurrentAutoLoad()
                if SlotFiller.Context.RequireReady()
                    and SlotFiller.ProfileActions:Overwrite(name) then
                    MainFrame:Refresh()
                end
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show("SLOTFILLER_OVERWRITE", selectedProfile, nil, selectedProfile)
    end)

    frame.renameButton = createButton(frame, Text.UI_RENAME, 72)
    frame.renameButton:SetPoint("LEFT", frame.overwriteButton, "RIGHT", 6, 0)
    frame.renameButton:SetScript("OnClick", function()
        if not selectedProfile then return end
        local profileName = selectedProfile
        StaticPopupDialogs.SLOTFILLER_RENAME = {
            text = Text.UI_RENAME_PROMPT, button1 = ACCEPT, button2 = CANCEL,
            hasEditBox = true, maxLetters = 32,
            OnAccept = function(dialog)
                local oldName = dialog.data
                local newName = getStaticPopupEditText(dialog)
                if SlotFiller.Context.RequireReady()
                    and SlotFiller.ProfileActions:Rename(oldName, newName) then
                    selectedProfile = newName
                    MainFrame:Refresh()
                end
            end,
            EditBoxOnEnterPressed = function(editBox)
                local dialog  = editBox:GetParent()
                local oldName = (dialog and dialog.data) or profileName
                local newName = trim(editBox:GetText())
                if SlotFiller.Context.RequireReady()
                    and SlotFiller.ProfileActions:Rename(oldName, newName) then
                    selectedProfile = newName
                    MainFrame:Refresh()
                end
                if dialog then dialog:Hide() end
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show("SLOTFILLER_RENAME", profileName, nil, profileName)
    end)

    -- ── Action row 2 — Duplicate / Delete ──
    frame.duplicateButton = createButton(frame, Text.UI_DUPLICATE, 88)
    frame.duplicateButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, Frame.ACTION_ROW2_BOTTOM)
    frame.duplicateButton:SetScript("OnClick", function()
        if not selectedProfile then return end
        local profileName = selectedProfile
        StaticPopupDialogs.SLOTFILLER_DUPLICATE = {
            text = Text.UI_DUPLICATE_PROMPT, button1 = ACCEPT, button2 = CANCEL,
            hasEditBox = true, maxLetters = 32,
            OnAccept = function(dialog)
                local sourceName = dialog.data
                local newName    = getStaticPopupEditText(dialog)
                if SlotFiller.Context.RequireReady()
                    and SlotFiller.ProfileActions:Duplicate(sourceName, newName) then
                    selectedProfile = newName
                    MainFrame:Refresh()
                end
            end,
            EditBoxOnEnterPressed = function(editBox)
                local dialog     = editBox:GetParent()
                local sourceName = (dialog and dialog.data) or profileName
                local newName    = trim(editBox:GetText())
                if SlotFiller.Context.RequireReady()
                    and SlotFiller.ProfileActions:Duplicate(sourceName, newName) then
                    selectedProfile = newName
                    MainFrame:Refresh()
                end
                if dialog then dialog:Hide() end
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show("SLOTFILLER_DUPLICATE", profileName, nil, profileName)
    end)

    frame.deleteButton = createButton(frame, Text.UI_DELETE, 72)
    frame.deleteButton:SetPoint("LEFT", frame.duplicateButton, "RIGHT", 6, 0)
    frame.deleteButton:SetScript("OnClick", function()
        if not selectedProfile then return end
        local profileName = selectedProfile
        StaticPopupDialogs.SLOTFILLER_DELETE = {
            text = Text.UI_CONFIRM_DELETE, button1 = YES, button2 = NO,
            OnAccept = function(dialog)
                local name = dialog.data
                if SlotFiller.Context.RequireReady()
                    and SlotFiller.ProfileActions:Delete(name) then
                    selectedProfile = nil
                    MainFrame:Refresh()
                end
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show("SLOTFILLER_DELETE", profileName, nil, profileName)
    end)

    -- ── Save row ──
    frame.saveBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.saveBox:SetAutoFocus(false)
    frame.saveBox:SetSize(Frame.SAVE_BOX_WIDTH, 24)
    frame.saveBox:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, Frame.SAVE_BOTTOM)
    frame.saveBox:SetMaxLetters(32)
    self:SetupSaveBox(frame.saveBox)

    frame.saveButton = createButton(frame, Text.UI_SAVE, Frame.SAVE_BUTTON_WIDTH)
    frame.saveButton:SetPoint("LEFT", frame.saveBox, "RIGHT", 8, 0)
    frame.saveButton:SetScript("OnClick", function() MainFrame:SaveFromInput() end)
    frame.saveBox:SetScript("OnEnterPressed", function()
        MainFrame:SaveFromInput()
        frame.saveBox:ClearFocus()
    end)
    frame.saveBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    frame.closeButton = createButton(frame, Text.UI_CLOSE, Frame.CLOSE_BUTTON_WIDTH)
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
    if not SlotFiller.Context.RequireReady() then return end

    local indexModel = SlotFiller.ProfileIndex:Build()

    -- Build "Name-Realm · Class · Spec" info line.
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

function MainFrame:HidePanel()
    if self.frame then self.frame:Hide() end
end

function MainFrame:Toggle()
    self:Ensure()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:ShowPanel()
    end
end
