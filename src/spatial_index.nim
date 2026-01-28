## spatial_index.nim - Spatial partitioning for O(1) nearest-thing queries
##
## This module provides procedures for maintaining and querying a cell-based
## spatial index for efficient nearest-neighbor queries.
##
## Architecture:
##   - World is partitioned into SpatialCellSize×SpatialCellSize cells
##   - Each cell maintains a seq of Things in that cell
##   - Queries examine cells within search radius
##
## Usage:
##   - Call addToSpatialIndex(env, thing) when a thing is added
##   - Call removeFromSpatialIndex(env, thing) when a thing is removed
##   - Call updateSpatialIndex(env, thing, oldPos) when a thing moves
##   - Use findNearestThingSpatial() instead of linear scans

import vmath
import types

proc cellCoords*(pos: IVec2): tuple[cx, cy: int] {.inline.} =
  ## Convert world position to cell coordinates
  result.cx = clamp(pos.x.int div SpatialCellSize, 0, SpatialCellsX - 1)
  result.cy = clamp(pos.y.int div SpatialCellSize, 0, SpatialCellsY - 1)

proc clearSpatialIndex*(env: Environment) =
  ## Clear all cells in the spatial index
  for cx in 0 ..< SpatialCellsX:
    for cy in 0 ..< SpatialCellsY:
      env.spatialIndex.cells[cx][cy].things.setLen(0)
      for kind in ThingKind:
        env.spatialIndex.kindCells[kind][cx][cy].setLen(0)

proc addToSpatialIndex*(env: Environment, thing: Thing) =
  ## Add a thing to the spatial index at its current position
  if thing.isNil or not isValidPos(thing.pos):
    return
  let (cx, cy) = cellCoords(thing.pos)
  env.spatialIndex.cells[cx][cy].things.add(thing)
  env.spatialIndex.kindCells[thing.kind][cx][cy].add(thing)

proc removeFromSpatialIndex*(env: Environment, thing: Thing) =
  ## Remove a thing from the spatial index
  if thing.isNil or not isValidPos(thing.pos):
    return
  let (cx, cy) = cellCoords(thing.pos)

  # Remove from general cell (swap-and-pop for O(1) removal)
  let cellThings = addr env.spatialIndex.cells[cx][cy].things
  for i in 0 ..< cellThings[].len:
    if cellThings[][i] == thing:
      cellThings[][i] = cellThings[][^1]
      cellThings[].setLen(cellThings[].len - 1)
      break

  # Remove from kind-specific cell (swap-and-pop for O(1) removal)
  let kindCellThings = addr env.spatialIndex.kindCells[thing.kind][cx][cy]
  for i in 0 ..< kindCellThings[].len:
    if kindCellThings[][i] == thing:
      kindCellThings[][i] = kindCellThings[][^1]
      kindCellThings[].setLen(kindCellThings[].len - 1)
      break

proc updateSpatialIndex*(env: Environment, thing: Thing, oldPos: IVec2) =
  ## Update a thing's position in the spatial index
  ## Called when a thing moves from oldPos to thing.pos
  if thing.isNil:
    return

  let (oldCx, oldCy) = cellCoords(oldPos)
  let (newCx, newCy) = cellCoords(thing.pos)

  # If cell hasn't changed, no update needed
  if oldCx == newCx and oldCy == newCy:
    return

  # Remove from old cell (swap-and-pop for O(1) removal)
  if isValidPos(oldPos):
    let cellThings = addr env.spatialIndex.cells[oldCx][oldCy].things
    for i in 0 ..< cellThings[].len:
      if cellThings[][i] == thing:
        cellThings[][i] = cellThings[][^1]
        cellThings[].setLen(cellThings[].len - 1)
        break

    let kindCellThings = addr env.spatialIndex.kindCells[thing.kind][oldCx][oldCy]
    for i in 0 ..< kindCellThings[].len:
      if kindCellThings[][i] == thing:
        kindCellThings[][i] = kindCellThings[][^1]
        kindCellThings[].setLen(kindCellThings[].len - 1)
        break

  # Add to new cell
  if isValidPos(thing.pos):
    env.spatialIndex.cells[newCx][newCy].things.add(thing)
    env.spatialIndex.kindCells[thing.kind][newCx][newCy].add(thing)

