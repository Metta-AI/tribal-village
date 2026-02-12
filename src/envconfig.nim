## envconfig.nim - Centralized environment variable parsing with consistent error handling
##
## Provides safe parsing functions for environment configuration variables.
## Logs warnings when parsing fails instead of silently using fallbacks.
## Import this module early to make utilities available to included files.
##
## Usage:
##   import envconfig
##   let interval = parseEnvInt("TV_INTERVAL", 100)
##   let enabled = parseEnvBool("TV_ENABLED", false)

import std/[os, strutils, tables]

const
  ## Set to true to enable debug logging for env var parsing
  EnvConfigDebug* = false

proc parseEnvInt*(envVar: string, fallback: int): int =
  ## Parse an integer from an environment variable with logging on failure.
  ## Returns `fallback` if the variable is empty or invalid.
  let raw = getEnv(envVar, "")
  if raw.len == 0:
    return fallback
  try:
    result = parseInt(raw)
  except ValueError:
    when EnvConfigDebug:
      echo "[envconfig] Warning: Failed to parse ", envVar, "='", raw,
           "' as int, using fallback=", fallback
    result = fallback

proc parseEnvIntRaw*(raw: string, fallback: int, envVar: string = ""): int =
  ## Parse an integer from a raw string value with logging on failure.
  ## Use this when you already have the raw value from getEnv.
  if raw.len == 0:
    return fallback
  try:
    result = parseInt(raw)
  except ValueError:
    when EnvConfigDebug:
      let varInfo = if envVar.len > 0: envVar & "=" else: ""
      echo "[envconfig] Warning: Failed to parse ", varInfo, "'", raw,
           "' as int, using fallback=", fallback
    result = fallback

proc parseEnvBool*(envVar: string, fallback: bool): bool =
  ## Parse a boolean from an environment variable.
  ## Recognizes: "1", "true", "yes", "on" as true
  ##             "0", "false", "no", "off", "" as false
  let raw = getEnv(envVar, "").toLowerAscii
  if raw in ["1", "true", "yes", "on"]:
    return true
  elif raw in ["0", "false", "no", "off", ""]:
    return false
  else:
    when EnvConfigDebug:
      echo "[envconfig] Warning: Unrecognized bool value ", envVar, "='", raw,
           "', using fallback=", fallback
    return fallback

proc parseEnvFloat*(envVar: string, fallback: float): float =
  ## Parse a float from an environment variable with logging on failure.
  let raw = getEnv(envVar, "")
  if raw.len == 0:
    return fallback
  try:
    result = parseFloat(raw)
  except ValueError:
    when EnvConfigDebug:
      echo "[envconfig] Warning: Failed to parse ", envVar, "='", raw,
           "' as float, using fallback=", fallback
    result = fallback

proc initStringIntTable*(capacity: int = 16): Table[string, int] =
  ## Initialize a string->int table with pre-allocated capacity to avoid rehashing.
  ## Default capacity of 16 covers most audit use cases (damage types, unit types, resources).
  result = initTable[string, int](capacity)
