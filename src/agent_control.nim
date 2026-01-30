## Unified Action Interface for Agent Control
## Supports both external neural network control and built-in AI control
## Controller type is specified when creating the environment

import std/os, std/strutils

include "scripted/ai_core"
include "scripted/ai_defaults"

const
  ActionsFile = "actions.tmp"

type
  ControllerType* = enum
    BuiltinAI,      # Use built-in Nim AI controller
    ExternalNN      # Use external neural network (Python)

  AgentController* = ref object
    controllerType*: ControllerType
    # Built-in AI controller (when using BuiltinAI)
    aiController*: Controller
    # External action callback (when using ExternalNN)
    externalActionCallback*: proc(): array[MapAgents, uint8]

# Global agent controller instance
var globalController*: AgentController

proc initGlobalController*(controllerType: ControllerType, seed: int = int(nowSeconds() * 1000)) =
  ## Initialize the global controller with specified type
  case controllerType:
  of BuiltinAI:
    globalController = AgentController(
      controllerType: BuiltinAI,
      aiController: newController(seed),
      externalActionCallback: nil
    )
  of ExternalNN:
    # External callback will be set later via setExternalActionCallback
    globalController = AgentController(
      controllerType: ExternalNN,
      aiController: nil,
      externalActionCallback: nil
    )
    # Start automatic play mode for external controller
    play = true

proc setExternalActionCallback*(callback: proc(): array[MapAgents, uint8]) =
  ## Set the external action callback for neural network control
  if not isNil(globalController) and globalController.controllerType == ExternalNN:
    globalController.externalActionCallback = callback

proc getActions*(env: Environment): array[MapAgents, uint8] =
  ## Get actions for all agents using the configured controller
  case globalController.controllerType
  of BuiltinAI:
    var actions: array[MapAgents, uint8]
    for i in 0 ..< env.agents.len:
      actions[i] = globalController.aiController.decideAction(env, i)
    globalController.aiController.updateController(env)
    return actions
  of ExternalNN:
    if not isNil(globalController.externalActionCallback):
      return globalController.externalActionCallback()

    if fileExists(ActionsFile):
      try:
        let lines = readFile(ActionsFile).replace("\r", "").replace("\n\n", "\n").split("\n")
        if lines.len >= MapAgents:
          var fileActions: array[MapAgents, uint8]
          for i in 0 ..< MapAgents:
            let parts = lines[i].split(',')
            if parts.len >= 2:
              fileActions[i] = encodeAction(parseInt(parts[0]).uint8, parseInt(parts[1]).uint8)
            elif parts.len == 1 and parts[0].len > 0:
              fileActions[i] = parseInt(parts[0]).uint8

          discard tryRemoveFile(ActionsFile)

          return fileActions
      except CatchableError:
        discard

  echo "❌ FATAL ERROR: ExternalNN controller configured but no callback or actions file found!"
  echo "Python environment must call setExternalActionCallback() or provide " & ActionsFile & "!"
  raise newException(ValueError, "ExternalNN controller has no actions - Python communication failed!")

# Attack-Move API
# These functions allow external code to set attack-move targets for agents.
# Attack-move: unit moves toward destination, attacking any enemies encountered along the way.

proc setAgentAttackMoveTarget*(agentId: int, target: IVec2) =
  ## Set an attack-move target for an agent.
  ## The agent will move toward the target while engaging enemies along the way.
  ## Requires BuiltinAI controller.
  if not isNil(globalController) and globalController.controllerType == BuiltinAI:
    globalController.aiController.setAttackMoveTarget(agentId, target)

proc setAgentAttackMoveTargetXY*(agentId: int, x, y: int32) =
  ## Set an attack-move target for an agent using x,y coordinates.
  setAgentAttackMoveTarget(agentId, ivec2(x, y))

proc clearAgentAttackMoveTarget*(agentId: int) =
  ## Clear the attack-move target for an agent, stopping attack-move behavior.
  if not isNil(globalController) and globalController.controllerType == BuiltinAI:
    globalController.aiController.clearAttackMoveTarget(agentId)

proc getAgentAttackMoveTarget*(agentId: int): IVec2 =
  ## Get the current attack-move target for an agent.
  ## Returns (-1, -1) if no attack-move is active.
  if not isNil(globalController) and globalController.controllerType == BuiltinAI:
    return globalController.aiController.getAttackMoveTarget(agentId)
  ivec2(-1, -1)

