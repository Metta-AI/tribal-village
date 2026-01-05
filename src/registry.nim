type
  BuildingUseKind* = enum
    UseNone
    UseAltar
    UseArmory
    UseClayOven
    UseWeavingLoom
    UseBlacksmith
    UseMarket
    UseDropoff
    UseDropoffAndStorage
    UseStorage
    UseTrain
    UseTrainAndCraft
    UseCraft

  BuildingTickKind* = enum
    TickNone
    TickMillFertile

  BuildingInfo* = object
    isBuilding*: bool
    displayName*: string
    spriteKey*: string
    ascii*: char
    renderColor*: tuple[r, g, b: uint8]
    needsLantern*: bool
    hasFrozenOverlay*: bool
    usesCooldown*: bool
    teamOwned*: bool
    showStockpile*: bool
    stockpileRes*: StockpileResource
    buildable*: bool
    buildIndex*: int
    buildCost*: seq[ItemAmount]
    buildStation*: CraftStation
    buildCooldown*: int
    popCap*: int
    barrelCapacity*: int
    fertileRadius*: int
    useKind*: BuildingUseKind
    dropoffResources*: set[StockpileResource]
    storageItems*: seq[ItemKey]
    hasCraftStation*: bool
    craftStation*: CraftStation
    hasTrain*: bool
    trainUnit*: AgentUnitClass
    trainCosts*: seq[tuple[res: StockpileResource, count: int]]
    trainCooldown*: int
    tickKind*: BuildingTickKind
    tickCooldown*: int

