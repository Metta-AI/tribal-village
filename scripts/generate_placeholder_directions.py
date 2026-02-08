#!/usr/bin/env python3
"""Generate placeholder direction sprites from the .s (south) sprite.

Uses simple image transformations to create approximate direction sprites.
These are placeholders - proper AI-generated sprites should replace them.
"""
from pathlib import Path
from PIL import Image

# Units that need direction sprites
CASTLE_UNIQUE_UNITS = [
    "cataphract",
    "huskarl",
    "janissary",
    "longbowman",
    "mameluke",
    "samurai",
    "teutonic_knight",
    "woad_raider",
]

# All 8 directions
DIRECTIONS = ["n", "s", "e", "w", "ne", "nw", "se", "sw"]

# Transformation mappings: what to do to create each direction from south
# For a top-down isometric view:
# - s = original (facing camera)
# - n = same as s (back view would need AI generation)
# - w = flip horizontal (facing left)
# - e = original (facing right, same as w but mirrored)
# - sw = same as s or slight modification
# - se = flip of sw
# - nw = same as n or slight modification
# - ne = flip of nw


def generate_placeholder(src_path: Path, dst_path: Path, direction: str) -> bool:
    """Generate a placeholder sprite for the given direction."""
    if dst_path.exists():
        return False  # Already exists

    with Image.open(src_path) as img:
        img = img.convert("RGBA")

        if direction == "n":
            # North: same as south (placeholder - ideally would be back view)
            result = img.copy()
        elif direction == "e":
            # East: keep as-is (right-facing)
            result = img.copy()
        elif direction == "w":
            # West: flip horizontal (left-facing)
            result = img.transpose(Image.FLIP_LEFT_RIGHT)
        elif direction == "ne":
            # Northeast: keep as-is (slight right)
            result = img.copy()
        elif direction == "nw":
            # Northwest: flip horizontal
            result = img.transpose(Image.FLIP_LEFT_RIGHT)
        elif direction == "se":
            # Southeast: keep as-is
            result = img.copy()
        elif direction == "sw":
            # Southwest: flip horizontal
            result = img.transpose(Image.FLIP_LEFT_RIGHT)
        else:
            return False

        result.save(dst_path)
        return True


def main():
    data_dir = Path(__file__).parent.parent / "data" / "oriented"

    generated = 0
    skipped = 0

    for unit in CASTLE_UNIQUE_UNITS:
        src = data_dir / f"{unit}.s.png"
        if not src.exists():
            print(f"Warning: {unit}.s.png not found, skipping")
            continue

        for direction in DIRECTIONS:
            if direction == "s":
                continue  # Skip south, it's the source

            dst = data_dir / f"{unit}.{direction}.png"
            if generate_placeholder(src, dst, direction):
                print(f"Generated: {unit}.{direction}.png")
                generated += 1
            else:
                skipped += 1

    print(f"\nGenerated {generated} placeholder sprites, skipped {skipped} existing")


if __name__ == "__main__":
    main()
