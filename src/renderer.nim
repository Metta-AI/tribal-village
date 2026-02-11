import
  boxy, pixie, vmath, windy, tables,
  std/[algorithm, math, os, strutils],
  common, constants, environment, formations, semantic

# Infection system constants
const
  HeartPlusThreshold = 9           # Switch to compact heart counter after this many
  HeartCountFontPath = "data/Inter-Regular.ttf"
  HeartCountFontSize: float32 = 40
  HeartCountPadding = 6
  SpriteScale = 1.0 / 200.0

  # Idle animation constants
  IdleAnimationSpeed = 2.0        # Breathing cycles per second
  IdleAnimationAmplitude = 0.02   # Scale variation (+/- 2% from base)
  IdleAnimationPhaseScale = 0.7   # Phase offset multiplier for variation between units

  # Resource depletion animation constants
  DepletionScaleMin = 0.5         # Minimum scale when resource is empty (50% of full size)
  DepletionScaleMax = 1.0         # Maximum scale when resource is full (100%)

  # Health bar fade constants
  HealthBarFadeInDuration = 5     # Steps to fade in after taking damage
  HealthBarVisibleDuration = 60   # Steps to stay fully visible after damage
  HealthBarFadeOutDuration = 30   # Steps to fade out after visible period
  HealthBarMinAlpha = 0.3         # Minimum alpha when faded out (never fully invisible)

var
  heartCountImages: Table[int, string] = initTable[int, string]()
  overlayLabelImages: Table[string, string] = initTable[string, string]()
  infoLabelImages: Table[string, string] = initTable[string, string]()
  infoLabelSizes: Table[string, IVec2] = initTable[string, IVec2]()
  stepLabelKey = ""
  stepLabelLastValue = -1
  stepLabelSize = ivec2(0, 0)
  controlModeLabelKey = ""
  controlModeLabelLastValue = -2  # Start different from any valid value
  controlModeLabelSize = ivec2(0, 0)
  footerLabelImages: Table[string, string] = initTable[string, string]()
  footerLabelSizes: Table[string, IVec2] = initTable[string, IVec2]()
  footerIconSizes: Table[string, IVec2] = initTable[string, IVec2]()
  # Damage number label cache
  damageNumberImages: Table[string, string] = initTable[string, string]()
  damageNumberSizes: Table[string, IVec2] = initTable[string, IVec2]()
  # Control group badge cache
  controlGroupBadgeImages: Table[int, string] = initTable[int, string]()
  controlGroupBadgeSizes: Table[int, IVec2] = initTable[int, IVec2]()

const
  # Damage number rendering constants
  DamageNumberFontPath = "data/Inter-Regular.ttf"
  DamageNumberFontSize: float32 = 28
  DamageNumberFloatHeight: float32 = 0.8  # World units to float upward
  # Control group badge constants
  ControlGroupBadgeFontPath = "data/Inter-Regular.ttf"
  ControlGroupBadgeFontSize: float32 = 24
  ControlGroupBadgePadding = 4.0'f32
  ControlGroupBadgeScale = 1.0 / 180.0  # Scale for rendering in world space

  # Building smoke/chimney effect constants
  SmokeParticleCount = 3           # Number of smoke particles per building
  SmokeParticleScale = 1.0 / 500.0 # Smaller than sprites for wispy look
  SmokeBaseHeight = -0.4           # Start position above building center
  SmokeMaxHeight = 1.2             # How high particles rise
  SmokeAnimSpeed = 12              # Frames per animation cycle
  SmokeDriftAmount = 0.15          # Horizontal drift amplitude

  # Weather effect constants
  WeatherParticleDensity = 0.015   # Particles per tile (0.015 = ~1 particle per 67 tiles)
  WeatherParticleScale = 1.0 / 600.0  # Small particles for weather

  # Rain constants
  RainFallSpeed = 0.25'f32         # World units per frame (downward)
  RainDriftSpeed = 0.03'f32        # Slight horizontal drift
  RainCycleFrames = 48             # Frames for one full rain cycle
  RainAlpha = 0.5'f32              # Rain particle opacity
  RainStreakLength = 3             # Number of particles per streak

  # Wind constants
  WindBlowSpeed = 0.18'f32         # World units per frame (horizontal)
  WindDriftSpeed = 0.02'f32        # Vertical drift
  WindCycleFrames = 64             # Frames for one full wind cycle
  WindAlpha = 0.35'f32             # Wind particle opacity (subtle)

  # Fire flicker constants
  LanternFlickerSpeed1 = 0.15'f32    # Primary flicker wave speed
  LanternFlickerSpeed2 = 0.23'f32    # Secondary flicker wave speed (faster, irregular)
  LanternFlickerSpeed3 = 0.07'f32    # Tertiary slow wave for organic feel
  LanternFlickerAmplitude = 0.12'f32 # Brightness variation (+/- 12%)
  MagmaGlowSpeed = 0.04'f32          # Slower pulsing for magma pools
  MagmaGlowAmplitude = 0.08'f32      # Subtle glow variation (+/- 8%)

type FloorSpriteKind = enum
  FloorBase
  FloorCave
  FloorDungeon
  FloorSnow


const UnitClassSpriteKeys: array[AgentUnitClass, string] = [
  "",                              # UnitVillager (uses role-based key)
  "oriented/man_at_arms",          # UnitManAtArms
  "oriented/archer",               # UnitArcher
  "oriented/scout",                # UnitScout
  "oriented/knight",               # UnitKnight
  "oriented/monk",                 # UnitMonk
  "oriented/battering_ram",        # UnitBatteringRam
  "oriented/mangonel",             # UnitMangonel
  "",                              # UnitTrebuchet (packed/unpacked)
  "oriented/goblin",               # UnitGoblin
  "oriented/boat",                 # UnitBoat
  "oriented/trade_cog",            # UnitTradeCog
  "oriented/samurai",              # UnitSamurai
  "oriented/longbowman",           # UnitLongbowman
  "oriented/cataphract",           # UnitCataphract
  "oriented/woad_raider",          # UnitWoadRaider
  "oriented/teutonic_knight",      # UnitTeutonicKnight
  "oriented/huskarl",              # UnitHuskarl
  "oriented/mameluke",             # UnitMameluke
  "oriented/janissary",            # UnitJanissary
  "oriented/king",                 # UnitKing
  "oriented/man_at_arms",          # UnitLongSwordsman
  "oriented/man_at_arms",          # UnitChampion
  "oriented/scout",                # UnitLightCavalry
  "oriented/scout",                # UnitHussar
  "oriented/archer",               # UnitCrossbowman
  "oriented/archer",               # UnitArbalester
  "oriented/boat",                 # UnitGalley (uses boat sprite)
  "oriented/boat",                 # UnitFireShip (uses boat sprite)
  "oriented/boat",                 # UnitFishingShip (uses boat sprite)
  "oriented/boat",                 # UnitTransportShip (uses boat sprite)
  "oriented/boat",                 # UnitDemoShip (uses boat sprite)
  "oriented/boat",                 # UnitCannonGalleon (uses boat sprite)
  "oriented/mangonel",             # UnitScorpion (uses mangonel sprite)
  "oriented/knight",               # UnitCavalier (uses knight sprite)
  "oriented/knight",               # UnitPaladin (uses knight sprite)
  "oriented/cataphract",           # UnitCamel (uses cataphract sprite)
  "oriented/cataphract",           # UnitHeavyCamel (uses cataphract sprite)
  "oriented/cataphract",           # UnitImperialCamel (uses cataphract sprite)
  "oriented/archer",               # UnitSkirmisher (uses archer sprite)
  "oriented/archer",               # UnitEliteSkirmisher (uses archer sprite)
  "oriented/archer",               # UnitCavalryArcher (uses archer sprite)
  "oriented/archer",               # UnitHeavyCavalryArcher (uses archer sprite)
  "oriented/janissary",            # UnitHandCannoneer (uses janissary sprite)
]

const CliffDrawOrder = [
  CliffEdgeN,
  CliffEdgeE,
  CliffEdgeS,
  CliffEdgeW,
  CliffCornerInNE,
  CliffCornerInSE,
  CliffCornerInSW,
  CliffCornerInNW,
  CliffCornerOutNE,
  CliffCornerOutSE,
  CliffCornerOutSW,
  CliffCornerOutNW
]

var
  floorSpritePositions: array[FloorSpriteKind, seq[IVec2]]
  waterPositions: seq[IVec2] = @[]
  shallowWaterPositions: seq[IVec2] = @[]
  renderCacheGeneration = -1
  # Fog of war visibility buffer - reused across frames to avoid allocation overhead
  fogVisibility: array[MapWidth, array[MapHeight, bool]]
  fogLastViewport: ViewportBounds  # Track last cleared region for efficient reset

const
  InfoLabelFontPath = HeartCountFontPath
  InfoLabelFontSize: float32 = 54
  InfoLabelPadding = 18
  FooterFontPath = HeartCountFontPath
  FooterFontSize: float32 = 26
  FooterPadding = 10.0'f32
  FooterButtonPaddingX = 18.0'f32
  FooterButtonGap = 12.0'f32
  FooterLabelPadding = 4.0'f32
  FooterHudPadding = 12.0'f32

template setupCtxFont(ctx: untyped, fontPath: string, fontSize: float32) =
  ctx.font = fontPath
  ctx.fontSize = fontSize
  ctx.textBaseline = TopBaseline

proc renderTextLabel(text: string, fontPath: string, fontSize: float32,
                     padding: float32, bgAlpha: float32): (Image, IVec2) =
  var measureCtx = newContext(1, 1)
  setupCtxFont(measureCtx, fontPath, fontSize)
  let w = max(1, (measureCtx.measureText(text).width + padding * 2).int)
  let h = max(1, (fontSize + padding * 2).int)
  var ctx = newContext(w, h)
  setupCtxFont(ctx, fontPath, fontSize)
  if bgAlpha > 0:
    ctx.fillStyle.color = color(0, 0, 0, bgAlpha)
    ctx.fillRect(0, 0, w.float32, h.float32)
  ctx.fillStyle.color = color(1, 1, 1, 1)
  ctx.fillText(text, vec2(padding, padding))
  result = (ctx.image, ivec2(w, h))

proc getTeamColor*(env: Environment, teamId: int,
                   fallback: Color = color(0.6, 0.6, 0.6, 1.0)): Color =
  ## Get team color from environment, with fallback for invalid team IDs.
  if teamId >= 0 and teamId < env.teamColors.len:
    env.teamColors[teamId]
  else:
    fallback

proc getHealthBarColor*(ratio: float32): Color =
  ## Get health bar color based on HP ratio. Gradient from green (full) to red (low).
  ## Green (1.0) -> Yellow (0.5) -> Red (0.0)
  if ratio > 0.5:
    # Green to yellow: ratio 1.0->0.5 maps to green->yellow
    let t = (ratio - 0.5) * 2.0  # t: 1.0 at full, 0.0 at half
    color(1.0 - t * 0.9, 0.8, 0.1, 1.0)  # from yellow(1.0,0.8,0.1) to green(0.1,0.8,0.1)
  else:
    # Yellow to red: ratio 0.5->0.0 maps to yellow->red
    let t = ratio * 2.0  # t: 1.0 at half, 0.0 at empty
    color(1.0, t * 0.8, 0.1, 1.0)  # from red(1.0,0.0,0.1) to yellow(1.0,0.8,0.1)

proc getHealthBarAlpha*(currentStep: int, lastAttackedStep: int): float32 =
  ## Calculate health bar alpha based on damage recency.
  ## Fades in quickly after damage, stays visible, then fades out gradually.
  let stepsSinceDamage = currentStep - lastAttackedStep
  if lastAttackedStep <= 0:
    # Never attacked - show at minimum alpha
    return HealthBarMinAlpha
  if stepsSinceDamage < HealthBarFadeInDuration:
    # Fade in phase: 0.0 -> 1.0 over FadeInDuration steps
    let progress = stepsSinceDamage.float32 / HealthBarFadeInDuration.float32
    return HealthBarMinAlpha + (1.0 - HealthBarMinAlpha) * progress
  elif stepsSinceDamage < HealthBarFadeInDuration + HealthBarVisibleDuration:
    # Fully visible phase
    return 1.0
  elif stepsSinceDamage < HealthBarFadeInDuration + HealthBarVisibleDuration + HealthBarFadeOutDuration:
    # Fade out phase: 1.0 -> MinAlpha over FadeOutDuration steps
    let fadeProgress = (stepsSinceDamage - HealthBarFadeInDuration - HealthBarVisibleDuration).float32 / HealthBarFadeOutDuration.float32
    return 1.0 - (1.0 - HealthBarMinAlpha) * fadeProgress
  else:
    # Fully faded out (to minimum alpha)
    return HealthBarMinAlpha

