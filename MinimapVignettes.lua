-- =============================================================================
-- Topnight - MinimapVignettes.lua
-- Feature: Highlight Midnight zone-specific vignettes on the minimap
-- Overlays custom Topnight-themed icons on treasure/loot vignettes
-- =============================================================================

local ADDON_NAME, Topnight = ...

-- ---------------------------------------------------------------------------
-- Midnight Vignette Name Lookup
-- Vignettes whose names contain these keywords get custom icons.
-- All comparisons are case-insensitive.
-- ---------------------------------------------------------------------------
local MIDNIGHT_VIGNETTE_KEYWORDS = {
    "coalesced light",
    "haven's treasure",
    "quel'thalas relic",
    "sunwell fragment",
    "scattered moonlight",
    "forgotten amani cache"
}

-- Custom icon color (Pink)
local ICON_R, ICON_G, ICON_B = 1.0, 0.41, 0.71

-- ---------------------------------------------------------------------------
-- Rotateable Minimap Support
-- The minimap can be rotated. We need to counter-rotate our pin positions.
-- ---------------------------------------------------------------------------
local function GetMinimapShape()
    -- The default minimap is circular
    return "ROUND"
end

-- ---------------------------------------------------------------------------
-- Pin Frame Pool
-- ---------------------------------------------------------------------------
local pinPool = nil
local activePins = {} -- vignetteGUID -> pin frame
local eventFrame = nil

-- ---------------------------------------------------------------------------
-- Icon Options (cycle with /tn icon)
-- ---------------------------------------------------------------------------
local ICON_OPTIONS = {
    { atlas = "Warfront-NeutralHero",        label = "Skull" },
    { atlas = "VignetteKill",                label = "Crossbones" },
    { atlas = "Ping_Marker_Star",            label = "Star" },
}

local currentIconIndex = 1

local function ApplyIconToPin(pin)
    local option = ICON_OPTIONS[currentIconIndex]
    local atlasOk = pcall(function()
        pin.icon:SetAtlas(option.atlas, false)
    end)
    if not atlasOk then
        pin.icon:SetTexture("Interface\\Icons\\INV_Misc_StarMap")
    end
    pin.icon:SetVertexColor(ICON_R, ICON_G, ICON_B, 1.0)
    pin.icon:SetSize(20, 20)
end

-- ---------------------------------------------------------------------------
-- Pin Factory
-- ---------------------------------------------------------------------------
local function CreatePinFrame()
    local pin = CreateFrame("Frame", nil, Minimap)
    pin:SetSize(24, 24)
    pin:SetFrameStrata("HIGH")
    pin:SetFrameLevel(15)

    -- Subtle pink glow
    pin.glow = pin:CreateTexture(nil, "BACKGROUND", nil, 0)
    pin.glow:SetPoint("CENTER")
    pin.glow:SetSize(30, 30)
    pin.glow:SetTexture("Interface\\GLUES\\Models\\UI_BloodElf\\bloodelf_lensflare")
    pin.glow:SetVertexColor(ICON_R, ICON_G, ICON_B, 0.7)
    pin.glow:SetBlendMode("ADD")

    -- Main icon
    pin.icon = pin:CreateTexture(nil, "ARTWORK", nil, 7)
    pin.icon:SetPoint("CENTER")
    ApplyIconToPin(pin)

    -- Tooltip
    pin:EnableMouse(true)
    pin:SetScript("OnEnter", function(self)
        if self.vignetteName then
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:AddLine(Topnight.Colors.PREFIX .. "Topnight|r")
            GameTooltip:AddLine(self.vignetteName, 1, 1, 1)
            GameTooltip:AddLine(Topnight.Colors.INFO .. "Midnight Collectible|r")
            GameTooltip:Show()
        end
    end)
    pin:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return pin
end

local function ResetPinFrame(_, pin)
    pin:Hide()
    pin:ClearAllPoints()
    pin.vignetteGUID = nil
    pin.vignetteName = nil
    pin.vignetteX = nil
    pin.vignetteY = nil
end

-- ---------------------------------------------------------------------------
-- Name Matching
-- ---------------------------------------------------------------------------
local function IsMatchingVignette(info)
    if not info or not info.name then return false end

    local lowerName = info.name:lower()

    for _, keyword in ipairs(MIDNIGHT_VIGNETTE_KEYWORDS) do
        if lowerName:find(keyword, 1, true) then
            return true
        end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- Minimap Coordinate Math
