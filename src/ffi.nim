## Ultra-Fast Direct Buffer Interface
## Zero-copy numpy buffer communication - no conversions

import ./environment, agent_control

type
  ## C-compatible environment config passed from Python.
  ## Use NaN for float fields (or <=0 for maxSteps) to keep Nim defaults.
  CEnvironmentConfig* = object
    maxSteps*: int32
    victoryCondition*: int32  ## Maps to VictoryCondition enum (0=None, 1=Conquest, 2=Wonder, 3=Relic, 4=KingOfTheHill, 5=All)
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

proc tribal_village_create(): pointer {.exportc, dynlib.} =
  ## Create environment for direct buffer interface
  try:
    let config = defaultEnvironmentConfig()
    globalEnv = newEnvironment(config)
    initGlobalController(ExternalNN)
    return cast[pointer](globalEnv)
  except CatchableError:
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
    if incoming.victoryCondition >= 0 and incoming.victoryCondition <= ord(VictoryAll):
      config.victoryCondition = VictoryCondition(incoming.victoryCondition)

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
  except CatchableError:
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
    # Obscuring is now integrated into rebuildObservations for efficiency
    copyMem(obs_buffer, globalEnv.observations.addr,
      MapAgents * ObservationLayers * ObservationWidth * ObservationHeight)

    # Clear rewards/terminals/truncations
    for i in 0..<MapAgents:
      rewards_buffer[i] = 0.0
      terminals_buffer[i] = 0
      truncations_buffer[i] = 0

    return 1
  except CatchableError:
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
    # Obscuring is now integrated into rebuildObservations for efficiency
    copyMem(obs_buffer, globalEnv.observations.addr,
      MapAgents * ObservationLayers * ObservationWidth * ObservationHeight)

    # Direct buffer writes from contiguous rewards array (SIMD-friendly)
    copyMem(rewards_buffer, globalEnv.rewards.addr, MapAgents * sizeof(float32))
    zeroMem(globalEnv.rewards.addr, MapAgents * sizeof(float32))
    for i in 0..<MapAgents:
      terminals_buffer[i] = if globalEnv.terminated[i] > 0.0: 1 else: 0
      truncations_buffer[i] = if globalEnv.truncated[i] > 0.0: 1 else: 0

    return 1
  except CatchableError:
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
  except CatchableError:
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
  except CatchableError:
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

# ============== Agent Control FFI Functions ==============

# --- Attack-Move ---

proc tribal_village_set_attack_move*(agentId: int32, x: int32, y: int32) {.exportc, dynlib.} =
  ## Set an attack-move target for an agent.
  setAgentAttackMoveTargetXY(agentId, x, y)

proc tribal_village_clear_attack_move*(agentId: int32) {.exportc, dynlib.} =
  ## Clear the attack-move target for an agent.
  clearAgentAttackMoveTarget(agentId)

proc tribal_village_get_attack_move_x*(agentId: int32): int32 {.exportc, dynlib.} =
  ## Get the x coordinate of an agent's attack-move target. -1 if inactive.
  getAgentAttackMoveTarget(agentId).x

proc tribal_village_get_attack_move_y*(agentId: int32): int32 {.exportc, dynlib.} =
  ## Get the y coordinate of an agent's attack-move target. -1 if inactive.
  getAgentAttackMoveTarget(agentId).y

proc tribal_village_is_attack_move_active*(agentId: int32): int32 {.exportc, dynlib.} =
  ## Check if an agent has an active attack-move target. Returns 1 if active, 0 otherwise.
  if isAgentAttackMoveActive(agentId): 1 else: 0

# --- Patrol ---

proc tribal_village_set_patrol*(agentId: int32, x1: int32, y1: int32, x2: int32, y2: int32) {.exportc, dynlib.} =
  ## Set patrol waypoints for an agent.
  setAgentPatrolXY(agentId, x1, y1, x2, y2)

proc tribal_village_clear_patrol*(agentId: int32) {.exportc, dynlib.} =
  ## Clear patrol mode for an agent.
  clearAgentPatrol(agentId)

proc tribal_village_get_patrol_target_x*(agentId: int32): int32 {.exportc, dynlib.} =
  ## Get the x coordinate of an agent's current patrol target. -1 if inactive.
  getAgentPatrolTarget(agentId).x

proc tribal_village_get_patrol_target_y*(agentId: int32): int32 {.exportc, dynlib.} =
  ## Get the y coordinate of an agent's current patrol target. -1 if inactive.
  getAgentPatrolTarget(agentId).y

proc tribal_village_is_patrol_active*(agentId: int32): int32 {.exportc, dynlib.} =
  ## Check if an agent has patrol mode active. Returns 1 if active, 0 otherwise.
  if isAgentPatrolActive(agentId): 1 else: 0

# --- Stance ---

proc tribal_village_set_stance*(env: pointer, agentId: int32, stance: int32) {.exportc, dynlib.} =
  ## Set the combat stance for an agent.
  ## stance: 0=Aggressive, 1=Defensive, 2=StandGround, 3=NoAttack
  if stance >= 0 and stance <= ord(AgentStance.high):
    setAgentStance(globalEnv, agentId, AgentStance(stance))

