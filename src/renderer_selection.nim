## renderer_selection.nim - Selection indicators, rally points, and trade routes
##
## Contains: selection glow rendering, rally point rendering and preview,
## trade route visualization with animated flow indicators.

import
  boxy, pixie, vmath, std/math,
  common, environment

import renderer_core

# ─── Selection and Visual Ranges ─────────────────────────────────────────────

proc drawSelection*() =
  ## Draw selection indicators for selected units and buildings.
  if selection.len == 0:
    return
  for thing in selection:
    if thing.isNil:
      continue
    let pos = thing.pos.vec2
    if not isInViewport(thing.pos):
      continue

    # Draw pulsing glow effect (outer ring)
    if "selection" in bxy:
      let glowPulse = sin(frame.float32 * SelectionPulseSpeed) * SelectionPulseAmplitude + SelectionPulseBase
      let glowColor = color(0.3, 0.7, 1.0, SelectionGlowAlpha * glowPulse)
      bxy.drawImage("selection", pos, angle = 0, scale = SpriteScale * SelectionGlowScale,
                    tint = glowColor)

      # Draw main selection indicator (full opacity)
      bxy.drawImage("selection", pos, angle = 0, scale = SpriteScale)

# ─── Rally Point Rendering ───────────────────────────────────────────────────

const
  RallyPointLineWidth = 0.06'f32    # Width of the path line in world units
  RallyPointLineSegments = 12       # Number of segments in the path line
  RallyPointBeaconScale = 1.0 / 280.0  # Scale for the beacon sprite
  RallyPointPulseSpeed = 0.15'f32   # Speed of the pulsing animation
  RallyPointPulseMin = 0.6'f32      # Minimum alpha during pulse
  RallyPointPulseMax = 1.0'f32      # Maximum alpha during pulse

proc drawRallyPoints*() =
  ## Draw visual indicators for rally points on selected buildings.
  ## Shows an animated beacon at the rally point with a path line to the building.
  if selection.len == 0:
    return

  # Calculate pulsing animation based on frame counter
  let pulse = sin(frame.float32 * RallyPointPulseSpeed) * 0.5 + 0.5
  let pulseAlpha = RallyPointPulseMin + pulse * (RallyPointPulseMax - RallyPointPulseMin)

  for thing in selection:
    if thing.isNil or not isBuildingKind(thing.kind):
      continue
    if not hasRallyPoint(thing):
      continue

    let buildingPos = thing.pos
    let rallyPos = thing.rallyPoint

    # Skip if rally point is at the building itself
    if rallyPos == buildingPos:
      continue

    # Get team color for the rally point indicator
    let teamId = thing.teamId
    let teamColor = getTeamColor(env, teamId, color(0.8, 0.8, 0.8, 1.0))

    # Draw path line from building to rally point using small rectangles
    let startVec = buildingPos.vec2
    let endVec = rallyPos.vec2
    let lineDir = endVec - startVec
    let lineLen = sqrt(lineDir.x * lineDir.x + lineDir.y * lineDir.y)

    if lineLen > 0.1:
      let stepLen = lineLen / RallyPointLineSegments.float32
      let normalizedDir = vec2(lineDir.x / lineLen, lineDir.y / lineLen)

      # Draw dashed line segments
      for i in 0 ..< RallyPointLineSegments:
        # Alternating segments for dashed effect
        if i mod 2 == 0:
          continue

        let segStart = startVec + normalizedDir * (i.float32 * stepLen)
        let segEnd = startVec + normalizedDir * ((i.float32 + 1.0) * stepLen)

        # Check if segment is in viewport (approximate check using midpoint)
        let midpoint = (segStart + segEnd) * 0.5
        if not isInViewport(ivec2(midpoint.x.int, midpoint.y.int)):
          continue

        # Draw segment as a colored rectangle (using floor sprite with team color)
        let segMid = (segStart + segEnd) * 0.5
        let lineColor = color(teamColor.r, teamColor.g, teamColor.b, pulseAlpha * RallyPathAlpha)
        bxy.drawImage("floor", segMid, angle = 0, scale = RallyPointLineWidth * 2,
                      tint = lineColor)

    # Draw the rally point beacon (animated flag/marker)
    if isInViewport(rallyPos):
      # Pulsing scale effect for the beacon
      let beaconScale = RallyPointBeaconScale * (1.0 + pulse * RallyBeaconPulseAmount)

      # Draw outer glow (larger, more transparent)
      let glowColor = color(teamColor.r, teamColor.g, teamColor.b, pulseAlpha * RallyGlowAlpha)
      bxy.drawImage("floor", rallyPos.vec2, angle = 0, scale = beaconScale * RallyGlowScaleMult,
                    tint = glowColor)

      # Draw main beacon (use lantern sprite if available, otherwise floor)
      let beaconColor = color(teamColor.r, teamColor.g, teamColor.b, pulseAlpha)
      if "lantern" in bxy:
        bxy.drawImage("lantern", rallyPos.vec2, angle = 0, scale = SpriteScale * RallyBeaconSpriteScale,
                      tint = beaconColor)
      else:
        # Fallback: draw a colored circle using floor sprite
        bxy.drawImage("floor", rallyPos.vec2, angle = 0, scale = beaconScale * RallyBeaconFallbackScale,
                      tint = beaconColor)

      # Draw inner bright core
      let coreColor = color(1.0, 1.0, 1.0, pulseAlpha * RallyCoreAlpha)
      bxy.drawImage("floor", rallyPos.vec2, angle = 0, scale = beaconScale * RallyCoreScale,
                    tint = coreColor)

