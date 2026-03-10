-- =============================================================================
-- Topnight - EconomyScanner.lua
-- Feature: "Quick Hustle" Economy Scanner
-- Scans bags for items with high AH value compared to vendor value
-- =============================================================================

local ADDON_NAME, Topnight = ...

-- ---------------------------------------------------------------------------
-- Variables & State
-- ---------------------------------------------------------------------------
local quickWins = {}
local lastScanTime = 0
local SCAN_COOLDOWN = 10 -- Minimum seconds between full bag scans

-- ---------------------------------------------------------------------------
-- External Pricing API Wrappers
-- ---------------------------------------------------------------------------

--- Safely gets the auction house price of an item using available addons
--- @param itemLink string The item link to check
--- @return number|nil The AH price in copper, or nil if unavailable
local function GetAHPrice(itemLink)
    if not itemLink then return nil end

    -- Try TSM (TradeSkillMaster) First
    if TSM_API and TSM_API.GetCustomPriceValue then
        -- Prefer DBMarket (14 day moving average)
        local price = TSM_API.GetCustomPriceValue("DBMarket", itemLink)
        if price and price > 0 then return price end
    end

    -- Try Auctionator
    if Auctionator and Auctionator.API and Auctionator.API.v1.GetAuctionPriceByItemLink then
        local price = Auctionator.API.v1.GetAuctionPriceByItemLink(ADDON_NAME, itemLink)
        if price and price > 0 then return price end
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- Scanning Logic
-- ---------------------------------------------------------------------------

--- Scans the player's bags and calculates the profitability of items
local function ScanBagsForHustles()
    local currentTime = GetTime()
    if currentTime - lastScanTime < SCAN_COOLDOWN then return end
    lastScanTime = currentTime

    local newWins = {}

    -- Iterate through all standard bags (0 to 4)
    for bag = 0, NUM_BAG_SLOTS do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
            if itemInfo and itemInfo.hyperlink then
                local itemID = itemInfo.itemID
                local link = itemInfo.hyperlink
                local stackCount = itemInfo.stackCount or 1

                -- Get vendor sell price
                local _, _, _, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(link)
                
                if sellPrice then
                    local ahPrice = GetAHPrice(link)

                    -- If we have an AH price and it's significantly higher than the vendor price
                    if ahPrice and ahPrice > (sellPrice * 2) then -- Arbitrary threshold: AH is at least 2x vendor
                        local totalVendor = sellPrice * stackCount
                        local totalAH = ahPrice * stackCount
                        local profit = totalAH - totalVendor
                        
                        -- Only consider things that make at least some meaningful gold (e.g. >10g profit per stack)
                        if profit > 100000 then 
                            table.insert(newWins, {
                                itemID = itemID,
                                link = link,
                                icon = itemInfo.iconFileID,
                                stackCount = stackCount,
                                vendorTotal = totalVendor,
                                ahTotal = totalAH,
                                profit = profit,
                                profitMargin = (ahPrice / math.max(sellPrice, 1)) -- Ratio
                            })
                        end
                    end
                end
            end
        end
    end

    -- Sort the results by highest pure profit
    table.sort(newWins, function(a, b)
        return a.profit > b.profit
    end)

    quickWins = newWins
    
    -- Notify the UI that new economy data is ready
    if Topnight.RefreshControlPanel then
        Topnight:RefreshControlPanel()
    end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Get the top N economy quick wins
--- @param limit number The maximum number of items to return
--- @return table A list of high-value items
function Topnight:GetEconomyQuickWins(limit)
    limit = limit or 3
    local results = {}
    for i = 1, math.min(limit, #quickWins) do
        table.insert(results, quickWins[i])
    end
    return results
end

--- Force a manual scan of the bags
function Topnight:ScanEconomyHustles()
    lastScanTime = 0 -- bypass cooldown for manual scans
    ScanBagsForHustles()
end

-- ---------------------------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------------------------

function Topnight:InitEconomyScanner()
    self:RegisterEvent("BAG_UPDATE_DELAYED", function()
        -- Wait for bag updates to settle natively, then trigger our unified scan
        ScanBagsForHustles()
    end)
    
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        -- Initial scan when logging in
        C_Timer.After(5, function() ScanBagsForHustles() end)
    end)

    self:Debug("Economy Scanner initialized.")
end
