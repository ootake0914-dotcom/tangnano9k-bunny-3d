TOOLCHAIN_PATH ?= /home/yuhki/oss-cad-suite/bin
export PATH := $(TOOLCHAIN_PATH):$(PATH)

TOP = bunny_bram_top
DEVICE = GW1NR-LV9QN88PC6/I5
FAMILY = GW1N-9C
CST = tangnano9k_hdmi.cst

SRCS = bunny_bram_top.v tmds_encoder.v gowin_rpll_hdmi.v gowin_clkdiv.v
SEED ?= 3  # seed3: clean PLL lock + zero clk_126 routing warnings

all: bunny_bram.fs

bunny_bram.json: $(SRCS) bunny_tables.vh vert_mem.hex edge_mem.hex
	yosys -p "read_verilog -I. $(SRCS); synth_gowin -nodsp -top $(TOP) -json bunny_bram.json"

bunny_bram_pnr.json: bunny_bram.json $(CST)
	nextpnr-himbaechel --json bunny_bram.json --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=$(CST) --freq 30 --timing-allow-fail --seed $(SEED) --write bunny_bram_pnr.json

bunny_bram.fs: bunny_bram_pnr.json
	PYTHONBREAKPOINT=0 gowin_pack -d $(FAMILY) -o bunny_bram.fs bunny_bram_pnr.json

flash: flash-flash

flash-flash: bunny_bram.fs
	openFPGALoader -b tangnano9k -f bunny_bram.fs

flash-sram: bunny_bram.fs
	openFPGALoader -b tangnano9k -m bunny_bram.fs

test:
	python3 tests/run_all.py

clean:
	rm -f *.json *.fs *.vvp *.vcd *.ppm

.PHONY: all flash flash-flash flash-sram test clean
