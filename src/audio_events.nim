## audio_events.nim - Game event to audio mapping
##
## Bridges game events to audio playback. Call these procs from game logic
## where events occur (combat, deaths, building, etc.).
##
## This module provides high-level audio triggers that internally select
## appropriate sounds based on unit type, action, and context.

when defined(audio):
  import audio
  import types
  import vmath

  # Unit class to voice mapping
  proc getUnitVoiceCategory*(unitClass: AgentUnitClass): string =
    ## Map unit class to voice category
    case unitClass
    of UnitVillager:
      "villager"
    of UnitMonk:
      "monk"
    of UnitKnight, UnitCataphract, UnitScout, UnitLightCavalry, UnitHussar, UnitMameluke:
      "cavalry"
    of UnitArcher, UnitCrossbowman, UnitArbalester, UnitLongbowman, UnitJanissary:
      "archer"
    of UnitBatteringRam, UnitMangonel, UnitTrebuchet, UnitScorpion:
      "siege"
    of UnitBoat, UnitTradeCog, UnitGalley, UnitFireShip:
      "naval"
    else:
      "soldier"

  proc isRangedUnit*(unitClass: AgentUnitClass): bool =
    ## Check if unit class uses ranged attacks
    unitClass in {UnitArcher, UnitCrossbowman, UnitArbalester, UnitLongbowman,
                  UnitJanissary, UnitMangonel, UnitTrebuchet, UnitScorpion,
                  UnitGalley}

  proc isCavalryUnit*(unitClass: AgentUnitClass): bool =
    ## Check if unit class is cavalry (for death sounds)
    unitClass in {UnitKnight, UnitCataphract, UnitScout, UnitLightCavalry,
                  UnitHussar, UnitMameluke}

  proc isSiegeUnit*(unitClass: AgentUnitClass): bool =
    ## Check if unit class is siege
    unitClass in {UnitBatteringRam, UnitMangonel, UnitTrebuchet, UnitScorpion}

  # Combat audio triggers

  proc audioOnAttack*(attackerClass: AgentUnitClass, pos: IVec2) =
    ## Called when a unit attacks
    if isRangedUnit(attackerClass):
      playCombatSound(SndArrowShoot, pos, 0.7)
    elif isSiegeUnit(attackerClass):
      playCombatSound(SndSiegeAttack, pos, 1.0)
    else:
      playCombatSound(SndSwordHit, pos, 0.8)

  proc audioOnHit*(targetClass: AgentUnitClass, pos: IVec2, damage: int) =
    ## Called when a unit takes damage
    # Scale volume slightly by damage
    let vol = clamp(0.5 + (damage.float32 / 50.0), 0.5, 1.0)
    if isRangedUnit(targetClass):
      playCombatSound(SndArrowHit, pos, vol * 0.8)
    else:
      playCombatSound(SndSwordHit, pos, vol)

  proc audioOnDeath*(unitClass: AgentUnitClass, pos: IVec2) =
    ## Called when a unit dies
    if isCavalryUnit(unitClass):
      playDeathSound(SndDeathHorse, pos)
    elif isSiegeUnit(unitClass):
      playDeathSound(SndDeathBuilding, pos)
    else:
      playDeathSound(SndDeathMale, pos)

  proc audioOnConversion*(pos: IVec2) =
    ## Called when a monk converts a unit
    playCombatSound(SndMonkConvert, pos, 1.0)

  # Building audio triggers

  proc audioOnBuildingStart*(pos: IVec2) =
    ## Called when building construction starts
    playBuildingSound(SndBuildStart, pos)

  proc audioOnBuildingProgress*(pos: IVec2) =
    ## Called during building construction (periodic)
    playBuildingSound(SndBuildHammer, pos)

  proc audioOnBuildingComplete*(pos: IVec2) =
    ## Called when building construction completes
    playBuildingSound(SndBuildComplete, pos)

  proc audioOnBuildingDestroyed*(pos: IVec2) =
    ## Called when a building is destroyed
    playDeathSound(SndBuildDestroy, pos)

  # Resource gathering audio triggers

  proc audioOnGatherWood*(pos: IVec2) =
    ## Called when gathering wood
    playResourceSound(SndChopWood, pos)

  proc audioOnGatherStone*(pos: IVec2) =
    ## Called when mining stone
    playResourceSound(SndMineStone, pos)

  proc audioOnGatherGold*(pos: IVec2) =
    ## Called when mining gold
    playResourceSound(SndMineGold, pos)

  proc audioOnGatherFood*(pos: IVec2, fromFarm: bool) =
    ## Called when gathering food
    if fromFarm:
      playResourceSound(SndFarmHarvest, pos)
    else:
      playResourceSound(SndFishCatch, pos)

  # Unit selection and command audio

  proc audioOnUnitSelected*(unitClass: AgentUnitClass) =
    ## Called when unit(s) are selected
    let category = getUnitVoiceCategory(unitClass)
    case category
    of "villager":
      playUnitVoice(SndVillagerWhat)
    of "monk":
      playUnitVoice(SndMonkYes)
    else:
      playUnitVoice(SndSoldierWhat)

  proc audioOnUnitCommand*(unitClass: AgentUnitClass) =
    ## Called when unit(s) receive a command (move, attack, etc.)
    let category = getUnitVoiceCategory(unitClass)
    case category
    of "villager":
      playUnitVoice(SndVillagerYes)
    of "monk":
      playUnitVoice(SndMonkYes)
    else:
      playUnitVoice(SndSoldierYes)

  # Research and tech audio

  proc audioOnResearchComplete*() =
    ## Called when research/tech completes
    playUISound(SndUIResearchComplete)

  # UI audio

  proc audioOnUIClick*() =
    ## Called on UI button clicks
    playUISound(SndUIClick)

  proc audioOnAlert*() =
    ## Called for important alerts
    playUISound(SndUIAlert)

  # Ambient audio based on biome

  proc updateAmbientForBiome*(biome: string) =
    ## Update ambient sound based on current biome
    setAmbientBiome(biome)

  proc updateAmbientForCombat*(inCombat: bool) =
    ## Overlay combat ambient when battle is happening nearby
    if inCombat:
      setAmbientBiome("battle")

# Stub implementations when audio is disabled
else:
  import types
  import vmath

  proc audioOnAttack*(attackerClass: AgentUnitClass, pos: IVec2) = discard
  proc audioOnHit*(targetClass: AgentUnitClass, pos: IVec2, damage: int) = discard
  proc audioOnDeath*(unitClass: AgentUnitClass, pos: IVec2) = discard
  proc audioOnConversion*(pos: IVec2) = discard
  proc audioOnBuildingStart*(pos: IVec2) = discard
  proc audioOnBuildingProgress*(pos: IVec2) = discard
  proc audioOnBuildingComplete*(pos: IVec2) = discard
  proc audioOnBuildingDestroyed*(pos: IVec2) = discard
  proc audioOnGatherWood*(pos: IVec2) = discard
  proc audioOnGatherStone*(pos: IVec2) = discard
  proc audioOnGatherGold*(pos: IVec2) = discard
  proc audioOnGatherFood*(pos: IVec2, fromFarm: bool) = discard
  proc audioOnUnitSelected*(unitClass: AgentUnitClass) = discard
  proc audioOnUnitCommand*(unitClass: AgentUnitClass) = discard
  proc audioOnResearchComplete*() = discard
  proc audioOnUIClick*() = discard
  proc audioOnAlert*() = discard
  proc updateAmbientForBiome*(biome: string) = discard
  proc updateAmbientForCombat*(inCombat: bool) = discard
