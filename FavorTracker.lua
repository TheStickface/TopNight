-- =============================================================================
-- Topnight - FavorTracker.lua
-- Tracks weekly favor-granting activities for the Midnight expansion
-- =============================================================================

local ADDON_NAME, Topnight = ...

-- ---------------------------------------------------------------------------
-- Known Favor Sources (placeholder IDs — discover real ones on beta)
-- Format: { name, questID, favorAmount, category }
-- questID is the hidden completion flag checked via C_QuestLog.IsQuestFlaggedCompleted
-- ---------------------------------------------------------------------------
local FAVOR_SOURCES = {
    { name = "Weekly Dungeon",     questID = nil, favorAmount = 50,  category = "weekly" },
    { name = "Weekly World Quest", questID = nil, favorAmount = 30,  category = "weekly" },
    { name = "Housing Daily",      questID = nil, favorAmount = 15,  category = "daily" },
    { name = "Storyline Chapter",  questID = nil, favorAmount = 100, category = "once" },
}

-- ---------------------------------------------------------------------------
-- Favor Source API
-- ---------------------------------------------------------------------------

--- Returns the list of favor sources with completion status
function Topnight:GetFavorSources()
    local results = {}
    
    for _, source in ipairs(FAVOR_SOURCES) do
        local completed = false
        if source.questID and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
            completed = C_QuestLog.IsQuestFlaggedCompleted(source.questID)
        end
        
        table.insert(results, {
            name = source.name,
            favorAmount = source.favorAmount,
            completed = completed,
            category = source.category,
            hasQuestID = source.questID ~= nil,
        })
    end
    
    return results
end

-- ---------------------------------------------------------------------------
-- Favor Change Detection (auto-discover which activities grant favor)
-- ---------------------------------------------------------------------------

local lastKnownFavor = nil

function Topnight:TrackFavorChange(eventFavor)
    if not eventFavor or not eventFavor.houseFavor then return end
    
    local currentFavor = eventFavor.houseFavor
    
    if lastKnownFavor and currentFavor > lastKnownFavor then
        local gained = currentFavor - lastKnownFavor
        self:PrintSuccess(string.format("Favor gained: +%d (total: %d)", gained, currentFavor))
        
        -- Log it for discovery purposes
        if self.db then
            self.db.favorLog = self.db.favorLog or {}
            table.insert(self.db.favorLog, {
                amount = gained,
                total = currentFavor,
                timestamp = time(),
                zone = GetZoneText(),
            })
            -- Keep only last 20 entries
            while #self.db.favorLog > 20 do
                table.remove(self.db.favorLog, 1)
            end
        end
    end
    
    lastKnownFavor = currentFavor
end

