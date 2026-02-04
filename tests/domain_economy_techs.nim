import std/unittest
import environment
import types
import items
import test_utils

suite "Economy Techs - Research":
  test "hasEconomyTech returns false for unresearched tech":
    let env = makeEmptyEnv()
    check not env.hasEconomyTech(0, TechWheelbarrow)
    check not env.hasEconomyTech(0, TechDoubleBitAxe)
    check not env.hasEconomyTech(0, TechGoldMining)
    check not env.hasEconomyTech(0, TechHorseCollar)

  test "economyTechBuilding returns correct building":
    check economyTechBuilding(TechWheelbarrow) == TownCenter
    check economyTechBuilding(TechHandCart) == TownCenter
    check economyTechBuilding(TechDoubleBitAxe) == LumberCamp
    check economyTechBuilding(TechBowSaw) == LumberCamp
    check economyTechBuilding(TechTwoManSaw) == LumberCamp
    check economyTechBuilding(TechGoldMining) == MiningCamp
    check economyTechBuilding(TechGoldShaftMining) == MiningCamp
    check economyTechBuilding(TechStoneMining) == MiningCamp
    check economyTechBuilding(TechStoneShaftMining) == MiningCamp
    check economyTechBuilding(TechHorseCollar) == Mill
    check economyTechBuilding(TechHeavyPlow) == Mill
    check economyTechBuilding(TechCropRotation) == Mill

  test "economyTechPrerequisite returns correct prereq":
    # No prereq for first techs
    check economyTechPrerequisite(TechWheelbarrow) == TechWheelbarrow
    check economyTechPrerequisite(TechDoubleBitAxe) == TechDoubleBitAxe
    check economyTechPrerequisite(TechGoldMining) == TechGoldMining
    check economyTechPrerequisite(TechStoneMining) == TechStoneMining
    check economyTechPrerequisite(TechHorseCollar) == TechHorseCollar
    # Tier 2 requires tier 1
    check economyTechPrerequisite(TechHandCart) == TechWheelbarrow
    check economyTechPrerequisite(TechBowSaw) == TechDoubleBitAxe
    check economyTechPrerequisite(TechGoldShaftMining) == TechGoldMining
    check economyTechPrerequisite(TechStoneShaftMining) == TechStoneMining
    check economyTechPrerequisite(TechHeavyPlow) == TechHorseCollar
    # Tier 3 requires tier 2
    check economyTechPrerequisite(TechTwoManSaw) == TechBowSaw
    check economyTechPrerequisite(TechCropRotation) == TechHeavyPlow

suite "Economy Techs - Gathering Bonuses":
  test "getWoodGatherBonus returns 0 with no techs":
    let env = makeEmptyEnv()
    check env.getWoodGatherBonus(0) == 0

  test "getWoodGatherBonus accumulates with techs":
    let env = makeEmptyEnv()
    env.teamEconomyTechs[0].researched[TechDoubleBitAxe] = true
    check env.getWoodGatherBonus(0) == DoubleBitAxeGatherBonus
    env.teamEconomyTechs[0].researched[TechBowSaw] = true
    check env.getWoodGatherBonus(0) == DoubleBitAxeGatherBonus + BowSawGatherBonus
    env.teamEconomyTechs[0].researched[TechTwoManSaw] = true
    check env.getWoodGatherBonus(0) == DoubleBitAxeGatherBonus + BowSawGatherBonus + TwoManSawGatherBonus

  test "getGoldGatherBonus returns 0 with no techs":
    let env = makeEmptyEnv()
    check env.getGoldGatherBonus(0) == 0

  test "getGoldGatherBonus accumulates with techs":
    let env = makeEmptyEnv()
    env.teamEconomyTechs[0].researched[TechGoldMining] = true
    check env.getGoldGatherBonus(0) == GoldMiningGatherBonus
    env.teamEconomyTechs[0].researched[TechGoldShaftMining] = true
    check env.getGoldGatherBonus(0) == GoldMiningGatherBonus + GoldShaftMiningGatherBonus

  test "getStoneGatherBonus returns 0 with no techs":
    let env = makeEmptyEnv()
    check env.getStoneGatherBonus(0) == 0

  test "getStoneGatherBonus accumulates with techs":
    let env = makeEmptyEnv()
    env.teamEconomyTechs[0].researched[TechStoneMining] = true
    check env.getStoneGatherBonus(0) == StoneMiningGatherBonus
    env.teamEconomyTechs[0].researched[TechStoneShaftMining] = true
    check env.getStoneGatherBonus(0) == StoneMiningGatherBonus + StoneShaftMiningGatherBonus

