# This file is included by src/environment.nim
import std/math
proc createTumor(pos: IVec2, homeSpawner: IVec2, r: var Rand): Thing =
  ## Create a new Tumor seed that can branch once before turning inert
  Thing(
    kind: Tumor,
    pos: pos,
    orientation: Orientation(randIntInclusive(r, 0, 3)),
    homeSpawner: homeSpawner,
    hasClaimedTerritory: false,  # Start mobile, will plant when far enough from others
    turnsAlive: 0                # New tumor hasn't lived any turns yet
  )

const
  ResourceGround = {TerrainEmpty, TerrainGrass, TerrainSand, TerrainSnow, TerrainDune}
  TreeGround = {TerrainEmpty, TerrainGrass, TerrainSand, TerrainDune}

proc addResourceNode(env: Environment, pos: IVec2, kind: ThingKind,
                     item: ItemKey, amount: int = ResourceNodeInitial) =
  if not env.isEmpty(pos) or not isNil(env.getOverlayThing(pos)) or env.hasDoor(pos):
    return
  let node = Thing(kind: kind, pos: pos)
  node.inventory = emptyInventory()
  if item != ItemNone and amount > 0:
    setInv(node, item, amount)
  env.add(node)

proc placeResourceCluster(env: Environment, centerX, centerY: int, size: int,
                          baseDensity: float, falloffRate: float, kind: ThingKind,
                          item: ItemKey, allowedTerrain: set[TerrainType], r: var Rand,
                          allowedBiomes: set[BiomeType] = {}) =
  let radius = max(1, (size.float / 2.0).int)
  for dx in -radius .. radius:
    for dy in -radius .. radius:
      let x = centerX + dx
      let y = centerY + dy
      if x < 0 or x >= MapWidth or y < 0 or y >= MapHeight:
        continue
      if env.terrain[x][y] notin allowedTerrain:
        continue
      if allowedBiomes.card > 0 and env.biomes[x][y] notin allowedBiomes:
        continue
      let dist = sqrt((dx * dx + dy * dy).float)
      if dist > radius.float:
        continue
      let chance = baseDensity - (dist / radius.float) * falloffRate
      if randChance(r, chance):
        addResourceNode(env, ivec2(x.int32, y.int32), kind, item)