-- Converts map-relative coordinates to minimap pixel offsets.
-- ---------------------------------------------------------------------------
local cachedMapID = nil
local cachedMapWidth = nil
local cachedMapHeight = nil

local function GetMapWorldSize(mapID)
    if cachedMapID == mapID and cachedMapWidth then
        return cachedMapWidth, cachedMapHeight
    end

    local w, h
    pcall(function()
        w, h = C_Map.GetMapWorldSize(mapID)
    end)

    if w and w > 0 and h and h > 0 then
        cachedMapID = mapID
        cachedMapWidth = w
        cachedMapHeight = h
        Topnight:Debug(string.format("Map %d world size: %.0f x %.0f yards", mapID, w, h))
        return w, h
    end

    -- Fallback: estimate from a known map.
    -- Eversong / Midnight zone maps are roughly 3000-5000 yards
    cachedMapID = mapID
    cachedMapWidth = 3500
    cachedMapHeight = 2333
    Topnight:Debug(string.format("Map %d using fallback size: %.0f x %.0f yards", mapID, cachedMapWidth, cachedMapHeight))
    return cachedMapWidth, cachedMapHeight
end

local function PositionPinOnMinimap(pin)
    if not pin.vignetteX or not pin.vignetteY then
        pin:Hide()
        return
    end

    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then
        pin:Hide()
        return
    end

    local playerPos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not playerPos then
        pin:Hide()
        return
    end

    local px, py = playerPos:GetXY()
    if not px or (px == 0 and py == 0) then
        pin:Hide()
        return
    end

    -- Map coordinate deltas (normalized 0-1)
    local dx = pin.vignetteX - px
    local dy = pin.vignetteY - py

    -- Convert to yard offsets using the map's world size
    local mapWidth, mapHeight = GetMapWorldSize(mapID)
    local yardDX = dx * mapWidth
    local yardDY = dy * mapHeight

    -- Minimap visible range depends on zoom level and indoors/outdoors
    -- Minimap:GetViewRadius() returns the radius in yards (if available)
    local visibleRadius
    pcall(function()
        visibleRadius = C_Minimap.GetViewRadius()
    end)
    if not visibleRadius or visibleRadius <= 0 then
        -- Fallback: approximate based on zoom level
        local zoom = Minimap:GetZoom() or 0
        local yardsByZoom = {
            [0] = 233, [1] = 200, [2] = 166,
            [3] = 133, [4] = 100, [5] = 66,
        }
        visibleRadius = yardsByZoom[zoom] or 166
    end

    -- Scale from yards to minimap pixels
    local minimapRadius = Minimap:GetWidth() / 2

    -- Handle minimap rotation
    local rotateMinimap = GetCVar("rotateMinimap") == "1"
    if rotateMinimap then
        local facing = GetPlayerFacing() or 0
        local sinF = math.sin(facing)
        local cosF = math.cos(facing)
        local rotX = yardDX * cosF - yardDY * sinF
        local rotY = yardDX * sinF + yardDY * cosF
        yardDX = rotX
        yardDY = rotY
    end

    local scale = minimapRadius / visibleRadius
    local pinX = yardDX * scale
    local pinY = -yardDY * scale  -- Y is inverted (map Y goes down, screen Y goes up)

    -- Check if pin is within the minimap circle
    local dist = math.sqrt(pinX * pinX + pinY * pinY)
    if dist > minimapRadius - 6 then
        -- Outside visible area — hide or clamp to edge
        if dist > 0 then
            -- Clamp to edge so player can see direction
            local clampDist = minimapRadius - 8
            pinX = pinX / dist * clampDist
            pinY = pinY / dist * clampDist
        else
            pin:Hide()
            return
        end
    end

    pin:ClearAllPoints()
    pin:SetPoint("CENTER", Minimap, "CENTER", pinX, pinY)
    pin:Show()
end

