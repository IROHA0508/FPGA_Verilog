`timescale 1ns / 1ps

// top module
module uart_loopback (
    input  clk,
    input  rst,
    input  rx,    // from PC
    output tx,     // to PC
    output rx_done,
    output [7:0] rx_data
);

    wire w_b_tick; 
    // wire w_rx_done;
    // wire [7:0] w_rx_data;

    // uart TX
    uart_tx U_UART_TX (
        .clk     (clk),
        .rst     (rst),
        .tx_start(rx_done),
        .tx_data (rx_data),
        .b_tick  (w_b_tick),
        .tx      (tx),
        .tx_busy ()
    );

    uart_rx U_UART_RX (
        .clk    (clk),
        .rst    (rst),
        .b_tick (w_b_tick),
        .rx     (rx),
        .rx_data(rx_data),
        .rx_done(rx_done)
    );

    // baud tick gen
    baud_tick_gen U_BAUD_TICK_GEN (
        .clk   (clk),
        .rst   (rst),
        .b_tick(w_b_tick)
    );

endmodule