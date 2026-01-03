import
  boxy, vmath, windy, tables,
  std/[algorithm, math, strutils],
  common, environment, assets

# Infection system constants
const
  HeartPlusThreshold = 9           # Switch to compact heart counter after this many
  HeartCountFontPath = "data/Inter-Regular.ttf"
  HeartCountFontSize: float32 = 28
  HeartCountPadding = 6

var
  heartCountImages: Table[int, string] = initTable[int, string]()
  infoLabelImages: Table[string, string] = initTable[string, string]()
  doorSpriteKey* = "wall"

proc setDoorSprite*(key: string) =
  doorSpriteKey = key

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

template configureInfoLabelFont(ctx: var Context) =
  ctx.font = InfoLabelFontPath
  ctx.fontSize = InfoLabelFontSize
  ctx.textBaseline = TopBaseline

proc ensureInfoLabel(text: string): string =
  if text.len == 0:
    return ""
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

proc getInfectionLevel*(pos: IVec2): float32 =
  ## Simple infection level based on color temperature
  return if isBuildingFrozen(pos, env): 1.0 else: 0.0

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
        if thing != nil:
          selection = thing

proc drawOverlayIf(infected: bool, overlaySprite: string, pos: Vec2) =
  ## Tiny helper to reduce repeated overlay checks.
  if infected and overlaySprite.len > 0:
    bxy.drawImage(overlaySprite, pos, angle = 0, scale = 1/200)

proc drawRoofTint(spriteKey: string, pos: Vec2, teamId: int) =
  ## Apply village color tint to roof mask overlays when available.
  if teamId < 0 or teamId >= teamColors.len:
    return
  let maskKey = "roofmask." & spriteKey
  if not assetExists(maskKey):
    return
  let tint = teamColors[teamId]
  bxy.drawImage(maskKey, pos, angle = 0, scale = 1/200, tint = tint)

proc toSnakeCase(name: string): string =
  result = ""
  for i, ch in name:
    if ch.isUpperAscii:
      if i > 0:
        result.add('_')
      result.add(ch.toLowerAscii)
    else:
      result.add(ch)

proc thingSpriteKey(kind: ThingKind): string =
  case kind
  of Converter: "magma"
  else: toSnakeCase($kind)

proc hasFrozenOverlay(kind: ThingKind): bool =
  case kind
  of Mine, Converter, Altar, Armory, Forge, ClayOven, WeavingLoom,
     Bed, Chair, Table, Statue, Outpost, Barrel, Mill, LumberCamp, MiningCamp, Farm, Stump,
     TownCenter, House, Barracks, ArcheryRange, Stable, SiegeWorkshop, Blacksmith, Market, Dock,
     Monastery, University, Castle:
    true
  else:
    false

proc drawFloor*() =
  # Draw the floor tiles everywhere first as the base layer
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:

      let tileColor = env.tileColors[x][y]
      let floorSprite = case env.biomes[x][y]
        of BiomeCavesType: "cave_floor"
        of BiomeDungeonType: "dungeon_floor"
        else: "floor"

      let finalR = min(tileColor.r * tileColor.intensity, 1.5)
      let finalG = min(tileColor.g * tileColor.intensity, 1.5)
      let finalB = min(tileColor.b * tileColor.intensity, 1.5)

      bxy.drawImage(floorSprite, ivec2(x, y).vec2, angle = 0, scale = 1/200, tint = color(finalR, finalG, finalB, 1.0))

proc drawTerrain*() =
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      let pos = ivec2(x, y)
      let infectionLevel = getInfectionLevel(pos)
      let infected = infectionLevel >= 1.0
      let terrain = env.terrain[x][y]
      if terrain == Water:
        continue
      var spriteKey = ""
      case terrain
      of Bridge:
        spriteKey = "bridge"
      of Wheat:
        spriteKey = "wheat"
      of Tree:
        spriteKey = "pine"
      of Palm:
        spriteKey = "palm"
      of Fertile:
        spriteKey = "fertile"
      of Road:
        spriteKey = "road"
      of Rock:
        spriteKey = "rock"
      of Gem:
        spriteKey = "gem"
      of Bush:
        spriteKey = "bush"
      of Animal:
        spriteKey = "cow"
      of Grass:
        spriteKey = "grass"
      of Cactus:
        spriteKey = "cactus"
      of Dune:
        spriteKey = "dune"
      of Stalagmite:
        spriteKey = "stalagmite"
      of Sand:
        spriteKey = "sand"
      of Snow:
        spriteKey = "snow"
      of Empty, Water:
        discard
      if spriteKey.len > 0:
        bxy.drawImage(spriteKey, pos.vec2, angle = 0, scale = 1/200)
      if infected and terrain in {Wheat, Tree, Palm}:
        drawOverlayIf(true, "frozen", pos.vec2)

