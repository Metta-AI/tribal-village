import std/[algorithm, strutils, tables, sets], vmath, chroma
import entropy
import terrain, items, common, biome
import types, registry, balance, errors
export terrain, items, common
export types, registry, balance, errors
proc clear[T](s: var openarray[T]) =
  ## Zero out a contiguous buffer (arrays/openarrays) without reallocating.
  let p = cast[pointer](s[0].addr)
  zeroMem(p, s.len * sizeof(T))


{.push inline.}
proc updateObservations(
  env: Environment,
  layer: ObservationName,
  pos: IVec2,
  value: int
) =
  ## Ultra-optimized observation update - early bailout and minimal calculations
  let layerId = ord(layer)

  # Ultra-fast observation update with minimal calculations

  # Still need to check all agents but with optimized early exit
  let agentCount = env.agents.len
  for agentId in 0 ..< agentCount:
    if not isAgentAlive(env, env.agents[agentId]):
      continue
    let agentPos = env.agents[agentId].pos

    # Ultra-fast bounds check using compile-time constants
    let dx = pos.x - agentPos.x
    let dy = pos.y - agentPos.y
    if dx < -ObservationRadius or dx > ObservationRadius or
       dy < -ObservationRadius or dy > ObservationRadius:
      continue

    let x = dx + ObservationRadius
    let y = dy + ObservationRadius
    var agentLayer = addr env.observations[agentId][layerId]
    agentLayer[][x][y] = value.uint8
  env.observationsInitialized = true
{.pop.}

include "colors"

proc getInv*(thing: Thing, key: ItemKey): int


proc rebuildObservations*(env: Environment) =
  ## Recompute all observation layers from the current environment state when needed.
  env.observations.clear()
  env.observationsInitialized = false

  # Populate agent-centric layers (presence, orientation, inventory).
  for agent in env.agents:
    if agent.isNil:
      continue
    if not isAgentAlive(env, agent):
      continue
    if not isValidPos(agent.pos):
      continue
    let teamValue = getTeamId(agent.agentId) + 1
    env.updateObservations(AgentLayer, agent.pos, teamValue)
    env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
    env.updateObservations(AgentInventoryGoldLayer, agent.pos, getInv(agent, ItemGold))
    env.updateObservations(AgentInventoryStoneLayer, agent.pos, getInv(agent, ItemStone))
    env.updateObservations(AgentInventoryBarLayer, agent.pos, getInv(agent, ItemBar))
    env.updateObservations(AgentInventoryWaterLayer, agent.pos, getInv(agent, ItemWater))
    env.updateObservations(AgentInventoryWheatLayer, agent.pos, getInv(agent, ItemWheat))
    env.updateObservations(AgentInventoryWoodLayer, agent.pos, getInv(agent, ItemWood))
    env.updateObservations(AgentInventorySpearLayer, agent.pos, getInv(agent, ItemSpear))
    env.updateObservations(AgentInventoryLanternLayer, agent.pos, getInv(agent, ItemLantern))
    env.updateObservations(AgentInventoryArmorLayer, agent.pos, getInv(agent, ItemArmor))
    env.updateObservations(AgentInventoryBreadLayer, agent.pos, getInv(agent, ItemBread))
    env.updateObservations(AgentInventoryMeatLayer, agent.pos, getInv(agent, ItemMeat))
    env.updateObservations(AgentInventoryFishLayer, agent.pos, getInv(agent, ItemFish))
    env.updateObservations(AgentInventoryPlantLayer, agent.pos, getInv(agent, ItemPlant))

  # Populate environment object layers.
  for thing in env.things:
    if thing.isNil:
      continue
    case thing.kind
    of Agent:
      discard  # Already handled above.
    of Wall:
      env.updateObservations(WallLayer, thing.pos, 1)
    of Tree:
      discard  # No dedicated observation layer for trees.
    of Magma:
      env.updateObservations(MagmaLayer, thing.pos, 1)
    of Altar:
      env.updateObservations(altarLayer, thing.pos, 1)
      env.updateObservations(altarHeartsLayer, thing.pos, getInv(thing, ItemHearts))
    of Spawner:
      discard  # No dedicated observation layer for spawners.
    of Tumor:
      env.updateObservations(AgentLayer, thing.pos, 255)
    else:
      discard

  env.observationsInitialized = true

{.push inline.}
proc getThing*(env: Environment, pos: IVec2): Thing =
  if not isValidPos(pos):
    return nil
  return env.grid[pos.x][pos.y]

