import rng_compat
import ./biome_common

type
  DungeonMazeConfig* = object
    wallKeepProb*: float = 0.65

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
