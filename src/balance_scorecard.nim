## balance_scorecard.nim - Game balance metrics instrument
##
## Collects and reports key game balance metrics after each match:
## - Per-team win rates
## - Resource gathering curves over time
## - Military unit composition timelines
## - Technology progression tracking
## - Idle villager percentages
## - Economy-to-military spending ratios
##
## Output: Structured JSON and optional human-readable summary.
##
## Controlled via environment variables:
##   TV_SCORECARD_ENABLED  - Enable scorecard collection (0 or unset = disabled)
##   TV_SCORECARD_INTERVAL - Sample interval in steps (default: 50)
##   TV_SCORECARD_DIR      - Output directory (default: ./scorecards/)

import std/[json, os, times, strformat, strutils, math]
import types, items, environment

const
  DefaultSampleInterval = 50
  DefaultOutputDir = "./scorecards/"

type
  ResourceSample* = object
    ## Resource snapshot at a point in time
    step*: int
    food*: int
    wood*: int
    gold*: int
    stone*: int

  UnitComposition* = object
    ## Unit counts by category at a point in time
    step*: int
    villagers*: int
    infantry*: int      # ManAtArms, LongSwordsman, Champion, etc.
    archers*: int       # Archer, Crossbowman, Arbalester, Longbowman, etc.
    cavalry*: int       # Scout, Knight, LightCavalry, Hussar, Cataphract, etc.
    siege*: int         # BatteringRam, Mangonel, Trebuchet
    monks*: int
    unique*: int        # Castle unique units
    total*: int

  TechProgress* = object
    ## Technology research state at a point in time
    step*: int
    blacksmithLevels*: int    # Sum of all blacksmith upgrade levels (max 15)
    universityTechs*: int     # Count of researched university techs
    castleTechs*: int         # Count of researched castle techs
    unitUpgrades*: int        # Count of researched unit upgrades

  SpendingRecord* = object
    ## Cumulative spending tracking
    economySpend*: int        # Resources spent on economy (buildings, villagers)
    militarySpend*: int       # Resources spent on military (units, upgrades)

  TeamScorecard* = object
    ## Complete metrics for one team across the match
    teamId*: int

    # Time series data
    resourceCurve*: seq[ResourceSample]
    unitTimeline*: seq[UnitComposition]
    techTimeline*: seq[TechProgress]

    # Final state
    finalResources*: ResourceSample
    finalUnits*: UnitComposition
    finalTech*: TechProgress

    # Match outcome
    won*: bool
    finalScore*: int          # Composite score
    aliveUnits*: int
    deadUnits*: int
    buildingsBuilt*: int
    territoryTiles*: int

    # Efficiency metrics
    idleVillagerPct*: float32   # Percentage of villagers that were idle
    economyMilitaryRatio*: float32  # Economy spend / total spend

    # Spending
    spending*: SpendingRecord

  BalanceScorecard* = object
    ## Complete match scorecard
    matchId*: string
    seed*: int
    startTime*: DateTime
    endTime*: DateTime
    totalSteps*: int
    victoryWinner*: int
    victoryCondition*: string

    teams*: array[MapRoomObjectsTeams, TeamScorecard]

    # Aggregate balance metrics
    winDistribution*: array[MapRoomObjectsTeams, int]  # Cumulative wins (for multi-match)
    resourceParity*: float32      # Gini coefficient of final resources
    militaryBalance*: float32     # Variance in military strength
    techParity*: float32          # Variance in tech progression

  ScorecardCollector* = object
    ## Stateful collector that samples during gameplay
    enabled*: bool
    sampleInterval*: int
    outputDir*: string
    currentScorecard*: BalanceScorecard
    lastSampleStep*: int
    initialized*: bool

    # Track spending between samples
    lastTeamResources*: array[MapRoomObjectsTeams, TeamStockpile]

    # Track villager activity (steps since last action)
    villagerIdleSteps*: array[MapAgents, int]
    villagerTotalSteps*: array[MapAgents, int]

var collector*: ScorecardCollector

# ---------------------------------------------------------------------------
# Initialization
# ---------------------------------------------------------------------------

