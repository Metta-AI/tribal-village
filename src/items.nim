## Item catalog and container definitions for future stockpile/storage work.
## This keeps the "what exists" separate from game logic.

import std/tables

type
  ItemKey* = string
  Inventory* = Table[ItemKey, int]

const
  ItemNone* = ""
  ItemGold* = "gold"
  ItemStone* = "stone"
  ItemBar* = "bar"
  ItemWater* = "water"
  ItemWheat* = "wheat"
  ItemWood* = "wood"
  ItemSpear* = "spear"
  ItemLantern* = "lantern"
  ItemArmor* = "armor"
  ItemBread* = "bread"
  ItemPlant* = "plant"
  ItemFish* = "fish"
  ItemRock* = "rock"
  ItemBranch* = "branch"
  ItemHearts* = "hearts"
  ItemThingPrefix* = "thing:"

  ObservedItemKeys* = [
    ItemGold,
    ItemStone,
    ItemBar,
    ItemWater,
    ItemWheat,
    ItemWood,
    ItemSpear,
    ItemLantern,
    ItemArmor,
    ItemBread
  ]

type
  StockpileResource* = enum
    ResourceFood
    ResourceWood
    ResourceGold
    ResourceStone
    ResourceWater

proc isFoodItem*(key: ItemKey): bool =
  case key
  of ItemWheat, ItemBread, ItemFish, ItemPlant:
    true
  else:
    false

proc isStockpileResourceKey*(key: ItemKey): bool =
  case key
  of ItemWood, ItemGold, ItemStone, ItemWater:
    true
  else:
    isFoodItem(key)

proc stockpileResourceForItem*(key: ItemKey): StockpileResource =
  if isFoodItem(key):
    return ResourceFood
  case key
  of ItemWood: ResourceWood
  of ItemGold: ResourceGold
  of ItemStone: ResourceStone
  of ItemWater: ResourceWater
  else: ResourceFood

proc emptyInventory*(): Inventory =
  initTable[ItemKey, int]()

type
  ItemCategory* = enum
    Ammo
    AnimalCaged
    Armor
    BarBlock
    ClothThread
    Coins
    Corpses
    FinishedGoods
    Food
    FurnitureStorage
    Gem
    Leather
    Refuse
    Sheets
    StoneOre
    Weapons
    Wood

  ContainerKind* = enum
    ContainerNone
    Barrel
    Pot
    Bin
    Bag
    Cage
    Chest

  ItemDef* = object
    id*: string
    displayName*: string
    category*: ItemCategory
    maxStack*: int          # 1 for non-stackable items
    isContainer*: bool
    containerKind*: ContainerKind
    notes*: string

  ContainerDef* = object
    kind*: ContainerKind
    displayName*: string
    capacity*: int          # Item count capacity
    allowedCategories*: set[ItemCategory]

  DfTokenPlacement* = enum
    DfItem
    DfBuilding

  DfTokenDef* = object
    token*: string
    id*: string
    displayName*: string
    placement*: DfTokenPlacement
    notes*: string

  DfTokenBehavior* = object
    token*: string
    inputs*: seq[string]
    outputs*: seq[string]
    uses*: string

  GameStructureDef* = object
    id*: string
    displayName*: string
    buildCost*: seq[string]
    uses*: string

  ItemAmount* = tuple[key: ItemKey, count: int]

  CraftStation* = enum
    StationBlacksmith
    StationArmory
    StationLoom
    StationOven
    StationTable
    StationSiegeWorkshop

  CraftRecipe* = object
    id*: string
    station*: CraftStation
    inputs*: seq[ItemAmount]
    outputs*: seq[ItemAmount]
    cooldown*: int

const
  ## DF tileset overrides are currently disabled; keep the catalog empty so
  ## asset generation becomes a no-op without extra build flags.
  DfTokenCatalog*: seq[DfTokenDef] = @[]

proc addRecipe*(recipes: var seq[CraftRecipe], id: string, station: CraftStation,
                inputs, outputs: seq[ItemAmount], cooldown: int = 8) =
  recipes.add(CraftRecipe(id: id, station: station, inputs: inputs, outputs: outputs, cooldown: cooldown))

proc thingItem*(name: string): ItemKey =
  ItemThingPrefix & name

const
  ## Container examples for stockpile storage mechanics.
  ExampleContainers*: seq[ContainerDef] = @[
    ContainerDef(kind: Barrel, displayName: "Barrel", capacity: 30,
      allowedCategories: {Food, BarBlock, StoneOre, Wood}),
    ContainerDef(kind: Pot, displayName: "Pot", capacity: 20,
      allowedCategories: {Food}),
    ContainerDef(kind: Bin, displayName: "Bin", capacity: 40,
      allowedCategories: {FinishedGoods, ClothThread, Leather, Coins, Ammo}),
    ContainerDef(kind: Bag, displayName: "Bag", capacity: 10,
      allowedCategories: {Food, Gem, Refuse, ClothThread}),
    ContainerDef(kind: Cage, displayName: "Cage", capacity: 1,
      allowedCategories: {AnimalCaged}),
    ContainerDef(kind: Chest, displayName: "Chest", capacity: 25,
      allowedCategories: {Weapons, Armor, FinishedGoods, Coins})
  ]

