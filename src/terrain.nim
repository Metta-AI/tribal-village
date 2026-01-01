import std/math, vmath
import rng_compat
import biome_forest, biome_desert, biome_caves, biome_city, biome_plains, biome_common
import dungeon_maze, dungeon_radial

const
  # Keep in sync with biome_common.nim's MaxBiomeSize.
  MaxTerrainSize* = 512

type
  TerrainType* = enum
    Empty
    Water
    Bridge
    Wheat
    Tree
    Fertile
    Road
    Rock
    Gem
    Bush
    Animal
    Grass
    Cactus
    Dune
    Stalagmite
    Palm
    Sand
  ## Sized to comfortably exceed current MapWidth/MapHeight.
  TerrainGrid* = array[MaxTerrainSize, array[MaxTerrainSize, TerrainType]]

  Structure* = object
    width*, height*: int
    centerPos*: IVec2
    layout*: seq[seq[char]]

type
  BiomeKind* = enum
    BiomeForest
    BiomeDesert
    BiomeCaves
    BiomeCity
    BiomePlains

  BiomeType* = enum
    BiomeNone
    BiomeForestType
    BiomeDesertType
    BiomeCavesType
    BiomeCityType
    BiomePlainsType
    BiomeDungeonType

  BiomeGrid* = array[MaxTerrainSize, array[MaxTerrainSize, BiomeType]]

  DungeonKind* = enum
    DungeonMaze
    DungeonRadial

const
  UseBiomeTerrain* = true
  BaseBiome* = BiomePlains
  BiomeForestTerrain* = Tree
  BiomeDesertTerrain* = Sand
  BiomeCavesTerrain* = Stalagmite
  BiomePlainsTerrain* = Grass
  BiomeCityBlockTerrain* = Rock
  BiomeCityRoadTerrain* = Road
  UseBiomeZones* = true
  UseDungeonZones* = true
  UseSequentialBiomeZones* = true
  UseLegacyTreeClusters* = true
  UsePalmGroves* = true
  WheatFieldClusterBase* = 14
  WheatFieldClusterRange* = 6
  WheatFieldClusterScale* = 7
  TreeGroveClusterBase* = 14
  TreeGroveClusterRange* = 6
  TreeGroveClusterScale* = 7
  PalmGroveClusterBase* = 6
  PalmGroveClusterRange* = 4
  PalmGroveClusterScale* = 3
  # Slightly higher biome/dungeon density for richer maps.
  BiomeZoneDivisor* = 5500
  DungeonZoneDivisor* = 9000
  BiomeZoneMinCount* = 5
  BiomeZoneMaxCount* = 12
  DungeonZoneMinCount* = 4
  DungeonZoneMaxCount* = 9
  BiomeZoneMaxFraction* = 0.22
  DungeonZoneMaxFraction* = 0.18
  ZoneMinSize* = 12
  DungeonTerrainWall* = Tree
  DungeonTerrainPath* = Road

const
  TerrainEmpty* = TerrainType.Empty
  TerrainWater* = TerrainType.Water
  TerrainBridge* = TerrainType.Bridge
  TerrainWheat* = TerrainType.Wheat
  TerrainTree* = TerrainType.Tree
  TerrainPalm* = TerrainType.Palm
  TerrainFertile* = TerrainType.Fertile
  TerrainRock* = TerrainType.Rock
  TerrainGem* = TerrainType.Gem
  TerrainBush* = TerrainType.Bush
  TerrainAnimal* = TerrainType.Animal
  TerrainGrass* = TerrainType.Grass
  TerrainCactus* = TerrainType.Cactus
  TerrainDune* = TerrainType.Dune
  TerrainStalagmite* = TerrainType.Stalagmite
  TerrainSand* = TerrainType.Sand

template isBlockedTerrain*(terrain: TerrainType): bool =
  terrain in {Water, Dune, Stalagmite}

template randInclusive(r: var Rand, a, b: int): int = randIntInclusive(r, a, b)
template randChance(r: var Rand, p: float): bool = randFloat(r) < p

const
  RiverWidth* = 6

type
  ZoneRect = object
    x, y, w, h: int

proc applyMaskToTerrain(terrain: var TerrainGrid, mask: MaskGrid, mapWidth, mapHeight, mapBorder: int,
                        terrainType: TerrainType) =
  for x in mapBorder ..< mapWidth - mapBorder:
    for y in mapBorder ..< mapHeight - mapBorder:
      if mask[x][y] and terrain[x][y] == Empty:
        terrain[x][y] = terrainType

