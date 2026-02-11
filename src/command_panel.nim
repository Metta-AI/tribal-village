## Command Panel: context-sensitive action buttons (Phase 3)
##
## Shows different buttons depending on what is selected:
## - Unit selected: move/attack/patrol/stop/stance commands
## - Villager selected: build menu, gather commands
## - Building selected: production/research buttons
## - Multi-selection: common commands only
##
## Migrated to silky rendering for proper button states and consistent UI.

import
  pixie, vmath, windy,
  common, environment, tooltips, semantic

when defined(useSilky):
  import silky

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
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
  # Use UIColors from colors.nim for consistent theming
  CommandPanelBgColor = UiBg
  CommandButtonBgColor = UiBgButton
  CommandButtonHoverColor = UiBgButtonHover
  CommandButtonDisabledColor = UiBgButtonDisabled

  # Font used for button labels (must exist in silky atlas)
  CommandLabelFont = "Default"
  CommandHotkeyFont = "Default"

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var
  commandPanelState*: CommandPanelState
  buildMenuOpen*: bool = false  # Whether the build submenu is showing

# ---------------------------------------------------------------------------
# Color conversion helpers
# ---------------------------------------------------------------------------

proc toRGBX(c: Color): ColorRGBX {.inline.} =
  ## Convert pixie Color (float 0-1) to silky ColorRGBX (uint8 0-255).
  rgbx(
    (c.r * 255).uint8,
    (c.g * 255).uint8,
    (c.b * 255).uint8,
    (c.a * 255).uint8
  )

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
  of CmdHoldPosition: "Hold"
  of CmdBuild: "Build"
  of CmdGather: "Gather"
  of CmdBuildBack: "Back"
  of CmdBuildHouse: "House"
  of CmdBuildMill: "Mill"
  of CmdBuildLumberCamp: "Lumber"
  of CmdBuildMiningCamp: "Mining"
  of CmdBuildBarracks: "Barracks"
  of CmdBuildArcheryRange: "Archery"
  of CmdBuildStable: "Stable"
  of CmdBuildWall: "Wall"
  of CmdBuildBlacksmith: "Smith"
  of CmdBuildMarket: "Market"
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
  of CmdTrainGalley: "Galley"
  of CmdTrainFireShip: "F.Ship"
  of CmdTrainFishingShip: "Fisher"
  of CmdTrainTransportShip: "Transp"
  of CmdTrainDemoShip: "Demo"
  of CmdTrainCannonGalleon: "C.Galln"
  of CmdFormationLine: "Line"
  of CmdFormationBox: "Box"
  of CmdFormationStaggered: "Stagger"
  of CmdFormationRangedSpread: "Spread"
  # Blacksmith research
  of CmdResearchMeleeAttack: "MeleeAtk"
  of CmdResearchArcherAttack: "RangeAtk"
  of CmdResearchInfantryArmor: "InfArmor"
  of CmdResearchCavalryArmor: "CavArmor"
  of CmdResearchArcherArmor: "ArcArmor"
  # University research
  of CmdResearchBallistics: "Ballist"
  of CmdResearchMurderHoles: "MrdHole"
  of CmdResearchMasonry: "Masonry"
  of CmdResearchArchitecture: "Archit"
  of CmdResearchTreadmillCrane: "Treadml"
  of CmdResearchArrowslits: "Arrowsl"
  of CmdResearchHeatedShot: "HeatSht"
  of CmdResearchSiegeEngineers: "SiegeEn"
  of CmdResearchChemistry: "Chemist"
  of CmdResearchCoinage: "Coinage"
  # Castle research
  of CmdResearchCastleTech1: "CstlT1"
  of CmdResearchCastleTech2: "CstlT2"
  # Mill commands
  of CmdQueueFarm: "QFarm"

