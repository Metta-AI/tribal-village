import std/[algorithm, strutils, tables, sets], vmath, chroma
import entropy
import terrain, items, common, biome
import types, registry
export terrain, items, common
export types, registry

const
  ## Default tumor behavior constants
  DefaultTumorBranchRange* = 5
  DefaultTumorBranchMinAge* = 2
  DefaultTumorBranchChance* = 0.1
  DefaultTumorAdjacencyDeathChance* = 1.0 / 3.0

  ## Default village spacing constants
  DefaultMinVillageSpacing* = 22
  DefaultSpawnerMinDistance* = 20
  DefaultInitialActiveAgents* = 6

  ## Default combat constants
  DefaultSpearCharges* = 5
  DefaultArmorPoints* = 5
  DefaultBreadHealAmount* = 999

  ## Default market tuning
  DefaultMarketSellNumerator* = 1
  DefaultMarketSellDenominator* = 2
  DefaultMarketBuyFoodNumerator* = 1
  DefaultMarketBuyFoodDenominator* = 1
  DefaultMarketCooldown* = 2

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


proc updateObservations(
  env: Environment,
  layer: ObservationName,
  pos: IVec2,
  value: int
) =
  ## Incremental observation update for a single world tile.
  discard layer
  discard value
  if not isValidPos(pos):
    return

  proc teamIdForObs(thing: Thing): int =
    if thing.isNil:
      return -1
    if thing.kind == Agent:
      return getTeamId(thing)
    if thing.kind in TeamOwnedKinds and thing.teamId >= 0 and thing.teamId < MapRoomObjectsHouses:
      return thing.teamId
    -1

  proc writeTileObs(agentId, obsX, obsY, worldX, worldY: int) =
    var agentObs = addr env.observations[agentId]
    for layerId in 0 ..< ObservationLayers:
      agentObs[][layerId][obsX][obsY] = 0

    let terrain = env.terrain[worldX][worldY]
    agentObs[][TerrainLayerStart + ord(terrain)][obsX][obsY] = 1

    let baseThing = env.grid[worldX][worldY]
    if not isNil(baseThing):
      agentObs[][ThingLayerStart + ord(baseThing.kind)][obsX][obsY] = 1

    let overlayThing = env.overlayGrid[worldX][worldY]
    if not isNil(overlayThing):
      agentObs[][ThingLayerStart + ord(overlayThing.kind)][obsX][obsY] = 1

    let cliffKind = env.cliffGrid[worldX][worldY]
    if cliffKind >= 0:
      agentObs[][ThingLayerStart + cliffKind.int][obsX][obsY] = 1

    var teamValue = 0
    var orientValue = 0
    var classValue = 0
    if not isNil(baseThing) and baseThing.kind == Agent:
      teamValue = getTeamId(baseThing) + 1
      orientValue = ord(baseThing.orientation) + 1
      classValue = ord(baseThing.unitClass) + 1
    else:
      let teamId = block:
        let baseTeam = teamIdForObs(baseThing)
        if baseTeam >= 0:
          baseTeam
        else:
          teamIdForObs(overlayThing)
      if teamId >= 0:
        teamValue = teamId + 1
    agentObs[][ord(TeamLayer)][obsX][obsY] = teamValue.uint8
    agentObs[][ord(AgentOrientationLayer)][obsX][obsY] = orientValue.uint8
    agentObs[][ord(AgentUnitClassLayer)][obsX][obsY] = classValue.uint8
    agentObs[][ord(TintLayer)][obsX][obsY] = env.actionTintCode[worldX][worldY]

  let agentCount = env.agents.len
  for agentId in 0 ..< agentCount:
    let agent = env.agents[agentId]
    if not isAgentAlive(env, agent):
      continue
    let agentPos = agent.pos
    let dx = pos.x - agentPos.x
    let dy = pos.y - agentPos.y
    if dx < -ObservationRadius or dx > ObservationRadius or
       dy < -ObservationRadius or dy > ObservationRadius:
      continue
    let obsX = dx + ObservationRadius
    let obsY = dy + ObservationRadius
    writeTileObs(agentId, obsX, obsY, pos.x, pos.y)
  env.observationsInitialized = true

