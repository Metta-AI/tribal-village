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
    UseDropoffAndTrain  # Dock: resource dropoff + unit training
    UseUniversity  # Research University techs
    UseCastle      # Train unique units + research unique techs

  BuildingInfo* = object
    displayName*: string
    spriteKey*: string
    ascii*: char
    renderColor*: tuple[r, g, b: uint8]
    buildIndex*: int
    buildCost*: seq[ItemAmount]
    buildCooldown*: int
    # Consolidated building properties (formerly in separate case statements)
    useKind*: BuildingUseKind
    stockpileRes*: StockpileResource
    popCap*: int
    barrelCapacity*: int
    fertileRadius*: int
    dropoffResources*: set[StockpileResource]
    storageItems*: seq[ItemKey]
    craftStation*: CraftStation
    trainCosts*: seq[tuple[res: StockpileResource, count: int]]

let BuildingRegistry* = block:
  var reg: array[ThingKind, BuildingInfo]
  # Initialize all with defaults
  for kind in ThingKind:
    reg[kind] = BuildingInfo(
      displayName: "",
      spriteKey: "",
      ascii: '?',
      renderColor: (r: 180'u8, g: 180'u8, b: 180'u8),
      buildIndex: -1,
      buildCost: @[],
      buildCooldown: 0,
      useKind: UseNone,
      stockpileRes: ResourceNone,
      popCap: 0,
      barrelCapacity: 0,
      fertileRadius: 0,
      dropoffResources: {},
      storageItems: @[],
      craftStation: StationNone,
      trainCosts: @[]
    )

  # Altar
  reg[Altar] = BuildingInfo(
    displayName: "Altar", spriteKey: "altar", ascii: 'a',
    renderColor: (r: 220'u8, g: 0'u8, b: 220'u8), buildIndex: -1, buildCost: @[], buildCooldown: 0,
    useKind: UseAltar, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationNone, trainCosts: @[])

  # TownCenter
  reg[TownCenter] = BuildingInfo(
    displayName: "Town Center", spriteKey: "town_center", ascii: 'N',
    renderColor: (r: 190'u8, g: 180'u8, b: 140'u8), buildIndex: 1, buildCost: @[(ItemWood, 14)], buildCooldown: 16,
    useKind: UseDropoff, stockpileRes: ResourceNone, popCap: TownCenterPopCap, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {ResourceFood, ResourceWood, ResourceGold, ResourceStone}, storageItems: @[],
    craftStation: StationNone, trainCosts: @[])

  # House
  reg[House] = BuildingInfo(
    displayName: "House", spriteKey: "house", ascii: 'h',
    renderColor: (r: 170'u8, g: 140'u8, b: 110'u8), buildIndex: 0, buildCost: @[(ItemWood, 1)], buildCooldown: 10,
    useKind: UseNone, stockpileRes: ResourceNone, popCap: HousePopCap, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationNone, trainCosts: @[])

  # Door
  reg[Door] = BuildingInfo(
    displayName: "Door", spriteKey: "door", ascii: 'D',
    renderColor: (r: 120'u8, g: 100'u8, b: 80'u8), buildIndex: BuildIndexDoor, buildCost: @[(ItemWood, 1)], buildCooldown: 6,
    useKind: UseNone, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationNone, trainCosts: @[])

  # ClayOven
  reg[ClayOven] = BuildingInfo(
    displayName: "Clay Oven", spriteKey: "clay_oven", ascii: 'C',
    renderColor: (r: 255'u8, g: 180'u8, b: 120'u8), buildIndex: 20, buildCost: @[(ItemWood, 4)], buildCooldown: 12,
    useKind: UseClayOven, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationOven, trainCosts: @[])

  # WeavingLoom
  reg[WeavingLoom] = BuildingInfo(
    displayName: "Weaving Loom", spriteKey: "weaving_loom", ascii: 'W',
    renderColor: (r: 0'u8, g: 180'u8, b: 255'u8), buildIndex: 21, buildCost: @[(ItemWood, 3)], buildCooldown: 12,
    useKind: UseWeavingLoom, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationLoom, trainCosts: @[])

  # Outpost
  reg[Outpost] = BuildingInfo(
    displayName: "Outpost", spriteKey: "outpost", ascii: '^',
    renderColor: (r: 120'u8, g: 120'u8, b: 140'u8), buildIndex: 13, buildCost: @[(ItemWood, 1)], buildCooldown: 8,
    useKind: UseNone, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationNone, trainCosts: @[])

  # GuardTower
  reg[GuardTower] = BuildingInfo(
    displayName: "Guard Tower", spriteKey: "guard_tower", ascii: 'T',
    renderColor: (r: 110'u8, g: 110'u8, b: 130'u8), buildIndex: BuildIndexGuardTower, buildCost: @[(ItemWood, 5)], buildCooldown: 12,
    useKind: UseNone, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationNone, trainCosts: @[])

  # Barrel
  reg[Barrel] = BuildingInfo(
    displayName: "Barrel", spriteKey: "barrel", ascii: 'b',
    renderColor: (r: 150'u8, g: 110'u8, b: 60'u8), buildIndex: 22, buildCost: @[(ItemWood, 2)], buildCooldown: 10,
    useKind: UseStorage, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: BarrelCapacity, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[ItemBread, ItemMeat, ItemFish, ItemPlant, ItemLantern, ItemSpear, ItemArmor, ItemBar, ItemRelic],
    craftStation: StationNone, trainCosts: @[])

  # Mill
  reg[Mill] = BuildingInfo(
    displayName: "Mill", spriteKey: "mill", ascii: 'm',
    renderColor: (r: 210'u8, g: 200'u8, b: 170'u8), buildIndex: 2, buildCost: @[(ItemWood, 5)], buildCooldown: 12,
    useKind: UseDropoff, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 2,
    dropoffResources: {ResourceFood}, storageItems: @[], craftStation: StationNone, trainCosts: @[])

  # Granary
  reg[Granary] = BuildingInfo(
    displayName: "Granary", spriteKey: "granary", ascii: 'n',
    renderColor: (r: 220'u8, g: 200'u8, b: 150'u8), buildIndex: 5, buildCost: @[(ItemWood, 5)], buildCooldown: 12,
    useKind: UseDropoffAndStorage, stockpileRes: ResourceFood, popCap: 0, barrelCapacity: BarrelCapacity, fertileRadius: 0,
    dropoffResources: {ResourceFood}, storageItems: @[ItemWheat], craftStation: StationNone, trainCosts: @[])

  # LumberCamp
  reg[LumberCamp] = BuildingInfo(
    displayName: "Lumber Camp", spriteKey: "lumber_camp", ascii: 'L',
    renderColor: (r: 140'u8, g: 100'u8, b: 60'u8), buildIndex: 3, buildCost: @[(ItemWood, 5)], buildCooldown: 10,
    useKind: UseDropoff, stockpileRes: ResourceWood, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {ResourceWood}, storageItems: @[], craftStation: StationNone, trainCosts: @[])

  # Quarry
  reg[Quarry] = BuildingInfo(
    displayName: "Quarry", spriteKey: "quarry", ascii: 'Q',
    renderColor: (r: 120'u8, g: 120'u8, b: 120'u8), buildIndex: 4, buildCost: @[(ItemWood, 5)], buildCooldown: 12,
    useKind: UseDropoff, stockpileRes: ResourceStone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {ResourceStone}, storageItems: @[], craftStation: StationNone, trainCosts: @[])

  # MiningCamp
  reg[MiningCamp] = BuildingInfo(
    displayName: "Mining Camp", spriteKey: "mining_camp", ascii: 'M',
    renderColor: (r: 200'u8, g: 190'u8, b: 120'u8), buildIndex: 15, buildCost: @[(ItemWood, 5)], buildCooldown: 12,
    useKind: UseDropoff, stockpileRes: ResourceGold, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {ResourceGold}, storageItems: @[], craftStation: StationNone, trainCosts: @[])

  # Barracks
  reg[Barracks] = BuildingInfo(
    displayName: "Barracks", spriteKey: "barracks", ascii: 'r',
    renderColor: (r: 160'u8, g: 90'u8, b: 60'u8), buildIndex: 8, buildCost: @[(ItemWood, 9)], buildCooldown: 12,
    useKind: UseTrain, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationNone,
    trainCosts: @[(res: ResourceFood, count: 3), (res: ResourceGold, count: 1)])

  # ArcheryRange
  reg[ArcheryRange] = BuildingInfo(
    displayName: "Archery Range", spriteKey: "archery_range", ascii: 'g',
    renderColor: (r: 140'u8, g: 120'u8, b: 180'u8), buildIndex: 9, buildCost: @[(ItemWood, 9)], buildCooldown: 12,
    useKind: UseTrain, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationNone,
    trainCosts: @[(res: ResourceWood, count: 2), (res: ResourceGold, count: 2)])

  # Stable
  reg[Stable] = BuildingInfo(
    displayName: "Stable", spriteKey: "stable", ascii: 's',
    renderColor: (r: 120'u8, g: 90'u8, b: 60'u8), buildIndex: 10, buildCost: @[(ItemWood, 9)], buildCooldown: 12,
    useKind: UseTrain, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationNone,
    trainCosts: @[(res: ResourceFood, count: 3)])

  # SiegeWorkshop
  reg[SiegeWorkshop] = BuildingInfo(
    displayName: "Siege Workshop", spriteKey: "siege_workshop", ascii: 'i',
    renderColor: (r: 120'u8, g: 120'u8, b: 160'u8), buildIndex: 11, buildCost: @[(ItemWood, 10)], buildCooldown: 14,
    useKind: UseTrainAndCraft, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationSiegeWorkshop,
    trainCosts: @[(res: ResourceWood, count: 3), (res: ResourceStone, count: 2)])

  # MangonelWorkshop
  reg[MangonelWorkshop] = BuildingInfo(
    displayName: "Mangonel Workshop", spriteKey: "mangonel_workshop", ascii: 'j',
    renderColor: (r: 120'u8, g: 130'u8, b: 160'u8), buildIndex: BuildIndexMangonelWorkshop, buildCost: @[(ItemWood, 10), (ItemStone, 4)], buildCooldown: 14,
    useKind: UseTrain, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationNone,
    trainCosts: @[(res: ResourceWood, count: 4), (res: ResourceStone, count: 3)])

  # TrebuchetWorkshop
  reg[TrebuchetWorkshop] = BuildingInfo(
    displayName: "Trebuchet Workshop", spriteKey: "trebuchet_workshop", ascii: 'T',
    renderColor: (r: 100'u8, g: 110'u8, b: 150'u8), buildIndex: 25, buildCost: @[(ItemWood, 12), (ItemStone, 6)], buildCooldown: 16,
    useKind: UseTrain, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationNone,
    trainCosts: @[(res: ResourceWood, count: 5), (res: ResourceGold, count: 4)])

  # Blacksmith
  reg[Blacksmith] = BuildingInfo(
    displayName: "Blacksmith", spriteKey: "blacksmith", ascii: 'k',
    renderColor: (r: 90'u8, g: 90'u8, b: 90'u8), buildIndex: 16, buildCost: @[(ItemWood, 8)], buildCooldown: 12,
    useKind: UseBlacksmith, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: BarrelCapacity, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[ItemArmor, ItemSpear], craftStation: StationBlacksmith, trainCosts: @[])

  # Market
  reg[Market] = BuildingInfo(
    displayName: "Market", spriteKey: "market", ascii: 'e',
    renderColor: (r: 200'u8, g: 170'u8, b: 120'u8), buildIndex: 7, buildCost: @[(ItemWood, 9)], buildCooldown: 12,
    useKind: UseMarket, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationNone, trainCosts: @[])

  # Dock
  reg[Dock] = BuildingInfo(
    displayName: "Dock", spriteKey: "dock", ascii: 'd',
    renderColor: (r: 80'u8, g: 140'u8, b: 200'u8), buildIndex: 6, buildCost: @[(ItemWood, 8)], buildCooldown: 12,
    useKind: UseDropoffAndTrain, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {ResourceFood}, storageItems: @[], craftStation: StationNone,
    trainCosts: @[(res: ResourceWood, count: 3), (res: ResourceGold, count: 2)])

  # Monastery
  reg[Monastery] = BuildingInfo(
    displayName: "Monastery", spriteKey: "monastery", ascii: 'y',
    renderColor: (r: 220'u8, g: 200'u8, b: 120'u8), buildIndex: 17, buildCost: @[(ItemWood, 9)], buildCooldown: 12,
    useKind: UseTrain, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationNone,
    trainCosts: @[(res: ResourceGold, count: 2)])

  # University
  reg[University] = BuildingInfo(
    displayName: "University", spriteKey: "university", ascii: 'u',
    renderColor: (r: 140'u8, g: 160'u8, b: 200'u8), buildIndex: 18, buildCost: @[(ItemWood, 10)], buildCooldown: 14,
    useKind: UseUniversity, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationTable, trainCosts: @[])

  # Castle
  reg[Castle] = BuildingInfo(
    displayName: "Castle", spriteKey: "castle", ascii: 'c',
    renderColor: (r: 120'u8, g: 120'u8, b: 120'u8), buildIndex: 12, buildCost: @[(ItemStone, 33)], buildCooldown: 20,
    useKind: UseCastle, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationNone,
    trainCosts: @[(res: ResourceFood, count: 4), (res: ResourceGold, count: 2)])

  # Wonder
  reg[Wonder] = BuildingInfo(
    displayName: "Wonder", spriteKey: "wonder", ascii: 'W',
    renderColor: (r: 255'u8, g: 215'u8, b: 0'u8), buildIndex: 26, buildCost: @[(ItemWood, 50), (ItemStone, 50), (ItemGold, 50)], buildCooldown: 50,
    useKind: UseNone, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationNone, trainCosts: @[])

  # GoblinHive
  reg[GoblinHive] = BuildingInfo(
    displayName: "Goblin Hive", spriteKey: "goblin_hive", ascii: 'H',
    renderColor: (r: 120'u8, g: 170'u8, b: 90'u8), buildIndex: -1, buildCost: @[], buildCooldown: 0,
    useKind: UseNone, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationNone, trainCosts: @[])

  # GoblinHut
  reg[GoblinHut] = BuildingInfo(
    displayName: "Goblin Hut", spriteKey: "goblin_hut", ascii: 'g',
    renderColor: (r: 110'u8, g: 150'u8, b: 90'u8), buildIndex: -1, buildCost: @[], buildCooldown: 0,
    useKind: UseNone, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationNone, trainCosts: @[])

  # GoblinTotem
  reg[GoblinTotem] = BuildingInfo(
    displayName: "Goblin Totem", spriteKey: "goblin_totem", ascii: 'T',
    renderColor: (r: 90'u8, g: 140'u8, b: 100'u8), buildIndex: -1, buildCost: @[], buildCooldown: 0,
    useKind: UseNone, stockpileRes: ResourceNone, popCap: 0, barrelCapacity: 0, fertileRadius: 0,
    dropoffResources: {}, storageItems: @[], craftStation: StationNone, trainCosts: @[])

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
    (ShallowWater, "Shallow Water", "", '.'),
    (Bridge, "Bridge", "", '='),
    (Fertile, "Fertile", "", 'f'),
    (Road, "Road", "", 'r'),
    (Grass, "Grass", "", 'g'),
    (Dune, "Dune", "", 'd'),
    (Sand, "Sand", "", 's'),
    (Snow, "Snow", "", 'n'),
    (Mud, "Mud", "", 'm')
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
    (ControlPoint, "Control Point", "control_point", 'P'),
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

# Lookup procs - now simple registry lookups instead of case statements
proc buildingUseKind*(kind: ThingKind): BuildingUseKind {.inline.} =
  BuildingRegistry[kind].useKind

proc buildingStockpileRes*(kind: ThingKind): StockpileResource {.inline.} =
  BuildingRegistry[kind].stockpileRes

proc buildingBuildable*(kind: ThingKind): bool {.inline.} =
  let info = BuildingRegistry[kind]
  info.buildIndex >= 0 and info.buildCost.len > 0

proc buildingPopCap*(kind: ThingKind): int {.inline.} =
  BuildingRegistry[kind].popCap

proc buildingBarrelCapacity*(kind: ThingKind): int {.inline.} =
  BuildingRegistry[kind].barrelCapacity

proc buildingFertileRadius*(kind: ThingKind): int {.inline.} =
  BuildingRegistry[kind].fertileRadius

proc buildingDropoffResources*(kind: ThingKind): set[StockpileResource] {.inline.} =
  BuildingRegistry[kind].dropoffResources

proc buildingStorageItems*(kind: ThingKind): seq[ItemKey] {.inline.} =
  BuildingRegistry[kind].storageItems

proc buildingCraftStation*(kind: ThingKind): CraftStation {.inline.} =
  BuildingRegistry[kind].craftStation

proc buildingHasCraftStation*(kind: ThingKind): bool {.inline.} =
  BuildingRegistry[kind].craftStation != StationNone

proc buildingHasTrain*(kind: ThingKind): bool {.inline.} =
  BuildingRegistry[kind].trainCosts.len > 0

# Castle unique units by team (civilization)
const CastleUniqueUnits*: array[MapRoomObjectsTeams, AgentUnitClass] = [
  UnitSamurai,        # Team 0
  UnitLongbowman,     # Team 1
  UnitCataphract,     # Team 2
  UnitWoadRaider,     # Team 3
  UnitTeutonicKnight, # Team 4
  UnitHuskarl,        # Team 5
  UnitMameluke,       # Team 6
  UnitJanissary       # Team 7
]

proc buildingTrainUnit*(kind: ThingKind, teamId: int = -1): AgentUnitClass =
  ## Returns the unit class trained by a building.
  ## For castles, each team has a unique unit (AoE2-style).
  case kind
  of Barracks: UnitManAtArms
  of ArcheryRange: UnitArcher
  of Stable: UnitScout
  of SiegeWorkshop: UnitBatteringRam
  of MangonelWorkshop: UnitMangonel
  of TrebuchetWorkshop: UnitTrebuchet
  of Monastery: UnitMonk
  of Castle:
    if teamId >= 0 and teamId < MapRoomObjectsTeams:
      CastleUniqueUnits[teamId]
    else:
      UnitKnight  # Fallback for invalid/unknown team
  of Dock: UnitTradeCog
  else: UnitVillager

proc buildingTrainCosts*(kind: ThingKind): seq[tuple[res: StockpileResource, count: int]] {.inline.} =
  BuildingRegistry[kind].trainCosts

proc unitTrainTime*(unitClass: AgentUnitClass): int =
  ## Training duration in game steps for each unit type (AoE2-style).
  ## More powerful units take longer to train.
  case unitClass
  of UnitVillager: 50
  of UnitManAtArms: 40
  of UnitArcher: 35
  of UnitScout: 30
  of UnitKnight: 60
  of UnitMonk: 50
  of UnitBatteringRam: 80
  of UnitMangonel: 80
  of UnitTrebuchet: 80
  of UnitGoblin: 30
  of UnitBoat: 60
  # Castle unique units
  of UnitSamurai: 50
  of UnitLongbowman: 45
  of UnitCataphract: 60
  of UnitWoadRaider: 40
  of UnitTeutonicKnight: 55
  of UnitHuskarl: 45
  of UnitMameluke: 55
  of UnitJanissary: 50
  of UnitKing: 0  # Kings are not trainable (placed at game start for Regicide)
  of UnitTradeCog: 60  # Trade Cogs trained at Docks
  # Unit upgrade tiers (use same training time as their base building)
  of UnitLongSwordsman: 45
  of UnitChampion: 50
  of UnitLightCavalry: 35
  of UnitHussar: 40
  of UnitCrossbowman: 40
  of UnitArbalester: 45

proc buildIndexFor*(kind: ThingKind): int =
  BuildingRegistry[kind].buildIndex

proc appendBuildingRecipes*(recipes: var seq[CraftRecipe]) =
  for kind in ThingKind:
    if not isBuildingKind(kind):
      continue
    if not buildingBuildable(kind):
      continue
    let info = BuildingRegistry[kind]
    addRecipe(
      recipes,
      toSnakeCase($kind),
      StationTable,
      info.buildCost,
      @[(thingItem($kind), 1)]
    )
