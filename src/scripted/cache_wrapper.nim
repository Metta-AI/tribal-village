## Hierarchical state caching with explicit lifecycle management.
##
## Provides CacheWrapper pattern with alloc/reset/cleanup lifecycle phases.
## Supports per-agent state tracking for multiplayer scenarios.
## Avoids global mutable state by encapsulating cache state in explicit objects.
##
## Pattern adapted from mettascope's _CacheWrapper with these lifecycle phases:
## - alloc(): Initialize cache resources at creation time
## - reset(): Clear cached values at step/episode boundaries
## - cleanup(): Release resources when cache is no longer needed

import ../types
import vmath

export IVec2

const
  CacheInvalid* = -1'i32  ## Sentinel value for invalid cache entries

type
  CacheLifecyclePhase* = enum
    ## Tracks the current lifecycle phase of a cache wrapper.
    phaseUnallocated  ## Not yet initialized
    phaseAllocated    ## Resources allocated, ready to use
    phaseActive       ## In use during a step
    phaseCleaned      ## Cleaned up, resources released

  CacheWrapper*[T] = object
    ## Generic hierarchical cache with explicit lifecycle management.
    ## Uses generation counters for O(1) staleness detection.
    phase*: CacheLifecyclePhase
    generation*: int32      ## Current generation (incremented each reset)
    validGen*: int32        ## Generation when value was last set
    value*: T               ## Cached value

  PerAgentCacheWrapper*[T] = object
    ## Per-agent cache with explicit lifecycle for multiplayer support.
    ## Tracks validity per-agent using generation counters.
    phase*: CacheLifecyclePhase
    stepGeneration*: int32                   ## Current step generation
    agentGen*: array[MapAgents, int32]       ## Generation when each agent's value was set
    values*: array[MapAgents, T]             ## Cached value per agent

  PerTeamCacheWrapper*[T] = object
    ## Per-team cache with explicit lifecycle.
    ## Useful for team-wide cached computations (threat maps, etc.).
    phase*: CacheLifecyclePhase
    stepGeneration*: int32                          ## Current step generation
    teamGen*: array[MapRoomObjectsTeams, int32]    ## Generation when each team's value was set
    values*: array[MapRoomObjectsTeams, T]         ## Cached value per team

  AgentStateLifecycle* = object
    ## Tracks lifecycle state for per-agent state management.
    ## Enables proper cleanup when agents die/despawn.
    activeAgents*: array[MapAgents, bool]    ## Which agents have active state
    lastActiveStep*: array[MapAgents, int32] ## Step when agent was last active
    needsCleanup*: array[MapAgents, bool]    ## Agents needing state cleanup

# =============================================================================
# CacheWrapper[T] - Simple scalar cache with lifecycle
# =============================================================================

proc alloc*[T](cache: var CacheWrapper[T]) =
  ## Initialize cache resources. Call once at creation time.
  cache.phase = phaseAllocated
  cache.generation = 0
  cache.validGen = CacheInvalid

proc reset*[T](cache: var CacheWrapper[T]) =
  ## Reset cache for a new step/episode. Invalidates cached value.
  assert cache.phase in {phaseAllocated, phaseActive}, "Cannot reset unallocated cache"
  inc cache.generation
  cache.phase = phaseActive

proc cleanup*[T](cache: var CacheWrapper[T]) =
  ## Release cache resources. Call when cache is no longer needed.
  cache.phase = phaseCleaned
  cache.validGen = CacheInvalid

proc isValid*[T](cache: CacheWrapper[T]): bool {.inline.} =
  ## Check if cached value is valid for current generation.
  cache.validGen == cache.generation

proc get*[T](cache: var CacheWrapper[T], compute: proc(): T): T =
  ## Get cached value or compute and cache if not valid.
  if cache.validGen != cache.generation:
    cache.value = compute()
    cache.validGen = cache.generation
  cache.value

