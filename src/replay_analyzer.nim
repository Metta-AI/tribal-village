# This file is included by src/ai_defaults.nim
## Replay analysis system for AI learning.
##
## Loads compressed replay files produced by replay_writer.nim,
## extracts per-team strategy summaries, and feeds results back
## into the evolutionary role/behavior fitness system.

import std/[json, os, algorithm, times]
import zippy
import replay_common

const
  ReplayAnalysisVersion* = 1
  MaxReplaysPerPass* = 8
  WinRewardThreshold* = 0.5
  ReplayFeedbackAlpha* = 0.1

type
  ActionDistribution* = object
    ## Per-action-verb frequency counts for a team.
    counts*: array[ActionVerbCount, int]
    total*: int

  CombatStats* = object
    ## Attack attempts vs successes for a team.
    attacks*: int
    hits*: int
    kills*: int  # inferred from agents going inactive

  ResourceStats* = object
    ## Aggregate resource gathering activity.
    gatherActions*: int   # use actions
    buildActions*: int    # build actions
    totalInventoryGain*: int

  TeamStrategy* = object
    ## Summary of a single team's behavior across one replay.
    teamId*: int
    agentCount*: int
    actionDist*: ActionDistribution
    combat*: CombatStats
    resources*: ResourceStats
    finalReward*: float32
    won*: bool

  ReplayAnalysis* = object
    ## Analysis results for one replay file.
    filePath*: string
    maxSteps*: int
    numAgents*: int
    teams*: seq[TeamStrategy]
    winningTeamId*: int  # -1 if no clear winner

  ActionSequence* = object
    ## Extracted action pattern from a high-performing agent.
    verbs*: seq[int]
    teamReward*: float32

# ---------------------------------------------------------------------------
# Replay loading
# ---------------------------------------------------------------------------

proc loadReplayJson*(path: string): JsonNode =
  ## Load a compressed .json.z replay file and return parsed JSON.
  let compressed = readFile(path)
  let decompressed = zippy.uncompress(compressed, dataFormat = dfZlib)
  parseJson(decompressed)

# ---------------------------------------------------------------------------
# Strategy extraction
# ---------------------------------------------------------------------------

proc analyzeReplay*(replayJson: JsonNode): ReplayAnalysis =
  ## Extract per-team strategy summaries from parsed replay JSON.
  result.maxSteps = replayJson{"max_steps"}.getInt()
  result.numAgents = replayJson{"num_agents"}.getInt()
  result.winningTeamId = -1

  var teamStrategies: array[MapRoomObjectsTeams, TeamStrategy]
  for i in 0 ..< MapRoomObjectsTeams:
    teamStrategies[i].teamId = i

  let objects = replayJson{"objects"}
  if objects.isNil or objects.kind != JArray:
    return

  for obj in objects.items:
    if obj.kind != JObject:
      continue
    # Only analyze agents (they have agent_id)
    let agentIdNode = obj{"agent_id"}
    if agentIdNode.isNil:
      continue
    let groupIdNode = obj{"group_id"}
    if groupIdNode.isNil:
      continue
    let teamId = groupIdNode.getInt()
    if teamId < 0 or teamId >= MapRoomObjectsTeams:
      continue

    inc teamStrategies[teamId].agentCount

    # Parse action and success changes once, accumulate all stats in a single pass
    let actionIdSeries = obj{"action_id"}
    let actionSuccessSeries = obj{"action_success"}

    if not actionIdSeries.isNil:
      let actionChanges = parseChanges(actionIdSeries)
      let successChanges = if not actionSuccessSeries.isNil:
                             parseChanges(actionSuccessSeries)
                           else: @[]
      var successIdx = 0

      for ac in actionChanges:
        let verb = ac.value.getInt()
        if verb < 0 or verb >= ActionVerbCount:
          continue

        # Action distribution
        inc teamStrategies[teamId].actionDist.counts[verb]
        inc teamStrategies[teamId].actionDist.total

        # Combat stats
        if verb == ActionAttack:
          inc teamStrategies[teamId].combat.attacks
          while successIdx < successChanges.len and
                successChanges[successIdx].step < ac.step:
            inc successIdx
          if successIdx < successChanges.len and
             successChanges[successIdx].step == ac.step and
             successChanges[successIdx].value.getBool():
            inc teamStrategies[teamId].combat.hits

        # Resource stats
        elif verb == ActionUse:
          inc teamStrategies[teamId].resources.gatherActions
        elif verb == ActionBuild:
          inc teamStrategies[teamId].resources.buildActions

    # Final reward
    let totalRewardSeries = obj{"total_reward"}
    if not totalRewardSeries.isNil:
      let lastReward = lastChangeValue(totalRewardSeries)
      if lastReward.kind == JFloat or lastReward.kind == JInt:
        teamStrategies[teamId].finalReward += lastReward.getFloat().float32

  # Determine winner (team with highest aggregate reward)
  var bestReward = float32.low
  var bestTeam = -1
  for i in 0 ..< MapRoomObjectsTeams:
    if teamStrategies[i].agentCount > 0:
      let avgReward = teamStrategies[i].finalReward /
                      float32(teamStrategies[i].agentCount)
      teamStrategies[i].won = avgReward >= WinRewardThreshold
      if avgReward > bestReward:
        bestReward = avgReward
        bestTeam = i

  result.winningTeamId = bestTeam
  for i in 0 ..< MapRoomObjectsTeams:
    if teamStrategies[i].agentCount > 0:
      result.teams.add teamStrategies[i]

