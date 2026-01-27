# Economy Management and Worker Allocation System
# Tracks resource flow, detects bottlenecks, and suggests role changes
# This file is included by ai_defaults.nim which is included by agent_control.nim
# It has access to types defined in ai_core.nim (AgentRole, Controller, etc.)

const
  # Resource flow tracking window (in steps)
  EconomyTrackingWindow* = 60  # Track over ~1 minute of game time
  # Minimum steps between role suggestions
  RoleSuggestionCooldown* = 30
  # Thresholds for bottleneck detection
  MinGatherersRatio* = 0.3    # At least 30% gatherers
  MaxGatherersRatio* = 0.7    # At most 70% gatherers
  MinBuildersRatio* = 0.1     # At least 10% builders
  MaxBuildersRatio* = 0.4     # At most 40% builders
  MinFightersRatio* = 0.1     # At least 10% fighters when under threat
  # Resource thresholds for trade decisions
  TradeExcessThreshold* = 20  # Trade if any resource exceeds this
  TradeScarceThreshold* = 5   # Trade to acquire if below this
  # Critical resource thresholds
  CriticalFoodLevel* = 3      # Food below this is critical
  CriticalWoodLevel* = 5      # Wood below this is critical

type
  ResourceSnapshot* = object
    food*: int
    wood*: int
    stone*: int
    gold*: int
    step*: int

  ResourceFlowRate* = object
    foodPerStep*: float
    woodPerStep*: float
    stonePerStep*: float
    goldPerStep*: float

  WorkerCounts* = object
    gatherers*: int
    builders*: int
    fighters*: int
    total*: int

  BottleneckKind* = enum
    NoBottleneck
    TooManyGatherers
    TooFewGatherers
    TooManyBuilders
    TooFewBuilders
    TooFewFighters
    FoodCritical
    WoodCritical
    StoneCritical

  RoleSuggestion* = object
    fromRole*: AgentRole
    toRole*: AgentRole
    reason*: BottleneckKind
    urgency*: float  # 0.0 to 1.0, higher = more urgent

  EconomyState* = object
    # Circular buffer of resource snapshots
    snapshots*: array[EconomyTrackingWindow, ResourceSnapshot]
    snapshotIndex*: int
    snapshotCount*: int
    # Cached flow rates (updated periodically)
    flowRate*: ResourceFlowRate
    # Last suggestion time per team
    lastSuggestionStep*: int
    # Current bottleneck
    currentBottleneck*: BottleneckKind

# Team-indexed economy state (global storage)
var teamEconomy*: array[MapRoomObjectsTeams, EconomyState]

proc recordSnapshot*(teamId: int, env: Environment) =
  ## Record current stockpile levels for resource flow tracking
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return

  let idx = teamEconomy[teamId].snapshotIndex
  teamEconomy[teamId].snapshots[idx] = ResourceSnapshot(
    food: env.stockpileCount(teamId, ResourceFood),
    wood: env.stockpileCount(teamId, ResourceWood),
    stone: env.stockpileCount(teamId, ResourceStone),
    gold: env.stockpileCount(teamId, ResourceGold),
    step: env.currentStep
  )
  teamEconomy[teamId].snapshotIndex = (idx + 1) mod EconomyTrackingWindow
  if teamEconomy[teamId].snapshotCount < EconomyTrackingWindow:
    inc teamEconomy[teamId].snapshotCount

proc calculateFlowRate*(teamId: int): ResourceFlowRate =
  ## Calculate resource flow rates from recent snapshots
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return ResourceFlowRate()

  let state = teamEconomy[teamId]
  if state.snapshotCount < 2:
    return ResourceFlowRate()

  # Find oldest and newest snapshots
  let newestIdx = (state.snapshotIndex - 1 + EconomyTrackingWindow) mod EconomyTrackingWindow
  let oldestIdx = if state.snapshotCount >= EconomyTrackingWindow:
    state.snapshotIndex
  else:
    0

  let newest = state.snapshots[newestIdx]
  let oldest = state.snapshots[oldestIdx]
  let stepDiff = newest.step - oldest.step

  if stepDiff <= 0:
    return ResourceFlowRate()

  let divisor = float(stepDiff)
  result.foodPerStep = float(newest.food - oldest.food) / divisor
  result.woodPerStep = float(newest.wood - oldest.wood) / divisor
  result.stonePerStep = float(newest.stone - oldest.stone) / divisor
  result.goldPerStep = float(newest.gold - oldest.gold) / divisor

proc updateFlowRate*(teamId: int) =
  ## Update cached flow rate
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  teamEconomy[teamId].flowRate = calculateFlowRate(teamId)

proc getFlowRate*(teamId: int): ResourceFlowRate =
  ## Get current resource flow rate
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return ResourceFlowRate()
  teamEconomy[teamId].flowRate

