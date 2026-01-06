import vmath, terrain

export terrain.Structure

proc createVillage*(): Structure =
  ## Small town starter: altar + town center, no walls.
  const size = 7
  const radius = 3
  let center = ivec2(radius, radius)
  var layout: seq[seq[char]] = newSeq[seq[char]](size)
  for y in 0 ..< size:
    layout[y] = newSeq[char](size)
    for x in 0 ..< size:
      layout[y][x] = ' '

  # Clear a small plaza around the altar so the start isn't cluttered.
  for y in 0 ..< size:
    for x in 0 ..< size:
      if abs(x - center.x) + abs(y - center.y) <= 2:
        layout[y][x] = StructureFloorChar

  result = Structure(
    width: size,
    height: size,
    centerPos: center,
    layout: layout
  )
