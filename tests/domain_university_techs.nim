import std/unittest
import environment
import items
import test_utils

suite "University Technologies":
  test "university tech research costs resources":
    let env = makeEmptyEnv()
    let university = addBuilding(env, University, ivec2(10, 9), 0)
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    # Cost for tech: 5 food + 3 gold
    setStockpile(env, 0, ResourceFood, 10)
    setStockpile(env, 0, ResourceGold, 10)

    # Initial tech level should be 0
    check env.teamUniversityTechs[0].levels[TechBallistics] == 0

    env.stepAction(agent.agentId, 3'u8, dirIndex(agent.pos, university.pos))

    # Tech should have been researched
    var totalLevels = 0
    for techType in UniversityTechType:
      totalLevels += env.teamUniversityTechs[0].levels[techType]
    check totalLevels == 1

    # Resources should have been spent (5 food + 3 gold)
    check env.stockpileCount(0, ResourceFood) == 5  # 10 - 5
    check env.stockpileCount(0, ResourceGold) == 7  # 10 - 3

  test "university tech fails without resources":
    let env = makeEmptyEnv()
    let university = addBuilding(env, University, ivec2(10, 9), 0)
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    # Not enough resources
    setStockpile(env, 0, ResourceFood, 1)
    setStockpile(env, 0, ResourceGold, 1)

    env.stepAction(agent.agentId, 3'u8, dirIndex(agent.pos, university.pos))

    # No tech should have been researched
    var totalLevels = 0
    for techType in UniversityTechType:
      totalLevels += env.teamUniversityTechs[0].levels[techType]
    check totalLevels == 0

  test "university tech max level is respected":
    let env = makeEmptyEnv()
    let university = addBuilding(env, University, ivec2(10, 9), 0)
    let agent = addAgentAt(env, 0, ivec2(10, 10))
    # Set all techs to max level
    for techType in UniversityTechType:
      env.teamUniversityTechs[0].levels[techType] = UniversityTechMaxLevel
    setStockpile(env, 0, ResourceFood, 100)
    setStockpile(env, 0, ResourceGold, 100)

    env.stepAction(agent.agentId, 3'u8, dirIndex(agent.pos, university.pos))

    # No resources should have been spent
    check env.stockpileCount(0, ResourceFood) == 100
    check env.stockpileCount(0, ResourceGold) == 100

  test "chemistry tech increases attack damage":
    let env = makeEmptyEnv()
    # Research Chemistry tech
    env.teamUniversityTechs[0].levels[TechChemistry] = 1
    # Create a man-at-arms and apply unit class
    let attacker = addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitManAtArms)
    applyUnitClass(attacker, UnitManAtArms)
    # Create an enemy target
    let defender = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 9))
    defender.hp = 10
    defender.maxHp = 10

    # Attack
    env.stepAction(attacker.agentId, 2'u8, dirIndex(attacker.pos, defender.pos))

    # Base damage is 2, +1 from Chemistry = 3 damage
    check defender.hp == 7

  test "siege engineers increases siege damage":
    let env = makeEmptyEnv()
    # Research Siege Engineers tech
    env.teamUniversityTechs[0].levels[TechSiegeEngineers] = 1
    # Create a mangonel (siege unit) and apply unit class
    let attacker = addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitMangonel)
    applyUnitClass(attacker, UnitMangonel)
    # Create an enemy target
    let defender = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 9))
    defender.hp = 20
    defender.maxHp = 20

    # Attack
    env.stepAction(attacker.agentId, 2'u8, dirIndex(attacker.pos, defender.pos))

    # Base damage is 2, +1 from Siege Engineers = 3 damage
    check defender.hp == 17

  test "chemistry and siege engineers stack":
    let env = makeEmptyEnv()
    # Research both techs
    env.teamUniversityTechs[0].levels[TechChemistry] = 1
    env.teamUniversityTechs[0].levels[TechSiegeEngineers] = 1
    # Create a mangonel (siege unit) and apply unit class
    let attacker = addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitMangonel)
    applyUnitClass(attacker, UnitMangonel)
    # Create an enemy target
    let defender = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 9))
    defender.hp = 20
    defender.maxHp = 20

    # Attack
    env.stepAction(attacker.agentId, 2'u8, dirIndex(attacker.pos, defender.pos))

    # Base damage is 2, +1 Chemistry +1 Siege Engineers = 4 damage
    check defender.hp == 16

  test "non-siege units do not get siege engineers bonus":
    let env = makeEmptyEnv()
    # Research Siege Engineers tech
    env.teamUniversityTechs[0].levels[TechSiegeEngineers] = 1
    # Create an archer (not a siege unit) and apply unit class
    let attacker = addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitArcher)
    applyUnitClass(attacker, UnitArcher)
    # Create an enemy target
    let defender = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 8))
    defender.hp = 10
    defender.maxHp = 10

    # Attack
    env.stepAction(attacker.agentId, 2'u8, dirIndex(attacker.pos, defender.pos))

    # Base damage is 1, no siege bonus for archers
    check defender.hp == 9

  test "only villagers can research techs":
    let env = makeEmptyEnv()
    let university = addBuilding(env, University, ivec2(10, 9), 0)
    # Create a man-at-arms (not a villager) and apply unit class
    let agent = addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitManAtArms)
    applyUnitClass(agent, UnitManAtArms)
    setStockpile(env, 0, ResourceFood, 100)
    setStockpile(env, 0, ResourceGold, 100)

    env.stepAction(agent.agentId, 3'u8, dirIndex(agent.pos, university.pos))

    # No tech should have been researched
    var totalLevels = 0
    for techType in UniversityTechType:
      totalLevels += env.teamUniversityTechs[0].levels[techType]
    check totalLevels == 0

  test "teams have independent techs":
    let env = makeEmptyEnv()
    # Set up different tech levels for teams
    env.teamUniversityTechs[0].levels[TechChemistry] = 1
    env.teamUniversityTechs[1].levels[TechChemistry] = 0

    # Create two man-at-arms from different teams
    let attacker0 = addAgentAt(env, 0, ivec2(10, 10), unitClass = UnitManAtArms)
    applyUnitClass(attacker0, UnitManAtArms)
    let attacker1 = addAgentAt(env, MapAgentsPerTeam, ivec2(10, 9), unitClass = UnitManAtArms)
    applyUnitClass(attacker1, UnitManAtArms)
    attacker0.hp = 20
    attacker0.maxHp = 20
    attacker1.hp = 20
    attacker1.maxHp = 20

    # Team 0 attacks team 1: base 2 + 1 chemistry = 3, halved by ManAtArms aura = 2 damage
    env.stepAction(attacker0.agentId, 2'u8, dirIndex(attacker0.pos, attacker1.pos))
    check attacker1.hp == 18

    # Team 1 attacks team 0: base 2 + 0 chemistry = 2, halved by ManAtArms aura = 1 damage
    env.stepAction(attacker1.agentId, 2'u8, dirIndex(attacker1.pos, attacker0.pos))
    check attacker0.hp == 19

  test "hasUniversityTech helper function":
    let env = makeEmptyEnv()
    # Initially no techs researched
    check not env.hasUniversityTech(0, TechBallistics)
    check not env.hasUniversityTech(0, TechChemistry)

    # Research a tech
    env.teamUniversityTechs[0].levels[TechBallistics] = 1

    # Check helper returns correctly
    check env.hasUniversityTech(0, TechBallistics)
    check not env.hasUniversityTech(0, TechChemistry)
    # Other team should not have it
    check not env.hasUniversityTech(1, TechBallistics)