proc findNearestThingSpatial*(env: Environment, pos: IVec2, kind: ThingKind,
                               maxDist: int): Thing =
  ## Find nearest thing of a given kind using spatial index
  ## Returns nil if no thing found within maxDist
  result = nil
  var minDist = int.high

  let (cx, cy) = cellCoords(pos)
  # Clamp maxDist to avoid overflow when computing cellRadius
  # Max meaningful search is the map diagonal, but we cap to grid size for safety
  let clampedMaxDist = min(maxDist, max(SpatialCellsX, SpatialCellsY) * SpatialCellSize)
  let cellRadius = (clampedMaxDist + SpatialCellSize - 1) div SpatialCellSize

  for dx in -cellRadius .. cellRadius:
    for dy in -cellRadius .. cellRadius:
      let nx = cx + dx
      let ny = cy + dy
      if nx < 0 or nx >= SpatialCellsX or ny < 0 or ny >= SpatialCellsY:
        continue

      for thing in env.spatialIndex.kindCells[kind][nx][ny]:
        if thing.isNil:
          continue
        let dist = abs(thing.pos.x - pos.x) + abs(thing.pos.y - pos.y)
        if dist < minDist and dist < maxDist:
          minDist = dist
          result = thing

proc findNearestFriendlyThingSpatial*(env: Environment, pos: IVec2, teamId: int,
                                       kind: ThingKind, maxDist: int): Thing =
  ## Find nearest team-owned thing of a given kind using spatial index
  result = nil
  var minDist = int.high

  let (cx, cy) = cellCoords(pos)
  # Clamp maxDist to avoid overflow when computing cellRadius
  let clampedMaxDist = min(maxDist, max(SpatialCellsX, SpatialCellsY) * SpatialCellSize)
  let cellRadius = (clampedMaxDist + SpatialCellSize - 1) div SpatialCellSize

  for dx in -cellRadius .. cellRadius:
    for dy in -cellRadius .. cellRadius:
      let nx = cx + dx
      let ny = cy + dy
      if nx < 0 or nx >= SpatialCellsX or ny < 0 or ny >= SpatialCellsY:
        continue

      for thing in env.spatialIndex.kindCells[kind][nx][ny]:
        if thing.isNil or thing.teamId != teamId:
          continue
        let dist = abs(thing.pos.x - pos.x) + abs(thing.pos.y - pos.y)
        if dist < minDist and dist < maxDist:
          minDist = dist
          result = thing

proc findNearestEnemyAgentSpatial*(env: Environment, pos: IVec2, teamId: int,
                                    maxDist: int): Thing =
  ## Find nearest enemy agent (alive, different team) using spatial index.
  ## Uses Chebyshev distance for consistency with game mechanics.
  result = nil
  var minDist = int.high

  let (cx, cy) = cellCoords(pos)
  let clampedMaxDist = min(maxDist, max(SpatialCellsX, SpatialCellsY) * SpatialCellSize)
  let cellRadius = (clampedMaxDist + SpatialCellSize - 1) div SpatialCellSize

  for dx in -cellRadius .. cellRadius:
    for dy in -cellRadius .. cellRadius:
      let nx = cx + dx
      let ny = cy + dy
      if nx < 0 or nx >= SpatialCellsX or ny < 0 or ny >= SpatialCellsY:
        continue

      for thing in env.spatialIndex.kindCells[Agent][nx][ny]:
        if thing.isNil or not isAgentAlive(env, thing):
          continue
        if getTeamId(thing) == teamId:
          continue
        let dist = max(abs(thing.pos.x - pos.x), abs(thing.pos.y - pos.y))
        if dist <= maxDist and dist < minDist:
          minDist = dist
          result = thing

