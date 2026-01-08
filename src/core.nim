# This file is included by src/external.nim
## Simplified AI system - clean and efficient
## Replaces the 1200+ line complex system with ~150 lines
import std/[tables, sets, algorithm]
import entropy
import vmath
import ./environment, common, terrain

type
  # Meta roles with focused responsibilities (AoE-style)
  AgentRole* = enum
    Gatherer   # Dynamic resource gatherer (food/wood/stone/gold + hearts)
    Builder    # Builds structures and expands the base
    Fighter    # Combat & hunting

  # Minimal state tracking with spiral search
  AgentState = object
    role: AgentRole
    # Spiral search state
    spiralStepsInArc: int
    spiralArcsCompleted: int
    spiralClockwise: bool
    basePosition: IVec2
    lastSearchPosition: IVec2
    # Bail-out / anti-oscillation state
    lastPosition: IVec2
    recentPositions: array[12, IVec2]
    recentPosIndex: int
    recentPosCount: int
    escapeMode: bool
    escapeStepsRemaining: int
    escapeDirection: IVec2
    cachedThingPos: array[ThingKind, IVec2]
    closestFoodPos: IVec2
    closestWoodPos: IVec2
    closestStonePos: IVec2
    closestGoldPos: IVec2
    closestMagmaPos: IVec2
    plannedTarget: IVec2
    plannedPath: seq[IVec2]
    plannedPathIndex: int
    pathBlockedTarget: IVec2

  # Simple controller
  Controller* = ref object
    rng*: Rand
    agents: array[MapAgents, AgentState]
    agentsInitialized: array[MapAgents, bool]
    buildingCountsStep: int
    buildingCounts: array[MapRoomObjectsHouses, array[ThingKind, int]]

proc newController*(seed: int): Controller =
  result = Controller(
    rng: initRand(seed),
    buildingCountsStep: -1
  )

# Helper proc to save state and return action
proc saveStateAndReturn(controller: Controller, agentId: int, state: AgentState, action: uint8): uint8 =
  controller.agents[agentId] = state
  controller.agentsInitialized[agentId] = true
  return action

proc vecToOrientation(vec: IVec2): int =
  ## Map a step vector to orientation index (0..7)
  let x = vec.x
  let y = vec.y
  if x == 0'i32 and y == -1'i32: return 0  # N
  elif x == 0'i32 and y == 1'i32: return 1  # S
  elif x == -1'i32 and y == 0'i32: return 2 # W
  elif x == 1'i32 and y == 0'i32: return 3  # E
  elif x == -1'i32 and y == -1'i32: return 4 # NW
  elif x == 1'i32 and y == -1'i32: return 5  # NE
  elif x == -1'i32 and y == 1'i32: return 6  # SW
  elif x == 1'i32 and y == 1'i32: return 7   # SE
  else: return 0

proc signi*(x: int32): int32 =
  if x < 0: -1
  elif x > 0: 1
  else: 0

proc chebyshevDist(a, b: IVec2): int32 =
  let dx = abs(a.x - b.x)
  let dy = abs(a.y - b.y)
  return (if dx > dy: dx else: dy)

proc updateClosestSeen(state: var AgentState, basePos: IVec2, candidate: IVec2, current: var IVec2) =
  if candidate.x < 0:
    return
  if current.x < 0:
    current = candidate
    return
  if chebyshevDist(candidate, basePos) < chebyshevDist(current, basePos):
    current = candidate

proc applyDirectionOffset(offset: var IVec2, direction: int, distance: int32) =
  case direction:
  of 0: offset.y -= distance  # North
  of 1: offset.x += distance  # East
  of 2: offset.y += distance  # South
  of 3: offset.x -= distance  # West
  else: discard

const Directions8 = [
  ivec2(0, -1),  # 0: North
  ivec2(0, 1),   # 1: South
  ivec2(-1, 0),  # 2: West
  ivec2(1, 0),   # 3: East
  ivec2(-1, -1), # 4: NW
  ivec2(1, -1),  # 5: NE
  ivec2(-1, 1),  # 6: SW
  ivec2(1, 1)    # 7: SE
]
const AltForCardinal = [
  [5, 4, 1, 3, 2],  # N blocked
  [7, 6, 0, 3, 2],  # S blocked
  [4, 6, 3, 0, 1],  # W blocked
  [5, 7, 2, 0, 1]   # E blocked
]

proc clampToPlayable(pos: IVec2): IVec2 {.inline.} =
  ## Keep positions inside the playable area (inside border walls).
  result.x = min(MapWidth - MapBorder - 1, max(MapBorder, pos.x))
  result.y = min(MapHeight - MapBorder - 1, max(MapBorder, pos.y))

proc spiralDir(dir: int, clockwise: bool): int =
  if clockwise:
    return dir
  case dir
  of 1: 3
  of 3: 1
  else: dir

