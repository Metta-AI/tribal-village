proc clearTintModifications(env: Environment) =
  ## Clear only active tile modifications for performance
  for pos in env.activeTiles.positions:
    let tileX = pos.x.int
    let tileY = pos.y.int
    if tileX >= 0 and tileX < MapWidth and tileY >= 0 and tileY < MapHeight:
      env.tintMods[tileX][tileY] = TintModification(r: 0, g: 0, b: 0)
      env.activeTiles.flags[tileX][tileY] = false

  # Clear the active list for next frame
  env.activeTiles.positions.setLen(0)

proc updateTintModifications(env: Environment) =
  ## Update unified tint modification array based on entity positions - runs every frame
  # Clear previous frame's modifications
  env.clearTintModifications()

  template markActiveTile(tileX, tileY: int) =
    if tileX >= 0 and tileX < MapWidth and tileY >= 0 and tileY < MapHeight:
      if not env.activeTiles.flags[tileX][tileY]:
        env.activeTiles.flags[tileX][tileY] = true
        env.activeTiles.positions.add(ivec2(tileX, tileY))

  # Helper: add team tint in a radius with simple Manhattan falloff
  proc addTintArea(baseX, baseY: int, color: Color, radius: int, scale: int) =
    let minX = max(0, baseX - radius)
    let maxX = min(MapWidth - 1, baseX + radius)
    let minY = max(0, baseY - radius)
    let maxY = min(MapHeight - 1, baseY + radius)
    let colorR = color.r - 0.7
    let colorG = color.g - 0.65
    let colorB = color.b - 0.6
    for tileX in minX .. maxX:
      let dx = tileX - baseX
      for tileY in minY .. maxY:
        let dy = tileY - baseY
        let dist = abs(dx) + abs(dy)
        let falloff = max(1, radius * 2 + 1 - dist)
        markActiveTile(tileX, tileY)
        let strength = scale.float32 * falloff.float32
        safeTintAdd(env.tintMods[tileX][tileY].r, int(colorR * strength))
        safeTintAdd(env.tintMods[tileX][tileY].g, int(colorG * strength))
        safeTintAdd(env.tintMods[tileX][tileY].b, int(colorB * strength))

  # Process all entities and mark their affected positions as active
  for thing in env.things:
    let pos = thing.pos
    if pos.x < 0 or pos.x >= MapWidth or pos.y < 0 or pos.y >= MapHeight:
      continue
    let baseX = pos.x.int
    let baseY = pos.y.int

    case thing.kind
    of Tumor:
      # Tumors create creep spread in 5x5 area (active seeds glow brighter)
      let creepIntensity = if thing.hasClaimedTerritory: 2 else: 1

      let minX = max(0, baseX - 2)
      let maxX = min(MapWidth - 1, baseX + 2)
      let minY = max(0, baseY - 2)
      let maxY = min(MapHeight - 1, baseY + 2)
      for tileX in minX .. maxX:
        let dx = tileX - baseX
        for tileY in minY .. maxY:
          let dy = tileY - baseY
          # Distance-based falloff for more organic look
          let manDist = abs(dx) + abs(dy)  # Manhattan distance
          let falloff = max(1, 5 - manDist)  # Stronger at center, weaker at edges (5x5 grid)
          markActiveTile(tileX, tileY)

          # Tumor creep effect with overflow protection
          safeTintAdd(env.tintMods[tileX][tileY].r, -15 * creepIntensity * falloff)
          safeTintAdd(env.tintMods[tileX][tileY].g, -8 * creepIntensity * falloff)
          safeTintAdd(env.tintMods[tileX][tileY].b, 20 * creepIntensity * falloff)

    of Agent:
      let tribeId = thing.agentId
      if tribeId < agentVillageColors.len:
        addTintArea(baseX, baseY, agentVillageColors[tribeId], radius = 2, scale = 90)

    of Lantern:
      if thing.lanternHealthy and thing.teamId >= 0 and thing.teamId < teamColors.len:
        addTintArea(baseX, baseY, teamColors[thing.teamId], radius = 2, scale = 60)

    else:
      discard

proc applyTintModifications(env: Environment) =
  ## Apply tint modifications to entity positions and their surrounding areas

  # Apply modifications only to tiles touched this frame
  for pos in env.activeTiles.positions:
    let tileX = pos.x.int
    let tileY = pos.y.int
    if tileX < 0 or tileX >= MapWidth or tileY < 0 or tileY >= MapHeight:
      continue

    # Skip if tint modifications are below minimum threshold
    let tint = env.tintMods[tileX][tileY]
    if abs(tint.r) < MinTintEpsilon and abs(tint.g) < MinTintEpsilon and abs(tint.b) < MinTintEpsilon:
      continue

    # Skip tinting on water tiles (rivers should remain clean)
    if env.terrain[tileX][tileY] == Water:
      continue

    # Get current color as integers (scaled by 1000 for precision)
    var r = int(env.tileColors[tileX][tileY].r * 1000)
    var g = int(env.tileColors[tileX][tileY].g * 1000)
    var b = int(env.tileColors[tileX][tileY].b * 1000)

    # Apply unified tint modifications
    r += tint.r div 10  # 10% of the modification
    g += tint.g div 10
    b += tint.b div 10

    # Convert back to float with clamping
    env.tileColors[tileX][tileY].r = min(max(r.float32 / 1000.0, 0.3), 1.2)
    env.tileColors[tileX][tileY].g = min(max(g.float32 / 1000.0, 0.3), 1.2)
    env.tileColors[tileX][tileY].b = min(max(b.float32 / 1000.0, 0.3), 1.2)

  # Apply global decay to ALL tiles (but infrequently for performance)
  if env.currentStep mod 30 == 0 and env.currentStep > 0:
    let decay = 0.98'f32  # 2% decay every 30 steps

    for x in 0 ..< MapWidth:
      for y in 0 ..< MapHeight:
        # Get the base color for this tile (could be team color for houses)
        let baseR = env.baseTileColors[x][y].r
        let baseG = env.baseTileColors[x][y].g
        let baseB = env.baseTileColors[x][y].b

        # Only decay if color differs from base (avoid floating point errors)
        # Lowered threshold to allow subtle creep effects to be balanced by decay
        if abs(env.tileColors[x][y].r - baseR) > 0.001 or
           abs(env.tileColors[x][y].g - baseG) > 0.001 or
           abs(env.tileColors[x][y].b - baseB) > 0.001:
          env.tileColors[x][y].r = env.tileColors[x][y].r * decay + baseR * (1.0 - decay)
          env.tileColors[x][y].g = env.tileColors[x][y].g * decay + baseG * (1.0 - decay)
          env.tileColors[x][y].b = env.tileColors[x][y].b * decay + baseB * (1.0 - decay)

        # Also decay intensity back to base intensity
        let baseIntensity = env.baseTileColors[x][y].intensity
        if abs(env.tileColors[x][y].intensity - baseIntensity) > 0.01:
          env.tileColors[x][y].intensity = env.tileColors[x][y].intensity * decay + baseIntensity * (1.0 - decay)
