## Log human-readable game events.
##
## Gated behind `-d:eventLog` and compiled out when disabled.

when defined(eventLog):
  import
    std/[os, strutils],
    constants

  const
    EventSummaryDivider = "========================"
    EventSummaryDisabledValues = ["", "0", "false"]

  type
    EventCategory* = enum
      ecSpawn        ## Agent spawned.
      ecDeath        ## Agent died.
      ecBuildStart   ## Building construction started.
      ecBuildDone    ## Building construction completed.
      ecBuildDestroy ## Building destroyed.
      ecGather       ## Resource gathered.
      ecDeposit      ## Resource deposited.
      ecCombat       ## Combat hit.
      ecConversion   ## Monk conversion.
      ecResearch     ## Technology researched.
      ecTrade        ## Market trade.

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

  var
    eventLogState*: EventLogState
    eventLogInitialized = false

  proc categoryFromString(name: string): EventCategory =
    ## Convert one filter token into an event category.
    case name.toLowerAscii()
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
    else:
      ecCombat

  proc parseFilter(filterText: string): set[EventCategory] =
    ## Parse `TV_EVENT_FILTER` into a set of enabled categories.
    if filterText.len == 0 or filterText == "*" or
        filterText.toLowerAscii() == "all":
      return {
        ecSpawn,
        ecDeath,
        ecBuildStart,
        ecBuildDone,
        ecBuildDestroy,
        ecGather,
        ecDeposit,
        ecCombat,
        ecConversion,
        ecResearch,
        ecTrade
      }
    result = {}
    for part in filterText.split(','):
      let trimmed = part.strip()
      if trimmed.len > 0:
        result.incl(categoryFromString(trimmed))

  proc categoryLabel(category: EventCategory): string =
    ## Return the summary label for one event category.
    case category
    of ecSpawn:
      "Spawns"
    of ecDeath:
      "Deaths"
    of ecBuildStart:
      "Buildings Started"
    of ecBuildDone:
      "Buildings Completed"
    of ecBuildDestroy:
      "Buildings Destroyed"
    of ecGather:
      "Resources Gathered"
    of ecDeposit:
      "Resources Deposited"
    of ecCombat:
      "Combat Hits"
    of ecConversion:
      "Conversions"
    of ecResearch:
      "Tech Researched"
    of ecTrade:
      "Market Trades"

  proc initEventLog*() =
    ## Initialize event logging from environment variables.
    let filterEnv = getEnv("TV_EVENT_FILTER", "")
    let summaryEnv = getEnv("TV_EVENT_SUMMARY", "")
    eventLogState = EventLogState(
      enabled: true,
      filter: parseFilter(filterEnv),
      summaryMode: summaryEnv notin EventSummaryDisabledValues,
      events: @[],
      currentStep: 0
    )
    eventLogInitialized = true

  proc ensureEventLogInit*() =
    ## Initialize event logging on first use.
    if not eventLogInitialized:
      initEventLog()

  proc formatEvent(ev: GameEvent): string =
    ## Format one event for log output.
    "[Step " & $ev.step & "] " & teamColorName(ev.teamId) & " " & ev.message

  proc logEvent*(
    category: EventCategory,
    teamId: int,
    message: string,
    step: int
  ) =
    ## Log one event immediately or queue it for summary mode.
    ensureEventLogInit()
    if category notin eventLogState.filter:
      return
    let ev = GameEvent(step: step, category: category, teamId: teamId, message: message)
    if eventLogState.summaryMode:
      eventLogState.events.add(ev)
    else:
      echo formatEvent(ev)

  proc flushEventSummary*(step: int) =
    ## Print and clear the current step summary batch.
    ensureEventLogInit()
    if not eventLogState.summaryMode or eventLogState.events.len == 0:
      return
    echo "=== Step " & $step & " Events ==="
    var categoryCounts: array[EventCategory, int]
    for ev in eventLogState.events:
      inc categoryCounts[ev.category]
    for category in EventCategory:
      if categoryCounts[category] > 0:
        echo "  " & categoryLabel(category) & ": " &
          $categoryCounts[category]
    for ev in eventLogState.events:
      echo "  " & formatEvent(ev)
    echo EventSummaryDivider
    eventLogState.events.setLen(0)

  proc logCombatHit*(
    attackerTeam: int,
    targetTeam: int,
    attackerUnit: string,
    targetUnit: string,
    damage: int,
    step: int
  ) =
    ## Log one combat-hit event.
    let msg = attackerUnit & " hit " & teamColorName(targetTeam) & " " &
              targetUnit & " for " & $damage & " damage"
    logEvent(ecCombat, attackerTeam, msg, step)

  proc logConversion*(
    monkTeam: int,
    targetTeam: int,
    targetUnit: string,
    step: int
  ) =
    ## Log one monk-conversion event.
    let msg = "Monk converted " & teamColorName(targetTeam) & " " & targetUnit
    logEvent(ecConversion, monkTeam, msg, step)

  proc logTechResearched*(teamId: int, techName: string, step: int) =
    ## Log one completed research event.
    logEvent(ecResearch, teamId, "Researched " & techName, step)

  proc logMarketTrade*(
    teamId: int,
    action: string,
    resource: string,
    amount: int,
    goldAmount: int,
    step: int
  ) =
    ## Log one market-trade event.
    let msg = action & " " & $amount & " " & resource & " for " &
      $goldAmount & " gold"
    logEvent(ecTrade, teamId, msg, step)