proc getNextSpiralPoint(state: var AgentState, rng: var Rand): IVec2 =
  ## Generate next position in expanding spiral search pattern
  # Track current position in spiral
  var totalOffset = ivec2(0, 0)
  var currentArcLength = 1
  var direction = 0
  let clockwise = state.spiralClockwise

  # Rebuild position by simulating all steps up to current point
  for arcNum in 0 ..< state.spiralArcsCompleted:
    let arcLen = (arcNum div 2) + 1  # 1,1,2,2,3,3,4,4...
    let dir = spiralDir(arcNum mod 4, clockwise)  # Direction cycles 0,1,2,3 (N,E,S,W)
    applyDirectionOffset(totalOffset, dir, int32(arcLen))

  # Add partial progress in current arc
  currentArcLength = (state.spiralArcsCompleted div 2) + 1
  direction = spiralDir(state.spiralArcsCompleted mod 4, clockwise)

  # Add steps taken in current arc
  applyDirectionOffset(totalOffset, direction, int32(state.spiralStepsInArc))

  # Calculate next step
  state.spiralStepsInArc += 1

  # Check if we completed the current arc
  if state.spiralStepsInArc > currentArcLength:
    # Move to next arc
    state.spiralArcsCompleted += 1
    state.spiralStepsInArc = 1

    # Reset spiral after ~100 arcs (radius ~50) to avoid going too far
    if state.spiralArcsCompleted > 100:
      state.spiralArcsCompleted = 0  # Reset to start of spiral
      state.spiralStepsInArc = 1
      # Don't return to base immediately, continue spiral from current area
      state.basePosition = state.lastSearchPosition

  # Calculate next position
  applyDirectionOffset(totalOffset, direction, 1)
  result = clampToPlayable(state.basePosition + totalOffset)

proc findNearestThing(env: Environment, pos: IVec2, kind: ThingKind): Thing =
  result = nil
  var minDist = 999999
  for thing in env.thingsByKind[kind]:
    let dist = abs(thing.pos.x - pos.x) + abs(thing.pos.y - pos.y)
    if dist < minDist and dist < 30:  # Reasonable search radius
      minDist = dist
      result = thing

proc findNearestFriendlyThing(env: Environment, pos: IVec2, teamId: int, kind: ThingKind): Thing =
  result = nil
  var minDist = 999999
  for thing in env.thingsByKind[kind]:
    if thing.teamId == teamId:
      let dist = abs(thing.pos.x - pos.x) + abs(thing.pos.y - pos.y)
      if dist < minDist and dist < 30:
        minDist = dist
        result = thing

proc findNearestThingSpiral(env: Environment, state: var AgentState, kind: ThingKind, rng: var Rand): Thing =
  ## Find nearest thing using spiral search pattern - more systematic than random search
  let cachedPos = state.cachedThingPos[kind]
  if cachedPos.x >= 0:
    if abs(cachedPos.x - state.lastSearchPosition.x) + abs(cachedPos.y - state.lastSearchPosition.y) < 30:
      let cachedThing = env.getThing(cachedPos)
      if not isNil(cachedThing) and cachedThing.kind == kind:
        return cachedThing
    state.cachedThingPos[kind] = ivec2(-1, -1)

  # First check immediate area around current position
  result = findNearestThing(env, state.lastSearchPosition, kind)
  if not isNil(result):
    state.cachedThingPos[kind] = result.pos
    return result

  # Also check around agent's current position before advancing spiral
  result = findNearestThing(env, state.basePosition, kind)
  if not isNil(result):
    state.cachedThingPos[kind] = result.pos
    return result

  # If not found, advance spiral search only every few calls to reduce dithering
  let nextSearchPos = getNextSpiralPoint(state, rng)
  state.lastSearchPosition = nextSearchPos

  # Search from new spiral position
  result = findNearestThing(env, nextSearchPos, kind)
  if not isNil(result):
    state.cachedThingPos[kind] = result.pos
  return result

proc findNearestFriendlyThingSpiral(env: Environment, state: var AgentState, teamId: int,
                                    kind: ThingKind, rng: var Rand): Thing =
  ## Find nearest team-owned thing using spiral search pattern
  result = findNearestFriendlyThing(env, state.lastSearchPosition, teamId, kind)
  if not isNil(result):
    return result

  result = findNearestFriendlyThing(env, state.basePosition, teamId, kind)
  if not isNil(result):
    return result

  let nextSearchPos = getNextSpiralPoint(state, rng)
  state.lastSearchPosition = nextSearchPos
  result = findNearestFriendlyThing(env, nextSearchPos, teamId, kind)
  return result

