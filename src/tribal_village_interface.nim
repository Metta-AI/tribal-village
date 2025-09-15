## Tribal Village C-Compatible Interface
## Direct pointer-based interface for zero-copy communication with Python

import environment, external_actions, common
import std/[json]

# Global environment instance
var globalEnv: Environment = nil

# C-compatible interface functions using direct pointers
proc tribal_village_create(): pointer {.exportc, dynlib.} =
  ## Create a new tribal village environment instance
  try:
    let config = defaultEnvironmentConfig()
    globalEnv = newEnvironment(config)
    return cast[pointer](globalEnv)
  except:
    return nil

proc tribal_village_destroy(env: pointer) {.exportc, dynlib.} =
  ## Destroy the environment instance
  globalEnv = nil

proc tribal_village_reset_and_get_obs(env: pointer, obs_ptr: int): int32 {.exportc, dynlib.} =
  ## Reset environment and write observations directly to provided buffer
  ## Returns 1 on success, 0 on failure
  if globalEnv == nil or obs_ptr == 0:
    return 0

  try:
    globalEnv.reset()

    # Write observations directly to the provided buffer
    # Buffer format: [num_agents, max_tokens, 3] uint8 array
    let obs_buffer = cast[ptr UncheckedArray[uint8]](obs_ptr)
    var buffer_idx = 0

    for agent_id in 0..<MapAgents:
      # Convert 3D observation to token format for this agent
      var token_count = 0
      let max_tokens_per_agent = 256  # Sparse observations - much smaller than full grid

      for layer in 0..<ObservationLayers:
        for x in 0..<ObservationWidth:
          for y in 0..<ObservationHeight:
            if token_count >= max_tokens_per_agent:
              break

            let obs_value = globalEnv.observations[agent_id][layer][x][y]
            if obs_value > 0:  # Only include non-zero values as tokens
              # coord_byte: pack x,y in 4 bits each like metta (max 16x16)
              let coord_byte = ((x and 0x0F) shl 4) or (y and 0x0F)

              # Write token as [coord_byte, layer, value]
              obs_buffer[buffer_idx] = coord_byte.uint8
              obs_buffer[buffer_idx + 1] = layer.uint8
              obs_buffer[buffer_idx + 2] = obs_value
              buffer_idx += 3
              inc token_count

      # Fill remaining tokens with padding for this agent
      for i in token_count..<max_tokens_per_agent:
        obs_buffer[buffer_idx] = 255  # padding marker
        obs_buffer[buffer_idx + 1] = 0
        obs_buffer[buffer_idx + 2] = 0
        buffer_idx += 3

    return 1
  except:
    return 0

proc tribal_village_step_with_pointers(env: pointer, actions_ptr: int, obs_ptr: int, rewards_ptr: int, terminals_ptr: int, truncations_ptr: int): int32 {.exportc, dynlib.} =
  ## Step environment using direct pointer access for all data
  ## Returns 1 on success, 0 on failure
  if globalEnv == nil or actions_ptr == 0:
    return 0

  try:
    # Read actions from provided buffer
    let actions_buffer = cast[ptr UncheckedArray[uint8]](actions_ptr)

    # Convert to the format expected by step()
    # Actions buffer format: [num_agents, 2] uint8 array
    var actions: array[MapAgents, array[2, uint8]]
    for agent_id in 0..<MapAgents:
      let base_idx = agent_id * 2
      actions[agent_id][0] = actions_buffer[base_idx]      # action type
      actions[agent_id][1] = actions_buffer[base_idx + 1]  # action argument

    # Step the environment
    globalEnv.step(unsafeAddr actions)

    # Write observations directly to obs buffer (same format as reset)
    if obs_ptr != 0:
      let obs_buffer = cast[ptr UncheckedArray[uint8]](obs_ptr)
      var buffer_idx = 0

      for agent_id in 0..<MapAgents:
        var token_count = 0
        let max_tokens_per_agent = 256

        for layer in 0..<ObservationLayers:
          for x in 0..<ObservationWidth:
            for y in 0..<ObservationHeight:
              if token_count >= max_tokens_per_agent:
                break

              let obs_value = globalEnv.observations[agent_id][layer][x][y]
              if obs_value > 0:
                # coord_byte: pack x,y in 4 bits each like metta (max 16x16)
                let coord_byte = ((x and 0x0F) shl 4) or (y and 0x0F)
                obs_buffer[buffer_idx] = coord_byte.uint8
                obs_buffer[buffer_idx + 1] = layer.uint8
                obs_buffer[buffer_idx + 2] = obs_value
                buffer_idx += 3
                inc token_count

        # Fill remaining with padding
        for i in token_count..<max_tokens_per_agent:
          obs_buffer[buffer_idx] = 255
          obs_buffer[buffer_idx + 1] = 0
          obs_buffer[buffer_idx + 2] = 0
          buffer_idx += 3

    # Write rewards directly to rewards buffer
    if rewards_ptr != 0:
      let rewards_buffer = cast[ptr UncheckedArray[float32]](rewards_ptr)
      for agent_id in 0..<MapAgents:
        rewards_buffer[agent_id] = globalEnv.agents[agent_id].reward

    # Write terminals directly to terminals buffer
    if terminals_ptr != 0:
      let terminals_buffer = cast[ptr UncheckedArray[uint8]](terminals_ptr)
      for agent_id in 0..<MapAgents:
        terminals_buffer[agent_id] = if globalEnv.terminated[agent_id] > 0.0: 1 else: 0

    # Write truncations directly to truncations buffer
    if truncations_ptr != 0:
      let truncations_buffer = cast[ptr UncheckedArray[uint8]](truncations_ptr)
      for agent_id in 0..<MapAgents:
        truncations_buffer[agent_id] = if globalEnv.truncated[agent_id] > 0.0: 1 else: 0

    return 1
  except:
    return 0

proc tribal_village_get_num_agents(): int32 {.exportc, dynlib.} =
  ## Get the number of agents
  return MapAgents.int32

proc tribal_village_get_max_tokens(): int32 {.exportc, dynlib.} =
  ## Get the maximum tokens per agent (conservative estimate for sparse observations)
  ## Most observations are sparse, so we don't need full grid size
  return 256.int32  # Much smaller than 2541, but enough for typical sparse observations

proc tribal_village_is_done(env: pointer): int32 {.exportc, dynlib.} =
  ## Check if environment episode is done
  if globalEnv == nil:
    return 1
  return if globalEnv.shouldReset: 1 else: 0