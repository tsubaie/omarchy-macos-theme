"""The app icon: Omarchy's mark in lime on a green-to-navy macOS squircle.

The mark, colors and proportions follow the design "Lime Geometric Frame Icon";
trace_mark.py measures the mark from it. Run:
  python3 trace_mark.py design.png > mark.txt && python3 make_icon.py mark.txt > icon.svg
"""
import math
import pathlib
import re
import sys

SIZE, C = 1024, 512
# Measured from the design by trace_mark.py, in icon coordinates.
MARK = pathlib.Path(sys.argv[1]).read_text().strip()


def squircle(n=5.0, steps=720):
    """A superellipse, the continuous curve of macOS icons."""
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = C + C * math.copysign(abs(c) ** (2 / n), c)
        y = C + C * math.copysign(abs(s) ** (2 / n), s)
        pts.append(f"{x:.1f},{y:.1f}")
    return "M" + " L".join(pts) + " Z"


print(f"""<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">
  <defs>
    <linearGradient id="sky" x1="0.05" y1="0.05" x2="0.95" y2="0.95">
      <stop offset="0" stop-color="#48E092"/>
      <stop offset="0.27" stop-color="#0AAA93"/>
      <stop offset="0.5" stop-color="#03697B"/>
      <stop offset="0.73" stop-color="#024A68"/>
      <stop offset="1" stop-color="#022C4B"/>
    </linearGradient>
  </defs>
  <!-- Filled shapes only, no clipping or filters, so Qt's SVG renderer draws it as browsers do. -->
  <path d="{squircle()}" fill="url(#sky)"/>
  <path d="{MARK}" fill="#ACEB72"/>
</svg>""")
