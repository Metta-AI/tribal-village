import environment
import external

const Steps = 1000

proc main() =
  initGlobalController(BuiltinAI, seed = 12345)
  var env = newEnvironment()
  for _ in 0 ..< Steps:
    var actions = getActions(env)
    env.step(addr actions)

main()
