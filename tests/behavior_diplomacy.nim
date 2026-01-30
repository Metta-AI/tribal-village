import std/[unittest, strformat]
import environment
import types
import items
import test_utils

suite "Behavior: Team Identity and Membership":
  test "agents on same team share team ID":
    let env = makeEmptyEnv()
    let a0 = addAgentAt(env, 0, ivec2(10, 10))
    let a1 = addAgentAt(env, 1, ivec2(10, 11))
    check getTeamId(a0) == 0
    check getTeamId(a1) == 0
    echo fmt"  Agent 0 team={getTeamId(a0)}, Agent 1 team={getTeamId(a1)}"

  test "agents on different teams have different team IDs":
    let env = makeEmptyEnv()
    let a0 = addAgentAt(env, 0, ivec2(10, 10))
    let a1 = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 11))
    check getTeamId(a0) == 0
    check getTeamId(a1) == 1
    echo fmt"  Agent 0 team={getTeamId(a0)}, Agent 1 team={getTeamId(a1)}"

  test "teamIdOverride changes effective team":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    check getTeamId(agent) == 0
    agent.teamIdOverride = 3
    check getTeamId(agent) == 3
    echo fmt"  Default team=0, override team={getTeamId(agent)}"

  test "clearing teamIdOverride restores default team":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    agent.teamIdOverride = 5
    check getTeamId(agent) == 5
    agent.teamIdOverride = -1
    check getTeamId(agent) == 0
    echo fmt"  After clearing override: team={getTeamId(agent)}"

