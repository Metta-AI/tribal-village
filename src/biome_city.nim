import rng_compat
import ./biome_common

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
