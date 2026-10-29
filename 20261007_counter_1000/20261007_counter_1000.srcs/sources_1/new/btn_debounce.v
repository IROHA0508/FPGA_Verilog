`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/12 16:25:56
// Design Name: 
// Module Name: btn_debounce
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


module btn_debounce(
    input clk,
    input reset,
    input i_btn,
    output o_btn
);
    reg [7:0] q_reg;
    wire debounce;
    reg edge_reg;

    // clk div 100Mhz -> 1Mhz
    parameter F_COUNT = $clog2(100);
    reg [F_COUNT -1 : 0] count_reg;
    reg clk_1Mhz;
    always @(posedge clk, posedge reset) begin 
        if(reset) begin 
            count_reg <= 0;
            clk_1Mhz <= 1'b0;
        end
        else begin 
            count_reg <= count_reg + 1;
            if (count_reg == 100 - 1) begin
                clk_1Mhz <= 1'b1;
                count_reg <= 0;
            end else begin
                clk_1Mhz <= 1'b0;
            end
        end
    end

    // 8Bit Shift Register
    always @(posedge clk_1Mhz, posedge reset) begin 
        if(reset) q_reg <= 8'h00;
        else q_reg <= {i_btn, q_reg[7:1]};
    end

    //  8-input AND gate
    assign debounce = &q_reg;

    // edge detection
    always @(posedge clk, posedge reset) begin 
        if (reset) edge_reg <=1'b0;
        else edge_reg <= debounce;
    end

    // rising edge, tick gen 
    assign o_btn = ~edge_reg & debounce;
endmodule
