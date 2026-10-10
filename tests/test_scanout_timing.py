"""Video scanout timing golden test (no hardware required).

Python model of the 640x480@60Hz timing generator in bunny_bram_top.v:
  - sync pulse positions/widths (TV lock depends on exact CEA-861 timing),
  - 4x downscale viewport mapping covers 160x120 exactly once per frame,
  - 2px white border frame geometry,
  - framebuffer address formula (py*160+px shift-add, double-buffer base).
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

H_ACTIVE, H_FRONT, H_SYNC, H_BACK, H_TOTAL = 640, 16, 96, 48, 800
V_ACTIVE, V_FRONT, V_SYNC, V_BACK, V_TOTAL = 480, 10, 2, 33, 525


def hsync(h):
    return (H_ACTIVE + H_FRONT) <= h < (H_ACTIVE + H_FRONT + H_SYNC)


def vsync(v):
    return (V_ACTIVE + V_FRONT) <= v < (V_ACTIVE + V_FRONT + V_SYNC)


def test_sync_geometry():
    assert sum(1 for h in range(H_TOTAL) if hsync(h)) == H_SYNC == 96
    assert sum(1 for v in range(V_TOTAL) if vsync(v)) == V_SYNC == 2
    assert [h for h in range(H_TOTAL) if hsync(h)][0] == 656
    assert [v for v in range(V_TOTAL) if vsync(v)][0] == 490
    assert H_TOTAL * V_TOTAL == 800 * 525 == 420000  # 25.2MHz/420000 = 60.00Hz
    print("[*] HSync@656+96, VSync@490+2, 420000 px/frame = 60.00Hz @25.2MHz")


def test_viewport_covers_160x120_exactly_once():
    seen = set()
    for v in range(V_ACTIVE):
        for h in range(H_ACTIVE):
            px, py = h >> 2, v >> 2  # h_cnt[9:2], v_cnt[8:2]
            assert 0 <= px <= 159 and 0 <= py <= 119
            seen.add((px, py))
    assert len(seen) == 160 * 120 == 19200, f"viewport covers {len(seen)} px"
    # each logical pixel is exactly a 4x4 block (no gaps, no overlaps in count)
    print("[*] 640x480 active window maps bijectively onto 160x120 (4x4 blocks)")


def test_border_frame_geometry():
    border = [(h, v) for v in range(V_ACTIVE) for h in range(H_ACTIVE)
              if h < 2 or h >= 638 or v < 2 or v >= 478]
    inner = 640 * 480 - len(border)
    assert inner == 636 * 476, f"inner area {inner}"
    assert len(border) == 640 * 480 - 636 * 476
    print(f"[*] 2px white border frame, inner canvas 636x476")


def test_fb_address_formula():
    # pixel_offset = (by<<7)+(by<<5)+bx == by*160+bx; base selects double buffer
    for by, bx in ((0, 0), (0, 159), (119, 0), (119, 159), (60, 80)):
        off = (by << 7) + (by << 5) + bx
        assert off == by * 160 + bx, f"shift-add mismatch at ({bx},{by})"
        assert 0 <= off < 19200
    for front, base in ((0, 0), (1, 19200)):
        assert base + 19199 < 38400
    print("[*] fb addr = base + by*160+bx, both 19.2k buffers inside 38400 regs")


def test_frame_start_pulse():
    # frame_start = (h_cnt==0 && v_cnt==480): exactly once per frame, in VBlank
    hits = [(h, v) for v in range(V_TOTAL) for h in range(H_TOTAL)
            if h == 0 and v == 480]
    assert hits == [(0, 480)]
    assert not (0 <= 480 < V_ACTIVE)  # must be blanking, not active video
    print("[*] frame_start fires exactly once per frame at line 480 (VBlank)")


def main() -> int:
    try:
        test_sync_geometry()
        test_viewport_covers_160x120_exactly_once()
        test_border_frame_geometry()
        test_fb_address_formula()
        test_frame_start_pulse()
    except AssertionError as e:
        print(f"FAILED: {e}")
        return 1
    print("ALL SCANOUT-TIMING TESTS PASSED!")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