proc countWorkers*(controller: Controller, env: Environment, teamId: int): WorkerCounts =
  ## Count agents by role for a team using controller's agent state
  for agent in env.agents:
    if not isAgentAlive(env, agent):
      continue
    if getTeamId(agent) != teamId:
      continue
    inc result.total
    let agentId = agent.agentId
    if agentId < 0 or agentId >= MapAgents or not controller.agentsInitialized[agentId]:
      # Default to gatherer if not initialized
      inc result.gatherers
      continue
    case controller.agents[agentId].role
    of Gatherer:
      inc result.gatherers
    of Builder:
      inc result.builders
    of Fighter:
      inc result.fighters
    of Scripted:
      # Count scripted as gatherers for ratio purposes
      inc result.gatherers

proc detectBottleneck*(controller: Controller, env: Environment, teamId: int): BottleneckKind =
  ## Detect economic bottlenecks for a team
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return NoBottleneck

  # Check critical resource levels first
  let food = env.stockpileCount(teamId, ResourceFood)
  let wood = env.stockpileCount(teamId, ResourceWood)
  let stone = env.stockpileCount(teamId, ResourceStone)

  if food < CriticalFoodLevel:
    return FoodCritical
  if wood < CriticalWoodLevel:
    return WoodCritical

  # Check worker ratios
  let counts = countWorkers(controller, env, teamId)
  if counts.total == 0:
    return NoBottleneck

  let gathererRatio = float(counts.gatherers) / float(counts.total)
  let builderRatio = float(counts.builders) / float(counts.total)
  let fighterRatio = float(counts.fighters) / float(counts.total)

  # Check for enemy presence to determine fighter needs
  var hasNearbyEnemy = false
  for agent in env.agents:
    if not isAgentAlive(env, agent):
      continue
    if getTeamId(agent) == teamId:
      continue
    # Enemy agent exists
    hasNearbyEnemy = true
    break

  if hasNearbyEnemy and fighterRatio < MinFightersRatio:
    return TooFewFighters

  if gathererRatio > MaxGatherersRatio:
    return TooManyGatherers
  if gathererRatio < MinGatherersRatio:
    return TooFewGatherers

  if builderRatio > MaxBuildersRatio:
    return TooManyBuilders
  if builderRatio < MinBuildersRatio:
    return TooFewBuilders

  NoBottleneck

proc updateBottleneck*(controller: Controller, env: Environment, teamId: int) =
  ## Update current bottleneck state
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  teamEconomy[teamId].currentBottleneck = detectBottleneck(controller, env, teamId)

proc getCurrentBottleneck*(teamId: int): BottleneckKind =
  ## Get current bottleneck for team
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return NoBottleneck
  teamEconomy[teamId].currentBottleneck

proc suggestRoleChange*(controller: Controller, env: Environment, teamId: int): RoleSuggestion =
  ## Suggest a role change based on current economic state
  ## Returns NoBottleneck in reason if no change needed
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return RoleSuggestion(reason: NoBottleneck)

  # Check cooldown
  let state = teamEconomy[teamId]
  if env.currentStep - state.lastSuggestionStep < RoleSuggestionCooldown:
    return RoleSuggestion(reason: NoBottleneck)

  let bottleneck = detectBottleneck(controller, env, teamId)
  let counts = countWorkers(controller, env, teamId)

  case bottleneck
  of FoodCritical, TooFewGatherers:
    if counts.builders > 0:
      return RoleSuggestion(
        fromRole: Builder,
        toRole: Gatherer,
        reason: bottleneck,
        urgency: if bottleneck == FoodCritical: 1.0 else: 0.7
      )
    elif counts.fighters > 1:
      return RoleSuggestion(
        fromRole: Fighter,
        toRole: Gatherer,
        reason: bottleneck,
        urgency: if bottleneck == FoodCritical: 0.9 else: 0.5
      )

  of WoodCritical:
    if counts.fighters > 1:
      return RoleSuggestion(
        fromRole: Fighter,
        toRole: Gatherer,
        reason: WoodCritical,
        urgency: 0.8
      )
    elif counts.builders > 1:
      return RoleSuggestion(
        fromRole: Builder,
        toRole: Gatherer,
        reason: WoodCritical,
        urgency: 0.6
      )

  of TooManyGatherers:
    # Need more builders or fighters
    if counts.builders == 0:
      return RoleSuggestion(
        fromRole: Gatherer,
        toRole: Builder,
        reason: TooManyGatherers,
        urgency: 0.6
      )
    else:
      return RoleSuggestion(
        fromRole: Gatherer,
        toRole: Fighter,
        reason: TooManyGatherers,
        urgency: 0.4
      )

  of TooFewBuilders:
    if counts.gatherers > 2:
      return RoleSuggestion(
        fromRole: Gatherer,
        toRole: Builder,
        reason: TooFewBuilders,
        urgency: 0.5
      )

  of TooManyBuilders:
    return RoleSuggestion(
      fromRole: Builder,
      toRole: Gatherer,
      reason: TooManyBuilders,
      urgency: 0.3
    )

  of TooFewFighters:
    if counts.gatherers > 2:
      return RoleSuggestion(
        fromRole: Gatherer,
        toRole: Fighter,
        reason: TooFewFighters,
        urgency: 0.8
      )
    elif counts.builders > 1:
      return RoleSuggestion(
        fromRole: Builder,
        toRole: Fighter,
        reason: TooFewFighters,
        urgency: 0.7
      )

  of StoneCritical, NoBottleneck:
    discard

  RoleSuggestion(reason: NoBottleneck)