proc init(env: Environment) =
  inc env.mapGeneration
  # Use current time for random seed to get different maps each time
  let seed = int(nowSeconds() * 1000)
  var r = initRand(seed)

  env.thingsByKind = default(array[ThingKind, seq[Thing]])

  # Initialize tile colors to base terrain colors (neutral gray-brown)
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      env.baseTintColors[x][y] = BaseTileColorDefault
      env.computedTintColors[x][y] = TileColor(r: 0, g: 0, b: 0, intensity: 0)

  # Clear overlay grid (non-blocking things like doors)
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      env.overlayGrid[x][y] = nil
      env.elevation[x][y] = 0

  # Reset team stockpiles
  env.teamStockpiles = default(array[MapRoomObjectsHouses, TeamStockpile])

  # Initialize active tiles tracking
  env.activeTiles.positions.setLen(0)
  env.activeTiles.flags = default(array[MapWidth, array[MapHeight, bool]])
  env.tumorActiveTiles.positions.setLen(0)
  env.tumorActiveTiles.flags = default(array[MapWidth, array[MapHeight, bool]])
  env.tumorTintMods = default(array[MapWidth, array[MapHeight, TintModification]])
  env.tintStrength = default(array[MapWidth, array[MapHeight, int32]])
  env.tumorStrength = default(array[MapWidth, array[MapHeight, int32]])

  # Clear action tints
  env.actionTintCountdown = default(ActionTintCountdown)
  env.actionTintColor = default(ActionTintColor)
  env.actionTintFlags = default(ActionTintFlags)
  env.actionTintPositions.setLen(0)
  env.shieldCountdown = default(array[MapAgents, int8])

  # Initialize terrain with all features
  initTerrain(env.terrain, env.biomes, MapWidth, MapHeight, MapBorder, seed)
  env.applyBiomeBaseColors()

  # Resource nodes are spawned as Things later; base terrain stays walkable.

  # Convert city blocks into walls (roads remain passable).
  for x in MapBorder ..< MapWidth - MapBorder:
    for y in MapBorder ..< MapHeight - MapBorder:
      if env.biomes[x][y] != BiomeCityType:
        continue
      if env.terrain[x][y] != BiomeCityBlockTerrain:
        continue
      let pos = ivec2(x.int32, y.int32)
      if env.hasDoor(pos):
        continue
      let existing = env.getThing(pos)
      if not isNil(existing):
        if existing.kind in {Tree}:
          removeThing(env, existing)
        else:
          continue
      env.terrain[x][y] = Empty
      env.add(Thing(kind: Wall, pos: pos))

  # Add sparse dungeon walls using procedural dungeon masks.
  if UseDungeonZones:
    let dungeonKinds = [DungeonMaze, DungeonRadial]
    var count = zoneCount(MapWidth * MapHeight, DungeonZoneDivisor, DungeonZoneMinCount, DungeonZoneMaxCount)
    if UseSequentialDungeonZones:
      count = max(count, dungeonKinds.len)
    var dungeonWalls: MaskGrid
    dungeonWalls.clearMask(MapWidth, MapHeight)
    var seqIdx = randIntInclusive(r, 0, dungeonKinds.len - 1)
    for zone in evenlyDistributedZones(r, MapWidth, MapHeight, MapBorder, count, DungeonZoneMaxFraction):
      let x0 = max(MapBorder, zone.x)
      let y0 = max(MapBorder, zone.y)
      let x1 = min(MapWidth - MapBorder, zone.x + zone.w)
      let y1 = min(MapHeight - MapBorder, zone.y + zone.h)

      var zoneMask: MaskGrid
      buildZoneBlobMask(zoneMask, MapWidth, MapHeight, MapBorder, zone, r)

      # Tint the dungeon zone background with a soft edge blend.
      let dungeonBlendDepth = 4
      for x in x0 ..< x1:
        for y in y0 ..< y1:
          if not zoneMask[x][y]:
            continue
          env.biomes[x][y] = BiomeDungeonType
          let edge = maskEdgeDistance(zoneMask, MapWidth, MapHeight, x, y, dungeonBlendDepth)
          let t = if dungeonBlendDepth <= 0: 1.0'f32 else:
            min(1.0'f32, max(0.0'f32, edge.float32 / dungeonBlendDepth.float32))
          let dungeonColor = biomeBaseColor(BiomeDungeonType)
          let base = env.baseTintColors[x][y]
          let tClamped = max(0.0'f32, min(1.0'f32, t))
          env.baseTintColors[x][y] = TileColor(
            r: base.r * (1.0 - tClamped) + dungeonColor.r * tClamped,
            g: base.g * (1.0 - tClamped) + dungeonColor.g * tClamped,
            b: base.b * (1.0 - tClamped) + dungeonColor.b * tClamped,
            intensity: base.intensity * (1.0 - tClamped) + dungeonColor.intensity * tClamped
          )
      var mask: MaskGrid
      let dungeonKind = if UseSequentialDungeonZones:
        inc seqIdx
        dungeonKinds[(seqIdx - 1) mod dungeonKinds.len]
      else:
        if randFloat(r) * 1.6 <= 1.0:
          DungeonMaze
        else:
          DungeonRadial
      case dungeonKind:
      of DungeonMaze:
        buildDungeonMazeMask(mask, MapWidth, MapHeight, zone.x, zone.y, zone.w, zone.h, r, DungeonMazeConfig())
      of DungeonRadial:
        buildDungeonRadialMask(mask, MapWidth, MapHeight, zone.x, zone.y, zone.w, zone.h, r, DungeonRadialConfig())

      for x in x0 ..< x1:
        for y in y0 ..< y1:
          if not zoneMask[x][y]:
            continue
          if (if dungeonKind == DungeonRadial:
                not mask[x][y]  # radial mask encodes corridors; invert for walls
              else:
                mask[x][y]) and not isBlockedTerrain(env.terrain[x][y]):
            dungeonWalls[x][y] = true

    # Soften dungeon edges so they blend into surrounding biomes.
    ditherEdges(dungeonWalls, MapWidth, MapHeight, 0.08, 3, r)

    for x in MapBorder ..< MapWidth - MapBorder:
      for y in MapBorder ..< MapHeight - MapBorder:
        if not dungeonWalls[x][y]:
          continue
        if env.terrain[x][y] == Water:
          continue
        let pos = ivec2(x.int32, y.int32)
        if env.hasDoor(pos):
          continue
        let existing = env.getThing(pos)
        if not isNil(existing):
          if existing.kind in {Tree}:
            removeThing(env, existing)
          else:
            continue
        env.add(Thing(kind: Wall, pos: pos))

  if MapBorder > 0:
    for x in 0 ..< MapWidth:
      for j in 0 ..< MapBorder:
        env.add(Thing(kind: Wall, pos: ivec2(x, j)))
        env.add(Thing(kind: Wall, pos: ivec2(x, MapHeight - j - 1)))
    for y in 0 ..< MapHeight:
      for j in 0 ..< MapBorder:
        env.add(Thing(kind: Wall, pos: ivec2(j, y)))
        env.add(Thing(kind: Wall, pos: ivec2(MapWidth - j - 1, y)))

  # Agents will now spawn with their villages below
  # Clear and prepare village colors arrays (use Environment fields)
  env.agentColors.setLen(MapRoomObjectsAgents)  # Allocate space for all agents
  env.teamColors.setLen(0)  # Clear team colors
  env.altarColors.clear()  # Clear altar colors from previous game
  # Spawn villages with altars, town centers, and associated agents (tribes)
  let numVillages = MapRoomObjectsHouses
  var totalAgentsSpawned = 0
  var villageCenters: seq[IVec2] = @[]
  proc placeStartingTownCenter(center: IVec2, teamId: int, r: var Rand): IVec2 =
    var candidates: seq[IVec2] = @[]
    for dx in -3 .. 3:
      for dy in -3 .. 3:
        if dx == 0 and dy == 0:
          continue
        let dist = max(abs(dx), abs(dy))
        if dist < 1 or dist > 3:
          continue
        let pos = center + ivec2(dx.int32, dy.int32)
        if pos == center + ivec2(2, -2) or pos == center + ivec2(2, 2) or
            pos == center + ivec2(-2, 2) or pos == center + ivec2(-2, -2):
          continue
        candidates.add(pos)
    for i in countdown(candidates.len - 1, 1):
      let j = randIntInclusive(r, 0, i)
      swap(candidates[i], candidates[j])
    for pos in candidates:
      if not isValidPos(pos):
        continue
      if env.terrain[pos.x][pos.y] == Water:
        continue
      let existing = env.getThing(pos)
      if not isNil(existing):
        if existing.kind in {Tree}:
          removeThing(env, existing)
        else:
          continue
      if env.hasDoor(pos):
        continue
      if not env.isEmpty(pos):
        continue
      env.add(Thing(kind: TownCenter, pos: pos, teamId: teamId))
      return pos
    # Fallback: place directly east if possible.
    let fallback = center + ivec2(1, 0)
    if isValidPos(fallback) and env.isEmpty(fallback) and env.terrain[fallback.x][fallback.y] != Water and not env.hasDoor(fallback):
      env.add(Thing(kind: TownCenter, pos: fallback, teamId: teamId))
      return fallback
    center
  proc placeStartingRoads(center: IVec2, teamId: int, r: var Rand) =
    proc signi(x: int32): int32 =
      if x < 0: -1
      elif x > 0: 1
      else: 0

    proc placeRoad(pos: IVec2) =
      if not isValidPos(pos):
        return
      if env.terrain[pos.x][pos.y] == Water:
        return
      if env.hasDoor(pos):
        return
      let existing = env.getThing(pos)
      if not isNil(existing):
        if existing.kind in {Tree}:
          removeThing(env, existing)
        else:
          return
      if env.terrain[pos.x][pos.y] != Road:
        env.terrain[pos.x][pos.y] = Road
        env.resetTileColor(pos)

    var anchors: seq[IVec2] = @[center]
    for thing in env.things:
      if thing.teamId != teamId:
        continue
      if thing.kind notin {TownCenter, House, Granary, LumberCamp, Quarry, MiningCamp, Mill}:
        continue
      let dist = max(abs(thing.pos.x - center.x), abs(thing.pos.y - center.y))
      if dist <= 7:
        anchors.add(thing.pos)

    for anchor in anchors:
      if anchor == center:
        continue
      var pos = center
      while pos.x != anchor.x:
        pos.x += signi(anchor.x - pos.x)
        placeRoad(pos)
      while pos.y != anchor.y:
        pos.y += signi(anchor.y - pos.y)
        placeRoad(pos)

    var maxEast = 0
    var maxWest = 0
    var maxSouth = 0
    var maxNorth = 0
    for anchor in anchors:
      let dx = (anchor.x - center.x).int
      let dy = (anchor.y - center.y).int
      if dx > maxEast: maxEast = dx
      if dx < 0 and -dx > maxWest: maxWest = -dx
      if dy > maxSouth: maxSouth = dy
      if dy < 0 and -dy > maxNorth: maxNorth = -dy

    for (dir, baseDist) in [(ivec2(1, 0), maxEast), (ivec2(-1, 0), maxWest),
                            (ivec2(0, 1), maxSouth), (ivec2(0, -1), maxNorth)]:
      let extra = randIntInclusive(r, 3, 4)
      for step in 1 .. baseDist + extra:
        let pos = center + ivec2(dir.x.int32 * step.int32, dir.y.int32 * step.int32)
        placeRoad(pos)

  proc placeStartingResourceBuildings(center: IVec2, teamId: int) =
    for entry in [
      (offset: ivec2(2, -2), kind: LumberCamp, res: ResourceWood),   # Lumber Camp
      (offset: ivec2(2, 2), kind: Granary, res: ResourceFood),       # Granary
      (offset: ivec2(-2, 2), kind: Quarry, res: ResourceStone),      # Quarry
      (offset: ivec2(-2, -2), kind: MiningCamp, res: ResourceGold)   # Mining Camp
    ]:
      var placed = false
      for radius in 0 .. 2:
        for dx in -radius .. radius:
          for dy in -radius .. radius:
            if radius > 0 and max(abs(dx), abs(dy)) != radius:
              continue
            let pos = center + entry.offset + ivec2(dx.int32, dy.int32)
            if not isValidPos(pos):
              continue
            if env.terrain[pos.x][pos.y] == Water or isTileFrozen(pos, env):
              continue
            if env.hasDoor(pos):
              continue
            let existing = env.getThing(pos)
            if not isNil(existing):
              if existing.kind in {Tree}:
                removeThing(env, existing)
              else:
                continue
            if not env.isEmpty(pos):
              continue
            let building = Thing(
              kind: entry.kind,
              pos: pos,
              teamId: teamId
            )
            let capacity = buildingBarrelCapacity(entry.kind)
            if capacity > 0:
              building.barrelCapacity = capacity
            env.add(building)
            env.teamStockpiles[teamId].counts[entry.res] =
              max(env.teamStockpiles[teamId].counts[entry.res], 5)
            placed = true
            break
          if placed: break
        if placed: break

  proc placeStartingHouses(center: IVec2, teamId: int, r: var Rand) =
    let count = randIntInclusive(r, 4, 5)
    var placed = 0
    var attempts = 0
    while placed < count and attempts < 120:
      inc attempts
      let dx = randIntInclusive(r, -5, 5)
      let dy = randIntInclusive(r, -5, 5)
      let dist = max(abs(dx), abs(dy))
      if dist < 3 or dist > 5:
        continue
      let pos = center + ivec2(dx.int32, dy.int32)
      if not isValidPos(pos):
        continue
      if env.hasDoor(pos) or not env.isEmpty(pos):
        continue
      if env.terrain[pos.x][pos.y] == Water or isTileFrozen(pos, env):
        continue
      env.add(Thing(
        kind: House,
        pos: pos,
        teamId: teamId
      ))
      inc placed
  doAssert WarmVillagePalette.len >= numVillages,
    "WarmVillagePalette must cover all base colors without reuse."
  for i in 0 ..< numVillages:
    let villageStruct = block:
      ## Small town starter: altar + town center, no walls.
      const size = 7
      const radius = 3
      let center = ivec2(radius, radius)
      var layout: seq[seq[char]] = newSeq[seq[char]](size)
      for y in 0 ..< size:
        layout[y] = newSeq[char](size)
        for x in 0 ..< size:
          layout[y][x] = ' '

      # Clear a small plaza around the altar so the start isn't cluttered.
      for y in 0 ..< size:
        for x in 0 ..< size:
          if abs(x - center.x) + abs(y - center.y) <= 2:
            layout[y][x] = StructureFloorChar

      Structure(
        width: size,
        height: size,
        centerPos: center,
        layout: layout
      )
    var placed = false
    var placementPosition: IVec2

    # Simple random placement with collision avoidance
    for attempt in 0 ..< 200:
      let candidatePos = r.randomEmptyPos(env)
      # Check if position has enough space for the village footprint
      var canPlace = true
      for dy in 0 ..< villageStruct.height:
        for dx in 0 ..< villageStruct.width:
          let checkX = candidatePos.x + dx
          let checkY = candidatePos.y + dy
          if checkX >= MapWidth or checkY >= MapHeight or
             not env.isEmpty(ivec2(checkX, checkY)) or
             isBlockedTerrain(env.terrain[checkX][checkY]):
            canPlace = false
            break
        if not canPlace: break

      # Keep villages spaced apart (Chebyshev) to avoid crowding
      if canPlace:
        const MinVillageSpacing = DefaultMinVillageSpacing  # from balance.nim
        let candidateCenter = candidatePos + villageStruct.centerPos
        for c in villageCenters:
          let dx = abs(c.x - candidateCenter.x)
          let dy = abs(c.y - candidateCenter.y)
          if max(dx, dy) < MinVillageSpacing:
            canPlace = false
            break

      if canPlace:
        placementPosition = candidatePos
        placed = true
        break

    if placed:
      let elements = getStructureElements(villageStruct, placementPosition)

      # Clear terrain within the village area to create a clearing
      for dy in 0 ..< villageStruct.height:
        for dx in 0 ..< villageStruct.width:
          let clearX = placementPosition.x + dx
          let clearY = placementPosition.y + dy
          if clearX >= 0 and clearX < MapWidth and clearY >= 0 and clearY < MapHeight:
            if dy < villageStruct.layout.len and dx < villageStruct.layout[dy].len:
              if villageStruct.layout[dy][dx] == ' ':
                continue
            # Clear any terrain features (wheat, trees) but keep blocked terrain
            if not isBlockedTerrain(env.terrain[clearX][clearY]):
              env.terrain[clearX][clearY] = Empty
              env.resetTileColor(ivec2(clearX.int32, clearY.int32))

      # Generate a distinct warm color for this village (avoid cool/blue hues)
      let villageColor = WarmVillagePalette[i]
      env.teamColors.add(villageColor)
      let teamId = env.teamColors.len - 1

      # Spawn agent slots for this village (six active, the rest dormant)
      let agentsForThisVillage = min(MapAgentsPerVillage, MapRoomObjectsAgents - totalAgentsSpawned)

      # Add the altar with initial hearts and village bounds
      let altar = Thing(
        kind: Altar,
        pos: elements.center,
        teamId: teamId
      )
      altar.inventory = emptyInventory()
      altar.hearts = MapObjectAltarInitialHearts
      env.add(altar)
      villageCenters.add(elements.center)
      env.altarColors[elements.center] = villageColor  # Associate altar position with village color

      discard placeStartingTownCenter(elements.center, teamId, r)

      # Initialize base colors for village tiles to team color
      for dx in 0 ..< villageStruct.width:
        for dy in 0 ..< villageStruct.height:
          let tileX = placementPosition.x + dx
          let tileY = placementPosition.y + dy
          if tileX >= 0 and tileX < MapWidth and tileY >= 0 and tileY < MapHeight:
            if dy < villageStruct.layout.len and dx < villageStruct.layout[dy].len:
              if villageStruct.layout[dy][dx] == ' ':
                continue
            env.baseTintColors[tileX][tileY] = TileColor(
              r: villageColor.r,
              g: villageColor.g,
              b: villageColor.b,
              intensity: 1.0
            )

      # Add nearby village resources first, then connect roads between them.
      placeStartingResourceBuildings(elements.center, teamId)
      placeStartingHouses(elements.center, teamId, r)
      placeStartingRoads(elements.center, teamId, r)

      # Add the walls
      for wallPos in elements.walls:
        env.add(Thing(
          kind: Wall,
          pos: wallPos,
        ))

      # Add the doors (team-colored, passable only to that team)
      for doorPos in elements.doors:
        if doorPos.x >= 0 and doorPos.x < MapWidth and doorPos.y >= 0 and doorPos.y < MapHeight:
          if env.isEmpty(doorPos) and not env.hasDoor(doorPos):
            env.add(Thing(kind: Door, pos: doorPos, teamId: teamId, hp: DoorMaxHearts, maxHp: DoorMaxHearts))

      # Add the interior buildings from the layout
      for y in 0 ..< villageStruct.height:
        for x in 0 ..< villageStruct.width:
          if y < villageStruct.layout.len and x < villageStruct.layout[y].len:
            let worldPos = placementPosition + ivec2(x.int32, y.int32)
            case villageStruct.layout[y][x]:
            of StructureBlacksmithChar:  # Blacksmith
              env.add(Thing(
                kind: Blacksmith,
                pos: worldPos,
                teamId: teamId,
                barrelCapacity: buildingBarrelCapacity(Blacksmith)
              ))
            of StructureClayOvenChar:  # Clay Oven at bottom-left
              env.add(Thing(
                kind: ClayOven,
                pos: worldPos,
                teamId: teamId
              ))
            of StructureWeavingLoomChar:  # Weaving Loom at bottom-right
              env.add(Thing(
                kind: WeavingLoom,
                pos: worldPos,
                teamId: teamId
              ))
            of StructureTownCenterChar:  # Town Center
              env.add(Thing(
                kind: TownCenter,
                pos: worldPos,
                teamId: teamId
              ))
            of StructureBarracksChar:  # Barracks
              env.add(Thing(
                kind: Barracks,
                pos: worldPos,
                teamId: teamId
              ))
            of StructureArcheryRangeChar:  # Archery Range
              env.add(Thing(
                kind: ArcheryRange,
                pos: worldPos,
                teamId: teamId
              ))
            of StructureStableChar:  # Stable
              env.add(Thing(
                kind: Stable,
                pos: worldPos,
                teamId: teamId
              ))
            of StructureSiegeWorkshopChar:  # Siege Workshop
              env.add(Thing(
                kind: SiegeWorkshop,
                pos: worldPos,
                teamId: teamId
              ))
            of StructureMarketChar:  # Market
              env.add(Thing(
                kind: Market,
                pos: worldPos,
                teamId: teamId
              ))
            of StructureDockChar:  # Dock
              env.add(Thing(
                kind: Dock,
                pos: worldPos,
                teamId: teamId
              ))
            of StructureUniversityChar:  # University
              env.add(Thing(
                kind: University,
                pos: worldPos,
                teamId: teamId
              ))
            else:
              discard
      if agentsForThisVillage > 0:
        # Get nearby positions around the altar
        let nearbyPositions = env.findEmptyPositionsAround(elements.center, 3)

        for j in 0 ..< agentsForThisVillage:
          let agentId = teamId * MapAgentsPerVillage + j

          # Store the village color for this agent (shared by all agents of the village)
          env.agentColors[agentId] = env.teamColors[teamId]

          var agentPos = ivec2(-1, -1)
          var frozen = 0
          var hp = 0
          if j < min(6, agentsForThisVillage):
            if j < nearbyPositions.len:
              agentPos = nearbyPositions[j]
            else:
              agentPos = r.randomEmptyPos(env)
            hp = AgentMaxHp
            env.terminated[agentId] = 0.0
          else:
            env.terminated[agentId] = 1.0

          # Create the agent slot (only the first is placed immediately)
          env.add(Thing(
            kind: Agent,
            agentId: agentId,
            pos: agentPos,
            orientation: Orientation(randIntInclusive(r, 0, 3)),
            homeAltar: elements.center,  # Link agent to their home altar
            frozen: frozen,
            hp: hp,
            maxHp: AgentMaxHp,
            attackDamage: VillagerAttackDamage,
            unitClass: UnitVillager,
            embarkedUnitClass: UnitVillager
          ))

          totalAgentsSpawned += 1
          if totalAgentsSpawned >= MapRoomObjectsAgents:
            break

      # Note: Door gaps are placed instead of walls for defendable entrances

  # Now place additional random walls after villages to avoid blocking corner placement
  for i in 0 ..< MapRoomObjectsWalls:
    let pos = r.randomEmptyPos(env)
    env.add(Thing(kind: Wall, pos: pos))

  # If there are still agents to spawn (e.g., if not enough villages), spawn them randomly
  # They will get a neutral color
  while totalAgentsSpawned < MapRoomObjectsAgents:
    let agentPos = r.randomEmptyPos(env)
    let agentId = totalAgentsSpawned

    # Store neutral color for agents without a village
    env.agentColors[agentId] = color(0.5, 0.5, 0.5, 1.0)  # Gray for unaffiliated agents

    env.add(Thing(
      kind: Agent,
      agentId: agentId,
      pos: agentPos,
      orientation: Orientation(randIntInclusive(r, 0, 3)),
      homeAltar: ivec2(-1, -1),  # No home altar for unaffiliated agents
      frozen: 0,
      hp: AgentMaxHp,
      maxHp: AgentMaxHp,
      attackDamage: VillagerAttackDamage,
      unitClass: UnitVillager,
      embarkedUnitClass: UnitVillager,
    ))

    totalAgentsSpawned += 1

  # Random spawner placement with minimum distance from villages and other spawners
  # Gather altar positions for distance checks
  var altarPositionsNow: seq[IVec2] = @[]
  var spawnerPositions: seq[IVec2] = @[]
  for thing in env.things:
    if thing.kind == Altar:
      altarPositionsNow.add(thing.pos)

  let minDist = DefaultSpawnerMinDistance  # from balance.nim
  let minDist2 = minDist * minDist

  for i in 0 ..< numVillages:
    let spawnerStruct = Structure(width: 3, height: 3, centerPos: ivec2(1, 1))
    var placed = false
    var targetPos: IVec2

    for attempt in 0 ..< 200:
      targetPos = r.randomEmptyPos(env)
      # Keep within borders allowing spawner bounds
      if targetPos.x < MapBorder + spawnerStruct.width div 2 or
         targetPos.x >= MapWidth - MapBorder - spawnerStruct.width div 2 or
         targetPos.y < MapBorder + spawnerStruct.height div 2 or
         targetPos.y >= MapHeight - MapBorder - spawnerStruct.height div 2:
        continue

      # Check simple area clear (3x3)
      var areaValid = true
      for dx in -(spawnerStruct.width div 2) .. (spawnerStruct.width div 2):
        for dy in -(spawnerStruct.height div 2) .. (spawnerStruct.height div 2):
          let checkPos = targetPos + ivec2(dx, dy)
          if not isValidPos(checkPos):
            areaValid = false
            break
          if not env.isEmpty(checkPos) or isBlockedTerrain(env.terrain[checkPos.x][checkPos.y]):
            areaValid = false
            break
        if not areaValid:
          break

      if not areaValid:
        continue

      # Enforce min distance from any altar and other spawners
      var okDistance = true
      # Check distance from villages (altars)
      for ap in altarPositionsNow:
        let dx = int(targetPos.x) - int(ap.x)
        let dy = int(targetPos.y) - int(ap.y)
        if dx*dx + dy*dy < minDist2:
          okDistance = false
          break
      # Check distance from other spawners
      for sp in spawnerPositions:
        let dx = int(targetPos.x) - int(sp.x)
        let dy = int(targetPos.y) - int(sp.y)
        if dx*dx + dy*dy < minDist2:
          okDistance = false
          break
      if not okDistance:
        continue

      # Clear terrain and place spawner
      for dx in -(spawnerStruct.width div 2) .. (spawnerStruct.width div 2):
        for dy in -(spawnerStruct.height div 2) .. (spawnerStruct.height div 2):
          let clearPos = targetPos + ivec2(dx, dy)
          if clearPos.x >= 0 and clearPos.x < MapWidth and clearPos.y >= 0 and clearPos.y < MapHeight:
            if not isBlockedTerrain(env.terrain[clearPos.x][clearPos.y]):
              env.terrain[clearPos.x][clearPos.y] = Empty
              env.resetTileColor(clearPos)

      env.add(Thing(
        kind: Spawner,
        pos: targetPos,
        cooldown: 0,
        homeSpawner: targetPos
      ))

      # Add this spawner position for future collision checks
      spawnerPositions.add(targetPos)

      let nearbyPositions = env.findEmptyPositionsAround(targetPos, 1)
      if nearbyPositions.len > 0:
        let spawnCount = min(3, nearbyPositions.len)
        for i in 0 ..< spawnCount:
          env.add(createTumor(nearbyPositions[i], targetPos, r))
      placed = true
      break

    # If we fail to satisfy distance after attempts, place anywhere random
    if not placed:
      targetPos = r.randomEmptyPos(env)
      env.add(Thing(
        kind: Spawner,
        pos: targetPos,
        cooldown: 0,
        homeSpawner: targetPos
      ))
      let nearbyPositions = env.findEmptyPositionsAround(targetPos, 1)
      if nearbyPositions.len > 0:
        let spawnCount = min(3, nearbyPositions.len)
        for i in 0 ..< spawnCount:
          env.add(createTumor(nearbyPositions[i], targetPos, r))

  # Magma spawns in slightly larger clusters (3-4) for higher local density.
  var poolsPlaced = 0
  let magmaClusterCount = max(1, min(MapRoomObjectsMagmaClusters, max(1, MapRoomObjectsMagmaPools div 2)))
  for clusterIndex in 0 ..< magmaClusterCount:
    let remaining = MapRoomObjectsMagmaPools - poolsPlaced
    if remaining <= 0:
      break
    let clustersLeft = magmaClusterCount - clusterIndex
    let maxCluster = min(4, remaining)
    let minCluster = if remaining >= 3: 3 else: 1
    let baseSize = max(minCluster, min(maxCluster, remaining div clustersLeft))
    let clusterSize = max(minCluster, min(maxCluster, baseSize + randIntInclusive(r, -1, 1)))
    let center = r.randomEmptyPos(env)

    env.add(Thing(
      kind: Magma,
      pos: center,
    ))
    inc poolsPlaced

    if poolsPlaced >= MapRoomObjectsMagmaPools:
      break

    var candidates = env.findEmptyPositionsAround(center, 1)
    if candidates.len < clusterSize - 1:
      let extra = env.findEmptyPositionsAround(center, 2)
      for pos in extra:
        var exists = false
        for c in candidates:
          if c == pos:
            exists = true
            break
        if not exists:
          candidates.add(pos)

    let toPlace = min(clusterSize - 1, candidates.len)
    for i in 0 ..< toPlace:
      env.add(Thing(
        kind: Magma,
        pos: candidates[i],
      ))
      inc poolsPlaced
      if poolsPlaced >= MapRoomObjectsMagmaPools:
        break

  # Spawn resource nodes (trees, wheat, ore, plants) as Things.
  block:
    # Wheat fields.
    for _ in 0 ..< randIntInclusive(r, WheatFieldClusterCountMin, WheatFieldClusterCountMax):
      var placed = false
      for attempt in 0 ..< 20:
        let x = randIntInclusive(r, MapBorder + 3, MapWidth - MapBorder - 3)
        let y = randIntInclusive(r, MapBorder + 3, MapHeight - MapBorder - 3)
        var nearWater = false
        for dx in -5 .. 5:
          for dy in -5 .. 5:
            let checkX = x + dx
            let checkY = y + dy
            if checkX >= 0 and checkX < MapWidth and checkY >= 0 and checkY < MapHeight:
              if env.terrain[checkX][checkY] == Water:
                nearWater = true
                break
          if nearWater:
            break
        if nearWater or attempt > 10:
          let fieldSize = randIntInclusive(r, WheatFieldSizeMin, WheatFieldSizeMax)
          placeResourceCluster(env, x, y, fieldSize, 1.0, 0.3, Wheat, ItemWheat, ResourceGround, r)
          placeResourceCluster(env, x, y, fieldSize + 1, 0.5, 0.3, Wheat, ItemWheat, ResourceGround, r)
          placed = true
          break
      if not placed:
        let x = randIntInclusive(r, MapBorder + 3, MapWidth - MapBorder - 3)
        let y = randIntInclusive(r, MapBorder + 3, MapHeight - MapBorder - 3)
        let fieldSize = randIntInclusive(r, WheatFieldSizeMin, WheatFieldSizeMax)
        placeResourceCluster(env, x, y, fieldSize, 1.0, 0.3, Wheat, ItemWheat, ResourceGround, r)
        placeResourceCluster(env, x, y, fieldSize + 1, 0.5, 0.3, Wheat, ItemWheat, ResourceGround, r)

    proc placeTreeOasis(centerX, centerY: int) =
      let rx = randIntInclusive(r, TreeOasisWaterRadiusMin, TreeOasisWaterRadiusMax)
      let ry = randIntInclusive(r, TreeOasisWaterRadiusMin, TreeOasisWaterRadiusMax)
      template canPlaceWater(pos: IVec2): bool =
        env.isEmpty(pos) and isNil(env.getOverlayThing(pos)) and not env.hasDoor(pos) and
          env.terrain[pos.x][pos.y] notin {Road, Bridge}
      for ox in -(rx + 1) .. (rx + 1):
        for oy in -(ry + 1) .. (ry + 1):
          let px = centerX + ox
          let py = centerY + oy
          if px < MapBorder or px >= MapWidth - MapBorder or py < MapBorder or py >= MapHeight - MapBorder:
            continue
          let waterPos = ivec2(px.int32, py.int32)
          if not canPlaceWater(waterPos):
            continue
          let dx = ox.float / rx.float
          let dy = oy.float / ry.float
          let dist = dx * dx + dy * dy
          if dist <= 1.0 + (randFloat(r) - 0.5) * 0.35:
            env.terrain[px][py] = Water
            env.resetTileColor(waterPos)

      for _ in 0 ..< randIntInclusive(r, 1, 2):
        var pos = ivec2(centerX.int32, centerY.int32)
        for _ in 0 ..< randIntInclusive(r, 4, 10):
          let dir = sample(r, [ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1),
                               ivec2(1, 1), ivec2(-1, 1), ivec2(1, -1), ivec2(-1, -1)])
          pos += dir
          if pos.x < MapBorder.int32 or pos.x >= (MapWidth - MapBorder).int32 or
             pos.y < MapBorder.int32 or pos.y >= (MapHeight - MapBorder).int32:
            break
          if not canPlaceWater(pos):
            continue
          env.terrain[pos.x][pos.y] = Water
          env.resetTileColor(pos)

      for ox in -(rx + 2) .. (rx + 2):
        for oy in -(ry + 2) .. (ry + 2):
          let px = centerX + ox
          let py = centerY + oy
          if px < MapBorder or px >= MapWidth - MapBorder or py < MapBorder or py >= MapHeight - MapBorder:
            continue
          if env.terrain[px][py] == Water:
            continue
          var nearWater = false
          for dx in -1 .. 1:
            for dy in -1 .. 1:
              let nx = px + dx
              let ny = py + dy
              if nx < MapBorder or nx >= MapWidth - MapBorder or ny < MapBorder or ny >= MapHeight - MapBorder:
                continue
              if env.terrain[nx][ny] == Water:
                nearWater = true
                break
            if nearWater:
              break
          if nearWater and randChance(r, 0.7) and env.terrain[px][py] in TreeGround:
            addResourceNode(env, ivec2(px.int32, py.int32), Tree, ItemWood)

    if UseTreeOases:
      let numGroves = randIntInclusive(r, TreeOasisClusterCountMin, TreeOasisClusterCountMax)
      for _ in 0 ..< numGroves:
        var placed = false
        for attempt in 0 ..< 16:
          let x = randIntInclusive(r, MapBorder + 3, MapWidth - MapBorder - 3)
          let y = randIntInclusive(r, MapBorder + 3, MapHeight - MapBorder - 3)
          var nearWater = false
          for dx in -5 .. 5:
            for dy in -5 .. 5:
              let checkX = x + dx
              let checkY = y + dy
              if checkX >= 0 and checkX < MapWidth and checkY >= 0 and checkY < MapHeight:
                if env.terrain[checkX][checkY] == Water:
                  nearWater = true
                  break
            if nearWater:
              break
          if nearWater or attempt > 10:
            placeTreeOasis(x, y)
            placed = true
            break
        if not placed:
          let x = randIntInclusive(r, MapBorder + 3, MapWidth - MapBorder - 3)
          let y = randIntInclusive(r, MapBorder + 3, MapHeight - MapBorder - 3)
          placeTreeOasis(x, y)

    if UseLegacyTreeClusters:
      let numGroves = randIntInclusive(r, TreeGroveClusterCountMin, TreeGroveClusterCountMax)
      for _ in 0 ..< numGroves:
        let x = randIntInclusive(r, MapBorder + 3, MapWidth - MapBorder - 3)
        let y = randIntInclusive(r, MapBorder + 3, MapHeight - MapBorder - 3)
        let groveSize = randIntInclusive(r, 3, 10)
        placeResourceCluster(env, x, y, groveSize, 0.8, 0.4, Tree, ItemWood, ResourceGround, r)

    proc buildClusterSizes(targetDeposits: int, clusterCount: int): seq[int] =
      let minCluster = 3
      let maxCluster = 4
      let minDeposits = clusterCount * minCluster
      let maxDeposits = clusterCount * maxCluster
      let clamped = max(minDeposits, min(maxDeposits, targetDeposits))
      result = newSeq[int](clusterCount)
      for i in 0 ..< clusterCount:
        result[i] = minCluster
      var extras = clamped - minDeposits
      while extras > 0:
        let idx = randIntInclusive(r, 0, clusterCount - 1)
        if result[idx] < maxCluster:
          inc result[idx]
          dec extras

    proc placeMineClusters(depositKind: ThingKind, depositItem: ItemKey,
                           targetDeposits: int, clusterCount: int) =
      if targetDeposits <= 0 or clusterCount <= 0:
        return
      let clusterSizes = buildClusterSizes(targetDeposits, clusterCount)
      for clusterIndex in 0 ..< clusterSizes.len:
        let clusterSize = clusterSizes[clusterIndex]
        let center = r.randomEmptyPos(env)

        addResourceNode(env, center, depositKind, depositItem, MineDepositAmount)

        var candidates = env.findEmptyPositionsAround(center, 1)
        if candidates.len < clusterSize - 1:
          let extra = env.findEmptyPositionsAround(center, 2)
          for pos in extra:
            var exists = false
            for c in candidates:
              if c == pos:
                exists = true
                break
            if not exists:
              candidates.add(pos)

        let toPlace = min(clusterSize - 1, candidates.len)
        for i in 0 ..< toPlace:
          addResourceNode(env, candidates[i], depositKind, depositItem, MineDepositAmount)

    placeMineClusters(Stone, ItemStone, MapRoomObjectsStoneClusters, MapRoomObjectsStoneClusterCount)
    placeMineClusters(Gold, ItemGold, MapRoomObjectsGoldClusters, MapRoomObjectsGoldClusterCount)

    let fishClusters = max(8, MapWidth div 20)
    for _ in 0 ..< fishClusters:
      var placed = false
      for attempt in 0 ..< 20:
        let x = randIntInclusive(r, MapBorder + 2, MapWidth - MapBorder - 2)
        let y = randIntInclusive(r, MapBorder + 2, MapHeight - MapBorder - 2)
        if env.terrain[x][y] != Water:
          continue
        let size = randIntInclusive(r, 3, 7)
        placeResourceCluster(env, x, y, size, 0.85, 0.45, Fish, ItemFish, {Water}, r)
        placed = true
        break
      if not placed:
        break

    for _ in 0 ..< 30:
      var attempts = 0
      var placed = false
      while attempts < 12 and not placed:
        inc attempts
        let x = randIntInclusive(r, MapBorder + 2, MapWidth - MapBorder - 2)
        let y = randIntInclusive(r, MapBorder + 2, MapHeight - MapBorder - 2)
        var nearWater = false
        for dx in -4 .. 4:
          for dy in -4 .. 4:
            let checkX = x + dx
            let checkY = y + dy
            if checkX >= 0 and checkX < MapWidth and checkY >= 0 and checkY < MapHeight:
              if env.terrain[checkX][checkY] == Water:
                nearWater = true
                break
          if nearWater:
            break
        if nearWater or attempts >= 10:
          let size = randIntInclusive(r, 3, 7)
          placeResourceCluster(env, x, y, size, 0.75, 0.45, Bush, ItemPlant, ResourceGround, r)
          placed = true

    for _ in 0 ..< max(10, MapWidth div 20):
      let x = randIntInclusive(r, MapBorder + 2, MapWidth - MapBorder - 2)
      let y = randIntInclusive(r, MapBorder + 2, MapHeight - MapBorder - 2)
      let size = randIntInclusive(r, 2, 5)
      placeResourceCluster(env, x, y, size, 0.65, 0.4, Cactus, ItemPlant, ResourceGround, r,
        allowedBiomes = {BiomeDesertType})

    for _ in 0 ..< max(10, MapWidth div 30):
      let x = randIntInclusive(r, MapBorder + 2, MapWidth - MapBorder - 2)
      let y = randIntInclusive(r, MapBorder + 2, MapHeight - MapBorder - 2)
      let size = randIntInclusive(r, 2, 6)
      placeResourceCluster(env, x, y, size, 0.7, 0.45, Stalagmite, ItemStone, ResourceGround, r,
        allowedBiomes = {BiomeCavesType})

  # Ensure the world is a single connected component after terrain and structures.
  env.makeConnected()


  # Cows spawn in herds (5-10) across open terrain.
  const MinHerdSize = 5
  const MaxHerdSize = 10
  var cowsPlaced = 0
  var herdId = 0
  while cowsPlaced < MapRoomObjectsCows:
    let remaining = MapRoomObjectsCows - cowsPlaced
    var herdSize: int
    if remaining <= MaxHerdSize:
      herdSize = remaining
    else:
      herdSize = randIntInclusive(r, MinHerdSize, MaxHerdSize)
      let remainder = remaining - herdSize
      if remainder > 0 and remainder < MinHerdSize:
        herdSize -= (MinHerdSize - remainder)
    let center = r.randomEmptyPos(env)
    if env.terrain[center.x][center.y] != Empty:
      continue
    if env.biomes[center.x][center.y] == BiomeDungeonType:
      continue
    var herdPositions = env.findEmptyPositionsAround(center, 3)
    herdPositions.insert(center, 0)
    var filtered: seq[IVec2] = @[]
    for pos in herdPositions:
      if env.terrain[pos.x][pos.y] == Empty and env.biomes[pos.x][pos.y] != BiomeDungeonType:
        filtered.add(pos)
    if filtered.len < 5:
      continue
    let toPlace = min(herdSize, filtered.len)
    for i in 0 ..< toPlace:
      let cow = Thing(
        kind: Cow,
        pos: filtered[i],
        orientation: Orientation.W,
        herdId: herdId
      )
      cow.inventory = emptyInventory()
      setInv(cow, ItemMeat, ResourceNodeInitial)
      env.add(cow)
      inc cowsPlaced
      if cowsPlaced >= MapRoomObjectsCows:
        break
    inc herdId

  # Initialize altar locations for all spawners
  var altarPositions: seq[IVec2] = @[]
  for thing in env.things:
    if thing.kind == Altar:
      altarPositions.add(thing.pos)

  # Initialize observations only when first needed (lazy approach)
  # Individual action updates will populate observations as needed


