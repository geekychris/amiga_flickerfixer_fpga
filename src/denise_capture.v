// ---------------------------------------------------------------------
// File name         : denise_capture.v
// Module name       : denise_capture
// Description       : Captures digital RGB and sync signals from the
//                     Commodore Amiga Super DENISE (8373) chip.
//                     Includes composite sync separation, PAL/NTSC
//                     detection, interlace detection, and field
//                     identification. Outputs a pixel stream with
//                     coordinates suitable for frame buffer storage.
//
// Signals from DENISE:
//   R[3:0], G[3:0], B[3:0] - 12-bit digital RGB (pins 20-31)
//   nCSYNC                  - Composite sync, active low (pin 32)
//   nZD                     - Zero detect / blanking (pin 33)
//   CDAC                    - Clock DAC, ~7MHz 90deg shifted (pin 34)
//   CLK_7M                  - 7.09/7.16 MHz pixel clock (pin 35)
//
// All DENISE signals are active 5V TTL - external level shifters
// (e.g., 74LVC245) are required before connecting to the FPGA.
// ---------------------------------------------------------------------

module denise_capture (
    input              clk_28m,       // 28 MHz capture clock (from PLL)
    input              rst_n,

    // DENISE digital interface (active after level shifting to 3.3V)
    input  [3:0]       I_denise_r,    // Red 4-bit
    input  [3:0]       I_denise_g,    // Green 4-bit
    input  [3:0]       I_denise_b,    // Blue 4-bit
    input              I_denise_csync_n, // Composite sync (active low)
    input              I_denise_zd_n, // Zero detect (active low = blanking/bg)
    input              I_denise_7m,   // 7 MHz clock reference
    input              I_denise_cdac, // CDAC clock reference (ECS)

    // Captured pixel output
    output reg         O_pix_valid,   // Pixel data valid (active video only)
    output reg [11:0]  O_pix_rgb,     // {R[3:0], G[3:0], B[3:0]}
    output reg [10:0]  O_pix_x,       // Horizontal pixel position (0-2047)
    output reg [9:0]   O_pix_y,       // Vertical line position (0-1023)

    // Sync and mode outputs
    output reg         O_hsync,       // Extracted horizontal sync
    output reg         O_vsync,       // Extracted vertical sync
    output reg         O_field_id,    // 0 = even (short frame), 1 = odd (long frame)
    output reg         O_is_pal,      // 1 = PAL, 0 = NTSC
    output reg         O_is_interlaced, // 1 = interlaced mode detected
    output reg         O_frame_start, // Pulse at start of each field
    output reg         O_line_start,  // Pulse at start of each active line
    output reg [10:0]  O_active_width, // Detected active pixels per line
    output reg [9:0]   O_active_height // Detected active lines per field
);

// ============================================================
// Input synchronization (double-flop for metastability)
// ============================================================
reg [3:0] r_sync1, r_sync2;
reg [3:0] g_sync1, g_sync2;
reg [3:0] b_sync1, b_sync2;
reg       csync_n_s1, csync_n_s2;
reg       zd_n_s1, zd_n_s2;
reg       clk7m_s1, clk7m_s2, clk7m_s3;

always @(posedge clk_28m or negedge rst_n) begin
    if (!rst_n) begin
        r_sync1 <= 0; r_sync2 <= 0;
        g_sync1 <= 0; g_sync2 <= 0;
        b_sync1 <= 0; b_sync2 <= 0;
        csync_n_s1 <= 1; csync_n_s2 <= 1;
        zd_n_s1 <= 1; zd_n_s2 <= 1;
        clk7m_s1 <= 0; clk7m_s2 <= 0; clk7m_s3 <= 0;
    end else begin
        r_sync1 <= I_denise_r; r_sync2 <= r_sync1;
        g_sync1 <= I_denise_g; g_sync2 <= g_sync1;
        b_sync1 <= I_denise_b; b_sync2 <= b_sync1;
        csync_n_s1 <= I_denise_csync_n; csync_n_s2 <= csync_n_s1;
        zd_n_s1 <= I_denise_zd_n; zd_n_s2 <= zd_n_s1;
        clk7m_s1 <= I_denise_7m; clk7m_s2 <= clk7m_s1; clk7m_s3 <= clk7m_s2;
    end
end

// Active-high sync for internal use
wire csync = ~csync_n_s2;
wire blanking = ~zd_n_s2;
wire clk7m_rising = clk7m_s2 & ~clk7m_s3;