proc markSuggestionApplied*(teamId: int, step: int) =
  ## Mark that a role suggestion was applied (reset cooldown)
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  teamEconomy[teamId].lastSuggestionStep = step

proc shouldTrade*(env: Environment, teamId: int): tuple[should: bool, sellResource, buyResource: StockpileResource] =
  ## Determine if trading is beneficial and what to trade
  ## Returns the resource to sell and resource to buy
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return (false, ResourceFood, ResourceFood)

  let food = env.stockpileCount(teamId, ResourceFood)
  let wood = env.stockpileCount(teamId, ResourceWood)
  let stone = env.stockpileCount(teamId, ResourceStone)
  let gold = env.stockpileCount(teamId, ResourceGold)

  # Find most scarce resource
  var scarceRes = ResourceFood
  var scarceAmount = food
  if wood < scarceAmount:
    scarceRes = ResourceWood
    scarceAmount = wood
  if stone < scarceAmount:
    scarceRes = ResourceStone
    scarceAmount = stone

  # Only trade if scarce resource is below threshold
  if scarceAmount >= TradeScarceThreshold:
    return (false, ResourceFood, ResourceFood)

  # Find most abundant tradeable resource (not the scarce one, prefer gold)
  if gold > TradeExcessThreshold:
    return (true, ResourceGold, scarceRes)

  # Check other resources
  if food > TradeExcessThreshold and scarceRes != ResourceFood:
    return (true, ResourceFood, scarceRes)
  if wood > TradeExcessThreshold and scarceRes != ResourceWood:
    return (true, ResourceWood, scarceRes)
  if stone > TradeExcessThreshold and scarceRes != ResourceStone:
    return (true, ResourceStone, scarceRes)

  (false, ResourceFood, ResourceFood)

proc isResourceCritical*(env: Environment, teamId: int, res: StockpileResource): bool =
  ## Check if a specific resource is at critical levels
  let amount = env.stockpileCount(teamId, res)
  case res
  of ResourceFood: amount < CriticalFoodLevel
  of ResourceWood: amount < CriticalWoodLevel
  of ResourceStone: amount < 3
  of ResourceGold: amount < 2
  of ResourceWater, ResourceNone: false

proc getResourcePriority*(env: Environment, teamId: int): StockpileResource =
  ## Get the highest priority resource to gather based on economic state
  let food = env.stockpileCount(teamId, ResourceFood)
  let wood = env.stockpileCount(teamId, ResourceWood)
  let stone = env.stockpileCount(teamId, ResourceStone)
  let gold = env.stockpileCount(teamId, ResourceGold)

  # Critical levels first
  if food < CriticalFoodLevel:
    return ResourceFood
  if wood < CriticalWoodLevel:
    return ResourceWood

  # Then balance based on flow rates
  let flowRate = getFlowRate(teamId)

  # If food is decreasing fastest, prioritize it
  if flowRate.foodPerStep < -0.1 and food < 15:
    return ResourceFood
  if flowRate.woodPerStep < -0.1 and wood < 15:
    return ResourceWood

  # Default to lowest stockpile
  var lowestRes = ResourceFood
  var lowestAmount = food
  if wood < lowestAmount:
    lowestRes = ResourceWood
    lowestAmount = wood
  if stone < lowestAmount:
    lowestRes = ResourceStone
    lowestAmount = stone
  if gold < lowestAmount:
    lowestRes = ResourceGold

  lowestRes

proc updateEconomy*(controller: Controller, env: Environment, teamId: int) =
  ## Main update function - call once per step
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return

  # Record snapshot every few steps to avoid excessive memory
  if env.currentStep mod 5 == 0:
    recordSnapshot(teamId, env)

  # Update flow rate periodically
  if env.currentStep mod 10 == 0:
    updateFlowRate(teamId)

  # Update bottleneck detection
  updateBottleneck(controller, env, teamId)

proc resetEconomy*() =
  ## Reset all economy state (call on environment reset)
  for i in 0 ..< MapRoomObjectsTeams:
    teamEconomy[i] = EconomyState()
