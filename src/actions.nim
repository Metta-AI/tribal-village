# This file is included by src/environment.nim
proc noopAction(env: Environment, id: int, agent: Thing) =
  inc env.stats[id].actionNoop

proc add(env: Environment, thing: Thing)
proc removeThing(env: Environment, thing: Thing)
proc updateTumorInfluence*(env: Environment, pos: IVec2, intensityDelta: int)
proc tryCraftAtStation(env: Environment, agent: Thing, station: CraftStation, stationThing: Thing): bool
proc tryTrainUnit(env: Environment, agent: Thing, building: Thing, unitClass: AgentUnitClass,
                  costs: openArray[tuple[res: StockpileResource, count: int]], cooldown: int): bool
proc useDropoffBuilding(env: Environment, agent: Thing, allowed: set[StockpileResource]): bool
proc useStorageBuilding(env: Environment, agent: Thing, storage: Thing, allowed: openArray[ItemKey]): bool

include "carry"
include "craft"
include "place"
include "move"
include "combat"
include "use"
include "give"
include "search"
include "tint"
include "build"
include "plant"
