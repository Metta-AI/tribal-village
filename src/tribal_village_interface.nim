## Ultra-Fast Direct Buffer Interface
## Zero-copy numpy buffer communication - no conversions

import environment, external_actions

var globalEnv: Environment = nil

proc tribal_village_create(): pointer {.exportc, dynlib.} =
  ## Create environment for direct buffer interface
  try:
    let config = defaultEnvironmentConfig()
    globalEnv = newEnvironment(config)
    initGlobalController(ExternalNN)
    return cast[pointer](globalEnv)
  except:
    return nil

proc tribal_village_reset_and_get_obs(
  env: pointer,
  obs_buffer: ptr UncheckedArray[uint8],    # [60, 21, 11, 11] direct
  rewards_buffer: ptr UncheckedArray[float32],
  terminals_buffer: ptr UncheckedArray[uint8],
  truncations_buffer: ptr UncheckedArray[uint8]
): int32 {.exportc, dynlib.} =
  ## Reset and write directly to buffers - no conversions
  if globalEnv == nil:
    return 0

  try:
    globalEnv.reset()

    # Direct memory copy of observations (zero conversion)
    let obs_size = MapAgents * ObservationLayers * ObservationWidth * ObservationHeight
    copyMem(obs_buffer, globalEnv.observations.addr, obs_size)

    # Clear rewards/terminals/truncations
    for i in 0..<MapAgents:
      rewards_buffer[i] = 0.0
      terminals_buffer[i] = 0
      truncations_buffer[i] = 0

    return 1
  except:
    return 0

proc tribal_village_step_with_pointers(
  env: pointer,
  actions_buffer: ptr UncheckedArray[uint8],    # [60, 2] direct read
  obs_buffer: ptr UncheckedArray[uint8],        # [60, 21, 11, 11] direct write
  rewards_buffer: ptr UncheckedArray[float32],
  terminals_buffer: ptr UncheckedArray[uint8],
  truncations_buffer: ptr UncheckedArray[uint8]
): int32 {.exportc, dynlib.} =
  ## Ultra-fast step with direct buffer access
  if globalEnv == nil:
    return 0

  try:
    # Read actions directly from buffer (no conversion)
    var actions: array[MapAgents, array[2, uint8]]
    for i in 0..<MapAgents:
      actions[i][0] = actions_buffer[i * 2]
      actions[i][1] = actions_buffer[i * 2 + 1]

    # Step environment
    globalEnv.step(unsafeAddr actions)

    # Direct memory copy of observations (zero conversion overhead)
    let obs_size = MapAgents * ObservationLayers * ObservationWidth * ObservationHeight
    copyMem(obs_buffer, globalEnv.observations.addr, obs_size)

    # Direct buffer writes (no dict conversion)
    for i in 0..<MapAgents:
      rewards_buffer[i] = globalEnv.agents[i].reward
      terminals_buffer[i] = if globalEnv.terminated[i] > 0.0: 1 else: 0
      truncations_buffer[i] = if globalEnv.truncated[i] > 0.0: 1 else: 0

    return 1
  except:
    return 0

proc tribal_village_get_num_agents(): int32 {.exportc, dynlib.} =
  return MapAgents.int32

proc tribal_village_get_obs_layers(): int32 {.exportc, dynlib.} =
  return ObservationLayers.int32

proc tribal_village_get_obs_width(): int32 {.exportc, dynlib.} =
  return ObservationWidth.int32

proc tribal_village_get_obs_height(): int32 {.exportc, dynlib.} =
  return ObservationHeight.int32

proc tribal_village_destroy(env: pointer) {.exportc, dynlib.} =
  ## Clean up environment
  globalEnv = nil