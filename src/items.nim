## Item catalog and container definitions for future stockpile/storage work.
## This keeps the "what exists" separate from game logic.

import std/tables

type
  ## Type-safe enum for all item kinds
  ItemKind* = enum
    ikNone = "none"
    ikGold = "gold"
    ikStone = "stone"
    ikBar = "bar"
    ikWater = "water"
    ikWheat = "wheat"
    ikWood = "wood"
    ikSpear = "spear"
    ikLantern = "lantern"
    ikArmor = "armor"
    ikBread = "bread"
    ikPlant = "plant"
    ikFish = "fish"
    ikMeat = "meat"
    ikHearts = "hearts"

  ## ItemKey remains a string for backwards compatibility
  ## Can be either an item kind string or a "thing:ThingKind" building item
  ItemKey* = string

  Inventory* = Table[ItemKey, int]

const
  SpearCharges* = 5       # Spears forged per craft & max carried
  ArmorPoints* = 5        # Armor durability granted per craft
  BreadHealAmount* = 999  # Effectively "heal to full" per bread use

  ## String constants for backwards compatibility - prefer ItemKind enum in new code
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
  ItemMeat* = "meat"
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
    ItemBread,
    ItemMeat,
    ItemFish,
    ItemPlant
  ]

  ## Mapping from ItemKind enum to observation layers (for efficient lookup)
  ObservedItemKinds* = [ikGold, ikStone, ikBar, ikWater, ikWheat, ikWood, ikSpear, ikLantern, ikArmor, ikBread,
                        ikMeat, ikFish, ikPlant]

proc toItemKey*(kind: ItemKind): ItemKey {.inline.} =
  ## Convert ItemKind enum to ItemKey string
  case kind
  of ikNone: ItemNone
  of ikGold: ItemGold
  of ikStone: ItemStone
  of ikBar: ItemBar
  of ikWater: ItemWater
  of ikWheat: ItemWheat
  of ikWood: ItemWood
  of ikSpear: ItemSpear
  of ikLantern: ItemLantern
  of ikArmor: ItemArmor
  of ikBread: ItemBread
  of ikPlant: ItemPlant
  of ikFish: ItemFish
  of ikMeat: ItemMeat
  of ikHearts: ItemHearts

proc toItemKind*(key: ItemKey): ItemKind {.inline.} =
  ## Convert ItemKey string to ItemKind enum (returns ikNone for unknown/thing keys)
  case key
  of ItemGold: ikGold
  of ItemStone: ikStone
  of ItemBar: ikBar
  of ItemWater: ikWater
  of ItemWheat: ikWheat
  of ItemWood: ikWood
  of ItemSpear: ikSpear
  of ItemLantern: ikLantern
  of ItemArmor: ikArmor
  of ItemBread: ikBread
  of ItemPlant: ikPlant
  of ItemFish: ikFish
  of ItemMeat: ikMeat
  of ItemHearts: ikHearts
  else: ikNone

type
  StockpileResource* = enum
    ResourceFood
    ResourceWood
    ResourceGold
    ResourceStone
    ResourceWater
    ResourceNone

proc isFoodItem*(key: ItemKey): bool =
  ## Check if an ItemKey is a food item
  toItemKind(key) in {ikWheat, ikBread, ikFish, ikMeat, ikPlant}

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
    StationNone
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
      allowedCategories: {Food, Refuse, ClothThread}),
    ContainerDef(kind: Cage, displayName: "Cage", capacity: 1,
      allowedCategories: {AnimalCaged}),
    ContainerDef(kind: Chest, displayName: "Chest", capacity: 25,
      allowedCategories: {Weapons, Armor, FinishedGoods, Coins})
  ]

proc initCraftRecipesBase*(): seq[CraftRecipe] =
  var recipes: seq[CraftRecipe] = @[]

  # Table/workbench: wood and stone crafts.
  # Siege workshop crafts for walls/roads (1/20 AoE2 scale).
  addRecipe(recipes, "wall", StationSiegeWorkshop, @[(ItemWood, 1)], @[(thingItem("Wall"), 1)], 6)
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
  addRecipe(recipes, "spear", StationBlacksmith, @[(ItemWood, 1)], @[(ItemSpear, SpearCharges)], 6)
  addRecipe(recipes, "armor_metal", StationBlacksmith, @[(ItemBar, 2)], @[(ItemArmor, ArmorPoints)], 10)
  addRecipe(recipes, "weapon", StationBlacksmith, @[(ItemBar, 1)], @[("weapon", 1)], 8)
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

var CraftRecipes*: seq[CraftRecipe] = initCraftRecipesBase()
