-- =============================================================================
-- Topnight - Options.lua
-- Feature: Native WoW Settings Panel (/tn config)
-- =============================================================================

local ADDON_NAME, Topnight = ...

-- ---------------------------------------------------------------------------
-- Panel Construction
-- ---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "TopnightOptionsPanel", UIParent)
frame.name = "Topnight"

-- Title
local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Topnight Configuration")

local subText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subText:SetText("Configure the Topnight housing companion addon.")
subText:SetJustifyH("LEFT")

-- ---------------------------------------------------------------------------
-- Widgets
-- ---------------------------------------------------------------------------

-- 1. Welcome Message Checkbox
local cbWelcome = CreateFrame("CheckButton", "TopnightCheckboxWelcome", frame, "InterfaceOptionsCheckButtonTemplate")
cbWelcome:SetPoint("TOPLEFT", subText, "BOTTOMLEFT", 0, -20)
TopnightCheckboxWelcomeText:SetText("Show welcome message on login")
cbWelcome:SetScript("OnClick", function(self)
    Topnight:SetSetting("welcomeMessage", self:GetChecked())
end)

-- 2. Minimap Button Checkbox
local cbMinimap = CreateFrame("CheckButton", "TopnightCheckboxMinimap", frame, "InterfaceOptionsCheckButtonTemplate")
cbMinimap:SetPoint("TOPLEFT", cbWelcome, "BOTTOMLEFT", 0, -8)
TopnightCheckboxMinimapText:SetText("Show minimap button")
cbMinimap:SetScript("OnClick", function(self)
    local minimapDB = Topnight:GetSetting("minimap")
    minimapDB.hide = not self:GetChecked()
    Topnight:SetSetting("minimap", minimapDB)
    if Topnight.UpdateMinimapVisibility then
        Topnight:UpdateMinimapVisibility()
    end
end)

-- 2b. Minimap Vignette Highlights Checkbox
local cbVignettes = CreateFrame("CheckButton", "TopnightCheckboxVignettes", frame, "InterfaceOptionsCheckButtonTemplate")
cbVignettes:SetPoint("TOPLEFT", cbMinimap, "BOTTOMLEFT", 0, -8)
TopnightCheckboxVignettesText:SetText("Highlight Midnight vignettes on minimap")
cbVignettes:SetScript("OnClick", function(self)
    if Topnight.ToggleMinimapVignettes then
        Topnight:ToggleMinimapVignettes()
        -- Keep checkbox in sync with actual state
        self:SetChecked(Topnight:IsMinimapVignettesEnabled())
    end
end)

-- 3. Control Panel Opacity Slider
local sliderOpacity = CreateFrame("Slider", "TopnightSliderOpacity", frame, "OptionsSliderTemplate")
sliderOpacity:SetPoint("TOPLEFT", cbVignettes, "BOTTOMLEFT", 4, -30)
sliderOpacity:SetMinMaxValues(0.1, 1.0)
sliderOpacity:SetValueStep(0.05)
sliderOpacity:SetObeyStepOnDrag(true)
TopnightSliderOpacityText:SetText("Control Panel Opacity")
TopnightSliderOpacityLow:SetText("10%")
TopnightSliderOpacityHigh:SetText("100%")

sliderOpacity:SetScript("OnValueChanged", function(self, value)
    local db = Topnight:GetSetting("controlPanel")
    db.alpha = value
    Topnight:SetSetting("controlPanel", db)
    
    if Topnight.UpdateControlPanelOpacity then
        Topnight:UpdateControlPanelOpacity(value)
    end
end)

-- 4. Reset Button
local btnReset = CreateFrame("Button", "TopnightBtnReset", frame, "UIPanelButtonTemplate")
btnReset:SetSize(120, 22)
btnReset:SetPoint("BOTTOMLEFT", 16, 16)
btnReset:SetText("Reset Defaults")
btnReset:SetScript("OnClick", function()
    Topnight:ResetSettings()
    -- Safely reload UI
    ReloadUI()
end)

-- ---------------------------------------------------------------------------
-- Panel Registration & Sync
-- ---------------------------------------------------------------------------

frame:SetScript("OnShow", function()
    -- Sync widget states with DB when the panel opens
    cbWelcome:SetChecked(Topnight:GetSetting("welcomeMessage") ~= false)
    
    local minimapDB = Topnight:GetSetting("minimap")
    cbMinimap:SetChecked(minimapDB.hide ~= true)

    cbVignettes:SetChecked(Topnight:IsMinimapVignettesEnabled() == true)
    
    local cpDB = Topnight:GetSetting("controlPanel")
    sliderOpacity:SetValue(cpDB.alpha or 1.0)
end)

-- Register the category with the WoW Settings API
if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(frame, frame.name)
    Settings.RegisterAddOnCategory(category)
    Topnight.category = category
    Topnight.SettingsCategoryID = category.ID
else
    -- Fallback for older WoW clients
    InterfaceOptions_AddCategory(frame)
end
