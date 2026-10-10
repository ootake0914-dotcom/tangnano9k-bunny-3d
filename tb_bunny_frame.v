`timescale 1ns / 1ps

// =============================================================================
// Stanford Bunny RTL Framebuffer Verification Testbench
// Simulates bunny_bram_top.v, runs 1 full frame rasterization,
// and dumps the simulated BRAM framebuffer to a PPM image.
// =============================================================================

module rPLL #(
    parameter FCLKIN = "27",
    parameter IDIV_SEL = 2,
    parameter FBDIV_SEL = 13,
    parameter ODIV_SEL = 4,
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

module tb_bunny_frame;
    reg clk_27;
    wire [5:0] led;
    wire tmds_clk_p, tmds_clk_n;
    wire [2:0] tmds_d_p, tmds_d_n;

    bunny_bram_top uut (
        .clk(clk_27),
        .led(led),
        .tmds_clk_p(tmds_clk_p),
        .tmds_clk_n(tmds_clk_n),
        .tmds_d_p(tmds_d_p),
        .tmds_d_n(tmds_d_n)
    );

    initial begin
        clk_27 = 0;
        forever #18.518 clk_27 = ~clk_27;
    end

    integer f, x, y, pval;
    reg [23:0] color_rgb;

    initial begin
        $display("[SIM] Starting Stanford Bunny RTL Simulation...");
        // Wait for reset release
        wait(uut.rst_n == 1'b1);
        $display("[SIM] Reset released at %0t ns", $time);

        // Fast-forward video counter to just before line 480 VBlank
        @(posedge uut.clk_pixel);
        uut.h_cnt = 10'd799;
        uut.v_cnt = 10'd479;

        // Wait for frame_start trigger
        @(posedge uut.clk_pixel);
        $display("[SIM] frame_start triggered at %0t ns! r_state=%d, back_buf=%d", $time, uut.r_state, uut.back_buf);

        // Wait until rasterizer finishes the frame
        wait(uut.draw_frame_done == 1'b1);
        $display("[SIM] Frame drawing completed at %0t ns! Verifying framebuffer...", $time);

        // Dump back buffer to PPM image
        f = $fopen("/tmp/bunny_sim_frame.ppm", "w");
        if (f == 0) begin
            $display("[SIM ERROR] Failed to open /tmp/bunny_sim_frame.ppm");
            $finish;
        end

        // PPM Header: 160x120 24-bit color
        $fwrite(f, "P3\n160 120\n255\n");

        for (y = 0; y < 120; y = y + 1) begin
            for (x = 0; x < 160; x = x + 1) begin
                pval = uut.fb_mem[(uut.back_buf ? 19200 : 0) + y * 160 + x];
                case (pval)
                    4'd0: color_rgb = 24'h1C2850; // Deep Sapphire Blue Backdrop
                    4'd1: color_rgb = 24'hFF3399; // Neon Pink (Front Ears)
                    4'd2: color_rgb = 24'hFFF0C0; // Golden Cream (Front Head)
                    4'd3: color_rgb = 24'h00E5FF; // Bright Cyan (Front Body)
                    4'd4: color_rgb = 24'hFFA000; // Vibrant Amber (Front Feet)
                    4'd5: color_rgb = 24'h781446; // Deep Magenta (Back Ears)
                    4'd6: color_rgb = 24'h786E50; // Dim Sand (Back Head)
                    4'd7: color_rgb = 24'h00506E; // Dark Cyan (Back Body)
                    4'd8: color_rgb = 24'h6E4100; // Dark Bronze (Back Feet)
                    default: color_rgb = 24'hFFFFFF;
                endcase
                $fwrite(f, "%d %d %d\n", color_rgb[23:16], color_rgb[15:8], color_rgb[7:0]);
            end
        end

        $fclose(f);
        $display("[SIM] Successfully wrote /tmp/bunny_sim_frame.ppm!");
        $finish;
    end

    // Safety watchdog: 5ms simulation time
    initial begin
        #5000000;
        $display("[SIM TIMEOUT] Simulation exceeded 5ms! Current r_state=%d, edge_idx=%d", uut.r_state, uut.edge_idx);
        $finish;
    end

endmodule
