## UI Test Harness: Testing infrastructure for AoE2-style UI components
##
## Provides utilities for testing UI state without rendering:
## - Selection state management
## - Input simulation helpers
## - UI state assertions
## - Command panel logic testing
## - Minimap coordinate conversion tests

import environment
import agent_control
import common
import types
import items
import command_panel

# Re-export clearSelection from agent_control for convenience
export agent_control.clearSelection

# ---------------------------------------------------------------------------
# Selection Testing Utilities
# ---------------------------------------------------------------------------

proc resetSelection*() =
  ## Clear the current selection and reset selectedPos.
  selection = @[]
  selectedPos = ivec2(-1, -1)

proc selectThing*(thing: Thing) =
  ## Set selection to a single thing.
  selection = @[thing]
  if not isNil(thing) and isValidPos(thing.pos):
    selectedPos = thing.pos

proc selectThings*(things: seq[Thing]) =
  ## Set selection to multiple things.
  selection = things
  if things.len > 0 and not isNil(things[0]) and isValidPos(things[0].pos):
    selectedPos = things[0].pos
  else:
    selectedPos = ivec2(-1, -1)

proc addThingToSelection*(thing: Thing) =
  ## Add a thing to the current selection (shift-click behavior).
  if isNil(thing):
    return
  for s in selection:
    if s == thing:
      return  # Already in selection
  selection.add(thing)

proc removeThingFromSelection*(thing: Thing) =
  ## Remove a thing from selection (shift-click toggle).
  for i, s in selection:
    if s == thing:
      selection.delete(i)
      return

proc isSelected*(thing: Thing): bool =
  ## Check if a thing is currently selected.
  for s in selection:
    if s == thing:
      return true
  false

proc selectionCount*(): int =
  ## Get the number of selected items.
  selection.len

# ---------------------------------------------------------------------------
# Player Team / AI Takeover Testing
# ---------------------------------------------------------------------------

proc setPlayerTeam*(team: int) =
  ## Set the player-controlled team (-1 for observer mode).
  playerTeam = team

proc getPlayerTeam*(): int =
  ## Get the current player team.
  playerTeam

proc isObserverMode*(): bool =
  ## Check if we're in observer mode.
  playerTeam < 0

proc cyclePlayerTeam*() =
  ## Simulate Tab key press to cycle teams.
  playerTeam = (playerTeam + 2) mod (MapRoomObjectsTeams + 1) - 1

# ---------------------------------------------------------------------------
# Command Panel Testing
# ---------------------------------------------------------------------------

proc getCommandButtonsForSelection*(panelRect: IRect): seq[CommandButton] =
  ## Get the command buttons that would be shown for current selection.
  buildCommandButtons(panelRect)

proc getCommandButtonKinds*(panelRect: IRect): seq[CommandButtonKind] =
  ## Get just the button kinds for current selection.
  let buttons = buildCommandButtons(panelRect)
  result = @[]
  for b in buttons:
    result.add(b.kind)

proc hasCommandButton*(panelRect: IRect, kind: CommandButtonKind): bool =
  ## Check if a specific command button is available.
  let buttons = buildCommandButtons(panelRect)
  for b in buttons:
    if b.kind == kind:
      return true
  false

proc countCommandButtons*(panelRect: IRect): int =
  ## Count how many command buttons are shown.
  buildCommandButtons(panelRect).len

# ---------------------------------------------------------------------------
# Drag-Box Selection Simulation
# ---------------------------------------------------------------------------

type DragBoxResult* = object
  agents*: seq[Thing]
  filterByTeam*: bool
  teamId*: int

proc simulateDragBox*(env: Environment, startWorld: Vec2, endWorld: Vec2,
                      filterTeam: int = -1): DragBoxResult =
  ## Simulate a drag-box selection and return agents within the box.
  ## If filterTeam >= 0, only include agents from that team.
  let minX = min(startWorld.x, endWorld.x)
  let maxX = max(startWorld.x, endWorld.x)
  let minY = min(startWorld.y, endWorld.y)
  let maxY = max(startWorld.y, endWorld.y)

  result.agents = @[]
  result.filterByTeam = filterTeam >= 0
  result.teamId = filterTeam

  for agent in env.thingsByKind[Agent]:
    if not env.isAgentAlive(agent):
      continue
    let ax = agent.pos.x.float32
    let ay = agent.pos.y.float32
    if ax >= minX and ax <= maxX and ay >= minY and ay <= maxY:
      if filterTeam >= 0:
        let agentTeam = getTeamId(agent)
        if agentTeam == filterTeam:
          result.agents.add(agent)
      else:
        result.agents.add(agent)