proc applyMaskToTerrainRect(terrain: var TerrainGrid, mask: MaskGrid, zone: ZoneRect,
                            mapWidth, mapHeight, mapBorder: int, terrainType: TerrainType,
                            overwrite = false) =
  let x0 = max(mapBorder, zone.x)
  let y0 = max(mapBorder, zone.y)
  let x1 = min(mapWidth - mapBorder, zone.x + zone.w)
  let y1 = min(mapHeight - mapBorder, zone.y + zone.h)
  if x1 <= x0 or y1 <= y0:
    return
  for x in x0 ..< x1:
    for y in y0 ..< y1:
      if mask[x][y]:
        if overwrite or terrain[x][y] == Empty:
          terrain[x][y] = terrainType

proc applyBiomeToZone(biomes: var BiomeGrid, zone: ZoneRect, mapWidth, mapHeight, mapBorder: int,
                      biome: BiomeType) =
  let x0 = max(mapBorder, zone.x)
  let y0 = max(mapBorder, zone.y)
  let x1 = min(mapWidth - mapBorder, zone.x + zone.w)
  let y1 = min(mapHeight - mapBorder, zone.y + zone.h)
  if x1 <= x0 or y1 <= y0:
    return
  for x in x0 ..< x1:
    for y in y0 ..< y1:
      biomes[x][y] = biome

proc applyBiomeMaskToZone(terrain: var TerrainGrid, biomes: var BiomeGrid, mask: MaskGrid,
                          zone: ZoneRect, mapWidth, mapHeight, mapBorder: int,
                          terrainType: TerrainType, biomeType: BiomeType, baseBiomeType: BiomeType,
                          r: var Rand, blendChance: float) =
  let x0 = max(mapBorder, zone.x)
  let y0 = max(mapBorder, zone.y)
  let x1 = min(mapWidth - mapBorder, zone.x + zone.w)
  let y1 = min(mapHeight - mapBorder, zone.y + zone.h)
  if x1 <= x0 or y1 <= y0:
    return
  for x in x0 ..< x1:
    for y in y0 ..< y1:
      if not mask[x][y]:
        continue
      if terrain[x][y] == Empty or randChance(r, blendChance):
        terrain[x][y] = terrainType
      if biomes[x][y] == baseBiomeType or randChance(r, blendChance):
        biomes[x][y] = biomeType

proc pickWeighted[T](r: var Rand, options: openArray[T], weights: openArray[float]): T =
  var total = 0.0
  for w in weights:
    total += max(0.0, w)
  if total <= 0.0:
    return options[0]
  let roll = randFloat(r) * total
  var accum = 0.0
  for i, w in weights:
    accum += max(0.0, w)
    if roll <= accum:
      return options[i]
  options[^1]

proc randomZone(r: var Rand, mapWidth, mapHeight, mapBorder: int, maxFraction: float): ZoneRect =
  let maxW = max(ZoneMinSize, int(min(mapWidth.float * maxFraction, mapWidth.float / 2)))
  let maxH = max(ZoneMinSize, int(min(mapHeight.float * maxFraction, mapHeight.float / 2)))
  let w = randIntInclusive(r, ZoneMinSize, maxW)
  let h = randIntInclusive(r, ZoneMinSize, maxH)
  let xMax = max(mapBorder, mapWidth - mapBorder - w)
  let yMax = max(mapBorder, mapHeight - mapBorder - h)
  let x = randIntInclusive(r, mapBorder, xMax)
  let y = randIntInclusive(r, mapBorder, yMax)
  ZoneRect(x: x, y: y, w: w, h: h)

proc zoneCount(area: int, divisor: int, minCount: int, maxCount: int): int =
  let raw = max(1, area div divisor)
  clamp(raw, minCount, maxCount)

