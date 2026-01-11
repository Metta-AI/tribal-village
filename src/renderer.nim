import
  boxy, vmath, windy, tables,
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
  infoLabelImages: Table[string, string] = initTable[string, string]()
  infoLabelSizes: Table[string, IVec2] = initTable[string, IVec2]()
  stepLabelKey = ""
  stepLabelLastValue = -1
  stepLabelSize = ivec2(0, 0)
  footerLabelImages: Table[string, string] = initTable[string, string]()
  footerLabelSizes: Table[string, IVec2] = initTable[string, IVec2]()
  footerIconSizes: Table[string, IVec2] = initTable[string, IVec2]()

type FloorSpriteKind = enum
  FloorBase
  FloorCave
  FloorDungeon

const UnitClassLabels: array[AgentUnitClass, string] = [
  "Villager",
  "Man-at-Arms",
  "Archer",
  "Scout",
  "Knight",
  "Monk",
  "Siege"
]

var
  floorSpritePositions: array[FloorSpriteKind, seq[IVec2]]
  waterPositions: seq[IVec2] = @[]
  renderCacheGeneration = -1

template configureHeartFont(ctx: var Context) =
  ctx.font = HeartCountFontPath
  ctx.fontSize = HeartCountFontSize
  ctx.textBaseline = TopBaseline

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

template configureInfoLabelFont(ctx: var Context) =
  ctx.font = InfoLabelFontPath
  ctx.fontSize = InfoLabelFontSize
  ctx.textBaseline = TopBaseline

template configureFooterFont(ctx: var Context) =
  ctx.font = FooterFontPath
  ctx.fontSize = FooterFontSize
  ctx.textBaseline = TopBaseline

proc useSelections*(blockSelection = false) =
  if blockSelection:
    return
  if window.buttonPressed[MouseLeft]:
    mouseDownPos = logicalMousePos(window)

  if window.buttonReleased[MouseLeft]:
    let mouseUpPos = logicalMousePos(window)
    let dragDistance = (mouseUpPos - mouseDownPos).length
    let clickThreshold = 3.0
    if dragDistance <= clickThreshold:
      selection = nil
      let
        mousePos = bxy.getTransform().inverse * window.mousePos.vec2
        gridPos = (mousePos + vec2(0.5, 0.5)).ivec2
      if gridPos.x >= 0 and gridPos.x < MapWidth and
         gridPos.y >= 0 and gridPos.y < MapHeight:
        selectedPos = gridPos
        let thing = env.grid[gridPos.x][gridPos.y]
        if not isNil(thing):
          selection = thing

