## environment_grid.nim - Spatial grid operations for Environment
##
## This module contains grid/position queries, terrain checks, and placement validation.
## These are low-level utilities for querying and manipulating the game grid.

import vmath
import types, registry, terrain

export types

# ============================================================================
# Basic grid queries
# ============================================================================

{.push inline.}

proc getThing*(env: Environment, pos: IVec2): Thing =
  ## Get the blocking thing at a position, or nil if empty/invalid.
  if not isValidPos(pos): nil else: env.grid[pos.x][pos.y]

proc getBackgroundThing*(env: Environment, pos: IVec2): Thing =
  ## Get the background thing at a position (doors, roads), or nil if empty/invalid.
  if not isValidPos(pos): nil else: env.backgroundGrid[pos.x][pos.y]

proc isEmpty*(env: Environment, pos: IVec2): bool =
  ## True when no blocking unit occupies the tile.
  isValidPos(pos) and isNil(env.grid[pos.x][pos.y])

proc hasDoor*(env: Environment, pos: IVec2): bool =
  ## Check if there is a door at the position.
  let door = env.getBackgroundThing(pos)
  not isNil(door) and door.kind == Door

proc canAgentPassDoor*(env: Environment, agent: Thing, pos: IVec2): bool =
  ## Check if an agent can pass through a door at the position.
  ## Agents can pass their own team's doors.
  let door = env.getBackgroundThing(pos)
  isNil(door) or door.kind != Door or door.teamId == getTeamId(agent)

proc hasDockAt*(env: Environment, pos: IVec2): bool =
  ## Check if there is a dock at the position.
  let background = env.getBackgroundThing(pos)
  not isNil(background) and background.kind == Dock

proc isWaterUnit*(agent: Thing): bool =
  ## Check if an agent is a water-based unit (boat, ship, etc.).
  agent.unitClass in {UnitBoat, UnitTradeCog, UnitGalley, UnitFireShip,
                      UnitFishingShip, UnitTransportShip, UnitDemoShip, UnitCannonGalleon}

proc isWaterBlockedForAgent*(env: Environment, agent: Thing, pos: IVec2): bool =
  ## Check if a land unit cannot enter a water tile.
  ## Land units can enter water if there's a dock.
  env.terrain[pos.x][pos.y] == Water and not agent.isWaterUnit and not env.hasDockAt(pos)

{.pop.}

## hasWaterNearby and getBiomeGatherBonus remain in environment.nim due to complex dependencies

# ============================================================================
# Elevation and movement checks
# ============================================================================

proc canTraverseElevation*(env: Environment, fromPos, toPos: IVec2): bool {.inline.} =
  ## Allow flat movement, ramp-assisted elevation changes, or falling down cliffs.
  ## Going UP requires a ramp/road. Going DOWN is always allowed (but may cause fall damage).
  if not isValidPos(fromPos) or not isValidPos(toPos):
    return false
  let dx = toPos.x - fromPos.x
  let dy = toPos.y - fromPos.y
  if abs(dx) + abs(dy) != 1:
    return false
  let elevFrom = env.elevation[fromPos.x][fromPos.y]
  let elevTo = env.elevation[toPos.x][toPos.y]
  if elevFrom == elevTo:
    return true
  if abs(elevFrom - elevTo) != 1:
    return false

  # Dropping down is always allowed (may cause fall damage)
  if elevFrom > elevTo:
    return true

  # Going up requires a ramp or road
  let terrainFrom = env.terrain[fromPos.x][fromPos.y]
  let terrainTo = env.terrain[toPos.x][toPos.y]
  terrainFrom == Road or terrainTo == Road or
    isRampTerrain(terrainFrom) or isRampTerrain(terrainTo)

proc willCauseCliffFallDamage*(env: Environment, fromPos, toPos: IVec2): bool {.inline.} =
  ## Check if moving from fromPos to toPos would cause cliff fall damage.
  ## Fall damage occurs when dropping elevation without using a ramp or road.
  if not isValidPos(fromPos) or not isValidPos(toPos):
    return false
  let elevFrom = env.elevation[fromPos.x][fromPos.y]
  let elevTo = env.elevation[toPos.x][toPos.y]
  if elevFrom <= elevTo:
    return false  # Not dropping elevation

  # Check if there's a ramp/road that would prevent fall damage
  let terrainFrom = env.terrain[fromPos.x][fromPos.y]
  let terrainTo = env.terrain[toPos.x][toPos.y]
  let hasRampOrRoad = terrainFrom == Road or terrainTo == Road or
    isRampTerrain(terrainFrom) or isRampTerrain(terrainTo)

  not hasRampOrRoad  # Fall damage if no ramp/road

# ============================================================================
# Placement checks
# ============================================================================
# NOTE: canPlace, isSpawnable, canPlaceDock remain in environment.nim
# because they depend on isTileFrozen from colors.nim (included file).

proc isBuildableTerrain*(terrain: TerrainType): bool {.inline.} =
  ## Check if terrain type allows building placement.
  terrain in BuildableTerrain

proc isSpawnable*(env: Environment, pos: IVec2): bool {.inline.} =
  ## Check if a unit can spawn at the position.
  isValidPos(pos) and env.isEmpty(pos) and isNil(env.getBackgroundThing(pos)) and not env.hasDoor(pos)

# ============================================================================
# Tile color management
# ============================================================================

proc resetTileColor*(env: Environment, pos: IVec2) =
  ## Clear dynamic tint overlays for a tile.
  env.computedTintColors[pos.x][pos.y] = TileColor(r: 0, g: 0, b: 0, intensity: 0)
