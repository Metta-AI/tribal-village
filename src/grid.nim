{.push inline.}
proc getThing(env: Environment, pos: IVec2): Thing =
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
  let color = env.baseColorForPos(pos)
  env.tileColors[pos.x][pos.y] = color
  env.baseTileColors[pos.x][pos.y] = color

proc clearDoors(env: Environment) =
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      env.doorTeams[x][y] = -1
      env.doorHearts[x][y] = 0
