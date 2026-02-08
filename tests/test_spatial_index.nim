## Unit tests for spatial_index.nim - spatial partitioning for O(1) nearest queries.
##
## Tests cover:
## 1. Basic insert/remove operations
## 2. findNearest queries (single kind, multi-kind, friendly, enemy)
## 3. collectThings range queries
## 4. Edge cases: empty index, duplicate positions, boundary positions, update operations

import std/unittest
import test_utils
import environment
import types
import spatial_index

# Helper to create a thing at a position for testing
proc makeThing(kind: ThingKind, pos: IVec2, teamId: int = 0): Thing =
  result = Thing(kind: kind, pos: pos, teamId: teamId)
  result.inventory = emptyInventory()
  result.hp = 100
  result.maxHp = 100
  if kind == Agent:
    result.agentId = 0
    result.unitClass = UnitVillager

proc addTestAgent(env: Environment, agentId: int, pos: IVec2, teamId: int, unitClass: AgentUnitClass = UnitVillager): Thing =
  ## Add an agent that is properly registered as alive in the environment.
  ## This sets up grid, terminated array, and all required state for isAgentAlive.
  ## Team is set via teamIdOverride since that takes precedence for agents.
  result = addAgentAt(env, agentId, pos, unitClass = unitClass)
  result.teamIdOverride = teamId

suite "Spatial Index: Basic Operations":
  test "addToSpatialIndex adds thing to correct cell":
    let env = makeEmptyEnv()
    let pos = ivec2(50, 50)
    let thing = makeThing(Tree, pos)
    env.add(thing)

    # Thing should be findable via spatial query
    let found = findNearestThingSpatial(env, pos, Tree, 10)
    check found == thing

  test "removeFromSpatialIndex removes thing from cell":
    let env = makeEmptyEnv()
    let pos = ivec2(50, 50)
    let thing = makeThing(Tree, pos)
    env.add(thing)

    # Verify it's there
    var found = findNearestThingSpatial(env, pos, Tree, 10)
    check found == thing

    # Remove it
    removeFromSpatialIndex(env, thing)

    # Should not find it anymore
    found = findNearestThingSpatial(env, pos, Tree, 10)
    check found.isNil

  test "updateSpatialIndex moves thing between cells":
    let env = makeEmptyEnv()
    let oldPos = ivec2(10, 10)
    let newPos = ivec2(100, 100)  # Different cell
    let thing = makeThing(Tree, oldPos)
    env.add(thing)

    # Verify findable at old position
    var found = findNearestThingSpatial(env, oldPos, Tree, 10)
    check found == thing

    # Update position
    let savedOldPos = thing.pos
    thing.pos = newPos
    updateSpatialIndex(env, thing, savedOldPos)

    # Should not find at old position (outside range)
    found = findNearestThingSpatial(env, oldPos, Tree, 10)
    check found.isNil

    # Should find at new position
    found = findNearestThingSpatial(env, newPos, Tree, 10)
    check found == thing

  test "rebuildSpatialIndex repopulates from scratch":
    let env = makeEmptyEnv()

    # Add several things
    let thing1 = makeThing(Tree, ivec2(10, 10))
    let thing2 = makeThing(Tree, ivec2(50, 50))
    let thing3 = makeThing(Stone, ivec2(90, 90))
    env.add(thing1)
    env.add(thing2)
    env.add(thing3)

    # Clear and rebuild
    clearSpatialIndex(env)
    rebuildSpatialIndex(env)

    # All things should be findable
    check findNearestThingSpatial(env, ivec2(10, 10), Tree, 10) == thing1
    check findNearestThingSpatial(env, ivec2(50, 50), Tree, 10) == thing2
    check findNearestThingSpatial(env, ivec2(90, 90), Stone, 10) == thing3

