// ---------------------------------------------------------------------
// File name         : frame_buffer_ctrl.v
// Module name       : frame_buffer_ctrl
// Description       : DDR3 frame buffer controller with read/write
//                     arbitration for the Amiga flicker fixer.
//
//                     Manages 4 field buffers in DDR3 (ping-pong for
//                     each field parity) and provides line-oriented
//                     read access through on-chip line buffers.
//
//                     Write side: accepts pixels from denise_capture
//                     Read side:  provides scaled line data to output_gen
//
// Memory layout (DDR3, 16-bit words):
//   Field 0 (even ping): 0x000000 - 0x0FFFFF
//   Field 1 (even pong): 0x100000 - 0x1FFFFF
//   Field 2 (odd ping):  0x200000 - 0x2FFFFF
//   Field 3 (odd pong):  0x300000 - 0x3FFFFF
//
//   Line stride: 2048 pixels (2048 words = 4096 bytes)
//   addr = base + (line * 2048) + pixel
//
// DDR3 controller interface (nand2mario style):
//   16-bit data, 26-bit address, single-word access
// ---------------------------------------------------------------------

module frame_buffer_ctrl (
    // DDR3 controller interface (100 MHz domain)
    input              clk_mem,        // 100 MHz DDR3 user clock
    input              rst_n,

    output reg [25:0]  O_ddr_addr,
    output reg [15:0]  O_ddr_din,
    input  [15:0]      I_ddr_dout,
    output reg         O_ddr_rd,
    output reg         O_ddr_wr,
    input              I_ddr_busy,
    input              I_ddr_data_ready,

    // Write interface (from denise_capture, via async FIFO)
    // Directly in mem clock domain after FIFO
    input              I_wr_req,
    input  [11:0]      I_wr_rgb,       // {R[3:0], G[3:0], B[3:0]}
    input  [10:0]      I_wr_x,
    input  [9:0]       I_wr_y,
    input              I_wr_field_id,   // 0=even, 1=odd
    output             O_wr_ack,

    // Field buffer management
    input              I_field_done,    // Pulse when field capture completes
    input              I_field_parity,  // Parity of completed field

    // Read interface (from output_gen, via async FIFO)
    // Request a line to be loaded into line buffer
    input              I_rd_line_req,
    input  [9:0]       I_rd_line_num,
    input              I_rd_field_sel,  // Which field parity to read
    input  [10:0]      I_rd_line_width, // Pixels to read
    output reg         O_rd_line_done,

    // Line buffer read port (directly accessible by output_gen)
    input  [10:0]      I_lb_rd_addr,
    output [15:0]      O_lb_rd_data,

    // Status
    output reg [1:0]   O_even_rd_buf,  // Which even buffer is readable (0 or 1)
    output reg [1:0]   O_odd_rd_buf    // Which odd buffer is readable (2 or 3)
);

// ============================================================
// Field buffer index management (ping-pong per parity)
// ============================================================
// Even field uses buffers 0, 1 (base addresses 0x000000, 0x100000)
// Odd field uses buffers 2, 3 (base addresses 0x200000, 0x300000)

reg even_wr_sel; // 0 = write to buf 0, 1 = write to buf 1
reg odd_wr_sel;  // 0 = write to buf 2, 1 = write to buf 3

initial begin
    even_wr_sel = 0;
    odd_wr_sel  = 0;
    O_even_rd_buf = 2'd1; // Read from buf 1 initially
    O_odd_rd_buf  = 2'd3; // Read from buf 3 initially
end

always @(posedge clk_mem or negedge rst_n) begin
    if (!rst_n) begin
        even_wr_sel   <= 0;
        odd_wr_sel    <= 0;
        O_even_rd_buf <= 2'd1;
        O_odd_rd_buf  <= 2'd3;
    end else if (I_field_done) begin
        if (!I_field_parity) begin
            // Even field completed: swap even buffers
            even_wr_sel   <= ~even_wr_sel;
            O_even_rd_buf <= even_wr_sel ? 2'd1 : 2'd0;
        end else begin
            // Odd field completed: swap odd buffers
            odd_wr_sel   <= ~odd_wr_sel;
            O_odd_rd_buf <= odd_wr_sel ? 2'd3 : 2'd2;
        end
    end
end

// Base address for each buffer (in 16-bit word address space)
function [25:0] buf_base_addr;
    input [1:0] buf_id;
    begin
        buf_base_addr = {buf_id, 18'b0, 6'b0}; // buf_id * 0x100000 (in words)
    end
endfunction

// Compute write base address from field_id
wire [25:0] wr_base = I_wr_field_id ?
    (odd_wr_sel  ? 26'h300000 : 26'h200000) :
    (even_wr_sel ? 26'h100000 : 26'h000000);

