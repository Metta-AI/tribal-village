## perf_regression.nim - Real-time performance regression detector
##
## Gated behind -d:perfRegression compile flag. Zero-cost when disabled.
## Compares per-step execution times against a stored baseline.
## Tracks mean, p95, and p99 step times over a sliding window.
## Flags regressions exceeding a configurable threshold (default 10%).
## Logs warnings identifying the subsystem contributing most to slowdown.
##
## Environment variables:
##   TV_PERF_BASELINE       - Path to baseline JSON file (load on startup)
##   TV_PERF_THRESHOLD      - Regression threshold percentage (default: 10)
##   TV_PERF_WINDOW         - Sliding window size in steps (default: 100)
##   TV_PERF_INTERVAL       - Report/check every N steps (default: 100)
##   TV_PERF_SAVE_BASELINE  - Path to save captured baseline (if set, captures and saves)
##   TV_PERF_FAIL_ON_REGRESSION - If "1", exit with non-zero code on regression (CI mode)

when defined(perfRegression):
  import std/[monotimes, strutils, json, os, algorithm, math]

  const
    PerfSubsystemCount* = 11
    PerfSubsystemNames*: array[PerfSubsystemCount, string] = [
      "actionTint", "shields", "preDeaths", "actions", "things",
      "tumors", "tumorDamage", "auras", "popRespawn", "survival", "tintObs"
    ]
    ## Map subsystems to high-level categories for regression warnings
    PerfSubsystemCategory*: array[PerfSubsystemCount, string] = [
      "rendering",    # actionTint
      "physics",      # shields
      "physics",      # preDeaths
      "AI",           # actions (agent decision processing)
      "physics",      # things (entity updates)
      "physics",      # tumors
      "physics",      # tumorDamage
      "physics",      # auras
      "AI",           # popRespawn
      "physics",      # survival
      "rendering"     # tintObs
    ]
    DefaultThresholdPct = 10.0
    DefaultWindowSize = 100
    DefaultReportInterval = 100

  type
    PerfBaseline* = object
      ## Per-subsystem baseline statistics
      mean*: array[PerfSubsystemCount, float64]
      p95*: array[PerfSubsystemCount, float64]
      p99*: array[PerfSubsystemCount, float64]
      totalMean*: float64
      totalP95*: float64
      totalP99*: float64
      stepCount*: int
      windowSize*: int

    PerfSlidingWindow* = object
      ## Circular buffer of per-step timing samples
      samples: seq[array[PerfSubsystemCount, float64]]
      totalSamples: seq[float64]
      head: int       ## Next write position
      count: int      ## Number of valid samples
      capacity: int   ## Window size

    PerfRegressionState* = object
      window*: PerfSlidingWindow
      baseline*: PerfBaseline
      hasBaseline*: bool
      thresholdPct*: float64
      reportInterval*: int
      stepsSinceReport*: int
      failOnRegression*: bool
      saveBaselinePath*: string
      regressionDetected*: bool

  var perfState*: PerfRegressionState
  var perfInitialized = false

  proc msBetweenPerf(a, b: MonoTime): float64 =
    (b.ticks - a.ticks).float64 / 1_000_000.0

  proc initSlidingWindow(capacity: int): PerfSlidingWindow =
    result.capacity = capacity
    result.samples = newSeq[array[PerfSubsystemCount, float64]](capacity)
    result.totalSamples = newSeq[float64](capacity)
    result.head = 0
    result.count = 0

  proc pushSample(w: var PerfSlidingWindow,
                  subsystems: array[PerfSubsystemCount, float64], total: float64) =
    w.samples[w.head] = subsystems
    w.totalSamples[w.head] = total
    w.head = (w.head + 1) mod w.capacity
    if w.count < w.capacity:
      inc w.count

  proc computePercentile(values: var seq[float64], pct: float64): float64 =
    ## Compute percentile from a seq. Sorts in place.
    if values.len == 0: return 0.0
    sort(values)
    let idx = int(float64(values.len - 1) * pct / 100.0)
    values[min(idx, values.len - 1)]

  proc computeWindowStats(w: PerfSlidingWindow): PerfBaseline =
    ## Compute mean, p95, p99 from current window contents.
    if w.count == 0: return

    result.stepCount = w.count
    result.windowSize = w.capacity

    # Collect per-subsystem values
    var subsystemValues: array[PerfSubsystemCount, seq[float64]]
    var totalValues = newSeq[float64](w.count)

    for i in 0 ..< PerfSubsystemCount:
      subsystemValues[i] = newSeq[float64](w.count)

    for i in 0 ..< w.count:
      let idx = if w.count < w.capacity:
        i
      else:
        (w.head + i) mod w.capacity
      for s in 0 ..< PerfSubsystemCount:
        subsystemValues[s][i] = w.samples[idx][s]
      totalValues[i] = w.totalSamples[idx]

    # Compute stats
    for s in 0 ..< PerfSubsystemCount:
      var sum = 0.0
      for v in subsystemValues[s]:
        sum += v
      result.mean[s] = sum / float64(w.count)
      result.p95[s] = computePercentile(subsystemValues[s], 95.0)
      result.p99[s] = computePercentile(subsystemValues[s], 99.0)

    var totalSum = 0.0
    for v in totalValues:
      totalSum += v
    result.totalMean = totalSum / float64(w.count)
    result.totalP95 = computePercentile(totalValues, 95.0)
    result.totalP99 = computePercentile(totalValues, 99.0)

  proc baselineToJson(b: PerfBaseline): JsonNode =
    result = newJObject()
    result["stepCount"] = %b.stepCount
    result["windowSize"] = %b.windowSize
    result["totalMean"] = %b.totalMean
    result["totalP95"] = %b.totalP95
    result["totalP99"] = %b.totalP99

    var subsystems = newJObject()
    for i in 0 ..< PerfSubsystemCount:
      var entry = newJObject()
      entry["mean"] = %b.mean[i]
      entry["p95"] = %b.p95[i]
      entry["p99"] = %b.p99[i]
      subsystems[PerfSubsystemNames[i]] = entry
    result["subsystems"] = subsystems

  proc baselineFromJson(node: JsonNode): PerfBaseline =
    result.stepCount = node["stepCount"].getInt()
    result.windowSize = node["windowSize"].getInt()
    result.totalMean = node["totalMean"].getFloat()
    result.totalP95 = node["totalP95"].getFloat()
    result.totalP99 = node["totalP99"].getFloat()

    let subsystems = node["subsystems"]
    for i in 0 ..< PerfSubsystemCount:
      let name = PerfSubsystemNames[i]
      if subsystems.hasKey(name):
        let entry = subsystems[name]
        result.mean[i] = entry["mean"].getFloat()
        result.p95[i] = entry["p95"].getFloat()
        result.p99[i] = entry["p99"].getFloat()

  proc saveBaseline*(b: PerfBaseline, path: string) =
    let j = baselineToJson(b)
    writeFile(path, $j)
    echo "[perf] Baseline saved to ", path

  proc loadBaseline*(path: string): PerfBaseline =
    let content = readFile(path)
    let node = parseJson(content)
    result = baselineFromJson(node)
    echo "[perf] Baseline loaded from ", path,
         " (", result.stepCount, " samples, window=", result.windowSize, ")"

  proc initPerfRegression*() =
    let windowSize = parseEnvInt(getEnv("TV_PERF_WINDOW", ""), DefaultWindowSize)
    let threshold = getEnv("TV_PERF_THRESHOLD", "")
    let interval = parseEnvInt(getEnv("TV_PERF_INTERVAL", ""), DefaultReportInterval)
    let baselinePath = getEnv("TV_PERF_BASELINE", "")
    let savePath = getEnv("TV_PERF_SAVE_BASELINE", "")
    let failOn = getEnv("TV_PERF_FAIL_ON_REGRESSION", "")

    perfState.window = initSlidingWindow(windowSize)
    perfState.thresholdPct = if threshold.len > 0:
      parseFloat(threshold)
    else:
      DefaultThresholdPct
    perfState.reportInterval = max(1, interval)
    perfState.stepsSinceReport = 0
    perfState.saveBaselinePath = savePath
    perfState.failOnRegression = failOn == "1"
    perfState.regressionDetected = false

    if baselinePath.len > 0 and fileExists(baselinePath):
      perfState.baseline = loadBaseline(baselinePath)
      perfState.hasBaseline = true
    else:
      perfState.hasBaseline = false

    perfInitialized = true

  proc ensurePerfInit*() =
    if not perfInitialized:
      initPerfRegression()

  proc recordPerfStep*(subsystems: array[PerfSubsystemCount, float64], totalMs: float64) =
    ## Record one step's timing data into the sliding window.
    ensurePerfInit()
    pushSample(perfState.window, subsystems, totalMs)
    inc perfState.stepsSinceReport

  proc padLeftPerf(s: string, width: int): string =
    if s.len >= width: return s
    " ".repeat(width - s.len) & s

  proc padRightPerf(s: string, width: int): string =
    if s.len >= width: return s
    s & " ".repeat(width - s.len)

  proc checkPerfRegression*(currentStep: int) =
    ## Check for regressions and print report at configured interval.
    ensurePerfInit()

    if perfState.stepsSinceReport < perfState.reportInterval:
      return

    perfState.stepsSinceReport = 0
    let stats = computeWindowStats(perfState.window)

    if stats.stepCount == 0:
      return

    # Print current stats
    echo ""
    echo "=== Perf Regression Report (step ", currentStep, ", window=", stats.stepCount, ") ==="
    echo padRightPerf("Subsystem", 14), " | ",
         padLeftPerf("Mean ms", 10), " | ",
         padLeftPerf("P95 ms", 10), " | ",
         padLeftPerf("P99 ms", 10),
         (if perfState.hasBaseline: " | " & padLeftPerf("Δ Mean%", 9) else: "")
    echo repeat("-", 14), "-+-", repeat("-", 10), "-+-", repeat("-", 10), "-+-", repeat("-", 10),
         (if perfState.hasBaseline: "-+-" & repeat("-", 9) else: "")

    var worstSubsystem = -1
    var worstDeltaPct = 0.0

    for i in 0 ..< PerfSubsystemCount:
      var deltaPctStr = ""
      if perfState.hasBaseline and perfState.baseline.mean[i] > 0.0:
        let deltaPct = (stats.mean[i] - perfState.baseline.mean[i]) /
                       perfState.baseline.mean[i] * 100.0
        if deltaPct > worstDeltaPct:
          worstDeltaPct = deltaPct
          worstSubsystem = i
        let sign = if deltaPct >= 0.0: "+" else: ""
        deltaPctStr = " | " & padLeftPerf(sign & formatFloat(deltaPct, ffDecimal, 1) & "%", 9)
      elif perfState.hasBaseline:
        deltaPctStr = " | " & padLeftPerf("N/A", 9)

      echo padRightPerf(PerfSubsystemNames[i], 14), " | ",
           padLeftPerf(formatFloat(stats.mean[i], ffDecimal, 4), 10), " | ",
           padLeftPerf(formatFloat(stats.p95[i], ffDecimal, 4), 10), " | ",
           padLeftPerf(formatFloat(stats.p99[i], ffDecimal, 4), 10),
           deltaPctStr

    # Total row
    var totalDeltaStr = ""
    if perfState.hasBaseline and perfState.baseline.totalMean > 0.0:
      let totalDelta = (stats.totalMean - perfState.baseline.totalMean) /
                       perfState.baseline.totalMean * 100.0
      let sign = if totalDelta >= 0.0: "+" else: ""
      totalDeltaStr = " | " & padLeftPerf(sign & formatFloat(totalDelta, ffDecimal, 1) & "%", 9)

    echo repeat("-", 14), "-+-", repeat("-", 10), "-+-", repeat("-", 10), "-+-", repeat("-", 10),
         (if perfState.hasBaseline: "-+-" & repeat("-", 9) else: "")
    echo padRightPerf("TOTAL", 14), " | ",
         padLeftPerf(formatFloat(stats.totalMean, ffDecimal, 4), 10), " | ",
         padLeftPerf(formatFloat(stats.totalP95, ffDecimal, 4), 10), " | ",
         padLeftPerf(formatFloat(stats.totalP99, ffDecimal, 4), 10),
         totalDeltaStr

    # Check for regressions
    if perfState.hasBaseline:
      let totalDelta = if perfState.baseline.totalMean > 0.0:
        (stats.totalMean - perfState.baseline.totalMean) / perfState.baseline.totalMean * 100.0
      else:
        0.0

      if totalDelta > perfState.thresholdPct:
        perfState.regressionDetected = true
        echo ""
        echo "⚠ REGRESSION DETECTED: total step time +",
             formatFloat(totalDelta, ffDecimal, 1), "% (threshold: ",
             formatFloat(perfState.thresholdPct, ffDecimal, 1), "%)"
        if worstSubsystem >= 0:
          echo "  Worst offender: ", PerfSubsystemNames[worstSubsystem],
               " (", PerfSubsystemCategory[worstSubsystem], ")",
               " +", formatFloat(worstDeltaPct, ffDecimal, 1), "%"
      else:
        echo ""
        echo "✓ No regression (total Δ ",
             (if totalDelta >= 0.0: "+" else: ""),
             formatFloat(totalDelta, ffDecimal, 1),
             "%, threshold: ", formatFloat(perfState.thresholdPct, ffDecimal, 1), "%)"

    echo ""

    # Save baseline if requested (captures at end of run)
    if perfState.saveBaselinePath.len > 0:
      saveBaseline(stats, perfState.saveBaselinePath)

  proc perfRegressionDetected*(): bool =
    ## Returns true if any regression was detected during this run.
    ## Use in CI to gate builds.
    ensurePerfInit()
    perfState.regressionDetected
