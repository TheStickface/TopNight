# Prey Progress Dots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 3 stage-indicator dots to the Progression task card in the Control Panel to replace the vague default prey crystal icon.

**Architecture:** New `Prey.lua` data layer queries the WoW widget API to detect the active hunt's stage (Cold/Warm/Hot/Final). `Progression.lua` inserts a task with a `stageIndicator` field. `ControlPanel.lua` renders 3 dots in place of description text when that field is present.

**Tech Stack:** WoW Lua 5.1 (Midnight 12.0+), `C_UIWidgetManager` widget API, `Enum.PreyHuntProgressState`, WoW event system.

---

## Stage Mapping

The WoW API exposes **4 stages**, not 3. They map to 3 dots as follows:

| API Stage | Value | Dots Lit |
|-----------|-------|----------|
| Cold | 0 | 0 (no active hunt) |
| Warm | 1 | 1 |
| Hot | 2 | 2 |
| Final | 3 | 3 (red tint + attuned glow) |

When stage == Cold, no task is added (hunt is inactive). When stage >= Warm, a task appears with the appropriate number of dots lit.

---

## Files

| File | Action | Responsibility |
|------|--------|----------------|
| `Prey.lua` | **Create** | Widget API queries, `GetPreyHuntData()`, `InitPrey()` |
| `Progression.lua` | **Modify** | Add `EvaluatePreyHunts()`, call from `EvaluateProgressionTasks()` |
| `ControlPanel.lua` | **Modify** | Add dot textures + attuned overlay in `CreateControlPanel()`, update `UpdateDirectorDisplay()` |
| `Topnight.toc` | **Modify** | Load `Prey.lua` before `Progression.lua` |
| `Core.lua` | **Modify** | Call `InitPrey()` in `PLAYER_LOGIN` handler |

> **Note on testing:** WoW addons have no offline test runner. Each task ends with in-game verification via `/reload` and debug commands. Use `/run Topnight:Debug("test")` then enable debug mode via `/tn debug` to check output. All in-game verification assumes an active Prey Hunt is in progress.

---

## Task 1: Create Prey.lua

**Files:**
- Create: `Prey.lua`

- [ ] **Step 1: Create the file with data layer and InitPrey**

```lua
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
```

- [ ] **Step 2: Verify file saved correctly**

Run: `wc -l Prey.lua` (or open in editor)
Expected: ~70 lines, no syntax errors visible.

---

## Task 2: Wire Prey.lua into load order and PLAYER_LOGIN

**Files:**
- Modify: `Topnight.toc` — add `Prey.lua` line
- Modify: `Core.lua:77-103` — add `InitPrey` call

- [ ] **Step 1: Add Prey.lua to the toc before Progression.lua**

In `Topnight.toc`, find the lines:
```
HousingData.lua
CollectionTracker.lua
```
Change to:
```
HousingData.lua
CollectionTracker.lua
Prey.lua
```
`Prey.lua` must load before `Progression.lua` because the evaluator calls `GetPreyHuntData`.

- [ ] **Step 2: Add InitPrey call in Core.lua PLAYER_LOGIN handler**

In `Core.lua`, find the block:
```lua
    if self.InitKnowledgePoints then
        self:InitKnowledgePoints()
    end
```
Add after it:
```lua
    if self.InitPrey then
        self:InitPrey()
    end
```

- [ ] **Step 3: Reload and check no Lua errors**

In-game: `/reload`
Expected: No red Lua error popup. `/tn` command still works.

- [ ] **Step 4: Verify GetPreyHuntData returns a table**

In-game (with or without an active hunt):
```
/run local d = Topnight:GetPreyHuntData(); print(d.active, d.stage)
```
Expected: `false 0` when no hunt active, or `true 1/2/3` when hunt is in progress.

- [ ] **Step 5: Commit**

```bash
git add Topnight.toc Core.lua Prey.lua
git commit -m "feat: Add Prey.lua data layer and wire into load order"
```

