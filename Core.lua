-- =============================================================================
-- Topnight - Core.lua
-- Addon initialization and event framework
-- =============================================================================

local ADDON_NAME, Topnight = ...

Topnight.name    = ADDON_NAME
Topnight.version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "unknown"

-- ---------------------------------------------------------------------------
-- Event Framework
-- ---------------------------------------------------------------------------
local EventFrame = CreateFrame("Frame")
local eventHandlers = {}

--- Register a handler for a WoW event
---@param event string
---@param handler function
function Topnight:RegisterEvent(event, handler)
    eventHandlers[event] = eventHandlers[event] or {}
    table.insert(eventHandlers[event], handler)
    EventFrame:RegisterEvent(event)
end

--- Unregister all handlers for an event
---@param event string
function Topnight:UnregisterEvent(event)
    eventHandlers[event] = nil
    EventFrame:UnregisterEvent(event)
end

EventFrame:SetScript("OnEvent", function(_, event, ...)
    local handlers = eventHandlers[event]
    if handlers then
        for _, handler in ipairs(handlers) do
            handler(Topnight, event, ...)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- ADDON_LOADED — one-time setup
-- ---------------------------------------------------------------------------
Topnight:RegisterEvent("ADDON_LOADED", function(self, _, loadedAddon)
    if loadedAddon ~= ADDON_NAME then return end

    -- Initialize saved variables & config
    self:InitializeConfig()

    -- Register slash commands
    self:RegisterCommands()

    -- Initialize housing data layer
    if self.InitHousingData then
        self:InitHousingData()
    end

    self:Debug("Addon loaded successfully (v" .. self.version .. ")")

    -- We only need this once
    self:UnregisterEvent("ADDON_LOADED")
end)

-- ---------------------------------------------------------------------------
-- PLAYER_LOGIN — fires after the player is fully in the world
-- ---------------------------------------------------------------------------
Topnight:RegisterEvent("PLAYER_LOGIN", function(self)
    if self:GetSetting("welcomeMessage") then
        self:Print("v" .. self.version .. " loaded. Type "
            .. self.Colors.ACCENT .. "/topnight" .. self.Colors.RESET
            .. " or " .. self.Colors.ACCENT .. "/tn" .. self.Colors.RESET
            .. " for commands.")
    end

    -- Initialize housing UI modules (must happen after login)
    if self.InitCollectionTracker then
        self:InitCollectionTracker()
    end
    if self.InitShoppingList then
        self:InitShoppingList()
    end
    if self.InitControlPanel then
        self:InitControlPanel()
    end
    if self.InitMinimap then
        self:InitMinimap()
    end
    if self.InitMapPins then
        self:InitMapPins()
    end
    if self.InitMinimapVignettes then
        self:InitMinimapVignettes()
    end
    if self.InitEndeavors then
        self:InitEndeavors()
    end
    if self.InitEconomyScanner then
        self:InitEconomyScanner()
    end

    -- Scan housing catalog after a short delay for API readiness
    if self.ScanCatalog then
        -- Initial silent scan to populate data
        C_Timer.After(2, function() self:ScanCatalog(true) end)
        
        -- Start silent background scanning every 5 minutes (300 seconds)
        C_Timer.NewTicker(300, function()
            self:ScanCatalog(true)
        end)
    end

    -- Listen for housing favor changes (for FavorTracker auto-detection)
    self:RegisterEvent("HOUSE_LEVEL_FAVOR_UPDATED", function(innerSelf, _, favorData)
        if innerSelf.TrackFavorChange then
            innerSelf:TrackFavorChange(favorData)
        end
        if innerSelf.RefreshControlPanel then
            innerSelf:RefreshControlPanel()
        end
    end)

    -- Listen for endeavor updates (event name may vary; silently skip if unknown)
    local endeavorHandler = function(innerSelf)
        if innerSelf.InvalidateEndeavorCache then
            innerSelf:InvalidateEndeavorCache()
        end
        if innerSelf.RefreshControlPanel then
            innerSelf:RefreshControlPanel()
        end
    end
    -- Try known possible event names — pcall to avoid errors on unknown events
    local endeavorEvents = {
        "NEIGHBORHOOD_ENDEAVOR_UPDATED",
        "HOUSING_ENDEAVOR_UPDATED",
        "HOUSING_ENDEAVOR_DATA_UPDATED",
    }
    for _, evName in ipairs(endeavorEvents) do
        local ok = pcall(function()
            self:RegisterEvent(evName, endeavorHandler)
        end)
        if ok then
            self:Debug("Registered endeavor event: " .. evName)
            break
        end
    end

    self:UnregisterEvent("PLAYER_LOGIN")
end)

-- ---------------------------------------------------------------------------
-- Public namespace (other files access via select(2, ...))
-- ---------------------------------------------------------------------------
-- The Topnight table is already shared across all files via the ... mechanism.
-- No additional exports needed.
