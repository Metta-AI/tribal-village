## renderer_effects.nim - Visual effects and particle rendering
##
## Contains rendering for: shadows, smoke, projectiles, damage numbers,
## ragdolls, debris, spawn effects, sparkles, trails, ripples, impacts,
## conversions, and weather effects.

import
  boxy, pixie, vmath,
  common, environment

# Import sprite helper procs from renderer_core
import renderer_core

# ─── Constants ───────────────────────────────────────────────────────────────

const
  # Building smoke/chimney effect constants
  SmokeParticleCount = 3           # Number of smoke particles per building
  SmokeParticleScale = 1.0 / 500.0 # Smaller than sprites for wispy look
  SmokeBaseHeight = -0.4           # Start position above building center
  SmokeMaxHeight = 1.2             # How high particles rise
  SmokeAnimSpeed = 12              # Frames per animation cycle
  SmokeDriftAmount = 0.15          # Horizontal drift amplitude

  # Weather effect constants
  WeatherParticleDensity = 0.015   # Particles per tile (0.015 = ~1 particle per 67 tiles)
  WeatherParticleScale = 1.0 / 600.0  # Small particles for weather

  # Rain constants
  RainFallSpeed = 0.25'f32         # World units per frame (downward)
  RainDriftSpeed = 0.03'f32        # Slight horizontal drift
  RainCycleFrames = 48             # Frames for one full rain cycle
  RainAlpha = 0.5'f32              # Rain particle opacity
  RainStreakLength = 3             # Number of particles per streak

  # Wind constants
  WindBlowSpeed = 0.18'f32         # World units per frame (horizontal)
  WindDriftSpeed = 0.02'f32        # Vertical drift
  WindCycleFrames = 64             # Frames for one full wind cycle
  WindAlpha = 0.35'f32             # Wind particle opacity (subtle)

  # Damage number rendering constants
  DamageNumberFontPath = "data/Inter-Regular.ttf"
  DamageNumberFontSize: float32 = 28
  DamageNumberFloatHeight: float32 = 0.8  # World units to float upward

# ─── Damage Number Cache ─────────────────────────────────────────────────────

import tables

var
  damageNumberImages: Table[string, string] = initTable[string, string]()
  damageNumberSizes: Table[string, IVec2] = initTable[string, IVec2]()

template setupCtxFont(ctx: untyped, fontPath: string, fontSize: float32) =
  ctx.font = fontPath
  ctx.fontSize = fontSize
  ctx.textBaseline = TopBaseline

proc renderDamageNumberLabel(text: string, textColor: Color): (Image, IVec2) =
  ## Render a damage number label with outline for visibility.
  let fontSize = DamageNumberFontSize
  let padding = 2.0'f32
  var measureCtx = newContext(1, 1)
  setupCtxFont(measureCtx, DamageNumberFontPath, fontSize)
  let w = max(1, (measureCtx.measureText(text).width + padding * 2).int)
  let h = max(1, (fontSize + padding * 2).int)
  var ctx = newContext(w, h)
  setupCtxFont(ctx, DamageNumberFontPath, fontSize)
  # Draw outline for visibility
  ctx.fillStyle.color = color(0, 0, 0, 0.6)
  for dx in -1 .. 1:
    for dy in -1 .. 1:
      if dx != 0 or dy != 0:
        ctx.fillText(text, vec2(padding + dx.float32, padding + dy.float32))
  ctx.fillStyle.color = textColor
  ctx.fillText(text, vec2(padding, padding))
  result = (ctx.image, ivec2(w, h))

