## constants.nim - Centralized game balance constants for tribal-village
##
## All gameplay-tunable numeric constants live here: damage values, HP, ranges,
## timings, costs, radii, and probabilities. This is the single source of truth
## for game balance tuning.
##
## Import order: This module has NO dependencies on other game modules.
## types.nim imports and re-exports this module.

const
  # ============================================================================
  # Agent Base Stats
  # ============================================================================
  AgentMaxHp* = 5

  # ============================================================================
  # Building HP
  # ============================================================================
  WallMaxHp* = 10
  OutpostMaxHp* = 8
  GuardTowerMaxHp* = 14
  TownCenterMaxHp* = 20
  CastleMaxHp* = 30
  MonasteryMaxHp* = 12
  WonderMaxHp* = 80
  DoorMaxHearts* = 5

  # ============================================================================
  # Building Attack
  # ============================================================================
  GuardTowerAttackDamage* = 2
  CastleAttackDamage* = 3
  TownCenterAttackDamage* = 2
  GuardTowerRange* = 4
  CastleRange* = 6
  TownCenterRange* = 6

  # ============================================================================
  # Building Garrison (AoE2-style)
  # ============================================================================
  TownCenterGarrisonCapacity* = 15
  CastleGarrisonCapacity* = 20
  GuardTowerGarrisonCapacity* = 5
  HouseGarrisonCapacity* = 5
  GarrisonArrowBonus* = 1

  # ============================================================================
  # Siege
  # ============================================================================
  SiegeStructureMultiplier* = 3

  # ============================================================================
  # Construction
  # ============================================================================
  ConstructionBonusTable* = [1.0'f32, 1.0, 1.5, 1.83, 2.08, 2.28, 2.45, 2.59, 2.72]
  ConstructionHpPerAction* = 1
  RoadWoodCost* = 1
  OutpostWoodCost* = 1

  # ============================================================================
  # Resource & Economy
  # ============================================================================
  ResourceCarryCapacity* = 5
  MineDepositAmount* = 100
  BarrelCapacity* = 50
  ResourceNodeInitial* = 25
  TownCenterPopCap* = 0
  HousePopCap* = 4

  # ============================================================================
  # Wildlife Stats
  # ============================================================================
  CowMilkCooldown* = 25
  BearMaxHp* = 6
  BearAttackDamage* = 2
  BearAggroRadius* = 6
  WolfMaxHp* = 3
  WolfAttackDamage* = 1
  WolfPackMinSize* = 3
  WolfPackMaxSize* = 5
  WolfPackAggroRadius* = 7
  WolfPackCohesionRadius* = 3
  ScatteredDuration* = 10

  # Wildlife movement probabilities
  CowHerdFollowChance* = 0.6
  CowRandomMoveChance* = 0.08
  WolfPackFollowChance* = 0.55
  WolfRandomMoveChance* = 0.1
  WolfScatteredMoveChance* = 0.4
  BearRandomMoveChance* = 0.12

  # ============================================================================
  # Villager & Gatherer
  # ============================================================================
  VillagerAttackDamage* = 1
  GathererFleeRadius* = 8  # Radius at which gatherers flee from predators
  EarlyGameThreshold* = 0.33  # First third of game
  LateGameThreshold* = 0.66   # Last third of game
  TaskSwitchHysteresis* = 5.0

  # ============================================================================
  # Military Unit Stats
  # ============================================================================
  # Man-at-Arms
  ManAtArmsAttackDamage* = 2
  ManAtArmsMaxHp* = 7

  # Archer
  ArcherAttackDamage* = 1
  ArcherMaxHp* = 4
  ArcherBaseRange* = 3

  # Scout
  ScoutAttackDamage* = 1
  ScoutMaxHp* = 6

  # Knight
  KnightAttackDamage* = 2
  KnightMaxHp* = 8

  # Monk
  MonkAttackDamage* = 0
  MonkMaxHp* = 4

  # Siege Units
  BatteringRamAttackDamage* = 2
  BatteringRamMaxHp* = 18
  MangonelAttackDamage* = 2
  MangonelMaxHp* = 12
  MangonelBaseRange* = 3
  MangonelAoELength* = 5
  TrebuchetAttackDamage* = 3
  TrebuchetMaxHp* = 14
  TrebuchetBaseRange* = 6
  TrebuchetPackDuration* = 15

  # Goblin
  GoblinAttackDamage* = 1
  GoblinMaxHp* = 4

  # Trade Cog
  TradeCogAttackDamage* = 0
  TradeCogMaxHp* = 6
  TradeCogGoldPerDistance* = 1
  TradeCogDistanceDivisor* = 10

  # ============================================================================
  # Castle Unique Unit Stats
  # ============================================================================
  SamuraiMaxHp* = 7
  SamuraiAttackDamage* = 3
  LongbowmanMaxHp* = 5
  LongbowmanAttackDamage* = 2
  CataphractMaxHp* = 10
  CataphractAttackDamage* = 2
  WoadRaiderMaxHp* = 6
  WoadRaiderAttackDamage* = 2
  TeutonicKnightMaxHp* = 12
  TeutonicKnightAttackDamage* = 3
  HuskarlMaxHp* = 8
  HuskarlAttackDamage* = 2
  MamelukeMaxHp* = 7
  MamelukeAttackDamage* = 2
  JanissaryMaxHp* = 6
  JanissaryAttackDamage* = 3
  KingMaxHp* = 15
  KingAttackDamage* = 2

  # ============================================================================
  # Unit Upgrade Tiers (AoE2-style promotion chains)
  # ============================================================================
  LongSwordsmanMaxHp* = 9
  LongSwordsmanAttackDamage* = 3
  ChampionMaxHp* = 11
  ChampionAttackDamage* = 4
  LightCavalryMaxHp* = 8
  LightCavalryAttackDamage* = 2
  HussarMaxHp* = 10
  HussarAttackDamage* = 2
  CrossbowmanMaxHp* = 5
  CrossbowmanAttackDamage* = 2
  ArbalesterMaxHp* = 6
  ArbalesterAttackDamage* = 3

  # ============================================================================
  # Naval Combat Units
  # ============================================================================
  GalleyMaxHp* = 8
  GalleyAttackDamage* = 2
  GalleyBaseRange* = 3
  FireShipMaxHp* = 6
  FireShipAttackDamage* = 3

  # ============================================================================
  # Additional Siege Units
  # ============================================================================
  ScorpionMaxHp* = 8
  ScorpionAttackDamage* = 2
  ScorpionBaseRange* = 4

  # ============================================================================
  # Monk Mechanics (AoE2-style)
  # ============================================================================
  MonkMaxFaith* = 10
  MonkConversionFaithCost* = 10
  MonkFaithRechargeRate* = 1
  MonasteryRelicGoldInterval* = 20
  MonasteryRelicGoldAmount* = 1

  # ============================================================================
  # Tech Costs
  # ============================================================================
  # Blacksmith upgrades
  BlacksmithUpgradeMaxLevel* = 3
  BlacksmithUpgradeFoodCost* = 3
  BlacksmithUpgradeGoldCost* = 2

  # University techs
  UniversityTechFoodCost* = 5
  UniversityTechGoldCost* = 3
  UniversityTechWoodCost* = 2

  # Castle unique techs
  CastleTechFoodCost* = 4
  CastleTechGoldCost* = 3
  CastleTechImperialFoodCost* = 8
  CastleTechImperialGoldCost* = 6

  # Unit upgrade costs
  UnitUpgradeTier2FoodCost* = 3
  UnitUpgradeTier2GoldCost* = 2
  UnitUpgradeTier3FoodCost* = 6
  UnitUpgradeTier3GoldCost* = 4

  # Economy techs (AoE2-style)
  # Town Center techs
  WheelbarrowFoodCost* = 4
  WheelbarrowWoodCost* = 2
  WheelbarrowCarryBonus* = 3
  WheelbarrowSpeedBonus* = 10  # +10% speed
  HandCartFoodCost* = 6
  HandCartWoodCost* = 3
  HandCartCarryBonus* = 7
  HandCartSpeedBonus* = 10  # +10% speed (stacks)

  # Lumber Camp techs
  DoubleBitAxeFoodCost* = 2
  DoubleBitAxeWoodCost* = 1
  DoubleBitAxeGatherBonus* = 20  # +20%
  BowSawFoodCost* = 3
  BowSawWoodCost* = 2
  BowSawGatherBonus* = 20  # +20% (stacks)
  TwoManSawFoodCost* = 4
  TwoManSawWoodCost* = 2
  TwoManSawGatherBonus* = 10  # +10% (stacks)

  # Mining Camp techs
  GoldMiningFoodCost* = 2
  GoldMiningWoodCost* = 1
  GoldMiningGatherBonus* = 15  # +15%
  GoldShaftMiningFoodCost* = 3
  GoldShaftMiningWoodCost* = 2
  GoldShaftMiningGatherBonus* = 15  # +15% (stacks)
  StoneMiningFoodCost* = 2
  StoneMiningWoodCost* = 1
  StoneMiningGatherBonus* = 15  # +15%
  StoneShaftMiningFoodCost* = 3
  StoneShaftMiningWoodCost* = 2
  StoneShaftMiningGatherBonus* = 15  # +15% (stacks)

  # Mill techs
  HorseCollarFoodCost* = 3
  HorseCollarWoodCost* = 2
  HorseCollarFarmBonus* = 75  # +75 farm food
  HeavyPlowFoodCost* = 4
  HeavyPlowWoodCost* = 2
  HeavyPlowFarmBonus* = 125  # +125 farm food (stacks)
  CropRotationFoodCost* = 5
  CropRotationWoodCost* = 3
  CropRotationFarmBonus* = 175  # +175 farm food (stacks)

  # Farm auto-reseed cost
  FarmReseedWoodCost* = 1
  FarmReseedFoodCost* = 0

  # ============================================================================
  # Blacksmith Upgrade Bonuses
  # ============================================================================
  BlacksmithMeleeAttackBonus*: array[4, int] = [0, 1, 2, 4]
  BlacksmithArcherAttackBonus*: array[4, int] = [0, 1, 2, 3]
  BlacksmithInfantryArmorBonus*: array[4, int] = [0, 1, 2, 4]
  BlacksmithCavalryArmorBonus*: array[4, int] = [0, 1, 2, 4]
  BlacksmithArcherArmorBonus*: array[4, int] = [0, 1, 2, 4]

  BlacksmithMeleeAttackNames*: array[3, string] = ["Forging", "Iron Casting", "Blast Furnace"]
  BlacksmithArcherAttackNames*: array[3, string] = ["Fletching", "Bodkin Arrow", "Bracer"]
  BlacksmithInfantryArmorNames*: array[3, string] = ["Scale Mail", "Chain Mail", "Plate Mail"]
  BlacksmithCavalryArmorNames*: array[3, string] = ["Scale Barding", "Chain Barding", "Plate Barding"]
  BlacksmithArcherArmorNames*: array[3, string] = ["Padded Archer", "Leather Archer", "Ring Archer"]

  # ============================================================================
  # Production Queue (AoE2-style)
  # ============================================================================
  ProductionQueueMaxSize* = 10
  ProductionTrainDuration* = 5
  BatchTrainSmall* = 5
  BatchTrainLarge* = 10

  # ============================================================================
  # Victory Conditions
  # ============================================================================
  WonderVictoryCountdown* = 600
  RelicVictoryCountdown* = 200
  VictoryReward* = 10.0'f32
  HillControlRadius* = 5
  HillVictoryCountdown* = 300

  # ============================================================================
  # Attack Tint Durations
  # ============================================================================
  TowerAttackTintDuration* = 2'i8
  CastleAttackTintDuration* = 3'i8
  TownCenterAttackTintDuration* = 2'i8
  TankAuraTintDuration* = 1'i8
  MonkAuraTintDuration* = 1'i8
  DeathTintDuration* = 3'i8           # Death animation tint duration (steps)

  # ============================================================================
  # Aura Radii
  # ============================================================================
  ManAtArmsAuraRadius* = 1
  KnightAuraRadius* = 2
  MonkAuraRadius* = 2

  # ============================================================================
  # Mill & Spawner
  # ============================================================================
  MillFertileCooldown* = 10
  MaxTumorsPerSpawner* = 3
  TumorSpawnCooldownBase* = 20.0
  TumorSpawnDisabledCooldown* = 1000

  # ============================================================================
  # Temple Cooldowns
  # ============================================================================
  TempleInteractionCooldown* = 12
  TempleHybridCooldown* = 25

  # ============================================================================
  # Combat AI Constants
  # ============================================================================
  # Target evaluation
  TargetSwapInterval* = 25     # Re-evaluate target every N ticks (perf: reduced from 10)
  LowHpThreshold* = 0.33      # Enemies below this HP ratio get priority
  AllyThreatRadius* = 2       # Distance at which enemy is considered threatening an ally
  EscortRadius* = 3           # Stay within this distance of the protected unit
  HoldPositionReturnRadius* = 3  # Max distance to drift from hold position
  FollowProximityRadius* = 3  # Stay within this distance of followed target

  # Divider wall building
  DividerDoorSpacing* = 5
  DividerDoorOffset* = 0
  DividerHalfLengthMin* = 6
  DividerHalfLengthMax* = 18

  # Healing
  HealerSeekRadius* = 30      # Max distance to search for friendly monks
  MonkHealRadius* = 2         # Distance to stay near monk for healing (matches MonkAuraRadius)

  # Kiting and siege detection
  KiteTriggerDistance* = 3    # Distance at which kiting triggers
  AntiSiegeDetectionRadius* = 12  # Distance to detect enemy siege units
  SiegeNearStructureRadius* = 5   # Siege units this close to structures get priority

  # Attack move
  AttackMoveDetectionRadius* = 8  # Distance to detect enemies while attack-moving
  FormationArrivalThreshold* = 1  # Distance at which formation slot is reached

  # Ranged formation
  RangedFormationSpacing* = 3     # Wider spacing for ranged units to avoid friendly fire
  RangedFormationRowOffset* = 2   # Offset between rows in ranged formation

  # Scout behavior
  ScoutFleeRadius* = 10       # Distance at which scouts flee from enemies
  ScoutFleeRecoverySteps* = 30  # Steps after enemy sighting before resuming
  ScoutExploreGrowth* = 3     # How much to expand explore radius each cycle

  # ============================================================================
  # Wall Ring (Builder AI)
  # ============================================================================
  WallRingBaseRadius* = 5
  WallRingMaxRadius* = 12
  WallRingBuildingsPerRadius* = 4
  WallRingRadiusSlack* = 1
  WallRingMaxDoors* = 2

  # ============================================================================
  # Fortification
  # ============================================================================
  EnemyWallFortifyRadius* = 12

  # ============================================================================
  # AI Threat & Vision
  # ============================================================================
  ThreatVisionRange* = 12     # Range to detect threats
  ScoutVisionRange* = 18      # Scout extended vision range (50% larger than normal)
  ThreatDecaySteps* = 50      # Steps before threat decays
  ThreatUpdateStagger* = 4    # Only update threat map every N steps per agent

  # ============================================================================
  # Shadow Casting
  # ============================================================================
  # Light direction determines shadow offset (opposite to light source)
  # Using NW light source, so shadows cast to SE (positive X and Y)
  ShadowOffsetX* = 0.15'f32      # Shadow offset in X direction (positive = east)
  ShadowOffsetY* = 0.15'f32      # Shadow offset in Y direction (positive = south)
  ShadowAlpha* = 0.35'f32        # Shadow transparency (0.0 = invisible, 1.0 = opaque)

  # ============================================================================
  # Town Splitting (multi-altar expansion)
  # ============================================================================
  TownSplitPopulationThreshold* = 25   ## Villager count near altar that triggers split
  TownSplitSettlerCount* = 10          ## Number of villagers in settler party
  TownSplitMinDistance* = 18           ## Minimum distance for new town from original altar
  TownSplitMaxDistance* = 25           ## Maximum distance for new town from original altar
  TownSplitNewAltarRadius* = 2        ## Max distance of new altar from new town center

  # Derived constants
  VillagerMaxHp* = AgentMaxHp
