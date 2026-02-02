## SIMD-optimized observation layer operations
## Uses AVX2 for vectorized memory operations (32 bytes per cycle)

import nimsimd/avx2, nimsimd/avx, nimsimd/sse2
import ./types

when defined(gcc) or defined(clang):
  {.passC: "-mavx2".}

when defined(release):
  {.push checks: off.}

const
  # Pre-computed strides for observation buffer layout
  ObsTileStride* = ObservationWidth * ObservationHeight
  ObsAgentStride* = ObservationLayers * ObsTileStride
  ObsBufferSize* = MapAgents * ObsAgentStride

proc simdZeroObservations*(observations: ptr UncheckedArray[uint8]) {.inline.} =
  ## Zero the entire observation buffer using AVX2.
  ## Processes 256 bytes per iteration (8x 256-bit stores).
  let
    vecZero = mm256_setzero_si256()
    totalBytes = ObsBufferSize
  var p = cast[uint](observations)

  # Handle initial unaligned bytes
  while (p and 31) != 0 and (p - cast[uint](observations)) < totalBytes.uint:
    cast[ptr uint8](p)[] = 0
    inc p

  let remaining = totalBytes - int(p - cast[uint](observations))
  let iterations = remaining div 256  # 8 x 32-byte stores per iteration

  for _ in 0 ..< iterations:
    # Unroll 8 stores per iteration for better throughput
    mm256_store_si256(cast[pointer](p), vecZero)
    mm256_store_si256(cast[pointer](p + 32), vecZero)
    mm256_store_si256(cast[pointer](p + 64), vecZero)
    mm256_store_si256(cast[pointer](p + 96), vecZero)
    mm256_store_si256(cast[pointer](p + 128), vecZero)
    mm256_store_si256(cast[pointer](p + 160), vecZero)
    mm256_store_si256(cast[pointer](p + 192), vecZero)
    mm256_store_si256(cast[pointer](p + 224), vecZero)
    p += 256

  # Handle remaining aligned 32-byte chunks
  let remaining32 = (remaining mod 256) div 32
  for _ in 0 ..< remaining32:
    mm256_store_si256(cast[pointer](p), vecZero)
    p += 32

  # Handle remaining bytes
  let tailBytes = remaining mod 32
  for _ in 0 ..< tailBytes:
    cast[ptr uint8](p)[] = 0
    inc p

proc simdCopyObservations*(dst, src: ptr UncheckedArray[uint8]) {.inline.} =
  ## Copy observation buffer using AVX2 with streaming stores.
  ## Uses non-temporal stores for large buffer to avoid cache pollution.
  let totalBytes = ObsBufferSize
  var
    pDst = cast[uint](dst)
    pSrc = cast[uint](src)

  # Handle initial unaligned bytes
  while (pDst and 31) != 0 and (pDst - cast[uint](dst)) < totalBytes.uint:
    cast[ptr uint8](pDst)[] = cast[ptr uint8](pSrc)[]
    inc pDst
    inc pSrc

  let remaining = totalBytes - int(pDst - cast[uint](dst))
  let iterations = remaining div 256

  for _ in 0 ..< iterations:
    # Load and store 8 x 32 bytes per iteration
    let v0 = mm256_load_si256(cast[pointer](pSrc))
    let v1 = mm256_load_si256(cast[pointer](pSrc + 32))
    let v2 = mm256_load_si256(cast[pointer](pSrc + 64))
    let v3 = mm256_load_si256(cast[pointer](pSrc + 96))
    let v4 = mm256_load_si256(cast[pointer](pSrc + 128))
    let v5 = mm256_load_si256(cast[pointer](pSrc + 160))
    let v6 = mm256_load_si256(cast[pointer](pSrc + 192))
    let v7 = mm256_load_si256(cast[pointer](pSrc + 224))
    # Use streaming stores to bypass cache for large buffer
    mm256_stream_si256(cast[pointer](pDst), v0)
    mm256_stream_si256(cast[pointer](pDst + 32), v1)
    mm256_stream_si256(cast[pointer](pDst + 64), v2)
    mm256_stream_si256(cast[pointer](pDst + 96), v3)
    mm256_stream_si256(cast[pointer](pDst + 128), v4)
    mm256_stream_si256(cast[pointer](pDst + 160), v5)
    mm256_stream_si256(cast[pointer](pDst + 192), v6)
    mm256_stream_si256(cast[pointer](pDst + 224), v7)
    pSrc += 256
    pDst += 256

  # Handle remaining 32-byte chunks
  let remaining32 = (remaining mod 256) div 32
  for _ in 0 ..< remaining32:
    let v = mm256_load_si256(cast[pointer](pSrc))
    mm256_stream_si256(cast[pointer](pDst), v)
    pSrc += 32
    pDst += 32

  # Memory fence after streaming stores
  mm_sfence()

  # Handle remaining bytes
  let tailBytes = remaining mod 32
  for _ in 0 ..< tailBytes:
    cast[ptr uint8](pDst)[] = cast[ptr uint8](pSrc)[]
    inc pDst
    inc pSrc

proc simdZeroAgentLayers*(obs_buffer: ptr UncheckedArray[uint8], agentBase: int) {.inline.} =
  ## Zero all layers for a single agent using AVX2.
  ## Agent observation size = 96 layers * 11 * 11 = 11,616 bytes
  let
    vecZero = mm256_setzero_si256()
    agentSize = ObsAgentStride  # 11,616 bytes
  var p = cast[uint](obs_buffer) + agentBase.uint

  # 11,616 / 32 = 363 full vectors
  for _ in 0 ..< 363:
    mm256_storeu_si256(cast[pointer](p), vecZero)
    p += 32

  # Remaining bytes (11616 mod 32 = 0, so none needed)

proc simdZeroLayerRegion*(
  obs_buffer: ptr UncheckedArray[uint8],
  agentBase: int,
  startLayer: int,
  numLayers: int
) {.inline.} =
  ## Zero a contiguous region of layers for an agent.
  let
    vecZero = mm256_setzero_si256()
    startOffset = agentBase + startLayer * ObsTileStride
    totalBytes = numLayers * ObsTileStride
  var p = cast[uint](obs_buffer) + startOffset.uint

  let iterations = totalBytes div 32
  for _ in 0 ..< iterations:
    mm256_storeu_si256(cast[pointer](p), vecZero)
    p += 32

  let remaining = totalBytes mod 32
  for _ in 0 ..< remaining:
    cast[ptr uint8](p)[] = 0
    inc p

when defined(release):
  {.pop.}
