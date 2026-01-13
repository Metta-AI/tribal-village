import std/unittest
import environment
import agent_control
import common
import types
import items
import terrain

proc decodeAction(action: uint8): tuple[verb: int, arg: int] =
  (action.int div ActionArgumentCount, action.int mod ActionArgumentCount)

proc dirIndex(fromPos, toPos: IVec2): int =
  let dx = toPos.x - fromPos.x
  let dy = toPos.y - fromPos.y
  let sx = if dx > 0: 1'i32 elif dx < 0: -1'i32 else: 0'i32
  let sy = if dy > 0: 1'i32 elif dy < 0: -1'i32 else: 0'i32
  if sx == 0'i32 and sy == -1'i32: return 0
  if sx == 0'i32 and sy == 1'i32: return 1
  if sx == -1'i32 and sy == 0'i32: return 2
  if sx == 1'i32 and sy == 0'i32: return 3
  if sx == -1'i32 and sy == -1'i32: return 4
  if sx == 1'i32 and sy == -1'i32: return 5
  if sx == -1'i32 and sy == 1'i32: return 6
  if sx == 1'i32 and sy == 1'i32: return 7
  0

proc makeEmptyEnv(): Environment =
  result = newEnvironment()
  result.currentStep = 0
  result.shouldReset = false
  result.things.setLen(0)
  result.agents.setLen(0)
  result.stats.setLen(0)
  result.thingsByKind = default(array[ThingKind, seq[Thing]])
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      result.grid[x][y] = nil
      result.overlayGrid[x][y] = nil
      result.terrain[x][y] = TerrainEmpty
      result.biomes[x][y] = BiomeBaseType
      result.baseTintColors[x][y] = BaseTileColorDefault
      result.computedTintColors[x][y] = TileColor(r: 0, g: 0, b: 0, intensity: 0)
  result.teamStockpiles = default(array[MapRoomObjectsHouses, TeamStockpile])
  result.actionTintPositions.setLen(0)
  result.activeTiles.positions.setLen(0)
  result.tumorActiveTiles.positions.setLen(0)
  result.altarColors.clear()
  result.teamColors.setLen(0)
  result.agentColors.setLen(0)

proc addAgentAt(env: Environment, agentId: int, pos: IVec2,
                homeAltar: IVec2 = ivec2(-1, -1), unitClass: AgentUnitClass = UnitVillager,
                orientation: Orientation = N): Thing =
  while env.agents.len <= agentId:
    let nextId = env.agents.len
    let isTarget = nextId == agentId
    let agent = Thing(
      kind: Agent,
      pos: (if isTarget: pos else: ivec2(-1, -1)),
      agentId: nextId,
      orientation: (if isTarget: orientation else: N),
      inventory: emptyInventory(),
      hp: (if isTarget: AgentMaxHp else: 0),
      maxHp: AgentMaxHp,
      attackDamage: 1,
      unitClass: (if isTarget: unitClass else: UnitVillager),
      homeAltar: (if isTarget: homeAltar else: ivec2(-1, -1))
    )
    env.add(agent)
    env.terminated[nextId] = (if isTarget: 0.0 else: 1.0)
    if isTarget:
      result = agent

proc addBuilding(env: Environment, kind: ThingKind, pos: IVec2, teamId: int): Thing =
  let thing = Thing(kind: kind, pos: pos, teamId: teamId)
  env.add(thing)
  thing

proc addBuildings(env: Environment, teamId: int, start: IVec2, kinds: openArray[ThingKind]) =
  var dx = 0
  for kind in kinds:
    discard addBuilding(env, kind, start + ivec2(dx.int32, 0), teamId)
    inc dx

proc addAltar(env: Environment, pos: IVec2, teamId: int, hearts: int): Thing =
  let altar = Thing(kind: Altar, pos: pos, teamId: teamId)
  altar.inventory = emptyInventory()
  altar.hearts = hearts
  env.add(altar)
  altar

proc addResource(env: Environment, kind: ThingKind, pos: IVec2, key: ItemKey,
                 amount: int = ResourceNodeInitial): Thing =
  let node = Thing(kind: kind, pos: pos)
  node.inventory = emptyInventory()
  if key != ItemNone and amount > 0:
    setInv(node, key, amount)
  env.add(node)
  node

