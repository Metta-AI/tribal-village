import std/[os, strutils, math],
  boxy, windy, vmath, pixie,
  src/environment, src/common, src/renderer, src/agent_control, src/tileset,
  src/minimap, src/command_panel, src/tooltips

when compileOption("profiler"):
  import std/nimprof

when defined(renderTiming):
  import std/monotimes

# Initialize the global environment for the renderer/game loop.
env = newEnvironment()

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
var dragStartWorld: Vec2 = vec2(0, 0)
var isDragging: bool = false

# Player control state for right-click commands
# playerTeam: -1 = observer mode (no commands), 0-7 = controlling that team
var playerTeam*: int = 0

# Gatherable resource kinds for right-click gather command
const GatherableResourceKinds* = {Tree, Wheat, Fish, Stone, Gold, Bush, Cactus}

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

  # AI takeover toggle: Tab cycles Observer -> Team 0-7 -> Observer
  if window.buttonPressed[KeyTab]:
    playerTeam = (playerTeam + 2) mod (MapRoomObjectsTeams + 1) - 1
    # Cycles: -1 -> 0 -> 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> -1

  # F1-F8 to switch team shown in resource bar
  if window.buttonPressed[KeyF1]: playerTeam = 0
  if window.buttonPressed[KeyF2]: playerTeam = 1
  if window.buttonPressed[KeyF3]: playerTeam = 2
  if window.buttonPressed[KeyF4]: playerTeam = 3
  if window.buttonPressed[KeyF5]: playerTeam = 4
  if window.buttonPressed[KeyF6]: playerTeam = 5
  if window.buttonPressed[KeyF7]: playerTeam = 6
  if window.buttonPressed[KeyF8]: playerTeam = 7

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
  let panelRect = Rect(
    x: panelRectInt.x.float32,
    y: panelRectInt.y.float32,
    w: panelRectInt.w.float32,
    h: panelRectInt.h.float32
  )

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

  let onMinimap = isInMinimap(panelRectInt, window.mousePos.vec2)
  let onCommandPanel = isInCommandPanel(panelRectInt, window.mousePos.vec2)
  worldMapPanel.hasMouse = worldMapPanel.visible and not onMinimap and not onCommandPanel and not minimapCaptured and
    ((not mouseCaptured and insideRect) or
    (mouseCaptured and mouseCapturedPanel == worldMapPanel))

  if worldMapPanel.hasMouse and window.buttonPressed[MouseLeft]:
    mouseCaptured = true
    mouseCapturedPanel = worldMapPanel
    mouseDownPos = logicalMousePos(window)

  if worldMapPanel.hasMouse:
    if (window.buttonDown[MouseLeft] and not isDragging) or window.buttonDown[MouseMiddle]:
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

  # Update viewport bounds for culling (before any rendering)
  updateViewport(worldMapPanel, panelRectInt, MapWidth, MapHeight, scaleF)

  let footerRect = Rect(
    x: panelRect.x,
    y: panelRect.y + panelRect.h - FooterHeight.float32,
    w: panelRect.w,
    h: FooterHeight.float32
  )
  let mousePosPx = window.mousePos.vec2
  var blockSelection = uiMouseCaptured or minimapCaptured
  var clearUiCapture = false

  # Minimap click-to-pan: check if mouse pressed on minimap
  if window.buttonPressed[MouseLeft] and isInMinimap(panelRectInt, mousePosPx):
    minimapCaptured = true
    blockSelection = true
    # Pan camera to clicked world position
    let worldPos = minimapToWorld(panelRectInt, mousePosPx)
    let scaleF = window.contentScale.float32
    let rectW = panelRect.w / scaleF
    let rectH = panelRect.h / scaleF
    worldMapPanel.pos = vec2(
      rectW / 2.0'f32 - worldPos.x * zoomScale,
      rectH / 2.0'f32 - worldPos.y * zoomScale
    )
    worldMapPanel.vel = vec2(0, 0)

  # Minimap drag-to-pan: continue panning while dragging on minimap
  if minimapCaptured and window.buttonDown[MouseLeft]:
    blockSelection = true
    if isInMinimap(panelRectInt, mousePosPx):
      let worldPos = minimapToWorld(panelRectInt, mousePosPx)
      let scaleF = window.contentScale.float32
      let rectW = panelRect.w / scaleF
      let rectH = panelRect.h / scaleF
      worldMapPanel.pos = vec2(
        rectW / 2.0'f32 - worldPos.x * zoomScale,
        rectH / 2.0'f32 - worldPos.y * zoomScale
      )
      worldMapPanel.vel = vec2(0, 0)

  if minimapCaptured and window.buttonReleased[MouseLeft]:
    minimapCaptured = false

  # Command panel click handling
  if window.buttonPressed[MouseLeft] and isInCommandPanel(panelRectInt, mousePosPx):
    blockSelection = true
    let clickedCmd = handleCommandPanelClick(panelRectInt, mousePosPx)
    # Process the clicked command
    case clickedCmd
    of CmdBuild:
      buildMenuOpen = true
    of CmdBuildBack:
      buildMenuOpen = false
      buildingPlacementMode = false
    of CmdBuildHouse, CmdBuildMill, CmdBuildLumberCamp, CmdBuildMiningCamp,
       CmdBuildBarracks, CmdBuildArcheryRange, CmdBuildStable, CmdBuildWall,
       CmdBuildBlacksmith, CmdBuildMarket:
      buildingPlacementMode = true
      buildingPlacementKind = commandKindToBuildingKind(clickedCmd)
    of CmdStop:
      for sel in selection:
        if not isNil(sel) and sel.kind == Agent:
          stopAgent(sel.agentId)
    of CmdFormationLine, CmdFormationBox, CmdFormationStaggered:
      # Find which control group the selection belongs to
      # or create a new control group from the selection
      var targetGroup = -1
      if selection.len > 0 and not isNil(selection[0]) and selection[0].kind == Agent:
        targetGroup = findAgentControlGroup(selection[0].agentId)
      if targetGroup < 0 and selection.len > 1:
        # No existing group - assign selection to first empty group
        for g in 0 ..< ControlGroupCount:
          if controlGroups[g].len == 0:
            controlGroups[g] = selection
            targetGroup = g
            break
        # If no empty group, use group 0
        if targetGroup < 0:
          controlGroups[0] = selection
          targetGroup = 0
      if targetGroup >= 0:
        let ftype = case clickedCmd
          of CmdFormationLine: FormationLine
          of CmdFormationBox: FormationBox
          of CmdFormationStaggered: FormationStaggered
          else: FormationNone
        setFormation(targetGroup, ftype)
    else:
      discard

  if window.buttonPressed[MouseLeft] and not minimapCaptured and
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
        of FooterFaster:
          playSpeed = FasterPlaySpeed
          play = true
          lastSimTime = nowSeconds()
        of FooterSuper:
          playSpeed = SuperPlaySpeed
          play = true
          lastSimTime = nowSeconds()
        break
    clearUiCapture = true
    blockSelection = true

  if not blockSelection:
    if window.buttonPressed[MouseLeft]:
      mouseDownPos = logicalMousePos(window)
      dragStartWorld = bxy.getTransform().inverse * window.mousePos.vec2
      isDragging = false

    if window.buttonDown[MouseLeft] and not window.buttonPressed[MouseLeft]:
      let dragDist = (logicalMousePos(window) - mouseDownPos).length
      if dragDist > 5.0:
        isDragging = true

    if window.buttonReleased[MouseLeft]:
      if isDragging:
        # Drag-box multi-select: find all agents within the rectangle
        let dragEndWorld = bxy.getTransform().inverse * window.mousePos.vec2
        let minX = min(dragStartWorld.x, dragEndWorld.x)
        let maxX = max(dragStartWorld.x, dragEndWorld.x)
        let minY = min(dragStartWorld.y, dragEndWorld.y)
        let maxY = max(dragStartWorld.y, dragEndWorld.y)
        var boxSelection: seq[Thing] = @[]
        for agent in env.thingsByKind[Agent]:
          if not isNil(agent) and isValidPos(agent.pos) and
             env.isAgentAlive(agent):
            # Filter by player team when in player control mode
            if playerTeam >= 0 and agent.getTeamId() != playerTeam:
              continue
            let ax = agent.pos.x.float32
            let ay = agent.pos.y.float32
            if ax >= minX and ax <= maxX and ay >= minY and ay <= maxY:
              boxSelection.add(agent)
        if boxSelection.len > 0:
          selection = boxSelection
          selectedPos = boxSelection[0].pos
        else:
          selection = @[]
        isDragging = false
      else:
        # Click select (existing behavior)
        selection = @[]
        let
          mousePos = bxy.getTransform().inverse * window.mousePos.vec2
          gridPos = (mousePos + vec2(0.5, 0.5)).ivec2
        if gridPos.x >= 0 and gridPos.x < MapWidth and
           gridPos.y >= 0 and gridPos.y < MapHeight:
          selectedPos = gridPos
          let thing = env.grid[gridPos.x][gridPos.y]
          if not isNil(thing):
            if window.buttonDown[KeyLeftShift] or window.buttonDown[KeyRightShift]:
              # Shift-click: toggle unit in selection
              var found = false
              for i, s in selection:
                if s == thing:
                  selection.delete(i)
                  found = true
                  break
              if not found:
                selection.add(thing)
            else:
              selection = @[thing]

    # Right-click command handling (AoE2-style)
    if window.buttonPressed[MouseRight] and selection.len > 0 and playerTeam >= 0:
      let
        mousePos = bxy.getTransform().inverse * window.mousePos.vec2
        gridPos = (mousePos + vec2(0.5, 0.5)).ivec2
      if gridPos.x >= 0 and gridPos.x < MapWidth and
         gridPos.y >= 0 and gridPos.y < MapHeight:
        let shiftDown = window.buttonDown[KeyLeftShift] or window.buttonDown[KeyRightShift]
        let targetThing = env.grid[gridPos.x][gridPos.y]
        let bgThing = env.backgroundGrid[gridPos.x][gridPos.y]

        # Determine command type based on target
        # Check if there's something at the target position
        if not isNil(targetThing):
          if targetThing.kind == Agent:
            # Right-click on agent
            let targetTeam = getTeamId(targetThing)
            if targetTeam != playerTeam:
              # Enemy agent: attack-move to target
              for sel in selection:
                if not isNil(sel) and sel.kind == Agent and env.isAgentAlive(sel):
                  if shiftDown:
                    # Shift+right-click: queue patrol waypoint
                    setAgentPatrol(sel.agentId, sel.pos, gridPos)
                  else:
                    setAgentAttackMoveTarget(sel.agentId, gridPos)
            else:
              # Friendly agent: follow (using attack-move for now, could be follow command)
              for sel in selection:
                if not isNil(sel) and sel.kind == Agent and env.isAgentAlive(sel):
                  if shiftDown:
                    setAgentPatrol(sel.agentId, sel.pos, gridPos)
                  else:
                    setAgentFollowTarget(sel.agentId, targetThing.agentId)
          elif targetThing.kind in GatherableResourceKinds:
            # Resource: gather command (attack-move for villagers)
            for sel in selection:
              if not isNil(sel) and sel.kind == Agent and env.isAgentAlive(sel):
                if shiftDown:
                  setAgentPatrol(sel.agentId, sel.pos, gridPos)
                else:
                  setAgentAttackMoveTarget(sel.agentId, gridPos)
          elif isBuildingKind(targetThing.kind):
            # Building: check if friendly or enemy
            if targetThing.teamId == playerTeam:
              # Friendly building: garrison/dropoff (attack-move to building)
              for sel in selection:
                if not isNil(sel) and sel.kind == Agent and env.isAgentAlive(sel):
                  if shiftDown:
                    setAgentPatrol(sel.agentId, sel.pos, gridPos)
                  else:
                    setAgentAttackMoveTarget(sel.agentId, gridPos)
            else:
              # Enemy building: attack-move
              for sel in selection:
                if not isNil(sel) and sel.kind == Agent and env.isAgentAlive(sel):
                  if shiftDown:
                    setAgentPatrol(sel.agentId, sel.pos, gridPos)
                  else:
                    setAgentAttackMoveTarget(sel.agentId, gridPos)
          else:
            # Other things (Tumor, Spawner, etc.): attack-move
            for sel in selection:
              if not isNil(sel) and sel.kind == Agent and env.isAgentAlive(sel):
                if shiftDown:
                  setAgentPatrol(sel.agentId, sel.pos, gridPos)
                else:
                  setAgentAttackMoveTarget(sel.agentId, gridPos)
        elif not isNil(bgThing) and bgThing.kind in GatherableResourceKinds:
          # Background thing is a gatherable resource (like Fish)
          for sel in selection:
            if not isNil(sel) and sel.kind == Agent and env.isAgentAlive(sel):
              if shiftDown:
                setAgentPatrol(sel.agentId, sel.pos, gridPos)
              else:
                setAgentAttackMoveTarget(sel.agentId, gridPos)
        else:
          # Empty tile: move command
          for sel in selection:
            if not isNil(sel) and sel.kind == Agent and env.isAgentAlive(sel):
              if shiftDown:
                # Shift+right-click: queue patrol waypoint
                setAgentPatrol(sel.agentId, sel.pos, gridPos)
              else:
                setAgentAttackMoveTarget(sel.agentId, gridPos)

  # Control group handling (AoE2-style: Ctrl+N assigns, N recalls, double-tap centers)
  let ctrlDown = window.buttonDown[KeyLeftControl] or window.buttonDown[KeyRightControl]
  const numberKeys = [Key0, Key1, Key2, Key3, Key4, Key5, Key6, Key7, Key8, Key9]
  let groupNow = nowSeconds()
  const doubleTapThreshold = 0.3  # seconds

  for i in 0 ..< ControlGroupCount:
    if window.buttonPressed[numberKeys[i]]:
      if ctrlDown:
        # Ctrl+N: assign current selection to group N
        controlGroups[i] = selection
      else:
        # N: recall group N
        # Filter out dead/nil units before recalling
        var alive: seq[Thing] = @[]
        for thing in controlGroups[i]:
          if not isNil(thing) and thing.kind == Agent and
             env.isAgentAlive(thing):
            alive.add(thing)
        controlGroups[i] = alive

        if alive.len > 0:
          # Double-tap detection: center camera on group
          if lastGroupKeyIndex == i and (groupNow - lastGroupKeyTime[i]) < doubleTapThreshold:
            # Double-tap: center camera on group centroid
            var cx, cy: float32 = 0
            for thing in alive:
              cx += thing.pos.x.float32
              cy += thing.pos.y.float32
            cx /= alive.len.float32
            cy /= alive.len.float32
            let scaleF = window.contentScale.float32
            let rectW = panelRect.w / scaleF
            let rectH = panelRect.h / scaleF
            let zoomScale = worldMapPanel.zoom * worldMapPanel.zoom
            worldMapPanel.pos = vec2(
              rectW / 2.0'f32 - cx * zoomScale,
              rectH / 2.0'f32 - cy * zoomScale
            )
            worldMapPanel.vel = vec2(0, 0)
          else:
            # Single tap: select the group
            selection = alive
            if alive.len > 0:
              selectedPos = alive[0].pos

          lastGroupKeyTime[i] = groupNow
          lastGroupKeyIndex = i

  # Escape key: cancel building placement mode or close build menu
  if window.buttonPressed[KeyEscape]:
    if buildingPlacementMode:
      buildingPlacementMode = false
    elif buildMenuOpen:
      buildMenuOpen = false

  # Command panel hotkeys (when not in building placement mode)
  if not buildingPlacementMode and selection.len > 0 and playerTeam >= 0:
    let isVillagerSelected = selection.len == 1 and selection[0].kind == Agent and
                             selection[0].unitClass == UnitVillager
    if isVillagerSelected:
      if buildMenuOpen:
        # Build submenu hotkeys
        if window.buttonPressed[KeyQ]:
          buildingPlacementMode = true
          buildingPlacementKind = House
        elif window.buttonPressed[KeyW]:
          buildingPlacementMode = true
          buildingPlacementKind = Mill
        elif window.buttonPressed[KeyE]:
          buildingPlacementMode = true
          buildingPlacementKind = LumberCamp
        elif window.buttonPressed[KeyR]:
          buildingPlacementMode = true
          buildingPlacementKind = MiningCamp
        elif window.buttonPressed[KeyA]:
          buildingPlacementMode = true
          buildingPlacementKind = Barracks
        elif window.buttonPressed[KeyS]:
          buildingPlacementMode = true
          buildingPlacementKind = ArcheryRange
        elif window.buttonPressed[KeyD]:
          buildingPlacementMode = true
          buildingPlacementKind = Stable
        elif window.buttonPressed[KeyF]:
          buildingPlacementMode = true
          buildingPlacementKind = Wall
        elif window.buttonPressed[KeyZ]:
          buildingPlacementMode = true
          buildingPlacementKind = Blacksmith
        elif window.buttonPressed[KeyX]:
          buildingPlacementMode = true
          buildingPlacementKind = Market
      else:
        # Main command hotkeys for villager
        if window.buttonPressed[KeyB]:
          buildMenuOpen = true
        elif window.buttonPressed[KeyS]:
          for sel in selection:
            if not isNil(sel) and sel.kind == Agent:
              stopAgent(sel.agentId)
    else:
      # Non-villager unit hotkeys
      if window.buttonPressed[KeyS]:
        for sel in selection:
          if not isNil(sel) and sel.kind == Agent:
            stopAgent(sel.agentId)
      # Formation hotkeys (L=Line, O=Box, T=Staggered)
      elif window.buttonPressed[KeyL] or window.buttonPressed[KeyO] or window.buttonPressed[KeyT]:
        var targetGroup = -1
        if selection.len > 0 and not isNil(selection[0]) and selection[0].kind == Agent:
          targetGroup = findAgentControlGroup(selection[0].agentId)
        if targetGroup < 0 and selection.len > 1:
          # No existing group - assign selection to first empty group
          for g in 0 ..< ControlGroupCount:
            if controlGroups[g].len == 0:
              controlGroups[g] = selection
              targetGroup = g
              break
          if targetGroup < 0:
            controlGroups[0] = selection
            targetGroup = 0
        if targetGroup >= 0:
          let ftype = if window.buttonPressed[KeyL]: FormationLine
                      elif window.buttonPressed[KeyO]: FormationBox
                      else: FormationStaggered
          setFormation(targetGroup, ftype)

  # Building placement click handling
  if buildingPlacementMode and window.buttonPressed[MouseLeft] and not blockSelection:
    let mousePos = bxy.getTransform().inverse * window.mousePos.vec2
    let gridPos = (mousePos + vec2(0.5, 0.5)).ivec2
    if canPlaceBuildingAt(gridPos, buildingPlacementKind) and playerTeam >= 0:
      # Place the building (using a villager if available)
      for sel in selection:
        if not isNil(sel) and sel.kind == Agent and sel.unitClass == UnitVillager:
          # Set the villager to build at this location
          setAgentAttackMoveTarget(sel.agentId, gridPos)
          break
      # Exit placement mode (unless shift is held for multiple placements)
      if not (window.buttonDown[KeyLeftShift] or window.buttonDown[KeyRightShift]):
        buildingPlacementMode = false
        buildMenuOpen = false
    blockSelection = true

  if selection.len > 0 and selection[0].kind == Agent:
    let agent = selection[0]

    template overrideAndStep(action: uint8) =
      actionsArray = getActions(env)
      for sel in selection:
        if not isNil(sel) and sel.kind == Agent:
          actionsArray[sel.agentId] = action
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
  else:
    # Camera panning with WASD/arrow keys (when no agent selected)
    const CameraPanSpeed = 12.0'f32  # Pan speed in pixels per frame
    var panVel = vec2(0, 0)
    # W/Up: pan camera up (see content above)
    if window.buttonDown[KeyW] or window.buttonDown[KeyUp]:
      panVel.y += CameraPanSpeed
    # S/Down: pan camera down (see content below)
    if window.buttonDown[KeyS] or window.buttonDown[KeyDown]:
      panVel.y -= CameraPanSpeed
    # A/Left: pan camera left (see content to the left)
    if window.buttonDown[KeyA] or window.buttonDown[KeyLeft]:
      panVel.x += CameraPanSpeed
    # D/Right: pan camera right (see content to the right)
    if window.buttonDown[KeyD] or window.buttonDown[KeyRight]:
      panVel.x -= CameraPanSpeed
    if panVel.x != 0 or panVel.y != 0:
      worldMapPanel.vel = panVel

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
  drawProjectiles()
  drawDamageNumbers()
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
  drawRallyPoints()

  # Draw building ghost preview if in placement mode
  if buildingPlacementMode:
    let mousePos = bxy.getTransform().inverse * window.mousePos.vec2
    drawBuildingGhost(mousePos)

  # Draw drag-box selection rectangle
  if isDragging and window.buttonDown[MouseLeft]:
    let dragEndWorld = bxy.getTransform().inverse * window.mousePos.vec2
    let minX = min(dragStartWorld.x, dragEndWorld.x)
    let maxX = max(dragStartWorld.x, dragEndWorld.x)
    let minY = min(dragStartWorld.y, dragEndWorld.y)
    let maxY = max(dragStartWorld.y, dragEndWorld.y)
    let lineWidth = 0.05'f32  # Thin line in world units
    let dragColor = color(0.2, 0.9, 0.2, 0.8)
    # Top edge
    bxy.drawRect(Rect(x: minX, y: minY, w: maxX - minX, h: lineWidth), dragColor)
    # Bottom edge
    bxy.drawRect(Rect(x: minX, y: maxY - lineWidth, w: maxX - minX, h: lineWidth), dragColor)
    # Left edge
    bxy.drawRect(Rect(x: minX, y: minY, w: lineWidth, h: maxY - minY), dragColor)
    # Right edge
    bxy.drawRect(Rect(x: maxX - lineWidth, y: minY, w: lineWidth, h: maxY - minY), dragColor)

  when defined(renderTiming):
    if timing:
      tNow = getMonoTime()
      tSelectionMs = msBetween(tStart, tNow)
      tStart = tNow

  bxy.restoreTransform()

  bxy.restoreTransform()
  # Draw UI elements
  drawResourceBar(panelRectInt, playerTeam)
  let footerButtons = buildFooterButtons(panelRectInt)
  drawMinimap(panelRectInt, worldMapPanel)
  drawFooter(panelRectInt, footerButtons)
  drawUnitInfoPanel(panelRectInt)
  drawCommandPanel(panelRectInt, mousePosPx)
  # Update and draw tooltips (after command panel so tooltip appears on top)
  updateTooltip()
  drawTooltip(vec2(panelRectInt.w.float32, panelRectInt.h.float32))
  drawSelectionLabel(panelRectInt)
  drawStepLabel(panelRectInt)
  drawControlModeLabel(panelRectInt)
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
var skippedCount = 0
var totalBytes = 0

for path in walkDirRec("data/"):
  if path.startsWith("data/df_view/"):
    continue
  if path.endsWith(".png"):
    try:
      let key = path.replace("data/", "").replace(".png", "")
      let image = readImage(path)
      bxy.addImage(key, image)
      inc loadedCount
      totalBytes += getFileSize(path).int
    except Exception as e:
      echo "⚠️  Skipping ", path, ": ", e.msg
      inc skippedCount

echo "✅ Loaded ", loadedCount, " assets (", totalBytes div 1024 div 1024, " MB)"
if skippedCount > 0:
  echo "⚠️  Skipped ", skippedCount, " files due to errors"

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
