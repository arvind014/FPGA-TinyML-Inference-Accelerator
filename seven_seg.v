`timescale 1ns / 1ps

module seven_seg (
    input  wire        clk,
    input  wire [3:0]  prediction,
    input  wire [6:0]  confidence,      // 0..99
    output reg  [6:0]  seg,
    output reg  [3:0]  an
);
    localparam DIV_MAX = 16'd49999;
    reg [15:0] div_cnt       = 16'd0;
    reg  [1:0] refresh_counter = 2'd0;

    always @(posedge clk) begin
        if (div_cnt == DIV_MAX) begin
            div_cnt         <= 16'd0;
            refresh_counter <= refresh_counter + 2'd1;
        end else begin
            div_cnt <= div_cnt + 16'd1;
        end
    end

    reg [3:0] conf_tens;
    reg [3:0] conf_ones;

    always @(*) begin
        if      (confidence >= 7'd90) begin conf_tens = 4'd9; conf_ones = confidence - 7'd90; end
        else if (confidence >= 7'd80) begin conf_tens = 4'd8; conf_ones = confidence - 7'd80; end
        else if (confidence >= 7'd70) begin conf_tens = 4'd7; conf_ones = confidence - 7'd70; end
        else if (confidence >= 7'd60) begin conf_tens = 4'd6; conf_ones = confidence - 7'd60; end
        else if (confidence >= 7'd50) begin conf_tens = 4'd5; conf_ones = confidence - 7'd50; end
        else if (confidence >= 7'd40) begin conf_tens = 4'd4; conf_ones = confidence - 7'd40; end
        else if (confidence >= 7'd30) begin conf_tens = 4'd3; conf_ones = confidence - 7'd30; end
        else if (confidence >= 7'd20) begin conf_tens = 4'd2; conf_ones = confidence - 7'd20; end
        else if (confidence >= 7'd10) begin conf_tens = 4'd1; conf_ones = confidence - 7'd10; end
        else                          begin conf_tens = 4'd0; conf_ones = confidence;          end
    end

    reg [3:0] current_digit;

    always @(*) begin
        case (refresh_counter)
            2'b00: begin an = 4'b1110; current_digit = conf_ones;   end
            2'b01: begin an = 4'b1101; current_digit = conf_tens;   end
            2'b10: begin an = 4'b1011; current_digit = prediction;  end
            2'b11: begin an = 4'b0111; current_digit = 4'hF;        end // blank
        endcase
    end

    always @(*) begin
        case (current_digit)
            4'd0: seg = 7'b1000000;
            4'd1: seg = 7'b1111001;
            4'd2: seg = 7'b0100100;
            4'd3: seg = 7'b0110000;
            4'd4: seg = 7'b0011001;
            4'd5: seg = 7'b0010010;
            4'd6: seg = 7'b0000010;
            4'd7: seg = 7'b1111000;
            4'd8: seg = 7'b0000000;
            4'd9: seg = 7'b0010000;
            default: seg = 7'b1111111; // blank
        endcase
    end

endmodule