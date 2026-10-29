`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/08 09:39:02
// Design Name: 
// Module Name: blocking
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


module blocking();
    reg clk,a,b;

    initial begin
        a = 0;
        b = 1;
        clk = 0;
    end

    always #5 clk = ~clk;

    always @(posedge clk) begin
        a <= b;
        b <= a;
    end

    
endmodule

module dsp_strobe();
    reg [7:0] a, b;

    initial begin 
        a = 8'h34;
        b = 8'h34;
        #10 b <= 1 + a;
        $display("$display-1 : time = %0t a = %h b = %h", $time, a, b);
        $strobe("$strobe-1 : time = %0t a = %h b = %h", $time, a, b);
        #5;
        $display("$display-2 : time = %0t a = %h b = %h", $time, a, b);
        $strobe("$strobe-1 : time = %0t a = %h b = %h", $time, a, b);
    end
endmodule