proc isAgentAttackMoveActive*(agentId: int): bool =
  ## Check if an agent currently has an active attack-move target.
  let target = getAgentAttackMoveTarget(agentId)
  target.x >= 0

# Patrol API
# These functions allow external code to set patrol behavior for agents.
# Patrol: unit walks back and forth between two waypoints, attacking enemies encountered.

proc setAgentPatrol*(agentId: int, point1, point2: IVec2) =
  ## Set patrol waypoints for an agent. Enables patrol mode.
  ## The agent will walk between the two points, attacking any enemies encountered.
  ## Requires BuiltinAI controller.
  if not isNil(globalController) and globalController.controllerType == BuiltinAI:
    globalController.aiController.setPatrol(agentId, point1, point2)

proc setAgentPatrolXY*(agentId: int, x1, y1, x2, y2: int32) =
  ## Set patrol waypoints for an agent using x,y coordinates.
  setAgentPatrol(agentId, ivec2(x1, y1), ivec2(x2, y2))

proc clearAgentPatrol*(agentId: int) =
  ## Clear the patrol for an agent, disabling patrol mode.
  if not isNil(globalController) and globalController.controllerType == BuiltinAI:
    globalController.aiController.clearPatrol(agentId)

proc getAgentPatrolTarget*(agentId: int): IVec2 =
  ## Get the current patrol target waypoint for an agent.
  ## Returns (-1, -1) if no patrol is active.
  if not isNil(globalController) and globalController.controllerType == BuiltinAI:
    return globalController.aiController.getPatrolTarget(agentId)
  ivec2(-1, -1)

proc isAgentPatrolActive*(agentId: int): bool =
  ## Check if an agent currently has patrol mode active.
  if not isNil(globalController) and globalController.controllerType == BuiltinAI:
    return globalController.aiController.isPatrolActive(agentId)
  false

# Stance API
# These functions allow external code to set combat stance for agents.

proc setAgentStance*(env: Environment, agentId: int, stance: AgentStance) =
  ## Set the combat stance for an agent.
  if agentId >= 0 and agentId < env.agents.len:
    let agent = env.agents[agentId]
    if isAgentAlive(env, agent):
      agent.stance = stance

proc getAgentStance*(env: Environment, agentId: int): AgentStance =
  ## Get the current combat stance for an agent.
  if agentId >= 0 and agentId < env.agents.len:
    let agent = env.agents[agentId]
    if isAgentAlive(env, agent):
      return agent.stance
  StanceDefensive

# Garrison API
# These functions allow external code to garrison/ungarrison units.

proc garrisonAgentInBuilding*(env: Environment, agentId: int, buildingX, buildingY: int32): bool =
  ## Garrison an agent into the building at the given position.
  ## Returns true if successful.
  if agentId < 0 or agentId >= env.agents.len:
    return false
  let agent = env.agents[agentId]
  if not isAgentAlive(env, agent):
    return false
  let pos = ivec2(buildingX, buildingY)
  if not isValidPos(pos):
    return false
  let thing = env.grid[pos.x][pos.y]
  if isNil(thing) or not isBuildingKind(thing.kind):
    return false
  garrisonUnitInBuilding(env, agent, thing)

proc ungarrisonAllFromBuilding*(env: Environment, buildingX, buildingY: int32): int32 =
  ## Ungarrison all units from the building at the given position.
  ## Returns the number of units ungarrisoned.
  let pos = ivec2(buildingX, buildingY)
  if not isValidPos(pos):
    return 0
  let thing = env.grid[pos.x][pos.y]
  if isNil(thing) or not isBuildingKind(thing.kind):
    return 0
  let units = ungarrisonAllUnits(env, thing)
  units.len.int32

proc getGarrisonCount*(env: Environment, buildingX, buildingY: int32): int32 =
  ## Get the number of units garrisoned in the building at the given position.
  let pos = ivec2(buildingX, buildingY)
  if not isValidPos(pos):
    return 0
  let thing = env.grid[pos.x][pos.y]
  if isNil(thing) or not isBuildingKind(thing.kind):
    return 0
  thing.garrisonedUnits.len.int32

# Production Queue API
# These functions allow external code to queue/cancel unit training at buildings.

