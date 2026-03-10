-- =============================================================================
-- Topnight - ShoppingList.lua
-- Feature 2: Shopping List & Acquisition Planner
-- =============================================================================

local ADDON_NAME, Topnight = ...

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
local PANEL_WIDTH  = 440
local PANEL_HEIGHT = 480
local HEADER_HEIGHT = 55

local C_PURPLE     = { r = 0.545, g = 0.361, b = 0.965 }
local C_DARK_BG    = { r = 0.08,  g = 0.08,  b = 0.12,  a = 0.92 }
local C_PANEL_BG   = { r = 0.10,  g = 0.10,  b = 0.15,  a = 0.95 }
local C_GREEN      = { r = 0.133, g = 0.773, b = 0.369 }
local C_ACCENT     = { r = 0.376, g = 0.647, b = 0.980 }
local C_WHITE      = { r = 0.90,  g = 0.90,  b = 0.92 }
local C_GRAY       = { r = 0.45,  g = 0.45,  b = 0.50 }
local C_YELLOW     = { r = 0.96,  g = 0.78,  b = 0.15 }
local C_DIM        = { r = 0.60,  g = 0.60,  b = 0.60 }

-- Group icons for each source type
local GROUP_ICONS = {
    VENDOR      = "🏪",
    QUEST       = "📜",
    DROP        = "⚔️",
    PROFESSION  = "🔨",
    ACHIEVEMENT = "🏆",
    PVP         = "⚔️",
    UNKNOWN     = "❓",
}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local shoppingFrame = nil
local groupFrames = {}

-- ---------------------------------------------------------------------------
-- UI Helpers
-- ---------------------------------------------------------------------------


-- ---------------------------------------------------------------------------
-- Shopping List Panel
-- ---------------------------------------------------------------------------

local function CreateShoppingFrame()
    if shoppingFrame then return shoppingFrame end

    local f = CreateFrame("Frame", "TopnightShoppingFrame", UIParent, "BackdropTemplate")
    f:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    f:SetPoint("CENTER", 350, 0)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    Topnight:CreateBackdrop(f, C_PANEL_BG)

    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    table.insert(UISpecialFrames, "TopnightShoppingFrame")

    -- ========================= HEADER =========================
    f.header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.header:SetPoint("TOPLEFT", 0, 0)
    f.header:SetPoint("TOPRIGHT", 0, 0)
    f.header:SetHeight(HEADER_HEIGHT)
    Topnight:CreateBackdrop(f.header, { r = C_PURPLE.r * 0.25, g = C_PURPLE.g * 0.25, b = C_PURPLE.b * 0.25, a = 0.95 })

    f.title = f.header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 14, -10)
    f.title:SetText("|cff8B5CF6Topnight|r  Shopping List")
    f.title:SetTextColor(C_WHITE.r, C_WHITE.g, C_WHITE.b)

    f.subtitle = f.header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.subtitle:SetPoint("TOPLEFT", 14, -32)
    f.subtitle:SetText("0 items wanted")
    f.subtitle:SetTextColor(C_GRAY.r, C_GRAY.g, C_GRAY.b)

    -- Close button
    f.closeBtn = CreateFrame("Button", nil, f.header)
    f.closeBtn:SetSize(20, 20)
    f.closeBtn:SetPoint("TOPRIGHT", -8, -8)
    f.closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    f.closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    f.closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Clear all button
    f.clearBtn = CreateFrame("Button", nil, f.header, "BackdropTemplate")
    f.clearBtn:SetSize(70, 22)
    f.clearBtn:SetPoint("RIGHT", f.closeBtn, "LEFT", -10, 0)
    Topnight:CreateBackdrop(f.clearBtn, { r = 0.5, g = 0.15, b = 0.1, a = 0.7 })
    f.clearBtn.text = f.clearBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.clearBtn.text:SetPoint("CENTER")
    f.clearBtn.text:SetText("|cffEF4444Clear All|r")
    f.clearBtn:SetScript("OnClick", function()
        if Topnight.db then
            Topnight.db.shoppingList = {}
            Topnight:PrintInfo("Shopping list cleared.")
            Topnight:FireCallback("TOPNIGHT_SHOPPING_LIST_UPDATED")
            Topnight:RefreshShoppingUI()
        end
    end)

    -- ========================= SCROLL CONTENT =========================
    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", 6, -HEADER_HEIGHT - 4)
    f.scroll:SetPoint("BOTTOMRIGHT", -24, 6)

    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetWidth(PANEL_WIDTH - 36)
    f.content:SetHeight(1)
    f.scroll:SetScrollChild(f.content)

    shoppingFrame = f
    f:Hide()
    return f
