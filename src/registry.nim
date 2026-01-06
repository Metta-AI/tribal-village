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
  add(Armory, "Armory", "armory", 'A', (r: 255'u8, g: 120'u8, b: 40'u8))
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
  add(LumberYard, "Lumber Yard", "lumber_yard", 'L', (r: 140'u8, g: 100'u8, b: 60'u8),
      buildIndex = 19, buildCost = @[(ItemWood, 5)], buildCooldown = 10)
  add(LumberCamp, "Lumber Camp", "lumber_camp", 'l', (r: 130'u8, g: 90'u8, b: 60'u8),
      buildIndex = 3, buildCost = @[(ItemWood, 5)], buildCooldown = 10)
  add(Quarry, "Quarry", "quarry", 'Q', (r: 120'u8, g: 120'u8, b: 120'u8),
      buildIndex = 23, buildCost = @[(ItemWood, 5)], buildCooldown = 12)
  add(MiningCamp, "Mining Camp", "mining_camp", 'G', (r: 120'u8, g: 120'u8, b: 120'u8),
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

proc toSnakeCase(name: string): string

proc buildingInfo*(kind: ThingKind): BuildingInfo =
  BuildingRegistry[kind]

proc isBuildingKind*(kind: ThingKind): bool =
  BuildingRegistry[kind].displayName.len > 0

proc buildingSpriteKey*(kind: ThingKind): string =
  let key = BuildingRegistry[kind].spriteKey
  if key.len > 0:
    return key
  toSnakeCase($kind)

proc buildingDisplayName*(kind: ThingKind): string =
  BuildingRegistry[kind].displayName

proc buildingAscii*(kind: ThingKind): char =
  BuildingRegistry[kind].ascii

type
  CatalogEntry* = object
    displayName*: string
    spriteKey*: string
    ascii*: char

proc initTerrainCatalog(): array[TerrainType, CatalogEntry] =
  var reg: array[TerrainType, CatalogEntry]
  for terrain in TerrainType:
    reg[terrain] = CatalogEntry(displayName: "", spriteKey: "", ascii: '?')

  proc add(terrain: TerrainType, displayName, spriteKey: string, ascii: char) =
    reg[terrain] = CatalogEntry(displayName: displayName, spriteKey: spriteKey, ascii: ascii)

  add(Empty, "Empty", "", ' ')
  add(Water, "Water", "", '~')
  add(Bridge, "Bridge", "", '=')
  add(Wheat, "Wheat", "", '.')
  add(Pine, "Pine", "", 'T')
  add(Fertile, "Fertile", "", 'f')
  add(Road, "Road", "", 'r')
  add(Stone, "Stone", "", 'S')
  add(Gold, "Gold", "", 'G')
  add(Bush, "Bush", "", 'b')
  add(Grass, "Grass", "", 'g')
  add(Cactus, "Cactus", "", 'c')
  add(Dune, "Dune", "", 'd')
  add(Stalagmite, "Stalagmite", "", 'm')
  add(Palm, "Palm", "", 'P')
  add(Sand, "Sand", "", 's')
  add(Snow, "Snow", "", 'n')
  reg

proc initThingCatalog(): array[ThingKind, CatalogEntry] =
  var reg: array[ThingKind, CatalogEntry]
  for kind in ThingKind:
    reg[kind] = CatalogEntry(displayName: "", spriteKey: "", ascii: '?')

  proc add(kind: ThingKind, displayName, spriteKey: string, ascii: char) =
    reg[kind] = CatalogEntry(displayName: displayName, spriteKey: spriteKey, ascii: ascii)

  add(Agent, "Agent", "agent", '@')
  add(Wall, "Wall", "wall", '#')
  add(Pine, "Pine", "pine", 't')
  add(Palm, "Palm", "palm", 'P')
  add(Magma, "Magma", "magma", 'v')
  add(Spawner, "Spawner", "spawner", 'Z')
  add(Tumor, "Tumor", "tumor", 'X')
  add(Cow, "Cow", "cow", 'w')
  add(Corpse, "Corpse", "corpse", 'C')
  add(Skeleton, "Skeleton", "skeleton", 'K')
  add(Stump, "Stump", "stump", 'p')
  add(Lantern, "Lantern", "lantern", 'l')
  reg

proc initItemCatalog(): Table[ItemKey, CatalogEntry] =
  result = initTable[ItemKey, CatalogEntry]()
  result[ItemGold] = CatalogEntry(displayName: "Gold", spriteKey: "gold", ascii: '$')
  result[ItemStone] = CatalogEntry(displayName: "Stone", spriteKey: "stone", ascii: 'S')
  result[ItemBar] = CatalogEntry(displayName: "Bar", spriteKey: "bar", ascii: 'B')
  result[ItemWater] = CatalogEntry(displayName: "Water", spriteKey: "droplet", ascii: '~')
  result[ItemWheat] = CatalogEntry(displayName: "Wheat", spriteKey: "bushel", ascii: 'w')
  result[ItemWood] = CatalogEntry(displayName: "Wood", spriteKey: "wood", ascii: 't')
  result[ItemSpear] = CatalogEntry(displayName: "Spear", spriteKey: "spear", ascii: 's')
  result[ItemLantern] = CatalogEntry(displayName: "Lantern", spriteKey: "lantern", ascii: 'l')
  result[ItemArmor] = CatalogEntry(displayName: "Armor", spriteKey: "armor", ascii: 'a')
  result[ItemBread] = CatalogEntry(displayName: "Bread", spriteKey: "bread", ascii: 'b')
  result[ItemPlant] = CatalogEntry(displayName: "Plant", spriteKey: "plant", ascii: 'p')
  result[ItemFish] = CatalogEntry(displayName: "Fish", spriteKey: "fish", ascii: 'f')
  result[ItemMeat] = CatalogEntry(displayName: "Meat", spriteKey: "meat", ascii: 'm')
  result[ItemHearts] = CatalogEntry(displayName: "Hearts", spriteKey: "heart", ascii: 'h')

let TerrainCatalog* = initTerrainCatalog()
let ThingCatalog* = initThingCatalog()
let ItemCatalog* = initItemCatalog()

proc terrainInfo*(terrain: TerrainType): CatalogEntry =
  TerrainCatalog[terrain]

proc terrainSpriteKey*(terrain: TerrainType): string =
  if terrain == Empty:
    return ""
  let key = TerrainCatalog[terrain].spriteKey
  if key.len > 0:
    return key
  toSnakeCase($terrain)

proc terrainDisplayName*(terrain: TerrainType): string =
  let name = TerrainCatalog[terrain].displayName
  if name.len > 0: name else: $terrain

proc terrainAscii*(terrain: TerrainType): char =
  TerrainCatalog[terrain].ascii

proc thingInfo*(kind: ThingKind): CatalogEntry =
  ThingCatalog[kind]

proc thingSpriteKey*(kind: ThingKind): string =
  if isBuildingKind(kind):
    return buildingSpriteKey(kind)
  let key = ThingCatalog[kind].spriteKey
  if key.len > 0:
    return key
  toSnakeCase($kind)

proc thingDisplayName*(kind: ThingKind): string =
  if isBuildingKind(kind):
    return buildingDisplayName(kind)
  let name = ThingCatalog[kind].displayName
  if name.len > 0: name else: $kind

proc thingAscii*(kind: ThingKind): char =
  if isBuildingKind(kind):
    return buildingAscii(kind)
  ThingCatalog[kind].ascii

proc itemInfo*(key: ItemKey): CatalogEntry =
  ItemCatalog.getOrDefault(key, CatalogEntry(displayName: key, spriteKey: key, ascii: '?'))

proc itemSpriteKey*(key: ItemKey): string =
  if key.startsWith(ItemThingPrefix):
    let kindName = key[ItemThingPrefix.len .. ^1]
    for kind in ThingKind:
      if $kind == kindName:
        return thingSpriteKey(kind)
  if ItemCatalog.hasKey(key):
    return ItemCatalog[key].spriteKey
  key

proc itemDisplayName*(key: ItemKey): string =
  if key.startsWith(ItemThingPrefix):
    let kindName = key[ItemThingPrefix.len .. ^1]
    for kind in ThingKind:
      if $kind == kindName:
        return thingDisplayName(kind)
  if ItemCatalog.hasKey(key):
    return ItemCatalog[key].displayName
  key

proc stockpileIconKey*(res: StockpileResource): string =
  case res
  of ResourceFood: itemSpriteKey(ItemWheat)
  of ResourceWood: itemSpriteKey(ItemWood)
  of ResourceStone: itemSpriteKey(ItemStone)
  of ResourceGold: itemSpriteKey(ItemGold)
  of ResourceWater: itemSpriteKey(ItemWater)
  of ResourceNone: ""

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
  of Armory: UseNone
  of Mill: UseDropoff
  of ClayOven: UseClayOven
  of WeavingLoom: UseWeavingLoom
  of Blacksmith: UseBlacksmith
  of Market: UseMarket
  of Bank, LumberYard, Quarry: UseDropoff
  of TownCenter, LumberCamp, MiningCamp, Dock: UseDropoff
  of Granary: UseDropoffAndStorage
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

proc buildingStockpileRes*(kind: ThingKind): StockpileResource =
  case kind
  of Granary: ResourceFood
  of LumberYard: ResourceWood
  of Quarry: ResourceStone
  of Bank: ResourceGold
  else: ResourceNone

proc buildingShowsStockpile*(kind: ThingKind): bool =
  buildingStockpileRes(kind) != ResourceNone

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
  of Barrel, Granary, Blacksmith: BarrelCapacity
  else: 0

proc buildingFertileRadius*(kind: ThingKind): int =
  case kind
  of Mill: 2
  else: 0

proc buildingDropoffResources*(kind: ThingKind): set[StockpileResource] =
  case kind
  of TownCenter: {ResourceFood, ResourceWood, ResourceGold, ResourceStone}
  of Granary, Mill: {ResourceFood}
  of LumberCamp, LumberYard: {ResourceWood}
  of MiningCamp: {ResourceGold, ResourceStone}
  of Quarry: {ResourceStone}
  of Bank: {ResourceGold}
  of Dock: {ResourceFood}
  else: {}

proc buildingStorageItems*(kind: ThingKind): seq[ItemKey] =
  case kind
  of Granary: @[ItemWheat]
  of Blacksmith: @[ItemArmor, ItemSpear]
  else: @[]

proc buildingCraftStation*(kind: ThingKind): CraftStation

proc buildingCraftStation*(kind: ThingKind): CraftStation =
  case kind
  of ClayOven: StationOven
  of WeavingLoom: StationLoom
  of Blacksmith: StationBlacksmith
  of SiegeWorkshop: StationSiegeWorkshop
  else: StationNone

proc buildingHasCraftStation*(kind: ThingKind): bool =
  buildingCraftStation(kind) != StationNone

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
