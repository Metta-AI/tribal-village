import std/[algorithm, strutils, tables], vmath, chroma
import entropy
import terrain, objects, workshop, items, common, biome
export terrain, objects, workshop, items, common

include "types"
include "registry"
include "colors"
include "ascii"
include "observe"
include "grid"
include "inventory"

# Build craft recipes after registry is available.
CraftRecipes = initCraftRecipesBase()
appendBuildingRecipes(CraftRecipes)

include "actions"
include "connect"
include "spawn"
include "step"