end

-- ---------------------------------------------------------------------------
-- Frame Pools
-- ---------------------------------------------------------------------------
local groupPool = {}
local activeGroups = 0
local itemPool = {}
local activeItems = 0

local function ResetPools()
    for i = 1, activeGroups do
        if groupPool[i] then groupPool[i]:Hide() end
    end
    for i = 1, activeItems do
        if itemPool[i] then itemPool[i]:Hide() end
    end
    activeGroups = 0
    activeItems = 0
end

local function AcquireGroupFrame(parent)
    activeGroups = activeGroups + 1
    local frame = groupPool[activeGroups]
    if not frame then
        frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        Topnight:CreateBackdrop(frame, { r = 0.08, g = 0.08, b = 0.12, a = 0.7 })

        -- Group header
        local headerBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        headerBg:SetPoint("TOPLEFT", 0, 0)
        headerBg:SetPoint("TOPRIGHT", 0, 0)
        headerBg:SetHeight(28)
        Topnight:CreateBackdrop(headerBg, { r = C_PURPLE.r * 0.2, g = C_PURPLE.g * 0.2, b = C_PURPLE.b * 0.2, a = 0.9 })

        local headerIcon = headerBg:CreateTexture(nil, "ARTWORK")
        headerIcon:SetSize(16, 16)
        headerIcon:SetPoint("LEFT", 8, 0)

        local headerText = headerBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        headerText:SetPoint("LEFT", headerIcon, "RIGHT", 6, 0)

        frame.headerIcon = headerIcon
        frame.headerText = headerText
        groupPool[activeGroups] = frame
    end
    
    frame:SetParent(parent)
    frame:Show()
    return frame
end

