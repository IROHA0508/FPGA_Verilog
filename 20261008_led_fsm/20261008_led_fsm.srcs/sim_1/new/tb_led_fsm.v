`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/08 16:35:25
// Design Name: 
// Module Name: tb_led_fsm
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


module tb_led_fsm();
    reg clk, reset;
    reg [1:0] sw;
    wire [2:0] led;

    led_fsm_1 dut(
    .clk(clk),
    .reset(reset),
    .sw(sw),
    .led(led)
    );

    // Generate clock
    always #5 clk = ~clk;

    initial begin
        clk = 0;
        reset = 1;
        sw = 2'b00;
        #10 reset = 0;

        // Test Scenario 1
        #10 sw = 2'b01;
        #10 sw = 2'b10;
        #10 sw = 2'b11;
        #10 sw = 2'b00;
        
        #10;
        $finish;

    end
endmodule