proc drawAttackOverlays*() =
  for pos in env.actionTintPositions:
    if pos.x < 0 or pos.x >= MapWidth or pos.y < 0 or pos.y >= MapHeight:
      continue
    if env.actionTintCountdown[pos.x][pos.y] > 0:
      let c = env.actionTintColor[pos.x][pos.y]
      # Render the short-lived action overlay fully opaque so it sits above the
      # normal tint layer and clearly masks the underlying tile color.
      bxy.drawImage("floor", pos.vec2, angle = 0, scale = 1/200, tint = color(c.r, c.g, c.b, 1.0))

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
  ctx.fillStyle.color = color(0, 0, 0, 1)
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
    env.grid[x][y] != nil and
    env.grid[x][y].kind == Wall

  var wallFills: seq[IVec2]
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      let thing = env.grid[x][y]
      if thing != nil and thing.kind == Wall:
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

        bxy.drawImage(wallSprites[tile], vec2(x.float32, y.float32),
                     angle = 0, scale = 1/200, tint = wallTint)

  for fillPos in wallFills:
    let brightness = 0.3  # Fixed wall fill brightness
    let fillTint = color(brightness, brightness, brightness, 1.0)
    bxy.drawImage("wall.fill", fillPos.vec2 + vec2(0.5, 0.3),
                  angle = 0, scale = 1/200, tint = fillTint)

proc drawDoors*() =
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      let pos = ivec2(x, y)
      if not env.hasDoor(pos):
        continue
      let teamId = env.getDoorTeam(pos)
      let base = if teamId >= 0 and teamId < teamColors.len: teamColors[teamId] else: color(0.8, 0.8, 0.8, 1.0)
      let tint = color(base.r * 0.75 + 0.1, base.g * 0.75 + 0.1, base.b * 0.75 + 0.1, 0.9)
      bxy.drawImage(doorSpriteKey, pos.vec2, angle = 0, scale = 1/200, tint = tint)

