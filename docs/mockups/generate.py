"""Generates the five redesign mockups as one SVG (screens side by side)."""
import math

W, GAP = 393, 60
BG, CARD, TEXT, SEC, SEP = "#F2F4F8", "#FFFFFF", "#111827", "#6B7280", "#E6E9EF"
STRAIN, REC, AMBER, RED, SLEEP, LIFT, NUTR = "#1F7AFF", "#10B866", "#F29A00", "#FF3B4E", "#7A5CFF", "#FF6A1A", "#00B3A4"
FONT = "Inter"
TFONT = "Inter"

defs = []
grad_ids = {}


def grad(c1, c2, vertical=False):
    key = (c1, c2, vertical)
    if key not in grad_ids:
        gid = f"g{len(grad_ids)}"
        grad_ids[key] = gid
        x2, y2 = ("0", "1") if vertical else ("1", "1")
        defs.append(f'<linearGradient id="{gid}" x1="0" y1="0" x2="{x2}" y2="{y2}">'
                    f'<stop offset="0" stop-color="{c1}"/><stop offset="1" stop-color="{c2}"/></linearGradient>')
    return f"url(#{grad_ids[key]})"


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


class Screen:
    def __init__(self, height=852):
        self.h = height
        self.o = []

    def add(self, s):
        self.o.append(s)

    def rect(self, x, y, w, h, r=0, fill=CARD, extra=""):
        self.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" {extra}/>')

    def card(self, x, y, w, h, r=24):
        self.rect(x, y, w, h, r, CARD, 'filter="url(#shadow)"')

    def text(self, x, y, s, size=15, weight=400, color=TEXT, anchor="start", font=None, ls=None, opacity=None):
        f = font or (FONT if size >= 20 else TFONT)
        extra = f' letter-spacing="{ls}"' if ls is not None else ""
        if opacity is not None:
            extra += f' opacity="{opacity}"'
        self.add(f'<text x="{x}" y="{y}" font-family="{f}" font-size="{size}" font-weight="{weight}" '
                 f'fill="{color}" text-anchor="{anchor}"{extra}>{esc(s)}</text>')

    def label(self, x, y, s, color=SEC):
        self.text(x, y, s.upper(), 11, 600, color, ls=0.8)

    def circle(self, cx, cy, r, fill="none", stroke=None, sw=0, extra=""):
        st = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ""
        self.add(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}"{st} {extra}/>')

    def line(self, x1, y1, x2, y2, color=SEP, w=1, extra=""):
        self.add(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{w}" {extra}/>')

    def glow(self, cx, cy, r, color, op=0.22):
        self.add(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{color}" opacity="{op}" filter="url(#blur)"/>')

    def ring(self, cx, cy, r, frac, c1, c2, sw=10, track="#EEF1F6", glow=True, disk=True):
        circ = 2 * math.pi * r
        if disk:
            self.circle(cx, cy, r - sw / 2 - 1, "#FFFFFF")
        self.circle(cx, cy, r, "none", track, sw)
        g = grad(c1, c2)
        if glow:
            self.add(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{c2}" stroke-width="{sw}" '
                     f'stroke-linecap="round" stroke-dasharray="{circ * frac:.1f} {circ:.1f}" opacity="0.35" '
                     f'filter="url(#ringglow)" transform="rotate(-90 {cx} {cy})"/>')
        self.add(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{g}" stroke-width="{sw}" '
                 f'stroke-linecap="round" stroke-dasharray="{circ * frac:.1f} {circ:.1f}" '
                 f'transform="rotate(-90 {cx} {cy})"/>')

    def arc_path(self, cx, cy, r, a0, a1):
        """Arc from angle a0 to a1 in degrees (0 = left, 180 = right, over the top)."""
        def pt(a):
            t = math.radians(180 - a)
            return cx + r * math.cos(t), cy - r * math.sin(t)
        x0, y0 = pt(a0)
        x1, y1 = pt(a1)
        large = 1 if a1 - a0 > 180 else 0
        return f"M{x0:.2f} {y0:.2f} A{r} {r} 0 {large} 1 {x1:.2f} {y1:.2f}"

    def pill(self, x, y, w, h, fill, txt, color, size=13, weight=600):
        self.rect(x, y, w, h, h / 2, fill)
        self.text(x + w / 2, y + h / 2 + size * 0.36, txt, size, weight, color, "middle")

    def spark(self, x, y, w, h, vals, color, sw=2, area=False, dot=True):
        lo, hi = min(vals), max(vals)
        pts = [(x + i * w / (len(vals) - 1), y + h - (v - lo) / (hi - lo or 1) * h) for i, v in enumerate(vals)]
        d = "M" + " L".join(f"{px:.1f} {py:.1f}" for px, py in pts)
        if area:
            g = grad(color + "40", color + "00", vertical=True)
            self.add(f'<path d="{d} L{x + w} {y + h} L{x} {y + h} Z" fill="{g}"/>')
        self.add(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"/>')
        if dot:
            px, py = pts[-1]
            self.circle(px, py, sw * 2 + 1, "#FFFFFF", color, sw)

    def status_bar(self):
        self.text(38, 33, "9:41", 16, 600, TEXT)
        # signal, wifi, battery
        for i in range(4):
            self.rect(300 + i * 5, 28 - i * 2.5, 3, 4 + i * 2.5, 1, TEXT)
        self.add(f'<path d="M327 22.5 a10 10 0 0 1 14 0 M329.5 25.5 a6 6 0 0 1 9 0" fill="none" stroke="{TEXT}" stroke-width="2" stroke-linecap="round"/>')
        self.circle(334, 29, 1.6, TEXT)
        self.rect(349, 21, 25, 12, 4, "none", f'stroke="{TEXT}" stroke-opacity="0.4" stroke-width="1"')
        self.rect(351, 23, 18, 8, 2.5, TEXT)
        self.rect(375.5, 25, 1.6, 4, 1, TEXT, 'opacity="0.4"')

    def tab_bar(self, active):
        y = self.h - 34 - 62
        self.add(f'<rect x="16" y="{y}" width="285" height="62" rx="31" fill="#FFFFFF" fill-opacity="0.78" '
                 f'stroke="#FFFFFF" stroke-width="1" filter="url(#glass)"/>')
        tabs = ["Home", "Fitness", "Coach", "Biology"]
        for i, t in enumerate(tabs):
            cx = 16 + 8 + i * 67.25 + 33.6
            on = t == active
            if on:
                self.rect(cx - 33, y + 6, 66, 50, 25, "#EEF1F6")
            col = TEXT if on else "#8A909C"
            icon_tab(self, t, cx, y + 23, col)
            self.text(cx, y + 47, t, 10, 600 if on else 500, col, "middle")
        self.circle(346, y + 31, 31, TEXT, extra='filter="url(#shadow)"')
        self.add(f'<path d="M346 {y + 21} V{y + 41} M336 {y + 31} H356" stroke="#FFFFFF" stroke-width="2.6" stroke-linecap="round"/>')
        self.rect(W / 2 - 67, self.h - 13, 134, 5, 2.5, TEXT)


def icon_tab(s, t, cx, cy, col):
    st = f'fill="none" stroke="{col}" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"'
    if t == "Home":
        s.add(f'<path d="M{cx - 9} {cy - 1} L{cx} {cy - 9} L{cx + 9} {cy - 1} V{cy + 8} H{cx - 9} Z M{cx - 3} {cy + 8} V{cy + 2} H{cx + 3} V{cy + 8}" {st}/>')
    elif t == "Fitness":
        s.add(f'<path d="M{cx - 10} {cy} H{cx - 5} L{cx - 2} {cy - 7} L{cx + 2} {cy + 7} L{cx + 5} {cy} H{cx + 10}" {st}/>')
    elif t == "Coach":
        sparkle(s, cx - 2, cy + 1, 8, col, outline=True)
        sparkle(s, cx + 7, cy - 6, 3.5, col, outline=True)
    else:
        s.add(f'<path d="M{cx} {cy + 8} C{cx - 12} {cy} {cx - 10} {cy - 10} {cx} {cy - 5} C{cx + 10} {cy - 10} {cx + 12} {cy} {cx} {cy + 8} Z" {st}/>')


def sparkle(s, cx, cy, r, col, outline=False):
    k = r * 0.22
    d = (f"M{cx} {cy - r} Q{cx + k} {cy - k} {cx + r} {cy} Q{cx + k} {cy + k} {cx} {cy + r} "
         f"Q{cx - k} {cy + k} {cx - r} {cy} Q{cx - k} {cy - k} {cx} {cy - r} Z")
    if outline:
        s.add(f'<path d="{d}" fill="none" stroke="{col}" stroke-width="1.8" stroke-linejoin="round"/>')
    else:
        s.add(f'<path d="{d}" fill="{col}"/>')


def check(s, cx, cy, r, fill, done=True):
    if done:
        s.circle(cx, cy, r, fill)
        s.add(f'<path d="M{cx - r * 0.42} {cy} L{cx - r * 0.1} {cy + r * 0.32} L{cx + r * 0.45} {cy - r * 0.32}" '
              f'fill="none" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>')
    else:
        s.circle(cx, cy, r, "#FFFFFF", "#C9CED8", 1.5)


def chevron(s, x, y, col="#A0A6B1"):
    s.add(f'<path d="M{x} {y - 5} L{x + 5} {y} L{x} {y + 5}" fill="none" stroke="{col}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>')


# ---------------------------------------------------------------- (a) TODAY
def today():
    s = Screen(1400)
    s.rect(0, 0, W, s.h, 0, BG)
    s.glow(40, 30, 150, REC, 0.20)
    s.glow(330, 10, 140, STRAIN, 0.16)
    s.status_bar()
    # header
    s.circle(36, 82, 20, grad("#2B2F3A", "#111827"))
    s.text(36, 87, "XS", 14, 700, "#FFFFFF", "middle")
    s.rect(64, 70, 84, 24, 12, "#DDF5E9")
    s.circle(77, 82, 4, REC)
    s.text(88, 86.5, "Synced", 13, 600, "#0B8A4D")
    s.circle(357, 82, 20, "#FFFFFF", extra='filter="url(#shadow)"')
    s.add(f'<path d="M351 87 V80 a6 6 0 0 1 12 0 V87 Z M349 87 H365 M355 90 a2 2 0 0 0 4 0" fill="none" stroke="{TEXT}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>')
    s.text(16, 142, "Today, October 17", 30, 700, ls=-0.5)

    # rings card
    y = 164
    s.card(16, y, 361, 252)
    rings = [("Strain", "11.4", "of 21", 11.4 / 21, "#62A8FF", STRAIN),
             ("Recovery", "72%", "High", 0.72, "#4BDC94", REC),
             ("Sleep", "86%", "7h 43m", 0.86, "#A994FF", SLEEP)]
    for i, (name, val, sub, f, c1, c2) in enumerate(rings):
        cx = 16 + 62 + i * 118.5
        s.ring(cx, y + 74, 44, f, c1, c2, 11)
        s.text(cx, y + 81, val, 21, 700, TEXT, "middle", ls=-0.3)
        s.text(cx, y + 141, name, 14, 600, TEXT, "middle")
        s.text(cx, y + 158, sub, 12, 500, SEC, "middle")
    s.line(32, y + 176, 361, y + 176)
    sparkle(s, 39, y + 195, 6, STRAIN)
    s.label(52, y + 199, "Coaching", STRAIN)
    s.text(32, y + 213, "Recovery is high and you slept well. Push today:", 13.5, 400, TEXT)
    s.text(32, y + 230, "aim for strain 14–18.", 13.5, 700, STRAIN)

    # strain goal card
    y = 432
    s.card(16, y, 361, 330)
    s.label(32, y + 30, "Strain goal")
    s.rect(272, y + 15, 89, 24, 12, "#E6F0FF")
    s.text(316.5, y + 31.5, "2.6 to go", 13, 700, STRAIN, "middle")
    s.text(32, y + 66, "11.4", 34, 700, TEXT, ls=-0.8)
    s.text(106, y + 66, "/ target 14–18", 16, 500, SEC)
    # bar
    bx, bw, by = 32, 329, y + 92
    sc = bw / 21
    s.rect(bx, by, bw, 12, 6, "#EEF1F6")
    s.rect(bx + 14 * sc, by - 4, 4 * sc, 20, 6, "#10B86630", f'stroke="{REC}" stroke-width="1.5" stroke-dasharray="3 2.5"')
    s.rect(bx, by, 11.4 * sc, 12, 6, grad("#7DB8FF", STRAIN))
    mx = bx + 11.4 * sc
    s.circle(mx, by + 6, 10, "#FFFFFF", STRAIN, 3.5, 'filter="url(#shadow)"')
    for v in (0, 7, 14, 18, 21):
        s.text(bx + v * sc, by + 34, str(v), 11, 600 if v in (14, 18) else 500,
               "#0B8A4D" if v in (14, 18) else "#9AA0AB", "middle")
    s.text(bx + 16 * sc, by - 10, "Target", 11, 600, "#0B8A4D", "middle")
    # suggestions
    sy = y + 152
    s.label(32, sy, "Suggested to close the gap")
    rows = [("Push Day", "45 min · Strength", "+3.8", LIFT, "dumbbell"),
            ("Zone 2 ride", "30 min · Cardio", "+2.9", STRAIN, "bike")]
    for i, (t, sub, plus, col, ic) in enumerate(rows):
        ry = sy + 14 + i * 50
        s.rect(32, ry, 329, 44, 14, "#F5F7FA")
        s.rect(40, ry + 6, 32, 32, 10, col + "1F")
        draw_icon(s, ic, 56, ry + 22, col)
        s.text(82, ry + 20, t, 15, 600)
        s.text(82, ry + 36, sub, 12, 500, SEC)
        s.text(330, ry + 27, plus, 15, 700, STRAIN, "end")
        chevron(s, 343, ry + 22)
    s.rect(32, y + 274, 329, 44, 22, TEXT)
    s.add(f'<path d="M{132} {y + 289} L{142} {y + 296} L{132} {y + 303} Z" fill="#FFFFFF"/>')
    s.text(206, y + 301, "Start workout", 15, 600, "#FFFFFF", "middle")

    # nutrition card
    y = 778
    s.card(16, y, 361, 200)
    s.label(32, y + 30, "Nutrition")
    s.text(361, y + 30, "From Cronometer", 12, 500, SEC, "end")
    s.ring(92, y + 112, 52, 1840 / 2600, "#3ADBC9", NUTR, 11)
    s.text(92, y + 113, "1,840", 22, 700, TEXT, "middle", ls=-0.4)
    s.text(92, y + 131, "of 2,600 kcal", 11, 500, SEC, "middle")
    macros = [("Protein", "132", "/ 150 g", 132 / 150, NUTR), ("Carbs", "210", "g", 210 / 300, AMBER),
              ("Fat", "64", "g", 64 / 90, SLEEP)]
    for i, (n, v, unit, f, col) in enumerate(macros):
        my = y + 66 + i * 42
        s.text(172, my, n, 13, 500, SEC)
        s.add(f'<text x="361" y="{my}" text-anchor="end" font-family="{TFONT}" font-size="14" fill="{TEXT}">'
              f'<tspan font-weight="700">{v}</tspan><tspan font-weight="500" fill="{SEC}"> {unit}</tspan></text>')
        s.rect(172, my + 9, 189, 6, 3, "#EEF1F6")
        s.rect(172, my + 9, 189 * f, 6, 3, col)

    # health monitor
    y = 998
    s.text(16, y + 20, "Health Monitor", 22, 700, ls=-0.3)
    s.text(377, y + 20, "All normal", 13, 600, REC, "end")
    tiles = [("Resting HR", "54", "bpm", "Lower", REC, 0.32, (0.35, 0.7)),
             ("HRV", "61", "ms", "Higher", REC, 0.78, (0.3, 0.68)),
             ("Respiratory", "14.8", "rpm", "Normal", SEC, 0.52, (0.3, 0.7)),
             ("Sleep", "7h 43m", "", "Normal", SEC, 0.55, (0.3, 0.72))]
    for i, (n, v, unit, st, col, pos, band) in enumerate(tiles):
        tx = 16 + (i % 2) * 184.5
        ty = y + 38 + (i // 2) * 128
        s.card(tx, ty, 176.5, 116, 22)
        s.text(tx + 16, ty + 28, n, 13, 600, SEC)
        s.add(f'<text x="{tx + 16}" y="{ty + 70}" font-family="{FONT}" font-size="28" fill="{TEXT}" letter-spacing="-0.6">'
              f'<tspan font-weight="700">{v}</tspan><tspan font-size="14" font-weight="500" fill="{SEC}" letter-spacing="0"> {unit}</tspan></text>')
        badge_bg = "#DDF5E9" if col == REC else "#EEF1F6"
        badge_fg = "#0B8A4D" if col == REC else SEC
        bw = 14 + len(st) * 7
        s.rect(tx + 16, ty + 82, bw, 22, 11, badge_bg)
        if st in ("Lower", "Higher"):
            arrow = "↓" if st == "Lower" else "↑"
            s.text(tx + 16 + bw / 2, ty + 97, f"{arrow} {st}", 12, 600, badge_fg, "middle")
        else:
            s.text(tx + 16 + bw / 2, ty + 97, st, 12, 600, badge_fg, "middle")
        # vertical range gauge
        gx, gy, gh = tx + 150, ty + 22, 74
        s.rect(gx - 3, gy, 6, gh, 3, "#EEF1F6")
        s.rect(gx - 3, gy + gh * (1 - band[1]), 6, gh * (band[1] - band[0]), 3, "#C8EED9" if col == REC else "#DCE0E7")
        s.circle(gx, gy + gh * (1 - pos), 6, "#FFFFFF", col if col == REC else TEXT, 3)
    s.tab_bar("Home")
    return s


def draw_icon(s, kind, cx, cy, col):
    st = f'fill="none" stroke="{col}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"'
    if kind == "dumbbell":
        s.add(f'<path d="M{cx - 9} {cy - 4} V{cy + 4} M{cx - 6} {cy - 7} V{cy + 7} M{cx + 6} {cy - 7} V{cy + 7} M{cx + 9} {cy - 4} V{cy + 4} M{cx - 6} {cy} H{cx + 6}" {st}/>')
    elif kind == "bike":
        s.add(f'<circle cx="{cx - 6}" cy="{cy + 3}" r="4.5" {st}/><circle cx="{cx + 6}" cy="{cy + 3}" r="4.5" {st}/>'
              f'<path d="M{cx - 6} {cy + 3} L{cx - 2} {cy - 5} H{cx + 3} L{cx + 6} {cy + 3} M{cx - 2} {cy - 5} L{cx + 1} {cy + 3} H{cx + 6} M{cx - 4} {cy - 7} H{cx}" {st}/>')
    elif kind == "walk":
        s.add(f'<circle cx="{cx + 1}" cy="{cy - 7}" r="2.2" fill="{col}"/>'
              f'<path d="M{cx} {cy - 3} L{cx - 2} {cy + 3} L{cx + 2} {cy + 8} M{cx - 2} {cy + 3} L{cx - 5} {cy + 8} M{cx} {cy - 3} L{cx + 5} {cy} M{cx} {cy - 3} L{cx - 5} {cy - 1}" {st}/>')


# ---------------------------------------------------------------- (b) FITNESS
def fitness():
    s = Screen(1330)
    s.rect(0, 0, W, s.h, 0, BG)
    s.glow(200, 0, 170, STRAIN, 0.18)
    s.status_bar()
    s.text(16, 96, "Fitness", 30, 700, ls=-0.5)
    s.circle(357, 86, 20, "#FFFFFF", extra='filter="url(#shadow)"')
    s.add(f'<rect x="349" y="79" width="16" height="15" rx="3" fill="none" stroke="{TEXT}" stroke-width="1.7"/>'
          f'<path d="M349 84 H365 M353 76 V81 M361 76 V81" stroke="{TEXT}" stroke-width="1.7" stroke-linecap="round"/>')
    # week strip
    days = [("W", "14", 12.1), ("T", "15", 8.4), ("F", "16", 15.2), ("S", "17", 11.4),
            ("S", "18", None), ("M", "19", None), ("T", "20", None)]
    y = 118
    for i, (d, n, v) in enumerate(days):
        cx = 16 + 25 + i * 51.5
        today_ = n == "17"
        if today_:
            s.rect(cx - 24, y, 48, 92, 20, "#FFFFFF", 'filter="url(#shadow)"')
        s.text(cx, y + 20, d, 12, 600, STRAIN if today_ else SEC, "middle")
        if v is None:
            s.circle(cx, y + 48, 16, "none", "#C9CED8", 2.5, 'stroke-dasharray="3 3.5"')
        else:
            s.ring(cx, y + 48, 16, v / 21, "#62A8FF", STRAIN, 4.5, glow=False)
            s.text(cx, y + 52, f"{v}", 10, 700, TEXT, "middle")
        s.text(cx, y + 82, n, 13, 700 if today_ else 500, TEXT if today_ else SEC, "middle")

    # gauge card
    y = 226
    s.card(16, y, 361, 290)
    s.label(32, y + 30, "Day strain")
    s.text(361, y + 30, "Target 14–18", 12, 600, "#0B8A4D", "end")
    cx, cy, r = 196.5, y + 190, 118
    a = lambda v: v / 21 * 180
    s.add(f'<path d="{s.arc_path(cx, cy, r, 0, 180)}" fill="none" stroke="#EEF1F6" stroke-width="22" stroke-linecap="round"/>')
    s.add(f'<path d="{s.arc_path(cx, cy, r, a(14), a(18))}" fill="none" stroke="#10B86638" stroke-width="34"/>')
    s.add(f'<path d="{s.arc_path(cx, cy, r + 21, a(14), a(18))}" fill="none" stroke="{REC}" stroke-width="3" stroke-linecap="round"/>')
    s.add(f'<path d="{s.arc_path(cx, cy, r, 0, a(11.4))}" fill="none" stroke="{STRAIN}" stroke-width="22" stroke-linecap="round" opacity="0.35" filter="url(#ringglow)"/>')
    s.add(f'<path d="{s.arc_path(cx, cy, r, 0, a(11.4))}" fill="none" stroke="{grad("#8EC3FF", STRAIN)}" stroke-width="22" stroke-linecap="round"/>')
    t = math.radians(180 - a(11.4))
    s.circle(cx + r * math.cos(t), cy - r * math.sin(t), 8, "#FFFFFF", extra='filter="url(#shadow)"')
    for v in (0, 7, 14, 21):
        tt = math.radians(180 - a(v))
        s.text(cx + (r - 36) * math.cos(tt), cy - (r - 36) * math.sin(tt) + 4, str(v), 11, 600, "#9AA0AB", "middle")
    s.text(cx, cy - 16, "11.4", 48, 700, TEXT, "middle", ls=-1.5)
    s.text(cx, cy + 6, "of 21 strain", 13, 500, SEC, "middle")
    s.rect(32, y + 222, 329, 52, 16, "#E8F8F0")
    sparkle(s, 52, y + 248, 7, REC)
    s.add(f'<text x="68" y="{y + 244}" font-family="{TFONT}" font-size="13.5" fill="{TEXT}"><tspan font-weight="700" fill="#0B8A4D">2.6 to go:</tspan>'
          f'<tspan font-weight="500"> finish today\'s push session</tspan></text>')
    s.text(68, y + 262, "to hit your target.", 13.5, 500)

    # training load
    y = 536
    s.text(16, y + 20, "Training Load", 22, 700, ls=-0.3)
    loads = [("Cardio", 9, (7, 11), 16, STRAIN, "#62A8FF"), ("Muscular", 14, (8, 17), 24, LIFT, "#FFA066")]
    for i, (n, v, (lo, hi), mx, col, c1) in enumerate(loads):
        tx = 16 + i * 184.5
        ty = y + 38
        s.card(tx, ty, 176.5, 168, 22)
        s.text(tx + 16, ty + 28, n, 14, 600)
        s.rect(tx + 112, ty + 13, 50, 22, 11, "#DDF5E9")
        s.text(tx + 137, ty + 28, "Optimal", 11, 600, "#0B8A4D", "middle")
        gx, gy, gr = tx + 88.25, ty + 118, 56
        f = lambda val: val / mx * 180
        s.add(f'<path d="{s.arc_path(gx, gy, gr, 0, 180)}" fill="none" stroke="#EEF1F6" stroke-width="12" stroke-linecap="round"/>')
        s.add(f'<path d="{s.arc_path(gx, gy, gr + 11, f(lo), f(hi))}" fill="none" stroke="{REC}" stroke-width="3" stroke-linecap="round"/>')
        s.add(f'<path d="{s.arc_path(gx, gy, gr, 0, f(v))}" fill="none" stroke="{grad(c1, col)}" stroke-width="12" stroke-linecap="round"/>')
        s.text(gx, gy - 6, str(v), 30, 700, TEXT, "middle", ls=-0.8)
        s.text(gx, gy + 12, f"optimal {lo}–{hi}", 11, 500, SEC, "middle")
        s.text(tx + 16, ty + 156, "0", 10, 500, "#9AA0AB")
        s.text(tx + 160.5, ty + 156, f"max {mx}", 10, 500, "#9AA0AB", "end")

    # today's activity
    y = 764
    s.text(16, y + 20, "Today's Activity", 22, 700, ls=-0.3)
    s.card(16, y + 38, 361, 148)
    acts = [("Push Day", "52 min · 12,450 lb", "+4.1", LIFT, "dumbbell", "6:42 AM"),
            ("Walk", "24 min · 2.1 km", "+1.2", REC, "walk", "12:15 PM")]
    for i, (t, sub, plus, col, ic, time) in enumerate(acts):
        ry = y + 38 + 16 + i * 66
        s.rect(32, ry + 4, 44, 44, 14, col + "1F")
        draw_icon(s, ic, 54, ry + 26, col)
        s.text(90, ry + 22, t, 16, 600)
        s.text(90, ry + 41, f"{sub} · {time}", 12.5, 500, SEC)
        s.rect(304, ry + 13, 57, 26, 13, "#E6F0FF")
        s.text(332.5, ry + 30.5, plus, 13, 700, STRAIN, "middle")
        if i == 0:
            s.line(90, ry + 60, 361, ry + 60)

    # HR zones
    y = 970
    s.text(16, y + 20, "Heart Rate Zones", 22, 700, ls=-0.3)
    s.card(16, y + 38, 361, 220)
    zones = [("Z1", "Warm-up", 18, "#5AA9FF"), ("Z2", "Fat burn", 31, "#14C38E"), ("Z3", "Aerobic", 14, "#FFC107"),
             ("Z4", "Threshold", 7, "#FF7A1A"), ("Z5", "Max", 2, "#FF2D55")]
    base = y + 38 + 170
    for i, (z, n, m, col) in enumerate(zones):
        bx = 40 + i * 66
        h = m / 31 * 116
        s.rect(bx, base - 116, 40, 116, 10, "#F3F5F8")
        s.rect(bx, base - h, 40, max(h, 8), min(10, max(h, 8) / 2), grad(col, col + "B0", vertical=True))
        s.text(bx + 20, base - h - 8, f"{m}m", 12, 700, TEXT, "middle")
        s.text(bx + 20, base + 20, z, 12, 700, TEXT, "middle")
        s.text(bx + 20, base + 34, n, 10, 500, SEC, "middle")
    s.text(32, y + 66, "72 min tracked · avg 128 bpm", 12.5, 500, SEC)
    s.tab_bar("Fitness")
    return s


# ---------------------------------------------------------------- (c) LIVE WORKOUT
def live():
    s = Screen(900)
    s.rect(0, 0, W, s.h, 0, BG)
    s.glow(330, 40, 150, LIFT, 0.18)
    s.glow(60, 20, 120, STRAIN, 0.12)
    s.status_bar()
    s.circle(36, 82, 18, "#FFFFFF", extra='filter="url(#shadow)"')
    s.add(f'<path d="M30 79 L36 85 L42 79" fill="none" stroke="{TEXT}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>')
    s.rect(291, 64, 86, 36, 18, LIFT)
    s.text(334, 87, "Finish", 15, 700, "#FFFFFF", "middle")
    s.circle(205, 82, 4, RED)
    s.text(215, 86.5, "LIVE", 12, 700, RED, ls=0.8)
    # hero
    y = 116
    s.text(16, y + 28, "Push Day", 30, 700, ls=-0.5)
    s.text(16, y + 74, "38:12", 46, 700, TEXT, ls=-1.5, font="Inter")
    s.text(16, y + 98, "Elapsed · 3 of 4 exercises", 13, 500, SEC)
    s.ring(320, y + 56, 46, 3.2 / 6, "#62A8FF", STRAIN, 10)
    s.text(320, y + 57, "+3.2", 22, 700, TEXT, "middle", ls=-0.4)
    s.text(320, y + 74, "strain", 11, 500, SEC, "middle")
    # rest pill
    y = 238
    s.add(f'<rect x="16" y="{y}" width="361" height="52" rx="26" fill="{grad("#3D8EFF", STRAIN)}" filter="url(#shadow)"/>')
    s.circle(44, y + 26, 13, "#FFFFFF33")
    s.add(f'<circle cx="44" cy="{y + 26}" r="13" fill="none" stroke="#FFFFFF" stroke-width="3" stroke-dasharray="48 82" stroke-linecap="round" transform="rotate(-90 44 {y + 26})"/>')
    s.add(f'<text x="68" y="{y + 32}" font-family="{TFONT}" font-size="16" fill="#FFFFFF"><tspan font-weight="600">Rest</tspan>'
          f'<tspan font-weight="700" font-family="Inter"> 1:24</tspan></text>')
    s.rect(220, y + 12, 50, 28, 14, "#FFFFFF2E")
    s.text(245, y + 31, "−15s", 13, 600, "#FFFFFF", "middle")
    s.rect(278, y + 12, 50, 28, 14, "#FFFFFF2E")
    s.text(303, y + 31, "+15s", 13, 600, "#FFFFFF", "middle")
    s.text(353, y + 31, "Skip", 14, 700, "#FFFFFF", "middle")

    # bench card
    y = 306
    s.card(16, y, 361, 384)
    s.rect(32, y + 16, 40, 40, 12, LIFT + "1F")
    draw_icon(s, "dumbbell", 52, y + 36, LIFT)
    s.text(84, y + 34, "Bench Press", 18, 700)
    s.text(84, y + 52, "Barbell · Chest", 12.5, 500, SEC)
    s.rect(281, y + 22, 80, 26, 13, "#FFF0E6")
    s.add(f'<path d="M296 {y + 29} L298 {y + 33.5} L303 {y + 34} L299.5 {y + 37} L300.5 {y + 42} L296 {y + 39.5} L291.5 {y + 42} L292.5 {y + 37} L289 {y + 34} L294 {y + 33.5} Z" fill="{LIFT}"/>')
    s.text(334, y + 39.5, "New PR", 12, 700, LIFT, "middle")
    cols = [("SET", 44), ("PREVIOUS", 108), ("LB", 192), ("REPS", 240), ("RPE", 288), ("", 340)]
    hy = y + 84
    for c, x in cols:
        s.text(x, hy, c, 10.5, 700, "#9AA0AB", "middle", ls=0.6)
    rows = [("W", "95 × 10", "95", "10", "—", "done"), ("1", "185 × 8", "185", "8", "7", "done"),
            ("2", "185 × 8", "185", "8", "8", "done"), ("3", "185 × 7", "190", "8", "", "current")]
    for i, (st, prev, lb, reps, rpe, state) in enumerate(rows):
        ry = hy + 14 + i * 46
        if state == "current":
            s.rect(28, ry, 337, 42, 14, "#FFF4EC", f'stroke="{LIFT}" stroke-opacity="0.5" stroke-width="1.5"')
        elif state == "done":
            s.rect(28, ry, 337, 42, 14, "#EAF8F1")
        stc = AMBER if st == "W" else TEXT
        s.text(44, ry + 26, st, 14, 700, stc, "middle")
        s.text(108, ry + 26, prev, 13.5, 500, "#9AA0AB", "middle")
        for v, x in ((lb, 192), (reps, 240), (rpe, 288)):
            if state == "current":
                s.rect(x - 21, ry + 8, 42, 26, 8, "#FFFFFF", f'stroke="#F0D6C4" stroke-width="1"')
                s.text(x, ry + 26, v if v else "RPE", 14.5 if v else 12, 700 if v else 500,
                       TEXT if v else "#B4B9C2", "middle")
            else:
                s.text(x, ry + 26, v, 14.5, 700 if x != 288 else 600, TEXT if x != 288 or v != "—" else "#9AA0AB", "middle")
        if state == "done":
            check(s, 340, ry + 21, 12, REC)
        else:
            check(s, 340, ry + 21, 12, None, done=False)
    ay = hy + 14 + 4 * 46 + 10
    s.rect(32, ay, 329, 40, 14, "#F3F5F8")
    s.text(196.5, ay + 25, "+  Add set", 14, 600, TEXT, "middle")
    s.text(32, ay + 64, "Last time: 185 × 8, 8, 7 · Goal: beat 1,480 lb volume", 12, 500, SEC)

    # collapsed cards
    y = 706
    s.card(16, y, 361, 70, 22)
    check(s, 48, y + 35, 14, REC)
    s.text(74, y + 31, "Incline DB Press", 16, 600)
    s.text(74, y + 50, "3 sets · 60 lb × 10 · done", 12.5, 500, SEC)
    chevron(s, 351, y + 35)
    y = 788
    s.card(16, y, 361, 70, 22)
    s.circle(48, y + 35, 14, "#EEF1F6")
    s.text(48, y + 40, "4", 13, 700, SEC, "middle")
    s.text(74, y + 31, "Cable Fly", 16, 600)
    s.text(74, y + 50, "3 × 12 @ RPE 8", 12.5, 500, SEC)
    s.rect(277, y + 22, 66, 26, 13, "#E6F0FF")
    s.text(310, y + 39.5, "Up next", 12, 700, STRAIN, "middle")
    # bottom finish
    s.rect(W / 2 - 67, s.h - 13, 134, 5, 2.5, TEXT)
    return s


# ---------------------------------------------------------------- (d) BIOLOGY
def biology():
    s = Screen(950)
    s.rect(0, 0, W, s.h, 0, BG)
    s.glow(320, 20, 160, SLEEP, 0.20)
    s.glow(40, 60, 120, REC, 0.14)
    s.status_bar()
    s.text(16, 96, "Biology", 30, 700, ls=-0.5)
    s.text(16, 120, "Your long-term baselines", 14, 500, SEC)
    # hero
    y = 140
    s.card(16, y, 361, 252)
    s.label(32, y + 30, "HRV baseline")
    s.text(361, y + 30, "90 days", 12, 600, SEC, "end")
    s.add(f'<text x="32" y="{y + 82}" font-family="{FONT}" font-size="52" fill="{TEXT}" letter-spacing="-1.5">'
          f'<tspan font-weight="700">58</tspan><tspan font-size="20" font-weight="600" fill="{SEC}" letter-spacing="0"> ms</tspan></text>')
    s.rect(152, y + 58, 138, 28, 14, "#DDF5E9")
    s.text(221, y + 77, "↑ 6% vs last month", 13, 700, "#0B8A4D", "middle")
    vals = [50, 52, 49, 51, 53, 51, 54, 52, 55, 53, 52, 55, 57, 54, 56, 58, 55, 57, 59, 58, 60, 58]
    s.line(32, y + 140, 361, y + 140, SEP, 1, 'stroke-dasharray="3 4"')
    s.text(32, y + 134, "Baseline 55", 10, 600, "#9AA0AB")
    s.spark(32, y + 110, 329, 100, vals, SLEEP, 3, area=True)
    for i, m in enumerate(["Jul", "Aug", "Sep", "Oct"]):
        s.text(32 + i * 109.6, y + 234, m, 11, 500, "#9AA0AB", "start" if i == 0 else ("end" if i == 3 else "middle"))

    # biomarkers
    y = 412
    s.text(16, y + 20, "Biomarkers", 22, 700, ls=-0.3)
    s.card(16, y + 38, 361, 5 * 76 + 8)
    rows = [("Weight", "Decreasing", "163.8", "lb", STRAIN, [167, 166.5, 166.8, 166, 165.4, 165.6, 164.9, 164.5, 164.6, 163.8], "#E6F0FF", STRAIN),
            ("RHR baseline", "Excellent", "54", "bpm", RED, [58, 57, 57.5, 56, 56.4, 55.5, 55, 55.3, 54.5, 54], "#DDF5E9", "#0B8A4D"),
            ("Body fat", "Fit", "13.3", "%", AMBER, [14.6, 14.4, 14.5, 14.1, 13.9, 14.0, 13.7, 13.6, 13.5, 13.3], "#DDF5E9", "#0B8A4D"),
            ("VO₂ max", "Fair", "42.0", "", SLEEP, [40.2, 40.5, 40.4, 41, 40.8, 41.3, 41.5, 41.4, 41.8, 42], "#FFF3DE", "#B86E00"),
            ("Protein · 7-day avg", "On target", "128", "g", NUTR, [118, 124, 121, 130, 126, 133, 129, 125, 131, 128], "#DDF5E9", "#0B8A4D")]
    for i, (n, st, v, unit, col, vals, bbg, bfg) in enumerate(rows):
        ry = y + 38 + 4 + i * 76
        s.text(32, ry + 28, n, 14, 600, SEC)
        s.add(f'<text x="32" y="{ry + 56}" font-family="{FONT}" font-size="24" fill="{TEXT}" letter-spacing="-0.5">'
              f'<tspan font-weight="700">{v}</tspan><tspan font-size="13" font-weight="500" fill="{SEC}" letter-spacing="0"> {unit}</tspan></text>')
        bw = 16 + len(st) * 6.8
        bx = 150
        s.rect(bx, ry + 39, bw, 22, 11, bbg)
        s.text(bx + bw / 2, ry + 54, st, 11.5, 700, bfg, "middle")
        s.spark(250, ry + 22, 82, 34, vals, col, 2.2)
        chevron(s, 352, ry + 38)
        if i < 4:
            s.line(32, ry + 76, 361, ry + 76)
    s.tab_bar("Biology")
    return s


# ---------------------------------------------------------------- (e) COACH
def coach():
    s = Screen(880)
    s.rect(0, 0, W, s.h, 0, BG)
    s.glow(200, 10, 170, SLEEP, 0.18)
    s.glow(40, 80, 110, STRAIN, 0.12)
    s.status_bar()
    sparkle(s, 30, 86, 13, grad("#A994FF", STRAIN))
    sparkle(s, 44, 72, 5, SLEEP)
    s.text(52, 96, "Coach", 30, 700, ls=-0.5)
    s.circle(357, 86, 20, "#FFFFFF", extra='filter="url(#shadow)"')
    s.add(f'<path d="M349 80 H365 M349 86 H365 M349 92 H359" stroke="{TEXT}" stroke-width="1.8" stroke-linecap="round"/>')
    s.text(16, 122, "Knows today's data · on-device + cloud", 13, 500, SEC)
    # context chips
    chips = [("Recovery", "72%", REC, 110), ("Strain", "11.4 / 14–18", STRAIN, 136), ("Protein", "132 g", NUTR, 103)]
    x = 16
    for n, v, col, w in chips:
        s.rect(x, 138, w, 32, 16, "#FFFFFF", 'filter="url(#shadow)"')
        s.circle(x + 12, 154, 3.5, col)
        s.add(f'<text x="{x + 20}" y="158.5" font-family="{TFONT}" font-size="11.5" fill="{SEC}">'
              f'<tspan font-weight="500">{n} </tspan><tspan font-weight="700" fill="{TEXT}">{v}</tspan></text>')
        x += w + 5
    # user bubble
    s.add(f'<rect x="174" y="196" width="203" height="44" rx="22" fill="{grad("#3D8EFF", STRAIN)}"/>')
    s.text(275.5, 223, "How should I train today?", 15, 500, "#FFFFFF", "middle")
    # coach reply
    y = 258
    s.circle(30, y + 14, 14, grad("#A994FF", STRAIN))
    sparkle(s, 30, y + 14, 7, "#FFFFFF")
    s.add(f'<text x="52" y="{y + 19}" font-family="{TFONT}" font-size="15" fill="{TEXT}" font-weight="400">'
          f'Recovery is <tspan font-weight="700" fill="#0B8A4D">72%</tspan> and you slept 7h 43m,</text>')
    s.text(52, y + 40, "so today is a good day to push. You're at 11.4;", 15, 400)
    s.text(52, y + 61, "this session should land you around 15.", 15, 400)
    # workout card
    y = 340
    s.card(52, y, 325, 330)
    s.label(68, y + 28, "Suggested", LIFT)
    s.text(68, y + 54, "Push Day", 20, 700)
    s.add(f'<text x="361" y="{y + 54}" text-anchor="end" font-family="{TFONT}" font-size="13" fill="{SEC}">'
          f'45 min · <tspan font-weight="700" fill="{STRAIN}">≈+3.8 strain</tspan></text>')
    ex = [("Bench Press", "4 × 6–8 @ RPE 8"), ("Incline DB Press", "3 × 10 @ RPE 8"),
          ("Overhead Press", "3 × 8 @ RPE 7"), ("Cable Fly", "3 × 12 @ RPE 8")]
    for i, (n, d) in enumerate(ex):
        ry = y + 76 + i * 48
        s.rect(68, ry, 30, 30, 9, "#FFF0E6")
        s.text(83, ry + 20, str(i + 1), 13, 700, LIFT, "middle")
        s.text(110, ry + 14, n, 14.5, 600)
        s.text(110, ry + 30, d, 12, 500, SEC)
        if i < 3:
            s.line(110, ry + 41, 361, ry + 41)
    s.rect(68, y + 270, 293, 44, 22, TEXT)
    s.add(f'<path d="M138 {y + 284} L148 {y + 292} L138 {y + 300} Z" fill="#FFFFFF"/>')
    s.text(226, y + 297, "Start this workout", 15, 600, "#FFFFFF", "middle")
    s.text(52, y + 350, "Want a lighter option, or swap an exercise?", 13, 500, SEC)
    # suggestion chips
    y = 718
    sug = ["Make it 30 min", "Swap for a ride", "What should I eat?"]
    x = 16
    for t in sug:
        w = 26 + len(t) * 7.1
        s.rect(x, y, w, 36, 18, "#FFFFFF", f'stroke="{SEP}" stroke-width="1"')
        s.text(x + w / 2, y + 23, t, 13, 600, TEXT, "middle")
        x += w + 8
    # glass message bar
    y = s.h - 34 - 60
    s.add(f'<rect x="16" y="{y}" width="361" height="56" rx="28" fill="#FFFFFF" fill-opacity="0.8" stroke="#FFFFFF" filter="url(#glass)"/>')
    s.add(f'<path d="M38 {y + 28} H50 M44 {y + 22} V{y + 34}" stroke="{SEC}" stroke-width="2" stroke-linecap="round"/>')
    s.text(64, y + 33, "Ask your coach…", 15, 400, "#9AA0AB")
    s.add(f'<path d="M304 {y + 20} v12 a5 5 0 0 0 10 0 v-12 a5 5 0 0 0 -10 0 Z M299 {y + 30} a10 10 0 0 0 20 0 M309 {y + 40} v3" fill="none" stroke="{SEC}" stroke-width="1.8" stroke-linecap="round"/>')
    s.circle(355, y + 28, 18, grad("#3D8EFF", STRAIN))
    s.add(f'<path d="M355 {y + 36} V{y + 20} M349 {y + 26} L355 {y + 20} L361 {y + 26}" fill="none" stroke="#FFFFFF" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>')
    s.rect(W / 2 - 67, s.h - 13, 134, 5, 2.5, TEXT)
    return s


screens = [today(), fitness(), live(), biology(), coach()]

if __name__ == "__main__":
    import sys
    out = sys.argv[1]
    total_w = len(screens) * W + (len(screens) - 1) * GAP
    total_h = max(sc.h for sc in screens)
    body = []
    for i, sc in enumerate(screens):
        body.append(f'<g id="screen{i + 1}" transform="translate({i * (W + GAP)} 0)">' + "".join(sc.o) + "</g>")
    common = ('<filter id="shadow" x="-20%" y="-20%" width="140%" height="160%"><feDropShadow dx="0" dy="4" stdDeviation="9" flood-color="#0B1220" flood-opacity="0.07"/></filter>'
              '<filter id="glass" x="-20%" y="-40%" width="140%" height="200%"><feDropShadow dx="0" dy="8" stdDeviation="12" flood-color="#0B1220" flood-opacity="0.12"/></filter>'
              '<filter id="blur" x="-80%" y="-80%" width="260%" height="260%"><feGaussianBlur stdDeviation="50"/></filter>'
              '<filter id="ringglow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="5"/></filter>')
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{total_w}" height="{total_h}" viewBox="0 0 {total_w} {total_h}">'
           f'<defs>{common}{"".join(defs)}</defs>{"".join(body)}</svg>')
    open(out, "w").write(svg)
    print(total_w, total_h, [sc.h for sc in screens])
