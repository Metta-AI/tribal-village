## Runtime environment metadata for lazy component initialization.

import
  std/[tables],
  common_types,
  types

export types, common_types

const
  ActionCount* = ActionVerbCount * ActionArgumentCount
    ## Total action count derived from verbs and arguments.
  UnknownFeatureId = 255
    ## Sentinel ID for features absent from the original mapping.

type
  FeatureProps* = object
    ## Descriptor for one observation feature.
    id*: int
      ## Unique feature identifier.
    name*: string
      ## Feature name.
    normalization*: float
      ## Normalization factor for the feature.

  EnvironmentInfo* = object
    ## Runtime environment parameters passed to lazy components.
    mapWidth*: int
      ## Runtime map width.
    mapHeight*: int
      ## Runtime map height.
    obsWidth*: int
      ## Observation width.
    obsHeight*: int
      ## Observation height.
    obsLayers*: int
      ## Observation layer count.
    numAgents*: int
      ## Total agent count.
    numTeams*: int
      ## Total team count.
    agentsPerTeam*: int
      ## Agent count per team.
    numActions*: int
      ## Total action count.
    numActionVerbs*: int
      ## Action verb count.
    numActionArgs*: int
      ## Action argument count.
    obsFeatures*: seq[FeatureProps]
      ## Observation feature descriptors.
    featureNameToId*: Table[string, int]
      ## Mapping from feature name to feature ID.
    originalFeatureMapping*: Table[string, int]
      ## Baseline feature mapping for policy portability.
    initialized*: bool
      ## Whether the structure has been initialized.

  InitResult* = object
    ## Result of an environment initialization attempt.
    success*: bool
    message*: string

  InitializableComponent* = concept c
    ## Component that supports lazy environment initialization.
    c.initializeToEnvironment(EnvironmentInfo) is InitResult

proc addDefaultObservationFeatures(info: var EnvironmentInfo) =
  ## Populates observation feature metadata from `ObservationName`.
  for layer in ObservationName:
    let props = FeatureProps(
      id: ord(layer),
      name: $layer,
      normalization: 1.0,
    )
    info.obsFeatures.add(props)
    info.featureNameToId[$layer] = ord(layer)

proc newEnvironmentInfo*(): EnvironmentInfo =
  ## Creates an uninitialized `EnvironmentInfo`.
  result = EnvironmentInfo(
    mapWidth: 0,
    mapHeight: 0,
    obsWidth: 0,
    obsHeight: 0,
    obsLayers: 0,
    numAgents: 0,
    numTeams: 0,
    agentsPerTeam: 0,
    numActions: 0,
    numActionVerbs: 0,
    numActionArgs: 0,
    obsFeatures: @[],
    featureNameToId: initTable[string, int](),
    originalFeatureMapping: initTable[string, int](),
    initialized: false,
  )

proc defaultEnvironmentInfo*(): EnvironmentInfo =
  ## Creates `EnvironmentInfo` with compile-time default values.
  result = newEnvironmentInfo()
  result.mapWidth = MapWidth
  result.mapHeight = MapHeight
  result.obsWidth = ObservationWidth
  result.obsHeight = ObservationHeight
  result.obsLayers = ObservationLayers
  result.numAgents = MapAgents
  result.numTeams = MapRoomObjectsTeams
  result.agentsPerTeam = MapAgentsPerTeam
  result.numActions = ActionCount
  result.numActionVerbs = ActionVerbCount
  result.numActionArgs = ActionArgumentCount
  result.initialized = true
  result.addDefaultObservationFeatures()

proc isValid*(info: EnvironmentInfo): bool =
  ## Returns whether the environment info has valid dimensions.
  info.initialized and
    info.mapWidth > 0 and
    info.mapHeight > 0 and
    info.numAgents > 0

proc obsRadius*(info: EnvironmentInfo): int =
  ## Returns the observation radius derived from observation width.
  info.obsWidth div 2

proc getFeatureId*(info: EnvironmentInfo, name: string): int =
  ## Returns a feature ID by name, or `-1` when it is absent.
  if name in info.featureNameToId:
    return info.featureNameToId[name]
  -1

proc getFeatureNormalization*(info: EnvironmentInfo, featureId: int): float =
  ## Returns the normalization factor for one feature ID.
  for feature in info.obsFeatures:
    if feature.id == featureId:
      return feature.normalization
  1.0

proc hasFeature*(info: EnvironmentInfo, name: string): bool =
  ## Returns whether the named feature exists.
  name in info.featureNameToId

proc storeOriginalMapping*(info: var EnvironmentInfo) =
  ## Stores the current feature mapping as the baseline mapping.
  info.originalFeatureMapping = info.featureNameToId

proc createFeatureRemapping*(
  info: EnvironmentInfo,
  currentFeatures: seq[FeatureProps]
): Table[int, int] =
  ## Creates a remapping from current feature IDs to original IDs.
  result = initTable[int, int]()
  for feature in currentFeatures:
    if feature.name in info.originalFeatureMapping:
      let originalId = info.originalFeatureMapping[feature.name]
      if feature.id != originalId:
        result[feature.id] = originalId
    else:
      result[feature.id] = UnknownFeatureId