proc set*[T](cache: var CacheWrapper[T], value: T) =
  ## Set cached value and mark as valid for current generation.
  cache.value = value
  cache.validGen = cache.generation

proc invalidate*[T](cache: var CacheWrapper[T]) {.inline.} =
  ## Explicitly invalidate the cached value.
  cache.validGen = CacheInvalid

# =============================================================================
# PerAgentCacheWrapper[T] - Per-agent cache with lifecycle
# =============================================================================

proc alloc*[T](cache: var PerAgentCacheWrapper[T]) =
  ## Initialize per-agent cache resources.
  cache.phase = phaseAllocated
  cache.stepGeneration = 0
  for i in 0 ..< MapAgents:
    cache.agentGen[i] = CacheInvalid

proc reset*[T](cache: var PerAgentCacheWrapper[T]) =
  ## Reset cache for a new step. All agents' cached values become invalid.
  ## Uses O(1) generation bump instead of O(n) array clearing.
  assert cache.phase in {phaseAllocated, phaseActive}, "Cannot reset unallocated cache"
  inc cache.stepGeneration
  cache.phase = phaseActive

proc cleanup*[T](cache: var PerAgentCacheWrapper[T]) =
  ## Release cache resources.
  cache.phase = phaseCleaned
  for i in 0 ..< MapAgents:
    cache.agentGen[i] = CacheInvalid

proc isValid*[T](cache: PerAgentCacheWrapper[T], agentId: int): bool {.inline.} =
  ## Check if cached value is valid for this agent in current generation.
  if agentId < 0 or agentId >= MapAgents:
    return false
  cache.agentGen[agentId] == cache.stepGeneration

proc get*[T](cache: var PerAgentCacheWrapper[T], agentId: int,
             compute: proc(agentId: int): T): T =
  ## Get cached value for agent or compute and cache if not valid.
  if agentId < 0 or agentId >= MapAgents:
    return compute(agentId)
  if cache.agentGen[agentId] != cache.stepGeneration:
    cache.values[agentId] = compute(agentId)
    cache.agentGen[agentId] = cache.stepGeneration
  cache.values[agentId]

proc set*[T](cache: var PerAgentCacheWrapper[T], agentId: int, value: T) =
  ## Set cached value for agent and mark as valid.
  if agentId >= 0 and agentId < MapAgents:
    cache.values[agentId] = value
    cache.agentGen[agentId] = cache.stepGeneration

proc invalidate*[T](cache: var PerAgentCacheWrapper[T], agentId: int) {.inline.} =
  ## Invalidate cached value for a specific agent.
  if agentId >= 0 and agentId < MapAgents:
    cache.agentGen[agentId] = CacheInvalid

proc invalidateAll*[T](cache: var PerAgentCacheWrapper[T]) {.inline.} =
  ## Invalidate all cached values (O(n) operation - prefer reset() when possible).
  for i in 0 ..< MapAgents:
    cache.agentGen[i] = CacheInvalid

# =============================================================================
# PerTeamCacheWrapper[T] - Per-team cache with lifecycle
# =============================================================================

proc alloc*[T](cache: var PerTeamCacheWrapper[T]) =
  ## Initialize per-team cache resources.
  cache.phase = phaseAllocated
  cache.stepGeneration = 0
  for i in 0 ..< MapRoomObjectsTeams:
    cache.teamGen[i] = CacheInvalid

proc reset*[T](cache: var PerTeamCacheWrapper[T]) =
  ## Reset cache for a new step.
  assert cache.phase in {phaseAllocated, phaseActive}, "Cannot reset unallocated cache"
  inc cache.stepGeneration
  cache.phase = phaseActive

proc cleanup*[T](cache: var PerTeamCacheWrapper[T]) =
  ## Release cache resources.
  cache.phase = phaseCleaned
  for i in 0 ..< MapRoomObjectsTeams:
    cache.teamGen[i] = CacheInvalid

