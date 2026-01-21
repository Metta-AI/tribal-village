import std/math, vmath
import entropy
import biome

const
  # Keep in sync with biome.nim's MaxBiomeSize.
  MaxTerrainSize* = 512

type
  TerrainType* = enum
    Empty
    Water
    Bridge
    Fertile
    Road
    Grass
    Dune
    Sand
    Snow
    RampUpN
    RampUpS
    RampUpW
    RampUpE
    RampDownN
    RampDownS
    RampDownW
    RampDownE

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
    BiomeSwamp

  BiomeType* = enum
    BiomeNone
    BiomeBaseType
    BiomeForestType
    BiomeDesertType
    BiomeCavesType
    BiomeCityType
    BiomePlainsType
    BiomeSnowType
    BiomeSwampType
    BiomeDungeonType

  BiomeGrid* = array[MaxTerrainSize, array[MaxTerrainSize, BiomeType]]

  DungeonKind* = enum
    DungeonMaze
    DungeonRadial

const
  UseBiomeTerrain* = true
  BaseBiome* = BiomeBase
  BiomeForestTerrain* = Grass
  BiomeDesertTerrain* = Sand
  BiomeCavesTerrain* = Dune
  BiomePlainsTerrain* = Grass
  BiomeSnowTerrain* = Snow
  BiomeSwampTerrain* = Grass
  BiomeCityBlockTerrain* = Grass
  BiomeCityRoadTerrain* = Road
  UseBiomeZones* = true
  UseDungeonZones* = true
  UseSequentialBiomeZones* = true
  UseSequentialDungeonZones* = true
  UseLegacyTreeClusters* = true
  UseTreeOases* = true
  WheatFieldClusterCountMin* = 98
  WheatFieldClusterCountMax* = 140
  WheatFieldSizeMin* = 3
  WheatFieldSizeMax* = 6
  TreeGroveClusterCountMin* = 98
  TreeGroveClusterCountMax* = 140
  TreeOasisClusterCountMin* = 18
  TreeOasisClusterCountMax* = 30
  TreeOasisWaterRadiusMin* = 1
  TreeOasisWaterRadiusMax* = 2
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
  DungeonTerrainWall* = Dune
  DungeonTerrainPath* = Road

const
  TerrainEmpty* = TerrainType.Empty
  TerrainWater* = TerrainType.Water
  TerrainBridge* = TerrainType.Bridge
  TerrainFertile* = TerrainType.Fertile
  TerrainRoad* = TerrainType.Road
  TerrainGrass* = TerrainType.Grass
  TerrainDune* = TerrainType.Dune
  TerrainSand* = TerrainType.Sand
  TerrainSnow* = TerrainType.Snow
  BuildableTerrain* = {Empty, Grass, Sand, Snow, Dune, Road}

template isBlockedTerrain*(terrain: TerrainType): bool =
  terrain == Water

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
  let blendT = min(1.0, dist.float / depth.float)
  edgeChance + (1.0 - edgeChance) * blendT

proc canApplyBiome(currentBiome, biomeType, baseBiomeType: BiomeType): bool =
  currentBiome == BiomeNone or currentBiome == baseBiomeType or currentBiome == biomeType

proc splitCliffRing(mask: MaskGrid, mapWidth, mapHeight: int,
                    ringMask, innerMask: var MaskGrid) =
  ringMask.clearMask(mapWidth, mapHeight)
  innerMask.clearMask(mapWidth, mapHeight)
  for x in 0 ..< mapWidth:
    for y in 0 ..< mapHeight:
      if not mask[x][y]:
        continue
      var boundary = false
      if y == 0 or not mask[x][y - 1]:
        boundary = true
      elif x == mapWidth - 1 or not mask[x + 1][y]:
        boundary = true
      elif y == mapHeight - 1 or not mask[x][y + 1]:
        boundary = true
      elif x == 0 or not mask[x - 1][y]:
        boundary = true
      if boundary:
        ringMask[x][y] = true
      else:
        innerMask[x][y] = true

proc baseBiomeType*(): BiomeType =
  case BaseBiome:
  of BiomeBase: BiomeBaseType
  of BiomeForest: BiomeForestType
  of BiomeDesert: BiomeDesertType
  of BiomeCaves: BiomeCavesType
  of BiomeCity: BiomeCityType
  of BiomePlains: BiomePlainsType
  of BiomeSnow: BiomeSnowType
  of BiomeSwamp: BiomeSwampType

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

proc applyBiomeZoneFill(terrain: var TerrainGrid, biomes: var BiomeGrid, zoneMask: MaskGrid,
                        zone: ZoneRect, mapWidth, mapHeight, mapBorder: int,
                        terrainType: TerrainType, biomeType: BiomeType,
                        baseBiomeType: BiomeType) =
  let (x0, y0, x1, y1) = zoneBounds(zone, mapWidth, mapHeight, mapBorder)
  if x1 <= x0 or y1 <= y0:
    return
  for x in x0 ..< x1:
    for y in y0 ..< y1:
      if not zoneMask[x][y]:
        continue
      if not canApplyBiome(biomes[x][y], biomeType, baseBiomeType):
        continue
      terrain[x][y] = terrainType
      biomes[x][y] = biomeType

