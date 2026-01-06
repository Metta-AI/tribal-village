# This file is included by src/ai.nim
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
    Builder    # Builds structures + equips villagers
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
    recentPositions: seq[IVec2]
    stuckCounter: int
    escapeMode: bool
    escapeStepsRemaining: int
    escapeDirection: IVec2

  # Simple controller
  Controller* = ref object
    rng*: Rand
    agents: Table[int, AgentState]

proc newController*(seed: int): Controller =
  result = Controller(
    rng: initRand(seed),
    agents: initTable[int, AgentState]()
  )

# Helper proc to save state and return action
proc saveStateAndReturn(controller: Controller, agentId: int, state: AgentState, action: uint8): uint8 =
  controller.agents[agentId] = state
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

proc applyDirectionOffset(offset: var IVec2, direction: int, distance: int32) =
  case direction:
  of 0: offset.y -= distance  # North
  of 1: offset.x += distance  # East
  of 2: offset.y += distance  # South
  of 3: offset.x -= distance  # West
  else: discard

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
  for thing in env.things:
    if thing.kind == kind:
      let dist = abs(thing.pos.x - pos.x) + abs(thing.pos.y - pos.y)
      if dist < minDist and dist < 30:  # Reasonable search radius
        minDist = dist
        result = thing

proc findNearestFriendlyThing(env: Environment, pos: IVec2, teamId: int, kind: ThingKind): Thing =
  result = nil
  var minDist = 999999
  for thing in env.things:
    if thing.kind == kind and thing.teamId == teamId:
      let dist = abs(thing.pos.x - pos.x) + abs(thing.pos.y - pos.y)
      if dist < minDist and dist < 30:
        minDist = dist
        result = thing

proc findNearestThingSpiral(env: Environment, state: var AgentState, kind: ThingKind, rng: var Rand): Thing =
  ## Find nearest thing using spiral search pattern - more systematic than random search
  # First check immediate area around current position
  result = findNearestThing(env, state.lastSearchPosition, kind)
  if result != nil:
    return result

  # Also check around agent's current position before advancing spiral
  result = findNearestThing(env, state.basePosition, kind)
  if result != nil:
    return result

  # If not found, advance spiral search only every few calls to reduce dithering
  let nextSearchPos = getNextSpiralPoint(state, rng)
  state.lastSearchPosition = nextSearchPos

  # Search from new spiral position
  result = findNearestThing(env, nextSearchPos, kind)
  return result

proc findNearestFriendlyThingSpiral(env: Environment, state: var AgentState, teamId: int,
                                    kind: ThingKind, rng: var Rand): Thing =
  ## Find nearest team-owned thing using spiral search pattern
  result = findNearestFriendlyThing(env, state.lastSearchPosition, teamId, kind)
  if result != nil:
    return result

  result = findNearestFriendlyThing(env, state.basePosition, teamId, kind)
  if result != nil:
    return result

  let nextSearchPos = getNextSpiralPoint(state, rng)
  state.lastSearchPosition = nextSearchPos
  result = findNearestFriendlyThing(env, nextSearchPos, teamId, kind)
  return result

proc findNearestTerrain(env: Environment, pos: IVec2, terrain: TerrainType): IVec2 =
  result = ivec2(-1, -1)
  var minDist = 999999
  for x in max(0, pos.x - 20)..<min(MapWidth, pos.x + 21):
    for y in max(0, pos.y - 20)..<min(MapHeight, pos.y + 21):
      if env.terrain[x][y] == terrain:
        let terrainPos = ivec2(x.int32, y.int32)
        let dist = abs(terrainPos.x - pos.x) + abs(terrainPos.y - pos.y)
        if dist < minDist:
          minDist = dist
          result = terrainPos

proc hasFoodCargo(agent: Thing): bool =
  for key, count in agent.inventory.pairs:
    if count > 0 and isFoodItem(key):
      return true
  false

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

