## Headless driver for profiling the built-in AI (no renderer).
## Example:
##   nim r -d:release --path:src scripts/profile_ai.nim
##   TV_PROFILE_STEPS=3000 nim r -d:release --path:src scripts/profile_ai.nim

import std/[os, strutils]
import environment
import agent_control
import types

proc parseEnvInt(name: string, fallback: int): int =
  let raw = getEnv(name, "")
  if raw.len == 0:
    return fallback
  try:
    parseInt(raw)
  except ValueError:
    fallback

proc countHouses(env: Environment): array[MapRoomObjectsVillages, int] =
  var counts: array[MapRoomObjectsVillages, int]
  for house in env.thingsByKind[House]:
    let teamId = house.teamId
    if teamId >= 0 and teamId < counts.len:
      inc counts[teamId]
  counts

proc updateMaxHearts(env: Environment, maxHearts: var array[MapRoomObjectsVillages, int]) =
  for altar in env.thingsByKind[Altar]:
    let teamId = altar.teamId
    if teamId >= 0 and teamId < maxHearts.len:
      if altar.hearts > maxHearts[teamId]:
        maxHearts[teamId] = altar.hearts

proc formatCounts(label: string, counts: array[MapRoomObjectsVillages, int]): string =
  var parts: seq[string] = @[]
  for teamId in 0 ..< counts.len:
    parts.add("t" & $teamId & "=" & $counts[teamId])
  label & " " & parts.join(" ")

when isMainModule:
  let steps = max(1, parseEnvInt("TV_PROFILE_STEPS", 3000))
  let reportEvery = max(0, parseEnvInt("TV_PROFILE_REPORT_EVERY", 0))
  let seed = parseEnvInt("TV_PROFILE_SEED", 42)

  var env = newEnvironment()
  initGlobalController(BuiltinAI, seed)

  let baselineHouses = countHouses(env)
  var maxHouses = baselineHouses
  var maxHearts: array[MapRoomObjectsVillages, int]
  for teamId in 0 ..< maxHearts.len:
    maxHearts[teamId] = MapObjectAltarInitialHearts
  updateMaxHearts(env, maxHearts)

  var actions: array[MapAgents, uint8]
  for step in 1 .. steps:
    actions = getActions(env)
    env.step(addr actions)
    let currentHouses = countHouses(env)
    for teamId in 0 ..< maxHouses.len:
      if currentHouses[teamId] > maxHouses[teamId]:
        maxHouses[teamId] = currentHouses[teamId]
    updateMaxHearts(env, maxHearts)
    if reportEvery > 0 and step mod reportEvery == 0:
      echo "step=", step, " ", formatCounts("houses", currentHouses),
        " ", formatCounts("max_hearts", maxHearts)

  echo "Profile complete: steps=", steps
  echo formatCounts("baseline_houses", baselineHouses)
  echo formatCounts("max_houses", maxHouses)
  echo formatCounts("max_hearts", maxHearts)
