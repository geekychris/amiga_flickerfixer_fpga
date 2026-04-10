// ---------------------------------------------------------------------
// File name         : line_buffer.v
// Module name       : line_buffer
// Description       : Simple dual-port RAM for line buffering.
//                     Infers BSRAM on Gowin GW2A.
//                     Port A: write, Port B: read (independent clocks)
// ---------------------------------------------------------------------

module line_buffer #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 10  // 1024 pixels per line
)(
    // Write port
    input                       wr_clk,
    input                       wr_en,
    input  [ADDR_WIDTH-1:0]     wr_addr,
    input  [DATA_WIDTH-1:0]     wr_data,

    // Read port
    input                       rd_clk,
    input  [ADDR_WIDTH-1:0]     rd_addr,
    output reg [DATA_WIDTH-1:0] rd_data
);

localparam DEPTH = 1 << ADDR_WIDTH;

reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

// Write port
always @(posedge wr_clk) begin
    if (wr_en)
        mem[wr_addr] <= wr_data;
end

// Read port
always @(posedge rd_clk) begin
    rd_data <= mem[rd_addr];
end

endmodule
