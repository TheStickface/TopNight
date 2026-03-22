-- =============================================================================
-- Topnight - Progression.lua
-- The Progression Director Engine
-- Priorities: Housing/Midnight content first, then general WoW progression
-- =============================================================================

local ADDON_NAME, Topnight = ...

-- ---------------------------------------------------------------------------
-- Priority Tiers (higher = shows first)
-- ---------------------------------------------------------------------------
-- 80-89:  Midnight Weekly/Seasonal content
-- 70-79:  Great Vault / Lockouts
-- 50-55:  Midnight Housing (decor, favor, shopping)
-- 40-49:  Character Optimization (enchants, gems)

-- ---------------------------------------------------------------------------
-- The Evaluator Engine
-- ---------------------------------------------------------------------------
Topnight.ProgressionTasks = {}

local function AddTask(title, description, priority, actionFunc)
    table.insert(Topnight.ProgressionTasks, {
        title = title,
        description = description,
        priority = priority,
        action = actionFunc
    })
end

function Topnight:EvaluateProgressionTasks()
    self.ProgressionTasks = {}

    -- 1. Housing (Midnight core — highest priority)
    local ok0, err0 = pcall(function() self:EvaluateHousing(AddTask) end)
    if not ok0 then self:Debug("Housing evaluator error: " .. tostring(err0)) end

    -- 1b. Neighborhood Endeavors
    local ok4, err4 = pcall(function() self:EvaluateEndeavors(AddTask) end)
    if not ok4 then self:Debug("Endeavor evaluator error: " .. tostring(err4)) end

    -- 1c. Prey Hunts
    local okP, errP = pcall(function() self:EvaluatePreyHunts() end)
    if not okP then self:Debug("Prey evaluator error: " .. tostring(errP)) end

    -- 2. Midnight Weekly Quests
    local ok3, err3 = pcall(function() self:EvaluateWeeklyLockouts(AddTask) end)
    if not ok3 then self:Debug("Weekly evaluator error: " .. tostring(err3)) end

    -- 3. Great Vault (general progression)
    local ok1, err1 = pcall(function() self:EvaluateGreatVault(AddTask) end)
    if not ok1 then self:Debug("Vault evaluator error: " .. tostring(err1)) end

    -- 4. Character Optimization (lowest priority)
    local ok2, err2 = pcall(function() self:EvaluateGear(AddTask) end)
    if not ok2 then self:Debug("Gear evaluator error: " .. tostring(err2)) end

    -- Sort high to low
    table.sort(self.ProgressionTasks, function(a, b)
        return a.priority > b.priority
    end)
    
    -- Filter out snoozed tasks
    local filtered = {}
    for _, task in ipairs(self.ProgressionTasks) do
        if not self:IsTaskSnoozed(task.title) then
            table.insert(filtered, task)
        end
    end
    self.ProgressionTasks = filtered
end

-- ---------------------------------------------------------------------------
-- Snooze System
-- ---------------------------------------------------------------------------

function Topnight:SnoozeTask(taskTitle)
    if not taskTitle then return end
    if not self.db then return end
    
    self.db.snoozedTasks = self.db.snoozedTasks or {}
    self.db.snoozedTasks[taskTitle] = time() + (7 * 24 * 60 * 60)
    self:PrintInfo("Snoozed: " .. taskTitle)
end

function Topnight:IsTaskSnoozed(taskTitle)
    if not self.db or not self.db.snoozedTasks then return false end
    
    local expiry = self.db.snoozedTasks[taskTitle]
    if not expiry then return false end
    
    if time() > expiry then
        self.db.snoozedTasks[taskTitle] = nil
        return false
    end
    
    return true
end

-- ---------------------------------------------------------------------------
-- Evaluator: Housing (Midnight Core — Priority 50-55)
-- ---------------------------------------------------------------------------
function Topnight:EvaluateHousing(addTask)
    -- Catalog scan status
    if not self.collectionReady then
        addTask("Scan Decor Catalog", "Your decor collection hasn't loaded yet. Click to run a scan.", 55, function()
            Topnight:ScanCatalog()
        end)
    end

    -- House favor progress — nudge when close to leveling up
    if self.houseLevelData and not self.houseLevelData.noHouse then
        local favor = self.houseLevelData.favor or 0
        local nextFavor = self.houseLevelData.nextFavor or 100
        local level = self.houseLevelData.level or 1
        local pct = nextFavor > 0 and (favor / nextFavor) or 0

        if pct >= 0.8 then
            addTask("House Level Up", string.format("You're at %d%% favor — almost House Level %d!", math.floor(pct * 100), level + 1), 53, function()
                Topnight:ShowControlPanel()
            end)
        end
    end

    -- Shopping list reminder
    if self.db and self.db.shoppingList then
        local shopCount = 0
        for _ in pairs(self.db.shoppingList) do shopCount = shopCount + 1 end
        if shopCount > 0 then
            addTask("Decor Shopping", string.format("You have %d decor item%s on your shopping list.", shopCount, shopCount == 1 and "" or "s"), 50, function()
                if Topnight.ToggleShoppingList then
                    Topnight:ToggleShoppingList()
                end
            end)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Evaluator: Midnight Weekly Quests (Priority 80-89)
