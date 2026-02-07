# UI Overhaul Design: Interactive Agent Control

Date: 2026-02-06
Owner: Design / UI
Status: Partially Implemented

## 0) Scope & Goals

### Current State (as of 2026-02-06)
The game now has a functional AoE2-style RTS interface with many features implemented:
- **Resource bar HUD** (top): team resources, population, step counter
- **Minimap** (bottom-left): clickable bird's-eye view with terrain colors, unit dots, viewport rectangle
- **Unit info panel** (right): selected unit stats, HP bars, inventory
- **Command panel** (right-lower): context-sensitive action buttons with hotkeys
- **Drag-box multi-select**: click-and-drag rectangle selection
- **Right-click commands**: AoE2-style move/attack/gather/garrison
- **Building placement mode**: ghost preview, validity checking, shift-click multibuild
- **Control groups**: Ctrl+0-9 assign, 0-9 recall, double-tap to center
- **Formations**: Line, Box, Staggered, Ranged Spread (with 8-direction rotation)
- **Rally points**: visual beacon with path line from building
- **Team switching**: Tab cycle, F1-F8 quick switch, observer mode
- **Weather effects**: Rain, Wind, None (F9 cycle)
- **Visual effects**: water ripples, unit trails, torch flicker, damage numbers, ragdolls, debris, spawn effects, trade route visualization

All rendering is in Nim using Boxy/Windy/OpenGL.

### Goals
Transform the viewer into a playable RTS interface inspired by AoE2, enabling direct player
control of AI agents while preserving the AI-driven simulation as default. The player should
be able to seamlessly take over a team, issue commands, and release control back to AI.

### Non-Goals
- Full multiplayer networking (single-player or AI-observer only).
- Replacing the AI system; player commands override individual agent actions per-step.
- Mobile/touch input support.
- 3D rendering or engine change.

---

## 1) Architecture Overview

### Panel System Redesign

The current UI has a single `WorldMap` panel filling the viewport plus a footer bar.
The new layout uses a panel-based composition where each HUD element is a logical region
rendered in screen space after the world transform is restored.

```
+------------------------------------------------------------------+
|  [Resource Bar HUD]  Food | Wood | Stone | Gold | Pop | Step     |
+------+---------------------------------------------------+-------+
|      |                                                   |       |
|      |                                                   | Unit  |
|      |              World Map                            | Info  |
|      |              (existing)                           | Panel |
|      |                                                   |       |
|      |                                                   |       |
| Mini |                                                   +-------+
| Map  |                                                   |       |
|      |                                                   | Cmd   |
|      |                                                   | Panel |
+------+---------------------------------------------------+-------+
|  [Footer: Playback Controls + Selection Label + Hotkey Hints]    |
+------------------------------------------------------------------+
```

**Layout regions (all in screen/pixel space):**

| Region | Position | Size | Purpose |
|--------|----------|------|---------|
| Resource Bar | Top | Full width x 32px | Team resources, pop, step |
| Minimap | Bottom-left | 200x200px | Clickable overview with fog |
| Unit Info Panel | Right, upper | 240px wide | Selected unit stats/HP/armor |
| Command Panel | Right, lower | 240px wide | Context-sensitive action buttons |
| Footer | Bottom | Full width x 64px | Playback controls (existing) |
| World Map | Center | Remaining space | Game world (existing) |

### Key Design Decisions

1. **No new Panel type hierarchy.** Each HUD region is drawn procedurally in screen space
   by dedicated `draw*` procs in `renderer.nim`, following the existing footer pattern.
   Mouse hit-testing uses simple rect checks, same as footer buttons.

2. **Input priority chain:** UI regions consume mouse events top-down. If a click lands
   inside a HUD region, it sets `uiMouseCaptured = true` and the world map ignores it.
   Keyboard shortcuts always work regardless of mouse position.

3. **AI takeover toggle** is a per-team flag (`playerControlled: bool`) on the environment.
   When active, player commands replace AI actions for that team's agents before `env.step()`.
   When released, AI resumes seamlessly.

---

## 2) Resource Bar HUD

**Location:** Top of viewport, full width, 32px height.

**Content (left to right):**
- Team color swatch (16x16)
- Food icon + count
- Wood icon + count
- Stone icon + count
- Gold icon + count
- Separator
- Population: current / cap (villager icon)
- Separator
- Step counter (moved from footer)
- AI/Player mode indicator

**Data source:** `env.teamStockpiles[playerTeam].counts[res]` for resources.
Population from agent alive count; cap from house count * HousePopCap.

**Implementation approach:**
- New proc `drawResourceBar*(panelRect: IRect, teamId: int)` in `renderer.nim`.
- Uses same text-caching pattern as existing footer labels.
- Resource icons reuse existing item sprites at small scale.
- `playerTeam` variable defaults to 0, switchable via F1-F8.

