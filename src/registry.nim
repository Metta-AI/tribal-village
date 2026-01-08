## registry.nim - Building, terrain, and thing registries for tribal-village
##
## This module provides lookup tables and metadata for all game entities.

import std/[tables, strutils]
import types, items
export types, items

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

  ThingPlacementKind* = enum
    PlacementBlocking
    PlacementOverlay

let BuildingRegistry* = block:
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
  add(Door, "Door", "door", 'D', (r: 120'u8, g: 100'u8, b: 80'u8),
      buildIndex = BuildIndexDoor, buildCost = @[(ItemWood, 1)], buildCooldown = 6)
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
  add(LumberCamp, "Lumber Camp", "lumber_camp", 'L', (r: 140'u8, g: 100'u8, b: 60'u8),
      buildIndex = 3, buildCost = @[(ItemWood, 5)], buildCooldown = 10)
  add(Quarry, "Quarry", "quarry", 'Q', (r: 120'u8, g: 120'u8, b: 120'u8),
      buildIndex = 4, buildCost = @[(ItemWood, 5)], buildCooldown = 12)
  add(MiningCamp, "Mining Camp", "mining_camp", 'M', (r: 200'u8, g: 190'u8, b: 120'u8),
      buildIndex = 15, buildCost = @[(ItemWood, 5)], buildCooldown = 12)
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

proc toSnakeCase(name: string): string

{.push inline.}
proc isBuildingKind*(kind: ThingKind): bool =
  BuildingRegistry[kind].displayName.len > 0

proc thingBlocksMovement*(kind: ThingKind): bool =
  kind notin {Door, Wheat, Tree}
{.pop.}

proc buildingSpriteKey*(kind: ThingKind): string =
  let key = BuildingRegistry[kind].spriteKey
  if key.len > 0:
    return key
  toSnakeCase($kind)

proc buildingDisplayName*(kind: ThingKind): string =
  BuildingRegistry[kind].displayName


type
  CatalogEntry* = object
    displayName*: string
    spriteKey*: string
    ascii*: char

let TerrainCatalog* = block:
  var reg: array[TerrainType, CatalogEntry]
  for terrain in TerrainType:
    reg[terrain] = CatalogEntry(displayName: "", spriteKey: "", ascii: '?')

  proc add(terrain: TerrainType, displayName, spriteKey: string, ascii: char) =
    reg[terrain] = CatalogEntry(displayName: displayName, spriteKey: spriteKey, ascii: ascii)

  add(Empty, "Empty", "", ' ')
  add(Water, "Water", "", '~')
  add(Bridge, "Bridge", "", '=')
  add(Fertile, "Fertile", "", 'f')
  add(Road, "Road", "", 'r')
  add(Grass, "Grass", "", 'g')
  add(Dune, "Dune", "", 'd')
  add(Sand, "Sand", "", 's')
  add(Snow, "Snow", "", 'n')
  reg

let ThingCatalog* = block:
  var reg: array[ThingKind, CatalogEntry]
  for kind in ThingKind:
    reg[kind] = CatalogEntry(displayName: "", spriteKey: "", ascii: '?')

  proc add(kind: ThingKind, displayName, spriteKey: string, ascii: char) =
    reg[kind] = CatalogEntry(displayName: displayName, spriteKey: spriteKey, ascii: ascii)

  add(Agent, "Agent", "gatherer", '@')
  add(Wall, "Wall", "wall", '#')
  add(Tree, "Tree", "tree", 't')
  add(Wheat, "Wheat", "wheat", 'w')
  add(Stone, "Stone", "stone", 'S')
  add(Gold, "Gold", "gold", 'G')
  add(Bush, "Bush", "bush", 'b')
  add(Cactus, "Cactus", "cactus", 'c')
  add(Stalagmite, "Stalagmite", "stalagmite", 'm')
  add(Magma, "Magma", "magma", 'v')
  add(Spawner, "Spawner", "spawner", 'Z')
  add(Tumor, "Tumor", "tumor", 'X')
  add(Cow, "Cow", "cow", 'w')
  add(Corpse, "Corpse", "corpse", 'C')
  add(Skeleton, "Skeleton", "skeleton", 'K')
  add(Stump, "Stump", "stump", 'p')
  add(Lantern, "Lantern", "lantern", 'l')
  reg

let ItemCatalog* = block:
  var reg = initTable[ItemKey, CatalogEntry]()
  for entry in [
    (ItemGold, "Gold", "gold", '$'),
    (ItemStone, "Stone", "stone", 'S'),
    (ItemBar, "Bar", "bar", 'B'),
    (ItemWater, "Water", "droplet", '~'),
    (ItemWheat, "Wheat", "bushel", 'w'),
    (ItemWood, "Wood", "wood", 't'),
    (ItemSpear, "Spear", "spear", 's'),
    (ItemLantern, "Lantern", "lantern", 'l'),
    (ItemArmor, "Armor", "armor", 'a'),
    (ItemBread, "Bread", "bread", 'b'),
    (ItemPlant, "Plant", "plant", 'p'),
    (ItemFish, "Fish", "fish", 'f'),
    (ItemMeat, "Meat", "meat", 'm'),
    (ItemHearts, "Hearts", "heart", 'h')
  ]:
    let (key, displayName, spriteKey, ascii) = entry
    reg[key] = CatalogEntry(displayName: displayName, spriteKey: spriteKey, ascii: ascii)
  reg

proc terrainSpriteKey*(terrain: TerrainType): string =
  if terrain == Empty:
    return ""
  let key = TerrainCatalog[terrain].spriteKey
  if key.len > 0:
    return key
  toSnakeCase($terrain)


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


proc itemSpriteKey*(key: ItemKey): string =
  if key.startsWith(ItemThingPrefix):
    let kindName = key[ItemThingPrefix.len .. ^1]
    for kind in ThingKind:
      if $kind == kindName:
        return thingSpriteKey(kind)
  if ItemCatalog.hasKey(key):
    return ItemCatalog[key].spriteKey
  key

proc buildingUseKind*(kind: ThingKind): BuildingUseKind =
  case kind
  of Altar: UseAltar
  of Armory: UseNone
  of ClayOven: UseClayOven
  of WeavingLoom: UseWeavingLoom
  of Blacksmith: UseBlacksmith
  of Market: UseMarket
  of TownCenter, Mill, LumberCamp, Quarry, MiningCamp, Dock: UseDropoff
  of Granary: UseDropoffAndStorage
  of Barrel: UseStorage
  of Barracks, ArcheryRange, Stable, Monastery, Castle: UseTrain
  of SiegeWorkshop: UseTrainAndCraft
  else: UseNone

proc buildingStockpileRes*(kind: ThingKind): StockpileResource =
  case kind
  of Granary: ResourceFood
  of LumberCamp: ResourceWood
  of Quarry: ResourceStone
  of MiningCamp: ResourceGold
  else: ResourceNone

proc buildingBuildable*(kind: ThingKind): bool =
  BuildingRegistry[kind].buildIndex >= 0 and BuildingRegistry[kind].buildCost.len > 0

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
  of LumberCamp: {ResourceWood}
  of Quarry: {ResourceStone}
  of MiningCamp: {ResourceGold}
  of Dock: {ResourceFood}
  else: {}

proc buildingStorageItems*(kind: ThingKind): seq[ItemKey] =
  case kind
  of Granary: @[ItemWheat]
  of Blacksmith: @[ItemArmor, ItemSpear]
  else: @[]

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
    let costs = BuildingRegistry[kind].buildCost
    if costs.len == 0:
      continue
    let id = toSnakeCase($kind)
    let station = StationTable
    let cooldown = BuildingRegistry[kind].buildCooldown
    addRecipe(recipes, id, station, costs, @[(thingItem($kind), 1)], cooldown)
