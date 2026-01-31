# Metta UI Audit: Reusable Features for tribal_village

**Date:** 2026-01-31
**Task:** tv-wisp-c2hg8
**Cross-reference:** docs/ui_overhaul_design.md

## Executive Summary

Mettascope has a mature UI system built on **Silky** (a Nim immediate-mode UI library) with **Boxy** for rendering. Key transferable patterns include:
1. Draggable panel system with split areas
2. ZoomInfo abstraction for pan/zoom handling
3. A* pathfinding for right-click commands
4. Modular HUD components (header, footer, timeline, object info)
5. Icon-based button patterns with state management

tribal_village currently renders UI procedurally in `renderer.nim` (1000+ lines) without a panel abstraction. The ui_overhaul_design.md already plans similar features but metta provides working implementations to borrow from.

---

## 1. Reusable UI Widgets/Panels

### 1a. Panel System (HIGH VALUE)

**Metta Files:**
- `mettascope/src/mettascope/panels.nim` (552 lines)

**Key Constructs:**
```nim
type
  AreaLayout* = enum Horizontal, Vertical
  Area* = ref object
    layout*: AreaLayout
    areas*: seq[Area]      # Child areas (for splits)
    panels*: seq[Panel]    # Panels in this area
    split*: float32        # Split ratio 0-1
    selectedPanelNum*: int
    rect*: Rect

  Panel* = ref object
    name*: string
    parentArea*: Area
    draw*: PanelDraw       # Render callback
```

**Key Procs:**
- `split*(area: Area, layout: AreaLayout)` - Split area horizontally/vertically
- `addPanel*(area: Area, name: string, draw: PanelDraw)` - Add panel to area
- `movePanel*(area: Area, panel: Panel)` - Drag panel to new area
- `drawPanels*()` - Render entire panel tree with drag-drop highlighting
- `scan*(area: Area): (Area, AreaScan, Rect)` - Hit-test for drop targets

**Adaptation Notes:**
- tribal_village doesn't need full drag-drop panel rearrangement
- BUT the Area/Panel abstraction is useful for organizing HUD regions
- Could simplify to fixed layout (no dynamic splits) while keeping render callback pattern
- Reduces renderer.nim complexity by moving HUD to dedicated modules

**Recommended Port:**
- Simplified `Panel` type with fixed positions (no dynamic layout)
- Keep the `draw: PanelDraw` callback pattern
- Each HUD region (minimap, unit info, command panel) becomes a Panel

---

### 1b. ZoomInfo for Pan/Zoom (HIGH VALUE)

**Metta Files:**
- `mettascope/src/mettascope/panels.nim:29-40`

**Key Constructs:**
```nim
type ZoomInfo* = ref object
  rect*: IRect           # Viewport rect in screen coords
  pos*: Vec2             # Pan offset
  vel*: Vec2             # Pan velocity (for momentum)
  zoom*: float32         # Current zoom level
  zoomVel*: float32      # Zoom velocity
  minZoom*, maxZoom*: float32
  scrollArea*: Rect
  hasMouse*: bool        # Mouse is over this area
  dragging*: bool
```

**Key Procs:**
- `beginPanAndZoom*(zoomInfo: ZoomInfo)` - Sets up transform, handles input
- `endPanAndZoom*(zoomInfo: ZoomInfo)` - Restores transform
- `clampMapPan*(zoomInfo: ZoomInfo)` - Keep map visible
- `fitFullMap*(zoomInfo: ZoomInfo)` - Zoom to show entire map
- `fitVisibleMap*(zoomInfo: ZoomInfo)` - Zoom to visible agents
- `centerAt*(zoomInfo: ZoomInfo, entity: Entity)` - Focus on entity

**Adaptation Notes:**
- tribal_village uses raw `pos`, `zoom` in Panel type (common.nim)
- Metta's approach is cleaner - encapsulates all pan/zoom state
- The `beginPanAndZoom/endPanAndZoom` bracketing is elegant
- Focal-point zoom (zoom at mouse position) is already implemented in metta

**Recommended Port:**
- Extract ZoomInfo as standalone type (could go in common.nim or new zoom.nim)
- Use the begin/end pattern in tribal_village.nim display proc
- Port `clampMapPan` - tribal_village doesn't have this, map can scroll off-screen

