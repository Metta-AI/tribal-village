import std/[os, strutils, math],
  boxy, windy, vmath, pixie,
  src/environment, src/common, src/renderer, src/external, src/tileset

when compileOption("profiler"):
  import std/nimprof

when defined(renderTiming):
  import std/monotimes

let profileStepsStr = getEnv("TV_PROFILE_STEPS", "")
if profileStepsStr.len > 0:
  let profileSteps = parseInt(profileStepsStr)
  if globalController.isNil:
    let profileExternal = existsEnv("TRIBAL_PYTHON_CONTROL") or existsEnv("TRIBAL_EXTERNAL_CONTROL")
    initGlobalController(if profileExternal: ExternalNN else: BuiltinAI)
  var actionsArray: array[MapAgents, uint8]
  for _ in 0 ..< profileSteps:
    actionsArray = getActions(env)
    env.step(addr actionsArray)
  quit(QuitSuccess)

when defined(renderTiming):
  let renderTimingStartStr = getEnv("TV_RENDER_TIMING", "")
  let renderTimingWindowStr = getEnv("TV_RENDER_TIMING_WINDOW", "0")
  let renderTimingEveryStr = getEnv("TV_RENDER_TIMING_EVERY", "1")
  let renderTimingStart = block:
    if renderTimingStartStr.len == 0:
      -1
    else:
      try:
        parseInt(renderTimingStartStr)
      except ValueError:
        -1
  let renderTimingWindow = block:
    if renderTimingWindowStr.len == 0:
      0
    else:
      try:
        parseInt(renderTimingWindowStr)
      except ValueError:
        0
  let renderTimingEvery = block:
    if renderTimingEveryStr.len == 0:
      1
    else:
      try:
        max(1, parseInt(renderTimingEveryStr))
      except ValueError:
        1
  let renderTimingExitStr = getEnv("TV_RENDER_TIMING_EXIT", "")
  let renderTimingExit = block:
    if renderTimingExitStr.len == 0:
      -1
    else:
      try:
        parseInt(renderTimingExitStr)
      except ValueError:
        -1

  proc msBetween(a, b: MonoTime): float64 =
    (b.ticks - a.ticks).float64 / 1_000_000.0

when not defined(emscripten):
  import opengl

let baseWindowSize = ivec2(1280, 800)
let initialWindowSize = block:
  ## Choose a large window that fits on the primary screen
  when defined(emscripten):
    ivec2(baseWindowSize.x * 2, baseWindowSize.y * 2)
  elif defined(linux):
    # Windy does not expose getScreens on Linux; fall back to a safe default.
    baseWindowSize
  else:
    let screens = getScreens()
    var target = ivec2(baseWindowSize.x * 2, baseWindowSize.y * 2)
    for s in screens:
      if s.primary:
        let sz = s.size()
        target = ivec2(min(target.x, sz.x), min(target.y, sz.y))
        break
    target

window = newWindow("Tribal Village", initialWindowSize)
makeContextCurrent(window)

when not defined(emscripten):
  loadExtensions()

bxy = newBoxy()
rootArea = Area(layout: Horizontal)
worldMapPanel = Panel(panelType: WorldMap, name: "World Map")

rootArea.areas.add(Area(layout: Horizontal))
rootArea.panels.add(worldMapPanel)

