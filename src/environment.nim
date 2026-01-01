import std/[algorithm, strutils, tables], vmath, chroma
import rng_compat
import terrain, objects, workshop, items, common, biome_common
import dungeon_maze, dungeon_radial
export terrain, objects, workshop, items, common


const
  # Map Layout
  MapLayoutRoomsX* = 1
  MapLayoutRoomsY* = 1
  MapBorder* = 4
  MapRoomWidth* = 288  # 16:10 aspect ratio (1.5x 192x120)
  MapRoomHeight* = 180
  MapRoomBorder* = 0

  AgentMaxHp* = 5

  # World Objects
  # Eight bases with six agents each -> 48 agents total (divisible by 12 and 16 for batching).
  MapRoomObjectsHouses* = 8
  MapAgentsPerHouse* = 20
  MapRoomObjectsAgents* = MapRoomObjectsHouses * MapAgentsPerHouse  # Agent slots across all villages
  MapRoomObjectsConverters* = 10
  MapRoomObjectsMines* = 20
  MapRoomObjectsMineClusters* = 6
  MapRoomObjectsWalls* = 30
  MapRoomObjectsCows* = 24

  # Agent Parameters
  MapObjectAgentMaxInventory* = 5

  # Building Parameters
  MapObjectAltarInitialHearts* = 5
  MapObjectAltarCooldown* = 10
  MapObjectAltarRespawnCost* = 1
  MapObjectAltarAutoSpawnThreshold* = 5
  BarrelCapacity* = 50
  MapObjectMineCooldown* = 5
  MapObjectMineInitialResources* = 30
  DoorMaxHearts* = 5
  RoadWoodCost* = 1
  WatchTowerWoodCost* = 2
  CowMilkCooldown* = 25

  # Gameplay
  MinTintEpsilon* = 5

  # Observation System
  ObservationLayers* = 21
  ObservationWidth* = 11
  ObservationHeight* = 11

  # Action tint observation codes (TintLayer values)
  ActionTintAttack* = 1'u8   # red overlay when attacking
  ActionTintShield* = 2'u8   # gold overlay when shielding (armor up)
  ActionTintHeal* = 3'u8     # green overlay when healing

  # Computed Values
  MapAgents* = MapRoomObjectsAgents * MapLayoutRoomsX * MapLayoutRoomsY
  MapWidth* = MapLayoutRoomsX * (MapRoomWidth + MapRoomBorder) + MapBorder
  MapHeight* = MapLayoutRoomsY * (MapRoomHeight + MapRoomBorder) + MapBorder

  # Compile-time optimization constants
  ObservationRadius* = ObservationWidth div 2  # 5 - computed once
  MapAgentsPerHouseFloat* = MapAgentsPerHouse.float32  # Avoid runtime conversion

{.push inline.}
proc getTeamId*(agentId: int): int =
  ## Inline team ID calculation - frequently used
  agentId div MapAgentsPerHouse

template isValidPos*(pos: IVec2): bool =
  ## Inline bounds checking template - very frequently used
  pos.x >= 0 and pos.x < MapWidth and pos.y >= 0 and pos.y < MapHeight

template safeTintAdd*(tintMod: var int16, delta: int): void =
  ## Safe tint accumulation with overflow protection
  tintMod = max(-32000'i16, min(32000'i16, tintMod + delta.int16))
{.pop.}



