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
    displayName*: string
    spriteKey*: string
    ascii*: char
    renderColor*: tuple[r, g, b: uint8]
    buildIndex*: int
    buildCost*: seq[ItemAmount]
    buildCooldown*: int

proc initBuildingRegistry(): array[ThingKind, BuildingInfo] =
  var reg: array[ThingKind, BuildingInfo]
  for kind in ThingKind:
    reg[kind] = BuildingInfo(
      displayName: "",
      spriteKey: "",
      ascii: '?',
      renderColor: (r: 180'u8, g: 180'u8, b: 180'u8),
      buildIndex: -1,
      buildCost: @[],
      buildCooldown: 8
    )

  proc add(kind: ThingKind, displayName, spriteKey: string, ascii: char,
           renderColor: tuple[r, g, b: uint8],
           buildIndex = -1, buildCost: seq[ItemAmount] = @[],
           buildCooldown = 8) =
    reg[kind] = BuildingInfo(
      displayName: displayName,
      spriteKey: spriteKey,
      ascii: ascii,
      renderColor: renderColor,
      buildIndex: buildIndex,
      buildCost: buildCost,
      buildCooldown: buildCooldown
    )

  add(Altar, "Altar", "altar", 'a', (r: 220'u8, g: 0'u8, b: 220'u8))
  add(TownCenter, "Town Center", "town_center", 'N', (r: 190'u8, g: 180'u8, b: 140'u8),
      buildIndex = 1, buildCost = @[(ItemWood, 14)], buildCooldown = 16)
  add(House, "House", "house", 'h', (r: 170'u8, g: 140'u8, b: 110'u8),
      buildIndex = 0, buildCost = @[(ItemWood, 1)], buildCooldown = 10)
  add(Armory, "Armory", "armory", 'A', (r: 255'u8, g: 120'u8, b: 40'u8),
      buildIndex = 19, buildCost = @[(ItemWood, 4)], buildCooldown = 12)
  add(ClayOven, "Clay Oven", "clay_oven", 'C', (r: 255'u8, g: 180'u8, b: 120'u8),
      buildIndex = 20, buildCost = @[(ItemWood, 4)], buildCooldown = 12)
  add(WeavingLoom, "Weaving Loom", "weaving_loom", 'W', (r: 0'u8, g: 180'u8, b: 255'u8),
      buildIndex = 21, buildCost = @[(ItemWood, 3)], buildCooldown = 12)
  add(Outpost, "Outpost", "outpost", '^', (r: 120'u8, g: 120'u8, b: 140'u8),
      buildIndex = 13, buildCost = @[(ItemWood, 1)], buildCooldown = 8)
  add(Barrel, "Barrel", "barrel", 'b', (r: 150'u8, g: 110'u8, b: 60'u8),
      buildIndex = 22, buildCost = @[(ItemWood, 2)], buildCooldown = 10)
  add(Mill, "Mill", "mill", 'm', (r: 210'u8, g: 200'u8, b: 170'u8),
      buildIndex = 2, buildCost = @[(ItemWood, 5)], buildCooldown = 12)
  add(Granary, "Granary", "granary", 'n', (r: 220'u8, g: 200'u8, b: 150'u8),
      buildIndex = 5, buildCost = @[(ItemWood, 5)], buildCooldown = 12)
  add(LumberCamp, "Lumber Yard", "lumber_yard", 'L', (r: 140'u8, g: 100'u8, b: 60'u8),
      buildIndex = 3, buildCost = @[(ItemWood, 5)], buildCooldown = 10)
  add(MiningCamp, "Quarry", "quarry", 'G', (r: 120'u8, g: 120'u8, b: 120'u8),
      buildIndex = 4, buildCost = @[(ItemWood, 5)], buildCooldown = 12)
  add(Bank, "Bank", "bank", 'B', (r: 220'u8, g: 200'u8, b: 120'u8))
  add(Barracks, "Barracks", "barracks", 'r', (r: 160'u8, g: 90'u8, b: 60'u8),
      buildIndex = 8, buildCost = @[(ItemWood, 9)], buildCooldown = 12)
  add(ArcheryRange, "Archery Range", "archery_range", 'g', (r: 140'u8, g: 120'u8, b: 180'u8),
      buildIndex = 9, buildCost = @[(ItemWood, 9)], buildCooldown = 12)
  add(Stable, "Stable", "stable", 's', (r: 120'u8, g: 90'u8, b: 60'u8),
      buildIndex = 10, buildCost = @[(ItemWood, 9)], buildCooldown = 12)
  add(SiegeWorkshop, "Siege Workshop", "siege_workshop", 'i', (r: 120'u8, g: 120'u8, b: 160'u8),
      buildIndex = 11, buildCost = @[(ItemWood, 10)], buildCooldown = 14)
  add(Blacksmith, "Blacksmith", "blacksmith", 'k', (r: 90'u8, g: 90'u8, b: 90'u8),
      buildIndex = 16, buildCost = @[(ItemWood, 8)], buildCooldown = 12)
  add(Market, "Market", "market", 'e', (r: 200'u8, g: 170'u8, b: 120'u8),
      buildIndex = 7, buildCost = @[(ItemWood, 9)], buildCooldown = 12)
  add(Dock, "Dock", "dock", 'd', (r: 80'u8, g: 140'u8, b: 200'u8),
      buildIndex = 6, buildCost = @[(ItemWood, 8)], buildCooldown = 12)
  add(Monastery, "Monastery", "monastery", 'y', (r: 220'u8, g: 200'u8, b: 120'u8),
      buildIndex = 17, buildCost = @[(ItemWood, 9)], buildCooldown = 12)
  add(University, "University", "university", 'u', (r: 140'u8, g: 160'u8, b: 200'u8),
      buildIndex = 18, buildCost = @[(ItemWood, 10)], buildCooldown = 14)
  add(Castle, "Castle", "castle", 'c', (r: 120'u8, g: 120'u8, b: 120'u8),
      buildIndex = 12, buildCost = @[(ItemStone, 33)], buildCooldown = 20)

  reg

let BuildingRegistry* = initBuildingRegistry()

proc buildingInfo*(kind: ThingKind): BuildingInfo =
  BuildingRegistry[kind]

proc isBuildingKind*(kind: ThingKind): bool =
  BuildingRegistry[kind].displayName.len > 0

proc buildingSpriteKey*(kind: ThingKind): string =
  BuildingRegistry[kind].spriteKey

proc buildingDisplayName*(kind: ThingKind): string =
  BuildingRegistry[kind].displayName

proc buildingAscii*(kind: ThingKind): char =
  BuildingRegistry[kind].ascii

proc buildingRenderColor*(kind: ThingKind): tuple[r, g, b: uint8] =
  BuildingRegistry[kind].renderColor

proc buildingNeedsLantern*(kind: ThingKind): bool =
  isBuildingKind(kind) and kind != Barrel

proc buildingTeamOwned*(kind: ThingKind): bool =
  isBuildingKind(kind) and kind != Barrel

proc buildingHasFrozenOverlay*(kind: ThingKind): bool =
  isBuildingKind(kind)

proc buildingUseKind*(kind: ThingKind): BuildingUseKind =
  case kind
  of Altar: UseAltar
  of Armory: UseArmory
  of ClayOven: UseClayOven
  of WeavingLoom: UseWeavingLoom
  of Blacksmith: UseBlacksmith
  of Market: UseMarket
  of TownCenter, LumberCamp, Dock: UseDropoff
  of Granary, MiningCamp: UseDropoffAndStorage
  of Barrel: UseStorage
  of Barracks, ArcheryRange, Stable, Monastery, Castle: UseTrain
  of SiegeWorkshop: UseTrainAndCraft
  else: UseNone

proc buildingUsesCooldown*(kind: ThingKind): bool =
  if not isBuildingKind(kind):
    return false
  case buildingUseKind(kind)
  of UseArmory, UseClayOven, UseWeavingLoom, UseBlacksmith, UseMarket,
     UseTrain, UseTrainAndCraft, UseCraft:
    true
  else:
    false

proc buildingStockpileRes*(kind: ThingKind): StockpileResource

proc buildingShowsStockpile*(kind: ThingKind): bool =
  buildingStockpileRes(kind) != ResourceNone

proc buildingStockpileRes*(kind: ThingKind): StockpileResource =
  case kind
  of Granary: ResourceFood
  of LumberCamp: ResourceWood
  of MiningCamp: ResourceStone
  of Bank: ResourceGold
  else: ResourceNone

proc buildingBuildIndex*(kind: ThingKind): int =
  BuildingRegistry[kind].buildIndex

proc buildingBuildable*(kind: ThingKind): bool =
  BuildingRegistry[kind].buildIndex >= 0 and BuildingRegistry[kind].buildCost.len > 0

proc buildingBuildCost*(kind: ThingKind): seq[ItemAmount] =
  BuildingRegistry[kind].buildCost

proc buildingBuildCooldown*(kind: ThingKind): int =
  BuildingRegistry[kind].buildCooldown

proc buildingPopCap*(kind: ThingKind): int =
  case kind
  of TownCenter: TownCenterPopCap
  of House: HousePopCap
  else: 0

proc buildingBarrelCapacity*(kind: ThingKind): int =
  case kind
  of Barrel, Granary, LumberCamp, MiningCamp, Blacksmith: BarrelCapacity
  else: 0

proc buildingFertileRadius*(kind: ThingKind): int =
  case kind
  of Mill: 2
  else: 0

proc buildingDropoffResources*(kind: ThingKind): set[StockpileResource] =
  case kind
  of TownCenter: {ResourceFood, ResourceWood, ResourceGold, ResourceStone}
  of Granary: {ResourceFood}
  of LumberCamp: {ResourceWood}
  of MiningCamp: {ResourceGold, ResourceStone}
  of Dock: {ResourceFood}
  else: {}

proc buildingStorageItems*(kind: ThingKind): seq[ItemKey] =
  case kind
  of Granary: @[ItemWheat]
  of MiningCamp: @[ItemRock]
  of Blacksmith: @[ItemArmor, ItemSpear]
  else: @[]

proc buildingCraftStation*(kind: ThingKind): CraftStation

proc buildingHasCraftStation*(kind: ThingKind): bool =
  buildingCraftStation(kind) != StationNone

proc buildingCraftStation*(kind: ThingKind): CraftStation =
  case kind
  of ClayOven: StationOven
  of WeavingLoom: StationLoom
  of Blacksmith: StationBlacksmith
  of SiegeWorkshop: StationSiegeWorkshop
  else: StationNone

proc buildingHasTrain*(kind: ThingKind): bool =
  case kind
  of Barracks, ArcheryRange, Stable, SiegeWorkshop, Monastery, Castle:
    true
  else:
    false

proc buildingTrainUnit*(kind: ThingKind): AgentUnitClass =
  case kind
  of Barracks: UnitManAtArms
  of ArcheryRange: UnitArcher
  of Stable: UnitScout
  of SiegeWorkshop: UnitSiege
  of Monastery: UnitMonk
  of Castle: UnitKnight
  else: UnitVillager

proc buildingTrainCosts*(kind: ThingKind): seq[tuple[res: StockpileResource, count: int]] =
  case kind
  of Barracks: @[(res: ResourceFood, count: 3), (res: ResourceGold, count: 1)]
  of ArcheryRange: @[(res: ResourceWood, count: 2), (res: ResourceGold, count: 2)]
  of Stable: @[(res: ResourceFood, count: 3)]
  of SiegeWorkshop: @[(res: ResourceWood, count: 3), (res: ResourceStone, count: 2)]
  of Monastery: @[(res: ResourceGold, count: 2)]
  of Castle: @[(res: ResourceFood, count: 4), (res: ResourceGold, count: 2)]
  else: @[]

proc buildingTrainCooldown*(kind: ThingKind): int =
  case kind
  of Barracks, ArcheryRange, Stable: 8
  of SiegeWorkshop: 10
  of Monastery: 10
  of Castle: 12
  else: 0

proc buildingTickKind*(kind: ThingKind): BuildingTickKind =
  case kind
  of Mill: TickMillFertile
  else: TickNone

proc buildingTickCooldown*(kind: ThingKind): int =
  case kind
  of Mill: 10
  else: 0

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
    let station = StationTable
    let cooldown = buildingBuildCooldown(kind)
    addRecipe(recipes, id, station, costs, @[(thingItem($kind), 1)], cooldown)
