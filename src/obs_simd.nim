## SIMD-optimized observation layer operations
## Uses nimsimd for vectorized memory operations on observation arrays.

when defined(amd64) or defined(i386):
  import nimsimd/sse2
  const HasSimd* = true
  const SimdWidth* = 16  # SSE2: 128-bit = 16 bytes
else:
  const HasSimd* = false
  const SimdWidth* = 1

import types

const
  ObsTileSize* = ObservationWidth * ObservationHeight  # 121 bytes per layer
  ObsAgentSize* = ObservationLayers * ObsTileSize      # ~11KB per agent
  ObsTotalSize* = MapAgents * ObsAgentSize             # ~11MB total

proc simdZeroAligned*(dst: pointer, bytes: int) {.inline.} =
  ## Zero memory using SIMD stores. Assumes 16-byte alignment.
  ## Falls back to regular zeroing on non-x86 platforms.
  when HasSimd:
    let zero = mm_setzero_si128()
    var p = cast[ptr M128i](dst)
    var remaining = bytes
    # Process 64 bytes (4 x 128-bit) per iteration for better throughput
    while remaining >= 64:
      mm_store_si128(p, zero)
      mm_store_si128(cast[ptr M128i](cast[int](p) + 16), zero)
      mm_store_si128(cast[ptr M128i](cast[int](p) + 32), zero)
      mm_store_si128(cast[ptr M128i](cast[int](p) + 48), zero)
      p = cast[ptr M128i](cast[int](p) + 64)
      remaining -= 64
    # Process remaining 16-byte chunks
    while remaining >= 16:
      mm_store_si128(p, zero)
      p = cast[ptr M128i](cast[int](p) + 16)
      remaining -= 16
    # Handle tail bytes
    if remaining > 0:
      var tail = cast[ptr UncheckedArray[uint8]](p)
      for i in 0 ..< remaining:
        tail[i] = 0
  else:
    zeroMem(dst, bytes)

proc simdZeroUnaligned*(dst: pointer, bytes: int) {.inline.} =
  ## Zero memory using SIMD stores. Handles unaligned memory.
  when HasSimd:
    let zero = mm_setzero_si128()
    var p = cast[ptr M128i](dst)
    var remaining = bytes
    # Process 64 bytes per iteration
    while remaining >= 64:
      mm_storeu_si128(p, zero)
      mm_storeu_si128(cast[ptr M128i](cast[int](p) + 16), zero)
      mm_storeu_si128(cast[ptr M128i](cast[int](p) + 32), zero)
      mm_storeu_si128(cast[ptr M128i](cast[int](p) + 48), zero)
      p = cast[ptr M128i](cast[int](p) + 64)
      remaining -= 64
    # Process remaining 16-byte chunks
    while remaining >= 16:
      mm_storeu_si128(p, zero)
      p = cast[ptr M128i](cast[int](p) + 16)
      remaining -= 16
    # Handle tail bytes
    if remaining > 0:
      var tail = cast[ptr UncheckedArray[uint8]](p)
      for i in 0 ..< remaining:
        tail[i] = 0
  else:
    zeroMem(dst, bytes)

proc simdZeroObservations*(obs: var array[MapAgents, array[ObservationLayers,
    array[ObservationWidth, array[ObservationHeight, uint8]]]]) {.inline.} =
  ## Zero the entire observations array using SIMD.
  ## Uses unaligned stores since the array may not be 16-byte aligned.
  simdZeroUnaligned(addr obs, sizeof(obs))

proc simdZeroAgentObs*(obs: var array[ObservationLayers,
    array[ObservationWidth, array[ObservationHeight, uint8]]]) {.inline.} =
  ## Zero a single agent's observation space (~11KB) using SIMD.
  simdZeroUnaligned(addr obs, sizeof(obs))

proc simdZeroLayer*(layer: var array[ObservationWidth,
    array[ObservationHeight, uint8]]) {.inline.} =
  ## Zero a single observation layer (121 bytes) using SIMD.
  simdZeroUnaligned(addr layer, sizeof(layer))

proc simdFillRow*(row: var array[ObservationHeight, uint8], value: uint8) {.inline.} =
  ## Fill an observation row (11 bytes) with a value.
  ## For small sizes, scalar is often faster than SIMD overhead.
  for i in 0 ..< ObservationHeight:
    row[i] = value

