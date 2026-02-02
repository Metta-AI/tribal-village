import std/[algorithm, strutils, tables, sets], vmath, chroma
import entropy
import terrain, items, common, biome
import types, registry
import spatial_index
import formations
import state_dumper
import arena_alloc
export terrain, items, common
export types, registry
export spatial_index
export formations
export state_dumper

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

  ## Ramp tile placement constants
  ## Controls how frequently ramps are placed at elevation transitions
  ## and their visual width for clearer elevation feedback.
  RampPlacementSpacing* = 4     # Place ramp every Nth cliff edge (lower = more ramps)
  RampWidthMin* = 1             # Minimum ramp width in tiles
  RampWidthMax* = 3             # Maximum ramp width in tiles

  ## Cliff fall damage - agents take damage when dropping elevation without a ramp
  CliffFallDamage* = 1          # Damage taken per elevation level dropped without ramp

  ## Default combat constants
  DefaultSpearCharges* = 5
  DefaultArmorPoints* = 5
  DefaultBreadHealAmount* = 999

  ## Default market tuning (AoE2-style dynamic pricing)
  ## Prices are in gold per 100 units of resource (scaled for integer math)
  MarketBasePrice* = 100        # Base price: 100 gold per 100 resources
  MarketMinPrice* = 20          # Minimum price floor
  MarketMaxPrice* = 300         # Maximum price ceiling
  MarketBuyPriceIncrease* = 3   # Price increase per buy transaction
  MarketSellPriceDecrease* = 3  # Price decrease per sell transaction
  MarketPriceDecayRate* = 1     # Price drift toward base per decay tick
  MarketPriceDecayInterval* = 50 # Steps between price decay ticks
  DefaultMarketCooldown* = 2
  # Legacy constants (kept for compatibility)
  DefaultMarketSellNumerator* = 1
  DefaultMarketSellDenominator* = 2
  DefaultMarketBuyFoodNumerator* = 1
  DefaultMarketBuyFoodDenominator* = 1

  ## Biome gathering bonus constants
  BiomeGatherBonusChance* = 0.20  # 20% chance for bonus item in matching biomes
  DesertOasisBonusChance* = 0.10  # 10% chance for bonus in desert near water
  DesertOasisRadius* = 3  # Tiles from water to get desert bonus

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
  zeroMem(cast[pointer](s[0].addr), s.len * sizeof(T))

proc hasWaterNearby*(env: Environment, pos: IVec2, radius: int, includeShallow: bool = false): bool =
  ## Check if there is water terrain within the given radius of a position.
  ## If includeShallow is true, also matches ShallowWater.
  for dx in -radius .. radius:
    for dy in -radius .. radius:
      let x = pos.x + dx
      let y = pos.y + dy
      if x >= 0 and x < MapWidth and y >= 0 and y < MapHeight:
        let t = env.terrain[x][y]
        if t == Water or (includeShallow and t == ShallowWater):
          return true
  false

proc getBiomeGatherBonus*(env: Environment, pos: IVec2, itemKey: ItemKey): int =
  ## Calculate bonus items from biome-specific gathering bonuses.
  ## Returns 0 or 1 based on probability roll using deterministic seed.
  ## Forest: +20% wood, Plains: +20% food, Caves: +20% stone, Snow: +20% gold,
  ## Desert: +10% all resources near water (oasis effect)
  if not isValidPos(pos):
    return 0

  let biome = env.biomes[pos.x][pos.y]

  # Check for biome-specific bonus
  var bonusChance = 0.0
  case biome
  of BiomeForestType:
    if itemKey == ItemWood:
      bonusChance = BiomeGatherBonusChance
  of BiomePlainsType:
    if itemKey == ItemWheat:
      bonusChance = BiomeGatherBonusChance
  of BiomeCavesType:
    if itemKey == ItemStone:
      bonusChance = BiomeGatherBonusChance
  of BiomeSnowType:
    if itemKey == ItemGold:
      bonusChance = BiomeGatherBonusChance
  of BiomeDesertType:
    # Desert gives bonus to all resources if near water (oasis effect)
    if itemKey == ItemWood or itemKey == ItemWheat or itemKey == ItemStone or itemKey == ItemGold:
      if env.hasWaterNearby(pos, DesertOasisRadius):
        bonusChance = DesertOasisBonusChance
  else:
    discard

  if bonusChance <= 0.0:
    return 0

  # Use deterministic seed based on position and step for reproducible behavior
  # Cast to int to avoid int32 overflow and ensure positive seed
  let seed = abs(int(pos.x) * 31337 + int(pos.y) * 7919 + env.currentStep * 13) + 1
  var r = initRand(seed)
  # Warm up RNG by discarding first few values to improve distribution
  discard next(r)
  discard next(r)
  if randChance(r, bonusChance):
    return 1
  0

{.push boundChecks: off, overflowChecks: off.}
proc writeTileObs(env: Environment, agentId, obsX, obsY, worldX, worldY: int) {.inline.} =
  ## Write observation data for a single tile. Called from rebuildObservations
  ## which already zeroed all observation memory, so we only set non-zero values.
  ## Bounds checking disabled: caller validates worldX/worldY in [0, MapWidth/Height)
  ## and obsX/obsY in [0, ObservationWidth/Height).

  # Cache base observation pointer - avoid repeated addr computation
  let obs = addr env.observations[agentId]

  # Terrain layer (one-hot encoded)
  let terrain = env.terrain[worldX][worldY]
  obs[][TerrainLayerStart + ord(terrain)][obsX][obsY] = 1

  # Thing layers - cache lookups
  let blockingThing = env.grid[worldX][worldY]
  let backgroundThing = env.backgroundGrid[worldX][worldY]

  if not isNil(blockingThing):
    obs[][ThingLayerStart + ord(blockingThing.kind)][obsX][obsY] = 1

  if not isNil(backgroundThing):
    obs[][ThingLayerStart + ord(backgroundThing.kind)][obsX][obsY] = 1

  # Process based on what's on the tile - single branch structure
  if not isNil(blockingThing):
    if blockingThing.kind == Agent:
      # Agent-specific layers (team, orientation, class, idle, stance)
      obs[][ord(TeamLayer)][obsX][obsY] = uint8(getTeamId(blockingThing) + 1)
      obs[][ord(AgentOrientationLayer)][obsX][obsY] = uint8(ord(blockingThing.orientation) + 1)
      obs[][ord(AgentUnitClassLayer)][obsX][obsY] = uint8(ord(blockingThing.unitClass) + 1)
      obs[][ord(UnitStanceLayer)][obsX][obsY] = uint8(ord(blockingThing.stance) + 1)

      # Idle detection: 1 if agent took NOOP/ORIENT action
      if blockingThing.isIdle:
        obs[][ord(AgentIdleLayer)][obsX][obsY] = 1

      # Monk faith (only if non-zero)
      if blockingThing.unitClass == UnitMonk and blockingThing.faith > 0:
        obs[][ord(MonkFaithLayer)][obsX][obsY] =
          uint8((blockingThing.faith * 255) div MonkMaxFaith)

      # Trebuchet packed state
      if blockingThing.unitClass == UnitTrebuchet and blockingThing.packed:
        obs[][ord(TrebuchetPackedLayer)][obsX][obsY] = 1
    else:
      # Non-agent blocking thing (building/resource/etc)
      # Team ownership: prefer blocking thing, fall back to background
      if blockingThing.kind in TeamOwnedKinds and
         blockingThing.teamId >= 0 and blockingThing.teamId < MapRoomObjectsTeams:
        obs[][ord(TeamLayer)][obsX][obsY] = uint8(blockingThing.teamId + 1)
      elif not isNil(backgroundThing) and backgroundThing.kind in TeamOwnedKinds and
           backgroundThing.teamId >= 0 and backgroundThing.teamId < MapRoomObjectsTeams:
        obs[][ord(TeamLayer)][obsX][obsY] = uint8(backgroundThing.teamId + 1)

      # Building HP (normalized to 0-255)
      if blockingThing.maxHp > 0:
        obs[][ord(BuildingHpLayer)][obsX][obsY] =
          uint8((blockingThing.hp * 255) div blockingThing.maxHp)

      # Garrison count (normalized to 0-255 by capacity)
      let capacity = case blockingThing.kind
        of TownCenter: TownCenterGarrisonCapacity
        of Castle: CastleGarrisonCapacity
        of GuardTower: GuardTowerGarrisonCapacity
        of House: HouseGarrisonCapacity
        else: 0
      if capacity > 0 and blockingThing.garrisonedUnits.len > 0:
        obs[][ord(GarrisonCountLayer)][obsX][obsY] =
          uint8((blockingThing.garrisonedUnits.len * 255) div capacity)

      # Monastery relic count
      if blockingThing.kind == Monastery and blockingThing.garrisonedRelics > 0:
        obs[][ord(RelicCountLayer)][obsX][obsY] =
          uint8(min(blockingThing.garrisonedRelics, 255))

      # Production queue length
      if blockingThing.productionQueue.entries.len > 0:
        obs[][ord(ProductionQueueLenLayer)][obsX][obsY] =
          uint8(min(blockingThing.productionQueue.entries.len, 255))
  else:
    # No blocking thing - check background for team ownership
    if not isNil(backgroundThing) and backgroundThing.kind in TeamOwnedKinds and
       backgroundThing.teamId >= 0 and backgroundThing.teamId < MapRoomObjectsTeams:
      obs[][ord(TeamLayer)][obsX][obsY] = uint8(backgroundThing.teamId + 1)

  # Tint layer
  let tintCode = env.actionTintCode[worldX][worldY]
  if tintCode != 0:
    obs[][ord(TintLayer)][obsX][obsY] = tintCode

  # Biome layer (enum value)
  obs[][ord(BiomeLayer)][obsX][obsY] = uint8(ord(env.biomes[worldX][worldY]))
{.pop.}

