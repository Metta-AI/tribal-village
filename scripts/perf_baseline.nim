## perf_baseline.nim - Capture or check performance baselines
##
## Usage:
##   # Capture a new baseline (runs N steps, saves timing data):
##   TV_PERF_SAVE_BASELINE=baselines/baseline.json \
##     nim c -r -d:perfRegression -d:release --path:src scripts/perf_baseline.nim
##
##   # Check for regressions against a baseline:
##   TV_PERF_BASELINE=baselines/baseline.json \
##   TV_PERF_FAIL_ON_REGRESSION=1 \
##     nim c -r -d:perfRegression -d:release --path:src scripts/perf_baseline.nim
##
## Environment variables:
##   TV_PERF_STEPS     - Steps to run (default: 1000)
##   TV_PERF_SEED      - Random seed (default: 42)
##   TV_PERF_WARMUP    - Warmup steps before measuring (default: 100)
##   TV_PERF_WINDOW    - Sliding window size (default: 100)
##   TV_PERF_INTERVAL  - Report interval (default: 100)
##   TV_PERF_THRESHOLD - Regression threshold % (default: 10)
##   TV_PERF_BASELINE  - Path to load baseline from
##   TV_PERF_SAVE_BASELINE - Path to save baseline to
##   TV_PERF_FAIL_ON_REGRESSION - "1" to exit non-zero on regression

import std/[os, strutils, strformat]
import environment
import agent_control
import types

proc main() =
  let steps = parseInt(getEnv("TV_PERF_STEPS", "1000"))
  let seed = parseInt(getEnv("TV_PERF_SEED", "42"))
  let warmup = parseInt(getEnv("TV_PERF_WARMUP", "100"))

  echo "=== Performance Baseline Runner ==="
  echo &"  Steps: {steps} (warmup: {warmup})"
  echo &"  Seed: {seed}"
  echo &"  Baseline: {getEnv(\"TV_PERF_BASELINE\", \"(none)\")}"
  echo &"  Save to: {getEnv(\"TV_PERF_SAVE_BASELINE\", \"(none)\")}"
  echo &"  Threshold: {getEnv(\"TV_PERF_THRESHOLD\", \"10\")}%"
  echo &"  Fail on regression: {getEnv(\"TV_PERF_FAIL_ON_REGRESSION\", \"0\")}"
  echo ""

  initGlobalController(BuiltinAI, seed = seed)
  var env = newEnvironment()

  # Warmup phase (not measured by regression detector since window resets)
  echo &"Running {warmup} warmup steps..."
  for step in 0 ..< warmup:
    var actions = getActions(env)
    env.step(addr actions)

  echo &"Running {steps} measured steps..."
  for step in 0 ..< steps:
    var actions = getActions(env)
    env.step(addr actions)

    if step > 0 and step mod 200 == 0:
      echo &"  Step {step}/{steps}..."

  echo ""
  echo "=== Run Complete ==="

  when defined(perfRegression):
    if perfRegressionDetected():
      echo "RESULT: REGRESSION DETECTED"
      if getEnv("TV_PERF_FAIL_ON_REGRESSION", "0") == "1":
        quit(1)
    else:
      echo "RESULT: No regressions detected"

main()
