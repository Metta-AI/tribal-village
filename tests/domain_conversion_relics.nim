import std/unittest
import environment
import types
import items
import test_utils

proc isAdjacent(a, b: IVec2): bool =
  max(abs(a.x - b.x), abs(a.y - b.y)) <= 1

suite "Conversion":
  test "monk conversion updates team and home altar":
    let env = makeEmptyEnv()
    let altarPos = ivec2(12, 10)
    discard addAltar(env, altarPos, 0, 10)
    discard addBuilding(env, House, ivec2(12, 11), 0)
    let monk = addAgentAt(env, 0, ivec2(10, 10), homeAltar = altarPos, unitClass = UnitMonk)
    let enemy = addAgentAt(env, MapAgentsPerVillage, ivec2(10, 9))

    env.stepAction(monk.agentId, 2'u8, dirIndex(monk.pos, enemy.pos))

    check getTeamId(enemy) == 0
    check enemy.homeAltar == altarPos

  test "monk conversion respects pop cap":
    let env = makeEmptyEnv()
    let altarPos = ivec2(12, 10)
    discard addAltar(env, altarPos, 0, 10)
    discard addBuilding(env, House, ivec2(12, 11), 0)
    let cap = buildingPopCap(House)
    for i in 0 ..< cap:
      let pos = if i == 0: ivec2(10, 10) else: ivec2(20 + i.int32, 20)
      let unitClass = if i == 0: UnitMonk else: UnitVillager
      discard addAgentAt(env, i, pos, homeAltar = altarPos, unitClass = unitClass)
    let enemy = addAgentAt(env, MapAgentsPerVillage, ivec2(10, 9))

    env.stepAction(0, 2'u8, dirIndex(ivec2(10, 10), enemy.pos))

    check getTeamId(enemy) == 1

suite "Relics":
  test "relic pickup grants gold and drop restores relic":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    let relicPos = ivec2(10, 9)
    let relic = Thing(kind: Relic, pos: relicPos)
    relic.inventory = emptyInventory()
    setInv(relic, ItemGold, 1)
    env.add(relic)

    env.stepAction(agent.agentId, 3'u8, dirIndex(agent.pos, relicPos))
    check agent.inventoryRelic == 1
    check getInv(agent, ItemGold) == 1
    check env.getOverlayThing(relicPos) == nil

    env.stepAction(agent.agentId, 3'u8, dirIndex(agent.pos, relicPos))
    check agent.inventoryRelic == 0
    let dropped = env.getOverlayThing(relicPos)
    check not isNil(dropped)
    check dropped.kind == Relic
    check getInv(dropped, ItemGold) == 0

  test "relics and lanterns drop on death":
    let env = makeEmptyEnv()
    let attacker = addAgentAt(env, 0, ivec2(10, 10))
    let victimPos = ivec2(10, 9)
    let victim = addAgentAt(env, MapAgentsPerVillage, victimPos)
    victim.hp = 1
    victim.inventoryRelic = 1
    victim.inventoryLantern = 1

    env.stepAction(attacker.agentId, 2'u8, dirIndex(attacker.pos, victimPos))

    check env.thingsByKind[Relic].len == 1
    check env.thingsByKind[Lantern].len == 1
    let droppedRelic = env.thingsByKind[Relic][0]
    let droppedLantern = env.thingsByKind[Lantern][0]
    check isAdjacent(droppedRelic.pos, victimPos)
    check isAdjacent(droppedLantern.pos, victimPos)
    check getInv(droppedRelic, ItemGold) == 0
