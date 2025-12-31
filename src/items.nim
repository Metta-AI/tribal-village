## Item catalog and container definitions for future stockpile/storage work.
## This keeps the "what exists" separate from game logic.

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
