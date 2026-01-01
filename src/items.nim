## Item catalog and container definitions for future stockpile/storage work.
## This keeps the "what exists" separate from game logic.

import std/tables

type
  ItemKey* = string
  Inventory* = Table[ItemKey, int]

const
  ItemNone* = ""
  ItemOre* = "ore"
  ItemBattery* = "battery"
  ItemWater* = "water"
  ItemWheat* = "wheat"
  ItemWood* = "wood"
  ItemSpear* = "spear"
  ItemLantern* = "lantern"
  ItemArmor* = "armor"
  ItemBread* = "bread"
  ItemHearts* = "hearts"
  ItemThingPrefix* = "thing:"

  ObservedItemKeys* = [
    ItemOre,
    ItemBattery,
    ItemWater,
    ItemWheat,
    ItemWood,
    ItemSpear,
    ItemLantern,
    ItemArmor,
    ItemBread
  ]

proc emptyInventory*(): Inventory =
  initTable[ItemKey, int]()

type
  ItemKind* = enum
    ItemNone
    Ore
    Bar
    Water
    Wheat
    Wood
    Spear
    Lantern
    Armor
    Bread
    Hearts

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

const
  ## One example per stockpile category (DF-inspired).
  ExampleItems*: seq[ItemDef] = @[
    ItemDef(id: "ammo_iron_bolt", displayName: "Iron bolt", category: Ammo,
      maxStack: 25, isContainer: false, containerKind: ContainerNone, notes: "Ranged ammo"),
    ItemDef(id: "animal_caged_turkey", displayName: "Caged turkey", category: AnimalCaged,
      maxStack: 1, isContainer: false, containerKind: Cage, notes: "Captured animal"),
    ItemDef(id: "armor_leather_cap", displayName: "Leather cap", category: Armor,
      maxStack: 1, isContainer: false, containerKind: ContainerNone, notes: "Basic armor"),
    ItemDef(id: "bar_copper", displayName: "Copper bar", category: BarBlock,
      maxStack: 10, isContainer: false, containerKind: ContainerNone, notes: "Metal bar"),
    ItemDef(id: "cloth_ropereed", displayName: "Rope reed cloth", category: ClothThread,
      maxStack: 5, isContainer: false, containerKind: ContainerNone, notes: "Woven cloth"),
    ItemDef(id: "coins_silver_stack", displayName: "Silver coin stack", category: Coins,
      maxStack: 50, isContainer: false, containerKind: ContainerNone, notes: "Currency"),
    ItemDef(id: "corpse_rat", displayName: "Dead rat", category: Corpses,
      maxStack: 1, isContainer: false, containerKind: ContainerNone, notes: "Corpse"),
    ItemDef(id: "goods_bone_craft", displayName: "Bone carving", category: FinishedGoods,
      maxStack: 1, isContainer: false, containerKind: ContainerNone, notes: "Finished good"),
    ItemDef(id: "food_plump_helmet", displayName: "Plump helmet", category: Food,
      maxStack: 10, isContainer: false, containerKind: ContainerNone, notes: "Edible"),
    ItemDef(id: "furniture_wooden_chest", displayName: "Wooden chest", category: FurnitureStorage,
      maxStack: 1, isContainer: true, containerKind: Chest, notes: "Storage furniture"),
    ItemDef(id: "gem_rough_ruby", displayName: "Rough ruby", category: Gem,
      maxStack: 5, isContainer: false, containerKind: ContainerNone, notes: "Uncut gem"),
    ItemDef(id: "leather_tanned_hide", displayName: "Tanned hide", category: Leather,
      maxStack: 5, isContainer: false, containerKind: ContainerNone, notes: "Leather"),
    ItemDef(id: "refuse_goblin_tooth", displayName: "Goblin tooth", category: Refuse,
      maxStack: 5, isContainer: false, containerKind: ContainerNone, notes: "Refuse"),
    ItemDef(id: "sheet_parchment", displayName: "Parchment sheet", category: Sheets,
      maxStack: 10, isContainer: false, containerKind: ContainerNone, notes: "Writing material"),
    ItemDef(id: "stone_hematite_ore", displayName: "Hematite ore", category: StoneOre,
      maxStack: 5, isContainer: false, containerKind: ContainerNone, notes: "Ore/stone"),
    ItemDef(id: "weapon_iron_axe", displayName: "Iron axe", category: Weapons,
      maxStack: 1, isContainer: false, containerKind: ContainerNone, notes: "Weapon"),
    ItemDef(id: "wood_log", displayName: "Log", category: Wood,
      maxStack: 10, isContainer: false, containerKind: ContainerNone, notes: "Raw wood")
  ]

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

  ## One representative DF item per token category (v0.47/DF2014 tokens).
  DfTokenCatalog*: seq[DfTokenDef] = @[
    DfTokenDef(token: "BAR", id: "df_bar_iron", displayName: "Iron bar",
      placement: DfItem, notes: "Metal bar"),
    DfTokenDef(token: "SMALLGEM", id: "df_smallgem_ruby", displayName: "Cut ruby",
      placement: DfItem, notes: "Small cut gem"),
    DfTokenDef(token: "BLOCKS", id: "df_blocks_granite", displayName: "Granite block",
      placement: DfItem, notes: "Building block"),
    DfTokenDef(token: "ROUGH", id: "df_rough_emerald", displayName: "Rough emerald",
      placement: DfItem, notes: "Uncut gem"),
    DfTokenDef(token: "BOULDER", id: "df_boulder_granite", displayName: "Granite boulder",
      placement: DfItem, notes: "Boulder/stone"),
    DfTokenDef(token: "WOOD", id: "df_wood_oak_log", displayName: "Oak log",
      placement: DfItem, notes: "Raw wood"),
    DfTokenDef(token: "DOOR", id: "df_door_stone", displayName: "Stone door",
      placement: DfBuilding, notes: "Door furniture"),
    DfTokenDef(token: "FLOODGATE", id: "df_floodgate_iron", displayName: "Iron floodgate",
      placement: DfBuilding, notes: "Water control gate"),
    DfTokenDef(token: "BED", id: "df_bed_wood", displayName: "Wooden bed",
      placement: DfBuilding, notes: "Sleeping furniture"),
    DfTokenDef(token: "CHAIR", id: "df_chair_stone", displayName: "Stone throne",
      placement: DfBuilding, notes: "Seating furniture"),
    DfTokenDef(token: "CHAIN", id: "df_chain_iron", displayName: "Iron chain",
      placement: DfBuilding, notes: "Restraint"),
    DfTokenDef(token: "FLASK", id: "df_flask_metal", displayName: "Metal flask",
      placement: DfItem, notes: "Liquid container"),
    DfTokenDef(token: "GOBLET", id: "df_goblet_silver", displayName: "Silver goblet",
      placement: DfItem, notes: "Drinkware"),
    DfTokenDef(token: "INSTRUMENT", id: "df_instrument_drum", displayName: "Drum",
      placement: DfItem, notes: "Musical instrument"),
    DfTokenDef(token: "TOY", id: "df_toy_boat", displayName: "Toy boat",
      placement: DfItem, notes: "Plaything"),
    DfTokenDef(token: "WINDOW", id: "df_window_glass", displayName: "Glass window",
      placement: DfBuilding, notes: "Window furniture"),
    DfTokenDef(token: "CAGE", id: "df_cage_wood", displayName: "Wooden cage",
      placement: DfItem, notes: "Creature container"),
    DfTokenDef(token: "BARREL", id: "df_barrel_wood", displayName: "Wooden barrel",
      placement: DfItem, notes: "Storage container"),
    DfTokenDef(token: "BUCKET", id: "df_bucket_wood", displayName: "Wooden bucket",
      placement: DfItem, notes: "Utility container"),
    DfTokenDef(token: "ANIMALTRAP", id: "df_animaltrap", displayName: "Animal trap",
      placement: DfBuilding, notes: "Trap furniture"),
    DfTokenDef(token: "TABLE", id: "df_table_stone", displayName: "Stone table",
      placement: DfBuilding, notes: "Dining furniture"),
    DfTokenDef(token: "COFFIN", id: "df_coffin_stone", displayName: "Stone coffin",
      placement: DfBuilding, notes: "Burial furniture"),
    DfTokenDef(token: "STATUE", id: "df_statue_stone", displayName: "Stone statue",
      placement: DfBuilding, notes: "Decorative furniture"),
    DfTokenDef(token: "CORPSE", id: "df_corpse_dwarf", displayName: "Dwarf corpse",
      placement: DfItem, notes: "Corpse"),
    DfTokenDef(token: "WEAPON", id: "df_weapon_short_sword", displayName: "Iron short sword",
      placement: DfItem, notes: "Weapon"),
    DfTokenDef(token: "ARMOR", id: "df_armor_breastplate", displayName: "Iron breastplate",
      placement: DfItem, notes: "Armor"),
    DfTokenDef(token: "SHOES", id: "df_shoes_leather", displayName: "Leather shoes",
      placement: DfItem, notes: "Footwear"),
    DfTokenDef(token: "SHIELD", id: "df_shield_wood", displayName: "Wooden shield",
      placement: DfItem, notes: "Shield"),
    DfTokenDef(token: "HELM", id: "df_helm_iron", displayName: "Iron helm",
      placement: DfItem, notes: "Helmet"),
    DfTokenDef(token: "GLOVES", id: "df_gloves_leather", displayName: "Leather gloves",
      placement: DfItem, notes: "Gloves"),
    DfTokenDef(token: "BOX", id: "df_box_wood", displayName: "Wooden chest",
      placement: DfItem, notes: "Small storage"),
    DfTokenDef(token: "BIN", id: "df_bin_wood", displayName: "Wooden bin",
      placement: DfItem, notes: "Bulk storage"),
    DfTokenDef(token: "ARMORSTAND", id: "df_armorstand_metal", displayName: "Metal armor stand",
      placement: DfBuilding, notes: "Display furniture"),
    DfTokenDef(token: "WEAPONRACK", id: "df_weaponrack_wood", displayName: "Wooden weapon rack",
      placement: DfBuilding, notes: "Display furniture"),
    DfTokenDef(token: "CABINET", id: "df_cabinet_wood", displayName: "Wooden cabinet",
      placement: DfBuilding, notes: "Storage furniture"),
    DfTokenDef(token: "FIGURINE", id: "df_figurine_stone", displayName: "Stone figurine",
      placement: DfItem, notes: "Crafted good"),
    DfTokenDef(token: "AMULET", id: "df_amulet_gold", displayName: "Gold amulet",
      placement: DfItem, notes: "Jewelry"),
    DfTokenDef(token: "SCEPTER", id: "df_scepter_silver", displayName: "Silver scepter",
      placement: DfItem, notes: "Regal item"),
    DfTokenDef(token: "AMMO", id: "df_ammo_copper_bolt", displayName: "Copper bolt",
      placement: DfItem, notes: "Ranged ammo"),
    DfTokenDef(token: "CROWN", id: "df_crown_gold", displayName: "Gold crown",
      placement: DfItem, notes: "Jewelry"),
    DfTokenDef(token: "RING", id: "df_ring_silver", displayName: "Silver ring",
      placement: DfItem, notes: "Jewelry"),
    DfTokenDef(token: "EARRING", id: "df_earring_gold", displayName: "Gold earring",
      placement: DfItem, notes: "Jewelry"),
    DfTokenDef(token: "BRACELET", id: "df_bracelet_gold", displayName: "Gold bracelet",
      placement: DfItem, notes: "Jewelry"),
    DfTokenDef(token: "GEM", id: "df_gem_diamond", displayName: "Large diamond",
      placement: DfItem, notes: "Cut gem"),
    DfTokenDef(token: "ANVIL", id: "df_anvil_iron", displayName: "Iron anvil",
      placement: DfBuilding, notes: "Workshop tool"),
    DfTokenDef(token: "CORPSEPIECE", id: "df_corpsepiece_hand", displayName: "Left hand",
      placement: DfItem, notes: "Body part"),
    DfTokenDef(token: "REMAINS", id: "df_remains_rat", displayName: "Rat remains",
      placement: DfItem, notes: "Small remains"),
    DfTokenDef(token: "MEAT", id: "df_meat_beef", displayName: "Beef",
      placement: DfItem, notes: "Butchered meat"),
    DfTokenDef(token: "FISH", id: "df_fish_trout", displayName: "Prepared trout",
      placement: DfItem, notes: "Prepared fish"),
    DfTokenDef(token: "FISH_RAW", id: "df_fish_raw_trout", displayName: "Raw trout",
      placement: DfItem, notes: "Raw fish"),
    DfTokenDef(token: "VERMIN", id: "df_vermin_rat", displayName: "Live rat",
      placement: DfItem, notes: "Vermin"),
    DfTokenDef(token: "PET", id: "df_pet_frog", displayName: "Tamed frog",
      placement: DfItem, notes: "Pet animal"),
    DfTokenDef(token: "SEEDS", id: "df_seeds_plump_helmet", displayName: "Plump helmet spawn",
      placement: DfItem, notes: "Seeds"),
    DfTokenDef(token: "PLANT", id: "df_plant_plump_helmet", displayName: "Plump helmet",
      placement: DfItem, notes: "Harvested plant"),
    DfTokenDef(token: "SKIN_TANNED", id: "df_skin_tanned_cow", displayName: "Cow leather",
      placement: DfItem, notes: "Tanned hide"),
    DfTokenDef(token: "PLANT_GROWTH", id: "df_plant_growth_apple", displayName: "Apple",
      placement: DfItem, notes: "Plant growth"),
    DfTokenDef(token: "THREAD", id: "df_thread_pig_tail", displayName: "Pig tail thread",
      placement: DfItem, notes: "Thread"),
    DfTokenDef(token: "CLOTH", id: "df_cloth_pig_tail", displayName: "Pig tail cloth",
      placement: DfItem, notes: "Cloth"),
    DfTokenDef(token: "TOTEM", id: "df_totem_skull", displayName: "Skull totem",
      placement: DfItem, notes: "Totem"),
    DfTokenDef(token: "PANTS", id: "df_pants_trousers", displayName: "Trousers",
      placement: DfItem, notes: "Legwear"),
    DfTokenDef(token: "BACKPACK", id: "df_backpack_leather", displayName: "Leather backpack",
      placement: DfItem, notes: "Container"),
    DfTokenDef(token: "QUIVER", id: "df_quiver_leather", displayName: "Leather quiver",
      placement: DfItem, notes: "Ammo container"),
    DfTokenDef(token: "CATAPULTPARTS", id: "df_catapult_parts", displayName: "Catapult parts",
      placement: DfItem, notes: "Siege parts"),
    DfTokenDef(token: "BALLISTAPARTS", id: "df_ballista_parts", displayName: "Ballista parts",
      placement: DfItem, notes: "Siege parts"),
    DfTokenDef(token: "SIEGEAMMO", id: "df_siegeammo_ballista_arrow", displayName: "Ballista arrow",
      placement: DfItem, notes: "Siege ammo"),
    DfTokenDef(token: "BALLISTAARROWHEAD", id: "df_ballista_arrowhead", displayName: "Ballista arrowhead",
      placement: DfItem, notes: "Siege ammo component"),
    DfTokenDef(token: "TRAPPARTS", id: "df_trapparts_mechanism", displayName: "Mechanism",
      placement: DfItem, notes: "Trap part"),
    DfTokenDef(token: "TRAPCOMP", id: "df_trapcomp_serrated_disc", displayName: "Large serrated disc",
      placement: DfItem, notes: "Trap component"),
    DfTokenDef(token: "DRINK", id: "df_drink_dwarven_ale", displayName: "Dwarven ale",
      placement: DfItem, notes: "Alcohol"),
    DfTokenDef(token: "POWDER_MISC", id: "df_powder_flour", displayName: "Flour",
      placement: DfItem, notes: "Powder"),
    DfTokenDef(token: "CHEESE", id: "df_cheese", displayName: "Cheese",
      placement: DfItem, notes: "Food"),
    DfTokenDef(token: "FOOD", id: "df_food_prepared_meal", displayName: "Prepared meal",
      placement: DfItem, notes: "Cooked food"),
    DfTokenDef(token: "LIQUID_MISC", id: "df_liquid_water", displayName: "Water",
      placement: DfItem, notes: "Liquid"),
    DfTokenDef(token: "COIN", id: "df_coin_gold", displayName: "Gold coin",
      placement: DfItem, notes: "Currency"),
    DfTokenDef(token: "GLOB", id: "df_glob_tallow", displayName: "Tallow",
      placement: DfItem, notes: "Fat glob"),
    DfTokenDef(token: "ROCK", id: "df_rock_small", displayName: "Small rock",
      placement: DfItem, notes: "Throwable rock"),
    DfTokenDef(token: "PIPE_SECTION", id: "df_pipe_section_glass", displayName: "Glass pipe section",
      placement: DfItem, notes: "Pipe construction item"),
    DfTokenDef(token: "HATCH_COVER", id: "df_hatch_cover_stone", displayName: "Stone hatch cover",
      placement: DfBuilding, notes: "Hatch furniture"),
    DfTokenDef(token: "GRATE", id: "df_grate_metal", displayName: "Metal grate",
      placement: DfBuilding, notes: "Grate furniture"),
    DfTokenDef(token: "QUERN", id: "df_quern_stone", displayName: "Stone quern",
      placement: DfBuilding, notes: "Mill furniture"),
    DfTokenDef(token: "MILLSTONE", id: "df_millstone_stone", displayName: "Stone millstone",
      placement: DfBuilding, notes: "Mill furniture"),
    DfTokenDef(token: "SPLINT", id: "df_splint_wood", displayName: "Wooden splint",
      placement: DfItem, notes: "Medical item"),
    DfTokenDef(token: "CRUTCH", id: "df_crutch_wood", displayName: "Wooden crutch",
      placement: DfItem, notes: "Medical item"),
    DfTokenDef(token: "TRACTION_BENCH", id: "df_traction_bench", displayName: "Traction bench",
      placement: DfBuilding, notes: "Medical furniture"),
    DfTokenDef(token: "ORTHOPEDIC_CAST", id: "df_orthopedic_cast", displayName: "Cast",
      placement: DfItem, notes: "Medical item"),
    DfTokenDef(token: "TOOL", id: "df_tool_nest_box", displayName: "Nest box",
      placement: DfItem, notes: "Tool item"),
    DfTokenDef(token: "SLAB", id: "df_slab_memorial", displayName: "Memorial slab",
      placement: DfBuilding, notes: "Commemorative slab"),
    DfTokenDef(token: "EGG", id: "df_egg_chicken", displayName: "Chicken egg",
      placement: DfItem, notes: "Egg"),
    DfTokenDef(token: "BOOK", id: "df_book", displayName: "Book",
      placement: DfItem, notes: "Written work"),
    DfTokenDef(token: "SHEET", id: "df_sheet_paper", displayName: "Paper sheet",
      placement: DfItem, notes: "Writing material"),
    DfTokenDef(token: "BRANCH", id: "df_branch_tree", displayName: "Tree branch",
      placement: DfItem, notes: "Wood branch")
  ]