proc applyBiomeZones(terrain: var TerrainGrid, biomes: var BiomeGrid, mapWidth, mapHeight, mapBorder: int,
                     r: var Rand) =
  let count = zoneCount(mapWidth * mapHeight, BiomeZoneDivisor, BiomeZoneMinCount, BiomeZoneMaxCount)
  let kinds = [BiomeForest, BiomeDesert, BiomeCaves, BiomeCity, BiomePlains]
  let weights = [1.0, 1.0, 0.6, 0.6, 1.0]
  let baseBiomeType = case BaseBiome:
    of BiomeForest: BiomeForestType
    of BiomeDesert: BiomeDesertType
    of BiomeCaves: BiomeCavesType
    of BiomeCity: BiomeCityType
    of BiomePlains: BiomePlainsType
  var seqIdx = randIntInclusive(r, 0, kinds.len - 1)
  let blendChance = 0.35
  for _ in 0 ..< count:
    let zone = randomZone(r, mapWidth, mapHeight, mapBorder, BiomeZoneMaxFraction)
    let biome = if UseSequentialBiomeZones:
      let selected = kinds[seqIdx mod kinds.len]
      inc seqIdx
      selected
    else:
      pickWeighted(r, kinds, weights)
    var mask: MaskGrid
    case biome:
    of BiomeForest:
      buildBiomeForestMask(mask, mapWidth, mapHeight, mapBorder, r, BiomeForestConfig())
      applyBiomeMaskToZone(terrain, biomes, mask, zone, mapWidth, mapHeight, mapBorder,
        BiomeForestTerrain, BiomeForestType, baseBiomeType, r, blendChance)
    of BiomeDesert:
      buildBiomeDesertMask(mask, mapWidth, mapHeight, mapBorder, r, BiomeDesertConfig())
      applyBiomeMaskToZone(terrain, biomes, mask, zone, mapWidth, mapHeight, mapBorder,
        BiomeDesertTerrain, BiomeDesertType, baseBiomeType, r, blendChance)
    of BiomeCaves:
      buildBiomeCavesMask(mask, mapWidth, mapHeight, mapBorder, r, BiomeCavesConfig())
      applyBiomeMaskToZone(terrain, biomes, mask, zone, mapWidth, mapHeight, mapBorder,
        BiomeCavesTerrain, BiomeCavesType, baseBiomeType, r, blendChance)
    of BiomeCity:
      var roadMask: MaskGrid
      buildBiomeCityMasks(mask, roadMask, mapWidth, mapHeight, mapBorder, r, BiomeCityConfig())
      applyBiomeMaskToZone(terrain, biomes, mask, zone, mapWidth, mapHeight, mapBorder,
        BiomeCityBlockTerrain, BiomeCityType, baseBiomeType, r, blendChance)
      applyBiomeMaskToZone(terrain, biomes, roadMask, zone, mapWidth, mapHeight, mapBorder,
        BiomeCityRoadTerrain, BiomeCityType, baseBiomeType, r, blendChance)
    of BiomePlains:
      buildBiomePlainsMask(mask, mapWidth, mapHeight, mapBorder, r, BiomePlainsConfig())
      applyBiomeMaskToZone(terrain, biomes, mask, zone, mapWidth, mapHeight, mapBorder,
        BiomePlainsTerrain, BiomePlainsType, baseBiomeType, r, blendChance)

proc applyDungeonZones(terrain: var TerrainGrid, mapWidth, mapHeight, mapBorder: int, r: var Rand) =
  let count = zoneCount(mapWidth * mapHeight, DungeonZoneDivisor, DungeonZoneMinCount, DungeonZoneMaxCount)
  let kinds = [DungeonMaze, DungeonRadial]
  let weights = [1.0, 0.6]
  for _ in 0 ..< count:
    let zone = randomZone(r, mapWidth, mapHeight, mapBorder, DungeonZoneMaxFraction)
    let dungeon = pickWeighted(r, kinds, weights)
    var mask: MaskGrid
    case dungeon:
    of DungeonMaze:
      buildDungeonMazeMask(mask, mapWidth, mapHeight, zone.x, zone.y, zone.w, zone.h, r, DungeonMazeConfig())
      applyMaskToTerrainRect(terrain, mask, zone, mapWidth, mapHeight, mapBorder, DungeonTerrainWall, overwrite = true)
    of DungeonRadial:
      buildDungeonRadialMask(mask, mapWidth, mapHeight, zone.x, zone.y, zone.w, zone.h, r, DungeonRadialConfig())
      applyMaskToTerrainRect(terrain, mask, zone, mapWidth, mapHeight, mapBorder, DungeonTerrainWall, overwrite = true)

proc applyBaseBiome(terrain: var TerrainGrid, mapWidth, mapHeight, mapBorder: int, r: var Rand) =
  var mask: MaskGrid
  case BaseBiome:
  of BiomeForest:
    buildBiomeForestMask(mask, mapWidth, mapHeight, mapBorder, r, BiomeForestConfig())
    applyMaskToTerrain(terrain, mask, mapWidth, mapHeight, mapBorder, BiomeForestTerrain)
  of BiomeDesert:
    buildBiomeDesertMask(mask, mapWidth, mapHeight, mapBorder, r, BiomeDesertConfig())
    applyMaskToTerrain(terrain, mask, mapWidth, mapHeight, mapBorder, BiomeDesertTerrain)
  of BiomeCaves:
    buildBiomeCavesMask(mask, mapWidth, mapHeight, mapBorder, r, BiomeCavesConfig())
    applyMaskToTerrain(terrain, mask, mapWidth, mapHeight, mapBorder, BiomeCavesTerrain)
  of BiomeCity:
    var roadMask: MaskGrid
    buildBiomeCityMasks(mask, roadMask, mapWidth, mapHeight, mapBorder, r, BiomeCityConfig())
    applyMaskToTerrain(terrain, mask, mapWidth, mapHeight, mapBorder, BiomeCityBlockTerrain)
    applyMaskToTerrain(terrain, roadMask, mapWidth, mapHeight, mapBorder, BiomeCityRoadTerrain)
  of BiomePlains:
    buildBiomePlainsMask(mask, mapWidth, mapHeight, mapBorder, r, BiomePlainsConfig())
    applyMaskToTerrain(terrain, mask, mapWidth, mapHeight, mapBorder, BiomePlainsTerrain)

