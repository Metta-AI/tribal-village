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
  WorkshopBedChar* = 'B'
  WorkshopChairChar* = 'H'
  WorkshopTableChar* = 'T'
  WorkshopStatueChar* = 'S'
  WorkshopTownCenterChar* = 'N'

proc createVillage*(): Structure =
  ## Village layout with enclosed walls, interior workshops, and door gaps.
  result = Structure(
    width: 11,
    height: 11,
    centerPos: ivec2(5, 5),
    layout: @[
      @['#', '#', '#', '#', '#', 'D', '#', '#', '#', '#', '#'],
      @['#', '.', '.', '.', '.', 'N', '.', '.', '.', '.', '#'],
      @['#', '.', 'A', '.', '.', '.', '.', '.', 'F', '.', '#'],
      @['#', '.', '.', 'B', '.', '.', '.', 'T', '.', '.', '#'],
      @['#', '.', '.', '.', '.', '.', '.', '.', '.', '.', '#'],
      @['D', '.', '.', '.', '.', 'a', '.', '.', '.', '.', 'D'],
      @['#', '.', '.', '.', '.', '.', '.', '.', '.', '.', '#'],
      @['#', '.', '.', 'H', '.', '.', '.', 'S', '.', '.', '#'],
      @['#', '.', 'C', '.', '.', '.', '.', '.', 'W', '.', '#'],
      @['#', '.', '.', '.', '.', '.', '.', '.', '.', '.', '#'],
      @['#', '#', '#', '#', '#', 'D', '#', '#', '#', '#', '#']
    ]
  )