proc getDamageNumberLabel(amount: int, kind: DamageNumberKind): (string, IVec2) =
  ## Get or create a cached damage number label image.
  let prefix = case kind
    of DmgNumDamage: "d"
    of DmgNumHeal: "h"
    of DmgNumCritical: "c"
  let cacheKey = prefix & $amount
  if cacheKey in damageNumberImages:
    return (damageNumberImages[cacheKey], damageNumberSizes[cacheKey])
  # Create new label with appropriate color
  let textColor = case kind
    of DmgNumDamage: color(1.0, 0.3, 0.3, 1.0)    # Red
    of DmgNumHeal: color(0.3, 1.0, 0.3, 1.0)      # Green
    of DmgNumCritical: color(1.0, 0.8, 0.2, 1.0)  # Yellow/gold
  let text = $amount
  let (image, size) = renderDamageNumberLabel(text, textColor)
  let imageKey = "dmgnum_" & cacheKey
  bxy.addImage(imageKey, image)
  damageNumberImages[cacheKey] = imageKey
  damageNumberSizes[cacheKey] = size
  return (imageKey, size)

# ─── Projectile Constants ────────────────────────────────────────────────────

const
  ProjectileColors: array[ProjectileKind, Color] = [
    color(0.6, 0.4, 0.2, 1.0),     # ProjArrow - brown
    color(0.5, 0.3, 0.2, 1.0),     # ProjLongbow - darker brown
    color(0.9, 0.9, 0.3, 1.0),     # ProjJanissary - yellow
    color(0.6, 0.4, 0.2, 1.0),     # ProjTowerArrow - brown
    color(0.7, 0.5, 0.3, 1.0),     # ProjCastleArrow - tan
    color(0.4, 0.4, 0.4, 1.0),     # ProjMangonel - gray
    color(0.5, 0.5, 0.5, 1.0),     # ProjTrebuchet - dark gray
  ]

  ProjectileScales: array[ProjectileKind, float32] = [
    (1.0 / 400.0).float32,  # ProjArrow - small
    (1.0 / 380.0).float32,  # ProjLongbow - slightly larger
    (1.0 / 350.0).float32,  # ProjJanissary - medium
    (1.0 / 380.0).float32,  # ProjTowerArrow - small
    (1.0 / 350.0).float32,  # ProjCastleArrow - medium
    (1.0 / 280.0).float32,  # ProjMangonel - large
    (1.0 / 240.0).float32,  # ProjTrebuchet - very large
  ]

  ProjectileTrailPoints = 5     # Number of trail segments behind projectile
  ProjectileTrailStep = 0.12'f32  # Time step between trail points (fraction of lifetime)

# ─── Debris Constants ────────────────────────────────────────────────────────

const DebrisColors: array[DebrisKind, Color] = [
  color(0.55, 0.35, 0.15, 1.0),  # DebrisWood - brown
  color(0.50, 0.50, 0.50, 1.0),  # DebrisStone - gray
  color(0.70, 0.40, 0.25, 1.0),  # DebrisBrick - terracotta/orange-brown
]

# ─── Effect Drawing Procedures ───────────────────────────────────────────────

proc drawBuildingSmoke*(buildingPos: Vec2, buildingId: int) =
  ## Draw procedural smoke particles rising from an active building.
  ## Uses deterministic noise based on frame and building ID for consistent animation.
  for i in 0 ..< SmokeParticleCount:
    # Each particle has a unique phase offset based on building ID and particle index
    let phase = (buildingId * 7 + i * 13) mod 100
    let cycleFrame = (frame + phase * 3) mod (SmokeAnimSpeed * SmokeParticleCount)

    # Calculate particle's position in its rise cycle (0.0 to 1.0)
    let particleCycle = (cycleFrame + i * SmokeAnimSpeed) mod (SmokeAnimSpeed * SmokeParticleCount)
    let t = particleCycle.float32 / (SmokeAnimSpeed * SmokeParticleCount).float32

    # Vertical rise with slight acceleration at start
    let rise = t * t * SmokeMaxHeight

    # Horizontal drift using sine wave for gentle swaying
    let driftPhase = (frame.float32 * 0.05 + phase.float32 * 0.1 + i.float32 * 2.1)
    let drift = sin(driftPhase) * SmokeDriftAmount * t

    # Position particle above building
    let particlePos = buildingPos + vec2(drift, SmokeBaseHeight - rise)

    # Fade out as particle rises (full opacity at start, transparent at top)
    let alpha = (1.0 - t) * 0.6

    # Slight size variation based on rise (particles expand as they rise)
    let sizeScale = SmokeParticleScale * (1.0 + t * 0.5)

    # Gray-white smoke color with slight variation per particle
    let grayVal = 0.7 + (i.float32 * 0.1)
    let smokeTint = color(grayVal, grayVal, grayVal, alpha)

    bxy.drawImage("floor", particlePos, angle = 0, scale = sizeScale, tint = smokeTint)