---

## Task 3: Add EvaluatePreyHunts to Progression.lua

**Files:**
- Modify: `Progression.lua:31-67` — add evaluator function and call it

- [ ] **Step 1: Add the EvaluatePreyHunts function**

In `Progression.lua`, add this function after `EvaluateEndeavors` (around line 261):

```lua
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
```

- [ ] **Step 2: Call EvaluatePreyHunts from EvaluateProgressionTasks**

In `Progression.lua`, find the block:
```lua
    -- 1b. Neighborhood Endeavors
    local ok4, err4 = pcall(function() self:EvaluateEndeavors(AddTask) end)
    if not ok4 then self:Debug("Endeavor evaluator error: " .. tostring(err4)) end
```
Add after it:
```lua
    -- 1c. Prey Hunts
    local okP, errP = pcall(function() self:EvaluatePreyHunts() end)
    if not okP then self:Debug("Prey evaluator error: " .. tostring(errP)) end
```

- [ ] **Step 3: Reload and verify task appears when hunt is active**

In-game with an active Prey Hunt:
```
/reload
/run Topnight:EvaluateProgressionTasks(); for i,t in ipairs(Topnight.ProgressionTasks) do print(t.title, t.priority, t.stageIndicator and t.stageIndicator.current) end
```
Expected: A line like `Prey Hunt  83  2` appears (stage number matches current crystal state).

Without an active hunt, no `Prey Hunt` line should appear.

- [ ] **Step 4: Commit**

```bash
git add Progression.lua
git commit -m "feat: Add EvaluatePreyHunts to Progression Director"
```

---

## Task 4: Add dot widgets to ControlPanel directorBanner

**Files:**
- Modify: `ControlPanel.lua:171-199` — add dot textures and attuned overlay in `CreateControlPanel()`

- [ ] **Step 1: Add dot textures and attuned overlay after the directorBanner block**

In `ControlPanel.lua`, find this existing block (around line 171–199):
```lua
    f.directorBanner = CreateFrame("Frame", nil, f.body, "BackdropTemplate")
    f.directorBanner:SetSize(barWidth, 72)
    f.directorBanner:SetPoint("TOPLEFT", 10, y)
    Topnight:CreateBackdrop(f.directorBanner, { r = 0.1, g = 0.1, b = 0.14, a = 0.9 })
    f.directorIndex = 1  -- which task is currently displayed

    f.directorTitle = f.directorBanner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.directorTitle:SetPoint("TOPLEFT", 6, -6)
    f.directorTitle:SetText("|cffF59E0B> Up Next|r")

    f.directorDesc = f.directorBanner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.directorDesc:SetPoint("TOPLEFT", 6, -22)
    f.directorDesc:SetWidth(barWidth - 24)
    f.directorDesc:SetJustifyH("LEFT")
    f.directorDesc:SetJustifyV("TOP")
    f.directorDesc:SetText("|cff9CA3AFAwaiting evaluation...|r")
```

After `f.directorDesc:SetText(...)`, add:
```lua
    -- Stage dots: 3 circles shown when current task has stageIndicator
    -- Anchored to the top-right of the title row
    local DOT_SIZE = 7
    local DOT_GAP  = 4
    f.directorDots = {}
    for i = 1, 3 do
        local dot = f.directorBanner:CreateTexture(nil, "OVERLAY")
        dot:SetSize(DOT_SIZE, DOT_SIZE)
        dot:SetTexture("Interface\\Buttons\\WHITE8x8")
        if i == 1 then
            -- Anchor rightmost dot first, then chain left-to-right
            dot:SetPoint("RIGHT", f.directorBanner, "TOPRIGHT",
                -((DOT_SIZE + DOT_GAP) * 2) - 8, -(DOT_SIZE / 2) - 6)
        else
            dot:SetPoint("LEFT", f.directorDots[i - 1], "RIGHT", DOT_GAP, 0)
        end
        dot:Hide()
        f.directorDots[i] = dot
    end

    -- Attuned (Final stage) red background tint — shown only when stage == 3
    -- C_RED is defined at the top of this file: local C_RED = { r=0.93, g=0.27, b=0.17 }
    f.directorAttunedOverlay = f.directorBanner:CreateTexture(nil, "BACKGROUND")
    f.directorAttunedOverlay:SetAllPoints()
    f.directorAttunedOverlay:SetTexture("Interface\\Buttons\\WHITE8x8")
    f.directorAttunedOverlay:SetVertexColor(C_RED.r * 0.18, C_RED.g * 0.02, C_RED.b * 0.02, 0.45)
    f.directorAttunedOverlay:Hide()
```

