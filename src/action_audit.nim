## action_audit.nim - Frame-by-frame action distribution logger
##
## Gated behind -d:actionAudit compile flag. Zero-cost when disabled.
## Tracks per-step and per-team action distributions.
## Prints periodic aggregate reports every N steps.

when defined(actionAudit):
  import std/[strutils, os]

  const
    VerbCount = ActionVerbCount  # 11 verbs (0-10)
    TeamCount = MapRoomObjectsTeams  # 8 teams
    VerbNames: array[VerbCount, string] = [
      "noop", "move", "attack", "use", "swap",
      "put", "plant_lantern", "plant_resource", "build", "orient",
      "set_rally_point"
    ]

  type
    ActionAuditState* = object
      ## Per-step counters (reset each step)
      stepVerbCounts: array[VerbCount, int]
      stepTeamVerbCounts: array[TeamCount, array[VerbCount, int]]
      stepTotal: int
      stepTeamTotals: array[TeamCount, int]
      ## Aggregate counters (reset each report interval)
      aggVerbCounts: array[VerbCount, int]
      aggTeamVerbCounts: array[TeamCount, array[VerbCount, int]]
      aggTotal: int
      aggTeamTotals: array[TeamCount, int]
      aggStepCount: int
      ## Config
      reportInterval: int
      lastReportStep: int

  var actionAuditState*: ActionAuditState
  var actionAuditInitialized = false

  proc initActionAudit*() =
    actionAuditState = ActionAuditState(
      reportInterval: max(1, parseInt(getEnv("TV_ACTION_AUDIT_INTERVAL", "100")))
    )
    actionAuditInitialized = true

  proc ensureActionAuditInit*() =
    if not actionAuditInitialized:
      initActionAudit()

  proc resetStepCounters() =
    for v in 0 ..< VerbCount:
      actionAuditState.stepVerbCounts[v] = 0
    for t in 0 ..< TeamCount:
      for v in 0 ..< VerbCount:
        actionAuditState.stepTeamVerbCounts[t][v] = 0
      actionAuditState.stepTeamTotals[t] = 0
    actionAuditState.stepTotal = 0

  proc recordAction*(agentId: int, verb: int) =
    ## Record a single agent action for this step.
    ensureActionAuditInit()
    let v = clamp(verb, 0, VerbCount - 1)
    let teamId = agentId div MapAgentsPerTeam
    inc actionAuditState.stepVerbCounts[v]
    inc actionAuditState.stepTotal
    if teamId >= 0 and teamId < TeamCount:
      inc actionAuditState.stepTeamVerbCounts[teamId][v]
      inc actionAuditState.stepTeamTotals[teamId]

  proc flushStep() =
    ## Accumulate step counters into aggregates.
    for v in 0 ..< VerbCount:
      actionAuditState.aggVerbCounts[v] += actionAuditState.stepVerbCounts[v]
    for t in 0 ..< TeamCount:
      for v in 0 ..< VerbCount:
        actionAuditState.aggTeamVerbCounts[t][v] += actionAuditState.stepTeamVerbCounts[t][v]
      actionAuditState.aggTeamTotals[t] += actionAuditState.stepTeamTotals[t]
    actionAuditState.aggTotal += actionAuditState.stepTotal
    inc actionAuditState.aggStepCount
    resetStepCounters()

  proc padLeft(s: string, width: int): string =
    if s.len >= width: return s
    " ".repeat(width - s.len) & s

  proc padRight(s: string, width: int): string =
    if s.len >= width: return s
    s & " ".repeat(width - s.len)

  proc fmtPct(num, denom: int): string =
    if denom == 0: return "  0.0%"
    let pct = num.float64 / denom.float64 * 100.0
    padLeft(formatFloat(pct, ffDecimal, 1) & "%", 6)

  proc fmtAvg(total, steps: int): string =
    if steps == 0: return "0.0"
    formatFloat(total.float64 / steps.float64, ffDecimal, 1)

  proc printStepSummary*(currentStep: int) =
    ## Print per-step action summary.
    ensureActionAuditInit()
    let st = actionAuditState
    echo ""
    echo "--- Action Distribution — Step ", currentStep, " (", st.stepTotal, " actions) ---"
    echo padRight("Action", 16), padLeft("Count", 7), padLeft("%", 7)
    for v in 0 ..< VerbCount:
      let c = st.stepVerbCounts[v]
      if c > 0:
        echo padRight(VerbNames[v], 16), padLeft($c, 7), " ", fmtPct(c, st.stepTotal)

    # Per-team breakdown
    for t in 0 ..< TeamCount:
      if st.stepTeamTotals[t] == 0:
        continue
      echo "  Team ", t, " (", st.stepTeamTotals[t], " actions):"
      for v in 0 ..< VerbCount:
        let c = st.stepTeamVerbCounts[t][v]
        if c > 0:
          echo "    ", padRight(VerbNames[v], 14), padLeft($c, 7), " ", fmtPct(c, st.stepTeamTotals[t])

  proc printActionAuditReport*(currentStep: int) =
    ## Print aggregate report every N steps. Call at end of each step.
    ensureActionAuditInit()

    # Print per-step summary
    printStepSummary(currentStep)

    # Flush step into aggregates
    flushStep()

    # Check if it's time for an aggregate report
    if actionAuditState.aggStepCount < actionAuditState.reportInterval:
      return

    let n = actionAuditState.aggStepCount
    let stepStart = currentStep - n + 1
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  ACTION AUDIT AGGREGATE — Steps ", stepStart, "-", currentStep, " (", n, " steps)"
    echo "═══════════════════════════════════════════════════════════"

    # Find busiest action type
    var busiestVerb = 0
    for v in 1 ..< VerbCount:
      if actionAuditState.aggVerbCounts[v] > actionAuditState.aggVerbCounts[busiestVerb]:
        busiestVerb = v

    echo "  Avg actions/step: ", fmtAvg(actionAuditState.aggTotal, n)
    echo "  Busiest action:   ", VerbNames[busiestVerb], " (", fmtPct(actionAuditState.aggVerbCounts[busiestVerb], actionAuditState.aggTotal), ")"
    echo ""

    # Overall distribution table
    echo padRight("Action", 16), padLeft("Total", 9), padLeft("Avg/step", 10), padLeft("%", 7)
    echo repeat("-", 42)
    for v in 0 ..< VerbCount:
      let c = actionAuditState.aggVerbCounts[v]
      echo padRight(VerbNames[v], 16), padLeft($c, 9), padLeft(fmtAvg(c, n), 10), " ", fmtPct(c, actionAuditState.aggTotal)

    # Per-team idle rate and distribution
    echo ""
    echo "  Per-Team Summary:"
    echo padRight("  Team", 8), padLeft("Actions", 9), padLeft("Avg/step", 10), padLeft("Idle%", 8), padLeft("Move%", 8), padLeft("Attack%", 9), padLeft("Build%", 8)
    echo "  ", repeat("-", 58)
    for t in 0 ..< TeamCount:
      if actionAuditState.aggTeamTotals[t] == 0:
        continue
      let total = actionAuditState.aggTeamTotals[t]
      let idlePct = (actionAuditState.aggTeamVerbCounts[t][0].float64 +
                     actionAuditState.aggTeamVerbCounts[t][9].float64) /
                    total.float64 * 100.0
      let movePct = actionAuditState.aggTeamVerbCounts[t][1].float64 / total.float64 * 100.0
      let atkPct = actionAuditState.aggTeamVerbCounts[t][2].float64 / total.float64 * 100.0
      let buildPct = actionAuditState.aggTeamVerbCounts[t][8].float64 / total.float64 * 100.0
      echo padRight("  T" & $t, 8),
           padLeft($total, 9),
           padLeft(fmtAvg(total, n), 10),
           padLeft(formatFloat(idlePct, ffDecimal, 1) & "%", 8),
           padLeft(formatFloat(movePct, ffDecimal, 1) & "%", 8),
           padLeft(formatFloat(atkPct, ffDecimal, 1) & "%", 9),
           padLeft(formatFloat(buildPct, ffDecimal, 1) & "%", 8)

    echo "═══════════════════════════════════════════════════════════"
    echo ""

    # Reset aggregates
    for v in 0 ..< VerbCount:
      actionAuditState.aggVerbCounts[v] = 0
    for t in 0 ..< TeamCount:
      for v in 0 ..< VerbCount:
        actionAuditState.aggTeamVerbCounts[t][v] = 0
      actionAuditState.aggTeamTotals[t] = 0
    actionAuditState.aggTotal = 0
    actionAuditState.aggStepCount = 0
