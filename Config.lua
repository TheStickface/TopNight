-- =============================================================================
-- Topnight - Config.lua
-- SavedVariables management and settings API
-- =============================================================================

local ADDON_NAME, Topnight = ...

-- ---------------------------------------------------------------------------
-- Default Settings
-- ---------------------------------------------------------------------------
local DEFAULTS = {
    debug = false,
    welcomeMessage = true,
    
    minimap = {
        hide = false,
        minimapPos = 220,
    },

    -- Minimap Vignette Overlay (highlight Midnight collectibles)
    minimapVignettes = {
        enabled = true,
    },

    -- Housing: Shopping List
    shoppingList = {},

    -- Housing: Control Panel position & visibility
    controlPanel = {
        show = true,
        locked = false,
        x = -200,
        y = 200,
        collapsed = false,
        alpha = 1.0,
    },

    -- Housing: Collection Tracker filters
    collectionFilters = {
        showOwned = true,
        showMissing = true,
        sourceFilter = "ALL",  -- ALL, VENDOR, QUEST, DROP, ACHIEVEMENT, PROFESSION, PVP
        sortBy = "NAME",       -- NAME, CATEGORY, SOURCE, EASIEST
    },

    -- Housing: Endeavor Tracker
    endeavors = {
        enabled = true,
    },

    -- Housing: Knowledge Points Tracker
    knowledgePoints = {
        enabled = true,
    },
    
    -- Housing: Estate Manager (Account-wide alt tracking)
    alts = {},

    -- Panel section collapse state
    collapsedSections = {},
}

Topnight.DEFAULTS = DEFAULTS

-- ---------------------------------------------------------------------------
-- Initialization (called from Core.lua on ADDON_LOADED)
-- ---------------------------------------------------------------------------
function Topnight:InitializeConfig()
    -- TopnightDB is the SavedVariables table declared in the TOC
    if not TopnightDB then
        TopnightDB = {}
    end

    -- Merge defaults into saved data (saved values take priority)
    self:MergeDefaults(TopnightDB, DEFAULTS)

    -- Store a convenient reference
    self.db = TopnightDB
end

-- ---------------------------------------------------------------------------
-- Settings API
-- ---------------------------------------------------------------------------

--- Get a setting value
---@param key string
---@return any
function Topnight:GetSetting(key)
    if self.db then
        return self.db[key]
    end
    return DEFAULTS[key]
end

--- Set a setting value
---@param key string
---@param value any
function Topnight:SetSetting(key, value)
    if self.db then
        self.db[key] = value
        self:Debug("Setting changed: " .. tostring(key) .. " = " .. tostring(value))
    end
end

--- Toggle a boolean setting
---@param key string
---@return boolean newValue
function Topnight:ToggleSetting(key)
    local current = self:GetSetting(key)
    local newValue = not current
    self:SetSetting(key, newValue)
    return newValue
end

--- Reset all settings to defaults
function Topnight:ResetSettings()
    TopnightDB = self:DeepCopy(DEFAULTS)
    self.db = TopnightDB
    self:PrintSuccess("All settings have been reset to defaults.")
end
