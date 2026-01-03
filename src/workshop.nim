import vmath, terrain

export terrain.Structure

proc createVillage*(): Structure =
  ## Diamond town layout with walls and distinct interior buildings.
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
      let dx = x - center.x
      let dy = y - center.y
      let dist = abs(dx) + abs(dy)
      if dist == radius:
        layout[y][x] = StructureWallChar
      elif dist < radius:
        layout[y][x] = StructureFloorChar

  layout[center.y - radius][center.x] = StructureDoorChar
  layout[center.y + radius][center.x] = StructureDoorChar
  layout[center.y][center.x - radius] = StructureDoorChar
  layout[center.y][center.x + radius] = StructureDoorChar

  layout[center.y][center.x] = StructureAltarChar

  let buildingChars = @[
    StructureTownCenterChar,
    StructureArmoryChar,
    StructureBlacksmithChar,
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

  let ringDist = radius - 1
  let ringDistI32 = ringDist.int32
  var ring: seq[IVec2] = @[]
  ring.add(ivec2(0'i32, -ringDistI32))
  for i in 1 .. ringDist:
    ring.add(ivec2(i.int32, (-ringDist + i).int32))
  for i in 1 .. ringDist:
    ring.add(ivec2((ringDist - i).int32, i.int32))
  for i in 1 .. ringDist:
    ring.add(ivec2((-i).int32, (ringDist - i).int32))
  for i in 1 .. (ringDist - 1):
    ring.add(ivec2((-ringDist + i).int32, (-i).int32))

  for idx in 0 ..< min(ring.len, buildingChars.len):
    let pos = center + ring[idx]
    layout[pos.y][pos.x] = buildingChars[idx]

  result = Structure(
    width: size,
    height: size,
    centerPos: center,
    layout: layout
  )
