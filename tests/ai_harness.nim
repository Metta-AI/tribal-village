import std/unittest
import environment
import agent_control
import types
import items
import terrain
import test_utils

proc fillStockpile(env: Environment, teamId: int, amount: int) =
  setStockpile(env, teamId, ResourceFood, amount)
  setStockpile(env, teamId, ResourceWood, amount)
  setStockpile(env, teamId, ResourceStone, amount)
  setStockpile(env, teamId, ResourceGold, amount)

suite "Mechanics - Resources":
  test "tree to stump and stump depletes":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    discard addResource(env, Tree, ivec2(10, 9), ItemWood, ResourceNodeInitial)

    env.stepAction(0, 3'u8, dirIndex(agent.pos, ivec2(10, 9)))
    let stump = env.getThing(ivec2(10, 9))
    check stump.kind == Stump
    check getInv(stump, ItemWood) == ResourceNodeInitial - 1
    check agent.inventoryWood == 1

    setInv(stump, ItemWood, 1)
    env.stepAction(0, 3'u8, dirIndex(agent.pos, ivec2(10, 9)))
    check env.getThing(ivec2(10, 9)) == nil

  test "wheat depletes and removes":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    discard addResource(env, Wheat, ivec2(10, 9), ItemWheat, 2)

    env.stepAction(0, 3'u8, dirIndex(agent.pos, ivec2(10, 9)))
    let wheat = env.getBackgroundThing(ivec2(10, 9))
    check wheat.kind == Stubble
    check getInv(wheat, ItemWheat) == 1

    env.stepAction(0, 3'u8, dirIndex(agent.pos, ivec2(10, 9)))
    check env.getBackgroundThing(ivec2(10, 9)) == nil

  test "stone and gold deplete":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    discard addResource(env, Stone, ivec2(10, 9), ItemStone, 1)
    discard addResource(env, Gold, ivec2(11, 10), ItemGold, 1)
    let goldNode = env.getThing(ivec2(11, 10))
    check getInv(goldNode, ItemGold) == 1

    env.stepAction(0, 3'u8, dirIndex(agent.pos, ivec2(10, 9)))
    check env.getThing(ivec2(10, 9)) == nil

    agent.inventory = emptyInventory()
    env.stepAction(0, 3'u8, dirIndex(agent.pos, ivec2(11, 10)))
    check env.getThing(ivec2(11, 10)) == nil

  test "boat harvests fish on water":
    let env = makeEmptyEnv()
    env.terrain[10][10] = Water
    env.terrain[10][9] = Water
    discard addBuilding(env, Dock, ivec2(10, 10), 0)
    discard addResource(env, Fish, ivec2(10, 9), ItemFish, 1)
    let agent = addAgentAt(env, 0, ivec2(10, 11))

    env.stepAction(agent.agentId, 1'u8, dirIndex(agent.pos, ivec2(10, 10)))
    check env.agents[agent.agentId].unitClass == UnitBoat

    env.stepAction(agent.agentId, 3'u8, dirIndex(ivec2(10, 10), ivec2(10, 9)))
    check getInv(env.agents[agent.agentId], ItemFish) == 1
    check env.getBackgroundThing(ivec2(10, 9)) == nil

  test "planting wheat consumes inventory and clears fertile":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    agent.inventoryWheat = 1
    let target = ivec2(10, 9)
    env.terrain[target.x][target.y] = Fertile

    env.stepAction(agent.agentId, 7'u8, dirIndex(agent.pos, target))

    let crop = env.getBackgroundThing(target)
    check crop.kind == Wheat
    check getInv(crop, ItemWheat) == ResourceNodeInitial
    check agent.inventoryWheat == 0
    check env.terrain[target.x][target.y] == TerrainEmpty

suite "Mechanics - Movement":
  test "boat embarks on dock and disembarks on land":
    let env = makeEmptyEnv()
    env.terrain[10][10] = Water
    discard addBuilding(env, Dock, ivec2(10, 10), 0)
    let agent = addAgentAt(env, 0, ivec2(10, 11))

    env.stepAction(agent.agentId, 1'u8, dirIndex(agent.pos, ivec2(10, 10)))
    check env.agents[agent.agentId].pos == ivec2(10, 10)
    check env.agents[agent.agentId].unitClass == UnitBoat

    env.stepAction(agent.agentId, 1'u8, dirIndex(ivec2(10, 10), ivec2(10, 11)))
    check env.agents[agent.agentId].pos == ivec2(10, 11)
    check env.agents[agent.agentId].unitClass == UnitVillager

  test "swap action updates positions":
    let env = makeEmptyEnv()
    let agentA = addAgentAt(env, 0, ivec2(10, 10))
    let agentB = addAgentAt(env, 1, ivec2(10, 9))

    env.stepAction(agentA.agentId, 4'u8, dirIndex(agentA.pos, agentB.pos))

    check agentA.pos == ivec2(10, 9)
    check agentB.pos == ivec2(10, 10)
    check env.getThing(ivec2(10, 9)) == agentA
    check env.getThing(ivec2(10, 10)) == agentB

suite "Mechanics - Combat":
  test "attack kills enemy and drops corpse inventory":
    let env = makeEmptyEnv()
    let attacker = addAgentAt(env, 0, ivec2(10, 10))
    let defender = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 9))
    defender.hp = 1
    setInv(defender, ItemWood, 2)

    env.stepAction(attacker.agentId, 2'u8, dirIndex(attacker.pos, defender.pos))

    let corpse = env.getBackgroundThing(ivec2(10, 9))
    check corpse.kind == Corpse
    check getInv(corpse, ItemWood) == 2
    check env.terminated[defender.agentId] == 1.0

  test "armor absorbs damage before hp":
    let env = makeEmptyEnv()
    let attacker = addAgentAt(env, 0, ivec2(10, 10))
    let defender = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 9))
    defender.inventoryArmor = 2
    defender.hp = 5

    env.stepAction(attacker.agentId, 2'u8, dirIndex(attacker.pos, defender.pos))

    check defender.inventoryArmor == 1
    check defender.hp == 5

  test "class bonus damage applies on counter hit":
    let env = makeEmptyEnv()
    let archer = addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitArcher)
    let infantry = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 9), unitClass = UnitManAtArms)
    let cavalry = addAgentAt(env, MapAgentsPerTeam * 2, ivec2(12, 10), unitClass = UnitScout)
    archer.attackDamage = 1
    infantry.hp = 5
    cavalry.hp = 5

    env.stepAction(archer.agentId, 2'u8, dirIndex(archer.pos, infantry.pos))

    check infantry.hp == 4
    env.stepAction(archer.agentId, 2'u8, dirIndex(archer.pos, cavalry.pos))
    check cavalry.hp == 4

  test "spear attack hits at range and consumes spear":
    let env = makeEmptyEnv()
    let attacker = addAgentAt(env, 0, ivec2(10, 10))
    attacker.inventorySpear = 1
    let defender = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 8))
    defender.hp = 2

    env.stepAction(attacker.agentId, 2'u8, dirIndex(attacker.pos, defender.pos))

    check attacker.inventorySpear == 0
    check defender.hp == 1

  test "monk heals adjacent ally":
    let env = makeEmptyEnv()
    let monk = addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitMonk)
    let ally = addAgentAt(env, 1, ivec2(10, 9))
    ally.hp = 1

    env.stepAction(monk.agentId, 2'u8, dirIndex(monk.pos, ally.pos))

    check ally.hp == 3

  test "guard tower attacks enemy in range":
    let env = makeEmptyEnv()
    discard addBuilding(env, GuardTower, ivec2(10, 10), 0)
    let enemyId = MapAgentsPerTeam
    let enemy = addAgentAt(env, enemyId, ivec2(10, 13))
    let startHp = enemy.hp

    env.stepAction(enemyId, 0'u8, 0)
    check enemy.hp < startHp

  test "castle attacks enemy in range":
    let env = makeEmptyEnv()
    discard addBuilding(env, Castle, ivec2(10, 10), 0)
    let enemyId = MapAgentsPerTeam
    let enemy = addAgentAt(env, enemyId, ivec2(10, 15))
    let startHp = enemy.hp

    env.stepAction(enemyId, 0'u8, 0)
    check enemy.hp < startHp

suite "Mechanics - Training":
  test "siege workshop trains battering ram":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    discard addBuilding(env, SiegeWorkshop, ivec2(10, 9), 0)
    env.teamStockpiles[0].counts[ResourceWood] = 10
    env.teamStockpiles[0].counts[ResourceStone] = 10

    env.stepAction(agent.agentId, 3'u8, dirIndex(agent.pos, ivec2(10, 9)))
    check agent.unitClass == UnitBatteringRam

  test "mangonel workshop trains mangonel":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    discard addBuilding(env, MangonelWorkshop, ivec2(10, 9), 0)
    env.teamStockpiles[0].counts[ResourceWood] = 10
    env.teamStockpiles[0].counts[ResourceStone] = 10

    env.stepAction(agent.agentId, 3'u8, dirIndex(agent.pos, ivec2(10, 9)))
    check agent.unitClass == UnitMangonel

  test "archery range trains archer":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    discard addBuilding(env, ArcheryRange, ivec2(10, 9), 0)
    env.teamStockpiles[0].counts[ResourceWood] = 10
    env.teamStockpiles[0].counts[ResourceGold] = 10

    env.stepAction(agent.agentId, 3'u8, dirIndex(agent.pos, ivec2(10, 9)))
    check agent.unitClass == UnitArcher

  test "stable trains scout":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    discard addBuilding(env, Stable, ivec2(10, 9), 0)
    env.teamStockpiles[0].counts[ResourceFood] = 10

    env.stepAction(agent.agentId, 3'u8, dirIndex(agent.pos, ivec2(10, 9)))
    check agent.unitClass == UnitScout

  test "castle trains knight":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    discard addBuilding(env, Castle, ivec2(10, 9), 0)
    env.teamStockpiles[0].counts[ResourceFood] = 10
    env.teamStockpiles[0].counts[ResourceGold] = 10

    env.stepAction(agent.agentId, 3'u8, dirIndex(agent.pos, ivec2(10, 9)))
    check agent.unitClass == UnitKnight

suite "Mechanics - Siege":
  test "siege damage multiplier applies vs walls":
    let env = makeEmptyEnv()
    let attacker = addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitBatteringRam)
    applyUnitClass(attacker, UnitBatteringRam)
    let wall = Thing(kind: Wall, pos: ivec2(10, 9), teamId: MapAgentsPerTeam)
    wall.hp = WallMaxHp
    wall.maxHp = WallMaxHp
    env.add(wall)

    env.stepAction(attacker.agentId, 2'u8, dirIndex(attacker.pos, wall.pos))
    check wall.hp == WallMaxHp - (BatteringRamAttackDamage * SiegeStructureMultiplier)

  test "mangonel extended attack hits multiple targets":
    let env = makeEmptyEnv()
    let mangonel = addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitMangonel)
    let enemyA = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 8))
    let enemyB = addAgentAt(env, MapAgentsPerTeam + 1, ivec2(9, 8))
    let enemyC = addAgentAt(env, MapAgentsPerTeam + 2, ivec2(11, 8))
    let hpA = enemyA.hp
    let hpB = enemyB.hp
    let hpC = enemyC.hp

    env.stepAction(mangonel.agentId, 2'u8, dirIndex(mangonel.pos, enemyA.pos))
    check enemyA.hp < hpA
    check enemyB.hp < hpB
    check enemyC.hp < hpC

  test "siege prefers attacking blocking wall":
    let env = makeEmptyEnv()
    let ram = addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitBatteringRam)
    let wall = Thing(kind: Wall, pos: ivec2(10, 9), teamId: MapAgentsPerTeam)
    wall.hp = WallMaxHp
    wall.maxHp = WallMaxHp
    env.add(wall)
    let enemy = addAgentAt(env, MapAgentsPerTeam, ivec2(9, 10))
    let enemyHp = enemy.hp

    env.stepAction(ram.agentId, 2'u8, dirIndex(ram.pos, wall.pos))
    check wall.hp < WallMaxHp
    check enemy.hp == enemyHp

suite "AI - Gatherer":
  test "drops off carried wood":
    let env = makeEmptyEnv()
    let controller = newController(1)
    let altarPos = ivec2(10, 10)
    discard addBuilding(env, TownCenter, altarPos, 0)
    let agent = addAgentAt(env, 0, ivec2(10, 11), homeAltar = altarPos)
    setInv(agent, ItemWood, 1)

    let (verb, arg) = decodeAction(controller.decideAction(env, 0))
    check verb == 3
    check arg == dirIndex(agent.pos, altarPos)

  test "task hearts uses magma when carrying gold":
    let env = makeEmptyEnv()
    let controller = newController(2)
    let altarPos = ivec2(12, 10)
    discard addAltar(env, altarPos, 0, 0)
    let agent = addAgentAt(env, 0, ivec2(10, 10), homeAltar = altarPos)
    setInv(agent, ItemGold, 1)
    discard addBuilding(env, Magma, ivec2(10, 9), 0)

    let (verb, _) = decodeAction(controller.decideAction(env, 0))
    check verb == 3

  const gathererCases = [
    (name: "task food uses wheat", seed: 3, kind: Wheat, item: ItemWheat, target: ResourceFood),
    (name: "task wood uses tree", seed: 4, kind: Tree, item: ItemWood, target: ResourceWood),
    (name: "task stone uses stone", seed: 5, kind: Stone, item: ItemStone, target: ResourceStone),
    (name: "task gold uses gold", seed: 6, kind: Gold, item: ItemGold, target: ResourceGold)
  ]

  for gathererCase in gathererCases:
    test gathererCase.name:
      let env = makeEmptyEnv()
      let controller = newController(gathererCase.seed)
      let altarPos = ivec2(10, 10)
      discard addAltar(env, altarPos, 0, 12)
      discard addResource(env, gathererCase.kind, ivec2(10, 9), gathererCase.item, 3)
      discard addAgentAt(env, 0, ivec2(10, 10), homeAltar = altarPos)
      fillStockpile(env, 0, 5)
      setStockpile(env, 0, gathererCase.target, 0)

      let (verb, _) = decodeAction(controller.decideAction(env, 0))
      check verb == 3

suite "AI - Builder":
  test "drops off carried resources":
    let env = makeEmptyEnv()
    let controller = newController(7)
    let tcPos = ivec2(10, 10)
    discard addBuilding(env, TownCenter, tcPos, 0)
    let agent = addAgentAt(env, 2, ivec2(10, 11), homeAltar = tcPos)
    setInv(agent, ItemWood, 1)

    let (verb, arg) = decodeAction(controller.decideAction(env, 2))
    check verb == 3
    check arg == dirIndex(agent.pos, tcPos)

  test "builds core economy building when missing":
    let env = makeEmptyEnv()
    let controller = newController(8)
    discard addAgentAt(env, 2, ivec2(10, 10))
    fillStockpile(env, 0, 50)

    let (verb, arg) = decodeAction(controller.decideAction(env, 2))
    check verb == 8
    check arg == buildIndexFor(Granary)

  test "builds production building after core economy":
    let env = makeEmptyEnv()
    let controller = newController(9)
    addBuildings(env, 0, ivec2(12, 10), @[Granary, LumberCamp, Quarry, MiningCamp])
    discard addAgentAt(env, 2, ivec2(10, 10))
    fillStockpile(env, 0, 50)

    let (verb, arg) = decodeAction(controller.decideAction(env, 2))
    check verb == 8
    check arg == buildIndexFor(WeavingLoom)

  test "builds wall ring before tech buildings":
    let env = makeEmptyEnv()
    let controller = newController(14)
    let basePos = ivec2(10, 10)
    addBuildings(env, 0, ivec2(12, 10), @[Granary, LumberCamp, Quarry, MiningCamp])
    env.currentStep = 1
    discard addAgentAt(env, 2, ivec2(3, 5), homeAltar = basePos)
    fillStockpile(env, 0, 50)

    let (verb, arg) = decodeAction(controller.decideAction(env, 2))
    check verb == 8
    check arg == BuildIndexWall

  test "builds clay oven after weaving loom":
    let env = makeEmptyEnv()
    let controller = newController(14)
    addBuildings(env, 0, ivec2(12, 10),
      @[Granary, LumberCamp, Quarry, MiningCamp, WeavingLoom])
    discard addAgentAt(env, 2, ivec2(10, 10))
    fillStockpile(env, 0, 50)

    let (verb, arg) = decodeAction(controller.decideAction(env, 2))
    check verb == 8
    check arg == buildIndexFor(ClayOven)

  test "builds blacksmith after clay oven":
    let env = makeEmptyEnv()
    let controller = newController(15)
    addBuildings(env, 0, ivec2(12, 10),
      @[Granary, LumberCamp, Quarry, MiningCamp, WeavingLoom, ClayOven])
    discard addAgentAt(env, 2, ivec2(10, 10))
    fillStockpile(env, 0, 50)

    let (verb, arg) = decodeAction(controller.decideAction(env, 2))
    check verb == 8
    check arg == buildIndexFor(Blacksmith)

  test "builds barracks after blacksmith":
    let env = makeEmptyEnv()
    let controller = newController(16)
    addBuildings(env, 0, ivec2(12, 10),
      @[Granary, LumberCamp, Quarry, MiningCamp, WeavingLoom, ClayOven, Blacksmith])
    discard addAgentAt(env, 2, ivec2(10, 10))
    fillStockpile(env, 0, 50)

    let (verb, arg) = decodeAction(controller.decideAction(env, 2))
    check verb == 8
    check arg == buildIndexFor(Barracks)

  test "builds siege workshop after stable":
    let env = makeEmptyEnv()
    let controller = newController(17)
    addBuildings(env, 0, ivec2(12, 10), @[
      Granary, LumberCamp, Quarry, MiningCamp,
      WeavingLoom, ClayOven, Blacksmith,
      Barracks, ArcheryRange, Stable
    ])
    discard addAgentAt(env, 2, ivec2(10, 10))
    fillStockpile(env, 0, 50)

    let (verb, arg) = decodeAction(controller.decideAction(env, 2))
    check verb == 8
    check arg == buildIndexFor(SiegeWorkshop)

  test "builds castle after outpost":
    let env = makeEmptyEnv()
    let controller = newController(18)
    addBuildings(env, 0, ivec2(12, 10), @[
      Granary, LumberCamp, Quarry, MiningCamp,
      WeavingLoom, ClayOven, Blacksmith,
      Barracks, ArcheryRange, Stable, SiegeWorkshop, MangonelWorkshop, Outpost
    ])
    discard addAgentAt(env, 2, ivec2(10, 10))
    fillStockpile(env, 0, 50)

    let (verb, arg) = decodeAction(controller.decideAction(env, 2))
    check verb == 8
    check arg == buildIndexFor(Castle)

  test "builds house when one house of room left":
    let env = makeEmptyEnv()
    let controller = newController(12)
    let basePos = ivec2(10, 10)
    discard addBuilding(env, House, ivec2(8, 8), 0)
    discard addBuilding(env, House, ivec2(12, 8), 0)
    discard addAgentAt(env, 0, ivec2(10, 10), homeAltar = basePos)
    discard addAgentAt(env, 1, ivec2(10, 11), homeAltar = basePos)
    discard addAgentAt(env, 2, ivec2(1, 0), homeAltar = basePos)
    discard addAgentAt(env, 3, ivec2(11, 10), homeAltar = basePos)
    setStockpile(env, 0, ResourceWood, 10)

    let (verb, arg) = decodeAction(controller.decideAction(env, 2))
    check verb == 1 or (verb == 8 and arg == buildIndexFor(House))

  test "builds house at cap using team-only pop cap":
    let env = makeEmptyEnv()
    let controller = newController(13)
    let basePos = ivec2(10, 10)
    discard addBuilding(env, House, ivec2(8, 8), 0)
    discard addAgentAt(env, 0, ivec2(10, 10), homeAltar = basePos)
    discard addAgentAt(env, 2, ivec2(1, 0), homeAltar = basePos)
    setStockpile(env, 0, ResourceWood, 10)
    discard addBuilding(env, House, ivec2(20, 20), 1)
    discard addBuilding(env, House, ivec2(22, 20), 1)
    discard addBuilding(env, House, ivec2(24, 20), 1)

    let (verb, arg) = decodeAction(controller.decideAction(env, 2))
    check verb == 1 or (verb == 8 and arg == buildIndexFor(House))

suite "AI - Fighter":
  test "villager fighter builds divider door when enemy nearby":
    let env = makeEmptyEnv()
    let controller = newController(10)
    let basePos = ivec2(10, 10)
    discard addAltar(env, basePos, 0, 12)
    let agentPos = ivec2(10, 17)
    let enemyPos = ivec2(10, 26)
    discard addAgentAt(env, 4, agentPos, homeAltar = basePos, orientation = S)
    discard addAgentAt(env, MapAgentsPerTeam, enemyPos)
    setStockpile(env, 0, ResourceWood, 10)

    let (verb, arg) = decodeAction(controller.decideAction(env, 4))
    check verb == 8
    check arg == BuildIndexDoor

  test "places lantern when target available":
    let env = makeEmptyEnv()
    let controller = newController(11)
    discard addBuilding(env, TownCenter, ivec2(10, 10), 0)
    let agent = addAgentAt(env, 4, ivec2(10, 12))
    setInv(agent, ItemLantern, 1)

    let (verb, _) = decodeAction(controller.decideAction(env, 4))
    check verb == 6

suite "AI - Combat Behaviors":
  test "gatherer flees from nearby wolf":
    let env = makeEmptyEnv()
    let controller = newController(20)
    let basePos = ivec2(10, 10)
    discard addAltar(env, basePos, 0, 10)
    let agent = addAgentAt(env, 0, ivec2(15, 10), homeAltar = basePos)
    # Add wolf within flee radius (5 tiles)
    let wolf = Thing(kind: Wolf, pos: ivec2(14, 10), packId: 0, hp: WolfMaxHp, maxHp: WolfMaxHp)
    env.add(wolf)
    env.wolfPackCounts.add(1)
    env.wolfPackSumX.add(wolf.pos.x)
    env.wolfPackSumY.add(wolf.pos.y)
    env.wolfPackDrift.add(ivec2(0, 0))
    env.wolfPackTargets.add(ivec2(-1, -1))
    env.wolfPackLeaders.add(wolf)
    wolf.isPackLeader = true

    let (verb, arg) = decodeAction(controller.decideAction(env, 0))
    # Agent should move (verb 1) away from wolf
    check verb == 1
    # Direction 3 is East, 5 is NE, 7 is SE - all move away from wolf at west
    check arg.int in {3, 5, 7}

  test "wolf pack scatters when leader killed":
    let env = makeEmptyEnv()
    let attacker = addAgentAt(env, 0, ivec2(10, 10))
    attacker.attackDamage = 10  # One-hit kill
    # Create pack with leader and two followers
    let leaderPos = ivec2(10, 9)
    let leader = Thing(kind: Wolf, pos: leaderPos, packId: 0, hp: 1, maxHp: WolfMaxHp, isPackLeader: true)
    let follower1 = Thing(kind: Wolf, pos: ivec2(10, 8), packId: 0, hp: WolfMaxHp, maxHp: WolfMaxHp)
    let follower2 = Thing(kind: Wolf, pos: ivec2(11, 9), packId: 0, hp: WolfMaxHp, maxHp: WolfMaxHp)
    env.add(leader)
    env.add(follower1)
    env.add(follower2)
    env.wolfPackCounts.add(3)
    env.wolfPackSumX.add(leader.pos.x + follower1.pos.x + follower2.pos.x)
    env.wolfPackSumY.add(leader.pos.y + follower1.pos.y + follower2.pos.y)
    env.wolfPackDrift.add(ivec2(0, 0))
    env.wolfPackTargets.add(ivec2(-1, -1))
    env.wolfPackLeaders.add(leader)

    # Followers not scattered before leader death
    check follower1.scatteredSteps == 0
    check follower2.scatteredSteps == 0

    # Kill the leader
    env.stepAction(attacker.agentId, 2'u8, dirIndex(attacker.pos, leaderPos))

    # Followers should now be scattered (may have decremented by 1 during wolf step)
    check follower1.scatteredSteps >= ScatteredDuration - 1
    check follower2.scatteredSteps >= ScatteredDuration - 1
    # Leader should be removed
    check env.getThing(leaderPos) == nil or env.getThing(leaderPos).kind != Wolf