proc queueUnitTraining*(env: Environment, buildingX, buildingY: int32, teamId: int32): bool =
  ## Queue a unit for training at the building at the given position.
  ## The unit type and cost are determined by the building type.
  ## Returns true if successfully queued.
  let pos = ivec2(buildingX, buildingY)
  if not isValidPos(pos):
    return false
  let thing = env.grid[pos.x][pos.y]
  if isNil(thing) or not isBuildingKind(thing.kind):
    return false
  if not buildingHasTrain(thing.kind):
    return false
  let unitClass = buildingTrainUnit(thing.kind, teamId)
  let costs = buildingTrainCosts(thing.kind)
  queueTrainUnit(env, thing, teamId, unitClass, costs)

proc cancelLastQueuedUnit*(env: Environment, buildingX, buildingY: int32): bool =
  ## Cancel the last unit in the production queue at the given building.
  ## Returns true if a unit was cancelled.
  let pos = ivec2(buildingX, buildingY)
  if not isValidPos(pos):
    return false
  let thing = env.grid[pos.x][pos.y]
  if isNil(thing) or not isBuildingKind(thing.kind):
    return false
  cancelLastQueued(env, thing)

proc getProductionQueueSize*(env: Environment, buildingX, buildingY: int32): int32 =
  ## Get the number of units in the production queue at the given building.
  let pos = ivec2(buildingX, buildingY)
  if not isValidPos(pos):
    return 0
  let thing = env.grid[pos.x][pos.y]
  if isNil(thing) or not isBuildingKind(thing.kind):
    return 0
  thing.productionQueue.entries.len.int32

proc getProductionQueueEntryProgress*(env: Environment, buildingX, buildingY: int32, index: int32): int32 =
  ## Get the remaining steps for a production queue entry.
  ## Returns -1 if invalid.
  let pos = ivec2(buildingX, buildingY)
  if not isValidPos(pos):
    return -1
  let thing = env.grid[pos.x][pos.y]
  if isNil(thing) or not isBuildingKind(thing.kind):
    return -1
  if index < 0 or index >= thing.productionQueue.entries.len.int32:
    return -1
  thing.productionQueue.entries[index].remainingSteps.int32

# Research API
# These functions allow external code to research technologies at buildings.

proc researchBlacksmithUpgrade*(env: Environment, agentId: int, buildingX, buildingY: int32): bool =
  ## Research the next blacksmith upgrade at the given building.
  ## The agent must be a villager at the building.
  if agentId < 0 or agentId >= env.agents.len:
    return false
  let agent = env.agents[agentId]
  if not isAgentAlive(env, agent):
    return false
  let pos = ivec2(buildingX, buildingY)
  if not isValidPos(pos):
    return false
  let thing = env.grid[pos.x][pos.y]
  if isNil(thing) or thing.kind != Blacksmith:
    return false
  tryResearchBlacksmithUpgrade(env, agent, thing)

proc researchUniversityTech*(env: Environment, agentId: int, buildingX, buildingY: int32): bool =
  ## Research the next university technology at the given building.
  if agentId < 0 or agentId >= env.agents.len:
    return false
  let agent = env.agents[agentId]
  if not isAgentAlive(env, agent):
    return false
  let pos = ivec2(buildingX, buildingY)
  if not isValidPos(pos):
    return false
  let thing = env.grid[pos.x][pos.y]
  if isNil(thing) or thing.kind != University:
    return false
  tryResearchUniversityTech(env, agent, thing)

proc researchCastleTech*(env: Environment, agentId: int, buildingX, buildingY: int32): bool =
  ## Research the next castle unique technology at the given building.
  if agentId < 0 or agentId >= env.agents.len:
    return false
  let agent = env.agents[agentId]
  if not isAgentAlive(env, agent):
    return false
  let pos = ivec2(buildingX, buildingY)
  if not isValidPos(pos):
    return false
  let thing = env.grid[pos.x][pos.y]
  if isNil(thing) or thing.kind != Castle:
    return false
  tryResearchCastleTech(env, agent, thing)

proc researchUnitUpgrade*(env: Environment, agentId: int, buildingX, buildingY: int32): bool =
  ## Research the next unit upgrade at the given building.
  if agentId < 0 or agentId >= env.agents.len:
    return false
  let agent = env.agents[agentId]
  if not isAgentAlive(env, agent):
    return false
  let pos = ivec2(buildingX, buildingY)
  if not isValidPos(pos):
    return false
  let thing = env.grid[pos.x][pos.y]
  if isNil(thing):
    return false
  tryResearchUnitUpgrade(env, agent, thing)

