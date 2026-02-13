## respawn_diagnostic.nim - Why are zero agents respawning?
## Usage: nim c -r -d:release --path:src scripts/respawn_diagnostic.nim

import std/[os, strutils, strformat]
import environment
import agent_control
import types

proc main() =
  initGlobalController(BuiltinAI, seed = 42)
  var env = newEnvironment()

  # Check initial state
  echo "=== Initial State ==="
  var aliveCount = 0
  var deadCount = 0
  var hasHomeAltar = 0
  var noHomeAltar = 0
  for id in 0 ..< MapAgents:
    if env.terminated[id] == 0.0:
      inc aliveCount
      let agent = env.agents[id]
      if agent.homeAltar.x >= 0:
        inc hasHomeAltar
      else:
        inc noHomeAltar
    else:
      inc deadCount
  echo &"  Alive: {aliveCount}, Dead: {deadCount}"
  echo &"  With homeAltar: {hasHomeAltar}, Without: {noHomeAltar}"

  # Check pop caps
  echo ""
  echo "=== Initial Pop Caps ==="
  for teamId in 0 ..< MapRoomObjectsTeams:
    echo &"  Team {teamId}: popCap={env.stepTeamPopCaps[teamId]}, popCount={env.stepTeamPopCounts[teamId]}"

  # Count altars
  echo ""
  echo "=== Altars ==="
  for altar in env.thingsByKind[Altar]:
    echo &"  Altar at ({altar.pos.x},{altar.pos.y}) team={altar.teamId} hearts={altar.hearts}"

  # Count houses and TCs
  var housesByTeam: array[8, int]
  var tcsByTeam: array[8, int]
  for house in env.thingsByKind[House]:
    if house.teamId >= 0 and house.teamId < 8:
      inc housesByTeam[house.teamId]
  for tc in env.thingsByKind[TownCenter]:
    if tc.teamId >= 0 and tc.teamId < 8:
      inc tcsByTeam[tc.teamId]
  echo ""
  echo "=== Buildings ==="
  for t in 0 ..< 8:
    if housesByTeam[t] > 0 or tcsByTeam[t] > 0:
      echo &"  Team {t}: {housesByTeam[t]} houses, {tcsByTeam[t]} TCs, popCap={housesByTeam[t]*HousePopCap + tcsByTeam[t]*TownCenterPopCap}"

  echo ""
  echo &"  TownCenterPopCap = {TownCenterPopCap}"
  echo &"  HousePopCap = {HousePopCap}"
  echo &"  MapObjectAltarRespawnCost = {MapObjectAltarRespawnCost}"

  # Run 500 steps and track why respawns fail
  echo ""
  echo "=== Running 500 steps, tracking respawn blockers ==="
  var totalDeaths = 0
  var blockerNoAltar = 0
  var blockerPopCap = 0
  var blockerAltarMissing = 0
  var blockerNoSpace = 0
  var blockerNotDead = 0
  var totalRespawns = 0

  for i in 0 ..< 500:
    var actions = getActions(env)
    env.step(addr actions)

    # Check every dead agent for why they can't respawn
    if (i + 1) mod 100 == 0:
      var stepDeadWithAltar = 0
      var stepDeadNoAltar = 0
      var stepPopBlocked = 0
      var stepAltarGone = 0
      var stepNoSpace = 0
      var stepAlive = 0

      for id in 0 ..< MapAgents:
        if env.terminated[id] == 0.0:
          inc stepAlive
          continue
        let agent = env.agents[id]
        if agent.homeAltar.x < 0:
          inc stepDeadNoAltar
          continue
        inc stepDeadWithAltar
        let teamId = getTeamId(agent)
        if teamId < 0 or teamId >= MapRoomObjectsTeams:
          continue
        if env.stepTeamPopCounts[teamId] >= env.stepTeamPopCaps[teamId]:
          inc stepPopBlocked
          continue
        let altarThing = env.getThing(agent.homeAltar)
        if isNil(altarThing) or altarThing.kind != Altar:
          inc stepAltarGone
          continue
        if altarThing.hearts < MapObjectAltarRespawnCost:
          continue # hearts too low
        let respawnPos = env.findFirstEmptyPositionAround(altarThing.pos, 2)
        if respawnPos.x < 0:
          inc stepNoSpace
          continue

      echo &"  Step {i+1}: alive={stepAlive}, dead(noAltar)={stepDeadNoAltar}, dead(withAltar)={stepDeadWithAltar}"
      echo &"    Blockers: popCap={stepPopBlocked}, altarGone={stepAltarGone}, noSpace={stepNoSpace}"

      # Show team pop details
      for t in 0 ..< MapRoomObjectsTeams:
        if env.stepTeamPopCounts[t] > 0 or env.stepTeamPopCaps[t] > 0:
          echo &"    Team {t}: pop={env.stepTeamPopCounts[t]}/{env.stepTeamPopCaps[t]}"

main()