proc applyBiomeZoneInsetFill(terrain: var TerrainGrid, biomes: var BiomeGrid, zoneMask: MaskGrid,
                             zone: ZoneRect, mapWidth, mapHeight, mapBorder: int,
                             biomeTerrain: TerrainType,
                             biomeType, baseBiomeType: BiomeType) =
  var ringMask: MaskGrid
  var innerMask: MaskGrid
  splitCliffRing(zoneMask, mapWidth, mapHeight, ringMask, innerMask)
  var hasInner = false
  for x in 0 ..< mapWidth:
    for y in 0 ..< mapHeight:
      if innerMask[x][y]:
        hasInner = true
        break
    if hasInner:
      break
  if not hasInner:
    let (x0, y0, x1, y1) = zoneBounds(zone, mapWidth, mapHeight, mapBorder)
    if x1 > x0 and y1 > y0:
      let cx = (x0 + x1 - 1) div 2
      let cy = (y0 + y1 - 1) div 2
      if zoneMask[cx][cy]:
        innerMask[cx][cy] = true
      else:
        for x in x0 ..< x1:
          for y in y0 ..< y1:
            if zoneMask[x][y]:
              innerMask[x][y] = true
              hasInner = true
              break
          if hasInner:
            break
  applyBiomeZoneFill(terrain, biomes, innerMask, zone, mapWidth, mapHeight, mapBorder,
    biomeTerrain, biomeType, baseBiomeType)

type
  MaskBuilder[T] = proc(mask: var MaskGrid, mapWidth, mapHeight, mapBorder: int,
                        r: var Rand, cfg: T) {.nimcall.}

proc applyBiomeZoneMask[T](terrain: var TerrainGrid, biomes: var BiomeGrid,
                           zoneMask: MaskGrid, zone: ZoneRect, mapWidth, mapHeight, mapBorder: int,
                           r: var Rand, edgeChance: float,
                           builder: MaskBuilder[T], cfg: T,
                           terrainType: TerrainType, biomeType: BiomeType,
                           baseBiomeType: BiomeType) =
  var mask: MaskGrid
  builder(mask, mapWidth, mapHeight, mapBorder, r, cfg)
  applyBiomeMaskToZone(terrain, biomes, mask, zoneMask, zone, mapWidth, mapHeight, mapBorder,
    terrainType, biomeType, baseBiomeType, r, edgeChance)

proc applyBaseBiomeMask[T](terrain: var TerrainGrid, mapWidth, mapHeight, mapBorder: int,
                           r: var Rand, builder: MaskBuilder[T], cfg: T,
                           terrainType: TerrainType) =
  var mask: MaskGrid
  builder(mask, mapWidth, mapHeight, mapBorder, r, cfg)
  applyMaskToTerrain(terrain, mask, mapWidth, mapHeight, mapBorder, terrainType)

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
  let lobeCount = randIntInclusive(r, ZoneBlobLobesMin, ZoneBlobLobesMax)
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
  let biteCount = randIntInclusive(r, ZoneBlobBiteCountMin, ZoneBlobBiteCountMax)
  for _ in 0 ..< biteCount:
    var bx = randIntInclusive(r, x0, x1 - 1)
    var by = randIntInclusive(r, y0, y1 - 1)
    var attempts = 0
    while attempts < 10 and not mask[bx][by]:
      bx = randIntInclusive(r, x0, x1 - 1)
      by = randIntInclusive(r, y0, y1 - 1)
      inc attempts
    if not mask[bx][by]:
      continue
    let biteMin = max(2, int(baseRadius.float * ZoneBlobBiteScaleMin))
    let biteMax = max(biteMin, int(baseRadius.float * ZoneBlobBiteScaleMax))
    let biteRadius = randIntInclusive(r, biteMin, biteMax)
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

proc applySwampWater*(terrain: var TerrainGrid, biomes: var BiomeGrid,
                      mapWidth, mapHeight, mapBorder: int,
                      r: var Rand, cfg: BiomeSwampConfig) =
  var swampTiles: seq[IVec2] = @[]
  for x in mapBorder ..< mapWidth - mapBorder:
    for y in mapBorder ..< mapHeight - mapBorder:
      if biomes[x][y] != BiomeSwampType:
        continue
      swampTiles.add(ivec2(x.int32, y.int32))
      if randChance(r, cfg.waterScatterProb):
        terrain[x][y] = Water

  if swampTiles.len == 0:
    return

  let tilesPerPond = max(1, cfg.pondTilesPerPond)
  let desired = max(cfg.pondCountMin, swampTiles.len div tilesPerPond)
  let pondCount = min(cfg.pondCountMax, desired)

  for _ in 0 ..< pondCount:
    let center = swampTiles[randIntExclusive(r, 0, swampTiles.len)]
    let radius = randIntInclusive(r, cfg.pondRadiusMin, cfg.pondRadiusMax)
    let radius2 = radius * radius
    let inner2 = max(0, (radius - 1) * (radius - 1))
    for dx in -radius .. radius:
      for dy in -radius .. radius:
        let wx = center.x + dx
        let wy = center.y + dy
        if wx < mapBorder or wx >= mapWidth - mapBorder or
           wy < mapBorder or wy >= mapHeight - mapBorder:
          continue
        if biomes[wx][wy] != BiomeSwampType:
          continue
        let dist2 = dx * dx + dy * dy
        if dist2 > radius2:
          continue
        if dist2 > inner2 and randChance(r, cfg.pondEdgeDitherProb):
          continue
        terrain[wx][wy] = Water

