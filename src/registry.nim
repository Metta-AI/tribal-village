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

  BuildingInfo* = object
    displayName*: string
    spriteKey*: string
    ascii*: char
    renderColor*: tuple[r, g, b: uint8]
    buildIndex*: int
    buildCost*: seq[ItemAmount]
    buildCooldown*: int

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
      buildCooldown: 0
    )

  for entry in [
    (Altar, "Altar", "altar", 'a', (r: 220'u8, g: 0'u8, b: 220'u8), -1, @[], 0),
    (TownCenter, "Town Center", "town_center", 'N', (r: 190'u8, g: 180'u8, b: 140'u8),
      1, @[(ItemWood, 14)], 16),
    (House, "House", "house", 'h', (r: 170'u8, g: 140'u8, b: 110'u8),
      0, @[(ItemWood, 1)], 10),
    (Door, "Door", "door", 'D', (r: 120'u8, g: 100'u8, b: 80'u8),
      BuildIndexDoor, @[(ItemWood, 1)], 6),
    (ClayOven, "Clay Oven", "clay_oven", 'C', (r: 255'u8, g: 180'u8, b: 120'u8),
      20, @[(ItemWood, 4)], 12),
    (WeavingLoom, "Weaving Loom", "weaving_loom", 'W', (r: 0'u8, g: 180'u8, b: 255'u8),
      21, @[(ItemWood, 3)], 12),
    (Outpost, "Outpost", "outpost", '^', (r: 120'u8, g: 120'u8, b: 140'u8),
      13, @[(ItemWood, 1)], 8),
    (GuardTower, "Guard Tower", "guard_tower", 'T', (r: 110'u8, g: 110'u8, b: 130'u8),
      BuildIndexGuardTower, @[(ItemWood, 5)], 12),
    (Barrel, "Barrel", "barrel", 'b', (r: 150'u8, g: 110'u8, b: 60'u8),
      22, @[(ItemWood, 2)], 10),
    (Mill, "Mill", "mill", 'm', (r: 210'u8, g: 200'u8, b: 170'u8),
      2, @[(ItemWood, 5)], 12),
    (Granary, "Granary", "granary", 'n', (r: 220'u8, g: 200'u8, b: 150'u8),
      5, @[(ItemWood, 5)], 12),
    (LumberCamp, "Lumber Camp", "lumber_camp", 'L', (r: 140'u8, g: 100'u8, b: 60'u8),
      3, @[(ItemWood, 5)], 10),
    (Quarry, "Quarry", "quarry", 'Q', (r: 120'u8, g: 120'u8, b: 120'u8),
      4, @[(ItemWood, 5)], 12),
    (MiningCamp, "Mining Camp", "mining_camp", 'M', (r: 200'u8, g: 190'u8, b: 120'u8),
      15, @[(ItemWood, 5)], 12),
    (Barracks, "Barracks", "barracks", 'r', (r: 160'u8, g: 90'u8, b: 60'u8),
      8, @[(ItemWood, 9)], 12),
    (ArcheryRange, "Archery Range", "archery_range", 'g', (r: 140'u8, g: 120'u8, b: 180'u8),
      9, @[(ItemWood, 9)], 12),
    (Stable, "Stable", "stable", 's', (r: 120'u8, g: 90'u8, b: 60'u8),
      10, @[(ItemWood, 9)], 12),
    (SiegeWorkshop, "Siege Workshop", "siege_workshop", 'i', (r: 120'u8, g: 120'u8, b: 160'u8),
      11, @[(ItemWood, 10)], 14),
    (MangonelWorkshop, "Mangonel Workshop", "mangonel_workshop", 'j', (r: 120'u8, g: 130'u8, b: 160'u8),
      BuildIndexMangonelWorkshop, @[(ItemWood, 10), (ItemStone, 4)], 14),
    (Blacksmith, "Blacksmith", "blacksmith", 'k', (r: 90'u8, g: 90'u8, b: 90'u8),
      16, @[(ItemWood, 8)], 12),
    (Market, "Market", "market", 'e', (r: 200'u8, g: 170'u8, b: 120'u8),
      7, @[(ItemWood, 9)], 12),
    (Dock, "Dock", "dock", 'd', (r: 80'u8, g: 140'u8, b: 200'u8),
      6, @[(ItemWood, 8)], 12),
    (Monastery, "Monastery", "monastery", 'y', (r: 220'u8, g: 200'u8, b: 120'u8),
      17, @[(ItemWood, 9)], 12),
    (University, "University", "university", 'u', (r: 140'u8, g: 160'u8, b: 200'u8),
      18, @[(ItemWood, 10)], 14),
    (Castle, "Castle", "castle", 'c', (r: 120'u8, g: 120'u8, b: 120'u8),
      12, @[(ItemStone, 33)], 20),
    (GoblinHive, "Goblin Hive", "goblin_hive", 'H', (r: 120'u8, g: 170'u8, b: 90'u8),
      -1, @[], 0),
    (GoblinHut, "Goblin Hut", "goblin_hut", 'g', (r: 110'u8, g: 150'u8, b: 90'u8),
      -1, @[], 0),
    (GoblinTotem, "Goblin Totem", "goblin_totem", 'T', (r: 90'u8, g: 140'u8, b: 100'u8),
      -1, @[], 0)
  ]:
    let (kind, displayName, spriteKey, ascii, renderColor, buildIndex, buildCost, buildCooldown) = entry
    reg[kind] = BuildingInfo(
      displayName: displayName,
      spriteKey: spriteKey,
      ascii: ascii,
      renderColor: renderColor,
      buildIndex: buildIndex,
      buildCost: buildCost,
      buildCooldown: buildCooldown
    )

  reg

proc toSnakeCase(name: string): string =
  result = ""
  for ch in name:
    if ch.isUpperAscii:
      if result.len > 0:
        result.add('_')
      result.add(ch.toLowerAscii)
    else:
      result.add(ch)

{.push inline.}
proc isBuildingKind*(kind: ThingKind): bool =
  BuildingRegistry[kind].displayName.len > 0

proc thingBlocksMovement*(kind: ThingKind): bool =
  kind notin BackgroundThingKinds
{.pop.}

proc buildingSpriteKey*(kind: ThingKind): string =
  let key = BuildingRegistry[kind].spriteKey
  if key.len == 0: toSnakeCase($kind) else: key

type
  CatalogEntry* = object
    displayName*: string
    spriteKey*: string
    ascii*: char

let TerrainCatalog* = block:
  var reg: array[TerrainType, CatalogEntry]
  for terrain in TerrainType:
    reg[terrain] = CatalogEntry(displayName: "", spriteKey: "", ascii: '?')

  for (terrain, displayName, spriteKey, ascii) in [
    (Empty, "Empty", "", ' '),
    (Water, "Water", "", '~'),
    (Bridge, "Bridge", "", '='),
    (Fertile, "Fertile", "", 'f'),
    (Road, "Road", "", 'r'),
    (Grass, "Grass", "", 'g'),
    (Dune, "Dune", "", 'd'),
    (Sand, "Sand", "", 's'),
    (Snow, "Snow", "", 'n')
  ]:
    reg[terrain] = CatalogEntry(displayName: displayName, spriteKey: spriteKey, ascii: ascii)
  reg

let ThingCatalog* = block:
  var reg: array[ThingKind, CatalogEntry]
  for kind in ThingKind:
    reg[kind] = CatalogEntry(displayName: "", spriteKey: "", ascii: '?')

  for (kind, displayName, spriteKey, ascii) in [
    (Agent, "Agent", "gatherer", '@'),
    (Wall, "Wall", "oriented/wall", '#'),
    (Tree, "Tree", "tree", 't'),
    (Wheat, "Wheat", "wheat", 'w'),
    (Fish, "Fish", "fish", 'f'),
    (Relic, "Relic", "goblet", 'r'),
    (Stone, "Stone", "stone", 'S'),
    (Gold, "Gold", "gold", 'G'),
    (Bush, "Bush", "bush", 'b'),
    (Cactus, "Cactus", "cactus", 'c'),
    (Stalagmite, "Stalagmite", "stalagmite", 'm'),
    (Magma, "Magma", "magma", 'v'),
    (Spawner, "Spawner", "spawner", 'Z'),
    (Tumor, "Tumor", "tumor", 'X'),
    (Cow, "Cow", "oriented/cow", 'w'),
    (Bear, "Bear", "oriented/bear", 'B'),
    (Wolf, "Wolf", "oriented/wolf", 'W'),
    (Corpse, "Corpse", "corpse", 'C'),
    (Skeleton, "Skeleton", "skeleton", 'K'),
    (Stump, "Stump", "stump", 'p'),
    (Stubble, "Stubble", "stubble", 'u'),
    (Lantern, "Lantern", "lantern", 'l'),
    (Temple, "Temple", "temple", 'T'),
    (CliffEdgeN, "Cliff Edge North", "cliff_edge_ew_s", '^'),
    (CliffEdgeE, "Cliff Edge East", "cliff_edge_ns_w", '^'),
    (CliffEdgeS, "Cliff Edge South", "cliff_edge_ew", '^'),
    (CliffEdgeW, "Cliff Edge West", "cliff_edge_ns", '^'),
    (CliffCornerInNE, "Cliff Corner In NE", "oriented/cliff_corner_in_ne", '^'),
    (CliffCornerInSE, "Cliff Corner In SE", "oriented/cliff_corner_in_se", '^'),
    (CliffCornerInSW, "Cliff Corner In SW", "oriented/cliff_corner_in_sw", '^'),
    (CliffCornerInNW, "Cliff Corner In NW", "oriented/cliff_corner_in_nw", '^'),
    (CliffCornerOutNE, "Cliff Corner Out NE", "oriented/cliff_corner_out_ne", '^'),
    (CliffCornerOutSE, "Cliff Corner Out SE", "oriented/cliff_corner_out_se", '^'),
    (CliffCornerOutSW, "Cliff Corner Out SW", "oriented/cliff_corner_out_sw", '^'),
    (CliffCornerOutNW, "Cliff Corner Out NW", "oriented/cliff_corner_out_nw", '^')
  ]:
    reg[kind] = CatalogEntry(displayName: displayName, spriteKey: spriteKey, ascii: ascii)
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
    (ItemArmor, "Armor", "shield", 'a'),
    (ItemBread, "Bread", "bread", 'b'),
    (ItemPlant, "Plant", "plant", 'p'),
    (ItemFish, "Fish", "fish", 'f'),
    (ItemMeat, "Meat", "meat", 'm'),
    (ItemRelic, "Relic", "goblet", 'r'),
    (ItemHearts, "Hearts", "heart", 'h')
  ]:
    let (key, displayName, spriteKey, ascii) = entry
    reg[key] = CatalogEntry(displayName: displayName, spriteKey: spriteKey, ascii: ascii)
  reg

proc terrainSpriteKey*(terrain: TerrainType): string =
  if terrain == Empty or isRampTerrain(terrain):
    return ""
  if terrain in RampTerrain:
    return ""
  let key = TerrainCatalog[terrain].spriteKey
  if key.len == 0: toSnakeCase($terrain) else: key


proc thingSpriteKey*(kind: ThingKind): string =
  if isBuildingKind(kind):
    return buildingSpriteKey(kind)
  let key = ThingCatalog[kind].spriteKey
  if key.len > 0:
    return key
  toSnakeCase($kind)

proc itemSpriteKey*(key: ItemKey): string =
  if isThingKey(key):
    for kind in ThingKind:
      if $kind == key.name:
        return thingSpriteKey(kind)
    return key.name
  if ItemCatalog.hasKey(key):
    return ItemCatalog[key].spriteKey
  case key.kind
  of ItemKeyOther:
    key.name
  of ItemKeyItem:
    ItemKindNames[key.item]
  else:
    ""

proc buildingUseKind*(kind: ThingKind): BuildingUseKind =
  case kind
  of Altar: UseAltar
  of ClayOven: UseClayOven
  of WeavingLoom: UseWeavingLoom
  of Blacksmith: UseBlacksmith
  of Market: UseMarket
  of TownCenter, Mill, LumberCamp, Quarry, MiningCamp, Dock: UseDropoff
  of Granary: UseDropoffAndStorage
  of Barrel: UseStorage
  of University: UseCraft
  of Barracks, ArcheryRange, Stable, Monastery, Castle, MangonelWorkshop: UseTrain
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
  let info = BuildingRegistry[kind]
  info.buildIndex >= 0 and info.buildCost.len > 0

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
  of Barrel: @[
    ItemBread,
    ItemMeat,
    ItemFish,
    ItemPlant,
    ItemLantern,
    ItemSpear,
    ItemArmor,
    ItemBar,
    ItemRelic
  ]
  else: @[]

proc buildingCraftStation*(kind: ThingKind): CraftStation =
  case kind
  of ClayOven: StationOven
  of WeavingLoom: StationLoom
  of Blacksmith: StationBlacksmith
  of University: StationTable
  of SiegeWorkshop: StationSiegeWorkshop
  else: StationNone

proc buildingHasCraftStation*(kind: ThingKind): bool =
  buildingCraftStation(kind) != StationNone

proc buildingHasTrain*(kind: ThingKind): bool =
  kind in {Barracks, ArcheryRange, Stable, SiegeWorkshop, MangonelWorkshop, Monastery, Castle}

proc buildingTrainUnit*(kind: ThingKind): AgentUnitClass =
  case kind
  of Barracks: UnitManAtArms
  of ArcheryRange: UnitArcher
  of Stable: UnitScout
  of SiegeWorkshop: UnitBatteringRam
  of MangonelWorkshop: UnitMangonel
  of Monastery: UnitMonk
  of Castle: UnitKnight
  else: UnitVillager

proc buildingTrainCosts*(kind: ThingKind): seq[tuple[res: StockpileResource, count: int]] =
  case kind
  of Barracks: @[(res: ResourceFood, count: 3), (res: ResourceGold, count: 1)]
  of ArcheryRange: @[(res: ResourceWood, count: 2), (res: ResourceGold, count: 2)]
  of Stable: @[(res: ResourceFood, count: 3)]
  of SiegeWorkshop: @[(res: ResourceWood, count: 3), (res: ResourceStone, count: 2)]
  of MangonelWorkshop: @[(res: ResourceWood, count: 4), (res: ResourceStone, count: 3)]
  of Monastery: @[(res: ResourceGold, count: 2)]
  of Castle: @[(res: ResourceFood, count: 4), (res: ResourceGold, count: 2)]
  else: @[]

proc buildIndexFor*(kind: ThingKind): int =
  BuildingRegistry[kind].buildIndex

proc applyBuildCostMultiplier*(costs: seq[tuple[res: StockpileResource, count: int]],
                                multiplier: float32): seq[tuple[res: StockpileResource, count: int]] =
  ## Apply a build cost multiplier to a sequence of costs
  let effectiveMultiplier = if multiplier == 0.0'f32: 1.0'f32 else: multiplier  # Default to 1.0 if uninitialized
  result = @[]
  for cost in costs:
    let adjustedCount = max(1, int(float32(cost.count) * effectiveMultiplier))
    result.add((res: cost.res, count: adjustedCount))

proc appendBuildingRecipes*(recipes: var seq[CraftRecipe]) =
  for kind in ThingKind:
    if not isBuildingKind(kind):
      continue
    if not buildingBuildable(kind):
      continue
    let info = BuildingRegistry[kind]
    let costs = info.buildCost
    addRecipe(
      recipes,
      toSnakeCase($kind),
      StationTable,
      costs,
      @[(thingItem($kind), 1)],
      info.buildCooldown
    )
