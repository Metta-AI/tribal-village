## Command Panel: context-sensitive action buttons (Phase 3)
##
## Shows different buttons depending on what is selected:
## - Unit selected: move/attack/patrol/stop/stance commands
## - Villager selected: build menu, gather commands
## - Building selected: production/research buttons
## - Multi-selection: common commands only

import
  boxy, pixie, vmath, windy, tables,
  std/strutils,
  common, environment

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  CommandButtonKind* = enum
    CmdNone
    # Unit commands (common)
    CmdMove
    CmdAttack
    CmdStop
    CmdPatrol
    CmdStance
    # Villager-specific
    CmdBuild
    CmdGather
    # Building commands
    CmdSetRally
    CmdUngarrison
    # Production (for military buildings)
    CmdTrainVillager
    CmdTrainManAtArms
    CmdTrainArcher
    CmdTrainScout
    CmdTrainKnight
    CmdTrainMonk
    CmdTrainBatteringRam
    CmdTrainMangonel
    CmdTrainTrebuchet
    CmdTrainBoat
    CmdTrainTradeCog

  CommandButton* = object
    kind*: CommandButtonKind
    rect*: Rect
    label*: string
    hotkey*: string
    enabled*: bool
    hovered*: bool

  CommandPanelState* = object
    buttons*: seq[CommandButton]
    visible*: bool
    rect*: Rect

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const
  CommandPanelBgColor = color(0.12, 0.16, 0.20, 0.92)
  CommandButtonBgColor = color(0.20, 0.24, 0.28, 0.90)
  CommandButtonHoverColor = color(0.28, 0.32, 0.38, 0.95)
  CommandButtonDisabledColor = color(0.15, 0.18, 0.22, 0.70)

  CommandLabelFontPath = "data/Inter-Regular.ttf"
  CommandLabelFontSize: float32 = 14
  CommandHotkeyFontSize: float32 = 11

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var
  commandPanelState*: CommandPanelState
  commandLabelImages: Table[string, string] = initTable[string, string]()
  commandLabelSizes: Table[string, IVec2] = initTable[string, IVec2]()

# ---------------------------------------------------------------------------
# Label rendering
# ---------------------------------------------------------------------------

proc renderCommandLabel(text: string, fontSize: float32): (string, IVec2) =
  ## Render a text label and return the image key and size.
  if text in commandLabelImages:
    return (commandLabelImages[text], commandLabelSizes.getOrDefault(text, ivec2(0, 0)))

  var measureCtx = newContext(1, 1)
  measureCtx.font = CommandLabelFontPath
  measureCtx.fontSize = fontSize
  measureCtx.textBaseline = TopBaseline

  let padding = 2.0'f32
  let w = max(1, (measureCtx.measureText(text).width + padding * 2).int)
  let h = max(1, (fontSize + padding * 2).int)

  var ctx = newContext(w, h)
  ctx.font = CommandLabelFontPath
  ctx.fontSize = fontSize
  ctx.textBaseline = TopBaseline
  ctx.fillStyle.color = color(1, 1, 1, 1)
  ctx.fillText(text, vec2(padding, padding))

  let key = "cmd_label/" & text.replace(" ", "_")
  bxy.addImage(key, ctx.image)
  commandLabelImages[text] = key
  commandLabelSizes[text] = ivec2(w, h)
  result = (key, ivec2(w, h))

# ---------------------------------------------------------------------------
# Button generation (context-sensitive)
# ---------------------------------------------------------------------------

proc getButtonLabel(kind: CommandButtonKind): string =
  case kind
  of CmdNone: ""
  of CmdMove: "Move"
  of CmdAttack: "Attack"
  of CmdStop: "Stop"
  of CmdPatrol: "Patrol"
  of CmdStance: "Stance"
  of CmdBuild: "Build"
  of CmdGather: "Gather"
  of CmdSetRally: "Rally"
  of CmdUngarrison: "Ungarr"
  of CmdTrainVillager: "Villgr"
  of CmdTrainManAtArms: "M@Arms"
  of CmdTrainArcher: "Archer"
  of CmdTrainScout: "Scout"
  of CmdTrainKnight: "Knight"
  of CmdTrainMonk: "Monk"
  of CmdTrainBatteringRam: "Ram"
  of CmdTrainMangonel: "Mangon"
  of CmdTrainTrebuchet: "Trebuc"
  of CmdTrainBoat: "Boat"
  of CmdTrainTradeCog: "T.Cog"