proc analyzeReplayFile*(path: string): ReplayAnalysis =
  ## Load and analyze a single replay file.
  let replayJson = loadReplayJson(path)
  result = analyzeReplay(replayJson)
  result.filePath = path

# ---------------------------------------------------------------------------
# Strategy scoring - map strategies to behavior fitness signals
# ---------------------------------------------------------------------------

proc actionProfile*(strategy: TeamStrategy): array[ActionVerbCount, float32] =
  ## Normalize action counts to a frequency distribution.
  if strategy.actionDist.total <= 0:
    return
  for i in 0 ..< ActionVerbCount:
    result[i] = float32(strategy.actionDist.counts[i]) /
                float32(strategy.actionDist.total)

proc combatEfficiency*(strategy: TeamStrategy): float32 =
  ## Hit rate for attacks (0.0 - 1.0).
  if strategy.combat.attacks <= 0:
    return 0.0
  float32(strategy.combat.hits) / float32(strategy.combat.attacks)

proc economyScore*(strategy: TeamStrategy): float32 =
  ## Ratio of gather to build actions, clamped. Higher = more economy focused.
  let total = strategy.resources.gatherActions + strategy.resources.buildActions
  if total <= 0:
    return 0.0
  float32(strategy.resources.gatherActions) / float32(total)

proc strategyScore*(strategy: TeamStrategy): float32 =
  ## Composite strategy quality score (0.0 - 1.0) based on outcome and activity.
  let rewardComponent = clamp(strategy.finalReward /
                              max(1.0, float32(strategy.agentCount)), 0.0, 1.0)
  let combatComponent = combatEfficiency(strategy) * 0.2
  let winBonus = if strategy.won: 0.15'f32 else: 0.0'f32
  clamp(rewardComponent * 0.65 + combatComponent + winBonus, 0.0, 1.0)

# ---------------------------------------------------------------------------
# Fitness feedback - update role catalog from replay analysis
# ---------------------------------------------------------------------------

proc applyReplayFeedback*(catalog: var RoleCatalog, analysis: ReplayAnalysis) =
  ## Update role and behavior fitness scores based on replay analysis.
  ## Uses a lower alpha than live scoring to blend gradually.
  if analysis.teams.len == 0:
    return

  # Compute per-strategy scores
  var scores: seq[float32] = @[]
  for team in analysis.teams:
    scores.add strategyScore(team)

  # Average score across all teams as a baseline
  var avgScore: float32 = 0.0
  for s in scores:
    avgScore += s
  avgScore /= float32(scores.len)

  # Boost roles that appear in winning strategies, penalize losers
  for role in catalog.roles.mitems:
    if role.games <= 0:
      continue
    let blended = role.fitness * (1.0 - ReplayFeedbackAlpha) +
                  avgScore * ReplayFeedbackAlpha
    role.fitness = clamp(blended, 0.0, 1.0)

  # Update behavior fitness similarly
  for behavior in catalog.behaviors.mitems:
    if behavior.games <= 0:
      continue
    let blended = behavior.fitness * (1.0 - ReplayFeedbackAlpha) +
                  avgScore * ReplayFeedbackAlpha
    behavior.fitness = clamp(blended, 0.0, 1.0)

