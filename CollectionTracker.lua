-- =============================================================================
-- Topnight - CollectionTracker.lua
-- Feature 1: Decor Collection Tracker — scrollable category/item grid UI
-- =============================================================================

local ADDON_NAME, Topnight = ...

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
local PANEL_WIDTH  = 680
local PANEL_HEIGHT = 520
local ICON_SIZE    = 42
local ICON_SPACING = 4
local ICONS_PER_ROW = 12
local SIDEBAR_WIDTH = 170
local HEADER_HEIGHT = 70
local FILTER_HEIGHT = 36
local SEARCH_HEIGHT = 28

-- Colors matching Topnight branding
local C_PURPLE     = { r = 0.545, g = 0.361, b = 0.965 }
local C_DARK_BG    = { r = 0.08,  g = 0.08,  b = 0.12,  a = 0.92 }
local C_PANEL_BG   = { r = 0.10,  g = 0.10,  b = 0.15,  a = 0.95 }
local C_SIDEBAR_BG = { r = 0.07,  g = 0.07,  b = 0.10,  a = 0.98 }
local C_ACCENT     = { r = 0.376, g = 0.647, b = 0.980 }
local C_GREEN      = { r = 0.133, g = 0.773, b = 0.369 }
local C_GRAY       = { r = 0.45,  g = 0.45,  b = 0.50 }
local C_WHITE      = { r = 0.90,  g = 0.90,  b = 0.92 }
local C_DIM        = { r = 0.35,  g = 0.35,  b = 0.40 }

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local collectionFrame = nil
local selectedCategory = nil  -- nil = "All" view
local searchText = ""
local itemButtons = {}

-- ---------------------------------------------------------------------------
-- UI Helpers
-- ---------------------------------------------------------------------------


local function CreateProgressBar(parent, width, height)
    local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bar:SetSize(width, height)
    Topnight:CreateBackdrop(bar, { r = 0.05, g = 0.05, b = 0.08, a = 0.8 })

    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", 1, -1)
    bar.fill:SetHeight(height - 2)
    bar.fill:SetTexture("Interface\\Buttons\\WHITE8x8")

    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.text:SetPoint("CENTER")
    bar.text:SetTextColor(C_WHITE.r, C_WHITE.g, C_WHITE.b)

    function bar:SetProgress(current, total)
        local pct = total > 0 and (current / total) or 0
        local fillWidth = math.max(1, (width - 2) * pct)
        bar.fill:SetWidth(fillWidth)

        -- Color gradient: red -> yellow -> green based on progress
        if pct < 0.33 then
            bar.fill:SetVertexColor(0.9, 0.3, 0.2, 0.8)
        elseif pct < 0.66 then
            bar.fill:SetVertexColor(0.95, 0.75, 0.15, 0.8)
        else
            bar.fill:SetVertexColor(C_GREEN.r, C_GREEN.g, C_GREEN.b, 0.8)
        end

        bar.text:SetText(string.format("%d / %d  (%.1f%%)", current, total, pct * 100))
    end

    return bar
end

-- ---------------------------------------------------------------------------
-- Main Panel Construction
-- ---------------------------------------------------------------------------

