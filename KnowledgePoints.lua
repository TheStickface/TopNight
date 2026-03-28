-- =============================================================================
-- Topnight - KnowledgePoints.lua
-- Feature: Profession Knowledge Point (KP) Dashboard
-- Tracks weekly KP sources per TWW profession
-- =============================================================================

local ADDON_NAME, Topnight = ...

-- ---------------------------------------------------------------------------
-- Known Weekly KP Sources (The War Within / Midnight professions)
-- Each entry: { questID, label }
-- These are common cross-profession weekly quest IDs; profession-specific
-- ones are looked up dynamically when possible.
-- ---------------------------------------------------------------------------

-- Patron Order weekly quest IDs per profession (TWW Season 1+)
-- These are approximate; the addon gracefully handles missing/wrong IDs.
local WEEKLY_KP_SOURCES = {
    -- Generic weekly sources (apply to all professions)
    TREATISE      = { label = "Treatise",    tooltip = "Craft or buy from the AH" },
    WEEKLY_QUEST  = { label = "Weekly",      tooltip = "Profession weekly quest" },
    PATRON_ORDER  = { label = "Patron",      tooltip = "Patron crafting order" },
    WORLD_DROP    = { label = "Drops",       tooltip = "Gather from world/dungeon" },
}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local kpCache = nil  -- cached per-session; invalidated on profession data changes
local lastScanTime = 0
local KP_SCAN_COOLDOWN = 5  -- seconds between re-scans

-- ---------------------------------------------------------------------------
-- Profession Discovery
-- ---------------------------------------------------------------------------

--- Gets all primary professions for the current character
--- @return table[] List of { skillLineID, profName, iconID, parentSkillLineID }
local function GetPlayerProfessions()
    local professions = {}

    -- C_TradeSkillUI.GetAllProfTradeSkillLine() returns all known skill lines
    local ok, allSkillLines = pcall(function()
        return C_TradeSkillUI.GetAllProfTradeSkillLine()
    end)

    if ok and allSkillLines then
        for _, skillLineID in ipairs(allSkillLines) do
            local infoOk, info = pcall(function()
                return C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLineID)
            end)
            if infoOk and info and info.professionName and info.professionName ~= "" then
                -- Only include primary professions (not secondary like Cooking/Fishing)
                -- Primary professions have parentSkillLineID that matches a known primary
                table.insert(professions, {
                    skillLineID = skillLineID,
                    profName    = info.professionName,
                    iconID      = info.professionID and select(2, GetProfessionInfo(info.professionID)) or 134939,
                    parentSkillLineID = info.parentSkillLineID,
                    professionID = info.professionID,
                })
            end
        end
    end

    -- Fallback: use GetProfessions() API
    if #professions == 0 then
        local fallbackOk = pcall(function()
            local prof1, prof2 = GetProfessions()
            for _, idx in ipairs({ prof1, prof2 }) do
                if idx then
                    local name, icon, skillLevel, maxSkillLevel, _, _, skillLineID = GetProfessionInfo(idx)
                    if name and skillLineID then
                        table.insert(professions, {
                            skillLineID = skillLineID,
                            profName    = name,
                            iconID      = icon or 134939,
                            skillLevel  = skillLevel,
                            maxSkillLevel = maxSkillLevel,
                            professionID = idx,
                        })
                    end
                end
            end
        end)
    end

    return professions
end

-- ---------------------------------------------------------------------------
-- KP Scanning
-- ---------------------------------------------------------------------------