type
  ObservationName* = enum
    AgentLayer = 0        # Team-aware: 0=empty, 1=team0, 2=team1, 3=team2, 255=Tumor
    AgentOrientationLayer = 1
    AgentInventoryOreLayer = 2
    AgentInventoryBarLayer = 3
    AgentInventoryWaterLayer = 4
    AgentInventoryWheatLayer = 5
    AgentInventoryWoodLayer = 6
    AgentInventorySpearLayer = 7
    AgentInventoryLanternLayer = 8
    AgentInventoryArmorLayer = 9
    WallLayer = 10
    MineLayer = 11
    MineResourceLayer = 12
    MineReadyLayer = 13
    ConverterLayer = 14  # Renamed from Converter
    ConverterReadyLayer = 15
    altarLayer = 16
    altarHeartsLayer = 17  # Hearts for respawning
    altarReadyLayer = 18
    TintLayer = 19        # Unified tint layer for all environmental effects
    AgentInventoryBreadLayer = 20  # Bread baked from clay oven


  ThingKind* = enum
    Agent
    Wall
    TreeObject
    Mine
    Converter  # Smelts ore into bars
    Altar
    Spawner
    Tumor
    Cow
    Armory
    Forge
    ClayOven
    WeavingLoom
    Bed
    Chair
    Table
    Statue
    WatchTower
    Barrel
    Mill
    LumberCamp
    MiningCamp
    Farm
    PlantedLantern  # Planted lanterns that spread team colors

  TreeVariant* = enum
    TreeVariantPine
    TreeVariantPalm

  Thing* = ref object
    kind*: ThingKind
    pos*: IVec2
    id*: int
    layer*: int
    cooldown*: int
    frozen*: int

    # Agent:
    agentId*: int
    orientation*: Orientation
    inventory*: Inventory
    barrelCapacity*: int
    reward*: float32
    hp*: int
    maxHp*: int
    homeAltar*: IVec2      # Position of agent's home altar for respawning
    herdId*: int               # Cow herd grouping id
    # Tumor:
    homeSpawner*: IVec2     # Position of tumor's home spawner
    hasClaimedTerritory*: bool  # Whether this tumor has already branched and is now inert
    turnsAlive*: int            # Number of turns this tumor has been alive

    # PlantedLantern:
    teamId*: int               # Which team this lantern belongs to (for color spreading)
    lanternHealthy*: bool      # Whether lantern is active (not destroyed by tumor)

    # TreeObject:
    treeVariant*: TreeVariant

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
    actionPlantResource*: int  # Action 7: Plant wheat/tree onto fertile tile

  TileColor* = object
    r*, g*, b*: float32      # RGB color components
    intensity*: float32      # Overall intensity/brightness modifier

  # Tint modification layers for efficient batch updates
  TintModification* = object
    r*, g*, b*: int16       # Delta values to add (scaled by 1000)

  # Track active tiles for sparse processing
  ActiveTiles* = object
    positions*: seq[IVec2]  # Linear list of active tiles
    flags*: array[MapWidth, array[MapHeight, bool]]  # Dedup mask per tile

  # Action tint overlay (short-lived highlights for combat/effects)
  ActionTintCountdown* = array[MapWidth, array[MapHeight, int8]]
  ActionTintColor* = array[MapWidth, array[MapHeight, TileColor]]
  ActionTintFlags* = array[MapWidth, array[MapHeight, bool]]

