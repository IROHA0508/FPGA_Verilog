`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/07 09:36:40
// Design Name: 
// Module Name: tb_gate_premitive
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


module tb_gate_premitive();
    reg a, b;
    wire s, c;

    half_adder dut(
    .a(a),
    .b(b),
    .s(s),
    .c(c)
    );

    initial begin
        a = 0;
        b = 0;
        #1;

        a = 0;
        b = 1;
        #1;
        
        a = 1;
        b = 0;
        #1;

        a = 1;
        b = 1;
        #1;
    end
    
endmodule
