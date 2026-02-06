## tumor_audit.nim - Tumor spread and biome infection audit logging
##
## Gated behind -d:tumorAudit compile flag. Zero-cost when disabled.
## Tracks tumors spawned, total count, damage dealt, tiles spread, and spread rate.
## Prints periodic tumor reports to console every N steps.
##
## Included by environment.nim — types, items, spatial_index, strutils, os are in scope.

when defined(tumorAudit):
  import std/[strutils, os]

  type
    TumorAuditState* = object
      reportInterval*: int
      lastReportStep*: int
      ## Cumulative totals (lifetime)
      totalSpawned*: int          ## Total tumors spawned by spawners
      totalBranched*: int         ## Total tumors created by branching
      totalDamageDealt*: int      ## Total damage dealt to agents
      totalAgentKills*: int       ## Agents killed by tumors
      totalPredatorKills*: int    ## Bears/wolves killed by tumors
      totalTumorsDestroyed*: int  ## Tumors destroyed via mutual kill
      ## Per-interval counters (reset each report)
      intervalSpawned*: int
      intervalBranched*: int
      intervalDamageDealt*: int
      intervalAgentKills*: int
      intervalPredatorKills*: int
      intervalTumorsDestroyed*: int

  var tumorAudit*: TumorAuditState
  var tumorAuditInitialized = false

  proc initTumorAudit*() =
    tumorAudit = TumorAuditState(
      reportInterval: max(1, parseEnvInt("TV_TUMOR_REPORT_INTERVAL", 100)),
      lastReportStep: 0
    )
    tumorAuditInitialized = true

  proc ensureTumorAuditInit*() =
    if not tumorAuditInitialized:
      initTumorAudit()

  proc recordTumorSpawned*() =
    ensureTumorAuditInit()
    inc tumorAudit.totalSpawned
    inc tumorAudit.intervalSpawned

  proc recordTumorBranched*() =
    ensureTumorAuditInit()
    inc tumorAudit.totalBranched
    inc tumorAudit.intervalBranched

  proc recordTumorDamage*(killed: bool) =
    ensureTumorAuditInit()
    inc tumorAudit.totalDamageDealt
    inc tumorAudit.intervalDamageDealt
    if killed:
      inc tumorAudit.totalAgentKills
      inc tumorAudit.intervalAgentKills

  proc recordTumorPredatorKill*() =
    ensureTumorAuditInit()
    inc tumorAudit.totalPredatorKills
    inc tumorAudit.intervalPredatorKills

  proc recordTumorDestroyed*() =
    ensureTumorAuditInit()
    inc tumorAudit.totalTumorsDestroyed
    inc tumorAudit.intervalTumorsDestroyed

  proc printTumorReport*(env: Environment) =
    ensureTumorAuditInit()
    if env.currentStep - tumorAudit.lastReportStep < tumorAudit.reportInterval:
      return
    tumorAudit.lastReportStep = env.currentStep

    # Count active tumors on map
    let activeTumors = env.thingsByKind[Tumor].len
    # Count mobile vs inert
    var mobileTumors = 0
    var inertTumors = 0
    for tumor in env.thingsByKind[Tumor]:
      if tumor.isNil: continue
      if tumor.hasClaimedTerritory:
        inc inertTumors
      else:
        inc mobileTumors

    # Count spawners
    let spawnerCount = env.thingsByKind[Spawner].len

    # Compute spread velocity (new tumors per interval)
    let intervalSteps = tumorAudit.reportInterval
    let newThisInterval = tumorAudit.intervalSpawned + tumorAudit.intervalBranched
    let spreadVelocity = if intervalSteps > 0:
      newThisInterval.float / intervalSteps.float
    else: 0.0

    echo "═══════════════════════════════════════════════════════"
    echo "  TUMOR REPORT — Step ", env.currentStep
    echo "═══════════════════════════════════════════════════════"
    echo "  Active tumors: ", activeTumors, " (mobile=", mobileTumors,
         " inert=", inertTumors, ")"
    echo "  Spawners: ", spawnerCount
    echo "  --- This interval (", intervalSteps, " steps) ---"
    echo "  New tumors: ", newThisInterval,
         " (spawned=", tumorAudit.intervalSpawned,
         " branched=", tumorAudit.intervalBranched, ")"
    echo "  Spread velocity: ", formatFloat(spreadVelocity, ffDecimal, 3), " tumors/step"
    echo "  Damage dealt: ", tumorAudit.intervalDamageDealt,
         " (agent kills=", tumorAudit.intervalAgentKills,
         " predator kills=", tumorAudit.intervalPredatorKills, ")"
    echo "  Tumors destroyed: ", tumorAudit.intervalTumorsDestroyed
    echo "  --- Lifetime totals ---"
    echo "  Total spawned: ", tumorAudit.totalSpawned,
         " Total branched: ", tumorAudit.totalBranched
    echo "  Total damage: ", tumorAudit.totalDamageDealt,
         " Agent kills: ", tumorAudit.totalAgentKills,
         " Predator kills: ", tumorAudit.totalPredatorKills
    echo "  Total tumors destroyed: ", tumorAudit.totalTumorsDestroyed
    echo "═══════════════════════════════════════════════════════"

    # Reset interval counters
    tumorAudit.intervalSpawned = 0
    tumorAudit.intervalBranched = 0
    tumorAudit.intervalDamageDealt = 0
    tumorAudit.intervalAgentKills = 0
    tumorAudit.intervalPredatorKills = 0
    tumorAudit.intervalTumorsDestroyed = 0