proc getOverlayThing*(env: Environment, pos: IVec2): Thing =
  if not isValidPos(pos):
    return nil
  return env.overlayGrid[pos.x][pos.y]

proc isEmpty*(env: Environment, pos: IVec2): bool =
  if not isValidPos(pos):
    return false
  return isNil(env.grid[pos.x][pos.y])

proc hasDoor*(env: Environment, pos: IVec2): bool =
  if not isValidPos(pos):
    return false
  let door = env.overlayGrid[pos.x][pos.y]
  return not isNil(door) and door.kind == Door

proc canAgentPassDoor*(env: Environment, agent: Thing, pos: IVec2): bool =
  if not env.hasDoor(pos):
    return true
  let door = env.overlayGrid[pos.x][pos.y]
  return door.teamId == getTeamId(agent.agentId)
{.pop.}

proc isBuildableTerrain*(terrain: TerrainType): bool {.inline.} =
  terrain in BuildableTerrain

proc canPlaceBuilding*(env: Environment, pos: IVec2): bool {.inline.} =
  isValidPos(pos) and env.isEmpty(pos) and isNil(env.getOverlayThing(pos)) and not env.hasDoor(pos) and
    not isTileFrozen(pos, env) and isBuildableTerrain(env.terrain[pos.x][pos.y])

proc canLayRoad*(env: Environment, pos: IVec2): bool {.inline.} =
  isValidPos(pos) and env.isEmpty(pos) and isNil(env.getOverlayThing(pos)) and not env.hasDoor(pos) and
    env.terrain[pos.x][pos.y] in BuildableTerrain

proc resetTileColor*(env: Environment, pos: IVec2) =
  ## Clear dynamic tint overlays for a tile
  env.computedTintColors[pos.x][pos.y] = TileColor(r: 0, g: 0, b: 0, intensity: 0)

include "inventory"

# Build craft recipes after registry is available.
CraftRecipes = initCraftRecipesBase()
appendBuildingRecipes(CraftRecipes)

proc giveItem(env: Environment, agent: Thing, key: ItemKey, count: int = 1): bool =
  if count <= 0:
    return false
  if isStockpileResourceKey(key):
    var total = 0
    for invKey, invCount in agent.inventory.pairs:
      if invCount > 0 and isStockpileResourceKey(invKey):
        total += invCount
    if total + count > ResourceCarryCapacity:
      return false
  else:
    if getInv(agent, key) + count > MapObjectAgentMaxInventory:
      return false
  setInv(agent, key, getInv(agent, key) + count)
  env.updateAgentInventoryObs(agent, key)
  true

proc useStorageBuilding(env: Environment, agent: Thing, storage: Thing, allowed: openArray[ItemKey]): bool =
  if storage.inventory.len > 0:
    var storedKey = ItemNone
    var storedCount = 0
    for key, count in storage.inventory.pairs:
      if count > 0:
        storedKey = key
        storedCount = count
        break
    if storedKey.len == 0:
      return false
    if allowed.len > 0:
      var allowedMatch = false
      for allowedKey in allowed:
        if storedKey == allowedKey:
          allowedMatch = true
          break
      if not allowedMatch:
        return false
    let agentCount = getInv(agent, storedKey)
    let storageSpace = max(0, storage.barrelCapacity - storedCount)
    if agentCount > 0 and storageSpace > 0:
      let moved = min(agentCount, storageSpace)
      setInv(agent, storedKey, agentCount - moved)
      setInv(storage, storedKey, storedCount + moved)
      env.updateAgentInventoryObs(agent, storedKey)
      return true
    let capacityLeft =
      if isStockpileResourceKey(storedKey):
        block:
          var total = 0
          for invKey, invCount in agent.inventory.pairs:
            if invCount > 0 and isStockpileResourceKey(invKey):
              total += invCount
          max(0, ResourceCarryCapacity - total)
      else:
        max(0, MapObjectAgentMaxInventory - agentCount)
    if capacityLeft > 0:
      let moved = min(storedCount, capacityLeft)
      if moved > 0:
        setInv(agent, storedKey, agentCount + moved)
        let remaining = storedCount - moved
        setInv(storage, storedKey, remaining)
        env.updateAgentInventoryObs(agent, storedKey)
        return true
    return false

  var choiceKey = ItemNone
  var choiceCount = 0
  if allowed.len == 0:
    for key, count in agent.inventory.pairs:
      if count > choiceCount:
        choiceKey = key
        choiceCount = count
  else:
    for key in allowed:
      let count = getInv(agent, key)
      if count > choiceCount:
        choiceKey = key
        choiceCount = count
  if choiceCount > 0 and choiceKey != ItemNone:
    let moved = min(choiceCount, storage.barrelCapacity)
    setInv(agent, choiceKey, choiceCount - moved)
    setInv(storage, choiceKey, moved)
    env.updateAgentInventoryObs(agent, choiceKey)
    return true
  false