---

## 3) Command Panel (Context-Sensitive Actions)

**Location:** Right side, lower portion, 240px wide.

**Behavior:** Shows different buttons depending on what is selected.

### 3a) Unit Selected (Agent)

Shows available actions as a button grid (3 columns x N rows):

**Villager commands:**
- Move (right-click on map sets destination)
- Attack (right-click target)
- Build (opens building submenu)
- Gather (auto on right-click resource)
- Use/Craft
- Plant Lantern
- Plant Resource
- Patrol (toggle)
- Stop

**Military unit commands:**
- Move / Attack-Move
- Attack
- Patrol
- Stop
- Stance toggle (Aggressive/Defensive/Stand Ground/No Attack)
- Special: Pack/Unpack (Trebuchet), Heal/Convert (Monk)

**Implementation:**
- Each button maps to an action verb + argument.
- Clicking a button enters a "pending command" mode where next click on world map
  provides the direction/target argument.
- Hotkeys displayed on button corners (e.g., "B" for Build, "A" for Attack).

### 3b) Building Selected

Shows building-specific actions:

**Production buildings (Barracks, Archery Range, Stable, etc.):**
- Train unit buttons (with hotkeys)
- Research upgrade buttons (grayed if already researched)
- Set Rally Point button
- Cancel queue button

**Economy buildings:**
- Dropoff indicator
- Garrison count
- Ungarrison All button

**Research buildings (Blacksmith, University, Castle):**
- Tech buttons in grid layout
- Researched techs shown with checkmark overlay
- In-progress tech shows progress bar
- Cost tooltip on hover

### 3c) Multi-Selection

- Shows unit composition (e.g., "3 Villagers, 2 Archers")
- Common commands only (Move, Attack, Stop, Patrol)
- Formation controls (future)

---

## 4) Unit Info Panel

**Location:** Right side, upper portion, 240px wide.

**Single unit selected:**
```
+-----------------------------------+
| [Unit Sprite]  Man-at-Arms        |
|                Team 0 (Red)       |
| HP: ████████░░  7/7               |
| Attack: 2  (+1 Forging)           |
| Armor: 1  (Scale Mail)            |
| Range: 2                          |
| Stance: Defensive                 |
| Status: Idle                      |
+-----------------------------------+
| Inventory:                        |
| [Spear x2] [Armor x1]            |
+-----------------------------------+
```

**Building selected:**
```
+-----------------------------------+
| [Building Sprite]  Barracks       |
|                    Team 0 (Red)   |
| HP: ████████████  12/12           |
| Garrison: 2/5                     |
+-----------------------------------+
| Production Queue:                 |
| [Man-at-Arms] ████░░ 3/5 steps   |
| [Archer] (queued)                 |
+-----------------------------------+
```

**Multiple selected:**
```
+-----------------------------------+
| 5 units selected                  |
| 3x Villager  2x Archer           |
+-----------------------------------+
```

**Implementation:**
- New proc `drawUnitInfoPanel*(panelRect: IRect)` in `renderer.nim`.
- Reads from `selection` seq and `env` state.
- HP bar uses existing segment rendering pattern.
- Stat bonuses computed from `teamBlacksmithUpgrades`, `teamUniversityTechs`, etc.

---

## 5) Minimap

**Location:** Bottom-left corner, 200x200px.

**Features:**
- Bird's-eye view of entire map (305x191 tiles scaled to fit).
- Color-coded: terrain base colors, team-colored dots for units, building outlines.
- Fog of war overlay (dark for unexplored tiles per `revealedMaps[teamId]`).
- Current viewport shown as white rectangle outline.
- Click to pan camera to that location.
- Right-click to issue move command to selected units.

**Implementation approach:**
- Generate minimap as a texture each frame (or every N frames for performance).
- Create a `minimapImage` (200x200 pixels) using pixie.
- For each map tile, set pixel color based on:
  - Water: dark blue
  - Trees: dark green
  - Buildings: team color (bright)
  - Units: team color (small dot)
  - Empty: terrain tint color (dimmed)
- Apply fog mask from `revealedMaps`.
- Draw viewport rect by reverse-mapping camera position to minimap coords.
- Blit as a Boxy image overlay.

**Performance:**
- Full minimap rebuild is expensive (305x191 = 58k pixels).
- Strategy: rebuild every 10 frames, or on camera move/unit change.
- Cache the base terrain layer (static between map generations).

---

## 6) Right-Click Commands

**New input flow for right-click:**

Currently right-click is unused. Add right-click as the primary command input:

1. **Right-click on empty tile:** Move selected units there.
2. **Right-click on enemy:** Attack-move to that unit's position.
3. **Right-click on resource:** Gather (villagers only).
4. **Right-click on friendly building:** Garrison or dropoff.
5. **Shift+right-click:** Queue waypoint (add to command queue).