proc inCornerReserve(x, y, mapWidth, mapHeight, mapBorder: int, reserve: int): bool =
  ## Returns true if the coordinate is within a reserved corner area
  let left = mapBorder
  let right = mapWidth - mapBorder
  let top = mapBorder
  let bottom = mapHeight - mapBorder
  let rx = reserve
  let ry = reserve
  let inTopLeft = (x >= left and x < left + rx) and (y >= top and y < top + ry)
  let inTopRight = (x >= right - rx and x < right) and (y >= top and y < top + ry)
  let inBottomLeft = (x >= left and x < left + rx) and (y >= bottom - ry and y < bottom)
  let inBottomRight = (x >= right - rx and x < right) and (y >= bottom - ry and y < bottom)
  inTopLeft or inTopRight or inBottomLeft or inBottomRight

proc generateRiver*(terrain: var TerrainGrid, mapWidth, mapHeight, mapBorder: int, r: var Rand) =
  var riverPath: seq[IVec2] = @[]

  # Reserve corners for villages so river doesn't block them
  let reserve = max(8, min(mapWidth, mapHeight) div 10)

  # Start near left edge and centered vertically (avoid corner reserves)
  let centerY = mapHeight div 2
  let span = max(6, mapHeight div 6)
  var startMin = max(mapBorder + RiverWidth + reserve, centerY - span)
  var startMax = min(mapHeight - mapBorder - RiverWidth - reserve, centerY + span)
  if startMin > startMax: swap(startMin, startMax)
  var currentPos = ivec2(mapBorder.int32, randInclusive(r, startMin, startMax).int32)

  var hasFork = false
  var forkPoint: IVec2
  var secondaryPath: seq[IVec2] = @[]

  while currentPos.x >= mapBorder and currentPos.x < mapWidth - mapBorder and
        currentPos.y >= mapBorder and currentPos.y < mapHeight - mapBorder:
    riverPath.add(currentPos)

    if not hasFork and riverPath.len > max(20, mapWidth div 8) and randChance(r, 0.5):
      hasFork = true
      forkPoint = currentPos

      let towardTop = int(forkPoint.y) - mapBorder
      let towardBottom = (mapHeight - mapBorder) - int(forkPoint.y)
      let dirY = (if towardTop < towardBottom: -1 else: 1)
      var secondaryDirection = ivec2(1, dirY.int32)

      var secondaryPos = forkPoint
      let maxSteps = max(mapWidth * 2, mapHeight * 2)
      var steps = 0
      while secondaryPos.y > mapBorder + RiverWidth and secondaryPos.y < mapHeight - mapBorder - RiverWidth and steps < maxSteps:
        secondaryPos.x += 1
        secondaryPos.y += secondaryDirection.y
        if randChance(r, 0.15):
          secondaryPos.y += sample(r, [-1, 0, 1]).int32
        if secondaryPos.x >= mapBorder and secondaryPos.x < mapWidth - mapBorder and
           secondaryPos.y >= mapBorder and secondaryPos.y < mapHeight - mapBorder:
          if not inCornerReserve(secondaryPos.x, secondaryPos.y, mapWidth, mapHeight, mapBorder, reserve):
            secondaryPath.add(secondaryPos)
        else:
          break
        inc steps
      # Ensure the branch touches the edge vertically with a short vertical run
      var tip = secondaryPos
      var pushSteps = 0
      let maxPush = mapHeight
      if dirY < 0:
        while tip.y > mapBorder and pushSteps < maxPush:
          dec tip.y
          if tip.x >= mapBorder and tip.x < mapWidth and tip.y >= mapBorder and tip.y < mapHeight:
            if not inCornerReserve(tip.x, tip.y, mapWidth, mapHeight, mapBorder, reserve):
              secondaryPath.add(tip)
          inc pushSteps
      else:
        while tip.y < mapHeight - mapBorder and pushSteps < maxPush:
          inc tip.y
          if tip.x >= mapBorder and tip.x < mapWidth and tip.y >= mapBorder and tip.y < mapHeight:
            if not inCornerReserve(tip.x, tip.y, mapWidth, mapHeight, mapBorder, reserve):
              secondaryPath.add(tip)
          inc pushSteps

    currentPos.x += 1  # Always move right
    if randChance(r, 0.3):
      currentPos.y += sample(r, [-1, 0, 0, 1]).int32  # Bias towards staying straight

  # Place water tiles for main river (skip reserved corners)
  for pos in riverPath:
    for dx in -RiverWidth div 2 .. RiverWidth div 2:
      for dy in -RiverWidth div 2 .. RiverWidth div 2:
        let waterPos = pos + ivec2(dx.int32, dy.int32)
        if waterPos.x >= 0 and waterPos.x < mapWidth and
           waterPos.y >= 0 and waterPos.y < mapHeight:
          if not inCornerReserve(waterPos.x, waterPos.y, mapWidth, mapHeight, mapBorder, reserve):
            terrain[waterPos.x][waterPos.y] = Water

  # Place water tiles for secondary branch (skip reserved corners)
  for pos in secondaryPath:
    for dx in -(RiverWidth div 2 - 1) .. (RiverWidth div 2 - 1):
      for dy in -(RiverWidth div 2 - 1) .. (RiverWidth div 2 - 1):
        let waterPos = pos + ivec2(dx.int32, dy.int32)
        if waterPos.x >= 0 and waterPos.x < mapWidth and
           waterPos.y >= 0 and waterPos.y < mapHeight:
          if not inCornerReserve(waterPos.x, waterPos.y, mapWidth, mapHeight, mapBorder, reserve):
            terrain[waterPos.x][waterPos.y] = Water

  # Place bridges across the river and any tributary branch.
  # Bridges are three tiles wide (east-west) and span slightly beyond river width north-south.
  proc placeBridgeMain(t: var TerrainGrid, center: IVec2) =
    let startY = max(mapBorder, int(center.y) - (RiverWidth div 2 + 1))
    let endY = min(mapHeight - mapBorder - 1, int(center.y) + (RiverWidth div 2 + 1))
    let baseX = max(mapBorder, min(mapWidth - mapBorder - 3, int(center.x) - 1))
    for dx in 0 .. 2:
      for y in startY .. endY:
        if not inCornerReserve(baseX + dx, y, mapWidth, mapHeight, mapBorder, reserve):
          t[baseX + dx][y] = Bridge

  # Branch bridges run horizontally (east-west span) across the tributary.
  proc placeBridgeBranch(t: var TerrainGrid, center: IVec2) =
    let startX = max(mapBorder, int(center.x) - (RiverWidth div 2 + 1))
    let endX = min(mapWidth - mapBorder - 1, int(center.x) + (RiverWidth div 2 + 1))
    let baseY = max(mapBorder, min(mapHeight - mapBorder - 3, int(center.y) - 1))
    for dy in 0 .. 2:
      for x in startX .. endX:
        if not inCornerReserve(x, baseY + dy, mapWidth, mapHeight, mapBorder, reserve):
          t[x][baseY + dy] = Bridge

  var mainCandidates: seq[IVec2] = @[]
  for pos in riverPath:
    if pos.x > mapBorder + RiverWidth and pos.x < mapWidth - mapBorder - RiverWidth and
       pos.y > mapBorder + RiverWidth and pos.y < mapHeight - mapBorder - RiverWidth and
       not inCornerReserve(pos.x, pos.y, mapWidth, mapHeight, mapBorder, reserve):
      mainCandidates.add(pos)

  var branchCandidates: seq[IVec2] = @[]
  for pos in secondaryPath:
    if pos.x > mapBorder + RiverWidth and pos.x < mapWidth - mapBorder - RiverWidth and
       pos.y > mapBorder + RiverWidth and pos.y < mapHeight - mapBorder - RiverWidth and
       not inCornerReserve(pos.x, pos.y, mapWidth, mapHeight, mapBorder, reserve):
      branchCandidates.add(pos)

  let hasBranch = secondaryPath.len > 0
  let desiredBridges = max(randInclusive(r, 4, 5), (if hasBranch: 3 else: 0))

  var placed: seq[IVec2] = @[]
  template placeFrom(cands: seq[IVec2], useBranch: bool) =
    if cands.len > 0:
      let center = cands[cands.len div 2]
      if useBranch:
        placeBridgeBranch(terrain, center)
      else:
        placeBridgeMain(terrain, center)
      placed.add(center)

  if hasBranch:
    let forkIdx = riverPath.find(forkPoint)
    if forkIdx >= 0:
      let upstream = if forkIdx > 0: mainCandidates[0 ..< min(forkIdx, mainCandidates.len)] else: @[]
      let downstream = if forkIdx < mainCandidates.len: mainCandidates[min(forkIdx, mainCandidates.len-1) ..< mainCandidates.len] else: @[]
      placeFrom(upstream, false)
      placeFrom(branchCandidates, true)
      placeFrom(downstream, false)

  # Fill remaining bridges by spreading along main river first, then branch.
  proc uniqueAdd(pos: IVec2, list: var seq[IVec2]) =
    for p in list:
      if p == pos: return
    list.add(pos)

  var remaining = desiredBridges - placed.len
  if remaining > 0 and mainCandidates.len > 0:
    let stride = max(1, mainCandidates.len div (remaining + 1))
    var idx = stride
    while remaining > 0 and idx < mainCandidates.len:
      let center = mainCandidates[idx]
      uniqueAdd(center, placed)
      placeBridgeMain(terrain, center)
      dec remaining
      idx += stride

  if remaining > 0 and branchCandidates.len > 0:
    let stride = max(1, branchCandidates.len div (remaining + 1))
    var idx = stride
    while remaining > 0 and idx < branchCandidates.len:
      let center = branchCandidates[idx]
      uniqueAdd(center, placed)
      placeBridgeBranch(terrain, center)
      dec remaining
      idx += stride