proc useDropoffBuilding(env: Environment, agent: Thing, allowed: set[StockpileResource]): bool =
  let teamId = getTeamId(agent.agentId)
  var depositKeys: seq[ItemKey] = @[]
  for key, count in agent.inventory.pairs:
    if count <= 0:
      continue
    if not isStockpileResourceKey(key):
      continue
    let res = stockpileResourceForItem(key)
    if res in allowed:
      depositKeys.add(key)
  if depositKeys.len == 0:
    return false
  for key in depositKeys:
    let count = getInv(agent, key)
    if count <= 0:
      continue
    let res = stockpileResourceForItem(key)
    env.addToStockpile(teamId, res, count)
    setInv(agent, key, 0)
    env.updateAgentInventoryObs(agent, key)
  true

proc tryTrainUnit(env: Environment, agent: Thing, building: Thing, unitClass: AgentUnitClass,
                  costs: openArray[tuple[res: StockpileResource, count: int]], cooldown: int): bool =
  if agent.unitClass != UnitVillager:
    return false
  let teamId = getTeamId(agent.agentId)
  if building.teamId != teamId:
    return false
  if not env.spendStockpile(teamId, costs):
    return false
  applyUnitClass(agent, unitClass)
  if agent.inventorySpear > 0:
    agent.inventorySpear = 0
    env.updateObservations(AgentInventorySpearLayer, agent.pos, agent.inventorySpear)
  building.cooldown = cooldown
  true

proc tryMarketTrade(env: Environment, agent: Thing, building: Thing): bool =
  let teamId = getTeamId(agent.agentId)
  if building.teamId != teamId:
    return false
  var traded = false
  for key, count in agent.inventory.pairs:
    if count <= 0:
      continue
    if not isStockpileResourceKey(key):
      continue
    let res = stockpileResourceForItem(key)
    if res == ResourceWater:
      continue
    if res == ResourceGold:
      env.addToStockpile(teamId, ResourceFood, count)
      setInv(agent, key, 0)
      env.updateAgentInventoryObs(agent, key)
      traded = true
    else:
      let gained = count div 2
      if gained > 0:
        env.addToStockpile(teamId, ResourceGold, gained)
        setInv(agent, key, count mod 2)
        env.updateAgentInventoryObs(agent, key)
        traded = true
  if traded:
    building.cooldown = 6
    return true
  false

proc recipeUsesStockpile(recipe: CraftRecipe): bool =
  if recipe.station == StationSiegeWorkshop:
    return false
  for output in recipe.outputs:
    if output.key.startsWith(ItemThingPrefix):
      return true
  false

proc canApplyRecipe(env: Environment, agent: Thing, recipe: CraftRecipe): bool =
  let useStockpile = recipeUsesStockpile(recipe)
  let teamId = getTeamId(agent.agentId)
  for input in recipe.inputs:
    if useStockpile and isStockpileResourceKey(input.key):
      let res = stockpileResourceForItem(input.key)
      if env.stockpileCount(teamId, res) < input.count:
        return false
    elif getInv(agent, input.key) < input.count:
      return false
  for output in recipe.outputs:
    if getInv(agent, output.key) + output.count > MapObjectAgentMaxInventory:
      return false
  true

proc applyRecipe(env: Environment, agent: Thing, recipe: CraftRecipe) =
  let useStockpile = recipeUsesStockpile(recipe)
  let teamId = getTeamId(agent.agentId)
  if useStockpile:
    var costs: seq[tuple[res: StockpileResource, count: int]] = @[]
    for input in recipe.inputs:
      if isStockpileResourceKey(input.key):
        costs.add((res: stockpileResourceForItem(input.key), count: input.count))
    discard env.spendStockpile(teamId, costs)
  for input in recipe.inputs:
    if useStockpile and isStockpileResourceKey(input.key):
      continue
    setInv(agent, input.key, getInv(agent, input.key) - input.count)
    env.updateAgentInventoryObs(agent, input.key)
  for output in recipe.outputs:
    setInv(agent, output.key, getInv(agent, output.key) + output.count)
    env.updateAgentInventoryObs(agent, output.key)

