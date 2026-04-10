// ==============================================================================
// File name         : flicker_fixer_top.v
// Module name       : flicker_fixer_top
// Description       : Top-level module for the Amiga DENISE flicker fixer.
//
//                     Captures 12-bit digital RGB from the Super DENISE 8373
//                     (ECS) chip, stores frames in DDR3 via ping-pong field
//                     buffers, performs weave deinterlacing and nearest-neighbor
//                     scaling, and outputs progressive 720p HDMI.
//
//                     Outputs 720p50 for PAL input, 720p60 for NTSC input.
//                     Falls back to test pattern when no Amiga input detected.
//
// Target            : Gowin GW2A-LV18PG256C8/I7 (Tang Primer 20K)
// ==============================================================================

module flicker_fixer_top (
    // System
    input              I_clk,          // 27 MHz board oscillator
    input              I_rst_n,        // Active-low reset button

    // DENISE interface (active after 5V->3.3V level shifting)
    input  [3:0]       I_denise_r,     // Red digital output (pins 20-23)
    input  [3:0]       I_denise_g,     // Green digital output (pins 28-31)
    input  [3:0]       I_denise_b,     // Blue digital output (pins 24-27)
    input              I_denise_csync_n, // Composite sync (pin 32, active low)
    input              I_denise_zd_n,  // Zero detect / blanking (pin 33)
    input              I_denise_7m,    // 7 MHz clock (pin 35)
    input              I_denise_cdac,  // CDAC clock (pin 34, ECS only)

    // HDMI output (directly to connector)
    output             O_tmds_clk_p,
    output             O_tmds_clk_n,
    output [2:0]       O_tmds_data_p,  // {R, G, B}
    output [2:0]       O_tmds_data_n,

    // DDR3 memory interface — added when DDR3 controller is integrated.
    // For now, omitted to allow clean synthesis without controller.
    // See PLACEHOLDER section below for the instantiation template.

    // Status LEDs
    output [3:0]       O_led
);

// ============================================================
// Clock generation
// ============================================================

// --- HDMI output clocks (from 27 MHz) ---
wire serial_clk;    // ~371.25 MHz TMDS serial clock
wire pix_clk;       // ~74.25 MHz pixel clock
wire tmds_pll_lock;

TMDS_rPLL u_tmds_rpll (
    .clkin  (I_clk),
    .clkout (serial_clk),
    .lock   (tmds_pll_lock)
);

wire hdmi_rst_n = I_rst_n & tmds_pll_lock;