suite "Spatial Index: findNearest Queries":
  test "findNearestThingSpatial returns closest of kind":
    let env = makeEmptyEnv()
    let queryPos = ivec2(50, 50)

    # Add trees at different distances
    let nearTree = makeThing(Tree, ivec2(52, 50))  # dist = 2
    let farTree = makeThing(Tree, ivec2(60, 50))   # dist = 10
    env.add(nearTree)
    env.add(farTree)

    let found = findNearestThingSpatial(env, queryPos, Tree, 100)
    check found == nearTree

  test "findNearestThingSpatial respects maxDist":
    let env = makeEmptyEnv()
    let queryPos = ivec2(50, 50)

    # Add tree outside maxDist
    let farTree = makeThing(Tree, ivec2(100, 50))  # dist = 50
    env.add(farTree)

    # Should not find with small maxDist
    let found = findNearestThingSpatial(env, queryPos, Tree, 10)
    check found.isNil

  test "findNearestThingSpatial returns nil for wrong kind":
    let env = makeEmptyEnv()
    let queryPos = ivec2(50, 50)

    let tree = makeThing(Tree, ivec2(51, 50))
    env.add(tree)

    # Query for Stone, should find nothing
    let found = findNearestThingSpatial(env, queryPos, Stone, 100)
    check found.isNil

  test "findNearestFriendlyThingSpatial finds same-team things":
    let env = makeEmptyEnv()
    let queryPos = ivec2(50, 50)

    # Add buildings from different teams
    let friendlyHouse = makeThing(House, ivec2(52, 50), teamId = 0)
    let enemyHouse = makeThing(House, ivec2(51, 50), teamId = 1)  # Closer but enemy
    env.add(friendlyHouse)
    env.add(enemyHouse)

    let found = findNearestFriendlyThingSpatial(env, queryPos, teamId = 0, House, 100)
    check found == friendlyHouse

  test "findNearestEnemyAgentSpatial finds different-team agents":
    let env = makeEmptyEnv()
    let queryPos = ivec2(50, 50)

    # Add agents from different teams
    let friendlyAgent = addTestAgent(env,0, ivec2(51, 50), teamId = 0)
    let enemyAgent = addTestAgent(env,1, ivec2(55, 50), teamId = 1)
    env.add(friendlyAgent)
    env.add(enemyAgent)

    let found = findNearestEnemyAgentSpatial(env, queryPos, teamId = 0, 100)
    check found == enemyAgent

  test "findNearestEnemyInRangeSpatial respects min and max range":
    let env = makeEmptyEnv()
    let queryPos = ivec2(50, 50)

    # Add enemy agents at different distances (Chebyshev)
    let tooClose = addTestAgent(env,0, ivec2(52, 50), teamId = 1)  # dist = 2
    let inRange = addTestAgent(env,1, ivec2(60, 50), teamId = 1)   # dist = 10
    let tooFar = addTestAgent(env,2, ivec2(80, 50), teamId = 1)    # dist = 30
    env.add(tooClose)
    env.add(inRange)
    env.add(tooFar)

    # Query with min=5, max=20 should find only inRange
    let found = findNearestEnemyInRangeSpatial(env, queryPos, teamId = 0, minRange = 5, maxRange = 20)
    check found == inRange

  test "findNearestThingOfKindsSpatial searches multiple kinds":
    let env = makeEmptyEnv()
    let queryPos = ivec2(50, 50)

    # Add different resources
    let tree = makeThing(Tree, ivec2(60, 50))      # dist = 10
    let stone = makeThing(Stone, ivec2(55, 50))    # dist = 5 (closer)
    let gold = makeThing(Gold, ivec2(70, 50))   # dist = 20
    env.add(tree)
    env.add(stone)
    env.add(gold)

    let found = findNearestThingOfKindsSpatial(env, queryPos, {Tree, Stone, Gold}, 100)
    check found == stone  # Closest regardless of kind