proc tribal_village_get_stance*(env: pointer, agentId: int32): int32 {.exportc, dynlib.} =
  ## Get the combat stance for an agent.
  ## Returns: 0=Aggressive, 1=Defensive, 2=StandGround, 3=NoAttack
  ord(getAgentStance(globalEnv, agentId)).int32

# --- Garrison ---

proc tribal_village_garrison*(env: pointer, agentId: int32, buildingX: int32, buildingY: int32): int32 {.exportc, dynlib.} =
  ## Garrison an agent into a building. Returns 1 on success, 0 on failure.
  if garrisonAgentInBuilding(globalEnv, agentId, buildingX, buildingY): 1 else: 0

proc tribal_village_ungarrison*(env: pointer, buildingX: int32, buildingY: int32): int32 {.exportc, dynlib.} =
  ## Ungarrison all units from a building. Returns the number of units ungarrisoned.
  ungarrisonAllFromBuilding(globalEnv, buildingX, buildingY)

proc tribal_village_garrison_count*(env: pointer, buildingX: int32, buildingY: int32): int32 {.exportc, dynlib.} =
  ## Get the number of units garrisoned in a building.
  getGarrisonCount(globalEnv, buildingX, buildingY)

# --- Production Queue ---

proc tribal_village_queue_train*(env: pointer, buildingX: int32, buildingY: int32, teamId: int32): int32 {.exportc, dynlib.} =
  ## Queue a unit for training at a building. Returns 1 on success, 0 on failure.
  if queueUnitTraining(globalEnv, buildingX, buildingY, teamId): 1 else: 0

proc tribal_village_cancel_train*(env: pointer, buildingX: int32, buildingY: int32): int32 {.exportc, dynlib.} =
  ## Cancel the last queued unit at a building. Returns 1 on success, 0 on failure.
  if cancelLastQueuedUnit(globalEnv, buildingX, buildingY): 1 else: 0

proc tribal_village_queue_size*(env: pointer, buildingX: int32, buildingY: int32): int32 {.exportc, dynlib.} =
  ## Get the number of units in the production queue at a building.
  getProductionQueueSize(globalEnv, buildingX, buildingY)

proc tribal_village_queue_progress*(env: pointer, buildingX: int32, buildingY: int32, index: int32): int32 {.exportc, dynlib.} =
  ## Get remaining steps for a production queue entry. Returns -1 if invalid.
  getProductionQueueEntryProgress(globalEnv, buildingX, buildingY, index)

# --- Research ---

proc tribal_village_research_blacksmith*(env: pointer, agentId: int32, buildingX: int32, buildingY: int32): int32 {.exportc, dynlib.} =
  ## Research the next blacksmith upgrade. Returns 1 on success, 0 on failure.
  if researchBlacksmithUpgrade(globalEnv, agentId, buildingX, buildingY): 1 else: 0

proc tribal_village_research_university*(env: pointer, agentId: int32, buildingX: int32, buildingY: int32): int32 {.exportc, dynlib.} =
  ## Research the next university tech. Returns 1 on success, 0 on failure.
  if researchUniversityTech(globalEnv, agentId, buildingX, buildingY): 1 else: 0

proc tribal_village_research_castle*(env: pointer, agentId: int32, buildingX: int32, buildingY: int32): int32 {.exportc, dynlib.} =
  ## Research the next castle unique tech. Returns 1 on success, 0 on failure.
  if researchCastleTech(globalEnv, agentId, buildingX, buildingY): 1 else: 0

proc tribal_village_research_unit_upgrade*(env: pointer, agentId: int32, buildingX: int32, buildingY: int32): int32 {.exportc, dynlib.} =
  ## Research the next unit upgrade. Returns 1 on success, 0 on failure.
  if researchUnitUpgrade(globalEnv, agentId, buildingX, buildingY): 1 else: 0

proc tribal_village_has_blacksmith_upgrade*(env: pointer, teamId: int32, upgradeType: int32): int32 {.exportc, dynlib.} =
  ## Get the current level of a blacksmith upgrade for a team.
  ## upgradeType: 0=MeleeAttack, 1=ArcherAttack, 2=InfantryArmor, 3=CavalryArmor, 4=ArcherArmor
  hasBlacksmithUpgrade(globalEnv, teamId, upgradeType)

proc tribal_village_has_university_tech*(env: pointer, teamId: int32, techType: int32): int32 {.exportc, dynlib.} =
  ## Check if a university tech has been researched. Returns 1 if researched, 0 otherwise.
  if hasUniversityTechResearched(globalEnv, teamId, techType): 1 else: 0

proc tribal_village_has_castle_tech*(env: pointer, teamId: int32, techType: int32): int32 {.exportc, dynlib.} =
  ## Check if a castle tech has been researched. Returns 1 if researched, 0 otherwise.
  if hasCastleTechResearched(globalEnv, teamId, techType): 1 else: 0

