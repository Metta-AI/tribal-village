## balance.nim - Consolidated game balance and tuning constants
##
## This module centralizes scattered constants for easier tuning and experimentation.
## All balance-related values that affect gameplay should be defined here.

type
  TumorConfig* = object
    ## Configuration for tumor/creep behavior
    branchRange*: int           ## Max distance a tumor can branch to
    branchMinAge*: int          ## Minimum turns alive before branching
    branchChance*: float        ## Probability of branching per turn (0.0 to 1.0)
    adjacencyDeathChance*: float ## Chance of death when adjacent to another tumor

  VillageConfig* = object
    ## Configuration for village spawning and layout
    minSpacing*: int            ## Minimum Chebyshev distance between village centers
    spawnerMinDistance*: int    ## Minimum distance from spawners to villages
    initialActiveAgents*: int   ## Number of agents active at game start (per village)

  CombatConfig* = object
    ## Configuration for combat mechanics
    spearCharges*: int          ## Number of uses per crafted spear
    armorPoints*: int           ## Durability per crafted armor
    breadHealAmount*: int       ## HP healed per bread consumption

  BalanceConfig* = object
    ## Top-level container for all balance configurations
    tumor*: TumorConfig
    village*: VillageConfig
    combat*: CombatConfig

const
  ## Default tumor behavior constants
  DefaultTumorBranchRange* = 5
  DefaultTumorBranchMinAge* = 2
  DefaultTumorBranchChance* = 0.1
  DefaultTumorAdjacencyDeathChance* = 1.0 / 3.0

  ## Default village spacing constants
  DefaultMinVillageSpacing* = 22
  DefaultSpawnerMinDistance* = 20
  DefaultInitialActiveAgents* = 6

  ## Default combat constants
  DefaultSpearCharges* = 5
  DefaultArmorPoints* = 5
  DefaultBreadHealAmount* = 999

proc defaultTumorConfig*(): TumorConfig =
  TumorConfig(
    branchRange: DefaultTumorBranchRange,
    branchMinAge: DefaultTumorBranchMinAge,
    branchChance: DefaultTumorBranchChance,
    adjacencyDeathChance: DefaultTumorAdjacencyDeathChance
  )

proc defaultVillageConfig*(): VillageConfig =
  VillageConfig(
    minSpacing: DefaultMinVillageSpacing,
    spawnerMinDistance: DefaultSpawnerMinDistance,
    initialActiveAgents: DefaultInitialActiveAgents
  )

proc defaultCombatConfig*(): CombatConfig =
  CombatConfig(
    spearCharges: DefaultSpearCharges,
    armorPoints: DefaultArmorPoints,
    breadHealAmount: DefaultBreadHealAmount
  )

proc defaultBalanceConfig*(): BalanceConfig =
  BalanceConfig(
    tumor: defaultTumorConfig(),
    village: defaultVillageConfig(),
    combat: defaultCombatConfig()
  )
