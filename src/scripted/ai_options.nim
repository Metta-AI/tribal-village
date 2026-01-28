## Behavior option framework for the AI system.
## Contains the OptionDef type, runOptions executor, and shared helper procs.

import ai_types
import ../environment

export ai_types

type
  OptionDef* = object
    name*: string
    canStart*: proc(controller: Controller, env: Environment, agent: Thing,
                    agentId: int, state: var AgentState): bool
    shouldTerminate*: proc(controller: Controller, env: Environment, agent: Thing,
                           agentId: int, state: var AgentState): bool
    act*: proc(controller: Controller, env: Environment, agent: Thing,
               agentId: int, state: var AgentState): uint8
    interruptible*: bool

proc optionsAlwaysCanStart*(controller: Controller, env: Environment, agent: Thing,
                            agentId: int, state: var AgentState): bool =
  true

proc optionsAlwaysTerminate*(controller: Controller, env: Environment, agent: Thing,
                             agentId: int, state: var AgentState): bool =
  true

template resetActiveOption(state: var AgentState) =
  state.activeOptionId = -1
  state.activeOptionTicks = 0

proc runOptions*(controller: Controller, env: Environment, agent: Thing,
                 agentId: int, state: var AgentState,
                 roleOptions: openArray[OptionDef]): uint8 =
  ## Execute the RL-style options framework.
  ## Handles active option continuation, preemption by higher-priority options,
  ## and scanning for new options when none is active.
  let optionCount = roleOptions.len
  # Handle active option first (if any).
  if state.activeOptionId in 0 ..< optionCount:
    let activeIdx = state.activeOptionId
    if roleOptions[activeIdx].interruptible:
      for i in 0 ..< activeIdx:
        if roleOptions[i].canStart(controller, env, agent, agentId, state):
          state.activeOptionId = i
          state.activeOptionTicks = 0
          break
    inc state.activeOptionTicks
    let action = roleOptions[state.activeOptionId].act(
      controller, env, agent, agentId, state)
    if action != 0'u8:
      if roleOptions[state.activeOptionId].shouldTerminate(
          controller, env, agent, agentId, state):
        resetActiveOption(state)
      return action
    resetActiveOption(state)

  # Otherwise, scan options in priority order and use the first that acts.
  for i, opt in roleOptions:
    if not opt.canStart(controller, env, agent, agentId, state):
      continue
    state.activeOptionId = i
    state.activeOptionTicks = 1
    let action = opt.act(controller, env, agent, agentId, state)
    if action != 0'u8:
      if opt.shouldTerminate(controller, env, agent, agentId, state):
        resetActiveOption(state)
      return action
    resetActiveOption(state)

  return 0'u8
