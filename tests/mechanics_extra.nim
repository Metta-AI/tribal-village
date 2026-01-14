import std/unittest
import environment
import types
import items
import balance
import test_utils

proc isAdjacent(a, b: IVec2): bool =
  max(abs(a.x - b.x), abs(a.y - b.y)) <= 1

suite "Mechanics - Conversion":
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

suite "Mechanics - Relics":
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

suite "Mechanics - Market":
  test "market trades multiple resources and sets cooldown":
    let env = makeEmptyEnv()
    let market = addBuilding(env, Market, ivec2(10, 9), 0)
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    setInv(agent, ItemWood, 3)
    setInv(agent, ItemGold, 2)
    setStockpile(env, 0, ResourceGold, 0)
    setStockpile(env, 0, ResourceFood, 0)

    env.stepAction(agent.agentId, 3'u8, dirIndex(agent.pos, market.pos))

    let expectedGold = (3 * DefaultMarketSellNumerator) div DefaultMarketSellDenominator
    let expectedFood = (2 * DefaultMarketBuyFoodNumerator) div DefaultMarketBuyFoodDenominator
    check env.stockpileCount(0, ResourceGold) == expectedGold
    check env.stockpileCount(0, ResourceFood) == expectedFood
    check agent.inventoryWood == 3 mod DefaultMarketSellDenominator
    check agent.inventoryGold == 0
    check market.cooldown == max(0, DefaultMarketCooldown - 1)

  test "market cooldown blocks trading":
    let env = makeEmptyEnv()
    let market = addBuilding(env, Market, ivec2(10, 9), 0)
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    setInv(agent, ItemWood, 2)
    setStockpile(env, 0, ResourceGold, 0)
    market.cooldown = 1

    env.stepAction(agent.agentId, 3'u8, dirIndex(agent.pos, market.pos))

    check agent.inventoryWood == 2
    check env.stockpileCount(0, ResourceGold) == 0
    check market.cooldown == 0

suite "Mechanics - Dock":
  test "cannot embark without dock":
    let env = makeEmptyEnv()
    env.terrain[10][10] = Water
    let agent = addAgentAt(env, 0, ivec2(10, 11))

    env.stepAction(agent.agentId, 1'u8, dirIndex(agent.pos, ivec2(10, 10)))
    check env.agents[agent.agentId].pos == ivec2(10, 11)
    check env.agents[agent.agentId].unitClass == UnitVillager

suite "Mechanics - Crafting":
  test "university crafts table items":
    let env = makeEmptyEnv()
    let uni = addBuilding(env, University, ivec2(10, 9), 0)
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    setInv(agent, ItemWood, 1)

    env.stepAction(agent.agentId, 3'u8, dirIndex(agent.pos, uni.pos))

    check agent.inventoryWood == 0
    check getInv(agent, otherItem("bucket")) == 1

suite "Mechanics - Storage":
  test "barrel stores and returns items":
    let env = makeEmptyEnv()
    let barrel = addBuilding(env, Barrel, ivec2(10, 9), 0)
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    setInv(agent, ItemBread, 2)

    env.stepAction(agent.agentId, 3'u8, dirIndex(agent.pos, barrel.pos))
    check getInv(barrel, ItemBread) == 2
    check agent.inventoryBread == 0

    env.stepAction(agent.agentId, 3'u8, dirIndex(agent.pos, barrel.pos))
    check getInv(barrel, ItemBread) == 0
    check agent.inventoryBread == 2

suite "Mechanics - Training":
  test "monastery trains monk and spends gold":
    let env = makeEmptyEnv()
    let monastery = addBuilding(env, Monastery, ivec2(10, 9), 0)
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    setStockpile(env, 0, ResourceGold, 2)

    env.stepAction(agent.agentId, 3'u8, dirIndex(agent.pos, monastery.pos))
    check agent.unitClass == UnitMonk
    check env.stockpileCount(0, ResourceGold) == 0

suite "Mechanics - Spawn":
  test "fish spawn only on water":
    let env = newEnvironment()
    let fish = env.thingsByKind[Fish]
    check fish.len > 0
    for node in fish:
      check env.terrain[node.pos.x][node.pos.y] == Water
