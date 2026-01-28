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