CLKDIV u_clkdiv (
    .RESETN (hdmi_rst_n),
    .HCLKIN (serial_clk),
    .CLKOUT (pix_clk),
    .CALIB  (1'b1)
);
defparam u_clkdiv.DIV_MODE = "5";
defparam u_clkdiv.GSREN = "false";

// --- Amiga capture clock (from 7M) ---
wire clk_28m;
wire amiga_pll_lock;

Amiga_rPLL u_amiga_rpll (
    .clkin  (I_denise_7m),
    .clkout (clk_28m),
    .lock   (amiga_pll_lock)
);

wire capture_rst_n = I_rst_n & amiga_pll_lock;

// --- DDR3 memory clock ---
// The DDR3 controller generates its own clocks internally.
// clk_mem (100 MHz) comes from the DDR3 controller module.
wire clk_mem;       // 100 MHz user clock from DDR3 controller
wire ddr3_init_done;
wire mem_rst_n = I_rst_n & ddr3_init_done;

// ============================================================
// Input presence detection
// ============================================================
// Detect if Amiga is connected by watching for sync activity
reg [23:0] input_timeout_cnt;
reg        input_valid;

always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        input_timeout_cnt <= 0;
        input_valid <= 0;
    end else begin
        if (amiga_pll_lock)
            input_valid <= 1;
        else begin
            if (input_timeout_cnt >= 24'd13_500_000) // ~0.5 sec at 27 MHz
                input_valid <= 0;
            else
                input_timeout_cnt <= input_timeout_cnt + 1'b1;
        end
        if (amiga_pll_lock)
            input_timeout_cnt <= 0;
    end
end

// ============================================================
// DENISE Capture
// ============================================================
wire        cap_pix_valid;
wire [11:0] cap_pix_rgb;
wire [10:0] cap_pix_x;
wire [9:0]  cap_pix_y;
wire        cap_hsync, cap_vsync;
wire        cap_field_id;
wire        cap_is_pal;
wire        cap_is_interlaced;
wire        cap_frame_start;
wire        cap_line_start;
wire [10:0] cap_active_width;
wire [9:0]  cap_active_height;

denise_capture u_capture (
    .clk_28m            (clk_28m),
    .rst_n              (capture_rst_n),
    .I_denise_r         (I_denise_r),
    .I_denise_g         (I_denise_g),
    .I_denise_b         (I_denise_b),
    .I_denise_csync_n   (I_denise_csync_n),
    .I_denise_zd_n      (I_denise_zd_n),
    .I_denise_7m        (I_denise_7m),
    .I_denise_cdac      (I_denise_cdac),
    .O_pix_valid        (cap_pix_valid),
    .O_pix_rgb          (cap_pix_rgb),
    .O_pix_x            (cap_pix_x),
    .O_pix_y            (cap_pix_y),
    .O_hsync            (cap_hsync),
    .O_vsync            (cap_vsync),
    .O_field_id         (cap_field_id),
    .O_is_pal           (cap_is_pal),
    .O_is_interlaced    (cap_is_interlaced),
    .O_frame_start      (cap_frame_start),
    .O_line_start       (cap_line_start),
    .O_active_width     (cap_active_width),
    .O_active_height    (cap_active_height)
);

// ============================================================
// Write FIFO: capture (28 MHz) -> memory (100 MHz)
// ============================================================
// Pack pixel data + coordinates into FIFO word
// Format: {field_id[0], y[9:0], x[10:0], rgb[11:0]} = 34 bits
wire [33:0] wr_fifo_din = {cap_field_id, cap_pix_y, cap_pix_x, cap_pix_rgb};
wire [33:0] wr_fifo_dout;
wire        wr_fifo_empty;
wire        wr_fifo_full;
reg         wr_fifo_rd_en;

async_fifo #(
    .DATA_WIDTH (34),
    .ADDR_WIDTH (6)    // 64-deep FIFO
) u_wr_fifo (
    .wr_clk   (clk_28m),
    .wr_rst_n (capture_rst_n),
    .wr_en    (cap_pix_valid & ~wr_fifo_full),
    .wr_data  (wr_fifo_din),
    .wr_full  (wr_fifo_full),
    .rd_clk   (clk_mem),
    .rd_rst_n (mem_rst_n),
    .rd_en    (wr_fifo_rd_en),
    .rd_data  (wr_fifo_dout),
    .rd_empty (wr_fifo_empty)
);

// Unpack FIFO output
wire        fifo_wr_field = wr_fifo_dout[33];
wire [9:0]  fifo_wr_y     = wr_fifo_dout[32:23];
wire [10:0] fifo_wr_x     = wr_fifo_dout[22:12];
wire [11:0] fifo_wr_rgb   = wr_fifo_dout[11:0];

// FIFO read: drain whenever not empty
always @(posedge clk_mem or negedge mem_rst_n) begin
    if (!mem_rst_n)
        wr_fifo_rd_en <= 0;
    else
        wr_fifo_rd_en <= ~wr_fifo_empty;
end

wire wr_pixel_valid = wr_fifo_rd_en & ~wr_fifo_empty;

// ============================================================
// Frame start CDC (capture -> memory domain)
// ============================================================
reg frame_start_s1, frame_start_s2, frame_start_s3;
reg field_parity_s1, field_parity_s2;

always @(posedge clk_mem or negedge mem_rst_n) begin
    if (!mem_rst_n) begin
        frame_start_s1 <= 0; frame_start_s2 <= 0; frame_start_s3 <= 0;
        field_parity_s1 <= 0; field_parity_s2 <= 0;
    end else begin
        frame_start_s1 <= cap_frame_start;
        frame_start_s2 <= frame_start_s1;
        frame_start_s3 <= frame_start_s2;
        field_parity_s1 <= cap_field_id;
        field_parity_s2 <= field_parity_s1;
    end
end

wire field_done_pulse = frame_start_s2 & ~frame_start_s3;

// ============================================================
// Mode CDC (capture -> output pixel domain)
// ============================================================
reg        is_pal_pix_s1, is_pal_pix;
reg        is_interlaced_pix_s1, is_interlaced_pix;
reg [10:0] active_width_pix_s1, active_width_pix;
reg [9:0]  active_height_pix_s1, active_height_pix;
reg        input_valid_pix_s1, input_valid_pix;

always @(posedge pix_clk or negedge hdmi_rst_n) begin
    if (!hdmi_rst_n) begin
        is_pal_pix_s1 <= 0; is_pal_pix <= 0;
        is_interlaced_pix_s1 <= 0; is_interlaced_pix <= 0;
        active_width_pix_s1 <= 11'd640; active_width_pix <= 11'd640;
        active_height_pix_s1 <= 10'd256; active_height_pix <= 10'd256;
        input_valid_pix_s1 <= 0; input_valid_pix <= 0;
    end else begin
        is_pal_pix_s1 <= cap_is_pal;
        is_pal_pix <= is_pal_pix_s1;
        is_interlaced_pix_s1 <= cap_is_interlaced;
        is_interlaced_pix <= is_interlaced_pix_s1;
        active_width_pix_s1 <= cap_active_width;
        active_width_pix <= active_width_pix_s1;
        active_height_pix_s1 <= cap_active_height;
        active_height_pix <= active_height_pix_s1;
        input_valid_pix_s1 <= input_valid;
        input_valid_pix <= input_valid_pix_s1;
    end
end

// ============================================================
// Frame Buffer Controller
// ============================================================
wire [25:0] ddr_addr;
wire [15:0] ddr_din;
wire [15:0] ddr_dout;
wire        ddr_rd;
wire        ddr_wr;
wire        ddr_busy;
wire        ddr_data_ready;

// Read interface signals (from output_gen, need CDC)
wire        fetch_req_pix;
wire [9:0]  fetch_line_pix;
wire        fetch_field_pix;
wire [10:0] fetch_width_pix;
wire        fetch_done_mem;

// Line buffer read signals
wire [10:0] lb_rd_addr_pix;
wire [15:0] lb_rd_data_mem;

// CDC for fetch request: pixel -> mem domain
reg fetch_req_toggle_pix;
reg fetch_req_toggle_s1, fetch_req_toggle_s2, fetch_req_toggle_s3;
reg [9:0]  fetch_line_mem;
reg        fetch_field_mem;
reg [10:0] fetch_width_mem;

always @(posedge pix_clk or negedge hdmi_rst_n) begin
    if (!hdmi_rst_n)
        fetch_req_toggle_pix <= 0;
    else if (fetch_req_pix)
        fetch_req_toggle_pix <= ~fetch_req_toggle_pix;
end

always @(posedge clk_mem or negedge mem_rst_n) begin
    if (!mem_rst_n) begin
        fetch_req_toggle_s1 <= 0;
        fetch_req_toggle_s2 <= 0;
        fetch_req_toggle_s3 <= 0;
        fetch_line_mem <= 0;
        fetch_field_mem <= 0;
        fetch_width_mem <= 0;
    end else begin
        fetch_req_toggle_s1 <= fetch_req_toggle_pix;
        fetch_req_toggle_s2 <= fetch_req_toggle_s1;
        fetch_req_toggle_s3 <= fetch_req_toggle_s2;
        // Latch request parameters on toggle edge
        if (fetch_req_toggle_s2 != fetch_req_toggle_s3) begin
            fetch_line_mem  <= fetch_line_pix;
            fetch_field_mem <= fetch_field_pix;
            fetch_width_mem <= fetch_width_pix;
        end
    end
end

wire fetch_req_mem = (fetch_req_toggle_s2 != fetch_req_toggle_s3);

// CDC for fetch done: mem -> pixel domain
reg fetch_done_toggle_mem;
reg fetch_done_toggle_s1, fetch_done_toggle_s2, fetch_done_toggle_s3;

always @(posedge clk_mem or negedge mem_rst_n) begin
    if (!mem_rst_n)
        fetch_done_toggle_mem <= 0;
    else if (fetch_done_mem)
        fetch_done_toggle_mem <= ~fetch_done_toggle_mem;
end

always @(posedge pix_clk or negedge hdmi_rst_n) begin
    if (!hdmi_rst_n) begin
        fetch_done_toggle_s1 <= 0;
        fetch_done_toggle_s2 <= 0;
        fetch_done_toggle_s3 <= 0;
    end else begin
        fetch_done_toggle_s1 <= fetch_done_toggle_mem;
        fetch_done_toggle_s2 <= fetch_done_toggle_s1;
        fetch_done_toggle_s3 <= fetch_done_toggle_s2;
    end
end

wire fetch_done_pix = (fetch_done_toggle_s2 != fetch_done_toggle_s3);

// Line buffer address CDC: pixel -> mem
// (line buffer is dual-port, so rd_addr goes directly)
// We synchronize lb_rd_addr from pix_clk to clk_mem for the read port
reg [10:0] lb_rd_addr_mem;
always @(posedge clk_mem) begin
    lb_rd_addr_mem <= lb_rd_addr_pix;
end

// Line buffer data CDC: mem -> pixel
// (1-2 cycle latency is acceptable since we pipeline the output)
reg [15:0] lb_rd_data_pix;
always @(posedge pix_clk) begin
    lb_rd_data_pix <= lb_rd_data_mem;
end

wire [1:0] even_rd_buf, odd_rd_buf;

frame_buffer_ctrl u_fb_ctrl (
    .clk_mem        (clk_mem),
    .rst_n          (mem_rst_n),
    // DDR3 controller
    .O_ddr_addr     (ddr_addr),
    .O_ddr_din      (ddr_din),
    .I_ddr_dout     (ddr_dout),
    .O_ddr_rd       (ddr_rd),
    .O_ddr_wr       (ddr_wr),
    .I_ddr_busy     (ddr_busy),
    .I_ddr_data_ready (ddr_data_ready),
    // Write interface
    .I_wr_req       (wr_pixel_valid),
    .I_wr_rgb       (fifo_wr_rgb),
    .I_wr_x         (fifo_wr_x),
    .I_wr_y         (fifo_wr_y),
    .I_wr_field_id  (fifo_wr_field),
    .O_wr_ack       (),
    // Field management
    .I_field_done   (field_done_pulse),
    .I_field_parity (field_parity_s2),
    // Read interface
    .I_rd_line_req  (fetch_req_mem),
    .I_rd_line_num  (fetch_line_mem),
    .I_rd_field_sel (fetch_field_mem),
    .I_rd_line_width(fetch_width_mem),
    .O_rd_line_done (fetch_done_mem),
    // Line buffer read port
    .I_lb_rd_addr   (lb_rd_addr_mem),
    .O_lb_rd_data   (lb_rd_data_mem),
    // Status
    .O_even_rd_buf  (even_rd_buf),
    .O_odd_rd_buf   (odd_rd_buf)
);

// ============================================================
// DDR3 Controller
// ============================================================
// Instantiate the DDR3 memory controller.
// This uses the nand2mario open-source controller or Gowin DDR3 IP.
// The user must add the DDR3 controller to the project.
//
// Interface expected:
//   input  clk        -> I_clk (27 MHz, used to generate memory clocks)
//   input  resetn     -> I_rst_n
//   output pclk       -> clk_mem (100 MHz user clock)
//   output init_done  -> ddr3_init_done
//   input  [25:0] addr -> ddr_addr
//   input  [15:0] din  -> ddr_din
//   output [15:0] dout -> ddr_dout
//   input  rd          -> ddr_rd
//   input  wr          -> ddr_wr
//   output busy        -> ddr_busy
//   output data_ready  -> ddr_data_ready
//   DDR3 physical pins -> O_ddr3_*, IO_ddr3_*

// PLACEHOLDER: Replace with actual DDR3 controller instantiation.
// For nand2mario controller:
//
// ddr3_controller u_ddr3 (
//     .clk       (I_clk),
//     .resetn    (I_rst_n),
//     .pclk      (clk_mem),
//     .init_done (ddr3_init_done),
//     .addr      (ddr_addr),
//     .din       (ddr_din),
//     .dout      (ddr_dout),
//     .rd        (ddr_rd),
//     .wr        (ddr_wr),
//     .busy      (ddr_busy),
//     .data_ready(ddr_data_ready),
//     // DDR3 physical interface
//     .DDR3_A    (O_ddr3_addr),
//     .DDR3_BA   (O_ddr3_ba),
//     .DDR3_nRAS (O_ddr3_ras_n),
//     .DDR3_nCAS (O_ddr3_cas_n),
//     .DDR3_nWE  (O_ddr3_we_n),
//     .DDR3_CK   (O_ddr3_ck),
//     .DDR3_CK_N (O_ddr3_ck_n),
//     .DDR3_CKE  (O_ddr3_cke),
//     .DDR3_ODT  (O_ddr3_odt),
//     .DDR3_nCS  (O_ddr3_cs_n),
//     .DDR3_nRESET(O_ddr3_reset_n),
//     .DDR3_DM   (O_ddr3_dm),
//     .DDR3_DQ   (IO_ddr3_dq),
//     .DDR3_DQS  (IO_ddr3_dqs),
//     .DDR3_DQS_N(IO_ddr3_dqs_n)
// );

// Temporary: stub DDR3 signals for compilation without controller
assign clk_mem       = I_clk;  // TEMPORARY: use 27 MHz
assign ddr3_init_done = 1'b0;  // TEMPORARY: never ready
assign ddr_dout      = 16'd0;
assign ddr_busy      = 1'b1;
assign ddr_data_ready = 1'b0;

// ============================================================
// Output Generator
// ============================================================
wire       out_de;
wire       out_hs;
wire       out_vs;
wire [7:0] out_r, out_g, out_b;

output_gen u_output (
    .pix_clk         (pix_clk),
    .rst_n           (hdmi_rst_n),
    .I_is_pal        (is_pal_pix),
    .I_is_interlaced (is_interlaced_pix),
    .I_active_width  (active_width_pix),
    .I_active_height (active_height_pix),
    .I_input_valid   (input_valid_pix),
    .O_lb_rd_addr    (lb_rd_addr_pix),
    .I_lb_rd_data    (lb_rd_data_pix),
    .O_fetch_req     (fetch_req_pix),
    .O_fetch_line    (fetch_line_pix),
    .O_fetch_field   (fetch_field_pix),
    .O_fetch_width   (fetch_width_pix),
    .I_fetch_done    (fetch_done_pix),
    .O_de            (out_de),
    .O_hs            (out_hs),
    .O_vs            (out_vs),
    .O_data_r        (out_r),
    .O_data_g        (out_g),
    .O_data_b        (out_b)
);

// ============================================================
// Fallback test pattern (when no Amiga input)
// ============================================================
wire        tp_de, tp_hs, tp_vs;
wire [7:0]  tp_r, tp_g, tp_b;

testpattern u_testpattern (
    .I_pxl_clk  (pix_clk),
    .I_rst_n    (hdmi_rst_n),
    .I_mode     (3'b000),           // Color bars
    .I_single_r (8'd0),
    .I_single_g (8'd255),
    .I_single_b (8'd0),
    .I_h_total  (12'd1650),         // 720p60 timing for test
    .I_h_sync   (12'd40),
    .I_h_bporch (12'd220),
    .I_h_res    (12'd1280),
    .I_v_total  (12'd750),
    .I_v_sync   (12'd5),
    .I_v_bporch (12'd20),
    .I_v_res    (12'd720),
    .I_hs_pol   (1'b1),
    .I_vs_pol   (1'b1),
    .O_de       (tp_de),
    .O_hs       (tp_hs),
    .O_vs       (tp_vs),
    .O_data_r   (tp_r),
    .O_data_g   (tp_g),
    .O_data_b   (tp_b)
);

// Select between Amiga output and test pattern
wire       vid_de = input_valid_pix ? out_de : tp_de;
wire       vid_hs = input_valid_pix ? out_hs : tp_hs;
wire       vid_vs = input_valid_pix ? out_vs : tp_vs;
wire [7:0] vid_r  = input_valid_pix ? out_r  : tp_r;
wire [7:0] vid_g  = input_valid_pix ? out_g  : tp_g;
wire [7:0] vid_b  = input_valid_pix ? out_b  : tp_b;

// ============================================================
// HDMI/DVI Transmitter
// ============================================================
DVI_TX_Top u_dvi_tx (
    .I_rst_n       (hdmi_rst_n),
    .I_serial_clk  (serial_clk),
    .I_rgb_clk     (pix_clk),
    .I_rgb_vs      (vid_vs),
    .I_rgb_hs      (vid_hs),
    .I_rgb_de      (vid_de),
    .I_rgb_r       (vid_r),
    .I_rgb_g       (vid_g),
    .I_rgb_b       (vid_b),
    .O_tmds_clk_p  (O_tmds_clk_p),
    .O_tmds_clk_n  (O_tmds_clk_n),
    .O_tmds_data_p (O_tmds_data_p),
    .O_tmds_data_n (O_tmds_data_n)
);

// ============================================================
// Status LEDs
// ============================================================
reg [24:0] led_cnt;
always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n)
        led_cnt <= 0;
    else
        led_cnt <= led_cnt + 1'b1;
end

assign O_led[0] = led_cnt[24];          // Heartbeat (~1 Hz blink)
assign O_led[1] = input_valid;          // Amiga input detected
assign O_led[2] = amiga_pll_lock;       // Amiga PLL locked
assign O_led[3] = tmds_pll_lock;        // HDMI PLL locked

endmodule
