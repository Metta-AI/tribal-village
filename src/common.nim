when defined(emscripten):
  import emscripten/html5
else:
  import std/times

import vmath

proc nowSeconds*(): float64 =
  ## Wall-clock seconds for seeding and timing.
  when defined(emscripten):
    emscripten_get_now() / 1000.0
  else:
    epochTime()

type
  OrientationDelta* = tuple[x, y: int]
  Orientation* = enum
    N = 0  ## North (Up)
    S = 1  ## South (Down)
    W = 2  ## West (Left)
    E = 3  ## East (Right)
    NW = 4 ## Northwest (Up-Left)
    NE = 5 ## Northeast (Up-Right)
    SW = 6 ## Southwest (Down-Left)
    SE = 7 ## Southeast (Down-Right)

const OrientationDeltas*: array[8, OrientationDelta] = [
  (x: 0, y: -1),   # N
  (x: 0, y: 1),    # S
  (x: -1, y: 0),   # W
  (x: 1, y: 0),    # E
  (x: -1, y: -1),  # NW
  (x: 1, y: -1),   # NE
  (x: -1, y: 1),   # SW
  (x: 1, y: 1)     # SE
]

{.push inline.}
proc getOrientationDelta*(orient: Orientation): OrientationDelta =
  OrientationDeltas[ord(orient)]
{.pop.}

proc isDiagonal*(orient: Orientation): bool =
  ord(orient) >= ord(NW)

proc getOpposite*(orient: Orientation): Orientation =
  case orient
  of N: S
  of S: N
  of W: E
  of E: W
  of NW: SE
  of NE: SW
  of SW: NE
  of SE: NW

proc orientationToVec*(orientation: Orientation): IVec2 =
  case orientation
  of N: result = ivec2(0, -1)
  of S: result = ivec2(0, 1)
  of E: result = ivec2(1, 0)
  of W: result = ivec2(-1, 0)
  of NW: result = ivec2(-1, -1)
  of NE: result = ivec2(1, -1)
  of SW: result = ivec2(-1, 1)
  of SE: result = ivec2(1, 1)

proc ivec2*(x, y: int): IVec2 =
  ## Convenience helper for integer vector construction.
  result.x = x.int32
  result.y = y.int32

proc getDirectionTo*(fromPos, toPos: IVec2): IVec2 =
  ## Normalised taxicab direction from one point to another.
  let dx = toPos.x - fromPos.x
  let dy = toPos.y - fromPos.y
  result.x = (if dx > 0: 1 elif dx < 0: -1 else: 0)
  result.y = (if dy > 0: 1 elif dy < 0: -1 else: 0)

proc relativeLocation*(orientation: Orientation, distance, offset: int): IVec2 =
  ## Companion helper used by the environment pathing code.
  case orientation
  of N: ivec2(-offset, -distance)
  of S: ivec2(offset, distance)
  of E: ivec2(distance, -offset)
  of W: ivec2(-distance, offset)
  of NW: ivec2(-distance - offset, -distance + offset)
  of NE: ivec2(distance - offset, -distance - offset)
  of SW: ivec2(-distance + offset, distance + offset)
  of SE: ivec2(distance + offset, distance - offset)

proc manhattanDistance*(a, b: IVec2): int =
  abs(a.x - b.x) + abs(a.y - b.y)

proc euclideanDistance*(a, b: IVec2): float =
  let dx = (a.x - b.x).float
  let dy = (a.y - b.y).float
  sqrt(dx * dx + dy * dy)
