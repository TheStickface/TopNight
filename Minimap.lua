-- =============================================================================
-- Topnight - Minimap.lua
-- Feature: Standalone Minimap Button
-- =============================================================================

local ADDON_NAME, Topnight = ...

local minimapButton = nil

-- ---------------------------------------------------------------------------
-- Math helper for Minimap Positioning
-- ---------------------------------------------------------------------------
local function UpdateMinimapButtonPosition(angle)
    if not minimapButton then return end
    
    -- Minimap radius varies slightly but ~80 is standard
    local radius = 80
    
    -- Convert angle degrees to radians
    local r = math.rad(angle or 220)
    
    -- X corresponds to cos, Y to sin
    -- Standard WoW Minimap is a circle. We offset by (radius * math.cos(r)) and (radius * math.sin(r))
    local x = math.cos(r) * radius
    local y = math.sin(r) * radius
    
    -- The center of the Minimap is the reference
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- ---------------------------------------------------------------------------
-- Drag Handlers
-- ---------------------------------------------------------------------------
local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    
    -- Adjust for UI scale
    local scale = Minimap:GetEffectiveScale()
    cx = cx / scale
    cy = cy / scale
    
    -- Calculate angle from center of minimap to cursor
    local dx = cx - mx
    local dy = cy - my
    local angle = math.deg(math.atan2(dy, dx))
    
    -- Normalize angle to 0-360
    if angle < 0 then
        angle = angle + 360
    end
    
    -- Save exact angle
    local settings = Topnight:GetSetting("minimap")
    if settings then
        settings.minimapPos = angle
    end
    
    UpdateMinimapButtonPosition(angle)
end

local function OnDragStart(self)
    self:LockHighlight()
    self.isDragging = true
    self:SetScript("OnUpdate", OnDragUpdate)
end

local function OnDragStop(self)
    self:UnlockHighlight()
    self.isDragging = false
    self:SetScript("OnUpdate", nil)
    
    -- Persist exactly
    local settings = Topnight:GetSetting("minimap")
    if settings then
        Topnight:SetSetting("minimap", settings)
    end
end

-- ---------------------------------------------------------------------------
-- Click Handlers
-- ---------------------------------------------------------------------------
local function OnClick(self, button)
    if button == "LeftButton" then
        if Topnight.ToggleControlPanel then
            Topnight:ToggleControlPanel()
        end
    elseif button == "RightButton" then
        if Topnight.ToggleCollectionTracker then
            Topnight:ToggleCollectionTracker()
        end
    elseif button == "MiddleButton" then
        if Topnight.ToggleShoppingList then
            Topnight:ToggleShoppingList()
        end
    end
end

local function OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(Topnight.Colors.PREFIX .. "Topnight|r", 1, 1, 1)
    GameTooltip:AddLine("Housing companion and tracker", 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(Topnight.Colors.ACCENT .. "Left-Click:|r", "Control Panel")
    GameTooltip:AddDoubleLine(Topnight.Colors.ACCENT .. "Right-Click:|r", "Collection Tracker")
    GameTooltip:AddDoubleLine(Topnight.Colors.ACCENT .. "Middle-Click:|r", "Shopping List")
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(Topnight.Colors.INFO .. "Drag to move button|r")
    GameTooltip:Show()
end

local function OnLeave(self)
    GameTooltip:Hide()
end

-- ---------------------------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------------------------

function Topnight:InitMinimap()
    local settings = self:GetSetting("minimap")
    if settings.hide then return end

    if not minimapButton then
        -- Create container frame
        minimapButton = CreateFrame("Button", "TopnightMinimapButton", Minimap)
        minimapButton:SetSize(31, 31)
        minimapButton:SetFrameLevel(8)
        minimapButton:SetMovable(true)
        minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

        -- Registration for dragging
        minimapButton:RegisterForDrag("LeftButton")
        minimapButton:SetScript("OnDragStart", OnDragStart)
        minimapButton:SetScript("OnDragStop", OnDragStop)

        -- Registration for clicks
        minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
        minimapButton:SetScript("OnClick", OnClick)

        -- Tooltips
        minimapButton:SetScript("OnEnter", OnEnter)
        minimapButton:SetScript("OnLeave", OnLeave)

        -- Minimap border ring base
        minimapButton.border = minimapButton:CreateTexture(nil, "OVERLAY")
        minimapButton.border:SetSize(52, 52)
        minimapButton.border:SetPoint("TOPLEFT", -2, 2)
        minimapButton.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

        -- Icon inside the ring
        minimapButton.icon = minimapButton:CreateTexture(nil, "ARTWORK")
        minimapButton.icon:SetSize(20, 20)
        minimapButton.icon:SetPoint("CENTER", -1, 1) -- Shifted 1px left and up to align perfectly in the default ring
        minimapButton.icon:SetTexture("Interface/Icons/INV_Misc_StarMap")
        
        -- Mask to make the square icon round (so it fits cleanly in the ring)
        minimapButton.mask = minimapButton:CreateMaskTexture()
        minimapButton.mask:SetTexture("Interface/CharacterFrame/TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        minimapButton.mask:SetSize(20, 20)
        minimapButton.mask:SetPoint("CENTER", minimapButton.icon, "CENTER")
        minimapButton.icon:AddMaskTexture(minimapButton.mask)

        -- Inner circle background to block minimap map behind text/alpha
        minimapButton.bg = minimapButton:CreateTexture(nil, "BACKGROUND")
        minimapButton.bg:SetSize(20, 20)
        minimapButton.bg:SetPoint("CENTER", -1, 1)
        minimapButton.bg:SetColorTexture(0, 0, 0, 0.7)
    end

    minimapButton:Show()
    UpdateMinimapButtonPosition(settings.minimapPos)
    self:Debug("Minimap button initialized.")
end

function Topnight:ToggleMinimapButton()
    local settings = self:GetSetting("minimap")
    settings.hide = not settings.hide
    self:SetSetting("minimap", settings)
    
    if settings.hide then
        if minimapButton then minimapButton:Hide() end
        self:PrintInfo("Minimap button disabled. Use '/tn minimap' to restore.")
    else
        self:InitMinimap()
        self:PrintSuccess("Minimap button enabled.")
    end
end
