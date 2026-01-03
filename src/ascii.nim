proc thingAsciiChar*(kind: ThingKind): char =
  ## ASCII schema for map objects (typeable characters).
  case kind:
  of Agent: '@'
  of Wall: '#'
  of Pine: 't'
  of Palm: 'P'
  of Mine: 'M'
  of Magma: 'v'
  of Altar: 'a'
  of Spawner: 'Z'
  of Tumor: 'X'
  of Cow: 'w'
  of Skeleton: 'K'
  of Armory: 'A'
  of Forge: 'F'
  of ClayOven: 'C'
  of WeavingLoom: 'W'
  of Bed: 'B'
  of Chair: 'H'
  of Table: 'T'
  of Statue: 'S'
  of Outpost: '^'
  of Barrel: 'b'
  of Mill: 'm'
  of LumberCamp: 'L'
  of MiningCamp: 'G'
  of Farm: 'f'
  of Stump: 'p'
  of Lantern: 'l'
  of TownCenter: 'N'
  of House: 'h'
  of Barracks: 'r'
  of ArcheryRange: 'g'
  of Stable: 's'
  of SiegeWorkshop: 'i'
  of Blacksmith: 'k'
  of Market: 'e'
  of Dock: 'd'
  of Monastery: 'y'
  of University: 'u'
  of Castle: 'c'

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
        of Tree: "T"
        of Fertile: "f"
        of Road: "r"
        of Rock: "R"
        of Gem: "G"
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
          case thing.kind
          of Agent:
            cell = "A"
          of Wall:
            cell = "#"
          of Pine:
            cell = "T"
          of Palm:
            cell = "P"
          of Mine:
            cell = "m"
          of Magma:
            cell = "v"
          of Altar:
            cell = "a"
          of Spawner:
            cell = "t"
          of Tumor:
            cell = "C"
          of Cow:
            cell = "o"
          of Skeleton:
            cell = "x"
          of Armory:
            cell = "A"
          of Forge:
            cell = "F"
          of ClayOven:
            cell = "O"
          of WeavingLoom:
            cell = "W"
          of Barrel:
            cell = "b"
          of Mill:
            cell = "M"
          of LumberCamp:
            cell = "l"
          of MiningCamp:
            cell = "n"
          of Farm:
            cell = "f"
          of Stump:
            cell = "u"
          of Bed:
            cell = "B"
          of Chair:
            cell = "H"
          of Table:
            cell = "T"
          of Statue:
            cell = "S"
          of Outpost:
            cell = "^"
          of Lantern:
            cell = "L"
          of TownCenter:
            cell = "N"
          of House:
            cell = "h"
          of Barracks:
            cell = "B"
          of ArcheryRange:
            cell = "R"
          of Stable:
            cell = "S"
          of SiegeWorkshop:
            cell = "G"
          of Blacksmith:
            cell = "K"
          of Market:
            cell = "M"
          of Dock:
            cell = "D"
          of Monastery:
            cell = "O"
          of University:
            cell = "U"
          of Castle:
            cell = "C"
          break
      result.add(cell)
    result.add("\n")
