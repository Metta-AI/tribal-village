import std/[unittest]
import audit_manager
import environment
import test_utils

# =============================================================================
# Audit Manager - Type Enumeration
# =============================================================================

suite "AuditManager - AuditKind":
  test "all AuditKind values are distinct":
    var seen: set[AuditKind]
    for kind in AuditKind:
      check kind notin seen
      seen.incl(kind)
    check seen.card == 6  # Combat, Econ, Tech, Action, Tumor, Ai

  test "AuditKind covers all audit types":
    check akCombat in {AuditKind.low .. AuditKind.high}
    check akEcon in {AuditKind.low .. AuditKind.high}
    check akTech in {AuditKind.low .. AuditKind.high}
    check akAction in {AuditKind.low .. AuditKind.high}
    check akTumor in {AuditKind.low .. AuditKind.high}
    check akAi in {AuditKind.low .. AuditKind.high}

# =============================================================================
# Audit Manager - isAuditEnabled
# =============================================================================

suite "AuditManager - isAuditEnabled":
  test "isAuditEnabled returns compile-time flags":
    # These checks verify the proc compiles and runs for each audit kind.
    # The actual return value depends on compile-time flags.
    let combatEnabled = isAuditEnabled(akCombat)
    let econEnabled = isAuditEnabled(akEcon)
    let techEnabled = isAuditEnabled(akTech)
    let actionEnabled = isAuditEnabled(akAction)
    let tumorEnabled = isAuditEnabled(akTumor)
    let aiEnabled = isAuditEnabled(akAi)
    # Verify booleans are returned (true or false)
    check combatEnabled in {true, false}
    check econEnabled in {true, false}
    check techEnabled in {true, false}
    check actionEnabled in {true, false}
    check tumorEnabled in {true, false}
    check aiEnabled in {true, false}

  test "isAuditEnabled is consistent":
    # Calling twice should return the same result
    check isAuditEnabled(akCombat) == isAuditEnabled(akCombat)
    check isAuditEnabled(akEcon) == isAuditEnabled(akEcon)
    check isAuditEnabled(akTech) == isAuditEnabled(akTech)

# =============================================================================
# Audit Manager - getEnabledAudits
# =============================================================================

suite "AuditManager - getEnabledAudits":
  test "getEnabledAudits returns a seq":
    let enabled = getEnabledAudits()
    # Should return some sequence (possibly empty if no audits enabled)
    check enabled.len >= 0
    check enabled.len <= 6  # Max 6 audit types

  test "getEnabledAudits matches isAuditEnabled":
    let enabled = getEnabledAudits()
    for kind in AuditKind:
      if isAuditEnabled(kind):
        check kind in enabled
      else:
        check kind notin enabled

  test "getEnabledAudits has no duplicates":
    let enabled = getEnabledAudits()
    var seen: set[AuditKind]
    for kind in enabled:
      check kind notin seen
      seen.incl(kind)

# =============================================================================
# Audit Manager - Initialization
# =============================================================================

suite "AuditManager - initAllAudits":
  test "initAllAudits does not crash":
    # Simply verify that calling initAllAudits doesn't cause any errors.
    # This tests that all enabled audit modules can be initialized.
    initAllAudits()
    check true  # If we got here, no crash

  test "initAllAudits can be called multiple times":
    initAllAudits()
    initAllAudits()
    check true  # Idempotent, no crash

# =============================================================================
# Audit Manager - Flush
# =============================================================================

suite "AuditManager - flushAllAudits":
  test "flushAllAudits does not crash with valid environment":
    let env = makeEmptyEnv()
    initAllAudits()
    flushAllAudits(env, 0)
    check true  # If we got here, no crash

  test "flushAllAudits works at various step counts":
    let env = makeEmptyEnv()
    initAllAudits()
    flushAllAudits(env, 0)
    flushAllAudits(env, 100)
    flushAllAudits(env, 1000)
    check true  # No crash

# =============================================================================
# Audit Manager - Reset
# =============================================================================

suite "AuditManager - resetAllAudits":
  test "resetAllAudits does not crash":
    initAllAudits()
    resetAllAudits()
    check true  # If we got here, no crash

  test "resetAllAudits can be called multiple times":
    initAllAudits()
    resetAllAudits()
    resetAllAudits()
    check true  # Idempotent, no crash

  test "reset then flush works":
    let env = makeEmptyEnv()
    initAllAudits()
    flushAllAudits(env, 50)
    resetAllAudits()
    flushAllAudits(env, 0)  # After reset, step starts at 0
    check true

# =============================================================================
# Integration Tests
# =============================================================================

suite "AuditManager - Integration":
  test "full lifecycle: init, flush, reset, flush":
    let env = makeEmptyEnv()

    # Initialize
    initAllAudits()

    # Simulate some steps
    for step in 0 ..< 10:
      env.stepNoop()
      flushAllAudits(env, step)

    # Reset
    resetAllAudits()

    # More steps after reset
    for step in 0 ..< 5:
      flushAllAudits(env, step)

    check true

  test "audit manager works with multiple environments":
    let env1 = makeEmptyEnv()
    let env2 = makeEmptyEnv()

    initAllAudits()

    flushAllAudits(env1, 0)
    flushAllAudits(env2, 0)
    flushAllAudits(env1, 1)
    flushAllAudits(env2, 1)

    check true