local function CreateCollectionFrame()
    if collectionFrame then return collectionFrame end

    -- Main frame
    local f = CreateFrame("Frame", "TopnightCollectionFrame", UIParent, "BackdropTemplate")
    f:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    Topnight:CreateBackdrop(f, C_PANEL_BG)

    -- Make draggable from header area
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    -- Close on Escape
    table.insert(UISpecialFrames, "TopnightCollectionFrame")

    -- ========================= HEADER =========================
    f.header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.header:SetPoint("TOPLEFT", 0, 0)
    f.header:SetPoint("TOPRIGHT", 0, 0)
    f.header:SetHeight(HEADER_HEIGHT)
    Topnight:CreateBackdrop(f.header, { r = C_PURPLE.r * 0.3, g = C_PURPLE.g * 0.3, b = C_PURPLE.b * 0.3, a = 0.95 })

    -- Title
    f.title = f.header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 14, -10)
    f.title:SetText("|cff8B5CF6Topnight|r  Decor Collection")
    f.title:SetTextColor(C_WHITE.r, C_WHITE.g, C_WHITE.b)

    -- Overall progress bar
    f.progressBar = CreateProgressBar(f.header, PANEL_WIDTH - 28, 18)
    f.progressBar:SetPoint("TOPLEFT", 14, -38)
    f.progressBar:SetProgress(0, 0)

    -- Close button
    f.closeBtn = CreateFrame("Button", nil, f.header)
    f.closeBtn:SetSize(20, 20)
    f.closeBtn:SetPoint("TOPRIGHT", -8, -8)
    f.closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    f.closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    f.closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- ========================= SIDEBAR =========================
    f.sidebar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.sidebar:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT)
    f.sidebar:SetPoint("BOTTOMLEFT", 0, 0)
    f.sidebar:SetWidth(SIDEBAR_WIDTH)
    Topnight:CreateBackdrop(f.sidebar, C_SIDEBAR_BG)

    -- "All" button
    f.allBtn = CreateFrame("Button", nil, f.sidebar, "BackdropTemplate")
    f.allBtn:SetSize(SIDEBAR_WIDTH - 8, 24)
    f.allBtn:SetPoint("TOPLEFT", 4, -6)
    Topnight:CreateBackdrop(f.allBtn, { r = C_PURPLE.r * 0.4, g = C_PURPLE.g * 0.4, b = C_PURPLE.b * 0.4, a = 0.8 })

    f.allBtn.text = f.allBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.allBtn.text:SetPoint("LEFT", 8, 0)
    f.allBtn.text:SetText("|cffFFFFFFAll Categories|r")

    f.allBtn:SetScript("OnClick", function()
        selectedCategory = nil
        Topnight:RefreshCollectionUI()
    end)

    -- Category button container (scrollable)
    f.catScroll = CreateFrame("ScrollFrame", nil, f.sidebar, "UIPanelScrollFrameTemplate")
    f.catScroll:SetPoint("TOPLEFT", 4, -34)
    f.catScroll:SetPoint("BOTTOMRIGHT", -22, 4)

    f.catContent = CreateFrame("Frame", nil, f.catScroll)
    f.catContent:SetWidth(SIDEBAR_WIDTH - 30)
    f.catContent:SetHeight(1) -- will resize
    f.catScroll:SetScrollChild(f.catContent)

    f.catButtons = {}

    -- ========================= FILTER BAR =========================
    local contentLeft = SIDEBAR_WIDTH
    local contentWidth = PANEL_WIDTH - SIDEBAR_WIDTH

    f.filterBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.filterBar:SetPoint("TOPLEFT", contentLeft, -HEADER_HEIGHT)
    f.filterBar:SetPoint("TOPRIGHT", 0, -HEADER_HEIGHT)
    f.filterBar:SetHeight(FILTER_HEIGHT)
    Topnight:CreateBackdrop(f.filterBar, { r = 0.06, g = 0.06, b = 0.09, a = 0.9 })

    -- Search box
    f.searchBox = CreateFrame("EditBox", "TopnightSearchBox", f.filterBar, "InputBoxTemplate")
    f.searchBox:SetSize(160, SEARCH_HEIGHT)
    f.searchBox:SetPoint("LEFT", 10, 0)
    f.searchBox:SetAutoFocus(false)
    f.searchBox:SetFontObject("ChatFontSmall")
    f.searchBox:SetTextInsets(4, 4, 0, 0)
    
    -- Placeholder text
    f.searchBox.Instructions = f.searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    f.searchBox.Instructions:SetPoint("LEFT", 4, 0)
    f.searchBox.Instructions:SetText("Search decor...")
    f.searchBox:SetScript("OnEditFocusGained", function(self) self.Instructions:Hide() end)
    f.searchBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then self.Instructions:Show() end
    end)

    local searchLabel = f.filterBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("RIGHT", f.searchBox, "LEFT", -4, 0)

    f.searchBox:SetScript("OnTextChanged", function(self)
        searchText = self:GetText() or ""
        Topnight:RefreshCollectionUI()
    end)
    f.searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- Filter buttons: Owned / Missing
    f.ownedBtn = CreateFrame("Button", nil, f.filterBar, "BackdropTemplate")
    f.ownedBtn:SetSize(60, 22)
    f.ownedBtn:SetPoint("LEFT", f.searchBox, "RIGHT", 12, 0)
    Topnight:CreateBackdrop(f.ownedBtn, { r = C_GREEN.r * 0.3, g = C_GREEN.g * 0.3, b = C_GREEN.b * 0.3, a = 0.8 })
    f.ownedBtn.text = f.ownedBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.ownedBtn.text:SetPoint("CENTER")
    f.ownedBtn.text:SetText("|cff22C55EOwned|r")
    f.ownedBtn:SetScript("OnClick", function()
        local filters = Topnight:GetSetting("collectionFilters")
        filters.showOwned = not filters.showOwned
        Topnight:SetSetting("collectionFilters", filters)
        Topnight:RefreshCollectionUI()
    end)

    f.missingBtn = CreateFrame("Button", nil, f.filterBar, "BackdropTemplate")
    f.missingBtn:SetSize(64, 22)
    f.missingBtn:SetPoint("LEFT", f.ownedBtn, "RIGHT", 6, 0)
    Topnight:CreateBackdrop(f.missingBtn, { r = 0.9 * 0.3, g = 0.3 * 0.3, b = 0.2 * 0.3, a = 0.8 })
    f.missingBtn.text = f.missingBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.missingBtn.text:SetPoint("CENTER")
    f.missingBtn.text:SetText("|cffEF4444Missing|r")
    f.missingBtn:SetScript("OnClick", function()
        local filters = Topnight:GetSetting("collectionFilters")
        filters.showMissing = not filters.showMissing
        Topnight:SetSetting("collectionFilters", filters)
        Topnight:RefreshCollectionUI()
    end)

    -- Sort dropdown label / button
    f.sortBtn = CreateFrame("Button", nil, f.filterBar, "BackdropTemplate")
    f.sortBtn:SetSize(120, 22)
    f.sortBtn:SetPoint("RIGHT", -10, 0)
    Topnight:CreateBackdrop(f.sortBtn, { r = 0.15, g = 0.15, b = 0.18, a = 0.8 })
    
    f.sortBtn.text = f.sortBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.sortBtn.text:SetPoint("CENTER", 0, 0)
    
    f.sortBtn:SetScript("OnClick", function()
        local filters = Topnight:GetSetting("collectionFilters")
        local current = filters.sortBy or "NAME"
        local nextSort = "NAME"
        
        if current == "NAME" then nextSort = "CATEGORY"
        elseif current == "CATEGORY" then nextSort = "SOURCE"
        elseif current == "SOURCE" then nextSort = "EASIEST"
        elseif current == "EASIEST" then nextSort = "CHEAPEST"
        elseif current == "CHEAPEST" then nextSort = "NAME"
        end

        filters.sortBy = nextSort
        Topnight:SetSetting("collectionFilters", filters)
        Topnight:RefreshCollectionUI()
    end)

    -- ========================= ITEM GRID =========================
    local gridTop = -(HEADER_HEIGHT + FILTER_HEIGHT)

    f.gridScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.gridScroll:SetPoint("TOPLEFT", contentLeft + 6, gridTop - 4)
    f.gridScroll:SetPoint("BOTTOMRIGHT", -24, 4)

    f.gridContent = CreateFrame("Frame", nil, f.gridScroll)
    f.gridContent:SetWidth(contentWidth - 36)
    f.gridContent:SetHeight(1)
    f.gridScroll:SetScrollChild(f.gridContent)

    collectionFrame = f
    f:Hide()
    return f
