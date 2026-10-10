"""Shared helpers for the tangnano9k FPGA regression suite (no hardware needed).

- Resolves workspace paths (tests/ -> workspace root).
- Parses bunny_bram/bunny_tables.vh ROM contents (single source of truth).
- Bit-exact Python model of the bunny_bram_top.v rotation pipeline.
- Bit-exact Python model of the S_SETUP_EDGE/S_DRAW_PIXEL Bresenham walker.
- Bit-exact Python model of the DVI TMDS encoder (tmds_encoder.v).
- iverilog discovery + compile/run helper (works with apt iverilog or OSS CAD Suite).
"""

import os
import re
import shutil
import subprocess

WS_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if os.path.isfile(os.path.join(WS_ROOT, "bunny_tables.vh")):
    BUNNY = WS_ROOT
else:
    BUNNY = os.path.join(WS_ROOT, "bunny_bram")
VH_PATH = os.path.join(BUNNY, "bunny_tables.vh")

OSS_BIN = os.environ.get("TOOLCHAIN_PATH", "/home/yuhki/oss-cad-suite/bin")


def ensure_iverilog():
    """Return (iverilog, vvp) paths, preferring PATH, falling back to OSS CAD Suite."""
    iv = shutil.which("iverilog")
    vv = shutil.which("vvp")
    if iv and vv:
        return iv, vv
    iv = os.path.join(OSS_BIN, "iverilog")
    vv = os.path.join(OSS_BIN, "vvp")
    if os.path.isfile(iv) and os.path.isfile(vv):
        return iv, vv
    return None, None


def run_sim(sources, sim_top="tb", timeout=300, extra_args=(), cwd=None):
    """Compile Verilog sources with iverilog and run with vvp. Returns stdout text."""
    iv, vv = ensure_iverilog()
    assert iv is not None, "iverilog not found (apt install iverilog or OSS CAD Suite)"
    workdir = "/tmp/fpga_tests"
    os.makedirs(workdir, exist_ok=True)
    vvp_path = os.path.join(workdir, sim_top + ".vvp")
    cmd = [iv, "-o", vvp_path, "-g2012"] + list(extra_args) + list(sources)
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                       cwd=cwd or WS_ROOT)
    assert r.returncode == 0, f"iverilog failed:\n{r.stdout}\n{r.stderr}"
    r = subprocess.run([vv, vvp_path], capture_output=True, text=True,
                       timeout=timeout, cwd=cwd or WS_ROOT)
    assert r.returncode == 0, f"vvp failed (rc={r.returncode}):\n{r.stdout}\n{r.stderr}"
    return r.stdout


# ---------------------------------------------------------------- ROM parsing

def _vh_text():
    with open(VH_PATH) as f:
        return f.read()


def parse_sin_q():
    """Return list of 32 sin_q quarter-wave entries (midpoint sampled, Q12)."""
    txt = _vh_text()
    m = re.search(r"function \[11:0\] sin_q.*?case \(i\)(.*?)endcase", txt, re.S)
    assert m, "sin_q function not found in bunny_tables.vh"
    vals = re.findall(r"\d+'d(\d+):\s*sin_q\s*=\s*12'd(\d+);", m.group(1))
    tbl = [0] * 32
    for idx, val in vals:
        tbl[int(idx)] = int(val)
    assert len(vals) == 32, f"sin_q has {len(vals)} entries, want 32"
    return tbl


def _signed12(tok):
    tok = tok.strip()
    mm = re.match(r"(-?)12's?d(\d+)", tok)
    assert mm, f"bad 12-bit literal: {tok}"
    v = int(mm.group(2))
    return -v if mm.group(1) == "-" else v


def _s12(v):
    return v - 4096 if v >= 2048 else v


def parse_verts():
    """Return list of N (vx, vy, vz) signed 12-bit tuples from vert_mem.hex."""
    lines = open(os.path.join(BUNNY, "vert_mem.hex")).read().strip().split("\n")
    verts = []
    for ln in lines:
        w = int(ln.strip(), 16)
        verts.append((_s12((w >> 24) & 0xFFF),
                      _s12((w >> 12) & 0xFFF),
                      _s12(w & 0xFFF)))
    assert len(verts) >= 1
    return verts


def parse_edges():
    """Return list of N (v0, v1) index pairs from edge_mem.hex (skip zero pad)."""
    lines = open(os.path.join(BUNNY, "edge_mem.hex")).read().strip().split("\n")
    edges = []
    for ln in lines:
        w = int(ln.strip(), 16)
        u, v = (w >> 8) & 0xFF, w & 0xFF
        if (u, v) != (0, 0):
            edges.append((u, v))
    assert len(edges) >= 1
    return edges


def parse_regions():
    """Return list of N region ids (0..3)."""
    txt = _vh_text()
    m = re.search(r"function \[1:0\] rg_rom.*?case \(idx\)(.*?)endcase", txt, re.S)
    assert m, "rg_rom function not found in bunny_tables.vh"
    rows = re.findall(r"\d+'d(\d+):\s*rg_rom\s*=\s*2'd(\d+);", m.group(1))
    assert len(rows) >= 1
    rg = [None] * len(rows)
    for idx, v in rows:
        rg[int(idx)] = int(v)
    assert all(v is not None for v in rg), "rg_rom missing indices"
    return rg


# ---------------------------------------------------------------- rotation model

def _asr_floor(value, shift):
    """Verilog signed >>> : arithmetic shift = floor(value / 2**shift)."""
    return value // (1 << shift)


