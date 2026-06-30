local _, SlotFiller = ...

local Constants = SlotFiller.Constants
local Text = SlotFiller.Text
local Colors = Constants.COLORS

SlotFiller.UI = SlotFiller.UI or {}
SlotFiller.UI.CopyFrame = {}

local frame

local function build()
    frame = CreateFrame("Frame", "SlotFillerCopyFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(520, 380)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetToplevel(true)

    if frame.TitleText then
        frame.TitleText:SetText(Constants.ADDON_TITLE)
    end

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -30)
    hint:SetText(Text.UI_COPY_HINT)
    hint:SetTextColor(Colors.MUTED[1], Colors.MUTED[2], Colors.MUTED[3], Colors.MUTED[4])

    local sf = CreateFrame("ScrollFrame", "SlotFillerCopyScrollFrame", frame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",  frame, "TOPLEFT",  8, -50)
    sf:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 8)

    local eb = CreateFrame("EditBox", "SlotFillerCopyEditBox", sf)
    eb:SetWidth(sf:GetWidth())
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject("ChatFontNormal")
    eb:SetScript("OnEscapePressed", function() frame:Hide() end)

    sf:SetScrollChild(eb)
    sf:SetScript("OnSizeChanged", function(self)
        eb:SetWidth(self:GetWidth())
    end)

    frame.editBox = eb
    frame.scrollFrame = sf
end

function SlotFiller.UI.CopyFrame:Show(text)
    if not frame then build() end
    frame.editBox:SetText(text or "")
    frame.editBox:SetFocus()
    frame.editBox:HighlightText()
    frame.scrollFrame:SetVerticalScroll(0)
    frame:Show()
    frame:Raise()
end
