import std/math, vmath
import entropy
import forest, desert, caves, city, plains, snow, biome
import maze, radial

const
  # Keep in sync with biome.nim's MaxBiomeSize.
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
    Gold
    Bush
    Animal
    Grass
    Cactus
    Dune
    Stalagmite
    Palm
    Sand
    Snow

  ## Sized to comfortably exceed current MapWidth/MapHeight.
  TerrainGrid* = array[MaxTerrainSize, array[MaxTerrainSize, TerrainType]]

  Structure* = object
    width*, height*: int
    centerPos*: IVec2
    layout*: seq[seq[char]]

const
  # Structure layout ASCII schema (typeable characters).
  StructureWallChar* = '#'
  StructureFloorChar* = '.'
  StructureDoorChar* = 'D'
  StructureAltarChar* = 'a'
  StructureArmoryChar* = 'A'
  StructureBlacksmithChar* = 'F'
  StructureClayOvenChar* = 'C'
  StructureWeavingLoomChar* = 'W'
  StructureTownCenterChar* = 'N'
  StructureBarracksChar* = 'R'
  StructureArcheryRangeChar* = 'G'
  StructureStableChar* = 'P'
  StructureSiegeWorkshopChar* = 'I'
  StructureMarketChar* = 'M'
  StructureDockChar* = 'K'
  StructureUniversityChar* = 'U'

type
  BiomeKind* = enum
    BiomeBase
    BiomeForest
    BiomeDesert
    BiomeCaves
    BiomeCity
    BiomePlains
    BiomeSnow

  BiomeType* = enum
    BiomeNone
    BiomeBaseType
    BiomeForestType
    BiomeDesertType
    BiomeCavesType
    BiomeCityType
    BiomePlainsType
    BiomeSnowType
    BiomeDungeonType

  BiomeGrid* = array[MaxTerrainSize, array[MaxTerrainSize, BiomeType]]

  DungeonKind* = enum
    DungeonMaze
    DungeonRadial

const
  UseBiomeTerrain* = true
  BaseBiome* = BiomeBase
  BiomeForestTerrain* = Tree
  BiomeDesertTerrain* = Sand
  BiomeCavesTerrain* = Stalagmite
  BiomePlainsTerrain* = Grass
  BiomeSnowTerrain* = Snow
  BiomeCityBlockTerrain* = Rock
  BiomeCityRoadTerrain* = Road
  UseBiomeZones* = true
  UseDungeonZones* = true
  UseSequentialBiomeZones* = true
  UseSequentialDungeonZones* = true
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
  # Slightly lower biome/dungeon density for less crowded maps.
  BiomeZoneDivisor* = 5000
  DungeonZoneDivisor* = 7800
  BiomeZoneMinCount* = 5
  BiomeZoneMaxCount* = 16
  DungeonZoneMinCount* = 4
  DungeonZoneMaxCount* = 14
  BiomeZoneMaxFraction* = 0.48
  DungeonZoneMaxFraction* = 0.24
  ZoneMinSize* = 18
  BiomeBlendDepth* = 6
  BiomeZoneGridJitter* = 0.35
  BiomeZoneCellFill* = 0.95
  ZoneBlobNoise* = 0.35
  ZoneBlobLobesMin* = 1
  ZoneBlobLobesMax* = 3
  ZoneBlobLobeOffset* = 0.7
  ZoneBlobAnisotropy* = 0.45
  ZoneBlobBiteCountMin* = 1
  ZoneBlobBiteCountMax* = 4
  ZoneBlobBiteScaleMin* = 0.28
  ZoneBlobBiteScaleMax* = 0.7
  ZoneBlobBiteAngleMin* = 0.35
  ZoneBlobBiteAngleMax* = 0.75
  ZoneBlobJaggedPasses* = 2
  ZoneBlobJaggedProb* = 0.18
  ZoneBlobDitherProb* = 0.12
  ZoneBlobDitherDepth* = 4
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
  TerrainGold* = TerrainType.Gold
  TerrainBush* = TerrainType.Bush
  TerrainAnimal* = TerrainType.Animal
  TerrainGrass* = TerrainType.Grass
  TerrainCactus* = TerrainType.Cactus
  TerrainDune* = TerrainType.Dune
  TerrainStalagmite* = TerrainType.Stalagmite
  TerrainSand* = TerrainType.Sand
  TerrainSnow* = TerrainType.Snow

template isBlockedTerrain*(terrain: TerrainType): bool =
  terrain == Water

template randInclusive(r: var Rand, a, b: int): int = randIntInclusive(r, a, b)
template randChance(r: var Rand, p: float): bool = randFloat(r) < p

const
  RiverWidth* = 6

type
  ZoneRect* = object
    x*, y*, w*, h*: int

proc applyMaskToTerrain(terrain: var TerrainGrid, mask: MaskGrid, mapWidth, mapHeight, mapBorder: int,
                        terrainType: TerrainType) =
  for x in mapBorder ..< mapWidth - mapBorder:
    for y in mapBorder ..< mapHeight - mapBorder:
      if mask[x][y] and terrain[x][y] == Empty:
        terrain[x][y] = terrainType

proc blendChanceForDistance(dist, depth: int, edgeChance: float): float =
  if depth <= 0:
    return 1.0
  let t = min(1.0, dist.float / depth.float)
  edgeChance + (1.0 - edgeChance) * t

proc canApplyBiome(currentBiome, biomeType, baseBiomeType: BiomeType): bool =
  currentBiome == BiomeNone or currentBiome == baseBiomeType or currentBiome == biomeType

