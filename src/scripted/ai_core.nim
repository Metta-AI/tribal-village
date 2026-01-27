# This file is included by src/agent_control.nim
## Simplified AI system - clean and efficient
## Replaces the 1200+ line complex system with ~150 lines
import std/[tables, sets]
import ../entropy
import vmath
import ../environment, ../common, ../terrain

const
  MaxPathNodes* = 512     # Slightly more than 250 exploration limit
  MaxPathLength* = 256    # Max reconstructed path length
  MaxPathGoals* = 10      # Max goal positions (8 neighbors + direct)
  # Shared threat map configuration
  MaxThreatEntries* = 64  # Max threats tracked per team
  ThreatDecaySteps* = 50  # Steps before threat decays
  ThreatVisionRange* = 12 # Range to detect threats

type
  ## Shared threat map entry for team coordination
  ThreatEntry* = object
    pos*: IVec2           # Position where threat was seen
    strength*: int32      # Estimated threat strength (1 = single enemy)
    lastSeen*: int32      # Step when threat was last observed
    agentId*: int32       # ID of enemy agent (-1 if structure)
    isStructure*: bool    # True if threat is a building

  ## Shared threat map for a team - tracks enemy positions seen by any agent
  ThreatMap* = object
    entries*: array[MaxThreatEntries, ThreatEntry]
    count*: int32
    lastUpdateStep*: int32

  ## Pre-allocated pathfinding scratch space to avoid per-call allocations.
  ## Uses generation counters for O(1) validity checks without clearing arrays.
  PathfindingCache* = object
    generation: int32
    # Generation-stamped membership for O(1) open set lookup
    inOpenSetGen: array[MapWidth, array[MapHeight, int32]]
    # Generation-stamped gScore values
    gScoreGen: array[MapWidth, array[MapHeight, int32]]
    gScoreVal: array[MapWidth, array[MapHeight, int32]]
    # Generation-stamped cameFrom for path reconstruction
    cameFromGen: array[MapWidth, array[MapHeight, int32]]
    cameFromVal: array[MapWidth, array[MapHeight, IVec2]]
    # Open set array for iteration (with active flags for removal)
    openSet: array[MaxPathNodes, IVec2]
    openSetLen: int
    openSetActive: array[MaxPathNodes, bool]
    # Goals array
    goals: array[MaxPathGoals, IVec2]
    goalsLen: int
    # Result path buffer
    path: array[MaxPathLength, IVec2]
    pathLen: int

  # Meta roles with focused responsibilities (AoE-style)
  AgentRole* = enum
    Gatherer   # Dynamic resource gatherer (food/wood/stone/gold + hearts)
    Builder    # Builds structures and expands the base
    Fighter    # Combat & hunting
    Scripted   # Evolutionary/scripted role

  GathererTask = enum
    TaskFood
    TaskWood
    TaskStone
    TaskGold
    TaskHearts

  # Minimal state tracking with spiral search
  AgentState = object
    role: AgentRole
    roleId: int
    activeOptionId: int
    activeOptionTicks: int
    gathererTask: GathererTask
    fighterEnemyAgentId: int
    fighterEnemyStep: int
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
    lastActionVerb: int
    lastActionArg: int
    blockedMoveDir: int
    blockedMoveSteps: int
    cachedThingPos: array[ThingKind, IVec2]
    cachedWaterPos: IVec2
    closestFoodPos: IVec2
    closestWoodPos: IVec2
    closestStonePos: IVec2
    closestGoldPos: IVec2
    closestWaterPos: IVec2
    closestMagmaPos: IVec2
    buildTarget: IVec2
    buildStand: IVec2
    buildIndex: int
    buildLockSteps: int
    plannedTarget: IVec2
    plannedPath: seq[IVec2]
    plannedPathIndex: int
    pathBlockedTarget: IVec2
    # Patrol state
    patrolPoint1: IVec2      # First patrol waypoint
    patrolPoint2: IVec2      # Second patrol waypoint
    patrolToSecondPoint: bool # True = heading to point2, False = heading to point1
    patrolActive: bool       # Whether patrol mode is enabled
    # Attack-move state: move to destination, attack enemies along the way
    attackMoveTarget: IVec2  # Destination for attack-move (-1,-1 = inactive)

  # Difficulty levels for AI - affects decision quality and reaction time
  DifficultyLevel* = enum
    DiffEasy     # High delay, limited intelligence
    DiffNormal   # Moderate delay, most features enabled
    DiffHard     # Low delay, all features enabled
    DiffBrutal   # No delay, all features, aggressive behavior

  # Per-team difficulty configuration
  DifficultyConfig* = object
    level*: DifficultyLevel
    # Decision delay: probability of returning NOOP to simulate thinking time
    decisionDelayChance*: float32
    # Feature toggles - disable advanced behaviors on lower difficulties
    threatResponseEnabled*: bool     # Use shared threat map intelligence
    advancedTargetingEnabled*: bool  # Use smart enemy selection (priority scoring)
    coordinationEnabled*: bool       # Use inter-role coordination system
    optimalBuildOrderEnabled*: bool  # Place buildings in optimal locations
    # Adaptive mode - adjusts difficulty based on performance
    adaptive*: bool
    adaptiveTarget*: float32         # Target territory % (0.5 = balanced)
    lastAdaptiveCheck*: int32        # Step when difficulty was last adjusted

  # Simple controller
  Controller* = ref object
    rng*: Rand
    agents: array[MapAgents, AgentState]
    agentsInitialized: array[MapAgents, bool]
    buildingCountsStep: int
    buildingCounts: array[MapRoomObjectsTeams, array[ThingKind, int]]
    claimedBuildings: array[MapRoomObjectsTeams, set[ThingKind]]  # Buildings claimed by builders this step
    pathCache*: PathfindingCache  # Pre-allocated pathfinding scratch space
    threatMaps*: array[MapRoomObjectsTeams, ThreatMap]  # Shared threat awareness per team
    # Difficulty system - per-team configuration
    difficulty*: array[MapRoomObjectsTeams, DifficultyConfig]

proc defaultDifficultyConfig*(level: DifficultyLevel): DifficultyConfig =
  ## Create a default difficulty configuration for the given level.
  ## Easy: High delay (30%), limited intelligence
  ## Normal: Moderate delay (10%), most features enabled
  ## Hard: Low delay (2%), all features enabled
  ## Brutal: No delay, all features, aggressive behavior
  case level
  of DiffEasy:
    result = DifficultyConfig(
      level: DiffEasy,
      decisionDelayChance: 0.30,
      threatResponseEnabled: false,
      advancedTargetingEnabled: false,
      coordinationEnabled: false,
      optimalBuildOrderEnabled: false,
      adaptive: false,
      adaptiveTarget: 0.5,
      lastAdaptiveCheck: 0
    )
  of DiffNormal:
    result = DifficultyConfig(
      level: DiffNormal,
      decisionDelayChance: 0.10,
      threatResponseEnabled: true,
      advancedTargetingEnabled: false,
      coordinationEnabled: true,
      optimalBuildOrderEnabled: true,
      adaptive: false,
      adaptiveTarget: 0.5,
      lastAdaptiveCheck: 0
    )
  of DiffHard:
    result = DifficultyConfig(
      level: DiffHard,
      decisionDelayChance: 0.02,
      threatResponseEnabled: true,
      advancedTargetingEnabled: true,
      coordinationEnabled: true,
      optimalBuildOrderEnabled: true,
      adaptive: false,
      adaptiveTarget: 0.5,
      lastAdaptiveCheck: 0
    )
  of DiffBrutal:
    result = DifficultyConfig(
      level: DiffBrutal,
      decisionDelayChance: 0.0,
      threatResponseEnabled: true,
      advancedTargetingEnabled: true,
      coordinationEnabled: true,
      optimalBuildOrderEnabled: true,
      adaptive: false,
      adaptiveTarget: 0.5,
      lastAdaptiveCheck: 0
    )