include "colors"

const
  DefaultScoreNeutralThreshold = 0.05'f32
  DefaultScoreIncludeWater = false

{.push inline.}
proc updateAgentInventoryObs*(env: Environment, agent: Thing, key: ItemKey) =
  ## Inventory observations are not encoded in the spatial observation layers.
  discard

proc updateAgentInventoryObs*(env: Environment, agent: Thing, kind: ItemKind) =
  ## Type-safe overload using ItemKind enum
  discard

proc stockpileCount*(env: Environment, teamId: int, res: StockpileResource): int =
  env.teamStockpiles[teamId].counts[res]

proc addToStockpile*(env: Environment, teamId: int, res: StockpileResource, amount: int) =
  env.teamStockpiles[teamId].counts[res] += amount

proc toStockpileCosts(costs: openArray[tuple[key: ItemKey, count: int]],
                      outCosts: var seq[tuple[res: StockpileResource, count: int]]): bool =
  outCosts.setLen(0)
  for cost in costs:
    if not isStockpileResourceKey(cost.key):
      return false
    outCosts.add((res: stockpileResourceForItem(cost.key), count: cost.count))
  true

proc canSpendStockpile*(env: Environment, teamId: int,
                        costs: openArray[tuple[res: StockpileResource, count: int]]): bool =
  for cost in costs:
    if env.teamStockpiles[teamId].counts[cost.res] < cost.count:
      return false
  true

proc spendStockpile*(env: Environment, teamId: int,
                     costs: openArray[tuple[res: StockpileResource, count: int]]): bool =
  if not env.canSpendStockpile(teamId, costs):
    return false
  for cost in costs:
    env.teamStockpiles[teamId].counts[cost.res] -= cost.count
  true

proc canSpendStockpile*(env: Environment, teamId: int,
                        costs: openArray[tuple[key: ItemKey, count: int]]): bool =
  var resCosts: seq[tuple[res: StockpileResource, count: int]] = @[]
  if not toStockpileCosts(costs, resCosts):
    return false
  env.canSpendStockpile(teamId, resCosts)

proc spendStockpile*(env: Environment, teamId: int,
                     costs: openArray[tuple[key: ItemKey, count: int]]): bool =
  var resCosts: seq[tuple[res: StockpileResource, count: int]] = @[]
  if not toStockpileCosts(costs, resCosts):
    return false
  env.spendStockpile(teamId, resCosts)

proc spendInventory*(env: Environment, agent: Thing,
                     costs: openArray[tuple[key: ItemKey, count: int]]): bool =
  if not canSpendInventory(agent, costs):
    return false
  for cost in costs:
    setInv(agent, cost.key, getInv(agent, cost.key) - cost.count)
    env.updateAgentInventoryObs(agent, cost.key)
  true

proc choosePayment*(env: Environment, agent: Thing,
                    costs: openArray[tuple[key: ItemKey, count: int]]): PaymentSource =
  if costs.len == 0:
    return PayNone
  if canSpendInventory(agent, costs):
    return PayInventory
  let teamId = getTeamId(agent)
  if env.canSpendStockpile(teamId, costs):
    return PayStockpile
  PayNone

proc spendCosts*(env: Environment, agent: Thing, source: PaymentSource,
                 costs: openArray[tuple[key: ItemKey, count: int]]): bool =
  case source
  of PayInventory:
    spendInventory(env, agent, costs)
  of PayStockpile:
    env.spendStockpile(getTeamId(agent), costs)
  of PayNone:
    false

