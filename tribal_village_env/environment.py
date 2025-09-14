"""
Tribal Village Environment - Direct pointer-based PufferLib integration.

This module provides the TribalVillageEnv class using direct pointer communication
with the Nim shared library for zero-copy performance.
"""

import ctypes
import numpy as np
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple
import gymnasium as gym
from gymnasium import spaces
import pufferlib


class TribalVillageEnv(pufferlib.PufferEnv):
    """
    Tribal Village Environment - Direct pointer-based integration.

    Uses pre-allocated numpy arrays and direct pointer passing for efficient
    communication with the Nim environment.
    """

    def __init__(self, config: Optional[Dict[str, Any]] = None, buf=None):
        self.config = config or {}

        # Environment configuration
        self.max_steps = self.config.get('max_steps', 512)

        # Load the Nim shared library from the installed package
        lib_path = Path(__file__).parent / "libtribal_village.so"
        if not lib_path.exists():
            raise FileNotFoundError(f"Nim library not found at {lib_path}. The tribal-village package was not properly installed.")

        self.lib = ctypes.CDLL(str(lib_path))
        self._setup_ctypes_interface()

        # Initialize the Nim environment
        self.env_ptr = self.lib.tribal_village_create()
        if not self.env_ptr:
            raise RuntimeError("Failed to create Nim environment")

        # Get environment parameters
        self.max_tokens_per_agent = self.lib.tribal_village_get_max_tokens()
        self.total_agents = self.lib.tribal_village_get_num_agents()

        # PufferLib controls all agents
        self.num_agents = self.total_agents
        self.agents = [f"agent_{i}" for i in range(self.total_agents)]
        self.possible_agents = self.agents.copy()

        # Define spaces BEFORE calling super()
        self.single_observation_space = spaces.Box(
            low=0, high=255,
            shape=(self.max_tokens_per_agent, 3),
            dtype=np.uint8
        )
        self.single_action_space = spaces.MultiDiscrete([9, 8], dtype=np.int32)  # [move_direction, action_type]
        self.is_continuous = False

        # Now call super()
        super().__init__(buf)

        # Set up joint action space like metta does
        self.action_space = pufferlib.spaces.joint_space(self.single_action_space, self.num_agents)
        if hasattr(self, 'actions'):
            self.actions = self.actions.astype(np.int32)

        # Pre-allocate numpy arrays for zero-copy communication
        # We allocate for all agents but only use what we need
        self.observations = np.zeros((self.total_agents, self.max_tokens_per_agent, 3), dtype=np.uint8)
        self.rewards = np.zeros(self.total_agents, dtype=np.float32)
        self.terminals = np.zeros(self.total_agents, dtype=np.bool_)
        self.truncations = np.zeros(self.total_agents, dtype=np.bool_)
        self.actions_buffer = np.zeros((self.total_agents, 2), dtype=np.uint8)

        # Environment state
        self.step_count = 0

    def _setup_ctypes_interface(self):
        """Setup ctypes function signatures for the Nim library."""

        # tribal_village_create() -> pointer
        self.lib.tribal_village_create.argtypes = []
        self.lib.tribal_village_create.restype = ctypes.c_void_p

        # tribal_village_destroy(env: pointer)
        self.lib.tribal_village_destroy.argtypes = [ctypes.c_void_p]
        self.lib.tribal_village_destroy.restype = None

        # tribal_village_reset_and_get_obs(env: pointer, obs_ptr: int) -> int32
        self.lib.tribal_village_reset_and_get_obs.argtypes = [ctypes.c_void_p, ctypes.c_int64]
        self.lib.tribal_village_reset_and_get_obs.restype = ctypes.c_int32

        # tribal_village_step_with_pointers(env, actions_ptr, obs_ptr, rewards_ptr, terminals_ptr, truncations_ptr) -> int32
        self.lib.tribal_village_step_with_pointers.argtypes = [
            ctypes.c_void_p, ctypes.c_int64, ctypes.c_int64,
            ctypes.c_int64, ctypes.c_int64, ctypes.c_int64
        ]
        self.lib.tribal_village_step_with_pointers.restype = ctypes.c_int32

        # tribal_village_get_num_agents() -> int32
        self.lib.tribal_village_get_num_agents.argtypes = []
        self.lib.tribal_village_get_num_agents.restype = ctypes.c_int32

        # tribal_village_get_max_tokens() -> int32
        self.lib.tribal_village_get_max_tokens.argtypes = []
        self.lib.tribal_village_get_max_tokens.restype = ctypes.c_int32

        # tribal_village_is_done(env: pointer) -> int32
        self.lib.tribal_village_is_done.argtypes = [ctypes.c_void_p]
        self.lib.tribal_village_is_done.restype = ctypes.c_int32

    def reset(self, seed: Optional[int] = None, options: Optional[Dict] = None) -> Tuple[Dict, Dict]:
        """Reset the environment using direct pointer access."""
        self.step_count = 0

        # Get pointer to observations buffer
        obs_ptr = self.observations.ctypes.data_as(ctypes.c_void_p).value or 0

        # Reset environment and get observations in one call
        success = self.lib.tribal_village_reset_and_get_obs(self.env_ptr, obs_ptr)
        if not success:
            raise RuntimeError("Failed to reset Nim environment")

        # Extract observations for all agents
        observations = {}
        info = {}
        for i in range(self.num_agents):
            observations[f"agent_{i}"] = self.observations[i].copy()
            info[f"agent_{i}"] = {}

        return observations, info

    def step(self, actions: Dict[str, np.ndarray]) -> Tuple[Dict, Dict, Dict, Dict, Dict]:
        """Step the environment using direct pointer access."""
        self.step_count += 1

        # Clear actions buffer (all agents get no-op by default)
        self.actions_buffer.fill(0)

        # Set actions for all controlled agents
        for i in range(self.num_agents):
            agent_key = f"agent_{i}"
            if agent_key in actions:
                action = actions[agent_key]
                self.actions_buffer[i, 0] = action[0]  # move_direction
                self.actions_buffer[i, 1] = action[1]  # action_type

        # Get pointers to all buffers
        actions_ptr = self.actions_buffer.ctypes.data_as(ctypes.c_void_p).value or 0
        obs_ptr = self.observations.ctypes.data_as(ctypes.c_void_p).value or 0
        rewards_ptr = self.rewards.ctypes.data_as(ctypes.c_void_p).value or 0
        terminals_ptr = self.terminals.ctypes.data_as(ctypes.c_void_p).value or 0
        truncations_ptr = self.truncations.ctypes.data_as(ctypes.c_void_p).value or 0

        # Step environment with all pointers
        success = self.lib.tribal_village_step_with_pointers(
            self.env_ptr, actions_ptr, obs_ptr, rewards_ptr, terminals_ptr, truncations_ptr
        )
        if not success:
            raise RuntimeError("Failed to step Nim environment")

        # Extract results for all agents
        observations = {}
        rewards = {}
        terminated = {}
        truncated = {}
        infos = {}

        for i in range(self.num_agents):
            agent_key = f"agent_{i}"
            observations[agent_key] = self.observations[i].copy()
            rewards[agent_key] = float(self.rewards[i])
            terminated[agent_key] = bool(self.terminals[i])
            truncated[agent_key] = bool(self.truncations[i]) or (self.step_count >= self.max_steps)
            infos[agent_key] = {}

        return observations, rewards, terminated, truncated, infos

    def close(self):
        """Clean up the environment."""
        if hasattr(self, 'env_ptr') and self.env_ptr:
            self.lib.tribal_village_destroy(self.env_ptr)
            self.env_ptr = None


def make_tribal_village_env(config: Optional[Dict[str, Any]] = None, **kwargs) -> TribalVillageEnv:
    """Factory function to create a tribal village environment."""
    if config is None:
        config = {}
    config.update(kwargs)
    return TribalVillageEnv(config=config)