proc applyDragBoxSelection*(env: Environment, startWorld: Vec2, endWorld: Vec2,
                            filterTeam: int = -1) =
  ## Apply a drag-box selection to the global selection state.
  let dragResult = simulateDragBox(env, startWorld, endWorld, filterTeam)
  if dragResult.agents.len > 0:
    selection = dragResult.agents
    selectedPos = dragResult.agents[0].pos
  else:
    selection = @[]

# ---------------------------------------------------------------------------
# UI Panel Hit Testing
# ---------------------------------------------------------------------------

proc makeTestPanelRect*(width: int = 1280, height: int = 720): IRect =
  ## Create a standard test panel rect.
  IRect(x: 0, y: 0, w: width, h: height)

proc isInResourceBarArea*(panelRect: IRect, screenPos: Vec2): bool =
  ## Check if a screen position is within the resource bar HUD area.
  ## Note: Resource bar is offset down by half its height to avoid top clipping.
  let barTop = panelRect.y.float32 + ResourceBarHeight.float32 * 0.5
  screenPos.y >= barTop and
    screenPos.y <= barTop + ResourceBarHeight.float32

proc isInFooterArea*(panelRect: IRect, screenPos: Vec2): bool =
  ## Check if a screen position is within the footer area.
  let footerY = panelRect.y.float32 + panelRect.h.float32 - FooterHeight.float32
  screenPos.y >= footerY and screenPos.y <= panelRect.y.float32 + panelRect.h.float32

proc isInMinimapArea*(panelRect: IRect, screenPos: Vec2): bool =
  ## Check if a screen position is within the minimap area.
  let mmX = panelRect.x.float32 + MinimapMargin.float32
  let mmY = panelRect.y.float32 + panelRect.h.float32 - FooterHeight.float32 -
            MinimapSize.float32 - MinimapMargin.float32
  screenPos.x >= mmX and screenPos.x <= mmX + MinimapSize.float32 and
    screenPos.y >= mmY and screenPos.y <= mmY + MinimapSize.float32

proc isInUnitInfoPanelArea*(panelRect: IRect, screenPos: Vec2): bool =
  ## Check if a screen position is within the unit info panel area.
  ## Unit info panel is on the right side, upper portion.
  let panelX = panelRect.x.float32 + panelRect.w.float32 - 240.0 - 12.0  # UnitInfoPanelWidth + padding
  let panelY = panelRect.y.float32 + 40.0
  let panelH = panelRect.h.float32 * 0.45
  screenPos.x >= panelX and screenPos.x <= panelRect.x.float32 + panelRect.w.float32 and
    screenPos.y >= panelY and screenPos.y <= panelY + panelH

# ---------------------------------------------------------------------------
# Minimap Coordinate Conversion Testing
# ---------------------------------------------------------------------------

proc worldToMinimapPixel*(worldPos: IVec2, panelRect: IRect): Vec2 =
  ## Convert world coordinates to minimap pixel position.
  let mmX = panelRect.x.float32 + MinimapMargin.float32
  let mmY = panelRect.y.float32 + panelRect.h.float32 - FooterHeight.float32 -
            MinimapSize.float32 - MinimapMargin.float32
  let scaleX = MinimapSize.float32 / MapWidth.float32
  let scaleY = MinimapSize.float32 / MapHeight.float32
  vec2(mmX + worldPos.x.float32 * scaleX, mmY + worldPos.y.float32 * scaleY)

