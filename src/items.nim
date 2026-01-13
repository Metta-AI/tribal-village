## Item catalog and container definitions for future stockpile/storage work.
## This keeps the "what exists" separate from game logic.

import std/tables
import std/hashes

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

  ItemKeyKind* = enum
    ItemKeyNone
    ItemKeyItem
    ItemKeyThing
    ItemKeyOther

  ## ItemKey represents inventory entries and craft/build outputs.
  ## - ItemKeyItem: core item kinds (typed)
  ## - ItemKeyThing: buildable/placeable things by name
  ## - ItemKeyOther: extra recipe-only items
  ItemKey* = object
    case kind*: ItemKeyKind
    of ItemKeyNone:
      discard
    of ItemKeyItem:
      item*: ItemKind
    of ItemKeyThing, ItemKeyOther:
      name*: string

  Inventory* = Table[ItemKey, int]

const
  SpearCharges* = 5       # Spears forged per craft & max carried
  ArmorPoints* = 5        # Armor durability granted per craft
  BreadHealAmount* = 999  # Effectively "heal to full" per bread use

  ItemKindNames: array[ItemKind, string] = [
    "",        # ikNone
    "gold",
    "stone",
    "bar",
    "water",
    "wheat",
    "wood",
    "spear",
    "lantern",
    "armor",
    "bread",
    "plant",
    "fish",
    "meat",
    "hearts"
  ]

  ItemNone* = ItemKey(kind: ItemKeyNone)
  ItemGold* = ItemKey(kind: ItemKeyItem, item: ikGold)
  ItemStone* = ItemKey(kind: ItemKeyItem, item: ikStone)
  ItemBar* = ItemKey(kind: ItemKeyItem, item: ikBar)
  ItemWater* = ItemKey(kind: ItemKeyItem, item: ikWater)
  ItemWheat* = ItemKey(kind: ItemKeyItem, item: ikWheat)
  ItemWood* = ItemKey(kind: ItemKeyItem, item: ikWood)
  ItemSpear* = ItemKey(kind: ItemKeyItem, item: ikSpear)
  ItemLantern* = ItemKey(kind: ItemKeyItem, item: ikLantern)
  ItemArmor* = ItemKey(kind: ItemKeyItem, item: ikArmor)
  ItemBread* = ItemKey(kind: ItemKeyItem, item: ikBread)
  ItemPlant* = ItemKey(kind: ItemKeyItem, item: ikPlant)
  ItemFish* = ItemKey(kind: ItemKeyItem, item: ikFish)
  ItemMeat* = ItemKey(kind: ItemKeyItem, item: ikMeat)
  ItemHearts* = ItemKey(kind: ItemKeyItem, item: ikHearts)

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
  ## Convert ItemKind enum to ItemKey
  if kind == ikNone:
    ItemNone
  else:
    ItemKey(kind: ItemKeyItem, item: kind)

proc toItemKind*(key: ItemKey): ItemKind {.inline.} =
  ## Convert ItemKey to ItemKind enum (returns ikNone for non-item keys)
  if key.kind == ItemKeyItem:
    key.item
  else:
    ikNone

proc itemKindName*(kind: ItemKind): string =
  ItemKindNames[kind]

proc itemKeyName*(key: ItemKey): string =
  case key.kind
  of ItemKeyNone:
    ""
  of ItemKeyItem:
    itemKindName(key.item)
  of ItemKeyThing, ItemKeyOther:
    key.name

proc `$`*(key: ItemKey): string =
  itemKeyName(key)

proc isItemKey*(key: ItemKey): bool =
  key.kind == ItemKeyItem

proc isThingKey*(key: ItemKey): bool =
  key.kind == ItemKeyThing

proc isOtherKey*(key: ItemKey): bool =
  key.kind == ItemKeyOther

proc `==`*(a, b: ItemKey): bool =
  if a.kind != b.kind:
    return false
  case a.kind
  of ItemKeyNone:
    true
  of ItemKeyItem:
    a.item == b.item
  of ItemKeyThing, ItemKeyOther:
    a.name == b.name

