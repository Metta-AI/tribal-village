## Ultra-Fast Direct Buffer Interface
## Zero-copy numpy buffer communication - no conversions

import ./environment, agent_control

type
  ## C-compatible environment config passed from Python.
  ## Use NaN for float fields (or <=0 for maxSteps) to keep Nim defaults.
  CEnvironmentConfig* = object
    maxSteps*: int32
    tumorSpawnRate*: float32
    heartReward*: float32
    oreReward*: float32
    barReward*: float32
    woodReward*: float32
    waterReward*: float32
    wheatReward*: float32
    spearReward*: float32
    armorReward*: float32
    foodReward*: float32
    clothReward*: float32
    tumorKillReward*: float32
    survivalPenalty*: float32
    deathPenalty*: float32

var globalEnv: Environment = nil

const
  ObscuredLayerIndex = ord(ObscuredLayer)
  ObsTileStride = ObservationWidth * ObservationHeight
  ObsAgentStride = ObservationLayers * ObsTileStride

proc applyObscuredMask(env: Environment, obs_buffer: ptr UncheckedArray[uint8]) =
  ## Mask tiles above the observer elevation and mark the ObscuredLayer.
  let radius = ObservationRadius
  for agentId in 0 ..< MapAgents:
    let agent = env.agents[agentId]
    if not isAgentAlive(env, agent):
      continue
    let agentPos = agent.pos
    let baseElevation = env.elevation[agentPos.x][agentPos.y]
    let agentBase = agentId * ObsAgentStride
    for x in 0 ..< ObservationWidth:
      let worldX = agentPos.x + (x - radius)
      let xOffset = x * ObservationHeight
      for y in 0 ..< ObservationHeight:
        let worldY = agentPos.y + (y - radius)
        let inBounds = worldX >= 0 and worldX < MapWidth and worldY >= 0 and worldY < MapHeight
        let obscured = inBounds and env.elevation[worldX][worldY] > baseElevation
        let obscuredIndex = agentBase + ObscuredLayerIndex * ObsTileStride + xOffset + y
        obs_buffer[obscuredIndex] = (if obscured: 1'u8 else: 0'u8)
        if obscured:
          for layer in 0 ..< ObservationLayers:
            if layer == ObscuredLayerIndex:
              continue
            let bufferIdx = agentBase + layer * ObsTileStride + xOffset + y
            obs_buffer[bufferIdx] = 0

proc tribal_village_create(): pointer {.exportc, dynlib.} =
  ## Create environment for direct buffer interface
  try:
    let config = defaultEnvironmentConfig()
    globalEnv = newEnvironment(config)
    initGlobalController(ExternalNN)
    return cast[pointer](globalEnv)
  except:
    return nil

proc tribal_village_set_config(
  env: pointer,
  cfg: ptr CEnvironmentConfig
): int32 {.exportc, dynlib.} =
  ## Update runtime config (rewards, spawn rates, max steps) from Python.
  try:
    discard env
    let incoming = cfg[]
    var config = defaultEnvironmentConfig()
    if incoming.maxSteps > 0:
      config.maxSteps = incoming.maxSteps.int

    template applyFloat(field: untyped, value: float32) =
      if value == value:
        config.field = value.float

    applyFloat(tumorSpawnRate, incoming.tumorSpawnRate)
    applyFloat(heartReward, incoming.heartReward)
    applyFloat(oreReward, incoming.oreReward)
    applyFloat(barReward, incoming.barReward)
    applyFloat(woodReward, incoming.woodReward)
    applyFloat(waterReward, incoming.waterReward)
    applyFloat(wheatReward, incoming.wheatReward)
    applyFloat(spearReward, incoming.spearReward)
    applyFloat(armorReward, incoming.armorReward)
    applyFloat(foodReward, incoming.foodReward)
    applyFloat(clothReward, incoming.clothReward)
    applyFloat(tumorKillReward, incoming.tumorKillReward)
    applyFloat(survivalPenalty, incoming.survivalPenalty)
    applyFloat(deathPenalty, incoming.deathPenalty)
    globalEnv.config = config
    return 1
  except:
    return 0

