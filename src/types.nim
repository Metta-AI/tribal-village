## types.nim - Forward type declarations for tribal-village
##
## This module provides type definitions that multiple modules need access to,
## breaking circular dependency chains. All fundamental types should be defined here.
##
## Import order for modules using these types:
##   1. types (this file) - for type definitions
##   2. Other modules that use these types

import std/[tables, sets], vmath, chroma
import terrain, items, common
export terrain, items, common

# Re-export key types from dependencies
export tables, vmath, chroma

const
  # Map Layout
  MapLayoutRoomsX* = 1
  MapLayoutRoomsY* = 1
  MapBorder* = 4
  MapRoomWidth* = 230  # ~20% smaller than 288
  MapRoomHeight* = 144  # ~20% smaller than 180
  MapRoomBorder* = 0

  AgentMaxHp* = 5

  # World Objects
  # Eight bases with 125 agents each -> 1000 agents total.
  MapRoomObjectsHouses* = 8
  MapAgentsPerVillage* = 125
  MapRoomObjectsAgents* = MapRoomObjectsHouses * MapAgentsPerVillage  # Agent slots across all villages
  MapRoomObjectsMagmaPools* = 44
  MapRoomObjectsMagmaClusters* = 28
  MapRoomObjectsStoneClusters* = 48
  MapRoomObjectsStoneClusterCount* = 28
  MapRoomObjectsGoldClusters* = 48
  MapRoomObjectsGoldClusterCount* = 28
  MapRoomObjectsWalls* = 30
  MapRoomObjectsCows* = 24
  MapRoomObjectsBears* = 6
  MapRoomObjectsWolves* = 12
  MapRoomObjectsRelics* = 12

  # Agent Parameters
  MapObjectAgentMaxInventory* = 5

  # Building Parameters
  MapObjectAltarInitialHearts* = 5
  MapObjectAltarCooldown* = 0
  MapObjectAltarRespawnCost* = 1
  MapObjectAltarAutoSpawnThreshold* = 5
  BarrelCapacity* = 50
  ResourceNodeInitial* = 25
  DoorMaxHearts* = 5
  WallMaxHp* = 10
  OutpostMaxHp* = 8
  GuardTowerMaxHp* = 14
  TownCenterMaxHp* = 20
  CastleMaxHp* = 30
  GuardTowerAttackDamage* = 2
  CastleAttackDamage* = 3
  GuardTowerRange* = 4
  CastleRange* = 6
  SiegeStructureMultiplier* = 3
  BuildIndexGuardTower* = 23
  BuildIndexMangonelWorkshop* = 24
  BuildIndexWall* = 14
  BuildIndexRoad* = 15
  BuildIndexDoor* = 19
  RoadWoodCost* = 1
  OutpostWoodCost* = 1
  CowMilkCooldown* = 25
  BearMaxHp* = 6
  BearAttackDamage* = 2
  BearAggroRadius* = 6
  WolfMaxHp* = 3
  WolfAttackDamage* = 1
  WolfPackMinSize* = 3
  WolfPackMaxSize* = 5
  WolfPackAggroRadius* = 7
  WolfPackCohesionRadius* = 3
  ResourceCarryCapacity* = 5
  MineDepositAmount* = 100
  TownCenterPopCap* = 0
  HousePopCap* = 2
  VillagerAttackDamage* = 1
  ManAtArmsAttackDamage* = 2
  ArcherAttackDamage* = 1
  ScoutAttackDamage* = 1
  KnightAttackDamage* = 2
  MonkAttackDamage* = 0
  BatteringRamAttackDamage* = 2
  MangonelAttackDamage* = 2
  VillagerMaxHp* = AgentMaxHp
  ManAtArmsMaxHp* = 7
  ArcherMaxHp* = 4
  ScoutMaxHp* = 6
  KnightMaxHp* = 8
  MonkMaxHp* = 4
  BatteringRamMaxHp* = 18
  MangonelMaxHp* = 12
  ArcherBaseRange* = 3
  MangonelBaseRange* = 3
  MangonelAoELength* = 4

  # Gameplay
  MinTintEpsilon* = 5

  # Observation System
  ObservationWidth* = 11
  ObservationHeight* = 11

  # Action tint observation codes (TintLayer values)
  ActionTintNone* = 0'u8
  ActionTintAttackVillager* = 1'u8
  ActionTintAttackManAtArms* = 2'u8
  ActionTintAttackArcher* = 3'u8
  ActionTintAttackScout* = 4'u8
  ActionTintAttackKnight* = 5'u8
  ActionTintAttackMonk* = 6'u8
  ActionTintAttackBatteringRam* = 7'u8
  ActionTintAttackMangonel* = 8'u8
  ActionTintAttackBoat* = 9'u8
  ActionTintAttackTower* = 10'u8
  ActionTintAttackCastle* = 11'u8
  ActionTintAttackBonus* = 12'u8
  ActionTintShield* = 20'u8
  ActionTintHealMonk* = 30'u8
  ActionTintHealBread* = 31'u8
  ActionTintMixed* = 200'u8

  # Computed Values
  MapAgents* = MapRoomObjectsAgents * MapLayoutRoomsX * MapLayoutRoomsY
  MapWidth* = MapLayoutRoomsX * (MapRoomWidth + MapRoomBorder) + MapBorder
  MapHeight* = MapLayoutRoomsY * (MapRoomHeight + MapRoomBorder) + MapBorder

  # Compile-time optimization constants
  ObservationRadius* = ObservationWidth div 2  # 5 - computed once
  MapAgentsPerVillageFloat* = MapAgentsPerVillage.float32  # Avoid runtime conversion