proc updateObservations(
  env: Environment,
  layer: ObservationName,
  pos: IVec2,
  value: int
) {.inline.} =
  ## No-op: observations are rebuilt in batch at end of step() for efficiency.
  ## Previously iterated ALL agents per tile update which was O(updates * agents).
  ## Now rebuildObservations is called once at end of step() which is O(agents * tiles).
  discard env
  discard layer
  discard pos
  discard value

include "colors"
include "event_log"

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
  ## Add resources to team stockpile, applying gather rate modifier
  let rawModifier = env.teamModifiers[teamId].gatherRateMultiplier
  let modifier = if rawModifier == 0.0'f32: 1.0'f32 else: rawModifier  # Default to 1.0 if uninitialized
  let adjustedAmount = int(float32(amount) * modifier)
  env.teamStockpiles[teamId].counts[res] += adjustedAmount

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
  for cost in costs:
    let res = stockpileResourceForItem(cost.key)
    if res == ResourceNone:
      return false
    if env.teamStockpiles[teamId].counts[res] < cost.count:
      return false
  true

proc spendStockpile*(env: Environment, teamId: int,
                     costs: openArray[tuple[key: ItemKey, count: int]]): bool =
  if not env.canSpendStockpile(teamId, costs):
    return false
  for cost in costs:
    let res = stockpileResourceForItem(cost.key)
    env.teamStockpiles[teamId].counts[res] -= cost.count
  true

# ============================================================================
# AoE2-style Market Trading with Dynamic Prices
# ============================================================================

proc initMarketPrices*(env: Environment) =
  ## Initialize market prices to base rates for all teams
  for teamId in 0 ..< MapRoomObjectsTeams:
    for res in StockpileResource:
      if res != ResourceNone and res != ResourceGold:
        env.teamMarketPrices[teamId].prices[res] = MarketBasePrice

proc getMarketPrice*(env: Environment, teamId: int, res: StockpileResource): int {.inline.} =
  ## Get current market price for a resource (gold cost per 100 units)
  if res == ResourceGold or res == ResourceNone:
    return 0
  env.teamMarketPrices[teamId].prices[res]

proc setMarketPrice*(env: Environment, teamId: int, res: StockpileResource, price: int) =
  ## Set market price with clamping to min/max bounds
  if res == ResourceGold or res == ResourceNone:
    return
  env.teamMarketPrices[teamId].prices[res] = clamp(price, MarketMinPrice, MarketMaxPrice)

proc marketBuyResource*(env: Environment, teamId: int, res: StockpileResource,
                        amount: int): tuple[goldCost: int, resourceGained: int] =
  ## Buy resources from market using gold from stockpile.
  ## Returns (gold spent, resources gained). Price increases after buying.
  ## Uses scaled integer math: price is gold per 100 units.
  if res == ResourceGold or res == ResourceNone or amount <= 0:
    return (0, 0)

  let currentPrice = env.getMarketPrice(teamId, res)
  # Cost = (amount * price) / 100, rounding up
  let goldCost = (amount * currentPrice + 99) div 100

  # Check if team has enough gold
  if env.teamStockpiles[teamId].counts[ResourceGold] < goldCost:
    return (0, 0)

  # Execute transaction
  env.teamStockpiles[teamId].counts[ResourceGold] -= goldCost
  env.teamStockpiles[teamId].counts[res] += amount

  # Increase price (supply decreased, demand increased)
  env.setMarketPrice(teamId, res, currentPrice + MarketBuyPriceIncrease)

  result = (goldCost, amount)

proc marketSellResource*(env: Environment, teamId: int, res: StockpileResource,
                         amount: int): tuple[resourceSold: int, goldGained: int] =
  ## Sell resources to market for gold.
  ## Returns (resources sold, gold gained). Price decreases after selling.
  ## Uses scaled integer math: price is gold per 100 units.
  if res == ResourceGold or res == ResourceNone or amount <= 0:
    return (0, 0)

  let currentPrice = env.getMarketPrice(teamId, res)
  # Gain = (amount * price) / 100, rounding down
  let goldGained = (amount * currentPrice) div 100

  # Check if team has enough resources to sell
  if env.teamStockpiles[teamId].counts[res] < amount:
    return (0, 0)

  # Execute transaction
  env.teamStockpiles[teamId].counts[res] -= amount
  env.teamStockpiles[teamId].counts[ResourceGold] += goldGained

  # Decrease price (supply increased)
  env.setMarketPrice(teamId, res, currentPrice - MarketSellPriceDecrease)

  result = (amount, goldGained)

proc marketSellInventory*(env: Environment, agent: Thing, itemKey: ItemKey):
                          tuple[amountSold: int, goldGained: int] =
  ## Sell all of an item from agent's inventory to their team's market.
  ## Returns (amount sold, gold gained).
  let teamId = getTeamId(agent)
  let res = stockpileResourceForItem(itemKey)
  if res == ResourceGold or res == ResourceNone or res == ResourceWater:
    return (0, 0)

  let amount = getInv(agent, itemKey)
  if amount <= 0:
    return (0, 0)

  let currentPrice = env.getMarketPrice(teamId, res)
  # Gain = (amount * price) / 100, rounding down
  let goldGained = (amount * currentPrice) div 100

  if goldGained > 0:
    # Clear inventory and add gold to stockpile
    setInv(agent, itemKey, 0)
    env.addToStockpile(teamId, ResourceGold, goldGained)
    # Decrease price (supply increased)
    env.setMarketPrice(teamId, res, currentPrice - MarketSellPriceDecrease)
    return (amount, goldGained)

  result = (0, 0)