proc drawProjectiles*() =
  ## Draw visual-only projectiles traveling from source to target.
  ## Renders a trail of fading points behind the projectile head.
  for proj in env.projectiles:
    if proj.lifetime <= 0:
      continue
    # Interpolate position: t=1 at source, t=0 at target
    let t = proj.countdown.float32 / proj.lifetime.float32
    let c = ProjectileColors[proj.kind]
    let sc = ProjectileScales[proj.kind]
    let srcX = proj.source.x.float32
    let srcY = proj.source.y.float32
    let tgtX = proj.target.x.float32
    let tgtY = proj.target.y.float32

    # Draw trail points (from back to front, oldest first)
    # Trail points represent past positions along the trajectory
    for i in countdown(ProjectileTrailPoints - 1, 0):
      let trailT = t + ProjectileTrailStep * (i + 1).float32
      # Skip trail points that would be beyond the source position
      if trailT > 1.0:
        continue
      let trailPos = vec2(
        srcX * trailT + tgtX * (1.0 - trailT),
        srcY * trailT + tgtY * (1.0 - trailT))
      # Fade opacity and shrink scale for older trail points
      let fadeRatio = 1.0 - (i + 1).float32 / (ProjectileTrailPoints + 1).float32
      let trailAlpha = c.a * fadeRatio * 0.7  # Max 70% opacity for trails
      let trailScale = sc * (0.5 + 0.5 * fadeRatio)  # Shrink to 50% at tail
      let trailColor = color(c.r, c.g, c.b, trailAlpha)
      bxy.drawImage("floor", trailPos, angle = 0, scale = trailScale, tint = trailColor)

    # Draw projectile head at current position
    let pos = vec2(srcX * t + tgtX * (1.0 - t), srcY * t + tgtY * (1.0 - t))
    bxy.drawImage("floor", pos, angle = 0, scale = sc, tint = c)

proc drawDamageNumbers*() =
  ## Draw floating damage numbers for combat feedback.
  ## Numbers float upward and fade out over their lifetime.
  if not currentViewport.valid:
    return
  for dmg in env.damageNumbers:
    if dmg.lifetime <= 0 or not isInViewport(dmg.pos):
      continue
    # Calculate progress (1.0 at spawn, 0.0 at expire)
    let t = dmg.countdown.float32 / dmg.lifetime.float32
    # Float upward as time progresses
    let floatOffset = (1.0 - t) * DamageNumberFloatHeight
    let worldPos = vec2(dmg.pos.x.float32, dmg.pos.y.float32 - floatOffset)
    # Fade out
    let alpha = t * t  # Quadratic ease for smoother fade
    let (imageKey, _) = getDamageNumberLabel(dmg.amount, dmg.kind)
    # Scale for world-space rendering (similar to HP bars)
    let scale = 1.0 / 200.0
    bxy.drawImage(imageKey, worldPos, angle = 0, scale = scale,
                  tint = color(1.0, 1.0, 1.0, alpha))