proc tribal_village_has_unit_upgrade*(env: pointer, teamId: int32, upgradeType: int32): int32 {.exportc, dynlib.} =
  ## Check if a unit upgrade has been researched. Returns 1 if researched, 0 otherwise.
  if hasUnitUpgradeResearched(globalEnv, teamId, upgradeType): 1 else: 0

# --- Scout Mode ---

proc tribal_village_set_scout_mode*(agentId: int32, active: int32) {.exportc, dynlib.} =
  ## Enable or disable scout mode for an agent. active: 1=enable, 0=disable.
  setAgentScoutMode(agentId, active != 0)

proc tribal_village_is_scout_mode_active*(agentId: int32): int32 {.exportc, dynlib.} =
  ## Check if scout mode is active for an agent. Returns 1 if active, 0 otherwise.
  if isAgentScoutModeActive(agentId): 1 else: 0

proc tribal_village_get_scout_explore_radius*(agentId: int32): int32 {.exportc, dynlib.} =
  ## Get the current scout exploration radius for an agent.
  getAgentScoutExploreRadius(agentId)

# --- Fog of War ---

proc tribal_village_is_tile_revealed*(env: pointer, teamId: int32, x: int32, y: int32): int32 {.exportc, dynlib.} =
  ## Check if a tile has been revealed by the specified team.
  ## Returns 1 if revealed, 0 otherwise.
  if isRevealed(globalEnv, teamId, ivec2(x, y)): 1 else: 0

proc tribal_village_get_revealed_tile_count*(env: pointer, teamId: int32): int32 {.exportc, dynlib.} =
  ## Count how many tiles have been revealed by a team (exploration progress).
  getRevealedTileCount(globalEnv, teamId).int32

proc tribal_village_clear_revealed_map*(env: pointer, teamId: int32) {.exportc, dynlib.} =
  ## Clear the revealed map for a team.
  clearRevealedMap(globalEnv, teamId)

# --- Rally Point ---

proc tribal_village_set_rally_point*(env: pointer, buildingX: int32, buildingY: int32, rallyX: int32, rallyY: int32) {.exportc, dynlib.} =
  ## Set a rally point for a building.
  setBuildingRallyPoint(globalEnv, buildingX, buildingY, rallyX, rallyY)

proc tribal_village_clear_rally_point*(env: pointer, buildingX: int32, buildingY: int32) {.exportc, dynlib.} =
  ## Clear the rally point for a building.
  clearBuildingRallyPoint(globalEnv, buildingX, buildingY)

proc tribal_village_get_rally_point_x*(env: pointer, buildingX: int32, buildingY: int32): int32 {.exportc, dynlib.} =
  ## Get the x coordinate of a building's rally point. -1 if not set.
  getBuildingRallyPoint(globalEnv, buildingX, buildingY).x

proc tribal_village_get_rally_point_y*(env: pointer, buildingX: int32, buildingY: int32): int32 {.exportc, dynlib.} =
  ## Get the y coordinate of a building's rally point. -1 if not set.
  getBuildingRallyPoint(globalEnv, buildingX, buildingY).y

# --- Stop Command ---

proc tribal_village_stop*(agentId: int32) {.exportc, dynlib.} =
  ## Stop an agent, clearing all active orders (attack-move, patrol, scout, hold, follow).
  stopAgent(agentId)

# --- Hold Position ---

proc tribal_village_hold_position*(agentId: int32, x: int32, y: int32) {.exportc, dynlib.} =
  ## Set hold position for an agent at the given coordinates.
  ## The agent stays at the position, attacks enemies in range, but won't chase.
  setAgentHoldPositionXY(agentId, x, y)

proc tribal_village_clear_hold_position*(agentId: int32) {.exportc, dynlib.} =
  ## Clear hold position for an agent.
  clearAgentHoldPosition(agentId)

proc tribal_village_get_hold_position_x*(agentId: int32): int32 {.exportc, dynlib.} =
  ## Get x coordinate of hold position. -1 if not active.
  getAgentHoldPosition(agentId).x

proc tribal_village_get_hold_position_y*(agentId: int32): int32 {.exportc, dynlib.} =
  ## Get y coordinate of hold position. -1 if not active.
  getAgentHoldPosition(agentId).y

proc tribal_village_is_hold_position_active*(agentId: int32): int32 {.exportc, dynlib.} =
  ## Check if hold position is active. Returns 1 if active, 0 if not.
  if isAgentHoldPositionActive(agentId): 1 else: 0

# --- Follow ---

proc tribal_village_follow_agent*(agentId: int32, targetAgentId: int32) {.exportc, dynlib.} =
  ## Set an agent to follow another agent.
  setAgentFollowTarget(agentId, targetAgentId)

proc tribal_village_clear_follow*(agentId: int32) {.exportc, dynlib.} =
  ## Clear follow target for an agent.
  clearAgentFollowTarget(agentId)

