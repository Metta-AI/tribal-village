import std/math
import entropy
import biome

type
  BiomeForestConfig* = object
    clumpiness*: int = 2
    seedProb*: float = 0.03
    growthProb*: float = 0.5
    neighborThreshold*: int = 3
    ditherEdges*: bool = true
    ditherProb*: float = 0.15
    ditherDepth*: int = 5

proc buildBiomeForestMask*(mask: var MaskGrid, mapWidth, mapHeight, mapBorder: int,
                           r: var Rand, cfg: BiomeForestConfig) =
  mask.clearMask(mapWidth, mapHeight)

  for x in mapBorder ..< mapWidth - mapBorder:
    for y in mapBorder ..< mapHeight - mapBorder:
      if randFloat(r) < cfg.seedProb:
        mask[x][y] = true

  for _ in 0 ..< max(0, cfg.clumpiness):
    var nextMask: MaskGrid
    for x in mapBorder ..< mapWidth - mapBorder:
      for y in mapBorder ..< mapHeight - mapBorder:
        var neighbors = 0
        for dx in -1 .. 1:
          for dy in -1 .. 1:
            if dx == 0 and dy == 0:
              continue
            let nx = x + dx
            let ny = y + dy
            if nx >= 0 and nx < mapWidth and ny >= 0 and ny < mapHeight:
              if mask[nx][ny]:
                inc neighbors
        let grow = neighbors >= cfg.neighborThreshold and randFloat(r) < cfg.growthProb
        nextMask[x][y] = grow or mask[x][y]
    mask = nextMask

  if cfg.ditherEdges:
    ditherEdges(mask, mapWidth, mapHeight, cfg.ditherProb, cfg.ditherDepth, r)

type
  BiomeDesertConfig* = object
    dunePeriod*: int = 8
    ridgeWidth*: int = 1
    angle*: float = PI / 4
    noiseProb*: float = 0.1
    ditherEdges*: bool = true
    ditherProb*: float = 0.15
    ditherDepth*: int = 5

proc buildBiomeDesertMask*(mask: var MaskGrid, mapWidth, mapHeight, mapBorder: int,
                           r: var Rand, cfg: BiomeDesertConfig) =
  mask.clearMask(mapWidth, mapHeight)

  let period = max(2, cfg.dunePeriod)
  let width = max(1, cfg.ridgeWidth)
  let theta = cfg.angle
  let cosT = cos(theta)
  let sinT = sin(theta)

  for x in mapBorder ..< mapWidth - mapBorder:
    for y in mapBorder ..< mapHeight - mapBorder:
      let xr = x.float * cosT + y.float * sinT
      var modv = xr - floor(xr / period.float) * period.float
      if modv < width.float:
        mask[x][y] = true
      if mask[x][y] and randFloat(r) < cfg.noiseProb:
        mask[x][y] = false

  if cfg.ditherEdges:
    ditherEdges(mask, mapWidth, mapHeight, cfg.ditherProb, cfg.ditherDepth, r)

type
  BiomeCavesConfig* = object
    fillProb*: float = 0.25
    steps*: int = 3
    birthLimit*: int = 5
    deathLimit*: int = 3
    ditherEdges*: bool = true
    ditherProb*: float = 0.15
    ditherDepth*: int = 5

proc buildBiomeCavesMask*(mask: var MaskGrid, mapWidth, mapHeight, mapBorder: int,
                          r: var Rand, cfg: BiomeCavesConfig) =
  mask.clearMask(mapWidth, mapHeight)

  for x in mapBorder ..< mapWidth - mapBorder:
    for y in mapBorder ..< mapHeight - mapBorder:
      mask[x][y] = randFloat(r) < cfg.fillProb

  for _ in 0 ..< max(0, cfg.steps):
    var nextMask: MaskGrid
    for x in mapBorder ..< mapWidth - mapBorder:
      for y in mapBorder ..< mapHeight - mapBorder:
        var neighbors = 0
        for dx in -1 .. 1:
          for dy in -1 .. 1:
            if dx == 0 and dy == 0:
              continue
            let nx = x + dx
            let ny = y + dy
            if nx < mapBorder or nx >= mapWidth - mapBorder or
               ny < mapBorder or ny >= mapHeight - mapBorder:
              inc neighbors
            elif mask[nx][ny]:
              inc neighbors
        let birth = neighbors > cfg.birthLimit
        let death = neighbors < cfg.deathLimit
        nextMask[x][y] = birth or ((not death) and mask[x][y])
    mask = nextMask

  if cfg.ditherEdges:
    ditherEdges(mask, mapWidth, mapHeight, cfg.ditherProb, cfg.ditherDepth, r)

type
  BiomeCityConfig* = object
    pitch*: int = 10
    roadWidth*: int = 3
    placeProb*: float = 0.9
    minBlockFrac*: float = 0.5
    jitter*: int = 1
    ditherEdges*: bool = true
    ditherProb*: float = 0.15
    ditherDepth*: int = 5

