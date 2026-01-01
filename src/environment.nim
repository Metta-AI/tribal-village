import std/tables, vmath, chroma
import rng_compat
import terrain, objects, workshop, common
export terrain, objects, workshop, common


const
  # Map Layout
  MapLayoutRoomsX* = 1
  MapLayoutRoomsY* = 1
  MapBorder* = 4
  MapRoomWidth* = 192  # 16:9 aspect ratio
  MapRoomHeight* = 108
  MapRoomBorder* = 0

  AgentMaxHp* = 5

  # World Objects
  # Eight bases with six agents each -> 48 agents total (divisible by 12 and 16 for batching).
  MapRoomObjectsHouses* = 8
  MapAgentsPerHouse* = 20
  MapRoomObjectsAgents* = MapRoomObjectsHouses * MapAgentsPerHouse  # Agent slots across all villages
  MapRoomObjectsConverters* = 10
  MapRoomObjectsMines* = 20
  MapRoomObjectsWalls* = 30

  # Agent Parameters
  MapObjectAgentMaxInventory* = 5

  # Building Parameters
  MapObjectassemblerInitialHearts* = 5
  MapObjectassemblerCooldown* = 10
  MapObjectassemblerRespawnCost* = 1
  MapObjectassemblerAutoSpawnThreshold* = 5
  MapObjectMineCooldown* = 5
  MapObjectMineInitialResources* = 30
  DoorMaxHearts* = 5

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
    AgentInventoryBatteryLayer = 3
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
    assemblerLayer = 16
    assemblerHeartsLayer = 17  # Hearts for respawning
    assemblerReadyLayer = 18
    TintLayer = 19        # Unified tint layer for all environmental effects
    AgentInventoryBreadLayer = 20  # Bread baked from clay oven


  ThingKind* = enum
    Agent
    Wall
    Mine
    Converter  # Converts ore to batteries
    assembler
    Spawner
    Tumor
    Armory
    Forge
    ClayOven
    WeavingLoom
    Bed
    Chair
    Table
    Statue
    PlantedLantern  # Planted lanterns that spread team colors

  Thing* = ref object
    kind*: ThingKind
    pos*: IVec2
    id*: int
    layer*: int
    hearts*: int  # For assemblers only - used for respawning agents
    resources*: int  # For mines - remaining ore
    cooldown*: int
    frozen*: int

    # Agent:
    agentId*: int
    orientation*: Orientation
    inventoryOre*: int      # Ore from mines
    inventoryBattery*: int  # Batteries from converters
    inventoryWater*: int    # Water from water tiles
    inventoryWheat*: int    # Wheat from wheat tiles
    inventoryWood*: int     # Wood from tree tiles
    inventorySpear*: int    # Spears crafted from forge
    inventoryLantern*: int  # Lanterns from weaving loom (plantable team markers)
    inventoryArmor*: int    # Armor from armory (5-hit protection, tracks remaining uses)
    inventoryBread*: int    # Bread baked from clay oven
    reward*: float32
    hp*: int
    maxHp*: int
    homeassembler*: IVec2      # Position of agent's home assembler for respawning
    # Tumor:
    homeSpawner*: IVec2     # Position of tumor's home spawner
    hasClaimedTerritory*: bool  # Whether this tumor has already branched and is now inert
    turnsAlive*: int            # Number of turns this tumor has been alive

    # PlantedLantern:
    teamId*: int               # Which team this lantern belongs to (for color spreading)
    lanternHealthy*: bool      # Whether lantern is active (not destroyed by tumor)

    # Spawner: (no longer needs assembler targeting for new creep spread behavior)

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
    batteryReward*: float
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
var assemblerColors*: Table[IVec2, Color] = initTable[IVec2, Color]()

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
      of Fertile:
        cell = "f"
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
          of Mine:
            cell = "m"
          of Converter:
            cell = "g"
          of assembler:
            cell = "a"
          of Spawner:
            cell = "t"
          of Tumor:
            cell = "C"
          of Armory:
            cell = "A"
          of Forge:
            cell = "F"
          of ClayOven:
            cell = "O"
          of WeavingLoom:
            cell = "W"
          of Bed:
            cell = "B"
          of Chair:
            cell = "H"
          of Table:
            cell = "T"
          of Statue:
            cell = "S"
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
    env.updateObservations(AgentInventoryOreLayer, agent.pos, agent.inventoryOre)
    env.updateObservations(AgentInventoryBatteryLayer, agent.pos, agent.inventoryBattery)
    env.updateObservations(AgentInventoryWaterLayer, agent.pos, agent.inventoryWater)
    env.updateObservations(AgentInventoryWheatLayer, agent.pos, agent.inventoryWheat)
    env.updateObservations(AgentInventoryWoodLayer, agent.pos, agent.inventoryWood)
    env.updateObservations(AgentInventorySpearLayer, agent.pos, agent.inventorySpear)
    env.updateObservations(AgentInventoryLanternLayer, agent.pos, agent.inventoryLantern)
    env.updateObservations(AgentInventoryArmorLayer, agent.pos, agent.inventoryArmor)
    env.updateObservations(AgentInventoryBreadLayer, agent.pos, agent.inventoryBread)

  # Populate environment object layers.
  for thing in env.things:
    if thing.isNil:
      continue
    case thing.kind
    of Agent:
      discard  # Already handled above.
    of Wall:
      env.updateObservations(WallLayer, thing.pos, 1)
    of Mine:
      env.updateObservations(MineLayer, thing.pos, 1)
      env.updateObservations(MineResourceLayer, thing.pos, thing.resources)
      env.updateObservations(MineReadyLayer, thing.pos, thing.cooldown)
    of Converter:
      env.updateObservations(ConverterLayer, thing.pos, 1)
      env.updateObservations(ConverterReadyLayer, thing.pos, thing.cooldown)
    of assembler:
      env.updateObservations(assemblerLayer, thing.pos, 1)
      env.updateObservations(assemblerHeartsLayer, thing.pos, thing.hearts)
      env.updateObservations(assemblerReadyLayer, thing.pos, thing.cooldown)
    of Spawner:
      discard  # No dedicated observation layer for spawners.
    of Tumor:
      env.updateObservations(AgentLayer, thing.pos, 255)
    of Armory, Forge, ClayOven, WeavingLoom, Bed, Chair, Table, Statue, PlantedLantern:
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
  ## Restore a tile to the default floor color
  env.tileColors[pos.x][pos.y] = BaseTileColorDefault
  env.baseTileColors[pos.x][pos.y] = BaseTileColorDefault

proc clearDoors(env: Environment) =
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      env.doorTeams[x][y] = -1
      env.doorHearts[x][y] = 0



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






include "environment/actions"

include "environment/spawn"

include "environment/step"

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

proc getassemblerColor*(pos: IVec2): Color =
  ## Get assembler color by position, with white fallback.
  ## Falls back to the base tile color so assemblers start visibly tinted even
  ## before any dynamic color updates run.
  if assemblerColors.hasKey(pos):
    return assemblerColors[pos]

  if pos.x >= 0 and pos.x < MapWidth and pos.y >= 0 and pos.y < MapHeight:
    let base = env.baseTileColors[pos.x][pos.y]
    return color(base.r, base.g, base.b, 1.0)

  color(1.0, 1.0, 1.0, 1.0)
