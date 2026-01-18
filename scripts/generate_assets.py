#!/usr/bin/env python
from __future__ import annotations

import argparse
import io
import os
from collections import deque
import re
from pathlib import Path
from typing import Iterable, Iterator, NamedTuple

from google import genai
from google.genai import types
from PIL import Image
import cv2  # type: ignore
import numpy as np  # type: ignore

# Setup notes:
# - Option A (API key): export GOOGLE_API_KEY=...
# - Option B (gcloud ADC): install gcloud and run
#   `gcloud auth application-default login`, then set the project via
#   `gcloud config set project <id>` or pass `--project <id>` (location must be "global").


ORIENTATION_TEMPLATES = [
    ("n", "Back view facing away from the camera."),
    ("s", "Front view facing the camera."),
    ("e", "Right-facing profile view."),
    ("w", "Left-facing profile view."),
    ("ne", "Three-quarter back view facing up-right (northeast), facing away from camera."),
    ("nw", "Three-quarter back view facing up-left (northwest), facing away from camera."),
    ("se", "Three-quarter view facing down-right (southeast), looking left."),
    ("sw", "Three-quarter view facing down-left (southwest), looking right."),
]
EDGE_ORIENTATIONS = [
    (
        "ew",
        "Horizontal cliff edge segment running east-west, spanning fully from left edge to right edge with no diagonal sections. High ground/rim with grass tufts is on the north (top) side; low ground/rock face drop is on the south (bottom) side.",
    ),
    (
        "ew_s",
        "Horizontal cliff edge segment running east-west, spanning fully from left edge to right edge with no diagonal sections. Depict higher ground on the south (bottom) side that descends northward down a cliff face to a lower plain on the north (top) side. Grass tufts only on the high rim.",
    ),
    (
        "ns",
        "Vertical cliff edge segment running north-south, spanning fully from top edge to bottom edge with no diagonal sections. High ground/rim with grass tufts is on the east (right) side; low ground/rock face drop is on the west (left) side.",
    ),
    (
        "ns_w",
        "Vertical cliff edge segment running north-south, spanning fully from top edge to bottom edge with no diagonal sections. High ground/rim with grass tufts is on the west (left) side; low ground/rock face drop is on the east (right) side.",
    ),
]

ORIENTATION_SETS = {
    "unit": ORIENTATION_TEMPLATES,
    "edge": EDGE_ORIENTATIONS,
}


class OrientedRow(NamedTuple):
    filename_template: str
    prompt_template: str
    orientation_set: str
    allowed_dirs: set[str] | None
    reference_dir: str | None


class OrientedOutput(NamedTuple):
    filename: str
    prompt: str
    dir_key: str
    reference_filename: str
    orientation_set: str
    reference_dir: str

def parse_flags(raw: str) -> dict[str, str]:
    flags: dict[str, str] = {}
    if not raw:
        return flags
    for token in raw.split(","):
        token = token.strip()
        if not token:
            continue
        if "=" in token:
            key, value = token.split("=", 1)
            flags[key.strip()] = value.strip()
        else:
            flags[token] = "true"
    return flags


def resolve_orientation_set(name: str) -> list[tuple[str, str]]:
    if name not in ORIENTATION_SETS:
        raise ValueError(f"Unknown orientation set '{name}' (expected one of {sorted(ORIENTATION_SETS)})")
    return ORIENTATION_SETS[name]


def parse_dirs(raw: str | None) -> set[str] | None:
    if not raw:
        return None
    parts = [part.strip() for part in re.split(r"[|;,]", raw) if part.strip()]
    return set(parts)


def expand_oriented_row(
    filename: str,
    prompt: str,
    orientation_set: str,
    allowed_dirs: set[str] | None,
) -> list[tuple[str, str]]:
    if "{dir}" not in filename:
        if "{orientation}" in prompt or "{dir}" in prompt:
            raise ValueError(f"Orientation placeholder requires {{dir}} in filename: {filename}")
        return [(filename, prompt)]
    rows: list[tuple[str, str]] = []
    for dir_key, orientation in resolve_orientation_set(orientation_set):
        if allowed_dirs and dir_key not in allowed_dirs:
            continue
        subs = {
            "dir": dir_key,
            "dir_upper": dir_key.upper(),
            "orientation": orientation,
        }
        try:
            expanded_name = filename.format(**subs)
            expanded_prompt = prompt.format(**subs)
        except KeyError as exc:
            raise ValueError(f"Unknown placeholder in prompt row: {filename}") from exc
        rows.append((expanded_name, expanded_prompt))
    return rows