proc baseBiomeType*(): BiomeType =
  case BaseBiome:
  of BiomeBase: BiomeBaseType
  of BiomeForest: BiomeForestType
  of BiomeDesert: BiomeDesertType
  of BiomeCaves: BiomeCavesType
  of BiomeCity: BiomeCityType
  of BiomePlains: BiomePlainsType
  of BiomeSnow: BiomeSnowType

proc zoneBounds(zone: ZoneRect, mapWidth, mapHeight, mapBorder: int): tuple[x0, y0, x1, y1: int] =
  let x0 = max(mapBorder, zone.x)
  let y0 = max(mapBorder, zone.y)
  let x1 = min(mapWidth - mapBorder, zone.x + zone.w)
  let y1 = min(mapHeight - mapBorder, zone.y + zone.h)
  (x0: x0, y0: y0, x1: x1, y1: y1)

proc maskEdgeDistance*(mask: MaskGrid, mapWidth, mapHeight: int, x, y, maxDepth: int): int =
  if not mask[x][y]:
    return 0
  for depth in 0 .. maxDepth:
    let radius = depth + 1
    for dx in -radius .. radius:
      for dy in -radius .. radius:
        if abs(dx) != radius and abs(dy) != radius:
          continue
        let nx = x + dx
        let ny = y + dy
        if nx < 0 or nx >= mapWidth or ny < 0 or ny >= mapHeight:
          return depth
        if not mask[nx][ny]:
          return depth
  maxDepth + 1

proc applyBiomeMaskToZone(terrain: var TerrainGrid, biomes: var BiomeGrid, mask: MaskGrid,
                          zoneMask: MaskGrid, zone: ZoneRect, mapWidth, mapHeight, mapBorder: int,
                          terrainType: TerrainType, biomeType: BiomeType, baseBiomeType: BiomeType,
                          r: var Rand, edgeChance: float, blendDepth: int = BiomeBlendDepth,
                          density: float = 1.0) =
  let (x0, y0, x1, y1) = zoneBounds(zone, mapWidth, mapHeight, mapBorder)
  if x1 <= x0 or y1 <= y0:
    return
  for x in x0 ..< x1:
    for y in y0 ..< y1:
      if not zoneMask[x][y] or not mask[x][y]:
        continue
      if not canApplyBiome(biomes[x][y], biomeType, baseBiomeType):
        continue
      let maskDist = maskEdgeDistance(mask, mapWidth, mapHeight, x, y, blendDepth)
      let zoneDist = maskEdgeDistance(zoneMask, mapWidth, mapHeight, x, y, blendDepth)
      let edgeDist = min(maskDist, zoneDist)
      let chance = min(1.0, blendChanceForDistance(edgeDist, blendDepth, edgeChance) * density)
      if terrain[x][y] == Empty or randChance(r, chance):
        terrain[x][y] = terrainType
      if randChance(r, chance):
        biomes[x][y] = biomeType

proc applyTerrainBlendToZone(terrain: var TerrainGrid, biomes: var BiomeGrid, zoneMask: MaskGrid,
                             zone: ZoneRect, mapWidth, mapHeight, mapBorder: int,
                             terrainType: TerrainType, biomeType: BiomeType,
                             baseBiomeType: BiomeType, r: var Rand, edgeChance: float,
                             blendDepth: int = BiomeBlendDepth, overwriteWater = false,
                             density: float = 1.0) =
  let (x0, y0, x1, y1) = zoneBounds(zone, mapWidth, mapHeight, mapBorder)
  if x1 <= x0 or y1 <= y0:
    return
  for x in x0 ..< x1:
    for y in y0 ..< y1:
      if not overwriteWater and terrain[x][y] == Water:
        continue
      if not zoneMask[x][y]:
        continue
      if not canApplyBiome(biomes[x][y], biomeType, baseBiomeType):
        continue
      let edgeDist = maskEdgeDistance(zoneMask, mapWidth, mapHeight, x, y, blendDepth)
      let chance = min(1.0, blendChanceForDistance(edgeDist, blendDepth, edgeChance) * density)
      if randChance(r, chance):
        terrain[x][y] = terrainType
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

proc evenlyDistributedZones*(r: var Rand, mapWidth, mapHeight, mapBorder: int, count: int,
                             maxFraction: float): seq[ZoneRect] =
  if count <= 0:
    return @[]
  let playableW = max(1, mapWidth - mapBorder * 2)
  let playableH = max(1, mapHeight - mapBorder * 2)
  let aspect = playableW.float / playableH.float
  let cols = max(1, int(round(sqrt(count.float * aspect))))
  let rows = max(1, int(ceil(count.float / cols.float)))
  let cellW = playableW.float / cols.float
  let cellH = playableH.float / rows.float

  var cells: seq[tuple[cx, cy: int]] = @[]
  for cy in 0 ..< rows:
    for cx in 0 ..< cols:
      cells.add((cx, cy))

  for i in countdown(cells.len - 1, 1):
    let j = randIntInclusive(r, 0, i)
    swap(cells[i], cells[j])

  let maxW = max(ZoneMinSize, int(playableW.float * maxFraction))
  let maxH = max(ZoneMinSize, int(playableH.float * maxFraction))

  result = @[]
  for i in 0 ..< min(count, cells.len):
    let cell = cells[i]
    let jitterX = (randFloat(r) - 0.5) * BiomeZoneGridJitter * cellW
    let jitterY = (randFloat(r) - 0.5) * BiomeZoneGridJitter * cellH
    let centerX = mapBorder.float + (cell.cx.float + 0.5) * cellW + jitterX
    let centerY = mapBorder.float + (cell.cy.float + 0.5) * cellH + jitterY

    let sizeW = clamp(int(cellW * BiomeZoneCellFill * (0.85 + 0.3 * randFloat(r))), ZoneMinSize, maxW)
    let sizeH = clamp(int(cellH * BiomeZoneCellFill * (0.85 + 0.3 * randFloat(r))), ZoneMinSize, maxH)
    let x = clamp(int(centerX) - sizeW div 2, mapBorder, mapWidth - mapBorder - sizeW)
    let y = clamp(int(centerY) - sizeH div 2, mapBorder, mapHeight - mapBorder - sizeH)
    result.add(ZoneRect(x: x, y: y, w: sizeW, h: sizeH))

