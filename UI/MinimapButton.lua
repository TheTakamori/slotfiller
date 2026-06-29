local _, SlotFiller = ...

local Constants = SlotFiller.Constants
local Text = SlotFiller.Text
local WoW = SlotFiller.WoWConstants
local MinimapLayout = Constants.MINIMAP
local Texture = Constants.TEXTURE

SlotFiller.UI = SlotFiller.UI or {}
SlotFiller.UI.MinimapButton = {}

local MinimapButton = SlotFiller.UI.MinimapButton

local minimapShapes = {
    ["ROUND"] = { true, true, true, true },
    ["SQUARE"] = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function normalizeAngle(angle)
    angle = tonumber(angle) or 220
    angle = math.fmod(angle, 360)
    if angle < 0 then
        angle = angle + 360
    end
    return angle
end

local function atan2(y, x)
    if math.atan2 then
        return math.atan2(y, x)
    end
    if x > 0 then
        return math.atan(y / x)
    elseif x < 0 and y >= 0 then
        return math.atan(y / x) + math.pi
    elseif x < 0 and y < 0 then
        return math.atan(y / x) - math.pi
    elseif x == 0 and y > 0 then
        return math.pi / 2
    elseif x == 0 and y < 0 then
        return -math.pi / 2
    end
    return 0
end

local function setButtonAngle(button, angle)
    if not button or not Minimap then
        return
    end

    angle = normalizeAngle(angle)
    local radians = math.rad(angle)
    local x = math.cos(radians)
    local y = math.sin(radians)
    local quadrant = 1
    if x < 0 then
        quadrant = quadrant + 1
    end
    if y > 0 then
        quadrant = quadrant + 2
    end

    local widthRadius = (Minimap:GetWidth() / 2) + MinimapLayout.RADIUS_OFFSET
    local heightRadius = (Minimap:GetHeight() / 2) + MinimapLayout.RADIUS_OFFSET
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local quadrants = minimapShapes[shape] or minimapShapes["ROUND"]
    if quadrants[quadrant] then
        x = x * widthRadius
        y = y * heightRadius
    else
        local diagonalWidth = math.sqrt(2 * (widthRadius ^ 2)) - 10
        local diagonalHeight = math.sqrt(2 * (heightRadius ^ 2)) - 10
        x = math.max(-widthRadius, math.min(x * diagonalWidth, widthRadius))
        y = math.max(-heightRadius, math.min(y * diagonalHeight, heightRadius))
    end

    button:ClearAllPoints()
    button:SetPoint(WoW.UI.ANCHOR_CENTER, Minimap, WoW.UI.ANCHOR_CENTER, x, y)
    button.currentAngle = angle
end

local function updateDragPosition(button)
    if not button or not Minimap or not GetCursorPosition then
        return
    end

    local scale = Minimap:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    if button.dragStartX and button.dragStartY then
        local deltaX = cursorX - button.dragStartX
        local deltaY = cursorY - button.dragStartY
        if (deltaX * deltaX) + (deltaY * deltaY) > 4 then
            button.dragMoved = true
        end
    end

    local centerX, centerY = Minimap:GetCenter()
    centerX = (centerX or 0) * scale
    centerY = (centerY or 0) * scale
    setButtonAngle(button, math.deg(atan2(cursorY - centerY, cursorX - centerX)))
end

local function showTooltip(button)
    if not GameTooltip then
        return
    end
    GameTooltip:SetOwner(button, WoW.UI.ANCHOR_LEFT)
    GameTooltip:ClearLines()
    GameTooltip:AddLine(Text.MINIMAP_TOOLTIP_TITLE, 1, 1, 1)
    GameTooltip:AddLine(Text.MINIMAP_TOOLTIP_OPEN, 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine(Text.MINIMAP_TOOLTIP_TOGGLE, 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine(Text.MINIMAP_TOOLTIP_DRAG, 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

function MinimapButton:SetHidden(hidden)
    SlotFiller.State:SetMinimapHidden(hidden)
    if self.button then
        self.button:SetShown(not hidden)
    end
    SlotFiller.Print(hidden and Text.MINIMAP_HIDDEN or Text.MINIMAP_SHOWN)
end

function MinimapButton:ToggleHidden()
    self:SetHidden(not SlotFiller.State:IsMinimapHidden())
end

function MinimapButton:RefreshVisibility()
    if self.button then
        self.button:SetShown(not SlotFiller.State:IsMinimapHidden())
    end
end

function MinimapButton:Ensure()
    if self.button then
        setButtonAngle(self.button, SlotFiller.State:GetMinimapAngle())
        self:RefreshVisibility()
        return self.button
    end
    if not Minimap then
        return nil
    end

    local button = CreateFrame(WoW.UI.BUTTON, "SlotFillerMinimapButton", Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel((Minimap:GetFrameLevel() or 0) + MinimapLayout.FRAME_LEVEL_OFFSET)
    button:SetSize(MinimapLayout.BUTTON_SIZE, MinimapLayout.BUTTON_SIZE)
    button:RegisterForClicks(WoW.UI.ANY_UP)
    button:RegisterForDrag(WoW.UI.LEFT_BUTTON)
    button:SetHighlightTexture(Texture.MINIMAP_HIGHLIGHT, WoW.UI.ADD)

    local background = button:CreateTexture(nil, WoW.UI.BACKGROUND)
    background:SetTexture(Texture.MINIMAP_BACKGROUND)
    background:SetSize(MinimapLayout.BACKGROUND_SIZE, MinimapLayout.BACKGROUND_SIZE)
    background:SetPoint(WoW.UI.ANCHOR_CENTER, button, WoW.UI.ANCHOR_CENTER)

    local icon = button:CreateTexture(nil, WoW.UI.ARTWORK)
    icon:SetTexture(Texture.MINIMAP_ICON)
    icon:SetSize(MinimapLayout.ICON_SIZE, MinimapLayout.ICON_SIZE)
    icon:SetPoint(WoW.UI.ANCHOR_TOPLEFT, button, WoW.UI.ANCHOR_TOPLEFT, MinimapLayout.ICON_OFFSET_X, MinimapLayout.ICON_OFFSET_Y)
    icon:SetTexCoord(
        MinimapLayout.TEX_COORD_LEFT,
        MinimapLayout.TEX_COORD_RIGHT,
        MinimapLayout.TEX_COORD_TOP,
        MinimapLayout.TEX_COORD_BOTTOM
    )

    local border = button:CreateTexture(nil, WoW.UI.OVERLAY)
    border:SetTexture(Texture.MINIMAP_BORDER)
    border:SetSize(MinimapLayout.OVERLAY_SIZE, MinimapLayout.OVERLAY_SIZE)
    border:SetPoint(WoW.UI.ANCHOR_TOPLEFT, button, WoW.UI.ANCHOR_TOPLEFT)

    button:SetScript(WoW.UI.ON_CLICK, function(self)
        if self.suppressNextClick then
            self.suppressNextClick = nil
            return
        end
        SlotFiller.UI.MainFrame:ShowPanel()
    end)
    button:SetScript(WoW.UI.ON_ENTER, showTooltip)
    button:SetScript(WoW.UI.ON_LEAVE, function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    button:SetScript(WoW.UI.ON_DRAG_START, function(self)
        self.dragMoved = nil
        self.dragStartX, self.dragStartY = GetCursorPosition()
        self:SetScript(WoW.UI.ON_UPDATE, updateDragPosition)
    end)
    button:SetScript(WoW.UI.ON_DRAG_STOP, function(self)
        self:SetScript(WoW.UI.ON_UPDATE, nil)
        updateDragPosition(self)
        SlotFiller.State:SetMinimapAngle(self.currentAngle)
        self.dragStartX = nil
        self.dragStartY = nil
        if self.dragMoved then
            self.suppressNextClick = true
            self.dragMoved = nil
        end
    end)

    setButtonAngle(button, SlotFiller.State:GetMinimapAngle())
    self.button = button
    self:RefreshVisibility()
    return button
end
