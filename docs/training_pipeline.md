# Training Pipeline

## Local Training (this repo)
The Python entrypoint is exposed as a console script:

```bash
tribal-village train --steps 1000000 --parallel-envs 8 --num-workers 4 --log-outputs
```

This command is defined in `tribal_village_env.cli` and uses pufferlib-backed
training under the hood.

### Defaults
- Checkpoints: `./train_dir`
- Render mode: `ansi` (train-only)
- Episode length: 1000 steps

## Training via Metta Workspace
For the metta monorepo, use the helper script from this repo:

```bash
scripts/train_metta.sh --steps 1000000 --parallel-envs 8 --num-workers 4 --log-outputs
```

The script runs:
- `uv run` inside the metta checkout
- With the `tribal-village` optional dependency enabled

Override the metta checkout path if needed:

```bash
METTA_DIR=/path/to/metta scripts/train_metta.sh --steps 1000000 --parallel-envs 8
```

## CoGames CLI
If you have the `cogames` extras installed, you can also run:

```bash
cogames train-tribal -p class=tribal --steps 1000000 --parallel-envs 8 --num-workers 4
```

## Packaging Notes
- The package is installable via `pyproject.toml`.
- The optional dependency group `cogames` points to metta's `packages/cogames`.
- The training CLI expects the native lib to be available
  (`tribal_village_env/libtribal_village.*`).
