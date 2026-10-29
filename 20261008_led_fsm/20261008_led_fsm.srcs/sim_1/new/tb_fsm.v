`timescale 1ns / 1ps

module tb_fsm();
    reg clk, reset;
    reg [1:0] sw;
    wire clear, run_stop;

    parameter stop = 2'b00, run = 2'b01, s_clear = 2'b10;
    fsm dut(
    .clk(clk),
    .reset(reset),
    .sw(sw),
    .clear(clear),
    .run_stop(run_stop)
    );


    // Generate clock
    always #5 clk = ~clk;

    initial begin
        clk = 0;
        reset = 1;
        sw = 2'b00;
        #10;
        reset = 0;

        // Change state
        // TEST CASE 1
        // STATE : stop, SW : 2'b01 -> Change state to run
        sw = 2'b01;
        dut.c_state = stop;
        #10;

        // TEST CASE 2
        // STATE : stop, SW : 2'b10 -> Change state to s_clear
        sw = 2'b10;
        dut.c_state = stop;
        #10;

        // TEST CASE 3
        // STATE : stop, SW : 2'b11 -> Change state to run (SW0 priority)
        sw = 2'b11;
        dut.c_state = stop;
        #10;

        // TEST CASE 4
        // STATE : run, SW : 2'b00 -> Change state to stop
        sw = 2'b00;
        dut.c_state = run;
        #10;

        // TEST CASE 5
        // STATE : run, SW : 2'b10 -> Change state to stop
        sw = 2'b10;
        dut.c_state = run;
        #10;

        // TEST CASE 6
        // STATE : s_clear, SW : 2'b00 -> Change state to stop
        sw = 2'b00;
        dut.c_state = s_clear;
        #10;

        // TEST CASE 7
        // STATE : s_clear, SW : 2'b01 -> Change state to stop
        sw = 2'b01;
        dut.c_state = s_clear;
        #10;

        // No Change
        // TEST CASE 8
        // STATE : stop, SW : 2'b00
        sw = 2'b00;
        dut.c_state = stop;
        #10;

        // TEST CASE 9
        // STATE : run, SW : 2'b01
        sw = 2'b01;
        dut.c_state = run;
        #10;

        // TEST CASE 10
        // STATE : run, SW : 2'b11
        sw = 2'b11;
        dut.c_state = run;
        #10;

        // TEST CASE 11
        // STATE : s_clear, SW : 2'b10
        sw = 2'b10;
        dut.c_state = s_clear;
        #10;

        // TEST CASE 12
        // STATE : s_clear, SW : 2'b11
        sw = 2'b11;
        dut.c_state = s_clear;
        #10;

        $finish;
    end
endmodule