def parse_prompt_line(raw: str) -> tuple[str, str, dict[str, str]]:
    line = raw.strip()
    if not line or line.startswith("#"):
        return "", "", {}
    parts = line.split("\t")
    if len(parts) not in (2, 3):
        raise ValueError(f"Invalid prompt line (expected TSV with 2 or 3 columns): {raw}")
    filename = parts[0].strip()
    prompt = parts[1].strip()
    flags = parse_flags(parts[2].strip()) if len(parts) == 3 else {}
    return filename, prompt, flags


def load_prompts(path: Path) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    for raw in path.read_text().splitlines():
        filename, prompt, flags = parse_prompt_line(raw)
        if not filename:
            continue
        orientation_set = flags.get("orient", "unit")
        allowed_dirs = parse_dirs(flags.get("dirs"))
        rows.extend(expand_oriented_row(filename, prompt, orientation_set, allowed_dirs))
    return rows


def load_oriented_rows(path: Path) -> list[OrientedRow]:
    rows: list[OrientedRow] = []
    for raw in path.read_text().splitlines():
        filename, prompt, flags = parse_prompt_line(raw)
        if not filename:
            continue
        orientation_set = flags.get("orient", "unit")
        allowed_dirs = parse_dirs(flags.get("dirs"))
        reference_dir = flags.get("ref") or flags.get("reference")
        if "{dir}" in filename:
            rows.append(
                OrientedRow(
                    filename_template=filename,
                    prompt_template=prompt,
                    orientation_set=orientation_set,
                    allowed_dirs=allowed_dirs,
                    reference_dir=reference_dir,
                )
            )
    return rows


def iter_oriented_rows(
    rows: Iterable[OrientedRow],
    reference_dir: str,
    only: set[str] | None,
) -> Iterator[OrientedOutput]:
    for row in rows:
        orientation_set = resolve_orientation_set(row.orientation_set)
        orientation_map = {key: text for key, text in orientation_set}
        row_reference_dir = row.reference_dir or reference_dir
        for dir_key, orientation in orientation_set:
            if row.allowed_dirs and dir_key not in row.allowed_dirs:
                continue
            subs = {
                "dir": dir_key,
                "dir_upper": dir_key.upper(),
                "orientation": orientation,
            }
            out_name = row.filename_template.format(**subs)
            if only and out_name not in only and Path(out_name).name not in only:
                continue
            if row_reference_dir not in orientation_map:
                raise ValueError(
                    f"Unknown reference dir '{row_reference_dir}' for orient={row.orientation_set} "
                    f"(expected one of {sorted(orientation_map)})"
                )
            reference_orientation = orientation_map[row_reference_dir]
            prompt = row.prompt_template.format(**subs)
            ref_subs = {
                "dir": row_reference_dir,
                "dir_upper": row_reference_dir.upper(),
                "orientation": reference_orientation,
            }
            ref_name = row.filename_template.format(**ref_subs)
            yield OrientedOutput(
                filename=out_name,
                prompt=prompt,
                dir_key=dir_key,
                reference_filename=ref_name,
                orientation_set=row.orientation_set,
                reference_dir=row_reference_dir,
            )


def make_client(project: str | None, location: str | None) -> genai.Client:
    api_key = os.environ.get("GOOGLE_API_KEY")
    if api_key:
        return genai.Client(api_key=api_key)
    return genai.Client(vertexai=True, project=project, location=location)


def extract_inline_image(response) -> bytes:
    if not response.candidates:
        raise RuntimeError("No candidates returned from API.")
    for part in response.candidates[0].content.parts:
        inline = getattr(part, "inline_data", None)
        if inline and inline.data:
            return inline.data
    raise RuntimeError("No inline image data found in response.")


DEFAULT_MODEL = "gemini-3-pro-image-preview"
ALLOWED_MODELS = {
    "gemini-2.5-flash-image",
    "publishers/google/models/gemini-2.5-flash-image",
    "gemini-3-pro-image-preview",
    "publishers/google/models/gemini-3-pro-image-preview",
}