local function AcquireItemFrame(parentGroup)
    activeItems = activeItems + 1
    local row = itemPool[activeItems]
    
    if not row then
        row = CreateFrame("Button", nil, parentGroup, "BackdropTemplate")
        row:SetHeight(26)
        Topnight:CreateBackdrop(row, { r = 0.07, g = 0.07, b = 0.10, a = 0.5 })

        -- Item icon
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", 6, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        -- Item name
        local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        name:SetTextColor(C_WHITE.r, C_WHITE.g, C_WHITE.b)
        name:SetWordWrap(false)
        name:SetWidth(230)
        name:SetJustifyH("LEFT")

        -- Source detail
        local detail = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        detail:SetPoint("RIGHT", -30, 0)
        detail:SetTextColor(C_GRAY.r, C_GRAY.g, C_GRAY.b)

        -- Remove button
        local removeBtn = CreateFrame("Button", nil, row)
        removeBtn:SetSize(16, 16)
        removeBtn:SetPoint("RIGHT", -6, 0)
        removeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
        removeBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
        removeBtn:SetScript("OnClick", function(self)
            Topnight:RemoveFromShoppingList(self.entryID)
            Topnight:RefreshShoppingUI()
        end)

        row:SetScript("OnClick", function(self)
            local data = self.itemData
            if not data then return end

            -- Always pull fresh source info from DecorSources to ensure we have the latest static data (like map coordinates)
            -- falling back to the cached info (which might just be parsed text)
            local si = nil
            if data.entryID and Topnight.DecorSources[data.entryID] then
                si = Topnight.DecorSources[data.entryID]
            else
                si = data.sourceInfo
            end
            
            if not si then 
                Topnight:PrintInfo("No source information available for " .. data.name)
                return 
            end

            -- Fallback to NPC Locations dictionary if we only have an NPC Name from the API
            if not si.uiMapID and si.npcName and Topnight.NPC_LOCATIONS and Topnight.NPC_LOCATIONS[si.npcName] then
                local npcData = Topnight.NPC_LOCATIONS[si.npcName]
                si.uiMapID = npcData.uiMapID
                si.x = npcData.x
                si.y = npcData.y
            end

            -- Fallback to Zone Locations dictionary if we only have a Zone from the API
            if not si.uiMapID and si.zone and Topnight.ZONE_LOCATIONS then
                local cleanZone = tostring(si.zone):lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
                
                -- DEBUG: Print exactly what cleanZone evaluates to so the user can verify it
                Topnight:Debug("Sanitized Zone string: '" .. cleanZone .. "'")
                
                local zoneData = Topnight.ZONE_LOCATIONS[cleanZone]
                if zoneData then
                    si.uiMapID = zoneData.uiMapID
                    si.x = zoneData.x
                    si.y = zoneData.y
                end
            end
            
            -- If we have native map coordinates (like our map pins do)
            if si.uiMapID and si.x and si.y then
                local point = UiMapPoint.CreateFromCoordinates(si.uiMapID, si.x, si.y)
                C_Map.SetUserWaypoint(point)
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
                
                if TomTom and TomTom.AddWaypoint then
                    TomTom:AddWaypoint(si.uiMapID, si.x, si.y, {
                        title = data.name,
                        persistent = false,
                        minimap = true,
                        world = true
                    })
                end

                Topnight:PrintInfo("Waypoint set to " .. data.name)
                
                -- Open the map to show the user where the waypoint is
                if not WorldMapFrame:IsShown() then
                    ToggleWorldMap()
                end
                WorldMapFrame:SetMapID(si.uiMapID)
            
            -- Fallback when no exact coordinates exist but we have a zone
            elseif si.zone then
                Topnight:PrintInfo("No exact coordinates available. Zone: " .. si.zone)
            
            -- Absolute fallback
            else
                local fallbackText = si.instanceName or si.npcName or si.questName or si.sourceName or si.detail or "Unknown"
                Topnight:PrintInfo("No exact coordinates available. Source: " .. fallbackText)
            end
        end)

        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.itemData.name, C_WHITE.r, C_WHITE.g, C_WHITE.b)
            local srcType = Topnight.SOURCE_TYPES[self.itemData.sourceType] or Topnight.SOURCE_TYPES.UNKNOWN
            GameTooltip:AddLine("Source: " .. srcType.label, C_ACCENT.r, C_ACCENT.g, C_ACCENT.b)
            if self.itemData.sourceInfo then
                local si = self.itemData.sourceInfo
                if si.npcName then GameTooltip:AddLine("NPC: " .. si.npcName, C_GRAY.r, C_GRAY.g, C_GRAY.b) end
                if si.zone then GameTooltip:AddLine("Zone: " .. si.zone, C_GRAY.r, C_GRAY.g, C_GRAY.b) end
                if si.cost then GameTooltip:AddLine("Cost: " .. si.cost, C_YELLOW.r, C_YELLOW.g, C_YELLOW.b) end
                -- Show raw source text from the API if available
                if si.detail and not si.npcName and not si.questName and not si.sourceName then
                    GameTooltip:AddLine("  " .. si.detail, C_DIM.r, C_DIM.g, C_DIM.b)
                end
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click for waypoint  |  X to remove", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row.icon = icon
        row.nameText = name
        row.detailText = detail
        row.removeBtn = removeBtn
        itemPool[activeItems] = row
    end
    
    row:SetParent(parentGroup)
    row:Show()
    return row
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------

