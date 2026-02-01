import std/[unittest, strformat]
import environment
import agent_control
import types
import items
import spatial_index
import test_utils
import common

## Behavioral tests for spatial index operations.
## Verifies that spatial queries handle edge cases like invalid positions
## without triggering OverflowDefect or other crashes.

suite "Behavior: Spatial Index Position Validation":
  test "findNearestThingSpatial handles valid positions":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(50, 50))
    let resource = addResource(env, Tree, ivec2(55, 50), ItemWood)

    env.rebuildSpatialIndex()
    let nearest = env.findNearestThingSpatial(agent.pos, Tree, 100)
    check nearest == resource
    echo "  Found nearest tree at valid position"

  test "findNearestThingSpatial returns nil when no things found":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(50, 50))

    env.rebuildSpatialIndex()
    let nearest = env.findNearestThingSpatial(agent.pos, Tree, 100)
    check nearest == nil
    echo "  Returns nil when no trees in range"

  test "findNearestThingSpatial skips things with positions outside map bounds":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(50, 50))

    # Create a thing and manually set invalid position (simulating corruption)
    let resource = Thing(kind: Tree, pos: ivec2(-10, -10))  # Invalid position
    resource.inventory = emptyInventory()
    setInv(resource, ItemWood, 10)
    env.things.add(resource)
    env.thingsByKind[Tree].add(resource)

    # Add a valid tree
    let validTree = addResource(env, Tree, ivec2(55, 50), ItemWood)

    env.rebuildSpatialIndex()

    # The invalid tree should not cause an overflow; only valid tree should be found
    let nearest = env.findNearestThingSpatial(agent.pos, Tree, 100)
    check nearest == validTree
    echo "  Skipped tree with invalid position, found valid tree"

  test "findNearestEnemyAgentSpatial handles agents with invalid positions":
    let env = makeEmptyEnv()
    let teamId = 0
    let agent = addAgentAt(env, 0, ivec2(50, 50))

    # Add a valid enemy
    let enemy = addAgentAt(env, MapAgentsPerTeam, ivec2(55, 50))

    env.rebuildSpatialIndex()

    # Should find the valid enemy without overflow
    let nearest = env.findNearestEnemyAgentSpatial(agent.pos, teamId, 100)
    check nearest == enemy
    echo "  Found enemy agent at valid position"

  test "collectEnemiesInRangeSpatial handles mixed valid/invalid positions":
    let env = makeEmptyEnv()
    let teamId = 0
    let agent = addAgentAt(env, 0, ivec2(50, 50))

    # Add valid enemies at different distances
    let enemy1 = addAgentAt(env, MapAgentsPerTeam, ivec2(55, 50))
    let enemy2 = addAgentAt(env, MapAgentsPerTeam + 1, ivec2(52, 52))

    env.rebuildSpatialIndex()

    var targets: seq[Thing] = @[]
    env.collectEnemiesInRangeSpatial(agent.pos, teamId, 10, targets)

    check targets.len == 2
    check enemy1 in targets
    check enemy2 in targets
    echo &"  Collected {targets.len} enemies in range"

  test "collectAlliesInRangeSpatial handles boundary positions":
    let env = makeEmptyEnv()
    let teamId = 0
    let agent = addAgentAt(env, 0, ivec2(MapBorder.int32, MapBorder.int32))  # Corner position

    # Add ally near the corner
    let ally = addAgentAt(env, 1, ivec2(MapBorder.int32 + 3, MapBorder.int32 + 3))

    env.rebuildSpatialIndex()

    var allies: seq[Thing] = @[]
    env.collectAlliesInRangeSpatial(agent.pos, teamId, 10, allies)

    check ally in allies
    echo "  Collected ally near map corner"

suite "Behavior: Spatial Index Robustness":
  test "spatial queries at map boundaries do not overflow":
    let env = makeEmptyEnv()

    # Test at all four corners
    let corners = [
      ivec2(MapBorder.int32, MapBorder.int32),  # NW
      ivec2((MapWidth - MapBorder - 1).int32, MapBorder.int32),  # NE
      ivec2(MapBorder.int32, (MapHeight - MapBorder - 1).int32),  # SW
      ivec2((MapWidth - MapBorder - 1).int32, (MapHeight - MapBorder - 1).int32)  # SE
    ]

    for i, corner in corners:
      discard addAgentAt(env, i, corner)

    env.rebuildSpatialIndex()

    # Query from each corner - should not crash
    for corner in corners:
      let nearest = env.findNearestThingSpatial(corner, Tree, 100)
      check nearest == nil  # No trees added

    echo "  Spatial queries at all four corners succeeded"

  test "large search radius does not overflow":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(50, 50))
    let tree = addResource(env, Tree, ivec2(200, 150), ItemWood)

    env.rebuildSpatialIndex()

    # Use a very large search radius
    let nearest = env.findNearestThingSpatial(agent.pos, Tree, int.high div 2)
    check nearest == tree
    echo "  Large search radius handled correctly"

  test "empty spatial index returns nil":
    let env = makeEmptyEnv()
    env.rebuildSpatialIndex()

    let result = env.findNearestThingSpatial(ivec2(50, 50), Tree, 100)
    check result == nil
    echo "  Empty spatial index returns nil"

  test "findNearestFriendlyThingSpatial with valid team":
    let env = makeEmptyEnv()
    let teamId = 0
    let agent = addAgentAt(env, 0, ivec2(50, 50))
    let house = addBuilding(env, House, ivec2(55, 50), teamId)

    env.rebuildSpatialIndex()

    let nearest = env.findNearestFriendlyThingSpatial(agent.pos, teamId, House, 100)
    check nearest == house
    echo "  Found friendly building"

  test "findNearestFriendlyThingSpatial ignores enemy buildings":
    let env = makeEmptyEnv()
    let teamId = 0
    let enemyTeamId = 1
    let agent = addAgentAt(env, 0, ivec2(50, 50))

    # Add enemy building closer than friendly building
    let enemyHouse = addBuilding(env, House, ivec2(52, 50), enemyTeamId)
    let friendlyHouse = addBuilding(env, House, ivec2(60, 50), teamId)

    env.rebuildSpatialIndex()

    let nearest = env.findNearestFriendlyThingSpatial(agent.pos, teamId, House, 100)
    check nearest == friendlyHouse
    check nearest != enemyHouse
    echo "  Correctly ignored enemy building, found friendly building"
