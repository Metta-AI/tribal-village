## types.nim - Forward type declarations for tribal-village
##
## This module provides type definitions that multiple modules need access to,
## breaking circular dependency chains. All fundamental types should be defined here.
##
## Import order for modules using these types:
##   1. types (this file) - for type definitions
##   2. Other modules that use these types

import std/[tables, sets], vmath, chroma
import terrain, items, common, constants
export terrain, items, common, constants

# Re-export key types from dependencies
export tables, vmath, chroma

const
  # Map Layout
  MapLayoutRoomsX* = 1
  MapLayoutRoomsY* = 1
  MapBorder* = 1
  MapRoomWidth* = 305  # ~6% larger than 288
  MapRoomHeight* = 191  # ~6% larger than 180
  MapRoomBorder* = 0

  # World Objects
  # Eight teams with 125 agents each -> 1000 agents total.
  MapRoomObjectsTeams* = 8
  GoblinTeamId* = MapRoomObjectsTeams
  MapAgentsPerTeam* = 125
  MapRoomObjectsGoblinAgents* = 6
  MapRoomObjectsAgents* = MapRoomObjectsTeams * MapAgentsPerTeam + MapRoomObjectsGoblinAgents
    ## Agent slots across all teams plus goblins
  MapRoomObjectsMagmaPools* = 72
  MapRoomObjectsMagmaClusters* = 36
  MapRoomObjectsStoneClusters* = 48
  MapRoomObjectsStoneClusterCount* = 28
  MapRoomObjectsGoldClusters* = 48
  MapRoomObjectsGoldClusterCount* = 28
  MapRoomObjectsWalls* = 30
  MapRoomObjectsCows* = 24
  MapRoomObjectsBears* = 6
  MapRoomObjectsWolves* = 12
  MapRoomObjectsRelics* = 18
  MapRoomObjectsGoblinHuts* = 3
  MapRoomObjectsGoblinTotems* = 2

  # Agent Parameters
  MapObjectAgentMaxInventory* = 5

  # Building Parameters
  MapObjectAltarInitialHearts* = 5
  MapObjectAltarCooldown* = 0
  MapObjectAltarRespawnCost* = 0
  MapObjectAltarAutoSpawnThreshold* = 5
  BuildIndexGuardTower* = 23
  BuildIndexMangonelWorkshop* = 24
  BuildIndexWall* = 14
  BuildIndexRoad* = 15
  BuildIndexDoor* = 19

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
  ActionTintAttackTrebuchet* = 9'u8
  ActionTintAttackBoat* = 10'u8
  ActionTintAttackTower* = 11'u8
  ActionTintAttackCastle* = 12'u8
  ActionTintAttackBonus* = 13'u8
  ActionTintBonusArcher* = 14'u8     # Archer counter bonus (vs infantry)
  ActionTintBonusInfantry* = 15'u8   # Infantry counter bonus (vs cavalry)
  ActionTintBonusScout* = 16'u8      # Scout counter bonus (vs archers)
  ActionTintBonusKnight* = 17'u8     # Knight counter bonus (vs archers)
  ActionTintBonusBatteringRam* = 18'u8  # Battering ram siege bonus (vs structures)
  ActionTintBonusMangonel* = 19'u8   # Mangonel siege bonus (vs structures)
  ActionTintBonusTrebuchet* = 20'u8  # Trebuchet siege bonus (vs structures)
  ActionTintShield* = 21'u8
  ActionTintHealMonk* = 30'u8
  ActionTintHealBread* = 31'u8
  ActionTintMixed* = 200'u8
  # Castle unique unit attack tints
  ActionTintAttackSamurai* = 40'u8
  ActionTintAttackLongbowman* = 41'u8
  ActionTintAttackCataphract* = 42'u8
  ActionTintAttackWoadRaider* = 43'u8
  ActionTintAttackTeutonicKnight* = 44'u8
  ActionTintAttackHuskarl* = 45'u8
  ActionTintAttackMameluke* = 46'u8
  ActionTintAttackJanissary* = 47'u8
  ActionTintAttackKing* = 48'u8
  # Unit upgrade tier attack tints
  ActionTintAttackLongSwordsman* = 49'u8
  ActionTintAttackChampion* = 50'u8
  ActionTintAttackLightCavalry* = 51'u8
  ActionTintAttackHussar* = 52'u8
  ActionTintAttackCrossbowman* = 53'u8
  ActionTintAttackArbalester* = 54'u8
  ActionTintDeath* = 60'u8            # Death animation tint at kill location

  # Computed Values
  MapAgents* = MapRoomObjectsAgents * MapLayoutRoomsX * MapLayoutRoomsY
  MapWidth* = MapLayoutRoomsX * (MapRoomWidth + MapRoomBorder) + MapBorder
  MapHeight* = MapLayoutRoomsY * (MapRoomHeight + MapRoomBorder) + MapBorder

  # Compile-time optimization constants
  ObservationRadius* = ObservationWidth div 2  # 5 - computed once

