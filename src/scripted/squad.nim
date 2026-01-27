# Squad coordination system for multi-unit tactics
# Enables grouped units to move in formation, attack together, and retreat as one

import vmath
import ../common, ../environment

const
  MaxSquadSize* = 8           # Maximum units per squad
  MaxSquadsPerTeam* = 4       # Maximum squads per team
  FormationSpacing* = 2       # Distance between units in formation
  SquadCohesionRadius* = 10   # Max distance before unit considered separated
  SquadRetreatHpThreshold* = 0.4  # Squad retreats when avg HP drops below this
  SquadRegroupRadius* = 3     # Distance for squad to be considered grouped

type
  FormationType* = enum
    FormationLine       # Units spread horizontally
    FormationWedge      # V-shape, leader in front
    FormationCircle     # Defensive circle around leader
    FormationColumn     # Single file behind leader

  SquadRole* = enum
    RoleTank     # Front line, absorbs damage (Knight, ManAtArms)
    RoleDPS      # Damage dealers (Archer, Mangonel)
    RoleHealer   # Support units (Monk)
    RoleGeneral  # Default role

  SquadState* = enum
    SquadIdle        # No active orders
    SquadMoving      # Moving to destination in formation
    SquadAttacking   # Engaged in combat
    SquadRetreating  # Retreating to safety
    SquadRegrouping  # Reforming after being scattered

  SquadMember* = object
    agentId*: int32           # Agent ID (-1 = empty slot)
    role*: SquadRole          # Combat role in squad
    formationOffset*: IVec2   # Offset from leader in current formation
    isAlive*: bool            # Cached alive status

  Squad* = object
    id*: int32                # Squad identifier
    teamId*: int32            # Owning team
    members*: array[MaxSquadSize, SquadMember]
    memberCount*: int32       # Number of active members
    leaderId*: int32          # Agent ID of squad leader (-1 = no leader)
    formation*: FormationType # Current formation
    state*: SquadState        # Current squad state
    targetPos*: IVec2         # Movement/attack target
    rallyPoint*: IVec2        # Fallback position for retreat/regroup
    lastUpdateStep*: int32    # Last step this squad was updated
    active*: bool             # Whether squad is in use

  SquadManager* = object
    squads*: array[MaxSquadsPerTeam, Squad]
    squadCount*: int32

# Team-indexed squad managers
var teamSquads*: array[MapRoomObjectsTeams, SquadManager]