proc buildZoneBlobMask*(mask: var MaskGrid, mapWidth, mapHeight, mapBorder: int,
                        zone: ZoneRect, r: var Rand) =
  mask.clearMask(mapWidth, mapHeight)
  let (x0, y0, x1, y1) = zoneBounds(zone, mapWidth, mapHeight, mapBorder)
  if x1 <= x0 or y1 <= y0:
    return
  let cx = (x0 + x1 - 1) div 2
  let cy = (y0 + y1 - 1) div 2
  let rx = max(2, (x1 - x0) div 2)
  let ry = max(2, (y1 - y0) div 2)
  let lobeCount = randInclusive(r, ZoneBlobLobesMin, ZoneBlobLobesMax)
  var lobes: seq[tuple[cx, cy, rx, ry: float]] = @[]
  let baseStretch = max(0.35, 1.0 + (randFloat(r) * 2.0 - 1.0) * ZoneBlobAnisotropy)
  lobes.add((
    cx: cx.float,
    cy: cy.float,
    rx: max(2.0, rx.float * baseStretch),
    ry: max(2.0, ry.float / baseStretch)
  ))
  if lobeCount > 1:
    let minRadius = min(rx.float, ry.float)
    for _ in 1 ..< lobeCount:
      let angle = randFloat(r) * 2.0 * PI
      let offset = (0.35 + 0.55 * randFloat(r)) * minRadius * ZoneBlobLobeOffset
      let stretch = max(0.35, 1.0 + (randFloat(r) * 2.0 - 1.0) * ZoneBlobAnisotropy)
      let lrx = max(2.0, rx.float * (0.45 + 0.55 * randFloat(r)) * stretch)
      let lry = max(2.0, ry.float * (0.45 + 0.55 * randFloat(r)) / stretch)
      lobes.add((
        cx: cx.float + cos(angle) * offset,
        cy: cy.float + sin(angle) * offset,
        rx: lrx,
        ry: lry
      ))

  for x in x0 ..< x1:
    for y in y0 ..< y1:
      let noise = (randFloat(r) - 0.5) * ZoneBlobNoise
      var inside = false
      for lobe in lobes:
        let dx = (x.float - lobe.cx) / lobe.rx
        let dy = (y.float - lobe.cy) / lobe.ry
        let dist = dx * dx + dy * dy
        if dist <= 1.0 + noise:
          inside = true
          break
      if inside:
        mask[x][y] = true

  let baseRadius = max(2, min(rx, ry))
  let biteCount = randInclusive(r, ZoneBlobBiteCountMin, ZoneBlobBiteCountMax)
  for _ in 0 ..< biteCount:
    var bx = randInclusive(r, x0, x1 - 1)
    var by = randInclusive(r, y0, y1 - 1)
    var attempts = 0
    while attempts < 10 and not mask[bx][by]:
      bx = randInclusive(r, x0, x1 - 1)
      by = randInclusive(r, y0, y1 - 1)
      inc attempts
    if not mask[bx][by]:
      continue
    let biteMin = max(2, int(baseRadius.float * ZoneBlobBiteScaleMin))
    let biteMax = max(biteMin, int(baseRadius.float * ZoneBlobBiteScaleMax))
    let biteRadius = randInclusive(r, biteMin, biteMax)
    let biteAngle = randFloat(r) * 2.0 * PI
    let biteSpread = (ZoneBlobBiteAngleMin + randFloat(r) *
      (ZoneBlobBiteAngleMax - ZoneBlobBiteAngleMin)) * PI
    let minX = max(x0, bx - biteRadius)
    let maxX = min(x1 - 1, bx + biteRadius)
    let minY = max(y0, by - biteRadius)
    let maxY = min(y1 - 1, by + biteRadius)
    for x in minX .. maxX:
      for y in minY .. maxY:
        if not mask[x][y]:
          continue
        let dx = x - bx
        let dy = y - by
        if dx * dx + dy * dy > biteRadius * biteRadius:
          continue
        var ang = arctan2(dy.float, dx.float) - biteAngle
        while ang > PI:
          ang -= 2.0 * PI
        while ang < -PI:
          ang += 2.0 * PI
        if abs(ang) <= biteSpread:
          mask[x][y] = false

  for _ in 0 ..< ZoneBlobJaggedPasses:
    var nextMask = mask
    for x in x0 ..< x1:
      for y in y0 ..< y1:
        if not mask[x][y]:
          continue
        var edge = false
        for dx in -1 .. 1:
          for dy in -1 .. 1:
            if dx == 0 and dy == 0:
              continue
            let nx = x + dx
            let ny = y + dy
            if nx < x0 or nx >= x1 or ny < y0 or ny >= y1 or not mask[nx][ny]:
              edge = true
              break
          if edge:
            break
        if edge and randChance(r, ZoneBlobJaggedProb):
          nextMask[x][y] = false
    mask = nextMask

  mask[cx][cy] = true
  ditherEdges(mask, mapWidth, mapHeight, ZoneBlobDitherProb, ZoneBlobDitherDepth, r)

proc zoneCount*(area: int, divisor: int, minCount: int, maxCount: int): int =
  let raw = max(1, area div divisor)
  clamp(raw, minCount, maxCount)

