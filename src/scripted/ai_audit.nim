import ai_types
export ai_types

when defined(aiAudit):
  import std/[os, strformat, strutils]

  const
    AuditActionNames*: array[ActionVerbCount, string] = [
      "noop", "move", "attack", "use", "swap", "put",
      "plant_lantern", "plant_resource", "build", "orient", "set_rally_point"
    ]
    AuditRoleNames*: array[4, string] = ["Gatherer", "Builder", "Fighter", "Scripted"]
    AuditSummaryInterval* = 50

  type
    AuditDecisionBranch* = enum
      BranchInactive
      BranchDecisionDelay
      BranchStopped
      BranchGoblinRelic
      BranchGoblinAvoid
      BranchGoblinSearch
      BranchEscape
      BranchAttackOpportunity
      BranchPatrolChase
      BranchPatrolMove
      BranchRallyPoint
      BranchAttackMoveEngage
      BranchAttackMoveAdvance
      BranchSettlerMigrate
      BranchHearts
      BranchPopCapWood
      BranchPopCapBuild
      BranchRoleCatalog

    AuditRecord* = object
      agentId*: int
      teamId*: int
      role*: AgentRole
      verb*: int
      arg*: int
      branch*: AuditDecisionBranch

    AuditSummaryState* = object
      logLevel*: int
      stepDecisions*: seq[AuditRecord]
      verbCounts*: array[ActionVerbCount, int]
      roleCounts*: array[MapRoomObjectsTeams, array[4, int]]
      branchCounts*: array[AuditDecisionBranch, int]
      stepsAccumulated*: int
      totalDecisions*: int

  var
    auditSummary*: AuditSummaryState
    auditCurrentBranch*: AuditDecisionBranch

  proc initAuditLog*() =
    ## Initialize audit logging from environment configuration.
    let level = getEnv("TV_AI_LOG", "0")
    auditSummary.logLevel = try: parseInt(level) except: 0
    auditSummary.stepDecisions = @[]
    auditSummary.stepsAccumulated = 0
    auditSummary.totalDecisions = 0

  proc setAuditBranch*(branch: AuditDecisionBranch) {.inline.} =
    ## Record the current decision branch for the next audit event.
    auditCurrentBranch = branch

  proc recordAuditDecision*(agentId: int, teamId: int, role: AgentRole,
                            action: uint16) =
    ## Record one agent decision in the audit summary.
    if auditSummary.logLevel <= 0:
      return
    let verb = action.int div ActionArgumentCount
    let arg = action.int mod ActionArgumentCount
    let branch = auditCurrentBranch

    if verb >= 0 and verb < ActionVerbCount:
      inc auditSummary.verbCounts[verb]
    if teamId >= 0 and teamId < MapRoomObjectsTeams:
      inc auditSummary.roleCounts[teamId][ord(role)]
    inc auditSummary.branchCounts[branch]
    inc auditSummary.totalDecisions

    if auditSummary.logLevel >= 2:
      auditSummary.stepDecisions.add(AuditRecord(
        agentId: agentId,
        teamId: teamId,
        role: role,
        verb: verb,
        arg: arg,
        branch: branch
      ))

  proc printVerboseDecisions*(step: int) =
    ## Print the current step's verbose audit records.
    if auditSummary.logLevel < 2 or auditSummary.stepDecisions.len == 0:
      return
    echo &"[AI_AUDIT step={step}] {auditSummary.stepDecisions.len} decisions:"
    for d in auditSummary.stepDecisions:
      let verbName = if d.verb >= 0 and d.verb < ActionVerbCount:
                       AuditActionNames[d.verb]
                     else: $d.verb
      let roleName = if ord(d.role) < AuditRoleNames.len:
                       AuditRoleNames[ord(d.role)]
                     else: $d.role
      echo(
        &"  agent={d.agentId} team={d.teamId} role={roleName} " &
        &"action={verbName}:{d.arg} branch={d.branch}"
      )
    auditSummary.stepDecisions.setLen(0)

  proc printAuditSummary*(step: int) =
    ## Print verbose or summary audit output for the current step.
    if auditSummary.logLevel <= 0:
      return
    inc auditSummary.stepsAccumulated

    if auditSummary.logLevel >= 2:
      printVerboseDecisions(step)

    if auditSummary.stepsAccumulated mod AuditSummaryInterval != 0:
      return

    let total = auditSummary.totalDecisions
    if total == 0:
      return

    echo(
      &"\n[AI_AUDIT SUMMARY steps={step - AuditSummaryInterval + 1}.." &
      &"{step}] total_decisions={total}"
    )

    echo "  Action distribution:"
    for i in 0 ..< ActionVerbCount:
      let count = auditSummary.verbCounts[i]
      if count > 0:
        let pct = (count.float * 100.0) / total.float
        echo &"    {AuditActionNames[i]}: {count} ({pct:.1f}%)"

    echo "  Role distribution per team:"
    for teamId in 0 ..< MapRoomObjectsTeams:
      var teamTotal = 0
      for r in 0 ..< 4:
        teamTotal += auditSummary.roleCounts[teamId][r]
      if teamTotal > 0:
        var parts: seq[string] = @[]
        for r in 0 ..< 4:
          let c = auditSummary.roleCounts[teamId][r]
          if c > 0:
            let pct = (c.float * 100.0) / teamTotal.float
            parts.add(&"{AuditRoleNames[r]}={c}({pct:.0f}%)")
        echo &"    team {teamId}: {parts.join(\", \")}"

    echo "  Decision branches:"
    for branch in AuditDecisionBranch:
      let count = auditSummary.branchCounts[branch]
      if count > 0:
        let pct = (count.float * 100.0) / total.float
        echo &"    {branch}: {count} ({pct:.1f}%)"

    for i in 0 ..< ActionVerbCount:
      auditSummary.verbCounts[i] = 0
    for teamId in 0 ..< MapRoomObjectsTeams:
      for r in 0 ..< 4:
        auditSummary.roleCounts[teamId][r] = 0
    for branch in AuditDecisionBranch:
      auditSummary.branchCounts[branch] = 0
    auditSummary.totalDecisions = 0

else:
  template setAuditBranch*(branch: untyped) = discard
  template initAuditLog*() = discard
  template recordAuditDecision*(
    agentId,
    teamId: int,
    role: untyped,
    action: uint16
  ) = discard
  template printAuditSummary*(step: int) = discard