proc initCollector*() =
  ## Initialize scorecard collector from environment variables.
  let enabledStr = getEnv("TV_SCORECARD_ENABLED", "0")
  collector.enabled = enabledStr == "1" or enabledStr.toLowerAscii == "true"

  let intervalStr = getEnv("TV_SCORECARD_INTERVAL", $DefaultSampleInterval)
  collector.sampleInterval = try: parseInt(intervalStr) except ValueError: DefaultSampleInterval

  collector.outputDir = getEnv("TV_SCORECARD_DIR", DefaultOutputDir)

  if collector.enabled:
    createDir(collector.outputDir)

  collector.initialized = true

proc ensureInit() =
  if not collector.initialized:
    initCollector()

proc startMatch*(env: Environment, seed: int) =
  ## Call at match start to initialize scorecard collection.
  ensureInit()
  if not collector.enabled:
    return

  collector.currentScorecard = BalanceScorecard()
  collector.currentScorecard.seed = seed
  collector.currentScorecard.startTime = now()
  collector.currentScorecard.matchId = $seed & "_" & now().format("yyyyMMddHHmmss")
  collector.lastSampleStep = -1

  # Initialize team scorecards
  for teamId in 0 ..< MapRoomObjectsTeams:
    collector.currentScorecard.teams[teamId].teamId = teamId
    collector.currentScorecard.teams[teamId].resourceCurve = @[]
    collector.currentScorecard.teams[teamId].unitTimeline = @[]
    collector.currentScorecard.teams[teamId].techTimeline = @[]

  # Initialize resource tracking
  for teamId in 0 ..< MapRoomObjectsTeams:
    for res in StockpileResource:
      collector.lastTeamResources[teamId].counts[res] = env.teamStockpiles[teamId].counts[res]

  # Initialize villager tracking
  for i in 0 ..< MapAgents:
    collector.villagerIdleSteps[i] = 0
    collector.villagerTotalSteps[i] = 0

# ---------------------------------------------------------------------------
# Sampling helpers
# ---------------------------------------------------------------------------

proc classifyUnit(unitClass: AgentUnitClass): string =
  ## Classify unit into category for composition tracking.
  case unitClass
  of UnitVillager: "villager"
  of UnitManAtArms, UnitLongSwordsman, UnitChampion, UnitWoadRaider,
     UnitTeutonicKnight, UnitHuskarl: "infantry"
  of UnitArcher, UnitCrossbowman, UnitArbalester, UnitLongbowman, UnitJanissary: "archers"
  of UnitScout, UnitKnight, UnitLightCavalry, UnitHussar, UnitCataphract, UnitMameluke: "cavalry"
  of UnitBatteringRam, UnitMangonel, UnitTrebuchet, UnitScorpion: "siege"
  of UnitMonk: "monks"
  of UnitSamurai: "unique"
  of UnitGoblin, UnitBoat, UnitTradeCog, UnitKing, UnitGalley, UnitFireShip: "other"

proc sampleResources(env: Environment, teamId: int, step: int): ResourceSample =
  result.step = step
  result.food = env.teamStockpiles[teamId].counts[ResourceFood]
  result.wood = env.teamStockpiles[teamId].counts[ResourceWood]
  result.gold = env.teamStockpiles[teamId].counts[ResourceGold]
  result.stone = env.teamStockpiles[teamId].counts[ResourceStone]

proc sampleUnitComposition(env: Environment, teamId: int, step: int): UnitComposition =
  result.step = step

  for agent in env.agents:
    if agent.isNil:
      continue
    if agent.getTeamId() != teamId:
      continue
    if env.terminated[agent.agentId] != 0.0:
      continue  # Dead

    inc result.total
    case classifyUnit(agent.unitClass)
    of "villager": inc result.villagers
    of "infantry": inc result.infantry
    of "archers": inc result.archers
    of "cavalry": inc result.cavalry
    of "siege": inc result.siege
    of "monks": inc result.monks
    of "unique": inc result.unique
    else: discard