proc countNearbyTerrain*(env: Environment, center: IVec2, radius: int,
                         allowed: set[TerrainType]): int =
  let cx = center.x.int
  let cy = center.y.int
  let startX = max(0, cx - radius)
  let endX = min(MapWidth - 1, cx + radius)
  let startY = max(0, cy - radius)
  let endY = min(MapHeight - 1, cy + radius)
  for x in startX..endX:
    for y in startY..endY:
      if max(abs(x - cx), abs(y - cy)) > radius:
        continue
      if env.terrain[x][y] in allowed:
        inc result

proc countNearbyThings*(env: Environment, center: IVec2, radius: int,
                        allowed: set[ThingKind]): int =
  let cx = center.x.int
  let cy = center.y.int
  let startX = max(0, cx - radius)
  let endX = min(MapWidth - 1, cx + radius)
  let startY = max(0, cy - radius)
  let endY = min(MapHeight - 1, cy + radius)
  for x in startX..endX:
    for y in startY..endY:
      if max(abs(x - cx), abs(y - cy)) > radius:
        continue
      let occ = env.grid[x][y]
      if not isNil(occ) and occ.kind in allowed:
        inc result

proc nearestFriendlyBuildingDistance*(env: Environment, teamId: int,
                                      kinds: openArray[ThingKind], pos: IVec2): int =
  result = int.high
  for thing in env.things:
    if thing.teamId != teamId:
      continue
    var matches = false
    for kind in kinds:
      if thing.kind == kind:
        matches = true
        break
    if not matches:
      continue
    let dist = int(chebyshevDist(thing.pos, pos))
    if dist < result:
      result = dist

proc getBuildingCount(controller: Controller, env: Environment, teamId: int, kind: ThingKind): int =
  if controller.buildingCountsStep != env.currentStep:
    controller.buildingCountsStep = env.currentStep
    controller.buildingCounts = default(array[MapRoomObjectsHouses, array[ThingKind, int]])
    for thing in env.things:
      if thing.isNil:
        continue
      if not isBuildingKind(thing.kind):
        continue
      controller.buildingCounts[thing.teamId][thing.kind] += 1
  controller.buildingCounts[teamId][kind]

proc canAffordBuild*(env: Environment, teamId: int, key: ItemKey): bool =
  let costs = buildCostsForKey(key)
  if costs.len == 0:
    return false
  env.canSpendStockpile(teamId, costs)


proc getCardinalDirIndex(fromPos, toPos: IVec2): int =
  ## Convert direction to orientation (0=N, 1=S, 2=W, 3=E, 4=NW, 5=NE, 6=SW, 7=SE)
  let dx = toPos.x - fromPos.x
  let dy = toPos.y - fromPos.y

  # Handle cardinal directions first (simpler pathfinding)
  if abs(dx) > abs(dy):
    if dx > 0: return 3  # East
    else: return 2       # West
  else:
    if dy > 0: return 1  # South
    else: return 0       # North

