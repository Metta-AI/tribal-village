# Inter-role coordination system
# Allows agents to communicate needs across role boundaries:
# - Gatherer requests protection from Fighter when under attack
# - Fighter requests defensive structures from Builder when seeing threats
# - Builder responds to defense requests by prioritizing walls/towers

# This file is designed to be used alongside the include-based ai system.
# It doesn't import ai_core to avoid type namespace conflicts.

import vmath
import ../common, ../environment

const
  MaxCoordinationRequests* = 16  # Max pending requests per team
  RequestExpirationSteps* = 60  # Requests expire after N steps
  DuplicateWindowSteps* = 30    # Duplicate detection window (steps)
  ProtectionResponseRadius* = 15  # Fighters respond to protection requests within this radius
  DefenseRequestRadius* = 20  # Distance from threat that triggers defense request

type
  CoordinationRequestKind* = enum
    RequestProtection   # Gatherer requests Fighter escort
    RequestDefense      # Fighter requests Builder to build defensive structures
    RequestSiegeBuild   # Fighter requests Builder to build siege workshop

  CoordinationPriority* = enum
    PriorityLow = 0
    PriorityNormal = 1
    PriorityHigh = 2        # Urgent requests (e.g. active combat)

  CoordinationRequest* = object
    kind*: CoordinationRequestKind
    teamId*: int
    requesterId*: int       # Agent ID that made the request
    requesterPos*: IVec2    # Position of requester
    threatPos*: IVec2       # Position of the threat (for defense/protection)
    createdStep*: int       # Step when created
    fulfilled*: bool        # Whether request has been handled
    priority*: CoordinationPriority  # Request priority for fulfillment ordering

  CoordinationState* = object
    requests*: array[MaxCoordinationRequests, CoordinationRequest]
    requestCount*: int

# Team-indexed coordination state (global storage)
var teamCoordination*: array[MapRoomObjectsTeams, CoordinationState]

proc clearExpiredRequests*(step: int) =
  ## Remove expired and fulfilled requests
  for teamId in 0 ..< MapRoomObjectsTeams:
    var writeIdx = 0
    for readIdx in 0 ..< teamCoordination[teamId].requestCount:
      let req = teamCoordination[teamId].requests[readIdx]
      if not req.fulfilled and (step - req.createdStep) < RequestExpirationSteps:
        teamCoordination[teamId].requests[writeIdx] = req
        inc writeIdx
    teamCoordination[teamId].requestCount = writeIdx

proc addRequest*(teamId: int, kind: CoordinationRequestKind,
                 requesterId: int, requesterPos, threatPos: IVec2, step: int,
                 priority: CoordinationPriority = PriorityNormal): bool =
  ## Add a coordination request. Returns true if added successfully.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false
  # Check for duplicate (same requester, same kind, recent)
  for i in 0 ..< teamCoordination[teamId].requestCount:
    let req = teamCoordination[teamId].requests[i]
    if req.requesterId == requesterId and req.kind == kind and
       (step - req.createdStep) < DuplicateWindowSteps:
      return false
  if teamCoordination[teamId].requestCount >= MaxCoordinationRequests:
    # Remove oldest request to make room
    for i in 1 ..< MaxCoordinationRequests:
      teamCoordination[teamId].requests[i-1] = teamCoordination[teamId].requests[i]
    dec teamCoordination[teamId].requestCount
  let idx = teamCoordination[teamId].requestCount
  teamCoordination[teamId].requests[idx] = CoordinationRequest(
    kind: kind,
    teamId: teamId,
    requesterId: requesterId,
    requesterPos: requesterPos,
    threatPos: threatPos,
    createdStep: step,
    fulfilled: false,
    priority: priority
  )
  inc teamCoordination[teamId].requestCount
  true

proc findNearestProtectionRequest*(teamId: int, agentPos: IVec2): ptr CoordinationRequest =
  ## Find the highest-priority, nearest unfulfilled protection request within response radius
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return nil
  var bestDist = int.high
  var bestPriority = PriorityLow
  var bestReq: ptr CoordinationRequest = nil
  for i in 0 ..< teamCoordination[teamId].requestCount:
    let req = addr teamCoordination[teamId].requests[i]
    if req.kind != RequestProtection or req.fulfilled:
      continue
    let dx = abs(agentPos.x - req.requesterPos.x)
    let dy = abs(agentPos.y - req.requesterPos.y)
    let dist = int(if dx > dy: dx else: dy)  # chebyshevDist inline
    if dist <= ProtectionResponseRadius:
      if req.priority > bestPriority or
         (req.priority == bestPriority and dist < bestDist):
        bestDist = dist
        bestPriority = req.priority
        bestReq = req
  bestReq

