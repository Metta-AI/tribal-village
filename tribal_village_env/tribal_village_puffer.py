"""
PufferLib wrapper for Tribal Village environment.

This module provides a PufferLib-compatible wrapper for the Nim-based tribal village environment.
It bridges the TribalVillageGridEnv from the tribal village bindings to work seamlessly with PufferLib
as a third-party environment.
"""

import numpy as np
import gymnasium as gym
from typing import Any, Dict, Optional, Tuple, List


class TribalVillagePufferEnv:
    """
    PufferLib wrapper for the Tribal Village environment.

    This wrapper adapts the Nim-based tribal village environment to work with PufferLib's
    training infrastructure as a third-party environment. It handles the conversion
    between PufferLib's expected interface and the tribal village environment's native interface.
    """

    def __init__(self, config: Optional[Dict[str, Any]] = None, render_mode: Optional[str] = 'rgb_array', buf=None):
        """
        Initialize the PufferLib-compatible tribal village environment.

        Args:
            config: Configuration dictionary for the tribal village environment
            render_mode: Rendering mode (default: 'rgb_array')
            buf: PufferLib buffer (not used in this implementation)
        """
        # Import the tribal village environment
        try:
            # Add the tribal village bindings to the path
            import sys
            from pathlib import Path

            # Find the tribal-village root directory
            package_root = Path(__file__).parent.parent
            tribal_src_path = package_root / "src"

            if str(tribal_src_path) not in sys.path:
                sys.path.insert(0, str(tribal_src_path))

            from .tribal_village_genny import TribalVillageGridEnv

        except ImportError as e:
            raise ImportError(
                f"Failed to import TribalVillageGridEnv: {e}\n\n"
                "This requires the tribal village environment with bindings built. "
                "Run './build_bindings.sh' to build the bindings."
            )

        # Create the tribal village environment
        self._tribal_env = TribalVillageGridEnv(config=config, render_mode=render_mode)

        # Set up gymnasium spaces based on the tribal village environment
        self.single_observation_space = self._tribal_env.single_observation_space
        self.single_action_space = self._tribal_env.single_action_space

        # Multi-agent setup
        self.num_agents = self._tribal_env.num_agents
        self.agents = [f"agent_{i}" for i in range(self.num_agents)]

        # Create multi-agent spaces
        self.observation_space = gym.spaces.Dict({
            agent: self.single_observation_space for agent in self.agents
        })
        self.action_space = gym.spaces.Dict({
            agent: self.single_action_space for agent in self.agents
        })

        # Store render mode internally
        self._render_mode = render_mode
        self.possible_agents = self.agents.copy()


    def reset(self, seed: Optional[int] = None, options: Optional[Dict] = None) -> Tuple[Dict[str, np.ndarray], Dict[str, Any]]:
        """
        Reset the environment.

        Returns:
            observations: Dictionary mapping agent names to their observations
            infos: Dictionary containing environment information
        """
        # Reset the tribal village environment
        obs_array, info = self._tribal_env.reset(seed=seed)

        # Convert to PufferLib multi-agent format
        observations = {
            agent: obs_array[i] for i, agent in enumerate(self.agents)
        }

        # Convert info to per-agent format
        infos = {agent: info.copy() for agent in self.agents}

        return observations, infos

    def step(self, actions: Dict[str, np.ndarray]) -> Tuple[Dict[str, np.ndarray], Dict[str, float], Dict[str, bool], Dict[str, bool], Dict[str, Dict[str, Any]]]:
        """
        Step the environment forward.

        Args:
            actions: Dictionary mapping agent names to their actions

        Returns:
            observations: New observations for each agent
            rewards: Rewards for each agent
            terminals: Terminal flags for each agent
            truncations: Truncation flags for each agent
            infos: Info dictionaries for each agent
        """
        # Convert actions from dict format to array format expected by tribal env
        action_array = np.array([actions[agent] for agent in self.agents])

        # Step the tribal village environment
        obs_array, rewards_array, terminals_array, truncations_array, info = self._tribal_env.step(action_array)

        # Convert back to PufferLib multi-agent format
        observations = {
            agent: obs_array[i] for i, agent in enumerate(self.agents)
        }

        rewards = {
            agent: float(rewards_array[i]) for i, agent in enumerate(self.agents)
        }

        terminals = {
            agent: bool(terminals_array[i]) for i, agent in enumerate(self.agents)
        }

        truncations = {
            agent: bool(truncations_array[i]) for i, agent in enumerate(self.agents)
        }

        infos = {
            agent: info.copy() for agent in self.agents
        }

        return observations, rewards, terminals, truncations, infos

    def render(self):
        """Render the environment if supported."""
        if hasattr(self._tribal_env, 'render'):
            return self._tribal_env.render()
        return None

    def close(self):
        """Close the environment."""
        if hasattr(self._tribal_env, 'close'):
            self._tribal_env.close()

    @property
    def emulated(self) -> bool:
        """Return whether this is an emulated environment."""
        return getattr(self._tribal_env, 'emulated', False)

    @property
    def current_step(self) -> int:
        """Get the current step count."""
        return getattr(self._tribal_env, 'current_step', 0)

    @property
    def max_steps(self) -> int:
        """Get the maximum number of steps."""
        return getattr(self._tribal_env, 'max_steps', 1000)

    @property
    def render_mode(self) -> Optional[str]:
        """Get the render mode."""
        return self._render_mode


def make_tribal_village_puffer_env(config: Optional[Dict[str, Any]] = None, render_mode: str = 'rgb_array', **kwargs) -> TribalVillagePufferEnv:
    """
    Factory function to create a TribalVillagePufferEnv instance.

    Args:
        config: Configuration for the tribal village environment
        render_mode: Rendering mode
        **kwargs: Additional keyword arguments

    Returns:
        Configured TribalVillagePufferEnv instance
    """
    return TribalVillagePufferEnv(config=config, render_mode=render_mode)