// Compute read base address from field select and current readable buffer
wire [25:0] rd_base = I_rd_field_sel ?
    {O_odd_rd_buf[1:0],  24'b0} :
    {O_even_rd_buf[1:0], 24'b0};

// ============================================================
// Address calculation
// ============================================================
// Line stride = 2048 words (shift left by 11)
wire [25:0] wr_addr = wr_base + ({15'b0, I_wr_y} << 11) + {15'b0, I_wr_x};

// ============================================================
// Line buffer for read path
// ============================================================
// Two line buffers (ping-pong): fill one while output reads other
reg        lb_wr_en;
reg [10:0] lb_wr_addr;
reg [15:0] lb_wr_data;

line_buffer #(
    .DATA_WIDTH(16),
    .ADDR_WIDTH(11)
) u_line_buffer (
    .wr_clk  (clk_mem),
    .wr_en   (lb_wr_en),
    .wr_addr (lb_wr_addr),
    .wr_data (lb_wr_data),
    .rd_clk  (clk_mem),      // Same clock - output_gen crosses domain externally
    .rd_addr (I_lb_rd_addr),
    .rd_data (O_lb_rd_data)
);

// ============================================================
// State machine for DDR3 arbitration
// ============================================================
localparam ST_IDLE      = 3'd0;
localparam ST_WRITE     = 3'd1;
localparam ST_WRITE_WAIT = 3'd2;
localparam ST_READ_START = 3'd3;
localparam ST_READ_WAIT = 3'd4;
localparam ST_READ_STORE = 3'd5;

reg [2:0]  state;
reg [10:0] rd_pixel_cnt;  // Current pixel in line read
reg [10:0] rd_line_width_r;
reg [25:0] rd_line_base;  // Base address for current read line

assign O_wr_ack = (state == ST_WRITE) && !I_ddr_busy;

always @(posedge clk_mem or negedge rst_n) begin
    if (!rst_n) begin
        state          <= ST_IDLE;
        O_ddr_addr     <= 0;
        O_ddr_din      <= 0;
        O_ddr_rd       <= 0;
        O_ddr_wr       <= 0;
        O_rd_line_done <= 0;
        lb_wr_en       <= 0;
        lb_wr_addr     <= 0;
        lb_wr_data     <= 0;
        rd_pixel_cnt   <= 0;
        rd_line_width_r <= 0;
        rd_line_base   <= 0;
    end else begin
        // Default: deassert strobes
        O_ddr_rd       <= 0;
        O_ddr_wr       <= 0;
        O_rd_line_done <= 0;
        lb_wr_en       <= 0;

        case (state)
            ST_IDLE: begin
                // Priority: line read requests > pixel writes
                // (reads are time-critical for output timing)
                if (I_rd_line_req) begin
                    state          <= ST_READ_START;
                    rd_pixel_cnt   <= 0;
                    rd_line_width_r <= I_rd_line_width;
                    rd_line_base   <= rd_base + ({16'b0, I_rd_line_num} << 11);
                end else if (I_wr_req && !I_ddr_busy) begin
                    state      <= ST_WRITE;
                    O_ddr_addr <= wr_addr;
                    O_ddr_din  <= {4'b0, I_wr_rgb};
                    O_ddr_wr   <= 1;
                end
            end

            ST_WRITE: begin
                if (!I_ddr_busy) begin
                    state <= ST_IDLE;
                end else begin
                    // Stay in write state, wait for not busy
                    state <= ST_WRITE_WAIT;
                end
            end

            ST_WRITE_WAIT: begin
                if (!I_ddr_busy)
                    state <= ST_IDLE;
            end

            ST_READ_START: begin
                if (!I_ddr_busy) begin
                    O_ddr_addr <= rd_line_base + {15'b0, rd_pixel_cnt};
                    O_ddr_rd   <= 1;
                    state      <= ST_READ_WAIT;
                end
            end

            ST_READ_WAIT: begin
                if (I_ddr_data_ready) begin
                    // Store read data in line buffer
                    lb_wr_en   <= 1;
                    lb_wr_addr <= rd_pixel_cnt;
                    lb_wr_data <= I_ddr_dout;
                    rd_pixel_cnt <= rd_pixel_cnt + 1'b1;

                    if (rd_pixel_cnt >= rd_line_width_r - 1'b1) begin
                        O_rd_line_done <= 1;
                        state <= ST_IDLE;
                    end else begin
                        state <= ST_READ_START;
                    end
                end
            end

            default: state <= ST_IDLE;
        endcase
    end
end

endmodule
