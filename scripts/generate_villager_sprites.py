#!/usr/bin/env python
from __future__ import annotations

import argparse
import io
import os
from pathlib import Path

from google import genai
from google.genai import types
from PIL import Image


def build_prompt(view: str) -> str:
    base = (
        "Pixel art, 1:1 sprite, extremely simple Age of Empires II villager. "
        "Single adult male villager, consistent design across all views: "
        "blue tunic, brown belt, tan pants, dark brown boots, light skin, short brown hair. "
        "Thick outlines, limited palette, no fine details, readable at a glance. "
        "Full body, centered, zoomed to fill most of the frame with a little padding. "
        "Transparent background (true alpha), no checkerboard, no white/gray backdrop. "
        "No text, no UI, no extra props, no weapons."
    )
    return f"{base} {view}"


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


def generate_one(
    client: genai.Client,
    model: str,
    prompt: str,
    seed: int,
    out_path: Path,
    target_size: int,
) -> None:
    # Use GenerateContent with image modalities (works for Gemini image generation on Vertex).
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
    if target_size and img.size != (target_size, target_size):
        img = img.resize((target_size, target_size), Image.LANCZOS)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate AoE-style villager sprites.")
    parser.add_argument("--project", default=os.environ.get("GOOGLE_CLOUD_PROJECT"))
    parser.add_argument("--location", default=os.environ.get("GOOGLE_CLOUD_LOCATION", "us-east1"))
    parser.add_argument("--model", default="publishers/google/models/gemini-2.0-flash-preview-image-generation")
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--size", type=int, default=200, help="Output size (square).")
    args = parser.parse_args()

    client = make_client(args.project, args.location)

    out_dir = Path("data")
    views = {
        "agent.s.png": "Front view facing the camera.",
        "agent.n.png": "Back view facing away from the camera.",
        "agent.w.png": "Left-facing profile view.",
        "agent.e.png": "Right-facing profile view.",
    }

    for idx, (filename, view_text) in enumerate(views.items()):
        seed = args.seed + idx
        prompt = build_prompt(view_text)
        generate_one(client, args.model, prompt, seed, out_dir / filename, args.size)


if __name__ == "__main__":
    main()
