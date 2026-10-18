"""Draws the app icon (1024 px) and a preview of the logo mark.

The mark: a ring split into three gradient arcs, one per score (strain
orange, recovery green, sleep blue), around a white disk with a heartbeat
line. The same mark is drawn in SwiftUI by `AppLogoMark` (App/Design/AppLogo.swift).

Run: python3 docs/brand/make_logo.py
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SIZE = 1024
SS = 4  # supersampling
W = SIZE * SS


def hex_rgb(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def ramp(stops, t):
    """Color at t (0...1) along evenly spaced color stops."""
    if t <= 0:
        return stops[0]
    if t >= 1:
        return stops[-1]
    scaled = t * (len(stops) - 1)
    i = int(scaled)
    return lerp(stops[i], stops[i + 1], scaled - i)


def background():
    img = Image.new("RGB", (W, W), hex_rgb("#FFFFFF"))
    px = ImageDraw.Draw(img)
    top, bottom = hex_rgb("#FFFBF5"), hex_rgb("#F3F1FF")
    for y in range(0, W, SS):
        px.rectangle([0, y, W, y + SS], fill=lerp(top, bottom, y / W))
    # Soft pastel blobs, like the tab headers.
    blobs = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    bd = ImageDraw.Draw(blobs)
    for (cx, cy, r, color, alpha) in [
        (0.12, 0.10, 0.55, "#FFD3B0", 200),
        (0.95, 0.20, 0.45, "#FFF0A6", 170),
        (0.10, 0.95, 0.50, "#D9F5A6", 150),
        (0.92, 0.92, 0.55, "#B9DEFF", 200),
    ]:
        x, y, rr = cx * W, cy * W, r * W
        bd.ellipse([x - rr, y - rr, x + rr, y + rr], fill=hex_rgb(color) + (alpha,))
    blobs = blobs.filter(ImageFilter.GaussianBlur(W * 0.12))
    img = img.convert("RGBA")
    img.alpha_composite(blobs)
    return img


def arc_layer(center, radius, width, arcs):
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    r = width / 2
    for start, end, stops in arcs:
        steps = int(abs(end - start) * 8)
        for k in range(steps + 1):
            t = k / steps
            angle = math.radians(start + (end - start) * t)
            x = center[0] + radius * math.cos(angle)
            y = center[1] + radius * math.sin(angle)
            color = ramp(stops, t)
            d.ellipse([x - r, y - r, x + r, y + r], fill=color + (255,))
    return layer


def pulse_mask(center, scale, width):
    mask = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(mask)
    # A heartbeat: flat, small bump, tall spike, dip, flat.
    shape = [(-1.0, 0.0), (-0.48, 0.0), (-0.34, -0.22), (-0.2, 0.0), (-0.08, 0.0),
             (0.06, -0.78), (0.22, 0.62), (0.36, 0.0), (1.0, 0.0)]
    points = [(center[0] + x * scale, center[1] + y * scale) for x, y in shape]
    d.line(points, fill=255, width=int(width), joint="curve")
    for p in (points[0], points[-1]):
        d.ellipse([p[0] - width / 2, p[1] - width / 2, p[0] + width / 2, p[1] + width / 2], fill=255)
    return mask


def gradient_fill(stops, x0, x1):
    """Horizontal gradient from x0 to x1 (flat colour outside)."""
    img = Image.new("RGBA", (W, W))
    d = ImageDraw.Draw(img)
    for i in range(0, W, SS):
        d.rectangle([i, 0, i + SS, W], fill=ramp(stops, (i - x0) / max(1, x1 - x0)) + (255,))
    return img


def mark(img, center, radius, width, disk=True):
    gap = 15
    arcs = [
        (-90 + gap, 30 - gap, [hex_rgb("#FFC94A"), hex_rgb("#FF7A1A"), hex_rgb("#F0447A")]),
        (30 + gap, 150 - gap, [hex_rgb("#C9EC4C"), hex_rgb("#22C36A")]),
        (150 + gap, 270 - gap, [hex_rgb("#5CC8FF"), hex_rgb("#5B5BF0")]),
    ]
    ring = arc_layer(center, radius, width, arcs)
    # Coloured glow under the ring.
    glow = ring.copy().filter(ImageFilter.GaussianBlur(width * 0.45))
    glow.putalpha(glow.getchannel("A").point(lambda a: int(a * 0.35)))
    img.alpha_composite(glow)
    img.alpha_composite(ring)
    if disk:
        inner = radius - width * 0.64
        shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).ellipse(
            [center[0] - inner, center[1] - inner + width * 0.18, center[0] + inner, center[1] + inner + width * 0.18],
            fill=(30, 30, 60, 60))
        shadow = shadow.filter(ImageFilter.GaussianBlur(width * 0.35))
        img.alpha_composite(shadow)
        ImageDraw.Draw(img).ellipse(
            [center[0] - inner, center[1] - inner, center[0] + inner, center[1] + inner], fill=(255, 255, 255, 255))
        scale = inner * 0.66
        line = gradient_fill([hex_rgb("#FF9A1A"), hex_rgb("#F0447A"), hex_rgb("#5B5BF0")], center[0] - scale, center[0] + scale)
        mask = pulse_mask(center, scale, width * 0.38)
        img.paste(line, (0, 0), mask)


def main():
    img = background()
    mark(img, (W / 2, W / 2), W * 0.30, W * 0.115)
    icon = img.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    out = os.path.join(ROOT, "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
    icon.save(out)
    icon.resize((512, 512), Image.LANCZOS).save(os.path.join(ROOT, "docs/brand/app-icon.png"))
    print("wrote", out)


if __name__ == "__main__":
    main()
