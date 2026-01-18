# This file is included by src/environment.nim
import std/math
import replay_writer
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

const
  ResourceGround = {TerrainEmpty, TerrainGrass, TerrainSand, TerrainSnow, TerrainDune}
  TreeGround = {TerrainEmpty, TerrainGrass, TerrainSand, TerrainDune}
  TradingHubSize = 15
  TradingHubTint = TileColor(r: 0.58, g: 0.58, b: 0.58, intensity: 1.0)

proc randInteriorPos(r: var Rand, pad: int): IVec2 =
  let x = randIntInclusive(r, MapBorder + pad, MapWidth - MapBorder - pad)
  let y = randIntInclusive(r, MapBorder + pad, MapHeight - MapBorder - pad)
  ivec2(x.int32, y.int32)

proc addResourceNode(env: Environment, pos: IVec2, kind: ThingKind,
                     item: ItemKey, amount: int = ResourceNodeInitial) =
  if not env.isEmpty(pos) or not isNil(env.getBackgroundThing(pos)) or env.hasDoor(pos):
    return
  let node = Thing(kind: kind, pos: pos)
  node.inventory = emptyInventory()
  if item != ItemNone and amount > 0:
    setInv(node, item, amount)
  env.add(node)

proc placeResourceCluster(env: Environment, centerX, centerY: int, size: int,
                          baseDensity: float, falloffRate: float, kind: ThingKind,
                          item: ItemKey, allowedTerrain: set[TerrainType], r: var Rand,
                          allowedBiomes: set[BiomeType] = {}) =
  let radius = max(1, (size.float / 2.0).int)
  for dx in -radius .. radius:
    for dy in -radius .. radius:
      let x = centerX + dx
      let y = centerY + dy
      if x < 0 or x >= MapWidth or y < 0 or y >= MapHeight:
        continue
      if env.terrain[x][y] notin allowedTerrain:
        continue
      if allowedBiomes.card > 0 and env.biomes[x][y] notin allowedBiomes:
        continue
      let dist = sqrt((dx * dx + dy * dy).float)
      if dist > radius.float:
        continue
      let chance = baseDensity - (dist / radius.float) * falloffRate
      if randChance(r, chance):
        addResourceNode(env, ivec2(x.int32, y.int32), kind, item)

proc placeBiomeResourceClusters(env: Environment, r: var Rand, count: int,
                                sizeMin, sizeMax: int, baseDensity, falloffRate: float,
                                kind: ThingKind, item: ItemKey, allowedBiome: BiomeType) =
  for _ in 0 ..< count:
    let pos = randInteriorPos(r, 2)
    let size = randIntInclusive(r, sizeMin, sizeMax)
    placeResourceCluster(env, pos.x.int, pos.y.int, size, baseDensity, falloffRate,
      kind, item, ResourceGround, r, allowedBiomes = {allowedBiome})

proc applyBiomeElevation(env: Environment) =
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      if env.terrain[x][y] in {Water, Bridge}:
        env.elevation[x][y] = 0
        continue
      let biome = env.biomes[x][y]
      env.elevation[x][y] =
        if biome == BiomeSwampType:
          -1
        elif biome == BiomeSnowType:
          1
        else:
          0

proc applyCliffRamps(env: Environment) =
  var cliffCount = 0
  let dirs = [ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0)]
  for x in MapBorder ..< MapWidth - MapBorder:
    for y in MapBorder ..< MapHeight - MapBorder:
      if env.terrain[x][y] == Water or env.terrain[x][y] == Road:
        continue
      let elev = env.elevation[x][y]
      for d in dirs:
        let nx = x + d.x.int
        let ny = y + d.y.int
        if nx < MapBorder or nx >= MapWidth - MapBorder or
           ny < MapBorder or ny >= MapHeight - MapBorder:
          continue
        let nelev = env.elevation[nx][ny]
        if nelev <= elev:
          continue
        if env.terrain[nx][ny] == Water or env.terrain[nx][ny] == Road:
          continue
        inc cliffCount
        if cliffCount mod 10 != 0:
          continue
        env.terrain[x][y] = Road
        env.terrain[nx][ny] = Road

proc applyCliffs(env: Environment) =
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      if env.terrain[x][y] == Water:
        continue
      let elev = env.elevation[x][y]
      proc isLower(dx, dy: int): bool =
        let nx = x + dx
        let ny = y + dy
        if nx < 0 or nx >= MapWidth or ny < 0 or ny >= MapHeight:
          return false
        env.elevation[nx][ny] < elev

      let lowN = isLower(0, -1)
      let lowE = isLower(1, 0)
      let lowS = isLower(0, 1)
      let lowW = isLower(-1, 0)
      let lowNE = isLower(1, -1)
      let lowSE = isLower(1, 1)
      let lowSW = isLower(-1, 1)
      let lowNW = isLower(-1, -1)

      let cardinalCount =
        (if lowN: 1 else: 0) +
        (if lowE: 1 else: 0) +
        (if lowS: 1 else: 0) +
        (if lowW: 1 else: 0)
      let diagonalCount =
        (if lowNE: 1 else: 0) +
        (if lowSE: 1 else: 0) +
        (if lowSW: 1 else: 0) +
        (if lowNW: 1 else: 0)

      var kind: ThingKind
      var hasCliff = false

      if cardinalCount == 2:
        if lowN and lowE:
          kind = CliffCornerInNE
          hasCliff = true
        elif lowE and lowS:
          kind = CliffCornerInSE
          hasCliff = true
        elif lowS and lowW:
          kind = CliffCornerInSW
          hasCliff = true
        elif lowW and lowN:
          kind = CliffCornerInNW
          hasCliff = true
      elif cardinalCount == 1:
        if lowN:
          kind = CliffEdgeN
          hasCliff = true
        elif lowE:
          kind = CliffEdgeE
          hasCliff = true
        elif lowS:
          kind = CliffEdgeS
          hasCliff = true
        elif lowW:
          kind = CliffEdgeW
          hasCliff = true
      elif cardinalCount == 0 and diagonalCount == 1:
        if lowNE:
          kind = CliffCornerOutNE
          hasCliff = true
        elif lowSE:
          kind = CliffCornerOutSE
          hasCliff = true
        elif lowSW:
          kind = CliffCornerOutSW
          hasCliff = true
        elif lowNW:
          kind = CliffCornerOutNW
          hasCliff = true

      if hasCliff:
        env.add(Thing(kind: kind, pos: ivec2(x.int32, y.int32)))

