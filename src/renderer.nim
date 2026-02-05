import
  boxy, pixie, vmath, windy, tables,
  std/[algorithm, math, os, strutils],
  common, environment

# Infection system constants
const
  HeartPlusThreshold = 9           # Switch to compact heart counter after this many
  HeartCountFontPath = "data/Inter-Regular.ttf"
  HeartCountFontSize: float32 = 40
  HeartCountPadding = 6
  SpriteScale = 1.0 / 200.0

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

const
  # Damage number rendering constants
  DamageNumberFontPath = "data/Inter-Regular.ttf"
  DamageNumberFontSize: float32 = 28
  DamageNumberFloatHeight: float32 = 0.8  # World units to float upward

  # Fire flicker effect constants
  FlickerBaseIntensity: float32 = 1.0       # Base brightness
  FlickerAmplitude: float32 = 0.15          # Max brightness variation (±15%)
  FlickerSpeed1: float32 = 0.12             # Primary flicker frequency
  FlickerSpeed2: float32 = 0.23             # Secondary flicker (for organic look)
  FlickerSpeed3: float32 = 0.07             # Slow glow variation
  MagmaFlickerAmplitude: float32 = 0.10     # Magma flickers less than lanterns
  MagmaGlowPulse: float32 = 0.05            # Additional slow pulse for magma

type FloorSpriteKind = enum
  FloorBase
  FloorCave
  FloorDungeon


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
  "oriented/mangonel",             # UnitScorpion (uses mangonel sprite)
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

proc getFireFlicker*(posHash: int): float32 =
  ## Calculate a fire/torch flicker intensity based on frame and position.
  ## Returns a value between (1 - amplitude) and (1 + amplitude).
  ## Uses multiple sine waves at different frequencies for organic-looking flicker.
  ## posHash provides spatial variation so different fires flicker independently.
  let t = frame.float32
  let offset = (posHash mod 1000).float32 * 0.1  # Spatial phase offset
  # Combine multiple sine waves for organic flicker pattern
  let wave1 = sin((t * FlickerSpeed1 + offset) * PI)
  let wave2 = sin((t * FlickerSpeed2 + offset * 1.7) * PI) * 0.6
  let wave3 = sin((t * FlickerSpeed3 + offset * 0.3) * PI) * 0.3
  # Combine waves and scale to amplitude
  let combined = (wave1 + wave2 + wave3) / 1.9  # Normalize to ~[-1, 1]
  result = FlickerBaseIntensity + combined * FlickerAmplitude

proc getMagmaFlicker*(posHash: int): float32 =
  ## Calculate magma glow intensity - slower, more subtle than torch flicker.
  ## Magma has a steady glow with slow pulsing.
  let t = frame.float32
  let offset = (posHash mod 1000).float32 * 0.1
  let wave1 = sin((t * 0.05 + offset) * PI) * MagmaGlowPulse
  let wave2 = sin((t * 0.11 + offset * 1.3) * PI) * MagmaFlickerAmplitude
  result = FlickerBaseIntensity + wave1 + wave2

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