const
  BaseTileColorDefault = TileColor(r: 0.7, g: 0.65, b: 0.6, intensity: 1.0)
  BiomeColorForest = TileColor(r: 0.45, g: 0.60, b: 0.40, intensity: 1.0)
  BiomeColorDesert = TileColor(r: 0.78, g: 0.70, b: 0.45, intensity: 1.0)
  BiomeColorCaves = TileColor(r: 0.45, g: 0.50, b: 0.58, intensity: 0.95)
  BiomeColorCity = TileColor(r: 0.62, g: 0.62, b: 0.66, intensity: 1.0)
  BiomeColorPlains = TileColor(r: 0.55, g: 0.70, b: 0.50, intensity: 1.0)
  BiomeColorDungeon = TileColor(r: 0.40, g: 0.36, b: 0.48, intensity: 0.9)
  BiomeColorSnow = TileColor(r: 0.93, g: 0.95, b: 0.98, intensity: 1.0)
  WheatBaseColor = TileColor(r: 0.88, g: 0.78, b: 0.48, intensity: 1.05)
  PalmBaseColor = TileColor(r: 0.70, g: 0.78, b: 0.52, intensity: 1.0)
  WheatBaseBlend = 0.65'f32
  PalmBaseBlend = 0.55'f32
  BiomeBlendPasses = 2
  BiomeBlendNeighborWeight = 0.18'f32
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
    oreReward*: float
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

  Environment* = ref object
    currentStep*: int
    config*: EnvironmentConfig  # Configuration for this environment
    shouldReset*: bool  # Track if environment needs reset
    observationsInitialized*: bool  # Track whether observation tensors are populated
    things*: seq[Thing]
    agents*: seq[Thing]
    grid*: array[MapWidth, array[MapHeight, Thing]]
    doorTeams*: array[MapWidth, array[MapHeight, int16]]  # -1 means no door
    doorHearts*: array[MapWidth, array[MapHeight, int8]]
    terrain*: TerrainGrid
    biomes*: BiomeGrid
    tileColors*: array[MapWidth, array[MapHeight, TileColor]]  # Main color array
    baseTileColors*: array[MapWidth, array[MapHeight, TileColor]]  # Base colors (terrain)
    tintMods*: array[MapWidth, array[MapHeight, TintModification]]  # Unified tint modifications
    activeTiles*: ActiveTiles  # Sparse list of tiles to process
    actionTintCountdown*: ActionTintCountdown  # Short-lived combat/heal highlights
    actionTintColor*: ActionTintColor
    actionTintFlags*: ActionTintFlags
    actionTintPositions*: seq[IVec2]
    shieldCountdown*: array[MapAgents, int8]  # shield active timer per agent
    observations*: array[
      MapAgents,
      array[ObservationLayers,
        array[ObservationWidth, array[ObservationHeight, uint8]]
      ]
    ]
    terminated*: array[MapAgents, float32]
    truncated*: array[MapAgents, float32]
    stats: seq[Stats]

# Global village color management and palettes
var agentVillageColors*: seq[Color] = @[]
var teamColors*: seq[Color] = @[]
var altarColors*: Table[IVec2, Color] = initTable[IVec2, Color]()

include equipment

# Forward declaration so combat helpers can update observations before the
# inline definition later in the file.
proc updateObservations(env: Environment, layer: ObservationName, pos: IVec2, value: int)

const WarmVillagePalette* = [
  # Eight bright, evenly spaced tints (similar brightness, varied hue; away from clippy purple)
  color(0.910, 0.420, 0.420, 1.0),  # team 0: soft red        (#e86b6b)
  color(0.940, 0.650, 0.420, 1.0),  # team 1: soft orange     (#f0a86b)
  color(0.940, 0.820, 0.420, 1.0),  # team 2: soft yellow     (#f0d56b)
  color(0.600, 0.840, 0.500, 1.0),  # team 3: soft olive-lime (#99d680)
  color(0.780, 0.380, 0.880, 1.0),  # team 4: warm magenta    (#c763e0)
  color(0.420, 0.720, 0.940, 1.0),  # team 5: soft sky        (#6ab8f0)
  color(0.870, 0.870, 0.870, 1.0),  # team 6: light gray      (#dedede)
  color(0.930, 0.560, 0.820, 1.0)   # team 7: soft pink       (#ed8fd1)
]

# Combat tint helpers (inlined from combat.nim)
proc applyActionTint(env: Environment, pos: IVec2, tintColor: TileColor, duration: int8, tintCode: uint8) =
  if pos.x < 0 or pos.x >= MapWidth or pos.y < 0 or pos.y >= MapHeight:
    return
  env.actionTintColor[pos.x][pos.y] = tintColor
  env.actionTintCountdown[pos.x][pos.y] = duration
  # Keep observation tint layer in sync so agents can “see” recent combat actions
  env.updateObservations(TintLayer, pos, tintCode.int)
  if not env.actionTintFlags[pos.x][pos.y]:
    env.actionTintFlags[pos.x][pos.y] = true
    env.actionTintPositions.add(pos)

