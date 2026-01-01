import std/math
import rng_compat
import ./biome_common

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
