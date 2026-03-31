import unittest
import gui_assets

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