proc newController*(seed: int): Controller =
  result = Controller(
    rng: initRand(seed),
    buildingCountsStep: -1
  )
  # Initialize all teams to Normal difficulty by default
  for teamId in 0 ..< MapRoomObjectsTeams:
    result.difficulty[teamId] = defaultDifficultyConfig(DiffNormal)

proc getDifficulty*(controller: Controller, teamId: int): DifficultyConfig =
  ## Get the difficulty configuration for a team.
  if teamId >= 0 and teamId < MapRoomObjectsTeams:
    return controller.difficulty[teamId]
  return defaultDifficultyConfig(DiffNormal)

proc setDifficulty*(controller: Controller, teamId: int, level: DifficultyLevel) =
  ## Set the difficulty level for a team.
  if teamId >= 0 and teamId < MapRoomObjectsTeams:
    controller.difficulty[teamId] = defaultDifficultyConfig(level)

proc setDifficultyConfig*(controller: Controller, teamId: int, config: DifficultyConfig) =
  ## Set a custom difficulty configuration for a team.
  if teamId >= 0 and teamId < MapRoomObjectsTeams:
    controller.difficulty[teamId] = config

proc enableAdaptiveDifficulty*(controller: Controller, teamId: int, targetTerritory: float32 = 0.5) =
  ## Enable adaptive difficulty for a team. The AI will adjust its difficulty
  ## based on territory control compared to the target percentage.
  if teamId >= 0 and teamId < MapRoomObjectsTeams:
    controller.difficulty[teamId].adaptive = true
    controller.difficulty[teamId].adaptiveTarget = targetTerritory

proc disableAdaptiveDifficulty*(controller: Controller, teamId: int) =
  ## Disable adaptive difficulty for a team.
  if teamId >= 0 and teamId < MapRoomObjectsTeams:
    controller.difficulty[teamId].adaptive = false

proc shouldApplyDecisionDelay*(controller: Controller, teamId: int): bool =
  ## Check if the AI should apply a decision delay (return NOOP) based on difficulty.
  ## Returns true with probability equal to decisionDelayChance.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false
  let chance = controller.difficulty[teamId].decisionDelayChance
  if chance <= 0.0:
    return false
  randChance(controller.rng, chance)

const
  AdaptiveCheckInterval* = 500  # Check every 500 steps

proc updateAdaptiveDifficulty*(controller: Controller, env: Environment) =
  ## Update difficulty levels for teams with adaptive mode enabled.
  ## Adjusts difficulty up if team is doing too well, down if struggling.
  ## Called periodically from updateController.
  let currentStep = env.currentStep.int32
  let score = env.scoreTerritory()
  let totalTiles = max(1, score.scoredTiles)

  for teamId in 0 ..< MapRoomObjectsTeams:
    if not controller.difficulty[teamId].adaptive:
      continue
    # Only check periodically
    let lastCheck = controller.difficulty[teamId].lastAdaptiveCheck
    if currentStep - lastCheck < AdaptiveCheckInterval:
      continue

    controller.difficulty[teamId].lastAdaptiveCheck = currentStep
    let teamTiles = score.teamTiles[teamId]
    let territoryRatio = float32(teamTiles) / float32(totalTiles)
    let target = controller.difficulty[teamId].adaptiveTarget
    let currentLevel = controller.difficulty[teamId].level

    # Adjust difficulty based on performance vs target
    # If team is doing much better than target (>20% above), increase difficulty
    # If team is doing much worse than target (>20% below), decrease difficulty
    const Threshold = 0.15

    if territoryRatio > target + Threshold:
      # Team is doing too well - increase difficulty
      let newLevel = case currentLevel
        of DiffEasy: DiffNormal
        of DiffNormal: DiffHard
        of DiffHard: DiffBrutal
        of DiffBrutal: DiffBrutal
      if newLevel != currentLevel:
        let adaptive = controller.difficulty[teamId].adaptive
        let adaptiveTarget = controller.difficulty[teamId].adaptiveTarget
        controller.difficulty[teamId] = defaultDifficultyConfig(newLevel)
        controller.difficulty[teamId].adaptive = adaptive
        controller.difficulty[teamId].adaptiveTarget = adaptiveTarget
        controller.difficulty[teamId].lastAdaptiveCheck = currentStep

    elif territoryRatio < target - Threshold:
      # Team is struggling - decrease difficulty
      let newLevel = case currentLevel
        of DiffEasy: DiffEasy
        of DiffNormal: DiffEasy
        of DiffHard: DiffNormal
        of DiffBrutal: DiffHard
      if newLevel != currentLevel:
        let adaptive = controller.difficulty[teamId].adaptive
        let adaptiveTarget = controller.difficulty[teamId].adaptiveTarget
        controller.difficulty[teamId] = defaultDifficultyConfig(newLevel)
        controller.difficulty[teamId].adaptive = adaptive
        controller.difficulty[teamId].adaptiveTarget = adaptiveTarget
        controller.difficulty[teamId].lastAdaptiveCheck = currentStep

proc getAgentRole*(controller: Controller, agentId: int): AgentRole =
  ## Get the role of an agent (for profiling)
  if agentId >= 0 and agentId < MapAgents and controller.agentsInitialized[agentId]:
    return controller.agents[agentId].role
  return Gatherer  # Default

proc isAgentInitialized*(controller: Controller, agentId: int): bool =
  ## Check if an agent has been initialized (for profiling)
  if agentId >= 0 and agentId < MapAgents:
    return controller.agentsInitialized[agentId]
  return false

# Helper proc to save state and return action
proc saveStateAndReturn(controller: Controller, agentId: int, state: AgentState, action: uint8): uint8 =
  var nextState = state
  nextState.lastActionVerb = action.int div ActionArgumentCount
  nextState.lastActionArg = action.int mod ActionArgumentCount
  controller.agents[agentId] = nextState
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

proc chebyshevDist*(a, b: IVec2): int32 =
  let dx = abs(a.x - b.x)
  let dy = abs(a.y - b.y)
  return (if dx > dy: dx else: dy)

# ============================================================================
# Shared Threat Map Functions
# ============================================================================

proc decayThreats*(controller: Controller, teamId: int, currentStep: int32) =
  ## Remove threats that haven't been seen recently
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  var map = addr controller.threatMaps[teamId]
  var writeIdx = 0
  for readIdx in 0 ..< map.count:
    let age = currentStep - map.entries[readIdx].lastSeen
    if age < ThreatDecaySteps:
      if writeIdx != readIdx:
        map.entries[writeIdx] = map.entries[readIdx]
      inc writeIdx
  map.count = writeIdx.int32
  map.lastUpdateStep = currentStep