proc drawSegmentBar*(basePos: Vec2, offset: Vec2, ratio: float32,
                     filledColor, emptyColor: Color, segments = 5, alpha = 1.0'f32) =
  let filled = int(ceil(ratio * segments.float32))
  const segStep = 0.16'f32
  let origin = basePos + vec2(-segStep * (segments.float32 - 1) / 2 + offset.x, offset.y)
  for i in 0 ..< segments:
    let baseColor = if i < filled: filledColor else: emptyColor
    let fadedColor = color(baseColor.r, baseColor.g, baseColor.b, baseColor.a * alpha)
    bxy.drawImage("floor", origin + vec2(segStep * i.float32, 0),
                  angle = 0, scale = 1/500,
                  tint = fadedColor)

proc drawBuildingSmoke*(buildingPos: Vec2, buildingId: int) =
  ## Draw procedural smoke particles rising from an active building.
  ## Uses deterministic noise based on frame and building ID for consistent animation.
  for i in 0 ..< SmokeParticleCount:
    # Each particle has a unique phase offset based on building ID and particle index
    let phase = (buildingId * 7 + i * 13) mod 100
    let cycleFrame = (frame + phase * 3) mod (SmokeAnimSpeed * SmokeParticleCount)

    # Calculate particle's position in its rise cycle (0.0 to 1.0)
    let particleCycle = (cycleFrame + i * SmokeAnimSpeed) mod (SmokeAnimSpeed * SmokeParticleCount)
    let t = particleCycle.float32 / (SmokeAnimSpeed * SmokeParticleCount).float32

    # Vertical rise with slight acceleration at start
    let rise = t * t * SmokeMaxHeight

    # Horizontal drift using sine wave for gentle swaying
    let driftPhase = (frame.float32 * 0.05 + phase.float32 * 0.1 + i.float32 * 2.1)
    let drift = sin(driftPhase) * SmokeDriftAmount * t

    # Position particle above building
    let particlePos = buildingPos + vec2(drift, SmokeBaseHeight - rise)

    # Fade out as particle rises (full opacity at start, transparent at top)
    let alpha = (1.0 - t) * 0.6

    # Slight size variation based on rise (particles expand as they rise)
    let sizeScale = SmokeParticleScale * (1.0 + t * 0.5)

    # Gray-white smoke color with slight variation per particle
    let grayVal = 0.7 + (i.float32 * 0.1)
    let smokeTint = color(grayVal, grayVal, grayVal, alpha)

    bxy.drawImage("floor", particlePos, angle = 0, scale = sizeScale, tint = smokeTint)

type FooterButtonKind* = enum
  FooterPlayPause
  FooterStep
  FooterSlow
  FooterFast
  FooterFaster
  FooterSuper

type FooterButton* = object
  kind*: FooterButtonKind
  rect*: Rect
  iconKey*: string
  iconSize*: IVec2
  labelKey*: string
  labelSize*: IVec2
  active*: bool

type QueueCancelButton* = object
  ## Button to cancel a queued unit in the production queue
  rect*: Rect
  queueIndex*: int
  buildingPos*: IVec2

var queueCancelButtons*: seq[QueueCancelButton] = @[]

proc buildFooterButtons*(panelRect: IRect): seq[FooterButton] =
  let iconKeys = [if play: "ui/pause" else: "ui/play", "ui/stepForward", "ui/turtle", "ui/speed", "", "ui/rabbit"]
  let labels = ["Pause", "Step", "Slow", "Fast", ">>", "Super"]
  var buttonWidths: array[labels.len, float32]
  var labelKeys: array[labels.len, string]
  var labelSizes: array[labels.len, IVec2]
  var iconSizes: array[labels.len, IVec2]
  var totalWidth = 0.0'f32
  for i, label in labels:
    var labelKey = ""
    var labelSize = ivec2(0, 0)
    if label in footerLabelImages:
      labelKey = footerLabelImages[label]
      labelSize = footerLabelSizes[label]
    else:
      let (image, size) = renderTextLabel(label, FooterFontPath, FooterFontSize,
                                          FooterLabelPadding, 0.0)
      labelKey = "footer_label/" & label.replace(" ", "_").replace("/", "_")
      bxy.addImage(labelKey, image)
      labelSize = size
      footerLabelImages[label] = labelKey
      footerLabelSizes[label] = labelSize
    labelKeys[i] = labelKey
    labelSizes[i] = labelSize
    let width = labelSize.x.float32 + FooterButtonPaddingX * 2.0
    buttonWidths[i] = width
    let iconKey = iconKeys[i]
    var iconSize = ivec2(0, 0)
    if iconKey.len > 0:
      if iconKey in footerIconSizes:
        iconSize = footerIconSizes[iconKey]
      else:
        let path = "data/" & iconKey & ".png"
        if fileExists(path):
          let image = readImage(path)
          iconSize = ivec2(image.width, image.height)
        footerIconSizes[iconKey] = iconSize
    iconSizes[i] = iconSize
    totalWidth += width
    if i < labels.len - 1:
      totalWidth += FooterButtonGap
  let startX = panelRect.x.float32 + (panelRect.w.float32 - totalWidth) * 0.5
  var x = startX
  for i, label in labels:
    let kind = case i
      of 0: FooterPlayPause
      of 1: FooterStep
      of 2: FooterSlow
      of 3: FooterFast
      of 4: FooterFaster
      else: FooterSuper
    let rect = Rect(
      x: x,
      y: panelRect.y.float32 + panelRect.h.float32 - FooterHeight.float32 + FooterPadding,
      w: buttonWidths[i],
      h: FooterHeight.float32 - FooterPadding * 2.0
    )
    let speedForKind = case kind
      of FooterSlow: SlowPlaySpeed
      of FooterFast: FastPlaySpeed
      of FooterFaster: FasterPlaySpeed
      of FooterSuper: SuperPlaySpeed
      else: -1.0'f32
    let active = speedForKind > 0 and abs(playSpeed - speedForKind) < 0.0001
    result.add(FooterButton(
      kind: kind,
      rect: rect,
      iconKey: iconKeys[i],
      iconSize: iconSizes[i],
      labelKey: labelKeys[i],
      labelSize: labelSizes[i],
      active: active
    ))
    x += buttonWidths[i] + FooterButtonGap

proc drawFooter*(panelRect: IRect, buttons: seq[FooterButton]) =
  let fy = panelRect.y.float32 + panelRect.h.float32 - FooterHeight.float32
  bxy.drawRect(rect = Rect(x: panelRect.x.float32, y: fy,
               w: panelRect.w.float32, h: FooterHeight.float32),
               color = color(0.12, 0.16, 0.2, 0.9))

  # Semantic capture: footer panel
  pushSemanticContext("Footer")
  capturePanel("Footer", vec2(panelRect.x.float32, fy),
               vec2(panelRect.w.float32, FooterHeight.float32))

  let mousePos = window.mousePos.vec2
  for button in buttons:
    let hovered = mousePos.x >= button.rect.x and mousePos.x <= button.rect.x + button.rect.w and
      mousePos.y >= button.rect.y and mousePos.y <= button.rect.y + button.rect.h
    let baseColor = if button.active: color(0.2, 0.5, 0.7, 0.95) else: color(0.2, 0.24, 0.28, 0.9)
    let drawColor = if hovered: color(baseColor.r + 0.08, baseColor.g + 0.08, baseColor.b + 0.08, baseColor.a) else: baseColor
    bxy.drawRect(rect = button.rect, color = drawColor)
    template centerIn(r: Rect, sz: Vec2): Vec2 =
      vec2(r.x + (r.w - sz.x) * 0.5, r.y + (r.h - sz.y) * 0.5)

    # Semantic capture: button
    let buttonName = case button.kind
      of FooterPlayPause: (if play: "Pause" else: "Play")
      of FooterStep: "Step"
      of FooterSlow: "Slow"
      of FooterFast: "Fast"
      of FooterFaster: "Faster"
      of FooterSuper: "Super"
    captureButton(buttonName, vec2(button.rect.x, button.rect.y),
                  vec2(button.rect.w, button.rect.h))

    if button.iconKey.len > 0 and button.iconSize.x > 0 and button.iconSize.y > 0:
      let sc = min(1.0'f32, min(button.rect.w, button.rect.h) * 0.6 /
               max(button.iconSize.x.float32, button.iconSize.y.float32))
      let iconPos = centerIn(button.rect, vec2(button.iconSize.x.float32 * sc,
                    button.iconSize.y.float32 * sc)) + vec2(8.0, 9.0) * sc
      bxy.drawImage(button.iconKey, iconPos, angle = 0, scale = sc)
    else:
      let shift = if button.kind == FooterFaster: vec2(8.0, 9.0) else: vec2(0.0, 0.0)
      bxy.drawImage(button.labelKey,
        centerIn(button.rect, vec2(button.labelSize.x.float32, button.labelSize.y.float32)) + shift,
        angle = 0, scale = 1)

  popSemanticContext()

proc rebuildRenderCaches() =
  for kind in FloorSpriteKind:
    floorSpritePositions[kind].setLen(0)
  waterPositions.setLen(0)
  shallowWaterPositions.setLen(0)

  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      let biome = env.biomes[x][y]
      let floorKind = case biome
        of BiomeCavesType: FloorCave
        of BiomeDungeonType:
          var v = uint32(x) * 374761393'u32 + uint32(y) * 668265263'u32
          v = (v xor (v shr 13)) * 1274126177'u32
          if ((v xor (v shr 16)) mod 100) < 35: FloorDungeon else: FloorBase
        of BiomeSnowType: FloorSnow
        else: FloorBase
      floorSpritePositions[floorKind].add(ivec2(x, y))

      if env.terrain[x][y] == Water:
        waterPositions.add(ivec2(x, y))
      elif env.terrain[x][y] == ShallowWater:
        shallowWaterPositions.add(ivec2(x, y))
  renderCacheGeneration = env.mapGeneration

proc drawFloor*() =
  if renderCacheGeneration != env.mapGeneration:
    rebuildRenderCaches()
  # Draw the floor tiles everywhere first as the base layer
  # Use viewport culling to skip off-screen tiles
  let ambient = getAmbientLight()
  for floorKind in FloorSpriteKind:
    let floorSprite = case floorKind
      of FloorCave: "cave"
      of FloorDungeon: "dungeon"
      of FloorSnow: "snow"
      of FloorBase: "floor"
    for pos in floorSpritePositions[floorKind]:
      if not isInViewport(pos):
        continue
      let bc = combinedTileTint(env, pos.x, pos.y)
      # Apply ambient light to tile color
      let lit = applyAmbient(bc.r, bc.g, bc.b, bc.intensity, ambient)
      bxy.drawImage(floorSprite, pos.vec2, angle = 0, scale = SpriteScale,
        tint = color(min(lit.r * lit.i, 1.5), min(lit.g * lit.i, 1.5),
                     min(lit.b * lit.i, 1.5), 1.0))

proc drawTerrain*() =
  # Only iterate over visible tiles for viewport culling
  if not currentViewport.valid:
    return
  for x in currentViewport.minX .. currentViewport.maxX:
    for y in currentViewport.minY .. currentViewport.maxY:
      let terrain = env.terrain[x][y]
      if terrain == Water: continue
      let spriteKey = terrainSpriteKey(terrain)
      if spriteKey.len > 0 and spriteKey in bxy:
        bxy.drawImage(spriteKey, ivec2(x, y).vec2, angle = 0, scale = SpriteScale)

proc ensureHeartCountLabel(count: int): string =
  ## Cache a simple "x N" label for large heart counts so we can reuse textures.
  if count <= 0: return ""
  if count in heartCountImages: return heartCountImages[count]
  let (image, _) = renderTextLabel("x " & $count, HeartCountFontPath,
                                   HeartCountFontSize, HeartCountPadding.float32, 0.7)
  let key = "heart_count/" & $count
  bxy.addImage(key, image)
  heartCountImages[count] = key
  result = key

proc ensureControlGroupBadge(groupNum: int): (string, IVec2) =
  ## Cache a control group badge label (1-9) for display above units.
  if groupNum < 0 or groupNum >= 10: return ("", ivec2(0, 0))
  if groupNum in controlGroupBadgeImages:
    return (controlGroupBadgeImages[groupNum], controlGroupBadgeSizes[groupNum])
  # Display 1-9 for groups 0-8, 0 for group 9
  let displayNum = if groupNum == 9: 0 else: groupNum + 1
  let (image, size) = renderTextLabel($displayNum, ControlGroupBadgeFontPath,
                                      ControlGroupBadgeFontSize, ControlGroupBadgePadding, 0.7)
  let key = "control_group/" & $groupNum
  bxy.addImage(key, image)
  controlGroupBadgeImages[groupNum] = key
  controlGroupBadgeSizes[groupNum] = size
  result = (key, size)

let wallSprites = block:
  var sprites = newSeq[string](16)
  for i in 0 .. 15:
    var suffix = ""
    if (i and 8) != 0: suffix.add("n")
    if (i and 4) != 0: suffix.add("w")
    if (i and 2) != 0: suffix.add("s")
    if (i and 1) != 0: suffix.add("e")

    if suffix.len > 0:
      sprites[i] = "oriented/wall." & suffix
    else:
      sprites[i] = "oriented/wall"
  sprites

type WallTile = enum
  WallE = 1,
  WallS = 2,
  WallW = 4,
  WallN = 8,
  WallSE = 2 or 1,
  WallNW = 8 or 4,

proc drawWalls*() =
  template hasWall(x: int, y: int): bool =
    x >= 0 and x < MapWidth and
    y >= 0 and y < MapHeight and
    not isNil(env.grid[x][y]) and
    env.grid[x][y].kind == Wall

  if not currentViewport.valid:
    return
  var wallFills: seq[IVec2]
  let wallTint = color(0.3, 0.3, 0.3, 1.0)
  # Only iterate over visible tiles for viewport culling
  for x in currentViewport.minX .. currentViewport.maxX:
    for y in currentViewport.minY .. currentViewport.maxY:
      let thing = env.grid[x][y]
      if not isNil(thing) and thing.kind == Wall:
        var tile = 0'u16
        if hasWall(x, y + 1): tile = tile or WallS.uint16
        if hasWall(x + 1, y): tile = tile or WallE.uint16
        if hasWall(x, y - 1): tile = tile or WallN.uint16
        if hasWall(x - 1, y): tile = tile or WallW.uint16

        if (tile and WallSE.uint16) == WallSE.uint16 and
            hasWall(x + 1, y + 1):
          wallFills.add(ivec2(x.int32, y.int32))
          if (tile and WallNW.uint16) == WallNW.uint16 and
              hasWall(x - 1, y - 1) and
              hasWall(x - 1, y + 1) and
              hasWall(x + 1, y - 1):
            continue

        let wallSpriteKey = wallSprites[tile]
        bxy.drawImage(wallSpriteKey, vec2(x.float32, y.float32),
                     angle = 0, scale = SpriteScale, tint = wallTint)

  let fillSpriteKey = "oriented/wall.fill"
  for fillPos in wallFills:
    bxy.drawImage(fillSpriteKey, fillPos.vec2 + vec2(0.5, 0.3),
                  angle = 0, scale = SpriteScale, tint = wallTint)

const OrientationDirKeys = [
  "n",  # N
  "s",  # S
  "w",  # W
  "e",  # E
  "nw", # NW
  "ne", # NE
  "sw", # SW
  "se"  # SE
]
const TumorDirKeys = [
  "n", # N
  "s", # S
  "w", # W
  "e", # E
  "w", # NW
  "e", # NE
  "w", # SW
  "e"  # SE
]

proc drawObjects*() =
  var teamPopCounts: array[MapRoomObjectsTeams, int]
  var teamHouseCounts: array[MapRoomObjectsTeams, int]
  for agent in env.agents:
    if isAgentAlive(env, agent):
      let teamId = getTeamId(agent)
      if teamId >= 0 and teamId < MapRoomObjectsTeams:
        inc teamPopCounts[teamId]
  for house in env.thingsByKind[House]:
    let teamId = house.teamId
    if teamId >= 0 and teamId < MapRoomObjectsTeams:
      inc teamHouseCounts[teamId]

  # Get ambient light for day/night cycle
  let ambient = getAmbientLight()

  for pos in env.actionTintPositions:
    if not isValidPos(pos) or not isInViewport(pos):
      continue
    if env.actionTintCountdown[pos.x][pos.y] > 0:
      let c = env.actionTintColor[pos.x][pos.y]
      # Apply ambient light to action tint overlay
      let lit = applyAmbient(c.r, c.g, c.b, 1.0, ambient)
      # Render the short-lived action overlay fully opaque so it sits above the
      # normal tint layer and clearly masks the underlying tile color.
      bxy.drawImage("floor", pos.vec2, angle = 0, scale = SpriteScale, tint = color(lit.r, lit.g, lit.b, 1.0))

  let waterKey = terrainSpriteKey(Water)

  # Draw water from terrain so agents can occupy those tiles while keeping visuals.
  # Deep water (center of rivers) renders darker, shallow water (edges) renders lighter.
  if renderCacheGeneration != env.mapGeneration:
    rebuildRenderCaches()
  if waterKey.len > 0:
    # Draw deep water (impassable) with ambient-lit tint
    let waterLit = applyAmbient(1.0, 1.0, 1.0, 1.0, ambient)
    let waterTint = color(waterLit.r * waterLit.i, waterLit.g * waterLit.i, waterLit.b * waterLit.i, 1.0)
    for pos in waterPositions:
      if isInViewport(pos):
        bxy.drawImage(waterKey, pos.vec2, angle = 0, scale = SpriteScale, tint = waterTint)
    # Draw shallow water (passable but slow) with lighter tint to distinguish
    let shallowLit = applyAmbient(0.6, 0.85, 0.95, 1.0, ambient)
    let shallowTint = color(shallowLit.r * shallowLit.i, shallowLit.g * shallowLit.i, shallowLit.b * shallowLit.i, 1.0)
    for pos in shallowWaterPositions:
      if isInViewport(pos):
        bxy.drawImage(waterKey, pos.vec2, angle = 0, scale = SpriteScale, tint = shallowTint)

  for kind in CliffDrawOrder:
    let spriteKey = thingSpriteKey(kind)
    if spriteKey.len > 0 and spriteKey in bxy:
      for cliff in env.thingsByKind[kind]:
        if isInViewport(cliff.pos):
          bxy.drawImage(spriteKey, cliff.pos.vec2, angle = 0, scale = SpriteScale)

  template drawThings(thingKind: ThingKind, body: untyped) =
    for it in env.thingsByKind[thingKind]:
      if not isInViewport(it.pos):
        continue
      let thing {.inject.} = it
      let thingPos {.inject.} = it.pos
      body

  # Resource depletion scale - shrinks nodes from 100% to 50% as resources deplete
  proc getResourceDepletionScale(thing: Thing): float32 =
    let (itemKey, maxAmount) = case thing.kind
      of Tree, Stump: (ItemWood, ResourceNodeInitial)
      of Wheat, Stubble: (ItemWheat, ResourceNodeInitial)
      of Stone, Stalagmite: (ItemStone, ResourceNodeInitial)
      of Gold: (ItemGold, ResourceNodeInitial)
      of Bush, Cactus: (ItemPlant, ResourceNodeInitial)
      of Fish: (ItemFish, ResourceNodeInitial)
      else: (ItemNone, 1)
    if itemKey == ItemNone or maxAmount <= 0:
      return SpriteScale
    let remaining = getInv(thing, itemKey)
    let ratio = remaining.float32 / maxAmount.float32
    # Scale from DepletionScaleMax (1.0) to DepletionScaleMin (0.5) based on remaining
    SpriteScale * (DepletionScaleMin + ratio * (DepletionScaleMax - DepletionScaleMin))

  for kind in [Tree, Wheat, Stubble]:
    let spriteKey = thingSpriteKey(kind)
    if spriteKey.len > 0 and spriteKey in bxy:
      for thing in env.thingsByKind[kind]:
        let pos = thing.pos
        if not isInViewport(pos):
          continue
        let depletionScale = getResourceDepletionScale(thing)
        bxy.drawImage(spriteKey, pos.vec2, angle = 0, scale = depletionScale)
        if isTileFrozen(pos, env):
          bxy.drawImage("frozen", pos.vec2, angle = 0, scale = depletionScale)

  # Draw unit shadows first (before agents, so shadows appear underneath)
  # Light source is NW, so shadows cast to SE (positive X and Y offset)
  let shadowTint = color(0.0, 0.0, 0.0, ShadowAlpha)
  let shadowOffset = vec2(ShadowOffsetX, ShadowOffsetY)
  for agent in env.agents:
    if not isAgentAlive(env, agent):
      continue
    let pos = agent.pos
    if not isValidPos(pos) or env.grid[pos.x][pos.y] != agent or not isInViewport(pos):
      continue
    let baseKey = block:
      let tbl = UnitClassSpriteKeys[agent.unitClass]
      if tbl.len > 0: tbl
      elif agent.unitClass == UnitTrebuchet:
        if agent.packed: "oriented/trebuchet_packed"
        else: "oriented/trebuchet_unpacked"
      else: # UnitVillager: role-based
        case agent.agentId mod MapAgentsPerTeam
        of 0, 1: "oriented/gatherer"
        of 2, 3: "oriented/builder"
        of 4, 5: "oriented/fighter"
        else: "oriented/gatherer"
    let dirKey = OrientationDirKeys[agent.orientation.int]
    let agentImage = baseKey & "." & dirKey
    let shadowSpriteKey = if agentImage in bxy: agentImage
                          elif baseKey & ".s" in bxy: baseKey & ".s"
                          else: ""
    if shadowSpriteKey.len > 0:
      # Draw shadow: offset from unit position, dark semi-transparent tint
      let shadowPos = pos.vec2 + shadowOffset
      bxy.drawImage(shadowSpriteKey, shadowPos, angle = 0,
                    scale = SpriteScale, tint = shadowTint)

  drawThings(Agent):
    let agent = thing
    let baseKey = block:
      let tbl = UnitClassSpriteKeys[agent.unitClass]
      if tbl.len > 0: tbl
      elif agent.unitClass == UnitTrebuchet:
        if agent.packed: "oriented/trebuchet_packed"
        else: "oriented/trebuchet_unpacked"
      else: # UnitVillager: role-based
        case agent.agentId mod MapAgentsPerTeam
        of 0, 1: "oriented/gatherer"
        of 2, 3: "oriented/builder"
        of 4, 5: "oriented/fighter"
        else: "oriented/gatherer"
    let dirKey = OrientationDirKeys[agent.orientation.int]
    let agentImage = baseKey & "." & dirKey
    let agentSpriteKey = if agentImage in bxy: agentImage
                         elif baseKey & ".s" in bxy: baseKey & ".s"
                         else: ""
    if agentSpriteKey.len > 0:
      # Apply subtle breathing animation when idle
      let animScale = if agent.isIdle:
        # Use agent position for phase offset so units don't breathe in sync
        let phaseOffset = (thingPos.x.float32 + thingPos.y.float32 * 1.3) * IdleAnimationPhaseScale
        let breathPhase = nowSeconds() * IdleAnimationSpeed * 2 * PI + phaseOffset
        SpriteScale * (1.0 + IdleAnimationAmplitude * sin(breathPhase))
      else:
        SpriteScale
      bxy.drawImage(agentSpriteKey, thingPos.vec2, angle = 0,
                    scale = animScale, tint = env.agentColors[agent.agentId])

  # Draw dying units with fade-out animation
  for dying in env.dyingUnits:
    if not isInViewport(dying.pos):
      continue
    let dyingBaseKey = block:
      let tbl = UnitClassSpriteKeys[dying.unitClass]
      if tbl.len > 0: tbl
      elif dying.unitClass == UnitTrebuchet: "oriented/trebuchet_packed"
      else:  # UnitVillager: role-based
        case dying.agentId mod MapAgentsPerTeam
        of 0, 1: "oriented/gatherer"
        of 2, 3: "oriented/builder"
        of 4, 5: "oriented/fighter"
        else: "oriented/gatherer"
    let dyingDirKey = OrientationDirKeys[dying.orientation.int]
    let dyingImage = dyingBaseKey & "." & dyingDirKey
    let dyingSpriteKey = if dyingImage in bxy: dyingImage
                         elif dyingBaseKey & ".s" in bxy: dyingBaseKey & ".s"
                         else: ""
    if dyingSpriteKey.len > 0:
      # Calculate fade: starts at 1.0 (full opacity), fades to 0.0
      let fade = dying.countdown.float32 / dying.lifetime.float32
      # Calculate scale: starts at 1.0, shrinks to 0.3 for collapse effect
      let dyingScale = SpriteScale * (0.3 + 0.7 * fade)
      # Get base unit color and apply alpha fade
      let baseColor = env.agentColors[dying.agentId]
      # Tint towards red during death, then fade out
      let deathTint = color(
        min(1.0, baseColor.r + 0.3 * (1.0 - fade)),
        baseColor.g * fade,
        baseColor.b * fade,
        fade * 0.9 + 0.1  # Never fully transparent until removed
      )
      bxy.drawImage(dyingSpriteKey, dying.pos.vec2, angle = 0,
                    scale = dyingScale, tint = deathTint)

  drawThings(Altar):
    let altarTint = if env.altarColors.hasKey(thingPos): env.altarColors[thingPos]
      elif thingPos.x >= 0 and thingPos.x < MapWidth and thingPos.y >= 0 and thingPos.y < MapHeight:
        let base = env.baseTintColors[thingPos.x][thingPos.y]
        color(base.r, base.g, base.b, 1.0)
      else: color(1.0, 1.0, 1.0, 1.0)
    let posVec = thingPos.vec2
    bxy.drawImage("floor", posVec, angle = 0, scale = SpriteScale,
                  tint = color(altarTint.r, altarTint.g, altarTint.b, 0.35))
    bxy.drawImage("altar", posVec, angle = 0, scale = SpriteScale,
                  tint = color(altarTint.r, altarTint.g, altarTint.b, 1.0))
    const heartAnchor = vec2(-0.48, -0.64)
    let amt = max(0, thing.hearts)
    let heartPos = posVec + heartAnchor
    if amt == 0:
      bxy.drawImage("heart", heartPos, angle = 0, scale = 1/420,
                    tint = color(altarTint.r, altarTint.g, altarTint.b, 0.35))
    elif amt <= HeartPlusThreshold:
      for i in 0 ..< amt:
        bxy.drawImage("heart", heartPos + vec2(0.12 * i.float32, 0.0),
                      angle = 0, scale = 1/420, tint = altarTint)
    else:
      bxy.drawImage("heart", heartPos, angle = 0, scale = 1/420, tint = altarTint)
      let labelKey = ensureHeartCountLabel(amt)
      bxy.drawImage(labelKey, heartPos + vec2(0.14, -0.08), angle = 0,
                    scale = 1/200, tint = color(1, 1, 1, 1))
    if isTileFrozen(thingPos, env):
      bxy.drawImage("frozen", posVec, angle = 0, scale = SpriteScale)

  drawThings(Tumor):
    let prefix = if thing.hasClaimedTerritory: "oriented/tumor.expired." else: "oriented/tumor."
    let key = prefix & TumorDirKeys[thing.orientation.int]
    if key in bxy:
      bxy.drawImage(key, thingPos.vec2, angle = 0, scale = SpriteScale)

  template drawOrientedThings(thingKind: ThingKind, prefix: string) =
    drawThings(thingKind):
      let key = prefix & OrientationDirKeys[thing.orientation.int]
      if key in bxy:
        bxy.drawImage(key, thingPos.vec2, angle = 0, scale = SpriteScale)

  drawOrientedThings(Cow, "oriented/cow.")
  drawOrientedThings(Bear, "oriented/bear.")
  drawOrientedThings(Wolf, "oriented/wolf.")

  drawThings(Lantern):
    if "lantern" in bxy:
      let tint = if thing.lanternHealthy:
        let teamId = thing.teamId
        let baseColor = if teamId >= 0 and teamId < env.teamColors.len: env.teamColors[teamId]
                        else: color(0.6, 0.6, 0.6, 1.0)
        # Multi-wave fire flicker using position-based phase offset for independent animation
        let posHash = (thingPos.x * 73 + thingPos.y * 137).float32
        let wave1 = sin((frame.float32 * LanternFlickerSpeed1) + posHash * 0.1)
        let wave2 = sin((frame.float32 * LanternFlickerSpeed2) + posHash * 0.17)
        let wave3 = sin((frame.float32 * LanternFlickerSpeed3) + posHash * 0.23)
        let flicker = 1.0 + LanternFlickerAmplitude * (wave1 * 0.5 + wave2 * 0.3 + wave3 * 0.2)
        color(min(1.2, baseColor.r * flicker), min(1.2, baseColor.g * flicker),
              min(1.2, baseColor.b * flicker), baseColor.a)
      else: color(0.5, 0.5, 0.5, 1.0)
      bxy.drawImage("lantern", thingPos.vec2, angle = 0, scale = SpriteScale, tint = tint)

  template isPlacedAt(thing: Thing): bool =
    isValidPos(thing.pos) and (
      if thingBlocksMovement(thing.kind): env.grid[thing.pos.x][thing.pos.y] == thing
      else: env.backgroundGrid[thing.pos.x][thing.pos.y] == thing)

  const OverlayIconScale = 1/320
  const OverlayLabelScale = 1/200

  for kind in ThingKind:
    if kind in {Wall, Tree, Wheat, Stubble, Agent, Altar, Tumor, Cow, Bear, Wolf, Lantern} or
        kind in CliffKinds:
      continue
    if isBuildingKind(kind):
      let spriteKey = buildingSpriteKey(kind)
      if spriteKey.len == 0 or spriteKey notin bxy:
        continue
      for thing in env.thingsByKind[kind]:
        if not isPlacedAt(thing) or not isInViewport(thing.pos):
          continue
        let pos = thing.pos
        # Check if building is under construction
        let isUnderConstruction = thing.maxHp > 0 and thing.hp < thing.maxHp
        let baseTint =
          if thing.kind in {Door, TownCenter, Barracks, ArcheryRange, Stable, SiegeWorkshop, Castle}:
            let teamId = thing.teamId
            let base = if teamId >= 0 and teamId < env.teamColors.len:
              env.teamColors[teamId]
            else:
              color(0.6, 0.6, 0.6, 0.9)
            color(base.r * 0.75 + 0.1, base.g * 0.75 + 0.1, base.b * 0.75 + 0.1, 0.9)
          else:
            color(1, 1, 1, 1)
        # Apply scaffolding effect: desaturate and add transparency when under construction
        let tint = if isUnderConstruction:
          let constructionProgress = thing.hp.float32 / thing.maxHp.float32
          # Desaturate: blend toward gray, more gray at lower progress
          let desatFactor = 0.4 + 0.6 * constructionProgress  # 0.4 to 1.0
          let gray = (baseTint.r + baseTint.g + baseTint.b) / 3.0
          color(
            baseTint.r * desatFactor + gray * (1.0 - desatFactor),
            baseTint.g * desatFactor + gray * (1.0 - desatFactor),
            baseTint.b * desatFactor + gray * (1.0 - desatFactor),
            0.7 + 0.3 * constructionProgress  # 0.7 to 1.0 alpha
          )
        else:
          baseTint
        bxy.drawImage(spriteKey, pos.vec2, angle = 0, scale = SpriteScale, tint = tint)
        # Construction scaffolding visual for buildings under construction
        if thing.maxHp > 0 and thing.hp < thing.maxHp:
          let constructionRatio = thing.hp.float32 / thing.maxHp.float32
          # Draw scaffolding frame (4 corner posts using floor sprite as small dots)
          let scaffoldTint = color(0.7, 0.5, 0.2, 0.8)  # Brown/wood color
          let scaffoldScale = 1.0 / 600.0  # Smaller dots for scaffolding posts
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
            continue
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
    else:
      let spriteKey = thingSpriteKey(kind)
      if spriteKey.len == 0 or spriteKey notin bxy:
        continue
      for thing in env.thingsByKind[kind]:
        if not isPlacedAt(thing) or not isInViewport(thing.pos):
          continue
        # Death animation: tint corpse/skeleton during death transition
        if thing.kind in {Corpse, Skeleton}:
          let px = thing.pos.x
          let py = thing.pos.y
          let countdown = env.actionTintCountdown[px][py]
          if countdown > 0 and env.actionTintCode[px][py] == ActionTintDeath:
            let fade = countdown.float32 / DeathTintDuration.float32
            let tint = color(1.0, 0.3 + 0.7 * (1.0 - fade), 0.3 + 0.7 * (1.0 - fade), fade * 0.6 + 0.4)
            bxy.drawImage(spriteKey, thing.pos.vec2, angle = 0, scale = SpriteScale, tint = tint)
          else:
            bxy.drawImage(spriteKey, thing.pos.vec2, angle = 0, scale = SpriteScale)
        elif thing.kind == Magma:
          # Magma glow pulsing - slower, subtle variation for molten effect
          let posHash = (thing.pos.x * 73 + thing.pos.y * 137).float32
          let glow = 1.0 + MagmaGlowAmplitude * sin((frame.float32 * MagmaGlowSpeed) + posHash * 0.1)
          let tint = color(min(1.2, glow), min(1.1, 0.85 * glow), min(1.0, 0.7 * glow), 1.0)
          bxy.drawImage(spriteKey, thing.pos.vec2, angle = 0, scale = SpriteScale, tint = tint)
        else:
          # Apply depletion scale for resource nodes
          let scale = if thing.kind in {Stone, Gold, Bush, Cactus, Fish, Stalagmite, Stump}:
            getResourceDepletionScale(thing)
          else:
            SpriteScale
          bxy.drawImage(spriteKey, thing.pos.vec2, angle = 0, scale = scale)
        if thing.kind in {Magma, Stump} and isTileFrozen(thing.pos, env):
          let frozenScale = if thing.kind == Stump: getResourceDepletionScale(thing) else: SpriteScale
          bxy.drawImage("frozen", thing.pos.vec2, angle = 0, scale = frozenScale)

proc drawVisualRanges*(alpha = 0.2) =
  if not currentViewport.valid:
    return

  # Clear only the viewport region of the reused visibility buffer
  # This avoids allocating a full MapWidth x MapHeight array each frame
  for x in currentViewport.minX .. currentViewport.maxX:
    for y in currentViewport.minY .. currentViewport.maxY:
      fogVisibility[x][y] = false

  # Extended viewport bounds for agents whose vision overlaps viewport
  let extMinX = max(0, currentViewport.minX - ObservationRadius)
  let extMaxX = min(MapWidth - 1, currentViewport.maxX + ObservationRadius)
  let extMinY = max(0, currentViewport.minY - ObservationRadius)
  let extMaxY = min(MapHeight - 1, currentViewport.maxY + ObservationRadius)

  # Only process agents whose vision could overlap the viewport
  for agent in env.agents:
    if not isAgentAlive(env, agent):
      continue
    # Skip agents too far from viewport to contribute visibility
    if agent.pos.x < extMinX or agent.pos.x > extMaxX or
       agent.pos.y < extMinY or agent.pos.y > extMaxY:
      continue
    # Mark visible tiles - clamp to viewport bounds for efficiency
    let startX = max(currentViewport.minX, agent.pos.x - ObservationRadius)
    let endX = min(currentViewport.maxX, agent.pos.x + ObservationRadius)
    let startY = max(currentViewport.minY, agent.pos.y - ObservationRadius)
    let endY = min(currentViewport.maxY, agent.pos.y + ObservationRadius)
    for x in startX .. endX:
      for y in startY .. endY:
        fogVisibility[x][y] = true

  # Draw fog with smooth edges
  # Edge smoothing: tiles at the boundary get lighter alpha based on visible neighbors
  const
    FogEdgeSmoothFactor = 0.7  # How much to reduce alpha at edges (0=no smoothing, 1=full)
    Neighbors = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]

  for x in currentViewport.minX .. currentViewport.maxX:
    for y in currentViewport.minY .. currentViewport.maxY:
      if not fogVisibility[x][y]:
        # Count visible neighbors for edge smoothing
        var visibleNeighbors = 0
        for (dx, dy) in Neighbors:
          let nx = x + dx
          let ny = y + dy
          if nx >= 0 and nx < MapWidth and ny >= 0 and ny < MapHeight:
            if fogVisibility[nx][ny]:
              visibleNeighbors += 1

        # Compute alpha: more visible neighbors = lighter fog (smoother edge)
        let edgeRatio = visibleNeighbors.float32 / 8.0
        let tileAlpha = alpha * (1.0 - edgeRatio * FogEdgeSmoothFactor)
        let fogColor = color(0, 0, 0, tileAlpha)
        bxy.drawRect(rect(x.float32 - 0.5, y.float32 - 0.5, 1, 1), fogColor)

