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

when defined(spatialStats):
  import std/[strutils, os]

  type
    SpatialQueryKind* = enum
      sqkFindNearest, sqkFindNearestFriendly, sqkFindNearestEnemy,
      sqkFindNearestEnemyInRange, sqkCollectEnemies, sqkCollectAllies

  var
    spatialTotalQueries*: array[SpatialQueryKind, int]
    spatialTotalCellsScanned*: array[SpatialQueryKind, int]
    spatialTotalThingsExamined*: array[SpatialQueryKind, int]
    spatialTotalHits*: array[SpatialQueryKind, int]
    spatialTotalMisses*: array[SpatialQueryKind, int]
    spatialReportInterval*: int = 100
    spatialStepCounter*: int = 0

  block:
    let envInterval = getEnv("TV_SPATIAL_STATS_INTERVAL", "100")
    try:
      spatialReportInterval = parseInt(envInterval)
    except ValueError:
      discard

  proc resetSpatialCounters*() =
    for k in SpatialQueryKind:
      spatialTotalQueries[k] = 0
      spatialTotalCellsScanned[k] = 0
      spatialTotalThingsExamined[k] = 0
      spatialTotalHits[k] = 0
      spatialTotalMisses[k] = 0

  proc printSpatialReport*() =
    inc spatialStepCounter
    if spatialReportInterval <= 0 or spatialStepCounter mod spatialReportInterval != 0:
      return

    let stepStart = spatialStepCounter - spatialReportInterval + 1
    echo ""
    echo "=== Spatial Index Report (steps " & $stepStart & "-" & $spatialStepCounter & ") ==="

    const header = "Query Type                 Queries  Cells/Q  Things/Q      Hits   Misses   Hit%"
    const separator = "-------------------------------------------------------------------------------"
    echo header
    echo separator

    const names: array[SpatialQueryKind, string] = [
      "findNearest", "findNearestFriendly", "findNearestEnemy",
      "findNearestEnemyInRange", "collectEnemies", "collectAllies"
    ]

    proc padLeft(s: string, width: int): string =
      if s.len >= width: return s
      result = " ".repeat(width - s.len) & s

    proc padRight(s: string, width: int): string =
      if s.len >= width: return s
      result = s & " ".repeat(width - s.len)

    proc fmtFloat1(v: float64): string =
      let i = int(v * 10 + 0.5)
      $int(i div 10) & "." & $int(i mod 10)

    var totalQ, totalC, totalT, totalH, totalM: int
    for k in SpatialQueryKind:
      let q = spatialTotalQueries[k]
      if q == 0:
        echo padRight(names[k], 26) & " " & padLeft("0", 8) &
          padLeft("-", 9) & padLeft("-", 11) & padLeft("-", 10) &
          padLeft("-", 9) & padLeft("-", 7)
        continue
      let avgCells = spatialTotalCellsScanned[k].float64 / q.float64
      let avgThings = spatialTotalThingsExamined[k].float64 / q.float64
      let h = spatialTotalHits[k]
      let m = spatialTotalMisses[k]
      let hitPct = if h + m > 0: (h.float64 / (h + m).float64) * 100.0 else: 0.0
      echo padRight(names[k], 26) & " " & padLeft($q, 8) &
        padLeft(fmtFloat1(avgCells), 9) & padLeft(fmtFloat1(avgThings), 11) &
        padLeft($h, 10) & padLeft($m, 9) & padLeft(fmtFloat1(hitPct) & "%", 7)
      totalQ += q; totalC += spatialTotalCellsScanned[k]
      totalT += spatialTotalThingsExamined[k]; totalH += h; totalM += m

    echo separator
    if totalQ > 0:
      let avgC = totalC.float64 / totalQ.float64
      let avgT = totalT.float64 / totalQ.float64
      let hitPct = if totalH + totalM > 0: (totalH.float64 / (totalH + totalM).float64) * 100.0 else: 0.0
      echo padRight("TOTAL", 26) & " " & padLeft($totalQ, 8) &
        padLeft(fmtFloat1(avgC), 9) & padLeft(fmtFloat1(avgT), 11) &
        padLeft($totalH, 10) & padLeft($totalM, 9) & padLeft(fmtFloat1(hitPct) & "%", 7)
    echo ""

    resetSpatialCounters()

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

