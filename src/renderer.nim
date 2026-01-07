import
  boxy, vmath, windy, tables,
  std/[algorithm, math, strutils],
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
  stepLabelKey = ""
  stepLabelLastValue = -1
  stepLabelSize = ivec2(0, 0)

type FloorSpriteKind = enum
  FloorBase
  FloorCave
  FloorDungeon

var
  floorSpritePositions: array[FloorSpriteKind, seq[IVec2]]
  waterPositions: seq[IVec2] = @[]
  renderCacheGeneration = -1

proc rememberAssetKey*(key: string) =
  discard

template configureHeartFont(ctx: var Context) =
  ctx.font = HeartCountFontPath
  ctx.fontSize = HeartCountFontSize
  ctx.textBaseline = TopBaseline

const
  InfoLabelFontPath = HeartCountFontPath
  InfoLabelFontSize: float32 = 54
  InfoLabelPadding = 18
  InfoLabelInsetX = 100
  InfoLabelInsetY = 50
  StepLabelInsetY = 20

template configureInfoLabelFont(ctx: var Context) =
  ctx.font = InfoLabelFontPath
  ctx.fontSize = InfoLabelFontSize
  ctx.textBaseline = TopBaseline

proc ensureInfoLabel(text: string): string =
  if text in infoLabelImages:
    return infoLabelImages[text]

  var measureCtx = newContext(1, 1)
  configureInfoLabelFont(measureCtx)
  let metrics = measureCtx.measureText(text)
  let labelWidth = max(1, metrics.width.int + InfoLabelPadding * 2)
  let labelHeight = max(1, measureCtx.fontSize.int + InfoLabelPadding * 2)

  var ctx = newContext(labelWidth, labelHeight)
  configureInfoLabelFont(ctx)
  ctx.fillStyle.color = color(0, 0, 0, 0.6)
  ctx.fillRect(0, 0, labelWidth.float32, labelHeight.float32)
  ctx.fillStyle.color = color(1, 1, 1, 1)
  ctx.fillText(text, vec2(InfoLabelPadding.float32, InfoLabelPadding.float32))

  let key = "selection_label/" & text.replace(" ", "_").replace("/", "_")
  bxy.addImage(key, ctx.image, mipmaps = false)
  infoLabelImages[text] = key
  result = key

proc ensureStepLabel(step: int): string =
  if stepLabelLastValue == step and stepLabelKey.len > 0:
    return stepLabelKey
  stepLabelLastValue = step

  let text = "Step " & $step
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
  result = stepLabelKey

proc getInfectionLevel*(pos: IVec2): float32 =
  ## Simple infection level based on color temperature
  return if isTileFrozen(pos, env): 1.0 else: 0.0

proc spriteScale(_: string): float32 =
  SpriteScale

proc resolveSpriteKey(key: string): string =
  key

proc useSelections*() =
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

proc drawOverlayIf(infected: bool, overlaySprite: string, pos: Vec2) =
  ## Tiny helper to reduce repeated overlay checks.
  if infected:
    bxy.drawImage(overlaySprite, pos, angle = 0, scale = spriteScale(overlaySprite))

proc drawFrozenOverlay(pos: IVec2) =
  if getInfectionLevel(pos) >= 1.0:
    drawOverlayIf(true, "frozen", pos.vec2)

proc drawFrozenOverlayIfNeeded(kind: ThingKind, pos: IVec2) =
  if kind in {Magma, Stump, Wheat}:
    drawFrozenOverlay(pos)

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

proc ensureRenderCaches() =
  if renderCacheGeneration != env.mapGeneration:
    rebuildRenderCaches()