proc tryCraftAtStation(env: Environment, agent: Thing, station: CraftStation, stationThing: Thing): bool =
  for recipe in CraftRecipes:
    if recipe.station != station:
      continue
    var hasThingOutput = false
    for output in recipe.outputs:
      if output.key.startsWith(ItemThingPrefix):
        hasThingOutput = true
        break
    if hasThingOutput:
      continue
    if not canApplyRecipe(env, agent, recipe):
      continue
    env.applyRecipe(agent, recipe)
    if not isNil(stationThing):
      stationThing.cooldown = max(1, recipe.cooldown)
    return true
  false

include "place"

proc convertTreeToStump(env: Environment, tree: Thing) =
  removeThing(env, tree)
  env.dropStump(tree.pos, ResourceNodeInitial - 1)

proc grantWood(env: Environment, agent: Thing, amount: int = 1): bool =
  if amount <= 0:
    return true
  for _ in 0 ..< amount:
    if not env.giveItem(agent, ItemWood):
      return false
  true

proc harvestTree(env: Environment, agent: Thing, tree: Thing): bool =
  if not env.grantWood(agent):
    return false
  agent.reward += env.config.woodReward
  env.convertTreeToStump(tree)
  true

include "move"
include "combat"
include "use"

proc putAction(env: Environment, id: int, agent: Thing, argument: int) =
  ## Give items to adjacent teammate in the given direction.
  if argument > 7:
    inc env.stats[id].actionInvalid
    return
  let dir = Orientation(argument)
  agent.orientation = dir
  env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
  let delta = getOrientationDelta(dir)
  let targetPos = ivec2(agent.pos.x + delta.x.int32, agent.pos.y + delta.y.int32)
  if targetPos.x < 0 or targetPos.x >= MapWidth or targetPos.y < 0 or targetPos.y >= MapHeight:
    inc env.stats[id].actionInvalid
    return
  let target = env.getThing(targetPos)
  if isNil(target):
    inc env.stats[id].actionInvalid
    return
  if target.kind != Agent or isThingFrozen(target, env):
    inc env.stats[id].actionInvalid
    return
  var transferred = false
  # Give armor if we have any and target has none
  if agent.inventoryArmor > 0 and target.inventoryArmor == 0:
    target.inventoryArmor = agent.inventoryArmor
    agent.inventoryArmor = 0
    transferred = true
  # Otherwise give food if possible (no obs layer yet)
  elif agent.inventoryBread > 0:
    let capacity = block:
      var total = 0
      for invKey, invCount in target.inventory.pairs:
        if invCount > 0 and isStockpileResourceKey(invKey):
          total += invCount
      max(0, ResourceCarryCapacity - total)
    let giveAmt = min(agent.inventoryBread, capacity)
    if giveAmt > 0:
      agent.inventoryBread = agent.inventoryBread - giveAmt
      target.inventoryBread = target.inventoryBread + giveAmt
      transferred = true
  else:
    let stockpileCapacityLeft = block:
      var total = 0
      for invKey, invCount in target.inventory.pairs:
        if invCount > 0 and isStockpileResourceKey(invKey):
          total += invCount
      max(0, ResourceCarryCapacity - total)
    var bestKey = ItemNone
    var bestCount = 0
    for key, count in agent.inventory.pairs:
      if count <= 0:
        continue
      let capacity =
        if isStockpileResourceKey(key):
          stockpileCapacityLeft
        else:
          MapObjectAgentMaxInventory - getInv(target, key)
      if capacity <= 0:
        continue
      if count > bestCount:
        bestKey = key
        bestCount = count
    if bestKey != ItemNone and bestCount > 0:
      let capacity =
        if isStockpileResourceKey(bestKey):
          stockpileCapacityLeft
        else:
          max(0, MapObjectAgentMaxInventory - getInv(target, bestKey))
      if capacity > 0:
        let moved = min(bestCount, capacity)
        setInv(agent, bestKey, bestCount - moved)
        setInv(target, bestKey, getInv(target, bestKey) + moved)
        env.updateAgentInventoryObs(agent, bestKey)
        env.updateAgentInventoryObs(target, bestKey)
        transferred = true
  if transferred:
    inc env.stats[id].actionPut
    # Update observations for changed inventories
    env.updateAgentInventoryObs(agent, ItemArmor)
    env.updateAgentInventoryObs(agent, ItemBread)
    env.updateAgentInventoryObs(target, ItemArmor)
    env.updateAgentInventoryObs(target, ItemBread)
  else:
    inc env.stats[id].actionInvalid