proc isValid*[T](cache: PerTeamCacheWrapper[T], teamId: int): bool {.inline.} =
  ## Check if cached value is valid for this team.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false
  cache.teamGen[teamId] == cache.stepGeneration

proc get*[T](cache: var PerTeamCacheWrapper[T], teamId: int,
             compute: proc(teamId: int): T): T =
  ## Get cached value for team or compute and cache if not valid.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return compute(teamId)
  if cache.teamGen[teamId] != cache.stepGeneration:
    cache.values[teamId] = compute(teamId)
    cache.teamGen[teamId] = cache.stepGeneration
  cache.values[teamId]

proc set*[T](cache: var PerTeamCacheWrapper[T], teamId: int, value: T) =
  ## Set cached value for team and mark as valid.
  if teamId >= 0 and teamId < MapRoomObjectsTeams:
    cache.values[teamId] = value
    cache.teamGen[teamId] = cache.stepGeneration

proc invalidate*[T](cache: var PerTeamCacheWrapper[T], teamId: int) {.inline.} =
  ## Invalidate cached value for a specific team.
  if teamId >= 0 and teamId < MapRoomObjectsTeams:
    cache.teamGen[teamId] = CacheInvalid

# =============================================================================
# AgentStateLifecycle - Per-agent state tracking
# =============================================================================

proc init*(lifecycle: var AgentStateLifecycle) =
  ## Initialize agent state lifecycle tracking.
  for i in 0 ..< MapAgents:
    lifecycle.activeAgents[i] = false
    lifecycle.lastActiveStep[i] = 0
    lifecycle.needsCleanup[i] = false

proc markActive*(lifecycle: var AgentStateLifecycle, agentId: int, currentStep: int32) =
  ## Mark an agent as active at the current step.
  if agentId >= 0 and agentId < MapAgents:
    lifecycle.activeAgents[agentId] = true
    lifecycle.lastActiveStep[agentId] = currentStep
    lifecycle.needsCleanup[agentId] = false

proc markInactive*(lifecycle: var AgentStateLifecycle, agentId: int) =
  ## Mark an agent as inactive (died, despawned, etc.).
  ## The agent's state will be flagged for cleanup.
  if agentId >= 0 and agentId < MapAgents:
    if lifecycle.activeAgents[agentId]:
      lifecycle.needsCleanup[agentId] = true
    lifecycle.activeAgents[agentId] = false

proc isActive*(lifecycle: AgentStateLifecycle, agentId: int): bool {.inline.} =
  ## Check if agent is currently active.
  if agentId < 0 or agentId >= MapAgents:
    return false
  lifecycle.activeAgents[agentId]

proc needsCleanup*(lifecycle: AgentStateLifecycle, agentId: int): bool {.inline.} =
  ## Check if agent's state needs cleanup.
  if agentId < 0 or agentId >= MapAgents:
    return false
  lifecycle.needsCleanup[agentId]

proc clearCleanupFlag*(lifecycle: var AgentStateLifecycle, agentId: int) =
  ## Clear the cleanup flag after state has been cleaned up.
  if agentId >= 0 and agentId < MapAgents:
    lifecycle.needsCleanup[agentId] = false

proc getAgentsNeedingCleanup*(lifecycle: AgentStateLifecycle): seq[int] =
  ## Get list of agent IDs that need state cleanup.
  result = @[]
  for i in 0 ..< MapAgents:
    if lifecycle.needsCleanup[i]:
      result.add(i)

proc detectStaleAgents*(lifecycle: var AgentStateLifecycle, currentStep: int32,
                        staleThreshold: int32 = 100): seq[int] =
  ## Detect agents that haven't been active for staleThreshold steps.
  ## Marks them for cleanup and returns their IDs.
  result = @[]
  for i in 0 ..< MapAgents:
    if lifecycle.activeAgents[i]:
      if currentStep - lifecycle.lastActiveStep[i] > staleThreshold:
        lifecycle.needsCleanup[i] = true
        lifecycle.activeAgents[i] = false
        result.add(i)