proc drawAgentDecorations*() =
  type OverlayItem = object
    name: string
    icon: string
    count: int

  for agent in env.agents:
    let pos = agent.pos
    if not isValidPos(pos) or env.grid[pos.x][pos.y] != agent or not isInViewport(pos):
      continue
    let posVec = pos.vec2
    if agent.frozen > 0:
      bxy.drawImage("frozen", posVec, angle = 0, scale = SpriteScale)
    # Health bar: only show when damaged (hp < maxHp), with fade effect based on damage recency
    if agent.maxHp > 0 and agent.hp < agent.maxHp:
      let hpRatio = clamp(agent.hp.float32 / agent.maxHp.float32, 0.0, 1.0)
      let barAlpha = getHealthBarAlpha(env.currentStep, agent.lastAttackedStep)
      drawSegmentBar(posVec, vec2(0, -0.55), hpRatio,
                     getHealthBarColor(hpRatio), color(0.3, 0.3, 0.3, 0.7), alpha = barAlpha)
    # Cooldown indicator bar (for Trebuchet pack/unpack and other ability cooldowns)
    if agent.cooldown > 0:
      let maxCooldown = if agent.unitClass == UnitTrebuchet: TrebuchetPackDuration
                        else: agent.cooldown  # Fallback: treat current as max
      let cooldownRatio = clamp(agent.cooldown.float32 / maxCooldown.float32, 0.0, 1.0)
      drawSegmentBar(posVec, vec2(0, -0.40), cooldownRatio,
                     color(0.2, 0.8, 0.9, 1.0), color(0.3, 0.3, 0.3, 0.7))

    # Draw veterancy stars above HP bar for units with kills
    if agent.kills > 0:
      const VeterancyStarScale = 1.0 / 500.0
      const VeterancyStarColor = color(1.0, 0.85, 0.2, 1.0)  # Gold/yellow
      const MaxStarsDisplayed = 5
      let starsToShow = min(agent.kills, MaxStarsDisplayed)
      let starSpacing = 0.14'f32
      let starY = -0.72'f32  # Above HP bar
      let startX = -starSpacing * (starsToShow - 1).float32 / 2.0
      for i in 0 ..< starsToShow:
        let starPos = posVec + vec2(startX + starSpacing * i.float32, starY)
        bxy.drawImage("floor", starPos, angle = 0, scale = VeterancyStarScale,
                      tint = VeterancyStarColor)

    # Draw control group badge if assigned
    let groupNum = findAgentControlGroup(agent.agentId)
    if groupNum >= 0:
      let (badgeKey, badgeSize) = ensureControlGroupBadge(groupNum)
      if badgeKey.len > 0:
        # Position badge at upper-right of unit, offset from health bar
        let badgeOffset = vec2(0.35, -0.45)
        bxy.drawImage(badgeKey, posVec + badgeOffset, angle = 0,
                      scale = ControlGroupBadgeScale)

    # Draw veterancy stars above HP bar for units with kills
    if agent.kills > 0:
      const VeterancyStarScale = 1.0 / 500.0
      const VeterancyStarColor = color(1.0, 0.85, 0.2, 1.0)  # Gold/yellow
      const MaxStarsDisplayed = 5
      let starsToShow = min(agent.kills, MaxStarsDisplayed)
      let starSpacing = 0.14'f32
      let starY = -0.72'f32  # Above HP bar
      let startX = -starSpacing * (starsToShow - 1).float32 / 2.0
      for i in 0 ..< starsToShow:
        let starPos = posVec + vec2(startX + starSpacing * i.float32, starY)
        bxy.drawImage("floor", starPos, angle = 0, scale = VeterancyStarScale,
                      tint = VeterancyStarColor)

    var overlays: seq[OverlayItem] = @[]
    for key, count in agent.inventory.pairs:
      if count > 0:
        overlays.add(OverlayItem(name: $key, icon: itemSpriteKey(key), count: count))
    if overlays.len == 0:
      continue
    overlays.sort(proc(a, b: OverlayItem): int = cmp(a.name, b.name))

    let step = 360.0 / overlays.len.float32
    for i, ov in overlays:
      let angle = degToRad(135.0 - step * i.float32)
      let dir = vec2(cos(angle).float32, -sin(angle).float32)
      for j in 0 ..< min(ov.count, 4):
        bxy.drawImage(ov.icon, posVec + dir * (0.58 + 0.10 * j.float32),
                      angle = 0, scale = 1/320)