proc tribal_village_reset_and_get_obs(
  env: pointer,
  obs_buffer: ptr UncheckedArray[uint8],    # [MapAgents, ObservationLayers, 11, 11] direct
  rewards_buffer: ptr UncheckedArray[float32],
  terminals_buffer: ptr UncheckedArray[uint8],
  truncations_buffer: ptr UncheckedArray[uint8]
): int32 {.exportc, dynlib.} =
  ## Reset and write directly to buffers - no conversions
  try:
    globalEnv.reset()
    globalEnv.rebuildObservations()

    # Direct memory copy of observations (zero conversion)
    copyMem(obs_buffer, globalEnv.observations.addr,
      MapAgents * ObservationLayers * ObservationWidth * ObservationHeight)
    applyObscuredMask(globalEnv, obs_buffer)

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
  actions_buffer: ptr UncheckedArray[uint8],    # [MapAgents] direct read
  obs_buffer: ptr UncheckedArray[uint8],        # [MapAgents, ObservationLayers, 11, 11] direct write
  rewards_buffer: ptr UncheckedArray[float32],
  terminals_buffer: ptr UncheckedArray[uint8],
  truncations_buffer: ptr UncheckedArray[uint8]
): int32 {.exportc, dynlib.} =
  ## Ultra-fast step with direct buffer access
  try:
    # Read actions directly from buffer (no conversion)
    var actions: array[MapAgents, uint8]
    copyMem(addr actions[0], actions_buffer, sizeof(actions))

    # Step environment
    globalEnv.step(unsafeAddr actions)

    # Direct memory copy of observations (zero conversion overhead)
    copyMem(obs_buffer, globalEnv.observations.addr,
      MapAgents * ObservationLayers * ObservationWidth * ObservationHeight)
    applyObscuredMask(globalEnv, obs_buffer)

    # Direct buffer writes (no dict conversion)
    for i in 0..<MapAgents:
      let agent = globalEnv.agents[i]
      let reward = agent.reward
      rewards_buffer[i] = reward
      agent.reward = 0.0'f32
      terminals_buffer[i] = if globalEnv.terminated[i] > 0.0: 1 else: 0
      truncations_buffer[i] = if globalEnv.truncated[i] > 0.0: 1 else: 0

    return 1
  except:
    return 0

proc tribal_village_get_num_agents(): int32 {.exportc, dynlib.} =
  MapAgents.int32

proc tribal_village_get_obs_layers(): int32 {.exportc, dynlib.} =
  ObservationLayers.int32

proc tribal_village_get_obs_width(): int32 {.exportc, dynlib.} =
  ObservationWidth.int32


proc tribal_village_get_map_width(): int32 {.exportc, dynlib.} =
  MapWidth.int32

proc tribal_village_get_map_height(): int32 {.exportc, dynlib.} =
  MapHeight.int32

# Render full map as HxWx3 RGB (uint8)
proc toByte(value: float32): uint8 =
  let iv = max(0, min(255, int(value * 255.0)))
  uint8(iv)