proc applyShieldBand(env: Environment, agent: Thing, orientation: Orientation) =
  let d = getOrientationDelta(orientation)
  let tint = TileColor(r: 0.95, g: 0.75, b: 0.25, intensity: 1.1)

  # Diagonal orientations should “wrap the corner”: cover the forward diagonal tile
  # plus the two adjacent cardinals (one step in x, one step in y).
  if abs(d.x) == 1 and abs(d.y) == 1:
    let diagPos = agent.pos + ivec2(d.x, d.y)
    let xPos = agent.pos + ivec2(d.x, 0)
    let yPos = agent.pos + ivec2(0, d.y)
    env.applyActionTint(diagPos, tint, 2, ActionTintShield)
    env.applyActionTint(xPos, tint, 2, ActionTintShield)
    env.applyActionTint(yPos, tint, 2, ActionTintShield)
  else:
    # Cardinal facing: keep a 3-wide band centered on the forward tile
    let perp = if d.x != 0: ivec2(0, 1) else: ivec2(1, 0)
    let forward = agent.pos + ivec2(d.x, d.y)
    for offset in -1 .. 1:
      let p = forward + ivec2(perp.x * offset, perp.y * offset)
      env.applyActionTint(p, tint, 2, ActionTintShield)

proc applySpearStrike(env: Environment, agent: Thing, orientation: Orientation) =
  let d = getOrientationDelta(orientation)
  let left = ivec2(-d.y, d.x)
  let right = ivec2(d.y, -d.x)
  let tint = TileColor(r: 0.9, g: 0.15, b: 0.15, intensity: 1.15)
  for step in 1 .. 3:
    let forward = agent.pos + ivec2(d.x * step, d.y * step)
    env.applyActionTint(forward, tint, 2, ActionTintAttack)
    # Keep spear width contiguous: side tiles offset by 1 perpendicular, not scaled by range.
    env.applyActionTint(forward + left, tint, 2, ActionTintAttack)
    env.applyActionTint(forward + right, tint, 2, ActionTintAttack)

# Utility to tick a building cooldown and update its ready observation if provided.
proc tickCooldown(env: Environment, thing: Thing, readyLayer: ObservationName = TintLayer, updateLayer = false) =
  if thing.cooldown > 0:
    dec thing.cooldown
    if updateLayer:
      env.updateObservations(readyLayer, thing.pos, thing.cooldown)

var
  env*: Environment  # Global environment instance
  selection*: Thing  # Currently selected entity for UI interaction
  selectedPos*: IVec2 = ivec2(-1, -1)  # Last clicked tile for UI label

# Frozen detection (terrain & buildings share the same tint-based check)
proc matchesClippyTint(color: TileColor): bool =
  ## Frozen only when the tile tint fully matches the clippy tint.
  abs(color.r - ClippyTint.r) <= ClippyTintTolerance and
  abs(color.g - ClippyTint.g) <= ClippyTintTolerance and
  abs(color.b - ClippyTint.b) <= ClippyTintTolerance

proc isTileFrozen*(pos: IVec2, env: Environment): bool =
  if pos.x < 0 or pos.x >= MapWidth or pos.y < 0 or pos.y >= MapHeight:
    return false
  return matchesClippyTint(env.tileColors[pos.x][pos.y])

proc isBuildingFrozen*(pos: IVec2, env: Environment): bool =
  ## Backwards-compatible alias for frozen detection on buildings.
  return isTileFrozen(pos, env)

proc isThingFrozen*(thing: Thing, env: Environment): bool =
  ## Anything explicitly frozen or sitting on a frozen tile counts as non-interactable.
  if thing.frozen > 0:
    return true
  return isTileFrozen(thing.pos, env)

proc biomeBaseColor*(biome: BiomeType): TileColor =
  case biome:
  of BiomeForestType: BiomeColorForest
  of BiomeDesertType: BiomeColorDesert
  of BiomeCavesType: BiomeColorCaves
  of BiomeCityType: BiomeColorCity
  of BiomePlainsType: BiomeColorPlains
  of BiomeSnowType: BiomeColorSnow
  of BiomeDungeonType: BiomeColorDungeon
  else: BaseTileColorDefault

proc baseColorForPos(env: Environment, pos: IVec2): TileColor =
  if pos.x < 0 or pos.x >= MapWidth or pos.y < 0 or pos.y >= MapHeight:
    return BaseTileColorDefault
  env.baseTileColors[pos.x][pos.y]

