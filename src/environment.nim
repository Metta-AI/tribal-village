import std/[algorithm, strutils, tables, sets], vmath, chroma
import entropy
import terrain, items, common, biome
export terrain, items, common

include "types"
include "registry"
include "colors"
include "observe"
include "grid"
include "inventory"

# Build craft recipes after registry is available.
CraftRecipes = initCraftRecipesBase()
appendBuildingRecipes(CraftRecipes)

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

include "connect"
include "spawn"
include "step"

proc render*(env: Environment): string =
  for y in 0 ..< MapHeight:
    for x in 0 ..< MapWidth:
      var cell = " "
      # First check terrain
      cell = $TerrainCatalog[env.terrain[x][y]].ascii
      # Then override with objects if present
      for thing in env.things:
        if thing.pos.x == x and thing.pos.y == y:
          let kind = thing.kind
          if isBuildingKind(kind):
            cell = $BuildingRegistry[kind].ascii
          else:
            cell = $ThingCatalog[kind].ascii
          break
      result.add(cell)
    result.add("\n")
