`timescale 1ns / 1ps

module UART_FIFO_ASCII (
    input         clk,
    input         rst,
    input         rx,
    output        tx,

    // ASCII Decoder -> control
    output        uart_R,
    output        uart_L,
    output        uart_U,
    output        uart_D,
    output        stopwatch,
    output        watch,
    output        sr04_start,
    output        dht11_start,

    // control -> ASCII Sender
    input         result_done,
    input         result_valid,
    input  [1:0]  result_type,
    input  [39:0] result_data,

    // ASCII Sender 상태
    output        sender_ready,
    output        sender_busy
);

    // FIFO RX 
    wire [7:0] w_rx_pop_data;
    wire       w_rx_valid;
    wire       w_rx_pop;

    // FIFO TX 
    wire [7:0] w_fifo_tx_push_data;
    wire       w_fifo_tx_push;
    wire       w_fifo_tx_full;


    
    // UART RX / FIFO RX / FIFO TX / UART TX

    uart_fifo_loopback U_UART_FIFO_LOOPBACK (
        .clk               (clk),
        .rst               (rst),
        .rx                (rx),
        .tx                (tx),

        // FIFO RX
        .fifo_rx_pop       (w_rx_pop),
        .rx_pop_data       (w_rx_pop_data),
        .rx_empty          (w_rx_valid),

        // FIFO TX
        .fifo_tx_push      (w_fifo_tx_push),
        .fifo_tx_push_data (w_fifo_tx_push_data),
        .fifo_tx_full      (w_fifo_tx_full)
    );


  
    // ASCII Decoder
   

    ascii_decoder U_ASCII_DECODER (
        .clk           (clk),
        .rst           (rst),
        // FIFO RX
        .enable        (w_rx_valid),
        .ascii         (w_rx_pop_data),
        .pop           (w_rx_pop),
        // control
        .uart_R        (uart_R),
        .uart_L        (uart_L),
        .uart_U        (uart_U),
        .uart_D        (uart_D),
        .stopwatch     (stopwatch),
        .watch         (watch),
        .sr04_start    (sr04_start),
        .dht11_start   (dht11_start)
    );


     // ASCII Sender
    ascii_sender U_ASCII_SENDER (
        .clk         (clk),
        .rst         (rst),

        .done        (result_done),
        .vaild       (result_valid),
        .data_type   (result_type),
        .input_data  (result_data),

        // FIFO TX
        .fifo_full   (w_fifo_tx_full),
        .fifo_data   (w_fifo_tx_push_data),
        .push        (w_fifo_tx_push),

        // Sender 상태
        .ready       (sender_ready),
        .sender_busy (sender_busy)
    );

endmodule