proc reportThreat*(controller: Controller, teamId: int, pos: IVec2,
                   strength: int32, currentStep: int32,
                   agentId: int32 = -1, isStructure: bool = false) =
  ## Report a threat position to the team's shared threat map.
  ## Called by any agent that spots an enemy.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  var map = addr controller.threatMaps[teamId]

  # Check if threat already exists at this position or for this agent
  for i in 0 ..< map.count:
    let entry = addr map.entries[i]
    # Update existing entry if same position or same enemy agent
    if (entry.pos == pos) or (agentId >= 0 and entry.agentId == agentId):
      entry.pos = pos
      entry.strength = max(entry.strength, strength)
      entry.lastSeen = currentStep
      entry.agentId = agentId
      entry.isStructure = isStructure
      return

  # Add new threat if space available
  if map.count < MaxThreatEntries:
    map.entries[map.count] = ThreatEntry(
      pos: pos,
      strength: strength,
      lastSeen: currentStep,
      agentId: agentId,
      isStructure: isStructure
    )
    inc map.count

proc getNearestThreat*(controller: Controller, teamId: int, pos: IVec2,
                       currentStep: int32): tuple[pos: IVec2, dist: int32, found: bool] =
  ## Get the nearest known threat to a position.
  ## Returns the threat position and distance, or found=false if none.
  result = (pos: ivec2(-1, -1), dist: int32.high, found: false)
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  let map = addr controller.threatMaps[teamId]
  for i in 0 ..< map.count:
    let entry = map.entries[i]
    let age = currentStep - entry.lastSeen
    if age >= ThreatDecaySteps:
      continue  # Skip stale threats
    let dist = chebyshevDist(pos, entry.pos)
    if dist < result.dist:
      result = (pos: entry.pos, dist: dist, found: true)

proc getThreatsInRange*(controller: Controller, teamId: int, pos: IVec2,
                        rangeVal: int32, currentStep: int32): seq[ThreatEntry] =
  ## Get all known threats within range of a position.
  result = @[]
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  let map = addr controller.threatMaps[teamId]
  for i in 0 ..< map.count:
    let entry = map.entries[i]
    let age = currentStep - entry.lastSeen
    if age >= ThreatDecaySteps:
      continue  # Skip stale threats
    let dist = chebyshevDist(pos, entry.pos)
    if dist <= rangeVal:
      result.add entry

proc getTotalThreatStrength*(controller: Controller, teamId: int, pos: IVec2,
                              rangeVal: int32, currentStep: int32): int32 =
  ## Get the total threat strength within range of a position.
  result = 0
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  let map = addr controller.threatMaps[teamId]
  for i in 0 ..< map.count:
    let entry = map.entries[i]
    let age = currentStep - entry.lastSeen
    if age >= ThreatDecaySteps:
      continue
    let dist = chebyshevDist(pos, entry.pos)
    if dist <= rangeVal:
      result += entry.strength

proc hasKnownThreats*(controller: Controller, teamId: int, currentStep: int32): bool =
  ## Check if team has any known (non-stale) threats
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false
  let map = addr controller.threatMaps[teamId]
  for i in 0 ..< map.count:
    let age = currentStep - map.entries[i].lastSeen
    if age < ThreatDecaySteps:
      return true
  false

proc clearThreatMap*(controller: Controller, teamId: int) =
  ## Clear all threats for a team (e.g., at episode reset)
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  controller.threatMaps[teamId].count = 0
  controller.threatMaps[teamId].lastUpdateStep = 0

proc updateThreatMapFromVision*(controller: Controller, env: Environment,
                                 agent: Thing, currentStep: int32) =
  ## Scan agent's vision range and report any enemies to the team threat map.
  ## Called each tick for each agent to share threat intelligence.
  let teamId = getTeamId(agent)
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return

  # Scan for enemy agents within vision range
  for other in env.agents:
    if not isAgentAlive(env, other):
      continue
    let otherTeam = getTeamId(other)
    if otherTeam == teamId or otherTeam < 0:
      continue  # Skip allies and neutral
    let dist = chebyshevDist(agent.pos, other.pos)
    if dist <= ThreatVisionRange:
      # Calculate threat strength based on unit class
      var strength: int32 = 1
      case other.unitClass
      of UnitKnight: strength = 3
      of UnitManAtArms: strength = 2
      of UnitArcher: strength = 2
      of UnitMangonel: strength = 4
      of UnitMonk: strength = 1
      else: strength = 1
      controller.reportThreat(teamId, other.pos, strength, currentStep,
                              agentId = other.agentId.int32, isStructure = false)

  # Scan for enemy structures within vision range
  for thing in env.things:
    if thing.isNil or not isBuildingKind(thing.kind):
      continue
    if thing.teamId < 0 or thing.teamId == teamId:
      continue  # Skip neutral and friendly
    let dist = chebyshevDist(agent.pos, thing.pos)
    if dist <= ThreatVisionRange:
      # Calculate threat strength based on building type
      var strength: int32 = 1
      case thing.kind
      of Castle: strength = 5
      of GuardTower: strength = 3
      of Barracks, ArcheryRange, Stable: strength = 2
      else: strength = 1
      controller.reportThreat(teamId, thing.pos, strength, currentStep,
                              agentId = -1, isStructure = true)

# ============================================================================
# End Shared Threat Map Functions
# ============================================================================

proc updateClosestSeen(state: var AgentState, basePos: IVec2, candidate: IVec2, current: var IVec2) =
  if candidate.x < 0:
    return
  if current.x < 0:
    current = candidate
    return
  if chebyshevDist(candidate, basePos) < chebyshevDist(current, basePos):
    current = candidate

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

const
  SearchRadius = 50
  SpiralAdvanceSteps = 3
proc clampToPlayable(pos: IVec2): IVec2 {.inline.} =
  ## Keep positions inside the playable area (inside border walls).
  result.x = min(MapWidth - MapBorder - 1, max(MapBorder, pos.x))
  result.y = min(MapHeight - MapBorder - 1, max(MapBorder, pos.y))

proc getNextSpiralPoint(state: var AgentState): IVec2 =
  ## Advance the spiral one step using incremental state.
  let clockwise = state.spiralClockwise
  let arcLen = (state.spiralArcsCompleted div 2) + 1
  var direction = state.spiralArcsCompleted mod 4
  if not clockwise:
    case direction
    of 1: direction = 3
    of 3: direction = 1
    else: discard
  let delta = case direction
    of 0: ivec2(0, -1)  # North
    of 1: ivec2(1, 0)   # East
    of 2: ivec2(0, 1)   # South
    else: ivec2(-1, 0)  # West

  let nextPos = clampToPlayable(state.lastSearchPosition + delta)
  state.lastSearchPosition = nextPos
  state.spiralStepsInArc += 1
  if state.spiralStepsInArc > arcLen:
    state.spiralArcsCompleted += 1
    state.spiralStepsInArc = 1
    if state.spiralArcsCompleted > 100:
      state.spiralArcsCompleted = 0
      state.spiralStepsInArc = 1
      # Continue from the current area.
      state.basePosition = state.lastSearchPosition
  result = state.lastSearchPosition

proc findNearestThing(env: Environment, pos: IVec2, kind: ThingKind,
                      maxDist: int = SearchRadius): Thing =
  ## Find nearest thing of a kind using spatial index for O(1) cell lookup
  findNearestThingSpatial(env, pos, kind, maxDist)

proc radiusBounds*(center: IVec2, radius: int): tuple[startX, endX, startY, endY: int] {.inline.} =
  let cx = center.x.int
  let cy = center.y.int
  (max(0, cx - radius), min(MapWidth - 1, cx + radius),
   max(0, cy - radius), min(MapHeight - 1, cy + radius))

