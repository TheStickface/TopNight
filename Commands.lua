-- =============================================================================
-- Topnight - Commands.lua
-- Slash command registration and dispatch
-- =============================================================================

local ADDON_NAME, Topnight = ...

-- ---------------------------------------------------------------------------
-- Sub-command Dispatch Table
-- ---------------------------------------------------------------------------
-- Add new commands by inserting entries into this table.
-- Each entry: { handler = function, description = string }
local subCommands = {}

subCommands["help"] = {
    description = "Show this help message",
    handler = function(self)
        self:Print(self.Colors.ACCENT .. "Available commands:" .. self.Colors.RESET)
        for cmd, info in pairs(subCommands) do
            self:Print("  " .. self.Colors.ACCENT .. "/tn " .. cmd .. self.Colors.RESET
                .. " - " .. info.description)
        end
    end,
}

subCommands["version"] = {
    description = "Show addon version",
    handler = function(self)
        self:Print("Version: " .. self.Colors.SUCCESS .. self.version .. self.Colors.RESET)
    end,
}

subCommands["debug"] = {
    description = "Toggle debug mode",
    handler = function(self)
        local enabled = self:ToggleSetting("debug")
        if enabled then
            self:PrintSuccess("Debug mode enabled.")
        else
            self:PrintInfo("Debug mode disabled.")
        end
    end,
}

subCommands["reset"] = {
    description = "Reset all settings to defaults",
    handler = function(self)
        self:ResetSettings()
    end,
}

subCommands["config"] = {
    description = "Open Topnight Settings panel",
    handler = function(self)
        if Settings and Settings.OpenToCategory and Topnight.SettingsCategoryID then
            Settings.OpenToCategory(Topnight.SettingsCategoryID)
        else
            InterfaceOptionsFrame_OpenToCategory("Topnight")
            InterfaceOptionsFrame_OpenToCategory("Topnight")
        end
    end,
}

subCommands["settings"] = subCommands["config"]
subCommands["options"]  = subCommands["config"]

subCommands["welcome"] = {
    description = "Toggle login welcome message",
    handler = function(self)
        local enabled = self:ToggleSetting("welcomeMessage")
        if enabled then
            self:PrintSuccess("Welcome message enabled.")
        else
            self:PrintInfo("Welcome message disabled.")
        end
    end,
}

subCommands["minimap"] = {
    description = "Toggle the minimap button",
    handler = function(self)
        if self.ToggleMinimapButton then
            self:ToggleMinimapButton()
        else
            self:PrintError("Minimap module not loaded.")
        end
    end,
}

subCommands["vignettes"] = {
    description = "Toggle Midnight vignette highlights on minimap",
    handler = function(self)
        if self.ToggleMinimapVignettes then
            self:ToggleMinimapVignettes()
        else
            self:PrintError("Minimap vignettes module not loaded.")
        end
    end,
}

subCommands["vdebug"] = {
    description = "Dump active minimap vignettes (diagnostics)",
    handler = function(self)
        if self.DebugVignettes then
            self:DebugVignettes()
        else
            self:PrintError("Minimap vignettes module not loaded.")
        end
    end,
}

subCommands["mmdebug"] = {
    description = "Scan Minimap children frames (diagnostics)",
    handler = function(self)
        if self.DebugMinimapChildren then
            self:DebugMinimapChildren()
        else
            self:PrintError("Minimap vignettes module not loaded.")
        end
    end,
}

subCommands["icon"] = {
    description = "Cycle vignette overlay icon style",
    handler = function(self)
        if self.CycleVignetteIcon then
            self:CycleVignetteIcon()
        else
            self:PrintError("Minimap vignettes module not loaded.")
        end
    end,
}
-- ---------------------------------------------------------------------------
-- Housing Commands
-- ---------------------------------------------------------------------------

subCommands["collection"] = {
    description = "Open the Decor Collection Tracker",
    handler = function(self)
        if self.ToggleCollectionTracker then
            self:ToggleCollectionTracker()
        else
            self:PrintError("Collection Tracker not loaded.")
        end
    end,
}

subCommands["shopping"] = {
    description = "Open the Shopping List",
    handler = function(self)
        if self.ToggleShoppingList then
            self:ToggleShoppingList()
        else
            self:PrintError("Shopping List not loaded.")
        end
    end,
}

subCommands["panel"] = {
    description = "Toggle the Housing Control Panel",
    handler = function(self)
        if self.ToggleControlPanel then
            self:ToggleControlPanel()
        else
            self:PrintError("Control Panel not loaded.")
        end
    end,
}

subCommands["home"] = {
    description = "Teleport to your house",
    handler = function(self)
        if self.TeleportHome then
            self:TeleportHome()
        else
            self:PrintError("Housing module not loaded.")
        end
    end,
}

subCommands["scan"] = {
    description = "Force refresh the decor catalog",
    handler = function(self)
        if self.ScanCatalog then
            self:ScanCatalog()
        else
            self:PrintError("Housing data module not loaded.")
        end
    end,
}