proc tribal_village_get_follow_target*(agentId: int32): int32 {.exportc, dynlib.} =
  ## Get the follow target agent ID. -1 if not active.
  getAgentFollowTargetId(agentId).int32

proc tribal_village_is_follow_active*(agentId: int32): int32 {.exportc, dynlib.} =
  ## Check if follow mode is active. Returns 1 if active, 0 if not.
  if isAgentFollowActive(agentId): 1 else: 0

# --- Formation (per control group) ---

proc tribal_village_set_formation*(env: pointer, controlGroupId: int32, formationType: int32) {.exportc, dynlib.} =
  ## Set formation type for a control group.
  ## formationType: 0=None, 1=Line, 2=Box, 3=Wedge(reserved), 4=Scatter
  setControlGroupFormation(controlGroupId, formationType)

proc tribal_village_get_formation*(env: pointer, controlGroupId: int32): int32 {.exportc, dynlib.} =
  ## Get formation type for a control group.
  ## Returns: 0=None, 1=Line, 2=Box, 3=Wedge, 4=Scatter
  getControlGroupFormation(controlGroupId)

proc tribal_village_clear_formation*(env: pointer, controlGroupId: int32) {.exportc, dynlib.} =
  ## Clear formation for a control group.
  clearControlGroupFormation(controlGroupId)

proc tribal_village_set_formation_rotation*(env: pointer, controlGroupId: int32, rotation: int32) {.exportc, dynlib.} =
  ## Set formation rotation for a control group (0-7 for 8 compass directions).
  setControlGroupFormationRotation(controlGroupId, rotation)

proc tribal_village_get_formation_rotation*(env: pointer, controlGroupId: int32): int32 {.exportc, dynlib.} =
  ## Get formation rotation for a control group.
  getControlGroupFormationRotation(controlGroupId)

# --- Market Trading ---

proc tribal_village_init_market_prices*(env: pointer) {.exportc, dynlib.} =
  ## Initialize market prices to base rates for all teams.
  initMarketPrices(globalEnv)

proc tribal_village_get_market_price*(env: pointer, teamId: int32, resource: int32): int32 {.exportc, dynlib.} =
  ## Get current market price for a resource (gold cost per 100 units).
  ## resource: 0=Food, 1=Wood, 2=Gold, 3=Stone, 4=Water, 5=None
  if resource < 0 or resource > ord(StockpileResource.high):
    return 0
  getMarketPrice(globalEnv, teamId, StockpileResource(resource)).int32

proc tribal_village_set_market_price*(env: pointer, teamId: int32, resource: int32, price: int32) {.exportc, dynlib.} =
  ## Set market price for a resource (clamped to min/max bounds).
  ## resource: 0=Food, 1=Wood, 2=Gold, 3=Stone, 4=Water, 5=None
  if resource < 0 or resource > ord(StockpileResource.high):
    return
  setMarketPrice(globalEnv, teamId, StockpileResource(resource), price)

proc tribal_village_market_buy*(env: pointer, teamId: int32, resource: int32, amount: int32, outGoldCost: ptr int32, outResourceGained: ptr int32): int32 {.exportc, dynlib.} =
  ## Buy resources from market using gold from stockpile.
  ## Returns 1 on success, 0 on failure. Writes gold cost and resource gained to output pointers.
  if resource < 0 or resource > ord(StockpileResource.high):
    return 0
  let result = marketBuyResource(globalEnv, teamId, StockpileResource(resource), amount)
  if not outGoldCost.isNil:
    outGoldCost[] = result.goldCost.int32
  if not outResourceGained.isNil:
    outResourceGained[] = result.resourceGained.int32
  if result.resourceGained > 0: 1 else: 0

proc tribal_village_market_sell*(env: pointer, teamId: int32, resource: int32, amount: int32, outResourceSold: ptr int32, outGoldGained: ptr int32): int32 {.exportc, dynlib.} =
  ## Sell resources to market for gold.
  ## Returns 1 on success, 0 on failure. Writes resource sold and gold gained to output pointers.
  if resource < 0 or resource > ord(StockpileResource.high):
    return 0
  let result = marketSellResource(globalEnv, teamId, StockpileResource(resource), amount)
  if not outResourceSold.isNil:
    outResourceSold[] = result.resourceSold.int32
  if not outGoldGained.isNil:
    outGoldGained[] = result.goldGained.int32
  if result.goldGained > 0: 1 else: 0

proc tribal_village_market_sell_inventory*(env: pointer, agentId: int32, itemKind: int32, outAmountSold: ptr int32, outGoldGained: ptr int32): int32 {.exportc, dynlib.} =
  ## Sell all of an item from agent's inventory to their team's market.
  ## itemKind maps to ItemKind enum ordinal. Returns 1 on success, 0 on failure.
  if agentId < 0 or agentId >= MapAgents:
    return 0
  if itemKind < 0 or itemKind > ord(ItemKind.high):
    return 0
  let agent = globalEnv.agents[agentId]
  let itemKey = ItemKey(kind: ItemKeyItem, item: ItemKind(itemKind))
  let result = marketSellInventory(globalEnv, agent, itemKey)
  if not outAmountSold.isNil:
    outAmountSold[] = result.amountSold.int32
  if not outGoldGained.isNil:
    outGoldGained[] = result.goldGained.int32
  if result.goldGained > 0: 1 else: 0

