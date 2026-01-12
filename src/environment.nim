import std/[algorithm, strutils, tables, sets], vmath, chroma
import entropy
import terrain, items, common, biome
import types, registry, balance
export terrain, items, common
export types, registry, balance

## Error types and FFI error state management.
type
  TribalErrorKind* = enum
    ## Error categories for better diagnostics
    ErrNone = 0
    ErrMapFull = 1          ## No empty positions available for placement
    ErrInvalidPosition = 2  ## Position is out of bounds or invalid
    ErrResourceNotFound = 3 ## Required resource not found
    ErrInvalidState = 4     ## Invalid game state encountered
    ErrFFIError = 5         ## Error in FFI layer

  TribalError* = object of CatchableError
    ## Base exception type for tribal village errors
    kind*: TribalErrorKind
    details*: string

  FFIErrorState* = object
    ## Thread-local error state for FFI layer
    hasError*: bool
    errorCode*: TribalErrorKind
    errorMessage*: string

var lastFFIError*: FFIErrorState

proc clearFFIError*() =
  ## Clear the last FFI error state
  lastFFIError = FFIErrorState(hasError: false, errorCode: ErrNone, errorMessage: "")

proc newTribalError*(kind: TribalErrorKind, message: string): ref TribalError =
  ## Create a new tribal error with the given kind and message
  result = new(TribalError)
  result.kind = kind
  result.details = message
  result.msg = $kind & ": " & message

proc raiseMapFullError*() {.noreturn.} =
  ## Raise an error when the map is too full to place entities
  raise newTribalError(ErrMapFull, "Failed to find an empty position, map too full!")
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

include "inventory"

proc render*(env: Environment): string


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
    for key in ObservedItemKeys:
      env.updateAgentInventoryObs(agent, key)

  # Populate environment object layers.
  for thing in env.things:
    if thing.isNil:
      continue
    case thing.kind
    of Wall:
      env.updateObservations(WallLayer, thing.pos, 1)
    of Magma:
      env.updateObservations(MagmaLayer, thing.pos, 1)
    of Altar:
      env.updateObservations(altarLayer, thing.pos, 1)
      env.updateObservations(altarHeartsLayer, thing.pos, getInv(thing, ItemHearts))
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
  let door = env.getOverlayThing(pos)
  return not isNil(door) and door.kind == Door

proc canAgentPassDoor*(env: Environment, agent: Thing, pos: IVec2): bool =
  let door = env.getOverlayThing(pos)
  return isNil(door) or door.kind != Door or door.teamId == getTeamId(agent.agentId)
{.pop.}

proc isBuildableTerrain*(terrain: TerrainType): bool {.inline.} =
  terrain in BuildableTerrain

proc canPlace*(env: Environment, pos: IVec2, checkFrozen: bool = true): bool {.inline.} =
  isValidPos(pos) and env.isEmpty(pos) and isNil(env.getOverlayThing(pos)) and
    (not checkFrozen or not isTileFrozen(pos, env)) and isBuildableTerrain(env.terrain[pos.x][pos.y])

proc resetTileColor*(env: Environment, pos: IVec2) =
  ## Clear dynamic tint overlays for a tile
  env.computedTintColors[pos.x][pos.y] = TileColor(r: 0, g: 0, b: 0, intensity: 0)

# Build craft recipes after registry is available.
CraftRecipes = initCraftRecipesBase()
appendBuildingRecipes(CraftRecipes)

proc stockpileCapacityLeft(agent: Thing): int {.inline.} =
  var total = 0
  for invKey, invCount in agent.inventory.pairs:
    if invCount > 0 and isStockpileResourceKey(invKey):
      total += invCount
  max(0, ResourceCarryCapacity - total)

