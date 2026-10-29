`timescale 1ns / 1ps

module tb_gates();

    reg r_a, r_b;
    wire y0,y1,y2,y3,y4,y5,y6;

    gates DUT(
        .a(r_a),
        .b(r_b),
        .y0(y0),
        .y1(y1),
        .y2(y2),
        .y3(y3),
        .y4(y4),
        .y5(y5),
        .y6(y6)
    );

    initial begin
        r_a = 0;
        r_b = 0;

        // 1ns delay -> 1000times interpret
        #1; 

        r_a = 1;
        r_b = 0;
        #1;

        r_a = 0;
        r_b = 1;
        #1;

        r_a = 1;
        r_b = 1;
        #1;

        //  $finish 와 비슷한 역할
        $stop;
    end 
endmodule
