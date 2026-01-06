proc thingAsciiChar*(kind: ThingKind): char =
  ## ASCII schema for map objects (typeable characters).
  thingAscii(kind)

proc render*(env: Environment): string =
  for y in 0 ..< MapHeight:
    for x in 0 ..< MapWidth:
      var cell = " "
      # First check terrain
      cell = $terrainAscii(env.terrain[x][y])
      # Then override with objects if present
      for thing in env.things:
        if thing.pos.x == x and thing.pos.y == y:
          cell = $thingAsciiChar(thing.kind)
          break
      result.add(cell)
    result.add("\n")
