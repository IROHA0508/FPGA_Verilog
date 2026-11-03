`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/31 14:57:48
// Design Name: 
// Module Name: ascii_decoder
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

`timescale 1ns / 1ps


module ascii_decoder (
    input            clk,
    input            rst,
    input            enable,
    input      [7:0] ascii,
    output reg       pop,
    output reg       uart_R,
    output reg       uart_L,
    output reg       uart_U,
    output reg       uart_D,
    output reg       stopwatch,
    output reg       watch,
    output reg       sr04_start,
    output reg       dht11_start

);

    reg [7:0] data_reg, data_next;

    always @(posedge clk, posedge rst) begin
        if (rst) begin
            data_reg <= 0;
        end else begin
            data_reg <= data_next;
        end
    end

    always @(*) begin

        pop         = 1'b0;
        uart_R      = 1'b0;
        uart_L      = 1'b0;
        uart_U      = 1'b0;
        uart_D      = 1'b0;
        stopwatch   = 1'b0;
        watch       = 1'b0;
        sr04_start  = 1'b0;
        dht11_start = 1'b0;

        data_next   = data_reg;
        
        if (enable == 1) begin
            data_next = ascii;
            pop = 1'b1;
            case (ascii)
                "r", "R": uart_R        = 1'b1;
                "c", "C": uart_L        = 1'b1;
                "u", "U": uart_U        = 1'b1;
                "l", "L": uart_D        = 1'b1;
                "0":      stopwatch     = 1'b1;
                "1":      watch         = 1'b1;
                "2":      sr04_start    = 1'b1;
                "3":      dht11_start   = 1'b1;
            endcase
        end
    end


endmodule