let
  ## Describes what each DF token item/building is used for, with typical inputs/outputs.
  DfTokenBehaviors*: seq[DfTokenBehavior] = @[
    DfTokenBehavior(token: "BAR", inputs: @["smelted ore"], outputs: @["metal bars"],
      uses: "Base metal material for tools, weapons, and constructions."),
    DfTokenBehavior(token: "SMALLGEM", inputs: @["cut rough gem"], outputs: @["small cut gem"],
      uses: "Jewelry and trade goods."),
    DfTokenBehavior(token: "BLOCKS", inputs: @["stone or wood"], outputs: @["blocks"],
      uses: "Construction material for buildings."),
    DfTokenBehavior(token: "ROUGH", inputs: @["mined gem"], outputs: @["rough gem"],
      uses: "Cutting into finished gems."),
    DfTokenBehavior(token: "BOULDER", inputs: @["mined stone"], outputs: @["boulder"],
      uses: "Masonry and basic stoneworking."),
    DfTokenBehavior(token: "WOOD", inputs: @["felled tree"], outputs: @["log"],
      uses: "Carpentry and basic wooden items."),
    DfTokenBehavior(token: "DOOR", inputs: @["block or wood"], outputs: @["door"],
      uses: "Access control for rooms and corridors."),
    DfTokenBehavior(token: "FLOODGATE", inputs: @["block or metal"], outputs: @["floodgate"],
      uses: "Water and fluid control."),
    DfTokenBehavior(token: "BED", inputs: @["wood"], outputs: @["bed"],
      uses: "Sleeping/resting furniture."),
    DfTokenBehavior(token: "CHAIR", inputs: @["block or wood"], outputs: @["chair/throne"],
      uses: "Seating furniture."),
    DfTokenBehavior(token: "CHAIN", inputs: @["metal"], outputs: @["chain"],
      uses: "Restraints and leashing."),
    DfTokenBehavior(token: "FLASK", inputs: @["metal"], outputs: @["flask"],
      uses: "Portable liquid container."),
    DfTokenBehavior(token: "GOBLET", inputs: @["metal"], outputs: @["goblet"],
      uses: "Drinkware."),
    DfTokenBehavior(token: "INSTRUMENT", inputs: @["wood/metal"], outputs: @["instrument"],
      uses: "Music and entertainment."),
    DfTokenBehavior(token: "TOY", inputs: @["wood/cloth"], outputs: @["toy"],
      uses: "Child entertainment and trade."),
    DfTokenBehavior(token: "WINDOW", inputs: @["glass"], outputs: @["window"],
      uses: "Light/visibility while keeping barriers."),
    DfTokenBehavior(token: "CAGE", inputs: @["wood/metal"], outputs: @["cage"],
      uses: "Contain creatures and prisoners."),
    DfTokenBehavior(token: "BARREL", inputs: @["wood"], outputs: @["barrel"],
      uses: "Bulk storage for food and drink."),
    DfTokenBehavior(token: "BUCKET", inputs: @["wood/metal"], outputs: @["bucket"],
      uses: "Carry liquids and materials."),
    DfTokenBehavior(token: "ANIMALTRAP", inputs: @["wood/metal"], outputs: @["animal trap"],
      uses: "Capture small wildlife."),
    DfTokenBehavior(token: "TABLE", inputs: @["block or wood"], outputs: @["table"],
      uses: "Dining and work surface."),
    DfTokenBehavior(token: "COFFIN", inputs: @["stone or wood"], outputs: @["coffin"],
      uses: "Burial container."),
    DfTokenBehavior(token: "STATUE", inputs: @["stone/metal"], outputs: @["statue"],
      uses: "Decoration and morale."),
    DfTokenBehavior(token: "CORPSE", inputs: @["death"], outputs: @["corpse"],
      uses: "Butchery or burial."),
    DfTokenBehavior(token: "WEAPON", inputs: @["metal/wood"], outputs: @["weapon"],
      uses: "Combat equipment."),
    DfTokenBehavior(token: "ARMOR", inputs: @["metal/leather"], outputs: @["armor"],
      uses: "Damage mitigation."),
    DfTokenBehavior(token: "SHOES", inputs: @["leather/cloth"], outputs: @["shoes"],
      uses: "Foot protection."),
    DfTokenBehavior(token: "SHIELD", inputs: @["wood/metal"], outputs: @["shield"],
      uses: "Defensive equipment."),
    DfTokenBehavior(token: "HELM", inputs: @["metal/leather"], outputs: @["helm"],
      uses: "Head protection."),
    DfTokenBehavior(token: "GLOVES", inputs: @["leather/cloth"], outputs: @["gloves"],
      uses: "Hand protection."),
    DfTokenBehavior(token: "BOX", inputs: @["wood"], outputs: @["box"],
      uses: "Small storage."),
    DfTokenBehavior(token: "BIN", inputs: @["wood"], outputs: @["bin"],
      uses: "Bulk storage for finished goods."),
    DfTokenBehavior(token: "ARMORSTAND", inputs: @["wood/metal"], outputs: @["armor stand"],
      uses: "Display and storage for armor."),
    DfTokenBehavior(token: "WEAPONRACK", inputs: @["wood/metal"], outputs: @["weapon rack"],
      uses: "Display and storage for weapons."),
    DfTokenBehavior(token: "CABINET", inputs: @["wood"], outputs: @["cabinet"],
      uses: "Storage furniture."),
    DfTokenBehavior(token: "FIGURINE", inputs: @["stone/metal"], outputs: @["figurine"],
      uses: "Craft/trade item."),
    DfTokenBehavior(token: "AMULET", inputs: @["metal + gem"], outputs: @["amulet"],
      uses: "Jewelry and status item."),
    DfTokenBehavior(token: "SCEPTER", inputs: @["metal"], outputs: @["scepter"],
      uses: "Noble regalia."),
    DfTokenBehavior(token: "AMMO", inputs: @["metal/wood"], outputs: @["ammo"],
      uses: "Ranged ammunition."),
    DfTokenBehavior(token: "CROWN", inputs: @["metal + gem"], outputs: @["crown"],
      uses: "Jewelry and status item."),
    DfTokenBehavior(token: "RING", inputs: @["metal"], outputs: @["ring"],
      uses: "Jewelry."),
    DfTokenBehavior(token: "EARRING", inputs: @["metal"], outputs: @["earring"],
      uses: "Jewelry."),
    DfTokenBehavior(token: "BRACELET", inputs: @["metal"], outputs: @["bracelet"],
      uses: "Jewelry."),
    DfTokenBehavior(token: "GEM", inputs: @["gem cutting"], outputs: @["large cut gem"],
      uses: "Jewelry and trade goods."),
    DfTokenBehavior(token: "ANVIL", inputs: @["metal bars"], outputs: @["anvil"],
      uses: "Metalworking tool."),
    DfTokenBehavior(token: "CORPSEPIECE", inputs: @["butchery"], outputs: @["body part"],
      uses: "Refuse or crafting material."),
    DfTokenBehavior(token: "REMAINS", inputs: @["small corpse"], outputs: @["remains"],
      uses: "Refuse or bone materials."),
    DfTokenBehavior(token: "MEAT", inputs: @["butchery"], outputs: @["meat"],
      uses: "Food ingredient."),
    DfTokenBehavior(token: "FISH", inputs: @["fish processing"], outputs: @["prepared fish"],
      uses: "Food ingredient."),
    DfTokenBehavior(token: "FISH_RAW", inputs: @["fishing"], outputs: @["raw fish"],
      uses: "Raw food."),
    DfTokenBehavior(token: "VERMIN", inputs: @["wild pests"], outputs: @["vermin"],
      uses: "Nuisance, sometimes food."),
    DfTokenBehavior(token: "PET", inputs: @["taming"], outputs: @["pet"],
      uses: "Companion animal."),
    DfTokenBehavior(token: "SEEDS", inputs: @["plants"], outputs: @["seeds"],
      uses: "Farming inputs."),
    DfTokenBehavior(token: "PLANT", inputs: @["harvest"], outputs: @["plant"],
      uses: "Food and brewing ingredient."),
    DfTokenBehavior(token: "SKIN_TANNED", inputs: @["hide + tanning"], outputs: @["leather"],
      uses: "Leatherworking input."),
    DfTokenBehavior(token: "PLANT_GROWTH", inputs: @["harvest"], outputs: @["growth"],
      uses: "Food/ingredient."),
    DfTokenBehavior(token: "THREAD", inputs: @["plant fiber"], outputs: @["thread"],
      uses: "Weaving cloth."),
    DfTokenBehavior(token: "CLOTH", inputs: @["thread"], outputs: @["cloth"],
      uses: "Clothing and bags."),
    DfTokenBehavior(token: "TOTEM", inputs: @["bones"], outputs: @["totem"],
      uses: "Craft/trade item."),
    DfTokenBehavior(token: "PANTS", inputs: @["cloth/leather"], outputs: @["pants"],
      uses: "Legwear."),
    DfTokenBehavior(token: "BACKPACK", inputs: @["cloth/leather"], outputs: @["backpack"],
      uses: "Personal storage."),
    DfTokenBehavior(token: "QUIVER", inputs: @["leather"], outputs: @["quiver"],
      uses: "Ammo container."),
    DfTokenBehavior(token: "CATAPULTPARTS", inputs: @["wood/metal"], outputs: @["catapult parts"],
      uses: "Siege building component."),
    DfTokenBehavior(token: "BALLISTAPARTS", inputs: @["wood/metal"], outputs: @["ballista parts"],
      uses: "Siege building component."),
    DfTokenBehavior(token: "SIEGEAMMO", inputs: @["wood/metal"], outputs: @["siege ammo"],
      uses: "Catapult/ballista ammunition."),
    DfTokenBehavior(token: "BALLISTAARROWHEAD", inputs: @["metal"], outputs: @["arrowhead"],
      uses: "Ballista ammo component."),
    DfTokenBehavior(token: "TRAPPARTS", inputs: @["stone/metal"], outputs: @["mechanism"],
      uses: "Trap and door mechanisms."),
    DfTokenBehavior(token: "TRAPCOMP", inputs: @["metal"], outputs: @["trap component"],
      uses: "Weaponized trap parts."),
    DfTokenBehavior(token: "DRINK", inputs: @["brewing"], outputs: @["drink"],
      uses: "Hydration and morale."),
    DfTokenBehavior(token: "POWDER_MISC", inputs: @["milling"], outputs: @["powder"],
      uses: "Cooking ingredient."),
    DfTokenBehavior(token: "CHEESE", inputs: @["milk"], outputs: @["cheese"],
      uses: "Food ingredient."),
    DfTokenBehavior(token: "FOOD", inputs: @["prepared ingredients"], outputs: @["meal"],
      uses: "Cooked food."),
    DfTokenBehavior(token: "LIQUID_MISC", inputs: @["liquid source"], outputs: @["liquid"],
      uses: "General liquid container."),
    DfTokenBehavior(token: "COIN", inputs: @["metal"], outputs: @["coins"],
      uses: "Currency and trade."),
    DfTokenBehavior(token: "GLOB", inputs: @["fat/tallow"], outputs: @["glob"],
      uses: "Cooking and fuel material."),
    DfTokenBehavior(token: "ROCK", inputs: @["stone"], outputs: @["small rock"],
      uses: "Throwing and minor construction."),
    DfTokenBehavior(token: "PIPE_SECTION", inputs: @["glass/metal"], outputs: @["pipe section"],
      uses: "Plumbing or construction."),
    DfTokenBehavior(token: "HATCH_COVER", inputs: @["stone/wood"], outputs: @["hatch cover"],
      uses: "Floor access control."),
    DfTokenBehavior(token: "GRATE", inputs: @["metal"], outputs: @["grate"],
      uses: "Ventilation and drain cover."),
    DfTokenBehavior(token: "QUERN", inputs: @["stone"], outputs: @["quern"],
      uses: "Manual milling."),
    DfTokenBehavior(token: "MILLSTONE", inputs: @["stone"], outputs: @["millstone"],
      uses: "Powered milling."),
    DfTokenBehavior(token: "SPLINT", inputs: @["wood"], outputs: @["splint"],
      uses: "Medical support."),
    DfTokenBehavior(token: "CRUTCH", inputs: @["wood"], outputs: @["crutch"],
      uses: "Medical support."),
    DfTokenBehavior(token: "TRACTION_BENCH", inputs: @["wood/metal"], outputs: @["traction bench"],
      uses: "Medical treatment station."),
    DfTokenBehavior(token: "ORTHOPEDIC_CAST", inputs: @["plaster/cloth"], outputs: @["cast"],
      uses: "Medical treatment item."),
    DfTokenBehavior(token: "TOOL", inputs: @["varies"], outputs: @["tool"],
      uses: "Utility item."),
    DfTokenBehavior(token: "SLAB", inputs: @["stone"], outputs: @["slab"],
      uses: "Memorial marker."),
    DfTokenBehavior(token: "EGG", inputs: @["animals"], outputs: @["egg"],
      uses: "Food ingredient."),
    DfTokenBehavior(token: "BOOK", inputs: @["paper + writing"], outputs: @["book"],
      uses: "Knowledge and records."),
    DfTokenBehavior(token: "SHEET", inputs: @["paper/parchment"], outputs: @["sheet"],
      uses: "Writing material."),
    DfTokenBehavior(token: "BRANCH", inputs: @["tree"], outputs: @["branch"],
      uses: "Light woodworking material.")
  ]

  GameStructureCatalog*: seq[GameStructureDef] = @[
    GameStructureDef(id: "road", displayName: "Road",
      buildCost: @["wood x1"],
      uses: "Movement booster: entering pushes the agent two tiles forward."),
    GameStructureDef(id: "watchtower", displayName: "Watch Tower",
      buildCost: @["wood x2"],
      uses: "Outpost for builders; extends territory reach."),
    GameStructureDef(id: "bed", displayName: "Bed",
      buildCost: @["wood"], uses: "Resting furniture."),
    GameStructureDef(id: "chair", displayName: "Chair",
      buildCost: @["wood/stone"], uses: "Seating furniture."),
    GameStructureDef(id: "table", displayName: "Table",
      buildCost: @["wood/stone"], uses: "Dining/work surface."),
    GameStructureDef(id: "statue", displayName: "Statue",
      buildCost: @["stone/metal"], uses: "Decorative/morale structure.")
  ]