proc initBuildingRegistry(): array[ThingKind, BuildingInfo] =
  var reg: array[ThingKind, BuildingInfo]
  for kind in ThingKind:
    reg[kind] = BuildingInfo(
      isBuilding: false,
      displayName: "",
      spriteKey: "",
      ascii: '?',
      renderColor: (r: 180'u8, g: 180'u8, b: 180'u8),
      needsLantern: false,
      hasFrozenOverlay: false,
      usesCooldown: false,
      teamOwned: false,
      showStockpile: false,
      stockpileRes: ResourceFood,
      buildable: false,
      buildIndex: -1,
      buildCost: @[],
      buildStation: StationTable,
      buildCooldown: 8,
      popCap: 0,
      barrelCapacity: 0,
      fertileRadius: 0,
      useKind: UseNone,
      dropoffResources: {},
      storageItems: @[],
      hasCraftStation: false,
      craftStation: StationTable,
      hasTrain: false,
      trainUnit: UnitVillager,
      trainCosts: @[],
      trainCooldown: 0,
      tickKind: TickNone,
      tickCooldown: 0
    )

  proc add(kind: ThingKind, displayName, spriteKey: string, ascii: char,
           renderColor: tuple[r, g, b: uint8], teamOwned = true,
           needsLantern = true, hasFrozenOverlay = true, usesCooldown = true,
           showStockpile = false, stockpileRes = ResourceFood,
           buildable = false, buildIndex = -1, buildCost: seq[ItemAmount] = @[],
           buildStation = StationTable, buildCooldown = 8, popCap = 0, barrelCapacity = 0,
           fertileRadius = 0, useKind = UseNone,
           dropoffResources: set[StockpileResource] = {},
           storageItems: seq[ItemKey] = @[],
           hasCraftStation = false, craftStation = StationTable,
           hasTrain = false, trainUnit = UnitVillager,
           trainCosts: seq[tuple[res: StockpileResource, count: int]] = @[],
           trainCooldown = 0, tickKind = TickNone, tickCooldown = 0) =
    reg[kind] = BuildingInfo(
      isBuilding: true,
      displayName: displayName,
      spriteKey: spriteKey,
      ascii: ascii,
      renderColor: renderColor,
      needsLantern: needsLantern,
      hasFrozenOverlay: hasFrozenOverlay,
      usesCooldown: usesCooldown,
      teamOwned: teamOwned,
      showStockpile: showStockpile,
      stockpileRes: stockpileRes,
      buildable: buildable,
      buildIndex: buildIndex,
      buildCost: buildCost,
      buildStation: buildStation,
      popCap: popCap,
      barrelCapacity: barrelCapacity,
      fertileRadius: fertileRadius,
      useKind: useKind,
      dropoffResources: dropoffResources,
      storageItems: storageItems,
      hasCraftStation: hasCraftStation,
      craftStation: craftStation,
      hasTrain: hasTrain,
      trainUnit: trainUnit,
      trainCosts: trainCosts,
      trainCooldown: trainCooldown,
      tickKind: tickKind,
      tickCooldown: tickCooldown,
      buildCooldown: buildCooldown
    )

  add(Altar, "Altar", "altar", 'a', (r: 220'u8, g: 0'u8, b: 220'u8),
      usesCooldown = false, needsLantern = true, useKind = UseAltar)
  add(TownCenter, "Town Center", "town_center", 'N', (r: 190'u8, g: 180'u8, b: 140'u8),
      buildable = true, buildIndex = 1, buildCost = @[(ItemWood, 14)], buildCooldown = 16,
      useKind = UseDropoff, dropoffResources = {ResourceFood, ResourceWood, ResourceGold, ResourceStone},
      popCap = TownCenterPopCap)
  add(House, "House", "house", 'h', (r: 170'u8, g: 140'u8, b: 110'u8),
      buildable = true, buildIndex = 0, buildCost = @[(ItemWood, 1)], buildCooldown = 10,
      popCap = HousePopCap)
  add(Armory, "Armory", "armory", 'A', (r: 255'u8, g: 120'u8, b: 40'u8),
      buildable = true, buildIndex = 19, buildCost = @[(ItemWood, 4)], buildCooldown = 12,
      useKind = UseArmory, usesCooldown = true)
  add(ClayOven, "Clay Oven", "clay_oven", 'C', (r: 255'u8, g: 180'u8, b: 120'u8),
      buildable = true, buildIndex = 20, buildCost = @[(ItemWood, 4)], buildCooldown = 12,
      useKind = UseClayOven, usesCooldown = true, hasCraftStation = true, craftStation = StationOven)
  add(WeavingLoom, "Weaving Loom", "weaving_loom", 'W', (r: 0'u8, g: 180'u8, b: 255'u8),
      buildable = true, buildIndex = 21, buildCost = @[(ItemWood, 3)], buildCooldown = 12,
      useKind = UseWeavingLoom, usesCooldown = true, hasCraftStation = true, craftStation = StationLoom)
  add(Outpost, "Outpost", "outpost", '^', (r: 120'u8, g: 120'u8, b: 140'u8),
      usesCooldown = false, buildable = true, buildIndex = 13, buildCost = @[(ItemWood, 1)],
      buildCooldown = 8)
  add(Barrel, "Barrel", "barrel", 'b', (r: 150'u8, g: 110'u8, b: 60'u8),
      needsLantern = false, usesCooldown = false, teamOwned = false,
      buildable = true, buildIndex = 22, buildCost = @[(ItemWood, 2)], buildCooldown = 10,
      useKind = UseStorage, storageItems = @[], barrelCapacity = BarrelCapacity)
  add(Mill, "Granary", "granary", 'm', (r: 210'u8, g: 200'u8, b: 170'u8),
      usesCooldown = false, showStockpile = true, stockpileRes = ResourceFood,
      buildable = true, buildIndex = 2, buildCost = @[(ItemWood, 5)], buildCooldown = 12,
      useKind = UseDropoffAndStorage, dropoffResources = {ResourceFood}, storageItems = @[ItemWheat],
      barrelCapacity = BarrelCapacity, fertileRadius = 2, tickKind = TickMillFertile, tickCooldown = 10)
  add(LumberCamp, "Lumber Yard", "lumber_yard", 'L', (r: 140'u8, g: 100'u8, b: 60'u8),
      usesCooldown = false, showStockpile = true, stockpileRes = ResourceWood,
      buildable = true, buildIndex = 3, buildCost = @[(ItemWood, 5)], buildCooldown = 10,
      useKind = UseDropoff, dropoffResources = {ResourceWood}, barrelCapacity = BarrelCapacity)
  add(MiningCamp, "Quarry", "quarry", 'G', (r: 120'u8, g: 120'u8, b: 120'u8),
      usesCooldown = false, showStockpile = true, stockpileRes = ResourceStone,
      buildable = true, buildIndex = 4, buildCost = @[(ItemWood, 5)], buildCooldown = 12,
      useKind = UseDropoffAndStorage, dropoffResources = {ResourceGold, ResourceStone},
      storageItems = @[ItemRock], barrelCapacity = BarrelCapacity)
  add(Bank, "Bank", "bank", 'B', (r: 220'u8, g: 200'u8, b: 120'u8),
      usesCooldown = false, showStockpile = true, stockpileRes = ResourceGold)
  add(Barracks, "Barracks", "barracks", 'r', (r: 160'u8, g: 90'u8, b: 60'u8),
      buildable = true, buildIndex = 8, buildCost = @[(ItemWood, 9)], buildCooldown = 12,
      useKind = UseTrain, hasTrain = true, trainUnit = UnitManAtArms,
      trainCosts = @[(res: ResourceFood, count: 3), (res: ResourceGold, count: 1)],
      trainCooldown = 8)
  add(ArcheryRange, "Archery Range", "archery_range", 'g', (r: 140'u8, g: 120'u8, b: 180'u8),
      buildable = true, buildIndex = 9, buildCost = @[(ItemWood, 9)], buildCooldown = 12,
      useKind = UseTrain, hasTrain = true, trainUnit = UnitArcher,
      trainCosts = @[(res: ResourceWood, count: 2), (res: ResourceGold, count: 2)],
      trainCooldown = 8)
  add(Stable, "Stable", "stable", 's', (r: 120'u8, g: 90'u8, b: 60'u8),
      buildable = true, buildIndex = 10, buildCost = @[(ItemWood, 9)], buildCooldown = 12,
      useKind = UseTrain, hasTrain = true, trainUnit = UnitScout,
      trainCosts = @[(res: ResourceFood, count: 3)],
      trainCooldown = 8)
  add(SiegeWorkshop, "Siege Workshop", "siege_workshop", 'i', (r: 120'u8, g: 120'u8, b: 160'u8),
      buildable = true, buildIndex = 11, buildCost = @[(ItemWood, 10)], buildCooldown = 14,
      useKind = UseTrainAndCraft, hasCraftStation = true, craftStation = StationSiegeWorkshop,
      hasTrain = true, trainUnit = UnitSiege,
      trainCosts = @[(res: ResourceWood, count: 3), (res: ResourceStone, count: 2)],
      trainCooldown = 10)
  add(Blacksmith, "Blacksmith", "blacksmith", 'k', (r: 90'u8, g: 90'u8, b: 90'u8),
      buildable = true, buildIndex = 16, buildCost = @[(ItemWood, 8)], buildCooldown = 12,
      useKind = UseBlacksmith, usesCooldown = true, hasCraftStation = true, craftStation = StationBlacksmith,
      storageItems = @[ItemArmor, ItemSpear], barrelCapacity = BarrelCapacity)
  add(Market, "Market", "market", 'e', (r: 200'u8, g: 170'u8, b: 120'u8),
      buildable = true, buildIndex = 7, buildCost = @[(ItemWood, 9)], buildCooldown = 12,
      useKind = UseMarket, usesCooldown = true)
  add(Dock, "Dock", "dock", 'd', (r: 80'u8, g: 140'u8, b: 200'u8),
      buildable = true, buildIndex = 6, buildCost = @[(ItemWood, 8)], buildCooldown = 12,
      useKind = UseDropoff, dropoffResources = {ResourceFood})
  add(Monastery, "Monastery", "monastery", 'y', (r: 220'u8, g: 200'u8, b: 120'u8),
      buildable = true, buildIndex = 17, buildCost = @[(ItemWood, 9)], buildCooldown = 12,
      useKind = UseTrain, hasTrain = true, trainUnit = UnitMonk,
      trainCosts = @[(res: ResourceGold, count: 2)],
      trainCooldown = 10)
  add(University, "University", "university", 'u', (r: 140'u8, g: 160'u8, b: 200'u8),
      buildable = true, buildIndex = 18, buildCost = @[(ItemWood, 10)], buildCooldown = 14,
      useKind = UseNone, usesCooldown = true)
  add(Castle, "Castle", "castle", 'c', (r: 120'u8, g: 120'u8, b: 120'u8),
      buildable = true, buildIndex = 12, buildCost = @[(ItemStone, 33)], buildCooldown = 20,
      useKind = UseTrain, hasTrain = true, trainUnit = UnitKnight,
      trainCosts = @[(res: ResourceFood, count: 4), (res: ResourceGold, count: 2)],
      trainCooldown = 12)

  reg

let BuildingRegistry* = initBuildingRegistry()

proc buildingInfo*(kind: ThingKind): BuildingInfo =
  BuildingRegistry[kind]

proc isBuildingKind*(kind: ThingKind): bool =
  BuildingRegistry[kind].isBuilding

proc buildingSpriteKey*(kind: ThingKind): string =
  BuildingRegistry[kind].spriteKey

proc buildingDisplayName*(kind: ThingKind): string =
  BuildingRegistry[kind].displayName

proc buildingAscii*(kind: ThingKind): char =
  BuildingRegistry[kind].ascii

proc buildingRenderColor*(kind: ThingKind): tuple[r, g, b: uint8] =
  BuildingRegistry[kind].renderColor

proc buildingNeedsLantern*(kind: ThingKind): bool =
  BuildingRegistry[kind].needsLantern

proc buildingHasFrozenOverlay*(kind: ThingKind): bool =
  BuildingRegistry[kind].hasFrozenOverlay

proc buildingUsesCooldown*(kind: ThingKind): bool =
  BuildingRegistry[kind].usesCooldown

proc buildingTeamOwned*(kind: ThingKind): bool =
  BuildingRegistry[kind].teamOwned

proc buildingShowsStockpile*(kind: ThingKind): bool =
  BuildingRegistry[kind].showStockpile

proc buildingStockpileRes*(kind: ThingKind): StockpileResource =
  BuildingRegistry[kind].stockpileRes

proc buildingBuildIndex*(kind: ThingKind): int =
  BuildingRegistry[kind].buildIndex

proc buildingBuildable*(kind: ThingKind): bool =
  BuildingRegistry[kind].buildable

proc buildingBuildCost*(kind: ThingKind): seq[ItemAmount] =
  BuildingRegistry[kind].buildCost

proc buildingBuildStation*(kind: ThingKind): CraftStation =
  BuildingRegistry[kind].buildStation

proc buildingBuildCooldown*(kind: ThingKind): int =
  BuildingRegistry[kind].buildCooldown

proc buildingPopCap*(kind: ThingKind): int =
  BuildingRegistry[kind].popCap

proc buildingBarrelCapacity*(kind: ThingKind): int =
  BuildingRegistry[kind].barrelCapacity

proc buildingFertileRadius*(kind: ThingKind): int =
  BuildingRegistry[kind].fertileRadius

proc buildingUseKind*(kind: ThingKind): BuildingUseKind =
  BuildingRegistry[kind].useKind

proc buildingDropoffResources*(kind: ThingKind): set[StockpileResource] =
  BuildingRegistry[kind].dropoffResources

proc buildingStorageItems*(kind: ThingKind): seq[ItemKey] =
  BuildingRegistry[kind].storageItems

proc buildingHasCraftStation*(kind: ThingKind): bool =
  BuildingRegistry[kind].hasCraftStation

proc buildingCraftStation*(kind: ThingKind): CraftStation =
  BuildingRegistry[kind].craftStation

proc buildingHasTrain*(kind: ThingKind): bool =
  BuildingRegistry[kind].hasTrain

proc buildingTrainUnit*(kind: ThingKind): AgentUnitClass =
  BuildingRegistry[kind].trainUnit

proc buildingTrainCosts*(kind: ThingKind): seq[tuple[res: StockpileResource, count: int]] =
  BuildingRegistry[kind].trainCosts

proc buildingTrainCooldown*(kind: ThingKind): int =
  BuildingRegistry[kind].trainCooldown

proc buildingTickKind*(kind: ThingKind): BuildingTickKind =
  BuildingRegistry[kind].tickKind

proc buildingTickCooldown*(kind: ThingKind): int =
  BuildingRegistry[kind].tickCooldown

proc buildIndexFor*(kind: ThingKind): int =
  BuildingRegistry[kind].buildIndex

proc toSnakeCase(name: string): string =
  result = ""
  for i, ch in name:
    if ch.isUpperAscii:
      if i > 0:
        result.add('_')
      result.add(ch.toLowerAscii)
    else:
      result.add(ch)

proc appendBuildingRecipes*(recipes: var seq[CraftRecipe]) =
  for kind in ThingKind:
    if not isBuildingKind(kind):
      continue
    if not buildingBuildable(kind):
      continue
    let costs = buildingBuildCost(kind)
    if costs.len == 0:
      continue
    let id = toSnakeCase($kind)
    let station = buildingBuildStation(kind)
    let cooldown = buildingBuildCooldown(kind)
    addRecipe(recipes, id, station, costs, @[(thingItem($kind), 1)], cooldown)
