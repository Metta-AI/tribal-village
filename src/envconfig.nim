## Parse environment configuration values with typed errors and fallbacks.

import std/[os, strutils, tables]

const
  ## Set to true to enable debug logging for environment parsing.
  EnvConfigDebug* = false

type
  EnvConfigError* = object of CatchableError
    ## Describe an environment parsing failure.

proc raiseEnvConfigError(
  envVar: string,
  raw: string,
  expected: string
) {.noreturn.} =
  ## Raise an EnvConfigError for an invalid environment value.
  let value =
    if raw.len == 0:
      "<empty>"
    else:
      raw
  raise newException(
    EnvConfigError,
    "Failed to parse " & envVar & "='" & value & "' as " & expected & "."
  )

proc logEnvConfigFallback(
  envVar: string,
  raw: string,
  expected: string,
  fallback: string
) =
  ## Log an environment fallback when debug output is enabled.
  when EnvConfigDebug:
    let value =
      if raw.len == 0:
        "<empty>"
      else:
        raw
    echo "[envconfig] Failed to parse ", envVar, "='", value, "' as ",
      expected, ", using fallback=", fallback

proc parseIntValue(envVar: string, raw: string): int =
  ## Parse an integer environment value or raise EnvConfigError.
  try:
    result = parseInt(raw)
  except ValueError:
    raiseEnvConfigError(envVar, raw, "int")

proc parseBoolValue(envVar: string, raw: string): bool =
  ## Parse a boolean environment value or raise EnvConfigError.
  let normalized = raw.toLowerAscii
  case normalized
  of "1", "true", "yes", "on":
    return true
  of "0", "false", "no", "off":
    return false
  else:
    raiseEnvConfigError(envVar, raw, "bool")

proc parseFloatValue(envVar: string, raw: string): float =
  ## Parse a float environment value or raise EnvConfigError.
  try:
    result = parseFloat(raw)
  except ValueError:
    raiseEnvConfigError(envVar, raw, "float")

proc parseEnvInt*(envVar: string, fallback: int): int =
  ## Parse an integer from an environment variable with logging on failure.
  ## Return the fallback when the variable is empty or invalid.
  let raw = getEnv(envVar, "")
  if raw.len == 0:
    return fallback
  try:
    result = parseIntValue(envVar, raw)
  except EnvConfigError:
    logEnvConfigFallback(envVar, raw, "int", $fallback)
    result = fallback

proc parseEnvBool*(envVar: string, fallback: bool): bool =
  ## Parse a boolean from an environment variable.
  ## Return the fallback when the variable is empty or invalid.
  let raw = getEnv(envVar, "")
  if raw.len == 0:
    return fallback
  try:
    result = parseBoolValue(envVar, raw)
  except EnvConfigError:
    logEnvConfigFallback(envVar, raw, "bool", $fallback)
    result = fallback

proc parseEnvFloat*(envVar: string, fallback: float): float =
  ## Parse a float from an environment variable with logging on failure.
  let raw = getEnv(envVar, "")
  if raw.len == 0:
    return fallback
  try:
    result = parseFloatValue(envVar, raw)
  except EnvConfigError:
    logEnvConfigFallback(envVar, raw, "float", $fallback)
    result = fallback

proc parseEnvString*(envVar: string, fallback: string): string =
  ## Parse a string from an environment variable.
  let raw = getEnv(envVar, "")
  if raw.len == 0:
    return fallback
  return raw

proc initStringIntTable*(capacity: int = 16): Table[string, int] =
  ## Initialize a string-to-int table with pre-allocated capacity.
  result = initTable[string, int](capacity)
