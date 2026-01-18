#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


SPRITES = [
    (
        "Edge N",
        Path("data/cliff_edge_ew_s.png"),
        {(0, -1)},
    ),
    (
        "Edge E",
        Path("data/cliff_edge_ns_w.png"),
        {(1, 0)},
    ),
    (
        "Edge S",
        Path("data/cliff_edge_ew.png"),
        {(0, 1)},
    ),
    (
        "Edge W",
        Path("data/cliff_edge_ns.png"),
        {(-1, 0)},
    ),
    (
        "Corner In NE",
        Path("data/oriented/cliff_corner_in_ne.png"),
        {(0, -1), (1, 0)},
    ),
    (
        "Corner In SE",
        Path("data/oriented/cliff_corner_in_se.png"),
        {(1, 0), (0, 1)},
    ),
    (
        "Corner In SW",
        Path("data/oriented/cliff_corner_in_sw.png"),
        {(0, 1), (-1, 0)},
    ),
    (
        "Corner In NW",
        Path("data/oriented/cliff_corner_in_nw.png"),
        {(-1, 0), (0, -1)},
    ),
    (
        "Corner Out NE",
        Path("data/oriented/cliff_corner_out_ne.png"),
        {(1, -1)},
    ),
    (
        "Corner Out SE",
        Path("data/oriented/cliff_corner_out_se.png"),
        {(1, 1)},
    ),
    (
        "Corner Out SW",
        Path("data/oriented/cliff_corner_out_sw.png"),
        {(-1, 1)},
    ),
    (
        "Corner Out NW",
        Path("data/oriented/cliff_corner_out_nw.png"),
        {(-1, -1)},
    ),
]


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    font_path = Path("data/Inter-Regular.ttf")
    if font_path.exists():
        return ImageFont.truetype(str(font_path), size=size)
    return ImageFont.load_default()


def draw_grid(low_cells: set[tuple[int, int]], cell: int, padding: int) -> Image.Image:
    grid_size = cell * 3
    img = Image.new("RGBA", (grid_size + padding * 2, grid_size + padding * 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    high_color = (210, 230, 200, 255)
    low_color = (120, 145, 110, 255)
    border = (30, 30, 30, 255)
    center_color = (240, 245, 235, 255)

    font = load_font(int(cell * 0.45))

    for row in range(3):
        for col in range(3):
            dx = col - 1
            dy = row - 1
            is_center = dx == 0 and dy == 0
            is_low = (dx, dy) in low_cells
            fill = center_color if is_center else (low_color if is_low else high_color)
            x0 = padding + col * cell
            y0 = padding + row * cell
            x1 = x0 + cell
            y1 = y0 + cell
            draw.rectangle([x0, y0, x1, y1], fill=fill, outline=border, width=1)
            label = "H" if is_center or not is_low else "L"
            bbox = draw.textbbox((0, 0), label, font=font)
            w = bbox[2] - bbox[0]
            h = bbox[3] - bbox[1]
            draw.text(
                (x0 + (cell - w) / 2, y0 + (cell - h) / 2 - 1),
                label,
                fill=(20, 20, 20, 255),
                font=font,
            )
    return img


def render_preview(output_path: Path) -> None:
    label_font = load_font(16)
    small_font = load_font(12)

    cell = 26
    padding = 4
    grid_img = draw_grid(set(), cell, padding)
    grid_w, grid_h = grid_img.size

    sprite_w = sprite_h = 200
    row_height = max(sprite_h, grid_h) + 16
    label_width = 160
    gap = 16
    width = label_width + grid_w + gap + sprite_w + gap
    height = row_height * len(SPRITES) + 20

    canvas = Image.new("RGBA", (width, height), (15, 15, 15, 255))
    draw = ImageDraw.Draw(canvas)

    title = "Cliff Preview (3x3 H/L vs Sprite)"
    draw.text((12, 8), title, fill=(235, 235, 235, 255), font=label_font)

    y = 28
    for label, sprite_path, low_cells in SPRITES:
        row_top = y
        # label
        draw.text((12, row_top + 6), label, fill=(235, 235, 235, 255), font=label_font)
        draw.text(
            (12, row_top + 26),
            sprite_path.as_posix(),
            fill=(150, 150, 150, 255),
            font=small_font,
        )

        # grid
        grid_img = draw_grid(low_cells, cell, padding)
        grid_x = label_width
        grid_y = row_top + (row_height - grid_img.size[1]) // 2
        canvas.paste(grid_img, (grid_x, grid_y), grid_img)

        # sprite
        sprite_x = label_width + grid_w + gap
        sprite_y = row_top + (row_height - sprite_h) // 2
        if sprite_path.exists():
            sprite = Image.open(sprite_path).convert("RGBA")
            if sprite.size != (sprite_w, sprite_h):
                sprite = sprite.resize((sprite_w, sprite_h), Image.NEAREST)
            canvas.paste(sprite, (sprite_x, sprite_y), sprite)
        else:
            draw.rectangle(
                [sprite_x, sprite_y, sprite_x + sprite_w, sprite_y + sprite_h],
                outline=(200, 80, 80, 255),
                width=2,
            )
            draw.text(
                (sprite_x + 8, sprite_y + 8),
                "missing",
                fill=(200, 80, 80, 255),
                font=label_font,
            )

        y += row_height

    output_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output_path)


def main() -> None:
    parser = argparse.ArgumentParser(description="Render cliff sprite preview sheet.")
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("data/tmp/cliff_preview.png"),
        help="Output path for the preview image.",
    )
    args = parser.parse_args()
    render_preview(args.out)


if __name__ == "__main__":
    main()
