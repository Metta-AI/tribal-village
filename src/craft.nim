proc tryTrainUnit(env: Environment, agent: Thing, building: Thing, unitClass: AgentUnitClass,
                  costs: openArray[tuple[res: StockpileResource, count: int]], cooldown: int): bool =
  if agent.unitClass != UnitVillager:
    return false
  let teamId = getTeamId(agent.agentId)
  if building.teamId != teamId:
    return false
  if not env.spendStockpile(teamId, costs):
    return false
  applyUnitClass(agent, unitClass)
  if agent.inventorySpear > 0:
    agent.inventorySpear = 0
    env.updateObservations(AgentInventorySpearLayer, agent.pos, agent.inventorySpear)
  building.cooldown = cooldown
  true

proc tryMarketTrade(env: Environment, agent: Thing, building: Thing): bool =
  let teamId = getTeamId(agent.agentId)
  if building.teamId != teamId:
    return false
  var traded = false
  for key, count in agent.inventory.pairs:
    if count <= 0:
      continue
    if not isStockpileResourceKey(key):
      continue
    let res = stockpileResourceForItem(key)
    if res == ResourceWater:
      continue
    if res == ResourceGold:
      env.addToStockpile(teamId, ResourceFood, count)
      setInv(agent, key, 0)
      env.updateAgentInventoryObs(agent, key)
      traded = true
    else:
      let gained = count div 2
      if gained > 0:
        env.addToStockpile(teamId, ResourceGold, gained)
        setInv(agent, key, count mod 2)
        env.updateAgentInventoryObs(agent, key)
        traded = true
  if traded:
    building.cooldown = 6
    return true
  false

proc recipeUsesStockpile(recipe: CraftRecipe): bool =
  if recipe.station == StationSiegeWorkshop:
    return false
  for output in recipe.outputs:
    if output.key.startsWith(ItemThingPrefix):
      return true
  false

proc canApplyRecipe(env: Environment, agent: Thing, recipe: CraftRecipe): bool =
  let useStockpile = recipeUsesStockpile(recipe)
  let teamId = getTeamId(agent.agentId)
  for input in recipe.inputs:
    if useStockpile and isStockpileResourceKey(input.key):
      let res = stockpileResourceForItem(input.key)
      if env.stockpileCount(teamId, res) < input.count:
        return false
    elif getInv(agent, input.key) < input.count:
      return false
  for output in recipe.outputs:
    if getInv(agent, output.key) + output.count > MapObjectAgentMaxInventory:
      return false
  true

proc applyRecipe(env: Environment, agent: Thing, recipe: CraftRecipe) =
  let useStockpile = recipeUsesStockpile(recipe)
  let teamId = getTeamId(agent.agentId)
  if useStockpile:
    var costs: seq[tuple[res: StockpileResource, count: int]] = @[]
    for input in recipe.inputs:
      if isStockpileResourceKey(input.key):
        costs.add((res: stockpileResourceForItem(input.key), count: input.count))
    discard env.spendStockpile(teamId, costs)
  for input in recipe.inputs:
    if useStockpile and isStockpileResourceKey(input.key):
      continue
    setInv(agent, input.key, getInv(agent, input.key) - input.count)
    env.updateAgentInventoryObs(agent, input.key)
  for output in recipe.outputs:
    setInv(agent, output.key, getInv(agent, output.key) + output.count)
    env.updateAgentInventoryObs(agent, output.key)

proc tryCraftAtStation(env: Environment, agent: Thing, station: CraftStation, stationThing: Thing): bool =
  for recipe in CraftRecipes:
    if recipe.station != station:
      continue
    var hasThingOutput = false
    for output in recipe.outputs:
      if output.key.startsWith(ItemThingPrefix):
        hasThingOutput = true
        break
    if hasThingOutput:
      continue
    if not canApplyRecipe(env, agent, recipe):
      continue
    env.applyRecipe(agent, recipe)
    if stationThing != nil:
      stationThing.cooldown = max(1, recipe.cooldown)
    return true
  false
