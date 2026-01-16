import std/[json, os, tables]
import zippy
import types, items, registry

const
  ReplayVersion = 3
  DefaultReplayBaseName = "tribal_village"
  ReplayActionNames: array[ActionVerbCount, string] = [
    "noop",
    "move",
    "attack",
    "use",
    "swap",
    "put",
    "plant_lantern",
    "plant_resource",
    "build",
    "orient"
  ]

type
  ReplaySeries = object
    hasLast: bool
    last: JsonNode
    changes: seq[tuple[step: int, value: JsonNode]]

  ReplayObject = ref object
    id: int
    constFields: Table[string, JsonNode]
    series: Table[string, ReplaySeries]
    active: bool

  ReplayWriter* = ref object
    enabled*: bool
    baseDir: string
    basePath: string
    baseName: string
    label: string
    episodeIndex: int
    outputPath: string
    fileName: string
    nextId: int
    thingIds: Table[pointer, int]
    objects: seq[ReplayObject]
    totalRewards: array[MapAgents, float32]
    lastInvalidCounts: array[MapAgents, int]
    maxStep: int
    active: bool

var replayWriter*: ReplayWriter = nil

proc toReplayTypeName(kind: ThingKind): string =
  buildingSpriteKey(kind)

proc buildItemNames(): JsonNode =
  result = newJArray()
  for kind in ItemKind:
    result.add(newJString(itemKindName(kind)))

proc buildTypeNames(): JsonNode =
  result = newJArray()
  for kind in ThingKind:
    result.add(newJString(toReplayTypeName(kind)))

proc buildActionNames(): JsonNode =
  result = newJArray()
  for name in ReplayActionNames:
    result.add(newJString(name))

proc ensureWriter(): ReplayWriter =
  if not replayWriter.isNil:
    return replayWriter
  let basePath = getEnv("TV_REPLAY_PATH", "")
  let baseDir = getEnv("TV_REPLAY_DIR", "")
  if basePath.len == 0 and baseDir.len == 0:
    return nil
  let baseName = getEnv("TV_REPLAY_NAME", DefaultReplayBaseName)
  let label = getEnv("TV_REPLAY_LABEL", "Tribal Village Replay")
  replayWriter = ReplayWriter(
    enabled: true,
    baseDir: baseDir,
    basePath: basePath,
    baseName: baseName,
    label: label
  )
  replayWriter

proc resetEpisode(writer: ReplayWriter) =
  writer.thingIds.clear()
  writer.objects.setLen(0)
  writer.nextId = 1
  writer.totalRewards = default(array[MapAgents, float32])
  writer.lastInvalidCounts = default(array[MapAgents, int])
  writer.maxStep = -1
  writer.active = true

proc computeOutputPath(writer: ReplayWriter) =
  if writer.basePath.len > 0:
    writer.outputPath = writer.basePath
  else:
    let suffix = "_" & $writer.episodeIndex
    let fileName = writer.baseName & suffix & ".json.z"
    if writer.baseDir.len > 0:
      writer.outputPath = writer.baseDir / fileName
    else:
      writer.outputPath = fileName
  writer.fileName = extractFilename(writer.outputPath)

proc maybeStartReplayEpisode*(env: Environment) =
  discard env
  let writer = ensureWriter()
  if writer.isNil:
    return
  inc writer.episodeIndex
  writer.resetEpisode()
  writer.computeOutputPath()

proc seriesAdd(series: var ReplaySeries, step: int, value: JsonNode) =
  if not series.hasLast:
    series.changes.add((step: step, value: value))
    series.last = value
    series.hasLast = true
    return
  if series.last != value:
    series.changes.add((step: step, value: value))
    series.last = value

proc addSeries(obj: ReplayObject, key: string, step: int, value: JsonNode) =
  var series = obj.series.mgetOrPut(key, ReplaySeries())
  series.seriesAdd(step, value)
  obj.series[key] = series

proc inventoryNode(thing: Thing): JsonNode =
  result = newJArray()
  for kind in ItemKind:
    if kind == ikNone:
      continue
    let count = getInv(thing, kind)
    if count <= 0:
      continue
    var pair = newJArray()
    pair.add(newJInt(kind.int))
    pair.add(newJInt(count))
    result.add(pair)

proc locationNode(pos: IVec2): JsonNode =
  result = newJArray()
  result.add(newJInt(pos.x))
  result.add(newJInt(pos.y))

proc ensureReplayObject(writer: ReplayWriter, thing: Thing): ReplayObject =
  let key = cast[pointer](thing)
  var objectId = writer.thingIds.getOrDefault(key, 0)
  if objectId == 0:
    objectId = writer.nextId
    inc writer.nextId
    writer.thingIds[key] = objectId
  if writer.objects.len < objectId:
    writer.objects.setLen(objectId)
  if writer.objects[objectId - 1].isNil:
    let obj = ReplayObject(id: objectId)
    obj.constFields = initTable[string, JsonNode]()
    obj.series = initTable[string, ReplaySeries]()
    obj.constFields["id"] = newJInt(objectId)
    obj.constFields["type_name"] = newJString(toReplayTypeName(thing.kind))
    if thing.kind == Agent:
      obj.constFields["agent_id"] = newJInt(thing.agentId)
      obj.constFields["group_id"] = newJInt(getTeamId(thing))
      obj.constFields["inventory_max"] = newJInt(MapObjectAgentMaxInventory)
    elif thing.barrelCapacity > 0:
      obj.constFields["inventory_max"] = newJInt(thing.barrelCapacity)
    else:
      obj.constFields["inventory_max"] = newJInt(0)
    writer.objects[objectId - 1] = obj
  writer.objects[objectId - 1]