--- Scans knowledge point data for all professions
--- @return table[] kpData  List of { profName, iconID, kpEarned, kpMax, weeklySources }
local function ScanKP()
    local currentTime = GetTime()
    if kpCache and (currentTime - lastScanTime) < KP_SCAN_COOLDOWN then
        return kpCache
    end
    lastScanTime = currentTime

    local professions = GetPlayerProfessions()
    local results = {}

    for _, prof in ipairs(professions) do
        local entry = {
            profName = prof.profName,
            iconID   = prof.iconID,
            kpEarned = 0,
            kpMax    = 0,
            weeklySources = {},
        }

        -- Try to get KP info via C_Traits (TWW knowledge system)
        local traitOk = pcall(function()
            if C_ProfSpecs and C_ProfSpecs.GetCurrencyInfoForSkillLine then
                local currencyInfo = C_ProfSpecs.GetCurrencyInfoForSkillLine(prof.skillLineID)
                if currencyInfo then
                    entry.kpEarned = currencyInfo.spent or 0
                    entry.kpMax    = currencyInfo.maxQuantity or 0
                end
            end
        end)

        -- Fallback: try GetProfessionKnowledgeInfo if available
        if not traitOk or (entry.kpEarned == 0 and entry.kpMax == 0) then
            pcall(function()
                if C_TradeSkillUI.GetProfessionKnowledgeInfo then
                    local spent, max = C_TradeSkillUI.GetProfessionKnowledgeInfo(prof.skillLineID)
                    if spent then entry.kpEarned = spent end
                    if max then entry.kpMax = max end
                end
            end)
        end

        -- Weekly sources — check common quest completion flags
        for sourceKey, sourceInfo in pairs(WEEKLY_KP_SOURCES) do
            table.insert(entry.weeklySources, {
                key   = sourceKey,
                label = sourceInfo.label,
                tooltip = sourceInfo.tooltip,
                completed = false,  -- default; we can't reliably know quest IDs for all profs
            })
        end

        table.insert(results, entry)
    end

    -- Sort alphabetically by profession name
    table.sort(results, function(a, b) return a.profName < b.profName end)

    kpCache = results
    return results
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Returns a summary of KP data for all professions
--- @return table[]
function Topnight:GetKPSummary()
    return ScanKP()
end

--- Invalidate KP cache (called when profession data changes)
function Topnight:InvalidateKPCache()
    kpCache = nil
    lastScanTime = 0
end

--- Persist current KP snapshot to the alt roster (cross-character tracking)
local function PersistKPToAltRoster()
    if not Topnight.db or not Topnight.db.alts then return end

    local charName = UnitName("player")
    local realmName = GetRealmName()
    local fullName = charName .. "-" .. realmName

    Topnight.db.alts[fullName] = Topnight.db.alts[fullName] or {}
    local altData = Topnight.db.alts[fullName]

    local kpData = ScanKP()
    if kpData and #kpData > 0 then
        altData.kpSnapshot = {}
        for _, entry in ipairs(kpData) do
            table.insert(altData.kpSnapshot, {
                profName = entry.profName,
                kpEarned = entry.kpEarned,
                kpMax    = entry.kpMax,
            })
        end
        altData.kpSnapshotTime = time()
    end
end

-- ---------------------------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------------------------

function Topnight:InitKnowledgePoints()
    local kpSettings = self:GetSetting("knowledgePoints")
    if kpSettings and not kpSettings.enabled then
        self:Debug("Knowledge Points tracker disabled.")
        return
    end

    -- Listen for profession data changes to invalidate cache
    local profEvents = {
        "TRADE_SKILL_DATA_SOURCE_CHANGED",
        "SKILL_LINES_CHANGED",
        "TRADE_SKILL_LIST_UPDATE",
    }
    for _, evName in ipairs(profEvents) do
        pcall(function()
            self:RegisterEvent(evName, function()
                self:InvalidateKPCache()
                -- Persist updated data to alt roster
                C_Timer.After(1, function()
                    PersistKPToAltRoster()
                    if Topnight.RefreshControlPanel then
                        Topnight:RefreshControlPanel()
                    end
                end)
            end)
        end)
    end

    -- Initial scan after a short delay
    C_Timer.After(3, function()
        ScanKP()
        PersistKPToAltRoster()
        if self.RefreshControlPanel then
            self:RefreshControlPanel()
        end
    end)

    self:Debug("Knowledge Points tracker initialized.")
end
