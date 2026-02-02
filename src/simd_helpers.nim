## SIMD-optimized helpers for observation buffer operations
## Uses SSE2 (128-bit) for portable x86_64 optimization

when defined(amd64) or defined(i386):
  import nimsimd/sse2

  {.localPassc: "-msse2".}

  proc simdZeroMemAligned32*(dst: pointer, len: int) {.inline.} =
    ## Zero memory using SSE2 (16 bytes at a time)
    ## dst must be 16-byte aligned, len should be multiple of 16
    let zero = mm_setzero_si128()
    var p = cast[ptr UncheckedArray[uint8]](dst)
    var remaining = len

    # Main loop: 32 bytes (2 x 16) per iteration
    while remaining >= 32:
      mm_storeu_si128(addr p[0], zero)
      mm_storeu_si128(addr p[16], zero)
      p = cast[ptr UncheckedArray[uint8]](cast[uint](p) + 32)
      remaining -= 32

    # Handle remaining 16-byte chunk
    if remaining >= 16:
      mm_storeu_si128(addr p[0], zero)
      p = cast[ptr UncheckedArray[uint8]](cast[uint](p) + 16)
      remaining -= 16

    # Handle remaining bytes
    for i in 0 ..< remaining:
      p[i] = 0

  proc simdZeroBytes*(dst: ptr UncheckedArray[uint8], offset: int, count: int) {.inline.} =
    ## Zero `count` bytes starting at dst[offset]
    let p = cast[ptr UncheckedArray[uint8]](cast[uint](dst) + offset.uint)
    let zero = mm_setzero_si128()
    var remaining = count
    var i = 0

    # Main loop: 16 bytes per iteration
    while remaining >= 16:
      mm_storeu_si128(addr p[i], zero)
      i += 16
      remaining -= 16

    # Handle remaining bytes
    while remaining > 0:
      p[i] = 0
      inc i
      dec remaining

  proc simdFloatToUint8GreaterThanZero*(
    src: ptr UncheckedArray[float32],
    dst: ptr UncheckedArray[uint8],
    count: int
  ) {.inline.} =
    ## Convert float32 array to uint8: 1 if > 0.0, else 0
    ## Processes 4 floats at a time using SSE2
    let zero = mm_setzero_ps()
    var i = 0

    # Process 4 floats at a time
    while i + 4 <= count:
      # Load 4 floats
      let floats = mm_loadu_ps(addr src[i])
      # Compare > 0.0 (returns -1 for true, 0 for false)
      let cmp = mm_cmpgt_ps(floats, zero)
      # Extract comparison results as a 4-bit mask
      let mask = mm_movemask_ps(cmp)
      # Write individual bytes based on mask
      dst[i] = if (mask and 1) != 0: 1'u8 else: 0'u8
      dst[i+1] = if (mask and 2) != 0: 1'u8 else: 0'u8
      dst[i+2] = if (mask and 4) != 0: 1'u8 else: 0'u8
      dst[i+3] = if (mask and 8) != 0: 1'u8 else: 0'u8
      i += 4

    # Handle remaining elements
    while i < count:
      dst[i] = if src[i] > 0.0'f32: 1'u8 else: 0'u8
      inc i

  proc simdZeroScatteredLayers*(
    buffer: ptr UncheckedArray[uint8],
    baseOffset: int,
    tileOffset: int,
    tileStride: int,
    layerCount: int,
    skipLayer: int
  ) {.inline.} =
    ## Zero scattered layer bytes at a specific tile position
    ## Each layer is spaced by tileStride bytes
    ## Skips the layer at index skipLayer
    for layer in 0 ..< layerCount:
      if layer == skipLayer:
        continue
      let idx = baseOffset + layer * tileStride + tileOffset
      buffer[idx] = 0

else:
  # Fallback for non-x86 platforms
  proc simdZeroMemAligned32*(dst: pointer, len: int) {.inline.} =
    zeroMem(dst, len)

  proc simdZeroBytes*(dst: ptr UncheckedArray[uint8], offset: int, count: int) {.inline.} =
    let p = cast[ptr UncheckedArray[uint8]](cast[uint](dst) + offset.uint)
    for i in 0 ..< count:
      p[i] = 0

  proc simdFloatToUint8GreaterThanZero*(
    src: ptr UncheckedArray[float32],
    dst: ptr UncheckedArray[uint8],
    count: int
  ) {.inline.} =
    for i in 0 ..< count:
      dst[i] = if src[i] > 0.0'f32: 1'u8 else: 0'u8

  proc simdZeroScatteredLayers*(
    buffer: ptr UncheckedArray[uint8],
    baseOffset: int,
    tileOffset: int,
    tileStride: int,
    layerCount: int,
    skipLayer: int
  ) {.inline.} =
    for layer in 0 ..< layerCount:
      if layer == skipLayer:
        continue
      let idx = baseOffset + layer * tileStride + tileOffset
      buffer[idx] = 0

# Optimized obscured tile zeroing
proc zeroObscuredTileLayers*(
  buffer: ptr UncheckedArray[uint8],
  agentBase: int,
  xOffset: int,
  y: int,
  tileStride: int,
  layerCount: int,
  skipLayer: int
) {.inline.} =
  ## Zero all layers except skipLayer for a tile at (x,y) in agent's observation
  ## Uses manual unrolling for better instruction-level parallelism
  let tileOffset = xOffset + y

  # Unroll in groups of 4 for better ILP
  var layer = 0
  while layer + 4 <= layerCount:
    let idx0 = agentBase + layer * tileStride + tileOffset
    let idx1 = agentBase + (layer + 1) * tileStride + tileOffset
    let idx2 = agentBase + (layer + 2) * tileStride + tileOffset
    let idx3 = agentBase + (layer + 3) * tileStride + tileOffset

    if layer != skipLayer: buffer[idx0] = 0
    if layer + 1 != skipLayer: buffer[idx1] = 0
    if layer + 2 != skipLayer: buffer[idx2] = 0
    if layer + 3 != skipLayer: buffer[idx3] = 0

    layer += 4

  # Handle remaining layers
  while layer < layerCount:
    if layer != skipLayer:
      let idx = agentBase + layer * tileStride + tileOffset
      buffer[idx] = 0
    inc layer