proc placeTradingHub(env: Environment, r: var Rand) =
  let centerX = MapWidth div 2
  let centerY = MapHeight div 2
  let half = TradingHubSize div 2
  let x0 = centerX - half
  let x1 = centerX + half
  let y0 = centerY - half
  let y1 = centerY + half

  proc clearThings(pos: IVec2) =
    let existing = env.getThing(pos)
    if not isNil(existing):
      removeThing(env, existing)
    let background = env.getBackgroundThing(pos)
    if not isNil(background):
      removeThing(env, background)

  for x in x0 .. x1:
    for y in y0 .. y1:
      if x < 0 or x >= MapWidth or y < 0 or y >= MapHeight:
        continue
      let pos = ivec2(x.int32, y.int32)
      clearThings(pos)
      env.terrain[x][y] = Empty
      env.resetTileColor(pos)
      env.baseTintColors[x][y] = TradingHubTint
      env.tintLocked[x][y] = true

  proc paintRoad(x, y: int) =
    if x < MapBorder + 1 or x >= MapWidth - MapBorder - 1 or
        y < MapBorder + 1 or y >= MapHeight - MapBorder - 1:
      return
    let pos = ivec2(x.int32, y.int32)
    if env.terrain[x][y] == Water:
      env.terrain[x][y] = Bridge
    else:
      env.terrain[x][y] = Road
    env.resetTileColor(pos)

  proc extendRoad(startX, startY, dx, dy: int) =
    var x = startX
    var y = startY
    while x >= MapBorder + 1 and x < MapWidth - MapBorder - 1 and
        y >= MapBorder + 1 and y < MapHeight - MapBorder - 1:
      let outsideHub = x < x0 or x > x1 or y < y0 or y > y1
      let existing = env.terrain[x][y]
      paintRoad(x, y)
      if outsideHub and existing in {Road, Bridge}:
        break
      x += dx
      y += dy

  let roadX = centerX
  extendRoad(roadX, centerY, 1, 0)
  extendRoad(roadX, centerY, -1, 0)
  extendRoad(roadX, centerY, 0, 1)
  extendRoad(roadX, centerY, 0, -1)
  proc isHubRoad(x, y: int): bool =
    x == roadX or y == centerY

  proc canPlaceHubThing(x, y: int): bool =
    if x < MapBorder + 1 or x >= MapWidth - MapBorder - 1 or
        y < MapBorder + 1 or y >= MapHeight - MapBorder - 1:
      return false
    if env.terrain[x][y] in {Water, Road, Bridge}:
      return false
    if isHubRoad(x, y):
      return false
    let pos = ivec2(x.int32, y.int32)
    if not env.isEmpty(pos):
      return false
    if not isNil(env.getBackgroundThing(pos)) or env.hasDoor(pos):
      return false
    true

  var wallPositions: seq[IVec2] = @[]
  proc tryAddWall(x, y: int) =
    if not canPlaceHubThing(x, y):
      return
    let pos = ivec2(x.int32, y.int32)
    env.add(Thing(kind: Wall, pos: pos, teamId: -1))
    wallPositions.add(pos)

  let wallMinX = max(MapBorder + 1, x0 - 2)
  let wallMaxX = min(MapWidth - MapBorder - 2, x1 + 2)
  let wallMinY = max(MapBorder + 1, y0 - 2)
  let wallMaxY = min(MapHeight - MapBorder - 2, y1 + 2)
  let wallJitter = 2
  let wallChance = 0.65

  for x in wallMinX .. wallMaxX:
    if randChance(r, wallChance):
      let jitter = randIntInclusive(r, -wallJitter, wallJitter)
      tryAddWall(x, max(wallMinY, min(wallMaxY, y0 - 1 + jitter)))
    if randChance(r, wallChance):
      let jitter = randIntInclusive(r, -wallJitter, wallJitter)
      tryAddWall(x, max(wallMinY, min(wallMaxY, y1 + 1 + jitter)))

  for y in wallMinY .. wallMaxY:
    if randChance(r, wallChance):
      let jitter = randIntInclusive(r, -wallJitter, wallJitter)
      tryAddWall(max(wallMinX, min(wallMaxX, x0 - 1 + jitter)), y)
    if randChance(r, wallChance):
      let jitter = randIntInclusive(r, -wallJitter, wallJitter)
      tryAddWall(max(wallMinX, min(wallMaxX, x1 + 1 + jitter)), y)

  let spurCount = randIntInclusive(r, 6, 10)
  let spurDirs = [ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1)]
  for _ in 0 ..< spurCount:
    let startX = randIntInclusive(r, x0 + 1, x1 - 1)
    let startY = randIntInclusive(r, y0 + 1, y1 - 1)
    if isHubRoad(startX, startY):
      continue
    let dir = spurDirs[randIntInclusive(r, 0, spurDirs.len - 1)]
    let length = randIntInclusive(r, 2, 4)
    var pos = ivec2(startX.int32, startY.int32)
    for _ in 0 ..< length:
      tryAddWall(pos.x.int, pos.y.int)
      pos = pos + dir

  var towerSlots = min(4, wallPositions.len)
  while towerSlots > 0 and wallPositions.len > 0:
    let idx = randIntInclusive(r, 0, wallPositions.len - 1)
    let pos = wallPositions[idx]
    let wallThing = env.getThing(pos)
    if not isNil(wallThing) and wallThing.kind == Wall:
      removeThing(env, wallThing)
      env.add(Thing(kind: GuardTower, pos: pos, teamId: -1))
      dec towerSlots
    wallPositions[idx] = wallPositions[^1]
    wallPositions.setLen(wallPositions.len - 1)

  let center = ivec2(centerX.int32, centerY.int32)
  env.add(Thing(kind: Castle, pos: center, teamId: -1))
  var hubBuildings = @[
    Market, Market, Market, Outpost, Blacksmith, ClayOven, WeavingLoom,
    Barracks, ArcheryRange, Stable, SiegeWorkshop, MangonelWorkshop,
    Monastery, University, House, House, Granary, Mill,
    LumberCamp, Quarry, MiningCamp, Barrel
  ]
  for i in countdown(hubBuildings.len - 1, 1):
    let j = randIntInclusive(r, 0, i)
    swap(hubBuildings[i], hubBuildings[j])
  var placed = 0
  let mainTarget = min(hubBuildings.len, randIntInclusive(r, 16, 20))
  for kind in hubBuildings:
    if placed >= mainTarget:
      break
    var attempts = 0
    var placedHere = false
    while attempts < 80 and not placedHere:
      inc attempts
      let x = randIntInclusive(r, x0 + 1, x1 - 1)
      let y = randIntInclusive(r, y0 + 1, y1 - 1)
      if x == centerX or y == centerY:
        continue
      let pos = ivec2(x.int32, y.int32)
      if not canPlaceHubThing(x, y):
        continue
      if abs(x - centerX) <= 1 and abs(y - centerY) <= 1:
        continue
      let building = Thing(kind: kind, pos: pos, teamId: -1)
      let capacity = buildingBarrelCapacity(kind)
      if capacity > 0:
        building.barrelCapacity = capacity
      env.add(building)
      inc placed
      placedHere = true

  let minorPool = [House, House, House, Barrel, Barrel, Outpost, Market, Granary, Mill]
  let extraTarget = randIntInclusive(r, 10, 18)
  var extraPlaced = 0
  var extraAttempts = 0
  while extraPlaced < extraTarget and extraAttempts < extraTarget * 60:
    inc extraAttempts
    let x = randIntInclusive(r, x0 + 1, x1 - 1)
    let y = randIntInclusive(r, y0 + 1, y1 - 1)
    if not canPlaceHubThing(x, y):
      continue
    if abs(x - centerX) <= 1 and abs(y - centerY) <= 1:
      continue
    let kind = minorPool[randIntInclusive(r, 0, minorPool.len - 1)]
    let building = Thing(kind: kind, pos: ivec2(x.int32, y.int32), teamId: -1)
    let capacity = buildingBarrelCapacity(kind)
    if capacity > 0:
      building.barrelCapacity = capacity
    env.add(building)
    inc extraPlaced

