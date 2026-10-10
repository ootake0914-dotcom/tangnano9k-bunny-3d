`timescale 1ns / 1ps
// Simulation stubs for Gowin primitives (full rPLL parameter set for defparam)
module rPLL #(
    parameter FCLKIN = "27",
    parameter DYN_IDIV_SEL = "false",
    parameter IDIV_SEL = 2,
    parameter FBDIV_SEL = 13,
    parameter ODIV_SEL = 4,
    parameter DYN_FBDIV_SEL = "false",
    parameter DYN_ODIV_SEL = "false",
    parameter PSDA_SEL = "0000",
    parameter DYN_DA_EN = "false",
    parameter DUTYDA_SEL = "1000",
    parameter CLKOUT_FT_DIR = 1'b1,
    parameter CLKOUTP_FT_DIR = 1'b1,
    parameter CLKOUT_DLY_STEP = 0,
    parameter CLKOUTP_DLY_STEP = 0,
    parameter CLKFB_SEL = "internal",
    parameter CLKOUT_BYPASS = "false",
    parameter CLKOUTP_BYPASS = "false",
    parameter CLKOUTD_BYPASS = "false",
    parameter DYN_SDIV_SEL = 2,
    parameter CLKOUTD_SRC = "CLKOUT",
    parameter CLKOUTD3_SRC = "CLKOUT",
    parameter DEVICE = "GW1NR-9C"
)(
    output reg  CLKOUT,
    output reg  LOCK,
    output wire CLKOUTP,
    output wire CLKOUTD,
    output wire CLKOUTD3,
    input  wire RESET,
    input  wire RESET_P,
    input  wire CLKIN,
    input  wire CLKFB,
    input  wire [5:0] FBDSEL,
    input  wire [5:0] IDSEL,
    input  wire [5:0] ODSEL,
    input  wire [3:0] PSDA,
    input  wire [3:0] DUTYDA,
    input  wire [3:0] FDLY
);
    assign CLKOUTP = 1'b0;
    assign CLKOUTD = 1'b0;
    assign CLKOUTD3 = 1'b0;
    initial begin
        CLKOUT = 0;
        LOCK = 0;
        #100;
        LOCK = 1;
    end
    // 126 MHz (period = 7.9365ns)
    always #3.968 CLKOUT = ~CLKOUT;
endmodule

module BUFG (
    input  wire I,
    output wire O
);
    assign O = I;
endmodule

// Behavioral Gowin CLKDIV (/5 only, matching DIV_MODE="5" use)
module CLKDIV (
    output reg  CLKOUT,
    input  wire HCLKIN,
    input  wire RESETN,
    input  wire CALIB
);
    parameter DIV_MODE = "5";
    parameter GSREN = "false";
    reg [2:0] cnt;
    initial begin CLKOUT = 0; cnt = 0; end
    always @(posedge HCLKIN or negedge RESETN) begin
        if (!RESETN) begin CLKOUT <= 0; cnt <= 0; end
        else begin
            cnt <= (cnt == 3'd4) ? 3'd0 : cnt + 1'b1;
            CLKOUT <= (cnt == 3'd0 || cnt == 3'd1);
        end
    end
endmodule

// Behavioral OSER10: 10:1 DDR, D0-first.
module OSER10 (
    output reg Q,
    input D0, D1, D2, D3, D4, D5, D6, D7, D8, D9,
    input PCLK, FCLK, RESET
);
    parameter GSREN = "false";
    parameter LSREN = "true";
    reg [9:0] sr; reg [3:0] n; reg pclk_q;
    always @(posedge FCLK or negedge FCLK or posedge RESET) begin
        if (RESET) begin Q <= 0; sr <= 0; n <= 0; pclk_q <= 0; end
        else begin
            if (PCLK && !pclk_q) begin
                sr <= {D9,D8,D7,D6,D5,D4,D3,D2,D1,D0};
                Q <= D0; n <= 1;
            end else begin
                Q <= sr[n]; n <= (n == 9) ? 0 : n + 1;
            end
            pclk_q <= PCLK;
        end
    end
endmodule

module ELVDS_OBUF (input I, output O, OB);
    assign O = I;
    assign OB = ~I;
endmodule

// Behavioral Gowin MULT18X18 (combinational signed multiply, CLK=0 mode)
module MULT18X18 (
    output [35:0] DOUT,
    input [17:0] A, B, SIA, SIB,
    input ASEL, ASIGN, BSEL, BSIGN, CE, CLK, RESET
);
    wire signed [17:0] sa = ASIGN ? $signed(A) : $signed({1'b0, A[16:0]});
    wire signed [17:0] sb = BSIGN ? $signed(B) : $signed({1'b0, B[16:0]});
    assign DOUT = sa * sb;
endmodule