-- ---------------------------------------------------------------------------
-- Vignette Scanning & Pin Update
-- ---------------------------------------------------------------------------
local function UpdateAllPins()
    local settings = Topnight:GetSetting("minimapVignettes")
    if not settings or not settings.enabled then
        for guid, pin in pairs(activePins) do
            pin:Hide()
            if pinPool then pinPool:Release(pin) end
            activePins[guid] = nil
        end
        return
    end

    local vignetteGUIDs = C_VignetteInfo.GetVignettes()
    if not vignetteGUIDs then return end

    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end

    -- Build set of currently matching vignettes
    local currentMatches = {}

    for _, guid in ipairs(vignetteGUIDs) do
        local info = C_VignetteInfo.GetVignetteInfo(guid)
        if info and info.onMinimap and IsMatchingVignette(info) then
            local pos = C_VignetteInfo.GetVignettePosition(guid, mapID)
            if pos then
                local vx, vy = pos:GetXY()
                if vx and vy then
                    currentMatches[guid] = {
                        name = info.name,
                        x = vx,
                        y = vy,
                    }
                end
            end
        end
    end

    -- Remove stale pins
    for guid, pin in pairs(activePins) do
        if not currentMatches[guid] then
            pin:Hide()
            pinPool:Release(pin)
            activePins[guid] = nil
        end
    end

    -- Create/update pins
    for guid, data in pairs(currentMatches) do
        local pin = activePins[guid]
        if not pin then
            pin = pinPool:Acquire()
            pin.vignetteGUID = guid
            activePins[guid] = pin
        end

        pin.vignetteName = data.name
        pin.vignetteX = data.x
        pin.vignetteY = data.y

        PositionPinOnMinimap(pin)
    end
end

-- ---------------------------------------------------------------------------
-- OnUpdate: reposition pins as the player moves
-- ---------------------------------------------------------------------------
local updateElapsed = 0
local scanElapsed = 0
local POSITION_INTERVAL = 1 / 30  -- ~30fps repositioning
local SCAN_INTERVAL = 0.5         -- full scan every 0.5s

local function OnUpdate(self, elapsed)
    updateElapsed = updateElapsed + elapsed
    scanElapsed = scanElapsed + elapsed

    if scanElapsed >= SCAN_INTERVAL then
        scanElapsed = 0
        UpdateAllPins()
    elseif updateElapsed >= POSITION_INTERVAL then
        updateElapsed = 0
        for _, pin in pairs(activePins) do
            PositionPinOnMinimap(pin)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------------------------
function Topnight:InitMinimapVignettes()
    local settings = self:GetSetting("minimapVignettes")
    if not settings or not settings.enabled then
        self:Debug("Minimap vignettes disabled.")
        return
    end

    if not C_VignetteInfo or not C_VignetteInfo.GetVignettes then
        self:Debug("C_VignetteInfo API not available. Minimap vignettes disabled.")
        return
    end

    if not pinPool then
        pinPool = CreateObjectPool(CreatePinFrame, ResetPinFrame)
    end

    if not eventFrame then
        eventFrame = CreateFrame("Frame", "TopnightVignetteFrame", UIParent)

        eventFrame:RegisterEvent("VIGNETTE_MINIMAP_UPDATED")
        eventFrame:RegisterEvent("VIGNETTES_UPDATED")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

        eventFrame:SetScript("OnEvent", function(_, event, ...)
            scanElapsed = SCAN_INTERVAL  -- force immediate scan on next update
            cachedMapID = nil            -- invalidate map size cache on zone change
        end)

        eventFrame:SetScript("OnUpdate", OnUpdate)
    end

    self:Debug("Minimap vignette overlays initialized.")
end

-- ---------------------------------------------------------------------------
-- Toggle
-- ---------------------------------------------------------------------------
function Topnight:ToggleMinimapVignettes()
    local settings = self:GetSetting("minimapVignettes")
    if not settings then
        settings = { enabled = false }
        self:SetSetting("minimapVignettes", settings)
    end

    settings.enabled = not settings.enabled
    self:SetSetting("minimapVignettes", settings)

    if settings.enabled then
        if not pinPool then
            self:InitMinimapVignettes()
        elseif eventFrame then
            scanElapsed = SCAN_INTERVAL
        end
        self:PrintSuccess("Minimap vignette highlights enabled.")
    else
        for guid, pin in pairs(activePins) do
            pin:Hide()
            if pinPool then pinPool:Release(pin) end
            activePins[guid] = nil
        end
        self:PrintInfo("Minimap vignette highlights disabled.")
    end
end

