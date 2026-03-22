-- =============================================================================
-- Topnight - ControlPanel.lua
-- Feature 3: Quick Housing Control Panel — floating HUD
-- =============================================================================

local ADDON_NAME, Topnight = ...

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
local PANEL_WIDTH     = 220
local PANEL_EXPANDED  = 640
local PANEL_COLLAPSED = 32
local UPDATE_INTERVAL = 10 -- seconds between auto-refreshes

local C_PURPLE     = { r = 0.545, g = 0.361, b = 0.965 }
local C_DARK_BG    = { r = 0.06,  g = 0.06,  b = 0.10,  a = 0.88 }
local C_GREEN      = { r = 0.133, g = 0.773, b = 0.369 }
local C_YELLOW     = { r = 0.96,  g = 0.78,  b = 0.15 }
local C_RED        = { r = 0.93,  g = 0.27,  b = 0.17 }
local C_ACCENT     = { r = 0.376, g = 0.647, b = 0.980 }
local C_WHITE      = { r = 0.90,  g = 0.90,  b = 0.92 }
local C_GRAY       = { r = 0.45,  g = 0.45,  b = 0.50 }
local C_GLOW       = { r = 0.545, g = 0.361, b = 0.965, a = 0.15 }

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local controlPanel = nil
local isCollapsed = false
local updateTimer = nil

-- ---------------------------------------------------------------------------
-- UI Helpers
-- ---------------------------------------------------------------------------


local function CreateMiniBar(parent, width, height, yOffset, label)
    local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bar:SetSize(width, height)
    bar:SetPoint("TOPLEFT", 10, yOffset)
    Topnight:CreateBackdrop(bar, { r = 0.04, g = 0.04, b = 0.07, a = 0.8 })

    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", 1, -1)
    bar.fill:SetHeight(height - 2)
    bar.fill:SetWidth(1)
    bar.fill:SetTexture("Interface\\Buttons\\WHITE8x8")

    bar.label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.label:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 2)
    bar.label:SetText(label)
    bar.label:SetTextColor(C_GRAY.r, C_GRAY.g, C_GRAY.b)

    bar.value = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.value:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 2)
    bar.value:SetTextColor(C_WHITE.r, C_WHITE.g, C_WHITE.b)

    function bar:SetProgress(current, total, colorOverride)
        local pct = total > 0 and (current / total) or 0
        local fillWidth = math.max(1, (width - 2) * pct)
        bar.fill:SetWidth(fillWidth)

        if colorOverride then
            bar.fill:SetVertexColor(colorOverride.r, colorOverride.g, colorOverride.b, 0.8)
        elseif pct >= 0.9 then
            bar.fill:SetVertexColor(C_RED.r, C_RED.g, C_RED.b, 0.8)
        elseif pct >= 0.7 then
            bar.fill:SetVertexColor(C_YELLOW.r, C_YELLOW.g, C_YELLOW.b, 0.8)
        else
            bar.fill:SetVertexColor(C_GREEN.r, C_GREEN.g, C_GREEN.b, 0.8)
        end

        bar.value:SetText(string.format("%d/%d", current, total))
    end

    return bar
end

-- ---------------------------------------------------------------------------
-- Panel Construction
-- ---------------------------------------------------------------------------

