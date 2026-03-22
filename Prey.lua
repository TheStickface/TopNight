-- =============================================================================
-- Topnight - Prey.lua
-- Prey Hunt stage data — queries C_UIWidgetManager widget API (Midnight 12.0+)
-- =============================================================================

local ADDON_NAME, Topnight = ...

-- Stage constants — mirror Enum.PreyHuntProgressState with safe fallbacks
local PREY_COLD  = (Enum and Enum.PreyHuntProgressState and Enum.PreyHuntProgressState.Cold)  or 0
local PREY_WARM  = (Enum and Enum.PreyHuntProgressState and Enum.PreyHuntProgressState.Warm)  or 1
local PREY_HOT   = (Enum and Enum.PreyHuntProgressState and Enum.PreyHuntProgressState.Hot)   or 2
local PREY_FINAL = (Enum and Enum.PreyHuntProgressState and Enum.PreyHuntProgressState.Final) or 3

local WIDGET_TYPE_PREY = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.PreyHuntProgress) or 31
local WIDGET_SHOWN     = (Enum and Enum.WidgetShownState and Enum.WidgetShownState.Shown) or 1

-- ---------------------------------------------------------------------------
-- Internal: walk the power-bar widget set to find the active prey widget
-- ---------------------------------------------------------------------------
local function GetPreyWidgetInfo()
    if type(C_UIWidgetManager) ~= "table" then return nil end

    local getSetID   = C_UIWidgetManager.GetPowerBarWidgetSetID
    local getWidgets = C_UIWidgetManager.GetAllWidgetsBySetID
    local getInfo    = C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo
    if type(getSetID) ~= "function" or type(getWidgets) ~= "function" or type(getInfo) ~= "function" then
        return nil
    end

    local ok1, setID = pcall(getSetID)
    if not ok1 or not setID then return nil end

    local ok2, widgets = pcall(getWidgets, setID)
    if not ok2 or type(widgets) ~= "table" then return nil end

    for _, widget in ipairs(widgets) do
        if widget.widgetType == WIDGET_TYPE_PREY then
            local ok3, info = pcall(getInfo, widget.widgetID)
            if ok3 and type(info) == "table" then
                -- shownState nil means always shown; otherwise must equal WIDGET_SHOWN
                if info.shownState == nil or info.shownState == WIDGET_SHOWN then
                    return info
                end
            end
        end
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Returns the current prey hunt state.
--- @return table  { active = bool, stage = 0|1|2|3 }
---   stage 0 = Cold (no active hunt), 1 = Warm, 2 = Hot, 3 = Final (fight now)
function Topnight:GetPreyHuntData()
    local info = GetPreyWidgetInfo()
    if not info or info.progressState == nil then
        return { active = false, stage = 0 }
    end

    local s = info.progressState
    if s ~= PREY_COLD and s ~= PREY_WARM and s ~= PREY_HOT and s ~= PREY_FINAL then
        return { active = false, stage = 0 }
    end

    return {
        active = (s ~= PREY_COLD),
        stage  = s,
    }
end

-- ---------------------------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------------------------

function Topnight:InitPrey()
    -- NOTE: No caching is used. GetPreyHuntData() queries the widget API live on each call.
    -- The widget API is fast (table walk only) and this is called at most once per RefreshControlPanel
    -- tick (every 10s + on events), so live queries are preferable to stale cache bugs.
    -- NOTE: The spec listed PREY_HUNT_STAGE_CHANGED as a candidate event. The actual Midnight
    -- API does not expose that event. UPDATE_UI_WIDGET fires whenever any widget (including
    -- the prey crystal) changes state — it is the correct event to use here.
    local function onWidgetUpdate()
        if self.RefreshControlPanel then
            self:RefreshControlPanel()
        end
    end

    -- These events fire whenever the prey crystal stage changes
    self:RegisterEvent("UPDATE_UI_WIDGET",      function() onWidgetUpdate() end)
    self:RegisterEvent("UPDATE_ALL_UI_WIDGETS", function() onWidgetUpdate() end)

    self:Debug("Prey tracker initialized.")
end
