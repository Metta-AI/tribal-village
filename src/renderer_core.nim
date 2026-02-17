## renderer_core.nim - Core rendering types, constants, and helpers
##
## Contains: sprite constants, sprite selection helpers, color utilities,
## team color helpers, and other shared rendering infrastructure.

import
  boxy, pixie, vmath, tables, math,
  common, constants, environment

# ─── Shared Constants ────────────────────────────────────────────────────────

const
  SpriteScale* = 1.0 / 200.0

  # Idle animation constants
  IdleAnimationSpeed* = 2.0        # Breathing cycles per second
  IdleAnimationAmplitude* = 0.02   # Scale variation (+/- 2% from base)
  IdleAnimationPhaseScale* = 0.7   # Phase offset multiplier for variation between units

  # Resource depletion animation constants
  DepletionScaleMin* = 0.5         # Minimum scale when resource is empty (50% of full size)
  DepletionScaleMax* = 1.0         # Maximum scale when resource is full (100%)

  # Health bar fade constants
  HealthBarFadeInDuration* = 5     # Steps to fade in after taking damage
  HealthBarVisibleDuration* = 60   # Steps to stay fully visible after damage
  HealthBarFadeOutDuration* = 30   # Steps to fade out after visible period
  HealthBarMinAlpha* = 0.3         # Minimum alpha when faded out (never fully invisible)

  # Shadow constants
  ShadowAlpha* = 0.25'f32
  ShadowOffsetX* = 0.15'f32
  ShadowOffsetY* = 0.10'f32

  # Fire flicker constants
  LanternFlickerSpeed1* = 0.15'f32    # Primary flicker wave speed
  LanternFlickerSpeed2* = 0.23'f32    # Secondary flicker wave speed (faster, irregular)
  LanternFlickerSpeed3* = 0.07'f32    # Tertiary slow wave for organic feel
  LanternFlickerAmplitude* = 0.12'f32 # Brightness variation (+/- 12%)
  MagmaGlowSpeed* = 0.04'f32          # Slower pulsing for magma pools
  MagmaGlowAmplitude* = 0.08'f32      # Subtle glow variation (+/- 8%)

  # Icon and label scale constants
  HeartIconScale* = 1.0 / 420.0       # Scale for heart sprites at altars
  HeartCountLabelScale* = 1.0 / 200.0 # Scale for heart count labels
  OverlayIconScale* = 1.0 / 320.0     # Scale for building overlay icons
  OverlayLabelScale* = 1.0 / 200.0    # Scale for overlay text labels
  SegmentBarDotScale* = 1.0 / 500.0   # Scale for segment/health bar dots
  ScaffoldingPostScale* = 1.0 / 600.0 # Scale for scaffolding post dots
  TradeRouteDotScale* = 1.0 / 350.0   # Scale for trade route animation dots
  DockMarkerScale* = 1.0 / 280.0      # Scale for dock gold coin indicators

  # Control group badge constants
  ControlGroupBadgeFontPath* = "data/Inter-Regular.ttf"
  ControlGroupBadgeFontSize*: float32 = 24
  ControlGroupBadgePadding* = 4.0'f32
  ControlGroupBadgeScale* = 1.0 / 180.0  # Scale for rendering in world space

  # Selection glow
  SelectionGlowScale* = 1.3'f32

# ─── Unit Class Sprite Keys ──────────────────────────────────────────────────

const UnitClassSpriteKeys*: array[AgentUnitClass, string] = [
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
  "oriented/long_swordsman",       # UnitLongSwordsman
  "oriented/champion",             # UnitChampion
  "oriented/light_cavalry",        # UnitLightCavalry
  "oriented/hussar",               # UnitHussar
  "oriented/crossbowman",          # UnitCrossbowman
  "oriented/arbalester",           # UnitArbalester
  "oriented/galley",               # UnitGalley
  "oriented/fire_ship",            # UnitFireShip
  "oriented/fishing_ship",         # UnitFishingShip
  "oriented/transport_ship",       # UnitTransportShip
  "oriented/demo_ship",            # UnitDemoShip
  "oriented/cannon_galleon",       # UnitCannonGalleon
  "oriented/scorpion",             # UnitScorpion
  "oriented/cavalier",             # UnitCavalier
  "oriented/paladin",              # UnitPaladin
  "oriented/camel",                # UnitCamel
  "oriented/heavy_camel",          # UnitHeavyCamel
  "oriented/imperial_camel",       # UnitImperialCamel
  "oriented/skirmisher",           # UnitSkirmisher
  "oriented/elite_skirmisher",     # UnitEliteSkirmisher
  "oriented/cavalry_archer",       # UnitCavalryArcher
  "oriented/heavy_cavalry_archer", # UnitHeavyCavalryArcher
  "oriented/hand_cannoneer",       # UnitHandCannoneer
]