when HasSimd:
  proc simdCopyAligned*(dst, src: pointer, bytes: int) {.inline.} =
    ## Copy memory using SIMD loads/stores. Assumes 16-byte alignment.
    var pd = cast[ptr M128i](dst)
    var ps = cast[ptr M128i](src)
    var remaining = bytes
    # Process 64 bytes per iteration
    while remaining >= 64:
      let v0 = mm_load_si128(ps)
      let v1 = mm_load_si128(cast[ptr M128i](cast[int](ps) + 16))
      let v2 = mm_load_si128(cast[ptr M128i](cast[int](ps) + 32))
      let v3 = mm_load_si128(cast[ptr M128i](cast[int](ps) + 48))
      mm_store_si128(pd, v0)
      mm_store_si128(cast[ptr M128i](cast[int](pd) + 16), v1)
      mm_store_si128(cast[ptr M128i](cast[int](pd) + 32), v2)
      mm_store_si128(cast[ptr M128i](cast[int](pd) + 48), v3)
      pd = cast[ptr M128i](cast[int](pd) + 64)
      ps = cast[ptr M128i](cast[int](ps) + 64)
      remaining -= 64
    # Process remaining 16-byte chunks
    while remaining >= 16:
      mm_store_si128(pd, mm_load_si128(ps))
      pd = cast[ptr M128i](cast[int](pd) + 16)
      ps = cast[ptr M128i](cast[int](ps) + 16)
      remaining -= 16
    # Handle tail bytes
    if remaining > 0:
      var td = cast[ptr UncheckedArray[uint8]](pd)
      var ts = cast[ptr UncheckedArray[uint8]](ps)
      for i in 0 ..< remaining:
        td[i] = ts[i]

  proc simdCopyUnaligned*(dst, src: pointer, bytes: int) {.inline.} =
    ## Copy memory using SIMD loads/stores. Handles unaligned memory.
    var pd = cast[ptr M128i](dst)
    var ps = cast[ptr M128i](src)
    var remaining = bytes
    # Process 64 bytes per iteration
    while remaining >= 64:
      let v0 = mm_loadu_si128(ps)
      let v1 = mm_loadu_si128(cast[ptr M128i](cast[int](ps) + 16))
      let v2 = mm_loadu_si128(cast[ptr M128i](cast[int](ps) + 32))
      let v3 = mm_loadu_si128(cast[ptr M128i](cast[int](ps) + 48))
      mm_storeu_si128(pd, v0)
      mm_storeu_si128(cast[ptr M128i](cast[int](pd) + 16), v1)
      mm_storeu_si128(cast[ptr M128i](cast[int](pd) + 32), v2)
      mm_storeu_si128(cast[ptr M128i](cast[int](pd) + 48), v3)
      pd = cast[ptr M128i](cast[int](pd) + 64)
      ps = cast[ptr M128i](cast[int](ps) + 64)
      remaining -= 64
    # Process remaining 16-byte chunks
    while remaining >= 16:
      mm_storeu_si128(pd, mm_loadu_si128(ps))
      pd = cast[ptr M128i](cast[int](pd) + 16)
      ps = cast[ptr M128i](cast[int](ps) + 16)
      remaining -= 16
    # Handle tail bytes
    if remaining > 0:
      var td = cast[ptr UncheckedArray[uint8]](pd)
      var ts = cast[ptr UncheckedArray[uint8]](ps)
      for i in 0 ..< remaining:
        td[i] = ts[i]
else:
  proc simdCopyAligned*(dst, src: pointer, bytes: int) {.inline.} =
    copyMem(dst, src, bytes)

  proc simdCopyUnaligned*(dst, src: pointer, bytes: int) {.inline.} =
    copyMem(dst, src, bytes)

proc simdCopyObservations*(dst: ptr UncheckedArray[uint8],
    src: ptr array[MapAgents, array[ObservationLayers,
    array[ObservationWidth, array[ObservationHeight, uint8]]]]) {.inline.} =
  ## Copy entire observation array to external buffer using SIMD.
  simdCopyUnaligned(dst, src, ObsTotalSize)