def build_config(seed: int) -> types.GenerateContentConfig:
    return types.GenerateContentConfig(
        response_modalities=["IMAGE"],
        image_config=types.ImageConfig(output_mime_type="image/png", aspect_ratio="1:1"),
        seed=seed,
        safety_settings=[
            types.SafetySetting(
                category=types.HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
                threshold=types.HarmBlockThreshold.BLOCK_ONLY_HIGH,
            ),
            types.SafetySetting(
                category=types.HarmCategory.HARM_CATEGORY_HATE_SPEECH,
                threshold=types.HarmBlockThreshold.BLOCK_ONLY_HIGH,
            ),
            types.SafetySetting(
                category=types.HarmCategory.HARM_CATEGORY_HARASSMENT,
                threshold=types.HarmBlockThreshold.BLOCK_ONLY_HIGH,
            ),
            types.SafetySetting(
                category=types.HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
                threshold=types.HarmBlockThreshold.BLOCK_ONLY_HIGH,
            ),
        ],
    )


def generate_image(
    client: genai.Client,
    model: str,
    prompt: str,
    seed: int,
    size: int,
) -> Image.Image:
    config = build_config(seed)
    response = client.models.generate_content(model=model, contents=prompt, config=config)
    image_bytes = extract_inline_image(response)
    img = Image.open(io.BytesIO(image_bytes)).convert("RGBA")
    return img


def generate_oriented_image(
    client: genai.Client,
    model: str,
    prompt: str,
    seed: int,
    size: int,
    reference_path: Path,
) -> Image.Image:
    config = build_config(seed)
    reference_bytes = reference_path.read_bytes()
    parts = [
        types.Part.from_bytes(data=reference_bytes, mime_type="image/png"),
        types.Part.from_text(text=prompt),
    ]
    response = client.models.generate_content(model=model, contents=parts, config=config)
    image_bytes = extract_inline_image(response)
    img = Image.open(io.BytesIO(image_bytes)).convert("RGBA")
    return img


def flood_fill_bg_cv2(img: Image.Image, tol: int = 18) -> Image.Image:
    if img.mode != "RGBA":
        img = img.convert("RGBA")

    w, h = img.size
    px = img.load()
    border_colors: dict[tuple[int, int, int], int] = {}
    for x in range(w):
        for y in (0, h - 1):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            key = (r // 8, g // 8, b // 8)
            border_colors[key] = border_colors.get(key, 0) + 1
    for y in range(h):
        for x in (0, w - 1):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            key = (r // 8, g // 8, b // 8)
            border_colors[key] = border_colors.get(key, 0) + 1

    if border_colors:
        top = sorted(border_colors.items(), key=lambda item: item[1], reverse=True)[:4]
        bg_colors = [(k[0] * 8, k[1] * 8, k[2] * 8) for k, _ in top]
    else:
        bg_colors = [px[x, y][:3] for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1))]

    def color_close(c, ref) -> bool:
        return all(abs(int(c[i]) - int(ref[i])) <= tol for i in range(3))

    arr = np.array(img)
    rgb = arr[:, :, :3].copy()
    alpha = arr[:, :, 3]
    if bg_colors:
        rgb[alpha == 0] = bg_colors[0]

    mask = np.zeros((h + 2, w + 2), dtype=np.uint8)
    lo = (tol, tol, tol)
    up = (tol, tol, tol)
    flags = cv2.FLOODFILL_MASK_ONLY | (255 << 8)

    for x in range(w):
        for y in (0, h - 1):
            if mask[y + 1, x + 1] != 0:
                continue
            r, g, b, a = px[x, y]
            if a == 0 or any(color_close((r, g, b), ref) for ref in bg_colors):
                cv2.floodFill(rgb, mask, (x, y), (0, 0, 0), loDiff=lo, upDiff=up, flags=flags)
    for y in range(h):
        for x in (0, w - 1):
            if mask[y + 1, x + 1] != 0:
                continue
            r, g, b, a = px[x, y]
            if a == 0 or any(color_close((r, g, b), ref) for ref in bg_colors):
                cv2.floodFill(rgb, mask, (x, y), (0, 0, 0), loDiff=lo, upDiff=up, flags=flags)

    fill_mask = mask[1:-1, 1:-1] != 0
    arr[:, :, 3][fill_mask] = 0
    return Image.fromarray(arr, "RGBA")