proc marketBuyFood*(env: Environment, agent: Thing, goldAmount: int):
                    tuple[goldSpent: int, foodGained: int] =
  ## Buy food with gold from agent's inventory.
  ## Returns (gold spent, food gained to stockpile).
  let teamId = getTeamId(agent)
  if goldAmount <= 0:
    return (0, 0)

  let invGold = getInv(agent, ItemGold)
  if invGold < goldAmount:
    return (0, 0)

  let currentPrice = env.getMarketPrice(teamId, ResourceFood)
  # Food gained = (gold * 100) / price
  let foodGained = (goldAmount * 100) div currentPrice

  if foodGained > 0:
    setInv(agent, ItemGold, invGold - goldAmount)
    env.addToStockpile(teamId, ResourceFood, foodGained)
    # Increase price (demand increased)
    env.setMarketPrice(teamId, ResourceFood, currentPrice + MarketBuyPriceIncrease)
    return (goldAmount, foodGained)

  result = (0, 0)

proc decayMarketPrices*(env: Environment) =
  ## Slowly drift market prices back toward base rate.
  ## Should be called periodically (every MarketPriceDecayInterval steps).
  for teamId in 0 ..< MapRoomObjectsTeams:
    for res in StockpileResource:
      if res == ResourceGold or res == ResourceNone:
        continue
      let currentPrice = env.teamMarketPrices[teamId].prices[res]
      if currentPrice > MarketBasePrice:
        env.teamMarketPrices[teamId].prices[res] = max(MarketBasePrice,
          currentPrice - MarketPriceDecayRate)
      elif currentPrice < MarketBasePrice:
        env.teamMarketPrices[teamId].prices[res] = min(MarketBasePrice,
          currentPrice + MarketPriceDecayRate)

# ============================================================================

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
    TrebuchetMaxHp,
    GoblinMaxHp,
    VillagerMaxHp,
    TradeCogMaxHp,
    # Castle unique units
    SamuraiMaxHp,
    LongbowmanMaxHp,
    CataphractMaxHp,
    WoadRaiderMaxHp,
    TeutonicKnightMaxHp,
    HuskarlMaxHp,
    MamelukeMaxHp,
    JanissaryMaxHp,
    KingMaxHp,
    # Unit upgrade tiers
    LongSwordsmanMaxHp,
    ChampionMaxHp,
    LightCavalryMaxHp,
    HussarMaxHp,
    CrossbowmanMaxHp,
    ArbalesterMaxHp
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
    TrebuchetAttackDamage,
    GoblinAttackDamage,
    VillagerAttackDamage,
    TradeCogAttackDamage,
    # Castle unique units
    SamuraiAttackDamage,
    LongbowmanAttackDamage,
    CataphractAttackDamage,
    WoadRaiderAttackDamage,
    TeutonicKnightAttackDamage,
    HuskarlAttackDamage,
    MamelukeAttackDamage,
    JanissaryAttackDamage,
    KingAttackDamage,
    # Unit upgrade tiers
    LongSwordsmanAttackDamage,
    ChampionAttackDamage,
    LightCavalryAttackDamage,
    HussarAttackDamage,
    CrossbowmanAttackDamage,
    ArbalesterAttackDamage
  ]

proc defaultStanceForClass*(unitClass: AgentUnitClass): AgentStance =
  ## Returns the default stance for a unit class.
  ## Villagers use NoAttack (won't auto-attack).
  ## Military units use Defensive (attack in range, return to position).
  case unitClass
  of UnitVillager, UnitMonk, UnitBoat, UnitTradeCog:
    StanceNoAttack
  of UnitManAtArms, UnitArcher, UnitScout, UnitKnight, UnitBatteringRam, UnitMangonel, UnitTrebuchet, UnitGoblin,
     UnitSamurai, UnitLongbowman, UnitCataphract, UnitWoadRaider, UnitTeutonicKnight,
     UnitHuskarl, UnitMameluke, UnitJanissary, UnitKing,
     UnitLongSwordsman, UnitChampion, UnitLightCavalry, UnitHussar, UnitCrossbowman, UnitArbalester:
    StanceDefensive

type
  UnitCategory* = enum
    ## Categories for Blacksmith upgrade application
    CategoryNone      ## Units that don't receive upgrades (villagers, siege, monks)
    CategoryInfantry  ## Man-at-arms, Samurai, Woad Raider, Teutonic Knight, Huskarl
    CategoryCavalry   ## Scout, Knight, Cataphract, Mameluke
    CategoryArcher    ## Archer, Longbowman, Janissary

proc getUnitCategory*(unitClass: AgentUnitClass): UnitCategory =
  ## Returns the Blacksmith upgrade category for a unit class.
  ## Used to determine which upgrades apply to a unit.
  case unitClass
  of UnitManAtArms, UnitSamurai, UnitWoadRaider, UnitTeutonicKnight, UnitHuskarl,
     UnitLongSwordsman, UnitChampion:
    CategoryInfantry
  of UnitScout, UnitKnight, UnitCataphract, UnitMameluke,
     UnitLightCavalry, UnitHussar:
    CategoryCavalry
  of UnitArcher, UnitLongbowman, UnitJanissary,
     UnitCrossbowman, UnitArbalester:
    CategoryArcher
  of UnitVillager, UnitMonk, UnitBatteringRam, UnitMangonel, UnitTrebuchet, UnitGoblin, UnitBoat, UnitKing, UnitTradeCog:
    CategoryNone

proc getBlacksmithAttackBonus*(env: Environment, teamId: int, unitClass: AgentUnitClass): int =
  ## Returns the attack bonus from Blacksmith upgrades for a unit.
  ## Melee attack (Forging line) applies to infantry + cavalry.
  ## Archer attack (Fletching line) applies to archers.
  ## Bonus varies by tier: level 3 melee gives +2 extra (Blast Furnace).
  let category = getUnitCategory(unitClass)
  case category
  of CategoryInfantry, CategoryCavalry:
    let level = env.teamBlacksmithUpgrades[teamId].levels[UpgradeMeleeAttack]
    BlacksmithMeleeAttackBonus[level]
  of CategoryArcher:
    let level = env.teamBlacksmithUpgrades[teamId].levels[UpgradeArcherAttack]
    BlacksmithArcherAttackBonus[level]
  of CategoryNone:
    0

proc getBlacksmithArmorBonus*(env: Environment, teamId: int, unitClass: AgentUnitClass): int =
  ## Returns the armor bonus from Blacksmith upgrades for a unit.
  ## Bonus varies by tier: level 3 gives +2 extra (Plate/Ring upgrades).
  let category = getUnitCategory(unitClass)
  case category
  of CategoryInfantry:
    let level = env.teamBlacksmithUpgrades[teamId].levels[UpgradeInfantryArmor]
    BlacksmithInfantryArmorBonus[level]
  of CategoryCavalry:
    let level = env.teamBlacksmithUpgrades[teamId].levels[UpgradeCavalryArmor]
    BlacksmithCavalryArmorBonus[level]
  of CategoryArcher:
    let level = env.teamBlacksmithUpgrades[teamId].levels[UpgradeArcherArmor]
    BlacksmithArcherArmorBonus[level]
  of CategoryNone:
    0

proc applyUnitClass*(agent: Thing, unitClass: AgentUnitClass) =
  ## Apply unit class stats without team modifiers (backwards compatibility)
  agent.unitClass = unitClass
  if unitClass != UnitBoat:
    agent.embarkedUnitClass = unitClass
  agent.maxHp = UnitMaxHpByClass[unitClass]
  agent.attackDamage = UnitAttackDamageByClass[unitClass]
  agent.hp = agent.maxHp
  agent.stance = defaultStanceForClass(unitClass)
  # Initialize monk faith
  if unitClass == UnitMonk:
    agent.faith = MonkMaxFaith
  else:
    agent.faith = 0

