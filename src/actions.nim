# This file is included by src/step.nim
const UnitAttackTints: array[AgentUnitClass, TileColor] = [
  # UnitVillager
  TileColor(r: 0.95, g: 0.25, b: 0.20, intensity: 1.10),
  # UnitManAtArms
  TileColor(r: 0.95, g: 0.55, b: 0.15, intensity: 1.10),
  # UnitArcher
  TileColor(r: 0.95, g: 0.85, b: 0.20, intensity: 1.10),
  # UnitScout
  TileColor(r: 0.30, g: 0.90, b: 0.30, intensity: 1.10),
  # UnitKnight
  TileColor(r: 0.20, g: 0.90, b: 0.85, intensity: 1.12),
  # UnitMonk
  TileColor(r: 0.25, g: 0.55, b: 0.95, intensity: 1.12),
  # UnitBatteringRam
  TileColor(r: 0.45, g: 0.35, b: 0.90, intensity: 1.12),
  # UnitMangonel
  TileColor(r: 0.75, g: 0.35, b: 0.95, intensity: 1.18),
  # UnitGoblin
  TileColor(r: 0.35, g: 0.85, b: 0.35, intensity: 1.12),
  # UnitBoat
  TileColor(r: 0.95, g: 0.35, b: 0.75, intensity: 1.12),
]

const UnitAttackObservationCodes: array[AgentUnitClass, uint8] = [
  ActionTintAttackVillager,
  ActionTintAttackManAtArms,
  ActionTintAttackArcher,
  ActionTintAttackScout,
  ActionTintAttackKnight,
  ActionTintAttackMonk,
  ActionTintAttackBatteringRam,
  ActionTintAttackMangonel,
  ActionTintAttackVillager,
  ActionTintAttackBoat,
]

const UnitAttackTintDurations: array[AgentUnitClass, int8] = [
  1'i8, # UnitVillager
  2'i8, # UnitManAtArms
  2'i8, # UnitArcher
  1'i8, # UnitScout
  3'i8, # UnitKnight
  2'i8, # UnitMonk
  3'i8, # UnitBatteringRam
  3'i8, # UnitMangonel
  1'i8, # UnitGoblin
  2'i8, # UnitBoat
]

proc applyUnitAttackTint(env: Environment, unit: AgentUnitClass, pos: IVec2) {.inline.} =
  env.applyActionTint(pos, UnitAttackTints[unit], UnitAttackTintDurations[unit], UnitAttackObservationCodes[unit])