def flood_fill_bg(img: Image.Image, tol: int = 18) -> Image.Image:
    return flood_fill_bg_cv2(img, tol)


def alpha_bbox_cv2(
    alpha: np.ndarray,
    min_border_fraction: float = 0.004,
    min_border_pixels: int = 64,
    min_alpha: int = 1,
) -> tuple[int, int, int, int] | None:
    mask = (alpha >= min_alpha).astype("uint8")
    if not mask.any():
        return None
    num, labels, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
    if num <= 1:
        return None
    total_area = int(mask.sum())
    min_border_area = max(min_border_pixels, int(total_area * min_border_fraction))
    h, w = mask.shape
    keep: list[int] = []
    for idx in range(1, num):
        left = stats[idx, cv2.CC_STAT_LEFT]
        top = stats[idx, cv2.CC_STAT_TOP]
        width = stats[idx, cv2.CC_STAT_WIDTH]
        height = stats[idx, cv2.CC_STAT_HEIGHT]
        area = stats[idx, cv2.CC_STAT_AREA]
        touches_border = (
            left == 0
            or top == 0
            or left + width >= w
            or top + height >= h
        )
        if touches_border and area < min_border_area:
            continue
        keep.append(idx)
    if not keep:
        ys, xs = np.where(mask)
        if len(xs) == 0:
            return None
        return (int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1))
    left = int(min(stats[idx, cv2.CC_STAT_LEFT] for idx in keep))
    top = int(min(stats[idx, cv2.CC_STAT_TOP] for idx in keep))
    right = int(max(stats[idx, cv2.CC_STAT_LEFT] + stats[idx, cv2.CC_STAT_WIDTH] for idx in keep))
    bottom = int(max(stats[idx, cv2.CC_STAT_TOP] + stats[idx, cv2.CC_STAT_HEIGHT] for idx in keep))
    return (left, top, right, bottom)


def crop_to_content(
    img: Image.Image,
    target_size: int,
    padding_frac: float = 0.1,
) -> Image.Image:
    w, h = img.size
    alpha = img.getchannel("A")
    bbox = alpha_bbox_cv2(np.array(alpha))
    if not bbox:
        return img
    minx, miny, maxx, maxy = bbox
    box_w = maxx - minx
    box_h = maxy - miny
    side = max(box_w, box_h)
    if padding_frac > 0:
        pad = int(round(side * padding_frac))
        side = side + pad * 2
    cx = minx + box_w // 2
    cy = miny + box_h // 2
    half = side // 2
    left = max(0, cx - half)
    top = max(0, cy - half)
    right = min(w, left + side)
    bottom = min(h, top + side)
    if right - left < side:
        left = max(0, right - side)
    if bottom - top < side:
        top = max(0, bottom - side)
    cropped = img.crop((left, top, right, bottom))
    if target_size and cropped.size != (target_size, target_size):
        cropped = cropped.resize((target_size, target_size), Image.LANCZOS)
    return cropped


def purple_bg_mask(arr: np.ndarray) -> np.ndarray:
    # Use HSV to capture magenta/purple backgrounds even when hue drifts.
    bgr = arr[:, :, :3][:, :, ::-1]
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    h = hsv[:, :, 0]
    s = hsv[:, :, 1]
    v = hsv[:, :, 2]
    alpha = arr[:, :, 3]
    return (
        (alpha > 0)
        & (h >= 100)
        & (h <= 150)
        & (s >= 80)
        & (v >= 80)
    )


def flood_fill_purple_bg(img: Image.Image) -> Image.Image:
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    arr = np.array(img)
    mask = purple_bg_mask(arr).astype("uint8")
    if not mask.any():
        return img
    h, w = mask.shape
    visited = np.zeros(mask.shape, dtype=bool)
    q: deque[tuple[int, int]] = deque()

    def enqueue(x: int, y: int) -> None:
        if mask[y, x] == 1 and not visited[y, x]:
            visited[y, x] = True
            q.append((x, y))

    for x in range(w):
        enqueue(x, 0)
        enqueue(x, h - 1)
    for y in range(h):
        enqueue(0, y)
        enqueue(w - 1, y)

    while q:
        x, y = q.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and mask[ny, nx] == 1 and not visited[ny, nx]:
                visited[ny, nx] = True
                q.append((nx, ny))

    if visited.any():
        arr[:, :, 3][visited] = 0
    return Image.fromarray(arr, "RGBA")


