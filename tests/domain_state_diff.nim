## Tests for state_diff.nim - Step-by-step game state diff logger.
## Must compile with -d:stateDiff to get the real implementation.
##
## Run: nim r -d:stateDiff --path:src tests/domain_state_diff.nim

import std/[unittest]
import environment
import types
import items
import state_diff
import test_utils

suite "State Diff - Snapshot Capture":
  test "captureSnapshot captures step and victory state":
    let env = makeEmptyEnv()
    env.currentStep = 42
    env.victoryWinner = -1

    let snap = captureSnapshot(env)
    check snap.step == 42
    check snap.victoryWinner == -1

  test "captureSnapshot captures agent counts by team":
    let env = makeEmptyEnv()
    # Add 3 alive agents on team 0
    discard addAgentAt(env, 0, ivec2(10, 10))
    discard addAgentAt(env, 1, ivec2(12, 10))
    discard addAgentAt(env, 2, ivec2(14, 10))
    # Add 1 alive agent on team 1
    discard addAgentAt(env, MapAgentsPerTeam, ivec2(30, 30))

    let snap = captureSnapshot(env)
    check snap.teams[0].aliveCount == 3
    check snap.teams[0].villagerCount == 3  # All are villagers
    check snap.teams[1].aliveCount == 1
    check snap.teams[1].villagerCount == 1

  test "captureSnapshot captures dead agents":
    let env = makeEmptyEnv()
    discard addAgentAt(env, 0, ivec2(10, 10))
    discard addAgentAt(env, 1, ivec2(12, 10))
    # Kill agent 1
    env.terminated[1] = 1.0

    let snap = captureSnapshot(env)
    check snap.teams[0].aliveCount == 1
    check snap.teams[0].deadCount == 1

  test "captureSnapshot captures unit class diversity":
    let env = makeEmptyEnv()
    discard addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitVillager)
    discard addAgentAt(env, 1, ivec2(12, 10), unitClass = UnitArcher)
    discard addAgentAt(env, 2, ivec2(14, 10), unitClass = UnitKnight)
    discard addAgentAt(env, 3, ivec2(16, 10), unitClass = UnitManAtArms)
    discard addAgentAt(env, 4, ivec2(18, 10), unitClass = UnitMonk)

    let snap = captureSnapshot(env)
    check snap.teams[0].villagerCount == 1
    check snap.teams[0].archerCount == 1
    check snap.teams[0].knightCount == 1
    check snap.teams[0].manAtArmsCount == 1
    check snap.teams[0].monkCount == 1

  test "captureSnapshot captures stockpile resources":
    let env = makeEmptyEnv()
    setStockpile(env, 0, ResourceFood, 100)
    setStockpile(env, 0, ResourceWood, 200)
    setStockpile(env, 0, ResourceGold, 50)
    setStockpile(env, 0, ResourceStone, 30)
    setStockpile(env, 0, ResourceWater, 10)

    let snap = captureSnapshot(env)
    check snap.teams[0].food == 100
    check snap.teams[0].wood == 200
    check snap.teams[0].gold == 50
    check snap.teams[0].stone == 30
    check snap.teams[0].water == 10

  test "captureSnapshot captures building counts":
    let env = makeEmptyEnv()
    discard addBuilding(env, House, ivec2(5, 5), 0)
    discard addBuilding(env, House, ivec2(7, 5), 0)
    discard addBuilding(env, House, ivec2(9, 5), 0)
    discard addBuilding(env, GuardTower, ivec2(11, 5), 0)
    discard addBuilding(env, Wall, ivec2(13, 5), 0)
    discard addBuilding(env, Market, ivec2(15, 5), 0)
    discard addBuilding(env, Castle, ivec2(17, 5), 0)

    let snap = captureSnapshot(env)
    check snap.houseCount == 3
    check snap.towerCount == 1
    check snap.wallCount == 1
    check snap.marketCount == 1
    check snap.castleCount == 1

  test "captureSnapshot counts projectiles":
    let env = makeEmptyEnv()
    env.projectiles.add(Projectile(countdown: 5, lifetime: 10))
    env.projectiles.add(Projectile(countdown: 3, lifetime: 10))

    let snap = captureSnapshot(env)
    check snap.projectileCount == 2

  test "captureSnapshot empty environment":
    let env = makeEmptyEnv()

    let snap = captureSnapshot(env)
    check snap.step == 0
    check snap.victoryWinner == -1
    check snap.thingCount == 0
    check snap.projectileCount == 0
    check snap.houseCount == 0
    for teamId in 0 ..< MapRoomObjectsTeams:
      check snap.teams[teamId].aliveCount == 0
      check snap.teams[teamId].food == 0

