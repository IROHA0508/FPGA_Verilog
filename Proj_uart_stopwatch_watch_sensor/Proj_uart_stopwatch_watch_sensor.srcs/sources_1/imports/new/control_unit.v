`timescale 1ns / 1ps

module top_control_unit (
    input            clk,
    input            rst,
    input      [1:0] sw,            // 모드 전이 스위치,
    input            sw_dth,        // 온도, 습도 전환 스위치
    input            btnR,          // run,stop or move right
    input            btnL,          // clear or move_left
    input            btnU,          // up,down or watch_up
    input            btnD,          // Laptime or watch_down
    input            uart_R,
    input            uart_L,
    input            uart_U,
    input            uart_D,
    input            uart_0,        // status_stopwatch
    input            uart_1,        // status_watch
    input            uart_2,        // status_SR04
    input            uart_3,        // status_DHT11
    input            sr04_done,
    input            sr04_timeout,
    input            dht11_done,
    input            dht11_valid,
    input            sender_ready,
    output reg [3:0] o_sw_btn,      // {lap, mode, clear, run_stop}
    output reg [3:0] o_wt_btn,      // {D, U, L, R}
    output reg       sr04_start,    // sr04 start
    output reg       dht11_start,   // dht11 시작 신호 전달
    output           sender_start,  // 샌더 신호 전달
    output           result_valid,
    output           o_sw_dth,      // 0 : temperature, 1 : humidity
    output     [1:0] displaymode,   // 현재 모드 FND,샌더 전달용
    output           o_us_tick
);
    tick_gen_us U_TICK_GEN_US (
        .clk    (clk),
        .rst    (rst),
        .us_tick(o_us_tick)
    );

    parameter [1:0] STOPWATCH = 0, WATCH = 1, SR04 = 2, DHT11 = 3;

    reg [1:0] c_state, n_state;
    reg  [1:0] sw_reg;  // sw 이전 값
    wire       sw_change = (sw != sw_reg);  // sw 바뀐 순간만 1

    reg send_reg, send_next;
    reg valid_reg, valid_next;
    // uart r,c,u,l 입력 후 결과 송신 요청
    // 1클록 늦춰서 송신 -> stopwatch clear 등 값 반영 후 전송
    reg btn_req, btn_req_reg;

    assign sender_start = send_reg & sender_ready;
    assign result_valid = valid_reg;
    assign displaymode  = c_state;
    assign o_sw_dth     = sw_dth;

    always @(posedge clk, posedge rst) begin
        if (rst) begin
            c_state      <= STOPWATCH;
            sw_reg       <= 2'b00;
            send_reg <= 1'b0;
            valid_reg    <= 1'b0;
            btn_req_reg  <= 1'b0;
        end else begin
            c_state      <= n_state;
            sw_reg       <= sw;
            send_reg <= send_next;
            valid_reg    <= valid_next;
            btn_req_reg  <= btn_req;
        end
    end

    always @(*) begin
        n_state       = c_state;
        o_sw_btn      = 4'b0000;
        o_wt_btn      = 4'b0000;
        sr04_start    = 1'b0;
        dht11_start   = 1'b0;
        send_next = send_reg;
        valid_next    = valid_reg;
        btn_req       = 1'b0;
        if (sender_start) begin
            send_next = 1'b0;
        end
        if (btn_req_reg) begin  // uart r,c,u,l 다음 클록에 결과 송신
            send_next  = 1'b1;
            valid_next = 1'b1;
        end
        case (c_state)
            STOPWATCH: begin
                if (btnR | uart_R) begin
                    o_sw_btn[0] = 1'b1;
                end else if (btnL | uart_L) begin
                    o_sw_btn[1] = 1'b1;
                end else if (btnU | uart_U) begin
                    o_sw_btn[2] = 1'b1;
                end else if (btnD | uart_D) begin
                    o_sw_btn[3] = 1'b1;
                end
                if (uart_R | uart_L | uart_U | uart_D) begin
                    btn_req = 1'b1;
                end
                if ((sw_change && sw == 2'b00) | uart_0) begin
                    n_state = STOPWATCH;
                    if (uart_0) begin
                        send_next = 1'b1;
                        valid_next    = 1'b1;
                    end
                end else if ((sw_change && sw == 2'b01) | uart_1) begin
                    n_state = WATCH;
                    if (uart_1) begin
                        send_next = 1'b1;
                        valid_next    = 1'b1;
                    end
                end else if ((sw_change && sw == 2'b10) | uart_2) begin
                    n_state = SR04;
                    sr04_start = 1'b1;
                end else if ((sw_change && sw == 2'b11) | uart_3) begin
                    n_state = DHT11;
                    dht11_start = 1'b1;
                end
            end

            WATCH: begin
                if (btnR | uart_R) begin
                    o_wt_btn[0] = 1'b1;
                end else if (btnL | uart_L) begin
                    o_wt_btn[1] = 1'b1;
                end else if (btnU | uart_U) begin
                    o_wt_btn[2] = 1'b1;
                end else if (btnD | uart_D) begin
                    o_wt_btn[3] = 1'b1;
                end
                if (uart_R | uart_L | uart_U | uart_D) begin
                    btn_req = 1'b1;
                end
                if ((sw_change && sw == 2'b00) | uart_0) begin
                    n_state = STOPWATCH;
                    if (uart_0) begin
                        send_next = 1'b1;
                        valid_next    = 1'b1;
                    end
                end else if ((sw_change && sw == 2'b01) | uart_1) begin
                    n_state = WATCH;
                    if (uart_1) begin
                        send_next = 1'b1;
                        valid_next    = 1'b1;
                    end
                end else if ((sw_change && sw == 2'b10) | uart_2) begin
                    n_state = SR04;
                    sr04_start = 1'b1;
                end else if ((sw_change && sw == 2'b11) | uart_3) begin
                    n_state = DHT11;
                    dht11_start = 1'b1;
                end
            end

            SR04: begin
                if (sr04_done | sr04_timeout) begin
                    send_next = 1'b1;
                    valid_next    = ~sr04_timeout;
                end
                if ((sw_change && sw == 2'b00) | uart_0) begin
                    n_state = STOPWATCH;
                    if (uart_0) begin
                        send_next = 1'b1;
                        valid_next    = 1'b1;
                    end
                end else if ((sw_change && sw == 2'b01) | uart_1) begin
                    n_state = WATCH;
                    if (uart_1) begin
                        send_next = 1'b1;
                        valid_next    = 1'b1;
                    end
                end else if ((sw_change && sw == 2'b10) | uart_2) begin
                    n_state = SR04;
                    sr04_start = 1'b1;
                end else if ((sw_change && sw == 2'b11) | uart_3) begin
                    n_state = DHT11;
                    dht11_start = 1'b1;
                end
            end

            DHT11: begin
                if (dht11_done) begin
                    send_next = 1'b1;
                    valid_next    = dht11_valid;
                end
                if ((sw_change && sw == 2'b00) | uart_0) begin
                    n_state = STOPWATCH;
                    if (uart_0) begin
                        send_next = 1'b1;
                        valid_next    = 1'b1;
                    end
                end else if ((sw_change && sw == 2'b01) | uart_1) begin
                    n_state = WATCH;
                    if (uart_1) begin
                        send_next = 1'b1;
                        valid_next    = 1'b1;
                    end
                end else if ((sw_change && sw == 2'b10) | uart_2) begin
                    n_state = SR04;
                    sr04_start = 1'b1;
                end else if ((sw_change && sw == 2'b11) | uart_3) begin
                    n_state = DHT11;
                    dht11_start = 1'b1;
                end
            end
        endcase
    end
endmodule

module tick_gen_us (
    input clk,
    input rst,
    output reg us_tick
);
    parameter FREQ = 100_000_000 / 1_000_000;
    reg [$clog2(FREQ)-1:0] counter_reg;

    always @(posedge clk, posedge rst) begin
        if (rst) begin
            counter_reg <= 0;
            us_tick <= 0;
        end else begin
            counter_reg <= counter_reg + 1;

            if (counter_reg == (FREQ - 1)) begin
                counter_reg <= 0;
                us_tick     <= 1'b1;
            end else begin
                us_tick <= 1'b0;
            end
        end
    end
endmodule
