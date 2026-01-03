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
