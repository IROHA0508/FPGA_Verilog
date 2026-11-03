
`timescale 1ns / 1ps

module sr04 (
    input clk,
    input rst,
    input sr04_start,
    input echo,

    output trig,
    output busy,
    output done,
    output timeout,
    output [15:0] distance
);

    wire w_us_tick;
    wire w_echo_cnt_en;
    wire w_echo_cnt_clear;

    us_tick_gen U_US_TICK_GEN (
        .clk(clk),
        .rst(rst),
        .us_tick(w_us_tick)
    );

    sr04_controller U_SR04_CONTROLLER (
        .clk(clk),
        .rst(rst),
        .sr04_start(sr04_start),
        .echo(echo),
        .us_tick(w_us_tick),

        .trig(trig),
        .echo_cnt_en(w_echo_cnt_en),
        .echo_cnt_clear(w_echo_cnt_clear),
        .busy(busy),
        .done(done),
        .timeout(timeout)
    );

    sr04_datapath U_SR04_DATAPATH (
        .clk(clk),
        .rst(rst),
        .us_tick(w_us_tick),
        .echo_cnt_en(w_echo_cnt_en),
        .echo_cnt_clear(w_echo_cnt_clear),
        .done(done),
        .distance(distance)
    );

endmodule
