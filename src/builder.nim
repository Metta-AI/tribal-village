proc signi(x: int32): int32 =
  if x < 0: -1
  elif x > 0: 1
  else: 0

proc findWallRingTarget(env: Environment, altar: IVec2, radius: int): IVec2 =
  for dx in -radius .. radius:
    for dy in -radius .. radius:
      if max(abs(dx), abs(dy)) != radius:
        continue
      let pos = altar + ivec2(dx.int32, dy.int32)
      if not isValidPos(pos):
        continue
      if env.hasDoor(pos) or not env.isEmpty(pos):
        continue
      if isBlockedTerrain(env.terrain[pos.x][pos.y]) or isTileFrozen(pos, env):
        continue
      return pos
  ivec2(-1, -1)

proc decideBuilder(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)

  # Top priority: keep population cap ahead of current population.
  let popCount = env.teamPopCount(teamId)
  let popCap = env.teamPopCap(teamId)
  if popCap > 0 and popCount >= popCap - 1:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexHouse)
    if did: return act

  # Build a wall ring around the altar.
  if agent.homeAltar.x >= 0:
    let target = findWallRingTarget(env, agent.homeAltar, 5)
    if target.x >= 0:
      let dir = ivec2(signi(target.x - agent.pos.x), signi(target.y - agent.pos.y))
      if agent.orientation == Orientation(vecToOrientation(dir)) and chebyshevDist(agent.pos, target) == 1'i32:
        let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexWall)
        if did: return act
      return saveStateAndReturn(controller, agentId, state,
        encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, target, controller.rng).uint8))

  # Core economic infrastructure.
  if env.countTeamBuildings(teamId, Mill) == 0:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexMill)
    if did: return act
  if env.countTeamBuildings(teamId, LumberCamp) == 0:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexLumberCamp)
    if did: return act
  if env.countTeamBuildings(teamId, MiningCamp) == 0:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexMiningCamp)
    if did: return act

  # Production buildings.
  if env.countTeamBuildings(teamId, WeavingLoom) == 0:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexWeavingLoom)
    if did: return act
  if env.countTeamBuildings(teamId, ClayOven) == 0:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexClayOven)
    if did: return act
  if env.countTeamBuildings(teamId, Armory) == 0:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexArmory)
    if did: return act
  if env.countTeamBuildings(teamId, Blacksmith) == 0:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexBlacksmith)
    if did: return act

  # Military production.
  if env.countTeamBuildings(teamId, Barracks) == 0:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexBarracks)
    if did: return act
  if env.countTeamBuildings(teamId, ArcheryRange) == 0:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexArcheryRange)
    if did: return act
  if env.countTeamBuildings(teamId, Stable) == 0:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexStable)
    if did: return act
  if env.countTeamBuildings(teamId, SiegeWorkshop) == 0:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexSiegeWorkshop)
    if did: return act

  # Defensive buildings.
  if env.countTeamBuildings(teamId, Outpost) == 0:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexOutpost)
    if did: return act
  if env.countTeamBuildings(teamId, Castle) == 0:
    let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, BuildIndexCastle)
    if did: return act

  # Gear up if we can.
  if agent.inventoryArmor < ArmorPoints:
    let armory = env.findNearestFriendlyThingSpiral(state, teamId, Armory, controller.rng)
    if armory != nil:
      return controller.useOrMove(env, agent, agentId, state, armory.pos)

  return controller.moveNextSearch(env, agent, agentId, state)
