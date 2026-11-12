`timescale 1ns / 1ps

module uart_sv (
    input  logic       clk,
    input  logic       rst,
    input  logic       tx_start,
    input  logic [7:0] tx_data,
    output logic       tx_busy,
    output logic       tx
);
    logic b_tick;

    uart_tx U_UART_TX (
        .*,
        .b_tick(b_tick)
    );

    baud_tickgen U_B_TICKGEN (
        .clk(clk),
        .rst(rst),
        .b_tick(b_tick)
    );
endmodule

module uart_tx (
    input  logic       clk,
    input  logic       rst,
    input  logic       tx_start,
    input  logic [7:0] tx_data,
    input  logic       b_tick,
    output logic       tx_busy,
    output logic       tx
);
    // 기존 localparam을 typedef로 지정할 수 있음
    typedef enum logic [1:0] {
        IDLE,
        START,
        DATA,
        STOP
    } state_e;

    // 4state needs 2 bits
    state_e c_state, n_state;

    // send 8 bits data -> needs 3bits to count
    logic [2:0] bit_cnt, bit_cnt_next;

    // count 8bit when sensing data first time
    // and repeat as b_tick_cnt = 16
    logic [3:0] b_tick_cnt, b_tick_cnt_next;

    // tx_data has 8bits
    logic [7:0] data, data_next;

    logic tx_next;
    logic tx_busy_next;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            c_state    <= IDLE;
            bit_cnt    <= 3'b0;
            b_tick_cnt <= 0;
            data       <= 8'h0;
            tx         <= 1'b1;
            tx_busy    <= 1'b0;
        end else begin
            c_state    <= n_state;
            bit_cnt    <= bit_cnt_next;
            b_tick_cnt <= b_tick_cnt_next;
            data       <= data_next;
            tx         <= tx_next;
            tx_busy    <= tx_busy_next;
        end
    end

    always_comb begin
        n_state         = c_state;
        bit_cnt_next    = bit_cnt;
        b_tick_cnt_next = b_tick_cnt;
        data_next       = data;
        tx_next         = tx;
        tx_busy_next    = tx_busy;

        case (c_state)
            IDLE: begin
                tx_next      = 1'b1;
                tx_busy_next = 1'b0;
                if (tx_start) begin
                    data_next       = tx_data;
                    n_state         = START;
                    b_tick_cnt_next = 0;
                    bit_cnt_next    = 0;
                    tx_busy_next    = 1;
                end
            end

            START: begin
                tx_next      = 1'b0;
                tx_busy_next = 1'b1;
                if (b_tick) begin
                    if (b_tick_cnt == 15) begin
                        b_tick_cnt_next = 0;
                        n_state         = DATA;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt + 1;
                    end
                end
            end

            DATA: begin
                tx_next = data[0];
                if (b_tick) begin
                    if (b_tick_cnt == 15) begin
                        b_tick_cnt_next = 0;
                        if (bit_cnt == 7) begin
                            n_state = STOP;
                        end else begin
                            bit_cnt_next = bit_cnt + 1;
                            data_next    = {1'b0, data[7:1]};
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt + 1;
                    end
                end
            end

            STOP: begin
                tx_next = 1'b1;
                if (b_tick) begin
                    if (b_tick_cnt == 15) n_state = IDLE;
                    else b_tick_cnt_next = b_tick_cnt + 1;
                end
            end

            default: begin
                n_state         = IDLE;
                bit_cnt_next    = 0;
                b_tick_cnt_next = 0;
            end
        endcase
    end
endmodule

module baud_tickgen (
    input  logic clk,
    input  logic rst,
    output logic b_tick
);
    // 100MHz => 9600hz
    // F_COUNT 만큼 세고 1tick 발생
    parameter F_COUNT = 100_000_000 / (9600 * 16);
    logic [$clog2(F_COUNT) - 1:0] counter_reg;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            counter_reg <= 0;
            b_tick      <= 0;
        end else begin
            counter_reg <= counter_reg + 1;
            b_tick      <= 0;
            if (counter_reg == F_COUNT - 1) begin
                counter_reg <= 0;
                b_tick      <= 1;
            end
        end
    end
endmodule
