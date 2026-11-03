`timescale 1ns / 1ps
module uart_fifo_loopback (
    input  clk,
    input  rst,
    input  rx,   //from PC
    input  fifo_rx_pop,
    input  fifo_tx_push,
    input  [7:0] fifo_tx_push_data,
    output fifo_tx_full,
    output tx,
    output[7:0] rx_pop_data,
    output rx_empty     //to PC
);
    wire w_b_tick;
    wire w_rx_done;
    wire [7:0] w_rx_data, w_fifo_rx_pop_data, w_fifo_tx_pop_data;
    wire w_fifo_tx_full, w_fifo_rx_empty, w_fifo_tx_empty,w_tx_busy;

    assign rx_pop_data= w_fifo_rx_pop_data;
    // 기존 포트의 의미 유지: 1=수신 데이터 있음, 0=없음.
    assign rx_empty = ~w_fifo_rx_empty;
    assign fifo_tx_full = w_fifo_tx_full;

    // uart_tx의 busy가 올라오기 전 FIFO를 두 번 pop하지 않도록 대기합니다.
    localparam [1:0] TX_IDLE = 0, WAIT_BUSY_HIGH = 1, WAIT_BUSY_LOW = 2;
    reg [1:0] tx_state;
    wire w_tx_take;
    assign w_tx_take = !rst && (tx_state == TX_IDLE) &&
                       !w_fifo_tx_empty && !w_tx_busy;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state <= TX_IDLE;
        end else begin
            case (tx_state)
                TX_IDLE: if (w_tx_take) tx_state <= WAIT_BUSY_HIGH;
                WAIT_BUSY_HIGH: if (w_tx_busy) tx_state <= WAIT_BUSY_LOW;
                WAIT_BUSY_LOW: if (!w_tx_busy) tx_state <= TX_IDLE;
                default: tx_state <= TX_IDLE;
            endcase
        end
    end
  

    uart_rx U_UART_RX (
        .clk    (clk),
        .rst    (rst),
        .b_tick (w_b_tick),
        .rx     (rx),
        .rx_data(w_rx_data),
        .rx_done(w_rx_done)
    );
    fifo U_FIFO_RX (
        .clk      (clk),
        .rst      (rst),
        .push     (w_rx_done),           //from uart rx
        .pop      (fifo_rx_pop),
        .push_data(w_rx_data),
        .pop_data (w_fifo_rx_pop_data),
        .full     (),
        .empty    (w_fifo_rx_empty)
    );
    fifo U_FIFO_TX (
        .clk      (clk),
        .rst      (rst),
        .push     (fifo_tx_push),
        .pop      (w_tx_take),
        .push_data(fifo_tx_push_data),
        .pop_data (w_fifo_tx_pop_data),
        .full     (w_fifo_tx_full),
        .empty    (w_fifo_tx_empty)
    );

    //uart tx
    uart_tx U_UART_TX (
        .clk     (clk),
        .rst     (rst),
        .tx_start(w_tx_take),
        .tx_data (w_fifo_tx_pop_data),
        .b_tick  (w_b_tick),
        .tx      (tx),
        .tx_busy (w_tx_busy)

    );

    baud_tick_gen U_BAUD_TICK_GEN (
        .clk   (clk),
        .rst   (rst),
        .b_tick(w_b_tick)
    );
endmodule

module baud_tick_gen (
    input      clk,
    input      rst,
    output reg b_tick
);
    // parameter F_COUNT = 100_000_000 / 9600;
    parameter F_COUNT = 100_000_000 / (9600 * 16);
    reg [$clog2(F_COUNT) -1:0] counter_reg;
    //100Mhz -> 9600hz
    always @(posedge clk, posedge rst) begin
        if (rst) begin
            counter_reg <= 0;
            b_tick      <= 1'b0;
        end else begin
            counter_reg <= counter_reg + 1;
            if (counter_reg == F_COUNT - 1) begin
                counter_reg <= 0;
                b_tick      <= 1'b1;
            end else begin
                b_tick <= 1'b0;
            end
        end
    end
endmodule