type
  ## Team bitmask for O(1) team membership checks
  ## Each team (0-7) is represented by a single bit: Team N = 1 << N
  ## This enables bitwise operations for alliance/visibility checks
  TeamMask* = uint8

const
  ## Pre-computed team masks for teams 0-7
  ## TeamMasks[N] = 1 << N, with special case for invalid teams
  TeamMasks*: array[MapRoomObjectsTeams + 1, TeamMask] = [
    0b00000001'u8,  # Team 0
    0b00000010'u8,  # Team 1
    0b00000100'u8,  # Team 2
    0b00001000'u8,  # Team 3
    0b00010000'u8,  # Team 4
    0b00100000'u8,  # Team 5
    0b01000000'u8,  # Team 6
    0b10000000'u8,  # Team 7
    0b00000000'u8   # Goblins/invalid (no team affiliation)
  ]

  ## Mask with all valid teams set (for alliance systems)
  AllTeamsMask*: TeamMask = 0b11111111'u8

  ## Empty mask (no team affiliation)
  NoTeamMask*: TeamMask = 0b00000000'u8

{.push inline.}
proc getTeamId*(agentId: int): int =
  ## Inline team ID calculation - frequently used
  agentId div MapAgentsPerTeam

proc getTeamMask*(teamId: int): TeamMask =
  ## Convert team ID to bitmask for O(1) bitwise team checks.
  ## Returns NoTeamMask for invalid team IDs (< 0 or >= MapRoomObjectsTeams).
  if teamId >= 0 and teamId < MapRoomObjectsTeams:
    TeamMasks[teamId]
  else:
    NoTeamMask

proc getTeamMaskFromAgentId*(agentId: int): TeamMask =
  ## Get team mask directly from agent ID (combines getTeamId + getTeamMask).
  let teamId = agentId div MapAgentsPerTeam
  if teamId >= 0 and teamId < MapRoomObjectsTeams:
    TeamMasks[teamId]
  else:
    NoTeamMask

proc isTeamInMask*(teamId: int, mask: TeamMask): bool =
  ## Check if a team is included in a bitmask. O(1) operation.
  (getTeamMask(teamId) and mask) != 0

proc teamsShareMask*(maskA, maskB: TeamMask): bool =
  ## Check if two masks have any overlapping teams (for alliance checks).
  (maskA and maskB) != 0


template isValidPos*(pos: IVec2): bool =
  ## Inline bounds checking template - very frequently used
  pos.x >= 0 and pos.x < MapWidth and pos.y >= 0 and pos.y < MapHeight

const
  MaxTintAccum* = 50_000_000'i32