proc minimapPixelToWorld*(minimapPos: Vec2, panelRect: IRect): IVec2 =
  ## Convert minimap pixel position to world coordinates.
  let mmX = panelRect.x.float32 + MinimapMargin.float32
  let mmY = panelRect.y.float32 + panelRect.h.float32 - FooterHeight.float32 -
            MinimapSize.float32 - MinimapMargin.float32
  let scaleX = MinimapSize.float32 / MapWidth.float32
  let scaleY = MinimapSize.float32 / MapHeight.float32
  let wx = int((minimapPos.x - mmX) / scaleX)
  let wy = int((minimapPos.y - mmY) / scaleY)
  ivec2(clamp(wx, 0, MapWidth - 1), clamp(wy, 0, MapHeight - 1))

# ---------------------------------------------------------------------------
# Resource Bar State Testing
# ---------------------------------------------------------------------------

type ResourceBarState* = object
  food*: int
  wood*: int
  stone*: int
  gold*: int
  popCurrent*: int
  popCap*: int
  stepNumber*: int32

proc getResourceBarState*(env: Environment, teamId: int): ResourceBarState =
  ## Get the state that would be displayed in the resource bar.
  let validTeamId = if teamId >= 0 and teamId < MapRoomObjectsTeams: teamId else: 0

  result.food = env.teamStockpiles[validTeamId].counts[ResourceFood]
  result.wood = env.teamStockpiles[validTeamId].counts[ResourceWood]
  result.stone = env.teamStockpiles[validTeamId].counts[ResourceStone]
  result.gold = env.teamStockpiles[validTeamId].counts[ResourceGold]
  result.stepNumber = env.currentStep.int32

  # Count population for this team
  result.popCurrent = 0
  for agent in env.agents:
    if isAgentAlive(env, agent):
      if getTeamId(agent) == validTeamId:
        inc result.popCurrent

  # Calculate pop cap from houses and town centers
  result.popCap = 0
  for house in env.thingsByKind[House]:
    if house.teamId == validTeamId:
      result.popCap += HousePopCap
  for tc in env.thingsByKind[TownCenter]:
    if tc.teamId == validTeamId:
      result.popCap += TownCenterPopCap
  result.popCap = min(result.popCap, MapAgentsPerTeam)

# ---------------------------------------------------------------------------
# Unit Info Panel State Testing
# ---------------------------------------------------------------------------

type UnitInfoState* = object
  isSingleUnit*: bool
  isSingleBuilding*: bool
  isMultiSelect*: bool
  unitName*: string
  teamId*: int
  hp*: int
  maxHp*: int
  attackDamage*: int
  stance*: AgentStance
  isIdle*: bool
  unitCount*: int

proc getUnitInfoState*(): UnitInfoState =
  ## Get the state that would be displayed in the unit info panel.
  if selection.len == 0:
    return UnitInfoState()

  if selection.len == 1:
    let thing = selection[0]
    if thing.kind == Agent:
      result.isSingleUnit = true
      result.unitName = $thing.unitClass
      result.teamId = getTeamId(thing)
      result.hp = thing.hp
      result.maxHp = thing.maxHp
      result.attackDamage = thing.attackDamage
      result.stance = thing.stance
      result.isIdle = thing.isIdle
      result.unitCount = 1
    elif isBuildingKind(thing.kind):
      result.isSingleBuilding = true
      result.unitName = $thing.kind
      result.teamId = thing.teamId
      result.hp = thing.hp
      result.maxHp = thing.maxHp
      result.unitCount = 1
  else:
    result.isMultiSelect = true
    result.unitCount = selection.len

# ---------------------------------------------------------------------------
# Control Group Testing
# ---------------------------------------------------------------------------

const ControlGroupCount* = 10

var testControlGroups*: array[ControlGroupCount, seq[Thing]]

proc clearTestControlGroups*() =
  ## Clear all control groups.
  for i in 0 ..< ControlGroupCount:
    testControlGroups[i] = @[]

proc assignControlGroup*(groupIndex: int) =
  ## Assign current selection to a control group (Ctrl+N behavior).
  if groupIndex >= 0 and groupIndex < ControlGroupCount:
    testControlGroups[groupIndex] = selection

proc recallControlGroup*(groupIndex: int) =
  ## Recall a control group (N key behavior).
  if groupIndex >= 0 and groupIndex < ControlGroupCount:
    selection = testControlGroups[groupIndex]
    if selection.len > 0 and not isNil(selection[0]) and isValidPos(selection[0].pos):
      selectedPos = selection[0].pos
