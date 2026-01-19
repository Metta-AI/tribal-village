# Asset Pipeline and Oriented Sprites

Date: 2026-01-19
Owner: Docs / Art Systems
Status: Draft

## Purpose
Codex sessions repeatedly hit issues around missing sprites, incorrect orientations, and
post-processing artifacts. This doc captures the current asset pipeline, how oriented
sprites are generated, and the knobs that control cleanup.

## Asset Locations
- `data/*.png` : primary map + inventory sprites
- `data/oriented/*.png` : directional unit and edge sprites
- `data/ui/*.png` : UI-only assets
- `data/prompts/assets.tsv` : prompt source of truth
- `data/tmp/` : raw generations (kept for inspection)

## Prompt File Format
`data/prompts/assets.tsv` is TSV with 2 or 3 columns:
1. output filename (relative to `data/`)
2. prompt text
3. optional flags (comma-separated key=value pairs)

Examples:
- `barracks.png<TAB>...prompt...`
- `oriented/builder.{dir}.png<TAB>...prompt with {orientation}...<TAB>orient=unit`

Notes:
- Use `{dir}` in the filename to request oriented output.
- Use `{orientation}` (or `{dir}`) in the prompt to insert the orientation text.
- `orient=unit` uses unit directions; `orient=edge` uses cliff edge directions.

## Orientation Sets
Defined in `scripts/generate_assets.py`:
- `unit`: n, s, e, w, ne, nw, se, sw
- `edge`: ew, ew_s, ns, ns_w

The unit orientation text is explicit about left/right facing (for example, `se` is
"looking left" and `sw` is "looking right") to avoid flipped sprites.

## Generation Commands
Base assets:
- `python scripts/generate_assets.py --postprocess`

Oriented assets (default reference dir is `s`):
- `python scripts/generate_assets.py --oriented --postprocess --postprocess-purple-bg`

Limit to specific outputs:
- `python scripts/generate_assets.py --oriented --only oriented/builder.{dir}.png --postprocess`

Postprocess only (reuse `data/tmp`):
- `python scripts/generate_assets.py --postprocess-only --postprocess-tol 30`

## Postprocessing Knobs
- `--postprocess-tol` adjusts chroma-key tolerance (default 35).
- `--postprocess-purple-bg` removes solid purple backgrounds before other steps.
- `--postprocess-purple-to-white` replaces purple highlights for team tinting.

Guidance from recent sessions:
- Keep unit tunics neutral so team colors tint cleanly.
- Prefer a solid royal purple background for oriented units to avoid edge artifacts.
- Use `--postprocess-only` to iterate on tolerance without regenerating.
- East/west can be mirrored when the prompt is stable (see `FLIP_ORIENTATIONS`).

## Size and Consistency
- Default output size is 200x200 (see `--size` in `scripts/generate_assets.py`).
- Keep all new unit sprites consistent in size to avoid rendering jitter.
- Use `scripts/render_asset_preview.py` to spot orientation and transparency issues.

## Troubleshooting Checklist
1. Confirm the prompt row exists in `data/prompts/assets.tsv`.
2. Verify the output file is in `data/` or `data/oriented/`.
3. Inspect raw output under `data/tmp/` if postprocessing fails.
4. Adjust `--postprocess-tol` and rerun `--postprocess-only`.
