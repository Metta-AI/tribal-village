# Population and unit composition audit tracker
# Gate: compile with -d:popAudit to enable
# Included by step.nim when defined(popAudit)

import std/[strutils, strformat]

const
  PopAuditInterval* = 50  # Print dashboard every N steps

type
  PopAuditSnapshot = object
    totalPop: int
    villagerCount: int
    infantryCount: int
    cavalryCount: int
    archerCount: int
    monkCount: int
    siegeCount: int
    idleCount: int
    deadCount: int
    buildings: array[ThingKind, int]

var
  prevSnapshots: array[MapRoomObjectsTeams, PopAuditSnapshot]
  popAuditInitialized: bool

proc isInfantry(uc: AgentUnitClass): bool =
  uc in {UnitManAtArms, UnitLongSwordsman, UnitChampion,
         UnitSamurai, UnitWoadRaider, UnitTeutonicKnight, UnitHuskarl, UnitJanissary}

proc isCavalry(uc: AgentUnitClass): bool =
  uc in {UnitScout, UnitKnight, UnitLightCavalry, UnitHussar,
         UnitCataphract, UnitMameluke}

proc isArcher(uc: AgentUnitClass): bool =
  uc in {UnitArcher, UnitCrossbowman, UnitArbalester, UnitLongbowman}

proc isSiege(uc: AgentUnitClass): bool =
  uc in {UnitBatteringRam, UnitMangonel, UnitTrebuchet}

proc popAuditStep*(env: Environment) =
  if env.currentStep mod PopAuditInterval != 0:
    return

  var snapshots: array[MapRoomObjectsTeams, PopAuditSnapshot]

  # Count agents per team
  for i in 0 ..< MapAgents:
    let agent = env.agents[i]
    let teamId = getTeamId(i)
    if teamId < 0 or teamId >= MapRoomObjectsTeams:
      continue

    if agent.isNil or env.terminated[i] != 0.0 or not isValidPos(agent.pos):
      snapshots[teamId].deadCount.inc
      continue

    snapshots[teamId].totalPop.inc
    let uc = agent.unitClass

    if uc == UnitVillager:
      snapshots[teamId].villagerCount.inc
    elif isInfantry(uc):
      snapshots[teamId].infantryCount.inc
    elif isCavalry(uc):
      snapshots[teamId].cavalryCount.inc
    elif isArcher(uc):
      snapshots[teamId].archerCount.inc
    elif uc == UnitMonk:
      snapshots[teamId].monkCount.inc
    elif isSiege(uc):
      snapshots[teamId].siegeCount.inc
    # else: King, Goblin, Boat, TradeCog etc - counted in totalPop only

    if agent.isIdle:
      snapshots[teamId].idleCount.inc

  # Count buildings per team
  for thing in env.things:
    if thing.isNil:
      continue
    if isBuildingKind(thing.kind) and thing.teamId >= 0 and thing.teamId < MapRoomObjectsTeams:
      snapshots[thing.teamId].buildings[thing.kind].inc

  # Compute pop caps per team
  var teamPopCaps: array[MapRoomObjectsTeams, int]
  for teamId in 0 ..< MapRoomObjectsTeams:
    teamPopCaps[teamId] = snapshots[teamId].buildings[TownCenter] * TownCenterPopCap +
                           snapshots[teamId].buildings[House] * HousePopCap
    if teamPopCaps[teamId] > MapAgentsPerTeam:
      teamPopCaps[teamId] = MapAgentsPerTeam

  # Print dashboard
  echo "═══════════════════════════════════════════════════════════════"
  echo &"  POPULATION AUDIT · Step {env.currentStep}"
  echo "═══════════════════════════════════════════════════════════════"

  for teamId in 0 ..< MapRoomObjectsTeams:
    let s = snapshots[teamId]
    if s.totalPop == 0 and s.deadCount == 0:
      continue

    let popCap = teamPopCaps[teamId]
    let militaryCount = s.infantryCount + s.cavalryCount + s.archerCount +
                        s.monkCount + s.siegeCount
    let total = max(s.totalPop, 1)

    # Trend indicator
    var trend = "~"
    if popAuditInitialized:
      let prev = prevSnapshots[teamId].totalPop
      if s.totalPop > prev + 2:
        trend = "▲"
      elif s.totalPop < prev - 2:
        trend = "▼"

    let villPct = (s.villagerCount * 100) div total
    let milPct = (militaryCount * 100) div total
    let idlePct = if s.totalPop > 0: (s.idleCount * 100) div s.totalPop else: 0

    echo &"  T{teamId} {trend} Pop: {s.totalPop}/{popCap} | Dead: {s.deadCount}"
    echo &"     Villagers: {s.villagerCount} ({villPct}%) | Military: {militaryCount} ({milPct}%) | Idle: {s.idleCount} ({idlePct}%)"
    echo &"     Inf: {s.infantryCount} Cav: {s.cavalryCount} Arch: {s.archerCount} Monk: {s.monkCount} Siege: {s.siegeCount}"

    # Building inventory (only non-zero)
    var bldgs: seq[string] = @[]
    for kind in ThingKind:
      if s.buildings[kind] > 0:
        bldgs.add($kind & ":" & $s.buildings[kind])
    if bldgs.len > 0:
      echo "     Bldg: " & bldgs.join(" ")

  echo "───────────────────────────────────────────────────────────────"

  prevSnapshots = snapshots
  popAuditInitialized = true