end

-- ---------------------------------------------------------------------------
-- Item Icon Button Creation
-- ---------------------------------------------------------------------------

local function CreateItemButton(parent, index)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    Topnight:CreateBackdrop(btn, { r = 0.12, g = 0.12, b = 0.16, a = 0.9 })

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 2, -2)
    btn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim icon edges

    btn.owned = btn:CreateTexture(nil, "OVERLAY")
    btn.owned:SetSize(14, 14)
    btn.owned:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.owned:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    btn.owned:Hide()

    -- Highlight on hover
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        if not self.itemData then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()

        local data = self.itemData
        if data.isOwned then
            GameTooltip:AddLine(data.name, C_GREEN.r, C_GREEN.g, C_GREEN.b)
            GameTooltip:AddLine("Collected", C_GREEN.r, C_GREEN.g, C_GREEN.b)
        else
            GameTooltip:AddLine(data.name, C_WHITE.r, C_WHITE.g, C_WHITE.b)
            GameTooltip:AddLine("Not Collected", C_GRAY.r, C_GRAY.g, C_GRAY.b)
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Category: " .. (data.categoryName or "Unknown"), C_ACCENT.r, C_ACCENT.g, C_ACCENT.b)

        -- Source info
        local srcInfo = data.sourceInfo
        local srcType = Topnight.SOURCE_TYPES[data.sourceType] or Topnight.SOURCE_TYPES.UNKNOWN
        GameTooltip:AddLine("Source: " .. srcType.label, C_PURPLE.r, C_PURPLE.g, C_PURPLE.b)

        if srcInfo then
            if srcInfo.npcName then
                GameTooltip:AddLine("  NPC: " .. srcInfo.npcName, C_DIM.r, C_DIM.g, C_DIM.b)
            end
            if srcInfo.zone then
                GameTooltip:AddLine("  Zone: " .. srcInfo.zone, C_DIM.r, C_DIM.g, C_DIM.b)
            end
            if srcInfo.questName then
                GameTooltip:AddLine("  Quest: " .. srcInfo.questName, C_DIM.r, C_DIM.g, C_DIM.b)
            end
            if srcInfo.sourceName then
                GameTooltip:AddLine("  Drops from: " .. srcInfo.sourceName, C_DIM.r, C_DIM.g, C_DIM.b)
            end
            if srcInfo.instanceName then
                GameTooltip:AddLine("  Instance: " .. srcInfo.instanceName, C_DIM.r, C_DIM.g, C_DIM.b)
            end
            if srcInfo.cost then
                GameTooltip:AddLine("  Cost: " .. srcInfo.cost, C_DIM.r, C_DIM.g, C_DIM.b)
            elseif data.costValue and data.costValue < 99999999 then
                GameTooltip:AddLine(string.format("  Detected Price: %d", data.costValue), C_YELLOW.r, C_YELLOW.g, C_YELLOW.b)
            end
            -- Show raw source text from the API if available
            if srcInfo.detail and not srcInfo.npcName and not srcInfo.questName and not srcInfo.sourceName then
                GameTooltip:AddLine("  " .. srcInfo.detail, C_DIM.r, C_DIM.g, C_DIM.b)
            end
        end

        if not data.isOwned then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Right-click to add to Shopping List", 0.7, 0.7, 0.3)
        end

        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Right-click to add to shopping list
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" and self.itemData and not self.itemData.isOwned then
            Topnight:AddToShoppingList(self.itemData.entryID)
            Topnight:RefreshCollectionUI()
        end
    end)

    return btn