proc actionSuccess(writer: ReplayWriter, agentId: int, env: Environment): bool =
  if agentId < 0 or agentId >= env.stats.len:
    return false
  let invalidNow = env.stats[agentId].actionInvalid
  let success = invalidNow == writer.lastInvalidCounts[agentId]
  writer.lastInvalidCounts[agentId] = invalidNow
  success

proc resolveColor(thing: Thing): int =
  if thing.kind == Agent:
    return getTeamId(thing)
  if isBuildingKind(thing.kind):
    return max(0, thing.teamId)
  if thing.kind in {Lantern, Door, Outpost, GuardTower, TownCenter, Castle, Altar}:
    return max(0, thing.teamId)
  0

proc maybeLogReplayStep*(env: Environment, actions: ptr array[MapAgents, uint8]) =
  let writer = replayWriter
  if writer.isNil or not writer.active:
    return
  let stepIndex = env.currentStep - 1
  if stepIndex < 0:
    return
  writer.maxStep = max(writer.maxStep, stepIndex)

  var seen: seq[bool] = @[]

  for thing in env.things:
    if thing.isNil:
      continue
    let obj = writer.ensureReplayObject(thing)
    let idx = obj.id - 1
    if idx >= seen.len:
      let oldLen = seen.len
      seen.setLen(idx + 1)
      for i in oldLen ..< seen.len:
        seen[i] = false
    seen[idx] = true
    obj.active = true

    obj.addSeries("location", stepIndex, locationNode(thing.pos))
    obj.addSeries("orientation", stepIndex, newJInt(thing.orientation.int))
    obj.addSeries("inventory", stepIndex, inventoryNode(thing))
    obj.addSeries("color", stepIndex, newJInt(resolveColor(thing)))

    if thing.kind == Agent:
      let agentId = thing.agentId
      let actionValue = actions[][agentId]
      let verb = actionValue.int div ActionArgumentCount
      let arg = actionValue.int mod ActionArgumentCount
      obj.addSeries("action_id", stepIndex, newJInt(verb))
      obj.addSeries("action_param", stepIndex, newJInt(arg))
      obj.addSeries("action_success", stepIndex, newJBool(writer.actionSuccess(agentId, env)))
      obj.addSeries("current_reward", stepIndex, newJFloat(thing.reward.float))
      writer.totalRewards[agentId] += thing.reward
      obj.addSeries("total_reward", stepIndex, newJFloat(writer.totalRewards[agentId].float))
      obj.addSeries("is_frozen", stepIndex, newJBool(thing.frozen > 0))

  for idx, obj in writer.objects:
    if obj.isNil:
      continue
    if idx >= seen.len or not seen[idx]:
      if obj.active:
        obj.active = false
        obj.addSeries("location", stepIndex, locationNode(ivec2(-1, -1)))

proc seriesToJson(series: ReplaySeries): JsonNode =
  result = newJArray()
  for change in series.changes:
    var pair = newJArray()
    pair.add(newJInt(change.step))
    pair.add(change.value)
    result.add(pair)

proc buildReplayJson(writer: ReplayWriter, env: Environment): JsonNode =
  result = newJObject()
  result["version"] = newJInt(ReplayVersion)
  result["action_names"] = buildActionNames()
  result["item_names"] = buildItemNames()
  result["type_names"] = buildTypeNames()
  result["num_agents"] = newJInt(MapAgents)
  let maxSteps = if writer.maxStep >= 0: writer.maxStep + 1 else: 0
  result["max_steps"] = newJInt(maxSteps)
  var mapSize = newJArray()
  mapSize.add(newJInt(MapWidth))
  mapSize.add(newJInt(MapHeight))
  result["map_size"] = mapSize
  result["file_name"] = newJString(writer.fileName)
  var mgConfig = newJObject()
  mgConfig["label"] = newJString(writer.label)
  result["mg_config"] = mgConfig

  var objectsArr = newJArray()
  for obj in writer.objects:
    if obj.isNil:
      continue
    var objNode = newJObject()
    for key, value in obj.constFields:
      objNode[key] = value
    for key, series in obj.series:
      objNode[key] = seriesToJson(series)
    objectsArr.add(objNode)
  result["objects"] = objectsArr

proc maybeFinalizeReplay*(env: Environment) =
  discard env
  let writer = replayWriter
  if writer.isNil or not writer.active:
    return
  let data = buildReplayJson(writer, env)
  let jsonData = $data
  let compressed = zippy.compress(jsonData, dataFormat = dfZlib)
  if writer.outputPath.len > 0:
    let dir = parentDir(writer.outputPath)
    if dir.len > 0:
      createDir(dir)
    writeFile(writer.outputPath, compressed)
  writer.active = false
