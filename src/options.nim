# Minimal RL-style options: initiation, termination, and per-tick policy step.

proc optionsAlwaysCanStart*(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): bool =
  true

proc optionsAlwaysTerminate*(controller: Controller, env: Environment, agent: Thing,
                             agentId: int, state: var AgentState): bool =
  true

proc optionsNeverTerminate*(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): bool =
  false

type OptionDef* = object
  name*: string
  canStart*: proc(controller: Controller, env: Environment, agent: Thing,
                  agentId: int, state: var AgentState): bool
  shouldTerminate*: proc(controller: Controller, env: Environment, agent: Thing,
                         agentId: int, state: var AgentState): bool
  act*: proc(controller: Controller, env: Environment, agent: Thing,
             agentId: int, state: var AgentState): uint8
  interruptible*: bool

proc clearActiveOption(state: var AgentState) =
  state.activeOptionId = -1
  state.activeOptionTicks = 0

proc runOptions*(controller: Controller, env: Environment, agent: Thing,
                 agentId: int, state: var AgentState,
                 roleOptions: openArray[OptionDef]): uint8 =
  # Handle active option first (if any).
  if state.activeOptionId >= 0 and state.activeOptionId < roleOptions.len:
    let activeIdx = state.activeOptionId
    let activeDef = roleOptions[activeIdx]
    if activeDef.interruptible:
      for i in 0 ..< activeIdx:
        if roleOptions[i].canStart(controller, env, agent, agentId, state):
          state.activeOptionId = i
          state.activeOptionTicks = 0
          break
    if state.activeOptionId >= 0 and state.activeOptionId < roleOptions.len:
      inc state.activeOptionTicks
      let action = roleOptions[state.activeOptionId].act(
        controller, env, agent, agentId, state)
      if action != 0'u8:
        if roleOptions[state.activeOptionId].shouldTerminate(
            controller, env, agent, agentId, state):
          clearActiveOption(state)
        return action
      clearActiveOption(state)

  # Otherwise, scan options in priority order and use the first that acts.
  for i, opt in roleOptions:
    if not opt.canStart(controller, env, agent, agentId, state):
      continue
    state.activeOptionId = i
    state.activeOptionTicks = 1
    let action = opt.act(controller, env, agent, agentId, state)
    if action != 0'u8:
      if opt.shouldTerminate(controller, env, agent, agentId, state):
        clearActiveOption(state)
      return action
    clearActiveOption(state)

  return 0'u8
