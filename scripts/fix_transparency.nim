import std/[os, sequtils, strutils, tables]
import pixie
import pixie/fileformats/png

type
  RGBA = tuple[r, g, b, a: uint8]

const SkipOpaque = [
  "floor",
  "wall",
  "wall.fill",
  "water",
  "sand",
  "snow",
  "grass",
  "fertile_tile",
  "dune",
  "road",
  "cave_floor",
  "dungeon_floor"
]

const ForceTransparent = [
  "farm",
  "mining_camp",
  "lumber_camp",
  "mill"
]

proc toTuple(c: ColorRGBA): RGBA =
  (c.r, c.g, c.b, c.a)

proc eqColor(a, b: RGBA, tol: int): bool =
  abs(a.r.int - b.r.int) <= tol and
  abs(a.g.int - b.g.int) <= tol and
  abs(a.b.int - b.b.int) <= tol and
  abs(a.a.int - b.a.int) <= tol

proc hasTransparency(img: Image, alphaThreshold: uint8): bool =
  for y in 0 ..< img.height:
    for x in 0 ..< img.width:
      if img[x, y].a < alphaThreshold:
        return true
  false

proc borderColors(img: Image): seq[RGBA] =
  result = @[]
  let w = img.width
  let h = img.height
  if w == 0 or h == 0:
    return
  for x in 0 ..< w:
    result.add(toTuple(img[x, 0]))
    if h > 1:
      result.add(toTuple(img[x, h - 1]))
  for y in 1 ..< max(1, h - 1):
    result.add(toTuple(img[0, y]))
    if w > 1:
      result.add(toTuple(img[w - 1, y]))

proc dominantBorderColor(colors: seq[RGBA], q: int): RGBA =
  var counts: Table[int, int]
  var reps: Table[int, RGBA]
  for c in colors:
    let key =
      (c.r.int div q) shl 24 or
      (c.g.int div q) shl 16 or
      (c.b.int div q) shl 8 or
      (c.a.int div q)
    counts[key] = counts.getOrDefault(key, 0) + 1
    if key notin reps:
      reps[key] = c
  var bestKey = -1
  var bestCount = -1
  for key, cnt in counts.pairs:
    if cnt > bestCount:
      bestCount = cnt
      bestKey = key
  if bestKey in reps:
    reps[bestKey]
  else:
    (0'u8, 0'u8, 0'u8, 0'u8)

proc floodFillTransparent(img: var Image, target: RGBA, tol: int): int =
  let w = img.width
  let h = img.height
  if w == 0 or h == 0:
    return 0
  var visited = newSeq[bool](w * h)
  var stack: seq[tuple[x, y: int]] = @[]
  template push(px, py: int) =
    if px >= 0 and px < w and py >= 0 and py < h:
      let idx = py * w + px
      if not visited[idx]:
        visited[idx] = true
        let c = toTuple(img[px, py])
        if eqColor(c, target, tol):
          stack.add((px, py))

  for x in 0 ..< w:
    push(x, 0)
    push(x, h - 1)
  for y in 0 ..< h:
    push(0, y)
    push(w - 1, y)

  var cleared = 0
  while stack.len > 0:
    let (x, y) = stack.pop()
    let c = toTuple(img[x, y])
    if not eqColor(c, target, tol):
      continue
    img[x, y] = rgba(c.r, c.g, c.b, 0'u8)
    inc cleared
    push(x + 1, y)
    push(x - 1, y)
    push(x, y + 1)
    push(x, y - 1)
  cleared

proc main() =
  let files = toSeq(walkDir("data")).filterIt(it.kind == pcFile and it.path.endsWith(".png")).mapIt(it.path)
  var noAlpha: seq[string] = @[]
  var fixed: seq[string] = @[]
  var skipped: seq[string] = @[]
  for path in files:
    let img = readImage(path)
    if hasTransparency(img, 250'u8):
      continue
    noAlpha.add(path)
    let key = path.extractFilename.replace(".png", "")
    if key in SkipOpaque:
      skipped.add(path)
      continue
    if key in ForceTransparent:
      var mutable = img
      let corner = toTuple(img[0, 0])
      let cleared = floodFillTransparent(mutable, corner, 24)
      if cleared > 0:
        writeFile(path, encodePng(mutable))
        fixed.add(path)
      else:
        skipped.add(path)
      continue

    let border = borderColors(img)
    if border.len == 0:
      skipped.add(path)
      continue
    let color = dominantBorderColor(border, 8)
    var near = 0
    for c in border:
      if eqColor(c, color, 12):
        inc near
    let coverage = near.float / border.len.float
    if coverage < 0.75:
      skipped.add(path)
      continue
    var mutable = img
    let cleared = floodFillTransparent(mutable, color, 12)
    if cleared == 0:
      skipped.add(path)
      continue
    writeFile(path, encodePng(mutable))
    fixed.add(path)

  echo "PNG total: ", files.len
  echo "No transparency: ", noAlpha.len
  echo "Fixed: ", fixed.len
  echo "Skipped: ", skipped.len
  if skipped.len > 0:
    echo "Skipped files:"
    for path in skipped:
      echo "  ", path

when isMainModule:
  main()
