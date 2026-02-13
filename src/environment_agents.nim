## environment_agents.nim - Agent lifecycle operations for Environment
##
## This module provides re-exports for agent lifecycle types and procedures.
## The actual implementations remain in environment.nim due to complex interdependencies.
## This module exists for organizational clarity and future refactoring.
##
## Key types and procs exported from environment.nim:
## - defaultStanceForClass: Returns default stance for a unit class
## - UnitCategory: Enum for Blacksmith upgrade categories
## - UnitCategoryByClass: Lookup table for unit categories
## - getUnitCategory: Get upgrade category for a unit
## - setRallyPoint, clearRallyPoint, hasRallyPoint: Rally point management

import vmath
import types

export types
export vmath