proc tribal_village_render_rgb(
  env: pointer,
  out_buffer: ptr UncheckedArray[uint8],
  out_w: int32,
  out_h: int32
): int32 {.exportc, dynlib.} =
  proc thingTintBytes(thing: Thing): tuple[r, g, b: uint8] =
    if isBuildingKind(thing.kind):
      let tint = BuildingRegistry[thing.kind].renderColor
      return (tint.r, tint.g, tint.b)
    case thing.kind
    of Agent: (255'u8, 255'u8, 0'u8)
    of Wall: (96'u8, 96'u8, 96'u8)
    of Tree: (34'u8, 139'u8, 34'u8)
    of Wheat: (200'u8, 180'u8, 90'u8)
    of Stubble: (175'u8, 150'u8, 70'u8)
    of Stone: (140'u8, 140'u8, 140'u8)
    of Gold: (220'u8, 190'u8, 80'u8)
    of Bush: (60'u8, 120'u8, 60'u8)
    of Cactus: (80'u8, 140'u8, 60'u8)
    of Stalagmite: (150'u8, 150'u8, 170'u8)
    of Magma: (0'u8, 200'u8, 200'u8)
    of Spawner: (255'u8, 170'u8, 0'u8)
    of Tumor: (160'u8, 32'u8, 240'u8)
    of Cow: (230'u8, 230'u8, 230'u8)
    of Bear: (140'u8, 90'u8, 40'u8)
    of Wolf: (130'u8, 130'u8, 130'u8)
    of Skeleton: (210'u8, 210'u8, 210'u8)
    of Stump: (110'u8, 85'u8, 55'u8)
    of Lantern: (255'u8, 240'u8, 128'u8)
    else: (180'u8, 180'u8, 180'u8)

  let width = int(out_w)
  let height = int(out_h)

  let scaleX = width div MapWidth
  let scaleY = height div MapHeight
  try:
    for y in 0 ..< MapHeight:
      for sy in 0 ..< scaleY:
        for x in 0 ..< MapWidth:
          let thing = globalEnv.grid[x][y]
          let (rByte, gByte, bByte) =
            if not isNil(thing):
              thingTintBytes(thing)
            elif globalEnv.actionTintCountdown[x][y] > 0:
              let tint = globalEnv.actionTintColor[x][y]
              (toByte(tint.r), toByte(tint.g), toByte(tint.b))
            else:
              let color = combinedTileTint(globalEnv, x, y)
              (toByte(color.r), toByte(color.g), toByte(color.b))

          let xBase = (y * scaleY + sy) * (width * 3) + x * scaleX * 3
          for sx in 0 ..< scaleX:
            let bufferIdx = xBase + sx * 3
            out_buffer[bufferIdx] = rByte
            out_buffer[bufferIdx + 1] = gByte
            out_buffer[bufferIdx + 2] = bByte
    return 1
  except:
    return 0
proc tribal_village_get_obs_height(): int32 {.exportc, dynlib.} =
  ObservationHeight.int32

proc tribal_village_destroy(env: pointer) {.exportc, dynlib.} =
  ## Clean up environment
  globalEnv = nil

# --- Rendering interface (ANSI) ---
proc tribal_village_render_ansi(
  env: pointer,
  out_buffer: ptr UncheckedArray[char],
  buf_len: int32
): int32 {.exportc, dynlib.} =
  ## Write an ANSI string render into out_buffer (null-terminated).
  ## Returns number of bytes written (excluding terminator). 0 on error.
  try:
    let rendered = render(globalEnv)  # environment.render*(env: Environment): string
    let n = min(rendered.len, max(0, buf_len - 1).int)
    copyMem(out_buffer, cast[pointer](rendered.cstring), n)
    out_buffer[n] = '\0'  # null-terminate
    return n.int32
  except:
    return 0

# ============== FFI Error Query Functions ==============

proc tribal_village_has_error*(): int32 {.exportc, dynlib.} =
  ## Check if an error occurred during the last operation
  ## Returns 1 if error, 0 otherwise
  if lastFFIError.hasError: 1 else: 0

proc tribal_village_get_error_code*(): int32 {.exportc, dynlib.} =
  ## Get the error code from the last operation
  ## Returns the TribalErrorKind as an integer
  ord(lastFFIError.errorCode).int32

proc tribal_village_get_error_message*(buffer: ptr char, bufferSize: int32): int32 {.exportc, dynlib.} =
  ## Copy the error message to the provided buffer
  ## Returns the actual length written, or -1 if buffer too small
  let msg = lastFFIError.errorMessage
  if msg.len >= bufferSize:
    return -1
  if msg.len > 0:
    copyMem(buffer, unsafeAddr msg[0], msg.len)
  cast[ptr char](cast[uint](buffer) + msg.len.uint)[] = '\0'
  msg.len.int32

proc tribal_village_clear_error*() {.exportc, dynlib.} =
  ## Clear the error state
  clearFFIError()
