`timescale 1ns / 1ps

// Test Case 9 ~ 10 : UART + FIFO Loop Back 검증
module tb_hw_uart ();
    // 1 clock = 10ns, 9600 baud 1bit 길이
    parameter BAUD_BIT_PERIOD = (100_000_000 / 9600) * 10;

    reg clk, rst, rx;
    wire tx;

    integer i;
    integer t_done, t_tx;
    integer tc_fail[9:10];
    reg [7:0] send_data, recv_data;
    reg start_bit, stop_bit;

    uart_fifo_loopback DUT (
        .clk(clk),
        .rst(rst),
        .rx (rx),
        .tx (tx)
    );

    always #5 clk = ~clk;

    task check(input integer tc, input ok);
        begin
            if (ok !== 1'b1) begin
                tc_fail[tc] = tc_fail[tc] + 1;
                $display("%t : [Test Case %0d] fail", $time, tc);
            end
        end
    endtask

    // PC처럼 rx로 start(0) + data 8bit(LSB first) + stop(1)을 보낸다.
    task sender_uart(input [7:0] data);
        integer j;
        begin
            rx = 0;
            #(BAUD_BIT_PERIOD);
            for (j = 0; j < 8; j = j + 1) begin
                rx = data[j];
                #(BAUD_BIT_PERIOD);
            end
            rx = 1;
            #(BAUD_BIT_PERIOD);
        end
    endtask

    // tx에서 start bit를 감지한 뒤, 각 bit의 가운데에서 샘플링한다.
    task receive_uart(output [7:0] data, output sbit, output ebit);
        integer j;
        begin
            wait (~tx);
            #(BAUD_BIT_PERIOD / 2);
            sbit = tx;
            for (j = 0; j < 8; j = j + 1) begin
                #(BAUD_BIT_PERIOD);
                data[j] = tx;
            end
            #(BAUD_BIT_PERIOD);
            ebit = tx;
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        rx = 1;
        tc_fail[9] = 0;
        tc_fail[10] = 0;
        #10 rst = 0;
        #100;

        // ---------------------------------------------------------
        // Test Case 9 : rx = start(0) + 8'h24 + stop(1) -> tx = same data
        // ---------------------------------------------------------
        send_data = 8'h24;
        fork
            sender_uart(send_data);
            begin
                @(posedge DUT.w_rx_done);                       // stop bit 구간에서 rx_done = 1
                t_done = $time;
                check(9, DUT.w_rx_data === send_data);          // rx_data = 24
                wait (~tx);                                     // tx start bit
                t_tx = $time;
                check(9, (t_tx - t_done) === 40);               // rx_done 4 clk 뒤 (10ns x 4)
                receive_uart(recv_data, start_bit, stop_bit);
                check(9, start_bit === 1'b0);                   // start bit = 0
                check(9, recv_data === send_data);              // 같은 data 출력
                check(9, stop_bit === 1'b1);                    // stop bit = 1
            end
        join

        // ---------------------------------------------------------
        // Test Case 10 : Loop Back, random data 16 times -> tx data = rx data
        // ---------------------------------------------------------
        for (i = 0; i < 16; i = i + 1) begin
            send_data = $random;
            fork
                sender_uart(send_data);
                receive_uart(recv_data, start_bit, stop_bit);
            join
            check(10, start_bit === 1'b0 && stop_bit === 1'b1 && recv_data === send_data);
            if (recv_data === send_data) $display("%t : pass data = %h", $time, recv_data);
            else $display("%t : fail data = %h, expected = %h", $time, recv_data, send_data);
        end

        #1000;
        $display("*** UART LOOP BACK TEST RESULT ***");
        if (tc_fail[9] == 0) $display("Test Case 9 : PASS");
        else $display("Test Case 9 : FAIL (%0d)", tc_fail[9]);
        if (tc_fail[10] == 0) $display("Test Case 10 : PASS (16 / 16)");
        else $display("Test Case 10 : FAIL (%0d / 16)", tc_fail[10]);
        $finish;
    end
endmodule