local function CreateControlPanel()
    if controlPanel then return controlPanel end

    local f = CreateFrame("Frame", "TopnightControlPanel", UIParent, "BackdropTemplate")
    f:SetSize(PANEL_WIDTH, PANEL_EXPANDED)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")
    -- Background with dynamic opacity
    local bg = Topnight:DeepCopy(C_DARK_BG)
    local settings = Topnight:GetSetting("controlPanel")
    if settings and settings.alpha then bg.a = settings.alpha end
    Topnight:CreateBackdrop(f, bg)

    -- Position from saved settings
    local settings = Topnight:GetSetting("controlPanel")
    if settings then
        f:SetPoint("CENTER", UIParent, "CENTER", settings.x or -200, settings.y or 200)
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -200)
    end

    -- Dragging
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        local settings = Topnight:GetSetting("controlPanel")
        if settings and not settings.locked then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local settings = Topnight:GetSetting("controlPanel")
        if settings then
            settings.x = cx - ux
            settings.y = cy - uy
            Topnight:SetSetting("controlPanel", settings)
        end
    end)

    -- ========================= HEADER BAR =========================
    f.headerBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.headerBar:SetPoint("TOPLEFT", 0, 0)
    f.headerBar:SetPoint("TOPRIGHT", 0, 0)
    f.headerBar:SetHeight(28)
    Topnight:CreateBackdrop(f.headerBar, { r = C_PURPLE.r * 0.3, g = C_PURPLE.g * 0.3, b = C_PURPLE.b * 0.3, a = 0.95 })

    f.titleText = f.headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.titleText:SetPoint("LEFT", 8, 0)
    f.titleText:SetText("|cff8B5CF6*|r |cffE2E8F0Topnight|r")

    -- Location indicator (glows when in own house)
    f.locationDot = f.headerBar:CreateTexture(nil, "OVERLAY")
    f.locationDot:SetSize(8, 8)
    f.locationDot:SetPoint("LEFT", f.titleText, "RIGHT", 6, 0)
    f.locationDot:SetTexture("Interface\\Buttons\\WHITE8x8")
    f.locationDot:SetVertexColor(C_GRAY.r, C_GRAY.g, C_GRAY.b)

    -- Collapse button
    f.collapseBtn = CreateFrame("Button", nil, f.headerBar)
    f.collapseBtn:SetSize(16, 16)
    f.collapseBtn:SetPoint("RIGHT", -6, 0)
    f.collapseBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Up")
    f.collapseBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Highlight")
    f.collapseBtn:SetScript("OnClick", function()
        isCollapsed = not isCollapsed
        local settings = Topnight:GetSetting("controlPanel")
        if settings then
            settings.collapsed = isCollapsed
            Topnight:SetSetting("controlPanel", settings)
        end
        Topnight:UpdateControlPanelLayout()
    end)

    -- ========================= CONTENT =========================
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", 0, -28)
    f.body:SetPoint("BOTTOMRIGHT", 0, 0)

    local barWidth = PANEL_WIDTH - 20
    local y = -8

    -- ========================= PROGRESSION DIRECTOR =========================
    f.directorBanner = CreateFrame("Frame", nil, f.body, "BackdropTemplate")
    f.directorBanner:SetSize(barWidth, 72)
    f.directorBanner:SetPoint("TOPLEFT", 10, y)
    Topnight:CreateBackdrop(f.directorBanner, { r = 0.1, g = 0.1, b = 0.14, a = 0.9 })
    f.directorIndex = 1  -- which task is currently displayed

    f.directorTitle = f.directorBanner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.directorTitle:SetPoint("TOPLEFT", 6, -6)
    f.directorTitle:SetText("|cffF59E0B> Up Next|r")

    f.directorDesc = f.directorBanner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.directorDesc:SetPoint("TOPLEFT", 6, -22)
    f.directorDesc:SetWidth(barWidth - 24)
    f.directorDesc:SetJustifyH("LEFT")
    f.directorDesc:SetJustifyV("TOP")
    f.directorDesc:SetText("|cff9CA3AFAwaiting evaluation...|r")

    -- Stage dots: 3 circles shown when current task has stageIndicator
    -- Anchored to the top-right of the title row
    local DOT_SIZE = 7
    local DOT_GAP  = 4
    f.directorDots = {}
    for i = 1, 3 do
        local dot = f.directorBanner:CreateTexture(nil, "OVERLAY")
        dot:SetSize(DOT_SIZE, DOT_SIZE)
        dot:SetTexture("Interface\\Buttons\\WHITE8x8")
        if i == 1 then
            -- Anchor rightmost dot first, then chain left-to-right
            dot:SetPoint("RIGHT", f.directorBanner, "TOPRIGHT",
                -((DOT_SIZE + DOT_GAP) * 2) - 20, -(DOT_SIZE / 2) - 6)
        else
            dot:SetPoint("LEFT", f.directorDots[i - 1], "RIGHT", DOT_GAP, 0)
        end
        dot:Hide()
        f.directorDots[i] = dot
    end

    -- Attuned (Final stage) red background tint — shown only when stage == 3
    -- C_RED is defined at the top of this file: local C_RED = { r=0.93, g=0.27, b=0.17 }
    f.directorAttunedOverlay = f.directorBanner:CreateTexture(nil, "BACKGROUND")
    f.directorAttunedOverlay:SetAllPoints()
    f.directorAttunedOverlay:SetTexture("Interface\\Buttons\\WHITE8x8")
    f.directorAttunedOverlay:SetVertexColor(C_RED.r * 0.18, C_RED.g * 0.02, C_RED.b * 0.02, 0.45)
    f.directorAttunedOverlay:Hide()

    -- Dismiss/snooze button (top-right X)
    f.directorDismissBtn = CreateFrame("Button", nil, f.directorBanner)
    f.directorDismissBtn:SetSize(14, 14)
    f.directorDismissBtn:SetPoint("TOPRIGHT", -4, -4)
    f.directorDismissBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    f.directorDismissBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
    f.directorDismissBtn:SetScript("OnClick", function()
        if f.currentDirectorTaskTitle then
            Topnight:SnoozeTask(f.currentDirectorTaskTitle)
            f.directorIndex = 1
            Topnight:RefreshControlPanel()
        end
    end)
    f.directorDismissBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Dismiss", C_RED.r, C_RED.g, C_RED.b)
        GameTooltip:AddLine("Snooze this suggestion until weekly reset.", C_GRAY.r, C_GRAY.g, C_GRAY.b)
        GameTooltip:Show()
    end)
    f.directorDismissBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Navigation: left arrow
    f.directorPrevBtn = CreateFrame("Button", nil, f.directorBanner)
    f.directorPrevBtn:SetSize(14, 14)
    f.directorPrevBtn:SetPoint("BOTTOMLEFT", 6, 4)
    f.directorPrevBtn.text = f.directorPrevBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.directorPrevBtn.text:SetPoint("CENTER")
    f.directorPrevBtn.text:SetText("|cff9CA3AF<|r")
    f.directorPrevBtn:SetScript("OnClick", function()
        if Topnight.ProgressionTasks and #Topnight.ProgressionTasks > 1 then
            f.directorIndex = f.directorIndex - 1
            if f.directorIndex < 1 then f.directorIndex = #Topnight.ProgressionTasks end
            Topnight:UpdateDirectorDisplay()
        end
    end)
    f.directorPrevBtn:SetScript("OnEnter", function(self) self.text:SetText("|cffE2E8F0<|r") end)
    f.directorPrevBtn:SetScript("OnLeave", function(self) self.text:SetText("|cff9CA3AF<|r") end)

    -- Navigation: page indicator
    f.directorPageText = f.directorBanner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.directorPageText:SetPoint("BOTTOM", 0, 6)
    f.directorPageText:SetText("|cff6B72801 of 1|r")

    -- Navigation: right arrow
    f.directorNextBtn = CreateFrame("Button", nil, f.directorBanner)
    f.directorNextBtn:SetSize(14, 14)
    f.directorNextBtn:SetPoint("BOTTOMRIGHT", -6, 4)
    f.directorNextBtn.text = f.directorNextBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.directorNextBtn.text:SetPoint("CENTER")
    f.directorNextBtn.text:SetText("|cff9CA3AF>|r")
    f.directorNextBtn:SetScript("OnClick", function()
        if Topnight.ProgressionTasks and #Topnight.ProgressionTasks > 1 then
            f.directorIndex = f.directorIndex + 1
            if f.directorIndex > #Topnight.ProgressionTasks then f.directorIndex = 1 end
            Topnight:UpdateDirectorDisplay()
        end
    end)
    f.directorNextBtn:SetScript("OnEnter", function(self) self.text:SetText("|cffE2E8F0>|r") end)
    f.directorNextBtn:SetScript("OnLeave", function(self) self.text:SetText("|cff9CA3AF>|r") end)

    -- Clickable action overlay (doesn't cover arrows or dismiss)
    f.directorActionBtn = CreateFrame("Button", nil, f.directorBanner)
    f.directorActionBtn:SetPoint("TOPLEFT", 0, 0)
    f.directorActionBtn:SetPoint("RIGHT", f.directorDismissBtn, "LEFT", -2, 0)
    f.directorActionBtn:SetPoint("BOTTOM", f.directorPrevBtn, "TOP", 0, 2)
    f.directorActionBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    f.directorActionBtn:SetScript("OnClick", function()
        if f.currentDirectorAction then
            f.currentDirectorAction()
        end
    end)
    f.directorActionBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Progression Director", C_ACCENT.r, C_ACCENT.g, C_ACCENT.b)
        GameTooltip:AddLine("Click to open relevant UI.", C_GRAY.r, C_GRAY.g, C_GRAY.b)
        GameTooltip:Show()
    end)
    f.directorActionBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    y = y - 80

    -- Teleport Home button
    f.homeBtn = CreateFrame("Button", nil, f.body, "BackdropTemplate")
    f.homeBtn:SetSize(barWidth, 26)
    f.homeBtn:SetPoint("TOPLEFT", 10, y)
    Topnight:CreateBackdrop(f.homeBtn, { r = C_PURPLE.r * 0.25, g = C_PURPLE.g * 0.25, b = C_PURPLE.b * 0.25, a = 0.9 })
    f.homeBtn.text = f.homeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.homeBtn.text:SetPoint("CENTER")
    f.homeBtn.text:SetText("|cffE2E8F0Open Housing UI|r")
    f.homeBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    f.homeBtn:SetScript("OnClick", function()
        Topnight:TeleportHome()
    end)
    f.homeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Teleport Home", C_WHITE.r, C_WHITE.g, C_WHITE.b)
        GameTooltip:AddLine("Click to teleport to your house.", C_GRAY.r, C_GRAY.g, C_GRAY.b)
        GameTooltip:Show()
    end)
    f.homeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - 38

    -- House Level + Favor bar
    f.favorBar = CreateMiniBar(f.body, barWidth, 10, y, "|cff9CA3AFHouse Level|r")
    y = y - 38

    -- Collection progress
    f.collectionBar = CreateMiniBar(f.body, barWidth, 10, y, "|cff9CA3AFDecor Collected|r")
    y = y - 38

    -- Shopping list count
    f.shoppingLabel = f.body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.shoppingLabel:SetPoint("TOPLEFT", 10, y)
    f.shoppingLabel:SetTextColor(C_GRAY.r, C_GRAY.g, C_GRAY.b)
    y = y - 24

    -- Quick action buttons row 1
    f.actionRow = CreateFrame("Frame", nil, f.body)
    f.actionRow:SetSize(barWidth, 22)
    f.actionRow:SetPoint("TOPLEFT", 10, y)

    -- Collection button
    f.collBtn = CreateFrame("Button", nil, f.actionRow, "BackdropTemplate")
    f.collBtn:SetSize((barWidth - 4) / 2, 22)
    f.collBtn:SetPoint("LEFT", 0, 0)
    Topnight:CreateBackdrop(f.collBtn, { r = 0.1, g = 0.1, b = 0.14, a = 0.8 })
    f.collBtn.text = f.collBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.collBtn.text:SetPoint("CENTER")
    f.collBtn.text:SetText("|cff60A5FATracker|r")
    f.collBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    f.collBtn:SetScript("OnClick", function() Topnight:ToggleCollectionTracker() end)

    -- Shopping button
    f.shopBtn = CreateFrame("Button", nil, f.actionRow, "BackdropTemplate")
    f.shopBtn:SetSize((barWidth - 4) / 2, 22)
    f.shopBtn:SetPoint("LEFT", f.collBtn, "RIGHT", 4, 0)
    Topnight:CreateBackdrop(f.shopBtn, { r = 0.1, g = 0.1, b = 0.14, a = 0.8 })
    f.shopBtn.text = f.shopBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.shopBtn.text:SetPoint("CENTER")
    f.shopBtn.text:SetText("|cffF59E0BShopping|r")
    f.shopBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    f.shopBtn:SetScript("OnClick", function() Topnight:ToggleShoppingList() end)

    y = y - 26

    -- Quick action buttons row 2
    f.actionRow2 = CreateFrame("Frame", nil, f.body)
    f.actionRow2:SetSize(barWidth, 22)
    f.actionRow2:SetPoint("TOPLEFT", 10, y)

    -- Teleport button
    f.tpBtn = CreateFrame("Button", nil, f.actionRow2, "BackdropTemplate")
    f.tpBtn:SetSize((barWidth - 4) / 2, 22)
    f.tpBtn:SetPoint("LEFT", 0, 0)
    Topnight:CreateBackdrop(f.tpBtn, { r = 0.1, g = 0.14, b = 0.1, a = 0.8 })
    f.tpBtn.text = f.tpBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.tpBtn.text:SetPoint("CENTER")
    f.tpBtn.text:SetText("|cff22C55EHome|r")
    f.tpBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    f.tpBtn:SetScript("OnClick", function()
        Topnight:TeleportHome()
    end)
    -- OnUpdate will handle the cooldown timer overlay
    f.tpBtn:SetScript("OnUpdate", function(self, elapsed)
        if C_Housing and C_Housing.GetVisitCooldownInfo then
            local cdInfo = C_Housing.GetVisitCooldownInfo()
            if cdInfo and cdInfo.duration and cdInfo.duration > 0 and cdInfo.startTime then
                local remaining = (cdInfo.startTime + cdInfo.duration) - GetTime()
                if remaining > 0 then
                    local mins = math.floor(remaining / 60)
                    local secs = math.floor(remaining % 60)
                    self.text:SetText(string.format("|cffEF4444%d:%02d|r", mins, secs))
                    self:SetAlpha(0.6)
                    return
                end
            end
        end
        self.text:SetText("|cff22C55EHome|r")
        self:SetAlpha(1.0)
    end)
    
    -- Scan button
    f.scanBtn = CreateFrame("Button", nil, f.actionRow2, "BackdropTemplate")
    f.scanBtn:SetSize((barWidth - 4) / 2, 22)
    f.scanBtn:SetPoint("LEFT", f.tpBtn, "RIGHT", 4, 0)
    Topnight:CreateBackdrop(f.scanBtn, { r = 0.1, g = 0.1, b = 0.14, a = 0.8 })
    f.scanBtn.text = f.scanBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.scanBtn.text:SetPoint("CENTER")
    f.scanBtn.text:SetText("|cff9CA3AFScan|r")
    f.scanBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    f.scanBtn:SetScript("OnClick", function()
        Topnight:PrintInfo("Scanning decor catalog...")
        Topnight:ScanCatalog()
    end)

    y = y - 30

    -- Divider line
    local divider = f.body:CreateTexture(nil, "ARTWORK")
    divider:SetSize(barWidth, 1)
    divider:SetPoint("TOPLEFT", 10, y)
    divider:SetTexture("Interface\\Buttons\\WHITE8x8")
    divider:SetVertexColor(C_PURPLE.r, C_PURPLE.g, C_PURPLE.b, 0.2)
    y = y - 6

    -- =======================================================================
    -- COLLAPSIBLE SECTIONS
    -- =======================================================================
    f.sectionAnchorY = y  -- remember where collapsible sections begin
    f.panelSections = {}  -- ordered list of section metadata

    -- Helper: create a collapsible section header button
    local function CreateSectionHeader(parent, sectionKey, label)
        local header = CreateFrame("Button", nil, parent)
        header:SetSize(barWidth, 16)
        header.sectionKey = sectionKey

        header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header.text:SetPoint("LEFT", 0, 0)
        
        local collapsed = Topnight.db and Topnight.db.collapsedSections and Topnight.db.collapsedSections[sectionKey]
        header.text:SetText(string.format("|cff9CA3AF%s %s|r", collapsed and "[+]" or "[-]", label))

        header:SetScript("OnClick", function(self)
            if not Topnight.db then return end
            Topnight.db.collapsedSections = Topnight.db.collapsedSections or {}
            local isCollapsed = Topnight.db.collapsedSections[sectionKey]
            Topnight.db.collapsedSections[sectionKey] = not isCollapsed
            Topnight:RelayoutSections()
        end)
        header:SetScript("OnEnter", function(self)
            self.text:SetTextColor(C_WHITE.r, C_WHITE.g, C_WHITE.b)
        end)
        header:SetScript("OnLeave", function(self)
            self.text:SetTextColor(C_GRAY.r, C_GRAY.g, C_GRAY.b)
        end)

        return header
    end

    -- ----- Section 1: Quick Wins -----
    local qwHeader = CreateSectionHeader(f.body, "QuickWins", "Quick Wins")
    f.qwHeader = qwHeader

    local qwContainer = CreateFrame("Frame", nil, f.body)
    qwContainer:SetSize(barWidth, (5 * 14) + 4)
    f.qwContainer = qwContainer

    f.qwBtns = {}
    for i = 1, 5 do
        local btn = CreateFrame("Button", nil, qwContainer)
        btn:SetSize(barWidth - 4, 14)
        btn:SetPoint("TOPLEFT", 2, -(i - 1) * 14)
        
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.label:SetPoint("LEFT", 0, 0)
        btn.label:SetTextColor(C_GRAY.r, C_GRAY.g, C_GRAY.b)
        btn.label:SetWidth(barWidth - 4)
        btn.label:SetJustifyH("LEFT")
        btn.label:SetWordWrap(false)
        
        btn:SetScript("OnEnter", function(self)
            self.label:SetTextColor(C_WHITE.r, C_WHITE.g, C_WHITE.b)
            if self.entryID and self.itemName then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.itemName, C_ACCENT.r, C_ACCENT.g, C_ACCENT.b)
                if self.itemSource then
                    GameTooltip:AddLine(self.itemSource, 1, 1, 1, true)
                end
                GameTooltip:AddLine("\n|cff22C55EClick to add to Shopping List|r")
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function(self)
            self.label:SetTextColor(C_GRAY.r, C_GRAY.g, C_GRAY.b)
            GameTooltip:Hide()
        end)
        btn:SetScript("OnClick", function(self)
            if self.entryID then
                Topnight:AddToShoppingList(self.entryID)
                Topnight:RefreshControlPanel()
            end
        end)

        f.qwBtns[i] = btn
    end

    table.insert(f.panelSections, { key = "QuickWins", header = qwHeader, container = qwContainer, contentHeight = (5 * 14) + 4 })

    -- ----- Section 1.5: Economy Hustles -----
    local ecoHeader = CreateSectionHeader(f.body, "EconomyHustles", "Economy Hustles")
    f.ecoHeader = ecoHeader

    local ecoContainer = CreateFrame("Frame", nil, f.body)
    ecoContainer:SetSize(barWidth, (3 * 22) + 4)
    f.ecoContainer = ecoContainer

    f.ecoRows = {}
    for i = 1, 3 do
        local row = CreateFrame("Frame", nil, ecoContainer, "BackdropTemplate")
        row:SetSize(barWidth - 4, 20)
        row:SetPoint("TOPLEFT", 2, -(i - 1) * 22)
        Topnight:CreateBackdrop(row, { r = 0.1, g = 0.1, b = 0.14, a = 0.6 })

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", 2, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        label:SetWidth(110)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetTextColor(C_WHITE.r, C_WHITE.g, C_WHITE.b)

        local value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        value:SetPoint("RIGHT", -4, 0)
        value:SetJustifyH("RIGHT")

        row.icon = icon
        row.label = label
        row.valueText = value
        f.ecoRows[i] = row
    end

    table.insert(f.panelSections, { key = "EconomyHustles", header = ecoHeader, container = ecoContainer, contentHeight = (3 * 22) + 4 })

    -- ----- Section 2: Favor Sources -----
    local favHeader = CreateSectionHeader(f.body, "FavorSources", "Favor Sources")
    f.favorHeader = favHeader

    local favContainer = CreateFrame("Frame", nil, f.body)
    favContainer:SetSize(barWidth, (4 * 14) + 4)
    f.favContainer = favContainer

    f.favorRows = {}
    for i = 1, 4 do
        local row = favContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row:SetPoint("TOPLEFT", 4, -(i - 1) * 14)
        row:SetWidth(barWidth - 14)
        row:SetJustifyH("LEFT")
        row:SetText("")
        f.favorRows[i] = row
    end

    table.insert(f.panelSections, { key = "FavorSources", header = favHeader, container = favContainer, contentHeight = (4 * 14) + 4 })

    -- ----- Section 3: Estate Roster -----
    local rosterHeaderBtn = CreateSectionHeader(f.body, "EstateRoster", "Estate Roster")
    f.rosterHeaderBtn = rosterHeaderBtn

    local rosterContainer = CreateFrame("Frame", nil, f.body)
    rosterContainer:SetSize(barWidth, 80)
    f.rosterContainer = rosterContainer
    
    f.rosterText = rosterContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.rosterText:SetPoint("TOPLEFT", 0, 0)
    f.rosterText:SetWidth(barWidth)
    f.rosterText:SetJustifyH("LEFT")
    f.rosterText:SetJustifyV("TOP")
    f.rosterText:SetText("|cff6B7280No alts tracked yet.|r")

    table.insert(f.panelSections, { key = "EstateRoster", header = rosterHeaderBtn, container = rosterContainer, contentHeight = 80 })

    -- ----- Section 4: Endeavors -----
    local endHeader = CreateSectionHeader(f.body, "Endeavors", "Endeavors")
    f.endHeader = endHeader

    local endContainer = CreateFrame("Frame", nil, f.body)
    local endContentHeight = (4 * 14) + 18  -- 4 task rows + timer row
    endContainer:SetSize(barWidth, endContentHeight)
    f.endContainer = endContainer

    f.endRows = {}
    for i = 1, 4 do
        local row = endContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row:SetPoint("TOPLEFT", 4, -(i - 1) * 14)
        row:SetWidth(barWidth - 14)
        row:SetJustifyH("LEFT")
        row:SetText("")
        f.endRows[i] = row
    end

    f.endTimerText = endContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.endTimerText:SetPoint("TOPLEFT", 4, -(4 * 14) - 2)
    f.endTimerText:SetWidth(barWidth - 14)
    f.endTimerText:SetJustifyH("LEFT")
    f.endTimerText:SetTextColor(C_GRAY.r, C_GRAY.g, C_GRAY.b)
    f.endTimerText:SetText("")

    table.insert(f.panelSections, { key = "Endeavors", header = endHeader, container = endContainer, contentHeight = endContentHeight })

    controlPanel = f
    return f