template safeTintAdd*(tintMod: var int32, delta: int): void =
  ## Safe tint accumulation with overflow protection
  let clampedDelta = max(-MaxTintAccum, min(MaxTintAccum, delta.int32))
  tintMod = max(-MaxTintAccum, min(MaxTintAccum, tintMod + clampedDelta))
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
    ThingTrebuchetWorkshopLayer
    ThingBlacksmithLayer
    ThingMarketLayer
    ThingDockLayer
    ThingMonasteryLayer
    ThingUniversityLayer
    ThingCastleLayer
    ThingWonderLayer
    ThingGoblinHiveLayer
    ThingGoblinHutLayer
    ThingGoblinTotemLayer
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
    AgentIdleLayer            # 1 if agent is idle (NOOP/ORIENT action), 0 otherwise
    TintLayer                 # Action/combat tint codes
    RallyPointLayer           # 1 if a friendly building has its rally point on this tile
    BiomeLayer                # Biome type enum value
    GarrisonCountLayer        # Garrison fill ratio: (count * 255) div capacity, 0 = empty/not garrisonable
    RelicCountLayer           # Monastery relic count (direct value, 0-255)
    ProductionQueueLenLayer   # Number of units in production queue (direct value, 0-255)
    BuildingHpLayer           # Building HP ratio: (hp * 255) div maxHp, 0 = none
    MonkFaithLayer            # Monk faith ratio: (faith * 255) div MonkMaxFaith
    TrebuchetPackedLayer      # 1 if trebuchet is packed (mobile), 0 if unpacked (stationary)
    UnitStanceLayer           # AgentStance enum + 1 (0 = none/not an agent)
    ObscuredLayer             # 1 when target tile is above observer elevation

const
  ## Layer aliases for semantic clarity. These map to Thing layers since
  ## updateObservations is a no-op (observations rebuilt in batch at step end).
  AgentLayer* = ThingAgentLayer
  altarHeartsLayer* = ThingAltarLayer

type
  AgentStance* = enum
    StanceAggressive    ## Chase enemies, attack anything in sight
    StanceDefensive     ## Attack enemies in range, return to position
    StanceStandGround   ## Don't move, only attack what's in range
    StanceNoAttack      ## Never auto-attack, useful for scouts

  AgentUnitClass* = enum
    UnitVillager
    UnitManAtArms
    UnitArcher
    UnitScout
    UnitKnight
    UnitMonk
    UnitBatteringRam
    UnitMangonel
    UnitTrebuchet
    UnitGoblin
    UnitBoat
    UnitTradeCog   # Water-based trade unit, generates gold between Docks
    # Castle unique units (one per civilization/team)
    UnitSamurai        # Team 0: Fast infantry, high damage
    UnitLongbowman     # Team 1: Extended range archer
    UnitCataphract     # Team 2: Heavy cavalry
    UnitWoadRaider     # Team 3: Fast infantry
    UnitTeutonicKnight # Team 4: Slow but very tough
    UnitHuskarl        # Team 5: Anti-archer infantry
    UnitMameluke       # Team 6: Ranged cavalry
    UnitJanissary      # Team 7: Powerful ranged unit
    UnitKing           # Regicide mode: team leader, high HP, limited combat
    # Unit upgrade tiers (AoE2-style promotion chains)
    UnitLongSwordsman  # ManAtArms upgrade tier 2
    UnitChampion       # ManAtArms upgrade tier 3
    UnitLightCavalry   # Scout upgrade tier 2
    UnitHussar         # Scout upgrade tier 3
    UnitCrossbowman    # Archer upgrade tier 2
    UnitArbalester     # Archer upgrade tier 3

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
    TrebuchetWorkshop
    Blacksmith
    Market
    Dock
    Monastery
    Temple
    University
    Castle
    Wonder             # AoE2-style Wonder victory building
    ControlPoint       # King of the Hill control point
    GoblinHive
    GoblinHut
    GoblinTotem
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
  ProductionQueueEntry* = object
    ## A single entry in a building's production queue (AoE2-style)
    unitClass*: AgentUnitClass
    totalSteps*: int        ## Original training duration for progress calculation
    remainingSteps*: int

  ProductionQueue* = object
    ## Building production queue for training units over time (AoE2-style)
    entries*: seq[ProductionQueueEntry]

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
    stance*: AgentStance        # Combat stance mode (Aggressive/Defensive/StandGround/NoAttack)
    isIdle*: bool               # True if agent took NOOP/ORIENT action last step (AoE2-style idle detection)
    embarkedUnitClass*: AgentUnitClass
    teamIdOverride*: int
    homeAltar*: IVec2      # Position of agent's home altar for respawning
    movementDebt*: float32     # Accumulated terrain penalty (movement skipped when >= 1.0)
    herdId*: int               # Cow herd grouping id
    packId*: int               # Wolf pack grouping id
    isPackLeader*: bool        # Whether this wolf is the pack leader
    scatteredSteps*: int       # Remaining steps of scattered state after leader death
    # Trebuchet:
    packed*: bool              # Trebuchet pack state (true=packed/mobile, false=unpacked/stationary)
    # Trade Cog:
    tradeHomeDock*: IVec2      # Position of origin dock for trade route gold calculation
    # Monk:
    faith*: int                # Current faith points for conversion (AoE2-style)
    # Tumor:
    homeSpawner*: IVec2     # Position of tumor's home spawner
    hasClaimedTerritory*: bool  # Whether this tumor has already branched and is now inert
    turnsAlive*: int            # Number of turns this tumor has been alive

    # Lantern:
    teamId*: int               # Which team this lantern belongs to (for color spreading)
    lanternHealthy*: bool      # Whether lantern is active (not destroyed by tumor)

    # Garrison (TownCenter, Castle, GuardTower, House):
    garrisonedUnits*: seq[Thing]  # Units currently garrisoned inside this building
    townBellActive*: bool         # True when town bell is ringing, recalling villagers

    # Monastery:
    garrisonedRelics*: int     # Number of relics garrisoned for gold generation

    # Production queue (AoE2-style):
    productionQueue*: ProductionQueue  # Queue of units being trained at this building

    # Rally point (AoE2-style):
    rallyPoint*: IVec2  # Building: where trained units auto-move after spawning (-1,-1 = none)
    rallyTarget*: IVec2  # Agent: assigned rally destination after training (-1,-1 = none)

    # Wonder victory:
    wonderVictoryCountdown*: int  # Steps remaining to hold Wonder for victory

    # Tint tracking:
    lastTintPos*: IVec2        # Last position where tint was applied (for delta optimization)

    # Spawner: (no longer needs altar targeting for new creep spread behavior)

  PoolStats* = object
    acquired*: int
    released*: int
    poolSize*: int

  ThingPool* = object
    free*: array[ThingKind, seq[Thing]]
    stats*: PoolStats

  ProjectilePool* = object
    ## Pool statistics for projectile allocation tracking.
    ## Projectiles use seq with pre-allocated capacity to avoid growth allocations.
    stats*: PoolStats