def yaw_sin_cos(yaw, sin_tbl):
    """Replicate quarter-sine yaw LUT. Returns (sin_val, cos_val) signed 13-bit."""
    yaw &= 0xFF
    sq = (yaw >> 6) & 3
    six = (yaw >> 1) & 31
    six_m = six if (sq == 0 or sq == 2) else (31 - six)
    sin_mag = sin_tbl[six_m]
    sin_val = -sin_mag if (sq == 2 or sq == 3) else sin_mag
    yaw_c = (yaw + 64) & 0xFF
    cq = (yaw_c >> 6) & 3
    cix = (yaw_c >> 1) & 31
    cix_m = cix if (cq == 0 or cq == 2) else (31 - cix)
    cos_mag = sin_tbl[cix_m]
    cos_val = -cos_mag if (cq == 2 or cq == 3) else cos_mag
    return sin_val, cos_val


def rot_project(vx, vy, vz, yaw, sin_tbl):
    """Bit-exact model of S_ROT_FETCH/STAGE1/STAGE2 + clamp.

    Returns (sx_clamped, sy_clamped, front_bit, raw_sx, raw_sy, xrot, zrot).
    """
    sin_val, cos_val = yaw_sin_cos(yaw, sin_tbl)
    xrot = _asr_floor(vx * cos_val + vz * sin_val, 12)
    zrot = _asr_floor(vz * cos_val - vx * sin_val, 12)
    # Shift-add scale (exact: 128-16-4=108, 128+16=144), mirrors RTL.
    sx_full = (xrot << 7) - (xrot << 4) - (xrot << 2)
    raw_sx = 80 + _asr_floor(sx_full, 12)
    raw_sy = 60 - _asr_floor((vy << 7) + (vy << 4), 12)
    sx = 0 if raw_sx < 0 else (159 if raw_sx > 159 else raw_sx)
    sy = 0 if raw_sy < 0 else (119 if raw_sy > 119 else raw_sy)
    return sx, sy, (1 if zrot >= 0 else 0), raw_sx, raw_sy, xrot, zrot


# ---------------------------------------------------------------- Bresenham walker model

def bresenham_walk(x0, y0, x1, y1, watchdog_limit=200):
    """Bit-exact model of S_SETUP_EDGE + S_DRAW_PIXEL.

    Returns pixel list. Raises AssertionError on watchdog trip or OOB step,
    mirroring the RTL's pixel_offset wrap hazard.
    """
    dx = x1 - x0
    dy = y1 - y0
    bdx = -dx if dx < 0 else dx
    step_x_dir = 1 if dx < 0 else 0
    bdy = dy if dy < 0 else -dy
    step_y_dir = 1 if dy < 0 else 0
    berr = bdx + bdy
    bx, by = x0, y0
    pixels = [(bx, by)]
    watchdog = 0
    while not (bx == x1 and by == y1):
        assert watchdog < watchdog_limit, \
            f"watchdog trip on edge ({x0},{y0})->({x1},{y1})"
        watchdog += 1
        e2 = berr << 1
        step_x = e2 >= bdy
        step_y = e2 <= bdx
        if step_x:
            bx = bx - 1 if step_x_dir else bx + 1
        if step_y:
            by = by - 1 if step_y_dir else by + 1
        if step_x:
            berr = berr + bdy
        if step_y:
            berr = berr + bdx
        assert 0 <= bx <= 159 and 0 <= by <= 119, \
            f"OOB step to ({bx},{by}) on edge ({x0},{y0})->({x1},{y1})"
        pixels.append((bx, by))
    return pixels


# ---------------------------------------------------------------- TMDS model

CTRL_CODES = {0: 0b1101010100, 1: 0b0010101011, 2: 0b0101010100, 3: 0b1010101011}


def tmds_encode_stream(symbols):
    """Bit-exact model of tmds_encoder.v over a (de, data, ctrl) symbol stream.

    symbols: list of (de, data_in, ctrl_in). Returns (outputs, disparities).
    outputs[i] is the registered tmds_out sampled after symbol i (with the
    RTL's one-cycle latency: initial output is 0, disparity starts at 0).
    """
    disparity = 0
    out = 0
    outputs, disps = [], []
    for de, data, ctrl in symbols:
        if not de:
            disparity = 0
            out = CTRL_CODES[ctrl & 3]
        else:
            ones = bin(data & 0xFF).count("1")
            use_xnor = (ones > 4) or (ones == 4 and (data & 1) == 0)
            qm = [0] * 9
            qm[0] = (data >> 0) & 1
            for i in range(1, 8):
                b = (data >> i) & 1
                qm[i] = (~(qm[i - 1] ^ b)) & 1 if use_xnor else (qm[i - 1] ^ b)
            qm[8] = 0 if use_xnor else 1
            ones_qm = sum(qm[:8])
            diff = ones_qm - (8 - ones_qm)
            if disparity == 0 or ones_qm == 4:
                bit9 = (~qm[8]) & 1
                low = qm[:8] if qm[8] else [b ^ 1 for b in qm[:8]]
                disparity = disparity - diff if qm[8] == 0 else disparity + diff
            elif (disparity > 0 and ones_qm > 4) or (disparity < 0 and ones_qm < 4):
                bit9 = 1
                low = [b ^ 1 for b in qm[:8]]
                disparity = disparity + ((qm[8] << 1)) - diff
            else:
                bit9 = 0
                low = qm[:8]
                disparity = disparity - ((1 - qm[8]) << 1) + diff
            out = (bit9 << 9) | (qm[8] << 8) | sum(b << i for i, b in enumerate(low))
        outputs.append(out)
        disps.append(disparity)
    return outputs, disps
