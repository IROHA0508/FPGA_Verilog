`timescale 1ns / 1ps

module uart_rx (
    input            clk,
    input            rst,
    input            b_tick,
    input            rx,
    output [7:0] rx_data,
    output       rx_done
);

    // State
    //parameter IDLE = 2'b00, START = 2'b01, DATA = 2'b10, STOP = 2'b11;
    localparam [1:0] IDLE = 2'b00, START = 2'b01, DATA = 2'b10, STOP = 2'b11;
    // State 관리 register
    reg [1:0] c_state, n_state;

    // b_tick counter
    reg [3:0] b_tick_cnt_reg, b_tick_cnt_next;
    // Bit count (Data 0 ~ Data 7)
    reg [2:0] bit_cnt_reg, bit_cnt_next;
    // Data register
    reg [7:0] data_reg, data_next;

    reg rx_done_reg, rx_done_next;

    // Output assignment 추가
    assign rx_data = data_reg;
    assign rx_done = rx_done_reg;

    // SL
    always @(posedge clk, posedge rst) begin
        if (rst) begin
            c_state        <= IDLE;
            b_tick_cnt_reg <= 4'h0;
            bit_cnt_reg    <= 3'b000;

            data_reg       <= 0;
            rx_done_reg    <= 1'b0;
        end else begin
            c_state        <= n_state;
            b_tick_cnt_reg <= b_tick_cnt_next;
            bit_cnt_reg    <= bit_cnt_next;

            data_reg       <= data_next;
            rx_done_reg    <= rx_done_next;
        end
    end

    // next, output CL
    always @(*) begin
        n_state         = c_state;
        bit_cnt_next    = bit_cnt_reg;
        b_tick_cnt_next = b_tick_cnt_reg;
        data_next       = data_reg;
        rx_done_next    = rx_done_reg;

        case (c_state)
            IDLE: begin
                b_tick_cnt_next = 0;
                rx_done_next = 1'b0;
                if (b_tick) begin
                    // rx == 0
                    if (!rx) begin
                        n_state = START;  // IDLE → START
                    end
                end
            end

            START: begin
                if (b_tick) begin
                    // 16배속 b_tick의 절반
                    if (b_tick_cnt_reg == 7) begin
                        b_tick_cnt_next = 0;
                        bit_cnt_next = 0;
                        data_next = 8'h00;

                        n_state = DATA;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end

            DATA: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        b_tick_cnt_next = 0;
                        // MSB에 rx 추가
                        // right shift to data register
                        data_next = {rx, data_reg[7:1]};

                        if (bit_cnt_reg == 7) begin
                            b_tick_cnt_next = 0;

                            n_state = STOP;
                        end else begin
                            bit_cnt_next = bit_cnt_reg + 1;
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end

            STOP: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        rx_done_next = 1;

                        n_state = IDLE; 
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end

            default: begin
                n_state = IDLE;
            end
        endcase
    end

endmodule