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

endmodule