const
  UnitMaxHpByClass: array[AgentUnitClass, int] = [
    VillagerMaxHp,
    ManAtArmsMaxHp,
    ArcherMaxHp,
    ScoutMaxHp,
    KnightMaxHp,
    MonkMaxHp,
    BatteringRamMaxHp,
    MangonelMaxHp,
    GoblinMaxHp,
    VillagerMaxHp
  ]
  UnitAttackDamageByClass: array[AgentUnitClass, int] = [
    VillagerAttackDamage,
    ManAtArmsAttackDamage,
    ArcherAttackDamage,
    ScoutAttackDamage,
    KnightAttackDamage,
    MonkAttackDamage,
    BatteringRamAttackDamage,
    MangonelAttackDamage,
    GoblinAttackDamage,
    VillagerAttackDamage
  ]

proc applyUnitClass*(agent: Thing, unitClass: AgentUnitClass) =
  agent.unitClass = unitClass
  if unitClass != UnitBoat:
    agent.embarkedUnitClass = unitClass
  agent.maxHp = UnitMaxHpByClass[unitClass]
  agent.attackDamage = UnitAttackDamageByClass[unitClass]
  agent.hp = agent.maxHp

proc applyUnitClassPreserveHp*(agent: Thing, unitClass: AgentUnitClass) =
  let prevHp = agent.hp
  applyUnitClass(agent, unitClass)
  agent.hp = min(prevHp, agent.maxHp)

proc embarkAgent*(agent: Thing) =
  if agent.unitClass == UnitBoat:
    return
  agent.embarkedUnitClass = agent.unitClass
  applyUnitClassPreserveHp(agent, UnitBoat)

proc disembarkAgent*(agent: Thing) =
  if agent.unitClass != UnitBoat:
    return
  var target = agent.embarkedUnitClass
  if target == UnitBoat:
    target = UnitVillager
  applyUnitClassPreserveHp(agent, target)
{.pop.}

proc scoreTerritory*(env: Environment): TerritoryScore =
  ## Compute territory ownership by nearest tint color (teams + clippy).
  var score: TerritoryScore
  let teamCount = min(env.teamColors.len, MapRoomObjectsHouses)
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      if not DefaultScoreIncludeWater and env.terrain[x][y] == Water:
        continue
      let tint = env.computedTintColors[x][y]
      if tint.intensity < DefaultScoreNeutralThreshold:
        inc score.neutralTiles
        continue
      var bestDist = 1.0e9'f32
      var bestTeam = -1
      # Clippy as NPC team
      let drc = tint.r - ClippyTint.r
      let dgc = tint.g - ClippyTint.g
      let dbc = tint.b - ClippyTint.b
      bestDist = drc * drc + dgc * dgc + dbc * dbc
      bestTeam = MapRoomObjectsHouses
      for teamId in 0 ..< teamCount:
        let t = env.teamColors[teamId]
        let dr = tint.r - t.r
        let dg = tint.g - t.g
        let db = tint.b - t.b
        let dist = dr * dr + dg * dg + db * db
        if dist < bestDist:
          bestDist = dist
          bestTeam = teamId
      if bestTeam == MapRoomObjectsHouses:
        inc score.clippyTiles
      elif bestTeam >= 0 and bestTeam < MapRoomObjectsHouses:
        inc score.teamTiles[bestTeam]
      inc score.scoredTiles
  score


