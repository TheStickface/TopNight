-- =============================================================================
-- Topnight - Endeavors.lua
-- Neighborhood Endeavor Tracker — data layer with safe API wrappers
-- =============================================================================

local ADDON_NAME, Topnight = ...

-- ---------------------------------------------------------------------------
-- Cached Endeavor Data
-- ---------------------------------------------------------------------------
local cachedEndeavors = nil
local cachedSummary = nil
local lastRefreshTime = 0
local CACHE_TTL = 30 -- seconds before re-querying API

-- ---------------------------------------------------------------------------
-- Safe API Helpers
-- ---------------------------------------------------------------------------

--- Safely call a C_Housing function, returning nil on failure
local function SafeCall(func, ...)
    if not func then return nil end
    local ok, result = pcall(func, ...)
    if ok then return result end
    return nil
end

-- ---------------------------------------------------------------------------
-- Endeavor Data API
-- ---------------------------------------------------------------------------

--- Fetch current neighborhood endeavor tasks from the game API.
--- Returns a list of task tables, or an empty table if the API is unavailable.
---@return table[] tasks  Each entry: { name, description, progress, threshold, completed, rewardType }
function Topnight:GetEndeavorData()
    local now = GetTime()
    if cachedEndeavors and (now - lastRefreshTime) < CACHE_TTL then
        return cachedEndeavors
    end

    local tasks = {}

    -- Guard: API namespace must exist
    if not C_Housing then
        cachedEndeavors = tasks
        lastRefreshTime = now
        return tasks
    end

    -- Try to get active endeavors from the API
    -- The exact function name may vary; we try known candidates
    local endeavorList = SafeCall(C_Housing.GetActiveEndeavors)
        or SafeCall(C_Housing.GetNeighborhoodEndeavors)
        or SafeCall(C_Housing.GetEndeavors)

    if not endeavorList or type(endeavorList) ~= "table" then
        cachedEndeavors = tasks
        lastRefreshTime = now
        return tasks
    end

    for _, endeavor in ipairs(endeavorList) do
        local entry = {
            name        = endeavor.name or endeavor.taskName or "Unknown Task",
            description = endeavor.description or endeavor.taskDescription or "",
            progress    = endeavor.progress or endeavor.currentProgress or 0,
            threshold   = endeavor.threshold or endeavor.maxProgress or endeavor.goal or 1,
            completed   = false,
            rewardType  = "UNKNOWN",
        }

        -- Determine completion
        entry.completed = (entry.progress >= entry.threshold)

        -- Classify reward type from available fields
        if endeavor.rewardType then
            if type(endeavor.rewardType) == "string" then
                entry.rewardType = endeavor.rewardType
            elseif Enum and Enum.EndeavorRewardType then
                if endeavor.rewardType == Enum.EndeavorRewardType.Coupon then
                    entry.rewardType = "COUPON"
                elseif endeavor.rewardType == Enum.EndeavorRewardType.Favor then
                    entry.rewardType = "FAVOR"
                elseif endeavor.rewardType == Enum.EndeavorRewardType.HouseXP then
                    entry.rewardType = "XP"
                end
            end
        end

        table.insert(tasks, entry)
    end

    cachedEndeavors = tasks
    lastRefreshTime = now
    return tasks
end

--- Returns aggregate endeavor summary for display.
---@return table { totalTasks, completedTasks, neighborhoodName, timeRemaining }
function Topnight:GetEndeavorSummary()
    local now = GetTime()
    if cachedSummary and (now - lastRefreshTime) < CACHE_TTL then
        return cachedSummary
    end

    local tasks = self:GetEndeavorData()
    local total = #tasks
    local completed = 0
    for _, t in ipairs(tasks) do
        if t.completed then completed = completed + 1 end
    end

    -- Neighborhood name
    local neighborhoodName = "Unknown"
    if C_Housing then
        local info = SafeCall(C_Housing.GetNeighborhoodInfo)
            or SafeCall(C_Housing.GetCurrentNeighborhoodInfo)
        if info and type(info) == "table" then
            neighborhoodName = info.name or info.neighborhoodName or "Unknown"
        elseif type(info) == "string" then
            neighborhoodName = info
        end
    end

    -- Time remaining until endeavor reset
    local timeRemaining = nil
    if C_Housing then
        local resetInfo = SafeCall(C_Housing.GetEndeavorResetTime)
            or SafeCall(C_Housing.GetEndeavorsResetTime)
        if resetInfo then
            if type(resetInfo) == "number" then
                timeRemaining = math.max(0, resetInfo - time())
            elseif type(resetInfo) == "table" and resetInfo.resetTime then
                timeRemaining = math.max(0, resetInfo.resetTime - time())
            end
        end
    end

    cachedSummary = {
        totalTasks = total,
        completedTasks = completed,
        neighborhoodName = neighborhoodName,
        timeRemaining = timeRemaining,
    }

    return cachedSummary
end

--- Check if the Endeavor system is available at all.
---@return boolean
function Topnight:IsEndeavorSystemAvailable()
    if not C_Housing then return false end
    return (C_Housing.GetActiveEndeavors ~= nil)
        or (C_Housing.GetNeighborhoodEndeavors ~= nil)
        or (C_Housing.GetEndeavors ~= nil)
end

-- ---------------------------------------------------------------------------
-- Cache Invalidation (called from events)
-- ---------------------------------------------------------------------------

function Topnight:InvalidateEndeavorCache()
    cachedEndeavors = nil
    cachedSummary = nil
    lastRefreshTime = 0
end

-- ---------------------------------------------------------------------------
-- Time Formatting for Endeavor Reset
-- ---------------------------------------------------------------------------

function Topnight:FormatEndeavorTimeRemaining(seconds)
    if not seconds or seconds <= 0 then
        return "resetting soon"
    end

    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)

    if days > 0 then
        return string.format("%dd %dh", days, hours)
    elseif hours > 0 then
        local mins = math.floor((seconds % 3600) / 60)
        return string.format("%dh %dm", hours, mins)
    else
        local mins = math.floor(seconds / 60)
        return string.format("%dm", math.max(1, mins))
    end
end

-- ---------------------------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------------------------

function Topnight:InitEndeavors()
    self:Debug("Endeavor tracker initialized")

    -- Pre-fetch data after a short delay for API readiness
    C_Timer.After(3, function()
        self:GetEndeavorData()
    end)
end
