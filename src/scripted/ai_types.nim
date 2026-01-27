# AI Types Module - Shared types for the AI system
# This module contains the core types used by all AI modules.
import vmath
import ../types, ../entropy

const
  MaxPathNodes* = 512     # Slightly more than 250 exploration limit
  MaxPathLength* = 256    # Max reconstructed path length
  MaxPathGoals* = 10      # Max goal positions (8 neighbors + direct)

type
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
    cachedWaterPos*: IVec2
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

  # Simple controller
  Controller* = ref object
    rng*: Rand
    agents*: array[MapAgents, AgentState]
    agentsInitialized*: array[MapAgents, bool]
    buildingCountsStep*: int
    buildingCounts*: array[MapRoomObjectsTeams, array[ThingKind, int]]
    claimedBuildings*: array[MapRoomObjectsTeams, set[ThingKind]]  # Buildings claimed by builders this step
    pathCache*: PathfindingCache  # Pre-allocated pathfinding scratch space

proc newController*(seed: int): Controller =
  result = Controller(
    rng: initRand(seed),
    buildingCountsStep: -1
  )

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
