`timescale 1ns / 1ps

// Framebuffer dump TB for bunny_bram_top.v: runs 1 full rasterized frame
// and writes the back buffer to /tmp/bunny_sim_frame.ppm for pixel analysis.
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
        wait(uut.rst_n == 1'b1);
        $display("[SIM] Reset released at %0t ns", $time);

        @(negedge uut.clk_pixel);
        uut.h_cnt = 10'd799;
        uut.v_cnt = 10'd479;

        @(posedge uut.clk_pixel);
        $display("[SIM] frame_start at %0t ns! r_state=%d, back_buf=%d",
                 $time, uut.r_state, uut.back_buf);

        wait(uut.draw_frame_done == 1'b1);
        $display("[SIM] Frame drawing completed at %0t ns!", $time);

        f = $fopen("/tmp/bunny_sim_frame.ppm", "w");
        if (f == 0) begin
            $display("[SIM ERROR] Failed to open /tmp/bunny_sim_frame.ppm");
            $finish;
        end
        $fwrite(f, "P3\n160 120\n255\n");

        for (y = 0; y < 120; y = y + 1) begin
            for (x = 0; x < 160; x = x + 1) begin
                pval = uut.fb_mem[(uut.back_buf ? 19200 : 0) + y * 160 + x];
                case (pval)
                    4'd0: color_rgb = 24'h1C2850;
                    4'd1: color_rgb = 24'hFF3399;
                    4'd2: color_rgb = 24'hFFF0C0;
                    4'd3: color_rgb = 24'h00E5FF;
                    4'd4: color_rgb = 24'hFFA000;
                    4'd5: color_rgb = 24'h781446;
                    4'd6: color_rgb = 24'h786E50;
                    4'd7: color_rgb = 24'h00506E;
                    4'd8: color_rgb = 24'h6E4100;
                    default: color_rgb = 24'hFFFFFF;
                endcase
                $fwrite(f, "%d %d %d\n", color_rgb[23:16], color_rgb[15:8], color_rgb[7:0]);
            end
        end

        $fclose(f);
        $display("[SIM] Successfully wrote /tmp/bunny_sim_frame.ppm!");
        $finish;
    end

    initial begin
        #5000000;
        $display("[SIM TIMEOUT] r_state=%d, edge_idx=%d", uut.r_state, uut.edge_idx);
        $finish;
    end

endmodule
