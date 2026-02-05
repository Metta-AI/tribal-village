# Settlement founding logic: settlers build town center and altar at new site,
# then reassign homeAltar. This file is included by ai_defaults.nim.

proc foundSettlement*(env: Environment, settlerTarget: IVec2, teamId: int,
                      rng: var Rand): tuple[altarPos: IVec2, tcPos: IVec2] =
  ## Place a new town center and altar at the settler target site.
  ## Returns the positions of the new altar and town center, or (-1,-1) if failed.
  result = (ivec2(-1, -1), ivec2(-1, -1))

  # 1. Place Town Center at or near settlerTarget
  let tcPos = placeStartingTownCenter(env, settlerTarget, teamId, rng)
  if tcPos == settlerTarget and not env.isEmpty(settlerTarget):
    # placeStartingTownCenter returns center on failure; check we actually placed
    let thing = env.getThing(tcPos)
    if isNil(thing) or thing.kind != TownCenter or thing.teamId != teamId:
      return
  result.tcPos = tcPos

  # 2. Place Altar within TownSplitNewAltarRadius of the new town center
  var altarPos = ivec2(-1, -1)
  for radius in 1 .. TownSplitNewAltarRadius:
    for dx in -radius .. radius:
      for dy in -radius .. radius:
        if max(abs(dx), abs(dy)) != radius:
          continue
        let pos = tcPos + ivec2(dx.int32, dy.int32)
        if not isValidPos(pos):
          continue
        if env.terrain[pos.x][pos.y] == Water:
          continue
        if not env.isEmpty(pos):
          continue
        if env.hasDoor(pos):
          continue
        altarPos = pos
        break
      if altarPos.x >= 0: break
    if altarPos.x >= 0: break

  if altarPos.x < 0:
    # Fallback: try adjacent to tcPos
    altarPos = env.findFirstEmptyPositionAround(tcPos, TownSplitNewAltarRadius)

  if altarPos.x < 0:
    return  # Cannot place altar, founding fails

  # Create and place the altar
  let altar = Thing(
    kind: Altar,
    pos: altarPos,
    teamId: teamId
  )
  altar.inventory = emptyInventory()
  altar.hearts = MapObjectAltarInitialHearts
  env.add(altar)

  # Register altar in tracking structures
  if teamId >= 0 and teamId < MapRoomObjectsTeams:
    env.teamAltars[teamId].add(altarPos)
    if teamId < env.teamColors.len:
      env.altarColors[altarPos] = env.teamColors[teamId]

  result.altarPos = altarPos

proc reassignSettlers*(env: Environment, teamId: int, newAltarPos: IVec2) =
  ## Reassign all settlers of a team to the new altar and clear settler flags.
  ## Called after town founding completes.
  if newAltarPos.x < 0:
    return

  let startId = teamId * MapAgentsPerTeam
  let endId = min(startId + MapAgentsPerTeam, MapAgents)
  for agentId in startId ..< endId:
    let agent = env.agents[agentId]
    if agent.isNil:
      continue
    if not agent.isSettler:
      continue
    if not isAgentAlive(env, agent):
      continue

    # Update altar population tracking
    if agent.homeAltar.x >= 0:
      let oldCount = env.altarPopulation.getOrDefault(agent.homeAltar, 0)
      if oldCount > 0:
        env.altarPopulation[agent.homeAltar] = oldCount - 1

    # Reassign homeAltar to new altar
    agent.homeAltar = newAltarPos
    env.altarPopulation[newAltarPos] = env.altarPopulation.getOrDefault(newAltarPos, 0) + 1

    # Clear settler state
    agent.isSettler = false
    agent.settlerTarget = ivec2(-1, -1)
    agent.settlerArrived = false

# -- Behavior option for settler founding --

proc canStartSettlerFounding*(controller: Controller, env: Environment, agent: Thing,
                              agentId: int, state: var AgentState): bool =
  ## Settlers who have arrived at target should found a settlement.
  agent.isSettler and agent.settlerArrived and
    agent.settlerTarget.x >= 0 and agent.settlerTarget.y >= 0

proc shouldTerminateSettlerFounding*(controller: Controller, env: Environment, agent: Thing,
                                     agentId: int, state: var AgentState): bool =
  ## Terminate when settler flags are cleared (founding complete or aborted).
  not agent.isSettler

proc optSettlerFounding*(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): uint8 =
  ## Settler has arrived at target - found the new settlement.
  ## Only the first arrived settler triggers the actual founding; others wait.
  let teamId = getTeamId(agent)
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return 0'u8

  let target = agent.settlerTarget
  if target.x < 0:
    return 0'u8

  # Check if a new altar already exists near the target (another settler already founded)
  for altarPos in env.teamAltars[teamId]:
    # Skip the agent's current home altar
    if altarPos == agent.homeAltar:
      continue
    let dist = max(abs(altarPos.x - target.x), abs(altarPos.y - target.y))
    if dist <= TownSplitNewAltarRadius + 3:
      # Founding already done by another settler - reassign self
      if agent.homeAltar.x >= 0:
        let oldCount = env.altarPopulation.getOrDefault(agent.homeAltar, 0)
        if oldCount > 0:
          env.altarPopulation[agent.homeAltar] = oldCount - 1
      agent.homeAltar = altarPos
      agent.isSettler = false
      agent.settlerTarget = ivec2(-1, -1)
      agent.settlerArrived = false
      env.altarPopulation[altarPos] = env.altarPopulation.getOrDefault(altarPos, 0) + 1
      return 1'u8  # NOOP action, just clearing state

  # This settler is the founder - place town center and altar
  let (altarPos, _) = foundSettlement(env, target, teamId, controller.rng)
  if altarPos.x < 0:
    # Founding failed - try adjacent positions
    return 0'u8

  # Place starting resource buildings around the new altar
  placeStartingResourceBuildings(env, altarPos, teamId)

  # Reassign all settlers of this team to the new altar
  reassignSettlers(env, teamId, altarPos)

  1'u8  # Return NOOP; settlers transition to normal villager behavior next step
