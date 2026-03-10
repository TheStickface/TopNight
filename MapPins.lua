-- =============================================================================
-- Topnight - MapPins.lua
-- Feature 4: Map Pins for tracked Decor items
-- =============================================================================

local ADDON_NAME, Topnight = ...

-- ---------------------------------------------------------------------------
-- Topnight Custom Pin Template
-- ---------------------------------------------------------------------------

-- Create a virtual template mixin for our map pins
TopnightMapPinMixin = CreateFromMixins(MapCanvasPinMixin)

function TopnightMapPinMixin:OnLoad()
    self:SetScalingLimits(1, 1.5, 0.5, 0.5) -- Limit how small/large the pin scales when zooming
end

function TopnightMapPinMixin:OnAcquired(pinData)
    -- pinData comes from our DataProvider when plotting
    self.pinData = pinData
    self:UseFrameLevelType("PIN_FRAME_LEVEL_VIGNETTE") -- Draw above most basic map elements
    
    -- Determine icon based on source type (fallback to a purple star)
    local iconTexture = "Interface\\AddOns\\Topnight\\Icons\\pin_default" -- We will create a fallback or use built-ins
    if Topnight.SOURCE_TYPES[pinData.sourceType] then
        iconTexture = Topnight.SOURCE_TYPES[pinData.sourceType].icon
    end

    if not self.Texture then
        self.Texture = self:CreateTexture(nil, "OVERLAY")
        self.Texture:SetAllPoints()
    end

    self.Texture:SetTexture(iconTexture)
    
    -- Adding a glowing border to make it stand out as a Topnight pin
    if not self.Glow then
        self.Glow = self:CreateTexture(nil, "BACKGROUND")
        self.Glow:SetPoint("CENTER")
        self.Glow:SetSize(40, 40)
        self.Glow:SetTexture("Interface\\GLUES\\Models\\UI_BloodElf\\bloodelf_lensflare")
        self.Glow:SetVertexColor(0.545, 0.361, 0.965, 0.8) -- Topnight Purple
        self.Glow:SetBlendMode("ADD")
    end
    
    self:SetPosition(pinData.x, pinData.y)
end

function TopnightMapPinMixin:OnMouseEnter()
    -- Show tooltip when hovering over the pin
    if not self.pinData then return end
    
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.pinData.name, 0.545, 0.361, 0.965) -- Topnight Purple Title
    GameTooltip:AddLine("Shopping List", 1, 1, 1)
    
    local srcInfo = self.pinData.sourceInfo
    if srcInfo then
        if srcInfo.npcName then
            GameTooltip:AddLine("NPC: " .. srcInfo.npcName, 0.9, 0.9, 0.9)
        end
        if srcInfo.zone then
            GameTooltip:AddLine("Zone: " .. srcInfo.zone, 0.9, 0.9, 0.9)
        end
        if srcInfo.cost then
            GameTooltip:AddLine("Cost: " .. srcInfo.cost, 0.96, 0.78, 0.15) -- Yellow
        end
        if srcInfo.sourceName then
            GameTooltip:AddLine("Drops from: " .. srcInfo.sourceName, 0.9, 0.9, 0.9)
        end
    end
    
    GameTooltip:Show()
end

function TopnightMapPinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

function TopnightMapPinMixin:OnMouseDown(button)
    if button == "LeftButton" and self.pinData then
        local uiMapID = self:GetMap():GetMapID()
        if uiMapID then
            -- Set new waypoint position
            local point = UiMapPoint.CreateFromCoordinates(uiMapID, self.pinData.x, self.pinData.y)
            C_Map.SetUserWaypoint(point)
            
            -- Set to actively track it
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            
            Topnight:PrintInfo("Waypoint set to " .. self.pinData.name)

            -- Ensure map is focused on the correct zone
            if WorldMapFrame and WorldMapFrame:IsShown() then
                WorldMapFrame:SetMapID(uiMapID)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- MapCanvas DataProvider
-- ---------------------------------------------------------------------------

TopnightDataProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function TopnightDataProviderMixin:OnShow()
    self:RegisterEvent("MAP_EXPLORATION_UPDATED")
    Topnight:RegisterCallback("TOPNIGHT_SHOPPING_LIST_UPDATED", function()
        self:RefreshAllData()
    end)
end

function TopnightDataProviderMixin:OnHide()
    self:UnregisterEvent("MAP_EXPLORATION_UPDATED")
end

function TopnightDataProviderMixin:OnEvent(event, ...)
    if event == "MAP_EXPLORATION_UPDATED" then
        self:RefreshAllData()
    end
end

function TopnightDataProviderMixin:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate("TopnightMapPinTemplate")
end

