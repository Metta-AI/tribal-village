## Tests for balance_scorecard.nim
##
## Verifies the balance scorecard instrument correctly collects
## and reports game balance metrics.

import std/[unittest, os, json, strutils]
import environment
import agent_control
import types
import balance_scorecard

const
  TestSeed = 42
  TestSteps = 100

suite "Balance Scorecard - Collection":

  test "scorecard collector initializes from environment":
    # Set env vars before init
    putEnv("TV_SCORECARD_ENABLED", "1")
    putEnv("TV_SCORECARD_INTERVAL", "10")
    putEnv("TV_SCORECARD_DIR", "/tmp/test_scorecards/")

    initCollector()

    check collector.enabled == true
    check collector.sampleInterval == 10
    check collector.outputDir == "/tmp/test_scorecards/"

    # Cleanup
    delEnv("TV_SCORECARD_ENABLED")
    delEnv("TV_SCORECARD_INTERVAL")
    delEnv("TV_SCORECARD_DIR")

  test "scorecard disabled by default":
    # Reset collector
    collector.initialized = false
    delEnv("TV_SCORECARD_ENABLED")

    initCollector()

    check collector.enabled == false

  test "startMatch initializes scorecard state":
    putEnv("TV_SCORECARD_ENABLED", "1")
    collector.initialized = false
    initCollector()

    var config = defaultEnvironmentConfig()
    config.maxSteps = TestSteps
    let env = newEnvironment(config, TestSeed)

    startMatch(env, TestSeed)

    check collector.currentScorecard.seed == TestSeed
    check collector.currentScorecard.matchId.len > 0
    for teamId in 0 ..< MapRoomObjectsTeams:
      check collector.currentScorecard.teams[teamId].teamId == teamId

    delEnv("TV_SCORECARD_ENABLED")

  test "maybeSample collects data at intervals":
    putEnv("TV_SCORECARD_ENABLED", "1")
    putEnv("TV_SCORECARD_INTERVAL", "10")
    collector.initialized = false
    initCollector()

    var config = defaultEnvironmentConfig()
    config.maxSteps = TestSteps
    let env = newEnvironment(config, TestSeed)

    initGlobalController(BuiltinAI, seed = TestSeed)

    startMatch(env, TestSeed)

    # Run a few steps
    for step in 0 ..< 25:
      var actions = getActions(env)
      env.step(addr actions)
      maybeSample(env)

    # Should have at least 2 samples (at steps ~10, ~20)
    check collector.currentScorecard.teams[0].resourceCurve.len >= 2

    delEnv("TV_SCORECARD_ENABLED")
    delEnv("TV_SCORECARD_INTERVAL")

suite "Balance Scorecard - Metrics":

  test "resource samples capture stockpile data":
    putEnv("TV_SCORECARD_ENABLED", "1")
    collector.initialized = false
    initCollector()

    var config = defaultEnvironmentConfig()
    let env = newEnvironment(config, TestSeed)

    startMatch(env, TestSeed)

    # Run a few steps to generate some resource activity
    initGlobalController(BuiltinAI, seed = TestSeed)
    for step in 0 ..< 50:
      var actions = getActions(env)
      env.step(addr actions)
      maybeSample(env)

    endMatch(env)

    # Check that final resources were captured
    for teamId in 0 ..< MapRoomObjectsTeams:
      let r = collector.currentScorecard.teams[teamId].finalResources
      # Resources should be non-negative
      check r.food >= 0
      check r.wood >= 0
      check r.gold >= 0
      check r.stone >= 0

    delEnv("TV_SCORECARD_ENABLED")

  test "unit composition tracks unit classes":
    putEnv("TV_SCORECARD_ENABLED", "1")
    collector.initialized = false
    initCollector()

    var config = defaultEnvironmentConfig()
    let env = newEnvironment(config, TestSeed)

    startMatch(env, TestSeed)

    initGlobalController(BuiltinAI, seed = TestSeed)
    for step in 0 ..< 20:
      var actions = getActions(env)
      env.step(addr actions)
      maybeSample(env)

    endMatch(env)

    # Each team should have some villagers at start
    var totalVillagers = 0
    for teamId in 0 ..< MapRoomObjectsTeams:
      totalVillagers += collector.currentScorecard.teams[teamId].finalUnits.villagers

    check totalVillagers > 0

    delEnv("TV_SCORECARD_ENABLED")

  test "tech progress tracks research":
    putEnv("TV_SCORECARD_ENABLED", "1")
    collector.initialized = false
    initCollector()

    var config = defaultEnvironmentConfig()
    let env = newEnvironment(config, TestSeed)

    startMatch(env, TestSeed)

    # Tech starts at 0
    let initialTech = collector.currentScorecard.teams[0].finalTech
    check initialTech.blacksmithLevels == 0
    check initialTech.universityTechs == 0
    check initialTech.castleTechs == 0

    delEnv("TV_SCORECARD_ENABLED")