proc applyWinnerBoost*(catalog: var RoleCatalog, analysis: ReplayAnalysis,
                       boostAlpha: float32 = 0.15) =
  ## Give an extra fitness boost to roles matching winning team patterns.
  if analysis.winningTeamId < 0:
    return
  var winnerScore: float32 = 0.0
  for team in analysis.teams:
    if team.teamId == analysis.winningTeamId:
      winnerScore = strategyScore(team)
      break
  if winnerScore <= 0.0:
    return
  for role in catalog.roles.mitems:
    if role.fitness >= 0.5 and role.games > 0:
      let boost = role.fitness * (1.0 - boostAlpha) +
                  winnerScore * boostAlpha
      role.fitness = clamp(boost, 0.0, 1.0)

# ---------------------------------------------------------------------------
# Human pattern extraction
# ---------------------------------------------------------------------------

proc extractTopActionSequences*(replayJson: JsonNode,
                                teamId: int,
                                maxSequences: int = 5,
                                windowSize: int = 20): seq[ActionSequence] =
  ## Extract action verb sequences from the best-performing agents on a team.
  ## Returns up to maxSequences action windows from high-reward agents.
  let objects = replayJson{"objects"}
  if objects.isNil or objects.kind != JArray:
    return @[]

  type AgentInfo = tuple[reward: float32, actions: seq[int]]
  var agents: seq[AgentInfo] = @[]

  for obj in objects.items:
    if obj.kind != JObject:
      continue
    let gid = obj{"group_id"}
    if gid.isNil or gid.getInt() != teamId:
      continue
    let aid = obj{"agent_id"}
    if aid.isNil:
      continue

    var reward: float32 = 0.0
    let totalRewardSeries = obj{"total_reward"}
    if not totalRewardSeries.isNil:
      let lv = lastChangeValue(totalRewardSeries)
      if lv.kind == JFloat or lv.kind == JInt:
        reward = lv.getFloat().float32

    var actions: seq[int] = @[]
    let actionIdSeries = obj{"action_id"}
    if not actionIdSeries.isNil:
      let changes = parseChanges(actionIdSeries)
      for c in changes:
        actions.add c.value.getInt()

    if actions.len > 0:
      agents.add((reward: reward, actions: actions))

  # Sort by reward descending
  agents.sort(proc(a, b: AgentInfo): int =
    if a.reward > b.reward: -1
    elif a.reward < b.reward: 1
    else: 0
  )

  # Extract windows from top agents
  let topCount = min(agents.len, maxSequences)
  for i in 0 ..< topCount:
    let a = agents[i]
    let startIdx = max(0, a.actions.len - windowSize)
    var verbs: seq[int] = @[]
    for j in startIdx ..< a.actions.len:
      verbs.add a.actions[j]
    if verbs.len > 0:
      result.add ActionSequence(verbs: verbs, teamReward: a.reward)

proc dominantActionVerb*(seq_data: ActionSequence): int =
  ## Return the most frequent action verb in a sequence.
  var counts: array[ActionVerbCount, int]
  for v in seq_data.verbs:
    if v >= 0 and v < ActionVerbCount:
      inc counts[v]
  var bestCount = 0
  result = 0
  for i in 0 ..< ActionVerbCount:
    if counts[i] > bestCount:
      bestCount = counts[i]
      result = i

# ---------------------------------------------------------------------------
# Batch analysis - scan a directory of replays
# ---------------------------------------------------------------------------

proc findReplayFiles*(dir: string): seq[string] =
  ## Find all .json.z replay files in a directory.
  if not dirExists(dir):
    return @[]
  for entry in walkDir(dir):
    if entry.kind == pcFile and entry.path.endsWith(".json.z"):
      result.add entry.path
  result.sort(proc(a, b: string): int =
    let ta = getLastModificationTime(a)
    let tb = getLastModificationTime(b)
    cmp(tb, ta)
  )

proc analyzeReplayBatch*(dir: string, maxFiles: int = MaxReplaysPerPass): seq[ReplayAnalysis] =
  ## Analyze up to maxFiles replay files from a directory.
  let files = findReplayFiles(dir)
  let count = min(files.len, maxFiles)
  for i in 0 ..< count:
    try:
      result.add analyzeReplayFile(files[i])
    except CatchableError:
      discard

proc applyBatchFeedback*(catalog: var RoleCatalog, analyses: seq[ReplayAnalysis]) =
  ## Apply fitness feedback from multiple replay analyses.
  for analysis in analyses:
    applyReplayFeedback(catalog, analysis)
    applyWinnerBoost(catalog, analysis)
