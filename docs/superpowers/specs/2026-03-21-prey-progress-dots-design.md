# Prey Progress Dots — Design Spec
**Date:** 2026-03-21
**Addon:** Topnight (WoW: Midnight)
**Scope:** Minimal — stage indicator in Progression task card only

---

## Background

The WoW: Midnight Prey system is a weekly open-world hunting activity. Players collect Anguish by doing outdoor content (world quests, rares, treasures, traps) which fills an Anguish Crystal through three stages. Once fully attuned, the prey target's location is revealed and the player can fight it.

The default WoW UI shows only a vague crystal icon. Topnight will replace this with 3 minimal dots in the Progression task card — one dot per stage — giving players a clear, at-a-glance hunt status.

**API constraint:** Blizzard exposes stage transitions only, not a continuous percentage. The system is stage-based and event-driven. All API calls are guarded with `pcall`.

---

## Hunt Stages

| Stage | Value | Crystal State |
|-------|-------|---------------|
| Inactive | 0 | No active hunt |
| Hidden | 1 | Location unknown, crystal dim |
| Tracking | 2 | Crystal glowing/pulsing |
| Attuned | 3 | Target revealed — ready to fight |

---

## Components

### 1. `Prey.lua` (new file)

**Purpose:** Data layer for prey hunt state.

**Public API:**
- `Topnight:GetPreyHuntData()` → `{ stage = 0–3, active = bool }` or `nil`
- `Topnight:InitPrey()` — registers events and initializes module

**Behavior:**
- Queries `C_Prey` API (exact functions TBD at implementation; guarded with `pcall`)
- Caches result; invalidates on relevant WoW events (e.g. `PREY_HUNT_STAGE_CHANGED`)
- On stage change, calls `Topnight:RefreshControlPanel()` if available

**Initialization:** Called from `Core.lua` `PLAYER_LOGIN` handler, like all other modules.

---

### 2. `Progression.lua` (updated)

**New evaluator:** `Topnight:EvaluatePreyHunts(addTask)`

- Called from `EvaluateProgressionTasks()` alongside existing evaluators
- Calls `Topnight:GetPreyHuntData()`
- If `active == true` and `stage >= 1`, inserts a task directly via `table.insert(Topnight.ProgressionTasks, ...)` rather than going through the local `addTask` callback (which has a fixed four-parameter signature that cannot carry `stageIndicator`). This keeps all existing call sites unchanged:
  ```lua
  table.insert(Topnight.ProgressionTasks, {
      title          = "Prey Hunt",
      description    = nil,   -- dots replace description; nothing to display as text
      priority       = 83,
      stageIndicator = { current = N, max = 3 },
      action         = function() ... end,
  })
  ```

**Priority:** 83 — intentionally sits above an in-progress weekly quest (82) but below an un-picked-up weekly quest (85). An attuned hunt is actionable but less urgent than a quest the player hasn't started yet.

---

### 3. `ControlPanel.lua` (updated)

**Task card rendering:**
- When a task has `stageIndicator`, render 3 dots on the right side of the title row instead of description text
- Dot states (colors as normalized floats, matching existing `C_*` conventions):
  - Filled dot 1: `{ r=0.78, g=0.20, b=0.20, a=0.6 }` — stage ≥ 1
  - Filled dot 2: `{ r=0.86, g=0.16, b=0.16, a=0.8 }` — stage ≥ 2
  - Filled dot 3: `{ r=0.80, g=0.13, b=0.13, a=1.0 }` with glow — stage == 3 (Attuned)
  - Empty dot: `{ r=1.0, g=1.0, b=1.0, a=0.08 }` with subtle border
- When a task has `stageIndicator`, `task.description` is `nil`; the renderer skips the description line entirely
- When stage == 3 (Attuned): card border color shifts to `C_RED` (existing constant in `ControlPanel.lua`: `{ r=0.93, g=0.27, b=0.17 }`) to draw attention
- No label text alongside the dots

---

### 4. `Topnight.toc` (updated)

Add `Prey.lua` before `Progression.lua` in the load order (data layer must load before evaluator).

---

## Data Flow

```
PLAYER_LOGIN
  → InitPrey()
      → registers PREY_HUNT_STAGE_CHANGED (and similar events)

[Stage change event fires]
  → invalidate cache
  → RefreshControlPanel()
      → EvaluateProgressionTasks()
          → EvaluatePreyHunts()
              → GetPreyHuntData()
              → table.insert(Topnight.ProgressionTasks, { ..., stageIndicator = { current, max = 3 } })
      → render task cards
          → detect stageIndicator → draw 3 dots
```

---

## Out of Scope (for now)

- Weekly completion tracking per difficulty
- Remnants of Anguish currency display
- Warband-wide prey overview
- Multiple simultaneous hunts (one per zone — may be added later)

---

## Open Questions for Implementation

- Exact `C_Prey` function names (to be confirmed at implementation via WoW API docs / Preydator source)
- Exact event name(s) for hunt stage changes
- Whether multiple active hunts (different zones/difficulties) need to be shown — design assumes one row per active hunt but implementation may simplify to one row total