suite "Spatial Index: collectThings Range Queries":
  test "collectThingsInRangeSpatial collects all of kind in range":
    let env = makeEmptyEnv()
    let queryPos = ivec2(50, 50)

    # Add multiple trees
    let tree1 = makeThing(Tree, ivec2(52, 50))
    let tree2 = makeThing(Tree, ivec2(48, 50))
    let tree3 = makeThing(Tree, ivec2(100, 50))  # Out of range
    env.add(tree1)
    env.add(tree2)
    env.add(tree3)

    var targets: seq[Thing] = @[]
    collectThingsInRangeSpatial(env, queryPos, Tree, maxRange = 20, targets)

    check targets.len == 2
    check tree1 in targets
    check tree2 in targets
    check tree3 notin targets

  test "collectEnemiesInRangeSpatial collects enemy agents":
    let env = makeEmptyEnv()
    let queryPos = ivec2(50, 50)

    # Add agents (addTestAgent already calls env.add internally)
    let friendly = addTestAgent(env, 0, ivec2(51, 50), teamId = 0)
    let enemy1 = addTestAgent(env, 1, ivec2(52, 50), teamId = 1)
    let enemy2 = addTestAgent(env, 2, ivec2(53, 50), teamId = 1)
    let farEnemy = addTestAgent(env, 3, ivec2(100, 50), teamId = 1)  # Out of range

    var targets: seq[Thing] = @[]
    collectEnemiesInRangeSpatial(env, queryPos, teamId = 0, maxRange = 20, targets)

    check targets.len == 2
    check enemy1 in targets
    check enemy2 in targets
    check friendly notin targets
    check farEnemy notin targets

  test "collectAlliesInRangeSpatial collects friendly agents":
    let env = makeEmptyEnv()
    let queryPos = ivec2(50, 50)

    # Add agents (addTestAgent already calls env.add internally)
    let ally1 = addTestAgent(env, 0, ivec2(51, 50), teamId = 0)
    let ally2 = addTestAgent(env, 1, ivec2(52, 50), teamId = 0)
    let enemy = addTestAgent(env, 2, ivec2(53, 50), teamId = 1)

    var targets: seq[Thing] = @[]
    collectAlliesInRangeSpatial(env, queryPos, teamId = 0, maxRange = 20, targets)

    check targets.len == 2
    check ally1 in targets
    check ally2 in targets
    check enemy notin targets

  test "collectAgentsByClassInRange filters by unit class":
    let env = makeEmptyEnv()
    let queryPos = ivec2(50, 50)

    # Add different unit classes (addTestAgent already calls env.add internally)
    let villager = addTestAgent(env, 0, ivec2(51, 50), teamId = 0, UnitVillager)
    let archer = addTestAgent(env, 1, ivec2(52, 50), teamId = 0, UnitArcher)
    let knight = addTestAgent(env, 2, ivec2(53, 50), teamId = 0, UnitKnight)

    var targets: seq[Thing] = @[]
    collectAgentsByClassInRange(env, queryPos, teamId = 0, {UnitArcher, UnitKnight}, maxRange = 20, targets)

    check targets.len == 2
    check archer in targets
    check knight in targets
    check villager notin targets

suite "Spatial Index: Edge Cases":
  test "empty index returns nil for findNearest":
    let env = makeEmptyEnv()
    let found = findNearestThingSpatial(env, ivec2(50, 50), Tree, 100)
    check found.isNil

  test "empty index returns empty seq for collect":
    let env = makeEmptyEnv()
    var targets: seq[Thing] = @[]
    collectThingsInRangeSpatial(env, ivec2(50, 50), Tree, 100, targets)
    check targets.len == 0

  test "duplicate positions handled correctly":
    let env = makeEmptyEnv()
    let pos = ivec2(50, 50)

    # Add two things at same position
    let tree1 = makeThing(Tree, pos)
    let tree2 = makeThing(Tree, pos)
    env.add(tree1)
    env.add(tree2)

    var targets: seq[Thing] = @[]
    collectThingsInRangeSpatial(env, pos, Tree, 10, targets)

    # Both should be collected
    check targets.len == 2
    check tree1 in targets
    check tree2 in targets

  test "boundary positions at map edges":
    let env = makeEmptyEnv()

    # Add things at map boundaries
    let corner1 = makeThing(Tree, ivec2(0, 0))
    let corner2 = makeThing(Tree, ivec2(MapWidth - 1, 0))
    let corner3 = makeThing(Tree, ivec2(0, MapHeight - 1))
    let corner4 = makeThing(Tree, ivec2(MapWidth - 1, MapHeight - 1))
    env.add(corner1)
    env.add(corner2)
    env.add(corner3)
    env.add(corner4)

    # All corners should be findable
    check findNearestThingSpatial(env, ivec2(0, 0), Tree, 10) == corner1
    check findNearestThingSpatial(env, ivec2(MapWidth - 1, 0), Tree, 10) == corner2
    check findNearestThingSpatial(env, ivec2(0, MapHeight - 1), Tree, 10) == corner3
    check findNearestThingSpatial(env, ivec2(MapWidth - 1, MapHeight - 1), Tree, 10) == corner4

  test "query from boundary position":
    let env = makeEmptyEnv()

    # Add thing near boundary
    let tree = makeThing(Tree, ivec2(5, 5))
    env.add(tree)

    # Query from origin
    let found = findNearestThingSpatial(env, ivec2(0, 0), Tree, 20)
    check found == tree

  test "large search radius across many cells":
    let env = makeEmptyEnv()

    # Add thing at a moderate distance
    let tree = makeThing(Tree, ivec2(100, 100))
    env.add(tree)

    # Query with radius that covers the tree (Manhattan distance is 50+50=100)
    let found = findNearestThingSpatial(env, ivec2(50, 50), Tree, 150)
    check found == tree

  test "cell coordinate clamping for out-of-bounds positions":
    # Test cellCoords with boundary values (pure function, no env needed)
    let (cx0, cy0) = cellCoords(ivec2(0, 0))
    check cx0 == 0
    check cy0 == 0

    let (cxMax, cyMax) = cellCoords(ivec2(MapWidth - 1, MapHeight - 1))
    check cxMax == SpatialCellsX - 1
    check cyMax == SpatialCellsY - 1

