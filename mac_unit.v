`timescale 1ns / 1ps

module mac_unit_4way(
    input clk,
    input reset,
    input enable,
    input signed [31:0] bias_val,
    input signed [7:0] p0, p1, p2, p3,
    input signed [7:0] w0, w1, w2, w3,
    output reg signed [31:0] accumulator
);

    reg signed [15:0] prod0, prod1, prod2, prod3;

    always @(posedge clk) begin //Every clock: 4 multiplications + 3 additions
        if (enable) begin
            prod0 <= p0 * w0;
            prod1 <= p1 * w1;
            prod2 <= p2 * w2;
            prod3 <= p3 * w3;
        end
    end

    wire signed [17:0] sum_prods = {{2{prod0[15]}}, prod0} + //The Math: prod0 + prod1 + prod2 + prod3. The Hardware Tax: The extra braces and symbols ({{2{prod0[15]}}, prod0}) are just there to make sure that if any of those products are negative numbers, they stay negative, and if the sum gets too large, it doesn't overflow and ruin the calculation.
                                   {{2{prod1[15]}}, prod1} + 
                                   {{2{prod2[15]}}, prod2} + 
                                   {{2{prod3[15]}}, prod3};
    always @(posedge clk) begin
        if (reset) begin
            accumulator <= bias_val;
        end 
        else if (enable) begin
            accumulator <= accumulator + {{14{sum_prods[17]}}, sum_prods};
        end
    end

endmodule