end

-- ---------------------------------------------------------------------------
-- Section Relayout (dynamic positioning for collapsible sections)
-- ---------------------------------------------------------------------------

function Topnight:RelayoutSections()
    if not controlPanel or not controlPanel.panelSections then return end
    
    local y = controlPanel.sectionAnchorY or -288
    local collapsedSections = self.db and self.db.collapsedSections or {}
    local barWidth = PANEL_WIDTH - 20
    local HEADER_HEIGHT = 16
    local SECTION_GAP = 6

    for _, section in ipairs(controlPanel.panelSections) do
        local isCollapsed = collapsedSections[section.key]
        
        -- Update header text with toggle indicator
        local label = section.key == "QuickWins" and "Quick Wins"
            or section.key == "EconomyHustles" and "Economy Hustles"
            or section.key == "FavorSources" and "Favor Sources"
            or section.key == "EstateRoster" and "Estate Roster"
            or section.key
        section.header.text:SetText(string.format("|cff9CA3AF%s %s|r", isCollapsed and "[+]" or "[-]", label))
        
        -- Position header
        section.header:ClearAllPoints()
        section.header:SetPoint("TOPLEFT", 10, y)
        y = y - HEADER_HEIGHT
        
        -- Show/hide container
        if isCollapsed then
            section.container:Hide()
        else
            section.container:ClearAllPoints()
            section.container:SetPoint("TOPLEFT", 12, y)
            section.container:Show()
            y = y - section.contentHeight
        end
        
        y = y - SECTION_GAP
    end

    -- Resize the panel to fit content (28px title bar + content below)
    local totalHeight = 28 + math.abs(y) + 10
    if not isCollapsed then
        controlPanel:SetHeight(totalHeight)
    end