proc rebuildObservations*(env: Environment) =
  ## Recompute all observation layers from the current environment state.
  env.observations.clear()
  env.observationsInitialized = false

  proc teamIdForObs(thing: Thing): int =
    if thing.isNil:
      return -1
    if thing.kind == Agent:
      return getTeamId(thing)
    if thing.kind in TeamOwnedKinds and thing.teamId >= 0 and thing.teamId < MapRoomObjectsHouses:
      return thing.teamId
    -1

  proc writeTileObs(agentId, obsX, obsY, worldX, worldY: int) =
    var agentObs = addr env.observations[agentId]
    for layerId in 0 ..< ObservationLayers:
      agentObs[][layerId][obsX][obsY] = 0

    let terrain = env.terrain[worldX][worldY]
    agentObs[][TerrainLayerStart + ord(terrain)][obsX][obsY] = 1

    let baseThing = env.grid[worldX][worldY]
    if not isNil(baseThing):
      agentObs[][ThingLayerStart + ord(baseThing.kind)][obsX][obsY] = 1

    let overlayThing = env.overlayGrid[worldX][worldY]
    if not isNil(overlayThing):
      agentObs[][ThingLayerStart + ord(overlayThing.kind)][obsX][obsY] = 1

    let cliffKind = env.cliffGrid[worldX][worldY]
    if cliffKind >= 0:
      agentObs[][ThingLayerStart + cliffKind.int][obsX][obsY] = 1

    var teamValue = 0
    var orientValue = 0
    var classValue = 0
    if not isNil(baseThing) and baseThing.kind == Agent:
      teamValue = getTeamId(baseThing) + 1
      orientValue = ord(baseThing.orientation) + 1
      classValue = ord(baseThing.unitClass) + 1
    else:
      let teamId = block:
        let baseTeam = teamIdForObs(baseThing)
        if baseTeam >= 0:
          baseTeam
        else:
          teamIdForObs(overlayThing)
      if teamId >= 0:
        teamValue = teamId + 1
    agentObs[][ord(TeamLayer)][obsX][obsY] = teamValue.uint8
    agentObs[][ord(AgentOrientationLayer)][obsX][obsY] = orientValue.uint8
    agentObs[][ord(AgentUnitClassLayer)][obsX][obsY] = classValue.uint8
    agentObs[][ord(TintLayer)][obsX][obsY] = env.actionTintCode[worldX][worldY]

  for agentId in 0 ..< env.agents.len:
    let agent = env.agents[agentId]
    if agent.isNil or not isAgentAlive(env, agent) or not isValidPos(agent.pos):
      continue
    let agentPos = agent.pos
    for obsX in 0 ..< ObservationWidth:
      let worldX = agentPos.x + (obsX - ObservationRadius)
      if worldX < 0 or worldX >= MapWidth:
        continue
      for obsY in 0 ..< ObservationHeight:
        let worldY = agentPos.y + (obsY - ObservationRadius)
        if worldY < 0 or worldY >= MapHeight:
          continue
        writeTileObs(agentId, obsX, obsY, worldX, worldY)

  env.observationsInitialized = true

{.push inline.}
proc getThing*(env: Environment, pos: IVec2): Thing =
  if not isValidPos(pos): nil else: env.grid[pos.x][pos.y]

proc getOverlayThing*(env: Environment, pos: IVec2): Thing =
  if not isValidPos(pos): nil else: env.overlayGrid[pos.x][pos.y]

proc isEmpty*(env: Environment, pos: IVec2): bool =
  isValidPos(pos) and isNil(env.grid[pos.x][pos.y])

proc hasDoor*(env: Environment, pos: IVec2): bool =
  let door = env.getOverlayThing(pos)
  not isNil(door) and door.kind == Door

proc canAgentPassDoor*(env: Environment, agent: Thing, pos: IVec2): bool =
  let door = env.getOverlayThing(pos)
  isNil(door) or door.kind != Door or door.teamId == getTeamId(agent)

proc hasDockAt*(env: Environment, pos: IVec2): bool {.inline.} =
  let overlay = env.getOverlayThing(pos)
  let base = env.getThing(pos)
  (not isNil(overlay) and overlay.kind == Dock) or (not isNil(base) and base.kind == Dock)

proc isWaterBlockedForAgent*(env: Environment, agent: Thing, pos: IVec2): bool {.inline.} =
  env.terrain[pos.x][pos.y] == Water and agent.unitClass != UnitBoat and not env.hasDockAt(pos)
{.pop.}