template forEachInRadius(envExpr: Environment, posExpr: IVec2,
                          kindExpr: ThingKind, maxDistExpr: int,
                          thingVar: untyped, body: untyped) =
  ## Iterate over non-nil things of `kindExpr` within `maxDistExpr` of `posExpr`.
  ## The body receives each thing as `thingVar`. A mutable `searchRadius` (in
  ## cells) is injected; the body may shrink it for early-exit optimisation in
  ## findNearest* queries.
  let qPos  {.inject.} = posExpr
  let (qCx, qCy) = cellCoords(qPos)
  let clampedMax = min(maxDistExpr, max(SpatialCellsX, SpatialCellsY) * SpatialCellSize)
  var searchRadius {.inject.} = (clampedMax + SpatialCellSize - 1) div SpatialCellSize
  let maxRadius = searchRadius
  let queryKind = kindExpr
  let queryEnv  = envExpr
  when defined(spatialStats):
    var cellsScanned {.inject.} = 0
    var thingsExamined {.inject.} = 0

  for dx in -maxRadius .. maxRadius:
    if abs(dx) > searchRadius: continue
    for dy in -maxRadius .. maxRadius:
      if abs(dy) > searchRadius: continue
      let nx = qCx + dx
      let ny = qCy + dy
      if nx < 0 or nx >= SpatialCellsX or ny < 0 or ny >= SpatialCellsY:
        continue
      when defined(spatialStats):
        inc cellsScanned
      for thingVar in queryEnv.spatialIndex.kindCells[queryKind][nx][ny]:
        if not thingVar.isNil:
          when defined(spatialStats):
            inc thingsExamined
          body

proc findNearestThingSpatial*(env: Environment, pos: IVec2, kind: ThingKind,
                               maxDist: int): Thing =
  ## Find nearest thing of a given kind using spatial index.
  ## Returns nil if no thing found within maxDist.
  result = nil
  var minDist = int.high

  forEachInRadius(env, pos, kind, maxDist, thing):
    let dist = abs(thing.pos.x - qPos.x) + abs(thing.pos.y - qPos.y)
    if dist < minDist and dist < maxDist:
      minDist = dist
      result = thing
      searchRadius = (dist + SpatialCellSize - 1) div SpatialCellSize

  when defined(spatialStats):
    inc spatialTotalQueries[sqkFindNearest]
    spatialTotalCellsScanned[sqkFindNearest] += cellsScanned
    spatialTotalThingsExamined[sqkFindNearest] += thingsExamined
    if result.isNil: inc spatialTotalMisses[sqkFindNearest]
    else: inc spatialTotalHits[sqkFindNearest]

proc findNearestFriendlyThingSpatial*(env: Environment, pos: IVec2, teamId: int,
                                       kind: ThingKind, maxDist: int): Thing =
  ## Find nearest team-owned thing of a given kind using spatial index.
  result = nil
  var minDist = int.high

  forEachInRadius(env, pos, kind, maxDist, thing):
    if thing.teamId != teamId:
      continue
    let dist = abs(thing.pos.x - qPos.x) + abs(thing.pos.y - qPos.y)
    if dist < minDist and dist < maxDist:
      minDist = dist
      result = thing
      searchRadius = (dist + SpatialCellSize - 1) div SpatialCellSize

  when defined(spatialStats):
    inc spatialTotalQueries[sqkFindNearestFriendly]
    spatialTotalCellsScanned[sqkFindNearestFriendly] += cellsScanned
    spatialTotalThingsExamined[sqkFindNearestFriendly] += thingsExamined
    if result.isNil: inc spatialTotalMisses[sqkFindNearestFriendly]
    else: inc spatialTotalHits[sqkFindNearestFriendly]

