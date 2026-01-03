import std/os
import pixie
import pixie/fileformats/png

const RoofMaskSprites = [
  "house",
  "town_center",
  "barracks",
  "archery_range",
  "stable",
  "siege_workshop",
  "blacksmith",
  "market",
  "dock",
  "monastery",
  "university",
  "castle"
]

proc buildRoofMask(src: Image, outCount: var int): Image =
  ## Generate a mask where red roof pixels become white (to be tinted by team).
  result = newImage(src.width, src.height)
  outCount = 0
  let maxY = int(src.height.float * 0.7)
  for y in 0 ..< src.height:
    if y > maxY:
      continue
    for x in 0 ..< src.width:
      let c = src[x, y]
      if c.a <= 2'u8:
        continue
      let rf = c.r.float32 / 255.0
      let gf = c.g.float32 / 255.0
      let bf = c.b.float32 / 255.0
      let redDominant = rf > 0.45 and rf > gf + 0.12 and rf > bf + 0.12
      if redDominant:
        result[x, y] = rgba(255'u8, 255'u8, 255'u8, c.a)
        inc outCount

proc main() =
  var created = 0
  for name in RoofMaskSprites:
    let srcPath = "data" / (name & ".png")
    if not fileExists(srcPath):
      echo "Missing source sprite: ", srcPath
      continue
    let src = readImage(srcPath)
    var maskCount = 0
    let mask = buildRoofMask(src, maskCount)
    if maskCount <= 0:
      echo "No roof pixels found for: ", name
      continue
    let outPath = "data" / ("roofmask." & name & ".png")
    writeFile(outPath, encodePng(mask))
    inc created
  echo "Roof masks generated: ", created

when isMainModule:
  main()