proc applyUnitClass*(env: Environment, agent: Thing, unitClass: AgentUnitClass) =
  ## Apply unit class stats with team modifier bonuses
  ## Also maintains tankUnits/monkUnits collections for efficient aura iteration
  let oldClass = agent.unitClass
  agent.unitClass = unitClass
  if unitClass != UnitBoat:
    agent.embarkedUnitClass = unitClass
  let teamId = getTeamId(agent)
  let modifiers = env.teamModifiers[teamId]
  agent.maxHp = UnitMaxHpByClass[unitClass] + modifiers.unitHpBonus[unitClass]
  agent.attackDamage = UnitAttackDamageByClass[unitClass] + modifiers.unitAttackBonus[unitClass]
  agent.hp = agent.maxHp
  # Initialize monk faith
  if unitClass == UnitMonk:
    agent.faith = MonkMaxFaith
  else:
    agent.faith = 0

  # Update aura unit collections for optimized aura processing
  # Tank units: ManAtArms and Knight have shield auras
  let wasTank = oldClass in {UnitManAtArms, UnitKnight}
  let isTank = unitClass in {UnitManAtArms, UnitKnight}
  if wasTank and not isTank:
    # Remove from tankUnits (swap-and-pop for O(1))
    for i in 0 ..< env.tankUnits.len:
      if env.tankUnits[i] == agent:
        env.tankUnits[i] = env.tankUnits[^1]
        env.tankUnits.setLen(env.tankUnits.len - 1)
        break
  elif isTank and not wasTank:
    env.tankUnits.add(agent)

  # Monk units: have heal auras
  let wasMonk = oldClass == UnitMonk
  let isMonk = unitClass == UnitMonk
  if wasMonk and not isMonk:
    # Remove from monkUnits (swap-and-pop for O(1))
    for i in 0 ..< env.monkUnits.len:
      if env.monkUnits[i] == agent:
        env.monkUnits[i] = env.monkUnits[^1]
        env.monkUnits.setLen(env.monkUnits.len - 1)
        break
  elif isMonk and not wasMonk:
    env.monkUnits.add(agent)

proc embarkAgent*(agent: Thing) =
  if agent.unitClass in {UnitBoat, UnitTradeCog}:
    return
  agent.embarkedUnitClass = agent.unitClass
  applyUnitClass(agent, UnitBoat)

proc disembarkAgent*(agent: Thing) =
  if agent.unitClass == UnitTradeCog:
    return  # Trade Cogs never disembark
  if agent.unitClass != UnitBoat:
    return
  var target = agent.embarkedUnitClass
  if target == UnitBoat:
    target = UnitVillager
  applyUnitClass(agent, target)
{.pop.}

proc scoreTerritory*(env: Environment): TerritoryScore =
  ## Compute territory ownership by nearest tint color (teams + clippy).
  var score: TerritoryScore
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
      bestTeam = MapRoomObjectsTeams
      for teamId in 0 ..< min(env.teamColors.len, MapRoomObjectsTeams):
        let teamColor = env.teamColors[teamId]
        let dr = tint.r - teamColor.r
        let dg = tint.g - teamColor.g
        let db = tint.b - teamColor.b
        let dist = dr * dr + dg * dg + db * db
        if dist < bestDist:
          bestDist = dist
          bestTeam = teamId
      if bestTeam == MapRoomObjectsTeams:
        inc score.clippyTiles
      elif bestTeam >= 0 and bestTeam < MapRoomObjectsTeams:
        inc score.teamTiles[bestTeam]
      inc score.scoredTiles
  score


proc setRallyPoint*(building: Thing, pos: IVec2) =
  ## Set a building's rally point. Trained units will auto-move here after spawning.
  building.rallyPoint = pos

proc clearRallyPoint*(building: Thing) =
  ## Clear a building's rally point.
  building.rallyPoint = ivec2(-1, -1)

proc hasRallyPoint*(building: Thing): bool =
  ## Check if a building has an active rally point.
  building.rallyPoint.x >= 0 and building.rallyPoint.y >= 0

proc rebuildObservationsForAgent(env: Environment, agentId: int, agent: Thing) {.inline.} =
  ## Rebuild all observation layers for a single agent.
  let agentPos = agent.pos
  for obsX in 0 ..< ObservationWidth:
    let worldX = agentPos.x + (obsX - ObservationRadius)
    if worldX < 0 or worldX >= MapWidth:
      continue
    for obsY in 0 ..< ObservationHeight:
      let worldY = agentPos.y + (obsY - ObservationRadius)
      if worldY < 0 or worldY >= MapHeight:
        continue
      writeTileObs(env, agentId, obsX, obsY, worldX, worldY)

proc rebuildObservations*(env: Environment) =
  ## Recompute all observation layers from the current environment state.
  ## Optimization: Only zero and rebuild observations for alive agents that moved.
  env.observationsInitialized = false

proc ensureObservations*(env: Environment) {.inline.} =
  ## Ensure observations are up-to-date (lazy rebuild if dirty).
  ## Call this before accessing env.observations directly.
  ## Optimized: only full rebuild for agents that moved. Stationary agents
  ## skip rebuild for major performance gain.
  if env.observationsDirty:
    env.rebuildObservations()
    env.observationsDirty = false

  let firstRun = not env.observationsInitialized

  for agentId in 0 ..< env.agents.len:
    let agent = env.agents[agentId]
    if not isAgentAlive(env, agent):
      # Dead agent: zero their observation slot if needed
      if env.observationsInitialized:
        zeroMem(addr env.observations[agentId], sizeof(env.observations[agentId]))
      env.lastObsAgentPos[agentId] = ivec2(-1, -1)
      continue

    let agentPos = agent.pos
    let lastPos = env.lastObsAgentPos[agentId]
    let agentMoved = lastPos.x != agentPos.x or lastPos.y != agentPos.y

    if firstRun or agentMoved:
      # Agent moved or first run: zero and full rebuild
      if not firstRun:
        zeroMem(addr env.observations[agentId], sizeof(env.observations[agentId]))
      rebuildObservationsForAgent(env, agentId, agent)
      env.lastObsAgentPos[agentId] = agentPos
    # else: Agent stationary - terrain/biome unchanged, skip rebuild
    # Note: Things could move in/out of view, but we accept this minor
    # staleness for major perf gain. Next movement will refresh.

  # Rally point layer: mark tiles that are rally targets for friendly buildings
  for thing in env.things:
    if not isBuildingKind(thing.kind):
      continue
    if not thing.hasRallyPoint():
      continue
    let rp = thing.rallyPoint
    if not isValidPos(rp):
      continue
    let buildingTeam = thing.teamId
    # Mark rally point in observations for agents on the same team
    for agentId in 0 ..< env.agents.len:
      let agent = env.agents[agentId]
      if not isAgentAlive(env, agent):
        continue
      if getTeamId(agent) != buildingTeam:
        continue
      let obsX = rp.x - agent.pos.x + ObservationRadius
      let obsY = rp.y - agent.pos.y + ObservationRadius
      if obsX < 0 or obsX >= ObservationWidth or obsY < 0 or obsY >= ObservationHeight:
        continue
      var agentObs = addr env.observations[agentId]
      agentObs[][ord(RallyPointLayer)][obsX][obsY] = 1

  env.observationsInitialized = true

{.push inline.}
proc getThing*(env: Environment, pos: IVec2): Thing =
  if not isValidPos(pos): nil else: env.grid[pos.x][pos.y]

proc getBackgroundThing*(env: Environment, pos: IVec2): Thing =
  if not isValidPos(pos): nil else: env.backgroundGrid[pos.x][pos.y]

proc isEmpty*(env: Environment, pos: IVec2): bool =
  ## True when no blocking unit occupies the tile.
  isValidPos(pos) and isNil(env.grid[pos.x][pos.y])