const
  ## Thing kinds eligible for object pooling (frequently created/destroyed)
  PoolableKinds* = {Tumor, Corpse, Skeleton, Stubble, Lantern, Stump}

  ## Initial capacity for projectile pool (avoids growth allocations during combat)
  ProjectilePoolCapacity* = 128

  ## Initial capacity for action tint positions (avoids growth during combat)
  ActionTintPoolCapacity* = 256

  ## Default capacity for arena-backed sequences
  ArenaDefaultCap* = 1024

type
  Arena* = object
    ## Collection of pre-allocated temporary sequences for per-step use.
    ## All sequences reset to len=0 at step start but retain their capacity.

    # Thing-typed scratch buffers (most common case)
    things1*: seq[Thing]
    things2*: seq[Thing]
    things3*: seq[Thing]
    things4*: seq[Thing]

    # Position scratch buffers
    positions1*: seq[IVec2]
    positions2*: seq[IVec2]

    # Int scratch buffers (for indices, counts, etc.)
    ints1*: seq[int]
    ints2*: seq[int]

    # Generic tuple buffer for inventory-like data
    itemCounts*: seq[tuple[key: ItemKey, count: int]]

    # String buffer for formatting
    strings*: seq[string]

  ArenaStats* = object
    ## Statistics for arena usage tracking
    resets*: int           ## Number of reset calls
    peakThings*: int       ## Peak things buffer usage
    peakPositions*: int    ## Peak positions buffer usage
    peakInts*: int         ## Peak int buffer usage

const
  # Spatial index constants
  SpatialCellSize* = 16  # Tiles per spatial cell
  SpatialCellsX* = (MapWidth + SpatialCellSize - 1) div SpatialCellSize
  SpatialCellsY* = (MapHeight + SpatialCellSize - 1) div SpatialCellSize

