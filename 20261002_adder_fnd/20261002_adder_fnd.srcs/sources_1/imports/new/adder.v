`timescale 1ns / 1ps


module adder_fnd (
    input clk,
    input reset,
    input  [7:0] a,
    input  [7:0] b,
    // input  [1:0] ds_sel,
    output [3:0] fnd_com,
    output [7:0] fnd_font


);
    wire [7:0] w_s;
    wire w_c;

    adder U_Adder (
        .a(a),
        .b(b),
        .s(w_s),
        .c(w_c)
    );

    fnd_controller U_FND_CNTL (
        .clk(clk),
        .reset(reset),
        // .ds_sel  (ds_sel),
        .fnd_data({w_c, w_s}),  //9bit {c,s}
        .fnd_com (fnd_com),
        .fnd_font(fnd_font)
    );
endmodule


module adder (
    input [7:0] a,
    input [7:0] b,
    output [7:0] s,
    output c
);
    wire w_c;

    full_adder_4 U_FA1 (
        .a  (a[3:0]),
        .b  (b[3:0]),
        .cin(1'b0),
        .s  (s[3:0]),
        .c  (w_c)
    );

    full_adder_4 U_FA2 (
        .a  (a[7:4]),
        .b  (b[7:4]),
        .cin(w_c),
        .s  (s[7:4]),
        .c  (c)
    );
endmodule

module full_adder_8 (
    input [7:0] a,
    input [7:0] b,
    // input cin,
    output [7:0] s,
    output c
);
    wire w_c;

    full_adder_4 U_FA1 (
        .a  (a[3:0]),
        .b  (b[3:0]),
        .cin(1'b0),
        .s  (s[3:0]),
        .c  (w_c)
    );

    full_adder_4 U_FA2 (
        .a  (a[7:4]),
        .b  (b[7:4]),
        .cin(w_c),
        .s  (s[7:4]),
        .c  (c)
    );
endmodule


module full_adder_4 (
    input [3:0] a,
    input [3:0] b,
    input cin,
    output [3:0] s,
    output c
);
    wire w_c1, w_c2, w_c3;

    // instanciation
    full_adder U_FA1 (
        .a  (a[0]),
        .b  (b[0]),
        .cin(cin),
        .s  (s[0]),
        .c  (w_c1)
    );


    full_adder U_FA2 (
        .a  (a[1]),
        .b  (b[1]),
        .cin(w_c1),
        .s  (s[1]),
        .c  (w_c2)
    );

    full_adder U_FA3 (
        .a  (a[2]),
        .b  (b[2]),
        .cin(w_c2),
        .s  (s[2]),
        .c  (w_c3)
    );


    full_adder U_FA4 (
        .a  (a[3]),
        .b  (b[3]),
        .cin(w_c3),
        .s  (s[3]),
        .c  (c)
    );
endmodule



module full_adder (
    input  a,
    input  b,
    input  cin,
    output s,
    output c
);
    wire w_s1, w_c1, w_c2;
    assign c = w_c1 | w_c2;

    half_adder U_HA1 (
        .a(a),
        .b(b),
        .s(w_s1),
        .c(w_c1)
    );


    half_adder U_HA2 (
        .a(w_s1),
        .b(cin),
        .s(s),  // full adder output s
        .c(w_c2)
    );
endmodule


module half_adder (
    input  a,
    input  b,
    output s,
    output c
);
    // assign s = a ^ b;
    // assign c = a & b;

    // Using Gate Premitive
    xor (s, a, b);
    and (c, a, b);
endmodule