proc countNearbyTrees*(env: Environment, center: IVec2, radius: int): int =
  countNearbyTerrain(env, center, radius, {TerrainType.Pine, TerrainType.Palm})

proc hasFriendlyBuildingNearby*(env: Environment, teamId: int, kind: ThingKind,
                                center: IVec2, radius: int): bool =
  for thing in env.things:
    if thing.kind != kind:
      continue
    if thing.teamId != teamId:
      continue
    if max(abs(thing.pos.x - center.x), abs(thing.pos.y - center.y)) <= radius:
      return true
  false

proc findDropoffBuilding*(env: Environment, state: var AgentState, teamId: int,
                          res: StockpileResource, rng: var Rand): Thing =
  template tryKind(kind: ThingKind): Thing =
    env.findNearestFriendlyThingSpiral(state, teamId, kind, rng)
  case res
  of ResourceFood:
    result = tryKind(Granary)
    if result == nil:
      result = tryKind(TownCenter)
    if result == nil:
      result = tryKind(Mill)
  of ResourceWood:
    result = tryKind(LumberCamp)
    if result == nil:
      result = tryKind(TownCenter)
  of ResourceStone:
    result = tryKind(Quarry)
    if result == nil:
      result = tryKind(TownCenter)
  of ResourceGold:
    result = tryKind(MiningCamp)
    if result == nil:
      result = tryKind(TownCenter)
  of ResourceWater, ResourceNone:
    result = nil