end

-- ---------------------------------------------------------------------------
-- Layout Update (expand/collapse entire panel)
-- ---------------------------------------------------------------------------

function Topnight:UpdateControlPanelLayout()
    if not controlPanel then return end

    if isCollapsed then
        controlPanel:SetHeight(PANEL_COLLAPSED)
        controlPanel.body:Hide()
    else
        controlPanel.body:Show()
        self:RelayoutSections()
    end
end

-- Dot fill colors per lit stage (normalized floats, matching C_* constants)
local PREY_DOT_COLORS = {
    { r = 0.78, g = 0.20, b = 0.20, a = 0.6 },  -- dot 1 (Warm)
    { r = 0.86, g = 0.16, b = 0.16, a = 0.8 },  -- dot 2 (Hot)
    { r = 0.80, g = 0.13, b = 0.13, a = 1.0 },  -- dot 3 (Final)
}
local PREY_DOT_EMPTY = { r = 1.0, g = 1.0, b = 1.0, a = 0.08 }

local function UpdateDirectorDots(panel, stage)
    local dots = panel.directorDots
    if not dots then return end

    for i = 1, 3 do
        local dot = dots[i]
        if not dot then break end
        dot:Show()
        if i <= stage then
            local c = PREY_DOT_COLORS[i]
            dot:SetVertexColor(c.r, c.g, c.b, c.a)
        else
            dot:SetVertexColor(PREY_DOT_EMPTY.r, PREY_DOT_EMPTY.g, PREY_DOT_EMPTY.b, PREY_DOT_EMPTY.a)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Director Display (renders current index without re-evaluating)
