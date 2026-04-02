## UI layout helpers for the resource bar, world view, and overlays.

import bumpy

type
  AreaAxis* = enum
    ## Split axis for dividing an area into two children.
    AxisHorizontal
    AxisVertical

  LayoutArea* = ref object
    ## Binary tree node that stores one layout region.
    parent*: LayoutArea
    left*: LayoutArea
    right*: LayoutArea
    ratio*: float32
    axis*: AreaAxis
    rect*: Rect

  UILayout* = object
    ## Complete UI layout with named accessors for key regions.
    root*: LayoutArea
    worldArea*: LayoutArea
    resourceBarArea*: LayoutArea
    footerArea*: LayoutArea
    minimapArea*: LayoutArea
    commandPanelArea*: LayoutArea
    unitInfoArea*: LayoutArea

const
  ResourceBarRatio* = 0.04'f32
  FooterRatio* = 0.08'f32
  MinimapRatio* = 0.25'f32
  CommandPanelRatio* = 0.20'f32

proc split*(area: LayoutArea, axis: AreaAxis, ratio: float32 = 0.5) =
  ## Split an area into two child regions.
  if area.left != nil or area.right != nil:
    return

  area.axis = axis
  area.ratio = ratio.clamp(0.1, 0.9)
  area.left = LayoutArea(parent: area)
  area.right = LayoutArea(parent: area)

proc isLeaf*(area: LayoutArea): bool =
  ## Return true when an area has no child regions.
  area.left == nil and area.right == nil

proc get*(area: LayoutArea, path: string): LayoutArea =
  ## Return the descendant area identified by an `L` and `R` path.
  result = area
  for c in path:
    if result == nil:
      return nil
    case c
    of 'L', 'l':
      result = result.left
    of 'R', 'r':
      result = result.right
    else:
      discard

proc resize*(area: LayoutArea, newRatio: float32) =
  ## Clamp and store a new split ratio for an area.
  area.ratio = newRatio.clamp(0.1, 0.9)

proc calculateLayout*(area: LayoutArea, bounds: Rect) =
  ## Recompute bounds for an area and all of its descendants.
  area.rect = bounds
  if area.isLeaf:
    return

  case area.axis
  of AxisHorizontal:
    let
      splitY = bounds.y + bounds.h * area.ratio
      topH = bounds.h * area.ratio
      bottomH = bounds.h * (1.0 - area.ratio)
    if area.left != nil:
      calculateLayout(area.left, rect(bounds.x, bounds.y, bounds.w, topH))
    if area.right != nil:
      calculateLayout(area.right, rect(bounds.x, splitY, bounds.w, bottomH))

  of AxisVertical:
    let
      splitX = bounds.x + bounds.w * area.ratio
      leftW = bounds.w * area.ratio
      rightW = bounds.w * (1.0 - area.ratio)
    if area.left != nil:
      calculateLayout(area.left, rect(bounds.x, bounds.y, leftW, bounds.h))
    if area.right != nil:
      calculateLayout(area.right, rect(splitX, bounds.y, rightW, bounds.h))

proc createDefaultLayout*(): UILayout =
  ## Build the default tribal_village panel layout.
  result.root = LayoutArea()
  result.root.split(AxisHorizontal, ResourceBarRatio)
  result.resourceBarArea = result.root.left

  result.root.right.split(
    AxisHorizontal,
    1.0 - FooterRatio / (1.0 - ResourceBarRatio)
  )
  result.worldArea = result.root.right.left
  result.footerArea = result.root.right.right

  result.minimapArea = LayoutArea()
  result.commandPanelArea = LayoutArea()
  result.unitInfoArea = LayoutArea()

proc calculateOverlayAreas*(
  layout: var UILayout,
  unusedFooterH: float32,
  minimapSize: float32,
  commandPanelW: float32,
  margin: float32
) =
  ## Recompute overlay rectangles after the main layout pass.
  discard unusedFooterH
  let worldRect = layout.worldArea.rect

  layout.minimapArea.rect = rect(
    worldRect.x + margin,
    worldRect.y + worldRect.h - minimapSize - margin,
    minimapSize,
    minimapSize
  )
  layout.commandPanelArea.rect = rect(
    worldRect.x + worldRect.w - commandPanelW - margin,
    worldRect.y + worldRect.h - minimapSize - margin,
    commandPanelW,
    minimapSize
  )

  let
    infoX = layout.minimapArea.rect.x + layout.minimapArea.rect.w + margin
    infoW = layout.commandPanelArea.rect.x - infoX - margin
  layout.unitInfoArea.rect = rect(
    infoX,
    worldRect.y + worldRect.h - minimapSize - margin,
    max(0, infoW),
    minimapSize
  )

proc updateLayout*(
  layout: var UILayout,
  windowW,
  windowH: float32,
  minimapSize: float32,
  commandPanelW: float32,
  resourceBarH: float32,
  footerH: float32,
  margin: float32
) =
  ## Update every layout region for the current window size.
  let totalH = windowH
  layout.root.ratio = resourceBarH / totalH

  let remainingH = totalH - resourceBarH
  if remainingH > 0:
    let contentH = remainingH - footerH
    layout.root.right.ratio = contentH / remainingH

  calculateLayout(layout.root, rect(0, 0, windowW, windowH))
  calculateOverlayAreas(
    layout,
    footerH,
    minimapSize,
    commandPanelW,
    margin
  )
