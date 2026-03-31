import std/os
import unittest
import gui_assets

const
  PngHeaderSize = 24
  PngSignature = [
    char(0x89), 'P', 'N', 'G', '\r', '\n', char(0x1a), '\n'
  ]

proc readPngSize(path: string): tuple[width, height: int] =
  ## Read the PNG IHDR width and height from disk.
  var file: File
  if not open(file, path, fmRead):
    raise newException(IOError, "Could not open PNG: " & path)
  defer:
    file.close()
  var header: array[PngHeaderSize, char]
  let bytesRead = file.readChars(header.toOpenArray(0, header.high))
  if bytesRead != header.len:
    raise newException(IOError, "Incomplete PNG header: " & path)
  for i in 0 ..< PngSignature.len:
    if header[i] != PngSignature[i]:
      raise newException(ValueError, "Invalid PNG signature: " & path)
  if header[12] != 'I' or
    header[13] != 'H' or
    header[14] != 'D' or
    header[15] != 'R':
      raise newException(ValueError, "Missing IHDR chunk: " & path)
  result.width =
    (ord(header[16]) shl 24) or
    (ord(header[17]) shl 16) or
    (ord(header[18]) shl 8) or
    ord(header[19])
  result.height =
    (ord(header[20]) shl 24) or
    (ord(header[21]) shl 16) or
    (ord(header[22]) shl 8) or
    ord(header[23])

suite "GUI asset preload filtering":

  test "preloads gameplay sprites":
    check shouldPreloadGuiAsset("data/house.png")
    check guiAssetKey("data/house.png") == "house"
    check guiAssetKey("data/oriented/monk.s.png") == "oriented/monk.s"

  test "skips optional df_view exports":
    check not shouldPreloadGuiAsset("data/df_view/data/art/foo.png")
    check not shouldPreloadGuiAsset("df_view/data/art/foo.png")

  test "skips raw preview assets":
    check not shouldPreloadGuiAsset("data/tmp/oriented/monk.e.png")
    check not shouldPreloadGuiAsset("tmp/oriented/monk.e.png")

  test "skips abandoned silky atlas preload":
    check not shouldPreloadGuiAsset("data/silky.atlas.png")
    check not shouldPreloadGuiAsset("silky.atlas.png")

  test "preloaded gui assets stay within tile footprint":
    for path in walkDirRec("data"):
      if not shouldPreloadGuiAsset(path):
        continue
      let (width, height) = readPngSize(path)
      checkpoint(path & " is " & $width & "x" & $height)
      check width <= GuiAssetMaxEdge
      check height <= GuiAssetMaxEdge