subCommands["api"] = {
    description = "Dump available housing API functions",
    handler = function(self)
        if self.DumpHousingAPI then
            self:DumpHousingAPI()
        else
            self:PrintError("Housing data module not loaded.")
        end
    end,
}

subCommands["sources"] = {
    description = "Show source type classification breakdown",
    handler = function(self)
        if self.PrintSourceBreakdown then
            self:PrintSourceBreakdown()
        else
            self:PrintError("Housing data module not loaded.")
        end
    end,
}

subCommands["debugcat"] = {
    description = "Dump first catalog entry to chat",
    handler = function(self)
        self:Print("Running category diagnostic...")
        local searcher = C_HousingCatalog.CreateCatalogSearcher()
        searcher:SetOwnedOnly(false)
        searcher:SetEditorModeContext(Enum.HouseEditorMode.BasicDecor)
        searcher:SetCollected(true)
        searcher:SetUncollected(true)
        searcher:SetResultsUpdatedCallback(function()
            local results = searcher:GetCatalogSearchResults()
            if results and results[1] then
                self:Print("--- RESULT FIELDS ---")
                for k,v in pairs(results[1]) do
                    self:Print(" - " .. tostring(k) .. ": " .. tostring(v))
                end
                
                local info = C_HousingCatalog.GetCatalogEntryInfoByRecordID(results[1].entryType or 1, results[1].recordID, true)
                if info then
                    self:Print("--- INFO FIELDS ---")
                    for k,v in pairs(info) do
                        self:Print(" - " .. tostring(k) .. ": " .. tostring(v))
                    end
                end

                self:Print("--- CATEGORY API TESTS ---")
                local s1, r1 = pcall(C_HousingCatalog.SearchCatalogCategories, searcher)
                self:Print("SearchCatalogCategories(searcher): " .. tostring(s1) .. " - " .. type(r1))
                if type(r1) == "table" then self:Print("Size: " .. #r1) end

                local s2, r2 = pcall(C_HousingCatalog.SearchCatalogCategories, {})
                self:Print("SearchCatalogCategories({}): " .. tostring(s2) .. " - " .. type(r2))

                local s3, r3 = pcall(C_HousingCatalog.SearchCatalogCategories)
                self:Print("SearchCatalogCategories(): " .. tostring(s3) .. " - " .. type(r3))
            end
        end)
        searcher:SetSearchText()
        searcher:RunSearch()
    end,
}

subCommands["diag"] = {
    description = "Run full system diagnostics",
    handler = function(self)
        self:Print(self.Colors.ACCENT .. "=== Topnight Diagnostics ===" .. self.Colors.RESET)
        self:Print(self.Colors.INFO .. "Version: " .. self.version .. self.Colors.RESET)
        
        -- 1. Collection State
        self:Print(self.Colors.ACCENT .. "--- Collection ---" .. self.Colors.RESET)
        self:Print("  collectionReady: " .. tostring(self.collectionReady))
        local cacheCount = 0
        if self.catalogCache then
            for _ in pairs(self.catalogCache) do cacheCount = cacheCount + 1 end
        end
        self:Print("  catalogCache entries: " .. cacheCount)
        local catCount = 0
        if self.categoryCache then
            for _ in pairs(self.categoryCache) do catCount = catCount + 1 end
        end
        self:Print("  categoryCache entries: " .. catCount)
        if self.categoryOrder then
            self:Print("  categoryOrder count: " .. #self.categoryOrder)
        end
        
        -- 2. Housing Data
        self:Print(self.Colors.ACCENT .. "--- Housing ---" .. self.Colors.RESET)
        if self.houseLevelData then
            self:Print("  houseLevelData present: true")
            for k,v in pairs(self.houseLevelData) do
                self:Print("    " .. tostring(k) .. " = " .. tostring(v))
            end
        else
            self:Print("  houseLevelData: nil")
        end
        
        -- 3. Alt Roster
        self:Print(self.Colors.ACCENT .. "--- Alts ---" .. self.Colors.RESET)
        if self.db and self.db.alts then
            local altCount = 0
            for name, data in pairs(self.db.alts) do
                altCount = altCount + 1
                self:Print("  " .. name .. ": Lvl " .. tostring(data.level) .. ", Plot: " .. tostring(data.currentPlot))
            end
            if altCount == 0 then self:Print("  (none tracked)") end
        else
            self:Print("  db.alts: nil")
        end
        
        -- 4. Shopping List
        self:Print(self.Colors.ACCENT .. "--- Shopping List ---" .. self.Colors.RESET)
        local shopCount = 0
        if self.db and self.db.shoppingList then
            for _ in pairs(self.db.shoppingList) do shopCount = shopCount + 1 end
        end
        self:Print("  items: " .. shopCount)
        
        -- 5. Progression Director
        self:Print(self.Colors.ACCENT .. "--- Progression Director ---" .. self.Colors.RESET)
        if self.EvaluateProgressionTasks then
            local evalOk, evalErr = pcall(function() self:EvaluateProgressionTasks() end)
            if evalOk then
                self:Print("  tasks generated: " .. #self.ProgressionTasks)
                for i, task in ipairs(self.ProgressionTasks) do
                    self:Print("  " .. i .. ". [P" .. task.priority .. "] " .. task.title)
                    self:Print("     " .. task.description)
                end
                if #self.ProgressionTasks == 0 then
                    self:Print("  (no tasks -- APIs may not be available on beta)")
                end
            else
                self:Print("  |cffEF4444ERROR:|r " .. tostring(evalErr))
            end
        else
            self:Print("  EvaluateProgressionTasks: nil")
        end
        
        -- 6. Snoozed Tasks
        self:Print(self.Colors.ACCENT .. "--- Snoozed Tasks ---" .. self.Colors.RESET)
        if self.db and self.db.snoozedTasks then
            local sc = 0
            for title, expiry in pairs(self.db.snoozedTasks) do
                sc = sc + 1
                local remaining = expiry - time()
                self:Print("  " .. title .. " (expires in " .. math.floor(remaining / 3600) .. "h)")
            end
            if sc == 0 then self:Print("  (none)") end
        else
            self:Print("  (none)")
        end
        
        -- 7. API Availability
        self:Print(self.Colors.ACCENT .. "--- API Check ---" .. self.Colors.RESET)
        self:Print("  C_WeeklyRewards: " .. tostring(C_WeeklyRewards ~= nil))
        if C_WeeklyRewards then
            self:Print("  C_WeeklyRewards.GetActivities: " .. tostring(C_WeeklyRewards.GetActivities ~= nil))
            if C_WeeklyRewards.GetActivities then
                local ok, result = pcall(C_WeeklyRewards.GetActivities)
                self:Print("  GetActivities() call ok: " .. tostring(ok) .. ", type: " .. type(result))
                if ok and type(result) == "table" then
                    self:Print("  GetActivities() count: " .. #result)
                    for i, act in ipairs(result) do
                        self:Print("    " .. i .. ". type=" .. tostring(act.type) .. " progress=" .. tostring(act.progress) .. "/" .. tostring(act.threshold))
                    end
                end
            end
        end
        self:Print("  C_Housing: " .. tostring(C_Housing ~= nil))
        self:Print("  C_HousingCatalog: " .. tostring(C_HousingCatalog ~= nil))
        self:Print("  C_QuestLog: " .. tostring(C_QuestLog ~= nil))
        self:Print("  Enum.WeeklyRewardTraitValue: " .. tostring(Enum and Enum.WeeklyRewardTraitValue ~= nil))
        
        self:Print(self.Colors.SUCCESS .. "=== End Diagnostics ===" .. self.Colors.RESET)
    end,
}

subCommands["favor"] = {
    description = "Show favor gain history",
    handler = function(self)
        self:Print(self.Colors.ACCENT .. "--- Favor Sources ---" .. self.Colors.RESET)
        
        if self.GetFavorSources then
            local sources = self:GetFavorSources()
            for _, src in ipairs(sources) do
                local status = src.hasQuestID and (src.completed and "|cff22C55E[x]|r" or "|cff9CA3AF[ ]|r") or "|cffF59E0B[?]|r"
                self:Print(string.format("  %s %s (+%d favor)", status, src.name, src.favorAmount))
            end
        else
            self:Print("  FavorTracker not loaded.")
        end
        
        -- Recent gains
        self:Print(self.Colors.ACCENT .. "--- Recent Gains ---" .. self.Colors.RESET)
        if self.db and self.db.favorLog and #self.db.favorLog > 0 then
            for _, entry in ipairs(self.db.favorLog) do
                local ago = self:FormatTimeAgo(entry.timestamp)
                self:Print(string.format("  +%d favor in %s (%s)", entry.amount, entry.zone or "?", ago))
            end
        else
            self:Print("  (no favor gains recorded yet)")
        end
    end,
}

-- ---------------------------------------------------------------------------
-- Command Handler
-- ---------------------------------------------------------------------------
local function OnSlashCommand(msg)
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""

    if cmd == "" then
        subCommands["help"].handler(Topnight)
        return
    end

    local entry = subCommands[cmd]
    if entry then
        entry.handler(Topnight, rest)
    else
        Topnight:PrintError("Unknown command: " .. cmd)
        subCommands["help"].handler(Topnight)
    end
end

-- ---------------------------------------------------------------------------
-- Registration (called from Core.lua)
-- ---------------------------------------------------------------------------
function Topnight:RegisterCommands()
    SLASH_TOPNIGHT1 = "/topnight"
    SLASH_TOPNIGHT2 = "/tn"
    SlashCmdList["TOPNIGHT"] = OnSlashCommand

    self:Debug("Slash commands registered: /topnight, /tn")
end

-- Expose for extensibility — other files can add sub-commands:
--   Topnight.subCommands["mycommand"] = { handler = ..., description = ... }
Topnight.subCommands = subCommands