proc initCraftRecipes*(): seq[CraftRecipe] =
  var recipes: seq[CraftRecipe] = @[]

  # Table/workbench: wood and stone crafts.
  addRecipe(recipes, "door_wood", StationTable, @[(ItemWood, 1)], @[("door", 1)], 6)
  addRecipe(recipes, "barrel", StationTable, @[(ItemWood, 2)], @[(thingItem("Barrel"), 1)], 10)
  # AoE2-inspired building costs scaled to ~1/20 (house = 1 wood baseline).
  addRecipe(recipes, "mill", StationTable, @[(ItemWood, 5)], @[(thingItem("Mill"), 1)], 12)
  addRecipe(recipes, "lumber_camp", StationTable, @[(ItemWood, 5)], @[(thingItem("LumberCamp"), 1)], 10)
  addRecipe(recipes, "mining_camp", StationTable, @[(ItemWood, 5)], @[(thingItem("MiningCamp"), 1)], 12)
  addRecipe(recipes, "house", StationTable, @[(ItemWood, 1)], @[(thingItem("House"), 1)], 10)
  addRecipe(recipes, "town_center", StationTable, @[(ItemWood, 14)], @[(thingItem("TownCenter"), 1)], 16)
  addRecipe(recipes, "barracks", StationTable, @[(ItemWood, 9)], @[(thingItem("Barracks"), 1)], 12)
  addRecipe(recipes, "archery_range", StationTable, @[(ItemWood, 9)], @[(thingItem("ArcheryRange"), 1)], 12)
  addRecipe(recipes, "stable", StationTable, @[(ItemWood, 9)], @[(thingItem("Stable"), 1)], 12)
  addRecipe(recipes, "siege_workshop", StationTable, @[(ItemWood, 10)], @[(thingItem("SiegeWorkshop"), 1)], 14)
  addRecipe(recipes, "blacksmith", StationTable, @[(ItemWood, 8)], @[(thingItem("Blacksmith"), 1)], 12)
  addRecipe(recipes, "market", StationTable, @[(ItemWood, 9)], @[(thingItem("Market"), 1)], 12)
  addRecipe(recipes, "dock", StationTable, @[(ItemWood, 8)], @[(thingItem("Dock"), 1)], 12)
  addRecipe(recipes, "monastery", StationTable, @[(ItemWood, 9)], @[(thingItem("Monastery"), 1)], 12)
  addRecipe(recipes, "university", StationTable, @[(ItemWood, 10)], @[(thingItem("University"), 1)], 14)
  addRecipe(recipes, "castle", StationTable, @[(ItemStone, 33)], @[(thingItem("Castle"), 1)], 20)
  addRecipe(recipes, "outpost", StationTable, @[(ItemWood, 1)], @[(thingItem("Outpost"), 1)], 8)
  addRecipe(recipes, "armory", StationTable, @[(ItemWood, 4)], @[(thingItem("Armory"), 1)], 12)
  addRecipe(recipes, "clay_oven", StationTable, @[(ItemWood, 4)], @[(thingItem("ClayOven"), 1)], 12)
  addRecipe(recipes, "weaving_loom", StationTable, @[(ItemWood, 3)], @[(thingItem("WeavingLoom"), 1)], 12)
  # Siege workshop crafts for walls/roads (1/20 AoE2 scale).
  addRecipe(recipes, "wall", StationSiegeWorkshop, @[(ItemStone, 1)], @[(thingItem("Wall"), 1)], 6)
  addRecipe(recipes, "road", StationSiegeWorkshop, @[(ItemWood, 1)], @[(thingItem("Road"), 1)], 4)
  addRecipe(recipes, "bucket", StationTable, @[(ItemWood, 1)], @[("bucket", 1)], 6)
  addRecipe(recipes, "box", StationTable, @[(ItemWood, 1)], @[("box", 1)], 6)
  addRecipe(recipes, "bin", StationTable, @[(ItemWood, 2)], @[("bin", 1)], 8)
  addRecipe(recipes, "cabinet", StationTable, @[(ItemWood, 2)], @[("cabinet", 1)], 8)
  addRecipe(recipes, "cage", StationTable, @[(ItemWood, 2)], @[("cage", 1)], 8)
  addRecipe(recipes, "animaltrap", StationTable, @[(ItemWood, 1)], @[("animaltrap", 1)], 6)
  addRecipe(recipes, "armorstand_wood", StationTable, @[(ItemWood, 2)], @[("armorstand", 1)], 8)
  addRecipe(recipes, "weaponrack_wood", StationTable, @[(ItemWood, 2)], @[("weaponrack", 1)], 8)
  # Blacksmith: metalworking and mechanisms.
  addRecipe(recipes, "weapon", StationBlacksmith, @[(ItemBar, 1)], @[("weapon", 1)], 8)
  addRecipe(recipes, "armor_metal", StationBlacksmith, @[(ItemBar, 2)], @[(ItemArmor, 1)], 10)
  addRecipe(recipes, "shield_metal", StationBlacksmith, @[(ItemBar, 1)], @[("shield", 1)], 8)
  addRecipe(recipes, "anvil", StationBlacksmith, @[(ItemBar, 2)], @[("anvil", 1)], 10)
  addRecipe(recipes, "goblet", StationBlacksmith, @[(ItemBar, 1)], @[("goblet", 1)], 6)
  addRecipe(recipes, "crown", StationBlacksmith, @[(ItemBar, 1)], @[("crown", 1)], 8)
  addRecipe(recipes, "armorstand_metal", StationBlacksmith, @[(ItemBar, 1)], @[("armorstand", 1)], 8)
  addRecipe(recipes, "weaponrack_metal", StationBlacksmith, @[(ItemBar, 1)], @[("weaponrack", 1)], 8)

  # Armory: wood gear.
  addRecipe(recipes, "shield_wood", StationArmory, @[(ItemWood, 1)], @[("shield", 1)], 6)

  # Oven: food.
  addRecipe(recipes, "bread", StationOven, @[(ItemWheat, 1)], @[(ItemBread, 1)], 6)

  recipes

let CraftRecipes*: seq[CraftRecipe] = initCraftRecipes()
