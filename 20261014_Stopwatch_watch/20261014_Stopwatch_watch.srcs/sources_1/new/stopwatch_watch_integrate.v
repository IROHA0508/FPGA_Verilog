`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/14 16:27:55
// Design Name: 
// Module Name: stopwatch_watch_integrate
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


module stopwatch_watch_integrate #(
    parameter MSEC_BIT_WIDTH = 7,
    parameter SEC_BIT_WIDTH = 6,
    parameter MIN_BIT_WIDTH = 6,
    parameter HOUR_BIT_WIDTH = 5,
    parameter TIME_WIDTH = MSEC_BIT_WIDTH + SEC_BIT_WIDTH + MIN_BIT_WIDTH + HOUR_BIT_WIDTH
    )(
        input clk,
        input rst,
        input btnR, btnL, btnU, btnD,
        input [2:0] sw,
        output [3:0] fnd_com,
        output [7:0] fnd_font,
        output [1:0]led
    );

    wire [1:0] w_disp_mode;
    wire [2:0] w_set_field;
    wire       w_blink_en;

    wire [TIME_WIDTH-1:0] w_wt_time, w_sw_time;
    wire [3:0] w_wt_btn, w_sw_btn;

    button_debounce_integrate U_BTN_DEBOUNCE(
        .clk(clk),
        .rst(rst),
        .sw0(sw[0]),
        .btn({btnD, btnU, btnL, btnR}),
        .o_wt_btn(w_wt_btn),
        .o_sw_btn(w_sw_btn)
    );

    // sw[0] = 0
    watch U_WATCH(
        .clk(clk),
        .rst(rst),
        .btn(w_wt_btn),
        .sw0(sw[0]),
        .sw2(sw[2]),
        .o_time(w_wt_time),
        .disp_mode(w_disp_mode),
        .set_field(w_set_field),
        .blink_en(w_blink_en)
    );

    // sw[0] = 1
    stopwatch U_STOPWATCH(
        .clk(clk),
        .rst(rst),
        .btn(w_sw_btn),
        .o_time(w_sw_time)
    );

    fnd_controller U_FND_CNTL(
        .clk(clk),
        .rst(rst),
        .sw_stopwatch_mode(sw[0]),
        .sw_display_mode(sw[1]),
        .disp_mode(w_disp_mode),
        .set_field(w_set_field),
        .blink_en(w_blink_en),
        .wt_time(w_wt_time),
        .sw_time(w_sw_time),
        .fnd_com(fnd_com),
        .fnd_font(fnd_font),
        .led_hrmin(led[0]),
        .led_watch(led[1])
    );
endmodule
