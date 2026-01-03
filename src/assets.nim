import std/sets

var assetKeys*: HashSet[string] = initHashSet[string]()

proc rememberAssetKey*(key: string) =
  assetKeys.incl(key)

proc assetExists*(key: string): bool =
  key in assetKeys
