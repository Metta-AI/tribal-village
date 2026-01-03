import argparse
import os
from io import BytesIO
from pathlib import Path
from typing import Optional, Sequence, Tuple

from google import genai
from google.genai.types import GenerateContentConfig, Modality

try:
    from PIL import Image
except ImportError:  # Pillow is optional; we can still save raw bytes.
    Image = None

def _ensure_vertex_env(project_id: Optional[str], location: Optional[str]) -> None:
    if project_id:
        os.environ["GOOGLE_CLOUD_PROJECT"] = project_id
    if location:
        os.environ["GOOGLE_CLOUD_LOCATION"] = location
    os.environ.setdefault("GOOGLE_GENAI_USE_VERTEXAI", "True")

def _extract_first_image_bytes(response) -> Optional[bytes]:
    for candidate in getattr(response, "candidates", []) or []:
        content = getattr(candidate, "content", None)
        if not content:
            continue
        for part in getattr(content, "parts", []) or []:
            inline_data = getattr(part, "inline_data", None)
            if inline_data and getattr(inline_data, "data", None):
                return inline_data.data
    return None

def _has_transparency(image) -> bool:
    if image.mode in ("RGBA", "LA"):
        return image.getchannel("A").getextrema()[0] < 255
    return image.info.get("transparency") is not None

def _key_out_background(image, threshold: int):
    rgba = image.convert("RGBA")
    w, h = rgba.size
    samples = [
        rgba.getpixel((0, 0)),
        rgba.getpixel((w - 1, 0)),
        rgba.getpixel((0, h - 1)),
        rgba.getpixel((w - 1, h - 1)),
        rgba.getpixel((w // 2, 0)),
        rgba.getpixel((w // 2, h - 1)),
    ]
    bg_r = round(sum(p[0] for p in samples) / len(samples))
    bg_g = round(sum(p[1] for p in samples) / len(samples))
    bg_b = round(sum(p[2] for p in samples) / len(samples))
    new_pixels = []
    for r, g, b, a in rgba.getdata():
        if (
            abs(r - bg_r) <= threshold
            and abs(g - bg_g) <= threshold
            and abs(b - bg_b) <= threshold
        ):
            new_pixels.append((r, g, b, 0))
        else:
            new_pixels.append((r, g, b, a))
    rgba.putdata(new_pixels)
    return rgba

def generate_image(
    prompt: str,
    output_file: str,
    model: str,
    project_id: Optional[str],
    location: Optional[str],
    tile_size: Optional[int],
    key_out_background: bool,
    key_out_threshold: int,
) -> None:
    """Generates an image using Gemini on Vertex AI."""
    _ensure_vertex_env(project_id, location)
    client = genai.Client()

    response = client.models.generate_content(
        model=model,
        contents=[prompt],
        config=GenerateContentConfig(response_modalities=[Modality.IMAGE]),
    )

    image_bytes = _extract_first_image_bytes(response)
    if not image_bytes:
        raise RuntimeError("No image bytes returned by the model.")

    os.makedirs(os.path.dirname(output_file) or ".", exist_ok=True)

    if Image is None:
        with open(output_file, "wb") as output:
            output.write(image_bytes)
        print("Saved image bytes (install Pillow for resizing/transparency).")
        return

    image = Image.open(BytesIO(image_bytes))
    if key_out_background and not _has_transparency(image):
        image = _key_out_background(image, key_out_threshold)

    if tile_size:
        image = image.resize((tile_size, tile_size), resample=Image.NEAREST)

    image.save(output_file)
    print(f"Image generated and saved to {output_file}")

def _load_batch_prompts(path: str) -> Sequence[Tuple[str, str]]:
    lines = Path(path).read_text().splitlines()
    entries = []
    for idx, line in enumerate(lines, start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if "\t" not in line:
            raise ValueError(f"{path}:{idx}: expected tab-separated 'filename\\tprompt'")
        name, prompt = line.split("\t", 1)
        name = name.strip()
        prompt = prompt.strip()
        if not name or not prompt:
            raise ValueError(f"{path}:{idx}: empty filename or prompt")
        entries.append((name, prompt))
    return entries

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-id", type=str, help="Your GCP project ID.")
    parser.add_argument("--location", type=str, help="The GCP location to use.")
    parser.add_argument(
        "--model",
        type=str,
        default="gemini-2.5-flash-image",
        help="Gemini image model ID.",
    )
    parser.add_argument(
        "--prompt",
        type=str,
        default="a simple pixel-art house icon with a transparent background",
        help="The prompt for image generation.",
    )
    parser.add_argument(
        "--output-file",
        type=str,
        default="generated_image.png",
        help="The output file name.",
    )
    parser.add_argument(
        "--batch-prompts",
        type=str,
        default=None,
        help="Path to a TSV file of filename<TAB>prompt for batch generation.",
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        default=None,
        help="Output directory for batch generation (defaults to prompt file directory).",
    )
    parser.add_argument(
        "--skip-existing",
        action="store_true",
        help="Skip outputs that already exist when batch generating.",
    )
    parser.add_argument(
        "--tile-size",
        type=int,
        default=None,
        help="If set, resize the output to this square size using nearest-neighbor.",
    )
    parser.add_argument(
        "--key-out-background",
        action="store_true",
        help="If the image has no alpha, key out the dominant border color.",
    )
    parser.add_argument(
        "--key-out-threshold",
        type=int,
        default=10,
        help="Tolerance for background keying (0-255).",
    )
    args = parser.parse_args()

    if args.batch_prompts:
        output_dir = args.output_dir
        if not output_dir:
            output_dir = os.path.dirname(args.batch_prompts) or "."
        os.makedirs(output_dir, exist_ok=True)
        failures = []
        for filename, prompt in _load_batch_prompts(args.batch_prompts):
            out_path = os.path.join(output_dir, filename)
            if args.skip_existing and os.path.exists(out_path):
                continue
            try:
                generate_image(
                    prompt=prompt,
                    output_file=out_path,
                    model=args.model,
                    project_id=args.project_id,
                    location=args.location,
                    tile_size=args.tile_size,
                    key_out_background=args.key_out_background,
                    key_out_threshold=args.key_out_threshold,
                )
            except Exception as exc:
                failures.append((filename, str(exc)))
        if failures:
            print("Batch complete with errors:")
            for filename, err in failures:
                print(f"- {filename}: {err}")
            raise SystemExit(1)
    else:
        generate_image(
            prompt=args.prompt,
            output_file=args.output_file,
            model=args.model,
            project_id=args.project_id,
            location=args.location,
            tile_size=args.tile_size,
            key_out_background=args.key_out_background,
            key_out_threshold=args.key_out_threshold,
        )
