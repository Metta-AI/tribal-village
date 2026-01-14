import std/unittest
import environment
import items
import balance
import test_utils

suite "Market":
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

suite "Crafting":
  test "university crafts table items":
    let env = makeEmptyEnv()
    let uni = addBuilding(env, University, ivec2(10, 9), 0)
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    setInv(agent, ItemWood, 1)

    env.stepAction(agent.agentId, 3'u8, dirIndex(agent.pos, uni.pos))

    check agent.inventoryWood == 0
    check getInv(agent, otherItem("bucket")) == 1

suite "Storage":
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

suite "Training":
  test "monastery trains monk and spends gold":
    let env = makeEmptyEnv()
    let monastery = addBuilding(env, Monastery, ivec2(10, 9), 0)
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    setStockpile(env, 0, ResourceGold, 2)

    env.stepAction(agent.agentId, 3'u8, dirIndex(agent.pos, monastery.pos))
    check agent.unitClass == UnitMonk
    check env.stockpileCount(0, ResourceGold) == 0
