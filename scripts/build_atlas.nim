## Build texture atlas for silky rendering
##
## Scans data/ for all PNG sprites, packs them into a single atlas image,
## and generates JSON metadata with sprite coordinates.
##
## Usage: nim c -r scripts/build_atlas.nim
## Output:
##   - data/silky.atlas.png - Combined texture atlas
##   - data/silky.atlas.json - Atlas metadata (sprite positions)

import std/[os, algorithm, json, strutils, sequtils]
import pixie

const
  AtlasPadding = 2  # Padding between sprites to prevent bleeding
  MaxAtlasSize = 8192  # Maximum atlas dimension

type
  Sprite = object
    key: string
    path: string
    image: Image
    width, height: int
    # Assigned position in atlas
    x, y: int

  # Shelf for row-based packing
  Shelf = object
    y, height, usedWidth: int

proc findPngFiles(dataDir: string): seq[tuple[key: string, path: string]] =
  ## Recursively find all PNG files and generate their atlas keys
  for entry in walkDirRec(dataDir, yieldFilter = {pcFile}):
    if entry.endsWith(".png"):
      # Generate key: strip "data/" prefix and ".png" suffix
      let key = entry.replace(dataDir & "/", "").replace(".png", "")
      result.add((key: key, path: entry))

proc loadSprites(files: seq[tuple[key: string, path: string]]): seq[Sprite] =
  ## Load all sprite images
  echo "Loading ", files.len, " sprites..."
  for (key, path) in files:
    try:
      let img = readImage(path)
      result.add(Sprite(
        key: key,
        path: path,
        image: img,
        width: img.width,
        height: img.height
      ))
    except Exception as e:
      echo "  Skipping ", path, ": ", e.msg

proc calculateAtlasSize(sprites: seq[Sprite]): int =
  ## Calculate required atlas size (power of 2)
  var totalArea = 0
  var maxDim = 0
  for s in sprites:
    totalArea += (s.width + AtlasPadding) * (s.height + AtlasPadding)
    maxDim = max(maxDim, max(s.width, s.height))

  # Start with minimum size that can fit the largest sprite
  var size = 256
  while size < maxDim + AtlasPadding:
    size *= 2

  # Grow until we have enough area (with headroom for packing inefficiency)
  while size < MaxAtlasSize:
    if size * size >= totalArea * 2:  # 2x headroom
      return size
    size *= 2
  return MaxAtlasSize

proc packSpritesShelf(sprites: var seq[Sprite], atlasSize: int): bool =
  ## Pack sprites using shelf algorithm (simple row-based packing)
  ## Sort by height descending, then place in rows

  # Sort by height (tallest first), then by width
  sprites.sort(proc(a, b: Sprite): int =
    result = b.height - a.height
    if result == 0:
      result = b.width - a.width
  )

  var shelves: seq[Shelf]

  for i in 0..<sprites.len:
    let spriteW = sprites[i].width + AtlasPadding
    let spriteH = sprites[i].height + AtlasPadding
    var placed = false

    # Try to fit in existing shelf
    for j in 0..<shelves.len:
      if shelves[j].usedWidth + spriteW <= atlasSize and
         spriteH <= shelves[j].height:
        # Fits in this shelf
        sprites[i].x = shelves[j].usedWidth
        sprites[i].y = shelves[j].y
        shelves[j].usedWidth += spriteW
        placed = true
        break

    if not placed:
      # Create new shelf
      let shelfY = if shelves.len == 0: 0
                   else: shelves[^1].y + shelves[^1].height

      if shelfY + spriteH > atlasSize:
        return false  # Doesn't fit

      shelves.add(Shelf(
        y: shelfY,
        height: spriteH,
        usedWidth: spriteW
      ))
      sprites[i].x = 0
      sprites[i].y = shelfY

  return true

proc generateAtlas(sprites: seq[Sprite], atlasSize: int): Image =
  ## Render all sprites into the atlas image
  result = newImage(atlasSize, atlasSize)

  for sprite in sprites:
    result.draw(sprite.image, translate(vec2(sprite.x.float32, sprite.y.float32)))

proc generateJson(sprites: seq[Sprite], atlasSize: int): JsonNode =
  ## Generate atlas metadata JSON
  var entries = newJObject()

  for sprite in sprites:
    entries[sprite.key] = %*{
      "x": sprite.x,
      "y": sprite.y,
      "width": sprite.width,
      "height": sprite.height
    }

  result = %*{
    "size": atlasSize,
    "entries": entries
  }

proc main() =
  let dataDir = "data"
  let atlasPath = dataDir / "silky.atlas.png"
  let jsonPath = dataDir / "silky.atlas.json"

  # Find and load sprites
  let files = findPngFiles(dataDir)
  echo "Found ", files.len, " PNG files"

  # Filter out existing atlas files
  let filteredFiles = files.filterIt(
    not it.key.startsWith("silky.atlas") and
    not it.path.endsWith("silky.atlas.png")
  )

  var sprites = loadSprites(filteredFiles)
  echo "Loaded ", sprites.len, " sprites"

  if sprites.len == 0:
    echo "No sprites found!"
    quit(1)

  # Calculate and try atlas sizes
  var atlasSize = calculateAtlasSize(sprites)
  echo "Initial atlas size estimate: ", atlasSize, "x", atlasSize

  while atlasSize <= MaxAtlasSize:
    var workingSprites = sprites  # Copy for packing
    if packSpritesShelf(workingSprites, atlasSize):
      sprites = workingSprites
      echo "Successfully packed into ", atlasSize, "x", atlasSize, " atlas"
      break
    else:
      atlasSize *= 2
      echo "Trying larger atlas: ", atlasSize, "x", atlasSize

  if atlasSize > MaxAtlasSize:
    echo "Failed to pack sprites into atlas (max size ", MaxAtlasSize, ")"
    quit(1)

  # Generate outputs
  echo "Generating atlas image..."
  let atlasImage = generateAtlas(sprites, atlasSize)
  atlasImage.writeFile(atlasPath)
  echo "Wrote ", atlasPath

  echo "Generating atlas JSON..."
  let atlasJson = generateJson(sprites, atlasSize)
  writeFile(jsonPath, atlasJson.pretty)
  echo "Wrote ", jsonPath

  # Summary
  echo ""
  echo "Atlas build complete:"
  echo "  - Sprites: ", sprites.len
  echo "  - Size: ", atlasSize, "x", atlasSize
  echo "  - Output: ", atlasPath, ", ", jsonPath

when isMainModule:
  main()