suite "Behavior: Combat Respects Team Affiliation":
  test "same-team attack is rejected":
    let env = makeEmptyEnv()
    let attacker = addAgentAt(env, 0, ivec2(10, 10))
    attacker.attackDamage = 5
    let ally = addAgentAt(env, 1, ivec2(10, 9))
    let startHp = ally.hp

    env.stepAction(attacker.agentId, 2'u8, dirIndex(attacker.pos, ally.pos))

    check ally.hp == startHp
    echo fmt"  Ally HP unchanged: {startHp} -> {ally.hp}"

  test "cross-team attack deals damage":
    let env = makeEmptyEnv()
    let attacker = addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitManAtArms, stance = StanceAggressive)
    applyUnitClass(attacker, UnitManAtArms)
    let enemy = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 9), unitClass = UnitManAtArms, stance = StanceAggressive)
    applyUnitClass(enemy, UnitManAtArms)
    let startHp = enemy.hp

    env.stepAction(attacker.agentId, 2'u8, dirIndex(attacker.pos, enemy.pos))

    check enemy.hp < startHp
    echo fmt"  Enemy HP: {startHp} -> {enemy.hp}"

  test "converted unit is treated as new team member by combat":
    let env = makeEmptyEnv()
    let altarPos = ivec2(12, 10)
    discard addAltar(env, altarPos, 0, 10)
    discard addBuilding(env, House, ivec2(12, 11), 0)
    # Monk converts enemy; add attacker first (id 1) so it exists before stepAction
    let monk = addAgentAt(env, 0, ivec2(10, 10), homeAltar = altarPos, unitClass = UnitMonk)
    let attacker = addAgentAt(env, 1, ivec2(10, 8))
    attacker.attackDamage = 5
    let target = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 9))
    check getTeamId(target) == 1

    env.stepAction(monk.agentId, 2'u8, dirIndex(monk.pos, target.pos))
    check getTeamId(target) == 0

    # Now a team 0 attacker should NOT be able to damage the converted unit
    let hpBefore = target.hp
    env.stepAction(attacker.agentId, 2'u8, dirIndex(attacker.pos, target.pos))
    check target.hp == hpBefore
    echo fmt"  Converted unit HP unchanged by former ally attack: {hpBefore} -> {target.hp}"

  test "converted unit can be attacked by former allies":
    ## After conversion, the unit's old team can now attack it
    let env = makeEmptyEnv()
    let altarPos = ivec2(12, 10)
    discard addAltar(env, altarPos, 0, 10)
    discard addBuilding(env, House, ivec2(12, 11), 0)
    let monk = addAgentAt(env, 0, ivec2(10, 10), homeAltar = altarPos, unitClass = UnitMonk)
    let target = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 9))
    # Convert to team 0
    env.stepAction(monk.agentId, 2'u8, dirIndex(monk.pos, target.pos))
    check getTeamId(target) == 0

    # Manually set teamIdOverride to verify combat team check
    # Use a separate fresh env for clarity
    let env2 = makeEmptyEnv()
    let unit = addAgentAt(env2, MapAgentsPerTeam, ivec2(10, 9))
    unit.teamIdOverride = 0  # Simulate conversion to team 0
    let attacker = addAgentAt(env2, MapAgentsPerTeam + 1, ivec2(10, 8))
    attacker.attackDamage = 5
    let hpBefore = unit.hp
    env2.stepAction(attacker.agentId, 2'u8, dirIndex(attacker.pos, unit.pos))
    check unit.hp < hpBefore
    echo fmt"  Former ally attacks converted unit: HP {hpBefore} -> {unit.hp}"

suite "Behavior: Monk Conversion Diplomatic Transitions":
  test "monk conversion changes unit team membership":
    let env = makeEmptyEnv()
    let altarPos = ivec2(12, 10)
    discard addAltar(env, altarPos, 0, 10)
    discard addBuilding(env, House, ivec2(12, 11), 0)
    let monk = addAgentAt(env, 0, ivec2(10, 10), homeAltar = altarPos, unitClass = UnitMonk)
    let enemy = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 9))

    check getTeamId(enemy) == 1
    env.stepAction(monk.agentId, 2'u8, dirIndex(monk.pos, enemy.pos))
    check getTeamId(enemy) == 0
    echo fmt"  Enemy team changed: 1 -> {getTeamId(enemy)}"

  test "conversion requires population capacity":
    let env = makeEmptyEnv()
    let altarPos = ivec2(12, 10)
    discard addAltar(env, altarPos, 0, 10)
    # No house means no pop capacity beyond TownCenter
    # Without any TownCenter or House, popCap = 0 so conversion fails
    let monk = addAgentAt(env, 0, ivec2(10, 10), homeAltar = altarPos, unitClass = UnitMonk)
    let enemy = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 9))

    env.stepAction(monk.agentId, 2'u8, dirIndex(monk.pos, enemy.pos))
    check getTeamId(enemy) == 1  # Should stay on enemy team (no pop cap)
    echo fmt"  No pop capacity -> conversion blocked, enemy still team {getTeamId(enemy)}"

  test "conversion assigns converted unit to nearest altar":
    let env = makeEmptyEnv()
    let nearAltar = ivec2(11, 10)
    let farAltar = ivec2(20, 20)
    discard addAltar(env, nearAltar, 0, 10)
    discard addAltar(env, farAltar, 0, 10)
    discard addBuilding(env, House, ivec2(12, 11), 0)
    let monk = addAgentAt(env, 0, ivec2(10, 10), homeAltar = nearAltar, unitClass = UnitMonk)
    let enemy = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 9))

    env.stepAction(monk.agentId, 2'u8, dirIndex(monk.pos, enemy.pos))
    check getTeamId(enemy) == 0
    # Converted unit should be assigned to the monk's home altar
    check enemy.homeAltar == nearAltar
    echo fmt"  Converted unit home altar: ({enemy.homeAltar.x}, {enemy.homeAltar.y})"

  test "double conversion returns unit to original default team":
    let env = makeEmptyEnv()
    # Setup: team 0 altar and housing
    let altar0 = ivec2(12, 10)
    discard addAltar(env, altar0, 0, 10)
    discard addBuilding(env, House, ivec2(12, 11), 0)
    # Setup: team 1 altar and housing
    let altar1 = ivec2(20, 10)
    discard addAltar(env, altar1, 1, 10)
    discard addBuilding(env, House, ivec2(20, 11), 1)

    # Create all agents before any stepAction (which pads to MapAgents)
    let monk0 = addAgentAt(env, 0, ivec2(10, 10), homeAltar = altar0, unitClass = UnitMonk)
    let target = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 9))
    let monk1 = addAgentAt(env, MapAgentsPerTeam + 1, ivec2(10, 8), homeAltar = altar1, unitClass = UnitMonk)
    check getTeamId(target) == 1

    # Team 0 monk converts team 1 unit
    env.stepAction(monk0.agentId, 2'u8, dirIndex(monk0.pos, target.pos))
    check getTeamId(target) == 0

    # Team 1 monk converts the unit back
    env.stepAction(monk1.agentId, 2'u8, dirIndex(monk1.pos, target.pos))
    # The unit's default team is 1 (agentId = MapAgentsPerTeam), so converting back should clear override
    check getTeamId(target) == 1
    echo fmt"  Double conversion restored team: {getTeamId(target)}"

suite "Behavior: Monk Aura Heals Allies Only":
  test "monk aura heals nearby same-team allies":
    let env = makeEmptyEnv()
    let monk = addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitMonk)
    let ally = addAgentAt(env, 1, ivec2(10, 11))
    ally.hp = 1
    ally.maxHp = 10
    let hpBefore = ally.hp

    env.stepNoop()  # Triggers monk aura processing

    check ally.hp > hpBefore
    echo fmt"  Ally healed by aura: {hpBefore} -> {ally.hp}"

  test "monk aura does not heal enemies":
    let env = makeEmptyEnv()
    let monk = addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitMonk)
    let enemy = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 11))
    enemy.hp = 1
    enemy.maxHp = 10
    let hpBefore = enemy.hp

    env.stepNoop()

    check enemy.hp == hpBefore
    echo fmt"  Enemy NOT healed by aura: {hpBefore} -> {enemy.hp}"

  test "converted unit receives aura healing from new team monk":
    let env = makeEmptyEnv()
    let altarPos = ivec2(12, 10)
    discard addAltar(env, altarPos, 0, 10)
    discard addBuilding(env, House, ivec2(12, 11), 0)
    let monk = addAgentAt(env, 0, ivec2(10, 10), homeAltar = altarPos, unitClass = UnitMonk)
    let enemy = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 9))

    # Convert enemy to team 0
    env.stepAction(monk.agentId, 2'u8, dirIndex(monk.pos, enemy.pos))
    check getTeamId(enemy) == 0

    # Damage the converted unit
    enemy.hp = 1
    enemy.maxHp = 10
    let hpBefore = enemy.hp

    # Aura should now heal the converted unit (same team as monk)
    env.stepNoop()
    check enemy.hp > hpBefore
    echo fmt"  Converted unit healed by new team monk: {hpBefore} -> {enemy.hp}"

suite "Behavior: Item Giving Between Units":
  test "same-team agent can give items to teammate":
    let env = makeEmptyEnv()
    let giver = addAgentAt(env, 0, ivec2(10, 10))
    let receiver = addAgentAt(env, 1, ivec2(10, 9))
    setInv(giver, ItemWood, 5)

    env.stepAction(giver.agentId, 5'u8, dirIndex(giver.pos, receiver.pos))

    let giverWood = getInv(giver, ItemWood)
    let receiverWood = getInv(receiver, ItemWood)
    check giverWood == 0
    check receiverWood == 5
    echo fmt"  Gave wood: giver={giverWood}, receiver={receiverWood}"

  test "cross-team agent can give items to enemy":
    ## The put action does not restrict by team - any adjacent agent can receive
    let env = makeEmptyEnv()
    let giver = addAgentAt(env, 0, ivec2(10, 10))
    let enemy = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 9))
    setInv(giver, ItemWood, 5)

    env.stepAction(giver.agentId, 5'u8, dirIndex(giver.pos, enemy.pos))

    let giverWood = getInv(giver, ItemWood)
    let enemyWood = getInv(enemy, ItemWood)
    check giverWood == 0
    check enemyWood == 5
    echo fmt"  Cross-team give: giver={giverWood}, enemy={enemyWood}"

suite "Behavior: Tower and Building Team Targeting":
  test "guard tower fires at enemy but not allies":
    let env = makeEmptyEnv()
    discard addBuilding(env, GuardTower, ivec2(10, 10), 0)
    # Create both agents before any step call (step pads agents to MapAgents)
    let ally = addAgentAt(env, 0, ivec2(10, 13))
    let enemy = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 12))
    let allyHpBefore = ally.hp
    let enemyHpBefore = enemy.hp

    env.stepNoop()
    check ally.hp == allyHpBefore  # Tower doesn't fire at allies
    check enemy.hp < enemyHpBefore  # Tower fires at enemy
    echo fmt"  Ally HP unchanged={allyHpBefore}, Enemy HP {enemyHpBefore}->{enemy.hp}"

  test "town center fires at enemy but not allies":
    let env = makeEmptyEnv()
    discard addBuilding(env, TownCenter, ivec2(10, 10), 0)
    let ally = addAgentAt(env, 0, ivec2(10, 14))
    let enemy = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 13))
    let allyHpBefore = ally.hp
    let enemyHpBefore = enemy.hp

    env.stepNoop()
    check ally.hp == allyHpBefore
    check enemy.hp < enemyHpBefore
    echo fmt"  TC: Ally HP unchanged={allyHpBefore}, Enemy HP {enemyHpBefore}->{enemy.hp}"

  test "converted unit is no longer targeted by new team tower":
    ## After conversion, a team's own tower should not fire at the converted ally
    let env = makeEmptyEnv()
    let altarPos = ivec2(12, 10)
    discard addAltar(env, altarPos, 0, 10)
    discard addBuilding(env, House, ivec2(12, 11), 0)
    discard addBuilding(env, GuardTower, ivec2(10, 10), 0)
    # Monk adjacent to enemy for conversion
    let monk = addAgentAt(env, 0, ivec2(10, 12), homeAltar = altarPos, unitClass = UnitMonk)
    let enemy = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 13))

    # Convert enemy to team 0
    env.stepAction(monk.agentId, 2'u8, dirIndex(monk.pos, enemy.pos))
    check getTeamId(enemy) == 0

    let hpAfterConversion = enemy.hp
    # Tower should NOT fire at newly converted ally
    env.stepNoop()
    check enemy.hp == hpAfterConversion
    echo fmt"  Converted unit safe from new team tower: HP={enemy.hp}"

suite "Behavior: Multi-team Interactions":
  test "three teams can coexist with independent combat":
    let env = makeEmptyEnv()
    let team0 = addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitManAtArms, stance = StanceAggressive)
    applyUnitClass(team0, UnitManAtArms)
    let team1 = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 9), unitClass = UnitManAtArms, stance = StanceAggressive)
    applyUnitClass(team1, UnitManAtArms)
    let team2 = addAgentAt(env, MapAgentsPerTeam * 2, ivec2(15, 15))
    let team2HpBefore = team2.hp

    # Team 0 attacks team 1 - team 2 is far away and unaffected
    for step in 0 ..< 10:
      env.stepAction(team0.agentId, 2'u8, dirIndex(team0.pos, team1.pos))

    check team1.hp < team1.maxHp  # team 1 took damage
    check team2.hp == team2HpBefore  # team 2 unaffected
    echo fmt"  Team1 HP={team1.hp}, Team2 HP={team2.hp} (unaffected)"

  test "altar attack respects team - cannot attack own altar":
    let env = makeEmptyEnv()
    let altar = addAltar(env, ivec2(10, 9), 0, 10)
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    agent.attackDamage = 5
    let heartsBefore = altar.hearts

    env.stepAction(agent.agentId, 2'u8, dirIndex(agent.pos, altar.pos))
    check altar.hearts == heartsBefore
    echo fmt"  Own altar hearts unchanged: {heartsBefore}"

  test "altar attack works against enemy altar":
    let env = makeEmptyEnv()
    let altar = addAltar(env, ivec2(10, 9), 1, 10)
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    agent.attackDamage = 5
    let heartsBefore = altar.hearts

    env.stepAction(agent.agentId, 2'u8, dirIndex(agent.pos, altar.pos))
    check altar.hearts < heartsBefore
    echo fmt"  Enemy altar hearts: {heartsBefore} -> {altar.hearts}"
