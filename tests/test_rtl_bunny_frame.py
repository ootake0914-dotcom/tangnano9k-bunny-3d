"""RTL bunny-frame test (iverilog, no hardware required).

Compiles the REAL bunny_bram_top.v + TMDS + PLL wrapper and runs one full
rasterized frame. This is the test that would have caught the rotate-tearing
and any future black-screen regression before touching hardware:
  - FSM must reach draw_frame_done (no hang, no watchdog trip),
  - the frame must contain a sane amount of bunny pixels in all 8 colors,
  - stray/white pixels (uninitialized memory, wrap-around) must be ~zero.
"""

import os
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import fpga_testutil as T

PPM = "/tmp/bunny_sim_frame.ppm"

PALETTE = {
    (28, 40, 80): 0,
    (255, 51, 153): 1,
    (255, 240, 192): 2,
    (0, 229, 255): 3,
    (255, 160, 0): 4,
    (120, 20, 70): 5,
    (120, 110, 80): 6,
    (0, 80, 110): 7,
    (110, 65, 0): 8,
    (255, 255, 255): "stray",
}


def test_frame_sim_completes_and_dumps_ppm():
    rtl = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rtl")
    srcs = [
        os.path.join(rtl, "sim_stubs.v"),
        os.path.join(rtl, "tb_bunny_frame.v"),
        os.path.join(T.BUNNY, "bunny_bram_top.v"),
        os.path.join(T.BUNNY, "gowin_rpll_hdmi.v"),
        os.path.join(T.BUNNY, "gowin_clkdiv.v"),
        os.path.join(T.BUNNY, "tmds_encoder.v"),
    ]
    if os.path.exists(PPM):
        os.remove(PPM)
    log = T.run_sim(srcs, sim_top="tb_bunny_frame", extra_args=("-I", T.BUNNY),
                    cwd=T.BUNNY)
    assert "Frame drawing completed" in log, f"FSM did not finish a frame:\n{log}"
    assert "TIMEOUT" not in log, f"simulation watchdog fired:\n{log}"
    assert os.path.isfile(PPM), "PPM dump missing"
    print("[*] RTL sim: reset -> frame_start -> draw_frame_done, PPM dumped")


def test_frame_pixel_statistics():
    lines = open(PPM).read().strip().split("\n")
    assert lines[:3] == ["P3", "160 120", "255"], f"bad PPM header: {lines[:3]}"
    px = [tuple(int(v) for v in ln.split()) for ln in lines[3:]]
    assert len(px) == 19200, f"want 19200 px, got {len(px)}"
    unknown = [p for p in px if p not in PALETTE]
    assert not unknown, f"{len(unknown)} pixels outside palette, e.g. {unknown[:5]}"
    cnt = Counter(PALETTE[p] for p in px)
    bg = cnt.get(0, 0)
    drawn = 19200 - bg
    print(f"[*] pixels: background={bg}, bunny={drawn}")
    assert 300 <= drawn <= 8000, f"bunny pixel count {drawn} insane (empty? overflow?)"
    for color in range(1, 9):
        assert cnt.get(color, 0) >= 10, \
            f"color {color} has only {cnt.get(color, 0)} px (region dropped?)"
    stray = cnt.get("stray", 0)
    assert stray <= 8, f"{stray} stray white pixels (wrap/uninit memory?)"
    print(f"[*] all 8 bunny colors present (>=10px each), stray white={stray}")


def main() -> int:
    try:
        test_frame_sim_completes_and_dumps_ppm()
        test_frame_pixel_statistics()
    except AssertionError as e:
        print(f"FAILED: {e}")
        return 1
    print("ALL RTL-BUNNY-FRAME TESTS PASSED!")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
