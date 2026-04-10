// ---------------------------------------------------------------------
// File name         : output_gen.v
// Module name       : output_gen
// Description       : HDMI output timing generator with integrated
//                     weave deinterlacer and nearest-neighbor scaler.
//
//                     Generates 720p50 (PAL) or 720p60 (NTSC) HDMI
//                     timing. Both use 74.25 MHz pixel clock.
//
//                     720p60 (CEA-4):  1650 x 750, HFP=110
//                     720p50 (CEA-19): 1980 x 750, HFP=440
//
//                     Reads deinterlaced, scaled pixel data from
//                     the frame buffer's line buffers.
// ---------------------------------------------------------------------

module output_gen (
    input              pix_clk,       // 74.25 MHz pixel clock
    input              rst_n,

    // Mode configuration (synced from capture domain)
    input              I_is_pal,
    input              I_is_interlaced,
    input  [10:0]      I_active_width,  // Source active pixels per line
    input  [9:0]       I_active_height, // Source active lines per field
    input              I_input_valid,   // High when Amiga input is detected

    // Line buffer interface (directly in pix_clk domain via line buffer read port)
    output reg [10:0]  O_lb_rd_addr,
    input  [15:0]      I_lb_rd_data,    // {4'b0, R[3:0], G[3:0], B[3:0]}

    // Line fetch request (to frame_buffer_ctrl via CDC)
    output reg         O_fetch_req,
    output reg [9:0]   O_fetch_line,
    output reg         O_fetch_field,   // Field parity to fetch
    output reg [10:0]  O_fetch_width,
    input              I_fetch_done,

    // Video output to DVI TX
    output             O_de,
    output reg         O_hs,
    output reg         O_vs,
    output     [7:0]   O_data_r,
    output     [7:0]   O_data_g,
    output     [7:0]   O_data_b
);

// ============================================================
// Output timing parameters
// ============================================================
// Both 720p50 and 720p60 share same pixel clock (74.25 MHz),
// vertical timing, sync widths, and back porches.
// Only horizontal front porch differs.

localparam H_SYNC    = 12'd40;
localparam H_BPORCH  = 12'd220;
localparam H_RES     = 12'd1280;
localparam V_TOTAL   = 12'd750;
localparam V_SYNC    = 12'd5;
localparam V_BPORCH  = 12'd20;
localparam V_RES     = 12'd720;

// Horizontal front porch: 110 for 60Hz, 440 for 50Hz
wire [11:0] h_fporch = I_is_pal ? 12'd440 : 12'd110;
wire [11:0] h_total  = H_SYNC + H_BPORCH + H_RES + h_fporch;

// ============================================================
// Timing counters
// ============================================================
reg [11:0] h_cnt;
reg [11:0] v_cnt;

