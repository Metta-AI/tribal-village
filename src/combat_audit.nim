## combat_audit.nim - Combat event audit logging
##
## Gated behind -d:combatAudit compile flag. Zero-cost when disabled.
## Tracks damage dealt, kills, healing, monk conversions, and siege damage.
## Prints periodic combat reports to console every N steps.

when defined(combatAudit):
  import std/[strutils, tables, algorithm, os]

  type
    CombatEventKind* = enum
      ceDamage       ## Damage dealt to an agent
      ceKill         ## Agent killed
      ceHeal         ## Agent healed
      ceConversion   ## Monk conversion
      ceSiegeDamage  ## Siege/structure damage
      ceBuildingDestroyed ## Building destroyed

    CombatEvent* = object
      step*: int
      kind*: CombatEventKind
      attackerTeam*: int
      targetTeam*: int
      attackerUnit*: string
      targetUnit*: string
      attackerId*: int
      targetId*: int
      amount*: int          ## Damage/heal amount
      damageType*: string   ## "melee", "ranged", "siege", "tower", "aoe"

    TeamCombatStats* = object
      totalDamageDealt*: int
      totalDamageTaken*: int
      kills*: int
      deaths*: int
      healsGiven*: int
      healAmount*: int
      conversions*: int
      buildingsDestroyed*: int
      siegeDamageDealt*: int
      damageByType*: Table[string, int]       ## damage type -> amount
      killsByUnit*: Table[string, int]         ## unit class -> kill count

    CombatAuditState* = object
      events*: seq[CombatEvent]
      teamStats*: array[9, TeamCombatStats]    ## 8 teams + goblin
      reportInterval*: int
      verbose*: bool
      lastReportStep*: int

  var auditState*: CombatAuditState
  var auditInitialized = false

  proc initCombatAudit*() =
    auditState = CombatAuditState(
      events: @[],
      reportInterval: max(1, parseEnvInt("TV_COMBAT_REPORT_INTERVAL", 100)),
      verbose: parseEnvBool("TV_COMBAT_VERBOSE", false),
      lastReportStep: 0
    )
    for i in 0 ..< auditState.teamStats.len:
      auditState.teamStats[i].damageByType = initTable[string, int]()
      auditState.teamStats[i].killsByUnit = initTable[string, int]()
    auditInitialized = true

  proc ensureCombatAuditInit*() =
    if not auditInitialized:
      initCombatAudit()

  proc recordDamage*(step, attackerTeam, targetTeam, attackerId, targetId, amount: int,
                     attackerUnit, targetUnit, damageType: string) =
    let ev = CombatEvent(
      step: step, kind: ceDamage,
      attackerTeam: attackerTeam, targetTeam: targetTeam,
      attackerUnit: attackerUnit, targetUnit: targetUnit,
      attackerId: attackerId, targetId: targetId,
      amount: amount, damageType: damageType
    )
    if auditState.verbose:
      auditState.events.add(ev)
    if attackerTeam >= 0 and attackerTeam < auditState.teamStats.len:
      auditState.teamStats[attackerTeam].totalDamageDealt += amount
      let dt = auditState.teamStats[attackerTeam].damageByType.getOrDefault(damageType, 0)
      auditState.teamStats[attackerTeam].damageByType[damageType] = dt + amount
    if targetTeam >= 0 and targetTeam < auditState.teamStats.len:
      auditState.teamStats[targetTeam].totalDamageTaken += amount

  proc recordKill*(step, killerTeam, victimTeam, killerId, victimId: int,
                   killerUnit, victimUnit: string) =
    let ev = CombatEvent(
      step: step, kind: ceKill,
      attackerTeam: killerTeam, targetTeam: victimTeam,
      attackerUnit: killerUnit, targetUnit: victimUnit,
      attackerId: killerId, targetId: victimId
    )
    if auditState.verbose:
      auditState.events.add(ev)
    if killerTeam >= 0 and killerTeam < auditState.teamStats.len:
      auditState.teamStats[killerTeam].kills += 1
      let kc = auditState.teamStats[killerTeam].killsByUnit.getOrDefault(killerUnit, 0)
      auditState.teamStats[killerTeam].killsByUnit[killerUnit] = kc + 1
    if victimTeam >= 0 and victimTeam < auditState.teamStats.len:
      auditState.teamStats[victimTeam].deaths += 1

  proc recordHeal*(step, healerTeam, targetTeam, healerId, targetId, amount: int,
                   healerUnit, targetUnit: string) =
    let ev = CombatEvent(
      step: step, kind: ceHeal,
      attackerTeam: healerTeam, targetTeam: targetTeam,
      attackerUnit: healerUnit, targetUnit: targetUnit,
      attackerId: healerId, targetId: targetId,
      amount: amount
    )
    if auditState.verbose:
      auditState.events.add(ev)
    if healerTeam >= 0 and healerTeam < auditState.teamStats.len:
      auditState.teamStats[healerTeam].healsGiven += 1
      auditState.teamStats[healerTeam].healAmount += amount

  proc recordConversion*(step, monkTeam, targetTeam, monkId, targetId: int,
                         targetUnit: string) =
    let ev = CombatEvent(
      step: step, kind: ceConversion,
      attackerTeam: monkTeam, targetTeam: targetTeam,
      attackerUnit: "Monk", targetUnit: targetUnit,
      attackerId: monkId, targetId: targetId
    )
    if auditState.verbose:
      auditState.events.add(ev)
    if monkTeam >= 0 and monkTeam < auditState.teamStats.len:
      auditState.teamStats[monkTeam].conversions += 1

  proc recordSiegeDamage*(step, attackerTeam: int, buildingKind: string,
                          targetTeam, amount: int, attackerUnit: string,
                          destroyed: bool) =
    if auditState.verbose:
      auditState.events.add(CombatEvent(
        step: step,
        kind: if destroyed: ceBuildingDestroyed else: ceSiegeDamage,
        attackerTeam: attackerTeam, targetTeam: targetTeam,
        attackerUnit: attackerUnit, targetUnit: buildingKind,
        amount: amount, damageType: "siege"
      ))
    if attackerTeam >= 0 and attackerTeam < auditState.teamStats.len:
      auditState.teamStats[attackerTeam].siegeDamageDealt += amount
      if destroyed:
        auditState.teamStats[attackerTeam].buildingsDestroyed += 1

  proc formatRatio(a, b: int): string =
    if b == 0:
      if a == 0: "0.00" else: $a & ".00"
    else:
      formatFloat(a.float / b.float, ffDecimal, 2)

  proc printCombatReport*(currentStep: int) =
    if currentStep - auditState.lastReportStep < auditState.reportInterval:
      return
    auditState.lastReportStep = currentStep

    echo "═══════════════════════════════════════════════════════"
    echo "  COMBAT REPORT — Step ", currentStep
    echo "═══════════════════════════════════════════════════════"

    # Per-team summary
    for teamId in 0 ..< 9:
      let s = auditState.teamStats[teamId]
      if s.totalDamageDealt == 0 and s.totalDamageTaken == 0 and
         s.kills == 0 and s.deaths == 0:
        continue
      let teamLabel = if teamId < 8: "Team " & $teamId else: "Goblins"
      echo "  ", teamLabel, ":"
      echo "    Damage: dealt=", s.totalDamageDealt, " taken=", s.totalDamageTaken
      echo "    Kills=", s.kills, " Deaths=", s.deaths,
           " K/D=", formatRatio(s.kills, s.deaths)
      if s.healsGiven > 0:
        echo "    Heals: count=", s.healsGiven, " amount=", s.healAmount
      if s.conversions > 0:
        echo "    Conversions: ", s.conversions
      if s.siegeDamageDealt > 0:
        echo "    Siege damage: ", s.siegeDamageDealt,
             " buildings destroyed=", s.buildingsDestroyed

      # Damage type breakdown
      if s.damageByType.len > 0:
        var parts: seq[string] = @[]
        for dtype, amt in s.damageByType:
          parts.add(dtype & "=" & $amt)
        parts.sort()
        echo "    Damage by type: ", parts.join(", ")

      # Most lethal unit types
      if s.killsByUnit.len > 0:
        var pairs: seq[(string, int)] = @[]
        for unit, count in s.killsByUnit:
          pairs.add((unit, count))
        pairs.sort(proc(a, b: (string, int)): int = cmp(b[1], a[1]))
        var parts: seq[string] = @[]
        for (unit, count) in pairs:
          parts.add(unit & "=" & $count)
        echo "    Kills by unit: ", parts.join(", ")

    echo "═══════════════════════════════════════════════════════"

    # Verbose mode: print per-fight details
    if auditState.verbose and auditState.events.len > 0:
      echo "  DETAILED EVENTS (last interval):"
      for ev in auditState.events:
        case ev.kind
        of ceDamage:
          echo "    [", ev.step, "] T", ev.attackerTeam, " ", ev.attackerUnit,
               "(", ev.attackerId, ") -> T", ev.targetTeam, " ", ev.targetUnit,
               "(", ev.targetId, ") dmg=", ev.amount, " (", ev.damageType, ")"
        of ceKill:
          echo "    [", ev.step, "] KILL T", ev.attackerTeam, " ", ev.attackerUnit,
               "(", ev.attackerId, ") killed T", ev.targetTeam, " ", ev.targetUnit,
               "(", ev.targetId, ")"
        of ceHeal:
          echo "    [", ev.step, "] HEAL T", ev.attackerTeam, " ", ev.attackerUnit,
               "(", ev.attackerId, ") -> T", ev.targetTeam, " ", ev.targetUnit,
               "(", ev.targetId, ") hp=+", ev.amount
        of ceConversion:
          echo "    [", ev.step, "] CONVERT T", ev.attackerTeam, " Monk(",
               ev.attackerId, ") converted T", ev.targetTeam, " ", ev.targetUnit,
               "(", ev.targetId, ")"
        of ceSiegeDamage:
          echo "    [", ev.step, "] SIEGE T", ev.attackerTeam, " ", ev.attackerUnit,
               "(", ev.attackerId, ") -> ", ev.targetUnit, " dmg=", ev.amount
        of ceBuildingDestroyed:
          echo "    [", ev.step, "] DESTROYED T", ev.attackerTeam, " ", ev.attackerUnit,
               "(", ev.attackerId, ") destroyed ", ev.targetUnit
      echo "═══════════════════════════════════════════════════════"
      # Clear events after printing
      auditState.events.setLen(0)
