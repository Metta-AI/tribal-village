## Shared type definitions for the AI system.
## This module is imported by all other AI modules to avoid circular dependencies.

import vmath
import ../entropy
import ../types

export IVec2, Rand, types

const
  MaxPathNodes* = 512     # Slightly more than 250 exploration limit
  MaxPathLength* = 256    # Max reconstructed path length
  MaxPathGoals* = 10      # Max goal positions (8 neighbors + direct)
  # Shared threat map configuration
  MaxThreatEntries* = 64  # Max threats tracked per team
  ThreatDecaySteps* = 50  # Steps before threat decays
  ThreatVisionRange* = 12 # Range to detect threats
  # Scout-specific vision (AoE2-style extended line of sight)
  ScoutVisionRange* = 18  # Scout extended vision range (50% larger than normal)

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
    generation*: int32
    # Generation-stamped membership for O(1) open set lookup
    inOpenSetGen*: array[MapWidth, array[MapHeight, int32]]
    # Generation-stamped gScore values
    gScoreGen*: array[MapWidth, array[MapHeight, int32]]
    gScoreVal*: array[MapWidth, array[MapHeight, int32]]
    # Generation-stamped cameFrom for path reconstruction
    cameFromGen*: array[MapWidth, array[MapHeight, int32]]
    cameFromVal*: array[MapWidth, array[MapHeight, IVec2]]
    # Open set array for iteration (with active flags for removal)
    openSet*: array[MaxPathNodes, IVec2]
    openSetLen*: int
    openSetActive*: array[MaxPathNodes, bool]
    # Goals array
    goals*: array[MaxPathGoals, IVec2]
    goalsLen*: int
    # Result path buffer
    path*: array[MaxPathLength, IVec2]
    pathLen*: int

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
    buildingCountsStep: -1,
    teamPopCountsStep: -1
  )
  # Initialize all teams to Normal difficulty by default
  for teamId in 0 ..< MapRoomObjectsTeams:
    result.difficulty[teamId] = defaultDifficultyConfig(DiffNormal)