end

-- ---------------------------------------------------------------------------
-- Refresh / Update Logic
-- ---------------------------------------------------------------------------

function Topnight:RefreshCollectionUI()
    if not collectionFrame or not collectionFrame:IsShown() then return end

    -- Update overall progress bar
    local stats = self:GetCollectionStats()
    collectionFrame.progressBar:SetProgress(stats.owned, stats.total)

    -- Update filter button appearance
    local filters = self:GetSetting("collectionFilters") or {}
    if filters.showOwned then
        Topnight:CreateBackdrop(collectionFrame.ownedBtn, { r = C_GREEN.r * 0.4, g = C_GREEN.g * 0.4, b = C_GREEN.b * 0.4, a = 0.9 })
    else
        Topnight:CreateBackdrop(collectionFrame.ownedBtn, { r = 0.15, g = 0.15, b = 0.18, a = 0.7 })
    end
    if filters.showMissing then
        Topnight:CreateBackdrop(collectionFrame.missingBtn, { r = 0.9 * 0.3, g = 0.3 * 0.3, b = 0.2 * 0.3, a = 0.9 })
    else
        Topnight:CreateBackdrop(collectionFrame.missingBtn, { r = 0.15, g = 0.15, b = 0.18, a = 0.7 })
    end

    -- Update sort label String mapping
    local sortStrings = {
        NAME = "Name",
        CATEGORY = "Category",
        SOURCE = "Unlock Type",
        EASIEST = "Easiest",
        CHEAPEST = "Cheapest",
    }
    local sortStr = sortStrings[filters.sortBy] or "Name"
    collectionFrame.sortBtn.text:SetText("|cff9CA3AFSort: " .. sortStr .. "|r")

    -- Rebuild category sidebar
    self:RefreshCategorySidebar()

    -- Rebuild item grid
    self:RefreshItemGrid(filters)
