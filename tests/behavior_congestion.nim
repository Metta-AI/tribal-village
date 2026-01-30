import std/[unittest, strformat]
import environment
import types
import items
import terrain
import test_utils
import common

## Behavioral tests for unit pathfinding under congestion: narrow passages,
## bridges over water, bottleneck throughput with many units, and verification
## that no infinite loops or unreasonable step counts occur.

suite "Behavior: Narrow Passage Congestion":
  test "50 units traverse a 1-tile-wide bottleneck in line":
    ## All 50 agents are lined up at y=50 heading east through a 1-tile gap.
    ## Tests pure throughput: front agents clear the way via forward movement,
    ## rear agents advance via same-team swap mechanics.
    let env = makeEmptyEnv()
    # Wall barrier at x=80 with single gap at y=50
    for y in 40 .. 60:
      if y == 50:
        continue
      let wall = Thing(kind: Wall, pos: ivec2(80, y.int32))
      wall.inventory = emptyInventory()
      env.add(wall)

    # Place 50 agents in a line at y=50, from x=30 to x=79
    var agents: seq[Thing]
    for i in 0 ..< 50:
      agents.add addAgentAt(env, i, ivec2((30 + i).int32, 50))

    let maxSteps = 500
    var steps = 0
    for step in 0 ..< maxSteps:
      inc steps
      # Move front agents first to clear path
      for i in countdown(agents.len - 1, 0):
        env.stepAction(agents[i].agentId, 1'u8, 3)  # E

      var allPassed = true
      for a in agents:
        if a.pos.x <= 80:
          allPassed = false
          break
      if allPassed:
        break

    var passedCount = 0
    for a in agents:
      if a.pos.x > 80:
        inc passedCount

    echo &"  {passedCount}/50 agents passed 1-tile bottleneck in {steps} steps"
    check passedCount == 50
    check steps < maxSteps

  test "units pass through 2-tile-wide corridor without deadlock":
    let env = makeEmptyEnv()
    # Walls at y=49 and y=52 from x=55 to x=65, creating 2-wide corridor at y=50,51
    for x in 55 .. 65:
      let wN = Thing(kind: Wall, pos: ivec2(x.int32, 49))
      wN.inventory = emptyInventory()
      env.add(wN)
      let wS = Thing(kind: Wall, pos: ivec2(x.int32, 52))
      wS.inventory = emptyInventory()
      env.add(wS)

    # Place 20 agents in two rows at y=50 and y=51 before the corridor
    var agents: seq[Thing]
    for i in 0 ..< 20:
      let row = i mod 2  # Alternate between y=50 and y=51
      let col = i div 2
      agents.add addAgentAt(env, i, ivec2((45 + col).int32, (50 + row).int32))

    let maxSteps = 300
    var steps = 0
    for step in 0 ..< maxSteps:
      inc steps
      for i in countdown(agents.len - 1, 0):
        env.stepAction(agents[i].agentId, 1'u8, 3)  # E

      var allPassed = true
      for a in agents:
        if a.pos.x <= 65:
          allPassed = false
          break
      if allPassed:
        break

    var passedCount = 0
    for a in agents:
      if a.pos.x > 65:
        inc passedCount

    echo &"  {passedCount}/20 agents through 2-wide corridor in {steps} steps"
    check passedCount == 20
    check steps < maxSteps

  test "single-file corridor allows sequential passage":
    let env = makeEmptyEnv()
    # 1-tile corridor at y=50, walls at y=49 and y=51, from x=50 to x=60
    for x in 50 .. 60:
      let wN = Thing(kind: Wall, pos: ivec2(x.int32, 49))
      wN.inventory = emptyInventory()
      env.add(wN)
      let wS = Thing(kind: Wall, pos: ivec2(x.int32, 51))
      wS.inventory = emptyInventory()
      env.add(wS)

    # Place 5 agents in a line before the corridor entrance
    var agents: seq[Thing]
    for i in 0 ..< 5:
      agents.add addAgentAt(env, i, ivec2((45 + i).int32, 50))

    let maxSteps = 200
    var steps = 0
    for step in 0 ..< maxSteps:
      inc steps
      for i in countdown(agents.len - 1, 0):
        env.stepAction(agents[i].agentId, 1'u8, 3)

      var allPassed = true
      for a in agents:
        if a.pos.x <= 60:
          allPassed = false
          break
      if allPassed:
        break

    var passedCount = 0
    for a in agents:
      if a.pos.x > 60:
        inc passedCount

    echo &"  {passedCount}/5 agents through single-file corridor in {steps} steps"
    check passedCount >= 5

  test "50 units traverse a 5-tile-wide bottleneck":
    ## 50 agents in 5 rows pass through a 5-tile-wide gap.
    ## Tests parallel throughput with wider openings.
    let env = makeEmptyEnv()
    # Wall barrier at x=70 with 5-tile gap at y=48..52
    for y in 40 .. 60:
      if y >= 48 and y <= 52:
        continue  # 5-tile gap
      let wall = Thing(kind: Wall, pos: ivec2(70, y.int32))
      wall.inventory = emptyInventory()
      env.add(wall)

    # Place 50 agents in 5 rows (y=48..52) of 10 columns
    var agents: seq[Thing]
    for i in 0 ..< 50:
      let row = i mod 5
      let col = i div 5
      agents.add addAgentAt(env, i, ivec2((55 + col).int32, (48 + row).int32))

    let maxSteps = 200
    var steps = 0
    for step in 0 ..< maxSteps:
      inc steps
      for i in countdown(agents.len - 1, 0):
        env.stepAction(agents[i].agentId, 1'u8, 3)  # E

      var allPassed = true
      for a in agents:
        if a.pos.x <= 70:
          allPassed = false
          break
      if allPassed:
        break

    var passedCount = 0
    for a in agents:
      if a.pos.x > 70:
        inc passedCount

    echo &"  {passedCount}/50 agents through 5-tile gap in {steps} steps"
    check passedCount == 50
    check steps < maxSteps

suite "Behavior: Bridge Congestion":
  test "units traverse bridge over water":
    let env = makeEmptyEnv()
    # Water barrier 3 tiles wide at x=60..62, y=45..55
    for x in 60 .. 62:
      for y in 45 .. 55:
        env.terrain[x][y] = Water

    # Place a bridge across the water at y=50
    for x in 60 .. 62:
      env.terrain[x][50] = Bridge

    # Place 10 agents in a line at y=50 approaching the bridge
    var agents: seq[Thing]
    for i in 0 ..< 10:
      agents.add addAgentAt(env, i, ivec2((50 + i).int32, 50))

    let maxSteps = 200
    var steps = 0
    for step in 0 ..< maxSteps:
      inc steps
      for i in countdown(agents.len - 1, 0):
        env.stepAction(agents[i].agentId, 1'u8, 3)  # E

      var allPassed = true
      for a in agents:
        if a.pos.x <= 62:
          allPassed = false
          break
      if allPassed:
        break

    var passedCount = 0
    for a in agents:
      if a.pos.x > 62:
        inc passedCount

    echo &"  {passedCount}/10 agents crossed bridge in {steps} steps"
    check passedCount == 10
    check steps < maxSteps

  test "bridge terrain is walkable while adjacent water is not":
    let env = makeEmptyEnv()
    let agent = addAgentAt(env, 0, ivec2(50, 50))

    # Water to the east
    env.terrain[51][50] = Water
    let startPos = agent.pos
    env.stepAction(agent.agentId, 1'u8, 3)  # E - blocked by water
    check agent.pos == startPos

    # Change water to bridge
    env.terrain[51][50] = Bridge
    env.stepAction(agent.agentId, 1'u8, 3)  # E - bridge is walkable
    check agent.pos == ivec2(51, 50)
    echo "  Bridge walkable, water blocked"

  test "units queue to cross single-tile bridge":
    let env = makeEmptyEnv()
    # Water barrier at x=60, y=45..55
    for y in 45 .. 55:
      env.terrain[60][y] = Water

    # Single bridge tile at (60, 50)
    env.terrain[60][50] = Bridge

    # Place 10 agents in a line at y=50
    var agents: seq[Thing]
    for i in 0 ..< 10:
      agents.add addAgentAt(env, i, ivec2((50 + i).int32, 50))

    let maxSteps = 500
    var steps = 0
    for step in 0 ..< maxSteps:
      inc steps
      for i in countdown(agents.len - 1, 0):
        env.stepAction(agents[i].agentId, 1'u8, 3)  # E

      var allPassed = true
      for a in agents:
        if a.pos.x <= 60:
          allPassed = false
          break
      if allPassed:
        break

    var passedCount = 0
    for a in agents:
      if a.pos.x > 60:
        inc passedCount

    echo &"  {passedCount}/10 agents crossed single-tile bridge in {steps} steps"
    check passedCount == 10
    check steps < maxSteps

  test "50 units cross wide bridge over water":
    ## 50 agents in 5 rows cross a 5-row-wide bridge over a 3-tile water gap.
    let env = makeEmptyEnv()
    # Water barrier at x=70..72, y=40..60
    for x in 70 .. 72:
      for y in 40 .. 60:
        env.terrain[x][y] = Water

    # 5-row-wide bridge at y=48..52
    for x in 70 .. 72:
      for y in 48 .. 52:
        env.terrain[x][y] = Bridge

    # Place 50 agents in 5 rows within bridge y-range
    var agents: seq[Thing]
    for i in 0 ..< 50:
      let row = i mod 5
      let col = i div 5
      agents.add addAgentAt(env, i, ivec2((55 + col).int32, (48 + row).int32))

    let maxSteps = 200
    var steps = 0
    for step in 0 ..< maxSteps:
      inc steps
      for i in countdown(agents.len - 1, 0):
        env.stepAction(agents[i].agentId, 1'u8, 3)  # E

      var allPassed = true
      for a in agents:
        if a.pos.x <= 72:
          allPassed = false
          break
      if allPassed:
        break

    var passedCount = 0
    for a in agents:
      if a.pos.x > 72:
        inc passedCount

    echo &"  {passedCount}/50 agents crossed wide bridge in {steps} steps"
    check passedCount == 50
    check steps < maxSteps

suite "Behavior: Congestion Step Limits":
  test "no infinite loop when agents face completely blocked path":
    let env = makeEmptyEnv()
    # Completely walled off - no gap
    for y in 45 .. 55:
      let wall = Thing(kind: Wall, pos: ivec2(60, y.int32))
      wall.inventory = emptyInventory()
      env.add(wall)

    # Place 10 agents on the left
    var agents: seq[Thing]
    for i in 0 ..< 10:
      agents.add addAgentAt(env, i, ivec2((55 + i div 5).int32, (48 + i mod 5).int32))

    # Run for fixed steps - should complete without hanging
    let fixedSteps = 100
    for step in 0 ..< fixedSteps:
      for a in agents:
        env.stepAction(a.agentId, 1'u8, 3)  # E - all blocked by wall

    # No agent should have passed the wall
    for a in agents:
      check a.pos.x <= 60
    echo "  Blocked path: no agents passed, no infinite loop"

  test "same-team swap enables flow through congestion":
    let env = makeEmptyEnv()
    # Two agents in a corridor heading opposite directions
    # Corridor: walls at y=49 and y=51, x=48..52
    for x in 48 .. 52:
      let wN = Thing(kind: Wall, pos: ivec2(x.int32, 49))
      wN.inventory = emptyInventory()
      env.add(wN)
      let wS = Thing(kind: Wall, pos: ivec2(x.int32, 51))
      wS.inventory = emptyInventory()
      env.add(wS)

    let agentA = addAgentAt(env, 0, ivec2(48, 50))  # Heading east
    let agentB = addAgentAt(env, 1, ivec2(52, 50))  # Heading west

    # Move A east and B west - they should swap when meeting
    for step in 0 ..< 20:
      env.stepAction(agentA.agentId, 1'u8, 3)  # E
      env.stepAction(agentB.agentId, 1'u8, 2)  # W

    # Both should have made progress past each other via swaps
    check agentA.pos.x >= 50  # A moved east
    check agentB.pos.x <= 50  # B moved west
    echo &"  Swap flow: A at x={agentA.pos.x}, B at x={agentB.pos.x}"

  test "throughput scales with bottleneck width":
    ## Wider bottlenecks should allow more agents through faster.
    var passedByWidth: array[3, int]
    let fixedSteps = 100

    for widthIdx, gapWidth in [1, 3, 5]:
      let env = makeEmptyEnv()
      # Wall barrier at x=70 with variable-width gap centered at y=50
      let halfGap = gapWidth div 2
      for y in 40 .. 60:
        if y >= 50 - halfGap and y <= 50 + halfGap:
          continue
        let wall = Thing(kind: Wall, pos: ivec2(70, y.int32))
        wall.inventory = emptyInventory()
        env.add(wall)

      # Place 20 agents in a line at gap y-coordinates
      var agents: seq[Thing]
      for i in 0 ..< 20:
        let row = i mod gapWidth
        let col = i div gapWidth
        let y = 50 - halfGap + row
        agents.add addAgentAt(env, i, ivec2((55 + col).int32, y.int32))

      for step in 0 ..< fixedSteps:
        for i in countdown(agents.len - 1, 0):
          env.stepAction(agents[i].agentId, 1'u8, 3)  # E

      var passed = 0
      for a in agents:
        if a.pos.x > 70:
          inc passed
      passedByWidth[widthIdx] = passed

    echo &"  Throughput: width=1→{passedByWidth[0]}, width=3→{passedByWidth[1]}, width=5→{passedByWidth[2]}"
    # Wider gaps should allow at least as many (usually more) agents through
    check passedByWidth[1] >= passedByWidth[0]
    check passedByWidth[2] >= passedByWidth[1]

  test "50 units through bottleneck with reasonable step count":
    ## 50 agents lined up at y=50 pass through a 1-tile gap.
    ## Verifies completion within a bounded number of steps.
    let env = makeEmptyEnv()
    # Wall at x=80 with gap at y=50
    for y in 40 .. 60:
      if y == 50:
        continue
      let wall = Thing(kind: Wall, pos: ivec2(80, y.int32))
      wall.inventory = emptyInventory()
      env.add(wall)

    var agents: seq[Thing]
    for i in 0 ..< 50:
      agents.add addAgentAt(env, i, ivec2((30 + i).int32, 50))

    let maxSteps = 500
    var steps = 0
    for step in 0 ..< maxSteps:
      inc steps
      for i in countdown(agents.len - 1, 0):
        env.stepAction(agents[i].agentId, 1'u8, 3)  # E

      var allPassed = true
      for a in agents:
        if a.pos.x <= 80:
          allPassed = false
          break
      if allPassed:
        break

    echo &"  50 units through bottleneck in {steps}/{maxSteps} steps"
    check steps < maxSteps  # Must complete within budget