def apply_postprocess(
    img: Image.Image,
    target_size: int,
    tol: int = 18,
    purple_to_white: bool = False,
    purple_bg: bool = False,
) -> Image.Image:
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    if purple_bg:
        img = flood_fill_purple_bg(img)
        img = crop_to_content(img, target_size)
    else:
        img = flood_fill_bg(img, tol)
        img = crop_to_content(img, target_size)
    if purple_to_white:
        px = img.load()
        w, h = img.size
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                if a == 0:
                    continue
                if r >= 180 and b >= 180 and g <= 120:
                    px[x, y] = (255, 255, 255, a)
    return img


def flip_horizontal(img: Image.Image) -> Image.Image:
    return img.transpose(Image.FLIP_LEFT_RIGHT)


def maybe_derive_cliff_variants(target: Path, out_dir: Path) -> None:
    try:
        relative = target.relative_to(out_dir)
    except ValueError:
        relative = target
    rel = relative.as_posix()
    if rel == "oriented/cliff_corner_in_nw.png":
        with Image.open(target) as existing:
            base = existing.convert("RGBA")
        corner_dir = target.parent
        img_ne = flip_horizontal(base)
        img_sw = base.transpose(Image.ROTATE_90)
        img_se = flip_horizontal(img_sw)
        corner_dir.mkdir(parents=True, exist_ok=True)
        img_ne.save(corner_dir / "cliff_corner_in_ne.png")
        img_sw.save(corner_dir / "cliff_corner_in_sw.png")
        img_se.save(corner_dir / "cliff_corner_in_se.png")
        return
    if rel == "oriented/cliff_corner_out_se.png":
        with Image.open(target) as existing:
            base = existing.convert("RGBA")
        corner_dir = target.parent
        img_sw = flip_horizontal(base)
        img_ne = base.transpose(Image.ROTATE_90)
        img_nw = flip_horizontal(img_ne)
        corner_dir.mkdir(parents=True, exist_ok=True)
        img_sw.save(corner_dir / "cliff_corner_out_sw.png")
        img_ne.save(corner_dir / "cliff_corner_out_ne.png")
        img_nw.save(corner_dir / "cliff_corner_out_nw.png")
        return


def swap_orientation_token(filename: str, old: str, new: str) -> str:
    replacements = [
        (f".{old}.", f".{new}."),
        (f"_{old}.", f"_{new}."),
        (f"_{old}_", f"_{new}_"),
        (f"/{old}.", f"/{new}."),
    ]
    for src, dst in replacements:
        if src in filename:
            return filename.replace(src, dst)
    return filename.replace(old, new, 1)


def tmp_path_for(target: Path, out_dir: Path, tmp_dir: Path) -> Path:
    try:
        relative = target.relative_to(out_dir)
    except ValueError:
        return tmp_dir / target.name
    return tmp_dir / relative


def postprocess_to_target(
    source: Path,
    target: Path,
    size: int,
    tol: int,
    purple_to_white: bool,
    purple_bg: bool,
) -> None:
    with Image.open(source) as existing:
        img = existing.convert("RGBA")
    img = apply_postprocess(img, size, tol, purple_to_white, purple_bg)
    target.parent.mkdir(parents=True, exist_ok=True)
    img.save(target)


def iter_rows(
    rows: Iterable[tuple[str, str]],
    only: set[str] | None,
) -> Iterable[tuple[str, str]]:
    for filename, prompt in rows:
        if only:
            if filename not in only and Path(filename).name not in only:
                continue
        yield filename, prompt


def build_oriented_prompt(prompt: str) -> str:
    return (
        "Use the provided reference image as the same unit. "
        "Match palette, silhouette, proportions, and line weight. "
        "Keep lighting consistent and preserve the background described in the prompt. "
        + prompt
    )