when defined(spatialAutoTune):
  const
    SpatialAutoTuneThreshold* = 32  ## Max entities per cell before rebalance
    SpatialMinCellSize* = 4         ## Minimum cell size in tiles
    SpatialMaxCellSize* = 64        ## Maximum cell size in tiles

type
  SpatialCell* = object
    things*: seq[Thing]

  SpatialIndex* = object
    cells*: array[SpatialCellsX, array[SpatialCellsY, SpatialCell]]
    # Per-kind indices for faster filtered queries
    kindCells*: array[ThingKind, array[SpatialCellsX, array[SpatialCellsY, seq[Thing]]]]
    when defined(spatialAutoTune):
      activeCellSize*: int        ## Current runtime cell size (tiles)
      activeCellsX*: int          ## Current grid width in cells
      activeCellsY*: int          ## Current grid height in cells
      dynCells*: seq[seq[SpatialCell]]
      dynKindCells*: array[ThingKind, seq[seq[seq[Thing]]]]

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
    actionSetRallyPoint*: int  # Action 10: SET_RALLY_POINT

  TempleInteraction* = object
    agentId*: int
    teamId*: int
    pos*: IVec2

  TempleHybridRequest* = object
    parentA*: int
    parentB*: int
    childId*: int
    teamId*: int
    pos*: IVec2

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

  ProjectileKind* = enum
    ProjArrow        ## Archer/crossbow/arbalester arrows
    ProjLongbow      ## Longbowman arrows (slightly different color)
    ProjJanissary    ## Janissary bullets
    ProjTowerArrow   ## Guard tower / town center arrows
    ProjCastleArrow  ## Castle arrows
    ProjMangonel     ## Mangonel projectile (stone)
    ProjTrebuchet    ## Trebuchet projectile (boulder)

  Projectile* = object
    ## A visual-only projectile traveling from source to target.
    ## Does not affect gameplay - damage is applied instantly (hitscan).
    ## Exists purely for rendering combat readability.
    source*: IVec2       ## Where the projectile was fired from
    target*: IVec2       ## Where it lands (damage already applied)
    kind*: ProjectileKind
    countdown*: int8     ## Frames remaining before removal (starts at lifetime)
    lifetime*: int8      ## Total frames this projectile lives (for interpolation)

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
    TrebuchetWorkshop,
    Blacksmith,
    Market,
    Dock,
    Monastery,
    University,
    Castle,
    Wonder,
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

const
  BackgroundThingKinds* = {
    Door,
    Wheat,
    Stubble,
    Tree,
    Fish,
    Relic,
    Lantern,
    Corpse,
    Skeleton,
    Dock,
    ControlPoint
  } + CliffKinds

proc getTeamId*(agent: Thing): int =
  ## Team ID lookup that respects conversions.
  if agent.teamIdOverride >= 0:
    agent.teamIdOverride
  else:
    getTeamId(agent.agentId)

proc getTeamMask*(agent: Thing): TeamMask =
  ## Get team bitmask for a Thing. Respects conversions.
  ## Returns NoTeamMask for nil agents or invalid teams.
  if agent.isNil:
    return NoTeamMask
  getTeamMask(getTeamId(agent))

proc sameTeamMask*(a, b: Thing): bool =
  ## Check if two Things are on the same team using bitwise AND.
  ## More efficient than getTeamId comparison when masks are cached.
  if a.isNil or b.isNil:
    return false
  (getTeamMask(a) and getTeamMask(b)) != 0

proc isEnemyMask*(a, b: Thing): bool =
  ## Check if two Things are enemies (different valid teams) using bitwise ops.
  ## Returns false if either is nil or has invalid team.
  if a.isNil or b.isNil:
    return false
  let maskA = getTeamMask(a)
  let maskB = getTeamMask(b)
  # Both must have valid teams, and they must be different
  maskA != NoTeamMask and maskB != NoTeamMask and (maskA and maskB) == 0

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

  TotalRelicsOnMap* = MapRoomObjectsRelics  # Total relics placed on map

