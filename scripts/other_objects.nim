## Quick check: what are the "other" grid objects?
import std/[os, strutils, strformat, tables, algorithm]
import environment
import agent_control
import types

proc main() =
  initGlobalController(BuiltinAI, seed = 42)
  var env = newEnvironment()

  # Run 3000 steps
  for i in 0 ..< 3000:
    var actions = getActions(env)
    env.step(addr actions)

  # Count ALL grid objects by kind
  var kindCounts: CountTable[string]
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      let t = env.grid[x][y]
      if t != nil:
        kindCounts.inc($t.kind)

  echo "=== Grid objects at step 3000 by ThingKind ==="
  var pairs: seq[(int, string)]
  for k, v in kindCounts:
    pairs.add((v, k))
  pairs.sort(proc(a, b: (int, string)): int = cmp(b[0], a[0]))
  for p in pairs:
    echo &"  {p[1]:>20}: {p[0]}"

  # Also check backgroundGrid
  var bgCounts: CountTable[string]
  for x in 0 ..< MapWidth:
    for y in 0 ..< MapHeight:
      let bg = env.backgroundGrid[x][y]
      if bg != nil:
        bgCounts.inc($bg.kind)

  echo ""
  echo "=== Background grid objects ==="
  var bgPairs: seq[(int, string)]
  for k, v in bgCounts:
    bgPairs.add((v, k))
  bgPairs.sort(proc(a, b: (int, string)): int = cmp(b[0], a[0]))
  for p in bgPairs:
    echo &"  {p[1]:>20}: {p[0]}"

main()