suite "Spatial Index: Update Operations":
  test "updateSpatialIndex no-op for same cell":
    let env = makeEmptyEnv()
    let pos1 = ivec2(50, 50)
    let pos2 = ivec2(51, 51)  # Same cell (within SpatialCellSize)

    let thing = makeThing(Tree, pos1)
    env.add(thing)

    # Update within same cell
    let oldPos = thing.pos
    thing.pos = pos2
    updateSpatialIndex(env, thing, oldPos)

    # Should still be findable
    let found = findNearestThingSpatial(env, pos2, Tree, 10)
    check found == thing

  test "multiple updates track position correctly":
    let env = makeEmptyEnv()

    let thing = makeThing(Tree, ivec2(10, 10))
    env.add(thing)

    # Series of moves within close proximity
    let positions = [ivec2(50, 50), ivec2(60, 60), ivec2(70, 70), ivec2(80, 80)]
    for newPos in positions:
      let oldPos = thing.pos
      thing.pos = newPos
      updateSpatialIndex(env, thing, oldPos)

      # Verify findable at new position (use larger radius to be safe)
      let found = findNearestThingSpatial(env, newPos, Tree, 20)
      check found == thing

suite "Spatial Index: Lookup Tables":
  test "distToCellRadius16 gives correct cell radius":
    # Distance 0 should give radius 0
    check distToCellRadius16(0) == 0

    # Distance 16 should give radius 1 (exactly one cell)
    check distToCellRadius16(16) == 1

    # Distance 15 should still give radius 1 (ceiling)
    check distToCellRadius16(15) == 1

    # Distance 32 should give radius 2
    check distToCellRadius16(32) == 2

    # Distance 17 should give radius 2 (ceiling)
    check distToCellRadius16(17) == 2

  test "NeighborOffsets are sorted by Chebyshev distance":
    for radius in 0 .. min(5, MaxPrecomputedRadius):
      let offsets = NeighborOffsets[radius]
      var prevDist = 0
      for offset in offsets:
        let dist = max(abs(offset.dx.int), abs(offset.dy.int))
        check dist >= prevDist  # Non-decreasing
        check dist <= radius     # Within radius
        prevDist = dist

  test "NeighborOffsetCounts match expected (2r+1)^2":
    for radius in 0 .. min(5, MaxPrecomputedRadius):
      let expected = (2 * radius + 1) * (2 * radius + 1)
      check NeighborOffsetCounts[radius] == expected
      check NeighborOffsets[radius].len == expected

suite "Spatial Index: Enemy Building Search":
  test "findNearestEnemyBuildingSpatial finds enemy buildings":
    let env = makeEmptyEnv()
    let queryPos = ivec2(50, 50)

    # Add buildings
    let friendlyTC = makeThing(TownCenter, ivec2(52, 50), teamId = 0)
    let enemyTC = makeThing(TownCenter, ivec2(60, 50), teamId = 1)
    let enemyHouse = makeThing(House, ivec2(55, 50), teamId = 1)  # Closer enemy
    env.add(friendlyTC)
    env.add(enemyTC)
    env.add(enemyHouse)

    let found = findNearestEnemyBuildingSpatial(env, queryPos, teamId = 0, maxDist = 100)
    check found == enemyHouse  # Closest enemy building

  test "findNearestEnemyBuildingSpatial ignores neutral buildings":
    let env = makeEmptyEnv()
    let queryPos = ivec2(50, 50)

    # Add neutral building (teamId = -1)
    let neutralBuilding = makeThing(House, ivec2(52, 50), teamId = -1)
    let enemyBuilding = makeThing(House, ivec2(60, 50), teamId = 1)
    env.add(neutralBuilding)
    env.add(enemyBuilding)

    let found = findNearestEnemyBuildingSpatial(env, queryPos, teamId = 0, maxDist = 100)
    check found == enemyBuilding  # Should skip neutral
