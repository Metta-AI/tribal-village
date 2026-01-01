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
  MapDir = "data/map"
  InventoryDir = "data/inventory"
  ForceDfTokens = ["DOOR"]

type
  OverrideEntry = object
    tilesetIdx: int
    tileIndex: int

proc isDigitsOnly(s: string): bool =
  if s.len == 0:
    return false
  for ch in s:
    if ch < '0' or ch > '9':
      return false
  true

proc parseTilesetMap(lines: seq[string]): Table[int, string] =
  for line in lines:
    let trimmed = line.strip()
    if not trimmed.startsWith("[TILESET:"):
      continue
    let parts = trimmed.strip(chars = {'[', ']'}).split(':')
    if parts.len < 4:
      continue
    let idxStr = parts[^1]
    if not isDigitsOnly(idxStr):
      continue
    let idx = parseInt(idxStr)
    let filename = parts[1]
    if filename.len == 0:
      continue
    result[idx] = ArtDir / filename

proc parseOverrides(lines: seq[string], tilesets: Table[int, string]): Table[string, OverrideEntry] =
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
      if not isDigitsOnly(parts[i]):
        continue
      let value = parseInt(parts[i])
      if value notin tilesets:
        continue
      for j in i + 1 ..< parts.len:
        if isDigitsOnly(parts[j]):
          tilesetIdx = value
          tileIndex = parseInt(parts[j])
          break
      if tilesetIdx != -1:
        break
    if tilesetIdx == -1 or tileIndex == -1:
      continue
    if token notin result:
      result[token] = OverrideEntry(tilesetIdx: tilesetIdx, tileIndex: tileIndex)

proc scaleNearest(src: Image, dstW, dstH: int): Image =
  result = newImage(dstW, dstH)
  for y in 0 ..< dstH:
    let sy = (y * src.height) div dstH
    for x in 0 ..< dstW:
      let sx = (x * src.width) div dstW
      result[x, y] = src[sx, sy]

proc extractTile(sheet: Image, tileIndex: int): Image =
  let col = tileIndex mod TilesPerRow
  let row = tileIndex div TilesPerRow
  let x = col * TileSize
  let y = row * TileSize
  result = sheet.subImage(x, y, TileSize, TileSize)

proc generateDfViewAssets*() =
  when defined(emscripten):
    return

  if not dirExists(DfViewRoot) or not fileExists(OverridesPath):
    return

  let lines = readFile(OverridesPath).splitLines()
  let tilesets = parseTilesetMap(lines)
  if tilesets.len == 0:
    return

  let overrides = parseOverrides(lines, tilesets)
  if overrides.len == 0:
    return

  var sheetCache: Table[int, Image]
  var created = 0
  var missing: seq[string]

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

    let entry = overrides[lookupToken]
    if entry.tilesetIdx notin tilesets:
      if token notin missing:
        missing.add(token)
      continue

    let sheetPath = tilesets[entry.tilesetIdx]
    if not fileExists(sheetPath):
      if token notin missing:
        missing.add(token)
      continue

    let sheet = if entry.tilesetIdx in sheetCache:
      sheetCache[entry.tilesetIdx]
    else:
      let img = readImage(sheetPath)
      sheetCache[entry.tilesetIdx] = img
      img

    let tile = extractTile(sheet, entry.tileIndex)
    let scaled = scaleNearest(tile, TargetSize, TargetSize)

    createDir(parentDir(outPath))
    writeFile(outPath, encodePng(scaled))
    inc created

  # Replace the road sprite with a constructed floor tile when available.
  if "ConstructedFloor" in overrides:
    let entry = overrides["ConstructedFloor"]
    if entry.tilesetIdx in tilesets:
      let sheetPath = tilesets[entry.tilesetIdx]
      if fileExists(sheetPath):
        let sheet = if entry.tilesetIdx in sheetCache:
          sheetCache[entry.tilesetIdx]
        else:
          let img = readImage(sheetPath)
          sheetCache[entry.tilesetIdx] = img
          img
        let tile = extractTile(sheet, entry.tileIndex)
        let scaled = scaleNearest(tile, TargetSize, TargetSize)
        let outPath = MapDir / "road.png"
        createDir(parentDir(outPath))
        writeFile(outPath, encodePng(scaled))
        inc created
  else:
    if "road" notin missing:
      missing.add("road")

  if created > 0:
    echo "DF tileset: generated ", created, " sprites"
  if missing.len > 0:
    echo "DF tileset: missing overrides for: ", missing.join(", ")
