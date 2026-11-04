`timescale 1ns / 1ps

module adder (
    input  logic [7:0] a,
    input  logic [7:0] b,
    input  logic       mode,        // 0 : add, 1 : sub
    output logic [7:0] s,
    output logic       c
);
    assign {c, s} = mode ? a - b : a + b;

    // always @(*) begin
    //     {c, s} = a + b;
    // end

    // always_comb : Combinational Logic <-> always_ff : Sequential Logic
    // always_comb begin 
    //     {c,s} = a + b;
    // end
endmodule
