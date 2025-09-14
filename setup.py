#!/usr/bin/env python3
"""
Setup script for tribal-village that builds the Nim shared library.
"""

import os
import subprocess
import shutil
from pathlib import Path
from setuptools import setup, find_packages
from setuptools.command.build_py import build_py
from setuptools.command.develop import develop
from setuptools.command.install import install


class BuildNimLibrary:
    """Mixin class to build the Nim shared library."""

    def build_nim_library(self):
        """Build the Nim shared library using build_lib.sh"""
        print("Building Nim shared library...")

        # Get the project root directory
        project_root = Path(__file__).parent
        build_script = project_root / "build_lib.sh"

        if not build_script.exists():
            raise RuntimeError(f"Build script not found: {build_script}")

        # Run the build script
        result = subprocess.run(
            ["bash", str(build_script)],
            cwd=project_root,
            capture_output=True,
            text=True
        )

        if result.returncode != 0:
            raise RuntimeError(f"Failed to build Nim library: {result.stderr}")

        # Copy the built library to the Python package directory
        lib_file = project_root / "libtribal_village.so"
        if not lib_file.exists():
            raise RuntimeError("Nim library was not created by build script")

        package_dir = project_root / "tribal_village_env"
        shutil.copy2(lib_file, package_dir / "libtribal_village.so")
        print(f"Copied {lib_file} to {package_dir}")


class CustomBuildPy(build_py, BuildNimLibrary):
    """Custom build_py that builds Nim library first."""

    def run(self):
        self.build_nim_library()
        super().run()


class CustomDevelop(develop, BuildNimLibrary):
    """Custom develop that builds Nim library first."""

    def run(self):
        self.build_nim_library()
        super().run()


class CustomInstall(install, BuildNimLibrary):
    """Custom install that builds Nim library first."""

    def run(self):
        self.build_nim_library()
        super().run()


if __name__ == "__main__":
    setup(
        cmdclass={
            'build_py': CustomBuildPy,
            'develop': CustomDevelop,
            'install': CustomInstall,
        }
    )