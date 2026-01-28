import std/unittest
import environment
import items
import test_utils

suite "Town Center Garrison":
  test "villager can garrison in own town center":
    let env = makeEmptyEnv()
    let tc = addBuilding(env, TownCenter, ivec2(10, 9), 0)
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    # Villager has no resources, so USE on TC should garrison

    env.stepAction(agent.agentId, 3'u8, dirIndex(agent.pos, tc.pos))

    check tc.garrisonedUnits.len == 1
    check tc.garrisonedUnits[0] == agent
    check agent.pos == ivec2(-1, -1)  # Agent is off-grid

  test "garrisoned villagers add TC arrow damage":
    let env = makeEmptyEnv()
    let tc = addBuilding(env, TownCenter, ivec2(10, 10), 0)
    # Add some villagers to garrison
    for i in 0 ..< 5:
      let villager = addAgentAt(env, i, ivec2(10 + i, 11))
      discard env.garrisonUnitInBuilding(villager, tc)

    check tc.garrisonedUnits.len == 5
    # Each garrisoned unit adds TownCenterGarrisonArrowBonus arrows

  test "units ungarrison when TC is destroyed":
    let env = makeEmptyEnv()
    let tc = addBuilding(env, TownCenter, ivec2(10, 10), 0)
    let agent = addAgentAt(env, 0, ivec2(11, 11))
    discard env.garrisonUnitInBuilding(agent, tc)

    check tc.garrisonedUnits.len == 1
    check agent.pos == ivec2(-1, -1)

    # Destroy TC
    discard env.applyStructureDamage(tc, TownCenterMaxHp + 10)

    # Agent should be ejected
    check agent.pos != ivec2(-1, -1)
    check isValidPos(agent.pos)

  test "town bell recalls villagers to garrison":
    let env = makeEmptyEnv()
    let tc = addBuilding(env, TownCenter, ivec2(10, 10), 0)
    let triggerer = addAgentAt(env, 0, ivec2(9, 10))  # Adjacent to TC
    let villager1 = addAgentAt(env, 1, ivec2(5, 5))
    let villager2 = addAgentAt(env, 2, ivec2(20, 20))

    # Ring town bell (argument 10)
    env.stepAction(triggerer.agentId, 3'u8, 10)

    # All villagers should be garrisoned
    check tc.garrisonedUnits.len == 3

  test "ungarrison command ejects all units":
    let env = makeEmptyEnv()
    let tc = addBuilding(env, TownCenter, ivec2(10, 10), 0)
    let triggerer = addAgentAt(env, 0, ivec2(9, 10))
    # Garrison some units
    for i in 1 ..< 5:
      let villager = addAgentAt(env, i, ivec2(10 + i, 11))
      discard env.garrisonUnitInBuilding(villager, tc)

    check tc.garrisonedUnits.len == 4

    # Ungarrison (argument 9)
    env.stepAction(triggerer.agentId, 3'u8, 9)

    check tc.garrisonedUnits.len == 0

  test "enemy villager cannot garrison in opponent TC":
    let env = makeEmptyEnv()
    let tc = addBuilding(env, TownCenter, ivec2(10, 9), 0)  # Team 0 TC
    let enemy = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 10))  # Team 1 villager

    env.stepAction(enemy.agentId, 3'u8, dirIndex(enemy.pos, tc.pos))

    check tc.garrisonedUnits.len == 0  # Enemy should not garrison