proc drawRagdolls*() =
  ## Draw ragdoll death bodies with physics-based tumbling.
  ## Bodies tumble away from damage source and fade out.
  if not currentViewport.valid:
    return
  for ragdoll in env.ragdolls:
    if ragdoll.lifetime <= 0:
      continue
    # Check viewport bounds using integer position
    let ipos = ivec2(ragdoll.pos.x.int32, ragdoll.pos.y.int32)
    if not isInViewport(ipos):
      continue
    # Get sprite key for the unit class
    let baseKey = UnitClassSpriteKeys[ragdoll.unitClass]
    # Fall back to villager sprites for villager-like units
    let spriteKey = if baseKey.len > 0 and baseKey & ".s" in bxy:
      baseKey & ".s"  # Use south-facing sprite as death pose
    elif "oriented/gatherer.s" in bxy:
      "oriented/gatherer.s"  # Fallback for villagers
    else:
      ""
    if spriteKey.len == 0:
      continue
    # Calculate alpha fade (quadratic ease for smoother fade)
    let t = ragdoll.countdown.float32 / ragdoll.lifetime.float32
    let alpha = t * t
    # Get team color with alpha applied
    let teamColor = getTeamColor(env, ragdoll.teamId)
    let tint = color(teamColor.r, teamColor.g, teamColor.b, alpha)
    # Draw with rotation
    bxy.drawImage(spriteKey, ragdoll.pos, angle = ragdoll.angle, scale = SpriteScale, tint = tint)

proc drawDebris*() =
  ## Draw debris particles from destroyed buildings.
  ## Particles move outward and fade out over their lifetime.
  if not currentViewport.valid:
    return
  for deb in env.debris:
    if deb.lifetime <= 0:
      continue
    # Check viewport bounds (convert float pos to int for check)
    let ipos = ivec2(deb.pos.x.int32, deb.pos.y.int32)
    if not isInViewport(ipos):
      continue
    # Calculate progress (1.0 at spawn, 0.0 at expire)
    let t = deb.countdown.float32 / deb.lifetime.float32
    # Fade out
    let alpha = t * t  # Quadratic ease for smoother fade
    let baseColor = DebrisColors[deb.kind]
    let tintColor = color(baseColor.r, baseColor.g, baseColor.b, alpha)
    # Draw as small colored dot using floor sprite
    let scale = (1.0 / 350.0).float32  # Slightly smaller than projectiles
    bxy.drawImage("floor", deb.pos, angle = 0, scale = scale, tint = tintColor)

proc drawSpawnEffects*() =
  ## Draw visual effects for unit spawning from buildings.
  ## Shows an expanding, fading glow at the spawn location.
  if not currentViewport.valid:
    return
  for effect in env.spawnEffects:
    if effect.lifetime <= 0 or not isInViewport(effect.pos):
      continue
    # Calculate progress (1.0 at spawn, 0.0 at expire)
    let t = effect.countdown.float32 / effect.lifetime.float32
    let progress = 1.0 - t  # 0.0 at spawn, 1.0 at expire
    # Expand from small to large as effect progresses
    let baseScale = SpriteScale * (0.3 + progress * 0.7)  # 30% to 100%
    # Fade out with quadratic ease (bright at start, fades smoothly)
    let alpha = t * t * 0.6  # Max alpha 0.6 to not be too bright
    # Use a bright cyan/white tint for spawn effect
    let tint = color(0.6, 0.9, 1.0, alpha)
    bxy.drawImage("floor", effect.pos.vec2, angle = 0, scale = baseScale, tint = tint)

proc drawGatherSparkles*() =
  ## Draw sparkle particles when workers collect resources.
  ## Golden particles burst outward and fade out over their lifetime.
  if not currentViewport.valid:
    return
  for sparkle in env.gatherSparkles:
    if sparkle.lifetime <= 0:
      continue
    # Check viewport bounds (convert float pos to int for check)
    let ipos = ivec2(sparkle.pos.x.int32, sparkle.pos.y.int32)
    if not isInViewport(ipos):
      continue
    # Calculate progress (1.0 at spawn, 0.0 at expire)
    let t = sparkle.countdown.float32 / sparkle.lifetime.float32
    # Fade out with quadratic ease
    let alpha = t * t * 0.8
    # Golden sparkle color
    let tintColor = color(1.0, 0.85, 0.3, alpha)
    # Small particles
    let scale = (1.0 / 450.0).float32 * (0.5 + t * 0.5)
    bxy.drawImage("floor", sparkle.pos, angle = 0, scale = scale, tint = tintColor)

