const
  ConnectWallCost = 5
  ConnectTerrainCost = 6
  ConnectWaterCost = 50
  ConnectMaxEdgeCost = ConnectWaterCost

let ConnectDirs8 = [
  ivec2(-1, 0), ivec2(1, 0), ivec2(0, -1), ivec2(0, 1),
  ivec2(-1, -1), ivec2(1, -1), ivec2(-1, 1), ivec2(1, 1)
]

proc makeConnected*(env: Environment) =
  proc isPlayablePos(pos: IVec2): bool =
    pos.x >= MapBorder and pos.x < MapWidth - MapBorder and
      pos.y >= MapBorder and pos.y < MapHeight - MapBorder

  proc isPassableForConnect(env: Environment, pos: IVec2): bool =
    if not isValidPos(pos) or not isPlayablePos(pos):
      return false
    if not env.isEmpty(pos):
      return false
    if isBlockedTerrain(env.terrain[pos.x][pos.y]):
      return false
    true

  proc digCost(env: Environment, pos: IVec2): int =
    if not isValidPos(pos) or not isPlayablePos(pos):
      return int.high
    if isPassableForConnect(env, pos):
      return 1
    let thing = env.getThing(pos)
    if not isNil(thing):
      if thing.kind in {Wall, Tree, Wheat, Stubble, Stone, Gold, Bush, Cactus, Stalagmite, Stump}:
        return ConnectWallCost
      return int.high
    let terrain = env.terrain[pos.x][pos.y]
    if terrain == Water:
      return ConnectWaterCost
    if terrain in {Dune, Snow}:
      return ConnectTerrainCost
    if isBlockedTerrain(terrain):
      return ConnectTerrainCost
    1

  proc digCell(env: Environment, pos: IVec2) =
    if not isValidPos(pos) or not isPlayablePos(pos):
      return
    let thing = env.getThing(pos)
    if not isNil(thing):
      if thing.kind in {Wall, Tree, Wheat, Stubble, Stone, Gold, Bush, Cactus, Stalagmite, Stump}:
        removeThing(env, thing)
      else:
        return
    let terrain = env.terrain[pos.x][pos.y]
    if terrain in {Water, Dune, Snow}:
      env.terrain[pos.x][pos.y] = Empty
      env.resetTileColor(pos)

  proc labelComponents(env: Environment,
                       labels: var array[MapWidth, array[MapHeight, int16]],
                       counts: var seq[int]): int =
    labels = default(array[MapWidth, array[MapHeight, int16]])
    counts.setLen(0)
    var label = 0
    for x in MapBorder ..< MapWidth - MapBorder:
      for y in MapBorder ..< MapHeight - MapBorder:
        if labels[x][y] != 0 or not isPassableForConnect(env, ivec2(x, y)):
          continue
        inc label
        var queue: seq[IVec2] = @[ivec2(x, y)]
        var head = 0
        labels[x][y] = label.int16
        var count = 0
        while head < queue.len:
          let pos = queue[head]
          inc head
          inc count
          for d in ConnectDirs8:
            let nx = pos.x + d.x
            let ny = pos.y + d.y
            let npos = ivec2(nx.int32, ny.int32)
            if not isPassableForConnect(env, npos):
              continue
            if not env.canTraverseElevation(pos, npos):
              continue
            let ix = nx.int
            let iy = ny.int
            if labels[ix][iy] != 0:
              continue
            labels[ix][iy] = label.int16
            queue.add(npos)
        counts.add(count)
    label

  proc computeDistances(env: Environment,
                        labels: array[MapWidth, array[MapHeight, int16]],
                        sourceLabel: int16,
                        dist: var seq[int],
                        prev: var seq[int]) =
    let size = MapWidth * MapHeight
    let inf = size * ConnectMaxEdgeCost + 1
    dist.setLen(size)
    prev.setLen(size)
    for i in 0 ..< size:
      dist[i] = inf
      prev[i] = -1

    let bucketCount = ConnectMaxEdgeCost + 1
    var buckets: seq[seq[int]] = newSeq[seq[int]](bucketCount)
    var heads: seq[int] = newSeq[int](bucketCount)

    for x in MapBorder ..< MapWidth - MapBorder:
      for y in MapBorder ..< MapHeight - MapBorder:
        if labels[x][y] == sourceLabel:
          let idx = y * MapWidth + x
          dist[idx] = 0
          prev[idx] = -2
          buckets[0].add(idx)

    var processed = 0
    var currentCost = 0
    while processed < size and currentCost <= inf:
      let b = currentCost mod bucketCount
      if heads[b] >= buckets[b].len:
        inc currentCost
        continue
      let idx = buckets[b][heads[b]]
      inc heads[b]
      if dist[idx] < currentCost:
        continue
      inc processed
      let x = idx mod MapWidth
      let y = idx div MapWidth
      for d in ConnectDirs8:
        let nx = x + d.x.int
        let ny = y + d.y.int
        if nx < 0 or ny < 0 or nx >= MapWidth or ny >= MapHeight:
          continue
        let npos = ivec2(nx.int32, ny.int32)
        if not env.canTraverseElevation(ivec2(x.int32, y.int32), npos):
          continue
        let stepCost = digCost(env, npos)
        if stepCost == int.high:
          continue
        let nidx = ny * MapWidth + nx
        let newCost = currentCost + stepCost
        if newCost < dist[nidx]:
          dist[nidx] = newCost
          prev[nidx] = idx
          buckets[newCost mod bucketCount].add(nidx)

  var labels: array[MapWidth, array[MapHeight, int16]]
  var counts: seq[int] = @[]
  while true:
    let componentCount = labelComponents(env, labels, counts)
    if componentCount <= 1:
      break
    var largest = 0
    var largestCount = -1
    for i, count in counts:
      if count > largestCount:
        largestCount = count
        largest = i + 1
    var dist: seq[int] = @[]
    var prev: seq[int] = @[]
    computeDistances(env, labels, largest.int16, dist, prev)
    let inf = MapWidth * MapHeight * ConnectMaxEdgeCost + 1
    var anyDig = false
    for label in 1 .. componentCount:
      if label == largest:
        continue
      var bestIdx = -1
      var bestDist = inf
      for x in MapBorder ..< MapWidth - MapBorder:
        for y in MapBorder ..< MapHeight - MapBorder:
          if labels[x][y] != label.int16:
            continue
          let idx = y * MapWidth + x
          if dist[idx] < bestDist:
            bestDist = dist[idx]
            bestIdx = idx
      if bestIdx >= 0 and bestDist < inf:
        var cur = bestIdx
        while cur >= 0 and prev[cur] >= 0:
          let x = cur mod MapWidth
          let y = cur div MapWidth
          digCell(env, ivec2(x.int32, y.int32))
          cur = prev[cur]
        anyDig = true
    if not anyDig:
      break
