## econ_audit.nim - Resource economy flow tracker with console dashboard
##
## Gated behind -d:econAudit compile flag. Zero-cost when disabled.
## Tracks all resource flows: gathering, depositing, building costs, unit training,
## market trades, relic gold generation, trade ship gold.
##
## Format: [Step N] TEAM_COLOR: income/spend summary
## Dashboard printed every EconAuditDashboardInterval steps showing per-team:
## - Resource stocks
## - Income/spend rates (per 100 steps)
## - Net flow
## - Total gathered/spent

when defined(econAudit):
  import std/[strformat, os]
  import types
  import items

  const
    EconAuditDashboardInterval* = 100  ## Print dashboard every N steps
    EconAuditWindowSize* = 100         ## Steps to average rates over

  type
    ResourceFlowSource* = enum
      ## Categories of resource income/spending
      rfsGathering       ## Villager gathering from resource nodes
      rfsDeposit         ## Depositing gathered resources at storage
      rfsBuildingCost    ## Building construction costs
      rfsUnitTraining    ## Unit training costs
      rfsTechResearch    ## Technology research costs
      rfsMarketBuy       ## Market purchase (spend gold, gain resource)
      rfsMarketSell      ## Market sale (spend resource, gain gold)
      rfsRelicGold       ## Relic gold generation from monastery
      rfsTradeShip       ## Trade ship (cog) gold generation
      rfsFarmReseed      ## Farm reseed wood cost
      rfsRefund          ## Cancelled queue refunds

    ResourceFlowEvent* = object
      step*: int
      teamId*: int
      resource*: StockpileResource
      amount*: int        ## Positive for income, negative for spending
      source*: ResourceFlowSource

    TeamResourceStats* = object
      ## Per-team resource tracking
      totalGained*: array[StockpileResource, int]
      totalSpent*: array[StockpileResource, int]
      gainedBySource*: array[ResourceFlowSource, array[StockpileResource, int]]
      ## Sliding window for rate calculation
      recentGains*: array[StockpileResource, int]
      recentSpends*: array[StockpileResource, int]
      windowStartStep*: int

    EconAuditState* = object
      enabled*: bool
      verboseMode*: bool          ## Print individual events
      teamStats*: array[MapRoomObjectsTeams, TeamResourceStats]
      lastDashboardStep*: int
      initialized*: bool

  const TeamColorNames: array[8, string] = [
    "RED", "ORANGE", "YELLOW", "GREEN", "MAGENTA", "BLUE", "GRAY", "PINK"
  ]

  var econAuditState*: EconAuditState

  proc teamColorName(teamId: int): string =
    if teamId >= 0 and teamId < TeamColorNames.len:
      TeamColorNames[teamId]
    elif teamId == 8:
      "GOBLIN"
    else:
      "NEUTRAL"

  proc resourceName(res: StockpileResource): string =
    case res
    of ResourceFood: "food"
    of ResourceWood: "wood"
    of ResourceGold: "gold"
    of ResourceStone: "stone"
    of ResourceWater: "water"
    of ResourceNone: "none"

  proc sourceName(source: ResourceFlowSource): string =
    case source
    of rfsGathering: "gathered"
    of rfsDeposit: "deposited"
    of rfsBuildingCost: "building"
    of rfsUnitTraining: "training"
    of rfsTechResearch: "research"
    of rfsMarketBuy: "market_buy"
    of rfsMarketSell: "market_sell"
    of rfsRelicGold: "relic"
    of rfsTradeShip: "trade_ship"
    of rfsFarmReseed: "farm_reseed"
    of rfsRefund: "refund"

  proc initEconAudit*() =
    let verboseEnv = getEnv("TV_ECON_VERBOSE", "")
    econAuditState = EconAuditState(
      enabled: true,
      verboseMode: verboseEnv notin ["", "0", "false"],
      lastDashboardStep: 0,
      initialized: true
    )
    for teamId in 0 ..< MapRoomObjectsTeams:
      econAuditState.teamStats[teamId] = TeamResourceStats(
        windowStartStep: 0
      )

  proc ensureEconAuditInit*() =
    if not econAuditState.initialized:
      initEconAudit()

  proc recordFlow*(teamId: int, res: StockpileResource, amount: int,
                   source: ResourceFlowSource, step: int) =
    ## Record a resource flow event.
    ## Positive amount = income, negative = spending.
    ensureEconAuditInit()
    if teamId < 0 or teamId >= MapRoomObjectsTeams:
      return
    if res == ResourceNone:
      return

    var stats = addr econAuditState.teamStats[teamId]

    # Reset window if needed
    if step - stats.windowStartStep >= EconAuditWindowSize:
      for r in StockpileResource:
        stats.recentGains[r] = 0
        stats.recentSpends[r] = 0
      stats.windowStartStep = step

    if amount > 0:
      stats.totalGained[res] += amount
      stats.recentGains[res] += amount
      stats.gainedBySource[source][res] += amount
    else:
      let absAmount = -amount
      stats.totalSpent[res] += absAmount
      stats.recentSpends[res] += absAmount

    # Verbose mode: print individual events
    if econAuditState.verboseMode:
      let sign = if amount > 0: "+" else: ""
      echo &"[Step {step}] {teamColorName(teamId)} {sign}{amount} {resourceName(res)} ({sourceName(source)})"

  # Convenience procs for specific flow types

  proc recordGathering*(teamId: int, res: StockpileResource, amount: int, step: int) =
    recordFlow(teamId, res, amount, rfsGathering, step)

  proc recordDeposit*(teamId: int, res: StockpileResource, amount: int, step: int) =
    recordFlow(teamId, res, amount, rfsDeposit, step)

  proc recordBuildingCost*(teamId: int, costs: openArray[tuple[res: StockpileResource, count: int]], step: int) =
    for cost in costs:
      recordFlow(teamId, cost.res, -cost.count, rfsBuildingCost, step)

  proc recordTrainingCost*(teamId: int, costs: openArray[tuple[res: StockpileResource, count: int]], step: int) =
    for cost in costs:
      recordFlow(teamId, cost.res, -cost.count, rfsUnitTraining, step)

  proc recordResearchCost*(teamId: int, costs: openArray[tuple[res: StockpileResource, count: int]], step: int) =
    for cost in costs:
      recordFlow(teamId, cost.res, -cost.count, rfsTechResearch, step)

  proc recordMarketBuy*(teamId: int, res: StockpileResource, amount: int,
                        goldCost: int, step: int) =
    ## Buying: gain resource, spend gold
    recordFlow(teamId, res, amount, rfsMarketBuy, step)
    recordFlow(teamId, ResourceGold, -goldCost, rfsMarketBuy, step)

  proc recordMarketSell*(teamId: int, res: StockpileResource, amount: int,
                         goldGained: int, step: int) =
    ## Selling: spend resource, gain gold
    recordFlow(teamId, res, -amount, rfsMarketSell, step)
    recordFlow(teamId, ResourceGold, goldGained, rfsMarketSell, step)

  proc recordRelicGold*(teamId: int, amount: int, step: int) =
    recordFlow(teamId, ResourceGold, amount, rfsRelicGold, step)

  proc recordTradeShipGold*(teamId: int, amount: int, step: int) =
    recordFlow(teamId, ResourceGold, amount, rfsTradeShip, step)

  proc recordFarmReseed*(teamId: int, woodCost: int, step: int) =
    if woodCost > 0:
      recordFlow(teamId, ResourceWood, -woodCost, rfsFarmReseed, step)

  proc recordRefund*(teamId: int, costs: openArray[tuple[res: StockpileResource, count: int]], step: int) =
    for cost in costs:
      recordFlow(teamId, cost.res, cost.count, rfsRefund, step)

  proc printEconDashboard*(env: Environment, step: int) =
    ## Print economy dashboard for all teams.
    echo ""
    echo "======================================================================"
    echo &"  ECONOMY DASHBOARD - Step {step}"
    echo "======================================================================"

    const ResourceOrder = [ResourceFood, ResourceWood, ResourceGold, ResourceStone]

    # Header
    echo "Team       |       Food |       Wood |       Gold |      Stone"
    echo "----------------------------------------------------------------------"

    for teamId in 0 ..< MapRoomObjectsTeams:
      let stats = econAuditState.teamStats[teamId]

      # Current stocks (read from environment)
      var stockLine = &"{teamColorName(teamId):<10} |"
      for res in ResourceOrder:
        let stock = env.teamStockpiles[teamId].counts[res]
        stockLine &= &" {stock:>10} |"
      echo stockLine

      # Calculate rates per 100 steps
      let windowSteps = max(1, step - stats.windowStartStep)
      let rateMultiplier = 100.0 / float(windowSteps)

      # Income rate
      var incomeRate = &"  +income  |"
      for res in ResourceOrder:
        let rate = int(float(stats.recentGains[res]) * rateMultiplier)
        if rate > 0:
          incomeRate &= &" {rate:>+10} |"
        else:
          incomeRate &= &" {\"\":>10} |"
      echo incomeRate

      # Spend rate
      var spendRate = &"  -spend   |"
      for res in ResourceOrder:
        let rate = int(float(stats.recentSpends[res]) * rateMultiplier)
        if rate > 0:
          spendRate &= &" {-rate:>10} |"
        else:
          spendRate &= &" {\"\":>10} |"
      echo spendRate

      # Net flow
      var netFlow = &"  =net     |"
      for res in ResourceOrder:
        let gain = int(float(stats.recentGains[res]) * rateMultiplier)
        let spend = int(float(stats.recentSpends[res]) * rateMultiplier)
        let net = gain - spend
        if net != 0:
          netFlow &= &" {net:>+10} |"
        else:
          netFlow &= &" {\"\":>10} |"
      echo netFlow

      echo "----------------------------------------------------------------------"

    # Totals summary
    echo ""
    echo "======================================================================"
    echo "  TOTALS (All Time)"
    echo "======================================================================"
    echo "Team       |   F-Gained |   W-Gained |   G-Gained |   S-Gained"
    echo "----------------------------------------------------------------------"

    for teamId in 0 ..< MapRoomObjectsTeams:
      let stats = econAuditState.teamStats[teamId]
      var line = &"{teamColorName(teamId):<10} |"
      for res in ResourceOrder:
        line &= &" {stats.totalGained[res]:>10} |"
      echo line

    echo "Team       |    F-Spent |    W-Spent |    G-Spent |    S-Spent"
    echo "----------------------------------------------------------------------"

    for teamId in 0 ..< MapRoomObjectsTeams:
      let stats = econAuditState.teamStats[teamId]
      var line = &"{teamColorName(teamId):<10} |"
      for res in ResourceOrder:
        line &= &" {stats.totalSpent[res]:>10} |"
      echo line

    # Income source breakdown (optional detailed view)
    let detailedEnv = getEnv("TV_ECON_DETAILED", "")
    if detailedEnv notin ["", "0", "false"]:
      echo ""
      echo "======================================================================"
      echo "  INCOME BY SOURCE"
      echo "======================================================================"
      for teamId in 0 ..< MapRoomObjectsTeams:
        let stats = econAuditState.teamStats[teamId]
        echo &"\n{teamColorName(teamId)}:"
        for source in ResourceFlowSource:
          var hasData = false
          for res in ResourceOrder:
            if stats.gainedBySource[source][res] > 0:
              hasData = true
              break
          if hasData:
            var line = &"  {sourceName(source):<12}:"
            for res in ResourceOrder:
              let amt = stats.gainedBySource[source][res]
              if amt > 0:
                line &= &" {resourceName(res)}={amt}"
            echo line

    echo "======================================================================\n"

  proc maybePrintEconDashboard*(env: Environment, step: int) =
    ## Print dashboard every EconAuditDashboardInterval steps.
    ensureEconAuditInit()
    if step > 0 and step mod EconAuditDashboardInterval == 0 and
       step != econAuditState.lastDashboardStep:
      econAuditState.lastDashboardStep = step
      printEconDashboard(env, step)

  proc resetEconAudit*() =
    ## Reset econ audit state for game reset.
    for teamId in 0 ..< MapRoomObjectsTeams:
      econAuditState.teamStats[teamId] = TeamResourceStats(
        windowStartStep: 0
      )
    econAuditState.lastDashboardStep = 0
