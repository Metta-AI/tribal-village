# This file is included by src/step.nim
const UnitAttackTints: array[AgentUnitClass, tuple[tint: TileColor, duration: int8, code: uint8]] = [
  # UnitVillager
  (TileColor(r: 0.95, g: 0.25, b: 0.20, intensity: 1.10), 1'i8, ActionTintAttackVillager),
  # UnitManAtArms
  (TileColor(r: 0.95, g: 0.55, b: 0.15, intensity: 1.10), 2'i8, ActionTintAttackManAtArms),
  # UnitArcher
  (TileColor(r: 0.95, g: 0.85, b: 0.20, intensity: 1.10), 2'i8, ActionTintAttackArcher),
  # UnitScout
  (TileColor(r: 0.30, g: 0.90, b: 0.30, intensity: 1.10), 1'i8, ActionTintAttackScout),
  # UnitKnight
  (TileColor(r: 0.20, g: 0.90, b: 0.85, intensity: 1.12), 3'i8, ActionTintAttackKnight),
  # UnitMonk
  (TileColor(r: 0.25, g: 0.55, b: 0.95, intensity: 1.12), 2'i8, ActionTintAttackMonk),
  # UnitBatteringRam
  (TileColor(r: 0.45, g: 0.35, b: 0.90, intensity: 1.12), 3'i8, ActionTintAttackBatteringRam),
  # UnitMangonel
  (TileColor(r: 0.75, g: 0.35, b: 0.95, intensity: 1.18), 3'i8, ActionTintAttackMangonel),
  # UnitGoblin
  (TileColor(r: 0.35, g: 0.85, b: 0.35, intensity: 1.12), 1'i8, ActionTintAttackVillager),
  # UnitBoat
  (TileColor(r: 0.95, g: 0.35, b: 0.75, intensity: 1.12), 2'i8, ActionTintAttackBoat),
]

proc applyUnitAttackTint(env: Environment, unit: AgentUnitClass, pos: IVec2) {.inline.} =
  let tintDef = UnitAttackTints[unit]
  env.applyActionTint(pos, tintDef.tint, tintDef.duration, tintDef.code)