---

## 2. Input Handling Patterns

### 2a. Mouse Selection and Right-Click Commands (HIGH VALUE)

**Metta Files:**
- `mettascope/src/mettascope/worldmap.nim:215-310` (useSelections proc)

**Key Pattern:**
```nim
proc useSelections*(zoomInfo: ZoomInfo) =
  # Track mouse down position to distinguish clicks from drags
  if window.buttonPressed[MouseLeft] and not modifierDown:
    mouseDownPos = window.mousePos.vec2

  # Only select on mouse up if we didn't drag much
  if window.buttonReleased[MouseLeft] and not modifierDown:
    let mouseDragDistance = (window.mousePos.vec2 - mouseDownPos).length
    const maxClickDragDistance = 5.0
    if mouseDragDistance < maxClickDragDistance:
      # ... selection logic
```

**Right-Click Commands:**
```nim
if window.buttonPressed[MouseRight] or (window.buttonPressed[MouseLeft] and modifierDown):
  if selection != nil and selection.isAgent:
    # Determine if Bump or Move objective
    let targetObj = getObjectAtLocation(gridPos)
    var objective: Objective
    if targetObj != nil:
      # Calculate approach direction from click quadrant
      objective = Objective(kind: Bump, pos: gridPos, approachDir: approachDir)
    else:
      objective = Objective(kind: Move, pos: gridPos)

    if shiftDown:
      # Queue additional objectives
      agentObjectives[agentId].add(objective)
    else:
      # Replace objective queue
      agentObjectives[agentId] = @[objective]
    recomputePath(agentId, startPos)
```

**Adaptation Notes:**
- tribal_village already has click-to-select and shift-click multi-select
- Missing: right-click commands, shift+right-click waypoint queuing
- The "click vs drag" detection (5px threshold) is useful pattern
- Approach direction from click quadrant is clever for resource gathering

**Recommended Port:**
- Add `mouseDownPos` tracking to distinguish click from drag
- Implement right-click command system with objective queuing
- Port the quadrant-based approach direction for bump/interact actions

---

### 2b. Keyboard Controls (MEDIUM VALUE)

**Metta Files:**
- `mettascope/src/mettascope/actions.nim:134-159` (agentControls)
- `mettascope/src/mettascope/timeline.nim:20-66` (playControls)

**Key Patterns:**
```nim
proc agentControls*() =
  if selection != nil and selection.isAgent:
    if window.buttonPressed[KeyW] or window.buttonPressed[KeyUp]:
      sendAction(agent.agentId, "move_north")
      clearPath(agent.agentId)  # Clear queued path when manual override
```

```nim
proc playControls*() =
  if window.buttonPressed[KeySpace]: play = not play
  if window.buttonPressed[KeyMinus]: playSpeed *= 0.5
  if window.buttonPressed[KeyEqual]: playSpeed *= 2
  if window.buttonPressed[KeyLeftBracket]: step -= 1
  if window.buttonPressed[KeyRightBracket]: step += 1
```

**Adaptation Notes:**
- tribal_village already has WASD movement, space for play/pause
- Metta's `clearPath` on manual control is important - prevents conflict between queued commands and manual input
- The bracket keys for single-stepping are useful

**Recommended Port:**
- Add step-forward/step-back keyboard shortcuts
- Ensure manual movement clears any queued commands

---

## 3. HUD Components

### 3a. Header Bar (MEDIUM VALUE)

**Metta Files:**
- `mettascope/src/mettascope/header.nim` (31 lines)

**Key Pattern:**
```nim
proc drawHeader*() =
  ribbon(sk.pos, vec2(sk.size.x, 64), HeaderColor):
    image("ui/logo")
    sk.advance(vec2(8, 2))
    h1text(title)
    sk.at = sk.pos + vec2(sk.size.x - 100, 16)
    iconButton("ui/help"): openUrl(...)
    iconButton("ui/share"): openUrl(...)
```

**Adaptation Notes:**
- tribal_village doesn't have a header bar (ui_overhaul_design.md plans Resource Bar at top)
- The `ribbon()` helper from Silky is clean but tribal_village doesn't use Silky
- Pattern: position-based layout with `sk.at` and `sk.advance`