const ProjectileColors: array[ProjectileKind, Color] = [
  color(0.95, 0.85, 0.20, 1.0),  # ProjArrow - yellow
  color(0.70, 0.90, 0.25, 1.0),  # ProjLongbow - green-yellow
  color(0.90, 0.30, 0.35, 1.0),  # ProjJanissary - red
  color(0.95, 0.70, 0.25, 1.0),  # ProjTowerArrow - orange-yellow
  color(0.35, 0.25, 0.85, 1.0),  # ProjCastleArrow - blue-purple
  color(0.75, 0.35, 0.95, 1.0),  # ProjMangonel - pink-purple
  color(0.65, 0.20, 0.98, 1.0),  # ProjTrebuchet - deep purple
]

const ProjectileScales: array[ProjectileKind, float32] = [
  (1.0 / 400.0).float32,  # ProjArrow - small
  (1.0 / 400.0).float32,  # ProjLongbow - small
  (1.0 / 400.0).float32,  # ProjJanissary - small
  (1.0 / 400.0).float32,  # ProjTowerArrow - small
  (1.0 / 400.0).float32,  # ProjCastleArrow - small
  (1.0 / 280.0).float32,  # ProjMangonel - medium
  (1.0 / 240.0).float32,  # ProjTrebuchet - large
]

const
  ProjectileTrailPoints = 5     # Number of trail segments behind projectile
  ProjectileTrailStep = 0.12'f32  # Time step between trail points (fraction of lifetime)

proc drawProjectiles*() =
  ## Draw visual-only projectiles traveling from source to target.
  ## Renders a trail of fading points behind the projectile head.
  for proj in env.projectiles:
    if proj.lifetime <= 0:
      continue
    # Interpolate position: t=1 at source, t=0 at target
    let t = proj.countdown.float32 / proj.lifetime.float32
    let c = ProjectileColors[proj.kind]
    let sc = ProjectileScales[proj.kind]
    let srcX = proj.source.x.float32
    let srcY = proj.source.y.float32
    let tgtX = proj.target.x.float32
    let tgtY = proj.target.y.float32

    # Draw trail points (from back to front, oldest first)
    # Trail points represent past positions along the trajectory
    for i in countdown(ProjectileTrailPoints - 1, 0):
      let trailT = t + ProjectileTrailStep * (i + 1).float32
      # Skip trail points that would be beyond the source position
      if trailT > 1.0:
        continue
      let trailPos = vec2(
        srcX * trailT + tgtX * (1.0 - trailT),
        srcY * trailT + tgtY * (1.0 - trailT))
      # Fade opacity and shrink scale for older trail points
      let fadeRatio = 1.0 - (i + 1).float32 / (ProjectileTrailPoints + 1).float32
      let trailAlpha = c.a * fadeRatio * 0.7  # Max 70% opacity for trails
      let trailScale = sc * (0.5 + 0.5 * fadeRatio)  # Shrink to 50% at tail
      let trailColor = color(c.r, c.g, c.b, trailAlpha)
      bxy.drawImage("floor", trailPos, angle = 0, scale = trailScale, tint = trailColor)

    # Draw projectile head at current position
    let pos = vec2(srcX * t + tgtX * (1.0 - t), srcY * t + tgtY * (1.0 - t))
    bxy.drawImage("floor", pos, angle = 0, scale = sc, tint = c)

