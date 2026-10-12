"""bunny_tables.vh ROM structural test (no hardware required).

The .vh file is the single source of truth for vertex/edge/sine/region data.
Any accidental edit (dropped line, bad index, out-of-range value) must fail here.
Vertex/edge contents are cross-checked against the generator outputs in
tests/testdata/ (the mesh decimation sources).
"""

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import fpga_testutil as T

TESTDATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "testdata")

# Verts 9/13 were isolated in the source decimated mesh; repaired with
# triangle edges (9,13),(13,10),(9,10), so no isolated verts remain.
# Asserted exactly so any mesh/table change fails loudly instead of silently.
KNOWN_ISOLATED_VERTS = set()
NUM_VERTS = 256
NUM_EDGES = 700


def test_vert_count_and_index_coverage():
    verts = T.parse_verts()
    assert len(verts) == NUM_VERTS, f"want {NUM_VERTS} verts, got {len(verts)}"
    print(f"[*] vert_rom: {NUM_VERTS} entries, indices 0..{NUM_VERTS-1} fully covered")


def test_vert_ranges_fit_q12():
    verts = T.parse_verts()
    for i, (x, y, z) in enumerate(verts):
        for name, v in (("x", x), ("y", y), ("z", z)):
            assert -2048 <= v <= 2047, f"vert {i}.{name}={v} out of signed-12-bit range"
    xs = [v[0] for v in verts]
    print(f"[*] vert ranges: x[{min(xs)},{max(xs)}] "
          f"y[{min(v[1] for v in verts)},{max(v[1] for v in verts)}] "
          f"z[{min(v[2] for v in verts)},{max(v[2] for v in verts)}] (Q4 px units)")


def test_edge_count_and_valid_indices():
    edges = T.parse_edges()
    assert len(edges) == NUM_EDGES, f"want {NUM_EDGES} edges, got {len(edges)}"
    for i, (a, b) in enumerate(edges):
        assert 0 <= a < NUM_VERTS and 0 <= b < NUM_VERTS, f"edge {i}=({a},{b}) bad vertex index"
        assert a != b, f"edge {i} is degenerate ({a}=={b})"
    assert len(set(edges)) == NUM_EDGES, "duplicate edges found"
    used = {v for e in edges for v in e}
    isolated = set(range(NUM_VERTS)) - used
    assert isolated == KNOWN_ISOLATED_VERTS, \
        f"isolated verts changed: {sorted(isolated)} (known {sorted(KNOWN_ISOLATED_VERTS)})"
    print(f"[*] edge_rom: {NUM_EDGES} unique edges, all {NUM_VERTS} verts referenced "
          f"(9/13 repaired)")


def test_verts_match_generator_source():
    p = os.path.join(TESTDATA, "bunny56.json")
    if not os.path.exists(p):
        print(f"[*] skipping verts generator source check ({os.path.basename(p)} not present)")
        return
    golden = json.load(open(p))["q"]
    verts = T.parse_verts()
    assert len(golden) == NUM_VERTS, "testdata mesh changed size?"
    bad = [i for i in range(NUM_VERTS) if tuple(golden[i]) != verts[i]]
    assert not bad, f"RTL verts differ from generator source at {bad}"
    print(f"[*] all {NUM_VERTS} RTL verts bit-match the generator mesh (bunny56.json)")


def test_edges_match_generator_source():
    p = os.path.join(TESTDATA, "bunny_edges.json")
    if not os.path.exists(p):
        print(f"[*] skipping edges generator source check ({os.path.basename(p)} not present)")
        return
    golden = [tuple(e) for e in json.load(open(p))["edges"]]
    edges = T.parse_edges()
    assert sorted(golden) == sorted(edges), "RTL edges differ from generator source"
    print(f"[*] all {NUM_EDGES} RTL edges match the generator mesh (bunny_edges.json)")


def test_sin_quarter_wave_shape():
    tbl = T.parse_sin_q()
    assert len(tbl) == 32
    # Strictly increasing (quarter sine 0..90deg, midpoint sampled)
    for i in range(31):
        assert tbl[i] < tbl[i + 1], f"sin_q not increasing at {i}"
    # Peak must approach full scale 4095 from below
    assert 4090 <= tbl[31] <= 4095, f"sin_q peak {tbl[31]} not near 4095"
    # Spot-check against ideal midpoint-sampled sine within 1 LSB
    for i in (0, 7, 15, 23, 31):
        ideal = math.sin((i + 0.5) / 32 * math.pi / 2) * 4095
        assert abs(tbl[i] - round(ideal)) <= 1, \
            f"sin_q[{i}]={tbl[i]} vs ideal {ideal:.2f}"
    print(f"[*] sin_q: monotonic 0..90deg, peak={tbl[31]}, matches ideal sine +/-1LSB")


def test_region_ids_valid():
    rg = T.parse_regions()
    assert len(rg) == NUM_VERTS
    assert set(rg) <= {0, 1, 2, 3}, f"region ids out of range: {set(rg)}"
    for r in range(4):
        assert rg.count(r) > 0, f"region {r} has no vertices (dead color branch?)"
    print(f"[*] rg_rom: regions used = {sorted(set(rg))}, "
          f"counts={[rg.count(r) for r in range(4)]}")


def main() -> int:
    try:
        test_vert_count_and_index_coverage()
        test_vert_ranges_fit_q12()
        test_edge_count_and_valid_indices()
        test_verts_match_generator_source()
        test_edges_match_generator_source()
        test_sin_quarter_wave_shape()
        test_region_ids_valid()
    except AssertionError as e:
        print(f"FAILED: {e}")
        return 1
    print("ALL BUNNY-TABLES TESTS PASSED!")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
