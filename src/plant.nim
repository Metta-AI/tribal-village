proc plantAction(env: Environment, id: int, agent: Thing, argument: int) =
  ## Plant lantern at agent's current position - argument specifies direction (0=N, 1=S, 2=W, 3=E, 4=NW, 5=NE, 6=SW, 7=SE)
  if argument > 7:
    inc env.stats[id].actionInvalid
    return

  # Calculate target position based on orientation argument
  let plantOrientation = Orientation(argument)
  let delta = getOrientationDelta(plantOrientation)
  var targetPos = agent.pos
  targetPos.x += int32(delta.x)
  targetPos.y += int32(delta.y)

  # Check bounds
  if targetPos.x < 0 or targetPos.x >= MapWidth or targetPos.y < 0 or targetPos.y >= MapHeight:
    inc env.stats[id].actionInvalid
    return

  # Check if position is empty and not water
  if not env.isEmpty(targetPos) or env.hasDoor(targetPos) or isBlockedTerrain(env.terrain[targetPos.x][targetPos.y]) or isTileFrozen(targetPos, env):
    inc env.stats[id].actionInvalid
    return

  if agent.inventoryLantern > 0:
    # Calculate team ID directly from the planting agent's ID
    let teamId = getTeamId(agent.agentId)

    # Plant the lantern
    let lantern = Thing(
      kind: PlantedLantern,
      pos: targetPos,
      teamId: teamId,
      lanternHealthy: true
    )

    env.add(lantern)

    # Consume the lantern from agent's inventory
    agent.inventoryLantern = 0

    # Give reward for planting
    agent.reward += env.config.clothReward * 0.5  # Half reward for planting

    inc env.stats[id].actionPlant
  else:
    let roadKey = ItemThingPrefix & "Road"
    if getInv(agent, roadKey) <= 0:
      inc env.stats[id].actionInvalid
      return
    if env.terrain[targetPos.x][targetPos.y] != Empty:
      inc env.stats[id].actionInvalid
      return
    setInv(agent, roadKey, getInv(agent, roadKey) - 1)
    env.updateAgentInventoryObs(agent, roadKey)
    env.terrain[targetPos.x][targetPos.y] = Road
    env.resetTileColor(targetPos)
    env.updateObservations(TintLayer, targetPos, 0)
    inc env.stats[id].actionPlant

proc plantResourceAction(env: Environment, id: int, agent: Thing, argument: int) =
  ## Plant wheat (args 0-3) or tree (args 4-7) onto an adjacent fertile tile
  if argument < 0 or argument >= 8:
    inc env.stats[id].actionInvalid
    return

  let plantingTree = argument >= 4
  let dirIndex = if plantingTree: argument - 4 else: argument
  let orientation = Orientation(dirIndex)
  let delta = getOrientationDelta(orientation)
  let targetPos = ivec2(agent.pos.x + delta.x.int32, agent.pos.y + delta.y.int32)

  # Bounds and occupancy checks
  if targetPos.x < 0 or targetPos.x >= MapWidth or targetPos.y < 0 or targetPos.y >= MapHeight:
    inc env.stats[id].actionInvalid
    return
  if not env.isEmpty(targetPos) or env.hasDoor(targetPos) or isBlockedTerrain(env.terrain[targetPos.x][targetPos.y]) or isTileFrozen(targetPos, env):
    inc env.stats[id].actionInvalid
    return
  if env.terrain[targetPos.x][targetPos.y] != Fertile:
    inc env.stats[id].actionInvalid
    return

  if plantingTree:
    if agent.inventoryWood <= 0:
      inc env.stats[id].actionInvalid
      return
    agent.inventoryWood = max(0, agent.inventoryWood - 1)
    env.updateObservations(AgentInventoryWoodLayer, agent.pos, agent.inventoryWood)
    env.terrain[targetPos.x][targetPos.y] = Empty
    env.resetTileColor(targetPos)
    env.add(Thing(
      kind: TreeObject,
      pos: targetPos,
      treeVariant: TreeVariantPine
    ))
  else:
    if agent.inventoryWheat <= 0:
      inc env.stats[id].actionInvalid
      return
    agent.inventoryWheat = max(0, agent.inventoryWheat - 1)
    env.updateObservations(AgentInventoryWheatLayer, agent.pos, agent.inventoryWheat)
    env.terrain[targetPos.x][targetPos.y] = Wheat
    env.resetTileColor(targetPos)

  # Consuming fertility (terrain replaced above)
  inc env.stats[id].actionPlantResource