end

function Topnight:RefreshCategorySidebar()
    -- Clear old buttons
    for _, btn in ipairs(collectionFrame.catButtons) do
        btn:Hide()
    end

    local yOffset = 0
    local index = 0

    for _, catID in ipairs(self.categoryOrder) do
        local catData = self.categoryCache[catID]
        if catData then
            index = index + 1

            local btn = collectionFrame.catButtons[index]
            if not btn then
                btn = CreateFrame("Button", nil, collectionFrame.catContent, "BackdropTemplate")
                btn:SetSize(SIDEBAR_WIDTH - 30, 28)
                collectionFrame.catButtons[index] = btn

                btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                btn.text:SetPoint("LEFT", 6, 0)
                btn.text:SetWordWrap(false)
                btn.text:SetWidth(SIDEBAR_WIDTH - 80)
                btn.text:SetJustifyH("LEFT")

                btn.count = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                btn.count:SetPoint("RIGHT", -6, 0)

                btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
            end

            btn:SetPoint("TOPLEFT", 0, -yOffset)
            btn:Show()

            local isSelected = (selectedCategory == catID)
            if isSelected then
                Topnight:CreateBackdrop(btn, { r = C_PURPLE.r * 0.3, g = C_PURPLE.g * 0.3, b = C_PURPLE.b * 0.3, a = 0.9 })
            else
                Topnight:CreateBackdrop(btn, { r = 0.08, g = 0.08, b = 0.11, a = 0.5 })
            end

            btn.text:SetText(catData.name)
            btn.text:SetTextColor(isSelected and C_WHITE.r or C_GRAY.r,
                                  isSelected and C_WHITE.g or C_GRAY.g,
                                  isSelected and C_WHITE.b or C_GRAY.b)

            local pct = catData.numTotal > 0 and (catData.numOwned / catData.numTotal * 100) or 0
            btn.count:SetText(string.format("|cff9CA3AF%d/%d|r", catData.numOwned, catData.numTotal))

            btn.categoryID = catID
            btn:SetScript("OnClick", function(self)
                selectedCategory = self.categoryID
                Topnight:RefreshCollectionUI()
            end)

            yOffset = yOffset + 30
        end
    end

    collectionFrame.catContent:SetHeight(math.max(1, yOffset))

    -- Update "All" button styling
    if selectedCategory == nil then
        Topnight:CreateBackdrop(collectionFrame.allBtn, { r = C_PURPLE.r * 0.4, g = C_PURPLE.g * 0.4, b = C_PURPLE.b * 0.4, a = 0.9 })
    else
        Topnight:CreateBackdrop(collectionFrame.allBtn, { r = 0.12, g = 0.12, b = 0.16, a = 0.7 })
    end