proc hasDefenseRequest*(teamId: int): bool =
  ## Check if there's an unfulfilled defense request
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false
  for i in 0 ..< teamCoordination[teamId].requestCount:
    let req = teamCoordination[teamId].requests[i]
    if req.kind == RequestDefense and not req.fulfilled:
      return true
  false

proc hasSiegeBuildRequest*(teamId: int): bool =
  ## Check if there's an unfulfilled siege build request
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false
  for i in 0 ..< teamCoordination[teamId].requestCount:
    let req = teamCoordination[teamId].requests[i]
    if req.kind == RequestSiegeBuild and not req.fulfilled:
      return true
  false

proc markDefenseRequestFulfilled*(teamId: int) =
  ## Mark the highest-priority unfulfilled defense request as fulfilled
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  var bestIdx = -1
  var bestPriority = PriorityLow
  for i in 0 ..< teamCoordination[teamId].requestCount:
    if teamCoordination[teamId].requests[i].kind == RequestDefense and
       not teamCoordination[teamId].requests[i].fulfilled:
      if bestIdx < 0 or teamCoordination[teamId].requests[i].priority > bestPriority:
        bestIdx = i
        bestPriority = teamCoordination[teamId].requests[i].priority
  if bestIdx >= 0:
    teamCoordination[teamId].requests[bestIdx].fulfilled = true

proc markSiegeBuildRequestFulfilled*(teamId: int) =
  ## Mark the highest-priority unfulfilled siege build request as fulfilled
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  var bestIdx = -1
  var bestPriority = PriorityLow
  for i in 0 ..< teamCoordination[teamId].requestCount:
    if teamCoordination[teamId].requests[i].kind == RequestSiegeBuild and
       not teamCoordination[teamId].requests[i].fulfilled:
      if bestIdx < 0 or teamCoordination[teamId].requests[i].priority > bestPriority:
        bestIdx = i
        bestPriority = teamCoordination[teamId].requests[i].priority
  if bestIdx >= 0:
    teamCoordination[teamId].requests[bestIdx].fulfilled = true

# --- Coordination request creators (called from role behaviors) ---

proc requestProtectionFromFighter*(env: Environment, agent: Thing, threatPos: IVec2) =
  ## Called by Gatherer when fleeing - requests Fighter escort
  let teamId = getTeamId(agent)
  discard addRequest(teamId, RequestProtection, agent.agentId, agent.pos, threatPos, env.currentStep)

proc requestDefenseFromBuilder*(env: Environment, agent: Thing, threatPos: IVec2) =
  ## Called by Fighter when seeing enemy threat - requests Builder to prioritize defensive structures
  let teamId = getTeamId(agent)
  discard addRequest(teamId, RequestDefense, agent.agentId, agent.pos, threatPos, env.currentStep)

proc requestSiegeFromBuilder*(env: Environment, agent: Thing) =
  ## Called by Fighter when seeing enemy structures - requests Builder to build siege workshop
  let teamId = getTeamId(agent)
  discard addRequest(teamId, RequestSiegeBuild, agent.agentId, agent.pos, agent.pos, env.currentStep)

# --- Coordination behavior helpers ---

proc fighterShouldEscort*(env: Environment, agent: Thing): tuple[should: bool, target: IVec2] =
  ## Check if fighter should respond to a protection request
  ## Returns (true, target position) if should escort
  let teamId = getTeamId(agent)
  let req = findNearestProtectionRequest(teamId, agent.pos)
  if isNil(req):
    return (false, ivec2(-1, -1))
  # Check if the requester is still alive and still needs help
  if req.requesterId >= 0 and req.requesterId < MapAgents:
    let requester = env.agents[req.requesterId]
    if isAgentAlive(env, requester):
      # Move toward the requester's current position
      return (true, requester.pos)
  (false, ivec2(-1, -1))

proc builderShouldPrioritizeDefense*(teamId: int): bool =
  ## Check if builder should prioritize defensive structures
  hasDefenseRequest(teamId)

# Note: builderShouldBuildSiege is implemented in builder.nim with access to Controller
