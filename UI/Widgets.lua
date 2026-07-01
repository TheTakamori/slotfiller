local _, SlotFiller = ...

local Constants = SlotFiller.Constants
local Colors = Constants.COLORS

-- Small, reusable widget-creation helpers shared across UI/*.lua frames.
-- Creation only (per the reuse rule, widget creation is kept separate from
-- widget application, which each caller does itself after constructing).
SlotFiller.UI = SlotFiller.UI or {}
SlotFiller.UI.Widgets = {}

local Widgets = SlotFiller.UI.Widgets

function Widgets.ApplyBackdrop(frame)
    frame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(Colors.BODY[1], Colors.BODY[2], Colors.BODY[3], Colors.BODY[4])
    frame:SetBackdropBorderColor(Colors.BORDER[1], Colors.BORDER[2], Colors.BORDER[3], Colors.BORDER[4])
end

function Widgets.CreateLabel(parent, text, fontObject)
    local label = parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlight")
    label:SetText(text or "")
    label:SetTextColor(Colors.TEXT[1], Colors.TEXT[2], Colors.TEXT[3])
    return label
end

function Widgets.CreateButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or Constants.FRAME.BUTTON_WIDTH_SM, Constants.FRAME.DD_HEIGHT)
    button:SetText(text)
    return button
end

-- Attaches a GameTooltip OnEnter/OnLeave pair to hoverFrame showing a
-- title line followed by a wrapped hint line. titleColor/hintColor default
-- to Constants.COLORS.TOOLTIP_TITLE/TOOLTIP_BODY; pass a different color
-- table to highlight the title instead.
function Widgets.AttachTooltip(hoverFrame, titleText, hintText, titleColor, hintColor)
    titleColor = titleColor or Colors.TOOLTIP_TITLE
    hintColor  = hintColor  or Colors.TOOLTIP_BODY
    hoverFrame:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(titleText, titleColor[1], titleColor[2], titleColor[3])
        GameTooltip:AddLine(hintText, hintColor[1], hintColor[2], hintColor[3], true)
        GameTooltip:Show()
    end)
    hoverFrame:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end
