{.push inline.}
proc getThing*(env: Environment, pos: IVec2): Thing =
  if not isValidPos(pos):
    return nil
  return env.grid[pos.x][pos.y]

proc isEmpty*(env: Environment, pos: IVec2): bool =
  if not isValidPos(pos):
    return false
  return env.grid[pos.x][pos.y] == nil

proc hasDoor*(env: Environment, pos: IVec2): bool =
  if not isValidPos(pos):
    return false
  return env.doorTeams[pos.x][pos.y] >= 0

proc getDoorTeam*(env: Environment, pos: IVec2): int =
  if not isValidPos(pos):
    return -1
  return env.doorTeams[pos.x][pos.y].int

proc canAgentPassDoor*(env: Environment, agent: Thing, pos: IVec2): bool =
  if not env.hasDoor(pos):
    return true
  return env.getDoorTeam(pos) == getTeamId(agent.agentId)
{.pop.}
proc resetTileColor*(env: Environment, pos: IVec2) =
  ## Restore a tile to the biome base color
  if pos.x < 0 or pos.x >= MapWidth or pos.y < 0 or pos.y >= MapHeight:
    return
  let color = env.baseTintColors[pos.x][pos.y]
  env.tileColors[pos.x][pos.y] = color
  env.baseTileColors[pos.x][pos.y] = color
