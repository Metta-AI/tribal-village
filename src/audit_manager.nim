## audit_manager.nim - Centralized audit orchestration
##
## Provides unified initialization, flushing, and status checking for all
## audit subsystems. Each audit module registers with this manager.
##
## Compile flags: -d:combatAudit, -d:econAudit, -d:techAudit, -d:actionAudit,
##                -d:tumorAudit, -d:aiAudit
##
## Usage:
##   initAllAudits()           - Call once at startup
##   flushAllAudits(env, step) - Call at end of each step
##   isAuditEnabled(kind)      - Check if specific audit is compiled in

import types

when defined(combatAudit):
  import combat_audit as ca

when defined(econAudit):
  import econ_audit as ea

when defined(techAudit):
  import tech_audit as ta

when defined(actionAudit):
  import action_audit as aa

when defined(tumorAudit):
  import tumor_audit as tua

when defined(aiAudit):
  import scripted/ai_audit as aia

type
  AuditKind* = enum
    akCombat
    akEcon
    akTech
    akAction
    akTumor
    akAi

proc isAuditEnabled*(kind: AuditKind): bool =
  ## Check if a specific audit type is compiled in.
  case kind
  of akCombat:
    when defined(combatAudit): true else: false
  of akEcon:
    when defined(econAudit): true else: false
  of akTech:
    when defined(techAudit): true else: false
  of akAction:
    when defined(actionAudit): true else: false
  of akTumor:
    when defined(tumorAudit): true else: false
  of akAi:
    when defined(aiAudit): true else: false

proc getEnabledAudits*(): seq[AuditKind] =
  ## Return list of all enabled audit types.
  result = @[]
  for kind in AuditKind:
    if isAuditEnabled(kind):
      result.add(kind)

proc initAllAudits*() =
  ## Initialize all enabled audit subsystems.
  ## Call once at application startup.
  when defined(combatAudit):
    ca.initCombatAudit()
  when defined(econAudit):
    ea.initEconAudit()
  when defined(techAudit):
    ta.initTechAudit()
  when defined(actionAudit):
    aa.initActionAudit()
  when defined(tumorAudit):
    tua.initTumorAudit()
  when defined(aiAudit):
    aia.initAuditLog()

proc flushAllAudits*(env: Environment, step: int) =
  ## Print/flush reports from all enabled audit subsystems.
  ## Call at end of each simulation step.
  when defined(combatAudit):
    ca.printCombatReport(step)
  when defined(tumorAudit):
    tua.printTumorReport(env)
  when defined(actionAudit):
    aa.printActionAuditReport(step)
  when defined(techAudit):
    ta.maybePrintTechSummary(env, step)
  when defined(econAudit):
    ea.maybePrintEconDashboard(env, step)
  when defined(aiAudit):
    aia.printAuditSummary(step)

proc resetAllAudits*() =
  ## Reset audit state for environment reset.
  ## Call when the simulation resets.
  when defined(econAudit):
    ea.resetEconAudit()
  when defined(techAudit):
    ta.resetTechAudit()
  # Note: combat_audit, action_audit, tumor_audit, ai_audit
  # don't have explicit reset procs (they reset on print or use ensure*Init)