proc hash*(key: ItemKey): Hash =
  var h = hash(key.kind)
  case key.kind
  of ItemKeyNone:
    discard
  of ItemKeyItem:
    h = h !& hash(key.item)
  of ItemKeyThing, ItemKeyOther:
    h = h !& hash(key.name)
  result = !$h

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
  key.kind == ItemKeyItem and key.item in {ikWheat, ikBread, ikFish, ikMeat, ikPlant}

proc isStockpileResourceKey*(key: ItemKey): bool =
  if key.kind != ItemKeyItem:
    return false
  case key.item
  of ikWood, ikGold, ikStone, ikWater:
    true
  else:
    isFoodItem(key)

proc stockpileResourceForItem*(key: ItemKey): StockpileResource =
  if isFoodItem(key):
    return ResourceFood
  if key.kind != ItemKeyItem:
    return ResourceNone
  case key.item
  of ikWood: ResourceWood
  of ikGold: ResourceGold
  of ikStone: ResourceStone
  of ikWater: ResourceWater
  else: ResourceNone

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
                inputs, outputs: seq[ItemAmount], cooldown: int = 0) =
  discard cooldown
  recipes.add(CraftRecipe(id: id, station: station, inputs: inputs, outputs: outputs, cooldown: 0))

proc thingItem*(name: string): ItemKey =
  ItemKey(kind: ItemKeyThing, name: name)

proc otherItem*(name: string): ItemKey =
  ItemKey(kind: ItemKeyOther, name: name)

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
  addRecipe(recipes, "bucket", StationTable, @[(ItemWood, 1)], @[(otherItem("bucket"), 1)], 6)
  addRecipe(recipes, "box", StationTable, @[(ItemWood, 1)], @[(otherItem("box"), 1)], 6)
  addRecipe(recipes, "bin", StationTable, @[(ItemWood, 2)], @[(otherItem("bin"), 1)], 8)
  addRecipe(recipes, "cabinet", StationTable, @[(ItemWood, 2)], @[(otherItem("cabinet"), 1)], 8)
  addRecipe(recipes, "cage", StationTable, @[(ItemWood, 2)], @[(otherItem("cage"), 1)], 8)
  addRecipe(recipes, "animaltrap", StationTable, @[(ItemWood, 1)], @[(otherItem("animaltrap"), 1)], 6)
  addRecipe(recipes, "armorstand_wood", StationTable, @[(ItemWood, 2)], @[(otherItem("armorstand"), 1)], 8)
  addRecipe(recipes, "weaponrack_wood", StationTable, @[(ItemWood, 2)], @[(otherItem("weaponrack"), 1)], 8)
  # Blacksmith: metalworking and mechanisms.
  addRecipe(recipes, "spear", StationBlacksmith, @[(ItemWood, 1)], @[(ItemSpear, SpearCharges)], 6)
  addRecipe(recipes, "armor_metal", StationBlacksmith, @[(ItemBar, 2)], @[(ItemArmor, ArmorPoints)], 10)
  addRecipe(recipes, "weapon", StationBlacksmith, @[(ItemBar, 1)], @[(otherItem("weapon"), 1)], 8)
  addRecipe(recipes, "shield_metal", StationBlacksmith, @[(ItemBar, 1)], @[(otherItem("shield"), 1)], 8)
  addRecipe(recipes, "anvil", StationBlacksmith, @[(ItemBar, 2)], @[(otherItem("anvil"), 1)], 10)
  addRecipe(recipes, "goblet", StationBlacksmith, @[(ItemBar, 1)], @[(otherItem("goblet"), 1)], 6)
  addRecipe(recipes, "crown", StationBlacksmith, @[(ItemBar, 1)], @[(otherItem("crown"), 1)], 8)
  addRecipe(recipes, "armorstand_metal", StationBlacksmith, @[(ItemBar, 1)], @[(otherItem("armorstand"), 1)], 8)
  addRecipe(recipes, "weaponrack_metal", StationBlacksmith, @[(ItemBar, 1)], @[(otherItem("weaponrack"), 1)], 8)

  # Armory: wood gear.
  addRecipe(recipes, "shield_wood", StationArmory, @[(ItemWood, 1)], @[(otherItem("shield"), 1)], 6)

  # Oven: food.
  addRecipe(recipes, "bread", StationOven, @[(ItemWheat, 1)], @[(ItemBread, 1)], 6)

  recipes

var CraftRecipes*: seq[CraftRecipe] = initCraftRecipesBase()