proc drawRallyPointPreview*(buildingPos: Vec2, mousePos: Vec2) =
  ## Draw a preview of where the rally point will be set.
  ## Shows a dashed line from building to mouse position and a beacon at mouse.
  let pulse = sin(frame.float32 * RallyPointPulseSpeed) * 0.5 + 0.5
  let pulseAlpha = RallyPointPulseMin + pulse * (RallyPointPulseMax - RallyPointPulseMin)

  # Get team color for the preview (use green for valid placement)
  let previewColor = color(0.3, 1.0, 0.3, pulseAlpha * 0.8)

  # Draw path line from building to mouse position
  let lineDir = mousePos - buildingPos
  let lineLen = sqrt(lineDir.x * lineDir.x + lineDir.y * lineDir.y)

  if lineLen > 0.5:
    let normalizedDir = vec2(lineDir.x / lineLen, lineDir.y / lineLen)
    let stepLen = lineLen / RallyPointLineSegments.float32

    # Draw dashed line segments
    for i in 0 ..< RallyPointLineSegments:
      if i mod 2 == 0:
        continue
      let segStart = buildingPos + normalizedDir * (i.float32 * stepLen)
      let segMid = segStart + normalizedDir * (stepLen * 0.5)
      if isInViewport(ivec2(segMid.x.int, segMid.y.int)):
        let lineColor = color(previewColor.r, previewColor.g, previewColor.b, pulseAlpha * RallyPreviewPathAlpha)
        bxy.drawImage("floor", segMid, angle = 0, scale = RallyPointLineWidth * 2,
                      tint = lineColor)

  # Draw the rally point preview beacon at mouse position
  let mouseGrid = ivec2(mousePos.x.int, mousePos.y.int)
  if isInViewport(mouseGrid):
    let beaconScale = RallyPointBeaconScale * (1.0 + pulse * RallyPreviewPulseAmount)

    # Draw outer glow
    let glowColor = color(previewColor.r, previewColor.g, previewColor.b, pulseAlpha * RallyPreviewGlowAlpha)
    bxy.drawImage("floor", mousePos, angle = 0, scale = beaconScale * RallyPreviewGlowScale,
                  tint = glowColor)

    # Draw main beacon
    if "lantern" in bxy:
      bxy.drawImage("lantern", mousePos, angle = 0, scale = SpriteScale * RallyPreviewSpriteScale,
                    tint = previewColor)
    else:
      bxy.drawImage("floor", mousePos, angle = 0, scale = beaconScale * RallyPreviewFallbackScale,
                    tint = previewColor)

    # Draw inner bright core
    let coreColor = color(1.0, 1.0, 1.0, pulseAlpha * RallyPreviewCoreAlpha)
    bxy.drawImage("floor", mousePos, angle = 0, scale = beaconScale * RallyPreviewCoreScale,
                  tint = coreColor)

