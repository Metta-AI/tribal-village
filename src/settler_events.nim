## settler_events.nim - Event logging for settler migration system
##
## Gated behind -d:settlerLog compile flag. Zero-cost when disabled.
## Logs key events in the settler migration lifecycle: split checks,
## settler selection, arrival, town center placement, altar reassignment.
##
## Format: [Step N] TEAM_COLOR SETTLER: Event description
## Filter via TV_SETTLER_LOG env var: "0"/"false" to disable, anything else enables.

when defined(settlerLog):
  import std/os
  import types

  type
    SettlerEventKind* = enum
      seSplitCheck       ## Town split check triggered
      seSettlersSelected ## Settlers chosen for migration
      seSettlersArrived  ## Settlers arrived at target site
      seTownCenterPlaced ## New town center placed for settlement
      seAltarPlaced      ## New altar placed, homeAltar reassigned

    SettlerEvent* = object
      step*: int
      kind*: SettlerEventKind
      teamId*: int
      message*: string

  const TeamColorNames: array[8, string] = [
    "RED", "ORANGE", "YELLOW", "GREEN", "MAGENTA", "BLUE", "GRAY", "PINK"
  ]

  var settlerLogEnabled* = true
  var settlerLogInitialized = false

  proc teamName(teamId: int): string =
    if teamId >= 0 and teamId < TeamColorNames.len:
      TeamColorNames[teamId]
    else:
      "TEAM" & $teamId

  proc initSettlerLog*() =
    let envVal = getEnv("TV_SETTLER_LOG", "")
    settlerLogEnabled = envVal notin ["0", "false"]
    settlerLogInitialized = true

  proc ensureSettlerLogInit*() =
    if not settlerLogInitialized:
      initSettlerLog()

  proc logSettlerEvent*(kind: SettlerEventKind, teamId: int, message: string, step: int) =
    ensureSettlerLogInit()
    if not settlerLogEnabled:
      return
    echo "[Step " & $step & "] " & teamName(teamId) & " SETTLER: " & message

  proc logSplitCheck*(teamId: int, altarPos: IVec2, populationCount: int, step: int) =
    logSettlerEvent(seSplitCheck, teamId,
      "Split check at altar (" & $altarPos.x & "," & $altarPos.y &
      "), population=" & $populationCount, step)

  proc logSettlersSelected*(teamId: int, count: int, sourceAltar: IVec2, step: int) =
    logSettlerEvent(seSettlersSelected, teamId,
      $count & " settlers selected from altar (" &
      $sourceAltar.x & "," & $sourceAltar.y & ")", step)

  proc logSettlersArrived*(teamId: int, targetPos: IVec2, step: int) =
    logSettlerEvent(seSettlersArrived, teamId,
      "Settlers arrived at (" & $targetPos.x & "," & $targetPos.y & ")", step)

  proc logTownCenterPlaced*(teamId: int, pos: IVec2, distFromOriginal: float32, step: int) =
    logSettlerEvent(seTownCenterPlaced, teamId,
      "New town center at (" & $pos.x & "," & $pos.y &
      "), distance=" & $distFromOriginal, step)

  proc logAltarPlaced*(teamId: int, oldAltar: IVec2, newAltar: IVec2,
                       villagerCount: int, step: int) =
    logSettlerEvent(seAltarPlaced, teamId,
      "New altar at (" & $newAltar.x & "," & $newAltar.y &
      "), old=(" & $oldAltar.x & "," & $oldAltar.y &
      "), " & $villagerCount & " villagers reassigned", step)
