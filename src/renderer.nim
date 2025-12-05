import
  boxy, vmath, windy, tables,
  common, environment

# Infection system constants
const
  InfectionThreshold* = 0.05  # Blue tint threshold for infection
  PurpleOverlayStrength* = 0.6  # How strong the purple overlay is

proc getInfectionLevel*(pos: IVec2): float32 =
  ## Simple infection level based on color temperature
  return if isBuildingFrozen(pos, env): 1.0 else: 0.0

proc getInfectionSprite*(entityType: string): string =
  ## Get the appropriate infection overlay sprite for static environmental objects only
  case entityType:
  of "building", "mine", "converter", "assembler", "armory", "forge", "clay_oven", "weaving_loom":
    return "agents/frozen"  # Ice cube overlay for static buildings
  of "terrain", "wheat", "tree":
    return "agents/frozen"  # Ice cube overlay for terrain features (walls excluded)
  of "agent", "tumor", "spawner", "wall":
    return ""  # No overlays for dynamic entities and walls
  else:
    return ""  # Default: no overlay


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
        let thing = env.grid[gridPos.x][gridPos.y]
        if thing != nil:
          selection = thing

proc drawFloor*() =
  # Draw the floor tiles everywhere first as the base layer
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:

      let tileColor = env.tileColors[x][y]

      let finalR = min(tileColor.r * tileColor.intensity, 1.5)
      let finalG = min(tileColor.g * tileColor.intensity, 1.5)
      let finalB = min(tileColor.b * tileColor.intensity, 1.5)

      bxy.drawImage("objects/floor", ivec2(x, y).vec2, angle = 0, scale = 1/200, tint = color(finalR, finalG, finalB, 1.0))

proc drawTerrain*() =
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      let pos = ivec2(x, y)
      let infectionLevel = getInfectionLevel(pos)
      let infected = infectionLevel >= 1.0

      case env.terrain[x][y]
      of Wheat:
        bxy.drawImage("objects/wheat_field", pos.vec2, angle = 0, scale = 1/200)
        if infected:
          # Add infection overlay sprite to infected wheat
          let overlaySprite = getInfectionSprite("wheat")
          if overlaySprite != "":
            bxy.drawImage(overlaySprite, pos.vec2, angle = 0, scale = 1/200)
      of Tree:
        bxy.drawImage("objects/palm_tree", pos.vec2, angle = 0, scale = 1/200)
        if infected:
          # Add infection overlay sprite to infected trees
          let overlaySprite = getInfectionSprite("tree")
          if overlaySprite != "":
            bxy.drawImage(overlaySprite, pos.vec2, angle = 0, scale = 1/200)
      of Fertile:
        bxy.drawImage("objects/fertile", pos.vec2, angle = 0, scale = 1/200)
      of Empty:
        discard
      else:
        discard

proc drawAttackOverlays*() =
  for pos in env.actionTintPositions:
    if pos.x < 0 or pos.x >= MapWidth or pos.y < 0 or pos.y >= MapHeight:
      continue
    if env.actionTintCountdown[pos.x][pos.y] > 0:
      let c = env.actionTintColor[pos.x][pos.y]
      # Render the short-lived action overlay fully opaque so it sits above the
      # normal tint layer and clearly masks the underlying tile color.
      bxy.drawImage("objects/floor", pos.vec2, angle = 0, scale = 1/200, tint = color(c.r, c.g, c.b, 1.0))

proc drawStackedOverlay*(basePos: Vec2, anchor: Vec2, icon: string, count: int, tint: Color,
                         iconScale: float32 = 1/320, maxStack: int = 5, stackStep: float32 = 0.09,
                         fadedWhenZero = false) =
  ## Small helper to render a stacked icon overlay (matches agent resource style).
  let amt = max(0, count)
  if amt == 0:
    if fadedWhenZero:
      let fadedTint = color(tint.r, tint.g, tint.b, 0.35)
      bxy.drawImage(icon, basePos + anchor, angle = 0, scale = iconScale, tint = fadedTint)
    return

  let drawCount = min(amt, maxStack)
  for i in 0 ..< drawCount:
    let pos = basePos + anchor + vec2(0.0, -i.float32 * stackStep)
    bxy.drawImage(icon, pos, angle = 0, scale = iconScale, tint = tint)

  if amt > drawCount:
    let plusPos = basePos + anchor + vec2(0.14, - (drawCount - 1).float32 * stackStep)
    let boxSize = 0.26
    bxy.drawRect(
      rect(plusPos.x - boxSize / 2, plusPos.y - boxSize / 2, boxSize, boxSize),
      color(0, 0, 0, 0.65)
    )
    let barThickness = 0.055
    let barLength = 0.15
    bxy.drawRect(
      rect(plusPos.x - barLength / 2, plusPos.y - barThickness / 2, barLength, barThickness),
      tint
    )
    bxy.drawRect(
      rect(plusPos.x - barThickness / 2, plusPos.y - barLength / 2, barThickness, barLength),
      tint
    )

