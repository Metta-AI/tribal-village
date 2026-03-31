import std/unittest
import vmath
import terrain

proc neverInCorner(x, y: int): bool =
  discard x
  discard y
  false

suite "River Fill":
  test "diagonal overlaps do not downgrade centerline water to shallow":
    var grid: TerrainGrid
    let path = @[
      ivec2(20'i32, 20'i32),
      ivec2(21'i32, 21'i32),
      ivec2(22'i32, 22'i32),
    ]

    placeWaterPath(grid, path, RiverWidth div 2, 64, 64, neverInCorner)

    for pos in path:
      check grid[pos.x.int][pos.y.int] == Water