**Implementation:**
- Add `pendingCommands: seq[PendingCommand]` to track queued orders.
- Each frame, if an agent has pending commands and AI is not controlling it,
  compute the appropriate action verb + argument to move toward the target.
- A* pathfinding is not currently in the engine; use simple direction-toward-target
  (closest cardinal/diagonal direction). This matches the existing 8-directional movement.
- `PendingCommand = object: targetPos: IVec2, commandType: CommandType`
- `CommandType = enum: CmdMove, CmdAttackMove, CmdGather, CmdGarrison`

**Cursor changes:**
- Default: normal arrow.
- Over enemy: sword icon.
- Over resource: gather icon (axe/pickaxe/farm).
- Over friendly building: enter icon.
- Build mode: building ghost preview.

**Note:** Custom cursors require Windy cursor API or software-rendered cursor sprites.
Start with software-rendered cursors (draw sprite at mouse position) for simplicity.

---

## 7) Building Placement Mode

**Flow:**
1. Player clicks "Build" in command panel (or presses B).
2. Building submenu appears showing available buildings with costs.
3. Player selects a building type.
4. Cursor changes to building ghost (semi-transparent sprite follows mouse).
5. Ghost is green if placement valid, red if invalid.
6. Left-click places the building (issues BUILD action to nearest villager).
7. ESC or right-click cancels placement mode.

**Placement validation:**
- Reuse existing `canPlace()` / `canPlaceDock()` from environment.
- Show build radius from selected villager (they must be adjacent to build).
- If villager is far from click position, issue move command first, then build.

**Implementation:**
- New state: `buildMode: bool`, `buildGhostKind: ThingKind`.
- In display loop: if `buildMode`, draw ghost sprite at mouse world position.
- On click: find nearest idle villager from selection, compute build action.

---

## 8) Research & Production Queue Panels

**Research Panel (Blacksmith/University/Castle selected):**
- Grid of tech buttons, each showing:
  - Tech icon (reuse existing item/unit sprites or generate simple icons)
  - Cost (food/gold/wood)
  - Researched state (checkmark overlay)
  - In-progress state (progress bar)
- Click to research (if resources available).

**Production Queue Panel (military buildings selected):**
- Row of unit buttons for trainable units.
- Queue display showing up to 10 queued units as small icons.
- Progress bar on first queued unit.
- Click to train, Shift+click to train 5.
- Right-click queue entry to cancel.

**Implementation:**
- Render within command panel area when appropriate building is selected.
- Read from `env.teamBlacksmithUpgrades`, `env.teamUniversityTechs`, etc.
- Issue actions by overriding the villager/agent action for that step.

---

## 9) Drag-Box Multi-Select

**Current:** Only click and shift-click selection.

**New:** Click and drag to draw selection rectangle.

**Implementation:**
1. On MouseLeft press (not on UI), record `dragStartPos` in world coords.
2. While held, draw a green rectangle from `dragStartPos` to current mouse pos.
3. On release, if drag distance > 5px:
   - Find all agents within the rectangle bounds.
   - Filter to player's team only (or all if observing).
   - Set `selection` to matched agents.
4. If drag distance <= 5px, treat as click (existing behavior).

**Selection filtering:**
- Military units preferred over villagers (if mixed, only select military).
- Or select all and let player use control groups to organize.
- Start with "select all in box" for simplicity.

**Code location:** In `tribal_village.nim` display proc, extend the existing
`window.buttonReleased[MouseLeft]` handler.

---

## 10) Hotkey System

**Hotkey categories:**

### Global Hotkeys (always active)
| Key | Action |
|-----|--------|
| Space | Play/Pause |
| +/- | Speed up/down |
| F1-F8 | Switch observed team |
| Tab | Toggle AI/Player control |
| Esc | Cancel current mode |
| M | Toggle grid |
| N | Cycle observation overlay |
| H | Select all idle villagers |
| , (comma) | Select idle military |
| . (period) | Center on last event |

### Unit Command Hotkeys (when units selected)
| Key | Action |
|-----|--------|
| A | Attack-move mode |
| S | Stop |
| P | Patrol mode |
| D | Stance cycle |
| Delete | Delete/kill selected unit |

### Villager Hotkeys (when villager selected)
| Key | Action |
|-----|--------|
| B | Open build menu |
| B, B | Build Barracks |
| B, A | Build Archery Range |
| B, S | Build Stable |
| B, W | Build Wall |
| B, G | Build Guard Tower |
| B, T | Build Town Center |
| B, H | Build House |
| B, K | Build Blacksmith |
| B, U | Build University |
| B, M | Build Market |
| B, D | Build Dock |
| B, C | Build Castle |

