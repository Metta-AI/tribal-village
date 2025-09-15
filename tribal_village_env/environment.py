"""
Ultra-Fast Tribal Village Environment - Direct Buffer Interface.

Eliminates ALL conversion overhead by using direct numpy buffer communication.
"""

import ctypes
import numpy as np
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple
import gymnasium as gym
from gymnasium import spaces
import pufferlib


class TribalVillageFastEnv(pufferlib.PufferEnv):
    """
    Ultra-fast tribal village environment using direct buffer interface.

    Eliminates conversion overhead by using pre-allocated numpy buffers
    that Nim reads/writes directly.
    """

    def __init__(self, config: Optional[Dict[str, Any]] = None, buf=None):
        self.config = config or {}
        self.max_steps = self.config.get('max_steps', 512)

        # Load the optimized Nim library
        lib_path = Path(__file__).parent / "libtribal_village.so"
        if not lib_path.exists():
            raise FileNotFoundError(f"Nim library not found at {lib_path}")

        self.lib = ctypes.CDLL(str(lib_path))
        self._setup_ctypes_interface()

        # Get environment dimensions
        self.total_agents = self.lib.tribal_village_get_num_agents_fast()
        self.obs_layers = self.lib.tribal_village_get_obs_layers()
        self.obs_width = self.lib.tribal_village_get_obs_width()
        self.obs_height = self.lib.tribal_village_get_obs_height()

        # PufferLib controls all agents
        self.num_agents = self.total_agents
        self.agents = [f"agent_{i}" for i in range(self.total_agents)]
        self.possible_agents = self.agents.copy()

        # Define spaces - use direct observation shape (no sparse tokens!)
        self.single_observation_space = spaces.Box(
            low=0, high=255,
            shape=(self.obs_layers, self.obs_width, self.obs_height),
            dtype=np.uint8
        )
        self.single_action_space = spaces.MultiDiscrete([9, 8], dtype=np.uint8)
        self.is_continuous = False

        super().__init__(buf)

        # Pre-allocate direct buffers (zero-copy communication)
        self.obs_buffer = np.zeros(
            (self.total_agents, self.obs_layers, self.obs_width, self.obs_height),
            dtype=np.uint8
        )
        self.actions_buffer = np.zeros((self.total_agents, 2), dtype=np.uint8)
        self.rewards_buffer = np.zeros(self.total_agents, dtype=np.float32)
        self.terminals_buffer = np.zeros(self.total_agents, dtype=np.uint8)
        self.truncations_buffer = np.zeros(self.total_agents, dtype=np.uint8)

        # Initialize environment
        self.env_ptr = self.lib.tribal_village_create_fast()
        if not self.env_ptr:
            raise RuntimeError("Failed to create Nim environment")

        self.step_count = 0

    def _setup_ctypes_interface(self):
        """Setup ctypes for direct buffer functions."""

        # tribal_village_create_fast() -> pointer
        self.lib.tribal_village_create_fast.argtypes = []
        self.lib.tribal_village_create_fast.restype = ctypes.c_void_p

        # tribal_village_reset_direct(env, obs_buf, rewards_buf, terminals_buf, truncations_buf) -> int32
        self.lib.tribal_village_reset_direct.argtypes = [
            ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p,
            ctypes.c_void_p, ctypes.c_void_p
        ]
        self.lib.tribal_village_reset_direct.restype = ctypes.c_int32

        # tribal_village_step_direct(env, actions_buf, obs_buf, rewards_buf, terminals_buf, truncations_buf) -> int32
        self.lib.tribal_village_step_direct.argtypes = [
            ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p,
            ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p
        ]
        self.lib.tribal_village_step_direct.restype = ctypes.c_int32

        # Dimension getters
        for func_name in ['tribal_village_get_num_agents_fast', 'tribal_village_get_obs_layers',
                         'tribal_village_get_obs_width', 'tribal_village_get_obs_height']:
            getattr(self.lib, func_name).argtypes = []
            getattr(self.lib, func_name).restype = ctypes.c_int32

    def reset(self, seed: Optional[int] = None, options: Optional[Dict] = None) -> Tuple[Dict, Dict]:
        """Ultra-fast reset using direct buffers."""
        self.step_count = 0

        # Get buffer pointers
        obs_ptr = self.obs_buffer.ctypes.data_as(ctypes.c_void_p)
        rewards_ptr = self.rewards_buffer.ctypes.data_as(ctypes.c_void_p)
        terminals_ptr = self.terminals_buffer.ctypes.data_as(ctypes.c_void_p)
        truncations_ptr = self.truncations_buffer.ctypes.data_as(ctypes.c_void_p)

        # Direct buffer reset - no conversions
        success = self.lib.tribal_village_reset_direct(
            self.env_ptr, obs_ptr, rewards_ptr, terminals_ptr, truncations_ptr
        )
        if not success:
            raise RuntimeError("Failed to reset Nim environment")

        # Return observations as views (no copying!)
        observations = {f"agent_{i}": self.obs_buffer[i] for i in range(self.num_agents)}
        info = {f"agent_{i}": {} for i in range(self.num_agents)}

        return observations, info

    def step(self, actions: Dict[str, np.ndarray]) -> Tuple[Dict, Dict, Dict, Dict, Dict]:
        """Ultra-fast step using direct buffers."""
        self.step_count += 1

        # Clear actions buffer
        self.actions_buffer.fill(0)

        # Direct action setting (no dict overhead)
        for i in range(self.num_agents):
            agent_key = f"agent_{i}"
            if agent_key in actions:
                action = actions[agent_key]
                self.actions_buffer[i, 0] = action[0]
                self.actions_buffer[i, 1] = action[1]

        # Get buffer pointers
        actions_ptr = self.actions_buffer.ctypes.data_as(ctypes.c_void_p)
        obs_ptr = self.obs_buffer.ctypes.data_as(ctypes.c_void_p)
        rewards_ptr = self.rewards_buffer.ctypes.data_as(ctypes.c_void_p)
        terminals_ptr = self.terminals_buffer.ctypes.data_as(ctypes.c_void_p)
        truncations_ptr = self.truncations_buffer.ctypes.data_as(ctypes.c_void_p)

        # Direct buffer step - no conversions
        success = self.lib.tribal_village_step_direct(
            self.env_ptr, actions_ptr, obs_ptr, rewards_ptr, terminals_ptr, truncations_ptr
        )
        if not success:
            raise RuntimeError("Failed to step Nim environment")

        # Return results as views (no copying!)
        observations = {f"agent_{i}": self.obs_buffer[i] for i in range(self.num_agents)}
        rewards = {f"agent_{i}": float(self.rewards_buffer[i]) for i in range(self.num_agents)}
        terminated = {f"agent_{i}": bool(self.terminals_buffer[i]) for i in range(self.num_agents)}
        truncated = {f"agent_{i}": bool(self.truncations_buffer[i]) or (self.step_count >= self.max_steps) for i in range(self.num_agents)}
        infos = {f"agent_{i}": {} for i in range(self.num_agents)}

        return observations, rewards, terminated, truncated, infos

    def close(self):
        """Clean up the environment."""
        if hasattr(self, 'env_ptr') and self.env_ptr:
            # Use existing destroy function
            pass


def make_tribal_village_fast_env(config: Optional[Dict[str, Any]] = None, **kwargs) -> TribalVillageFastEnv:
    """Factory function for ultra-fast tribal village environment."""
    if config is None:
        config = {}
    config.update(kwargs)
    return TribalVillageFastEnv(config=config)