#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def parse_seeds(raw: str) -> list[int]:
    seeds: list[int] = []
    for token in raw.split(","):
        token = token.strip()
        if not token:
            continue
        seeds.append(int(token))
    return seeds


def build_seeds(start: int, count: int) -> list[int]:
    return list(range(start, start + count))


def run_generate(out_dir: Path, seed: int, kind: str) -> bool:
    if kind == "in":
        only = "oriented/cliff_corner_in_nw.png"
    elif kind == "out":
        only = "oriented/cliff_corner_out_se.png"
    else:
        raise ValueError(f"Unknown kind '{kind}'")
    cmd = [
        sys.executable,
        "scripts/generate_assets.py",
        "--seed",
        str(seed),
        "--postprocess",
        "--postprocess-purple-bg",
        "--out-dir",
        str(out_dir),
        "--only",
        only,
    ]
    print(f"[gen] {kind} seed {seed} -> {out_dir}")
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as exc:
        print(f"[warn] generation failed for seed {seed} ({kind}): {exc}")
        return False
    return True


def write_manifest(path: Path, rows: list[tuple[str, Path]]) -> None:
    lines = [f"{label}\t{sprite.as_posix()}" for label, sprite in rows]
    path.write_text("\n".join(lines) + "\n")


def render_preview(manifest: Path, out_path: Path, title: str) -> None:
    cmd = [
        sys.executable,
        "scripts/render_asset_preview.py",
        "--manifest",
        manifest.as_posix(),
        "--out",
        out_path.as_posix(),
        "--title",
        title,
    ]
    subprocess.run(cmd, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate multiple cliff corner variants.")
    parser.add_argument(
        "--out-dir",
        default="data/tmp/cliff_variants",
        help="Base output directory for variants.",
    )
    parser.add_argument("--seeds", default="", help="Comma-separated seed list.")
    parser.add_argument("--start", type=int, default=1001, help="Seed start (if --seeds empty).")
    parser.add_argument("--count", type=int, default=5, help="How many seeds to generate.")
    parser.add_argument(
        "--kinds",
        default="in,out",
        help="Which variants to generate: in, out, or in,out.",
    )
    parser.add_argument("--include-current", action="store_true", help="Include current asset in preview.")
    parser.add_argument("--open", action="store_true", help="Open previews in Preview.app.")
    args = parser.parse_args()

    base_dir = Path(args.out_dir)
    base_dir.mkdir(parents=True, exist_ok=True)

    seeds = parse_seeds(args.seeds) if args.seeds else build_seeds(args.start, args.count)
    kinds = [k.strip() for k in args.kinds.split(",") if k.strip()]

    for seed in seeds:
        seed_dir = base_dir / f"seed{seed}"
        for kind in kinds:
            run_generate(seed_dir, seed, kind)

    previews: list[tuple[str, Path, str, str]] = []
    if "in" in kinds:
        rows: list[tuple[str, Path]] = []
        if args.include_current:
            rows.append(("Current", Path("data/oriented/cliff_corner_in_nw.png")))
        for seed in seeds:
            sprite = base_dir / f"seed{seed}" / "oriented" / "cliff_corner_in_nw.png"
            if sprite.exists():
                rows.append((f"Seed {seed}", sprite))
        manifest = base_dir / "preview_corner_in.tsv"
        preview = base_dir / "preview_corner_in.png"
        write_manifest(manifest, rows)
        previews.append((manifest.as_posix(), preview, "Corner In Variants", "preview_corner_in.png"))

    if "out" in kinds:
        rows = []
        if args.include_current:
            rows.append(("Current", Path("data/oriented/cliff_corner_out_se.png")))
        for seed in seeds:
            sprite = base_dir / f"seed{seed}" / "oriented" / "cliff_corner_out_se.png"
            if sprite.exists():
                rows.append((f"Seed {seed}", sprite))
        manifest = base_dir / "preview_corner_out.tsv"
        preview = base_dir / "preview_corner_out.png"
        write_manifest(manifest, rows)
        previews.append((manifest.as_posix(), preview, "Corner Out Variants", "preview_corner_out.png"))

    for manifest_path, preview_path, title, _ in previews:
        render_preview(Path(manifest_path), preview_path, title)
        if args.open:
            subprocess.run(["open", "-a", "Preview", preview_path.as_posix()], check=False)


if __name__ == "__main__":
    main()
