`timescale 1ns / 1ps


module uart_fifo_ascii (
    input        clk,
    input        rst,
    input        rx,
    input        btn_R,
    input        echo,
    output       tx,
    output       run_stop,
    output       clear,
    output       mode,
    output       status,
    output [3:0] fnd_com,
    output [7:0] fnd_font,
    output       trig
);
    wire       w_rx_empty;
    wire [3:0] w_bin;
    wire [7:0] w_rx_pop_data;
    wire       w_rx_pop;

    uart_fifo_loopback U_UART_FIFO_LOOPBACK (
        .clk        (clk),
        .rst        (rst),
        .rx         (rx),            // from PC
        .tx         (tx),            // to PC
        .fifo_rx_pop(w_rx_pop),
        .rx_empty   (w_rx_empty),
        .rx_pop_data(w_rx_pop_data)
    );

    ascii_decoder U_ASCII_DECODER (
        .clk     (clk),
        .rst     (rst),
        .enable  (w_rx_empty),
        .ascii   (w_rx_pop_data),
        .binary  (w_bin),
        .pop     (w_rx_pop),
        .run_stop(run_stop),
        .clear   (clear),
        .mode    (mode),
        .status  (status)
    );

    wire w_dist;
    wire w_btn_r;
    wire w_enable;
    wire w_clear;
    wire w_us_tick;

    btn_debounce U_BTN_DEBOUNCE_R (
        .clk  (clk),
        .reset(rst),
        .i_btn(btn_R),
        .o_btn(w_btn_r)
    );

    sr04_controller U_SR04_CNTL (
        .clk       (clk),
        .rst       (rst),
        .echo      (echo),
        .sr04_start(run_stop || w_btn_r),
        .trig      (trig),
        .us_tick   (w_us_tick),
        .enable    (w_enable),
        .clear     (w_clear),
        .distance  (w_dist)
    );

    sr04_tick_gen U_SR04_TICK_GEN (
        .clk    (clk),
        .rst    (rst),
        .enable (w_enable),
        .clear  (w_clear),
        .us_tick(w_us_tick)
    );


    fnd_controller U_FND_CNTL (
        .clk     (clk),
        .reset   (rst),
        .fnd_data(w_dist),
        .fnd_com (fnd_com),
        .fnd_font(fnd_font)
    );

endmodule
