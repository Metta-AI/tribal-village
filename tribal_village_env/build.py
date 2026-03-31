from __future__ import annotations

import os
import platform
import shutil
import stat
import subprocess
import tempfile
import urllib.request
from pathlib import Path
from typing import Iterable

DEFAULT_NIM_VERSION = os.environ.get("TRIBAL_VILLAGE_NIM_VERSION", "2.2.6")
DEFAULT_NIMBY_VERSION = os.environ.get("TRIBAL_VILLAGE_NIMBY_VERSION", "0.1.11")


def _target_library_name() -> str:
    system = platform.system()
    if system == "Darwin":
        return "libtribal_village.dylib"
    if system == "Windows":
        return "libtribal_village.dll"
    return "libtribal_village.so"


def _target_binary_name() -> str:
    if platform.system() == "Windows":
        return "tribal_village.exe"
    return "tribal_village"


def _collect_source_files(project_root: Path) -> list[Path]:
    src_dir = project_root / "src"
    nim_sources = list(src_dir.rglob("*.nim")) if src_dir.exists() else []
    return nim_sources + [
        project_root / "tribal_village.nim",
        project_root / "tribal_village.nimble",
        project_root / "nim.cfg",
        project_root / "nimby.lock",
    ]


def _latest_mtime(paths: Iterable[Path]) -> float | None:
    mtimes = [path.stat().st_mtime for path in paths if path.exists()]
    if not mtimes:
        return None
    return max(mtimes)


def _build_library(project_root: Path) -> Path:
    _ensure_nim_toolchain()
    _install_nim_deps(project_root)

    ext = Path(_target_library_name()).suffix
    cmd = [
        "nim",
        "c",
        "--app:lib",
        "--mm:arc",
        "--opt:speed",
        "-d:danger",
        f"--out:libtribal_village{ext}",
        "src/ffi.nim",
    ]
    result = subprocess.run(cmd, cwd=project_root, capture_output=True, text=True)

    if result.returncode != 0:
        stdout = result.stdout.strip()
        stderr = result.stderr.strip()
        raise RuntimeError(
            f"Failed to build Nim library (exit {result.returncode}). stdout: {stdout} stderr: {stderr}"
        )

    for ext in (".dylib", ".dll", ".so"):
        candidate = project_root / f"libtribal_village{ext}"
        if candidate.exists():
            return candidate

    raise RuntimeError(
        "Build completed but libtribal_village.{so,dylib,dll} not found."
    )


def _build_binary(project_root: Path) -> Path:
    _ensure_nim_toolchain()
    _install_nim_deps(project_root)

    target_name = _target_binary_name()
    cmd = [
        "nim",
        "c",
        "-d:release",
        "--path:src",
        f"--out:{target_name}",
        "tribal_village.nim",
    ]
    result = subprocess.run(cmd, cwd=project_root, capture_output=True, text=True)

    if result.returncode != 0:
        stdout = result.stdout.strip()
        stderr = result.stderr.strip()
        raise RuntimeError(
            f"Failed to build Tribal Village binary (exit {result.returncode}). stdout: {stdout} stderr: {stderr}"
        )

    binary_path = project_root / target_name
    if binary_path.exists():
        return binary_path

    raise RuntimeError(f"Build completed but {target_name} was not found.")


def _needs_rebuild(target_path: Path, source_files: Iterable[Path]) -> bool:
    latest_source_mtime = _latest_mtime(source_files)
    target_mtime: float | None = (
        target_path.stat().st_mtime if target_path.exists() else None
    )
    return target_mtime is None or (
        latest_source_mtime is not None and target_mtime < latest_source_mtime
    )


def ensure_nim_library_current(verbose: bool = True) -> Path:
    """Rebuild libtribal_village if missing or stale."""
    package_dir = Path(__file__).resolve().parent
    project_root = package_dir.parent
    target_name = _target_library_name()
    target_path = package_dir / target_name

    source_files = _collect_source_files(project_root)
    needs_rebuild = _needs_rebuild(target_path, source_files)

    if not needs_rebuild:
        return target_path

    if verbose:
        print("Building Tribal Village Nim library to keep bindings current...")

    built_lib = _build_library(project_root)
    target_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(built_lib, target_path)

    if verbose:
        print(f"Copied {built_lib} to {target_path}")

    return target_path


def ensure_nim_binary_current(verbose: bool = True) -> Path:
    """Rebuild the GUI binary if missing or stale."""
    project_root = Path(__file__).resolve().parent.parent
    target_path = project_root / _target_binary_name()

    source_files = _collect_source_files(project_root)
    if not _needs_rebuild(target_path, source_files):
        return target_path

    if verbose:
        print("Building Tribal Village GUI binary to keep the launcher current...")

    return _build_binary(project_root)


def _ensure_nim_toolchain() -> None:
    """Ensure nimby is available and installs the requested Nim version."""

    nimby_path = shutil.which("nimby")

    system = platform.system()
    arch = platform.machine().lower()
    if nimby_path is None:
        if system == "Linux":
            url = f"https://github.com/treeform/nimby/releases/download/{DEFAULT_NIMBY_VERSION}/nimby-Linux-X64"
        elif system == "Darwin":
            suffix = "ARM64" if "arm" in arch else "X64"
            url = f"https://github.com/treeform/nimby/releases/download/{DEFAULT_NIMBY_VERSION}/nimby-macOS-{suffix}"
        else:
            raise RuntimeError(f"Unsupported OS for nimby bootstrap: {system}")

        dst = Path.home() / ".nimby" / "nim" / "bin" / "nimby"
        with tempfile.TemporaryDirectory() as tmp:
            nimby_dl = Path(tmp) / "nimby"
            urllib.request.urlretrieve(url, nimby_dl)
            nimby_dl.chmod(nimby_dl.stat().st_mode | stat.S_IEXEC)
            subprocess.check_call([str(nimby_dl), "use", DEFAULT_NIM_VERSION])

            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(nimby_dl, dst)

        nimby_path = str(dst)

    nim_bin_dir = Path.home() / ".nimby" / "nim" / "bin"
    os.environ["PATH"] = f"{nim_bin_dir}{os.pathsep}" + os.environ.get("PATH", "")

    if shutil.which("nim") is None:
        subprocess.check_call([nimby_path, "use", DEFAULT_NIM_VERSION])

    if shutil.which("nim") is None:
        raise RuntimeError("Failed to provision nim via nimby.")


def _install_nim_deps(project_root: Path) -> None:
    """Install Nim deps via nimby lockfile."""

    nimby = shutil.which("nimby")
    if nimby is None:
        raise RuntimeError("nimby not found after setup.")

    lockfile = project_root / "nimby.lock"
    if not lockfile.exists():
        raise RuntimeError(f"nimby.lock missing at {lockfile}")

    nim_cfg = project_root / "nim.cfg"
    if nim_cfg.exists():
        nim_cfg.unlink()

    result = subprocess.run(
        [nimby, "sync", "-g", str(lockfile)],
        cwd=project_root,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        stdout = result.stdout.strip()
        stderr = result.stderr.strip()
        raise RuntimeError(
            f"nimby sync failed (exit {result.returncode}). stdout: {stdout} stderr: {stderr}"
        )
