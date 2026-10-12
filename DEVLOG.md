# Tang Nano 9K: BRAM Stanford Bunny Engine - Development Log

## 2026-10-12: 128v/377e -> 256v/700e Mesh Upgrade (PSRAM-free)

- `tools/gen_mesh.py 256 700` regenerated `vert_mem.hex` (256), `edge_mem.hex`
  (700, isolated=[]), `bunny_tables.vh` (`rg_rom` 256 entries), regions
  `{ears:14, head:101, body:83, feet:58}`, worst edge 11.2px.
- Test goldens copied to `tests/testdata/`; `test_bunny_tables.py`
  (`NUM_VERTS`/`NUM_EDGES`) updated.
- `bunny_bram_top.v`: `NUM_VERTS/EDGES`, ROM depths (`vert_mem[0:255]`,
  `edge_mem[0:1023]`, `vert_data_*[0:255]`), `vd_waddr/vd0_raddr/vd1_raddr`
  7->8 bit. (`vert_idx` 8bit / `edge_idx` 10bit already sufficient.)
- Regression: 7/7 PASSED (incl. full-frame RTL sim).
- Build OK, flashed `-f` (CRC Success) + loaded `-m`. HDMI shows denser bunny.

## Headroom Analysis: How Far Can BRAM Go? (measured 256v/700e build)

- Current utilization: BSRAM 14/26 (DP 12 + SP 2), LUT ~3029/8640 (~35%),
  DFF ~480/6480 (~7%).
- Framebuffer is a fixed 10 BSRAM (160x120x4bit double-buffered); mesh uses ~4.
- Estimates:
  - 512 verts / ~1400 edges -> BSRAM ~15-16, LUT ~40%. Fits comfortably.
    (Needs: ROM depths 512/2048, `vert_idx`/vd-addrs 9bit, `edge_idx` 11bit,
    `gen_mesh.py 512 <EMAX>`, test constants in sync.)
  - 1024 verts / ~2800 edges -> BSRAM ~20, LUT ~50%. Probably fits.
    (Needs: same treatment one bit wider; `vert_mem` 1024x36 = 2 blocks,
    `edge_mem` 4096x16 = 4 blocks.)
  - Practical ceiling ~1024-1500 verts: source mesh is 2503 verts (decimation
    loses meaning near it) and BSRAM runs out past ~20 blocks.
- Non-resource limits: frame time scales ~linearly (256v/700e ~= a few ms vs
  16.6ms budget, so 60fps holds to ~3000 edges); visual saturation at
  160x120 (700 edges already cover ~half the pixels; 1400+ may look muddy —
  verify on screen).
- Decision (2026-10-12): stay at 256v/700e for now; upscale only if the picture
  asks for it.