proc blendTileColor(a, b: TileColor, t: float32): TileColor =
  let tClamped = max(0.0'f32, min(1.0'f32, t))
  TileColor(
    r: a.r * (1.0 - tClamped) + b.r * tClamped,
    g: a.g * (1.0 - tClamped) + b.g * tClamped,
    b: a.b * (1.0 - tClamped) + b.b * tClamped,
    intensity: a.intensity * (1.0 - tClamped) + b.intensity * tClamped
  )

proc smoothBaseColors(colors: var array[MapWidth, array[MapHeight, TileColor]], passes: int) =
  if passes <= 0:
    return
  var temp: array[MapWidth, array[MapHeight, TileColor]]
  let centerWeight = 1.0'f32
  let neighborWeight = BiomeBlendNeighborWeight
  for _ in 0 ..< passes:
    for x in 0 ..< MapWidth:
      for y in 0 ..< MapHeight:
        var sumR = colors[x][y].r * centerWeight
        var sumG = colors[x][y].g * centerWeight
        var sumB = colors[x][y].b * centerWeight
        var sumI = colors[x][y].intensity * centerWeight
        var total = centerWeight
        for dx in -1 .. 1:
          for dy in -1 .. 1:
            if dx == 0 and dy == 0:
              continue
            let nx = x + dx
            let ny = y + dy
            if nx < 0 or nx >= MapWidth or ny < 0 or ny >= MapHeight:
              continue
            let c = colors[nx][ny]
            sumR += c.r * neighborWeight
            sumG += c.g * neighborWeight
            sumB += c.b * neighborWeight
            sumI += c.intensity * neighborWeight
            total += neighborWeight
        temp[x][y] = TileColor(
          r: sumR / total,
          g: sumG / total,
          b: sumB / total,
          intensity: sumI / total
        )
    colors = temp

proc applyBiomeBaseColors*(env: Environment) =
  var colors: array[MapWidth, array[MapHeight, TileColor]]
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      var color = biomeBaseColor(env.biomes[x][y])
      case env.terrain[x][y]:
      of Wheat:
        color = blendTileColor(color, WheatBaseColor, WheatBaseBlend)
      of Palm:
        # Treat palm groves as desert oases for ground color.
        color = BiomeColorDesert
      else:
        discard
      colors[x][y] = color
  smoothBaseColors(colors, BiomeBlendPasses)
  env.baseTileColors = colors
  env.tileColors = colors

proc render*(env: Environment): string =
  for y in 0 ..< MapHeight:
    for x in 0 ..< MapWidth:
      var cell = " "
      # First check terrain
      case env.terrain[x][y]
      of Bridge:
        cell = "="
      of Water:
        cell = "~"
      of Wheat:
        cell = "."
      of Tree:
        cell = "T"
      of Palm:
        cell = "P"
      of Fertile:
        cell = "f"
      of Road:
        cell = "r"
      of Rock:
        cell = "R"
      of Gem:
        cell = "G"
      of Bush:
        cell = "b"
      of Animal:
        cell = "a"
      of Grass:
        cell = "g"
      of Cactus:
        cell = "c"
      of Dune:
        cell = "d"
      of Sand:
        cell = "s"
      of Snow:
        cell = "n"
      of Stalagmite:
        cell = "m"
      of Empty:
        cell = " "
      # Then override with objects if present
      for thing in env.things:
        if thing.pos.x == x and thing.pos.y == y:
          case thing.kind
          of Agent:
            cell = "A"
          of Wall:
            cell = "#"
          of TreeObject:
            cell = "T"
          of Mine:
            cell = "m"
          of Converter:
            cell = "g"
          of Altar:
            cell = "a"
          of Spawner:
            cell = "t"
          of Tumor:
            cell = "C"
          of Cow:
            cell = "o"
          of Armory:
            cell = "A"
          of Forge:
            cell = "F"
          of ClayOven:
            cell = "O"
          of WeavingLoom:
            cell = "W"
          of Barrel:
            cell = "b"
          of Mill:
            cell = "M"
          of LumberCamp:
            cell = "l"
          of MiningCamp:
            cell = "n"
          of Farm:
            cell = "f"
          of Bed:
            cell = "B"
          of Chair:
            cell = "H"
          of Table:
            cell = "T"
          of Statue:
            cell = "S"
          of WatchTower:
            cell = "^"
          of PlantedLantern:
            cell = "L"
          break
      result.add(cell)
    result.add("\n")


