## action_freq_counter.nim - Action frequency counter per unit type per step
##
## Gated behind -d:actionFreqCounter compile flag. Zero-cost when disabled.
## Tracks per-step action distributions broken down by unit type.
## Prints periodic aggregate reports every N steps.

when defined(actionFreqCounter):
  import std/strutils

  const
    VerbCount = ActionVerbCount  # 11 verbs (0-10)
    UnitTypeCount = ord(UnitScorpion) + 1  # 31 unit types
    VerbNames: array[VerbCount, string] = [
      "noop", "move", "attack", "use", "swap",
      "put", "plant_lantern", "plant_resource", "build", "orient",
      "set_rally_point"
    ]

  type
    ActionFreqCounterState* = object
      ## Per-step counters (reset each step)
      stepUnitVerbCounts: array[UnitTypeCount, array[VerbCount, int]]
      stepUnitTotals: array[UnitTypeCount, int]
      stepTotal: int
      ## Aggregate counters (reset each report interval)
      aggUnitVerbCounts: array[UnitTypeCount, array[VerbCount, int]]
      aggUnitTotals: array[UnitTypeCount, int]
      aggTotal: int
      aggStepCount: int
      ## Config
      reportInterval: int
      lastReportStep: int

  var actionFreqState*: ActionFreqCounterState
  var actionFreqInitialized = false

  proc initActionFreqCounter*() =
    actionFreqState = ActionFreqCounterState(
      reportInterval: max(1, parseEnvInt("TV_ACTION_FREQ_INTERVAL", 100))
    )
    actionFreqInitialized = true

  proc ensureActionFreqInit*() =
    if not actionFreqInitialized:
      initActionFreqCounter()

  proc resetStepCounters() =
    for u in 0 ..< UnitTypeCount:
      for v in 0 ..< VerbCount:
        actionFreqState.stepUnitVerbCounts[u][v] = 0
      actionFreqState.stepUnitTotals[u] = 0
    actionFreqState.stepTotal = 0

  proc recordActionByUnitType*(agentId: int, verb: int, unitClass: AgentUnitClass) =
    ## Record a single agent action for this step, keyed by unit type.
    ensureActionFreqInit()
    let v = clamp(verb, 0, VerbCount - 1)
    let u = ord(unitClass)
    if u >= 0 and u < UnitTypeCount:
      inc actionFreqState.stepUnitVerbCounts[u][v]
      inc actionFreqState.stepUnitTotals[u]
    inc actionFreqState.stepTotal

  proc flushStep() =
    ## Accumulate step counters into aggregates.
    for u in 0 ..< UnitTypeCount:
      for v in 0 ..< VerbCount:
        actionFreqState.aggUnitVerbCounts[u][v] += actionFreqState.stepUnitVerbCounts[u][v]
      actionFreqState.aggUnitTotals[u] += actionFreqState.stepUnitTotals[u]
    actionFreqState.aggTotal += actionFreqState.stepTotal
    inc actionFreqState.aggStepCount
    resetStepCounters()

  proc printActionFreqReport*(currentStep: int) =
    ## Print aggregate report every N steps. Call at end of each step.
    ensureActionFreqInit()

    # Flush step into aggregates
    flushStep()

    # Check if it's time for an aggregate report
    if actionFreqState.aggStepCount < actionFreqState.reportInterval:
      return

    let n = actionFreqState.aggStepCount
    let stepStart = currentStep - n + 1
    echo ""
    echo "==============================================================================="
    echo "  ACTION FREQUENCY BY UNIT TYPE - Steps ", stepStart, "-", currentStep, " (", n, " steps)"
    echo "==============================================================================="
    echo ""

    # Header: Action names
    var header = alignLeft("Unit Type", 18)
    for v in 0 ..< VerbCount:
      header &= align(VerbNames[v][0..min(5, VerbNames[v].high)], 7)
    header &= align("Total", 8)
    echo header
    echo repeat("-", header.len)

    # Per unit type rows
    for u in 0 ..< UnitTypeCount:
      if actionFreqState.aggUnitTotals[u] == 0:
        continue
      let unitName = UnitClassLabels[AgentUnitClass(u)]
      var row = alignLeft(unitName[0..min(17, unitName.high)], 18)
      for v in 0 ..< VerbCount:
        let c = actionFreqState.aggUnitVerbCounts[u][v]
        row &= align($c, 7)
      row &= align($actionFreqState.aggUnitTotals[u], 8)
      echo row

    echo repeat("-", header.len)

    # Totals row
    var totalsRow = alignLeft("TOTAL", 18)
    for v in 0 ..< VerbCount:
      var verbTotal = 0
      for u in 0 ..< UnitTypeCount:
        verbTotal += actionFreqState.aggUnitVerbCounts[u][v]
      totalsRow &= align($verbTotal, 7)
    totalsRow &= align($actionFreqState.aggTotal, 8)
    echo totalsRow

    echo ""
    echo "  Legend: noop=N, move=M, attack=A, use=U, swap=S, put=P"
    echo "          plant_lantern=pl, plant_resource=pr, build=B, orient=O, rally=R"
    echo "==============================================================================="
    echo ""

    # Reset aggregates
    for u in 0 ..< UnitTypeCount:
      for v in 0 ..< VerbCount:
        actionFreqState.aggUnitVerbCounts[u][v] = 0
      actionFreqState.aggUnitTotals[u] = 0
    actionFreqState.aggTotal = 0
    actionFreqState.aggStepCount = 0