proc getButtonHotkey*(kind: CommandButtonKind): string =
  case kind
  of CmdNone: ""
  of CmdMove: "M"
  of CmdAttack: "A"
  of CmdStop: "S"
  of CmdPatrol: "P"
  of CmdStance: "D"
  of CmdHoldPosition: "H"
  of CmdBuild: "B"
  of CmdGather: "G"
  of CmdBuildBack: "Esc"
  of CmdBuildHouse: "Q"
  of CmdBuildMill: "W"
  of CmdBuildLumberCamp: "E"
  of CmdBuildMiningCamp: "R"
  of CmdBuildBarracks: "A"
  of CmdBuildArcheryRange: "S"
  of CmdBuildStable: "D"
  of CmdBuildWall: "F"
  of CmdBuildBlacksmith: "Z"
  of CmdBuildMarket: "X"
  of CmdSetRally: "G"
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
  of CmdTrainGalley: "E"
  of CmdTrainFireShip: "R"
  of CmdTrainFishingShip: "A"
  of CmdTrainTransportShip: "S"
  of CmdTrainDemoShip: "D"
  of CmdTrainCannonGalleon: "F"
  of CmdFormationLine: "1"
  of CmdFormationBox: "2"
  of CmdFormationStaggered: "3"
  of CmdFormationRangedSpread: "4"
  # Blacksmith research hotkeys (Q-T for 5 upgrade lines)
  of CmdResearchMeleeAttack: "Q"
  of CmdResearchArcherAttack: "W"
  of CmdResearchInfantryArmor: "E"
  of CmdResearchCavalryArmor: "R"
  of CmdResearchArcherArmor: "T"
  # University research hotkeys (Q-O for 9 techs in 2 rows)
  of CmdResearchBallistics: "Q"
  of CmdResearchMurderHoles: "W"
  of CmdResearchMasonry: "E"
  of CmdResearchArchitecture: "R"
  of CmdResearchTreadmillCrane: "T"
  of CmdResearchArrowslits: "A"
  of CmdResearchHeatedShot: "S"
  of CmdResearchSiegeEngineers: "D"
  of CmdResearchChemistry: "F"
  of CmdResearchCoinage: "G"
  # Castle research hotkeys
  of CmdResearchCastleTech1: "Q"
  of CmdResearchCastleTech2: "W"
  # Mill hotkeys
  of CmdQueueFarm: "Q"

proc commandKindToBuildingKind*(cmd: CommandButtonKind): ThingKind =
  ## Convert a build command to the corresponding ThingKind.
  case cmd
  of CmdBuildHouse: House
  of CmdBuildMill: Mill
  of CmdBuildLumberCamp: LumberCamp
  of CmdBuildMiningCamp: MiningCamp
  of CmdBuildBarracks: Barracks
  of CmdBuildArcheryRange: ArcheryRange
  of CmdBuildStable: Stable
  of CmdBuildWall: Wall
  of CmdBuildBlacksmith: Blacksmith
  of CmdBuildMarket: Market
  else: Wall  # Default fallback

proc buildUnitCommands(): seq[CommandButtonKind] =
  ## Commands available for military units.
  @[CmdMove, CmdAttack, CmdStop, CmdHoldPosition, CmdPatrol, CmdStance]

proc buildVillagerCommands(): seq[CommandButtonKind] =
  ## Commands available for villagers.
  if buildMenuOpen:
    @[CmdBuildBack, CmdBuildHouse, CmdBuildMill, CmdBuildLumberCamp,
      CmdBuildMiningCamp, CmdBuildBarracks, CmdBuildArcheryRange,
      CmdBuildStable, CmdBuildWall, CmdBuildBlacksmith, CmdBuildMarket]
  else:
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
    result.add(CmdTrainGalley)
    result.add(CmdTrainFireShip)
    result.add(CmdTrainFishingShip)
    result.add(CmdTrainTransportShip)
    result.add(CmdTrainDemoShip)
    result.add(CmdTrainCannonGalleon)
  of Blacksmith:
    # Blacksmith: 5 upgrade lines (attack/armor research)
    result.add(CmdResearchMeleeAttack)
    result.add(CmdResearchArcherAttack)
    result.add(CmdResearchInfantryArmor)
    result.add(CmdResearchCavalryArmor)
    result.add(CmdResearchArcherArmor)
  of University:
    # University: 9 technologies
    result.add(CmdResearchBallistics)
    result.add(CmdResearchMurderHoles)
    result.add(CmdResearchMasonry)
    result.add(CmdResearchArchitecture)
    result.add(CmdResearchTreadmillCrane)
    result.add(CmdResearchArrowslits)
    result.add(CmdResearchHeatedShot)
    result.add(CmdResearchSiegeEngineers)
    result.add(CmdResearchChemistry)
    result.add(CmdResearchCoinage)
  of Castle:
    # Castle: 2 unique techs per team (already has ungarrison)
    result.add(CmdResearchCastleTech1)
    result.add(CmdResearchCastleTech2)
  of Mill:
    # Mill: queue farm reseeds (AoE2-style)
    result.add(CmdQueueFarm)
  else:
    discard

proc buildMultiSelectCommands(): seq[CommandButtonKind] =
  ## Commands for multi-selection (common commands only).
  @[CmdMove, CmdAttack, CmdStop, CmdHoldPosition, CmdPatrol]

