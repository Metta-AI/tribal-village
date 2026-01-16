# This file is included by src/step.nim
import std/os

proc parseEnvInt(raw: string, fallback: int): int =
  if raw.len == 0:
    return fallback
  try:
    parseInt(raw)
  except ValueError:
    fallback

when defined(stepTiming):
  import std/[os, monotimes]

  let stepTimingTarget = parseEnvInt(getEnv("TV_STEP_TIMING", ""), -1)
  let stepTimingWindow = parseEnvInt(getEnv("TV_STEP_TIMING_WINDOW", "0"), 0)

  proc msBetween(a, b: MonoTime): float64 =
    (b.ticks - a.ticks).float64 / 1_000_000.0

let spawnerScanOffsets = block:
  var offsets: seq[IVec2] = @[]
  for dx in -5 .. 5:
    for dy in -5 .. 5:
      offsets.add(ivec2(dx, dy))
  offsets

let logRenderEnabled = getEnv("TV_LOG_RENDER", "") notin ["", "0", "false"]
let logRenderWindow = max(100, parseEnvInt(getEnv("TV_LOG_RENDER_WINDOW", "100"), 100))
let logRenderEvery = max(1, parseEnvInt(getEnv("TV_LOG_RENDER_EVERY", "1"), 1))
let logRenderPath = block:
  let raw = getEnv("TV_LOG_RENDER_PATH", "")
  if raw.len > 0: raw else: "tribal_village.log"

var logRenderBuffer: seq[string] = @[]
var logRenderHead = 0
var logRenderCount = 0
