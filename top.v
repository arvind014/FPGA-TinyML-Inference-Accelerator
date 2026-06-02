`timescale 1ns / 1ps

module top(
    input clk,              // 100 MHz Basys3 clock
    input btnC,             // STEP 4.2: Center Pushbutton used as Hardware Reset (Active High)
    input RsRx,             // UART RX line
    output RsTx,            // UART TX line
    output [6:0] seg,       // 7-segment lines
    output [3:0] an,        // 7-segment anode lines
    output [15:0] led       // Diagnostic LEDs
);

    // Global Reset Configuration
    wire rst = btnC;

    wire [7:0] rx_data;
    wire rx_done;
    reg [9:0] write_addr = 10'd0;
    reg packet_complete = 1'b0;
    reg start_nn = 1'b0;
    reg pending_frame = 1'b0;

    wire [3:0] model_prediction;
    wire [6:0] model_confidence;
    wire nn_busy;
    wire nn_finished_pulse;

    // ----------------------------------------------------------------
    // STEP 4.1: Boost Baud Rate parameters to 460,800
    // ----------------------------------------------------------------
    uart_rx #(
        .CLK_FREQ(100_000_000),
        .BAUD_RATE(460_800)
    ) rx_inst (
        .clk(clk),
        .rx(RsRx),
        .rx_data(rx_data),
        .rx_done(rx_done)
    );

    // Address counter tracking with synchronous reset link
    always @(posedge clk) begin
        if (rst) begin
            write_addr <= 10'd0;
            packet_complete <= 1'b0;
        end else if (rx_done) begin
            if (write_addr == 10'd783) begin
                write_addr <= 10'd0;
                packet_complete <= 1'b1;
            end else begin
                write_addr <= write_addr + 10'd1;
                packet_complete <= 1'b0;
            end
        end else begin
            packet_complete <= 1'b0;
        end
    end

    // Trigger state machine control tracking logic
    always @(posedge clk) begin
        if (rst) begin
            pending_frame <= 1'b0;
            start_nn      <= 1'b0;
        end else begin
            if (packet_complete) begin
                pending_frame <= 1'b1;
            end
            
            if (pending_frame && !nn_busy) begin
                start_nn      <= 1'b1;
                pending_frame <= 1'b0;
            end else begin
                start_nn      <= 1'b0;
            end
        end
    end

    // TinyML Accelerator Instance Core Linked to Reset Tree
    nn_core core_inst (
        .clk(clk),
        .rst(rst),          // Connected global hardware reset signal
        .start(start_nn),
        .rx_done(rx_done),
        .rx_byte(rx_data),
        .rx_addr(write_addr),
        .prediction(model_prediction),
        .done(nn_finished_pulse),
        .busy(nn_busy),
        .confidence(model_confidence)
    );

    // Dynamic Thermometer Confidence Display Code Block
    reg [14:0] confidence_bar;
    always @(*) begin
        if (model_confidence >= 7'd94)      confidence_bar = 15'b111_1111_1111_1111;
        else if (model_confidence >= 7'd88) confidence_bar = 15'b011_1111_1111_1111;
        else if (model_confidence >= 7'd82) confidence_bar = 15'b001_1111_1111_1111;
        else if (model_confidence >= 7'd75) confidence_bar = 15'b000_1111_1111_1111;
        else if (model_confidence >= 7'd68) confidence_bar = 15'b000_0111_1111_1111;
        else if (model_confidence >= 7'd62) confidence_bar = 15'b000_0011_1111_1111;
        else if (model_confidence >= 7'd55) confidence_bar = 15'b000_0001_1111_1111;
        else if (model_confidence >= 7'd50) confidence_bar = 15'b000_0000_1111_1111;
        else if (model_confidence >= 7'd42) confidence_bar = 15'b000_0000_0111_1111;
        else if (model_confidence >= 7'd35) confidence_bar = 15'b000_0000_0011_1111;
        else if (model_confidence >= 7'd28) confidence_bar = 15'b000_0000_0001_1111;
        else if (model_confidence >= 7'd20) confidence_bar = 15'b000_0000_0000_1111;
        else if (model_confidence >= 7'd14) confidence_bar = 15'b000_0000_0000_0111;
        else if (model_confidence >= 7'd8)  confidence_bar = 15'b000_0000_0000_0011;
        else if (model_confidence > 7'd0)   confidence_bar = 15'b000_0000_0000_0001;
        else                                confidence_bar = 15'b000_0000_0000_0000;
    end

    assign led[15]   = nn_busy;
    assign led[14:0] = confidence_bar;

    seven_seg display_inst (
        .clk(clk),
        .prediction(model_prediction),
        .confidence(model_confidence),
        .seg(seg),
        .an(an)
    );

    // Outbound response TX machine tuned to 460,800 Baud
    reg        uart_start = 1'b0;
    reg  [7:0] uart_data;
    wire       uart_busy;
    reg  [1:0] send_state = 0;
    reg        tx_pending = 1'b0;

    uart_tx #(
        .CLK_FREQ(100_000_000),
        .BAUD(460_800)
    ) tx_inst (
        .clk(clk),
        .start(uart_start),
        .data_in(uart_data),
        .tx(RsTx),
        .busy(uart_busy)
    );

    always @(posedge clk) begin
        if (rst) begin
            uart_start <= 1'b0;
            tx_pending <= 1'b0;
            send_state <= 0;
        end else begin
            if (nn_finished_pulse) begin
                tx_pending <= 1'b1;
            end

            case (send_state)
                0: begin
                    uart_start <= 1'b0;
                    if (tx_pending && !uart_busy) begin
                        uart_data  <= {4'd0, model_prediction};
                        uart_start <= 1'b1;
                        send_state <= 1;
                    end
                end
                1: begin
                    uart_start <= 1'b0;
                    if (!uart_busy && !uart_start) begin
                        uart_data  <= {1'b0, model_confidence};
                        uart_start <= 1'b1;
                        send_state <= 2;
                    end
                end
                2: begin
                    uart_start <= 1'b0;
                    if (!uart_busy && !uart_start) begin
                        tx_pending <= 1'b0;
                        send_state <= 0;
                    end
                end
                default: send_state <= 0;
            endcase
        end
    end

endmodule