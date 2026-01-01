import std/math
import rng_compat
import ./biome_common

type
  DungeonRadialConfig* = object
    arms*: int = 8
    armWidth*: int = 1
    ring*: bool = true

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
  let dir = randIntInclusive(r, 0, 3)
  case dir
  of 0: # North
    for y in countdown(cy, zoneY):
      for ox in -armWidth .. armWidth:
        let gx = cx + ox
        if gx < zoneX or gx >= zoneX + zoneW:
          continue
        if gx >= 0 and gx < mapWidth and y >= 0 and y < mapHeight:
          mask[gx][y] = true
  of 1: # South
    for y in cy ..< zoneY + zoneH:
      for ox in -armWidth .. armWidth:
        let gx = cx + ox
        if gx < zoneX or gx >= zoneX + zoneW:
          continue
        if gx >= 0 and gx < mapWidth and y >= 0 and y < mapHeight:
          mask[gx][y] = true
  of 2: # West
    for x in countdown(cx, zoneX):
      for oy in -armWidth .. armWidth:
        let gy = cy + oy
        if gy < zoneY or gy >= zoneY + zoneH:
          continue
        if x >= 0 and x < mapWidth and gy >= 0 and gy < mapHeight:
          mask[x][gy] = true
  else: # East
    for x in cx ..< zoneX + zoneW:
      for oy in -armWidth .. armWidth:
        let gy = cy + oy
        if gy < zoneY or gy >= zoneY + zoneH:
          continue
        if x >= 0 and x < mapWidth and gy >= 0 and gy < mapHeight:
          mask[x][gy] = true
