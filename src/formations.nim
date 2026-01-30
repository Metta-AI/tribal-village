## Formation system for coordinated fighter movement and positioning.
## Enables groups of fighters to maintain spatial relationships during movement.
##
## Formation types:
##   - Line: Units arranged in a horizontal or vertical line
##   - Box: Units arranged in a rectangular perimeter
##   - Wedge: V-shaped formation (reserved for future)
##   - Scatter: No formation constraint (default)

import vmath
import types

type
  FormationType* = enum
    FormationNone = 0     ## No formation (scatter/default)
    FormationLine = 1     ## Line formation (horizontal or vertical)
    FormationBox = 2      ## Box formation (rectangular perimeter)
    FormationWedge = 3    ## Wedge/V-shape (reserved)
    FormationScatter = 4  ## Explicit scatter

  FormationState* = object
    formationType*: FormationType
    active*: bool
    ## Rotation in 45-degree increments (0=East, 1=NE, 2=North, etc.)
    ## Maps to Orientation enum values
    rotation*: int

const
  FormationSpacing* = 2       ## Tiles between units in formation
  MaxFormationSize* = 20      ## Max units in a single formation

## Per-control-group formation state
var groupFormations*: array[ControlGroupCount, FormationState]

proc clearFormation*(groupIndex: int) =
  ## Clear formation for a control group, returning to scatter behavior.
  if groupIndex >= 0 and groupIndex < ControlGroupCount:
    groupFormations[groupIndex] = FormationState(
      formationType: FormationNone,
      active: false,
      rotation: 0
    )

proc setFormation*(groupIndex: int, formationType: FormationType) =
  ## Set formation type for a control group.
  if groupIndex < 0 or groupIndex >= ControlGroupCount:
    return
  if formationType == FormationNone or formationType == FormationScatter:
    clearFormation(groupIndex)
    return
  groupFormations[groupIndex] = FormationState(
    formationType: formationType,
    active: true,
    rotation: 0
  )

proc getFormation*(groupIndex: int): FormationType =
  ## Get formation type for a control group.
  if groupIndex >= 0 and groupIndex < ControlGroupCount:
    return groupFormations[groupIndex].formationType
  FormationNone

proc setFormationRotation*(groupIndex: int, rotation: int) =
  ## Set formation rotation (0-7 for 8 directions).
  if groupIndex >= 0 and groupIndex < ControlGroupCount:
    groupFormations[groupIndex].rotation = rotation mod 8

proc getFormationRotation*(groupIndex: int): int =
  if groupIndex >= 0 and groupIndex < ControlGroupCount:
    return groupFormations[groupIndex].rotation
  0

proc isFormationActive*(groupIndex: int): bool =
  if groupIndex >= 0 and groupIndex < ControlGroupCount:
    return groupFormations[groupIndex].active
  false

# --- Position Calculation ---

proc calcLinePositions*(center: IVec2, unitCount: int, rotation: int): seq[IVec2] =
  ## Calculate positions for line formation around a center point.
  ## rotation: 0=horizontal (E-W), 2=vertical (N-S), 1/3=diagonal
  result = newSeq[IVec2](unitCount)
  if unitCount == 0:
    return

  # Direction vector based on rotation
  let dir = case rotation
    of 0: ivec2(1, 0)       # East-West line
    of 1: ivec2(1, -1)      # NE-SW diagonal
    of 2: ivec2(0, -1)      # North-South line
    of 3: ivec2(-1, -1)     # NW-SE diagonal
    of 4: ivec2(-1, 0)      # Same as 0 (reversed)
    of 5: ivec2(-1, 1)      # Same as 1 (reversed)
    of 6: ivec2(0, 1)       # Same as 2 (reversed)
    of 7: ivec2(1, 1)       # Same as 3 (reversed)
    else: ivec2(1, 0)

  # Place units centered on the center point
  let halfCount = unitCount div 2
  for i in 0 ..< unitCount:
    let offset = (i - halfCount) * FormationSpacing
    result[i] = ivec2(
      center.x + dir.x * offset.int32,
      center.y + dir.y * offset.int32
    )