proc drawConstructionDust*() =
  ## Draw dust particles at construction sites.
  ## Brown/tan particles rise and spread out as they fade.
  if not currentViewport.valid:
    return
  for dust in env.constructionDust:
    if dust.lifetime <= 0:
      continue
    # Check viewport bounds
    let ipos = ivec2(dust.pos.x.int32, dust.pos.y.int32)
    if not isInViewport(ipos):
      continue
    # Calculate progress
    let t = dust.countdown.float32 / dust.lifetime.float32
    # Fade out
    let alpha = t * t * 0.5
    # Dusty brown color
    let tintColor = color(0.7, 0.6, 0.4, alpha)
    # Particles that grow slightly as they rise
    let scale = (1.0 / 400.0).float32 * (0.7 + (1.0 - t) * 0.3)
    bxy.drawImage("floor", dust.pos, angle = 0, scale = scale, tint = tintColor)

proc drawUnitTrails*() =
  ## Draw movement trails behind fast-moving units.
  ## Fading afterimages showing recent movement path.
  if not currentViewport.valid:
    return
  for trail in env.unitTrails:
    if trail.lifetime <= 0:
      continue
    # Check viewport bounds
    let ipos = ivec2(trail.pos.x.int32, trail.pos.y.int32)
    if not isInViewport(ipos):
      continue
    # Calculate progress
    let t = trail.countdown.float32 / trail.lifetime.float32
    # Fade out quickly
    let alpha = t * t * 0.4
    # Light team-colored trail
    let teamColor = getTeamColor(env, trail.teamId)
    let tintColor = color(teamColor.r, teamColor.g, teamColor.b, alpha)
    # Small trail dots
    let scale = (1.0 / 500.0).float32
    bxy.drawImage("floor", trail.pos, angle = 0, scale = scale, tint = tintColor)

proc drawDustParticles*() =
  ## Draw dust particles kicked up by walking units.
  ## Color varies based on terrain type.
  if not currentViewport.valid:
    return
  for dust in env.dustParticles:
    if dust.lifetime <= 0:
      continue
    # Check viewport bounds
    let ipos = ivec2(dust.pos.x.int32, dust.pos.y.int32)
    if not isInViewport(ipos):
      continue
    # Calculate progress (1.0 at spawn, 0.0 at expire)
    let t = dust.countdown.float32 / dust.lifetime.float32
    # Fade out with quadratic ease
    let alpha = t * t * 0.6
    # Color based on terrain type
    let tintColor = case dust.terrainColor
      of 0: color(0.85, 0.75, 0.55, alpha)  # Sand/Dune - tan
      of 1: color(0.95, 0.95, 1.0, alpha)   # Snow - white
      of 2: color(0.45, 0.35, 0.25, alpha)  # Mud - dark brown
      of 3: color(0.6, 0.55, 0.4, alpha)    # Grass/Fertile - green-brown
      of 4: color(0.5, 0.5, 0.5, alpha)     # Road - gray
      else: color(0.7, 0.6, 0.4, alpha)     # Default tan
    # Small particles that shrink slightly as they fade
    let scale = (1.0 / 600.0).float32 * (0.5 + t * 0.5)
    bxy.drawImage("floor", dust.pos, angle = 0, scale = scale, tint = tintColor)

