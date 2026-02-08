## Shared type definitions and option framework for the AI system.
## This module is imported by all other AI modules to avoid circular dependencies.

import std/heapqueue
import vmath
import ../entropy
import ../types
import ../environment

export IVec2, Rand, types, heapqueue, environment

const
  MaxPathNodes* = 512     # Slightly more than 250 exploration limit
  MaxPathLength* = 256    # Max reconstructed path length
  MaxPathGoals* = 10      # Max goal positions (8 neighbors + direct)
  # Shared threat map configuration
  MaxThreatEntries* = 64  # Max threats tracked per team
  # Damaged building cache
  MaxDamagedBuildingsPerTeam* = 32  # Max damaged buildings tracked per team

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

  ## Heap node for A* priority queue (ordered by f-score, lower = higher priority)
  PathHeapNode* = object
    fScore*: int32
    pos*: IVec2

  ## Pre-allocated pathfinding scratch space to avoid per-call allocations.
  ## Uses generation counters for O(1) validity checks without clearing arrays.
  PathfindingCache* = object
    generation*: int32
    # Generation-stamped closed set for skipping already-processed nodes
    closedGen*: array[MapWidth, array[MapHeight, int32]]
    # Generation-stamped gScore values
    gScoreGen*: array[MapWidth, array[MapHeight, int32]]
    gScoreVal*: array[MapWidth, array[MapHeight, int32]]
    # Generation-stamped cameFrom for path reconstruction
    cameFromGen*: array[MapWidth, array[MapHeight, int32]]
    cameFromVal*: array[MapWidth, array[MapHeight, IVec2]]
    # Binary heap priority queue for open set (O(log n) push/pop)
    openHeap*: HeapQueue[PathHeapNode]
    # Goals array
    goals*: array[MaxPathGoals, IVec2]
    goalsLen*: int
    # Result path buffer
    path*: array[MaxPathLength, IVec2]
    pathLen*: int

proc `<`*(a, b: PathHeapNode): bool =
  ## Comparison for min-heap ordering (lower f-score = higher priority)
  a.fScore < b.fScore

