import entropy
import ./biome

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

  let passes = max(0, cfg.clumpiness)
  for _ in 0 ..< passes:
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
