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
  overlayLabelImages: Table[string, string] = initTable[string, string]()
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
  "Battering Ram",
  "Mangonel",
  "Trebuchet",
  "Goblin",
  "Boat",
  "Trade Cog",
  # Castle unique units
  "Samurai",
  "Longbowman",
  "Cataphract",
  "Woad Raider",
  "Teutonic Knight",
  "Huskarl",
  "Mameluke",
  "Janissary",
  "King"
]

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
  for floorKind in FloorSpriteKind:
    let floorSprite = case floorKind
      of FloorCave: "cave"
      of FloorDungeon: "dungeon"
      of FloorBase: "floor"
    for pos in floorSpritePositions[floorKind]:
      let bc = combinedTileTint(env, pos.x, pos.y)
      bxy.drawImage(floorSprite, pos.vec2, angle = 0, scale = SpriteScale,
        tint = color(min(bc.r * bc.intensity, 1.5), min(bc.g * bc.intensity, 1.5),
                     min(bc.b * bc.intensity, 1.5), 1.0))

proc drawTerrain*() =
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
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
    if not isValidPos(pos):
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
      bxy.drawImage(waterKey, pos.vec2, angle = 0, scale = SpriteScale)
    # Draw shallow water (passable but slow) with lighter tint to distinguish
    let shallowTint = color(0.6, 0.85, 0.95, 1.0)  # Lighter blue-green for wading depth
    for pos in shallowWaterPositions:
      bxy.drawImage(waterKey, pos.vec2, angle = 0, scale = SpriteScale, tint = shallowTint)

  for kind in CliffDrawOrder:
    let spriteKey = thingSpriteKey(kind)
    if spriteKey.len > 0 and spriteKey in bxy:
      for cliff in env.thingsByKind[kind]:
        bxy.drawImage(spriteKey, cliff.pos.vec2, angle = 0, scale = SpriteScale)

  template drawThings(thingKind: ThingKind, body: untyped) =
    for it in env.thingsByKind[thingKind]:
      let thing {.inject.} = it
      let pos {.inject.} = it.pos
      body

  for kind in [Tree, Wheat, Stubble]:
    let spriteKey = thingSpriteKey(kind)
    if spriteKey.len > 0 and spriteKey in bxy:
      for thing in env.thingsByKind[kind]:
        let pos = thing.pos
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
      bxy.drawImage(agentSpriteKey, pos.vec2, angle = 0,
                    scale = SpriteScale, tint = env.agentColors[agent.agentId])

  drawThings(Altar):
    let altarTint = if env.altarColors.hasKey(pos): env.altarColors[pos]
      elif pos.x >= 0 and pos.x < MapWidth and pos.y >= 0 and pos.y < MapHeight:
        let base = env.baseTintColors[pos.x][pos.y]
        color(base.r, base.g, base.b, 1.0)
      else: color(1.0, 1.0, 1.0, 1.0)
    let posVec = pos.vec2
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
    if isTileFrozen(pos, env):
      bxy.drawImage("frozen", posVec, angle = 0, scale = SpriteScale)

  drawThings(Tumor):
    let prefix = if thing.hasClaimedTerritory: "oriented/tumor.expired." else: "oriented/tumor."
    let key = prefix & TumorDirKeys[thing.orientation.int]
    if key in bxy:
      bxy.drawImage(key, pos.vec2, angle = 0, scale = SpriteScale)

  drawThings(Cow):
    let cowKey = if thing.orientation == Orientation.E: "oriented/cow.r" else: "oriented/cow"
    if cowKey in bxy:
      bxy.drawImage(cowKey, pos.vec2, angle = 0, scale = SpriteScale)

  template drawOrientedThings(thingKind: ThingKind, prefix: string) =
    drawThings(thingKind):
      let key = prefix & OrientationDirKeys[thing.orientation.int]
      if key in bxy:
        bxy.drawImage(key, pos.vec2, angle = 0, scale = SpriteScale)

  drawOrientedThings(Bear, "oriented/bear.")
  drawOrientedThings(Wolf, "oriented/wolf.")

  drawThings(Lantern):
    if "lantern" in bxy:
      let tint = if thing.lanternHealthy:
        let teamId = thing.teamId
        if teamId >= 0 and teamId < env.teamColors.len: env.teamColors[teamId]
        else: color(0.6, 0.6, 0.6, 1.0)
      else: color(0.5, 0.5, 0.5, 1.0)
      bxy.drawImage("lantern", pos.vec2, angle = 0, scale = SpriteScale, tint = tint)

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
        if not isPlacedAt(thing):
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
        if not isPlacedAt(thing):
          continue
        bxy.drawImage(spriteKey, thing.pos.vec2, angle = 0, scale = SpriteScale)
        if thing.kind in {Magma, Stump} and isTileFrozen(thing.pos, env):
          bxy.drawImage("frozen", thing.pos.vec2, angle = 0, scale = SpriteScale)

proc drawVisualRanges*(alpha = 0.2) =
  var visibility: array[MapWidth, array[MapHeight, bool]]
  for agent in env.agents:
    if not isAgentAlive(env, agent):
      continue
    for i in 0 ..< ObservationWidth:
      for j in 0 ..< ObservationHeight:
        let gp = agent.pos + ivec2(i - ObservationWidth div 2, j - ObservationHeight div 2)
        if gp.x >= 0 and gp.x < MapWidth and gp.y >= 0 and gp.y < MapHeight:
          visibility[gp.x][gp.y] = true
  let fogColor = color(0, 0, 0, alpha)
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      if not visibility[x][y]:
        bxy.drawRect(rect(x.float32 - 0.5, y.float32 - 0.5, 1, 1), fogColor)

proc drawAgentDecorations*() =
  type OverlayItem = object
    name: string
    icon: string
    count: int

  for agent in env.agents:
    let pos = agent.pos
    if not isValidPos(pos) or env.grid[pos.x][pos.y] != agent:
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

proc drawGrid*() =
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      bxy.drawImage("grid", ivec2(x, y).vec2, angle = 0, scale = SpriteScale)

proc drawSelection*() =
  for thing in selection:
    if not isNil(thing) and isValidPos(thing.pos):
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