const OrientationDirKeys* = [
  "n",  # N
  "s",  # S
  "w",  # W
  "e",  # E
  "nw", # NW
  "ne", # NE
  "sw", # SW
  "se"  # SE
]

const TumorDirKeys* = [
  "n", # N
  "s", # S
  "w", # W
  "e", # E
  "w", # NW
  "e", # NE
  "w", # SW
  "e"  # SE
]

# ─── Floor Sprite Types ──────────────────────────────────────────────────────

type FloorSpriteKind* = enum
  FloorBase
  FloorCave
  FloorDungeon
  FloorSnow

# ─── Sprite Helper Procs ─────────────────────────────────────────────────────

proc getUnitSpriteBase*(unitClass: AgentUnitClass, agentId: int, packed: bool = true): string =
  ## Determine the base sprite key for a unit based on its class and role.
  ## Used for consistent sprite selection across shadow, agent, and dying unit rendering.
  ## The packed parameter is only relevant for trebuchets (defaults to true for dying units).
  let tbl = UnitClassSpriteKeys[unitClass]
  if tbl.len > 0:
    tbl
  elif unitClass == UnitTrebuchet:
    if packed: "oriented/trebuchet_packed"
    else: "oriented/trebuchet_unpacked"
  else: # UnitVillager: role-based
    case agentId mod MapAgentsPerTeam
    of 0, 1: "oriented/gatherer"
    of 2, 3: "oriented/builder"
    of 4, 5: "oriented/fighter"
    else: "oriented/gatherer"

proc selectUnitSpriteKey*(baseKey: string, orientation: AgentOrientation): string =
  ## Select the appropriate sprite key for a unit given its base key and orientation.
  ##
  ## Attempts to find a direction-specific sprite (e.g., "oriented/gatherer.nw").
  ## Falls back to the south-facing sprite if the direction-specific one doesn't exist.
  ## Returns an empty string if neither sprite is available.
  ##
  ## Parameters:
  ##   baseKey: The base sprite key (e.g., "oriented/gatherer")
  ##   orientation: The unit's facing direction
  ##
  ## Returns:
  ##   The sprite key to use, or empty string if unavailable.
  let dirKey = OrientationDirKeys[orientation.int]
  let orientedImage = baseKey & "." & dirKey
  if orientedImage in bxy: orientedImage
  elif baseKey & ".s" in bxy: baseKey & ".s"
  else: ""

# ─── Color Helper Procs ──────────────────────────────────────────────────────

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

proc toRgbx*(c: Color): ColorRGBX {.inline.} =
  ## Convert a boxy/pixie Color (float 0-1) to silky ColorRGBX (uint8 0-255).
  rgbx(
    uint8(clamp(c.r * 255, 0, 255)),
    uint8(clamp(c.g * 255, 0, 255)),
    uint8(clamp(c.b * 255, 0, 255)),
    uint8(clamp(c.a * 255, 0, 255))
  )

proc colorToRgbx*(c: Color): ColorRGBX =
  rgbx(
    uint8(clamp(c.r * 255, 0, 255)),
    uint8(clamp(c.g * 255, 0, 255)),
    uint8(clamp(c.b * 255, 0, 255)),
    255
  )

# ─── Shadow Rendering ────────────────────────────────────────────────────────

proc renderAgentShadow*(agent: Thing, shadowTint: Color, shadowOffset: Vec2) =
  ## Render a shadow beneath a single agent.
  ##
  ## Draws a semi-transparent dark silhouette offset from the unit's position to
  ## create the illusion of depth. Light source is assumed to be NW, so shadows
  ## cast to the SE (positive X and Y offset).
  ##
  ## Parameters:
  ##   agent: The agent Thing to render shadow for
  ##   shadowTint: Color for the shadow (typically semi-transparent black)
  ##   shadowOffset: Offset vector from agent position to shadow position
  let pos = agent.pos
  if not isValidPos(pos) or env.grid[pos.x][pos.y] != agent or not isInViewport(pos):
    return
  let baseKey = getUnitSpriteBase(agent.unitClass, agent.agentId, agent.packed)
  let shadowSpriteKey = selectUnitSpriteKey(baseKey, agent.orientation)
  if shadowSpriteKey.len > 0:
    let shadowPos = pos.vec2 + shadowOffset
    bxy.drawImage(shadowSpriteKey, shadowPos, angle = 0,
                  scale = SpriteScale, tint = shadowTint)

