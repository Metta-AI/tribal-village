"""
Tribal Village Environment Package

A multi-agent reinforcement learning environment built with Nim and integrated with PufferLib.
"""

from .tribal_village_puffer import TribalVillagePufferEnv, make_tribal_village_puffer_env

__version__ = "0.1.0"
__all__ = ["TribalVillagePufferEnv", "make_tribal_village_puffer_env"]