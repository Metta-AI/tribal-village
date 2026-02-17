## renderer_ui.nim - UI overlays and HUD rendering
##
## Contains: building construction/UI, footer buttons, selection, rally points,
## minimap, unit info panel, resource bar, trade routes, building ghost preview.

import
  boxy, bumpy, pixie, vmath, tables, std/[math, strutils],
  common, constants, environment, semantic

import renderer_core
from renderer_effects import drawBuildingSmoke

# ─── Building Construction Rendering ─────────────────────────────────────────

proc renderBuildingConstruction*(pos: IVec2, constructionRatio: float32) =
  ## Render construction scaffolding for a building under construction.
  ##
  ## Draws scaffolding posts at the four corners of the building and horizontal
  ## bars connecting them, plus a progress bar showing construction completion.
  ##
  ## Parameters:
  ##   pos: World position of the building
  ##   constructionRatio: Progress from 0.0 (just started) to 1.0 (complete)
  let scaffoldTint = color(0.7, 0.5, 0.2, 0.8)  # Brown/wood color
  let scaffoldScale = ScaffoldingPostScale
  let offsets = [vec2(-0.35, -0.35), vec2(0.35, -0.35),
                 vec2(-0.35, 0.35), vec2(0.35, 0.35)]
  for offset in offsets:
    bxy.drawImage("floor", pos.vec2 + offset, angle = 0,
                  scale = scaffoldScale, tint = scaffoldTint)
  # Draw horizontal scaffold bars connecting posts
  let barTint = color(0.6, 0.4, 0.15, 0.7)
  for yOff in [-0.35'f32, 0.35'f32]:
    bxy.drawImage("floor", pos.vec2 + vec2(0, yOff), angle = 0,
                  scale = scaffoldScale, tint = barTint)
  # Draw construction progress bar below the building
  drawSegmentBar(pos.vec2, vec2(0, 0.65), constructionRatio,
                 color(0.9, 0.7, 0.1, 1.0), color(0.3, 0.3, 0.3, 0.7))

