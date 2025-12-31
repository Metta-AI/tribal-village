import vmath, terrain

export terrain.Structure

proc createSpawner*(): Structure =
  result.width = 3
  result.height = 3
  result.centerPos = ivec2(1, 1)
