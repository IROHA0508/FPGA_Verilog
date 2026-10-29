`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/16 12:33:54
// Design Name: 
// Module Name: button_debounce_integrate
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


module button_debounce_integrate (
    input        clk,
    input        rst,
    input        sw0,              // 0: watch, 1: stopwatch
    input  [3:0] btn,              // {D, U, L, R} = [3] [2] [1] [0]
    output [3:0] o_wt_btn,         // watch용     {D, U, L, R}
    output [3:0] o_sw_btn          // stopwatch용 {D, U, L, R}
);

    wire [3:0] w_btn;              // 디바운스된 한 클록 펄스

    btn_debounce U_BD_R (.clk(clk), .reset(rst), .i_btn(btn[0]), .o_btn(w_btn[0]));
    btn_debounce U_BD_L (.clk(clk), .reset(rst), .i_btn(btn[1]), .o_btn(w_btn[1]));
    btn_debounce U_BD_U (.clk(clk), .reset(rst), .i_btn(btn[2]), .o_btn(w_btn[2]));
    btn_debounce U_BD_D (.clk(clk), .reset(rst), .i_btn(btn[3]), .o_btn(w_btn[3]));

    // {4{x}}는 x를 4번 복제한 4비트 값이라 4비트 AND가 한 줄로 끝난다
    assign o_wt_btn = w_btn & {4{~sw0}};
    assign o_sw_btn = w_btn & {4{sw0}};

endmodule
