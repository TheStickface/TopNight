-- =============================================================================
-- Topnight - Utils.lua
-- Reusable utility functions
-- =============================================================================

local ADDON_NAME, Topnight = ...

-- ---------------------------------------------------------------------------
-- Color Constants
-- ---------------------------------------------------------------------------
local COLORS = {
    PREFIX  = "|cff8B5CF6",   -- Purple (matches addon title)
    INFO    = "|cff9CA3AF",   -- Gray
    SUCCESS = "|cff22C55E",   -- Green
    WARNING = "|cffF59E0B",   -- Amber
    ERROR   = "|cffEF4444",   -- Red
    ACCENT  = "|cff60A5FA",   -- Blue
    RESET   = "|r",
}

Topnight.Colors = COLORS

-- ---------------------------------------------------------------------------
-- Chat Output Helpers
-- ---------------------------------------------------------------------------
local PREFIX = COLORS.PREFIX .. "Topnight" .. COLORS.RESET .. " "

function Topnight:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

function Topnight:PrintInfo(msg)
    self:Print(COLORS.INFO .. tostring(msg) .. COLORS.RESET)
end

function Topnight:PrintSuccess(msg)
    self:Print(COLORS.SUCCESS .. tostring(msg) .. COLORS.RESET)
end

function Topnight:PrintWarning(msg)
    self:Print(COLORS.WARNING .. tostring(msg) .. COLORS.RESET)
end

function Topnight:PrintError(msg)
    self:Print(COLORS.ERROR .. tostring(msg) .. COLORS.RESET)
end

-- ---------------------------------------------------------------------------
-- Debug Print (only when debug mode is enabled)
-- ---------------------------------------------------------------------------
function Topnight:Debug(msg)
    if self.db and self.db.debug then
        self:Print(COLORS.ACCENT .. "[Debug]" .. COLORS.RESET .. " " .. tostring(msg))
    end
end

-- ---------------------------------------------------------------------------
-- Table Utilities
-- ---------------------------------------------------------------------------

--- Deep copy a table
---@param orig table
---@return table
function Topnight:DeepCopy(orig)
    if type(orig) ~= "table" then
        return orig
    end
    local copy = {}
    for k, v in pairs(orig) do
        if type(v) == "table" then
            copy[k] = self:DeepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

--- Merge source table into destination (destination values take priority)
---@param dst table
---@param src table
---@return table
function Topnight:MergeDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = self:DeepCopy(v)
            else
                dst[k] = v
            end
        elseif type(v) == "table" and type(dst[k]) == "table" then
            self:MergeDefaults(dst[k], v)
        end
    end
    return dst
end

-- ---------------------------------------------------------------------------
-- String Utilities
-- ---------------------------------------------------------------------------

--- Format a key-value pair for display
---@param key string
---@param value any
---@return string
function Topnight:FormatKeyValue(key, value)
    return COLORS.ACCENT .. tostring(key) .. COLORS.RESET .. ": " .. tostring(value)
end

-- ---------------------------------------------------------------------------
-- UI Utilities
-- ---------------------------------------------------------------------------

--- Apply a standard backdrop to a frame
---@param frame table
---@param bg table {r, g, b, a}
function Topnight:CreateBackdrop(frame, bg)
    if not frame.SetBackdrop then
        Mixin(frame, BackdropTemplateMixin)
    end
    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 1)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
end