proc hasDoor*(env: Environment, pos: IVec2): bool =
  let door = env.getBackgroundThing(pos)
  not isNil(door) and door.kind == Door

proc canAgentPassDoor*(env: Environment, agent: Thing, pos: IVec2): bool =
  let door = env.getBackgroundThing(pos)
  isNil(door) or door.kind != Door or door.teamId == getTeamId(agent)

proc hasDockAt*(env: Environment, pos: IVec2): bool {.inline.} =
  let background = env.getBackgroundThing(pos)
  not isNil(background) and background.kind == Dock

proc isWaterUnit*(agent: Thing): bool {.inline.} =
  agent.unitClass in {UnitBoat, UnitTradeCog}

proc isWaterBlockedForAgent*(env: Environment, agent: Thing, pos: IVec2): bool {.inline.} =
  env.terrain[pos.x][pos.y] == Water and not agent.isWaterUnit and not env.hasDockAt(pos)
{.pop.}

proc canTraverseElevation*(env: Environment, fromPos, toPos: IVec2): bool {.inline.} =
  ## Allow flat movement, ramp-assisted elevation changes, or falling down cliffs.
  ## Going UP requires a ramp/road. Going DOWN is always allowed (but may cause fall damage).
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

  # Dropping down is always allowed (may cause fall damage)
  if elevFrom > elevTo:
    return true

  # Going up requires a ramp or road
  let terrainFrom = env.terrain[fromPos.x][fromPos.y]
  let terrainTo = env.terrain[toPos.x][toPos.y]
  terrainFrom == Road or terrainTo == Road or
    isRampTerrain(terrainFrom) or isRampTerrain(terrainTo)

proc willCauseCliffFallDamage*(env: Environment, fromPos, toPos: IVec2): bool {.inline.} =
  ## Check if moving from fromPos to toPos would cause cliff fall damage.
  ## Fall damage occurs when dropping elevation without using a ramp or road.
  if not isValidPos(fromPos) or not isValidPos(toPos):
    return false
  let elevFrom = env.elevation[fromPos.x][fromPos.y]
  let elevTo = env.elevation[toPos.x][toPos.y]
  if elevFrom <= elevTo:
    return false  # Not dropping elevation

  # Check if there's a ramp/road that would prevent fall damage
  let terrainFrom = env.terrain[fromPos.x][fromPos.y]
  let terrainTo = env.terrain[toPos.x][toPos.y]
  let hasRampOrRoad = terrainFrom == Road or terrainTo == Road or
    isRampTerrain(terrainFrom) or isRampTerrain(terrainTo)

  not hasRampOrRoad  # Fall damage if no ramp/road

proc isBuildableTerrain*(terrain: TerrainType): bool {.inline.} =
  terrain in BuildableTerrain

proc canPlace*(env: Environment, pos: IVec2, checkFrozen: bool = true): bool {.inline.} =
  isValidPos(pos) and env.isEmpty(pos) and isNil(env.getBackgroundThing(pos)) and
    (not checkFrozen or not isTileFrozen(pos, env)) and isBuildableTerrain(env.terrain[pos.x][pos.y])

proc isSpawnable*(env: Environment, pos: IVec2): bool {.inline.} =
  isValidPos(pos) and env.isEmpty(pos) and isNil(env.getBackgroundThing(pos)) and not env.hasDoor(pos)

proc canPlaceDock*(env: Environment, pos: IVec2, checkFrozen: bool = true): bool {.inline.} =
  isValidPos(pos) and env.isEmpty(pos) and isNil(env.getBackgroundThing(pos)) and
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
    let stockpileRes = stockpileResourceForItem(key)
    if stockpileRes in allowed:
      depositKeys.add(key)
  if depositKeys.len == 0:
    return false
  for key in depositKeys:
    let count = getInv(agent, key)
    if count <= 0:
      continue
    let stockpileRes = stockpileResourceForItem(key)
    env.addToStockpile(teamId, stockpileRes, count)
    when defined(eventLog):
      logResourceDeposited(teamId, $stockpileRes, count, env.currentStep)
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

proc queueTrainUnit*(env: Environment, building: Thing, teamId: int,
                     unitClass: AgentUnitClass,
                     costs: openArray[tuple[res: StockpileResource, count: int]]): bool =
  ## Queue a unit for training at a building (AoE2-style production queue).
  ## Resources are spent when queued. When a villager later interacts with the
  ## building and there's a ready entry, the villager is instantly converted
  ## without additional cost.
  if building.productionQueue.entries.len >= ProductionQueueMaxSize:
    return false
  if building.teamId != teamId:
    return false
  if not env.spendStockpile(teamId, costs):
    return false
  let trainTime = unitTrainTime(unitClass)
  building.productionQueue.entries.add(ProductionQueueEntry(
    unitClass: unitClass,
    totalSteps: trainTime,
    remainingSteps: trainTime
  ))
  true

proc cancelLastQueued*(env: Environment, building: Thing): bool =
  ## Cancel the last unit in the production queue, refunding resources.
  if building.productionQueue.entries.len == 0:
    return false
  building.productionQueue.entries.setLen(building.productionQueue.entries.len - 1)
  let teamId = building.teamId
  if teamId >= 0 and teamId < MapRoomObjectsTeams:
    let costs = buildingTrainCosts(building.kind)
    for cost in costs:
      env.teamStockpiles[teamId].counts[cost.res] += cost.count
  true

proc tryBatchQueueTrain*(env: Environment, building: Thing, teamId: int,
                         count: int): int =
  ## Queue multiple units for training (batch/shift-click).
  ## Returns the number of units actually queued.
  if not buildingHasTrain(building.kind):
    return 0
  let unitClass = buildingTrainUnit(building.kind, teamId)
  let costs = buildingTrainCosts(building.kind)
  var queued = 0
  for i in 0 ..< count:
    if not env.queueTrainUnit(building, teamId, unitClass, costs):
      break
    inc queued
  queued

proc productionQueueHasReady*(building: Thing): bool =
  ## Check if the building has a queue entry ready for conversion.
  building.productionQueue.entries.len > 0 and
    building.productionQueue.entries[0].remainingSteps <= 0

proc consumeReadyQueueEntry*(building: Thing): AgentUnitClass =
  ## Consume the front ready entry from the queue. Returns the unit class.
  ## Caller must verify productionQueueHasReady first.
  result = building.productionQueue.entries[0].unitClass
  building.productionQueue.entries.delete(0)

proc processProductionQueue*(building: Thing) =
  ## Tick one step of a building's production queue countdown.
  if building.productionQueue.entries.len > 0 and
     building.productionQueue.entries[0].remainingSteps > 0:
    building.productionQueue.entries[0].remainingSteps -= 1

proc getNextBlacksmithUpgrade(env: Environment, teamId: int): BlacksmithUpgradeType =
  ## Find the next upgrade to research (lowest level across all types).
  ## Returns the upgrade type with the lowest current level.
  var minLevel = BlacksmithUpgradeMaxLevel + 1
  result = UpgradeMeleeAttack  # Default
  for upgradeType in BlacksmithUpgradeType:
    let level = env.teamBlacksmithUpgrades[teamId].levels[upgradeType]
    if level < minLevel:
      minLevel = level
      result = upgradeType

