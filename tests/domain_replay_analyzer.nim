import std/[unittest]
import replay_analyzer
import common_types

suite "Replay Analyzer - Action Profile":
  test "actionProfile normalizes counts to frequencies":
    var strategy = TeamStrategy(teamId: 0, agentCount: 1)
    strategy.actionDist.counts[ActionAttack] = 50
    strategy.actionDist.counts[ActionUse] = 30
    strategy.actionDist.counts[ActionBuild] = 20
    strategy.actionDist.total = 100
    let profile = actionProfile(strategy)
    check abs(profile[ActionAttack] - 0.5) < 0.001
    check abs(profile[ActionUse] - 0.3) < 0.001
    check abs(profile[ActionBuild] - 0.2) < 0.001

  test "actionProfile with zero total returns all zeros":
    var strategy = TeamStrategy(teamId: 0, agentCount: 1)
    strategy.actionDist.total = 0
    let profile = actionProfile(strategy)
    for i in 0 ..< ActionVerbCount:
      check profile[i] == 0.0

  test "actionProfile sums to approximately 1.0":
    var strategy = TeamStrategy(teamId: 0, agentCount: 1)
    strategy.actionDist.counts[0] = 10
    strategy.actionDist.counts[1] = 20
    strategy.actionDist.counts[ActionAttack] = 30
    strategy.actionDist.counts[ActionUse] = 40
    strategy.actionDist.total = 100
    let profile = actionProfile(strategy)
    var sum: float32 = 0.0
    for i in 0 ..< ActionVerbCount:
      sum += profile[i]
    check abs(sum - 1.0) < 0.01

suite "Replay Analyzer - Combat Efficiency":
  test "combatEfficiency is hit rate":
    var strategy = TeamStrategy(teamId: 0)
    strategy.combat.attacks = 100
    strategy.combat.hits = 75
    check abs(combatEfficiency(strategy) - 0.75) < 0.001

  test "combatEfficiency returns 0 with no attacks":
    var strategy = TeamStrategy(teamId: 0)
    strategy.combat.attacks = 0
    check combatEfficiency(strategy) == 0.0

  test "combatEfficiency perfect accuracy":
    var strategy = TeamStrategy(teamId: 0)
    strategy.combat.attacks = 50
    strategy.combat.hits = 50
    check abs(combatEfficiency(strategy) - 1.0) < 0.001

suite "Replay Analyzer - Economy Score":
  test "economyScore ratio of gather to total":
    var strategy = TeamStrategy(teamId: 0)
    strategy.resources.gatherActions = 80
    strategy.resources.buildActions = 20
    check abs(economyScore(strategy) - 0.8) < 0.001

  test "economyScore returns 0 with no actions":
    var strategy = TeamStrategy(teamId: 0)
    strategy.resources.gatherActions = 0
    strategy.resources.buildActions = 0
    check economyScore(strategy) == 0.0

  test "economyScore all gather returns 1.0":
    var strategy = TeamStrategy(teamId: 0)
    strategy.resources.gatherActions = 100
    strategy.resources.buildActions = 0
    check abs(economyScore(strategy) - 1.0) < 0.001

  test "economyScore all build returns 0.0":
    var strategy = TeamStrategy(teamId: 0)
    strategy.resources.gatherActions = 0
    strategy.resources.buildActions = 100
    check economyScore(strategy) == 0.0

suite "Replay Analyzer - Strategy Score":
  test "strategyScore is clamped between 0 and 1":
    var strategy = TeamStrategy(teamId: 0, agentCount: 1)
    strategy.finalReward = 10.0  # Very high
    strategy.won = true
    strategy.combat.attacks = 100
    strategy.combat.hits = 100
    let score = strategyScore(strategy)
    check score >= 0.0
    check score <= 1.0

  test "strategyScore winner gets bonus":
    var winnerStrategy = TeamStrategy(teamId: 0, agentCount: 1)
    winnerStrategy.finalReward = 0.5
    winnerStrategy.won = true

    var loserStrategy = TeamStrategy(teamId: 1, agentCount: 1)
    loserStrategy.finalReward = 0.5
    loserStrategy.won = false

    check strategyScore(winnerStrategy) > strategyScore(loserStrategy)

  test "strategyScore zero reward no combat":
    var strategy = TeamStrategy(teamId: 0, agentCount: 1)
    strategy.finalReward = 0.0
    strategy.won = false
    check strategyScore(strategy) == 0.0

  test "strategyScore with combat efficiency adds bonus":
    var noCombat = TeamStrategy(teamId: 0, agentCount: 1)
    noCombat.finalReward = 0.5

    var withCombat = TeamStrategy(teamId: 0, agentCount: 1)
    withCombat.finalReward = 0.5
    withCombat.combat.attacks = 100
    withCombat.combat.hits = 80

    check strategyScore(withCombat) > strategyScore(noCombat)

