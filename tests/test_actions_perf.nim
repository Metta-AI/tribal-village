import std/[unittest, monotimes, strformat]
import environment
import agent_control
import types

## Performance benchmark for actions subsystem.
## Verifies that action processing time scales reasonably with step count.
## Acceptance criteria: < 4x growth from step 100 to step 1000.

const
  WarmupSteps = 100
  MeasureSteps = 1000
  CheckpointInterval = 200
  MaxScalingFactor = 4.0  # Fail if growth exceeds this

proc msBetween(a, b: MonoTime): float64 =
  (b.ticks - a.ticks).float64 / 1_000_000.0

suite "Actions Subsystem Performance":
  test "action processing time scales sub-linearly":
    # Initialize environment with AI
    initGlobalController(BuiltinAI, seed = 42)
    var env = newEnvironment()

    # Warmup
    for _ in 0 ..< WarmupSteps:
      var actions = getActions(env)
      env.step(addr actions)

    # Measure at checkpoints
    var checkpoints: seq[tuple[step: int, ms: float64]]
    var stepsSinceCheckpoint = 0
    var cumMs = 0.0

    for step in WarmupSteps ..< WarmupSteps + MeasureSteps:
      var actions = getActions(env)
      let t0 = getMonoTime()
      env.step(addr actions)
      let t1 = getMonoTime()
      cumMs += msBetween(t0, t1)
      inc stepsSinceCheckpoint

      if stepsSinceCheckpoint >= CheckpointInterval:
        let avgMs = cumMs / float64(stepsSinceCheckpoint)
        checkpoints.add((step: step, ms: avgMs))
        cumMs = 0.0
        stepsSinceCheckpoint = 0

    # Report results
    echo "\nActions subsystem scaling:"
    for cp in checkpoints:
      echo &"  Step {cp.step}: {cp.ms:.4f} ms/step"

    # Verify scaling
    require checkpoints.len >= 2
    let firstMs = checkpoints[0].ms
    let lastMs = checkpoints[^1].ms
    let scalingFactor = lastMs / firstMs

    echo &"\nScaling factor: {scalingFactor:.2f}x (first: {firstMs:.4f}ms, last: {lastMs:.4f}ms)"
    echo &"Max allowed: {MaxScalingFactor:.1f}x"

    check scalingFactor < MaxScalingFactor
