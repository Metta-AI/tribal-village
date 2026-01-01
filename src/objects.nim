import vmath, terrain

export terrain.Structure

proc createSpawner*(): Structure =
  Structure(width: 3, height: 3, centerPos: ivec2(1, 1))
