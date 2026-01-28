import std/unittest
import environment
import terrain
import test_utils

suite "Dock":
  test "cannot embark without dock":
    let env = makeEmptyEnv()
    env.terrain[10][10] = Water
    let agent = addAgentAt(env, 0, ivec2(10, 11))

    env.stepAction(agent.agentId, 1'u8, dirIndex(agent.pos, ivec2(10, 10)))
    check env.agents[agent.agentId].pos == ivec2(10, 11)
    check env.agents[agent.agentId].unitClass == UnitVillager

suite "Spawn":
  test "fish spawn only on water":
    let env = newEnvironment()
    let fish = env.thingsByKind[Fish]
    if fish.len > 0:
      for node in fish:
        check env.terrain[node.pos.x][node.pos.y] in {Water, ShallowWater}
