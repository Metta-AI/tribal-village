## state_dumper.nim - Game state snapshot dumper for offline analysis
##
## Serializes key game state to JSON files at configurable intervals.
## Controlled via environment variables:
##   TV_DUMP_INTERVAL - dump every N steps (0 or unset = disabled)
##   TV_DUMP_DIR      - output directory (default: ./dumps/)

import std/[json, os, times, strformat, strutils]
import types, items

var
  dumpInterval*: int = 0
  dumpDir*: string = "./dumps/"
  dumpInitialized: bool = false

proc initDumper*() =
  ## Initialize dump settings from environment variables.
  let intervalStr = getEnv("TV_DUMP_INTERVAL", "0")
  dumpInterval = try: parseInt(intervalStr) except ValueError: 0
  dumpDir = getEnv("TV_DUMP_DIR", "./dumps/")
  if dumpInterval > 0:
    createDir(dumpDir)
  dumpInitialized = true

proc dumpAgents(env: Environment): JsonNode =
  ## Serialize all agents as compact arrays: [agentId, x, y, hp, maxHp, teamId, unitClass, stance, inventoryItemCount]
  var arr = newJArray()
  for agent in env.liveAgents:
    let alive = env.terminated[agent.agentId] == 0.0
    var a = newJArray()
    a.add(%agent.agentId)
    a.add(%agent.pos.x)
    a.add(%agent.pos.y)
    a.add(%agent.hp)
    a.add(%agent.maxHp)
    a.add(%agent.getTeamId())
    a.add(%ord(agent.unitClass))
    a.add(%ord(agent.stance))
    a.add(%agent.inventory.len)
    a.add(%(if alive: 1 else: 0))
    arr.add(a)
  return arr

proc dumpThings(env: Environment): JsonNode =
  ## Serialize all non-agent things as compact arrays: [kind, x, y, hp, maxHp, teamId]
  var arr = newJArray()
  for thing in env.things:
    if thing.isNil or thing.kind == Agent:
      continue
    var t = newJArray()
    t.add(%ord(thing.kind))
    t.add(%thing.pos.x)
    t.add(%thing.pos.y)
    t.add(%thing.hp)
    t.add(%thing.maxHp)
    t.add(%thing.teamId)
    arr.add(t)
  return arr

proc dumpTeamResources(env: Environment): JsonNode =
  ## Serialize team stockpiles as arrays: [food, wood, gold, stone, water]
  var arr = newJArray()
  for teamId in 0 ..< MapRoomObjectsTeams:
    var team = newJArray()
    for res in StockpileResource:
      team.add(%env.teamStockpiles[teamId].counts[res])
    arr.add(team)
  return arr

proc dumpTeamPopulations(env: Environment): JsonNode =
  ## Count alive agents per team
  var counts: array[MapRoomObjectsTeams, int]
  for agent in env.liveAgents:
    if env.terminated[agent.agentId] == 0.0:
      let tid = agent.getTeamId()
      if tid >= 0 and tid < MapRoomObjectsTeams:
        inc counts[tid]
  var arr = newJArray()
  for teamId in 0 ..< MapRoomObjectsTeams:
    arr.add(%counts[teamId])
  return arr

proc dumpSpatialIndexStats(env: Environment): JsonNode =
  ## Summary stats about spatial index occupancy
  var nonEmpty = 0
  var maxCount = 0
  var totalThings = 0
  for cx in 0 ..< SpatialCellsX:
    for cy in 0 ..< SpatialCellsY:
      let count = env.spatialIndex.cells[cx][cy].things.len
      if count > 0:
        inc nonEmpty
        totalThings += count
        if count > maxCount:
          maxCount = count
  return %*{
    "cells_total": SpatialCellsX * SpatialCellsY,
    "cells_occupied": nonEmpty,
    "things_indexed": totalThings,
    "max_per_cell": maxCount
  }

proc dumpState*(env: Environment) =
  ## Dump full game state to a timestamped JSON file.
  if not dumpInitialized:
    initDumper()

  let now = now()
  let timestamp = now.format("yyyyMMdd'T'HHmmss'.'fff")
  let filename = dumpDir / &"state_step{env.currentStep:06d}_{timestamp}.json"

  var root = newJObject()
  root["step"] = %env.currentStep
  root["timestamp"] = %($now)
  root["map_width"] = %MapWidth
  root["map_height"] = %MapHeight
  root["num_teams"] = %MapRoomObjectsTeams
  root["victory_winner"] = %env.victoryWinner

  # Agent fields: [agentId, x, y, hp, maxHp, teamId, unitClass, stance, invCount, alive]
  root["agent_fields"] = %["agentId", "x", "y", "hp", "maxHp", "teamId", "unitClass", "stance", "invCount", "alive"]
  root["agents"] = dumpAgents(env)

  # Thing fields: [kind, x, y, hp, maxHp, teamId]
  root["thing_fields"] = %["kind", "x", "y", "hp", "maxHp", "teamId"]
  root["things"] = dumpThings(env)

  root["team_resource_fields"] = %["food", "wood", "gold", "stone", "water", "none"]
  root["team_resources"] = dumpTeamResources(env)
  root["team_populations"] = dumpTeamPopulations(env)
  root["spatial_index"] = dumpSpatialIndexStats(env)

  writeFile(filename, $root)

proc maybeDumpState*(env: Environment) =
  ## Called each step; dumps state if interval is configured and step matches.
  if not dumpInitialized:
    initDumper()
  if dumpInterval > 0 and env.currentStep mod dumpInterval == 0:
    dumpState(env)