proc dropoffResourceIfCarrying*(controller: Controller, env: Environment, agent: Thing,
                                agentId: int, state: var AgentState,
                                res: StockpileResource, amount: int): tuple[did: bool, action: uint8] =
  if amount <= 0:
    return (false, 0'u8)
  let teamId = getTeamId(agent.agentId)
  let dropoff = findDropoffBuilding(env, state, teamId, res, controller.rng)
  if dropoff != nil:
    return (true, controller.useOrMove(env, agent, agentId, state, dropoff.pos))
  (false, 0'u8)

proc dropoffFoodIfCarrying*(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): tuple[did: bool, action: uint8] =
  if not hasFoodCargo(agent):
    return (false, 0'u8)
  let teamId = getTeamId(agent.agentId)
  let dropoff = findDropoffBuilding(env, state, teamId, ResourceFood, controller.rng)
  if dropoff != nil:
    return (true, controller.useOrMove(env, agent, agentId, state, dropoff.pos))
  (false, 0'u8)

proc teamPopCount*(env: Environment, teamId: int): int =
  for agent in env.agents:
    if not isAgentAlive(env, agent):
      continue
    if getTeamId(agent.agentId) == teamId:
      inc result

proc teamPopCap*(env: Environment, teamId: int): int =
  for thing in env.things:
    if thing.isNil:
      continue
    if thing.teamId != teamId:
      continue
    if isBuildingKind(thing.kind):
      let cap = buildingPopCap(thing.kind)
      if cap > 0:
        result += cap

proc countTeamBuildings*(env: Environment, teamId: int, kind: ThingKind): int =
  for thing in env.things:
    if thing.isNil:
      continue
    if thing.kind == kind and thing.teamId == teamId:
      inc result

proc canAffordBuild*(env: Environment, teamId: int, key: ItemKey): bool =
  let costs = buildCostsForKey(key)
  if costs.len == 0:
    return false
  env.canSpendStockpile(teamId, costs)


proc findNearestEmpty(env: Environment, pos: IVec2, fertileNeeded: bool, maxRadius: int = 8): IVec2 =
  ## Find nearest empty, non-water tile matching fertile flag
  result = ivec2(-1, -1)
  var minDist = 999999
  let startX = max(0, pos.x - maxRadius)
  let endX = min(MapWidth - 1, pos.x + maxRadius)
  let startY = max(0, pos.y - maxRadius)
  let endY = min(MapHeight - 1, pos.y + maxRadius)
  for x in startX..endX:
    for y in startY..endY:
      let terrainOk = if fertileNeeded: env.terrain[x][y] == TerrainType.Fertile else: env.terrain[x][y] == TerrainType.Empty
      if terrainOk and env.isEmpty(ivec2(x, y)) and env.doorTeams[x][y] < 0:
        let dist = abs(x - pos.x) + abs(y - pos.y)
        if dist < minDist:
          minDist = dist
          result = ivec2(x.int32, y.int32)

proc findNearestTerrainSpiral(env: Environment, state: var AgentState, terrain: TerrainType, rng: var Rand): IVec2 =
  ## Find terrain using spiral search pattern
  # First check from current spiral search position
  result = findNearestTerrain(env, state.lastSearchPosition, terrain)
  if result.x >= 0:
    return result

  # Also check around agent's current position before advancing spiral
  result = findNearestTerrain(env, state.basePosition, terrain)
  if result.x >= 0:
    return result

  # If not found, advance spiral search
  let nextSearchPos = getNextSpiralPoint(state, rng)
  state.lastSearchPosition = nextSearchPos

  # Search from new spiral position
  result = findNearestTerrain(env, nextSearchPos, terrain)
  return result

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

proc chebyshevDist(a, b: IVec2): int32 =
  let dx = abs(a.x - b.x)
  let dy = abs(a.y - b.y)
  return (if dx > dy: dx else: dy)

proc isValidEmptyTile(env: Environment, agent: Thing, pos: IVec2): bool =
  pos.x >= 0 and pos.x < MapWidth and pos.y >= 0 and pos.y < MapHeight and
  env.isEmpty(pos) and not isBlockedTerrain(env.terrain[pos.x][pos.y]) and env.canAgentPassDoor(agent, pos)

proc spearAttackDir(agentPos: IVec2, targetPos: IVec2): int {.inline.} =
  ## Pick an orientation whose spear wedge covers the target (matches attackAction pattern).
  var bestDir = -1
  var bestStep = int.high
  for dirIdx in 0 .. 7:
    let d = getOrientationDelta(Orientation(dirIdx))
    let left = ivec2(-d.y, d.x)
    let right = ivec2(d.y, -d.x)
    for step in 1 .. 3:
      let forward = agentPos + ivec2(d.x * step, d.y * step)
      if forward == targetPos or forward + left == targetPos or forward + right == targetPos:
        if step < bestStep:
          bestStep = step
          bestDir = dirIdx
        break
  return bestDir

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
        if target == nil:
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
      let dirIdx = spearAttackDir(agent.pos, thing.pos)
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
    if occupant == nil:
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

type NeedType = enum
  NeedArmor
  NeedBread
  NeedSpear

proc findNearestTeammateNeeding(env: Environment, me: Thing, need: NeedType): Thing =
  var best: Thing = nil
  var bestDist = int.high
  for other in env.agents:
    if other.agentId == me.agentId: continue
    if not isAgentAlive(env, other): continue
    if not sameTeam(me, other): continue
    var needs = false
    case need
    of NeedArmor:
      needs = other.inventoryArmor == 0
    of NeedBread:
      needs = other.inventoryBread < 1
    of NeedSpear:
      needs = other.unitClass == UnitManAtArms and other.inventorySpear == 0
    if not needs: continue
    let d = int(chebyshevDist(me.pos, other.pos))
    if d < bestDist:
      bestDist = d
      best = other
  return best

proc isPassable(env: Environment, agent: Thing, pos: IVec2): bool =
  ## Consider lantern tiles passable for movement planning and respect doors/water.
  if not isValidPos(pos):
    return false
  if isBlockedTerrain(env.terrain[pos.x][pos.y]):
    return false
  if not env.canAgentPassDoor(agent, pos):
    return false
  let occupant = env.grid[pos.x][pos.y]
  if occupant == nil:
    return true
  return occupant.kind == Lantern

proc nextStepToward(env: Environment, agent: Thing, fromPos, targetPos: IVec2): int =
  ## A* for the next step toward a target, falling back to -1 if no path found.
  let directions = [
    ivec2(0, -1),  # 0: North
    ivec2(0, 1),   # 1: South
    ivec2(-1, 0),  # 2: West
    ivec2(1, 0),   # 3: East
    ivec2(-1, -1), # 4: NW
    ivec2(1, -1),  # 5: NE
    ivec2(-1, 1),  # 6: SW
    ivec2(1, 1)    # 7: SE
  ]

  # Determine goal tiles: target if passable, otherwise any passable neighbor.
  var goals: seq[IVec2] = @[]
  if isPassable(env, agent, targetPos):
    goals.add(targetPos)
  else:
    for d in directions:
      let candidate = targetPos + d
      if isValidPos(candidate) and isPassable(env, agent, candidate):
        goals.add(candidate)

  if goals.len == 0:
    return -1
  for g in goals:
    if g == fromPos:
      return -1

  proc heuristic(loc: IVec2): int =
    var best = int.high
    for g in goals:
      let d = int(chebyshevDist(loc, g))
      if d < best:
        best = d
    return best

  proc reconstructPath(cameFrom: Table[IVec2, IVec2], current: IVec2): seq[IVec2] =
    var cur = current
    result = @[cur]
    var cf = cameFrom
    while cf.hasKey(cur):
      cur = cf[cur]
      result.add(cur)
    result.reverse()

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
      return -1

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
      return -1

    for g in goals:
      if current == g:
        let path = reconstructPath(cameFrom, current)
        if path.len >= 2:
          return neighborDirIndex(path[0], path[1])
        return -1

    openSet.excl(current)
    inc explored

    for dirIdx in 0 .. 7:
      let nextPos = current + directions[dirIdx]
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

  return -1

proc getMoveTowards(env: Environment, agent: Thing, fromPos, toPos: IVec2, rng: var Rand): int =
  ## Get a movement direction towards target, with obstacle avoidance
  let clampedTarget = clampToPlayable(toPos)
  if clampedTarget == fromPos:
    # Target is outside playable bounds; push back inward toward the widest margin.
    let directions = [
      ivec2(0, -1),  # 0: North
      ivec2(0, 1),   # 1: South
      ivec2(-1, 0),  # 2: West
      ivec2(1, 0),   # 3: East
      ivec2(-1, -1), # 4: NW
      ivec2(1, -1),  # 5: NE
      ivec2(-1, 1),  # 6: SW
      ivec2(1, 1)    # 7: SE
    ]
    var bestDir = -1
    var bestMargin = -1
    for idx, d in directions:
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

  let pathDir = nextStepToward(env, agent, fromPos, clampedTarget)
  if pathDir >= 0:
    return pathDir

  let primaryDir = getCardinalDirIndex(fromPos, clampedTarget)

  # Try primary direction first
  let directions = [
    ivec2(0, -1),  # 0: North
    ivec2(0, 1),   # 1: South
    ivec2(-1, 0),  # 2: West
    ivec2(1, 0),   # 3: East
    ivec2(-1, -1), # 4: NW
    ivec2(1, -1),  # 5: NE
    ivec2(-1, 1),  # 6: SW
    ivec2(1, 1)    # 7: SE
  ]

  let primaryMove = fromPos + directions[primaryDir]
  if isPassable(env, agent, primaryMove):
    return primaryDir

  # Primary blocked, try adjacent directions
  let alternatives = case primaryDir:
    of 0: @[5, 4, 1, 3, 2]  # North blocked, try NE, NW, South, East, West
    of 1: @[7, 6, 0, 3, 2]  # South blocked, try SE, SW, North, East, West
    of 2: @[4, 6, 3, 0, 1]  # West blocked, try NW, SW, East, North, South
    of 3: @[5, 7, 2, 0, 1]  # East blocked, try NE, SE, West, North, South
    else: @[0, 1, 2, 3]     # Diagonal blocked, try cardinals

  for altDir in alternatives:
    let altMove = fromPos + directions[altDir]
    if isPassable(env, agent, altMove):
      return altDir

  # All blocked, try random movement
  return randIntInclusive(rng, 0, 3)

proc tryPlantOnFertile(controller: Controller, env: Environment, agent: Thing,
                       agentId: int, state: var AgentState): tuple[did: bool, action: uint8] =
  ## If carrying wood/wheat and a fertile tile is nearby, plant; otherwise move toward it.
  if agent.inventoryWheat > 0 or agent.inventoryWood > 0:
    let fertilePos = findNearestEmpty(env, agent.pos, true)
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

proc useOrMove(controller: Controller, env: Environment, agent: Thing, agentId: int,
               state: var AgentState, targetPos: IVec2): uint8 =
  let dx = abs(targetPos.x - agent.pos.x)
  let dy = abs(targetPos.y - agent.pos.y)
  if max(dx, dy) == 1'i32:
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(3'u8, neighborDirIndex(agent.pos, targetPos).uint8))
  return saveStateAndReturn(controller, agentId, state,
    encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, targetPos, controller.rng).uint8))

proc useOrMoveToTerrain(controller: Controller, env: Environment, agent: Thing, agentId: int,
                        state: var AgentState, terrainPos: IVec2): uint8 =
  let dx = abs(terrainPos.x - agent.pos.x)
  let dy = abs(terrainPos.y - agent.pos.y)
  if max(dx, dy) == 1'i32:
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(3'u8, neighborDirIndex(agent.pos, terrainPos).uint8))

  var best = ivec2(-1, -1)
  var bestDist = int.high
  for oy in -1 .. 1:
    for ox in -1 .. 1:
      if ox == 0 and oy == 0:
        continue
      let candidate = terrainPos + ivec2(ox.int32, oy.int32)
      if not isValidPos(candidate):
        continue
      if not isPassable(env, agent, candidate):
        continue
      let dist = abs(candidate.x - agent.pos.x) + abs(candidate.y - agent.pos.y)
      if dist < bestDist:
        bestDist = dist
        best = candidate
  if best.x >= 0:
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, best, controller.rng).uint8))

  return controller.moveNextSearch(env, agent, agentId, state)

proc attackOrMove(controller: Controller, env: Environment, agent: Thing, agentId: int,
                  state: var AgentState, targetPos: IVec2): uint8 =
  let dx = abs(targetPos.x - agent.pos.x)
  let dy = abs(targetPos.y - agent.pos.y)
  if max(dx, dy) == 1'i32:
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(2'u8, neighborDirIndex(agent.pos, targetPos).uint8))
  return saveStateAndReturn(controller, agentId, state,
    encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, targetPos, controller.rng).uint8))

