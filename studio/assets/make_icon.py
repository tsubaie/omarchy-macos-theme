"""The app icon: Omarchy's maze mark in lime on a deep-teal macOS squircle.

Styled as Apple draws its icons: a top-to-bottom gradient in one hue, a soft
sheen and a bright rim catching light from above, a slightly darker bottom
edge, and a soft shadow under the mark. The mark is measured from the design
"Lime Geometric Frame Icon" by trace_mark.py. Run:
  python3 trace_mark.py design.png > mark.txt && python3 make_icon.py mark.txt > icon.svg
  python3 make_icon.py mark.txt mono > icon-mono.svg   # graphite and white, as Tahoe's tinted icons
  python3 make_icon.py mark.txt omarchy > icon-omarchy.svg   # graphite and Omarchy's green
"""
import math
import pathlib
import sys

SIZE, C = 1024, 512
MARK = pathlib.Path(sys.argv[1]).read_text().strip()

STYLE = sys.argv[2] if len(sys.argv) > 2 else "color"
BG_TOP, BG_BOTTOM = {"mono": ("#48484C", "#1C1C1E"), "omarchy": ("#48484C", "#1C1C1E")}.get(STYLE, ("#127C78", "#073E46"))
# Omarchy's own green (#9ECE6A, from its icon), lighter at the top.
MARK_TOP, MARK_BOTTOM = {"mono": ("#FFFFFF", "#D6D6DA"), "omarchy": ("#B6DE8C", "#9ECE6A")}.get(STYLE, ("#C6F592", "#A1E35F"))


def squircle(n=5.0, steps=720, inset=0):
    """A superellipse, the continuous curve of macOS icons."""
    r = C - inset
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = C + r * math.copysign(abs(c) ** (2 / n), c)
        y = C + r * math.copysign(abs(s) ** (2 / n), s)
        pts.append(f"{x:.1f},{y:.1f}")
    return "M" + " L".join(pts) + " Z"


SQ = squircle()
print(f"""<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{BG_TOP}"/><stop offset="1" stop-color="{BG_BOTTOM}"/>
    </linearGradient>
    <radialGradient id="sheen" cx="0.5" cy="0" r="0.75">
      <stop offset="0" stop-color="#fff" stop-opacity="0.16"/><stop offset="1" stop-color="#fff" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fff" stop-opacity="0.35"/><stop offset="0.25" stop-color="#fff" stop-opacity="0"/>
      <stop offset="0.85" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.25"/>
    </linearGradient>
    <linearGradient id="ink" gradientUnits="userSpaceOnUse" x1="0" y1="200" x2="0" y2="830">
      <stop offset="0" stop-color="{MARK_TOP}"/><stop offset="1" stop-color="{MARK_BOTTOM}"/>
    </linearGradient>
    <filter id="soft" x="-10%" y="-10%" width="120%" height="125%"><feGaussianBlur stdDeviation="12"/></filter>
  </defs>
  <!-- Filled shapes only, no clipping, so Qt's SVG renderer draws it as browsers do. -->
  <path d="{SQ}" fill="url(#bg)"/>
  <path d="{SQ}" fill="url(#sheen)"/>
  <path d="{MARK}" fill="#000" fill-opacity="0.28" transform="translate(0 12)" filter="url(#soft)"/>
  <path d="{MARK}" fill="url(#ink)"/>
  <path d="{squircle(inset=2)}" fill="none" stroke="url(#rim)" stroke-width="4"/>
</svg>""")
