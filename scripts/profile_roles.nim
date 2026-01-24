## Enhanced AI profiler with per-role action tracking
## Tracks success/failure rates for gatherer, builder, fighter roles
##
## Usage:
##   nim r -d:release --path:src scripts/profile_roles.nim
##   TV_PROFILE_STEPS=3000 nim r -d:release --path:src scripts/profile_roles.nim
##   TV_PROFILE_STEPS=3000 TV_PROFILE_REPORT_EVERY=500 nim r -d:release --path:src scripts/profile_roles.nim

import std/[os, strutils, strformat, tables, algorithm]
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

type
  RoleStats = object
    count: int          # Number of agents with this role
    actionNoop: int
    actionMove: int
    actionAttack: int
    actionUse: int
    actionSwap: int
    actionPlant: int
    actionPut: int
    actionBuild: int
    actionPlantResource: int
    actionOrient: int
    actionInvalid: int
    # Computed
    totalActions: int
    successRate: float

  ProfileReport = object
    steps: int
    totalAgents: int
    activeAgents: int
    byRole: Table[string, RoleStats]
    # Environment metrics
    maxHouses: array[MapRoomObjectsTeams, int]
    maxHearts: array[MapRoomObjectsTeams, int]
    finalHouses: array[MapRoomObjectsTeams, int]

proc roleToString(role: AgentRole): string =
  case role
  of Gatherer: "gatherer"
  of Builder: "builder"
  of Fighter: "fighter"
  of Scripted: "scripted"

proc initRoleStats(): RoleStats =
  RoleStats()

proc aggregateStats(env: Environment, controller: Controller): Table[string, RoleStats] =
  ## Aggregate per-agent stats by role
  result = initTable[string, RoleStats]()

  # Initialize all role buckets
  for role in AgentRole:
    result[roleToString(role)] = initRoleStats()
  result["dead"] = initRoleStats()
  result["unknown"] = initRoleStats()

  for agentId in 0 ..< env.agents.len:
    let agent = env.agents[agentId]
    let stats = env.stats[agentId]

    # Determine role bucket
    var bucket: string
    if isNil(agent) or agent.kind != Agent:
      bucket = "dead"
    elif controller.isAgentInitialized(agentId):
      bucket = roleToString(controller.getAgentRole(agentId))
    else:
      bucket = "unknown"

    # Aggregate stats
    result[bucket].count += 1
    if not isNil(stats):
      result[bucket].actionNoop += stats.actionNoop
      result[bucket].actionMove += stats.actionMove
      result[bucket].actionAttack += stats.actionAttack
      result[bucket].actionUse += stats.actionUse
      result[bucket].actionSwap += stats.actionSwap
      result[bucket].actionPlant += stats.actionPlant
      result[bucket].actionPut += stats.actionPut
      result[bucket].actionBuild += stats.actionBuild
      result[bucket].actionPlantResource += stats.actionPlantResource
      result[bucket].actionOrient += stats.actionOrient
      result[bucket].actionInvalid += stats.actionInvalid

proc computeDerivedStats(stats: var RoleStats) =
  stats.totalActions = stats.actionNoop + stats.actionMove + stats.actionAttack +
    stats.actionUse + stats.actionSwap + stats.actionPlant + stats.actionPut +
    stats.actionBuild + stats.actionPlantResource + stats.actionOrient + stats.actionInvalid

  let validActions = stats.totalActions - stats.actionInvalid - stats.actionNoop
  if stats.totalActions > 0:
    stats.successRate = validActions.float / stats.totalActions.float * 100.0

proc countHouses(env: Environment): array[MapRoomObjectsTeams, int] =
  var counts: array[MapRoomObjectsTeams, int]
  for house in env.thingsByKind[House]:
    let teamId = house.teamId
    if teamId >= 0 and teamId < counts.len:
      inc counts[teamId]
  counts

proc updateMaxHearts(env: Environment, maxHearts: var array[MapRoomObjectsTeams, int]) =
  for altar in env.thingsByKind[Altar]:
    let teamId = altar.teamId
    if teamId >= 0 and teamId < maxHearts.len:
      if altar.hearts > maxHearts[teamId]:
        maxHearts[teamId] = altar.hearts