-- ---------------------------------------------------------------------------

function Topnight:UpdateDirectorDisplay()
    if not controlPanel then return end
    
    local tasks = self.ProgressionTasks
    local total = tasks and #tasks or 0
    local idx = controlPanel.directorIndex or 1
    
    if total > 0 and idx >= 1 and idx <= total then
        local task = tasks[idx]
        controlPanel.directorTitle:SetText("|cffF59E0B> " .. task.title .. "|r")

        if task.stageIndicator then
            -- Prey task: render dots, hide description text
            controlPanel.directorDesc:SetText("")
            UpdateDirectorDots(controlPanel, task.stageIndicator.current)
            -- Attuned (stage 3) gets a red tint overlay
            if controlPanel.directorAttunedOverlay then
                if task.stageIndicator.current >= 3 then
                    controlPanel.directorAttunedOverlay:Show()
                else
                    controlPanel.directorAttunedOverlay:Hide()
                end
            end
        else
            -- Normal task: hide dots, show description text
            if controlPanel.directorDots then
                for _, dot in ipairs(controlPanel.directorDots) do dot:Hide() end
            end
            if controlPanel.directorAttunedOverlay then
                controlPanel.directorAttunedOverlay:Hide()
            end
            controlPanel.directorDesc:SetText("|cffE2E8F0" .. (task.description or "") .. "|r")
        end

        controlPanel.currentDirectorAction = task.action
        controlPanel.currentDirectorTaskTitle = task.title
        controlPanel.directorDismissBtn:Show()
        controlPanel.directorPageText:SetText(string.format("|cff6B7280%d of %d|r", idx, total))
        
        -- Show/hide arrows based on task count
        if total > 1 then
            controlPanel.directorPrevBtn:Show()
            controlPanel.directorNextBtn:Show()
            controlPanel.directorPageText:Show()
        else
            controlPanel.directorPrevBtn:Hide()
            controlPanel.directorNextBtn:Hide()
            controlPanel.directorPageText:Hide()
        end
    else
        controlPanel.directorTitle:SetText("|cffF59E0B> All Done|r")
        controlPanel.directorDesc:SetText("|cff6B7280All weekly tasks completed!|r")
        if controlPanel.directorDots then
            for _, dot in ipairs(controlPanel.directorDots) do dot:Hide() end
        end
        if controlPanel.directorAttunedOverlay then
            controlPanel.directorAttunedOverlay:Hide()
        end
        controlPanel.currentDirectorAction = nil
        controlPanel.currentDirectorTaskTitle = nil
        controlPanel.directorDismissBtn:Hide()
        controlPanel.directorPrevBtn:Hide()
        controlPanel.directorNextBtn:Hide()
        controlPanel.directorPageText:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Data Refresh