proc canTraverseElevation*(env: Environment, fromPos, toPos: IVec2): bool {.inline.} =
  ## Allow flat movement or a 1-elevation step when a ramp connects the tiles.
  if not isValidPos(fromPos) or not isValidPos(toPos):
    return false
  let dx = toPos.x - fromPos.x
  let dy = toPos.y - fromPos.y
  if abs(dx) + abs(dy) != 1:
    return false
  let elevFrom = env.elevation[fromPos.x][fromPos.y]
  let elevTo = env.elevation[toPos.x][toPos.y]
  if elevFrom == elevTo:
    return true
  if abs(elevFrom - elevTo) != 1:
    return false

  let fromTerrain = env.terrain[fromPos.x][fromPos.y]
  let toTerrain = env.terrain[toPos.x][toPos.y]
  (fromTerrain == Road or toTerrain == Road)

proc isBuildableTerrain*(terrain: TerrainType): bool {.inline.} =
  terrain in BuildableTerrain

proc canPlace*(env: Environment, pos: IVec2, checkFrozen: bool = true): bool {.inline.} =
  isValidPos(pos) and env.isEmpty(pos) and isNil(env.getOverlayThing(pos)) and
    (not checkFrozen or not isTileFrozen(pos, env)) and isBuildableTerrain(env.terrain[pos.x][pos.y])

proc canPlaceDock*(env: Environment, pos: IVec2, checkFrozen: bool = true): bool {.inline.} =
  isValidPos(pos) and env.isEmpty(pos) and isNil(env.getOverlayThing(pos)) and
    (not checkFrozen or not isTileFrozen(pos, env)) and env.terrain[pos.x][pos.y] == Water

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
    if storedKey == ItemNone:
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
  let teamId = getTeamId(agent)
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
  let teamId = getTeamId(agent)
  if building.teamId != teamId:
    return false
  if not env.spendStockpile(teamId, costs):
    return false
  applyUnitClass(agent, unitClass)
  if agent.inventorySpear > 0:
    agent.inventorySpear = 0
  building.cooldown = cooldown
  true

proc tryCraftAtStation(env: Environment, agent: Thing, station: CraftStation, stationThing: Thing): bool =
  for recipe in CraftRecipes:
    if recipe.station != station:
      continue
    var hasThingOutput = false
    for output in recipe.outputs:
      if isThingKey(output.key):
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
          if isThingKey(output.key):
            uses = true
            break
        uses
    let teamId = getTeamId(agent)
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

include "placement"

proc grantItem(env: Environment, agent: Thing, key: ItemKey, amount: int = 1): bool =
  if amount <= 0:
    return true
  for _ in 0 ..< amount:
    if not env.giveItem(agent, key):
      return false
  true

proc harvestTree(env: Environment, agent: Thing, tree: Thing): bool =
  if not env.grantItem(agent, ItemWood):
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
  if not env.grantItem(agent, ItemWheat):
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
    env.isEmpty(pos) and isNil(env.getOverlayThing(pos)) and not env.hasDoor(pos) and
    not isBlockedTerrain(env.terrain[pos.x][pos.y]) and
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


  # Tumor constants from shared tuning defaults.
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

proc buildCostsForKey*(key: ItemKey): seq[tuple[key: ItemKey, count: int]] =
  var kind: ThingKind
  if parseThingKey(key, kind) and isBuildingKind(kind):
    var costs: seq[tuple[key: ItemKey, count: int]] = @[]
    for input in BuildingRegistry[kind].buildCost:
      costs.add((key: input.key, count: input.count))
    return costs
  for recipe in CraftRecipes:
    for output in recipe.outputs:
      if output.key != key:
        continue
      var costs: seq[tuple[key: ItemKey, count: int]] = @[]
      for input in recipe.inputs:
        costs.add((key: input.key, count: input.count))
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

include "connectivity"
include "spawn"
include "step"
