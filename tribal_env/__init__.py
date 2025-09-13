"""
Tribal Environment Package

A multi-agent reinforcement learning environment built with Nim and integrated with PufferLib.
"""

from .tribal_puffer import TribalPufferEnv, make_tribal_puffer_env

__version__ = "0.1.0"
__all__ = ["TribalPufferEnv", "make_tribal_puffer_env"]