`timescale 1ns / 1ps

module tb_sr04 ();

    reg clk, rst, sr04_start, echo;
    wire trig, distance;

    top_sr04 dut (
        .clk       (clk),
        .rst       (rst),
        .sr04_start(sr04_start),
        .echo      (echo),
        .trig      (trig)
    );

    always #5 clk = ~clk;
    
    initial begin 
        clk = 0;
        rst = 1;
        echo = 0;
        sr04_start = 0;

        #10;
        rst = 0;
        #10;

        //sr04 start btn
        @(negedge clk);
        sr04_start = 1;
        @(posedge clk);

        // sr04 trigger monitoring
        @(posedge trig);
        @(negedge trig);

        #(2000);

        echo = 1;
        // 600 * 1us
        #(600*1000);
        echo = 0;
        
        // 10ms
        #(10_000_000);
        #(2000);
        $finish;
    end
endmodule
