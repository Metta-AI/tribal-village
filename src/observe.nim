proc clear[T](s: var openarray[T]) =
  ## Zero out a contiguous buffer (arrays/openarrays) without reallocating.
  let p = cast[pointer](s[0].addr)
  zeroMem(p, s.len * sizeof(T))


{.push inline.}
proc updateObservations(
  env: Environment,
  layer: ObservationName,
  pos: IVec2,
  value: int
) =
  ## Ultra-optimized observation update - early bailout and minimal calculations
  let layerId = ord(layer)

  # Ultra-fast observation update with minimal calculations

  # Still need to check all agents but with optimized early exit
  let agentCount = env.agents.len
  for agentId in 0 ..< agentCount:
    let agentPos = env.agents[agentId].pos

    # Ultra-fast bounds check using compile-time constants
    let dx = pos.x - agentPos.x
    let dy = pos.y - agentPos.y
    if dx < -ObservationRadius or dx > ObservationRadius or
       dy < -ObservationRadius or dy > ObservationRadius:
      continue

    let x = dx + ObservationRadius
    let y = dy + ObservationRadius
    var agentLayer = addr env.observations[agentId][layerId]
    agentLayer[][x][y] = value.uint8
  env.observationsInitialized = true
{.pop.}

proc getInv*(thing: Thing, key: ItemKey): int


proc rebuildObservations*(env: Environment) =
  ## Recompute all observation layers from the current environment state when needed.
  env.observations.clear()
  env.observationsInitialized = false

  # Populate agent-centric layers (presence, orientation, inventory).
  for agent in env.agents:
    if agent.isNil:
      continue
    if not isValidPos(agent.pos):
      continue
    let teamValue = getTeamId(agent.agentId) + 1
    env.updateObservations(AgentLayer, agent.pos, teamValue)
    env.updateObservations(AgentOrientationLayer, agent.pos, agent.orientation.int)
    env.updateObservations(AgentInventoryGoldLayer, agent.pos, getInv(agent, ItemGold))
    env.updateObservations(AgentInventoryStoneLayer, agent.pos, getInv(agent, ItemStone))
    env.updateObservations(AgentInventoryBarLayer, agent.pos, getInv(agent, ItemBar))
    env.updateObservations(AgentInventoryWaterLayer, agent.pos, getInv(agent, ItemWater))
    env.updateObservations(AgentInventoryWheatLayer, agent.pos, getInv(agent, ItemWheat))
    env.updateObservations(AgentInventoryWoodLayer, agent.pos, getInv(agent, ItemWood))
    env.updateObservations(AgentInventorySpearLayer, agent.pos, getInv(agent, ItemSpear))
    env.updateObservations(AgentInventoryLanternLayer, agent.pos, getInv(agent, ItemLantern))
    env.updateObservations(AgentInventoryArmorLayer, agent.pos, getInv(agent, ItemArmor))
    env.updateObservations(AgentInventoryBreadLayer, agent.pos, getInv(agent, ItemBread))

  # Populate environment object layers.
  for thing in env.things:
    if thing.isNil:
      continue
    case thing.kind
    of Agent:
      discard  # Already handled above.
    of Wall:
      env.updateObservations(WallLayer, thing.pos, 1)
    of Pine, Palm:
      discard  # No dedicated observation layer for trees.
    of Magma:
      env.updateObservations(MagmaLayer, thing.pos, 1)
    of Altar:
      env.updateObservations(altarLayer, thing.pos, 1)
      env.updateObservations(altarHeartsLayer, thing.pos, getInv(thing, ItemHearts))
    of Spawner:
      discard  # No dedicated observation layer for spawners.
    of Tumor:
      env.updateObservations(AgentLayer, thing.pos, 255)
    of Cow, Skeleton, Armory, ClayOven, WeavingLoom, Outpost,
       Barrel, Mill, LumberCamp, MiningCamp, Lantern, TownCenter, House,
       Barracks, ArcheryRange, Stable, SiegeWorkshop, Blacksmith, Market, Dock, Monastery,
       University, Castle:
      discard

  env.observationsInitialized = true