proc findNearestEnemyAgentSpatial*(env: Environment, pos: IVec2, teamId: int,
                                    maxDist: int): Thing =
  ## Find nearest enemy agent (alive, different team) using spatial index.
  ## Uses Chebyshev distance for consistency with game mechanics.
  result = nil
  var minDist = int.high

  forEachInRadius(env, pos, Agent, maxDist, thing):
    if not isAgentAlive(env, thing):
      continue
    if getTeamId(thing) == teamId:
      continue
    let dist = max(abs(thing.pos.x - qPos.x), abs(thing.pos.y - qPos.y))
    if dist <= maxDist and dist < minDist:
      minDist = dist
      result = thing
      searchRadius = (dist + SpatialCellSize - 1) div SpatialCellSize

  when defined(spatialStats):
    inc spatialTotalQueries[sqkFindNearestEnemy]
    spatialTotalCellsScanned[sqkFindNearestEnemy] += cellsScanned
    spatialTotalThingsExamined[sqkFindNearestEnemy] += thingsExamined
    if result.isNil: inc spatialTotalMisses[sqkFindNearestEnemy]
    else: inc spatialTotalHits[sqkFindNearestEnemy]

proc findNearestEnemyInRangeSpatial*(env: Environment, pos: IVec2, teamId: int,
                                      minRange, maxRange: int): Thing =
  ## Find nearest enemy agent in [minRange, maxRange] Chebyshev distance.
  ## Used by towers and buildings with minimum attack ranges.
  result = nil
  var bestDist = int.high

  forEachInRadius(env, pos, Agent, maxRange, thing):
    if not isAgentAlive(env, thing):
      continue
    if getTeamId(thing) == teamId:
      continue
    let dist = max(abs(thing.pos.x - qPos.x), abs(thing.pos.y - qPos.y))
    if dist >= minRange and dist <= maxRange and dist < bestDist:
      bestDist = dist
      result = thing
      searchRadius = (dist + SpatialCellSize - 1) div SpatialCellSize

  when defined(spatialStats):
    inc spatialTotalQueries[sqkFindNearestEnemyInRange]
    spatialTotalCellsScanned[sqkFindNearestEnemyInRange] += cellsScanned
    spatialTotalThingsExamined[sqkFindNearestEnemyInRange] += thingsExamined
    if result.isNil: inc spatialTotalMisses[sqkFindNearestEnemyInRange]
    else: inc spatialTotalHits[sqkFindNearestEnemyInRange]

proc collectEnemiesInRangeSpatial*(env: Environment, pos: IVec2, teamId: int,
                                    maxRange: int, targets: var seq[Thing]) =
  ## Collect all enemy agents within maxRange Chebyshev distance.
  ## Used by town centers that need to fire at multiple targets.
  when defined(spatialStats):
    let prevLen = targets.len
  forEachInRadius(env, pos, Agent, maxRange, thing):
    if not isAgentAlive(env, thing):
      continue
    if getTeamId(thing) == teamId:
      continue
    let dist = max(abs(thing.pos.x - qPos.x), abs(thing.pos.y - qPos.y))
    if dist <= maxRange:
      targets.add(thing)

  when defined(spatialStats):
    inc spatialTotalQueries[sqkCollectEnemies]
    spatialTotalCellsScanned[sqkCollectEnemies] += cellsScanned
    spatialTotalThingsExamined[sqkCollectEnemies] += thingsExamined
    let found = targets.len - prevLen
    if found > 0: inc spatialTotalHits[sqkCollectEnemies]
    else: inc spatialTotalMisses[sqkCollectEnemies]

proc collectAlliesInRangeSpatial*(env: Environment, pos: IVec2, teamId: int,
                                    maxRange: int, allies: var seq[Thing]) =
  ## Collect all allied agents within maxRange Chebyshev distance.
  when defined(spatialStats):
    let prevLen = allies.len
  forEachInRadius(env, pos, Agent, maxRange, thing):
    if not isAgentAlive(env, thing):
      continue
    if getTeamId(thing) != teamId:
      continue
    let dist = max(abs(thing.pos.x - qPos.x), abs(thing.pos.y - qPos.y))
    if dist <= maxRange:
      allies.add(thing)

  when defined(spatialStats):
    inc spatialTotalQueries[sqkCollectAllies]
    spatialTotalCellsScanned[sqkCollectAllies] += cellsScanned
    spatialTotalThingsExamined[sqkCollectAllies] += thingsExamined
    let found = allies.len - prevLen
    if found > 0: inc spatialTotalHits[sqkCollectAllies]
    else: inc spatialTotalMisses[sqkCollectAllies]

proc rebuildSpatialIndex*(env: Environment) =
  ## Rebuild the entire spatial index from scratch
  ## Useful for initialization or after major map changes
  clearSpatialIndex(env)
  for thing in env.things:
    addToSpatialIndex(env, thing)
