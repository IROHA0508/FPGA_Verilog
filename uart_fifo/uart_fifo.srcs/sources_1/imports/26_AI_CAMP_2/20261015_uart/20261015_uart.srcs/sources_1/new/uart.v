`timescale 1ns / 1ps

// top module
module uart_fifo_loopback (
    input  clk,
    input  rst,
    input  rx,   // from PC
    output tx    // to PC
    // output rx_done,
    // output [7:0] rx_data
);

    wire       w_b_tick;
    wire       w_rx_done;
    wire       w_fifo_tx_full;
    wire       w_fifo_rx_empty;
    wire       w_fifo_tx_empty;
    wire       w_tx_busy;
    wire [7:0] w_rx_data, w_fifo_rx_pop_data, w_fifo_tx_pop_data;

    uart_rx U_UART_RX (
        .clk    (clk),
        .rst    (rst),
        .b_tick (w_b_tick),
        .rx     (rx),
        .rx_data(w_rx_data),
        .rx_done(w_rx_done)
    );

    fifo U_FIFO_RX (
        .clk     (clk),
        .rst     (rst),
        .push    (w_rx_done),        //from uart rx
        .pop     (~w_fifo_tx_full),
        .pushdata(w_rx_data),
        .popdata (w_fifo_rx_pop_data),
        .full    (),
        .empty   (w_fifo_rx_empty)
    );


    // uart TX
    uart_tx U_UART_TX (
        .clk     (clk),
        .rst     (rst),
        .tx_start(~w_fifo_tx_empty),
        .tx_data (w_fifo_tx_pop_data),
        .b_tick  (w_b_tick),
        .tx      (tx),
        .tx_busy (w_tx_busy)
    );

    fifo U_FIFO_TX (
        .clk     (clk),
        .rst     (rst),
        .push    (~w_fifo_rx_empty),
        .pop     (~w_tx_busy),
        .pushdata(w_fifo_rx_pop_data),
        .popdata (w_fifo_tx_pop_data),
        .full    (w_fifo_tx_full),
        .empty   (w_fifo_tx_empty)
    );

    // baud tick gen
    baud_tick_gen U_BAUD_TICK_GEN (
        .clk   (clk),
        .rst   (rst),
        .b_tick(w_b_tick)
    );

endmodule