proc init(env: Environment) =
  inc env.mapGeneration
  # Use current time for random seed to get different maps each time
  let seed = int(nowSeconds() * 1000)
  var r = initRand(seed)

  env.thingsByKind = default(array[ThingKind, seq[Thing]])

  # Initialize tile colors to base terrain colors (neutral gray-brown)
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      env.baseTintColors[x][y] = BaseTileColorDefault
      env.computedTintColors[x][y] = TileColor(r: 0, g: 0, b: 0, intensity: 0)

  # Clear background grid (non-blocking things like doors and cliffs)
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      env.backgroundGrid[x][y] = nil
      env.elevation[x][y] = 0

  # Reset team stockpiles
  env.teamStockpiles = default(array[MapRoomObjectsHouses, TeamStockpile])

  # Initialize active tiles tracking
  env.activeTiles.positions.setLen(0)
  env.activeTiles.flags = default(array[MapWidth, array[MapHeight, bool]])
  env.tumorActiveTiles.positions.setLen(0)
  env.tumorActiveTiles.flags = default(array[MapWidth, array[MapHeight, bool]])
  env.tumorTintMods = default(array[MapWidth, array[MapHeight, TintModification]])
  env.tintStrength = default(array[MapWidth, array[MapHeight, int32]])
  env.tumorStrength = default(array[MapWidth, array[MapHeight, int32]])
  env.tintLocked = default(array[MapWidth, array[MapHeight, bool]])

  # Clear action tints
  env.actionTintCountdown = default(ActionTintCountdown)
  env.actionTintColor = default(ActionTintColor)
  env.actionTintFlags = default(ActionTintFlags)
  env.actionTintCode = default(ActionTintCode)
  env.actionTintPositions.setLen(0)
  env.shieldCountdown = default(array[MapAgents, int8])

  # Initialize base terrain and biomes (dry pass).
  initTerrain(env.terrain, env.biomes, MapWidth, MapHeight, MapBorder, seed)
  # Water features override biome terrain before elevation/cliffs.
  applySwampWater(env.terrain, env.biomes, MapWidth, MapHeight, MapBorder, r, BiomeSwampConfig())
  env.terrain.generateRiver(MapWidth, MapHeight, MapBorder, r)
  env.applyBiomeElevation()
  env.applyCliffRamps()
  env.applyCliffs()
  env.applyBiomeBaseColors()

  # Resource nodes are spawned as Things later; base terrain stays walkable.

  # Convert city blocks into walls (roads remain passable).
  for x in MapBorder ..< MapWidth - MapBorder:
    for y in MapBorder ..< MapHeight - MapBorder:
      if env.biomes[x][y] != BiomeCityType:
        continue
      if env.terrain[x][y] != BiomeCityBlockTerrain:
        continue
      let pos = ivec2(x.int32, y.int32)
      if not isNil(env.getBackgroundThing(pos)):
        continue
      if env.hasDoor(pos):
        continue
      let existing = env.getThing(pos)
      if not isNil(existing):
        if existing.kind in {Tree}:
          removeThing(env, existing)
        else:
          continue
      env.terrain[x][y] = Empty
      env.add(Thing(kind: Wall, pos: pos))

  # Add sparse dungeon walls using procedural dungeon masks.
  if UseDungeonZones:
    let dungeonKinds = [DungeonMaze, DungeonRadial]
    var count = zoneCount(MapWidth * MapHeight, DungeonZoneDivisor, DungeonZoneMinCount, DungeonZoneMaxCount)
    if UseSequentialDungeonZones:
      count = max(count, dungeonKinds.len)
    var dungeonWalls: MaskGrid
    dungeonWalls.clearMask(MapWidth, MapHeight)
    var seqIdx = randIntInclusive(r, 0, dungeonKinds.len - 1)
    for zone in evenlyDistributedZones(r, MapWidth, MapHeight, MapBorder, count, DungeonZoneMaxFraction):
      let x0 = max(MapBorder, zone.x)
      let y0 = max(MapBorder, zone.y)
      let x1 = min(MapWidth - MapBorder, zone.x + zone.w)
      let y1 = min(MapHeight - MapBorder, zone.y + zone.h)

      var zoneMask: MaskGrid
      buildZoneBlobMask(zoneMask, MapWidth, MapHeight, MapBorder, zone, r)

      # Tint the dungeon zone background with a soft edge blend.
      let dungeonBlendDepth = 4
      for x in x0 ..< x1:
        for y in y0 ..< y1:
          if not zoneMask[x][y]:
            continue
          env.biomes[x][y] = BiomeDungeonType
          let edge = maskEdgeDistance(zoneMask, MapWidth, MapHeight, x, y, dungeonBlendDepth)
          let t = if dungeonBlendDepth <= 0: 1.0'f32 else:
            min(1.0'f32, max(0.0'f32, edge.float32 / dungeonBlendDepth.float32))
          let dungeonColor = biomeBaseColor(BiomeDungeonType)
          let base = env.baseTintColors[x][y]
          let tClamped = max(0.0'f32, min(1.0'f32, t))
          env.baseTintColors[x][y] = TileColor(
            r: base.r * (1.0 - tClamped) + dungeonColor.r * tClamped,
            g: base.g * (1.0 - tClamped) + dungeonColor.g * tClamped,
            b: base.b * (1.0 - tClamped) + dungeonColor.b * tClamped,
            intensity: base.intensity * (1.0 - tClamped) + dungeonColor.intensity * tClamped
          )
      var mask: MaskGrid
      let dungeonKind = if UseSequentialDungeonZones:
        inc seqIdx
        dungeonKinds[(seqIdx - 1) mod dungeonKinds.len]
      else:
        if randFloat(r) * 1.6 <= 1.0:
          DungeonMaze
        else:
          DungeonRadial
      case dungeonKind:
      of DungeonMaze:
        buildDungeonMazeMask(mask, MapWidth, MapHeight, zone.x, zone.y, zone.w, zone.h, r, DungeonMazeConfig())
      of DungeonRadial:
        buildDungeonRadialMask(mask, MapWidth, MapHeight, zone.x, zone.y, zone.w, zone.h, r, DungeonRadialConfig())

      for x in x0 ..< x1:
        for y in y0 ..< y1:
          if not zoneMask[x][y]:
            continue
          if (if dungeonKind == DungeonRadial:
                not mask[x][y]  # radial mask encodes corridors; invert for walls
              else:
                mask[x][y]) and not isBlockedTerrain(env.terrain[x][y]):
            dungeonWalls[x][y] = true

    # Soften dungeon edges so they blend into surrounding biomes.
    ditherEdges(dungeonWalls, MapWidth, MapHeight, 0.08, 3, r)

    for x in MapBorder ..< MapWidth - MapBorder:
      for y in MapBorder ..< MapHeight - MapBorder:
        if not dungeonWalls[x][y]:
          continue
        if env.terrain[x][y] == Water:
          continue
        let pos = ivec2(x.int32, y.int32)
        if not isNil(env.getBackgroundThing(pos)):
          continue
        if env.hasDoor(pos):
          continue
        let existing = env.getThing(pos)
        if not isNil(existing):
          if existing.kind in {Tree}:
            removeThing(env, existing)
          else:
            continue
        env.add(Thing(kind: Wall, pos: pos))

  if MapBorder > 0:
    proc addBorderWall(pos: IVec2) =
      if not isNil(env.getBackgroundThing(pos)):
        return
      env.add(Thing(kind: Wall, pos: pos))
    for x in 0 ..< MapWidth:
      for j in 0 ..< MapBorder:
        addBorderWall(ivec2(x, j))
        addBorderWall(ivec2(x, MapHeight - j - 1))
    for y in 0 ..< MapHeight:
      for j in 0 ..< MapBorder:
        addBorderWall(ivec2(j, y))
        addBorderWall(ivec2(MapWidth - j - 1, y))

  # Place neutral trading hub near map center before villages.
  env.placeTradingHub(r)

  # Agents will now spawn with their villages below
  # Clear and prepare village colors arrays (use Environment fields)
  env.agentColors.setLen(MapRoomObjectsAgents)  # Allocate space for all agents
  env.teamColors.setLen(0)  # Clear team colors
  env.altarColors.clear()  # Clear altar colors from previous game
  # Spawn villages with altars, town centers, and associated agents (tribes)
  let numVillages = MapRoomObjectsHouses
  var totalAgentsSpawned = 0
  let villageAgentCap = MapRoomObjectsHouses * MapAgentsPerVillage
  var villageCenters: seq[IVec2] = @[]
  proc placeStartingTownCenter(center: IVec2, teamId: int, r: var Rand): IVec2 =
    var candidates: seq[IVec2] = @[]
    for dx in -3 .. 3:
      for dy in -3 .. 3:
        if dx == 0 and dy == 0:
          continue
        let dist = max(abs(dx), abs(dy))
        if dist < 1 or dist > 3:
          continue
        let pos = center + ivec2(dx.int32, dy.int32)
        if pos == center + ivec2(2, -2) or pos == center + ivec2(2, 2) or
            pos == center + ivec2(-2, 2) or pos == center + ivec2(-2, -2):
          continue
        candidates.add(pos)
    for i in countdown(candidates.len - 1, 1):
      let j = randIntInclusive(r, 0, i)
      swap(candidates[i], candidates[j])
    for pos in candidates:
      if not isValidPos(pos):
        continue
      if env.terrain[pos.x][pos.y] == Water:
        continue
      let existing = env.getThing(pos)
      if not isNil(existing):
        if existing.kind in {Tree}:
          removeThing(env, existing)
        else:
          continue
      if env.hasDoor(pos):
        continue
      if not env.isEmpty(pos):
        continue
      env.add(Thing(kind: TownCenter, pos: pos, teamId: teamId))
      return pos
    # Fallback: place directly east if possible.
    let fallback = center + ivec2(1, 0)
    if isValidPos(fallback) and env.isEmpty(fallback) and env.terrain[fallback.x][fallback.y] != Water and not env.hasDoor(fallback):
      env.add(Thing(kind: TownCenter, pos: fallback, teamId: teamId))
      return fallback
    center
  proc placeStartingRoads(center: IVec2, teamId: int, r: var Rand) =
    proc placeRoad(pos: IVec2) =
      if not isValidPos(pos):
        return
      if env.terrain[pos.x][pos.y] == Water:
        return
      if env.hasDoor(pos):
        return
      let existing = env.getThing(pos)
      if not isNil(existing):
        if existing.kind in {Tree}:
          removeThing(env, existing)
        else:
          return
      if env.terrain[pos.x][pos.y] != Road:
        env.terrain[pos.x][pos.y] = Road
        env.resetTileColor(pos)

    var anchors: seq[IVec2] = @[center]
    for thing in env.things:
      if thing.teamId != teamId:
        continue
      if thing.kind notin {TownCenter, House, Granary, LumberCamp, Quarry, MiningCamp, Mill}:
        continue
      let dist = max(abs(thing.pos.x - center.x), abs(thing.pos.y - center.y))
      if dist <= 7:
        anchors.add(thing.pos)

    for anchor in anchors:
      if anchor == center:
        continue
      var pos = center
      while pos.x != anchor.x:
        let delta = anchor.x - pos.x
        pos.x += (if delta < 0: -1 elif delta > 0: 1 else: 0)
        placeRoad(pos)
      while pos.y != anchor.y:
        let delta = anchor.y - pos.y
        pos.y += (if delta < 0: -1 elif delta > 0: 1 else: 0)
        placeRoad(pos)

    var maxEast = 0
    var maxWest = 0
    var maxSouth = 0
    var maxNorth = 0
    for anchor in anchors:
      let dx = (anchor.x - center.x).int
      let dy = (anchor.y - center.y).int
      if dx > maxEast: maxEast = dx
      if dx < 0 and -dx > maxWest: maxWest = -dx
      if dy > maxSouth: maxSouth = dy
      if dy < 0 and -dy > maxNorth: maxNorth = -dy

    for (dir, baseDist) in [(ivec2(1, 0), maxEast), (ivec2(-1, 0), maxWest),
                            (ivec2(0, 1), maxSouth), (ivec2(0, -1), maxNorth)]:
      let extra = randIntInclusive(r, 3, 4)
      for step in 1 .. baseDist + extra:
        let pos = center + ivec2(dir.x.int32 * step.int32, dir.y.int32 * step.int32)
        placeRoad(pos)

  proc placeStartingResourceBuildings(center: IVec2, teamId: int) =
    for entry in [
      (offset: ivec2(2, -2), kind: LumberCamp, res: ResourceWood),   # Lumber Camp
      (offset: ivec2(2, 2), kind: Granary, res: ResourceFood),       # Granary
      (offset: ivec2(-2, 2), kind: Quarry, res: ResourceStone),      # Quarry
      (offset: ivec2(-2, -2), kind: MiningCamp, res: ResourceGold)   # Mining Camp
    ]:
      var placed = false
      for radius in 0 .. 2:
        for dx in -radius .. radius:
          for dy in -radius .. radius:
            if radius > 0 and max(abs(dx), abs(dy)) != radius:
              continue
            let pos = center + entry.offset + ivec2(dx.int32, dy.int32)
            if not isValidPos(pos):
              continue
            if env.terrain[pos.x][pos.y] == Water or isTileFrozen(pos, env):
              continue
            if env.hasDoor(pos):
              continue
            let existing = env.getThing(pos)
            if not isNil(existing):
              if existing.kind in {Tree}:
                removeThing(env, existing)
              else:
                continue
            if not env.isEmpty(pos):
              continue
            let building = Thing(
              kind: entry.kind,
              pos: pos,
              teamId: teamId
            )
            let capacity = buildingBarrelCapacity(entry.kind)
            if capacity > 0:
              building.barrelCapacity = capacity
            env.add(building)
            env.teamStockpiles[teamId].counts[entry.res] =
              max(env.teamStockpiles[teamId].counts[entry.res], 5)
            placed = true
            break
          if placed: break
        if placed: break

  proc placeStartingResourceNodes(center: IVec2, r: var Rand) =
    proc findSpot(r: var Rand, minRadius, maxRadius: int, allowedTerrain: set[TerrainType]): IVec2 =
      for attempt in 0 ..< 40:
        let dx = randIntInclusive(r, -maxRadius, maxRadius)
        let dy = randIntInclusive(r, -maxRadius, maxRadius)
        let dist = max(abs(dx), abs(dy))
        if dist < minRadius or dist > maxRadius:
          continue
        let pos = center + ivec2(dx.int32, dy.int32)
        if not isValidPos(pos):
          continue
        if env.terrain[pos.x][pos.y] notin allowedTerrain:
          continue
        if env.hasDoor(pos):
          continue
        if not env.isEmpty(pos) or not isNil(env.getBackgroundThing(pos)):
          continue
        return pos
      for attempt in 0 ..< 40:
        let radius = maxRadius + 4
        let dx = randIntInclusive(r, -radius, radius)
        let dy = randIntInclusive(r, -radius, radius)
        let dist = max(abs(dx), abs(dy))
        if dist < minRadius or dist > radius:
          continue
        let pos = center + ivec2(dx.int32, dy.int32)
        if not isValidPos(pos):
          continue
        if env.terrain[pos.x][pos.y] notin allowedTerrain:
          continue
        if env.hasDoor(pos):
          continue
        if not env.isEmpty(pos) or not isNil(env.getBackgroundThing(pos)):
          continue
        return pos
      ivec2(-1, -1)

    proc placeDepositCluster(r: var Rand, kind: ThingKind, item: ItemKey, count: int,
                             minRadius, maxRadius: int) =
      var spot = findSpot(r, minRadius, maxRadius, ResourceGround)
      if spot.x < 0:
        spot = r.randomEmptyPos(env)
      addResourceNode(env, spot, kind, item, MineDepositAmount)
      if count <= 1:
        return
      var candidates = env.findEmptyPositionsAround(spot, 2)
      let toPlace = min(count - 1, candidates.len)
      for i in 0 ..< toPlace:
        addResourceNode(env, candidates[i], kind, item, MineDepositAmount)

    proc placeMagmaCluster(r: var Rand, minRadius, maxRadius: int) =
      var spot = findSpot(r, minRadius, maxRadius, ResourceGround)
      if spot.x < 0:
        spot = r.randomEmptyPos(env)
      if env.isEmpty(spot) and isNil(env.getBackgroundThing(spot)) and not env.hasDoor(spot) and
          env.terrain[spot.x][spot.y] in ResourceGround:
        env.add(Thing(kind: Magma, pos: spot))
      var candidates = env.findEmptyPositionsAround(spot, 2)
      let extraCount = randIntInclusive(r, 1, 2)
      let toPlace = min(extraCount, candidates.len)
      for i in 0 ..< toPlace:
        let pos = candidates[i]
        if env.isEmpty(pos) and isNil(env.getBackgroundThing(pos)) and not env.hasDoor(pos) and
            env.terrain[pos.x][pos.y] in ResourceGround:
          env.add(Thing(kind: Magma, pos: pos))

    var woodSpot = findSpot(r, 6, 12, ResourceGround)
    if woodSpot.x < 0:
      woodSpot = r.randomEmptyPos(env)
    placeResourceCluster(env, woodSpot.x, woodSpot.y,
      randIntInclusive(r, 5, 8), 0.85, 0.4, Tree, ItemWood, ResourceGround, r)

    var foodSpot = findSpot(r, 5, 11, ResourceGround)
    if foodSpot.x < 0:
      foodSpot = r.randomEmptyPos(env)
    placeResourceCluster(env, foodSpot.x, foodSpot.y,
      randIntInclusive(r, 4, 7), 0.85, 0.35, Wheat, ItemWheat, ResourceGround, r)

    placeDepositCluster(r, Stone, ItemStone, randIntInclusive(r, 3, 4), 7, 14)
    placeDepositCluster(r, Gold, ItemGold, randIntInclusive(r, 3, 4), 8, 15)
    placeMagmaCluster(r, 9, 16)

  proc placeStartingHouses(center: IVec2, teamId: int, r: var Rand) =
    let count = randIntInclusive(r, 4, 5)
    var placed = 0
    var attempts = 0
    while placed < count and attempts < 120:
      inc attempts
      let dx = randIntInclusive(r, -5, 5)
      let dy = randIntInclusive(r, -5, 5)
      let dist = max(abs(dx), abs(dy))
      if dist < 3 or dist > 5:
        continue
      let pos = center + ivec2(dx.int32, dy.int32)
      if not isValidPos(pos):
        continue
      if env.hasDoor(pos) or not env.isEmpty(pos):
        continue
      if env.terrain[pos.x][pos.y] == Water or isTileFrozen(pos, env):
        continue
      env.add(Thing(
        kind: House,
        pos: pos,
        teamId: teamId
      ))
      inc placed
  doAssert WarmVillagePalette.len >= numVillages,
    "WarmVillagePalette must cover all base colors without reuse."
  for i in 0 ..< numVillages:
    let villageStruct = block:
      ## Small town starter: altar + town center, no walls.
      const size = 7
      const radius = 3
      let center = ivec2(radius, radius)
      var layout: seq[seq[char]] = newSeq[seq[char]](size)
      for y in 0 ..< size:
        layout[y] = newSeq[char](size)
        for x in 0 ..< size:
          layout[y][x] = ' '

      # Clear a small plaza around the altar so the start isn't cluttered.
      for y in 0 ..< size:
        for x in 0 ..< size:
          if abs(x - center.x) + abs(y - center.y) <= 2:
            layout[y][x] = StructureFloorChar

      Structure(
        width: size,
        height: size,
        centerPos: center,
        layout: layout
      )
    var placed = false
    var placementPosition: IVec2

    # Simple random placement with collision avoidance
    for attempt in 0 ..< 200:
      let candidatePos = r.randomEmptyPos(env)
      # Check if position has enough space for the village footprint
      var canPlace = true
      for dy in 0 ..< villageStruct.height:
        for dx in 0 ..< villageStruct.width:
          let checkX = candidatePos.x + dx
          let checkY = candidatePos.y + dy
          if checkX >= MapWidth or checkY >= MapHeight or
             not env.isEmpty(ivec2(checkX, checkY)) or
             isBlockedTerrain(env.terrain[checkX][checkY]):
            canPlace = false
            break
        if not canPlace: break

      # Keep villages spaced apart (Chebyshev) to avoid crowding
      if canPlace:
        const MinVillageSpacing = DefaultMinVillageSpacing
        let candidateCenter = candidatePos + villageStruct.centerPos
        for c in villageCenters:
          let dx = abs(c.x - candidateCenter.x)
          let dy = abs(c.y - candidateCenter.y)
          if max(dx, dy) < MinVillageSpacing:
            canPlace = false
            break

      if canPlace:
        placementPosition = candidatePos
        placed = true
        break

    if placed:
      let elements = getStructureElements(villageStruct, placementPosition)

      # Clear terrain within the village area to create a clearing
      for dy in 0 ..< villageStruct.height:
        for dx in 0 ..< villageStruct.width:
          let clearX = placementPosition.x + dx
          let clearY = placementPosition.y + dy
          if clearX >= 0 and clearX < MapWidth and clearY >= 0 and clearY < MapHeight:
            if dy < villageStruct.layout.len and dx < villageStruct.layout[dy].len:
              if villageStruct.layout[dy][dx] == ' ':
                continue
            # Clear any terrain features (wheat, trees) but keep blocked terrain
            if not isBlockedTerrain(env.terrain[clearX][clearY]):
              env.terrain[clearX][clearY] = Empty
              env.resetTileColor(ivec2(clearX.int32, clearY.int32))

      # Generate a distinct warm color for this village (avoid cool/blue hues)
      let villageColor = WarmVillagePalette[i]
      env.teamColors.add(villageColor)
      let teamId = env.teamColors.len - 1

      # Spawn agent slots for this village (six active, the rest dormant)
      let agentsForThisVillage = min(MapAgentsPerVillage, villageAgentCap - totalAgentsSpawned)

      # Add the altar with initial hearts and village bounds
      let altar = Thing(
        kind: Altar,
        pos: elements.center,
        teamId: teamId
      )
      altar.inventory = emptyInventory()
      altar.hearts = MapObjectAltarInitialHearts
      env.add(altar)
      villageCenters.add(elements.center)
      env.altarColors[elements.center] = villageColor  # Associate altar position with village color

      discard placeStartingTownCenter(elements.center, teamId, r)

      # Initialize base colors for village tiles to team color
      for dx in 0 ..< villageStruct.width:
        for dy in 0 ..< villageStruct.height:
          let tileX = placementPosition.x + dx
          let tileY = placementPosition.y + dy
          if tileX >= 0 and tileX < MapWidth and tileY >= 0 and tileY < MapHeight:
            if dy < villageStruct.layout.len and dx < villageStruct.layout[dy].len:
              if villageStruct.layout[dy][dx] == ' ':
                continue
            env.baseTintColors[tileX][tileY] = TileColor(
              r: villageColor.r,
              g: villageColor.g,
              b: villageColor.b,
              intensity: 1.0
            )

      # Add nearby village resources first, then connect roads between them.
      placeStartingResourceBuildings(elements.center, teamId)
      placeStartingHouses(elements.center, teamId, r)
      placeStartingRoads(elements.center, teamId, r)
      placeStartingResourceNodes(elements.center, r)

      # Add the walls
      for wallPos in elements.walls:
        if not isNil(env.getBackgroundThing(wallPos)):
          continue
        env.add(Thing(
          kind: Wall,
          pos: wallPos,
        ))

      # Add the doors (team-colored, passable only to that team)
      for doorPos in elements.doors:
        if doorPos.x >= 0 and doorPos.x < MapWidth and doorPos.y >= 0 and doorPos.y < MapHeight:
          if env.isEmpty(doorPos) and not env.hasDoor(doorPos):
            env.add(Thing(kind: Door, pos: doorPos, teamId: teamId))

      # Add the interior buildings from the layout
      for y in 0 ..< villageStruct.height:
        for x in 0 ..< villageStruct.width:
          if y < villageStruct.layout.len and x < villageStruct.layout[y].len:
            let worldPos = placementPosition + ivec2(x.int32, y.int32)
            case villageStruct.layout[y][x]:
            of StructureBlacksmithChar:  # Blacksmith
              env.add(Thing(
                kind: Blacksmith,
                pos: worldPos,
                teamId: teamId,
                barrelCapacity: buildingBarrelCapacity(Blacksmith)
              ))
            of StructureClayOvenChar:  # Clay Oven at bottom-left
              env.add(Thing(
                kind: ClayOven,
                pos: worldPos,
                teamId: teamId
              ))
            of StructureWeavingLoomChar:  # Weaving Loom at bottom-right
              env.add(Thing(
                kind: WeavingLoom,
                pos: worldPos,
                teamId: teamId
              ))
            of StructureTownCenterChar:  # Town Center
              env.add(Thing(
                kind: TownCenter,
                pos: worldPos,
                teamId: teamId
              ))
            of StructureBarracksChar:  # Barracks
              env.add(Thing(
                kind: Barracks,
                pos: worldPos,
                teamId: teamId
              ))
            of StructureArcheryRangeChar:  # Archery Range
              env.add(Thing(
                kind: ArcheryRange,
                pos: worldPos,
                teamId: teamId
              ))
            of StructureStableChar:  # Stable
              env.add(Thing(
                kind: Stable,
                pos: worldPos,
                teamId: teamId
              ))
            of StructureSiegeWorkshopChar:  # Siege Workshop
              env.add(Thing(
                kind: SiegeWorkshop,
                pos: worldPos,
                teamId: teamId
              ))
            of StructureMarketChar:  # Market
              env.add(Thing(
                kind: Market,
                pos: worldPos,
                teamId: teamId
              ))
            of StructureDockChar:  # Dock
              env.add(Thing(
                kind: Dock,
                pos: worldPos,
                teamId: teamId
              ))
            of StructureUniversityChar:  # University
              env.add(Thing(
                kind: University,
                pos: worldPos,
                teamId: teamId
              ))
            else:
              discard
      if agentsForThisVillage > 0:
        # Get nearby positions around the altar
        let nearbyPositions = env.findEmptyPositionsAround(elements.center, 3)

        for j in 0 ..< agentsForThisVillage:
          let agentId = teamId * MapAgentsPerVillage + j

          # Store the village color for this agent (shared by all agents of the village)
          env.agentColors[agentId] = env.teamColors[teamId]

          var agentPos = ivec2(-1, -1)
          var frozen = 0
          var hp = 0
          if j < min(6, agentsForThisVillage):
            if j < nearbyPositions.len:
              agentPos = nearbyPositions[j]
            else:
              agentPos = r.randomEmptyPos(env)
            hp = AgentMaxHp
            env.terminated[agentId] = 0.0
          else:
            env.terminated[agentId] = 1.0

          # Create the agent slot (only the first is placed immediately)
          env.add(Thing(
            kind: Agent,
            agentId: agentId,
            pos: agentPos,
            orientation: Orientation(randIntInclusive(r, 0, 3)),
            homeAltar: elements.center,  # Link agent to their home altar
            frozen: frozen,
            hp: hp,
            maxHp: AgentMaxHp,
            attackDamage: VillagerAttackDamage,
            unitClass: UnitVillager,
            embarkedUnitClass: UnitVillager,
            teamIdOverride: -1
          ))

          totalAgentsSpawned += 1
          if totalAgentsSpawned >= villageAgentCap:
            break

      # Note: Door gaps are placed instead of walls for defendable entrances

  # Now place additional random walls after villages to avoid blocking corner placement
  for i in 0 ..< MapRoomObjectsWalls:
    let pos = r.randomEmptyPos(env)
    if not isNil(env.getBackgroundThing(pos)):
      continue
    env.add(Thing(kind: Wall, pos: pos))

  # If there are still agents to spawn (e.g., if not enough villages), spawn them randomly
  # They will get a neutral color
  while totalAgentsSpawned < villageAgentCap:
    let agentPos = r.randomEmptyPos(env)
    let agentId = totalAgentsSpawned

    # Store neutral color for agents without a village
    env.agentColors[agentId] = color(0.5, 0.5, 0.5, 1.0)  # Gray for unaffiliated agents

    env.add(Thing(
      kind: Agent,
      agentId: agentId,
      pos: agentPos,
      orientation: Orientation(randIntInclusive(r, 0, 3)),
      homeAltar: ivec2(-1, -1),  # No home altar for unaffiliated agents
      frozen: 0,
      hp: AgentMaxHp,
      maxHp: AgentMaxHp,
      attackDamage: VillagerAttackDamage,
      unitClass: UnitVillager,
      embarkedUnitClass: UnitVillager,
      teamIdOverride: -1,
    ))

    totalAgentsSpawned += 1

  # Place goblin hives with surrounding structures, then spawn goblin agents.
  const GoblinHiveCount = 2
  var goblinHivePositions: seq[IVec2] = @[]

  proc findGoblinHivePos(existing: seq[IVec2]): IVec2 =
    const HiveRadius = 2
    let minGoblinDist = DefaultSpawnerMinDistance
    let minGoblinDist2 = minGoblinDist * minGoblinDist
    let minHiveDist = max(4, DefaultSpawnerMinDistance div 2)
    let minHiveDist2 = minHiveDist * minHiveDist
    for attempt in 0 ..< 200:
      let center = r.randomEmptyPos(env)
      if env.terrain[center.x][center.y] == Water:
        continue
      var okDistance = true
      for altar in env.thingsByKind[Altar]:
        let dx = int(center.x) - int(altar.pos.x)
        let dy = int(center.y) - int(altar.pos.y)
        if dx * dx + dy * dy < minGoblinDist2:
          okDistance = false
          break
      if not okDistance:
        continue
      for hive in existing:
        let dx = int(center.x) - int(hive.x)
        let dy = int(center.y) - int(hive.y)
        if dx * dx + dy * dy < minHiveDist2:
          okDistance = false
          break
      if not okDistance:
        continue
      var areaValid = true
      for dx in -HiveRadius .. HiveRadius:
        for dy in -HiveRadius .. HiveRadius:
          let pos = center + ivec2(dx, dy)
          if not isValidPos(pos):
            areaValid = false
            break
          if not env.isEmpty(pos) or not isNil(env.getBackgroundThing(pos)) or
              isBlockedTerrain(env.terrain[pos.x][pos.y]):
            areaValid = false
            break
        if not areaValid:
          break
      if not areaValid:
        continue
      for dx in -HiveRadius .. HiveRadius:
        for dy in -HiveRadius .. HiveRadius:
          let pos = center + ivec2(dx, dy)
          if isValidPos(pos) and not isBlockedTerrain(env.terrain[pos.x][pos.y]):
            env.terrain[pos.x][pos.y] = Empty
            env.resetTileColor(pos)
      return center
    var fallback = r.randomEmptyPos(env)
    var tries = 0
    while tries < 50:
      var ok = env.terrain[fallback.x][fallback.y] != Water
      if ok:
        for hive in existing:
          let dx = int(fallback.x) - int(hive.x)
          let dy = int(fallback.y) - int(hive.y)
          if dx * dx + dy * dy < minHiveDist2:
            ok = false
            break
      if ok:
        break
      fallback = r.randomEmptyPos(env)
      inc tries
    fallback

  let goblinTint = color(0.35, 0.80, 0.35, 1.0)
  for hiveIndex in 0 ..< GoblinHiveCount:
    let goblinHivePos = findGoblinHivePos(goblinHivePositions)
    goblinHivePositions.add(goblinHivePos)
    env.add(Thing(kind: GoblinHive, pos: goblinHivePos, teamId: -1))

    var goblinSpots = env.findEmptyPositionsAround(goblinHivePos, 2)
    if goblinSpots.len == 0:
      goblinSpots = env.findEmptyPositionsAround(goblinHivePos, 3)

    let hutCount = MapRoomObjectsGoblinHuts div GoblinHiveCount +
      (if hiveIndex < MapRoomObjectsGoblinHuts mod GoblinHiveCount: 1 else: 0)
    for _ in 0 ..< hutCount:
      if goblinSpots.len == 0:
        break
      let idx = randIntInclusive(r, 0, goblinSpots.len - 1)
      let pos = goblinSpots[idx]
      goblinSpots[idx] = goblinSpots[^1]
      goblinSpots.setLen(goblinSpots.len - 1)
      env.add(Thing(kind: GoblinHut, pos: pos, teamId: -1))

    let totemCount = MapRoomObjectsGoblinTotems div GoblinHiveCount +
      (if hiveIndex < MapRoomObjectsGoblinTotems mod GoblinHiveCount: 1 else: 0)
    for _ in 0 ..< totemCount:
      if goblinSpots.len == 0:
        break
      let idx = randIntInclusive(r, 0, goblinSpots.len - 1)
      let pos = goblinSpots[idx]
      goblinSpots[idx] = goblinSpots[^1]
      goblinSpots.setLen(goblinSpots.len - 1)
      env.add(Thing(kind: GoblinTotem, pos: pos, teamId: -1))

    let agentCount = MapRoomObjectsGoblinAgents div GoblinHiveCount +
      (if hiveIndex < MapRoomObjectsGoblinAgents mod GoblinHiveCount: 1 else: 0)
    for _ in 0 ..< agentCount:
      let agentId = totalAgentsSpawned
      var agentPos = ivec2(-1, -1)
      if goblinSpots.len > 0:
        let idx = randIntInclusive(r, 0, goblinSpots.len - 1)
        agentPos = goblinSpots[idx]
        goblinSpots[idx] = goblinSpots[^1]
        goblinSpots.setLen(goblinSpots.len - 1)
      else:
        agentPos = r.randomEmptyPos(env)
      env.agentColors[agentId] = goblinTint
      env.terminated[agentId] = 0.0
      env.add(Thing(
        kind: Agent,
        agentId: agentId,
        pos: agentPos,
        orientation: Orientation(randIntInclusive(r, 0, 3)),
        homeAltar: goblinHivePos,
        frozen: 0,
        hp: GoblinMaxHp,
        maxHp: GoblinMaxHp,
        attackDamage: GoblinAttackDamage,
        unitClass: UnitGoblin,
        embarkedUnitClass: UnitGoblin,
        teamIdOverride: MapRoomObjectsHouses
      ))
      totalAgentsSpawned += 1

  # Random spawner placement with minimum distance from villages and other spawners
  # Gather altar positions for distance checks
  var altarPositionsNow: seq[IVec2] = @[]
  var spawnerPositions: seq[IVec2] = @[]
  for thing in env.things:
    if thing.kind == Altar:
      altarPositionsNow.add(thing.pos)

  let minDist = DefaultSpawnerMinDistance
  let minDist2 = minDist * minDist

  for i in 0 ..< numVillages:
    let spawnerStruct = Structure(width: 3, height: 3, centerPos: ivec2(1, 1))
    var placed = false
    var targetPos: IVec2

    for attempt in 0 ..< 200:
      targetPos = r.randomEmptyPos(env)
      # Keep within borders allowing spawner bounds
      if targetPos.x < MapBorder + spawnerStruct.width div 2 or
         targetPos.x >= MapWidth - MapBorder - spawnerStruct.width div 2 or
         targetPos.y < MapBorder + spawnerStruct.height div 2 or
         targetPos.y >= MapHeight - MapBorder - spawnerStruct.height div 2:
        continue

      # Check simple area clear (3x3)
      var areaValid = true
      for dx in -(spawnerStruct.width div 2) .. (spawnerStruct.width div 2):
        for dy in -(spawnerStruct.height div 2) .. (spawnerStruct.height div 2):
          let checkPos = targetPos + ivec2(dx, dy)
          if not isValidPos(checkPos):
            areaValid = false
            break
          if not env.isEmpty(checkPos) or isBlockedTerrain(env.terrain[checkPos.x][checkPos.y]):
            areaValid = false
            break
        if not areaValid:
          break

      if not areaValid:
        continue

      # Enforce min distance from any altar and other spawners
      var okDistance = true
      # Check distance from villages (altars)
      for ap in altarPositionsNow:
        let dx = int(targetPos.x) - int(ap.x)
        let dy = int(targetPos.y) - int(ap.y)
        if dx*dx + dy*dy < minDist2:
          okDistance = false
          break
      # Check distance from other spawners
      for sp in spawnerPositions:
        let dx = int(targetPos.x) - int(sp.x)
        let dy = int(targetPos.y) - int(sp.y)
        if dx*dx + dy*dy < minDist2:
          okDistance = false
          break
      if not okDistance:
        continue

      # Clear terrain and place spawner
      for dx in -(spawnerStruct.width div 2) .. (spawnerStruct.width div 2):
        for dy in -(spawnerStruct.height div 2) .. (spawnerStruct.height div 2):
          let clearPos = targetPos + ivec2(dx, dy)
          if clearPos.x >= 0 and clearPos.x < MapWidth and clearPos.y >= 0 and clearPos.y < MapHeight:
            if not isBlockedTerrain(env.terrain[clearPos.x][clearPos.y]):
              env.terrain[clearPos.x][clearPos.y] = Empty
              env.resetTileColor(clearPos)

      env.add(Thing(
        kind: Spawner,
        pos: targetPos,
        cooldown: 0,
        homeSpawner: targetPos
      ))

      # Add this spawner position for future collision checks
      spawnerPositions.add(targetPos)

      let nearbyPositions = env.findEmptyPositionsAround(targetPos, 1)
      if nearbyPositions.len > 0:
        let spawnCount = min(3, nearbyPositions.len)
        for i in 0 ..< spawnCount:
          env.add(createTumor(nearbyPositions[i], targetPos, r))
      placed = true
      break

    # If we fail to satisfy distance after attempts, place anywhere random
    if not placed:
      targetPos = r.randomEmptyPos(env)
      env.add(Thing(
        kind: Spawner,
        pos: targetPos,
        cooldown: 0,
        homeSpawner: targetPos
      ))
      let nearbyPositions = env.findEmptyPositionsAround(targetPos, 1)
      if nearbyPositions.len > 0:
        let spawnCount = min(3, nearbyPositions.len)
        for i in 0 ..< spawnCount:
          env.add(createTumor(nearbyPositions[i], targetPos, r))

  # Magma spawns in slightly larger clusters (3-4) for higher local density.
  var poolsPlaced = 0
  let magmaClusterCount = max(1, min(MapRoomObjectsMagmaClusters, max(1, MapRoomObjectsMagmaPools div 2)))
  for clusterIndex in 0 ..< magmaClusterCount:
    let remaining = MapRoomObjectsMagmaPools - poolsPlaced
    if remaining <= 0:
      break
    let clustersLeft = magmaClusterCount - clusterIndex
    let maxCluster = min(4, remaining)
    let minCluster = if remaining >= 3: 3 else: 1
    let baseSize = max(minCluster, min(maxCluster, remaining div clustersLeft))
    let clusterSize = max(minCluster, min(maxCluster, baseSize + randIntInclusive(r, -1, 1)))
    let center = r.randomEmptyPos(env)

    env.add(Thing(
      kind: Magma,
      pos: center,
    ))
    inc poolsPlaced

    if poolsPlaced >= MapRoomObjectsMagmaPools:
      break

    var candidates = env.findEmptyPositionsAround(center, 1)
    if candidates.len < clusterSize - 1:
      let extra = env.findEmptyPositionsAround(center, 2)
      for pos in extra:
        var exists = false
        for c in candidates:
          if c == pos:
            exists = true
            break
        if not exists:
          candidates.add(pos)

    let toPlace = min(clusterSize - 1, candidates.len)
    for i in 0 ..< toPlace:
      env.add(Thing(
        kind: Magma,
        pos: candidates[i],
      ))
      inc poolsPlaced
      if poolsPlaced >= MapRoomObjectsMagmaPools:
        break

  # Spawn resource nodes (trees, wheat, ore, plants) as Things.
  block:
    # Wheat fields.
    for _ in 0 ..< randIntInclusive(r, WheatFieldClusterCountMin, WheatFieldClusterCountMax):
      var placed = false
      for attempt in 0 ..< 20:
        let pos = randInteriorPos(r, 3)
        let x = pos.x.int
        let y = pos.y.int
        var nearWater = false
        for dx in -5 .. 5:
          for dy in -5 .. 5:
            let checkX = x + dx
            let checkY = y + dy
            if checkX >= 0 and checkX < MapWidth and checkY >= 0 and checkY < MapHeight:
              if env.terrain[checkX][checkY] == Water:
                nearWater = true
                break
          if nearWater:
            break
        if nearWater or attempt > 10:
          let fieldSize = randIntInclusive(r, WheatFieldSizeMin, WheatFieldSizeMax)
          for (sizeDelta, density) in [(0, 1.0), (1, 0.5)]:
            placeResourceCluster(env, x, y, fieldSize + sizeDelta, density, 0.3,
              Wheat, ItemWheat, ResourceGround, r)
          placed = true
          break
      if not placed:
        let pos = randInteriorPos(r, 3)
        let x = pos.x.int
        let y = pos.y.int
        let fieldSize = randIntInclusive(r, WheatFieldSizeMin, WheatFieldSizeMax)
        for (sizeDelta, density) in [(0, 1.0), (1, 0.5)]:
          placeResourceCluster(env, x, y, fieldSize + sizeDelta, density, 0.3,
            Wheat, ItemWheat, ResourceGround, r)

    proc placeTreeOasis(centerX, centerY: int) =
      let rx = randIntInclusive(r, TreeOasisWaterRadiusMin, TreeOasisWaterRadiusMax)
      let ry = randIntInclusive(r, TreeOasisWaterRadiusMin, TreeOasisWaterRadiusMax)
      template canPlaceWater(pos: IVec2): bool =
        env.isEmpty(pos) and isNil(env.getBackgroundThing(pos)) and not env.hasDoor(pos) and
          env.terrain[pos.x][pos.y] notin {Road, Bridge}
      for ox in -(rx + 1) .. (rx + 1):
        for oy in -(ry + 1) .. (ry + 1):
          let px = centerX + ox
          let py = centerY + oy
          if px < MapBorder or px >= MapWidth - MapBorder or py < MapBorder or py >= MapHeight - MapBorder:
            continue
          let waterPos = ivec2(px.int32, py.int32)
          if not canPlaceWater(waterPos):
            continue
          let dx = ox.float / rx.float
          let dy = oy.float / ry.float
          let dist = dx * dx + dy * dy
          if dist <= 1.0 + (randFloat(r) - 0.5) * 0.35:
            env.terrain[px][py] = Water
            env.resetTileColor(waterPos)

      for _ in 0 ..< randIntInclusive(r, 1, 2):
        var pos = ivec2(centerX.int32, centerY.int32)
        for _ in 0 ..< randIntInclusive(r, 4, 10):
          let dir = sample(r, [ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1),
                               ivec2(1, 1), ivec2(-1, 1), ivec2(1, -1), ivec2(-1, -1)])
          pos += dir
          if pos.x < MapBorder.int32 or pos.x >= (MapWidth - MapBorder).int32 or
             pos.y < MapBorder.int32 or pos.y >= (MapHeight - MapBorder).int32:
            break
          if not canPlaceWater(pos):
            continue
          env.terrain[pos.x][pos.y] = Water
          env.resetTileColor(pos)

      for ox in -(rx + 2) .. (rx + 2):
        for oy in -(ry + 2) .. (ry + 2):
          let px = centerX + ox
          let py = centerY + oy
          if px < MapBorder or px >= MapWidth - MapBorder or py < MapBorder or py >= MapHeight - MapBorder:
            continue
          if env.terrain[px][py] == Water:
            continue
          var nearWater = false
          for dx in -1 .. 1:
            for dy in -1 .. 1:
              let nx = px + dx
              let ny = py + dy
              if nx < MapBorder or nx >= MapWidth - MapBorder or ny < MapBorder or ny >= MapHeight - MapBorder:
                continue
              if env.terrain[nx][ny] == Water:
                nearWater = true
                break
            if nearWater:
              break
          if nearWater and randChance(r, 0.7) and env.terrain[px][py] in TreeGround:
            addResourceNode(env, ivec2(px.int32, py.int32), Tree, ItemWood)

    if UseTreeOases:
      let numGroves = randIntInclusive(r, TreeOasisClusterCountMin, TreeOasisClusterCountMax)
      for _ in 0 ..< numGroves:
        var placed = false
        for attempt in 0 ..< 16:
          let pos = randInteriorPos(r, 3)
          let x = pos.x.int
          let y = pos.y.int
          var nearWater = false
          for dx in -5 .. 5:
            for dy in -5 .. 5:
              let checkX = x + dx
              let checkY = y + dy
              if checkX >= 0 and checkX < MapWidth and checkY >= 0 and checkY < MapHeight:
                if env.terrain[checkX][checkY] == Water:
                  nearWater = true
                  break
            if nearWater:
              break
          if nearWater or attempt > 10:
            placeTreeOasis(x, y)
            placed = true
            break
        if not placed:
          let pos = randInteriorPos(r, 3)
          let x = pos.x.int
          let y = pos.y.int
          placeTreeOasis(x, y)

    if UseLegacyTreeClusters:
      let numGroves = randIntInclusive(r, TreeGroveClusterCountMin, TreeGroveClusterCountMax)
      for _ in 0 ..< numGroves:
        let pos = randInteriorPos(r, 3)
        let x = pos.x.int
        let y = pos.y.int
        let groveSize = randIntInclusive(r, 3, 10)
        placeResourceCluster(env, x, y, groveSize, 0.8, 0.4, Tree, ItemWood, ResourceGround, r)

    proc buildClusterSizes(targetDeposits: int, clusterCount: int): seq[int] =
      let minCluster = 3
      let maxCluster = 4
      let minDeposits = clusterCount * minCluster
      let maxDeposits = clusterCount * maxCluster
      let clamped = max(minDeposits, min(maxDeposits, targetDeposits))
      result = newSeq[int](clusterCount)
      for i in 0 ..< clusterCount:
        result[i] = minCluster
      var extras = clamped - minDeposits
      while extras > 0:
        let idx = randIntInclusive(r, 0, clusterCount - 1)
        if result[idx] < maxCluster:
          inc result[idx]
          dec extras

    proc placeMineClusters(depositKind: ThingKind, depositItem: ItemKey,
                           targetDeposits: int, clusterCount: int) =
      if targetDeposits <= 0 or clusterCount <= 0:
        return
      let clusterSizes = buildClusterSizes(targetDeposits, clusterCount)
      for clusterIndex in 0 ..< clusterSizes.len:
        let clusterSize = clusterSizes[clusterIndex]
        let center = r.randomEmptyPos(env)

        addResourceNode(env, center, depositKind, depositItem, MineDepositAmount)

        var candidates = env.findEmptyPositionsAround(center, 1)
        if candidates.len < clusterSize - 1:
          let extra = env.findEmptyPositionsAround(center, 2)
          for pos in extra:
            var exists = false
            for c in candidates:
              if c == pos:
                exists = true
                break
            if not exists:
              candidates.add(pos)

        let toPlace = min(clusterSize - 1, candidates.len)
        for i in 0 ..< toPlace:
          addResourceNode(env, candidates[i], depositKind, depositItem, MineDepositAmount)

    placeMineClusters(Stone, ItemStone, MapRoomObjectsStoneClusters, MapRoomObjectsStoneClusterCount)
    placeMineClusters(Gold, ItemGold, MapRoomObjectsGoldClusters, MapRoomObjectsGoldClusterCount)

    let fishClusters = max(8, MapWidth div 20)
    for _ in 0 ..< fishClusters:
      var placed = false
      for attempt in 0 ..< 20:
        let pos = randInteriorPos(r, 2)
        let x = pos.x.int
        let y = pos.y.int
        if env.terrain[x][y] != Water:
          continue
        let size = randIntInclusive(r, 3, 7)
        placeResourceCluster(env, x, y, size, 0.85, 0.45, Fish, ItemFish, {Water}, r)
        placed = true
        break
      if not placed:
        break

    var relicsPlaced = 0
    var relicAttempts = 0
    while relicsPlaced < MapRoomObjectsRelics and relicAttempts < MapRoomObjectsRelics * 10:
      inc relicAttempts
      let pos = r.randomEmptyPos(env)
      if env.terrain[pos.x][pos.y] == Water:
        continue
      if env.isEmpty(pos) and isNil(env.getBackgroundThing(pos)) and not env.hasDoor(pos):
        let relic = Thing(kind: Relic, pos: pos)
        relic.inventory = emptyInventory()
        setInv(relic, ItemGold, 1)
        env.add(relic)
        inc relicsPlaced

    for _ in 0 ..< 30:
      var attempts = 0
      var placed = false
      while attempts < 12 and not placed:
        inc attempts
        let pos = randInteriorPos(r, 2)
        let x = pos.x.int
        let y = pos.y.int
        var nearWater = false
        for dx in -4 .. 4:
          for dy in -4 .. 4:
            let checkX = x + dx
            let checkY = y + dy
            if checkX >= 0 and checkX < MapWidth and checkY >= 0 and checkY < MapHeight:
              if env.terrain[checkX][checkY] == Water:
                nearWater = true
                break
          if nearWater:
            break
        if nearWater or attempts >= 10:
          let size = randIntInclusive(r, 3, 7)
          placeResourceCluster(env, x, y, size, 0.75, 0.45, Bush, ItemPlant, ResourceGround, r)
          placed = true

    placeBiomeResourceClusters(env, r, max(10, MapWidth div 20),
      2, 5, 0.65, 0.4, Cactus, ItemPlant, BiomeDesertType)

    placeBiomeResourceClusters(env, r, max(10, MapWidth div 30),
      2, 6, 0.7, 0.45, Stalagmite, ItemStone, BiomeCavesType)

  # Ensure the world is a single connected component after terrain and structures.
  env.makeConnected()

  proc chooseGroupSize(remaining, minSize, maxSize: int): int =
    if remaining <= maxSize:
      return remaining
    result = randIntInclusive(r, minSize, maxSize)
    let remainder = remaining - result
    if remainder > 0 and remainder < minSize:
      result -= (minSize - remainder)

  proc collectGroupPositions(center: IVec2, radius: int): seq[IVec2] =
    var positions = env.findEmptyPositionsAround(center, radius)
    positions.insert(center, 0)
    result = @[]
    for pos in positions:
      if env.terrain[pos.x][pos.y] == Empty and env.biomes[pos.x][pos.y] != BiomeDungeonType:
        result.add(pos)


  # Cows spawn in herds (5-10) across open terrain.
  const MinHerdSize = 5
  const MaxHerdSize = 10
  var cowsPlaced = 0
  var herdId = 0
  while cowsPlaced < MapRoomObjectsCows:
    let herdSize = chooseGroupSize(MapRoomObjectsCows - cowsPlaced, MinHerdSize, MaxHerdSize)
    let center = r.randomEmptyPos(env)
    if env.terrain[center.x][center.y] != Empty:
      continue
    if env.biomes[center.x][center.y] == BiomeDungeonType:
      continue
    let filtered = collectGroupPositions(center, 3)
    if filtered.len < 5:
      continue
    let toPlace = min(herdSize, filtered.len)
    for i in 0 ..< toPlace:
      let cow = Thing(
        kind: Cow,
        pos: filtered[i],
        orientation: Orientation.W,
        herdId: herdId
      )
      cow.inventory = emptyInventory()
      setInv(cow, ItemMeat, ResourceNodeInitial)
      env.add(cow)
      inc cowsPlaced
      if cowsPlaced >= MapRoomObjectsCows:
        break
    inc herdId

  # Bears spawn as solitary predators across open terrain.
  var bearsPlaced = 0
  while bearsPlaced < MapRoomObjectsBears:
    let pos = r.randomEmptyPos(env)
    if env.terrain[pos.x][pos.y] != Empty:
      continue
    if env.biomes[pos.x][pos.y] == BiomeDungeonType:
      continue
    let bear = Thing(
      kind: Bear,
      pos: pos,
      orientation: Orientation.W,
      maxHp: BearMaxHp,
      hp: BearMaxHp,
      attackDamage: BearAttackDamage
    )
    env.add(bear)
    inc bearsPlaced

  # Wolves spawn in packs (3-5) across open terrain.
  var wolvesPlaced = 0
  var packId = 0
  while wolvesPlaced < MapRoomObjectsWolves:
    let packSize = chooseGroupSize(MapRoomObjectsWolves - wolvesPlaced, WolfPackMinSize, WolfPackMaxSize)
    let center = r.randomEmptyPos(env)
    if env.terrain[center.x][center.y] != Empty:
      continue
    if env.biomes[center.x][center.y] == BiomeDungeonType:
      continue
    let filtered = collectGroupPositions(center, 4)
    if filtered.len < WolfPackMinSize:
      continue
    let toPlace = min(packSize, filtered.len)
    for i in 0 ..< toPlace:
      let wolf = Thing(
        kind: Wolf,
        pos: filtered[i],
        orientation: Orientation.W,
        packId: packId,
        maxHp: WolfMaxHp,
        hp: WolfMaxHp,
        attackDamage: WolfAttackDamage
      )
      env.add(wolf)
      inc wolvesPlaced
      if wolvesPlaced >= MapRoomObjectsWolves:
        break
    inc packId

  # Initialize altar locations for all spawners
  var altarPositions: seq[IVec2] = @[]
  for thing in env.things:
    if thing.kind == Altar:
      altarPositions.add(thing.pos)

  # Initialize observations only when first needed (lazy approach)
  # Individual action updates will populate observations as needed
  maybeStartReplayEpisode(env)


proc newEnvironment*(): Environment =
  ## Create a new environment with default configuration
  result = Environment(config: defaultEnvironmentConfig())
  result.init()

proc newEnvironment*(config: EnvironmentConfig): Environment =
  ## Create a new environment with custom configuration
  result = Environment(config: config)
  result.init()

# Global environment is initialized by entry points (e.g., tribal_village.nim).
