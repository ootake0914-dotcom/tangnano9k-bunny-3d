"""RTL TMDS test (iverilog, no hardware required).

Dumps every output of the REAL tmds_encoder.v and cross-checks bit-exactly
against the Python golden model:
  - 256 isolated data symbols (disparity reset before each),
  - 4 control words (must equal the DVI idle codes for TV word-sync),
  - 256-symbol back-to-back stream (running-disparity sequence must match).
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import fpga_testutil as T


def _dump():
    if _dump.cache is not None:
        return _dump.cache
    rtl = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rtl")
    srcs = [
        os.path.join(rtl, "tb_tmds.v"),
        os.path.join(T.BUNNY, "tmds_encoder.v"),
    ]
    log = T.run_sim(srcs, sim_top="tb_tmds")
    assert "TMDS dump complete" in log, f"TB did not finish:\n{log}"
    data = {}
    for m in re.finditer(r"TMDS_DATA (\d+) ([01]{10})", log):
        data[int(m.group(1))] = int(m.group(2), 2)
    ctrl = {}
    for m in re.finditer(r"TMDS_CTRL (\d+) ([01]{10})", log):
        ctrl[int(m.group(1))] = int(m.group(2), 2)
    stream = {}
    for m in re.finditer(r"TMDS_STREAM (\d+) ([01]{10})", log):
        stream[int(m.group(1))] = int(m.group(2), 2)
    assert len(data) == 256, f"got {len(data)}/256 isolated vectors"
    assert len(ctrl) == 4, f"got {len(ctrl)}/4 control vectors"
    assert len(stream) == 256, f"got {len(stream)}/256 stream vectors"
    _dump.cache = (data, ctrl, stream)
    return data, ctrl, stream


_dump.cache = None


def test_isolated_data_matches_golden():
    data, _, _ = _dump()
    bad = 0
    for d in range(256):
        want, _ = T.tmds_encode_stream([(1, d, 0)])
        if data[d] != want[0]:
            print(f"  mismatch data {d:02X}: RTL={data[d]:010b} gold={want[0]:010b}")
            bad += 1
    assert bad == 0, f"{bad}/256 isolated symbols differ from golden model"
    print("[*] 256/256 isolated data symbols bit-match the golden model")


def test_control_words_match_golden():
    _, ctrl, _ = _dump()
    for c in range(4):
        assert ctrl[c] == T.CTRL_CODES[c], \
            f"ctrl {c:02b}: RTL={ctrl[c]:010b} want={T.CTRL_CODES[c]:010b}"
    print("[*] 4/4 control words bit-match (TV word-sync safe)")


def test_stream_disparity_sequence_matches():
    _, _, stream = _dump()
    syms = [(1, d, 0) for d in range(256)]
    want_outs, want_disps = T.tmds_encode_stream(syms)
    bad = sum(1 for d in range(256) if stream[d] != want_outs[d])
    assert bad == 0, f"{bad}/256 stream symbols differ from golden model"
    peak = max(abs(d) for d in want_disps)
    print(f"[*] 256-symbol stream bit-matches; RTL disparity peak {peak}")


def main() -> int:
    try:
        test_isolated_data_matches_golden()
        test_control_words_match_golden()
        test_stream_disparity_sequence_matches()
    except AssertionError as e:
        print(f"FAILED: {e}")
        return 1
    print("ALL RTL-TMDS TESTS PASSED!")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