proc neighborDirIndex(fromPos, toPos: IVec2): int =
  ## Orientation index (0..7) toward adjacent target (includes diagonals)
  let dx = toPos.x - fromPos.x
  let dy = toPos.y - fromPos.y
  let sx = (if dx > 0: 1'i32 elif dx < 0: -1'i32 else: 0'i32)
  let sy = (if dy > 0: 1'i32 elif dy < 0: -1'i32 else: 0'i32)
  return vecToOrientation(ivec2(sx.int, sy.int))


proc sameTeam(agentA, agentB: Thing): bool =
  (agentA.agentId div MapAgentsPerVillage) == (agentB.agentId div MapAgentsPerVillage)

proc findAttackOpportunity(env: Environment, agent: Thing): int =
  ## Return attack orientation index if a valid target is in reach, else -1.
  ## Prefer the closest tumor; fall back to spawners or enemy agents if present.
  var bestTumor = (dir: -1, dist: int.high)
  var bestSpawner = (dir: -1, dist: int.high)
  var bestEnemy = (dir: -1, dist: int.high)

  if agent.unitClass == UnitMonk:
    return -1

  let rangedRange = case agent.unitClass
    of UnitArcher: ArcherBaseRange
    of UnitSiege: SiegeBaseRange
    else: 0

  if rangedRange > 0:
    for dirIdx in 0 .. 7:
      let delta = getOrientationDelta(Orientation(dirIdx))
      for distance in 1 .. rangedRange:
        let targetPos = agent.pos + ivec2(delta.x * distance, delta.y * distance)
        if targetPos.x < 0 or targetPos.x >= MapWidth or targetPos.y < 0 or targetPos.y >= MapHeight:
          continue
        let target = env.grid[targetPos.x][targetPos.y]
        if isNil(target):
          continue
        if target.kind == Agent and (not isAgentAlive(env, target) or sameTeam(agent, target)):
          continue
        let dist = int(chebyshevDist(agent.pos, target.pos))
        case target.kind
        of Tumor:
          if dist < bestTumor.dist:
            bestTumor = (dirIdx, dist)
          break
        of Spawner:
          if dist < bestSpawner.dist:
            bestSpawner = (dirIdx, dist)
          break
        of Agent:
          if dist < bestEnemy.dist:
            bestEnemy = (dirIdx, dist)
          break
        else:
          discard
          break

    if bestTumor.dir >= 0: return bestTumor.dir
    if bestSpawner.dir >= 0: return bestSpawner.dir
    if bestEnemy.dir >= 0: return bestEnemy.dir

  if agent.inventorySpear > 0:
    for thing in env.things:
      if thing.kind notin {Tumor, Spawner, Agent}:
        continue
      # Safety: skip stale things whose grid entry was already cleared (can happen after destruction
      # but before env.things is pruned). Without this, agents may attack an empty tile where the
      # object used to live.
      if thing.pos.x < 0 or thing.pos.x >= MapWidth or thing.pos.y < 0 or thing.pos.y >= MapHeight:
        continue
      if env.grid[thing.pos.x][thing.pos.y] != thing:
        continue
      if thing.kind == Agent:
        if not isAgentAlive(env, thing):
          continue
        if sameTeam(agent, thing):
          continue
      let dirIdx = block:
        var bestDir = -1
        var bestStep = int.high
        for checkDir in 0 .. 7:
          let d = getOrientationDelta(Orientation(checkDir))
          let left = ivec2(-d.y, d.x)
          let right = ivec2(d.y, -d.x)
          for step in 1 .. 3:
            let forward = agent.pos + ivec2(d.x * step, d.y * step)
            if forward == thing.pos or forward + left == thing.pos or forward + right == thing.pos:
              if step < bestStep:
                bestStep = step
                bestDir = checkDir
              break
        bestDir
      if dirIdx < 0:
        continue
      let dist = int(chebyshevDist(agent.pos, thing.pos))
      case thing.kind
      of Tumor:
        if dist < bestTumor.dist:
          bestTumor = (dirIdx, dist)
      of Spawner:
        if dist < bestSpawner.dist:
          bestSpawner = (dirIdx, dist)
      of Agent:
        if dist < bestEnemy.dist:
          bestEnemy = (dirIdx, dist)
      else:
        discard

    if bestTumor.dir >= 0: return bestTumor.dir
    if bestSpawner.dir >= 0: return bestSpawner.dir
    if bestEnemy.dir >= 0: return bestEnemy.dir

  # Fallback for non-spear attacks: 1-tile direct neighbors.
  for dirIdx in 0 .. 7:
    let delta = getOrientationDelta(Orientation(dirIdx))
    let targetPos = agent.pos + ivec2(delta.x, delta.y)
    if targetPos.x < 0 or targetPos.x >= MapWidth or
       targetPos.y < 0 or targetPos.y >= MapHeight:
      continue
    let occupant = env.grid[targetPos.x][targetPos.y]
    if isNil(occupant):
      continue

    if occupant.kind == Tumor:
      return dirIdx
    elif occupant.kind == Spawner and bestSpawner.dir < 0:
      bestSpawner = (dirIdx, 1)
    elif occupant.kind == Agent and bestEnemy.dir < 0 and isAgentAlive(env, occupant) and not sameTeam(agent, occupant):
      bestEnemy = (dirIdx, 1)

  if bestSpawner.dir >= 0: return bestSpawner.dir
  if bestEnemy.dir >= 0: return bestEnemy.dir
  return -1

proc isPassable(env: Environment, agent: Thing, pos: IVec2): bool =
  ## Consider lantern tiles passable for movement planning and respect doors/water.
  if not isValidPos(pos):
    return false
  if isBlockedTerrain(env.terrain[pos.x][pos.y]):
    return false
  if not env.canAgentPassDoor(agent, pos):
    return false
  let occupant = env.grid[pos.x][pos.y]
  if isNil(occupant):
    return true
  return occupant.kind == Lantern

proc getMoveTowards(env: Environment, agent: Thing, fromPos, toPos: IVec2, rng: var Rand): int =
  ## Get a movement direction towards target, with obstacle avoidance
  let clampedTarget = clampToPlayable(toPos)
  if clampedTarget == fromPos:
    # Target is outside playable bounds; push back inward toward the widest margin.
    var bestDir = -1
    var bestMargin = -1
    for idx, d in Directions8:
      let np = fromPos + d
      if not isPassable(env, agent, np):
        continue
      let marginX = min(np.x - MapBorder, (MapWidth - MapBorder - 1) - np.x)
      let marginY = min(np.y - MapBorder, (MapHeight - MapBorder - 1) - np.y)
      let margin = min(marginX, marginY)
      if margin > bestMargin:
        bestMargin = margin
        bestDir = idx
    if bestDir >= 0:
      return bestDir
    return randIntInclusive(rng, 0, 3)

  let primaryDir = getCardinalDirIndex(fromPos, clampedTarget)

  # Try primary direction first
  let primaryMove = fromPos + Directions8[primaryDir]
  if isPassable(env, agent, primaryMove):
    return primaryDir

  # Primary blocked, try adjacent directions
  if primaryDir <= 3:
    for altDir in AltForCardinal[primaryDir]:
      let altMove = fromPos + Directions8[altDir]
      if isPassable(env, agent, altMove):
        return altDir
  else:
    for altDir in [0, 1, 2, 3]:
      let altMove = fromPos + Directions8[altDir]
      if isPassable(env, agent, altMove):
        return altDir

  # All blocked, try random movement
  return randIntInclusive(rng, 0, 3)

proc findPath(env: Environment, agent: Thing, fromPos, targetPos: IVec2): seq[IVec2] =
  ## A* path from start to target (or passable neighbor), returns path including start.
  var goals: seq[IVec2] = @[]
  if isPassable(env, agent, targetPos):
    goals.add(targetPos)
  else:
    for d in Directions8:
      let candidate = targetPos + d
      if isValidPos(candidate) and isPassable(env, agent, candidate):
        goals.add(candidate)

  if goals.len == 0:
    return @[]
  for g in goals:
    if g == fromPos:
      return @[fromPos]

  proc heuristic(loc: IVec2): int =
    var best = int.high
    for g in goals:
      let d = int(chebyshevDist(loc, g))
      if d < best:
        best = d
    best

  var openSet = initHashSet[IVec2]()
  openSet.incl(fromPos)
  var cameFrom = initTable[IVec2, IVec2]()
  var gScore = initTable[IVec2, int]()
  var fScore = initTable[IVec2, int]()
  gScore[fromPos] = 0
  fScore[fromPos] = heuristic(fromPos)

  var explored = 0
  while openSet.len > 0:
    if explored > 250:
      return @[]

    var currentIter = false
    var current: IVec2
    var bestF = int.high
    for n in openSet:
      let f = (if fScore.hasKey(n): fScore[n] else: int.high)
      if not currentIter or f < bestF:
        bestF = f
        current = n
        currentIter = true

    if not currentIter:
      return @[]

    for g in goals:
      if current == g:
        var cur = current
        result = @[cur]
        var cf = cameFrom
        while cf.hasKey(cur):
          cur = cf[cur]
          result.add(cur)
        result.reverse()
        return result

    openSet.excl(current)
    inc explored

    for dirIdx in 0 .. 7:
      let nextPos = current + Directions8[dirIdx]
      if not isValidPos(nextPos):
        continue
      if not isPassable(env, agent, nextPos):
        continue

      let tentativeG = (if gScore.hasKey(current): gScore[current] else: int.high) + 1
      let nextG = (if gScore.hasKey(nextPos): gScore[nextPos] else: int.high)
      if tentativeG < nextG:
        cameFrom[nextPos] = current
        gScore[nextPos] = tentativeG
        fScore[nextPos] = tentativeG + heuristic(nextPos)
        openSet.incl(nextPos)

  @[]

proc hasTeamLanternNear(env: Environment, teamId: int, pos: IVec2): bool =
  for thing in env.things:
    if thing.kind != Lantern:
      continue
    if not thing.lanternHealthy or thing.teamId != teamId:
      continue
    if abs(thing.pos.x - pos.x) + abs(thing.pos.y - pos.y) <= 2:
      return true
  false

proc isLanternPlacementValid(env: Environment, pos: IVec2): bool =
  isValidPos(pos) and env.isEmpty(pos) and not env.hasDoor(pos) and
    not isBlockedTerrain(env.terrain[pos.x][pos.y]) and not isTileFrozen(pos, env) and
    env.terrain[pos.x][pos.y] != Water


proc tryPlantOnFertile(controller: Controller, env: Environment, agent: Thing,
                       agentId: int, state: var AgentState): tuple[did: bool, action: uint8] =
  ## If carrying wood/wheat and a fertile tile is nearby, plant; otherwise move toward it.
  if agent.inventoryWheat > 0 or agent.inventoryWood > 0:
    var fertilePos = ivec2(-1, -1)
    var minDist = 999999
    let startX = max(0, agent.pos.x - 8)
    let endX = min(MapWidth - 1, agent.pos.x + 8)
    let startY = max(0, agent.pos.y - 8)
    let endY = min(MapHeight - 1, agent.pos.y + 8)
    let ax = agent.pos.x.int
    let ay = agent.pos.y.int
    for x in startX..endX:
      for y in startY..endY:
        if env.terrain[x][y] != TerrainType.Fertile:
          continue
        let candPos = ivec2(x.int32, y.int32)
        if env.isEmpty(candPos) and isNil(env.getOverlayThing(candPos)) and not env.hasDoor(candPos):
          let dist = abs(x - ax) + abs(y - ay)
          if dist < minDist:
            minDist = dist
            fertilePos = candPos
    if fertilePos.x >= 0:
      let dx = abs(fertilePos.x - agent.pos.x)
      let dy = abs(fertilePos.y - agent.pos.y)
      if max(dx, dy) == 1'i32 and (dx == 0 or dy == 0):
        let dirIdx = getCardinalDirIndex(agent.pos, fertilePos)
        let plantArg = (if agent.inventoryWheat > 0: dirIdx else: dirIdx + 4)
        return (true, saveStateAndReturn(controller, agentId, state,
                 encodeAction(7'u8, plantArg.uint8)))
      else:
        return (true, saveStateAndReturn(controller, agentId, state,
                 encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, fertilePos, controller.rng).uint8)))
  return (false, 0'u8)

proc moveNextSearch(controller: Controller, env: Environment, agent: Thing, agentId: int,
                    state: var AgentState): uint8 =
  let nextSearchPos = getNextSpiralPoint(state, controller.rng)
  return saveStateAndReturn(controller, agentId, state,
    encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, nextSearchPos, controller.rng).uint8))

proc isAdjacent(a, b: IVec2): bool =
  let dx = abs(a.x - b.x)
  let dy = abs(a.y - b.y)
  max(dx, dy) == 1'i32

proc actAt(controller: Controller, env: Environment, agent: Thing, agentId: int,
           state: var AgentState, targetPos: IVec2, verb: uint8,
           argument: int = -1): uint8 =
  let desiredDir = neighborDirIndex(agent.pos, targetPos)
  let arg = if argument < 0: desiredDir else: argument
  return saveStateAndReturn(controller, agentId, state,
    encodeAction(verb, arg.uint8))

proc moveTo(controller: Controller, env: Environment, agent: Thing, agentId: int,
            state: var AgentState, targetPos: IVec2): uint8 =
  let dx = abs(targetPos.x - agent.pos.x)
  let dy = abs(targetPos.y - agent.pos.y)
  if max(dx, dy) >= 6'i32:
    if state.pathBlockedTarget != targetPos:
      if state.plannedTarget != targetPos or state.plannedPath.len == 0:
        state.plannedPath = findPath(env, agent, agent.pos, targetPos)
        state.plannedTarget = targetPos
        state.plannedPathIndex = 0
      elif state.plannedPathIndex < state.plannedPath.len and
           state.plannedPath[state.plannedPathIndex] != agent.pos:
        state.plannedPath = findPath(env, agent, agent.pos, targetPos)
        state.plannedTarget = targetPos
        state.plannedPathIndex = 0
      if state.plannedPath.len >= 2 and state.plannedPathIndex < state.plannedPath.len - 1:
        let nextPos = state.plannedPath[state.plannedPathIndex + 1]
        if isPassable(env, agent, nextPos):
          state.plannedPathIndex += 1
          return saveStateAndReturn(controller, agentId, state,
            encodeAction(1'u8, neighborDirIndex(agent.pos, nextPos).uint8))
        state.plannedPath.setLen(0)
        state.pathBlockedTarget = targetPos
      elif state.plannedPath.len == 0:
        state.pathBlockedTarget = targetPos
    else:
      state.plannedPath.setLen(0)
  return saveStateAndReturn(controller, agentId, state,
    encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, targetPos, controller.rng).uint8))

proc useAt(controller: Controller, env: Environment, agent: Thing, agentId: int,
           state: var AgentState, targetPos: IVec2): uint8 =
  actAt(controller, env, agent, agentId, state, targetPos, 3'u8)

proc tryMoveToKnownResource(controller: Controller, env: Environment, agent: Thing, agentId: int,
                            state: var AgentState, pos: var IVec2,
                            allowed: set[ThingKind], verb: uint8): tuple[did: bool, action: uint8] =
  if pos.x < 0:
    return (false, 0'u8)
  let thing = env.getThing(pos)
  if isNil(thing) or thing.kind notin allowed or isThingFrozen(thing, env):
    pos = ivec2(-1, -1)
    return (false, 0'u8)
  if isAdjacent(agent.pos, pos):
    return (true, actAt(controller, env, agent, agentId, state, pos, verb))
  return (true, moveTo(controller, env, agent, agentId, state, pos))

proc moveToNearestSmith(controller: Controller, env: Environment, agent: Thing, agentId: int,
                        state: var AgentState, teamId: int): tuple[did: bool, action: uint8] =
  let smith = env.findNearestFriendlyThingSpiral(state, teamId, Blacksmith, controller.rng)
  if not isNil(smith):
    if isAdjacent(agent.pos, smith.pos):
      return (true, controller.useAt(env, agent, agentId, state, smith.pos))
    return (true, controller.moveTo(env, agent, agentId, state, smith.pos))
  (false, 0'u8)

proc findDropoffBuilding*(env: Environment, state: var AgentState, teamId: int,
                          res: StockpileResource, rng: var Rand): Thing =
  template tryKind(kind: ThingKind): Thing =
    env.findNearestFriendlyThingSpiral(state, teamId, kind, rng)
  case res
  of ResourceFood:
    result = tryKind(Granary)
    if isNil(result):
      result = tryKind(Mill)
    if isNil(result):
      result = tryKind(TownCenter)
  of ResourceWood:
    result = tryKind(LumberCamp)
    if isNil(result):
      result = tryKind(TownCenter)
  of ResourceStone:
    result = tryKind(Quarry)
    if isNil(result):
      result = tryKind(TownCenter)
  of ResourceGold:
    result = tryKind(MiningCamp)
    if isNil(result):
      result = tryKind(TownCenter)
  of ResourceWater, ResourceNone:
    result = nil
  if isNil(result):
    var bestDist = int.high
    for thing in env.thingsByKind[TownCenter]:
      if thing.teamId != teamId:
        continue
      let dist = int(chebyshevDist(thing.pos, state.basePosition))
      if dist < bestDist:
        bestDist = dist
        result = thing

proc dropoffResourceIfCarrying*(controller: Controller, env: Environment, agent: Thing,
                                agentId: int, state: var AgentState,
                                res: StockpileResource, amount: int): tuple[did: bool, action: uint8] =
  ## Drop off a single resource type if carrying any
  if amount <= 0:
    return (false, 0'u8)
  let teamId = getTeamId(agent.agentId)
  let dropoff = findDropoffBuilding(env, state, teamId, res, controller.rng)
  if not isNil(dropoff):
    if isAdjacent(agent.pos, dropoff.pos):
      return (true, controller.useAt(env, agent, agentId, state, dropoff.pos))
    return (true, controller.moveTo(env, agent, agentId, state, dropoff.pos))
  (false, 0'u8)

proc dropoffCarrying*(controller: Controller, env: Environment, agent: Thing,
                      agentId: int, state: var AgentState,
                      allowFood: bool = false,
                      allowWood: bool = false,
                      allowStone: bool = false,
                      allowGold: bool = false): tuple[did: bool, action: uint8] =
  ## Unified dropoff function - attempts to drop off resources in priority order
  ## Priority: food -> wood -> gold -> stone

  # Food dropoff - requires checking inventory for any food items
  if allowFood:
    var hasFood = false
    for key, count in agent.inventory.pairs:
      if count > 0 and isFoodItem(key):
        hasFood = true
        break
    if hasFood:
      let teamId = getTeamId(agent.agentId)
      let dropoff = findDropoffBuilding(env, state, teamId, ResourceFood, controller.rng)
      if not isNil(dropoff):
        if isAdjacent(agent.pos, dropoff.pos):
          return (true, controller.useAt(env, agent, agentId, state, dropoff.pos))
        return (true, controller.moveTo(env, agent, agentId, state, dropoff.pos))

  # Wood dropoff
  if allowWood:
    let (did, act) = dropoffResourceIfCarrying(controller, env, agent, agentId, state,
                                                ResourceWood, agent.inventoryWood)
    if did: return (true, act)

  # Gold dropoff
  if allowGold:
    let (did, act) = dropoffResourceIfCarrying(controller, env, agent, agentId, state,
                                                ResourceGold, agent.inventoryGold)
    if did: return (true, act)

  # Stone dropoff
  if allowStone:
    let (did, act) = dropoffResourceIfCarrying(controller, env, agent, agentId, state,
                                                ResourceStone, agent.inventoryStone)
    if did: return (true, act)

  (false, 0'u8)

proc dropoffGathererCarrying*(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState,
                              allowGold: bool): tuple[did: bool, action: uint8] =
  ## Convenience wrapper for gatherers - drops food, wood, stone, and optionally gold
  dropoffCarrying(controller, env, agent, agentId, state,
                  allowFood = true, allowWood = true, allowStone = true, allowGold = allowGold)

proc ensureWood(controller: Controller, env: Environment, agent: Thing, agentId: int,
                state: var AgentState): tuple[did: bool, action: uint8] =
  let (didKnown, actKnown) = controller.tryMoveToKnownResource(
    env, agent, agentId, state, state.closestWoodPos, {Stump, Tree}, 3'u8)
  if didKnown: return (didKnown, actKnown)
  var target = env.findNearestThingSpiral(state, Stump, controller.rng)
  if not isNil(target):
    updateClosestSeen(state, state.basePosition, target.pos, state.closestWoodPos)
    if isAdjacent(agent.pos, target.pos):
      return (true, controller.useAt(env, agent, agentId, state, target.pos))
    return (true, controller.moveTo(env, agent, agentId, state, target.pos))
  target = env.findNearestThingSpiral(state, Tree, controller.rng)
  if not isNil(target):
    updateClosestSeen(state, state.basePosition, target.pos, state.closestWoodPos)
    if isAdjacent(agent.pos, target.pos):
      return (true, controller.useAt(env, agent, agentId, state, target.pos))
    return (true, controller.moveTo(env, agent, agentId, state, target.pos))
  target = env.findNearestThingSpiral(state, Tree, controller.rng)
  if not isNil(target):
    updateClosestSeen(state, state.basePosition, target.pos, state.closestWoodPos)
    if isAdjacent(agent.pos, target.pos):
      return (true, controller.useAt(env, agent, agentId, state, target.pos))
    return (true, controller.moveTo(env, agent, agentId, state, target.pos))
  (true, controller.moveNextSearch(env, agent, agentId, state))

proc ensureStone(controller: Controller, env: Environment, agent: Thing, agentId: int,
                 state: var AgentState): tuple[did: bool, action: uint8] =
  let (didKnown, actKnown) = controller.tryMoveToKnownResource(
    env, agent, agentId, state, state.closestStonePos, {Stone, Stalagmite}, 3'u8)
  if didKnown: return (didKnown, actKnown)
  var target = env.findNearestThingSpiral(state, Stone, controller.rng)
  if not isNil(target):
    updateClosestSeen(state, state.basePosition, target.pos, state.closestStonePos)
    if isAdjacent(agent.pos, target.pos):
      return (true, controller.useAt(env, agent, agentId, state, target.pos))
    return (true, controller.moveTo(env, agent, agentId, state, target.pos))
  target = env.findNearestThingSpiral(state, Stalagmite, controller.rng)
  if not isNil(target):
    updateClosestSeen(state, state.basePosition, target.pos, state.closestStonePos)
    if isAdjacent(agent.pos, target.pos):
      return (true, controller.useAt(env, agent, agentId, state, target.pos))
    return (true, controller.moveTo(env, agent, agentId, state, target.pos))
  (true, controller.moveNextSearch(env, agent, agentId, state))

proc ensureGold(controller: Controller, env: Environment, agent: Thing, agentId: int,
                state: var AgentState): tuple[did: bool, action: uint8] =
  let (didKnown, actKnown) = controller.tryMoveToKnownResource(
    env, agent, agentId, state, state.closestGoldPos, {Gold}, 3'u8)
  if didKnown: return (didKnown, actKnown)
  let target = env.findNearestThingSpiral(state, Gold, controller.rng)
  if not isNil(target):
    updateClosestSeen(state, state.basePosition, target.pos, state.closestGoldPos)
    if isAdjacent(agent.pos, target.pos):
      return (true, controller.useAt(env, agent, agentId, state, target.pos))
    return (true, controller.moveTo(env, agent, agentId, state, target.pos))
  (true, controller.moveNextSearch(env, agent, agentId, state))

proc ensureWheat(controller: Controller, env: Environment, agent: Thing, agentId: int,
                 state: var AgentState): tuple[did: bool, action: uint8] =
  let target = env.findNearestThingSpiral(state, Wheat, controller.rng)
  if not isNil(target):
    if isAdjacent(agent.pos, target.pos):
      return (true, controller.useAt(env, agent, agentId, state, target.pos))
    return (true, controller.moveTo(env, agent, agentId, state, target.pos))
  (true, controller.moveNextSearch(env, agent, agentId, state))

proc ensureHuntFood(controller: Controller, env: Environment, agent: Thing, agentId: int,
                    state: var AgentState): tuple[did: bool, action: uint8] =
  var target = env.findNearestThingSpiral(state, Corpse, controller.rng)
  if not isNil(target):
    updateClosestSeen(state, state.basePosition, target.pos, state.closestFoodPos)
    if isAdjacent(agent.pos, target.pos):
      return (true, controller.useAt(env, agent, agentId, state, target.pos))
    return (true, controller.moveTo(env, agent, agentId, state, target.pos))
  target = env.findNearestThingSpiral(state, Cow, controller.rng)
  if not isNil(target):
    updateClosestSeen(state, state.basePosition, target.pos, state.closestFoodPos)
    if isAdjacent(agent.pos, target.pos):
      return (true, controller.actAt(env, agent, agentId, state, target.pos, 2'u8))
    return (true, controller.moveTo(env, agent, agentId, state, target.pos))
  target = env.findNearestThingSpiral(state, Bush, controller.rng)
  if not isNil(target):
    updateClosestSeen(state, state.basePosition, target.pos, state.closestFoodPos)
    if isAdjacent(agent.pos, target.pos):
      return (true, controller.useAt(env, agent, agentId, state, target.pos))
    return (true, controller.moveTo(env, agent, agentId, state, target.pos))
  (true, controller.moveNextSearch(env, agent, agentId, state))