{.push inline.}
proc getTeamId*(agentId: int): int =
  ## Inline team ID calculation - frequently used
  agentId div MapAgentsPerVillage


template isValidPos*(pos: IVec2): bool =
  ## Inline bounds checking template - very frequently used
  pos.x >= 0 and pos.x < MapWidth and pos.y >= 0 and pos.y < MapHeight

const
  MaxTintAccum* = 50_000_000'i32

template safeTintAdd*(tintMod: var int32, delta: int): void =
  ## Safe tint accumulation with overflow protection
  tintMod = max(-MaxTintAccum, min(MaxTintAccum,
    tintMod + max(-MaxTintAccum, min(MaxTintAccum, delta.int32))
  ))
{.pop.}

type
  ObservationName* = enum
    TerrainEmptyLayer = 0
    TerrainWaterLayer
    TerrainBridgeLayer
    TerrainFertileLayer
    TerrainRoadLayer
    TerrainGrassLayer
    TerrainDuneLayer
    TerrainSandLayer
    TerrainSnowLayer
    TerrainRampUpNLayer
    TerrainRampUpSLayer
    TerrainRampUpWLayer
    TerrainRampUpELayer
    TerrainRampDownNLayer
    TerrainRampDownSLayer
    TerrainRampDownWLayer
    TerrainRampDownELayer

    ThingAgentLayer
    ThingWallLayer
    ThingDoorLayer
    ThingTreeLayer
    ThingWheatLayer
    ThingFishLayer
    ThingRelicLayer
    ThingStoneLayer
    ThingGoldLayer
    ThingBushLayer
    ThingCactusLayer
    ThingStalagmiteLayer
    ThingMagmaLayer
    ThingAltarLayer
    ThingSpawnerLayer
    ThingTumorLayer
    ThingCowLayer
    ThingBearLayer
    ThingWolfLayer
    ThingCorpseLayer
    ThingSkeletonLayer
    ThingClayOvenLayer
    ThingWeavingLoomLayer
    ThingOutpostLayer
    ThingGuardTowerLayer
    ThingBarrelLayer
    ThingMillLayer
    ThingGranaryLayer
    ThingLumberCampLayer
    ThingQuarryLayer
    ThingMiningCampLayer
    ThingStumpLayer
    ThingLanternLayer
    ThingTownCenterLayer
    ThingHouseLayer
    ThingBarracksLayer
    ThingArcheryRangeLayer
    ThingStableLayer
    ThingSiegeWorkshopLayer
    ThingMangonelWorkshopLayer
    ThingBlacksmithLayer
    ThingMarketLayer
    ThingDockLayer
    ThingMonasteryLayer
    ThingUniversityLayer
    ThingCastleLayer
    ThingStubbleLayer
    ThingCliffEdgeNLayer
    ThingCliffEdgeELayer
    ThingCliffEdgeSLayer
    ThingCliffEdgeWLayer
    ThingCliffCornerInNELayer
    ThingCliffCornerInSELayer
    ThingCliffCornerInSWLayer
    ThingCliffCornerInNWLayer
    ThingCliffCornerOutNELayer
    ThingCliffCornerOutSELayer
    ThingCliffCornerOutSWLayer
    ThingCliffCornerOutNWLayer

    TeamLayer                 # Team id + 1, 0 = none/neutral
    AgentOrientationLayer     # Orientation enum + 1, 0 = none
    AgentUnitClassLayer       # Unit class enum + 1, 0 = none
    TintLayer                 # Action/combat tint codes
    ObscuredLayer             # 1 when target tile is above observer elevation

