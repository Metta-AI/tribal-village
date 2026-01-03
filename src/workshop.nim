import vmath, terrain

export terrain.Structure

proc createVillage*(): Structure =
  ## Square town layout with walls, gates, and edge buildings.
  const size = 11
  const radius = 5
  let center = ivec2(radius, radius)
  var layout: seq[seq[char]] = newSeq[seq[char]](size)
  for y in 0 ..< size:
    layout[y] = newSeq[char](size)
    for x in 0 ..< size:
      layout[y][x] = ' '

  for y in 0 ..< size:
    for x in 0 ..< size:
      if x == 0 or y == 0 or x == size - 1 or y == size - 1:
        layout[y][x] = StructureWallChar
      else:
        layout[y][x] = StructureFloorChar

  layout[0][center.x] = StructureDoorChar
  layout[size - 1][center.x] = StructureDoorChar
  layout[center.y][0] = StructureDoorChar
  layout[center.y][size - 1] = StructureDoorChar

  layout[center.y][center.x] = StructureAltarChar

  let buildingChars = @[
    StructureTownCenterChar,
    StructureArmoryChar,
    StructureForgeChar,
    StructureClayOvenChar,
    StructureWeavingLoomChar,
    StructureBarracksChar,
    StructureArcheryRangeChar,
    StructureStableChar,
    StructureSiegeWorkshopChar,
    StructureMarketChar,
    StructureDockChar,
    StructureUniversityChar
  ]

  let innerMin = 1
  let innerMax = size - 2
  proc isGateFront(pos: IVec2): bool =
    (pos.x == center.x and (pos.y == innerMin or pos.y == innerMax)) or
    (pos.y == center.y and (pos.x == innerMin or pos.x == innerMax))

  var edgePositions: seq[IVec2] = @[]
  var x = innerMin
  while x <= innerMax:
    edgePositions.add(ivec2(x.int32, innerMin.int32))
    x += 2
  var y = innerMin + 2
  while y <= innerMax - 2:
    edgePositions.add(ivec2(innerMax.int32, y.int32))
    y += 2
  x = innerMax
  while x >= innerMin:
    edgePositions.add(ivec2(x.int32, innerMax.int32))
    x -= 2
  y = innerMax - 2
  while y >= innerMin + 2:
    edgePositions.add(ivec2(innerMin.int32, y.int32))
    y -= 2

  var placed = 0
  for pos in edgePositions:
    if placed >= buildingChars.len:
      break
    if pos == center or isGateFront(pos):
      continue
    layout[pos.y][pos.x] = buildingChars[placed]
    inc placed

  result = Structure(
    width: size,
    height: size,
    centerPos: center,
    layout: layout
  )
