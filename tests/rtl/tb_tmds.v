`timescale 1ns / 1ps

// TMDS dump TB: exercises tmds_encoder.v with isolated + streaming vectors.
// Python side cross-checks every output bit against the golden model.
module tb_tmds;
    reg clk;
    reg rst_n;
    reg [7:0] data_in;
    reg [1:0] ctrl_in;
    reg de;
    wire [9:0] tmds_out;

    tmds_encoder uut (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .ctrl_in(ctrl_in),
        .de(de),
        .tmds_out(tmds_out)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    integer d, c;

    // NOTE: stimulus is driven on negedge so DUT posedge sampling never races
    // the testbench (blocking assignments on posedge would be nondeterministic).
    initial begin
        rst_n = 0; de = 0; data_in = 0; ctrl_in = 0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Isolated data vectors: blank (disparity reset) then one data symbol
        for (d = 0; d < 256; d = d + 1) begin
            @(negedge clk);
            de = 0; ctrl_in = 0;
            @(posedge clk);
            @(negedge clk);
            de = 1; data_in = d[7:0];
            @(posedge clk);
            #1;
            $display("TMDS_DATA %0d %b", d, tmds_out);
        end

        // Control words
        for (c = 0; c < 4; c = c + 1) begin
            @(negedge clk);
            de = 0; ctrl_in = c[1:0];
            @(posedge clk);
            #1;
            $display("TMDS_CTRL %0d %b", c, tmds_out);
        end

        // Streaming: 256 data symbols back-to-back (running disparity evolves)
        @(negedge clk);
        de = 0;
        @(posedge clk);
        for (d = 0; d < 256; d = d + 1) begin
            @(negedge clk);
            de = 1; data_in = d[7:0];
            @(posedge clk);
            #1;
            $display("TMDS_STREAM %0d %b", d, tmds_out);
        end

        $display("[SIM] TMDS dump complete");
        $finish;
    end

    initial begin
        #1000000;
        $display("[SIM TIMEOUT]");
        $finish;
    end
endmodule