proc renderDamageNumberLabel(text: string, textColor: Color): (Image, IVec2) =
  ## Render a damage number label with outline for visibility.
  let fontSize = DamageNumberFontSize
  let padding = 2.0'f32
  var measureCtx = newContext(1, 1)
  setupCtxFont(measureCtx, DamageNumberFontPath, fontSize)
  let w = max(1, (measureCtx.measureText(text).width + padding * 2).int)
  let h = max(1, (fontSize + padding * 2).int)
  var ctx = newContext(w, h)
  setupCtxFont(ctx, DamageNumberFontPath, fontSize)
  # Draw outline for visibility
  ctx.fillStyle.color = color(0, 0, 0, 0.6)
  for dx in -1 .. 1:
    for dy in -1 .. 1:
      if dx != 0 or dy != 0:
        ctx.fillText(text, vec2(padding + dx.float32, padding + dy.float32))
  ctx.fillStyle.color = textColor
  ctx.fillText(text, vec2(padding, padding))
  result = (ctx.image, ivec2(w, h))

proc getDamageNumberLabel(amount: int, kind: DamageNumberKind): (string, IVec2) =
  ## Get or create a cached damage number label image.
  let prefix = case kind
    of DmgNumDamage: "d"
    of DmgNumHeal: "h"
    of DmgNumCritical: "c"
  let cacheKey = prefix & $amount
  if cacheKey in damageNumberImages:
    return (damageNumberImages[cacheKey], damageNumberSizes[cacheKey])
  # Create new label with appropriate color
  let textColor = case kind
    of DmgNumDamage: color(1.0, 0.3, 0.3, 1.0)    # Red
    of DmgNumHeal: color(0.3, 1.0, 0.3, 1.0)      # Green
    of DmgNumCritical: color(1.0, 0.8, 0.2, 1.0)  # Yellow/gold
  let text = $amount
  let (image, size) = renderDamageNumberLabel(text, textColor)
  let imageKey = "dmgnum_" & cacheKey
  bxy.addImage(imageKey, image)
  damageNumberImages[cacheKey] = imageKey
  damageNumberSizes[cacheKey] = size
  return (imageKey, size)

proc drawDamageNumbers*() =
  ## Draw floating damage numbers for combat feedback.
  ## Numbers float upward and fade out over their lifetime.
  if not currentViewport.valid:
    return
  for dmg in env.damageNumbers:
    if dmg.lifetime <= 0 or not isInViewport(dmg.pos):
      continue
    # Calculate progress (1.0 at spawn, 0.0 at expire)
    let t = dmg.countdown.float32 / dmg.lifetime.float32
    # Float upward as time progresses
    let floatOffset = (1.0 - t) * DamageNumberFloatHeight
    let worldPos = vec2(dmg.pos.x.float32, dmg.pos.y.float32 - floatOffset)
    # Fade out
    let alpha = t * t  # Quadratic ease for smoother fade
    let (imageKey, _) = getDamageNumberLabel(dmg.amount, dmg.kind)
    # Scale for world-space rendering (similar to HP bars)
    let scale = 1.0 / 200.0
    bxy.drawImage(imageKey, worldPos, angle = 0, scale = scale,
                  tint = color(1.0, 1.0, 1.0, alpha))

proc drawRagdolls*() =
  ## Draw ragdoll death bodies with physics-based tumbling.
  ## Bodies tumble away from damage source and fade out.
  if not currentViewport.valid:
    return
  for ragdoll in env.ragdolls:
    if ragdoll.lifetime <= 0:
      continue
    # Check viewport bounds using integer position
    let ipos = ivec2(ragdoll.pos.x.int32, ragdoll.pos.y.int32)
    if not isInViewport(ipos):
      continue
    # Get sprite key for the unit class
    let baseKey = UnitClassSpriteKeys[ragdoll.unitClass]
    # Fall back to villager sprites for villager-like units
    let spriteKey = if baseKey.len > 0 and baseKey & ".s" in bxy:
      baseKey & ".s"  # Use south-facing sprite as death pose
    elif "oriented/gatherer.s" in bxy:
      "oriented/gatherer.s"  # Fallback for villagers
    else:
      ""
    if spriteKey.len == 0:
      continue
    # Calculate alpha fade (quadratic ease for smoother fade)
    let t = ragdoll.countdown.float32 / ragdoll.lifetime.float32
    let alpha = t * t
    # Get team color with alpha applied
    let teamColor = getTeamColor(env, ragdoll.teamId)
    let tint = color(teamColor.r, teamColor.g, teamColor.b, alpha)
    # Draw with rotation
    bxy.drawImage(spriteKey, ragdoll.pos, angle = ragdoll.angle, scale = SpriteScale, tint = tint)

const DebrisColors: array[DebrisKind, Color] = [
  color(0.55, 0.35, 0.15, 1.0),  # DebrisWood - brown
  color(0.50, 0.50, 0.50, 1.0),  # DebrisStone - gray
  color(0.70, 0.40, 0.25, 1.0),  # DebrisBrick - terracotta/orange-brown
]

proc drawDebris*() =
  ## Draw debris particles from destroyed buildings.
  ## Particles move outward and fade out over their lifetime.
  if not currentViewport.valid:
    return
  for deb in env.debris:
    if deb.lifetime <= 0:
      continue
    # Check viewport bounds (convert float pos to int for check)
    let ipos = ivec2(deb.pos.x.int32, deb.pos.y.int32)
    if not isInViewport(ipos):
      continue
    # Calculate progress (1.0 at spawn, 0.0 at expire)
    let t = deb.countdown.float32 / deb.lifetime.float32
    # Fade out
    let alpha = t * t  # Quadratic ease for smoother fade
    let baseColor = DebrisColors[deb.kind]
    let tintColor = color(baseColor.r, baseColor.g, baseColor.b, alpha)
    # Draw as small colored dot using floor sprite
    let scale = (1.0 / 350.0).float32  # Slightly smaller than projectiles
    bxy.drawImage("floor", deb.pos, angle = 0, scale = scale, tint = tintColor)

proc drawSpawnEffects*() =
  ## Draw visual effects for unit spawning from buildings.
  ## Shows an expanding, fading glow at the spawn location.
  if not currentViewport.valid:
    return
  for effect in env.spawnEffects:
    if effect.lifetime <= 0 or not isInViewport(effect.pos):
      continue
    # Calculate progress (1.0 at spawn, 0.0 at expire)
    let t = effect.countdown.float32 / effect.lifetime.float32
    let progress = 1.0 - t  # 0.0 at spawn, 1.0 at expire
    # Expand from small to large as effect progresses
    let baseScale = SpriteScale * (0.3 + progress * 0.7)  # 30% to 100%
    # Fade out with quadratic ease (bright at start, fades smoothly)
    let alpha = t * t * 0.6  # Max alpha 0.6 to not be too bright
    # Use a bright cyan/white tint for spawn effect
    let tint = color(0.6, 0.9, 1.0, alpha)
    bxy.drawImage("floor", effect.pos.vec2, angle = 0, scale = baseScale, tint = tint)

proc drawGatherSparkles*() =
  ## Draw sparkle particles when workers collect resources.
  ## Golden particles burst outward and fade out over their lifetime.
  if not currentViewport.valid:
    return
  for sparkle in env.gatherSparkles:
    if sparkle.lifetime <= 0:
      continue
    # Check viewport bounds (convert float pos to int for check)
    let ipos = ivec2(sparkle.pos.x.int32, sparkle.pos.y.int32)
    if not isInViewport(ipos):
      continue
    # Calculate progress (1.0 at spawn, 0.0 at expire)
    let t = sparkle.countdown.float32 / sparkle.lifetime.float32
    # Fade out with quadratic ease
    let alpha = t * t * 0.9  # Bright golden sparkle
    # Golden/yellow color for resource collection
    let tintColor = color(1.0, 0.85, 0.3, alpha)
    # Draw as small glowing dot
    let scale = (1.0 / 400.0).float32  # Small sparkle particle
    bxy.drawImage("floor", sparkle.pos, angle = 0, scale = scale, tint = tintColor)

proc drawConstructionDust*() =
  ## Draw dust particles rising from buildings under construction.
  ## Brown/tan particles rise upward and fade out over their lifetime.
  if not currentViewport.valid:
    return
  for dust in env.constructionDust:
    if dust.lifetime <= 0:
      continue
    # Check viewport bounds (convert float pos to int for check)
    let ipos = ivec2(dust.pos.x.int32, dust.pos.y.int32)
    if not isInViewport(ipos):
      continue
    # Calculate progress (1.0 at spawn, 0.0 at expire)
    let t = dust.countdown.float32 / dust.lifetime.float32
    # Fade out with quadratic ease, dust becomes more transparent as it rises
    let alpha = t * t * 0.7  # Semi-transparent dust
    # Brown/tan dust color
    let tintColor = color(0.6, 0.5, 0.35, alpha)
    # Dust particles grow slightly as they rise and dissipate
    let scale = (1.0 / 350.0).float32 * (1.0 + (1.0 - t) * 0.5)  # 1.0x to 1.5x
    bxy.drawImage("floor", dust.pos, angle = 0, scale = scale, tint = tintColor)

proc drawUnitTrails*() =
  ## Draw dust/footprint trail particles behind moving units.
  ## Small dust particles that fade out where units have walked.
  if not currentViewport.valid:
    return
  for trail in env.unitTrails:
    if trail.lifetime <= 0:
      continue
    # Check viewport bounds (convert float pos to int for check)
    let ipos = ivec2(trail.pos.x.int32, trail.pos.y.int32)
    if not isInViewport(ipos):
      continue
    # Calculate progress (1.0 at spawn, 0.0 at expire)
    let t = trail.countdown.float32 / trail.lifetime.float32
    # Fade out with cubic ease - trails fade quickly but linger slightly
    let alpha = t * t * t * 0.5  # Semi-transparent dust
    # Light brown/tan dust color with slight team tint
    let baseColor = color(0.55, 0.45, 0.35, alpha)
    # Small dust particles that shrink as they fade
    let scale = (1.0 / 500.0).float32 * (0.5 + t * 0.5)  # 0.5x to 1.0x
    bxy.drawImage("floor", trail.pos, angle = 0, scale = scale, tint = baseColor)

proc drawWaterRipples*() =
  ## Draw ripple effects when units walk through water.
  ## Expanding rings that fade out over their lifetime.
  if not currentViewport.valid:
    return
  for ripple in env.waterRipples:
    if ripple.lifetime <= 0:
      continue
    # Check viewport bounds (convert float pos to int for check)
    let ipos = ivec2(ripple.pos.x.int32, ripple.pos.y.int32)
    if not isInViewport(ipos):
      continue
    # Calculate progress (1.0 at spawn, 0.0 at expire)
    let t = ripple.countdown.float32 / ripple.lifetime.float32
    let progress = 1.0 - t  # 0.0 at spawn, 1.0 at expire
    # Expand from small to large as effect progresses
    let baseScale = SpriteScale * (0.2 + progress * 0.8)  # 20% to 100%
    # Fade out with quadratic ease (visible at start, fades smoothly)
    let alpha = t * t * 0.5  # Max alpha 0.5 for subtle effect
    # Use a light cyan/blue tint for water ripple
    let tint = color(0.5, 0.7, 0.9, alpha)
    bxy.drawImage("floor", ripple.pos, angle = 0, scale = baseScale, tint = tint)

proc drawAttackImpacts*() =
  ## Draw attack impact burst particles when attacks hit targets.
  ## Particles radiate outward and fade quickly for a sharp impact effect.
  if not currentViewport.valid:
    return
  for impact in env.attackImpacts:
    if impact.lifetime <= 0:
      continue
    # Check viewport bounds (convert float pos to int for check)
    let ipos = ivec2(impact.pos.x.int32, impact.pos.y.int32)
    if not isInViewport(ipos):
      continue
    # Calculate progress (1.0 at spawn, 0.0 at expire)
    let t = impact.countdown.float32 / impact.lifetime.float32
    # Fade out quickly with quadratic ease for punchy effect
    let alpha = t * t * 0.9
    # Orange/red impact color for combat feedback
    let tintColor = color(1.0, 0.5, 0.2, alpha)
    # Small particles that shrink as they fade
    let scale = (1.0 / 400.0).float32 * (0.3 + t * 0.7)  # 30% to 100%
    bxy.drawImage("floor", impact.pos, angle = 0, scale = scale, tint = tintColor)

proc drawConversionEffects*() =
  ## Draw pulsing glow effects when monks convert enemy units.
  ## Displays as a golden/team-colored radial glow that pulses and fades.
  if not currentViewport.valid:
    return
  for effect in env.conversionEffects:
    if effect.lifetime <= 0:
      continue
    # Check viewport bounds
    let ipos = ivec2(effect.pos.x.int32, effect.pos.y.int32)
    if not isInViewport(ipos):
      continue
    # Calculate progress (1.0 at spawn, 0.0 at expire)
    let t = effect.countdown.float32 / effect.lifetime.float32
    # Pulsing effect: sine wave for divine/spiritual feel (2 pulses over lifetime)
    let pulse = (sin(t * 6.28318 * 2.0) + 1.0) * 0.5  # 0 to 1
    # Fade out over time with pulsing intensity
    let alpha = t * (0.5 + pulse * 0.5)
    # Blend between golden divine color and team color
    let golden = color(0.95, 0.85, 0.35, alpha)
    let teamAlpha = effect.teamColor
    let blendT = 1.0 - t  # More team color as time progresses
    let tintColor = color(
      golden.r * (1.0 - blendT) + teamAlpha.r * blendT,
      golden.g * (1.0 - blendT) + teamAlpha.g * blendT,
      golden.b * (1.0 - blendT) + teamAlpha.b * blendT,
      alpha * 0.8)
    # Draw expanding ring effect
    let baseScale = (1.0 / 400.0).float32
    let expandScale = baseScale * (1.0 + (1.0 - t) * 1.5)  # Expands as it fades
    bxy.drawImage("floor", effect.pos, angle = 0, scale = expandScale, tint = tintColor)

