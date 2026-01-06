# This file is included by src/environment.nim
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

proc init(env: Environment) =
  # Use current time for random seed to get different maps each time
  let seed = int(nowSeconds() * 1000)
  var r = initRand(seed)

  # Initialize tile colors to base terrain colors (neutral gray-brown)
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      env.tileColors[x][y] = BaseTileColorDefault
      env.baseTintColors[x][y] = BaseTileColorDefault
      env.baseTileColors[x][y] = BaseTileColorDefault

  # Clear door grid
  env.clearDoors()

  # Reset team stockpiles
  env.teamStockpiles = default(array[MapRoomObjectsHouses, TeamStockpile])

  # Initialize active tiles tracking
  env.activeTiles.positions.setLen(0)
  env.activeTiles.flags = default(array[MapWidth, array[MapHeight, bool]])

  # Clear action tints
  env.actionTintCountdown = default(ActionTintCountdown)
  env.actionTintColor = default(ActionTintColor)
  env.actionTintFlags = default(ActionTintFlags)
  env.actionTintPositions.setLen(0)
  env.shieldCountdown = default(array[MapAgents, int8])

  # Initialize terrain with all features
  initTerrain(env.terrain, env.biomes, MapWidth, MapHeight, MapBorder, seed)
  env.applyBiomeBaseColors()

  # Keep forest/palm terrain as walkable tiles (trees are harvested from terrain).

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
      if existing != nil:
        if existing.kind in {Pine, Palm}:
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
    let zones = evenlyDistributedZones(r, MapWidth, MapHeight, MapBorder, count, DungeonZoneMaxFraction)
    var seqIdx = randIntInclusive(r, 0, dungeonKinds.len - 1)
    for zone in zones:
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
          let blended = blendTileColor(base, dungeonColor, t)
          env.baseTintColors[x][y] = blended
          env.baseTileColors[x][y] = blended
          env.tileColors[x][y] = blended
      var mask: MaskGrid
      let dungeonKind = if UseSequentialDungeonZones:
        let selected = dungeonKinds[seqIdx mod dungeonKinds.len]
        inc seqIdx
        selected
      else:
        pickDungeonKind(r)
      buildDungeonMask(mask, MapWidth, MapHeight, zone, r, dungeonKind)

      for x in x0 ..< x1:
        for y in y0 ..< y1:
          if not zoneMask[x][y]:
            continue
          let shouldWall = if dungeonKind == DungeonRadial:
            not mask[x][y]  # radial mask encodes corridors; invert for walls
          else:
            mask[x][y]
          if shouldWall and not isBlockedTerrain(env.terrain[x][y]):
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
        if existing != nil:
          if existing.kind in {Pine, Palm}:
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
  # Clear and prepare village colors arrays
  agentVillageColors.setLen(MapRoomObjectsAgents)  # Allocate space for all agents
  teamColors.setLen(0)  # Clear team colors
  altarColors.clear()  # Clear altar colors from previous game
  # Spawn villages with altars, town centers, and associated agents (tribes)
  let numVillages = MapRoomObjectsHouses
  var totalAgentsSpawned = 0
  var villageCenters: seq[IVec2] = @[]
  proc placeStartingTownCenter(center: IVec2, teamId: int, r: var Rand): IVec2 =
    let reserved = [
      center + ivec2(2, -2),
      center + ivec2(2, 2),
      center + ivec2(-2, 2),
      center + ivec2(-2, -2)
    ]
    var candidates: seq[IVec2] = @[]
    for dx in -3 .. 3:
      for dy in -3 .. 3:
        if dx == 0 and dy == 0:
          continue
        let dist = max(abs(dx), abs(dy))
        if dist < 1 or dist > 3:
          continue
        let pos = center + ivec2(dx.int32, dy.int32)
        if pos in reserved:
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
      if existing != nil:
        if existing.kind in {Pine, Palm}:
          removeThing(env, existing)
        else:
          continue
      if env.hasDoor(pos):
        continue
      if not env.isEmpty(pos):
        continue
      let tc = Thing(kind: TownCenter, pos: pos, teamId: teamId)
      env.add(tc)
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
      if existing != nil:
        if existing.kind in {Pine, Palm}:
          removeThing(env, existing)
        else:
          return
      if env.terrain[pos.x][pos.y] != Road:
        env.terrain[pos.x][pos.y] = Road
        env.resetTileColor(pos)

    let connectKinds = {TownCenter, House, Granary, LumberYard, Quarry, Bank, Mill}
    var anchors: seq[IVec2] = @[center]
    for thing in env.things:
      if thing.teamId != teamId:
        continue
      if thing.kind notin connectKinds:
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

    let dirs = [(ivec2(1, 0), maxEast), (ivec2(-1, 0), maxWest),
                (ivec2(0, 1), maxSouth), (ivec2(0, -1), maxNorth)]
    for (dir, baseDist) in dirs:
      let extra = randIntInclusive(r, 3, 4)
      let total = baseDist + extra
      for step in 1 .. total:
        let pos = center + ivec2(dir.x.int32 * step.int32, dir.y.int32 * step.int32)
        placeRoad(pos)

  proc placeStartingResourceBuildings(center: IVec2, teamId: int) =
    let placements = [
      (offset: ivec2(2, -2), kind: LumberYard, res: ResourceWood),   # Lumber Yard
      (offset: ivec2(2, 2), kind: Granary, res: ResourceFood),       # Granary
      (offset: ivec2(-2, 2), kind: Quarry, res: ResourceStone),      # Quarry
      (offset: ivec2(-2, -2), kind: Bank, res: ResourceGold)         # Bank
    ]
    for entry in placements:
      var placed = false
      let basePos = center + entry.offset
      for radius in 0 .. 2:
        for dx in -radius .. radius:
          for dy in -radius .. radius:
            if radius > 0 and max(abs(dx), abs(dy)) != radius:
              continue
            let pos = basePos + ivec2(dx.int32, dy.int32)
            if not isValidPos(pos):
              continue
            if env.terrain[pos.x][pos.y] == Water or isTileFrozen(pos, env):
              continue
            if env.hasDoor(pos):
              continue
            let existing = env.getThing(pos)
            if existing != nil:
              if existing.kind in {Pine, Palm}:
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
    let count = 4 + randIntInclusive(r, 0, 1)
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
    let villageStruct = createVillage()
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
        const MinVillageSpacing = 22
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
      teamColors.add(villageColor)
      let teamId = teamColors.len - 1

      # Spawn agent slots for this village (six active, the rest dormant)
      let agentsForThisVillage = min(MapAgentsPerVillage, MapRoomObjectsAgents - totalAgentsSpawned)
      let baseAgentId = teamId * MapAgentsPerVillage

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
      altarColors[elements.center] = villageColor  # Associate altar position with village color

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
            env.baseTileColors[tileX][tileY] = TileColor(
              r: villageColor.r,
              g: villageColor.g,
              b: villageColor.b,
              intensity: 1.0
            )
            env.tileColors[tileX][tileY] = env.baseTileColors[tileX][tileY]

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
          env.doorTeams[doorPos.x][doorPos.y] = teamId.int16
          env.doorHearts[doorPos.x][doorPos.y] = DoorMaxHearts.int8

      # Add the interior buildings from the layout
      for y in 0 ..< villageStruct.height:
        for x in 0 ..< villageStruct.width:
          if y < villageStruct.layout.len and x < villageStruct.layout[y].len:
            let worldPos = placementPosition + ivec2(x.int32, y.int32)
            case villageStruct.layout[y][x]:
            of StructureArmoryChar:  # Armory at top-left
              env.add(Thing(
                kind: Armory,
                pos: worldPos,
                teamId: teamId
              ))
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
      if agentsForThisHouse > 0:
        # Get nearby positions around the altar
        let nearbyPositions = env.findEmptyPositionsAround(elements.center, 3)
        let initialActive = min(6, agentsForThisHouse)

      for j in 0 ..< agentsForThisVillage:
          let agentId = baseAgentId + j

          # Store the village color for this agent (shared by all agents of the village)
          agentVillageColors[agentId] = teamColors[teamId]

          var agentPos = ivec2(-1, -1)
          var frozen = 0
          var hp = 0
          if j < initialActive:
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
            unitClass: UnitVillager
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
  let neutralColor = color(0.5, 0.5, 0.5, 1.0)  # Gray for unaffiliated agents
  while totalAgentsSpawned < MapRoomObjectsAgents:
    let agentPos = r.randomEmptyPos(env)
    let agentId = totalAgentsSpawned

    # Store neutral color for agents without a village
    agentVillageColors[agentId] = neutralColor

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
    ))

    totalAgentsSpawned += 1

  # Random spawner placement with minimum distance from villages and other spawners
  # Gather altar positions for distance checks
  var altarPositionsNow: seq[IVec2] = @[]
  var spawnerPositions: seq[IVec2] = @[]
  for thing in env.things:
    if thing.kind == Altar:
      altarPositionsNow.add(thing.pos)

  let numSpawners = numVillages
  let minDist = 20  # tiles; simple guard so spawner isn't extremely close to a village
  let minDist2 = minDist * minDist

  for i in 0 ..< numSpawners:
    let spawnerStruct = createSpawner()
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
          if checkPos.x < 0 or checkPos.x >= MapWidth or checkPos.y < 0 or checkPos.y >= MapHeight:
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

  # Gold/stone deposits spawn as slightly larger terrain clusters (4-7 tiles), non-depleting.
  var depositsPlaced = 0
  let clusterCount = max(1, min(MapRoomObjectsMineClusters, max(1, MapRoomObjectsMines div 3)))
  for clusterIndex in 0 ..< clusterCount:
    let remaining = MapRoomObjectsMines - depositsPlaced
    if remaining <= 0:
      break
    let clustersLeft = clusterCount - clusterIndex
    let maxCluster = min(7, remaining)
    let minCluster = min(4, remaining)
    let baseSize = max(minCluster, min(maxCluster, remaining div clustersLeft))
    let clusterSize = max(minCluster, min(maxCluster, baseSize + randIntInclusive(r, -1, 1)))
    let depositTerrain = if clusterIndex mod 2 == 0: Stone else: Gold
    let center = r.randomEmptyPos(env)

    env.terrain[center.x][center.y] = depositTerrain
    env.resetTileColor(center)
    inc depositsPlaced

    if depositsPlaced >= MapRoomObjectsMines:
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
      let pos = candidates[i]
      env.terrain[pos.x][pos.y] = depositTerrain
      env.resetTileColor(pos)
      inc depositsPlaced
      if depositsPlaced >= MapRoomObjectsMines:
        break

  # Ensure the world is a single connected component after terrain and structures.
  env.makeConnected()

  # Initialize terrain resource counts (each resource tile yields 1 per harvest, 25 total).
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      if env.terrain[x][y] in {Water, Wheat, Pine, Palm, Stone, Gold, Bush, Cactus, Stalagmite}:
        env.terrainResources[x][y] = ResourceNodeInitial
      else:
        env.terrainResources[x][y] = 0

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
    maxSteps: 1000,

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
