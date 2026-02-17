from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import Optional

import typer
from rich.console import Console

from tribal_village_env.build import ensure_nim_library_current
from tribal_village_env.constants import DEFAULT_ANSI_STEPS, DEFAULT_PROFILE_STEPS
from tribal_village_env.environment import TribalVillageEnv

# Optional CoGames training integration
try:
    from tribal_village_env.cogames.cli import attach_train_command
except ImportError:  # CoGames not installed; CLI should still work for play mode
    attach_train_command = None  # type: ignore[assignment]

app = typer.Typer(
    help="CLI for playing Tribal Village",
    invoke_without_command=True,
    pretty_exceptions_show_locals=False,
    rich_markup_mode="rich",
    add_completion=False,
)
console = Console()

# Attempt to register the PufferLib trainer if CoGames is installed locally.
if attach_train_command is not None:
    attach_train_command(
        app, command_name="train", require_cogames=False, console_fallback=console
    )


def _project_root() -> Path:
    return Path(__file__).resolve().parent.parent


def _run_gui(
    profile: bool,
    profile_steps: int,
    step_timing: bool,
    step_timing_target: int,
    step_timing_window: int,
    render_timing: bool,
    render_timing_target: int,
    render_timing_window: int,
    render_timing_every: int,
    render_timing_exit: Optional[int],
) -> None:
    project_root = _project_root()
    cmd = ["nim", "r", "-d:release"]
    if profile:
        cmd.extend(["--profiler:on", "--stackTrace:on", "--lineTrace:on"])
    if step_timing:
        cmd.append("-d:stepTiming")
    if render_timing:
        cmd.append("-d:renderTiming")
    # Prefer the src entrypoint if present (it is included in source distributions via MANIFEST.in).
    if (project_root / "src" / "tribal_village.nim").exists():
        cmd.append("--path:src")
        cmd.append("src/tribal_village.nim")
    else:
        cmd.append("tribal_village.nim")

    env = os.environ.copy()
    if profile:
        env["TV_PROFILE_STEPS"] = str(profile_steps)
    if step_timing:
        env["TV_STEP_TIMING"] = str(step_timing_target)
        env["TV_STEP_TIMING_WINDOW"] = str(step_timing_window)
    if render_timing:
        env["TV_RENDER_TIMING"] = str(render_timing_target)
        env["TV_RENDER_TIMING_WINDOW"] = str(render_timing_window)
        env["TV_RENDER_TIMING_EVERY"] = str(render_timing_every)
        if render_timing_exit is not None:
            env["TV_RENDER_TIMING_EXIT"] = str(render_timing_exit)

    console.print("[cyan]Launching Tribal Village GUI via Nim...[/cyan]")
    subprocess.run(cmd, cwd=project_root, check=True, env=env)


def _run_ansi(steps: int, max_steps: Optional[int], random_actions: bool) -> None:
    config: dict[str, object] = {"render_mode": "ansi"}
    if max_steps is not None:
        config["max_steps"] = max_steps

    env = TribalVillageEnv(config=config)

    def _make_actions() -> dict[str, int]:
        return {
            f"agent_{agent_id}": int(env.single_action_space.sample()) if random_actions else 0
            for agent_id in range(env.num_agents)
        }

    try:
        env.reset()
        console.print(env.render())

        for step in range(steps):
            actions = _make_actions()
            _, _, terminated, truncated, _ = env.step(actions)
            console.print(env.render())

            if all(terminated.values()) or all(truncated.values()):
                console.print(f"[yellow]Episode ended at step {step + 1}[/yellow]")
                break
    finally:
        env.close()


