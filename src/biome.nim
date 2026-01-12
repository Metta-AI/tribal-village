import std/math
import entropy

const
  # Keep in sync with terrain.nim's MaxTerrainSize.
  MaxBiomeSize* = 512

type
  MaskGrid* = array[MaxBiomeSize, array[MaxBiomeSize, bool]]

proc clearMask*(mask: var MaskGrid, mapWidth, mapHeight: int, value = false) =
  for x in 0 ..< mapWidth:
    for y in 0 ..< mapHeight:
      mask[x][y] = value

proc expandMask(mask: MaskGrid, mapWidth, mapHeight: int): MaskGrid =
  var outMask: MaskGrid
  for x in 0 ..< mapWidth:
    for y in 0 ..< mapHeight:
      if not mask[x][y]:
        continue
      for dx in -1 .. 1:
        for dy in -1 .. 1:
          if dx == 0 and dy == 0:
            continue
          let nx = x + dx
          let ny = y + dy
          if nx >= 0 and nx < mapWidth and ny >= 0 and ny < mapHeight:
            outMask[nx][ny] = true
  outMask

proc ditherEdges*(mask: var MaskGrid, mapWidth, mapHeight: int, prob: float, depth: int, r: var Rand) =
  if depth <= 0 or prob <= 0.0:
    return

  var wall: MaskGrid
  var empty: MaskGrid
  for x in 0 ..< mapWidth:
    for y in 0 ..< mapHeight:
      wall[x][y] = mask[x][y]
      empty[x][y] = not mask[x][y]

  let wallExpand = expandMask(wall, mapWidth, mapHeight)
  let emptyExpand = expandMask(empty, mapWidth, mapHeight)

  var boundary: MaskGrid
  for x in 0 ..< mapWidth:
    for y in 0 ..< mapHeight:
      boundary[x][y] = (wallExpand[x][y] and empty[x][y]) or (emptyExpand[x][y] and wall[x][y])

  var dist: array[MaxBiomeSize, array[MaxBiomeSize, int]]
  var seen: MaskGrid
  var frontier: MaskGrid

  for x in 0 ..< mapWidth:
    for y in 0 ..< mapHeight:
      if boundary[x][y]:
        dist[x][y] = 0
        seen[x][y] = true
        frontier[x][y] = true
      else:
        dist[x][y] = -1

  var currentDepth = 0
  while currentDepth < depth:
    inc currentDepth
    let expanded = expandMask(frontier, mapWidth, mapHeight)
    var nextFrontier: MaskGrid
    var any = false
    for x in 0 ..< mapWidth:
      for y in 0 ..< mapHeight:
        if expanded[x][y] and not seen[x][y]:
          nextFrontier[x][y] = true
          seen[x][y] = true
          dist[x][y] = currentDepth
          any = true
    if not any:
      break
    frontier = nextFrontier

  for x in 0 ..< mapWidth:
    for y in 0 ..< mapHeight:
      let d = dist[x][y]
      if d < 0 or d > depth:
        continue
      if x < depth or y < depth or x >= mapWidth - depth or y >= mapHeight - depth:
        continue
      let effective = if d < 1: 1 else: d
      let edgeProb = prob * (float(depth - effective + 1) / float(depth))
      if randFloat(r) < edgeProb:
        mask[x][y] = not mask[x][y]

type
  DungeonMazeConfig* = object
    wallKeepProb*: float = 0.65

  DungeonRadialConfig* = object
    arms*: int = 8
    armWidth*: int = 1
    ring*: bool = true

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

proc buildDungeonMazeMask*(mask: var MaskGrid, mapWidth, mapHeight: int,
                           zoneX, zoneY, zoneW, zoneH: int,
                           r: var Rand, cfg: DungeonMazeConfig) =
  for x in zoneX ..< zoneX + zoneW:
    for y in zoneY ..< zoneY + zoneH:
      if x >= 0 and x < mapWidth and y >= 0 and y < mapHeight:
        mask[x][y] = false

  var w = zoneW
  var h = zoneH
  if w < 3 or h < 3:
    return
  if w mod 2 == 0:
    dec w
  if h mod 2 == 0:
    dec h
  let cellW = (w - 1) div 2
  let cellH = (h - 1) div 2
  if cellW <= 0 or cellH <= 0:
    return

  var walls = newSeq[seq[bool]](w)
  for x in 0 ..< w:
    walls[x] = newSeq[bool](h)
    for y in 0 ..< h:
      walls[x][y] = true

  var visited = newSeq[seq[bool]](cellW)
  for x in 0 ..< cellW:
    visited[x] = newSeq[bool](cellH)

  var stack: seq[(int, int)] = @[]
  let startX = randIntExclusive(r, 0, cellW)
  let startY = randIntExclusive(r, 0, cellH)
  stack.add((startX, startY))
  visited[startX][startY] = true
  walls[1 + startX * 2][1 + startY * 2] = false

  const dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]

  while stack.len > 0:
    let (cx, cy) = stack[^1]
    var candidates: seq[(int, int)] = @[]
    for (dx, dy) in dirs:
      let nx = cx + dx
      let ny = cy + dy
      if nx >= 0 and nx < cellW and ny >= 0 and ny < cellH:
        if not visited[nx][ny]:
          candidates.add((nx, ny))
    if candidates.len == 0:
      discard stack.pop()
      continue

    let pick = candidates[randIntExclusive(r, 0, candidates.len)]
    let nx = pick[0]
    let ny = pick[1]
    visited[nx][ny] = true

    let x1 = 1 + cx * 2
    let y1 = 1 + cy * 2
    let x2 = 1 + nx * 2
    let y2 = 1 + ny * 2
    walls[x2][y2] = false
    walls[x1 + (x2 - x1) div 2][y1 + (y2 - y1) div 2] = false

    stack.add((nx, ny))

  for x in 0 ..< w:
    for y in 0 ..< h:
      if not walls[x][y]:
        continue
      let gx = zoneX + x
      let gy = zoneY + y
      if gx < 0 or gx >= mapWidth or gy < 0 or gy >= mapHeight:
        continue
      if randFloat(r) <= cfg.wallKeepProb:
        mask[gx][gy] = true