proc drawWaterRipples*() =
  ## Draw ripple effects when units walk through water.
  ## Expanding rings that fade out over their lifetime.
  if not currentViewport.valid:
    return
  for ripple in env.waterRipples:
    if ripple.lifetime <= 0:
      continue
    # Check viewport bounds (convert float pos to int for check)
    let ipos = ivec2(ripple.pos.x.int32, ripple.pos.y.int32)
    if not isInViewport(ipos):
      continue
    # Calculate progress (1.0 at spawn, 0.0 at expire)
    let t = ripple.countdown.float32 / ripple.lifetime.float32
    let progress = 1.0 - t  # 0.0 at spawn, 1.0 at expire
    # Expand from small to large as effect progresses
    let baseScale = SpriteScale * (0.2 + progress * 0.8)  # 20% to 100%
    # Fade out with quadratic ease (visible at start, fades smoothly)
    let alpha = t * t * 0.5  # Max alpha 0.5 for subtle effect
    # Use a light cyan/blue tint for water ripple
    let tint = color(0.5, 0.7, 0.9, alpha)
    bxy.drawImage("floor", ripple.pos, angle = 0, scale = baseScale, tint = tint)

proc drawAttackImpacts*() =
  ## Draw attack impact burst particles when attacks hit targets.
  ## Particles radiate outward and fade quickly for a sharp impact effect.
  if not currentViewport.valid:
    return
  for impact in env.attackImpacts:
    if impact.lifetime <= 0:
      continue
    # Check viewport bounds (convert float pos to int for check)
    let ipos = ivec2(impact.pos.x.int32, impact.pos.y.int32)
    if not isInViewport(ipos):
      continue
    # Calculate progress (1.0 at spawn, 0.0 at expire)
    let t = impact.countdown.float32 / impact.lifetime.float32
    # Fade out quickly with quadratic ease for punchy effect
    let alpha = t * t * 0.9
    # Orange/red impact color for combat feedback
    let tintColor = color(1.0, 0.5, 0.2, alpha)
    # Small particles that shrink as they fade
    let scale = (1.0 / 400.0).float32 * (0.3 + t * 0.7)  # 30% to 100%
    bxy.drawImage("floor", impact.pos, angle = 0, scale = scale, tint = tintColor)

proc drawConversionEffects*() =
  ## Draw pulsing glow effects when monks convert enemy units.
  ## Displays as a golden/team-colored radial glow that pulses and fades.
  if not currentViewport.valid:
    return
  for effect in env.conversionEffects:
    if effect.lifetime <= 0:
      continue
    # Check viewport bounds
    let ipos = ivec2(effect.pos.x.int32, effect.pos.y.int32)
    if not isInViewport(ipos):
      continue
    # Calculate progress (1.0 at spawn, 0.0 at expire)
    let t = effect.countdown.float32 / effect.lifetime.float32
    # Pulsing effect: sine wave for divine/spiritual feel (2 pulses over lifetime)
    let pulse = (sin(t * 6.28318 * 2.0) + 1.0) * 0.5  # 0 to 1
    # Fade out over time with pulsing intensity
    let alpha = t * (0.5 + pulse * 0.5)
    # Blend between golden divine color and team color
    let golden = color(0.95, 0.85, 0.35, alpha)
    let teamAlpha = effect.teamColor
    let blendT = 1.0 - t  # More team color as time progresses
    let tintColor = color(
      golden.r * (1.0 - blendT) + teamAlpha.r * blendT,
      golden.g * (1.0 - blendT) + teamAlpha.g * blendT,
      golden.b * (1.0 - blendT) + teamAlpha.b * blendT,
      alpha * 0.8)
    # Draw expanding ring effect
    let baseScale = (1.0 / 400.0).float32
    let expandScale = baseScale * (1.0 + (1.0 - t) * 1.5)  # Expands as it fades
    bxy.drawImage("floor", effect.pos, angle = 0, scale = expandScale, tint = tintColor)