suite "Balance Scorecard - Output":

  test "scorecardToJson produces valid JSON":
    putEnv("TV_SCORECARD_ENABLED", "1")
    collector.initialized = false
    initCollector()

    var config = defaultEnvironmentConfig()
    let env = newEnvironment(config, TestSeed)

    startMatch(env, TestSeed)
    endMatch(env)

    let jsonNode = scorecardToJson(collector.currentScorecard)

    # Verify structure
    check jsonNode.hasKey("match_id")
    check jsonNode.hasKey("seed")
    check jsonNode.hasKey("teams")
    check jsonNode.hasKey("balance_metrics")
    check jsonNode["teams"].len == MapRoomObjectsTeams

    delEnv("TV_SCORECARD_ENABLED")

  test "generateSummary produces readable output":
    putEnv("TV_SCORECARD_ENABLED", "1")
    collector.initialized = false
    initCollector()

    var config = defaultEnvironmentConfig()
    let env = newEnvironment(config, TestSeed)

    startMatch(env, TestSeed)
    endMatch(env)

    let summary = generateSummary(collector.currentScorecard)

    # Check for expected sections
    check summary.contains("GAME BALANCE SCORECARD")
    check summary.contains("BALANCE METRICS")
    check summary.contains("PER-TEAM SUMMARY")
    check summary.contains("FINAL RESOURCES")
    check summary.contains("FINAL UNIT COMPOSITION")
    check summary.contains("TECHNOLOGY PROGRESS")

    delEnv("TV_SCORECARD_ENABLED")

suite "Balance Scorecard - Balance Metrics":

  test "balance metrics are between 0 and 1":
    putEnv("TV_SCORECARD_ENABLED", "1")
    collector.initialized = false
    initCollector()

    var config = defaultEnvironmentConfig()
    config.maxSteps = 100
    let env = newEnvironment(config, TestSeed)

    initGlobalController(BuiltinAI, seed = TestSeed)

    startMatch(env, TestSeed)

    for step in 0 ..< 100:
      var actions = getActions(env)
      env.step(addr actions)
      maybeSample(env)

    endMatch(env)

    let sc = collector.currentScorecard
    check sc.resourceParity >= 0.0 and sc.resourceParity <= 1.0
    check sc.militaryBalance >= 0.0 and sc.militaryBalance <= 1.0
    check sc.techParity >= 0.0 and sc.techParity <= 1.0

    delEnv("TV_SCORECARD_ENABLED")

  test "idle villager percentage is reasonable":
    putEnv("TV_SCORECARD_ENABLED", "1")
    collector.initialized = false
    initCollector()

    var config = defaultEnvironmentConfig()
    config.maxSteps = 50
    let env = newEnvironment(config, TestSeed)

    initGlobalController(BuiltinAI, seed = TestSeed)

    startMatch(env, TestSeed)

    for step in 0 ..< 50:
      var actions = getActions(env)
      env.step(addr actions)
      maybeSample(env)

    endMatch(env)

    # Idle percentage should be between 0 and 100
    for teamId in 0 ..< MapRoomObjectsTeams:
      let idle = collector.currentScorecard.teams[teamId].idleVillagerPct
      check idle >= 0.0 and idle <= 100.0

    delEnv("TV_SCORECARD_ENABLED")
