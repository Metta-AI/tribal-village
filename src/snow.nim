import std/math
import entropy
import ./biome

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
