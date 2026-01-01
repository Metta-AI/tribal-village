import std/sets

var assetKeys*: HashSet[string] = initHashSet[string]()

proc rememberAssetKey*(key: string) =
  assetKeys.incl(key)

proc assetExists*(key: string): bool =
  key in assetKeys

proc mapSpriteKey*(name: string): string =
  let mapKey = "map/" & name
  if mapKey in assetKeys:
    return mapKey
  let invKey = "inventory/" & name
  if invKey in assetKeys:
    return invKey
  mapKey

proc inventorySpriteKey*(name: string): string =
  let invKey = "inventory/" & name
  if invKey in assetKeys:
    return invKey
  let mapKey = "map/" & name
  if mapKey in assetKeys:
    return mapKey
  invKey