proc getButtonHotkey(kind: CommandButtonKind): string =
  case kind
  of CmdNone: ""
  of CmdMove: "M"
  of CmdAttack: "A"
  of CmdStop: "S"
  of CmdPatrol: "P"
  of CmdStance: "D"
  of CmdBuild: "B"
  of CmdGather: "G"
  of CmdSetRally: "R"
  of CmdUngarrison: "V"
  of CmdTrainVillager: "Q"
  of CmdTrainManAtArms: "W"
  of CmdTrainArcher: "E"
  of CmdTrainScout: "R"
  of CmdTrainKnight: "T"
  of CmdTrainMonk: "Y"
  of CmdTrainBatteringRam: "Q"
  of CmdTrainMangonel: "W"
  of CmdTrainTrebuchet: "E"
  of CmdTrainBoat: "Q"
  of CmdTrainTradeCog: "W"

proc buildUnitCommands(): seq[CommandButtonKind] =
  ## Commands available for military units.
  @[CmdMove, CmdAttack, CmdStop, CmdPatrol, CmdStance]

proc buildVillagerCommands(): seq[CommandButtonKind] =
  ## Commands available for villagers.
  @[CmdMove, CmdAttack, CmdStop, CmdBuild, CmdGather]

proc buildBuildingCommands(thing: Thing): seq[CommandButtonKind] =
  ## Commands available for selected building.
  result = @[CmdSetRally]

  # Add ungarrison if building can garrison
  if thing.kind in {TownCenter, Castle, GuardTower, House}:
    result.add(CmdUngarrison)

  # Add production options based on building type
  case thing.kind
  of TownCenter:
    result.add(CmdTrainVillager)
  of Barracks:
    result.add(CmdTrainManAtArms)
  of ArcheryRange:
    result.add(CmdTrainArcher)
  of Stable:
    result.add(CmdTrainScout)
    result.add(CmdTrainKnight)
  of Monastery:
    result.add(CmdTrainMonk)
  of SiegeWorkshop:
    result.add(CmdTrainBatteringRam)
  of MangonelWorkshop:
    result.add(CmdTrainMangonel)
  of TrebuchetWorkshop:
    result.add(CmdTrainTrebuchet)
  of Dock:
    result.add(CmdTrainBoat)
    result.add(CmdTrainTradeCog)
  else:
    discard

proc buildMultiSelectCommands(): seq[CommandButtonKind] =
  ## Commands for multi-selection (common commands only).
  @[CmdMove, CmdAttack, CmdStop, CmdPatrol]

# ---------------------------------------------------------------------------
# Panel rect calculation
# ---------------------------------------------------------------------------

proc commandPanelRect*(panelRect: IRect): Rect =
  ## Calculate the command panel rectangle (right side, above footer).
  let x = panelRect.x.float32 + panelRect.w.float32 - CommandPanelWidth.float32 - CommandPanelMargin.float32
  let y = panelRect.y.float32 + panelRect.h.float32 - FooterHeight.float32 - MinimapSize.float32 - CommandPanelMargin.float32 * 2
  let h = MinimapSize.float32  # Same height as minimap for visual balance
  Rect(x: x, y: y, w: CommandPanelWidth.float32, h: h)

proc isInCommandPanel*(panelRect: IRect, mousePosPx: Vec2): bool =
  ## Check if mouse position is inside the command panel.
  let cpRect = commandPanelRect(panelRect)
  mousePosPx.x >= cpRect.x and mousePosPx.x <= cpRect.x + cpRect.w and
    mousePosPx.y >= cpRect.y and mousePosPx.y <= cpRect.y + cpRect.h

# ---------------------------------------------------------------------------
# Build buttons based on selection
# ---------------------------------------------------------------------------

proc buildCommandButtons*(panelRect: IRect): seq[CommandButton] =
  ## Build the list of command buttons based on current selection.
  let cpRect = commandPanelRect(panelRect)

  # Determine which commands to show based on selection
  var commandKinds: seq[CommandButtonKind] = @[]

  if selection.len == 0:
    # No selection - no commands
    return @[]
  elif selection.len == 1:
    let thing = selection[0]
    if thing.kind == Agent:
      if thing.unitClass == UnitVillager:
        commandKinds = buildVillagerCommands()
      else:
        commandKinds = buildUnitCommands()
    elif isBuildingKind(thing.kind):
      commandKinds = buildBuildingCommands(thing)
    else:
      return @[]
  else:
    # Multi-selection: check if all are agents
    var allAgents = true
    for thing in selection:
      if thing.kind != Agent:
        allAgents = false
        break
    if allAgents:
      commandKinds = buildMultiSelectCommands()
    else:
      return @[]

  # Create button objects with positions
  let startX = cpRect.x + CommandPanelPadding.float32
  let startY = cpRect.y + CommandPanelPadding.float32 + 20  # Leave room for header

  for i, kind in commandKinds:
    let col = i mod CommandButtonCols
    let row = i div CommandButtonCols
    let x = startX + col.float32 * (CommandButtonSize.float32 + CommandButtonGap.float32)
    let y = startY + row.float32 * (CommandButtonSize.float32 + CommandButtonGap.float32)

    result.add(CommandButton(
      kind: kind,
      rect: Rect(x: x, y: y, w: CommandButtonSize.float32, h: CommandButtonSize.float32),
      label: getButtonLabel(kind),
      hotkey: getButtonHotkey(kind),
      enabled: true,
      hovered: false
    ))

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