type
  # Meta roles with focused responsibilities (AoE-style)
  AgentRole* = enum
    Gatherer   # Dynamic resource gatherer (food/wood/stone/gold + hearts)
    Builder    # Builds structures and expands the base
    Fighter    # Combat & hunting
    Scripted   # Evolutionary/scripted role

  GathererTask* = enum
    TaskFood
    TaskWood
    TaskStone
    TaskGold
    TaskHearts

  # Minimal state tracking with spiral search
  AgentState* = object
    role*: AgentRole
    roleId*: int
    activeOptionId*: int
    activeOptionTicks*: int
    gathererTask*: GathererTask
    fighterEnemyAgentId*: int
    fighterEnemyStep*: int
    # Spiral search state
    spiralStepsInArc*: int
    spiralArcsCompleted*: int
    spiralClockwise*: bool
    basePosition*: IVec2
    lastSearchPosition*: IVec2
    # Bail-out / anti-oscillation state
    lastPosition*: IVec2
    recentPositions*: array[12, IVec2]
    recentPosIndex*: int
    recentPosCount*: int
    escapeMode*: bool
    escapeStepsRemaining*: int
    escapeDirection*: IVec2
    lastActionVerb*: int
    lastActionArg*: int
    blockedMoveDir*: int
    blockedMoveSteps*: int
    cachedThingPos*: array[ThingKind, IVec2]
    cachedThingStep*: array[ThingKind, int]  # Step when cache was set (staleness detection)
    cachedWaterPos*: IVec2
    cachedWaterStep*: int  # Step when water cache was set
    closestFoodPos*: IVec2
    closestWoodPos*: IVec2
    closestStonePos*: IVec2
    closestGoldPos*: IVec2
    closestWaterPos*: IVec2
    closestMagmaPos*: IVec2
    buildTarget*: IVec2
    buildStand*: IVec2
    buildIndex*: int
    buildLockSteps*: int
    plannedTarget*: IVec2
    plannedPath*: seq[IVec2]
    plannedPathIndex*: int
    pathBlockedTarget*: IVec2
    # Patrol state
    patrolPoint1*: IVec2      # First patrol waypoint
    patrolPoint2*: IVec2      # Second patrol waypoint
    patrolToSecondPoint*: bool # True = heading to point2, False = heading to point1
    patrolActive*: bool       # Whether patrol mode is enabled
    # Attack-move state: move to destination, attack enemies along the way
    attackMoveTarget*: IVec2  # Destination for attack-move (-1,-1 = inactive)
    # Scout state: exploration and enemy detection
    scoutExploreRadius*: int32    # Current exploration radius from base
    scoutLastEnemySeenStep*: int32  # Step when scout last saw an enemy (for alarm)
    scoutActive*: bool            # Whether scout mode is enabled
    # Hold position state: stay at location, attack but don't chase
    holdPositionActive*: bool         # Whether hold position is enabled
    holdPositionTarget*: IVec2        # Position to hold (-1,-1 = inactive)
    # Follow state: follow another agent maintaining proximity
    followTargetAgentId*: int         # Target agent to follow (-1 = inactive)
    followActive*: bool               # Whether follow mode is enabled
    # Stop state: agent is stopped and idle until new command or threshold expires
    stoppedActive*: bool              # Whether agent is currently stopped
    stoppedUntilStep*: int32          # Step at which stopped state expires

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
    agents*: array[MapAgents, AgentState]
    agentsInitialized*: array[MapAgents, bool]
    buildingCountsStep*: int
    buildingCounts*: array[MapRoomObjectsTeams, array[ThingKind, int]]
    claimedBuildings*: array[MapRoomObjectsTeams, set[ThingKind]]  # Buildings claimed by builders this step
    teamPopCountsStep*: int  # Step at which teamPopCounts was last computed
    teamPopCounts*: array[MapRoomObjectsTeams, int]  # Cached per-team alive agent counts
    pathCache*: PathfindingCache  # Pre-allocated pathfinding scratch space
    threatMaps*: array[MapRoomObjectsTeams, ThreatMap]  # Shared threat awareness per team
    # Difficulty system - per-team configuration
    difficulty*: array[MapRoomObjectsTeams, DifficultyConfig]
    # Per-step cache for isThreateningAlly results to avoid redundant spatial scans
    # Cache is invalidated when step changes; stores -1=uncached, 0=false, 1=true
    allyThreatCacheStep*: array[MapRoomObjectsTeams, int]
    allyThreatCache*: array[MapRoomObjectsTeams, array[MapAgents, int8]]
    # Per-step cache for damaged buildings - avoids redundant O(n) scans
    damagedBuildingCacheStep*: int
    damagedBuildingPositions*: array[MapRoomObjectsTeams, array[MaxDamagedBuildingsPerTeam, IVec2]]
    damagedBuildingCounts*: array[MapRoomObjectsTeams, int]
    # Fog of war optimization: track last position where fog was revealed per agent
    # Skip redundant fog updates when agent hasn't moved
    fogLastRevealPos*: array[MapAgents, IVec2]
    fogLastRevealStep*: array[MapAgents, int32]
    # Town split cooldown: tracks last step when each team triggered a split
    townSplitLastStep*: array[MapRoomObjectsTeams, int32]
    # Town bell auto-trigger: last step when each team's bell was auto-checked
    townBellAutoCheckStep*: array[MapRoomObjectsTeams, int32]

proc defaultDifficultyConfig*(level: DifficultyLevel): DifficultyConfig =
  ## Create a default difficulty configuration for the given level.
  ## Easy: High delay (30%), limited intelligence
  ## Normal: Moderate delay (10%), most features enabled
  ## Hard: Low delay (2%), all features enabled
  ## Brutal: No delay, all features, aggressive behavior
  result = DifficultyConfig(level: level, adaptive: false, adaptiveTarget: 0.5, lastAdaptiveCheck: 0)
  case level
  of DiffEasy:
    result.decisionDelayChance = 0.30
  of DiffNormal:
    result.decisionDelayChance = 0.10
    result.threatResponseEnabled = true
    result.coordinationEnabled = true
    result.optimalBuildOrderEnabled = true
  of DiffHard:
    result.decisionDelayChance = 0.02
    result.threatResponseEnabled = true
    result.advancedTargetingEnabled = true
    result.coordinationEnabled = true
    result.optimalBuildOrderEnabled = true
  of DiffBrutal:
    result.threatResponseEnabled = true
    result.advancedTargetingEnabled = true
    result.coordinationEnabled = true
    result.optimalBuildOrderEnabled = true