proc createTerrainCluster*(terrain: var TerrainGrid, centerX, centerY: int, size: int,
                          mapWidth, mapHeight: int, terrainType: TerrainType,
                          baseDensity: float, falloffRate: float, r: var Rand) =
  ## Create a terrain cluster around a center point with configurable density
  let radius = (size.float / 2.0).int
  for dx in -radius .. radius:
    for dy in -radius .. radius:
      let x = centerX + dx
      let y = centerY + dy
      if x >= 0 and x < mapWidth and y >= 0 and y < mapHeight:
        if terrain[x][y] == Empty:
          let dist = sqrt((dx * dx + dy * dy).float)
          if dist <= radius.float:
            let chance = baseDensity - (dist / radius.float) * falloffRate
            if randChance(r, chance):
              terrain[x][y] = terrainType

proc generateWheatFields*(terrain: var TerrainGrid, mapWidth, mapHeight, mapBorder: int, r: var Rand) =
  ## Generate clustered wheat fields; boosted count for richer biomes
  let numFields = randInclusive(r, WheatFieldClusterBase, WheatFieldClusterBase + WheatFieldClusterRange) *
    WheatFieldClusterScale

  for i in 0 ..< numFields:
    var placed = false
    for attempt in 0 ..< 20:
      let x = randInclusive(r, mapBorder + 3, mapWidth - mapBorder - 3)
      let y = randInclusive(r, mapBorder + 3, mapHeight - mapBorder - 3)

      var nearWater = false
      for dx in -5 .. 5:
        for dy in -5 .. 5:
          let checkX = x + dx
          let checkY = y + dy
          if checkX >= 0 and checkX < mapWidth and checkY >= 0 and checkY < mapHeight:
            if terrain[checkX][checkY] == Water:
              nearWater = true
              break
        if nearWater:
          break

      if nearWater or attempt > 10:
        let fieldSize = randInclusive(r, 5, 12)
        terrain.createTerrainCluster(x, y, fieldSize, mapWidth, mapHeight, Wheat, 1.0, 0.3, r)
        terrain.createTerrainCluster(x, y, fieldSize + 1, mapWidth, mapHeight, Wheat, 0.5, 0.3, r)
        placed = true
        break

    if not placed:
      let x = randInclusive(r, mapBorder + 3, mapWidth - mapBorder - 3)
      let y = randInclusive(r, mapBorder + 3, mapHeight - mapBorder - 3)
      let fieldSize = randInclusive(r, 5, 12)
      terrain.createTerrainCluster(x, y, fieldSize, mapWidth, mapHeight, Wheat, 1.0, 0.3, r)
      terrain.createTerrainCluster(x, y, fieldSize + 1, mapWidth, mapHeight, Wheat, 0.5, 0.3, r)

