import std/sets

var assetKeys*: HashSet[string] = initHashSet[string]()

proc rememberAssetKey*(key: string) =
  assetKeys.incl(key)

proc assetExists*(key: string): bool =
  key in assetKeys

proc mapSpriteKey*(name: string): string =
  name

proc inventorySpriteKey*(name: string): string =
  name