FLIP_ORIENTATIONS = {
    "unit": {
        "e": "w",
        "ne": "nw",
        "se": "sw",
    },
    "edge": {
        "ns_w": "ns",
    },
}

def oriented_uses_purple_bg(output: OrientedOutput) -> bool:
    return output.orientation_set in {"unit", "edge"}


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate image assets from TSV prompts.")
    parser.add_argument("--prompts", default="data/prompts/assets.tsv")
    parser.add_argument("--out-dir", default="data")
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help="Gemini image model (global endpoint only).",
    )
    parser.add_argument("--project", default=os.environ.get("GOOGLE_CLOUD_PROJECT"))
    parser.add_argument("--location", default=os.environ.get("GOOGLE_CLOUD_LOCATION", "global"))
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--size", type=int, default=200, help="Output square size.")
    parser.add_argument("--postprocess", action="store_true")
    parser.add_argument("--postprocess-only", action="store_true")
    parser.add_argument("--postprocess-tol", type=int, default=35, help="Background keying tolerance.")
    parser.add_argument(
        "--postprocess-purple-to-white",
        action="store_true",
        help="Replace bright purple pixels with white for team tinting.",
    )
    parser.add_argument(
        "--postprocess-purple-bg",
        action="store_true",
        help="Key out solid royal purple backgrounds before other postprocessing.",
    )
    parser.add_argument(
        "--oriented",
        action="store_true",
        help="Generate oriented sprites using reference images (rows with {dir}).",
    )
    parser.add_argument(
        "--reference-dir",
        default="s",
        help="Orientation to use as the reference image (default: s).",
    )
    parser.add_argument(
        "--include-reference",
        action="store_true",
        help="Also generate the reference orientation instead of skipping it.",
    )
    parser.add_argument("--only", default="", help="Comma-separated filenames to generate.")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    prompt_path = Path(args.prompts)
    only = {p.strip() for p in args.only.split(",") if p.strip()} or None

    client = None
    if not args.dry_run and not args.postprocess_only:
        if args.location != "global":
            raise SystemExit("Only the global endpoint is supported for image generation.")
        if args.model not in ALLOWED_MODELS:
            raise SystemExit("Only supported Gemini image models are allowed.")
        client = make_client(args.project, args.location)
    out_dir = Path(args.out_dir)
    tmp_dir = out_dir / "tmp"

    if args.oriented:
        oriented_rows = load_oriented_rows(prompt_path)
        if not oriented_rows:
            raise SystemExit("No oriented rows found (filenames containing {dir}).")
        outputs = list(iter_oriented_rows(oriented_rows, args.reference_dir, only))
        non_flip: list[OrientedOutput] = []
        flip: list[OrientedOutput] = []
        for output in outputs:
            flip_map = FLIP_ORIENTATIONS.get(output.orientation_set, {})
            if output.dir_key in flip_map:
                flip.append(output)
            else:
                non_flip.append(output)

        for idx, output in enumerate(non_flip):
            if (
                output.dir_key == args.reference_dir
                and not args.include_reference
                and not args.postprocess_only
            ):
                continue
            target = Path(output.filename)
            if not target.is_absolute():
                target = out_dir / target
            raw_target = tmp_path_for(target, out_dir, tmp_dir)
            reference = Path(output.reference_filename)
            if not reference.is_absolute():
                reference = out_dir / reference
            raw_reference = tmp_path_for(reference, out_dir, tmp_dir)
            if raw_reference.exists():
                reference = raw_reference
            if args.dry_run:
                print(f"[dry-run] {target} <- {output.prompt[:80]}... (ref {reference})")
                continue
            if args.postprocess_only:
                source = raw_target if raw_target.exists() else target
                if not source.exists():
                    print(f"[skip] missing {source}")
                    continue
                postprocess_to_target(
                    source,
                    target,
                    args.size,
                    args.postprocess_tol,
                    args.postprocess_purple_to_white,
                    oriented_uses_purple_bg(output) or args.postprocess_purple_bg,
                )
                continue
            if not reference.exists():
                raise SystemExit(f"Missing reference image: {reference}")
            if client is None:
                raise SystemExit("Client not initialized for image generation.")
            prompt = build_oriented_prompt(output.prompt)
            img = generate_oriented_image(
                client, args.model, prompt, args.seed + idx, args.size, reference
            )
            use_purple = oriented_uses_purple_bg(output)
            do_postprocess = args.postprocess or use_purple
            if do_postprocess:
                raw_target.parent.mkdir(parents=True, exist_ok=True)
                img.save(raw_target)
                postprocess_to_target(
                    raw_target,
                    target,
                    args.size,
                    args.postprocess_tol,
                    args.postprocess_purple_to_white,
                    use_purple or args.postprocess_purple_bg,
                )
            else:
                if args.size and img.size != (args.size, args.size):
                    img = img.resize((args.size, args.size), Image.LANCZOS)
                target.parent.mkdir(parents=True, exist_ok=True)
                img.save(target)

        for output in flip:
            target = Path(output.filename)
            if not target.is_absolute():
                target = out_dir / target
            raw_target = tmp_path_for(target, out_dir, tmp_dir)
            flip_map = FLIP_ORIENTATIONS.get(output.orientation_set, {})
            source_dir = flip_map[output.dir_key]
            source_name = swap_orientation_token(output.filename, output.dir_key, source_dir)
            source = Path(source_name)
            if not source.is_absolute():
                source = out_dir / source
            if args.dry_run:
                print(f"[dry-run] {target} <- flip {source}")
                continue
            if args.postprocess_only:
                source = raw_target if raw_target.exists() else target
                if not source.exists():
                    print(f"[skip] missing {source}")
                    continue
                postprocess_to_target(
                    source,
                    target,
                    args.size,
                    args.postprocess_tol,
                    args.postprocess_purple_to_white,
                    oriented_uses_purple_bg(output) or args.postprocess_purple_bg,
                )
                continue
            raw_source = tmp_path_for(source, out_dir, tmp_dir)
            if raw_source.exists():
                source = raw_source
            if not source.exists():
                raise SystemExit(f"Missing flip source image: {source}")
            with Image.open(source) as existing:
                img = existing.convert("RGBA")
            img = flip_horizontal(img)
            use_purple = oriented_uses_purple_bg(output)
            do_postprocess = args.postprocess or use_purple
            if do_postprocess:
                raw_target.parent.mkdir(parents=True, exist_ok=True)
                img.save(raw_target)
                postprocess_to_target(
                    raw_target,
                    target,
                    args.size,
                    args.postprocess_tol,
                    args.postprocess_purple_to_white,
                    use_purple or args.postprocess_purple_bg,
                )
            else:
                if args.size and img.size != (args.size, args.size):
                    img = img.resize((args.size, args.size), Image.LANCZOS)
                target.parent.mkdir(parents=True, exist_ok=True)
                img.save(target)
    else:
        rows = load_prompts(prompt_path)
        for idx, (filename, prompt) in enumerate(iter_rows(rows, only)):
            target = Path(filename)
            if not target.is_absolute():
                target = out_dir / target
            raw_target = tmp_path_for(target, out_dir, tmp_dir)
            if args.dry_run:
                print(f"[dry-run] {target} <- {prompt[:80]}...")
                continue
            if args.postprocess_only:
                source = raw_target if raw_target.exists() else target
                if not source.exists():
                    print(f"[skip] missing {source}")
                    continue
                postprocess_to_target(
                    source,
                    target,
                    args.size,
                    args.postprocess_tol,
                    args.postprocess_purple_to_white,
                    args.postprocess_purple_bg,
                )
                maybe_derive_cliff_variants(target, out_dir)
                continue
            if client is None:
                raise SystemExit("Client not initialized for image generation.")
            img = generate_image(client, args.model, prompt, args.seed + idx, args.size)
            if args.postprocess:
                raw_target.parent.mkdir(parents=True, exist_ok=True)
                img.save(raw_target)
                postprocess_to_target(
                    raw_target,
                    target,
                    args.size,
                    args.postprocess_tol,
                    args.postprocess_purple_to_white,
                    args.postprocess_purple_bg,
                )
                maybe_derive_cliff_variants(target, out_dir)
            else:
                if args.size and img.size != (args.size, args.size):
                    img = img.resize((args.size, args.size), Image.LANCZOS)
                target.parent.mkdir(parents=True, exist_ok=True)
                img.save(target)
                maybe_derive_cliff_variants(target, out_dir)


if __name__ == "__main__":
    main()