proc sampleTechProgress(env: Environment, teamId: int, step: int): TechProgress =
  result.step = step

  # Sum blacksmith levels (5 lines, 0-3 each = max 15)
  for upgradeType in BlacksmithUpgradeType:
    result.blacksmithLevels += env.teamBlacksmithUpgrades[teamId].levels[upgradeType]

  # Count university techs
  for techType in UniversityTechType:
    if env.teamUniversityTechs[teamId].researched[techType]:
      inc result.universityTechs

  # Count castle techs (each team has 2 available)
  for techType in CastleTechType:
    if env.teamCastleTechs[teamId].researched[techType]:
      inc result.castleTechs

  # Count unit upgrades
  for upgradeType in UnitUpgradeType:
    if env.teamUnitUpgrades[teamId].researched[upgradeType]:
      inc result.unitUpgrades

proc countBuildings(env: Environment, teamId: int): int =
  ## Count standing buildings owned by a team.
  for kind in ThingKind:
    if kind in {Altar, TownCenter, House, Barracks, ArcheryRange, Stable,
                Blacksmith, Market, Monastery, University, Castle, Wonder,
                SiegeWorkshop, MangonelWorkshop, TrebuchetWorkshop,
                Dock, Outpost, GuardTower, Wall, Door, Mill, Granary,
                LumberCamp, Quarry, MiningCamp, WeavingLoom, ClayOven,
                Lantern, Temple}:
      for thing in env.thingsByKind[kind]:
        if not thing.isNil and thing.teamId == teamId and thing.hp > 0:
          inc result

proc updateSpending(env: Environment, teamId: int) =
  ## Track resource spending between samples.
  # This is a simplified model: resource decreases = spending
  # In reality we'd need to track actual transactions
  var totalDelta = 0

  for res in [ResourceFood, ResourceWood, ResourceGold, ResourceStone]:
    let current = env.teamStockpiles[teamId].counts[res]
    let previous = collector.lastTeamResources[teamId].counts[res]
    let delta = previous - current
    if delta > 0:
      totalDelta += delta
    collector.lastTeamResources[teamId].counts[res] = current

  # Rough heuristic: if villager count increased, it's economy spend
  # Otherwise assume military
  # This is a simplification - a proper implementation would hook into actual build/train events
  collector.currentScorecard.teams[teamId].spending.economySpend += totalDelta div 2
  collector.currentScorecard.teams[teamId].spending.militarySpend += totalDelta div 2

proc updateVillagerIdleness(env: Environment) =
  ## Track villager activity for idle percentage calculation.
  ## Villagers with inventory items are considered "active" (gathering/delivering).
  for agent in env.agents:
    if agent.isNil:
      continue
    if env.terminated[agent.agentId] != 0.0:
      continue
    if agent.unitClass != UnitVillager:
      continue

    let agentId = agent.agentId
    inc collector.villagerTotalSteps[agentId]

    # Consider villager idle if they have no inventory items
    # (not carrying resources = not actively gathering/delivering)
    if agent.inventory.len == 0:
      inc collector.villagerIdleSteps[agentId]

# ---------------------------------------------------------------------------
# Sampling entry point
# ---------------------------------------------------------------------------

proc maybeSample*(env: Environment) =
  ## Called each step; samples if interval matches.
  ensureInit()
  if not collector.enabled:
    return

  let step = env.currentStep

  # Update villager tracking every step
  updateVillagerIdleness(env)

  # Sample at intervals
  if step - collector.lastSampleStep >= collector.sampleInterval:
    collector.lastSampleStep = step

    for teamId in 0 ..< MapRoomObjectsTeams:
      collector.currentScorecard.teams[teamId].resourceCurve.add(
        sampleResources(env, teamId, step))
      collector.currentScorecard.teams[teamId].unitTimeline.add(
        sampleUnitComposition(env, teamId, step))
      collector.currentScorecard.teams[teamId].techTimeline.add(
        sampleTechProgress(env, teamId, step))

      updateSpending(env, teamId)

# ---------------------------------------------------------------------------
# Final scorecard computation
# ---------------------------------------------------------------------------