# ─── Segment Bar Drawing ─────────────────────────────────────────────────────

proc drawSegmentBar*(basePos: Vec2, offset: Vec2, ratio: float32,
                     filledColor, emptyColor: Color, segments = 5, alpha = 1.0'f32) =
  let filled = int(ceil(ratio * segments.float32))
  const segStep = 0.16'f32
  let origin = basePos + vec2(-segStep * (segments.float32 - 1) / 2 + offset.x, offset.y)
  for i in 0 ..< segments:
    let baseColor = if i < filled: filledColor else: emptyColor
    let fadedColor = color(baseColor.r, baseColor.g, baseColor.b, baseColor.a * alpha)
    bxy.drawImage("floor", origin + vec2(segStep * i.float32, 0),
                  angle = 0, scale = SegmentBarDotScale,
                  tint = fadedColor)

# ─── Text Label Rendering ────────────────────────────────────────────────────

const
  HeartCountFontPath* = "data/Inter-Regular.ttf"
  HeartCountFontSize*: float32 = 40
  HeartCountPadding* = 6
  InfoLabelFontPath* = HeartCountFontPath
  InfoLabelFontSize*: float32 = 54
  InfoLabelPadding* = 18
  FooterFontPath* = HeartCountFontPath
  FooterFontSize*: float32 = 26
  FooterPadding* = 10.0'f32
  FooterButtonPaddingX* = 18.0'f32
  FooterButtonGap* = 12.0'f32
  FooterLabelPadding* = 4.0'f32
  FooterHudPadding* = 12.0'f32

template setupCtxFont*(ctx: untyped, fontPath: string, fontSize: float32) =
  ctx.font = fontPath
  ctx.fontSize = fontSize
  ctx.textBaseline = TopBaseline

proc renderTextLabel*(text: string, fontPath: string, fontSize: float32,
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

# ─── Label Caches ────────────────────────────────────────────────────────────

var
  heartCountImages*: Table[int, string] = initTable[int, string]()
  overlayLabelImages*: Table[string, string] = initTable[string, string]()
  infoLabelImages*: Table[string, string] = initTable[string, string]()
  infoLabelSizes*: Table[string, IVec2] = initTable[string, IVec2]()
  controlGroupBadgeImages*: Table[int, string] = initTable[int, string]()
  controlGroupBadgeSizes*: Table[int, IVec2] = initTable[int, IVec2]()

proc ensureHeartCountLabel*(count: int): string =
  ## Cache a simple "x N" label for large heart counts so we can reuse textures.
  if count <= 0: return ""
  if count in heartCountImages: return heartCountImages[count]
  let (image, _) = renderTextLabel("x " & $count, HeartCountFontPath,
                                   HeartCountFontSize, HeartCountPadding.float32, 0.7)
  let key = "heart_count/" & $count
  bxy.addImage(key, image)
  heartCountImages[count] = key
  result = key

proc ensureControlGroupBadge*(groupNum: int): (string, IVec2) =
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

# ─── Cliff Draw Order ────────────────────────────────────────────────────────

const CliffDrawOrder* = [
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

# ─── Render Cache Variables ──────────────────────────────────────────────────

var
  floorSpritePositions*: array[FloorSpriteKind, seq[IVec2]]
  waterPositions*: seq[IVec2] = @[]
  shallowWaterPositions*: seq[IVec2] = @[]
  mountainPositions*: seq[IVec2] = @[]
  renderCacheGeneration* = -1
  # Fog of war visibility buffer - reused across frames to avoid allocation overhead
  fogVisibility*: array[MapWidth, array[MapHeight, bool]]

proc rebuildRenderCaches*() =
  for kind in FloorSpriteKind:
    floorSpritePositions[kind].setLen(0)
  waterPositions.setLen(0)
  shallowWaterPositions.setLen(0)
  mountainPositions.setLen(0)

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
      elif env.terrain[x][y] == Mountain:
        mountainPositions.add(ivec2(x, y))
  renderCacheGeneration = env.mapGeneration

# ─── Wall Sprites ────────────────────────────────────────────────────────────

let wallSprites* = block:
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

type WallTile* = enum
  WallE = 1,
  WallS = 2,
  WallW = 4,
  WallN = 8,
  WallSE = 2 or 1,
  WallNW = 8 or 4,

# ─── Heart Plus Threshold ────────────────────────────────────────────────────

const HeartPlusThreshold* = 9  # Switch to compact heart counter after this many
