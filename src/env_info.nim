## Carry runtime environment parameters for lazy component initialization.

import
  std/tables,
  common_types, types

export types, common_types

const
  ## Store the total action count derived from verb and argument counts.
  ActionCount* = ActionVerbCount * ActionArgumentCount
  UnknownFeatureId = 255

type
  ## Describe one observation feature.
  FeatureProps* = object
    id*: int              ## Store the unique feature identifier.
    name*: string         ## Store the feature name.
    normalization*: float ## Store the feature normalization factor.

  ## Environment info passed to components for lazy initialization.
  ## Captures runtime environment parameters that components need to adapt to.
  EnvironmentInfo* = object
    ## Map dimensions (may differ from compile-time constants for variant support)
    mapWidth*: int
    mapHeight*: int

    ## Observation dimensions
    obsWidth*: int
    obsHeight*: int
    obsLayers*: int

    ## Agent/team configuration
    numAgents*: int
    numTeams*: int
    agentsPerTeam*: int

    ## Action space dimensions
    numActions*: int
    numActionVerbs*: int
    numActionArgs*: int

    ## Observation features (for feature remapping)
    obsFeatures*: seq[FeatureProps]

    ## Feature name to ID mapping (populated during initialization)
    featureNameToId*: Table[string, int]

    ## Original feature mapping (for policy portability)
    originalFeatureMapping*: Table[string, int]

    ## Flag indicating if this info has been initialized
    initialized*: bool

  ## Result of initializeToEnvironment call
  InitResult* = object
    success*: bool
    message*: string

## Describe components that support lazy environment initialization.
type
  InitializableComponent* = concept c
    c.initializeToEnvironment(EnvironmentInfo) is InitResult

proc newEnvironmentInfo*(): EnvironmentInfo =
  ## Create an uninitialized EnvironmentInfo.
  ## Call initFromEnvironment() to populate from an actual environment.
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
    initialized: false
  )

proc defaultEnvironmentInfo*(): EnvironmentInfo =
  ## Create EnvironmentInfo with compile-time default values.
  ## Used when no runtime configuration is needed.
  result = EnvironmentInfo(
    mapWidth: MapWidth,
    mapHeight: MapHeight,
    obsWidth: ObservationWidth,
    obsHeight: ObservationHeight,
    obsLayers: ObservationLayers,
    numAgents: MapAgents,
    numTeams: MapRoomObjectsTeams,
    agentsPerTeam: MapAgentsPerTeam,
    numActions: ActionCount,
    numActionVerbs: ActionVerbCount,
    numActionArgs: ActionArgumentCount,
    obsFeatures: @[],
    featureNameToId: initTable[string, int](),
    originalFeatureMapping: initTable[string, int](),
    initialized: true
  )

  # Populate observation features from the ObservationName enum.
  for layer in ObservationName:
    let props = FeatureProps(
      id: ord(layer),
      name: $layer,
      normalization: 1.0
    )
    result.obsFeatures.add(props)
    result.featureNameToId[$layer] = ord(layer)

proc isValid*(info: EnvironmentInfo): bool =
  ## Check if the environment info has valid dimensions.
  info.initialized and
    info.mapWidth > 0 and
    info.mapHeight > 0 and
    info.numAgents > 0

proc obsRadius*(info: EnvironmentInfo): int =
  ## Calculate observation radius from observation width.
  info.obsWidth div 2

proc getFeatureId*(info: EnvironmentInfo, name: string): int =
  ## Get feature ID by name, returning -1 if not found.
  if name in info.featureNameToId:
    return info.featureNameToId[name]
  return -1

proc getFeatureNormalization*(info: EnvironmentInfo, featureId: int): float =
  ## Get normalization factor for a feature ID.
  for feature in info.obsFeatures:
    if feature.id == featureId:
      return feature.normalization
  return 1.0

proc hasFeature*(info: EnvironmentInfo, name: string): bool =
  ## Check if a feature exists by name.
  name in info.featureNameToId

proc storeOriginalMapping*(info: var EnvironmentInfo) =
  ## Store the current feature mapping as the original.
  ## Called during first initialization to establish baseline.
  info.originalFeatureMapping = info.featureNameToId

proc createFeatureRemapping*(
  info: EnvironmentInfo,
  currentFeatures: seq[FeatureProps]
): Table[int, int] =
  ## Create a remapping from current feature IDs to original IDs.
  ## This enables policy portability across environments with different feature orderings.
  result = initTable[int, int]()

  for feature in currentFeatures:
    if feature.name in info.originalFeatureMapping:
      let originalId = info.originalFeatureMapping[feature.name]
      if feature.id != originalId:
        result[feature.id] = originalId
    else:
      # Map unknown features to the sentinel ID.
      result[feature.id] = UnknownFeatureId