proc renderBuildingUI*(thing: Thing, pos: IVec2,
                       teamPopCounts, teamHouseCounts: array[MapRoomObjectsTeams, int]) =
  ## Render UI overlays for a building (stockpiles, population, garrison).
  ##
  ## Handles:
  ## - Production queue progress bars for buildings training units
  ## - Resource stockpile icons showing team resource counts
  ## - Population display on TownCenters (current/max pop)
  ## - Garrison indicators showing garrisoned unit counts
  ##
  ## Parameters:
  ##   thing: The building Thing
  ##   pos: World position of the building
  ##   teamPopCounts: Array of population counts per team
  ##   teamHouseCounts: Array of house counts per team

  # Production queue progress bar (AoE2-style)
  if thing.productionQueue.entries.len > 0:
    let entry = thing.productionQueue.entries[0]
    if entry.totalSteps > 0 and entry.remainingSteps > 0:
      let ratio = clamp(1.0'f32 - entry.remainingSteps.float32 / entry.totalSteps.float32, 0.0, 1.0)
      drawSegmentBar(pos.vec2, vec2(0, 0.55), ratio,
                     color(0.2, 0.5, 1.0, 1.0), color(0.3, 0.3, 0.3, 0.7))
      # Draw smoke/chimney effect for active production buildings
      drawBuildingSmoke(pos.vec2, thing.id)
  let res = buildingStockpileRes(thing.kind)
  if res != ResourceNone:
    let teamId = thing.teamId
    if teamId < 0 or teamId >= MapRoomObjectsTeams:
      return
    let icon = case res
      of ResourceFood: itemSpriteKey(ItemWheat)
      of ResourceWood: itemSpriteKey(ItemWood)
      of ResourceStone: itemSpriteKey(ItemStone)
      of ResourceGold: itemSpriteKey(ItemGold)
      of ResourceWater: itemSpriteKey(ItemWater)
      of ResourceNone: ""
    let count = env.teamStockpiles[teamId].counts[res]
    let iconPos = pos.vec2 + vec2(-0.18, -0.62)
    if icon.len > 0 and icon in bxy:
      bxy.drawImage(icon, iconPos, angle = 0, scale = OverlayIconScale,
                    tint = color(1, 1, 1, if count > 0: 1.0 else: 0.35))
    if count > 0:
      let labelKey = ensureHeartCountLabel(count)
      if labelKey.len > 0 and labelKey in bxy:
        bxy.drawImage(labelKey, iconPos + vec2(0.14, -0.08), angle = 0,
                      scale = OverlayLabelScale, tint = color(1, 1, 1, 1))
  if thing.kind == TownCenter:
    let teamId = thing.teamId
    if teamId >= 0 and teamId < MapRoomObjectsTeams:
      let iconPos = pos.vec2 + vec2(-0.18, -0.62)
      if "oriented/gatherer.s" in bxy:
        bxy.drawImage("oriented/gatherer.s", iconPos, angle = 0,
                      scale = OverlayIconScale, tint = color(1, 1, 1, 1))
      let popText = "x " & $teamPopCounts[teamId] & "/" &
                    $min(MapAgentsPerTeam, teamHouseCounts[teamId] * HousePopCap)
      let popLabel = if popText in overlayLabelImages: overlayLabelImages[popText]
        else:
          let (image, _) = renderTextLabel(popText, HeartCountFontPath,
                                           HeartCountFontSize, HeartCountPadding.float32, 0.7)
          let key = "overlay_label/" & popText.replace(" ", "_").replace("/", "_")
          bxy.addImage(key, image)
          overlayLabelImages[popText] = key
          key
      if popLabel.len > 0 and popLabel in bxy:
        bxy.drawImage(popLabel, iconPos + vec2(0.14, -0.08), angle = 0,
                      scale = OverlayLabelScale, tint = color(1, 1, 1, 1))
  # Garrison indicator for buildings that can garrison units
  if thing.kind in {TownCenter, Castle, GuardTower, House}:
    let garrisonCount = thing.garrisonedUnits.len
    if garrisonCount > 0:
      # Position on right side of building to avoid overlap with stockpile icons
      let garrisonIconPos = pos.vec2 + vec2(0.22, -0.62)
      if "oriented/fighter.s" in bxy:
        bxy.drawImage("oriented/fighter.s", garrisonIconPos, angle = 0,
                      scale = OverlayIconScale, tint = color(1, 1, 1, 1))
      let garrisonText = "x" & $garrisonCount
      let garrisonLabel = if garrisonText in overlayLabelImages: overlayLabelImages[garrisonText]
        else:
          let (image, _) = renderTextLabel(garrisonText, HeartCountFontPath,
                                           HeartCountFontSize, HeartCountPadding.float32, 0.7)
          let key = "overlay_label/" & garrisonText.replace(" ", "_")
          bxy.addImage(key, image)
          overlayLabelImages[garrisonText] = key
          key
      if garrisonLabel.len > 0 and garrisonLabel in bxy:
        bxy.drawImage(garrisonLabel, garrisonIconPos + vec2(0.12, -0.08), angle = 0,
                      scale = OverlayLabelScale, tint = color(1, 1, 1, 1))

# ─── Footer Button Types and Rendering ───────────────────────────────────────

type FooterButtonKind* = enum
  FooterPlayPause
  FooterStep
  FooterSlow
  FooterFast
  FooterFaster
  FooterSuper

type FooterButton* = object
  kind*: FooterButtonKind
  rect*: IRect
  labelKey*: string
  labelSize*: IVec2
  iconKey*: string
  iconSize*: IVec2
  isPressed*: bool

var
  footerLabelImages: Table[string, string] = initTable[string, string]()
  footerLabelSizes: Table[string, IVec2] = initTable[string, IVec2]()
  footerIconSizes: Table[string, IVec2] = initTable[string, IVec2]()

proc buildFooterButtons*(panelRect: IRect): seq[FooterButton] =
  let footerTop = panelRect.y.int32 + panelRect.h.int32 - FooterHeight.int32
  let innerHeight = FooterHeight.float32 - FooterPadding * 2.0
  var buttons: seq[FooterButton] = @[]

  # Calculate button widths based on content
  let buttonDefs = [
    # Icon-first, but always provide a text fallback so missing atlas sprites don't crash UI.
    (FooterPlayPause, if paused: "icon_play" else: "icon_pause", if paused: "Play" else: "Pause"),
    (FooterStep, "icon_step", "Step"),
    (FooterSlow, "", "0.5x"),
    (FooterFast, "", "2x"),
    (FooterFaster, "icon_ffwd", "4x"),
  ]

  var totalWidth = 0.0'f32
  var buttonWidths: seq[float32] = @[]
  for (_, iconKey, labelText) in buttonDefs:
    var w = FooterButtonPaddingX * 2.0
    if iconKey.len > 0 and iconKey in bxy:
      if iconKey notin footerIconSizes:
        let size = bxy.getImageSize(iconKey)
        footerIconSizes[iconKey] = ivec2(size.x.int32, size.y.int32)
      let iconSize = footerIconSizes[iconKey]
      let sc = min(1.0'f32, innerHeight / iconSize.y.float32)
      w += iconSize.x.float32 * sc
    elif labelText.len > 0:
      if labelText notin footerLabelImages:
        let (image, size) = renderTextLabel(labelText, FooterFontPath,
                                            FooterFontSize, FooterLabelPadding, 0.0)
        let key = "footer_btn/" & labelText
        bxy.addImage(key, image)
        footerLabelImages[labelText] = key
        footerLabelSizes[labelText] = size
      let labelSize = footerLabelSizes[labelText]
      let sc = min(1.0'f32, innerHeight / labelSize.y.float32)
      w += labelSize.x.float32 * sc
    buttonWidths.add(w)
    totalWidth += w

  totalWidth += FooterButtonGap * (buttonWidths.len - 1).float32

  # Center buttons in footer
  var x = panelRect.x.float32 + (panelRect.w.float32 - totalWidth) / 2.0
  let y = footerTop.float32 + FooterPadding

  for i, (kind, iconKey, labelText) in buttonDefs:
    let w = buttonWidths[i]
    var btn = FooterButton(
      kind: kind,
      rect: IRect(x: x.int32, y: y.int32, w: w.int32, h: innerHeight.int32),
      isPressed: false
    )
    if iconKey.len > 0 and iconKey in bxy:
      btn.iconKey = iconKey
      btn.iconSize = footerIconSizes[iconKey]
    if labelText.len > 0:
      btn.labelKey = footerLabelImages[labelText]
      btn.labelSize = footerLabelSizes[labelText]
    # Check pressed state
    btn.isPressed = case kind
      of FooterPlayPause: not paused
      of FooterStep: false
      of FooterSlow: speedMultiplier == 0.5
      of FooterFast: speedMultiplier == 2.0
      of FooterFaster: speedMultiplier >= 4.0 and speedMultiplier < 10.0
      of FooterSuper: speedMultiplier >= 10.0
    buttons.add(btn)
    x += w + FooterButtonGap

  result = buttons

proc centerIn(rect: IRect, size: Vec2): Vec2 =
  vec2(
    rect.x.float32 + (rect.w.float32 - size.x) / 2.0,
    rect.y.float32 + (rect.h.float32 - size.y) / 2.0
  )

proc drawFooter*(panelRect: IRect, buttons: seq[FooterButton]) =
  pushSemanticContext("Footer")
  let footerTop = panelRect.y.float32 + panelRect.h.float32 - FooterHeight.float32

  # Draw footer background
  let bgColor = color(0.15, 0.15, 0.18, 0.9)
  bxy.drawRect(rect = Rect(x: panelRect.x.float32, y: footerTop,
                          w: panelRect.w.float32, h: FooterHeight.float32),
               color = bgColor)

  # Draw buttons
  let innerHeight = FooterHeight.float32 - FooterPadding * 2.0
  for button in buttons:
    # Button background
    let btnBg = if button.isPressed:
      color(0.3, 0.4, 0.5, 0.8)  # Highlight for active state
    else:
      color(0.25, 0.25, 0.28, 0.8)
    bxy.drawRect(rect = Rect(x: button.rect.x.float32, y: button.rect.y.float32,
                            w: button.rect.w.float32, h: button.rect.h.float32),
                 color = btnBg)

    # Draw icon or label
    if button.iconKey.len > 0 and button.iconKey in bxy:
      let sc = min(1.0'f32, innerHeight / button.iconSize.y.float32)
      let iconPos = centerIn(button.rect, vec2(
                      button.iconSize.x.float32 * sc,
                      button.iconSize.y.float32 * sc)) + vec2(8.0, 9.0) * sc
      bxy.drawImage(button.iconKey, iconPos, angle = 0, scale = sc)
    elif button.labelKey.len > 0 and button.labelKey in bxy:
      # Text labels still use boxy (no fonts in silky atlas yet)
      let shift = if button.kind == FooterFaster: vec2(8.0, 9.0) else: vec2(0.0, 0.0)
      bxy.drawImage(button.labelKey,
        centerIn(button.rect, vec2(button.labelSize.x.float32, button.labelSize.y.float32)) + shift,
        angle = 0, scale = 1)

  popSemanticContext()

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
      let glowPulse = sin(frame.float32 * 0.1) * 0.15 + 0.85
      let glowColor = color(0.3, 0.7, 1.0, 0.4 * glowPulse)
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
        let lineColor = color(teamColor.r, teamColor.g, teamColor.b, pulseAlpha * 0.7)
        bxy.drawImage("floor", segMid, angle = 0, scale = RallyPointLineWidth * 2,
                      tint = lineColor)

    # Draw the rally point beacon (animated flag/marker)
    if isInViewport(rallyPos):
      # Pulsing scale effect for the beacon
      let beaconScale = RallyPointBeaconScale * (1.0 + pulse * 0.15)

      # Draw outer glow (larger, more transparent)
      let glowColor = color(teamColor.r, teamColor.g, teamColor.b, pulseAlpha * 0.3)
      bxy.drawImage("floor", rallyPos.vec2, angle = 0, scale = beaconScale * 3.0,
                    tint = glowColor)

      # Draw main beacon (use lantern sprite if available, otherwise floor)
      let beaconColor = color(teamColor.r, teamColor.g, teamColor.b, pulseAlpha)
      if "lantern" in bxy:
        bxy.drawImage("lantern", rallyPos.vec2, angle = 0, scale = SpriteScale * 0.8,
                      tint = beaconColor)
      else:
        # Fallback: draw a colored circle using floor sprite
        bxy.drawImage("floor", rallyPos.vec2, angle = 0, scale = beaconScale * 1.5,
                      tint = beaconColor)

      # Draw inner bright core
      let coreColor = color(1.0, 1.0, 1.0, pulseAlpha * 0.8)
      bxy.drawImage("floor", rallyPos.vec2, angle = 0, scale = beaconScale * 0.8,
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
        let lineColor = color(previewColor.r, previewColor.g, previewColor.b, pulseAlpha * 0.5)
        bxy.drawImage("floor", segMid, angle = 0, scale = RallyPointLineWidth * 2,
                      tint = lineColor)

  # Draw the rally point preview beacon at mouse position
  let mouseGrid = ivec2(mousePos.x.int, mousePos.y.int)
  if isInViewport(mouseGrid):
    let beaconScale = RallyPointBeaconScale * (1.0 + pulse * 0.2)

    # Draw outer glow
    let glowColor = color(previewColor.r, previewColor.g, previewColor.b, pulseAlpha * 0.4)
    bxy.drawImage("floor", mousePos, angle = 0, scale = beaconScale * 3.5,
                  tint = glowColor)

    # Draw main beacon
    if "lantern" in bxy:
      bxy.drawImage("lantern", mousePos, angle = 0, scale = SpriteScale * 0.9,
                    tint = previewColor)
    else:
      bxy.drawImage("floor", mousePos, angle = 0, scale = beaconScale * 1.8,
                    tint = previewColor)

    # Draw inner bright core
    let coreColor = color(1.0, 1.0, 1.0, pulseAlpha * 0.9)
    bxy.drawImage("floor", mousePos, angle = 0, scale = beaconScale * 0.9,
                  tint = coreColor)

# ─── HUD Labels ──────────────────────────────────────────────────────────────

var
  stepLabelKey = ""
  stepLabelLastValue = -1
  stepLabelSize = ivec2(0, 0)
  controlModeLabelKey = ""
  controlModeLabelLastValue = -2  # Start different from any valid value
  controlModeLabelSize = ivec2(0, 0)

proc drawFooterHudLabel(panelRect: IRect, key: string, labelSize: IVec2, xOffset: float32) =
  let footerTop = panelRect.y.float32 + panelRect.h.float32 - FooterHeight.float32
  let innerHeight = FooterHeight.float32 - FooterPadding * 2.0
  let scale = min(1.0'f32, innerHeight / labelSize.y.float32)
  let pos = vec2(
    panelRect.x.float32 + xOffset,
    footerTop + FooterPadding + (innerHeight - labelSize.y.float32 * scale) * 0.5 + 20.0
  )
  bxy.drawImage(key, pos, angle = 0, scale = scale)

proc drawSelectionLabel*(panelRect: IRect) =
  if not isValidPos(selectedPos):
    return

  proc appendResourceCount(label: var string, thing: Thing) =
    var count = 0
    case thing.kind
    of Wheat, Stubble:
      count = getInv(thing, ItemWheat)
    of Fish:
      count = getInv(thing, ItemFish)
    of Relic:
      count = getInv(thing, ItemGold)
    of Tree, Stump:
      count = getInv(thing, ItemWood)
    of Stone, Stalagmite:
      count = getInv(thing, ItemStone)
    of Gold:
      count = getInv(thing, ItemGold)
    of Bush, Cactus:
      count = getInv(thing, ItemPlant)
    of Cow:
      count = getInv(thing, ItemMeat)
    of Corpse:
      for key, c in thing.inventory.pairs:
        if c > 0:
          label &= " (" & $key & " " & $c & ")"
          return
      return
    else:
      return
    label &= " (" & $count & ")"

  template displayNameFor(t: Thing): string =
    if t.kind == Agent:
      UnitClassLabels[t.unitClass]
    elif isBuildingKind(t.kind):
      BuildingRegistry[t.kind].displayName
    else:
      let name = ThingCatalog[t.kind].displayName
      if name.len > 0: name else: $t.kind

  var label = ""
  let selThing = env.grid[selectedPos.x][selectedPos.y]
  if not isNil(selThing):
    label = displayNameFor(selThing)
    appendResourceCount(label, selThing)
  else:
    let bgThing = env.backgroundGrid[selectedPos.x][selectedPos.y]
    if not isNil(bgThing):
      label = displayNameFor(bgThing)
      appendResourceCount(label, bgThing)

  if label.len == 0:
    return
  var key: string
  if label in infoLabelImages:
    key = infoLabelImages[label]
  else:
    let (image, size) = renderTextLabel(label, InfoLabelFontPath,
                                        InfoLabelFontSize, InfoLabelPadding.float32, 0.6)
    infoLabelSizes[label] = size
    key = "info_label/" & label.replace(" ", "_").replace("(", "_").replace(")", "_")
    bxy.addImage(key, image)
    infoLabelImages[label] = key
  let labelSize = infoLabelSizes[label]
  drawFooterHudLabel(panelRect, key, labelSize, FooterHudPadding)

proc drawStepLabel*(panelRect: IRect) =
  let currentStep = env.currentStep
  var key: string
  if currentStep == stepLabelLastValue and stepLabelKey.len > 0:
    key = stepLabelKey
  else:
    stepLabelLastValue = currentStep
    let text = "Step: " & $currentStep
    let (image, size) = renderTextLabel(text, InfoLabelFontPath,
                                        InfoLabelFontSize, InfoLabelPadding.float32, 0.6)
    stepLabelSize = size
    stepLabelKey = "hud_step"
    bxy.addImage(stepLabelKey, image)
    key = stepLabelKey
  if key.len == 0:
    return
  let innerHeight = FooterHeight.float32 - FooterPadding * 2.0
  let scale = min(1.0'f32, innerHeight / stepLabelSize.y.float32)
  let labelW = stepLabelSize.x.float32 * scale
  let xOffset = panelRect.w.float32 - labelW - FooterHudPadding
  drawFooterHudLabel(panelRect, key, stepLabelSize, xOffset)

proc drawControlModeLabel*(panelRect: IRect) =
  let mode = playerTeam
  var key: string
  if mode == controlModeLabelLastValue and controlModeLabelKey.len > 0:
    key = controlModeLabelKey
  else:
    controlModeLabelLastValue = mode
    let text = case mode
      of -1: "Observer"
      of 0..7: "Team " & $mode
      else: "Unknown"
    let (image, size) = renderTextLabel(text, InfoLabelFontPath,
                                        InfoLabelFontSize, InfoLabelPadding.float32, 0.6)
    controlModeLabelSize = size
    controlModeLabelKey = "hud_control_mode"
    bxy.addImage(controlModeLabelKey, image)
    key = controlModeLabelKey
  if key.len == 0:
    return
  let innerHeight = FooterHeight.float32 - FooterPadding * 2.0
  let scale = min(1.0'f32, innerHeight / controlModeLabelSize.y.float32)
  # Position to the left of the step label (center area of footer)
  let labelW = controlModeLabelSize.x.float32 * scale
  let stepLabelW = stepLabelSize.x.float32 * scale
  let xOffset = panelRect.w.float32 - labelW - stepLabelW - FooterHudPadding * 2.0 - 10.0
  drawFooterHudLabel(panelRect, key, controlModeLabelSize, xOffset)

# ─── Minimap ─────────────────────────────────────────────────────────────────

const
  MinimapSizeConst = 200       # pixels (square)
  MinimapPadding = 8.0'f32
  MinimapUpdateInterval = 10  # rebuild unit layer every N frames
  MinimapBorderWidth = 2.0'f32

var
  minimapTerrainImage: Image     # cached base terrain (invalidated on mapGeneration change)
  minimapTerrainGeneration = -1
  minimapCompositeImage: Image   # terrain + units + fog composite
  minimapLastUnitFrame = -1
  minimapImageKey = "minimap_composite"
  # Pre-computed minimap scale factors
  minimapScaleX: float32 = MinimapSizeConst.float32 / MapWidth.float32
  minimapScaleY: float32 = MinimapSizeConst.float32 / MapHeight.float32
  minimapInvScaleX: float32 = MapWidth.float32 / MinimapSizeConst.float32
  minimapInvScaleY: float32 = MapHeight.float32 / MinimapSizeConst.float32
  # Cached team colors for minimap (avoid Color -> ColorRGBX conversion each frame)
  minimapTeamColors: array[MapRoomObjectsTeams, ColorRGBX]
  minimapTeamBrightColors: array[MapRoomObjectsTeams, ColorRGBX]  # For buildings
  minimapTeamColorsInitialized = false

proc toMinimapColor(terrain: TerrainType, biome: BiomeType): ColorRGBX =
  ## Map a terrain+biome to a minimap pixel color.
  case terrain
  of Water:
    rgbx(30, 60, 130, 255)        # dark blue
  of ShallowWater:
    rgbx(80, 140, 200, 255)       # lighter blue
  of Bridge:
    rgbx(140, 110, 80, 255)       # brown
  of Road:
    rgbx(160, 150, 130, 255)      # tan
  of Snow:
    rgbx(230, 235, 245, 255)      # near-white
  of Dune, Sand:
    rgbx(210, 190, 110, 255)      # sandy yellow
  of Mud:
    rgbx(100, 85, 60, 255)        # muddy brown
  of Mountain:
    rgbx(80, 75, 70, 255)         # dark rocky gray
  else:
    # Use biome tint for base terrain (Empty, Grass, Fertile, ramps, etc.)
    let tc = case biome
      of BiomeForestType: BiomeColorForest
      of BiomeDesertType: BiomeColorDesert
      of BiomeCavesType: BiomeColorCaves
      of BiomeCityType: BiomeColorCity
      of BiomePlainsType: BiomeColorPlains
      of BiomeSwampType: BiomeColorSwamp
      of BiomeDungeonType: BiomeColorDungeon
      of BiomeSnowType: BiomeColorSnow
      else: BaseTileColorDefault
    let i = min(tc.intensity, 1.3'f32)
    rgbx(
      uint8(clamp(tc.r * i * 255, 0, 255)),
      uint8(clamp(tc.g * i * 255, 0, 255)),
      uint8(clamp(tc.b * i * 255, 0, 255)),
      255
    )

proc rebuildMinimapTerrain() =
  ## Rebuild the cached terrain layer. Called when mapGeneration changes.
  if minimapTerrainImage.isNil or
     minimapTerrainImage.width != MinimapSizeConst or
     minimapTerrainImage.height != MinimapSizeConst:
    minimapTerrainImage = newImage(MinimapSizeConst, MinimapSizeConst)

  # Scale factors: map coords -> minimap pixel
  let scaleX = MinimapSizeConst.float32 / MapWidth.float32
  let scaleY = MinimapSizeConst.float32 / MapHeight.float32

  for py in 0 ..< MinimapSizeConst:
    for px in 0 ..< MinimapSizeConst:
      let mx = clamp(int(px.float32 / scaleX), 0, MapWidth - 1)
      let my = clamp(int(py.float32 / scaleY), 0, MapHeight - 1)
      let terrain = env.terrain[mx][my]
      let biome = env.biomes[mx][my]
      # Check for trees at this tile
      let bg = env.backgroundGrid[mx][my]
      let c = if bg.isKind(Tree):
        rgbx(40, 100, 40, 255)    # dark green for trees
      else:
        toMinimapColor(terrain, biome)
      minimapTerrainImage.unsafe[px, py] = c

  minimapTerrainGeneration = env.mapGeneration

proc initMinimapTeamColors() =
  ## Pre-compute team colors for minimap to avoid per-frame conversions.
  for i in 0 ..< MapRoomObjectsTeams:
    let tc = if i < env.teamColors.len: env.teamColors[i] else: color(0.5, 0.5, 0.5, 1.0)
    minimapTeamColors[i] = colorToRgbx(tc)
    minimapTeamBrightColors[i] = colorToRgbx(color(
      min(tc.r * 1.2 + 0.1, 1.0),
      min(tc.g * 1.2 + 0.1, 1.0),
      min(tc.b * 1.2 + 0.1, 1.0),
      1.0
    ))
  minimapTeamColorsInitialized = true

# Building kinds that commonly have instances (skip iteration for unlikely kinds)
const MinimapBuildingKinds = [
  TownCenter, House, Mill, LumberCamp, MiningCamp, Market, Blacksmith,
  Barracks, ArcheryRange, Stable, SiegeWorkshop, Castle, Monastery,
  GuardTower, Door
]

proc rebuildMinimapComposite(fogTeamId: int) =
  ## Composite terrain + units + buildings + fog into final minimap image.
  if minimapTerrainGeneration != env.mapGeneration:
    rebuildMinimapTerrain()

  # Ensure team colors are initialized
  if not minimapTeamColorsInitialized:
    initMinimapTeamColors()

  if minimapCompositeImage.isNil or
     minimapCompositeImage.width != MinimapSizeConst or
     minimapCompositeImage.height != MinimapSizeConst:
    minimapCompositeImage = newImage(MinimapSizeConst, MinimapSizeConst)

  # Start from cached terrain
  copyMem(addr minimapCompositeImage.data[0],
          addr minimapTerrainImage.data[0],
          MinimapSizeConst * MinimapSizeConst * 4)

  # Use pre-computed scale factors
  let scaleX = minimapScaleX
  let scaleY = minimapScaleY

  # Draw buildings (team-colored, 2x2 pixel blocks)
  # Only iterate over building kinds that are likely to have instances
  for kind in MinimapBuildingKinds:
    for thing in env.thingsByKind[kind]:
      if not isValidPos(thing.pos):
        continue
      let teamId = thing.teamId
      # Use pre-computed team colors
      let bright = if teamId >= 0 and teamId < MapRoomObjectsTeams:
        minimapTeamBrightColors[teamId]
      else:
        rgbx(179, 179, 179, 255)  # 0.7 * 255 for neutral
      let px = int(thing.pos.x.float32 * scaleX)
      let py = int(thing.pos.y.float32 * scaleY)
      # Unrolled 2x2 block drawing
      let fx0 = clamp(px, 0, MinimapSizeConst - 1)
      let fx1 = clamp(px + 1, 0, MinimapSizeConst - 1)
      let fy0 = clamp(py, 0, MinimapSizeConst - 1)
      let fy1 = clamp(py + 1, 0, MinimapSizeConst - 1)
      minimapCompositeImage.unsafe[fx0, fy0] = bright
      minimapCompositeImage.unsafe[fx1, fy0] = bright
      minimapCompositeImage.unsafe[fx0, fy1] = bright
      minimapCompositeImage.unsafe[fx1, fy1] = bright

  # Draw units (team-colored dots) - use pre-computed colors
  for agent in env.agents:
    if not isAgentAlive(env, agent):
      continue
    let teamId = getTeamId(agent)
    let dot = if teamId >= 0 and teamId < MapRoomObjectsTeams:
      minimapTeamColors[teamId]
    else:
      rgbx(128, 128, 128, 255)  # Gray for unknown
    let px = clamp(int(agent.pos.x.float32 * scaleX), 0, MinimapSizeConst - 1)
    let py = clamp(int(agent.pos.y.float32 * scaleY), 0, MinimapSizeConst - 1)
    minimapCompositeImage.unsafe[px, py] = dot

  # Apply fog of war with edge smoothing
  if fogTeamId >= 0 and fogTeamId < MapRoomObjectsTeams:
    let invScaleX = minimapInvScaleX
    let invScaleY = minimapInvScaleY
    const
      MinimapFogEdgeSmoothFactor = 0.6  # How much to lighten edge tiles
      Neighbors = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
    for py in 0 ..< MinimapSizeConst:
      let my = clamp(int(py.float32 * invScaleY), 0, MapHeight - 1)
      for px in 0 ..< MinimapSizeConst:
        let mx = clamp(int(px.float32 * invScaleX), 0, MapWidth - 1)
        if not fogVisibility[mx][my]:
          # Check if this is an edge tile (adjacent to visible)
          var isEdge = false
          for (dx, dy) in Neighbors:
            let nx = mx + dx
            let ny = my + dy
            if nx >= 0 and nx < MapWidth and ny >= 0 and ny < MapHeight:
              if fogVisibility[nx][ny]:
                isEdge = true
                break
          # Darken fogged areas
          let c = minimapCompositeImage.unsafe[px, py]
          let factor = if isEdge: MinimapFogEdgeSmoothFactor else: 0.3'f32
          minimapCompositeImage.unsafe[px, py] = rgbx(
            uint8(c.r.float32 * factor),
            uint8(c.g.float32 * factor),
            uint8(c.b.float32 * factor),
            c.a
          )

  minimapLastUnitFrame = frame

proc drawMinimap*(panelRect: IRect, panel: Panel) =
  ## Draw the minimap in the bottom-left corner of the panel.
  let minimapX = panelRect.x.float32 + MinimapPadding
  let minimapY = panelRect.y.float32 + panelRect.h.float32 - MinimapSizeConst.float32 - MinimapPadding - FooterHeight.float32

  # Rebuild composite if needed (every MinimapUpdateInterval frames or on mapgen change)
  let fogTeamId = if settings.showFogOfWar: playerTeam else: -1
  if frame - minimapLastUnitFrame >= MinimapUpdateInterval or
     minimapTerrainGeneration != env.mapGeneration:
    rebuildMinimapComposite(fogTeamId)
    bxy.addImage(minimapImageKey, minimapCompositeImage)

  # Draw border
  let borderColor = color(0.2, 0.2, 0.25, 0.9)
  bxy.drawRect(
    rect = Rect(x: minimapX - MinimapBorderWidth, y: minimapY - MinimapBorderWidth,
                w: MinimapSizeConst.float32 + MinimapBorderWidth * 2,
                h: MinimapSizeConst.float32 + MinimapBorderWidth * 2),
    color = borderColor
  )

  # Draw minimap image
  bxy.drawImage(minimapImageKey, vec2(minimapX, minimapY), angle = 0, scale = 1.0)

  # Draw viewport rectangle
  if currentViewport.valid:
    let scaleX = minimapScaleX
    let scaleY = minimapScaleY
    let vpX = minimapX + currentViewport.minX.float32 * scaleX
    let vpY = minimapY + currentViewport.minY.float32 * scaleY
    let vpW = (currentViewport.maxX - currentViewport.minX + 1).float32 * scaleX
    let vpH = (currentViewport.maxY - currentViewport.minY + 1).float32 * scaleY
    let vpColor = color(1.0, 1.0, 1.0, 0.7)
    # Draw viewport outline as 4 thin rectangles
    let lineW = 1.0'f32
    bxy.drawRect(rect = Rect(x: vpX, y: vpY, w: vpW, h: lineW), color = vpColor)  # top
    bxy.drawRect(rect = Rect(x: vpX, y: vpY + vpH - lineW, w: vpW, h: lineW), color = vpColor)  # bottom
    bxy.drawRect(rect = Rect(x: vpX, y: vpY, w: lineW, h: vpH), color = vpColor)  # left
    bxy.drawRect(rect = Rect(x: vpX + vpW - lineW, y: vpY, w: lineW, h: vpH), color = vpColor)  # right

# ─── Unit Info Panel (stub) ──────────────────────────────────────────────────

const UnitInfoFontSize = 18.0'f32

proc getUnitInfoLabel(text: string, fontSize: float32 = UnitInfoFontSize): (string, IVec2) =
  if text in infoLabelImages:
    return (infoLabelImages[text], infoLabelSizes[text])
  let (image, size) = renderTextLabel(text, InfoLabelFontPath, fontSize, 4.0, 0.5)
  let key = "unit_info/" & text.replace(" ", "_").replace(":", "_")
  bxy.addImage(key, image)
  infoLabelImages[text] = key
  infoLabelSizes[text] = size
  return (key, size)

proc drawUnitInfoPanel*(panelRect: IRect) =
  ## Draw unit info panel showing details about selected unit/building.
  ## Positioned in bottom-right area of the screen.
  if selection.len == 0:
    return

  let selected = selection[0]
  if selected.isNil:
    return

  let panelW = 220.0'f32
  let panelH = 180.0'f32
  let panelX = panelRect.x.float32 + panelRect.w.float32 - panelW - MinimapPadding
  let panelY = panelRect.y.float32 + panelRect.h.float32 - panelH - MinimapPadding - FooterHeight.float32

  # Draw panel background
  bxy.drawRect(rect = Rect(x: panelX, y: panelY, w: panelW, h: panelH),
               color = color(0.1, 0.1, 0.15, 0.85))

  var yOffset = 8.0'f32
  let xPadding = 8.0'f32

  # Draw name/type
  let name = if selected.kind == Agent:
    UnitClassLabels[selected.unitClass]
  elif isBuildingKind(selected.kind):
    BuildingRegistry[selected.kind].displayName
  else:
    $selected.kind
  let (nameKey, nameSize) = getUnitInfoLabel(name, 22.0)
  bxy.drawImage(nameKey, vec2(panelX + xPadding, panelY + yOffset), angle = 0, scale = 1.0)
  yOffset += nameSize.y.float32 + 4.0

  # Draw HP if applicable
  if selected.maxHp > 0:
    let hpText = "HP: " & $selected.hp & "/" & $selected.maxHp
    let (hpKey, hpSize) = getUnitInfoLabel(hpText)
    bxy.drawImage(hpKey, vec2(panelX + xPadding, panelY + yOffset), angle = 0, scale = 1.0)
    yOffset += hpSize.y.float32 + 2.0

  # Draw team
  let teamText = "Team: " & $selected.teamId
  let (teamKey, teamSize) = getUnitInfoLabel(teamText)
  bxy.drawImage(teamKey, vec2(panelX + xPadding, panelY + yOffset), angle = 0, scale = 1.0)
  yOffset += teamSize.y.float32 + 2.0

  # Draw position
  let posText = "Pos: " & $selected.pos.x & ", " & $selected.pos.y
  let (posKey, _) = getUnitInfoLabel(posText)
  bxy.drawImage(posKey, vec2(panelX + xPadding, panelY + yOffset), angle = 0, scale = 1.0)

# ─── Resource Bar ────────────────────────────────────────────────────────────

var
  resourceBarLabelImages: Table[string, string] = initTable[string, string]()
  resourceBarLabelSizes: Table[string, IVec2] = initTable[string, IVec2]()

proc ensureResourceBarLabel(text: string): (string, IVec2) =
  if text in resourceBarLabelImages:
    return (resourceBarLabelImages[text], resourceBarLabelSizes[text])
  let (image, size) = renderTextLabel(text, FooterFontPath, FooterFontSize, 4.0, 0.0)
  let key = "res_bar/" & text
  bxy.addImage(key, image)
  resourceBarLabelImages[text] = key
  resourceBarLabelSizes[text] = size
  return (key, size)

proc drawResourceBar*(panelRect: IRect, teamId: int) =
  ## Draw resource bar at top of viewport showing team resources.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return

  let barY = panelRect.y.float32
  let barH = ResourceBarHeight.float32
  let barX = panelRect.x.float32

  # Draw background
  bxy.drawRect(rect = Rect(x: barX, y: barY, w: panelRect.w.float32, h: barH),
               color = color(0.1, 0.1, 0.15, 0.8))

  let stockpile = env.teamStockpiles[teamId]
  var xOffset = 10.0'f32

  # Draw each resource type
  for res in [ResourceFood, ResourceWood, ResourceStone, ResourceGold]:
    let icon = case res
      of ResourceFood: itemSpriteKey(ItemWheat)
      of ResourceWood: itemSpriteKey(ItemWood)
      of ResourceStone: itemSpriteKey(ItemStone)
      of ResourceGold: itemSpriteKey(ItemGold)
      of ResourceWater: itemSpriteKey(ItemWater)
      of ResourceNone: ""

    if icon.len > 0 and icon in bxy:
      # Draw icon
      let iconY = barY + (barH - 24.0) / 2.0
      bxy.drawImage(icon, vec2(barX + xOffset, iconY), angle = 0, scale = 1.0 / 8.0)
      xOffset += 28.0

      # Draw count
      let count = stockpile.counts[res]
      let (labelKey, labelSize) = ensureResourceBarLabel($count)
      let labelY = barY + (barH - labelSize.y.float32) / 2.0
      bxy.drawImage(labelKey, vec2(barX + xOffset, labelY), angle = 0, scale = 1.0)
      xOffset += labelSize.x.float32 + 20.0

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

# ─── Building Ghost Preview ──────────────────────────────────────────────────

proc canPlaceBuildingAt*(pos: IVec2, kind: ThingKind): bool =
  ## Check if a building can be placed at the given position.
  if not isValidPos(pos):
    return false
  # Check terrain
  let terrain = env.terrain[pos.x][pos.y]
  if isWaterTerrain(terrain):
    return false
  # Check for existing objects
  let blocking = env.grid[pos.x][pos.y]
  if not isNil(blocking):
    return false
  let background = env.backgroundGrid[pos.x][pos.y]
  if not isNil(background) and background.kind in CliffKinds:
    return false
  true

proc drawBuildingGhost*(worldPos: Vec2) =
  ## Draw a transparent building preview at the given world position.
  ## Shows green if placement is valid, red if invalid.
  if not buildingPlacementMode:
    return

  let gridPos = (worldPos + vec2(0.5, 0.5)).ivec2
  let spriteKey = buildingSpriteKey(buildingPlacementKind)
  if spriteKey.len == 0 or spriteKey notin bxy:
    return

  let valid = canPlaceBuildingAt(gridPos, buildingPlacementKind)
  buildingPlacementValid = valid

  # Ghost tint: green for valid, red for invalid
  let tint = if valid:
    color(0.3, 1.0, 0.3, 0.6)  # Semi-transparent green
  else:
    color(1.0, 0.3, 0.3, 0.6)  # Semi-transparent red

  bxy.drawImage(spriteKey, gridPos.vec2, angle = 0, scale = SpriteScale, tint = tint)
