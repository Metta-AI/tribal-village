const WarmVillagePalette* = [
  # Eight bright, evenly spaced tints (similar brightness, varied hue; away from clippy purple)
  color(0.910, 0.420, 0.420, 1.0),  # team 0: soft red        (#e86b6b)
  color(0.940, 0.650, 0.420, 1.0),  # team 1: soft orange     (#f0a86b)
  color(0.940, 0.820, 0.420, 1.0),  # team 2: soft yellow     (#f0d56b)
  color(0.600, 0.840, 0.500, 1.0),  # team 3: soft olive-lime (#99d680)
  color(0.780, 0.380, 0.880, 1.0),  # team 4: warm magenta    (#c763e0)
  color(0.420, 0.720, 0.940, 1.0),  # team 5: soft sky        (#6ab8f0)
  color(0.870, 0.870, 0.870, 1.0),  # team 6: light gray      (#dedede)
  color(0.930, 0.560, 0.820, 1.0)   # team 7: soft pink       (#ed8fd1)
]

# Combat tint helpers (inlined from combat.nim)
proc applyActionTint(env: Environment, pos: IVec2, tintColor: TileColor, duration: int8, tintCode: uint8) =
  if pos.x < 0 or pos.x >= MapWidth or pos.y < 0 or pos.y >= MapHeight:
    return
  env.actionTintColor[pos.x][pos.y] = tintColor
  env.actionTintCountdown[pos.x][pos.y] = duration
  # Keep observation tint layer in sync so agents can “see” recent combat actions
  env.updateObservations(TintLayer, pos, tintCode.int)
  if not env.actionTintFlags[pos.x][pos.y]:
    env.actionTintFlags[pos.x][pos.y] = true
    env.actionTintPositions.add(pos)

# Utility to tick a building cooldown.
proc tickCooldown(env: Environment, thing: Thing) =
  if thing.cooldown > 0:
    dec thing.cooldown

proc combinedTileTint*(env: Environment, x, y: int): TileColor =
  let base = env.baseTintColors[x][y]
  let overlay = env.computedTintColors[x][y]
  let alpha = max(0.0'f32, min(1.0'f32, overlay.intensity))
  let r = base.r * (1.0 - alpha) + overlay.r * alpha
  let g = base.g * (1.0 - alpha) + overlay.g * alpha
  let b = base.b * (1.0 - alpha) + overlay.b * alpha
  let intensity = base.intensity + (1.0'f32 - base.intensity) * alpha
  TileColor(r: r, g: g, b: b, intensity: intensity)

proc isTileFrozen*(pos: IVec2, env: Environment): bool =
  if pos.x < 0 or pos.x >= MapWidth or pos.y < 0 or pos.y >= MapHeight:
    return false
  let color = combinedTileTint(env, pos.x, pos.y)
  return abs(color.r - ClippyTint.r) <= ClippyTintTolerance and
    abs(color.g - ClippyTint.g) <= ClippyTintTolerance and
    abs(color.b - ClippyTint.b) <= ClippyTintTolerance

proc isThingFrozen*(thing: Thing, env: Environment): bool =
  ## Anything explicitly frozen or sitting on a frozen tile counts as non-interactable.
  if thing.frozen > 0:
    return true
  return isTileFrozen(thing.pos, env)

proc biomeBaseColor*(biome: BiomeType): TileColor =
  case biome:
  of BiomeBaseType: BaseTileColorDefault
  of BiomeForestType: BiomeColorForest
  of BiomeDesertType: BiomeColorDesert
  of BiomeCavesType: BiomeColorCaves
  of BiomeCityType: BiomeColorCity
  of BiomePlainsType: BiomeColorPlains
  of BiomeSnowType: BiomeColorSnow
  of BiomeDungeonType: BiomeColorDungeon
  else: BaseTileColorDefault

proc blendTileColor(a, b: TileColor, t: float32): TileColor =
  let tClamped = max(0.0'f32, min(1.0'f32, t))
  TileColor(
    r: a.r * (1.0 - tClamped) + b.r * tClamped,
    g: a.g * (1.0 - tClamped) + b.g * tClamped,
    b: a.b * (1.0 - tClamped) + b.b * tClamped,
    intensity: a.intensity * (1.0 - tClamped) + b.intensity * tClamped
  )