type
  VictoryCondition* = enum
    VictoryNone         ## No victory condition (time limit only)
    VictoryConquest     ## Win when all enemy units and buildings destroyed
    VictoryWonder       ## Build Wonder, survive countdown
    VictoryRelic        ## Hold all relics in Monasteries for countdown
    VictoryRegicide     ## Win by killing all enemy kings
    VictoryKingOfTheHill ## Control the hill for consecutive steps
    VictoryAll          ## Any of the above can trigger victory

  VictoryState* = object
    ## Per-team victory tracking
    wonderBuiltStep*: int          ## Step when Wonder was built (-1 = no wonder)
    relicHoldStartStep*: int       ## Step when team started holding all relics (-1 = not holding)
    kingAgentId*: int              ## Agent ID of this team's king (-1 = no king)
    hillControlStartStep*: int     ## Step when team started controlling the hill (-1 = not controlling)

  # Configuration structure for environment - ONLY runtime parameters
  # Structural constants (map size, agent count, observation dimensions) remain compile-time constants
  EnvironmentConfig* = object
    # Core game parameters
    maxSteps*: int
    victoryCondition*: VictoryCondition  ## Which victory conditions are active

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
    maxSteps: 3000,
    victoryCondition: VictoryNone,

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
    teamTiles*: array[MapRoomObjectsTeams, int]
    clippyTiles*: int
    neutralTiles*: int
    scoredTiles*: int

  TeamStockpile* = object
    counts*: array[StockpileResource, int]

  TeamModifiers* = object
    ## Civilization-style asymmetry modifiers for team differentiation
    gatherRateMultiplier*: float32  ## 1.0 = normal gather rate
    buildCostMultiplier*: float32   ## 1.0 = normal build costs
    unitHpBonus*: array[AgentUnitClass, int]      ## Bonus HP per unit class
    unitAttackBonus*: array[AgentUnitClass, int]  ## Bonus attack per unit class

  MarketPrices* = object
    ## AoE2-style dynamic market prices per resource (in gold per 100 units)
    ## Gold is the base currency and not traded
    prices*: array[StockpileResource, int]  ## Current price for each resource

  BlacksmithUpgradeType* = enum
    ## AoE2-style Blacksmith upgrade lines (5 lines, 3 tiers each)
    UpgradeMeleeAttack       ## Forging → Iron Casting → Blast Furnace (infantry + cavalry)
    UpgradeArcherAttack      ## Fletching → Bodkin Arrow → Bracer (archers + towers)
    UpgradeInfantryArmor     ## Scale Mail → Chain Mail → Plate Mail
    UpgradeCavalryArmor      ## Scale Barding → Chain Barding → Plate Barding
    UpgradeArcherArmor       ## Padded Archer → Leather Archer → Ring Archer

  BlacksmithUpgrades* = object
    ## Team-level Blacksmith upgrade progress (AoE2-style named tech tree)
    ## Each line can be researched up to 3 tiers with variable bonuses per tier
    levels*: array[BlacksmithUpgradeType, int]  ## Current tier (0-3) for each line