# ─── Trade Routes ────────────────────────────────────────────────────────────

const
  TradeRouteLineWidth = 0.08'f32       # World-space line width
  TradeRouteGoldColor = color(0.95, 0.78, 0.15, 0.7)  # Gold color for route lines
  TradeRouteFlowDotCount = 5           # Number of animated dots per route segment
  TradeRouteFlowSpeed = 0.015'f32      # Animation speed (fraction per frame)

var
  tradeRouteAnimationPhase: float32 = 0.0  # Global animation phase for flow indicators

proc drawLineWorldSpace(p1, p2: Vec2, lineColor: Color, width: float32 = TradeRouteLineWidth) =
  ## Draw a line between two world-space points using floor sprites along the path.
  let dx = p2.x - p1.x
  let dy = p2.y - p1.y
  let length = sqrt(dx * dx + dy * dy)
  if length < 0.001:
    return

  # Draw line as a series of small floor sprites along the path
  let segments = max(1, int(length / 0.5))
  for i in 0 ..< segments:
    let t0 = i.float32 / segments.float32
    let t1 = (i + 1).float32 / segments.float32
    let x0 = p1.x + dx * t0
    let y0 = p1.y + dy * t0
    let x1 = p1.x + dx * t1
    let y1 = p1.y + dy * t1
    let midX = (x0 + x1) * 0.5
    let midY = (y0 + y1) * 0.5
    let segLen = length / segments.float32
    # Use floor sprite scaled down as line segment
    bxy.drawImage("floor", vec2(midX, midY), angle = 0,
                  scale = max(segLen, width) / 200.0, tint = lineColor)