proc generateWallSprites(): seq[string] =
  result = newSeq[string](16)
  for i in 0 .. 15:
    var suffix = ""
    if (i and 8) != 0: suffix.add("n")
    if (i and 4) != 0: suffix.add("w")
    if (i and 2) != 0: suffix.add("s")
    if (i and 1) != 0: suffix.add("e")

    if suffix.len > 0:
      result[i] = "objects/wall." & suffix
    else:
      result[i] = "objects/wall"

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
    bxy.drawImage("objects/wall.fill", fillPos.vec2 + vec2(0.5, 0.3),
                  angle = 0, scale = 1/200, tint = fillTint)

proc drawObjects*() =
  drawAttackOverlays()
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
        of WaterTile:
          bxy.drawImage("objects/water", pos.vec2, angle = 0, scale = 1/200)
        of Agent:
          let agent = thing
          var agentImage = case agent.orientation:
            of N: "agents/agent.n"
            of S: "agents/agent.s"
            of E: "agents/agent.e"
            of W: "agents/agent.w"
            of NW: "agents/agent.w"  # Use west sprite for NW
            of NE: "agents/agent.e"  # Use east sprite for NE
            of SW: "agents/agent.w"  # Use west sprite for SW
            of SE: "agents/agent.e"  # Use east sprite for SE

          # Draw agent sprite with normal coloring (no infection overlay for agents)
          bxy.drawImage(
            agentImage,
            pos.vec2,
            angle = 0,
            scale = 1/200,
            tint = generateEntityColor("agent", agent.agentId)
          )

        of assembler:
          let baseImage = "objects/altar"  # Visual centerpiece for each village
          let assemblerTint = getassemblerColor(pos)
          # Subtle ground tint so altars start with their team shade visible.
          bxy.drawImage(
            "objects/floor",
            pos.vec2,
            angle = 0,
            scale = 1/200,
            tint = color(assemblerTint.r, assemblerTint.g, assemblerTint.b, 0.35)
          )
          bxy.drawImage(
            baseImage,
            pos.vec2,
            angle = 0,
            scale = 1/200,
            tint = color(assemblerTint.r, assemblerTint.g, assemblerTint.b, 1.0)
          )
          # Always show current heart count above the altar using stacked overlay style.
          drawStackedOverlay(
            basePos = thing.pos.vec2,
            anchor = vec2(0.0, -0.60),
            icon = "ui/heart",
            count = thing.hearts,
            tint = assemblerTint,
            iconScale = 1/320,
            maxStack = 5,
            stackStep = 0.09,
            fadedWhenZero = true
          )
          if infected:
            # Add infection overlay sprite
            let overlaySprite = getInfectionSprite("assembler")
            if overlaySprite != "":
              bxy.drawImage(overlaySprite, pos.vec2, angle = 0, scale = 1/200)

        of Converter:
          let baseImage = "objects/converter"
          bxy.drawImage(baseImage, pos.vec2, angle = 0, scale = 1/200)
          if infected:
            # Add infection overlay sprite
            let overlaySprite = getInfectionSprite("converter")
            if overlaySprite != "":
              bxy.drawImage(overlaySprite, pos.vec2, angle = 0, scale = 1/200)

        of Mine, Spawner:
          let imageName = if thing.kind == Mine: "objects/mine" else: "objects/spawner"
          bxy.drawImage(imageName, pos.vec2, angle = 0, scale = 1/200)
          if infected and thing.kind == Mine:
            # Only mines get infection overlays, not spawners
            let overlaySprite = getInfectionSprite("mine")
            if overlaySprite != "":
              bxy.drawImage(overlaySprite, pos.vec2, angle = 0, scale = 1/200)

        of Tumor:
          # Map diagonal orientations to cardinal sprites
          let spriteDir = case thing.orientation:
            of N: "n"
            of S: "s"
            of E, NE, SE: "e"
            of W, NW, SW: "w"
          let spritePrefix = if thing.hasClaimedTerritory:
            "agents/tumor."
          else:
            "agents/tumor.color."
          let baseImage = spritePrefix & spriteDir
          # Tumors draw directly with tint variations baked into the sprite
          bxy.drawImage(baseImage, pos.vec2, angle = 0, scale = 1/200)

        of Armory, Forge, ClayOven, WeavingLoom:
          let imageName = case thing.kind:
            of Armory: "objects/armory"
            of Forge: "objects/forge"
            of ClayOven: "objects/clay_oven"
            of WeavingLoom: "objects/weaving_loom"
            else: ""

          bxy.drawImage(imageName, pos.vec2, angle = 0, scale = 1/200)
          if infected:
            # Add infection overlay sprite
            let overlayType = case thing.kind:
              of Armory: "armory"
              of Forge: "forge"
              of ClayOven: "clay_oven"
              of WeavingLoom: "weaving_loom"
              else: "building"
            let overlaySprite = getInfectionSprite(overlayType)
            if overlaySprite != "":
              bxy.drawImage(overlaySprite, pos.vec2, angle = 0, scale = 1/200)

        of PlantedLantern:
          # Draw lantern using a simple image with team color tint
          let lantern = thing
          if lantern.lanternHealthy and lantern.teamId >= 0 and lantern.teamId < teamColors.len:
            let teamColor = teamColors[lantern.teamId]
            bxy.drawImage("objects/lantern", pos.vec2, angle = 0, scale = 1/200, tint = teamColor)
          else:
            # Unhealthy or unassigned lantern - draw as gray
            bxy.drawImage("objects/lantern", pos.vec2, angle = 0, scale = 1/200, tint = color(0.5, 0.5, 0.5, 1.0))

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
      bxy.drawImage("agents/frozen", agent.pos.vec2, angle = 0, scale = 1/200)

    # Health bar (5 segments)
    if agent.maxHp > 0:
      let segments = 5
      let ratio = clamp(agent.hp.float32 / agent.maxHp.float32, 0.0, 1.0)
      let filled = int(ceil(ratio * segments.float32))
      let baseOffset = vec2(-0.40, -0.55)
      let segStep = 0.16
      for i in 0 ..< segments:
        let tint = if i < filled: color(0.1, 0.8, 0.1, 1.0) else: color(0.3, 0.3, 0.3, 0.7)
        bxy.drawImage("objects/floor", agent.pos.vec2 + vec2(baseOffset.x + segStep * i.float32, baseOffset.y), angle = 0, scale = 1/500, tint = tint)

    # Inventory overlays placed per-corner/edge for clarity
    type OverlayItem = tuple[key: string, icon: string, count: int]
    var overlays: seq[OverlayItem] = @[]
    if agent.inventoryOre > 0: overlays.add((key: "nw", icon: "resources/ore", count: agent.inventoryOre))
    if agent.inventoryBattery > 0: overlays.add((key: "n", icon: "resources/battery", count: agent.inventoryBattery))
    if agent.inventoryWater > 0: overlays.add((key: "ne", icon: "resources/water", count: agent.inventoryWater))
    if agent.inventoryWheat > 0: overlays.add((key: "sw", icon: "resources/wheat", count: agent.inventoryWheat))
    if agent.inventoryBread > 0: overlays.add((key: "s", icon: "resources/bread", count: agent.inventoryBread))
    if agent.inventoryArmor > 0: overlays.add((key: "se", icon: "resources/armor", count: agent.inventoryArmor))
    if agent.inventoryLantern > 0: overlays.add((key: "w", icon: "objects/lantern", count: agent.inventoryLantern))
    if agent.inventoryWood > 0: overlays.add((key: "e", icon: "resources/wood", count: agent.inventoryWood))
    if agent.inventorySpear > 0: overlays.add((key: "c", icon: "resources/spear", count: agent.inventorySpear))

    if overlays.len == 0:
      continue

    let basePos = agent.pos.vec2
    let iconScale = 1/320
    let maxStack = 4
    let stackStep = 0.08

    # Anchor offsets per key (keep corners near tile corners, bottom row pushed lower)
    let anchor = toTable({
      "nw": vec2(-0.40, -0.48),
      "n":  vec2(0.00, -0.52),
      "ne": vec2(0.40, -0.48),
      "w":  vec2(-0.48, -0.06),
      "c":  vec2(0.00, -0.06),
      "e":  vec2(0.48, -0.06),
      "sw": vec2(-0.40, 0.52),
      "s":  vec2(0.00, 0.56),
      "se": vec2(0.40, 0.52)
    })

    var stackCounts = initTable[string, int]()

    for ov in overlays:
      let off = anchor.getOrDefault(ov.key, vec2(0.0, -0.42))
      var stackIdx = stackCounts.getOrDefault(ov.key, 0)
      let n = min(ov.count, maxStack)
      for i in 0 ..< n:
        let pos = basePos + off + vec2(0.0, -stackIdx.float32 * stackStep)
        bxy.drawImage(ov.icon, pos, angle = 0, scale = iconScale)
        stackIdx += 1
      stackCounts[ov.key] = stackIdx

proc drawGrid*() =
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      bxy.drawImage(
        "view/grid",
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
