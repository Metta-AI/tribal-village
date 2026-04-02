## Selection indicators, rally points, and trade route rendering.

import
  std/math,
  boxy, pixie, vmath,
  common, environment, renderer_core

const
  TradeRouteGoldColor = TradeRouteGoldTint

type
  TradeRoute = object
    tradeCogPos: Vec2
    homeDockPos: Vec2
    targetDockPos: Vec2
    teamId: int
    hasTarget: bool

var
  tradeRouteAnimationPhase = 0.0'f

proc drawDashedRallyPath(
  startPos, endPos: Vec2,
  minLineLength: float32,
  tint: Color
) =
  ## Draw a dashed rally path between two world positions.
  let
    lineDir = endPos - startPos
    lineLen = sqrt(lineDir.x * lineDir.x + lineDir.y * lineDir.y)
  if lineLen <= minLineLength:
    return

  let
    stepLen = lineLen / RallyPointLineSegments.float32
    normalizedDir = vec2(lineDir.x / lineLen, lineDir.y / lineLen)
  for i in 0 ..< RallyPointLineSegments:
    if i mod 2 == 0:
      continue

    let
      segStart = startPos + normalizedDir * (i.float32 * stepLen)
      segMid = segStart + normalizedDir * (stepLen * 0.5'f)
    if not isInViewport(ivec2(segMid.x.int, segMid.y.int)):
      continue

    bxy.drawImage(
      "floor",
      segMid,
      angle = 0,
      scale = RallyPointLineWidth * 2.0'f,
      tint = tint
    )

proc drawRallyBeacon(
  pos: Vec2,
  beaconScale: float32,
  glowTint: Color,
  beaconTint: Color,
  glowScale: float32,
  spriteScale: float32,
  fallbackScale: float32,
  pulseAlpha: float32,
  coreAlpha: float32,
  coreScale: float32
) =
  ## Draw a pulsing rally beacon with glow, sprite, and core layers.
  bxy.drawImage(
    "floor",
    pos,
    angle = 0,
    scale = beaconScale * glowScale,
    tint = glowTint
  )

  if "lantern" in bxy:
    bxy.drawImage(
      "lantern",
      pos,
      angle = 0,
      scale = SpriteScale * spriteScale,
      tint = beaconTint
    )
  else:
    bxy.drawImage(
      "floor",
      pos,
      angle = 0,
      scale = beaconScale * fallbackScale,
      tint = beaconTint
    )

  let coreColor = withAlpha(RallyCoreTint, pulseAlpha * coreAlpha)
  bxy.drawImage(
    "floor",
    pos,
    angle = 0,
    scale = beaconScale * coreScale,
    tint = coreColor
  )

proc drawTradeDockMarker(pos: IVec2, scale: float32, tint: Color) =
  ## Draw a trade-route marker above a dock position.
  bxy.drawImage(
    "floor",
    vec2(pos.x.float32, pos.y.float32) +
      vec2(0.0'f, TradeRouteDockMarkerOffsetY),
    angle = 0,
    scale = scale,
    tint = tint
  )

proc drawSelection*() =
  ## Draw selection indicators for selected units and buildings.
  if selection.len == 0:
    return

  for thing in selection:
    if thing.isNil or not isInViewport(thing.pos):
      continue

    let pos = thing.pos.vec2
    if "selection" in bxy:
      let
        glowPulse =
          sin(frame.float32 * SelectionPulseSpeed) *
          SelectionPulseAmplitude + SelectionPulseBase
        glowColor = withAlpha(UiSelectionGlow, UiSelectionGlow.a * glowPulse)
      bxy.drawImage(
        "selection",
        pos,
        angle = 0,
        scale = SpriteScale * SelectionGlowScale,
        tint = glowColor
      )
      bxy.drawImage("selection", pos, angle = 0, scale = SpriteScale)

    if thing.maxHp > 0:
      let
        hpRatio = thing.hp.float32 / thing.maxHp.float32
        barOffset = vec2(0.0'f, SelectionHealthBarYOffset)
        hpColor = getHealthBarColor(hpRatio)
      drawSegmentBar(
        pos,
        barOffset,
        hpRatio,
        hpColor,
        BarBgColor,
        SelectionHealthBarSegments
      )

proc drawRallyPoints*() =
  ## Draw rally point indicators for selected buildings.
  if selection.len == 0:
    return

  let
    pulse = sin(frame.float32 * RallyPointPulseSpeed) * 0.5'f + 0.5'f
    pulseAlpha =
      RallyPointPulseMin + pulse * (RallyPointPulseMax - RallyPointPulseMin)

  for thing in selection:
    if thing.isNil or not isBuildingKind(thing.kind):
      continue
    if not hasRallyPoint(thing):
      continue

    let
      buildingPos = thing.pos
      rallyPos = thing.rallyPoint
    if rallyPos == buildingPos:
      continue

    let teamColor = getTeamColor(env, thing.teamId, RallyPointFallback)
    drawDashedRallyPath(
      buildingPos.vec2,
      rallyPos.vec2,
      RallyMinLineLength,
      withAlpha(teamColor, pulseAlpha * RallyPathAlpha)
    )

    if isInViewport(rallyPos):
      let beaconScale =
        RallyPointBeaconScale * (1.0'f + pulse * RallyBeaconPulseAmount)
      drawRallyBeacon(
        rallyPos.vec2,
        beaconScale,
        withAlpha(teamColor, pulseAlpha * RallyGlowAlpha),
        withAlpha(teamColor, pulseAlpha),
        RallyGlowScaleMult,
        RallyBeaconSpriteScale,
        RallyBeaconFallbackScale,
        pulseAlpha,
        RallyCoreAlpha,
        RallyCoreScale
      )

proc drawRallyPointPreview*(buildingPos: Vec2, mousePos: Vec2) =
  ## Draw the rally point preview from the building to the mouse.
  let
    pulse = sin(frame.float32 * RallyPointPulseSpeed) * 0.5'f + 0.5'f
    pulseAlpha =
      RallyPointPulseMin + pulse * (RallyPointPulseMax - RallyPointPulseMin)
    previewColor =
      withAlpha(RallyPreviewColor, pulseAlpha * RallyPreviewBaseAlpha)
  drawDashedRallyPath(
    buildingPos,
    mousePos,
    RallyPreviewMinLineLength,
    withAlpha(previewColor, pulseAlpha * RallyPreviewPathAlpha)
  )

  let mouseGrid = ivec2(mousePos.x.int, mousePos.y.int)
  if isInViewport(mouseGrid):
    let beaconScale =
      RallyPointBeaconScale * (1.0'f + pulse * RallyPreviewPulseAmount)
    drawRallyBeacon(
      mousePos,
      beaconScale,
      withAlpha(previewColor, pulseAlpha * RallyPreviewGlowAlpha),
      previewColor,
      RallyPreviewGlowScale,
      RallyPreviewSpriteScale,
      RallyPreviewFallbackScale,
      pulseAlpha,
      RallyPreviewCoreAlpha,
      RallyPreviewCoreScale
    )

proc drawLineWorldSpace(
  p1, p2: Vec2,
  lineColor: Color,
  width: float32 = TradeRouteLineWidth
) =
  ## Draw a world-space line using floor sprites along the path.
  let
    dx = p2.x - p1.x
    dy = p2.y - p1.y
    length = sqrt(dx * dx + dy * dy)
  if length < 0.001'f:
    return

  let segments = max(1, int(length / TradeRouteSegmentSpacing))
  for i in 0 ..< segments:
    let
      t0 = i.float32 / segments.float32
      t1 = (i + 1).float32 / segments.float32
      x0 = p1.x + dx * t0
      y0 = p1.y + dy * t0
      x1 = p1.x + dx * t1
      y1 = p1.y + dy * t1
      midX = (x0 + x1) * 0.5'f
      midY = (y0 + y1) * 0.5'f
      segLen = length / segments.float32
    bxy.drawImage(
      "floor",
      vec2(midX, midY),
      angle = 0,
      scale = max(segLen, width) / TradeRouteLineSegScale,
      tint = lineColor
    )

proc drawTradeRoutes*() =
  ## Draw trade route lines and animated gold flow indicators.
  if not currentViewport.valid:
    return

  tradeRouteAnimationPhase += TradeRouteFlowSpeed
  if tradeRouteAnimationPhase >= 1.0'f:
    tradeRouteAnimationPhase -= 1.0'f

  var activeRoutes: seq[TradeRoute]
  for agent in env.agents:
    if not isAgentAlive(env, agent) or agent.unitClass != UnitTradeCog:
      continue

    let
      teamId = getTeamId(agent)
      homeDockPos = agent.tradeHomeDock
    if not isValidPos(homeDockPos):
      continue

    var
      targetDock: Thing
      targetDist = int.high
    for dock in env.thingsByKind[Dock]:
      if dock.teamId != teamId or dock.pos == homeDockPos:
        continue

      let dist = abs(dock.pos.x - agent.pos.x) + abs(dock.pos.y - agent.pos.y)
      if dist < targetDist:
        targetDist = dist
        targetDock = dock

    var route: TradeRoute
    route.tradeCogPos = agent.pos.vec2
    route.homeDockPos = homeDockPos.vec2
    route.teamId = teamId
    route.hasTarget = not targetDock.isNil
    if route.hasTarget:
      route.targetDockPos = targetDock.pos.vec2
    activeRoutes.add(route)

  if activeRoutes.len == 0:
    return

  for route in activeRoutes:
    let
      teamColor = getTeamColor(env, route.teamId)
      routeColor = color(
        teamColor.r * TradeRouteTeamBlend +
          TradeRouteGoldColor.r * TradeRouteGoldBlend,
        teamColor.g * TradeRouteTeamBlend +
          TradeRouteGoldColor.g * TradeRouteGoldBlend,
        teamColor.b * TradeRouteTeamBlend +
          TradeRouteGoldColor.b * TradeRouteGoldBlend,
        TradeRouteGoldColor.a
      )
      p1 = route.homeDockPos
      p2 = route.tradeCogPos
      dx1 = p2.x - p1.x
      dy1 = p2.y - p1.y
      len1 = sqrt(dx1 * dx1 + dy1 * dy1)

    if len1 > TradeRouteMinLineLength:
      let inView1 =
        isInViewport(ivec2(p1.x.int, p1.y.int)) or
        isInViewport(ivec2(p2.x.int, p2.y.int))
      if inView1:
        drawLineWorldSpace(p1, p2, routeColor)
        for i in 0 ..< TradeRouteFlowDotCount:
          let
            baseT = i.float32 / TradeRouteFlowDotCount.float32
            t = (baseT + tradeRouteAnimationPhase) mod 1.0'f
            dotPos = vec2(p1.x + dx1 * t, p1.y + dy1 * t)
          if isInViewport(ivec2(dotPos.x.int, dotPos.y.int)):
            let
              brightness =
                TradeRouteBrightnessBase +
                TradeRouteBrightnessVar * sin(t * PI)
              dotColor = color(
                min(
                  routeColor.r * brightness + TradeRouteDotColorBoostR,
                  1.0'f
                ),
                min(
                  routeColor.g * brightness + TradeRouteDotColorBoostG,
                  1.0'f
                ),
                min(routeColor.b * brightness, 1.0'f),
                TradeRouteDotAlpha
              )
            bxy.drawImage(
              "floor",
              dotPos,
              angle = 0,
              scale = TradeRouteDotScale,
              tint = dotColor
            )

    if route.hasTarget:
      let
        p3 = route.targetDockPos
        dx2 = p3.x - p2.x
        dy2 = p3.y - p2.y
        len2 = sqrt(dx2 * dx2 + dy2 * dy2)
      if len2 > TradeRouteMinLineLength:
        let inView2 =
          isInViewport(ivec2(p2.x.int, p2.y.int)) or
          isInViewport(ivec2(p3.x.int, p3.y.int))
        if inView2:
          let targetColor =
            withAlpha(routeColor, routeColor.a * TradeRouteTargetAlpha)
          drawLineWorldSpace(p2, p3, targetColor)

  var drawnDocks: seq[IVec2]
  for route in activeRoutes:
    let homeDock = ivec2(route.homeDockPos.x.int, route.homeDockPos.y.int)
    if isInViewport(homeDock) and homeDock notin drawnDocks:
      drawnDocks.add(homeDock)
      drawTradeDockMarker(homeDock, DockMarkerScale, TradeRouteGoldColor)

    if route.hasTarget:
      let targetDock =
        ivec2(route.targetDockPos.x.int, route.targetDockPos.y.int)
      if isInViewport(targetDock) and targetDock notin drawnDocks:
        drawnDocks.add(targetDock)
        drawTradeDockMarker(
          targetDock,
          OverlayIconScale,
          TradeRouteGoldTarget
        )