def _options():
    return {
        "render": typer.Option(
            "gui",
            "--render",
            "-r",
            help="Render mode: gui (default) or ansi (text-only)",
        ),
        "steps": typer.Option(
            DEFAULT_ANSI_STEPS, "--steps", "-s", help="Steps to run when using ANSI render", min=1
        ),
        "max_steps": typer.Option(
            None, "--max-steps", help="Override max steps in ANSI mode", min=1
        ),
        "random_actions": typer.Option(
            True,
            "--random-actions/--no-random-actions",
            help="Use random actions in ANSI mode (otherwise no-op)",
        ),
        "profile": typer.Option(
            False,
            "--profile",
            help="Enable Nim profiler (GUI mode only; runs headless steps then exits)",
        ),
        "profile_steps": typer.Option(
            DEFAULT_PROFILE_STEPS,
            "--profile-steps",
            help="Steps to run when profiling",
            min=1,
        ),
        "step_timing": typer.Option(
            False,
            "--step-timing",
            help="Enable per-step timing logs (GUI mode only)",
        ),
        "step_timing_target": typer.Option(
            0,
            "--step-timing-target",
            help="Step index at which to start timing logs",
            min=0,
        ),
        "step_timing_window": typer.Option(
            0,
            "--step-timing-window",
            help="Number of steps to log starting at target",
            min=0,
        ),
        "render_timing": typer.Option(
            False,
            "--render-timing",
            help="Enable per-frame render timing logs (GUI mode only)",
        ),
        "render_timing_target": typer.Option(
            0,
            "--render-timing-target",
            help="Frame index at which to start render timing logs",
            min=0,
        ),
        "render_timing_window": typer.Option(
            0,
            "--render-timing-window",
            help="Number of frames to log starting at target",
            min=0,
        ),
        "render_timing_every": typer.Option(
            1,
            "--render-timing-every",
            help="Log every N frames within the timing window",
            min=1,
        ),
        "render_timing_exit": typer.Option(
            None,
            "--render-timing-exit",
            help="Exit after this frame index (GUI mode only)",
            min=1,
        ),
    }


@app.command("play", help="Play Tribal Village using the Nim GUI or ANSI renderer")
def play(
    render: str = _options()["render"],
    steps: int = _options()["steps"],
    max_steps: Optional[int] = _options()["max_steps"],
    random_actions: bool = _options()["random_actions"],
    profile: bool = _options()["profile"],
    profile_steps: int = _options()["profile_steps"],
    step_timing: bool = _options()["step_timing"],
    step_timing_target: int = _options()["step_timing_target"],
    step_timing_window: int = _options()["step_timing_window"],
    render_timing: bool = _options()["render_timing"],
    render_timing_target: int = _options()["render_timing_target"],
    render_timing_window: int = _options()["render_timing_window"],
    render_timing_every: int = _options()["render_timing_every"],
    render_timing_exit: Optional[int] = _options()["render_timing_exit"],
) -> None:
    ensure_nim_library_current()

    render_mode = render.lower()
    if render_mode not in {"gui", "ansi"}:
        console.print("[red]Invalid render mode. Use 'gui' or 'ansi'.[/red]")
        raise typer.Exit(1)

    if render_mode == "gui":
        _run_gui(
            profile=profile,
            profile_steps=profile_steps,
            step_timing=step_timing,
            step_timing_target=step_timing_target,
            step_timing_window=step_timing_window,
            render_timing=render_timing,
            render_timing_target=render_timing_target,
            render_timing_window=render_timing_window,
            render_timing_every=render_timing_every,
            render_timing_exit=render_timing_exit,
        )
    else:
        _run_ansi(steps=steps, max_steps=max_steps, random_actions=random_actions)


@app.callback(invoke_without_command=True)
def root(
    ctx: typer.Context,
    render: str = _options()["render"],
    steps: int = _options()["steps"],
    max_steps: Optional[int] = _options()["max_steps"],
    random_actions: bool = _options()["random_actions"],
    profile: bool = _options()["profile"],
    profile_steps: int = _options()["profile_steps"],
    step_timing: bool = _options()["step_timing"],
    step_timing_target: int = _options()["step_timing_target"],
    step_timing_window: int = _options()["step_timing_window"],
    render_timing: bool = _options()["render_timing"],
    render_timing_target: int = _options()["render_timing_target"],
    render_timing_window: int = _options()["render_timing_window"],
    render_timing_every: int = _options()["render_timing_every"],
    render_timing_exit: Optional[int] = _options()["render_timing_exit"],
) -> None:
    """Default to play when no subcommand is provided."""
    if ctx.invoked_subcommand is None:
        ctx.invoke(
            play,
            render=render,
            steps=steps,
            max_steps=max_steps,
            random_actions=random_actions,
            profile=profile,
            profile_steps=profile_steps,
            step_timing=step_timing,
            step_timing_target=step_timing_target,
            step_timing_window=step_timing_window,
            render_timing=render_timing,
            render_timing_target=render_timing_target,
            render_timing_window=render_timing_window,
            render_timing_every=render_timing_every,
            render_timing_exit=render_timing_exit,
        )


if __name__ == "__main__":
    app()
