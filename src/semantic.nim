## Semantic capture for LLM UI debugging.
## When enabled, outputs a YAML-like text representation of the UI widget hierarchy
## instead of (or in addition to) rendering pixels. This allows LLMs to inspect
## UI layout, verify button positions, and detect overlapping widgets.

import std/strformat
import vmath

type
  SemanticWidgetKind* = enum
    WidgetButton
    WidgetLabel
    WidgetIcon
    WidgetPanel
    WidgetRect
    WidgetImage

  SemanticWidget* = object
    kind*: SemanticWidgetKind
    name*: string
    pos*: Vec2
    size*: Vec2
    parent*: string  ## Parent context name for hierarchy

  SemanticContext* = object
    name*: string
    depth*: int

var
  semanticEnabled* = false
  capturedWidgets: seq[SemanticWidget]
  contextStack: seq[SemanticContext]
  currentContext: string = ""
  currentDepth: int = 0

proc enableSemanticCapture*() =
  ## Enable semantic capture mode.
  semanticEnabled = true
  capturedWidgets = @[]
  contextStack = @[]
  currentContext = ""
  currentDepth = 0

proc disableSemanticCapture*() =
  ## Disable semantic capture mode.
  semanticEnabled = false

proc beginSemanticFrame*() =
  ## Start capturing a new frame. Clears previous frame's data.
  if not semanticEnabled:
    return
  capturedWidgets = @[]
  contextStack = @[]
  currentContext = ""
  currentDepth = 0

proc pushSemanticContext*(name: string) =
  ## Push a named context onto the stack (e.g., "Footer", "ResourceBar").
  if not semanticEnabled:
    return
  contextStack.add(SemanticContext(name: currentContext, depth: currentDepth))
  currentContext = name
  inc currentDepth

proc popSemanticContext*() =
  ## Pop the current context from the stack.
  if not semanticEnabled:
    return
  if contextStack.len > 0:
    let prev = contextStack.pop()
    currentContext = prev.name
    currentDepth = prev.depth

proc captureButton*(name: string, pos: Vec2, size: Vec2) =
  ## Capture a button widget.
  if not semanticEnabled:
    return
  capturedWidgets.add(SemanticWidget(
    kind: WidgetButton,
    name: name,
    pos: pos,
    size: size,
    parent: currentContext
  ))

proc captureLabel*(text: string, pos: Vec2, size: Vec2 = vec2(0, 0)) =
  ## Capture a label/text widget.
  if not semanticEnabled:
    return
  capturedWidgets.add(SemanticWidget(
    kind: WidgetLabel,
    name: text,
    pos: pos,
    size: size,
    parent: currentContext
  ))

proc captureIcon*(name: string, pos: Vec2, size: Vec2) =
  ## Capture an icon widget.
  if not semanticEnabled:
    return
  capturedWidgets.add(SemanticWidget(
    kind: WidgetIcon,
    name: name,
    pos: pos,
    size: size,
    parent: currentContext
  ))

proc capturePanel*(name: string, pos: Vec2, size: Vec2) =
  ## Capture a panel/container widget.
  if not semanticEnabled:
    return
  capturedWidgets.add(SemanticWidget(
    kind: WidgetPanel,
    name: name,
    pos: pos,
    size: size,
    parent: currentContext
  ))

proc captureRect*(name: string, pos: Vec2, size: Vec2) =
  ## Capture a generic rectangle (for backgrounds, borders, etc).
  if not semanticEnabled:
    return
  capturedWidgets.add(SemanticWidget(
    kind: WidgetRect,
    name: name,
    pos: pos,
    size: size,
    parent: currentContext
  ))

proc captureImage*(name: string, pos: Vec2, size: Vec2) =
  ## Capture an image/sprite widget.
  if not semanticEnabled:
    return
  capturedWidgets.add(SemanticWidget(
    kind: WidgetImage,
    name: name,
    pos: pos,
    size: size,
    parent: currentContext
  ))

proc kindToString(kind: SemanticWidgetKind): string =
  case kind
  of WidgetButton: "Button"
  of WidgetLabel: "Label"
  of WidgetIcon: "Icon"
  of WidgetPanel: "Panel"
  of WidgetRect: "Rect"
  of WidgetImage: "Image"

proc endSemanticFrame*(frameNumber: int): string =
  ## End the frame and return YAML-like output of all captured widgets.
  if not semanticEnabled:
    return ""

  var output = &"Frame {frameNumber}:\n"

  # Group widgets by parent context
  var contexts: seq[string] = @[]
  for widget in capturedWidgets:
    if widget.parent notin contexts:
      contexts.add(widget.parent)

  for ctx in contexts:
    let contextName = if ctx == "": "Root" else: ctx
    output.add(&"  {contextName}:\n")
    for widget in capturedWidgets:
      if widget.parent == ctx:
        let kindStr = kindToString(widget.kind)
        let posX = widget.pos.x.int
        let posY = widget.pos.y.int
        let sizeW = widget.size.x.int
        let sizeH = widget.size.y.int
        if widget.size.x > 0 and widget.size.y > 0:
          output.add(&"    - {kindStr} \"{widget.name}\" @ ({posX}, {posY}) {sizeW}x{sizeH}\n")
        else:
          output.add(&"    - {kindStr} \"{widget.name}\" @ ({posX}, {posY})\n")

  output
