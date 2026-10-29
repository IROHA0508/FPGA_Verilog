`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/01 11:38:57
// Design Name: 
// Module Name: tb_adder
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


module tb_adder();

    reg [7:0] r_a, r_b;
    wire [7:0] s;
    wire c;
    integer i,j;

    full_adder_8 DUT(
        .a(r_a),
        .b(r_b),
        .s(s),
        .c(c)
    );

    // full_adder_4 DUT(
    //     .a(r_a),
    //     .b(r_b),
    //     .cin(1'b0),     // 1bit starts with 0
    //     .s(s),
    //     .c(c)
    // );

    initial begin
        for(i = 0; i < 256; i = i + 1) begin
            for(j = 0; j < 256; j = j + 1) begin
                r_a = i;
                r_b = j;
                #1;
            end
        end

        $finish;
    end
endmodule