function Topnight:RefreshShoppingUI()
    if not shoppingFrame or not shoppingFrame:IsShown() then return end

    -- Hide pooled frames
    ResetPools()

    -- Get grouped shopping list
    local groups = self:GetShoppingListGrouped()

    -- Count total items
    local totalItems = 0
    for _, group in ipairs(groups) do
        totalItems = totalItems + group.count
    end

    shoppingFrame.subtitle:SetText(string.format("%d item%s wanted", totalItems, totalItems == 1 and "" or "s"))

    -- Build group sections
    local yOffset = 0

    if totalItems == 0 then
        -- Empty state
        local emptyText = shoppingFrame.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyText:SetPoint("TOP", 0, -40)
        emptyText:SetText("|cff9CA3AFYour shopping list is empty.|r\n\n"
            .. "|cff6B7280Right-click items in the Collection Tracker|r\n"
            .. "|cff6B7280to add them here.|r")
        emptyText:SetJustifyH("CENTER")
        shoppingFrame.content.emptyText = emptyText
    else
        if shoppingFrame.content.emptyText then
            shoppingFrame.content.emptyText:Hide()
        end

        for _, groupData in ipairs(groups) do
            local groupFrame = AcquireGroupFrame(shoppingFrame.content)
            groupFrame:SetPoint("TOPLEFT", 0, -yOffset)
            groupFrame:SetPoint("RIGHT", 0, 0)
            
            groupFrame.headerIcon:SetTexture(groupData.icon)
            groupFrame.headerText:SetText(string.format("|cff8B5CF6%s|r  |cff9CA3AF(%d item%s)|r",
                groupData.label,
                groupData.count,
                groupData.count == 1 and "" or "s"))

            local headerHeight = 28
            local rowHeight = 26
            local totalHeight = headerHeight

            for i, item in ipairs(groupData.items) do
                local row = AcquireItemFrame(groupFrame)
                row:SetPoint("TOPLEFT", 4, -(headerHeight + (i - 1) * rowHeight))
                row:SetPoint("RIGHT", -4, 0)

                if i % 2 == 0 then
                    Topnight:CreateBackdrop(row, { r = 0.09, g = 0.09, b = 0.13, a = 0.5 })
                else
                    Topnight:CreateBackdrop(row, { r = 0.07, g = 0.07, b = 0.10, a = 0.3 })
                end

                row.itemData = item
                row.removeBtn.entryID = item.entryID
                row.icon:SetTexture(item.icon)
                row.nameText:SetText(item.name)
                
                local srcInfo = item.sourceInfo
                row.detailText:SetText("")
                if srcInfo then
                    if srcInfo.zone then
                        row.detailText:SetText(srcInfo.zone)
                    elseif srcInfo.instanceName then
                        row.detailText:SetText(srcInfo.instanceName)
                    elseif srcInfo.questName then
                        row.detailText:SetText(srcInfo.questName)
                    end
                end
                
                totalHeight = totalHeight + rowHeight
            end

            groupFrame:SetHeight(totalHeight + 4)
            yOffset = yOffset + totalHeight + 8
        end
    end

    shoppingFrame.content:SetHeight(math.max(1, yOffset + 10))
end

-- ---------------------------------------------------------------------------
-- Toggle / Init
-- ---------------------------------------------------------------------------

function Topnight:ToggleShoppingList()
    local f = CreateShoppingFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        self:RefreshShoppingUI()
    end
end

function Topnight:InitShoppingList()
    self:RegisterCallback("TOPNIGHT_SHOPPING_LIST_UPDATED", function()
        Topnight:RefreshShoppingUI()
    end)

    self:RegisterCallback("TOPNIGHT_COLLECTION_UPDATED", function()
        Topnight:RefreshShoppingUI()
    end)

    self:Debug("Shopping List initialized.")
end