proc pickDungeonKind*(r: var Rand): DungeonKind =
  let kinds = [DungeonMaze, DungeonRadial]
  let weights = [1.0, 0.6]
  pickWeighted(r, kinds, weights)

proc buildDungeonMask*(mask: var MaskGrid, mapWidth, mapHeight: int, zone: ZoneRect,
                       r: var Rand, kind: DungeonKind) =
  case kind:
  of DungeonMaze:
    buildDungeonMazeMask(mask, mapWidth, mapHeight, zone.x, zone.y, zone.w, zone.h, r, DungeonMazeConfig())
  of DungeonRadial:
    buildDungeonRadialMask(mask, mapWidth, mapHeight, zone.x, zone.y, zone.w, zone.h, r, DungeonRadialConfig())

proc applyBiomeZones(terrain: var TerrainGrid, biomes: var BiomeGrid, mapWidth, mapHeight, mapBorder: int,
                     r: var Rand) =
  var count = zoneCount(mapWidth * mapHeight, BiomeZoneDivisor, BiomeZoneMinCount, BiomeZoneMaxCount)
  let kinds = [BiomeForest, BiomeDesert, BiomeCaves, BiomeCity, BiomePlains, BiomeSnow]
  let weights = [1.0, 1.0, 0.6, 0.6, 1.0, 0.8]
  if UseSequentialBiomeZones:
    count = max(count, kinds.len)
  let baseBiomeType = baseBiomeType()
  var seqIdx = randIntInclusive(r, 0, kinds.len - 1)
  let edgeChance = 0.25
  let zones = evenlyDistributedZones(r, mapWidth, mapHeight, mapBorder, count, BiomeZoneMaxFraction)
  for zone in zones:
    let biome = if UseSequentialBiomeZones:
      let selected = kinds[seqIdx mod kinds.len]
      inc seqIdx
      selected
    else:
      pickWeighted(r, kinds, weights)
    var mask: MaskGrid
    var zoneMask: MaskGrid
    buildZoneBlobMask(zoneMask, mapWidth, mapHeight, mapBorder, zone, r)
    case biome:
    of BiomeBase:
      discard
    of BiomeForest:
      buildBiomeForestMask(mask, mapWidth, mapHeight, mapBorder, r, BiomeForestConfig())
      applyBiomeMaskToZone(terrain, biomes, mask, zoneMask, zone, mapWidth, mapHeight, mapBorder,
        BiomeForestTerrain, BiomeForestType, baseBiomeType, r, edgeChance)
    of BiomeDesert:
      # Blend sand into the zone so edges ease into the base biome, then layer dunes.
      applyTerrainBlendToZone(terrain, biomes, zoneMask, zone, mapWidth, mapHeight, mapBorder,
        TerrainSand, BiomeDesertType, baseBiomeType, r, edgeChance, density = 0.3)
      buildBiomeDesertMask(mask, mapWidth, mapHeight, mapBorder, r, BiomeDesertConfig())
      applyBiomeMaskToZone(terrain, biomes, mask, zoneMask, zone, mapWidth, mapHeight, mapBorder,
        TerrainDune, BiomeDesertType, baseBiomeType, r, edgeChance)
    of BiomeCaves:
      buildBiomeCavesMask(mask, mapWidth, mapHeight, mapBorder, r, BiomeCavesConfig())
      applyBiomeMaskToZone(terrain, biomes, mask, zoneMask, zone, mapWidth, mapHeight, mapBorder,
        BiomeCavesTerrain, BiomeCavesType, baseBiomeType, r, edgeChance)
    of BiomeSnow:
      # Blend snow into the zone, then add clustered accents for texture.
      applyTerrainBlendToZone(terrain, biomes, zoneMask, zone, mapWidth, mapHeight, mapBorder,
        TerrainSnow, BiomeSnowType, baseBiomeType, r, edgeChance, density = 0.25)
      buildBiomeSnowMask(mask, mapWidth, mapHeight, mapBorder, r, BiomeSnowConfig())
      let snowEdgeChance = max(edgeChance, 0.55)
      applyBiomeMaskToZone(terrain, biomes, mask, zoneMask, zone, mapWidth, mapHeight, mapBorder,
        BiomeSnowTerrain, BiomeSnowType, baseBiomeType, r, snowEdgeChance, density = 0.25)
      # Add sparse snowy pine clusters and boulder outcrops for more visual interest.
      var pineMask: MaskGrid
      let pineCfg = BiomeForestConfig(
        clumpiness: 1,
        seedProb: 0.012,
        growthProb: 0.45,
        neighborThreshold: 3,
        ditherEdges: true,
        ditherProb: 0.18,
        ditherDepth: 3
      )
      buildBiomeForestMask(pineMask, mapWidth, mapHeight, mapBorder, r, pineCfg)
      let (px0, py0, px1, py1) = zoneBounds(zone, mapWidth, mapHeight, mapBorder)
      for x in px0 ..< px1:
        for y in py0 ..< py1:
          if terrain[x][y] == Water:
            pineMask[x][y] = false
      applyBiomeMaskToZone(terrain, biomes, pineMask, zoneMask, zone, mapWidth, mapHeight, mapBorder,
        Tree, BiomeSnowType, baseBiomeType, r, 0.2, blendDepth = 2)

      var boulderMask: MaskGrid
      let boulderCfg = BiomeSnowConfig(
        clusterPeriod: 16,
        clusterMinRadius: 1,
        clusterMaxRadius: 2,
        clusterFill: 0.45,
        clusterProb: 0.35,
        jitter: 3,
        ditherEdges: false,
        ditherProb: 0.0,
        ditherDepth: 0
      )
      buildBiomeSnowMask(boulderMask, mapWidth, mapHeight, mapBorder, r, boulderCfg)
      for x in px0 ..< px1:
        for y in py0 ..< py1:
          if terrain[x][y] == Water:
            boulderMask[x][y] = false
      applyBiomeMaskToZone(terrain, biomes, boulderMask, zoneMask, zone, mapWidth, mapHeight, mapBorder,
        Rock, BiomeSnowType, baseBiomeType, r, 0.15, blendDepth = 1)

      # Place larger square-ish rock chunks (12-14 rocks) within the snow zone.
      let area = (px1 - px0) * (py1 - py0)
      var clumpCount = 1
      if area > 4000: clumpCount = 2
      if area > 8000: clumpCount = 3
      if area > 12000: clumpCount = 4
      clumpCount = min(5, clumpCount + randInclusive(r, 0, 1))
      for _ in 0 ..< clumpCount:
        var placedClump = false
        for attempt in 0 ..< 24:
          let clumpW = 4
          let clumpH = 4
          if px1 - px0 <= clumpW or py1 - py0 <= clumpH:
            break
          let startX = randInclusive(r, px0, px1 - clumpW)
          let startY = randInclusive(r, py0, py1 - clumpH)
          var candidates: seq[tuple[x, y: int]] = @[]
          for x in startX ..< startX + clumpW:
            for y in startY ..< startY + clumpH:
              if not zoneMask[x][y]:
                continue
              if biomes[x][y] != BiomeSnowType:
                continue
              if terrain[x][y] in {Water, Tree, Rock}:
                continue
              candidates.add((x: x, y: y))
          if candidates.len < 12:
            continue
          for i in countdown(candidates.len - 1, 1):
            let j = randInclusive(r, 0, i)
            swap(candidates[i], candidates[j])
          let target = randInclusive(r, 12, 14)
          let take = min(target, candidates.len)
          for i in 0 ..< take:
            let pos = candidates[i]
            terrain[pos.x][pos.y] = Rock
          placedClump = true
          break
        if not placedClump:
          discard
    of BiomeCity:
      var roadMask: MaskGrid
      buildBiomeCityMasks(mask, roadMask, mapWidth, mapHeight, mapBorder, r, BiomeCityConfig())
      applyBiomeMaskToZone(terrain, biomes, mask, zoneMask, zone, mapWidth, mapHeight, mapBorder,
        BiomeCityBlockTerrain, BiomeCityType, baseBiomeType, r, edgeChance)
      applyBiomeMaskToZone(terrain, biomes, roadMask, zoneMask, zone, mapWidth, mapHeight, mapBorder,
        BiomeCityRoadTerrain, BiomeCityType, baseBiomeType, r, edgeChance)
    of BiomePlains:
      buildBiomePlainsMask(mask, mapWidth, mapHeight, mapBorder, r, BiomePlainsConfig())
      applyBiomeMaskToZone(terrain, biomes, mask, zoneMask, zone, mapWidth, mapHeight, mapBorder,
        BiomePlainsTerrain, BiomePlainsType, baseBiomeType, r, edgeChance)

