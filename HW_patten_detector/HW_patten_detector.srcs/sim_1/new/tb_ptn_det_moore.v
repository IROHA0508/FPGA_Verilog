`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 2026/10/13 09:12:35
// Design Name:
// Module Name: tb_ptn_det_moore
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


module tb_ptn_det_moore();
    reg clk, reset, din_bit;
    wire ptn_check;

    parameter S0 = 3'b000, S1 = 3'b001, S2 = 3'b010, S3 = 3'b011, S4 = 3'b100;
    pattern_detect_moore dut(
    .clk(clk),
    .reset(reset),
    .din_bit(din_bit),
    .ptn_check(ptn_check)
    );

    // Generate clock
    always #5 clk = ~clk;

    initial begin
        clk = 0;
        reset = 1;
        din_bit = 1'b0;
        #10;
        reset = 0;

        // Test Case : State Change
        // TEST CASE 1
        // STATE : S0, DIN_BIT : 1'b0 -> Change state to S1
        din_bit = 1'b0;
        dut.c_state = S0;
        #10;

        // TEST CASE 2
        // STATE : S0, DIN_BIT : 1'b1 -> Stay at S0
        din_bit = 1'b1;
        dut.c_state = S0;
        #10;

        // TEST CASE 3
        // STATE : S1, DIN_BIT : 1'b0 -> Stay at S1
        din_bit = 1'b0;
        dut.c_state = S1;
        #10;

        // TEST CASE 4
        // STATE : S1, DIN_BIT : 1'b1 -> Change state to S2
        din_bit = 1'b1;
        dut.c_state = S1;
        #10;

        // TEST CASE 5
        // STATE : S2, DIN_BIT : 1'b0 -> Change state to S3
        din_bit = 1'b0;
        dut.c_state = S2;
        #10;

        // TEST CASE 6
        // STATE : S2, DIN_BIT : 1'b1 -> Change state to S0
        din_bit = 1'b1;
        dut.c_state = S2;
        #10;

        // TEST CASE 7
        // STATE : S3, DIN_BIT : 1'b0 -> Change state to S1
        din_bit = 1'b0;
        dut.c_state = S3;
        #10;

        // TEST CASE 8
        // STATE : S3, DIN_BIT : 1'b1 -> Change state to S4 (ptn_check = 1)
        din_bit = 1'b1;
        dut.c_state = S3;
        #10;

        // TEST CASE 9
        // STATE : S4, DIN_BIT : 1'b0 -> Change state to S1 (Overlapping : S3)
        din_bit = 1'b0;
        dut.c_state = S4;
        #10;

        // TEST CASE 10
        // STATE : S4, DIN_BIT : 1'b1 -> Change state to S0
        din_bit = 1'b1;
        dut.c_state = S4;
        #10;

        // Test Case : Pattern Detect
        // TEST CASE 11
        // STATE : S0, DIN_BIT : 0101 -> Detect pattern (Non-overlapping, Overlapping same)
        reset = 1;
        din_bit = 1'b0;
        #10;
        reset = 0;
        din_bit = 1'b0;
        #10;
        din_bit = 1'b1;
        #10;
        din_bit = 1'b0;
        #10;
        din_bit = 1'b1;
        #10;

        // TEST CASE 12
        // STATE : S0, DIN_BIT : 01010 -> After S4, din_bit = 0 (Non-overlapping : S1, Overlapping : S3)
        reset = 1;
        din_bit = 1'b0;
        #10;
        reset = 0;
        din_bit = 1'b0;
        #10;
        din_bit = 1'b1;
        #10;
        din_bit = 1'b0;
        #10;
        din_bit = 1'b1;
        #10;
        din_bit = 1'b0;
        #10;

        // TEST CASE 13
        // STATE : S0, DIN_BIT : 0101010 -> Non-overlapping : detect 1 time, Overlapping : detect 2 times
        reset = 1;
        din_bit = 1'b0;
        #10;
        reset = 0;
        din_bit = 1'b0;
        #10;
        din_bit = 1'b1;
        #10;
        din_bit = 1'b0;
        #10;
        din_bit = 1'b1;
        #10;
        din_bit = 1'b0;
        #10;
        din_bit = 1'b1;
        #10;
        din_bit = 1'b0;
        #10;

        // TEST CASE 14
        // STATE : S0, DIN_BIT : 01010101 -> Non-overlapping : detect 2 times, Overlapping : detect 3 times
        reset = 1;
        din_bit = 1'b0;
        #10;
        reset = 0;
        din_bit = 1'b0;
        #10;
        din_bit = 1'b1;
        #10;
        din_bit = 1'b0;
        #10;
        din_bit = 1'b1;
        #10;
        din_bit = 1'b0;
        #10;
        din_bit = 1'b1;
        #10;
        din_bit = 1'b0;
        #10;
        din_bit = 1'b1;
        #10;

        // TEST CASE 15
        // STATE : S0, DIN_BIT : 0100101 -> Detect pattern (Non-overlapping, Overlapping same)
        reset = 1;
        din_bit = 1'b0;
        #10;
        reset = 0;
        din_bit = 1'b0;
        #10;
        din_bit = 1'b1;
        #10;
        din_bit = 1'b0;
        #10;
        din_bit = 1'b0;
        #10;
        din_bit = 1'b1;
        #10;
        din_bit = 1'b0;
        #10;
        din_bit = 1'b1;
        #10;

        // TEST CASE 16
        // STATE : S0, DIN_BIT : 1101 -> No detection (Non-overlapping, Overlapping same)
        reset = 1;
        din_bit = 1'b0;
        #10;
        reset = 0;
        din_bit = 1'b1;
        #10;
        din_bit = 1'b1;
        #10;
        din_bit = 1'b0;
        #10;
        din_bit = 1'b1;
        #10;

        $finish;
    end
endmodule