proc clear[T](s: var openarray[T]) =
  ## Zero out a contiguous buffer (arrays/openarrays) without reallocating.
  let p = cast[pointer](s[0].addr)
  zeroMem(p, s.len * sizeof(T))


{.push inline.}
proc updateObservations(
  env: Environment,
  layer: ObservationName,
  pos: IVec2,
  value: int
) =
  ## Ultra-optimized observation update - early bailout and minimal calculations
  let layerId = ord(layer)

  # Ultra-fast observation update with minimal calculations

  # Still need to check all agents but with optimized early exit
  let agentCount = env.agents.len
  for agentId in 0 ..< agentCount:
    let agentPos = env.agents[agentId].pos

    # Ultra-fast bounds check using compile-time constants
    let dx = pos.x - agentPos.x
    let dy = pos.y - agentPos.y
    if dx < -ObservationRadius or dx > ObservationRadius or
       dy < -ObservationRadius or dy > ObservationRadius:
      continue

    let x = dx + ObservationRadius
    let y = dy + ObservationRadius
    var agentLayer = addr env.observations[agentId][layerId]
    agentLayer[][x][y] = value.uint8
  env.observationsInitialized = true
{.pop.}

proc getInv*(thing: Thing, key: ItemKey): int


proc rebuildObservations*(env: Environment) =
  ## Recompute all observation layers from the current environment state when needed.
  env.observations.clear()
  env.observationsInitialized = false

  # Populate agent-centric layers (presence, orientation, inventory).
  for agent in env.agents:
    if agent.isNil:
      continue
    if not isValidPos(agent.pos):
      continue
    let teamValue = getTeamId(agent.agentId) + 1
    env.updateObservations(AgentLayer, agent.pos, teamValue)
    env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
    env.updateObservations(AgentInventoryOreLayer, agent.pos, getInv(agent, ItemOre))
    env.updateObservations(AgentInventoryBarLayer, agent.pos, getInv(agent, ItemBar))
    env.updateObservations(AgentInventoryWaterLayer, agent.pos, getInv(agent, ItemWater))
    env.updateObservations(AgentInventoryWheatLayer, agent.pos, getInv(agent, ItemWheat))
    env.updateObservations(AgentInventoryWoodLayer, agent.pos, getInv(agent, ItemWood))
    env.updateObservations(AgentInventorySpearLayer, agent.pos, getInv(agent, ItemSpear))
    env.updateObservations(AgentInventoryLanternLayer, agent.pos, getInv(agent, ItemLantern))
    env.updateObservations(AgentInventoryArmorLayer, agent.pos, getInv(agent, ItemArmor))
    env.updateObservations(AgentInventoryBreadLayer, agent.pos, getInv(agent, ItemBread))

  # Populate environment object layers.
  for thing in env.things:
    if thing.isNil:
      continue
    case thing.kind
    of Agent:
      discard  # Already handled above.
    of Wall:
      env.updateObservations(WallLayer, thing.pos, 1)
    of TreeObject:
      discard  # No dedicated observation layer for trees.
    of Mine:
      env.updateObservations(MineLayer, thing.pos, 1)
      env.updateObservations(MineResourceLayer, thing.pos, getInv(thing, ItemOre))
      env.updateObservations(MineReadyLayer, thing.pos, thing.cooldown)
    of Converter:
      env.updateObservations(ConverterLayer, thing.pos, 1)
      env.updateObservations(ConverterReadyLayer, thing.pos, thing.cooldown)
    of Altar:
      env.updateObservations(altarLayer, thing.pos, 1)
      env.updateObservations(altarHeartsLayer, thing.pos, getInv(thing, ItemHearts))
      env.updateObservations(altarReadyLayer, thing.pos, thing.cooldown)
    of Spawner:
      discard  # No dedicated observation layer for spawners.
    of Tumor:
      env.updateObservations(AgentLayer, thing.pos, 255)
    of Cow, Armory, Forge, ClayOven, WeavingLoom, Bed, Chair, Table, Statue, WatchTower,
       Barrel, Mill, LumberCamp, MiningCamp, Farm, PlantedLantern:
      discard

  env.observationsInitialized = true