proc buildDungeonRadialMask*(mask: var MaskGrid, mapWidth, mapHeight: int,
                             zoneX, zoneY, zoneW, zoneH: int,
                             r: var Rand, cfg: DungeonRadialConfig) =
  for x in zoneX ..< zoneX + zoneW:
    for y in zoneY ..< zoneY + zoneH:
      if x >= 0 and x < mapWidth and y >= 0 and y < mapHeight:
        mask[x][y] = false

  if zoneW < 3 or zoneH < 3:
    return

  let cx = zoneX + zoneW div 2
  let cy = zoneY + zoneH div 2
  let radius = min(zoneW, zoneH) div 2
  let arms = max(1, cfg.arms)
  let armWidth = max(1, cfg.armWidth)

  for i in 0 ..< arms:
    let angle = 2.0 * PI * float(i) / float(arms)
    let dx = cos(angle)
    let dy = sin(angle)
    for step in 0 .. radius:
      let fx = cx + int(round(dx * float(step)))
      let fy = cy + int(round(dy * float(step)))
      for ox in -armWidth .. armWidth:
        for oy in -armWidth .. armWidth:
          let gx = fx + ox
          let gy = fy + oy
          if gx < zoneX or gx >= zoneX + zoneW or gy < zoneY or gy >= zoneY + zoneH:
            continue
          if gx >= 0 and gx < mapWidth and gy >= 0 and gy < mapHeight:
            mask[gx][gy] = true

  if cfg.ring:
    let ringRadius = max(2, radius div 2)
    let steps = max(16, ringRadius * 6)
    for i in 0 ..< steps:
      let angle = 2.0 * PI * float(i) / float(steps)
      let fx = cx + int(round(cos(angle) * float(ringRadius)))
      let fy = cy + int(round(sin(angle) * float(ringRadius)))
      for ox in -armWidth .. armWidth:
        for oy in -armWidth .. armWidth:
          let gx = fx + ox
          let gy = fy + oy
          if gx < zoneX or gx >= zoneX + zoneW or gy < zoneY or gy >= zoneY + zoneH:
            continue
          if gx >= 0 and gx < mapWidth and gy >= 0 and gy < mapHeight:
            mask[gx][gy] = true

  # Soften edges with a tiny bit of noise.
  for x in zoneX ..< zoneX + zoneW:
    for y in zoneY ..< zoneY + zoneH:
      if x < 0 or x >= mapWidth or y < 0 or y >= mapHeight:
        continue
      if mask[x][y] and randFloat(r) < 0.08:
        mask[x][y] = false

  # Ensure at least one corridor reaches the zone boundary so the dungeon
  # connects back to the rest of the map.
  let dirs = [(dx: 0, dy: -1), (dx: 0, dy: 1), (dx: -1, dy: 0), (dx: 1, dy: 0)]
  let dir = dirs[randIntInclusive(r, 0, dirs.high)]
  let maxStep =
    if dir.dx == 1: (zoneX + zoneW - 1) - cx
    elif dir.dx == -1: cx - zoneX
    elif dir.dy == 1: (zoneY + zoneH - 1) - cy
    else: cy - zoneY
  for step in 0 .. maxStep:
    let x = cx + dir.dx * step
    let y = cy + dir.dy * step
    for off in -armWidth .. armWidth:
      let gx = x + (if dir.dy == 0: 0 else: off)
      let gy = y + (if dir.dx == 0: 0 else: off)
      if gx < zoneX or gx >= zoneX + zoneW or gy < zoneY or gy >= zoneY + zoneH:
        continue
      if gx >= 0 and gx < mapWidth and gy >= 0 and gy < mapHeight:
        mask[gx][gy] = true

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
