import std/[os, strutils, tables]
import pixie
import pixie/fileformats/png
import ./items

const
  DfViewRoot = "data/df_view"
  OverridesPath = DfViewRoot & "/data/init/overrides.txt"
  ArtDir = DfViewRoot & "/data/art"
  TileSize = 24
  TilesPerRow = 16
  TargetSize = 256
  MapDir = "data"
  InventoryDir = "data"
  ForceDfTokens = ["DOOR"]

type
  OverrideEntry = object
    tilesetIdx: int
    tileIndex: int

proc generateDfViewAssets*() =
  when defined(emscripten):
    return

  if not dirExists(DfViewRoot) or not fileExists(OverridesPath):
    return

  let lines = readFile(OverridesPath).splitLines()
  var tilesets: Table[int, string]
  for line in lines:
    let trimmed = line.strip()
    if not trimmed.startsWith("[TILESET:"):
      continue
    let parts = trimmed.strip(chars = {'[', ']'}).split(':')
    if parts.len < 4:
      continue
    let idxStr = parts[^1]
    if idxStr.len == 0 or not idxStr.allCharsInSet(Digits):
      continue
    let tilesetIdx = parseInt(idxStr)
    let filename = parts[1]
    if filename.len == 0:
      continue
    tilesets[tilesetIdx] = ArtDir / filename
  if tilesets.len == 0:
    return

  var overrides: Table[string, OverrideEntry]
  for line in lines:
    let trimmed = line.strip()
    if trimmed.len == 0 or trimmed[0] == '#':
      continue
    if not trimmed.startsWith("[OVERRIDE:"):
      continue
    let parts = trimmed.strip(chars = {'[', ']'}).split(':')
    if parts.len < 5:
      continue
    let token = parts[3]
    if token.len == 0:
      continue
    var tilesetIdx = -1
    var tileIndex = -1
    for i in countdown(parts.len - 1, 0):
      if parts[i].len == 0 or not parts[i].allCharsInSet(Digits):
        continue
      let tilesetIdxValue = parseInt(parts[i])
      if tilesetIdxValue notin tilesets:
        continue
      for j in i + 1 ..< parts.len:
        if parts[j].len > 0 and parts[j].allCharsInSet(Digits):
          tilesetIdx = tilesetIdxValue
          tileIndex = parseInt(parts[j])
          break
      if tilesetIdx != -1:
        break
    if tilesetIdx == -1 or tileIndex == -1:
      continue
    if token notin overrides:
      overrides[token] = OverrideEntry(tilesetIdx: tilesetIdx, tileIndex: tileIndex)
  if overrides.len == 0:
    return

  var sheetCache: Table[int, Image]
  var created = 0
  var missing: seq[string]

  proc writeScaledTile(outPath: string, tilesetIdx: int, tileIndex: int, sheetPath: string) =
    var sheet: Image
    if tilesetIdx in sheetCache:
      sheet = sheetCache[tilesetIdx]
    else:
      sheet = readImage(sheetPath)
      sheetCache[tilesetIdx] = sheet
    let col = tileIndex mod TilesPerRow
    let row = tileIndex div TilesPerRow
    let x0 = col * TileSize
    let y0 = row * TileSize
    let src = sheet.subImage(x0, y0, TileSize, TileSize)
    let scaled = newImage(TargetSize, TargetSize)
    for y in 0 ..< TargetSize:
      let sy = (y * src.height) div TargetSize
      for x in 0 ..< TargetSize:
        let sx = (x * src.width) div TargetSize
        scaled[x, y] = src[sx, sy]
    createDir(parentDir(outPath))
    writeFile(outPath, encodePng(scaled))
    inc created

  for def in DfTokenCatalog:
    let token = def.token
    let outPath = if def.placement == DfBuilding:
      MapDir / (token.toLowerAscii & ".png")
    else:
      InventoryDir / (token.toLowerAscii & ".png")
    if fileExists(outPath) and token notin ForceDfTokens:
      continue

    var lookupToken = token
    if lookupToken notin overrides:
      lookupToken = case token
        of "BOULDER": "ROCK"
        of "PLANT_GROWTH": "PLANT"
        of "VERMIN": "CORPSE"
        of "PET": "CAGE"
        of "DRINK": "GOBLET"
        of "POWDER_MISC": "FOOD"
        of "LIQUID_MISC": "FLASK"
        of "SHEET": "BOOK"
        of "BRANCH": "WOOD"
        else: ""

    if lookupToken.len == 0 or lookupToken notin overrides:
      if token notin missing:
        missing.add(token)
      continue

    let overrideEntry = overrides[lookupToken]
    let sheetPath = tilesets.getOrDefault(overrideEntry.tilesetIdx, "")
    if sheetPath.len == 0 or not fileExists(sheetPath):
      if token notin missing:
        missing.add(token)
      continue

    writeScaledTile(outPath, overrideEntry.tilesetIdx, overrideEntry.tileIndex, sheetPath)

  # Replace the road sprite with a constructed floor tile when available.
  if "ConstructedFloor" in overrides:
    let overrideEntry = overrides["ConstructedFloor"]
    if overrideEntry.tilesetIdx in tilesets:
      let sheetPath = tilesets[overrideEntry.tilesetIdx]
      if fileExists(sheetPath):
        let outPath = MapDir / "road.png"
        if not fileExists(outPath):
          writeScaledTile(outPath, overrideEntry.tilesetIdx, overrideEntry.tileIndex, sheetPath)
  else:
    if "road" notin missing:
      missing.add("road")

  if created > 0:
    echo "DF tileset: generated ", created, " sprites"
  if missing.len > 0:
    echo "DF tileset: missing overrides for: ", missing.join(", ")