proc tryResearchBlacksmithUpgrade*(env: Environment, agent: Thing, building: Thing): bool =
  ## Attempt to research the next Blacksmith upgrade for the team.
  ## Costs: Food + Gold, increasing by level.
  ## Returns true if research was successful.
  if agent.unitClass != UnitVillager:
    return false
  let teamId = getTeamId(agent)
  if building.teamId != teamId:
    return false
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false

  # Find the next upgrade to research
  let upgradeType = env.getNextBlacksmithUpgrade(teamId)
  let currentLevel = env.teamBlacksmithUpgrades[teamId].levels[upgradeType]

  # Check if already at max level
  if currentLevel >= BlacksmithUpgradeMaxLevel:
    return false

  # Calculate cost based on current level (level 0->1: base cost, 1->2: 2x, 2->3: 3x)
  let costMultiplier = currentLevel + 1
  let foodCost = BlacksmithUpgradeFoodCost * costMultiplier
  let goldCost = BlacksmithUpgradeGoldCost * costMultiplier

  # Check and spend resources
  let costs = [(ResourceFood, foodCost), (ResourceGold, goldCost)]
  if not env.spendStockpile(teamId, costs):
    return false

  # Apply the upgrade
  env.teamBlacksmithUpgrades[teamId].levels[upgradeType] = currentLevel + 1
  building.cooldown = 5  # Short cooldown after research
  when defined(eventLog):
    logTechResearched(teamId, "Blacksmith " & $upgradeType & " Level " & $(currentLevel + 1), env.currentStep)
  true

proc getNextUniversityTech(env: Environment, teamId: int): UniversityTechType =
  ## Find the next unresearched University tech.
  ## Returns techs in order: Ballistics first (most impactful for ranged combat).
  for techType in UniversityTechType:
    if not env.teamUniversityTechs[teamId].researched[techType]:
      return techType
  # All researched, return first (no-op in caller)
  TechBallistics

proc hasUniversityTech*(env: Environment, teamId: int, tech: UniversityTechType): bool {.inline.} =
  ## Check if a team has researched a specific University tech.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false
  env.teamUniversityTechs[teamId].researched[tech]

proc tryResearchUniversityTech*(env: Environment, agent: Thing, building: Thing): bool =
  ## Attempt to research the next University tech for the team.
  ## Costs: Food + Gold + Wood (varies by tech).
  ## Returns true if research was successful.
  if agent.unitClass != UnitVillager:
    return false
  let teamId = getTeamId(agent)
  if building.teamId != teamId:
    return false
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false

  # Find the next tech to research
  let techType = env.getNextUniversityTech(teamId)

  # Check if already researched
  if env.teamUniversityTechs[teamId].researched[techType]:
    return false

  # Calculate cost - costs increase for later techs
  let techIndex = ord(techType) + 1
  let foodCost = UniversityTechFoodCost * techIndex
  let goldCost = UniversityTechGoldCost * techIndex
  let woodCost = UniversityTechWoodCost * techIndex

  # Check and spend resources
  let costs = [(ResourceFood, foodCost), (ResourceGold, goldCost), (ResourceWood, woodCost)]
  if not env.spendStockpile(teamId, costs):
    return false

  # Apply the tech
  env.teamUniversityTechs[teamId].researched[techType] = true
  building.cooldown = 8  # Longer cooldown for tech research
  when defined(eventLog):
    logTechResearched(teamId, "University " & $techType, env.currentStep)
  true

proc castleTechsForTeam*(teamId: int): (CastleTechType, CastleTechType) =
  ## Returns the (Castle Age, Imperial Age) tech pair for a team.
  ## Each team has exactly 2 unique techs, interleaved in the enum.
  let base = CastleTechType(teamId * 2)
  let imperial = CastleTechType(teamId * 2 + 1)
  (base, imperial)

proc getNextCastleTech(env: Environment, teamId: int): CastleTechType =
  ## Find the next unresearched Castle tech for this team.
  ## Castle Age tech must be researched before Imperial Age tech.
  let (castleAge, imperialAge) = castleTechsForTeam(teamId)
  if not env.teamCastleTechs[teamId].researched[castleAge]:
    return castleAge
  if not env.teamCastleTechs[teamId].researched[imperialAge]:
    return imperialAge
  # Both researched, return castle age (no-op in caller)
  castleAge

proc hasCastleTech*(env: Environment, teamId: int, tech: CastleTechType): bool {.inline.} =
  ## Check if a team has researched a specific Castle unique tech.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false
  env.teamCastleTechs[teamId].researched[tech]

proc applyCastleTechBonuses*(env: Environment, teamId: int, tech: CastleTechType) =
  ## Apply the bonuses from a Castle unique tech to the team's modifiers.
  ## Called when a tech is researched.
  case tech
  of CastleTechYeomen:
    # +1 archer range (modeled as +1 archer attack), +2 tower attack
    env.teamModifiers[teamId].unitAttackBonus[UnitArcher] += 1
    env.teamModifiers[teamId].unitAttackBonus[UnitLongbowman] += 1
    env.teamModifiers[teamId].unitAttackBonus[UnitCrossbowman] += 1
    env.teamModifiers[teamId].unitAttackBonus[UnitArbalester] += 1
  of CastleTechKataparuto:
    # +3 trebuchet attack
    env.teamModifiers[teamId].unitAttackBonus[UnitTrebuchet] += 3
  of CastleTechLogistica:
    # +1 infantry attack
    env.teamModifiers[teamId].unitAttackBonus[UnitManAtArms] += 1
    env.teamModifiers[teamId].unitAttackBonus[UnitSamurai] += 1
    env.teamModifiers[teamId].unitAttackBonus[UnitWoadRaider] += 1
    env.teamModifiers[teamId].unitAttackBonus[UnitTeutonicKnight] += 1
    env.teamModifiers[teamId].unitAttackBonus[UnitHuskarl] += 1
    env.teamModifiers[teamId].unitAttackBonus[UnitLongSwordsman] += 1
    env.teamModifiers[teamId].unitAttackBonus[UnitChampion] += 1
  of CastleTechCrenellations:
    # +2 castle attack (applied via hasCastleTech check in tower attack)
    discard
  of CastleTechGreekFire:
    # +2 tower attack vs siege (applied via hasCastleTech check in tower attack)
    discard
  of CastleTechFurorCeltica:
    # +2 siege attack
    env.teamModifiers[teamId].unitAttackBonus[UnitBatteringRam] += 2
    env.teamModifiers[teamId].unitAttackBonus[UnitMangonel] += 2
    env.teamModifiers[teamId].unitAttackBonus[UnitTrebuchet] += 2
  of CastleTechAnarchy:
    # +1 infantry HP
    env.teamModifiers[teamId].unitHpBonus[UnitManAtArms] += 1
    env.teamModifiers[teamId].unitHpBonus[UnitSamurai] += 1
    env.teamModifiers[teamId].unitHpBonus[UnitWoadRaider] += 1
    env.teamModifiers[teamId].unitHpBonus[UnitTeutonicKnight] += 1
    env.teamModifiers[teamId].unitHpBonus[UnitHuskarl] += 1
    env.teamModifiers[teamId].unitHpBonus[UnitLongSwordsman] += 1
    env.teamModifiers[teamId].unitHpBonus[UnitChampion] += 1
  of CastleTechPerfusion:
    # Military units train faster (modeled as +2 all military attack)
    env.teamModifiers[teamId].unitAttackBonus[UnitManAtArms] += 2
    env.teamModifiers[teamId].unitAttackBonus[UnitArcher] += 2
    env.teamModifiers[teamId].unitAttackBonus[UnitScout] += 2
    env.teamModifiers[teamId].unitAttackBonus[UnitKnight] += 2
    env.teamModifiers[teamId].unitAttackBonus[UnitLongSwordsman] += 2
    env.teamModifiers[teamId].unitAttackBonus[UnitChampion] += 2
    env.teamModifiers[teamId].unitAttackBonus[UnitLightCavalry] += 2
    env.teamModifiers[teamId].unitAttackBonus[UnitHussar] += 2
    env.teamModifiers[teamId].unitAttackBonus[UnitCrossbowman] += 2
    env.teamModifiers[teamId].unitAttackBonus[UnitArbalester] += 2
  of CastleTechIronclad:
    # +3 siege HP
    env.teamModifiers[teamId].unitHpBonus[UnitBatteringRam] += 3
    env.teamModifiers[teamId].unitHpBonus[UnitMangonel] += 3
    env.teamModifiers[teamId].unitHpBonus[UnitTrebuchet] += 3
  of CastleTechCrenellations2:
    # +2 castle attack (applied via hasCastleTech check in tower attack)
    discard
  of CastleTechBerserkergang:
    # +2 infantry HP
    env.teamModifiers[teamId].unitHpBonus[UnitManAtArms] += 2
    env.teamModifiers[teamId].unitHpBonus[UnitSamurai] += 2
    env.teamModifiers[teamId].unitHpBonus[UnitWoadRaider] += 2
    env.teamModifiers[teamId].unitHpBonus[UnitTeutonicKnight] += 2
    env.teamModifiers[teamId].unitHpBonus[UnitHuskarl] += 2
    env.teamModifiers[teamId].unitHpBonus[UnitLongSwordsman] += 2
    env.teamModifiers[teamId].unitHpBonus[UnitChampion] += 2
  of CastleTechChieftains:
    # +1 cavalry attack
    env.teamModifiers[teamId].unitAttackBonus[UnitScout] += 1
    env.teamModifiers[teamId].unitAttackBonus[UnitKnight] += 1
    env.teamModifiers[teamId].unitAttackBonus[UnitCataphract] += 1
    env.teamModifiers[teamId].unitAttackBonus[UnitMameluke] += 1
    env.teamModifiers[teamId].unitAttackBonus[UnitLightCavalry] += 1
    env.teamModifiers[teamId].unitAttackBonus[UnitHussar] += 1
  of CastleTechZealotry:
    # +2 cavalry HP
    env.teamModifiers[teamId].unitHpBonus[UnitScout] += 2
    env.teamModifiers[teamId].unitHpBonus[UnitKnight] += 2
    env.teamModifiers[teamId].unitHpBonus[UnitCataphract] += 2
    env.teamModifiers[teamId].unitHpBonus[UnitMameluke] += 2
    env.teamModifiers[teamId].unitHpBonus[UnitLightCavalry] += 2
    env.teamModifiers[teamId].unitHpBonus[UnitHussar] += 2
  of CastleTechMahayana:
    # +1 monk effectiveness (modeled as +1 monk attack)
    env.teamModifiers[teamId].unitAttackBonus[UnitMonk] += 1
  of CastleTechSipahi:
    # +2 archer HP
    env.teamModifiers[teamId].unitHpBonus[UnitArcher] += 2
    env.teamModifiers[teamId].unitHpBonus[UnitLongbowman] += 2
    env.teamModifiers[teamId].unitHpBonus[UnitJanissary] += 2
    env.teamModifiers[teamId].unitHpBonus[UnitCrossbowman] += 2
    env.teamModifiers[teamId].unitHpBonus[UnitArbalester] += 2
  of CastleTechArtillery:
    # +2 tower and castle attack (applied via hasCastleTech check in tower attack)
    discard