function TopnightDataProviderMixin:RefreshAllData()
    self:RemoveAllData()

    if not Topnight.db or not Topnight.db.shoppingList then return end
    
    local currentMapID = self:GetMap():GetMapID()
    if not currentMapID then return end

    -- Iterate through the Shopping List
    for entryID, isTracked in pairs(Topnight.db.shoppingList) do
        if isTracked then
            local itemInfo = Topnight.catalogCache and Topnight.catalogCache[entryID]
            local sourceInfo = Topnight.DecorSources[entryID] or (itemInfo and itemInfo.sourceInfo)
            
            if sourceInfo then
                -- If we have manual coordinates mapped for this item
                if sourceInfo.uiMapID and sourceInfo.x and sourceInfo.y then
                    -- Only draw the pin if the map we are looking at matches the item's map
                    if sourceInfo.uiMapID == currentMapID then
                        local pinType = "TopnightMapPinTemplate"
                        local pinData = {
                            entryID = entryID,
                            name = itemInfo and itemInfo.name or ("Decor #" .. entryID),
                            x = sourceInfo.x,
                            y = sourceInfo.y,
                            sourceType = sourceInfo.type or (itemInfo and itemInfo.sourceType) or "UNKNOWN",
                            sourceInfo = sourceInfo
                        }
                        
                        self:GetMap():AcquirePin(pinType, pinData)
                    end
                -- Fallback to NPC Locations dictionary if we only have an NPC Name from the API
                elseif sourceInfo.npcName and Topnight.NPC_LOCATIONS and Topnight.NPC_LOCATIONS[sourceInfo.npcName] then
                    local npcData = Topnight.NPC_LOCATIONS[sourceInfo.npcName]
                    if npcData.uiMapID == currentMapID then
                        local pinType = "TopnightMapPinTemplate"
                        
                        -- Graft the npc data into the sourceInfo so tooltips/clicks work
                        sourceInfo.uiMapID = npcData.uiMapID
                        sourceInfo.x = npcData.x
                        sourceInfo.y = npcData.y

                        local pinData = {
                            entryID = entryID,
                            name = itemInfo and itemInfo.name or ("Decor #" .. entryID),
                            x = npcData.x,
                            y = npcData.y,
                            sourceType = sourceInfo.type or (itemInfo and itemInfo.sourceType) or "UNKNOWN",
                            sourceInfo = sourceInfo
                        }
                        
                        self:GetMap():AcquirePin(pinType, pinData)
                    end
                -- Fallback to Zone Locations dictionary if we only have a Zone from the API
                elseif sourceInfo.zone and Topnight.ZONE_LOCATIONS then
                    local cleanZone = tostring(sourceInfo.zone):lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
                    local zoneData = Topnight.ZONE_LOCATIONS[cleanZone]
                    if zoneData and zoneData.uiMapID == currentMapID then
                        local pinType = "TopnightMapPinTemplate"
                        
                        -- Graft the zone data into the sourceInfo so tooltips/clicks work
                        sourceInfo.uiMapID = zoneData.uiMapID
                        sourceInfo.x = zoneData.x
                        sourceInfo.y = zoneData.y

                        local pinData = {
                            entryID = entryID,
                            name = itemInfo and itemInfo.name or ("Decor #" .. entryID),
                            x = zoneData.x,
                            y = zoneData.y,
                            sourceType = sourceInfo.type or (itemInfo and itemInfo.sourceType) or "UNKNOWN",
                            sourceInfo = sourceInfo
                        }
                        
                        self:GetMap():AcquirePin(pinType, pinData)
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------------------------

function Topnight:InitMapPins()
    -- 1. Create the XML template equivalent programmatically
    -- WoW's MapCanvas requires pins to be registered as templates (usually via XML)
    -- We can sidestep XML by dynamically creating a mixin-backed frame
    
    -- Create a hidden factory block
    local factoryFrame = CreateFrame("Frame")
    factoryFrame:Hide()
    
    -- In order to use AcquirePin, it needs to be registered with the PoolCollection
    -- But since we bypassed XML, we inject it directly into the map's pin pools if needed, 
    -- OR we just use a trick to register the frame type.
    
    -- The official way to register a non-XML template into MapCanvas is MapCanvas:AddPinTemplate
    -- but this relies heavily on AddDataProvider. Let's see how modern WoW handles it:
    
    if WorldMapFrame then
        -- Add our custom provider to the World Map
        local provider = CreateFromMixins(TopnightDataProviderMixin)
        
        -- Register the template: "TemplateName", "FrameType", "FrameInherits"
        -- We just need a generic Frame, but we inject our Mixin methods
        WorldMapFrame:AddDataProvider(provider)
        
        -- Override the factory generation for our specific template name because we don't have an XML file
        local pinPool = WorldMapFrame.pinPools and WorldMapFrame.pinPools["TopnightMapPinTemplate"]
        if not pinPool and WorldMapFrame.pinPools then
            WorldMapFrame.pinPools["TopnightMapPinTemplate"] = CreateFramePool("Frame", WorldMapFrame:GetCanvas(), nil, function(pool, pin)
                Mixin(pin, TopnightMapPinMixin)
                pin:SetSize(24, 24)
                pin:SetMouseClickEnabled(true) -- CRUCIAL: Allow the pin to receive click events
                if pin.OnLoad then pin:OnLoad() end
            end)
        end
    end
    
    self:Debug("Map Pins initialized.")
end