proc formatActionBreakdown(stats: RoleStats, indent: string = "  "): string =
  var lines: seq[string] = @[]
  let total = stats.totalActions
  if total == 0:
    return indent & "(no actions)"

  proc pct(n: int): string =
    if total > 0:
      fmt"{n:>8} ({n.float / total.float * 100.0:5.1f}%)"
    else:
      fmt"{n:>8}"

  lines.add fmt"{indent}noop:     {pct(stats.actionNoop)}"
  lines.add fmt"{indent}move:     {pct(stats.actionMove)}"
  lines.add fmt"{indent}attack:   {pct(stats.actionAttack)}"
  lines.add fmt"{indent}use:      {pct(stats.actionUse)}"
  lines.add fmt"{indent}swap:     {pct(stats.actionSwap)}"
  lines.add fmt"{indent}plant:    {pct(stats.actionPlant)}"
  lines.add fmt"{indent}put:      {pct(stats.actionPut)}"
  lines.add fmt"{indent}build:    {pct(stats.actionBuild)}"
  lines.add fmt"{indent}plantRes: {pct(stats.actionPlantResource)}"
  lines.add fmt"{indent}orient:   {pct(stats.actionOrient)}"
  lines.add fmt"{indent}INVALID:  {pct(stats.actionInvalid)}"
  lines.join("\n")

proc printReport(report: ProfileReport) =
  echo "\n" & "=".repeat(60)
  echo "PROFILE REPORT"
  echo "=".repeat(60)
  echo fmt"Steps: {report.steps}"
  echo fmt"Total agents: {report.totalAgents}"
  echo fmt"Active agents: {report.activeAgents}"
  echo ""

  # Sort roles for consistent output
  var roles = @["gatherer", "builder", "fighter", "scripted", "dead", "unknown"]

  for roleName in roles:
    if roleName in report.byRole:
      var stats = report.byRole[roleName]
      computeDerivedStats(stats)

      if stats.count > 0:
        echo fmt"--- {roleName.toUpperAscii()} ({stats.count} agents) ---"
        echo fmt"  Total actions: {stats.totalActions}"
        echo fmt"  Success rate:  {stats.successRate:5.1f}% (excluding noop/invalid)"
        echo fmt"  Invalid rate:  {stats.actionInvalid.float / max(1, stats.totalActions).float * 100.0:5.1f}%"
        echo "  Action breakdown:"
        echo formatActionBreakdown(stats, "    ")
        echo ""

  echo "--- TEAM METRICS ---"
  for teamId in 0 ..< report.maxHouses.len:
    if report.maxHouses[teamId] > 0 or report.finalHouses[teamId] > 0:
      echo fmt"  Team {teamId}: houses={report.finalHouses[teamId]} (max={report.maxHouses[teamId]}), max_hearts={report.maxHearts[teamId]}"

  echo "=".repeat(60)

when isMainModule:
  let steps = max(1, parseEnvInt("TV_PROFILE_STEPS", 3000))
  let reportEvery = max(0, parseEnvInt("TV_PROFILE_REPORT_EVERY", 0))
  let seed = parseEnvInt("TV_PROFILE_SEED", 42)

  echo fmt"Starting profile run: {steps} steps, seed={seed}"

  var env = newEnvironment()
  initGlobalController(BuiltinAI, seed)
  let controller = globalController.aiController

  var maxHouses = countHouses(env)
  var maxHearts: array[MapRoomObjectsTeams, int]
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
      echo fmt"Step {step}/{steps}..."

  # Build final report
  var report = ProfileReport(
    steps: steps,
    totalAgents: MapAgents,
    activeAgents: env.agents.len,
    byRole: aggregateStats(env, controller),
    maxHouses: maxHouses,
    maxHearts: maxHearts,
    finalHouses: countHouses(env)
  )

  printReport(report)
  echo "\nProfile complete."
