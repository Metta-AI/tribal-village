## Footer buttons, speed controls, and footer HUD label helpers.

import
  boxy, bumpy, pixie, tables, vmath,
  common, environment, label_cache, renderer_core, semantic

const
  PlaySpeedEpsilon = 0.0001'f

type
  FooterButtonKind* = enum
    FooterPlayPause
    FooterStep
    FooterSlow
    FooterFast
    FooterFaster
    FooterSuper

  FooterButton* = object
    kind*: FooterButtonKind
    rect*: IRect
    labelKey*: string
    labelSize*: IVec2
    iconKey*: string
    iconSize*: IVec2
    isPressed*: bool

let
  footerButtonDefs = [
    (FooterPlayPause, "icon_play", "Play"),
    (FooterStep, "icon_step", "Step"),
    (FooterSlow, "", "0.5x"),
    (FooterFast, "", "2x"),
    (FooterFaster, "icon_ffwd", "4x"),
  ]

var
  footerIconSizes = initTable[string, IVec2]()
  stepLabelKey = ""
  stepLabelLastValue = -1
  stepLabelSize = ivec2(0, 0)
  controlModeLabelKey = ""
  controlModeLabelLastValue = -2
  controlModeLabelSize = ivec2(0, 0)

proc buildFooterButtons*(panelRect: IRect): seq[FooterButton] =
  ## Build footer buttons for playback controls.
  let
    footerTop = panelRect.y.int32 + panelRect.h.int32 - FooterHeight.int32
    innerHeight = FooterHeight.float32 - FooterPadding * 2.0'f
    playPauseIcon =
      if play:
        "icon_pause"
      else:
        "icon_play"
    playPauseLabel =
      if play:
        "Pause"
      else:
        "Play"
  var buttons: seq[FooterButton] = @[]
  var buttonDefs = footerButtonDefs
  buttonDefs[0] = (FooterPlayPause, playPauseIcon, playPauseLabel)

  var
    totalWidth = 0.0'f
    buttonWidths: seq[float32] = @[]
  for (_, iconKey, labelText) in buttonDefs:
    var width = FooterButtonPaddingX * 2.0'f
    if iconKey.len > 0 and iconKey in bxy:
      if iconKey notin footerIconSizes:
        let size = bxy.getImageSize(iconKey)
        footerIconSizes[iconKey] = ivec2(size.x.int32, size.y.int32)
      let
        iconSize = footerIconSizes[iconKey]
        scale = min(1.0'f, innerHeight / iconSize.y.float32)
      width += iconSize.x.float32 * scale
    elif labelText.len > 0:
      let
        cached = ensureLabel("footer_btn", labelText, footerBtnLabelStyle)
        labelSize = cached.size
        scale = min(1.0'f, innerHeight / labelSize.y.float32)
      width += labelSize.x.float32 * scale
    buttonWidths.add(width)
    totalWidth += width

  totalWidth += FooterButtonGap * (buttonWidths.len - 1).float32

  var x = panelRect.x.float32 + (panelRect.w.float32 - totalWidth) / 2.0'f
  let y = footerTop.float32 + FooterPadding

  for i, (kind, iconKey, labelText) in buttonDefs:
    let width = buttonWidths[i]
    var button = FooterButton(
      kind: kind,
      rect: IRect(
        x: x.int32,
        y: y.int32,
        w: width.int32,
        h: innerHeight.int32
      ),
      isPressed: false
    )
    if iconKey.len > 0 and iconKey in bxy:
      button.iconKey = iconKey
      button.iconSize = footerIconSizes[iconKey]
    if labelText.len > 0:
      let cached = ensureLabel("footer_btn", labelText, footerBtnLabelStyle)
      button.labelKey = cached.imageKey
      button.labelSize = cached.size
    button.isPressed =
      case kind
      of FooterPlayPause:
        play
      of FooterStep:
        false
      of FooterSlow:
        abs(playSpeed - SlowPlaySpeed) <= PlaySpeedEpsilon
      of FooterFast:
        abs(playSpeed - FastPlaySpeed) <= PlaySpeedEpsilon
      of FooterFaster:
        abs(playSpeed - FasterPlaySpeed) <= PlaySpeedEpsilon
      of FooterSuper:
        abs(playSpeed - SuperPlaySpeed) <= PlaySpeedEpsilon
    buttons.add(button)
    x += width + FooterButtonGap

  buttons

proc centerIn(rect: IRect, size: Vec2): Vec2 =
  ## Return the centered position for a size inside a rect.
  vec2(
    rect.x.float32 + (rect.w.float32 - size.x) / 2.0'f,
    rect.y.float32 + (rect.h.float32 - size.y) / 2.0'f
  )

proc drawFooter*(panelRect: IRect, buttons: seq[FooterButton]) =
  ## Draw the footer ribbon and its control buttons.
  pushSemanticContext("Footer")
  let footerTop =
    panelRect.y.float32 + panelRect.h.float32 - FooterHeight.float32

  bxy.drawRect(
    rect = Rect(
      x: panelRect.x.float32,
      y: footerTop,
      w: panelRect.w.float32,
      h: FooterHeight.float32
    ),
    color = UiBgHeader
  )
  bxy.drawRect(
    rect = Rect(
      x: panelRect.x.float32,
      y: footerTop,
      w: panelRect.w.float32,
      h: FooterBorderHeight
    ),
    color = UiBorderBright
  )

  let innerHeight = FooterHeight.float32 - FooterPadding * 2.0'f
  for button in buttons:
    let backgroundColor =
      if button.isPressed:
        UiBgButtonActive
      else:
        UiBgButton
    bxy.drawRect(
      rect = Rect(
        x: button.rect.x.float32,
        y: button.rect.y.float32,
        w: button.rect.w.float32,
        h: button.rect.h.float32
      ),
      color = backgroundColor
    )
    bxy.drawRect(
      rect = Rect(
        x: button.rect.x.float32,
        y: button.rect.y.float32,
        w: button.rect.w.float32,
        h: FooterBorderHeight
      ),
      color = UiBorder
    )
    bxy.drawRect(
      rect = Rect(
        x: button.rect.x.float32,
        y:
          button.rect.y.float32 +
          button.rect.h.float32 -
          FooterBorderHeight,
        w: button.rect.w.float32,
        h: FooterBorderHeight
      ),
      color = UiBorder
    )

    if button.iconKey.len > 0 and button.iconKey in bxy:
      let
        scale = min(1.0'f, innerHeight / button.iconSize.y.float32)
        iconSize = vec2(
          button.iconSize.x.float32 * scale,
          button.iconSize.y.float32 * scale
        )
        iconPos =
          centerIn(button.rect, iconSize) +
          vec2(
            FooterIconCenterShiftX,
            FooterIconCenterShiftY
          ) * scale
      drawUiImageScaled(button.iconKey, iconPos, iconSize)
    elif button.labelKey.len > 0 and button.labelKey in bxy:
      let
        shift =
          if button.kind == FooterFaster:
            vec2(FooterIconCenterShiftX, FooterIconCenterShiftY)
          else:
            vec2(0.0'f, 0.0'f)
        labelSize = vec2(
          button.labelSize.x.float32,
          button.labelSize.y.float32
        )
        labelPos = centerIn(button.rect, labelSize) + shift
      drawUiImageScaled(button.labelKey, labelPos, labelSize)

  popSemanticContext()

proc drawFooterHudLabel(
  panelRect: IRect,
  key: string,
  labelSize: IVec2,
  xOffset: float32
) =
  ## Draw a cached footer HUD label at a horizontal offset.
  let
    footerTop =
      panelRect.y.float32 + panelRect.h.float32 - FooterHeight.float32
    innerHeight = FooterHeight.float32 - FooterPadding * 2.0'f
    scale = min(1.0'f, innerHeight / labelSize.y.float32)
    pos = vec2(
      panelRect.x.float32 + xOffset,
      footerTop +
        FooterPadding +
        (innerHeight - labelSize.y.float32 * scale) * 0.5'f +
        FooterHudLabelYShift
    )
    size = vec2(
      labelSize.x.float32 * scale,
      labelSize.y.float32 * scale
    )
  drawUiImageScaled(key, pos, size)

proc drawSelectionLabel*(panelRect: IRect) =
  ## Draw the selected thing label in the footer HUD area.
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
      for key, corpseCount in thing.inventory.pairs:
        if corpseCount > 0:
          label &= " (" & $key & " " & $corpseCount & ")"
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
      if name.len > 0:
        name
      else:
        $t.kind

  var label = ""
  let selectedThing = env.grid[selectedPos.x][selectedPos.y]
  if not isNil(selectedThing):
    label = displayNameFor(selectedThing)
    appendResourceCount(label, selectedThing)
  else:
    let bgThing = env.backgroundGrid[selectedPos.x][selectedPos.y]
    if not isNil(bgThing):
      label = displayNameFor(bgThing)
      appendResourceCount(label, bgThing)

  if label.len == 0:
    return
  let cached = ensureLabel("info_label", label, infoLabelStyle)
  drawFooterHudLabel(
    panelRect,
    cached.imageKey,
    cached.size,
    FooterHudPadding
  )

proc drawStepLabel*(panelRect: IRect) =
  ## Draw the current step counter in the footer HUD area.
  let currentStep = env.currentStep
  if currentStep != stepLabelLastValue or stepLabelKey.len == 0:
    stepLabelLastValue = currentStep
    invalidateLabel("hud_step")
    let text = "Step: " & $currentStep
    let cached = ensureLabelKeyed(
      "hud_step",
      "hud_step",
      text,
      infoLabelStyle
    )
    stepLabelKey = cached.imageKey
    stepLabelSize = cached.size
  if stepLabelKey.len == 0:
    return
  let
    innerHeight = FooterHeight.float32 - FooterPadding * 2.0'f
    scale = min(1.0'f, innerHeight / stepLabelSize.y.float32)
    labelWidth = stepLabelSize.x.float32 * scale
    xOffset = panelRect.w.float32 - labelWidth - FooterHudPadding
  drawFooterHudLabel(panelRect, stepLabelKey, stepLabelSize, xOffset)

proc drawControlModeLabel*(panelRect: IRect) =
  ## Draw the current control mode label in the footer HUD area.
  let mode = playerTeam
  if mode != controlModeLabelLastValue or controlModeLabelKey.len == 0:
    controlModeLabelLastValue = mode
    invalidateLabel("hud_control_mode")
    let text =
      case mode
      of -1:
        "Observer"
      of 0 .. 7:
        "Team " & $mode
      else:
        "Unknown"
    let cached = ensureLabelKeyed(
      "hud_control_mode",
      "hud_control_mode",
      text,
      infoLabelStyle
    )
    controlModeLabelKey = cached.imageKey
    controlModeLabelSize = cached.size
  if controlModeLabelKey.len == 0:
    return
  let
    innerHeight = FooterHeight.float32 - FooterPadding * 2.0'f
    scale = min(1.0'f, innerHeight / controlModeLabelSize.y.float32)
    labelWidth = controlModeLabelSize.x.float32 * scale
    stepLabelWidth = stepLabelSize.x.float32 * scale
    xOffset =
      panelRect.w.float32 -
      labelWidth -
      stepLabelWidth -
      FooterHudPadding * 2.0'f -
      ResourceBarXStart
  drawFooterHudLabel(
    panelRect,
    controlModeLabelKey,
    controlModeLabelSize,
    xOffset
  )