proc computeFinalMetrics(env: Environment) =
  ## Compute final match metrics.
  let step = env.currentStep

  for teamId in 0 ..< MapRoomObjectsTeams:
    var team = addr collector.currentScorecard.teams[teamId]

    # Final state samples
    team.finalResources = sampleResources(env, teamId, step)
    team.finalUnits = sampleUnitComposition(env, teamId, step)
    team.finalTech = sampleTechProgress(env, teamId, step)

    # Outcome
    team.won = (env.victoryWinner == teamId)
    team.aliveUnits = team.finalUnits.total
    team.buildingsBuilt = countBuildings(env, teamId)

    # Count dead units
    let startIdx = teamId * MapAgentsPerTeam
    let endIdx = min(startIdx + MapAgentsPerTeam, env.agents.len)
    for i in startIdx ..< endIdx:
      if i < env.agents.len and not env.agents[i].isNil:
        if env.terminated[i] != 0.0:
          inc team.deadUnits

    # Territory
    let territory = scoreTerritory(env)
    team.territoryTiles = territory.teamTiles[teamId]

    # Composite score (same formula as behavior_balance.nim)
    team.finalScore = team.finalResources.food + team.finalResources.wood +
                      team.finalResources.gold + team.finalResources.stone +
                      team.territoryTiles + team.aliveUnits * 10

    # Idle villager percentage
    var totalVillagerSteps = 0
    var totalIdleSteps = 0
    for i in startIdx ..< endIdx:
      if collector.villagerTotalSteps[i] > 0:
        totalVillagerSteps += collector.villagerTotalSteps[i]
        totalIdleSteps += collector.villagerIdleSteps[i]

    if totalVillagerSteps > 0:
      team.idleVillagerPct = float32(totalIdleSteps) / float32(totalVillagerSteps) * 100.0

    # Economy/military ratio
    let totalSpend = team.spending.economySpend + team.spending.militarySpend
    if totalSpend > 0:
      team.economyMilitaryRatio = float32(team.spending.economySpend) / float32(totalSpend)

proc computeBalanceMetrics() =
  ## Compute aggregate balance metrics across all teams.
  var sc = addr collector.currentScorecard

  # Resource parity (Gini coefficient of final total resources)
  var resources: array[MapRoomObjectsTeams, float64]
  var totalRes = 0.0
  for teamId in 0 ..< MapRoomObjectsTeams:
    let r = sc.teams[teamId].finalResources
    resources[teamId] = float64(r.food + r.wood + r.gold + r.stone)
    totalRes += resources[teamId]

  if totalRes > 0:
    # Simplified Gini: mean absolute difference / (2 * mean)
    var sumDiff = 0.0
    for i in 0 ..< MapRoomObjectsTeams:
      for j in 0 ..< MapRoomObjectsTeams:
        sumDiff += abs(resources[i] - resources[j])
    let meanRes = totalRes / float64(MapRoomObjectsTeams)
    sc.resourceParity = float32(1.0 - sumDiff / (2.0 * float64(MapRoomObjectsTeams * MapRoomObjectsTeams) * meanRes))

  # Military balance (coefficient of variation of military unit counts)
  var military: array[MapRoomObjectsTeams, float64]
  var totalMil = 0.0
  for teamId in 0 ..< MapRoomObjectsTeams:
    let u = sc.teams[teamId].finalUnits
    military[teamId] = float64(u.infantry + u.archers + u.cavalry + u.siege + u.monks + u.unique)
    totalMil += military[teamId]

  if totalMil > 0:
    let meanMil = totalMil / float64(MapRoomObjectsTeams)
    var variance = 0.0
    for teamId in 0 ..< MapRoomObjectsTeams:
      variance += (military[teamId] - meanMil) * (military[teamId] - meanMil)
    variance /= float64(MapRoomObjectsTeams)
    let stdDev = sqrt(variance)
    sc.militaryBalance = float32(1.0 - min(1.0, stdDev / meanMil))  # 1.0 = perfect balance

  # Tech parity (similar approach for tech progress)
  var techs: array[MapRoomObjectsTeams, float64]
  var totalTech = 0.0
  for teamId in 0 ..< MapRoomObjectsTeams:
    let t = sc.teams[teamId].finalTech
    techs[teamId] = float64(t.blacksmithLevels + t.universityTechs * 2 + t.castleTechs * 3 + t.unitUpgrades * 2)
    totalTech += techs[teamId]

  if totalTech > 0:
    let meanTech = totalTech / float64(MapRoomObjectsTeams)
    var variance = 0.0
    for teamId in 0 ..< MapRoomObjectsTeams:
      variance += (techs[teamId] - meanTech) * (techs[teamId] - meanTech)
    variance /= float64(MapRoomObjectsTeams)
    let stdDev = sqrt(variance)
    sc.techParity = float32(1.0 - min(1.0, stdDev / max(1.0, meanTech)))