# Formation offset calculations
proc getFormationOffsets*(formation: FormationType, memberIndex: int, totalMembers: int): IVec2 =
  ## Calculate position offset from leader for a given formation
  case formation
  of FormationLine:
    # Horizontal line centered on leader
    let halfCount = totalMembers div 2
    let offset = memberIndex - halfCount
    result = ivec2(offset.int32 * FormationSpacing.int32, 0'i32)
  of FormationWedge:
    # V-shape with leader at point
    if memberIndex == 0:
      result = ivec2(0, 0)  # Leader at front
    else:
      let row = (memberIndex + 1) div 2
      let side = if memberIndex mod 2 == 1: 1'i32 else: -1'i32
      result = ivec2(side * row.int32 * FormationSpacing.int32,
                     row.int32 * FormationSpacing.int32)
  of FormationCircle:
    # Circular formation around leader
    if memberIndex == 0:
      result = ivec2(0, 0)  # Leader in center
    else:
      # Distribute around circle
      let angle = float32(memberIndex - 1) * (6.28318 / float32(totalMembers - 1))
      let radius = FormationSpacing.float32 * 1.5
      result = ivec2(int32(cos(angle) * radius), int32(sin(angle) * radius))
  of FormationColumn:
    # Single file behind leader
    result = ivec2(0, memberIndex.int32 * FormationSpacing.int32)

proc getSquadRoleForUnit*(unitClass: AgentUnitClass): SquadRole =
  ## Determine squad role based on unit class
  case unitClass
  of UnitKnight, UnitManAtArms, UnitBatteringRam:
    RoleTank
  of UnitArcher, UnitMangonel:
    RoleDPS
  of UnitMonk:
    RoleHealer
  else:
    RoleGeneral

proc createSquad*(teamId: int, formation: FormationType = FormationWedge): ptr Squad =
  ## Create a new squad for a team. Returns nil if max squads reached.
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return nil
  var manager = addr teamSquads[teamId]
  for i in 0 ..< MaxSquadsPerTeam:
    if not manager.squads[i].active:
      manager.squads[i] = Squad(
        id: i.int32,
        teamId: teamId.int32,
        memberCount: 0,
        leaderId: -1,
        formation: formation,
        state: SquadIdle,
        targetPos: ivec2(-1, -1),
        rallyPoint: ivec2(-1, -1),
        lastUpdateStep: 0,
        active: true
      )
      for j in 0 ..< MaxSquadSize:
        manager.squads[i].members[j].agentId = -1
      if manager.squadCount <= i.int32:
        manager.squadCount = (i + 1).int32
      return addr manager.squads[i]
  nil

proc disbandSquad*(squad: ptr Squad) =
  ## Disband a squad, freeing all members
  if squad.isNil:
    return
  squad.active = false
  squad.memberCount = 0
  squad.leaderId = -1
  for i in 0 ..< MaxSquadSize:
    squad.members[i].agentId = -1

proc addToSquad*(squad: ptr Squad, agentId: int, unitClass: AgentUnitClass): bool =
  ## Add an agent to a squad. Returns true if successful.
  if squad.isNil or not squad.active or squad.memberCount >= MaxSquadSize:
    return false
  # Check if already in squad
  for i in 0 ..< squad.memberCount:
    if squad.members[i].agentId == agentId.int32:
      return false
  let idx = squad.memberCount
  squad.members[idx] = SquadMember(
    agentId: agentId.int32,
    role: getSquadRoleForUnit(unitClass),
    formationOffset: ivec2(0, 0),
    isAlive: true
  )
  inc squad.memberCount
  # First member becomes leader
  if squad.leaderId < 0:
    squad.leaderId = agentId.int32
  true

proc removeFromSquad*(squad: ptr Squad, agentId: int) =
  ## Remove an agent from a squad
  if squad.isNil or not squad.active:
    return
  var found = false
  for i in 0 ..< squad.memberCount:
    if found:
      squad.members[i - 1] = squad.members[i]
    elif squad.members[i].agentId == agentId.int32:
      found = true
  if found:
    dec squad.memberCount
    squad.members[squad.memberCount].agentId = -1
    # Elect new leader if needed
    if squad.leaderId == agentId.int32:
      squad.leaderId = if squad.memberCount > 0: squad.members[0].agentId else: -1

proc getSquadForAgent*(teamId, agentId: int): ptr Squad =
  ## Find which squad an agent belongs to (nil if none)
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return nil
  let manager = addr teamSquads[teamId]
  for i in 0 ..< manager.squadCount:
    if not manager.squads[i].active:
      continue
    for j in 0 ..< manager.squads[i].memberCount:
      if manager.squads[i].members[j].agentId == agentId.int32:
        return addr manager.squads[i]
  nil

proc electLeader*(squad: ptr Squad, env: Environment) =
  ## Elect the best leader based on unit class and HP
  ## Priority: Tank > DPS > Healer, then by HP
  if squad.isNil or squad.memberCount == 0:
    return
  var bestScore = -1
  var bestAgentId: int32 = -1
  for i in 0 ..< squad.memberCount:
    let member = squad.members[i]
    if member.agentId < 0:
      continue
    let agent = env.agents[member.agentId]
    if not isAgentAlive(env, agent):
      continue
    # Score: role priority * 1000 + HP
    let rolePriority = case member.role
      of RoleTank: 3
      of RoleDPS: 2
      of RoleHealer: 1
      of RoleGeneral: 0
    let score = rolePriority * 1000 + agent.hp.int
    if score > bestScore:
      bestScore = score
      bestAgentId = member.agentId
  if bestAgentId >= 0:
    squad.leaderId = bestAgentId

proc updateFormationOffsets*(squad: ptr Squad) =
  ## Recalculate formation offsets for all members
  if squad.isNil:
    return
  for i in 0 ..< squad.memberCount:
    squad.members[i].formationOffset = getFormationOffsets(
      squad.formation, i.int, squad.memberCount.int
    )

proc getSquadAverageHp*(squad: ptr Squad, env: Environment): float =
  ## Calculate average HP ratio of squad members
  if squad.isNil or squad.memberCount == 0:
    return 1.0
  var totalRatio = 0.0
  var aliveCount = 0
  for i in 0 ..< squad.memberCount:
    let agentId = squad.members[i].agentId
    if agentId < 0:
      continue
    let agent = env.agents[agentId]
    if not isAgentAlive(env, agent):
      continue
    inc aliveCount
    if agent.maxHp > 0:
      totalRatio += float(agent.hp) / float(agent.maxHp)
  if aliveCount == 0:
    return 0.0
  totalRatio / float(aliveCount)

proc getSquadCenterPos*(squad: ptr Squad, env: Environment): IVec2 =
  ## Get the center position of the squad
  if squad.isNil or squad.memberCount == 0:
    return ivec2(-1, -1)
  var sumX, sumY: int32 = 0
  var count: int32 = 0
  for i in 0 ..< squad.memberCount:
    let agentId = squad.members[i].agentId
    if agentId < 0:
      continue
    let agent = env.agents[agentId]
    if not isAgentAlive(env, agent):
      continue
    sumX += agent.pos.x
    sumY += agent.pos.y
    inc count
  if count == 0:
    return ivec2(-1, -1)
  ivec2(sumX div count, sumY div count)

proc isSquadGrouped*(squad: ptr Squad, env: Environment): bool =
  ## Check if squad members are close enough to be considered grouped
  if squad.isNil or squad.memberCount <= 1:
    return true
  let center = getSquadCenterPos(squad, env)
  if center.x < 0:
    return false
  for i in 0 ..< squad.memberCount:
    let agentId = squad.members[i].agentId
    if agentId < 0:
      continue
    let agent = env.agents[agentId]
    if not isAgentAlive(env, agent):
      continue
    let dx = abs(agent.pos.x - center.x)
    let dy = abs(agent.pos.y - center.y)
    let dist = if dx > dy: dx else: dy
    if dist > SquadRegroupRadius:
      return false
  true

proc getFormationPosForMember*(squad: ptr Squad, memberIdx: int, env: Environment): IVec2 =
  ## Get the target position for a squad member based on leader position and formation
  if squad.isNil or squad.leaderId < 0:
    return ivec2(-1, -1)
  let leader = env.agents[squad.leaderId]
  if not isAgentAlive(env, leader):
    return ivec2(-1, -1)
  let offset = squad.members[memberIdx].formationOffset
  ivec2(leader.pos.x + offset.x, leader.pos.y + offset.y)

proc setSquadTarget*(squad: ptr Squad, target: IVec2, state: SquadState = SquadMoving) =
  ## Set the squad's movement/attack target
  if squad.isNil:
    return
  squad.targetPos = target
  squad.state = state

proc setSquadRallyPoint*(squad: ptr Squad, rallyPoint: IVec2) =
  ## Set the squad's rally point for retreat/regroup
  if squad.isNil:
    return
  squad.rallyPoint = rallyPoint

proc shouldSquadRetreat*(squad: ptr Squad, env: Environment): bool =
  ## Check if squad should retreat based on HP
  if squad.isNil:
    return false
  getSquadAverageHp(squad, env) < SquadRetreatHpThreshold

proc updateSquad*(squad: ptr Squad, env: Environment, currentStep: int32) =
  ## Update squad state - check for dead members, elect new leader if needed
  if squad.isNil or not squad.active:
    return
  # Update alive status and count alive members
  var aliveCount: int32 = 0
  for i in 0 ..< squad.memberCount:
    let agentId = squad.members[i].agentId
    if agentId >= 0:
      squad.members[i].isAlive = isAgentAlive(env, env.agents[agentId])
      if squad.members[i].isAlive:
        inc aliveCount
  # Disband if all members dead
  if aliveCount == 0:
    disbandSquad(squad)
    return
  # Re-elect leader if current leader is dead
  if squad.leaderId >= 0:
    let leader = env.agents[squad.leaderId]
    if not isAgentAlive(env, leader):
      electLeader(squad, env)
      updateFormationOffsets(squad)
  # Auto-retreat check
  if squad.state == SquadAttacking and shouldSquadRetreat(squad, env):
    if squad.rallyPoint.x >= 0:
      squad.state = SquadRetreating
      squad.targetPos = squad.rallyPoint
    else:
      # Retreat toward team's altar
      if squad.leaderId >= 0:
        let leader = env.agents[squad.leaderId]
        if leader.homeAltar.x >= 0:
          squad.targetPos = leader.homeAltar
          squad.state = SquadRetreating
  # Check if regrouping is needed
  if squad.state == SquadMoving and not isSquadGrouped(squad, env):
    squad.state = SquadRegrouping
  elif squad.state == SquadRegrouping and isSquadGrouped(squad, env):
    squad.state = SquadMoving
  squad.lastUpdateStep = currentStep

proc clearTeamSquads*(teamId: int) =
  ## Clear all squads for a team (e.g., at episode reset)
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return
  teamSquads[teamId] = SquadManager()

proc getAgentSquadTarget*(teamId, agentId: int, env: Environment): tuple[hasTarget: bool, target: IVec2, isLeader: bool] =
  ## Get the target position for an agent based on their squad membership
  ## Returns (hasTarget, target position, whether agent is leader)
  let squad = getSquadForAgent(teamId, agentId)
  if squad.isNil or not squad.active or squad.state == SquadIdle:
    return (false, ivec2(-1, -1), false)
  let isLeader = squad.leaderId == agentId.int32
  case squad.state
  of SquadIdle:
    return (false, ivec2(-1, -1), isLeader)
  of SquadMoving, SquadAttacking:
    if isLeader:
      # Leader moves to squad target
      return (true, squad.targetPos, true)
    else:
      # Non-leaders follow formation
      for i in 0 ..< squad.memberCount:
        if squad.members[i].agentId == agentId.int32:
          let formationPos = getFormationPosForMember(squad, i.int, env)
          if formationPos.x >= 0:
            return (true, formationPos, false)
          break
      return (false, ivec2(-1, -1), false)
  of SquadRetreating:
    if isLeader:
      return (true, squad.rallyPoint, true)
    else:
      # Non-leaders follow leader during retreat
      if squad.leaderId >= 0:
        let leader = env.agents[squad.leaderId]
        if isAgentAlive(env, leader):
          return (true, leader.pos, false)
      return (true, squad.rallyPoint, false)
  of SquadRegrouping:
    # Everyone moves toward squad center
    let center = getSquadCenterPos(squad, env)
    if center.x >= 0:
      return (true, center, isLeader)
    return (false, ivec2(-1, -1), isLeader)

proc isAgentSquadLeader*(teamId, agentId: int): bool =
  ## Check if agent is a squad leader
  let squad = getSquadForAgent(teamId, agentId)
  if squad.isNil:
    return false
  squad.leaderId == agentId.int32

proc getSquadMembers*(teamId, agentId: int): seq[int32] =
  ## Get all squad member IDs for an agent's squad
  result = @[]
  let squad = getSquadForAgent(teamId, agentId)
  if squad.isNil:
    return
  for i in 0 ..< squad.memberCount:
    if squad.members[i].agentId >= 0:
      result.add(squad.members[i].agentId)

proc squadAttackTarget*(squad: ptr Squad, target: IVec2) =
  ## Order squad to attack a target position (synchronized attack)
  if squad.isNil:
    return
  squad.targetPos = target
  squad.state = SquadAttacking

proc squadMoveToFormation*(squad: ptr Squad, target: IVec2, formation: FormationType) =
  ## Order squad to move to target in specified formation
  if squad.isNil:
    return
  squad.formation = formation
  squad.targetPos = target
  squad.state = SquadMoving
  updateFormationOffsets(squad)

proc squadRetreat*(squad: ptr Squad) =
  ## Order squad to retreat to rally point
  if squad.isNil:
    return
  if squad.rallyPoint.x >= 0:
    squad.targetPos = squad.rallyPoint
  squad.state = SquadRetreating