proc drawTradeRoutes*() =
  ## Draw trade route visualization showing paths between docks with gold flow indicators.
  ## Trade cogs travel between friendly docks generating gold - visualize their routes.
  if not currentViewport.valid:
    return

  # Update animation phase
  tradeRouteAnimationPhase += TradeRouteFlowSpeed
  if tradeRouteAnimationPhase >= 1.0:
    tradeRouteAnimationPhase -= 1.0

  # Collect active trade routes by team
  # A trade route exists when a trade cog has a valid home dock
  type TradeRoute = object
    tradeCogPos: Vec2
    homeDockPos: Vec2
    targetDockPos: Vec2
    teamId: int
    hasTarget: bool

  var activeRoutes: seq[TradeRoute] = @[]

  # Find all active trade cogs and their routes
  for agent in env.agents:
    if not isAgentAlive(env, agent):
      continue
    if agent.unitClass != UnitTradeCog:
      continue

    let teamId = getTeamId(agent)
    let homeDockPos = agent.tradeHomeDock

    # Check if trade cog has a valid home dock
    if not isValidPos(homeDockPos):
      continue

    # Find target dock (nearest friendly dock that isn't home dock)
    var targetDock: Thing = nil
    var targetDist = int.high
    for dock in env.thingsByKind[Dock]:
      if dock.teamId != teamId:
        continue
      if dock.pos == homeDockPos:
        continue
      let dist = abs(dock.pos.x - agent.pos.x) + abs(dock.pos.y - agent.pos.y)
      if dist < targetDist:
        targetDist = dist
        targetDock = dock

    var route: TradeRoute
    route.tradeCogPos = agent.pos.vec2
    route.homeDockPos = homeDockPos.vec2
    route.teamId = teamId
    route.hasTarget = not isNil(targetDock)
    if route.hasTarget:
      route.targetDockPos = targetDock.pos.vec2

    activeRoutes.add(route)

  if activeRoutes.len == 0:
    return

  # Draw route lines and flow indicators
  for route in activeRoutes:
    let teamColor = getTeamColor(env, route.teamId)
    # Blend team color with gold for route visualization
    let routeColor = color(
      (teamColor.r * 0.3 + TradeRouteGoldColor.r * 0.7),
      (teamColor.g * 0.3 + TradeRouteGoldColor.g * 0.7),
      (teamColor.b * 0.3 + TradeRouteGoldColor.b * 0.7),
      TradeRouteGoldColor.a
    )

    # Draw dashed line from home dock to trade cog
    let p1 = route.homeDockPos
    let p2 = route.tradeCogPos
    let dx1 = p2.x - p1.x
    let dy1 = p2.y - p1.y
    let len1 = sqrt(dx1 * dx1 + dy1 * dy1)

    if len1 > 0.5:
      # Check if either endpoint is in viewport (with margin for long routes)
      let inView1 = isInViewport(ivec2(p1.x.int, p1.y.int)) or isInViewport(ivec2(p2.x.int, p2.y.int))
      if inView1:
        # Draw the route line
        drawLineWorldSpace(p1, p2, routeColor)

        # Draw animated gold flow dots (moving from dock toward trade cog)
        for i in 0 ..< TradeRouteFlowDotCount:
          let baseT = i.float32 / TradeRouteFlowDotCount.float32
          let t = (baseT + tradeRouteAnimationPhase) mod 1.0
          let dotX = p1.x + dx1 * t
          let dotY = p1.y + dy1 * t
          let dotPos = vec2(dotX, dotY)
          if isInViewport(ivec2(dotPos.x.int, dotPos.y.int)):
            # Pulsing brightness based on position
            let brightness = 0.7 + 0.3 * sin(t * 3.14159)
            let dotColor = color(
              min(routeColor.r * brightness + 0.2, 1.0),
              min(routeColor.g * brightness + 0.1, 1.0),
              min(routeColor.b * brightness, 1.0),
              0.9
            )
            bxy.drawImage("floor", dotPos, angle = 0, scale = TradeRouteDotScale, tint = dotColor)

    # Draw line from trade cog to target dock (if exists)
    if route.hasTarget:
      let p3 = route.targetDockPos
      let dx2 = p3.x - p2.x
      let dy2 = p3.y - p2.y
      let len2 = sqrt(dx2 * dx2 + dy2 * dy2)

      if len2 > 0.5:
        let inView2 = isInViewport(ivec2(p2.x.int, p2.y.int)) or isInViewport(ivec2(p3.x.int, p3.y.int))
        if inView2:
          # Draw lighter line to target (trade cog hasn't been there yet)
          let targetColor = color(routeColor.r, routeColor.g, routeColor.b, routeColor.a * 0.5)
          drawLineWorldSpace(p2, p3, targetColor)

  # Draw dock markers for docks with active trade routes
  var drawnDocks: seq[IVec2] = @[]
  for route in activeRoutes:
    let homeDock = ivec2(route.homeDockPos.x.int, route.homeDockPos.y.int)
    if isInViewport(homeDock) and homeDock notin drawnDocks:
      drawnDocks.add(homeDock)
      # Draw a gold coin indicator at the dock
      bxy.drawImage("floor", vec2(homeDock.x.float32, homeDock.y.float32) + vec2(0.0, -0.4), angle = 0,
                    scale = DockMarkerScale, tint = TradeRouteGoldColor)

    if route.hasTarget:
      let targetDock = ivec2(route.targetDockPos.x.int, route.targetDockPos.y.int)
      if isInViewport(targetDock) and targetDock notin drawnDocks:
        drawnDocks.add(targetDock)
        # Draw a smaller gold indicator at target dock
        bxy.drawImage("floor", vec2(targetDock.x.float32, targetDock.y.float32) + vec2(0.0, -0.4), angle = 0,
                      scale = OverlayIconScale, tint = color(TradeRouteGoldColor.r,
                                                   TradeRouteGoldColor.g,
                                                   TradeRouteGoldColor.b, 0.5))
