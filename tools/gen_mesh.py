#!/usr/bin/env python3
"""Regenerate bunny mesh at higher density from /tmp/bunny_full.obj.

- Farthest-point sampling -> NV verts (even coverage for wireframe).
- Edges: map each original face's verts to nearest sampled vert, emit
  distinct pairs; then guarantee min-degree-2 (ear-tip lesson!); cap at EMAX
  by dropping longest.
- Normalization replicates the 56-mesh framing: X-tilt -15deg baked,
  centered, uniform scale to fit Q4 +/-1200, quantized.
- Regions by y-bands calibrated from the 56-mesh (0:ears y>=840,
  1:head -70..840, 2:body -750..-70, 3:feet y<-750).
- Outputs: tests/testdata/bunny56.json (q verts), bunny_edges.json (edges),
  and bunny_bram/bunny_tables.vh (vert_rom/edge_rom/rg_rom; sin_q untouched).
Usage: gen_mesh.py [NV=128] [EMAX=450]
"""
import json
import math
import os
import sys

import numpy as np

NV = int(sys.argv[1]) if len(sys.argv) > 1 else 128
EMAX = int(sys.argv[2]) if len(sys.argv) > 2 else 450

WS = "/home/yuhki/tangnano9k_workspace"
OBJ = "/tmp/bunny_full.obj"


def load_obj(path):
    V, F = [], []
    with open(path) as fh:
        for line in fh:
            if line.startswith("v "):
                V.append([float(x) for x in line.split()[1:4]])
            elif line.startswith("f "):
                F.append([int(t.split("/")[0]) - 1 for t in line.split()[1:4]])
    return np.array(V), np.array(F, dtype=int)


def farthest_point(V, n, seed=7):
    rng = np.random.default_rng(seed)
    N = len(V)
    sel = [int(rng.integers(N))]
    mind = np.full(N, np.inf)
    for _ in range(1, n):
        d = np.linalg.norm(V - V[sel[-1]], axis=1)
        mind = np.minimum(mind, d)
        sel.append(int(np.argmax(mind)))
    return sel


def main():
    V, F = load_obj(OBJ)
    print(f"src: {len(V)} verts, {len(F)} faces")
    sel = farthest_point(V, NV)
    S = V[sel]

    # nearest sampled index for every src vert
    d2 = ((V[:, None, :] - S[None, :, :]) ** 2).sum(-1)
    nearest = d2.argmin(1)

    # edges from faces
    edges = set()
    for a, b, c in F:
        ia, ib, ic = nearest[a], nearest[b], nearest[c]
        for u, v in ((ia, ib), (ib, ic), (ic, ia)):
            if u != v:
                edges.add((min(u, v), max(u, v)))

    # min-degree-2 repair (ear-tip lesson)
    deg = [0] * NV
    for u, v in edges:
        deg[u] += 1
        deg[v] += 1
    D = np.linalg.norm(S[:, None, :] - S[None, :, :], axis=-1)
    np.fill_diagonal(D, np.inf)
    for i in range(NV):
        while deg[i] < 2:
            j = int(np.argmin(D[i]))
            e = (min(i, j), max(i, j))
            if e not in edges:
                edges.add(e)
                deg[i] += 1
                deg[j] += 1
            D[i, j] = D[j, i] = np.inf

    # cap by dropping longest
    elist = sorted(edges, key=lambda e: float(np.linalg.norm(S[e[0]] - S[e[1]])))
    elist = [(int(u), int(v)) for u, v in elist]
    if len(elist) > EMAX:
        elist = elist[:EMAX]
    # re-check isolation after cap
    used = {v for e in elist for v in e}
    missing = sorted(set(range(NV)) - used)
    print(f"sampled={NV} edges={len(elist)} isolated={missing}")
    assert not missing, f"isolated verts remain: {missing}"

    # normalize: tilt -15deg about X, center, uniform scale to +/-1200
    t = math.radians(-15)
    R = np.array([[1, 0, 0],
                  [0, math.cos(t), -math.sin(t)],
                  [0, math.sin(t), math.cos(t)]])
    T = (R @ S.T).T
    T -= (T.max(0) + T.min(0)) / 2
    T *= 1200.0 / np.abs(T).max()
    Q = np.round(T).astype(int)
    assert np.abs(Q).max() <= 2047

    def region(y):
        if y >= 840:
            return 0
        if y >= -70:
            return 1
        if y >= -750:
            return 2
        return 3

    RG = [region(y) for _, y, _ in Q]
    from collections import Counter
    print("regions:", dict(Counter(RG)))
    print("extents x", Q[:, 0].min(), Q[:, 0].max(),
          "y", Q[:, 1].min(), Q[:, 1].max(),
          "z", Q[:, 2].min(), Q[:, 2].max())

    # longest edge in px (watchdog sanity: must stay < 200)
    proj = [(80 + x * 108 / 4096, 60 - y * 144 / 4096) for x, y, _ in Q]
    wl = max(math.hypot(proj[u][0] - proj[v][0], proj[u][1] - proj[v][1])
             for u, v in elist)
    print(f"worst projected edge length: {wl:.1f}px")

    # write testdata
    td = os.path.join(WS, "tests", "testdata")
    json.dump({"q": Q.tolist()}, open(os.path.join(td, "bunny56.json"), "w"))
    json.dump({"edges": [list(e) for e in elist]},
              open(os.path.join(td, "bunny_edges.json"), "w"))

    # write BSRAM init hex (vert: 36-bit hex, edge: 16-bit hex)
    hx = os.path.join(WS, "bunny_bram")
    with open(os.path.join(hx, "vert_mem.hex"), "w") as f:
        for x, y, z in Q:
            f.write("%09x\n" % ((int(x) & 0xFFF) << 24 |
                                (int(y) & 0xFFF) << 12 | (int(z) & 0xFFF)))
    with open(os.path.join(hx, "edge_mem.hex"), "w") as f:
        for u, v in elist:
            f.write("%04x\n" % ((int(u) << 8) | int(v)))

    # write .vh (sin_q + rg_rom only; vert/edge live in BSRAM hex files)
    vh_path = os.path.join(WS, "bunny_bram", "bunny_tables.vh")
    old = open(vh_path).read()
    start = old.index("// sin quarter-wave LUT")
    end = old.index("endfunction", start) + len("endfunction")
    sin_sec = old[start:end]
    L = ["// bunny%d: vert/edge ROMs in BSRAM (vert_mem.hex/edge_mem.hex);" % NV,
         "// this file keeps sin_q + rg_rom only.",
         sin_sec.rstrip(),
         "",
         "// bunny vertex region ROM: 0=ears 1=head 2=body 3=feet.",
         "function [1:0] rg_rom(input [%d:0] idx);" % ((NV - 1).bit_length(),),
         "    case (idx)"]
    VW = (NV - 1).bit_length() + 1
    for i, r in enumerate(RG):
        L.append("        %d'd%d: rg_rom = 2'd%d;" % (VW, i, r))
    L += ["        default: rg_rom = 2'd0;", "    endcase", "endfunction", ""]
    open(vh_path, "w").write("\n".join(L))
    print(f"wrote {vh_path}: sin_q + rg_rom ({NV} verts)")


if __name__ == "__main__":
    main()
