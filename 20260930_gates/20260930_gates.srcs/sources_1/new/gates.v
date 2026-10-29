`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/30 10:44:37
// Design Name: 
// Module Name: gates
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module gates(
    input a,
    input b,

    output y0,
    output y1,
    output y2,
    output y3,
    output y4,
    output y5,
    output y6
    );

    assign y0 = a & b;
    assign y1 = ~(a & b);
    assign y2 = a | b;
    assign y3 = ~(a | b);
    assign y4 = a ^ b;
    assign y5 = ~(a ^ b);
    assign y6 = ~a;

endmodule