-- ---------------------------------------------------------------------------

function Topnight:RefreshControlPanel()
    if not controlPanel or not controlPanel:IsShown() then return end
    if isCollapsed then return end

    -- ==========================================================
    -- Progression Director
    -- ==========================================================
    if self.EvaluateProgressionTasks then
        self:EvaluateProgressionTasks()
        
        -- Clamp index to valid range after re-evaluation (tasks may have changed)
        local total = self.ProgressionTasks and #self.ProgressionTasks or 0
        if total == 0 then
            controlPanel.directorIndex = 1
        elseif controlPanel.directorIndex > total then
            controlPanel.directorIndex = total
        end
        
        self:UpdateDirectorDisplay()
    end

    -- Location awareness
    local inHouse = C_Housing and C_Housing.IsInsideOwnHouse and C_Housing.IsInsideOwnHouse()
    if inHouse then
        controlPanel.locationDot:SetVertexColor(C_GREEN.r, C_GREEN.g, C_GREEN.b)
    else
        controlPanel.locationDot:SetVertexColor(C_GRAY.r, C_GRAY.g, C_GRAY.b, 0.5)
    end

    -- House level & favor (Relies on globally cached data from PLAYER_HOUSE_LIST_UPDATED)
    local favorOk, favorErr = pcall(function()
        if not Topnight.houseLevelData then
            controlPanel.favorBar.label:SetText("|cff9CA3AFHouse Level|r")
            controlPanel.favorBar:SetProgress(0, 1, C_GRAY)
            controlPanel.favorBar.value:SetText("Loading...")
            return
        end
        
        if Topnight.houseLevelData.noHouse then
            controlPanel.favorBar.label:SetText("|cff9CA3AFHouse Level|r")
            controlPanel.favorBar:SetProgress(0, 1, C_GRAY)
            controlPanel.favorBar.value:SetText("No house")
            return
        end

        local currentLevel = Topnight.houseLevelData.level or 1
        local currentFavor = Topnight.houseLevelData.favor or 0
        local nextLevelFavor = Topnight.houseLevelData.nextFavor or 100

        controlPanel.favorBar.label:SetText("|cff9CA3AFHouse Level " .. currentLevel .. "|r")
        controlPanel.favorBar:SetProgress(currentFavor, nextLevelFavor, C_PURPLE)
    end)

    if not favorOk then
        controlPanel.favorBar.label:SetText("|cff9CA3AFHouse Level|r")
        controlPanel.favorBar:SetProgress(0, 1, C_GRAY)
        controlPanel.favorBar.value:SetText("N/A")
        Topnight:Debug("Favor bar error: " .. tostring(favorErr))
    end

    -- Collection stats
    if self.collectionReady then
        local stats = self:GetCollectionStats()
        controlPanel.collectionBar:SetProgress(stats.owned, stats.total, C_ACCENT)
    else
        controlPanel.collectionBar:SetProgress(0, 1, C_GRAY)
        controlPanel.collectionBar.value:SetText("Scanning...")
    end

    -- Shopping list count
    local shopCount = 0
    if self.db and self.db.shoppingList then
        for _ in pairs(self.db.shoppingList) do
            shopCount = shopCount + 1
        end
    end
    controlPanel.shoppingLabel:SetText(
        string.format("|cff9CA3AFShopping List:|r  |cffF59E0B%d|r |cff9CA3AFitem%s|r",
            shopCount, shopCount == 1 and "" or "s"))

    -- Quick Wins
    local quickWins = self:GetQuickWins(5)
    for i = 1, 5 do
        local btn = controlPanel.qwBtns[i]
        local item = quickWins[i]
        
        if item then
            btn.entryID = item.entryID
            btn.itemName = item.name
            btn.itemSource = item.sourceText or "Unknown Source"
            
            -- Format cost or source briefly
            local extra = ""
            if item.costValue and item.costValue > 0 and item.costValue < 99999999 then
                extra = " |cffF59E0B(" .. item.costValue .. "g)|r"
            elseif item.sourceType == "VENDOR" then
                extra = " |cff6B7280(Vendor)|r"
            elseif item.sourceType == "QUEST" then
                extra = " |cff6B7280(Quest)|r"
            end
            
            btn.label:SetText(string.format("|cff22C55E+|r %s%s", item.name, extra))
            btn:Show()
        else
            btn.entryID = nil
            btn.itemName = nil
            btn.itemSource = nil
            btn:Hide()
        end
    end

    -- Economy Hustles
    if controlPanel.ecoRows and self.GetEconomyQuickWins then
        local hustles = self:GetEconomyQuickWins(3)
        for i = 1, 3 do
            local row = controlPanel.ecoRows[i]
            local item = hustles[i]
            if item then
                row.icon:SetTexture(item.icon)
                row.label:SetText(item.link or "Unknown Item")
                if item.profit > 10000 then -- more than 1g
                    local profitG = math.floor(item.profit / 10000)
                    row.valueText:SetText(string.format("|cffF59E0B+%dg|r AH", profitG))
                else
                    row.valueText:SetText("|cff22C55ESell to AH|r")
                end
                
                row:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(item.link)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Vendor Price: " .. GetCoinTextureString(item.vendorTotal), C_WHITE.r, C_WHITE.g, C_WHITE.b)
                    GameTooltip:AddLine("AH Price: " .. GetCoinTextureString(item.ahTotal), C_ACCENT.r, C_ACCENT.g, C_ACCENT.b)
                    GameTooltip:AddLine("Profit: " .. GetCoinTextureString(item.profit), C_GREEN.r, C_GREEN.g, C_GREEN.b)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                row:Show()
            else
                row:Hide()
            end
        end
    end

    -- Favor Sources
    if controlPanel.favorRows and self.GetFavorSources then
        local sources = self:GetFavorSources()
        for i = 1, 4 do
            local row = controlPanel.favorRows[i]
            local src = sources[i]
            if src then
                local checkbox
                if not src.hasQuestID then
                    checkbox = "|cffF59E0B[?]|r"
                elseif src.completed then
                    checkbox = "|cff22C55E[x]|r"
                else
                    checkbox = "|cff6B7280[ ]|r"
                end
                row:SetText(string.format("%s %s |cff9CA3AF(+%d)|r", checkbox, src.name, src.favorAmount))
            else
                row:SetText("")
            end
        end
    end

    -- Estate Roster
    if controlPanel.rosterText then
        if self.db and self.db.alts then
            local rosterStr = ""
            local count = 0
            for altName, altData in pairs(self.db.alts) do
                local cleanName = altName:match("([^-]+)") or altName
                local colorStr = "|cffCCCCCC"
                if altData.class then
                    local color = RAID_CLASS_COLORS[altData.class]
                    if color then colorStr = "|c" .. color.colorStr end
                end
                local levelText = "|cff9CA3AFLvl " .. (altData.level or 1) .. "|r"
                local plotText = "|cff60A5FA" .. (altData.currentPlot or "None") .. "|r"
                
                rosterStr = rosterStr .. colorStr .. cleanName .. "|r  -  " .. levelText .. "  " .. plotText .. "\n"
                count = count + 1
            end
            if count > 0 then
                controlPanel.rosterText:SetText(rosterStr)
            else
                controlPanel.rosterText:SetText("|cff6B7280No alts tracked yet. Log into other characters.|r")
            end
        else
            controlPanel.rosterText:SetText("|cff6B7280Database not ready.|r")
        end
    end

    -- Endeavors
    if controlPanel.endRows then
        if self.IsEndeavorSystemAvailable and self:IsEndeavorSystemAvailable() then
            local tasks = self:GetEndeavorData()
            for i = 1, 4 do
                local row = controlPanel.endRows[i]
                local task = tasks[i]
                if task then
                    local checkbox
                    if task.completed then
                        checkbox = "|cff22C55E[x]|r"
                    else
                        checkbox = "|cff6B7280[ ]|r"
                    end
                    local progressText = string.format("|cff9CA3AF(%d/%d)|r", task.progress, task.threshold)
                    row:SetText(string.format("%s %s  %s", checkbox, task.name, progressText))
                else
                    row:SetText("")
                end
            end

            -- Reset timer
            local summary = self:GetEndeavorSummary()
            if summary.timeRemaining then
                controlPanel.endTimerText:SetText(
                    string.format("|cff9CA3AFResets in %s|r", self:FormatEndeavorTimeRemaining(summary.timeRemaining)))
            else
                controlPanel.endTimerText:SetText(
                    string.format("|cff9CA3AF%d/%d tasks done|r", summary.completedTasks, summary.totalTasks))
            end
        else
            controlPanel.endRows[1]:SetText("|cff6B7280Endeavors not available.|r")
            for i = 2, 4 do controlPanel.endRows[i]:SetText("") end
            controlPanel.endTimerText:SetText("|cff6B7280Unlock housing to track.|r")
        end
    end
