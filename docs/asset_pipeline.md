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
- Use `{orientation}` (or `{dir}`) in the prompt to insert orientation text.
- `orient=unit` uses unit directions; `orient=edge` uses cliff edge directions.

## Orientation Sets
Defined in `scripts/generate_assets.py`:
- `unit`: n, s, e, w, ne, nw, se, sw
- `edge`: ew, ew_s, ns, ns_w

The unit orientation text is explicit about left/right facing (for example, `se` is
"looking left" and `sw` is "looking right") to avoid flipped sprites. East/west
mirroring is also supported for stable prompts via `FLIP_ORIENTATIONS`.

## Generation Commands
Base assets:
- `python scripts/generate_assets.py --postprocess`

Oriented assets (default reference dir is `s`):
- `python scripts/generate_assets.py --oriented --postprocess --postprocess-purple-bg`

Limit to specific outputs:
- `python scripts/generate_assets.py --oriented --only oriented/builder.{dir}.png --postprocess`

Postprocess only (reuse `data/tmp`):
- `python scripts/generate_assets.py --postprocess-only --postprocess-tol 30`

## Postprocessing Pipeline
`apply_postprocess` in `scripts/generate_assets.py` performs:
1. Background removal (standard flood-fill or purple key).
2. Content crop using alpha connected components.
3. Resize to the requested square size.

Useful flags:
- `--postprocess-tol` adjusts chroma-key tolerance (default 35).
- `--postprocess-purple-bg` removes solid purple backgrounds before other steps.
- `--postprocess-purple-to-white` replaces purple highlights for team tinting.

## Preview Sheets
Use `render_asset_preview.py` to visually verify oriented or special assets:
- Default (cliff preview):
  `python scripts/render_asset_preview.py`
- Custom manifest (TSV):
  `python scripts/render_asset_preview.py --manifest path/to/manifest.tsv`
- Custom glob:
  `python scripts/render_asset_preview.py --glob 'data/oriented/*.png'`

Previews render a 3x3 grid with a sprite column to verify orientation and edge alignment.

## Size and Conventions
- Most item/building sprites are **256x256** with transparent backgrounds.
- Terrain tiles are top-down, full-tile coverage, and typically opaque.
- Cliff overlays commonly use **200x200** sprites.
- Oriented sprites live in `data/oriented/` and follow `{dir}` naming.

## Missing Asset Audit (2026-01-25)

The following oriented sprites are missing or incomplete:

| Entity | Status | Bead |
|--------|--------|------|
| Bear | Missing all 8 directions | tv-wisp-oip8 |
| Wolf | Missing all 8 directions | tv-wisp-ihxq |
| Cow | Has cow.png/cow.r.png only, needs 8 directions | tv-wisp-nt7q |

All other oriented unit sprites (gatherer, builder, fighter, man_at_arms, archer, scout, knight, monk, battering_ram, mangonel, boat, goblin, tumor) have complete 8-direction sets.

### Finding Missing Assets

To audit assets vs code definitions:

```bash
# List all entity kinds in code
grep -E "^\s+\w+$" src/types.nim | head -60

# List entities with oriented spriteKeys in registry
grep 'oriented/' src/registry.nim

# List existing oriented sprites
ls data/oriented/*.png | sort

# Cross-reference to find gaps
```

## Authentication Setup

The `generate_assets.py` script requires Google Cloud authentication:

### Option A: API Key (Simplest)
```bash
export GOOGLE_API_KEY=your_api_key_here
```
Get a key from: https://makersuite.google.com/app/apikey

### Option B: Application Default Credentials (ADC)
```bash
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

### Option C: Vertex AI (Enterprise)
```bash
export GOOGLE_CLOUD_PROJECT=your-project-id
export GOOGLE_CLOUD_LOCATION=us-central1
gcloud auth application-default login
```

## Troubleshooting Checklist
1. Confirm the prompt row exists in `data/prompts/assets.tsv`.
2. Verify the output file is in `data/` or `data/oriented/`.
3. Inspect raw output under `data/tmp/` if postprocessing fails.
4. Adjust `--postprocess-tol` and rerun `--postprocess-only`.
5. Use the preview sheet to spot misaligned orientation or transparency artifacts.
