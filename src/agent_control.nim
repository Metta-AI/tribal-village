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

# Squad API
# These functions allow external code to create and manage squads for coordinated multi-unit tactics.
# Squads enable formation movement, synchronized attacks, and coordinated retreats.

proc createSquadForTeam*(teamId: int, formation: FormationType = FormationWedge): int =
  ## Create a new squad for a team. Returns squad ID or -1 if max squads reached.
  let squad = createSquad(teamId, formation)
  if squad.isNil:
    return -1
  squad.id.int

proc addAgentToSquad*(teamId, squadId, agentId: int, env: Environment): bool =
  ## Add an agent to a squad. Returns true if successful.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false
  if squadId < 0 or squadId >= MaxSquadsPerTeam:
    return false
  if agentId < 0 or agentId >= MapAgents:
    return false
  let squad = addr teamSquads[teamId].squads[squadId]
  if not squad.active:
    return false
  let agent = env.agents[agentId]
  addToSquad(squad, agentId, agent.unitClass)

proc removeAgentFromSquad*(teamId, agentId: int) =
  ## Remove an agent from their current squad.
  let squad = getSquadForAgent(teamId, agentId)
  if not squad.isNil:
    removeFromSquad(squad, agentId)

proc setSquadFormation*(teamId, squadId: int, formation: FormationType) =
  ## Set the formation type for a squad.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  if squadId < 0 or squadId >= MaxSquadsPerTeam:
    return
  let squad = addr teamSquads[teamId].squads[squadId]
  if squad.active:
    squad.formation = formation
    updateFormationOffsets(squad)

proc setSquadMoveTarget*(teamId, squadId: int, x, y: int32) =
  ## Order a squad to move to a target position in formation.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  if squadId < 0 or squadId >= MaxSquadsPerTeam:
    return
  let squad = addr teamSquads[teamId].squads[squadId]
  if squad.active:
    setSquadTarget(squad, ivec2(x, y), SquadMoving)

proc setSquadAttackTarget*(teamId, squadId: int, x, y: int32) =
  ## Order a squad to attack a target position (synchronized attack).
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  if squadId < 0 or squadId >= MaxSquadsPerTeam:
    return
  let squad = addr teamSquads[teamId].squads[squadId]
  if squad.active:
    squadAttackTarget(squad, ivec2(x, y))

proc setSquadRallyPoint*(teamId, squadId: int, x, y: int32) =
  ## Set the rally point for a squad (used for retreats).
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  if squadId < 0 or squadId >= MaxSquadsPerTeam:
    return
  let squad = addr teamSquads[teamId].squads[squadId]
  if squad.active:
    squad.rallyPoint = ivec2(x, y)

proc orderSquadRetreat*(teamId, squadId: int) =
  ## Order a squad to retreat to their rally point.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  if squadId < 0 or squadId >= MaxSquadsPerTeam:
    return
  let squad = addr teamSquads[teamId].squads[squadId]
  if squad.active:
    squadRetreat(squad)

proc disbandSquadById*(teamId, squadId: int) =
  ## Disband a squad, freeing all members.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  if squadId < 0 or squadId >= MaxSquadsPerTeam:
    return
  let squad = addr teamSquads[teamId].squads[squadId]
  disbandSquad(squad)

proc getSquadMemberCount*(teamId, squadId: int): int =
  ## Get the number of members in a squad.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return 0
  if squadId < 0 or squadId >= MaxSquadsPerTeam:
    return 0
  let squad = teamSquads[teamId].squads[squadId]
  if not squad.active:
    return 0
  squad.memberCount.int

proc isAgentInSquad*(teamId, agentId: int): bool =
  ## Check if an agent is in any squad.
  not getSquadForAgent(teamId, agentId).isNil

proc getAgentSquadId*(teamId, agentId: int): int =
  ## Get the squad ID for an agent, or -1 if not in a squad.
  let squad = getSquadForAgent(teamId, agentId)
  if squad.isNil:
    return -1
  squad.id.int