proc applyBaseBiome(terrain: var TerrainGrid, mapWidth, mapHeight, mapBorder: int, r: var Rand) =
  var mask: MaskGrid
  case BaseBiome:
  of BiomeBase:
    discard
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
  of BiomeSnow:
    buildBiomeSnowMask(mask, mapWidth, mapHeight, mapBorder, r, BiomeSnowConfig())
    applyMaskToTerrain(terrain, mask, mapWidth, mapHeight, mapBorder, BiomeSnowTerrain)

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

  while currentPos.x >= mapBorder and currentPos.x < mapWidth - mapBorder and
        currentPos.y >= mapBorder and currentPos.y < mapHeight - mapBorder:
    riverPath.add(currentPos)

    currentPos.x += 1  # Always move right
    if randChance(r, 0.3):
      currentPos.y += sample(r, [-1, 0, 0, 1]).int32  # Bias towards staying straight

  proc buildBranch(start: IVec2, dirY: int, r: var Rand): seq[IVec2] =
    var path: seq[IVec2] = @[]
    var secondaryPos = start
    let maxSteps = max(mapWidth * 2, mapHeight * 2)
    var steps = 0
    while secondaryPos.y > mapBorder + RiverWidth and secondaryPos.y < mapHeight - mapBorder - RiverWidth and steps < maxSteps:
      secondaryPos.x += 1
      secondaryPos.y += dirY.int32
      if randChance(r, 0.15):
        secondaryPos.y += sample(r, [-1, 0, 1]).int32
      if secondaryPos.x >= mapBorder and secondaryPos.x < mapWidth - mapBorder and
         secondaryPos.y >= mapBorder and secondaryPos.y < mapHeight - mapBorder:
        if not inCornerReserve(secondaryPos.x, secondaryPos.y, mapWidth, mapHeight, mapBorder, reserve):
          path.add(secondaryPos)
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
            path.add(tip)
        inc pushSteps
    else:
      while tip.y < mapHeight - mapBorder and pushSteps < maxPush:
        inc tip.y
        if tip.x >= mapBorder and tip.x < mapWidth and tip.y >= mapBorder and tip.y < mapHeight:
          if not inCornerReserve(tip.x, tip.y, mapWidth, mapHeight, mapBorder, reserve):
            path.add(tip)
        inc pushSteps
    path

  var branchUpPath: seq[IVec2] = @[]
  var branchDownPath: seq[IVec2] = @[]
  var forkUp: IVec2
  var forkDown: IVec2
  var forkUpIdx = -1
  var forkDownIdx = -1
  var forkCandidates: seq[IVec2] = @[]
  for pos in riverPath:
    if pos.y > mapBorder + RiverWidth + 2 and pos.y < mapHeight - mapBorder - RiverWidth - 2 and
       not inCornerReserve(pos.x, pos.y, mapWidth, mapHeight, mapBorder, reserve):
      forkCandidates.add(pos)
  if forkCandidates.len > 0:
    let upIdx = forkCandidates.len div 3
    let downIdx = max(upIdx + 1, (forkCandidates.len * 2) div 3)
    forkUp = forkCandidates[upIdx]
    forkDown = forkCandidates[min(downIdx, forkCandidates.len - 1)]
  elif riverPath.len > 0:
    let upIdx = riverPath.len div 3
    let downIdx = max(upIdx + 1, (riverPath.len * 2) div 3)
    forkUp = riverPath[upIdx]
    forkDown = riverPath[min(downIdx, riverPath.len - 1)]
  if riverPath.len > 0:
    forkUpIdx = riverPath.find(forkUp)
    forkDownIdx = riverPath.find(forkDown)
    branchUpPath = buildBranch(forkUp, -1, r)
    branchDownPath = buildBranch(forkDown, 1, r)

  # Place water tiles for main river (skip reserved corners)
  for pos in riverPath:
    for dx in -RiverWidth div 2 .. RiverWidth div 2:
      for dy in -RiverWidth div 2 .. RiverWidth div 2:
        let waterPos = pos + ivec2(dx.int32, dy.int32)
        if waterPos.x >= 0 and waterPos.x < mapWidth and
           waterPos.y >= 0 and waterPos.y < mapHeight:
          if not inCornerReserve(waterPos.x, waterPos.y, mapWidth, mapHeight, mapBorder, reserve):
            terrain[waterPos.x][waterPos.y] = Water

  # Place water tiles for tributary branches (skip reserved corners)
  for pos in branchUpPath:
    for dx in -(RiverWidth div 2 - 1) .. (RiverWidth div 2 - 1):
      for dy in -(RiverWidth div 2 - 1) .. (RiverWidth div 2 - 1):
        let waterPos = pos + ivec2(dx.int32, dy.int32)
        if waterPos.x >= 0 and waterPos.x < mapWidth and
           waterPos.y >= 0 and waterPos.y < mapHeight:
          if not inCornerReserve(waterPos.x, waterPos.y, mapWidth, mapHeight, mapBorder, reserve):
            terrain[waterPos.x][waterPos.y] = Water
  for pos in branchDownPath:
    for dx in -(RiverWidth div 2 - 1) .. (RiverWidth div 2 - 1):
      for dy in -(RiverWidth div 2 - 1) .. (RiverWidth div 2 - 1):
        let waterPos = pos + ivec2(dx.int32, dy.int32)
        if waterPos.x >= 0 and waterPos.x < mapWidth and
           waterPos.y >= 0 and waterPos.y < mapHeight:
          if not inCornerReserve(waterPos.x, waterPos.y, mapWidth, mapHeight, mapBorder, reserve):
            terrain[waterPos.x][waterPos.y] = Water

  # Place bridges across the river and any tributary branch.
  # Bridges are three tiles wide (east-west) and span across the river north-south.
  proc placeBridgeMain(t: var TerrainGrid, center: IVec2) =
    let startY = max(mapBorder, int(center.y) - (RiverWidth div 2 + 1))
    let endY = min(mapHeight - mapBorder - 1, int(center.y) + (RiverWidth div 2 + 1))
    let baseX = max(mapBorder, min(mapWidth - mapBorder - 3, int(center.x) - 1))
    for dx in 0 .. 2:
      for y in startY .. endY:
        let x = baseX + dx
        if inCornerReserve(x, y, mapWidth, mapHeight, mapBorder, reserve):
          continue
        if t[x][y] == Water:
          t[x][y] = Bridge

  # Branch bridges run horizontally (east-west span) across the tributary.
  proc placeBridgeBranch(t: var TerrainGrid, center: IVec2) =
    let startX = max(mapBorder, int(center.x) - (RiverWidth div 2 + 1))
    let endX = min(mapWidth - mapBorder - 1, int(center.x) + (RiverWidth div 2 + 1))
    let baseY = max(mapBorder, min(mapHeight - mapBorder - 3, int(center.y) - 1))
    for dy in 0 .. 2:
      for x in startX .. endX:
        let y = baseY + dy
        if inCornerReserve(x, y, mapWidth, mapHeight, mapBorder, reserve):
          continue
        if t[x][y] == Water:
          t[x][y] = Bridge

  var mainCandidates: seq[IVec2] = @[]
  for pos in riverPath:
    if pos.x > mapBorder + RiverWidth and pos.x < mapWidth - mapBorder - RiverWidth and
       pos.y > mapBorder + RiverWidth and pos.y < mapHeight - mapBorder - RiverWidth and
       not inCornerReserve(pos.x, pos.y, mapWidth, mapHeight, mapBorder, reserve):
      mainCandidates.add(pos)

  var branchUpCandidates: seq[IVec2] = @[]
  for pos in branchUpPath:
    if pos.x > mapBorder + RiverWidth and pos.x < mapWidth - mapBorder - RiverWidth and
       pos.y > mapBorder + RiverWidth and pos.y < mapHeight - mapBorder - RiverWidth and
       not inCornerReserve(pos.x, pos.y, mapWidth, mapHeight, mapBorder, reserve):
      branchUpCandidates.add(pos)

  var branchDownCandidates: seq[IVec2] = @[]
  for pos in branchDownPath:
    if pos.x > mapBorder + RiverWidth and pos.x < mapWidth - mapBorder - RiverWidth and
       pos.y > mapBorder + RiverWidth and pos.y < mapHeight - mapBorder - RiverWidth and
       not inCornerReserve(pos.x, pos.y, mapWidth, mapHeight, mapBorder, reserve):
      branchDownCandidates.add(pos)

  let hasBranch = branchUpPath.len > 0 or branchDownPath.len > 0
  let desiredBridges = max(randInclusive(r, 4, 5), (if hasBranch: 3 else: 0)) * 2

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
    if forkUpIdx >= 0:
      let upstream = if forkUpIdx > 0: mainCandidates[0 ..< min(forkUpIdx, mainCandidates.len)] else: @[]
      placeFrom(upstream, false)
    if branchUpCandidates.len > 0:
      placeFrom(branchUpCandidates, true)
    if branchDownCandidates.len > 0:
      placeFrom(branchDownCandidates, true)
    if forkDownIdx >= 0 and forkDownIdx < mainCandidates.len:
      let downstream = mainCandidates[min(forkDownIdx, mainCandidates.len - 1) ..< mainCandidates.len]
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

  if remaining > 0 and branchUpCandidates.len > 0:
    let stride = max(1, branchUpCandidates.len div (remaining + 1))
    var idx = stride
    while remaining > 0 and idx < branchUpCandidates.len:
      let center = branchUpCandidates[idx]
      uniqueAdd(center, placed)
      placeBridgeBranch(terrain, center)
      dec remaining
      idx += stride

  if remaining > 0 and branchDownCandidates.len > 0:
    let stride = max(1, branchDownCandidates.len div (remaining + 1))
    var idx = stride
    while remaining > 0 and idx < branchDownCandidates.len:
      let center = branchDownCandidates[idx]
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
        let radius = (groveSize.float / 2.0).int
        for dx in -radius .. radius:
          for dy in -radius .. radius:
            let gx = x + dx
            let gy = y + dy
            if gx < mapBorder or gx >= mapWidth - mapBorder or gy < mapBorder or gy >= mapHeight - mapBorder:
              continue
            let dist = sqrt((dx * dx + dy * dy).float)
            if dist <= radius.float:
              let chance = 0.85 - (dist / radius.float) * 0.4
              if randChance(r, chance) and terrain[gx][gy] != Water and terrain[gx][gy] in {Empty, Sand, Grass, Fertile, Dune}:
                terrain[gx][gy] = Palm

        let oasisW = randInclusive(r, 3, 5)
        let oasisH = randInclusive(r, 3, 5)
        let rx = max(1, oasisW div 2)
        let ry = max(1, oasisH div 2)
        for ox in -(rx + 1) .. (rx + 1):
          for oy in -(ry + 1) .. (ry + 1):
            let px = x + ox
            let py = y + oy
            if px < mapBorder or px >= mapWidth - mapBorder or py < mapBorder or py >= mapHeight - mapBorder:
              continue
            let dx = ox.float / rx.float
            let dy = oy.float / ry.float
            let dist = dx * dx + dy * dy
            let noise = (randFloat(r) - 0.5) * 0.35
            if dist <= 1.0 + noise:
              terrain[px][py] = Water

        let rivulets = randInclusive(r, 1, 2)
        for _ in 0 ..< rivulets:
          var pos = ivec2(x.int32, y.int32)
          let steps = randInclusive(r, 4, 10)
          for _ in 0 ..< steps:
            let dir = sample(r, [ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1),
                                 ivec2(1, 1), ivec2(-1, 1), ivec2(1, -1), ivec2(-1, -1)])
            pos += dir
            if pos.x < mapBorder.int32 or pos.x >= (mapWidth - mapBorder).int32 or
               pos.y < mapBorder.int32 or pos.y >= (mapHeight - mapBorder).int32:
              break
            terrain[pos.x][pos.y] = Water

        for ox in -(rx + 2) .. (rx + 2):
          for oy in -(ry + 2) .. (ry + 2):
            let px = x + ox
            let py = y + oy
            if px < mapBorder or px >= mapWidth - mapBorder or py < mapBorder or py >= mapHeight - mapBorder:
              continue
            if terrain[px][py] == Water:
              continue
            var nearWater = false
            for dx in -1 .. 1:
              for dy in -1 .. 1:
                let nx = px + dx
                let ny = py + dy
                if nx < mapBorder or nx >= mapWidth - mapBorder or ny < mapBorder or ny >= mapHeight - mapBorder:
                  continue
                if terrain[nx][ny] == Water:
                  nearWater = true
                  break
              if nearWater:
                break
            if nearWater and randChance(r, 0.7) and terrain[px][py] in {Empty, Sand, Grass, Fertile, Dune}:
              terrain[px][py] = Palm
        placed = true
        break
    if not placed:
      let x = randInclusive(r, mapBorder + 3, mapWidth - mapBorder - 3)
      let y = randInclusive(r, mapBorder + 3, mapHeight - mapBorder - 3)
      let groveSize = randInclusive(r, 3, 8)
      let radius = (groveSize.float / 2.0).int
      for dx in -radius .. radius:
        for dy in -radius .. radius:
          let gx = x + dx
          let gy = y + dy
          if gx < mapBorder or gx >= mapWidth - mapBorder or gy < mapBorder or gy >= mapHeight - mapBorder:
            continue
          let dist = sqrt((dx * dx + dy * dy).float)
          if dist <= radius.float:
            let chance = 0.85 - (dist / radius.float) * 0.4
            if randChance(r, chance) and terrain[gx][gy] != Water and terrain[gx][gy] in {Empty, Sand, Grass, Fertile, Dune}:
              terrain[gx][gy] = Palm

      let oasisW = randInclusive(r, 3, 5)
      let oasisH = randInclusive(r, 3, 5)
      let rx = max(1, oasisW div 2)
      let ry = max(1, oasisH div 2)
      for ox in -(rx + 1) .. (rx + 1):
        for oy in -(ry + 1) .. (ry + 1):
          let px = x + ox
          let py = y + oy
          if px < mapBorder or px >= mapWidth - mapBorder or py < mapBorder or py >= mapHeight - mapBorder:
            continue
          let dx = ox.float / rx.float
          let dy = oy.float / ry.float
          let dist = dx * dx + dy * dy
          let noise = (randFloat(r) - 0.5) * 0.35
          if dist <= 1.0 + noise:
            terrain[px][py] = Water

      let rivulets = randInclusive(r, 1, 2)
      for _ in 0 ..< rivulets:
        var pos = ivec2(x.int32, y.int32)
        let steps = randInclusive(r, 4, 10)
        for _ in 0 ..< steps:
          let dir = sample(r, [ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1),
                               ivec2(1, 1), ivec2(-1, 1), ivec2(1, -1), ivec2(-1, -1)])
          pos += dir
          if pos.x < mapBorder.int32 or pos.x >= (mapWidth - mapBorder).int32 or
             pos.y < mapBorder.int32 or pos.y >= (mapHeight - mapBorder).int32:
            break
          terrain[pos.x][pos.y] = Water

      for ox in -(rx + 2) .. (rx + 2):
        for oy in -(ry + 2) .. (ry + 2):
          let px = x + ox
          let py = y + oy
          if px < mapBorder or px >= mapWidth - mapBorder or py < mapBorder or py >= mapHeight - mapBorder:
            continue
          if terrain[px][py] == Water:
            continue
          var nearWater = false
          for dx in -1 .. 1:
            for dy in -1 .. 1:
              let nx = px + dx
              let ny = py + dy
              if nx < mapBorder or nx >= mapWidth - mapBorder or ny < mapBorder or ny >= mapHeight - mapBorder:
                continue
              if terrain[nx][ny] == Water:
                nearWater = true
                break
            if nearWater:
              break
          if nearWater and randChance(r, 0.7) and terrain[px][py] in {Empty, Sand, Grass, Fertile, Dune}:
            terrain[px][py] = Palm