let mapCenter = vec2(
  (MapWidth.float32 - 1.0'f32) / 2.0'f32,
  (MapHeight.float32 - 1.0'f32) / 2.0'f32
)

var lastPanelSize = ivec2(0, 0)
var lastContentScale: float32 = 0.0

var actionsArray: array[MapAgents, uint8]

proc display() =
  # Handle mouse capture release
  if window.buttonReleased[MouseLeft]:
    common.mouseCaptured = false
    common.mouseCapturedPanel = nil
  
  if window.buttonPressed[KeySpace]:
    if play:
      play = false
    else:
      lastSimTime = nowSeconds()
      actionsArray = getActions(env)
      env.step(addr actionsArray)
  if window.buttonPressed[KeyMinus] or window.buttonPressed[KeyLeftBracket]:
    playSpeed *= 0.5
    playSpeed = clamp(playSpeed, 0.00001, 60.0)
    play = true
  if window.buttonPressed[KeyEqual] or window.buttonPressed[KeyRightBracket]:
    playSpeed *= 2
    playSpeed = clamp(playSpeed, 0.00001, 60.0)
    play = true

  if window.buttonPressed[KeyN]:
    dec settings.showObservations
  if window.buttonPressed[KeyM]:
    inc settings.showObservations
  settings.showObservations = clamp(settings.showObservations, -1, 23)

  let now = nowSeconds()
  while play and (lastSimTime + playSpeed < now):
    lastSimTime += playSpeed
    actionsArray = getActions(env)
    env.step(addr actionsArray)

  bxy.beginFrame(window.size)

  # Panels fill the window; simple recursive sizing
  rootArea.rect = IRect(x: 0, y: 0, w: window.size.x, h: window.size.y)
  proc updateArea(area: Area) =
    for panel in area.panels:
      panel.rect = area.rect
    for sub in area.areas:
      sub.rect = area.rect
      updateArea(sub)
  updateArea(rootArea)

  let panelRectInt = worldMapPanel.rect
  let panelRect = panelRectInt.rect

  if panelRectInt.w != lastPanelSize.x or
     panelRectInt.h != lastPanelSize.y or
     window.contentScale.float32 != lastContentScale:
    # Centers the map and chooses a zoom that fits the viewport when the window is resized.
    let scaleF = window.contentScale.float32
    let logicalW = panelRectInt.w.float32 / scaleF
    let logicalH = panelRectInt.h.float32 / scaleF
    if logicalW > 0 and logicalH > 0:
      let padding = 1.0'f32  # Zoom in one more notch
      let zoomForW = sqrt(logicalW / MapWidth.float32) * padding
      let zoomForH = sqrt(logicalH / MapHeight.float32) * padding
      let targetZoom = min(zoomForW, zoomForH).clamp(worldMapPanel.minZoom, worldMapPanel.maxZoom)
      worldMapPanel.zoom = targetZoom

      let zoomScale = worldMapPanel.zoom * worldMapPanel.zoom
      worldMapPanel.pos = vec2(
        logicalW / 2.0'f32 - mapCenter.x * zoomScale,
        logicalH / 2.0'f32 - mapCenter.y * zoomScale
      )
      worldMapPanel.vel = vec2(0, 0)
    lastPanelSize = ivec2(panelRectInt.w, panelRectInt.h)
    lastContentScale = window.contentScale.float32

  bxy.pushLayer()
  bxy.saveTransform()
  bxy.translate(vec2(panelRect.x, panelRect.y))

  # Pan and zoom handling
  bxy.saveTransform()

  let scaleVal = window.contentScale
  let logicalRect = Rect(
    x: panelRect.x / scaleVal,
    y: panelRect.y / scaleVal,
    w: panelRect.w / scaleVal,
    h: panelRect.h / scaleVal
  )
  let footerHeightLogical = FooterHeight.float32 / scaleVal
  let footerRectLogical = Rect(
    x: logicalRect.x,
    y: logicalRect.y + logicalRect.h - footerHeightLogical,
    w: logicalRect.w,
    h: footerHeightLogical
  )

  let mousePos = logicalMousePos(window)
  let insideRect = mousePos.x >= logicalRect.x and mousePos.x <= logicalRect.x + logicalRect.w and
    mousePos.y >= logicalRect.y and mousePos.y <= logicalRect.y + logicalRect.h and
    not (mousePos.x >= footerRectLogical.x and mousePos.x <= footerRectLogical.x + footerRectLogical.w and
      mousePos.y >= footerRectLogical.y and mousePos.y <= footerRectLogical.y + footerRectLogical.h)

  worldMapPanel.hasMouse = worldMapPanel.visible and ((not mouseCaptured and insideRect) or
    (mouseCaptured and mouseCapturedPanel == worldMapPanel))

  if worldMapPanel.hasMouse and window.buttonPressed[MouseLeft]:
    mouseCaptured = true
    mouseCapturedPanel = worldMapPanel
    mouseDownPos = logicalMousePos(window)

  if worldMapPanel.hasMouse:
    if window.buttonDown[MouseLeft] or window.buttonDown[MouseMiddle]:
      worldMapPanel.vel = window.mouseDelta.vec2 / window.contentScale
    else:
      worldMapPanel.vel *= 0.9

    worldMapPanel.pos += worldMapPanel.vel

    if window.scrollDelta.y != 0:
      let scaleF = window.contentScale.float32
      let rectOrigin = vec2(panelRect.x / scaleF, panelRect.y / scaleF)
      let localMouse = logicalMousePos(window) - rectOrigin

      let zoomSensitivity = when defined(emscripten): 0.002 else: 0.005
      let oldMat = translate(worldMapPanel.pos) * scale(vec2(worldMapPanel.zoom*worldMapPanel.zoom, worldMapPanel.zoom*worldMapPanel.zoom))
      let oldWorldPoint = oldMat.inverse() * localMouse

      # Scroll direction: wheel down (negative delta) zooms IN; wheel up zooms OUT.
      let zoomFactor64 = pow(1.0 - zoomSensitivity, window.scrollDelta.y.float64)
      let zoomFactor = zoomFactor64.float32
      worldMapPanel.zoom = clamp(worldMapPanel.zoom * zoomFactor, worldMapPanel.minZoom, worldMapPanel.maxZoom)

      let newMat = translate(worldMapPanel.pos) * scale(vec2(worldMapPanel.zoom*worldMapPanel.zoom, worldMapPanel.zoom*worldMapPanel.zoom))
      let newWorldPoint = newMat.inverse() * localMouse
      worldMapPanel.pos += (newWorldPoint - oldWorldPoint) * (worldMapPanel.zoom * worldMapPanel.zoom)

  let zoomScale = worldMapPanel.zoom * worldMapPanel.zoom
  if zoomScale > 0:
    let scaleF = window.contentScale.float32
    let rectW = panelRect.w / scaleF
    let rectH = panelRect.h / scaleF

    if rectW > 0 and rectH > 0:
      let mapMinX = -0.5'f32
      let mapMinY = -0.5'f32
      let mapMaxX = MapWidth.float32 - 0.5'f32
      let mapMaxY = MapHeight.float32 - 0.5'f32
      let mapWidthF = mapMaxX - mapMinX
      let mapHeightF = mapMaxY - mapMinY

      let viewHalfW = rectW / (2.0'f32 * zoomScale)
      let viewHalfH = rectH / (2.0'f32 * zoomScale)

      var cx = (rectW / 2.0'f32 - worldMapPanel.pos.x) / zoomScale
      var cy = (rectH / 2.0'f32 - worldMapPanel.pos.y) / zoomScale

      let minVisiblePixels = min(500.0'f32, min(rectW, rectH) * 0.5'f32)
      let minVisibleWorld = minVisiblePixels / zoomScale
      let maxVisibleUnitsX = min(minVisibleWorld, mapWidthF / 2.0'f32)
      let maxVisibleUnitsY = min(minVisibleWorld, mapHeightF / 2.0'f32)

      let minCenterX = mapMinX + maxVisibleUnitsX - viewHalfW
      let maxCenterX = mapMaxX - maxVisibleUnitsX + viewHalfW
      let minCenterY = mapMinY + maxVisibleUnitsY - viewHalfH
      let maxCenterY = mapMaxY - maxVisibleUnitsY + viewHalfH

      cx = cx.clamp(minCenterX, maxCenterX)
      cy = cy.clamp(minCenterY, maxCenterY)

      worldMapPanel.pos.x = rectW / 2.0'f32 - cx * zoomScale
      worldMapPanel.pos.y = rectH / 2.0'f32 - cy * zoomScale

  let scaleF = window.contentScale.float32
  bxy.translate(worldMapPanel.pos * scaleF)
  let zoomScaled = worldMapPanel.zoom * worldMapPanel.zoom * scaleF
  bxy.scale(vec2(zoomScaled, zoomScaled))

  let footerRect = Rect(
    x: panelRect.x,
    y: panelRect.y + panelRect.h - FooterHeight.float32,
    w: panelRect.w,
    h: FooterHeight.float32
  )
  let mousePosPx = window.mousePos.vec2
  var blockSelection = uiMouseCaptured
  var clearUiCapture = false
  if window.buttonPressed[MouseLeft] and
      mousePosPx.x >= footerRect.x and mousePosPx.x <= footerRect.x + footerRect.w and
      mousePosPx.y >= footerRect.y and mousePosPx.y <= footerRect.y + footerRect.h:
    uiMouseCaptured = true
    blockSelection = true
  if uiMouseCaptured and window.buttonReleased[MouseLeft]:
    let buttons = buildFooterButtons(panelRectInt)
    for button in buttons:
      if mousePosPx.x >= button.rect.x and mousePosPx.x <= button.rect.x + button.rect.w and
          mousePosPx.y >= button.rect.y and mousePosPx.y <= button.rect.y + button.rect.h:
        case button.kind
        of FooterPlayPause:
          if play:
            play = false
          else:
            play = true
            lastSimTime = nowSeconds()
        of FooterStep:
          play = false
          lastSimTime = nowSeconds()
          actionsArray = getActions(env)
          env.step(addr actionsArray)
        of FooterSlow:
          playSpeed = SlowPlaySpeed
          play = true
          lastSimTime = nowSeconds()
        of FooterFast:
          playSpeed = FastPlaySpeed
          play = true
          lastSimTime = nowSeconds()
        of FooterSuper:
          playSpeed = SuperPlaySpeed
          play = true
          lastSimTime = nowSeconds()
        break
    clearUiCapture = true
    blockSelection = true

  useSelections(blockSelection)

  if selection != nil and selection.kind == Agent:
    let agent = selection

    template overrideAndStep(action: uint8) =
      actionsArray = getActions(env)
      actionsArray[agent.agentId] = action
      env.step(addr actionsArray)

    if window.buttonPressed[KeyW] or window.buttonPressed[KeyUp]:
      overrideAndStep(encodeAction(1'u8, Orientation.N.uint8))
    elif window.buttonPressed[KeyS] or window.buttonPressed[KeyDown]:
      overrideAndStep(encodeAction(1'u8, Orientation.S.uint8))
    elif window.buttonPressed[KeyD] or window.buttonPressed[KeyRight]:
      overrideAndStep(encodeAction(1'u8, Orientation.E.uint8))
    elif window.buttonPressed[KeyA] or window.buttonPressed[KeyLeft]:
      overrideAndStep(encodeAction(1'u8, Orientation.W.uint8))
    elif window.buttonPressed[KeyQ]:
      overrideAndStep(encodeAction(1'u8, Orientation.NW.uint8))
    elif window.buttonPressed[KeyE]:
      overrideAndStep(encodeAction(1'u8, Orientation.NE.uint8))
    elif window.buttonPressed[KeyZ]:
      overrideAndStep(encodeAction(1'u8, Orientation.SW.uint8))
    elif window.buttonPressed[KeyC]:
      overrideAndStep(encodeAction(1'u8, Orientation.SE.uint8))

    if window.buttonPressed[KeyU]:
      let useDir = agent.orientation.uint8
      overrideAndStep(encodeAction(3'u8, useDir))

  when defined(renderTiming):
    let timing = renderTimingStart >= 0 and frame >= renderTimingStart and
      frame <= renderTimingStart + renderTimingWindow
    var tStart: MonoTime
    var tNow: MonoTime
    var tRenderStart: MonoTime
    var tFloorMs: float64
    var tTerrainMs: float64
    var tWallsMs: float64
    var tObjectsMs: float64
    var tDecorMs: float64
    var tVisualMs: float64
    var tGridMs: float64
    var tFogMs: float64
    var tSelectionMs: float64
    var tUiMs: float64
    var tMaskMs: float64
    var tEndFrameMs: float64
    var tSwapMs: float64
    if timing:
      tRenderStart = getMonoTime()
      tStart = tRenderStart

  drawFloor()
  when defined(renderTiming):
    if timing:
      tNow = getMonoTime()
      tFloorMs = msBetween(tStart, tNow)
      tStart = tNow

  drawTerrain()
  when defined(renderTiming):
    if timing:
      tNow = getMonoTime()
      tTerrainMs = msBetween(tStart, tNow)
      tStart = tNow

  drawWalls()
  when defined(renderTiming):
    if timing:
      tNow = getMonoTime()
      tWallsMs = msBetween(tStart, tNow)
      tStart = tNow

  drawObjects()
  when defined(renderTiming):
    if timing:
      tNow = getMonoTime()
      tObjectsMs = msBetween(tStart, tNow)
      tStart = tNow

  drawAgentDecorations()
  when defined(renderTiming):
    if timing:
      tNow = getMonoTime()
      tDecorMs = msBetween(tStart, tNow)
      tStart = tNow

  if settings.showVisualRange:
    drawVisualRanges()
  when defined(renderTiming):
    if timing:
      tNow = getMonoTime()
      tVisualMs = msBetween(tStart, tNow)
      tStart = tNow

  if settings.showGrid:
    drawGrid()
  when defined(renderTiming):
    if timing:
      tNow = getMonoTime()
      tGridMs = msBetween(tStart, tNow)
      tStart = tNow

  if settings.showFogOfWar:
    drawVisualRanges(alpha = 1.0)
  when defined(renderTiming):
    if timing:
      tNow = getMonoTime()
      tFogMs = msBetween(tStart, tNow)
      tStart = tNow

  drawSelection()
  when defined(renderTiming):
    if timing:
      tNow = getMonoTime()
      tSelectionMs = msBetween(tStart, tNow)
      tStart = tNow

  bxy.restoreTransform()

  bxy.restoreTransform()
  let footerButtons = buildFooterButtons(panelRectInt)
  drawFooter(panelRectInt, footerButtons)
  drawSelectionLabel(panelRectInt)
  drawStepLabel(panelRectInt)
  if clearUiCapture:
    uiMouseCaptured = false
  when defined(renderTiming):
    if timing:
      tNow = getMonoTime()
      tUiMs = msBetween(tStart, tNow)
      tStart = tNow
  bxy.pushLayer()
  bxy.drawRect(rect = panelRect, color = color(1, 0, 0, 1.0))
  bxy.popLayer(blendMode = MaskBlend)
  bxy.popLayer()
  when defined(renderTiming):
    if timing:
      tNow = getMonoTime()
      tMaskMs = msBetween(tStart, tNow)
      tStart = tNow

  bxy.endFrame()
  when defined(renderTiming):
    if timing:
      tNow = getMonoTime()
      tEndFrameMs = msBetween(tStart, tNow)
      tStart = tNow
  window.swapBuffers()
  when defined(renderTiming):
    if timing:
      tNow = getMonoTime()
      tSwapMs = msBetween(tStart, tNow)
      let shouldLog = (frame - renderTimingStart) mod renderTimingEvery == 0
      if shouldLog:
        let totalMs = msBetween(tRenderStart, tNow)
        echo "frame=", frame,
          " total_ms=", totalMs,
          " floor_ms=", tFloorMs,
          " terrain_ms=", tTerrainMs,
          " walls_ms=", tWallsMs,
          " objects_ms=", tObjectsMs,
          " decor_ms=", tDecorMs,
          " visual_ms=", tVisualMs,
          " grid_ms=", tGridMs,
          " fog_ms=", tFogMs,
          " selection_ms=", tSelectionMs,
          " ui_ms=", tUiMs,
          " mask_ms=", tMaskMs,
          " end_ms=", tEndFrameMs,
          " swap_ms=", tSwapMs,
          " things=", env.things.len,
          " agents=", env.agents.len,
          " tumors=", env.thingsByKind[Tumor].len
  inc frame
  when defined(renderTiming):
    if renderTimingExit >= 0 and frame >= renderTimingExit:
      quit(QuitSuccess)


# Build any missing DF tileset sprites before loading assets.
generateDfViewAssets()

# Build the atlas with progress feedback and error handling.
echo "🎨 Loading tribal assets..."
var loadedCount = 0
var totalFiles = 0

# Count total PNG files first
for path in walkDirRec("data/"):
  if path.startsWith("data/df_view/"):
    continue
  if path.endsWith(".png"):
    inc totalFiles


for path in walkDirRec("data/"):
  if path.startsWith("data/df_view/"):
    continue
  if path.endsWith(".png"):
    inc loadedCount

    try:
      let key = path.replace("data/", "").replace(".png", "")
      bxy.addImage(key, readImage(path))
    except Exception as e:
      echo "⚠️  Skipping ", path, ": ", e.msg

# Check for command line arguments to determine controller type
var useExternalController = false
for i in 1..paramCount():
  let param = paramStr(i)
  if param == "--external-controller":
    useExternalController = true
    # Command line: Requested external controller mode

# Decide controller source.
# Priority: explicit CLI flag --> env vars --> fallback to built-in AI.
let envExternal = existsEnv("TRIBAL_PYTHON_CONTROL") or existsEnv("TRIBAL_EXTERNAL_CONTROL")

if useExternalController:
  initGlobalController(ExternalNN)
elif envExternal:
  initGlobalController(ExternalNN)
elif globalController != nil:
  discard  # keep existing
else:
  initGlobalController(BuiltinAI)

# Check if external controller is active and start playing if so
if globalController != nil and globalController.controllerType == ExternalNN:
  play = true

when defined(emscripten):
  proc main() {.cdecl.} =
    display()
    pollEvents()
  window.run(main)
else:
  while not window.closeRequested:
    display()
    pollEvents()
