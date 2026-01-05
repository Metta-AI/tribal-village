#!/usr/bin/env python
from __future__ import annotations

import argparse
import io
import os
from collections import deque
from pathlib import Path
from typing import Iterable

from google import genai
from google.genai import types
from PIL import Image


def load_prompts(path: Path) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t", 1)
        if len(parts) != 2:
            raise ValueError(f"Invalid prompt line (expected TSV): {raw}")
        rows.append((parts[0].strip(), parts[1].strip()))
    return rows


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


def generate_image(
    client: genai.Client,
    model: str,
    prompt: str,
    seed: int,
    size: int,
) -> Image.Image:
    config = types.GenerateContentConfig(
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
    response = client.models.generate_content(model=model, contents=prompt, config=config)
    image_bytes = extract_inline_image(response)
    img = Image.open(io.BytesIO(image_bytes)).convert("RGBA")
    if size and img.size != (size, size):
        img = img.resize((size, size), Image.LANCZOS)
    return img


def flood_fill_bg(img: Image.Image, tol: int = 18) -> Image.Image:
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    corner_colors = [px[x, y][:3] for x, y in corners]

    def color_close(c, ref) -> bool:
        return all(abs(int(c[i]) - int(ref[i])) <= tol for i in range(3))

    visited = [[False] * h for _ in range(w)]
    q: deque[tuple[int, int]] = deque()
    for x, y in corners:
        q.append((x, y))
        visited[x][y] = True

    while q:
        x, y = q.popleft()
        r, g, b, a = px[x, y]
        if any(color_close((r, g, b), ref) for ref in corner_colors):
            px[x, y] = (r, g, b, 0)
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < w and 0 <= ny < h and not visited[nx][ny]:
                    visited[nx][ny] = True
                    q.append((nx, ny))
    return img


def crop_to_content(img: Image.Image, target_size: int) -> Image.Image:
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    w, h = img.size
    pixels = img.getdata()
    xs: list[int] = []
    ys: list[int] = []
    for i, p in enumerate(pixels):
        if p[3] > 0:
            y = i // w
            x = i - y * w
            xs.append(x)
            ys.append(y)
    if not xs:
        return img
    minx, maxx = min(xs), max(xs)
    miny, maxy = min(ys), max(ys)
    box_w = maxx - minx + 1
    box_h = maxy - miny + 1
    side = max(box_w, box_h)
    cx = (minx + maxx) // 2
    cy = (miny + maxy) // 2
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


def iter_rows(
    rows: Iterable[tuple[str, str]],
    only: set[str] | None,
) -> Iterable[tuple[str, str]]:
    for filename, prompt in rows:
        if only:
            if filename not in only and Path(filename).name not in only:
                continue
        yield filename, prompt


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate image assets from TSV prompts.")
    parser.add_argument("--prompts", default="data/nbi/image_prompts.txt")
    parser.add_argument("--out-dir", default="data")
    parser.add_argument(
        "--model",
        default="publishers/google/models/gemini-2.0-flash-preview-image-generation",
    )
    parser.add_argument("--project", default=os.environ.get("GOOGLE_CLOUD_PROJECT"))
    parser.add_argument("--location", default=os.environ.get("GOOGLE_CLOUD_LOCATION", "global"))
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--size", type=int, default=200, help="Output square size.")
    parser.add_argument("--postprocess", action="store_true")
    parser.add_argument("--only", default="", help="Comma-separated filenames to generate.")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    prompt_path = Path(args.prompts)
    rows = load_prompts(prompt_path)
    only = {p.strip() for p in args.only.split(",") if p.strip()} or None

    client = make_client(args.project, args.location)
    out_dir = Path(args.out_dir)

    for idx, (filename, prompt) in enumerate(iter_rows(rows, only)):
        target = Path(filename)
        if not target.is_absolute():
            target = out_dir / target
        if args.dry_run:
            print(f"[dry-run] {target} <- {prompt[:80]}...")
            continue
        img = generate_image(client, args.model, prompt, args.seed + idx, args.size)
        if args.postprocess:
            img = flood_fill_bg(img)
            img = crop_to_content(img, args.size)
        target.parent.mkdir(parents=True, exist_ok=True)
        img.save(target)


if __name__ == "__main__":
    main()
