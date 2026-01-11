# This file is included by src/step.nim
import std/os
when defined(stepTiming):
  import std/[os, monotimes]

  let stepTimingTargetStr = getEnv("TV_STEP_TIMING", "")
  let stepTimingWindowStr = getEnv("TV_STEP_TIMING_WINDOW", "0")
  let stepTimingTarget = block:
    if stepTimingTargetStr.len == 0:
      -1
    else:
      try:
        parseInt(stepTimingTargetStr)
      except ValueError:
        -1
  let stepTimingWindow = block:
    if stepTimingWindowStr.len == 0:
      0
    else:
      try:
        parseInt(stepTimingWindowStr)
      except ValueError:
        0

  proc msBetween(a, b: MonoTime): float64 =
    (b.ticks - a.ticks).float64 / 1_000_000.0

let spawnerScanOffsets = block:
  var offsets: seq[IVec2] = @[]
  for dx in -5 .. 5:
    for dy in -5 .. 5:
      offsets.add(ivec2(dx, dy))
  offsets

let logRenderEnabled = block:
  let raw = getEnv("TV_LOG_RENDER", "")
  raw.len > 0 and raw != "0" and raw != "false"
let logRenderWindow = block:
  let raw = getEnv("TV_LOG_RENDER_WINDOW", "100")
  let parsed =
    try:
      parseInt(raw)
    except ValueError:
      100
  max(100, parsed)
let logRenderEvery = block:
  let raw = getEnv("TV_LOG_RENDER_EVERY", "1")
  let parsed =
    try:
      parseInt(raw)
    except ValueError:
      1
  max(1, parsed)
let logRenderPath = block:
  let raw = getEnv("TV_LOG_RENDER_PATH", "")
  if raw.len > 0: raw else: "tribal_village.log"

var logRenderBuffer: seq[string] = @[]
var logRenderHead = 0
var logRenderCount = 0