type FooterButtonKind* = enum
  FooterPlayPause
  FooterStep
  FooterSlow
  FooterFast
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
  let footerY = panelRect.y.float32 + panelRect.h.float32 - FooterHeight.float32
  let buttonHeight = FooterHeight.float32 - FooterPadding * 2.0
  let playIcon = if play: "ui/pause" else: "ui/play"
  let iconKeys = [playIcon, "ui/stepForward", "ui/turtle", "ui/speed", "ui/rabbit"]
  let labels = ["Pause", "Step", "Slow", "Fast", "Super"]
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
      var measureCtx = newContext(1, 1)
      configureFooterFont(measureCtx)
      let metrics = measureCtx.measureText(label)
      let labelWidth = max(1, (metrics.width + FooterLabelPadding * 2).int)
      let labelHeight = max(1, (measureCtx.fontSize + FooterLabelPadding * 2).int)
      var ctx = newContext(labelWidth, labelHeight)
      configureFooterFont(ctx)
      ctx.fillStyle.color = color(1, 1, 1, 1)
      ctx.fillText(label, vec2(FooterLabelPadding, FooterLabelPadding))
      labelKey = "footer_label/" & label.replace(" ", "_").replace("/", "_")
      bxy.addImage(labelKey, ctx.image, mipmaps = false)
      labelSize = ivec2(labelWidth, labelHeight)
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
      else: FooterSuper
    let rect = Rect(
      x: x,
      y: footerY + FooterPadding,
      w: buttonWidths[i],
      h: buttonHeight
    )
    let active = case kind
      of FooterSlow:
        abs(playSpeed - SlowPlaySpeed) < 0.0001
      of FooterFast:
        abs(playSpeed - FastPlaySpeed) < 0.0001
      of FooterSuper:
        abs(playSpeed - SuperPlaySpeed) < 0.0001
      else:
        false
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
  let footerRect = Rect(
    x: panelRect.x.float32,
    y: panelRect.y.float32 + panelRect.h.float32 - FooterHeight.float32,
    w: panelRect.w.float32,
    h: FooterHeight.float32
  )
  bxy.drawRect(rect = footerRect, color = color(0.12, 0.16, 0.2, 0.9))
  let mousePos = window.mousePos.vec2
  for button in buttons:
    let hovered = mousePos.x >= button.rect.x and mousePos.x <= button.rect.x + button.rect.w and
      mousePos.y >= button.rect.y and mousePos.y <= button.rect.y + button.rect.h
    let baseColor = if button.active: color(0.2, 0.5, 0.7, 0.95) else: color(0.2, 0.24, 0.28, 0.9)
    let drawColor = if hovered: color(baseColor.r + 0.08, baseColor.g + 0.08, baseColor.b + 0.08, baseColor.a) else: baseColor
    bxy.drawRect(rect = button.rect, color = drawColor)
    if button.iconKey.len > 0 and button.iconSize.x > 0 and button.iconSize.y > 0:
      let maxIconSize = min(button.rect.w, button.rect.h) * 0.6
      let iconScale = min(1.0'f32, maxIconSize / max(button.iconSize.x.float32, button.iconSize.y.float32))
      let iconShift = vec2(8.0, 9.0) * iconScale
      let iconPos = vec2(
        button.rect.x + (button.rect.w - button.iconSize.x.float32 * iconScale) * 0.5,
        button.rect.y + (button.rect.h - button.iconSize.y.float32 * iconScale) * 0.5
      ) + iconShift
      bxy.drawImage(button.iconKey, iconPos, angle = 0, scale = iconScale)
    else:
      let labelPos = vec2(
        button.rect.x + (button.rect.w - button.labelSize.x.float32) * 0.5,
        button.rect.y + (button.rect.h - button.labelSize.y.float32) * 0.5
      )
      bxy.drawImage(button.labelKey, labelPos, angle = 0, scale = 1)

proc rebuildRenderCaches() =
  for kind in FloorSpriteKind:
    floorSpritePositions[kind].setLen(0)
  waterPositions.setLen(0)

  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      let biome = env.biomes[x][y]
      let floorKind =
        case biome
        of BiomeCavesType:
          FloorCave
        of BiomeDungeonType:
          let noise = block:
            var v = uint32(x) * 374761393'u32 + uint32(y) * 668265263'u32
            v = (v xor (v shr 13)) * 1274126177'u32
            v xor (v shr 16)
          if (noise mod 100) < 35:
            FloorDungeon
          else:
            FloorBase
        else:
          FloorBase
      floorSpritePositions[floorKind].add(ivec2(x, y))

      if env.terrain[x][y] == Water:
        waterPositions.add(ivec2(x, y))

  renderCacheGeneration = env.mapGeneration

proc drawFloor*() =
  if renderCacheGeneration != env.mapGeneration:
    rebuildRenderCaches()
  # Draw the floor tiles everywhere first as the base layer
  for floorKind in FloorSpriteKind:
    let floorSprite = case floorKind
      of FloorCave: "cave"
      of FloorDungeon: "dungeon"
      of FloorBase: "floor"
    for pos in floorSpritePositions[floorKind]:
      let x = pos.x
      let y = pos.y
      let blendedColor = combinedTileTint(env, x, y)

      let finalR = min(blendedColor.r * blendedColor.intensity, 1.5)
      let finalG = min(blendedColor.g * blendedColor.intensity, 1.5)
      let finalB = min(blendedColor.b * blendedColor.intensity, 1.5)

      bxy.drawImage(floorSprite, pos.vec2, angle = 0, scale = SpriteScale,
        tint = color(finalR, finalG, finalB, 1.0))

proc drawTerrain*() =
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      let pos = ivec2(x, y)
      let terrain = env.terrain[x][y]
      if terrain == Water:
        continue
      let spriteKey = terrainSpriteKey(terrain)
      if spriteKey.len > 0:
        bxy.drawImage(spriteKey, pos.vec2, angle = 0, scale = SpriteScale)

proc ensureHeartCountLabel(count: int): string =
  ## Cache a simple "x N" label for large heart counts so we can reuse textures.
  if count <= 0:
    return ""

  if count in heartCountImages:
    return heartCountImages[count]

  let text = "x " & $count

  # First pass to measure how large the label needs to be.
  var measureCtx = newContext(1, 1)
  configureHeartFont(measureCtx)
  let metrics = measureCtx.measureText(text)

  let padding = HeartCountPadding
  let labelWidth = max(1, metrics.width.int + padding * 2)
  let labelHeight = max(1, measureCtx.fontSize.int + padding * 2)

  # Render the text into a fresh image.
  var ctx = newContext(labelWidth, labelHeight)
  configureHeartFont(ctx)
  ctx.fillStyle.color = color(0, 0, 0, 0.7)
  ctx.fillRect(0, 0, labelWidth.float32, labelHeight.float32)
  ctx.fillStyle.color = color(1, 1, 1, 1)
  ctx.fillText(text, vec2(padding.float32, padding.float32))

  let key = "heart_count/" & $count
  bxy.addImage(key, ctx.image, mipmaps = false)
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
  WallNone = 0,
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

  var wallFills: seq[IVec2]
  let wallTint = color(0.3, 0.3, 0.3, 1.0)
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
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

proc drawObjects*() =
  for pos in env.actionTintPositions:
    if pos.x < 0 or pos.x >= MapWidth or pos.y < 0 or pos.y >= MapHeight:
      continue
    if env.actionTintCountdown[pos.x][pos.y] > 0:
      let c = env.actionTintColor[pos.x][pos.y]
      # Render the short-lived action overlay fully opaque so it sits above the
      # normal tint layer and clearly masks the underlying tile color.
      bxy.drawImage("floor", pos.vec2, angle = 0, scale = SpriteScale, tint = color(c.r, c.g, c.b, 1.0))

  let waterKey = terrainSpriteKey(Water)

  # Draw water from terrain so agents can occupy those tiles while keeping visuals.
  if renderCacheGeneration != env.mapGeneration:
    rebuildRenderCaches()
  if waterKey.len > 0:
    for pos in waterPositions:
      bxy.drawImage(waterKey, pos.vec2, angle = 0, scale = SpriteScale)

  template drawThings(thingKind: ThingKind, body: untyped) =
    for thing in env.thingsByKind[thingKind]:
      let t = thing
      let thing {.inject.} = t
      let pos {.inject.} = thing.pos
      body

  drawThings(Tree):
    let treeSprite = thingSpriteKey(thing.kind)
    bxy.drawImage(treeSprite, pos.vec2, angle = 0, scale = SpriteScale)
    if isTileFrozen(pos, env):
      bxy.drawImage("frozen", pos.vec2, angle = 0, scale = SpriteScale)

  drawThings(Wheat):
    let spriteKey = thingSpriteKey(thing.kind)
    bxy.drawImage(spriteKey, pos.vec2, angle = 0, scale = SpriteScale)
    if isTileFrozen(pos, env):
      bxy.drawImage("frozen", pos.vec2, angle = 0, scale = SpriteScale)

  drawThings(Stubble):
    let spriteKey = thingSpriteKey(thing.kind)
    bxy.drawImage(spriteKey, pos.vec2, angle = 0, scale = SpriteScale)
    if isTileFrozen(pos, env):
      bxy.drawImage("frozen", pos.vec2, angle = 0, scale = SpriteScale)

  drawThings(Agent):
    let agent = thing
    let roleKey =
      case agent.agentId mod MapAgentsPerVillage
      of 0, 1: "oriented/gatherer"
      of 2, 3: "oriented/builder"
      of 4, 5: "oriented/fighter"
      else: "oriented/gatherer"
    let dirKey = case agent.orientation:
      of N: "n"
      of S: "s"
      of E: "e"
      of W: "w"
      of NE: "ne"
      of NW: "nw"
      of SE: "se"
      of SW: "sw"
    let agentImage = roleKey & "." & dirKey
    bxy.drawImage(
      agentImage,
      pos.vec2,
      angle = 0,
      scale = SpriteScale,
      tint = env.agentColors[agent.agentId]
    )

  drawThings(Altar):
    let baseImage = "altar"
    let altarTint = block:
      if env.altarColors.hasKey(pos):
        env.altarColors[pos]
      elif pos.x >= 0 and pos.x < MapWidth and pos.y >= 0 and pos.y < MapHeight:
        let base = env.baseTintColors[pos.x][pos.y]
        color(base.r, base.g, base.b, 1.0)
      else:
        color(1.0, 1.0, 1.0, 1.0)
    bxy.drawImage(
      "floor",
      pos.vec2,
      angle = 0,
      scale = SpriteScale,
      tint = color(altarTint.r, altarTint.g, altarTint.b, 0.35)
    )
    bxy.drawImage(
      baseImage,
      pos.vec2,
      angle = 0,
      scale = SpriteScale,
      tint = color(altarTint.r, altarTint.g, altarTint.b, 1.0)
    )
    let heartAnchor = vec2(-0.48, -0.64)
    let heartStep = 0.12
    let heartScale: float32 = 1/420
    let labelScale: float32 = 1/200
    let amt = max(0, thing.hearts)
    if amt == 0:
      let fadedTint = color(altarTint.r, altarTint.g, altarTint.b, 0.35)
      bxy.drawImage("heart", thing.pos.vec2 + heartAnchor, angle = 0, scale = heartScale, tint = fadedTint)
    else:
      if amt <= HeartPlusThreshold:
        let drawCount = amt
        for i in 0 ..< drawCount:
          let posHeart = thing.pos.vec2 + heartAnchor + vec2(heartStep * i.float32, 0.0)
          bxy.drawImage("heart", posHeart, angle = 0, scale = heartScale, tint = altarTint)
      else:
        bxy.drawImage("heart", thing.pos.vec2 + heartAnchor, angle = 0, scale = heartScale, tint = altarTint)
        let labelKey = ensureHeartCountLabel(amt)
        let labelPos = thing.pos.vec2 + heartAnchor + vec2(0.14, -0.08)
        bxy.drawImage(labelKey, labelPos, angle = 0, scale = labelScale, tint = color(1, 1, 1, 1))
    if isTileFrozen(pos, env):
      bxy.drawImage("frozen", pos.vec2, angle = 0, scale = SpriteScale)

  drawThings(Tumor):
    let spriteDir = case thing.orientation:
      of N: "n"
      of S: "s"
      of E, NE, SE: "e"
      of W, NW, SW: "w"
    let spritePrefix = if thing.hasClaimedTerritory:
      "oriented/tumor."
    else:
      "oriented/tumor.color."
    let baseImage = spritePrefix & spriteDir
    bxy.drawImage(baseImage, pos.vec2, angle = 0, scale = SpriteScale)

  drawThings(Cow):
    let cowSprite = if thing.orientation == Orientation.E: "oriented/cow.r" else: "oriented/cow"
    bxy.drawImage(cowSprite, pos.vec2, angle = 0, scale = SpriteScale)

  drawThings(Lantern):
    let lanternKey = "lantern"
    if thing.lanternHealthy:
      let teamColor = env.teamColors[thing.teamId]
      bxy.drawImage(lanternKey, pos.vec2, angle = 0, scale = SpriteScale, tint = teamColor)
    else:
      bxy.drawImage(lanternKey, pos.vec2, angle = 0, scale = SpriteScale, tint = color(0.5, 0.5, 0.5, 1.0))

  for kind in ThingKind:
    if kind in {Wall, Tree, Wheat, Stubble, Agent, Altar, Tumor, Cow, Lantern}:
      continue
    if isBuildingKind(kind):
      for thing in env.thingsByKind[kind]:
        if not isValidPos(thing.pos):
          continue
        if thingBlocksMovement(thing.kind):
          if env.grid[thing.pos.x][thing.pos.y] != thing:
            continue
        else:
          if env.overlayGrid[thing.pos.x][thing.pos.y] != thing:
            continue
        let pos = thing.pos
        let spriteKey = buildingSpriteKey(thing.kind)
        let tint =
          if thing.kind == Door:
            let base = env.teamColors[thing.teamId]
            color(base.r * 0.75 + 0.1, base.g * 0.75 + 0.1, base.b * 0.75 + 0.1, 0.9)
          else:
            color(1, 1, 1, 1)
        bxy.drawImage(spriteKey, pos.vec2, angle = 0, scale = SpriteScale, tint = tint)
        let res = buildingStockpileRes(thing.kind)
        if res != ResourceNone:
          let icon = case res
            of ResourceFood: itemSpriteKey(ItemWheat)
            of ResourceWood: itemSpriteKey(ItemWood)
            of ResourceStone: itemSpriteKey(ItemStone)
            of ResourceGold: itemSpriteKey(ItemGold)
            of ResourceWater: itemSpriteKey(ItemWater)
            of ResourceNone: ""
          let count = env.teamStockpiles[thing.teamId].counts[res]
          let iconScale = 1/320
          let labelScale = 1/200
          let iconPos = pos.vec2 + vec2(-0.18, -0.72)
          let alpha = if count > 0: 1.0 else: 0.35
          bxy.drawImage(icon, iconPos, angle = 0, scale = iconScale, tint = color(1, 1, 1, alpha))
          if count > 0:
            let labelKey = ensureHeartCountLabel(count)
            let labelPos = iconPos + vec2(0.14, -0.08)
            bxy.drawImage(labelKey, labelPos, angle = 0, scale = labelScale, tint = color(1, 1, 1, 1))
    else:
      for thing in env.thingsByKind[kind]:
        if not isValidPos(thing.pos):
          continue
        if thingBlocksMovement(thing.kind):
          if env.grid[thing.pos.x][thing.pos.y] != thing:
            continue
        else:
          if env.overlayGrid[thing.pos.x][thing.pos.y] != thing:
            continue
        let pos = thing.pos
        let infected = isTileFrozen(pos, env)
        var spriteKey = thingSpriteKey(thing.kind)
        bxy.drawImage(spriteKey, pos.vec2, angle = 0, scale = SpriteScale)
        if infected and thing.kind in {Magma, Stump}:
          bxy.drawImage("frozen", pos.vec2, angle = 0, scale = SpriteScale)

proc drawVisualRanges*(alpha = 0.2) =
  var visibility: array[MapWidth, array[MapHeight, bool]]
  for agent in env.agents:
    if not isAgentAlive(env, agent):
      continue
    for i in 0 ..< ObservationWidth:
      for j in 0 ..< ObservationHeight:
        let
          gridPos = (agent.pos + ivec2(i - ObservationWidth div 2, j -
              ObservationHeight div 2))

        if gridPos.x >= 0 and gridPos.x < MapWidth and
           gridPos.y >= 0 and gridPos.y < MapHeight:
          visibility[gridPos.x][gridPos.y] = true

  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      if not visibility[x][y]:
        bxy.drawRect(
          rect(x.float32 - 0.5, y.float32 - 0.5, 1, 1),
          color(0, 0, 0, alpha)
        )

proc drawAgentDecorations*() =
  for agent in env.agents:
    if not isValidPos(agent.pos):
      continue
    if env.grid[agent.pos.x][agent.pos.y] != agent:
      continue
    # Frozen overlay
    if agent.frozen > 0:
      bxy.drawImage("frozen", agent.pos.vec2, angle = 0, scale = SpriteScale)

    # Health bar (5 segments)
    if agent.maxHp > 0:
      let segments = 5
      let ratio = clamp(agent.hp.float32 / agent.maxHp.float32, 0.0, 1.0)
      let filled = int(ceil(ratio * segments.float32))
      let segStep = 0.16
      let totalWidth = segStep * (segments.float32 - 1)
      let baseOffset = vec2(-totalWidth / 2, -0.55)
      for i in 0 ..< segments:
        let tint = if i < filled: color(0.1, 0.8, 0.1, 1.0) else: color(0.3, 0.3, 0.3, 0.7)
        bxy.drawImage("floor", agent.pos.vec2 + vec2(baseOffset.x + segStep * i.float32, baseOffset.y), angle = 0, scale = 1/500, tint = tint)

    # Inventory overlays placed radially, ordered by item name.
    type OverlayItem = object
      name: string
      icon: string
      count: int

    var overlays: seq[OverlayItem] = @[]
    for key, count in agent.inventory.pairs:
      if count <= 0:
        continue
      overlays.add(OverlayItem(name: key, icon: itemSpriteKey(key), count: count))

    if overlays.len == 0:
      continue

    overlays.sort(proc(a, b: OverlayItem): int = cmp(a.name, b.name))

    let basePos = agent.pos.vec2
    let iconScale = 1/320
    let maxStack = 4
    let stackStep = 0.10
    let baseRadius = 0.58
    let startAngle = 135.0  # degrees, top-left from positive X axis
    let step = 360.0 / overlays.len.float32

    for i, ov in overlays:
      let angle = degToRad(startAngle - step * i.float32)
      let dir = vec2(cos(angle).float32, -sin(angle).float32)
      let n = min(ov.count, maxStack)
      for j in 0 ..< n:
        let pos = basePos + dir * (baseRadius + stackStep * j.float32)
        bxy.drawImage(ov.icon, pos, angle = 0, scale = iconScale)

proc drawGrid*() =
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      bxy.drawImage(
        "grid",
        ivec2(x, y).vec2,
        angle = 0,
        scale = SpriteScale
      )

proc drawSelection*() =
  if not isNil(selection):
    bxy.drawImage(
      "selection",
      selection.pos.vec2,
      angle = 0,
      scale = SpriteScale
    )

proc drawSelectionLabel*(panelRect: IRect) =
  if selectedPos.x < 0 or selectedPos.x >= MapWidth or
     selectedPos.y < 0 or selectedPos.y >= MapHeight:
    return

  proc appendResourceCount(label: var string, thing: Thing) =
    var count = 0
    case thing.kind
    of Wheat, Stubble:
      count = getInv(thing, ItemWheat)
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
          label &= " (" & key & " " & $c & ")"
          return
      return
    else:
      return
    label &= " (" & $count & ")"

  template displayNameFor(t: Thing): string =
    if t.kind == Agent:
      UnitClassLabels[t.unitClass]
    elif isBuildingKind(t.kind):
      buildingDisplayName(t.kind)
    else:
      thingDisplayName(t.kind)

  var label = ""
  let thing = env.grid[selectedPos.x][selectedPos.y]
  let overlay = env.overlayGrid[selectedPos.x][selectedPos.y]
  if not isNil(thing):
    label = displayNameFor(thing)
    appendResourceCount(label, thing)
  elif not isNil(overlay):
    label = displayNameFor(overlay)
    appendResourceCount(label, overlay)
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
    var measureCtx = newContext(1, 1)
    configureInfoLabelFont(measureCtx)
    let metrics = measureCtx.measureText(label)
    let labelWidth = max(1, metrics.width.int + InfoLabelPadding * 2)
    let labelHeight = max(1, measureCtx.fontSize.int + InfoLabelPadding * 2)

    var ctx = newContext(labelWidth, labelHeight)
    configureInfoLabelFont(ctx)
    ctx.fillStyle.color = color(0, 0, 0, 0.6)
    ctx.fillRect(0, 0, labelWidth.float32, labelHeight.float32)
    ctx.fillStyle.color = color(1, 1, 1, 1)
    ctx.fillText(label, vec2(InfoLabelPadding.float32, InfoLabelPadding.float32))

    key = "selection_label/" & label.replace(" ", "_").replace("/", "_")
    bxy.addImage(key, ctx.image, mipmaps = false)
    infoLabelImages[label] = key
    infoLabelSizes[label] = ivec2(labelWidth, labelHeight)
    labelSize = ivec2(labelWidth, labelHeight)
  if key.len == 0:
    return
  if labelSize.x <= 0 or labelSize.y <= 0:
    return
  let footerTop = panelRect.y.float32 + panelRect.h.float32 - FooterHeight.float32
  let innerHeight = FooterHeight.float32 - FooterPadding * 2.0
  let scale = min(1.0'f32, innerHeight / labelSize.y.float32)
  let pos = vec2(
    panelRect.x.float32 + FooterHudPadding + 75.0,
    footerTop + FooterPadding + (innerHeight - labelSize.y.float32 * scale) * 0.5 + 20.0
  )
  bxy.drawImage(key, pos, angle = 0, scale = scale)

proc drawStepLabel*(panelRect: IRect) =
  var key = ""
  if stepLabelLastValue == env.currentStep and stepLabelKey.len > 0:
    key = stepLabelKey
  else:
    stepLabelLastValue = env.currentStep
    let text = "Step " & $env.currentStep
    var measureCtx = newContext(1, 1)
    configureInfoLabelFont(measureCtx)
    let metrics = measureCtx.measureText(text)
    let labelWidth = max(1, metrics.width.int + InfoLabelPadding * 2)
    let labelHeight = max(1, measureCtx.fontSize.int + InfoLabelPadding * 2)
    stepLabelSize = ivec2(labelWidth, labelHeight)

    var ctx = newContext(labelWidth, labelHeight)
    configureInfoLabelFont(ctx)
    ctx.fillStyle.color = color(0, 0, 0, 0.6)
    ctx.fillRect(0, 0, labelWidth.float32, labelHeight.float32)
    ctx.fillStyle.color = color(1, 1, 1, 1)
    ctx.fillText(text, vec2(InfoLabelPadding.float32, InfoLabelPadding.float32))

    stepLabelKey = "hud_step"
    bxy.addImage(stepLabelKey, ctx.image, mipmaps = false)
    key = stepLabelKey
  if key.len == 0:
    return
  let footerTop = panelRect.y.float32 + panelRect.h.float32 - FooterHeight.float32
  let innerHeight = FooterHeight.float32 - FooterPadding * 2.0
  let scale = min(1.0'f32, innerHeight / stepLabelSize.y.float32)
  let labelW = stepLabelSize.x.float32 * scale
  let pos = vec2(
    panelRect.x.float32 + panelRect.w.float32 - labelW - FooterHudPadding + 25.0,
    footerTop + FooterPadding + (innerHeight - stepLabelSize.y.float32 * scale) * 0.5 + 20.0
  )
  bxy.drawImage(key, pos, angle = 0, scale = scale)