proc tribal_village_market_buy_food*(env: pointer, agentId: int32, goldAmount: int32, outGoldSpent: ptr int32, outFoodGained: ptr int32): int32 {.exportc, dynlib.} =
  ## Buy food with gold from agent's inventory.
  ## Returns 1 on success, 0 on failure. Writes gold spent and food gained to output pointers.
  if agentId < 0 or agentId >= MapAgents:
    return 0
  let agent = globalEnv.agents[agentId]
  let result = marketBuyFood(globalEnv, agent, goldAmount)
  if not outGoldSpent.isNil:
    outGoldSpent[] = result.goldSpent.int32
  if not outFoodGained.isNil:
    outFoodGained[] = result.foodGained.int32
  if result.foodGained > 0: 1 else: 0

proc tribal_village_decay_market_prices*(env: pointer) {.exportc, dynlib.} =
  ## Slowly drift market prices back toward base rate.
  decayMarketPrices(globalEnv)

# --- Selection API ---

proc tribal_village_select_units*(env: pointer, agentIds: ptr int32, count: int32) {.exportc, dynlib.} =
  ## Replace current selection with the specified agent IDs.
  var ids: seq[int] = @[]
  for i in 0 ..< count:
    ids.add(int(cast[ptr UncheckedArray[int32]](agentIds)[i]))
  selectUnits(globalEnv, ids)

proc tribal_village_add_to_selection*(env: pointer, agentId: int32) {.exportc, dynlib.} =
  ## Add a single agent to the current selection.
  addToSelection(globalEnv, int(agentId))

proc tribal_village_remove_from_selection*(agentId: int32) {.exportc, dynlib.} =
  ## Remove a single agent from the current selection.
  removeFromSelection(int(agentId))

proc tribal_village_clear_selection*() {.exportc, dynlib.} =
  ## Clear the current selection.
  clearSelection()

proc tribal_village_get_selection_count*(): int32 {.exportc, dynlib.} =
  ## Get the number of currently selected units.
  int32(getSelectionCount())

proc tribal_village_get_selected_agent_id*(index: int32): int32 {.exportc, dynlib.} =
  ## Get the agent ID of a selected unit by index. Returns -1 if invalid.
  int32(getSelectedAgentId(int(index)))

# --- Control Group API ---

proc tribal_village_create_control_group*(env: pointer, groupIndex: int32, agentIds: ptr int32, count: int32) {.exportc, dynlib.} =
  ## Assign agents to a control group (0-9).
  var ids: seq[int] = @[]
  for i in 0 ..< count:
    ids.add(int(cast[ptr UncheckedArray[int32]](agentIds)[i]))
  createControlGroup(globalEnv, int(groupIndex), ids)

proc tribal_village_recall_control_group*(env: pointer, groupIndex: int32) {.exportc, dynlib.} =
  ## Recall a control group into the current selection.
  recallControlGroup(globalEnv, int(groupIndex))

proc tribal_village_get_control_group_count*(groupIndex: int32): int32 {.exportc, dynlib.} =
  ## Get the number of units in a control group.
  int32(getControlGroupCount(int(groupIndex)))

proc tribal_village_get_control_group_agent_id*(groupIndex: int32, index: int32): int32 {.exportc, dynlib.} =
  ## Get the agent ID at a position in a control group. Returns -1 if invalid.
  int32(getControlGroupAgentId(int(groupIndex), int(index)))

# --- Command to Selection ---

proc tribal_village_issue_command_to_selection*(env: pointer, commandType: int32, targetX: int32, targetY: int32) {.exportc, dynlib.} =
  ## Issue a command to all selected units.
  ## commandType: 0=attack-move, 1=patrol, 2=stop
  issueCommandToSelection(globalEnv, commandType, targetX, targetY)

# ============== Threat Map Query FFI Functions ==============

proc tribal_village_has_known_threats*(env: pointer, teamId: int32): int32 {.exportc, dynlib.} =
  ## Check if a team has any known (non-stale) threats.
  ## Returns 1 if threats exist, 0 otherwise.
  try:
    if isNil(globalController) or isNil(globalController.aiController):
      return 0
    let currentStep = globalEnv.currentStep.int32
    if hasKnownThreats(globalController.aiController, teamId.int, currentStep): 1 else: 0
  except CatchableError:
    return 0

proc tribal_village_get_nearest_threat*(env: pointer, agentId: int32,
    outX: ptr int32, outY: ptr int32, outStrength: ptr int32): int32 {.exportc, dynlib.} =
  ## Get the nearest threat to an agent's current position.
  ## Writes threat x, y, strength to output pointers.
  ## Returns 1 if a threat was found, 0 otherwise.
  try:
    if isNil(globalController) or isNil(globalController.aiController):
      return 0
    if agentId < 0 or agentId >= MapAgents:
      return 0
    let agent = globalEnv.agents[agentId]
    if not isAgentAlive(globalEnv, agent):
      return 0
    let teamId = agent.getTeamId()
    let currentStep = globalEnv.currentStep.int32
    let (pos, dist, found) = getNearestThreat(globalController.aiController, teamId, agent.pos, currentStep)
    if not found:
      return 0
    if not outX.isNil:
      outX[] = pos.x
    if not outY.isNil:
      outY[] = pos.y
    if not outStrength.isNil:
      # Look up the actual strength from the threat map entry
      let threats = getThreatsInRange(globalController.aiController, teamId, pos, 0, currentStep)
      outStrength[] = if threats.len > 0: threats[0].strength else: 0
    return 1
  except CatchableError:
    return 0

proc tribal_village_get_threats_in_range*(env: pointer, agentId: int32, radius: int32): int32 {.exportc, dynlib.} =
  ## Get the number of threats within radius of an agent's position.
  ## Returns the count of non-stale threats in range.
  try:
    if isNil(globalController) or isNil(globalController.aiController):
      return 0
    if agentId < 0 or agentId >= MapAgents:
      return 0
    let agent = globalEnv.agents[agentId]
    if not isAgentAlive(globalEnv, agent):
      return 0
    let teamId = agent.getTeamId()
    let currentStep = globalEnv.currentStep.int32
    let threats = getThreatsInRange(globalController.aiController, teamId, agent.pos, radius, currentStep)
    return threats.len.int32
  except CatchableError:
    return 0

proc tribal_village_get_threat_at*(env: pointer, teamId: int32, x: int32, y: int32): int32 {.exportc, dynlib.} =
  ## Get the threat strength at a specific map position for a team.
  ## Returns the strength value, or 0 if no threat at that position.
  try:
    if isNil(globalController) or isNil(globalController.aiController):
      return 0
    if teamId < 0 or teamId >= MapRoomObjectsTeams:
      return 0
    let currentStep = globalEnv.currentStep.int32
    let pos = ivec2(x, y)
    let threats = getThreatsInRange(globalController.aiController, teamId.int, pos, 0, currentStep)
    for entry in threats:
      if entry.pos == pos:
        return entry.strength
    return 0
  except CatchableError:
    return 0

# ============== Team Modifiers FFI Functions ==============

proc tribal_village_get_gather_rate_multiplier*(env: pointer, teamId: int32): float32 {.exportc, dynlib.} =
  ## Get the gather rate multiplier for a team. 1.0 = normal.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return 1.0'f32
  globalEnv.teamModifiers[teamId].gatherRateMultiplier

proc tribal_village_set_gather_rate_multiplier*(env: pointer, teamId: int32, value: float32) {.exportc, dynlib.} =
  ## Set the gather rate multiplier for a team. 1.0 = normal.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  globalEnv.teamModifiers[teamId].gatherRateMultiplier = value

proc tribal_village_get_build_cost_multiplier*(env: pointer, teamId: int32): float32 {.exportc, dynlib.} =
  ## Get the build cost multiplier for a team. 1.0 = normal.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return 1.0'f32
  globalEnv.teamModifiers[teamId].buildCostMultiplier

proc tribal_village_set_build_cost_multiplier*(env: pointer, teamId: int32, value: float32) {.exportc, dynlib.} =
  ## Set the build cost multiplier for a team. 1.0 = normal.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  globalEnv.teamModifiers[teamId].buildCostMultiplier = value

proc tribal_village_get_unit_hp_bonus*(env: pointer, teamId: int32, unitClass: int32): int32 {.exportc, dynlib.} =
  ## Get the bonus HP for a unit class on a team.
  ## unitClass: ordinal of AgentUnitClass enum.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return 0
  if unitClass < 0 or unitClass > ord(AgentUnitClass.high):
    return 0
  globalEnv.teamModifiers[teamId].unitHpBonus[AgentUnitClass(unitClass)].int32

proc tribal_village_set_unit_hp_bonus*(env: pointer, teamId: int32, unitClass: int32, bonus: int32) {.exportc, dynlib.} =
  ## Set the bonus HP for a unit class on a team.
  ## unitClass: ordinal of AgentUnitClass enum.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  if unitClass < 0 or unitClass > ord(AgentUnitClass.high):
    return
  globalEnv.teamModifiers[teamId].unitHpBonus[AgentUnitClass(unitClass)] = bonus.int

proc tribal_village_get_unit_attack_bonus*(env: pointer, teamId: int32, unitClass: int32): int32 {.exportc, dynlib.} =
  ## Get the bonus attack for a unit class on a team.
  ## unitClass: ordinal of AgentUnitClass enum.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return 0
  if unitClass < 0 or unitClass > ord(AgentUnitClass.high):
    return 0
  globalEnv.teamModifiers[teamId].unitAttackBonus[AgentUnitClass(unitClass)].int32

