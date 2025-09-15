import benchy
import std/random
import src/environment

const StepsPerBatch = 8

proc randomizeActions(rng: var Rand, actions: var array[MapAgents, array[2, uint8]]) =
  for i in 0 ..< MapAgents:
    actions[i][0] = uint8(rng.rand(0 .. 6))
    actions[i][1] = uint8(rng.rand(0 .. 7))

when isMainModule:
  var env = newEnvironment()
  var rng = initRand(1337)
  var actions: array[MapAgents, array[2, uint8]]

  # Warm up so the world has tint data, clippies, etc.
  for _ in 0 ..< 200:
    randomizeActions(rng, actions)
    env.step(addr actions)
    if env.shouldReset:
      env.reset()

  timeIt("env.step (8 ticks)"):
    for _ in 0 ..< StepsPerBatch:
      randomizeActions(rng, actions)
      env.step(addr actions)
      if env.shouldReset:
        env.reset()

  # refresh state once before timing internal passes
  env.updateTintModifications()
  env.applyTintModifications()

  timeIt("updateTintModifications"):
    env.updateTintModifications()

  timeIt("update+applyTintModifications"):
    env.updateTintModifications()
    env.applyTintModifications()