proc generateRockOutcrops*(terrain: var TerrainGrid, mapWidth, mapHeight, mapBorder: int, r: var Rand) =
  let clusters = max(16, mapWidth div 25)
  for i in 0 ..< clusters:
    let x = randInclusive(r, mapBorder + 4, mapWidth - mapBorder - 4)
    let y = randInclusive(r, mapBorder + 4, mapHeight - mapBorder - 4)
    let size = randInclusive(r, 4, 8)
    terrain.createTerrainCluster(x, y, size, mapWidth, mapHeight, Rock, 0.9, 0.3, r)

proc generateGoldVeins*(terrain: var TerrainGrid, mapWidth, mapHeight, mapBorder: int, r: var Rand) =
  let clusters = max(8, mapWidth div 50)
  for i in 0 ..< clusters:
    let x = randInclusive(r, mapBorder + 6, mapWidth - mapBorder - 6)
    let y = randInclusive(r, mapBorder + 6, mapHeight - mapBorder - 6)
    let size = randInclusive(r, 3, 5)
    terrain.createTerrainCluster(x, y, size, mapWidth, mapHeight, Gold, 0.8, 0.4, r)

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
  let baseBiomeType = baseBiomeType()
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
  terrain.generateGoldVeins(mapWidth, mapHeight, mapBorder, r)
  terrain.generateBushes(mapWidth, mapHeight, mapBorder, r)
  terrain.generateAnimals(mapWidth, mapHeight, mapBorder, r)

