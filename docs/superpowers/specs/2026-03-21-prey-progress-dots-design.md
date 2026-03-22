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
- `Topnight:GetPreyHuntData()` → `{ stage = 0–3, active = bool, zone = string }` or `nil`
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
- If `active == true` and `stage >= 1`, adds a task:
  ```
  title       = "Prey Hunt"
  priority    = 83
  stageIndicator = { current = N, max = 3 }
  action      = open map / hunt table
  ```
- If `stage == 3` (Attuned), description is set to `"__attuned"` as a signal to the renderer

**Priority:** 83 — slots above weekly quests (82/85) to surface an attuned hunt prominently.

---

### 3. `ControlPanel.lua` (updated)

**Task card rendering:**
- When a task has `stageIndicator`, render 3 dots on the right side of the title row instead of description text
- Dot states:
  - Filled dot 1: `rgba(200,50,50,0.6)` — stage ≥ 1
  - Filled dot 2: `rgba(220,40,40,0.8)` — stage ≥ 2
  - Filled dot 3: `#cc2222` with glow — stage == 3 (Attuned)
  - Empty dot: `rgba(255,255,255,0.08)` with subtle border
- When stage == 3 (Attuned): card border color shifts to red (`C_RED`) to draw attention
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
              → addTask(..., stageIndicator = { current, max = 3 })
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
