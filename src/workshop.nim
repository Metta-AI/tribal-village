import vmath, terrain

export terrain.Structure

const
  WorkshopWallChar* = '#'
  WorkshopFloorChar* = '.'
  WorkshopDoorChar* = 'D'
  WorkshopAltarChar* = 'a'
  WorkshopArmoryChar* = 'A'
  WorkshopForgeChar* = 'F'
  WorkshopClayOvenChar* = 'C'
  WorkshopWeavingLoomChar* = 'W'

proc createVillage*(): Structure =
  ## Village layout with enclosed walls, interior workshops, and door gaps.
  result.width = 11
  result.height = 11
  result.centerPos = ivec2(5, 5)

  result.layout = @[
    @['#', '#', '#', '#', '#', 'D', '#', '#', '#', '#', '#'],
    @['#', 'A', '.', '.', '.', '.', '.', '.', '.', 'F', '#'],
    @['#', '.', '.', '.', '.', '.', '.', '.', '.', '.', '#'],
    @['#', '.', '.', '.', '.', '.', '.', '.', '.', '.', '#'],
    @['#', '.', '.', '.', '.', '.', '.', '.', '.', '.', '#'],
    @['D', '.', '.', '.', '.', 'a', '.', '.', '.', '.', 'D'],
    @['#', '.', '.', '.', '.', '.', '.', '.', '.', '.', '#'],
    @['#', '.', '.', '.', '.', '.', '.', '.', '.', '.', '#'],
    @['#', '.', '.', '.', '.', '.', '.', '.', '.', '.', '#'],
    @['#', 'C', '.', '.', '.', '.', '.', '.', '.', 'W', '#'],
    @['#', '#', '#', '#', '#', 'D', '#', '#', '#', '#', '#']
  ]
