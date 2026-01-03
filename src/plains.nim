import entropy
import ./biome

type
  BiomePlainsConfig* = object
    clusterPeriod*: int = 7
    clusterMinRadius*: int = 0
    clusterMaxRadius*: int = 2
    clusterFill*: float = 0.7
    clusterProb*: float = 0.8
    jitter*: int = 2

const
  Directions = [
    (dx: 1, dy: 0),
    (dx: -1, dy: 0),
    (dx: 0, dy: 1),
    (dx: 0, dy: -1)
  ]

proc buildBiomePlainsMask*(mask: var MaskGrid, mapWidth, mapHeight, mapBorder: int,
                           r: var Rand, cfg: BiomePlainsConfig) =
  mask.clearMask(mapWidth, mapHeight)

  let period = max(3, cfg.clusterPeriod)
  let minRadius = max(0, cfg.clusterMinRadius)
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

      let radius = if maxRadius > 0: randIntInclusive(r, minRadius, maxRadius) else: 0
      if radius == 0:
        mask[cx][cy] = true
        continue

      let fill = fillBase * (0.6 + 0.4 * randFloat(r))
      let branchCount = randIntInclusive(r, 2, 4)
      let maxSteps = max(3, radius * 3)
      let maxDist2 = (radius + 1) * (radius + 1)

      var xs = newSeq[int](branchCount)
      var ys = newSeq[int](branchCount)
      var dirIdx = newSeq[int](branchCount)
      for i in 0 ..< branchCount:
        xs[i] = cx
        ys[i] = cy
        dirIdx[i] = randIntExclusive(r, 0, Directions.len)

      for step in 0 ..< maxSteps:
        for i in 0 ..< branchCount:
          let x = xs[i]
          let y = ys[i]
          if x >= mapBorder and x < mapWidth - mapBorder and
             y >= mapBorder and y < mapHeight - mapBorder:
            if randFloat(r) <= fill:
              mask[x][y] = true

          if randFloat(r) < 0.35:
            dirIdx[i] = randIntExclusive(r, 0, Directions.len)

          var dx = Directions[dirIdx[i]].dx
          var dy = Directions[dirIdx[i]].dy
          var nx = x + dx
          var ny = y + dy
          let dist2 = (nx - cx) * (nx - cx) + (ny - cy) * (ny - cy)
          if dist2 > maxDist2:
            dirIdx[i] = randIntExclusive(r, 0, Directions.len)
            dx = Directions[dirIdx[i]].dx
            dy = Directions[dirIdx[i]].dy
            nx = x + dx
            ny = y + dy
          xs[i] = nx
          ys[i] = ny

        if step > 1:
          for i in 0 ..< branchCount:
            if randFloat(r) < 0.12:
              let spurDir = randIntExclusive(r, 0, Directions.len)
              let sdx = Directions[spurDir].dx
              let sdy = Directions[spurDir].dy
              let sx = xs[i] + sdx
              let sy = ys[i] + sdy
              let dist2 = (sx - cx) * (sx - cx) + (sy - cy) * (sy - cy)
              if dist2 <= maxDist2:
                if sx >= mapBorder and sx < mapWidth - mapBorder and
                   sy >= mapBorder and sy < mapHeight - mapBorder:
                  if randFloat(r) <= fill:
                    mask[sx][sy] = true
                let sx2 = sx + sdx
                let sy2 = sy + sdy
                let dist2b = (sx2 - cx) * (sx2 - cx) + (sy2 - cy) * (sy2 - cy)
                if dist2b <= maxDist2:
                  if sx2 >= mapBorder and sx2 < mapWidth - mapBorder and
                     sy2 >= mapBorder and sy2 < mapHeight - mapBorder:
                    if randFloat(r) <= fill:
                      mask[sx2][sy2] = true
