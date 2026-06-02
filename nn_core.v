`timescale 1ns / 1ps

module nn_core(
    input clk,
    input rst,                     // STEP 4.2: Global Synchronous Reset Signal
    input start,

    input rx_done,
    input [7:0] rx_byte,
    input [9:0] rx_addr,

    output reg [3:0] prediction   = 4'd0,
    output reg       done         = 1'b0,
    output reg       busy         = 1'b0,
    output reg [6:0] confidence   = 7'd0
);

    // ----------------------------------------------------
    // Image RAM banks (4-way parallel distribution layout)
    // ----------------------------------------------------
    reg [7:0] image_ram0 [0:195];
    reg [7:0] image_ram1 [0:195];
    reg [7:0] image_ram2 [0:195];
    reg [7:0] image_ram3 [0:195];

    // Inbound stream address router interface logic
    always @(posedge clk) begin
        if (rx_done) begin
            case (rx_addr[1:0])
                2'b00: image_ram0[rx_addr[9:2]] <= rx_byte;
                2'b01: image_ram1[rx_addr[9:2]] <= rx_byte;
                2'b10: image_ram2[rx_addr[9:2]] <= rx_byte;
                2'b11: image_ram3[rx_addr[9:2]] <= rx_byte;
            endcase
        end
    end

    // ----------------------------------------------------
    // Controller registers and routing nodes
    // ----------------------------------------------------
    localparam IDLE     = 3'b000;
    localparam RESETMAC = 3'b001;
    localparam RUN      = 3'b010;
    localparam FLUSH1   = 3'b011;
    localparam FLUSH2   = 3'b100;
    localparam FLUSH3   = 3'b101;
    localparam EVAL     = 3'b110;

    reg [2:0] state = IDLE;
    reg [3:0] neuron_ptr = 4'd0;
    reg [7:0] pixel_ptr  = 8'd0;

    // Fixed-point signed activation scoring arrays
    reg signed [31:0] highest_score = 32'sh80000000;
    reg signed [31:0] scores [0:9];

    // ----------------------------------------------------
    // BRAM ROM Array Weight Layout Registrations
    // ----------------------------------------------------
    reg signed [7:0] weight_rom0 [0:1959];
    reg signed [7:0] weight_rom1 [0:1959];
    reg signed [7:0] weight_rom2 [0:1959];
    reg signed [7:0] weight_rom3 [0:1959];
    reg signed [7:0] bias_rom   [0:9];

    initial begin
        $readmemh("weights_layer1_b0.mem", weight_rom0);
        $readmemh("weights_layer1_b1.mem", weight_rom1);
        $readmemh("weights_layer1_b2.mem", weight_rom2);
        $readmemh("weights_layer1_b3.mem", weight_rom3);
        $readmemh("biases_layer1.mem", bias_rom);
    end

    // Pipeline Data Pipeline Interface Nodes
    reg  [7:0] p0, p1, p2, p3;
    reg signed [7:0] w0, w1, w2, w3;
    reg signed [31:0] current_bias = 32'sd0;
    reg reset_mac  = 1'b0;
    reg enable_mac = 1'b0;
    wire signed [31:0] mac_out;
    
    // Quantized Image Input Vector Sign Conversion Logic
    wire signed [7:0] p0_signed = (p0 > 8'd0) ? 8'sd1 : -8'sd1;
    wire signed [7:0] p1_signed = (p1 > 8'd0) ? 8'sd1 : -8'sd1;
    wire signed [7:0] p2_signed = (p2 > 8'd0) ? 8'sd1 : -8'sd1;
    wire signed [7:0] p3_signed = (p3 > 8'd0) ? 8'sd1 : -8'sd1;

    // Sub-module Multi-Way MAC Instantiation
    mac_unit_4way mac_inst (
        .clk(clk),
        .reset(reset_mac),
        .enable(enable_mac),
        .bias_val(current_bias),
        .p0(p0_signed),
        .p1(p1_signed),
        .p2(p2_signed),
        .p3(p3_signed),
        .w0(w0),
        .w1(w1),
        .w2(w2),
        .w3(w3),
        .accumulator(mac_out)
    );

    // Memory routing combinations linking addresses to active tracking registers
    wire [11:0] weight_addr = (neuron_ptr * 196) + pixel_ptr;

    always @(posedge clk) begin
        p0 <= image_ram0[pixel_ptr];
        p1 <= image_ram1[pixel_ptr];
        p2 <= image_ram2[pixel_ptr];
        p3 <= image_ram3[pixel_ptr];
        w0 <= weight_rom0[weight_addr];
        w1 <= weight_rom1[weight_addr];
        w2 <= weight_rom2[weight_addr];
        w3 <= weight_rom3[weight_addr];
    end

    // Exponential approximation function mapping node for softMax execution loops
    function automatic [31:0] exp_approx(input signed [31:0] x);
        reg signed [31:0] shifted;
        begin
            shifted = x >>> 6; // Balance scaling factor matching quantization configurations
            if (shifted < -32'sd8)   exp_approx = 32'd0;
            else if (shifted >= 32'sd4) exp_approx = 32'd1000;
            else begin
                case (shifted)
                    -32'sd8: exp_approx = 32'd0;
                    -32'sd7: exp_approx = 32'd1;
                    -32'sd6: exp_approx = 32'd2;
                    -32'sd5: exp_approx = 32'd7;
                    -32'sd4: exp_approx = 32'd18;
                    -32'sd3: exp_approx = 32'd50;
                    -32'sd2: exp_approx = 32'd135;
                    -32'sd1: exp_approx = 32'd368;
                     32'sd0: exp_approx = 32'd1000;
                     32'sd1: exp_approx = 32'd2718;
                     32'sd2: exp_approx = 32'd7389;
                     32'sd3: exp_approx = 32'd20086;
                    default: exp_approx = 32'd0;
                endcase
            end
        end
    endfunction

    integer i;
    reg [31:0] sum_exp;
    reg [31:0] top_exp;
    reg signed [31:0] final_highest_score;

    // ----------------------------------------------------
    // ACCELERATOR CORE STATE MACHINE INTEGRATED WITH RESET
    // ----------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            // Clear all structural control state data properties 
            state               <= IDLE;
            neuron_ptr          <= 4'd0;
            pixel_ptr           <= 8'd0;
            highest_score       <= 32'sh80000000;
            prediction          <= 4'd0;
            confidence          <= 7'd0;
            done                <= 1'b0;
            busy                <= 1'b0;
            current_bias        <= 32'sd0;
            reset_mac           <= 1'b0;
            enable_mac          <= 1'b0;
            
            // Safe initialize values within the internal tracking array
            for (i = 0; i < 10; i = i + 1) begin
                scores[i] <= 32'sd0;
            end
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        busy          <= 1'b1;
                        neuron_ptr    <= 4'd0;
                        highest_score <= 32'sh80000000;
                        current_bias  <= {{24{bias_rom[0][7]}}, bias_rom[0]};
                        state         <= RESETMAC;
                    end
                end

                RESETMAC: begin
                    reset_mac  <= 1'b1;
                    enable_mac <= 1'b0;
                    pixel_ptr  <= 8'd0;
                    state      <= RUN;
                end

                RUN: begin
                    reset_mac  <= 1'b0;
                    enable_mac <= 1'b1;
                    if (pixel_ptr == 8'd195) begin
                        state <= FLUSH1;
                    end else begin
                        pixel_ptr <= pixel_ptr + 1'b1;
                    end
                end

                FLUSH1: begin
                    enable_mac <= 1'b0;
                    state      <= FLUSH2;
                end

                FLUSH2: begin
                    scores[neuron_ptr] <= mac_out;
                    state              <= FLUSH3;
                end

                FLUSH3: begin
                    if (mac_out > highest_score) begin
                        highest_score <= mac_out;
                        prediction    <= neuron_ptr;
                    end

                    if (neuron_ptr == 4'd9) begin
                        state <= EVAL;
                    end else begin
                        neuron_ptr   <= neuron_ptr + 1'b1;
                        current_bias <= {{24{bias_rom[neuron_ptr + 1][7]}}, bias_rom[neuron_ptr + 1]};
                        state        <= RESETMAC;
                    end
                end

                EVAL: begin
                    sum_exp = 0;
                    for (i = 0; i < 10; i = i + 1) begin
                        sum_exp = sum_exp + exp_approx(scores[i]);
                    end

                    top_exp = exp_approx(highest_score);

                    confidence <= (sum_exp == 0) ? 7'd0 :
                                  (((top_exp * 100) / sum_exp) > 99) ? 7'd99 :
                                  ((top_exp * 100) / sum_exp);

                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule