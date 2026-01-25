# This file is included by src/agent_control.nim
proc tryBuildAction(controller: Controller, env: Environment, agent: Thing, agentId: int,
                    state: var AgentState, teamId: int, index: int): tuple[did: bool, action: uint8] =
  if index < 0 or index >= BuildChoices.len:
    return (false, 0'u8)
  let key = BuildChoices[index]
  if not env.canAffordBuild(agent, key):
    return (false, 0'u8)
  block findBuildPos:
    ## Find an empty adjacent tile for building, preferring the provided direction.
    let preferDir = orientationToVec(agent.orientation)
    let dirs = @[
      preferDir,
      ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0),
      ivec2(1, -1), ivec2(1, 1), ivec2(-1, 1), ivec2(-1, -1)
    ]
    var buildPos = ivec2(-1, -1)
    for d in dirs:
      if d.x == 0 and d.y == 0:
        continue
      let candidate = agent.pos + d
      if not isValidPos(candidate):
        continue
      if not env.canPlace(candidate):
        continue
      # Avoid building on roads/ramps so they stay clear for traffic.
      let candidateTerrain = env.terrain[candidate.x][candidate.y]
      if candidateTerrain == TerrainRoad or isRampTerrain(candidateTerrain):
        continue
      buildPos = candidate
      break
    if buildPos.x < 0:
      return (false, 0'u8)
  return (true, saveStateAndReturn(controller, agentId, state,
    encodeAction(8'u8, index.uint8)))


proc goToAdjacentAndBuild(controller: Controller, env: Environment, agent: Thing, agentId: int,
                          state: var AgentState, targetPos: IVec2,
                          buildIndex: int): tuple[did: bool, action: uint8] =
  if targetPos.x < 0:
    return (false, 0'u8)
  if buildIndex < 0 or buildIndex >= BuildChoices.len:
    return (false, 0'u8)
  if state.buildLockSteps > 0 and state.buildIndex != buildIndex:
    state.buildIndex = -1
    state.buildTarget = ivec2(-1, -1)
    state.buildStand = ivec2(-1, -1)
    state.buildLockSteps = 0
  var target = targetPos
  if state.buildLockSteps > 0 and state.buildIndex == buildIndex and state.buildTarget.x >= 0:
    let buildTargetTerrain = env.terrain[state.buildTarget.x][state.buildTarget.y]
    if env.canPlace(state.buildTarget) and buildTargetTerrain != TerrainRoad and
        not isRampTerrain(buildTargetTerrain):
      target = state.buildTarget
    dec state.buildLockSteps
    if state.buildLockSteps <= 0:
      state.buildIndex = -1
      state.buildTarget = ivec2(-1, -1)
      state.buildStand = ivec2(-1, -1)
  let teamId = getTeamId(agent)
  let key = BuildChoices[buildIndex]
  if not env.canAffordBuild(agent, key):
    return (false, 0'u8)
  if not env.canPlace(target):
    return (false, 0'u8)
  let targetTerrain = env.terrain[target.x][target.y]
  if targetTerrain == TerrainRoad or isRampTerrain(targetTerrain):
    return (false, 0'u8)
  if chebyshevDist(agent.pos, target) == 1'i32:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, buildIndex)
    if did:
      state.buildIndex = -1
      state.buildTarget = ivec2(-1, -1)
      state.buildStand = ivec2(-1, -1)
      state.buildLockSteps = 0
      return (true, act)
  state.buildTarget = target
  state.buildStand = ivec2(-1, -1)
  state.buildIndex = buildIndex
  if state.buildLockSteps <= 0:
    state.buildLockSteps = 8
  return (true, controller.moveTo(env, agent, agentId, state, target))

proc goToStandAndBuild(controller: Controller, env: Environment, agent: Thing, agentId: int,
                       state: var AgentState, standPos, targetPos: IVec2,
                       buildIndex: int): tuple[did: bool, action: uint8] =
  if standPos.x < 0:
    return (false, 0'u8)
  if buildIndex < 0 or buildIndex >= BuildChoices.len:
    return (false, 0'u8)
  if state.buildLockSteps > 0 and state.buildIndex != buildIndex:
    state.buildIndex = -1
    state.buildTarget = ivec2(-1, -1)
    state.buildStand = ivec2(-1, -1)
    state.buildLockSteps = 0
  var stand = standPos
  var target = targetPos
  if state.buildLockSteps > 0 and state.buildIndex == buildIndex and state.buildTarget.x >= 0 and
      state.buildStand.x >= 0:
    let buildTargetTerrain2 = env.terrain[state.buildTarget.x][state.buildTarget.y]
    if env.canPlace(state.buildTarget) and buildTargetTerrain2 != TerrainRoad and
        not isRampTerrain(buildTargetTerrain2) and
        isValidPos(state.buildStand) and not env.hasDoor(state.buildStand) and
        not isBlockedTerrain(env.terrain[state.buildStand.x][state.buildStand.y]) and
        not isTileFrozen(state.buildStand, env) and
        (env.isEmpty(state.buildStand) or state.buildStand == agent.pos) and
        env.canAgentPassDoor(agent, state.buildStand):
      target = state.buildTarget
      stand = state.buildStand
    dec state.buildLockSteps
    if state.buildLockSteps <= 0:
      state.buildIndex = -1
      state.buildTarget = ivec2(-1, -1)
      state.buildStand = ivec2(-1, -1)
  let teamId = getTeamId(agent)
  let key = BuildChoices[buildIndex]
  if not env.canAffordBuild(agent, key):
    return (false, 0'u8)
  if not env.canPlace(target):
    return (false, 0'u8)
  let targetTerrain2 = env.terrain[target.x][target.y]
  if targetTerrain2 == TerrainRoad or isRampTerrain(targetTerrain2):
    return (false, 0'u8)
  if not isValidPos(stand) or env.hasDoor(stand) or
      isBlockedTerrain(env.terrain[stand.x][stand.y]) or isTileFrozen(stand, env) or
      (not env.isEmpty(stand) and stand != agent.pos) or
      not env.canAgentPassDoor(agent, stand):
    return (false, 0'u8)
  if agent.pos == stand:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, buildIndex)
    if did:
      state.buildIndex = -1
      state.buildTarget = ivec2(-1, -1)
      state.buildStand = ivec2(-1, -1)
      state.buildLockSteps = 0
      return (true, act)
  state.buildTarget = target
  state.buildStand = stand
  state.buildIndex = buildIndex
  if state.buildLockSteps <= 0:
    let dist = int(chebyshevDist(agent.pos, stand))
    state.buildLockSteps = max(8, dist + 4)
  return (true, controller.moveTo(env, agent, agentId, state, stand))

proc tryBuildNearResource(controller: Controller, env: Environment, agent: Thing, agentId: int,
                          state: var AgentState, teamId: int, kind: ThingKind,
                          resourceCount, minResource: int,
                          nearbyKinds: openArray[ThingKind], distanceThreshold: int): tuple[did: bool, action: uint8] =
  if resourceCount < minResource:
    return (false, 0'u8)
  if nearestFriendlyBuildingDistance(env, teamId, nearbyKinds, agent.pos) <= distanceThreshold:
    return (false, 0'u8)
  let idx = buildIndexFor(kind)
  if idx >= 0:
    return tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
  (false, 0'u8)

proc tryBuildCampThreshold(controller: Controller, env: Environment, agent: Thing, agentId: int,
                           state: var AgentState, teamId: int, kind: ThingKind,
                           resourceCount, minResource: int,
                           nearbyKinds: openArray[ThingKind],
                           minSpacing: int = 3,
                           searchRadius: int = 4): tuple[did: bool, action: uint8] =
  ## Build a camp if resource threshold is met and no nearby camp is within minSpacing.
  if resourceCount < minResource:
    return (false, 0'u8)
  let dist = nearestFriendlyBuildingDistance(env, teamId, nearbyKinds, agent.pos)
  if dist <= minSpacing:
    return (false, 0'u8)
  let idx = buildIndexFor(kind)
  if idx < 0 or idx >= BuildChoices.len:
    return (false, 0'u8)
  let key = BuildChoices[idx]
  if not env.canAffordBuild(agent, key):
    return (false, 0'u8)
  block findBuildSpotNear:
    ## Find a buildable tile near center plus an adjacent stand tile.
    var buildPos = ivec2(-1, -1)
    var standPos = ivec2(-1, -1)
    let center = agent.pos
    let minX = max(0, center.x - searchRadius)
    let maxX = min(MapWidth - 1, center.x + searchRadius)
    let minY = max(0, center.y - searchRadius)
    let maxY = min(MapHeight - 1, center.y + searchRadius)

    for x in minX .. maxX:
      for y in minY .. maxY:
        let pos = ivec2(x.int32, y.int32)
        if not env.canPlace(pos):
          continue
        # Avoid building on roads/ramps so they stay clear for traffic.
        let posTerrain = env.terrain[pos.x][pos.y]
        if posTerrain == TerrainRoad or isRampTerrain(posTerrain):
          continue
        for d in CardinalOffsets:
          let stand = pos + d
          if not isValidPos(stand):
            continue
          if env.hasDoor(stand):
            continue
          if isBlockedTerrain(env.terrain[stand.x][stand.y]) or isTileFrozen(stand, env):
            continue
          if not env.isEmpty(stand) and stand != agent.pos:
            continue
          if not env.canAgentPassDoor(agent, stand):
            continue
          buildPos = pos
          standPos = stand
          break
        if buildPos.x >= 0:
          break
      if buildPos.x >= 0:
        break
    if buildPos.x < 0:
      return (false, 0'u8)
    return goToStandAndBuild(controller, env, agent, agentId, state,
      standPos, buildPos, idx)

proc tryBuildIfMissing(controller: Controller, env: Environment, agent: Thing, agentId: int,
                       state: var AgentState, teamId: int, kind: ThingKind): tuple[did: bool, action: uint8] =
  if controller.getBuildingCount(env, teamId, kind) != 0:
    return (false, 0'u8)
  let idx = buildIndexFor(kind)
  if idx < 0:
    return (false, 0'u8)
  let key = BuildChoices[idx]
  let costs = buildCostsForKey(key)
  if costs.len == 0:
    return (false, 0'u8)
  if choosePayment(env, agent, costs) == PayNone:
    for cost in costs:
      case stockpileResourceForItem(cost.key)
      of ResourceWood:
        return controller.ensureWood(env, agent, agentId, state)
      of ResourceStone:
        return controller.ensureStone(env, agent, agentId, state)
      of ResourceGold:
        return controller.ensureGold(env, agent, agentId, state)
      of ResourceFood:
        return controller.ensureWheat(env, agent, agentId, state)
      of ResourceWater, ResourceNone:
        discard
    return (false, 0'u8)

  let (didAdjacent, actAdjacent) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
  if didAdjacent:
    return (didAdjacent, actAdjacent)

  let anchor =
    if state.basePosition.x >= 0: state.basePosition
    elif agent.homeAltar.x >= 0: agent.homeAltar
    else: agent.pos

  const searchRadius = 8
  var bestDist = int.high
  var buildPos = ivec2(-1, -1)
  var standPos = ivec2(-1, -1)
  let minX = max(0, anchor.x - searchRadius)
  let maxX = min(MapWidth - 1, anchor.x + searchRadius)
  let minY = max(0, anchor.y - searchRadius)
  let maxY = min(MapHeight - 1, anchor.y + searchRadius)
  let ax = anchor.x.int
  let ay = anchor.y.int
  for x in minX .. maxX:
    for y in minY .. maxY:
      let pos = ivec2(x.int32, y.int32)
      if not env.canPlace(pos):
        continue
      let posTerrainHere = env.terrain[pos.x][pos.y]
      if posTerrainHere == TerrainRoad or isRampTerrain(posTerrainHere):
        continue
      for d in CardinalOffsets:
        let stand = pos + d
        if not isValidPos(stand):
          continue
        if env.hasDoor(stand):
          continue
        if isBlockedTerrain(env.terrain[stand.x][stand.y]) or isTileFrozen(stand, env):
          continue
        if not env.isEmpty(stand) and stand != agent.pos:
          continue
        if not env.canAgentPassDoor(agent, stand):
          continue
        let dist = abs(x - ax) + abs(y - ay)
        if dist < bestDist:
          bestDist = dist
          buildPos = pos
          standPos = stand
        break
  if buildPos.x >= 0:
    return goToStandAndBuild(controller, env, agent, agentId, state,
      standPos, buildPos, idx)
  return tryBuildAction(controller, env, agent, agentId, state, teamId, idx)

proc needsPopCapHouse(env: Environment, teamId: int): bool =
  var popCount = 0
  for otherAgent in env.agents:
    if not isAgentAlive(env, otherAgent):
      continue
    if getTeamId(otherAgent) == teamId:
      inc popCount
  var popCap = 0
  var hasBase = false
  for thing in env.things:
    if thing.isNil:
      continue
    if thing.teamId != teamId:
      continue
    if isBuildingKind(thing.kind):
      hasBase = true
      let cap = buildingPopCap(thing.kind)
      if cap > 0:
        popCap += cap
  if popCap >= MapAgentsPerTeam:
    return false
  let buffer = HousePopCap
  (popCap > 0 and popCount >= popCap - buffer) or
    (popCap == 0 and hasBase and popCount >= buffer)

proc tryBuildHouseForPopCap(controller: Controller, env: Environment, agent: Thing, agentId: int,
                            state: var AgentState, teamId: int, basePos: IVec2): tuple[did: bool, action: uint8] =
  ## Build a house when the team is at or near population cap.
  if needsPopCapHouse(env, teamId):
    let minX = max(0, basePos.x - 15)
    let maxX = min(MapWidth - 1, basePos.x + 15)
    let minY = max(0, basePos.y - 15)
    let maxY = min(MapHeight - 1, basePos.y + 15)
    var preferred: seq[tuple[build, stand: IVec2]]
    var fallback: seq[tuple[build, stand: IVec2]]
    for x in minX .. maxX:
      for y in minY .. maxY:
        let pos = ivec2(x.int32, y.int32)
        let dist = chebyshevDist(basePos, pos).int
        if dist < 5 or dist > 15:
          continue
        let posTerrainOutpost = env.terrain[pos.x][pos.y]
        if not env.canPlace(pos) or posTerrainOutpost == TerrainRoad or
            isRampTerrain(posTerrainOutpost):
          continue
        var standPos = ivec2(-1, -1)
        for d in CardinalOffsets:
          let stand = pos + d
          if isValidPos(stand) and not env.hasDoor(stand) and
              (env.isEmpty(stand) or stand == agent.pos) and
              env.canAgentPassDoor(agent, stand) and
              not isTileFrozen(stand, env) and
              not isBlockedTerrain(env.terrain[stand.x][stand.y]):
            standPos = stand
            break
        if standPos.x < 0:
          continue
        var adjacentHouses = 0
        for d in AdjacentOffsets8:
          let neighbor = pos + d
          if not isValidPos(neighbor):
            continue
          let occ = env.grid[neighbor.x][neighbor.y]
          if not isNil(occ) and occ.kind == House and occ.teamId == teamId:
            inc adjacentHouses
        var makesLine = false
        for dir in CardinalOffsets:
          var lineCount = 0
          for step in 1 .. 2:
            let neighbor = pos + ivec2(dir.x.int * step, dir.y.int * step)
            if not isValidPos(neighbor):
              break
            let occ = env.grid[neighbor.x][neighbor.y]
            if isNil(occ) or occ.kind != House or occ.teamId != teamId:
              break
            inc lineCount
          for step in 1 .. 2:
            let neighbor = pos - ivec2(dir.x.int * step, dir.y.int * step)
            if not isValidPos(neighbor):
              break
            let occ = env.grid[neighbor.x][neighbor.y]
            if isNil(occ) or occ.kind != House or occ.teamId != teamId:
              break
            inc lineCount
          if lineCount >= 2:
            makesLine = true
            break
        let candidate = (build: pos, stand: standPos)
        if adjacentHouses <= 1 and not makesLine:
          preferred.add(candidate)
        else:
          fallback.add(candidate)
    let candidates = if preferred.len > 0: preferred else: fallback
    if candidates.len > 0:
      let choice = candidates[randIntExclusive(controller.rng, 0, candidates.len)]
      return goToStandAndBuild(
        controller, env, agent, agentId, state,
        choice.stand, choice.build, buildIndexFor(House)
      )
  (false, 0'u8)

include "options"

include "gatherer"
include "builder"
include "fighter"
include "roles"
include "evolution"

const
  EvolutionEnabled = defined(enableEvolution)
  ScriptedRoleHistoryPath = "data/role_history.json"
  ScriptedScoreStep = 5000
  ScriptedGeneratedRoleCount = 16
  ScriptedRoleExplorationChance = 0.08
  ScriptedRoleMutationChance = 0.25
  ScriptedTempleAssignEnabled = true

type
  ScriptedRoleState = object
    initialized: bool
    catalog: RoleCatalog
    roleOptionsCache: seq[seq[OptionDef]]
    roleOptionsCached: seq[bool]
    roleAssignments: array[MapAgents, int]
    roleIsScripted: array[MapAgents, bool]
    pendingHybridRoles: array[MapAgents, int]
    coreRoleIds: array[AgentRole, int]
    lastEpisodeStep: int
    scoredAtStep: bool
    evolutionConfig: EvolutionConfig
    rolePool: seq[int]

var scriptedState: ScriptedRoleState

proc resetScriptedAssignments(state: var ScriptedRoleState) =
  for i in 0 ..< MapAgents:
    state.roleAssignments[i] = -1
    state.roleIsScripted[i] = false
    state.pendingHybridRoles[i] = -1

proc ensureRoleCache(state: var ScriptedRoleState) =
  if state.roleOptionsCache.len < state.catalog.roles.len:
    let needed = state.catalog.roles.len - state.roleOptionsCache.len
    for _ in 0 ..< needed:
      state.roleOptionsCache.add @[]
      state.roleOptionsCached.add false

proc buildCoreRole(catalog: var RoleCatalog, name: string,
                   options: openArray[OptionDef],
                   kind: AgentRole): int =
  let existing = findRoleId(catalog, name)
  if existing >= 0:
    catalog.roles[existing].kind = kind
    catalog.roles[existing].origin = "core"
    return existing
  var ids: seq[int] = @[]
  for opt in options:
    let id = findBehaviorId(catalog, opt.name)
    if id >= 0:
      ids.add id
  let tier = RoleTier(behaviorIds: ids, selection: TierFixed)
  let role = newRoleDef(catalog, name, @[tier], "core", kind)
  registerRole(catalog, role)

proc rebuildRolePool(state: var ScriptedRoleState) =
  state.rolePool.setLen(0)
  for role in state.catalog.roles:
    if role.origin != "core":
      state.rolePool.add role.id
  if state.rolePool.len == 0:
    for roleId in state.coreRoleIds:
      if roleId >= 0:
        state.rolePool.add roleId

proc generateRandomRole(state: var ScriptedRoleState, rng: var Rand,
                        origin: string): int =
  var role = sampleRole(state.catalog, rng, state.evolutionConfig)
  if randChance(rng, ScriptedRoleMutationChance):
    role = mutateRole(state.catalog, rng, role, state.evolutionConfig.mutationRate)
  role.origin = origin
  let id = registerRole(state.catalog, role)
  ensureRoleCache(state)
  if origin != "core":
    state.rolePool.add id
  id

proc initScriptedState(controller: Controller) =
  if scriptedState.initialized:
    return
  scriptedState.lastEpisodeStep = -1
  scriptedState.scoredAtStep = false
  resetScriptedAssignments(scriptedState)
  scriptedState.evolutionConfig = defaultEvolutionConfig()
  scriptedState.catalog = initRoleCatalog()
  scriptedState.catalog.seedDefaultBehaviorCatalog()
  if EvolutionEnabled:
    scriptedState.catalog.loadRoleHistory(ScriptedRoleHistoryPath)
  scriptedState.coreRoleIds = [
    buildCoreRole(scriptedState.catalog, "GathererCore", GathererOptions, Gatherer),
    buildCoreRole(scriptedState.catalog, "BuilderCore", BuilderOptions, Builder),
    buildCoreRole(scriptedState.catalog, "FighterCore", FighterOptions, Fighter),
    -1
  ]
  ensureRoleCache(scriptedState)
  if EvolutionEnabled:
    var nonCore = 0
    for role in scriptedState.catalog.roles:
      if role.origin != "core":
        inc nonCore
    while nonCore < ScriptedGeneratedRoleCount:
      discard generateRandomRole(scriptedState, controller.rng, "sampled")
      inc nonCore
  rebuildRolePool(scriptedState)
  resetScriptedAssignments(scriptedState)
  scriptedState.initialized = true

proc setAgentRole(agentId: int, state: var AgentState, roleId: int) =
  state.roleId = roleId
  scriptedState.roleAssignments[agentId] = roleId
  if roleId >= 0 and roleId < scriptedState.catalog.roles.len:
    state.role = scriptedState.catalog.roles[roleId].kind
    scriptedState.roleIsScripted[agentId] = scriptedState.catalog.roles[roleId].origin != "core"
  else:
    scriptedState.roleIsScripted[agentId] = false
  state.activeOptionId = -1
  state.activeOptionTicks = 0

proc assignScriptedRole(controller: Controller, agentId: int,
                        state: var AgentState) =
  initScriptedState(controller)
  if ScriptedTempleAssignEnabled and scriptedState.pendingHybridRoles[agentId] >= 0:
    let roleId = scriptedState.pendingHybridRoles[agentId]
    scriptedState.pendingHybridRoles[agentId] = -1
    setAgentRole(agentId, state, roleId)
    return
  var roleId = -1
  if EvolutionEnabled:
    if randChance(controller.rng, ScriptedRoleExplorationChance):
      roleId = generateRandomRole(scriptedState, controller.rng, "explore")
    else:
      roleId = pickRoleIdWeighted(scriptedState.catalog, controller.rng, scriptedState.rolePool)
  if roleId < 0:
    roleId = scriptedState.coreRoleIds[Gatherer]
  setAgentRole(agentId, state, roleId)

proc roleOptionsFor(roleId: int, rng: var Rand): seq[OptionDef] =
  if roleId < 0 or roleId >= scriptedState.catalog.roles.len:
    return @[]
  ensureRoleCache(scriptedState)
  if not scriptedState.roleOptionsCached[roleId]:
    scriptedState.roleOptionsCache[roleId] =
      materializeRoleOptions(scriptedState.catalog, scriptedState.catalog.roles[roleId], rng)
    scriptedState.roleOptionsCached[roleId] = true
  scriptedState.roleOptionsCache[roleId]

proc roleIdForAgent(controller: Controller, agentId: int): int

proc applyScriptedScoring(controller: Controller, env: Environment) =
  discard controller
  let score = env.scoreTerritory()
  let total = max(1, score.scoredTiles)
  var teamScores: array[MapRoomObjectsTeams, float32]
  for teamId in 0 ..< MapRoomObjectsTeams:
    teamScores[teamId] = float32(score.teamTiles[teamId]) / float32(total)
  var roleTeamCounts: Table[(int, int), int]
  for agent in env.agents:
    if not isAgentAlive(env, agent):
      continue
    let roleId = roleIdForAgent(controller, agent.agentId)
    if roleId < 0:
      continue
    let teamId = getTeamId(agent)
    if teamId < 0 or teamId >= MapRoomObjectsTeams:
      continue
    let key = (roleId, teamId)
    roleTeamCounts[key] = roleTeamCounts.getOrDefault(key, 0) + 1
  for key, count in roleTeamCounts.pairs:
    let roleId = key[0]
    let teamId = key[1]
    if roleId < 0 or roleId >= scriptedState.catalog.roles.len:
      continue
    if teamId < 0 or teamId >= MapRoomObjectsTeams:
      continue
    let sampleTeamScore = teamScores[teamId]
    let weight = min(4, count)
    recordRoleScore(scriptedState.catalog.roles[roleId], sampleTeamScore, sampleTeamScore >= 0.5, weight = weight)
    lockRoleNameIfFit(scriptedState.catalog.roles[roleId], scriptedState.evolutionConfig.lockFitnessThreshold)
    for tier in scriptedState.catalog.roles[roleId].tiers:
      for behaviorId in tier.behaviorIds:
        if behaviorId >= 0 and behaviorId < scriptedState.catalog.behaviors.len:
          recordBehaviorScore(scriptedState.catalog.behaviors[behaviorId], sampleTeamScore, weight = weight)
          inc scriptedState.catalog.behaviors[behaviorId].uses
  scriptedState.catalog.saveRoleHistory(ScriptedRoleHistoryPath)

proc roleIdForAgent(controller: Controller, agentId: int): int =
  if controller.agentsInitialized[agentId]:
    let stateRoleId = controller.agents[agentId].roleId
    if stateRoleId >= 0 and stateRoleId < scriptedState.catalog.roles.len:
      return stateRoleId
  let assigned = scriptedState.roleAssignments[agentId]
  if assigned >= 0 and assigned < scriptedState.catalog.roles.len:
    return assigned
  let stateRole = controller.agents[agentId].role
  let coreId = scriptedState.coreRoleIds[stateRole]
  if coreId >= 0:
    return coreId
  scriptedState.coreRoleIds[Gatherer]

proc injectBehavior(role: var RoleDef, rng: var Rand, catalog: RoleCatalog) =
  if role.tiers.len == 0 or catalog.behaviors.len == 0:
    return
  let newId = randIntExclusive(rng, 0, catalog.behaviors.len)
  for id in role.tiers[0].behaviorIds:
    if id == newId:
      return
  role.tiers[0].behaviorIds.add newId

proc processTempleHybridRequests(controller: Controller, env: Environment) =
  if env.templeHybridRequests.len == 0:
    return
  for req in env.templeHybridRequests:
    if req.childId < 0 or req.childId >= MapAgents:
      continue
    let roleAId = roleIdForAgent(controller, req.parentA)
    let roleBId = roleIdForAgent(controller, req.parentB)
    if roleAId < 0 or roleBId < 0:
      continue
    let roleA = scriptedState.catalog.roles[roleAId]
    let roleB = scriptedState.catalog.roles[roleBId]
    var hybrid = recombineRoles(scriptedState.catalog, controller.rng, roleA, roleB)
    if randChance(controller.rng, ScriptedRoleMutationChance):
      hybrid = mutateRole(scriptedState.catalog, controller.rng, hybrid, scriptedState.evolutionConfig.mutationRate)
    if randChance(controller.rng, 0.35):
      injectBehavior(hybrid, controller.rng, scriptedState.catalog)
    hybrid.origin = "temple"
    let newRoleId = registerRole(scriptedState.catalog, hybrid)
    ensureRoleCache(scriptedState)
    scriptedState.rolePool.add newRoleId
    scriptedState.pendingHybridRoles[req.childId] = newRoleId
    if ScriptedTempleAssignEnabled:
      controller.agentsInitialized[req.childId] = false
  env.templeHybridRequests.setLen(0)

const GoblinAvoidRadius = 6

proc tryPrioritizeHearts(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): tuple[did: bool, action: uint8] =
  let teamId = getTeamId(agent)
  var altarPos = ivec2(-1, -1)
  var altarHearts = 0
  if agent.homeAltar.x >= 0:
    let homeAltar = env.getThing(agent.homeAltar)
    if not isNil(homeAltar) and homeAltar.kind == Altar and homeAltar.teamId == teamId:
      altarPos = homeAltar.pos
      altarHearts = homeAltar.hearts
  if altarPos.x < 0:
    var bestDist = int.high
    for altar in env.thingsByKind[Altar]:
      if altar.teamId != teamId:
        continue
      let dist = abs(altar.pos.x - agent.pos.x) + abs(altar.pos.y - agent.pos.y)
      if dist < bestDist:
        bestDist = dist
        altarPos = altar.pos
        altarHearts = altar.hearts
  if altarPos.x < 0 or altarHearts >= 10:
    return (false, 0'u8)

  if agent.inventoryBar > 0:
    if isAdjacent(agent.pos, altarPos):
      return (true, controller.useAt(env, agent, agentId, state, altarPos))
    return (true, controller.moveTo(env, agent, agentId, state, altarPos))

  if agent.inventoryGold > 0:
    let (didKnown, actKnown) = controller.tryMoveToKnownResource(
      env, agent, agentId, state, state.closestMagmaPos, {Magma}, 3'u8)
    if didKnown: return (true, actKnown)
    let magmaGlobal = findNearestThing(env, agent.pos, Magma, maxDist = int.high)
    if not isNil(magmaGlobal):
      updateClosestSeen(state, state.basePosition, magmaGlobal.pos, state.closestMagmaPos)
      if isAdjacent(agent.pos, magmaGlobal.pos):
        return (true, controller.useAt(env, agent, agentId, state, magmaGlobal.pos))
      return (true, controller.moveTo(env, agent, agentId, state, magmaGlobal.pos))
    return (true, controller.moveNextSearch(env, agent, agentId, state))

  if agent.unitClass == UnitVillager:
    let (didGold, actGold) = controller.ensureGold(env, agent, agentId, state)
    if didGold: return (true, actGold)

  (false, 0'u8)

proc decideRoleFromCatalog(controller: Controller, env: Environment, agent: Thing,
                           agentId: int, state: var AgentState): uint8 =
  if state.role == Gatherer:
    updateGathererTask(controller, env, agent, state)
  var roleId = state.roleId
  if roleId < 0 or roleId >= scriptedState.catalog.roles.len:
    roleId = roleIdForAgent(controller, agentId)
  # Dynamic defense priority: Builders use threat-aware option ordering
  if state.role == Builder and isBuilderUnderThreat(env, agent):
    return runOptions(controller, env, agent, agentId, state, BuilderOptionsThreat)
  let options = roleOptionsFor(roleId, controller.rng)
  if options.len == 0:
    return 0'u8
  return runOptions(controller, env, agent, agentId, state, options)

proc decideAction*(controller: Controller, env: Environment, agentId: int): uint8 =
  let agent = env.agents[agentId]

  # Skip inactive agents
  if not isAgentAlive(env, agent):
    return encodeAction(0'u8, 0'u8)

  initScriptedState(controller)

  # Initialize agent role if needed (2 gatherers, 2 builders, 2 fighters)
  if not controller.agentsInitialized[agentId]:
    let slot = agentId mod MapAgentsPerTeam
    var role =
      case slot mod 6
      of 0, 1: Gatherer
      of 2, 3: Builder
      else: Fighter

    var initState = AgentState(
      role: role,
      roleId: -1,
      activeOptionId: -1,
      activeOptionTicks: 0,
      gathererTask: TaskFood,
      fighterEnemyAgentId: -1,
      fighterEnemyStep: -1,
      spiralStepsInArc: 0,
      spiralArcsCompleted: 0,
      spiralClockwise: (agentId mod 2) == 0,
      basePosition: agent.pos,
      lastSearchPosition: agent.pos,
      lastPosition: agent.pos,
      recentPosIndex: 0,
      recentPosCount: 0,
      escapeMode: false,
      escapeStepsRemaining: 0,
      escapeDirection: ivec2(0, -1),
      lastActionVerb: 0,
      lastActionArg: 0,
      blockedMoveDir: -1,
      blockedMoveSteps: 0,
      cachedWaterPos: ivec2(-1, -1),
      closestFoodPos: ivec2(-1, -1),
      closestWoodPos: ivec2(-1, -1),
      closestStonePos: ivec2(-1, -1),
      closestGoldPos: ivec2(-1, -1),
      closestWaterPos: ivec2(-1, -1),
      closestMagmaPos: ivec2(-1, -1),
      buildTarget: ivec2(-1, -1),
      buildStand: ivec2(-1, -1),
      buildIndex: -1,
      buildLockSteps: 0,
      plannedTarget: ivec2(-1, -1),
      plannedPath: @[],
      plannedPathIndex: 0,
      pathBlockedTarget: ivec2(-1, -1)
    )
    for kind in ThingKind:
      initState.cachedThingPos[kind] = ivec2(-1, -1)
    if ScriptedTempleAssignEnabled and scriptedState.pendingHybridRoles[agentId] >= 0:
      let pending = scriptedState.pendingHybridRoles[agentId]
      scriptedState.pendingHybridRoles[agentId] = -1
      setAgentRole(agentId, initState, pending)
    elif role == Scripted:
      assignScriptedRole(controller, agentId, initState)
    else:
      var roleId = scriptedState.coreRoleIds[role]
      if roleId < 0:
        roleId = scriptedState.coreRoleIds[Gatherer]
      setAgentRole(agentId, initState, roleId)
    controller.agents[agentId] = initState
    controller.agentsInitialized[agentId] = true

  var state = controller.agents[agentId]

  if agent.unitClass == UnitGoblin:
    var totalRelicsHeld = 0
    for other in env.agents:
      if not isAgentAlive(env, other):
        continue
      if other.unitClass == UnitGoblin:
        totalRelicsHeld += other.inventoryRelic
    if totalRelicsHeld >= MapRoomObjectsRelics and env.thingsByKind[Relic].len == 0:
      return saveStateAndReturn(controller, agentId, state, encodeAction(0'u8, 0'u8))

    var nearestThreat: Thing = nil
    var threatDist = int.high
    for other in env.agents:
      if other.agentId == agent.agentId:
        continue
      if not isAgentAlive(env, other):
        continue
      if other.unitClass == UnitGoblin:
        continue
      let dist = int(chebyshevDist(agent.pos, other.pos))
      if dist < threatDist:
        threatDist = dist
        nearestThreat = other

    if not isNil(nearestThreat) and threatDist <= GoblinAvoidRadius:
      let dx = signi(agent.pos.x - nearestThreat.pos.x)
      let dy = signi(agent.pos.y - nearestThreat.pos.y)
      let awayTarget = clampToPlayable(agent.pos + ivec2(dx * 6, dy * 6))
      return controller.moveTo(env, agent, agentId, state, awayTarget)

    let relic = env.findNearestThingSpiral(state, Relic)
    if not isNil(relic):
      return actOrMove(controller, env, agent, agentId, state, relic.pos, 3'u8)

    return controller.moveNextSearch(env, agent, agentId, state)

  # --- Simple bail-out to avoid getting stuck/oscillation ---
  # Update recent positions history (ring buffer size 12)
  state.recentPositions[state.recentPosIndex] = agent.pos
  state.recentPosIndex = (state.recentPosIndex + 1) mod 12
  if state.recentPosCount < 12:
    inc state.recentPosCount

  proc recentAt(offset: int): IVec2 =
    let idx = (state.recentPosIndex - 1 - offset + 12 * 12) mod 12
    state.recentPositions[idx]

  if state.blockedMoveSteps > 0:
    dec state.blockedMoveSteps
    if state.blockedMoveSteps <= 0:
      state.blockedMoveDir = -1

  if state.lastActionVerb == 1 and state.recentPosCount >= 2:
    if recentAt(1) == agent.pos and state.lastActionArg >= 0 and state.lastActionArg <= 7:
      state.blockedMoveDir = state.lastActionArg
      state.blockedMoveSteps = 4
      state.plannedPath.setLen(0)
      state.pathBlockedTarget = ivec2(-1, -1)

  # Enter escape mode if stuck in 1-3 tiles for 10+ steps
  let stuckWindow = if state.role == Builder: 6 else: 10
  if not state.escapeMode and state.recentPosCount >= stuckWindow:
    var uniqueCount = 0
    var unique: array[3, IVec2]
    for i in 0 ..< stuckWindow:
      let p = recentAt(i)
      var seen = false
      for j in 0 ..< uniqueCount:
        if unique[j] == p:
          seen = true
          break
      if not seen:
        if uniqueCount < 3:
          unique[uniqueCount] = p
          inc uniqueCount
        else:
          uniqueCount = 4
          break
    if uniqueCount <= 3:
      state.plannedTarget = ivec2(-1, -1)
      state.plannedPath.setLen(0)
      state.plannedPathIndex = 0
      state.pathBlockedTarget = ivec2(-1, -1)
      for kind in ThingKind:
        state.cachedThingPos[kind] = ivec2(-1, -1)
      state.closestFoodPos = ivec2(-1, -1)
      state.closestWoodPos = ivec2(-1, -1)
      state.closestStonePos = ivec2(-1, -1)
      state.closestGoldPos = ivec2(-1, -1)
      state.closestMagmaPos = ivec2(-1, -1)
      state.escapeMode = true
      state.escapeStepsRemaining = 10
      state.recentPosCount = 0
      state.recentPosIndex = 0
      # Choose an escape direction: prefer any empty cardinal, shuffled
      var dirs = CardinalOffsets
      for i in countdown(dirs.len - 1, 1):
        let j = randIntInclusive(controller.rng, 0, i)
        let tmp = dirs[i]
        dirs[i] = dirs[j]
        dirs[j] = tmp
      var chosen = ivec2(0, -1)
      for d in dirs:
        if isPassable(env, agent, agent.pos + d):
          chosen = d
          break
      state.escapeDirection = chosen

  # If in escape mode, try to move in escape direction for a few steps
  if state.escapeMode and state.escapeStepsRemaining > 0:
    let tryDirs = [state.escapeDirection,
                   ivec2(state.escapeDirection.y, -state.escapeDirection.x),  # perpendicular 1
                   ivec2(-state.escapeDirection.y, state.escapeDirection.x),  # perpendicular 2
                   ivec2(-state.escapeDirection.x, -state.escapeDirection.y)] # opposite
    for d in tryDirs:
      let np = agent.pos + d
      if isPassable(env, agent, np):
        dec state.escapeStepsRemaining
        if state.escapeStepsRemaining <= 0:
          state.escapeMode = false
        state.lastPosition = agent.pos
        return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, vecToOrientation(d).uint8))
    # If all blocked, drop out of escape for this tick
    state.escapeMode = false

  # From here on, ensure lastPosition is updated this tick regardless of branch
  state.lastPosition = agent.pos
  # Anchor spiral search around home altar when possible (common base-centric search)
  if agent.homeAltar.x >= 0:
    state.basePosition = agent.homeAltar
  else:
    state.basePosition = agent.pos

  # Emergency self-heal: eat bread if below half HP (applies to all roles)
  if agent.inventoryBread > 0 and agent.hp * 2 < agent.maxHp:
    let healDirs = AdjacentOffsets8
    for d in healDirs:
      let target = agent.pos + d
      if not env.hasDoor(target) and
          isValidPos(target) and
          env.isEmpty(target) and
          not isBlockedTerrain(env.terrain[target.x][target.y]) and
          env.canAgentPassDoor(agent, target):
        let dirIdx = neighborDirIndex(agent.pos, target)
        return saveStateAndReturn(
          controller, agentId, state,
          encodeAction(3'u8, dirIdx.uint8))

  let attackDir = findAttackOpportunity(env, agent)
  if attackDir >= 0:
    return saveStateAndReturn(controller, agentId, state, encodeAction(2'u8, attackDir.uint8))

  # Global: prioritize getting hearts to 10 via gold -> magma -> altar (gatherers only).
  if state.role == Gatherer:
    let (didHearts, heartsAct) = tryPrioritizeHearts(controller, env, agent, agentId, state)
    if didHearts: return heartsAct

  # Global: keep population cap ahead of current population (gatherers only).
  if state.role == Gatherer and agent.unitClass == UnitVillager:
    let teamId = getTeamId(agent)
    if needsPopCapHouse(env, teamId):
      let houseKey = thingItem("House")
      let costs = buildCostsForKey(houseKey)
      var requiredWood = 0
      if costs.len > 0:
        for cost in costs:
          if stockpileResourceForItem(cost.key) == ResourceWood:
            requiredWood += cost.count
      if requiredWood > 0 and
          env.stockpileCount(teamId, ResourceWood) + agent.inventoryWood < requiredWood:
        let (didWood, actWood) = controller.ensureWood(env, agent, agentId, state)
        if didWood: return actWood
      if env.canAffordBuild(agent, houseKey):
        let (didHouse, houseAct) =
          tryBuildHouseForPopCap(controller, env, agent, agentId, state, teamId, state.basePosition)
        if didHouse: return houseAct

  # Role-based decision making (unified priority lists)
  return decideRoleFromCatalog(controller, env, agent, agentId, state)

# Compatibility function for updateController
proc updateController*(controller: Controller, env: Environment) =
  initScriptedState(controller)
  if scriptedState.lastEpisodeStep >= 0 and env.currentStep < scriptedState.lastEpisodeStep:
    for i in 0 ..< MapAgents:
      controller.agentsInitialized[i] = false
    controller.buildingCountsStep = -1
    resetScriptedAssignments(scriptedState)
    scriptedState.scoredAtStep = false
    scriptedState.lastEpisodeStep = -1
  if EvolutionEnabled:
    if not scriptedState.scoredAtStep and env.currentStep >= ScriptedScoreStep:
      applyScriptedScoring(controller, env)
      scriptedState.scoredAtStep = true
  if ScriptedTempleAssignEnabled:
    processTempleHybridRequests(controller, env)
  scriptedState.lastEpisodeStep = env.currentStep