proc tribal_village_set_unit_attack_bonus*(env: pointer, teamId: int32, unitClass: int32, bonus: int32) {.exportc, dynlib.} =
  ## Set the bonus attack for a unit class on a team.
  ## unitClass: ordinal of AgentUnitClass enum.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  if unitClass < 0 or unitClass > ord(AgentUnitClass.high):
    return
  globalEnv.teamModifiers[teamId].unitAttackBonus[AgentUnitClass(unitClass)] = bonus.int

proc tribal_village_get_num_unit_classes*(): int32 {.exportc, dynlib.} =
  ## Get the number of AgentUnitClass values (for iterating over bonus arrays).
  int32(ord(AgentUnitClass.high) + 1)

# ============== Territory Scoring FFI Functions ==============

proc tribal_village_score_territory*(env: pointer) {.exportc, dynlib.} =
  ## Recompute territory scores. Results stored in env.territoryScore.
  globalEnv.territoryScore = globalEnv.scoreTerritory()

proc tribal_village_get_territory_team_tiles*(env: pointer, teamId: int32): int32 {.exportc, dynlib.} =
  ## Get the number of tiles owned by a team.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return 0
  globalEnv.territoryScore.teamTiles[teamId].int32

proc tribal_village_get_territory_clippy_tiles*(env: pointer): int32 {.exportc, dynlib.} =
  ## Get the number of tiles owned by clippy (NPC).
  globalEnv.territoryScore.clippyTiles.int32

proc tribal_village_get_territory_neutral_tiles*(env: pointer): int32 {.exportc, dynlib.} =
  ## Get the number of neutral (unclaimed) tiles.
  globalEnv.territoryScore.neutralTiles.int32

proc tribal_village_get_territory_scored_tiles*(env: pointer): int32 {.exportc, dynlib.} =
  ## Get the total number of scored tiles.
  globalEnv.territoryScore.scoredTiles.int32

proc tribal_village_get_num_teams*(): int32 {.exportc, dynlib.} =
  ## Get the number of teams (MapRoomObjectsTeams).
  MapRoomObjectsTeams.int32

# ============== AI Difficulty Control FFI Functions ==============

proc tribal_village_get_difficulty_level*(env: pointer, teamId: int32): int32 {.exportc, dynlib.} =
  ## Get the difficulty level for a team.
  ## Returns ordinal: 0=Easy, 1=Normal, 2=Hard, 3=Brutal
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return 1  # Default to Normal
  if isNil(globalController) or isNil(globalController.aiController):
    return 1
  ord(globalController.aiController.getDifficulty(teamId.int).level).int32

proc tribal_village_set_difficulty_level*(env: pointer, teamId: int32, level: int32) {.exportc, dynlib.} =
  ## Set the difficulty level for a team.
  ## level: 0=Easy, 1=Normal, 2=Hard, 3=Brutal
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  if isNil(globalController) or isNil(globalController.aiController):
    return
  if level < 0 or level > ord(DifficultyLevel.high):
    return
  globalController.aiController.setDifficulty(teamId.int, DifficultyLevel(level))

proc tribal_village_get_difficulty*(env: pointer, teamId: int32): float32 {.exportc, dynlib.} =
  ## Get the difficulty for a team as a float.
  ## Returns: 0.0=Easy, 1.0=Normal, 2.0=Hard, 3.0=Brutal
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return 1.0'f32  # Default to Normal
  if isNil(globalController) or isNil(globalController.aiController):
    return 1.0'f32
  float32(ord(globalController.aiController.getDifficulty(teamId.int).level))

proc tribal_village_set_difficulty*(env: pointer, teamId: int32, difficulty: float32) {.exportc, dynlib.} =
  ## Set the difficulty for a team using a float value.
  ## difficulty: 0.0=Easy, 1.0=Normal, 2.0=Hard, 3.0=Brutal (rounded to nearest)
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  if isNil(globalController) or isNil(globalController.aiController):
    return
  let levelInt = clamp(int(difficulty + 0.5), 0, ord(DifficultyLevel.high))
  globalController.aiController.setDifficulty(teamId.int, DifficultyLevel(levelInt))