proc findNearestEnemyInRangeSpatial*(env: Environment, pos: IVec2, teamId: int,
                                      minRange, maxRange: int): Thing =
  ## Find nearest enemy agent in [minRange, maxRange] Chebyshev distance.
  ## Used by towers and buildings with minimum attack ranges.
  result = nil
  var bestDist = int.high

  let (cx, cy) = cellCoords(pos)
  let clampedMaxDist = min(maxRange, max(SpatialCellsX, SpatialCellsY) * SpatialCellSize)
  let cellRadius = (clampedMaxDist + SpatialCellSize - 1) div SpatialCellSize

  for dx in -cellRadius .. cellRadius:
    for dy in -cellRadius .. cellRadius:
      let nx = cx + dx
      let ny = cy + dy
      if nx < 0 or nx >= SpatialCellsX or ny < 0 or ny >= SpatialCellsY:
        continue

      for thing in env.spatialIndex.kindCells[Agent][nx][ny]:
        if thing.isNil or not isAgentAlive(env, thing):
          continue
        if getTeamId(thing) == teamId:
          continue
        let dist = max(abs(thing.pos.x - pos.x), abs(thing.pos.y - pos.y))
        if dist >= minRange and dist <= maxRange and dist < bestDist:
          bestDist = dist
          result = thing

proc collectEnemiesInRangeSpatial*(env: Environment, pos: IVec2, teamId: int,
                                    maxRange: int, targets: var seq[Thing]) =
  ## Collect all enemy agents within maxRange Chebyshev distance.
  ## Used by town centers that need to fire at multiple targets.
  let (cx, cy) = cellCoords(pos)
  let clampedMaxDist = min(maxRange, max(SpatialCellsX, SpatialCellsY) * SpatialCellSize)
  let cellRadius = (clampedMaxDist + SpatialCellSize - 1) div SpatialCellSize

  for dx in -cellRadius .. cellRadius:
    for dy in -cellRadius .. cellRadius:
      let nx = cx + dx
      let ny = cy + dy
      if nx < 0 or nx >= SpatialCellsX or ny < 0 or ny >= SpatialCellsY:
        continue

      for thing in env.spatialIndex.kindCells[Agent][nx][ny]:
        if thing.isNil or not isAgentAlive(env, thing):
          continue
        if getTeamId(thing) == teamId:
          continue
        let dist = max(abs(thing.pos.x - pos.x), abs(thing.pos.y - pos.y))
        if dist <= maxRange:
          targets.add(thing)

proc collectAlliesInRangeSpatial*(env: Environment, pos: IVec2, teamId: int,
                                    maxRange: int, allies: var seq[Thing]) =
  ## Collect all allied agents within maxRange Chebyshev distance.
  let (cx, cy) = cellCoords(pos)
  let clampedMaxDist = min(maxRange, max(SpatialCellsX, SpatialCellsY) * SpatialCellSize)
  let cellRadius = (clampedMaxDist + SpatialCellSize - 1) div SpatialCellSize

  for dx in -cellRadius .. cellRadius:
    for dy in -cellRadius .. cellRadius:
      let nx = cx + dx
      let ny = cy + dy
      if nx < 0 or nx >= SpatialCellsX or ny < 0 or ny >= SpatialCellsY:
        continue

      for thing in env.spatialIndex.kindCells[Agent][nx][ny]:
        if thing.isNil or not isAgentAlive(env, thing):
          continue
        if getTeamId(thing) != teamId:
          continue
        let dist = max(abs(thing.pos.x - pos.x), abs(thing.pos.y - pos.y))
        if dist <= maxRange:
          allies.add(thing)

proc rebuildSpatialIndex*(env: Environment) =
  ## Rebuild the entire spatial index from scratch
  ## Useful for initialization or after major map changes
  clearSpatialIndex(env)
  for thing in env.things:
    addToSpatialIndex(env, thing)
