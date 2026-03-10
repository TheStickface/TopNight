-- =============================================================================
-- Topnight - HousingData.lua
-- Housing data layer: catalog scanning, collection cache, source DB, stats
-- =============================================================================

local ADDON_NAME, Topnight = ...

-- ---------------------------------------------------------------------------
-- Collection Cache
-- ---------------------------------------------------------------------------
Topnight.catalogCache = {}       -- { [entryID] = { name, icon, categoryID, categoryName, isOwned, ... } }
Topnight.categoryCache = {}      -- { [categoryID] = { name, icon, numTotal, numOwned } }
Topnight.categoryOrder = {}      -- ordered list of categoryIDs
Topnight.collectionReady = false -- true after first successful scan

-- ---------------------------------------------------------------------------
-- Estate Manager (Alt Tracking)
-- ---------------------------------------------------------------------------
function Topnight:UpdateAltHousingData()
    if not self.db then return end
    
    local charKey = UnitName("player") .. "-" .. GetRealmName()
    
    -- Safe API wrapper calls since we are tracking unreleased/beta features
    local houseLevel = 1
    local curFavor, maxFavor = 0, 1000
    local plotName = "Unknown Plot"
    
    pcall(function()
        if C_Housing and C_Housing.GetHouseLevelInfo then
            local levelInfo = C_Housing.GetHouseLevelInfo()
            if levelInfo then
                houseLevel = levelInfo.level or 1
                curFavor = levelInfo.currentFavor or 0
                maxFavor = levelInfo.favorForNextLevel or 1000
            end
        end
        if C_Housing and C_Housing.GetHouseInfo then
            local info = C_Housing.GetHouseInfo()
            if info and info.name then
                plotName = info.name
            end
        end
    end)
    
    self.db.alts = self.db.alts or {}
    self.db.alts[charKey] = {
        level = houseLevel,
        favor = curFavor,
        maxFavor = maxFavor,
        currentPlot = plotName,
        lastSeen = time(),
        class = select(2, UnitClass("player"))
    }
end

-- ---------------------------------------------------------------------------
-- Decor Source Database
-- Source types: VENDOR, QUEST, ACHIEVEMENT, DROP, PROFESSION, PVP, UNKNOWN
-- Community-expandable: add entries to Topnight.DecorSources
-- ---------------------------------------------------------------------------
Topnight.SOURCE_TYPES = {
    VENDOR      = { label = "Vendor",      icon = "Interface\\Icons\\INV_Misc_Coin_01",      priority = 1 },
    QUEST       = { label = "Quest",       icon = "Interface\\Icons\\INV_Misc_Map_01",       priority = 2 },
    ACHIEVEMENT = { label = "Achievement", icon = "Interface\\Icons\\Achievement_General",    priority = 3 },
    PROFESSION  = { label = "Profession",  icon = "Interface\\Icons\\Trade_Engineering",      priority = 4 },
    DROP        = { label = "Drop",        icon = "Interface\\Icons\\INV_Misc_Bag_10",       priority = 5 },
    PVP         = { label = "PvP",         icon = "Interface\\Icons\\Achievement_PVP_A_01",  priority = 6 },
    UNKNOWN     = { label = "Unknown",     icon = "Interface\\Icons\\INV_Misc_QuestionMark", priority = 99 },
}

-- Hardcoded source data — items mapped to acquisition info
-- Includes map coordinates for the MapPins module where available
Topnight.DecorSources = {
    [1001] = { type = "VENDOR", npcName = "Silvermoon Decor Vendor", zone = "Silvermoon City", cost = "50g", uiMapID = 2393, x = 0.54, y = 0.61 }, -- Example Map: Silvermoon
    [1002] = { type = "QUEST", questName = "Echoes of Quel'Thalas", zone = "Silvermoon", uiMapID = 2393, x = 0.45, y = 0.35 },
}