type

  UniversityTechType* = enum
    ## AoE2-style University technologies
    TechBallistics       ## Projectiles lead moving targets (ranged accuracy)
    TechMurderHoles      ## Towers attack adjacent units (no minimum range)
    TechMasonry          ## +10% building HP, +1/+1 building armor
    TechArchitecture     ## +10% building HP, +1/+1 building armor (stacks with Masonry)
    TechTreadmillCrane   ## +20% construction speed
    TechArrowslits       ## +1 tower attack damage
    TechHeatedShot       ## +2 attack vs ships (bonus damage)
    TechSiegeEngineers   ## +1 range, +20% building damage for siege units
    TechChemistry        ## Enables gunpowder units (future tech)

  UniversityTechs* = object
    ## Team-level University tech progress (AoE2-style)
    ## Each tech is either researched (true) or not (false)
    researched*: array[UniversityTechType, bool]

  CastleTechType* = enum
    ## AoE2-style Castle unique technologies (2 per civilization/team)
    ## Each team has one Castle Age tech and one Imperial Age tech.
    ## Index: team * 2 = Castle Age tech, team * 2 + 1 = Imperial Age tech
    CastleTechYeomen          ## Team 0 Castle: +1 archer range, +2 tower attack
    CastleTechKataparuto      ## Team 0 Imperial: +3 trebuchet attack
    CastleTechLogistica        ## Team 1 Castle: +1 infantry attack
    CastleTechCrenellations    ## Team 1 Imperial: +2 castle attack
    CastleTechGreekFire        ## Team 2 Castle: +2 tower attack vs siege
    CastleTechFurorCeltica     ## Team 2 Imperial: +2 siege attack
    CastleTechAnarchy          ## Team 3 Castle: +1 infantry HP per unit
    CastleTechPerfusion        ## Team 3 Imperial: military units train faster (not modeled, +2 all attack)
    CastleTechIronclad         ## Team 4 Castle: +3 siege unit armor (modeled as +3 siege HP)
    CastleTechCrenellations2   ## Team 4 Imperial: +2 castle attack
    CastleTechBerserkergang    ## Team 5 Castle: +2 infantry HP
    CastleTechChieftains       ## Team 5 Imperial: +1 cavalry attack bonus
    CastleTechZealotry         ## Team 6 Castle: +2 cavalry HP
    CastleTechMahayana         ## Team 6 Imperial: +1 monk conversion (modeled as +1 monk attack)
    CastleTechSipahi           ## Team 7 Castle: +2 archer HP
    CastleTechArtillery        ## Team 7 Imperial: +2 tower and castle attack

  CastleTechs* = object
    ## Team-level Castle unique tech progress (AoE2-style)
    ## Each team can research exactly 2 techs (their own civilization's unique techs)
    researched*: array[CastleTechType, bool]

  UnitUpgradeType* = enum
    ## AoE2-style unit promotion chains (researched at military buildings)
    UpgradeLongSwordsman     ## ManAtArms → LongSwordsman (Barracks)
    UpgradeChampion          ## LongSwordsman → Champion (Barracks)
    UpgradeLightCavalry      ## Scout → LightCavalry (Stable)
    UpgradeHussar            ## LightCavalry → Hussar (Stable)
    UpgradeCrossbowman       ## Archer → Crossbowman (Archery Range)
    UpgradeArbalester        ## Crossbowman → Arbalester (Archery Range)

  UnitUpgrades* = object
    ## Team-level unit upgrade progress (AoE2-style promotion chains)
    ## Each upgrade is either researched (true) or not (false)
    researched*: array[UnitUpgradeType, bool]

  ElevationGrid* = array[MapWidth, array[MapHeight, int8]]

  # Fog of war: tracks which tiles each team has explored (AoE2-style)
  RevealedMap* = array[MapWidth, array[MapHeight, bool]]

  Environment* = ref object
    currentStep*: int
    mapGeneration*: int  # Bumps each time the map is rebuilt (for render caches)
    config*: EnvironmentConfig  # Configuration for this environment
    shouldReset*: bool  # Track if environment needs reset
    observationsInitialized*: bool  # Track whether observation tensors are populated
    things*: seq[Thing]
    agents*: seq[Thing]
    grid*: array[MapWidth, array[MapHeight, Thing]]          # Blocking units
    backgroundGrid*: array[MapWidth, array[MapHeight, Thing]]   # Background (non-blocking) units
    elevation*: ElevationGrid
    teamStockpiles*: array[MapRoomObjectsTeams, TeamStockpile]
    teamModifiers*: array[MapRoomObjectsTeams, TeamModifiers]
    teamMarketPrices*: array[MapRoomObjectsTeams, MarketPrices]  # AoE2-style dynamic market prices
    teamBlacksmithUpgrades*: array[MapRoomObjectsTeams, BlacksmithUpgrades]  # AoE2-style Blacksmith upgrades
    teamUniversityTechs*: array[MapRoomObjectsTeams, UniversityTechs]  # AoE2-style University techs
    teamCastleTechs*: array[MapRoomObjectsTeams, CastleTechs]  # AoE2-style Castle unique techs
    teamUnitUpgrades*: array[MapRoomObjectsTeams, UnitUpgrades]  # AoE2-style unit promotion chains
    revealedMaps*: array[MapRoomObjectsTeams, RevealedMap]  # Fog of war: explored tiles per team
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
    projectiles*: seq[Projectile]  # Visual-only projectile sprites for ranged attacks
    thingsByKind*: array[ThingKind, seq[Thing]]
    spatialIndex*: SpatialIndex  # Spatial partitioning for O(1) nearest queries
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
    wolfPackLeaders*: seq[Thing]  # Leader wolf for each pack (nil if dead)
    shieldCountdown*: array[MapAgents, int8]  # shield active timer per agent
    territoryScore*: TerritoryScore
    territoryScored*: bool
    observations*: array[
      MapAgents,
      array[ObservationLayers,
        array[ObservationWidth, array[ObservationHeight, uint8]]
      ]
    ]
    rewards*: array[MapAgents, float32]
    terminated*: array[MapAgents, float32]
    truncated*: array[MapAgents, float32]
    stats*: seq[Stats]
    templeInteractions*: seq[TempleInteraction]
    templeHybridRequests*: seq[TempleHybridRequest]
    # Tint tracking for incremental updates
    lastAgentPos*: array[MapAgents, IVec2]  # Track agent positions for delta tint
    lastLanternPos*: seq[IVec2]              # Track lantern positions for delta tint
    # Color management
    agentColors*: seq[Color]           ## Per-agent colors for rendering
    teamColors*: seq[Color]            ## Per-team colors for rendering
    altarColors*: Table[IVec2, Color]  ## Altar position to color mapping
    # Victory conditions tracking
    victoryStates*: array[MapRoomObjectsTeams, VictoryState]
    victoryWinner*: int              ## Team that won (-1 = no winner yet)
    # Reusable scratch seqs for step() to avoid per-frame heap allocations
    tempTumorsToSpawn*: seq[Thing]
    tempTumorsToProcess*: seq[Thing]
    tempTowerRemovals*: seq[Thing]
    # Additional scratch buffers for hot-path allocations
    tempTowerTargets*: seq[Thing]      ## Tower attack target candidates
    tempTCTargets*: seq[Thing]         ## Town center attack targets
    tempMonkAuraAllies*: seq[Thing]    ## Nearby allies for monk auras
    tempEmptyTiles*: seq[IVec2]        ## Empty tiles for ungarrisoning
    # Object pool for frequently created/destroyed things
    thingPool*: ThingPool
    # Object pool for projectiles (pre-allocated capacity, stats tracking)
    projectilePool*: ProjectilePool
    # Arena allocator for per-step temporary allocations
    arena*: Arena