**Recommended Port:**
- Not directly portable (uses Silky)
- Concept of top-bar with icon buttons IS useful for Resource Bar HUD
- Create `drawResourceBar*()` following similar positioning pattern

---

### 3b. Footer/Playback Controls (HIGH VALUE)

**Metta Files:**
- `mettascope/src/mettascope/footer.nim` (68 lines)
- Compare with tribal_village `renderer.nim:156-272` (FooterButton system)

**Metta Pattern:**
```nim
proc drawFooter*(pos, size: Vec2) =
  ribbon(pos, size, FooterColor):
    group(vec2(0, 0), LeftToRight):
      clickableIcon("ui/rewindToStart", step != 0): step = 0
      clickableIcon("ui/stepBack", step > 0): step -= 1
      if play:
        clickableIcon("ui/pause", true): play = false
      else:
        clickableIcon("ui/play", true): play = true
      # ... more buttons

    # Speed controls
    sk.at = pos + vec2(size.x/2 - 120, 16)
    group(...):
      for i, speed in Speeds:
        clickableIcon(..., playSpeed >= speed): playSpeed = speed

    # Toggle buttons
    sk.at = pos + vec2(size.x - 240, 16)
    group(...):
      clickableIcon("ui/tack", settings.lockFocus): settings.lockFocus = not settings.lockFocus
      clickableIcon("ui/grid", settings.showGrid): settings.showGrid = not settings.showGrid
```

**tribal_village Current:**
- Has `FooterButton` type with rect, iconKey, labelKey, active state
- Uses `buildFooterButtons` and `drawFooter` procs
- Similar pattern but more verbose without Silky helpers

**Adaptation Notes:**
- tribal_village footer is already implemented but verbose
- Metta's `clickableIcon(icon, activeState): action` pattern is cleaner
- Could create helper macro/template to reduce boilerplate

**Recommended Port:**
- Keep current system but add more toggle buttons (fog, grid, etc.)
- Consider helper template like `clickableIcon` for cleaner code
- Add step-back, rewind-to-start, rewind-to-end buttons

---

### 3c. Timeline/Scrubber (MEDIUM VALUE)

**Metta Files:**
- `mettascope/src/mettascope/timeline.nim:68-73`

**Key Pattern:**
```nim
proc drawTimeline*(pos, size: Vec2) =
  ribbon(pos, size, ScrubberColor):
    let prevStepFloat = stepFloat
    scrubber("timeline", stepFloat, 0, replay.maxSteps.float32 - 1)
    if prevStepFloat != stepFloat:
      step = stepFloat.round.int
```

**Adaptation Notes:**
- tribal_village doesn't have a scrubber/timeline
- `scrubber()` is a Silky widget - would need custom implementation
- Useful for replays/debugging but not core for RTS gameplay

**Recommended Port:**
- Low priority for now
- Could add later for debug/replay mode

---

### 3d. Object Info Panel (HIGH VALUE)

**Metta Files:**
- `mettascope/src/mettascope/objectinfo.nim` (251 lines)

**Key Pattern:**
```nim
proc drawObjectInfo*(panel: Panel, frameId: string, contentPos: Vec2, contentSize: Vec2) =
  frame(frameId, contentPos, contentSize):
    if selection.isNil: text("No selection"); return

    h1text(cur.typeName)
    text(&"  Object ID: {cur.id}")

    if cur.isAgent:
      text(&"  Agent ID: {cur.agentId}")
      text(&"  Total reward: {formatFloat(reward, ffDecimal, 2)}")
    else:
      # Non-agent info
      if cooldown > 0: text(&"  Cooldown remaining: {cooldown}")

    text("Inventory")
    for itemAmount in currentInventory:
      text("  " & formatItem(itemAmount))

    # Protocols/abilities
    if cur.protocols.len > 0:
      text("Protocols")
      for protocol in sortedProtocols:
        group(..., LeftToRight):
          icon("resources/" & resourceName); text("x" & $count)
          icon("ui/right-arrow")
          # ... outputs
```

**Adaptation Notes:**
- tribal_village has `drawSelectionLabel` showing basic info in footer
- ui_overhaul_design.md plans Unit Info Panel (right side, 240px wide)
- Metta shows: type, ID, stats, inventory, abilities/protocols
- tribal_village would show: type, HP bar, attack/armor, stance, inventory

