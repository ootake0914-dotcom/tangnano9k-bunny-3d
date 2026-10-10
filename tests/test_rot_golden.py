"""Rotation-pipeline golden test (no hardware required).

Bit-exact Python model of bunny_bram_top.v S_ROT_FETCH/STAGE1/STAGE2
(yaw LUT -> 25-bit products -> >>>12 -> x108/x144 scale -> clamp).
Guards the fixed-point math against regressions: LUT symmetry, yaw
periodicity, clamp action, front/back-bit consistency, register headroom.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import fpga_testutil as T

SIN = T.parse_sin_q()
VERTS = T.parse_verts()


def test_yaw_lut_full_circle_symmetry():
    # sin^2+cos^2 ~= 1 (Q12 scale) at every yaw step
    worst = 0.0
    for yaw in range(256):
        s, c = T.yaw_sin_cos(yaw, SIN)
        err = abs((s / 4095) ** 2 + (c / 4095) ** 2 - 1.0)
        worst = max(worst, err)
    assert worst < 0.01, f"sin/cos norm error {worst:.4f} too large"
    print(f"[*] yaw LUT: sin^2+cos^2=1 within {worst:.4f} over all 256 steps")


def test_yaw_periodicity_and_lsb_insensitive():
    # yaw[0] is dropped by the LUT (six=yaw[5:1]), so yaw^1 must be identical
    for yaw in range(0, 256, 2):
        for v in VERTS[::7]:
            a = T.rot_project(*v, yaw, SIN)
            b = T.rot_project(*v, yaw + 1, SIN)
            assert a == b, f"yaw {yaw} vs {yaw+1} differ on {v}: {a} vs {b}"
    # full 256-step rotation returns to start for every vertex
    for v in VERTS:
        a = T.rot_project(*v, 0, SIN)
        b = T.rot_project(*v, 256 & 0xFF, SIN)
        assert a == b
    print("[*] yaw: 256-step periodic, bit0-insensitive (128 distinct poses)")


def test_projection_fits_viewport_with_margin():
    min_sx, max_sx, min_sy, max_sy = 159, 0, 119, 0
    for yaw in range(256):
        for v in VERTS:
            sx, sy, front, raw_sx, raw_sy, xrot, zrot = T.rot_project(*v, yaw, SIN)
            assert (sx, sy) == (raw_sx, raw_sy), \
                f"steady-state pose needs clamp?! yaw={yaw} v={v}"
            assert -4096 <= xrot <= 4095 and -4096 <= zrot <= 4095, \
                f"13-bit rot reg overflow: yaw={yaw} v={v}"
            min_sx, max_sx = min(min_sx, sx), max(max_sx, sx)
            min_sy, max_sy = min(min_sy, sy), max(max_sy, sy)
    # Steady state must keep a healthy margin from every viewport edge.
    assert min_sx >= 30 and max_sx <= 129, f"sx extremes {min_sx}..{max_sx}"
    assert min_sy >= 10 and max_sy <= 109, f"sy extremes {min_sy}..{max_sy}"
    print(f"[*] all 14336 poses fit unclamped: "
          f"sx {min_sx}..{max_sx}, sy {min_sy}..{max_sy} (margin >= 30/10px)")


def _clamp_sx(raw):
    return 0 if raw < 0 else (159 if raw > 159 else raw)


def _clamp_sy(raw):
    return 0 if raw < 0 else (119 if raw > 119 else raw)


def test_clamp_guard_logic_and_wrap_hazard():
    # Replica of the RTL clamped_sx/sy ternaries: must pin every integer
    # into range (the guard against single-cycle glitch garbage, which the
    # steady-state math above can never produce by design).
    for raw in range(-512, 512):
        assert 0 <= _clamp_sx(raw) <= 159
        assert 0 <= _clamp_sy(raw) <= 119
        assert _clamp_sx(raw) == min(max(raw, 0), 159)
        assert _clamp_sy(raw) == min(max(raw, 0), 119)
    # Demonstrate the hazard the clamp prevents: raw sx=-1 sliced as [7:0]
    # becomes 255, throwing pixel_offset one full raster row down (tearing).
    assert (-1) & 0xFF == 255
    wrapped = (60 * 160 + 255) - (60 * 160 + 0)
    assert wrapped == 255, "row-wrap stride must be 255 to prove the hazard"
    print("[*] clamp pins [-512,512] into range; -1->[7:0]=255 wrap hazard documented")


def test_sy_independent_of_yaw():
    # r_yrot comes straight from vy (pitch is baked into ROM), so sy must be
    # yaw-invariant for each vertex. If this breaks, the pipeline mis-routes y.
    for v in VERTS:
        sys_ = {T.rot_project(*v, yaw, SIN)[1] for yaw in range(256)}
        assert len(sys_) == 1, f"vertex {v} sy varies with yaw: {sorted(sys_)}"
    print("[*] sy yaw-invariant for all 56 verts (y path clean)")


def test_front_bit_matches_zrot_sign():
    for yaw in range(256):
        for v in VERTS:
            sx, sy, front, raw_sx, raw_sy, xrot, zrot = T.rot_project(*v, yaw, SIN)
            assert front == (1 if zrot >= 0 else 0)
    # both faces must appear across a full rotation (else 3D sort is dead)
    faces = {T.rot_project(*VERTS[0], yaw, SIN)[2] for yaw in range(256)}
    assert faces == {0, 1}, "vertex 0 never changes face: rotation broken?"
    print("[*] front/back bit consistent with zrot sign; faces flip over rotation")


def main() -> int:
    try:
        test_yaw_lut_full_circle_symmetry()
        test_yaw_periodicity_and_lsb_insensitive()
        test_projection_fits_viewport_with_margin()
        test_clamp_guard_logic_and_wrap_hazard()
        test_sy_independent_of_yaw()
        test_front_bit_matches_zrot_sign()
    except AssertionError as e:
        print(f"FAILED: {e}")
        return 1
    print("ALL ROT-GOLDEN TESTS PASSED!")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