always @(posedge pix_clk or negedge rst_n) begin
    if (!rst_n) begin
        h_cnt <= 0;
        v_cnt <= 0;
    end else begin
        if (h_cnt >= h_total - 1'b1) begin
            h_cnt <= 0;
            if (v_cnt >= V_TOTAL - 1'b1)
                v_cnt <= 0;
            else
                v_cnt <= v_cnt + 1'b1;
        end else begin
            h_cnt <= h_cnt + 1'b1;
        end
    end
end

// ============================================================
// Sync and data enable generation
// ============================================================
wire h_active = (h_cnt >= H_SYNC + H_BPORCH) &&
                (h_cnt < H_SYNC + H_BPORCH + H_RES);
wire v_active = (v_cnt >= V_SYNC + V_BPORCH) &&
                (v_cnt < V_SYNC + V_BPORCH + V_RES);
wire de_w = h_active & v_active;

// Sync signals (active high for 720p, positive polarity)
wire hs_w = (h_cnt < H_SYNC);
wire vs_w = (v_cnt < V_SYNC);

// Pipeline delay (2 stages for line buffer read latency)
reg [1:0] de_pipe;
reg [1:0] hs_pipe;
reg [1:0] vs_pipe;

always @(posedge pix_clk or negedge rst_n) begin
    if (!rst_n) begin
        de_pipe <= 0;
        hs_pipe <= 2'b00;
        vs_pipe <= 2'b00;
    end else begin
        de_pipe <= {de_pipe[0], de_w};
        hs_pipe <= {hs_pipe[0], hs_w};
        vs_pipe <= {vs_pipe[0], vs_w};
    end
end

assign O_de = de_pipe[1];

always @(posedge pix_clk or negedge rst_n) begin
    if (!rst_n) begin
        O_hs <= 0;
        O_vs <= 0;
    end else begin
        O_hs <= hs_pipe[1];
        O_vs <= vs_pipe[1];
    end
end

// ============================================================
// Active pixel coordinates (within 1280x720 active area)
// ============================================================
wire [11:0] active_x = h_cnt - (H_SYNC + H_BPORCH);
wire [11:0] active_y = v_cnt - (V_SYNC + V_BPORCH);

// ============================================================
// Scaling: nearest-neighbor
// ============================================================
// Compute source coordinates using fixed-point arithmetic.
// src_x = active_x * src_width / 1280
// src_y = active_y * src_height / 720
//
// For interlaced weave output:
//   Total source height = active_height * 2 (even + odd fields combined)
//   src_y_full = active_y * (active_height * 2) / 720
//   field_sel  = src_y_full[0]  (LSB selects field)
//   src_line   = src_y_full / 2 (line within field)

// Use safe defaults when input is invalid
wire [10:0] src_width  = (I_active_width  > 11'd16) ? I_active_width  : 11'd640;
wire [9:0]  src_height = (I_active_height > 10'd16) ? I_active_height : 10'd256;

// Scale factors as fixed-point 16.16: (src_size << 16) / dst_size
// Pre-compute once per frame (use registers to avoid huge combinational dividers)
reg [31:0] scale_x; // (src_width << 16) / 1280
reg [31:0] scale_y; // (src_total_height << 16) / 720

// Source total height for scaling
wire [10:0] src_total_height = I_is_interlaced ? {src_height, 1'b0} : {1'b0, src_height};

// Recompute scale factors at frame start (v_cnt == 0, h_cnt == 0)
// Use iterative divider or approximate with shift-based division.
// For synthesis simplicity, use a lookup approach based on common sizes.
// Alternatively, accept the combinational divider (synthesis tools handle it).
reg scale_valid;

always @(posedge pix_clk or negedge rst_n) begin
    if (!rst_n) begin
        scale_x <= 32'h00008000; // Default ~0.5 (640/1280)
        scale_y <= 32'h00008000;
        scale_valid <= 0;
    end else if (v_cnt == 0 && h_cnt == 0) begin
        // Compute scale factors
        // scale_x = (src_width << 16) / 1280
        // For common Amiga widths, these are fixed values:
        if (src_width <= 11'd384)
            scale_x <= ({21'b0, src_width} << 16) / 32'd1280;
        else if (src_width <= 11'd768)
            scale_x <= ({21'b0, src_width} << 16) / 32'd1280;
        else
            scale_x <= ({21'b0, src_width} << 16) / 32'd1280;

        scale_y <= ({21'b0, src_total_height} << 16) / 32'd720;
        scale_valid <= 1;
    end
end

// Source coordinate computation (fixed-point multiply)
wire [31:0] src_x_fp = active_x * scale_x[15:0]; // lower 16 bits of scale
wire [31:0] src_y_fp = active_y * scale_y[15:0];

// Integer source coordinates
wire [10:0] src_x_int = src_x_fp[26:16];
wire [10:0] src_y_int = src_y_fp[26:16];

// For interlaced weave: decompose Y into field + line
wire        src_field  = I_is_interlaced ? src_y_int[0] : 1'b0;
wire [9:0]  src_line   = I_is_interlaced ? src_y_int[10:1] : src_y_int[9:0];

// ============================================================
// Line prefetch logic
// ============================================================
// At the start of each output line (during HSYNC), request the
// source line from DDR3. If the source line hasn't changed from
// the previous output line, skip the fetch.

reg [9:0]  prev_src_line;
reg        prev_src_field;
reg        line_ready;

// Compute source line for the NEXT output line
wire [11:0] next_active_y = (v_cnt >= V_SYNC + V_BPORCH - 1'b1) ?
                            v_cnt - (V_SYNC + V_BPORCH - 1'b1) : 12'd0;
wire [31:0] next_src_y_fp = next_active_y * scale_y[15:0];
wire [10:0] next_src_y_int = next_src_y_fp[26:16];
wire        next_src_field = I_is_interlaced ? next_src_y_int[0] : 1'b0;
wire [9:0]  next_src_line  = I_is_interlaced ? next_src_y_int[10:1] : next_src_y_int[9:0];

always @(posedge pix_clk or negedge rst_n) begin
    if (!rst_n) begin
        O_fetch_req <= 0;
        O_fetch_line <= 0;
        O_fetch_field <= 0;
        O_fetch_width <= 0;
        prev_src_line <= 10'h3FF;
        prev_src_field <= 0;
        line_ready <= 0;
    end else begin
        O_fetch_req <= 0;

        // At horizontal position just after sync start, issue prefetch
        if (h_cnt == 12'd1 && v_active) begin
            if (next_src_line != prev_src_line || next_src_field != prev_src_field) begin
                O_fetch_req   <= 1;
                O_fetch_line  <= next_src_line;
                O_fetch_field <= next_src_field;
                O_fetch_width <= src_width;
                prev_src_line <= next_src_line;
                prev_src_field <= next_src_field;
                line_ready    <= 0;
            end
        end

        if (I_fetch_done)
            line_ready <= 1;

        // At frame start, invalidate
        if (v_cnt == 0 && h_cnt == 0) begin
            prev_src_line  <= 10'h3FF;
            prev_src_field <= 0;
            line_ready     <= 0;
        end
    end
end

// ============================================================
// Pixel output
// ============================================================
// During active display, read from line buffer at scaled X position.
// Expand 12-bit Amiga RGB (4-bit per channel) to 24-bit (8-bit per channel)
// by replicating the 4-bit value: {nibble, nibble} gives 0x00-0xFF range.

always @(posedge pix_clk) begin
    if (de_w && I_input_valid)
        O_lb_rd_addr <= src_x_int;
    else
        O_lb_rd_addr <= 0;
end

// Extract RGB from line buffer data (format: {4'b0, R[3:0], G[3:0], B[3:0]})
wire [3:0] lb_r = I_lb_rd_data[11:8];
wire [3:0] lb_g = I_lb_rd_data[7:4];
wire [3:0] lb_b = I_lb_rd_data[3:0];

// Expand 4-bit to 8-bit by bit replication (0→0x00, F→0xFF)
wire [7:0] expanded_r = {lb_r, lb_r};
wire [7:0] expanded_g = {lb_g, lb_g};
wire [7:0] expanded_b = {lb_b, lb_b};

// When no valid input, show a blue background to indicate "no signal"
reg [7:0] out_r, out_g, out_b;

always @(posedge pix_clk or negedge rst_n) begin
    if (!rst_n) begin
        out_r <= 0;
        out_g <= 0;
        out_b <= 0;
    end else begin
        if (I_input_valid && line_ready) begin
            out_r <= expanded_r;
            out_g <= expanded_g;
            out_b <= expanded_b;
        end else begin
            // No signal indicator: dark blue
            out_r <= 8'd0;
            out_g <= 8'd0;
            out_b <= 8'd32;
        end
    end
end

assign O_data_r = out_r;
assign O_data_g = out_g;
assign O_data_b = out_b;

endmodule