// ============================================================
// Composite Sync Separator
// ============================================================
// Strategy: measure CSYNC low pulse width to distinguish
// normal HSYNC (~4.7us = ~132 clocks @28MHz) from
// equalization/serration pulses (~2.35us = ~66 clocks).
// Also detect VSYNC region by tracking pulse patterns.

localparam HSYNC_THRESHOLD = 11'd90;   // Pulses shorter than this are eq/serration
localparam LINE_PERIOD_PAL = 16'd1820; // ~64us at 28.375MHz (PAL line)
localparam LINE_PERIOD_NTSC = 16'd1816; // ~63.5us at 28.636MHz (NTSC line)
localparam HALF_LINE = 16'd900;        // Half-line threshold
localparam VSYNC_LINE_THRESHOLD = 10'd280; // Lines > this = PAL

reg [15:0] csync_cnt;      // Counter during CSYNC active (low)
reg [15:0] line_cnt;        // Counter since last HSYNC rising edge
reg        csync_prev;
reg        hsync_raw;
reg        in_vsync_region;
reg [3:0]  short_pulse_cnt; // Count consecutive short sync pulses
reg [15:0] last_line_period; // Measured period between HSYNCs

// CSYNC pulse width measurement
always @(posedge clk_28m or negedge rst_n) begin
    if (!rst_n) begin
        csync_cnt <= 0;
        csync_prev <= 0;
    end else begin
        csync_prev <= csync;
        if (csync)
            csync_cnt <= csync_cnt + 1'b1;
        else
            csync_cnt <= 0;
    end
end

// Detect HSYNC (rising edge of CSYNC after a sufficiently long pulse)
wire csync_rising = csync & ~csync_prev;
wire csync_falling = ~csync & csync_prev;

always @(posedge clk_28m or negedge rst_n) begin
    if (!rst_n) begin
        hsync_raw <= 0;
        short_pulse_cnt <= 0;
        in_vsync_region <= 0;
        line_cnt <= 0;
        last_line_period <= LINE_PERIOD_PAL;
    end else begin
        // Line period counter
        line_cnt <= line_cnt + 1'b1;

        if (csync_falling) begin
            // End of sync pulse - classify it
            if (csync_cnt >= HSYNC_THRESHOLD) begin
                // Normal HSYNC pulse
                hsync_raw <= 1;
                short_pulse_cnt <= 0;
                last_line_period <= line_cnt;
                line_cnt <= 0;
                if (short_pulse_cnt >= 4)
                    in_vsync_region <= 0; // Leaving VSYNC
            end else begin
                // Short pulse (equalization or serration)
                hsync_raw <= 0;
                short_pulse_cnt <= short_pulse_cnt + 1'b1;
                if (short_pulse_cnt >= 3)
                    in_vsync_region <= 1; // Entering VSYNC region
                if (line_cnt > HALF_LINE) begin
                    line_cnt <= 0;
                    last_line_period <= line_cnt;
                end
            end
        end else begin
            hsync_raw <= 0;
        end
    end
end

// VSYNC output: stays high during the vertical sync region
// HSYNC output: pulse at each line start
always @(posedge clk_28m or negedge rst_n) begin
    if (!rst_n) begin
        O_hsync <= 0;
        O_vsync <= 0;
    end else begin
        O_hsync <= hsync_raw;
        O_vsync <= in_vsync_region;
    end
end

// ============================================================
// Line and Field Counting
// ============================================================
reg [9:0] field_line_cnt;   // Lines in current field
reg [9:0] prev_field_lines; // Lines in previous field
reg       vsync_prev;
reg       field_id_raw;

