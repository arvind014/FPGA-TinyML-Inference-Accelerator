`timescale 1ns / 1ps
module uart_tx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD     = 115200
)(
    input        clk,
    input        start,         
    input  [7:0] data_in,       
    output reg   tx = 1'b1,     
    output reg   busy = 1'b0
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD;
    reg [31:0] clk_count = 0;
    reg [3:0]  bit_index = 0;
    reg [9:0]  tx_shift  = 10'b1111111111;

    always @(posedge clk) begin
        if (start && !busy) begin
            tx_shift  <= {1'b1, data_in, 1'b0}; // Stop (1), Data (8), Start (0)
            tx        <= 1'b0;                  // Instantly drive the Start Bit!
            busy      <= 1'b1;
            clk_count <= 0;
            bit_index <= 1;                     // Next bit to handle will be index 1
        end else if (busy) begin
            if (clk_count < CLKS_PER_BIT - 1) begin
                clk_count <= clk_count + 1;
            end else begin
                clk_count <= 0;
                if (bit_index < 10) begin
                    tx        <= tx_shift[bit_index];
                    bit_index <= bit_index + 1;
                end else begin
                    busy <= 1'b0;               // Finished transmitting all 10 bits
                end
            end
        end else begin
            tx <= 1'b1; // Maintain Idle
        end
    end
endmodule