## layout.nim - Binary tree LayoutArea layout system for UI panels
##
## Ported from mettascope's layout system. Provides flexible, resizable
## panel regions using a binary tree structure with named path accessors.

import
  bumpy

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  AreaAxis* = enum
    ## Split axis for dividing an area into two children.
    AxisHorizontal  # Split top/bottom (children stack vertically)
    AxisVertical    # Split left/right (children stack horizontally)

  LayoutArea* = ref object
    ## A node in the binary tree layout.
    ## Leaf nodes have no children and represent drawable regions.
    ## Internal nodes split their space between two children.
    parent*: LayoutArea
    left*: LayoutArea      # First child (top or left depending on axis)
    right*: LayoutArea     # Second child (bottom or right depending on axis)
    ratio*: float32  # Split ratio (0.0-1.0), how much space goes to left child
    axis*: AreaAxis  # How this area splits its children
    rect*: Rect      # Calculated bounds in screen coordinates

# ---------------------------------------------------------------------------
# LayoutArea manipulation
# ---------------------------------------------------------------------------

proc split*(area: LayoutArea, axis: AreaAxis, ratio: float32 = 0.5) =
  ## Split an area into two children along the given axis.
  ## ratio determines how much space goes to the left/top child (0.0-1.0).
  if area.left != nil or area.right != nil:
    # Already split - could clear children if needed
    return

  area.axis = axis
  area.ratio = ratio.clamp(0.1, 0.9)
  area.left = LayoutArea(parent: area)
  area.right = LayoutArea(parent: area)

proc isLeaf*(area: LayoutArea): bool =
  ## Check if area is a leaf node (no children).
  area.left == nil and area.right == nil

proc get*(area: LayoutArea, path: string): LayoutArea =
  ## Get a descendant area by path string.
  ## 'L' = left child, 'R' = right child.
  ## Example: "RL" = right child, then left child.
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
  ## Adjust the split ratio of an area.
  area.ratio = newRatio.clamp(0.1, 0.9)

# ---------------------------------------------------------------------------
# Layout calculation
# ---------------------------------------------------------------------------

proc calculateLayout*(area: LayoutArea, bounds: Rect) =
  ## Recursively calculate the bounds of this area and all children.
  area.rect = bounds

  if area.isLeaf:
    return

  case area.axis
  of AxisHorizontal:
    # Split top/bottom
    let splitY = bounds.y + bounds.h * area.ratio
    let topH = bounds.h * area.ratio
    let bottomH = bounds.h * (1.0 - area.ratio)

    if area.left != nil:
      calculateLayout(area.left, rect(bounds.x, bounds.y, bounds.w, topH))
    if area.right != nil:
      calculateLayout(area.right, rect(bounds.x, splitY, bounds.w, bottomH))

  of AxisVertical:
    # Split left/right
    let splitX = bounds.x + bounds.w * area.ratio
    let leftW = bounds.w * area.ratio
    let rightW = bounds.w * (1.0 - area.ratio)

    if area.left != nil:
      calculateLayout(area.left, rect(bounds.x, bounds.y, leftW, bounds.h))
    if area.right != nil:
      calculateLayout(area.right, rect(splitX, bounds.y, rightW, bounds.h))

# ---------------------------------------------------------------------------
# Default tribal_village layout
# ---------------------------------------------------------------------------

type
  UILayout* = object
    ## The complete UI layout with named area accessors.
    root*: LayoutArea
    # Named areas for direct access
    worldArea*: LayoutArea         # Main world view
    resourceBarArea*: LayoutArea   # Resource bar at top
    footerArea*: LayoutArea        # Footer bar at bottom
    minimapArea*: LayoutArea       # Minimap overlay area (bottom-left)
    commandPanelArea*: LayoutArea  # Command panel overlay area (bottom-right)
    unitInfoArea*: LayoutArea      # Unit info panel area

# Layout constants
const
  ResourceBarRatio* = 0.04'f32  # ~32px at 800px height
  FooterRatio* = 0.08'f32       # ~64px at 800px height
  MinimapRatio* = 0.25'f32      # 25% of bottom panel width for minimap
  CommandPanelRatio* = 0.20'f32 # 20% for command panel

proc createDefaultLayout*(): UILayout =
  ## Create the default tribal_village UI layout.
  ##
  ## Layout structure:
  ##   Root (Horizontal split)
  ##   +-- Top section (resource bar)
  ##   +-- Bottom section (Horizontal split)
  ##       +-- Main content (world view + overlays)
  ##       +-- Footer bar
  ##
  ## Overlays (minimap, command panel) are positioned within the world area
  ## but rendered on top.

  result.root = LayoutArea()

  # Split: resource bar (top) vs rest
  result.root.split(AxisHorizontal, ResourceBarRatio)
  result.resourceBarArea = result.root.left

  # Split rest: main content (top) vs footer (bottom)
  result.root.right.split(AxisHorizontal, 1.0 - FooterRatio / (1.0 - ResourceBarRatio))
  result.worldArea = result.root.right.left
  result.footerArea = result.root.right.right

  # The minimap and command panel are overlays on the world area
  # They don't split the world area but position themselves within it
  # We create virtual areas for their positioning calculations

  # Create overlay container (not actually splitting world view)
  # This is a virtual structure for calculating overlay positions
  result.minimapArea = LayoutArea()
  result.commandPanelArea = LayoutArea()
  result.unitInfoArea = LayoutArea()

proc calculateOverlayAreas*(layout: var UILayout, footerH: float32, minimapSize: float32,
                            commandPanelW: float32, margin: float32) =
  ## Calculate overlay area positions based on the world area bounds.
  ## Called after calculateLayout on root.
  let worldRect = layout.worldArea.rect

  # Minimap: bottom-left corner, above footer
  layout.minimapArea.rect = rect(
    worldRect.x + margin,
    worldRect.y + worldRect.h - minimapSize - margin,
    minimapSize,
    minimapSize
  )

  # Command panel: bottom-right corner, above footer, same height as minimap
  layout.commandPanelArea.rect = rect(
    worldRect.x + worldRect.w - commandPanelW - margin,
    worldRect.y + worldRect.h - minimapSize - margin,
    commandPanelW,
    minimapSize
  )

  # Unit info: between minimap and command panel at bottom
  let infoX = layout.minimapArea.rect.x + layout.minimapArea.rect.w + margin
  let infoW = layout.commandPanelArea.rect.x - infoX - margin
  layout.unitInfoArea.rect = rect(
    infoX,
    worldRect.y + worldRect.h - minimapSize - margin,
    max(0, infoW),
    minimapSize
  )

proc updateLayout*(layout: var UILayout, windowW, windowH: float32,
                   minimapSize: float32, commandPanelW: float32,
                   resourceBarH: float32, footerH: float32, margin: float32) =
  ## Update all layout areas for a new window size.
  ## This is the main entry point called on window resize.

  # Update ratios based on actual pixel sizes
  let totalH = windowH
  layout.root.ratio = resourceBarH / totalH

  # Footer ratio within the remaining space after resource bar
  let remainingH = totalH - resourceBarH
  if remainingH > 0:
    let contentH = remainingH - footerH
    layout.root.right.ratio = contentH / remainingH

  # Calculate all bounds
  calculateLayout(layout.root, rect(0, 0, windowW, windowH))

  # Calculate overlay positions
  calculateOverlayAreas(layout, footerH, minimapSize, commandPanelW, margin)
