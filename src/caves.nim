import entropy
import ./biome

type
  BiomeCavesConfig* = object
    fillProb*: float = 0.4
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

  let steps = max(0, cfg.steps)
  for _ in 0 ..< steps:
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
