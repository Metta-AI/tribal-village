import std/unittest
import environment
import agent_control
import types
import test_utils

proc initTestGlobalController*(seed: int) =
  ## Initialize global controller for testing with Brutal difficulty (no decision delays).
  initGlobalController(BuiltinAI, seed)
  # Set Brutal difficulty for all teams to ensure deterministic test behavior
  for teamId in 0 ..< MapRoomObjectsTeams:
    globalController.aiController.setDifficulty(teamId, DiffBrutal)

suite "AttackMove":
  test "attack-move moves toward destination":
    let env = makeEmptyEnv()
    # Create agent at position (10, 10) with military unit class
    let agent = addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitManAtArms, stance = StanceDefensive)

    # Initialize global controller with built-in AI and Brutal difficulty for testing
    initTestGlobalController(42)
    let controller = globalController.aiController
    controller.setAttackMoveTarget(0, ivec2(20, 10))

    # Verify attack-move is active
    let target = controller.getAttackMoveTarget(0)
    check target.x == 20
    check target.y == 10

    # Get action - should move toward destination (right)
    let action = controller.decideAction(env, 0)
    let (verb, arg) = decodeAction(action)
    check verb == 1  # Move action
    check arg == 3   # East direction (toward x=20)

  test "attack-move attacks enemy encountered":
    let env = makeEmptyEnv()
    # Create attack-moving agent
    let agent = addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitManAtArms, stance = StanceDefensive)

    # Create enemy agent adjacent to attack-moving agent
    # Use agentId from a different team range (team 1 = agentIds 168+)
    let enemyAgentId = 168  # Team 1
    let enemy = addAgentAt(env, enemyAgentId, ivec2(11, 10), unitClass = UnitGoblin, stance = StanceAggressive)

    initTestGlobalController(42)
    let controller = globalController.aiController
    controller.setAttackMoveTarget(0, ivec2(20, 10))

    let action = controller.decideAction(env, 0)
    let (verb, arg) = decodeAction(action)
    check verb == 2  # Attack action
    check arg == 3   # East direction (toward enemy)

  test "attack-move can be cleared":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitManAtArms, stance = StanceDefensive)

    initTestGlobalController(42)
    let controller = globalController.aiController
    controller.setAttackMoveTarget(0, ivec2(20, 10))

    # Verify active
    let target1 = controller.getAttackMoveTarget(0)
    check target1.x >= 0

    controller.clearAttackMoveTarget(0)

    # Verify cleared
    let target2 = controller.getAttackMoveTarget(0)
    check target2.x == -1

  test "attack-move terminates at destination":
    let env = makeEmptyEnv()
    # Create agent very close to destination (within 1 tile)
    let agent = addAgentAt(env, 0, ivec2(19, 10), unitClass = UnitManAtArms, stance = StanceDefensive)

    initTestGlobalController(42)
    let controller = globalController.aiController
    controller.setAttackMoveTarget(0, ivec2(20, 10))

    # Get action - should clear target since we're at destination
    let action = controller.decideAction(env, 0)
    # After reaching destination, attack-move target should be cleared
    let target = controller.getAttackMoveTarget(0)
    check target.x == -1  # Target cleared

  test "attack-move does not activate without target":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitManAtArms, stance = StanceDefensive)

    initTestGlobalController(42)
    let controller = globalController.aiController
    # Trigger agent initialization by calling decideAction
    discard controller.decideAction(env, 0)
    # Attack-move not set, should not be active after initialization
    let target = controller.getAttackMoveTarget(0)
    check target.x == -1

  test "attack-move resumes after combat":
    let env = makeEmptyEnv()
    # Create attack-moving agent
    let agent = addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitManAtArms, stance = StanceDefensive)

    initTestGlobalController(42)
    let controller = globalController.aiController
    controller.setAttackMoveTarget(0, ivec2(20, 10))

    # First, no enemies - should move toward destination
    let action1 = controller.decideAction(env, 0)
    let (verb1, _) = decodeAction(action1)
    check verb1 == 1  # Move action

    # Attack-move target should still be set (path continues after combat)
    let target = controller.getAttackMoveTarget(0)
    check target.x == 20
