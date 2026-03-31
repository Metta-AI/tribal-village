## gui_assets.nim - GUI startup asset filtering helpers
##
## The GUI renderer should preload gameplay sprites, not raw generation
## previews or abandoned atlas artifacts that live under data/ for inspection.

import std/strutils

const
  GuiAssetSkipPrefixes* = [
    "df_view/",
    "tmp/",
  ]
  GuiAssetSkipPaths* = [
    "silky.atlas.png",
  ]

proc normalizeGuiAssetPath(path: string): string =
  result = path.replace('\\', '/')
  if result.startsWith("./"):
    result = result[2 .. ^1]
  if result.startsWith("data/"):
    result = result["data/".len .. ^1]

proc shouldPreloadGuiAsset*(path: string): bool =
  ## Return true when the GUI startup pass should decode and atlas this asset.
  let normalizedPath = normalizeGuiAssetPath(path)
  if not normalizedPath.endsWith(".png"):
    return false
  for prefix in GuiAssetSkipPrefixes:
    if normalizedPath.startsWith(prefix):
      return false
  for skippedPath in GuiAssetSkipPaths:
    if normalizedPath == skippedPath:
      return false
  true

proc guiAssetKey*(path: string): string =
  ## Convert a data/ PNG path into the boxy image key used by the renderer.
  result = normalizeGuiAssetPath(path)
  if result.endsWith(".png"):
    result.setLen(result.len - ".png".len)