# ---------------------------------------------------------------------------
# JSON output
# ---------------------------------------------------------------------------

proc resourceSampleToJson(s: ResourceSample): JsonNode =
  %*{"step": s.step, "food": s.food, "wood": s.wood, "gold": s.gold, "stone": s.stone}

proc unitCompositionToJson(u: UnitComposition): JsonNode =
  %*{
    "step": u.step,
    "villagers": u.villagers,
    "infantry": u.infantry,
    "archers": u.archers,
    "cavalry": u.cavalry,
    "siege": u.siege,
    "monks": u.monks,
    "unique": u.unique,
    "total": u.total
  }

proc techProgressToJson(t: TechProgress): JsonNode =
  %*{
    "step": t.step,
    "blacksmith_levels": t.blacksmithLevels,
    "university_techs": t.universityTechs,
    "castle_techs": t.castleTechs,
    "unit_upgrades": t.unitUpgrades
  }

proc teamScorecardToJson(t: TeamScorecard): JsonNode =
  var resourceCurve = newJArray()
  for s in t.resourceCurve:
    resourceCurve.add(resourceSampleToJson(s))

  var unitTimeline = newJArray()
  for u in t.unitTimeline:
    unitTimeline.add(unitCompositionToJson(u))

  var techTimeline = newJArray()
  for p in t.techTimeline:
    techTimeline.add(techProgressToJson(p))

  %*{
    "team_id": t.teamId,
    "won": t.won,
    "final_score": t.finalScore,
    "alive_units": t.aliveUnits,
    "dead_units": t.deadUnits,
    "buildings_built": t.buildingsBuilt,
    "territory_tiles": t.territoryTiles,
    "idle_villager_pct": t.idleVillagerPct,
    "economy_military_ratio": t.economyMilitaryRatio,
    "spending": {
      "economy": t.spending.economySpend,
      "military": t.spending.militarySpend
    },
    "final_resources": resourceSampleToJson(t.finalResources),
    "final_units": unitCompositionToJson(t.finalUnits),
    "final_tech": techProgressToJson(t.finalTech),
    "resource_curve": resourceCurve,
    "unit_timeline": unitTimeline,
    "tech_timeline": techTimeline
  }

proc scorecardToJson*(sc: BalanceScorecard): JsonNode =
  var teams = newJArray()
  for teamId in 0 ..< MapRoomObjectsTeams:
    teams.add(teamScorecardToJson(sc.teams[teamId]))

  var winDist = newJArray()
  for teamId in 0 ..< MapRoomObjectsTeams:
    winDist.add(%sc.winDistribution[teamId])

  %*{
    "match_id": sc.matchId,
    "seed": sc.seed,
    "start_time": $sc.startTime,
    "end_time": $sc.endTime,
    "total_steps": sc.totalSteps,
    "victory_winner": sc.victoryWinner,
    "victory_condition": sc.victoryCondition,
    "balance_metrics": {
      "resource_parity": sc.resourceParity,
      "military_balance": sc.militaryBalance,
      "tech_parity": sc.techParity
    },
    "win_distribution": winDist,
    "teams": teams
  }

# ---------------------------------------------------------------------------
# Human-readable summary
# ---------------------------------------------------------------------------

