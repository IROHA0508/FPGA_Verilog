`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/07 14:12:07
// Design Name: 
// Module Name: tb_counter_10000
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


// button simulation
module tb_stopwatch_top();
    reg clk, rst, btnU, btnL, btnR;
    reg sw_display_mode;
    wire [3:0] fnd_com;
    wire [7:0] fnd_font;

    // 10 clk * 1 mhz
    parameter BD_PUSH_TIME = 10 * 100;
    parameter MSEC = 100_000 * 10;

    stopwatch dut(
        .clk(clk),
        .rst(rst),
        .btnR(btnR),
        .btnL(btnL),
        .btnU(btnU),
        .sw_display_mode(sw_display_mode),
        .fnd_com(fnd_com),
        .fnd_font(fnd_font)
    );

    always #5 clk = ~clk;

    initial begin 
        clk = 0;
        rst = 1;
        btnU = 0;
        btnL = 0;
        btnR = 0;
        sw_display_mode = 0;
        #10 rst = 0;

        // Test case 1 : runstop btn 1 push-pop
        btnR = 1;
        repeat(BD_PUSH_TIME) @(posedge clk);
        btnR = 0;

        // run state
        repeat(100) begin
            # (MSEC * 10);
        end

        # (MSEC);

        sw_display_mode = 1'b1;
        repeat(10) begin
            # (MSEC * 10);
        end

        # (MSEC);
        sw_display_mode = 1'b0;     
        # (10 * MSEC);

        btnR = 1;
        repeat(BD_PUSH_TIME) @(posedge clk);
        btnR = 0;

        // stop state


        // clear


        // mode down

        // run

        // mode change

        // stop

        $finish;
    end
endmodule