**Recommended Port:**
- Create `drawUnitInfoPanel*()` proc
- Show: unit sprite, name, team, HP bar, attack/armor stats, stance, status
- For buildings: show production queue with progress bars
- Use text caching pattern from tribal_village footer labels

---

## 4. Command/Action Dispatching

### 4a. Action Request System (HIGH VALUE)

**Metta Files:**
- `mettascope/src/mettascope/actions.nim:13-19`
- `mettascope/src/mettascope/common.nim:66-103`

**Key Constructs:**
```nim
type
  ActionRequest* = object
    agentId*: int
    actionName*: cstring

  ObjectiveKind* = enum
    Move   # Move to position
    Bump   # Interact with object at position
    Vibe   # Execute specific action

  Objective* = object
    case kind*: ObjectiveKind
    of Move, Bump:
      pos*: IVec2
      approachDir*: IVec2
    of Vibe:
      vibeActionId*: int
    repeat*: bool  # Re-queue when completed

var
  requestActions*: seq[ActionRequest]
  agentPaths* = initTable[int, seq[PathAction]]()
  agentObjectives* = initTable[int, seq[Objective]]()
```

**Key Procs:**
```nim
proc sendAction*(agentId: int, actionName: cstring) =
  requestActions.add(ActionRequest(agentId: agentId, actionName: actionName))
  requestPython = true

proc processActions*() =
  for agentId in agentPaths.keys:
    let pathActions = agentPaths[agentId]
    if pathActions.len == 0: continue
    let nextAction = pathActions[0]
    case nextAction.kind
    of Move:
      sendAction(agentId, getMoveActionName(orientation))
      agentPaths[agentId].delete(0)
    of Bump:
      sendAction(agentId, getMoveActionName(targetOrientation))
      agentPaths[agentId].delete(0)
    of Vibe:
      sendAction(agentId, replay.actionNames[nextAction.vibeActionId])
      agentPaths[agentId].delete(0)
```

**Adaptation Notes:**
- tribal_village uses direct action execution in environment
- For player control, need command queue per agent (ui_overhaul_design.md: `agentCommands: array[MapAgents, seq[PendingCommand]]`)
- Metta's Objective system with repeat flag is useful for patrol/repeat commands

**Recommended Port:**
- Create `PendingCommand` type similar to metta's `Objective`
- Add `commandQueue: seq[PendingCommand]` per agent or global table
- Process queue each frame before env.step()
- Add `repeat` flag for patrol commands

---

### 4b. A* Pathfinding (HIGH VALUE)

**Metta Files:**
- `mettascope/src/mettascope/pathfinding.nim` (147 lines)

**Key Procs:**
```nim
proc findPath*(start, goal: IVec2): seq[IVec2] =
  ## A* pathfinding with cardinal directions only
  var openHeap = initHeapQueue[PathNode]()
  openHeap.push(PathNode(pos: start, gCost: 0, hCost: heuristic(start, goal), parent: -1))
  var closedSet = initHashSet[IVec2]()
  # ... standard A* implementation

proc recomputePath*(agentId: int, currentPos: IVec2) =
  ## Recompute path through all queued objectives
  for objective in agentObjectives[agentId]:
    case objective.kind
    of Move:
      let movePath = findPath(lastPos, objective.pos)
      for pos in movePath:
        pathActions.add(PathAction(kind: Move, pos: pos))
    of Bump:
      let approachPos = objective.pos + objective.approachDir
      let movePath = findPath(lastPos, approachPos)
      # ... add path + bump action
```

**Adaptation Notes:**
- ui_overhaul_design.md says: "No A* needed given 8-directional movement" - uses direction-toward-target
- But metta's A* is simple and works well
- For proper RTS feel, A* IS needed (units walk around obstacles)
- tribal_village has 8-directional movement, metta uses 4-directional

**Recommended Port:**
- Port A* with 8-directional support (add diagonal neighbors)
- Use `isWalkablePos` that checks terrain and things
- Cache paths and recompute on objective change

---

## 5. Nim UI Framework Usage

### 5a. Silky Library (MEDIUM VALUE)

**Metta Uses:**
- `silky` - Immediate-mode UI library for Nim
- Built on top of Boxy (GPU-accelerated 2D rendering)

