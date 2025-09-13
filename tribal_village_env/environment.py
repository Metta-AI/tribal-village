"""
Tribal Village Environment - Nim-based PufferLib integration.

This module provides the TribalVillageEnv class that interfaces with the Nim
shared library compiled from tribal_village.nim to provide a multi-agent
reinforcement learning environment.
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
    Tribal Village Environment - A multi-agent RL environment built with Nim.

    This environment wraps the Nim-based tribal village game engine and provides
    PufferLib compatibility for training RL agents.
    """

    def __init__(self, config: Optional[Dict[str, Any]] = None, buf=None):
        self.config = config or {}

        # Default configuration
        self.max_steps = self.config.get('max_steps', 512)
        self.ore_per_battery = self.config.get('ore_per_battery', 3)
        self.batteries_per_heart = self.config.get('batteries_per_heart', 2)
        self.enable_combat = self.config.get('enable_combat', True)
        self.clippy_spawn_rate = self.config.get('clippy_spawn_rate', 0.1)
        self.clippy_damage = self.config.get('clippy_damage', 10)

        # Reward configuration
        self.heart_reward = self.config.get('heart_reward', 1.0)
        self.battery_reward = self.config.get('battery_reward', 0.5)
        self.ore_reward = self.config.get('ore_reward', 0.1)
        self.survival_penalty = self.config.get('survival_penalty', -0.01)
        self.death_penalty = self.config.get('death_penalty', -1.0)

        # Environment state
        self.step_count = 0

        # Load the Nim shared library first to get actual parameters
        lib_path = Path(__file__).parent.parent / "libtribal_village.so"
        if not lib_path.exists():
            raise FileNotFoundError(f"Nim library not found at {lib_path}. Run ./build_lib.sh")

        self.lib = ctypes.CDLL(str(lib_path))

        # Setup function signatures
        self._setup_ctypes_interface()

        # Initialize the Nim environment to get actual parameters
        self.env_ptr = self.lib.tribal_village_create()

        # Get actual parameters from Nim
        self.max_tokens_per_agent = self.lib.tribal_village_get_max_tokens()

        # For independent agent control, we'll control just one agent per env instance
        # The config can specify which agent_id we control (default 0)
        self.controlled_agent_id = self.config.get('agent_id', 0)
        self.num_agents = 1  # Single agent per environment instance for PufferLib
        self.agents = ["agent_0"]
        self.possible_agents = self.agents.copy()

        # Define observation and action spaces with actual parameters BEFORE calling super()
        # Token-based observations: (MAX_TOKENS_PER_AGENT, 3) where 3 = [coord_byte, layer, value]
        self.single_observation_space = spaces.Box(
            low=0, high=255,
            shape=(self.max_tokens_per_agent, 3),
            dtype=np.uint8
        )

        # Multi-discrete action space: [move_direction(9), action_type(8)]
        self.single_action_space = spaces.MultiDiscrete([9, 8])

        # Now we can call super() with all required attributes set
        super().__init__()

    def _setup_ctypes_interface(self):
        """Setup ctypes function signatures for the Nim library."""

        # tribal_village_create() -> pointer
        self.lib.tribal_village_create.argtypes = []
        self.lib.tribal_village_create.restype = ctypes.c_void_p

        # tribal_village_destroy(env: pointer)
        self.lib.tribal_village_destroy.argtypes = [ctypes.c_void_p]
        self.lib.tribal_village_destroy.restype = None

        # tribal_village_reset(env: pointer)
        self.lib.tribal_village_reset.argtypes = [ctypes.c_void_p]
        self.lib.tribal_village_reset.restype = None

        # tribal_village_step(env: pointer, action0: int, action1: int)
        self.lib.tribal_village_step.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
        self.lib.tribal_village_step.restype = None

        # tribal_village_get_observation(env: pointer, agent_id: int, buffer: array, max_tokens: int)
        self.lib.tribal_village_get_observation.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_uint8), ctypes.c_int]
        self.lib.tribal_village_get_observation.restype = ctypes.c_int

        # tribal_village_get_reward(env: pointer, agent_id: int) -> float
        self.lib.tribal_village_get_reward.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self.lib.tribal_village_get_reward.restype = ctypes.c_float

        # tribal_village_is_done(env: pointer, agent_id: int) -> bool
        self.lib.tribal_village_is_done.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self.lib.tribal_village_is_done.restype = ctypes.c_int

        # tribal_village_get_num_agents(env: pointer) -> int
        self.lib.tribal_village_get_num_agents.argtypes = [ctypes.c_void_p]
        self.lib.tribal_village_get_num_agents.restype = ctypes.c_int

        # tribal_village_get_max_tokens() -> int
        self.lib.tribal_village_get_max_tokens.argtypes = []
        self.lib.tribal_village_get_max_tokens.restype = ctypes.c_int

    def reset(self, seed: Optional[int] = None, options: Optional[Dict] = None) -> Tuple[Dict, Dict]:
        """Reset the environment."""
        self.step_count = 0

        # Reset the Nim environment
        self.lib.tribal_village_reset(self.env_ptr)

        # Get initial observations
        observations = self._get_observations()
        info = {agent: {} for agent in self.agents}

        return observations, info

    def step(self, actions: Dict[str, np.ndarray]) -> Tuple[Dict, Dict, Dict, Dict, Dict]:
        """Step the environment forward."""
        self.step_count += 1

        # Get action for our controlled agent
        agent_action = actions.get("agent_0", np.array([0, 0]))  # default no-op
        action0 = int(agent_action[0])  # move_direction
        action1 = int(agent_action[1])  # action_type

        # Step the Nim environment with this agent's actions
        self.lib.tribal_village_step(self.env_ptr, action0, action1)

        # Get observations, rewards, and dones
        observations = self._get_observations()
        rewards = self._get_rewards()
        terminated = self._get_terminated()
        truncated = self._get_truncated()
        infos = {agent: {} for agent in self.agents}

        return observations, rewards, terminated, truncated, infos

    def _get_observations(self) -> Dict[str, np.ndarray]:
        """Get observations from the Nim environment."""
        # Create buffer for our single controlled agent's observations
        obs_buffer = (ctypes.c_uint8 * (self.max_tokens_per_agent * 3))()

        # Get observations for our controlled agent
        actual_tokens = self.lib.tribal_village_get_observation(
            self.env_ptr, self.controlled_agent_id, obs_buffer, self.max_tokens_per_agent
        )

        # Convert to numpy and reshape
        obs_array = np.ctypeslib.as_array(obs_buffer)
        obs_array = obs_array.reshape(self.max_tokens_per_agent, 3)

        # Return dict with our single agent's observations
        return {"agent_0": obs_array.copy()}

    def _get_rewards(self) -> Dict[str, float]:
        """Get rewards from the Nim environment."""
        reward = self.lib.tribal_village_get_reward(self.env_ptr, self.controlled_agent_id)
        return {"agent_0": float(reward)}

    def _get_terminated(self) -> Dict[str, bool]:
        """Get termination status for each agent."""
        is_done = self.lib.tribal_village_is_done(self.env_ptr, self.controlled_agent_id)
        return {"agent_0": bool(is_done)}

    def _get_truncated(self) -> Dict[str, bool]:
        """Get truncation status (time limit reached)."""
        is_truncated = self.step_count >= self.max_steps
        return {"agent_0": is_truncated}

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