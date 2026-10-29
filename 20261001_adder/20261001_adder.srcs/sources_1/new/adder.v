`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/01 10:22:18
// Design Name: 
// Module Name: adder
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
module full_adder_8(
    input [7:0] a,
    input [7:0] b,
    output [7:0] s,
    output c
);
    wire w_c1;

    full_adder_4 U_FA4_1(
        .a(a[3:0]),
        .b(b[3:0]),
        .cin(1'b0),
        .s(s[3:0]),
        .c(w_c1)
    );
    full_adder_4 U_FA4_2(
        .a(a[7:4]),
        .b(b[7:4]),
        .cin(w_c1),
        .s(s[7:4]),
        .c(c)
    );
endmodule


module full_adder_4(
    input [3:0] a,
    input [3:0] b,
    input cin,
    output [3:0] s,
    output c
);
    wire w_c1, w_c2, w_c3;
    full_adder U_FA1(
        .a(a[0]),
        .b(b[0]),
        .cin(cin),
        .s(s[0]),
        .c(w_c1)
    );
    full_adder U_FA2(
        .a(a[1]),
        .b(b[1]),
        .cin(w_c1),
        .s(s[1]),
        .c(w_c2)
    ); 
    full_adder U_FA3(
        .a(a[2]),
        .b(b[2]),
        .cin(w_c2),
        .s(s[2]),
        .c(w_c3)
    );    
    full_adder U_FA4(
        .a(a[3]),
        .b(b[3]),
        .cin(w_c3),
        .s(s[3]),
        .c(c)
    );    
endmodule


module full_adder(
    input a,
    input b,
    input cin,
    output s,
    output c
    );
    wire w_s1, w_c1, w_c2;
    
    assign c = w_c1 | w_c2;

    half_adder U_HA1(
    .a(a),
    .b(b),
    .s(w_s1),
    .c(w_c1)
    );

    
    half_adder U_HA2(
    .a(w_s1),
    .b(cin),
    .s(s),  // full adder output s
    .c(w_c2)
    );
endmodule

module half_adder(
    input a,
    input b,
    output s,
    output c
    );

    assign s = a ^ b;
    assign c = a & b;
endmodule