-- Database of known NPC map coordinates (fallback when specific item ID isn't mapped)
Topnight.NPC_LOCATIONS = {
    -- Silvermoon / Bel'ameth
    ["Corlen Hordralin"] = { uiMapID = 2393, x = 0.4413, y = 0.6276 }, -- Silvermoon City
    ["Ellandrieth"]      = { uiMapID = 2248, x = 0.4835, y = 0.5359 }, -- Bel'ameth (General Goods)
    ["Mythrin'dir"]      = { uiMapID = 2248, x = 0.5409, y = 0.6082 }, -- Bel'ameth (Trade Goods)
    
    -- Founder's Point (Alliance Midnight Housing)
    ["Argan Hammerfist"]  = { uiMapID = 2352, x = 0.5220, y = 0.3780 },
    ["Balen Starfinder"]  = { uiMapID = 2352, x = 0.5220, y = 0.3800 },
    ["Faarden the Builder"] = { uiMapID = 2352, x = 0.5200, y = 0.3840 },
    ["Harlowe Marl"]      = { uiMapID = 2352, x = 0.5300, y = 0.3800 },
    ["Klasa"]             = { uiMapID = 2352, x = 0.5830, y = 0.6170 },
    ["Trevor Grenner"]    = { uiMapID = 2352, x = 0.5350, y = 0.4090 },
    ["Xiao Dan"]          = { uiMapID = 2352, x = 0.5200, y = 0.3830 },

    -- Razorwind Shores (Horde Midnight Housing)
    ["Botanist Boh'an"]   = { uiMapID = 2351, x = 0.5400, y = 0.5840 },
    ["Brother Dovetail"]  = { uiMapID = 2351, x = 0.5440, y = 0.5610 },
    ["Gronthul"]          = { uiMapID = 2351, x = 0.5410, y = 0.5910 },
    ["Hesta Forlath"]     = { uiMapID = 2351, x = 0.5440, y = 0.5600 },
    ["Jehzar Starfall"]   = { uiMapID = 2351, x = 0.5360, y = 0.5850 },
    ["Lefton Farrer"]     = { uiMapID = 2351, x = 0.5350, y = 0.5850 },
    ["Lonomia"]           = { uiMapID = 2351, x = 0.6830, y = 0.7550 },
    ["Pascal-K1N6"]       = { uiMapID = 2351, x = 0.5410, y = 0.5600 },
    ["Shon'ja"]           = { uiMapID = 2351, x = 0.5410, y = 0.5900 },

    -- Classic Exmples
    ["Innkeeper Belm"]   = { uiMapID = 27,   x = 0.5407, y = 0.5076 }, -- Kharanos / Dun Morogh
}

-- Database of known General Zone map coordinates (fallback when specific item ID or NPC isn't mapped)
Topnight.ZONE_LOCATIONS = {
    ["silvermoon city"]  = { uiMapID = 2393, x = 0.4413, y = 0.6276 }, -- General Housing Vendor Area
    ["founder's point"]  = { uiMapID = 2352, x = 0.5000, y = 0.5000 }, -- Alliance Housing Hub
    ["razorwind shores"] = { uiMapID = 2351, x = 0.5000, y = 0.5000 }, -- Horde Housing Hub
    ["bel'ameth"]        = { uiMapID = 2248, x = 0.4835, y = 0.5359 }, -- Ellandrieth location
    ["stormwind city"]   = { uiMapID = 84,   x = 0.5000, y = 0.5000 }, -- General Fallback
    ["orgrimmar"]        = { uiMapID = 85,   x = 0.5000, y = 0.5000 }, -- General Fallback
    ["valdrakken"]       = { uiMapID = 2112, x = 0.5000, y = 0.5000 }, -- General Fallback
    ["dornogal"]         = { uiMapID = 2339, x = 0.5000, y = 0.5000 }, -- General Fallback
}
-- ---------------------------------------------------------------------------
-- Source Text Classifier
-- Parses the Blizzard API sourceText string into a structured source type.
-- ---------------------------------------------------------------------------

--- Keyword patterns ordered by specificity.
--- Each entry: { pattern, sourceType [, detailExtractor] }
local SOURCE_PATTERNS = {
    -- Vendors / purchasing
    { "sold by",          "VENDOR" },
    { "vendor",           "VENDOR" },
    { "purchased from",   "VENDOR" },
    { "bought from",      "VENDOR" },
    { "catalog",          "VENDOR" },
    { "market",           "VENDOR" },
    { "store",            "VENDOR" },
    { "costs",            "VENDOR" },

    -- Quests
    { "quest reward",     "QUEST" },
    { "quest",            "QUEST" },
    { "campaign",         "QUEST" },

    -- Achievements
    { "achievement",      "ACHIEVEMENT" },
    { "feat of strength", "ACHIEVEMENT" },

    -- Professions
    { "tailoring",        "PROFESSION" },
    { "blacksmithing",    "PROFESSION" },
    { "leatherworking",   "PROFESSION" },
    { "engineering",      "PROFESSION" },
    { "enchanting",       "PROFESSION" },
    { "alchemy",          "PROFESSION" },
    { "inscription",      "PROFESSION" },
    { "jewelcrafting",    "PROFESSION" },
    { "cooking",          "PROFESSION" },
    { "herbalism",        "PROFESSION" },
    { "mining",           "PROFESSION" },
    { "skinning",         "PROFESSION" },
    { "fishing",          "PROFESSION" },
    { "crafted",          "PROFESSION" },
    { "recipe",           "PROFESSION" },
    { "profession",       "PROFESSION" },

    -- PvP
    { "pvp",              "PVP" },
    { "rated",            "PVP" },
    { "arena",            "PVP" },
    { "battleground",     "PVP" },
    { "honor",            "PVP" },
    { "conquest",         "PVP" },

    -- Drops / loot
    { "drops from",       "DROP" },
    { "drop",             "DROP" },
    { "contained in",     "DROP" },
    { "looted from",      "DROP" },
    { "treasure",         "DROP" },
    { "rare",             "DROP" },
    { "world boss",       "DROP" },
    { "dungeon",          "DROP" },
    { "raid",             "DROP" },

    -- First acquisition / bonus (treat as vendor-like)
    { "first acquisition", "VENDOR" },
}

--- Parse cost from a source string into a sortable numeric value.
--- Unparsable/unknown costs default to 99999999.
---@param costStr string|nil (e.g. from hardcoded "50g")
---@param sourceText string|nil (e.g. from API "Costs 5000 Gold")
---@return number costValue
function Topnight:ParseCost(costStr, sourceText)
    local val = 99999999
    
    if costStr then
        local s = costStr:lower()
        local num = s:match("([%d,%.]+)")
        if num then
            num = tonumber((num:gsub("[,%.]", "")))
            if num then val = num end
        end
    elseif sourceText then
        local s = sourceText:lower()
        -- e.g. "Costs 5000 Gold" or "5000g"
        local num = s:match("costs?%s*([%d,%.]+)") or s:match("([%d,%.]+)%s*g") or s:match("([%d,%.]+)%s*gold")
        if num then
            num = tonumber((num:gsub("[,%.]", "")))
            if num then val = num end
        end
    end

    return val
end

--- Classify a sourceText string into a structured source type.
---@param sourceText string|nil
---@return table { type = string, detail = string|nil }
function Topnight:ClassifySourceText(sourceText)
    if not sourceText or sourceText == "" then
        return { type = "UNKNOWN" }
    end

    -- Create a cleaned version of the string for parsing
    local cleanText = sourceText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    local lower = cleanText:lower()

    for _, entry in ipairs(SOURCE_PATTERNS) do
        if lower:find(entry[1], 1, true) then
            local result = {
                type   = entry[2],
                detail = sourceText,  -- preserve original text with formatting
            }
            
            -- Attempt to extract standard fields from Blizzard's formatting
            if result.type == "VENDOR" then
                -- Match "Vendor: Name\n" or "Sold by: Name\n"
                local npc = cleanText:match("Vendor:%s*([^%c]+)") or cleanText:match("Sold by:%s*([^%c]+)")
                if npc then result.npcName = strtrim(npc) end
            end
            
            -- Extract Zone: Name, safely handling WoW client newline quirks (\r, \n, or both)
            local zone = cleanText:match("Zone:%s*([^\r\n|]+)")
            
            if zone then result.zone = strtrim(zone) end
            
            return result
        end
    end

    return { type = "UNKNOWN", detail = sourceText }
end

-- ---------------------------------------------------------------------------
-- Custom Event System
-- ---------------------------------------------------------------------------
local customCallbacks = {}

--- Register a callback for a custom Topnight event
---@param eventName string
---@param callback function
function Topnight:RegisterCallback(eventName, callback)
    customCallbacks[eventName] = customCallbacks[eventName] or {}
    table.insert(customCallbacks[eventName], callback)
end

--- Fire a custom Topnight event
---@param eventName string
function Topnight:FireCallback(eventName, ...)
    local cbs = customCallbacks[eventName]
    if cbs then
        for _, cb in ipairs(cbs) do
            cb(self, ...)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Catalog Scanner — async pattern
-- SearchCatalogCategories triggers a search; results arrive via event
-- ---------------------------------------------------------------------------

--- Dump all C_HousingCatalog and C_Housing functions for diagnostics
function Topnight:DumpHousingAPI()
    self:PrintInfo("C_HousingCatalog API:")
    if not C_HousingCatalog then
        self:PrintWarning("  C_HousingCatalog is nil")
    else
        local funcs = {}
        for k, v in pairs(C_HousingCatalog) do
            table.insert(funcs, k .. " (" .. type(v) .. ")")
        end
        table.sort(funcs)
        for _, f in ipairs(funcs) do
            self:Print("  " .. self.Colors.ACCENT .. f .. self.Colors.RESET)
        end
        if #funcs == 0 then self:Print("  (empty)") end
    end

    self:PrintInfo("C_Housing API:")
    if not C_Housing then
        self:PrintWarning("  C_Housing is nil")
    else
        local funcs = {}
        for k, v in pairs(C_Housing) do
            table.insert(funcs, k .. " (" .. type(v) .. ")")
        end
        table.sort(funcs)
        for _, f in ipairs(funcs) do
            self:Print("  " .. self.Colors.ACCENT .. f .. self.Colors.RESET)
        end
        if #funcs == 0 then self:Print("  (empty)") end
    end
end

--- Trigger catalog scan — async pattern using catalogSearcher
--- Pattern matched from Plumber addon's Housing_API.lua
function Topnight:ScanCatalog(silent)
    if not silent then self:PrintInfo("Scanning decor catalog...") end

    if not C_HousingCatalog then
        if not silent then self:PrintWarning("C_HousingCatalog API not available.") end
        return
    end

    if not C_HousingCatalog.CreateCatalogSearcher then
        if not silent then self:PrintWarning("CreateCatalogSearcher not found.") end
        return
    end

    -- Create and configure the searcher in one block (matching Plumber's pattern)
    -- Store on self to prevent garbage collection
    local self_ref = self
    local ok, err = pcall(function()
        self_ref.catalogSearcher = C_HousingCatalog.CreateCatalogSearcher()
        local searcher = self_ref.catalogSearcher
        
        searcher:SetOwnedOnly(false)
        searcher:SetEditorModeContext(Enum.HouseEditorMode.BasicDecor)
        searcher:SetCollected(true)
        searcher:SetUncollected(true)
        searcher:SetFirstAcquisitionBonusOnly(false)

        -- Set the results callback — fires when async search completes
        searcher:SetResultsUpdatedCallback(function()
            if not silent then self_ref:PrintInfo("Search results received. Processing...") end
            self_ref:ProcessSearchResults(searcher, silent)
        end)

        -- Trigger the search
        searcher:SetSearchText()
        searcher:RunSearch()
    end)

    if not ok then
        self:PrintWarning("Catalog scan setup failed: " .. tostring(err))
        return
    end

    if not silent then self:PrintInfo("Search running (async)... waiting for results.") end

    -- Timeout fallback
    C_Timer.After(10, function()
        if not self_ref.collectionReady then
            if not silent then self_ref:PrintWarning("Search timed out after 10s. Try /tn scan again.") end
        end
    end)
end

--- Helper: describe all fields of a table for diagnostics
function Topnight:DescribeFields(t, prefix)
    if type(t) ~= "table" then
        self:Print("  " .. self.Colors.INFO .. (prefix or "") .. type(t) .. " = " .. tostring(t) .. self.Colors.RESET)
        return
    end
    local fields = {}
    for k, v in pairs(t) do
        local desc = tostring(k) .. " (" .. type(v) .. ")"
        if type(v) == "string" then
            desc = desc .. ' = "' .. (v:sub(1, 40)) .. '"'
        elseif type(v) == "number" or type(v) == "boolean" then
            desc = desc .. " = " .. tostring(v)
        elseif type(v) == "table" then
            desc = desc .. " (#" .. #v .. ")"
        end
        table.insert(fields, desc)
    end
    table.sort(fields)
    for _, f in ipairs(fields) do
        self:Print("  " .. self.Colors.INFO .. (prefix or "") .. f .. self.Colors.RESET)
    end
    if #fields == 0 then
        self:Print("  " .. self.Colors.INFO .. (prefix or "") .. "(empty table)" .. self.Colors.RESET)
    end
end

--- Process search results after async callback fires
function Topnight:ProcessSearchResults(searcher, silent)
    -- Clear caches
    self.catalogCache = {}
    self.categoryCache = {}
    self.categoryOrder = {}

    -- Get all search results
    local results = searcher:GetCatalogSearchResults()
    if not results or type(results) ~= "table" then
        self:PrintWarning("GetCatalogSearchResults returned: " .. type(results))
        return
    end

    if not silent then self:PrintInfo("Got " .. #results .. " entries. Building cache...") end

    -- Step 1: Build subcategory map from category hierarchy
    local subcatMap = {}        -- subcatID → {name, parentCatName, icon}
    -- Step 1: In Midnight Beta, SearchCatalogCategories is broken/empty.
    -- However, the items themselves report their categoryIDs table.
    -- We can build our categoryCache dynamically as we process items.
    
    if not silent then self:PrintInfo("Skipping subcategory map generation due to API changes.") end

    -- Step 2: Dump first entry fields for diagnostics (one-time)
    if not silent and #results > 0 then
        self:PrintInfo("First search result entry fields:")
        self:DescribeFields(results[1], "  entry.")

        -- Also dump first info object
        local firstRID = results[1].recordID
        if firstRID then
            local firstInfo
            pcall(function()
                firstInfo = C_HousingCatalog.GetCatalogEntryInfoByRecordID(
                    results[1].entryType or 1, firstRID, true)
            end)
            if firstInfo then
                self:PrintInfo("First GetCatalogEntryInfoByRecordID fields:")
                self:DescribeFields(firstInfo, "  info.")
            end
        end
    end

    -- Step 3: Process all entries
    local totalItems = 0
    local totalOwned = 0
    local categorySet = {}  -- track unique categories

    for _, entry in ipairs(results) do
        local recordID = entry.recordID
        if recordID then
            local entryType = entry.entryType or 1
            local info
            pcall(function()
                info = C_HousingCatalog.GetCatalogEntryInfoByRecordID(entryType, recordID, true)
            end)

            if not info then
                pcall(function()
                    info = C_HousingCatalog.GetCatalogEntryInfoByRecordID(entryType, recordID, false)
                end)
            end

            local itemName = info and info.name or ("Decor #" .. recordID)
            
            local itemIcon = "Interface\\Icons\\INV_Misc_QuestionMark"
            local itemID = info and info.itemID or nil
            if itemID then
                local iconID = C_Item.GetItemIconByID(itemID)
                if iconID then
                    itemIcon = iconID
                end
            elseif info and info.icon then
                itemIcon = info.icon
            end
            local isOwned = info and info.quantity and info.quantity > 0 or false
            local sourceText = info and info.sourceText or nil

            -- Determine category from entry or info fields
            local subCatID = 0
            if info and info.subcategoryIDs and #info.subcategoryIDs > 0 then
                subCatID = info.subcategoryIDs[1]
            elseif entry.subcategoryID then
                subCatID = entry.subcategoryID
            end

            local catID = subCatID
            local catName = "Unknown"
            local catIcon = nil

            if subCatID ~= 0 and subcatMap[subCatID] then
                -- Group by Top-Level parent instead of granular subcategory
                catID = subcatMap[subCatID].parentCatID
                catName = subcatMap[subCatID].parentCatName
                catIcon = subcatMap[subCatID].parentCatIcon
            elseif info and info.categoryIDs and #info.categoryIDs > 0 then
                -- Fallback to top-level category if we didn't find a mapped subcategory
                catID = info.categoryIDs[1]
                local catInfo
                pcall(function() catInfo = C_HousingCatalog.GetCatalogCategoryInfo(catID) end)
                if catInfo then
                    catName = catInfo.name
                    catIcon = catInfo.icon
                end
            elseif info and info.categoryName then
                catName = info.categoryName
                catIcon = info.icon or nil
            elseif entry.categoryName then
                catName = entry.categoryName
            end

            -- Build source info: prefer hardcoded, then auto-classify
            local sourceInfo = self.DecorSources[recordID]
            if sourceInfo then
                -- Hardcoded entry — use as-is
                if sourceText and not sourceInfo.sourceText then
                    sourceInfo.sourceText = sourceText
                end
            else
                -- Auto-classify from the API sourceText
                sourceInfo = self:ClassifySourceText(sourceText)
            end

            local costVal = self:ParseCost(sourceInfo and sourceInfo.cost, sourceText)

            self.catalogCache[recordID] = {
                entryID      = recordID,
                name         = itemName,
                icon         = itemIcon,
                categoryID   = catID,
                categoryName = catName,
                isOwned      = isOwned,
                sourceType   = sourceInfo.type,
                sourceInfo   = sourceInfo,
                sourceText   = sourceText,
                itemID       = info and info.itemID or nil,
                quantity     = info and info.quantity or 0,
                costValue    = costVal,
            }

            -- Track categories
            if not categorySet[catID] then
                categorySet[catID] = {
                    categoryID = catID,
                    name       = catName,
                    icon       = catIcon,
                    numTotal   = 0,
                    numOwned   = 0,
                }
                table.insert(self.categoryOrder, catID)
            end
            categorySet[catID].numTotal = categorySet[catID].numTotal + 1
            if isOwned then
                categorySet[catID].numOwned = categorySet[catID].numOwned + 1
                totalOwned = totalOwned + 1
            end
            totalItems = totalItems + 1
        end
    end

    -- Store category cache
    self.categoryCache = categorySet
    self.collectionReady = true

    -- Build final sorted category list based on category names
    table.sort(self.categoryOrder, function(a, b)
        local cA = self.categoryCache[a]
        local cB = self.categoryCache[b]
        if cA and cB and cA.name and cB.name then
            return cA.name < cB.name
        end
        return false
    end)

    if not silent then
        self:PrintSuccess(string.format("Scan complete: %d items across %d categories (%d owned).",
            totalItems, #self.categoryOrder, totalOwned))
    end

    -- Check for newly acquired items
    self:CheckNewAcquisitions()

    -- Ensure we capture housing stats for this character
    self:UpdateAltHousingData()

    -- Fire update event for UI modules
    self:FireCallback("TOPNIGHT_COLLECTION_UPDATED")
end




-- ---------------------------------------------------------------------------
-- New Acquisition Detection
-- ---------------------------------------------------------------------------
local previousOwnedSet = {}

function Topnight:CheckNewAcquisitions()
    if not self.db then return end

    local newItems = {}

    for entryID, data in pairs(self.catalogCache) do
        if data.isOwned and not previousOwnedSet[entryID] then
            if self.collectionReady then
                table.insert(newItems, data)
            end
            previousOwnedSet[entryID] = true
        end
    end

    for _, item in ipairs(newItems) do
        -- Just announce it to chat, don't store it in the database anymore
        if self.db.shoppingList[item.entryID] then
            self.db.shoppingList[item.entryID] = nil
            self:PrintSuccess("✓ Acquired: " .. self.Colors.ACCENT .. item.name .. self.Colors.RESET
                .. " (removed from shopping list)")
        else
            self:PrintSuccess("✓ New decor: " .. self.Colors.ACCENT .. item.name .. self.Colors.RESET)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Quick Wins API
-- ---------------------------------------------------------------------------

--- Get a short list of unowned items that are cheap/easy, and not on the shopping list
---@param count number
---@return table[] list of catalog entries
function Topnight:GetQuickWins(count)
    if not self.collectionReady or not self.db then return {} end
    count = count or 5
    
    -- Get all missing items
    local missing = self:GetFilteredItems({ showOwned = false, showMissing = true, sortBy = "EASIEST" })
    
    local quickWins = {}
    local addedBaseNames = {}

    local function getBaseName(name)
        -- If the item has a quoted title (e.g., "Autumnal Eversong" Painting), group by the quote
        local quoted = name:match('"([^"]+)"')
        if quoted then return quoted end
        
        -- Otherwise, strip common variation keywords from the name
        return name:gsub(" Unframed", "")
                   :gsub(" Blueprint", "")
                   :gsub(" Pattern", "")
                   :gsub(" Recipe", "")
                   :gsub(" Schematic", "")
    end

    for _, item in ipairs(missing) do
        local baseName = getBaseName(item.name)
        
        -- Skip if on shopping list, or if we already added a variation of this item
        if not self.db.shoppingList[item.entryID] and not addedBaseNames[baseName] then
            -- We want quick wins to only include Vendor items, or things with a known cost
            if item.sourceType == "VENDOR" then
                table.insert(quickWins, item)
                addedBaseNames[baseName] = true
                if #quickWins >= count then
                    break
                end
            end
        end
    end
    
    -- If we don't have enough Vendor items, grab any remaining easy ones
    if #quickWins < count then
        for _, item in ipairs(missing) do
            local baseName = getBaseName(item.name)
            if not self.db.shoppingList[item.entryID] and item.sourceType ~= "VENDOR" and not addedBaseNames[baseName] then
                table.insert(quickWins, item)
                addedBaseNames[baseName] = true
                if #quickWins >= count then
                    break
                end
            end
        end
    end

    return quickWins
end

-- ---------------------------------------------------------------------------
-- Collection Stats API
-- ---------------------------------------------------------------------------

--- Get overall collection statistics
---@return table { total, owned, percentage }
function Topnight:GetCollectionStats()
    local total = 0
    local owned = 0
    for _, data in pairs(self.catalogCache) do
        total = total + 1
        if data.isOwned then
            owned = owned + 1
        end
    end
    local pct = total > 0 and (owned / total * 100) or 0
    return { total = total, owned = owned, percentage = pct }
end

--- Get stats for a specific category
---@param categoryID number
---@return table|nil { total, owned, percentage }
function Topnight:GetCategoryStats(categoryID)
    local cat = self.categoryCache[categoryID]
    if not cat then return nil end
    local pct = cat.numTotal > 0 and (cat.numOwned / cat.numTotal * 100) or 0
    return { total = cat.numTotal, owned = cat.numOwned, percentage = pct }
end

--- Print a breakdown of source type counts for diagnostics
function Topnight:PrintSourceBreakdown()
    if not self.collectionReady then
        self:PrintWarning("Collection not scanned yet. Run /tn scan first.")
        return
    end

    local counts = {}
    local total = 0
    for _, data in pairs(self.catalogCache) do
        local sType = data.sourceType or "UNKNOWN"
        counts[sType] = (counts[sType] or 0) + 1
        total = total + 1
    end

    self:Print(self.Colors.ACCENT .. "Source type breakdown:" .. self.Colors.RESET)
    -- Sort by count descending
    local sorted = {}
    for sType, count in pairs(counts) do
        table.insert(sorted, { type = sType, count = count })
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)

    for _, entry in ipairs(sorted) do
        local pct = total > 0 and (entry.count / total * 100) or 0
        local typeInfo = self.SOURCE_TYPES[entry.type] or self.SOURCE_TYPES.UNKNOWN
        self:Print(string.format("  %s%-12s%s  %d  (%.1f%%)",
            self.Colors.ACCENT, typeInfo.label, self.Colors.RESET,
            entry.count, pct))
    end
    self:Print(string.format("  %sTotal:%s  %d items",
        self.Colors.INFO, self.Colors.RESET, total))
end

--- Get filtered items from the catalog cache
---@param filters table|nil { categoryID, showOwned, showMissing, sourceFilter, searchText }
---@return table[] ordered list of catalog entries
function Topnight:GetFilteredItems(filters)
    filters = filters or {}
    local results = {}

    for _, data in pairs(self.catalogCache) do
        local pass = true

        -- Category filter
        if filters.categoryID and data.categoryID ~= filters.categoryID then
            pass = false
        end

        -- Owned/Missing filter
        if not filters.showOwned and data.isOwned then
            pass = false
        end
        if not filters.showMissing and not data.isOwned then
            pass = false
        end

        -- Source type filter
        if filters.sourceFilter and filters.sourceFilter ~= "ALL" then
            if data.sourceType ~= filters.sourceFilter then
                pass = false
            end
        end

        -- Text search filter
        if filters.searchText and filters.searchText ~= "" then
            local search = filters.searchText:lower()
            if not data.name:lower():find(search, 1, true) then
                pass = false
            end
        end

        if pass then
            table.insert(results, data)
        end
    end

    -- Sort results
    local sortBy = filters.sortBy or "NAME"
    if sortBy == "NAME" then
        table.sort(results, function(a, b) return a.name < b.name end)
    elseif sortBy == "CATEGORY" then
        table.sort(results, function(a, b)
            if a.categoryName == b.categoryName then return a.name < b.name end
            return a.categoryName < b.categoryName
        end)
    elseif sortBy == "SOURCE" then
        table.sort(results, function(a, b)
            if a.sourceType == b.sourceType then return a.name < b.name end
            return a.sourceType < b.sourceType
        end)
    elseif sortBy == "EASIEST" then
        table.sort(results, function(a, b)
            local pa = (self.SOURCE_TYPES[a.sourceType] or self.SOURCE_TYPES.UNKNOWN).priority
            local pb = (self.SOURCE_TYPES[b.sourceType] or self.SOURCE_TYPES.UNKNOWN).priority
            if pa == pb then
                -- Hybrid Option 3: Sort by Cost before Name
                local costA = a.costValue or 99999999
                local costB = b.costValue or 99999999
                if costA == costB then
                    return a.name < b.name
                end
                return costA < costB
            end
            return pa < pb
        end)
    elseif sortBy == "CHEAPEST" then
        table.sort(results, function(a, b)
            if a.costValue == b.costValue then return a.name < b.name end
            return a.costValue < b.costValue
        end)
    end

    return results
end

-- ---------------------------------------------------------------------------
-- Shopping List Helpers
-- ---------------------------------------------------------------------------

--- Add an item to the shopping list
---@param entryID number
function Topnight:AddToShoppingList(entryID)
    if not self.db then return end
    local item = self.catalogCache[entryID]
    if not item then
        self:PrintError("Item not found in catalog.")
        return
    end
    if item.isOwned then
        self:PrintWarning("You already own this item!")
        return
    end
    self.db.shoppingList[entryID] = true
    self:PrintSuccess("Added to shopping list: " .. self.Colors.ACCENT .. item.name .. self.Colors.RESET)
    self:FireCallback("TOPNIGHT_SHOPPING_LIST_UPDATED")
end

--- Remove an item from the shopping list
---@param entryID number
function Topnight:RemoveFromShoppingList(entryID)
    if not self.db then return end
    self.db.shoppingList[entryID] = nil
    self:PrintInfo("Removed from shopping list.")
    self:FireCallback("TOPNIGHT_SHOPPING_LIST_UPDATED")
end

--- Get shopping list items grouped by source type
---@return table { [sourceType] = { items = {}, label = "", count = n } }
function Topnight:GetShoppingListGrouped()
    if not self.db then return {} end

    local groups = {}
    for entryID, _ in pairs(self.db.shoppingList) do
        local item = self.catalogCache[entryID]
        if item and not item.isOwned then
            local sType = item.sourceType or "UNKNOWN"
            if not groups[sType] then
                local typeInfo = self.SOURCE_TYPES[sType] or self.SOURCE_TYPES.UNKNOWN
                groups[sType] = {
                    sourceType = sType,
                    label      = typeInfo.label,
                    icon       = typeInfo.icon,
                    priority   = typeInfo.priority,
                    items      = {},
                    count      = 0,
                }
            end
            table.insert(groups[sType].items, item)
            groups[sType].count = groups[sType].count + 1
        end
    end

    -- Convert to ordered list sorted by priority
    local ordered = {}
    for _, group in pairs(groups) do
        -- Sort items within group alphabetically
        table.sort(group.items, function(a, b) return a.name < b.name end)
        table.insert(ordered, group)
    end
    table.sort(ordered, function(a, b) return a.priority < b.priority end)

    return ordered
end

-- ---------------------------------------------------------------------------
-- Teleport Home Helper
-- ---------------------------------------------------------------------------

function Topnight:TeleportHome()
    -- C_Housing.TeleportHome is a protected Blizzard-only function.
    -- Instead, we open the Housing UI where the built-in teleport button lives.

    -- Try toggling the Housing UI panel (Blizzard's built-in)
    local opened = false
    pcall(function()
        if ToggleHousingUI then
            ToggleHousingUI()
            opened = true
        elseif HousingUI and HousingUI.Toggle then
            HousingUI.Toggle()
            opened = true
        elseif C_Housing and C_Housing.IsHousingServiceEnabled and C_Housing.IsHousingServiceEnabled() then
            -- Try the micro menu button for housing
            if HousingMicroButton and HousingMicroButton.Click then
                HousingMicroButton:Click()
                opened = true
            end
        end
    end)

    if opened then
        self:PrintInfo("Housing UI opened — use the teleport button inside.")
    else
        self:PrintInfo("Open the Housing UI from the micro menu bar to teleport home.")
    end
end

-- ---------------------------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------------------------

function Topnight:InitHousingData()
    self:Debug("Housing data layer initialized.")
end