{.push inline.}
proc getThing(env: Environment, pos: IVec2): Thing =
  if not isValidPos(pos):
    return nil
  return env.grid[pos.x][pos.y]

proc isEmpty*(env: Environment, pos: IVec2): bool =
  if not isValidPos(pos):
    return false
  return env.grid[pos.x][pos.y] == nil

proc hasDoor*(env: Environment, pos: IVec2): bool =
  if not isValidPos(pos):
    return false
  return env.doorTeams[pos.x][pos.y] >= 0

proc getDoorTeam*(env: Environment, pos: IVec2): int =
  if not isValidPos(pos):
    return -1
  return env.doorTeams[pos.x][pos.y].int

proc canAgentPassDoor*(env: Environment, agent: Thing, pos: IVec2): bool =
  if not env.hasDoor(pos):
    return true
  return env.getDoorTeam(pos) == getTeamId(agent.agentId)
{.pop.}

proc resetTileColor*(env: Environment, pos: IVec2) =
  ## Restore a tile to the biome base color
  let color = env.baseColorForPos(pos)
  env.tileColors[pos.x][pos.y] = color
  env.baseTileColors[pos.x][pos.y] = color

proc clearDoors(env: Environment) =
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      env.doorTeams[x][y] = -1
      env.doorHearts[x][y] = 0

proc getInv*(thing: Thing, key: ItemKey): int =
  if key.len == 0:
    return 0
  if thing.inventory.hasKey(key):
    return thing.inventory[key]
  0

proc setInv*(thing: Thing, key: ItemKey, value: int) =
  if key.len == 0:
    return
  if value <= 0:
    if thing.inventory.hasKey(key):
      thing.inventory.del(key)
  else:
    thing.inventory[key] = value

proc addInv*(thing: Thing, key: ItemKey, delta: int): int =
  if key.len == 0 or delta == 0:
    return getInv(thing, key)
  let newVal = getInv(thing, key) + delta
  setInv(thing, key, newVal)
  newVal

proc updateAgentInventoryObs*(env: Environment, agent: Thing, key: ItemKey) =
  if key == ItemOre:
    env.updateObservations(AgentInventoryOreLayer, agent.pos, getInv(agent, key))
  elif key == ItemBar:
    env.updateObservations(AgentInventoryBarLayer, agent.pos, getInv(agent, key))
  elif key == ItemWater:
    env.updateObservations(AgentInventoryWaterLayer, agent.pos, getInv(agent, key))
  elif key == ItemWheat:
    env.updateObservations(AgentInventoryWheatLayer, agent.pos, getInv(agent, key))
  elif key == ItemWood:
    env.updateObservations(AgentInventoryWoodLayer, agent.pos, getInv(agent, key))
  elif key == ItemSpear:
    env.updateObservations(AgentInventorySpearLayer, agent.pos, getInv(agent, key))
  elif key == ItemLantern:
    env.updateObservations(AgentInventoryLanternLayer, agent.pos, getInv(agent, key))
  elif key == ItemArmor:
    env.updateObservations(AgentInventoryArmorLayer, agent.pos, getInv(agent, key))
  elif key == ItemBread:
    env.updateObservations(AgentInventoryBreadLayer, agent.pos, getInv(agent, key))

proc agentMostHeldItem(agent: Thing): tuple[key: ItemKey, count: int] =
  ## Pick the item with the highest count to deposit into an empty barrel.
  result = (key: ItemNone, count: 0)
  for key, count in agent.inventory.pairs:
    if count > result.count:
      result = (key: key, count: count)