proc generateSummary*(sc: BalanceScorecard): string =
  ## Generate human-readable balance summary.
  var lines: seq[string] = @[]

  lines.add("=" .repeat(80))
  lines.add("GAME BALANCE SCORECARD")
  lines.add("=" .repeat(80))
  lines.add(&"Match: {sc.matchId} | Seed: {sc.seed}")
  lines.add(&"Duration: {sc.totalSteps} steps")
  lines.add(&"Winner: Team {sc.victoryWinner}" & (if sc.victoryWinner >= 0: " (" & sc.victoryCondition & ")" else: " (no winner)"))
  lines.add("-" .repeat(80))

  # Balance metrics
  lines.add("")
  lines.add("BALANCE METRICS:")
  lines.add(&"  Resource Parity:  {sc.resourceParity * 100:5.1f}% (100% = perfect equality)")
  lines.add(&"  Military Balance: {sc.militaryBalance * 100:5.1f}% (100% = equal strength)")
  lines.add(&"  Tech Parity:      {sc.techParity * 100:5.1f}% (100% = equal progress)")

  # Per-team summary
  lines.add("")
  lines.add("PER-TEAM SUMMARY:")
  lines.add("  Team  Score  Alive  Dead  Buildings  Territory  Idle%  Econ/Mil  Won")
  lines.add("  " & "-" .repeat(72))

  for teamId in 0 ..< MapRoomObjectsTeams:
    let t = sc.teams[teamId]
    let wonStr = if t.won: "YES" else: "   "
    lines.add(&"  {teamId:>4}  {t.finalScore:>5}  {t.aliveUnits:>5}  {t.deadUnits:>4}  {t.buildingsBuilt:>9}  {t.territoryTiles:>9}  {t.idleVillagerPct:>5.1f}  {t.economyMilitaryRatio:>7.2f}  {wonStr}")

  # Final resources
  lines.add("")
  lines.add("FINAL RESOURCES:")
  lines.add("  Team   Food   Wood   Gold  Stone   Total")
  lines.add("  " & "-" .repeat(44))

  for teamId in 0 ..< MapRoomObjectsTeams:
    let r = sc.teams[teamId].finalResources
    let total = r.food + r.wood + r.gold + r.stone
    lines.add(&"  {teamId:>4}  {r.food:>5}  {r.wood:>5}  {r.gold:>5}  {r.stone:>5}  {total:>6}")

  # Final unit composition
  lines.add("")
  lines.add("FINAL UNIT COMPOSITION:")
  lines.add("  Team  Vill  Inf  Arch  Cav  Siege  Monk  Uniq  Total")
  lines.add("  " & "-" .repeat(56))

  for teamId in 0 ..< MapRoomObjectsTeams:
    let u = sc.teams[teamId].finalUnits
    lines.add(&"  {teamId:>4}  {u.villagers:>4}  {u.infantry:>3}  {u.archers:>4}  {u.cavalry:>3}  {u.siege:>5}  {u.monks:>4}  {u.unique:>4}  {u.total:>5}")

  # Tech progress
  lines.add("")
  lines.add("TECHNOLOGY PROGRESS:")
  lines.add("  Team  Blacksmith  University  Castle  UnitUpg")
  lines.add("  " & "-" .repeat(48))

  for teamId in 0 ..< MapRoomObjectsTeams:
    let t = sc.teams[teamId].finalTech
    lines.add(&"  {teamId:>4}  {t.blacksmithLevels:>10}  {t.universityTechs:>10}  {t.castleTechs:>6}  {t.unitUpgrades:>7}")

  lines.add("=" .repeat(80))

  lines.join("\n")

# ---------------------------------------------------------------------------
# Match end - finalize and write scorecard
# ---------------------------------------------------------------------------

proc endMatch*(env: Environment) =
  ## Call at match end to finalize and write scorecard.
  ensureInit()
  if not collector.enabled:
    return

  collector.currentScorecard.endTime = now()
  collector.currentScorecard.totalSteps = env.currentStep
  collector.currentScorecard.victoryWinner = env.victoryWinner
  collector.currentScorecard.victoryCondition = $env.config.victoryCondition

  # Compute all final metrics
  computeFinalMetrics(env)
  computeBalanceMetrics()

  # Update win distribution
  if env.victoryWinner >= 0 and env.victoryWinner < MapRoomObjectsTeams:
    inc collector.currentScorecard.winDistribution[env.victoryWinner]

  # Write JSON
  let jsonFilename = collector.outputDir / &"scorecard_{collector.currentScorecard.matchId}.json"
  writeFile(jsonFilename, $scorecardToJson(collector.currentScorecard))

  # Write summary
  let summaryFilename = collector.outputDir / &"scorecard_{collector.currentScorecard.matchId}.txt"
  writeFile(summaryFilename, generateSummary(collector.currentScorecard))

proc getLastScorecard*(): BalanceScorecard =
  ## Get the most recently collected scorecard (for testing).
  collector.currentScorecard