proc tribal_village_set_adaptive_difficulty*(env: pointer, teamId: int32, enabled: int32) {.exportc, dynlib.} =
  ## Enable or disable adaptive difficulty for a team.
  ## enabled: 1=enable (with default 0.5 territory target), 0=disable
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  if isNil(globalController) or isNil(globalController.aiController):
    return
  if enabled != 0:
    globalController.aiController.enableAdaptiveDifficulty(teamId.int, 0.5'f32)
  else:
    globalController.aiController.disableAdaptiveDifficulty(teamId.int)

proc tribal_village_get_decision_delay_chance*(env: pointer, teamId: int32): float32 {.exportc, dynlib.} =
  ## Get the decision delay chance for a team (0.0-1.0).
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return 0.1  # Default to Normal (10%)
  if isNil(globalController) or isNil(globalController.aiController):
    return 0.1
  globalController.aiController.getDifficulty(teamId.int).decisionDelayChance

proc tribal_village_set_decision_delay_chance*(env: pointer, teamId: int32, chance: float32) {.exportc, dynlib.} =
  ## Set a custom decision delay chance for a team (0.0-1.0).
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  if isNil(globalController) or isNil(globalController.aiController):
    return
  globalController.aiController.difficulty[teamId].decisionDelayChance = clamp(chance, 0.0'f32, 1.0'f32)

proc tribal_village_enable_adaptive_difficulty*(env: pointer, teamId: int32, targetTerritory: float32) {.exportc, dynlib.} =
  ## Enable adaptive difficulty for a team.
  ## targetTerritory: target territory percentage (0.0-1.0, typically 0.5 for balanced)
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  if isNil(globalController) or isNil(globalController.aiController):
    return
  globalController.aiController.enableAdaptiveDifficulty(teamId.int, clamp(targetTerritory, 0.0'f32, 1.0'f32))

proc tribal_village_disable_adaptive_difficulty*(env: pointer, teamId: int32) {.exportc, dynlib.} =
  ## Disable adaptive difficulty for a team.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  if isNil(globalController) or isNil(globalController.aiController):
    return
  globalController.aiController.disableAdaptiveDifficulty(teamId.int)

proc tribal_village_is_adaptive_difficulty_enabled*(env: pointer, teamId: int32): int32 {.exportc, dynlib.} =
  ## Check if adaptive difficulty is enabled for a team.
  ## Returns 1 if enabled, 0 if disabled.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return 0
  if isNil(globalController) or isNil(globalController.aiController):
    return 0
  if globalController.aiController.getDifficulty(teamId.int).adaptive: 1 else: 0

proc tribal_village_get_adaptive_difficulty_target*(env: pointer, teamId: int32): float32 {.exportc, dynlib.} =
  ## Get the target territory percentage for adaptive difficulty.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return 0.5
  if isNil(globalController) or isNil(globalController.aiController):
    return 0.5
  globalController.aiController.getDifficulty(teamId.int).adaptiveTarget

proc tribal_village_get_threat_response_enabled*(env: pointer, teamId: int32): int32 {.exportc, dynlib.} =
  ## Check if threat response is enabled for a team.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return 0
  if isNil(globalController) or isNil(globalController.aiController):
    return 0
  if globalController.aiController.getDifficulty(teamId.int).threatResponseEnabled: 1 else: 0

proc tribal_village_set_threat_response_enabled*(env: pointer, teamId: int32, enabled: int32) {.exportc, dynlib.} =
  ## Enable or disable threat response for a team.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  if isNil(globalController) or isNil(globalController.aiController):
    return
  globalController.aiController.difficulty[teamId].threatResponseEnabled = enabled != 0

proc tribal_village_get_advanced_targeting_enabled*(env: pointer, teamId: int32): int32 {.exportc, dynlib.} =
  ## Check if advanced targeting is enabled for a team.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return 0
  if isNil(globalController) or isNil(globalController.aiController):
    return 0
  if globalController.aiController.getDifficulty(teamId.int).advancedTargetingEnabled: 1 else: 0

proc tribal_village_set_advanced_targeting_enabled*(env: pointer, teamId: int32, enabled: int32) {.exportc, dynlib.} =
  ## Enable or disable advanced targeting for a team.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  if isNil(globalController) or isNil(globalController.aiController):
    return
  globalController.aiController.difficulty[teamId].advancedTargetingEnabled = enabled != 0

proc tribal_village_get_coordination_enabled*(env: pointer, teamId: int32): int32 {.exportc, dynlib.} =
  ## Check if coordination is enabled for a team.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return 0
  if isNil(globalController) or isNil(globalController.aiController):
    return 0
  if globalController.aiController.getDifficulty(teamId.int).coordinationEnabled: 1 else: 0

proc tribal_village_set_coordination_enabled*(env: pointer, teamId: int32, enabled: int32) {.exportc, dynlib.} =
  ## Enable or disable coordination for a team.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  if isNil(globalController) or isNil(globalController.aiController):
    return
  globalController.aiController.difficulty[teamId].coordinationEnabled = enabled != 0

proc tribal_village_get_optimal_build_order_enabled*(env: pointer, teamId: int32): int32 {.exportc, dynlib.} =
  ## Check if optimal build order is enabled for a team.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return 0
  if isNil(globalController) or isNil(globalController.aiController):
    return 0
  if globalController.aiController.getDifficulty(teamId.int).optimalBuildOrderEnabled: 1 else: 0

proc tribal_village_set_optimal_build_order_enabled*(env: pointer, teamId: int32, enabled: int32) {.exportc, dynlib.} =
  ## Enable or disable optimal build order for a team.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  if isNil(globalController) or isNil(globalController.aiController):
    return
  globalController.aiController.difficulty[teamId].optimalBuildOrderEnabled = enabled != 0
