`timescale 1ns / 1ps

// UART 단독 검증 (FIFO 없음) : baud_tick_gen + uart_tx + uart_rx
// Test Case 1 ~ 9
module tb_hw_uart ();
    // 9600 baud, 16배 oversampling b_tick
    parameter F_COUNT = 100_000_000 / (9600 * 16);  // 651 clk
    parameter TICK_PERIOD = F_COUNT * 10;  // 6,510ns
    parameter BAUD_BIT_PERIOD = TICK_PERIOD * 16;  // 104,160ns (1 bit)

    reg clk, rst, rx;
    reg tx_start_tb, loop_en;
    reg [7:0] tx_data_tb;
    wire b_tick, tx, tx_busy, rx_done;
    wire [7:0] rx_data;

    // loop_en = 1 : Loop Back (rx_done -> tx_start, rx_data -> tx_data)
    wire tx_start = loop_en ? rx_done : tx_start_tb;
    wire [7:0] tx_data = loop_en ? rx_data : tx_data_tb;

    baud_tick_gen U_BAUD_TICK_GEN (
        .clk   (clk),
        .rst   (rst),
        .b_tick(b_tick)
    );

    uart_tx U_UART_TX (
        .clk     (clk),
        .rst     (rst),
        .tx_start(tx_start),
        .tx_data (tx_data),
        .b_tick  (b_tick),
        .tx      (tx),
        .tx_busy (tx_busy)
    );

    uart_rx U_UART_RX (
        .clk    (clk),
        .rst    (rst),
        .b_tick (b_tick),
        .rx     (rx),
        .rx_data(rx_data),
        .rx_done(rx_done)
    );

    always #5 clk = ~clk;

    integer i, j;
    integer tc_fail[1:9];
    integer pass_count, fail_count;
    integer t0, t1, t_rst_off, t_rx_start, t_tx_start, t_tx_fall, t_busy_rise, t_busy_fall;
    reg [7:0] send_data, recv_data;
    reg start_bit, stop_bit;

    // rx_done 감시 : 횟수, 값, 시각, 폭
    integer rx_cnt = 0;
    integer t_last_done = 0;
    integer rx_done_width = 0;
    reg [7:0] rx_log[0:63];
    always @(posedge rx_done) begin
        rx_log[rx_cnt] = rx_data;
        rx_cnt = rx_cnt + 1;
        t_last_done = $time;
    end
    always @(negedge rx_done) rx_done_width = $time - t_last_done;

    // ok가 X인 경우도 fail로 처리한다. (비교는 ===)
    task check(input integer tc, input ok);
        begin
            if (ok !== 1'b1) begin
                tc_fail[tc] = tc_fail[tc] + 1;
                $display("%t : [Test Case %0d] fail", $time, tc);
            end
        end
    endtask

    task tc_begin(input integer tc);
        $display("%t : [Test Case %0d] start", $time, tc);
    endtask

    task tc_end(input integer tc);
        $display("%t : [Test Case %0d] end", $time, tc);
    endtask

    // PC처럼 rx로 start(0) + data 8bit(LSB first) + stop(1)을 보낸다.
    task sender_uart(input [7:0] data);
        integer k;
        begin
            t_rx_start = $time;
            rx = 0;
            #(BAUD_BIT_PERIOD);
            for (k = 0; k < 8; k = k + 1) begin
                rx = data[k];
                #(BAUD_BIT_PERIOD);
            end
            rx = 1;
            #(BAUD_BIT_PERIOD);
        end
    endtask

    // tx에서 start bit(0)를 감지하면 각 bit의 가운데에서 샘플링한다.
    task receive_uart(output [7:0] data, output sbit, output ebit);
        integer k;
        begin
            wait (~tx);
            t_tx_fall = $time;
            #(BAUD_BIT_PERIOD / 2);
            sbit = tx;
            for (k = 0; k < 8; k = k + 1) begin
                #(BAUD_BIT_PERIOD);
                data[k] = tx;
            end
            #(BAUD_BIT_PERIOD);
            ebit = tx;
        end
    endtask

    // tx_start를 1 clk 동안 1로 만든다.
    task start_tx(input [7:0] data);
        begin
            @(negedge clk);
            tx_data_tb = data;
            tx_start_tb = 1;
            t_tx_start = $time;
            @(negedge clk);
            tx_start_tb = 0;
        end
    endtask

    // Loop Back 1 byte : rx로 보내고 tx 출력을 받아서 비교한다.
    task loopback_byte(input integer tc, input [7:0] data);
        begin
            fork
                sender_uart(data);
                receive_uart(recv_data, start_bit, stop_bit);
            join
            check(tc, rx_log[rx_cnt-1] === data);  // rx_data
            check(tc, (t_tx_fall - t_last_done) === 20);  // rx_done 후 2 clk 뒤 tx = 0
            check(tc, start_bit === 1'b0 && stop_bit === 1'b1);
            check(tc, recv_data === data);
            if (recv_data === data) begin
                pass_count = pass_count + 1;
                $display("%t : pass  send = %h, rx_data = %h, tx data = %h", $time, data,
                         rx_log[rx_cnt-1], recv_data);
            end else begin
                fail_count = fail_count + 1;
                $display("%t : fail  send = %h, rx_data = %h, tx data = %h", $time, data,
                         rx_log[rx_cnt-1], recv_data);
            end
        end
    endtask

    initial begin
        $timeformat(-9, 0, " ns", 14);
        clk = 0;
        rst = 1;
        rx = 1;
        tx_start_tb = 0;
        tx_data_tb = 0;
        loop_en = 0;
        pass_count = 0;
        fail_count = 0;
        for (i = 1; i <= 9; i = i + 1) tc_fail[i] = 0;

        // ---------------------------------------------------------
        // Test Case 1 : rst = 1 -> Reset, tx = 1, tx_busy = 0
        // ---------------------------------------------------------
        tc_begin(1);
        @(negedge clk);
        @(negedge clk);
        check(1, tx === 1'b1 && tx_busy === 1'b0);
        check(1, rx_done === 1'b0 && rx_data === 8'h00 && b_tick === 1'b0);
        @(negedge clk);
        rst = 0;
        t_rst_off = $time;
        @(posedge b_tick);  // 첫 b_tick까지 기다린다.
        check(1, ($time - t_rst_off) < 2 * TICK_PERIOD);
        check(1, tx === 1'b1 && tx_busy === 1'b0 && rx_done === 1'b0);
        tc_end(1);

        // ---------------------------------------------------------
        // Test Case 2 : b_tick -> 9600 baud x 16 (651 clk 마다 1 clk 동안 1)
        // ---------------------------------------------------------
        tc_begin(2);
        @(posedge b_tick);
        t0 = $time;
        @(negedge b_tick);
        check(2, ($time - t0) === 10);  // b_tick 폭 = 1 clk
        @(posedge b_tick);
        t1 = $time;
        check(2, (t1 - t0) === TICK_PERIOD);  // 651 clk = 6,510ns
        repeat (15) @(posedge b_tick);
        check(2, ($time - t0) === BAUD_BIT_PERIOD);  // b_tick 16개 = 1 bit
        tc_end(2);

        // ---------------------------------------------------------
        // Test Case 3 : tx_start = 1, tx_data = 30 -> tx = start + data(LSB first) + stop
        // ---------------------------------------------------------
        tc_begin(3);
        start_tx(8'h30);
        receive_uart(recv_data, start_bit, stop_bit);
        check(3, (t_tx_fall - t_tx_start) === 15);  // 다음 clk 상승엣지에 tx = 0
        check(3, start_bit === 1'b0);
        check(3, recv_data === 8'h30);
        check(3, stop_bit === 1'b1);
        check(3, tx_busy === 1'b1);  // stop bit 중에는 busy
        wait (~tx_busy);
        check(3, tx === 1'b1);  // 전송 후 tx = 1, tx_busy = 0
        tc_end(3);

        // ---------------------------------------------------------
        // Test Case 4 : 전송 중 tx_start = 1 (tx_data = ff) -> Ignore
        // ---------------------------------------------------------
        #(2 * BAUD_BIT_PERIOD);
        tc_begin(4);
        start_tx(8'h30);
        fork
            receive_uart(recv_data, start_bit, stop_bit);
            begin
                #(3 * BAUD_BIT_PERIOD + BAUD_BIT_PERIOD / 2);  // data 구간 한가운데
                @(negedge clk);
                tx_data_tb = 8'hff;
                tx_start_tb = 1;
                @(negedge clk);
                tx_start_tb = 0;
            end
        join
        check(4, start_bit === 1'b0 && recv_data === 8'h30 && stop_bit === 1'b1);
        wait (~tx_busy);
        t0 = $time;
        #(3 * BAUD_BIT_PERIOD);  // 두 번째 frame이 나오는지 확인
        check(4, tx === 1'b1 && tx_busy === 1'b0);
        tc_end(4);

        // ---------------------------------------------------------
        // Test Case 5 : rx = start(0) + 8'h41 + stop(1) -> rx_done, rx_data = 41
        // ---------------------------------------------------------
        #(BAUD_BIT_PERIOD);
        tc_begin(5);
        rx_cnt = 0;
        sender_uart(8'h41);
        #(2 * BAUD_BIT_PERIOD);
        check(5, rx_cnt === 1);  // rx_done은 1번만
        check(5, rx_log[0] === 8'h41);
        check(5, rx_done_width === 10);  // 1 clk 펄스
        check(5, (t_last_done - t_rx_start) >= 9 * BAUD_BIT_PERIOD &&
                 (t_last_done - t_rx_start) <= 10 * BAUD_BIT_PERIOD);  // stop bit 구간
        check(5, rx_data === 8'h41);  // 다음 frame 전까지 rx_data 유지
        tc_end(5);

        // ---------------------------------------------------------
        // Test Case 6 : 연속 3 byte (48, 69, 21) -> rx_done 3번, 순서대로 수신
        // ---------------------------------------------------------
        tc_begin(6);
        rx_cnt = 0;
        sender_uart(8'h48);
        sender_uart(8'h69);
        sender_uart(8'h21);
        #(2 * BAUD_BIT_PERIOD);
        check(6, rx_cnt === 3);
        check(6, rx_log[0] === 8'h48 && rx_log[1] === 8'h69 && rx_log[2] === 8'h21);
        tc_end(6);

        // ---------------------------------------------------------
        // Test Case 7 : Loop Back 1 byte (4b)
        // ---------------------------------------------------------
        #(BAUD_BIT_PERIOD);
        loop_en = 1;
        tc_begin(7);
        loopback_byte(7, 8'h4b);
        tc_end(7);

        // ---------------------------------------------------------
        // Test Case 8 : Loop Back, 경계값 00, ff
        // ---------------------------------------------------------
        tc_begin(8);
        loopback_byte(8, 8'h00);
        loopback_byte(8, 8'hff);
        tc_end(8);

        // ---------------------------------------------------------
        // Test Case 9 : Loop Back, random data 16 times
        // ---------------------------------------------------------
        pass_count = 0;
        fail_count = 0;
        rx_cnt = 0;
        tc_begin(9);
        for (i = 0; i < 16; i = i + 1) begin
            send_data = $random;
            loopback_byte(9, send_data);
        end
        tc_end(9);

        #1000;
        $display("*** UART TEST RESULT ***");
        for (i = 1; i <= 9; i = i + 1) begin
            if (tc_fail[i] == 0) $display("Test Case %0d : PASS", i);
            else $display("Test Case %0d : FAIL (%0d)", i, tc_fail[i]);
        end
        $display("random loop back : Pass Count = %0d, Fail Count = %0d", pass_count, fail_count);
        $finish;
    end
endmodule