proc drawWeatherEffects*() =
  ## Draw ambient weather effects (rain or wind particles) across the viewport.
  ## Uses deterministic animation based on frame counter for consistent effects.
  if not currentViewport.valid or settings.weatherType == WeatherNone:
    return

  let viewWidth = currentViewport.maxX - currentViewport.minX + 1
  let viewHeight = currentViewport.maxY - currentViewport.minY + 1
  let viewArea = viewWidth * viewHeight

  # Calculate number of particles based on viewport size
  let particleCount = max(10, int(viewArea.float32 * WeatherParticleDensity))

  case settings.weatherType
  of WeatherRain:
    # Rain particles falling diagonally with slight drift
    for i in 0 ..< particleCount:
      # Use deterministic positioning based on particle index and frame
      let seed = i * 17 + 31
      let cycleOffset = (seed * 7) mod RainCycleFrames
      let cycleFrame = (frame + cycleOffset) mod RainCycleFrames
      let t = cycleFrame.float32 / RainCycleFrames.float32

      # Horizontal position: spread across viewport with some variation
      let xBase = currentViewport.minX.float32 +
                  ((seed * 13) mod (viewWidth * 100)).float32 / 100.0
      let xDrift = t * RainDriftSpeed * RainCycleFrames.float32

      # Vertical position: cycle from top to bottom of viewport
      let yBase = currentViewport.minY.float32 - 2.0  # Start above viewport
      let yFall = t * RainFallSpeed * RainCycleFrames.float32

      let particlePos = vec2(xBase + xDrift, yBase + yFall)

      # Skip if outside viewport (with margin)
      if particlePos.y < currentViewport.minY.float32 - 1.0 or
         particlePos.y > currentViewport.maxY.float32 + 1.0:
        continue

      # Rain color: light blue-white with some variation
      let blueVal = 0.7 + ((seed * 3) mod 30).float32 / 100.0
      let rainTint = color(0.8, 0.85, blueVal, RainAlpha)

      # Draw rain streak (multiple particles in a line)
      for s in 0 ..< RainStreakLength:
        let streakOffset = vec2(
          -RainDriftSpeed * s.float32 * 2.0,
          -RainFallSpeed * s.float32 * 2.0
        )
        let streakAlpha = RainAlpha * (1.0 - s.float32 / RainStreakLength.float32)
        let streakTint = color(rainTint.r, rainTint.g, rainTint.b, streakAlpha)
        bxy.drawImage("floor", particlePos + streakOffset, angle = 0,
                      scale = WeatherParticleScale, tint = streakTint)

  of WeatherWind:
    # Wind particles blowing horizontally with slight vertical drift
    for i in 0 ..< particleCount:
      let seed = i * 23 + 47
      let cycleOffset = (seed * 11) mod WindCycleFrames
      let cycleFrame = (frame + cycleOffset) mod WindCycleFrames
      let t = cycleFrame.float32 / WindCycleFrames.float32

      # Vertical position: spread across viewport
      let yBase = currentViewport.minY.float32 +
                  ((seed * 19) mod (viewHeight * 100)).float32 / 100.0
      let yDrift = sin(t * 3.14159 * 2.0) * WindDriftSpeed * 4.0

      # Horizontal position: cycle from left to right of viewport
      let xBase = currentViewport.minX.float32 - 2.0  # Start left of viewport
      let xBlow = t * WindBlowSpeed * WindCycleFrames.float32

      let particlePos = vec2(xBase + xBlow, yBase + yDrift)

      # Skip if outside viewport
      if particlePos.x < currentViewport.minX.float32 - 1.0 or
         particlePos.x > currentViewport.maxX.float32 + 1.0:
        continue

      # Wind color: gray-white with variation
      let grayVal = 0.7 + ((seed * 5) mod 20).float32 / 100.0
      let windTint = color(grayVal, grayVal, grayVal, WindAlpha)

      bxy.drawImage("floor", particlePos, angle = 0,
                    scale = WeatherParticleScale, tint = windTint)

  of WeatherNone:
    discard  # No weather effects