proc drawObjects*() =
  drawAttackOverlays()

  let drawWaterTile = proc(pos: Vec2) =
    bxy.drawImage("water", pos, angle = 0, scale = 1/200)

  # Draw water from terrain so agents can occupy those tiles while keeping visuals.
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      if env.terrain[x][y] == Water:
        drawWaterTile(ivec2(x, y).vec2)

  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      if env.grid[x][y] != nil:
        let thing = env.grid[x][y]
        let pos = ivec2(x, y)
        let infectionLevel = getInfectionLevel(pos)
        let infected = infectionLevel >= 1.0

        case thing.kind
        of Wall:
          discard
        of TreeObject:
          let treeSprite = if thing.treeVariant == TreeVariantPalm:
            "palm"
          else:
            "pine"
          bxy.drawImage(treeSprite, pos.vec2, angle = 0, scale = 1/200)
          if infected:
            drawOverlayIf(true, "frozen", pos.vec2)
        of Agent:
          let agent = thing
          var agentImage = case agent.orientation:
            of N: "agent.n"
            of S: "agent.s"
            of E: "agent.e"
            of W: "agent.w"
            of NW: "agent.w"  # Use west sprite for NW
            of NE: "agent.e"  # Use east sprite for NE
            of SW: "agent.w"  # Use west sprite for SW
            of SE: "agent.e"  # Use east sprite for SE

          # Draw agent sprite with normal coloring (no infection overlay for agents)
          bxy.drawImage(
            agentImage,
            pos.vec2,
            angle = 0,
            scale = 1/200,
            tint = generateEntityColor("agent", agent.agentId)
          )

        of Altar:
          let baseImage = "altar"  # Visual centerpiece for each village
          let altarTint = getAltarColor(pos)
          # Subtle ground tint so altars start with their team shade visible.
          bxy.drawImage(
            "floor",
            pos.vec2,
            angle = 0,
            scale = 1/200,
            tint = color(altarTint.r, altarTint.g, altarTint.b, 0.35)
          )
          bxy.drawImage(
            baseImage,
            pos.vec2,
            angle = 0,
            scale = 1/200,
            tint = color(altarTint.r, altarTint.g, altarTint.b, 1.0)
          )

          # Hearts row uses the same small icons/spacing as agent inventory overlays.
          let heartAnchor = vec2(-0.48, -0.64)
          let heartStep = 0.12
          let heartScale: float32 = 1/80
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
              # Compact: single heart with a count label for large totals
              bxy.drawImage("heart", thing.pos.vec2 + heartAnchor, angle = 0, scale = heartScale, tint = altarTint)
              let labelKey = ensureHeartCountLabel(amt)
              # Offset roughly half a tile to the right for clearer separation from the icon.
              let labelPos = thing.pos.vec2 + heartAnchor + vec2(0.5, -0.015)
              bxy.drawImage(labelKey, labelPos, angle = 0, scale = heartScale, tint = altarTint)
          if infected:
            drawOverlayIf(true, "frozen", pos.vec2)

        of Mine:
          let imageName = thingSpriteKey(Mine)
          let mineTint = if thing.mineKind == MineStone:
            color(0.78, 0.78, 0.85, 1.0)
          else:
            color(1.10, 0.92, 0.55, 1.0)
          bxy.drawImage(imageName, pos.vec2, angle = 0, scale = 1/200, tint = mineTint)
          if infected and hasFrozenOverlay(Mine):
            drawOverlayIf(true, "frozen", pos.vec2)

        of Tumor:
          # Map diagonal orientations to cardinal sprites
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
          # Tumors draw directly with tint variations baked into the sprite
          bxy.drawImage(baseImage, pos.vec2, angle = 0, scale = 1/200)

        of Cow:
          let cowSprite = if thing.orientation == Orientation.E: "cow_r" else: "cow"
          bxy.drawImage(cowSprite, pos.vec2, angle = 0, scale = 1/200)
        of PlantedLantern:
          # Draw lantern using a simple image with team color tint
          let lantern = thing
          if lantern.lanternHealthy and lantern.teamId >= 0 and lantern.teamId < teamColors.len:
            let teamColor = teamColors[lantern.teamId]
            bxy.drawImage("lantern", pos.vec2, angle = 0, scale = 1/200, tint = teamColor)
          else:
            # Unhealthy or unassigned lantern - draw as gray
            bxy.drawImage("lantern", pos.vec2, angle = 0, scale = 1/200, tint = color(0.5, 0.5, 0.5, 1.0))
        else:
          let spriteKey = thingSpriteKey(thing.kind)
          if spriteKey.len > 0:
            let imageName = spriteKey
            bxy.drawImage(imageName, pos.vec2, angle = 0, scale = 1/200)
            drawRoofTint(imageName, pos.vec2, thing.teamId)
          if infected and hasFrozenOverlay(thing.kind):
            drawOverlayIf(true, "frozen", pos.vec2)

proc drawVisualRanges*(alpha = 0.2) =
  var visibility: array[MapWidth, array[MapHeight, bool]]
  for agent in env.agents:
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
    # Frozen overlay
    if agent.frozen > 0:
      bxy.drawImage("frozen", agent.pos.vec2, angle = 0, scale = 1/200)

    # Health bar (5 segments)
    if agent.maxHp > 0:
      let segments = 5
      let ratio = clamp(agent.hp.float32 / agent.maxHp.float32, 0.0, 1.0)
      let filled = int(ceil(ratio * segments.float32))
      let baseOffset = vec2(-0.40, -0.55)
      let segStep = 0.16
      for i in 0 ..< segments:
        let tint = if i < filled: color(0.1, 0.8, 0.1, 1.0) else: color(0.3, 0.3, 0.3, 0.7)
        bxy.drawImage("floor", agent.pos.vec2 + vec2(baseOffset.x + segStep * i.float32, baseOffset.y), angle = 0, scale = 1/500, tint = tint)

    # Inventory overlays placed radially, ordered by item name.
    type OverlayItem = object
      name: string
      icon: string
      count: int

    proc iconForItem(key: ItemKey): string =
      case key
      of ItemOre: "ore"
      of ItemStone: "blocks"
      of ItemWater: "droplet"
      of ItemWheat: "bushel"
      of ItemWood: "wood"
      of ItemSpear: "spear"
      of ItemLantern: "lantern"
      of ItemArmor: "armor"
      of ItemBread: "bread"
      of ItemMilk: "liquid_misc"
      of ItemHearts: "heart"
      else:
        if key.startsWith(ItemThingPrefix):
          let kindName = key[ItemThingPrefix.len .. ^1]
          return toSnakeCase(kindName)
        return key

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
        scale = 1/200
      )

