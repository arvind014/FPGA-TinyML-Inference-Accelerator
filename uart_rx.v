`timescale 1ns / 1ps

module uart_rx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input clk,
    input rx,
    output reg [7:0] rx_data,
    output reg rx_done
);

    localparam CLOCKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam HALF_BIT = CLOCKS_PER_BIT / 2;

    // FSM States
    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam DATA  = 2'b10;
    localparam STOP  = 2'b11;

    reg [1:0] state = IDLE;
    reg [15:0] clk_count = 0;
    reg [2:0] bit_index = 0;

    // ----------------------------------------------------------------
    // STEP 1.2: DOUBLE-FLOP SYNCHRONIZER
    // ----------------------------------------------------------------
    // Synchronizes the external asynchronous 'rx' pin to the local clock domain.
    // This isolates the FSM from setup/hold violations and metastability.
    reg rx_sync0 = 1'b1;
    reg rx_sync1 = 1'b1;

    always @(posedge clk) begin
        rx_sync0 <= rx;
        rx_sync1 <= rx_sync0;
    end

    // ----------------------------------------------------------------
    // UART RECEIVER STATE MACHINE
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        case (state)
            IDLE: begin
                rx_done   <= 1'b0;
                clk_count <= 0;
                bit_index <= 0;
                
                // Read from the synchronized line (rx_sync1) instead of the raw pin (rx)
                if (rx_sync1 == 1'b0) begin // Start bit detected
                    state <= START;
                end
            end

            START: begin
                if (clk_count == HALF_BIT) begin
                    // Verify the start bit is still low at the mid-point sample
                    if (rx_sync1 == 1'b0) begin
                        clk_count <= 0;
                        state     <= DATA;
                    end else begin
                        state     <= IDLE; // False start glitch detection
                    end
                end else begin
                    clk_count <= clk_count + 1;
                end
            end

            DATA: begin
                if (clk_count == CLOCKS_PER_BIT - 1) begin
                    clk_count <= 0;
                    rx_data[bit_index] <= rx_sync1; // Sample data bit from synchronized line
                    
                    if (bit_index < 7) begin
                        bit_index <= bit_index + 1;
                    end else begin
                        state     <= STOP;
                    end
                end else begin
                    clk_count <= clk_count + 1;
                end
            end

            STOP: begin
                if (clk_count == CLOCKS_PER_BIT - 1) begin
                    rx_done <= 1'b1; // Pulse packet completion done flag
                    state   <= IDLE;
                end else begin
                    clk_count <= clk_count + 1;
                end
            end
            
            default: state <= IDLE;
        endcase
    end

endmodule