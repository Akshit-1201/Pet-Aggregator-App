"""Regenerates the Pawgo launcher-icon source art in assets/icon/.

The mark is the prototype's paw glyph (design/Pawgo Prototype.dc.html, the 24x24
`<svg>` used on the splash tile) on the brand's diagonal orange gradient. Run
this only when the mark or the brand colours change:

    python tool/generate_app_icon.py
    dart run flutter_launcher_icons        # rebuilds android/.../mipmap-*

Requires Pillow + numpy (host tooling only; not a Flutter dependency).
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

SIZE = 1024          # source art is 1024x1024, flutter_launcher_icons downsizes
SS = 4               # supersample factor for the antialiased shape masks
OUT = Path(__file__).resolve().parent.parent / "assets" / "icon"

# Splash gradient, top-left -> bottom-right (lib/features/onboarding/splash_screen.dart).
GRADIENT = [(0xF8, 0xB4, 0x5E), (0xF0, 0x87, 0x1E), (0xE0, 0x77, 0x12)]

# Legacy icon: full-bleed tile with the splash's 31.7% corner radius (104px tile,
# 33px radius). Adaptive layers are masked by the launcher, so they stay square.
LEGACY_RADIUS = 0.317
LEGACY_PAW = 0.50    # paw width as a fraction of the tile

# Two corrections put the paw at the same visual size on the adaptive icon as on
# the legacy tile: the launcher only shows the inner 72/108 of an adaptive layer,
# and flutter_launcher_icons wraps the foreground in a 16%-per-side <inset> (so
# the art keeps 1 - 2*0.16 of the layer). They very nearly cancel.
ADAPTIVE_PAW = LEGACY_PAW * (72 / 108) / (1 - 2 * 0.16)


# --- the paw, in the prototype's 24x24 viewBox ------------------------------

# "M12 13.2c-2.4 0-4.5 1.7-4.5 3.9 0 1.3 1 2.1 2.3 2.1 .9 0 1.5-.4 2.2-.4
#  s1.3 .4 2.2 .4 c1.3 0 2.3-.8 2.3-2.1 0-2.2-2.1-3.9-4.5-3.9Z"
# resolved to absolute cubics (the `s` reflection is already applied).
PAD_CURVES = [
    ((12.0, 13.2), (9.6, 13.2), (7.5, 14.9), (7.5, 17.1)),
    ((7.5, 17.1), (7.5, 18.4), (8.5, 19.2), (9.8, 19.2)),
    ((9.8, 19.2), (10.7, 19.2), (11.3, 18.8), (12.0, 18.8)),
    ((12.0, 18.8), (12.7, 18.8), (13.3, 19.2), (14.2, 19.2)),
    ((14.2, 19.2), (15.5, 19.2), (16.5, 18.4), (16.5, 17.1)),
    ((16.5, 17.1), (16.5, 14.9), (14.4, 13.2), (12.0, 13.2)),
]

# <ellipse> toes: (cx, cy, rx, ry)
TOES = [(6.6, 10.8, 1.7, 2.1), (17.4, 10.8, 1.7, 2.1),
        (9.4, 7.2, 1.5, 1.9), (14.6, 7.2, 1.5, 1.9)]


def _cubic(p0, c1, c2, p3, steps=64):
    """Flattens one cubic bezier to a point list (endpoint excluded)."""
    pts = []
    for i in range(steps):
        t = i / steps
        u = 1 - t
        pts.append((
            u * u * u * p0[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t * t * t * p3[0],
            u * u * u * p0[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t * t * t * p3[1],
        ))
    return pts


def paw_polygons():
    """The paw as a list of polygons in viewBox units."""
    pad = []
    for curve in PAD_CURVES:
        pad.extend(_cubic(*curve))
    polys = [pad]
    for cx, cy, rx, ry in TOES:
        polys.append([
            (cx + rx * np.cos(a), cy + ry * np.sin(a))
            for a in np.linspace(0, 2 * np.pi, 96, endpoint=False)
        ])
    return polys


def paw_mask(size, width_fraction):
    """An 8-bit alpha mask of the paw, centred, scaled to `width_fraction`."""
    polys = paw_polygons()
    xs = [p[0] for poly in polys for p in poly]
    ys = [p[1] for poly in polys for p in poly]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)

    scale = size * SS * width_fraction / max(x1 - x0, y1 - y0)
    dx = size * SS / 2 - (x0 + x1) / 2 * scale
    dy = size * SS / 2 - (y0 + y1) / 2 * scale

    mask = Image.new("L", (size * SS, size * SS), 0)
    draw = ImageDraw.Draw(mask)
    for poly in polys:
        draw.polygon([(p[0] * scale + dx, p[1] * scale + dy) for p in poly], fill=255)
    return mask.resize((size, size), Image.LANCZOS)


# --- the gradient tile ------------------------------------------------------

def gradient(size):
    """Three-stop linear gradient running top-left to bottom-right."""
    stops = np.array(GRADIENT, dtype=float)
    # t is constant along each anti-diagonal, so build it from x + y.
    yy, xx = np.mgrid[0:size, 0:size]
    t = (xx + yy) / (2 * (size - 1))
    # piecewise-linear interpolation across the three stops
    pos = t * (len(stops) - 1)
    lo = np.clip(np.floor(pos).astype(int), 0, len(stops) - 2)
    frac = (pos - lo)[..., None]
    rgb = stops[lo] * (1 - frac) + stops[lo + 1] * frac
    return Image.fromarray(rgb.round().astype(np.uint8), "RGB")


def rounded_mask(size, radius_fraction):
    mask = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size * SS - 1, size * SS - 1),
        radius=size * SS * radius_fraction, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def white_on(base_rgba, paw_width):
    """Composites the white paw over an RGBA base."""
    out = base_rgba.copy()
    white = Image.new("RGBA", out.size, (255, 255, 255, 255))
    out.paste(white, (0, 0), paw_mask(out.size[0], paw_width))
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)

    grad = gradient(SIZE)

    # Legacy / Play Store icon: rounded gradient tile + paw.
    tile = grad.convert("RGBA")
    tile.putalpha(rounded_mask(SIZE, LEGACY_RADIUS))
    white_on(tile, LEGACY_PAW).save(OUT / "pawgo_icon.png")

    # Adaptive background: full-bleed gradient, the launcher supplies the mask.
    grad.convert("RGBA").save(OUT / "pawgo_icon_background.png")

    # Adaptive foreground + Android 13 monochrome: paw alone, inside the safe zone.
    paw_only = white_on(Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0)), ADAPTIVE_PAW)
    paw_only.save(OUT / "pawgo_icon_foreground.png")
    paw_only.save(OUT / "pawgo_icon_monochrome.png")

    for f in sorted(OUT.glob("*.png")):
        print(f"{f.name:32} {f.stat().st_size / 1024:6.1f} KB")


if __name__ == "__main__":
    main()