proc generateTrees*(terrain: var TerrainGrid, mapWidth, mapHeight, mapBorder: int, r: var Rand) =
  ## Generate tree groves; boosted count for richer biomes
  let numGroves = randInclusive(r, TreeGroveClusterBase, TreeGroveClusterBase + TreeGroveClusterRange) *
    TreeGroveClusterScale

  for i in 0 ..< numGroves:
    let x = randInclusive(r, mapBorder + 3, mapWidth - mapBorder - 3)
    let y = randInclusive(r, mapBorder + 3, mapHeight - mapBorder - 3)
    let groveSize = randInclusive(r, 3, 10)
    terrain.createTerrainCluster(x, y, groveSize, mapWidth, mapHeight, Tree, 0.8, 0.4, r)

proc generatePalmGroves*(terrain: var TerrainGrid, mapWidth, mapHeight, mapBorder: int, r: var Rand) =
  let numGroves = randInclusive(r, PalmGroveClusterBase, PalmGroveClusterBase + PalmGroveClusterRange) *
    PalmGroveClusterScale
  for i in 0 ..< numGroves:
    var placed = false
    for attempt in 0 ..< 16:
      let x = randInclusive(r, mapBorder + 3, mapWidth - mapBorder - 3)
      let y = randInclusive(r, mapBorder + 3, mapHeight - mapBorder - 3)
      var nearWater = false
      for dx in -5 .. 5:
        for dy in -5 .. 5:
          let checkX = x + dx
          let checkY = y + dy
          if checkX >= 0 and checkX < mapWidth and checkY >= 0 and checkY < mapHeight:
            if terrain[checkX][checkY] == Water:
              nearWater = true
              break
        if nearWater:
          break
      if nearWater or attempt > 10:
        let groveSize = randInclusive(r, 3, 8)
        terrain.createTerrainCluster(x, y, groveSize, mapWidth, mapHeight, Palm, 0.85, 0.4, r)
        let oasisW = randInclusive(r, 3, 5)
        let oasisH = randInclusive(r, 3, 5)
        let x0 = x - (oasisW div 2)
        let y0 = y - (oasisH div 2)
        for ox in 0 ..< oasisW:
          for oy in 0 ..< oasisH:
            let px = x0 + ox
            let py = y0 + oy
            if px < mapBorder or px >= mapWidth - mapBorder or py < mapBorder or py >= mapHeight - mapBorder:
              continue
            terrain[px][py] = Water
        placed = true
        break
    if not placed:
      let x = randInclusive(r, mapBorder + 3, mapWidth - mapBorder - 3)
      let y = randInclusive(r, mapBorder + 3, mapHeight - mapBorder - 3)
      let groveSize = randInclusive(r, 3, 8)
      terrain.createTerrainCluster(x, y, groveSize, mapWidth, mapHeight, Palm, 0.85, 0.4, r)
      let oasisW = randInclusive(r, 3, 5)
      let oasisH = randInclusive(r, 3, 5)
      let x0 = x - (oasisW div 2)
      let y0 = y - (oasisH div 2)
      for ox in 0 ..< oasisW:
        for oy in 0 ..< oasisH:
          let px = x0 + ox
          let py = y0 + oy
          if px < mapBorder or px >= mapWidth - mapBorder or py < mapBorder or py >= mapHeight - mapBorder:
            continue
          terrain[px][py] = Water

