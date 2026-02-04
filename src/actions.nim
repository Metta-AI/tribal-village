# This file is included by src/step.nim
type UnitAttackTint = object
  tint: TileColor
  duration: int8
  code: uint8

const UnitAttackTints: array[AgentUnitClass, UnitAttackTint] = [
  # UnitVillager
  UnitAttackTint(tint: TileColor(r: 0.95, g: 0.25, b: 0.20, intensity: 1.10),
    duration: 1'i8, code: ActionTintAttackVillager),
  # UnitManAtArms
  UnitAttackTint(tint: TileColor(r: 0.95, g: 0.55, b: 0.15, intensity: 1.10),
    duration: 2'i8, code: ActionTintAttackManAtArms),
  # UnitArcher
  UnitAttackTint(tint: TileColor(r: 0.95, g: 0.85, b: 0.20, intensity: 1.10),
    duration: 2'i8, code: ActionTintAttackArcher),
  # UnitScout
  UnitAttackTint(tint: TileColor(r: 0.30, g: 0.90, b: 0.30, intensity: 1.10),
    duration: 1'i8, code: ActionTintAttackScout),
  # UnitKnight
  UnitAttackTint(tint: TileColor(r: 0.20, g: 0.90, b: 0.85, intensity: 1.12),
    duration: 3'i8, code: ActionTintAttackKnight),
  # UnitMonk
  UnitAttackTint(tint: TileColor(r: 0.25, g: 0.55, b: 0.95, intensity: 1.12),
    duration: 2'i8, code: ActionTintAttackMonk),
  # UnitBatteringRam
  UnitAttackTint(tint: TileColor(r: 0.45, g: 0.35, b: 0.90, intensity: 1.12),
    duration: 3'i8, code: ActionTintAttackBatteringRam),
  # UnitMangonel
  UnitAttackTint(tint: TileColor(r: 0.75, g: 0.35, b: 0.95, intensity: 1.18),
    duration: 3'i8, code: ActionTintAttackMangonel),
  # UnitTrebuchet
  UnitAttackTint(tint: TileColor(r: 0.65, g: 0.20, b: 0.98, intensity: 1.22),
    duration: 4'i8, code: ActionTintAttackTrebuchet),
  # UnitGoblin
  UnitAttackTint(tint: TileColor(r: 0.35, g: 0.85, b: 0.35, intensity: 1.12),
    duration: 1'i8, code: ActionTintAttackVillager),
  # UnitBoat
  UnitAttackTint(tint: TileColor(r: 0.95, g: 0.35, b: 0.75, intensity: 1.12),
    duration: 2'i8, code: ActionTintAttackBoat),
  # UnitTradeCog (non-combat, uses villager tint as placeholder)
  UnitAttackTint(tint: TileColor(r: 0.95, g: 0.35, b: 0.75, intensity: 1.12),
    duration: 1'i8, code: ActionTintAttackVillager),
  # Castle unique units
  # UnitSamurai - Red/orange fast strike
  UnitAttackTint(tint: TileColor(r: 0.95, g: 0.40, b: 0.25, intensity: 1.15),
    duration: 2'i8, code: ActionTintAttackSamurai),
  # UnitLongbowman - Green/yellow archer tint
  UnitAttackTint(tint: TileColor(r: 0.70, g: 0.90, b: 0.25, intensity: 1.12),
    duration: 2'i8, code: ActionTintAttackLongbowman),
  # UnitCataphract - Gold/bronze heavy cavalry
  UnitAttackTint(tint: TileColor(r: 0.85, g: 0.70, b: 0.30, intensity: 1.15),
    duration: 3'i8, code: ActionTintAttackCataphract),
  # UnitWoadRaider - Blue/green celtic
  UnitAttackTint(tint: TileColor(r: 0.30, g: 0.60, b: 0.85, intensity: 1.12),
    duration: 2'i8, code: ActionTintAttackWoadRaider),
  # UnitTeutonicKnight - Steel gray heavy
  UnitAttackTint(tint: TileColor(r: 0.60, g: 0.65, b: 0.70, intensity: 1.18),
    duration: 3'i8, code: ActionTintAttackTeutonicKnight),
  # UnitHuskarl - Purple/blue nordic
  UnitAttackTint(tint: TileColor(r: 0.55, g: 0.40, b: 0.80, intensity: 1.12),
    duration: 2'i8, code: ActionTintAttackHuskarl),
  # UnitMameluke - Desert gold/tan
  UnitAttackTint(tint: TileColor(r: 0.90, g: 0.80, b: 0.50, intensity: 1.12),
    duration: 2'i8, code: ActionTintAttackMameluke),
  # UnitJanissary - Red/white ottoman
  UnitAttackTint(tint: TileColor(r: 0.90, g: 0.30, b: 0.35, intensity: 1.15),
    duration: 2'i8, code: ActionTintAttackJanissary),
  # UnitKing - Royal gold/purple regicide
  UnitAttackTint(tint: TileColor(r: 0.95, g: 0.80, b: 0.20, intensity: 1.20),
    duration: 3'i8, code: ActionTintAttackKing),
  # Unit upgrade tiers
  # UnitLongSwordsman - Orange infantry (like ManAtArms, stronger)
  UnitAttackTint(tint: TileColor(r: 0.95, g: 0.55, b: 0.15, intensity: 1.15),
    duration: 2'i8, code: ActionTintAttackLongSwordsman),
  # UnitChampion - Orange infantry (strongest)
  UnitAttackTint(tint: TileColor(r: 0.95, g: 0.55, b: 0.15, intensity: 1.20),
    duration: 2'i8, code: ActionTintAttackChampion),
  # UnitLightCavalry - Green cavalry (like Scout, stronger)
  UnitAttackTint(tint: TileColor(r: 0.30, g: 0.90, b: 0.30, intensity: 1.15),
    duration: 1'i8, code: ActionTintAttackLightCavalry),
  # UnitHussar - Green cavalry (strongest)
  UnitAttackTint(tint: TileColor(r: 0.30, g: 0.90, b: 0.30, intensity: 1.20),
    duration: 1'i8, code: ActionTintAttackHussar),
  # UnitCrossbowman - Yellow archer (like Archer, stronger)
  UnitAttackTint(tint: TileColor(r: 0.95, g: 0.85, b: 0.20, intensity: 1.15),
    duration: 2'i8, code: ActionTintAttackCrossbowman),
  # UnitArbalester - Yellow archer (strongest)
  UnitAttackTint(tint: TileColor(r: 0.95, g: 0.85, b: 0.20, intensity: 1.20),
    duration: 2'i8, code: ActionTintAttackArbalester),
  # Naval combat units
  # UnitGalley - Blue naval ranged
  UnitAttackTint(tint: TileColor(r: 0.30, g: 0.50, b: 0.95, intensity: 1.15),
    duration: 2'i8, code: ActionTintAttackGalley),
  # UnitFireShip - Orange/red fire ship
  UnitAttackTint(tint: TileColor(r: 1.00, g: 0.50, b: 0.20, intensity: 1.25),
    duration: 3'i8, code: ActionTintAttackFireShip),
  # Additional siege unit
  # UnitScorpion - Cyan/purple bolt thrower
  UnitAttackTint(tint: TileColor(r: 0.60, g: 0.50, b: 0.90, intensity: 1.18),
    duration: 3'i8, code: ActionTintAttackScorpion),
]

proc applyUnitAttackTint(env: Environment, unit: AgentUnitClass, pos: IVec2) {.inline.} =
  let entry = UnitAttackTints[unit]
  env.applyActionTint(pos, entry.tint, entry.duration, entry.code)
