## gui_assets.nim - GUI startup asset filtering helpers
##
## The GUI renderer should preload gameplay sprites, not raw generation
## previews or abandoned atlas artifacts that live under data/ for inspection.

import std/strutils

const
  GuiAssetMaxEdge* = 256
  GuiAssetPngExtension = ".png"
  GuiAssetSkipPrefixes* = [
    "df_view/",
    "tmp/",
  ]
  GuiAssetSkipPaths* = [
    "silky.atlas.png",
  ]

proc normalizeGuiAssetPath(path: string): string =
  ## Normalize a GUI asset path to a data-relative forward-slash path.
  result = path.replace('\\', '/')
  if result.startsWith("./"):
    result = result[2 .. ^1]
  if result.startsWith("data/"):
    result = result["data/".len .. ^1]

proc shouldSkipGuiAsset(path: string): bool =
  ## Return true when the normalized path is outside the GUI preload set.
  for prefix in GuiAssetSkipPrefixes:
    if path.startsWith(prefix):
      return true
  for skippedPath in GuiAssetSkipPaths:
    if path == skippedPath:
      return true
  false

proc shouldPreloadGuiAsset*(path: string): bool =
  ## Return true when the GUI startup pass should decode and atlas this asset.
  let normalizedPath = normalizeGuiAssetPath(path)
  if not normalizedPath.endsWith(GuiAssetPngExtension):
    return false
  not shouldSkipGuiAsset(normalizedPath)

proc guiAssetKey*(path: string): string =
  ## Convert a data/ PNG path into the boxy image key used by the renderer.
  result = normalizeGuiAssetPath(path)
  if result.endsWith(GuiAssetPngExtension):
    result.setLen(result.len - GuiAssetPngExtension.len)
