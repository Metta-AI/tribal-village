## balance.nim - Consolidated game balance and tuning constants
##
## This module centralizes balance-related constants for easier tuning
## and experimentation.

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