const
  ## Legacy layer aliases used by existing update calls. These no longer map to
  ## distinct observation channels, but keep the incremental update sites intact.
  LegacyObsLayer* = ThingAgentLayer
  AgentLayer* = ThingAgentLayer
  WallLayer* = ThingWallLayer
  MagmaLayer* = ThingMagmaLayer
  altarLayer* = ThingAltarLayer
  altarHeartsLayer* = ThingAltarLayer
  CliffLayer* = ThingCliffEdgeNLayer
  AgentInventoryGoldLayer* = LegacyObsLayer
  AgentInventoryStoneLayer* = LegacyObsLayer
  AgentInventoryBarLayer* = LegacyObsLayer
  AgentInventoryWaterLayer* = LegacyObsLayer
  AgentInventoryWheatLayer* = LegacyObsLayer
  AgentInventoryWoodLayer* = LegacyObsLayer
  AgentInventorySpearLayer* = LegacyObsLayer
  AgentInventoryLanternLayer* = LegacyObsLayer
  AgentInventoryArmorLayer* = LegacyObsLayer
  AgentInventoryBreadLayer* = LegacyObsLayer
  AgentInventoryMeatLayer* = LegacyObsLayer
  AgentInventoryFishLayer* = LegacyObsLayer
  AgentInventoryPlantLayer* = LegacyObsLayer

type
  AgentUnitClass* = enum
    UnitVillager
    UnitManAtArms
    UnitArcher
    UnitScout
    UnitKnight
    UnitMonk
    UnitBatteringRam
    UnitMangonel
    UnitBoat

  ThingKind* = enum
    Agent
    Wall
    Door
    Tree
    Wheat
    Fish
    Relic
    Stone
    Gold
    Bush
    Cactus
    Stalagmite
    Magma  # Smelts gold into bars
    Altar
    Spawner
    Tumor
    Cow
    Bear
    Wolf
    Corpse
    Skeleton
    ClayOven
    WeavingLoom
    Outpost
    GuardTower
    Barrel
    Mill
    Granary
    LumberCamp
    Quarry
    MiningCamp
    Stump
    Lantern  # Lanterns that spread team colors
    TownCenter
    House
    Barracks
    ArcheryRange
    Stable
    SiegeWorkshop
    MangonelWorkshop
    Blacksmith
    Market
    Dock
    Monastery
    University
    Castle
    Stubble  # Harvested wheat residue
    CliffEdgeN
    CliffEdgeE
    CliffEdgeS
    CliffEdgeW
    CliffCornerInNE
    CliffCornerInSE
    CliffCornerInSW
    CliffCornerInNW
    CliffCornerOutNE
    CliffCornerOutSE
    CliffCornerOutSW
    CliffCornerOutNW

