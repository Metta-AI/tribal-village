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

proc applyActionTint(env: Environment, pos: IVec2, tintColor: TileColor, duration: int8, tintCode: uint8) =
  if not isValidPos(pos):
    return
  if env.tintLocked[pos.x][pos.y]:
    return
  env.actionTintColor[pos.x][pos.y] = tintColor
  env.actionTintCountdown[pos.x][pos.y] = duration
  let existing = env.actionTintCode[pos.x][pos.y]
  let nextCode =
    if existing == ActionTintNone or existing == tintCode: tintCode else: ActionTintMixed
  env.actionTintCode[pos.x][pos.y] = nextCode
  # Keep observation tint layer in sync so agents can “see” recent combat actions
  env.updateObservations(TintLayer, pos, nextCode.int)
  if not env.actionTintFlags[pos.x][pos.y]:
    env.actionTintFlags[pos.x][pos.y] = true
    env.actionTintPositions.add(pos)

proc combinedTileTint*(env: Environment, x, y: int): TileColor =
  let base = env.baseTintColors[x][y]
  if env.tintLocked[x][y]:
    return base
  let overlay = env.computedTintColors[x][y]
  let alpha = max(0.0'f32, min(1.0'f32, overlay.intensity))
  let invAlpha = 1.0'f32 - alpha
  TileColor(
    r: base.r * invAlpha + overlay.r * alpha,
    g: base.g * invAlpha + overlay.g * alpha,
    b: base.b * invAlpha + overlay.b * alpha,
    intensity: base.intensity + (1.0'f32 - base.intensity) * alpha
  )

proc isTileFrozen*(pos: IVec2, env: Environment): bool =
  if not isValidPos(pos):
    return false
  let color = combinedTileTint(env, pos.x, pos.y)
  return abs(color.r - ClippyTint.r) <= ClippyTintTolerance and
    abs(color.g - ClippyTint.g) <= ClippyTintTolerance and
    abs(color.b - ClippyTint.b) <= ClippyTintTolerance

proc isThingFrozen*(thing: Thing, env: Environment): bool =
  ## Anything explicitly frozen or sitting on a frozen tile counts as non-interactable.
  thing.frozen > 0 or isTileFrozen(thing.pos, env)

proc biomeBaseColor*(biome: BiomeType): TileColor =
  case biome:
  of BiomeBaseType: BaseTileColorDefault
  of BiomeForestType: BiomeColorForest
  of BiomeDesertType: BiomeColorDesert
  of BiomeCavesType: BiomeColorCaves
  of BiomeCityType: BiomeColorCity
  of BiomePlainsType: BiomeColorPlains
  of BiomeSnowType: BiomeColorSnow
  of BiomeSwampType: BiomeColorSwamp
  of BiomeDungeonType: BiomeColorDungeon
  else: BaseTileColorDefault

proc applyBiomeBaseColors*(env: Environment) =
  var colors: array[MapWidth, array[MapHeight, TileColor]]
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      let baseBiome = env.biomes[x][y]
      var color = biomeBaseColor(baseBiome)
      if BiomeEdgeBlendRadius > 0 and baseBiome != BiomeNone:
        var minDist = BiomeEdgeBlendRadius + 1
        var sumR = 0.0'f32
        var sumG = 0.0'f32
        var sumB = 0.0'f32
        var sumI = 0.0'f32
        var count = 0

        for dx in -BiomeEdgeBlendRadius .. BiomeEdgeBlendRadius:
          let nx = x + dx
          if nx < 0 or nx >= MapWidth:
            continue
          for dy in -BiomeEdgeBlendRadius .. BiomeEdgeBlendRadius:
            if dx == 0 and dy == 0:
              continue
            let ny = y + dy
            if ny < 0 or ny >= MapHeight:
              continue
            let dist = max(abs(dx), abs(dy))
            if dist > BiomeEdgeBlendRadius:
              continue
            let otherBiome = env.biomes[nx][ny]
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

        if count > 0 and minDist <= BiomeEdgeBlendRadius:
          let invCount = 1.0'f32 / count.float32
          let neighborColor = TileColor(
            r: sumR * invCount,
            g: sumG * invCount,
            b: sumB * invCount,
            intensity: sumI * invCount
          )

          let raw = 1.0'f32 - (float32(minDist - 1) / float32(BiomeEdgeBlendRadius))
          let clamped = max(0.0'f32, min(1.0'f32, raw))
          let easeT = clamped * clamped * (3.0'f32 - 2.0'f32 * clamped)
          let invT = 1.0'f32 - easeT
          color = TileColor(
            r: color.r * invT + neighborColor.r * easeT,
            g: color.g * invT + neighborColor.g * easeT,
            b: color.b * invT + neighborColor.b * easeT,
            intensity: color.intensity * invT + neighborColor.intensity * easeT
          )
      colors[x][y] = color

  if BiomeBlendPasses > 0:
    var temp: array[MapWidth, array[MapHeight, TileColor]]
    let centerWeight = 1.0'f32
    let neighborWeight = BiomeBlendNeighborWeight
    for _ in 0 ..< BiomeBlendPasses:
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
              let neighborColor = colors[nx][ny]
              sumR += neighborColor.r * neighborWeight
              sumG += neighborColor.g * neighborWeight
              sumB += neighborColor.b * neighborWeight
              sumI += neighborColor.intensity * neighborWeight
              total += neighborWeight
          temp[x][y] = TileColor(
            r: sumR / total,
            g: sumG / total,
            b: sumB / total,
            intensity: sumI / total
          )
      colors = temp

  env.baseTintColors = colors