proc buildBiomeCityMasks*(blockMask: var MaskGrid, roadMask: var MaskGrid,
                          mapWidth, mapHeight, mapBorder: int,
                          r: var Rand, cfg: BiomeCityConfig) =
  blockMask.clearMask(mapWidth, mapHeight)
  roadMask.clearMask(mapWidth, mapHeight)

  let pitch = max(4, cfg.pitch)
  let roadW = max(1, cfg.roadWidth)
  let minBlock = max(1, int(float(pitch) * cfg.minBlockFrac))
  let jitter = max(0, cfg.jitter)

  for gy in countup(mapBorder, mapHeight - mapBorder - 1, pitch):
    for gx in countup(mapBorder, mapWidth - mapBorder - 1, pitch):
      if randFloat(r) > cfg.placeProb:
        continue
      let x0 = gx + roadW
      let y0 = gy + roadW
      var bw = minBlock
      var bh = minBlock
      if jitter > 0:
        bw += randIntInclusive(r, -jitter, jitter)
        bh += randIntInclusive(r, -jitter, jitter)
      bw = min(bw, pitch - 2 * roadW)
      bh = min(bh, pitch - 2 * roadW)
      if bw <= 0 or bh <= 0:
        continue
      let cx0 = max(mapBorder, x0)
      let cy0 = max(mapBorder, y0)
      let cx1 = min(mapWidth - mapBorder, x0 + bw)
      let cy1 = min(mapHeight - mapBorder, y0 + bh)
      if cx1 <= cx0 or cy1 <= cy0:
        continue
      for x in cx0 ..< cx1:
        for y in cy0 ..< cy1:
          blockMask[x][y] = true

  if cfg.ditherEdges:
    ditherEdges(blockMask, mapWidth, mapHeight, cfg.ditherProb, cfg.ditherDepth, r)

  for gy in countup(mapBorder, mapHeight - mapBorder - 1, pitch):
    let y1 = min(mapHeight - mapBorder, gy + roadW)
    for y in gy ..< y1:
      for x in mapBorder ..< mapWidth - mapBorder:
        if not blockMask[x][y]:
          roadMask[x][y] = true

  for gx in countup(mapBorder, mapWidth - mapBorder - 1, pitch):
    let x1 = min(mapWidth - mapBorder, gx + roadW)
    for x in gx ..< x1:
      for y in mapBorder ..< mapHeight - mapBorder:
        if not blockMask[x][y]:
          roadMask[x][y] = true

type
  BiomeSnowConfig* = object
    clusterPeriod*: int = 12
    clusterMinRadius*: int = 2
    clusterMaxRadius*: int = 5
    clusterFill*: float = 0.85
    clusterProb*: float = 0.75
    jitter*: int = 2
    ditherEdges*: bool = true
    ditherProb*: float = 0.12
    ditherDepth*: int = 3

proc buildBiomeSnowMask*(mask: var MaskGrid, mapWidth, mapHeight, mapBorder: int,
                         r: var Rand, cfg: BiomeSnowConfig) =
  mask.clearMask(mapWidth, mapHeight)

  let period = max(4, cfg.clusterPeriod)
  let minRadius = max(1, cfg.clusterMinRadius)
  let maxRadius = max(minRadius, cfg.clusterMaxRadius)
  let jitter = max(0, cfg.jitter)
  let fillBase = cfg.clusterFill

  for ay in countup(mapBorder, mapHeight - mapBorder - 1, period):
    for ax in countup(mapBorder, mapWidth - mapBorder - 1, period):
      if randFloat(r) > cfg.clusterProb:
        continue
      var cx = ax
      var cy = ay
      if jitter > 0:
        cx += randIntInclusive(r, -jitter, jitter)
        cy += randIntInclusive(r, -jitter, jitter)
      if cx < mapBorder or cx >= mapWidth - mapBorder or
         cy < mapBorder or cy >= mapHeight - mapBorder:
        continue

      let radius = randIntInclusive(r, minRadius, maxRadius)
      let fill = fillBase * (0.7 + 0.3 * randFloat(r))
      for dx in -radius .. radius:
        for dy in -radius .. radius:
          let x = cx + dx
          let y = cy + dy
          if x < mapBorder or x >= mapWidth - mapBorder or
             y < mapBorder or y >= mapHeight - mapBorder:
            continue
          let dist2 = dx * dx + dy * dy
          if dist2 > radius * radius:
            continue
          let dist = sqrt(dist2.float)
          let falloff = 1.0 - min(1.0, dist / radius.float)
          let chance = fill * (0.6 + 0.4 * falloff)
          if randFloat(r) < chance:
            mask[x][y] = true

  if cfg.ditherEdges:
    ditherEdges(mask, mapWidth, mapHeight, cfg.ditherProb, cfg.ditherDepth, r)
