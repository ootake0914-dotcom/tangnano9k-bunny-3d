"""TMDS encoder golden test (no hardware required).

Bit-exact Python model of bunny_bram/tmds_encoder.v (DVI 1.0 spec).
Checks the SPEC properties every change must preserve:
  - control codes are the exact DVI idle words (TV word-sync depends on them),
  - running disparity stays bounded over hostile data streams,
  - blanking resets disparity (mode-switch click guard),
  - q_m minimizes transitions per the ones-count rule.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import fpga_testutil as T


def test_control_codes_exact():
    for ctrl, want in T.CTRL_CODES.items():
        out, _ = T.tmds_encode_stream([(0, 0, ctrl)])
        assert out[0] == want, f"ctrl {ctrl:02b}: got {out[0]:010b}, want {want:010b}"
    print("[*] control codes exact: "
          + ", ".join(f"{c:02b}->{v:010b}" for c, v in T.CTRL_CODES.items()))


def test_disparity_bounded_over_all_bytes():
    syms = [(1, d, 0) for d in range(256)]
    outs, disps = T.tmds_encode_stream(syms)
    peak = max(abs(d) for d in disps)
    assert peak <= 10, f"running disparity peak {peak} exceeds bound"
    assert len(set(outs)) == 256, "data code mapping not injective"
    print(f"[*] 256-byte sweep: disparity peak {peak} (bound 10), 256 unique codes")


def test_disparity_bounded_over_hostile_stream():
    # Alternating worst-case bytes keep flipping the disparity sign.
    hostile = [0x00, 0xFF, 0x55, 0xAA, 0x0F, 0xF0, 0x33, 0xCC] * 64
    syms = [(1, d, 0) for d in hostile]
    _, disps = T.tmds_encode_stream(syms)
    peak = max(abs(d) for d in disps)
    assert peak <= 10, f"hostile stream disparity peak {peak}"
    print(f"[*] hostile 512-symbol stream: disparity peak {peak}")


def test_blank_resets_disparity():
    syms = [(1, 0xFF, 0)] * 40 + [(0, 0, 0)] + [(1, 0x00, 0)]
    outs, disps = T.tmds_encode_stream(syms)
    assert disps[40] == 0, "blanking must reset disparity to 0"
    assert outs[40] == T.CTRL_CODES[0]
    print("[*] blanking interval resets disparity (clean mode switch)")


def test_transition_minimization_rule():
    # ones>4 (or ==4 with lsb 0) must use XNOR chain (q_m[8]=0);
    # otherwise XOR chain (q_m[8]=1).
    for data in (0xFF, 0xF0, 0x0F, 0x00, 0x55, 0xAA, 0x81):
        ones = bin(data).count("1")
        want_xnor = (ones > 4) or (ones == 4 and (data & 1) == 0)
        out, _ = T.tmds_encode_stream([(1, data, 0)])
        qm8 = (out[0] >> 8) & 1
        # With disparity==0 the encoder keeps q_m polarity (bit9=~qm8, bit8=qm8)
        assert qm8 == (0 if want_xnor else 1), \
            f"data {data:02X}: ones={ones} want_xnor={want_xnor}, got qm8={qm8}"
    print("[*] XOR/XNOR selection follows the ones-count rule")


def main() -> int:
    try:
        test_control_codes_exact()
        test_disparity_bounded_over_all_bytes()
        test_disparity_bounded_over_hostile_stream()
        test_blank_resets_disparity()
        test_transition_minimization_rule()
    except AssertionError as e:
        print(f"FAILED: {e}")
        return 1
    print("ALL TMDS-GOLDEN TESTS PASSED!")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