proc biomeEdgeBlendColor(biomes: BiomeGrid, x, y: int, radius: int): TileColor =
  let baseBiome = biomes[x][y]
  let baseColor = biomeBaseColor(baseBiome)
  if radius <= 0 or baseBiome == BiomeNone:
    return baseColor

  var minDist = radius + 1
  var sumR = 0.0'f32
  var sumG = 0.0'f32
  var sumB = 0.0'f32
  var sumI = 0.0'f32
  var count = 0

  for dx in -radius .. radius:
    let nx = x + dx
    if nx < 0 or nx >= MapWidth:
      continue
    for dy in -radius .. radius:
      if dx == 0 and dy == 0:
        continue
      let ny = y + dy
      if ny < 0 or ny >= MapHeight:
        continue
      let dist = max(abs(dx), abs(dy))
      if dist > radius:
        continue
      let otherBiome = biomes[nx][ny]
      if otherBiome == baseBiome or otherBiome == BiomeNone:
        continue
      let otherColor = biomeBaseColor(otherBiome)
      if dist < minDist:
        minDist = dist
        sumR = otherColor.r
        sumG = otherColor.g
        sumB = otherColor.b
        sumI = otherColor.intensity
        count = 1
      elif dist == minDist:
        sumR += otherColor.r
        sumG += otherColor.g
        sumB += otherColor.b
        sumI += otherColor.intensity
        inc count

  if count == 0 or minDist > radius:
    return baseColor

  let invCount = 1.0'f32 / count.float32
  let neighborColor = TileColor(
    r: sumR * invCount,
    g: sumG * invCount,
    b: sumB * invCount,
    intensity: sumI * invCount
  )

  let raw = 1.0'f32 - (float32(minDist - 1) / float32(radius))
  let clamped = max(0.0'f32, min(1.0'f32, raw))
  let t = clamped * clamped * (3.0'f32 - 2.0'f32 * clamped)
  blendTileColor(baseColor, neighborColor, t)

proc smoothBaseColors(colors: var array[MapWidth, array[MapHeight, TileColor]], passes: int) =
  if passes <= 0:
    return
  var temp: array[MapWidth, array[MapHeight, TileColor]]
  let centerWeight = 1.0'f32
  let neighborWeight = BiomeBlendNeighborWeight
  for _ in 0 ..< passes:
    for x in 0 ..< MapWidth:
      for y in 0 ..< MapHeight:
        var sumR = colors[x][y].r * centerWeight
        var sumG = colors[x][y].g * centerWeight
        var sumB = colors[x][y].b * centerWeight
        var sumI = colors[x][y].intensity * centerWeight
        var total = centerWeight
        for dx in -1 .. 1:
          for dy in -1 .. 1:
            if dx == 0 and dy == 0:
              continue
            let nx = x + dx
            let ny = y + dy
            if nx < 0 or nx >= MapWidth or ny < 0 or ny >= MapHeight:
              continue
            let c = colors[nx][ny]
            sumR += c.r * neighborWeight
            sumG += c.g * neighborWeight
            sumB += c.b * neighborWeight
            sumI += c.intensity * neighborWeight
            total += neighborWeight
        temp[x][y] = TileColor(
          r: sumR / total,
          g: sumG / total,
          b: sumB / total,
          intensity: sumI / total
        )
    colors = temp

proc applyBiomeBaseColors*(env: Environment) =
  var colors: array[MapWidth, array[MapHeight, TileColor]]
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      var color = biomeEdgeBlendColor(env.biomes, x, y, BiomeEdgeBlendRadius)
      colors[x][y] = color
  smoothBaseColors(colors, BiomeBlendPasses)
  env.baseTintColors = colors


# ============== COLOR MANAGEMENT ==============

proc generateEntityColor*(entityType: string, id: int, fallbackColor: Color = color(0.5, 0.5, 0.5, 1.0)): Color =
  ## Unified color generation for all entity types
  ## Uses deterministic palette indexing; no random sampling.
  ## Uses Environment fields for color storage.
  case entityType:
  of "agent":
    return env.agentColors[id]
  of "village":
    return env.teamColors[id]
  else:
    return fallbackColor

proc getAltarColor*(pos: IVec2): Color =
  ## Get altar color by position, with white fallback.
  ## Falls back to the base tile color so altars start visibly tinted even
  ## before any dynamic color updates run.
  ## Uses Environment fields for color storage.
  if env.altarColors.hasKey(pos):
    return env.altarColors[pos]

  if pos.x >= 0 and pos.x < MapWidth and pos.y >= 0 and pos.y < MapHeight:
    let base = env.baseTintColors[pos.x][pos.y]
    return color(base.r, base.g, base.b, 1.0)

  color(1.0, 1.0, 1.0, 1.0)