### Building Hotkeys (when building selected)
| Key | Action |
|-----|--------|
| Q/W/E/R/T | Train unit (position-based, left to right) |
| G | Set rally point mode |
| V | Ungarrison all |

**Implementation:**
- New `HotkeyState` object tracking:
  - `pendingPrefix: char` (e.g., 'B' for build submenu)
  - `commandMode: CommandMode` (Normal, AttackMove, Patrol, BuildPlace, RallyPoint)
- Hotkey processing in display loop before world input handling.
- Hotkey hints drawn on command panel buttons.

---

## 11) AI Takeover Toggle

**Concept:** Player can take control of one team, issuing commands that override
the AI for selected units, while unselected units continue under AI control.

**Modes:**
1. **Observer mode** (default): All teams under AI. Player can select and view but
   not command. Current behavior.
2. **Player mode:** One team designated as player-controlled.
   - Selected units follow player commands.
   - Unselected units on player's team still follow AI.
   - All other teams under AI.

**Toggle:** Press Tab to cycle: Observer -> Team 0 -> Team 1 -> ... -> Team 7 -> Observer.

**Implementation:**
- New variable: `playerTeam: int = -1` (-1 = observer mode).
- In action computation (before `env.step()`):
  - For agents on `playerTeam`: if they have pending player commands,
    compute action from command; otherwise use AI action.
  - For other teams: always AI.
- UI shows "[OBSERVING]" or "[CONTROLLING Team N]" in resource bar.

**Command queue per agent:**
- `agentCommands: array[MapAgents, seq[PendingCommand]]`
- Each frame, pop front command for each agent and compute action.
- Commands cleared when unit is deselected from player control or mode switches.

---

## 12) File Organization

### Modified files:
| File | Changes |
|------|---------|
| `src/common.nim` | Add PanelType variants, HUD rect constants, command types |
| `src/renderer.nim` | Add all new draw* procs for HUD panels |
| `tribal_village.nim` | Input handling: right-click, drag-select, hotkeys, build mode |

### New files:
| File | Purpose |
|------|---------|
| `src/hud.nim` | Resource bar, minimap, unit info panel data/logic |
| `src/commands.nim` | Player command queue, pathfinding-lite, command types |
| `src/hotkeys.nim` | Hotkey definitions, state machine, prefix handling |

### Asset needs:
| Asset | Description |
|-------|-------------|
| `data/ui/cursor_*.png` | Cursor sprites (sword, axe, enter, build) |
| `data/ui/stance_*.png` | Stance icons (aggressive, defensive, etc.) |
| `data/ui/tech_*.png` | Tech tree icons (optional, can use text) |
| `data/ui/minimap_frame.png` | Minimap border/frame |
| `data/ui/button_bg.png` | Command button background |

---

## 13) Implementation Phases

### Phase 1: Foundation (DONE)
1. ~~Resource bar HUD~~
2. ~~Unit info panel (read-only stats display)~~
3. ~~Drag-box multi-select~~

### Phase 2: Minimap & Navigation (DONE)
4. ~~Minimap rendering~~
5. ~~Minimap click-to-pan~~
6. ~~Viewport rectangle on minimap~~

### Phase 3: Command System (DONE)
7. ~~Right-click move/attack commands~~
8. ~~Command panel with context-sensitive buttons~~
9. ~~AI takeover toggle (Tab / F1-F8)~~
10. ~~Player command queue~~

### Phase 4: Building & Production (DONE)
11. ~~Building placement mode with ghost preview~~
12. ~~Research/production queue panels~~
13. ~~Rally point visualization and setting~~

### Phase 5: Polish (Partially Done)
14. ~~Hotkey system with prefix menus~~ (basic hotkeys implemented)
15. Cursor changes by context (not yet implemented)
16. ~~Selection filtering and idle unit finding~~
17. Fog of war on minimap (toggle available, not fully on minimap)

---

## 14) Performance Considerations

- **Minimap:** Cache base terrain texture. Only rebuild unit/building layer each frame.
  Full rebuild every 10 frames. Target: <1ms per frame for minimap.
- **Text labels:** Continue using existing caching pattern. New labels (resource counts)
  change infrequently; cache and invalidate on value change.
- **Command panel:** Only rebuild button layout when selection changes, not every frame.
- **Drag-box:** Simple rect draw, negligible cost.
- **Right-click pathfinding:** Direction-toward-target is O(1) per agent per frame.
  No A* needed given the 8-directional movement system.

---

## 15) Compatibility Notes

- **Emscripten/WASM:** All UI uses Boxy drawing which works on both native and WASM.
  No platform-specific APIs. Custom cursors via software rendering.
- **Python wrapper:** UI changes are Nim-only. Python FFI interface unchanged.
  Player commands are internal to the display loop, not exposed to Python.
- **Replays:** Player commands should be logged in replay data for analysis.
  Extend replay format to include player override actions.