proc getStructureElements*(structure: Structure, topLeft: IVec2): tuple[
    walls: seq[IVec2],
    doors: seq[IVec2],
    floors: seq[IVec2],
    altars: seq[IVec2],
    blacksmiths: seq[IVec2],
    armories: seq[IVec2],
    clayOvens: seq[IVec2],
    weavingLooms: seq[IVec2],
    center: IVec2
  ] =
  ## Extract tiles for placing a structure
  result = (
    walls: @[],
    doors: @[],
    floors: @[],
    altars: @[],
    blacksmiths: @[],
    armories: @[],
    clayOvens: @[],
    weavingLooms: @[],
    center: topLeft + structure.centerPos
  )

  for y, row in structure.layout:
    for x, cell in row:
      let pos = ivec2(topLeft.x + x.int32, topLeft.y + y.int32)
      case cell
      of StructureWallChar: result.walls.add(pos)
      of StructureDoorChar: result.doors.add(pos)
      of StructureFloorChar: result.floors.add(pos)
      of StructureAltarChar: result.altars.add(pos)
      of StructureBlacksmithChar: result.blacksmiths.add(pos)
      of StructureArmoryChar: result.armories.add(pos)
      of StructureClayOvenChar: result.clayOvens.add(pos)
      of StructureWeavingLoomChar: result.weavingLooms.add(pos)
      else: discard

proc terrainAsciiChar*(terrain: TerrainType): char =
  ## ASCII schema for terrain tiles (typeable characters).
  case terrain:
  of Empty: ' '
  of Water: '~'
  of Bridge: '='
  of Wheat: '"'
  of Tree: 'Y'
  of Fertile: ':'
  of Road: '+'
  of Rock: 'R'
  of Gold: 'G'
  of Bush: '%'
  of Animal: '&'
  of Grass: ','
  of Cactus: '!'
  of Dune: '^'
  of Stalagmite: 'I'
  of Palm: 'P'
  of Sand: '.'
  of Snow: '_'