proc generateRockOutcrops*(terrain: var TerrainGrid, mapWidth, mapHeight, mapBorder: int, r: var Rand) =
  let clusters = max(16, mapWidth div 25)
  for i in 0 ..< clusters:
    let x = randInclusive(r, mapBorder + 4, mapWidth - mapBorder - 4)
    let y = randInclusive(r, mapBorder + 4, mapHeight - mapBorder - 4)
    let size = randInclusive(r, 3, 7)
    terrain.createTerrainCluster(x, y, size, mapWidth, mapHeight, Rock, 0.85, 0.35, r)

proc generateGemVeins*(terrain: var TerrainGrid, mapWidth, mapHeight, mapBorder: int, r: var Rand) =
  let clusters = max(8, mapWidth div 50)
  for i in 0 ..< clusters:
    let x = randInclusive(r, mapBorder + 6, mapWidth - mapBorder - 6)
    let y = randInclusive(r, mapBorder + 6, mapHeight - mapBorder - 6)
    let size = randInclusive(r, 2, 4)
    terrain.createTerrainCluster(x, y, size, mapWidth, mapHeight, Gem, 0.7, 0.5, r)

proc generateBushes*(terrain: var TerrainGrid, mapWidth, mapHeight, mapBorder: int, r: var Rand) =
  for i in 0 ..< 30:
    var attempts = 0
    var placed = false
    while attempts < 12 and not placed:
      inc attempts
      let x = randInclusive(r, mapBorder + 2, mapWidth - mapBorder - 2)
      let y = randInclusive(r, mapBorder + 2, mapHeight - mapBorder - 2)
      var nearWater = false
      for dx in -4 .. 4:
        for dy in -4 .. 4:
          let checkX = x + dx
          let checkY = y + dy
          if checkX >= 0 and checkX < mapWidth and checkY >= 0 and checkY < mapHeight:
            if terrain[checkX][checkY] == Water:
              nearWater = true
              break
        if nearWater:
          break
      if nearWater or attempts >= 10:
        let size = randInclusive(r, 3, 7)
        terrain.createTerrainCluster(x, y, size, mapWidth, mapHeight, Bush, 0.75, 0.45, r)
        placed = true