proc isResearchButtonEnabled*(kind: CommandButtonKind, building: Thing): bool =
  ## Check if a research button should be enabled (not yet researched).
  let teamId = building.teamId
  if teamId < 0 or teamId >= MapRoomObjectsTeams:
    return false

  case kind
  # Blacksmith upgrades - enabled if not at max level
  of CmdResearchMeleeAttack:
    env.teamBlacksmithUpgrades[teamId].levels[UpgradeMeleeAttack] < BlacksmithUpgradeMaxLevel
  of CmdResearchArcherAttack:
    env.teamBlacksmithUpgrades[teamId].levels[UpgradeArcherAttack] < BlacksmithUpgradeMaxLevel
  of CmdResearchInfantryArmor:
    env.teamBlacksmithUpgrades[teamId].levels[UpgradeInfantryArmor] < BlacksmithUpgradeMaxLevel
  of CmdResearchCavalryArmor:
    env.teamBlacksmithUpgrades[teamId].levels[UpgradeCavalryArmor] < BlacksmithUpgradeMaxLevel
  of CmdResearchArcherArmor:
    env.teamBlacksmithUpgrades[teamId].levels[UpgradeArcherArmor] < BlacksmithUpgradeMaxLevel
  # University techs - enabled if not researched
  of CmdResearchBallistics:
    not env.teamUniversityTechs[teamId].researched[TechBallistics]
  of CmdResearchMurderHoles:
    not env.teamUniversityTechs[teamId].researched[TechMurderHoles]
  of CmdResearchMasonry:
    not env.teamUniversityTechs[teamId].researched[TechMasonry]
  of CmdResearchArchitecture:
    not env.teamUniversityTechs[teamId].researched[TechArchitecture]
  of CmdResearchTreadmillCrane:
    not env.teamUniversityTechs[teamId].researched[TechTreadmillCrane]
  of CmdResearchArrowslits:
    not env.teamUniversityTechs[teamId].researched[TechArrowslits]
  of CmdResearchHeatedShot:
    not env.teamUniversityTechs[teamId].researched[TechHeatedShot]
  of CmdResearchSiegeEngineers:
    not env.teamUniversityTechs[teamId].researched[TechSiegeEngineers]
  of CmdResearchChemistry:
    not env.teamUniversityTechs[teamId].researched[TechChemistry]
  of CmdResearchCoinage:
    not env.teamUniversityTechs[teamId].researched[TechCoinage]
  # Castle unique techs - enabled if not researched (and prereq met for Imperial)
  of CmdResearchCastleTech1:
    let (castleAge, _) = castleTechsForTeam(teamId)
    not env.teamCastleTechs[teamId].researched[castleAge]
  of CmdResearchCastleTech2:
    let (castleAge, imperialAge) = castleTechsForTeam(teamId)
    env.teamCastleTechs[teamId].researched[castleAge] and  # Prereq met
      not env.teamCastleTechs[teamId].researched[imperialAge]
  else:
    true  # Non-research buttons are always enabled

# ---------------------------------------------------------------------------
# Panel rect calculation
# ---------------------------------------------------------------------------

proc commandPanelRect*(panelRect: IRect): Rect =
  ## Calculate the command panel rectangle (right side, above footer).
  ## Uses the layout system if available, falls back to calculated position.
  if uiLayout.commandPanelArea != nil and uiLayout.commandPanelArea.rect.w > 0:
    return uiLayout.commandPanelArea.rect

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

  # Get reference to selected building (if any) for research state checks
  let selectedBuilding = if selection.len == 1 and isBuildingKind(selection[0].kind):
    selection[0]
  else:
    nil

  for i, kind in commandKinds:
    let col = i mod CommandButtonCols
    let row = i div CommandButtonCols
    let x = startX + col.float32 * (CommandButtonSize.float32 + CommandButtonGap.float32)
    let y = startY + row.float32 * (CommandButtonSize.float32 + CommandButtonGap.float32)

    # Check if research buttons should be enabled
    let buttonEnabled = if not isNil(selectedBuilding):
      isResearchButtonEnabled(kind, selectedBuilding)
    else:
      true

    result.add(CommandButton(
      kind: kind,
      rect: Rect(x: x, y: y, w: CommandButtonSize.float32, h: CommandButtonSize.float32),
      label: getButtonLabel(kind),
      hotkey: getButtonHotkey(kind),
      enabled: buttonEnabled,
      hovered: false
    ))

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

