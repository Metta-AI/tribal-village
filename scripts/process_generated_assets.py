import argparse
import os
from collections import deque
from pathlib import Path
from typing import Iterable, Tuple

try:
    from PIL import Image
except ImportError as exc:  # pragma: no cover
    raise SystemExit("Pillow is required: pip install pillow") from exc


def is_tile(name: str) -> bool:
    return name.endswith("_tile.png")


def _color_match(c, target, tol: int) -> bool:
    return (
        abs(c[0] - target[0]) <= tol
        and abs(c[1] - target[1]) <= tol
        and abs(c[2] - target[2]) <= tol
    )


def flood_fill_from_corners(img: Image.Image, tol: int) -> Image.Image:
    rgba = img.convert("RGBA")
    w, h = rgba.size
    if w == 0 or h == 0:
        return rgba

    pixels = rgba.load()
    corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    corner_colors = [pixels[x, y][:3] for x, y in corners]

    for color in corner_colors:
        visited = bytearray(w * h)
        q = deque()
        for x, y in corners:
            if _color_match(pixels[x, y][:3], color, tol):
                q.append((x, y))

        while q:
            x, y = q.popleft()
            idx = y * w + x
            if visited[idx]:
                continue
            visited[idx] = 1
            r, g, b, a = pixels[x, y]
            if not _color_match((r, g, b), color, tol):
                continue
            if a != 0:
                pixels[x, y] = (r, g, b, 0)
            if x > 0:
                q.append((x - 1, y))
            if x + 1 < w:
                q.append((x + 1, y))
            if y > 0:
                q.append((x, y - 1))
            if y + 1 < h:
                q.append((x, y + 1))

    return rgba


def downsize_if_needed(img: Image.Image, max_size: int) -> Image.Image:
    w, h = img.size
    max_dim = max(w, h)
    if max_dim <= max_size:
        return img
    scale = max_size / max_dim
    new_w = max(1, int(round(w * scale)))
    new_h = max(1, int(round(h * scale)))
    return img.resize((new_w, new_h), resample=Image.NEAREST)


def crop_to_content(img: Image.Image) -> Image.Image:
    rgba = img.convert("RGBA")
    alpha = rgba.getchannel("A")
    bbox = alpha.getbbox()
    if not bbox:
        return rgba
    if bbox == (0, 0, rgba.size[0], rgba.size[1]):
        return rgba
    return rgba.crop(bbox)


def process_directory(path: Path, tol: int, max_size: int) -> None:
    for file in sorted(path.glob("*.png")):
        name = file.name
        img = Image.open(file)
        img.load()
        if not is_tile(name):
            img = flood_fill_from_corners(img, tol)
        img = downsize_if_needed(img, max_size)
        if not is_tile(name):
            img = crop_to_content(img)
        img.save(file)


def main(dirs: Iterable[str], tol: int, max_size: int) -> None:
    for d in dirs:
        path = Path(d)
        if not path.exists():
            raise SystemExit(f"Directory not found: {d}")
        process_directory(path, tol, max_size)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("dirs", nargs="+", help="Directories of PNGs to process")
    parser.add_argument("--tol", type=int, default=10, help="Color tolerance for flood fill")
    parser.add_argument("--max-size", type=int, default=256, help="Max dimension for downsize")
    args = parser.parse_args()
    main(args.dirs, args.tol, args.max_size)