end

-- ---------------------------------------------------------------------------
-- Time Formatting
-- ---------------------------------------------------------------------------

function Topnight:FormatTimeAgo(timestamp)
    if not timestamp then return "" end
    local diff = time() - timestamp
    if diff < 60 then
        return "just now"
    elseif diff < 3600 then
        return string.format("%dm ago", math.floor(diff / 60))
    elseif diff < 86400 then
        return string.format("%dh ago", math.floor(diff / 3600))
    else
        return string.format("%dd ago", math.floor(diff / 86400))
    end
end

-- ---------------------------------------------------------------------------
-- Toggle / Init
-- ---------------------------------------------------------------------------

function Topnight:ToggleControlPanel()
    local f = CreateControlPanel()
    if f:IsShown() then
        f:Hide()
        local settings = self:GetSetting("controlPanel")
        if settings then
            settings.show = false
            self:SetSetting("controlPanel", settings)
        end
    else
        f:Show()
        local settings = self:GetSetting("controlPanel")
        if settings then
            settings.show = true
            self:SetSetting("controlPanel", settings)
        end
        self:RefreshControlPanel()
    end
end

function Topnight:ShowControlPanel()
    local f = CreateControlPanel()
    if not f:IsShown() then
        f:Show()
        local settings = self:GetSetting("controlPanel")
        if settings then
            settings.show = true
            self:SetSetting("controlPanel", settings)
        end
        self:RefreshControlPanel()
    end
