import std/unittest
import environment
import external
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

suite "Mechanics":
  test "tree to stump and stump depletes":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    discard addResource(env, Pine, ivec2(10, 9), ItemWood, ResourceNodeInitial)

    agent.orientation = Orientation(dirIndex(agent.pos, ivec2(10, 9)))
    env.useAction(0, agent)
    let stump = env.getThing(ivec2(10, 9))
    check stump.kind == Stump
    check getInv(stump, ItemWood) == ResourceNodeInitial - 1
    check agent.inventoryWood == 1

    setInv(stump, ItemWood, 1)
    agent.orientation = Orientation(dirIndex(agent.pos, ivec2(10, 9)))
    env.useAction(0, agent)
    check env.getThing(ivec2(10, 9)) == nil

  test "wheat depletes and removes":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    discard addResource(env, Wheat, ivec2(10, 9), ItemWheat, 2)

    agent.orientation = Orientation(dirIndex(agent.pos, ivec2(10, 9)))
    env.useAction(0, agent)
    let wheat = env.getThing(ivec2(10, 9))
    check wheat.kind == Wheat
    check getInv(wheat, ItemWheat) == 1

    agent.orientation = Orientation(dirIndex(agent.pos, ivec2(10, 9)))
    env.useAction(0, agent)
    check env.getThing(ivec2(10, 9)) == nil

  test "stone and gold deplete":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    discard addResource(env, Stone, ivec2(10, 9), ItemStone, 1)
    discard addResource(env, Gold, ivec2(11, 10), ItemGold, 1)
    let goldNode = env.getThing(ivec2(11, 10))
    check getInv(goldNode, ItemGold) == 1

    agent.orientation = Orientation(dirIndex(agent.pos, ivec2(10, 9)))
    env.useAction(0, agent)
    check env.getThing(ivec2(10, 9)) == nil

    agent.inventory = emptyInventory()
    agent.orientation = Orientation(dirIndex(agent.pos, ivec2(11, 10)))
    env.useAction(0, agent)
    check env.getThing(ivec2(11, 10)) == nil

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
    discard addResource(env, Pine, ivec2(10, 9), ItemWood, 3)
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
    discard addBuilding(env, Granary, ivec2(12, 10), 0)
    discard addBuilding(env, LumberCamp, ivec2(13, 10), 0)
    discard addBuilding(env, Quarry, ivec2(14, 10), 0)
    discard addBuilding(env, MiningCamp, ivec2(15, 10), 0)
    discard addAgentAt(env, 2, ivec2(10, 10))
    setStockpile(env, 0, ResourceFood, 50)
    setStockpile(env, 0, ResourceWood, 50)
    setStockpile(env, 0, ResourceStone, 50)
    setStockpile(env, 0, ResourceGold, 50)

    let action = controller.decideAction(env, 2)
    let (verb, arg) = decodeAction(action)
    check verb == 8
    check arg == buildIndexFor(WeavingLoom)

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