proc drawWeatherEffects*() =
  ## Draw ambient weather effects (rain or wind particles) across the viewport.
  ## Uses deterministic animation based on frame counter for consistent effects.
  if not currentViewport.valid or settings.weatherType == WeatherNone:
    return

  let viewWidth = currentViewport.maxX - currentViewport.minX + 1
  let viewHeight = currentViewport.maxY - currentViewport.minY + 1
  let viewArea = viewWidth * viewHeight

  # Calculate number of particles based on viewport size
  let particleCount = max(10, int(viewArea.float32 * WeatherParticleDensity))

  case settings.weatherType
  of WeatherRain:
    # Rain particles falling diagonally with slight drift
    for i in 0 ..< particleCount:
      # Use deterministic positioning based on particle index and frame
      let seed = i * 17 + 31
      let cycleOffset = (seed * 7) mod RainCycleFrames
      let cycleFrame = (frame + cycleOffset) mod RainCycleFrames
      let t = cycleFrame.float32 / RainCycleFrames.float32

      # Horizontal position: spread across viewport with some variation
      let xBase = currentViewport.minX.float32 +
                  ((seed * 13) mod (viewWidth * 100)).float32 / 100.0
      let xDrift = t * RainDriftSpeed * RainCycleFrames.float32

      # Vertical position: cycle from top to bottom of viewport
      let yBase = currentViewport.minY.float32 - 2.0  # Start above viewport
      let yFall = t * RainFallSpeed * RainCycleFrames.float32

      let particlePos = vec2(xBase + xDrift, yBase + yFall)

      # Skip if outside viewport (with margin)
      if particlePos.y < currentViewport.minY.float32 - 1.0 or
         particlePos.y > currentViewport.maxY.float32 + 1.0:
        continue

      # Rain color: light blue-white with some variation
      let blueVal = 0.7 + ((seed * 3) mod 30).float32 / 100.0
      let rainTint = color(0.8, 0.85, blueVal, RainAlpha)

      # Draw rain streak (multiple particles in a line)
      for s in 0 ..< RainStreakLength:
        let streakOffset = vec2(
          -RainDriftSpeed * s.float32 * 2.0,
          -RainFallSpeed * s.float32 * 2.0
        )
        let streakAlpha = RainAlpha * (1.0 - s.float32 / RainStreakLength.float32)
        let streakTint = color(rainTint.r, rainTint.g, rainTint.b, streakAlpha)
        bxy.drawImage("floor", particlePos + streakOffset, angle = 0,
                      scale = WeatherParticleScale, tint = streakTint)

  of WeatherWind:
    # Wind particles blowing horizontally with slight vertical drift
    for i in 0 ..< particleCount:
      let seed = i * 23 + 47
      let cycleOffset = (seed * 11) mod WindCycleFrames
      let cycleFrame = (frame + cycleOffset) mod WindCycleFrames
      let t = cycleFrame.float32 / WindCycleFrames.float32

      # Vertical position: spread across viewport
      let yBase = currentViewport.minY.float32 +
                  ((seed * 19) mod (viewHeight * 100)).float32 / 100.0
      let yDrift = sin(t * 3.14159 * 2.0) * WindDriftSpeed * 4.0

      # Horizontal position: cycle from left to right of viewport
      let xBase = currentViewport.minX.float32 - 2.0  # Start left of viewport
      let xBlow = t * WindBlowSpeed * WindCycleFrames.float32

      let particlePos = vec2(xBase + xBlow, yBase + yDrift)

      # Skip if outside viewport (with margin)
      if particlePos.x < currentViewport.minX.float32 - 1.0 or
         particlePos.x > currentViewport.maxX.float32 + 1.0:
        continue

      # Wind color: dusty tan/gray for leaves and dust
      let grayVal = 0.6 + ((seed * 5) mod 20).float32 / 100.0
      let brownVal = 0.5 + ((seed * 7) mod 15).float32 / 100.0
      let windTint = color(grayVal, brownVal, 0.4, WindAlpha)

      # Draw wind particle with slight size variation
      let sizeVar = 1.0 + ((seed * 3) mod 50).float32 / 100.0
      bxy.drawImage("floor", particlePos, angle = 0,
                    scale = WeatherParticleScale * sizeVar, tint = windTint)

  of WeatherNone:
    discard
proc drawGrid*() =
  if not currentViewport.valid:
    return
  for x in currentViewport.minX .. currentViewport.maxX:
    for y in currentViewport.minY .. currentViewport.maxY:
      bxy.drawImage("grid", ivec2(x, y).vec2, angle = 0, scale = SpriteScale)

# Selection glow pulse constants
const
  SelectionPulseSpeed = 0.12'f32      # Animation speed (slower than rally point)
  SelectionPulseMin = 0.4'f32         # Minimum glow alpha
  SelectionPulseMax = 0.8'f32         # Maximum glow alpha
  SelectionGlowScale = 1.8'f32        # Glow layer scale multiplier

  # Building-specific glow constants for better visibility
  BuildingGlowScale1 = 2.4'f32        # Outermost glow layer (largest, faintest)
  BuildingGlowScale2 = 2.0'f32        # Middle glow layer
  BuildingGlowScale3 = 1.6'f32        # Inner glow layer (smallest, brightest)
  BuildingGlowAlpha1 = 0.15'f32       # Outermost layer alpha
  BuildingGlowAlpha2 = 0.25'f32       # Middle layer alpha
  BuildingGlowAlpha3 = 0.35'f32       # Inner layer alpha

proc drawSelection*() =
  if selection.len == 0:
    return

  # Calculate pulsing animation based on frame counter
  let pulse = sin(frame.float32 * SelectionPulseSpeed) * 0.5 + 0.5
  let pulseAlpha = SelectionPulseMin + pulse * (SelectionPulseMax - SelectionPulseMin)

  for thing in selection:
    if isNil(thing) or not isValidPos(thing.pos) or not isInViewport(thing.pos):
      continue

    let pos = thing.pos.vec2

    # Get team color for the glow (use neutral white if no team)
    let teamColor = getTeamColor(env, thing.teamId, color(1.0, 1.0, 1.0, 1.0))

    # Buildings get enhanced multi-layer glow for better visibility
    if isBuildingKind(thing.kind):
      # Draw three glow layers for a soft, visible building glow
      # Outermost layer - largest, faintest
      let glowColor1 = color(teamColor.r, teamColor.g, teamColor.b,
                             pulseAlpha * BuildingGlowAlpha1)
      bxy.drawImage("selection", pos, angle = 0, scale = SpriteScale * BuildingGlowScale1,
                    tint = glowColor1)

      # Middle layer
      let glowColor2 = color(teamColor.r, teamColor.g, teamColor.b,
                             pulseAlpha * BuildingGlowAlpha2)
      bxy.drawImage("selection", pos, angle = 0, scale = SpriteScale * BuildingGlowScale2,
                    tint = glowColor2)

      # Inner layer - smallest, brightest
      let glowColor3 = color(teamColor.r, teamColor.g, teamColor.b,
                             pulseAlpha * BuildingGlowAlpha3)
      bxy.drawImage("selection", pos, angle = 0, scale = SpriteScale * BuildingGlowScale3,
                    tint = glowColor3)
    else:
      # Units get standard single-layer glow
      let glowColor = color(teamColor.r, teamColor.g, teamColor.b, pulseAlpha * 0.35)
      bxy.drawImage("selection", pos, angle = 0, scale = SpriteScale * SelectionGlowScale,
                    tint = glowColor)

    # Draw main selection indicator (full opacity)
    bxy.drawImage("selection", pos, angle = 0, scale = SpriteScale)

# ─── Rally Point Visual Indicators ──────────────────────────────────────────

const
  RallyPointLineWidth = 0.06'f32    # Width of the path line in world units
  RallyPointLineSegments = 12       # Number of segments in the path line
  RallyPointBeaconScale = 1.0 / 280.0  # Scale for the beacon sprite
  RallyPointPulseSpeed = 0.15'f32   # Speed of the pulsing animation
  RallyPointPulseMin = 0.6'f32      # Minimum alpha during pulse
  RallyPointPulseMax = 1.0'f32      # Maximum alpha during pulse

# Building kinds that can have rally points (military/training buildings)
const RallyPointBuildingKinds = [
  TownCenter, Barracks, ArcheryRange, Stable, SiegeWorkshop,
  MangonelWorkshop, TrebuchetWorkshop, Castle, Dock, Monastery
]

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

        # Calculate perpendicular for line width
        let perpX = -normalizedDir.y * RallyPointLineWidth * 0.5
        let perpY = normalizedDir.x * RallyPointLineWidth * 0.5

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
  if selection.len > 1:
    # Multi-selection: show count
    label = $selection.len & " units selected"
  else:
    let thing = env.grid[selectedPos.x][selectedPos.y]
    let background = env.backgroundGrid[selectedPos.x][selectedPos.y]
    if not isNil(thing):
      label = displayNameFor(thing)
      appendResourceCount(label, thing)
    elif not isNil(background):
      label = displayNameFor(background)
      appendResourceCount(label, background)
    else:
      let terrain = env.terrain[selectedPos.x][selectedPos.y]
      let name = TerrainCatalog[terrain].displayName
      label = if name.len > 0: name else: $terrain

  if label.len == 0:
    return
  var key = ""
  var labelSize = ivec2(0, 0)
  if label in infoLabelImages:
    key = infoLabelImages[label]
    labelSize = infoLabelSizes.getOrDefault(label, ivec2(0, 0))
  else:
    let (image, size) = renderTextLabel(label, InfoLabelFontPath,
                                        InfoLabelFontSize, InfoLabelPadding.float32, 0.6)
    key = "selection_label/" & label.replace(" ", "_").replace("/", "_")
    bxy.addImage(key, image)
    infoLabelImages[label] = key
    infoLabelSizes[label] = size
    labelSize = size
  if key.len == 0 or labelSize.x <= 0 or labelSize.y <= 0:
    return
  drawFooterHudLabel(panelRect, key, labelSize, FooterHudPadding + 75.0)

