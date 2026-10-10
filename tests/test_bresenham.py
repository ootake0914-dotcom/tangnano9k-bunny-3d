"""Bresenham walker golden test (no hardware required).

Bit-exact Python model of bunny_bram_top.v S_SETUP_EDGE/S_DRAW_PIXEL.
Every one of the 155 edges is walked at multiple yaw poses and must:
  - terminate at the exact endpoint (no infinite RTL watchdog trips),
  - finish within the 200-cycle watchdog budget,
  - never step outside 160x120 (the pixel_offset wrap/tearing hazard),
  - visit a sane pixel count (max(|dx|,|dy|)+1 for 8-connected lines).
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import fpga_testutil as T

SIN = T.parse_sin_q()
VERTS = T.parse_verts()
EDGES = T.parse_edges()

YAW_SAMPLES = (0, 21, 64, 100, 128, 190, 211, 255)


def _project_all(yaw):
    return [T.rot_project(*v, yaw, SIN)[:2] for v in VERTS]


def test_all_edges_terminate_at_all_sample_yaws():
    worst_steps = 0
    total_px = 0
    n_edges = 0
    for yaw in YAW_SAMPLES:
        pts = _project_all(yaw)
        for a, b in EDGES:
            x0, y0 = pts[a]
            x1, y1 = pts[b]
            px = T.bresenham_walk(x0, y0, x1, y1)  # asserts inside
            assert px[-1] == (x1, y1), f"walker missed endpoint yaw={yaw} {a}->{b}"
            worst_steps = max(worst_steps, len(px) - 1)
            total_px += len(px)
            n_edges += 1
    assert worst_steps < 200, f"worst edge needs {worst_steps} steps (>= watchdog)"
    print(f"[*] {n_edges} edge-walks: all terminate exactly, "
          f"worst {worst_steps}/200 steps, {total_px} px total")


def test_walker_matches_reference_bresenham():
    # Cross-check the RTL-style walker against textbook Bresenham (all octants).
    def reference(x0, y0, x1, y1):
        pts = []
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            pts.append((x0, y0))
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy
        return pts

    checked = 0
    for x0 in (0, 5, 159):
        for y0 in (0, 60, 119):
            for x1 in (0, 80, 159):
                for y1 in (0, 30, 119):
                    if (x0, y0) == (x1, y1):
                        continue
                    assert T.bresenham_walk(x0, y0, x1, y1) == reference(x0, y0, x1, y1), \
                        f"mismatch ({x0},{y0})->({x1},{y1})"
                    checked += 1
    print(f"[*] walker == textbook Bresenham on {checked} corner/octant cases")


def test_degenerate_zero_length_edge():
    assert T.bresenham_walk(80, 60, 80, 60) == [(80, 60)]
    print("[*] zero-length edge draws exactly one pixel")


def main() -> int:
    try:
        test_all_edges_terminate_at_all_sample_yaws()
        test_walker_matches_reference_bresenham()
        test_degenerate_zero_length_edge()
    except AssertionError as e:
        print(f"FAILED: {e}")
        return 1
    print("ALL BRESENHAM TESTS PASSED!")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