proc giveItem(env: Environment, agent: Thing, key: ItemKey, count: int = 1): bool =
  if count <= 0:
    return false
  if isStockpileResourceKey(key):
    if stockpileCapacityLeft(agent) < count:
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
        stockpileCapacityLeft(agent)
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
    let useStockpile = block:
      if recipe.station == StationSiegeWorkshop:
        false
      else:
        var uses = false
        for output in recipe.outputs:
          if output.key.startsWith(ItemThingPrefix):
            uses = true
            break
        uses
    let teamId = getTeamId(agent.agentId)
    var canApply = true
    for input in recipe.inputs:
      if useStockpile and isStockpileResourceKey(input.key):
        let res = stockpileResourceForItem(input.key)
        if env.stockpileCount(teamId, res) < input.count:
          canApply = false
          break
      elif getInv(agent, input.key) < input.count:
        canApply = false
        break
    if canApply:
      for output in recipe.outputs:
        if getInv(agent, output.key) + output.count > MapObjectAgentMaxInventory:
          canApply = false
          break
    if not canApply:
      continue
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
    if not isNil(stationThing):
      stationThing.cooldown = 0
    return true
  false

include "place"

proc grantWood(env: Environment, agent: Thing, amount: int = 1): bool =
  if amount <= 0:
    return true
  for _ in 0 ..< amount:
    if not env.giveItem(agent, ItemWood):
      return false
  true

proc grantWheat(env: Environment, agent: Thing, amount: int = 1): bool =
  if amount <= 0:
    return true
  for _ in 0 ..< amount:
    if not env.giveItem(agent, ItemWheat):
      return false
  true

proc harvestTree(env: Environment, agent: Thing, tree: Thing): bool =
  if not env.grantWood(agent):
    return false
  agent.reward += env.config.woodReward
  removeThing(env, tree)
  let stump = Thing(kind: Stump, pos: tree.pos)
  stump.inventory = emptyInventory()
  let remaining = ResourceNodeInitial - 1
  if remaining > 0:
    setInv(stump, ItemWood, remaining)
  env.add(stump)
  true

proc harvestWheat(env: Environment, agent: Thing, wheat: Thing): bool =
  let stored = getInv(wheat, ItemWheat)
  if stored <= 0:
    removeThing(env, wheat)
    return true
  if not env.grantWheat(agent):
    return false
  agent.reward += env.config.wheatReward
  removeThing(env, wheat)
  let stubble = Thing(kind: Stubble, pos: wheat.pos)
  stubble.inventory = emptyInventory()
  let remaining = stored - 1
  if remaining > 0:
    setInv(stubble, ItemWheat, remaining)
  env.add(stubble)
  true
include "combat"

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

proc buildCostsForKey*(key: ItemKey): seq[tuple[res: StockpileResource, count: int]] =
  var kind: ThingKind
  if parseThingKey(key, kind) and isBuildingKind(kind):
    var costs: seq[tuple[res: StockpileResource, count: int]] = @[]
    for input in BuildingRegistry[kind].buildCost:
      if isStockpileResourceKey(input.key):
        costs.add((res: stockpileResourceForItem(input.key), count: input.count))
    return costs
  for recipe in CraftRecipes:
    for output in recipe.outputs:
      if output.key != key:
        continue
      var costs: seq[tuple[res: StockpileResource, count: int]] = @[]
      for input in recipe.inputs:
        if not isStockpileResourceKey(input.key):
          continue
        costs.add((res: stockpileResourceForItem(input.key), count: input.count))
      return costs
  @[]

let BuildChoices*: array[ActionArgumentCount, ItemKey] = block:
  var choices: array[ActionArgumentCount, ItemKey]
  for i in 0 ..< choices.len:
    choices[i] = ItemNone
  for kind in ThingKind:
    if not isBuildingKind(kind):
      continue
    if not buildingBuildable(kind):
      continue
    let idx = BuildingRegistry[kind].buildIndex
    if idx >= 0 and idx < choices.len:
      choices[idx] = thingItem($kind)
  choices[BuildIndexWall] = thingItem("Wall")
  choices[BuildIndexRoad] = thingItem("Road")
  choices[BuildIndexDoor] = thingItem("Door")
  choices

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
