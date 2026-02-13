## environment_state.nim - Core state management for Environment
##
## This module contains error handling and FFI state management types and procedures.
## These are foundational utilities used throughout the environment module.


# ============================================================================
# Error types and FFI error state management
# ============================================================================

type
  TribalErrorKind* = enum
    ## Error categories for better diagnostics
    ErrNone = 0
    ErrMapFull = 1          ## No empty positions available for placement
    ErrInvalidPosition = 2  ## Position is out of bounds or invalid
    ErrResourceNotFound = 3 ## Required resource not found
    ErrInvalidState = 4     ## Invalid game state encountered
    ErrFFIError = 5         ## Error in FFI layer

  TribalError* = object of CatchableError
    ## Base exception type for tribal village errors
    kind*: TribalErrorKind
    details*: string

  FFIErrorState* = object
    ## Thread-local error state for FFI layer
    hasError*: bool
    errorCode*: TribalErrorKind
    errorMessage*: string

var lastFFIError*: FFIErrorState

proc clearFFIError*() =
  ## Clear the last FFI error state
  lastFFIError = FFIErrorState(hasError: false, errorCode: ErrNone, errorMessage: "")

proc newTribalError*(kind: TribalErrorKind, message: string): ref TribalError =
  ## Create a new tribal error with the given kind and message
  result = new(TribalError)
  result.kind = kind
  result.details = message
  result.msg = $kind & ": " & message

proc raiseMapFullError*() {.noreturn.} =
  ## Raise an error when the map is too full to place entities
  raise newTribalError(ErrMapFull, "Failed to find an empty position, map too full!")
