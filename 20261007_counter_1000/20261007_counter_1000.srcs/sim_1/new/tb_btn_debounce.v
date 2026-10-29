`timescale 1ns / 1ps

module tb_btn_debounce();
    reg clk, reset, i_btn;
    wire o_btn;

    btn_debounce dut(
    .clk(clk),
    .reset(reset),
    .i_btn(i_btn),
    .o_btn(o_btn)
    );

    // Generate clock
    always #5 clk = ~clk;

    initial begin
        clk = 0;
        reset = 1;
        i_btn = 0;
        #10;
        reset = 0;

        // TEST CASE 1
        // i_btn : 0 (20us) -> o_btn stays 0
        i_btn = 1'b0;
        #20000;

        // TEST CASE 2
        // i_btn : 1 (3us) -> noise blocked
        i_btn = 1'b1;
        #3000;
        i_btn = 1'b0;
        #20000;

        // TEST CASE 3
        // i_btn : 1 (7us) -> blocked (less than 8us)
        i_btn = 1'b1;
        #7000;
        i_btn = 1'b0;
        #20000;

        // TEST CASE 4
        // i_btn : 1 (9us) -> o_btn pulse once
        i_btn = 1'b1;
        #9000;
        i_btn = 1'b0;
        #20000;

        // TEST CASE 5
        // i_btn : chattering (0.2us, 1us, 3us) then stable 1 (20us) -> o_btn pulse once
        i_btn = 1'b0;
        #1000;
        i_btn = 1'b1;
        #200;
        i_btn = 1'b0;
        #800;
        i_btn = 1'b1;
        #1000;
        i_btn = 1'b0;
        #1000;
        i_btn = 1'b1;
        #3000;
        i_btn = 1'b0;
        #1000;
        i_btn = 1'b1;
        #20000;

        // TEST CASE 6
        // i_btn : 1 -> 0 (release) -> o_btn stays 0
        i_btn = 1'b0;
        #20000;

        // TEST CASE 7
        // i_btn : press, release, press again -> o_btn pulse twice
        i_btn = 1'b1;
        #20000;
        i_btn = 1'b0;
        #20000;
        i_btn = 1'b1;
        #20000;
        i_btn = 1'b0;
        #20000;

        // TEST CASE 8
        // i_btn : 1 (20us), reset in the middle -> o_btn 0, then pulse again after reset release
        i_btn = 1'b1;
        #4000;
        reset = 1'b1;
        #100;
        reset = 1'b0;
        #20000;
        i_btn = 1'b0;
        #20000;

        // TEST CASE 9
        // i_btn : 1 (20us) with 1us glitch to 0 in the middle -> o_btn pulse again
        i_btn = 1'b1;
        #12000;
        i_btn = 1'b0;
        #1000;
        i_btn = 1'b1;
        #20000;
        i_btn = 1'b0;
        #20000;

        $finish;
    end
endmodule