-- ---------------------------------------------------------------------------
-- Cycle Icon (for testing different icons)
-- ---------------------------------------------------------------------------
function Topnight:CycleVignetteIcon()
    currentIconIndex = currentIconIndex + 1
    if currentIconIndex > #ICON_OPTIONS then
        currentIconIndex = 1
    end

    local option = ICON_OPTIONS[currentIconIndex]
    self:PrintSuccess("Vignette icon: " .. option.label .. " (" .. currentIconIndex .. "/" .. #ICON_OPTIONS .. ")")

    -- Update all active pins immediately
    for _, pin in pairs(activePins) do
        ApplyIconToPin(pin)
    end
end

-- ---------------------------------------------------------------------------
-- Debug: dump vignette info to chat
-- ---------------------------------------------------------------------------
function Topnight:DebugVignettes()
    self:Print(self.Colors.ACCENT .. "=== Vignette Debug ===" .. self.Colors.RESET)

    if not C_VignetteInfo or not C_VignetteInfo.GetVignettes then
        self:PrintWarning("C_VignetteInfo API not available.")
        return
    end

    local mapID = C_Map.GetBestMapForUnit("player")
    self:Print("Current mapID: " .. tostring(mapID))

    -- Map world size
    if mapID then
        local w, h = GetMapWorldSize(mapID)
        self:Print(string.format("Map world size: %.0f x %.0f yards", w, h))
    end

    -- Minimap view radius
    local viewRadius
    pcall(function() viewRadius = C_Minimap.GetViewRadius() end)
    self:Print("Minimap view radius: " .. tostring(viewRadius) .. " yards")
    self:Print("Minimap zoom: " .. tostring(Minimap:GetZoom()))
    self:Print("Minimap size: " .. tostring(Minimap:GetWidth()) .. "x" .. tostring(Minimap:GetHeight()))

    local guids = C_VignetteInfo.GetVignettes()
    if not guids or #guids == 0 then
        self:PrintInfo("No vignettes found on minimap.")
        return
    end

    self:Print("Found " .. #guids .. " vignettes:")
    for i, guid in ipairs(guids) do
        local info = C_VignetteInfo.GetVignetteInfo(guid)
        if info then
            local matchStr = IsMatchingVignette(info) and self.Colors.SUCCESS .. " [MATCH]" or ""
            self:Print(string.format("  %d. %s%s%s", i,
                self.Colors.ACCENT .. (info.name or "?") .. self.Colors.RESET,
                matchStr .. self.Colors.RESET,
                info.onMinimap and " (minimap)" or ""))
            self:Print(string.format("     type=%s atlas=%s vigID=%s",
                tostring(info.type), tostring(info.atlasName), tostring(info.vignetteID)))

            if mapID then
                local pos = C_VignetteInfo.GetVignettePosition(guid, mapID)
                if pos then
                    local vx, vy = pos:GetXY()
                    self:Print(string.format("     pos=%.4f, %.4f", vx or 0, vy or 0))
                else
                    self:Print("     pos=nil")
                end
            end
        end
    end

    -- Player position
    if mapID then
        local playerPos = C_Map.GetPlayerMapPosition(mapID, "player")
        if playerPos then
            local px, py = playerPos:GetXY()
            self:Print(string.format("Player pos: %.4f, %.4f", px or 0, py or 0))
        end
    end

    -- Pin state
    local pinCount = 0
    for guid, pin in pairs(activePins) do
        pinCount = pinCount + 1
        local shown = pin:IsShown() and "VISIBLE" or "HIDDEN"
        local pt = { pin:GetPoint() }
        local xOff = pt[4] or 0
        local yOff = pt[5] or 0
        self:Print(string.format("  Pin %s: %s offset=(%.1f, %.1f)",
            tostring(pin.vignetteName), shown, xOff, yOff))
    end
    self:Print("Active pins: " .. pinCount)

    self:Print(self.Colors.ACCENT .. "=== End Vignette Debug ===" .. self.Colors.RESET)
end

-- ---------------------------------------------------------------------------
-- Debug: scan all Minimap children to discover vignette pin frames
-- ---------------------------------------------------------------------------
function Topnight:DebugMinimapChildren()
    self:Print(self.Colors.ACCENT .. "=== Minimap Children Scan ===" .. self.Colors.RESET)

    local children = { Minimap:GetChildren() }
    self:Print("Total Minimap children: " .. #children)

    for i, child in ipairs(children) do
        local name = child:GetName() or "(anon)"
        local objType = child:GetObjectType() or "?"
        local shown = child:IsShown() and "shown" or "hidden"
        local w, h = child:GetWidth(), child:GetHeight()

        -- Check for vignetteGUID or other vignette-related properties
        local vigProps = ""
        if child.vignetteGUID then vigProps = vigProps .. " vigGUID=" .. tostring(child.vignetteGUID) end
        if child.vignetteID then vigProps = vigProps .. " vigID=" .. tostring(child.vignetteID) end
        if child.name then vigProps = vigProps .. " .name=" .. tostring(child.name) end
        if child.atlasName then vigProps = vigProps .. " .atlas=" .. tostring(child.atlasName) end
        if child.GetVignetteInfo then vigProps = vigProps .. " [HasGetVignetteInfo]" end
        if child.icon then vigProps = vigProps .. " [HasIcon]" end

        -- Check template/mixin
        local template = ""
        if child.VignettePinMixin then template = " Mixin:VignettePin" end

        -- Scan child textures for atlas names
        local texInfo = ""
        local regions = { child:GetRegions() }
        for _, region in ipairs(regions) do
            if region:GetObjectType() == "Texture" then
                local atlas = nil
                pcall(function() atlas = region:GetAtlas() end)
                local tex = region:GetTexture()
                if atlas and atlas ~= "" then
                    texInfo = texInfo .. " atlas:" .. tostring(atlas)
                elseif tex then
                    texInfo = texInfo .. " tex:" .. tostring(tex)
                end
            end
        end

        -- Only print interesting children (has textures, is a vignette pin, or is shown)
        if vigProps ~= "" or texInfo ~= "" or template ~= "" or objType == "Button" then
            self:Print(string.format("  %d. [%s] %s (%s) %.0fx%.0f%s%s%s",
                i, objType, name, shown, w, h, vigProps, template, texInfo))
        end
    end

    self:Print(self.Colors.ACCENT .. "=== End Minimap Children ===" .. self.Colors.RESET)
end

-- ---------------------------------------------------------------------------
-- Hide default vignette pin frames that match our criteria
-- Called during UpdateAllPins to hide the engine-created frames
-- ---------------------------------------------------------------------------
local hiddenFrames = {}

local function HideMatchingVignetteFrames()
    -- Get list of matching vignette GUIDs
    local matchingGUIDs = {}
    local vignetteGUIDs = C_VignetteInfo.GetVignettes()
    if not vignetteGUIDs then return end

    for _, guid in ipairs(vignetteGUIDs) do
        local info = C_VignetteInfo.GetVignetteInfo(guid)
        if info and info.onMinimap and IsMatchingVignette(info) then
            matchingGUIDs[guid] = true
        end
    end

    -- Scan minimap children for vignette pin frames
    local children = { Minimap:GetChildren() }
    for _, child in ipairs(children) do
        -- Check multiple ways to identify a vignette pin frame
        local childGUID = child.vignetteGUID or child.VignetteGUID
            or (child.GetVignetteGUID and child:GetVignetteGUID())

        if childGUID and matchingGUIDs[childGUID] then
            -- Found a matching default vignette pin — hide it
            if child:IsShown() then
                child:Hide()
                hiddenFrames[child] = true
            end
        else
            -- Also try matching by texture atlas
            local regions = { child:GetRegions() }
            for _, region in ipairs(regions) do
                if region:GetObjectType() == "Texture" then
                    local atlas
                    pcall(function() atlas = region:GetAtlas() end)
                    if atlas == "VignetteLoot" or atlas == "VignetteLootElite" then
                        -- This might be a vignette pin — check if its position
                        -- matches any of our matching vignettes
                        -- For now, mark it for potential hiding
                        -- (We'll refine this based on debug output)
                    end
                end
            end
        end
    end

    -- Restore hidden frames that no longer match
    for frame in pairs(hiddenFrames) do
        local guid = frame.vignetteGUID or frame.VignetteGUID
            or (frame.GetVignetteGUID and frame:GetVignetteGUID())
        if not guid or not matchingGUIDs[guid] then
            -- No longer matching, unhide if we hid it
            hiddenFrames[frame] = nil
        end
    end
end

-- ---------------------------------------------------------------------------
-- Public accessors
-- ---------------------------------------------------------------------------
function Topnight:IsMinimapVignettesEnabled()
    local settings = self:GetSetting("minimapVignettes")
    return settings and settings.enabled
end