suite "State Diff - Compare and Log":
  test "compareAndLog detects resource changes":
    let env = makeEmptyEnv()
    setStockpile(env, 0, ResourceFood, 100)
    let snap1 = captureSnapshot(env)

    setStockpile(env, 0, ResourceFood, 150)
    let snap2 = captureSnapshot(env)

    # Should not crash; output goes to stdout
    compareAndLog(snap1, snap2)
    check snap1.teams[0].food == 100
    check snap2.teams[0].food == 150

  test "compareAndLog detects building count changes":
    let env = makeEmptyEnv()
    let snap1 = captureSnapshot(env)

    discard addBuilding(env, House, ivec2(5, 5), 0)
    let snap2 = captureSnapshot(env)

    compareAndLog(snap1, snap2)
    check snap1.houseCount == 0
    check snap2.houseCount == 1

  test "compareAndLog no-op on identical snapshots":
    let env = makeEmptyEnv()
    setStockpile(env, 0, ResourceFood, 100)
    discard addBuilding(env, House, ivec2(5, 5), 0)

    let snap1 = captureSnapshot(env)
    let snap2 = captureSnapshot(env)

    # Should produce no output (identical snapshots)
    compareAndLog(snap1, snap2)
    check snap1.houseCount == snap2.houseCount
    check snap1.teams[0].food == snap2.teams[0].food

  test "compareAndLog detects victory winner change":
    let env = makeEmptyEnv()
    env.victoryWinner = -1
    let snap1 = captureSnapshot(env)

    env.victoryWinner = 0
    let snap2 = captureSnapshot(env)

    compareAndLog(snap1, snap2)
    check snap1.victoryWinner == -1
    check snap2.victoryWinner == 0

  test "compareAndLog detects alive/dead count changes":
    let env = makeEmptyEnv()
    discard addAgentAt(env, 0, ivec2(10, 10))
    discard addAgentAt(env, 1, ivec2(12, 10))
    let snap1 = captureSnapshot(env)

    env.terminated[1] = 1.0
    let snap2 = captureSnapshot(env)

    compareAndLog(snap1, snap2)
    check snap1.teams[0].aliveCount == 2
    check snap2.teams[0].aliveCount == 1
    check snap2.teams[0].deadCount == 1

suite "State Diff - Pre/Post Step":
  test "capturePreStep and comparePostStep integration":
    let env = makeEmptyEnv()
    setStockpile(env, 0, ResourceFood, 100)

    capturePreStep(env)
    check diffState.hasSnapshot

    # Modify state
    setStockpile(env, 0, ResourceFood, 200)
    env.currentStep = 1

    # Should log diff
    comparePostStep(env)
    # After compare, prev snapshot updated to new state
    check diffState.prevSnapshot.teams[0].food == 200

  test "comparePostStep no-op without capturePreStep":
    initStateDiff()
    let env = makeEmptyEnv()

    # Should not crash even without prior snapshot
    comparePostStep(env)
    check not diffState.hasSnapshot

  test "initStateDiff resets state":
    let env = makeEmptyEnv()
    capturePreStep(env)
    check diffState.hasSnapshot

    initStateDiff()
    check not diffState.hasSnapshot

  test "ensureStateDiffInit is idempotent":
    initStateDiff()
    diffState.hasSnapshot = true
    ensureStateDiffInit()
    # Should not reset since already initialized
    check diffState.hasSnapshot

suite "State Diff - Multi-Team Tracking":
  test "snapshot tracks multiple teams independently":
    let env = makeEmptyEnv()
    setStockpile(env, 0, ResourceFood, 100)
    setStockpile(env, 0, ResourceWood, 200)
    if MapRoomObjectsTeams > 1:
      setStockpile(env, 1, ResourceFood, 50)
      setStockpile(env, 1, ResourceGold, 300)

    let snap = captureSnapshot(env)
    check snap.teams[0].food == 100
    check snap.teams[0].wood == 200
    if MapRoomObjectsTeams > 1:
      check snap.teams[1].food == 50
      check snap.teams[1].gold == 300

  test "compareAndLog shows per-team diffs":
    let env = makeEmptyEnv()
    setStockpile(env, 0, ResourceFood, 100)
    if MapRoomObjectsTeams > 1:
      setStockpile(env, 1, ResourceFood, 100)
    let snap1 = captureSnapshot(env)

    # Change only team 0
    setStockpile(env, 0, ResourceFood, 200)
    let snap2 = captureSnapshot(env)

    compareAndLog(snap1, snap2)
    check snap2.teams[0].food == 200
    if MapRoomObjectsTeams > 1:
      check snap2.teams[1].food == 100  # Unchanged
