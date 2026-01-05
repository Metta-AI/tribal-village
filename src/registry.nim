type
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
      stockpileRes: ResourceFood
    )

  proc add(kind: ThingKind, displayName, spriteKey: string, ascii: char,
           renderColor: tuple[r, g, b: uint8], teamOwned = true,
           needsLantern = true, hasFrozenOverlay = true, usesCooldown = true,
           showStockpile = false, stockpileRes = ResourceFood) =
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
      stockpileRes: stockpileRes
    )

  add(Altar, "Altar", "altar", 'a', (r: 220'u8, g: 0'u8, b: 220'u8),
      usesCooldown = false, needsLantern = true)
  add(TownCenter, "Town Center", "town_center", 'N', (r: 190'u8, g: 180'u8, b: 140'u8))
  add(House, "House", "house", 'h', (r: 170'u8, g: 140'u8, b: 110'u8))
  add(Armory, "Armory", "armory", 'A', (r: 255'u8, g: 120'u8, b: 40'u8))
  add(ClayOven, "Clay Oven", "clay_oven", 'C', (r: 255'u8, g: 180'u8, b: 120'u8))
  add(WeavingLoom, "Weaving Loom", "weaving_loom", 'W', (r: 0'u8, g: 180'u8, b: 255'u8))
  add(Outpost, "Outpost", "outpost", '^', (r: 120'u8, g: 120'u8, b: 140'u8),
      usesCooldown = false)
  add(Barrel, "Barrel", "barrel", 'b', (r: 150'u8, g: 110'u8, b: 60'u8),
      needsLantern = false, usesCooldown = false)
  add(Mill, "Granary", "granary", 'm', (r: 210'u8, g: 200'u8, b: 170'u8),
      usesCooldown = false, showStockpile = true, stockpileRes = ResourceFood)
  add(LumberCamp, "Lumber Yard", "lumber_yard", 'L', (r: 140'u8, g: 100'u8, b: 60'u8),
      usesCooldown = false, showStockpile = true, stockpileRes = ResourceWood)
  add(MiningCamp, "Quarry", "quarry", 'G', (r: 120'u8, g: 120'u8, b: 120'u8),
      usesCooldown = false, showStockpile = true, stockpileRes = ResourceStone)
  add(Bank, "Bank", "bank", 'B', (r: 220'u8, g: 200'u8, b: 120'u8),
      usesCooldown = false, showStockpile = true, stockpileRes = ResourceGold)
  add(Barracks, "Barracks", "barracks", 'r', (r: 160'u8, g: 90'u8, b: 60'u8))
  add(ArcheryRange, "Archery Range", "archery_range", 'g', (r: 140'u8, g: 120'u8, b: 180'u8))
  add(Stable, "Stable", "stable", 's', (r: 120'u8, g: 90'u8, b: 60'u8))
  add(SiegeWorkshop, "Siege Workshop", "siege_workshop", 'i', (r: 120'u8, g: 120'u8, b: 160'u8))
  add(Blacksmith, "Blacksmith", "blacksmith", 'k', (r: 90'u8, g: 90'u8, b: 90'u8))
  add(Market, "Market", "market", 'e', (r: 200'u8, g: 170'u8, b: 120'u8))
  add(Dock, "Dock", "dock", 'd', (r: 80'u8, g: 140'u8, b: 200'u8))
  add(Monastery, "Monastery", "monastery", 'y', (r: 220'u8, g: 200'u8, b: 120'u8))
  add(University, "University", "university", 'u', (r: 140'u8, g: 160'u8, b: 200'u8))
  add(Castle, "Castle", "castle", 'c', (r: 120'u8, g: 120'u8, b: 120'u8))

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