proc findNearestWater(env: Environment, pos: IVec2): IVec2 =
  result = ivec2(-1, -1)
  let (startX, endX, startY, endY) = radiusBounds(pos, SearchRadius)
  let cx = pos.x.int
  let cy = pos.y.int
  var minDist = int.high
  for x in startX .. endX:
    for y in startY .. endY:
      if abs(x - cx) + abs(y - cy) >= SearchRadius:
        continue
      if env.terrain[x][y] != Water:
        continue
      let pos = ivec2(x.int32, y.int32)
      if isTileFrozen(pos, env):
        continue
      let dist = abs(x - cx) + abs(y - cy)
      if dist < minDist:
        minDist = dist
        result = pos

proc findNearestFriendlyThing(env: Environment, pos: IVec2, teamId: int, kind: ThingKind): Thing =
  ## Find nearest team-owned thing using spatial index for O(1) cell lookup
  findNearestFriendlyThingSpatial(env, pos, teamId, kind, SearchRadius)

proc findNearestThingSpiral(env: Environment, state: var AgentState, kind: ThingKind): Thing =
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

  # If not found, advance spiral search (multiple steps) to cover ground faster
  var nextSearchPos = state.lastSearchPosition
  for _ in 0 ..< SpiralAdvanceSteps:
    nextSearchPos = getNextSpiralPoint(state)

  # Search from new spiral position
  result = findNearestThing(env, nextSearchPos, kind)
  if not isNil(result):
    state.cachedThingPos[kind] = result.pos
  return result

proc findNearestWaterSpiral(env: Environment, state: var AgentState): IVec2 =
  let cachedPos = state.cachedWaterPos
  if cachedPos.x >= 0:
    if abs(cachedPos.x - state.lastSearchPosition.x) + abs(cachedPos.y - state.lastSearchPosition.y) < 30:
      if env.terrain[cachedPos.x][cachedPos.y] == Water and not isTileFrozen(cachedPos, env):
        return cachedPos
    state.cachedWaterPos = ivec2(-1, -1)

  result = findNearestWater(env, state.lastSearchPosition)
  if result.x >= 0:
    state.cachedWaterPos = result
    return result

  result = findNearestWater(env, state.basePosition)
  if result.x >= 0:
    state.cachedWaterPos = result
    return result

  var nextSearchPos = state.lastSearchPosition
  for _ in 0 ..< SpiralAdvanceSteps:
    nextSearchPos = getNextSpiralPoint(state)
  result = findNearestWater(env, nextSearchPos)
  if result.x >= 0:
    state.cachedWaterPos = result
  return result

proc findNearestFriendlyThingSpiral(env: Environment, state: var AgentState, teamId: int,
                                    kind: ThingKind): Thing =
  ## Find nearest team-owned thing using spiral search pattern
  result = findNearestFriendlyThing(env, state.lastSearchPosition, teamId, kind)
  if not isNil(result):
    return result

  result = findNearestFriendlyThing(env, state.basePosition, teamId, kind)
  if not isNil(result):
    return result

  var nextSearchPos = state.lastSearchPosition
  for _ in 0 ..< SpiralAdvanceSteps:
    nextSearchPos = getNextSpiralPoint(state)
  result = findNearestFriendlyThing(env, nextSearchPos, teamId, kind)
  return result

template forNearbyCells(center: IVec2, radius: int, body: untyped) =
  let cx {.inject.} = center.x.int
  let cy {.inject.} = center.y.int
  let startX {.inject.} = max(0, cx - radius)
  let endX {.inject.} = min(MapWidth - 1, cx + radius)
  let startY {.inject.} = max(0, cy - radius)
  let endY {.inject.} = min(MapHeight - 1, cy + radius)
  for x {.inject.} in startX..endX:
    for y {.inject.} in startY..endY:
      if max(abs(x - cx), abs(y - cy)) > radius:
        continue
      body

proc countNearbyTerrain*(env: Environment, center: IVec2, radius: int,
                         allowed: set[TerrainType]): int =
  forNearbyCells(center, radius):
    if env.terrain[x][y] in allowed:
      inc result

proc countNearbyThings*(env: Environment, center: IVec2, radius: int,
                        allowed: set[ThingKind]): int =
  forNearbyCells(center, radius):
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

proc getBuildingCount*(controller: Controller, env: Environment, teamId: int, kind: ThingKind): int =
  if controller.buildingCountsStep != env.currentStep:
    controller.buildingCountsStep = env.currentStep
    controller.buildingCounts = default(array[MapRoomObjectsTeams, array[ThingKind, int]])
    # Clear claimed buildings at start of new step - claims are per-step to prevent
    # multiple builders from trying to build the same building type in the same step
    controller.claimedBuildings = default(array[MapRoomObjectsTeams, set[ThingKind]])
    for thing in env.things:
      if thing.isNil:
        continue
      if not isBuildingKind(thing.kind):
        continue
      if thing.teamId < 0 or thing.teamId >= MapRoomObjectsTeams:
        continue
      controller.buildingCounts[thing.teamId][thing.kind] += 1
  controller.buildingCounts[teamId][kind]

proc isBuildingClaimed*(controller: Controller, teamId: int, kind: ThingKind): bool =
  ## Check if a building type is claimed by another builder this step.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false
  kind in controller.claimedBuildings[teamId]

proc claimBuilding*(controller: Controller, teamId: int, kind: ThingKind) =
  ## Claim a building type so other builders don't try to build the same thing.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  controller.claimedBuildings[teamId].incl(kind)

proc canAffordBuild*(env: Environment, agent: Thing, key: ItemKey): bool =
  let costs = buildCostsForKey(key)
  choosePayment(env, agent, costs) != PayNone


