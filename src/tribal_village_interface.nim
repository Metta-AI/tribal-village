## Tribal Village C-Compatible Interface
## Simple C interface for the tribal village environment that can be called from Python

import environment, external_actions, common
import std/[json, strutils]

# Global environment instance
var globalEnv: Environment = nil

# C-compatible interface functions
proc tribal_village_create(): bool {.exportc, dynlib.} =
  ## Create a new tribal village environment instance
  try:
    let config = defaultEnvironmentConfig()
    globalEnv = newEnvironment(config)
    return true
  except:
    return false

proc tribal_village_reset(): bool {.exportc, dynlib.} =
  ## Reset the environment
  try:
    if globalEnv == nil:
      return false
    globalEnv.reset()
    return true
  except:
    return false

proc tribal_village_get_observation(agent_id: int, buffer: ptr array[2541, uint8]): bool {.exportc, dynlib.} =
  ## Get observation for a specific agent (21 layers * 11 * 11 = 2541 bytes)
  try:
    if globalEnv == nil or agent_id < 0 or agent_id >= MapAgents:
      return false

    # Copy the 3D observation array to a flat buffer
    var idx = 0
    for layer in 0..<ObservationLayers:
      for x in 0..<ObservationWidth:
        for y in 0..<ObservationHeight:
          buffer[idx] = globalEnv.observations[agent_id][layer][x][y]
          inc idx

    return true
  except:
    return false

proc tribal_village_step(actions: ptr array[15, array[2, uint8]]): bool {.exportc, dynlib.} =
  ## Step the environment with actions for all agents
  try:
    if globalEnv == nil:
      return false

    globalEnv.step(actions)
    return true
  except:
    return false

proc tribal_village_get_reward(agent_id: int): float32 {.exportc, dynlib.} =
  ## Get reward for a specific agent
  try:
    if globalEnv == nil or agent_id < 0 or agent_id >= MapAgents:
      return 0.0
    return globalEnv.agents[agent_id].reward
  except:
    return 0.0

proc tribal_village_is_done(agent_id: int): bool {.exportc, dynlib.} =
  ## Check if a specific agent is done
  try:
    if globalEnv == nil or agent_id < 0 or agent_id >= MapAgents:
      return true
    return globalEnv.terminated[agent_id] > 0.0 or globalEnv.truncated[agent_id] > 0.0
  except:
    return true

proc tribal_village_get_info(): cstring {.exportc, dynlib.} =
  ## Get environment info as JSON string
  try:
    if globalEnv == nil:
      return ""

    let info = %*{
      "current_step": globalEnv.currentStep,
      "max_steps": globalEnv.config.maxSteps,
      "episode_done": globalEnv.shouldReset
    }
    return cstring($info)
  except:
    return ""

proc tribal_village_destroy() {.exportc, dynlib.} =
  ## Destroy the environment instance
  if globalEnv != nil:
    globalEnv = nil

proc tribal_village_get_num_agents(): int32 {.exportc, dynlib.} =
  ## Get the number of agents
  return MapAgents.int32

proc tribal_village_get_max_tokens(): int32 {.exportc, dynlib.} =
  ## Get the maximum tokens per agent
  return (ObservationLayers * ObservationWidth * ObservationHeight).int32