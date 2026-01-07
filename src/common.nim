when defined(emscripten):
  import windy/platforms/emscripten/emdefs
else:
  import std/[times]

import
  boxy, windy, vmath

type
  IRect* = object
    x*: int
    y*: int
    w*: int
    h*: int

  PanelType* = enum
    WorldMap

  Panel* = ref object
    panelType*: PanelType
    rect*: IRect
    name*: string

    pos*: Vec2
    vel*: Vec2
    zoom*: float32 = 1.25     # preferred default zoom (start further out)
    zoomVel*: float32
    minZoom*: float32 = 1.0   # allow further zoom-out
    maxZoom*: float32 = 8.0   # reduce maximum zoom-out
    hasMouse*: bool = false
    visible*: bool = true

  AreaLayout* = enum
    Horizontal
    Vertical

  Area* = ref object
    layout*: AreaLayout
    rect*: IRect
    areas*: seq[Area]
    panels*: seq[Panel]


  Settings* = object
    showFogOfWar* = false
    showVisualRange* = true
    showGrid* = true
    showObservations* = -1

proc nowSeconds*(): float64 =
  when defined(emscripten):
    emscripten_get_now() / 1000.0
  else:
    epochTime()

var
  window*: Window
  rootArea*: Area
  bxy*: Boxy
  frame*: int


  worldMapPanel*: Panel
  globalFooterPanel*: Panel

  settings* = Settings()

  play*: bool = true
  playSpeed*: float32 = 0.015625  # faster default playback
  lastSimTime*: float64 = nowSeconds()

const
  DefaultPlaySpeed* = 0.015625

var
  followSelection*: bool = false
  mouseCaptured*: bool = false
  mouseCapturedPanel*: Panel = nil
  mouseDownPos*: Vec2 = vec2(0, 0)

proc logicalMousePos*(window: Window): Vec2 =
  ## Mouse position in logical coordinates (accounts for HiDPI scaling).
  window.mousePos.vec2 / window.contentScale

proc irect*(x, y, w, h: int): IRect =
  ## Utility function to create IRect from coordinates
  IRect(x: x, y: y, w: w, h: h)

proc irect*(rect: Rect): IRect =
  ## Convert floating point Rect to integer IRect
  IRect(x: rect.x.int, y: rect.y.int, w: rect.w.int, h: rect.h.int)

proc rect*(irect: IRect): Rect =
  ## Convert integer IRect to floating point Rect
  Rect(x: irect.x.float32, y: irect.y.float32, w: irect.w.float32, h: irect.h.float32)

type
  OrientationDelta* = tuple[x, y: int]
  Orientation* = enum
    N = 0  # North (Up)
    S = 1  # South (Down) 
    W = 2  # West (Left)
    E = 3  # East (Right)
    NW = 4 # Northwest (Up-Left)
    NE = 5 # Northeast (Up-Right)
    SW = 6 # Southwest (Down-Left)
    SE = 7 # Southeast (Down-Right)

const OrientationDeltas*: array[8, OrientationDelta] = [
  (x: 0, y: -1),   # N (North)
  (x: 0, y: 1),    # S (South)
  (x: -1, y: 0),   # W (West)
  (x: 1, y: 0),    # E (East)
  (x: -1, y: -1),  # NW (Northwest)
  (x: 1, y: -1),   # NE (Northeast)
  (x: -1, y: 1),   # SW (Southwest)
  (x: 1, y: 1)     # SE (Southeast)
]

const
  ActionVerbCount* = 10  # Added orient action (verb 9)
  ActionArgumentCount* = 24

proc encodeAction*(verb: uint8, argument: uint8): uint8 =
  (verb.int * ActionArgumentCount + argument.int).uint8

{.push inline.}
proc getOrientationDelta*(orient: Orientation): OrientationDelta =
  OrientationDeltas[ord(orient)]
{.pop.}

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

{.push inline.}
proc ivec2*(x, y: int): IVec2 =
  result.x = x.int32
  result.y = y.int32
{.pop.}