proc setStockpile(env: Environment, teamId: int, res: StockpileResource, count: int) =
  env.teamStockpiles[teamId].counts[res] = count

proc stepAction(env: Environment, agentId: int, verb: uint8, argument: int) =
  while env.agents.len < MapAgents:
    let nextId = env.agents.len
    let agent = Thing(
      kind: Agent,
      pos: ivec2(-1, -1),
      agentId: nextId,
      orientation: N,
      inventory: emptyInventory(),
      hp: 0,
      maxHp: AgentMaxHp,
      attackDamage: 1,
      unitClass: UnitVillager,
      homeAltar: ivec2(-1, -1)
    )
    env.add(agent)
    env.terminated[nextId] = 1.0
  var actions: array[MapAgents, uint8]
  for i in 0 ..< MapAgents:
    actions[i] = 0
  actions[agentId] = encodeAction(verb, argument.uint8)
  env.step(addr actions)

suite "Mechanics":
  test "tree to stump and stump depletes":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    discard addResource(env, Tree, ivec2(10, 9), ItemWood, ResourceNodeInitial)

    let treeDir = dirIndex(agent.pos, ivec2(10, 9))
    env.stepAction(0, 3'u8, treeDir)
    let stump = env.getThing(ivec2(10, 9))
    check stump.kind == Stump
    check getInv(stump, ItemWood) == ResourceNodeInitial - 1
    check agent.inventoryWood == 1

    setInv(stump, ItemWood, 1)
    let stumpDir = dirIndex(agent.pos, ivec2(10, 9))
    env.stepAction(0, 3'u8, stumpDir)
    check env.getThing(ivec2(10, 9)) == nil

  test "wheat depletes and removes":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    discard addResource(env, Wheat, ivec2(10, 9), ItemWheat, 2)

    let wheatDir = dirIndex(agent.pos, ivec2(10, 9))
    env.stepAction(0, 3'u8, wheatDir)
    let wheat = env.getOverlayThing(ivec2(10, 9))
    check wheat.kind == Stubble
    check getInv(wheat, ItemWheat) == 1

    env.stepAction(0, 3'u8, wheatDir)
    check env.getOverlayThing(ivec2(10, 9)) == nil

  test "stone and gold deplete":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    discard addResource(env, Stone, ivec2(10, 9), ItemStone, 1)
    discard addResource(env, Gold, ivec2(11, 10), ItemGold, 1)
    let goldNode = env.getThing(ivec2(11, 10))
    check getInv(goldNode, ItemGold) == 1

    let stoneDir = dirIndex(agent.pos, ivec2(10, 9))
    env.stepAction(0, 3'u8, stoneDir)
    check env.getThing(ivec2(10, 9)) == nil

    agent.inventory = emptyInventory()
    let goldDir = dirIndex(agent.pos, ivec2(11, 10))
    env.stepAction(0, 3'u8, goldDir)
    check env.getThing(ivec2(11, 10)) == nil

  test "attack kills enemy and drops corpse inventory":
    let env = makeEmptyEnv()
    let attacker = addAgentAt(env, 0, ivec2(10, 10))
    let defender = addAgentAt(env, MapAgentsPerVillage, ivec2(10, 9))
    defender.hp = 1
    setInv(defender, ItemWood, 2)

    let attackDir = dirIndex(attacker.pos, defender.pos)
    env.stepAction(attacker.agentId, 2'u8, attackDir)

    let corpse = env.getOverlayThing(ivec2(10, 9))
    check corpse.kind == Corpse
    check getInv(corpse, ItemWood) == 2
    check env.terminated[defender.agentId] == 1.0

  test "armor absorbs damage before hp":
    let env = makeEmptyEnv()
    let attacker = addAgentAt(env, 0, ivec2(10, 10))
    let defender = addAgentAt(env, MapAgentsPerVillage, ivec2(10, 9))
    defender.inventoryArmor = 2
    defender.hp = 5

    let attackDir = dirIndex(attacker.pos, defender.pos)
    env.stepAction(attacker.agentId, 2'u8, attackDir)

    check defender.inventoryArmor == 1
    check defender.hp == 5

  test "spear attack hits at range and consumes spear":
    let env = makeEmptyEnv()
    let attacker = addAgentAt(env, 0, ivec2(10, 10))
    attacker.inventorySpear = 1
    let defender = addAgentAt(env, MapAgentsPerVillage, ivec2(10, 8))
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

    check ally.hp == 2

  test "swap action updates positions":
    let env = makeEmptyEnv()
    let agentA = addAgentAt(env, 0, ivec2(10, 10))
    let agentB = addAgentAt(env, 1, ivec2(10, 9))

    env.stepAction(agentA.agentId, 4'u8, dirIndex(agentA.pos, agentB.pos))

    check agentA.pos == ivec2(10, 9)
    check agentB.pos == ivec2(10, 10)
    check env.getThing(ivec2(10, 9)) == agentA
    check env.getThing(ivec2(10, 10)) == agentB

  test "planting wheat consumes inventory and clears fertile":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    agent.inventoryWheat = 1
    let target = ivec2(10, 9)
    env.terrain[target.x][target.y] = Fertile

    env.stepAction(agent.agentId, 7'u8, dirIndex(agent.pos, target))

    let crop = env.getOverlayThing(target)
    check crop.kind == Wheat
    check getInv(crop, ItemWheat) == ResourceNodeInitial
    check agent.inventoryWheat == 0
    check env.terrain[target.x][target.y] == TerrainEmpty

suite "AI - Gatherer":
  test "drops off carried wood":
    let env = makeEmptyEnv()
    let controller = newController(1)
    let altarPos = ivec2(10, 10)
    discard addBuilding(env, TownCenter, altarPos, 0)
    let agent = addAgentAt(env, 0, ivec2(10, 11), homeAltar = altarPos)
    setInv(agent, ItemWood, 1)

    let action = controller.decideAction(env, 0)
    let (verb, arg) = decodeAction(action)
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

    let action = controller.decideAction(env, 0)
    let (verb, _) = decodeAction(action)
    check verb == 3

  test "task food uses wheat":
    let env = makeEmptyEnv()
    let controller = newController(3)
    let altarPos = ivec2(10, 10)
    discard addAltar(env, altarPos, 0, 12)
    discard addResource(env, Wheat, ivec2(10, 9), ItemWheat, 3)
    discard addAgentAt(env, 0, ivec2(10, 10), homeAltar = altarPos)
    setStockpile(env, 0, ResourceFood, 0)
    setStockpile(env, 0, ResourceWood, 5)
    setStockpile(env, 0, ResourceStone, 5)
    setStockpile(env, 0, ResourceGold, 5)

    let action = controller.decideAction(env, 0)
    let (verb, _) = decodeAction(action)
    check verb == 3

  test "task wood uses tree":
    let env = makeEmptyEnv()
    let controller = newController(4)
    let altarPos = ivec2(10, 10)
    discard addAltar(env, altarPos, 0, 12)
    discard addResource(env, Tree, ivec2(10, 9), ItemWood, 3)
    discard addAgentAt(env, 0, ivec2(10, 10), homeAltar = altarPos)
    setStockpile(env, 0, ResourceFood, 5)
    setStockpile(env, 0, ResourceWood, 0)
    setStockpile(env, 0, ResourceStone, 5)
    setStockpile(env, 0, ResourceGold, 5)

    let action = controller.decideAction(env, 0)
    let (verb, _) = decodeAction(action)
    check verb == 3

  test "task stone uses stone":
    let env = makeEmptyEnv()
    let controller = newController(5)
    let altarPos = ivec2(10, 10)
    discard addAltar(env, altarPos, 0, 12)
    discard addResource(env, Stone, ivec2(10, 9), ItemStone, 3)
    discard addAgentAt(env, 0, ivec2(10, 10), homeAltar = altarPos)
    setStockpile(env, 0, ResourceFood, 5)
    setStockpile(env, 0, ResourceWood, 5)
    setStockpile(env, 0, ResourceStone, 0)
    setStockpile(env, 0, ResourceGold, 5)

    let action = controller.decideAction(env, 0)
    let (verb, _) = decodeAction(action)
    check verb == 3

  test "task gold uses gold":
    let env = makeEmptyEnv()
    let controller = newController(6)
    let altarPos = ivec2(10, 10)
    discard addAltar(env, altarPos, 0, 12)
    discard addResource(env, Gold, ivec2(10, 9), ItemGold, 3)
    discard addAgentAt(env, 0, ivec2(10, 10), homeAltar = altarPos)
    setStockpile(env, 0, ResourceFood, 5)
    setStockpile(env, 0, ResourceWood, 5)
    setStockpile(env, 0, ResourceStone, 5)
    setStockpile(env, 0, ResourceGold, 0)

    let action = controller.decideAction(env, 0)
    let (verb, _) = decodeAction(action)
    check verb == 3

suite "AI - Builder":
  test "drops off carried resources":
    let env = makeEmptyEnv()
    let controller = newController(7)
    let tcPos = ivec2(10, 10)
    discard addBuilding(env, TownCenter, tcPos, 0)
    let agent = addAgentAt(env, 2, ivec2(10, 11), homeAltar = tcPos)
    setInv(agent, ItemWood, 1)

    let action = controller.decideAction(env, 2)
    let (verb, arg) = decodeAction(action)
    check verb == 3
    check arg == dirIndex(agent.pos, tcPos)

  test "builds core economy building when missing":
    let env = makeEmptyEnv()
    let controller = newController(8)
    discard addAgentAt(env, 2, ivec2(10, 10))
    setStockpile(env, 0, ResourceFood, 50)
    setStockpile(env, 0, ResourceWood, 50)
    setStockpile(env, 0, ResourceStone, 50)
    setStockpile(env, 0, ResourceGold, 50)

    let action = controller.decideAction(env, 2)
    let (verb, arg) = decodeAction(action)
    check verb == 8
    check arg == buildIndexFor(Granary)

  test "builds production building after core economy":
    let env = makeEmptyEnv()
    let controller = newController(9)
    addBuildings(env, 0, ivec2(12, 10), @[Granary, LumberCamp, Quarry, MiningCamp])
    discard addAgentAt(env, 2, ivec2(10, 10))
    setStockpile(env, 0, ResourceFood, 50)
    setStockpile(env, 0, ResourceWood, 50)
    setStockpile(env, 0, ResourceStone, 50)
    setStockpile(env, 0, ResourceGold, 50)

    let action = controller.decideAction(env, 2)
    let (verb, arg) = decodeAction(action)
    check verb == 8
    check arg == buildIndexFor(WeavingLoom)

  test "builds clay oven after weaving loom":
    let env = makeEmptyEnv()
    let controller = newController(14)
    let basePos = ivec2(10, 10)
    addBuildings(env, 0, ivec2(12, 10),
      @[Granary, LumberCamp, Quarry, MiningCamp, WeavingLoom])
    discard addAgentAt(env, 2, basePos, homeAltar = basePos)
    setStockpile(env, 0, ResourceFood, 50)
    setStockpile(env, 0, ResourceWood, 50)
    setStockpile(env, 0, ResourceStone, 50)
    setStockpile(env, 0, ResourceGold, 50)

    let action = controller.decideAction(env, 2)
    let (verb, arg) = decodeAction(action)
    check verb == 8
    check arg == buildIndexFor(ClayOven)

  test "builds blacksmith after clay oven":
    let env = makeEmptyEnv()
    let controller = newController(15)
    let basePos = ivec2(10, 10)
    addBuildings(env, 0, ivec2(12, 10),
      @[Granary, LumberCamp, Quarry, MiningCamp, WeavingLoom, ClayOven])
    discard addAgentAt(env, 2, basePos, homeAltar = basePos)
    setStockpile(env, 0, ResourceFood, 50)
    setStockpile(env, 0, ResourceWood, 50)
    setStockpile(env, 0, ResourceStone, 50)
    setStockpile(env, 0, ResourceGold, 50)

    let action = controller.decideAction(env, 2)
    let (verb, arg) = decodeAction(action)
    check verb == 8
    check arg == buildIndexFor(Blacksmith)

  test "builds barracks after blacksmith":
    let env = makeEmptyEnv()
    let controller = newController(16)
    let basePos = ivec2(10, 10)
    addBuildings(env, 0, ivec2(12, 10),
      @[Granary, LumberCamp, Quarry, MiningCamp, WeavingLoom, ClayOven, Blacksmith])
    discard addAgentAt(env, 2, basePos, homeAltar = basePos)
    setStockpile(env, 0, ResourceFood, 50)
    setStockpile(env, 0, ResourceWood, 50)
    setStockpile(env, 0, ResourceStone, 50)
    setStockpile(env, 0, ResourceGold, 50)

    let action = controller.decideAction(env, 2)
    let (verb, arg) = decodeAction(action)
    check verb == 8
    check arg == buildIndexFor(Barracks)

  test "builds siege workshop after stable":
    let env = makeEmptyEnv()
    let controller = newController(17)
    let basePos = ivec2(10, 10)
    addBuildings(env, 0, ivec2(12, 10), @[
      Granary, LumberCamp, Quarry, MiningCamp,
      WeavingLoom, ClayOven, Blacksmith,
      Barracks, ArcheryRange, Stable
    ])
    discard addAgentAt(env, 2, basePos, homeAltar = basePos)
    setStockpile(env, 0, ResourceFood, 50)
    setStockpile(env, 0, ResourceWood, 50)
    setStockpile(env, 0, ResourceStone, 50)
    setStockpile(env, 0, ResourceGold, 50)

    let action = controller.decideAction(env, 2)
    let (verb, arg) = decodeAction(action)
    check verb == 8
    check arg == buildIndexFor(SiegeWorkshop)

  test "builds castle after outpost":
    let env = makeEmptyEnv()
    let controller = newController(18)
    let basePos = ivec2(10, 10)
    addBuildings(env, 0, ivec2(12, 10), @[
      Granary, LumberCamp, Quarry, MiningCamp,
      WeavingLoom, ClayOven, Blacksmith,
      Barracks, ArcheryRange, Stable, SiegeWorkshop, Outpost
    ])
    discard addAgentAt(env, 2, basePos, homeAltar = basePos)
    setStockpile(env, 0, ResourceFood, 50)
    setStockpile(env, 0, ResourceWood, 50)
    setStockpile(env, 0, ResourceStone, 50)
    setStockpile(env, 0, ResourceGold, 50)

    let action = controller.decideAction(env, 2)
    let (verb, arg) = decodeAction(action)
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
    setStockpile(env, 0, ResourceWood, 10)

    var built = false
    for _ in 0 ..< 20:
      let action = controller.decideAction(env, 2)
      let (verb, arg) = decodeAction(action)
      if verb == 8 and arg == buildIndexFor(House):
        built = true
        break
      if verb == 1:
        env.stepAction(2, verb.uint8, arg)
        continue
      break
    check built

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

    var built = false
    for _ in 0 ..< 20:
      let action = controller.decideAction(env, 2)
      let (verb, arg) = decodeAction(action)
      if verb == 8 and arg == buildIndexFor(House):
        built = true
        break
      if verb == 1:
        env.stepAction(2, verb.uint8, arg)
        continue
      break
    check built

suite "AI - Fighter":
  test "villager fighter builds divider door when enemy nearby":
    let env = makeEmptyEnv()
    let controller = newController(10)
    let basePos = ivec2(10, 10)
    discard addAltar(env, basePos, 0, 12)
    let agentPos = ivec2(10, 17)
    let enemyPos = ivec2(10, 26)
    discard addAgentAt(env, 4, agentPos, homeAltar = basePos, orientation = S)
    discard addAgentAt(env, MapAgentsPerVillage, enemyPos)
    setStockpile(env, 0, ResourceWood, 10)

    let action = controller.decideAction(env, 4)
    let (verb, arg) = decodeAction(action)
    check verb == 8
    check arg == BuildIndexDoor

  test "places lantern when target available":
    let env = makeEmptyEnv()
    let controller = newController(11)
    discard addBuilding(env, TownCenter, ivec2(10, 10), 0)
    let agent = addAgentAt(env, 4, ivec2(10, 12))
    setInv(agent, ItemLantern, 1)

    let action = controller.decideAction(env, 4)
    let (verb, _) = decodeAction(action)
    check verb == 6