end

function Topnight:InitControlPanel()
    local settings = self:GetSetting("controlPanel")

    -- Create the panel
    local f = CreateControlPanel()

    -- Restore collapsed state
    isCollapsed = settings and settings.collapsed or false
    self:UpdateControlPanelLayout()

    -- Show on login if previously visible
    if settings and settings.show then
        f:Show()
        self:RefreshControlPanel()
    else
        f:Hide()
    end

    -- Register for Housing data updates
    self:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED", function(_, _, houseInfoList)
        Topnight.houseLevelData = Topnight.houseLevelData or {}
        if houseInfoList and houseInfoList[1] then
            Topnight.houseLevelData.noHouse = false
            local houseGUID = houseInfoList[1].houseGUID
            if C_Housing and C_Housing.GetCurrentHouseLevelFavor then
                C_Housing.GetCurrentHouseLevelFavor(houseGUID)
            end
        else
            Topnight.houseLevelData.noHouse = true
            Topnight:RefreshControlPanel()
        end
    end)

    self:RegisterEvent("HOUSE_LEVEL_FAVOR_UPDATED", function(_, _, favorData)
        if not favorData then return end
        
        -- The API returns the actual Level and the favor amount
        Topnight.houseLevelData = Topnight.houseLevelData or {}
        Topnight.houseLevelData.level = favorData.houseLevel or 1
        Topnight.houseLevelData.favor = favorData.houseFavor or 0

        -- Query for max favor needed for the NEXT level
        if C_Housing and C_Housing.GetHouseLevelFavorForLevel then
            Topnight.houseLevelData.nextFavor = C_Housing.GetHouseLevelFavorForLevel(Topnight.houseLevelData.level + 1) or 100
        end

        Topnight:RefreshControlPanel()
    end)

    -- Register for data updates
    self:RegisterCallback("TOPNIGHT_COLLECTION_UPDATED", function()
        Topnight:RefreshControlPanel()
    end)
    self:RegisterCallback("TOPNIGHT_SHOPPING_LIST_UPDATED", function()
        Topnight:RefreshControlPanel()
    end)

    -- Periodic refresh timer
    updateTimer = C_Timer.NewTicker(UPDATE_INTERVAL, function()
        Topnight:RefreshControlPanel()
    end)

    -- Trigger initial load of house data from server
    if C_Housing and C_Housing.GetPlayerOwnedHouses then
        C_Housing.GetPlayerOwnedHouses()
    end

    self:Debug("Control Panel initialized.")
end