proc calcBoxPositions*(center: IVec2, unitCount: int, rotation: int): seq[IVec2] =
  ## Calculate positions for box formation around a center point.
  ## Units are placed on the perimeter of a rectangle.
  result = newSeq[IVec2](unitCount)
  if unitCount == 0:
    return
  if unitCount == 1:
    result[0] = center
    return

  # Determine box dimensions based on unit count
  # Try to make a roughly square box
  let sideLen = max(1, (unitCount + 3) div 4)  # Units per side
  let halfW = (sideLen * FormationSpacing) div 2
  let halfH = halfW

  # Generate perimeter positions (clockwise from top-left)
  var perimeterPositions: seq[IVec2] = @[]

  # Top edge (left to right)
  for i in 0 ..< sideLen:
    let x = -halfW + i * FormationSpacing
    perimeterPositions.add(ivec2(center.x + x.int32, center.y - halfH.int32))

  # Right edge (top to bottom)
  for i in 1 ..< sideLen:
    let y = -halfH + i * FormationSpacing
    perimeterPositions.add(ivec2(center.x + halfW.int32, center.y + y.int32))

  # Bottom edge (right to left)
  for i in countdown(sideLen - 1, 0):
    let x = -halfW + i * FormationSpacing
    perimeterPositions.add(ivec2(center.x + x.int32, center.y + halfH.int32))

  # Left edge (bottom to top)
  for i in countdown(sideLen - 2, 1):
    let y = -halfH + i * FormationSpacing
    perimeterPositions.add(ivec2(center.x - halfW.int32, center.y + y.int32))

  # Apply rotation to all positions around center
  if rotation != 0:
    for i in 0 ..< perimeterPositions.len:
      let dx = perimeterPositions[i].x - center.x
      let dy = perimeterPositions[i].y - center.y
      # Simple 90-degree rotations for cardinal, approximate for diagonals
      case rotation
      of 2: # 90 degrees
        perimeterPositions[i] = ivec2(center.x + dy, center.y - dx)
      of 4: # 180 degrees
        perimeterPositions[i] = ivec2(center.x - dx, center.y - dy)
      of 6: # 270 degrees
        perimeterPositions[i] = ivec2(center.x - dy, center.y + dx)
      of 1: # 45 degrees approx
        perimeterPositions[i] = ivec2(center.x + dx - dy, center.y + dx + dy)
      of 3: # 135 degrees approx
        perimeterPositions[i] = ivec2(center.x + dy - dx, center.y - dx - dy)
      of 5: # 225 degrees approx
        perimeterPositions[i] = ivec2(center.x - dx + dy, center.y - dx - dy)
      of 7: # 315 degrees approx
        perimeterPositions[i] = ivec2(center.x - dy + dx, center.y + dx + dy)
      else: discard

  # Assign units to perimeter positions (wrapping if more positions than units)
  for i in 0 ..< unitCount:
    if i < perimeterPositions.len:
      result[i] = perimeterPositions[i]
    else:
      # Extra units go toward center
      let innerOffset = i - perimeterPositions.len + 1
      result[i] = ivec2(
        center.x + ((innerOffset mod 3) - 1).int32,
        center.y + ((innerOffset div 3) - 1).int32
      )

proc calcFormationPositions*(center: IVec2, unitCount: int,
                              formationType: FormationType,
                              rotation: int = 0): seq[IVec2] =
  ## Calculate positions for any formation type.
  case formationType
  of FormationLine:
    calcLinePositions(center, unitCount, rotation)
  of FormationBox:
    calcBoxPositions(center, unitCount, rotation)
  of FormationNone, FormationScatter, FormationWedge:
    # No formation - return empty (units use their own movement)
    newSeq[IVec2](0)

proc getFormationTargetForAgent*(groupIndex: int, agentIndex: int,
                                  groupCenter: IVec2,
                                  groupSize: int): IVec2 =
  ## Get the formation target position for a specific agent within a control group.
  ## agentIndex: the index of the agent within the control group (0-based).
  ## groupCenter: the center point of the formation (e.g., average position or move target).
  ## groupSize: total number of units in the group.
  ## Returns (-1, -1) if no formation is active or index is out of bounds.
  if groupIndex < 0 or groupIndex >= ControlGroupCount:
    return ivec2(-1, -1)
  if not groupFormations[groupIndex].active:
    return ivec2(-1, -1)
  if agentIndex < 0 or agentIndex >= groupSize:
    return ivec2(-1, -1)

  let ftype = groupFormations[groupIndex].formationType
  let rotation = groupFormations[groupIndex].rotation
  let positions = calcFormationPositions(groupCenter, groupSize, ftype, rotation)

  if agentIndex < positions.len:
    # Clamp to valid map positions
    let pos = positions[agentIndex]
    return ivec2(
      max(0'i32, min(MapWidth.int32 - 1, pos.x)),
      max(0'i32, min(MapHeight.int32 - 1, pos.y))
    )
  ivec2(-1, -1)

proc findAgentControlGroup*(agentId: int): int =
  ## Find which control group an agent belongs to.
  ## Returns -1 if not in any group.
  for g in 0 ..< ControlGroupCount:
    for thing in controlGroups[g]:
      if not thing.isNil and thing.agentId == agentId:
        return g
  -1

proc calcGroupCenter*(groupIndex: int, env: Environment): IVec2 =
  ## Calculate the center position of a control group (average of alive members).
  if groupIndex < 0 or groupIndex >= ControlGroupCount:
    return ivec2(-1, -1)
  var sumX, sumY, count: int32 = 0
  for thing in controlGroups[groupIndex]:
    if not thing.isNil and isAgentAlive(env, thing):
      sumX += thing.pos.x
      sumY += thing.pos.y
      inc count
  if count == 0:
    return ivec2(-1, -1)
  ivec2(sumX div count, sumY div count)

proc aliveGroupSize*(groupIndex: int, env: Environment): int =
  ## Count alive units in a control group.
  if groupIndex < 0 or groupIndex >= ControlGroupCount:
    return 0
  for thing in controlGroups[groupIndex]:
    if not thing.isNil and isAgentAlive(env, thing):
      inc result

proc agentIndexInGroup*(groupIndex: int, agentId: int, env: Environment): int =
  ## Get the index of an agent within its control group (only counting alive members).
  ## Returns -1 if not found.
  if groupIndex < 0 or groupIndex >= ControlGroupCount:
    return -1
  var idx = 0
  for thing in controlGroups[groupIndex]:
    if not thing.isNil and isAgentAlive(env, thing):
      if thing.agentId == agentId:
        return idx
      inc idx
  -1

proc resetAllFormations*() =
  ## Reset all formation state (called on environment reset).
  for g in 0 ..< ControlGroupCount:
    groupFormations[g] = FormationState()
