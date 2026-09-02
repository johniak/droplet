#!/usr/bin/env python3
"""Generate the Droplet launcher icon (deterministic, no design tool needed).

A single droplet — circle plus a triangular tip — filled with a vertical
gradient in the app accent, on the app's dark background. Run:

    python3 scripts/make_icon.py
"""

import math
import pathlib

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
BG = (14, 17, 22, 255)  # #0E1116
ACCENT_TOP = (109, 205, 255)  # lighter tip
ACCENT_BOTTOM = (26, 118, 168)  # deeper base


def _droplet_mask() -> Image.Image:
    """White where the droplet is, black elsewhere."""
    mask = Image.new("L", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(mask)
    cx = SIZE // 2
    radius = int(SIZE * 0.26)
    circle_cy = int(SIZE * 0.60)
    tip_y = int(SIZE * 0.20)
    draw.ellipse(
        [cx - radius, circle_cy - radius, cx + radius, circle_cy + radius],
        fill=255,
    )
    # Tangent points from the tip to the circle, so the shoulders flow into
    # the body instead of showing a kink.
    d = circle_cy - tip_y
    a = radius**2 / d
    h = radius * math.sqrt(1 - (radius / d) ** 2)
    draw.polygon(
        [
            (cx, tip_y),
            (cx - h, circle_cy - a),
            (cx + h, circle_cy - a),
        ],
        fill=255,
    )
    return mask


def _gradient() -> Image.Image:
    grad = Image.new("RGB", (1, SIZE))
    for y in range(SIZE):
        t = y / (SIZE - 1)
        grad.putpixel(
            (0, y),
            tuple(
                round(a + (b - a) * t)
                for a, b in zip(ACCENT_TOP, ACCENT_BOTTOM)
            ),
        )
    return grad.resize((SIZE, SIZE))


def build() -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), BG)
    droplet = _gradient().convert("RGBA")
    img.paste(droplet, (0, 0), _droplet_mask())

    # A soft highlight, blurred and blended so it reads as light, not as a hole.
    highlight = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    hdraw = ImageDraw.Draw(highlight)
    cx, cy, r = int(SIZE * 0.42), int(SIZE * 0.52), int(SIZE * 0.09)
    hdraw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255, 70))
    highlight = highlight.filter(ImageFilter.GaussianBlur(SIZE * 0.05))
    highlight.putalpha(
        Image.composite(
            highlight.getchannel("A"),
            Image.new("L", (SIZE, SIZE), 0),
            _droplet_mask(),
        )
    )
    return Image.alpha_composite(img, highlight)


if __name__ == "__main__":
    out = pathlib.Path(__file__).resolve().parent.parent / "app/assets/icon/icon.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    build().save(out, format="PNG")
    print(f"zapisano {out}")
