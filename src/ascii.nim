proc thingAsciiChar*(kind: ThingKind): char =
  ## ASCII schema for map objects (typeable characters).
  if isBuildingKind(kind):
    return buildingAscii(kind)
  case kind:
  of Agent: '@'
  of Wall: '#'
  of Pine: 't'
  of Palm: 'P'
  of Magma: 'v'
  of Spawner: 'Z'
  of Tumor: 'X'
  of Cow: 'w'
  of Skeleton: 'K'
  of Stump: 'p'
  of Lantern: 'l'
  else: '?'

proc render*(env: Environment): string =
  for y in 0 ..< MapHeight:
    for x in 0 ..< MapWidth:
      var cell = " "
      # First check terrain
      cell = case env.terrain[x][y]
        of Empty: " "
        of Water: "~"
        of Bridge: "="
        of Wheat: "."
        of Pine: "T"
        of Fertile: "f"
        of Road: "r"
        of Stone: "S"
        of Gold: "G"
        of Bush: "b"
        of Animal: "a"
        of Grass: "g"
        of Cactus: "c"
        of Dune: "d"
        of Stalagmite: "m"
        of Palm: "P"
        of Sand: "s"
        of Snow: "n"
      # Then override with objects if present
      for thing in env.things:
        if thing.pos.x == x and thing.pos.y == y:
          cell = $thingAsciiChar(thing.kind)
          break
      result.add(cell)
    result.add("\n")
