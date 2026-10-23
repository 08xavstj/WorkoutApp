"""Draws the Tensile app icon (light, dark and tinted, 1024 px) and logo previews.

The mark is a "T" made from a loaded barbell: the bar flexes under load (the
"whip" of a heavy lift, i.e. tensile strength), with a plate at each end and
the stem of the T rising from the middle of the bar. On the light icon it is
white on the app's strain-to-sleep gradient (butter, orange, pink, violet).

The same geometry is drawn in SwiftUI by `TensileMark` (App/Design/AppLogo.swift).
Keep the numbers in `GEOMETRY` in sync with it.

Run: python3 docs/brand/make_logo.py
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SIZE = 1024
SS = 4  # supersampling
W = SIZE * SS

# Unit-square geometry, shared with TensileMark in Swift.
GEOMETRY = {
    "bar_start": (0.14, 0.40),
    "bar_control": (0.50, 0.25),
    "bar_end": (0.86, 0.40),
    "bar_width": 0.07,
    # Plates along the bar: (t on the curve, width, height). Mirrored on the right.
    "plates": [(0.075, 0.085, 0.30), (0.145, 0.06, 0.21)],
    "plate_corner": 0.035,
    "stem_top": 0.30,
    "stem_bottom": 0.82,
    "stem_width": 0.13,
}

# The mark sits inside the icon's safe area (iOS rounds the corners).
ICON_SCALE = 0.80
ICON_OFFSET = (0.5 - 0.5 * ICON_SCALE, 0.5 - 0.52 * ICON_SCALE)

GRADIENT = ["#FFC94A", "#FF7A1A", "#F0447A", "#5B5BF0"]  # strainLight, strain, lifting, sleep


def hex_rgb(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def ramp(stops, t):
    t = min(max(t, 0), 1)
    scaled = t * (len(stops) - 1)
    i = min(int(scaled), len(stops) - 2)
    return lerp(stops[i], stops[i + 1], scaled - i)


def diagonal_gradient(stops):
    """Top-left to bottom-right gradient."""
    small = 256
    img = Image.new("RGB", (small, small))
    px = img.load()
    rgb = [hex_rgb(s) for s in stops]
    for y in range(small):
        for x in range(small):
            px[x, y] = ramp(rgb, (x + y) / (2 * (small - 1)))
    return img.resize((W, W), Image.BICUBIC).convert("RGBA")


def quad(p0, p1, p2, t):
    return tuple((1 - t) ** 2 * p0[i] + 2 * (1 - t) * t * p1[i] + t ** 2 * p2[i] for i in range(2))


def mark_mask(scale=ICON_SCALE, offset=ICON_OFFSET):
    """White-on-black mask of the mark, in a W x W canvas."""
    g = GEOMETRY
    mask = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(mask)

    def P(pt):
        return ((offset[0] + pt[0] * scale) * W, (offset[1] + pt[1] * scale) * W)

    # Stem.
    sw = g["stem_width"] * scale * W
    x = P((0.5, 0))[0]
    top, bottom = P((0, g["stem_top"]))[1], P((0, g["stem_bottom"]))[1]
    d.rounded_rectangle([x - sw / 2, top, x + sw / 2, bottom], radius=sw / 2, fill=255)

    # Flexed bar: discs along a quadratic curve.
    r = g["bar_width"] * scale * W / 2
    p0, p1, p2 = g["bar_start"], g["bar_control"], g["bar_end"]
    for k in range(801):
        cx, cy = P(quad(p0, p1, p2, k / 800))
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)

    # Plates, square to the bar.
    corner = g["plate_corner"] * scale * W
    for t0, pw_u, ph_u in g["plates"]:
        for t in (t0, 1 - t0):
            pw, ph = pw_u * scale * W, ph_u * scale * W
            a_pt, b_pt = quad(p0, p1, p2, t - 0.01), quad(p0, p1, p2, t + 0.01)
            angle = math.degrees(math.atan2(b_pt[1] - a_pt[1], b_pt[0] - a_pt[0]))
            size = int(max(pw, ph) * 1.6)
            plate = Image.new("L", (size, size), 0)
            pd = ImageDraw.Draw(plate)
            c = size / 2
            pd.rounded_rectangle([c - pw / 2, c - ph / 2, c + pw / 2, c + ph / 2], radius=corner, fill=255)
            plate = plate.rotate(-angle, resample=Image.BICUBIC)
            ex, ey = P(quad(p0, p1, p2, t))
            mask.paste(255, (int(ex - size / 2), int(ey - size / 2)), plate)
    return mask


def finish(img, path):
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    img.convert("RGB").save(path)
    print("wrote", os.path.relpath(path, ROOT))


def light_icon():
    bg = diagonal_gradient(GRADIENT)
    # A soft highlight top-left, like the pastel washes in the app.
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([-0.25 * W, -0.35 * W, 0.65 * W, 0.45 * W], fill=(255, 255, 255, 90))
    bg.alpha_composite(glow.filter(ImageFilter.GaussianBlur(W * 0.08)))
    mask = mark_mask()
    shadow = Image.new("RGBA", (W, W), (60, 20, 80, 0))
    shadow.putalpha(mask.filter(ImageFilter.GaussianBlur(W * 0.018)).point(lambda v: v * 0.35))
    bg.alpha_composite(shadow, (0, int(W * 0.012)))
    white = Image.new("RGBA", (W, W), (255, 255, 255, 255))
    bg.paste(white, (0, 0), mask)
    return bg


def dark_icon():
    bg = Image.new("RGBA", (W, W), hex_rgb("#0B0B0F") + (255,))
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([0.15 * W, 0.15 * W, 0.85 * W, 0.85 * W], fill=hex_rgb("#F0447A") + (60,))
    bg.alpha_composite(glow.filter(ImageFilter.GaussianBlur(W * 0.12)))
    bg.paste(diagonal_gradient(GRADIENT), (0, 0), mark_mask())
    return bg


def tinted_icon():
    # iOS tints a grayscale image; keep the mark bright on black.
    bg = Image.new("RGBA", (W, W), (0, 0, 0, 255))
    shade = diagonal_gradient(["#FFFFFF", "#BDBDBD"])
    bg.paste(shade, (0, 0), mark_mask())
    return bg


def wordmark_preview():
    """Mark plus "Tensile" on white, for docs."""
    width, height = 1800 * 2, 600 * 2
    img = Image.new("RGBA", (width, height), (255, 255, 255, 255))
    icon = light_icon().resize((height - 200, height - 200), Image.LANCZOS)
    rounded = Image.new("L", icon.size, 0)
    ImageDraw.Draw(rounded).rounded_rectangle([0, 0, icon.width, icon.height], radius=int(icon.width * 0.225), fill=255)
    img.paste(icon, (100, 100), rounded)
    font = None
    for name in ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/System/Library/Fonts/SFNSRounded.ttf"]:
        if os.path.exists(name):
            font = ImageFont.truetype(name, 420)
            break
    font = font or ImageFont.load_default()
    text = Image.new("L", (width, height), 0)
    ImageDraw.Draw(text).text((height + 40, height / 2), "Tensile", font=font, fill=255, anchor="lm")
    grad = Image.new("RGBA", (width, height))
    gp = grad.load()
    rgb = [hex_rgb(s) for s in GRADIENT[1:]]
    for x in range(width):
        c = ramp(rgb, (x - height) / (width - height)) + (255,)
        for y in range(0, height):
            gp[x, y] = c
    img.paste(grad, (0, 0), text)
    img = img.resize((width // 2, height // 2), Image.LANCZOS)
    path = os.path.join(ROOT, "docs/brand/logo.png")
    img.convert("RGB").save(path)
    print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    out = os.path.join(ROOT, "App/Assets.xcassets/AppIcon.appiconset")
    finish(light_icon(), os.path.join(out, "AppIcon.png"))
    finish(dark_icon(), os.path.join(out, "AppIcon-Dark.png"))
    finish(tinted_icon(), os.path.join(out, "AppIcon-Tinted.png"))
    finish(light_icon(), os.path.join(ROOT, "docs/brand/app-icon.png"))
    wordmark_preview()
