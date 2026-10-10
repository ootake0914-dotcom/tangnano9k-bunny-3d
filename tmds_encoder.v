// DVI / HDMI 8b/10b TMDS Encoder (Standard DVI 1.0 Specification)
module tmds_encoder (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data_in,
    input  wire [1:0] ctrl_in,
    input  wire       de,
    output reg  [9:0] tmds_out
);

    wire [3:0] ones_cnt = data_in[0] + data_in[1] + data_in[2] + data_in[3] +
                          data_in[4] + data_in[5] + data_in[6] + data_in[7];
    wire use_xnor = (ones_cnt > 4'd4) || (ones_cnt == 4'd4 && data_in[0] == 1'b0);

    wire [8:0] q_m;
    assign q_m[0] = data_in[0];
    assign q_m[1] = use_xnor ? ~(q_m[0] ^ data_in[1]) : (q_m[0] ^ data_in[1]);
    assign q_m[2] = use_xnor ? ~(q_m[1] ^ data_in[2]) : (q_m[1] ^ data_in[2]);
    assign q_m[3] = use_xnor ? ~(q_m[2] ^ data_in[3]) : (q_m[2] ^ data_in[3]);
    assign q_m[4] = use_xnor ? ~(q_m[3] ^ data_in[4]) : (q_m[3] ^ data_in[4]);
    assign q_m[5] = use_xnor ? ~(q_m[4] ^ data_in[5]) : (q_m[4] ^ data_in[5]);
    assign q_m[6] = use_xnor ? ~(q_m[5] ^ data_in[6]) : (q_m[5] ^ data_in[6]);
    assign q_m[7] = use_xnor ? ~(q_m[6] ^ data_in[7]) : (q_m[6] ^ data_in[7]);
    assign q_m[8] = ~use_xnor;

    wire signed [4:0] ones_qm = q_m[0] + q_m[1] + q_m[2] + q_m[3] +
                                q_m[4] + q_m[5] + q_m[6] + q_m[7];
    wire signed [4:0] zeros_qm = 5'sd8 - ones_qm;
    wire signed [4:0] diff_qm  = ones_qm - zeros_qm;

    reg signed [4:0] disparity;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            disparity <= 5'sd0;
            tmds_out  <= 10'd0;
        end else begin
            if (!de) begin
                disparity <= 5'sd0;
                case (ctrl_in)
                    2'b00:   tmds_out <= 10'b1101010100;
                    2'b01:   tmds_out <= 10'b0010101011;
                    2'b10:   tmds_out <= 10'b0101010100;
                    default: tmds_out <= 10'b1010101011;
                endcase
            end else begin
                if (disparity == 5'sd0 || ones_qm == 4'sd4) begin
                    tmds_out[9]   <= ~q_m[8];
                    tmds_out[8]   <=  q_m[8];
                    tmds_out[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];
                    if (q_m[8] == 1'b0)
                        disparity <= disparity - diff_qm;
                    else
                        disparity <= disparity + diff_qm;
                end else if ((disparity > 0 && ones_qm > 4) || (disparity < 0 && ones_qm < 4)) begin
                    tmds_out[9]   <= 1'b1;
                    tmds_out[8]   <= q_m[8];
                    tmds_out[7:0] <= ~q_m[7:0];
                    disparity     <= disparity + {q_m[8], 1'b0} - diff_qm;
                end else begin
                    tmds_out[9]   <= 1'b0;
                    tmds_out[8]   <= q_m[8];
                    tmds_out[7:0] <= q_m[7:0];
                    disparity     <= disparity - {~q_m[8], 1'b0} + diff_qm;
                end
            end
        end
    end

endmodule