-- ---------------------------------------------------------------------------
function Topnight:EvaluateWeeklyLockouts(addTask)
    if not C_QuestLog then return end
    
    -- Midnight weekly meta-quest ID (placeholder — update when final ID is known)
    local WEEKLY_META_QUEST = 82706 
    
    if not C_QuestLog.IsQuestFlaggedCompleted(WEEKLY_META_QUEST) then
        local isOnQuest = C_QuestLog.GetLogIndexForQuestID(WEEKLY_META_QUEST) ~= nil
        
        if isOnQuest then
            addTask("Weekly Quest", "You have the weekly meta-quest but haven't finished it.", 82, function()
                ToggleQuestLog()
            end)
        else
            addTask("Weekly Quest", "You haven't picked up your weekly meta-quest yet!", 85, function()
                ToggleWorldMap()
            end)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Evaluator: The Great Vault (Priority 70-79)
-- ---------------------------------------------------------------------------
function Topnight:EvaluateGreatVault(addTask)
    if not C_WeeklyRewards or not C_WeeklyRewards.GetActivities then return end
    
    local activities = C_WeeklyRewards.GetActivities()
    if not activities then return end

    for _, activity in ipairs(activities) do
        if activity.progress < activity.threshold and (activity.threshold - activity.progress) == 1 then
            
            local actType = "Activity"
            if Enum and Enum.WeeklyRewardChestThresholdType then
                if activity.type == Enum.WeeklyRewardChestThresholdType.Raid then actType = "Raid Boss"
                elseif activity.type == Enum.WeeklyRewardChestThresholdType.MythicPlus then actType = "Mythic+ Dungeon"
                elseif activity.type == Enum.WeeklyRewardChestThresholdType.World then actType = "Delve or World Activity"
                end
            end

            addTask("Great Vault: " .. actType, string.format("Complete 1 more %s to unlock a new Great Vault slot!", actType), 75, function() 
                if WeeklyRewards_ShowUI then
                    WeeklyRewards_ShowUI()
                elseif ToggleEncounterJournal then
                    ToggleEncounterJournal()
                end
            end)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Evaluator: Character Gear Optimization (Priority 40-49)
-- ---------------------------------------------------------------------------
function Topnight:EvaluateGear(addTask)
    -- Only suggest enchants at max level — no point enchanting leveling gear
    if UnitLevel("player") < 90 then return end
    local ENCHANTABLE_SLOTS = {
        [5] = "Chest",
        [8] = "Feet",
        [9] = "Wrist",
        [11] = "Ring 1",
        [12] = "Ring 2",
        [15] = "Back",
        [16] = "Main Hand"
    }

    local missingEnchants = {}
    for slotID, slotName in pairs(ENCHANTABLE_SLOTS) do
        local itemLink = GetInventoryItemLink("player", slotID)
        if itemLink then
            local enchantID = itemLink:match("item:%d+:(%d*):")
            if enchantID == "" or enchantID == "0" then
                table.insert(missingEnchants, slotName)
            end
        end
    end

    if #missingEnchants > 0 then
        addTask("Missing Enchants", "You are missing enchants on: " .. table.concat(missingEnchants, ", "), 45, function()
            ToggleCharacter("PaperDollFrame")
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Evaluator: Neighborhood Endeavors (Priority 52)
-- ---------------------------------------------------------------------------
function Topnight:EvaluateEndeavors(addTask)
    if not self.IsEndeavorSystemAvailable or not self:IsEndeavorSystemAvailable() then return end

    local tasks = self:GetEndeavorData()
    if not tasks or #tasks == 0 then return end

    -- Check for near-complete tasks
    for _, task in ipairs(tasks) do
        if not task.completed and task.threshold > 0 then
            local pct = task.progress / task.threshold
            if pct >= 0.75 then
                addTask("Endeavor: " .. task.name,
                    string.format("Almost done — %d/%d contributions!", task.progress, task.threshold),
                    52, function()
                        Topnight:ShowControlPanel()
                    end)
                return -- Only surface the most impactful one
            end
        end
    end

    -- Fallback: check if no progress at all on any task
    local anyProgress = false
    for _, task in ipairs(tasks) do
        if task.progress > 0 then anyProgress = true; break end
    end

    if not anyProgress then
        addTask("Neighborhood Endeavors",
            "Your neighborhood has active Endeavors — check in!",
            52, function()
                Topnight:ShowControlPanel()
            end)
    end
end

-- ---------------------------------------------------------------------------
-- Evaluator: Prey Hunts (Priority 83)
-- ---------------------------------------------------------------------------
function Topnight:EvaluatePreyHunts()
    if not self.GetPreyHuntData then return end

    local data = self:GetPreyHuntData()
    if not data or not data.active then return end

    -- Insert directly (bypasses the fixed 4-param addTask — stageIndicator needs a 5th field)
    table.insert(self.ProgressionTasks, {
        title          = "Prey Hunt",
        description    = nil,
        priority       = 83,
        stageIndicator = { current = data.stage, max = 3 },
        action         = function()
            if ToggleWorldMap then ToggleWorldMap() end
        end,
    })
end