proc applyBiomeZones(terrain: var TerrainGrid, biomes: var BiomeGrid, mapWidth, mapHeight, mapBorder: int,
                     r: var Rand) =
  var count = zoneCount(mapWidth * mapHeight, BiomeZoneDivisor, BiomeZoneMinCount, BiomeZoneMaxCount)
  let kinds = [BiomeForest, BiomeDesert, BiomeCaves, BiomeCity, BiomePlains, BiomeSnow, BiomeSwamp]
  let weights = [1.0, 1.0, 0.6, 0.6, 1.0, 0.8, 0.7]
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
      var total = 0.0
      for w in weights:
        total += max(0.0, w)
      if total <= 0.0:
        kinds[0]
      else:
        let roll = randFloat(r) * total
        var accum = 0.0
        var selected = kinds[^1]
        for i, w in weights:
          accum += max(0.0, w)
          if roll <= accum:
            selected = kinds[i]
            break
        selected
    var zoneMask: MaskGrid
    buildZoneBlobMask(zoneMask, mapWidth, mapHeight, mapBorder, zone, r)
    case biome:
    of BiomeBase:
      discard
    of BiomeForest:
      applyBiomeZoneMask(terrain, biomes, zoneMask, zone, mapWidth, mapHeight, mapBorder,
        r, edgeChance, buildBiomeForestMask, BiomeForestConfig(),
        BiomeForestTerrain, BiomeForestType, baseBiomeType)
    of BiomeDesert:
      # Blend sand into the zone so edges ease into the base biome, then layer dunes.
      applyTerrainBlendToZone(terrain, biomes, zoneMask, zone, mapWidth, mapHeight, mapBorder,
        TerrainSand, BiomeDesertType, baseBiomeType, r, edgeChance, density = 0.3)
      applyBiomeZoneMask(terrain, biomes, zoneMask, zone, mapWidth, mapHeight, mapBorder,
        r, edgeChance, buildBiomeDesertMask, BiomeDesertConfig(),
        TerrainDune, BiomeDesertType, baseBiomeType)
    of BiomeCaves:
      applyBiomeZoneMask(terrain, biomes, zoneMask, zone, mapWidth, mapHeight, mapBorder,
        r, edgeChance, buildBiomeCavesMask, BiomeCavesConfig(),
        BiomeCavesTerrain, BiomeCavesType, baseBiomeType)
    of BiomeSnow:
      applyBiomeZoneInsetFill(terrain, biomes, zoneMask, zone, mapWidth, mapHeight, mapBorder,
        BiomeSnowTerrain, BiomeSnowType, baseBiomeType)
    of BiomeSwamp:
      applyBiomeZoneInsetFill(terrain, biomes, zoneMask, zone, mapWidth, mapHeight, mapBorder,
        BiomeSwampTerrain, BiomeSwampType, baseBiomeType)
    of BiomeCity:
      var mask: MaskGrid
      var roadMask: MaskGrid
      buildBiomeCityMasks(mask, roadMask, mapWidth, mapHeight, mapBorder, r, BiomeCityConfig())
      applyBiomeMaskToZone(terrain, biomes, mask, zoneMask, zone, mapWidth, mapHeight, mapBorder,
        BiomeCityBlockTerrain, BiomeCityType, baseBiomeType, r, edgeChance)
      applyBiomeMaskToZone(terrain, biomes, roadMask, zoneMask, zone, mapWidth, mapHeight, mapBorder,
        BiomeCityRoadTerrain, BiomeCityType, baseBiomeType, r, edgeChance)
    of BiomePlains:
      applyBiomeZoneMask(terrain, biomes, zoneMask, zone, mapWidth, mapHeight, mapBorder,
        r, edgeChance, buildBiomePlainsMask, BiomePlainsConfig(),
        BiomePlainsTerrain, BiomePlainsType, baseBiomeType)

proc applyBaseBiome(terrain: var TerrainGrid, mapWidth, mapHeight, mapBorder: int, r: var Rand) =
  case BaseBiome:
  of BiomeBase:
    discard
  of BiomeForest:
    applyBaseBiomeMask(terrain, mapWidth, mapHeight, mapBorder, r,
      buildBiomeForestMask, BiomeForestConfig(), BiomeForestTerrain)
  of BiomeDesert:
    applyBaseBiomeMask(terrain, mapWidth, mapHeight, mapBorder, r,
      buildBiomeDesertMask, BiomeDesertConfig(), BiomeDesertTerrain)
  of BiomeCaves:
    applyBaseBiomeMask(terrain, mapWidth, mapHeight, mapBorder, r,
      buildBiomeCavesMask, BiomeCavesConfig(), BiomeCavesTerrain)
  of BiomeCity:
    var mask: MaskGrid
    var roadMask: MaskGrid
    buildBiomeCityMasks(mask, roadMask, mapWidth, mapHeight, mapBorder, r, BiomeCityConfig())
    applyMaskToTerrain(terrain, mask, mapWidth, mapHeight, mapBorder, BiomeCityBlockTerrain)
    applyMaskToTerrain(terrain, roadMask, mapWidth, mapHeight, mapBorder, BiomeCityRoadTerrain)
  of BiomePlains:
    applyBaseBiomeMask(terrain, mapWidth, mapHeight, mapBorder, r,
      buildBiomePlainsMask, BiomePlainsConfig(), BiomePlainsTerrain)
  of BiomeSnow:
    applyBaseBiomeMask(terrain, mapWidth, mapHeight, mapBorder, r,
      buildBiomeSnowMask, BiomeSnowConfig(), BiomeSnowTerrain)
  of BiomeSwamp:
    applyBaseBiomeMask(terrain, mapWidth, mapHeight, mapBorder, r,
      buildBiomeSwampMask, BiomeSwampConfig(), BiomeSwampTerrain)

