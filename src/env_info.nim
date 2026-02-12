## env_info.nim - Environment-aware lazy initialization pattern
##
## This module implements the initialize_to_environment() pattern from mettascope.
## Components can adapt to runtime environment parameters (board size, action counts,
## observation features) instead of hardcoding game variants at compile time.
##
## The pattern enables:
## - Policy portability across different environment configurations
## - Runtime feature remapping for agent transferability
## - Lazy initialization when actual environment dimensions are known
##
## Usage:
##   # Create component with placeholders
##   var component = newObsProcessor()
##
##   # Later, when environment is available:
##   component.initializeToEnvironment(envInfo)
##
## Reference: metta/agent/components/obs_shim.py

import std/tables
import types, common_types

export types, common_types

const
  ## Total action count derived from verb and argument counts
  ActionCount* = ActionVerbCount * ActionArgumentCount

type
  ## Feature properties for observation encoding
  FeatureProps* = object
    id*: int              ## Unique feature identifier
    name*: string         ## Feature name (e.g., "TerrainEmptyLayer")
    normalization*: float ## Normalization factor for this feature

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

## Concept for components that support lazy environment initialization.
## Components implementing this pattern can adapt to runtime environment params.
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

  # Populate observation features from ObservationName enum
  for layer in ObservationName:
    let props = FeatureProps(
      id: ord(layer),
      name: $layer,
      normalization: 1.0  # Default normalization
    )
    result.obsFeatures.add(props)
    result.featureNameToId[$layer] = ord(layer)

proc initResult*(success: bool, message: string = ""): InitResult =
  InitResult(success: success, message: message)

proc successResult*(message: string = "Initialized successfully"): InitResult =
  initResult(true, message)

proc errorResult*(message: string): InitResult =
  initResult(false, message)

## Helper procs for common environment info queries

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
  for feat in info.obsFeatures:
    if feat.id == featureId:
      return feat.normalization
  return 1.0  # Default normalization

proc hasFeature*(info: EnvironmentInfo, name: string): bool =
  ## Check if a feature exists by name.
  name in info.featureNameToId

## Feature remapping support for policy portability

proc storeOriginalMapping*(info: var EnvironmentInfo) =
  ## Store the current feature mapping as the original.
  ## Called during first initialization to establish baseline.
  info.originalFeatureMapping = info.featureNameToId

proc createFeatureRemapping*(info: EnvironmentInfo,
                              currentFeatures: seq[FeatureProps]): Table[int, int] =
  ## Create a remapping from current feature IDs to original IDs.
  ## This enables policy portability across environments with different feature orderings.
  result = initTable[int, int]()
  const UnknownFeatureId = 255

  for feat in currentFeatures:
    if feat.name in info.originalFeatureMapping:
      let originalId = info.originalFeatureMapping[feat.name]
      if feat.id != originalId:
        result[feat.id] = originalId
    else:
      # Unknown feature - map to unknown ID
      result[feat.id] = UnknownFeatureId
