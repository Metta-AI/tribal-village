#!/usr/bin/env python3
"""
Simple test script for tribal village PufferLib integration.
"""

import sys
from pathlib import Path

# Add the tribal src path for the standalone repo
tribal_village_root = Path.cwd()
tribal_src_path = tribal_village_root / "src"
sys.path.insert(0, str(tribal_src_path))


def test_direct_import():
    """Test direct import of tribal village environment."""
    print("=== Testing Direct Import ===")
    try:
        from tribal_village_env import TribalVillageEnv

        env = TribalVillageEnv()
        print(f"✓ Environment created: {env.num_agents} agents")

        obs, info = env.reset()
        print(f"✓ Reset successful: {len(obs)} observations")

        # Test step with random actions
        actions = {}
        for agent in env.agents:
            actions[agent] = env.single_action_space.sample()

        obs, rewards, terms, truncs, infos = env.step(actions)
        print(f"✓ Step successful: {len(rewards)} rewards")

        return True
    except Exception as e:
        print(f"✗ Direct import failed: {e}")
        return False


def test_package_import():
    """Test tribal_env package import."""
    print("\n=== Testing Package Import ===")
    try:
        import tribal_village_env

        print("✓ Package imported successfully")
        print(f"  Version: {tribal_village_env.__version__}")
        print(f"  Available: {tribal_village_env.__all__}")

        # Test factory function
        env = tribal_village_env.make_tribal_village_env()
        print("✓ Factory function works")
        print(f"  Agents: {env.num_agents}")

        return True
    except Exception as e:
        print(f"✗ Package import failed: {e}")
        import traceback

        traceback.print_exc()
        return False


if __name__ == "__main__":
    direct_ok = test_direct_import()
    package_ok = test_package_import()

    if direct_ok and package_ok:
        print("\n🎉 All tests passed!")
    else:
        print(f"\n❌ Tests failed: Direct={direct_ok}, Package={package_ok}")
        sys.exit(1)