- [ ] **Step 2: Reload and verify no errors**

In-game: `/reload`
Expected: Control panel opens normally, no errors. Dots are invisible (correctly hidden).

- [ ] **Step 3: Commit**

```bash
git add ControlPanel.lua
git commit -m "feat: Add prey dot textures and attuned overlay to directorBanner"
```

---

## Task 5: Update UpdateDirectorDisplay to render dots

**Files:**
- Modify: `ControlPanel.lua:695-731` — update `UpdateDirectorDisplay()`

- [ ] **Step 1: Add UpdateDirectorDots local helper before UpdateDirectorDisplay**

In `ControlPanel.lua`, find the comment line:
```lua
-- ---------------------------------------------------------------------------
-- Director Display (renders current index without re-evaluating)
-- ---------------------------------------------------------------------------
```

Add this helper function immediately before it:
```lua
-- Dot fill colors per lit stage (normalized floats, matching C_* constants)
local PREY_DOT_COLORS = {
    { r = 0.78, g = 0.20, b = 0.20, a = 0.6 },  -- dot 1 (Warm)
    { r = 0.86, g = 0.16, b = 0.16, a = 0.8 },  -- dot 2 (Hot)
    { r = 0.80, g = 0.13, b = 0.13, a = 1.0 },  -- dot 3 (Final)
}
local PREY_DOT_EMPTY = { r = 1.0, g = 1.0, b = 1.0, a = 0.08 }

local function UpdateDirectorDots(panel, stage)
    local dots = panel.directorDots
    if not dots then return end

    for i = 1, 3 do
        local dot = dots[i]
        if not dot then break end
        dot:Show()
        if i <= stage then
            local c = PREY_DOT_COLORS[i]
            dot:SetVertexColor(c.r, c.g, c.b, c.a)
        else
            dot:SetVertexColor(PREY_DOT_EMPTY.r, PREY_DOT_EMPTY.g, PREY_DOT_EMPTY.b, PREY_DOT_EMPTY.a)
        end
    end
end
```

- [ ] **Step 2: Update UpdateDirectorDisplay to handle stageIndicator tasks**

In `ControlPanel.lua`, find this block inside `UpdateDirectorDisplay` (around line 702–710):
```lua
    if total > 0 and idx >= 1 and idx <= total then
        local task = tasks[idx]
        controlPanel.directorTitle:SetText("|cffF59E0B> " .. task.title .. "|r")
        controlPanel.directorDesc:SetText("|cffE2E8F0" .. task.description .. "|r")
        controlPanel.currentDirectorAction = task.action
        controlPanel.currentDirectorTaskTitle = task.title
        controlPanel.directorDismissBtn:Show()
        controlPanel.directorPageText:SetText(string.format("|cff6B7280%d of %d|r", idx, total))
```