proc drawFloor*() =
  ensureRenderCaches()
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

      bxy.drawImage(floorSprite, pos.vec2, angle = 0, scale = spriteScale(floorSprite),
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
        bxy.drawImage(spriteKey, pos.vec2, angle = 0, scale = spriteScale(spriteKey))

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

proc generateWallSprites(): seq[string] =
  result = newSeq[string](16)
  for i in 0 .. 15:
    var suffix = ""
    if (i and 8) != 0: suffix.add("n")
    if (i and 4) != 0: suffix.add("w")
    if (i and 2) != 0: suffix.add("s")
    if (i and 1) != 0: suffix.add("e")

    if suffix.len > 0:
      result[i] = "wall." & suffix
    else:
      result[i] = "wall"

const wallSprites = generateWallSprites()

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

        let brightness = 0.3  # Fixed wall brightness
        let wallTint = color(brightness, brightness, brightness, 1.0)

        let wallSpriteKey = wallSprites[tile]
        bxy.drawImage(wallSpriteKey, vec2(x.float32, y.float32),
                     angle = 0, scale = spriteScale(wallSpriteKey), tint = wallTint)

  for fillPos in wallFills:
    let brightness = 0.3  # Fixed wall fill brightness
    let fillTint = color(brightness, brightness, brightness, 1.0)
    let fillSpriteKey = "wall.fill"
    bxy.drawImage(fillSpriteKey, fillPos.vec2 + vec2(0.5, 0.3),
                  angle = 0, scale = spriteScale(fillSpriteKey), tint = fillTint)

proc drawObjects*() =
  for pos in env.actionTintPositions:
    if pos.x < 0 or pos.x >= MapWidth or pos.y < 0 or pos.y >= MapHeight:
      continue
    if env.actionTintCountdown[pos.x][pos.y] > 0:
      let c = env.actionTintColor[pos.x][pos.y]
      # Render the short-lived action overlay fully opaque so it sits above the
      # normal tint layer and clearly masks the underlying tile color.
      bxy.drawImage("floor", pos.vec2, angle = 0, scale = spriteScale("floor"), tint = color(c.r, c.g, c.b, 1.0))

  let waterKey = terrainSpriteKey(Water)
  let drawWaterTile = proc(pos: Vec2) =
    if waterKey.len > 0:
      bxy.drawImage(waterKey, pos, angle = 0, scale = spriteScale(waterKey))

  # Draw water from terrain so agents can occupy those tiles while keeping visuals.
  ensureRenderCaches()
  for pos in waterPositions:
    drawWaterTile(pos.vec2)

  template drawThings(thingKind: ThingKind, body: untyped) =
    for thing in env.thingsByKind[thingKind]:
      let t = thing
      let thing {.inject.} = t
      let pos {.inject.} = thing.pos
      body

  drawThings(Pine):
    let treeSprite = resolveSpriteKey(thingSpriteKey(thing.kind))
    bxy.drawImage(treeSprite, pos.vec2, angle = 0, scale = spriteScale(treeSprite))
    drawFrozenOverlay(pos)

  drawThings(Palm):
    let treeSprite = resolveSpriteKey(thingSpriteKey(thing.kind))
    bxy.drawImage(treeSprite, pos.vec2, angle = 0, scale = spriteScale(treeSprite))
    drawFrozenOverlay(pos)

  drawThings(Agent):
    let agent = thing
    var agentImage = case agent.orientation:
      of N: "agent.n"
      of S: "agent.s"
      of E: "agent.e"
      of W: "agent.w"
      of NW: "agent.w"
      of NE: "agent.e"
      of SW: "agent.w"
      of SE: "agent.e"
    bxy.drawImage(
      agentImage,
      pos.vec2,
      angle = 0,
      scale = spriteScale(agentImage),
      tint = generateEntityColor("agent", agent.agentId)
    )

  drawThings(Altar):
    let baseImage = resolveSpriteKey("altar")
    let altarTint = getAltarColor(pos)
    bxy.drawImage(
      "floor",
      pos.vec2,
      angle = 0,
      scale = spriteScale("floor"),
      tint = color(altarTint.r, altarTint.g, altarTint.b, 0.35)
    )
    bxy.drawImage(
      baseImage,
      pos.vec2,
      angle = 0,
      scale = spriteScale(baseImage),
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
    drawFrozenOverlay(pos)

  drawThings(Tumor):
    let spriteDir = case thing.orientation:
      of N: "n"
      of S: "s"
      of E, NE, SE: "e"
      of W, NW, SW: "w"
    let spritePrefix = if thing.hasClaimedTerritory:
      "tumor."
    else:
      "tumor.color."
    let baseImage = spritePrefix & spriteDir
    bxy.drawImage(baseImage, pos.vec2, angle = 0, scale = spriteScale(baseImage))

  drawThings(Cow):
    let cowSprite = if thing.orientation == Orientation.E: "cow.r" else: "cow"
    bxy.drawImage(cowSprite, pos.vec2, angle = 0, scale = spriteScale(cowSprite))

  drawThings(Lantern):
    let lanternKey = resolveSpriteKey("lantern")
    if thing.lanternHealthy:
      let teamColor = env.teamColors[thing.teamId]
      bxy.drawImage(lanternKey, pos.vec2, angle = 0, scale = spriteScale(lanternKey), tint = teamColor)
    else:
      bxy.drawImage(lanternKey, pos.vec2, angle = 0, scale = spriteScale(lanternKey), tint = color(0.5, 0.5, 0.5, 1.0))

  for kind in ThingKind:
    if kind in {Wall, Pine, Palm, Agent, Altar, Tumor, Cow, Lantern}:
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
        let spriteKey = resolveSpriteKey(buildingSpriteKey(thing.kind))
        let tint =
          if thing.kind == Door:
            let base = env.teamColors[thing.teamId]
            color(base.r * 0.75 + 0.1, base.g * 0.75 + 0.1, base.b * 0.75 + 0.1, 0.9)
          else:
            color(1, 1, 1, 1)
        bxy.drawImage(spriteKey, pos.vec2, angle = 0, scale = spriteScale(spriteKey), tint = tint)
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
        let infected = getInfectionLevel(pos) >= 1.0
        var spriteKey = thingSpriteKey(thing.kind)
        if thing.kind == Wheat:
          let remaining = getInv(thing, ItemWheat)
          if remaining > 0 and remaining < ResourceNodeInitial:
            spriteKey = "wheat_half"
        let resolved = resolveSpriteKey(spriteKey)
        bxy.drawImage(resolved, pos.vec2, angle = 0, scale = spriteScale(resolved))
        if infected:
          drawFrozenOverlayIfNeeded(thing.kind, pos)

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

proc drawFogOfWar*() =
  drawVisualRanges(alpha = 1.0)


proc drawAgentDecorations*() =
  for agent in env.agents:
    if not isValidPos(agent.pos):
      continue
    if env.grid[agent.pos.x][agent.pos.y] != agent:
      continue
    # Frozen overlay
    if agent.frozen > 0:
      bxy.drawImage("frozen", agent.pos.vec2, angle = 0, scale = spriteScale("frozen"))

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

    proc iconForItem(key: ItemKey): string =
      resolveSpriteKey(itemSpriteKey(key))

    var overlays: seq[OverlayItem] = @[]
    for key, count in agent.inventory.pairs:
      if count <= 0:
        continue
      overlays.add(OverlayItem(name: key, icon: iconForItem(key), count: count))

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
        scale = spriteScale("grid")
      )

proc drawSelection*() =
  if not isNil(selection):
    bxy.drawImage(
      "selection",
      selection.pos.vec2,
      angle = 0,
      scale = spriteScale("selection")
    )

proc drawSelectionLabel*(panelRect: IRect) =
  if selectedPos.x < 0 or selectedPos.x >= MapWidth or
     selectedPos.y < 0 or selectedPos.y >= MapHeight:
    return

  var label = ""
  let thing = env.grid[selectedPos.x][selectedPos.y]
  let overlay = env.overlayGrid[selectedPos.x][selectedPos.y]
  if not isNil(thing):
    label =
      if thing.kind == Agent:
        case thing.unitClass
        of UnitVillager: "Villager"
        of UnitManAtArms: "Man-at-Arms"
        of UnitArcher: "Archer"
        of UnitScout: "Scout"
        of UnitKnight: "Knight"
        of UnitMonk: "Monk"
        of UnitSiege: "Siege"
      elif isBuildingKind(thing.kind):
        buildingDisplayName(thing.kind)
      else:
        case thing.kind
        of Agent:
          case thing.unitClass
          of UnitVillager: "Villager"
          of UnitManAtArms: "Man-at-Arms"
          of UnitArcher: "Archer"
          of UnitScout: "Scout"
          of UnitKnight: "Knight"
          of UnitMonk: "Monk"
          of UnitSiege: "Siege"
        else:
          thingDisplayName(thing.kind)
  elif not isNil(overlay):
    label = thingDisplayName(overlay.kind)
  else:
    let terrain = env.terrain[selectedPos.x][selectedPos.y]
    let name = TerrainCatalog[terrain].displayName
    label = if name.len > 0: name else: $terrain

  let key = ensureInfoLabel(label)
  if key.len == 0:
    return
  let pos = vec2(panelRect.x.float32 + 8 + InfoLabelInsetX.float32,
    panelRect.y.float32 + 8 + InfoLabelInsetY.float32)
  bxy.drawImage(key, pos, angle = 0, scale = 1)

proc drawStepLabel*(panelRect: IRect) =
  let key = ensureStepLabel(env.currentStep)
  if key.len == 0:
    return
  let scale = window.contentScale.float32
  let labelW = stepLabelSize.x.float32 / scale
  let pos = vec2(
    panelRect.x.float32 + panelRect.w.float32 - labelW - 2.0,
    panelRect.y.float32 + StepLabelInsetY.float32
  )
  bxy.drawImage(key, pos, angle = 0, scale = 1)
