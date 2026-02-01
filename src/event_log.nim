## event_log.nim - Human-readable game event logging
##
## Gated behind -d:eventLog compile flag. Zero-cost when disabled.
## Logs key game events as they happen: spawns, deaths, building construction,
## resource gathering/depositing, combat, monk conversions, tech research, market trades.
##
## Format: [Step N] TEAM_COLOR Event description
## Filter via TV_EVENT_FILTER env var (e.g., 'combat,death,building')
## Summary mode batches events per step instead of printing each one.

when defined(eventLog):
  import std/[strutils, os, tables, sequtils]

  type
    EventCategory* = enum
      ecSpawn       ## Agent spawned
      ecDeath       ## Agent died
      ecBuildStart  ## Building construction started
      ecBuildDone   ## Building construction completed
      ecBuildDestroy ## Building destroyed
      ecGather      ## Resource gathered
      ecDeposit     ## Resource deposited
      ecCombat      ## Combat hit
      ecConversion  ## Monk conversion
      ecResearch    ## Technology researched
      ecTrade       ## Market trade

    GameEvent* = object
      step*: int
      category*: EventCategory
      teamId*: int
      message*: string

    EventLogState* = object
      enabled*: bool
      filter*: set[EventCategory]
      summaryMode*: bool
      events*: seq[GameEvent]
      currentStep*: int

  const TeamColorNames*: array[8, string] = [
    "RED", "ORANGE", "YELLOW", "GREEN", "MAGENTA", "BLUE", "GRAY", "PINK"
  ]

  var eventLogState*: EventLogState
  var eventLogInitialized = false

  proc categoryFromString(s: string): EventCategory =
    case s.toLowerAscii()
    of "spawn": ecSpawn
    of "death": ecDeath
    of "buildstart", "building_start": ecBuildStart
    of "builddone", "building_done", "building": ecBuildDone
    of "builddestroy", "building_destroy": ecBuildDestroy
    of "gather": ecGather
    of "deposit": ecDeposit
    of "combat", "hit": ecCombat
    of "conversion", "convert": ecConversion
    of "research", "tech": ecResearch
    of "trade", "market": ecTrade
    else: ecCombat  # Default fallback

  proc parseFilter(filterStr: string): set[EventCategory] =
    if filterStr.len == 0 or filterStr == "*" or filterStr.toLowerAscii() == "all":
      return {ecSpawn, ecDeath, ecBuildStart, ecBuildDone, ecBuildDestroy,
              ecGather, ecDeposit, ecCombat, ecConversion, ecResearch, ecTrade}
    result = {}
    for part in filterStr.split(','):
      let trimmed = part.strip()
      if trimmed.len > 0:
        result.incl(categoryFromString(trimmed))

  proc initEventLog*() =
    let filterEnv = getEnv("TV_EVENT_FILTER", "")
    let summaryEnv = getEnv("TV_EVENT_SUMMARY", "")
    eventLogState = EventLogState(
      enabled: true,
      filter: parseFilter(filterEnv),
      summaryMode: summaryEnv notin ["", "0", "false"],
      events: @[],
      currentStep: 0
    )
    eventLogInitialized = true

  proc ensureEventLogInit*() =
    if not eventLogInitialized:
      initEventLog()

  proc teamColorName*(teamId: int): string =
    if teamId >= 0 and teamId < TeamColorNames.len:
      TeamColorNames[teamId]
    elif teamId == 8:
      "GOBLIN"
    else:
      "NEUTRAL"

  proc formatEvent(ev: GameEvent): string =
    "[Step " & $ev.step & "] " & teamColorName(ev.teamId) & " " & ev.message

  proc logEvent*(category: EventCategory, teamId: int, message: string, step: int) =
    ensureEventLogInit()
    if category notin eventLogState.filter:
      return
    let ev = GameEvent(step: step, category: category, teamId: teamId, message: message)
    if eventLogState.summaryMode:
      eventLogState.events.add(ev)
    else:
      echo formatEvent(ev)

  proc flushEventSummary*(step: int) =
    ## In summary mode, print batched events at end of step
    ensureEventLogInit()
    if not eventLogState.summaryMode or eventLogState.events.len == 0:
      return
    echo "=== Step " & $step & " Events ==="
    var categoryCounts: array[EventCategory, int]
    for ev in eventLogState.events:
      inc categoryCounts[ev.category]
    for cat in EventCategory:
      if categoryCounts[cat] > 0:
        let catName = case cat
          of ecSpawn: "Spawns"
          of ecDeath: "Deaths"
          of ecBuildStart: "Buildings Started"
          of ecBuildDone: "Buildings Completed"
          of ecBuildDestroy: "Buildings Destroyed"
          of ecGather: "Resources Gathered"
          of ecDeposit: "Resources Deposited"
          of ecCombat: "Combat Hits"
          of ecConversion: "Conversions"
          of ecResearch: "Tech Researched"
          of ecTrade: "Market Trades"
        echo "  " & catName & ": " & $categoryCounts[cat]
    # Print individual events
    for ev in eventLogState.events:
      echo "  " & formatEvent(ev)
    echo "========================"
    eventLogState.events.setLen(0)

  # Convenience logging procs for specific event types
  proc logSpawn*(teamId: int, unitClass: string, pos: string, step: int) =
    logEvent(ecSpawn, teamId, "Spawned " & unitClass & " at " & pos, step)

  proc logDeath*(teamId: int, unitClass: string, pos: string, step: int) =
    logEvent(ecDeath, teamId, unitClass & " died at " & pos, step)

  proc logBuildingStarted*(teamId: int, buildingKind: string, pos: string, step: int) =
    logEvent(ecBuildStart, teamId, "Started building " & buildingKind & " at " & pos, step)

  proc logBuildingCompleted*(teamId: int, buildingKind: string, pos: string, step: int) =
    logEvent(ecBuildDone, teamId, "Completed " & buildingKind & " at " & pos, step)

  proc logBuildingDestroyed*(teamId: int, buildingKind: string, pos: string, step: int) =
    logEvent(ecBuildDestroy, teamId, buildingKind & " destroyed at " & pos, step)

  proc logResourceGathered*(teamId: int, resourceKind: string, amount: int, step: int) =
    logEvent(ecGather, teamId, "Gathered " & $amount & " " & resourceKind, step)

  proc logResourceDeposited*(teamId: int, resourceKind: string, amount: int, step: int) =
    logEvent(ecDeposit, teamId, "Deposited " & $amount & " " & resourceKind, step)

  proc logCombatHit*(attackerTeam: int, targetTeam: int, attackerUnit: string,
                     targetUnit: string, damage: int, step: int) =
    let msg = attackerUnit & " hit " & teamColorName(targetTeam) & " " &
              targetUnit & " for " & $damage & " damage"
    logEvent(ecCombat, attackerTeam, msg, step)

  proc logConversion*(monkTeam: int, targetTeam: int, targetUnit: string, step: int) =
    let msg = "Monk converted " & teamColorName(targetTeam) & " " & targetUnit
    logEvent(ecConversion, monkTeam, msg, step)

  proc logTechResearched*(teamId: int, techName: string, step: int) =
    logEvent(ecResearch, teamId, "Researched " & techName, step)

  proc logMarketTrade*(teamId: int, action: string, resource: string,
                       amount: int, goldAmount: int, step: int) =
    let msg = action & " " & $amount & " " & resource & " for " & $goldAmount & " gold"
    logEvent(ecTrade, teamId, msg, step)