# ============== CLIPPY AI ==============




{.push inline.}
proc isValidEmptyPosition(env: Environment, pos: IVec2): bool =
  ## Check if a position is within map bounds, empty, and not blocked terrain
  pos.x >= MapBorder and pos.x < MapWidth - MapBorder and
    pos.y >= MapBorder and pos.y < MapHeight - MapBorder and
    env.isEmpty(pos) and not env.hasDoor(pos) and not isBlockedTerrain(env.terrain[pos.x][pos.y]) and
    true

proc generateRandomMapPosition(r: var Rand): IVec2 =
  ## Generate a random position within map boundaries
  ivec2(
    int32(randIntExclusive(r, MapBorder, MapWidth - MapBorder)),
    int32(randIntExclusive(r, MapBorder, MapHeight - MapBorder))
  )
{.pop.}

proc findEmptyPositionsAround*(env: Environment, center: IVec2, radius: int): seq[IVec2] =
  ## Find empty positions around a center point within a given radius
  result = @[]
  for dx in -radius .. radius:
    for dy in -radius .. radius:
      if dx == 0 and dy == 0:
        continue  # Skip the center position
      let pos = ivec2(center.x + dx, center.y + dy)
      if env.isValidEmptyPosition(pos):
        result.add(pos)

proc findFirstEmptyPositionAround*(env: Environment, center: IVec2, radius: int): IVec2 =
  ## Find first empty position around center (no allocation)
  for dx in -radius .. radius:
    for dy in -radius .. radius:
      if dx == 0 and dy == 0:
        continue  # Skip the center position
      let pos = ivec2(center.x + dx, center.y + dy)
      if env.isValidEmptyPosition(pos):
        return pos
  return ivec2(-1, -1)  # No empty position found


# Tumor constants from balance.nim
const
  TumorBranchRange = DefaultTumorBranchRange
  TumorBranchMinAge = DefaultTumorBranchMinAge
  TumorBranchChance = DefaultTumorBranchChance
  TumorAdjacencyDeathChance = DefaultTumorAdjacencyDeathChance

let TumorBranchOffsets = block:
  var offsets: seq[IVec2] = @[]
  for dx in -TumorBranchRange .. TumorBranchRange:
    for dy in -TumorBranchRange .. TumorBranchRange:
      if dx == 0 and dy == 0:
        continue
      if max(abs(dx), abs(dy)) > TumorBranchRange:
        continue
      offsets.add(ivec2(dx, dy))
  offsets

proc findTumorBranchTarget(tumor: Thing, env: Environment, r: var Rand): IVec2 =
  ## Pick a random empty tile within the tumor's branching range
  var chosen = ivec2(-1, -1)
  var count = 0
  const AdjacentOffsets = [ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0)]

  for offset in TumorBranchOffsets:
    let candidate = tumor.pos + offset
    if not env.isValidEmptyPosition(candidate):
      continue

    var adjacentTumor = false
    for adj in AdjacentOffsets:
      let checkPos = candidate + adj
      if not isValidPos(checkPos):
        continue
      let occupant = env.getThing(checkPos)
      if not isNil(occupant) and occupant.kind == Tumor:
        adjacentTumor = true
        break
    if not adjacentTumor:
      inc count
      if randIntExclusive(r, 0, count) == 0:
        chosen = candidate

  if count == 0:
    return ivec2(-1, -1)
  chosen

proc randomEmptyPos(r: var Rand, env: Environment): IVec2 =
  # Try with moderate attempts first
  for i in 0 ..< 100:
    let pos = r.generateRandomMapPosition()
    if env.isValidEmptyPosition(pos):
      return pos
  # Try harder with more attempts
  for i in 0 ..< 1000:
    let pos = r.generateRandomMapPosition()
    if env.isValidEmptyPosition(pos):
      return pos
  raiseMapFullError()

include "tint"
include "build"

