import std/[math, os, parseutils, strformat, strutils]
import std/random

import src/environment
import src/external_actions

proc parseIntOption(name: string, default: int): int =
  ## Parse "--name=value" command line options.
  result = default
  for i in 1 .. paramCount():
    let arg = paramStr(i)
    let prefix = "--" & name & "="
    if arg.startsWith(prefix):
      discard parseInt(arg[prefix.len .. arg.len-1], result)
      return

proc parseBoolFlag(name: string): bool =
  ## Returns true if "--name" is present on the command line.
  for i in 1 .. paramCount():
    if paramStr(i) == "--" & name:
      return true
  return false

proc renderStep(env: Environment, step: int) =
  echo &"\n# Step {step}" 
  stdout.write env.render()

proc runEpisode(env: Environment, episode: int, maxSteps: int, renderEvery: int, useBuiltinAi: bool) =
  env.reset()
  echo &"\n=== Episode {episode + 1} ==="
  renderStep(env, 0)

  var actions: array[MapAgents, array[2, uint8]]
  var rng = initRand(episode)

  for step in 0 ..< maxSteps:
    if useBuiltinAi:
      actions = getActions(env)
    else:
      for i in 0 ..< MapAgents:
        actions[i][0] = uint8(rng.rand(0 .. 6))
        actions[i][1] = uint8(rng.rand(0 .. 7))

    env.step(addr actions)

    if renderEvery > 0 and ((step + 1) mod renderEvery == 0 or env.shouldReset):
      renderStep(env, step + 1)

    if env.shouldReset:
      break

when isMainModule:
  let episodes = max(1, parseIntOption("episodes", 1))
  let maxSteps = max(1, parseIntOption("max-steps", defaultEnvironmentConfig().maxSteps))
  let renderEvery = max(1, parseIntOption("render-every", 25))
  let randomControl = parseBoolFlag("random-controller")

  var env = newEnvironment()

  if randomControl:
    echo "Using random controller"
  else:
    initGlobalController(BuiltinAI)
    echo "Using built-in Nim controller"

  for episode in 0 ..< episodes:
    runEpisode(env, episode, maxSteps, renderEvery, not randomControl)

  echo "\nSimulation complete."