suite "Economy Techs - Villager Carry Capacity":
  test "getVillagerCarryCapacity returns base capacity with no techs":
    let env = makeEmptyEnv()
    check env.getVillagerCarryCapacity(0) == ResourceCarryCapacity

  test "getVillagerCarryCapacity increases with Wheelbarrow":
    let env = makeEmptyEnv()
    env.teamEconomyTechs[0].researched[TechWheelbarrow] = true
    check env.getVillagerCarryCapacity(0) == ResourceCarryCapacity + WheelbarrowCarryBonus

  test "getVillagerCarryCapacity increases with Hand Cart":
    let env = makeEmptyEnv()
    env.teamEconomyTechs[0].researched[TechWheelbarrow] = true
    env.teamEconomyTechs[0].researched[TechHandCart] = true
    check env.getVillagerCarryCapacity(0) == ResourceCarryCapacity + WheelbarrowCarryBonus + HandCartCarryBonus

suite "Economy Techs - Farm Bonuses":
  test "getFarmFoodBonus returns 0 with no techs":
    let env = makeEmptyEnv()
    check env.getFarmFoodBonus(0) == 0

  test "getFarmFoodBonus accumulates with techs":
    let env = makeEmptyEnv()
    env.teamEconomyTechs[0].researched[TechHorseCollar] = true
    check env.getFarmFoodBonus(0) == HorseCollarFarmBonus
    env.teamEconomyTechs[0].researched[TechHeavyPlow] = true
    check env.getFarmFoodBonus(0) == HorseCollarFarmBonus + HeavyPlowFarmBonus
    env.teamEconomyTechs[0].researched[TechCropRotation] = true
    check env.getFarmFoodBonus(0) == HorseCollarFarmBonus + HeavyPlowFarmBonus + CropRotationFarmBonus

  test "canAutoReseed requires Horse Collar":
    let env = makeEmptyEnv()
    check not env.canAutoReseed(0)
    env.teamEconomyTechs[0].researched[TechHorseCollar] = true
    check env.canAutoReseed(0)

suite "Mill Farm Queue":
  test "addFarmToMillQueue adds position to queue":
    let env = makeEmptyEnv()
    let mill = Thing(kind: Mill, pos: ivec2(10, 10), teamId: 0)
    env.addFarmToMillQueue(mill, ivec2(11, 10))
    check mill.farmQueue.len == 1
    check mill.farmQueue[0] == ivec2(11, 10)

  test "addFarmToMillQueue rejects farms outside radius":
    let env = makeEmptyEnv()
    let mill = Thing(kind: Mill, pos: ivec2(10, 10), teamId: 0)
    # Mill fertile radius is 2
    env.addFarmToMillQueue(mill, ivec2(15, 15))  # Too far
    check mill.farmQueue.len == 0

  test "addFarmToMillQueue prevents duplicates":
    let env = makeEmptyEnv()
    let mill = Thing(kind: Mill, pos: ivec2(10, 10), teamId: 0)
    env.addFarmToMillQueue(mill, ivec2(11, 10))
    env.addFarmToMillQueue(mill, ivec2(11, 10))  # Duplicate
    check mill.farmQueue.len == 1

  test "findNearestMill finds mill within range":
    let env = makeEmptyEnv()
    let mill = Thing(kind: Mill, pos: ivec2(10, 10), teamId: 0)
    env.thingsByKind[Mill].add(mill)
    let found = env.findNearestMill(ivec2(11, 10), 0)
    check found == mill

  test "findNearestMill returns nil for wrong team":
    let env = makeEmptyEnv()
    let mill = Thing(kind: Mill, pos: ivec2(10, 10), teamId: 1)
    env.thingsByKind[Mill].add(mill)
    let found = env.findNearestMill(ivec2(11, 10), 0)
    check found == nil

  test "findNearestMill returns nil when out of range":
    let env = makeEmptyEnv()
    let mill = Thing(kind: Mill, pos: ivec2(10, 10), teamId: 0)
    env.thingsByKind[Mill].add(mill)
    let found = env.findNearestMill(ivec2(50, 50), 0)  # Too far
    check found == nil