proc plantAction(env: Environment, id: int, agent: Thing, argument: int) =
  ## Plant lantern in the given direction.
  if argument > 7:
    inc env.stats[id].actionInvalid
    return
  let plantOrientation = Orientation(argument)
  agent.orientation = plantOrientation
  env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
  let delta = getOrientationDelta(plantOrientation)
  var targetPos = agent.pos
  targetPos.x += int32(delta.x)
  targetPos.y += int32(delta.y)

  # Check if position is empty and not water
  if not env.isEmpty(targetPos) or env.hasDoor(targetPos) or isBlockedTerrain(env.terrain[targetPos.x][targetPos.y]) or isTileFrozen(targetPos, env):
    inc env.stats[id].actionInvalid
    return

  if agent.inventoryLantern > 0:
    # Calculate team ID directly from the planting agent's ID
    let teamId = getTeamId(agent.agentId)

    # Plant the lantern
    let lantern = Thing(
      kind: Lantern,
      pos: targetPos,
      teamId: teamId,
      lanternHealthy: true
    )

    env.add(lantern)

    # Consume the lantern from agent's inventory
    agent.inventoryLantern = 0

    # Give reward for planting
    agent.reward += env.config.clothReward * 0.5  # Half reward for planting

    inc env.stats[id].actionPlant
  else:
    inc env.stats[id].actionInvalid

proc plantResourceAction(env: Environment, id: int, agent: Thing, argument: int) =
  ## Plant wheat (args 0-3) or tree (args 4-7) onto an adjacent fertile tile.
  let plantingTree =
    if argument <= 7:
      argument >= 4
    else:
      (argument mod 2) == 1
  let dirIndex =
    if argument <= 7:
      (if plantingTree: argument - 4 else: argument)
    else:
      (if argument mod 2 == 1: (argument div 2) mod 4 else: argument mod 4)
  if dirIndex < 0 or dirIndex > 7:
    inc env.stats[id].actionInvalid
    return
  let orientation = Orientation(dirIndex)
  agent.orientation = orientation
  env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
  let delta = getOrientationDelta(orientation)
  let targetPos = ivec2(agent.pos.x + delta.x.int32, agent.pos.y + delta.y.int32)

  # Occupancy checks
  if not env.isEmpty(targetPos) or not isNil(env.getOverlayThing(targetPos)) or env.hasDoor(targetPos) or
      isBlockedTerrain(env.terrain[targetPos.x][targetPos.y]) or isTileFrozen(targetPos, env):
    inc env.stats[id].actionInvalid
    return
  if env.terrain[targetPos.x][targetPos.y] != Fertile:
    inc env.stats[id].actionInvalid
    return

  if plantingTree:
    if agent.inventoryWood <= 0:
      inc env.stats[id].actionInvalid
      return
    agent.inventoryWood = max(0, agent.inventoryWood - 1)
    env.updateObservations(AgentInventoryWoodLayer, agent.pos, agent.inventoryWood)
    let tree = Thing(kind: Tree, pos: targetPos)
    tree.inventory = emptyInventory()
    setInv(tree, ItemWood, ResourceNodeInitial)
    env.add(tree)
  else:
    if agent.inventoryWheat <= 0:
      inc env.stats[id].actionInvalid
      return
    agent.inventoryWheat = max(0, agent.inventoryWheat - 1)
    env.updateObservations(AgentInventoryWheatLayer, agent.pos, agent.inventoryWheat)
    let crop = Thing(kind: Wheat, pos: targetPos)
    crop.inventory = emptyInventory()
    setInv(crop, ItemWheat, ResourceNodeInitial)
    env.add(crop)

  env.terrain[targetPos.x][targetPos.y] = Empty
  env.resetTileColor(targetPos)

  # Consuming fertility (terrain replaced above)
  inc env.stats[id].actionPlantResource

include "connect"
include "spawn"
include "step"

proc render*(env: Environment): string =
  for y in 0 ..< MapHeight:
    for x in 0 ..< MapWidth:
      var cell = " "
      # First check terrain
      cell = $TerrainCatalog[env.terrain[x][y]].ascii
      # Then override with objects if present (blocking first, overlay second)
      let blocking = env.grid[x][y]
      if not isNil(blocking):
        let kind = blocking.kind
        if isBuildingKind(kind):
          cell = $BuildingRegistry[kind].ascii
        else:
          cell = $ThingCatalog[kind].ascii
      else:
        let overlay = env.overlayGrid[x][y]
        if not isNil(overlay):
          let kind = overlay.kind
          if isBuildingKind(kind):
            cell = $BuildingRegistry[kind].ascii
          else:
            cell = $ThingCatalog[kind].ascii
      result.add(cell)
    result.add("\n")