const
  TerrainLayerStart* = ord(TerrainEmptyLayer)
  TerrainLayerCount* = ord(TerrainType.high) + 1
  ThingLayerStart* = ord(ThingAgentLayer)
  ThingLayerCount* = ord(ThingKind.high) + 1
  ObservationLayers* = ord(ObservationName.high) + 1

type
  Thing* = ref object
    kind*: ThingKind
    pos*: IVec2
    id*: int
    layer*: int
    cooldown*: int
    frozen*: int
    thingsIndex*: int
    kindListIndex*: int

    # Agent:
    agentId*: int
    orientation*: Orientation
    inventory*: Inventory
    barrelCapacity*: int
    reward*: float32
    hp*: int
    maxHp*: int
    attackDamage*: int
    unitClass*: AgentUnitClass
    embarkedUnitClass*: AgentUnitClass
    teamIdOverride*: int
    homeAltar*: IVec2      # Position of agent's home altar for respawning
    herdId*: int               # Cow herd grouping id
    packId*: int               # Wolf pack grouping id
    # Tumor:
    homeSpawner*: IVec2     # Position of tumor's home spawner
    hasClaimedTerritory*: bool  # Whether this tumor has already branched and is now inert
    turnsAlive*: int            # Number of turns this tumor has been alive

    # Lantern:
    teamId*: int               # Which team this lantern belongs to (for color spreading)
    lanternHealthy*: bool      # Whether lantern is active (not destroyed by tumor)

    # Spawner: (no longer needs altar targeting for new creep spread behavior)

  Stats* = ref object
    # Agent Stats - simplified actions:
    actionInvalid*: int
    actionNoop*: int     # Action 0: NOOP
    actionMove*: int     # Action 1: MOVE
    actionAttack*: int   # Action 2: ATTACK
    actionUse*: int      # Action 3: USE (terrain/buildings)
    actionSwap*: int     # Action 4: SWAP
    actionPlant*: int    # Action 6: PLANT lantern
    actionPut*: int      # Action 5: GIVE to teammate
    actionBuild*: int    # Action 8: BUILD
    actionPlantResource*: int  # Action 7: Plant wheat/tree onto fertile tile
    actionOrient*: int   # Action 9: ORIENT

  TileColor* = object
    r*, g*, b*: float32      # RGB color components
    intensity*: float32      # Overall intensity/brightness modifier

  # Tint modification layers for efficient batch updates
  TintModification* = object
    r*, g*, b*: int32       # Accumulated color contributions (scaled)

  # Track active tiles for sparse processing
  ActiveTiles* = object
    positions*: seq[IVec2]  # Linear list of active tiles
    flags*: array[MapWidth, array[MapHeight, bool]]  # Dedup mask per tile

  # Action tint overlay (short-lived highlights for combat/effects)
  ActionTintCountdown* = array[MapWidth, array[MapHeight, int8]]
  ActionTintColor* = array[MapWidth, array[MapHeight, TileColor]]
  ActionTintFlags* = array[MapWidth, array[MapHeight, bool]]
  ActionTintCode* = array[MapWidth, array[MapHeight, uint8]]

const
  TeamOwnedKinds* = {
    Agent,
    Door,
    Lantern,
    Altar,
    TownCenter,
    House,
    Barracks,
    ArcheryRange,
    Stable,
    SiegeWorkshop,
    MangonelWorkshop,
    Blacksmith,
    Market,
    Dock,
    Monastery,
    University,
    Castle,
    Outpost,
    GuardTower,
    ClayOven,
    WeavingLoom,
    Mill,
    Granary,
    LumberCamp,
    Quarry,
    MiningCamp
  }

const
  CliffKinds* = {
    CliffEdgeN,
    CliffEdgeE,
    CliffEdgeS,
    CliffEdgeW,
    CliffCornerInNE,
    CliffCornerInSE,
    CliffCornerInSW,
    CliffCornerInNW,
    CliffCornerOutNE,
    CliffCornerOutSE,
    CliffCornerOutSW,
    CliffCornerOutNW
  }

