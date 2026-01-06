# ============== CLIPPY AI ==============




{.push inline.}
proc isValidEmptyPosition(env: Environment, pos: IVec2): bool =
  ## Check if a position is within map bounds, empty, and not blocked terrain
  pos.x >= MapBorder and pos.x < MapWidth - MapBorder and
    pos.y >= MapBorder and pos.y < MapHeight - MapBorder and
    env.isEmpty(pos) and not env.hasDoor(pos) and not isBlockedTerrain(env.terrain[pos.x][pos.y]) and
    env.terrain[pos.x][pos.y] != Wheat

proc generateRandomMapPosition(r: var Rand): IVec2 =
  ## Generate a random position within map boundaries
  ivec2(
    int32(randIntExclusive(r, MapBorder, MapWidth - MapBorder)),
    int32(randIntExclusive(r, MapBorder, MapHeight - MapBorder))
  )
{.pop.}

proc findEmptyPositionsAround*(env: Environment, center: IVec2, radius: int): seq[IVec2] =
  ## Find empty positions around a center point within a given radius
  result = @[]
  for dx in -radius .. radius:
    for dy in -radius .. radius:
      if dx == 0 and dy == 0:
        continue  # Skip the center position
      let pos = ivec2(center.x + dx, center.y + dy)
      if env.isValidEmptyPosition(pos):
        result.add(pos)

proc findFirstEmptyPositionAround*(env: Environment, center: IVec2, radius: int): IVec2 =
  ## Find first empty position around center (no allocation)
  for dx in -radius .. radius:
    for dy in -radius .. radius:
      if dx == 0 and dy == 0:
        continue  # Skip the center position
      let pos = ivec2(center.x + dx, center.y + dy)
      if env.isValidEmptyPosition(pos):
        return pos
  return ivec2(-1, -1)  # No empty position found


const
  TumorBranchRange = 5
  TumorBranchMinAge = 2
  TumorBranchChance = 0.1
  TumorAdjacencyDeathChance = 1.0 / 3.0

let TumorBranchOffsets = block:
  var offsets: seq[IVec2] = @[]
  for dx in -TumorBranchRange .. TumorBranchRange:
    for dy in -TumorBranchRange .. TumorBranchRange:
      if dx == 0 and dy == 0:
        continue
      if max(abs(dx), abs(dy)) > TumorBranchRange:
        continue
      offsets.add(ivec2(dx, dy))
  offsets

proc findTumorBranchTarget(tumor: Thing, env: Environment, r: var Rand): IVec2 =
  ## Pick a random empty tile within the tumor's branching range
  var chosen = ivec2(-1, -1)
  var count = 0
  const AdjacentOffsets = [ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0)]

  for offset in TumorBranchOffsets:
    let candidate = tumor.pos + offset
    if not env.isValidEmptyPosition(candidate):
      continue

    var adjacentTumor = false
    for adj in AdjacentOffsets:
      let checkPos = candidate + adj
      if not isValidPos(checkPos):
        continue
      let occupant = env.getThing(checkPos)
      if not isNil(occupant) and occupant.kind == Tumor:
        adjacentTumor = true
        break
    if not adjacentTumor:
      inc count
      if randIntExclusive(r, 0, count) == 0:
        chosen = candidate

  if count == 0:
    return ivec2(-1, -1)
  chosen

proc randomEmptyPos(r: var Rand, env: Environment): IVec2 =
  # Try with moderate attempts first
  for i in 0 ..< 100:
    let pos = r.generateRandomMapPosition()
    if env.isValidEmptyPosition(pos):
      return pos
  # Try harder with more attempts
  for i in 0 ..< 1000:
    let pos = r.generateRandomMapPosition()
    if env.isValidEmptyPosition(pos):
      return pos
  quit("Failed to find an empty position, map too full!")