proc newController*(seed: int): Controller =
  result = Controller(
    rng: initRand(seed),
    buildingCountsStep: -1,
    teamPopCountsStep: -1,
    damagedBuildingCacheStep: -1
  )
  # Initialize all teams to Normal difficulty by default
  for teamId in 0 ..< MapRoomObjectsTeams:
    result.difficulty[teamId] = defaultDifficultyConfig(DiffNormal)
  # Initialize fog tracking - set invalid positions so first update always runs
  for agentId in 0 ..< MapAgents:
    result.fogLastRevealPos[agentId] = ivec2(-1, -1)
    result.fogLastRevealStep[agentId] = 0

# -----------------------------------------------------------------------------
# Option framework (consolidated from ai_options.nim)
# -----------------------------------------------------------------------------

type
  OptionDef* = object
    name*: string
    canStart*: proc(controller: Controller, env: Environment, agent: Thing,
                    agentId: int, state: var AgentState): bool
    shouldTerminate*: proc(controller: Controller, env: Environment, agent: Thing,
                           agentId: int, state: var AgentState): bool
    act*: proc(controller: Controller, env: Environment, agent: Thing,
               agentId: int, state: var AgentState): uint8
    interruptible*: bool

proc optionsAlwaysCanStart*(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): bool =
  true

proc optionsAlwaysTerminate*(controller: Controller, env: Environment, agent: Thing,
                             agentId: int, state: var AgentState): bool =
  true

template resetActiveOption(state: var AgentState) =
  state.activeOptionId = -1
  state.activeOptionTicks = 0

proc runOptions*(controller: Controller, env: Environment, agent: Thing,
                 agentId: int, state: var AgentState,
                 roleOptions: openArray[OptionDef]): uint8 =
  ## Execute the RL-style options framework.
  ## Handles active option continuation, preemption by higher-priority options,
  ## and scanning for new options when none is active.
  let optionCount = roleOptions.len
  # Handle active option first (if any).
  if state.activeOptionId in 0 ..< optionCount:
    let activeIdx = state.activeOptionId
    if roleOptions[activeIdx].interruptible:
      for i in 0 ..< activeIdx:
        if roleOptions[i].canStart(controller, env, agent, agentId, state):
          state.activeOptionId = i
          state.activeOptionTicks = 0
          break
    inc state.activeOptionTicks
    let action = roleOptions[state.activeOptionId].act(
      controller, env, agent, agentId, state)
    if action != 0'u8:
      if roleOptions[state.activeOptionId].shouldTerminate(
          controller, env, agent, agentId, state):
        resetActiveOption(state)
      return action
    resetActiveOption(state)

  # Otherwise, scan options in priority order and use the first that acts.
  for i, opt in roleOptions:
    if not opt.canStart(controller, env, agent, agentId, state):
      continue
    state.activeOptionId = i
    state.activeOptionTicks = 1
    let action = opt.act(controller, env, agent, agentId, state)
    if action != 0'u8:
      if opt.shouldTerminate(controller, env, agent, agentId, state):
        resetActiveOption(state)
      return action
    resetActiveOption(state)

  return 0'u8

template optionGuard*(canName, termName: untyped, body: untyped) {.dirty.} =
  ## Generate a canStart/shouldTerminate pair from a single boolean expression.
  ## shouldTerminate is the logical negation of canStart.
  ## Shared template used by gatherer, builder, and fighter options.
  proc canName(controller: Controller, env: Environment, agent: Thing,
               agentId: int, state: var AgentState): bool = body
  proc termName(controller: Controller, env: Environment, agent: Thing,
                agentId: int, state: var AgentState): bool = not (body)