proc drawSelection*() =
  if selection != nil:
    bxy.drawImage(
      "selection",
      selection.pos.vec2,
      angle = 0,
      scale = 1/200
    )

proc drawSelectionLabel*(panelRect: IRect) =
  if selectedPos.x < 0 or selectedPos.x >= MapWidth or
     selectedPos.y < 0 or selectedPos.y >= MapHeight:
    return

  var label = ""
  let thing = env.grid[selectedPos.x][selectedPos.y]
  if thing != nil:
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
      elif thing.kind == Mine:
        if thing.mineKind == MineStone: "Stone Mine" else: "Gold Mine"
      else:
        case thing.kind
        of Wall: "Wall"
        of TreeObject: "Tree"
        of Converter: "Magma Pool"
        of Altar: "Altar"
        of Spawner: "Spawner"
        of Tumor: "Tumor"
        of Cow: "Cow"
        of Skeleton: "Skeleton"
        of Armory: "Armory"
        of Forge: "Forge"
        of ClayOven: "Clay Oven"
        of WeavingLoom: "Weaving Loom"
        of Bed: "Bed"
        of Chair: "Chair"
        of Table: "Table"
        of Statue: "Statue"
        of Outpost: "Outpost"
        of Barrel: "Barrel"
        of Mill: "Mill"
        of LumberCamp: "Lumber Camp"
        of MiningCamp: "Mining Camp"
        of Farm: "Farm"
        of Stump: "Stump"
        of PlantedLantern: "Lantern"
        of TownCenter: "Town Center"
        of House: "House"
        of Barracks: "Barracks"
        of ArcheryRange: "Archery Range"
        of Stable: "Stable"
        of SiegeWorkshop: "Siege Workshop"
        of Blacksmith: "Blacksmith"
        of Market: "Market"
        of Dock: "Dock"
        of Monastery: "Monastery"
        of University: "University"
        of Castle: "Castle"
        of Agent:
          case thing.unitClass
          of UnitVillager: "Villager"
          of UnitManAtArms: "Man-at-Arms"
          of UnitArcher: "Archer"
          of UnitScout: "Scout"
          of UnitKnight: "Knight"
          of UnitMonk: "Monk"
          of UnitSiege: "Siege"
        of Mine:
          if thing.mineKind == MineStone: "Stone Mine" else: "Gold Mine"
  elif env.hasDoor(selectedPos):
    label = "Door"
  else:
    label = case env.terrain[selectedPos.x][selectedPos.y]
      of Empty: "Empty"
      of Water: "Water"
      of Bridge: "Bridge"
      of Wheat: "Wheat"
      of Tree: "Tree"
      of Fertile: "Fertile"
      of Road: "Road"
      of Rock: "Rock"
      of Gem: "Gem"
      of Bush: "Bush"
      of Animal: "Animal"
      of Grass: "Grass"
      of Cactus: "Cactus"
      of Dune: "Dune"
      of Stalagmite: "Stalagmite"
      of Palm: "Palm"
      of Sand: "Sand"
      of Snow: "Snow"

  let key = ensureInfoLabel(label)
  if key.len == 0:
    return
  let pos = vec2(panelRect.x.float32 + 8 + InfoLabelInsetX.float32,
    panelRect.y.float32 + 8 + InfoLabelInsetY.float32)
  bxy.drawImage(key, pos, angle = 0, scale = 1)
