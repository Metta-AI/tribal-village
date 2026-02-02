## Arena allocator for per-step temporary allocations
##
## Provides bump allocation that resets each step, avoiding repeated heap
## allocations for temporary sequences. Uses pre-allocated seq buffers that
## preserve capacity across resets.

import types

var arenaStats*: ArenaStats

proc initArena*(): Arena =
  ## Initialize arena with pre-allocated capacity
  result = Arena(
    things1: newSeqOfCap[Thing](ArenaDefaultCap),
    things2: newSeqOfCap[Thing](ArenaDefaultCap div 2),
    things3: newSeqOfCap[Thing](ArenaDefaultCap div 4),
    things4: newSeqOfCap[Thing](ArenaDefaultCap div 4),
    positions1: newSeqOfCap[IVec2](ArenaDefaultCap),
    positions2: newSeqOfCap[IVec2](ArenaDefaultCap div 2),
    ints1: newSeqOfCap[int](256),
    ints2: newSeqOfCap[int](256),
    itemCounts: newSeqOfCap[tuple[key: ItemKey, count: int]](MapObjectAgentMaxInventory),
    strings: newSeqOfCap[string](64),
  )

proc reset*(arena: var Arena) {.inline.} =
  ## Reset all arena buffers for a new step.
  ## Uses setLen(0) to preserve capacity while clearing contents.
  arena.things1.setLen(0)
  arena.things2.setLen(0)
  arena.things3.setLen(0)
  arena.things4.setLen(0)
  arena.positions1.setLen(0)
  arena.positions2.setLen(0)
  arena.ints1.setLen(0)
  arena.ints2.setLen(0)
  arena.itemCounts.setLen(0)
  arena.strings.setLen(0)
  inc arenaStats.resets

proc updateStats*(arena: Arena) {.inline.} =
  ## Update peak usage statistics
  if arena.things1.len > arenaStats.peakThings:
    arenaStats.peakThings = arena.things1.len
  if arena.positions1.len > arenaStats.peakPositions:
    arenaStats.peakPositions = arena.positions1.len
  if arena.ints1.len > arenaStats.peakInts:
    arenaStats.peakInts = arena.ints1.len

# Convenience templates for borrowing arena buffers
# These provide a scoped way to use arena memory

template withArenaThings*(arena: var Arena, buf: untyped, body: untyped) =
  ## Borrow things1 buffer, execute body, then clear
  buf = addr arena.things1
  body
  arena.things1.setLen(0)

template withArenaPositions*(arena: var Arena, buf: untyped, body: untyped) =
  ## Borrow positions1 buffer, execute body, then clear
  buf = addr arena.positions1
  body
  arena.positions1.setLen(0)

# Helper procs for common arena operations

proc borrowThings*(arena: var Arena): ptr seq[Thing] {.inline.} =
  ## Get pointer to things1 buffer (caller must clear when done)
  addr arena.things1

proc borrowPositions*(arena: var Arena): ptr seq[IVec2] {.inline.} =
  ## Get pointer to positions1 buffer (caller must clear when done)
  addr arena.positions1

proc borrowInts*(arena: var Arena): ptr seq[int] {.inline.} =
  ## Get pointer to ints1 buffer (caller must clear when done)
  addr arena.ints1