template isCliffKind*(kind: ThingKind): bool =
  kind in CliffKinds

proc getTeamId*(agent: Thing): int =
  ## Team ID lookup that respects conversions.
  if agent.teamIdOverride >= 0:
    return agent.teamIdOverride
  getTeamId(agent.agentId)

proc hasPlantInputs*(agent: Thing): bool =
  agent.inventoryWheat > 0 or agent.inventoryWood > 0

const
  BaseTileColorDefault* = TileColor(r: 0.7, g: 0.65, b: 0.6, intensity: 1.0)
  BiomeColorForest* = TileColor(r: 0.45, g: 0.60, b: 0.40, intensity: 1.0)
  BiomeColorDesert* = TileColor(r: 0.98, g: 0.90, b: 0.25, intensity: 1.05)
  BiomeColorCaves* = TileColor(r: 0.45, g: 0.50, b: 0.58, intensity: 0.95)
  BiomeColorCity* = TileColor(r: 0.62, g: 0.62, b: 0.66, intensity: 1.0)
  BiomeColorPlains* = TileColor(r: 0.55, g: 0.70, b: 0.50, intensity: 1.0)
  BiomeColorSwamp* = TileColor(r: 0.32, g: 0.48, b: 0.38, intensity: 0.95)
  BiomeColorDungeon* = TileColor(r: 0.40, g: 0.36, b: 0.48, intensity: 0.9)
  BiomeColorSnow* = TileColor(r: 0.93, g: 0.95, b: 0.98, intensity: 1.0)
  BiomeEdgeBlendRadius* = 6
  BiomeBlendPasses* = 2
  BiomeBlendNeighborWeight* = 0.18'f32
  # Tiles at peak clippy tint (fully saturated creep hue) count as frozen.
  # Single source of truth for the clippy/creep tint; aligned to clamp limits so tiles can actually reach it.
  ClippyTint* = TileColor(r: 0.30'f32, g: 0.30'f32, b: 1.20'f32, intensity: 0.80'f32)
  ClippyTintTolerance* = 0.06'f32

type
  # Configuration structure for environment - ONLY runtime parameters
  # Structural constants (map size, agent count, observation dimensions) remain compile-time constants
  EnvironmentConfig* = object
    # Core game parameters
    maxSteps*: int

    # Combat configuration
    tumorSpawnRate*: float

    # Reward configuration
    heartReward*: float
    oreReward*: float # Gold mining reward
    barReward*: float
    woodReward*: float
    waterReward*: float
    wheatReward*: float
    spearReward*: float
    armorReward*: float
    foodReward*: float
    clothReward*: float
    tumorKillReward*: float
    survivalPenalty*: float
    deathPenalty*: float

proc defaultEnvironmentConfig*(): EnvironmentConfig =
  ## Create default environment configuration
  EnvironmentConfig(
    # Core game parameters
    maxSteps: 10000,

    # Combat configuration
    tumorSpawnRate: 0.1,

    # Reward configuration (only arena_basic_easy_shaped rewards active)
    heartReward: 1.0,      # Arena: heart reward
    oreReward: 0.1,        # Arena: gold mining reward
    barReward: 0.8,        # Arena: bar smelting reward
    woodReward: 0.0,       # Disabled - not in arena
    waterReward: 0.0,      # Disabled - not in arena
    wheatReward: 0.0,      # Disabled - not in arena
    spearReward: 0.0,      # Disabled - not in arena
    armorReward: 0.0,      # Disabled - not in arena
    foodReward: 0.0,       # Disabled - not in arena
    clothReward: 0.0,      # Disabled - not in arena
    tumorKillReward: 0.0,  # Disabled - not in arena
    survivalPenalty: -0.01,
    deathPenalty: -5.0
  )

