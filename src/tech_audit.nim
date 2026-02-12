## tech_audit.nim - Technology research and upgrade tracking
##
## Gated behind -d:techAudit compile flag. Zero-cost when disabled.
## Logs technology research events with cost details and tracks
## upgrade application to units.
##
## Format: [Step N] Team X researched Y (cost: Z)
## Periodic summary: Per-team tech status every TechAuditSummaryInterval steps

when defined(techAudit):
  import std/[strformat, tables, strutils]
  import types
  import constants
  import envconfig

  const
    TechAuditSummaryInterval* = 100  ## Print tech status every N steps

  type
    TechResearchEvent* = object
      step*: int
      teamId*: int
      techName*: string
      costs*: seq[tuple[resource: string, amount: int]]

    UpgradeApplicationEvent* = object
      step*: int
      teamId*: int
      upgradeName*: string
      unitsAffected*: int
      attackDelta*: int
      armorDelta*: int
      hpDelta*: int

    TechAuditState* = object
      researchEvents*: seq[TechResearchEvent]
      upgradeEvents*: seq[UpgradeApplicationEvent]
      totalSpentByTeam*: array[MapRoomObjectsTeams, Table[string, int]]
      lastSummaryStep*: int

  const TeamColorNames: array[8, string] = [
    "RED", "ORANGE", "YELLOW", "GREEN", "MAGENTA", "BLUE", "GRAY", "PINK"
  ]

  var techAuditState*: TechAuditState
  var techAuditInitialized = false

  proc teamColorName(teamId: int): string =
    if teamId >= 0 and teamId < TeamColorNames.len:
      TeamColorNames[teamId]
    elif teamId == 8:
      "GOBLIN"
    else:
      "NEUTRAL"

  proc initTechAudit*() =
    techAuditState = TechAuditState(
      researchEvents: @[],
      upgradeEvents: @[],
      lastSummaryStep: 0
    )
    for teamId in 0 ..< MapRoomObjectsTeams:
      techAuditState.totalSpentByTeam[teamId] = initStringIntTable()
    techAuditInitialized = true

  proc ensureTechAuditInit*() =
    if not techAuditInitialized:
      initTechAudit()

  proc formatCosts(costs: seq[tuple[resource: string, amount: int]]): string =
    var parts: seq[string]
    for cost in costs:
      parts.add(&"{cost.amount} {cost.resource}")
    if parts.len > 0:
      result = parts.join(", ")
    else:
      result = "free"

  proc logTechResearch*(teamId: int, techName: string, step: int,
                        costs: seq[tuple[resource: string, amount: int]]) =
    ensureTechAuditInit()
    let ev = TechResearchEvent(
      step: step,
      teamId: teamId,
      techName: techName,
      costs: costs
    )
    techAuditState.researchEvents.add(ev)

    # Track total spent
    for cost in costs:
      if cost.resource notin techAuditState.totalSpentByTeam[teamId]:
        techAuditState.totalSpentByTeam[teamId][cost.resource] = 0
      techAuditState.totalSpentByTeam[teamId][cost.resource] += cost.amount

    echo &"[Step {step}] {teamColorName(teamId)} researched {techName} (cost: {formatCosts(costs)})"

  proc logBlacksmithUpgrade*(teamId: int, upgradeType: BlacksmithUpgradeType,
                              newLevel: int, step: int) =
    let costMultiplier = newLevel  # Level just increased, so cost was based on previous level + 1 = newLevel
    let foodCost = BlacksmithUpgradeFoodCost * costMultiplier
    let goldCost = BlacksmithUpgradeGoldCost * costMultiplier
    let techName = &"Blacksmith {upgradeType} Level {newLevel}"
    let costs = @[("food", foodCost), ("gold", goldCost)]
    logTechResearch(teamId, techName, step, costs)

  proc logUniversityTech*(teamId: int, techType: UniversityTechType, step: int) =
    let techIndex = ord(techType) + 1
    let foodCost = UniversityTechFoodCost * techIndex
    let goldCost = UniversityTechGoldCost * techIndex
    let woodCost = UniversityTechWoodCost * techIndex
    let techName = &"University {techType}"
    let costs = @[("food", foodCost), ("gold", goldCost), ("wood", woodCost)]
    logTechResearch(teamId, techName, step, costs)

  proc logCastleTech*(teamId: int, techType: CastleTechType, isImperial: bool, step: int) =
    let foodCost = if isImperial: CastleTechImperialFoodCost else: CastleTechFoodCost
    let goldCost = if isImperial: CastleTechImperialGoldCost else: CastleTechGoldCost
    let techName = &"Castle {techType}"
    let costs = @[("food", foodCost), ("gold", goldCost)]
    logTechResearch(teamId, techName, step, costs)

  proc logUnitUpgrade*(teamId: int, upgradeType: UnitUpgradeType, step: int,
                       costs: seq[tuple[res: StockpileResource, count: int]]) =
    let techName = &"Unit Upgrade {upgradeType}"
    var formattedCosts: seq[tuple[resource: string, amount: int]]
    for cost in costs:
      var resName: string
      case cost.res
      of ResourceFood: resName = "food"
      of ResourceWood: resName = "wood"
      of ResourceGold: resName = "gold"
      of ResourceStone: resName = "stone"
      of ResourceWater: resName = "water"
      of ResourceNone: resName = "none"
      formattedCosts.add((resName, cost.count))
    logTechResearch(teamId, techName, step, formattedCosts)

  proc logUpgradeApplication*(teamId: int, upgradeName: string, unitsAffected: int,
                               attackDelta, armorDelta, hpDelta: int, step: int) =
    ensureTechAuditInit()
    let ev = UpgradeApplicationEvent(
      step: step,
      teamId: teamId,
      upgradeName: upgradeName,
      unitsAffected: unitsAffected,
      attackDelta: attackDelta,
      armorDelta: armorDelta,
      hpDelta: hpDelta
    )
    techAuditState.upgradeEvents.add(ev)

    var deltaStr = ""
    if attackDelta != 0:
      deltaStr &= &" attack={attackDelta:+d}"
    if armorDelta != 0:
      deltaStr &= &" armor={armorDelta:+d}"
    if hpDelta != 0:
      deltaStr &= &" hp={hpDelta:+d}"
    if deltaStr == "":
      deltaStr = " (stat bonuses applied)"

    echo &"[Step {step}] {teamColorName(teamId)} upgrade applied: {upgradeName} to {unitsAffected} units{deltaStr}"

  proc printTeamTechStatus*(env: Environment, teamId: int) =
    ## Print detailed tech status for a team.
    echo &"  Team {teamId} ({teamColorName(teamId)}):"

    # Blacksmith upgrades
    var bsUpgrades: seq[string]
    for upType in BlacksmithUpgradeType:
      let level = env.teamBlacksmithUpgrades[teamId].levels[upType]
      if level > 0:
        bsUpgrades.add(&"{upType} L{level}")
    if bsUpgrades.len > 0:
      echo &"    Blacksmith: {bsUpgrades.join(\", \")}"

    # University techs
    var uniTechs: seq[string]
    for techType in UniversityTechType:
      if env.teamUniversityTechs[teamId].researched[techType]:
        uniTechs.add($techType)
    if uniTechs.len > 0:
      echo &"    University: {uniTechs.join(\", \")}"

    # Castle techs
    var castleTechs: seq[string]
    for techType in CastleTechType:
      if env.teamCastleTechs[teamId].researched[techType]:
        castleTechs.add($techType)
    if castleTechs.len > 0:
      echo &"    Castle: {castleTechs.join(\", \")}"

    # Unit upgrades
    var unitUpgrades: seq[string]
    for upType in UnitUpgradeType:
      if env.teamUnitUpgrades[teamId].researched[upType]:
        unitUpgrades.add($upType)
    if unitUpgrades.len > 0:
      echo &"    Units: {unitUpgrades.join(\", \")}"

    # Economy techs
    var econTechs: seq[string]
    for techType in EconomyTechType:
      if env.teamEconomyTechs[teamId].researched[techType]:
        econTechs.add($techType)
    if econTechs.len > 0:
      echo &"    Economy: {econTechs.join(\", \")}"

    # Total spent on research
    if techAuditState.totalSpentByTeam[teamId].len > 0:
      var spentParts: seq[string]
      for res, amount in techAuditState.totalSpentByTeam[teamId]:
        spentParts.add(&"{amount} {res}")
      echo &"    Total spent: {spentParts.join(\", \")}"

  proc maybePrintTechSummary*(env: Environment, step: int) =
    ## Print per-team tech status every TechAuditSummaryInterval steps.
    ensureTechAuditInit()
    if step > 0 and step mod TechAuditSummaryInterval == 0 and
       step != techAuditState.lastSummaryStep:
      techAuditState.lastSummaryStep = step
      echo &"=== Tech Status at Step {step} ==="
      for teamId in 0 ..< MapRoomObjectsTeams:
        printTeamTechStatus(env, teamId)
      echo "================================"

  proc resetTechAudit*() =
    ## Reset tech audit state for game reset.
    techAuditState.researchEvents.setLen(0)
    techAuditState.upgradeEvents.setLen(0)
    techAuditState.lastSummaryStep = 0
    for teamId in 0 ..< MapRoomObjectsTeams:
      techAuditState.totalSpentByTeam[teamId].clear()
