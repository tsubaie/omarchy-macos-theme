"""Measures the lime mark in the design and prints it as exact SVG outlines.

The mark is made of straight lines at right angles, so instead of tracing a
blurry outline this finds every edge position, rebuilds the shape on that grid,
and merges the cells into seamless outlines.
"""
import sys
from collections import defaultdict
from PIL import Image

img = Image.open(sys.argv[1]).convert("RGB")
W, H = img.size
px = img.load()
lime = [[(lambda p: p[0] > 140 and p[1] > 190 and p[2] < 170)(px[x, y]) for x in range(W)] for y in range(H)]

def edges(count, length, min_hits):
    """Positions where the mask flips often enough to be a real edge, clustered."""
    hits = [i for i in range(1, length) if count(i) >= min_hits]
    groups, cur = [], []
    for i in hits:
        if cur and i - cur[-1] > 4:
            groups.append(cur); cur = []
        cur.append(i)
    if cur: groups.append(cur)
    return [sum(g) / len(g) for g in groups]

xs = edges(lambda x: sum(lime[y][x] != lime[y][x - 1] for y in range(0, H, 2)), W, 25)
ys = edges(lambda y: sum(lime[y][x] != lime[y - 1][x] for x in range(0, W, 2)), H, 25)

def filled(x0, x1, y0, y1):
    n = on = 0
    for y in range(int(y0) + 2, int(y1) - 1, 3):
        for x in range(int(x0) + 2, int(x1) - 1, 3):
            n += 1; on += lime[y][x]
    return n > 0 and on / n > 0.5

cells = {(i, j) for i in range(len(xs) - 1) for j in range(len(ys) - 1)
         if filled(xs[i], xs[i + 1], ys[j], ys[j + 1])}

# Outline: each cell's edges clockwise; shared edges cancel; the rest chain into loops.
edge_set = set()
for i, j in cells:
    for e in [((i, j), (i + 1, j)), ((i + 1, j), (i + 1, j + 1)), ((i + 1, j + 1), (i, j + 1)), ((i, j + 1), (i, j))]:
        rev = (e[1], e[0])
        if rev in edge_set: edge_set.remove(rev)
        else: edge_set.add(e)
nxt = defaultdict(list)
for a, b in edge_set: nxt[a].append(b)
loops = []
while edge_set:
    a, b = next(iter(edge_set)); edge_set.remove((a, b)); nxt[a].remove(b)
    loop = [a, b]
    while loop[-1] != loop[0]:
        c = nxt[loop[-1]].pop(); edge_set.remove((loop[-1], c)); loop.append(c)
    pts = loop[:-1]
    # Keep corners only.
    pts = [p for k, p in enumerate(pts) if not (
        (pts[k - 1][0] == p[0] == pts[(k + 1) % len(pts)][0]) or (pts[k - 1][1] == p[1] == pts[(k + 1) % len(pts)][1]))]
    loops.append(pts)

# Into the 1024 icon: the design's tile (measured) maps onto the 1024 squircle.
tile_x, tile_y, tile = 61, 62, 1134
k = 1024 / tile
def X(i): return round((xs[i] - tile_x) * k * 2) / 2
def Y(j): return round((ys[j] - tile_y - (1126 - tile) / 2) * k * 2) / 2
d = " ".join("M" + " L".join(f"{X(i)},{Y(j)}" for i, j in pts) + " Z" for pts in loops)
sys.stderr.write(f"{len(xs)} x-edges, {len(ys)} y-edges, {len(cells)} cells, {len(loops)} outlines\n")
sys.stderr.write("xs " + " ".join(f"{x:.1f}" for x in xs) + "\nys " + " ".join(f"{y:.1f}" for y in ys) + "\n")
print(d)