type
  TerritoryScore* = object
    teamTiles*: array[MapRoomObjectsHouses, int]
    clippyTiles*: int
    neutralTiles*: int
    scoredTiles*: int

  TeamStockpile* = object
    counts*: array[StockpileResource, int]

  ElevationGrid* = array[MapWidth, array[MapHeight, int8]]

  Environment* = ref object
    currentStep*: int
    mapGeneration*: int  # Bumps each time the map is rebuilt (for render caches)
    config*: EnvironmentConfig  # Configuration for this environment
    shouldReset*: bool  # Track if environment needs reset
    observationsInitialized*: bool  # Track whether observation tensors are populated
    things*: seq[Thing]
    agents*: seq[Thing]
    grid*: array[MapWidth, array[MapHeight, Thing]]          # Blocking things
    overlayGrid*: array[MapWidth, array[MapHeight, Thing]]   # Non-blocking/background things
    elevation*: ElevationGrid
    teamStockpiles*: array[MapRoomObjectsHouses, TeamStockpile]
    terrain*: TerrainGrid
    biomes*: BiomeGrid
    baseTintColors*: array[MapWidth, array[MapHeight, TileColor]]  # Basemost biome tint layer (static)
    computedTintColors*: array[MapWidth, array[MapHeight, TileColor]]  # Dynamic tint overlay (lanterns/tumors)
    tintLocked*: array[MapWidth, array[MapHeight, bool]]  # Tiles that ignore dynamic tint overlays
    tintMods*: array[MapWidth, array[MapHeight, TintModification]]  # Unified tint modifications
    tintStrength*: array[MapWidth, array[MapHeight, int32]]  # Tint strength accumulation
    activeTiles*: ActiveTiles  # Sparse list of tiles to process
    tumorTintMods*: array[MapWidth, array[MapHeight, TintModification]]  # Persistent tumor tint contributions
    tumorStrength*: array[MapWidth, array[MapHeight, int32]]  # Tumor tint strength accumulation
    tumorActiveTiles*: ActiveTiles  # Sparse list of tiles touched by tumors
    actionTintCountdown*: ActionTintCountdown  # Short-lived combat/heal highlights
    actionTintColor*: ActionTintColor
    actionTintFlags*: ActionTintFlags
    actionTintCode*: ActionTintCode
    actionTintPositions*: seq[IVec2]
    thingsByKind*: array[ThingKind, seq[Thing]]
    cowHerdCounts*: seq[int]
    cowHerdSumX*: seq[int]
    cowHerdSumY*: seq[int]
    cowHerdDrift*: seq[IVec2]
    cowHerdTargets*: seq[IVec2]
    wolfPackCounts*: seq[int]
    wolfPackSumX*: seq[int]
    wolfPackSumY*: seq[int]
    wolfPackDrift*: seq[IVec2]
    wolfPackTargets*: seq[IVec2]
    shieldCountdown*: array[MapAgents, int8]  # shield active timer per agent
    territoryScore*: TerritoryScore
    territoryScored*: bool
    observations*: array[
      MapAgents,
      array[ObservationLayers,
        array[ObservationWidth, array[ObservationHeight, uint8]]
      ]
    ]
    terminated*: array[MapAgents, float32]
    truncated*: array[MapAgents, float32]
    stats*: seq[Stats]
    # Color management
    agentColors*: seq[Color]           ## Per-agent colors for rendering
    teamColors*: seq[Color]            ## Per-team colors for rendering
    altarColors*: Table[IVec2, Color]  ## Altar position to color mapping

# Global environment instance
var env*: Environment

# Selection state (for UI)
var selection*: Thing = nil
var selectedPos*: IVec2 = ivec2(-1, -1)

# Helper function for checking if agent is alive
proc isAgentAlive*(env: Environment, agent: Thing): bool =
  if agent.isNil:
    return false
  if env.terminated[agent.agentId] != 0.0:
    return false
  if not isValidPos(agent.pos):
    return false
  return env.grid[agent.pos.x][agent.pos.y] == agent
