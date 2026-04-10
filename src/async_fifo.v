// ---------------------------------------------------------------------
// File name         : async_fifo.v
// Module name       : async_fifo
// Description       : Parameterized dual-clock FIFO using gray-code
//                     pointers for safe clock domain crossing.
//                     Infers dual-port block RAM on Gowin GW2A.
// ---------------------------------------------------------------------

module async_fifo #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 4   // FIFO depth = 2^ADDR_WIDTH
)(
    // Write side
    input                       wr_clk,
    input                       wr_rst_n,
    input                       wr_en,
    input  [DATA_WIDTH-1:0]     wr_data,
    output                      wr_full,

    // Read side
    input                       rd_clk,
    input                       rd_rst_n,
    input                       rd_en,
    output [DATA_WIDTH-1:0]     rd_data,
    output                      rd_empty
);

localparam DEPTH = 1 << ADDR_WIDTH;

// Dual-port RAM
reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

// Write pointer (binary and gray)
reg [ADDR_WIDTH:0] wr_ptr_bin;
reg [ADDR_WIDTH:0] wr_ptr_gray;
wire [ADDR_WIDTH:0] wr_ptr_bin_next;
wire [ADDR_WIDTH:0] wr_ptr_gray_next;

// Read pointer (binary and gray)
reg [ADDR_WIDTH:0] rd_ptr_bin;
reg [ADDR_WIDTH:0] rd_ptr_gray;
wire [ADDR_WIDTH:0] rd_ptr_bin_next;
wire [ADDR_WIDTH:0] rd_ptr_gray_next;

// Synchronized pointers
reg [ADDR_WIDTH:0] wr_ptr_gray_rd1, wr_ptr_gray_rd2; // wr gray ptr synced to rd clk
reg [ADDR_WIDTH:0] rd_ptr_gray_wr1, rd_ptr_gray_wr2; // rd gray ptr synced to wr clk

// Next pointer values
assign wr_ptr_bin_next  = wr_ptr_bin + (wr_en & ~wr_full);
assign wr_ptr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;

assign rd_ptr_bin_next  = rd_ptr_bin + (rd_en & ~rd_empty);
assign rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;

// Full and empty flags
assign wr_full  = (wr_ptr_gray == {~rd_ptr_gray_wr2[ADDR_WIDTH:ADDR_WIDTH-1],
                                     rd_ptr_gray_wr2[ADDR_WIDTH-2:0]});
assign rd_empty = (rd_ptr_gray == wr_ptr_gray_rd2);

// Write logic
always @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
        wr_ptr_bin  <= 0;
        wr_ptr_gray <= 0;
    end else begin
        wr_ptr_bin  <= wr_ptr_bin_next;
        wr_ptr_gray <= wr_ptr_gray_next;
    end
end

always @(posedge wr_clk) begin
    if (wr_en && !wr_full)
        mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
end

// Read logic
always @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
        rd_ptr_bin  <= 0;
        rd_ptr_gray <= 0;
    end else begin
        rd_ptr_bin  <= rd_ptr_bin_next;
        rd_ptr_gray <= rd_ptr_gray_next;
    end
end

assign rd_data = mem[rd_ptr_bin[ADDR_WIDTH-1:0]];

// Synchronize write pointer to read clock domain
always @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
        wr_ptr_gray_rd1 <= 0;
        wr_ptr_gray_rd2 <= 0;
    end else begin
        wr_ptr_gray_rd1 <= wr_ptr_gray;
        wr_ptr_gray_rd2 <= wr_ptr_gray_rd1;
    end
end

// Synchronize read pointer to write clock domain
always @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
        rd_ptr_gray_wr1 <= 0;
        rd_ptr_gray_wr2 <= 0;
    end else begin
        rd_ptr_gray_wr1 <= rd_ptr_gray;
        rd_ptr_gray_wr2 <= rd_ptr_gray_wr1;
    end
end

endmodule