proc hasBlacksmithUpgrade*(env: Environment, teamId: int, upgradeType: int32): int32 =
  ## Get the current level of a blacksmith upgrade for a team.
  ## upgradeType: 0=MeleeAttack, 1=ArcherAttack, 2=InfantryArmor, 3=CavalryArmor, 4=ArcherArmor
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return 0
  if upgradeType < 0 or upgradeType > ord(BlacksmithUpgradeType.high).int32:
    return 0
  env.teamBlacksmithUpgrades[teamId].levels[BlacksmithUpgradeType(upgradeType)].int32

proc hasUniversityTechResearched*(env: Environment, teamId: int, techType: int32): bool =
  ## Check if a university tech has been researched for a team.
  ## techType: 0=Ballistics, 1=MurderHoles, 2=Masonry, etc.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false
  if techType < 0 or techType > ord(UniversityTechType.high).int32:
    return false
  hasUniversityTech(env, teamId, UniversityTechType(techType))

proc hasCastleTechResearched*(env: Environment, teamId: int, techType: int32): bool =
  ## Check if a castle tech has been researched for a team.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false
  if techType < 0 or techType > ord(CastleTechType.high).int32:
    return false
  hasCastleTech(env, teamId, CastleTechType(techType))

proc hasUnitUpgradeResearched*(env: Environment, teamId: int, upgradeType: int32): bool =
  ## Check if a unit upgrade has been researched for a team.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false
  if upgradeType < 0 or upgradeType > ord(UnitUpgradeType.high).int32:
    return false
  hasUnitUpgrade(env, teamId, UnitUpgradeType(upgradeType))

# Scout Mode API
# These functions allow external code to enable/disable scout mode for agents.

proc setAgentScoutMode*(agentId: int, active: bool) =
  ## Enable or disable scout mode for an agent.
  ## Requires BuiltinAI controller.
  if not isNil(globalController) and globalController.controllerType == BuiltinAI:
    globalController.aiController.setScoutMode(agentId, active)

proc isAgentScoutModeActive*(agentId: int): bool =
  ## Check if an agent has scout mode active.
  if not isNil(globalController) and globalController.controllerType == BuiltinAI:
    return globalController.aiController.isScoutModeActive(agentId)
  false

proc getAgentScoutExploreRadius*(agentId: int): int32 =
  ## Get the current scout exploration radius for an agent.
  if not isNil(globalController) and globalController.controllerType == BuiltinAI:
    return globalController.aiController.getScoutExploreRadius(agentId)
  0

# Rally Point API
# These functions allow external code to set rally points on buildings.

proc setBuildingRallyPoint*(env: Environment, buildingX, buildingY: int32, rallyX, rallyY: int32) =
  ## Set the rally point for a building.
  let pos = ivec2(buildingX, buildingY)
  if not isValidPos(pos):
    return
  let thing = env.grid[pos.x][pos.y]
  if isNil(thing) or not isBuildingKind(thing.kind):
    return
  setRallyPoint(thing, ivec2(rallyX, rallyY))

proc clearBuildingRallyPoint*(env: Environment, buildingX, buildingY: int32) =
  ## Clear the rally point for a building.
  let pos = ivec2(buildingX, buildingY)
  if not isValidPos(pos):
    return
  let thing = env.grid[pos.x][pos.y]
  if isNil(thing) or not isBuildingKind(thing.kind):
    return
  clearRallyPoint(thing)

proc getBuildingRallyPoint*(env: Environment, buildingX, buildingY: int32): IVec2 =
  ## Get the rally point for a building. Returns (-1, -1) if no rally point is set.
  let pos = ivec2(buildingX, buildingY)
  if not isValidPos(pos):
    return ivec2(-1, -1)
  let thing = env.grid[pos.x][pos.y]
  if isNil(thing) or not isBuildingKind(thing.kind):
    return ivec2(-1, -1)
  if hasRallyPoint(thing):
    return thing.rallyPoint
  ivec2(-1, -1)

# Stop Command API
# Clears all movement orders for an agent.

proc stopAgent*(agentId: int) =
  ## Stop an agent by clearing all active orders (attack-move, patrol, scout).
  clearAgentAttackMoveTarget(agentId)
  clearAgentPatrol(agentId)
  if not isNil(globalController) and globalController.controllerType == BuiltinAI:
    globalController.aiController.clearScoutMode(agentId)

# Formation API
# Formation system for coordinated group movement (Line, Box formations).
# Formations are per-control-group, not per-agent.

import formations
export formations

