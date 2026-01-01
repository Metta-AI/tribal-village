# This file is included by src/environment.nim
proc init(env: Environment) =
  # Use current time for random seed to get different maps each time
  let seed = int(nowSeconds() * 1000)
  var r = initRand(seed)

  # Initialize tile colors to base terrain colors (neutral gray-brown)
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      env.tileColors[x][y] = BaseTileColorDefault
      env.baseTileColors[x][y] = BaseTileColorDefault

  # Clear door grid
  env.clearDoors()

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

  # Convert forest/palm terrain into blocking tree objects.
  for x in MapBorder ..< MapWidth - MapBorder:
    for y in MapBorder ..< MapHeight - MapBorder:
      let pos = ivec2(x.int32, y.int32)
      if not env.isEmpty(pos):
        continue
      let isPalm = env.terrain[x][y] == Palm
      let isForestTree = env.terrain[x][y] == Tree and env.biomes[x][y] == BiomeForestType
      if isPalm or isForestTree:
        let variant = if isPalm: TreeVariantPalm else: TreeVariantPine
        env.terrain[x][y] = Empty
        env.add(Thing(kind: TreeObject, pos: ivec2(x.int32, y.int32), treeVariant: variant))

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
        if existing.kind == TreeObject:
          removeThing(env, existing)
        else:
          continue
      env.terrain[x][y] = Empty
      env.add(Thing(kind: Wall, pos: pos))

  # Add sparse dungeon walls using procedural dungeon masks.
  if UseDungeonZones:
    let count = zoneCount(MapWidth * MapHeight, DungeonZoneDivisor, DungeonZoneMinCount, DungeonZoneMaxCount)
    var dungeonWalls: MaskGrid
    dungeonWalls.clearMask(MapWidth, MapHeight)
    for i in 0 ..< count:
      let zone = randomZone(r, MapWidth, MapHeight, MapBorder, DungeonZoneMaxFraction)
      let x0 = max(MapBorder, zone.x)
      let y0 = max(MapBorder, zone.y)
      let x1 = min(MapWidth - MapBorder, zone.x + zone.w)
      let y1 = min(MapHeight - MapBorder, zone.y + zone.h)

      # Tint the dungeon zone background with a soft edge blend.
      for x in x0 ..< x1:
        for y in y0 ..< y1:
          env.biomes[x][y] = BiomeDungeonType
          let edge = min(min(x - x0, x1 - 1 - x), min(y - y0, y1 - 1 - y))
          let t = min(1.0'f32, max(0.0'f32, edge.float32 / 4.0))
          let dungeonColor = biomeBaseColor(BiomeDungeonType)
          let base = env.baseTileColors[x][y]
          let blended = blendTileColor(base, dungeonColor, t)
          env.baseTileColors[x][y] = blended
          env.tileColors[x][y] = blended
      var mask: MaskGrid
      let dungeonKind = pickDungeonKind(r)
      buildDungeonMask(mask, MapWidth, MapHeight, zone, r, dungeonKind)

      for x in x0 ..< x1:
        for y in y0 ..< y1:
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
          if existing.kind == TreeObject:
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

  # Agents will now spawn with their villages/houses below
  # Clear and prepare village colors arrays
  agentVillageColors.setLen(MapRoomObjectsAgents)  # Allocate space for all agents
  teamColors.setLen(0)  # Clear team colors
  assemblerColors.clear()  # Clear assembler colors from previous game
  # Spawn houses with their assemblers, walls, and associated agents (tribes)
  let numHouses = MapRoomObjectsHouses
  var totalAgentsSpawned = 0
  var houseCenters: seq[IVec2] = @[]
  for i in 0 ..< numHouses:
    let houseStruct = createVillage()
    var placed = false
    var placementPosition: IVec2

    # Simple random placement with collision avoidance
    for attempt in 0 ..< 200:
      let candidatePos = r.randomEmptyPos(env)
      # Check if position has enough space for the village footprint
      var canPlace = true
      for dy in 0 ..< houseStruct.height:
        for dx in 0 ..< houseStruct.width:
          let checkX = candidatePos.x + dx
          let checkY = candidatePos.y + dy
          if checkX >= MapWidth or checkY >= MapHeight or
             not env.isEmpty(ivec2(checkX, checkY)) or
             isBlockedTerrain(env.terrain[checkX][checkY]):
            canPlace = false
            break
        if not canPlace: break

      # Keep houses spaced apart (Chebyshev) to avoid crowding
      if canPlace:
        const MinHouseSpacing = 22
        let candidateCenter = candidatePos + houseStruct.centerPos
        for c in houseCenters:
          let dx = abs(c.x - candidateCenter.x)
          let dy = abs(c.y - candidateCenter.y)
          if max(dx, dy) < MinHouseSpacing:
            canPlace = false
            break

      if canPlace:
        placementPosition = candidatePos
        placed = true
        break

    if placed:
      let elements = getStructureElements(houseStruct, placementPosition)

      # Clear terrain within the house area to create a clearing
      for dy in 0 ..< houseStruct.height:
        for dx in 0 ..< houseStruct.width:
          let clearX = placementPosition.x + dx
          let clearY = placementPosition.y + dy
          if clearX >= 0 and clearX < MapWidth and clearY >= 0 and clearY < MapHeight:
            # Clear any terrain features (wheat, trees) but keep blocked terrain
            if not isBlockedTerrain(env.terrain[clearX][clearY]):
              env.terrain[clearX][clearY] = Empty
              env.resetTileColor(ivec2(clearX.int32, clearY.int32))

      # Generate a distinct warm color for this village (avoid cool/blue hues)
      let paletteIndex = i mod WarmVillagePalette.len
      let villageColor = WarmVillagePalette[paletteIndex]
      teamColors.add(villageColor)
      let teamId = teamColors.len - 1

      # Spawn agent slots for this house (one active, the rest dormant)
      let agentsForThisHouse = min(MapAgentsPerHouse, MapRoomObjectsAgents - totalAgentsSpawned)
      let baseAgentId = i * MapAgentsPerHouse

      # Add the altar (assembler) with initial hearts and house bounds
      let altar = Thing(
        kind: assembler,
        pos: elements.center,
        teamId: teamId
      )
      altar.inventory = emptyInventory()
      altar.hearts = MapObjectassemblerInitialHearts
      env.add(altar)
      houseCenters.add(elements.center)
      assemblerColors[elements.center] = villageColor  # Associate assembler position with village color

      # Initialize base colors for house tiles to team color
      for dx in 0 ..< houseStruct.width:
        for dy in 0 ..< houseStruct.height:
          let tileX = placementPosition.x + dx
          let tileY = placementPosition.y + dy
          if tileX >= 0 and tileX < MapWidth and tileY >= 0 and tileY < MapHeight:
            env.baseTileColors[tileX][tileY] = TileColor(
              r: villageColor.r,
              g: villageColor.g,
              b: villageColor.b,
              intensity: 1.0
            )
            env.tileColors[tileX][tileY] = env.baseTileColors[tileX][tileY]

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

      # Add the corner buildings from the house layout
      # Parse the house structure to find corner buildings
      for y in 0 ..< houseStruct.height:
        for x in 0 ..< houseStruct.width:
          if y < houseStruct.layout.len and x < houseStruct.layout[y].len:
            let worldPos = placementPosition + ivec2(x.int32, y.int32)
            case houseStruct.layout[y][x]:
            of 'A':  # Armory at top-left
              env.add(Thing(
                kind: Armory,
                pos: worldPos,
              ))
            of 'F':  # Forge at top-right
              env.add(Thing(
                kind: Forge,
                pos: worldPos,
              ))
            of 'C':  # Clay Oven at bottom-left
              env.add(Thing(
                kind: ClayOven,
                pos: worldPos,
              ))
            of 'W':  # Weaving Loom at bottom-right
              env.add(Thing(
                kind: WeavingLoom,
                pos: worldPos,
              ))
            of 'B':  # Bed
              env.add(Thing(
                kind: Bed,
                pos: worldPos,
              ))
            of 'H':  # Chair (throne)
              env.add(Thing(
                kind: Chair,
                pos: worldPos,
              ))
            of 'T':  # Table
              env.add(Thing(
                kind: Table,
                pos: worldPos,
              ))
            of 'S':  # Statue
              env.add(Thing(
                kind: Statue,
                pos: worldPos,
              ))
            else:
              discard
      if agentsForThisHouse > 0:
        # Get nearby positions around the assembler
        let nearbyPositions = env.findEmptyPositionsAround(elements.center, 3)

        for j in 0 ..< agentsForThisHouse:
          let agentId = baseAgentId + j

          # Store the village color for this agent (shared by all agents of the house)
          agentVillageColors[agentId] = teamColors[getTeamId(agentId)]

          var agentPos = ivec2(-1, -1)
          var frozen = 999999
          var hp = 0
          if j == 0:
            if nearbyPositions.len > 0:
              agentPos = nearbyPositions[0]
            else:
              agentPos = r.randomEmptyPos(env)
            frozen = 0
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
            homeassembler: elements.center,  # Link agent to their home assembler
            frozen: frozen,
            hp: hp,
            maxHp: AgentMaxHp
          ))

          totalAgentsSpawned += 1
          if totalAgentsSpawned >= MapRoomObjectsAgents:
            break

      # Note: Door gaps are placed instead of walls for defendable entrances

  # Now place additional random walls after villages to avoid blocking corner placement
  for i in 0 ..< MapRoomObjectsWalls:
    let pos = r.randomEmptyPos(env)
    env.add(Thing(kind: Wall, pos: pos))

  # If there are still agents to spawn (e.g., if not enough houses), spawn them randomly
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
      homeassembler: ivec2(-1, -1),  # No home assembler for unaffiliated agents
      frozen: 0,
    ))

    totalAgentsSpawned += 1

  # Random spawner placement with minimum distance from villages and other spawners
  # Gather assembler positions for distance checks
  var assemblerPositionsNow: seq[IVec2] = @[]
  var spawnerPositions: seq[IVec2] = @[]
  for thing in env.things:
    if thing.kind == assembler:
      assemblerPositionsNow.add(thing.pos)

  let numSpawners = numHouses
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

      # Enforce min distance from any assembler and other spawners
      var okDistance = true
      # Check distance from villages (assemblers)
      for ap in assemblerPositionsNow:
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

  for i in 0 ..< MapRoomObjectsConverters:
    let pos = r.randomEmptyPos(env)
    env.add(Thing(
      kind: Converter,
      pos: pos,
    ))

  # Mines spawn in small clusters (3-5 nodes) for higher local density.
  var minesPlaced = 0
  let clusterCount = max(1, min(MapRoomObjectsMineClusters, MapRoomObjectsMines))
  for clusterIndex in 0 ..< clusterCount:
    let remaining = MapRoomObjectsMines - minesPlaced
    if remaining <= 0:
      break
    let clustersLeft = clusterCount - clusterIndex
    let maxCluster = min(5, remaining)
    let minCluster = if remaining >= 3: 3 else: 1
    let baseSize = max(minCluster, min(maxCluster, remaining div clustersLeft))
    let clusterSize = max(1, min(maxCluster, baseSize + randIntInclusive(r, -1, 1)))
    let center = r.randomEmptyPos(env)

    let mine = Thing(
      kind: Mine,
      pos: center
    )
    mine.inventory = emptyInventory()
    mine.resources = MapObjectMineInitialResources
    env.add(mine)
    inc minesPlaced

    if minesPlaced >= MapRoomObjectsMines:
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
      let mine = Thing(
        kind: Mine,
        pos: candidates[i]
      )
      mine.inventory = emptyInventory()
      mine.resources = MapObjectMineInitialResources
      env.add(mine)
      inc minesPlaced
      if minesPlaced >= MapRoomObjectsMines:
        break

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
    var herdPositions = env.findEmptyPositionsAround(center, 3)
    herdPositions.insert(center, 0)
    var filtered: seq[IVec2] = @[]
    for pos in herdPositions:
      if env.terrain[pos.x][pos.y] == Empty:
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
      env.add(cow)
      inc cowsPlaced
      if cowsPlaced >= MapRoomObjectsCows:
        break
    inc herdId

  # Initialize assembler locations for all spawners
  var assemblerPositions: seq[IVec2] = @[]
  for thing in env.things:
    if thing.kind == assembler:
      assemblerPositions.add(thing.pos)

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
    oreReward: 0.1,        # Arena: ore mining reward
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