**Key Silky Features:**
- `ribbon()`, `frame()`, `group()` - Layout helpers
- `text()`, `h1text()` - Text rendering with caching
- `button()`, `iconButton()`, `clickableIcon()` - Interactive elements
- `scrubber()` - Slider widget
- 9-patch rendering for panels
- Font loading and atlas generation

**tribal_village Current:**
- Uses Boxy directly for all rendering
- Manual text rendering with pixie
- Custom label caching system
- No layout helpers

**Adaptation Notes:**
- Adding Silky as dependency would simplify UI code significantly
- BUT tribal_village already has established patterns
- Could port specific helpers (like clickableIcon template) without full Silky

**Recommended Approach:**
- Don't add Silky dependency (avoid major refactor)
- Port useful patterns: button state handling, text caching
- Create thin helper procs/templates for common operations

---

## 6. Priority Recommendations

### Immediate (Port Now)

1. **ZoomInfo abstraction** - `panels.nim:29-40`
   - Clean separation of pan/zoom state
   - Includes clamp logic missing in tribal_village

2. **Right-click command system** - `worldmap.nim:251-309`, `common.nim:66-103`
   - Objective types (Move, Bump)
   - Queue management with shift modifier
   - Essential for RTS gameplay

3. **A* Pathfinding** - `pathfinding.nim`
   - Simple implementation, easy to extend to 8-directional
   - Needed for proper unit movement

### High Priority (Port Soon)

4. **Object Info Panel pattern** - `objectinfo.nim`
   - Vertical layout with sections
   - Inventory display with icons
   - Stats with formatted output

5. **Click vs Drag detection** - `worldmap.nim:226-239`
   - 5px threshold pattern
   - Prevents accidental selection during pan

6. **Footer toggle buttons** - `footer.nim`
   - Pattern for icon toggles (fog, grid, etc.)
   - Visual feedback for active state

### Medium Priority (Consider Later)

7. **Panel system (simplified)** - `panels.nim`
   - Fixed layout version without drag-drop
   - Organizes code better

8. **Timeline scrubber** - `timeline.nim`
   - For debug/replay mode

9. **Header bar** - `header.nim`
   - Pattern for top resource bar

---

## 7. File Mapping Summary

| tribal_village File | Metta Equivalent | Notes |
|---------------------|------------------|-------|
| `src/renderer.nim` | `worldmap.nim`, `objectinfo.nim`, `minimap.nim` | Split into focused modules |
| `src/common.nim` | `common.nim`, `panels.nim` | Add ZoomInfo, command types |
| `tribal_village.nim` | `mettascope.nim` | Main loop, input handling |
| (new) `src/commands.nim` | `actions.nim`, `pathfinding.nim` | Player command system |
| (new) `src/hud.nim` | `header.nim`, `footer.nim`, `objectinfo.nim` | HUD components |

---

## 8. Code Snippets Ready to Port

### ZoomInfo Type (copy directly)
```nim
type ZoomInfo* = ref object
  rect*: IRect
  pos*: Vec2
  vel*: Vec2
  zoom*: float32 = 10
  zoomVel*: float32
  minZoom*: float32 = 0.5
  maxZoom*: float32 = 50
  scrollArea*: Rect
  hasMouse*: bool = false
  dragging*: bool = false
```

### Objective/Command Types (adapt)
```nim
type
  CommandKind* = enum
    CmdMove
    CmdAttackMove
    CmdGather
    CmdBuild
    CmdPatrol

  PendingCommand* = object
    case kind*: CommandKind
    of CmdMove, CmdAttackMove, CmdGather, CmdPatrol:
      targetPos*: IVec2
    of CmdBuild:
      buildingKind*: ThingKind
      buildPos*: IVec2
    repeat*: bool
```

### Click vs Drag Pattern (adapt)
```nim
var mouseDownPos: Vec2

# On mouse down
if window.buttonPressed[MouseLeft]:
  mouseDownPos = window.mousePos.vec2

# On mouse up
if window.buttonReleased[MouseLeft]:
  let dragDist = (window.mousePos.vec2 - mouseDownPos).length
  if dragDist < 5.0:
    # This was a click, not a drag
    handleClick(window.mousePos.vec2)
```
