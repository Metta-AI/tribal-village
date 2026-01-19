# Training and Replay Integration Notes

Date: 2026-01-19
Owner: Docs / ML Systems
Status: Draft

## Purpose
Codex sessions frequently revisit training wiring, metta integration, and replay support.
This doc summarizes the current training flow and the replay writer hooks that exist today.

## Training Entry Points
Primary CLI (requires CoGames extra):
- `pip install -e .[cogames]`
- `tribal-village train --steps 1000000 --parallel-envs 8 --num-workers 4 --log-outputs`

Alternative via CoGames CLI:
- `cogames train-tribal -p class=tribal --steps 1000000 --parallel-envs 8 --num-workers 4 --log-outputs`

Metta workspace helper:
- `scripts/train_metta.sh --steps 1000000 --parallel-envs 8 --num-workers 4 --log-outputs`
- Set `METTA_DIR=/path/to/metta` if the repo lives elsewhere.

Key files:
- `tribal_village_env/cogames/cli.py`
- `tribal_village_env/cogames/train.py`
- `tribal_village_env/environment.py`

## Packaging Notes
- The repo is a standalone, installable Python package (pyproject-based).
- If training from a metta checkout, avoid older copies of tribal-village to prevent
  conflicts in import resolution.
- PufferLib vs pufferlib-core mismatches have caused issues in past sessions; prefer the
  versions pinned in the workspace you are running.

## Replay Writer (Nim)
Replay output is supported in Nim via `src/replay_writer.nim` (ReplayVersion = 3).
It is opt-in and controlled by environment variables:
- `TV_REPLAY_DIR` : directory for replay files
- `TV_REPLAY_PATH` : explicit replay file path (overrides dir)
- `TV_REPLAY_NAME` : base name (default `tribal_village`)
- `TV_REPLAY_LABEL` : label metadata

Replays are written as compressed JSON: `*.json.z`.

To enable during a run:
1. Export `TV_REPLAY_DIR` (or `TV_REPLAY_PATH`).
2. Run `tribal-village play` (or `nim r -d:release tribal_village.nim`).
3. Verify output in the chosen directory.

## Common Training Issues Seen in Sessions
- "SPS = 0" or no logs: check PufferLib versions and vector env wiring.
- CLI confusion when `tribal-village train` is missing: install the `cogames` extra.
- Metta symlink setups can import the wrong package if an old copy exists.

## Suggested Follow-ups
- Wire replay output into the Python training pipeline (set `TV_REPLAY_DIR` in train
  wrappers when desired).
- Add a README snippet whenever the training entry point changes.
