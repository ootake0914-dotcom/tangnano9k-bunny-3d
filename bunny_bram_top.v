// =============================================================================
// Top-Level Module: Stanford Bunny 3D Wireframe on Tang Nano 9K
// ZERO-PSRAM On-Chip Dual-Port BRAM Double-Buffered Framebuffer Architecture
// Displays all 152 edges across 56 vertices with 3D Depth Shading & Anamorphic Correction:
// - Front Edges: Neon Pink Ears, Golden Cream Head, Bright Cyan Body, Vibrant Amber Feet
// - Back Edges: Deep Magenta Ears, Dim Sand Head, Dark Cyan Body, Dark Bronze Feet
// - 18-degree Fixed Downward Pitch Tilt for natural viewing angle
// - Anamorphic Aspect Correction (4:3 -> 16:9) to prevent widescreen distortion
// - Deep Sapphire Blue Backdrop (#1C2850) with 2-pixel Crisp White Border (#FFFFFF)
// Internal resolution: 160x120 4-bit, upscaled 4x to 640x480 @ 60Hz over HDMI
// =============================================================================

module bunny_bram_top (
    input  wire        clk,        // 27MHz Onboard Crystal (Pin 52)
    output wire [5:0]  led,        // Onboard LEDs (Pins 10, 11, 13, 14, 15, 16)

    // HDMI Direct-Drive Differential Pairs (LVCMOS33 Complementary)
    output wire        tmds_clk_p, // Pin 69
    output wire        tmds_clk_n, // Pin 68
    output wire [2:0]  tmds_d_p,   // Pins 71 (B), 73 (G), 75 (R)
    output wire [2:0]  tmds_d_n    // Pins 70 (B), 72 (G), 74 (R)
);

    `include "bunny_tables.vh"

    // =========================================================================
    // 1. Clock Generation via Gowin rPLL Primitive
    // 27MHz -> 126.0MHz (5x TMDS Serializer Clock)
    // Synchronous Divide-by-5 -> 25.200MHz (Pixel Clock for 640x480 @ 60Hz)
    // =========================================================================
    // Clocking (Sipeed-proven): rPLL 27->126MHz + CLKDIV /5 -> 25.2MHz.
    // The fabric div-by-5 + BUFG variant does NOT display (OSER10 PCLK fault).
    wire clk_126;
    wire pll_lock;
    wire clk_pixel;

    Gowin_rPLL_hdmi pll_inst (
        .clkout(clk_126),
        .lock(pll_lock),
        .clkin(clk)
    );

    Gowin_CLKDIV div5_inst (
        .clkout(clk_pixel),
        .hclkin(clk_126),
        .resetn(pll_lock)
    );

    // One-shot Power-on Reset on clk_126 with lock debouncing
    // Requires ~520us (65,536 cycles) of continuous PLL lock before releasing reset.
    // Latches HIGH permanently; completely immune to power ripple & transient lock dips!
    reg [15:0] por_cnt = 16'd0;
    reg rst_n = 1'b0;

    always @(posedge clk_126) begin
        if (pll_lock && por_cnt != 16'hFFFF) begin
            por_cnt <= por_cnt + 1'b1;
            rst_n   <= 1'b0;
        end else if (por_cnt == 16'hFFFF) begin
            rst_n   <= 1'b1;
        end
    end

    // =========================================================================
    // 2. Dual-Port Block RAM Framebuffer (38,400 x 4-bit)
    // Buffer 0: entries 0..19199 (addr[15] = 0)
    // Buffer 1: entries 19200..38399 (addr[15] = 1)
    // Infers 10 Gowin DPB (Dual-Port BSRAM) blocks seamlessly
    // =========================================================================
    reg [3:0] fb_mem [0:38399];

    // Port A: Rasterizer Write
    reg         fb_we_a;
    reg  [15:0] fb_addr_a;
    reg  [3:0]  fb_din_a;

    always @(posedge clk_pixel) begin
        if (fb_we_a)
            fb_mem[fb_addr_a] <= fb_din_a;
    end

    // Port B: Video Scanout Read
    wire [15:0] fb_addr_b;
    reg  [3:0]  fb_dout_b;

    always @(posedge clk_pixel) begin
        fb_dout_b <= fb_mem[fb_addr_b];
    end

    // =========================================================================
    // 3. 640x480 @ 60Hz Video Timing Generator
    // =========================================================================
    localparam H_ACTIVE = 640;
    localparam H_FRONT  = 16;
    localparam H_SYNC   = 96;
    localparam H_BACK   = 48;
    localparam H_TOTAL  = 800;

    localparam V_ACTIVE = 480;
    localparam V_FRONT  = 10;
    localparam V_SYNC   = 2;
    localparam V_BACK   = 33;
    localparam V_TOTAL  = 525;

    reg [9:0] h_cnt = 10'd0;
    reg [9:0] v_cnt = 10'd0;

    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
        end else if (h_cnt == H_TOTAL - 1) begin
            h_cnt <= 10'd0;
            if (v_cnt == V_TOTAL - 1)
                v_cnt <= 10'd0;
            else
                v_cnt <= v_cnt + 1'b1;
        end else begin
            h_cnt <= h_cnt + 1'b1;
        end
    end

    // Frame synchronization pulse at line 480 (start of VBlank)
    wire frame_start = (h_cnt == 10'd0 && v_cnt == 10'd480);

    // Buffer selection
    reg front_buf = 1'b0;
    reg back_buf  = 1'b1;

    // Viewport coordinate mapping: 640x480 downscaled 4x to 160x120
    wire [7:0] px = h_cnt[9:2]; // 0..159
    wire [6:0] py = v_cnt[8:2]; // 0..119

    // Word address: py * 160 + px = (py << 7) + (py << 5) + px
    wire [14:0] scanout_offset = {py, 7'd0} + {py, 5'd0} + {7'd0, px};
    assign fb_addr_b = (front_buf ? 16'd19200 : 16'd0) + scanout_offset;

    // Raw video control signals (positive polarity)
    wire raw_hsync  = (h_cnt >= (H_ACTIVE + H_FRONT)) && (h_cnt < (H_ACTIVE + H_FRONT + H_SYNC));
    wire raw_vsync  = (v_cnt >= (V_ACTIVE + V_FRONT)) && (v_cnt < (V_ACTIVE + V_FRONT + V_SYNC));
    wire raw_de     = (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE);
    wire raw_border = (h_cnt < 2 || h_cnt >= 638 || v_cnt < 2 || v_cnt >= 478);

    // 2-cycle pipeline to match BRAM read latency + Palette lookup
    reg hs_q1, hs_q2;
    reg vs_q1, vs_q2;
    reg de_q1, de_q2;
    reg border_q1, border_q2;
    reg [7:0] rgb_r;
    reg [7:0] rgb_g;
    reg [7:0] rgb_b;

    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            hs_q1     <= 1'b0; hs_q2     <= 1'b0;
            vs_q1     <= 1'b0; vs_q2     <= 1'b0;
            de_q1     <= 1'b0; de_q2     <= 1'b0;
            border_q1 <= 1'b0; border_q2 <= 1'b0;
            rgb_r     <= 8'd0;
            rgb_g     <= 8'd0;
            rgb_b     <= 8'd0;
        end else begin
            hs_q1     <= raw_hsync;
            hs_q2     <= hs_q1;
            vs_q1     <= raw_vsync;
            vs_q2     <= vs_q1;
            de_q1     <= raw_de;
            de_q2     <= de_q1;
            border_q1 <= raw_border;
            border_q2 <= border_q1;

            if (de_q1) begin
                if (border_q1) begin
                    rgb_r <= 8'hff;
                    rgb_g <= 8'hff;
                    rgb_b <= 8'hff;
                end else begin
                    case (fb_dout_b)
                        4'd0: begin // Deep Sapphire Blue Backdrop (#1C2850)
                            rgb_r <= 8'h1c; rgb_g <= 8'h28; rgb_b <= 8'h50;
                        end
                        // --- FRONT EDGES (Bright Neon) ---
                        4'd1: begin // Neon Pink (Front Ears: #FF3399)
                            rgb_r <= 8'hff; rgb_g <= 8'h33; rgb_b <= 8'h99;
                        end
                        4'd2: begin // Golden Cream (Front Head: #FFF0C0)
                            rgb_r <= 8'hff; rgb_g <= 8'hf0; rgb_b <= 8'hc0;
                        end
                        4'd3: begin // Bright Cyan (Front Body: #00E5FF)
                            rgb_r <= 8'h00; rgb_g <= 8'he5; rgb_b <= 8'hff;
                        end
                        4'd4: begin // Vibrant Amber (Front Feet: #FFA000)
                            rgb_r <= 8'hff; rgb_g <= 8'ha0; rgb_b <= 8'h00;
                        end
                        // --- BACK EDGES (Clearly visible 3D volume shading) ---
                        4'd5: begin // Rich Magenta (Back Ears: #D02080)
                            rgb_r <= 8'hd0; rgb_g <= 8'h20; rgb_b <= 8'h80;
                        end
                        4'd6: begin // Warm Sand Gold (Back Head: #D0B870)
                            rgb_r <= 8'hd0; rgb_g <= 8'hb8; rgb_b <= 8'h70;
                        end
                        4'd7: begin // Medium Cyan (Back Body: #0090C0)
                            rgb_r <= 8'h00; rgb_g <= 8'h90; rgb_b <= 8'hc0;
                        end
                        4'd8: begin // Rich Amber Copper (Back Feet: #C06000)
                            rgb_r <= 8'hc0; rgb_g <= 8'h60; rgb_b <= 8'h00;
                        end
                        default: begin // Bright White Fallback
                            rgb_r <= 8'hff; rgb_g <= 8'hff; rgb_b <= 8'hff;
                        end
                    endcase
                end
            end else begin
                rgb_r <= 8'd0;
                rgb_g <= 8'd0;
                rgb_b <= 8'd0;
            end
        end
    end

    // =========================================================================
    // 4. 3D Bresenham Rasterizer with Painter's Depth Sorting
    // Pass 0 renders Back Edges (dim), Pass 1 renders Front Edges (bright) on top
    // Total execution time: ~0.80ms at 25.2MHz (far below 16.6ms frame limit)
    // =========================================================================
    localparam S_IDLE       = 3'd0;
    localparam S_CLEAR      = 3'd1;
    localparam S_ROT_STAGE1 = 3'd2;
    localparam S_ROT_STAGE2 = 3'd3;
    localparam S_ROT_FETCH  = 3'd7;
    localparam S_LOAD_EDGE  = 3'd4;
    localparam S_SETUP_EDGE = 3'd5;
    localparam S_DRAW_PIXEL = 3'd6;
    // DSP settle states: tolerate 0/1/2-cycle MULT latency.
    // Harmless in all cases (+112 cyc/frame).
    localparam S_ROT_HOLD   = 4'd8;
    localparam S_ROT_HOLD2  = 4'd9;
    // BSRAM wait states: vert/edge ROMs are sync-read (1-cycle lag).
    localparam S_ROT_FETCH2 = 4'd10;
    localparam S_LOAD_EDGE2 = 4'd11;
    localparam S_LOAD_EDGE3 = 4'd12;

    reg [3:0]  r_state;
    reg [7:0]  yaw;
    reg [14:0] clear_cnt;
    reg [7:0]  vert_idx;
    reg [9:0]  edge_idx; // 700 edges
    reg        pass; // 0 = back edges, 1 = front edges
    reg        draw_frame_done;

    // Mesh sizes (regenerate via tools/gen_mesh.py; keep tests in sync)
    localparam NUM_VERTS = 256;
    localparam NUM_EDGES = 700;

    // Transformed 2D screen coordinates: duplicated BSRAM arrays
    // ({sx[7:0], sy[6:0], z}) to allow single-cycle concurrent read of endpoints v0 and v1.
    // Infers 2 simple BSRAM blocks (SPX9/DPB) and completely eliminates wide 256:1 LUT MUXes.
    reg [15:0] vert_data_0 [0:255];
    reg [15:0] vert_data_1 [0:255];
    reg        vd_we;
    reg [7:0]  vd_waddr;
    reg [15:0] vd_wdata;
    reg [7:0]  vd0_raddr;
    reg [7:0]  vd1_raddr;
    reg [15:0] vd0_q;
    reg [15:0] vd1_q;

    always @(posedge clk_pixel) begin
        if (vd_we) begin
            vert_data_0[vd_waddr] <= vd_wdata;
            vert_data_1[vd_waddr] <= vd_wdata;
        end
    end
    always @(posedge clk_pixel) begin
        vd0_q <= vert_data_0[vd0_raddr];
        vd1_q <= vert_data_1[vd1_raddr];
    end

    // Pipeline registers for 3D rotation
    // FETCH stage: latch vertex ROM coords (breaks ROM MUX from mult path)
    reg signed [11:0] reg_vx;
    reg signed [11:0] reg_vy;
    reg signed [11:0] reg_vz;
    // Yaw sin/cos latched once per frame (yaw is frame-constant).
    // CRITICAL: both mult operands must be REGISTERS. Yosys mis-maps
    // MULT18X18 when an operand is LUT-driven (A-side disconnected,
    // sin/cos cone swept as dead logic -> rotation garbage on HW).
    // REGxREG maps exactly like the proven dsp_probe design.
    reg signed [12:0] cos_r;
    reg signed [12:0] sin_r;
    reg signed [12:0] r_xrot;
    reg signed [12:0] r_zrot;
    reg signed [11:0] r_yrot;

    // Vertex/edge ROMs in BSRAM (sync read, hex init). Keeps wide MUX
    // trees out of LUTs (~5k LUTs saved at 256v/700e).
    reg [35:0] vert_mem [0:255];
    reg [15:0] edge_mem [0:1023];
    initial begin
        $readmemh("vert_mem.hex", vert_mem);
        $readmemh("edge_mem.hex", edge_mem);
    end
    reg [35:0] vmem_q;
    reg [15:0] emem_q;
    always @(posedge clk_pixel) begin
        vmem_q <= vert_mem[vert_idx];
        emem_q <= edge_mem[edge_idx];
    end

    // Bresenham line registers
    reg [7:0] bx, b_x1;
    reg [6:0] by, b_y1;
    reg signed [10:0] bdx;
    reg signed [10:0] bdy;
    reg step_x_dir; // 0: increment (+1), 1: decrement (-1)
    reg step_y_dir; // 0: increment (+1), 1: decrement (-1)
    reg signed [11:0] berr;
    reg [3:0] cur_color;
    reg [8:0] watchdog;

    // -------------------------------------------------------------------------
    // 3D Math Pipeline: Yaw Rotation + 18-deg Fixed Pitch Tilt + Anamorphic Scale
    // -------------------------------------------------------------------------
    // Vertex coords from BSRAM (1-cycle lag vs vert_idx; FETCH2 absorbs it)
    wire signed [11:0] vx = $signed(vmem_q[35:24]);
    wire signed [11:0] vy = $signed(vmem_q[23:12]);
    wire signed [11:0] vz = $signed(vmem_q[11:0]);

    // Quarter-sine lookup for Yaw rotation
    wire [1:0] sq = yaw[7:6];
    wire [4:0] six = yaw[5:1];
    wire [4:0] six_m = (sq == 2'd0 || sq == 2'd2) ? six : (5'd31 - six);
    wire signed [12:0] sin_mag = $signed({1'b0, sin_q(six_m)});
    wire signed [12:0] sin_val = (sq == 2'd2 || sq == 2'd3) ? -sin_mag : sin_mag;

    wire [7:0] yaw_c = yaw + 8'd64;
    wire [1:0] cq = yaw_c[7:6];
    wire [4:0] cix = yaw_c[5:1];
    wire [4:0] cix_m = (cq == 2'd0 || cq == 2'd2) ? cix : (5'd31 - cix);
    wire signed [12:0] cos_mag = $signed({1'b0, sin_q(cix_m)});
    wire signed [12:0] cos_val = (cq == 2'd2 || cq == 2'd3) ? -cos_mag : cos_mag;

    // Stage 1 Multipliers: Yaw rotation in X-Z plane
    // Inferred (*) + synth -nodsp (LUT math). DO NOT use MULT18X18 cells
    // (explicit or inferred): Yosys/nextpnr split them into MULT9X9 aux
    // cells with broken sign handling -> rotation garbage on HW.
    wire signed [24:0] prod_xc = reg_vx * cos_r;
    wire signed [24:0] prod_zs = reg_vz * sin_r;
    wire signed [24:0] prod_zc = reg_vz * cos_r;
    wire signed [24:0] prod_xs = reg_vx * sin_r;

    // Stage 2: projection via shift-add (exact: 128-16-4=108, 128+16=144).
    // LUT math (no DSP anywhere: -nodsp); BSRAM holds the tables instead.
    wire signed [21:0] r_xrot_x = r_xrot;
    wire signed [21:0] r_yrot_x = r_yrot;
    wire signed [21:0] prod_sx = (r_xrot_x <<< 7) - (r_xrot_x <<< 4) - (r_xrot_x <<< 2);
    wire signed [21:0] prod_sy = (r_yrot_x <<< 7) + (r_yrot_x <<< 4);

    // Viewport projection: 160x120 screen, perfectly centered at (80, 60)
    wire signed [9:0] sx_proj = 10'sd80 + (prod_sx >>> 12);
    wire signed [9:0] sy_proj = 10'sd60 - (prod_sy >>> 12);

    // Clamp projection to framebuffer bounds sx:[0,159], sy:[0,119].
    // Without this, a negative glitch (e.g. sx=-1) sliced as [7:0] becomes
    // 255 and wraps pixel_offset into the next raster row (tearing).
    wire [7:0] clamped_sx = (sx_proj < 10'sd0) ? 8'd0 : ((sx_proj > 10'sd159) ? 8'd159 : sx_proj[7:0]);
    wire [6:0] clamped_sy = (sy_proj < 10'sd0) ? 7'd0 : ((sy_proj > 10'sd119) ? 7'd119 : sy_proj[6:0]);

    // Edge endpoints from BSRAM (1-cycle lag vs edge_idx; LOAD_EDGE2 absorbs it)
    wire [15:0] cur_edge = emem_q;
    wire [7:0]  v0_idx   = cur_edge[15:8];
    wire [7:0]  v1_idx   = cur_edge[7:0];
    wire [1:0]  v_region = rg_rom(v0_idx);

    reg [3:0] edge_color_front;
    reg [3:0] edge_color_back;
    always @(*) begin
        case (v_region)
            2'd0: begin edge_color_front = 4'd1; edge_color_back = 4'd5; end // Ears (Pink)
            2'd1: begin edge_color_front = 4'd2; edge_color_back = 4'd6; end // Head (Cream)
            2'd2: begin edge_color_front = 4'd3; edge_color_back = 4'd7; end // Body (Cyan)
            2'd3: begin edge_color_front = 4'd4; edge_color_back = 4'd8; end // Feet (Amber)
            default: begin edge_color_front = 4'd1; edge_color_back = 4'd5; end
        endcase
    end

    wire is_front_edge = vd0_q[0] | vd1_q[0];

    // Word address calculation for writes
    wire [14:0] pixel_offset = {by, 7'd0} + {by, 5'd0} + {7'd0, bx};

    // Bresenham step arithmetic (100% signed, proven safe)
    wire signed [12:0] e2 = berr <<< 1;
    wire step_x = (e2 >= bdy);
    wire step_y = (e2 <= bdx);
    wire signed [11:0] err_after_x = step_x ? (berr + bdy) : berr;
    wire signed [11:0] final_err   = step_y ? (err_after_x + bdx) : err_after_x;

    wire signed [8:0] diff_x = $signed({1'b0, b_x1}) - $signed({1'b0, bx});
    wire signed [8:0] diff_y = $signed({1'b0, b_y1}) - $signed({1'b0, by});

    // Rasterizer FSM
    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            r_state         <= S_IDLE;
            yaw             <= 8'd0;
            clear_cnt       <= 15'd0;
            vert_idx        <= 8'd0;
            edge_idx        <= 10'd0;
            pass            <= 1'b0;
            reg_vx          <= 12'sd0;
            reg_vy          <= 12'sd0;
            reg_vz          <= 12'sd0;
            cos_r           <= 13'sd0;
            sin_r           <= 13'sd0;
            r_xrot          <= 13'sd0;
            r_zrot          <= 13'sd0;
            r_yrot          <= 12'sd0;
            front_buf       <= 1'b0;
            back_buf        <= 1'b1;
            draw_frame_done <= 1'b0;
            fb_we_a         <= 1'b0;
            fb_addr_a       <= 16'd0;
            fb_din_a        <= 4'd0;
            bx              <= 8'd0;
            by              <= 7'd0;
            b_x1            <= 8'd0;
            b_y1            <= 7'd0;
            bdx             <= 11'sd0;
            bdy             <= 11'sd0;
            step_x_dir      <= 1'b0;
            step_y_dir      <= 1'b0;
            berr            <= 12'sd0;
            cur_color       <= 4'd0;
            watchdog        <= 9'd0;
            vd_we           <= 1'b0;
            vd_waddr        <= 8'd0;
            vd_wdata        <= 16'd0;
            vd0_raddr       <= 8'd0;
            vd1_raddr       <= 8'd0;
        end else begin
            case (r_state)
                S_IDLE: begin
                    fb_we_a <= 1'b0;
                    vd_we   <= 1'b0;
                    if (frame_start) begin
                        // Flip buffers and advance yaw rotation
                        front_buf       <= back_buf;
                        back_buf        <= ~back_buf;
                        yaw             <= yaw + 8'd1;
                        clear_cnt       <= 15'd0;
                        draw_frame_done <= 1'b0;
                        r_state         <= S_CLEAR;
                    end
                end

                S_CLEAR: begin
                    // Clear 1 pixel per clock cycle with backdrop color 0.
                    // NOTE: fb_we_a stays 1 on the final pixel (19199); the
                    // write lands on the S_ROT_FETCH edge (all following
                    // states drive we_a low). Suppressing it here would skip
                    // pixel 19199 forever (1px garbage corner).
                    fb_we_a   <= 1'b1;
                    fb_addr_a <= (back_buf ? 16'd19200 : 16'd0) + clear_cnt;
                    fb_din_a  <= 4'd0; // Sapphire Blue

                    if (clear_cnt == 15'd19199) begin
                        vert_idx <= 8'd0;
                        cos_r    <= cos_val; // latch frame-constant yaw coeffs
                        sin_r    <= sin_val;
                        r_state  <= S_ROT_FETCH;
                    end else begin
                        clear_cnt <= clear_cnt + 15'd1;
                    end
                end

                S_ROT_FETCH: begin
                    // BSRAM wait: vert_idx is stable, vmem_q catches up
                    // next edge. Latch one cycle later in FETCH2.
                    fb_we_a <= 1'b0;
                    r_state <= S_ROT_FETCH2;
                end

                S_ROT_FETCH2: begin
                    // vmem_q now holds ROM[vert_idx]: latch vertex coords.
                    fb_we_a <= 1'b0;
                    reg_vx  <= vx;
                    reg_vy  <= vy;
                    reg_vz  <= vz;
                    r_state <= S_ROT_HOLD;
                end

                S_ROT_HOLD: begin
                    // Pipeline stage: let DSP products settle (covers 0/1/2
                    // cycles of MULT input/output register latency).
                    fb_we_a <= 1'b0;
                    r_state <= S_ROT_HOLD2;
                end

                S_ROT_HOLD2: begin
                    fb_we_a <= 1'b0;
                    r_state <= S_ROT_STAGE1;
                end

                S_ROT_STAGE1: begin
                    fb_we_a <= 1'b0;
                    r_xrot  <= (prod_xc + prod_zs) >>> 12;
                    r_zrot  <= (prod_zc - prod_xs) >>> 12;
                    r_yrot  <= reg_vy;
                    r_state <= S_ROT_STAGE2;
                end

                S_ROT_STAGE2: begin
                    fb_we_a  <= 1'b0;
                    vd_we    <= 1'b1;
                    vd_waddr <= vert_idx[7:0];
                    vd_wdata <= {clamped_sx, clamped_sy, (r_zrot >= 0)};

                    if (vert_idx == NUM_VERTS - 1) begin
                        pass     <= 1'b0; // Pass 0: Back edges first
                        edge_idx <= 10'd0;
                        r_state  <= S_LOAD_EDGE;
                    end else begin
                        vert_idx <= vert_idx + 8'd1;
                        r_state  <= S_ROT_FETCH;
                    end
                end

                S_LOAD_EDGE: begin
                    // BSRAM wait: edge_idx is stable, emem_q catches up
                    // next edge. Latch read addresses one cycle later in LOAD_EDGE2.
                    fb_we_a <= 1'b0;
                    vd_we   <= 1'b0;
                    r_state <= S_LOAD_EDGE2;
                end

                S_LOAD_EDGE2: begin
                    fb_we_a   <= 1'b0;
                    vd_we     <= 1'b0;
                    // emem_q now holds edge ROM[edge_idx].
                    // v0_idx and v1_idx are valid; initiate BSRAM vertex read.
                    vd0_raddr <= v0_idx;
                    vd1_raddr <= v1_idx;
                    r_state   <= S_LOAD_EDGE3;
                end

                S_LOAD_EDGE3: begin
                    fb_we_a <= 1'b0;
                    vd_we   <= 1'b0;
                    // vd0_q and vd1_q now hold 2D coords and z-flag.
                    if (is_front_edge != pass) begin
                        // Skip this edge for the current pass
                        if (edge_idx == NUM_EDGES - 1) begin
                            if (pass == 1'b0) begin
                                pass     <= 1'b1; // Proceed to front edges pass
                                edge_idx <= 10'd0;
                                r_state  <= S_LOAD_EDGE;
                            end else begin
                                draw_frame_done <= 1'b1;
                                fb_we_a         <= 1'b0;
                                r_state         <= S_IDLE;
                            end
                        end else begin
                            edge_idx <= edge_idx + 10'd1;
                            r_state  <= S_LOAD_EDGE;
                        end
                    end else begin
                        // Edge matches current pass: prepare to draw
                        bx        <= vd0_q[15:8];
                        by        <= vd0_q[7:1];
                        b_x1      <= vd1_q[15:8];
                        b_y1      <= vd1_q[7:1];
                        cur_color <= pass ? edge_color_front : edge_color_back;
                        r_state   <= S_SETUP_EDGE;
                    end
                end

                S_SETUP_EDGE: begin
                    fb_we_a  <= 1'b0;
                    watchdog <= 9'd0;
                    if (diff_x < 0) begin
                        bdx        <= -diff_x;
                        step_x_dir <= 1'b1; // decrement
                    end else begin
                        bdx        <= diff_x;
                        step_x_dir <= 1'b0; // increment
                    end

                    if (diff_y < 0) begin
                        bdy        <= diff_y; // negative
                        step_y_dir <= 1'b1; // decrement
                    end else begin
                        bdy        <= -diff_y; // negative
                        step_y_dir <= 1'b0; // increment
                    end

                    berr    <= (diff_x < 0 ? -diff_x : diff_x) + (diff_y < 0 ? diff_y : -diff_y);
                    r_state <= S_DRAW_PIXEL;
                end

                S_DRAW_PIXEL: begin
                    // Write pixel to back buffer: 1 cycle per pixel.
                    // NOTE: fb_we_a stays 1 on the endpoint cycle so the
                    // endpoint lands on the following state's edge (all
                    // following states drive we_a low). Suppressing it here
                    // would drop every edge endpoint (1px gaps in line art).
                    fb_we_a   <= 1'b1;
                    fb_addr_a <= (back_buf ? 16'd19200 : 16'd0) + pixel_offset;
                    fb_din_a  <= cur_color;
                    watchdog  <= watchdog + 1'b1;

                    if ((bx == b_x1 && by == b_y1) || watchdog >= 9'd200) begin
                        // Edge completed
                        if (edge_idx == NUM_EDGES - 1) begin
                            if (pass == 1'b0) begin
                                pass     <= 1'b1; // Proceed to front edges pass
                                edge_idx <= 10'd0;
                                r_state  <= S_LOAD_EDGE;
                            end else begin
                                draw_frame_done <= 1'b1;
                                r_state         <= S_IDLE;
                            end
                        end else begin
                            edge_idx <= edge_idx + 10'd1;
                            r_state  <= S_LOAD_EDGE;
                        end
                    end else begin
                        // Step Bresenham cleanly without signed addition bugs
                        if (step_x)
                            bx <= step_x_dir ? (bx - 1'b1) : (bx + 1'b1);
                        if (step_y)
                            by <= step_y_dir ? (by - 1'b1) : (by + 1'b1);
                        berr <= final_err;
                    end
                end

                default: r_state <= S_IDLE;
            endcase
        end
    end

    // =========================================================================
    // 5. TMDS Encoders & DDR 2-bit Serializers
    // =========================================================================
    wire [9:0] tmds_blue, tmds_green, tmds_red;

    tmds_encoder enc_b (
        .clk(clk_pixel),
        .rst_n(rst_n),
        .data_in(rgb_b),
        .ctrl_in({vs_q2, hs_q2}),
        .de(de_q2),
        .tmds_out(tmds_blue)
    );

    tmds_encoder enc_g (
        .clk(clk_pixel),
        .rst_n(rst_n),
        .data_in(rgb_g),
        .ctrl_in(2'b00),
        .de(de_q2),
        .tmds_out(tmds_green)
    );

    tmds_encoder enc_r (
        .clk(clk_pixel),
        .rst_n(rst_n),
        .data_in(rgb_r),
        .ctrl_in(2'b00),
        .de(de_q2),
        .tmds_out(tmds_red)
    );

    // OSER10 10:1 hard-SERDES (PCLK=pixel, FCLK=5x) + ELVDS_OBUF.
    // LSB-first: D0=tmds[0]. Clock channel = 11111_00000 (50% duty).
    wire [3:0] ser_q;
    OSER10 #(.GSREN("false"), .LSREN("true")) ser_b (
        .Q(ser_q[0]),
        .D0(tmds_blue[0]), .D1(tmds_blue[1]), .D2(tmds_blue[2]),
        .D3(tmds_blue[3]), .D4(tmds_blue[4]), .D5(tmds_blue[5]),
        .D6(tmds_blue[6]), .D7(tmds_blue[7]), .D8(tmds_blue[8]),
        .D9(tmds_blue[9]),
        .PCLK(clk_pixel), .FCLK(clk_126), .RESET(~rst_n));
    OSER10 #(.GSREN("false"), .LSREN("true")) ser_g (
        .Q(ser_q[1]),
        .D0(tmds_green[0]), .D1(tmds_green[1]), .D2(tmds_green[2]),
        .D3(tmds_green[3]), .D4(tmds_green[4]), .D5(tmds_green[5]),
        .D6(tmds_green[6]), .D7(tmds_green[7]), .D8(tmds_green[8]),
        .D9(tmds_green[9]),
        .PCLK(clk_pixel), .FCLK(clk_126), .RESET(~rst_n));
    OSER10 #(.GSREN("false"), .LSREN("true")) ser_r (
        .Q(ser_q[2]),
        .D0(tmds_red[0]), .D1(tmds_red[1]), .D2(tmds_red[2]),
        .D3(tmds_red[3]), .D4(tmds_red[4]), .D5(tmds_red[5]),
        .D6(tmds_red[6]), .D7(tmds_red[7]), .D8(tmds_red[8]),
        .D9(tmds_red[9]),
        .PCLK(clk_pixel), .FCLK(clk_126), .RESET(~rst_n));
    OSER10 #(.GSREN("false"), .LSREN("true")) ser_c (
        .Q(ser_q[3]),
        .D0(1'b1), .D1(1'b1), .D2(1'b1), .D3(1'b1), .D4(1'b1),
        .D5(1'b0), .D6(1'b0), .D7(1'b0), .D8(1'b0), .D9(1'b0),
        .PCLK(clk_pixel), .FCLK(clk_126), .RESET(~rst_n));

    ELVDS_OBUF obuf_b (.I(ser_q[0]), .O(tmds_d_p[0]), .OB(tmds_d_n[0]));
    ELVDS_OBUF obuf_g (.I(ser_q[1]), .O(tmds_d_p[1]), .OB(tmds_d_n[1]));
    ELVDS_OBUF obuf_r (.I(ser_q[2]), .O(tmds_d_p[2]), .OB(tmds_d_n[2]));
    ELVDS_OBUF obuf_c (.I(ser_q[3]), .O(tmds_clk_p),  .OB(tmds_clk_n));

    // =========================================================================
    // 6. Diagnostics LEDs & Heartbeat
    // =========================================================================
    reg [24:0] heartbeat_cnt = 25'd0;
    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n)
            heartbeat_cnt <= 25'd0;
        else
            heartbeat_cnt <= heartbeat_cnt + 1'b1;
    end

    // Active-Low LEDs:
    // LED 0: PLL Locked (LIT)
    // LED 1: Draw Complete (LIT)
    // LED 2: Front Buffer (Toggles at 30Hz)
    // LED 3: Current Pass (0=Back, 1=Front)
    // LED 4: FSM State bit 0
    // LED 5: Heartbeat (~1.5Hz blink)
    assign led[0] = ~pll_lock;
    assign led[1] = ~draw_frame_done;
    assign led[2] = ~front_buf;
    assign led[3] = ~pass;
    assign led[4] = ~r_state[0];
    assign led[5] = ~heartbeat_cnt[24];

endmodule