Replace with:
```lua
    if total > 0 and idx >= 1 and idx <= total then
        local task = tasks[idx]
        controlPanel.directorTitle:SetText("|cffF59E0B> " .. task.title .. "|r")

        if task.stageIndicator then
            -- Prey task: render dots, hide description text
            controlPanel.directorDesc:SetText("")
            UpdateDirectorDots(controlPanel, task.stageIndicator.current)
            -- Attuned (stage 3) gets a red tint overlay
            if task.stageIndicator.current >= 3 then
                controlPanel.directorAttunedOverlay:Show()
            else
                controlPanel.directorAttunedOverlay:Hide()
            end
        else
            -- Normal task: hide dots, show description text
            if controlPanel.directorDots then
                for _, dot in ipairs(controlPanel.directorDots) do dot:Hide() end
            end
            if controlPanel.directorAttunedOverlay then
                controlPanel.directorAttunedOverlay:Hide()
            end
            controlPanel.directorDesc:SetText("|cffE2E8F0" .. (task.description or "") .. "|r")
        end

        controlPanel.currentDirectorAction = task.action
        controlPanel.currentDirectorTaskTitle = task.title
        controlPanel.directorDismissBtn:Show()
        controlPanel.directorPageText:SetText(string.format("|cff6B7280%d of %d|r", idx, total))
```

- [ ] **Step 2b: Also clean up dots in the "All Done" else-branch**

In `UpdateDirectorDisplay`, find the existing else-branch (around line 722) that reads:
```lua
    else
        controlPanel.directorTitle:SetText("|cffF59E0B> All Done|r")
        controlPanel.directorDesc:SetText("|cff6B7280All weekly tasks completed!|r")
        controlPanel.currentDirectorAction = nil
        controlPanel.currentDirectorTaskTitle = nil
        controlPanel.directorDismissBtn:Hide()
```

Replace with:
```lua
    else
        controlPanel.directorTitle:SetText("|cffF59E0B> All Done|r")
        controlPanel.directorDesc:SetText("|cff6B7280All weekly tasks completed!|r")
        if controlPanel.directorDots then
            for _, dot in ipairs(controlPanel.directorDots) do dot:Hide() end
        end
        if controlPanel.directorAttunedOverlay then
            controlPanel.directorAttunedOverlay:Hide()
        end
        controlPanel.currentDirectorAction = nil
        controlPanel.currentDirectorTaskTitle = nil
        controlPanel.directorDismissBtn:Hide()
```

- [ ] **Step 3: Reload and verify dots render correctly**

In-game with an active Prey Hunt:
- `/reload` then open control panel (`/tn panel` or minimap click)
- The "Prey Hunt" task should appear in the director banner with 1–3 dots lit based on crystal stage
- Navigate away with the arrows; other tasks should show normal text (no dots)
- Verify no Lua errors in chat

- [ ] **Step 4: Verify attuned state (stage 3)**

If hunt is at Final stage:
- The director banner should have a subtle red background tint
- All 3 dots should be fully lit
- Clicking the banner area should open the world map

- [ ] **Step 5: Verify nil-safety — task without description**

```
/run Topnight.ProgressionTasks = {{ title="Test", description=nil, priority=50, action=function() end }}; Topnight:UpdateDirectorDisplay()
```
Expected: Panel shows "Test" title, empty description area, no Lua error.

- [ ] **Step 6: Commit**

```bash
git add ControlPanel.lua
git commit -m "feat: Render prey stage dots in director task card"
```

---

## Task 6: Final smoke test and cleanup

- [ ] **Step 1: Full reload smoke test**

In-game: `/reload`
- Open control panel: all sections render correctly
- No Lua errors in chat
- Non-prey tasks (housing, vault, etc.) still show text descriptions with no dot artifacts

- [ ] **Step 2: Verify task correctly absent when no hunt active**

Log out to character screen or use a character without an active hunt.
```
/run Topnight:EvaluateProgressionTasks(); for i,t in ipairs(Topnight.ProgressionTasks) do print(t.title) end
```
Expected: No "Prey Hunt" in the list.

- [ ] **Step 3: Commit version bump**

In `Topnight.toc`, update:
```
## Version: 1.6.0
```
to:
```
## Version: 1.7.0
```

```bash
git add Topnight.toc
git commit -m "chore: Bump version to 1.7.0"
```