proc generateRiver*(terrain: var TerrainGrid, mapWidth, mapHeight, mapBorder: int, r: var Rand) =
  var riverPath: seq[IVec2] = @[]
  var riverYByX: seq[int] = newSeq[int](mapWidth)
  for x in 0 ..< mapWidth:
    riverYByX[x] = -1

  # Reserve corners for villages so river doesn't block them
  let reserve = max(8, min(mapWidth, mapHeight) div 10)
  let left = mapBorder
  let right = mapWidth - mapBorder
  let top = mapBorder
  let bottom = mapHeight - mapBorder
  template inCorner(x, y: int): bool =
    ((x >= left and x < left + reserve) and (y >= top and y < top + reserve)) or
    ((x >= right - reserve and x < right) and (y >= top and y < top + reserve)) or
    ((x >= left and x < left + reserve) and (y >= bottom - reserve and y < bottom)) or
    ((x >= right - reserve and x < right) and (y >= bottom - reserve and y < bottom))

  # Start near left edge and centered vertically (avoid corner reserves)
  let centerY = mapHeight div 2
  let span = max(6, mapHeight div 6)
  var startMin = max(mapBorder + RiverWidth + reserve, centerY - span)
  var startMax = min(mapHeight - mapBorder - RiverWidth - reserve, centerY + span)
  if startMin > startMax: swap(startMin, startMax)
  let yMin = max(mapBorder + RiverWidth + reserve, mapBorder + 2)
  let yMax = min(mapHeight - mapBorder - RiverWidth - reserve, mapHeight - mapBorder - 2)
  var currentPos = ivec2(mapBorder.int32, randIntInclusive(r, startMin, startMax).int32)
  var targetY = randIntInclusive(r, yMin, yMax)
  var yVel = 0

  while currentPos.x >= mapBorder and currentPos.x < mapWidth - mapBorder and
        currentPos.y >= mapBorder and currentPos.y < mapHeight - mapBorder:
    riverPath.add(currentPos)

    currentPos.x += 1  # Always move right
    if randChance(r, 0.02):
      targetY = randIntInclusive(r, yMin, yMax)
    let dyBias = if targetY < currentPos.y.int: -1 elif targetY > currentPos.y.int: 1 else: 0
    if randChance(r, 0.12):
      yVel += dyBias
    elif randChance(r, 0.03):
      yVel += sample(r, [-1, 1])
    yVel = max(-1, min(1, yVel))
    if yVel != 0 or randChance(r, 0.08):
      currentPos.y += yVel.int32
    if currentPos.y < yMin.int32:
      currentPos.y = yMin.int32
      yVel = 1
    elif currentPos.y > yMax.int32:
      currentPos.y = yMax.int32
      yVel = -1

  var branchUpPath: seq[IVec2] = @[]
  var branchDownPath: seq[IVec2] = @[]
  var forkUp: IVec2
  var forkDown: IVec2
  var forkUpIdx = -1
  var forkDownIdx = -1
  var forkCandidates: seq[IVec2] = @[]
  for pos in riverPath:
    if pos.y > mapBorder + RiverWidth + 2 and pos.y < mapHeight - mapBorder - RiverWidth - 2 and
       not inCorner(pos.x, pos.y):
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
    block buildUp:
      let dirY = -1
      var path: seq[IVec2] = @[]
      var secondaryPos = forkUp
      var lastValid = forkUp
      var hasValid = false
      let maxSteps = max(mapWidth * 2, mapHeight * 2)
      var steps = 0
      var yBranchVel = dirY
      while secondaryPos.y > mapBorder + RiverWidth and secondaryPos.y < mapHeight - mapBorder - RiverWidth and steps < maxSteps:
        secondaryPos.x += 1
        if randChance(r, 0.08):
          yBranchVel += sample(r, [-1, 1])
        yBranchVel = max(-1, min(1, yBranchVel))
        if yBranchVel == 0:
          yBranchVel = dirY
        secondaryPos.y += yBranchVel.int32
        if randChance(r, 0.04):
          secondaryPos.y += sample(r, [-1, 0, 1]).int32
        if secondaryPos.x >= mapBorder and secondaryPos.x < mapWidth - mapBorder and
           secondaryPos.y >= mapBorder and secondaryPos.y < mapHeight - mapBorder:
          if not inCorner(secondaryPos.x, secondaryPos.y):
            path.add(secondaryPos)
            lastValid = secondaryPos
            hasValid = true
        else:
          break
        inc steps
      # Ensure the branch touches the edge vertically with a short vertical run
      var tip = (if hasValid: lastValid else: forkUp)
      let safeMinX = left + reserve
      let safeMaxX = right - reserve - 1
      var edgeX = tip.x.int
      if safeMinX <= safeMaxX:
        if edgeX < safeMinX:
          edgeX = safeMinX
        elif edgeX > safeMaxX:
          edgeX = safeMaxX
      else:
        edgeX = max(mapBorder, min(mapWidth - mapBorder - 1, edgeX))
      if edgeX != tip.x.int:
        let stepX = (if edgeX > tip.x.int: 1 else: -1)
        var x = tip.x.int
        while x != edgeX:
          x += stepX
          let drift = ivec2(x.int32, tip.y)
          if drift.x >= mapBorder and drift.x < mapWidth - mapBorder and
             drift.y >= mapBorder and drift.y < mapHeight - mapBorder:
            if not inCorner(drift.x, drift.y):
              path.add(drift)
              lastValid = drift
              hasValid = true
        tip = (if hasValid: lastValid else: tip)
      var pushSteps = 0
      let maxPush = mapHeight
      while tip.y > mapBorder and pushSteps < maxPush:
        dec tip.y
        if tip.x >= mapBorder and tip.x < mapWidth and tip.y >= mapBorder and tip.y < mapHeight:
          if not inCorner(tip.x, tip.y):
            path.add(tip)
        inc pushSteps
      branchUpPath = path

    block buildDown:
      let dirY = 1
      var path: seq[IVec2] = @[]
      var secondaryPos = forkDown
      var lastValid = forkDown
      var hasValid = false
      let maxSteps = max(mapWidth * 2, mapHeight * 2)
      var steps = 0
      var yBranchVel = dirY
      while secondaryPos.y > mapBorder + RiverWidth and secondaryPos.y < mapHeight - mapBorder - RiverWidth and steps < maxSteps:
        secondaryPos.x += 1
        if randChance(r, 0.08):
          yBranchVel += sample(r, [-1, 1])
        yBranchVel = max(-1, min(1, yBranchVel))
        if yBranchVel == 0:
          yBranchVel = dirY
        secondaryPos.y += yBranchVel.int32
        if randChance(r, 0.04):
          secondaryPos.y += sample(r, [-1, 0, 1]).int32
        if secondaryPos.x >= mapBorder and secondaryPos.x < mapWidth - mapBorder and
           secondaryPos.y >= mapBorder and secondaryPos.y < mapHeight - mapBorder:
          if not inCorner(secondaryPos.x, secondaryPos.y):
            path.add(secondaryPos)
            lastValid = secondaryPos
            hasValid = true
        else:
          break
        inc steps
      # Ensure the branch touches the edge vertically with a short vertical run
      var tip = (if hasValid: lastValid else: forkDown)
      let safeMinX = left + reserve
      let safeMaxX = right - reserve - 1
      var edgeX = tip.x.int
      if safeMinX <= safeMaxX:
        if edgeX < safeMinX:
          edgeX = safeMinX
        elif edgeX > safeMaxX:
          edgeX = safeMaxX
      else:
        edgeX = max(mapBorder, min(mapWidth - mapBorder - 1, edgeX))
      if edgeX != tip.x.int:
        let stepX = (if edgeX > tip.x.int: 1 else: -1)
        var x = tip.x.int
        while x != edgeX:
          x += stepX
          let drift = ivec2(x.int32, tip.y)
          if drift.x >= mapBorder and drift.x < mapWidth - mapBorder and
             drift.y >= mapBorder and drift.y < mapHeight - mapBorder:
            if not inCorner(drift.x, drift.y):
              path.add(drift)
              lastValid = drift
              hasValid = true
        tip = (if hasValid: lastValid else: tip)
      var pushSteps = 0
      let maxPush = mapHeight
      while tip.y < mapHeight - mapBorder and pushSteps < maxPush:
        inc tip.y
        if tip.x >= mapBorder and tip.x < mapWidth and tip.y >= mapBorder and tip.y < mapHeight:
          if not inCorner(tip.x, tip.y):
            path.add(tip)
        inc pushSteps
      branchDownPath = path

  # Place water tiles for main river (skip reserved corners)
  for pos in riverPath:
    if pos.x >= 0 and pos.x < mapWidth:
      riverYByX[pos.x] = pos.y.int
    for dx in -RiverWidth div 2 .. RiverWidth div 2:
      for dy in -RiverWidth div 2 .. RiverWidth div 2:
        let waterPos = pos + ivec2(dx.int32, dy.int32)
        if waterPos.x >= 0 and waterPos.x < mapWidth and
           waterPos.y >= 0 and waterPos.y < mapHeight:
          if not inCorner(waterPos.x, waterPos.y):
            terrain[waterPos.x][waterPos.y] = Water

  # Place water tiles for tributary branches (skip reserved corners)
  for pos in branchUpPath:
    for dx in -(RiverWidth div 2 - 1) .. (RiverWidth div 2 - 1):
      for dy in -(RiverWidth div 2 - 1) .. (RiverWidth div 2 - 1):
        let waterPos = pos + ivec2(dx.int32, dy.int32)
        if waterPos.x >= 0 and waterPos.x < mapWidth and
           waterPos.y >= 0 and waterPos.y < mapHeight:
          if not inCorner(waterPos.x, waterPos.y):
            terrain[waterPos.x][waterPos.y] = Water
  for pos in branchDownPath:
    for dx in -(RiverWidth div 2 - 1) .. (RiverWidth div 2 - 1):
      for dy in -(RiverWidth div 2 - 1) .. (RiverWidth div 2 - 1):
        let waterPos = pos + ivec2(dx.int32, dy.int32)
        if waterPos.x >= 0 and waterPos.x < mapWidth and
           waterPos.y >= 0 and waterPos.y < mapHeight:
          if not inCorner(waterPos.x, waterPos.y):
            terrain[waterPos.x][waterPos.y] = Water

  # Place bridges across the river and any tributary branch.
  # Bridges are three tiles wide and span across the river, with a slight overhang
  # and a diagonal stair-step option for prettier diagonal crossings.
  proc slopeSignForMain(center: IVec2): int =
    let x = center.x.int
    let y = center.y.int
    if x + 1 < riverYByX.len and riverYByX[x + 1] >= 0:
      let dy = riverYByX[x + 1] - y
      if dy != 0:
        return (if dy > 0: 1 else: -1)
    if x - 1 >= 0 and riverYByX[x - 1] >= 0:
      let dy = y - riverYByX[x - 1]
      if dy != 0:
        return (if dy > 0: 1 else: -1)
    0

  proc slopeSignForPath(path: seq[IVec2], center: IVec2): int =
    let idx = path.find(center)
    if idx < 0:
      return 0
    if idx + 1 < path.len:
      let dy = (path[idx + 1].y - center.y).int
      if dy != 0:
        return (if dy > 0: 1 else: -1)
    if idx > 0:
      let dy = (center.y - path[idx - 1].y).int
      if dy != 0:
        return (if dy > 0: 1 else: -1)
    0

  proc placeBridgeSpan(t: var TerrainGrid, center, dir, width: IVec2) =
    let bridgeOverhang = 1
    let scanLimit = RiverWidth * 2 + 6
    let cx = center.x.int
    let cy = center.y.int
    let dx = dir.x.int
    let dy = dir.y.int
    let wx = width.x.int
    let wy = width.y.int

    template setBridgeTile(x, y: int) =
      if x >= mapBorder and x < mapWidth - mapBorder and
         y >= mapBorder and y < mapHeight - mapBorder:
        if not inCorner(x, y):
          t[x][y] = Bridge

    proc hasWaterAt(grid: var TerrainGrid, step: int): bool =
      for w in -1 .. 1:
        let x = cx + dx * step + wx * w
        let y = cy + dy * step + wy * w
        if x < mapBorder or x >= mapWidth - mapBorder or
           y < mapBorder or y >= mapHeight - mapBorder:
          continue
        if inCorner(x, y):
          continue
        if grid[x][y] in {Water, Bridge}:
          return true
      false

    if not hasWaterAt(t, 0):
      return
    var startStep = 0
    var endStep = 0
    while startStep > -scanLimit and hasWaterAt(t, startStep - 1):
      dec startStep
    while endStep < scanLimit and hasWaterAt(t, endStep + 1):
      inc endStep
    startStep -= bridgeOverhang
    endStep += bridgeOverhang

    if abs(dx) + abs(dy) == 2:
      let spanSteps = endStep - startStep
      for w in -1 .. 1:
        var x = cx + dx * startStep + wx * w
        var y = cy + dy * startStep + wy * w
        setBridgeTile(x, y)
        for _ in 0 ..< spanSteps:
          x += dx
          setBridgeTile(x, y)
          y += dy
          setBridgeTile(x, y)
    else:
      for step in startStep .. endStep:
        for w in -1 .. 1:
          let x = cx + dx * step + wx * w
          let y = cy + dy * step + wy * w
          setBridgeTile(x, y)

  proc placeBridgeMain(t: var TerrainGrid, center: IVec2) =
    let slopeSign = slopeSignForMain(center)
    if slopeSign != 0:
      placeBridgeSpan(t, center, ivec2(1'i32, (-slopeSign).int32), ivec2(1'i32, slopeSign.int32))
    else:
      placeBridgeSpan(t, center, ivec2(0, 1), ivec2(1, 0))

  # Branch bridges run horizontally (east-west span) across the tributary.
  proc placeBridgeBranch(t: var TerrainGrid, center: IVec2) =
    var slopeSign = slopeSignForPath(branchUpPath, center)
    if slopeSign == 0:
      slopeSign = slopeSignForPath(branchDownPath, center)
    if slopeSign != 0:
      placeBridgeSpan(t, center, ivec2(1'i32, (-slopeSign).int32), ivec2(1'i32, slopeSign.int32))
    else:
      placeBridgeSpan(t, center, ivec2(1, 0), ivec2(0, 1))

  var mainCandidates: seq[IVec2] = @[]
  for pos in riverPath:
    if pos.x > mapBorder + RiverWidth and pos.x < mapWidth - mapBorder - RiverWidth and
       pos.y > mapBorder + RiverWidth and pos.y < mapHeight - mapBorder - RiverWidth and
       not inCorner(pos.x, pos.y):
      mainCandidates.add(pos)

  var branchUpCandidates: seq[IVec2] = @[]
  for pos in branchUpPath:
    if pos.x > mapBorder + RiverWidth and pos.x < mapWidth - mapBorder - RiverWidth and
       pos.y > mapBorder + RiverWidth and pos.y < mapHeight - mapBorder - RiverWidth and
       not inCorner(pos.x, pos.y):
      branchUpCandidates.add(pos)

  var branchDownCandidates: seq[IVec2] = @[]
  for pos in branchDownPath:
    if pos.x > mapBorder + RiverWidth and pos.x < mapWidth - mapBorder - RiverWidth and
       pos.y > mapBorder + RiverWidth and pos.y < mapHeight - mapBorder - RiverWidth and
       not inCorner(pos.x, pos.y):
      branchDownCandidates.add(pos)

  let hasBranch = branchUpPath.len > 0 or branchDownPath.len > 0
  let desiredBridges = max(randIntInclusive(r, 4, 5), (if hasBranch: 3 else: 0)) * 2

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
      let firstIdx = branchUpCandidates.len div 3
      let secondIdx = max(firstIdx + 1, (branchUpCandidates.len * 2) div 3)
      placeBridgeBranch(terrain, branchUpCandidates[firstIdx])
      placed.add(branchUpCandidates[firstIdx])
      if secondIdx < branchUpCandidates.len:
        placeBridgeBranch(terrain, branchUpCandidates[secondIdx])
        placed.add(branchUpCandidates[secondIdx])
    if branchDownCandidates.len > 0:
      let firstIdx = branchDownCandidates.len div 3
      let secondIdx = max(firstIdx + 1, (branchDownCandidates.len * 2) div 3)
      placeBridgeBranch(terrain, branchDownCandidates[firstIdx])
      placed.add(branchDownCandidates[firstIdx])
      if secondIdx < branchDownCandidates.len:
        placeBridgeBranch(terrain, branchDownCandidates[secondIdx])
        placed.add(branchDownCandidates[secondIdx])
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
    var candidateIdx = stride
    while remaining > 0 and candidateIdx < mainCandidates.len:
      let center = mainCandidates[candidateIdx]
      uniqueAdd(center, placed)
      placeBridgeMain(terrain, center)
      dec remaining
      candidateIdx += stride

  if remaining > 0 and branchUpCandidates.len > 0:
    let stride = max(1, branchUpCandidates.len div (remaining + 1))
    var candidateIdx = stride
    while remaining > 0 and candidateIdx < branchUpCandidates.len:
      let center = branchUpCandidates[candidateIdx]
      uniqueAdd(center, placed)
      placeBridgeBranch(terrain, center)
      dec remaining
      candidateIdx += stride

  if remaining > 0 and branchDownCandidates.len > 0:
    let stride = max(1, branchDownCandidates.len div (remaining + 1))
    var candidateIdx = stride
    while remaining > 0 and candidateIdx < branchDownCandidates.len:
      let center = branchDownCandidates[candidateIdx]
      uniqueAdd(center, placed)
      placeBridgeBranch(terrain, center)
      dec remaining
      candidateIdx += stride

  # Add a meandering road grid that criss-crosses the map.
  let dirs = [ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1)]

  template carveRoadPath(startPos, goalPos: IVec2, side: int) =
    var current = startPos
    var prevDir = ivec2(0, 0)
    var segmentDir = ivec2(0, 0)
    var segmentStepsLeft = 0
    var diagToggle = false
    let maxSteps = mapWidth * mapHeight
    var steps = 0
    var stagnation = 0
    var lastDist = abs(goalPos.x - current.x).int + abs(goalPos.y - current.y).int
    if terrain[current.x][current.y] notin {Water, Bridge}:
      terrain[current.x][current.y] = Road
    while current != goalPos and steps < maxSteps:
      if segmentStepsLeft <= 0 or stagnation > 10 or steps > (maxSteps div 2):
        let dxGoal = goalPos.x - current.x
        let dyGoal = goalPos.y - current.y
        let baseDir = block:
          let sx = (if dxGoal < 0: -1'i32 elif dxGoal > 0: 1'i32 else: 0'i32)
          let sy = (if dyGoal < 0: -1'i32 elif dyGoal > 0: 1'i32 else: 0'i32)
          if abs(dxGoal) >= abs(dyGoal):
            ivec2(sx, 0)
          else:
            ivec2(0, sy)
        if baseDir.x == 0 and baseDir.y == 0:
          break
        let orthoA = ivec2(baseDir.y, baseDir.x)
        let orthoB = ivec2(-baseDir.y, -baseDir.x)
        let diagA = ivec2(baseDir.x + orthoA.x, baseDir.y + orthoA.y)
        let diagB = ivec2(baseDir.x + orthoB.x, baseDir.y + orthoB.y)
        let roll = randFloat(r)
        if roll < 0.6:
          segmentDir = if randChance(r, 0.5): diagA else: diagB
        elif roll < 0.9:
          segmentDir = baseDir
        else:
          segmentDir = if randChance(r, 0.5): orthoA else: orthoB
        segmentStepsLeft = randIntInclusive(r, 5, 10)
        diagToggle = randChance(r, 0.5)

      let stepDir = if segmentDir.x != 0 and segmentDir.y != 0:
        let dir = if diagToggle: ivec2(segmentDir.x, 0) else: ivec2(0, segmentDir.y)
        diagToggle = not diagToggle
        dir
      else:
        segmentDir
      let nextPos = current + stepDir
      var moved = false
      if nextPos.x >= mapBorder and nextPos.x < mapWidth - mapBorder and
         nextPos.y >= mapBorder and nextPos.y < mapHeight - mapBorder and
         not inCorner(nextPos.x, nextPos.y) and terrain[nextPos.x][nextPos.y] != Water and
         not (side < 0 and nextPos.y >= riverMid) and
         not (side > 0 and nextPos.y <= riverMid):
        prevDir = stepDir
        current = nextPos
        dec segmentStepsLeft
        moved = true
      else:
        segmentStepsLeft = 0
        var bestScore = int.high
        var best: seq[IVec2] = @[]
        for d in dirs:
          let nx = current.x + d.x
          let ny = current.y + d.y
          if nx < mapBorder or nx >= mapWidth - mapBorder or
             ny < mapBorder or ny >= mapHeight - mapBorder:
            continue
          if inCorner(nx, ny):
            continue
          let terrainHere = terrain[nx][ny]
          if terrainHere == Water:
            continue
          if side < 0 and ny >= riverMid:
            continue
          if side > 0 and ny <= riverMid:
            continue
          var score = abs(goalPos.x - nx).int + abs(goalPos.y - ny).int
          if terrainHere == Bridge:
            score -= 2
          elif terrainHere == Road:
            score -= 1
          score += randIntInclusive(r, 0, 2)
          if score < bestScore:
            bestScore = score
            best.setLen(0)
            best.add(ivec2(nx, ny))
          elif score == bestScore:
            best.add(ivec2(nx, ny))
        if best.len == 0:
          break
        let fallback = best[randIntExclusive(r, 0, best.len)]
        prevDir = fallback - current
        current = fallback
        moved = true

      if moved:
        if terrain[current.x][current.y] notin {Water, Bridge}:
          terrain[current.x][current.y] = Road
        let newDist = abs(goalPos.x - current.x).int + abs(goalPos.y - current.y).int
        if newDist >= lastDist:
          inc stagnation
        else:
          stagnation = 0
        lastDist = newDist
        inc steps

  let verticalCount = randIntInclusive(r, 4, 5)
  let playWidth = mapWidth - 2 * mapBorder
  let vStride = max(1, playWidth div (verticalCount + 1))
  var vIdx = vStride
  var roadXs: seq[int] = @[]
  while roadXs.len < verticalCount and vIdx < mapWidth - mapBorder:
    let jitter = max(1, vStride div 4)
    var x = vIdx + randIntInclusive(r, -jitter, jitter)
    x = max(mapBorder + 2, min(mapWidth - mapBorder - 3, x))
    if x notin roadXs:
      roadXs.add(x)
    vIdx += vStride

  var riverMid = mapHeight div 2
  if riverPath.len > 0:
    var sumY = 0
    for pos in riverPath:
      sumY += pos.y.int
    riverMid = sumY div riverPath.len

  for x in roadXs:
    let start = ivec2(x.int32, (mapBorder + 1).int32)
    let goal = ivec2(x.int32, (mapHeight - mapBorder - 2).int32)
    if x >= 0 and x < riverYByX.len and riverYByX[x] >= 0:
      let bridgeCenter = ivec2(x.int32, riverYByX[x].int32)
      placeBridgeMain(terrain, bridgeCenter)
      carveRoadPath(start, bridgeCenter, 0)
      carveRoadPath(bridgeCenter, goal, 0)
    else:
      carveRoadPath(start, goal, 0)

  let northCount = randIntInclusive(r, 1, 2)
  let southCount = randIntInclusive(r, 1, 2)
  let northMin = mapBorder + 2
  let northMax = min(mapHeight - mapBorder - 3, riverMid - (RiverWidth div 2) - 3)
  if northMax >= northMin:
    let nStride = max(1, (northMax - northMin) div (northCount + 1))
    var y = northMin + nStride
    for _ in 0 ..< northCount:
      let start = ivec2((mapBorder + 1).int32, y.int32)
      let goal = ivec2((mapWidth - mapBorder - 2).int32, y.int32)
      carveRoadPath(start, goal, -1)
      y += nStride

  let southMin = max(mapBorder + 2, riverMid + (RiverWidth div 2) + 3)
  let southMax = mapHeight - mapBorder - 3
  if southMax >= southMin:
    let sStride = max(1, (southMax - southMin) div (southCount + 1))
    var y = southMin + sStride
    for _ in 0 ..< southCount:
      let start = ivec2((mapBorder + 1).int32, y.int32)
      let goal = ivec2((mapWidth - mapBorder - 2).int32, y.int32)
      carveRoadPath(start, goal, 1)
      y += sStride

proc initTerrain*(terrain: var TerrainGrid, biomes: var BiomeGrid,
                  mapWidth, mapHeight, mapBorder: int, seed: int = 2024) =
  ## Initialize base terrain and biomes (no water features).
  var rng = initRand(seed)

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
    applyBaseBiome(terrain, mapWidth, mapHeight, mapBorder, rng)
  if UseBiomeZones:
    applyBiomeZones(terrain, biomes, mapWidth, mapHeight, mapBorder, rng)

proc getStructureElements*(structure: Structure, topLeft: IVec2): tuple[
    walls: seq[IVec2],
    doors: seq[IVec2],
    floors: seq[IVec2],
    altars: seq[IVec2],
    blacksmiths: seq[IVec2],
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
      of StructureClayOvenChar: result.clayOvens.add(pos)
      of StructureWeavingLoomChar: result.weavingLooms.add(pos)
      else: discard