proc tryResearchCastleTech*(env: Environment, agent: Thing, building: Thing): bool =
  ## Attempt to research the next Castle unique tech for the team.
  ## Each team has 2 unique techs (Castle Age first, then Imperial Age).
  ## Only villagers can research. Returns true if research was successful.
  if agent.unitClass != UnitVillager:
    return false
  let teamId = getTeamId(agent)
  if building.teamId != teamId:
    return false
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false

  # Find the next tech to research for this team
  let techType = env.getNextCastleTech(teamId)

  # Check if already researched
  if env.teamCastleTechs[teamId].researched[techType]:
    return false

  # Determine cost based on whether this is Castle Age or Imperial Age tech
  let (castleAge, _) = castleTechsForTeam(teamId)
  let isImperial = techType != castleAge
  let foodCost = if isImperial: CastleTechImperialFoodCost else: CastleTechFoodCost
  let goldCost = if isImperial: CastleTechImperialGoldCost else: CastleTechGoldCost

  # Check and spend resources
  let costs = [(ResourceFood, foodCost), (ResourceGold, goldCost)]
  if not env.spendStockpile(teamId, costs):
    return false

  # Apply the tech
  env.teamCastleTechs[teamId].researched[techType] = true
  env.applyCastleTechBonuses(teamId, techType)
  building.cooldown = 10  # Longer cooldown for unique tech research
  when defined(eventLog):
    logTechResearched(teamId, "Castle " & $techType, env.currentStep)
  true

# ---- Unit upgrade / promotion chain logic (AoE2-style) ----

proc upgradePrerequisite*(upgrade: UnitUpgradeType): UnitUpgradeType =
  ## Returns the prerequisite upgrade that must be researched first.
  ## Tier-2 upgrades have no prerequisite (returns themselves).
  ## Tier-3 upgrades require the corresponding tier-2.
  case upgrade
  of UpgradeLongSwordsman: UpgradeLongSwordsman  # no prereq
  of UpgradeChampion: UpgradeLongSwordsman
  of UpgradeLightCavalry: UpgradeLightCavalry    # no prereq
  of UpgradeHussar: UpgradeLightCavalry
  of UpgradeCrossbowman: UpgradeCrossbowman      # no prereq
  of UpgradeArbalester: UpgradeCrossbowman

proc upgradeSourceUnit*(upgrade: UnitUpgradeType): AgentUnitClass =
  ## Returns the unit class that gets upgraded.
  case upgrade
  of UpgradeLongSwordsman: UnitManAtArms
  of UpgradeChampion: UnitLongSwordsman
  of UpgradeLightCavalry: UnitScout
  of UpgradeHussar: UnitLightCavalry
  of UpgradeCrossbowman: UnitArcher
  of UpgradeArbalester: UnitCrossbowman

proc upgradeTargetUnit*(upgrade: UnitUpgradeType): AgentUnitClass =
  ## Returns the unit class that results from the upgrade.
  case upgrade
  of UpgradeLongSwordsman: UnitLongSwordsman
  of UpgradeChampion: UnitChampion
  of UpgradeLightCavalry: UnitLightCavalry
  of UpgradeHussar: UnitHussar
  of UpgradeCrossbowman: UnitCrossbowman
  of UpgradeArbalester: UnitArbalester

proc upgradeBuilding*(upgrade: UnitUpgradeType): ThingKind =
  ## Returns the building where this upgrade is researched.
  case upgrade
  of UpgradeLongSwordsman, UpgradeChampion: Barracks
  of UpgradeLightCavalry, UpgradeHussar: Stable
  of UpgradeCrossbowman, UpgradeArbalester: ArcheryRange

proc upgradeCosts*(upgrade: UnitUpgradeType): seq[tuple[res: StockpileResource, count: int]] =
  ## Returns the resource costs for an upgrade.
  case upgrade
  of UpgradeLongSwordsman, UpgradeLightCavalry, UpgradeCrossbowman:
    @[(res: ResourceFood, count: UnitUpgradeTier2FoodCost),
      (res: ResourceGold, count: UnitUpgradeTier2GoldCost)]
  of UpgradeChampion, UpgradeHussar, UpgradeArbalester:
    @[(res: ResourceFood, count: UnitUpgradeTier3FoodCost),
      (res: ResourceGold, count: UnitUpgradeTier3GoldCost)]

proc hasUnitUpgrade*(env: Environment, teamId: int, upgrade: UnitUpgradeType): bool {.inline.} =
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false
  env.teamUnitUpgrades[teamId].researched[upgrade]

