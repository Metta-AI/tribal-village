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

proc deliverToTeammate(controller: Controller, env: Environment, agent: Thing,
                       agentId: int, state: var AgentState, teammate: Thing): uint8 =
  let dx = abs(teammate.pos.x - agent.pos.x)
  let dy = abs(teammate.pos.y - agent.pos.y)
  if max(dx, dy) == 1'i32:
    return saveStateAndReturn(controller, agentId, state,
      encodeAction(5'u8, neighborDirIndex(agent.pos, teammate.pos).uint8))
  return saveStateAndReturn(controller, agentId, state,
    encodeAction(1'u8, getMoveTowards(env, agent, agent.pos, teammate.pos, controller.rng).uint8))

proc dropoffBuilderCarrying(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): tuple[did: bool, action: uint8] =
  let teamId = getTeamId(agent.agentId)
  if agent.inventoryGold > 0:
    var dropoff = env.findNearestFriendlyThingSpiral(state, teamId, Bank, controller.rng)
    if dropoff == nil:
      dropoff = env.findNearestFriendlyThingSpiral(state, teamId, TownCenter, controller.rng)
    if dropoff != nil:
      return (true, controller.useOrMove(env, agent, agentId, state, dropoff.pos))
  if agent.inventoryStone > 0:
    var dropoff = env.findNearestFriendlyThingSpiral(state, teamId, MiningCamp, controller.rng)
    if dropoff == nil:
      dropoff = env.findNearestFriendlyThingSpiral(state, teamId, TownCenter, controller.rng)
    if dropoff != nil:
      return (true, controller.useOrMove(env, agent, agentId, state, dropoff.pos))
  (false, 0'u8)

proc decideBuilder(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): uint8 =
  let teamId = getTeamId(agent.agentId)

  let (didDrop, dropAct) = dropoffBuilderCarrying(controller, env, agent, agentId, state)
  if didDrop: return dropAct

  # Top priority: keep population cap ahead of current population.
  let popCount = env.teamPopCount(teamId)
  let popCap = env.teamPopCap(teamId)
  if popCap > 0 and popCount >= popCap - 1:
    let idx = buildIndexFor(House)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act

  # Ensure a town center exists if the starter one is lost.
  if env.countTeamBuildings(teamId, TownCenter) == 0:
    let idx = buildIndexFor(TownCenter)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
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
  if env.countTeamBuildings(teamId, Granary) == 0:
    let idx = buildIndexFor(Granary)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act
  if env.countTeamBuildings(teamId, Mill) == 0:
    let idx = buildIndexFor(Mill)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act
  if env.countTeamBuildings(teamId, LumberCamp) == 0:
    let idx = buildIndexFor(LumberCamp)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act
  if env.countTeamBuildings(teamId, MiningCamp) == 0:
    let idx = buildIndexFor(MiningCamp)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act
  if env.countTeamBuildings(teamId, Bank) == 0:
    let idx = buildIndexFor(Bank)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act

  # Production buildings.
  if env.countTeamBuildings(teamId, WeavingLoom) == 0:
    let idx = buildIndexFor(WeavingLoom)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act
  if env.countTeamBuildings(teamId, ClayOven) == 0:
    let idx = buildIndexFor(ClayOven)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act
  if env.countTeamBuildings(teamId, Blacksmith) == 0:
    let idx = buildIndexFor(Blacksmith)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act

  # Military production.
  if env.countTeamBuildings(teamId, Barracks) == 0:
    let idx = buildIndexFor(Barracks)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act
  if env.countTeamBuildings(teamId, ArcheryRange) == 0:
    let idx = buildIndexFor(ArcheryRange)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act
  if env.countTeamBuildings(teamId, Stable) == 0:
    let idx = buildIndexFor(Stable)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act
  if env.countTeamBuildings(teamId, SiegeWorkshop) == 0:
    let idx = buildIndexFor(SiegeWorkshop)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act

  # Defensive buildings.
  if env.countTeamBuildings(teamId, Outpost) == 0:
    let idx = buildIndexFor(Outpost)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act
  if env.countTeamBuildings(teamId, Castle) == 0:
    let idx = buildIndexFor(Castle)
    if idx >= 0:
      let (did, act) = tryBuildAction(controller, env, agent, agentId, state, teamId, idx)
      if did: return act

  # Equipment support: deliver armor/spears to teammates who need them.
  if agent.inventoryArmor > 0:
    let teammate = findNearestTeammateNeeding(env, agent, NeedArmor)
    if teammate != nil:
      return deliverToTeammate(controller, env, agent, agentId, state, teammate)
    let smith = env.findNearestFriendlyThingSpiral(state, teamId, Blacksmith, controller.rng)
    if smith != nil:
      return controller.useOrMove(env, agent, agentId, state, smith.pos)

  if agent.inventorySpear > 0:
    let teammate = findNearestTeammateNeeding(env, agent, NeedSpear)
    if teammate != nil:
      return deliverToTeammate(controller, env, agent, agentId, state, teammate)
    let smith = env.findNearestFriendlyThingSpiral(state, teamId, Blacksmith, controller.rng)
    if smith != nil:
      return controller.useOrMove(env, agent, agentId, state, smith.pos)

  # Craft armor at the blacksmith when bars are available.
  let armorNeedy = findNearestTeammateNeeding(env, agent, NeedArmor)
  if armorNeedy != nil and agent.inventoryBar > 0:
    let smith = env.findNearestFriendlyThingSpiral(state, teamId, Blacksmith, controller.rng)
    if smith != nil:
      return controller.useOrMove(env, agent, agentId, state, smith.pos)

  # Craft spears at the blacksmith if fighters are out.
  let spearNeedy = findNearestTeammateNeeding(env, agent, NeedSpear)
  if spearNeedy != nil:
    if agent.inventoryWood == 0:
      let stump = env.findNearestThingSpiral(state, Stump, controller.rng)
      if stump != nil:
        return controller.useOrMove(env, agent, agentId, state, stump.pos)
      let pinePos = env.findNearestTerrainSpiral(state, Pine, controller.rng)
      if pinePos.x >= 0:
        return controller.attackOrMoveToTerrain(env, agent, agentId, state, pinePos)
      let palmPos = env.findNearestTerrainSpiral(state, Palm, controller.rng)
      if palmPos.x >= 0:
        return controller.attackOrMoveToTerrain(env, agent, agentId, state, palmPos)
    let smith = env.findNearestFriendlyThingSpiral(state, teamId, Blacksmith, controller.rng)
    if smith != nil:
      return controller.useOrMove(env, agent, agentId, state, smith.pos)

  return controller.moveNextSearch(env, agent, agentId, state)
