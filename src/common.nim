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
  playSpeed*: float32 = 0.1  # slower default playback
  lastSimTime*: float64 = nowSeconds()

const
  SlowPlaySpeed* = 0.2
  FastPlaySpeed* = 0.02
  FasterPlaySpeed* = 0.005
  SuperPlaySpeed* = 0.001
  FooterHeight* = 64
  ResourceBarHeight* = 32  ## Resource bar HUD at top of viewport

const
  MinimapSize* = 200  ## Minimap width/height in pixels
  MinimapMargin* = 8  ## Margin from edges in pixels

  # Command Panel constants (Phase 3: context-sensitive action buttons)
  CommandPanelWidth* = 240     ## Width in pixels
  CommandPanelMargin* = 8      ## Margin from edges
  CommandButtonSize* = 48      ## Button size in pixels (square)
  CommandButtonGap* = 6        ## Gap between buttons
  CommandButtonCols* = 4       ## Buttons per row
  CommandPanelPadding* = 10    ## Internal padding

var
  mouseCaptured*: bool = false
  mouseCapturedPanel*: Panel = nil
  mouseDownPos*: Vec2 = vec2(0, 0)
  uiMouseCaptured*: bool = false
  minimapCaptured*: bool = false  ## Mouse is currently dragging on minimap
  playerTeam*: int = -1  ## AI takeover: -1 = observer, 0-7 = controlling that team

proc logicalMousePos*(window: Window): Vec2 =
  ## Mouse position in logical coordinates (accounts for HiDPI scaling).
  window.mousePos.vec2 / window.contentScale

type
  Orientation* = enum
    N = 0  # North (Up)
    S = 1  # South (Down) 
    W = 2  # West (Left)
    E = 3  # East (Right)
    NW = 4 # Northwest (Up-Left)
    NE = 5 # Northeast (Up-Right)
    SW = 6 # Southwest (Down-Left)
    SE = 7 # Southeast (Down-Right)

{.push inline.}
proc ivec2*(x, y: int): IVec2 =
  result.x = x.int32
  result.y = y.int32
{.pop.}

const OrientationDeltas*: array[8, IVec2] = [
  ivec2(0, -1),   # N (North)
  ivec2(0, 1),    # S (South)
  ivec2(-1, 0),   # W (West)
  ivec2(1, 0),    # E (East)
  ivec2(-1, -1),  # NW (Northwest)
  ivec2(1, -1),   # NE (Northeast)
  ivec2(-1, 1),   # SW (Southwest)
  ivec2(1, 1)     # SE (Southeast)
]

const
  ActionVerbCount* = 11  # Added set rally point action (verb 10)
  ActionArgumentCount* = 25

  # Action verb indices (used by replay_writer, replay_analyzer, ai_audit)
  ActionNoop* = 0
  ActionMove* = 1
  ActionAttack* = 2
  ActionUse* = 3
  ActionSwap* = 4
  ActionPut* = 5
  ActionPlantLantern* = 6
  ActionPlantResource* = 7
  ActionBuild* = 8
  ActionOrient* = 9
  ActionSetRallyPoint* = 10

  ActionNames*: array[ActionVerbCount, string] = [
    "noop", "move", "attack", "use", "swap", "put",
    "plant_lantern", "plant_resource", "build", "orient", "set_rally_point"
  ]

proc encodeAction*(verb: uint8, argument: uint8): uint8 =
  uint8(verb.int * ActionArgumentCount + argument.int)

{.push inline.}
proc orientationToVec*(orientation: Orientation): IVec2 =
  OrientationDeltas[orientation.int]
{.pop.}

const
  CardinalOffsets* = [
    ivec2(0, -1),
    ivec2(1, 0),
    ivec2(0, 1),
    ivec2(-1, 0)
  ]
  AdjacentOffsets8* = [
    ivec2(0, -1),
    ivec2(1, 0),
    ivec2(0, 1),
    ivec2(-1, 0),
    ivec2(1, -1),
    ivec2(1, 1),
    ivec2(-1, 1),
    ivec2(-1, -1)
  ]