proc hearts*(thing: Thing): int =
  getInv(thing, ItemHearts)

proc `hearts=`*(thing: Thing, value: int) =
  setInv(thing, ItemHearts, value)

proc resources*(thing: Thing): int =
  getInv(thing, ItemOre)

proc `resources=`*(thing: Thing, value: int) =
  setInv(thing, ItemOre, value)

proc inventoryOre*(agent: Thing): int =
  getInv(agent, ItemOre)

proc `inventoryOre=`*(agent: Thing, value: int) =
  setInv(agent, ItemOre, value)

proc inventoryBar*(agent: Thing): int =
  getInv(agent, ItemBar)

proc `inventoryBar=`*(agent: Thing, value: int) =
  setInv(agent, ItemBar, value)

proc inventoryWater*(agent: Thing): int =
  getInv(agent, ItemWater)

proc `inventoryWater=`*(agent: Thing, value: int) =
  setInv(agent, ItemWater, value)

proc inventoryWheat*(agent: Thing): int =
  getInv(agent, ItemWheat)

proc `inventoryWheat=`*(agent: Thing, value: int) =
  setInv(agent, ItemWheat, value)

proc inventoryWood*(agent: Thing): int =
  getInv(agent, ItemWood)

proc `inventoryWood=`*(agent: Thing, value: int) =
  setInv(agent, ItemWood, value)

proc inventorySpear*(agent: Thing): int =
  getInv(agent, ItemSpear)

proc `inventorySpear=`*(agent: Thing, value: int) =
  setInv(agent, ItemSpear, value)

proc inventoryLantern*(agent: Thing): int =
  getInv(agent, ItemLantern)

proc `inventoryLantern=`*(agent: Thing, value: int) =
  setInv(agent, ItemLantern, value)

proc inventoryArmor*(agent: Thing): int =
  getInv(agent, ItemArmor)

proc `inventoryArmor=`*(agent: Thing, value: int) =
  setInv(agent, ItemArmor, value)

proc inventoryBread*(agent: Thing): int =
  getInv(agent, ItemBread)

proc `inventoryBread=`*(agent: Thing, value: int) =
  setInv(agent, ItemBread, value)
proc createTumor(pos: IVec2, homeSpawner: IVec2, r: var Rand): Thing =
  ## Create a new Tumor seed that can branch once before turning inert
  Thing(
    kind: Tumor,
    pos: pos,
    orientation: Orientation(randIntInclusive(r, 0, 3)),
    homeSpawner: homeSpawner,
    hasClaimedTerritory: false,  # Start mobile, will plant when far enough from others
    turnsAlive: 0                # New tumor hasn't lived any turns yet
  )






include "environment_actions"

include "environment_spawn"

include "environment_step"

# ============== COLOR MANAGEMENT ==============

proc generateEntityColor*(entityType: string, id: int, fallbackColor: Color = color(0.5, 0.5, 0.5, 1.0)): Color =
  ## Unified color generation for all entity types
  ## Uses deterministic palette indexing; no random sampling.
  case entityType:
  of "agent":
    if id >= 0 and id < agentVillageColors.len:
      return agentVillageColors[id]
    let teamId = getTeamId(id)
    if teamId >= 0 and teamId < teamColors.len:
      return teamColors[teamId]
    return fallbackColor
  of "village":
    if id >= 0 and id < teamColors.len:
      return teamColors[id]
    return fallbackColor
  else:
    return fallbackColor

proc getAltarColor*(pos: IVec2): Color =
  ## Get altar color by position, with white fallback.
  ## Falls back to the base tile color so altars start visibly tinted even
  ## before any dynamic color updates run.
  if altarColors.hasKey(pos):
    return altarColors[pos]

  if pos.x >= 0 and pos.x < MapWidth and pos.y >= 0 and pos.y < MapHeight:
    let base = env.baseTileColors[pos.x][pos.y]
    return color(base.r, base.g, base.b, 1.0)

  color(1.0, 1.0, 1.0, 1.0)
