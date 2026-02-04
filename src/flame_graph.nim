## flame_graph.nim - Per-step CPU flame graph sampling
##
## Gated behind -d:flameGraph compile flag. Zero-cost when disabled.
## Records per-step subsystem timings and outputs in collapsed stack format
## compatible with flamegraph.pl, speedscope, and similar tools.
##
## Output format (collapsed stacks):
##   step;subsystem_name microseconds
##
## Environment variables:
##   TV_FLAME_OUTPUT    - Output file path (default: flame_graph.folded)
##   TV_FLAME_INTERVAL  - Flush to disk every N steps (default: 100)
##   TV_FLAME_SAMPLE    - Sample every N steps (default: 1, i.e., every step)

when defined(flameGraph):
  import std/[monotimes, strutils, os]

  when not declared(parseEnvInt):
    proc parseEnvInt(raw: string, fallback: int): int =
      if raw.len == 0:
        return fallback
      try:
        parseInt(raw)
      except ValueError:
        fallback

  const
    FlameSubsystemCount* = 11
    FlameSubsystemNames*: array[FlameSubsystemCount, string] = [
      "actionTint", "shields", "preDeaths", "actions", "things",
      "tumors", "tumorDamage", "auras", "popRespawn", "survival", "tintObs"
    ]
    DefaultFlameOutput = "flame_graph.folded"
    DefaultFlameInterval = 100
    DefaultFlameSample = 1

  type
    FlameGraphState* = object
      outputPath*: string
      flushInterval*: int
      sampleInterval*: int
      stepsSinceFlush*: int
      buffer*: seq[string]   # Buffered collapsed stack lines
      fileHandle*: File
      isOpen*: bool
      totalSamples*: int

  var flameState*: FlameGraphState
  var flameInitialized = false

  proc usBetween(a, b: MonoTime): int64 =
    ## Microseconds between two monotonic times
    (b.ticks - a.ticks) div 1000

  proc initFlameGraph*() =
    let outputPath = getEnv("TV_FLAME_OUTPUT", DefaultFlameOutput)
    let flushInterval = parseEnvInt(getEnv("TV_FLAME_INTERVAL", ""), DefaultFlameInterval)
    let sampleInterval = parseEnvInt(getEnv("TV_FLAME_SAMPLE", ""), DefaultFlameSample)

    flameState.outputPath = outputPath
    flameState.flushInterval = max(1, flushInterval)
    flameState.sampleInterval = max(1, sampleInterval)
    flameState.stepsSinceFlush = 0
    flameState.buffer = @[]
    flameState.totalSamples = 0

    # Open file for writing (truncate if exists)
    try:
      flameState.fileHandle = open(outputPath, fmWrite)
      flameState.isOpen = true
      echo "[flameGraph] Output file: ", outputPath,
           " (flush every ", flushInterval, " steps",
           ", sample every ", sampleInterval, " steps)"
    except IOError as e:
      echo "[flameGraph] WARNING: Could not open output file ", outputPath, ": ", e.msg
      flameState.isOpen = false

    flameInitialized = true

  proc ensureFlameInit*() =
    if not flameInitialized:
      initFlameGraph()

  proc flushFlameBuffer*() =
    ## Write buffered samples to disk
    if not flameState.isOpen or flameState.buffer.len == 0:
      return

    try:
      for line in flameState.buffer:
        flameState.fileHandle.writeLine(line)
      flameState.fileHandle.flushFile()
      flameState.buffer.setLen(0)
    except IOError:
      discard  # Silently ignore write errors to not spam logs

  proc recordFlameStep*(currentStep: int,
                        subsystems: array[FlameSubsystemCount, int64],
                        totalUs: int64) =
    ## Record one step's timing data in collapsed stack format.
    ## Each subsystem becomes a stack frame under "step".
    ensureFlameInit()

    # Check if we should sample this step
    if currentStep mod flameState.sampleInterval != 0:
      return

    # Record each subsystem as a separate stack with its time
    for i in 0 ..< FlameSubsystemCount:
      if subsystems[i] > 0:
        let line = "step;" & FlameSubsystemNames[i] & " " & $subsystems[i]
        flameState.buffer.add(line)

    inc flameState.totalSamples
    inc flameState.stepsSinceFlush

    # Flush at interval
    if flameState.stepsSinceFlush >= flameState.flushInterval:
      flushFlameBuffer()
      flameState.stepsSinceFlush = 0

  proc closeFlameGraph*() =
    ## Flush remaining buffer and close file
    if not flameInitialized:
      return

    flushFlameBuffer()

    if flameState.isOpen:
      try:
        flameState.fileHandle.close()
        echo "[flameGraph] Closed output file: ", flameState.outputPath,
             " (", flameState.totalSamples, " samples)"
      except IOError:
        discard
      flameState.isOpen = false

  proc msBetweenFlame*(a, b: MonoTime): float64 =
    ## Milliseconds between two monotonic times (for compatibility with other timing code)
    (b.ticks - a.ticks).float64 / 1_000_000.0