suite "Replay Analyzer - Dominant Action Verb":
  test "dominantActionVerb returns most frequent":
    let seq_data = ActionSequence(
      verbs: @[ActionAttack, ActionAttack, ActionAttack, ActionUse, ActionBuild],
      teamReward: 1.0
    )
    check dominantActionVerb(seq_data) == ActionAttack

  test "dominantActionVerb single verb":
    let seq_data = ActionSequence(verbs: @[ActionBuild], teamReward: 0.5)
    check dominantActionVerb(seq_data) == ActionBuild

  test "dominantActionVerb empty returns 0":
    let seq_data = ActionSequence(verbs: @[], teamReward: 0.0)
    check dominantActionVerb(seq_data) == 0

suite "Replay Analyzer - Feedback":
  test "applyReplayFeedback updates role fitness":
    var catalog = initRoleCatalog()
    let opt = OptionDef(name: "TestBehavior")
    discard catalog.addBehavior(opt, BehaviorCustom)
    var role = newRoleDef(catalog, "TestRole", @[], "test")
    role.games = 5
    role.fitness = 0.3
    discard registerRole(catalog, role)

    var analysis = ReplayAnalysis()
    var teamStrategy = TeamStrategy(
      teamId: 0, agentCount: 2,
      finalReward: 1.0, won: true
    )
    teamStrategy.combat.attacks = 50
    teamStrategy.combat.hits = 30
    analysis.teams.add teamStrategy
    analysis.winningTeamId = 0

    let fitnessBefore = catalog.roles[0].fitness
    applyReplayFeedback(catalog, analysis)
    # Fitness should have changed toward the strategy score
    check catalog.roles[0].fitness != fitnessBefore

  test "applyReplayFeedback no-op with empty analysis":
    var catalog = initRoleCatalog()
    var role = newRoleDef(catalog, "TestRole", @[], "test")
    role.games = 5
    role.fitness = 0.5
    discard registerRole(catalog, role)

    let analysis = ReplayAnalysis()
    let fitnessBefore = catalog.roles[0].fitness
    applyReplayFeedback(catalog, analysis)
    check catalog.roles[0].fitness == fitnessBefore

  test "applyWinnerBoost only boosts high-fitness roles":
    var catalog = initRoleCatalog()
    var lowRole = newRoleDef(catalog, "LowRole", @[], "test")
    lowRole.games = 5
    lowRole.fitness = 0.2  # Below 0.5 threshold
    discard registerRole(catalog, lowRole)

    var highRole = newRoleDef(catalog, "HighRole", @[], "test")
    highRole.games = 5
    highRole.fitness = 0.6  # Above 0.5 threshold
    discard registerRole(catalog, highRole)

    var analysis = ReplayAnalysis(winningTeamId: 0)
    var teamStrategy = TeamStrategy(
      teamId: 0, agentCount: 1,
      finalReward: 1.0, won: true
    )
    teamStrategy.combat.attacks = 20
    teamStrategy.combat.hits = 15
    analysis.teams.add teamStrategy

    let lowBefore = catalog.roles[0].fitness
    let highBefore = catalog.roles[1].fitness
    applyWinnerBoost(catalog, analysis)
    # Low fitness role should not change (below threshold)
    check catalog.roles[0].fitness == lowBefore
    # High fitness role should get boosted
    check catalog.roles[1].fitness != highBefore