proc drawCommandPanel*(panelRect: IRect, mousePosPx: Vec2) =
  ## Draw the command panel with context-sensitive buttons using silky.
  if selection.len == 0:
    return  # Don't draw if nothing selected

  if sk.isNil:
    return  # Silky not initialized

  let cpRect = commandPanelRect(panelRect)

  # Semantic capture: command panel
  pushSemanticContext("CommandPanel")
  capturePanel("CommandPanel", vec2(cpRect.x, cpRect.y), vec2(cpRect.w, cpRect.h))

  # Draw panel background with border
  sk.drawRect(
    vec2(cpRect.x - 2, cpRect.y - 2),
    vec2(cpRect.w + 4, cpRect.h + 4),
    UiBg.toRGBX
  )
  sk.drawRect(vec2(cpRect.x, cpRect.y), vec2(cpRect.w, cpRect.h), CommandPanelBgColor.toRGBX)

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

  let headerSize = sk.getTextSize(CommandLabelFont, headerText)
  let headerX = cpRect.x + (cpRect.w - headerSize.x) * 0.5
  let headerY = cpRect.y + 4
  discard sk.drawText(CommandLabelFont, headerText, vec2(headerX, headerY), UiFgBright.toRGBX)
  captureLabel(headerText, vec2(headerX, headerY), headerSize)

  # Build and draw buttons
  let buttons = buildCommandButtons(panelRect)
  var anyButtonHovered = false

  for button in buttons:
    # Check hover state
    let hovered = mousePosPx.x >= button.rect.x and
                  mousePosPx.x <= button.rect.x + button.rect.w and
                  mousePosPx.y >= button.rect.y and
                  mousePosPx.y <= button.rect.y + button.rect.h

    # Handle tooltip on hover
    if hovered and button.enabled:
      anyButtonHovered = true
      let tooltipContent = buildCommandTooltip(button.kind, button.hotkey)
      startHover(TooltipCommand, button.rect, tooltipContent)

    # Draw button background
    let bgColor = if not button.enabled:
      CommandButtonDisabledColor
    elif hovered:
      CommandButtonHoverColor
    else:
      CommandButtonBgColor

    sk.drawRect(vec2(button.rect.x, button.rect.y), vec2(button.rect.w, button.rect.h), bgColor.toRGBX)

    # Draw button border
    let borderColor = if hovered: UiBorderBright else: UiBorder
    let bw = 1.0'f32
    # Top border
    sk.drawRect(vec2(button.rect.x, button.rect.y), vec2(button.rect.w, bw), borderColor.toRGBX)
    # Bottom border
    sk.drawRect(vec2(button.rect.x, button.rect.y + button.rect.h - bw), vec2(button.rect.w, bw), borderColor.toRGBX)
    # Left border
    sk.drawRect(vec2(button.rect.x, button.rect.y), vec2(bw, button.rect.h), borderColor.toRGBX)
    # Right border
    sk.drawRect(vec2(button.rect.x + button.rect.w - bw, button.rect.y), vec2(bw, button.rect.h), borderColor.toRGBX)

    # Draw label centered
    let labelSize = sk.getTextSize(CommandLabelFont, button.label)
    let labelX = button.rect.x + (button.rect.w - labelSize.x) * 0.5
    let labelY = button.rect.y + (button.rect.h - labelSize.y) * 0.5
    let labelColor = if button.enabled: UiFgText else: UiFgDim
    discard sk.drawText(CommandLabelFont, button.label, vec2(labelX, labelY), labelColor.toRGBX)

    # Semantic capture: command button
    captureButton(button.label, vec2(button.rect.x, button.rect.y),
                  vec2(button.rect.w, button.rect.h))

    # Draw hotkey in corner
    if button.hotkey.len > 0:
      let hotkeySize = sk.getTextSize(CommandHotkeyFont, button.hotkey)
      let hotkeyX = button.rect.x + button.rect.w - hotkeySize.x - 2
      let hotkeyY = button.rect.y + 2
      discard sk.drawText(CommandHotkeyFont, button.hotkey, vec2(hotkeyX, hotkeyY), UiFgMuted.toRGBX)

    # Draw checkmark for researched techs (disabled research buttons)
    if not button.enabled and button.kind in {CmdResearchMeleeAttack, CmdResearchArcherAttack,
        CmdResearchInfantryArmor, CmdResearchCavalryArmor, CmdResearchArcherArmor,
        CmdResearchBallistics, CmdResearchMurderHoles, CmdResearchMasonry,
        CmdResearchArchitecture, CmdResearchTreadmillCrane, CmdResearchArrowslits,
        CmdResearchHeatedShot, CmdResearchSiegeEngineers, CmdResearchChemistry,
        CmdResearchCoinage, CmdResearchCastleTech1, CmdResearchCastleTech2}:
      # Draw a green checkmark indicator in the top-left corner
      let checkX = button.rect.x + 2
      let checkY = button.rect.y + 2
      discard sk.drawText(CommandHotkeyFont, "OK", vec2(checkX, checkY), UiSuccess.toRGBX)

  # Clear tooltip if no button is hovered
  if not anyButtonHovered:
    clearTooltip()

  popSemanticContext()

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