proc drawSegmentBar*(basePos: Vec2, offset: Vec2, ratio: float32,
                     filledColor, emptyColor: Color, segments = 5) =
  let filled = int(ceil(ratio * segments.float32))
  const segStep = 0.16'f32
  let origin = basePos + vec2(-segStep * (segments.float32 - 1) / 2 + offset.x, offset.y)
  for i in 0 ..< segments:
    bxy.drawImage("floor", origin + vec2(segStep * i.float32, 0),
                  angle = 0, scale = 1/500,
                  tint = if i < filled: filledColor else: emptyColor)

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
  let mousePos = window.mousePos.vec2
  for button in buttons:
    let hovered = mousePos.x >= button.rect.x and mousePos.x <= button.rect.x + button.rect.w and
      mousePos.y >= button.rect.y and mousePos.y <= button.rect.y + button.rect.h
    let baseColor = if button.active: color(0.2, 0.5, 0.7, 0.95) else: color(0.2, 0.24, 0.28, 0.9)
    let drawColor = if hovered: color(baseColor.r + 0.08, baseColor.g + 0.08, baseColor.b + 0.08, baseColor.a) else: baseColor
    bxy.drawRect(rect = button.rect, color = drawColor)
    template centerIn(r: Rect, sz: Vec2): Vec2 =
      vec2(r.x + (r.w - sz.x) * 0.5, r.y + (r.h - sz.y) * 0.5)
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
  for floorKind in FloorSpriteKind:
    let floorSprite = case floorKind
      of FloorCave: "cave"
      of FloorDungeon: "dungeon"
      of FloorBase: "floor"
    for pos in floorSpritePositions[floorKind]:
      if not isInViewport(pos):
        continue
      let bc = combinedTileTint(env, pos.x, pos.y)
      bxy.drawImage(floorSprite, pos.vec2, angle = 0, scale = SpriteScale,
        tint = color(min(bc.r * bc.intensity, 1.5), min(bc.g * bc.intensity, 1.5),
                     min(bc.b * bc.intensity, 1.5), 1.0))

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

  for pos in env.actionTintPositions:
    if not isValidPos(pos) or not isInViewport(pos):
      continue
    if env.actionTintCountdown[pos.x][pos.y] > 0:
      let c = env.actionTintColor[pos.x][pos.y]
      # Render the short-lived action overlay fully opaque so it sits above the
      # normal tint layer and clearly masks the underlying tile color.
      bxy.drawImage("floor", pos.vec2, angle = 0, scale = SpriteScale, tint = color(c.r, c.g, c.b, 1.0))

  let waterKey = terrainSpriteKey(Water)

  # Draw water from terrain so agents can occupy those tiles while keeping visuals.
  # Deep water (center of rivers) renders darker, shallow water (edges) renders lighter.
  if renderCacheGeneration != env.mapGeneration:
    rebuildRenderCaches()
  if waterKey.len > 0:
    # Draw deep water (impassable) with standard tint
    for pos in waterPositions:
      if isInViewport(pos):
        bxy.drawImage(waterKey, pos.vec2, angle = 0, scale = SpriteScale)
    # Draw shallow water (passable but slow) with lighter tint to distinguish
    let shallowTint = color(0.6, 0.85, 0.95, 1.0)  # Lighter blue-green for wading depth
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

  for kind in [Tree, Wheat, Stubble]:
    let spriteKey = thingSpriteKey(kind)
    if spriteKey.len > 0 and spriteKey in bxy:
      for thing in env.thingsByKind[kind]:
        let pos = thing.pos
        if not isInViewport(pos):
          continue
        bxy.drawImage(spriteKey, pos.vec2, angle = 0, scale = SpriteScale)
        if isTileFrozen(pos, env):
          bxy.drawImage("frozen", pos.vec2, angle = 0, scale = SpriteScale)

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
      bxy.drawImage(agentSpriteKey, thingPos.vec2, angle = 0,
                    scale = SpriteScale, tint = env.agentColors[agent.agentId])

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

  drawThings(Cow):
    let cowKey = if thing.orientation == Orientation.E: "oriented/cow.r" else: "oriented/cow"
    if cowKey in bxy:
      bxy.drawImage(cowKey, thingPos.vec2, angle = 0, scale = SpriteScale)

  template drawOrientedThings(thingKind: ThingKind, prefix: string) =
    drawThings(thingKind):
      let key = prefix & OrientationDirKeys[thing.orientation.int]
      if key in bxy:
        bxy.drawImage(key, thingPos.vec2, angle = 0, scale = SpriteScale)

  drawOrientedThings(Bear, "oriented/bear.")
  drawOrientedThings(Wolf, "oriented/wolf.")

  drawThings(Lantern):
    if "lantern" in bxy:
      let baseTint = if thing.lanternHealthy:
        let teamId = thing.teamId
        if teamId >= 0 and teamId < env.teamColors.len: env.teamColors[teamId]
        else: color(0.6, 0.6, 0.6, 1.0)
      else: color(0.5, 0.5, 0.5, 1.0)
      # Apply fire flicker effect to healthy lanterns
      let flicker = if thing.lanternHealthy:
        getFireFlicker(thingPos.x * 1000 + thingPos.y)
      else:
        1.0'f32
      let tint = color(
        min(baseTint.r * flicker, 1.5),
        min(baseTint.g * flicker, 1.5),
        min(baseTint.b * flicker, 1.5),
        baseTint.a
      )
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
        let tint =
          if thing.kind in {Door, TownCenter, Barracks, ArcheryRange, Stable, SiegeWorkshop, Castle}:
            let teamId = thing.teamId
            let base = if teamId >= 0 and teamId < env.teamColors.len:
              env.teamColors[teamId]
            else:
              color(0.6, 0.6, 0.6, 0.9)
            color(base.r * 0.75 + 0.1, base.g * 0.75 + 0.1, base.b * 0.75 + 0.1, 0.9)
          else:
            color(1, 1, 1, 1)
        bxy.drawImage(spriteKey, pos.vec2, angle = 0, scale = SpriteScale, tint = tint)
        # Production queue progress bar (AoE2-style)
        if thing.productionQueue.entries.len > 0:
          let entry = thing.productionQueue.entries[0]
          if entry.totalSteps > 0 and entry.remainingSteps > 0:
            let ratio = clamp(1.0'f32 - entry.remainingSteps.float32 / entry.totalSteps.float32, 0.0, 1.0)
            drawSegmentBar(pos.vec2, vec2(0, 0.55), ratio,
                           color(0.2, 0.5, 1.0, 1.0), color(0.3, 0.3, 0.3, 0.7))
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
          # Apply magma flicker effect - glowing lava with slow pulsing
          let flicker = getMagmaFlicker(thing.pos.x * 1000 + thing.pos.y)
          let magmaTint = color(flicker, flicker * 0.85, flicker * 0.6, 1.0)
          bxy.drawImage(spriteKey, thing.pos.vec2, angle = 0, scale = SpriteScale, tint = magmaTint)
        else:
          bxy.drawImage(spriteKey, thing.pos.vec2, angle = 0, scale = SpriteScale)
        if thing.kind in {Magma, Stump} and isTileFrozen(thing.pos, env):
          bxy.drawImage("frozen", thing.pos.vec2, angle = 0, scale = SpriteScale)

proc drawVisualRanges*(alpha = 0.2) =
  if not currentViewport.valid:
    return
  # Optimized: Only process agents whose vision could overlap the viewport
  # Use a smaller visibility buffer for just the viewport area
  var visibility: array[MapWidth, array[MapHeight, bool]]
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
    # Mark visible tiles (only within map bounds)
    let startX = max(0, agent.pos.x - ObservationRadius)
    let endX = min(MapWidth - 1, agent.pos.x + ObservationRadius)
    let startY = max(0, agent.pos.y - ObservationRadius)
    let endY = min(MapHeight - 1, agent.pos.y + ObservationRadius)
    for x in startX .. endX:
      for y in startY .. endY:
        visibility[x][y] = true
  let fogColor = color(0, 0, 0, alpha)
  # Only draw fog for visible tiles
  for x in currentViewport.minX .. currentViewport.maxX:
    for y in currentViewport.minY .. currentViewport.maxY:
      if not visibility[x][y]:
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
    if agent.maxHp > 0:
      drawSegmentBar(posVec, vec2(0, -0.55),
                     clamp(agent.hp.float32 / agent.maxHp.float32, 0.0, 1.0),
                     color(0.1, 0.8, 0.1, 1.0), color(0.3, 0.3, 0.3, 0.7))

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

proc drawProjectiles*() =
  ## Draw visual-only projectiles traveling from source to target.
  ## Uses the "floor" sprite as a small colored dot at the interpolated position.
  for proj in env.projectiles:
    if proj.lifetime <= 0:
      continue
    # Interpolate position: t=1 at source, t=0 at target
    let t = proj.countdown.float32 / proj.lifetime.float32
    let pos = vec2(
      proj.source.x.float32 * t + proj.target.x.float32 * (1.0 - t),
      proj.source.y.float32 * t + proj.target.y.float32 * (1.0 - t))
    let c = ProjectileColors[proj.kind]
    let sc = ProjectileScales[proj.kind]
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

proc drawGrid*() =
  if not currentViewport.valid:
    return
  for x in currentViewport.minX .. currentViewport.maxX:
    for y in currentViewport.minY .. currentViewport.maxY:
      bxy.drawImage("grid", ivec2(x, y).vec2, angle = 0, scale = SpriteScale)

proc drawSelection*() =
  for thing in selection:
    if not isNil(thing) and isValidPos(thing.pos) and isInViewport(thing.pos):
      bxy.drawImage("selection", thing.pos.vec2, angle = 0, scale = SpriteScale)

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

  # Apply fog of war
  if fogTeamId >= 0 and fogTeamId < MapRoomObjectsTeams:
    let invScaleX = minimapInvScaleX
    let invScaleY = minimapInvScaleY
    for py in 0 ..< MinimapSize:
      let my = clamp(int(py.float32 * invScaleY), 0, MapHeight - 1)
      for px in 0 ..< MinimapSize:
        let mx = clamp(int(px.float32 * invScaleX), 0, MapWidth - 1)
        if not env.revealedMaps[fogTeamId][mx][my]:
          # Darken unexplored tiles
          let c = minimapCompositeImage.unsafe[px, py]
          minimapCompositeImage.unsafe[px, py] = rgbx(
            uint8(c.r.int shr 2),
            uint8(c.g.int shr 2),
            uint8(c.b.int shr 2),
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

      # Production Queue
      if building.productionQueue.entries.len > 0:
        let (queueLabelKey, _) = getUnitInfoLabel("Production Queue:")
        bxy.drawImage(queueLabelKey, vec2(textX, y), angle = 0, scale = 1.0)
        y += UnitInfoLineHeight - 4.0

        for i, entry in building.productionQueue.entries:
          if i >= 3: break  # Show max 3 entries
          let unitName = UnitClassLabels[entry.unitClass]
          if i == 0 and entry.totalSteps > 0:
            # First entry with progress bar
            let (entryKey, _) = getUnitInfoLabel(unitName)
            bxy.drawImage(entryKey, vec2(textX, y), angle = 0, scale = 1.0)
            let progRatio = clamp(1.0 - entry.remainingSteps.float32 / entry.totalSteps.float32, 0.0, 1.0)
            let progBarX = textX + 100.0
            let progBarW = 100.0'f32
            bxy.drawRect(Rect(x: progBarX, y: y + 4.0, w: progBarW, h: UnitInfoBarHeight),
                         color(0.2, 0.2, 0.2, 0.9))
            bxy.drawRect(Rect(x: progBarX, y: y + 4.0, w: progBarW * progRatio, h: UnitInfoBarHeight),
                         color(0.2, 0.5, 1.0, 1.0))
          else:
            let queuedText = unitName & " (queued)"
            let (queuedKey, _) = getUnitInfoLabel(queuedText)
            bxy.drawImage(queuedKey, vec2(textX, y), angle = 0, scale = 1.0,
                          tint = color(0.6, 0.6, 0.6, 1.0))
          y += UnitInfoLineHeight - 4.0

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

  let validTeamId = if teamId >= 0 and teamId < MapRoomObjectsTeams: teamId else: 0

  var x = panelRect.x.float32 + ResourceBarPadding
  # Offset content down by half bar height to avoid text clipping at viewport top
  let centerY = barY + barH

  # Team color swatch (16x16)
  let swatchSize = 16.0'f32
  let teamColor = getTeamColor(env, validTeamId, color(0.5, 0.5, 0.5, 1.0))
  bxy.drawRect(rect = Rect(x: x, y: centerY - swatchSize * 0.5, w: swatchSize, h: swatchSize),
               color = teamColor)
  x += swatchSize + ResourceBarItemGap

  # Resource counts
  template drawResource(res: StockpileResource, iconKey: string) =
    let count = env.teamStockpiles[validTeamId].counts[res]
    let countText = $count
    let (labelKey, labelSize) = ensureResourceBarLabel(countText)
    if iconKey in bxy:
      let iconSize = 24.0'f32
      bxy.drawImage(iconKey, vec2(x, centerY - iconSize * 0.5 * 350 * ResourceBarIconScale),
                    angle = 0, scale = ResourceBarIconScale)
      x += iconSize * ResourceBarIconScale * 350 + 4.0
    if labelKey in bxy:
      bxy.drawImage(labelKey, vec2(x, centerY - labelSize.y.float32 * 0.5),
                    angle = 0, scale = 1.0)
      x += labelSize.x.float32 + ResourceBarItemGap

  drawResource(ResourceFood, itemSpriteKey(ItemWheat))
  drawResource(ResourceWood, itemSpriteKey(ItemWood))
  drawResource(ResourceStone, itemSpriteKey(ItemStone))
  drawResource(ResourceGold, itemSpriteKey(ItemGold))

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
    bxy.drawImage("oriented/gatherer.s", vec2(x, centerY - 12.0),
                  angle = 0, scale = ResourceBarIconScale)
    x += 24.0 * ResourceBarIconScale * 350 + 4.0

  let popText = $popCount & "/" & $popCap
  let (popLabelKey, popLabelSize) = ensureResourceBarLabel(popText)
  if popLabelKey in bxy:
    bxy.drawImage(popLabelKey, vec2(x, centerY - popLabelSize.y.float32 * 0.5),
                  angle = 0, scale = 1.0)
    x += popLabelSize.x.float32 + ResourceBarItemGap

  # Separator
  bxy.drawRect(rect = Rect(x: x, y: centerY - barH * 0.3, w: ResourceBarSeparatorWidth, h: barH * 0.6),
               color = color(0.4, 0.4, 0.4, 0.8))
  x += ResourceBarSeparatorWidth + ResourceBarItemGap

  # Step counter
  let stepText = "Step " & $env.currentStep
  let (stepLabelKey, stepLabelSize) = ensureResourceBarLabel(stepText)
  if stepLabelKey in bxy:
    bxy.drawImage(stepLabelKey, vec2(x, centerY - stepLabelSize.y.float32 * 0.5),
                  angle = 0, scale = 1.0)
    x += stepLabelSize.x.float32 + ResourceBarItemGap

  # Mode indicator (right-aligned)
  let modeText = "[AI]"
  let (modeLabelKey, modeLabelSize) = ensureResourceBarLabel(modeText)
  if modeLabelKey in bxy:
    let modeX = panelRect.x.float32 + barW - modeLabelSize.x.float32 - ResourceBarPadding
    bxy.drawImage(modeLabelKey, vec2(modeX, centerY - modeLabelSize.y.float32 * 0.5),
                  angle = 0, scale = 1.0)

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
