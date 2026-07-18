from __future__ import annotations

import os
from pathlib import Path

import fal_client
import httpx

from src.config import FLUX_IMAGE_HEIGHT, FLUX_IMAGE_WIDTH, FLUX_MODEL
from src.retry import call_with_retries


def generate_image(
    prompt: str,
    output_path: Path,
    api_key: str | None = None,
) -> Path:
    key = api_key or os.environ.get("FAL_KEY")
    if not key:
        raise ValueError("FAL_KEY is not set")

    os.environ["FAL_KEY"] = key

    result = call_with_retries(
        lambda: fal_client.subscribe(
            FLUX_MODEL,
            arguments={
                "prompt": prompt,
                "image_size": {
                    "width": FLUX_IMAGE_WIDTH,
                    "height": FLUX_IMAGE_HEIGHT,
                },
                "num_inference_steps": 4,
                "num_images": 1,
            },
        ),
        description="FLUX image generation",
    )

    images = result.get("images", [])
    if not images:
        raise RuntimeError("FLUX returned no images")

    image_url = images[0].get("url")
    if not image_url:
        raise RuntimeError("FLUX image response missing URL")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with httpx.Client(timeout=60.0) as client:
        response = client.get(image_url)
        response.raise_for_status()
        output_path.write_bytes(response.content)

    return output_path