proc drawStepLabel*(panelRect: IRect) =
  var key = ""
  if stepLabelLastValue == env.currentStep and stepLabelKey.len > 0:
    key = stepLabelKey
  else:
    stepLabelLastValue = env.currentStep
    let (image, size) = renderTextLabel("Step " & $env.currentStep, InfoLabelFontPath,
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
  drawFooterHudLabel(panelRect, key, stepLabelSize,
                     panelRect.w.float32 - labelW - FooterHudPadding + 25.0)

proc drawControlModeLabel*(panelRect: IRect) =
  ## Draws "[OBSERVING]" or "[CONTROLLING Team N]" in the footer HUD.
  var key = ""
  if controlModeLabelLastValue == playerTeam and controlModeLabelKey.len > 0:
    key = controlModeLabelKey
  else:
    controlModeLabelLastValue = playerTeam
    let label = if playerTeam < 0:
      "[OBSERVING]"
    else:
      "[CONTROLLING Team " & $playerTeam & "]"
    let (image, size) = renderTextLabel(label, InfoLabelFontPath,
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
  MinimapSize = 200       # pixels (square)
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
  minimapScaleX: float32 = MinimapSize.float32 / MapWidth.float32
  minimapScaleY: float32 = MinimapSize.float32 / MapHeight.float32
  minimapInvScaleX: float32 = MapWidth.float32 / MinimapSize.float32
  minimapInvScaleY: float32 = MapHeight.float32 / MinimapSize.float32
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
     minimapTerrainImage.width != MinimapSize or
     minimapTerrainImage.height != MinimapSize:
    minimapTerrainImage = newImage(MinimapSize, MinimapSize)

  # Scale factors: map coords -> minimap pixel
  let scaleX = MinimapSize.float32 / MapWidth.float32
  let scaleY = MinimapSize.float32 / MapHeight.float32

  for py in 0 ..< MinimapSize:
    for px in 0 ..< MinimapSize:
      let mx = clamp(int(px.float32 / scaleX), 0, MapWidth - 1)
      let my = clamp(int(py.float32 / scaleY), 0, MapHeight - 1)
      let terrain = env.terrain[mx][my]
      let biome = env.biomes[mx][my]
      # Check for trees at this tile
      let bg = env.backgroundGrid[mx][my]
      let c = if not bg.isNil and bg.kind == Tree:
        rgbx(40, 100, 40, 255)    # dark green for trees
      else:
        toMinimapColor(terrain, biome)
      minimapTerrainImage.unsafe[px, py] = c

  minimapTerrainGeneration = env.mapGeneration

proc colorToRgbx(c: Color): ColorRGBX =
  rgbx(
    uint8(clamp(c.r * 255, 0, 255)),
    uint8(clamp(c.g * 255, 0, 255)),
    uint8(clamp(c.b * 255, 0, 255)),
    255
  )

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
     minimapCompositeImage.width != MinimapSize or
     minimapCompositeImage.height != MinimapSize:
    minimapCompositeImage = newImage(MinimapSize, MinimapSize)

  # Start from cached terrain
  copyMem(addr minimapCompositeImage.data[0],
          addr minimapTerrainImage.data[0],
          MinimapSize * MinimapSize * 4)

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
      let fx0 = clamp(px, 0, MinimapSize - 1)
      let fx1 = clamp(px + 1, 0, MinimapSize - 1)
      let fy0 = clamp(py, 0, MinimapSize - 1)
      let fy1 = clamp(py + 1, 0, MinimapSize - 1)
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
    let px = clamp(int(agent.pos.x.float32 * scaleX), 0, MinimapSize - 1)
    let py = clamp(int(agent.pos.y.float32 * scaleY), 0, MinimapSize - 1)
    minimapCompositeImage.unsafe[px, py] = dot

  # Apply fog of war with edge smoothing
  if fogTeamId >= 0 and fogTeamId < MapRoomObjectsTeams:
    let invScaleX = minimapInvScaleX
    let invScaleY = minimapInvScaleY
    const
      MinimapFogEdgeSmoothFactor = 0.6  # How much to lighten edge tiles
      Neighbors = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
    for py in 0 ..< MinimapSize:
      let my = clamp(int(py.float32 * invScaleY), 0, MapHeight - 1)
      for px in 0 ..< MinimapSize:
        let mx = clamp(int(px.float32 * invScaleX), 0, MapWidth - 1)
        if not env.revealedMaps[fogTeamId][mx][my]:
          # Count revealed neighbors for edge smoothing
          var revealedNeighbors = 0
          for (dx, dy) in Neighbors:
            let nx = mx + dx
            let ny = my + dy
            if nx >= 0 and nx < MapWidth and ny >= 0 and ny < MapHeight:
              if env.revealedMaps[fogTeamId][nx][ny]:
                revealedNeighbors += 1

          # Compute darkening factor: more revealed neighbors = less darkening (smoother edge)
          # Base darkening is shr 2 (divide by 4), edge tiles get less darkening
          let edgeRatio = revealedNeighbors.float32 / 8.0
          let darkenFactor = 0.25 + edgeRatio * MinimapFogEdgeSmoothFactor * 0.75  # 0.25 to 1.0

          let c = minimapCompositeImage.unsafe[px, py]
          minimapCompositeImage.unsafe[px, py] = rgbx(
            uint8(clamp(c.r.float32 * darkenFactor, 0, 255)),
            uint8(clamp(c.g.float32 * darkenFactor, 0, 255)),
            uint8(clamp(c.b.float32 * darkenFactor, 0, 255)),
            c.a
          )

  minimapLastUnitFrame = frame
  # Upload to boxy
  bxy.addImage(minimapImageKey, minimapCompositeImage)

proc drawMinimap*(panelRect: IRect, panel: Panel) =
  ## Draw the minimap overlay in the bottom-left corner of the panel.
  let fogTeamId = if settings.showFogOfWar: 0 else: -1

  # Rebuild composite every N frames or on terrain change
  if minimapTerrainGeneration != env.mapGeneration or
     minimapLastUnitFrame < 0 or
     (frame - minimapLastUnitFrame) >= MinimapUpdateInterval:
    rebuildMinimapComposite(fogTeamId)

  # Position: bottom-left, above footer
  let mmX = panelRect.x.float32 + MinimapPadding
  let mmY = panelRect.y.float32 + panelRect.h.float32 - FooterHeight.float32 - MinimapSize.float32 - MinimapPadding

  # Draw background border
  bxy.drawRect(
    rect = Rect(
      x: mmX - MinimapBorderWidth,
      y: mmY - MinimapBorderWidth,
      w: MinimapSize.float32 + MinimapBorderWidth * 2,
      h: MinimapSize.float32 + MinimapBorderWidth * 2
    ),
    color = color(0.08, 0.10, 0.14, 0.95)
  )

  # Draw the minimap texture
  if minimapImageKey in bxy:
    bxy.drawImage(minimapImageKey, vec2(mmX, mmY))

  # Draw viewport rectangle
  let scaleVal = window.contentScale
  let rectW = panelRect.w.float32 / scaleVal
  let rectH = panelRect.h.float32 / scaleVal
  let zoomScale = panel.zoom * panel.zoom

  if zoomScale > 0 and rectW > 0 and rectH > 0:
    # Camera center in world coordinates
    let cx = (rectW / 2.0'f32 - panel.pos.x) / zoomScale
    let cy = (rectH / 2.0'f32 - panel.pos.y) / zoomScale
    let halfW = rectW / (2.0'f32 * zoomScale)
    let halfH = rectH / (2.0'f32 * zoomScale)

    # Map world coords to minimap pixels
    let mmScaleX = MinimapSize.float32 / MapWidth.float32
    let mmScaleY = MinimapSize.float32 / MapHeight.float32

    let vpX = mmX + (cx - halfW) * mmScaleX
    let vpY = mmY + (cy - halfH) * mmScaleY
    let vpW = halfW * 2.0 * mmScaleX
    let vpH = halfH * 2.0 * mmScaleY

    # Clamp to minimap bounds
    let x0 = max(vpX, mmX)
    let y0 = max(vpY, mmY)
    let x1 = min(vpX + vpW, mmX + MinimapSize.float32)
    let y1 = min(vpY + vpH, mmY + MinimapSize.float32)

    if x1 > x0 and y1 > y0:
      let lineW = 1.5'f32
      let vpColor = color(1.0, 1.0, 1.0, 0.85)
      # Top edge
      bxy.drawRect(Rect(x: x0, y: y0, w: x1 - x0, h: lineW), vpColor)
      # Bottom edge
      bxy.drawRect(Rect(x: x0, y: y1 - lineW, w: x1 - x0, h: lineW), vpColor)
      # Left edge
      bxy.drawRect(Rect(x: x0, y: y0, w: lineW, h: y1 - y0), vpColor)
      # Right edge
      bxy.drawRect(Rect(x: x1 - lineW, y: y0, w: lineW, h: y1 - y0), vpColor)

# ─── Unit Info Panel ────────────────────────────────────────────────────────

const
  UnitInfoPanelWidth* = 240.0'f32
  UnitInfoPanelPadding = 12.0'f32
  UnitInfoFontSize: float32 = 22
  UnitInfoLargeFontSize: float32 = 28
  UnitInfoLineHeight = 28.0'f32
  UnitInfoBarHeight = 12.0'f32
  UnitInfoBarWidth = 110.0'f32  # Reduced to fit HP text within panel bounds

var
  unitInfoLabelImages: Table[string, string] = initTable[string, string]()
  unitInfoLabelSizes: Table[string, IVec2] = initTable[string, IVec2]()

proc getUnitInfoLabel(text: string, fontSize: float32 = UnitInfoFontSize): (string, IVec2) =
  let cacheKey = text & "_" & $fontSize.int
  if cacheKey in unitInfoLabelImages:
    result = (unitInfoLabelImages[cacheKey], unitInfoLabelSizes[cacheKey])
  else:
    let (image, size) = renderTextLabel(text, FooterFontPath, fontSize, 2.0, 0.0)
    let key = "unit_info/" & cacheKey.replace(" ", "_").replace("/", "_").replace(":", "_")
    bxy.addImage(key, image)
    unitInfoLabelImages[cacheKey] = key
    unitInfoLabelSizes[cacheKey] = size
    result = (key, size)

proc drawUnitInfoPanel*(panelRect: IRect) =
  # Clear cancel buttons from previous frame
  queueCancelButtons.setLen(0)

  if selection.len == 0:
    return

  # Panel position: right side, from top (below resource bar area) to above command panel area
  let panelX = panelRect.x.float32 + panelRect.w.float32 - UnitInfoPanelWidth - UnitInfoPanelPadding
  let panelY = panelRect.y.float32 + 40.0'f32  # Below potential resource bar
  let panelH = panelRect.h.float32 * 0.45'f32  # Upper ~45% of right side

  # Background
  bxy.drawRect(
    rect = Rect(x: panelX, y: panelY, w: UnitInfoPanelWidth, h: panelH),
    color = color(0.08, 0.10, 0.14, 0.92)
  )

  var y = panelY + UnitInfoPanelPadding
  let textX = panelX + UnitInfoPanelPadding

  if selection.len == 1:
    let thing = selection[0]

    # --- Single Unit/Building Selected ---
    if thing.kind == Agent:
      let agent = thing
      let teamId = getTeamId(agent)

      # Unit name (large)
      let unitName = UnitClassLabels[agent.unitClass]
      let (nameKey, nameSize) = getUnitInfoLabel(unitName, UnitInfoLargeFontSize)
      bxy.drawImage(nameKey, vec2(textX, y), angle = 0, scale = 1.0)
      y += nameSize.y.float32 + 4.0

      # Team
      let teamLabel = "Team " & $teamId
      let teamColor = getTeamColor(env, teamId)
      let (teamKey, teamSize) = getUnitInfoLabel(teamLabel)
      bxy.drawImage(teamKey, vec2(textX, y), angle = 0, scale = 1.0, tint = teamColor)
      y += teamSize.y.float32 + 8.0

      # HP Bar
      let (hpLabelKey, _) = getUnitInfoLabel("HP:")
      bxy.drawImage(hpLabelKey, vec2(textX, y), angle = 0, scale = 1.0)
      let barX = textX + 40.0
      let barY = y + 4.0
      let hpRatio = if agent.maxHp > 0: clamp(agent.hp.float32 / agent.maxHp.float32, 0.0, 1.0) else: 0.0
      # Background bar
      bxy.drawRect(Rect(x: barX, y: barY, w: UnitInfoBarWidth, h: UnitInfoBarHeight),
                   color(0.2, 0.2, 0.2, 0.9))
      # Filled bar
      let hpColor = if hpRatio > 0.5: color(0.1, 0.8, 0.1, 1.0)
                    elif hpRatio > 0.25: color(0.9, 0.7, 0.1, 1.0)
                    else: color(0.9, 0.2, 0.1, 1.0)
      bxy.drawRect(Rect(x: barX, y: barY, w: UnitInfoBarWidth * hpRatio, h: UnitInfoBarHeight), hpColor)
      # HP text
      let hpText = $agent.hp & "/" & $agent.maxHp
      let (hpTextKey, _) = getUnitInfoLabel(hpText)
      bxy.drawImage(hpTextKey, vec2(barX + UnitInfoBarWidth + 8.0, y), angle = 0, scale = 1.0)
      y += UnitInfoLineHeight

      # Attack
      let (atkLabelKey, _) = getUnitInfoLabel("Attack: " & $agent.attackDamage)
      bxy.drawImage(atkLabelKey, vec2(textX, y), angle = 0, scale = 1.0)
      y += UnitInfoLineHeight

      # Range
      let range = getUnitAttackRange(agent)
      let (rangeLabelKey, _) = getUnitInfoLabel("Range: " & $range)
      bxy.drawImage(rangeLabelKey, vec2(textX, y), angle = 0, scale = 1.0)
      y += UnitInfoLineHeight

      # Stance
      let stanceText = "Stance: " & StanceLabels[agent.stance]
      let (stanceLabelKey, _) = getUnitInfoLabel(stanceText)
      bxy.drawImage(stanceLabelKey, vec2(textX, y), angle = 0, scale = 1.0)
      y += UnitInfoLineHeight

      # Kills (veterancy)
      if agent.kills > 0:
        let killsText = "Kills: " & $agent.kills
        let (killsLabelKey, _) = getUnitInfoLabel(killsText)
        let killsTint = color(1.0, 0.85, 0.2, 1.0)  # Gold color for veterancy
        bxy.drawImage(killsLabelKey, vec2(textX, y), angle = 0, scale = 1.0, tint = killsTint)
        y += UnitInfoLineHeight

      # Status (idle or not)
      let statusText = if agent.isIdle: "Status: Idle" else: "Status: Active"
      let (statusLabelKey, _) = getUnitInfoLabel(statusText)
      let statusTint = if agent.isIdle: color(0.7, 0.7, 0.3, 1.0) else: color(0.5, 0.9, 0.5, 1.0)
      bxy.drawImage(statusLabelKey, vec2(textX, y), angle = 0, scale = 1.0, tint = statusTint)
      y += UnitInfoLineHeight + 8.0

      # Inventory
      var hasInventory = false
      for key, count in agent.inventory.pairs:
        if count > 0:
          hasInventory = true
          break
      if hasInventory:
        let (invLabelKey, _) = getUnitInfoLabel("Inventory:")
        bxy.drawImage(invLabelKey, vec2(textX, y), angle = 0, scale = 1.0)
        y += UnitInfoLineHeight - 4.0
        var invX = textX
        for key, count in agent.inventory.pairs:
          if count > 0:
            let itemText = $key & " x" & $count
            let (itemKey, itemSize) = getUnitInfoLabel(itemText)
            if invX + itemSize.x.float32 > panelX + UnitInfoPanelWidth - UnitInfoPanelPadding:
              invX = textX
              y += UnitInfoLineHeight - 6.0
            bxy.drawImage(itemKey, vec2(invX, y), angle = 0, scale = 1.0,
                          tint = color(0.8, 0.85, 0.9, 1.0))
            invX += itemSize.x.float32 + 12.0

    elif isBuildingKind(thing.kind):
      # --- Building Selected ---
      let building = thing
      let teamId = building.teamId

      # Building name (large)
      let buildingName = BuildingRegistry[building.kind].displayName
      let (nameKey, nameSize) = getUnitInfoLabel(buildingName, UnitInfoLargeFontSize)
      bxy.drawImage(nameKey, vec2(textX, y), angle = 0, scale = 1.0)
      y += nameSize.y.float32 + 4.0

      # Team
      if teamId >= 0:
        let teamLabel = "Team " & $teamId
        let teamColor = getTeamColor(env, teamId)
        let (teamKey, teamSize) = getUnitInfoLabel(teamLabel)
        bxy.drawImage(teamKey, vec2(textX, y), angle = 0, scale = 1.0, tint = teamColor)
        y += teamSize.y.float32 + 8.0

      # HP Bar (for buildings with HP)
      if building.maxHp > 0:
        let (hpLabelKey, _) = getUnitInfoLabel("HP:")
        bxy.drawImage(hpLabelKey, vec2(textX, y), angle = 0, scale = 1.0)
        let barX = textX + 40.0
        let barY = y + 4.0
        let hpRatio = clamp(building.hp.float32 / building.maxHp.float32, 0.0, 1.0)
        bxy.drawRect(Rect(x: barX, y: barY, w: UnitInfoBarWidth, h: UnitInfoBarHeight),
                     color(0.2, 0.2, 0.2, 0.9))
        bxy.drawRect(Rect(x: barX, y: barY, w: UnitInfoBarWidth * hpRatio, h: UnitInfoBarHeight),
                     color(0.1, 0.8, 0.1, 1.0))
        let hpText = $building.hp & "/" & $building.maxHp
        let (hpTextKey, _) = getUnitInfoLabel(hpText)
        bxy.drawImage(hpTextKey, vec2(barX + UnitInfoBarWidth + 8.0, y), angle = 0, scale = 1.0)
        y += UnitInfoLineHeight

      # Garrison count (for garrisonable buildings)
      if building.kind in {TownCenter, Castle, GuardTower, House}:
        let garrisonCap = case building.kind
          of TownCenter: TownCenterGarrisonCapacity
          of Castle: CastleGarrisonCapacity
          of GuardTower: GuardTowerGarrisonCapacity
          of House: HouseGarrisonCapacity
          else: 0
        let garrisonCount = building.garrisonedUnits.len
        let garrisonText = "Garrison: " & $garrisonCount & "/" & $garrisonCap
        let (garrisonKey, _) = getUnitInfoLabel(garrisonText)
        bxy.drawImage(garrisonKey, vec2(textX, y), angle = 0, scale = 1.0)
        y += UnitInfoLineHeight

      # Production Queue with horizontal icon row (up to 10 entries)
      if building.productionQueue.entries.len > 0:
        let (queueLabelKey, _) = getUnitInfoLabel("Queue:")
        bxy.drawImage(queueLabelKey, vec2(textX, y), angle = 0, scale = 1.0)
        y += UnitInfoLineHeight - 2.0

        const
          QueueIconSize = 20.0'f32
          QueueIconScale = QueueIconSize / 200.0'f32  # Sprites are ~200px
          QueueIconGap = 2.0'f32
          QueueProgressBarH = 4.0'f32
          MaxQueueIcons = 10

        let queueRowY = y
        var iconX = textX

        for i, entry in building.productionQueue.entries:
          if i >= MaxQueueIcons: break  # Show max 10 entries

          # Draw unit icon
          let baseKey = UnitClassSpriteKeys[entry.unitClass]
          let iconKey = if baseKey.len > 0 and (baseKey & ".s") in bxy:
            baseKey & ".s"
          elif entry.unitClass == UnitVillager and "oriented/gatherer.s" in bxy:
            "oriented/gatherer.s"
          else:
            ""

          # Background for icon (darker for queued, brighter for first)
          let iconBgColor = if i == 0:
            color(0.25, 0.35, 0.45, 0.9)
          else:
            color(0.15, 0.18, 0.22, 0.8)
          bxy.drawRect(Rect(x: iconX, y: queueRowY, w: QueueIconSize, h: QueueIconSize), iconBgColor)

          if iconKey.len > 0:
            let tint = if i == 0: color(1.0, 1.0, 1.0, 1.0) else: color(0.7, 0.7, 0.7, 1.0)
            bxy.drawImage(iconKey, vec2(iconX, queueRowY), angle = 0, scale = QueueIconScale, tint = tint)

          # Progress bar under first entry
          if i == 0 and entry.totalSteps > 0:
            let progRatio = clamp(1.0 - entry.remainingSteps.float32 / entry.totalSteps.float32, 0.0, 1.0)
            let progBarY = queueRowY + QueueIconSize
            bxy.drawRect(Rect(x: iconX, y: progBarY, w: QueueIconSize, h: QueueProgressBarH),
                         color(0.2, 0.2, 0.2, 0.9))
            bxy.drawRect(Rect(x: iconX, y: progBarY, w: QueueIconSize * progRatio, h: QueueProgressBarH),
                         color(0.2, 0.5, 1.0, 1.0))

          # Track this icon for right-click cancel
          let iconRect = Rect(x: iconX, y: queueRowY, w: QueueIconSize, h: QueueIconSize + QueueProgressBarH)
          queueCancelButtons.add(QueueCancelButton(
            rect: iconRect,
            queueIndex: i,
            buildingPos: building.pos
          ))

          iconX += QueueIconSize + QueueIconGap

        y += QueueIconSize + QueueProgressBarH + 6.0

        # Show count if queue is longer than displayed
        if building.productionQueue.entries.len > MaxQueueIcons:
          let moreText = "+" & $(building.productionQueue.entries.len - MaxQueueIcons) & " more"
          let (moreKey, _) = getUnitInfoLabel(moreText)
          bxy.drawImage(moreKey, vec2(textX, y), angle = 0, scale = 1.0,
                        tint = color(0.6, 0.6, 0.6, 1.0))
          y += UnitInfoLineHeight

    else:
      # --- Other thing selected (resource, terrain object) ---
      let displayName = if ThingCatalog[thing.kind].displayName.len > 0:
        ThingCatalog[thing.kind].displayName
      else:
        $thing.kind
      let (nameKey, _) = getUnitInfoLabel(displayName, UnitInfoLargeFontSize)
      bxy.drawImage(nameKey, vec2(textX, y), angle = 0, scale = 1.0)

  else:
    # --- Multiple Units Selected ---
    let countText = $selection.len & " units selected"
    let (countKey, countSize) = getUnitInfoLabel(countText, UnitInfoLargeFontSize)
    bxy.drawImage(countKey, vec2(textX, y), angle = 0, scale = 1.0)
    y += countSize.y.float32 + 8.0

    # Count by unit class
    var classCounts: array[AgentUnitClass, int]
    for thing in selection:
      if thing.kind == Agent:
        inc classCounts[thing.unitClass]

    # Display composition
    for unitClass in AgentUnitClass:
      let count = classCounts[unitClass]
      if count > 0:
        let compText = $count & "x " & UnitClassLabels[unitClass]
        let (compKey, _) = getUnitInfoLabel(compText)
        bxy.drawImage(compKey, vec2(textX, y), angle = 0, scale = 1.0)
        y += UnitInfoLineHeight - 4.0
        if y > panelY + panelH - UnitInfoPanelPadding:
          break

# ─── Resource Bar HUD ─────────────────────────────────────────────────────────

const
  ResourceBarPadding = 8.0'f32
  ResourceBarIconScale = 1.0'f32 / 350.0'f32
  ResourceBarFontSize: float32 = 20
  ResourceBarLabelPadding = 4.0'f32
  ResourceBarItemGap = 24.0'f32
  ResourceBarSeparatorWidth = 2.0'f32

var
  resourceBarLabelImages: Table[string, string] = initTable[string, string]()
  resourceBarLabelSizes: Table[string, IVec2] = initTable[string, IVec2]()

proc ensureResourceBarLabel(text: string): (string, IVec2) =
  if text in resourceBarLabelImages:
    return (resourceBarLabelImages[text], resourceBarLabelSizes[text])
  let (image, size) = renderTextLabel(text, FooterFontPath, ResourceBarFontSize,
                                      ResourceBarLabelPadding, 0.0)
  let key = "resource_bar/" & text.replace(" ", "_").replace("/", "_")
  bxy.addImage(key, image)
  resourceBarLabelImages[text] = key
  resourceBarLabelSizes[text] = size
  result = (key, size)

proc drawResourceBar*(panelRect: IRect, teamId: int) =
  ## Draw the resource bar HUD at the top of the viewport.
  let barY = panelRect.y.float32
  let barW = panelRect.w.float32
  let barH = ResourceBarHeight.float32

  bxy.drawRect(rect = Rect(x: panelRect.x.float32, y: barY, w: barW, h: barH),
               color = color(0.12, 0.16, 0.2, 0.9))

  # Semantic capture: resource bar panel
  pushSemanticContext("ResourceBar")
  capturePanel("ResourceBar", vec2(panelRect.x.float32, barY), vec2(barW, barH))

  let validTeamId = if teamId >= 0 and teamId < MapRoomObjectsTeams: teamId else: 0

  var x = panelRect.x.float32 + ResourceBarPadding
  # Offset content down by half bar height to avoid text clipping at viewport top
  let centerY = barY + barH

  # Team color swatch (16x16)
  let swatchSize = 16.0'f32
  let teamColor = getTeamColor(env, validTeamId, color(0.5, 0.5, 0.5, 1.0))
  bxy.drawRect(rect = Rect(x: x, y: centerY - swatchSize * 0.5, w: swatchSize, h: swatchSize),
               color = teamColor)
  captureRect("TeamColor", vec2(x, centerY - swatchSize * 0.5), vec2(swatchSize, swatchSize))
  x += swatchSize + ResourceBarItemGap

  # Resource counts
  template drawResource(res: StockpileResource, iconKey: string, resName: string) =
    let count = env.teamStockpiles[validTeamId].counts[res]
    let countText = $count
    let (labelKey, labelSize) = ensureResourceBarLabel(countText)
    if iconKey in bxy:
      let iconSize = 24.0'f32
      let iconPos = vec2(x, centerY - iconSize * 0.5 * 350 * ResourceBarIconScale)
      bxy.drawImage(iconKey, iconPos, angle = 0, scale = ResourceBarIconScale)
      captureIcon(resName, iconPos, vec2(iconSize * ResourceBarIconScale * 350,
                  iconSize * ResourceBarIconScale * 350))
      x += iconSize * ResourceBarIconScale * 350 + 4.0
    if labelKey in bxy:
      let labelPos = vec2(x, centerY - labelSize.y.float32 * 0.5)
      bxy.drawImage(labelKey, labelPos, angle = 0, scale = 1.0)
      captureLabel(countText, labelPos, vec2(labelSize.x.float32, labelSize.y.float32))
      x += labelSize.x.float32 + ResourceBarItemGap

  drawResource(ResourceFood, itemSpriteKey(ItemWheat), "food")
  drawResource(ResourceWood, itemSpriteKey(ItemWood), "wood")
  drawResource(ResourceStone, itemSpriteKey(ItemStone), "stone")
  drawResource(ResourceGold, itemSpriteKey(ItemGold), "gold")

  # Separator
  bxy.drawRect(rect = Rect(x: x, y: centerY - barH * 0.3, w: ResourceBarSeparatorWidth, h: barH * 0.6),
               color = color(0.4, 0.4, 0.4, 0.8))
  x += ResourceBarSeparatorWidth + ResourceBarItemGap

  # Population
  var popCount = 0
  var popCap = 0
  for agent in env.agents:
    if isAgentAlive(env, agent):
      let agentTeam = getTeamId(agent)
      if agentTeam == validTeamId:
        inc popCount
  for house in env.thingsByKind[House]:
    if house.teamId == validTeamId:
      popCap += HousePopCap
  for tc in env.thingsByKind[TownCenter]:
    if tc.teamId == validTeamId:
      popCap += TownCenterPopCap
  popCap = min(popCap, MapAgentsPerTeam)

  if "oriented/gatherer.s" in bxy:
    let popIconPos = vec2(x, centerY - 12.0)
    bxy.drawImage("oriented/gatherer.s", popIconPos, angle = 0, scale = ResourceBarIconScale)
    captureIcon("population", popIconPos, vec2(24.0 * ResourceBarIconScale * 350,
                24.0 * ResourceBarIconScale * 350))
    x += 24.0 * ResourceBarIconScale * 350 + 4.0

  let popText = $popCount & "/" & $popCap
  let (popLabelKey, popLabelSize) = ensureResourceBarLabel(popText)
  if popLabelKey in bxy:
    let popLabelPos = vec2(x, centerY - popLabelSize.y.float32 * 0.5)
    bxy.drawImage(popLabelKey, popLabelPos, angle = 0, scale = 1.0)
    captureLabel(popText, popLabelPos, vec2(popLabelSize.x.float32, popLabelSize.y.float32))
    x += popLabelSize.x.float32 + ResourceBarItemGap

  # Separator
  bxy.drawRect(rect = Rect(x: x, y: centerY - barH * 0.3, w: ResourceBarSeparatorWidth, h: barH * 0.6),
               color = color(0.4, 0.4, 0.4, 0.8))
  x += ResourceBarSeparatorWidth + ResourceBarItemGap

  # Step counter
  let stepText = "Step " & $env.currentStep
  let (stepLabelKey, stepLabelSize) = ensureResourceBarLabel(stepText)
  if stepLabelKey in bxy:
    let stepLabelPos = vec2(x, centerY - stepLabelSize.y.float32 * 0.5)
    bxy.drawImage(stepLabelKey, stepLabelPos, angle = 0, scale = 1.0)
    captureLabel(stepText, stepLabelPos, vec2(stepLabelSize.x.float32, stepLabelSize.y.float32))
    x += stepLabelSize.x.float32 + ResourceBarItemGap

  # Mode indicator (right-aligned) - shows current AI/Player control state
  let modeText = if teamId < 0: "[OBSERVING]" else: "[PLAYER Team " & $teamId & "]"
  let (modeLabelKey, modeLabelSize) = ensureResourceBarLabel(modeText)
  if modeLabelKey in bxy:
    let modeX = panelRect.x.float32 + barW - modeLabelSize.x.float32 - ResourceBarPadding
    let modeLabelPos = vec2(modeX, centerY - modeLabelSize.y.float32 * 0.5)
    bxy.drawImage(modeLabelKey, modeLabelPos, angle = 0, scale = 1.0)
    captureLabel(modeText, modeLabelPos, vec2(modeLabelSize.x.float32, modeLabelSize.y.float32))

  popSemanticContext()

# ─── Trade Route Visualization ─────────────────────────────────────────────────

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
      let inView1 = isInViewport(p1.ivec2) or isInViewport(p2.ivec2)
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
          if isInViewport(dotPos.ivec2):
            # Pulsing brightness based on position
            let brightness = 0.7 + 0.3 * sin(t * 3.14159)
            let dotColor = color(
              min(routeColor.r * brightness + 0.2, 1.0),
              min(routeColor.g * brightness + 0.1, 1.0),
              min(routeColor.b * brightness, 1.0),
              0.9
            )
            bxy.drawImage("floor", dotPos, angle = 0, scale = 1/350, tint = dotColor)

    # Draw line from trade cog to target dock (if exists)
    if route.hasTarget:
      let p3 = route.targetDockPos
      let dx2 = p3.x - p2.x
      let dy2 = p3.y - p2.y
      let len2 = sqrt(dx2 * dx2 + dy2 * dy2)

      if len2 > 0.5:
        let inView2 = isInViewport(p2.ivec2) or isInViewport(p3.ivec2)
        if inView2:
          # Draw lighter line to target (trade cog hasn't been there yet)
          let targetColor = color(routeColor.r, routeColor.g, routeColor.b, routeColor.a * 0.5)
          drawLineWorldSpace(p2, p3, targetColor)

  # Draw dock markers for docks with active trade routes
  var drawnDocks: seq[IVec2] = @[]
  for route in activeRoutes:
    let homeDock = route.homeDockPos.ivec2
    if isInViewport(homeDock) and homeDock notin drawnDocks:
      drawnDocks.add(homeDock)
      # Draw a gold coin indicator at the dock
      bxy.drawImage("floor", homeDock.vec2 + vec2(0.0, -0.4), angle = 0,
                    scale = 1/280, tint = TradeRouteGoldColor)

    if route.hasTarget:
      let targetDock = route.targetDockPos.ivec2
      if isInViewport(targetDock) and targetDock notin drawnDocks:
        drawnDocks.add(targetDock)
        # Draw a smaller gold indicator at target dock
        bxy.drawImage("floor", targetDock.vec2 + vec2(0.0, -0.4), angle = 0,
                      scale = 1/320, tint = color(TradeRouteGoldColor.r,
                                                   TradeRouteGoldColor.g,
                                                   TradeRouteGoldColor.b, 0.5))

# ─── Building Ghost Preview ─────────────────────────────────────────────────────

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