proc getNextUnitUpgrade*(env: Environment, teamId: int, buildingKind: ThingKind): UnitUpgradeType =
  ## Find the next available upgrade for the given building type.
  ## Returns the first unresearched upgrade whose prerequisites are met.
  for upgrade in UnitUpgradeType:
    if upgradeBuilding(upgrade) != buildingKind:
      continue
    if env.teamUnitUpgrades[teamId].researched[upgrade]:
      continue
    # Check prerequisite
    let prereq = upgradePrerequisite(upgrade)
    if prereq != upgrade and not env.teamUnitUpgrades[teamId].researched[prereq]:
      continue
    return upgrade
  # No upgrades available; return first of this building type (caller checks researched)
  for upgrade in UnitUpgradeType:
    if upgradeBuilding(upgrade) == buildingKind:
      return upgrade
  UpgradeLongSwordsman  # fallback

proc upgradeExistingUnits*(env: Environment, teamId: int, fromClass: AgentUnitClass, toClass: AgentUnitClass) =
  ## Upgrade all living units of fromClass on the given team to toClass.
  ## Preserves current HP ratio.
  for agent in env.agents:
    if agent.isNil:
      continue
    if env.terminated[agent.agentId] != 0.0:
      continue
    if getTeamId(agent) != teamId:
      continue
    if agent.unitClass != fromClass:
      continue
    let hpRatio = if agent.maxHp > 0: agent.hp.float / agent.maxHp.float else: 1.0
    let modifiers = env.teamModifiers[teamId]
    agent.unitClass = toClass
    if toClass != UnitBoat:
      agent.embarkedUnitClass = toClass
    agent.maxHp = UnitMaxHpByClass[toClass] + modifiers.unitHpBonus[toClass]
    agent.attackDamage = UnitAttackDamageByClass[toClass] + modifiers.unitAttackBonus[toClass]
    agent.hp = max(1, int(hpRatio * agent.maxHp.float))

proc tryResearchUnitUpgrade*(env: Environment, agent: Thing, building: Thing): bool =
  ## Attempt to research the next unit upgrade at a military building.
  ## Only villagers can research. Returns true if research was successful.
  if agent.unitClass != UnitVillager:
    return false
  let teamId = getTeamId(agent)
  if building.teamId != teamId:
    return false
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false

  let upgrade = env.getNextUnitUpgrade(teamId, building.kind)

  # Check if already researched
  if env.teamUnitUpgrades[teamId].researched[upgrade]:
    return false

  # Check prerequisite
  let prereq = upgradePrerequisite(upgrade)
  if prereq != upgrade and not env.teamUnitUpgrades[teamId].researched[prereq]:
    return false

  # Check and spend resources
  let costs = upgradeCosts(upgrade)
  if not env.spendStockpile(teamId, costs):
    return false

  # Apply the upgrade
  env.teamUnitUpgrades[teamId].researched[upgrade] = true
  env.upgradeExistingUnits(teamId, upgradeSourceUnit(upgrade), upgradeTargetUnit(upgrade))
  building.cooldown = 8
  when defined(eventLog):
    logTechResearched(teamId, "Unit Upgrade " & $upgrade, env.currentStep)
  true

proc effectiveTrainUnit*(env: Environment, buildingKind: ThingKind, teamId: int): AgentUnitClass =
  ## Returns the effective unit class trained by a building, considering upgrades.
  ## For example, if LongSwordsman upgrade is researched, Barracks trains LongSwordsman instead of ManAtArms.
  let baseUnit = buildingTrainUnit(buildingKind, teamId)
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return baseUnit
  # Check upgrade chain for the base unit
  case baseUnit
  of UnitManAtArms:
    if env.teamUnitUpgrades[teamId].researched[UpgradeChampion]:
      return UnitChampion
    if env.teamUnitUpgrades[teamId].researched[UpgradeLongSwordsman]:
      return UnitLongSwordsman
    return UnitManAtArms
  of UnitScout:
    if env.teamUnitUpgrades[teamId].researched[UpgradeHussar]:
      return UnitHussar
    if env.teamUnitUpgrades[teamId].researched[UpgradeLightCavalry]:
      return UnitLightCavalry
    return UnitScout
  of UnitArcher:
    if env.teamUnitUpgrades[teamId].researched[UpgradeArbalester]:
      return UnitArbalester
    if env.teamUnitUpgrades[teamId].researched[UpgradeCrossbowman]:
      return UnitCrossbowman
    return UnitArcher
  else:
    return baseUnit

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
        let stockpileRes = stockpileResourceForItem(input.key)
        if env.stockpileCount(teamId, stockpileRes) < input.count:
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
  env.rewards[agent.agentId] += env.config.woodReward
  # Apply biome gathering bonus
  let bonus = env.getBiomeGatherBonus(tree.pos, ItemWood)
  if bonus > 0:
    discard env.grantItem(agent, ItemWood, bonus)
  when defined(eventLog):
    logResourceGathered(getTeamId(agent), "Wood", 1 + bonus, env.currentStep)
  let stumpPos = tree.pos  # Capture before pool release
  removeThing(env, tree)
  let stump = acquireThing(env, Stump)
  stump.pos = stumpPos
  stump.inventory = emptyInventory()
  let remaining = ResourceNodeInitial - 1
  if remaining > 0:
    setInv(stump, ItemWood, remaining)
  env.add(stump)
  true

proc spawnDamageNumber*(env: Environment, pos: IVec2, amount: int,
                        kind: DamageNumberKind = DmgNumDamage) =
  ## Spawn a floating damage number at the given position.
  ## Numbers float upward and fade out over DamageNumberLifetime frames.
  if amount <= 0 or not isValidPos(pos):
    return
  env.damageNumbers.add(DamageNumber(
    pos: pos, amount: amount, kind: kind,
    countdown: DamageNumberLifetime, lifetime: DamageNumberLifetime))

include "combat_audit"
include "tumor_audit"
include "combat"

# ============== CLIPPY AI ==============




{.push inline.}
proc isValidEmptyPosition(env: Environment, pos: IVec2): bool =
  ## Check if a position is within map bounds, empty, and not blocked terrain
  pos.x >= MapBorder and pos.x < MapWidth - MapBorder and
    pos.y >= MapBorder and pos.y < MapHeight - MapBorder and
    env.isEmpty(pos) and isNil(env.getBackgroundThing(pos)) and
    not isBlockedTerrain(env.terrain[pos.x][pos.y])

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
        continue
      let pos = ivec2(center.x + dx, center.y + dy)
      if env.isValidEmptyPosition(pos):
        result.add(pos)

proc findFirstEmptyPositionAround*(env: Environment, center: IVec2, radius: int): IVec2 =
  ## Find first empty position around center (no allocation)
  for dx in -radius .. radius:
    for dy in -radius .. radius:
      if dx == 0 and dy == 0:
        continue
      let pos = ivec2(center.x + dx, center.y + dy)
      if env.isValidEmptyPosition(pos):
        return pos
  ivec2(-1, -1)

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
    let buildIndex = BuildingRegistry[kind].buildIndex
    if buildIndex >= 0 and buildIndex < choices.len:
      choices[buildIndex] = thingItem($kind)
  choices[BuildIndexWall] = thingItem("Wall")
  choices[BuildIndexRoad] = thingItem("Road")
  choices[BuildIndexDoor] = thingItem("Door")
  choices

proc render*(env: Environment): string =
  for y in 0 ..< MapHeight:
    for x in 0 ..< MapWidth:
      # First check terrain
      var cell = $TerrainCatalog[env.terrain[x][y]].ascii
      # Then override with objects if present (blocking first, background second)
      let blockingThing = env.grid[x][y]
      let thing = if not isNil(blockingThing): blockingThing else: env.backgroundGrid[x][y]
      if not isNil(thing):
        let kind = thing.kind
        let ascii = if isBuildingKind(kind): BuildingRegistry[kind].ascii else: ThingCatalog[kind].ascii
        cell = $ascii
      result.add(cell)
    result.add("\n")

include "connectivity"
include "spawn"
include "console_viz"
include "gather_heatmap"
include "step"