# Global environment instance
var env*: Environment

# Control group constants
const
  ControlGroupCount* = 10  # Groups 0-9, bound to keys 0-9

# Selection state (for UI)
var selection*: seq[Thing] = @[]
var selectedPos*: IVec2 = ivec2(-1, -1)

# Control groups (AoE2-style: Ctrl+N assigns, N recalls, double-tap N centers camera)
var controlGroups*: array[ControlGroupCount, seq[Thing]] = default(array[ControlGroupCount, seq[Thing]])
var lastGroupKeyTime*: array[ControlGroupCount, float64]  # For double-tap detection
var lastGroupKeyIndex*: int = -1  # Last group key pressed (for double-tap)

# Building placement mode (for ghost preview)
var buildingPlacementMode*: bool = false
var buildingPlacementKind*: ThingKind = Wall  # Default to wall
var buildingPlacementValid*: bool = false     # Whether current position is valid

# Helper function for checking if agent is alive
proc isAgentAlive*(env: Environment, agent: Thing): bool {.inline.} =
  not agent.isNil and
    env.terminated[agent.agentId] == 0.0 and
    isValidPos(agent.pos) and
    env.grid[agent.pos.x][agent.pos.y] == agent

proc defaultTeamModifiers*(): TeamModifiers =
  ## Create default (neutral) team modifiers with no bonuses
  TeamModifiers(
    gatherRateMultiplier: 1.0'f32,
    buildCostMultiplier: 1.0'f32,
    unitHpBonus: default(array[AgentUnitClass, int]),
    unitAttackBonus: default(array[AgentUnitClass, int])
  )