proc drawCommandPanel*(panelRect: IRect, mousePosPx: Vec2) =
  ## Draw the command panel with context-sensitive buttons.
  if selection.len == 0:
    return  # Don't draw if nothing selected

  let cpRect = commandPanelRect(panelRect)

  # Draw panel background
  bxy.drawRect(
    rect = Rect(x: cpRect.x - 2, y: cpRect.y - 2,
                w: cpRect.w + 4, h: cpRect.h + 4),
    color = color(0.08, 0.10, 0.14, 0.95)
  )
  bxy.drawRect(rect = cpRect, color = CommandPanelBgColor)

  # Draw header label
  let headerText = if selection.len == 1:
    if selection[0].kind == Agent:
      "Commands"
    elif isBuildingKind(selection[0].kind):
      "Production"
    else:
      "Commands"
  else:
    "Commands (" & $selection.len & ")"

  let (headerKey, headerSize) = renderCommandLabel(headerText, CommandLabelFontSize + 2)
  let headerX = cpRect.x + (cpRect.w - headerSize.x.float32) * 0.5
  let headerY = cpRect.y + 4
  bxy.drawImage(headerKey, vec2(headerX, headerY), angle = 0, scale = 1)

  # Build and draw buttons
  let buttons = buildCommandButtons(panelRect)

  for button in buttons:
    # Check hover state
    let hovered = mousePosPx.x >= button.rect.x and
                  mousePosPx.x <= button.rect.x + button.rect.w and
                  mousePosPx.y >= button.rect.y and
                  mousePosPx.y <= button.rect.y + button.rect.h

    # Draw button background
    let bgColor = if not button.enabled:
      CommandButtonDisabledColor
    elif hovered:
      CommandButtonHoverColor
    else:
      CommandButtonBgColor

    bxy.drawRect(rect = button.rect, color = bgColor)

    # Draw button border
    let borderColor = if hovered: color(0.5, 0.6, 0.7, 0.8) else: color(0.3, 0.35, 0.4, 0.6)
    let bw = 1.0'f32
    bxy.drawRect(Rect(x: button.rect.x, y: button.rect.y, w: button.rect.w, h: bw), borderColor)
    bxy.drawRect(Rect(x: button.rect.x, y: button.rect.y + button.rect.h - bw, w: button.rect.w, h: bw), borderColor)
    bxy.drawRect(Rect(x: button.rect.x, y: button.rect.y, w: bw, h: button.rect.h), borderColor)
    bxy.drawRect(Rect(x: button.rect.x + button.rect.w - bw, y: button.rect.y, w: bw, h: button.rect.h), borderColor)

    # Draw label centered
    let (labelKey, labelSize) = renderCommandLabel(button.label, CommandLabelFontSize)
    let labelX = button.rect.x + (button.rect.w - labelSize.x.float32) * 0.5
    let labelY = button.rect.y + (button.rect.h - labelSize.y.float32) * 0.5
    bxy.drawImage(labelKey, vec2(labelX, labelY), angle = 0, scale = 1)

    # Draw hotkey in corner
    if button.hotkey.len > 0:
      let (hotkeyKey, hotkeySize) = renderCommandLabel(button.hotkey, CommandHotkeyFontSize)
      let hotkeyX = button.rect.x + button.rect.w - hotkeySize.x.float32 - 2
      let hotkeyY = button.rect.y + 2
      bxy.drawImage(hotkeyKey, vec2(hotkeyX, hotkeyY), angle = 0, scale = 1)

# ---------------------------------------------------------------------------
# Click handling
# ---------------------------------------------------------------------------

proc handleCommandPanelClick*(panelRect: IRect, mousePosPx: Vec2): CommandButtonKind =
  ## Handle a click on the command panel, returning the clicked button kind.
  if not isInCommandPanel(panelRect, mousePosPx):
    return CmdNone

  let buttons = buildCommandButtons(panelRect)
  for button in buttons:
    if mousePosPx.x >= button.rect.x and
       mousePosPx.x <= button.rect.x + button.rect.w and
       mousePosPx.y >= button.rect.y and
       mousePosPx.y <= button.rect.y + button.rect.h:
      if button.enabled:
        return button.kind

  return CmdNone