proc defaultEnvironmentConfig*(): EnvironmentConfig =
  ## Create default environment configuration
  EnvironmentConfig(
    # Core game parameters
    maxSteps: 10000,

    # Combat configuration
    tumorSpawnRate: 0.1,

    # Reward configuration (only arena_basic_easy_shaped rewards active)
    heartReward: 1.0,      # Arena: heart reward
    oreReward: 0.1,        # Arena: gold mining reward
    barReward: 0.8,        # Arena: bar smelting reward
    woodReward: 0.0,       # Disabled - not in arena
    waterReward: 0.0,      # Disabled - not in arena
    wheatReward: 0.0,      # Disabled - not in arena
    spearReward: 0.0,      # Disabled - not in arena
    armorReward: 0.0,      # Disabled - not in arena
    foodReward: 0.0,       # Disabled - not in arena
    clothReward: 0.0,      # Disabled - not in arena
    tumorKillReward: 0.0, # Disabled - not in arena
    survivalPenalty: -0.01,
    deathPenalty: -5.0
  )

proc newEnvironment*(): Environment =
  ## Create a new environment with default configuration
  result = Environment(config: defaultEnvironmentConfig())
  result.init()

proc newEnvironment*(config: EnvironmentConfig): Environment =
  ## Create a new environment with custom configuration
  result = Environment(config: config)
  result.init()

# Initialize the global environment
env = newEnvironment()
