`timescale 1ns / 1ps

module tb_temp();
    
    reg clk, rst;
    reg echo, sr04_start;
    wire w_us_tick, w_enable, w_clear;
    wire trig, distance;

    sr04_tick_gen dut_tick_gen(
        .clk(clk),
        .rst(rst),
        .enable(w_enable),
        .clear(w_clear),
        .us_tick(w_us_tick)
    );

    sr04_controller dut_controller(
        .clk(clk),
        .rst(rst),
        .echo(echo),
        .sr04_start(sr04_start),
        .us_tick(w_us_tick),
        .enable(w_enable),
        .clear(w_clear),
        .distance(distance)
    );

    always #5 clk = ~clk;

    initial begin 
        clk = 0;
        rst = 1;
        sr04_start = 0;

        #10 rst = 0;

        #10
        sr04_start = 0;

        #10
        sr04_start = 1;

        #20000;
        echo = 1;


        $finish;
    end
endmodule