proc attackOrMoveToTerrain(controller: Controller, env: Environment, agent: Thing, agentId: int,
                           state: var AgentState, terrainPos: IVec2): uint8 =
  let dx = abs(terrainPos.x - agent.pos.x)
  let dy = abs(terrainPos.y - agent.pos.y)
  if max(dx, dy) == 1'i32:
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(2'u8, neighborDirIndex(agent.pos, terrainPos).uint8))

  var best = ivec2(-1, -1)
  var bestDist = int.high
  for oy in -1 .. 1:
    for ox in -1 .. 1:
      if ox == 0 and oy == 0:
        continue
      let candidate = terrainPos + ivec2(ox.int32, oy.int32)
      if not isValidPos(candidate):
        continue
      if not isPassable(env, agent, candidate):
        continue
      let dist = abs(candidate.x - agent.pos.x) + abs(candidate.y - agent.pos.y)
      if dist < bestDist:
        bestDist = dist
        best = candidate
  if best.x >= 0:
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, best, controller.rng).uint8))

  return controller.moveNextSearch(env, agent, agentId, state)

proc findAndHarvest(controller: Controller, env: Environment, agent: Thing, agentId: int,
                    state: var AgentState, terrain: TerrainType): tuple[did: bool, action: uint8] =
  let pos = env.findNearestTerrainSpiral(state, terrain, controller.rng)
  if pos.x >= 0:
    return (true, controller.useOrMoveToTerrain(env, agent, agentId, state, pos))
  (false, 0'u8)

proc dropoffCarrying(controller: Controller, env: Environment, agent: Thing, agentId: int,
                     state: var AgentState, allowWood, allowStone, allowGold: bool): tuple[did: bool, action: uint8] =
  let teamId = getTeamId(agent.agentId)
  if allowWood and agent.inventoryWood > 0:
    var dropoff = env.findNearestFriendlyThingSpiral(state, teamId, LumberCamp, controller.rng)
    if dropoff == nil:
      dropoff = env.findNearestFriendlyThingSpiral(state, teamId, LumberYard, controller.rng)
    if dropoff == nil:
      dropoff = env.findNearestFriendlyThingSpiral(state, teamId, TownCenter, controller.rng)
    if dropoff != nil:
      return (true, controller.useOrMove(env, agent, agentId, state, dropoff.pos))

  if allowGold and agent.inventoryGold > 0:
    var dropoff = env.findNearestFriendlyThingSpiral(state, teamId, MiningCamp, controller.rng)
    if dropoff == nil:
      dropoff = env.findNearestFriendlyThingSpiral(state, teamId, Bank, controller.rng)
    if dropoff == nil:
      dropoff = env.findNearestFriendlyThingSpiral(state, teamId, TownCenter, controller.rng)
    if dropoff != nil:
      return (true, controller.useOrMove(env, agent, agentId, state, dropoff.pos))

  if allowStone and agent.inventoryStone > 0:
    var dropoff = env.findNearestFriendlyThingSpiral(state, teamId, MiningCamp, controller.rng)
    if dropoff == nil:
      dropoff = env.findNearestFriendlyThingSpiral(state, teamId, Quarry, controller.rng)
    if dropoff == nil:
      dropoff = env.findNearestFriendlyThingSpiral(state, teamId, TownCenter, controller.rng)
    if dropoff != nil:
      return (true, controller.useOrMove(env, agent, agentId, state, dropoff.pos))

  (false, 0'u8)

proc ensureWood(controller: Controller, env: Environment, agent: Thing, agentId: int,
                state: var AgentState): tuple[did: bool, action: uint8] =
  let stump = env.findNearestThingSpiral(state, Stump, controller.rng)
  if stump != nil:
    return (true, controller.useOrMove(env, agent, agentId, state, stump.pos))
  let pinePos = env.findNearestTerrainSpiral(state, Pine, controller.rng)
  if pinePos.x >= 0:
    return (true, controller.attackOrMoveToTerrain(env, agent, agentId, state, pinePos))
  let palmPos = env.findNearestTerrainSpiral(state, Palm, controller.rng)
  if palmPos.x >= 0:
    return (true, controller.attackOrMoveToTerrain(env, agent, agentId, state, palmPos))
  (true, controller.moveNextSearch(env, agent, agentId, state))

proc ensureStone(controller: Controller, env: Environment, agent: Thing, agentId: int,
                 state: var AgentState): tuple[did: bool, action: uint8] =
  let (didStone, actStone) = controller.findAndHarvest(env, agent, agentId, state, Stone)
  if didStone: return (didStone, actStone)
  let (didStalag, actStalag) = controller.findAndHarvest(env, agent, agentId, state, Stalagmite)
  if didStalag: return (didStalag, actStalag)
  (true, controller.moveNextSearch(env, agent, agentId, state))

proc ensureGold(controller: Controller, env: Environment, agent: Thing, agentId: int,
                state: var AgentState): tuple[did: bool, action: uint8] =
  let goldPos = env.findNearestTerrainSpiral(state, Gold, controller.rng)
  if goldPos.x >= 0:
    return (true, controller.useOrMoveToTerrain(env, agent, agentId, state, goldPos))
  (true, controller.moveNextSearch(env, agent, agentId, state))