proc setControlGroupFormation*(groupIndex: int, formationType: int32) =
  ## Set formation type for a control group.
  ## formationType: 0=None, 1=Line, 2=Box, 3=Wedge, 4=Scatter
  if formationType >= 0 and formationType <= ord(FormationType.high):
    setFormation(groupIndex, FormationType(formationType))

proc getControlGroupFormation*(groupIndex: int): int32 =
  ## Get formation type for a control group.
  ## Returns: 0=None, 1=Line, 2=Box, 3=Wedge, 4=Scatter
  ord(getFormation(groupIndex)).int32

proc clearControlGroupFormation*(groupIndex: int) =
  ## Clear formation for a control group, returning units to free movement.
  clearFormation(groupIndex)

proc setControlGroupFormationRotation*(groupIndex: int, rotation: int32) =
  ## Set formation rotation (0-7 for 8 compass directions).
  setFormationRotation(groupIndex, rotation.int)

proc getControlGroupFormationRotation*(groupIndex: int): int32 =
  ## Get formation rotation for a control group.
  getFormationRotation(groupIndex).int32

# Selection API
# Programmatic interface for the selection system (bridges GUI selection and control APIs).

proc selectUnits*(env: Environment, agentIds: seq[int]) =
  ## Replace current selection with the specified agents.
  selection = @[]
  for agentId in agentIds:
    if agentId >= 0 and agentId < env.agents.len:
      let agent = env.agents[agentId]
      if isAgentAlive(env, agent):
        selection.add(agent)

proc addToSelection*(env: Environment, agentId: int) =
  ## Add a single agent to the current selection (if alive and not already selected).
  if agentId >= 0 and agentId < env.agents.len:
    let agent = env.agents[agentId]
    if isAgentAlive(env, agent):
      for s in selection:
        if s.agentId == agentId:
          return
      selection.add(agent)

proc removeFromSelection*(agentId: int) =
  ## Remove a single agent from the current selection.
  for i in countdown(selection.len - 1, 0):
    if selection[i].agentId == agentId:
      selection.delete(i)
      return

proc clearSelection*() =
  ## Clear the current selection.
  selection = @[]

proc getSelectionCount*(): int =
  ## Get the number of currently selected units.
  selection.len

proc getSelectedAgentId*(index: int): int =
  ## Get the agent ID of a selected unit by index. Returns -1 if invalid index.
  if index >= 0 and index < selection.len:
    selection[index].agentId
  else:
    -1

proc createControlGroup*(env: Environment, groupIndex: int, agentIds: seq[int]) =
  ## Assign agents to a control group (0-9).
  if groupIndex < 0 or groupIndex >= ControlGroupCount:
    return
  controlGroups[groupIndex] = @[]
  for agentId in agentIds:
    if agentId >= 0 and agentId < env.agents.len:
      let agent = env.agents[agentId]
      if isAgentAlive(env, agent):
        controlGroups[groupIndex].add(agent)

proc recallControlGroup*(env: Environment, groupIndex: int) =
  ## Recall a control group into the current selection.
  if groupIndex < 0 or groupIndex >= ControlGroupCount:
    return
  # Filter out dead units
  var alive: seq[Thing] = @[]
  for thing in controlGroups[groupIndex]:
    if isAgentAlive(env, thing):
      alive.add(thing)
  controlGroups[groupIndex] = alive
  selection = alive

proc getControlGroupCount*(groupIndex: int): int =
  ## Get the number of units in a control group. Returns 0 if invalid index.
  if groupIndex >= 0 and groupIndex < ControlGroupCount:
    controlGroups[groupIndex].len
  else:
    0

proc getControlGroupAgentId*(groupIndex: int, index: int): int =
  ## Get the agent ID at a position in a control group. Returns -1 if invalid.
  if groupIndex >= 0 and groupIndex < ControlGroupCount and
     index >= 0 and index < controlGroups[groupIndex].len:
    controlGroups[groupIndex][index].agentId
  else:
    -1

proc issueCommandToSelection*(env: Environment, commandType: int32, targetX, targetY: int32) =
  ## Issue a command to all selected units.
  ## commandType: 0=attack-move, 1=patrol (from current pos to target), 2=stop
  let target = ivec2(targetX, targetY)
  for thing in selection:
    if isAgentAlive(env, thing):
      let agentId = thing.agentId
      case commandType
      of 0: # Attack-move
        setAgentAttackMoveTarget(agentId, target)
      of 1: # Patrol from current position to target
        setAgentPatrol(agentId, thing.pos, target)
      of 2: # Stop
        stopAgent(agentId)
      else:
        discard