proc neighborDirIndex(fromPos, toPos: IVec2): int =
  ## Orientation index (0..7) toward adjacent target (includes diagonals)
  let dx = toPos.x - fromPos.x
  let dy = toPos.y - fromPos.y
  return vecToOrientation(ivec2(
    (if dx > 0: 1'i32 elif dx < 0: -1'i32 else: 0'i32).int,
    (if dy > 0: 1'i32 elif dy < 0: -1'i32 else: 0'i32).int
  ))


proc sameTeam(agentA, agentB: Thing): bool =
  getTeamId(agentA) == getTeamId(agentB)

proc getBasePos*(agent: Thing): IVec2 =
  ## Return the agent's home altar position if valid, otherwise the agent's current position.
  if agent.homeAltar.x >= 0: agent.homeAltar else: agent.pos

proc findAttackOpportunity(env: Environment, agent: Thing): int =
  ## Return attack orientation index if a valid target is in reach, else -1.
  ## Simplified: pick the closest aligned target within range using a priority order.
  ## Respects agent stance: StanceNoAttack disables auto-attacking.
  if agent.unitClass == UnitMonk:
    return -1
  # NoAttack stance never auto-attacks
  if agent.stance == StanceNoAttack:
    return -1

  let maxRange = case agent.unitClass
    of UnitArcher: ArcherBaseRange
    of UnitMangonel: MangonelAoELength
    else:
      if agent.inventorySpear > 0: 2 else: 1

  proc targetPriority(kind: ThingKind): int =
    if agent.unitClass == UnitMangonel:
      if kind in AttackableStructures:
        return 0
      case kind
      of Tumor: 1
      of Spawner: 2
      of Agent: 3
      else: 4
    else:
      case kind
      of Tumor: 0
      of Spawner: 1
      of Agent: 2
      else:
        if kind in AttackableStructures: 3 else: 4

  var bestDir = -1
  var bestDist = int.high
  var bestPriority = int.high

  for thing in env.things:
    if thing.kind == Agent:
      if not isAgentAlive(env, thing):
        continue
      if sameTeam(agent, thing):
        continue
    elif thing.kind in {Tumor, Spawner}:
      discard
    elif thing.kind in AttackableStructures:
      if thing.teamId == getTeamId(agent):
        continue
    else:
      continue

    if not isValidPos(thing.pos):
      continue
    let placed = if thingBlocksMovement(thing.kind):
      env.grid[thing.pos.x][thing.pos.y]
    else:
      env.backgroundGrid[thing.pos.x][thing.pos.y]
    if placed != thing:
      continue

    let dx = thing.pos.x - agent.pos.x
    let dy = thing.pos.y - agent.pos.y
    if not (dx == 0 or dy == 0 or abs(dx) == abs(dy)):
      continue
    let dist = int(chebyshevDist(agent.pos, thing.pos))
    if dist > maxRange:
      continue

    let dir = vecToOrientation(ivec2(signi(dx), signi(dy)))
    let priority = targetPriority(thing.kind)
    if priority < bestPriority or (priority == bestPriority and dist < bestDist):
      bestPriority = priority
      bestDist = dist
      bestDir = dir

  return bestDir

proc isPassable(env: Environment, agent: Thing, pos: IVec2): bool =
  ## Consider lantern tiles passable for generic checks and respect doors/water.
  if not isValidPos(pos):
    return false
  if env.isWaterBlockedForAgent(agent, pos):
    return false
  if not env.canAgentPassDoor(agent, pos):
    return false
  let occupant = env.grid[pos.x][pos.y]
  if isNil(occupant):
    return true
  return occupant.kind == Lantern

proc canEnterForMove(env: Environment, agent: Thing, fromPos, toPos: IVec2): bool =
  ## Directional passability check that mirrors move logic (lantern pushing rules).
  if not isValidPos(toPos):
    return false
  if toPos.x < MapBorder.int32 or toPos.x >= (MapWidth - MapBorder).int32 or
      toPos.y < MapBorder.int32 or toPos.y >= (MapHeight - MapBorder).int32:
    return false
  if not env.canTraverseElevation(fromPos, toPos):
    return false
  if env.isWaterBlockedForAgent(agent, toPos):
    return false
  if not env.canAgentPassDoor(agent, toPos):
    return false
  if env.isEmpty(toPos):
    return true
  let blocker = env.getThing(toPos)
  if isNil(blocker) or blocker.kind != Lantern:
    return false

  template spacingOk(nextPos: IVec2): bool =
    var ok = true
    for t in env.thingsByKind[Lantern]:
      if t != blocker:
        let dist = max(abs(t.pos.x - nextPos.x), abs(t.pos.y - nextPos.y))
        if dist < 3'i32:
          ok = false
          break
    ok

  let delta = toPos - fromPos
  let ahead1 = ivec2(toPos.x + delta.x, toPos.y + delta.y)
  let ahead2 = ivec2(toPos.x + delta.x * 2, toPos.y + delta.y * 2)
  if isValidPos(ahead2) and env.isEmpty(ahead2) and not env.hasDoor(ahead2) and
      not env.isWaterBlockedForAgent(agent, ahead2) and spacingOk(ahead2):
    return true
  if isValidPos(ahead1) and env.isEmpty(ahead1) and not env.hasDoor(ahead1) and
      not env.isWaterBlockedForAgent(agent, ahead1) and spacingOk(ahead1):
    return true

  for dy in -1 .. 1:
    for dx in -1 .. 1:
      if dx == 0 and dy == 0:
        continue
      let alt = ivec2(toPos.x + dx, toPos.y + dy)
      if not isValidPos(alt):
        continue
      if env.isEmpty(alt) and not env.hasDoor(alt) and
          not env.isWaterBlockedForAgent(agent, alt) and spacingOk(alt):
        return true
  return false

proc getMoveTowards(env: Environment, agent: Thing, fromPos, toPos: IVec2,
                    rng: var Rand, avoidDir: int = -1): int =
  ## Get a movement direction towards target, with obstacle avoidance
  let clampedTarget = clampToPlayable(toPos)
  if clampedTarget == fromPos:
    # Target is outside playable bounds; push back inward toward the widest margin.
    var bestDir = -1
    var bestMargin = -1
    var avoidCandidate = -1
    for idx, d in Directions8:
      let np = fromPos + d
      if not canEnterForMove(env, agent, fromPos, np):
        continue
      if idx == avoidDir:
        avoidCandidate = idx
        continue
      let marginX = min(np.x - MapBorder, (MapWidth - MapBorder - 1) - np.x)
      let marginY = min(np.y - MapBorder, (MapHeight - MapBorder - 1) - np.y)
      let margin = min(marginX, marginY)
      if margin > bestMargin:
        bestMargin = margin
        bestDir = idx
    if bestDir >= 0:
      return bestDir
    if avoidCandidate >= 0:
      return avoidCandidate
    return -1

  let dx = clampedTarget.x - fromPos.x
  let dy = clampedTarget.y - fromPos.y
  let step = ivec2(signi(dx), signi(dy))
  if step.x != 0 or step.y != 0:
    let primaryDir = vecToOrientation(step)
    let primaryMove = fromPos + Directions8[primaryDir]
    if primaryDir != avoidDir and canEnterForMove(env, agent, fromPos, primaryMove):
      return primaryDir

  var bestDir = -1
  var bestDist = int.high
  var avoidCandidate = -1
  for idx, d in Directions8:
    let np = fromPos + d
    if not canEnterForMove(env, agent, fromPos, np):
      continue
    if idx == avoidDir:
      avoidCandidate = idx
      continue
    let dist = int(chebyshevDist(np, clampedTarget))
    if dist < bestDist:
      bestDist = dist
      bestDir = idx
  if bestDir >= 0:
    return bestDir
  if avoidCandidate >= 0:
    return avoidCandidate

  # All blocked - return -1 to signal no valid move (caller should noop)
  return -1

proc findPath(controller: Controller, env: Environment, agent: Thing, fromPos, targetPos: IVec2): seq[IVec2] =
  ## A* path from start to target (or passable neighbor), returns path including start.
  ## Uses pre-allocated cache to avoid per-call allocations.

  # Increment generation for this call - makes all previous data stale
  inc controller.pathCache.generation
  let gen = controller.pathCache.generation

  # Build goals list (target or passable neighbors)
  controller.pathCache.goalsLen = 0
  if isPassable(env, agent, targetPos):
    controller.pathCache.goals[0] = targetPos
    controller.pathCache.goalsLen = 1
  else:
    for d in Directions8:
      let candidate = targetPos + d
      if isValidPos(candidate) and isPassable(env, agent, candidate):
        if controller.pathCache.goalsLen < MaxPathGoals:
          controller.pathCache.goals[controller.pathCache.goalsLen] = candidate
          inc controller.pathCache.goalsLen

  if controller.pathCache.goalsLen == 0:
    return @[]

  # Check if already at goal
  for i in 0 ..< controller.pathCache.goalsLen:
    if controller.pathCache.goals[i] == fromPos:
      return @[fromPos]

  # Heuristic: minimum chebyshev distance to any goal
  proc heuristic(cache: PathfindingCache, loc: IVec2): int32 =
    var best = int32.high
    for i in 0 ..< cache.goalsLen:
      let d = int32(chebyshevDist(loc, cache.goals[i]))
      if d < best:
        best = d
    best

  # Initialize open set with starting position
  controller.pathCache.openSetLen = 1
  controller.pathCache.openSet[0] = fromPos
  controller.pathCache.openSetActive[0] = true
  controller.pathCache.inOpenSetGen[fromPos.x][fromPos.y] = gen

  # Initialize gScore and fScore for start
  controller.pathCache.gScoreGen[fromPos.x][fromPos.y] = gen
  controller.pathCache.gScoreVal[fromPos.x][fromPos.y] = 0
  let startH = heuristic(controller.pathCache, fromPos)

  var explored = 0
  while true:
    if explored > 250:
      return @[]

    # Find node in open set with lowest fScore
    var currentIdx = -1
    var current: IVec2
    var bestF = int32.high
    for i in 0 ..< controller.pathCache.openSetLen:
      if not controller.pathCache.openSetActive[i]:
        continue
      let n = controller.pathCache.openSet[i]
      # Calculate fScore: gScore + heuristic
      let g = controller.pathCache.gScoreVal[n.x][n.y]
      let h = heuristic(controller.pathCache, n)
      let f = g + h
      if f < bestF:
        bestF = f
        current = n
        currentIdx = i

    if currentIdx < 0:
      return @[]  # Open set is empty

    # Check if current is a goal
    for i in 0 ..< controller.pathCache.goalsLen:
      if current == controller.pathCache.goals[i]:
        # Reconstruct path
        controller.pathCache.pathLen = 0
        var cur = current
        while true:
          if controller.pathCache.pathLen >= MaxPathLength:
            break
          controller.pathCache.path[controller.pathCache.pathLen] = cur
          inc controller.pathCache.pathLen
          # Check if we have a parent
          if controller.pathCache.cameFromGen[cur.x][cur.y] != gen:
            break
          cur = controller.pathCache.cameFromVal[cur.x][cur.y]

        # Build result seq in correct order (path is reversed)
        result = newSeq[IVec2](controller.pathCache.pathLen)
        for j in 0 ..< controller.pathCache.pathLen:
          result[j] = controller.pathCache.path[controller.pathCache.pathLen - 1 - j]
        return result

    # Remove current from open set
    controller.pathCache.openSetActive[currentIdx] = false
    inc explored

    # Explore neighbors
    for dirIdx in 0 .. 7:
      let nextPos = current + Directions8[dirIdx]
      if not isValidPos(nextPos):
        continue
      if not canEnterForMove(env, agent, current, nextPos):
        continue

      # Get current gScore (or int32.high if not visited)
      let currentG = controller.pathCache.gScoreVal[current.x][current.y]
      let tentativeG = currentG + 1

      # Get neighbor's current gScore
      let neighborHasScore = controller.pathCache.gScoreGen[nextPos.x][nextPos.y] == gen
      let nextG = if neighborHasScore: controller.pathCache.gScoreVal[nextPos.x][nextPos.y] else: int32.high

      if tentativeG < nextG:
        # Update cameFrom
        controller.pathCache.cameFromGen[nextPos.x][nextPos.y] = gen
        controller.pathCache.cameFromVal[nextPos.x][nextPos.y] = current
        # Update gScore
        controller.pathCache.gScoreGen[nextPos.x][nextPos.y] = gen
        controller.pathCache.gScoreVal[nextPos.x][nextPos.y] = tentativeG
        # Add to open set if not already there
        if controller.pathCache.inOpenSetGen[nextPos.x][nextPos.y] != gen:
          if controller.pathCache.openSetLen < MaxPathNodes:
            controller.pathCache.openSet[controller.pathCache.openSetLen] = nextPos
            controller.pathCache.openSetActive[controller.pathCache.openSetLen] = true
            inc controller.pathCache.openSetLen
            controller.pathCache.inOpenSetGen[nextPos.x][nextPos.y] = gen

  @[]

proc hasTeamLanternNear(env: Environment, teamId: int, pos: IVec2): bool =
  for thing in env.things:
    if thing.kind != Lantern:
      continue
    if not thing.lanternHealthy or thing.teamId != teamId:
      continue
    if max(abs(thing.pos.x - pos.x), abs(thing.pos.y - pos.y)) < 3'i32:
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
        if env.isEmpty(candPos) and isNil(env.getBackgroundThing(candPos)) and not env.hasDoor(candPos):
          let dist = abs(x - ax) + abs(y - ay)
          if dist < minDist:
            minDist = dist
            fertilePos = candPos
    if fertilePos.x >= 0:
      if max(abs(fertilePos.x - agent.pos.x), abs(fertilePos.y - agent.pos.y)) == 1'i32:
        let dirIdx = neighborDirIndex(agent.pos, fertilePos)
        let plantArg = (if agent.inventoryWheat > 0: dirIdx else: dirIdx + 4)
        return (true, saveStateAndReturn(controller, agentId, state,
                 encodeAction(7'u8, plantArg.uint8)))
      else:
        let avoidDir = (if state.blockedMoveSteps > 0: state.blockedMoveDir else: -1)
        let dir = getMoveTowards(env, agent, agent.pos, fertilePos, controller.rng, avoidDir)
        if dir < 0:
          return (false, 0'u8)  # Can't move toward fertile, let other option handle it
        return (true, saveStateAndReturn(controller, agentId, state,
                 encodeAction(1'u8, dir.uint8)))
  return (false, 0'u8)

proc moveNextSearch(controller: Controller, env: Environment, agent: Thing, agentId: int,
                    state: var AgentState): uint8 =
  let dir = getMoveTowards(
    env, agent, agent.pos, getNextSpiralPoint(state),
    controller.rng, (if state.blockedMoveSteps > 0: state.blockedMoveDir else: -1))
  if dir < 0:
    return saveStateAndReturn(controller, agentId, state, 0'u8)  # Noop when blocked
  return saveStateAndReturn(controller, agentId, state, encodeAction(1'u8, dir.uint8))

proc isAdjacent(a, b: IVec2): bool =
  let dx = abs(a.x - b.x)
  let dy = abs(a.y - b.y)
  max(dx, dy) == 1'i32

proc actAt(controller: Controller, env: Environment, agent: Thing, agentId: int,
           state: var AgentState, targetPos: IVec2, verb: uint8,
           argument: int = -1): uint8 =
  return saveStateAndReturn(controller, agentId, state,
    encodeAction(verb,
      (if argument < 0: neighborDirIndex(agent.pos, targetPos) else: argument).uint8))

proc moveTo(controller: Controller, env: Environment, agent: Thing, agentId: int,
            state: var AgentState, targetPos: IVec2): uint8 =
  if state.pathBlockedTarget == targetPos:
    return controller.moveNextSearch(env, agent, agentId, state)
  var stuck = false
  if state.recentPosCount >= 6:
    var uniqueCount = 0
    var unique: array[4, IVec2]
    let historyLen = state.recentPositions.len
    for i in 0 ..< 6:
      let idx = (state.recentPosIndex - 1 - i + historyLen * historyLen) mod historyLen
      let p = state.recentPositions[idx]
      var seen = false
      for j in 0 ..< uniqueCount:
        if unique[j] == p:
          seen = true
          break
      if not seen:
        if uniqueCount < unique.len:
          unique[uniqueCount] = p
          inc uniqueCount
        if uniqueCount > 2:
          break
    stuck = uniqueCount <= 2
  if stuck:
    state.pathBlockedTarget = ivec2(-1, -1)
    state.plannedPath.setLen(0)

  if max(abs(targetPos.x - agent.pos.x), abs(targetPos.y - agent.pos.y)) >= 6'i32 or stuck:
    if state.pathBlockedTarget != targetPos or stuck:
      if state.plannedTarget != targetPos or state.plannedPath.len == 0 or stuck:
        state.plannedPath = findPath(controller, env, agent, agent.pos, targetPos)
        state.plannedTarget = targetPos
        state.plannedPathIndex = 0
      elif state.plannedPathIndex < state.plannedPath.len and
           state.plannedPath[state.plannedPathIndex] != agent.pos:
        state.plannedPath = findPath(controller, env, agent, agent.pos, targetPos)
        state.plannedTarget = targetPos
        state.plannedPathIndex = 0
      if state.plannedPath.len >= 2 and state.plannedPathIndex < state.plannedPath.len - 1:
        let nextPos = state.plannedPath[state.plannedPathIndex + 1]
        if canEnterForMove(env, agent, agent.pos, nextPos):
          var dirIdx = neighborDirIndex(agent.pos, nextPos)
          if state.role == Builder and state.lastPosition == nextPos:
            let altDir = getMoveTowards(env, agent, agent.pos, targetPos, controller.rng, dirIdx)
            if altDir != dirIdx:
              state.plannedPath.setLen(0)
              state.plannedPathIndex = 0
              return saveStateAndReturn(controller, agentId, state,
                encodeAction(1'u8, altDir.uint8))
          state.plannedPathIndex += 1
          return saveStateAndReturn(controller, agentId, state,
            encodeAction(1'u8, dirIdx.uint8))
        state.plannedPath.setLen(0)
        state.pathBlockedTarget = targetPos
        return controller.moveNextSearch(env, agent, agentId, state)
      elif state.plannedPath.len == 0:
        state.pathBlockedTarget = targetPos
        return controller.moveNextSearch(env, agent, agentId, state)
    else:
      state.plannedPath.setLen(0)
  var dirIdx = getMoveTowards(
    env, agent, agent.pos, targetPos, controller.rng,
    (if state.blockedMoveSteps > 0: state.blockedMoveDir else: -1)
  )
  if dirIdx < 0:
    return saveStateAndReturn(controller, agentId, state, 0'u8)  # Noop when blocked
  if state.role == Builder and state.lastPosition == agent.pos + Directions8[dirIdx]:
    let altDir = getMoveTowards(env, agent, agent.pos, targetPos, controller.rng, dirIdx)
    if altDir >= 0 and altDir != dirIdx:
      dirIdx = altDir
  return saveStateAndReturn(controller, agentId, state,
    encodeAction(1'u8, dirIdx.uint8))

proc useAt(controller: Controller, env: Environment, agent: Thing, agentId: int,
           state: var AgentState, targetPos: IVec2): uint8 =
  actAt(controller, env, agent, agentId, state, targetPos, 3'u8)

proc tryMoveToKnownResource(controller: Controller, env: Environment, agent: Thing, agentId: int,
                            state: var AgentState, pos: var IVec2,
                            allowed: set[ThingKind], verb: uint8): tuple[did: bool, action: uint8] =
  if pos.x < 0:
    return (false, 0'u8)
  if pos == state.pathBlockedTarget:
    pos = ivec2(-1, -1)
    return (false, 0'u8)
  let thing = env.getThing(pos)
  if isNil(thing) or thing.kind notin allowed or isThingFrozen(thing, env):
    pos = ivec2(-1, -1)
    return (false, 0'u8)
  return (true, if isAdjacent(agent.pos, pos):
    actAt(controller, env, agent, agentId, state, pos, verb)
  else:
    moveTo(controller, env, agent, agentId, state, pos))

proc moveToNearestSmith(controller: Controller, env: Environment, agent: Thing, agentId: int,
                        state: var AgentState, teamId: int): tuple[did: bool, action: uint8] =
  let smith = env.findNearestFriendlyThingSpiral(state, teamId, Blacksmith)
  if not isNil(smith):
    return (true, if isAdjacent(agent.pos, smith.pos):
      controller.useAt(env, agent, agentId, state, smith.pos)
    else:
      controller.moveTo(env, agent, agentId, state, smith.pos))
  (false, 0'u8)

proc findDropoffBuilding*(env: Environment, state: var AgentState, teamId: int,
                          res: StockpileResource, rng: var Rand): Thing =
  template tryKind(kind: ThingKind): Thing =
    env.findNearestFriendlyThingSpiral(state, teamId, kind)
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

proc dropoffCarrying*(controller: Controller, env: Environment, agent: Thing,
                      agentId: int, state: var AgentState,
                      allowFood: bool = false,
                      allowWood: bool = false,
                      allowStone: bool = false,
                      allowGold: bool = false): tuple[did: bool, action: uint8] =
  ## Unified dropoff function - attempts to drop off resources in priority order
  ## Priority: food -> wood -> gold -> stone
  let teamId = getTeamId(agent)

  # Food dropoff - requires checking inventory for any food items
  if allowFood:
    var hasFood = false
    for key, count in agent.inventory.pairs:
      if count > 0 and isFoodItem(key):
        hasFood = true
        break
    if hasFood:
      let dropoff = findDropoffBuilding(env, state, teamId, ResourceFood, controller.rng)
      if not isNil(dropoff):
        return (true, if isAdjacent(agent.pos, dropoff.pos):
          controller.useAt(env, agent, agentId, state, dropoff.pos)
        else:
          controller.moveTo(env, agent, agentId, state, dropoff.pos))

  # Wood dropoff
  for entry in [
    (res: ResourceWood, amount: agent.inventoryWood, allowed: allowWood),
    (res: ResourceGold, amount: agent.inventoryGold, allowed: allowGold),
    (res: ResourceStone, amount: agent.inventoryStone, allowed: allowStone)
  ]:
    if not entry.allowed or entry.amount <= 0:
      continue
    let dropoff = findDropoffBuilding(env, state, teamId, entry.res, controller.rng)
    if not isNil(dropoff):
      return (true, if isAdjacent(agent.pos, dropoff.pos):
        controller.useAt(env, agent, agentId, state, dropoff.pos)
      else:
        controller.moveTo(env, agent, agentId, state, dropoff.pos))

  (false, 0'u8)

proc ensureWood(controller: Controller, env: Environment, agent: Thing, agentId: int,
                state: var AgentState): tuple[did: bool, action: uint8] =
  let (didKnown, actKnown) = controller.tryMoveToKnownResource(
    env, agent, agentId, state, state.closestWoodPos, {Stump, Tree}, 3'u8)
  if didKnown: return (didKnown, actKnown)
  for kind in [Stump, Tree]:
    let target = env.findNearestThingSpiral(state, kind)
    if isNil(target):
      continue
    if target.pos == state.pathBlockedTarget:
      state.cachedThingPos[kind] = ivec2(-1, -1)
      continue
    updateClosestSeen(state, state.basePosition, target.pos, state.closestWoodPos)
    return (true, if isAdjacent(agent.pos, target.pos):
      controller.useAt(env, agent, agentId, state, target.pos)
    else:
      controller.moveTo(env, agent, agentId, state, target.pos))
  (true, controller.moveNextSearch(env, agent, agentId, state))

proc ensureStone(controller: Controller, env: Environment, agent: Thing, agentId: int,
                 state: var AgentState): tuple[did: bool, action: uint8] =
  let (didKnown, actKnown) = controller.tryMoveToKnownResource(
    env, agent, agentId, state, state.closestStonePos, {Stone, Stalagmite}, 3'u8)
  if didKnown: return (didKnown, actKnown)
  for kind in [Stone, Stalagmite]:
    let target = env.findNearestThingSpiral(state, kind)
    if isNil(target):
      continue
    if target.pos == state.pathBlockedTarget:
      state.cachedThingPos[kind] = ivec2(-1, -1)
      continue
    updateClosestSeen(state, state.basePosition, target.pos, state.closestStonePos)
    return (true, if isAdjacent(agent.pos, target.pos):
      controller.useAt(env, agent, agentId, state, target.pos)
    else:
      controller.moveTo(env, agent, agentId, state, target.pos))
  (true, controller.moveNextSearch(env, agent, agentId, state))

proc ensureGold(controller: Controller, env: Environment, agent: Thing, agentId: int,
                state: var AgentState): tuple[did: bool, action: uint8] =
  let (didKnown, actKnown) = controller.tryMoveToKnownResource(
    env, agent, agentId, state, state.closestGoldPos, {Gold}, 3'u8)
  if didKnown: return (didKnown, actKnown)
  let target = env.findNearestThingSpiral(state, Gold)
  if not isNil(target):
    if target.pos == state.pathBlockedTarget:
      state.cachedThingPos[Gold] = ivec2(-1, -1)
      return (true, controller.moveNextSearch(env, agent, agentId, state))
    updateClosestSeen(state, state.basePosition, target.pos, state.closestGoldPos)
    return (true, if isAdjacent(agent.pos, target.pos):
      controller.useAt(env, agent, agentId, state, target.pos)
    else:
      controller.moveTo(env, agent, agentId, state, target.pos))
  (true, controller.moveNextSearch(env, agent, agentId, state))

proc ensureWater(controller: Controller, env: Environment, agent: Thing, agentId: int,
                 state: var AgentState): tuple[did: bool, action: uint8] =
  if state.closestWaterPos.x >= 0:
    if state.closestWaterPos == state.pathBlockedTarget:
      state.closestWaterPos = ivec2(-1, -1)
    elif env.terrain[state.closestWaterPos.x][state.closestWaterPos.y] != Water or
         isTileFrozen(state.closestWaterPos, env):
      state.closestWaterPos = ivec2(-1, -1)
  if state.closestWaterPos.x >= 0:
    return (true, if isAdjacent(agent.pos, state.closestWaterPos):
      controller.useAt(env, agent, agentId, state, state.closestWaterPos)
    else:
      controller.moveTo(env, agent, agentId, state, state.closestWaterPos))

  let target = findNearestWaterSpiral(env, state)
  if target.x >= 0:
    if target == state.pathBlockedTarget:
      state.cachedWaterPos = ivec2(-1, -1)
      return (true, controller.moveNextSearch(env, agent, agentId, state))
    updateClosestSeen(state, state.basePosition, target, state.closestWaterPos)
    return (true, if isAdjacent(agent.pos, target):
      controller.useAt(env, agent, agentId, state, target)
    else:
      controller.moveTo(env, agent, agentId, state, target))
  (true, controller.moveNextSearch(env, agent, agentId, state))

proc ensureWheat(controller: Controller, env: Environment, agent: Thing, agentId: int,
                 state: var AgentState): tuple[did: bool, action: uint8] =
  for kind in [Wheat, Stubble]:
    let target = env.findNearestThingSpiral(state, kind)
    if isNil(target):
      continue
    if target.pos == state.pathBlockedTarget:
      state.cachedThingPos[kind] = ivec2(-1, -1)
      continue
    return (true, if isAdjacent(agent.pos, target.pos):
      controller.useAt(env, agent, agentId, state, target.pos)
    else:
      controller.moveTo(env, agent, agentId, state, target.pos))
  (true, controller.moveNextSearch(env, agent, agentId, state))

proc ensureHuntFood(controller: Controller, env: Environment, agent: Thing, agentId: int,
                    state: var AgentState): tuple[did: bool, action: uint8] =
  let teamId = getTeamId(agent)
  for kind in [Corpse, Cow, Bush, Fish]:
    let target = env.findNearestThingSpiral(state, kind)
    if isNil(target):
      continue
    if target.pos == state.pathBlockedTarget:
      state.cachedThingPos[kind] = ivec2(-1, -1)
      continue
    updateClosestSeen(state, state.basePosition, target.pos, state.closestFoodPos)
    # For cows: milk (interact) if healthy and food not critical, kill (attack) otherwise
    let verb = if kind == Cow:
      let foodCritical = env.stockpileCount(teamId, ResourceFood) < 3
      let cowHealthy = target.hp * 2 >= target.maxHp
      if cowHealthy and not foodCritical: 3'u8 else: 2'u8
    else:
      3'u8
    return (true, if isAdjacent(agent.pos, target.pos):
      (if verb == 2'u8:
        controller.actAt(env, agent, agentId, state, target.pos, verb)
      else:
        controller.useAt(env, agent, agentId, state, target.pos))
    else:
      controller.moveTo(env, agent, agentId, state, target.pos))
  (true, controller.moveNextSearch(env, agent, agentId, state))

# Patrol behavior helpers
proc setPatrol*(controller: Controller, agentId: int, point1, point2: IVec2) =
  ## Set patrol waypoints for an agent. Enables patrol mode.
  if agentId >= 0 and agentId < MapAgents:
    controller.agents[agentId].patrolPoint1 = point1
    controller.agents[agentId].patrolPoint2 = point2
    controller.agents[agentId].patrolToSecondPoint = true
    controller.agents[agentId].patrolActive = true

proc clearPatrol*(controller: Controller, agentId: int) =
  ## Disable patrol mode for an agent.
  if agentId >= 0 and agentId < MapAgents:
    controller.agents[agentId].patrolActive = false
    controller.agents[agentId].patrolPoint1 = ivec2(-1, -1)
    controller.agents[agentId].patrolPoint2 = ivec2(-1, -1)

proc isPatrolActive*(controller: Controller, agentId: int): bool =
  ## Check if patrol mode is active for an agent.
  if agentId >= 0 and agentId < MapAgents:
    return controller.agents[agentId].patrolActive
  false

proc getPatrolTarget*(controller: Controller, agentId: int): IVec2 =
  ## Get the current patrol target waypoint.
  if agentId >= 0 and agentId < MapAgents:
    let state = controller.agents[agentId]
    if state.patrolToSecondPoint:
      return state.patrolPoint2
    else:
      return state.patrolPoint1
  ivec2(-1, -1)

proc switchPatrolDirection*(controller: Controller, agentId: int) =
  ## Switch patrol direction (toggle between heading to point1 and point2).
  if agentId >= 0 and agentId < MapAgents:
    controller.agents[agentId].patrolToSecondPoint =
      not controller.agents[agentId].patrolToSecondPoint