always @(posedge clk_28m or negedge rst_n) begin
    if (!rst_n) begin
        field_line_cnt <= 0;
        prev_field_lines <= 0;
        vsync_prev <= 0;
        field_id_raw <= 0;
        O_is_pal <= 0;
        O_is_interlaced <= 0;
        O_frame_start <= 0;
    end else begin
        vsync_prev <= in_vsync_region;
        O_frame_start <= 0;

        if (hsync_raw) begin
            if (!in_vsync_region)
                field_line_cnt <= field_line_cnt + 1'b1;
        end

        // Detect VSYNC falling edge (start of new field)
        if (vsync_prev & ~in_vsync_region) begin
            O_frame_start <= 1;
            prev_field_lines <= field_line_cnt;
            field_line_cnt <= 0;

            // PAL/NTSC detection based on line count
            // PAL fields have ~288-313 lines, NTSC have ~240-263 lines
            O_is_pal <= (field_line_cnt > VSYNC_LINE_THRESHOLD);

            // Interlace detection: if consecutive fields have different
            // line counts (262 vs 263 for NTSC, 312 vs 313 for PAL)
            if (prev_field_lines != field_line_cnt && prev_field_lines != 0)
                O_is_interlaced <= 1;
            else
                O_is_interlaced <= 0;

            // Field ID: long frame = odd field (LOF=1)
            // PAL: 313 lines = long, 312 = short
            // NTSC: 263 lines = long, 262 = short
            if (O_is_pal)
                field_id_raw <= (field_line_cnt >= 10'd312);
            else
                field_id_raw <= (field_line_cnt >= 10'd262);
        end
    end
end

always @(posedge clk_28m or negedge rst_n) begin
    if (!rst_n)
        O_field_id <= 0;
    else if (vsync_prev & ~in_vsync_region)
        O_field_id <= field_id_raw;
end

// ============================================================
// Pixel Position Tracking
// ============================================================
// Track X (horizontal) and Y (vertical) positions within active area.
// Active area is defined by blanking signal (nZD low = blanking).

reg [10:0] h_pixel_cnt;    // Horizontal pixel counter (28MHz ticks since HSYNC)
reg [9:0]  v_line_cnt;     // Vertical active line counter
reg        blanking_prev;
reg        active_line;     // Currently in an active line
reg [10:0] active_pixel_cnt; // Pixels in current active region
reg [10:0] max_active_width;
reg [9:0]  max_active_height;

// Horizontal position counter (resets on HSYNC)
always @(posedge clk_28m or negedge rst_n) begin
    if (!rst_n) begin
        h_pixel_cnt <= 0;
    end else begin
        if (hsync_raw)
            h_pixel_cnt <= 0;
        else
            h_pixel_cnt <= h_pixel_cnt + 1'b1;
    end
end

// Detect active line transitions using blanking/nZD
wire blanking_falling = blanking_prev & ~blanking; // End of blanking = start of active
wire blanking_rising = ~blanking_prev & blanking;  // Start of blanking = end of active

always @(posedge clk_28m or negedge rst_n) begin
    if (!rst_n) begin
        blanking_prev <= 1;
        active_line <= 0;
        active_pixel_cnt <= 0;
        v_line_cnt <= 0;
        max_active_width <= 0;
        max_active_height <= 0;
        O_line_start <= 0;
    end else begin
        blanking_prev <= blanking;
        O_line_start <= 0;

        if (vsync_prev & ~in_vsync_region) begin
            // New field: reset vertical counter, store measurements
            O_active_width <= max_active_width;
            O_active_height <= max_active_height;
            max_active_width <= 0;
            max_active_height <= 0;
            v_line_cnt <= 0;
        end

        if (hsync_raw) begin
            // New line
            active_pixel_cnt <= 0;
            if (active_line && !in_vsync_region) begin
                v_line_cnt <= v_line_cnt + 1'b1;
                if (v_line_cnt + 1'b1 > max_active_height)
                    max_active_height <= v_line_cnt + 1'b1;
            end
            active_line <= 0;
        end

        if (blanking_falling && !in_vsync_region) begin
            // Start of active video on this line
            active_line <= 1;
            active_pixel_cnt <= 0;
            O_line_start <= 1;
        end

        if (!blanking && !in_vsync_region && active_line) begin
            active_pixel_cnt <= active_pixel_cnt + 1'b1;
            if (active_pixel_cnt + 1'b1 > max_active_width)
                max_active_width <= active_pixel_cnt + 1'b1;
        end
    end
end

// ============================================================
// Pixel Output
// ============================================================
always @(posedge clk_28m or negedge rst_n) begin
    if (!rst_n) begin
        O_pix_valid <= 0;
        O_pix_rgb <= 12'd0;
        O_pix_x <= 0;
        O_pix_y <= 0;
    end else begin
        // Output valid pixel during active video (not blanking, not VSYNC)
        O_pix_valid <= ~blanking & ~in_vsync_region & active_line;
        O_pix_rgb <= {r_sync2, g_sync2, b_sync2};
        O_pix_x <= active_pixel_cnt;
        O_pix_y <= v_line_cnt;
    end
end

endmodule
