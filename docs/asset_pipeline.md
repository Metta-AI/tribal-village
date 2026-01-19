# Asset Generation and Postprocessing

Date: 2026-01-19
Owner: Docs / Systems
Status: Draft

## Purpose
This document describes how art assets are generated, postprocessed, and previewed.
It covers the prompt TSV workflow, oriented sprites, flood-fill cleanup, and preview sheets.

Key implementation files:
- `scripts/generate_assets.py`
- `scripts/render_asset_preview.py`
- `data/prompts/assets.tsv`
- `data/tmp/`
- `data/oriented/`

## Prompt-Driven Generation
Asset prompts live in `data/prompts/assets.tsv` (TSV: filename, prompt, optional flags).
The generator reads this file and produces PNGs under `data/`.

Example usage:
- Generate new assets:
  `python scripts/generate_assets.py --prompts data/prompts/assets.tsv --out-dir data`
- Generate oriented assets (rows with `{dir}`):
  `python scripts/generate_assets.py --oriented --postprocess --postprocess-purple-bg`

## Oriented Sprites
- Oriented sprites use `{dir}` in filenames and prompts (e.g., `oriented/gatherer.{dir}.png`).
- Orientation sets are defined in `scripts/generate_assets.py` (`unit`, `edge`).
- The oriented workflow can use reference images and flip rules to reduce model calls.
- Oriented sprites commonly use a solid royal-purple background; use
  `--postprocess-purple-bg` to key it out before cropping.

## Postprocessing Pipeline
`apply_postprocess` in `scripts/generate_assets.py` performs:
1. **Background removal**
   - Flood-fill removal for regular backgrounds.
   - Purple background keying for oriented sprites.
2. **Content crop**
   - Uses alpha-based connected components to find the tight content bounds.
3. **Resize**
   - Cropped content is resized to the target square size.

Important flags:
- `--postprocess` : apply postprocessing after generation.
- `--postprocess-only` : run postprocessing on existing files.
- `--postprocess-purple-bg` : key out royal purple background first.
- `--size` : output size (many assets are 256; cliff overlays often use 200).

## Preview Sheets
Use `render_asset_preview.py` to visually verify oriented or special assets:
- Default (cliff preview):
  `python scripts/render_asset_preview.py`
- Custom manifest (TSV):
  `python scripts/render_asset_preview.py --manifest path/to/manifest.tsv`
- Custom glob:
  `python scripts/render_asset_preview.py --glob 'data/oriented/*.png'`

Previews render a 3x3 grid with a sprite column to verify orientation and edge alignment.

## Conventions
- Most item/building sprites are **256x256** with transparent backgrounds.
- Terrain tiles are top-down, full-tile coverage, and typically opaque.
- Oriented sprites live in `data/oriented/` and follow `{dir}` naming.
- Cliff overlays are separate sprites and should align to tile midpoints consistently.

## Common Pitfalls
- Partial alpha or white borders: ensure flood-fill and crop steps are applied.
- Wrong size: re-run postprocess with `--size` to normalize.
- Orientation mismatch: confirm `{dir}` mappings and preview with the grid sheet.