proc generateAnimals*(terrain: var TerrainGrid, mapWidth, mapHeight, mapBorder: int, r: var Rand) =
  for i in 0 ..< 24:
    let x = randInclusive(r, mapBorder + 3, mapWidth - mapBorder - 3)
    let y = randInclusive(r, mapBorder + 3, mapHeight - mapBorder - 3)
    let size = randInclusive(r, 2, 4)
    terrain.createTerrainCluster(x, y, size, mapWidth, mapHeight, Animal, 0.6, 0.6, r)

proc initTerrain*(terrain: var TerrainGrid, biomes: var BiomeGrid,
                  mapWidth, mapHeight, mapBorder: int, seed: int = 2024) =
  ## Initialize terrain with all features
  var r = initRand(seed)

  if mapWidth > terrain.len or mapHeight > terrain[0].len:
    raise newException(ValueError, "Map size exceeds TerrainGrid bounds")

  for x in 0 ..< mapWidth:
    for y in 0 ..< mapHeight:
      terrain[x][y] = Empty
      biomes[x][y] = BiomeNone

  # Set base biome background across the playable area.
  let baseBiomeType = case BaseBiome:
    of BiomeForest: BiomeForestType
    of BiomeDesert: BiomeDesertType
    of BiomeCaves: BiomeCavesType
    of BiomeCity: BiomeCityType
    of BiomePlains: BiomePlainsType
  for x in mapBorder ..< mapWidth - mapBorder:
    for y in mapBorder ..< mapHeight - mapBorder:
      biomes[x][y] = baseBiomeType

  if UseBiomeTerrain:
    applyBaseBiome(terrain, mapWidth, mapHeight, mapBorder, r)
  if UseBiomeZones:
    applyBiomeZones(terrain, biomes, mapWidth, mapHeight, mapBorder, r)

  terrain.generateRiver(mapWidth, mapHeight, mapBorder, r)
  terrain.generateWheatFields(mapWidth, mapHeight, mapBorder, r)
  if UsePalmGroves:
    terrain.generatePalmGroves(mapWidth, mapHeight, mapBorder, r)
  if UseLegacyTreeClusters:
    terrain.generateTrees(mapWidth, mapHeight, mapBorder, r)
  terrain.generateRockOutcrops(mapWidth, mapHeight, mapBorder, r)
  terrain.generateGemVeins(mapWidth, mapHeight, mapBorder, r)
  terrain.generateBushes(mapWidth, mapHeight, mapBorder, r)
  terrain.generateAnimals(mapWidth, mapHeight, mapBorder, r)

proc getStructureElements*(structure: Structure, topLeft: IVec2): tuple[
    walls: seq[IVec2],
    doors: seq[IVec2],
    floors: seq[IVec2],
    assemblers: seq[IVec2],
    forges: seq[IVec2],
    armories: seq[IVec2],
    clayOvens: seq[IVec2],
    weavingLooms: seq[IVec2],
    beds: seq[IVec2],
    chairs: seq[IVec2],
    tables: seq[IVec2],
    statues: seq[IVec2],
    center: IVec2
  ] =
  ## Extract tiles for placing a structure
  result = (
    walls: @[],
    doors: @[],
    floors: @[],
    assemblers: @[],
    forges: @[],
    armories: @[],
    clayOvens: @[],
    weavingLooms: @[],
    beds: @[],
    chairs: @[],
    tables: @[],
    statues: @[],
    center: topLeft + structure.centerPos
  )

  for y, row in structure.layout:
    for x, cell in row:
      let pos = ivec2(topLeft.x + x.int32, topLeft.y + y.int32)
      case cell
      of '#': result.walls.add(pos)
      of 'D': result.doors.add(pos)
      of '.': result.floors.add(pos)
      of 'a': result.assemblers.add(pos)
      of 'F': result.forges.add(pos)
      of 'A': result.armories.add(pos)
      of 'C': result.clayOvens.add(pos)
      of 'W': result.weavingLooms.add(pos)
      of 'B': result.beds.add(pos)
      of 'H': result.chairs.add(pos)
      of 'T': result.tables.add(pos)
      of 'S': result.statues.add(pos)
      else: discard