end

function Topnight:RefreshItemGrid(filters)
    -- Hide all existing buttons
    for _, btn in ipairs(itemButtons) do
        btn:Hide()
    end

    -- Get filtered items
    local items = self:GetFilteredItems({
        categoryID  = selectedCategory,
        showOwned   = filters.showOwned ~= false,
        showMissing = filters.showMissing ~= false,
        sourceFilter = filters.sourceFilter or "ALL",
        sortBy      = filters.sortBy or "NAME",
        searchText  = searchText,
    })

    local gridWidth = collectionFrame.gridContent:GetWidth()
    local iconsPerRow = math.floor((gridWidth + ICON_SPACING) / (ICON_SIZE + ICON_SPACING))
    if iconsPerRow < 1 then iconsPerRow = 1 end

    local row, col = 0, 0

    for i, itemData in ipairs(items) do
        local btn = itemButtons[i]
        if not btn then
            btn = CreateItemButton(collectionFrame.gridContent, i)
            itemButtons[i] = btn
        end

        btn.itemData = itemData
        btn:SetPoint("TOPLEFT", col * (ICON_SIZE + ICON_SPACING), -(row * (ICON_SIZE + ICON_SPACING)))
        btn:Show()

        -- Set icon
        btn.icon:SetTexture(itemData.icon)

        -- Owned vs missing styling
        if itemData.isOwned then
            btn.icon:SetDesaturated(false)
            btn.icon:SetAlpha(1.0)
            btn.owned:Show()
            Topnight:CreateBackdrop(btn, { r = 0.1, g = 0.18, b = 0.1, a = 0.9 })
        else
            btn.icon:SetDesaturated(true)
            btn.icon:SetAlpha(0.5)
            btn.owned:Hide()
            Topnight:CreateBackdrop(btn, { r = 0.12, g = 0.12, b = 0.16, a = 0.7 })

            -- Highlight if on shopping list
            if self.db and self.db.shoppingList[itemData.entryID] then
                Topnight:CreateBackdrop(btn, { r = 0.3, g = 0.25, b = 0.05, a = 0.9 })
                btn.icon:SetAlpha(0.7)
            end
        end

        col = col + 1
        if col >= iconsPerRow then
            col = 0
            row = row + 1
        end
    end

    if #items == 0 then
        if not collectionFrame.gridContent.emptyText then
            local emptyText = collectionFrame.gridContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            emptyText:SetPoint("TOP", 0, -40)
            emptyText:SetJustifyH("CENTER")
            collectionFrame.gridContent.emptyText = emptyText
        end
        collectionFrame.gridContent.emptyText:SetText("|cff9CA3AFNo items found matching your filters.|r")
        collectionFrame.gridContent.emptyText:Show()
    else
        if collectionFrame.gridContent.emptyText then
            collectionFrame.gridContent.emptyText:Hide()
        end
    end

    local totalRows = math.ceil(#items / iconsPerRow)
    collectionFrame.gridContent:SetHeight(math.max(1, totalRows * (ICON_SIZE + ICON_SPACING)))
end

-- ---------------------------------------------------------------------------
-- Toggle / Init
-- ---------------------------------------------------------------------------

function Topnight:ToggleCollectionTracker()
    local f = CreateCollectionFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        self:RefreshCollectionUI()
    end
end

function Topnight:InitCollectionTracker()
    -- Register for collection updates
    self:RegisterCallback("TOPNIGHT_COLLECTION_UPDATED", function()
        Topnight:RefreshCollectionUI()
    end)

    self:Debug("Collection Tracker initialized.")
end

